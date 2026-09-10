/**
 * Testes da máquina de estados: a ordem dos passos, o que cada erro provoca, e o
 * vigilante que fecha o lote quando a transacção morre.
 *
 * A cadeia não se encadeia nos testes, porque a plataforma só deixa enfileirar um job.
 * O passo seguinte assere-se pelo descritor que proximo() devolve.
 */
@IsTest
private class SC_NosPollingQueueableTest {
    private static final Datetime FIM = Datetime.now();
    private static final Datetime INICIO_48H = FIM.addHours(-48);

    private static SC_NosPollingQueueable passo(String nome, Id loteId, Datetime inicio, Datetime fim) {
        return new SC_NosPollingQueueable(nome, loteId, inicio, fim);
    }

    private static Lote_Integracao__c loteDe(String tipo) {
        return SC_NosTestDados.lote(tipo);
    }

    private static Lote_Integracao__c recarregar(Id loteId) {
        return [
            SELECT Estado__c, Resultado__c, Registos_Lidos__c, Criados__c, Actualizados__c,
                   Rejeitados__c, Erro__c, Payload__c
            FROM Lote_Integracao__c WHERE Id = :loteId
        ];
    }

    // ------------------------------------------------------------------
    // Cadeia
    // ------------------------------------------------------------------

    @IsTest
    static void depoisDasAbertasVemAsFechadas() {
        SC_NosPollingQueueable seguinte = passo(SC_NosConfig.CORRIDA_ABERTAS, null, INICIO_48H, FIM).proximo();

        Assert.areEqual(SC_NosConfig.CORRIDA_FECHADAS, seguinte.passo, 'A seguir às abertas vêm as fechadas.');
        Long horas = (seguinte.fim.getTime() - seguinte.inicio.getTime()) / (1000 * 60 * 60);
        Assert.areEqual(
            SC_NosConfig.janelaFechadasHoras(), horas,
            'A janela das fechadas é a da configuração, sempre abaixo do tecto de 72 horas da NOS.'
        );
        Assert.isTrue(horas <= 72, 'Acima de 72 horas a NOS recusa a consulta de fechadas.');
    }

    @IsTest
    static void depoisDasFechadasVemOVarrimentoSoQuandoACadeiaOTrouxe() {
        SC_NosPollingQueueable semVarrimento = passo(SC_NosConfig.CORRIDA_FECHADAS, null, FIM.addHours(-6), FIM);
        SC_NosPollingQueueable comVarrimento = passo(SC_NosConfig.CORRIDA_FECHADAS, null, FIM.addHours(-6), FIM);
        comVarrimento.varrer = true;

        Assert.areEqual(
            SC_NosConfig.CORRIDA_DETALHES, semVarrimento.proximo().passo,
            'Nas onze corridas sem varrimento, a seguir às fechadas vêm os detalhes.'
        );
        SC_NosPollingQueueable varrimento = comVarrimento.proximo();
        Assert.areEqual(
            SC_NosConfig.CORRIDA_VARRIMENTO, varrimento.passo,
            'Na corrida do minuto zero, a seguir às fechadas vem o varrimento.'
        );
        Long dias = (varrimento.fim.getTime() - varrimento.inicio.getTime()) / (1000L * 60 * 60 * 24);
        Assert.areEqual(SC_NosConfig.passoVarrimentoDias(), dias, 'A janela do varrimento é o passo configurado.');
        Assert.isNotNull(
            SC_NosConfig.estado().Ultimo_Varrimento__c, 'O varrimento carimba a data no estado da integração.'
        );
    }

    @IsTest
    static void aJanelaDoVarrimentoRodaPelaHoraDoDia() {
        Datetime base = Datetime.newInstanceGmt(2026, 9, 10, 0, 0, 0);
        Integer passoDias = SC_NosConfig.passoVarrimentoDias();
        Integer janelas = SC_NosConfig.alcanceVarrimentoDias() / passoDias;

        Assert.areEqual(
            base, SC_NosPollingQueueable.fimDaJanelaDeVarrimento(base),
            'À meia-noite o varrimento começa na janela mais recente.'
        );
        Assert.areEqual(
            base.addHours(1).addDays(-passoDias), SC_NosPollingQueueable.fimDaJanelaDeVarrimento(base.addHours(1)),
            'Cada hora recua uma janela.'
        );
        Assert.areEqual(
            base.addHours(janelas), SC_NosPollingQueueable.fimDaJanelaDeVarrimento(base.addHours(janelas)),
            'Ao fim de ' + janelas + ' horas o alcance está coberto e a rotação recomeça.'
        );
    }

