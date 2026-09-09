/**
 * SC_SlackNotifier (SinalCabo)
 *
 * Encaminha notificações de Opportunity para o Slack. Chamado pelo trigger
 * SC_Opportunity_Slack (after update). O callout corre em Queueable
 * (Database.AllowsCallouts): não pode ocorrer na transação de DML do trigger.
 * Bulkificado: um Queueable processa a lista de mensagens. Regista cada envio em
 * SC_Slack_Log__c. Nunca faz falhar a transação de negócio.
 *
 * LOTES GRANDES (C-04): o job só envia o que couber no orçamento de callouts da
 * transação e encadeia um Queueable novo com o resto, gravando sempre os logs do troço
 * que processou. Ver a secção "guarda do limite de chamadas externas" mais abaixo.
 *
 * APROVAÇÃO POR NÍVEL (Approval_Status__c)
 *   O ciclo de aprovação é sequencial (Aguarda L1 -> Aguarda L2 -> Aprovado/Recusado).
 *   A cada transição:
 *     - Aguarda L1: DM ao Aprovador_Alvo_N1 ("tens uma proposta para aprovar")
 *                   + auditoria ao canal de gestão (N1 [Nome] notificado).
 *     - Aguarda L2: DM ao Aprovador_Alvo_N2 + auditoria ao canal de gestão.
 *     - Aprovado / Recusado: fecho do ciclo, mensagem ao canal de gestão.
 *   A DM resolve o Slack do aprovador pelo email (SC_SlackService.lookupUserIdByEmail),
 *   sem manter mapa manual (requer scopes users:read.email + im:write no bot).
 *
 * FECHO COMERCIAL (StageName / IsWon)
 *   Ganha / Perdida / Cancelada: mensagem ao canal da direção da opp.
 *
 * Canais no CMT SC_Slack_Canal__mdt (Direccao -> Channel Id; registo "Gestao" = canal
 * de gestão/direção, crm-direcao).
 */
