/**
 * Testes do leitor e do saneador do ficheiro do PNI.
 *
 * Os casos de sujidade não são inventados: saem da medição feita sobre o ficheiro
 * que o cliente enviou a 04/09/2026, com 22.078 linhas. Cada teste diz quantas
 * linhas do ficheiro real dependem dele.
 *
 * Nenhum teste lê um ficheiro do cliente. O que se prova é o comportamento do
 * leitor, e os dados são construídos aqui.
 */
@IsTest
private class SC_PniCsvTest {

    private static final String CABECALHO =
        'Project ID;Status;Last Changed On;Célula;Tipo OT;Orçamento;Descrição';

    private static String linha(String chave, String estado, String data,
                                String celula, String tipo, String valor, String descricao) {
        return String.join(new List<String>{chave, estado, data, celula, tipo,
                                            valor, descricao}, ';');
    }

    private static String ficheiro(List<String> linhas) {
        String texto = CABECALHO;
        for (String l : linhas) {
            texto += '\n' + l;
        }
        return texto + '\n';
    }

    // ------------------------------------------------------------------
    // Cabeçalho
    // ------------------------------------------------------------------

    @IsTest
    static void cabecalhoSemAColunaDaChaveNaoLeNada() {
        String texto = 'Status;Last Changed On\nConcluído;2026-09-01\n';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assert(!r.valido(), 'devia recusar o ficheiro');
        System.assert(r.erroCabecalho.contains('Project ID'),
                      'a mensagem tem de dizer que coluna falta: ' + r.erroCabecalho);
        System.assertEquals(0, r.linhas.size(), 'não pode ler linha nenhuma');
    }

    @IsTest
    static void cabecalhoSemAColunaDaDataNaoLeNada() {
        String texto = 'Project ID;Status\nCRQ1;Concluído\n';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assert(!r.valido(), 'devia recusar');
        System.assert(r.erroCabecalho.contains('Last Changed On'), r.erroCabecalho);
    }

    @IsTest
    static void ficheiroVazioRecusa() {
        SC_PniCsv.Resultado r = SC_PniCsv.ler('', null, 1, true);
        System.assert(!r.valido(), 'ficheiro vazio tem de ser recusado');
    }

    @IsTest
    static void cabecalhoValidoLeAsLinhas() {
        String texto = ficheiro(new List<String>{
            linha('CRQ000003228630', 'Concluído (Remunerado)', '2026-09-01',
                  'YER-01', 'ORI-MRF', 'EUR 286.75', 'obra'),
            linha('TAS000001999999', 'Aguarda cadastro', '2026-08-30',
                  'LRS-04', 'OTI-RA2', '', 'avaria')
        });
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assert(r.valido(), r.erroCabecalho);
        System.assertEquals(2, r.linhas.size(), 'devia ler as duas linhas');
        System.assertEquals(0, r.rejeicoes.size(), 'nenhuma devia ser rejeitada');
        System.assertEquals('CRQ000003228630', r.linhas[0].chave());
        System.assertEquals('Concluído (Remunerado)', r.linhas[0].estado());
    }

    // ------------------------------------------------------------------
    // Sujidade medida no ficheiro real
    // ------------------------------------------------------------------

    @IsTest
    static void dataDe1970FicaNula() {
        // 4.997 linhas do ficheiro real trazem 1970-01-01 a fazer de nulo.
        System.assertEquals(null, SC_PniCsv.comoData('1970-01-01'),
                            '1970 é nulo disfarçado e não uma data');
        System.assertEquals(null, SC_PniCsv.comoData('1970-01-01 00:00:00'));
        System.assertEquals(Date.newInstance(2026, 9, 4),
                            SC_PniCsv.comoData('2026-09-04'),
                            'uma data a sério tem de passar');
        System.assertEquals(Date.newInstance(2022, 6, 30),
                            SC_PniCsv.comoData('2022-06-30 08:57:15'),
                            'com hora atrás, fica só a data');
    }

