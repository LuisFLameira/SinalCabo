/**
 * Testes do recálculo do segmento.
 *
 * O TESTE QUE IMPORTA MAIS é o equivalencia_com_os_flows. Este Apex é uma terceira
 * implementação do mesmo cálculo, ao lado dos dois flows de rollup, e uma divergência entre
 * eles reproduz o defeito que a Fase 6 existiu para corrigir: a mesma conta com segmentos
 * diferentes calculados em bases diferentes. Esse teste deixa o flow calcular ao inserir a
 * oportunidade, corre este Apex por cima, e exige que NADA mude. Se as duas lógicas se
 * separarem, fica vermelho.
 */
@isTest
private class SC_SegmentoCalculoTest {

    // As oportunidades da SinalCabo têm validation rules de contrato no Closed Won, portanto
    // todas estas colunas são obrigatórias e não decorativas.
    private static Opportunity ganha(Id contaId, String nome, Decimal valor, Decimal custo, Date d) {
        return new Opportunity(
            Name = nome, AccountId = contaId, StageName = 'Closed Won',
            CloseDate = d, Amount = valor, Custo_Estimado__c = custo,
            Empresa_Lider__c = 'Sinalcabo',
            Data_Inicio_Contrato__c = d, Data_Fim_Contrato__c = d.addYears(1),
            Numero_Contrato__c = 'T-' + nome, Link_Documento__c = 'https://exemplo.invalid/t');
    }

    private static Date dentroDaJanela() {
        return SC_SegmentoCalculo.inicioMesCorrente().addMonths(-2);
    }
    private static Date foraDaJanela() {
        return SC_SegmentoCalculo.inicioMesCorrente().addMonths(-20);
    }

    // ───────────────────────────── escalões ─────────────────────────────

    @isTest static void escalao_sai_do_custom_metadata_por_ordem() {
        // Os valores vêm do CMT da org, portanto o teste afirma a RELAÇÃO e não os números:
        // um valor alto tem de cair num escalão de ordem menor ou igual ao de um valor baixo.
        String alto = SC_SegmentoCalculo.segmento(10000000, false);
        String baixo = SC_SegmentoCalculo.segmento(1, false);
        System.assertNotEquals(null, alto, 'dez milhões tem de apanhar algum escalão');
        System.assertNotEquals(null, baixo, 'um euro tem de apanhar o escalão de base');
        System.assertNotEquals(alto, baixo, 'dez milhões e um euro não podem dar o mesmo segmento');
    }

    @isTest static void conta_a_zero_fica_sem_segmento() {
        // Decisão C do Joel (03/08): o Bronze tem mínimo zero, portanto sem o corte no valor
        // acima de zero uma conta sem negócio nenhum apanhava Bronze.
        System.assertEquals(null, SC_SegmentoCalculo.segmento(0, false), 'zero não tem segmento');
        System.assertEquals(null, SC_SegmentoCalculo.segmento(null, false), 'nulo não tem segmento');
        System.assertEquals(null, SC_SegmentoCalculo.segmento(-5, false), 'negativo não tem segmento');
    }

    // ───────────────────────────── a janela ─────────────────────────────

    @isTest static void janela_sao_doze_meses_a_excluir_o_mes_corrente() {
        Date iniMes = SC_SegmentoCalculo.inicioMesCorrente();
        System.assertEquals(1, iniMes.day(), 'a janela fecha no dia 1');
        System.assertEquals(iniMes.addMonths(-12), SC_SegmentoCalculo.inicioJanela(),
            'a janela abre 12 meses antes do início do mês corrente');
    }

    @isTest static void negocio_fora_da_janela_nao_conta_para_o_segmento() {
        Account a = new Account(Name = 'T fora da janela');
        insert a;
        insert ganha(a.Id, 'fora', 4000000, 2000000, foraDaJanela());

        Account r = [SELECT Total_Closed_Won__c, Closed_Won_12M__c, Segmento__c
                     FROM Account WHERE Id = :a.Id];
        System.assertEquals(4000000, r.Total_Closed_Won__c, 'o acumulado de sempre conta tudo');
        System.assertEquals(0, r.Closed_Won_12M__c, 'a janela não apanha negócio de 20 meses atrás');
        System.assertEquals(null, r.Segmento__c,
            'sem negócio na janela não há segmento, mesmo com quatro milhões de histórico');
    }

