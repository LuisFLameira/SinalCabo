/**
 * Dispara as notificações Slack quando uma oportunidade muda de estado relevante
 * (entra em Aprovação Interna, fecha Ganha/Perdida, ou é Cancelada). Só encaminha;
 * toda a lógica e o callout assíncrono estão em SC_SlackNotifier.
 */
trigger SC_Opportunity_Slack on Opportunity (after update) {
    SC_SlackNotifier.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}