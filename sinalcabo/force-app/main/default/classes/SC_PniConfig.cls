/**
 * Configuração da importação do ficheiro do PNI.
 *
 * Vive no custom metadata Sistema_Cliente__mdt.PNI_Ficheiro e viaja em deploys, tal
 * como a configuração da entrada da NOS. Não há aqui estado vivo: uma importação é
 * um acto de uma pessoa e não um ciclo agendado, por isso não existem cursores nem
 * janelas a guardar entre corridas.
 *
 * Sem o registo na org os valores de recurso seguram o código e Activo__c fica falso,
 * o que trava a importação em vez de a deixar correr às cegas.
 */
public with sharing class SC_PniConfig {
    public static final String SISTEMA = 'PNI_Ficheiro';
    public static final String INTERFACE_ENTRADA = 'PNI · Ficheiro de ordens';

    // Tipos de corrida (valores da lista Lote_Integracao__c.Tipo_Corrida__c).
    public static final String CORRIDA_FICHEIRO = 'Ficheiro PNI';
    public static final String CORRIDA_SIMULACAO = 'Simulação do ficheiro PNI';
    public static final String CORRIDA_REPROCESSAMENTO = 'Reprocessamento';

    // Valor de WorkOrder.Origem_Registo__c escrito por esta importação.
    public static final String ORIGEM_PNI = 'Ficheiro do PNI';

    // Meio megabyte por pedaço, cerca de mil linhas, muito abaixo da memória de uma
    // transacção. É o valor de recurso quando o metadata não o traz.
    public static final Integer PEDACO_OMISSAO = 524288;

    private static Sistema_Cliente__mdt configuracao;

    public static Sistema_Cliente__mdt config() {
        if (configuracao == null) {
            configuracao = Sistema_Cliente__mdt.getInstance(SISTEMA);
        }
        if (configuracao == null) {
            configuracao = new Sistema_Cliente__mdt(DeveloperName = SISTEMA);
        }
        return configuracao;
    }

    /** Substitui a configuração nos testes, sem tocar no registo da org. */
    @TestVisible
    private static void definirConfig(Sistema_Cliente__mdt substituta) {
        configuracao = substituta;
    }

    public static Boolean activo() {
        return config().Activo__c == true;
    }

    /**
     * Linhas alteradas antes desta data não entram. Nulo traz tudo o que o ficheiro
     * tiver, que é o que se quer numa carga histórica pedida de propósito.
     */
    public static Date dataCorte() {
        return config().Data_Corte__c;
    }

    public static Integer pedacoBytes() {
        Decimal valor = config().Pedaco_Bytes__c;
        if (valor == null || valor <= 0) {
            return PEDACO_OMISSAO;
        }
        return Integer.valueOf(valor);
    }

    /** Quem tem esta permissão pode carregar o ficheiro. Mais ninguém. */
    public static Boolean podeImportar() {
        return FeatureManagement.checkPermission('SC_FS_Importar_PNI');
    }
}