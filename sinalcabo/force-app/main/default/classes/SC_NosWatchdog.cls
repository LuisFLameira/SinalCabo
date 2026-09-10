/**
 * A vigia da entrada da NOS. Corre à hora e avisa quando a integração deixou de dar
 * sinal de vida ou ficou suspensa por muito tempo.
 *
 * O alerta de lote Falhado da F5a dispara quando alguma coisa corre mal. Esta classe
 * cobre o caso contrário e mais perigoso: quando não corre nada. Um agendador apagado,
 * um utilizador de integração desactivado ou uma fila parada não geram lote nenhum, e
 * sem vigia ninguém dava por isso.
 *
 * Não alerta com o travão de emergência ligado nem com a configuração inactiva: nesses
 * dois casos a paragem foi pedida por alguém.
 *
 * O mesmo alerta não sai mais do que uma vez por hora. A hora do último fica no custom
 * setting SC_NOS_Estado__c, que é dado da org e não viaja em deploys.
 */
public with sharing class SC_NosWatchdog implements Schedulable {
    public static final String NOME_AGENDAMENTO = 'SC_NOS_Watchdog';
    /** Regra absoluta do projecto: os avisos vão só para este endereço. */
    public static final String DESTINO = 'joel.regufe@techremotehub.com';
    public static final String NOTIFICACAO = 'SC_FS_Integracao_Falhou';

    /** Sem um lote fechado neste tempo, a integração está parada. */
    private static final Integer MINUTOS_SEM_LOTE = 30;
    /** Uma suspensão que ainda dure mais do que isto já não é um soluço da API. */
    private static final Integer HORAS_DE_SUSPENSAO = 1;
    private static final Integer MINUTOS_ENTRE_ALERTAS = 60;

    public void execute(SchedulableContext contexto) {
        verificar();
    }

    /** Devolve o motivo alertado, ou null quando não houve alerta. */
    public static String verificar() {
        String motivo = motivo();
        if (motivo == null || silenciado()) {
            return null;
        }
        avisar(motivo);
        SC_NosConfig.estado().Ultimo_Alerta_Watchdog__c = Datetime.now();
        SC_NosConfig.gravarEstado();
        return motivo;
    }

    // ------------------------------------------------------------------
    // O que se vigia
    // ------------------------------------------------------------------

    @TestVisible
    private static String motivo() {
        SC_NOS_Estado__c estado = SC_NosConfig.estado();
        Datetime suspensaLonga = Datetime.now().addHours(HORAS_DE_SUSPENSAO);
        if (estado.Suspenso_Ate__c != null && estado.Suspenso_Ate__c > suspensaLonga) {
            return 'A integração está suspensa até ' + instante(estado.Suspenso_Ate__c)
                + ', mais de ' + HORAS_DE_SUSPENSAO + ' hora à frente. '
                + 'A NOS recusou chamadas seguidas ou cortou o gateway duas vezes.';
        }
        if (SC_NosConfig.killSwitchLigado() || !SC_NosConfig.activo()) {
            return null;
        }
        Datetime limite = Datetime.now().addMinutes(-MINUTOS_SEM_LOTE);
        // Concluído com erros também é sinal de vida: houve chamada e houve resposta.
        // Alertar por causa de rejeições é trabalho do relatório de ocorrências.
        Integer fechados = [
            SELECT COUNT()
            FROM Lote_Integracao__c
            WHERE Estado__c IN (:SC_NosLote.ESTADO_CONCLUIDO, :SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS)
              AND LastModifiedDate >= :limite
        ];
        if (fechados == 0) {
            return 'Não há nenhum lote concluído nos últimos ' + MINUTOS_SEM_LOTE
                + ' minutos e o travão de emergência está desligado. '
                + 'A integração com a NOS está parada.';
        }
        return null;
    }

    private static Boolean silenciado() {
        Datetime ultimo = SC_NosConfig.estado().Ultimo_Alerta_Watchdog__c;
        return ultimo != null && ultimo > Datetime.now().addMinutes(-MINUTOS_ENTRE_ALERTAS);
    }

    // ------------------------------------------------------------------
    // Como se avisa
    // ------------------------------------------------------------------

    private static void avisar(String motivo) {
        Id alvo = alvo();
        enviarEmail(motivo, alvo);
        notificar(motivo, alvo);
    }

    private static void enviarEmail(String motivo, Id alvo) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ DESTINO });
        email.setSubject('SinalCabo FS: a integração com a NOS não está a correr');
        email.setPlainTextBody(corpo(motivo, alvo));
        email.setSaveAsActivity(false);
        // O resultado lê-se de propósito: um aviso que não sai tem de deixar rasto,
        // senão a vigia falha em silêncio, que é exactamente o que ela existe para evitar.
        Messaging.SendEmailResult resultado = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ email }, false
        )[0];
        System.debug(
            resultado.isSuccess() ? LoggingLevel.INFO : LoggingLevel.ERROR,
            'Aviso da vigia para ' + DESTINO + ': ' + (resultado.isSuccess()
                ? 'enviado.'
                : 'não saiu, ' + resultado.getErrors()[0].getMessage())
        );
    }

    @TestVisible
    private static String corpo(String motivo, Id alvo) {
        List<String> linhas = new List<String>{
            motivo,
            '',
            'Verificado em ' + instante(Datetime.now()) + ' (hora de Portugal).',
            'Travão de emergência: ' + (SC_NosConfig.killSwitchLigado() ? 'ligado' : 'desligado') + '.',
            'Configuração activa: ' + (SC_NosConfig.activo() ? 'sim' : 'não') + '.'
        };
        Datetime ate = SC_NosConfig.estado().Suspenso_Ate__c;
        if (ate != null) {
            linhas.add('Suspensa até: ' + instante(ate) + '.');
        }
        linhas.add('');
        linhas.add('O que fazer está no runbook, em salesforce/docs/MANUAL_STEPS.md, '
            + 'na secção da vigia da integração.');
        if (alvo != null) {
            linhas.add(URL.getOrgDomainUrl().toExternalForm() + '/' + alvo);
        }
        return String.join(linhas, '\n');
    }

    private static void notificar(String motivo, Id alvo) {
        List<CustomNotificationType> tipos = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICACAO LIMIT 1
        ];
        if (tipos.isEmpty() || alvo == null) {
            return;
        }
        Messaging.CustomNotification aviso = new Messaging.CustomNotification();
        aviso.setNotificationTypeId(tipos[0].Id);
        aviso.setTitle('Integração com a NOS parada');
        aviso.setBody(motivo.abbreviate(750));
        aviso.setTargetId(alvo);
        try {
            aviso.send(new Set<String>{ destinatario() });
        } catch (Exception e) {
            // A notificação é o segundo canal. Se falhar, o email já saiu.
            System.debug(LoggingLevel.WARN, 'Notificação da vigia não saiu: ' + e.getMessage());
        }
    }

    /** Registo para onde a notificação leva: o último lote, ou o próprio destinatário. */
    private static Id alvo() {
        List<Lote_Integracao__c> lotes = [
            SELECT Id FROM Lote_Integracao__c
            WHERE Interface__c = :SC_NosConfig.INTERFACE_ENTRADA
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return lotes.isEmpty() ? destinatario() : lotes[0].Id;
    }

    private static Id destinatario() {
        List<User> utilizadores = [
            SELECT Id FROM User WHERE Email = :DESTINO AND IsActive = TRUE ORDER BY CreatedDate LIMIT 1
        ];
        return utilizadores.isEmpty() ? UserInfo.getUserId() : utilizadores[0].Id;
    }

    private static String instante(Datetime valor) {
        return valor.format('yyyy-MM-dd HH:mm', SC_NosConfig.fuso());
    }
}