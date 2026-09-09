/**
 * SC_RevisaoPropostaServiceTest (B.2)
 * Cobre os dois caminhos da revisao: pedido do cliente (invocavel) e recusa interna,
 * mais o calculo de margem.
 */
@isTest
private class SC_RevisaoPropostaServiceTest {

    private static Opportunity criarOppEmNegociacao() {
        Account a = new Account(Name = 'Conta Teste Revisao');
        insert a;
        // Insert directo em "Em Negociacao": ISCHANGED(StageName) e false no insert,
        // logo a VR de stage-via-flow nao dispara. Amount/Custo satisfazem as VRs.
        Opportunity o = new Opportunity(
            Name = 'Opp Teste Revisao',
            AccountId = a.Id,
            StageName = 'Em Negociação',
            CloseDate = Date.today().addMonths(2),
            Empresa_Lider__c = 'Sinaltech',
            Amount = 350000,
            Custo_Estimado__c = 280000,
            Versao_Proposta__c = 1
        );
        insert o;
        return o;
    }

    @isTest
    static void revisaoPedidoCliente_versionaEDevolveAElaboracao() {
        Opportunity o = criarOppEmNegociacao();

        SC_RevisaoPropostaService.Request req = new SC_RevisaoPropostaService.Request();
        req.opportunityId = o.Id;
        req.motivo = 'Preço (aumentar)';
        req.nota = 'Cliente pediu âmbito adicional na negociação';
        req.novoValor = 400000;
        req.novoCusto = 300000;

        Test.startTest();
        List<SC_RevisaoPropostaService.Result> res =
            SC_RevisaoPropostaService.registarRevisaoCliente(new List<SC_RevisaoPropostaService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'Devolve um resultado');
        System.assertEquals(2, res[0].novaVersao, 'Versao incrementa para 2');

        Opportunity rec = [SELECT StageName, Amount, Custo_Estimado__c, Versao_Proposta__c,
                                  Approval_Status__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Em Elaboração', rec.StageName, 'Volta a Em Elaboracao');
        System.assertEquals(400000, rec.Amount, 'Valor actualizado');
        System.assertEquals(300000, rec.Custo_Estimado__c, 'Custo actualizado');
        System.assertEquals(2, rec.Versao_Proposta__c, 'Versao da proposta = 2');
        System.assertEquals(null, rec.Approval_Status__c, 'Approval Status limpo');

        Revisao_Proposta__c rev = [SELECT Origem__c, Motivo__c, Versao__c, Valor_Antes__c,
                                          Valor_Depois__c, Custo_Antes__c, Custo_Depois__c,
                                          Margem_Antes__c, Margem_Depois__c
                                   FROM Revisao_Proposta__c WHERE Oportunidade__c = :o.Id];
        System.assertEquals('Pedido do cliente', rev.Origem__c, 'Origem correcta');
        System.assertEquals('Preço (aumentar)', rev.Motivo__c, 'Motivo guardado');
        System.assertEquals(2, rev.Versao__c, 'Versao da revisao');
        System.assertEquals(350000, rev.Valor_Antes__c, 'Valor antes');
        System.assertEquals(400000, rev.Valor_Depois__c, 'Valor depois');
        System.assertEquals(20, rev.Margem_Antes__c, 'Margem antes 20%');
        System.assertEquals(25, rev.Margem_Depois__c, 'Margem depois 25%');
    }

    @isTest
    static void revisaoRecusa_criaRegistoNoHistorico() {
        Opportunity o = criarOppEmNegociacao();

        Test.startTest();
        SC_RevisaoPropostaService.registarRevisaoRecusa(
            new Set<Id>{ o.Id },
            new Map<Id, String>{ o.Id => 'Margem abaixo do mínimo aceitável' }
        );
        Test.stopTest();

        Revisao_Proposta__c rev = [SELECT Origem__c, Nota__c, Versao__c, Valor_Antes__c, Valor_Depois__c
                                   FROM Revisao_Proposta__c WHERE Oportunidade__c = :o.Id];
        System.assertEquals('Recusa interna', rev.Origem__c, 'Origem recusa');
        System.assertEquals('Margem abaixo do mínimo aceitável', rev.Nota__c, 'Motivo da recusa na nota');
        System.assertEquals(1, rev.Versao__c, 'Versao mantem-se (sem novos valores)');
        System.assertEquals(rev.Valor_Antes__c, rev.Valor_Depois__c, 'Sem alteracao de valor na recusa');
    }

    // ═══════════ Revisao de uma proposta JA APROVADA (fecho do ciclo) ═══════════
    //
    // O caminho que os testes anteriores nao tocavam: a opp ja passou pelo Approval Process
    // ate ao fim. Nesse estado o Approval Process NAO repoe o Requer_Aprovacao__c (so a
    // recallAction SC_AP_Rec_Requer_Off o faz), logo a opp fica com:
    //     Requer_Aprovacao__c = true, Approval_Status__c = Aprovado, Aprovador_Alvo_N1 preenchido
    //
    // Quando a revisao limpa o Approval_Status__c, essa e' exactamente a condicao de entrada do
    // SC_AutoSubmit_Aprovacao (Requer = true AND Approval_Status em branco AND alvo preenchido),
    // que dispara na transicao. Sem repor o Requer_Aprovacao__c, a revisao ressubmete sozinha,
    // ao aprovador do ciclo anterior, e o KAM fica outra vez com o registo trancado
    // (recordEditability = AdminOnly) sem chegar a rever valor nenhum.
    //
    // E' a mesma familia de defeito do ADR-010 (reset de estado na rejeicao) e do recall, e
    // fecha-se da mesma maneira: quem encerra o ciclo desarma o auto-submit, e o motor volta a
    // arma-lo com o aprovador fresco quando a opp reavanca pelo Guiar Pipeline.

    private static User comercial() {
        return [SELECT Id FROM User WHERE Profile.Name = 'End User' AND IsActive = true LIMIT 1];
    }

    private static Opportunity oppParaAprovacao(User dono) {
        Account a = new Account(Name = 'Revisao Pos Aprovacao'); insert a;
        Opportunity o = new Opportunity(
            Name = 'Opp Revisao Pos Aprovacao', AccountId = a.Id, OwnerId = dono.Id,
            StageName = 'Aprovação Interna', CloseDate = Date.today().addMonths(2),
            Empresa_Lider__c = 'Sinalcabo', Amount = 150000, Custo_Estimado__c = 90000,
            Direccao_Negocio__c = 'IT', Area_Negocio__c = 'Gestão Comercial',
            Tipo_Negocio__c = 'Box Moving', Versao_Proposta__c = 1, Approval_Status__c = null
        );
        insert o;
        return o;
    }

    // Regra de um so nivel: tecto N0 100k, opp de 150k -> nivel 1 -> so N1.
    private static void regraUmNivel(User dono, Id aprovador) {
        insert new Regra_Aprovacao__c(
            Name = 'R Revisao', Colaborador__c = dono.Id,
            Direccao__c = 'IT', Area__c = 'Gestão Comercial', Tipo_Negocio__c = 'Box Moving',
            Valor_N0__c = 100000, Condicao__c = 'Só Valor',
            Aprovador_N1__c = aprovador, Activa__c = true,
            Chave__c = dono.Id + '|Box Moving|Gestão Comercial'
        );
    }

    private static Integer pendentes(Id oppId) {
        return [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :oppId AND Status = 'Pending'];
    }

    @isTest
    static void revisao_de_opp_aprovada_nao_ressubmete_sozinha() {
        User kam = comercial();
        User n1 = [SELECT Id FROM User WHERE IsActive = true AND Id != :kam.Id LIMIT 1];
        regraUmNivel(kam, n1.Id);
        Opportunity o = oppParaAprovacao(kam);

        // ciclo completo: o motor submete e o N1 aprova
        SC_AvaliacaoAprovacao.Request av = new SC_AvaliacaoAprovacao.Request();
        av.opportunityId = o.Id;
        SC_AvaliacaoAprovacao.avaliar(new List<SC_AvaliacaoAprovacao.Request>{ av });

        Id workitem = [SELECT Id FROM ProcessInstanceWorkitem
                       WHERE ProcessInstance.TargetObjectId = :o.Id
                         AND ProcessInstance.Status = 'Pending' LIMIT 1].Id;
        Approval.ProcessWorkitemRequest pwr = new Approval.ProcessWorkitemRequest();
        pwr.setAction('Approve');
        pwr.setWorkitemId(workitem);
        System.runAs(n1) { Approval.process(pwr); }

        Opportunity aprovada = [SELECT StageName, Approval_Status__c, Requer_Aprovacao__c,
                                       Aprovador_Alvo_N1__c, G2_L1_Aprovador__c,
                                       G2_L1_Data_Aprovacao__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Aprovado', aprovada.Approval_Status__c, 'Pre-condicao: ciclo fechado como aprovado.');
        System.assertEquals('Proposta Enviada', aprovada.StageName,
            'Pre-condicao: a aprovacao final poe a opp em Proposta Enviada, onde a revisao e permitida.');
        System.assertEquals(true, aprovada.Requer_Aprovacao__c,
            'Pre-condicao do defeito: a aprovacao final NAO repoe o Requer_Aprovacao a false.');
        System.assertEquals(n1.Id, aprovada.Aprovador_Alvo_N1__c,
            'Pre-condicao do defeito: o alvo do ciclo anterior fica gravado.');
        // O carimbo de quem aprovou e' escrito em caminho assincrono na decisao
        // (SC_Carimbo_Aprovador), e trabalho assincrono num teste so' corre no
        // stopTest. Aqui ainda nao chegou; a pre-condicao com dentes e' a data, logo abaixo,
        // que e' field update sincrono do proprio Approval Process.
        System.assertEquals(null, aprovada.G2_L1_Aprovador__c,
            'Pre-condicao: o carimbo assincrono ainda nao correu neste ponto do teste.');
        System.assertNotEquals(null, aprovada.G2_L1_Data_Aprovacao__c, 'Pre-condicao: a data de L1 ficou.');
        System.assertEquals(0, pendentes(o.Id), 'Pre-condicao: nao ha pedido em aberto antes da revisao.');

        SC_RevisaoPropostaService.Request req = new SC_RevisaoPropostaService.Request();
        req.opportunityId = o.Id;
        req.motivo = 'Preço (baixar)';
        req.nota = 'Cliente pediu desconto depois da aprovação';
        req.novoValor = 140000;
        req.novoCusto = 90000;

        Test.startTest();
        SC_RevisaoPropostaService.registarRevisaoCliente(new List<SC_RevisaoPropostaService.Request>{ req });
        Test.stopTest();

        Opportunity depois = [SELECT StageName, Approval_Status__c, Requer_Aprovacao__c,
                                     Aprovador_Alvo_N1__c, Amount, G2_L1_Aprovador__c,
                                     G2_L1_Data_Aprovacao__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(0, pendentes(o.Id),
            'A revisao NAO pode abrir um pedido de aprovacao sozinha: quem re-submete e o KAM, pelo Guiar Pipeline.');
        System.assertEquals(null, depois.Approval_Status__c,
            'Se ficasse em Aguarda L1, era o auto-submit a disparar na limpeza do estado.');
        System.assertEquals(false, depois.Requer_Aprovacao__c,
            'A revisao fecha o ciclo, logo desarma o auto-submit ate o motor o rearmar com o aprovador fresco.');
        System.assertEquals('Em Elaboração', depois.StageName, 'A opp volta a ser editavel pelo KAM.');
        System.assertEquals(140000, depois.Amount, 'Os novos valores ficaram gravados.');
        System.assertEquals(n1.Id, depois.Aprovador_Alvo_N1__c,
            'O alvo antigo fica; e o motor que o recalcula no reavanco, como no recall.');
        System.assertEquals(null, depois.G2_L1_Aprovador__c,
            'O carimbo do ciclo fechado tem de sair, e o carimbo assincrono do ciclo morto nao o pode repor: '
            + 'o SC_Carimbo_Aprovador so escreve com o ciclo vivo, e a revisao poe o estado em branco.');
        System.assertEquals(null, depois.G2_L1_Data_Aprovacao__c,
            'A data de aprovacao do ciclo fechado nao pode sobreviver a revisao.');
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstanceWorkitem
                                WHERE ProcessInstance.TargetObjectId = :o.Id
                                  AND ProcessInstance.Status = 'Pending'],
            'Nao pode cair um work item novo na fila do aprovador do ciclo anterior.');
    }

    @isTest
    static void calcularMargem_casosFronteira() {
        System.assertEquals(25, SC_RevisaoPropostaService.calcularMargem(400000, 300000), '25%');
        System.assertEquals(0, SC_RevisaoPropostaService.calcularMargem(0, 100), 'Valor zero devolve 0');
        System.assertEquals(0, SC_RevisaoPropostaService.calcularMargem(null, 100), 'Valor nulo devolve 0');
        System.assertEquals(100, SC_RevisaoPropostaService.calcularMargem(100, null), 'Custo nulo = margem total');
    }
}