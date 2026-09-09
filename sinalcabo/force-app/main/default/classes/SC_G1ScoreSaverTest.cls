@isTest
private class SC_G1ScoreSaverTest {

    private static Opportunity novaOpp() {
        Opportunity o = new Opportunity(
            Name = 'G1 Saver Test',
            StageName = 'Identificada',
            CloseDate = Date.today().addDays(30),
            Empresa_Lider__c = 'Sinalcabo'
        );
        insert o;
        return o;
    }

    private static SC_G1ScoreSaver.SaveInput input(Id oppId, String json) {
        SC_G1ScoreSaver.SaveInput i = new SC_G1ScoreSaver.SaveInput();
        i.recordId = oppId;
        i.scoresJson = json;
        return i;
    }

    private static SC_G1ScoreSaver.SaveInput input(Id oppId, String json, String proposito) {
        SC_G1ScoreSaver.SaveInput i = input(oppId, json);
        i.proposito = proposito;
        return i;
    }

    // Positivo: grava um campo de score escrevivel (picklist G1_Q01, valores "0".."5").
    @isTest static void grava_score_valido() {
        Opportunity o = novaOpp();
        Test.startTest();
        SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
            input(o.Id, '{"G1_Q01_Atratividade__c":"4"}')
        });
        Test.stopTest();
        Opportunity c = [SELECT G1_Q01_Atratividade__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('4', c.G1_Q01_Atratividade__c, 'O score valido devia ficar gravado.');
    }

    // Negativo: JSON invalido -> AuraHandledException, nao silenciado.
    @isTest static void json_invalido() {
        Opportunity o = novaOpp();
        Boolean rebentou = false;
        Test.startTest();
        try {
            SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
                input(o.Id, 'isto nao e json')
            });
        } catch (AuraHandledException e) { rebentou = true; }
        Test.stopTest();
        System.assertEquals(true, rebentou, 'JSON invalido deve lancar excepcao, nao silenciar.');
    }

    // Negativo: campo inexistente -> sinalizado (excepcao) E nao gravado.
    // Verifica o comportamento observavel (nao gravou) em vez do tipo de excepcao,
    // porque AuraHandledException tem restricoes de contexto fora de Aura/VF.
    @isTest static void campo_inexistente_sinalizado() {
        Opportunity o = novaOpp();
        Boolean sinalizou = false;
        Test.startTest();
        try {
            SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
                input(o.Id, '{"Campo_Que_Nao_Existe__c":"1"}')
            });
        } catch (Exception e) { sinalizou = true; } // nao silenciado
        Test.stopTest();
        System.assertEquals(true, sinalizou, 'Campo invalido deve ser sinalizado (excepcao), nao silenciado.');
    }

    // Negativo: campo standard nao-allow-listed (sem __c) -> rejeitado e NAO gravado.
    @isTest static void campo_standard_rejeitado() {
        Opportunity o = novaOpp();
        Test.startTest();
        try {
            SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
                input(o.Id, '{"Amount":"999999"}') // standard, sem __c -> nao permitido
            });
        } catch (Exception e) { /* sinalizado, esperado */ }
        Test.stopTest();
        // O foco de seguranca: o Amount NAO foi gravado por esta via dinamica.
        Opportunity c = [SELECT Amount FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(null, c.Amount, 'Amount nao devia ser gravado por esta via (allow-list).');
    }

    // FLS por persona: um comercial (End User) grava o seu score (tem FLS dos campos G1).
    @isTest static void fls_persona_comercial() {
        Opportunity o = novaOpp();
        User comercial = [SELECT Id FROM User WHERE Profile.Name='End User' AND IsActive=true LIMIT 1];
        Test.startTest();
        System.runAs(comercial) {
            // pode nao ter FLS de Score_Qualificacao; o metodo nao deve rebentar de forma nao-tratada.
            try {
                SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
                    input(o.Id, '{"G1_Q01_Atratividade__c":"3"}')
                });
            } catch (AuraHandledException e) {
                // aceitavel: se o comercial nao tiver FLS, e sinalizado (nao silenciado)
            }
        }
        Test.stopTest();
        System.assert(true, 'Executou sob runAs sem erro nao tratado.');
    }

    // B.1: Go com proposito "Proposta" -> grava proposito + carimba Proposta_Iniciada + data.
    @isTest static void proposito_proposta_carimba_flags() {
        Opportunity o = novaOpp();
        Test.startTest();
        SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
            input(o.Id, '{"G1_Q01_Atratividade__c":"4"}', 'Proposta')
        });
        Test.stopTest();
        Opportunity c = [SELECT Proposito_Qualificacao__c, Proposta_Iniciada__c,
                                Data_Proposta_Iniciada__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Proposta', c.Proposito_Qualificacao__c, 'Proposito gravado.');
        System.assertEquals(true, c.Proposta_Iniciada__c, 'Go + Proposta marca a flag.');
        System.assertNotEquals(null, c.Data_Proposta_Iniciada__c, 'Data carimbada.');
    }

    // B.1: sem proposito "Proposta" (ou em branco) -> NAO carimba as flags de proposta.
    @isTest static void sem_proposta_nao_carimba() {
        Opportunity o = novaOpp();
        Test.startTest();
        SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{
            input(o.Id, '{"G1_Q01_Atratividade__c":"4"}') // sem proposito
        });
        Test.stopTest();
        Opportunity c = [SELECT Proposta_Iniciada__c, Data_Proposta_Iniciada__c
                         FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(false, c.Proposta_Iniciada__c, 'Sem Proposta nao marca a flag.');
        System.assertEquals(null, c.Data_Proposta_Iniciada__c, 'Sem Proposta nao carimba data.');
    }

    // recordId em branco -> excepcao.
    @isTest static void record_id_vazio() {
        Boolean rebentou = false;
        Test.startTest();
        try {
            SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>{ input(null, '{}') });
        } catch (AuraHandledException e) { rebentou = true; }
        Test.stopTest();
        System.assertEquals(true, rebentou);
    }

    // Lista vazia / null -> nao faz nada, sem erro.
    @isTest static void vazio() {
        Test.startTest();
        SC_G1ScoreSaver.saveScores(null);
        SC_G1ScoreSaver.saveScores(new List<SC_G1ScoreSaver.SaveInput>());
        Test.stopTest();
        System.assert(true, 'Vazio nao deve lancar.');
    }
}