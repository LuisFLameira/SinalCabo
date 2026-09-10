/**
 * Arranque da corrida de cinco em cinco minutos.
 *
 * São doze agendamentos, um por cada minuto múltiplo de cinco, porque a plataforma não
 * agenda abaixo da hora. Cada um abre o lote das abertas e põe o primeiro passo na fila:
 * o trabalho todo é do Queueable.
 *
 * **Existe um segundo caminho, pelo evento SC_NOS_Polling__e, que não está em uso.** Foi
 * construído para os lotes e as ordens ficarem com o CreatedBy do utilizador de
 * integração em vez do de quem agendou, porque um agendamento de Apex corre sempre como
 * quem o criou. O trigger do evento funciona e está testado, mas na fsbuild a 10/09/2026
 * a plataforma continuou a executá-lo como Automated Process, ignorando o utilizador do
 * PlatformEventSubscriberConfig, e esse utilizador não tem acesso ao principal da
 * credencial: todos os lotes falharam com "We couldn't access the credential(s)". Até isso
 * ficar resolvido, o agendador chama arrancar() de forma directa. Trocar de caminho é
 * trocar a linha do execute() por publicar(...).
 *
 * Três razões para não arrancar, por esta ordem: o travão de emergência, a suspensão
 * em curso, e um lote ainda Em curso há menos de dez minutos. A terceira é o que
 * impede duas cadeias de se sobreporem quando a NOS está lenta. As três avaliam-se sempre
 * do lado de quem executa, para o estado ser lido no instante certo; o invocable também as
 * lê antes de publicar, mas só para poder responder já a quem clicou.
 */
public with sharing class SC_NosPollingScheduler implements Schedulable {
    public static final String PREFIXO = 'SC_NOS_Polling_';
    private static final Integer PASSO_MINUTOS = 5;

    public static final String ORIGEM_AGENDADOR = 'Agendador';
    public static final String ORIGEM_MANUAL = 'Corrida manual';

    public void execute(SchedulableContext contexto) {
        arrancar();
    }

    // ------------------------------------------------------------------
    // Publicar e executar
    // ------------------------------------------------------------------

    /**
     * Põe um pedido de corrida no evento. Devolve o erro da publicação, ou null quando
     * saiu. Não verifica o travão nem a suspensão: isso é de quem executa.
     *
     * Fora de uso enquanto o utilizador do subscritor não for honrado pela plataforma.
     */
    public static String publicar(String tipoCorrida, Datetime inicio, Datetime fim, String origem) {
        Database.SaveResult resultado = EventBus.publish(new SC_NOS_Polling__e(
            Tipo_Corrida__c = tipoCorrida,
            Janela_Inicio__c = inicio,
            Janela_Fim__c = fim,
            Origem__c = origem
        ));
        if (resultado.isSuccess()) {
            return null;
        }
        return resultado.getErrors()[0].getStatusCode() + ': ' + resultado.getErrors()[0].getMessage();
    }

    /**
     * Executa os pedidos que chegaram pelo evento. Corre já como o utilizador do
     * subscritor. Um pedido com janela é uma corrida de uma janela só, que não encadeia;
     * um pedido sem janela é a cadeia normal.
     */
    public static void executar(List<SC_NOS_Polling__e> pedidos) {
        if (pedidos == null) {
            return;
        }
        for (SC_NOS_Polling__e pedido : pedidos) {
            if (pedido.Janela_Inicio__c != null && pedido.Janela_Fim__c != null) {
                correrJanela(pedido.Tipo_Corrida__c, pedido.Janela_Inicio__c, pedido.Janela_Fim__c);
            } else {
                arrancar();
            }
        }
    }

    /**
     * Corrida de uma janela explícita, que lê o que lhe pedem e pára. Repetível de
     * propósito: reler a mesma janela é o objectivo de uma corrida manual. Devolve o Id
     * do lote, ou null quando não pode correr.
     */
    public static Id correrJanela(String tipoCorrida, Datetime inicio, Datetime fim) {
        if (!SC_NosConfig.podeCorrer()) {
            return null;
        }
        String tipo = String.isBlank(tipoCorrida) ? SC_NosConfig.CORRIDA_MANUAL : tipoCorrida.trim();
        Lote_Integracao__c lote = SC_NosLote.abrirRepetivel(tipo, inicio, fim);
        if (lote == null) {
            return null;
        }
        SC_NosPollingQueueable trabalho = new SC_NosPollingQueueable(tipo, lote.Id, inicio, fim);
        trabalho.encadear = false;
        System.enqueueJob(trabalho);
        return lote.Id;
    }

    /** Abre a cadeia. Devolve o Id do lote das abertas, ou null quando não arranca. */
    public static Id arrancar() {
        if (!SC_NosConfig.podeCorrer()) {
            return null;
        }
        if (haCorridaEmCurso()) {
            return null;
        }
        Datetime agora = Datetime.now();
        Lote_Integracao__c lote = SC_NosLote.abrir(
            SC_NosConfig.CORRIDA_ABERTAS,
            agora.addHours(-SC_NosConfig.janelaAbertasHoras()),
            agora
        );
        if (lote == null) {
            return null;
        }
        SC_NosPollingQueueable trabalho = new SC_NosPollingQueueable(
            SC_NosConfig.CORRIDA_ABERTAS, lote.Id, lote.Janela_Inicio__c, lote.Janela_Fim__c
        );
        // A decisão do varrimento toma-se aqui e viaja com a cadeia até ao fim.
        trabalho.varrer = SC_NosPollingQueueable.horaDeVarrimento();
        System.enqueueJob(trabalho);
        return lote.Id;
    }

    @TestVisible
    private static Boolean haCorridaEmCurso() {
        Datetime limite = Datetime.now().addMinutes(-SC_NosConfig.LOTE_EM_CURSO_MINUTOS);
        return 0 < [
            SELECT COUNT()
            FROM Lote_Integracao__c
            WHERE Estado__c = :SC_NosLote.ESTADO_EM_CURSO
              AND CreatedDate > :limite
        ];
    }

    // ------------------------------------------------------------------
    // Agendamento
    // ------------------------------------------------------------------

    /** Cria os doze agendamentos. Os que já existem ficam como estão. */
    public static List<String> agendar() {
        Set<String> jaAgendados = new Set<String>();
        for (CronTrigger gatilho : [
            SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'SC_NOS_Polling%'
        ]) {
            jaAgendados.add(gatilho.CronJobDetail.Name);
        }
        List<String> criados = new List<String>();
        for (Integer minuto = 0; minuto < 60; minuto += PASSO_MINUTOS) {
            String nome = PREFIXO + (minuto < 10 ? '0' + minuto : String.valueOf(minuto));
            if (jaAgendados.contains(nome)) {
                continue;
            }
            System.schedule(nome, '0 ' + minuto + ' * * * ?', new SC_NosPollingScheduler());
            criados.add(nome);
        }
        return criados;
    }

    /** Apaga os doze agendamentos. Não mexe em nada que não seja nosso. */
    public static Integer desagendar() {
        Integer apagados = 0;
        for (CronTrigger gatilho : [
            SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'SC_NOS_Polling%'
        ]) {
            System.abortJob(gatilho.Id);
            apagados++;
        }
        return apagados;
    }
}