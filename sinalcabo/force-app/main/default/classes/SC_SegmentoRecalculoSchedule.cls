/**
 * Agendamento mensal do recálculo do segmento.
 *
 * PORQUE NO DIA 1: a janela são os 12 meses COMPLETOS anteriores, a excluir o mês corrente.
 * Ela avança exactamente na viragem do mês, portanto o dia 1 é o primeiro dia em que há algo
 * novo para recalcular. Correr a 15 deixaria as contas duas semanas com o segmento do mês
 * passado, e o report mensal do PVD sai no início do mês.
 *
 * Agendar (uma vez, em Anonymous Apex, em cada org):
 *   System.schedule('SC Recalculo Segmento Mensal', '0 30 3 1 * ?',
 *                   new SC_SegmentoRecalculoSchedule());
 *
 * 03:30 do dia 1 de cada mês. Fora de horas para o recálculo não competir com os utilizadores,
 * e não à meia-noite para não coincidir com as janelas de manutenção da plataforma.
 *
 * REFERÊNCIAS: ADR-014, em projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoRecalculoSchedule implements Schedulable {
    public void execute(SchedulableContext ctx) {
        SC_SegmentoRecalculo.mensal();
    }
}