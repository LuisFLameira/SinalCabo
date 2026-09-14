/**
 * Testes do reprocessamento das linhas do ficheiro do PNI que ficaram de fora.
 *
 * O que aqui se prova é que reprocessar não precisa do ficheiro: a linha original e o
 * cabeçalho ficaram guardados, e é com eles que ela volta a passar pelo mesmo caminho.
 */
@IsTest
private class SC_PniReprocessadorTest {

    private static final String CABECALHO =
        'Project ID;Status;Last Changed On;Célula;Tipo OT';

    private static Lote_Integracao__c loteComCabecalho() {
        Lote_Integracao__c lote = new Lote_Integracao__c(
            Interface__c = SC_PniConfig.INTERFACE_ENTRADA,
            Direccao__c = 'Entrada',
            Tipo_Corrida__c = SC_PniConfig.CORRIDA_FICHEIRO,
            Estado__c = SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS,
            Chave_Execucao__c = 'PNI|teste|' + String.valueOf(Crypto.getRandomInteger()),
            Payload__c = CABECALHO,
            Registos_Lidos__c = 1, Criados__c = 0, Actualizados__c = 0, Rejeitados__c = 1
        );
        insert lote;
        return lote;
    }

    private static Ocorrencia_Integracao__c rejeicao(Id loteId, String chave,
                                                     String bruto) {
        Ocorrencia_Integracao__c o = SC_NosLote.ocorrencia(loteId,
            SC_NosLote.TIPO_REJEICAO, chave, 'WorkOrder', 'linha rejeitada', bruto);
        insert o;
        return o;
    }

    // ------------------------------------------------------------------

    @IsTest
    static void aLinhaGuardadaVoltaAPassarSemOFicheiro() {
        Lote_Integracao__c origem = loteComCabecalho();
        Ocorrencia_Integracao__c o = rejeicao(origem.Id, 'CRQ_A',
            'CRQ_A;Concluído SP;2026-09-01;YER-01;ORI-MRF');

        Test.startTest();
        SC_PniReprocessador.Resposta r =
            SC_PniReprocessador.reprocessarOcorrencias(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(1, r.entraram, 'a linha corrigida tem de entrar');
        System.assertEquals(0, r.continuamDeFora);
        System.assertEquals(1, [
            SELECT COUNT() FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c = 'CRQ_A'
        ]);

        Lote_Integracao__c repeticao = [
            SELECT Tipo_Corrida__c, Reprocessado_De__c, Estado__c, Criados__c
            FROM Lote_Integracao__c WHERE Id = :r.loteId
        ];
        System.assertEquals(SC_PniConfig.CORRIDA_REPROCESSAMENTO,
                            repeticao.Tipo_Corrida__c);
        System.assertEquals(origem.Id, repeticao.Reprocessado_De__c,
                            'o lote novo tem de apontar ao lote de origem');
        System.assertEquals(SC_NosLote.ESTADO_CONCLUIDO, repeticao.Estado__c);
        System.assertEquals(1, repeticao.Criados__c);
    }

    @IsTest
    static void aOcorrenciaResolvidaDeixaDeEstarAEspera() {
        Lote_Integracao__c origem = loteComCabecalho();
        Ocorrencia_Integracao__c o = rejeicao(origem.Id, 'CRQ_B',
            'CRQ_B;Concluído SP;2026-09-01;YER-01;ORI-MRF');

        Test.startTest();
        SC_PniReprocessador.reprocessarOcorrencias(new List<Id>{ o.Id });
        Test.stopTest();

        Ocorrencia_Integracao__c depois = [
            SELECT Reprocessavel__c FROM Ocorrencia_Integracao__c WHERE Id = :o.Id
        ];
        System.assertEquals(false, depois.Reprocessavel__c,
                            'quem entrou não pode continuar na lista de espera');
    }

    @IsTest
    static void aLinhaQueContinuaMaFicaNaLista() {
        Lote_Integracao__c origem = loteComCabecalho();
        // Continua com campos a menos: vai voltar a ser rejeitada na leitura.
        Ocorrencia_Integracao__c o = rejeicao(origem.Id, 'CRQ_C', 'CRQ_C;só dois');

        Test.startTest();
        SC_PniReprocessador.Resposta r =
            SC_PniReprocessador.reprocessarOcorrencias(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(0, r.entraram);
        System.assertEquals(1, r.continuamDeFora, 'continua de fora e é contada');
        Ocorrencia_Integracao__c depois = [
            SELECT Reprocessavel__c FROM Ocorrencia_Integracao__c WHERE Id = :o.Id
        ];
        System.assertEquals(true, depois.Reprocessavel__c,
                            'quem não entrou continua à espera de correcção');
    }

    @IsTest
    static void semCabecalhoNoLoteDeOrigemAvisaEmVezDeAdivinhar() {
        Lote_Integracao__c origem = loteComCabecalho();
        origem.Payload__c = null;
        update origem;
        Ocorrencia_Integracao__c o = rejeicao(origem.Id, 'CRQ_D',
            'CRQ_D;Concluído SP;2026-09-01;YER-01;ORI-MRF');

        Test.startTest();
        SC_PniReprocessador.Resposta r =
            SC_PniReprocessador.reprocessarOcorrencias(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(0, r.entraram);
        System.assertEquals(1, r.continuamDeFora);
        List<Ocorrencia_Integracao__c> avisos = [
            SELECT Tipo__c, Mensagem__c FROM Ocorrencia_Integracao__c
            WHERE Lote__c = :r.loteId AND Tipo__c = :SC_NosLote.TIPO_AVISO
        ];
        System.assertEquals(1, avisos.size(), 'tem de avisar e não adivinhar colunas');
        System.assert(avisos[0].Mensagem__c.contains('cabeçalho'),
                      avisos[0].Mensagem__c);
    }

    @IsTest
    static void listaVaziaNaoAbreLoteNenhum() {
        Test.startTest();
        SC_PniReprocessador.Resposta r =
            SC_PniReprocessador.reprocessarOcorrencias(new List<Id>());
        Test.stopTest();
        System.assertEquals(null, r.loteId, 'sem linhas não há nada a fazer');
        System.assertEquals(0, [SELECT COUNT() FROM Lote_Integracao__c]);
    }

    @IsTest
    static void oFluxoChamaOMesmoCaminho() {
        Lote_Integracao__c origem = loteComCabecalho();
        Ocorrencia_Integracao__c o = rejeicao(origem.Id, 'CRQ_E',
            'CRQ_E;Concluído SP;2026-09-01;YER-01;ORI-MRF');

        SC_PniReprocessador.Pedido pedido = new SC_PniReprocessador.Pedido();
        pedido.ocorrencias = new List<Id>{ o.Id };

        Test.startTest();
        List<SC_PniReprocessador.Resposta> respostas =
            SC_PniReprocessador.reprocessar(
                new List<SC_PniReprocessador.Pedido>{ pedido });
        Test.stopTest();

        System.assertEquals(1, respostas.size());
        System.assertEquals(1, respostas[0].entraram,
                            'chamado de um fluxo tem de fazer o mesmo');
    }
}