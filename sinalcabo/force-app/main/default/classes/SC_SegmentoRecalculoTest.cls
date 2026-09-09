/**
 * Testes do batch, do agendamento e das duas entradas dos botões.
 *
 * LIMITE CONHECIDO, e é preciso dizê-lo: em contexto de teste o Salesforce só executa UM nível
 * de assíncrono por Test.stopTest(). A cadeia real do recálculo em massa tem quatro elos
 * (Queueable que liga o bypass, batch da fase Individual, batch da fase Grupo, Queueable que
 * desliga), portanto ela NÃO corre inteira aqui. O que estes testes cobrem é cada elo por si e o
 * arranque da cadeia. A cadeia completa foi verificada na org com um script, não em Apex, e o
 * ficheiro está em outputs/verificar-batch-segmento-2026-08-04.apex.
 */
@isTest
private class SC_SegmentoRecalculoTest {

    private static Opportunity ganha(Id contaId, String nome, Decimal valor, Decimal custo, Date d) {
        return new Opportunity(
            Name = nome, AccountId = contaId, StageName = 'Closed Won',
            CloseDate = d, Amount = valor, Custo_Estimado__c = custo,
            Empresa_Lider__c = 'Sinalcabo',
            Data_Inicio_Contrato__c = d, Data_Fim_Contrato__c = d.addYears(1),
            Numero_Contrato__c = 'TR-' + nome, Link_Documento__c = 'https://exemplo.invalid/tr');
    }
    private static Date dentro() { return SC_SegmentoCalculo.inicioMesCorrente().addMonths(-2); }
    private static Date fora()   { return SC_SegmentoCalculo.inicioMesCorrente().addMonths(-20); }

    // ───────────────────────────── o batch ─────────────────────────────

    @isTest static void batch_completo_corrige_e_registha_o_que_fez() {
        Account a = new Account(Name = 'TR completo');
        insert a;
        insert ganha(a.Id, 'antiga', 4000000, 2000000, fora());
        update new Account(Id = a.Id, Closed_Won_12M__c = 4000000, Segmento__c = 'Platina');

        Test.startTest();
        Database.executeBatch(new SC_SegmentoRecalculoBatch('Completo', 'Individual', null), 200);
        Test.stopTest();

        Account r = [SELECT Closed_Won_12M__c, Segmento__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(null, r.Segmento__c, 'o batch corrigiu o segmento desactualizado');

        List<SC_Recalculo_Log__c> logs = [
            SELECT Modo__c, Fase__c, Contas_Avaliadas__c, Contas_Alteradas__c,
                   Segmentos_Alterados__c, Erros__c, Detalhe__c
            FROM SC_Recalculo_Log__c WHERE Fase__c = 'Individual'];
        System.assertEquals(1, logs.size(), 'uma linha de log por fase, sempre');
        System.assertEquals('Completo', logs[0].Modo__c);
        System.assert(logs[0].Contas_Avaliadas__c >= 1, 'avaliou pelo menos a nossa conta');
        System.assertEquals(1, logs[0].Segmentos_Alterados__c,
            'a contagem de segmentos alterados é o número que torna visível uma fronteira que pare de apanhar casos');
        System.assertEquals(0, logs[0].Erros__c);
        System.assert(logs[0].Detalhe__c.contains('TR completo'), 'e o detalhe diz qual conta mudou');
    }

    @isTest static void batch_da_fase_grupo_recalcula_as_maes() {
        Account mae = new Account(Name = 'TR G mãe');
        insert mae;
        Account filha = new Account(Name = 'TR G filha', ParentId = mae.Id);
        insert filha;
        insert ganha(filha.Id, 'g', 2000000, 1000000, dentro());
        // deixa o grupo da mãe errado de propósito
        update new Account(Id = mae.Id, Total_Grupo_12M__c = 0, Segmento_Grupo__c = null);

        Test.startTest();
        Database.executeBatch(
            new SC_SegmentoRecalculoBatch('Completo', 'Grupo', new Set<Id>{ mae.Id }), 100);
        Test.stopTest();

        Account r = [SELECT Total_Grupo_12M__c, Segmento_Grupo__c FROM Account WHERE Id = :mae.Id];
        System.assertEquals(2000000, r.Total_Grupo_12M__c, 'o grupo da mãe foi refeito');
        System.assertNotEquals(null, r.Segmento_Grupo__c, 'e ganhou segmento de grupo');

        List<SC_Recalculo_Log__c> logs = [SELECT Fase__c FROM SC_Recalculo_Log__c
                                          WHERE Fase__c = 'Grupo'];
        System.assertEquals(1, logs.size(), 'a fase Grupo também escreve a sua linha');
    }

    @isTest static void fronteira_apanha_o_mes_que_entra_e_o_que_sai() {
        Date iniMes = SC_SegmentoCalculo.inicioMesCorrente();
        Account entra = new Account(Name = 'TR entra');
        Account sai = new Account(Name = 'TR sai');
        Account nem = new Account(Name = 'TR nem uma nem outra');
        insert new List<Account>{ entra, sai, nem };

        insert new List<Opportunity>{
            // mês anterior ao corrente: acabou de ENTRAR na janela
            ganha(entra.Id, 'entra', 100000, 50000, iniMes.addMonths(-1).addDays(5)),
            // mês imediatamente antes do início da janela: acabou de SAIR
            ganha(sai.Id, 'sai', 100000, 50000, SC_SegmentoCalculo.inicioJanela().addMonths(-1).addDays(5)),
            // a meio da janela: não mudou de lado nenhum
            ganha(nem.Id, 'nem', 100000, 50000, iniMes.addMonths(-6))
        };

        Set<Id> f = SC_SegmentoRecalculoBatch.contasNaFronteira();
        System.assert(f.contains(entra.Id), 'a conta com negócio no mês que entrou tem de ser recalculada');
        System.assert(f.contains(sai.Id), 'e a do mês que saiu, que é a que desce de escalão');
        System.assert(!f.contains(nem.Id),
            'e uma conta a meio da janela não, senão o modo Mensal era o modo Completo com outro nome');
    }

    @isTest static void modo_mensal_arranca_sem_rebentar() {
        Account a = new Account(Name = 'TR mensal');
        insert a;
        insert ganha(a.Id, 'm', 300000, 150000,
                     SC_SegmentoCalculo.inicioMesCorrente().addMonths(-1).addDays(2));

        Test.startTest();
        Database.executeBatch(new SC_SegmentoRecalculoBatch('Mensal', 'Individual', null), 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM SC_Recalculo_Log__c WHERE Modo__c = 'Mensal'],
            'o modo Mensal também deixa rasto');
    }

