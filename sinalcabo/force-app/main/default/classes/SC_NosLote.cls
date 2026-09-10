/**
 * Ciclo de vida do Lote_Integracao__c e das suas ocorrências.
 *
 * Um lote é o registo de uma chamada: abre-se antes do callout, numa transacção
 * própria, e fecha-se depois com os contadores. A Chave_Execucao__c é única na org e
 * é isso que impede duas corridas de lerem a mesma janela: quem chega a segundo
 * apanha DUPLICATE_VALUE e desiste em silêncio.
 *
 * As corridas manuais, os reprocessamentos e a carga histórica levam sufixo na chave,
 * porque repetir a mesma janela de propósito é o objectivo desses três casos.
 */
public with sharing class SC_NosLote {
    public static final String ESTADO_EM_CURSO = 'Em curso';
    public static final String ESTADO_CONCLUIDO = 'Concluído';
    public static final String ESTADO_CONCLUIDO_COM_ERROS = 'Concluído com erros';
    public static final String ESTADO_FALHADO = 'Falhado';

    public static final String TIPO_ALTERACAO = 'Alteração';
    public static final String TIPO_REJEICAO = 'Rejeição';
    public static final String TIPO_CONFLITO = 'Conflito';
    public static final String TIPO_AVISO = 'Aviso';

    private static final Integer TECTO_PAYLOAD = 131072;
    private static final Integer TECTO_ERRO = 32768;

    /** Chave determinística: duas corridas da mesma janela colidem de propósito. */
    public static String chave(String tipoCorrida, Datetime inicio, Datetime fim) {
        return 'NOS|' + tipoCorrida + '|' + instante(inicio) + '|' + instante(fim);
    }

    /**
     * Abre um lote. Devolve null quando outra corrida já abriu o mesmo, que é a
     * resposta certa: o trabalho está a ser feito e esta corrida não tem nada a fazer.
     */
    public static Lote_Integracao__c abrir(String tipoCorrida, Datetime inicio, Datetime fim) {
        return inserir(novo(tipoCorrida, inicio, fim, chave(tipoCorrida, inicio, fim)));
    }

    /** Abre um lote que pode repetir uma janela já lida (manual, reprocessamento, carga). */
    public static Lote_Integracao__c abrirRepetivel(String tipoCorrida, Datetime inicio, Datetime fim) {
        String sufixo = String.valueOf(System.currentTimeMillis()) + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return inserir(novo(tipoCorrida, inicio, fim, chave(tipoCorrida, inicio, fim) + '|' + sufixo));
    }

    private static Lote_Integracao__c novo(String tipoCorrida, Datetime inicio, Datetime fim, String chaveExecucao) {
        return new Lote_Integracao__c(
            Interface__c = SC_NosConfig.INTERFACE_ENTRADA,
            Direccao__c = 'Entrada',
            Tipo_Corrida__c = tipoCorrida,
            Janela_Inicio__c = inicio,
            Janela_Fim__c = fim,
            Estado__c = ESTADO_EM_CURSO,
            Chave_Execucao__c = chaveExecucao.abbreviate(255),
            Registos_Lidos__c = 0,
            Criados__c = 0,
            Actualizados__c = 0,
            Rejeitados__c = 0
        );
    }

    private static Lote_Integracao__c inserir(Lote_Integracao__c lote) {
        Database.SaveResult resultado = Database.insert(lote, false);
        if (resultado.isSuccess()) {
            return lote;
        }
        for (Database.Error erro : resultado.getErrors()) {
            if (erro.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return null;
            }
        }
        throw new SC_NosLoteException(
            'Não foi possível abrir o lote: ' + resultado.getErrors()[0].getMessage()
        );
    }

    /** Fecha o lote com os contadores da corrida. */
    public static void concluir(
        Lote_Integracao__c lote,
        SC_NosResponse resposta,
        Long duracaoMs,
        SC_NosUpsertService.Resultado r,
        Datetime proximaChegada
    ) {
        if (lote == null) {
            return;
        }
        lote.Registos_Lidos__c = r.lidos;
        lote.Criados__c = r.criados;
        lote.Actualizados__c = r.actualizados;
        lote.Rejeitados__c = r.rejeitados;
        lote.Duracao_ms__c = duracaoMs;
        lote.Proxima_Chegada_Esperada__c = proximaChegada;
        lote.Estado__c = r.rejeitados > 0 ? ESTADO_CONCLUIDO_COM_ERROS : ESTADO_CONCLUIDO;
        if (resposta == null) {
            // Sem resposta da API (reprocessamento) o resultado sai dos contadores.
            lote.Resultado__c = r.lidos > 0 ? 'Sucesso' : 'Vazio';
        } else {
            lote.Resultado__c = resposta.resultadoDoLote();
            // A resposta bruta só se guarda quando há algo para investigar.
            if (r.temOcorrencias() && String.isNotBlank(resposta.corpo)) {
                lote.Payload__c = resposta.corpo.abbreviate(TECTO_PAYLOAD);
            }
        }
        update lote;
    }

    /** Fecha o lote como Falhado. Usado pelo Finalizer e por quem apanha um erro. */
    public static void falhar(Lote_Integracao__c lote, SC_NosResponse resposta, String erro) {
        if (lote == null) {
            return;
        }
        lote.Estado__c = ESTADO_FALHADO;
        lote.Resultado__c = resposta == null ? 'Erro' : resposta.resultadoDoLote();
        if (resposta != null) {
            lote.Duracao_ms__c = resposta.duracaoMs;
            if (String.isNotBlank(resposta.corpo)) {
                lote.Payload__c = resposta.corpo.abbreviate(TECTO_PAYLOAD);
            }
        }
        lote.Erro__c = String.isBlank(erro) ? 'Erro sem mensagem.' : erro.abbreviate(TECTO_ERRO);
        update lote;
    }

    /** Fecha por Id, sem ter o registo em memória: é o caso do Finalizer. */
    public static void falharPorId(Id loteId, String erro) {
        if (loteId == null) {
            return;
        }
        List<Lote_Integracao__c> lotes = [
            SELECT Id, Estado__c, Erro__c
            FROM Lote_Integracao__c
            WHERE Id = :loteId
            LIMIT 1
        ];
        if (lotes.isEmpty() || lotes[0].Estado__c != ESTADO_EM_CURSO) {
            return;
        }
        lotes[0].Estado__c = ESTADO_FALHADO;
        lotes[0].Resultado__c = 'Erro';
        lotes[0].Erro__c = String.isBlank(erro) ? 'Erro sem mensagem.' : erro.abbreviate(TECTO_ERRO);
        update lotes[0];
    }

    // ------------------------------------------------------------------
    // Ocorrências
    // ------------------------------------------------------------------

    public static Ocorrencia_Integracao__c ocorrencia(
        Id loteId,
        String tipo,
        String chaveOrigem,
        String objecto,
        String mensagem,
        String conteudo
    ) {
        return new Ocorrencia_Integracao__c(
            Lote__c = loteId,
            Tipo__c = tipo,
            Chave_Origem__c = chaveOrigem == null ? null : chaveOrigem.abbreviate(50),
            Objecto__c = objecto,
            Mensagem__c = mensagem == null ? null : mensagem.abbreviate(255),
            Conteudo__c = conteudo == null ? null : conteudo.abbreviate(TECTO_ERRO),
            Reprocessavel__c = TIPO_REJEICAO.equals(tipo)
        );
    }

    public static void guardar(List<Ocorrencia_Integracao__c> ocorrencias) {
        if (ocorrencias == null || ocorrencias.isEmpty()) {
            return;
        }
        insert ocorrencias;
    }

    private static String instante(Datetime valor) {
        return valor == null ? '' : valor.formatGmt('yyyyMMddHHmm');
    }

    public class SC_NosLoteException extends Exception {}
}