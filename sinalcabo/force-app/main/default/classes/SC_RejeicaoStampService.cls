/**
 * SC_RejeicaoStampService
 *
 * Carimba na Opportunity QUEM rejeitou (G2_Rejeitado_Por__c), o MOTIVO
 * (G2_Motivo_Rejeicao__c) e o NIVEL em que a rejeicao aconteceu (G2_Nivel_Rejeicao__c).
 * Quem e motivo saem do passo de rejeicao do Approval Process (ProcessInstanceStep com
 * StepStatus='Rejected': ActorId e Comments); o nivel sai do Approval_Status ANTERIOR.
 *
 * Fonte da verdade = ProcessInstanceStep (ActorId real, a prova de futuro se um dia se
 * ligar delegacao). Disparado por trigger after-update quando Approval_Status passa a
 * "Recusado". A leitura do step e o update sao feitos ASSINCRONAMENTE (Queueable) para
 * garantir que o ProcessInstanceStep da rejeicao ja esta committed e visivel (evita o
 * risco de timing de o ler dentro da mesma transacao do save do AP).
 *
 * SEMPRE A ULTIMA REJEICAO. Nenhuma via de reposicao limpa o G2_Rejeitado_Por__c (nem o
 * flow SC_Reset_Aprovacao_Rejeicao nem a revisao de proposta, que ambos preservam os campos
 * de rejeicao de proposito); se o carimbo so' corresse com o campo vazio, a 2a rejeicao da
 * mesma oportunidade nao deixava rasto e a ficha continuava a mostrar o rejeitador e o
 * motivo da primeira. Por isso os tres campos sao sempre reescritos:
 * o que fica na ficha e' a rejeicao mais recente. O historico por nivel (um campo por L1/L2/L3)
 * foi ponderado e recusado por custo; quem quiser o percurso completo tem o Approval History
 * nativo e os registos de Revisao_Proposta__c.
 *
 * Nao toca no StageName (nao dispara a VR_Stage_Via_Flow_Obrigatorio) nem na data: o
 * G2_Data_Rejeicao__c e' um field update do proprio Approval Process (SC_AP_Rej_Data, NOW())
 * que ja dispara em cada rejeicao.
 */
public with sharing class SC_RejeicaoStampService {

    // Chamado pelo trigger after-update. Recolhe as opps que transitaram para Recusado
    // e despacha o carimbo assincrono.
    public static void carimbarRejeicao(List<Opportunity> novos, Map<Id, Opportunity> antigos) {
        // O NIVEL tem de ser apurado AQUI. Le-se do valor anterior do Approval_Status (quem
        // estava a decidir quando a rejeicao entrou), e esse valor so existe no contexto do
        // trigger: quando o Queueable corre, ja' e' passado. Por isso viaja no proprio job,
        // como o conjunto de Ids sempre viajou.
        Map<Id, Integer> nivelPorOpp = new Map<Id, Integer>();
        for (Opportunity o : novos) {
            Opportunity velho = (antigos != null) ? antigos.get(o.Id) : null;
            Boolean transitouRecusado = o.Approval_Status__c == 'Recusado'
                && (velho == null || velho.Approval_Status__c != 'Recusado');
            if (transitouRecusado) {
                nivelPorOpp.put(o.Id, nivelDoEstadoAnterior(velho == null ? null : velho.Approval_Status__c));
            }
        }
        if (nivelPorOpp.isEmpty()) return;
        // async: garante que o step de rejeicao ja' esta committed. So fora de contexto async.
        if (!System.isFuture() && !System.isBatch() && !System.isQueueable()) {
            System.enqueueJob(new CarimboQueueable(nivelPorOpp));
        } else {
            // ja' em contexto async (ex. cadeia): processa directamente
            processar(nivelPorOpp);
        }
    }

    // O nivel em que a decisao estava quando a rejeicao entrou. Os tres steps do AP tem
    // rejectBehavior = RejectRequest, logo cada ciclo tem uma so rejeicao e o nivel e' unico.
    // Estado anterior fora do circuito (ex. rejeicao forcada a partir de outro estado): null,
    // que e' honesto, em vez de assumir L1.
    @TestVisible
    private static Integer nivelDoEstadoAnterior(String estadoAnterior) {
        if (estadoAnterior == 'Aguarda L1') return 1;
        if (estadoAnterior == 'Aguarda L2') return 2;
        if (estadoAnterior == 'Aguarda L3') return 3;
        return null;
    }

    public class CarimboQueueable implements Queueable {
        private Map<Id, Integer> nivelPorOpp;
        public CarimboQueueable(Map<Id, Integer> nivelPorOpp) { this.nivelPorOpp = nivelPorOpp; }
        public void execute(QueueableContext ctx) { processar(nivelPorOpp); }
    }

    @TestVisible
    private static void processar(Map<Id, Integer> nivelPorOpp) {
        if (nivelPorOpp == null || nivelPorOpp.isEmpty()) return;
        Set<Id> oppIds = nivelPorOpp.keySet();

        // o passo de rejeicao mais recente por opp (ASC + put sobrescreve -> fica o mais recente)
        Map<Id, ProcessInstanceStep> stepPorOpp = new Map<Id, ProcessInstanceStep>();
        for (ProcessInstanceStep st : [
            SELECT ActorId, Comments, ProcessInstance.TargetObjectId, CreatedDate
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :oppIds AND StepStatus = 'Rejected'
            ORDER BY CreatedDate ASC
        ]) {
            stepPorOpp.put(st.ProcessInstance.TargetObjectId, st);
        }
        if (stepPorOpp.isEmpty()) return;

        Map<Id, String> motivoPorOpp = new Map<Id, String>();
        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Id oppId : stepPorOpp.keySet()) {
            ProcessInstanceStep st = stepPorOpp.get(oppId);
            String motivo = (String.isNotBlank(st.Comments) ? st.Comments.left(255) : null);
            motivoPorOpp.put(oppId, motivo);
            toUpdate.add(new Opportunity(
                Id = oppId,
                G2_Rejeitado_Por__c = st.ActorId,
                G2_Motivo_Rejeicao__c = motivo,
                G2_Nivel_Rejeicao__c = nivelPorOpp.get(oppId)
            ));
        }
        if (!toUpdate.isEmpty()) update toUpdate;

        // B.2: regista a revisao no historico unico (unificacao recusa + pedido do cliente).
        SC_RevisaoPropostaService.registarRevisaoRecusa(stepPorOpp.keySet(), motivoPorOpp);
    }
}