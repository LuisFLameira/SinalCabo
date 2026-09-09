/**
 * SC_AvaliacaoAprovacao (M.1, ADR-004, revisto pelo ADR-011)
 *
 * Motor de avaliacao de aprovacao por matriz Colaborador x Tipo de Negocio x Area.
 * Invocable (chamado pelo SC_Guiar_Pipeline no G2, no M.4) e bulkificavel.
 *
 * CHAVE DA REGRA (Colaborador x Tipo x Area) e resolucao por especificidade
 *   A mesma pessoa pode ter regras legitimas em AREAS diferentes com o mesmo Tipo
 *   (ex. Tipo "Solar" em "Energias Renovaveis" e em "Solarus"). A chave de match e'
 *   Colaborador | Tipo | norm(Area), com norm(x) = null/blank -> '' e trim.
 *   A regra para uma opp resolve-se por especificidade decrescente:
 *     1. EXACTA:   OwnerId | Tipo | norm(Area_Negocio__c da opp)
 *     2. GENERICA: OwnerId | Tipo | ''   (regras gravadas sem area)
 *     3. FALLBACK: CMT SC_BU_Director (director da Empresa_Lider como N1 unico)
 *   Em tipos 1:1 com a area (todos menos "Solar") a area e' inerte: a chave exacta e a
 *   generica convergem no mesmo comportamento.
 *
 * Decisao de arquitectura: Apex invocable (nao Flow puro). A combinacao de
 * 4 modos de condicao (Valor OU/E Margem, So Valor, So Margem) x 3 niveis (N0/N1/N2),
 * mais "regra mais conservadora", 3 aprovadores em cadeia e fallback por CMT, fica
 * fragil e dificil de manter em Flow declarativo (risco assumido no ADR-004).
 *
 * MODELO POR NIVEIS (ADR-011, contagem de tectos)
 *   margem = Margem_Percentual__c da opp (margem bruta, em pontos percentuais).
 *   nivelValor  = nº de tectos de valor (Valor_N0/N1/N2) nao nulos que o Amount
 *                 ultrapassa ESTRITAMENTE (Amount > tecto).
 *   nivelMargem = nº de pisos de margem (Margem_Min_N0/N1/N2) nao nulos que a margem
 *                 fica abaixo ESTRITAMENTE (margem < piso).
 *   O nivel exigido combina os dois eixos pela Condicao__c da regra:
 *     - "Só Valor"        -> nivelValor.
 *     - "Só Margem"       -> nivelMargem.
 *     - "Valor E Margem"  -> min(nivelValor, nivelMargem)  (o menos exigente).
 *     - "Valor OU Margem" -> max(nivelValor, nivelMargem)  (o mais exigente).
 *     - nula/desconhecida -> "Valor OU Margem" (default de negocio da folha).
 *   Clamp: nivelFinal = min(nivelExigido, nº de aprovadores preenchidos por ordem
 *   N1->N2->N3, usando o Backup respectivo se o titular estiver vazio).
 *     nivelFinal 0 -> autonomo (nao requer aprovacao)
 *     nivelFinal 1 -> N1
 *     nivelFinal 2 -> N1 + N2 (cadeia)
 *     nivelFinal 3 -> N1 + N2 + N3 (cadeia)
 *   Uma regra sem N3 nunca chega ao nivel 3, pelo clamp.
 *
 * CASOS DE FRONTEIRA (documentados e testados):
 *   - Limiar exacto de valor: Amount == Valor_Nx NAO cruza o tecto (uso > estrito),
 *     ou seja fica dentro do nivel; coerente com "ate" das matrizes.
 *   - Piso exacto de margem: margem == Margem_Min_Nx cumpre (uso < estrito para cruzar).
 *   - Threshold nulo num eixo: nao conta para a contagem desse eixo (ignora).
 *   - Margem nula: tratada como 0 (BlankAsZero), logo abaixo de qualquer piso.
 *   - Tectos coincidentes (Valor_N1 == Valor_N2, o default da folha): a banda intermedia
 *     colapsa; o clamp ao nº de aprovadores mantem o encaminhamento correcto.
 *   - Multiplas regras activas para a mesma celula: escolhe a MAIS CONSERVADORA
 *     (mais niveis exigidos; em empate, a de menor Valor_N1).
 *   - Multiplas AREAS para o mesmo Colaborador+Tipo: cada opp encaminha para a regra da
 *     SUA area (chave exacta); a regra sem area (chave generica) so serve de fallback.
 *   - Sem regra para Colaborador+Tipo+Area (nem exacta nem generica): FALLBACK por CMT
 *     SC_BU_Director (director da Empresa_Lider como N1; sem N2/N3), para nao ficar sem governacao.
 *
 * APROVADOR AUSENTE (substituicao por User.DelegatedApproverId)
 *   Depois de a regra ou o fallback resolverem a cadeia, e ANTES de gravar, cada aprovador
 *   resolvido e' trocado pelo seu Delegated Approver, se o tiver preenchido. A presenca do
 *   campo na ficha do utilizador E' o interruptor de ausencia: nao ha campo custom, nem data,
 *   nem flow agendado. Detalhe e guardas em substitutosDeAusentes e em aplicarSubstituicoes.
 *
 * DOIS PONTOS DE ENTRADA, UMA SO DECISAO
 *   avaliar  invocable do G2 (SC_Guiar_Pipeline): le' o contexto, decide e GRAVA (os campos de
 *            decisao na Opportunity e o OpportunityShare dos aprovadores).
 *   prever   previsao para o ecra de confirmacao, chamada pelo SC_PreverAprovacao: le' o contexto,
 *            decide e devolve o Result, sem DML nenhum.
 *   Os dois partilham carregarContexto (leitura da org) e decidirUma (decisao), por isso o que o
 *   ecra anuncia nao pode divergir do que o motor faz a seguir.
 *
 *   A margem entra em decidirUma como PARAMETRO e nao pelo campo da oportunidade: o
 *   Margem_Percentual__c e' formula e uma opp em memoria, com valores acabados de introduzir, nao
 *   a tem calculada (o Apex nao escreve em campo formula). O avaliar passa o campo gravado; a
 *   previsao passa margemDe(amount, custo), que replica a formula, arredondamento a uma casa
 *   incluido, para as duas decidirem na mesma fronteira.
 */
