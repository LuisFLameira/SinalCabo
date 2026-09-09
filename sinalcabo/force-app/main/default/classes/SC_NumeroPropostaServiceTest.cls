/**
 * Testes do SC_NumeroPropostaService (B.4).
 *
 * O QUE ESTES TESTES NAO PROVAM, e importa dize-lo: a correccao do lock pessimista. Um teste
 * Apex corre numa unica transaccao, logo nao ha concorrencia para o `FOR UPDATE` resolver.
 * Uma suite verde NAO garante ausencia de numeros duplicados sob carga simultanea; isso so'
 * se prova com duas sessoes em paralelo, e esse teste e' manual.
 *
 * A data e' injectada em vez de se usar Date.today(), senao o teste da viragem de ano seria
 * uma bomba a 1 de Janeiro.
 */
@isTest
private class SC_NumeroPropostaServiceTest {

    private static final String AREA_COM_SIGLA = 'Energias Renováveis';   // UN SOLAR no CMT
    private static final String TIPO_DA_AREA   = 'Solar';

    private static Account conta() {
        Account a = new Account(Name = 'Conta Numeracao');
        insert a;
        return a;
    }

    private static Opportunity nova(Account a, String area, String tipo) {
        return new Opportunity(
            Name = 'Opp ' + area,
            AccountId = a.Id,
            StageName = 'Identificada',
            CloseDate = Date.today().addMonths(1),
            Amount = 10000,
            Direccao_Negocio__c = 'Energia',
            Area_Negocio__c = area,
            Tipo_Negocio__c = tipo,
            Empresa_Lider__c = 'Sinalcabo'
        );
    }

