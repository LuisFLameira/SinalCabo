/**
 * SC_AprovacaoStampService
 *
 * Carimba na Opportunity QUEM aprovou cada nivel do Gate G2 (G2_L1/L2/L3_Aprovador__c), a
 * partir do passo de aprovacao do Approval Process (ProcessInstanceStep com StepStatus =
 * 'Approved': ActorId). Gemeo do SC_RejeicaoStampService, que faz o mesmo do lado da recusa,
 * e de proposito com a mesma forma: trigger after-update -> Queueable -> ProcessInstanceStep.
 *
 * ActorId E NAO OriginalActorId
 *   Numa decisao delegada (allowDelegate=true nos tres passos) os dois divergem:
 *   OriginalActorId e' o aprovador designado, ActorId e' quem carregou em Aprovar. A pergunta
 *   a que o campo responde e' "quem aprovou isto", logo e' o ActorId. Quem estava designado
 *   continua a ler-se nos Aprovador_Alvo_Nx__c, que e' o campo para isso.
 *
 * O k-ESIMO PASSO APROVADO CARIMBA O NIVEL k
 *   Os niveis do motor sao cumulativos (ADR-011: nivel 2 = N1+N2, nivel 3 = N1+N2+N3), nunca
 *   ha um L3 sem L2, portanto a ordem cronologica dos passos aprovados e' a ordem dos niveis.
 *   Um nivel ainda por decidir fica em BRANCO: e' assim que a ficha diz a verdade sobre uma
 *   cadeia a meio, em vez de nomear quem ainda tem o pedido na mao.
 *
 * PORQUE E' ASSINCRONO (e porque nao e' um flow)
 *   Nas transicoes INTERMEDIAS (L1 aprova e o pedido sobe ao L2) o ProcessInstanceStep da
 *   decisao ainda nao esta' visivel para quem corre dentro da transaccao do Approval Process,
 *   e o carimbo sairia vazio. E' a mesma razao por que o SC_RejeicaoStampService e' Queueable.
 *   O caminho declarativo equivalente seria o percurso assincrono do flow (AsyncAfterCommit),
 *   que a plataforma aceita mas NAO executa em teste Apex: nao havia como provar o
 *   comportamento. Este padrao e' testavel.
 *
 * SO' CARIMBA CICLO VIVO
 *   Entre a decisao e a corrida do Queueable o ciclo pode morrer por tres vias, e as tres
 *   limpam os carimbos: rejeicao (Recusado), recall (Recolhido) e revisao de proposta, que poe
 *   o Approval_Status EM BRANCO (ADR-010). Por isso a leitura do estado e' feita outra vez
 *   dentro do job, por lista branca: sem isso, um carimbo de um ciclo morto renasceria.
 *
 * Nao toca nas datas: os G2_Lx_Data_Aprovacao__c sao field updates do proprio Approval Process
 * (SC_AP_Carimbo_Lx_Data, NOW()) que ja' disparam na approvalAction de cada passo.
 */
public with sharing class SC_AprovacaoStampService {

    // Estados em que o ciclo esta' vivo depois de uma aprovacao. Fora destes, nao se carimba.
    private static final Set<String> ESTADOS_VIVOS = new Set<String>{
        'Aguarda L2', 'Aguarda L3', 'Aprovado'
    };

    // Chamado pelo trigger after-update. Recolhe as opps que acabaram de subir de nivel ou de
    // fechar aprovadas, que sao os unicos instantes em que ha uma decisao nova para carimbar.
    public static void carimbarAprovacao(List<Opportunity> novos, Map<Id, Opportunity> antigos) {
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : novos) {
            Opportunity velho = (antigos != null) ? antigos.get(o.Id) : null;
            String estadoAnterior = (velho == null) ? null : velho.Approval_Status__c;
            if (o.Approval_Status__c != estadoAnterior && ESTADOS_VIVOS.contains(o.Approval_Status__c)) {
                oppIds.add(o.Id);
            }
        }
        if (oppIds.isEmpty()) return;
        // async: garante que o step da decisao ja' esta' visivel. So' fora de contexto async.
        if (!System.isFuture() && !System.isBatch() && !System.isQueueable()) {
            System.enqueueJob(new CarimboQueueable(oppIds));
        } else {
            processar(oppIds);
        }
    }

    public class CarimboQueueable implements Queueable {
        private Set<Id> oppIds;
        public CarimboQueueable(Set<Id> oppIds) { this.oppIds = oppIds; }
        public void execute(QueueableContext ctx) { processar(oppIds); }
    }

    @TestVisible
    private static void processar(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) return;

        // So' as opps cujo ciclo continua vivo. As outras foram recusadas, recolhidas ou
        // revistas entre a decisao e agora, e ja' tem os carimbos limpos de proposito.
        Set<Id> vivas = new Set<Id>();
        for (Opportunity o : [SELECT Id, Approval_Status__c FROM Opportunity WHERE Id IN :oppIds]) {
            if (ESTADOS_VIVOS.contains(o.Approval_Status__c)) vivas.add(o.Id);
        }
        if (vivas.isEmpty()) return;

        // Os passos aprovados do ciclo MAIS RECENTE de cada opp, por ordem de decisao.
        // A ordenacao por ProcessInstance.CreatedDate DESC poe o ciclo mais recente primeiro;
        // fixa-se esse ProcessInstanceId por opp e ignoram-se os passos dos ciclos anteriores.
        Map<Id, Id> cicloPorOpp = new Map<Id, Id>();
        Map<Id, List<Id>> actoresPorOpp = new Map<Id, List<Id>>();
        for (ProcessInstanceStep st : [
            SELECT ActorId, ProcessInstanceId, ProcessInstance.TargetObjectId
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :vivas AND StepStatus = 'Approved'
            ORDER BY ProcessInstance.CreatedDate DESC, CreatedDate ASC
        ]) {
            Id oppId = st.ProcessInstance.TargetObjectId;
            if (!cicloPorOpp.containsKey(oppId)) {
                cicloPorOpp.put(oppId, st.ProcessInstanceId);
                actoresPorOpp.put(oppId, new List<Id>());
            }
            if (cicloPorOpp.get(oppId) == st.ProcessInstanceId) {
                actoresPorOpp.get(oppId).add(st.ActorId);
            }
        }
        if (actoresPorOpp.isEmpty()) return;

        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Id oppId : actoresPorOpp.keySet()) {
            List<Id> actores = actoresPorOpp.get(oppId);
            toUpdate.add(new Opportunity(
                Id = oppId,
                G2_L1_Aprovador__c = nivel(actores, 1),
                G2_L2_Aprovador__c = nivel(actores, 2),
                G2_L3_Aprovador__c = nivel(actores, 3)
            ));
        }
        update toUpdate;
    }

    // O actor do nivel n, ou null se esse nivel ainda nao decidiu (ou nao existe na cadeia).
    private static Id nivel(List<Id> actores, Integer n) {
        return (actores.size() >= n) ? actores[n - 1] : null;
    }
}