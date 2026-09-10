/**
 * Testes do cálculo do alvo dos milestones de SLA a partir do tipo de trabalho.
 *
 * `MilestoneType` é objecto de SETUP: criá-lo depois de um tipo de trabalho ou de uma
 * ordem na mesma transacção dá MIXED_DML_OPERATION. Por isso TODOS os tipos de
 * milestone, incluindo o que serve o caso do milestone desconhecido, nascem no
 * `@TestSetup`, que é transacção à parte, e nenhum método de teste os cria.
 */
@IsTest
private class SC_SlaCalculadorPrazoTest {

    private static final String TIPO_TE = 'TE (intervenção) teste';
    private static final String TIPO_TEC = 'TEC (cadastro) teste';
    private static final String TIPO_OUTRO = 'Aviso interno teste';

    @TestSetup
    static void tiposDeMilestone() {
        insert new List<MilestoneType>{
            new MilestoneType(Name = TIPO_TE, RecurrenceType = 'none'),
            new MilestoneType(Name = TIPO_TEC, RecurrenceType = 'none'),
            new MilestoneType(Name = TIPO_OUTRO, RecurrenceType = 'none')
        };
    }

    private static Id tipoMilestone(String nome) {
        return [SELECT Id FROM MilestoneType WHERE Name = :nome LIMIT 1].Id;
    }

    private static WorkOrder ordem(Decimal te, Decimal tec) {
        WorkType tipo = new WorkType(
            Name = 'SPIKE SLA', Codigo_Cliente__c = 'SPIKE-SLA',
            EstimatedDuration = 120, DurationType = 'Minutes',
            ShouldAutoCreateSvcAppt = false,
            TE_Minutos__c = te, TEC_Minutos__c = tec
        );
        insert tipo;
        WorkOrder ordem = new WorkOrder(Subject = 'SPIKE SLA', WorkTypeId = tipo.Id);
        insert ordem;
        return ordem;
    }

    @IsTest
    static void teLeOPrazoDeIntervencaoDoTipoDeTrabalho() {
        WorkOrder ordem = ordem(180, 10080);
        Id tipo = tipoMilestone(TIPO_TE);

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(ordem.Id, tipo);
        Test.stopTest();

        Assert.areEqual(180, minutos, 'O alvo do TE tem de ser o TE (minutos) do tipo de trabalho.');
    }

    @IsTest
    static void tecLeOPrazoDoCadastroDoTipoDeTrabalho() {
        WorkOrder ordem = ordem(180, 10080);
        Id tipo = tipoMilestone(TIPO_TEC);

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(ordem.Id, tipo);
        Test.stopTest();

        Assert.areEqual(10080, minutos,
            'O alvo do TEC tem de ser o TEC (minutos) e nunca o TE, que é o campo vizinho.');
    }

    @IsTest
    static void ordemSemTipoDeTrabalhoCaiNoValorPorOmissao() {
        WorkOrder ordem = new WorkOrder(Subject = 'SPIKE SLA sem tipo');
        insert ordem;

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(
            ordem.Id, tipoMilestone(TIPO_TE));
        Test.stopTest();

        Assert.areEqual(1, minutos,
            'Sem tipo de trabalho o milestone nasce vencido, com um minuto.');
    }

    @IsTest
    static void tipoDeTrabalhoSemPrazoCaiNoValorPorOmissao() {
        WorkOrder ordem = ordem(null, null);

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(
            ordem.Id, tipoMilestone(TIPO_TE));
        Test.stopTest();

        Assert.areEqual(1, minutos, 'Tipo de trabalho sem prazo preenchido vale um minuto.');
    }

    @IsTest
    static void prazoZeroCaiNoValorPorOmissao() {
        WorkOrder ordem = ordem(0, 10080);

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(
            ordem.Id, tipoMilestone(TIPO_TE));
        Test.stopTest();

        Assert.areEqual(1, minutos,
            'Um alvo de zero minutos não é aceitável para a plataforma, vale o mínimo.');
    }

    @IsTest
    static void registoQueNaoEOrdemNaoRebentaECaiNoValorPorOmissao() {
        Account conta = new Account(Name = 'SPIKE SLA conta');
        insert conta;

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(
            conta.Id, tipoMilestone(TIPO_TE));
        Test.stopTest();

        Assert.areEqual(1, minutos,
            'Se a plataforma passar o id de outro objecto, o método devolve o mínimo sem falhar.');
    }

    @IsTest
    static void idVazioOuInvalidoCaiNoValorPorOmissao() {
        Test.startTest();
        SC_SlaCalculadorPrazo calculador = new SC_SlaCalculadorPrazo();
        Integer vazio = calculador.calculateMilestoneTriggerTime(null, null);
        Integer lixo = calculador.calculateMilestoneTriggerTime('nada disto e um id', 'nem isto');
        Test.stopTest();

        Assert.areEqual(1, vazio, 'Id vazio vale o mínimo.');
        Assert.areEqual(1, lixo, 'Texto que não é um id vale o mínimo e não lança excepção.');
    }

    @IsTest
    static void tipoDeMilestoneDesconhecidoCaiNoValorPorOmissao() {
        Id outro = tipoMilestone(TIPO_OUTRO);
        WorkOrder ordem = ordem(180, 10080);

        Test.startTest();
        Integer minutos = new SC_SlaCalculadorPrazo().calculateMilestoneTriggerTime(
            ordem.Id, outro);
        Test.stopTest();

        Assert.areEqual(1, minutos,
            'Um milestone que não é TE nem TEC não tem campo de prazo, logo vale o mínimo.');
    }

    /**
     * A plataforma chama o método uma vez por milestone: numa carga de ordens são duas
     * chamadas por ordem. Este teste falha se alguém tirar a cache e voltar a consultar
     * a ordem em cada chamada.
     */
    @IsTest
    static void aMesmaOrdemSoEConsultadaUmaVez() {
        WorkOrder ordem = ordem(180, 10080);
        Id te = tipoMilestone(TIPO_TE);
        Id tec = tipoMilestone(TIPO_TEC);

        Test.startTest();
        SC_SlaCalculadorPrazo calculador = new SC_SlaCalculadorPrazo();
        calculador.calculateMilestoneTriggerTime(ordem.Id, te);
        Integer consultasApos1 = Limits.getQueries();
        Integer segundo = calculador.calculateMilestoneTriggerTime(ordem.Id, tec);
        Integer consultasApos2 = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(10080, segundo, 'A segunda chamada devolve o alvo do TEC.');
        Assert.areEqual(1, consultasApos2 - consultasApos1,
            'A segunda chamada só consulta o tipo de milestone, nunca outra vez a ordem.');
    }
}