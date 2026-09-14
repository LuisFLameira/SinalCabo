/**
 * Testes da fronteira entre o ecrã de carregamento e a importação do PNI.
 *
 * O que aqui se prova é o percurso completo de um ficheiro pequeno, pedaço a pedaço,
 * incluindo a fronteira entre pedaços, e as duas coisas que protegem a operação: a
 * permissão própria e a simulação que não grava.
 */
@IsTest
private class SC_PniCarregamentoControllerTest {

    private static final String CABECALHO =
        'Project ID;Status;Last Changed On;Célula;Tipo OT';

    private static String linhaDe(String chave, String estado, String data) {
        return chave + ';' + estado + ';' + data + ';YER-01;ORI-MRF';
    }

    private static String ficheiroDe(List<String> linhas) {
        return CABECALHO + '\n' + String.join(linhas, '\n') + '\n';
    }

    // ------------------------------------------------------------------
    // Permissão
    // ------------------------------------------------------------------

    @IsTest
    static void semPermissaoRecusaLogoAoAbrir() {
        Profile padrao = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User sem = new User(
            FirstName = 'Sem', LastName = 'Permissao', Alias = 'sempni',
            Email = 'sem.permissao@exemplo.invalido',
            Username = 'sem.pni.' + String.valueOf(Datetime.now().getTime())
                       + '@exemplo.invalido',
            ProfileId = padrao.Id, TimeZoneSidKey = 'Europe/Lisbon',
            LocaleSidKey = 'pt_PT', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US');
        insert sem;

        Boolean recusou = false;
        System.runAs(sem) {
            try {
                SC_PniCarregamentoController.iniciar('ficheiro.csv', true);
            } catch (Exception e) {
                recusou = true;
            }
        }
        System.assert(recusou, 'sem a permissão própria tem de recusar');
    }

    // ------------------------------------------------------------------
    // Abrir o lote
    // ------------------------------------------------------------------

    @IsTest
    static void aSimulacaoEOFicheiroAbremLotesDeTiposDiferentes() {
        Test.startTest();
        SC_PniCarregamentoController.Passagem ensaio =
            SC_PniCarregamentoController.iniciar('pni.csv', true);
        SC_PniCarregamentoController.Passagem real =
            SC_PniCarregamentoController.iniciar('pni.csv', false);
        Test.stopTest();

        Map<Id, Lote_Integracao__c> lotes = new Map<Id, Lote_Integracao__c>([
            SELECT Id, Tipo_Corrida__c, Interface__c, Estado__c
            FROM Lote_Integracao__c
        ]);
        System.assertEquals(SC_PniConfig.CORRIDA_SIMULACAO,
                            lotes.get(ensaio.loteId).Tipo_Corrida__c);
        System.assertEquals(SC_PniConfig.CORRIDA_FICHEIRO,
                            lotes.get(real.loteId).Tipo_Corrida__c);
        System.assertEquals(SC_PniConfig.INTERFACE_ENTRADA,
                            lotes.get(real.loteId).Interface__c,
                            'o lote tem de dizer que veio do ficheiro do PNI');
        System.assertEquals(SC_NosLote.ESTADO_EM_CURSO,
                            lotes.get(real.loteId).Estado__c);
    }

    // ------------------------------------------------------------------
    // Percurso completo
    // ------------------------------------------------------------------

    @IsTest
    static void percursoCompletoDeUmFicheiroPequeno() {
        String texto = ficheiroDe(new List<String>{
            linhaDe('CRQ_A', 'Concluído SP', '2026-09-01'),
            linhaDe('CRQ_B', 'Aguarda cadastro', '2026-09-02')
        });

        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('pni.csv', false);
        SC_PniCarregamentoController.Passagem p =
            SC_PniCarregamentoController.processar(
                inicio.loteId, texto, null, 1, true, false);
        SC_PniCarregamentoController.Passagem fim =
            SC_PniCarregamentoController.concluir(inicio.loteId);
        Test.stopTest();

        System.assertEquals(null, p.erro, 'o ficheiro é válido');
        System.assertEquals(2, p.criados, 'as duas ordens têm de nascer');
        System.assertEquals(2, fim.criados, 'e o lote tem de as contar');
        System.assertEquals(2, [SELECT COUNT() FROM WorkOrder]);

        Lote_Integracao__c lote = [
            SELECT Estado__c, Resultado__c, Duracao_ms__c, Registos_Lidos__c
            FROM Lote_Integracao__c WHERE Id = :inicio.loteId
        ];
        System.assertEquals(SC_NosLote.ESTADO_CONCLUIDO, lote.Estado__c);
        System.assertEquals('Sucesso', lote.Resultado__c);
        System.assertNotEquals(null, lote.Duracao_ms__c,
                               'a duração tem de ficar medida');
    }

    @IsTest
    static void aSimulacaoNaoGravaNenhumaOrdem() {
        String texto = ficheiroDe(new List<String>{
            linhaDe('CRQ_A', 'Concluído SP', '2026-09-01')
        });
        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('pni.csv', true);
        SC_PniCarregamentoController.Passagem p =
            SC_PniCarregamentoController.processar(
                inicio.loteId, texto, null, 1, true, true);
        Test.stopTest();
        System.assertEquals(1, p.criados, 'tem de dizer quantas nasceriam');
        System.assertEquals(0, [SELECT COUNT() FROM WorkOrder],
                            'e não pode gravar nenhuma');
    }

    // ------------------------------------------------------------------
    // Fronteira entre pedaços
    // ------------------------------------------------------------------

    @IsTest
    static void aCaudaDeUmPedacoEntraNoSeguinte() {
        String pedaco1 = CABECALHO + '\n'
            + linhaDe('CRQ_A', 'Concluído SP', '2026-09-01') + '\n'
            + 'CRQ_B;Aguarda cadastro;2026-09-02;YER';

        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('pni.csv', false);
        SC_PniCarregamentoController.Passagem p1 =
            SC_PniCarregamentoController.processar(
                inicio.loteId, pedaco1, null, 1, false, false);
        System.assertEquals(1, p1.criados, 'só a primeira linha está completa');
        System.assertNotEquals('', p1.cauda, 'o resto tem de vir na cauda');

        SC_PniCarregamentoController.Passagem p2 =
            SC_PniCarregamentoController.processar(
                inicio.loteId, p1.cauda + '-02;ORI-MRF\n', p1.colunas, 3, true, false);
        Test.stopTest();

        System.assertEquals(1, p2.criados, 'a linha reconstruída tem de entrar');
        System.assertEquals(2, [SELECT COUNT() FROM WorkOrder],
                            'nenhuma linha se pode perder na fronteira');
    }

    // ------------------------------------------------------------------
    // Erros
    // ------------------------------------------------------------------

    @IsTest
    static void cabecalhoErradoFazOLoteFalhar() {
        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('outro.csv', false);
        SC_PniCarregamentoController.Passagem p =
            SC_PniCarregamentoController.processar(
                inicio.loteId, 'Coluna A;Coluna B\n1;2\n', null, 1, true, false);
        Test.stopTest();

        System.assertNotEquals(null, p.erro, 'tem de dizer o que está mal');
        System.assertEquals(0, [SELECT COUNT() FROM WorkOrder],
                            'e não pode gravar nada');
        Lote_Integracao__c lote = [
            SELECT Estado__c, Erro__c FROM Lote_Integracao__c WHERE Id = :inicio.loteId
        ];
        System.assertEquals(SC_NosLote.ESTADO_FALHADO, lote.Estado__c);
        System.assertNotEquals(null, lote.Erro__c, 'o motivo fica no lote');
    }

    @IsTest
    static void linhaRejeitadaViraOcorrenciaReprocessavel() {
        String texto = CABECALHO + '\n'
            + linhaDe('CRQ_A', 'Concluído SP', '2026-09-01') + '\n'
            + 'CRQ_B;só dois campos\n';

        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('pni.csv', false);
        SC_PniCarregamentoController.processar(
            inicio.loteId, texto, null, 1, true, false);
        SC_PniCarregamentoController.concluir(inicio.loteId);
        Test.stopTest();

        List<Ocorrencia_Integracao__c> ocorrencias = [
            SELECT Tipo__c, Mensagem__c, Conteudo__c, Reprocessavel__c
            FROM Ocorrencia_Integracao__c WHERE Lote__c = :inicio.loteId
        ];
        System.assertEquals(1, ocorrencias.size(),
                            'a linha má tem de deixar uma ocorrência');
        System.assertEquals(SC_NosLote.TIPO_REJEICAO, ocorrencias[0].Tipo__c);
        System.assertEquals(true, ocorrencias[0].Reprocessavel__c,
                            'para poder ser corrigida e tentada outra vez');
        System.assert(ocorrencias[0].Conteudo__c.contains('só dois campos'),
                      'a linha original tem de ficar guardada');

        Lote_Integracao__c lote = [
            SELECT Estado__c, Rejeitados__c FROM Lote_Integracao__c
            WHERE Id = :inicio.loteId
        ];
        System.assertEquals(SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS, lote.Estado__c,
                            'com rejeições o lote fecha como concluído com erros');
        System.assertEquals(1, lote.Rejeitados__c);
    }

    // ------------------------------------------------------------------
    // Acompanhar
    // ------------------------------------------------------------------

    @IsTest
    static void oEcraConsegueIrBuscarOLoteParaMostrarOProgresso() {
        Test.startTest();
        SC_PniCarregamentoController.Passagem inicio =
            SC_PniCarregamentoController.iniciar('pni.csv', false);
        Lote_Integracao__c lote = SC_PniCarregamentoController.lote(inicio.loteId);
        Test.stopTest();
        System.assertEquals(inicio.loteId, lote.Id);
        System.assertEquals(SC_NosLote.ESTADO_EM_CURSO, lote.Estado__c);
    }
}