/**
 * SC_OpportunityNumeracaoTrigger (B.4)
 *
 * Before-insert: atribui o Numero_Proposta__c no formato SIGLA/NNNNN/AA.
 *
 * PORQUE E' UM TRIGGER NOVO e nao aproveita um dos tres existentes: os tres sao `after`
 * (SC_OpportunityRejeicaoTrigger e SC_Opportunity_Slack em after update,
 * SC_OpportunityTeamTrigger em after insert e after update, este ultimo de proposito porque
 * o OpportunityTeamMember precisa do Id ja existir). O numero tem de ser escrito ANTES do
 * save, para nao obrigar a um segundo DML na Opportunity.
 *
 * Consolidar os quatro num handler framework unico e' refactor separado e nao entra aqui.
 */
trigger SC_OpportunityNumeracaoTrigger on Opportunity (before insert) {
    SC_NumeroPropostaService.atribuir(Trigger.new);
}