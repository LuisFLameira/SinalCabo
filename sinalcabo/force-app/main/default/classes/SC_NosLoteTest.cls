/**
 * Testes do lote: a chave que impede duas corridas na mesma janela, os contadores com
 * que fecha, e a regra de só guardar a resposta bruta quando há algo para investigar.
 */
@IsTest
private class SC_NosLoteTest {
    private static SC_NosUpsertService.Resultado resultado(
        Integer lidos, Integer criados, Integer actualizados, Integer rejeitados
    ) {
        SC_NosUpsertService.Resultado r = new SC_NosUpsertService.Resultado();
        r.lidos = lidos;
        r.criados = criados;
        r.actualizados = actualizados;
        r.rejeitados = rejeitados;
        return r;
    }

    @IsTest
    static void loteAbreEmCursoComAJanelaEAChave() {
        Datetime fim = Datetime.now();
        Datetime inicio = fim.addHours(-48);

        Test.startTest();
        Lote_Integracao__c lote = SC_NosLote.abrir(SC_NosConfig.CORRIDA_ABERTAS, inicio, fim);
        Test.stopTest();

        Lote_Integracao__c guardado = [
            SELECT Interface__c, Direccao__c, Tipo_Corrida__c, Estado__c, Chave_Execucao__c,
                   Janela_Inicio__c, Janela_Fim__c, Registos_Lidos__c
            FROM Lote_Integracao__c WHERE Id = :lote.Id
        ];
        Assert.areEqual(SC_NosConfig.INTERFACE_ENTRADA, guardado.Interface__c, 'A interface identifica a entrada da NOS.');
        Assert.areEqual('Entrada', guardado.Direccao__c, 'A leitura da NOS é sempre entrada.');
        Assert.areEqual('Abertas', guardado.Tipo_Corrida__c, 'O tipo de corrida é o passo.');
        Assert.areEqual('Em curso', guardado.Estado__c, 'Um lote nasce em curso.');
        Assert.areEqual(0, guardado.Registos_Lidos__c, 'Os contadores começam a zero.');
        Assert.isTrue(guardado.Chave_Execucao__c.startsWith('NOS|Abertas|'), 'A chave nomeia o passo: ' + guardado.Chave_Execucao__c);
    }

    @IsTest
    static void segundaCorridaNaMesmaJanelaNaoAbreLote() {
        Datetime fim = Datetime.now();
        Datetime inicio = fim.addHours(-1);

        Test.startTest();
        Lote_Integracao__c primeiro = SC_NosLote.abrir(SC_NosConfig.CORRIDA_ABERTAS, inicio, fim);
        Lote_Integracao__c segundo = SC_NosLote.abrir(SC_NosConfig.CORRIDA_ABERTAS, inicio, fim);
        Test.stopTest();

        Assert.isNotNull(primeiro, 'A primeira corrida abre o lote.');
        Assert.isNull(segundo, 'A segunda apanha a chave duplicada e desiste em silêncio.');
        Assert.areEqual(1, [SELECT COUNT() FROM Lote_Integracao__c], 'Fica um lote só.');
    }

    @IsTest
    static void corridaRepetivelAbreSempreUmLoteNovo() {
        Datetime fim = Datetime.now();
        Datetime inicio = fim.addHours(-1);

        Test.startTest();
        Lote_Integracao__c primeiro = SC_NosLote.abrirRepetivel(SC_NosConfig.CORRIDA_MANUAL, inicio, fim);
        Lote_Integracao__c segundo = SC_NosLote.abrirRepetivel(SC_NosConfig.CORRIDA_MANUAL, inicio, fim);
        Test.stopTest();

        Assert.isNotNull(primeiro, 'A primeira corrida manual abre.');
        Assert.isNotNull(segundo, 'A segunda também: repetir a janela é o objectivo.');
        Assert.areNotEqual(primeiro.Chave_Execucao__c, segundo.Chave_Execucao__c, 'As chaves têm de ser diferentes.');
    }

    @IsTest
    static void chaveEhDeterministicaParaAMesmaJanela() {
        Datetime inicio = Datetime.newInstanceGmt(2026, 8, 4, 7, 0, 0);
        Datetime fim = Datetime.newInstanceGmt(2026, 8, 4, 8, 0, 0);

        Assert.areEqual(
            'NOS|Abertas|202608040700|202608040800',
            SC_NosLote.chave(SC_NosConfig.CORRIDA_ABERTAS, inicio, fim),
            'A chave é o passo mais a janela ao minuto, em GMT.'
        );
        Assert.areEqual('NOS|Detalhes||', SC_NosLote.chave(SC_NosConfig.CORRIDA_DETALHES, null, null),
            'Sem janela, a chave fica com os campos vazios.');
    }

