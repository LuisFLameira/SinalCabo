/**
 * Testes da escrita das ordens a partir do ficheiro do PNI.
 *
 * O que aqui se prova são as regras que tornam a importação segura: não regredir o
 * que a ligação à NOS escreveu, não reescrever o que não mudou, não deixar uma linha
 * má levar as boas atrás, e não fundir duas ordens que só diferem no sufixo.
 */
@IsTest
private class SC_PniUpsertServiceTest {

    private static final Date CORTE = Date.newInstance(2026, 1, 1);

    private static SC_PniLinha linha(String chave, String estado, String data) {
        SC_PniLinha l = new SC_PniLinha(1, chave + ';' + estado + ';' + data);
        l.valores.put(SC_PniLinha.COL_CHAVE, chave);
        l.valores.put(SC_PniLinha.COL_ESTADO, estado);
        l.valores.put(SC_PniLinha.COL_ALTERACAO, data);
        l.valores.put(SC_PniLinha.COL_CELULA, 'YER-01');
        l.valores.put(SC_PniLinha.COL_TIPO, 'ORI-MRF');
        return l;
    }

    private static SC_PniUpsertService servico(Boolean simulacao) {
        return new SC_PniUpsertService(null, simulacao, CORTE);
    }

    private static WorkOrder ordemExistente(String chave, String estadoPni) {
        WorkOrder o = new WorkOrder(
            Referencia_Ordem_Cliente__c = chave,
            Status = 'In Progress',
            Estado_Cliente__c = 'WORK_IN_PROGRESS',
            Estado_Aceitacao_Cliente__c = estadoPni,
            Assinatura_Origem__c = 'assinatura-da-nos'
        );
        insert o;
        return o;
    }

    // ------------------------------------------------------------------
    // Criar
    // ------------------------------------------------------------------

