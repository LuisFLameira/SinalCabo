/**
 * SC_OpportunityRejeicaoTrigger
 * After-update: quando Approval_Status passa a "Recusado", carimba quem rejeitou
 * e o motivo a partir do ProcessInstanceStep (via SC_RejeicaoStampService, async).
 */
trigger SC_OpportunityRejeicaoTrigger on Opportunity (after update) {
    SC_RejeicaoStampService.carimbarRejeicao(Trigger.new, Trigger.oldMap);
}