    @IsTest
    static void loteFechaComOsContadoresEOResultado() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();
        SC_NosResponse resposta = SC_NosResponse.classificar(
            respostaHttp(200, '{"result_code":0,"result_data":{"data":[{"ID":"TAS1"}]}}'), 0, 'url', 1234L
        );

        Test.startTest();
        SC_NosLote.concluir(lote, resposta, 1234L, resultado(10, 4, 3, 0), Datetime.now().addMinutes(5));
        Test.stopTest();

        Lote_Integracao__c guardado = [
            SELECT Estado__c, Resultado__c, Registos_Lidos__c, Criados__c, Actualizados__c,
                   Rejeitados__c, Duracao_ms__c, Payload__c, Proxima_Chegada_Esperada__c
            FROM Lote_Integracao__c WHERE Id = :lote.Id
        ];
        Assert.areEqual('Concluído', guardado.Estado__c, 'Sem rejeitados o lote fecha limpo.');
        Assert.areEqual('Sucesso', guardado.Resultado__c, 'O resultado vem da classificação da resposta.');
        Assert.areEqual(10, guardado.Registos_Lidos__c, 'Os lidos são os do resultado.');
        Assert.areEqual(4, guardado.Criados__c, 'Os criados também.');
        Assert.areEqual(3, guardado.Actualizados__c, 'E os actualizados.');
        Assert.areEqual(1234, guardado.Duracao_ms__c, 'A duração é a da chamada.');
        Assert.isNull(guardado.Payload__c, 'Sem ocorrências, a resposta bruta não se guarda.');
        Assert.isNotNull(guardado.Proxima_Chegada_Esperada__c, 'A próxima chegada fica registada.');
    }

    @IsTest
    static void loteComRejeitadosFechaComErrosEGuardaARespostaBruta() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();
        SC_NosResponse resposta = SC_NosResponse.classificar(
            respostaHttp(200, '{"result_code":0,"result_data":{"data":[{"ID":"TAS1"}]}}'), 0, 'url', 10L
        );
        SC_NosUpsertService.Resultado r = resultado(3, 1, 0, 2);
        r.ocorrencias.add(SC_NosLote.ocorrencia(lote.Id, SC_NosLote.TIPO_REJEICAO, 'TAS1', 'WorkOrder', 'não entrou', null));

        Test.startTest();
        SC_NosLote.concluir(lote, resposta, 10L, r, null);
        Test.stopTest();

        Lote_Integracao__c guardado = [
            SELECT Estado__c, Rejeitados__c, Payload__c FROM Lote_Integracao__c WHERE Id = :lote.Id
        ];
        Assert.areEqual('Concluído com erros', guardado.Estado__c, 'Com rejeitados o lote fecha com erros.');
        Assert.areEqual(2, guardado.Rejeitados__c, 'Os rejeitados ficam contados.');
        Assert.isNotNull(guardado.Payload__c, 'Com ocorrências, a resposta bruta guarda-se para reprocessar.');
    }

    @IsTest
    static void loteSemRespostaDaApiFechaPelosContadores() {
        Lote_Integracao__c comLinhas = SC_NosTestDados.lote();
        Lote_Integracao__c semLinhas = SC_NosTestDados.lote();

        Test.startTest();
        SC_NosLote.concluir(comLinhas, null, 0L, resultado(5, 5, 0, 0), null);
        SC_NosLote.concluir(semLinhas, null, 0L, resultado(0, 0, 0, 0), null);
        SC_NosLote.concluir(null, null, 0L, resultado(0, 0, 0, 0), null);
        Test.stopTest();

        Assert.areEqual('Sucesso',
            [SELECT Resultado__c FROM Lote_Integracao__c WHERE Id = :comLinhas.Id].Resultado__c,
            'Um reprocessamento com linhas fecha com Sucesso.');
        Assert.areEqual('Vazio',
            [SELECT Resultado__c FROM Lote_Integracao__c WHERE Id = :semLinhas.Id].Resultado__c,
            'Um reprocessamento sem linhas fecha com Vazio.');
    }

    @IsTest
    static void loteFalhadoGuardaOErro() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();
        SC_NosResponse resposta = SC_NosResponse.classificar(respostaHttp(504, 'stream timeout'), 0, 'url', 60000L);

        Test.startTest();
        SC_NosLote.falhar(lote, resposta, 'O gateway cortou a chamada.');
        SC_NosLote.falhar(null, null, 'nada');
        Test.stopTest();

        Lote_Integracao__c guardado = [
            SELECT Estado__c, Resultado__c, Erro__c, Payload__c FROM Lote_Integracao__c WHERE Id = :lote.Id
        ];
        Assert.areEqual('Falhado', guardado.Estado__c, 'Um corte deixa o lote falhado.');
        Assert.areEqual('Timeout', guardado.Resultado__c, 'E o resultado é Timeout.');
        Assert.areEqual('O gateway cortou a chamada.', guardado.Erro__c, 'O erro fica escrito por extenso.');
        Assert.isNotNull(guardado.Payload__c, 'A resposta do gateway guarda-se para diagnóstico.');
    }

    @IsTest
    static void falharPorIdSoMexeNumLoteAindaEmCurso() {
        Lote_Integracao__c emCurso = SC_NosTestDados.lote();
        Lote_Integracao__c jaFechado = SC_NosTestDados.lote();
        SC_NosLote.concluir(jaFechado, null, 0L, resultado(1, 1, 0, 0), null);

        Test.startTest();
        SC_NosLote.falharPorId(emCurso.Id, 'A transacção morreu.');
        SC_NosLote.falharPorId(jaFechado.Id, 'A transacção morreu.');
        SC_NosLote.falharPorId(null, 'sem lote');
        Test.stopTest();

        Assert.areEqual('Falhado', [SELECT Estado__c FROM Lote_Integracao__c WHERE Id = :emCurso.Id].Estado__c,
            'Um lote em curso passa a falhado.');
        Assert.areEqual('Concluído', [SELECT Estado__c FROM Lote_Integracao__c WHERE Id = :jaFechado.Id].Estado__c,
            'Um lote já fechado não se reabre.');
    }

    @IsTest
    static void falharSemMensagemNaoDeixaOCampoVazio() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();

        Test.startTest();
        SC_NosLote.falharPorId(lote.Id, null);
        Test.stopTest();

        Assert.areEqual('Erro sem mensagem.', [SELECT Erro__c FROM Lote_Integracao__c WHERE Id = :lote.Id].Erro__c,
            'Um lote falhado tem sempre uma razão escrita.');
    }

    @IsTest
    static void ocorrenciaCortaOsCamposAoTectoEMarcaOReprocessavel() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();

        Ocorrencia_Integracao__c aviso = SC_NosLote.ocorrencia(
            lote.Id, SC_NosLote.TIPO_AVISO, 'T'.repeat(80), 'WorkOrder', 'M'.repeat(400), 'conteúdo'
        );
        Ocorrencia_Integracao__c rejeicao = SC_NosLote.ocorrencia(
            lote.Id, SC_NosLote.TIPO_REJEICAO, null, 'WorkOrder', null, null
        );

        Test.startTest();
        SC_NosLote.guardar(new List<Ocorrencia_Integracao__c>{ aviso, rejeicao });
        SC_NosLote.guardar(null);
        SC_NosLote.guardar(new List<Ocorrencia_Integracao__c>());
        Test.stopTest();

        Assert.areEqual(50, aviso.Chave_Origem__c.length(), 'A chave de origem cabe nos 50 caracteres do campo.');
        Assert.areEqual(255, aviso.Mensagem__c.length(), 'A mensagem cabe nos 255 caracteres do campo.');
        Assert.isFalse(aviso.Reprocessavel__c, 'Um aviso não se reprocessa.');
        Assert.isTrue(rejeicao.Reprocessavel__c, 'Uma rejeição reprocessa-se depois de corrigida a causa.');
        Assert.areEqual(2, [SELECT COUNT() FROM Ocorrencia_Integracao__c WHERE Lote__c = :lote.Id], 'As duas ficam gravadas.');
    }

    private static HttpResponse respostaHttp(Integer codigo, String corpo) {
        HttpResponse resposta = new HttpResponse();
        resposta.setStatusCode(codigo);
        resposta.setBody(corpo);
        return resposta;
    }
}