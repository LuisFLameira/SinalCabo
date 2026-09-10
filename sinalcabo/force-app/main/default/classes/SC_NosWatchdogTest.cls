/**
 * Testes da vigia: quando é que ela grita, quando é que se cala, e o que sai no aviso.
 *
 * O correio e a notificação não se verificam por asserção, porque uma transacção de
 * teste não os entrega. O que se assere é a decisão, que é o que pode estar errado: o
 * motivo apurado, o silêncio da hora seguinte e o carimbo do último alerta.
 */
@IsTest
private class SC_NosWatchdogTest {
    private static Lote_Integracao__c loteConcluido() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();
        lote.Estado__c = SC_NosLote.ESTADO_CONCLUIDO;
        lote.Resultado__c = 'Sucesso';
        update lote;
        return lote;
    }

    private static void configurar(Boolean activo) {
        SC_NosConfig.definirConfig(new Sistema_Cliente__mdt(
            DeveloperName = SC_NosConfig.SISTEMA, Activo__c = activo
        ));
    }

    @IsTest
    static void semLoteConcluidoNaUltimaMeiaHoraAVigiaAvisa() {
        configurar(true);

        Test.startTest();
        String motivo = SC_NosWatchdog.verificar();
        Test.stopTest();

        Assert.isNotNull(motivo, 'Sem lote nenhum a integração está parada.');
        Assert.isTrue(motivo.contains('parada'), 'E o motivo di-lo por extenso: ' + motivo);
        SC_NosConfig.esquecerEstado();
        Assert.isNotNull(
            SC_NosConfig.estado().Ultimo_Alerta_Watchdog__c,
            'A hora do alerta fica guardada, para o seguinte não sair já a seguir.'
        );
    }

    @IsTest
    static void comUmLoteConcluidoAgoraAVigiaCalaSe() {
        configurar(true);
        loteConcluido();

        Test.startTest();
        String motivo = SC_NosWatchdog.verificar();
        Test.stopTest();

        Assert.isNull(motivo, 'Um lote fechado agora mesmo é sinal de vida.');
    }

    @IsTest
    static void comOTravaoLigadoAVigiaNaoAvisaDeParagem() {
        configurar(true);
        SC_NosConfig.estado().Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        Test.startTest();
        String motivo = SC_NosWatchdog.verificar();
        Test.stopTest();

        Assert.isNull(motivo, 'Uma paragem pedida por alguém não é um alerta.');
    }

    @IsTest
    static void comAConfiguracaoInactivaAVigiaTambemNaoAvisa() {
        configurar(false);

        Test.startTest();
        Assert.isNull(SC_NosWatchdog.verificar(), 'Com a configuração desligada não há nada a vigiar.');
        Test.stopTest();
    }

    @IsTest
    static void suspensaoLongaAvisaMesmoComOTravaoLigado() {
        configurar(true);
        SC_NosConfig.estado().Kill_Switch__c = true;
        SC_NosConfig.estado().Suspenso_Ate__c = Datetime.now().addHours(2);
        SC_NosConfig.gravarEstado();
        loteConcluido();

        Test.startTest();
        String motivo = SC_NosWatchdog.verificar();
        Test.stopTest();

        Assert.isNotNull(motivo, 'Uma suspensão de duas horas é para saber.');
        Assert.isTrue(motivo.contains('suspensa'), 'E o motivo é a suspensão: ' + motivo);
    }

    @IsTest
    static void suspensaoCurtaNaoAvisa() {
        configurar(true);
        SC_NosConfig.estado().Suspenso_Ate__c = Datetime.now().addMinutes(15);
        SC_NosConfig.gravarEstado();
        loteConcluido();

        Test.startTest();
        Assert.isNull(SC_NosWatchdog.verificar(), 'Quinze minutos é o soluço normal da API.');
        Test.stopTest();
    }

    @IsTest
    static void oMesmoAlertaNaoSaiDuasVezesNaMesmaHora() {
        configurar(true);
        SC_NosConfig.estado().Ultimo_Alerta_Watchdog__c = Datetime.now().addMinutes(-10);
        SC_NosConfig.gravarEstado();

        Test.startTest();
        String motivo = SC_NosWatchdog.verificar();
        Test.stopTest();

        Assert.isNull(motivo, 'Já saiu um alerta há dez minutos.');
        Assert.isNotNull(SC_NosWatchdog.motivo(), 'Mas a integração continua parada.');
    }

    @IsTest
    static void alertaDeHaMaisDeUmaHoraJaNaoSilencia() {
        configurar(true);
        SC_NosConfig.estado().Ultimo_Alerta_Watchdog__c = Datetime.now().addMinutes(-90);
        SC_NosConfig.gravarEstado();

        Test.startTest();
        Assert.isNotNull(SC_NosWatchdog.verificar(), 'Passada a hora, o alerta volta a sair.');
        Test.stopTest();
    }

    @IsTest
    static void oCorpoDoAvisoDizOEstadoDaIntegracao() {
        configurar(true);
        SC_NosConfig.estado().Suspenso_Ate__c = Datetime.now().addHours(2);
        SC_NosConfig.gravarEstado();

        String corpo = SC_NosWatchdog.corpo('motivo de teste', UserInfo.getUserId());

        Assert.isTrue(corpo.contains('motivo de teste'), 'O motivo vai no corpo: ' + corpo);
        Assert.isTrue(corpo.contains('Travão de emergência'), 'E o estado do travão.');
        Assert.isTrue(corpo.contains('Suspensa até'), 'E até quando está suspensa.');
        Assert.isTrue(corpo.contains('MANUAL_STEPS'), 'E onde está o runbook.');
    }

    @IsTest
    static void aVigiaAgendaSeEDaAsHoras() {
        configurar(true);

        Test.startTest();
        String jobId = System.schedule('SC_NOS_Watchdog_Teste', '0 20 * * * ?', new SC_NosWatchdog());
        Test.stopTest();

        Assert.areEqual(
            'SC_NOS_Watchdog_Teste',
            [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId].CronJobDetail.Name,
            'A vigia entra como agendamento à hora.'
        );
    }
}