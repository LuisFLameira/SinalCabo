/**
 * Testes do reprocessamento: passar outra vez pelo pipeline o que ficou guardado, sem
 * chamar a NOS. Nenhum destes testes precisa de mock, e é isso que se prova.
 */
@IsTest
private class SC_NosReprocessadorTest {
    private static Lote_Integracao__c loteComPayload(String tipoCorrida, String corpo) {
        Lote_Integracao__c lote = SC_NosTestDados.lote(tipoCorrida);
        lote.Payload__c = corpo;
        lote.Estado__c = SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS;
        lote.Rejeitados__c = 1;
        update lote;
        return lote;
    }

    @IsTest
    static void reprocessarUmaListagemCriaAsOrdensQueTinhamFaltado() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c original = loteComPayload(
            SC_NosConfig.CORRIDA_ABERTAS, SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );

        Test.startTest();
        Lote_Integracao__c novo = SC_NosReprocessador.reprocessar(original.Id);
        Test.stopTest();

        Assert.isNotNull(novo, 'Um lote com resposta guardada reprocessa-se.');
        Lote_Integracao__c guardado = [
            SELECT Tipo_Corrida__c, Estado__c, Resultado__c, Registos_Lidos__c, Criados__c, Reprocessado_De__c
            FROM Lote_Integracao__c WHERE Id = :novo.Id
        ];
        Assert.areEqual('Reprocessamento', guardado.Tipo_Corrida__c, 'O lote novo é de reprocessamento.');
        Assert.areEqual(original.Id, guardado.Reprocessado_De__c, 'E aponta ao lote de onde veio.');
        Assert.areEqual('Concluído', guardado.Estado__c, 'Sem rejeitados, fecha limpo.');
        Assert.areEqual('Sucesso', guardado.Resultado__c, 'E com sucesso, mesmo sem resposta da API.');
        Assert.areEqual(56, guardado.Registos_Lidos__c, 'Leu as 56 tarefas do corpo guardado.');
        Assert.areEqual(56, guardado.Criados__c, 'E criou as 56 ordens.');
        Assert.areEqual(56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL], 'Ordens na org.');
    }

    @IsTest
    static void oLoteOriginalFicaComoEstava() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c original = loteComPayload(
            SC_NosConfig.CORRIDA_ABERTAS, SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );

        Test.startTest();
        SC_NosReprocessador.reprocessar(original.Id);
        Test.stopTest();

        Lote_Integracao__c depois = [
            SELECT Estado__c, Rejeitados__c FROM Lote_Integracao__c WHERE Id = :original.Id
        ];
        Assert.areEqual('Concluído com erros', depois.Estado__c, 'O histórico do que aconteceu à primeira não se apaga.');
        Assert.areEqual(1, depois.Rejeitados__c, 'Nem os contadores.');
    }

    @IsTest
    static void reprocessarUmDetalheUsaOCaminhoDoDetalhe() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c original = loteComPayload(
            SC_NosConfig.CORRIDA_DETALHES, SC_NosTestDados.fixture('SC_NosFx_DetalheOk')
        );

        Test.startTest();
        Lote_Integracao__c novo = SC_NosReprocessador.reprocessar(original.Id);
        Test.stopTest();

        Assert.areEqual(1, [SELECT Criados__c FROM Lote_Integracao__c WHERE Id = :novo.Id].Criados__c,
            'Um detalhe guardado cria a ordem que ele descreve.');
        Assert.isTrue(
            [SELECT Description FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002537686' LIMIT 1]
                .Description.contains('Interacções na NOS'),
            'E com a descrição completa que o detalhe traz.'
        );
    }

    @IsTest
    static void loteSemRespostaGuardadaNaoSeReprocessa() {
        Lote_Integracao__c semPayload = SC_NosTestDados.lote();

        Test.startTest();
        Assert.isNull(SC_NosReprocessador.reprocessar(semPayload.Id), 'Sem resposta guardada não há nada a reprocessar.');
        Assert.isNull(SC_NosReprocessador.reprocessar(null), 'E sem lote também não.');
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Lote_Integracao__c], 'E não se abre lote nenhum.');
    }

    @IsTest
    static void reprocessarNaoDuplicaAsOrdensQueJaEntraram() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c original = loteComPayload(
            SC_NosConfig.CORRIDA_ABERTAS, SC_NosTestDados.fixture('SC_NosFx_ListaOk')
        );
        SC_NosReprocessador.reprocessar(original.Id);

        Test.startTest();
        Lote_Integracao__c segundo = SC_NosReprocessador.reprocessar(original.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT Criados__c FROM Lote_Integracao__c WHERE Id = :segundo.Id].Criados__c,
            'À segunda já não há nada a criar.');
        Assert.areEqual(56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL],
            'E as ordens continuam a ser 56.');
    }
}