    @isTest static void atribui_numero_no_formato_certo() {
        Account a = conta();
        Test.startTest();
        Opportunity o = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        insert o;
        Test.stopTest();

        o = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :o.Id];
        System.assertNotEquals(null, o.Numero_Proposta__c, 'A oportunidade tem de nascer com numero.');
        String anoCurto = String.valueOf(Date.today().year()).right(2);
        System.assertEquals('UN SOLAR/00001/' + anoCurto, o.Numero_Proposta__c,
            'Formato SIGLA/NNNNN/AA, com o sequencial a comecar em 1 e cinco casas.');
    }

    @isTest static void serie_incrementa_e_e_por_sigla() {
        Account a = conta();
        Test.startTest();
        List<Opportunity> lote = new List<Opportunity>{
            nova(a, AREA_COM_SIGLA, TIPO_DA_AREA),
            nova(a, AREA_COM_SIGLA, TIPO_DA_AREA),
            nova(a, 'Solarus', 'Solar')            // outra area, outra sigla: DN SOLARUS
        };
        insert lote;
        Test.stopTest();

        Map<Id, Opportunity> res = new Map<Id, Opportunity>(
            [SELECT Id, Area_Negocio__c, Numero_Proposta__c FROM Opportunity WHERE Id IN :lote]);
        String anoCurto = String.valueOf(Date.today().year()).right(2);

        List<String> renovaveis = new List<String>();
        String solarus;
        for (Opportunity o : res.values()) {
            if (o.Area_Negocio__c == 'Solarus') solarus = o.Numero_Proposta__c;
            else renovaveis.add(o.Numero_Proposta__c);
        }
        renovaveis.sort();
        System.assertEquals(2, renovaveis.size(), 'Duas na mesma sigla.');
        System.assertEquals('UN SOLAR/00001/' + anoCurto, renovaveis[0], 'Primeira da serie.');
        System.assertEquals('UN SOLAR/00002/' + anoCurto, renovaveis[1], 'Segunda da serie, incrementa.');
        System.assertEquals('DN SOLARUS/00001/' + anoCurto, solarus,
            'Sigla diferente tem serie propria, e comeca tambem em 1.');
    }

    @isTest static void um_soql_e_um_dml_em_lote_grande() {
        Account a = conta();
        List<Opportunity> lote = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) lote.add(nova(a, AREA_COM_SIGLA, TIPO_DA_AREA));

        Test.startTest();
        Integer soqlAntes = Limits.getQueries();
        insert lote;
        Integer soqlGasto = Limits.getQueries() - soqlAntes;
        Test.stopTest();

        Set<String> numeros = new Set<String>();
        for (Opportunity o : [SELECT Numero_Proposta__c FROM Opportunity WHERE Id IN :lote]) {
            numeros.add(o.Numero_Proposta__c);
        }
        System.assertEquals(200, numeros.size(),
            '200 oportunidades num insert tem de dar 200 numeros DISTINTOS.');
        System.assert(soqlGasto <= 5,
            'O servico tem de ser bulk-safe: poucas queries independentemente do lote. Gastou ' + soqlGasto);

        Contador_Proposta__c c = [SELECT Ultimo_Numero__c FROM Contador_Proposta__c
                                  WHERE Sigla__c = 'UN SOLAR' LIMIT 1];
        System.assertEquals(200, c.Ultimo_Numero__c, 'O contador tem de refletir as 200.');
    }

    @isTest static void area_sem_sigla_fica_sem_numero_e_nao_bloqueia() {
        // 'Gestão Comercial' tem sigla; usa-se uma area cujo CMT esta inactivo: Energias Algarve.
        // Como saiu da cascata, cria-se a opp sem area para simular "sem sigla mapeada".
        Account a = conta();
        Opportunity o = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        o.Area_Negocio__c = null;
        o.Tipo_Negocio__c = null;

        Test.startTest();
        Database.SaveResult sr = Database.insert(o, false);
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(),
            'Sem sigla, a criacao NAO e bloqueada: decisao do Joel de 04/08.');
        Opportunity gravada = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :sr.getId()];
        System.assertEquals(null, gravada.Numero_Proposta__c,
            'Sem sigla mapeada, o numero fica vazio.');
    }

    @isTest static void bypass_da_migracao_nao_gasta_a_serie() {
        insert new SC_Aprovacao_Config__c(SetupOwnerId = UserInfo.getUserId(), Bypass_Numeracao__c = true);
        Account a = conta();

        Test.startTest();
        Opportunity o = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        insert o;
        Test.stopTest();

        o = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(null, o.Numero_Proposta__c, 'Com bypass, nao se atribui numero.');
        System.assertEquals(0, [SELECT COUNT() FROM Contador_Proposta__c],
            'Com bypass, o contador nem chega a ser criado: a serie fica intacta.');
    }

    @isTest static void numero_que_ja_vem_preenchido_e_respeitado() {
        // Caso da migracao com numeros historicos: o valor que vem no ficheiro nao e' sobreposto.
        Account a = conta();
        Opportunity o = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        o.Numero_Proposta__c = 'HISTORICO/00042/24';

        Test.startTest();
        insert o;
        Test.stopTest();

        o = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('HISTORICO/00042/24', o.Numero_Proposta__c,
            'Um numero que ja vem no registo nao e substituido.');
    }

    @isTest static void viragem_de_ano_abre_serie_nova() {
        Account a = conta();
        // 1) uma opp "no ano passado"
        SC_NumeroPropostaService.hoje = Date.newInstance(2025, 12, 31);
        Opportunity ontem = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        insert ontem;

        // 2) outra no dia seguinte, ja noutro ano
        SC_NumeroPropostaService.hoje = Date.newInstance(2026, 1, 1);
        Test.startTest();
        Opportunity anoNovo = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        insert anoNovo;
        Test.stopTest();

        ontem = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :ontem.Id];
        anoNovo = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :anoNovo.Id];
        System.assertEquals('UN SOLAR/00001/25', ontem.Numero_Proposta__c, 'Serie de 2025.');
        System.assertEquals('UN SOLAR/00001/26', anoNovo.Numero_Proposta__c,
            'A serie reinicia em 1 no ano novo, sem tarefa anual nenhuma.');
        System.assertEquals(2, [SELECT COUNT() FROM Contador_Proposta__c],
            'Duas linhas de contador, uma por ano.');
    }

    @isTest static void contador_travado_nao_emite() {
        Account a = conta();
        Integer ano = Date.today().year();
        insert new Contador_Proposta__c(
            Name = 'UN SOLAR|' + ano, Chave__c = 'UN SOLAR|' + ano,
            Sigla__c = 'UN SOLAR', Ano__c = ano, Ultimo_Numero__c = 10, Activo__c = false);

        Test.startTest();
        Opportunity o = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        insert o;
        Test.stopTest();

        o = [SELECT Numero_Proposta__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(null, o.Numero_Proposta__c,
            'Contador inactivo: a oportunidade nasce sem numero em vez de rebentar.');
    }

    @isTest static void unicidade_impede_numero_repetido() {
        Account a = conta();
        Opportunity primeira = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        primeira.Numero_Proposta__c = 'MANUAL/00001/26';
        insert primeira;

        Opportunity segunda = nova(a, AREA_COM_SIGLA, TIPO_DA_AREA);
        segunda.Numero_Proposta__c = 'MANUAL/00001/26';

        Test.startTest();
        Database.SaveResult sr = Database.insert(segunda, false);
        Test.stopTest();

        System.assertEquals(false, sr.isSuccess(),
            'O campo e unico: um numero repetido posto a mao tem de ser rejeitado.');
    }
}