/**
 * SC_OpportunityAprovacaoTrigger
 * After-update: quando Approval_Status passa a "Aguarda L2", "Aguarda L3" ou "Aprovado",
 * carimba quem aprovou cada nivel a partir do ProcessInstanceStep (via
 * SC_AprovacaoStampService, async). Gemeo do SC_OpportunityRejeicaoTrigger.
 */
trigger SC_OpportunityAprovacaoTrigger on Opportunity (after update) {
    SC_AprovacaoStampService.carimbarAprovacao(Trigger.new, Trigger.oldMap);
}