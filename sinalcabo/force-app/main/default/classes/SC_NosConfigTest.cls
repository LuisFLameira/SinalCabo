@IsTest
private class SC_NosConfigTest {
    @IsTest
    static void configLeOCustomMetadataDaOrg() {
        Sistema_Cliente__mdt config = SC_NosConfig.config();

        Assert.isNotNull(config, 'O registo NOS_FFM tem de existir no custom metadata.');
        Assert.areEqual('SC_NOS_FFM_API', SC_NosConfig.namedCredential(), 'Credencial nomeada errada.');
        Assert.areEqual('Europe/Lisbon', SC_NosConfig.fuso(), 'O fuso dos parâmetros é o de Portugal.');
        Assert.areEqual(48, SC_NosConfig.janelaAbertasHoras(), 'Janela de abertas errada.');
        Assert.areEqual(6, SC_NosConfig.janelaFechadasHoras(), 'Janela de fechadas errada.');
        Assert.areEqual(7, SC_NosConfig.passoVarrimentoDias(), 'Passo do varrimento errado.');
        Assert.areEqual(45, SC_NosConfig.alcanceVarrimentoDias(), 'Alcance do varrimento errado.');
        Assert.areEqual(120000, SC_NosConfig.timeoutMs(), 'Tempo limite errado.');
        Assert.areEqual(3, SC_NosConfig.detalhesPorTransaccao(), 'Detalhes por transacção errados.');
        Assert.areEqual(30, SC_NosConfig.retencaoPayloadDias(), 'Retenção da resposta errada.');
        Assert.isTrue(SC_NosConfig.activo(), 'A configuração tem de estar activa.');
    }

    @IsTest
    static void valoresVaziosCaemNosDeRecurso() {
        SC_NosConfig.definirConfig(new Sistema_Cliente__mdt(DeveloperName = 'NOS_FFM'));

        Assert.areEqual('SC_NOS_FFM_API', SC_NosConfig.namedCredential(), 'Sem valor, vale a credencial de recurso.');
        Assert.areEqual('Europe/Lisbon', SC_NosConfig.fuso(), 'Sem valor, vale o fuso de recurso.');
        Assert.areEqual(48, SC_NosConfig.janelaAbertasHoras(), 'Sem valor, vale a janela de recurso.');
        Assert.areEqual(24, SC_NosConfig.janelaFechadasHoras(), 'Sem valor, vale a janela de recurso.');
        Assert.areEqual(7, SC_NosConfig.passoVarrimentoDias(), 'Sem valor, vale o passo de recurso.');
        Assert.areEqual(45, SC_NosConfig.alcanceVarrimentoDias(), 'Sem valor, vale o alcance de recurso.');
        Assert.areEqual(120000, SC_NosConfig.timeoutMs(), 'Sem valor, vale o tempo limite de recurso.');
        Assert.areEqual(5, SC_NosConfig.detalhesPorTransaccao(), 'Sem valor, valem cinco detalhes.');
        Assert.areEqual(30, SC_NosConfig.retencaoPayloadDias(), 'Sem valor, valem trinta dias.');
        Assert.isFalse(SC_NosConfig.activo(), 'Sem a marca de activo, não está activa.');
        Assert.areEqual(
            'A configuração NOS_FFM está inactiva.',
            SC_NosConfig.motivoParaNaoCorrer(),
            'Configuração inactiva tem de travar a corrida.'
        );
    }

    @IsTest
    static void configSubstituidaMandaNosValores() {
        SC_NosConfig.definirConfig(new Sistema_Cliente__mdt(
            DeveloperName = 'NOS_FFM',
            Named_Credential__c = 'OUTRA_CRED',
            Fuso_Horario__c = 'Atlantic/Azores',
            Janela_Abertas_Horas__c = 6,
            Timeout_ms__c = 30000,
            Activo__c = true
        ));

        Assert.areEqual('OUTRA_CRED', SC_NosConfig.namedCredential(), 'A substituta manda na credencial.');
        Assert.areEqual('Atlantic/Azores', SC_NosConfig.fuso(), 'A substituta manda no fuso.');
        Assert.areEqual(6, SC_NosConfig.janelaAbertasHoras(), 'A substituta manda na janela.');
        Assert.areEqual(30000, SC_NosConfig.timeoutMs(), 'A substituta manda no tempo limite.');
    }

