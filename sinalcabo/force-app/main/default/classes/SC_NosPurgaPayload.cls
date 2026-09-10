/**
 * Limpa a resposta bruta guardada nos lotes antigos. Corre uma vez por dia, às 03:00.
 *
 * O `Payload__c` de um lote é a resposta da NOS em bruto, até 131.072 caracteres, e só
 * existe para reprocessar o lote sem voltar a chamar a API. Passado o prazo de retenção
 * já ninguém reprocessa nada e o que fica é armazenamento ocupado com dados do cliente
 * que não têm de continuar aqui.
 *
 * Duas excepções: os lotes Falhado dos últimos 90 dias, que são material de análise, e
 * os lotes de carga histórica enquanto a carga não estiver dada por boa. Essa segunda
 * não está no código: a carga corre uma vez e o prazo de retenção trata dela.
 *
 * O prazo vem de Sistema_Cliente__mdt.NOS_FFM.Retencao_Payload_Dias__c, hoje 30 dias.
 *
 * Batchable e não um `update` de uma vez: um lote com o payload cheio pesa, e um mês de
 * corridas de cinco em cinco minutos dá milhares de registos.
 */
public with sharing class SC_NosPurgaPayload implements Database.Batchable<SObject>, Schedulable {
    public static final String NOME_AGENDAMENTO = 'SC_NOS_Purga_Payload';
    /** Um lote falhado guarda-se mais tempo: é a prova do que a NOS respondeu. */
    private static final Integer DIAS_DE_FALHADOS = 90;
    private static final Integer TAMANHO_DO_LOTE = 50;

    public void execute(SchedulableContext contexto) {
        Database.executeBatch(new SC_NosPurgaPayload(), TAMANHO_DO_LOTE);
    }

    public Database.QueryLocator start(Database.BatchableContext contexto) {
        // Um campo de texto longo não se pode filtrar em SOQL, por isso a consulta traz
        // os lotes pela data e o execute() salta os que já estão sem payload.
        Datetime corte = Datetime.now().addDays(-SC_NosConfig.retencaoPayloadDias());
        Datetime corteFalhados = Datetime.now().addDays(-DIAS_DE_FALHADOS);
        String falhado = SC_NosLote.ESTADO_FALHADO;
        return Database.getQueryLocator([
            SELECT Id, Payload__c
            FROM Lote_Integracao__c
            WHERE CreatedDate < :corte
              AND (Estado__c != :falhado OR CreatedDate < :corteFalhados)
            ORDER BY CreatedDate
        ]);
    }

    public void execute(Database.BatchableContext contexto, List<Lote_Integracao__c> lotes) {
        List<Lote_Integracao__c> aLimpar = new List<Lote_Integracao__c>();
        for (Lote_Integracao__c lote : lotes) {
            if (String.isNotBlank(lote.Payload__c)) {
                aLimpar.add(new Lote_Integracao__c(Id = lote.Id, Payload__c = null));
            }
        }
        if (!aLimpar.isEmpty()) {
            Database.update(aLimpar, false);
        }
    }

    public void finish(Database.BatchableContext contexto) {
        // Nada a fazer: a purga é silenciosa de propósito. Um erro de escrita aparece
        // no job de Apex, e um lote que fique com payload volta a ser apanhado amanhã.
    }
}