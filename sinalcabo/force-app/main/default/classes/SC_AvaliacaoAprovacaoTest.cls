@isTest
public class SC_AvaliacaoAprovacaoTest {

    // A classe e' publica e as fixtures sao publicas para o SC_PreverAprovacaoTest as reutilizar
    // (pool de utilizadores, opps, regras, autonomia total e ausencias) em vez de duplicar codigo
    // que ja custou a acertar contra a composicao real das orgs.
    public static Account acc;
    public static User owner;
    public static List<User> aprs;

    // ══════════════ POOL DE UTILIZADORES: a classe não aceita a composição da org ══════════════
    //
    // Escolher utilizadores por uma query solta ("o primeiro End User activo", "os três primeiros
    // utilizadores activos") faz o teste depender de quem existe na org, e isso parte de duas
    // maneiras opostas:
    //
    //  1. Numa org com poucos utilizadores de negócio, um SELECT sem filtro de licença devolve
    //     primeiro os utilizadores de plataforma (Automated Process, Platform Integration User,
    //     administradores sem role), nenhum deles um aprovador ou um dono de oportunidade legítimo.
    //  2. Numa org virgem, onde o perfil End User acabou de ser criado pelo deploy e ainda não tem
    //     titulares, a query não devolve linha nenhuma e rebenta com QueryException antes da
    //     primeira asserção, arrastando a classe toda.
    //
    // O pool resolve os dois casos: reutiliza utilizadores de negócio que sirvam e cria os que
    // faltarem. Reutilizar primeiro evita gastar licenças numa org já povoada; criar depois faz a
    // classe correr numa org sem ninguém. Criar ou escrever no User é DML a objecto de SETUP e
    // estes testes inserem Opportunity na mesma transacção, por isso a criação vai dentro de
    // System.runAs, como o darAutonomia e o darDelegado mais abaixo.
    //
    // Cada filtro do reaproveitamento paga um modo de falha concreto:
    //   UserType Standard + licença Salesforce  fora os de plataforma, integração e Identity.
    //   perfil End User                         o mesmo perfil do owner e dos titulares, e o único
    //                                           que se pode criar em qualquer org (vem no source
    //                                           do projecto).
    //   DelegatedApproverId = null              um titular com substituto declarado na org invalida
    //                                           as premissas dos testes de ausência.
    //   sem o PS SC_Autonomia_Total             um dono isento devolve origem 'AutonomiaTotal' onde
    //                                           o teste espera 'Regra'.
    private static List<User> pool;
    private static Id perfilNegocioId;
    private static Integer sequencia = 0;

    public static void setup() {
        // Os utilizadores primeiro: garante que o pool existe antes de haver DML a dados nesta
        // transacção. A criação está dentro de System.runAs, portanto a ordem não dá MIXED_DML,
        // mas resolver aqui mantém o setup legível.
        owner = doPool(0);
        aprs = new List<User>{ doPool(1), doPool(2), doPool(3) };
        acc = new Account(Name = 'Aval Test'); insert acc;
    }

    public static User doPool(Integer indice) {
        if (pool == null) {
            pool = new List<User>();
            Set<Id> isentos = new Set<Id>();
            for (PermissionSetAssignment psa : [SELECT AssigneeId FROM PermissionSetAssignment
                                                WHERE PermissionSet.Name = 'SC_Autonomia_Total']) {
                isentos.add(psa.AssigneeId);
            }
            for (User u : [SELECT Id, Name FROM User
                           WHERE IsActive = true AND UserType = 'Standard'
                             AND Profile.Name = 'End User'
                             AND Profile.UserLicense.Name = 'Salesforce'
                             AND DelegatedApproverId = null
                           ORDER BY Name]) {
                if (!isentos.contains(u.Id)) pool.add(u);
            }
        }
        if (pool.size() <= indice) pool.addAll(criarUtilizadores(indice + 1 - pool.size(), true));
        return pool[indice];
    }

