/**
 * Testes da leitura do JSON e do objecto SC_NosTarefa que ela produz, incluindo a
 * assinatura que decide se uma segunda leitura escreve ou não escreve.
 */
@IsTest
private class SC_NosParserTest {
    @IsTest
    static void listagemRealTrazAsCinquentaESeisTarefas() {
        List<SC_NosTarefa> tarefas = SC_NosParser.listagem(SC_NosTestDados.fixture('SC_NosFx_ListaOk'));

        Assert.areEqual(56, tarefas.size(), 'O fixture da listagem tem 56 tarefas.');
        SC_NosTarefa primeira = tarefas[0];
        Assert.areEqual('TAS000002533674', primeira.id, 'O identificador é o ID completo da NOS.');
        Assert.areEqual('INC000187369122', primeira.referenciaOcorrencia, 'A ocorrência pai é o ReferenceID.');
        Assert.areEqual('CLOSED', primeira.estado, 'O estado vem em maiúsculas.');
        Assert.areEqual('OTI-RA2', primeira.tipoPedido, 'O tipo de pedido é o código da OT.');
        Assert.areEqual('TS2-Sinalcabo', primeira.grupo, 'O grupo é o código do território na NOS.');
        Assert.areEqual('Medium', primeira.prioridade, 'A prioridade vem como a NOS a escreve.');
        Assert.areEqual('U9351539', primeira.utilizador, 'O técnico indicado vem no AssignedUser.');
        Assert.areEqual('SPGLOBAL', primeira.contrato, 'O contrato vem no ServiceContract.');
        Assert.isFalse(primeira.veioDoDetalhe, 'Uma tarefa de listagem não vem do detalhe.');
        Assert.isTrue(primeira.estaFechada(), 'CLOSED é uma tarefa fechada na NOS.');
    }

    @IsTest
    static void datasComOffsetEComZuluDaoOMesmoInstante() {
        Datetime comOffset = SC_NosParser.paraGmt('2026-08-04T08:09:09+01:00');
        Datetime comZulu = SC_NosParser.paraGmt('2026-08-04T07:09:09Z');
        Datetime semFuso = SC_NosParser.paraGmt('2026-08-04T07:09:09');

        Assert.areEqual(comZulu, comOffset, 'A mesma hora escrita das duas maneiras dá o mesmo instante.');
        Assert.areEqual(comZulu, semFuso, 'Sem fuso, lê-se como GMT.');
        Assert.areEqual(
            '2026-08-04 07:09:09', comOffset.formatGmt('yyyy-MM-dd HH:mm:ss'),
            'A conversão para GMT tira a hora de Verão de Portugal.'
        );
    }

