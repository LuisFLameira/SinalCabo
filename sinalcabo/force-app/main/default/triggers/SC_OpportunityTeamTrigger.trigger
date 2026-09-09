/**
 * SC_OpportunityTeamTrigger
 * -------------------------------------------------------------------------
 * Sincroniza o membro "Pre-Venda" da Opportunity Team com o campo
 * Opportunity.Pre_Venda_Lider__c. Toda a logica vive no handler.
 *
 * Corre em 'after' porque o OpportunityTeamMember precisa do Id da Opportunity.
 */
trigger SC_OpportunityTeamTrigger on Opportunity (after insert, after update) {
    SC_OpportunityPreVendaTeamHandler.reconcile(
        Trigger.new,
        Trigger.oldMap
    );
}