    // ───────────────────────────── o bypass ─────────────────────────────

    @isTest static void bypass_liga_e_desliga_e_e_idempotente() {
        Test.startTest();
        SC_SegmentoRecalculo.porBypass(true);
        SC_SegmentoRecalculo.porBypass(true);              // segunda vez não deve fazer DML
        SC_Aprovacao_Config__c depoisDeLigar =
            SC_Aprovacao_Config__c.getInstance(UserInfo.getUserId());
        SC_SegmentoRecalculo.porBypass(false);
        Test.stopTest();

        System.assertEquals(true, depoisDeLigar.Bypass_Rollup_Grupo__c, 'ligou');
        System.assertEquals(false,
            SC_Aprovacao_Config__c.getInstance(UserInfo.getUserId()).Bypass_Rollup_Grupo__c,
            'e desligou, que é a parte que não pode falhar: um bypass preso desliga o rollup de grupo em silêncio');
    }

    // ───────────────────────── o botão de uma conta ─────────────────────────

    @isTest static void botao_da_conta_corrige_e_diz_o_que_fez() {
        Account a = new Account(Name = 'TR botão');
        insert a;
        insert ganha(a.Id, 'b', 4000000, 2000000, fora());
        update new Account(Id = a.Id, Closed_Won_12M__c = 4000000, Segmento__c = 'Platina');

        SC_SegmentoRecalculoContaAction.Pedido p = new SC_SegmentoRecalculoContaAction.Pedido();
        p.contaId = a.Id;

        Test.startTest();
        List<SC_SegmentoRecalculoContaAction.Resposta> rs =
            SC_SegmentoRecalculoContaAction.executar(
                new List<SC_SegmentoRecalculoContaAction.Pedido>{ p });
        Test.stopTest();

        System.assertEquals(1, rs.size());
        System.assertEquals(true, rs[0].alterou);
        System.assert(rs[0].mensagem.contains('Segmento'),
            'a mensagem tem de dizer o que mudou, senão a pessoa vai verificar à mão: ' + rs[0].mensagem);
        System.assertEquals(null, [SELECT Segmento__c FROM Account WHERE Id = :a.Id].Segmento__c);
    }