    @IsTest
    static void offsetNegativoEMilissegundosTambemSaoLidos() {
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 8, 4, 12, 0, 0),
            SC_NosParser.paraGmt('2026-08-04T09:00:00-03:00'),
            'Um offset negativo soma horas ao GMT.'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 8, 4, 7, 9, 9),
            SC_NosParser.paraGmt('2026-08-04T07:09:09.123Z'),
            'Milissegundos não impedem a leitura.'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 8, 4, 7, 9, 9),
            SC_NosParser.paraGmt('2026-08-04 07:09:09'),
            'A separação por espaço também é aceite.'
        );
    }

    @IsTest
    static void dataQueNaoSeLeFicaVaziaEmVezDeRebentar() {
        Assert.isNull(SC_NosParser.paraGmt(null), 'Nulo devolve nulo.');
        Assert.isNull(SC_NosParser.paraGmt(''), 'Vazio devolve nulo.');
        Assert.isNull(SC_NosParser.paraGmt('04/08/2026'), 'Um formato desconhecido devolve nulo.');
        Assert.isNull(SC_NosParser.paraGmt('2026-13-45T99:99:99Z'), 'Uma data impossível devolve nulo.');
    }

    @IsTest
    static void estadoClosedEmMinusculasEhNormalizado() {
        Assert.areEqual('CLOSED', SC_NosParser.estadoNormalizado('Closed'), 'Closed e CLOSED são o mesmo estado.');
        Assert.areEqual('PENDING', SC_NosParser.estadoNormalizado(' pending '), 'Os espaços à volta desaparecem.');
        Assert.isNull(SC_NosParser.estadoNormalizado('  '), 'Um estado em branco fica nulo.');
    }

    @IsTest
    static void listagemMistaTrazOsCasosLimite() {
        List<SC_NosTarefa> tarefas = SC_NosParser.listagem(SC_NosTestDados.fixture('SC_NosFx_ListaMista'));

        Assert.areEqual(12, tarefas.size(), 'A mista tem 12 linhas, duas delas com o mesmo identificador.');
        Assert.areEqual('TAS000002533674', tarefas[0].id, 'A primeira e a segunda repetem o identificador.');
        Assert.areEqual('TAS000002533674', tarefas[1].id, 'A segunda repete o identificador da primeira.');
        Assert.areEqual('ASSIGNED_TO_COMPANY', tarefas[0].estado, 'A primeira linha ainda está atribuída à empresa.');
        Assert.areEqual('CLOSED', tarefas[1].estado, 'A segunda linha traz Closed e normaliza para CLOSED.');
        Assert.isNull(tarefas[0].dataFim, 'A primeira linha não traz EndDate.');
        Assert.areEqual(
            tarefas[0].dataAtribuicao, tarefas[1].dataAtribuicao,
            'A mesma atribuição escrita em +01:00 e em Z dá o mesmo instante.'
        );
        Assert.isNull(tarefas[7].utilizador, 'Uma das linhas não traz técnico indicado.');
        Assert.areEqual('Critical', tarefas[8].prioridade, 'A prioridade Critical é lida como vem.');
    }

    @IsTest
    static void detalheTrazNotasElementosDeRedeEInteraccoes() {
        SC_NosTarefa tarefa = SC_NosParser.detalhe(SC_NosTestDados.fixture('SC_NosFx_DetalheOk'));

        Assert.isNotNull(tarefa, 'O detalhe tem de produzir uma tarefa.');
        Assert.isTrue(tarefa.veioDoDetalhe, 'A tarefa sabe que veio do detalhe.');
        Assert.areEqual('TAS000002537686', tarefa.id, 'O identificador vem no data.');
        Assert.areEqual(2, tarefa.elementosRede.size(), 'O detalhe traz dois elementos de rede.');
        Assert.areEqual('CAI04-2C1', tarefa.elementosRede[0], 'O primeiro elemento é o mais específico.');
        Assert.areEqual(2, tarefa.interaccoes.size(), 'O detalhe traz duas interacções.');
        Assert.areEqual('General Information', tarefa.interaccoes[0].tipo, 'O tipo da interacção é lido.');
        Assert.isNotNull(tarefa.interaccoes[0].criadaEm, 'A data da interacção é lida.');
        Assert.isTrue(tarefa.notas.contains('<div>'), 'As notas chegam em HTML e é o mapeador que as limpa.');
    }

    @IsTest
    static void detalheDeOrdemInexistenteNaoProduzTarefa() {
        Assert.isNull(
            SC_NosParser.detalhe(SC_NosTestDados.fixture('SC_NosFx_Detalhe701')),
            'Um 701 não traz data nenhum e não produz tarefa.'
        );
    }

    @IsTest
    static void corposInvalidosDaoListaVaziaEmVezDeExcepcao() {
        Assert.areEqual(0, SC_NosParser.listagem(null).size(), 'Nulo dá lista vazia.');
        Assert.areEqual(0, SC_NosParser.listagem('não é json').size(), 'Texto solto dá lista vazia.');
        Assert.areEqual(0, SC_NosParser.listagem('[1,2,3]').size(), 'Uma raiz que não é objecto dá lista vazia.');
        Assert.areEqual(0, SC_NosParser.listagem('{"result_data":"nada"}').size(), 'Um result_data que não é objecto dá lista vazia.');
        Assert.areEqual(0, SC_NosParser.listagem(SC_NosTestDados.listagem('{"Status":"PENDING"}')).size(),
            'Uma linha sem identificador não conta.');
        Assert.isNull(SC_NosParser.detalhe('{"result_data":{"data":[]}}'), 'Um detalhe com lista vazia não produz tarefa.');
    }

    @IsTest
    static void listagemComDataObjectoEhAceite() {
        List<SC_NosTarefa> tarefas = SC_NosParser.listagem(
            '{"result_code":0,"result_data":{"data":{"ID":"TAS1","Status":"PENDING"}}}'
        );

        Assert.areEqual(1, tarefas.size(), 'Um data que é objecto conta como uma tarefa.');
        Assert.areEqual('TAS1', tarefas[0].id, 'O identificador é lido na mesma.');
    }

    @IsTest
    static void detalheComDataEmListaTambemEhAceite() {
        SC_NosTarefa tarefa = SC_NosParser.detalhe(
            '{"result_code":200,"result_data":{"data":[{"ID":"TAS2","NetworkElements":["ABD01"]}]}}'
        );

        Assert.areEqual('TAS2', tarefa.id, 'O detalhe lê a primeira linha da lista.');
        Assert.areEqual('ABD01', tarefa.elementosRede[0], 'Um elemento de rede em texto simples também é lido.');
    }

    @IsTest
    static void assinaturaIgnoraOFormatoDaDataEMudaComOEstado() {
        String linhaComOffset = '{"ID":"TAS9","Status":"PENDING","AssignedDate":"2026-08-04T08:09:09+01:00"}';
        String linhaComZulu = '{"ID":"TAS9","Status":"PENDING","AssignedDate":"2026-08-04T07:09:09Z"}';
        String linhaOutroEstado = '{"ID":"TAS9","Status":"CLOSED","AssignedDate":"2026-08-04T07:09:09Z"}';

        String comOffset = SC_NosParser.listagem(SC_NosTestDados.listagem(linhaComOffset))[0].assinatura();
        String comZulu = SC_NosParser.listagem(SC_NosTestDados.listagem(linhaComZulu))[0].assinatura();
        String outroEstado = SC_NosParser.listagem(SC_NosTestDados.listagem(linhaOutroEstado))[0].assinatura();

        Assert.areEqual(comZulu, comOffset, 'A mesma tarefa escrita de duas maneiras tem de dar a mesma assinatura.');
        Assert.areNotEqual(comZulu, outroEstado, 'Um estado diferente tem de dar assinatura diferente.');
        Assert.areEqual(64, comZulu.length(), 'A assinatura é um SHA-256 em hexadecimal, com 64 caracteres.');
    }

    @IsTest
    static void assinaturaEhIgualNaListagemENoDetalhe() {
        String cabecalho = '"ID":"TAS9","Status":"PENDING","Summary":"OTI-RA2 ABD01 sem sinal","RequestType":"OTI-RA2"';
        SC_NosTarefa daListagem = SC_NosParser.listagem(SC_NosTestDados.listagem('{' + cabecalho + '}'))[0];
        SC_NosTarefa doDetalhe = SC_NosParser.detalhe(
            '{"result_code":200,"result_data":{"data":{' + cabecalho + ',"Notes":"<div>algo</div>"}}}'
        );

        Assert.areEqual(
            daListagem.assinatura(), doDetalhe.assinatura(),
            'A assinatura cobre só o cabeçalho, para o detalhe não parecer uma alteração.'
        );
    }

    @IsTest
    static void notasEmHtmlViramTextoLegivel() {
        String limpo = SC_NosParser.textoSemHtml('<div>Linha um</div><div>Linha &amp; dois</div><br><div>Tr&ecirc;s</div>');

        Assert.isTrue(limpo.contains('Linha um'), 'O texto dentro das etiquetas mantém-se: ' + limpo);
        Assert.isTrue(limpo.contains('Linha & dois'), 'As entidades voltam a caracteres: ' + limpo);
        Assert.isTrue(limpo.contains('Três'), 'As entidades acentuadas também: ' + limpo);
        Assert.isFalse(limpo.contains('<'), 'Não pode sobrar HTML: ' + limpo);
        Assert.isFalse(limpo.contains('\n\n\n'), 'Não podem sobrar linhas vazias em cadeia: ' + limpo);
        Assert.areEqual('', SC_NosParser.textoSemHtml(null), 'Nulo dá texto vazio.');
    }

    @IsTest
    static void oCarimboDoEnvelopeDizQuandoANosRespondeu() {
        Datetime lida = SC_NosParser.instanteDoEnvelope(SC_NosTestDados.fixture('SC_NosFx_ListaOk'));

        Assert.areEqual(
            Datetime.newInstance(1788464573635L), lida,
            'O carimbo do envelope é a data de leitura de um corpo guardado.'
        );
        Assert.isNull(SC_NosParser.instanteDoEnvelope(null), 'Sem corpo não há carimbo.');
        Assert.isNull(SC_NosParser.instanteDoEnvelope('nem sequer é JSON'), 'Lixo não dá data.');
        Assert.isNull(SC_NosParser.instanteDoEnvelope('[1,2]'), 'Um envelope que não é objecto também não.');
        Assert.isNull(SC_NosParser.instanteDoEnvelope('{"result_code":0}'), 'Um envelope sem carimbo dá nulo.');
        Assert.isNull(SC_NosParser.instanteDoEnvelope('{"timestamp":12345}'), 'E um carimbo fora de qualquer época.');
        Assert.areEqual(
            Datetime.newInstance(1788464573635L),
            SC_NosParser.instanteDoEnvelope('{"timestamp":"1788464573635"}'),
            'O carimbo em texto lê-se na mesma.'
        );
    }

    @IsTest
    static void entidadesEscapadasDuasVezesTambemVoltamATexto() {
        // A NOS manda &amp;#124; onde queria uma barra: uma passagem só deixava &#124;.
        Assert.areEqual('a|b', SC_NosParser.textoSemHtml('<div>a&amp;#124;b</div>'),
            'Uma entidade escapada duas vezes tem de chegar a texto legível.');
        Assert.areEqual('preço & custo', SC_NosParser.textoSemHtml('pre&ccedil;o &amp; custo'),
            'Sem entidades numéricas, uma passagem só chega e o & fica como está.');
    }
}