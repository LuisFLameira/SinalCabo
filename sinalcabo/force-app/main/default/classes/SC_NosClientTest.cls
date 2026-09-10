/**
 * Testes do cliente HTTP e da classificação da resposta. Cobre os dois: o cliente só
 * monta o URL e devolve o que a SC_NosResponse classificou, e é a classificação que
 * decide todo o comportamento de erro do polling.
 */
@IsTest
private class SC_NosClientTest {
    private static final Datetime INICIO = Datetime.newInstanceGmt(2026, 8, 4, 7, 0, 0);
    private static final Datetime FIM = Datetime.newInstanceGmt(2026, 8, 4, 7, 59, 59);

    private static SC_NosMockFactory montar(SC_NosMockFactory.Resposta resposta) {
        SC_NosMockFactory mock = new SC_NosMockFactory().registarOmissao(resposta);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listagemComSucessoTrazAsTarefas() {
        SC_NosMockFactory mock = montar(SC_NosMockFactory.ok('SC_NosFx_ListaOk'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.OK, resposta.situacao, 'result_code 0 é sucesso na listagem.');
        Assert.areEqual(200, resposta.codigoHttp, 'A NOS responde 200 quando chega ao backend.');
        Assert.areEqual(0, resposta.resultCode, 'O result_code de sucesso da listagem é zero.');
        Assert.areEqual(56, resposta.registos, 'O fixture da listagem tem 56 tarefas.');
        Assert.isTrue(resposta.ok(), 'Uma listagem com tarefas é resposta boa.');
        Assert.areEqual('Sucesso', resposta.resultadoDoLote(), 'O lote fecha com Sucesso.');
        Assert.areEqual(1, mock.numeroDeChamadas(), 'Um callout por chamada ao cliente.');
    }

    @IsTest
    static void aJanelaVaiEmHoraLocalComOEspacoCodificado() {
        SC_NosMockFactory mock = montar(SC_NosMockFactory.ok('SC_NosFx_ListaOk'));

        Test.startTest();
        SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        String url = mock.urlDaChamada(0);
        Assert.isTrue(
            url.contains('startTime=2026-08-04%2008:00:00'),
            'As 07:00 GMT são as 08:00 em Portugal, e é a hora local que a NOS espera: ' + url
        );
        Assert.isTrue(url.contains('endTime=2026-08-04%2008:59:59'), 'O fim da janela segue a mesma regra: ' + url);
        Assert.isFalse(url.contains('status='), 'Sem estado pedido, o parâmetro não vai no URL: ' + url);
        Assert.isTrue(url.startsWith('callout:SC_NOS_FFM_API/workitem/listByPartner'), 'Caminho da listagem errado: ' + url);
    }

    @IsTest
    static void listagemDeFechadasLevaOEstadoNoUrl() {
        SC_NosMockFactory mock = montar(SC_NosMockFactory.ok('SC_NosFx_ListaOk'));

        Test.startTest();
        SC_NosClient.listar(INICIO, FIM, 'CLOSED');
        Test.stopTest();

        Assert.isTrue(mock.urlDaChamada(0).contains('status=CLOSED'), 'As fechadas pedem-se com status=CLOSED.');
    }

    @IsTest
    static void listagemVaziaEDiferenteDeListagemComTarefas() {
        montar(SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.VAZIO, resposta.situacao, 'Sem linhas, a resposta é Vazio.');
        Assert.isTrue(resposta.ok(), 'Vazio continua a ser resposta boa.');
        Assert.areEqual('Vazio', resposta.resultadoDoLote(), 'O lote fecha com Vazio.');
    }

    @IsTest
    static void janelaAcimaDeSetentaEDuasHorasDaSetecentosEDois() {
        montar(SC_NosMockFactory.ok('SC_NosFx_Lista702'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, 'CLOSED');
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.JANELA, resposta.situacao, 'O 702 é janela recusada.');
        Assert.areEqual(702, resposta.resultCode, 'O result_code tem de vir lido.');
        Assert.isFalse(resposta.ok(), 'Uma janela recusada não é resposta boa.');
        Assert.areEqual('Erro', resposta.resultadoDoLote(), 'O lote fecha com Erro.');
        Assert.isTrue(resposta.resumo().startsWith('JANELA'), 'O resumo nomeia a classe: ' + resposta.resumo());
    }

    @IsTest
    static void corteDoGatewayAosSessentaSegundosEhTimeout() {
        montar(SC_NosMockFactory.ok('SC_NosFx_504').comCodigo(504).comTipo('text/plain'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, 'CLOSED');
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.TIMEOUT, resposta.situacao, 'O 504 do gateway é timeout.');
        Assert.isTrue(resposta.corteDeGateway(), 'Um timeout conta como corte do gateway.');
        Assert.areEqual('Timeout', resposta.resultadoDoLote(), 'O lote fecha com Timeout.');
    }

    @IsTest
    static void enderecoSuspensoNoWso2EhSuspensao() {
        montar(SC_NosMockFactory.ok('SC_NosFx_500Wso2').comCodigo(500).comTipo('application/xml'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.SUSPENSO, resposta.situacao, 'O 303001 do WSO2 é suspensão.');
        Assert.isTrue(resposta.suspensoNaOrigem(), 'A suspensão vem da origem.');
        Assert.isFalse(resposta.corteDeGateway(), 'Uma suspensão não é um corte.');
    }

    @IsTest
    static void excepcaoDeCalloutNaoSaiDoCliente() {
        montar(SC_NosMockFactory.excepcao('Read timed out'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.TIMEOUT, resposta.situacao, 'Uma excepção de rede conta como corte.');
        Assert.isTrue(
            resposta.mensagem.contains('Read timed out'),
            'A mensagem da excepção tem de ficar registada: ' + resposta.mensagem
        );
        Assert.isNull(resposta.codigoHttp, 'Sem resposta não há código HTTP.');
    }

    @IsTest
    static void corpoQueNaoEhJsonEhErro() {
        montar(SC_NosMockFactory.http(200, '<html>portal de manutenção</html>'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.ERRO, resposta.situacao, 'Um corpo que não é JSON é erro.');
        Assert.isTrue(
            resposta.mensagem.startsWith('Resposta que não é JSON'),
            'A mensagem tem de dizer o que aconteceu: ' + resposta.mensagem
        );
    }

    @IsTest
    static void resultCodeInesperadoEhErro() {
        montar(SC_NosMockFactory.http(200, '{"result_code":999,"result_message":"Boom","result_data":{"data":[]}}'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.ERRO, resposta.situacao, 'Um result_code fora do esperado é erro.');
        Assert.areEqual(999, resposta.resultCode, 'O result_code tem de vir lido mesmo quando é erro.');
    }

    @IsTest
    static void detalheComSucessoUsaOutraEscalaDeCodigo() {
        SC_NosMockFactory mock = montar(SC_NosMockFactory.ok('SC_NosFx_DetalheOk'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.detalhe('TAS000002537686');
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.OK, resposta.situacao, 'No detalhe o sucesso é result_code 200.');
        Assert.areEqual(200, resposta.resultCode, 'O detalhe responde 200 e não 0.');
        Assert.areEqual(1, resposta.registos, 'O detalhe traz um objecto e não uma lista.');
        Assert.isTrue(
            mock.urlDaChamada(0).contains('getByWorkitemId?ID=TAS000002537686'),
            'O detalhe pede-se pelo identificador completo: ' + mock.urlDaChamada(0)
        );
    }

    @IsTest
    static void detalheDeOrdemInexistenteEhAusente() {
        montar(SC_NosMockFactory.ok('SC_NosFx_Detalhe701'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.detalhe('CRQ000001001020');
        Test.stopTest();

        Assert.areEqual(SC_NosResponse.Classe.AUSENTE, resposta.situacao, 'O 701 diz que a ordem não existe na NOS.');
        Assert.areEqual(701, resposta.resultCode, 'O result_code tem de vir lido.');
    }

    @IsTest
    static void listagemComDataObjectoEmVezDeListaContaUm() {
        montar(SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":{"ID":"TAS1"}}}'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(1, resposta.registos, 'Um data que é objecto conta como um registo.');
        Assert.areEqual(SC_NosResponse.Classe.OK, resposta.situacao, 'E continua a ser resposta boa.');
    }

    @IsTest
    static void respostaSemResultDataNaoRebenta() {
        montar(SC_NosMockFactory.http(200, '{"result_code":0}'));

        Test.startTest();
        SC_NosResponse resposta = SC_NosClient.listar(INICIO, FIM, null);
        Test.stopTest();

        Assert.areEqual(0, resposta.registos, 'Sem result_data não há registos.');
        Assert.areEqual(SC_NosResponse.Classe.VAZIO, resposta.situacao, 'E a resposta é Vazio.');
    }
}