    /**
     * Cria utilizadores de negócio para este teste, num só DML e dentro de System.runAs.
     *
     * NB LanguageLocaleKey: vai em 'en_US' e não em 'pt_PT' porque a língua tem de estar activa na
     * org e não se pode contar com isso (quando não está, a inserção falha com
     * INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST no LanguageLocaleKey). A língua do utilizador não
     * muda nada do que aqui se testa.
     *
     * Sem role, de propósito: um utilizador sem role e sem share não vê as oportunidades dos
     * outros com o OWD em Private, que é o que os testes de substituição precisam de poder provar.
     */
    private static List<User> criarUtilizadores(Integer quantos, Boolean activos) {
        List<User> novos = new List<User>();
        for (Integer i = 0; i < quantos; i++) {
            sequencia++;
            String marca = String.valueOf(DateTime.now().getTime()) + 'x' + sequencia;
            novos.add(new User(
                FirstName = 'Teste', LastName = 'Aprovacao ' + sequencia,
                Alias = 'ta' + sequencia,                 // o Alias tem um tecto de 8 caracteres
                Username = 'sc.aval.' + marca + '@sinalcabo.test.invalid',
                Email = 'sc.aval.' + marca + '@example.invalid',
                ProfileId = perfilNegocio(), IsActive = activos,
                TimeZoneSidKey = 'Europe/Lisbon', LocaleSidKey = 'pt_PT',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) { insert novos; }
        return novos;
    }

    private static Id perfilNegocio() {
        if (perfilNegocioId == null) {
            List<Profile> ps = [SELECT Id FROM Profile WHERE Name = 'End User' LIMIT 1];
            System.assertEquals(1, ps.size(),
                'o perfil "End User" vem no source do projecto e tem de existir na org para o '
                + 'teste criar os utilizadores de que precisa');
            perfilNegocioId = ps[0].Id;
        }
        return perfilNegocioId;
    }

    // Opp com margem controlada: Custo = Amount * (1 - margem/100).
    public static Opportunity opp(Decimal amount, Decimal custo, String tipo) {
        Opportunity o = new Opportunity(
            Name = 'Aval ' + tipo + ' ' + amount,
            StageName = 'Aprovação Interna',
            CloseDate = Date.today().addMonths(2),
            AccountId = acc.Id, OwnerId = owner.Id,
            Empresa_Lider__c = 'Sinalcabo',
            Amount = amount, Custo_Estimado__c = custo,
            Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial', Tipo_Negocio__c = tipo
        );
        insert o; return o;
    }

    // Variante com Direccao/Area explicitas (para o caso de multiplas areas no mesmo Tipo).
    public static Opportunity oppArea(Decimal amount, Decimal custo, String tipo, String direccao, String area) {
        Opportunity o = new Opportunity(
            Name = 'Aval ' + tipo + ' ' + area + ' ' + amount,
            StageName = 'Aprovação Interna',
            CloseDate = Date.today().addMonths(2),
            AccountId = acc.Id, OwnerId = owner.Id,
            Empresa_Lider__c = 'Sinalcabo',
            Amount = amount, Custo_Estimado__c = custo,
            Direccao_Negocio__c = direccao, Area_Negocio__c = area, Tipo_Negocio__c = tipo
        );
        insert o; return o;
    }

    // Regra com os tres tectos de valor, tres pisos de margem e ate tres aprovadores.
    public static Regra_Aprovacao__c regra(String tipo,
            Decimal vN0, Decimal mN0, Decimal vN1, Decimal mN1, Decimal vN2, Decimal mN2,
            String cond, Id apr1, Id apr2, Id apr3) {
        return new Regra_Aprovacao__c(
            Name = 'R ' + tipo, Colaborador__c = owner.Id,
            Direccao__c = 'IT', Area__c = 'Gestão Comercial', Tipo_Negocio__c = tipo,
            Valor_N0__c = vN0, Margem_Min_N0__c = mN0,
            Valor_N1__c = vN1, Margem_Min_N1__c = mN1,
            Valor_N2__c = vN2, Margem_Min_N2__c = mN2,
            Condicao__c = cond,
            Aprovador_N1__c = apr1, Aprovador_N2__c = apr2, Aprovador_N3__c = apr3,
            Activa__c = true, Chave__c = owner.Id + '|' + tipo
        );
    }

    public static SC_AvaliacaoAprovacao.Result run(Id oppId) {
        SC_AvaliacaoAprovacao.Request r = new SC_AvaliacaoAprovacao.Request();
        r.opportunityId = oppId;
        return SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{ r })[0];
    }

    public static User dir()  { return aprs[0]; }
    public static User pvd()  { return aprs[1]; }
    public static User ter()  { return aprs[2]; }

    // ── Canonico da folha (ADR-011 3.1): N0 50k / margem 16, proposta 60k / 20%. ──
    // Nos quatro criterios: OU e So Valor escalam a N1; E e So Margem ficam autonomos.
    @isTest static void canonico_60k_20pct_quatro_criterios() {
        setup(); User d = dir();
        insert regra('Box Moving',      50000, 16, null, null, null, null, 'Valor OU Margem', d.Id, d.Id, null);
        insert regra('Networking',      50000, 16, null, null, null, null, 'Só Valor',        d.Id, d.Id, null);
        insert regra('Workplace',       50000, 16, null, null, null, null, 'Valor E Margem',  d.Id, d.Id, null);
        insert regra('Hybrid IT',       50000, 16, null, null, null, null, 'Só Margem',       d.Id, d.Id, null);
        Test.startTest();
        SC_AvaliacaoAprovacao.Result ou = run(opp(60000, 48000, 'Box Moving').Id);   // 20% margem
        SC_AvaliacaoAprovacao.Result sv = run(opp(60000, 48000, 'Networking').Id);
        SC_AvaliacaoAprovacao.Result em = run(opp(60000, 48000, 'Workplace').Id);
        SC_AvaliacaoAprovacao.Result sm = run(opp(60000, 48000, 'Hybrid IT').Id);
        Test.stopTest();
        System.assertEquals(true,  ou.requerAprovacao, 'OU: valor fura o tecto -> escala (N1).');
        System.assertEquals(false, ou.requerN2, 'OU: so N1.');
        System.assertEquals(true,  sv.requerAprovacao, 'So Valor: valor fura -> N1.');
        System.assertEquals(false, em.requerAprovacao, 'E: valor fura mas margem boa -> autonomo.');
        System.assertEquals(false, sm.requerAprovacao, 'So Margem: margem boa -> autonomo.');
    }

    // ── Default de criterio nulo = "Valor OU Margem" (ADR-011, corrige o default). ──
    @isTest static void default_nulo_e_ou() {
        setup(); User d = dir();
        insert regra('Cibersegurança', 50000, 16, null, null, null, null, null, d.Id, d.Id, null); // Condicao nula
        Test.startTest();
        SC_AvaliacaoAprovacao.Result res = run(opp(60000, 48000, 'Cibersegurança').Id); // 60k/20%
        Test.stopTest();
        System.assertEquals(true, res.requerAprovacao, 'Condicao nula tratada como OU -> valor fura -> escala.');
        System.assertEquals(false, res.requerN2);
    }

    // ── 500 EUR / 12% ao nivel MAXIMO pela margem (ADR-011 1.2, o caso do probe). ──
    // Tectos 100k/500k/1M, margens 20/18/15, OU. Margem 12% fura os 3 pisos -> nivel 3.
    @isTest static void nivel_maximo_pela_margem_N3() {
        setup(); User d = dir(); User p = pvd(); User terceiro = ter();
        insert regra('Workplace', 100000, 20, 500000, 18, 1000000, 15, 'Valor OU Margem', d.Id, p.Id, terceiro.Id);
        Test.startTest();
        SC_AvaliacaoAprovacao.Result res = run(opp(500, 440, 'Workplace').Id); // margem 12%
        Test.stopTest();
        System.assertEquals(true, res.requerAprovacao, 'Margem 12% abaixo de todos os pisos -> requer aprovacao.');
        System.assertEquals(true, res.requerN2, 'Nivel maximo -> N2.');
        System.assertEquals(true, res.requerN3, 'Com 3 aprovadores, nivel maximo chega a N3.');
        System.assertEquals(d.Id, res.aprovadorN1);
        System.assertEquals(p.Id, res.aprovadorN2);
        System.assertEquals(terceiro.Id, res.aprovadorN3);
    }

    // ── Clamp: nivel exigido 3 mas so 2 aprovadores configurados -> fica em N2. ──
    @isTest static void clamp_sem_terceiro_aprovador() {
        setup(); User d = dir(); User p = pvd();
        insert regra('Seguranças & Proteção Eletrónica', 100000, 20, 500000, 18, 1000000, 15,
                     'Valor OU Margem', d.Id, p.Id, null); // sem N3
        Test.startTest();
        SC_AvaliacaoAprovacao.Result res = run(opp(500, 440, 'Seguranças & Proteção Eletrónica').Id); // 12%
        Test.stopTest();
        System.assertEquals(true, res.requerN2, 'Nivel 3 exigido faz clamp a 2 (N2).');
        System.assertEquals(false, res.requerN3, 'Sem terceiro aprovador, nao chega a N3.');
        System.assertEquals(null, res.aprovadorN3);
    }

    // ── Negocio grande com boa margem em "Valor E Margem" passa autonomo (ADR-011 3.1). ──
    @isTest static void grande_boa_margem_criterio_E_autonomo() {
        setup(); User d = dir(); User p = pvd();
        insert regra('NOS Managed Services', 100000, 20, 500000, 18, 1000000, 15, 'Valor E Margem', d.Id, p.Id, null);
        Test.startTest();
        SC_AvaliacaoAprovacao.Result res = run(opp(1500000, 1125000, 'NOS Managed Services').Id); // 25% margem
        Test.stopTest();
        System.assertEquals(false, res.requerAprovacao,
            'E: valor fura os 3 tectos mas margem boa (min(3,0)=0) -> autonomo.');
    }

    // ── Fronteira de valor inclusiva (Só Valor): == tecto fica dentro; +1 fura. ──
    @isTest static void fronteira_valor_inclusiva() {
        setup(); User d = dir(); User p = pvd();
        insert regra('Outsourcing', 50000, null, 250000, null, 250000, null, 'Só Valor', d.Id, p.Id, null);
        Test.startTest();
        SC_AvaliacaoAprovacao.Result exato   = run(opp(50000, 30000, 'Outsourcing').Id);   // == N0 -> autonomo
        SC_AvaliacaoAprovacao.Result acimaN0 = run(opp(50001, 30000, 'Outsourcing').Id);   // > N0 -> N1
        SC_AvaliacaoAprovacao.Result exatoN1 = run(opp(250000, 150000, 'Outsourcing').Id); // == N1 -> N1
        Test.stopTest();
        System.assertEquals(false, exato.requerAprovacao, '50.000 == N0 fica dentro -> autonomo.');
        System.assertEquals(true,  acimaN0.requerAprovacao, '50.001 fura N0 -> N1.');
        System.assertEquals(false, acimaN0.requerN2, '50.001 so fura N0 -> N1.');
        System.assertEquals(true,  exatoN1.requerAprovacao, '250.000 == N1 fica dentro de N1 -> N1.');
        System.assertEquals(false, exatoN1.requerN2, '250.000 nao fura N1 -> nao escala a N2.');
    }

    // ── So Margem: so a margem decide, o valor e ignorado. ──
    @isTest static void so_margem_ignora_valor() {
        setup(); User d = dir(); User p = pvd();
        insert regra('Networking', null, 40, null, 20, null, 20, 'Só Margem', d.Id, p.Id, null);
        Test.startTest();
        SC_AvaliacaoAprovacao.Result alta  = run(opp(300000, 150000, 'Networking').Id); // 50% -> autonomo
        SC_AvaliacaoAprovacao.Result media = run(opp(300000, 210000, 'Networking').Id); // 30% -> N1
        SC_AvaliacaoAprovacao.Result baixa = run(opp(300000, 270000, 'Networking').Id); // 10% -> N2 (clamp)
        Test.stopTest();
        System.assertEquals(false, alta.requerAprovacao, 'Margem 50% >= 40% -> autonomo apesar de 300k.');
        System.assertEquals(true,  media.requerAprovacao, 'Margem 30% (<40, >=20) -> N1.');
        System.assertEquals(false, media.requerN2);
        System.assertEquals(true,  baixa.requerN2, 'Margem 10% fura os 3 pisos, clamp a 2 aprovadores -> N2.');
    }

    // ══════════════ FALLBACK POR CMT: o CMT guarda User Ids, e um User Id é de uma org ══════════════
    //
    // O SC_BU_Director__mdt guarda o director de cada BU num campo de texto com o User Id. Um User
    // Id só vale na org onde o utilizador foi criado, e os Ids que vão no source são os da sandbox
    // de build. Numa org nova (a build2, ou a produção no dia do go-live) não correspondem a
    // utilizador nenhum e o motor, ao gravar Aprovador_Alvo_N1__c com esse Id, falha o update com
    // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY, e vermelha três testes desta classe.
    //
    // Re-semear o CMT é passo manual do runbook e não se pode fazer de dentro de um teste (não há
    // DML a custom metadata em Apex), o que cria uma ordem impossível: o deploy corre os testes
    // antes de alguém poder semear os Ids da org de destino. Por isso os testes de fallback
    // separam duas coisas:
    //   sempre        as asserções que só dependem de metadados (as cinco empresas da picklist
    //                 terem registo no CMT com director preenchido), que é o que apanha uma sexta
    //                 empresa sem governação;
    //   condicional   o exercício da resolução em runtime, só para as BUs cujo director existe
    //                 nesta org. Se não existir nenhum, fica o aviso no log e o teste não bloqueia
    //                 o deploy por uma lacuna de configuração que só se corrige depois dele.
    //
    // Depois de semear o CMT numa org, confirmar no log destes testes que a resolução foi mesmo
    // exercitada e não saltada. É o passo que fecha o ciclo.
    public static final String AVISO_CMT =
        'SC_BU_Director__mdt: nenhum Director_User_Id__c corresponde a um utilizador desta org. '
        + 'O CMT ainda tem os Ids da org onde foi semeado e tem de ser re-semeado aqui (passo '
        + 'manual do runbook). Resolução do fallback NÃO exercitada em: ';

    // BU -> Director_User_Id__c tal como está no CMT, sem validar nada contra a org.
    private static Map<String, String> cmtDirectores() {
        Map<String, String> r = new Map<String, String>();
        for (SC_BU_Director__mdt d : SC_BU_Director__mdt.getAll().values()) {
            if (d.BU_Label__c != null && String.isNotBlank(d.Director_User_Id__c)) {
                r.put(d.BU_Label__c, d.Director_User_Id__c);
            }
        }
        return r;
    }

    // Dos anteriores, só os que são utilizadores DESTA org. O IsActive vem lido para o teste poder
    // continuar a exigir que o director do fallback esteja activo.
    public static Map<String, User> cmtDirectoresDaOrg() {
        Map<String, String> cmt = cmtDirectores();
        Map<String, Id> porBU = new Map<String, Id>();
        for (String bu : cmt.keySet()) {
            // um Id malformado no CMT nunca é utilizador desta org, e não é aqui que se denuncia
            try { porBU.put(bu, (Id) cmt.get(bu)); } catch (Exception e) {}
        }
        Map<Id, User> existentes = new Map<Id, User>([
            SELECT Id, Name, IsActive FROM User WHERE Id IN :porBU.values()]);
        Map<String, User> r = new Map<String, User>();
        for (String bu : porBU.keySet()) {
            User u = existentes.get(porBU.get(bu));
            if (u != null) r.put(bu, u);
        }
        return r;
    }

    // ── Fallback: sem regra para o par -> director da Empresa_Lider via CMT. ──
    @isTest static void fallback_sem_regra() {
        setup();
        if (!cmtDirectoresDaOrg().containsKey('Sinalcabo')) {
            System.debug(LoggingLevel.ERROR, AVISO_CMT + 'fallback_sem_regra');
            return;
        }
        Opportunity o = opp(150000, 100000, 'NOS Managed Services'); // sem regra para este tipo
        Test.startTest(); SC_AvaliacaoAprovacao.Result res = run(o.Id); Test.stopTest();
        System.assertEquals('Fallback', res.origem, 'Sem regra -> fallback CMT.');
        System.assertEquals(true, res.requerAprovacao);
        System.assertEquals(false, res.requerN2);
        System.assertEquals(false, res.requerN3, 'Fallback nao tem N3.');
        System.assertNotEquals(null, res.aprovadorN1, 'Fallback resolve o director da BU SinalCabo.');
    }

    // ── O fallback resolve pela Empresa_Lider contra o BU_Label do CMT, nas CINCO empresas. ──
    //
    // A chave do fallback e' a Empresa_Lider__c da oportunidade contra o BU_Label__c do
    // SC_BU_Director__mdt, e nao a direccao nem a area, que e' o que a nota de divida tecnica
    // dizia. Este teste congela isso: se alguem trocar a chave, quatro das cinco empresas passam
    // a resolver o director errado ou a cair em SemGovernacao, e o teste apanha-o.
    //
    // As empresas saem da propria picklist, portanto uma sexta empresa do grupo sem registo no
    // CMT faz falhar aqui e nao em producao, com uma proposta a ficar sem aprovador.
    //
    // O mapeamento (a Netlink e a Solarus não apontam ao utilizador que é desactivado depois do
    // go-live) fica preso pelas duas asserções nominais.
    @isTest static void fallback_cobre_as_cinco_empresas_do_grupo() {
        setup();

        Map<String, String> cmt = cmtDirectores();

        List<String> empresas = new List<String>();
        for (Schema.PicklistEntry pe : Opportunity.Empresa_Lider__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) empresas.add(pe.getValue());
        }
        System.assertEquals(5, empresas.size(),
            'O grupo tem cinco empresas na picklist Empresa_Lider__c: ' + empresas);

        // Cobertura da governação, sem depender de utilizador nenhum: é esta asserção que apanha
        // uma sexta empresa na picklist sem registo no CMT, e apanha-a em qualquer org, incluindo
        // uma onde o CMT ainda não foi semeado com os Ids locais.
        for (String empresa : empresas) {
            System.assertNotEquals(null, cmt.get(empresa),
                empresa + ': tem de existir um SC_BU_Director__mdt com BU_Label__c "' + empresa
                + '" e Director_User_Id__c preenchido, senão as propostas desta empresa sem regra '
                + 'na matriz caem em SemGovernacao e ficam sem aprovador.');
        }

        Map<String, User> directores = cmtDirectoresDaOrg();
        if (directores.isEmpty()) {
            System.debug(LoggingLevel.ERROR, AVISO_CMT + 'fallback_cobre_as_cinco_empresas_do_grupo');
            return;
        }
        if (directores.size() != cmt.size()) {
            System.debug(LoggingLevel.ERROR, AVISO_CMT + 'parte das empresas ('
                + (cmt.size() - directores.size()) + ' de ' + cmt.size() + ') em '
                + 'fallback_cobre_as_cinco_empresas_do_grupo');
        }

        Map<String, Id> resolvido = new Map<String, Id>();
        Test.startTest();
        for (String empresa : empresas) {
            if (!directores.containsKey(empresa)) continue; // director de outra org, ver o aviso
            Opportunity o = new Opportunity(
                Name = 'Fallback ' + empresa, StageName = 'Aprovação Interna',
                CloseDate = Date.today().addMonths(2), AccountId = acc.Id, OwnerId = owner.Id,
                Empresa_Lider__c = empresa, Amount = 150000, Custo_Estimado__c = 100000,
                Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial',
                Tipo_Negocio__c = 'NOS Managed Services'); // sem regra na matriz para este tipo
            insert o;
            SC_AvaliacaoAprovacao.Result res = run(o.Id);
            System.assertEquals('Fallback', res.origem,
                empresa + ': sem regra na matriz tem de cair no fallback do CMT, nao em SemGovernacao.');
            System.assertEquals(directores.get(empresa).Id, res.aprovadorN1,
                empresa + ': o aprovador tem de ser o Director_User_Id__c do registo cujo BU_Label__c e "'
                + empresa + '". A chave e a Empresa Lider, nao a direccao nem a area.');
            System.assertEquals(false, res.requerN2, empresa + ': o fallback e de um nivel so.');
            resolvido.put(empresa, res.aprovadorN1);
        }
        Test.stopTest();

        for (String empresa : resolvido.keySet()) {
            System.assertEquals(true, directores.get(empresa).IsActive,
                empresa + ': o director do fallback esta inactivo, as propostas dessa empresa ficam sem aprovador.');
        }

        // Congelamento nominal dos directores, para as empresas que esta org resolve.
        if (resolvido.containsKey('Netlink')) {
            System.assertEquals('Damião Costa', directores.get('Netlink').Name,
                'Netlink (registo TTC do CMT) tem de apontar ao Damião Costa.');
        }
        if (resolvido.containsKey('Solarus')) {
            System.assertEquals('António Serrano', directores.get('Solarus').Name,
                'Solarus (registo Energia do CMT) tem de apontar ao António Serrano.');
        }
    }