    @isTest static void negocio_do_mes_corrente_ainda_nao_conta() {
        Account a = new Account(Name = 'T mês corrente');
        insert a;
        Date esteMes = SC_SegmentoCalculo.inicioMesCorrente().addDays(3);
        insert ganha(a.Id, 'agora', 2000000, 1000000, esteMes);

        Account r = [SELECT Closed_Won_12M__c, Total_Closed_Won__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(2000000, r.Total_Closed_Won__c, 'entra no acumulado de sempre');
        System.assertEquals(0, r.Closed_Won_12M__c,
            'um negócio ganho este mês só entra na janela no dia 1 do mês seguinte');
    }

    // ─────────────────── o teste que impede a divergência ───────────────────

    @isTest static void equivalencia_com_os_flows() {
        // Cenários variados de propósito: dentro e fora da janela, com e sem hierarquia, para
        // o Apex e o flow terem de concordar em mais do que um caminho.
        Account mae = new Account(Name = 'T EQ mãe');
        insert mae;
        Account filha = new Account(Name = 'T EQ filha', ParentId = mae.Id);
        Account solta = new Account(Name = 'T EQ solta');
        insert new List<Account>{ filha, solta };

        insert new List<Opportunity>{
            ganha(mae.Id,   'eq-mae-dentro',   300000, 150000, dentroDaJanela()),
            ganha(filha.Id, 'eq-filha-dentro', 2000000, 900000, dentroDaJanela()),
            ganha(filha.Id, 'eq-filha-fora',   5000000, 1000000, foraDaJanela()),
            ganha(solta.Id, 'eq-solta',        50000, 20000, dentroDaJanela())
        };

        List<String> campos = new List<String>{
            'Total_Closed_Won__c', 'Closed_Won_12M__c',
            'Closed_Won_Ano_Corrente__c', 'Closed_Won_Ano_Anterior__c',
            'Margem_Ganha_Total__c', 'Margem_Ganha_12M__c',
            'Margem_Ganha_Ano_Corrente__c', 'Margem_Ganha_Ano_Anterior__c',
            'Segmento__c', 'Segmento_Margem__c',
            'Total_Grupo__c', 'Total_Grupo_12M__c',
            'Margem_Grupo_Total__c', 'Margem_Grupo_12M__c',
            'Segmento_Grupo__c', 'Segmento_Margem_Grupo__c'
        };
        Set<Id> ids = new Set<Id>{ mae.Id, filha.Id, solta.Id };
        String soql = 'SELECT Id, Name, ' + String.join(campos, ', ')
                    + ' FROM Account WHERE Id IN :ids';

        Map<Id, Account> pelosFlows = new Map<Id, Account>((List<Account>) Database.query(soql));

        Test.startTest();
        SC_SegmentoCalculo.Contagem cInd = SC_SegmentoCalculo.recalcularIndividual(ids);
        SC_SegmentoCalculo.Contagem cGrp = SC_SegmentoCalculo.recalcularGrupo(new Set<Id>{ mae.Id });
        Test.stopTest();

        Map<Id, Account> peloApex = new Map<Id, Account>((List<Account>) Database.query(soql));

        for (Id i : ids) {
            for (String f : campos) {
                System.assertEquals(pelosFlows.get(i).get(f), peloApex.get(i).get(f),
                    'DIVERGÊNCIA entre o flow e o Apex em ' + pelosFlows.get(i).Name + '.' + f
                    + '. Os dois calculam o mesmo e um deles mudou.');
            }
        }
        System.assertEquals(0, cInd.alteradas,
            'o Apex não devia ter tido nada para corrigir depois do flow: '
            + String.join(cInd.detalhe, ' | '));
        System.assertEquals(0, cGrp.alteradas,
            'nem no grupo: ' + String.join(cGrp.detalhe, ' | '));
        System.assertEquals(0, cInd.erros + cGrp.erros, 'sem erros de gravação');
    }

    // ───────────────────────── o recálculo corrige ─────────────────────────

    @isTest static void recalculo_corrige_um_segmento_desactualizado() {
        Account a = new Account(Name = 'T desactualizada');
        insert a;
        insert ganha(a.Id, 'antiga', 4000000, 2000000, foraDaJanela());

        // Simula o estado a que a passagem do tempo leva: valores de quando o negócio ainda
        // estava na janela. É exactamente o que acontece a uma conta sem movimento novo.
        update new Account(Id = a.Id, Closed_Won_12M__c = 4000000,
                           Margem_Ganha_12M__c = 2000000, Segmento__c = 'Platina');

        Test.startTest();
        SC_SegmentoCalculo.Contagem c = SC_SegmentoCalculo.recalcularIndividual(new Set<Id>{ a.Id });
        Test.stopTest();

        Account r = [SELECT Closed_Won_12M__c, Segmento__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(0, r.Closed_Won_12M__c, 'a janela foi corrigida para zero');
        System.assertEquals(null, r.Segmento__c, 'e a conta deixou de ter segmento');
        System.assertEquals(1, c.avaliadas);
        System.assertEquals(1, c.alteradas);
        System.assertEquals(1, c.segmentos, 'a mudança de segmento tem de ser contada');
        System.assert(!c.detalhe.isEmpty(), 'e detalhada, senão ninguém sabe o que mudou');
    }

    @isTest static void recalculo_nao_grava_o_que_nao_mudou() {
        Account a = new Account(Name = 'T já certa');
        insert a;
        insert ganha(a.Id, 'certa', 300000, 150000, dentroDaJanela());

        Test.startTest();
        SC_SegmentoCalculo.Contagem c = SC_SegmentoCalculo.recalcularIndividual(new Set<Id>{ a.Id });
        Test.stopTest();

        System.assertEquals(1, c.avaliadas);
        System.assertEquals(0, c.alteradas,
            'gravar o que já está certo gasta limites e polui o LastModified de toda a base');
    }

    @isTest static void grupo_soma_a_propria_mae_mais_as_filhas() {
        Account mae = new Account(Name = 'T G mãe');
        insert mae;
        Account f1 = new Account(Name = 'T G f1', ParentId = mae.Id);
        Account f2 = new Account(Name = 'T G f2', ParentId = mae.Id);
        insert new List<Account>{ f1, f2 };
        insert new List<Opportunity>{
            ganha(mae.Id, 'g-mae', 100000, 50000, dentroDaJanela()),
            ganha(f1.Id,  'g-f1',  200000, 100000, dentroDaJanela()),
            ganha(f2.Id,  'g-f2',  300000, 150000, dentroDaJanela())
        };

        Test.startTest();
        SC_SegmentoCalculo.recalcularGrupo(new Set<Id>{ mae.Id });
        Test.stopTest();

        Account r = [SELECT Total_Grupo_12M__c, Closed_Won_12M__c FROM Account WHERE Id = :mae.Id];
        System.assertEquals(600000, r.Total_Grupo_12M__c,
            'o grupo inclui o negócio próprio da mãe, convenção do ADR-009 ponto 5');
        System.assertEquals(100000, r.Closed_Won_12M__c,
            'e o individual da mãe fica intacto ao lado');
    }

    @isTest static void maes_afectadas_apanha_a_mae_e_a_propria_se_for_mae() {
        Account avo = new Account(Name = 'T M avó');
        insert avo;
        Account mae = new Account(Name = 'T M mãe', ParentId = avo.Id);
        insert mae;
        Account filha = new Account(Name = 'T M filha', ParentId = mae.Id);
        insert filha;

        Set<Id> maes = SC_SegmentoCalculo.maesAfectadas(new Set<Id>{ mae.Id });
        System.assert(maes.contains(avo.Id), 'a mãe da conta tocada entra');
        System.assert(maes.contains(mae.Id),
            'e a própria conta tocada também, porque tem filhas e o grupo inclui o próprio');
        System.assertEquals(2, maes.size());
    }

    // ───────── o caso degenerado, que o teste de equivalência não cobria ─────────

    @isTest static void conta_sem_oportunidades_fica_a_zero_e_nao_vazia() {
        // Este é o caso que faltava: uma conta SEM oportunidade nenhuma. O flow nunca corre nela
        // (dispara na Opportunity), portanto os campos nascem vazios e ninguém os enche. A
        // primeira versão do dif() tratava null e zero como iguais, concluía que não havia nada
        // a mudar, e o campo ficava eternamente em branco enquanto o acumulado de sempre ao lado
        // mostrava 0,00. Foram 101 contas assim na build.
        Account a = new Account(Name = 'T sem negócio');
        insert a;

        Account antes = [SELECT Closed_Won_12M__c, Margem_Ganha_12M__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(null, antes.Closed_Won_12M__c,
            'a conta nasce com o campo vazio, é essa a premissa do teste');

        Test.startTest();
        SC_SegmentoCalculo.Contagem c = SC_SegmentoCalculo.recalcularIndividual(new Set<Id>{ a.Id });
        Test.stopTest();

        Account r = [SELECT Closed_Won_12M__c, Margem_Ganha_12M__c, Total_Closed_Won__c,
                            Segmento__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(0, r.Closed_Won_12M__c,
            'o recálculo tem de deixar ZERO e não vazio: vazio lê-se como "não calculado"');
        System.assertEquals(0, r.Margem_Ganha_12M__c, 'e o mesmo na margem');
        System.assertEquals(0, r.Total_Closed_Won__c, 'e no acumulado de sempre');
        System.assertEquals(null, r.Segmento__c,
            'mas SEM segmento, que é a decisão do Joel para conta a zero');
        System.assertEquals(1, c.alteradas, 'e conta como alterada, porque de facto gravou');
        System.assertEquals(0, c.segmentos, 'sem mudar de segmento, portanto não entra nessa contagem');
    }

    @isTest static void segunda_corrida_nao_grava_a_conta_a_zero() {
        // O medo que motivou a versão antiga do dif() era deixar a conta "eternamente alterada".
        // Este teste prova que não acontece: a gravação é única, e a partir da segunda corrida o
        // campo já está a zero e não há nada a fazer. Sem isto, a correcção trocava um defeito
        // visível por outro pior, escrever 112 contas em cada corrida mensal.
        Account a = new Account(Name = 'T sem negócio, segunda vez');
        insert a;

        Test.startTest();
        SC_SegmentoCalculo.Contagem primeira =
            SC_SegmentoCalculo.recalcularIndividual(new Set<Id>{ a.Id });
        SC_SegmentoCalculo.Contagem segunda =
            SC_SegmentoCalculo.recalcularIndividual(new Set<Id>{ a.Id });
        Test.stopTest();

        System.assertEquals(1, primeira.alteradas, 'a primeira corrida enche os campos vazios');
        System.assertEquals(0, segunda.alteradas,
            'a segunda não grava nada: a escrita é única, não é uma conta eternamente alterada');
    }

    @isTest static void mae_sem_negocio_no_grupo_tambem_fica_a_zero() {
        // O mesmo caso na fase de grupo. Uma mãe com filhas, todas sem negócio, tem de ficar com
        // os campos de grupo a zero e não vazios.
        Account mae = new Account(Name = 'T G mãe sem negócio');
        insert mae;
        insert new Account(Name = 'T G filha sem negócio', ParentId = mae.Id);

        Test.startTest();
        SC_SegmentoCalculo.Contagem c = SC_SegmentoCalculo.recalcularGrupo(new Set<Id>{ mae.Id });
        Test.stopTest();

        Account r = [SELECT Total_Grupo_12M__c, Margem_Grupo_12M__c, Total_Grupo__c,
                            Segmento_Grupo__c FROM Account WHERE Id = :mae.Id];
        System.assertEquals(0, r.Total_Grupo_12M__c, 'grupo a zero e não vazio');
        System.assertEquals(0, r.Margem_Grupo_12M__c, 'e a margem de grupo também');
        System.assertEquals(null, r.Segmento_Grupo__c, 'sem segmento de grupo, coerente com o individual');
        System.assertEquals(1, c.alteradas);
    }

    @isTest static void conjunto_vazio_nao_faz_nada() {
        Test.startTest();
        SC_SegmentoCalculo.Contagem a = SC_SegmentoCalculo.recalcularIndividual(new Set<Id>());
        SC_SegmentoCalculo.Contagem b = SC_SegmentoCalculo.recalcularGrupo(null);
        Test.stopTest();
        System.assertEquals(0, a.avaliadas);
        System.assertEquals(0, b.avaliadas);
        System.assert(SC_SegmentoCalculo.maesAfectadas(null).isEmpty());
    }
}