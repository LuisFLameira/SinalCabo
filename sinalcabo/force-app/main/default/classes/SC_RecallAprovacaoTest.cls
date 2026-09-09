/**
 * SC_RecallAprovacaoTest
 *
 * Cobre o recall do Approval Process SC_G2_Aprovacao_Matriz: o submissor retira o pedido
 * antes de haver decisao final e a oportunidade volta a um estado reapresentavel, sem
 * ficar com um aprovador antigo carimbado nem com o auto-submit armado.
 *
 * ESTADO ALVO DEPOIS DE UM RECALL
 *   Approval_Status__c = "Recolhido"        (recallAction SC_AP_Rec_Status_Recolhido)
 *   Requer_Aprovacao__c = false             (recallAction SC_AP_Rec_Requer_Off)
 *   StageName = "Em Elaboração"             (recallAction SC_AP_Rec_Stage_Elab, com o flag da VR)
 *   G2_L1/L2/L3_Aprovador__c e _Data_Aprovacao__c limpos  (flow SC_Reset_Aprovacao_Rejeicao)
 *   Aprovador_Alvo_N1/N2/N3 e os campos de rejeicao intactos
 *
 * AS DUAS TRAVAS CONTRA A REAPRESENTACAO SILENCIOSA (as duas, nao uma)
 *   1. o estado nao fica em branco ("Recolhido"), e o SC_AutoSubmit_Aprovacao so submete
 *      com Approval_Status em branco;
 *   2. Requer_Aprovacao__c vai a false, que e a outra condicao do mesmo filtro.
 *   A reapresentacao passa obrigatoriamente pelo Guiar Pipeline, que limpa o estado no
 *   Update_PreMotor e volta a correr o motor (aqui simulado com o mesmo par de DMLs).
 *
 * NOTA SOBRE O RECALL EM APEX: na UI o submissor carrega em Recall (allowRecall=true);
 * em Apex o equivalente e Approval.process com action 'Removed', que a plataforma so
 * aceita de um administrador. O caminho de metadados accionado e o mesmo (as recallActions),
 * por isso o teste corre o 'Removed' como utilizador do teste, sem System.runAs.
 */
@isTest
private class SC_RecallAprovacaoTest {

    // Utilizadores resolvidos em runtime (sem Ids fixos), como no SC_RejeicaoStampServiceTest.
    private static User comercial() {
        return [SELECT Id FROM User WHERE Profile.Name = 'End User' AND IsActive = true LIMIT 1];
    }
    private static List<User> aprovadores(Id excluir, Integer quantos) {
        List<User> us = [SELECT Id FROM User
                         WHERE IsActive = true AND Id != :excluir
                           AND Profile.Name IN ('Diretor', 'Executive Sponsor', 'System Administrator')
                         ORDER BY Profile.Name LIMIT :quantos];
        System.assertEquals(quantos, us.size(),
            'A org de teste precisa de ' + quantos + ' utilizadores activos com perfil de aprovacao.');
        return us;
    }

    // Opp em Aprovação Interna com o estado por atribuir; e o motor que decide e submete.
    private static Opportunity novaOpp(User dono, String sufixo) {
        Account a = new Account(Name = 'Recall ' + sufixo); insert a;
        Opportunity o = new Opportunity(Name = 'Recall Opp ' + sufixo, StageName = 'Aprovação Interna',
            CloseDate = Date.today().addMonths(2), AccountId = a.Id, OwnerId = dono.Id,
            Empresa_Lider__c = 'Sinalcabo', Amount = 150000, Custo_Estimado__c = 90000,
            Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial', Tipo_Negocio__c = 'Box Moving',
            Approval_Status__c = null);
        insert o;
        return o;
    }

    // Modelo por niveis (ADR-011): o nivel conta tectos ULTRAPASSADOS pelo Amount.
    // Amount 150k com tecto N0 100k da nivel 1 (so N1); com N0 100k + N1 120k da nivel 2 (N1+N2).
    private static Regra_Aprovacao__c regra(User dono, String sufixo, Decimal tectoN1, Id apr1, Id apr2) {
        Regra_Aprovacao__c r = new Regra_Aprovacao__c(Name = 'R ' + sufixo, Colaborador__c = dono.Id,
            Direccao__c = 'IT', Area__c = 'Gestão Comercial', Tipo_Negocio__c = 'Box Moving',
            Valor_N0__c = 100000, Valor_N1__c = tectoN1, Margem_Min_N1__c = 5,
            Condicao__c = 'Só Valor', Aprovador_N1__c = apr1, Aprovador_N2__c = apr2,
            Activa__c = true, Chave__c = dono.Id + '|' + sufixo);
        insert r;
        return r;
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

    private static void processar(Id workitemId, String accao) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setAction(accao);
        req.setWorkitemId(workitemId);
        Approval.process(req);
    }

