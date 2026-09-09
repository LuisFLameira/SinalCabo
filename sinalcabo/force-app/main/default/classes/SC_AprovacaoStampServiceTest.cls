/**
 * SC_AprovacaoStampServiceTest
 *
 * Cobre o carimbo de QUEM aprovou cada nivel do Gate G2 (G2_L1/L2/L3_Aprovador__c), feito
 * pelo SC_AprovacaoStampService.
 *
 * O QUE A SUITE PROVA
 *   O carimbo e' escrito na DECISAO e nao na submissao: um nivel so' aparece preenchido depois
 *   de quem o decide ter decidido, e quem fica carimbado e' quem decidiu.
 *
 * O QUE E' FONTE DA VERDADE
 *   ProcessInstanceStep.ActorId (quem decidiu) e nao OriginalActorId (a quem estava atribuido).
 *   Numa decisao delegada os dois divergem, e e' o ActorId que interessa: e' o que responde a
 *   "quem aprovou isto". O teste carimbo_segue_o_delegado prova precisamente isso.
 *
 * PORQUE E' QUE AS DECISOES CORREM DENTRO DE Test.startTest/stopTest
 *   O carimbo e' Queueable, porque o ProcessInstanceStep da decisao so' esta' visivel depois
 *   do commit: em caminho sincrono, nas transicoes intermedias o passo ainda nao existe para
 *   quem le dentro da transaccao do Approval Process. Num teste, o trabalho assincrono so' e'
 *   garantido no stopTest, por isso as asserções de carimbo vem todas depois.
 */
@isTest
private class SC_AprovacaoStampServiceTest {

    // ── Fixtures (mesmo padrao do SC_RecallAprovacaoTest: utilizadores resolvidos em runtime) ──

    private static User comercial() {
        return [SELECT Id FROM User WHERE Profile.Name = 'End User' AND IsActive = true LIMIT 1];
    }

    // DelegatedApproverId = null NAO e' detalhe: um utilizador com substituto definido conta como
    // AUSENTE e o motor troca-o na submissao. Um fixture que apanhasse um desses teria o alvo
    // trocado por baixo e falharia por dados da org, nao por codigo.
    private static List<User> aprovadores(Id excluir, Integer quantos) {
        List<User> us = [SELECT Id FROM User
                         WHERE IsActive = true AND Id != :excluir AND DelegatedApproverId = null
                           AND Profile.Name IN ('Diretor', 'Executive Sponsor', 'System Administrator')
                         ORDER BY Profile.Name LIMIT :quantos];
        System.assertEquals(quantos, us.size(),
            'A org de teste precisa de ' + quantos + ' utilizadores activos com perfil de aprovacao.');
        return us;
    }

    private static Opportunity novaOpp(User dono, String sufixo) {
        Account a = new Account(Name = 'Carimbo ' + sufixo); insert a;
        Opportunity o = new Opportunity(Name = 'Carimbo Opp ' + sufixo, StageName = 'Aprovação Interna',
            CloseDate = Date.today().addMonths(2), AccountId = a.Id, OwnerId = dono.Id,
            Empresa_Lider__c = 'Sinalcabo', Amount = 150000, Custo_Estimado__c = 90000,
            Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial', Tipo_Negocio__c = 'Box Moving',
            Approval_Status__c = null);
        insert o;
        return o;
    }

    // Modelo por niveis (ADR-011): o nivel conta tectos ULTRAPASSADOS pelo Amount de 150k.
    // Um tecto -> so' N1; dois -> N1+N2; tres -> N1+N2+N3.
    private static void regra(User dono, String sufixo, Decimal tN0, Decimal tN1, Decimal tN2,
                              Id ap1, Id ap2, Id ap3) {
        insert new Regra_Aprovacao__c(Name = 'R ' + sufixo, Colaborador__c = dono.Id,
            Direccao__c = 'IT', Area__c = 'Gestão Comercial', Tipo_Negocio__c = 'Box Moving',
            Valor_N0__c = tN0, Valor_N1__c = tN1, Valor_N2__c = tN2,
            Condicao__c = 'Só Valor',
            Aprovador_N1__c = ap1, Aprovador_N2__c = ap2, Aprovador_N3__c = ap3,
            Activa__c = true, Chave__c = dono.Id + '|' + sufixo);
    }

