/**
 * Resposta da API da NOS já classificada.
 *
 * A API responde sempre 200 com um result_code no corpo quando chega ao backend, e
 * responde com o erro do gateway quando não chega. Estas são as seis classes que o
 * resto do código conhece, e nenhuma delas é uma excepção: o cliente nunca lança.
 *
 *  OK          listagem com result_code 0 ou detalhe com result_code 200
 *  VAZIO       OK mas sem tarefas nenhumas
 *  JANELA      result_code 702, a janela de fechadas passou das 72 horas
 *  AUSENTE     result_code 701, a tarefa não existe na origem
 *  TIMEOUT     corte do gateway aos 60 s (504) ou excepção de callout
 *  SUSPENSO    500 do WSO2 com am:code 303001, endpoint suspenso do lado da NOS
 *  ERRO        tudo o resto, incluindo corpo que não é JSON
 */
public with sharing class SC_NosResponse {
    public enum Classe { OK, VAZIO, JANELA, AUSENTE, TIMEOUT, SUSPENSO, ERRO }

    public Classe situacao { get; private set; }
    public Integer codigoHttp { get; private set; }
    public Integer resultCode { get; private set; }
    public String mensagem { get; private set; }
    public String corpo { get; private set; }
    public Long duracaoMs { get; private set; }
    public String url { get; private set; }
    /** Número de linhas em result_data.data quando a resposta é uma listagem. */
    public Integer registos { get; private set; }

    private SC_NosResponse() {
        this.registos = 0;
    }

    public Boolean ok() {
        return this.situacao == Classe.OK || this.situacao == Classe.VAZIO;
    }

    /** Cortes e suspensões mexem no contador de erros do custom setting. */
    public Boolean corteDeGateway() {
        return this.situacao == Classe.TIMEOUT;
    }

    public Boolean suspensoNaOrigem() {
        return this.situacao == Classe.SUSPENSO;
    }

    /** Texto curto para o campo Erro__c do lote e para as ocorrências. */
    public String resumo() {
        String texto = this.situacao.name() + ' http=' + this.codigoHttp + ' result_code=' + this.resultCode;
        if (String.isNotBlank(this.mensagem)) {
            texto += ' ' + this.mensagem;
        }
        return texto.abbreviate(255);
    }

    /** Valor para Lote_Integracao__c.Resultado__c. */
    public String resultadoDoLote() {
        switch on this.situacao {
            when OK {
                return 'Sucesso';
            }
            when VAZIO {
                return 'Vazio';
            }
            when TIMEOUT {
                return 'Timeout';
            }
            when else {
                return 'Erro';
            }
        }
    }

    // ------------------------------------------------------------------
    // Construção
    // ------------------------------------------------------------------

    /**
     * Classifica uma resposta HTTP. `codigoDeSucesso` é 0 na listagem e 200 no detalhe:
     * a API usa escalas diferentes nos dois métodos.
     */
    public static SC_NosResponse classificar(HttpResponse http, Integer codigoDeSucesso, String url, Long duracaoMs) {
        SC_NosResponse r = new SC_NosResponse();
        r.url = url;
        r.duracaoMs = duracaoMs;
        r.codigoHttp = http == null ? null : http.getStatusCode();
        r.corpo = http == null ? null : http.getBody();

        // Fora do 200, o corpo é do gateway e não do backend: é aí que vive o corte e a suspensão.
        Boolean httpMau = r.codigoHttp == null || r.codigoHttp != 200;
        if (r.codigoHttp == 504 || (httpMau && r.corpo != null && r.corpo.containsIgnoreCase('stream timeout'))) {
            r.situacao = Classe.TIMEOUT;
            r.mensagem = 'O gateway cortou a chamada.';
            return r;
        }
        if (httpMau && r.corpo != null && r.corpo.contains('303001')) {
            r.situacao = Classe.SUSPENSO;
            r.mensagem = 'Endpoint suspenso na NOS (WSO2 303001).';
            return r;
        }

        Map<String, Object> raiz;
        try {
            Object lido = JSON.deserializeUntyped(r.corpo == null ? '' : r.corpo);
            raiz = lido instanceof Map<String, Object> ? (Map<String, Object>) lido : null;
        } catch (Exception e) {
            raiz = null;
        }
        if (raiz == null) {
            r.situacao = Classe.ERRO;
            r.mensagem = 'Resposta que não é JSON: ' + (r.corpo == null ? 'vazia' : r.corpo.abbreviate(120));
            return r;
        }

        r.resultCode = inteiro(raiz.get('result_code'));
        Object mensagem = raiz.get('result_message');
        r.mensagem = mensagem == null ? null : String.valueOf(mensagem);
        r.registos = contarRegistos(raiz);

        if (r.resultCode == 702) {
            r.situacao = Classe.JANELA;
            return r;
        }
        if (r.resultCode == 701) {
            r.situacao = Classe.AUSENTE;
            return r;
        }
        if (r.codigoHttp != 200 || r.resultCode == null || r.resultCode != codigoDeSucesso) {
            r.situacao = Classe.ERRO;
            return r;
        }
        r.situacao = r.registos == 0 ? Classe.VAZIO : Classe.OK;
        return r;
    }

    /** Uma excepção de callout conta como corte do gateway: o efeito operacional é o mesmo. */
    public static SC_NosResponse deExcepcao(Exception e, String url, Long duracaoMs) {
        SC_NosResponse r = new SC_NosResponse();
        r.url = url;
        r.duracaoMs = duracaoMs;
        r.situacao = Classe.TIMEOUT;
        r.mensagem = e == null ? 'Callout sem resposta.' : e.getTypeName() + ': ' + e.getMessage();
        return r;
    }

    private static Integer contarRegistos(Map<String, Object> raiz) {
        Object dados = raiz.get('result_data');
        if (!(dados instanceof Map<String, Object>)) {
            return 0;
        }
        Object linhas = ((Map<String, Object>) dados).get('data');
        if (linhas instanceof List<Object>) {
            return ((List<Object>) linhas).size();
        }
        return linhas instanceof Map<String, Object> ? 1 : 0;
    }

    private static Integer inteiro(Object valor) {
        if (valor == null) {
            return null;
        }
        if (valor instanceof Integer) {
            return (Integer) valor;
        }
        if (valor instanceof Decimal) {
            return ((Decimal) valor).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(valor));
        } catch (Exception e) {
            return null;
        }
    }
}