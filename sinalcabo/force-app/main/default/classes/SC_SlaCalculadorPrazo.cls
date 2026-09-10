/**
 * Alvo de um milestone de SLA calculado a partir do prazo que está no tipo de trabalho
 * da ordem, em vez de um número fixo escrito no entitlement process.
 *
 * A plataforma chama este método quando aplica um milestone cujo tempo de conclusão é
 * uma classe Apex, e passa o id do registo e o id do tipo de milestone. A interface é
 * documentada para casos, por isso o método confirma o prefixo do id antes de tocar no
 * schema e escreve no log o que recebeu: é essa linha que prova se em ordens de trabalho
 * chega o id da ordem.
 *
 * Corre sem sharing de propósito: o prazo é configuração do catálogo da NOS e o alvo do
 * SLA não pode depender do que o utilizador que gravou a ordem consegue ver.
 */
global without sharing class SC_SlaCalculadorPrazo implements Support.MilestoneTriggerTimeCalculator {

    /**
     * Sem prazo no tipo de trabalho o milestone nasce com um minuto: vence de imediato e
     * aparece nas vistas de incumprimento, em vez de passar despercebido com prazo largo.
     */
    @TestVisible
    private static final Integer OMISSAO_MINUTOS = 1;

    /**
     * Tecto deliberado: o campo escolhe-se pelo nome do tipo de milestone. A versão
     * definitiva lê a correspondência de custom metadata, como a de tipo de trabalho para
     * processo, e então renomear um tipo de milestone na org deixa de mexer em código.
     */
    private static final String NOME_TEC = 'TEC';
    private static final String NOME_TE = 'TE';

    private static final String PREFIXO_ORDEM =
        WorkOrder.SObjectType.getDescribe().getKeyPrefix();

    /**
     * Uma ordem é consultada uma vez por transacção, mesmo com os dois milestones a
     * pedirem o alvo: a plataforma chama o método registo a registo, por isso sem esta
     * cache uma carga de ordens gasta duas consultas por ordem.
     */
    private static final Map<Id, WorkOrder> ORDENS = new Map<Id, WorkOrder>();

    @TestVisible
    private static final Map<Id, String> TIPOS = new Map<Id, String>();

    global Integer calculateMilestoneTriggerTime(String idRegisto, String idTipoMilestone) {
        System.debug(LoggingLevel.INFO, 'SC_SLA_CALC registo=' + idRegisto
            + ' prefixo=' + prefixo(idRegisto) + ' prefixoDaOrdem=' + PREFIXO_ORDEM
            + ' tipoMilestone=' + idTipoMilestone);

        WorkOrder ordem = ordem(idRegisto);
        if (ordem == null) {
            System.debug(LoggingLevel.INFO, 'SC_SLA_CALC nao e uma ordem de trabalho conhecida,'
                + ' devolvo ' + OMISSAO_MINUTOS + ' minuto');
            return OMISSAO_MINUTOS;
        }

        String nome = nomeDoTipo(idTipoMilestone);
        Decimal minutos = minutosDoAlvo(ordem, nome);
        System.debug(LoggingLevel.INFO, 'SC_SLA_CALC ordem=' + ordem.Id + ' tipoTrabalho='
            + ordem.WorkTypeId + ' milestone=' + nome + ' minutos=' + minutos);

        return minutos == null || minutos <= 0 ? OMISSAO_MINUTOS : minutos.intValue();
    }

    private static String prefixo(String id) {
        return String.isBlank(id) || id.length() < 3 ? '(vazio)' : id.substring(0, 3);
    }

    private static WorkOrder ordem(String idRegisto) {
        if (prefixo(idRegisto) != PREFIXO_ORDEM) {
            return null;
        }
        Id chave = comoId(idRegisto);
        if (chave == null) {
            return null;
        }
        if (!ORDENS.containsKey(chave)) {
            List<WorkOrder> encontradas = [
                SELECT Id, WorkTypeId, WorkType.TE_Minutos__c, WorkType.TEC_Minutos__c
                FROM WorkOrder
                WHERE Id = :chave
                LIMIT 1
            ];
            ORDENS.put(chave, encontradas.isEmpty() ? null : encontradas[0]);
        }
        return ORDENS.get(chave);
    }

    private static String nomeDoTipo(String idTipoMilestone) {
        Id chave = comoId(idTipoMilestone);
        if (chave == null) {
            return '';
        }
        if (!TIPOS.containsKey(chave)) {
            List<MilestoneType> encontrados = [
                SELECT Name FROM MilestoneType WHERE Id = :chave LIMIT 1
            ];
            TIPOS.put(chave, encontrados.isEmpty() ? '' : encontrados[0].Name);
        }
        return TIPOS.get(chave);
    }

    private static Decimal minutosDoAlvo(WorkOrder ordem, String nome) {
        if (ordem.WorkTypeId == null || String.isBlank(nome)) {
            return null;
        }
        String maiusculas = nome.toUpperCase();
        if (maiusculas.startsWith(NOME_TEC)) {
            return ordem.WorkType.TEC_Minutos__c;
        }
        if (maiusculas.startsWith(NOME_TE)) {
            return ordem.WorkType.TE_Minutos__c;
        }
        return null;
    }

    private static Id comoId(String texto) {
        if (String.isBlank(texto)) {
            return null;
        }
        try {
            return (Id) texto;
        } catch (Exception e) {
            return null;
        }
    }
}