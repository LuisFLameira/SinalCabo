/**
 * Testes da previsao do gate G2 (SC_PreverAprovacao e SC_AvaliacaoAprovacao.prever).
 *
 * O QUE ESTA CLASSE TEM DE PROVAR: que o que o ecra de confirmacao anuncia e' exactamente o que o
 * motor decide a seguir. Uma previsao que divergisse da decisao era pior do que nao existir, porque
 * o comercial confirmava a contar com um desfecho e recebia outro.
 *
 * Por isso o teste central e' de EQUIVALENCIA, e nao de valores esperados escritos a mao: para cada
 * cenario, chama-se prever (sem gravar) e depois avaliar (que grava) sobre a MESMA oportunidade e
 * afirma-se que o nivel, os tres booleanos, os tres aprovadores e a origem sao iguais. Se alguem
 * partir a decisao de um dos lados, e' aqui que se ve.
 *
 * FIXTURES: vem do SC_AvaliacaoAprovacaoTest (pool de utilizadores de negocio, opps, regras,
 * autonomia total e ausencias), que e' publico para isso. Duplicar aqui esse codigo era duplicar
 * as decisoes que ele tomou sobre a composicao real das orgs, e ficariam duas versoes a divergir.
 */
@isTest
private class SC_PreverAprovacaoTest {

    // ---------- fixtures reutilizadas ----------
    private static void setup() { SC_AvaliacaoAprovacaoTest.setup(); }
    private static User owner() { return SC_AvaliacaoAprovacaoTest.owner; }
    private static User dir()   { return SC_AvaliacaoAprovacaoTest.dir(); }
    private static User pvd()   { return SC_AvaliacaoAprovacaoTest.pvd(); }
    private static User ter()   { return SC_AvaliacaoAprovacaoTest.ter(); }

    private static Opportunity opp(Decimal amount, Decimal custo, String tipo) {
        return SC_AvaliacaoAprovacaoTest.opp(amount, custo, tipo);
    }

    private static Opportunity oppArea(Decimal amount, Decimal custo, String tipo, String direccao, String area) {
        return SC_AvaliacaoAprovacaoTest.oppArea(amount, custo, tipo, direccao, area);
    }

    private static Regra_Aprovacao__c regra(String tipo,
            Decimal vN0, Decimal mN0, Decimal vN1, Decimal mN1, Decimal vN2, Decimal mN2,
            String cond, Id apr1, Id apr2, Id apr3) {
        return SC_AvaliacaoAprovacaoTest.regra(tipo, vN0, mN0, vN1, mN1, vN2, mN2, cond, apr1, apr2, apr3);
    }

    // ---------- helpers da previsao ----------

    // A previsao do motor para uma opp gravada, com os valores que o ecra tem em maos. A copia em
    // memoria leva so a classificacao (que e' a chave da matriz) e os valores novos.
    private static SC_AvaliacaoAprovacao.Result previsaoMotor(Opportunity o, Decimal amount, Decimal custo) {
        return SC_AvaliacaoAprovacao.prever(new Opportunity(
            Id = o.Id, OwnerId = o.OwnerId, Tipo_Negocio__c = o.Tipo_Negocio__c,
            Area_Negocio__c = o.Area_Negocio__c, Empresa_Lider__c = o.Empresa_Lider__c,
            Amount = amount, Custo_Estimado__c = custo));
    }

    // A previsao pelo invocavel, que e' o que o flow chama.
    private static SC_PreverAprovacao.Result previsao(Id oppId, Decimal amount, Decimal custo) {
        SC_PreverAprovacao.Request p = new SC_PreverAprovacao.Request();
        p.opportunityId = oppId;
        p.amount = amount;
        p.custoEstimado = custo;
        return SC_PreverAprovacao.prever(new List<SC_PreverAprovacao.Request>{ p })[0];
    }

    private static Integer nivelDe(SC_AvaliacaoAprovacao.Result r) {
        if (r.requerN3 == true) return 3;
        if (r.requerN2 == true) return 2;
        return (r.requerAprovacao == true) ? 1 : 0;
    }

