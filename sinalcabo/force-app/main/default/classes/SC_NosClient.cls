/**
 * Cliente da API Field Force Management da NOS. Só GET, só leitura, nunca lança.
 *
 * Dois métodos: a listagem de tarefas do parceiro por janela temporal e o detalhe de
 * uma tarefa por identificador. Ambos devolvem SC_NosResponse já classificado, para
 * que quem chama decida sem apanhar excepções.
 *
 * Duas regras que o spike da F0 fixou e que não se mexem sem repetir o spike:
 * os parâmetros startTime e endTime vão em hora local de Portugal (a API ignora o
 * fuso do servidor), e o espaço entre a data e a hora vai codificado como %20.
 */
public with sharing class SC_NosClient {
    private static final String CAMINHO_LISTAGEM = '/workitem/listByPartner';
    private static final String CAMINHO_DETALHE = '/workitem/getByWorkitemId';
    private static final String FORMATO_JANELA = 'yyyy-MM-dd HH:mm:ss';

    /** Listagem de tarefas atribuídas na janela. `status` a null traz só as não fechadas. */
    public static SC_NosResponse listar(Datetime inicio, Datetime fim, String status) {
        String url = 'callout:' + SC_NosConfig.namedCredential() + CAMINHO_LISTAGEM +
            '?startTime=' + parametroJanela(inicio) +
            '&endTime=' + parametroJanela(fim);
        if (String.isNotBlank(status)) {
            url += '&status=' + EncodingUtil.urlEncode(status, 'UTF-8');
        }
        return chamar(url, 0);
    }

    /** Detalhe de uma tarefa. Traz NetworkElements, Notes e Interactions. */
    public static SC_NosResponse detalhe(String identificador) {
        String url = 'callout:' + SC_NosConfig.namedCredential() + CAMINHO_DETALHE +
            '?ID=' + EncodingUtil.urlEncode(identificador == null ? '' : identificador, 'UTF-8');
        return chamar(url, 200);
    }

    /**
     * Data e hora no fuso que a API espera, com o espaço já codificado.
     * Provado na F0: a mesma ordem aparece na janela em hora local e não aparece na
     * mesma janela em UTC.
     */
    @TestVisible
    private static String parametroJanela(Datetime instante) {
        String texto = instante.format(FORMATO_JANELA, SC_NosConfig.fuso());
        return texto.replace(' ', '%20');
    }

    private static SC_NosResponse chamar(String url, Integer codigoDeSucesso) {
        HttpRequest pedido = new HttpRequest();
        pedido.setEndpoint(url);
        pedido.setMethod('GET');
        pedido.setTimeout(SC_NosConfig.timeoutMs());
        pedido.setHeader('Accept', 'application/json');

        Long inicio = System.currentTimeMillis();
        try {
            HttpResponse resposta = new Http().send(pedido);
            return SC_NosResponse.classificar(resposta, codigoDeSucesso, url, System.currentTimeMillis() - inicio);
        } catch (Exception e) {
            // Timeout de socket, DNS, credencial por configurar: tudo entra como corte.
            return SC_NosResponse.deExcepcao(e, url, System.currentTimeMillis() - inicio);
        }
    }
}