    @IsTest
    static void literaisDeVazioFicamNulos() {
        // 'null' aparece 717 vezes e 'N/A' 6.989 vezes no ficheiro real.
        System.assertEquals(null, SC_PniCsv.limpar('null'));
        System.assertEquals(null, SC_PniCsv.limpar('NULL'));
        System.assertEquals(null, SC_PniCsv.limpar('N/A'));
        System.assertEquals(null, SC_PniCsv.limpar('  '));
        System.assertEquals(null, SC_PniCsv.limpar(null));
        System.assertEquals('YER-01', SC_PniCsv.limpar('  YER-01 '),
                            'um valor a sério só perde os espaços');
    }

    @IsTest
    static void valorEmTextoViraNumero() {
        // O orçamento vem como "EUR 286.75" em 10.558 linhas.
        System.assertEquals(286.75, SC_PniCsv.comoValor('EUR 286.75'));
        System.assertEquals(286.75, SC_PniCsv.comoValor('286,75'));
        System.assertEquals(null, SC_PniCsv.comoValor('sem valor'));
        System.assertEquals(null, SC_PniCsv.comoValor('N/A'));
    }

    @IsTest
    static void textoLongoNaoRebenta() {
        // Três colunas de observações vêm cortadas nos 255 pelo Access.
        String longo = 'a'.repeat(300);
        System.assertEquals(255, SC_PniCsv.ate(longo, 255).length());
        System.assertEquals('abc', SC_PniCsv.ate('abc', 255),
                            'o que já cabe fica igual');
        System.assertEquals(null, SC_PniCsv.ate('  ', 255));
    }

    // ------------------------------------------------------------------
    // Aspas e separadores dentro do texto
    // ------------------------------------------------------------------

    @IsTest
    static void pontoEVirgulaDentroDeAspasNaoParteALinha() {
        // 37 descrições do ficheiro real trazem ponto e vírgula.
        String texto = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;'
            + '"obra com ; ponto e vírgula"\n';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(1, r.linhas.size(), 'devia ler uma linha só');
        System.assertEquals(0, r.rejeicoes.size(), 'e não rejeitar nada');
        System.assertEquals('obra com ; ponto e vírgula',
                            r.linhas[0].valor('Descrição'));
    }

    @IsTest
    static void aspasEscapadasFicamUmaSo() {
        String texto = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;'
            + '"ele disse ""sim"" ontem"\n';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(1, r.linhas.size());
        System.assertEquals('ele disse "sim" ontem', r.linhas[0].valor('Descrição'));
    }

    @IsTest
    static void mudancaDeLinhaDentroDeAspasNaoParteORegisto() {
        String texto = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;'
            + '"primeira\nsegunda"\n';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(1, r.linhas.size(), 'é um registo e não dois');
        System.assert(r.linhas[0].valor('Descrição').contains('segunda'),
                      'o texto das duas linhas tem de ficar inteiro');
    }

    // ------------------------------------------------------------------
    // Fronteira entre pedaços
    // ------------------------------------------------------------------

    @IsTest
    static void linhaCortadaAoMeioFicaNaCauda() {
        String pedaco1 = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;a'
            + '\nCRQ2;Aguarda cadastro;2026-09-02;YER-02;ORI';
        SC_PniCsv.Resultado r1 = SC_PniCsv.ler(pedaco1, null, 1, false);
        System.assertEquals(1, r1.linhas.size(), 'só a primeira linha está completa');
        System.assertEquals('CRQ2;Aguarda cadastro;2026-09-02;YER-02;ORI', r1.cauda,
                            'o resto tem de vir na cauda');

        SC_PniCsv.Resultado r2 = SC_PniCsv.ler(r1.cauda + '-MRF;;b\n', r1.colunas,
                                               2, true);
        System.assertEquals(1, r2.linhas.size(), 'a linha reconstruída tem de entrar');
        System.assertEquals('CRQ2', r2.linhas[0].chave());
        System.assertEquals('ORI-MRF', r2.linhas[0].tipoOrdem(),
                            'o campo cortado ao meio tem de ficar inteiro');
    }

