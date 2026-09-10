/**
 * Testes do arranque de cinco em cinco minutos e dos doze agendamentos.
 */
@IsTest
private class SC_NosPollingSchedulerTest {
    @IsTest
    static void arranqueAbreOLoteDasAbertasEPoeOPassoNaFila() {
        SC_NosTestDados.catalogo();
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));

        Test.startTest();
        Id loteId = SC_NosPollingScheduler.arrancar();
        Test.stopTest();

        Assert.isNotNull(loteId, 'O arranque tem de abrir o lote das abertas.');
        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Estado__c, Janela_Inicio__c, Janela_Fim__c
            FROM Lote_Integracao__c WHERE Id = :loteId
        ];
        Assert.areEqual('Abertas', lote.Tipo_Corrida__c, 'A cadeia começa pelas abertas.');
        Assert.areEqual('Concluído', lote.Estado__c, 'O passo correu e fechou o lote.');
        Long horas = (lote.Janela_Fim__c.getTime() - lote.Janela_Inicio__c.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(48, horas, 'A janela das abertas é a das últimas 48 horas.');
    }

    @IsTest
    static void travaoDeEmergenciaImpedeOArranque() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        Test.startTest();
        Id loteId = SC_NosPollingScheduler.arrancar();
        Test.stopTest();

        Assert.isNull(loteId, 'Com o travão ligado não se abre lote nenhum.');
        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'E não fica lixo na tabela de lotes.');
    }

    @IsTest
    static void suspensaoActivaImpedeOArranque() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Suspenso_Ate__c = Datetime.now().addMinutes(30);
        SC_NosConfig.gravarEstado();

        Test.startTest();
        Assert.isNull(SC_NosPollingScheduler.arrancar(), 'Com a integração suspensa não se arranca.');
        Test.stopTest();
    }

    @IsTest
    static void corridaAindaEmCursoImpedeOutraPorCima() {
        SC_NosTestDados.lote(SC_NosConfig.CORRIDA_ABERTAS);

        Test.startTest();
        Boolean haCorrida = SC_NosPollingScheduler.haCorridaEmCurso();
        Id loteId = SC_NosPollingScheduler.arrancar();
        Test.stopTest();

        Assert.isTrue(haCorrida, 'Um lote em curso há menos de dez minutos conta como corrida a decorrer.');
        Assert.isNull(loteId, 'E trava uma segunda cadeia por cima da primeira.');
    }

    @IsTest
    static void executarPeloAgendadorPassaPeloMesmoArranque() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        Test.startTest();
        new SC_NosPollingScheduler().execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Lote_Integracao__c], 'O agendador respeita o travão como o arranque.');
    }

    @IsTest
    static void publicarDevolveNuloQuandoOEventoSai() {
        Test.startTest();
        String erro = SC_NosPollingScheduler.publicar(
            SC_NosConfig.CORRIDA_ABERTAS, null, null, SC_NosPollingScheduler.ORIGEM_AGENDADOR
        );
        Test.stopTest();

        Assert.isNull(erro, 'Uma publicação que sai não devolve erro.');
    }

    @IsTest
    static void correrJanelaAbreLoteRepetivelQueNaoEncadeia() {
        SC_NosTestDados.catalogo();
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));
        Datetime fim = Datetime.now();

        Test.startTest();
        Id primeiro = SC_NosPollingScheduler.correrJanela(SC_NosConfig.CORRIDA_MANUAL, fim.addHours(-1), fim);
        Test.stopTest();

        Assert.isNotNull(primeiro, 'A corrida de janela abre lote.');
        Lote_Integracao__c lote = [
            SELECT Tipo_Corrida__c, Chave_Execucao__c FROM Lote_Integracao__c WHERE Id = :primeiro
        ];
        Assert.areEqual('Manual', lote.Tipo_Corrida__c, 'Sem tipo pedido vale Manual.');
        Assert.isTrue(
            lote.Chave_Execucao__c.countMatches('|') > 3,
            'A chave leva sufixo, para a mesma janela poder ser relida: ' + lote.Chave_Execucao__c
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Lote_Integracao__c], 'E não continua para os passos seguintes.');
    }

    @IsTest
    static void correrJanelaTambemParaNoTravao() {
        SC_NosConfig.estado().Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();
        Datetime fim = Datetime.now();

        Test.startTest();
        Assert.isNull(
            SC_NosPollingScheduler.correrJanela(SC_NosConfig.CORRIDA_MANUAL, fim.addHours(-1), fim),
            'Com o travão ligado a corrida de janela também não arranca.'
        );
        Test.stopTest();
    }

    @IsTest
    static void agendarCriaDozeCronsEDesagendarApagaOsTodos() {
        // O travão fica ligado para que um cron que dispare no fim do teste não corra.
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        // A org pode já ter os agendamentos: o que se assere é o estado final, não o delta.
        SC_NosPollingScheduler.agendar();
        Set<String> nomes = new Set<String>();
        for (CronTrigger gatilho : [
            SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'SC_NOS_Polling%'
        ]) {
            nomes.add(gatilho.CronJobDetail.Name);
        }
        Assert.areEqual(12, nomes.size(), 'São doze agendamentos, um por cada cinco minutos.');
        Assert.isTrue(nomes.contains('SC_NOS_Polling_00'), 'O do minuto zero tem de existir.');
        Assert.isTrue(nomes.contains('SC_NOS_Polling_55'), 'E o do minuto 55 também.');
        Assert.areEqual(0, SC_NosPollingScheduler.agendar().size(), 'Correr outra vez não duplica nada.');
        Assert.areEqual(12, SC_NosPollingScheduler.desagendar(), 'Desagendar apaga os doze.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'SC_NOS_Polling%'],
            'E não sobra nenhum.'
        );
    }
}