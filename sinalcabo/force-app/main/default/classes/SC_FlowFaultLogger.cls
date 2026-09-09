/**
 * SC_FlowFaultLogger (SinalCabo)
 *
 * Ponto único de tratamento das falhas apanhadas pelos caminhos de erro das automações.
 * Grava o erro em SC_Erro_Automacao_Log__c e notifica os administradores no sino e no
 * telemóvel: nenhum caminho de falha é silencioso.
 *
 * PORQUE É APEX E NÃO ELEMENTOS DE FLOW, que seria o caminho declarativo habitual:
 *   1) O "Create Records" de um flow grava no contexto do UTILIZADOR. Os dois rollups de
 *      segmento correm dentro da gravação do comercial, que não tem (nem deve ter) permissão
 *      de criação neste objecto: o log falharia em silêncio. Em Apex o insert corre em modo
 *      de sistema e grava sempre.
 *   2) Um caminho de falha não pode ter falhas suas. Aqui tudo está em try/catch e o método
 *      NUNCA lança, portanto não há como o tratamento do erro matar o flow que o chamou.
 *      Num flow, cada elemento novo traria o seu próprio caminho de falha a desenhar.
 *   3) Resolver os administradores por permissão, sem identificadores fixos, precisa de uma
 *      consulta e de uma colecção. Replicado em seis flows seriam dezenas de elementos.
 *
 * DESTINATÁRIOS, sem nada fixo no código: quem tiver "Modify All Data" e estiver activo, por
 * permission set ou pelo perfil (a consulta apanha os dois, porque o perfil também tem um
 * permission set próprio). Não é preciso configurar nada por org: quem lá for administrador
 * recebe, e quem for desactivado sai da lista sozinho.
 *
 * MODO DE SISTEMA, deliberado e nas duas operações. É a mesma excepção documentada que o
 * SC_AvaliacaoAprovacao já faz: o PermissionSetAssignment não é legível pelo comercial, e o
 * log tem de ser gravável por quem quer que tenha disparado a automação.
 */
public with sharing class SC_FlowFaultLogger {

    private static final String TIPO_NOTIFICACAO = 'SC_Erro_Automacao';
    private static final Integer MAX_TITULO = 250;
    private static final Integer MAX_CORPO = 750;

    public class Pedido {
        @InvocableVariable(label='Origem' description='Nome da automação, por exemplo SC_Opportunity_AlertaDeadline' required=true)
        public String origem;

        @InvocableVariable(label='Elemento' description='Elemento que falhou, por exemplo Update_Opps_Bulk')
        public String elemento;

        @InvocableVariable(label='Mensagem' description='Mensagem da falha, tipicamente {!$Flow.FaultMessage}')
        public String mensagem;

        @InvocableVariable(label='Registo afectado' description='Id do registo em causa, quando a automação o conhece')
        public String registoAfectado;
    }

    @InvocableMethod(
        label='Registar falha de automação'
        description='Grava a falha em SC_Erro_Automacao_Log__c e avisa os administradores. Nunca lança.'
        category='SinalCabo'
    )
    public static void registar(List<Pedido> pedidos) {
        if (pedidos == null || pedidos.isEmpty()) return;

        List<SC_Erro_Automacao_Log__c> logs = new List<SC_Erro_Automacao_Log__c>();
        for (Pedido p : pedidos) {
            if (p == null) continue;
            logs.add(new SC_Erro_Automacao_Log__c(
                Origem__c = trunc(p.origem, 80),
                Elemento__c = trunc(p.elemento, 80),
                Mensagem__c = p.mensagem,
                Registo_Afectado__c = idValido(p.registoAfectado)
            ));
        }
        if (logs.isEmpty()) return;

        // 1) Gravar primeiro. O registo é o que fica; a notificação é conveniência.
        Id alvo = null;
        try {
            Database.insert(logs, false);
            for (SC_Erro_Automacao_Log__c l : logs) {
                if (l.Id != null) { alvo = l.Id; break; }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SC_FlowFaultLogger: insert do log falhou: ' + e.getMessage());
        }

        // 2) Notificar. Isolado do passo anterior de propósito: se o sino falhar, o log fica.
        try {
            notificar(logs, alvo);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SC_FlowFaultLogger: notificacao falhou: ' + e.getMessage());
        }
    }

    /** Uma notificação por invocação, não uma por falha: num lote em massa o flow chama isto
     *  uma vez com a lista toda, e trinta avisos iguais no sino não ajudam ninguém. */
    private static void notificar(List<SC_Erro_Automacao_Log__c> logs, Id alvo) {
        Set<String> destinatarios = administradores();
        if (destinatarios.isEmpty()) return;

        List<CustomNotificationType> tipos = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :TIPO_NOTIFICACAO LIMIT 1
        ];
        if (tipos.isEmpty()) return;

        SC_Erro_Automacao_Log__c primeiro = logs[0];
        String titulo = (logs.size() == 1)
            ? 'Falha em ' + blank(primeiro.Origem__c, 'automação')
            : logs.size() + ' falhas de automação';
        String corpo = blank(primeiro.Origem__c, 'automação')
            + (String.isBlank(primeiro.Elemento__c) ? '' : ' / ' + primeiro.Elemento__c)
            + ': ' + blank(primeiro.Mensagem__c, 'sem mensagem');
        if (logs.size() > 1) corpo += ' (e mais ' + (logs.size() - 1) + ')';

        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setNotificationTypeId(tipos[0].Id);
        n.setTitle(trunc(titulo, MAX_TITULO));
        n.setBody(trunc(corpo, MAX_CORPO));
        // Sem log gravado não há registo para abrir; o alvo passa a ser o registo afectado e,
        // em último caso, o próprio utilizador, porque a notificação exige um alvo válido.
        n.setTargetId(alvo != null ? alvo : alvoAlternativo(primeiro));
        n.send(destinatarios);
    }

    /** Quem administra a org, resolvido por permissão e não por nome nem por Id. */
    private static Set<String> administradores() {
        Set<String> ids = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.PermissionsModifyAllData = true
              AND Assignee.IsActive = true
              AND Assignee.UserType = 'Standard'
            LIMIT 200
        ]) {
            ids.add(psa.AssigneeId);
        }
        return ids;
    }

    private static Id alvoAlternativo(SC_Erro_Automacao_Log__c l) {
        if (String.isNotBlank(l.Registo_Afectado__c)) {
            try { return (Id) l.Registo_Afectado__c; } catch (Exception e) { /* cai para o utilizador */ }
        }
        return UserInfo.getUserId();
    }

    /** Um Id inválido no campo faria a linha de log ser rejeitada; vale mais perder o Id do
     *  que perder o registo da falha. */
    private static String idValido(String valor) {
        if (String.isBlank(valor)) return null;
        try {
            Id.valueOf(valor);
            return valor;
        } catch (Exception e) {
            return null;
        }
    }

    private static String blank(String s, String omissao) { return String.isBlank(s) ? omissao : s; }

    private static String trunc(String s, Integer max) {
        return (s != null && s.length() > max) ? s.substring(0, max) : s;
    }
}