    @IsTest
    static void killSwitchTravaACorrida() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();

        Assert.isTrue(SC_NosConfig.killSwitchLigado(), 'O travão ficou ligado no custom setting.');
        Assert.isFalse(SC_NosConfig.podeCorrer(), 'Com o travão ligado a corrida não arranca.');
        Assert.areEqual(
            'Travão de emergência ligado.',
            SC_NosConfig.motivoParaNaoCorrer(),
            'O motivo tem de nomear o travão.'
        );
    }

    @IsTest
    static void suspensaoTravaAteExpirar() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Suspenso_Ate__c = Datetime.now().addMinutes(10);
        SC_NosConfig.gravarEstado();
        Assert.isTrue(SC_NosConfig.suspensaoActiva(), 'A suspensão está activa nos próximos dez minutos.');
        Assert.isTrue(
            SC_NosConfig.motivoParaNaoCorrer().startsWith('Integração suspensa até'),
            'O motivo tem de nomear a suspensão.'
        );

        estado = SC_NosConfig.estado();
        estado.Suspenso_Ate__c = Datetime.now().addMinutes(-1);
        SC_NosConfig.gravarEstado();
        Assert.isFalse(SC_NosConfig.suspensaoActiva(), 'Uma suspensão passada já não trava.');
        Assert.isTrue(SC_NosConfig.podeCorrer(), 'Sem travão nem suspensão, a corrida arranca.');
    }

    @IsTest
    static void doisCortesSeguidosMandamSuspender() {
        Assert.isFalse(SC_NosConfig.registarCorte504(), 'Um corte só não chega para suspender.');
        Assert.isTrue(SC_NosConfig.registarCorte504(), 'Dois cortes seguidos mandam suspender.');
        Assert.areEqual(2, SC_NosConfig.estado().Contador_504__c, 'O contador de cortes tem de subir.');
    }

    @IsTest
    static void respostaBoaApagaOsContadores() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Contador_504__c = 1;
        estado.Suspensoes_Seguidas__c = 3;

        SC_NosConfig.limparCortes();

        Assert.areEqual(0, SC_NosConfig.estado().Contador_504__c, 'Uma resposta boa apaga os cortes.');
        Assert.areEqual(0, SC_NosConfig.estado().Suspensoes_Seguidas__c, 'E apaga as suspensões seguidas.');
    }

    @IsTest
    static void suspensaoDobraAteAoTecto() {
        Assert.areEqual(15, SC_NosConfig.suspender(), 'A primeira suspensão é de quinze minutos.');
        Assert.areEqual(30, SC_NosConfig.suspender(), 'A segunda dobra para trinta.');
        Assert.areEqual(60, SC_NosConfig.suspender(), 'A terceira dobra para sessenta.');
        Assert.areEqual(120, SC_NosConfig.suspender(), 'A quarta chega ao tecto de duas horas.');
        Assert.areEqual(120, SC_NosConfig.suspender(), 'E daí em diante fica no tecto.');
        Assert.isTrue(SC_NosConfig.suspensaoActiva(), 'Depois de suspender, a suspensão está activa.');
        Assert.areEqual(0, SC_NosConfig.estado().Contador_504__c, 'Suspender apaga a contagem de cortes.');
    }

    @IsTest
    static void esquecerEstadoVoltaALerDaBase() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Contador_504__c = 7;
        SC_NosConfig.esquecerEstado();

        Assert.areEqual(
            0, SC_NosConfig.estado().Contador_504__c,
            'Sem gravar, esquecer o estado deita fora a alteração em memória.'
        );
    }
}