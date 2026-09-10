/**
 * Testes da carga histórica: os lotes com a resposta já guardada passam pelo pipeline,
 * pela ordem cronológica das janelas, sem nunca se chamar a NOS. Nenhum destes testes
 * tem mock, e é isso que se prova.
 */
@IsTest
private class SC_NosCargaHistoricaQueueableTest {
    private static Lote_Integracao__c carga(Datetime inicio, String corpo) {
        Lote_Integracao__c lote = SC_NosLote.abrirRepetivel(
            SC_NosConfig.CORRIDA_CARGA, inicio, inicio.addHours(24)
        );
        lote.Estado__c = SC_NosLote.ESTADO_CONCLUIDO;
        lote.Resultado__c = 'Sucesso';
        lote.Payload__c = corpo;
        update lote;
        return lote;
    }

    private static Integer reprocessamentosDe(Id loteId) {
        return [SELECT COUNT() FROM Lote_Integracao__c WHERE Reprocessado_De__c = :loteId];
    }

    @IsTest
    static void aCargaPassaOsLotesPeloPipelineSemChamarANos() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c lote = carga(
            Datetime.newInstanceGmt(2026, 8, 4, 0, 0, 0), SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );

        Test.startTest();
        System.enqueueJob(new SC_NosCargaHistoricaQueueable(new List<Id>{ lote.Id }));
        Test.stopTest();

        Assert.areEqual(
            56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL],
            'A carga cria as ordens do corpo guardado.'
        );
        Assert.areEqual(1, reprocessamentosDe(lote.Id), 'E deixa um lote de reprocessamento a apontar ao de carga.');
        Assert.areEqual(
            'Closed',
            [SELECT Status FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002533674' LIMIT 1].Status,
            'As que a NOS já dava por fechadas entram fechadas.'
        );
    }

    @IsTest
    static void aCargaTrataPoucosLotesPorTransaccao() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c primeiro = carga(
            Datetime.newInstanceGmt(2026, 8, 4, 0, 0, 0), SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );
        Lote_Integracao__c segundo = carga(
            Datetime.newInstanceGmt(2026, 8, 5, 0, 0, 0), SC_NosTestDados.fixture('SC_NosFx_ListaMista')
        );

        Test.startTest();
        System.enqueueJob(new SC_NosCargaHistoricaQueueable(
            new List<Id>{ primeiro.Id, segundo.Id }, 1
        ));
        Test.stopTest();

        Assert.areEqual(1, reprocessamentosDe(primeiro.Id), 'O primeiro da fila é tratado.');
        Assert.areEqual(0, reprocessamentosDe(segundo.Id), 'O segundo fica para a transacção seguinte.');
    }

    @IsTest
    static void porProcessarDevolveOsDeCargaAindaPorFazerEmOrdemDeJanela() {
        Lote_Integracao__c segundo = carga(Datetime.newInstanceGmt(2026, 8, 5, 0, 0, 0), '{}');
        Lote_Integracao__c primeiro = carga(Datetime.newInstanceGmt(2026, 8, 4, 0, 0, 0), '{}');
        SC_NosTestDados.lote();

        List<Id> porFazer = SC_NosCargaHistoricaQueueable.porProcessar();

        Assert.areEqual(2, porFazer.size(), 'Só os lotes de carga entram.');
        Assert.areEqual(primeiro.Id, porFazer[0], 'A janela mais antiga é a primeira a correr.');
        Assert.areEqual(segundo.Id, porFazer[1], 'E a mais recente é a última a escrever.');
    }

    @IsTest
    static void umLoteJaReprocessadoNaoVoltaAFila() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c lote = carga(
            Datetime.newInstanceGmt(2026, 8, 4, 0, 0, 0), SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );
        SC_NosReprocessador.reprocessar(lote.Id);

        Test.startTest();
        Assert.areEqual(0, SC_NosCargaHistoricaQueueable.porProcessar().size(),
            'Correr outra vez retoma onde ficou, não repete o que já entrou.');
        Assert.areEqual(0, SC_NosCargaHistoricaQueueable.arrancar(), 'E sem nada por fazer não enfileira nada.');
        Test.stopTest();
    }

    @IsTest
    static void arrancarPoeAFilaAAndar() {
        SC_NosTestDados.catalogo();
        carga(Datetime.newInstanceGmt(2026, 8, 4, 0, 0, 0), SC_NosTestDados.fixture('SC_NosFx_ListaOk'));

        Test.startTest();
        Integer quantos = SC_NosCargaHistoricaQueueable.arrancar();
        Test.stopTest();

        Assert.areEqual(1, quantos, 'Arranca com o que estiver por fazer.');
        Assert.areEqual(
            56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL],
            'E a fila corre até ao fim do que lhe deram.'
        );
    }

    @IsTest
    static void filaVaziaNaoFazNada() {
        Test.startTest();
        System.enqueueJob(new SC_NosCargaHistoricaQueueable(null, null));
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'Sem lotes na fila não se escreve nada.');
    }
}