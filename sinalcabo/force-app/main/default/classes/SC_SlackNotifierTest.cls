/**
 * Teste do SC_SlackNotifier + trigger SC_Opportunity_Slack. O HttpCalloutMock intercepta
 * o lookup por email (users.lookupByEmail) e o envio (chat.postMessage). Cobre a aprovação
 * por nível (DM ao aprovador + auditoria ao canal de gestão), o fecho do ciclo
 * (Aprovado/Recusado) e o fecho comercial (Ganha/Perdida) no canal da direção.
 */
@IsTest
private class SC_SlackNotifierTest {

    private class Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('users.lookupByEmail')) {
                res.setBody('{"ok":true,"user":{"id":"U_TEST"}}');
            } else {
                res.setBody('{"ok":true,"ts":"1"}');
            }
            return res;
        }
    }

    private static Opportunity novaOpp() {
        Account a = new Account(Name = 'PW SLACK Acc');
        insert a;
        Opportunity o = new Opportunity(
            Name = 'PW SLACK Opp', StageName = 'Em Elaboração', CloseDate = Date.today().addDays(30),
            AccountId = a.Id, Amount = 100000, Custo_Estimado__c = 60000,
            Empresa_Lider__c = 'Sinaltech', Direccao_Negocio__c = 'IT',
            Stage_Update_Via_Flow__c = true, Requer_Aprovacao__c = false
        );
        insert o;
        return o;
    }

    private static Map<String, SC_Slack_Log__c> logsPorEvento() {
        Map<String, SC_Slack_Log__c> m = new Map<String, SC_Slack_Log__c>();
        for (SC_Slack_Log__c l : [SELECT Canal__c, Sucesso__c, Evento__c, Mensagem__c FROM SC_Slack_Log__c]) {
            m.put(l.Evento__c, l);
        }
        return m;
    }

    @IsTest
    static void l1_dm_ao_aprovador_e_auditoria_gestao() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Aprovador_Alvo_N1__c = UserInfo.getUserId(),
            Approval_Status__c = 'Aguarda L1', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        Map<String, SC_Slack_Log__c> ev = logsPorEvento();
        Assert.isTrue(ev.containsKey('aprov-l1-dm'), 'devia haver DM ao aprovador N1');
        Assert.isTrue(ev.get('aprov-l1-dm').Sucesso__c, 'a DM (mock ok) deve ficar como sucesso');
        Assert.isTrue(ev.containsKey('aprov-l1-gestao'), 'devia haver auditoria ao canal de gestão');
        Assert.areEqual('C0BEV2SE2F5', ev.get('aprov-l1-gestao').Canal__c, 'auditoria vai ao crm-direcao');
    }

    @IsTest
    static void l2_dm_ao_aprovador_e_auditoria_gestao() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Aprovador_Alvo_N2__c = UserInfo.getUserId(),
            Requer_N2__c = true, Approval_Status__c = 'Aguarda L2', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        Map<String, SC_Slack_Log__c> ev = logsPorEvento();
        Assert.isTrue(ev.containsKey('aprov-l2-dm'), 'devia haver DM ao aprovador N2');
        Assert.isTrue(ev.containsKey('aprov-l2-gestao'), 'devia haver auditoria ao canal de gestão');
    }

    @IsTest
    static void l3_dm_ao_aprovador_e_auditoria_gestao() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Aprovador_Alvo_N3__c = UserInfo.getUserId(),
            Requer_N3__c = true, Approval_Status__c = 'Aguarda L3', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        Map<String, SC_Slack_Log__c> ev = logsPorEvento();
        Assert.isTrue(ev.containsKey('aprov-l3-dm'), 'devia haver DM ao aprovador N3');
        Assert.isTrue(ev.containsKey('aprov-l3-gestao'), 'devia haver auditoria L3 ao canal de gestão');
    }

    // Guarda do nivel fantasma: transicao para "Aguarda L2" sem Requer_N2 (opp de 1 nivel)
    // NAO deve notificar N2 (nem DM nem auditoria).
    @IsTest
    static void nivel_fantasma_l2_nao_notifica() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Aprovador_Alvo_N2__c = UserInfo.getUserId(),
            Requer_N2__c = false, Approval_Status__c = 'Aguarda L2', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        Map<String, SC_Slack_Log__c> ev = logsPorEvento();
        Assert.isFalse(ev.containsKey('aprov-l2-dm'), 'nivel fantasma: NAO deve haver DM N2');
        Assert.isFalse(ev.containsKey('aprov-l2-gestao'), 'nivel fantasma: NAO deve haver auditoria N2');
    }

    @IsTest
    static void aprovado_fecha_ciclo() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Approval_Status__c = 'Aprovado', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        List<SC_Slack_Log__c> logs = [SELECT Canal__c, Evento__c FROM SC_Slack_Log__c WHERE Evento__c = 'aprov-concluida'];
        Assert.isTrue(logs.size() >= 1, 'aprovado deve fechar o ciclo no crm-direcao');
        Assert.areEqual('C0BEV2SE2F5', logs[0].Canal__c);
    }

    @IsTest
    static void recusado_fecha_ciclo() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Approval_Status__c = 'Recusado', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        List<SC_Slack_Log__c> logs = [SELECT Evento__c FROM SC_Slack_Log__c WHERE Evento__c = 'aprov-recusada'];
        Assert.isTrue(logs.size() >= 1, 'recusado deve fechar o ciclo no crm-direcao');
    }

    // O recall e' o quinto estado da picklist e o UNICO que nao gera notificacao nenhuma.
    // E' deliberado: retirar um pedido nao e' uma decisao de aprovacao, e o KAM que carrega em
    // Recall e' o proprio submissor, portanto nao ha ninguem a informar. O handler so mapeia
    // Aguarda L1/L2/L3, Aprovado e Recusado; se alguem lhe acrescentar um ramo generico para
    // "qualquer mudanca de Approval_Status", o canal de gestao passa a receber ruido de recall
    // e este teste apanha-o.
    //
    // A asserção e' de AUSENCIA e por isso tem de olhar para a tabela toda: um teste que so
    // verificasse a ausencia de um evento com nome conhecido nao apanhava um evento com nome novo.
    // O controlo de que o cenario nao esta mudo por outro motivo e' o recusado_fecha_ciclo aqui
    // ao lado, que faz a mesma escrita com um estado que conta e exige log.
    @IsTest
    static void recolhido_nao_gera_evento() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, Aprovador_Alvo_N1__c = UserInfo.getUserId(),
            Requer_Aprovacao__c = true, Approval_Status__c = 'Recolhido',
            StageName = 'Em Elaboração', Stage_Update_Via_Flow__c = true);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM SC_Slack_Log__c],
            'Recolhido nao pode gerar mensagem nenhuma, nem DM ao aprovador nem auditoria ao canal de gestao.');
    }

    @IsTest
    static void ganha_notifica_canal_direccao() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        // Fechar como Ganha exige os campos de contrato (VRs activas: numero, datas e pasta de docs).
        update new Opportunity(Id = o.Id, StageName = 'Closed Won', Stage_Update_Via_Flow__c = true,
            Numero_Contrato__c = 'C-TEST-001', Data_Inicio_Contrato__c = Date.today(),
            Data_Fim_Contrato__c = Date.today().addYears(1),
            Link_Documento__c = 'https://example.com/contrato');
        Test.stopTest();

        List<SC_Slack_Log__c> logs = [SELECT Canal__c, Sucesso__c, Evento__c FROM SC_Slack_Log__c WHERE Evento__c = 'won'];
        Assert.isTrue(logs.size() >= 1, 'ganha deve gerar log no canal da direção');
        Assert.areEqual('C0BEKUATTFZ', logs[0].Canal__c, 'IT deve encaminhar para crm-it');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // C-04: guarda do limite de chamadas externas e encadeamento
    //
    // O orçamento real é de 100 callouts por transacção. Gastá-los num teste seria lento
    // e frágil, por isso os testes injectam um orçamento pequeno pelo orcamentoOverride:
    // o que se prova é a MECÂNICA (corta no orçamento, grava os logs do troço, passa o
    // resto adiante, nada se perde), que é independente do valor do orçamento.
    //
    // LIMITAÇÃO CONHECIDA, e é da plataforma: em contexto de teste não se pode encadear um
    // Queueable a partir de outro. Por isso o encadear() guarda o resto em restoPendente
    // em vez de o enfileirar, e o teste corre o troço seguinte à mão. O que fica por provar
    // por teste é só o System.enqueueJob em si; o resto do caminho é o mesmo código.
    // ═══════════════════════════════════════════════════════════════════════════

    private static List<SC_SlackNotifier.Msg> msgsCanal(Integer quantas) {
        List<SC_SlackNotifier.Msg> l = new List<SC_SlackNotifier.Msg>();
        for (Integer i = 0; i < quantas; i++) {
            l.add(new SC_SlackNotifier.Msg('C_TESTE', null, 'mensagem ' + i, 'ev-' + i));
        }
        return l;
    }

    private static Set<String> eventosGravados() {
        Set<String> s = new Set<String>();
        for (SC_Slack_Log__c l : [SELECT Evento__c FROM SC_Slack_Log__c]) s.add(l.Evento__c);
        return s;
    }

    // Um lote maior do que o orçamento tem de ser processado por COMPLETO ao longo do
    // encadeamento: zero mensagens perdidas, zero logs perdidos, zero repetições.
    //
    // O QUE ESTE TESTE NÃO PODE PROVAR, e porquê. Em produção cada troço é um Queueable
    // novo, logo uma transacção nova. Aqui correm todos na mesma transacção de teste e,
    // como cada troço grava logs (DML), a plataforma recusa os callouts dos troços
    // seguintes com "uncommitted work pending". É artefacto do teste, não do código: o
    // SC_SlackService apanha a excepção, devolve ok=false, e a mensagem fica na mesma
    // registada. Por isso a asserção aqui é sobre a COBERTURA do lote (nenhuma mensagem
    // fica por processar, por registar ou registada duas vezes) e não sobre o sucesso do
    // envio, que é provado no lote_pequeno_nao_encadeia e nos testes por evento.
    @IsTest
    static void lote_acima_do_orcamento_processa_tudo_por_encadeamento() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        List<SC_SlackNotifier.Msg> lote = msgsCanal(8);  // 8 mensagens de canal = 8 callouts

        Integer trocos = 0;
        List<SC_SlackNotifier.Msg> porEnviar = lote;
        Test.startTest();
        while (porEnviar != null && !porEnviar.isEmpty()) {
            // Em produção cada troço é um Queueable NOVO, logo uma transacção nova, e o
            // contador de callouts arranca do zero. Aqui os troços correm todos na mesma
            // transacção de teste, por isso o orçamento é reposicionado a cada volta para
            // simular esse arranque; sem isto o segundo troço não teria orçamento nenhum
            // e o teste ficava preso sem nunca progredir.
            SC_SlackNotifier.orcamentoOverride = Limits.getCallouts() + 3;
            SC_SlackNotifier.restoPendente = null;
            new SC_SlackNotifier(porEnviar).execute(null);
            porEnviar = SC_SlackNotifier.restoPendente;
            trocos++;
            Assert.isTrue(trocos <= 10, 'o encadeamento tem de progredir, nao pode ciclar');
        }
        Test.stopTest();

        Assert.isTrue(trocos > 1, 'o lote tinha de ser partido em mais do que um troco, senao o teste nao prova nada');
        Set<String> evs = eventosGravados();
        Assert.areEqual(8, evs.size(), 'as 8 mensagens tinham de ficar todas registadas');
        for (Integer i = 0; i < 8; i++) {
            Assert.isTrue(evs.contains('ev-' + i), 'faltou o log da mensagem ' + i);
        }
        Assert.areEqual(8, [SELECT COUNT() FROM SC_Slack_Log__c],
            'oito logs para oito mensagens: nenhuma perdida e nenhuma processada duas vezes');
    }

    // O corte tem de acontecer no orçamento: o primeiro troço não pode consumir o lote todo.
    @IsTest
    static void o_troco_respeita_o_orcamento_e_deixa_resto() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        SC_SlackNotifier.orcamentoOverride = 3;
        SC_SlackNotifier.restoPendente = null;

        Test.startTest();
        new SC_SlackNotifier(msgsCanal(8)).execute(null);
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM SC_Slack_Log__c],
            'o troco tem de parar no orcamento (3 callouts = 3 mensagens de canal)');
        Assert.isNotNull(SC_SlackNotifier.restoPendente, 'o resto tinha de ficar para encadear');
        Assert.areEqual(5, SC_SlackNotifier.restoPendente.size(), 'faltam 5 mensagens no resto');
        // a fronteira e' o ponto onde uma mensagem se perde ou se duplica: verifica-se inteira
        for (Integer i = 0; i < 5; i++) {
            Assert.areEqual('ev-' + (i + 3), SC_SlackNotifier.restoPendente[i].evento,
                'o resto tem de continuar exactamente onde o troco parou, pela mesma ordem');
        }
        Set<String> enviados = eventosGravados();
        Assert.isTrue(enviados.contains('ev-0') && enviados.contains('ev-2'), 'o troco enviou ev-0 a ev-2');
        Assert.isFalse(enviados.contains('ev-3'), 'ev-3 nao pode ter sido enviado E deixado no resto');
    }

    // Uma DM por resolver custa DOIS callouts (lookup + post), e a guarda tem de contar
    // callouts e nao mensagens: com orcamento 3 so' cabe UMA DM, nao tres.
    @IsTest
    static void dm_conta_dois_callouts_no_orcamento() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        SC_SlackNotifier.orcamentoOverride = 3;
        SC_SlackNotifier.restoPendente = null;

        List<SC_SlackNotifier.Msg> lote = new List<SC_SlackNotifier.Msg>{
            new SC_SlackNotifier.Msg(null, 'a@example.com', 'dm A', 'dm-a'),
            new SC_SlackNotifier.Msg(null, 'b@example.com', 'dm B', 'dm-b'),
            new SC_SlackNotifier.Msg(null, 'c@example.com', 'dm C', 'dm-c')
        };

        Test.startTest();
        new SC_SlackNotifier(lote).execute(null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM SC_Slack_Log__c],
            'com 3 callouts de orcamento so cabe uma DM (2 callouts); a segunda nao cabe');
        Assert.areEqual(2, SC_SlackNotifier.restoPendente.size(), 'as outras duas DMs ficam para o troco seguinte');
    }

    // Uma falha individual (o Slack a responder ok:false) não pode matar o lote: as
    // mensagens seguintes seguem e TODAS ficam com log, a falhada inclusive.
    private class MockUmaFalha implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getBody() != null && req.getBody().contains('mensagem 1')) {
                res.setBody('{"ok":false,"error":"channel_not_found"}');
            } else {
                res.setBody('{"ok":true,"ts":"1"}');
            }
            return res;
        }
    }

    @IsTest
    static void falha_individual_nao_mata_o_lote() {
        Test.setMock(HttpCalloutMock.class, new MockUmaFalha());
        SC_SlackNotifier.restoPendente = null;

        Test.startTest();
        new SC_SlackNotifier(msgsCanal(4)).execute(null);
        Test.stopTest();

        Assert.areEqual(4, [SELECT COUNT() FROM SC_Slack_Log__c], 'as 4 mensagens ficam registadas');
        List<SC_Slack_Log__c> falhadas = [SELECT Evento__c, Erro__c FROM SC_Slack_Log__c WHERE Sucesso__c = false];
        Assert.areEqual(1, falhadas.size(), 'so a mensagem 1 devia falhar');
        Assert.areEqual('ev-1', falhadas[0].Evento__c, 'a falhada e a mensagem 1');
        Assert.areEqual('channel_not_found', falhadas[0].Erro__c, 'o erro do Slack fica no log');
        Assert.areEqual(3, [SELECT COUNT() FROM SC_Slack_Log__c WHERE Sucesso__c = true],
            'as outras tres seguiram na mesma');
    }

    // O caso mais duro da garantia "uma falha não mata o lote": uma mensagem inutilizável
    // no meio da lista. O SC_SlackService nunca lança (apanha tudo e devolve Result), por
    // isso a única forma de provar o try/catch por mensagem é esta.
    @IsTest
    static void mensagem_invalida_nao_mata_o_lote() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        SC_SlackNotifier.restoPendente = null;

        List<SC_SlackNotifier.Msg> lote = msgsCanal(1);
        lote.add(null);                                   // mensagem inutilizável
        lote.addAll(msgsCanal(1));

        Test.startTest();
        new SC_SlackNotifier(lote).execute(null);
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM SC_Slack_Log__c],
            'as tres entradas ficam registadas, a invalida inclusive');
        List<SC_Slack_Log__c> invalida = [SELECT Canal__c, Erro__c FROM SC_Slack_Log__c WHERE Evento__c = 'msg-invalida'];
        Assert.areEqual(1, invalida.size(), 'a mensagem invalida tem de deixar rasto');
        Assert.areEqual('(mensagem invalida)', invalida[0].Canal__c);
        Assert.isTrue(invalida[0].Erro__c.startsWith('excepcao:'), 'o log guarda a excepcao');
        Assert.areEqual(2, [SELECT COUNT() FROM SC_Slack_Log__c WHERE Sucesso__c = true],
            'as duas mensagens boas seguiram na mesma');
    }

    // Sem lote grande o comportamento não muda: nada fica pendente de encadeamento.
    @IsTest
    static void lote_pequeno_nao_encadeia() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        SC_SlackNotifier.restoPendente = null;

        Test.startTest();
        new SC_SlackNotifier(msgsCanal(3)).execute(null);
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM SC_Slack_Log__c], 'as 3 mensagens seguem no mesmo troco');
        Assert.isNull(SC_SlackNotifier.restoPendente, 'um lote pequeno nao pode deixar resto');
    }

    @IsTest
    static void perdida_notifica_com_motivo() {
        Opportunity o = novaOpp();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Test.startTest();
        update new Opportunity(Id = o.Id, StageName = 'Closed Lost', Stage_Update_Via_Flow__c = true,
            Motivo_Perda__c = 'Concorrência', Concorrente_Vencedor__c = 'ACME');
        Test.stopTest();

        List<SC_Slack_Log__c> logs = [SELECT Mensagem__c, Evento__c FROM SC_Slack_Log__c WHERE Evento__c = 'lost'];
        Assert.isTrue(logs.size() >= 1, 'perdida deve gerar log');
        Assert.isTrue(logs[0].Mensagem__c.contains('Concorrência'), 'a mensagem deve incluir o motivo');
    }
}