    private static Integer pendentes(Id oppId) {
        return [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :oppId AND Status = 'Pending'];
    }

    // ── 1. Recall com o pedido ainda em L1 ────────────────────────────────────────
    // A asserção que apanha a armadilha e a dos ZERO ProcessInstance pendentes: se o recall
    // deixasse o processo vivo, a opp ficava em Em Elaboração com um pedido ainda em aberto.
    @isTest static void recall_em_L1() {
        User kam = comercial();
        User n1 = aprovadores(kam.Id, 1)[0];
        regra(kam, 'rc1', 250000, n1.Id, null);
        Opportunity o = novaOpp(kam, 'L1');
        correrMotor(o.Id);
        System.assertEquals(1, pendentes(o.Id), 'Pre-condicao: a opp tem de estar submetida.');

        Test.startTest();
        processar(workitemPendente(o.Id), 'Removed');
        Test.stopTest();

        Opportunity c = [SELECT Approval_Status__c, Requer_Aprovacao__c, StageName,
                                Aprovador_Alvo_N1__c, G2_L1_Aprovador__c, G2_L1_Data_Aprovacao__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Recolhido', c.Approval_Status__c, 'Trava 1: o estado nao fica em branco.');
        System.assertEquals(false, c.Requer_Aprovacao__c, 'Trava 2: o auto-submit fica desarmado.');
        System.assertEquals('Em Elaboração', c.StageName, 'A opp volta a ser editavel pelo KAM.');
        System.assertEquals(null, c.G2_L1_Aprovador__c, 'O carimbo do aprovador e limpo pelo flow.');
        System.assertEquals(n1.Id, c.Aprovador_Alvo_N1__c, 'O alvo fica, e o motor que o recalcula.');
        System.assertEquals(0, pendentes(o.Id), 'Nao pode sobrar processo de aprovacao pendente.');
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstanceWorkitem
                                WHERE ProcessInstance.TargetObjectId = :o.Id],
            'Nao pode sobrar work item na fila de ninguem.');
    }

    // ── 2. Reapresentacao pos-recall com o aprovador recalculado ──────────────────
    // Entre o recall e a reapresentacao a matriz muda de aprovador. O ciclo novo tem de
    // seguir o aprovador novo, e nao o que estava carimbado no ciclo retirado.
    @isTest static void reapresentacao_pos_recall_recalcula_aprovador() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        User n1Antigo = aps[0];
        User n1Novo = aps[1];
        Regra_Aprovacao__c r = regra(kam, 'rc2', 250000, n1Antigo.Id, null);
        Opportunity o = novaOpp(kam, 'Resub');
        correrMotor(o.Id);

        Test.startTest();
        processar(workitemPendente(o.Id), 'Removed');
        // a matriz passa a apontar para outro director
        update new Regra_Aprovacao__c(Id = r.Id, Aprovador_N1__c = n1Novo.Id);
        // reapresentacao pelo caminho do Guiar Pipeline: o Update_PreMotor limpa o estado e
        // repoe a fase antes de o motor correr (aqui reproduzido com o mesmo par de DMLs)
        update new Opportunity(Id = o.Id, Approval_Status__c = null,
            StageName = 'Aprovação Interna', Stage_Update_Via_Flow__c = true);
        correrMotor(o.Id);
        Test.stopTest();

        Opportunity c = [SELECT Approval_Status__c, Requer_Aprovacao__c,
                                Aprovador_Alvo_N1__c, G2_L1_Aprovador__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Aguarda L1', c.Approval_Status__c, 'O ciclo novo arranca em L1.');
        System.assertEquals(n1Novo.Id, c.Aprovador_Alvo_N1__c, 'O motor recalculou o alvo.');
        // O carimbo e' escrito na DECISAO e nao na submissao (SC_Carimbo_Aprovador,
        // a partir do ActorId do ProcessInstanceStep). O ciclo novo nasce sem carimbo nenhum, que e'
        // a forma mais forte de garantir o que este teste sempre quis: nao herdar o aprovador antigo.
        System.assertEquals(null, c.G2_L1_Aprovador__c,
            'O ciclo novo nasce sem carimbo: so quem decidir e que fica escrito.');
        System.assertEquals(1, pendentes(o.Id), 'A reapresentacao gera um pedido novo.');
        System.assertEquals(n1Novo.Id,
            [SELECT ActorId FROM ProcessInstanceWorkitem
             WHERE ProcessInstance.TargetObjectId = :o.Id AND ProcessInstance.Status = 'Pending' LIMIT 1].ActorId,
            'O work item novo esta na fila do aprovador novo.');
    }

    // ── 3. Recall em L2, com a cadeia ja a meio ───────────────────────────────────
    // O N1 aprovou (a data de L1 fica carimbada) e o pedido esta na mao do N2. O recall tem
    // de desfazer tambem o que ja tinha sido carimbado, senao o ciclo seguinte herda a data.
    @isTest static void recall_em_L2_cadeia_a_meio() {
        User kam = comercial();
        List<User> aps = aprovadores(kam.Id, 2);
        User n1 = aps[0];
        User n2 = aps[1];
        regra(kam, 'rc3', 120000, n1.Id, n2.Id); // Amount 150k fura os dois tectos -> N1 + N2
        Opportunity o = novaOpp(kam, 'L2');
        correrMotor(o.Id);
        System.assertEquals(true, [SELECT Requer_N2__c FROM Opportunity WHERE Id = :o.Id].Requer_N2__c,
            'Pre-condicao: a cadeia tem de exigir N2.');

        Test.startTest();
        Id wiL1 = workitemPendente(o.Id);
        System.runAs(n1) { processar(wiL1, 'Approve'); }
        Opportunity emL2 = [SELECT Approval_Status__c, G2_L1_Data_Aprovacao__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Aguarda L2', emL2.Approval_Status__c, 'Pre-condicao: o pedido esta em N2.');
        System.assertNotEquals(null, emL2.G2_L1_Data_Aprovacao__c, 'Pre-condicao: L1 ficou carimbado.');
        processar(workitemPendente(o.Id), 'Removed');
        Test.stopTest();

        Opportunity c = [SELECT Approval_Status__c, Requer_Aprovacao__c, StageName,
                                G2_L1_Aprovador__c, G2_L2_Aprovador__c,
                                G2_L1_Data_Aprovacao__c, G2_L2_Data_Aprovacao__c,
                                Aprovador_Alvo_N1__c, Aprovador_Alvo_N2__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Recolhido', c.Approval_Status__c);
        System.assertEquals(false, c.Requer_Aprovacao__c);
        System.assertEquals('Em Elaboração', c.StageName);
        System.assertEquals(null, c.G2_L1_Data_Aprovacao__c,
            'A data de aprovacao do ciclo retirado nao pode sobreviver ao recall.');
        System.assertEquals(null, c.G2_L2_Data_Aprovacao__c);
        System.assertEquals(null, c.G2_L1_Aprovador__c);
        System.assertEquals(null, c.G2_L2_Aprovador__c);
        System.assertEquals(n1.Id, c.Aprovador_Alvo_N1__c, 'Os alvos ficam intactos.');
        System.assertEquals(n2.Id, c.Aprovador_Alvo_N2__c, 'Os alvos ficam intactos.');
        System.assertEquals(0, pendentes(o.Id));
    }

    // ── 4. Recall nao e rejeicao ──────────────────────────────────────────────────
    // Retirar um pedido nao e o mesmo que ser recusado: nao carimba quem/porque/quando
    // recusou nem entra no historico de revisoes como recusa interna.
    @isTest static void recall_nao_e_rejeicao() {
        User kam = comercial();
        User n1 = aprovadores(kam.Id, 1)[0];
        regra(kam, 'rc4', 250000, n1.Id, null);
        Opportunity o = novaOpp(kam, 'NaoRej');
        correrMotor(o.Id);

        Test.startTest();
        processar(workitemPendente(o.Id), 'Removed');
        Test.stopTest();

        Opportunity c = [SELECT Approval_Status__c, G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c, G2_Data_Rejeicao__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Recolhido', c.Approval_Status__c, 'Estado proprio, nao Recusado.');
        System.assertEquals(null, c.G2_Rejeitado_Por__c, 'Ninguem recusou.');
        System.assertEquals(null, c.G2_Motivo_Rejeicao__c, 'Nao ha motivo de recusa a inventar.');
        System.assertEquals(null, c.G2_Data_Rejeicao__c, 'Nao ha data de recusa.');
        System.assertEquals(0, [SELECT COUNT() FROM Revisao_Proposta__c
                                WHERE Oportunidade__c = :o.Id AND Origem__c = 'Recusa interna'],
            'O recall nao entra no historico como recusa interna.');
    }
}