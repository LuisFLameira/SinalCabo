/**
 * SC_SlackService (SinalCabo)
 *
 * Envia mensagens de texto para canais de Slack via a Web API (chat.postMessage),
 * autenticado por bot token na Named Credential SC_Slack_API (External Credential
 * SC_Slack_Cred). Caminho grátis (Web API), não usa o conector pago Salesforce-Slack.
 *
 * NUNCA lança: devolve um Result (ok/statusCode/error) para o chamador decidir/registar.
 * O callout tem de correr em contexto assíncrono (Queueable), não em trigger/flow após
 * DML (senão "uncommitted work pending"). Ver SC_SlackNotifier.
 *
 * A Web API do Slack devolve HTTP 200 com {"ok": false, "error": "..."} em muitos casos
 * (not_in_channel, channel_not_found, invalid_auth), por isso não basta o status HTTP.
 */
public with sharing class SC_SlackService {
    private static final String ENDPOINT = 'callout:SC_Slack_API/api/chat.postMessage';
    private static final String LOOKUP_ENDPOINT = 'callout:SC_Slack_API/api/users.lookupByEmail';
    private static final Integer TIMEOUT_MS = 10000;

    public class Result {
        public String channel;
        public Boolean ok = false;
        public Integer statusCode;
        public String error;       // código de erro do Slack (ok:false) ou HTTP/excepção
        public String retryAfter;  // segundos a esperar em caso de 429
    }

    public class UserLookup {
        public Boolean ok = false;
        public String userId;      // Slack member ID (U...) quando ok
        public Integer statusCode;
        public String error;       // users_not_found, missing_scope, HTTP/excepção
    }

    /**
     * Resolve o Slack member ID de um utilizador a partir do email (users.lookupByEmail).
     * Usado para enviar DM ao aprovador sem manter um mapa manual. Nunca lança.
     * Requer o scope users:read.email no bot token.
     */
    public static UserLookup lookupUserIdByEmail(String email) {
        UserLookup r = new UserLookup();
        if (String.isBlank(email)) { r.error = 'email_vazio'; return r; }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(LOOKUP_ENDPOINT + '?email=' + EncodingUtil.urlEncode(email, 'UTF-8'));
            req.setMethod('GET');
            req.setTimeout(TIMEOUT_MS);

            HttpResponse res = new Http().send(req);
            r.statusCode = res.getStatusCode();

            if (res.getStatusCode() == 200) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                r.ok = (parsed.get('ok') == true);
                if (r.ok == true) {
                    Object u = parsed.get('user');
                    if (u instanceof Map<String, Object>) {
                        r.userId = String.valueOf(((Map<String, Object>) u).get('id'));
                    }
                } else {
                    r.error = String.valueOf(parsed.get('error'));
                }
            } else if (res.getStatusCode() == 429) {
                r.error = 'rate_limited';
            } else {
                r.error = 'HTTP ' + res.getStatusCode();
            }
        } catch (Exception e) {
            r.error = 'exception: ' + e.getMessage();
        }
        return r;
    }

    /**
     * Posta uma mensagem de texto num canal (por channel ID). Nunca lança.
     */
    public static Result postMessage(String channelId, String text) {
        Result r = new Result();
        r.channel = channelId;
        try {
            Map<String, Object> body = new Map<String, Object>{ 'channel' => channelId, 'text' => text };
            HttpRequest req = new HttpRequest();
            req.setEndpoint(ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json; charset=utf-8');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(JSON.serialize(body));

            HttpResponse res = new Http().send(req);
            r.statusCode = res.getStatusCode();

            if (res.getStatusCode() == 429) {
                r.ok = false;
                r.error = 'rate_limited';
                r.retryAfter = res.getHeader('Retry-After');
            } else if (res.getStatusCode() == 200) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                r.ok = (parsed.get('ok') == true);
                if (r.ok != true) {
                    r.error = String.valueOf(parsed.get('error'));
                }
            } else {
                r.ok = false;
                r.error = 'HTTP ' + res.getStatusCode();
            }
        } catch (Exception e) {
            r.ok = false;
            r.error = 'exception: ' + e.getMessage();
        }
        return r;
    }
}