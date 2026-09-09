/**
 * SC_G1CriterioSelectorTest
 *
 * O selector alimenta o LWC do gate G1, e a lista de criterios vem de Custom Metadata, que os
 * testes veem sempre (nao ha como semear CMT numa transacao de teste). Por isso as asserções
 * sao contra o CMT REAL da org, e e' isso que lhes da valor: uma questao apagada ou desactivada
 * por engano muda o questionario do G1 e a soma dos pesos, e passa a falhar aqui.
 */
@isTest
private class SC_G1CriterioSelectorTest {

    // O questionario do G1 sao 11 questoes (Q01 a Q11), todas activas.
    private static final Integer CRITERIOS_ACTIVOS = 11;

    // getCriteria devolve os criterios ACTIVOS, ordenados por categoria e ordem.
    @isTest static void get_criteria() {
        Test.startTest();
        List<SC_G1_Criterio__mdt> c = SC_G1CriterioSelector.getCriteria();
        Test.stopTest();

        Integer activosNoCmt = [SELECT COUNT() FROM SC_G1_Criterio__mdt WHERE Active__c = true];
        System.assertEquals(CRITERIOS_ACTIVOS, activosNoCmt,
            'O questionario do G1 mudou de tamanho no CMT. Se foi de proposito, actualiza a constante '
            + 'e confirma os pesos; se nao foi, alguem desactivou ou apagou uma questao.');
        System.assertEquals(activosNoCmt, c.size(),
            'O selector tem de devolver todos os criterios activos e so esses.');

        Map<String, SC_G1_Criterio__mdt> porApi = new Map<String, SC_G1_Criterio__mdt>();
        for (SC_G1_Criterio__mdt x : c) {
            System.assertEquals(true, x.Active__c, 'Nenhum criterio inactivo pode entrar na lista.');
            porApi.put(x.API_Name__c, x);
        }

        // DeveloperName conhecido: o Q01 e' a primeira questao do questionario e o campo que
        // alimenta. O DeveloperName nao vem no SELECT do selector, por isso le-se a parte.
        SC_G1_Criterio__mdt q01 = [SELECT DeveloperName, API_Name__c, Active__c, Category__c, Order__c
                                   FROM SC_G1_Criterio__mdt WHERE DeveloperName = 'Q01' LIMIT 1];
        System.assertEquals('G1_Q01_Atratividade__c', q01.API_Name__c,
            'O Q01 tem de continuar a apontar ao campo da atractividade do sector.');
        System.assertEquals(true, q01.Active__c, 'O Q01 tem de estar activo.');
        System.assert(porApi.containsKey(q01.API_Name__c),
            'O criterio Q01 tem de vir na lista devolvida ao LWC.');

        // Ordenacao: o LWC desenha os cartoes pela ordem que recebe e agrupa-os por categoria.
        // NAO se assume ordem alfabetica das categorias: o Category__c e' uma picklist restrita
        // com sorted=false, logo o ORDER BY segue a ordem declarada no valueSet (Mercado,
        // Relacionamento, Financeiro, Tecnico & Competitivo, Estrategico) e nao o alfabeto.
        // O que o ecra exige, e o que aqui se verifica, e' que cada categoria venha num bloco
        // contiguo e que dentro do bloco a ordem das questoes seja crescente.
        Set<String> categoriasFechadas = new Set<String>();
        String categoriaActual = null;
        Decimal ordemAnterior = null;
        for (SC_G1_Criterio__mdt x : c) {
            if (x.Category__c != categoriaActual) {
                System.assertEquals(false, categoriasFechadas.contains(x.Category__c),
                    'A categoria "' + x.Category__c + '" aparece em dois blocos separados da lista.');
                if (categoriaActual != null) categoriasFechadas.add(categoriaActual);
                categoriaActual = x.Category__c;
                ordemAnterior = null;
            }
            if (ordemAnterior != null) {
                System.assert(ordemAnterior <= x.Order__c,
                    'Ordem decrescente dentro de "' + x.Category__c + '": '
                    + ordemAnterior + ' antes de ' + x.Order__c + '.');
            }
            ordemAnterior = x.Order__c;
        }
    }

    // getOpportunityScores: devolve o valor gravado nos campos de score, e '0' nos que faltam.
    @isTest static void get_scores_opp() {
        Opportunity o = new Opportunity(
            Name = 'Crit Test', StageName = 'Identificada',
            CloseDate = Date.today().addDays(30), Empresa_Lider__c = 'Sinalcabo',
            G1_Q01_Atratividade__c = '4'
        );
        insert o;
        Test.startTest();
        Map<String, String> scores = SC_G1CriterioSelector.getOpportunityScores(o.Id);
        Test.stopTest();

        System.assertEquals(CRITERIOS_ACTIVOS, scores.size(),
            'Como admin, todos os criterios activos tem de vir com valor.');
        System.assertEquals('4', scores.get('G1_Q01_Atratividade__c'),
            'O score gravado tem de vir tal e qual, e nao normalizado.');
        System.assertEquals('0', scores.get('Score_Cliente_Estrategico__c'),
            'Um criterio por responder devolve "0", que e como o LWC desenha o cartao vazio.');
    }

    // recordId em branco -> mapa vazio, sem erro.
    @isTest static void record_id_vazio() {
        Test.startTest();
        Map<String, String> s = SC_G1CriterioSelector.getOpportunityScores(null);
        Map<String, String> s2 = SC_G1CriterioSelector.getOpportunityScores('');
        Test.stopTest();
        System.assertEquals(0, s.size());
        System.assertEquals(0, s2.size());
    }

    // FLS por persona: o comercial le os scores a que tem acesso, e nunca mais do que o admin.
    @isTest static void fls_persona_comercial() {
        Opportunity o = new Opportunity(
            Name = 'Crit Persona', StageName = 'Identificada',
            CloseDate = Date.today().addDays(30), Empresa_Lider__c = 'Sinalcabo',
            G1_Q01_Atratividade__c = '3'
        );
        insert o;
        Map<String, String> comoAdmin = SC_G1CriterioSelector.getOpportunityScores(o.Id);

        User comercial = [SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        Test.startTest();
        System.runAs(comercial) {
            Map<String, String> scores = SC_G1CriterioSelector.getOpportunityScores(o.Id);
            // O crivo de FLS e' uma degradacao controlada: campos sem leitura saem do SELECT em
            // vez de rebentar. Logo o comercial nunca pode ver MAIS do que o admin, e o que ve
            // tem de bater certo com o valor gravado.
            System.assert(comoAdmin.keySet().containsAll(scores.keySet()),
                'O comercial nao pode obter criterios que o admin nao obtem.');
            for (String api : scores.keySet()) {
                System.assertEquals(comoAdmin.get(api), scores.get(api),
                    'O valor lido pelo comercial tem de ser o mesmo: ' + api);
            }
        }
        Test.stopTest();
    }

    // Id de opp inexistente -> mapa vazio (a query nao devolve linhas), sem erro.
    @isTest static void opp_inexistente() {
        Test.startTest();
        Map<String, String> s = SC_G1CriterioSelector.getOpportunityScores('006000000000000AAA');
        Test.stopTest();
        System.assertEquals(0, s.size(),
            'Sem registo nao ha scores; devolver um mapa preenchido seria inventar valores.');
    }
}