@isTest
private class SC_RejeicaoStampServiceTest {

    private static Opportunity submeterEObterWorkitem(User comercial, User dir) {
        Account a = new Account(Name='RejStamp'); insert a;
        // Modelo por niveis (ADR-011): o nivel conta tectos ULTRAPASSADOS. Com autonomia
        // ate 100k e Amount 150k, "So Valor" da nivel 1 (so N1), logo a opp e submetida e
        // gera um work item pendente para rejeitar.
        insert new Regra_Aprovacao__c(Name='R rs', Colaborador__c=comercial.Id, Direccao__c='IT',
            Area__c='Gestão Comercial', Tipo_Negocio__c='Box Moving',
            Valor_N0__c=100000, Valor_N1__c=250000,
            Margem_Min_N1__c=5, Condicao__c='Só Valor', Aprovador_N1__c=dir.Id, Activa__c=true,
            Chave__c=comercial.Id+'|rs');
        Opportunity o = new Opportunity(Name='RejStamp Opp', StageName='Aprovação Interna',
            CloseDate=Date.today().addMonths(2), AccountId=a.Id, OwnerId=comercial.Id,
            Empresa_Lider__c='Sinalcabo', Amount=150000, Custo_Estimado__c=90000,
            Direccao_Negocio__c='IT', Area_Negocio__c='Gestão Comercial', Tipo_Negocio__c='Box Moving',
            Approval_Status__c=null);
        insert o;
        SC_AvaliacaoAprovacao.Request r=new SC_AvaliacaoAprovacao.Request(); r.opportunityId=o.Id;
        SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{r});
        return o;
    }

    // Rejeicao COM comentario -> grava ActorId (quem), Comments (motivo) e o nivel (L1).
    @isTest static void rejeicao_com_motivo() {
        User comercial=[SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        User dir=[SELECT Id FROM User WHERE IsActive=true AND Id!=:comercial.Id AND Profile.Name IN ('Diretor','Executive Sponsor','System Administrator') ORDER BY Profile.Name LIMIT 1]; // aprovador resolvido em runtime (era Id fixo Joao Machado)

        Test.startTest();
        Opportunity o = submeterEObterWorkitem(comercial, dir);
        Id wi=[SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId=:o.Id AND ProcessInstance.Status='Pending' LIMIT 1].Id;
        System.runAs(dir) {
            Approval.ProcessWorkitemRequest req=new Approval.ProcessWorkitemRequest();
            req.setAction('Reject'); req.setComments('Margem insuficiente'); req.setWorkitemId(wi);
            Approval.process(req);
        }
        Test.stopTest(); // o Queueable do carimbo corre aqui

        Opportunity c=[SELECT Approval_Status__c, G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c,
                              G2_Data_Rejeicao__c, G2_Nivel_Rejeicao__c
                       FROM Opportunity WHERE Id=:o.Id];
        System.assertEquals('Recusado', c.Approval_Status__c);
        System.assertEquals(dir.Id, c.G2_Rejeitado_Por__c, 'Quem rejeitou = o actor do step (Joao Machado).');
        System.assertEquals('Margem insuficiente', c.G2_Motivo_Rejeicao__c, 'Motivo = o Comments do step.');
        System.assertNotEquals(null, c.G2_Data_Rejeicao__c, 'A data continua a ser gravada pelo AP.');
        System.assertNotEquals(null, c.G2_Nivel_Rejeicao__c, 'O nivel da rejeicao tem de ser carimbado.');
        System.assertEquals(1, c.G2_Nivel_Rejeicao__c.intValue(), 'A rejeicao aconteceu em Aguarda L1, logo nivel 1.');
    }

    // Rejeicao SEM comentario -> grava quem, motivo fica VAZIO (nao inventa).
    @isTest static void rejeicao_sem_motivo() {
        User comercial=[SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        User dir=[SELECT Id FROM User WHERE IsActive=true AND Id!=:comercial.Id AND Profile.Name IN ('Diretor','Executive Sponsor','System Administrator') ORDER BY Profile.Name LIMIT 1];

        Test.startTest();
        Opportunity o = submeterEObterWorkitem(comercial, dir);
        Id wi=[SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId=:o.Id AND ProcessInstance.Status='Pending' LIMIT 1].Id;
        System.runAs(dir) {
            Approval.ProcessWorkitemRequest req=new Approval.ProcessWorkitemRequest();
            req.setAction('Reject'); req.setWorkitemId(wi); // sem comentario
            Approval.process(req);
        }
        Test.stopTest();

        Opportunity c=[SELECT G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c FROM Opportunity WHERE Id=:o.Id];
        System.assertEquals(dir.Id, c.G2_Rejeitado_Por__c, 'Quem rejeitou gravado mesmo sem comentario.');
        System.assertEquals(null, c.G2_Motivo_Rejeicao__c, 'Sem comentario -> motivo fica vazio (nao inventa).');
    }

    // Idempotencia / nao dispara em aprovacao: aprovar nao deve preencher os campos de rejeicao.
    @isTest static void aprovacao_nao_carimba_rejeicao() {
        User comercial=[SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        User dir=[SELECT Id FROM User WHERE IsActive=true AND Id!=:comercial.Id AND Profile.Name IN ('Diretor','Executive Sponsor','System Administrator') ORDER BY Profile.Name LIMIT 1];

        Test.startTest();
        Opportunity o = submeterEObterWorkitem(comercial, dir);
        Id wi=[SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId=:o.Id AND ProcessInstance.Status='Pending' LIMIT 1].Id;
        System.runAs(dir) {
            Approval.ProcessWorkitemRequest req=new Approval.ProcessWorkitemRequest();
            req.setAction('Approve'); req.setWorkitemId(wi);
            Approval.process(req);
        }
        Test.stopTest();

        Opportunity c=[SELECT StageName, G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c, G2_Nivel_Rejeicao__c FROM Opportunity WHERE Id=:o.Id];
        System.assertEquals('Proposta Enviada', c.StageName);
        System.assertEquals(null, c.G2_Rejeitado_Por__c, 'Aprovacao nao deve carimbar rejeicao.');
        System.assertEquals(null, c.G2_Motivo_Rejeicao__c, 'Aprovacao nao deve carimbar motivo.');
        System.assertEquals(null, c.G2_Nivel_Rejeicao__c, 'Aprovacao nao deve carimbar nivel.');
    }

    /**
     * C5: dois ciclos completos na mesma oportunidade. Submeter, rejeitar em L1, corrigir os
     * valores, ressubmeter, aprovar em L1 e rejeitar em L2. A ficha tem de mostrar a SEGUNDA
     * rejeicao (rejeitador, motivo e nivel), e o historico tem de ter as duas recusas.
     *
     * Antes do fix isto falhava: a guarda "&& G2_Rejeitado_Por__c == null" impedia o carimbo
     * da 2a rejeicao, e nenhuma via de reposicao limpa esse campo.
     */
    @isTest static void segunda_rejeicao_sobrescreve_a_primeira() {
        User comercial=[SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        List<User> aprovadores=[SELECT Id FROM User WHERE IsActive=true AND Id!=:comercial.Id
            AND Profile.Name IN ('Diretor','Executive Sponsor') ORDER BY Name LIMIT 2];
        Id dir1 = aprovadores[0].Id;
        Id dir2 = (aprovadores.size() > 1) ? aprovadores[1].Id : aprovadores[0].Id;

        Account a = new Account(Name='RejStamp2'); insert a;
        // N1 e N2 preenchidos: o mesmo registo serve os dois ciclos. Amount 150k cruza so' o
        // tecto N0 (nivel 1); no 2o ciclo, 300k cruza N0 e N1 (nivel 2), logo a cadeia vai a L2.
        insert new Regra_Aprovacao__c(Name='R rs2', Colaborador__c=comercial.Id, Direccao__c='IT',
            Area__c='Gestão Comercial', Tipo_Negocio__c='Box Moving',
            Valor_N0__c=100000, Valor_N1__c=250000,
            Margem_Min_N1__c=5, Condicao__c='Só Valor',
            Aprovador_N1__c=dir1, Aprovador_N2__c=dir2, Activa__c=true,
            Chave__c=comercial.Id+'|rs2');
        Opportunity o = new Opportunity(Name='RejStamp2 Opp', StageName='Aprovação Interna',
            CloseDate=Date.today().addMonths(2), AccountId=a.Id, OwnerId=comercial.Id,
            Empresa_Lider__c='Sinalcabo', Amount=150000, Custo_Estimado__c=90000,
            Direccao_Negocio__c='IT', Area_Negocio__c='Gestão Comercial', Tipo_Negocio__c='Box Moving',
            Approval_Status__c=null);
        insert o;

        // ---------- Ciclo 1: submeter e rejeitar em L1 ----------
        avaliar(o.Id);
        System.runAs(new User(Id=dir1)) { rejeitar(workitem(o.Id), 'Motivo A'); }

        // O Queueable enfileirado pelo trigger fora da janela start/stopTest so' correria no
        // stopTest, ou seja DEPOIS da 2a rejeicao, e carimbaria ele proprio os dados da 2a (o
        // servico le sempre o step de rejeicao mais recente), mascarando o que se quer testar.
        // Aborta-se, e faz-se o carimbo do 1o ciclo com o mesmo processar que esse job chamaria,
        // com o nivel que o trigger apurou (Aguarda L1 -> 1). A opp fica no estado real de quem
        // ja levou uma rejeicao, que e' a condicao de partida do 2o ciclo.
        abortarCarimbosPendentes();
        SC_RejeicaoStampService.processar(new Map<Id, Integer>{ o.Id => 1 });

        Opportunity c1=[SELECT Approval_Status__c, G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c
                        FROM Opportunity WHERE Id=:o.Id];
        System.assertEquals('Recusado', c1.Approval_Status__c, 'Ciclo 1 devia ter ficado Recusado.');
        System.assertEquals(dir1, c1.G2_Rejeitado_Por__c, 'Ciclo 1: rejeitador da 1a rejeicao.');
        System.assertEquals('Motivo A', c1.G2_Motivo_Rejeicao__c, 'Ciclo 1: motivo da 1a rejeicao.');

        // ---------- Ciclo 2: corrigir, ressubmeter, aprovar em L1 e rejeitar em L2 ----------
        Test.startTest();
        // o que o Guiar Pipeline faz no reavanco: novos valores e Approval_Status em branco
        update new Opportunity(Id=o.Id, Amount=300000, Custo_Estimado__c=180000, Approval_Status__c=null);
        avaliar(o.Id);
        System.runAs(new User(Id=dir1)) { aprovar(workitem(o.Id)); }   // L1 aprova, escala a L2
        System.runAs(new User(Id=dir2)) { rejeitar(workitem(o.Id), 'Motivo B'); }
        Test.stopTest(); // aqui corre o Queueable do carimbo da 2a rejeicao

        Opportunity c2=[SELECT Approval_Status__c, G2_Rejeitado_Por__c, G2_Motivo_Rejeicao__c,
                               G2_Nivel_Rejeicao__c, G2_Data_Rejeicao__c
                        FROM Opportunity WHERE Id=:o.Id];
        System.assertEquals('Recusado', c2.Approval_Status__c, 'Ciclo 2 devia ter ficado Recusado.');
        System.assertEquals(dir2, c2.G2_Rejeitado_Por__c,
            'A ficha tem de mostrar quem rejeitou da SEGUNDA vez, nao da primeira.');
        System.assertEquals('Motivo B', c2.G2_Motivo_Rejeicao__c,
            'A ficha tem de mostrar o motivo da SEGUNDA rejeicao, nao o da primeira.');
        System.assertNotEquals(null, c2.G2_Nivel_Rejeicao__c, 'O nivel da 2a rejeicao tem de ser carimbado.');
        System.assertEquals(2, c2.G2_Nivel_Rejeicao__c.intValue(),
            'A 2a rejeicao entrou em Aguarda L2, logo nivel 2.');
        System.assertNotEquals(null, c2.G2_Data_Rejeicao__c, 'A data e reescrita pelo AP em cada rejeicao.');
        System.assertEquals(2, [SELECT COUNT() FROM Revisao_Proposta__c
                                WHERE Oportunidade__c=:o.Id AND Origem__c='Recusa interna'],
            'Cada rejeicao deve deixar um registo de recusa no historico unificado.');
    }

    // O nivel so sai de um estado do circuito; de qualquer outro fica vazio em vez de assumir L1.
    @isTest static void nivel_so_sai_de_estado_do_circuito() {
        System.assertEquals(1, SC_RejeicaoStampService.nivelDoEstadoAnterior('Aguarda L1'));
        System.assertEquals(2, SC_RejeicaoStampService.nivelDoEstadoAnterior('Aguarda L2'));
        System.assertEquals(3, SC_RejeicaoStampService.nivelDoEstadoAnterior('Aguarda L3'));
        System.assertEquals(null, SC_RejeicaoStampService.nivelDoEstadoAnterior('Recolhido'));
        System.assertEquals(null, SC_RejeicaoStampService.nivelDoEstadoAnterior(null));
    }

    // ---------- utilitarios do teste dos dois ciclos ----------
    private static void abortarCarimbosPendentes() {
        for (AsyncApexJob j : [SELECT Id FROM AsyncApexJob
                               WHERE JobType='Queueable' AND Status IN ('Queued','Holding','Preparing')
                                 AND ApexClass.Name='SC_RejeicaoStampService']) {
            System.abortJob(j.Id);
        }
    }
    private static void avaliar(Id oppId) {
        SC_AvaliacaoAprovacao.Request r=new SC_AvaliacaoAprovacao.Request(); r.opportunityId=oppId;
        SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{r});
    }
    private static Id workitem(Id oppId) {
        return [SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId=:oppId AND ProcessInstance.Status='Pending' LIMIT 1].Id;
    }
    private static void rejeitar(Id wi, String comentario) {
        Approval.ProcessWorkitemRequest req=new Approval.ProcessWorkitemRequest();
        req.setAction('Reject'); req.setComments(comentario); req.setWorkitemId(wi);
        Approval.process(req);
    }
    private static void aprovar(Id wi) {
        Approval.ProcessWorkitemRequest req=new Approval.ProcessWorkitemRequest();
        req.setAction('Approve'); req.setWorkitemId(wi);
        Approval.process(req);
    }
}