public with sharing class SC_SlackNotifier implements Queueable, Database.AllowsCallouts {

    // Uma mensagem a enviar: ou para um canal (channelId) ou por DM (email a resolver).
    public class Msg {
        public String channelId;   // canal (post directo); null se for DM
        public String email;       // email do destinatário (DM); null se for canal
        public String text;
        public String evento;
        public Msg(String channelId, String email, String text, String evento) {
            this.channelId = channelId; this.email = email; this.text = text; this.evento = evento;
        }
    }

    private List<Msg> msgs;
    public SC_SlackNotifier(List<Msg> msgs) { this.msgs = msgs; }

    // ── C-04: guarda do limite de chamadas externas ────────────────────────────
    // A plataforma permite 100 callouts por transacção. Cada mensagem custa 1
    // (chat.postMessage) e uma DM cujo email ainda não esteja resolvido custa 2
    // (users.lookupByEmail + chat.postMessage). Um lote grande, como o cancelamento em
    // bloco das duplicadas no arranque, ultrapassa o limite; e a LimitException NÃO é
    // capturável, portanto rebentava a meio do ciclo, antes do insert dos logs, e perdia
    // as mensagens que faltavam E o registo de todas as anteriores.
    // O job passa a processar o que cabe no orçamento e a encadear o resto.
    private static final Integer RESERVA_CALLOUTS = 2;

    // Permite aos testes forçar o encadeamento sem gastar 100 callouts a sério.
    @TestVisible private static Integer orcamentoOverride = null;

    // Só em contexto de teste: a plataforma não deixa encadear um Queueable a partir de
    // outro, por isso o resto fica aqui para o teste o correr à mão. Em produção é null.
    @TestVisible private static List<Msg> restoPendente = null;

    private static Integer orcamentoCallouts() {
        return (orcamentoOverride != null) ? orcamentoOverride
                                           : Limits.getLimitCallouts() - RESERVA_CALLOUTS;
    }

    public void execute(QueueableContext ctx) {
        List<SC_Slack_Log__c> logs = new List<SC_Slack_Log__c>();
        // cache de resoluções email -> Slack userId, para não repetir o lookup no mesmo lote
        Map<String, SC_SlackService.UserLookup> resolvidos = new Map<String, SC_SlackService.UserLookup>();
        Integer orcamento = orcamentoCallouts();
        Integer i = 0;

        for (; i < msgs.size(); i++) {
            Msg m = msgs[i];
            // Custo MÁXIMO desta mensagem: uma DM por resolver gasta lookup + post.
            // Null-safe de propósito: esta linha corre FORA do try, portanto uma mensagem
            // inutilizável aqui rebentaria o job inteiro em vez de ser apanhada.
            Integer custo = (m != null && m.email != null && !resolvidos.containsKey(m.email)) ? 2 : 1;
            if (Limits.getCallouts() + custo > orcamento) break;
            try {
                enviar(m, resolvidos, logs);
            } catch (Exception e) {
                // uma mensagem malformada não pode matar as que vêm a seguir, e o tratamento
                // da falha tem de aguentar a própria mensagem ser inutilizável
                logs.add(new SC_Slack_Log__c(
                    Canal__c = trunc(destinoDe(m), 80),
                    Mensagem__c = (m == null) ? null : m.text,
                    Evento__c = (m == null) ? 'msg-invalida' : trunc(m.evento, 40),
                    Sucesso__c = false,
                    Erro__c = trunc('excepcao: ' + e.getMessage(), 255)
                ));
            }
        }

        // Os logs do troço processado gravam-se SEMPRE, e só aqui: um DML antes de um
        // callout na mesma transacção daria "uncommitted work pending".
        gravarLogs(logs);

        if (i < msgs.size()) {
            List<Msg> resto = new List<Msg>();
            for (Integer j = i; j < msgs.size(); j++) resto.add(msgs[j]);
            encadear(resto);
        }
    }

    // Envia uma mensagem e acrescenta a respectiva linha de log. Comportamento igual ao
    // que existia antes do C-04, incluindo a cache de lookups falhados (um email que não
    // resolve fica em cache e as mensagens seguintes para o mesmo email não repetem o callout).
    private static void enviar(Msg m, Map<String, SC_SlackService.UserLookup> resolvidos,
                               List<SC_Slack_Log__c> logs) {
        if (m.email != null) {
            SC_SlackService.UserLookup lu = resolvidos.get(m.email);
            if (lu == null) { lu = SC_SlackService.lookupUserIdByEmail(m.email); resolvidos.put(m.email, lu); }
            if (lu.ok != true || String.isBlank(lu.userId)) {
                logs.add(novoLog('DM ' + m.email, m, false, 'lookup: ' + lu.error, lu.statusCode));
                return;
            }
            SC_SlackService.Result r = SC_SlackService.postMessage(lu.userId, m.text);
            logs.add(novoLog('DM ' + m.email + ' (' + lu.userId + ')', m, (r.ok == true), r.error, r.statusCode));
        } else {
            SC_SlackService.Result r = SC_SlackService.postMessage(m.channelId, m.text);
            logs.add(novoLog(m.channelId, m, (r.ok == true), r.error, r.statusCode));
        }
    }

    // Trunca o que vai para campos de texto: um erro comprido do Slack não pode ser a razão
    // por que a linha de log é rejeitada.
    private static SC_Slack_Log__c novoLog(String canal, Msg m, Boolean sucesso, String erro, Integer statusCode) {
        return new SC_Slack_Log__c(
            Canal__c = trunc(canal, 80),
            Mensagem__c = m.text,
            Evento__c = trunc(m.evento, 40),
            Sucesso__c = sucesso,
            Erro__c = trunc(erro, 255),
            Status_Code__c = statusCode
        );
    }

    private static String destinoDe(Msg m) {
        if (m == null) return '(mensagem invalida)';
        return (m.email != null) ? 'DM ' + m.email : m.channelId;
    }

    // allOrNone a false: uma linha rejeitada não leva atrás o registo de todas as outras.
    private static void gravarLogs(List<SC_Slack_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        try {
            Database.insert(logs, false);
        } catch (Exception e) {
            System.debug('SC_SlackNotifier log falhou: ' + e.getMessage());
        }
    }

    private static void encadear(List<Msg> resto) {
        // Em teste a plataforma recusa encadear um Queueable a partir de outro; guardamos o
        // resto para o teste o correr à mão e provar que nada se perde.
        if (Test.isRunningTest()) { restoPendente = resto; return; }
        try {
            System.enqueueJob(new SC_SlackNotifier(resto));
        } catch (Exception e) {
            // sem encadeamento estas mensagens não seguem: fica registo disso, que é
            // exactamente o rasto que faltava no C-04.
            gravarLogs(new List<SC_Slack_Log__c>{
                new SC_Slack_Log__c(
                    Canal__c = '(encadeamento)',
                    Mensagem__c = 'Ficaram ' + resto.size() + ' mensagens por enviar.',
                    Evento__c = 'chain-falhou',
                    Sucesso__c = false,
                    Erro__c = trunc('enqueue: ' + e.getMessage(), 255)
                )
            });
        }
    }

    // ── handler do trigger (after update) ──────────────────────────────────────
    public static void handleAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        Map<Id, String> eventoPorOpp = new Map<Id, String>();
        for (Opportunity o : newList) {
            Opportunity old = (oldMap == null) ? null : oldMap.get(o.Id);
            if (old == null) continue;

            // 1) transições do estado de aprovação (prioritárias)
            if (o.Approval_Status__c != old.Approval_Status__c) {
                String s = o.Approval_Status__c;
                if (s == 'Aguarda L1')      eventoPorOpp.put(o.Id, 'approval-l1');
                else if (s == 'Aguarda L2') eventoPorOpp.put(o.Id, 'approval-l2');
                else if (s == 'Aguarda L3') eventoPorOpp.put(o.Id, 'approval-l3');
                else if (s == 'Aprovado')   eventoPorOpp.put(o.Id, 'approval-done');
                else if (s == 'Recusado')   eventoPorOpp.put(o.Id, 'approval-rejected');
            }

            // 2) fecho comercial (só se não houve já um evento de aprovação)
            if (!eventoPorOpp.containsKey(o.Id)) {
                if (o.IsWon == true && old.IsWon != true) {
                    eventoPorOpp.put(o.Id, 'won');
                } else if (o.StageName != old.StageName) {
                    if (o.StageName == 'Closed Lost')   eventoPorOpp.put(o.Id, 'lost');
                    else if (o.StageName == 'Cancelada') eventoPorOpp.put(o.Id, 'cancelada');
                }
            }
        }
        if (eventoPorOpp.isEmpty()) return;
        buildAndEnqueue(eventoPorOpp);
    }

    private static void buildAndEnqueue(Map<Id, String> eventoPorOpp) {
        Map<String, String> canalPorDir = new Map<String, String>();
        String canalGestao = null;
        for (SC_Slack_Canal__mdt c : SC_Slack_Canal__mdt.getAll().values()) {
            if (c.Direccao__c == 'Gestao') canalGestao = c.Channel_Id__c;
            else if (c.Direccao__c != null) canalPorDir.put(c.Direccao__c, c.Channel_Id__c);
        }

        List<Msg> msgs = new List<Msg>();
        for (Opportunity o : [
            SELECT Id, Name, Amount, Custo_Estimado__c, Direccao_Negocio__c, Owner.Name,
                   Motivo_Perda__c, Concorrente_Vencedor__c, Motivo_Cancelamento__c,
                   Requer_N2__c, Requer_N3__c,
                   Aprovador_Alvo_N1__c, Aprovador_Alvo_N1__r.Name, Aprovador_Alvo_N1__r.Email,
                   Aprovador_Alvo_N2__c, Aprovador_Alvo_N2__r.Name, Aprovador_Alvo_N2__r.Email,
                   Aprovador_Alvo_N3__c, Aprovador_Alvo_N3__r.Name, Aprovador_Alvo_N3__r.Email
            FROM Opportunity WHERE Id IN :eventoPorOpp.keySet()
        ]) {
            String ev = eventoPorOpp.get(o.Id);

            if (ev == 'approval-l1' || ev == 'approval-l2' || ev == 'approval-l3') {
                String lvl = ev.substringAfter('approval-'); // 'l1' | 'l2' | 'l3' (nome de evento no log)
                String nivel; String nome; String email; Boolean permitido;
                if (ev == 'approval-l1') {
                    nivel = 'N1'; nome = nomeOf(o.Aprovador_Alvo_N1__r); email = emailOf(o.Aprovador_Alvo_N1__r);
                    permitido = (o.Aprovador_Alvo_N1__c != null);
                } else if (ev == 'approval-l2') {
                    nivel = 'N2'; nome = nomeOf(o.Aprovador_Alvo_N2__r); email = emailOf(o.Aprovador_Alvo_N2__r);
                    // guarda do nivel fantasma: so notifica N2 se o nivel existe mesmo
                    permitido = (o.Requer_N2__c == true && o.Aprovador_Alvo_N2__c != null);
                } else {
                    nivel = 'N3'; nome = nomeOf(o.Aprovador_Alvo_N3__r); email = emailOf(o.Aprovador_Alvo_N3__r);
                    // guarda do nivel fantasma: so notifica N3 se o nivel existe mesmo
                    permitido = (o.Requer_N3__c == true && o.Aprovador_Alvo_N3__c != null);
                }
                // nivel fantasma (transicao transitoria por Aguarda L(n) sem esse nivel): nao notifica ninguem
                if (!permitido) continue;

                // DM ao aprovador (com link directo à oportunidade)
                if (email != null) {
                    String dm = '🔔 Tens uma proposta para aprovar (' + nivel + '): *' + o.Name + '* ('
                        + eur(o.Amount) + margemSuffix(o) + '), dono ' + o.Owner.Name + '. <' + linkOpp(o.Id) + '|Abrir no Salesforce>';
                    msgs.add(new Msg(null, email, dm, 'aprov-' + lvl + '-dm'));
                }
                // auditoria ao canal de gestão (tambem guardada pelo nivel fantasma acima)
                if (canalGestao != null) {
                    String quem = (nome != null) ? nome : '(aprovador ' + nivel + ' não definido)';
                    String aud;
                    if (nivel == 'N1')      aud = '📋 Proposta *' + o.Name + '* (' + eur(o.Amount) + ') submetida a aprovação. Aprovador ' + nivel + ' (' + quem + ') notificado.';
                    else if (nivel == 'N2') aud = '📋 *' + o.Name + '* aprovada em N1, agora pendente de N2. Aprovador ' + nivel + ' (' + quem + ') notificado.';
                    else                    aud = '📋 *' + o.Name + '* aprovada em N2, agora pendente de N3. Aprovador ' + nivel + ' (' + quem + ') notificado.';
                    msgs.add(new Msg(canalGestao, null, aud, 'aprov-' + lvl + '-gestao'));
                }

            } else if (ev == 'approval-done') {
                if (canalGestao != null) {
                    msgs.add(new Msg(canalGestao, null, '✅ *' + o.Name + '* (' + eur(o.Amount) + ') APROVADA (aprovação interna concluída).', 'aprov-concluida'));
                }
            } else if (ev == 'approval-rejected') {
                if (canalGestao != null) {
                    msgs.add(new Msg(canalGestao, null, '🚫 *' + o.Name + '* RECUSADA na aprovação interna.', 'aprov-recusada'));
                }
            } else {
                // fecho comercial -> canal da direção
                String canal = canalPorDir.get(o.Direccao_Negocio__c);
                if (canal == null) continue;
                msgs.add(new Msg(canal, null, buildTextFecho(ev, o), ev));
            }
        }
        if (msgs.isEmpty()) return;
        try {
            System.enqueueJob(new SC_SlackNotifier(msgs));
        } catch (Exception e) {
            System.debug('SC_SlackNotifier enqueue falhou: ' + e.getMessage());
        }
    }

    private static String buildTextFecho(String ev, Opportunity o) {
        if (ev == 'won') {
            return '🎉 Ganhámos: *' + o.Name + '* (' + eur(o.Amount) + ').';
        } else if (ev == 'lost') {
            return '❌ Perdida: *' + o.Name + '*. Motivo: ' + val(o.Motivo_Perda__c) + '. Concorrente: ' + val(o.Concorrente_Vencedor__c) + '.';
        } else if (ev == 'cancelada') {
            return '⏹️ Cancelada: *' + o.Name + '*. Motivo: ' + val(o.Motivo_Cancelamento__c) + '.';
        }
        return o.Name;
    }

    // ── helpers ────────────────────────────────────────────────────────────────
    private static String eur(Decimal amount) {
        return (amount == null) ? '?' : String.valueOf(amount.setScale(0)) + '€';
    }
    private static String margemSuffix(Opportunity o) {
        String mg = margem(o);
        return (mg != null) ? ', margem ' + mg : '';
    }
    private static String margem(Opportunity o) {
        if (o.Amount == null || o.Amount == 0) return null;
        Decimal custo = (o.Custo_Estimado__c == null) ? 0 : o.Custo_Estimado__c;
        return String.valueOf(((o.Amount - custo) / o.Amount * 100).setScale(0)) + '%';
    }
    // Link directo à página lightning do registo (o domínio da org resolve o /Id).
    private static String linkOpp(Id oppId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/' + oppId;
    }
    private static String nomeOf(User u) { return (u == null) ? null : u.Name; }
    private static String emailOf(User u) { return (u == null || String.isBlank(u.Email)) ? null : u.Email; }
    private static String val(String s) { return String.isBlank(s) ? '(n/d)' : s; }
    private static String trunc(String s, Integer max) { return (s != null && s.length() > max) ? s.substring(0, max) : s; }
}