    /**
     * O nucleo da classe: prever e avaliar sobre a mesma oportunidade tem de dar o mesmo.
     *
     * A ordem importa. Primeiro preve-se (sem gravar) e so' depois se avalia, porque o avaliar
     * grava e submete; se fosse ao contrario, a previsao ficava a olhar para uma oportunidade que
     * ja tinha passado pelo gate.
     */
    private static void assertEquivalente(Opportunity o, Decimal amount, Decimal custo, String cenario) {
        SC_AvaliacaoAprovacao.Result p = previsaoMotor(o, amount, custo);
        SC_AvaliacaoAprovacao.Result a = SC_AvaliacaoAprovacaoTest.run(o.Id);

        System.assertEquals(nivelDe(a), nivelDe(p), cenario + ': o nivel previsto tem de ser o decidido.');
        System.assertEquals(a.requerAprovacao == true, p.requerAprovacao == true, cenario + ': requerAprovacao.');
        System.assertEquals(a.requerN2 == true, p.requerN2 == true, cenario + ': requerN2.');
        System.assertEquals(a.requerN3 == true, p.requerN3 == true, cenario + ': requerN3.');
        System.assertEquals(a.aprovadorN1, p.aprovadorN1, cenario + ': aprovador N1.');
        System.assertEquals(a.aprovadorN2, p.aprovadorN2, cenario + ': aprovador N2.');
        System.assertEquals(a.aprovadorN3, p.aprovadorN3, cenario + ': aprovador N3.');
        System.assertEquals(a.origem, p.origem, cenario + ': origem da decisao.');
    }

    // ══════════════ EQUIVALENCIA, cenario a cenario ══════════════

    // ── Canonico da folha nos quatro criterios: 60k com 20% de margem, tectos 50k/16. ──
    @isTest static void equivalencia_canonico_quatro_criterios() {
        setup(); User d = dir();
        insert new List<Regra_Aprovacao__c>{
            regra('Box Moving', 50000, 16, null, null, null, null, 'Valor OU Margem', d.Id, d.Id, null),
            regra('Networking', 50000, 16, null, null, null, null, 'Só Valor',        d.Id, d.Id, null),
            regra('Workplace',  50000, 16, null, null, null, null, 'Valor E Margem',  d.Id, d.Id, null),
            regra('Hybrid IT',  50000, 16, null, null, null, null, 'Só Margem',       d.Id, d.Id, null)
        };
        Opportunity ou = opp(60000, 48000, 'Box Moving');
        Opportunity sv = opp(60000, 48000, 'Networking');
        Opportunity em = opp(60000, 48000, 'Workplace');
        Opportunity sm = opp(60000, 48000, 'Hybrid IT');

        Test.startTest();
        assertEquivalente(ou, 60000, 48000, 'Valor OU Margem');
        assertEquivalente(sv, 60000, 48000, 'Só Valor');
        assertEquivalente(em, 60000, 48000, 'Valor E Margem');
        assertEquivalente(sm, 60000, 48000, 'Só Margem');
        Test.stopTest();

        // controlo: os quatro criterios nao dao todos o mesmo, senao a equivalencia era vazia
        System.assertEquals(1, nivelDe(previsaoMotor(ou, 60000, 48000)), 'OU: o valor fura -> N1.');
        System.assertEquals(0, nivelDe(previsaoMotor(em, 60000, 48000)), 'E: margem boa -> autonomo.');
    }

    // ── Condicao nula tratada como "Valor OU Margem", tambem na previsao. ──
    @isTest static void equivalencia_default_nulo() {
        setup(); User d = dir();
        insert regra('Cibersegurança', 50000, 16, null, null, null, null, null, d.Id, d.Id, null);
        Opportunity o = opp(60000, 48000, 'Cibersegurança');
        Test.startTest();
        assertEquivalente(o, 60000, 48000, 'condicao nula');
        Test.stopTest();
        System.assertEquals(1, nivelDe(previsaoMotor(o, 60000, 48000)), 'condicao nula = OU -> N1.');
    }

    // ── Nivel maximo pela margem (12% fura os tres pisos) com tres aprovadores. ──
    @isTest static void equivalencia_N3_pela_margem() {
        setup();
        insert regra('Workplace', 100000, 20, 500000, 18, 1000000, 15, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);
        Opportunity o = opp(500, 440, 'Workplace');
        Test.startTest();
        assertEquivalente(o, 500, 440, 'N3 pela margem');
        Test.stopTest();
        System.assertEquals(3, nivelDe(previsaoMotor(o, 500, 440)), 'margem 12% fura os 3 pisos -> N3.');
    }

    // ── Clamp: nivel 3 exigido, dois aprovadores configurados. ──
    @isTest static void equivalencia_clamp_sem_terceiro_aprovador() {
        setup();
        insert regra('Seguranças & Proteção Eletrónica', 100000, 20, 500000, 18, 1000000, 15,
                     'Valor OU Margem', dir().Id, pvd().Id, null);
        Opportunity o = opp(500, 440, 'Seguranças & Proteção Eletrónica');
        Test.startTest();
        assertEquivalente(o, 500, 440, 'clamp a dois aprovadores');
        Test.stopTest();
        SC_AvaliacaoAprovacao.Result p = previsaoMotor(o, 500, 440);
        System.assertEquals(2, nivelDe(p), 'sem terceiro aprovador, o clamp trava em N2.');
        System.assertEquals(null, p.aprovadorN3, 'e a previsao nao inventa um terceiro aprovador.');
    }

