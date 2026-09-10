/**
 * Testes da fábrica de mocks. Não dependem de nenhuma classe SC_Nos* de produção: provam
 * que a fábrica escolhe a regra certa, respeita a sequência, guarda as chamadas e serve os
 * fixtures SC_NosFx_* tal como a API os devolveu. Se um destes falhar, o problema está na
 * fábrica ou nos static resources, e não no cliente da API.
 */
@IsTest
private class SC_NosMockFactoryTest {
    private static final String URL_ABERTAS =
        'https://exemplo.invalid/v1/workitem/listByPartner?startTime=2026-09-01+00:00:00&endTime=2026-09-02+00:00:00';
    private static final String URL_FECHADAS = URL_ABERTAS + '&status=CLOSED';
    private static final String URL_DETALHE =
        'https://exemplo.invalid/v1/workitem/getByWorkitemId?workitemId=TAS000002537686';
    private static final String URL_TERRITORIOS = 'https://exemplo.invalid/v1/listTerritories?group=TL2-Sinalcabo';

    private static HttpResponse chamar(String url) {
        HttpRequest pedido = new HttpRequest();
        pedido.setEndpoint(url);
        pedido.setMethod('GET');
        return new Http().send(pedido);
    }

    @IsTest
    static void serveOCorpoDoStaticResource() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('listByPartner', SC_NosMockFactory.ok('SC_NosFx_ListaOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse resposta = chamar(URL_FECHADAS);
        Test.stopTest();

        Assert.areEqual(200, resposta.getStatusCode(), 'O fixture OK responde 200.');
        Assert.areEqual('application/json', resposta.getHeader('Content-Type'), 'Content-Type por omissão.');
        Map<String, Object> corpo = (Map<String, Object>) JSON.deserializeUntyped(resposta.getBody());
        Assert.areEqual(0, corpo.get('result_code'), 'A listagem de sucesso da NOS traz result_code 0.');
        Map<String, Object> dados = (Map<String, Object>) corpo.get('result_data');
        List<Object> tarefas = (List<Object>) dados.get('data');
        Assert.areEqual(56, tarefas.size(), 'O fixture das fechadas de 04/08 tem 56 tarefas.');
    }

    @IsTest
    static void distingueFechadasDeAbertasPelaAusenciaDoStatus() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('listByPartner', 'status=', SC_NosMockFactory.ok('SC_NosFx_ListaAbertas'))
            .registar('listByPartner', SC_NosMockFactory.ok('SC_NosFx_ListaOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String abertas = chamar(URL_ABERTAS).getBody();
        String fechadas = chamar(URL_FECHADAS).getBody();
        Test.stopTest();

        Assert.isTrue(abertas.contains('ASSIGNED_TO_COMPANY'), 'A listagem sem status traz ordens abertas.');
        Assert.isFalse(abertas.contains('"Status": "CLOSED"'), 'A listagem sem status nunca traz fechadas.');
        Assert.isTrue(fechadas.contains('"Status": "CLOSED"'), 'O URL com status=CLOSED traz as fechadas.');
    }

    @IsTest
    static void aPrimeiraRegraQueCasaGanha() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('getByWorkitemId', SC_NosMockFactory.ok('SC_NosFx_DetalheOk'))
            .registar('workitem', SC_NosMockFactory.ok('SC_NosFx_ListaOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String corpo = chamar(URL_DETALHE).getBody();
        Test.stopTest();

        Assert.isTrue(corpo.contains('CAI04-2C1'), 'O detalhe traz o elemento de rede da célula.');
        Assert.isTrue(corpo.contains('"result_code": 200'), 'O detalhe de sucesso da NOS traz result_code 200.');
    }

    @IsTest
    static void sequenciaDevolveUmaRespostaPorChamada() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar(
                'listByPartner',
                SC_NosMockFactory.sequencia(
                    new List<SC_NosMockFactory.Resposta>{
                        SC_NosMockFactory.ok('SC_NosFx_504').comCodigo(504).comTipo('text/plain'),
                        SC_NosMockFactory.ok('SC_NosFx_500Wso2').comCodigo(500).comTipo('application/xml'),
                        SC_NosMockFactory.ok('SC_NosFx_ListaOk')
                    }
                )
            );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse primeira = chamar(URL_FECHADAS);
        HttpResponse segunda = chamar(URL_FECHADAS);
        HttpResponse terceira = chamar(URL_FECHADAS);
        HttpResponse quarta = chamar(URL_FECHADAS);
        Test.stopTest();

        Assert.areEqual(504, primeira.getStatusCode(), 'A primeira chamada apanha o timeout do gateway.');
        Assert.areEqual('stream timeout', primeira.getBody(), 'O corpo do 504 é o texto real da NOS.');
        Assert.areEqual(500, segunda.getStatusCode(), 'A segunda apanha o endpoint suspenso.');
        Assert.isTrue(segunda.getBody().contains('303001'), 'O 500 do WSO2 traz o código 303001.');
        Assert.areEqual(200, terceira.getStatusCode(), 'A terceira já corre bem.');
        Assert.areEqual(200, quarta.getStatusCode(), 'Esgotada a sequência, a última resposta repete-se.');
    }

    @IsTest
    static void guardaOsPedidosPelaOrdemDeChegada() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registarOmissao(SC_NosMockFactory.ok('SC_NosFx_Lista702'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        chamar(URL_ABERTAS);
        chamar(URL_FECHADAS);
        chamar(URL_TERRITORIOS);
        Test.stopTest();

        Assert.areEqual(3, mock.numeroDeChamadas(), 'Três callouts atendidos.');
        Assert.isTrue(mock.urlDaChamada(0).contains('listByPartner'), 'A primeira foi à listagem.');
        Assert.isTrue(mock.urlDaChamada(2).contains('listTerritories'), 'A terceira foi aos territórios.');
        Assert.areEqual(2, mock.chamadasQueContem('listByPartner'), 'Duas chamadas à listagem.');
        Assert.areEqual(1, mock.chamadasQueContem('status=CLOSED'), 'Só uma pediu fechadas.');
        Assert.areEqual('GET', mock.pedidoDaChamada(0).getMethod(), 'A entrada da NOS é só de leitura.');
        Assert.areEqual(3, mock.urlsChamados().size(), 'A lista de URLs acompanha as chamadas.');
    }

    @IsTest
    static void respostaLiteralNaoPrecisaDeFixture() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('listTerritories', SC_NosMockFactory.http(401, '{"result_code":401}'))
            .registarOmissao(SC_NosMockFactory.http(200, '{}').comCabecalho('X-Request-Id', 'abc'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse territorios = chamar(URL_TERRITORIOS);
        HttpResponse outra = chamar(URL_ABERTAS);
        Test.stopTest();

        Assert.areEqual(401, territorios.getStatusCode(), 'O código literal chega ao cliente.');
        Assert.areEqual('{"result_code":401}', territorios.getBody(), 'O corpo literal chega intacto.');
        Assert.areEqual(200, outra.getStatusCode(), 'A omissão apanha o que nenhuma regra apanhou.');
        Assert.areEqual('abc', outra.getHeader('X-Request-Id'), 'Os cabeçalhos extra chegam à resposta.');
    }

    @IsTest
    static void urlSemRegraRebentaComMensagemUtil() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('getByWorkitemId', SC_NosMockFactory.ok('SC_NosFx_DetalheOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        String erro = '';
        Test.startTest();
        try {
            chamar(URL_ABERTAS);
        } catch (Exception e) {
            erro = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(
            erro.contains('listByPartner'),
            'Um URL sem regra tem de rebentar e dizer qual foi, senão o teste passa por engano: ' + erro
        );
    }

    @IsTest
    static void fixtureInexistenteRebentaComONome() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('listByPartner', SC_NosMockFactory.ok('SC_NosFx_NaoExiste'));
        Test.setMock(HttpCalloutMock.class, mock);

        String erro = '';
        Test.startTest();
        try {
            chamar(URL_ABERTAS);
        } catch (Exception e) {
            erro = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(
            erro.contains('SC_NosFx_NaoExiste'),
            'Um fixture que não está na org tem de rebentar e nomear o recurso em falta: ' + erro
        );
    }

    @IsTest
    static void excepcaoSimulaOTimeoutDoCliente() {
        SC_NosMockFactory mock = new SC_NosMockFactory()
            .registar('listByPartner', SC_NosMockFactory.excepcao('Read timed out'));
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean rebentou = false;
        Test.startTest();
        try {
            chamar(URL_ABERTAS);
        } catch (CalloutException e) {
            rebentou = e.getMessage().contains('Read timed out');
        }
        Test.stopTest();

        Assert.isTrue(rebentou, 'A fábrica sabe simular o timeout que o cliente tem de apanhar.');
    }

    @IsTest
    static void osFixturesDeErroEstaoNaOrgComOCorpoReal() {
        Test.startTest();
        String texto504 = SC_NosMockFactory.corpoDoRecurso('SC_NosFx_504');
        String texto500 = SC_NosMockFactory.corpoDoRecurso('SC_NosFx_500Wso2');
        String lista702 = SC_NosMockFactory.corpoDoRecurso('SC_NosFx_Lista702');
        String mista = SC_NosMockFactory.corpoDoRecurso('SC_NosFx_ListaMista');
        String detalhe701 = SC_NosMockFactory.corpoDoRecurso('SC_NosFx_Detalhe701');
        Test.stopTest();

        Assert.areEqual('stream timeout', texto504, 'O 504 do gateway devolve texto e não JSON.');
        Assert.isTrue(texto500.contains('SUSPENDED'), 'O 500 do WSO2 diz que o endpoint ficou suspenso.');
        Assert.isTrue(lista702.contains('"result_code": 702'), 'A janela CLOSED acima de 72 h dá 702.');
        Assert.isTrue(detalhe701.contains('"result_code": 701'), 'O detalhe inexistente dá 701.');

        Map<String, Object> corpo = (Map<String, Object>) JSON.deserializeUntyped(mista);
        Map<String, Object> dados = (Map<String, Object>) corpo.get('result_data');
        List<Object> tarefas = (List<Object>) dados.get('data');
        Assert.areEqual(12, tarefas.size(), 'A listagem mista tem 12 linhas.');
        Set<String> identificadores = new Set<String>();
        for (Object linha : tarefas) {
            identificadores.add((String) ((Map<String, Object>) linha).get('ID'));
        }
        Assert.areEqual(11, identificadores.size(), 'Uma das 12 linhas repete o identificador da outra.');
    }
}