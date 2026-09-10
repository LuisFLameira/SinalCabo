/**
 * Testes da purga: o que se apaga, o que se guarda mais tempo e o que não se toca.
 *
 * A data de criação de um lote não se pode escolher em Apex, por isso os cenários de
 * idade fazem-se com `Test.setCreatedDate`, que é para isto mesmo que existe.
 */
@IsTest
private class SC_NosPurgaPayloadTest {
    private static final String CORPO = '{"result_code":0,"result_data":{"data":[]}}';

    private static Lote_Integracao__c lote(String estado, Integer diasAtras) {
        Lote_Integracao__c lote = SC_NosTestDados.lote();
        lote.Estado__c = estado;
        lote.Payload__c = CORPO;
        update lote;
        Test.setCreatedDate(lote.Id, Datetime.now().addDays(-diasAtras));
        return lote;
    }

    private static String payloadDe(Id loteId) {
        return [SELECT Payload__c FROM Lote_Integracao__c WHERE Id = :loteId].Payload__c;
    }

    @IsTest
    static void loteVelhoPerdeARespostaGuardada() {
        Lote_Integracao__c velho = lote(SC_NosLote.ESTADO_CONCLUIDO, 45);

        Test.startTest();
        Database.executeBatch(new SC_NosPurgaPayload(), 50);
        Test.stopTest();

        Assert.isNull(payloadDe(velho.Id), 'Passados os trinta dias a resposta bruta sai.');
    }

    @IsTest
    static void loteRecenteFicaComARespostaGuardada() {
        Lote_Integracao__c recente = lote(SC_NosLote.ESTADO_CONCLUIDO, 5);

        Test.startTest();
        Database.executeBatch(new SC_NosPurgaPayload(), 50);
        Test.stopTest();

        Assert.areEqual(CORPO, payloadDe(recente.Id), 'Dentro do prazo a resposta fica, para se poder reprocessar.');
    }

    @IsTest
    static void loteFalhadoGuardaSeNoventaDias() {
        Lote_Integracao__c falhado = lote(SC_NosLote.ESTADO_FALHADO, 45);
        Lote_Integracao__c falhadoAntigo = lote(SC_NosLote.ESTADO_FALHADO, 120);

        Test.startTest();
        Database.executeBatch(new SC_NosPurgaPayload(), 50);
        Test.stopTest();

        Assert.areEqual(CORPO, payloadDe(falhado.Id), 'Um lote falhado é material de análise durante 90 dias.');
        Assert.isNull(payloadDe(falhadoAntigo.Id), 'Passados os 90 dias sai como os outros.');
    }

    @IsTest
    static void loteVelhoSemRespostaNaoEEscritoOutraVez() {
        Lote_Integracao__c semPayload = SC_NosTestDados.lote();
        Test.setCreatedDate(semPayload.Id, Datetime.now().addDays(-45));
        Datetime antes = [SELECT LastModifiedDate FROM Lote_Integracao__c WHERE Id = :semPayload.Id].LastModifiedDate;

        Test.startTest();
        Database.executeBatch(new SC_NosPurgaPayload(), 50);
        Test.stopTest();

        Assert.areEqual(
            antes,
            [SELECT LastModifiedDate FROM Lote_Integracao__c WHERE Id = :semPayload.Id].LastModifiedDate,
            'Um lote já sem resposta guardada não se volta a escrever.'
        );
    }

    @IsTest
    static void aPurgaAgendaSeParaAsTresDaManha() {
        Test.startTest();
        String jobId = System.schedule('SC_NOS_Purga_Teste', '0 0 3 * * ?', new SC_NosPurgaPayload());
        Test.stopTest();

        Assert.areEqual(
            'SC_NOS_Purga_Teste',
            [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId].CronJobDetail.Name,
            'A purga entra como agendamento diário.'
        );
    }
}