    @IsTest
    static void aDecisaoDoVarrimentoViajaComACadeia() {
        SC_NosPollingQueueable abertas = passo(SC_NosConfig.CORRIDA_ABERTAS, null, INICIO_48H, FIM);
        abertas.varrer = true;

        Assert.isTrue(abertas.proximo().varrer, 'A marca do varrimento passa das abertas para as fechadas.');
        Assert.isNotNull(SC_NosPollingQueueable.horaDeVarrimento(), 'A hora do varrimento tem sempre resposta.');
    }

    @IsTest
    static void depoisDoVarrimentoVemSempreOsDetalhes() {
        SC_NosPollingQueueable seguinte = passo(SC_NosConfig.CORRIDA_VARRIMENTO, null, FIM.addDays(-7), FIM).proximo();

        Assert.areEqual(SC_NosConfig.CORRIDA_DETALHES, seguinte.passo, 'O varrimento fecha com os detalhes.');
    }

    @IsTest
    static void detalhesRepetemEnquantoHaOrdensNovasPorLer() {
        SC_NosPollingQueueable actual = passo(SC_NosConfig.CORRIDA_DETALHES, null, FIM, FIM);
        actual.detalhesPendentes = new List<String>{ 'TAS1', 'TAS2' };

        SC_NosPollingQueueable seguinte = actual.proximo();
        Assert.areEqual(SC_NosConfig.CORRIDA_DETALHES, seguinte.passo, 'Com pendentes, repete a passagem de detalhes.');
        Assert.areEqual(1, seguinte.ronda, 'E conta a ronda.');

        actual.ronda = 2;
        Assert.isNull(actual.proximo(), 'Ao fim de três rondas a cadeia pára, para o ciclo caber nos cinco minutos.');

        actual.ronda = 0;
        actual.detalhesPendentes = new List<String>();
        Assert.isNull(actual.proximo(), 'Sem pendentes, os detalhes fecham a cadeia.');
    }

    @IsTest
    static void corridaManualNaoContinuaParaOsPassosSeguintes() {
        SC_NosPollingQueueable manual = passo(SC_NosConfig.CORRIDA_MANUAL, null, INICIO_48H, FIM);
        manual.encadear = false;

        Assert.isNull(manual.proximo(), 'Uma corrida manual lê a janela que lhe deram e pára.');
    }

    @IsTest
    static void janelasPendentesSaoFeitasAntesDoPassoSeguinte() {
        SC_NosPollingQueueable actual = passo(SC_NosConfig.CORRIDA_ABERTAS, null, INICIO_48H, FIM);
        Datetime meio = INICIO_48H.addHours(24);
        actual.janelasPendentes = new List<String>{
            String.valueOf(INICIO_48H.getTime()) + '|' + String.valueOf(meio.getTime()),
            String.valueOf(meio.getTime()) + '|' + String.valueOf(FIM.getTime())
        };

        SC_NosPollingQueueable seguinte = actual.proximo();

        Assert.areEqual(SC_NosConfig.CORRIDA_ABERTAS, seguinte.passo, 'As janelas pendentes fazem-se no mesmo passo.');
        Assert.areEqual(INICIO_48H.getTime(), seguinte.inicio.getTime(), 'Começa pela metade mais antiga.');
        Assert.areEqual(meio.getTime(), seguinte.fim.getTime(), 'E acaba a meio.');
        Assert.areEqual(1, seguinte.janelasPendentes.size(), 'A outra metade fica na fila.');
        Assert.areEqual(1, seguinte.janelasFeitas, 'E a contagem de janelas feitas sobe.');
    }

    // ------------------------------------------------------------------
    // Passo com sucesso
    // ------------------------------------------------------------------

