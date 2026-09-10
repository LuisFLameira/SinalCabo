/**
 * Testes do trigger do evento SC_NOS_Polling__e, que é onde a cadeia de leitura arranca.
 *
 * O evento é entregue com `Test.getEventBus().deliver()`, porque numa transacção de teste
 * a entrega não acontece sozinha. O que se assere é o efeito: o lote que o trigger abriu e
 * o passo que ele pôs na fila.
 *
 * Quem executa o trigger na org é o utilizador do PlatformEventSubscriberConfig, e isso
 * não se pode simular num teste: prova-se na org, pelo CreatedBy do lote.
 */
@IsTest
private class SC_NosPollingTriggerTest {
    private static void semLinhas() {
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));
    }

    @IsTest
    static void pedidoSemJanelaArrancaACadeiaDasAbertas() {
        SC_NosTestDados.catalogo();
        semLinhas();

        Test.startTest();
        SC_NosPollingScheduler.publicar(SC_NosConfig.CORRIDA_ABERTAS, null, null, 'Teste');
        Test.getEventBus().deliver();
        Test.stopTest();

        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Estado__c, Janela_Inicio__c, Janela_Fim__c
            FROM Lote_Integracao__c LIMIT 1
        ];
        Assert.areEqual('Abertas', lote.Tipo_Corrida__c, 'Um pedido sem janela é a cadeia normal.');
        Assert.areEqual('Concluído', lote.Estado__c, 'E o passo correu.');
        Long horas = (lote.Janela_Fim__c.getTime() - lote.Janela_Inicio__c.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(48, horas, 'A janela é a das abertas.');
    }

    @IsTest
    static void pedidoComJanelaLeSoAquelaJanela() {
        SC_NosTestDados.catalogo();
        semLinhas();
        Datetime fim = Datetime.now();
        Datetime inicio = fim.addHours(-2);

        Test.startTest();
        SC_NosPollingScheduler.publicar(SC_NosConfig.CORRIDA_FECHADAS, inicio, fim, 'Teste');
        Test.getEventBus().deliver();
        Test.stopTest();

        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Janela_Inicio__c, Janela_Fim__c, Proxima_Chegada_Esperada__c
            FROM Lote_Integracao__c LIMIT 1
        ];
        Assert.areEqual('Fechadas', lote.Tipo_Corrida__c, 'O tipo pedido é o que corre.');
        Long horas = (lote.Janela_Fim__c.getTime() - lote.Janela_Inicio__c.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(2, horas, 'A janela é a que veio no evento.');
        Assert.isNull(lote.Proxima_Chegada_Esperada__c, 'Uma corrida de janela não promete voltar.');
        Assert.areEqual(1, [SELECT COUNT() FROM Lote_Integracao__c], 'E não encadeia os passos seguintes.');
    }

    @IsTest
    static void travaoLigadoNaoDeixaOTriggerAbrirLote() {
        SC_NosConfig.estado().Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        Test.startTest();
        SC_NosPollingScheduler.publicar(SC_NosConfig.CORRIDA_ABERTAS, null, null, 'Teste');
        SC_NosPollingScheduler.publicar(
            SC_NosConfig.CORRIDA_MANUAL, Datetime.now().addHours(-1), Datetime.now(), 'Teste'
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(
            0, [SELECT COUNT() FROM Lote_Integracao__c],
            'As regras de arranque valem para quem executa o evento, com janela ou sem ela.'
        );
    }

    @IsTest
    static void listaVaziaOuNulaNaoFazNada() {
        Test.startTest();
        SC_NosPollingScheduler.executar(null);
        SC_NosPollingScheduler.executar(new List<SC_NOS_Polling__e>());
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'Sem pedidos não se abre lote nenhum.');
    }
}