/**
 * Batch de recálculo do segmento. Uma instância por fase.
 *
 * DUAS FASES, E PORQUE NÃO UMA
 * A fase Individual recalcula os campos da própria conta. A fase Grupo recalcula o agregado das
 * mães, e só pode correr depois de todas as filhas estarem certas: uma mãe recalculada a meio
 * da primeira fase somaria filhas já actualizadas com filhas ainda por actualizar. Por isso a
 * segunda fase arranca no finish() da primeira, e não em paralelo.
 *
 * O BYPASS, E PORQUE NÃO SE LIGA AQUI DENTRO
 * Durante as duas fases o SC_Aprovacao_Config__c.Bypass_Rollup_Grupo__c está ligado, senão cada
 * uma das filhas gravadas faria o flow de grupo recalcular a mãe outra vez, com duas queries e
 * um update por filha. Ligar e desligar é DML a um Custom Setting, que é setup object: fazê-lo
 * na mesma transacção que o update das contas dá MIXED_DML_OPERATION. Por isso quem liga é o
 * Queueable do SC_SegmentoRecalculo antes do batch arrancar, e quem desliga é outro Queueable
 * depois da segunda fase acabar. Cada um na sua transacção.
 *
 * Se o batch morrer a meio, o bypass fica ligado. É detectável, porque fica ligado apenas no
 * utilizador que corre o batch (o Custom Setting é hierárquico) e o log da execução mostra que
 * a fase Grupo nunca escreveu linha.
 *
 * REFERÊNCIAS: ADR-014, em projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoRecalculoBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final String modo;                 // Mensal | Completo | Conta
    private final String fase;                 // Individual | Grupo
    private final Set<Id> alvos;               // usado pela fase Grupo e pelo modo Conta
    private final DateTime arranque;

    private SC_SegmentoCalculo.Contagem total = new SC_SegmentoCalculo.Contagem();

    public SC_SegmentoRecalculoBatch(String modo, String fase, Set<Id> alvos) {
        this.modo = modo;
        this.fase = fase;
        this.alvos = alvos;
        this.arranque = DateTime.now();
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // Alvos explícitos ganham sempre ao modo. É o que a fase Grupo usa, e é também o que
        // permite exercitar a cadeia inteira num punhado de contas de teste sem mexer na base
        // real: um recálculo completo altera dados que o cliente vê e não se corre à experiência.
        if (alvos != null && !alvos.isEmpty()) {
            Set<Id> ids = alvos;
            return Database.getQueryLocator('SELECT Id FROM Account WHERE Id IN :ids');
        }
        if (fase == 'Grupo' || modo == 'Conta') {
            // Sem alvos não há nada a fazer nestes dois casos, e uma query vazia é mais honesta
            // do que varrer a org inteira por omissão.
            return Database.getQueryLocator('SELECT Id FROM Account WHERE Id = null');
        }
        if (modo == 'Completo') {
            return Database.getQueryLocator('SELECT Id FROM Account');
        }
        // Mensal: só as contas na fronteira da janela, que é a decisão 3 do desenho.
        // Ao virar de mês, um mês ENTRA na janela e outro SAI. Só as contas com negócio ganho
        // num desses dois meses podem ter mudado de segmento sem ninguém lhes tocar.
        Set<Id> fronteira = contasNaFronteira();
        return Database.getQueryLocator('SELECT Id FROM Account WHERE Id IN :fronteira');
    }

    /**
     * O mês que entra é o anterior ao corrente; o que sai é o que estava no início da janela
     * antes de ela avançar. Com a janela a excluir o mês corrente, ao passar de Julho para
     * Agosto de 2026 entra Julho de 2026 e sai Julho de 2025.
     */
    @TestVisible
    private static Set<Id> contasNaFronteira() {
        Date iniMes = SC_SegmentoCalculo.inicioMesCorrente();
        Date entraDe = iniMes.addMonths(-1), entraAte = iniMes;
        Date saiDe = SC_SegmentoCalculo.inicioJanela().addMonths(-1);
        Date saiAte = SC_SegmentoCalculo.inicioJanela();

        Set<Id> ids = new Set<Id>();
        for (Opportunity o : [SELECT AccountId FROM Opportunity
                              WHERE StageName = 'Closed Won'
                                AND Conta_Para_Pipeline__c = true
                                AND AccountId != null
                                AND ((CloseDate >= :entraDe AND CloseDate < :entraAte)
                                  OR (CloseDate >= :saiDe AND CloseDate < :saiAte))]) {
            ids.add(o.AccountId);
        }
        return ids;
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        Set<Id> ids = new Map<Id, Account>(scope).keySet();
        total.juntar(fase == 'Grupo'
            ? SC_SegmentoCalculo.recalcularGrupo(ids)
            : SC_SegmentoCalculo.recalcularIndividual(ids));
    }

    public void finish(Database.BatchableContext ctx) {
        Integer segundos = (Integer) ((DateTime.now().getTime() - arranque.getTime()) / 1000);
        SC_SegmentoRecalculo.registarLog(modo, fase, total, segundos);

        if (fase == 'Individual' && modo != 'Conta') {
            // Com alvos restritos, as mães são só as das contas tocadas, mesmo em modo Completo:
            // senão uma corrida de verificação em três contas arrastava a org toda para a fase 2.
            Boolean restrito = alvos != null && !alvos.isEmpty();
            Set<Id> maes = (modo == 'Completo' && !restrito)
                ? todasAsMaes()
                : SC_SegmentoCalculo.maesAfectadas(total.tocadas);
            if (!maes.isEmpty()) {
                Database.executeBatch(new SC_SegmentoRecalculoBatch(modo, 'Grupo', maes), 100);
                return;                                   // o bypass desliga no fim da fase Grupo
            }
        }
        if (modo != 'Conta') {
            System.enqueueJob(new SC_SegmentoRecalculo.DesligarBypass());
        }
    }

    /** No recálculo completo, mãe é qualquer conta que tenha pelo menos uma filha. */
    private static Set<Id> todasAsMaes() {
        Set<Id> maes = new Set<Id>();
        for (AggregateResult r : [SELECT ParentId FROM Account
                                  WHERE ParentId != null GROUP BY ParentId]) {
            maes.add((Id) r.get('ParentId'));
        }
        return maes;
    }
}