/**
 * Volta a tentar as linhas do ficheiro do PNI que ficaram de fora.
 *
 * Não relê o ficheiro: lê as ocorrências. Cada rejeição guardou a linha original, e o
 * lote onde ela nasceu guardou o cabeçalho, que é o que dá sentido aos campos. Com as
 * duas coisas a linha volta a passar exactamente pelo mesmo caminho da importação.
 *
 * É por isso que reprocessar não obriga a pessoa a ir buscar o ficheiro outra vez, e é
 * também por isso que reprocessar com os dados de referência já corrigidos funciona:
 * a linha é a mesma, o que mudou foi a org à volta dela.
 *
 * Abre sempre um lote novo, do tipo Reprocessamento, a apontar ao lote de origem.
 */
public with sharing class SC_PniReprocessador {

    /** O que o ecrã ou o fluxo manda. */
    public class Pedido {
        @InvocableVariable(label='Ocorrências a reprocessar' required=true)
        public List<Id> ocorrencias;
    }

    public class Resposta {
        @InvocableVariable(label='Lote do reprocessamento')
        public Id loteId;
        @InvocableVariable(label='Linhas que entraram')
        public Integer entraram;
        @InvocableVariable(label='Linhas que continuam de fora')
        public Integer continuamDeFora;
    }

    @InvocableMethod(label='Reprocessar linhas do ficheiro do PNI'
        description='Volta a tentar as linhas que ficaram de fora, com os dados de hoje.')
    public static List<Resposta> reprocessar(List<Pedido> pedidos) {
        List<Resposta> respostas = new List<Resposta>();
        for (Pedido p : pedidos) {
            respostas.add(correr(p.ocorrencias));
        }
        return respostas;
    }

    @AuraEnabled
    public static Resposta reprocessarOcorrencias(List<Id> ocorrencias) {
        if (!SC_PniConfig.podeImportar()) {
            AuraHandledException e = new AuraHandledException(
                'Não tem permissão para reprocessar linhas do ficheiro do PNI.');
            e.setMessage('Não tem permissão para reprocessar linhas do ficheiro do PNI.');
            throw e;
        }
        return correr(ocorrencias);
    }

    // ------------------------------------------------------------------

    private static Resposta correr(List<Id> ocorrenciaIds) {
        Resposta r = new Resposta();
        r.entraram = 0;
        r.continuamDeFora = 0;
        if (ocorrenciaIds == null || ocorrenciaIds.isEmpty()) {
            return r;
        }

        List<Ocorrencia_Integracao__c> ocorrencias = [
            SELECT Id, Conteudo__c, Chave_Origem__c, Lote__c, Lote__r.Payload__c,
                   Reprocessavel__c
            FROM Ocorrencia_Integracao__c
            WHERE Id IN :ocorrenciaIds AND Reprocessavel__c = true
        ];
        if (ocorrencias.isEmpty()) {
            return r;
        }

        Lote_Integracao__c lote = new Lote_Integracao__c(
            Interface__c = SC_PniConfig.INTERFACE_ENTRADA,
            Direccao__c = 'Entrada',
            Tipo_Corrida__c = SC_PniConfig.CORRIDA_REPROCESSAMENTO,
            Janela_Inicio__c = Datetime.now(),
            Estado__c = SC_NosLote.ESTADO_EM_CURSO,
            Chave_Execucao__c = ('PNI|repetir|' + ocorrencias[0].Id + '|'
                + String.valueOf(System.currentTimeMillis())).abbreviate(255),
            Reprocessado_De__c = ocorrencias[0].Lote__c,
            Registos_Lidos__c = 0, Criados__c = 0, Actualizados__c = 0, Rejeitados__c = 0
        );
        insert lote;
        r.loteId = lote.Id;

        // As linhas de um mesmo lote partilham o cabeçalho. Agrupa-se por lote para
        // cada grupo ser lido com as colunas que lhe pertencem.
        Map<Id, List<Ocorrencia_Integracao__c>> porLote =
            new Map<Id, List<Ocorrencia_Integracao__c>>();
        for (Ocorrencia_Integracao__c o : ocorrencias) {
            if (!porLote.containsKey(o.Lote__c)) {
                porLote.put(o.Lote__c, new List<Ocorrencia_Integracao__c>());
            }
            porLote.get(o.Lote__c).add(o);
        }

        List<SC_PniLinha> linhas = new List<SC_PniLinha>();
        List<Ocorrencia_Integracao__c> semCabecalho =
            new List<Ocorrencia_Integracao__c>();
        for (Id loteOrigem : porLote.keySet()) {
            List<Ocorrencia_Integracao__c> grupo = porLote.get(loteOrigem);
            String cabecalho = grupo[0].Lote__r == null ? null : grupo[0].Lote__r.Payload__c;
            if (String.isBlank(cabecalho)) {
                semCabecalho.addAll(grupo);
                continue;
            }
            List<String> corpo = new List<String>{ cabecalho };
            for (Ocorrencia_Integracao__c o : grupo) {
                if (String.isNotBlank(o.Conteudo__c)) {
                    corpo.add(o.Conteudo__c);
                }
            }
            SC_PniCsv.Resultado leitura = SC_PniCsv.ler(
                String.join(corpo, '\n') + '\n', null, 1, true);
            linhas.addAll(leitura.linhas);
            r.continuamDeFora += leitura.rejeicoes.size();
        }

        SC_PniUpsertService.Resultado escrita =
            new SC_PniUpsertService(lote.Id, false).tratar(linhas);
        r.entraram = escrita.criados + escrita.actualizados;
        r.continuamDeFora += escrita.rejeitados + escrita.forasDeJanela
            + semCabecalho.size();

        List<Ocorrencia_Integracao__c> novas = new List<Ocorrencia_Integracao__c>();
        for (Ocorrencia_Integracao__c o : semCabecalho) {
            novas.add(SC_NosLote.ocorrencia(lote.Id, SC_NosLote.TIPO_AVISO,
                o.Chave_Origem__c, 'WorkOrder',
                'O lote de origem não guardou o cabeçalho do ficheiro, por isso esta '
                + 'linha não pode ser relida. Importe o ficheiro outra vez.',
                o.Conteudo__c));
        }
        for (SC_PniCsv.Rejeicao rej : escrita.rejeicoes) {
            novas.add(SC_NosLote.ocorrencia(lote.Id, SC_NosLote.TIPO_REJEICAO,
                rej.chave, 'WorkOrder', rej.motivo, rej.bruto));
        }
        if (!novas.isEmpty()) {
            SC_NosLote.guardar(novas);
        }

        lote.Registos_Lidos__c = linhas.size() + semCabecalho.size();
        lote.Criados__c = escrita.criados;
        lote.Actualizados__c = escrita.actualizados;
        lote.Rejeitados__c = r.continuamDeFora;
        lote.Estado__c = r.continuamDeFora > 0
            ? SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS : SC_NosLote.ESTADO_CONCLUIDO;
        lote.Resultado__c = 'Sucesso';
        lote.Janela_Fim__c = Datetime.now();
        lote.Duracao_ms__c = lote.Janela_Fim__c.getTime()
                             - lote.Janela_Inicio__c.getTime();
        update lote;

        // As que entraram deixam de estar à espera de alguém.
        List<Ocorrencia_Integracao__c> resolvidas =
            new List<Ocorrencia_Integracao__c>();
        Set<String> entraram = new Set<String>(escrita.criadas);
        for (Ocorrencia_Integracao__c o : ocorrencias) {
            if (o.Chave_Origem__c != null && entraram.contains(o.Chave_Origem__c)) {
                resolvidas.add(new Ocorrencia_Integracao__c(
                    Id = o.Id, Reprocessavel__c = false));
            }
        }
        if (!resolvidas.isEmpty()) {
            update resolvidas;
        }
        return r;
    }
}