    private static void correrMotor(Id oppId) {
        SC_AvaliacaoAprovacao.Request r = new SC_AvaliacaoAprovacao.Request();
        r.opportunityId = oppId;
        SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{ r });
    }

    private static Id workitemPendente(Id oppId) {
        return [SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :oppId AND ProcessInstance.Status = 'Pending'
                LIMIT 1].Id;
    }

    private static void processar(Id workitemId, String accao, String comentario) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setAction(accao);
        req.setWorkitemId(workitemId);
        if (comentario != null) req.setComments(comentario);
        Approval.process(req);
    }

    private static Opportunity carimbos(Id oppId) {
        return [SELECT Approval_Status__c, G2_L1_Aprovador__c, G2_L2_Aprovador__c, G2_L3_Aprovador__c,
                       G2_L1_Data_Aprovacao__c, G2_L2_Data_Aprovacao__c, G2_L3_Data_Aprovacao__c,
                       Aprovador_Alvo_N1__c, Aprovador_Alvo_N2__c, Aprovador_Alvo_N3__c
                FROM Opportunity WHERE Id = :oppId];
    }

    // Os passos aprovados do ciclo, pela ordem em que foram decididos.
    private static List<ProcessInstanceStep> passosAprovados(Id oppId) {
        return [SELECT ActorId, OriginalActorId, StepStatus
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId = :oppId AND StepStatus = 'Approved'
                ORDER BY CreatedDate ASC];
    }

    // ── 1. Antes de haver decisao, ninguem esta carimbado ─────────────────────────────
    // Uma opp acabada de submeter, parada na fila do L1, tem os tres "Aprovado por (Lx)" em
    // branco, mesmo com os alvos da matriz ja' resolvidos.
    @isTest static void submissao_nao_carimba_ninguem() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        regra(kam, 'c1', 100000, 120000, null, aps[0].Id, aps[1].Id, null);
        Opportunity o = novaOpp(kam, 'Submissao');

        Test.startTest();
        correrMotor(o.Id);
        Test.stopTest();

        Opportunity c = carimbos(o.Id);
        System.assertEquals('Aguarda L1', c.Approval_Status__c, 'Pre-condicao: o pedido esta na fila do L1.');
        System.assertEquals(aps[0].Id, c.Aprovador_Alvo_N1__c, 'Pre-condicao: o motor resolveu o alvo N1.');
        System.assertEquals(aps[1].Id, c.Aprovador_Alvo_N2__c, 'Pre-condicao: o motor resolveu o alvo N2.');
        System.assertEquals(null, c.G2_L1_Aprovador__c,
            'Ninguem decidiu ainda: "Aprovado por (L1)" tem de estar em branco.');
        System.assertEquals(null, c.G2_L2_Aprovador__c,
            'O L2 nem sequer viu o pedido: nao pode aparecer como quem aprovou.');
        System.assertEquals(null, c.G2_L3_Aprovador__c, 'Idem para o L3.');
        System.assertEquals(null, c.G2_L1_Data_Aprovacao__c, 'Sem decisao nao ha data de aprovacao.');
    }

    // ── 2. O carimbo de um nivel e' o actor do passo aprovado desse nivel ─────────────
    // E o nivel seguinte, que ainda tem o pedido na mao, continua em branco.
    @isTest static void carimbo_L1_e_o_actor_do_step() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        regra(kam, 'c2', 100000, 120000, null, aps[0].Id, aps[1].Id, null);
        Opportunity o = novaOpp(kam, 'L1');
        correrMotor(o.Id);
        System.assertEquals(true, [SELECT Requer_N2__c FROM Opportunity WHERE Id = :o.Id].Requer_N2__c,
            'Pre-condicao: a cadeia tem de exigir N2.');

        Test.startTest();
        Id wi = workitemPendente(o.Id);
        System.runAs(aps[0]) { processar(wi, 'Approve', null); }
        Test.stopTest();

        List<ProcessInstanceStep> passos = passosAprovados(o.Id);
        System.assertEquals(1, passos.size(), 'So houve uma decisao de aprovacao.');

        Opportunity c = carimbos(o.Id);
        System.assertEquals('Aguarda L2', c.Approval_Status__c, 'Pre-condicao: o pedido subiu ao L2.');
        System.assertEquals(passos[0].ActorId, c.G2_L1_Aprovador__c,
            'O carimbo do L1 e o ActorId do passo aprovado, que e a versao da plataforma de quem decidiu.');
        System.assertEquals(aps[0].Id, c.G2_L1_Aprovador__c, 'E esse actor e o N1.');
        System.assertNotEquals(null, c.G2_L1_Data_Aprovacao__c,
            'A data continua a ser do field update SC_AP_Carimbo_L1_Data do proprio AP.');
        System.assertEquals(null, c.G2_L2_Aprovador__c,
            'O L2 tem o pedido na mao e ainda nao decidiu: o campo dele fica em branco.');
        System.assertEquals(aps[1].Id, c.Aprovador_Alvo_N2__c,
            'Quem esta designado continua a ler-se no Aprovador_Alvo_N2, que e o campo para isso.');
    }

    // ── 3. Cadeia de tres: cada nivel carimba o seu decisor, e so' apos decidir ───────
    @isTest static void cadeia_de_tres_carimba_cada_nivel_na_sua_vez() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 3);
        regra(kam, 'c3', 50000, 80000, 100000, aps[0].Id, aps[1].Id, aps[2].Id);
        Opportunity o = novaOpp(kam, 'Tres');
        correrMotor(o.Id);
        System.assertEquals(true, [SELECT Requer_N3__c FROM Opportunity WHERE Id = :o.Id].Requer_N3__c,
            'Pre-condicao: a cadeia tem de exigir os tres niveis.');

        Test.startTest();
        Id wi1 = workitemPendente(o.Id);
        System.runAs(aps[0]) { processar(wi1, 'Approve', null); }
        Id wi2 = workitemPendente(o.Id);
        System.runAs(aps[1]) { processar(wi2, 'Approve', null); }
        Id wi3 = workitemPendente(o.Id);
        System.runAs(aps[2]) { processar(wi3, 'Approve', null); }
        Test.stopTest();

        List<ProcessInstanceStep> passos = passosAprovados(o.Id);
        System.assertEquals(3, passos.size(), 'Tres decisoes de aprovacao, uma por nivel.');

        Opportunity c = carimbos(o.Id);
        System.assertEquals('Aprovado', c.Approval_Status__c, 'Pre-condicao: o ciclo fechou aprovado.');
        System.assertEquals(passos[0].ActorId, c.G2_L1_Aprovador__c, 'L1 = quem decidiu primeiro.');
        System.assertEquals(passos[1].ActorId, c.G2_L2_Aprovador__c, 'L2 = quem decidiu a seguir.');
        System.assertEquals(passos[2].ActorId, c.G2_L3_Aprovador__c, 'L3 = quem decidiu por ultimo.');
        System.assertEquals(aps[0].Id, c.G2_L1_Aprovador__c);
        System.assertEquals(aps[1].Id, c.G2_L2_Aprovador__c);
        System.assertEquals(aps[2].Id, c.G2_L3_Aprovador__c);
    }

    // ── 4. Uma rejeicao nao carimba aprovador nenhum ──────────────────────────────────
    // O L1 aprovou e o L2 recusou. O que fica na ficha e' a rejeicao; o carimbo de aprovacao
    // do ciclo morto sai todo, e o caminho assincrono do carimbo nao o pode fazer renascer.
    @isTest static void rejeicao_em_L2_nao_deixa_carimbo_de_aprovacao() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        regra(kam, 'c4', 100000, 120000, null, aps[0].Id, aps[1].Id, null);
        Opportunity o = novaOpp(kam, 'Rejeicao');
        correrMotor(o.Id);

        Test.startTest();
        Id wi1 = workitemPendente(o.Id);
        System.runAs(aps[0]) { processar(wi1, 'Approve', null); }
        Id wi2 = workitemPendente(o.Id);
        System.runAs(aps[1]) { processar(wi2, 'Reject', 'Margem insuficiente'); }
        Test.stopTest();

        Opportunity c = carimbos(o.Id);
        System.assertEquals('Recusado', c.Approval_Status__c, 'Pre-condicao: o ciclo fechou recusado.');
        System.assertEquals(null, c.G2_L2_Aprovador__c,
            'Quem recusou nunca pode aparecer no campo "Aprovado por (L2)".');
        System.assertEquals(null, c.G2_L1_Aprovador__c,
            'O carimbo do ciclo morto sai, senao o ciclo seguinte nasce com um nivel a parecer aprovado.');
        System.assertEquals(null, c.G2_L1_Data_Aprovacao__c, 'Idem para a data.');
        System.assertEquals(aps[1].Id, [SELECT G2_Rejeitado_Por__c FROM Opportunity WHERE Id = :o.Id].G2_Rejeitado_Por__c,
            'Quem recusou fica no campo de rejeicao, que e o campo dele.');
    }

    // ── 5. Numa decisao delegada, o carimbo e' de quem decidiu ────────────────────────
    // O allowDelegate esta ligado nos tres passos. Com delegacao, o ActorId do step (o delegado)
    // diverge do OriginalActorId (o aprovador designado): a ficha tem de dizer quem carregou em
    // Aprovar, e nao quem devia ter carregado.
    //
    // A AUSENCIA E' DECLARADA COM O PEDIDO JA' EM VOO, E TEM DE SER ASSIM.
    // Para o SC_AvaliacaoAprovacao, um DelegatedApproverId preenchido significa "ausente" e o
    // motor troca o alvo LOGO NA SUBMISSAO. Se a ausencia fosse declarada antes de o motor
    // correr, o titular nunca chegaria a ser designado e a pre-condicao (designado = N1) nao
    // poderia ser verdade: nao havia delegacao a testar, so' substituicao. Com a substituicao
    // no motor, a delegacao NATIVA cobre um unico caso, o pedido que ja' estava submetido
    // quando a ausencia comeca, e e' esse o caso que este teste reproduz.
    @isTest static void carimbo_segue_o_delegado() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        User n1 = aps[0];
        User delegado = aps[1];

        regra(kam, 'c5', 100000, null, null, n1.Id, null, null);
        Opportunity o = novaOpp(kam, 'Delegado');
        correrMotor(o.Id);
        System.assertEquals(n1.Id, [SELECT Aprovador_Alvo_N1__c FROM Opportunity WHERE Id = :o.Id].Aprovador_Alvo_N1__c,
            'Pre-condicao: o pedido foi submetido ao titular, que nesse momento nao estava ausente.');
        System.assertEquals(n1.Id, [SELECT ActorId FROM ProcessInstanceWorkitem
                                    WHERE ProcessInstance.TargetObjectId = :o.Id
                                      AND ProcessInstance.Status = 'Pending' LIMIT 1].ActorId,
            'Pre-condicao: o work item esta na fila do titular, nao na do delegado.');

        // So' agora comeca a ausencia, com o pedido ja' em voo. DML de setup (User) isolado do
        // DML de negocio, senao rebenta em MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = n1.Id, DelegatedApproverId = delegado.Id);
        }

        Test.startTest();
        Id wi = workitemPendente(o.Id);
        System.runAs(delegado) { processar(wi, 'Approve', null); }
        Test.stopTest();

        List<ProcessInstanceStep> passos = passosAprovados(o.Id);
        System.assertEquals(1, passos.size(), 'Uma decisao.');
        System.assertEquals(delegado.Id, passos[0].ActorId, 'Pre-condicao: quem decidiu foi o delegado.');
        System.assertNotEquals(passos[0].ActorId, passos[0].OriginalActorId,
            'Pre-condicao: e uma decisao delegada, actor e original divergem.');

        Opportunity c = carimbos(o.Id);
        System.assertEquals(delegado.Id, c.G2_L1_Aprovador__c,
            'O carimbo segue o ActorId: aprovou quem carregou no botao.');
        System.assertEquals(n1.Id, c.Aprovador_Alvo_N1__c,
            'O designado continua a ler-se no alvo, que e onde a matriz o guarda.');
    }
}