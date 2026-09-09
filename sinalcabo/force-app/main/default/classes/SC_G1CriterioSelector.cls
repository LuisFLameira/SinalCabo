/**
 * SC_G1CriterioSelector (DT.6, crivo de FLS na leitura dinamica)
 *
 * Le os criterios do G1 (CMT) e os scores actuais da Opportunity.
 * Segurança:
 *  - getOpportunityScores usa SOQL dinamico com nomes de campo vindos do CMT. Cada nome
 *    e validado contra o fieldMap real da Opportunity (mata SOQL injection e campos
 *    inexistentes) e contra o FLS de leitura (isAccessible). So entram campos validos e
 *    legiveis. A query corre WITH USER_MODE (FLS/sharing).
 *  - Nao engole excepcoes silenciosas: campos sem acesso/invalidos sao simplesmente
 *    excluidos do SELECT (degradacao controlada de um metodo de leitura cacheable), nao
 *    apanhados num try/catch que mascara erros reais.
 */
public with sharing class SC_G1CriterioSelector {

    @AuraEnabled(cacheable=true)
    public static List<SC_G1_Criterio__mdt> getCriteria() {
        return [
            SELECT Label, API_Name__c, Category__c, Bg_Color__c,
                   Border_Color__c, Header_Color__c, Icon__c,
                   Order__c, Weight__c, Active__c
            FROM SC_G1_Criterio__mdt
            WHERE Active__c = true
            ORDER BY Category__c, Order__c
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getOpportunityScores(String recordId) {
        Map<String, String> scores = new Map<String, String>();
        if (String.isBlank(recordId)) return scores;

        List<SC_G1_Criterio__mdt> criteria = [
            SELECT API_Name__c FROM SC_G1_Criterio__mdt WHERE Active__c = true
        ];
        if (criteria.isEmpty()) return scores;

        // Valida cada API_Name contra o schema real e o FLS de leitura (allow-list).
        Map<String, Schema.SObjectField> fieldMap = Opportunity.SObjectType.getDescribe().fields.getMap();
        Set<String> camposValidos = new Set<String>{ 'Id' };
        List<String> apiNames = new List<String>();
        for (SC_G1_Criterio__mdt c : criteria) {
            String api = c.API_Name__c;
            if (String.isBlank(api)) continue;
            String key = api.toLowerCase();
            if (!fieldMap.containsKey(key)) continue;                 // campo inexistente -> fora
            if (!fieldMap.get(key).getDescribe().isAccessible()) continue; // sem FLS de leitura -> fora
            camposValidos.add(fieldMap.get(key).getDescribe().getName());
            apiNames.add(fieldMap.get(key).getDescribe().getName());
        }
        if (apiNames.isEmpty()) return scores;

        // SOQL dinamico so com campos validados (nao ha input de utilizador na lista de campos).
        String soql = 'SELECT ' + String.join(new List<String>(camposValidos), ', ')
                    + ' FROM Opportunity WHERE Id = :recordId WITH USER_MODE LIMIT 1';
        List<SObject> results = Database.query(soql);
        if (results.isEmpty()) return scores;

        SObject opp = results[0];
        for (String api : apiNames) {
            Object val = opp.get(api);
            scores.put(api, val != null ? String.valueOf(val) : '0');
        }
        return scores;
    }
}