    // ── Aprovador admin por defeito (SemGovernacao) via Custom Setting. ──
    // O utilizador corrente serve de cobaia: o campo é texto e o teste só verifica que o valor
    // configurado é lido de volta, não precisa de um utilizador em particular nem de uma query.
    // (A org default real, se existir, não é visível dentro do teste: confirmado na build, onde o
    // SC_Aprovacao_Config__c está configurado e a primeira asserção continua a dar null.)
    @isTest static void aprovador_default_config() {
        Id u = UserInfo.getUserId();
        System.assertEquals(null, SC_AvaliacaoAprovacao.aprovadorDefault(), 'Sem Custom Setting, o default e null.');
        insert new SC_Aprovacao_Config__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Aprovador_Default_Id__c = u);
        System.assertEquals(u, SC_AvaliacaoAprovacao.aprovadorDefault(),
            'Com Custom Setting, devolve o aprovador admin por defeito.');
    }

    // ── Mais conservadora entre duas regras concorrentes (agora ate 3 niveis). ──
    //
    // Duas regras GRAVADAS para a mesma celula nao sao possiveis: o SC_Chave_Regra_Aprovacao
    // (before-save) compoe a Chave__c a partir de Colaborador+Tipo+Area, logo a segunda insercao
    // bate na unicidade do External Id (provado no teste seguinte). Por isso o desempate testa-se
    // com instancias em memoria e nao com registos gravados.
    //
    // O desempate continua a existir no motor como codigo de defesa (flow desactivado, duplicados
    // anteriores ao flow), por isso continua provado, agora por chamada directa com as duas regras
    // em memoria. A opp e' gravada porque o desempate le o Amount e a margem dela.
    @isTest static void mais_conservadora() {
        setup(); User d = dir(); User p = pvd();
        // r1 (1 nivel): So Valor, tecto N1 alto. r2 (2 niveis): So Valor, tectos baixos.
        Regra_Aprovacao__c r1 = regra('NOS Sob Orçamentação', null, null, 500000, null, null, null, 'Só Valor', d.Id, p.Id, null);
        Regra_Aprovacao__c r2 = regra('NOS Sob Orçamentação', 50000, null, 100000, null, 150000, null, 'Só Valor', d.Id, p.Id, null);
        // opp 200k: r1 -> 200k>500k?nao -> 0 niveis; r2 -> fura N0,N1,N2 (3), clamp 2 -> N2.
        Opportunity o = opp(200000, 100000, 'NOS Sob Orçamentação');

        Test.startTest();
        Regra_Aprovacao__c escolhida = SC_AvaliacaoAprovacao.escolherMaisConservadora(
            new List<Regra_Aprovacao__c>{ r1, r2 }, o, o.Margem_Percentual__c);
        Test.stopTest();

        System.assertEquals(50000, escolhida.Valor_N0__c,
            'Escolhe a mais conservadora (2 niveis), que e a que tem tecto N0 de 50k.');
    }

    // ── Duas regras para a MESMA celula (Colaborador+Tipo+Area) sao travadas pela Chave. ──
    // Consequencia directa do SC_Chave_Regra_Aprovacao: a chave deixou de ser texto livre do admin
    // e passa a ser a identidade da celula da matriz, logo a unicidade do External Id impede o
    // duplicado que antes se conseguia inventando dois sufixos diferentes. As chaves manuais abaixo
    // sao propositadamente distintas para provar que nao e' a chave escrita que trava, e o flow que
    // a reescreve nas duas para o mesmo valor.
    @isTest static void duplicado_na_mesma_celula_travado_pela_chave() {
        setup(); User d = dir(); User p = pvd();
        Regra_Aprovacao__c r1 = regra('NOS Sob Orçamentação', null, null, 500000, null, null, null, 'Só Valor', d.Id, p.Id, null);
        r1.Chave__c = 'manual-A';
        Regra_Aprovacao__c r2 = regra('NOS Sob Orçamentação', 50000, null, 100000, null, 150000, null, 'Só Valor', d.Id, p.Id, null);
        r2.Chave__c = 'manual-B';

        Test.startTest();
        List<Database.SaveResult> rs = Database.insert(new List<Regra_Aprovacao__c>{ r1, r2 }, false);
        Test.stopTest();

        System.assertEquals(true, rs[0].isSuccess(), 'A primeira regra da celula grava.');
        System.assertEquals(false, rs[1].isSuccess(),
            'A segunda regra da MESMA celula tem de ser rejeitada pela unicidade da Chave.');
        System.assertEquals(StatusCode.DUPLICATE_VALUE, rs[1].getErrors()[0].getStatusCode(),
            'A rejeicao vem da unicidade do External Id: ' + rs[1].getErrors());

        // E a chave gravada e a composta pelo flow, nao a 'manual-A' que o Apex escreveu.
        // O nome vem de query e nao de owner.Name: quando o pool CRIA o utilizador (org virgem), o
        // Name nao volta preenchido no objecto em memoria e a assercao comparava contra 'null|...'.
        String nomeOwner = [SELECT Name FROM User WHERE Id = :owner.Id].Name;
        System.assertEquals(nomeOwner + '|NOS Sob Orçamentação|Gestão Comercial',
            [SELECT Chave__c FROM Regra_Aprovacao__c WHERE Id = :rs[0].getId()].Chave__c,
            'O before-save compoe a chave a partir de Colaborador+Tipo+Area.');
    }

    // ── Solar em DUAS areas: mesmo Colaborador+Tipo, a Area desambigua o aprovador. ──
    // Caso real da matriz (direccao Energia): o Tipo "Solar" existe em "Energias Renováveis"
    // e em "Solarus" com aprovadores diferentes. As duas regras coexistem (o Chave__c inclui
    // a Area, era impossivel antes por unicidade), e o motor encaminha pela chave EXACTA da
    // area da opp. NB: Opportunity.Tipo_Negocio__c e' picklist DEPENDENTE de Area_Negocio__c
    // (cascata Direccao>Area>Tipo) e "Solar" so e' valido sob "Solarus"; nao ha nenhum Tipo
    // valido em duas areas, logo nao e' possivel inserir duas opps com o mesmo Tipo em duas
    // areas. Prova-se com UMA opp (Solarus, a unica combinacao valida) e uma guarda forte: a
    // regra da OUTRA area (Energias Renováveis) e' propositadamente MAIS conservadora, por isso
    // sem a Area na chave o escolherMaisConservadora encaminharia para o aprovador errado.
    @isTest static void solar_duas_areas_desambigua() {
        setup(); User aSolarus = dir(); User aRenovaveis = pvd(); User aRenovaveis2 = ter();
        // Regra da area da opp (Solarus): 1 nivel, 1 aprovador.
        Regra_Aprovacao__c rSol = new Regra_Aprovacao__c(
            Name = 'R Solar Solarus', Colaborador__c = owner.Id,
            Direccao__c = 'Energia', Area__c = 'Solarus', Tipo_Negocio__c = 'Solar',
            Valor_N0__c = 50000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = aSolarus.Id, Activa__c = true,
            Chave__c = owner.Id + '|Solar|Solarus');
        // Regra da OUTRA area (Energias Renováveis): 2 niveis (mais conservadora). Sem a Area na
        // chave, o escolherMaisConservadora escolheria esta (2>1) e daria aprovadorN1=aRenovaveis.
        Regra_Aprovacao__c rRen = new Regra_Aprovacao__c(
            Name = 'R Solar Renovaveis', Colaborador__c = owner.Id,
            Direccao__c = 'Energia', Area__c = 'Energias Renováveis', Tipo_Negocio__c = 'Solar',
            Valor_N0__c = 10000, Valor_N1__c = 20000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = aRenovaveis.Id, Aprovador_N2__c = aRenovaveis2.Id, Activa__c = true,
            Chave__c = owner.Id + '|Solar|Energias Renováveis');
        insert new List<Regra_Aprovacao__c>{ rSol, rRen };

        Test.startTest();
        SC_AvaliacaoAprovacao.Result sol = run(oppArea(100000, 60000, 'Solar', 'Energia', 'Solarus').Id);
        Test.stopTest();

        System.assertEquals(true, sol.requerAprovacao, 'Solar/Solarus (100k > N0 50k) -> requer N1.');
        System.assertEquals(aSolarus.Id, sol.aprovadorN1,
            'Encaminha pelo aprovador da area Solarus (chave exacta), nao pela regra mais conservadora de outra area.');
        System.assertEquals(false, sol.requerN2,
            'A regra de Solarus tem 1 nivel; a de Energias Renovaveis (2 niveis) NAO se aplica por ser de outra area.');
        System.assertNotEquals(aRenovaveis.Id, sol.aprovadorN1, 'A Area na chave desambigua: nao usa o aprovador da outra area.');
    }

    // ── A chave generica (regra sem Area) NAO E' POSSIVEL. ──
    // A Regra_Aprovacao__c tem a cascata Area -> Tipo, copiada da
    // Opportunity, para impedir que se grave uma regra com um par impossivel, que carregaria e
    // nunca corresponderia a nenhuma oportunidade (falha silenciosa: cai no fallback e a
    // proposta vai ao director da Empresa Lider sem erro nenhum).
    //
    // CONSEQUENCIA, provada empiricamente a 04/08: com a picklist dependente E restrita, a API
    // valida o par, e um Tipo sem Area controladora nao e' valido para valor nenhum. Ou seja a
    // cascata e a chave generica sao mutuamente exclusivas, por qualquer via (UI, API ou Apex).
    // As 87 regras da matriz tem todas area, portanto o caminho generico era codigo sem uso.
    //
    // Este teste passou a documentar a decisao: a insercao de uma regra sem Area e' REJEITADA.
    // O caminho generico em SC_AvaliacaoAprovacao (resolucao por chave generica) fica inalcançavel
    // e e' candidato a remocao, com ADR, sendo o Accountable o Tiago.
    @isTest static void area_vazia_rejeitada_pela_cascata() {
        setup(); User d = dir();
        Regra_Aprovacao__c rGen = new Regra_Aprovacao__c(
            Name = 'R Generica', Colaborador__c = owner.Id,
            Direccao__c = 'IT', Tipo_Negocio__c = 'Outsourcing',   // Area__c a null, de proposito
            Valor_N0__c = 50000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = d.Id, Activa__c = true,
            Chave__c = owner.Id + '|Outsourcing|');

        Test.startTest();
        Database.SaveResult sr = Database.insert(rGen, false);
        Test.stopTest();

        System.assertEquals(false, sr.isSuccess(),
            'Com a cascata Area -> Tipo activa, uma regra sem Area tem de ser rejeitada.');
        System.assert(String.valueOf(sr.getErrors()).contains('RESTRICTED_PICKLIST'),
            'A rejeicao vem da picklist dependente e restrita, nao de outra validacao: '
            + sr.getErrors());
    }

    @isTest static void vazio_e_nulo() {
        Test.startTest();
        List<SC_AvaliacaoAprovacao.Result> a = SC_AvaliacaoAprovacao.avaliar(null);
        List<SC_AvaliacaoAprovacao.Result> b = SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>());
        Test.stopTest();
        System.assertEquals(0, a.size());
        System.assertEquals(0, b.size());
    }

    // ═══════════════ FASE 7: autonomia total (PS SC_Autonomia_Total) ═══════════════

    /**
     * Atribuir um Permission Set é DML a um objecto de SETUP, e insere-se Opportunity na mesma
     * transacção, o que dá MIXED_DML_OPERATION. O System.runAs é o que permite os dois num teste.
     */
    public static void darAutonomia(Id userId) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SC_Autonomia_Total' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    @isTest static void autonomia_total_isenta_do_gate() {
        setup();
        darAutonomia(owner.Id);
        // Uma proposta que sem isenção exigiria a cadeia toda: 400k com margem de 5%.
        Opportunity o = opp(400000, 380000, 'Box Moving');
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals('AutonomiaTotal', r.origem,
            'a origem tem de dizer que foi isenção e não lacuna de configuração');
        System.assertEquals(false, r.requerAprovacao, 'não requer aprovação nenhuma');
        System.assertEquals(false, r.requerN2);
        System.assertEquals(false, r.requerN3);
        System.assertEquals(null, r.aprovadorN1, 'e não aponta aprovador nenhum');

        Opportunity gravada = [SELECT Requer_Aprovacao__c, Aprovador_Alvo_N1__c
                               FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(false, gravada.Requer_Aprovacao__c, 'e ficou gravado na oportunidade');
        System.assertEquals(null, gravada.Aprovador_Alvo_N1__c);
    }

    @isTest static void sem_autonomia_a_mesma_opp_exige_aprovacao() {
        // CONTROLO do teste anterior. Sem ele, um bug que devolvesse sempre "não requer" passava
        // pelos dois, e nada provava que a isenção é que estava a agir.
        setup();
        Opportunity o = opp(400000, 380000, 'Box Moving');
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals('Regra', r.origem, 'sem o PS, decide a matriz');
        System.assertEquals(true, r.requerAprovacao, 'e a mesma proposta exige aprovação');
        System.assertEquals(true, r.requerN3, 'a cadeia toda, porque passa os três tectos');
    }

    @isTest static void autonomia_total_ganha_a_regra_da_matriz() {
        // Prova que o guarda vem ANTES da resolução da chave. O owner tem regra na matriz para
        // esta área e este tipo; se o guarda viesse depois, a regra decidia e a isenção só
        // funcionaria por acidente, nos casos em que a matriz não tem linha.
        setup();
        darAutonomia(owner.Id);
        Opportunity o = oppArea(1000000, 950000, 'Box Moving', 'IT', 'Gestão Comercial');
        Regra_Aprovacao__c rg = regra('Box Moving', 1000, 90, 2000, 80, 3000, 70, 'Valor E Margem',
                                      dir().Id, pvd().Id, ter().Id);
        insert rg;

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals('AutonomiaTotal', r.origem,
            'a regra existe e casa com a opp, mas a isenção vem primeiro');
        System.assertEquals(false, r.requerAprovacao);
    }

    @isTest static void autonomia_total_limpa_aprovadores_pendurados() {
        // Uma opp avaliada ANTES de o owner ganhar autonomia fica com aprovadores gravados. Ao
        // reavaliar, esses campos têm de ser limpos, senão o ecrã mostra um aprovador alvo numa
        // oportunidade que já não precisa de aprovação.
        setup();
        Opportunity o = opp(400000, 380000, 'Box Moving');
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);
        run(o.Id);
        Opportunity antes = [SELECT Requer_Aprovacao__c, Aprovador_Alvo_N1__c
                             FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(true, antes.Requer_Aprovacao__c, 'premissa: começou a exigir aprovação');
        System.assertNotEquals(null, antes.Aprovador_Alvo_N1__c, 'e com aprovador gravado');

        darAutonomia(owner.Id);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals('AutonomiaTotal', r.origem);
        Opportunity depois = [SELECT Requer_Aprovacao__c, Aprovador_Alvo_N1__c, Aprovador_Alvo_N2__c,
                                    Aprovador_Alvo_N3__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(false, depois.Requer_Aprovacao__c);
        System.assertEquals(null, depois.Aprovador_Alvo_N1__c, 'o aprovador pendurado foi limpo');
        System.assertEquals(null, depois.Aprovador_Alvo_N2__c);
        System.assertEquals(null, depois.Aprovador_Alvo_N3__c);
    }

    @isTest static void autonomia_de_um_owner_nao_isenta_os_outros() {
        // A isenção é por utilizador. Num processamento em bulk com owners diferentes, só as opps
        // do isento passam sem aprovação, e é por isso que a verificação não pode usar o
        // FeatureManagement.checkPermission, que responde pelo utilizador corrente.
        //
        // O outro owner é um utilizador só dele (nem o dono isento nem nenhum dos três aprovadores)
        // e leva regra própria na matriz. Antes reutilizava-se aprs[0], que era ao mesmo tempo dono
        // e aprovador N1 da opp, e a opp caía no fallback por não haver regra para esse dono, o que
        // punha este teste a depender do CMT sem nada disso ser o que ele quer provar.
        setup();
        User outro = doPool(4);
        darAutonomia(owner.Id);

        Opportunity oIsenta = opp(400000, 380000, 'Box Moving');
        Opportunity oNormal = new Opportunity(
            Name = 'Aval outro owner', StageName = 'Aprovação Interna',
            CloseDate = Date.today().addMonths(2), AccountId = acc.Id, OwnerId = outro.Id,
            Empresa_Lider__c = 'Sinalcabo', Amount = 400000, Custo_Estimado__c = 380000,
            Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial',
            Tipo_Negocio__c = 'Box Moving');
        insert oNormal;

        Regra_Aprovacao__c rOutro = regra('Box Moving', 50000, 16, 150000, 12, 300000, 8,
                                          'Valor OU Margem', dir().Id, pvd().Id, ter().Id);
        rOutro.Colaborador__c = outro.Id;
        rOutro.Chave__c = outro.Id + '|Box Moving';
        insert rOutro;

        SC_AvaliacaoAprovacao.Request r1 = new SC_AvaliacaoAprovacao.Request();
        r1.opportunityId = oIsenta.Id;
        SC_AvaliacaoAprovacao.Request r2 = new SC_AvaliacaoAprovacao.Request();
        r2.opportunityId = oNormal.Id;

        Test.startTest();
        List<SC_AvaliacaoAprovacao.Result> res =
            SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{ r1, r2 });
        Test.stopTest();

        System.assertEquals('AutonomiaTotal', res[0].origem, 'a do owner isento passa');
        System.assertEquals(false, res[0].requerAprovacao);
        System.assertNotEquals('AutonomiaTotal', res[1].origem,
            'a do outro owner NÃO é isenta, mesmo na mesma corrida');
    }

    @isTest static void sem_owners_nao_gasta_query() {
        // O helper devolve vazio sem consultar nada quando não há owners a avaliar.
        Test.startTest();
        Set<Id> a = SC_AvaliacaoAprovacao.comAutonomiaTotal(null);
        Set<Id> b = SC_AvaliacaoAprovacao.comAutonomiaTotal(new Set<Id>());
        Integer queries = Limits.getQueries();
        Test.stopTest();
        System.assert(a.isEmpty());
        System.assert(b.isEmpty());
        System.assertEquals(0, queries, 'nenhuma query com conjunto vazio ou nulo');
    }

    // ═══════ APROVADOR AUSENTE: substituição por User.DelegatedApproverId ═══════

    /**
     * Escrever no User é DML a um objecto de SETUP e os testes daqui inserem Opportunity na mesma
     * transacção, o que dá MIXED_DML_OPERATION. O System.runAs é o que permite os dois, tal como
     * no darAutonomia acima.
     */
    public static Database.SaveResult darDelegado(Id titular, Id substituto) {
        Database.SaveResult sr;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            sr = Database.update(new User(Id = titular, DelegatedApproverId = substituto), false);
        }
        return sr;
    }

    /**
     * Titulares para os testes de ausência: utilizadores do pool, nunca o owner (que é o pool[0]).
     *
     * Estes testes gravam na ficha do titular, e é por isso que não se aceita o primeiro
     * utilizador que a org devolver: já aconteceu o update do Delegated Approver responder
     * "Cannot insert a user with this profile", o teste falhar e parecer defeito do motor. O pool
     * dá utilizadores de negócio, com licença Salesforce, em que a plataforma aceita escrever, e
     * garante que existem os que forem pedidos mesmo numa org sem ninguém.
     */
    public static List<User> titulares(Integer n) {
        List<User> r = new List<User>();
        for (Integer i = 1; i <= n; i++) r.add(doPool(i));
        return r;
    }

    private static Boolean temAcesso(Id userId, Id recId) {
        // NB: em UserRecordAccess só se pode SELECCIONAR RecordId, os Has*Access e o
        // MaxAccessLevel. O UserId serve de filtro e não pode vir na projecção, por isso é uma
        // query por utilizador e não uma query para todos.
        List<UserRecordAccess> ura = [SELECT RecordId, HasReadAccess FROM UserRecordAccess
                                      WHERE UserId = :userId AND RecordId = :recId];
        return !ura.isEmpty() && ura[0].HasReadAccess;
    }

    /**
     * O substituto destes testes: alguém que NÃO vê esta oportunidade.
     *
     * É a armadilha destes testes: escolher como substituto alguém que seja dono da conta, que
     * esteja acima do dono na hierarquia de roles, que tenha View All, ou que já esteja na
     * Opportunity Team, dá um falso positivo (o share "existe" porque o acesso já lá estava). Por
     * isso a escolha é feita a perguntar ao UserRecordAccess, e não por nome ou por perfil.
     *
     * Procura primeiro nos utilizadores de negócio da org e, se nenhum servir, cria um. Antes
     * devolvia null nesse caso e o teste morria na premissa com "Same value: null", o que na build2
     * parecia defeito do motor e era só a org: com o OWD da Opportunity em Public Read não existe
     * utilizador interno nenhum sem acesso, por mais que se procure. Um utilizador acabado de criar,
     * sem role e sem share, é o caso limpo, e se nem ele ficar sem acesso é o OWD que está aberto.
     */
    public static Id substitutoSemAcesso(Id oppId, Set<Id> excluir) {
        for (User u : pool) {
            if (excluir.contains(u.Id)) continue;
            if (!temAcesso(u.Id, oppId)) return u.Id;
        }
        return criarUtilizadores(1, true)[0].Id;
    }

    /**
     * Se dá para provar, nesta org, que foi o share que deu acesso ao substituto.
     *
     * Com o OWD da Opportunity em Private, que é o modelo do desenho, um utilizador novo não vê a
     * oportunidade de outro e o ganho de acesso é demonstrável. Numa org onde a Opportunity está em
     * Public Read (medido na build2, que ainda não tinha o OWD apertado), qualquer interno já a lê
     * antes de ser designado e a asserção de acesso não provaria nada. Nesse caso ficam as
     * asserções que valem em qualquer modelo: o alvo gravado e a linha de OpportunityShare.
     */
    private static final String AVISO_OWD =
        'O OWD da Opportunity nesta org não é Private (um utilizador novo já lê a oportunidade de '
        + 'outro), por isso o ganho de acesso pelo share não é demonstrável e essa asserção não '
        + 'correu. Apertar o OWD para Private antes de dar o ensaio por bom. Teste: ';

    // ── Titular ausente resolve para o substituto, E o substituto passa a ver a proposta. ──
    // É a razão de ser do desenho: pôr o substituto no Aprovador_Alvo_N1__c faz com que ele herde
    // o OpportunityShare que o partilharComAprovadores dá aos aprovadores alvo. A delegação nativa
    // sozinha não dá acesso nenhum, e sem acesso o delegado não vê sequer o item para aprovar.
    @isTest static void ausente_resolve_para_o_substituto_e_ganha_acesso() {
        setup();
        User titular = titulares(1)[0];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        Id substituto = substitutoSemAcesso(o.Id, new Set<Id>{ owner.Id, titular.Id });
        Boolean provaGanhoDeAcesso = !temAcesso(substituto, o.Id);
        if (!provaGanhoDeAcesso) {
            System.debug(LoggingLevel.ERROR, AVISO_OWD + 'ausente_resolve_para_o_substituto_e_ganha_acesso');
        }

        Database.SaveResult sr = darDelegado(titular.Id, substituto);
        System.assertEquals(true, sr.isSuccess(),
            'premissa do teste: a ausência tem de ficar gravada na ficha do titular: '
            + (sr.isSuccess() ? '' : String.valueOf(sr.getErrors())));
        System.assertEquals(substituto, [SELECT DelegatedApproverId FROM User
                                         WHERE Id = :titular.Id].DelegatedApproverId,
            'premissa do teste: e tem de ser legível de volta');
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(substituto, r.aprovadorN1,
            'o titular está ausente, o alvo tem de ser o substituto declarado na ficha dele');
        Opportunity g = [SELECT Aprovador_Alvo_N1__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(substituto, g.Aprovador_Alvo_N1__c,
            'e tem de ficar gravado no campo, que é o que o Approval Process lê');
        System.assertEquals(1, [SELECT COUNT() FROM OpportunityShare
                                WHERE OpportunityId = :o.Id AND UserOrGroupId = :substituto
                                  AND RowCause = 'Manual'],
            'o substituto tem de ter OpportunityShare manual, senão não consegue decidir');
        if (provaGanhoDeAcesso) {
            System.assertEquals(true, temAcesso(substituto, o.Id),
                'e o acesso tem de ser real, não só a linha de share');
        }
    }

    // ── Salto único: o substituto também ausente NÃO substitui. Fica o titular da matriz. ──
    // Sem esta guarda a resolução encadeava. E encaminhar para quem declarou estar ausente trocava
    // um bloqueio por outro, sem ganho nenhum.
    @isTest static void salto_unico_nao_segue_a_cadeia() {
        setup();
        List<User> t = titulares(3);
        User titular = t[0]; User intermedio = t[1]; User fim = t[2];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        darDelegado(intermedio.Id, fim.Id);       // o substituto também está ausente
        darDelegado(titular.Id, intermedio.Id);
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(titular.Id, r.aprovadorN1,
            'com o substituto também ausente não se substitui, fica o titular');
        System.assertNotEquals(fim.Id, r.aprovadorN1, 'e nunca se salta dois níveis na cadeia');
    }

    // ── Substituição mútua (A cobre B e B cobre A) não faz ciclo. ──
    @isTest static void substituicao_mutua_nao_faz_ciclo() {
        setup();
        List<User> t = titulares(2);
        User titular = t[0]; User outro = t[1];
        Opportunity o = opp(400000, 380000, 'Networking');
        darDelegado(titular.Id, outro.Id);
        darDelegado(outro.Id, titular.Id);
        insert regra('Networking', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(titular.Id, r.aprovadorN1,
            'ambos ausentes e a apontar um para o outro: a mesma guarda do salto único trava, '
            + 'e o motor devolve o titular em vez de rodar');
    }

    // ── Auto-referência não é substituição. ──
    @isTest static void auto_referencia_ignorada() {
        setup();
        User titular = titulares(1)[0];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        Database.SaveResult sr = darDelegado(titular.Id, titular.Id);
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(titular.Id, r.aprovadorN1,
            'apontado a si próprio não é substituição nenhuma, fica o titular (a plataforma '
            + 'aceitou a gravação=' + sr.isSuccess() + ')');
    }

    // ── Substituto igual ao dono da proposta é ignorado, senão a pessoa aprova-se a si própria. ──
    @isTest static void substituto_igual_ao_dono_ignorado() {
        setup();
        User titular = titulares(1)[0];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        darDelegado(titular.Id, owner.Id);
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertNotEquals(owner.Id, r.aprovadorN1,
            'o dono da proposta nunca pode ser o aprovador dela');
        System.assertEquals(titular.Id, r.aprovadorN1, 'fica o titular da matriz');
    }

    // ── Substituto INACTIVO é ignorado, e isto não é higiene, é o que evita rebentar o lote. ──
    // Medido na build: o lookup grava um utilizador inactivo, mas o Approval Process lê o
    // Aprovador_Alvo como VAZIO e a submissão automática falha com "This approval request requires
    // the next approver to be determined by the Aprovador Alvo N1 field. This value is empty",
    // o que faz falhar o próprio update da oportunidade e, com ele, todas as outras do lote.
    @isTest static void substituto_inactivo_ignorado() {
        setup();
        User titular = titulares(1)[0];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        Id inactivo = utilizadorInactivo();
        darDelegado(titular.Id, inactivo);
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(titular.Id, r.aprovadorN1,
            'um substituto inactivo é lido pelo Approval Process como campo vazio, por isso não '
            + 'se substitui: fica o titular e a proposta grava');
        System.assertEquals(true, [SELECT Requer_Aprovacao__c FROM Opportunity
                                   WHERE Id = :o.Id].Requer_Aprovacao__c,
            'e a oportunidade tem mesmo de ter sido gravada, que é o que a guarda protege');
    }

    /**
     * Um utilizador inactivo, criado inactivo por este teste.
     *
     * Antes procurava-se um inactivo na org e, se não houvesse (produção no dia 1), desactivava-se
     * um activo qualquer dos dez primeiros por nome. Isso dependia de quem a org devolvia, podia
     * cair num utilizador de plataforma onde a plataforma recusa escrever, e mexia na ficha de
     * alguém que nada tinha a ver com o teste. A inserção directa com IsActive = false é aceite
     * (verificado na build2) e não toca em ninguém.
     */
    private static Id utilizadorInactivo() {
        return criarUtilizadores(1, false)[0].Id;
    }

    // ── Controlo negativo: sem ausência declarada, nada muda. ──
    // Sem este teste, uma implementação que devolvesse sempre o titular passava em quatro dos
    // cinco casos acima e ninguém dava por isso.
    @isTest static void titular_presente_nao_muda_nada() {
        setup();
        List<User> t = titulares(2);
        User titular = t[0]; User segundo = t[1];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        System.assertEquals(null, [SELECT DelegatedApproverId FROM User
                                   WHERE Id = :titular.Id].DelegatedApproverId,
            'premissa: o titular não tem substituto declarado');
        insert regra('Box Moving', 50000, 16, 150000, 12, null, null, 'Só Valor',
                     titular.Id, segundo.Id, null);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals(titular.Id, r.aprovadorN1, 'N1 continua a ser quem a matriz diz');
        System.assertEquals(segundo.Id, r.aprovadorN2, 'e o N2 também');
        System.assertEquals(true, r.requerN2, 'a decisão da matriz não é tocada pela substituição');
    }

    // ── O fallback também substitui, e é onde isto mais faz falta. ──
    // Decisão: aplica-se, por coerência e porque o ponto de aplicação é um só. O director da
    // Empresa Líder é o aprovador de último recurso; se ele estiver ausente a proposta fica presa
    // exactamente como qualquer outra, e sem regra na matriz não há sequer backup configurado.
    @isTest static void fallback_com_director_ausente_substitui() {
        setup();
        System.assertNotEquals(null, cmtDirectores().get('Sinalcabo'),
            'premissa: a BU SinalCabo tem director no CMT');
        Map<String, User> directores = cmtDirectoresDaOrg();
        if (!directores.containsKey('Sinalcabo')) {
            System.debug(LoggingLevel.ERROR, AVISO_CMT + 'fallback_com_director_ausente_substitui');
            return;
        }
        Opportunity o = opp(150000, 100000, 'NOS Managed Services'); // sem regra: cai no fallback
        Id director = directores.get('Sinalcabo').Id;
        Id substituto = substitutoSemAcesso(o.Id, new Set<Id>{ owner.Id, director });
        darDelegado(director, substituto);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result r = run(o.Id);
        Test.stopTest();

        System.assertEquals('Fallback', r.origem, 'continua a ser o caminho do fallback');
        System.assertEquals(substituto, r.aprovadorN1,
            'o director da Empresa Líder ausente também é substituído');
        System.assertEquals(1, [SELECT COUNT() FROM OpportunityShare
                                WHERE OpportunityId = :o.Id AND UserOrGroupId = :substituto
                                  AND RowCause = 'Manual'],
            'e o substituto do fallback ganha o mesmo acesso');
    }

    // ── O helper não gasta query nenhuma com um conjunto vazio ou nulo. ──
    @isTest static void substitutos_sem_aprovadores_nao_gasta_query() {
        Test.startTest();
        Map<Id, Id> a = SC_AvaliacaoAprovacao.substitutosDeAusentes(null);
        Map<Id, Id> b = SC_AvaliacaoAprovacao.substitutosDeAusentes(new Set<Id>());
        Integer queries = Limits.getQueries();
        Test.stopTest();
        System.assert(a.isEmpty());
        System.assert(b.isEmpty());
        System.assertEquals(0, queries, 'nenhuma query com conjunto vazio ou nulo');
    }
}