    // ── Fronteira de valor: == tecto fica dentro, +1 fura. As tres previsoes sobre a mesma opp. ──
    @isTest static void equivalencia_fronteira_valor() {
        setup();
        insert regra('Outsourcing', 50000, null, 250000, null, 250000, null, 'Só Valor',
                     dir().Id, pvd().Id, null);
        Opportunity exacto = opp(50000, 30000, 'Outsourcing');
        Opportunity acima  = opp(50001, 30000, 'Outsourcing');
        Test.startTest();
        assertEquivalente(exacto, 50000, 30000, 'Amount igual ao tecto N0');
        assertEquivalente(acima, 50001, 30000, 'Amount um euro acima do tecto N0');
        Test.stopTest();
        System.assertEquals(0, nivelDe(previsaoMotor(exacto, 50000, 30000)), '50.000 == N0 fica dentro.');
        System.assertEquals(1, nivelDe(previsaoMotor(exacto, 50001, 30000)),
            'e a previsao sobre a MESMA opp com um euro a mais ja escala, que e o que o ecra tem de mostrar.');
    }

    // ── Só Margem: o valor e' ignorado, os tres degraus. ──
    @isTest static void equivalencia_so_margem() {
        setup();
        insert regra('Networking', null, 40, null, 20, null, 20, 'Só Margem', dir().Id, pvd().Id, null);
        Opportunity alta  = opp(300000, 150000, 'Networking');
        Opportunity media = opp(300000, 210000, 'Networking');
        Opportunity baixa = opp(300000, 270000, 'Networking');
        Test.startTest();
        assertEquivalente(alta, 300000, 150000, 'margem 50%');
        assertEquivalente(media, 300000, 210000, 'margem 30%');
        assertEquivalente(baixa, 300000, 270000, 'margem 10%');
        Test.stopTest();
        System.assertEquals(0, nivelDe(previsaoMotor(alta, 300000, 150000)), '50% >= 40% -> autonomo.');
        System.assertEquals(1, nivelDe(previsaoMotor(media, 300000, 210000)), '30% -> N1.');
        System.assertEquals(2, nivelDe(previsaoMotor(baixa, 300000, 270000)), '10% fura os 3 pisos, clamp -> N2.');
    }

    // ── Sem regra: fallback pelo director da Empresa Lider, e a previsao mostra-o. ──
    // Guarda do CMT igual a do SC_AvaliacaoAprovacaoTest: numa org onde o SC_BU_Director ainda tem
    // os Ids de outra org, a resolucao nao e' exercitavel e o teste nao bloqueia o deploy.
    @isTest static void equivalencia_fallback_sem_regra() {
        setup();
        if (!SC_AvaliacaoAprovacaoTest.cmtDirectoresDaOrg().containsKey('Sinalcabo')) {
            System.debug(LoggingLevel.ERROR, SC_AvaliacaoAprovacaoTest.AVISO_CMT + 'equivalencia_fallback_sem_regra');
            return;
        }
        Opportunity o = opp(150000, 100000, 'NOS Managed Services'); // sem regra para este tipo
        Test.startTest();
        assertEquivalente(o, 150000, 100000, 'fallback sem regra');
        Test.stopTest();
        SC_AvaliacaoAprovacao.Result p = previsaoMotor(o, 150000, 100000);
        System.assertEquals('Fallback', p.origem, 'a previsao tem de assumir o fallback, nao esconde-lo.');
        System.assertNotEquals(null, p.aprovadorN1, 'e diz quem e o director que vai decidir.');
        System.assertEquals(null, p.autonomiaValor, 'sem regra nao ha autonomia a mostrar no ecra.');
    }