    @isTest static void botao_da_conta_diz_quando_nao_ha_nada_a_fazer() {
        Account a = new Account(Name = 'TR botão certo');
        insert a;
        insert ganha(a.Id, 'bc', 300000, 150000, dentro());

        SC_SegmentoRecalculoContaAction.Pedido p = new SC_SegmentoRecalculoContaAction.Pedido();
        p.contaId = a.Id;

        Test.startTest();
        List<SC_SegmentoRecalculoContaAction.Resposta> rs =
            SC_SegmentoRecalculoContaAction.executar(
                new List<SC_SegmentoRecalculoContaAction.Pedido>{ p });
        Test.stopTest();

        System.assertEquals(false, rs[0].alterou);
        System.assert(rs[0].mensagem.contains('já estavam certos'), rs[0].mensagem);
    }

    @isTest static void botao_da_conta_trata_a_conta_que_e_mae() {
        Account mae = new Account(Name = 'TR botão mãe');
        insert mae;
        Account filha = new Account(Name = 'TR botão filha', ParentId = mae.Id);
        insert filha;
        insert ganha(filha.Id, 'bm', 2000000, 1000000, dentro());
        // O flow de grupo já fez a mãe ao inserir a oportunidade. Estraga-se de propósito, para
        // provar que o botão da ficha da MÃE a repõe, caso que o flow não cobre por disparar na filha.
        update new Account(Id = mae.Id, Total_Grupo_12M__c = 0, Segmento_Grupo__c = null);

        Test.startTest();
        SC_SegmentoRecalculo.umaConta(mae.Id);
        Test.stopTest();

        System.assertEquals(2000000,
            [SELECT Total_Grupo_12M__c FROM Account WHERE Id = :mae.Id].Total_Grupo_12M__c,
            'o botão na ficha de uma mãe tem de refazer o agregado dela');
    }

    // ───────────────────── arranque em massa e agendamento ─────────────────────

    @isTest static void completo_e_mensal_enfileiram_o_arranque() {
        Test.startTest();
        SC_SegmentoRecalculo.completo();
        SC_SegmentoRecalculo.mensal();
        Integer enfileirados = Limits.getQueueableJobs();
        Test.stopTest();
        System.assertEquals(2, enfileirados,
            'cada arranque enfileira um Queueable, que é o que evita MIXED_DML_OPERATION ao ligar o bypass');
    }

    @isTest static void invocavel_do_recalculo_completo_responde() {
        Test.startTest();
        List<SC_SegmentoRecalculoTodasAction.Resposta> r =
            SC_SegmentoRecalculoTodasAction.executar(
                new List<SC_SegmentoRecalculoTodasAction.Pedido>{
                    new SC_SegmentoRecalculoTodasAction.Pedido() });
        Test.stopTest();
        System.assertEquals(1, r.size());
        System.assert(r[0].mensagem.contains('Log'),
            'a resposta diz onde ver o resultado: ' + r[0].mensagem);
    }

    @isTest static void agendamento_mensal_corre() {
        Test.startTest();
        String jobId = System.schedule('TR recalculo teste', '0 30 3 1 * ?',
                                       new SC_SegmentoRecalculoSchedule());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }

    // ───────────────────────────── o log ─────────────────────────────

    @isTest static void detalhe_muito_grande_e_truncado_com_aviso() {
        SC_SegmentoCalculo.Contagem c = new SC_SegmentoCalculo.Contagem();
        c.avaliadas = 9000;
        for (Integer i = 0; i < 4000; i++) {
            c.detalhe.add('conta número ' + i + ': sem segmento -> Bronze (volume 12345)');
        }

        Test.startTest();
        SC_SegmentoRecalculo.registarLog('Completo', 'Individual', c, 42);
        Test.stopTest();

        SC_Recalculo_Log__c log = [SELECT Detalhe__c, Duracao_Segundos__c
                                   FROM SC_Recalculo_Log__c LIMIT 1];
        Integer maximo = SC_Recalculo_Log__c.Detalhe__c.getDescribe().getLength();
        System.assert(log.Detalhe__c.length() <= maximo,
            'o detalhe tem de caber no campo, senão o insert rebenta e perde-se o log inteiro');
        System.assert(log.Detalhe__c.endsWith('linhas no total]'),
            'e tem de dizer que foi truncado, senão parece que só houve estas mudanças');
        System.assertEquals(42, log.Duracao_Segundos__c);
    }
}