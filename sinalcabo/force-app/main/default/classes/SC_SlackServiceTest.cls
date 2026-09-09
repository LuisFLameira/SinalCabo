/**
 * Teste do SC_SlackService. O HttpCalloutMock intercepta o callout à Named Credential,
 * por isso não é preciso a NC/token reais. Cobre: sucesso (ok:true), erro de negócio do
 * Slack (200 + ok:false, ex. not_in_channel), e rate limit (429 + Retry-After). Prova que
 * o serviço nunca lança e classifica bem cada caso.
 */
@IsTest
private class SC_SlackServiceTest {

    private class Mock implements HttpCalloutMock {
        Integer code; String body; String retryAfter;
        Mock(Integer code, String body, String retryAfter) { this.code = code; this.body = body; this.retryAfter = retryAfter; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            if (body != null) res.setBody(body);
            if (retryAfter != null) res.setHeader('Retry-After', retryAfter);
            return res;
        }
    }

    @IsTest
    static void sucesso_ok_true() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"ok":true,"channel":"C123","ts":"1"}', null));
        Test.startTest();
        SC_SlackService.Result r = SC_SlackService.postMessage('C123', 'Olá');
        Test.stopTest();
        Assert.isTrue(r.ok, 'devia ser ok');
        Assert.areEqual(200, r.statusCode);
        Assert.isNull(r.error);
    }

    @IsTest
    static void erro_negocio_ok_false() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"ok":false,"error":"not_in_channel"}', null));
        Test.startTest();
        SC_SlackService.Result r = SC_SlackService.postMessage('C999', 'Olá');
        Test.stopTest();
        Assert.isFalse(r.ok, 'ok:false do Slack deve dar ok=false');
        Assert.areEqual('not_in_channel', r.error, 'deve capturar o erro do Slack');
    }

    @IsTest
    static void rate_limited_429() {
        Test.setMock(HttpCalloutMock.class, new Mock(429, '', '30'));
        Test.startTest();
        SC_SlackService.Result r = SC_SlackService.postMessage('C123', 'Olá');
        Test.stopTest();
        Assert.isFalse(r.ok);
        Assert.areEqual('rate_limited', r.error);
        Assert.areEqual('30', r.retryAfter, 'deve ler o Retry-After');
    }
}