    // ── Solar em duas areas: a previsao encaminha pela area da opp, como a decisao. ──
    @isTest static void equivalencia_duas_areas_solar() {
        setup(); User aSolarus = dir(); User aRenovaveis = pvd(); User aRenovaveis2 = ter();
        Regra_Aprovacao__c rSol = new Regra_Aprovacao__c(
            Name = 'R Solar Solarus', Colaborador__c = owner().Id,
            Direccao__c = 'Energia', Area__c = 'Solarus', Tipo_Negocio__c = 'Solar',
            Valor_N0__c = 50000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = aSolarus.Id, Activa__c = true,
            Chave__c = owner().Id + '|Solar|Solarus');
        // a regra da OUTRA area e' mais conservadora: sem a area na chave, a previsao encaminhava
        // para o aprovador errado, e o teste apanha-o.
        Regra_Aprovacao__c rRen = new Regra_Aprovacao__c(
            Name = 'R Solar Renovaveis', Colaborador__c = owner().Id,
            Direccao__c = 'Energia', Area__c = 'Energias Renováveis', Tipo_Negocio__c = 'Solar',
            Valor_N0__c = 10000, Valor_N1__c = 20000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = aRenovaveis.Id, Aprovador_N2__c = aRenovaveis2.Id, Activa__c = true,
            Chave__c = owner().Id + '|Solar|Energias Renováveis');
        insert new List<Regra_Aprovacao__c>{ rSol, rRen };
        Opportunity o = oppArea(100000, 60000, 'Solar', 'Energia', 'Solarus');

        Test.startTest();
        assertEquivalente(o, 100000, 60000, 'Solar em Solarus');
        Test.stopTest();

        SC_AvaliacaoAprovacao.Result p = previsaoMotor(o, 100000, 60000);
        System.assertEquals(aSolarus.Id, p.aprovadorN1, 'a previsao usa a chave exacta da area da opp.');
        System.assertEquals(1, nivelDe(p), 'a regra de Solarus tem um nivel so.');
    }

    // ── Autonomia total: a isencao aparece na previsao, com a origem certa. ──
    @isTest static void equivalencia_autonomia_total() {
        setup();
        SC_AvaliacaoAprovacaoTest.darAutonomia(owner().Id);
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);
        Opportunity o = opp(400000, 380000, 'Box Moving'); // sem isencao exigiria a cadeia toda

        Test.startTest();
        assertEquivalente(o, 400000, 380000, 'autonomia total');
        Test.stopTest();