    @IsTest
    static void aspasAbertasNaFronteiraSeguremARegisto() {
        String pedaco1 = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;'
            + '"texto que começa';
        SC_PniCsv.Resultado r1 = SC_PniCsv.ler(pedaco1, null, 1, false);
        System.assertEquals(0, r1.linhas.size(),
                            'com aspas abertas nada pode ser dado por completo');
        System.assert(r1.cauda.contains('texto que começa'), r1.cauda);
    }

    @IsTest
    static void ultimoPedacoNaoDeixaCauda() {
        String texto = CABECALHO + '\nCRQ1;Concluído SP;2026-09-01;YER-01;ORI-MRF;;a';
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(1, r.linhas.size(),
                            'no último pedaço a linha sem fim de linha ainda conta');
        System.assertEquals('', r.cauda);
    }

    // ------------------------------------------------------------------
    // Rejeições
    // ------------------------------------------------------------------

    @IsTest
    static void linhaComMenosCamposERejeitadaEAsBoasEntram() {
        String texto = ficheiro(new List<String>{
            linha('CRQ1', 'Concluído SP', '2026-09-01', 'YER-01', 'ORI-MRF', '', 'boa'),
            'CRQ2;só dois campos',
            linha('CRQ3', 'Aguarda cadastro', '2026-09-02', 'YER-03', 'ORI-MRF', '', 'boa')
        });
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(2, r.linhas.size(), 'as duas boas têm de entrar');
        System.assertEquals(1, r.rejeicoes.size(), 'e a má tem de ficar registada');
        System.assert(r.rejeicoes[0].motivo.contains('campos'), r.rejeicoes[0].motivo);
        System.assertEquals('CRQ2;só dois campos', r.rejeicoes[0].bruto,
                            'a linha original tem de ficar guardada');
    }

    @IsTest
    static void linhaSemChaveERejeitada() {
        String texto = ficheiro(new List<String>{
            linha('', 'Concluído SP', '2026-09-01', 'YER-01', 'ORI-MRF', '', 'sem chave')
        });
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(0, r.linhas.size());
        System.assertEquals(1, r.rejeicoes.size());
        System.assert(r.rejeicoes[0].motivo.contains('identificador'),
                      r.rejeicoes[0].motivo);
    }

    // ------------------------------------------------------------------
    // Assinatura
    // ------------------------------------------------------------------

    @IsTest
    static void assinaturaMudaSoQuandoOsDadosMudam() {
        String texto = ficheiro(new List<String>{
            linha('CRQ1', 'Concluído SP', '2026-09-01', 'YER-01', 'ORI-MRF', '', 'a')
        });
        SC_PniCsv.Resultado r1 = SC_PniCsv.ler(texto, null, 1, true);
        SC_PniCsv.Resultado r2 = SC_PniCsv.ler(texto, null, 1, true);
        System.assertEquals(r1.linhas[0].assinatura(), r2.linhas[0].assinatura(),
                            'o mesmo ficheiro dá a mesma assinatura');

        String outro = ficheiro(new List<String>{
            linha('CRQ1', 'Validação Técnica', '2026-09-01', 'YER-01', 'ORI-MRF', '', 'a')
        });
        SC_PniCsv.Resultado r3 = SC_PniCsv.ler(outro, null, 1, true);
        System.assertNotEquals(r1.linhas[0].assinatura(), r3.linhas[0].assinatura(),
                               'mudar o estado tem de mudar a assinatura');

        String soDescricao = ficheiro(new List<String>{
            linha('CRQ1', 'Concluído SP', '2026-09-01', 'YER-01', 'ORI-MRF', '', 'b')
        });
        SC_PniCsv.Resultado r4 = SC_PniCsv.ler(soDescricao, null, 1, true);
        System.assertEquals(r1.linhas[0].assinatura(), r4.linhas[0].assinatura(),
                            'mudar uma coluna que não vai à ordem não pode mexer nela');
    }

