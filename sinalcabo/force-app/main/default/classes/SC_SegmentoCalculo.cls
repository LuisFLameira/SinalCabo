/**
 * Recálculo do segmento das contas, em Apex.
 *
 * PORQUE EXISTE EM APEX SE JÁ EXISTE EM FLOW
 * A janela de 12 meses move-se sozinha na viragem do mês. Os dois flows de rollup só disparam
 * com movimento na oportunidade, portanto uma conta sem negócio novo mantém para sempre o
 * segmento calculado na última vez que alguém lhe tocou, mesmo depois de o negócio que a punha
 * lá ter saído da janela. Alguém tem de recalcular sem esperar por movimento, e o flow
 * individual dispara na Opportunity, não na Account, logo não é invocável.
 *
 * O RISCO ASSUMIDO, E COMO ESTÁ COBERTO
 * Isto é uma terceira implementação do mesmo cálculo, ao lado dos dois flows. É exactamente o
 * tipo de duplicação que punha uma conta Prata no individual e Gold no grupo antes da Fase 6.
 * O que impede a divergência é o SC_SegmentoCalculoTest.equivalencia_com_os_flows: monta
 * cenários, deixa o flow calcular ao inserir a oportunidade, corre este Apex por cima e exige
 * que NADA mude. Se as duas lógicas se separarem, esse teste fica vermelho.
 *
 * O cálculo aqui é uma tradução literal do flow, e as escolhas seguem-no ponto por ponto:
 *   filtro das oportunidades   StageName = 'Closed Won' AND Conta_Para_Pipeline__c = true
 *   margem de cada uma         Amount menos Custo_Estimado__c, branco tratado como zero
 *   janela                     CloseDate >= início do mês menos 12 meses, e < início do mês
 *   ano corrente / anterior     por YEAR(CloseDate), e não pela janela
 *   escalão                    primeiro registo do Custom Metadata, por Ordem__c, cujo mínimo
 *                              o valor alcança, e só se o valor for acima de zero
 *   agregado de grupo          a própria mãe mais as filhas DIRECTAS, sem recursão
 *
 * REFERÊNCIAS: ADR-014, as três implementações e o teste de equivalência como guarda, em
 * projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoCalculo {

    /** Injecção de data para os testes. Sem isto, um teste de janela dependia do dia em que corre. */
    @TestVisible private static Date dataRef = null;
    private static Date agora() { return dataRef != null ? dataRef : Date.today(); }

    public static Date inicioMesCorrente() {
        Date h = agora();
        return Date.newInstance(h.year(), h.month(), 1);
    }
    public static Date inicioJanela() {
        return inicioMesCorrente().addMonths(-12);
    }

    // ─────────────────────────────── escalões ───────────────────────────────

    private static List<SC_Segmento_Escalao__mdt> cache;

    @TestVisible
    private static List<SC_Segmento_Escalao__mdt> escaloes() {
        if (cache == null) {
            // SOQL a Custom Metadata não conta para o limite de queries.
            cache = [SELECT Segmento__c, Minimo_Volume__c, Minimo_Margem__c, Ordem__c
                     FROM SC_Segmento_Escalao__mdt
                     WHERE Activo__c = true
                     ORDER BY Ordem__c ASC];
        }
        return cache;
    }

    /**
     * O segmento para um valor. Devolve null quando não há escalão, e é isso que produz o
     * "Sem segmento" da conta a zero: o Bronze tem mínimo zero, portanto sem o corte no
     * valor <= 0 uma conta sem negócio nenhum apanhava Bronze.
     */
    public static String segmento(Decimal valor, Boolean porMargem) {
        if (valor == null || valor <= 0) return null;
        for (SC_Segmento_Escalao__mdt e : escaloes()) {
            Decimal minimo = porMargem ? e.Minimo_Margem__c : e.Minimo_Volume__c;
            if (minimo == null) continue;
            if (valor >= minimo) return e.Segmento__c;
        }
        return null;
    }

    // ─────────────────────────────── contagem ───────────────────────────────

    public class Contagem {
        public Integer avaliadas = 0;
        public Integer alteradas = 0;
        public Integer segmentos = 0;
        public Integer erros = 0;
        public List<String> detalhe = new List<String>();
        /** Ids das contas gravadas. O chamador usa isto para saber que mães têm de ser refeitas. */
        public Set<Id> tocadas = new Set<Id>();

        public void juntar(Contagem o) {
            avaliadas += o.avaliadas;
            alteradas += o.alteradas;
            segmentos += o.segmentos;
            erros += o.erros;
            detalhe.addAll(o.detalhe);
            tocadas.addAll(o.tocadas);
        }
    }

    private class Agregado {
        Decimal total = 0, janela = 0, anoCorrente = 0, anoAnterior = 0;
        Decimal margemTotal = 0, margemJanela = 0, margemAnoCorrente = 0, margemAnoAnterior = 0;
    }

    // ────────────────────────── fase 1, individual ──────────────────────────

    public static Contagem recalcularIndividual(Set<Id> contaIds) {
        Contagem c = new Contagem();
        if (contaIds == null || contaIds.isEmpty()) return c;

        Map<Id, Account> contas = new Map<Id, Account>([
            SELECT Id, Name, ParentId,
                   Total_Closed_Won__c, Closed_Won_12M__c,
                   Closed_Won_Ano_Corrente__c, Closed_Won_Ano_Anterior__c,
                   Margem_Ganha_Total__c, Margem_Ganha_12M__c,
                   Margem_Ganha_Ano_Corrente__c, Margem_Ganha_Ano_Anterior__c,
                   Segmento__c, Segmento_Margem__c
            FROM Account WHERE Id IN :contaIds]);
        c.avaliadas = contas.size();
        if (contas.isEmpty()) return c;

        Map<Id, Agregado> porConta = new Map<Id, Agregado>();
        for (Id i : contas.keySet()) porConta.put(i, new Agregado());

        Date iniJanela = inicioJanela();
        Date iniMes = inicioMesCorrente();
        Integer anoCorr = agora().year();

        for (Opportunity o : [SELECT AccountId, Amount, CloseDate, Custo_Estimado__c
                              FROM Opportunity
                              WHERE AccountId IN :contas.keySet()
                                AND StageName = 'Closed Won'
                                AND Conta_Para_Pipeline__c = true]) {
            Agregado ag = porConta.get(o.AccountId);
            if (ag == null) continue;
            Decimal amt = o.Amount == null ? 0 : o.Amount;
            Decimal marg = amt - (o.Custo_Estimado__c == null ? 0 : o.Custo_Estimado__c);

            ag.total += amt;
            ag.margemTotal += marg;

            if (o.CloseDate != null && o.CloseDate >= iniJanela && o.CloseDate < iniMes) {
                ag.janela += amt;
                ag.margemJanela += marg;
            }
            Integer ano = o.CloseDate == null ? null : o.CloseDate.year();
            if (ano == anoCorr) {
                ag.anoCorrente += amt;
                ag.margemAnoCorrente += marg;
            } else if (ano == anoCorr - 1) {
                ag.anoAnterior += amt;
                ag.margemAnoAnterior += marg;
            }
        }

        List<Account> aGravar = new List<Account>();
        for (Account a : contas.values()) {
            Agregado ag = porConta.get(a.Id);
            String segNovo = segmento(ag.janela, false);
            String segMargNovo = segmento(ag.margemJanela, true);

            Boolean mudouSegmento = segNovo != a.Segmento__c || segMargNovo != a.Segmento_Margem__c;
            Boolean mudouValor = mudouSegmento
                || dif(a.Total_Closed_Won__c, ag.total)
                || dif(a.Closed_Won_12M__c, ag.janela)
                || dif(a.Closed_Won_Ano_Corrente__c, ag.anoCorrente)
                || dif(a.Closed_Won_Ano_Anterior__c, ag.anoAnterior)
                || dif(a.Margem_Ganha_Total__c, ag.margemTotal)
                || dif(a.Margem_Ganha_12M__c, ag.margemJanela)
                || dif(a.Margem_Ganha_Ano_Corrente__c, ag.margemAnoCorrente)
                || dif(a.Margem_Ganha_Ano_Anterior__c, ag.margemAnoAnterior);

            if (!mudouValor) continue;

            if (mudouSegmento) {
                c.segmentos++;
                c.detalhe.add(a.Name + ': ' + rotulo(a.Segmento__c) + ' -> ' + rotulo(segNovo)
                    + ' (volume ' + ag.janela.setScale(0) + ')'
                    + (segMargNovo == a.Segmento_Margem__c ? ''
                       : ' | margem ' + rotulo(a.Segmento_Margem__c) + ' -> ' + rotulo(segMargNovo)));
            }
            aGravar.add(new Account(
                Id = a.Id,
                Total_Closed_Won__c = ag.total,
                Closed_Won_12M__c = ag.janela,
                Closed_Won_Ano_Corrente__c = ag.anoCorrente,
                Closed_Won_Ano_Anterior__c = ag.anoAnterior,
                Margem_Ganha_Total__c = ag.margemTotal,
                Margem_Ganha_12M__c = ag.margemJanela,
                Margem_Ganha_Ano_Corrente__c = ag.margemAnoCorrente,
                Margem_Ganha_Ano_Anterior__c = ag.margemAnoAnterior,
                Segmento__c = segNovo,
                Segmento_Margem__c = segMargNovo));
        }

        gravar(aGravar, contas, c);
        return c;
    }

    // ─────────────────────────── fase 2, grupo ───────────────────────────

    /**
     * O agregado de grupo é a própria mãe mais as filhas DIRECTAS, sem recursão, que é o que o
     * SC_Account_Group_Rollup faz (Get_Filhas por ParentId, Get_Mae por Id). Uma hierarquia de
     * três níveis não sobe até ao topo, e essa convenção é a do ADR-009 ponto 5, não um descuido.
     */
    public static Contagem recalcularGrupo(Set<Id> maeIds) {
        Contagem c = new Contagem();
        if (maeIds == null || maeIds.isEmpty()) return c;

        String campos =
            'Id, Name, Total_Closed_Won__c, Closed_Won_12M__c, '
          + 'Closed_Won_Ano_Corrente__c, Closed_Won_Ano_Anterior__c, '
          + 'Margem_Ganha_Total__c, Margem_Ganha_12M__c, '
          + 'Margem_Ganha_Ano_Corrente__c, Margem_Ganha_Ano_Anterior__c, '
          + 'Total_Grupo__c, Total_Grupo_12M__c, '
          + 'Closed_Won_Grupo_Ano_Corrente__c, Closed_Won_Grupo_Ano_Anterior__c, '
          + 'Margem_Grupo_Total__c, Margem_Grupo_12M__c, '
          + 'Margem_Grupo_Ano_Corrente__c, Margem_Grupo_Ano_Anterior__c, '
          + 'Segmento_Grupo__c, Segmento_Margem_Grupo__c';

        Map<Id, Account> maes = new Map<Id, Account>(
            (List<Account>) Database.query('SELECT ' + campos + ' FROM Account WHERE Id IN :maeIds'));
        c.avaliadas = maes.size();
        if (maes.isEmpty()) return c;

        Map<Id, Agregado> porMae = new Map<Id, Agregado>();
        for (Account m : maes.values()) {
            Agregado ag = new Agregado();
            somar(ag, m);                        // o próprio negócio da mãe entra no grupo
            porMae.put(m.Id, ag);
        }

        Set<Id> ids = maes.keySet();
        for (Account f : Database.query(
                'SELECT ParentId, ' + campos + ' FROM Account WHERE ParentId IN :ids')) {
            Agregado ag = porMae.get(f.ParentId);
            if (ag != null) somar(ag, f);
        }

        List<Account> aGravar = new List<Account>();
        for (Account m : maes.values()) {
            Agregado ag = porMae.get(m.Id);
            String segNovo = segmento(ag.janela, false);
            String segMargNovo = segmento(ag.margemJanela, true);

            Boolean mudouSegmento = segNovo != m.Segmento_Grupo__c
                                 || segMargNovo != m.Segmento_Margem_Grupo__c;
            Boolean mudou = mudouSegmento
                || dif(m.Total_Grupo__c, ag.total)
                || dif(m.Total_Grupo_12M__c, ag.janela)
                || dif(m.Closed_Won_Grupo_Ano_Corrente__c, ag.anoCorrente)
                || dif(m.Closed_Won_Grupo_Ano_Anterior__c, ag.anoAnterior)
                || dif(m.Margem_Grupo_Total__c, ag.margemTotal)
                || dif(m.Margem_Grupo_12M__c, ag.margemJanela)
                || dif(m.Margem_Grupo_Ano_Corrente__c, ag.margemAnoCorrente)
                || dif(m.Margem_Grupo_Ano_Anterior__c, ag.margemAnoAnterior);

            if (!mudou) continue;

            if (mudouSegmento) {
                c.segmentos++;
                c.detalhe.add('[grupo] ' + m.Name + ': ' + rotulo(m.Segmento_Grupo__c)
                    + ' -> ' + rotulo(segNovo) + ' (volume ' + ag.janela.setScale(0) + ')');
            }
            aGravar.add(new Account(
                Id = m.Id,
                Total_Grupo__c = ag.total,
                Total_Grupo_12M__c = ag.janela,
                Closed_Won_Grupo_Ano_Corrente__c = ag.anoCorrente,
                Closed_Won_Grupo_Ano_Anterior__c = ag.anoAnterior,
                Margem_Grupo_Total__c = ag.margemTotal,
                Margem_Grupo_12M__c = ag.margemJanela,
                Margem_Grupo_Ano_Corrente__c = ag.margemAnoCorrente,
                Margem_Grupo_Ano_Anterior__c = ag.margemAnoAnterior,
                Segmento_Grupo__c = segNovo,
                Segmento_Margem_Grupo__c = segMargNovo));
        }

        gravar(aGravar, maes, c);
        return c;
    }

    /** Soma os valores INDIVIDUAIS de uma conta ao agregado de grupo. */
    private static void somar(Agregado ag, Account a) {
        ag.total             += zero(a.Total_Closed_Won__c);
        ag.janela            += zero(a.Closed_Won_12M__c);
        ag.anoCorrente       += zero(a.Closed_Won_Ano_Corrente__c);
        ag.anoAnterior       += zero(a.Closed_Won_Ano_Anterior__c);
        ag.margemTotal       += zero(a.Margem_Ganha_Total__c);
        ag.margemJanela      += zero(a.Margem_Ganha_12M__c);
        ag.margemAnoCorrente += zero(a.Margem_Ganha_Ano_Corrente__c);
        ag.margemAnoAnterior += zero(a.Margem_Ganha_Ano_Anterior__c);
    }

    // ─────────────────────────── quem são as mães ───────────────────────────

    /**
     * As mães que precisam de segunda passagem depois de um conjunto de contas ter mudado:
     * a mãe de cada uma, e cada uma que seja ela própria mãe (porque o grupo inclui o próprio).
     */
    public static Set<Id> maesAfectadas(Set<Id> tocadas) {
        Set<Id> maes = new Set<Id>();
        if (tocadas == null || tocadas.isEmpty()) return maes;
        for (Account a : [SELECT Id, ParentId FROM Account WHERE Id IN :tocadas AND ParentId != null]) {
            maes.add(a.ParentId);
        }
        for (Account f : [SELECT ParentId FROM Account WHERE ParentId IN :tocadas]) {
            maes.add(f.ParentId);
        }
        return maes;
    }

    // ─────────────────────────────── auxiliares ───────────────────────────────

    private static Decimal zero(Decimal d) { return d == null ? 0 : d; }
    private static String rotulo(String s) { return String.isBlank(s) ? 'sem segmento' : s; }

    /**
     * Decide se um campo tem de ser gravado.
     *
     * UM CAMPO VAZIO NÃO É UM CAMPO A ZERO, e a primeira versão disto fundia os dois: tratava
     * null como zero nos dois lados, portanto uma conta com o campo nunca escrito e valor
     * calculado de zero era dada como "igual" e NUNCA saía do vazio. Na build ficaram 101 contas
     * com o Closed_Won_12M__c em branco enquanto o Total_Closed_Won__c ao lado mostrava 0,00, o
     * que se lê como "não calculado" em vez de "não tem negócio".
     *
     * O flow de rollup não tem este problema porque não compara nada: escreve sempre, e as
     * variáveis dele arrancam em zero. Era divergência de GRAVAÇÃO entre os dois caminhos, não
     * de cálculo, e é por isso que o segmento nunca esteve errado.
     *
     * O medo que motivou a versão antiga, deixar a conta "eternamente alterada", não se
     * concretiza: gravado uma vez, o campo passa a zero e daí em diante o ramo de baixo diz que
     * é igual. É uma escrita única por campo, e o teste
     * segunda_corrida_nao_grava_a_conta_a_zero prova-o.
     */
    private static Boolean dif(Decimal actual, Decimal novo) {
        if (actual == null) return true;
        return actual.setScale(2) != zero(novo).setScale(2);
    }

    /** Grava em modo parcial: uma conta com problema não leva as outras atrás. */
    private static void gravar(List<Account> aGravar, Map<Id, Account> origem, Contagem c) {
        if (aGravar.isEmpty()) return;
        List<Database.SaveResult> rs = Database.update(aGravar, false);
        for (Integer i = 0; i < rs.size(); i++) {
            if (rs[i].isSuccess()) {
                c.alteradas++;
                c.tocadas.add(aGravar[i].Id);
            } else {
                c.erros++;
                Account o = origem.get(aGravar[i].Id);
                c.detalhe.add('ERRO em ' + (o == null ? String.valueOf(aGravar[i].Id) : o.Name)
                    + ': ' + rs[i].getErrors()[0].getMessage());
            }
        }
    }
}