/**
 * Volta a passar pelo pipeline a resposta que ficou guardada num lote, sem chamar a NOS.
 *
 * Serve para quando o erro foi nosso e não da origem: um Work Type que faltava no
 * catálogo, uma célula que ainda não estava carregada, uma validação que rejeitou o
 * que agora aceita. Corrige-se o que faltava e reprocessa-se o lote.
 *
 * O lote novo aponta ao antigo por Reprocessado_De__c, e o antigo fica como está: o
 * histórico do que aconteceu à primeira não se apaga.
 */
public with sharing class SC_NosReprocessador {
    /** Reprocessa o lote e devolve o lote novo, ou null quando não há nada guardado. */
    public static Lote_Integracao__c reprocessar(Id loteOriginalId) {
        List<Lote_Integracao__c> originais = [
            SELECT Id, Tipo_Corrida__c, Janela_Inicio__c, Janela_Fim__c, Payload__c
            FROM Lote_Integracao__c
            WHERE Id = :loteOriginalId
            LIMIT 1
        ];
        if (originais.isEmpty() || String.isBlank(originais[0].Payload__c)) {
            return null;
        }
        Lote_Integracao__c original = originais[0];

        Lote_Integracao__c lote = SC_NosLote.abrirRepetivel(
            SC_NosConfig.CORRIDA_REPROCESSAMENTO, original.Janela_Inicio__c, original.Janela_Fim__c
        );
        lote.Reprocessado_De__c = original.Id;

        // A data de leitura é a do envelope guardado e não a de agora: sem isto uma
        // resposta de há trinta dias escrevia por cima do que o polling já actualizou.
        Datetime lida = SC_NosParser.instanteDoEnvelope(original.Payload__c);
        if (lida == null) {
            lida = original.Janela_Fim__c == null ? Datetime.now() : original.Janela_Fim__c;
        }

        SC_NosUpsertService.Resultado r = SC_NosConfig.CORRIDA_DETALHES.equals(original.Tipo_Corrida__c)
            ? SC_NosUpsertService.processarDetalhe(original.Payload__c, lote.Id, lida)
            : SC_NosUpsertService.processarListagem(original.Payload__c, lote.Id, lida);

        SC_NosLote.guardar(r.ocorrencias);
        SC_NosLote.concluir(lote, null, 0, r, null);
        return lote;
    }
}