public with sharing class SC_AvaliacaoAprovacao {

    // ---------- Invocable wrappers ----------
    public class Request {
        @InvocableVariable(required=true label='Opportunity ID') public Id opportunityId;
    }
    public class Result {
        @InvocableVariable(label='Requer Aprovacao') public Boolean requerAprovacao;
        @InvocableVariable(label='Requer N2') public Boolean requerN2;
        @InvocableVariable(label='Requer N3') public Boolean requerN3;
        @InvocableVariable(label='Aprovador Alvo N1') public Id aprovadorN1;
        @InvocableVariable(label='Aprovador Alvo N2') public Id aprovadorN2;
        @InvocableVariable(label='Aprovador Alvo N3') public Id aprovadorN3;
        // 'Regra'          a matriz tem linha para o owner, tipo e area, e foi ela que decidiu
        // 'Fallback'       nao ha linha, decidiu o director da Empresa Lider (SC_BU_Director__mdt)
        // 'SemGovernacao'  nao ha linha nem director, a opp passa sem aprovacao por falta de config
        // 'AutonomiaTotal' o owner tem o PS SC_Autonomia_Total, esta' isento do gate por decisao
        //
        // A diferenca entre os dois ultimos importa para auditoria: 'SemGovernacao' e' uma lacuna
        // de configuracao a corrigir, 'AutonomiaTotal' e' uma decisao de negocio a respeitar.
        @InvocableVariable(label='Origem da decisao') public String origem;

        // Detalhe da decisao, SEM @InvocableVariable: nao entra no contrato do Apex_Motor (o flow
        // do G2 continua a ler so os campos de cima) e serve a previsao do ecra de confirmacao,
        // que tem de explicar por que e' que a proposta escala. Preenchido em avaliarPorRegra;
        // fica nulo em AutonomiaTotal, Fallback e SemGovernacao, onde nao ha regra nem eixos.
        public Integer nivelValor;      // tectos de valor que o Amount ultrapassa
        public Integer nivelMargem;     // pisos de margem que a margem fura
        public Id regraAplicadaId;      // a linha da matriz que decidiu
        public Decimal autonomiaValor;  // Valor_N0__c da regra, o tecto da autonomia
        public Decimal autonomiaMargem; // Margem_Min_N0__c da regra, o piso da autonomia
        public String condicao;         // Condicao__c da regra, tal como esta' gravada
    }

    @InvocableMethod(label='Avaliar Aprovacao (matriz)' description='Avalia a matriz e grava os campos de decisao na Opportunity')
    public static List<Result> avaliar(List<Request> pedidos) {
        List<Result> resultados = new List<Result>();
        if (pedidos == null || pedidos.isEmpty()) return resultados;

        Set<Id> oppIds = new Set<Id>();
        for (Request r : pedidos) if (r != null && r.opportunityId != null) oppIds.add(r.opportunityId);

        // 1 SOQL: opps
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, OwnerId, Amount, Margem_Percentual__c,
                   Direccao_Negocio__c, Area_Negocio__c, Tipo_Negocio__c, Empresa_Lider__c
            FROM Opportunity WHERE Id IN :oppIds WITH USER_MODE
        ]);

        Set<Id> owners = new Set<Id>();
        Set<String> tipos = new Set<String>();
        for (Opportunity o : opps.values()) { owners.add(o.OwnerId); if (o.Tipo_Negocio__c != null) tipos.add(o.Tipo_Negocio__c); }

        // 3 a 4 SOQL: matriz, ausencias e autonomia total (ver carregarContexto)
        Contexto ctx = carregarContexto(owners, tipos);

        List<Opportunity> toUpdate = new List<Opportunity>();
        // partilha do aprovador: (oppId -> Set de userIds a partilhar). OWD da Opp e' Private,
        // por isso um aprovador de outra area/hierarquia nao ve a opp sem share explicito.
        Map<Id, Set<Id>> aprovadoresPorOpp = new Map<Id, Set<Id>>();

        for (Request req : pedidos) {
            Result res = new Result();
            Opportunity o = (req != null) ? opps.get(req.opportunityId) : null;
            if (o == null) { res.origem = 'SemGovernacao'; resultados.add(res); continue; }

            // a decisao e' a mesma funcao que serve a previsao do ecra; aqui passa-se a margem
            // gravada pela formula, que e' o valor sobre o qual a proposta vai mesmo ser avaliada.
            decidirUma(o, o.Margem_Percentual__c, ctx, res);

            // gravar campos de decisao. O que se grava aqui e' o ALVO (quem foi designado), nao o
            // carimbo: os G2_L1/L2/L3_Aprovador sao escritos na DECISAO, pelo SC_AprovacaoStampService,
            // a partir de quem realmente decidiu o passo. Alvo e carimbo divergem quando decide um
            // delegado nativo, e carimbar aqui deitava fora essa informacao.
            toUpdate.add(new Opportunity(
                Id = o.Id,
                Requer_Aprovacao__c = res.requerAprovacao == true,
                Requer_N2__c = res.requerN2 == true,
                Requer_N3__c = res.requerN3 == true,
                Aprovador_Alvo_N1__c = res.aprovadorN1,
                Aprovador_Alvo_N2__c = res.aprovadorN2,
                Aprovador_Alvo_N3__c = res.aprovadorN3
            ));

            // recolher aprovadores a partilhar (so quando requer aprovacao)
            if (res.requerAprovacao == true) {
                Set<Id> users = new Set<Id>();
                if (res.aprovadorN1 != null) users.add(res.aprovadorN1);
                if (res.requerN2 == true && res.aprovadorN2 != null) users.add(res.aprovadorN2);
                if (res.requerN3 == true && res.aprovadorN3 != null) users.add(res.aprovadorN3);
                if (!users.isEmpty()) aprovadoresPorOpp.put(o.Id, users);
            }
            resultados.add(res);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        partilharComAprovadores(aprovadoresPorOpp);
        return resultados;
    }

    /**
     * O contexto de decisao: tudo o que se le' da org antes de decidir.
     *
     * Existe para o avaliar (que grava) e o prever (que nao grava) decidirem sobre o MESMO
     * contexto, com uma leitura so por chamada.
     */
    public class Contexto {
        public Map<String, List<Regra_Aprovacao__c>> regrasPorChave = new Map<String, List<Regra_Aprovacao__c>>();
        public Map<String, SC_BU_Director__mdt> dirPorBU = new Map<String, SC_BU_Director__mdt>();
        public Map<Id, Id> substitutos = new Map<Id, Id>();
        public Set<Id> autonomiaTotal = new Set<Id>();
    }

    /**
     * Le' a matriz, os directores por BU, as ausencias declaradas e quem tem autonomia total.
     *
     * 3 a 4 SOQL: regras (1), ausencias (1 ou 2, ver substitutosDeAusentes) e autonomia total (1).
     * O CMT (getAll) e o Custom Setting (getOrgDefaults) nao gastam query. Sem owners ou sem tipos
     * nao ha matriz a ler, e os dois helpers nao gastam query nenhuma com conjuntos vazios.
     */
    public static Contexto carregarContexto(Set<Id> owners, Set<String> tipos) {
        Contexto ctx = new Contexto();

        // todos os aprovadores que este lote pode vir a designar (regras, fallback e default),
        // recolhidos aqui para a leitura das ausencias ser uma so query fora do loop
        Set<Id> aprovadoresPossiveis = new Set<Id>();

        // 1 SOQL: regras activas para os owners+tipos em jogo
        if (owners != null && !owners.isEmpty() && tipos != null && !tipos.isEmpty()) {
            // NB: nao se filtra por Area no SOQL, para poder aplicar em memoria o fallback
            // da chave generica (regras sem area) quando nao ha regra exacta para a area da opp.
            for (Regra_Aprovacao__c rg : [
                SELECT Id, Colaborador__c, Tipo_Negocio__c, Area__c, Valor_N0__c, Valor_N1__c, Valor_N2__c,
                       Margem_Min_N0__c, Margem_Min_N1__c, Margem_Min_N2__c, Condicao__c,
                       Aprovador_N1__c, Aprovador_N2__c, Aprovador_N3__c,
                       Backup_N1__c, Backup_N2__c, Backup_N3__c
                FROM Regra_Aprovacao__c
                WHERE Activa__c = true AND Colaborador__c IN :owners AND Tipo_Negocio__c IN :tipos
                WITH USER_MODE
            ]) {
                String k = rg.Colaborador__c + '|' + rg.Tipo_Negocio__c + '|' + norm(rg.Area__c);
                if (!ctx.regrasPorChave.containsKey(k)) ctx.regrasPorChave.put(k, new List<Regra_Aprovacao__c>());
                ctx.regrasPorChave.get(k).add(rg);
                for (Id a : new List<Id>{ rg.Aprovador_N1__c, rg.Aprovador_N2__c, rg.Aprovador_N3__c,
                                          rg.Backup_N1__c, rg.Backup_N2__c, rg.Backup_N3__c }) {
                    if (a != null) aprovadoresPossiveis.add(a);
                }
            }
        }

        // CMT para fallback (mapa BU -> director)
        for (SC_BU_Director__mdt d : SC_BU_Director__mdt.getAll().values()) {
            if (d.BU_Label__c != null) ctx.dirPorBU.put(d.BU_Label__c, d);
            if (d.Director_User_Id__c != null) {
                // um Id mal preenchido no CMT nao pode rebentar o lote inteiro aqui; quando essa
                // BU precisar mesmo do fallback, e' o aplicarFallback que falha.
                try { aprovadoresPossiveis.add((Id) d.Director_User_Id__c); } catch (Exception e) {}
            }
        }
        Id defaultConfig = aprovadorDefault();
        if (defaultConfig != null) aprovadoresPossiveis.add(defaultConfig);

        // 1 ou 2 SOQL: quem dos aprovadores possiveis esta' ausente, e por quem e' substituido
        ctx.substitutos = substitutosDeAusentes(aprovadoresPossiveis);

        // 1 SOQL: quem tem autonomia total. So' os owners em jogo, e so' se houver
        // owners, portanto nao ha custo quando o motor corre sobre uma opp sem owner resolvido.
        ctx.autonomiaTotal = comAutonomiaTotal(owners);

        return ctx;
    }

    /**
     * A decisao para UMA oportunidade, sem tocar na base de dados: autonomia total, resolucao da
     * regra por especificidade, regra ou fallback, e substituicao dos aprovadores ausentes.
     *
     * A margem vem por parametro, em pontos percentuais (ver o cabecalho da classe); nula e'
     * tratada como zero em avaliarPorRegra.
     */
    private static void decidirUma(Opportunity o, Decimal margem, Contexto ctx, Result res) {
        // AUTONOMIA TOTAL: vem ANTES da resolucao da chave, e nao depois, porque
        // e' uma isencao do gate e nao um resultado da matriz. Se viesse depois, uma opp do
        // PVD com regra na matriz seria avaliada por essa regra e a isencao ficava a depender
        // de a matriz nao ter linha para ele, que e' uma coincidencia e nao uma decisao.
        if (ctx.autonomiaTotal.contains(o.OwnerId)) {
            res.requerAprovacao = false;
            res.requerN2 = false;
            res.requerN3 = false;
            res.origem = 'AutonomiaTotal';
            // sem aprovadores: quem grava nao tem com quem partilhar, e os campos de alvo ficam
            // nulos, o que limpa um aprovador pendurado de uma avaliacao anterior.
            return;
        }

        // Resolucao por especificidade: chave exacta (com area) -> chave generica (sem area).
        String chaveExacta   = o.OwnerId + '|' + o.Tipo_Negocio__c + '|' + norm(o.Area_Negocio__c);
        String chaveGenerica = o.OwnerId + '|' + o.Tipo_Negocio__c + '|' + '';
        List<Regra_Aprovacao__c> regras = ctx.regrasPorChave.get(chaveExacta);
        if (regras == null || regras.isEmpty()) regras = ctx.regrasPorChave.get(chaveGenerica);

        if (regras != null && !regras.isEmpty()) {
            avaliarPorRegra(o, margem, escolherMaisConservadora(regras, o, margem), res);
        } else {
            aplicarFallback(o, ctx.dirPorBU, res);
        }

        // ausencia: troca cada aprovador resolvido pelo seu substituto. Vem depois da regra E
        // do fallback, de proposito, para ser um ponto de aplicacao so.
        aplicarSubstituicoes(res, o.OwnerId, ctx.substitutos);
    }

    /**
     * A margem que a formula Margem_Percentual__c da' para estes valores: pontos percentuais,
     * arredondados a uma casa decimal como o campo (scale 1, HALF_UP), nulos tratados como zero.
     *
     * E' o que permite a previsao decidir na mesma fronteira que o motor decide depois de gravar:
     * 396.000 com custo 309.375 da' 21,875, que o campo grava e devolve como 21,9.
     */
    public static Decimal margemDe(Decimal amount, Decimal custo) {
        Decimal a = (amount == null) ? 0 : amount;
        Decimal c = (custo == null) ? 0 : custo;
        if (a <= 0) return 0;
        return ((a - c) / a * 100).setScale(1, RoundingMode.HALF_UP);
    }

    /**
     * A decisao da matriz para uma oportunidade em memoria, SEM gravar nada.
     *
     * Serve o ecra de confirmacao do G2, pelo SC_PreverAprovacao: o comercial ve, antes de
     * confirmar, o veredicto que o avaliar vai produzir com os valores que acabou de introduzir.
     * Zero DML, e por isso nao dispara o SC_AutoSubmit_Aprovacao nem submete a proposta.
     *
     * A opp em memoria traz o OwnerId, o Tipo_Negocio__c, a Area_Negocio__c e a Empresa_Lider__c
     * da oportunidade gravada, com o Amount e o Custo_Estimado__c do ecra. A margem calcula-se
     * aqui com margemDe, porque o campo formula so' existe depois de gravar.
     *
     * Uma opp por chamada, com o seu proprio contexto (3 a 4 SOQL). Prever um lote grande exigiria
     * carregar o contexto uma vez e chamar a decisao opp a opp; hoje nao e' preciso, porque o ecra
     * do G2 pergunta por uma proposta de cada vez.
     */
    public static Result prever(Opportunity oppEmMemoria) {
        Result res = new Result();
        if (oppEmMemoria == null) { res.origem = 'SemGovernacao'; return res; }

        Set<Id> owners = new Set<Id>();
        if (oppEmMemoria.OwnerId != null) owners.add(oppEmMemoria.OwnerId);
        Set<String> tipos = new Set<String>();
        if (oppEmMemoria.Tipo_Negocio__c != null) tipos.add(oppEmMemoria.Tipo_Negocio__c);

        decidirUma(oppEmMemoria, margemDe(oppEmMemoria.Amount, oppEmMemoria.Custo_Estimado__c),
                   carregarContexto(owners, tipos), res);
        return res;
    }

    /**
     * Os owners que estao isentos do Gate G2, por terem o Permission Set SC_Autonomia_Total.
     *
     * PORQUE PERMISSION SET E NAO CUSTOM METADATA: o PS vai no source e e' portavel para a
     * producao greenfield, enquanto um CMT com User Id exigia re-semear os Ids em producao, mais
     * um passo no MANUAL_STEPS ao lado do que ja existe para o SC_BU_Director. E dar ou tirar
     * autonomia passa a ser atribuir ou remover o PS na UI, sem deploy. E' o mesmo padrao do
     * SC_Editar_Stage_Manual, que isenta de uma validation rule.
     *
     * PORQUE NAO CUSTOM PERMISSION: a pergunta e' sobre o OWNER da oportunidade, e o
     * FeatureManagement.checkPermission so' responde pelo utilizador corrente, que num
     * processamento em bulk nao e' o mesmo. Dai a consulta directa a PermissionSetAssignment.
     *
     * Filtra pelos owners em jogo para nao trazer a org toda, e nao gasta query nenhuma quando
     * nao ha owners a avaliar.
     *
     * SEM WITH USER_MODE, ao contrario das outras duas queries deste metodo, e isso e' deliberado:
     * o PermissionSetAssignment e' um objecto de setup e um comercial nao tem leitura nele. Em
     * USER_MODE a query rebenta para quem submete a oportunidade, que e' precisamente quem faz
     * correr este motor. A consulta e' de leitura, sobre um conjunto fechado de Ids que o proprio
     * motor ja tem em maos, e nao expoe dado nenhum ao utilizador.
     */
    @TestVisible
    private static Set<Id> comAutonomiaTotal(Set<Id> owners) {
        Set<Id> isentos = new Set<Id>();
        if (owners == null || owners.isEmpty()) return isentos;
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'SC_Autonomia_Total'
              AND AssigneeId IN :owners
        ]) {
            isentos.add(psa.AssigneeId);
        }
        return isentos;
    }

    /**
     * Mapa "aprovador ausente -> quem o substitui", lido do campo nativo User.DelegatedApproverId.
     *
     * FONTE DE VERDADE: o campo preenchido significa ausente. Nao ha campo custom, nem janela de
     * datas, nem flow agendado a ligar e desligar nada. Quem regressa apaga o campo.
     *
     * COM WITH USER_MODE, ao contrario do comAutonomiaTotal aqui em cima: o User nao e' objecto de
     * setup para efeitos de leitura e o DelegatedApproverId e' legivel por todos os perfis com
     * utilizadores activos nesta org (End User, Executive Sponsor, Identity User, System
     * Administrator e Sales Insights), sem perda de linhas por sharing. Nao ha aqui a razao que
     * obriga o PermissionSetAssignment a sair do modo de utilizador, portanto fica na politica
     * da classe.
     *
     * QUATRO GUARDAS, e as duas ultimas nao sao teoricas:
     *  1. Auto-referencia: um utilizador apontado a si proprio nao e' substituicao nenhuma.
     *  2. Salto unico: se o substituto TAMBEM estiver ausente, nao se substitui. Sem isto, duas
     *     pessoas a substituirem-se mutuamente encadeavam sem fim; e mandar a proposta a quem
     *     declarou estar ausente trocava um bloqueio por outro. Fica o titular da matriz.
     *  3. Substituto inactivo: NAO se substitui. Um lookup para utilizador inactivo GRAVA, mas o
     *     Approval Process le' o Aprovador_Alvo como VAZIO e a submissao automatica falha, o que
     *     faz falhar o proprio update da oportunidade ("This approval request requires the next
     *     approver to be determined by the Aprovador Alvo N1 field. This value is empty"). Sem
     *     esta guarda, um substituto inactivo rebenta o lote todo.
     *  4. Substituto ilegivel (o utilizador corrente nao o ve): fica o titular. Falha para o lado
     *     seguro, que e' manter a governacao configurada.
     *
     * O que NAO precisa de guarda: o campo aceita, no schema, Group e User,
     * mas a plataforma rejeita a gravacao de um grupo ou fila ("You can't assign a group or queue
     * as a delegated approver"). Nunca chega aqui um Id que nao seja de utilizador.
     */
    @TestVisible
    private static Map<Id, Id> substitutosDeAusentes(Set<Id> aprovadores) {
        Map<Id, Id> subs = new Map<Id, Id>();
        if (aprovadores == null || aprovadores.isEmpty()) return subs;

        Map<Id, User> lidos = new Map<Id, User>();
        Map<Id, Id> declarado = new Map<Id, Id>();
        for (User u : [
            SELECT Id, IsActive, DelegatedApproverId FROM User
            WHERE Id IN :aprovadores WITH USER_MODE
        ]) {
            lidos.put(u.Id, u);
            if (u.DelegatedApproverId != null && u.DelegatedApproverId != u.Id) {  // guarda 1
                declarado.put(u.Id, u.DelegatedApproverId);
            }
        }
        if (declarado.isEmpty()) return subs;

        // segunda query so' para os substitutos que nao sao eles proprios aprovadores da matriz
        Set<Id> porLer = new Set<Id>();
        for (Id s : declarado.values()) if (!lidos.containsKey(s)) porLer.add(s);
        if (!porLer.isEmpty()) {
            for (User u : [SELECT Id, IsActive, DelegatedApproverId FROM User
                           WHERE Id IN :porLer WITH USER_MODE]) {
                lidos.put(u.Id, u);
            }
        }

        for (Id titular : declarado.keySet()) {
            User sub = lidos.get(declarado.get(titular));
            if (sub == null) continue;                       // guarda 4
            if (sub.IsActive != true) continue;              // guarda 3
            if (sub.DelegatedApproverId != null) continue;   // guarda 2
            subs.put(titular, sub.Id);
        }
        return subs;
    }

    /**
     * Troca os aprovadores ausentes pelos substitutos, no Result ja resolvido.
     *
     * PORQUE AQUI E NAO NO APPROVAL PROCESS: ao entrar no Aprovador_Alvo_Nx__c, o substituto herda
     * de graca tudo o que ja esta' amarrado a esse campo, o OpportunityShare do
     * partilharComAprovadores, a atribuicao do proprio Approval Process, a notificacao e o carimbo.
     * A delegacao nativa (allowDelegate) nao da nada disso: um delegado nativo sem acesso ao
     * registo NAO ve sequer o item para aprovar, e so' passa a ver e a conseguir aprovar quando
     * recebe o mesmo share que o motor da a um aprovador alvo.
     *
     * QUINTA GUARDA, esta dependente da oportunidade: um substituto que seja o DONO da proposta e'
     * ignorado, senao a pessoa aprovava-se a si propria. Nao se troca por outro, fica o titular da
     * matriz. (O partilharComAprovadores ja salta o dono na partilha, mas isso e' outro problema.)
     */
    private static void aplicarSubstituicoes(Result res, Id dono, Map<Id, Id> subs) {
        if (subs.isEmpty()) return;
        res.aprovadorN1 = substituir(res.aprovadorN1, dono, subs);
        res.aprovadorN2 = substituir(res.aprovadorN2, dono, subs);
        res.aprovadorN3 = substituir(res.aprovadorN3, dono, subs);
    }

    private static Id substituir(Id titular, Id dono, Map<Id, Id> subs) {
        if (titular == null) return null;
        Id sub = subs.get(titular);
        if (sub == null) return titular;   // nao esta ausente
        if (sub == dono) return titular;   // guarda 5
        return sub;
    }

    // Normaliza a Area para a chave de match: null/blank -> '', trim.
    private static String norm(String s) {
        return (s == null) ? '' : s.trim();
    }

    // ---------- Decisao por uma regra concreta (modelo por niveis, ADR-011) ----------
    private static void avaliarPorRegra(Opportunity o, Decimal margemOpp, Regra_Aprovacao__c r, Result res) {
        Decimal amount = (o.Amount == null) ? 0 : o.Amount;
        Decimal margem = (margemOpp == null) ? 0 : margemOpp;
        res.origem = 'Regra';

        // aprovadores da cadeia (titular ou backup)
        Id ap1 = (r.Aprovador_N1__c != null) ? r.Aprovador_N1__c : r.Backup_N1__c;
        Id ap2 = (r.Aprovador_N2__c != null) ? r.Aprovador_N2__c : r.Backup_N2__c;
        Id ap3 = (r.Aprovador_N3__c != null) ? r.Aprovador_N3__c : r.Backup_N3__c;

        // clamp: cadeia de aprovadores preenchidos, por ordem N1 -> N2 -> N3
        Integer maxNivelConfig = 0;
        if (ap1 != null) { maxNivelConfig = 1; if (ap2 != null) { maxNivelConfig = 2; if (ap3 != null) maxNivelConfig = 3; } }

        Integer nv = nivelValor(amount, r);
        Integer nm = nivelMargem(margem, r);
        Integer exigido = nivelExigido(nv, nm, r.Condicao__c);
        Integer nivelFinal = Math.min(exigido, maxNivelConfig);

        res.requerAprovacao = (nivelFinal >= 1);
        res.requerN2 = (nivelFinal >= 2);
        res.requerN3 = (nivelFinal >= 3);
        if (nivelFinal >= 1) res.aprovadorN1 = ap1;
        if (nivelFinal >= 2) res.aprovadorN2 = ap2;
        if (nivelFinal >= 3) res.aprovadorN3 = ap3;

        // detalhe para a previsao explicar a decisao: os dois eixos ANTES do clamp (e' o que diz
        // se decidiu o valor ou a margem), a regra aplicada e a autonomia dela.
        res.nivelValor = nv;
        res.nivelMargem = nm;
        res.regraAplicadaId = r.Id;
        res.autonomiaValor = r.Valor_N0__c;
        res.autonomiaMargem = r.Margem_Min_N0__c;
        res.condicao = r.Condicao__c;
    }

    // nº de tectos de valor que o Amount ultrapassa estritamente (tecto inclusivo).
    private static Integer nivelValor(Decimal amount, Regra_Aprovacao__c r) {
        Integer n = 0;
        if (r.Valor_N0__c != null && amount > r.Valor_N0__c) n++;
        if (r.Valor_N1__c != null && amount > r.Valor_N1__c) n++;
        if (r.Valor_N2__c != null && amount > r.Valor_N2__c) n++;
        return n;
    }

    // nº de pisos de margem que a margem fica abaixo estritamente (piso inclusivo).
    private static Integer nivelMargem(Decimal margem, Regra_Aprovacao__c r) {
        Integer n = 0;
        if (r.Margem_Min_N0__c != null && margem < r.Margem_Min_N0__c) n++;
        if (r.Margem_Min_N1__c != null && margem < r.Margem_Min_N1__c) n++;
        if (r.Margem_Min_N2__c != null && margem < r.Margem_Min_N2__c) n++;
        return n;
    }

    // combina os dois eixos pela Condicao (default = "Valor OU Margem", o da folha).
    private static Integer nivelExigido(Integer nv, Integer nm, String cond) {
        String c = (cond == null) ? 'Valor OU Margem' : cond;
        if (c == 'Só Valor')  return nv;
        if (c == 'Só Margem') return nm;
        if (c == 'Valor E Margem') return Math.min(nv, nm);
        // 'Valor OU Margem' e o default de negocio (o mais exigente)
        return Math.max(nv, nm);
    }

    // Mais conservadora: mais niveis exigidos; em empate, menor Valor_N1 (mais exigente).
    //
    // @TestVisible: duas regras GRAVADAS para a mesma celula colidem na unicidade da Chave__c
    // (External Id composto por Colaborador+Tipo+Area pelo before-save SC_Chave_Regra_Aprovacao),
    // por isso este desempate e' codigo de defesa (flow desactivado, ou duplicados vindos de
    // carregamento de dados) e so' e' exercitavel por chamada directa com regras em memoria.
    @TestVisible
    private static Regra_Aprovacao__c escolherMaisConservadora(List<Regra_Aprovacao__c> regras, Opportunity o, Decimal margem) {
        if (regras.size() == 1) return regras[0];
        Regra_Aprovacao__c melhor = null;
        Integer melhorNiveis = -1;
        Decimal melhorValorN1 = null;
        for (Regra_Aprovacao__c r : regras) {
            Result tmp = new Result();
            avaliarPorRegra(o, margem, r, tmp);
            Integer niveis = (tmp.requerAprovacao != true)
                ? 0
                : (tmp.requerN3 == true ? 3 : (tmp.requerN2 == true ? 2 : 1));
            Decimal vN1 = (r.Valor_N1__c == null) ? 0 : r.Valor_N1__c;
            if (niveis > melhorNiveis ||
                (niveis == melhorNiveis && (melhorValorN1 == null || vN1 < melhorValorN1))) {
                melhor = r; melhorNiveis = niveis; melhorValorN1 = vN1;
            }
        }
        return melhor;
    }

    // Fallback: director da Empresa_Lider via CMT, como N1 unico.
    // Se nao houver director, recorre ao aprovador admin por defeito (Custom Setting),
    // para a proposta NUNCA ficar sem alvo (o FAP precisa sempre de Aprovador_Alvo_N1).
    private static void aplicarFallback(Opportunity o, Map<String, SC_BU_Director__mdt> dirPorBU, Result res) {
        SC_BU_Director__mdt d = (o.Empresa_Lider__c != null) ? dirPorBU.get(o.Empresa_Lider__c) : null;
        res.requerAprovacao = true; res.requerN2 = false; res.requerN3 = false;
        if (d != null && d.Director_User_Id__c != null) {
            res.origem = 'Fallback';
            res.aprovadorN1 = (Id) d.Director_User_Id__c;
            return;
        }
        // Sem regra e sem director: aprovador admin por defeito, para nao ficar presa.
        res.origem = 'SemGovernacao';
        Id adminDefault = aprovadorDefault();
        if (adminDefault != null) {
            res.aprovadorN1 = adminDefault;
        }
        // Se ate o default estiver por configurar, fica sem alvo (estado a evitar):
        // o guia de arranque exige configurar SC_Aprovacao_Config.Aprovador_Default_Id__c.
    }

    // Le o aprovador admin por defeito do Custom Setting hierarquico (org default).
    @TestVisible
    private static Id aprovadorDefault() {
        SC_Aprovacao_Config__c cfg = SC_Aprovacao_Config__c.getOrgDefaults();
        if (cfg != null && String.isNotBlank(cfg.Aprovador_Default_Id__c)) {
            try { return (Id) cfg.Aprovador_Default_Id__c; }
            catch (Exception e) { return null; }
        }
        return null;
    }

    /**
     * Da acesso (OpportunityShare, Edit, RowCause Manual) ao(s) aprovador(es) designado(s),
     * para que um aprovador de outra area/hierarquia veja e aprove a opp (OWD = Private).
     * Bulk-safe e idempotente (nao duplica shares ja existentes). O dono e quem ja tem
     * acesso por hierarquia sao ignorados (Salesforce nao deixa partilhar com o owner).
     * Nota de design: a partilha NAO e' removida no fecho da aprovacao (aceitavel para
     * auditoria; limpar exigiria outro flow no fecho com risco de remover share legitimo).
     */
    private static void partilharComAprovadores(Map<Id, Set<Id>> aprovadoresPorOpp) {
        if (aprovadoresPorOpp == null || aprovadoresPorOpp.isEmpty()) return;

        // owners das opps (nao se partilha com o owner)
        Map<Id, Id> ownerPorOpp = new Map<Id, Id>();
        for (Opportunity o : [SELECT Id, OwnerId FROM Opportunity WHERE Id IN :aprovadoresPorOpp.keySet()]) {
            ownerPorOpp.put(o.Id, o.OwnerId);
        }

        // shares manuais ja existentes, para nao duplicar
        Set<String> existentes = new Set<String>();
        for (OpportunityShare sh : [
            SELECT OpportunityId, UserOrGroupId FROM OpportunityShare
            WHERE OpportunityId IN :aprovadoresPorOpp.keySet() AND RowCause = 'Manual'
        ]) {
            existentes.add(sh.OpportunityId + '|' + sh.UserOrGroupId);
        }

        List<OpportunityShare> novos = new List<OpportunityShare>();
        for (Id oppId : aprovadoresPorOpp.keySet()) {
            Id owner = ownerPorOpp.get(oppId);
            for (Id userId : aprovadoresPorOpp.get(oppId)) {
                if (userId == owner) continue;                       // owner ja ve
                if (existentes.contains(oppId + '|' + userId)) continue; // ja partilhado
                novos.add(new OpportunityShare(
                    OpportunityId = oppId,
                    UserOrGroupId = userId,
                    OpportunityAccessLevel = 'Edit',
                    RowCause = 'Manual'
                ));
            }
        }
        if (!novos.isEmpty()) {
            // allOrNone=false: ignora falhas pontuais (ex. user ja com acesso por outra via)
            Database.insert(novos, false);
        }
    }
}