        SC_AvaliacaoAprovacao.Result p = previsaoMotor(o, 400000, 380000);
        System.assertEquals('AutonomiaTotal', p.origem,
            'a previsao tem de dizer isencao, e nao lacuna de configuracao.');
        System.assertEquals(0, nivelDe(p), 'e nivel 0, apesar de a regra da matriz pedir a cadeia toda.');
    }

    // ── Aprovador ausente: a previsao mostra o SUBSTITUTO, que e' quem vai receber o pedido. ──
    @isTest static void equivalencia_ausente_com_substituto() {
        setup();
        User titular = SC_AvaliacaoAprovacaoTest.titulares(1)[0];
        Opportunity o = opp(400000, 380000, 'Box Moving');
        Id substituto = SC_AvaliacaoAprovacaoTest.substitutoSemAcesso(
            o.Id, new Set<Id>{ owner().Id, titular.Id });
        Database.SaveResult sr = SC_AvaliacaoAprovacaoTest.darDelegado(titular.Id, substituto);
        System.assertEquals(true, sr.isSuccess(),
            'premissa: a ausencia tem de ficar gravada na ficha do titular: '
            + (sr.isSuccess() ? '' : String.valueOf(sr.getErrors())));
        insert regra('Box Moving', 50000, 16, null, null, null, null, 'Só Valor',
                     titular.Id, null, null);

        Test.startTest();
        assertEquivalente(o, 400000, 380000, 'aprovador ausente');
        Test.stopTest();

        System.assertEquals(substituto, previsaoMotor(o, 400000, 380000).aprovadorN1,
            'o ecra tem de mostrar o substituto, que e quem recebe o pedido, e nao o titular ausente.');
    }

    /**
     * Lacuna de configuracao: sem regra e sem director, a previsao mostra o aprovador por omissao.
     *
     * So' pela previsao, e nao por equivalencia com o avaliar: a Empresa_Lider__c e' obrigatoria no
     * campo, as cinco empresas da picklist tem todas registo no SC_BU_Director (garantido pelo
     * fallback_cobre_as_cinco_empresas_do_grupo), e por isso nao ha oportunidade GRAVAVEL que caia
     * em SemGovernacao nesta org. Uma opp em memoria sem Empresa Lider exercita o caminho, que
     * existe para a proposta nunca ficar sem alvo.
     */
    @isTest static void sem_governacao_cai_no_aprovador_por_omissao() {
        setup();
        insert new SC_Aprovacao_Config__c(SetupOwnerId = UserInfo.getOrganizationId(),
                                          Aprovador_Default_Id__c = dir().Id);
        Opportunity emMemoria = new Opportunity(
            OwnerId = owner().Id, Tipo_Negocio__c = 'NOS Managed Services',
            Area_Negocio__c = 'Gestão Comercial', Amount = 150000, Custo_Estimado__c = 100000);

        Test.startTest();
        SC_AvaliacaoAprovacao.Result p = SC_AvaliacaoAprovacao.prever(emMemoria);
        Test.stopTest();

        System.assertEquals('SemGovernacao', p.origem, 'sem regra e sem director da Empresa Lider.');
        System.assertEquals(true, p.requerAprovacao, 'e a proposta nao passa sozinha.');
        System.assertEquals(dir().Id, p.aprovadorN1, 'o alvo e o aprovador por omissao do Custom Setting.');
    }

    // ── O desempate de regras concorrentes ve a margem PREVISTA, e nao o campo gravado. ──
    // Duas regras para a mesma celula nao sao gravaveis (unicidade da Chave__c), por isso o
    // desempate exercita-se com regras em memoria, como no SC_AvaliacaoAprovacaoTest. O que este
    // teste acrescenta e' que a margem que decide o desempate e' a que vem por parametro: com 13%
    // manda a regra de valor, com 5% manda a de margem.
    @isTest static void desempate_usa_a_margem_prevista() {
        setup(); User d = dir(); User p = pvd();
        Regra_Aprovacao__c rMargem = regra('NOS Sob Orçamentação', null, 10, null, 8, null, null,
                                           'Só Margem', d.Id, p.Id, null);
        Regra_Aprovacao__c rValor  = regra('NOS Sob Orçamentação', 50000, null, null, null, null, null,
                                           'Só Valor', d.Id, null, null);
        Opportunity emMemoria = new Opportunity(
            OwnerId = owner().Id, Tipo_Negocio__c = 'NOS Sob Orçamentação',
            Area_Negocio__c = 'Gestão Comercial', Amount = 100000);
        List<Regra_Aprovacao__c> concorrentes = new List<Regra_Aprovacao__c>{ rMargem, rValor };

        Test.startTest();
        Regra_Aprovacao__c com13 = SC_AvaliacaoAprovacao.escolherMaisConservadora(
            concorrentes, emMemoria, SC_AvaliacaoAprovacao.margemDe(100000, 87000)); // 13,0%
        Regra_Aprovacao__c com5 = SC_AvaliacaoAprovacao.escolherMaisConservadora(
            concorrentes, emMemoria, SC_AvaliacaoAprovacao.margemDe(100000, 95000)); // 5,0%
        Test.stopTest();

        System.assertEquals(50000, com13.Valor_N0__c,
            'com 13% de margem nenhum piso e furado, manda a regra de valor (1 nivel).');
        System.assertEquals(10, com5.Margem_Min_N0__c,
            'com 5% a regra de margem exige 2 niveis e passa a ser a mais conservadora.');
    }

    // ══════════════ A MARGEM: a previsao tem de dar o mesmo que a formula grava ══════════════

    /**
     * margemDe replica o Margem_Percentual__c, incluindo o arredondamento a uma casa.
     *
     * E' a costura entre os dois lados: a previsao decide sobre a margem calculada em Apex e o
     * motor decide sobre a margem gravada pela formula. Se as duas divergirem numa casa decimal,
     * uma proposta na fronteira exacta de um piso e' anunciada como autonoma e escala (ou o
     * contrario). Os tres pares sao de arredondamento: 38,9952 -> 39,0; 21,875 -> 21,9;
     * 19,999998 -> 20,0.
     */
    @isTest static void margem_calculada_igual_a_margem_gravada() {
        setup();
        Opportunity a = opp(246.21, 150.20, 'Box Moving');
        Opportunity b = opp(396000, 309375, 'Networking');
        Opportunity c = opp(161338.76, 129071.01, 'Workplace');

        Test.startTest();
        Map<Id, Opportunity> gravadas = new Map<Id, Opportunity>([
            SELECT Id, Margem_Percentual__c FROM Opportunity WHERE Id IN :new List<Id>{ a.Id, b.Id, c.Id }]);
        Test.stopTest();

        System.assertEquals(39.0, SC_AvaliacaoAprovacao.margemDe(246.21, 150.20).setScale(1),
            '246,21 com custo 150,20 da 38,9952, que arredonda a 39,0.');
        System.assertEquals(21.9, SC_AvaliacaoAprovacao.margemDe(396000, 309375).setScale(1),
            '396.000 com custo 309.375 da 21,875, que arredonda a 21,9.');
        System.assertEquals(20.0, SC_AvaliacaoAprovacao.margemDe(161338.76, 129071.01).setScale(1),
            '161.338,76 com custo 129.071,01 da 19,999998, que arredonda a 20,0.');

        System.assertEquals(gravadas.get(a.Id).Margem_Percentual__c.setScale(1),
            SC_AvaliacaoAprovacao.margemDe(246.21, 150.20).setScale(1),
            'a margem calculada tem de ser a gravada pela formula (246,21 / 150,20).');
        System.assertEquals(gravadas.get(b.Id).Margem_Percentual__c.setScale(1),
            SC_AvaliacaoAprovacao.margemDe(396000, 309375).setScale(1),
            'a margem calculada tem de ser a gravada pela formula (396.000 / 309.375).');
        System.assertEquals(gravadas.get(c.Id).Margem_Percentual__c.setScale(1),
            SC_AvaliacaoAprovacao.margemDe(161338.76, 129071.01).setScale(1),
            'a margem calculada tem de ser a gravada pela formula (161.338,76 / 129.071,01).');

        // valores em falta e valor zero nao rebentam a previsao
        System.assertEquals(0, SC_AvaliacaoAprovacao.margemDe(null, null), 'sem valores, margem 0.');
        System.assertEquals(0, SC_AvaliacaoAprovacao.margemDe(0, 1000), 'valor zero, margem 0.');
        System.assertEquals(100, SC_AvaliacaoAprovacao.margemDe(1000, null).setScale(0),
            'custo em falta conta como zero, como o BlankAsZero da formula.');
    }

    // ── Fronteiras exactas na previsao: tecto de valor inclusivo, piso de margem cumprido. ──
    @isTest static void fronteiras_exactas_na_previsao() {
        setup();
        insert regra('Outsourcing', 50000, null, null, null, null, null, 'Só Valor', dir().Id, null, null);
        insert regra('Hybrid IT', null, 20, null, null, null, null, 'Só Margem', dir().Id, null, null);
        Opportunity oValor  = opp(10000, 5000, 'Outsourcing');
        Opportunity oMargem = opp(10000, 5000, 'Hybrid IT');

        Test.startTest();
        SC_PreverAprovacao.Result tectoExacto = previsao(oValor.Id, 50000, 30000);
        SC_PreverAprovacao.Result tectoFurado = previsao(oValor.Id, 50001, 30000);
        SC_PreverAprovacao.Result pisoExacto  = previsao(oMargem.Id, 161338.76, 129071.01); // 20,0%
        SC_PreverAprovacao.Result pisoFurado  = previsao(oMargem.Id, 100000, 80100);        // 19,9%
        Test.stopTest();

        System.assertEquals(0, tectoExacto.nivel, 'Amount igual ao tecto N0 fica dentro da autonomia.');
        System.assertEquals(1, tectoFurado.nivel, 'um euro acima do tecto N0 escala.');
        System.assertEquals(0, pisoExacto.nivel, 'margem igual ao piso N0 cumpre (20,0 >= 20).');
        System.assertEquals(20.0, pisoExacto.margemCalculada.setScale(1), 'e a margem mostrada e 20,0.');
        System.assertEquals(1, pisoFurado.nivel, 'uma decima abaixo do piso N0 escala.');
        System.assertEquals(19.9, pisoFurado.margemCalculada.setScale(1), 'com a margem a 19,9.');
    }

    // ══════════════ O INVOCAVEL: o que o ecra le' ══════════════

    /**
     * Prever nao grava, nao partilha e nao submete.
     *
     * E' a razao de existir da classe: chamar o avaliar para pre-visualizar gravava os campos de
     * decisao, e esse update dispara o SC_AutoSubmit_Aprovacao, ou seja submetia a proposta que o
     * comercial ainda estava a confirmar.
     */
    @isTest static void prever_nao_grava_nao_partilha_nao_submete() {
        setup();
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);
        Opportunity o = opp(400000, 380000, 'Box Moving');

        Test.startTest();
        SC_PreverAprovacao.Result r = previsao(o.Id, 400000, 380000);
        Integer dml = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(0, dml, 'a previsao nao pode gastar DML nenhum.');
        System.assertEquals(3, r.nivel, 'premissa: esta proposta exige a cadeia toda.');

        Opportunity gravada = [SELECT Requer_Aprovacao__c, Requer_N2__c, Requer_N3__c,
                                      Aprovador_Alvo_N1__c, Aprovador_Alvo_N2__c, Aprovador_Alvo_N3__c
                               FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(false, gravada.Requer_Aprovacao__c, 'o campo de decisao nao pode ter sido escrito.');
        System.assertEquals(false, gravada.Requer_N2__c);
        System.assertEquals(false, gravada.Requer_N3__c);
        System.assertEquals(null, gravada.Aprovador_Alvo_N1__c, 'nem o aprovador alvo.');
        System.assertEquals(null, gravada.Aprovador_Alvo_N2__c);
        System.assertEquals(null, gravada.Aprovador_Alvo_N3__c);
        System.assertEquals(0, [SELECT COUNT() FROM OpportunityShare
                                WHERE OpportunityId = :o.Id AND RowCause = 'Manual'],
            'e nenhum aprovador ganha acesso a proposta so por ela ter sido pre-vista.');
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :o.Id],
            'e sobretudo: a proposta NAO foi submetida a aprovacao.');
    }

    // ── O eixo decisor: o ecra tem de poder dizer se foi o valor ou a margem. ──
    @isTest static void eixo_decisor_distingue_valor_de_margem() {
        setup();
        insert regra('Box Moving', 500000, 20, null, null, null, null, 'Valor OU Margem',
                     dir().Id, null, null);
        Opportunity o = opp(10000, 5000, 'Box Moving');

        Test.startTest();
        SC_PreverAprovacao.Result soMargem = previsao(o.Id, 100000, 87000);  // 13%, valor dentro
        SC_PreverAprovacao.Result soValor  = previsao(o.Id, 600000, 100000);  // 83,3%, valor fora
        SC_PreverAprovacao.Result ambos    = previsao(o.Id, 600000, 540000);  // 10% e valor fora
        SC_PreverAprovacao.Result nenhum   = previsao(o.Id, 100000, 50000);   // 50%, valor dentro
        Test.stopTest();

        System.assertEquals('Margem', soMargem.eixoDecisor,
            'a margem a 13% fura o piso de 20 e o valor esta dentro do tecto: decide a margem.');
        System.assertEquals(1, soMargem.nivel);
        System.assertEquals(13.0, soMargem.margemCalculada.setScale(1), 'e o ecra mostra a margem prevista.');
        System.assertEquals(500000, soMargem.autonomiaValor, 'com o tecto de autonomia da regra.');
        System.assertEquals(20, soMargem.autonomiaMargem, 'e o piso de margem da regra.');
        System.assertEquals('Valor OU Margem', soMargem.condicao, 'e a condicao tal como esta gravada.');
        System.assertEquals('500.000', soMargem.autonomiaValorTexto,
            'o tecto vai para o ecra escrito, e nao como 500000.00.');
        System.assertEquals('20', soMargem.autonomiaMargemTexto,
            'um piso inteiro escreve-se sem casas decimais.');
        System.assertEquals('13,0', soMargem.margemCalculadaTexto,
            'e a margem calculada com uma casa, como o Margem_Percentual__c.');

        System.assertEquals('Valor', soValor.eixoDecisor, 'valor acima do tecto com margem boa: decide o valor.');
        System.assertEquals('Ambos', ambos.eixoDecisor, 'os dois eixos furados ao mesmo nivel.');
        System.assertEquals('Nenhum', nenhum.eixoDecisor, 'dentro da autonomia nao ha eixo a decidir.');
        System.assertEquals(0, nenhum.nivel);
        System.assertEquals('Regra', nenhum.origem, 'e a decisao veio da matriz.');
    }

    // ── Os nomes dos aprovadores da cadeia, que e' o que o ecra escreve. ──
    @isTest static void nomes_dos_aprovadores_na_cadeia() {
        setup(); User d = dir(); User p = pvd(); User t = ter();
        insert regra('Workplace', 100000, 20, 500000, 18, 1000000, 15, 'Valor OU Margem',
                     d.Id, p.Id, t.Id);
        Opportunity o = opp(500, 440, 'Workplace'); // margem 12%, fura os tres pisos
        // o Name nao volta preenchido quando o pool CRIA o utilizador, por isso le-se da org
        Map<Id, User> nomes = new Map<Id, User>([SELECT Id, Name FROM User
                                                 WHERE Id IN :new List<Id>{ d.Id, p.Id, t.Id }]);

        Test.startTest();
        SC_PreverAprovacao.Result r = previsao(o.Id, 500, 440);
        Test.stopTest();

        System.assertEquals(3, r.nivel, 'premissa: a cadeia vai aos tres niveis.');
        System.assertEquals(nomes.get(d.Id).Name, r.aprovadorN1Nome, 'o nome do aprovador N1.');
        System.assertEquals(nomes.get(p.Id).Name, r.aprovadorN2Nome, 'o nome do aprovador N2.');
        System.assertEquals(nomes.get(t.Id).Name, r.aprovadorN3Nome, 'o nome do aprovador N3.');
        System.assertEquals('Margem', r.eixoDecisor, 'e foi a margem a decidir.');
    }

    // ── Autonomia total pelo invocavel: nivel 0, sem aprovadores e sem autonomia a mostrar. ──
    @isTest static void invocavel_reflecte_autonomia_total() {
        setup();
        SC_AvaliacaoAprovacaoTest.darAutonomia(owner().Id);
        insert regra('Box Moving', 50000, 16, 150000, 12, 300000, 8, 'Valor OU Margem',
                     dir().Id, pvd().Id, ter().Id);
        Opportunity o = opp(400000, 380000, 'Box Moving');

        Test.startTest();
        SC_PreverAprovacao.Result r = previsao(o.Id, 400000, 380000);
        Test.stopTest();

        System.assertEquals('AutonomiaTotal', r.origem);
        System.assertEquals(0, r.nivel);
        System.assertEquals(false, r.requerAprovacao);
        System.assertEquals(null, r.aprovadorN1Nome, 'sem aprovacao nao ha aprovador a nomear.');
        System.assertEquals(null, r.autonomiaValor, 'a isencao nao tem tecto para mostrar.');
        System.assertEquals('Nenhum', r.eixoDecisor);
        System.assertEquals(5.0, r.margemCalculada.setScale(1), 'a margem mostra-se sempre.');
    }

    /**
     * A formatacao dos numeros que o ecra escreve.
     *
     * Porque tem teste proprio: o ecra do G2 e' a unica coisa que o comercial le antes de submeter,
     * e antes disto dizia "ate 150000.00 euros e 20.00% de margem", porque o TEXT() de uma formula
     * preserva a escala do campo. Estes helpers sao a razao de a formatacao ter passado para Apex,
     * onde e' deterministica e independente do locale de quem corre o flow.
     */
    @isTest static void formatacao_dos_numeros_do_ecra() {
        System.assertEquals('150.000', SC_PreverAprovacao.formatarValor(150000),
            'um tecto redondo escreve-se com ponto nos milhares e sem casas decimais.');
        System.assertEquals('1.234,50', SC_PreverAprovacao.formatarValor(1234.5),
            'com centimos escreve-se com duas casas e virgula decimal.');
        System.assertEquals('999', SC_PreverAprovacao.formatarValor(999),
            'abaixo do milhar nao ha separador nenhum.');
        System.assertEquals(null, SC_PreverAprovacao.formatarValor(null),
            'nulo fica nulo, para o ecra distinguir "sem tecto" de "tecto zero".');

        System.assertEquals('20', SC_PreverAprovacao.formatarPercentagem(20, null),
            'um piso inteiro escreve-se sem casas.');
        System.assertEquals('12,5', SC_PreverAprovacao.formatarPercentagem(12.5, null),
            'um piso com meia casa mostra-a, com virgula.');
        System.assertEquals('13,0', SC_PreverAprovacao.formatarPercentagem(13.0, 1),
            'com casas fixas o zero decimal escreve-se.');
        System.assertEquals('21,9', SC_PreverAprovacao.formatarPercentagem(21.9, 1),
            'e uma casa arredondada mantem-se.');
        System.assertEquals(null, SC_PreverAprovacao.formatarPercentagem(null, 1),
            'nulo fica nulo tambem na percentagem.');
    }

    // ── Lista vazia ou nula nao rebenta nem gasta nada. ──
    @isTest static void invocavel_vazio_e_nulo() {
        Test.startTest();
        List<SC_PreverAprovacao.Result> a = SC_PreverAprovacao.prever(null);
        List<SC_PreverAprovacao.Result> b = SC_PreverAprovacao.prever(new List<SC_PreverAprovacao.Request>());
        Integer queries = Limits.getQueries();
        Test.stopTest();
        System.assertEquals(0, a.size());
        System.assertEquals(0, b.size());
        System.assertEquals(0, queries, 'sem pedidos nao ha query nenhuma.');
    }

    // ── Oportunidade ilegivel: excepcao, para o flow cair no faultConnector e mostrar a frase
    // neutra. Falhar a previsao nunca pode impedir a submissao. ──
    @isTest static void oportunidade_ilegivel_lanca_excepcao() {
        Id inexistente = '006000000000000AAA';
        Boolean rebentou = false;
        Test.startTest();
        try {
            previsao(inexistente, 100000, 60000);
        } catch (SC_PreverAprovacao.PrevisaoIndisponivelException e) {
            rebentou = true;
            System.assertEquals(true, e.getMessage().contains(inexistente),
                'a mensagem tem de identificar a oportunidade: ' + e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(true, rebentou,
            'uma oportunidade que o utilizador nao consegue ler tem de dar excepcao, e nao um veredicto inventado.');
    }
}