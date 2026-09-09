/**
 * SC_G1ScoreSaver (DT.6, achado A3 da auditoria)
 *
 * Grava os scores do Gate G1 na Opportunity a partir de um JSON dinamico vindo do ecra.
 * Segurança (Security Review):
 *  - Allow-list: so grava campos que existem na Opportunity, sao custom de score
 *    (sufixo configuravel) e estao acessiveis para escrita (FLS isUpdateable).
 *  - stripInaccessible (AccessType.UPDATABLE) antes do DML, como segunda barreira FLS.
 *  - Nao engole excepcoes: campos rejeitados/invalidos sao coleccionados e, se houver,
 *    lancada AuraHandledException com a lista (em vez de silenciar).
 */
public with sharing class SC_G1ScoreSaver {

    // So se aceitam campos de score do G1 (custom, terminados em __c). Barreira de allow-list
    // contra um JSON que tente gravar campos arbitrarios (ex. OwnerId, Amount).
    @TestVisible
    private static final String SUFIXO_PERMITIDO = '__c';

    public class SaveInput {
        @InvocableVariable(required=true label='Opportunity ID')
        public String recordId;

        @InvocableVariable(required=true label='Scores JSON')
        public String scoresJson;

        @InvocableVariable(label='Precisa Pré-Venda?')
        public Boolean precisaPreVenda;

        @InvocableVariable(label='Stage Name')
        public String stageName;

        @InvocableVariable(label='Propósito da Qualificação')
        public String proposito;
    }

    // B.1: valor da picklist Proposito_Qualificacao__c que marca o arranque da proposta.
    @TestVisible
    private static final String PROPOSITO_PROPOSTA = 'Proposta';

    @InvocableMethod(
        label='Gravar Scores G1'
        description='Guarda os scores do Gate G1 na Opportunity de forma dinâmica, respeitando FLS'
    )
    public static void saveScores(List<SaveInput> inputs) {
        if (inputs == null || inputs.isEmpty()) return;
        SaveInput inp = inputs[0];

        if (String.isBlank(inp.recordId)) {
            throw new AuraHandledException('Oportunidade não indicada.');
        }

        Map<String, Object> scoresMap;
        try {
            scoresMap = (Map<String, Object>) JSON.deserializeUntyped(inp.scoresJson);
        } catch (Exception e) {
            throw new AuraHandledException('JSON de scores inválido: ' + e.getMessage());
        }

        Opportunity opp = new Opportunity(Id = inp.recordId);

        // Mapa de campos reais da Opportunity, para validar nomes e FLS.
        Map<String, Schema.SObjectField> fieldMap = Opportunity.SObjectType.getDescribe().fields.getMap();

        List<String> rejeitadosFls = new List<String>();      // existe mas sem FLS de escrita
        List<String> rejeitadosInvalidos = new List<String>(); // nome nao corresponde a campo permitido

        for (String fieldName : scoresMap.keySet()) {
            if (String.isBlank(fieldName)) continue;
            String fn = fieldName.toLowerCase();

            // Allow-list: tem de ser campo custom (sufixo) e existir na Opportunity.
            if (!fieldName.endsWith(SUFIXO_PERMITIDO) || !fieldMap.containsKey(fn)) {
                rejeitadosInvalidos.add(fieldName);
                continue;
            }
            Schema.DescribeFieldResult dfr = fieldMap.get(fn).getDescribe();
            if (!dfr.isUpdateable()) {
                rejeitadosFls.add(fieldName);
                continue;
            }
            // Grava o valor (string; os campos de score sao Number/Text e fazem coerce).
            opp.put(dfr.getName(), String.valueOf(scoresMap.get(fieldName)));
        }

        if (inp.precisaPreVenda != null
                && Schema.sObjectType.Opportunity.fields.Precisa_Pre_Venda__c.isUpdateable()) {
            opp.Precisa_Pre_Venda__c = inp.precisaPreVenda;
        }
        if (String.isNotBlank(inp.stageName)) {
            opp.StageName = inp.stageName;
            opp.Stage_Update_Via_Flow__c = true;
        }

        // B.1: gravar o proposito da qualificacao (sub-estado de visibilidade).
        if (String.isNotBlank(inp.proposito)
                && Schema.sObjectType.Opportunity.fields.Proposito_Qualificacao__c.isUpdateable()) {
            opp.Proposito_Qualificacao__c = inp.proposito;
        }

        // B.1: este metodo so e' chamado pelo flow no ramo Go do Gate G1. Quando o proposito
        // e' "Proposta", a opp arranca formalmente a proposta -> carimba a flag e a data/hora.
        if (PROPOSITO_PROPOSTA.equalsIgnoreCase(inp.proposito)) {
            if (Schema.sObjectType.Opportunity.fields.Proposta_Iniciada__c.isUpdateable()) {
                opp.Proposta_Iniciada__c = true;
            }
            if (Schema.sObjectType.Opportunity.fields.Data_Proposta_Iniciada__c.isUpdateable()) {
                opp.Data_Proposta_Iniciada__c = System.now();
            }
        }

        // Quantos campos validos vamos mesmo gravar (alem do Id).
        Integer camposParaGravar = opp.getPopulatedFieldsAsMap().size() - 1; // -1 do Id

        // Grava os scores validos (se houver algum), com segunda barreira FLS (stripInaccessible).
        if (camposParaGravar > 0) {
            SObjectAccessDecision dec = Security.stripInaccessible(AccessType.UPDATABLE,
                new List<Opportunity>{ opp });
            Opportunity oppSeguro = (Opportunity) dec.getRecords()[0];
            try {
                update oppSeguro;
            } catch (DmlException e) {
                throw new AuraHandledException('Erro ao guardar os scores: ' + e.getDmlMessage(0));
            }
        }

        // Nao silenciar: se houve campos rejeitados, sinaliza de forma controlada.
        if (!rejeitadosFls.isEmpty() || !rejeitadosInvalidos.isEmpty()) {
            String msg = 'Alguns campos não foram gravados.';
            if (!rejeitadosFls.isEmpty()) {
                msg += ' Sem permissão (FLS): ' + String.join(rejeitadosFls, ', ') + '.';
            }
            if (!rejeitadosInvalidos.isEmpty()) {
                msg += ' Inválidos/não permitidos: ' + String.join(rejeitadosInvalidos, ', ') + '.';
            }
            System.debug(LoggingLevel.WARN, 'SC_G1ScoreSaver: ' + msg);
            throw new AuraHandledException(msg);
        }
    }
}