    // ------------------------------------------------------------------
    // Volume, para provar que um pedaço inteiro cabe na memória
    // ------------------------------------------------------------------

    @IsTest
    static void pedacoDeMeioMegabyteCabeNaMemoria() {
        List<String> linhas = new List<String>();
        for (Integer i = 0; i < 1000; i++) {
            linhas.add(linha('CRQ' + i, 'Concluído SP', '2026-09-01', 'YER-01',
                             'ORI-MRF', 'EUR 100.00',
                             'descrição com algum comprimento para pesar ' + i));
        }
        String texto = ficheiro(linhas);
        Integer antes = Limits.getHeapSize();
        Test.startTest();
        SC_PniCsv.Resultado r = SC_PniCsv.ler(texto, null, 1, true);
        Test.stopTest();
        System.assertEquals(1000, r.linhas.size(), 'as mil linhas têm de entrar');
        System.assert(Limits.getHeapSize() < Limits.getLimitHeapSize(),
                      'o pedaço tem de caber na memória da transacção');
        System.assert(Limits.getCpuTime() < Limits.getLimitCpuTime(),
                      'e no tempo de processamento');
        System.debug('memória usada: ' + (Limits.getHeapSize() - antes));
    }

    // ------------------------------------------------------------------
    // Configuração
    // ------------------------------------------------------------------

    @IsTest
    static void configuracaoLeODoMetadataQuandoNinguemASubstitui() {
        // Sem substituicao, tem de ir buscar o registo Ficheiro do PNI a org.
        Sistema_Cliente__mdt c = SC_PniConfig.config();
        System.assertNotEquals(null, c, 'a configuração nunca pode vir nula');
        System.assertEquals(SC_PniConfig.SISTEMA, c.DeveloperName);
    }

    @IsTest
    static void quemNaoTemAPermissaoNaoImporta() {
        // Corre como um utilizador acabado de criar, sem conjunto de permissoes
        // nenhum. Quem corre os testes e administrador e tem a permissao, por isso
        // sem o runAs este teste passaria por engano.
        Profile padrao = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User sem = new User(
            FirstName = 'Sem', LastName = 'Permissao',
            Alias = 'sempni', Email = 'sem.permissao@exemplo.invalido',
            Username = 'sem.permissao.' + String.valueOf(Datetime.now().getTime())
                       + '@exemplo.invalido',
            ProfileId = padrao.Id, TimeZoneSidKey = 'Europe/Lisbon',
            LocaleSidKey = 'pt_PT', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US');
        insert sem;
        System.runAs(sem) {
            System.assertEquals(false, SC_PniConfig.podeImportar(),
                                'sem a permissão a importação tem de recusar');
        }
    }

    @IsTest
    static void configuracaoTemValoresDeRecurso() {
        SC_PniConfig.definirConfig(new Sistema_Cliente__mdt(
            DeveloperName = SC_PniConfig.SISTEMA));
        System.assertEquals(SC_PniConfig.PEDACO_OMISSAO, SC_PniConfig.pedacoBytes(),
                            'sem valor no metadata vale o de recurso');
        System.assertEquals(false, SC_PniConfig.activo(),
                            'sem registo a importação não arranca');
        System.assertEquals(null, SC_PniConfig.dataCorte());

        SC_PniConfig.definirConfig(new Sistema_Cliente__mdt(
            DeveloperName = SC_PniConfig.SISTEMA, Activo__c = true,
            Data_Corte__c = Date.newInstance(2026, 1, 1), Pedaco_Bytes__c = 1024));
        System.assertEquals(true, SC_PniConfig.activo());
        System.assertEquals(1024, SC_PniConfig.pedacoBytes());
        System.assertEquals(Date.newInstance(2026, 1, 1), SC_PniConfig.dataCorte());
    }
}