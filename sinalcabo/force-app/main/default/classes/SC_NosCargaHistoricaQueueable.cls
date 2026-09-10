/**
 * Passa os lotes de carga histórica pelo pipeline, poucos por transacção.
 *
 * Os lotes de tipo "Carga histórica" são criados de fora, com a resposta da NOS já
 * guardada em `Payload__c` e sem nunca se chamar a API. Esta classe limita-se a
 * mandá-los ao `SC_NosReprocessador`, pela ordem em que lhe são dados, que é a ordem
 * cronológica das janelas: a leitura mais recente é a última a escrever, e a protecção
 * de regressão do `SC_NosUpsertService` trata do resto.
 *
 * Poucos por transacção porque cada corpo traz até 85 ordens e a criação de uma Work
 * Order arrasta os automatismos do pacote FSL. Uma transacção por punhado de lotes
 * mantém o consumo longe dos limites e deixa o rasto visível lote a lote.
 *
 * Não chama a NOS e não olha para o travão de emergência: correr a carga com o travão
 * ligado é o que se quer, para o polling não interferir a meio.
 */
public with sharing class SC_NosCargaHistoricaQueueable implements Queueable {
    private static final Integer LOTES_POR_TRANSACCAO = 3;

    /** Ids dos lotes de carga por processar, já por ordem cronológica. */
    public List<Id> porFazer;
    /** Quantos lotes se tratam por transacção. */
    public Integer porTransaccao;

    public SC_NosCargaHistoricaQueueable(List<Id> porFazer) {
        this(porFazer, LOTES_POR_TRANSACCAO);
    }

    public SC_NosCargaHistoricaQueueable(List<Id> porFazer, Integer porTransaccao) {
        this.porFazer = porFazer == null ? new List<Id>() : porFazer;
        this.porTransaccao = porTransaccao == null || porTransaccao < 1 ? LOTES_POR_TRANSACCAO : porTransaccao;
    }

    public void execute(QueueableContext contexto) {
        if (this.porTransaccao == null || this.porTransaccao < 1) {
            this.porTransaccao = LOTES_POR_TRANSACCAO;
        }
        List<Id> restantes = this.porFazer == null ? new List<Id>() : this.porFazer.clone();
        Integer quantos = Math.min(this.porTransaccao, restantes.size());
        for (Integer i = 0; i < quantos; i++) {
            SC_NosReprocessador.reprocessar(restantes.remove(0));
        }
        if (restantes.isEmpty() || Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(new SC_NosCargaHistoricaQueueable(restantes, this.porTransaccao));
    }

    /**
     * Os lotes de carga histórica que ainda não foram reprocessados, por ordem de
     * janela. Correr outra vez depois de uma interrupção retoma onde ficou.
     */
    public static List<Id> porProcessar() {
        Set<Id> feitos = new Set<Id>();
        for (Lote_Integracao__c lote : [
            SELECT Reprocessado_De__c
            FROM Lote_Integracao__c
            WHERE Reprocessado_De__c != NULL
        ]) {
            feitos.add(lote.Reprocessado_De__c);
        }
        List<Id> porFazer = new List<Id>();
        for (Lote_Integracao__c lote : [
            SELECT Id
            FROM Lote_Integracao__c
            WHERE Tipo_Corrida__c = :SC_NosConfig.CORRIDA_CARGA
            ORDER BY Janela_Inicio__c ASC, Chave_Execucao__c ASC
        ]) {
            if (!feitos.contains(lote.Id)) {
                porFazer.add(lote.Id);
            }
        }
        return porFazer;
    }

    /** Arranca a carga do que estiver por fazer. Devolve quantos lotes ficaram na fila. */
    public static Integer arrancar() {
        List<Id> porFazer = porProcessar();
        if (!porFazer.isEmpty()) {
            System.enqueueJob(new SC_NosCargaHistoricaQueueable(porFazer));
        }
        return porFazer.size();
    }
}