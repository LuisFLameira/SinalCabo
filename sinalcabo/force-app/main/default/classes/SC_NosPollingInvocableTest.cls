/**
 * Testes da corrida com janela explícita, a que o Flow e os scripts de operação chamam.
 */
@IsTest
private class SC_NosPollingInvocableTest {
    @IsTest
    static void corridaManualLeAJanelaPedidaEParaAli() {
        SC_NosTestDados.catalogo();
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_ListaOk')
        ));
        Datetime fim = Datetime.now();
        Datetime inicio = fim.addHours(-1);

        Test.startTest();
        SC_NosPollingInvocable.Resposta resposta = SC_NosPollingInvocable.correr(
            SC_NosConfig.CORRIDA_MANUAL, inicio, fim
        );
        Test.stopTest();

        Assert.isTrue(resposta.arrancou, 'A corrida manual arranca.');
        Assert.isNotNull(resposta.loteId, 'E devolve o lote que abriu.');
        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Estado__c, Criados__c, Proxima_Chegada_Esperada__c
            FROM Lote_Integracao__c WHERE Id = :resposta.loteId
        ];
        Assert.areEqual('Manual', lote.Tipo_Corrida__c, 'O tipo de corrida é o que se pediu.');
        Assert.areEqual('Concluído', lote.Estado__c, 'O passo correu e fechou o lote.');
        Assert.areEqual(56, lote.Criados__c, 'E criou as ordens da janela.');
        Assert.isNull(lote.Proxima_Chegada_Esperada__c, 'Uma corrida manual não promete voltar.');
        Assert.areEqual(1, [SELECT COUNT() FROM Lote_Integracao__c], 'E não continua para os passos seguintes.');
    }

    @IsTest
    static void semJanelaContaAsHorasParaTras() {
        SC_NosTestDados.catalogo();
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));
        SC_NosPollingInvocable.Pedido pedido = new SC_NosPollingInvocable.Pedido();
        pedido.tipo = SC_NosConfig.CORRIDA_FECHADAS;
        pedido.horas = 3;

        Test.startTest();
        List<SC_NosPollingInvocable.Resposta> respostas = SC_NosPollingInvocable.executar(
            new List<SC_NosPollingInvocable.Pedido>{ pedido }
        );
        Test.stopTest();

        Assert.isTrue(respostas[0].arrancou, 'Sem janela explícita a corrida arranca na mesma.');
        Lote_Integracao__c lote = [
            SELECT Janela_Inicio__c, Janela_Fim__c FROM Lote_Integracao__c WHERE Id = :respostas[0].loteId
        ];
        Long horas = (lote.Janela_Fim__c.getTime() - lote.Janela_Inicio__c.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(3, horas, 'A janela conta as horas pedidas a partir de agora.');
    }

    @IsTest
    static void semTipoNemHorasValeUmaHoraManual() {
        SC_NosTestDados.catalogo();
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));

        Test.startTest();
        List<SC_NosPollingInvocable.Resposta> respostas = SC_NosPollingInvocable.executar(
            new List<SC_NosPollingInvocable.Pedido>{ new SC_NosPollingInvocable.Pedido() }
        );
        Test.stopTest();

        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Janela_Inicio__c, Janela_Fim__c
            FROM Lote_Integracao__c WHERE Id = :respostas[0].loteId
        ];
        Assert.areEqual('Manual', lote.Tipo_Corrida__c, 'Sem tipo pedido, a corrida é manual.');
        Long horas = (lote.Janela_Fim__c.getTime() - lote.Janela_Inicio__c.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(1, horas, 'Sem horas pedidas, lê-se a última hora.');
    }

    @IsTest
    static void janelaAoContrarioNaoArranca() {
        Datetime agora = Datetime.now();

        Test.startTest();
        SC_NosPollingInvocable.Resposta resposta = SC_NosPollingInvocable.correr(
            SC_NosConfig.CORRIDA_MANUAL, agora, agora.addHours(-1)
        );
        Test.stopTest();

        Assert.isFalse(resposta.arrancou, 'Uma janela que acaba antes de começar não arranca.');
        Assert.areEqual('A janela pedida acaba antes de começar.', resposta.mensagem, 'E diz porquê.');
        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'E não abre lote nenhum.');
    }

    @IsTest
    static void travaoDeEmergenciaTravaTodosOsPedidosDoLote() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();
        SC_NosPollingInvocable.Pedido um = new SC_NosPollingInvocable.Pedido();
        SC_NosPollingInvocable.Pedido dois = new SC_NosPollingInvocable.Pedido();
        dois.tipo = SC_NosConfig.CORRIDA_FECHADAS;

        Test.startTest();
        List<SC_NosPollingInvocable.Resposta> respostas = SC_NosPollingInvocable.executar(
            new List<SC_NosPollingInvocable.Pedido>{ um, dois }
        );
        Test.stopTest();

        Assert.areEqual(2, respostas.size(), 'Cada pedido leva a sua resposta.');
        for (SC_NosPollingInvocable.Resposta resposta : respostas) {
            Assert.isFalse(resposta.arrancou, 'Com o travão ligado nenhum pedido arranca.');
            Assert.areEqual('Travão de emergência ligado.', resposta.mensagem, 'E todos dizem porquê.');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'E não fica lixo na tabela de lotes.');
    }
}