/**
 * Configuração e estado vivo da entrada de ordens da NOS.
 *
 * A configuração estática (janelas, timeout, passos) vive no custom metadata
 * Sistema_Cliente__mdt.NOS_FFM e viaja em deploys. O estado que muda a cada corrida
 * (travão de emergência, suspensão, contadores, cursores) vive no custom setting
 * hierárquico SC_NOS_Estado__c ao nível da organização, e é dado da org.
 *
 * Corre em contexto de sistema de propósito: quem lê a NOS é um job assíncrono sem
 * utilizador à frente e sem fronteira de confiança de interface. A validação do que
 * entra faz-se no parser e no mapeador, não por FLS.
 */
public with sharing class SC_NosConfig {
    public static final String SISTEMA = 'NOS_FFM';
    public static final String INTERFACE_ENTRADA = 'NOS FFM · Entrada de ordens';

    // Tipos de corrida (valores da lista Lote_Integracao__c.Tipo_Corrida__c).
    public static final String CORRIDA_ABERTAS = 'Abertas';
    public static final String CORRIDA_FECHADAS = 'Fechadas';
    public static final String CORRIDA_VARRIMENTO = 'Varrimento';
    public static final String CORRIDA_DETALHES = 'Detalhes';
    public static final String CORRIDA_MANUAL = 'Manual';
    public static final String CORRIDA_REPROCESSAMENTO = 'Reprocessamento';
    public static final String CORRIDA_CARGA = 'Carga histórica';

    // Suspensão: começa em 15 minutos e dobra a cada suspensão seguida até ao tecto.
    public static final Integer SUSPENSAO_INICIAL_MIN = 15;
    public static final Integer SUSPENSAO_MAXIMA_MIN = 120;
    // Dois cortes do gateway seguidos suspendem o endpoint.
    public static final Integer CORTES_ATE_SUSPENDER = 2;
    // Janela mínima a que a divisão por timeout desce antes de desistir.
    public static final Integer JANELA_MINIMA_HORAS = 6;
    // Um lote Em curso há menos disto trava uma nova corrida agendada.
    public static final Integer LOTE_EM_CURSO_MINUTOS = 10;

    private static Sistema_Cliente__mdt configuracao;
    private static SC_NOS_Estado__c estadoEmMemoria;

    // ------------------------------------------------------------------
    // Configuração estática
    // ------------------------------------------------------------------

    public static Sistema_Cliente__mdt config() {
        if (configuracao == null) {
            configuracao = Sistema_Cliente__mdt.getInstance(SISTEMA);
        }
        if (configuracao == null) {
            // Sem o registo na org, os valores de recurso dos getters seguram o código
            // e Activo__c fica falso: a corrida não arranca, em vez de arrancar às cegas.
            configuracao = new Sistema_Cliente__mdt(DeveloperName = SISTEMA);
        }
        return configuracao;
    }

    /** Substitui a configuração nos testes, sem tocar no registo da org. */
    @TestVisible
    private static void definirConfig(Sistema_Cliente__mdt substituta) {
        configuracao = substituta;
    }

    public static String namedCredential() {
        String nome = config().Named_Credential__c;
        return String.isBlank(nome) ? 'SC_NOS_FFM_API' : nome;
    }

    public static String fuso() {
        String nome = config().Fuso_Horario__c;
        return String.isBlank(nome) ? 'Europe/Lisbon' : nome;
    }

    public static Integer timeoutMs() {
        return inteiro(config().Timeout_ms__c, 120000);
    }

    public static Integer janelaAbertasHoras() {
        return inteiro(config().Janela_Abertas_Horas__c, 48);
    }

    public static Integer janelaFechadasHoras() {
        return inteiro(config().Janela_Fechadas_Horas__c, 24);
    }

    public static Integer passoVarrimentoDias() {
        return inteiro(config().Passo_Varrimento_Dias__c, 7);
    }

    public static Integer alcanceVarrimentoDias() {
        return inteiro(config().Alcance_Varrimento_Dias__c, 45);
    }

    public static Integer detalhesPorTransaccao() {
        return inteiro(config().Detalhes_Por_Transaccao__c, 5);
    }

    public static Integer retencaoPayloadDias() {
        return inteiro(config().Retencao_Payload_Dias__c, 30);
    }

    public static Boolean activo() {
        return config().Activo__c == true;
    }

    /** NIF da conta a que as ordens deste operador ficam ligadas. */
    public static String nifDaContaCliente() {
        return config().NIF_Conta_Cliente__c;
    }

    /** Nome da conta, só usado quando nenhuma conta tem o NIF configurado. */
    public static String nomeDaContaCliente() {
        return config().Nome_Conta_Cliente__c;
    }

    private static Integer inteiro(Decimal valor, Integer recurso) {
        return valor == null || valor <= 0 ? recurso : valor.intValue();
    }

    // ------------------------------------------------------------------
    // Estado vivo
    // ------------------------------------------------------------------

    /** Registo de organização do custom setting; cria-o em memória se ainda não existir. */
    public static SC_NOS_Estado__c estado() {
        if (estadoEmMemoria == null) {
            estadoEmMemoria = SC_NOS_Estado__c.getOrgDefaults();
            if (estadoEmMemoria == null) {
                estadoEmMemoria = new SC_NOS_Estado__c();
            }
            if (estadoEmMemoria.Contador_504__c == null) {
                estadoEmMemoria.Contador_504__c = 0;
            }
            if (estadoEmMemoria.Suspensoes_Seguidas__c == null) {
                estadoEmMemoria.Suspensoes_Seguidas__c = 0;
            }
        }
        return estadoEmMemoria;
    }

    /** Esquece o estado em memória: a próxima leitura volta à base de dados. */
    public static void esquecerEstado() {
        estadoEmMemoria = null;
    }

    public static void gravarEstado() {
        upsert estado();
        // Depois de gravar, a cópia em memória fica desalinhada da cache da plataforma.
        esquecerEstado();
    }

    public static Boolean killSwitchLigado() {
        return estado().Kill_Switch__c == true;
    }

    public static Boolean suspensaoActiva() {
        Datetime ate = estado().Suspenso_Ate__c;
        return ate != null && ate > Datetime.now();
    }

    /** Motivo por que a corrida não pode arrancar, ou null quando pode. */
    public static String motivoParaNaoCorrer() {
        if (!activo()) {
            return 'A configuração ' + SISTEMA + ' está inactiva.';
        }
        if (killSwitchLigado()) {
            return 'Travão de emergência ligado.';
        }
        if (suspensaoActiva()) {
            return 'Integração suspensa até ' + String.valueOf(estado().Suspenso_Ate__c) + '.';
        }
        return null;
    }

    public static Boolean podeCorrer() {
        return motivoParaNaoCorrer() == null;
    }

    /** Conta um corte do gateway. Devolve true quando o corte obriga a suspender. */
    public static Boolean registarCorte504() {
        SC_NOS_Estado__c e = estado();
        e.Contador_504__c = (e.Contador_504__c == null ? 0 : e.Contador_504__c) + 1;
        return e.Contador_504__c >= CORTES_ATE_SUSPENDER;
    }

    /** Uma resposta boa apaga a contagem de cortes e de suspensões seguidas. */
    public static void limparCortes() {
        SC_NOS_Estado__c e = estado();
        e.Contador_504__c = 0;
        e.Suspensoes_Seguidas__c = 0;
    }

    /** Suspende o endpoint: 15 minutos, a dobrar a cada suspensão seguida, tecto de 2 horas. */
    public static Integer suspender() {
        SC_NOS_Estado__c e = estado();
        Integer seguidas = (e.Suspensoes_Seguidas__c == null ? 0 : e.Suspensoes_Seguidas__c.intValue());
        Integer expoente = Math.min(seguidas, 3);
        Integer minutos = SUSPENSAO_INICIAL_MIN * (Integer) Math.pow(2, expoente);
        minutos = Math.min(minutos, SUSPENSAO_MAXIMA_MIN);
        e.Suspensoes_Seguidas__c = seguidas + 1;
        e.Contador_504__c = 0;
        e.Suspenso_Ate__c = Datetime.now().addMinutes(minutos);
        return minutos;
    }
}