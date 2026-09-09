/**
 * Porta de entrada do recálculo do segmento. É o que o agendamento mensal, os dois botões e
 * qualquer script chamam. Guarda aqui a orquestração do bypass e o registo do log, para o batch
 * e os Screen Flows não terem de conhecer nenhuma dessas duas coisas.
 *
 * TRÊS ENTRADAS
 *   umaConta(id)   síncrono. É o botão da ficha, e serve para o Marcelo responder a um comercial
 *                  que reporta um segmento errado sem esperar pelo fim do mês. Não usa bypass:
 *                  com uma conta o encadeamento do rollup de grupo é barato e resolve a mãe.
 *   completo()     todas as contas. É o botão da lista, e é a rede do recálculo mensal: se a
 *                  lógica de fronteira deixar contas de fora, isto corrige tudo.
 *   mensal()       só as contas na fronteira da janela. É o que o agendamento corre.
 *
 * REFERÊNCIAS: ADR-014, em projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoRecalculo {

    // ───────────────────────────── uma conta, síncrono ─────────────────────────────

    /**
     * Recalcula uma conta e, se ela for mãe, também o agregado dela.
     *
     * O Apex só admite um @InvocableMethod por classe, portanto os dois botões entram por
     * classes de acção próprias, SC_SegmentoRecalculoContaAction e ...TodasAction, que não fazem
     * mais nada senão delegar aqui. A lógica fica num sítio só.
     *
     * Devolve a linha de resumo para o Screen Flow mostrar, porque um botão que não diz o que
     * fez obriga a pessoa a ir verificar à mão.
     */
    public static String umaConta(Id contaId) {
        SC_SegmentoCalculo.Contagem c = SC_SegmentoCalculo.recalcularIndividual(
            new Set<Id>{ contaId });
        // Sem bypass: se a conta tem mãe, o flow de grupo já a refez no update acima. O que
        // falta é o caso de ela PRÓPRIA ser mãe, que o flow não cobre porque dispara na filha.
        Set<Id> maes = SC_SegmentoCalculo.maesAfectadas(new Set<Id>{ contaId });
        if (!maes.isEmpty()) c.juntar(SC_SegmentoCalculo.recalcularGrupo(maes));

        registarLog('Conta', 'Individual', c, 0);

        if (c.erros > 0) {
            return 'O recálculo falhou: ' + String.join(c.detalhe, ' | ');
        }
        if (c.alteradas == 0) {
            return 'Nada a corrigir: os valores já estavam certos.';
        }
        return c.segmentos > 0
            ? 'Segmento actualizado. ' + String.join(c.detalhe, ' | ')
            : 'Valores actualizados, o segmento não mudou.';
    }

    // ───────────────────────────── em massa, assíncrono ─────────────────────────────

    public static void completo() { arrancar('Completo', null); }
    public static void mensal()   { arrancar('Mensal', null); }

    /**
     * A cadeia completa (bypass, fase Individual, fase Grupo, desligar) num conjunto escolhido
     * de contas. Existe porque um recálculo completo altera dados que o cliente vê, e a cadeia
     * tem de poder ser exercitada antes disso, em contas de teste.
     */
    public static void emMassa(Set<Id> contaIds) { arrancar('Completo', contaIds); }

    /**
     * Não arranca o batch aqui. Enfileira um Queueable que liga o bypass e só depois o arranca,
     * porque ligar o bypass é DML a um Custom Setting: se o chamador já tiver feito DML a
     * qualquer outro objecto nesta transacção, como um Screen Flow faz, dava MIXED_DML_OPERATION.
     */
    private static void arrancar(String modo, Set<Id> alvos) {
        System.enqueueJob(new LigarBypassEArrancar(modo, alvos));
    }

    public class LigarBypassEArrancar implements Queueable {
        private final String modo;
        private final Set<Id> alvos;
        public LigarBypassEArrancar(String modo, Set<Id> alvos) {
            this.modo = modo;
            this.alvos = alvos;
        }
        public void execute(QueueableContext ctx) {
            porBypass(true);
            Database.executeBatch(new SC_SegmentoRecalculoBatch(modo, 'Individual', alvos), 200);
        }
    }

    public class DesligarBypass implements Queueable {
        public void execute(QueueableContext ctx) { porBypass(false); }
    }

    /** O Custom Setting é hierárquico, portanto isto afecta só quem corre o recálculo. */
    @TestVisible
    private static void porBypass(Boolean ligado) {
        SC_Aprovacao_Config__c cfg = SC_Aprovacao_Config__c.getInstance(UserInfo.getUserId());
        if (cfg == null || cfg.Id == null) {
            insert new SC_Aprovacao_Config__c(SetupOwnerId = UserInfo.getUserId(),
                                              Bypass_Rollup_Grupo__c = ligado);
            return;
        }
        if (cfg.Bypass_Rollup_Grupo__c == ligado) return;
        cfg.Bypass_Rollup_Grupo__c = ligado;
        update cfg;
    }

    // ───────────────────────────────────── log ─────────────────────────────────────

    /**
     * Uma linha por fase de cada execução. A contagem é obrigatória e não decorativa: com o
     * recálculo mensal limitado às contas na fronteira, uma query de fronteira que pare de
     * apanhar casos falha em silêncio, e o número de avaliadas por mês é o único sinal.
     */
    public static void registarLog(String modo, String fase,
                                   SC_SegmentoCalculo.Contagem c, Integer segundos) {
        String detalhe = String.join(c.detalhe, '\n');
        Integer maximo = SC_Recalculo_Log__c.Detalhe__c.getDescribe().getLength();
        if (detalhe.length() > maximo) {
            String aviso = '\n[truncado, ' + c.detalhe.size() + ' linhas no total]';
            detalhe = detalhe.substring(0, maximo - aviso.length()) + aviso;
        }
        insert new SC_Recalculo_Log__c(
            Modo__c = modo,
            Fase__c = fase,
            Contas_Avaliadas__c = c.avaliadas,
            Contas_Alteradas__c = c.alteradas,
            Segmentos_Alterados__c = c.segmentos,
            Erros__c = c.erros,
            Duracao_Segundos__c = segundos,
            Detalhe__c = detalhe);
    }
}