    @IsTest
    static void passoDasAbertasCriaAsOrdensEFechaOLote() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_ListaOk')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        Lote_Integracao__c fechado = recarregar(lote.Id);
        Assert.areEqual('Concluído', fechado.Estado__c, 'Um passo limpo fecha o lote como concluído.');
        Assert.areEqual('Sucesso', fechado.Resultado__c, 'E com resultado de sucesso.');
        Assert.areEqual(56, fechado.Registos_Lidos__c, 'Os lidos são as tarefas da listagem.');
        Assert.areEqual(56, fechado.Criados__c, 'Todas nascem como ordem.');
        Assert.areEqual(56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL], 'Ordens na org.');
    }

    @IsTest
    static void listagemVaziaFechaOLoteSemOrdens() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_FECHADAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_FECHADAS, lote.Id, FIM.addHours(-24), FIM));
        Test.stopTest();

        Lote_Integracao__c fechado = recarregar(lote.Id);
        Assert.areEqual('Concluído', fechado.Estado__c, 'Uma janela sem tarefas é normal e fecha limpa.');
        Assert.areEqual('Vazio', fechado.Resultado__c, 'Com resultado Vazio.');
        Assert.areEqual(0, fechado.Registos_Lidos__c, 'E sem nada lido.');
    }

    // ------------------------------------------------------------------
    // Erros
    // ------------------------------------------------------------------

    @IsTest
    static void corteDoGatewayParteAJanelaAoMeioEFalhaOLote() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_504').comCodigo(504).comTipo('text/plain')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        Lote_Integracao__c falhado = recarregar(lote.Id);
        Assert.areEqual('Falhado', falhado.Estado__c, 'Um corte deixa o lote falhado.');
        Assert.areEqual('Timeout', falhado.Resultado__c, 'Com resultado Timeout.');
        Assert.isTrue(falhado.Erro__c.contains('partida ao meio'), 'O erro diz o que se vai fazer: ' + falhado.Erro__c);
        SC_NosConfig.esquecerEstado();
        Assert.areEqual(1, SC_NosConfig.estado().Contador_504__c, 'O primeiro corte fica contado.');
        Assert.isFalse(SC_NosConfig.suspensaoActiva(), 'Um corte só não suspende.');
    }

    @IsTest
    static void janelaNoMinimoJaNaoSeParteEOLoteFalhaDeVez() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_504').comCodigo(504).comTipo('text/plain')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, FIM.addHours(-6), FIM));
        Test.stopTest();

        Assert.isTrue(
            recarregar(lote.Id).Erro__c.contains('já não se pode partir mais'),
            'Abaixo de seis horas não vale a pena continuar a partir: ' + recarregar(lote.Id).Erro__c
        );
    }

    @IsTest
    static void segundoCorteSeguidoSuspendeAIntegracao() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Contador_504__c = 1;
        SC_NosConfig.gravarEstado();
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.excepcao('Read timed out')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        SC_NosConfig.esquecerEstado();
        Assert.isTrue(SC_NosConfig.suspensaoActiva(), 'Dois cortes seguidos suspendem a integração.');
        Assert.areEqual(1, SC_NosConfig.estado().Suspensoes_Seguidas__c, 'E contam-se as suspensões seguidas.');
        Assert.isTrue(
            recarregar(lote.Id).Erro__c.contains('suspensa por 15 minutos'),
            'O erro diz quanto tempo fica suspensa: ' + recarregar(lote.Id).Erro__c
        );
    }

    @IsTest
    static void enderecoSuspensoNaNosSuspendeSemRepetir() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_500Wso2').comCodigo(500).comTipo('application/xml')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        SC_NosConfig.esquecerEstado();
        Assert.isTrue(SC_NosConfig.suspensaoActiva(), 'Um 303001 suspende logo à primeira.');
        Assert.areEqual(0, SC_NosConfig.estado().Contador_504__c, 'Não é corte de gateway: o contador não sobe.');
        Assert.areEqual('Falhado', recarregar(lote.Id).Estado__c, 'E o lote fica falhado.');
    }

    @IsTest
    static void janelaRecusadaDeixaRejeicaoEFechaComErros() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_FECHADAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_Lista702')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_FECHADAS, lote.Id, FIM.addDays(-7), FIM));
        Test.stopTest();

        Lote_Integracao__c fechado = recarregar(lote.Id);
        Assert.areEqual('Concluído com erros', fechado.Estado__c, 'Uma janela recusada fecha com erros.');
        Assert.areEqual(1, fechado.Rejeitados__c, 'E conta uma rejeição.');
        List<Ocorrencia_Integracao__c> ocorrencias = [
            SELECT Tipo__c, Mensagem__c FROM Ocorrencia_Integracao__c WHERE Lote__c = :lote.Id
        ];
        Assert.areEqual(1, ocorrencias.size(), 'Fica registada a recusa.');
        Assert.areEqual('Rejeição', ocorrencias[0].Tipo__c, 'Como rejeição, que é reprocessável.');
        Assert.isTrue(ocorrencias[0].Mensagem__c.contains('72 hours'), 'Com a razão da NOS: ' + ocorrencias[0].Mensagem__c);
    }

    @IsTest
    static void erroDesconhecidoFalhaOLoteSemSuspender() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":500,"result_message":"Erro interno"}')
        ));

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        Assert.areEqual('Falhado', recarregar(lote.Id).Estado__c, 'Um erro que não reconhecemos falha o lote.');
        SC_NosConfig.esquecerEstado();
        Assert.isFalse(SC_NosConfig.suspensaoActiva(), 'Mas não suspende a integração.');
    }

    @IsTest
    static void travaoDeEmergenciaTravaOPassoAntesDoCallout() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        estado.Kill_Switch__c = true;
        SC_NosConfig.gravarEstado();
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_ABERTAS);
        SC_NosMockFactory mock = new SC_NosMockFactory().registarOmissao(SC_NosMockFactory.ok('SC_NosFx_ListaOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, lote.Id, INICIO_48H, FIM));
        Test.stopTest();

        Assert.areEqual(0, mock.numeroDeChamadas(), 'Com o travão ligado não se chama a NOS.');
        Lote_Integracao__c falhado = recarregar(lote.Id);
        Assert.areEqual('Falhado', falhado.Estado__c, 'E o lote fecha como falhado.');
        Assert.areEqual('Travão de emergência ligado.', falhado.Erro__c, 'Com o motivo por extenso.');
    }

    // ------------------------------------------------------------------
    // Detalhes
    // ------------------------------------------------------------------

    @IsTest
    static void passoDeDetalhesEnriqueceAsOrdensNovas() {
        SC_NosTestDados.catalogo();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(
                '{"ID":"TAS000002537686","Status":"PENDING","RequestType":"OTI-RA3","AssignedGroup":"TL2-Sinalcabo"}'
            ),
            SC_NosTestDados.lote().Id
        );
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_DETALHES);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_DetalheOk')
        ));
        SC_NosPollingQueueable trabalho = passo(SC_NosConfig.CORRIDA_DETALHES, lote.Id, FIM, FIM);
        trabalho.detalhesPendentes = new List<String>{ 'TAS000002537686' };

        Test.startTest();
        System.enqueueJob(trabalho);
        Test.stopTest();

        Lote_Integracao__c fechado = recarregar(lote.Id);
        Assert.areEqual('Concluído', fechado.Estado__c, 'A passagem de detalhes fecha limpa.');
        Assert.areEqual(1, fechado.Registos_Lidos__c, 'Leu um detalhe.');
        Assert.areEqual(1, fechado.Actualizados__c, 'E actualizou a ordem que já existia.');
        Assert.isTrue(
            [SELECT Description FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002537686' LIMIT 1]
                .Description.contains('Interacções na NOS'),
            'A descrição da ordem passa a ter o que o detalhe trouxe.'
        );
    }

    @IsTest
    static void detalheQueANosJaNaoConheceMarcaADesaparecida() {
        SC_NosTestDados.catalogo();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem('{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2"}'),
            SC_NosTestDados.lote().Id
        );
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_DETALHES);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_Detalhe701')
        ));
        SC_NosPollingQueueable trabalho = passo(SC_NosConfig.CORRIDA_DETALHES, lote.Id, FIM, FIM);
        trabalho.detalhesPendentes = new List<String>{ 'TAS9' };

        Test.startTest();
        System.enqueueJob(trabalho);
        Test.stopTest();

        Assert.isTrue(
            [SELECT Desaparecida_Origem__c FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1]
                .Desaparecida_Origem__c,
            'Um 701 marca a ordem como desaparecida na origem.'
        );
        Assert.areEqual(0, recarregar(lote.Id).Rejeitados__c, 'Desaparecer na origem é aviso e não rejeição.');
        Assert.areEqual(1, [SELECT COUNT() FROM Ocorrencia_Integracao__c WHERE Lote__c = :lote.Id], 'Fica o aviso.');
    }

    @IsTest
    static void passoDeDetalhesSemNadaParaLerFechaOLoteVazio() {
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_DETALHES);
        SC_NosMockFactory mock = new SC_NosMockFactory().registarOmissao(SC_NosMockFactory.ok('SC_NosFx_DetalheOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_DETALHES, lote.Id, FIM, FIM));
        Test.stopTest();

        Assert.areEqual(0, mock.numeroDeChamadas(), 'Sem ordens por ler não se chama a NOS.');
        Assert.areEqual('Concluído', recarregar(lote.Id).Estado__c, 'E o lote fecha limpo.');
    }

    @IsTest
    static void corteNoMeioDosDetalhesFalhaOLote() {
        SC_NosTestDados.catalogo();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem('{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2"}'),
            SC_NosTestDados.lote().Id
        );
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_DETALHES);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.ok('SC_NosFx_504').comCodigo(504).comTipo('text/plain')
        ));
        SC_NosPollingQueueable trabalho = passo(SC_NosConfig.CORRIDA_DETALHES, lote.Id, FIM, FIM);
        trabalho.detalhesPendentes = new List<String>{ 'TAS9' };

        Test.startTest();
        System.enqueueJob(trabalho);
        Test.stopTest();

        Lote_Integracao__c falhado = recarregar(lote.Id);
        Assert.areEqual('Falhado', falhado.Estado__c, 'Um corte nos detalhes falha o lote.');
        Assert.isTrue(
            falhado.Erro__c.contains('já não se pode partir mais'),
            'Uma passagem de detalhes não tem janela para partir: ' + falhado.Erro__c
        );
    }

    // ------------------------------------------------------------------
    // Vigilante
    // ------------------------------------------------------------------

    @IsTest
    static void vigilanteFechaOLoteQuandoATransaccaoMorre() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();

        Test.startTest();
        try {
            throw new SC_NosLote.SC_NosLoteException('A transacção rebentou.');
        } catch (Exception e) {
            SC_NosPollingQueueable.fechar(lote.Id, e);
        }
        SC_NosPollingQueueable.fechar(null, null);
        Test.stopTest();

        Lote_Integracao__c falhado = [SELECT Estado__c, Erro__c FROM Lote_Integracao__c WHERE Id = :lote.Id];
        Assert.areEqual('Falhado', falhado.Estado__c, 'Um lote que ficaria Em curso para sempre tem de fechar.');
        Assert.isTrue(falhado.Erro__c.contains('A transacção rebentou.'), 'Com a mensagem original: ' + falhado.Erro__c);
    }

    @IsTest
    static void vigilanteSemExcepcaoAindaAssimFechaOLote() {
        Lote_Integracao__c lote = SC_NosTestDados.lote();

        Test.startTest();
        SC_NosPollingQueueable.fechar(lote.Id, null);
        Test.stopTest();

        Assert.areEqual(
            'A transacção do passo morreu sem mensagem.',
            [SELECT Erro__c FROM Lote_Integracao__c WHERE Id = :lote.Id].Erro__c,
            'Sem excepção fica escrito que morreu sem mensagem.'
        );
    }

    @IsTest
    static void passoDesserializadoPorOutraVersaoDaClasseNaoRebenta() {
        SC_NosTestDados.catalogo();
        Lote_Integracao__c lote = loteDe(SC_NosConfig.CORRIDA_FECHADAS);
        Test.setMock(HttpCalloutMock.class, new SC_NosMockFactory().registarOmissao(
            SC_NosMockFactory.http(200, '{"result_code":0,"result_data":{"data":[],"count":0}}')
        ));
        // O estado que um deploy a meio de um ciclo deixa: campos novos a nulo.
        SC_NosPollingQueueable trabalho = passo(SC_NosConfig.CORRIDA_FECHADAS, lote.Id, FIM.addHours(-6), FIM);
        trabalho.varrer = null;
        trabalho.encadear = null;
        trabalho.ronda = null;
        trabalho.janelasFeitas = null;
        trabalho.janelasPendentes = null;
        trabalho.detalhesPendentes = null;

        Test.startTest();
        System.enqueueJob(trabalho);
        Test.stopTest();

        Assert.areEqual(
            'Concluído', recarregar(lote.Id).Estado__c,
            'Um passo sem os campos novos tem de correr na mesma, com os valores de arranque.'
        );
    }

    @IsTest
    static void passoSemLoteNaoFazNada() {
        SC_NosMockFactory mock = new SC_NosMockFactory().registarOmissao(SC_NosMockFactory.ok('SC_NosFx_ListaOk'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(passo(SC_NosConfig.CORRIDA_ABERTAS, null, INICIO_48H, FIM));
        Test.stopTest();

        Assert.areEqual(0, mock.numeroDeChamadas(), 'Sem lote aberto o passo não chama a NOS.');
    }
}