    @IsTest
    static void linhaSemParCriaOrdemMarcadaComAOrigem() {
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ000003228630', 'Concluído SP', '2026-09-01')
        });
        Test.stopTest();
        System.assertEquals(1, r.criados, 'devia criar a ordem');
        System.assertEquals(0, r.rejeitados);

        WorkOrder o = [
            SELECT Status, Estado_Aceitacao_Cliente__c, Origem_Registo__c,
                   Data_Alteracao_PNI__c, Assinatura_PNI__c, Subject
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'CRQ000003228630'
        ];
        System.assertEquals('Concluído SP', o.Estado_Aceitacao_Cliente__c);
        System.assertEquals(SC_PniConfig.ORIGEM_PNI, o.Origem_Registo__c,
                            'tem de ficar marcada como vinda do ficheiro');
        System.assertEquals(Date.newInstance(2026, 9, 1), o.Data_Alteracao_PNI__c);
        System.assertEquals('New', o.Status, 'nasce por fazer');
        System.assertNotEquals(null, o.Assinatura_PNI__c);
    }

    @IsTest
    static void duasOrdensDaMesmaObraNaoSeFundem() {
        // Medido: tirar o sufixo funde 1.155 chaves distintas. Este teste falha se
        // alguém decidir normalizar a chave.
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('250894029_AIR', 'Concluído SP', '2026-09-01'),
            linha('250894029_AIR_TAB', 'Aguarda cadastro', '2026-09-01')
        });
        Test.stopTest();
        System.assertEquals(2, r.criados, 'são duas ordens e não uma');
        System.assertEquals(2, [
            SELECT COUNT() FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c LIKE '250894029%'
        ]);
    }

    // ------------------------------------------------------------------
    // Actualizar sem regredir
    // ------------------------------------------------------------------

    @IsTest
    static void oFicheiroGanhaNoEstadoDoPniENaoTocaNoRestante() {
        WorkOrder antes = ordemExistente('CRQ1', 'Aguarda cadastro');
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ1', 'Cadastro Enviado SP', '2026-09-02')
        });
        Test.stopTest();
        System.assertEquals(1, r.actualizados);
        System.assertEquals(1, r.divergentes,
                            'a divergência face ao que lá estava tem de ser contada');

        WorkOrder depois = [
            SELECT Status, Estado_Cliente__c, Estado_Aceitacao_Cliente__c,
                   Assinatura_Origem__c, Origem_Registo__c
            FROM WorkOrder WHERE Id = :antes.Id
        ];
        System.assertEquals('Cadastro Enviado SP', depois.Estado_Aceitacao_Cliente__c,
                            'o estado do PNI é do ficheiro e ele ganha');
        System.assertEquals('In Progress', depois.Status,
                            'o estado do trabalho é do Field Service e não se toca');
        System.assertEquals('WORK_IN_PROGRESS', depois.Estado_Cliente__c,
                            'o estado do NetGuard é da ligação e não se toca');
        System.assertEquals('assinatura-da-nos', depois.Assinatura_Origem__c,
                            'a assinatura da NOS não pode ser reescrita pelo PNI');
    }

    @IsTest
    static void segundaImportacaoIgualNaoEscreveNada() {
        SC_PniLinha l = linha('CRQ1', 'Concluído SP', '2026-09-01');
        servico(false).tratar(new List<SC_PniLinha>{ l });

        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ1', 'Concluído SP', '2026-09-01')
        });
        Test.stopTest();
        System.assertEquals(0, r.criados, 'já existe');
        System.assertEquals(0, r.actualizados, 'e nada mudou');
        System.assertEquals(1, r.inalterados,
                            'a assinatura igual tem de saltar a escrita');
    }

    @IsTest
    static void repetidosNoMesmoPedacoColapsamEVenceOUltimo() {
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ1', 'Aguarda cadastro', '2026-09-01'),
            linha('CRQ1', 'Cadastro Enviado SP', '2026-09-02')
        });
        Test.stopTest();
        System.assertEquals(1, r.criados, 'é uma ordem só');
        WorkOrder o = [
            SELECT Estado_Aceitacao_Cliente__c FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c = 'CRQ1'
        ];
        System.assertEquals('Cadastro Enviado SP', o.Estado_Aceitacao_Cliente__c,
                            'vence a última linha do ficheiro');
    }

    // ------------------------------------------------------------------
    // Data de corte
    // ------------------------------------------------------------------

    @IsTest
    static void linhaAnteriorAoCorteNaoEntra() {
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ_VELHA', 'Concluído SP', '2025-06-30'),
            linha('CRQ_NOVA', 'Concluído SP', '2026-06-30')
        });
        Test.stopTest();
        System.assertEquals(1, r.criados, 'só a de 2026 entra');
        System.assertEquals(1, r.forasDeJanela, 'a de 2025 fica de fora e conta-se');
        System.assertEquals(0, [
            SELECT COUNT() FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c = 'CRQ_VELHA'
        ]);
    }

    @IsTest
    static void linhaComDataDe1970NaoEntra() {
        // São 4.997 linhas no ficheiro real: 1970 é nulo disfarçado e não uma data.
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ_SEM_DATA', 'Concluído SP', '1970-01-01')
        });
        Test.stopTest();
        System.assertEquals(0, r.criados);
        System.assertEquals(1, r.forasDeJanela,
                            'sem data de alteração não se sabe se é recente');
    }

    // ------------------------------------------------------------------
    // Simulação
    // ------------------------------------------------------------------

    @IsTest
    static void simulacaoContaMasNaoGrava() {
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(true).tratar(new List<SC_PniLinha>{
            linha('CRQ1', 'Concluído SP', '2026-09-01'),
            linha('CRQ2', 'Aguarda cadastro', '2026-09-01')
        });
        Test.stopTest();
        System.assertEquals(2, r.criados, 'tem de dizer quantas nasceriam');
        System.assertEquals(0, [SELECT COUNT() FROM WorkOrder],
                            'e não pode gravar nenhuma');
    }

    @IsTest
    static void simulacaoEImportacaoDaoOsMesmosNumeros() {
        List<SC_PniLinha> linhas = new List<SC_PniLinha>{
            linha('CRQ1', 'Concluído SP', '2026-09-01'),
            linha('CRQ2', 'Aguarda cadastro', '2026-09-01'),
            linha('CRQ_VELHA', 'Concluído SP', '2025-01-01')
        };
        SC_PniUpsertService.Resultado ensaio = servico(true).tratar(linhas);
        Test.startTest();
        SC_PniUpsertService.Resultado real = servico(false).tratar(linhas);
        Test.stopTest();
        System.assertEquals(ensaio.criados, real.criados,
                            'a simulação tem de prever as criações ao certo');
        System.assertEquals(ensaio.actualizados, real.actualizados);
        System.assertEquals(ensaio.forasDeJanela, real.forasDeJanela);
    }

    // ------------------------------------------------------------------
    // Erros
    // ------------------------------------------------------------------

    @IsTest
    static void linhaMaNaoLevaAsBoasAtras() {
        // Uma chave acima dos 50 caracteres do campo faz a gravação dessa linha falhar.
        SC_PniLinha ma = linha('X'.repeat(60), 'Concluído SP', '2026-09-01');
        Test.startTest();
        SC_PniUpsertService.Resultado r = servico(false).tratar(new List<SC_PniLinha>{
            linha('CRQ1', 'Concluído SP', '2026-09-01'),
            ma,
            linha('CRQ2', 'Concluído SP', '2026-09-01')
        });
        Test.stopTest();
        System.assertEquals(2, r.criados, 'as duas boas têm de entrar');
        System.assertEquals(1, r.rejeitados, 'e a má tem de ser contada');
        System.assertEquals(1, r.rejeicoes.size(),
                            'com a rejeição guardada para reprocessar');
        System.assertNotEquals(null, r.rejeicoes[0].motivo);
        System.assertNotEquals(null, r.rejeicoes[0].bruto,
                               'a linha original tem de ficar guardada');
    }

    @IsTest
    static void listaVaziaNaoFazNada() {
        SC_PniUpsertService.Resultado r = servico(false).tratar(
            new List<SC_PniLinha>());
        System.assertEquals(0, r.lidos);
        System.assertEquals(0, r.criados);
        SC_PniUpsertService.Resultado n = servico(false).tratar(null);
        System.assertEquals(0, n.lidos);
    }

    @IsTest
    static void contadoresSomamEntrePedacos() {
        SC_PniUpsertService.Resultado a = new SC_PniUpsertService.Resultado();
        a.criados = 2;
        a.rejeitados = 1;
        a.rejeicoes.add(new SC_PniCsv.Rejeicao(1, 'CRQ1', 'motivo', 'bruto'));
        SC_PniUpsertService.Resultado b = new SC_PniUpsertService.Resultado();
        b.criados = 3;
        b.inalterados = 4;
        a.juntar(b);
        System.assertEquals(5, a.criados, 'os pedaços somam-se no mesmo lote');
        System.assertEquals(4, a.inalterados);
        System.assertEquals(1, a.rejeicoes.size());
    }
}