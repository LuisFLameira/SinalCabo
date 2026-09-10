/**
 * Testes da proposta de célula: onde o código é encontrado, o que acontece quando há
 * vários, e as duas situações em que a proposta não pode sobrepor-se ao despacho.
 */
@IsTest
private class SC_NosCelulaExtractorTest {
    @IsTest
    static void codigoEncontraSeNoMeioDoTextoLivre() {
        Assert.areEqual(new List<String>{ 'ABD01' }, SC_NosCelulaExtractor.codigos('ABD01'), 'Código isolado.');
        Assert.areEqual(new List<String>{ 'CAI07' }, SC_NosCelulaExtractor.codigos('CAI07-1A3'), 'Código com sufixo de rede.');
        Assert.areEqual(new List<String>{ 'ALB06' }, SC_NosCelulaExtractor.codigos('PD: ALB06-2A2'), 'Código depois de prefixo.');
        Assert.areEqual(new List<String>{ 'STB51' }, SC_NosCelulaExtractor.codigos('STB51 PD 2AB'), 'Código antes de sufixo solto.');
        Assert.areEqual(
            new List<String>{ 'ALM13', 'BAR03' },
            SC_NosCelulaExtractor.codigos('OTI-MR0 ALM13 e BAR03 - Cabos caidos'),
            'Dois códigos vêm pela ordem em que aparecem.'
        );
    }

    @IsTest
    static void oQueNaoEhCodigoNaoEhApanhado() {
        Assert.isTrue(SC_NosCelulaExtractor.codigos('OTI-RA2 sem referencia de rede').isEmpty(), 'O tipo de OT não é célula.');
        Assert.isTrue(SC_NosCelulaExtractor.codigos('AS4112').isEmpty(), 'Duas letras e quatro dígitos não é código.');
        Assert.isTrue(SC_NosCelulaExtractor.codigos('N22SSM0002J14').isEmpty(), 'Três letras seguidas de mais de dois dígitos não é código.');
        Assert.isTrue(SC_NosCelulaExtractor.codigos(null).isEmpty(), 'Texto nulo não rebenta.');
        Assert.isTrue(SC_NosCelulaExtractor.codigos('').isEmpty(), 'Texto vazio não rebenta.');
    }

    @IsTest
    static void codigoRepetidoContaUmaVezSo() {
        Assert.areEqual(
            new List<String>{ 'BAR03' },
            SC_NosCelulaExtractor.codigos('BAR03 e outra vez BAR03'),
            'O mesmo código repetido conta uma vez.'
        );
    }

    @IsTest
    static void elementoDeRedeGanhaAoResumo() {
        SC_NosTarefa tarefa = SC_NosParser.detalhe(SC_NosTestDados.fixture('SC_NosFx_DetalheOk'));

        List<String> encontrados = SC_NosCelulaExtractor.codigosDaTarefa(tarefa);

        Assert.areEqual('CAI04', encontrados[0], 'O elemento de rede é campo estruturado e ganha ao texto livre.');
        Assert.areEqual(1, encontrados.size(), 'Os dois elementos do detalhe são a mesma célula.');
    }

    @IsTest
    static void elementoDeRedeQueNaoComecaPeloCodigoNaoConta() {
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.elementosRede = new List<String>{ 'PLC-YQC51-006' };

        List<String> encontrados = SC_NosCelulaExtractor.codigosDaTarefa(tarefa);

        Assert.areEqual('BAR03', encontrados[0], 'Sem elemento de rede utilizável, vale o resumo.');
    }

    @IsTest
    static void celulaPropostaTrazTecnologiaTerritorioECoordenada() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_TEJO);

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        Boolean escreveu = extractor.aplicar(
            ordem, tarefa, SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_TEJO), false, false
        );
        Test.stopTest();

        Assert.isTrue(escreveu, 'A célula BAR03 existe e é activa: tem de ser proposta.');
        Assert.areEqual(SC_NosTestDados.celulasPorCodigo.get('BAR03'), ordem.Celula__c, 'A célula proposta é a do resumo.');
        Assert.areEqual('Proposta pela API', ordem.Origem_Celula__c, 'A origem diz que foi a API a propor.');
        Assert.isFalse(ordem.Classificacao_Confirmada__c, 'Uma proposta não é uma confirmação.');
        Assert.areEqual('HFC', ordem.Tecnologia__c, 'A tecnologia vem da célula.');
        Celula__c bar03 = [
            SELECT Localizacao__Latitude__s, Localizacao__Longitude__s
            FROM Celula__c WHERE Codigo__c = 'BAR03' LIMIT 1
        ];
        Assert.areEqual(bar03.Localizacao__Latitude__s, ordem.Latitude, 'A latitude vem da célula.');
        Assert.areEqual(bar03.Localizacao__Longitude__s, ordem.Longitude, 'A longitude vem da célula.');
        Assert.areEqual(
            SC_NosTestDados.zonasPorCodigo.get(SC_NosTestDados.ZONA_TEJO), ordem.ServiceTerritoryId,
            'A zona da célula manda no despacho, não o território de grupo.'
        );
        Assert.isFalse(
            ordem.Divergencia_Territorio__c,
            'A zona da célula é filha do grupo que a NOS deu: sem divergência.'
        );
        Assert.isNull(ordem.Celulas_Candidatas__c, 'Com um só código não há candidatas.');
    }

    @IsTest
    static void celulaNoutroTerritorioMarcaDivergencia() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        // BAR03 está no Tejo e a NOS atribuiu a ordem ao grupo do Sul.
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        extractor.aplicar(ordem, tarefa, SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_SUL), false, false);
        Test.stopTest();

        Assert.isTrue(
            ordem.Divergencia_Territorio__c,
            'A zona da célula é do Tejo e o grupo é do Sul: é divergência.'
        );
        Assert.areEqual(
            SC_NosTestDados.zonasPorCodigo.get(SC_NosTestDados.ZONA_TEJO), ordem.ServiceTerritoryId,
            'Mesmo com divergência, o território que fica é a zona da célula.'
        );
    }

    @IsTest
    static void variosCodigosDaoUmaPropostaEORestoCandidatas() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-MR0', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'OTI-MR0 ALM13 e BAR03 e COR15 - Cabos caidos';

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        extractor.aplicar(ordem, tarefa, SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_SUL), false, false);
        Test.stopTest();

        Assert.areEqual(SC_NosTestDados.celulasPorCodigo.get('ALM13'), ordem.Celula__c, 'O primeiro código é o proposto.');
        Assert.areEqual('BAR03, COR15', ordem.Celulas_Candidatas__c, 'Os restantes ficam como candidatas.');
    }

    @IsTest
    static void codigoSemCadastroNaoCriaNadaEDeixaAviso() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'OTI-RA2 ZZZ99 PD 2AB - Oscilações UP TX';

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        Boolean escreveu = extractor.aplicar(ordem, tarefa, null, false, false);
        Test.stopTest();

        Assert.isFalse(escreveu, 'Sem célula no cadastro não há proposta.');
        Assert.isNull(ordem.Celula__c, 'E a ordem fica por classificar.');
        Assert.areEqual(1, extractor.ocorrencias().size(), 'Fica um aviso com o código que falta.');
        Assert.isTrue(
            extractor.ocorrencias()[0].Mensagem__c.contains('ZZZ99'),
            'O aviso nomeia o código: ' + extractor.ocorrencias()[0].Mensagem__c
        );
        Assert.areEqual(0, [SELECT COUNT() FROM Celula__c WHERE Codigo__c = 'ZZZ99'], 'A célula não se cria sozinha.');
    }

    @IsTest
    static void celulaDesactivadaNaoEhProposta() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'OTI-RA2 INA01 sem sinal';

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        Boolean escreveu = extractor.aplicar(ordem, tarefa, null, false, false);
        Test.stopTest();

        Assert.isFalse(escreveu, 'Uma célula desactivada não conta como cadastro.');
        Assert.areEqual(1, extractor.ocorrencias().size(), 'E deixa aviso, como um código que não existe.');
    }

    @IsTest
    static void celulaJaPreenchidaOuConfirmadaNuncaEhReescrita() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder comCelula = new WorkOrder();
        WorkOrder confirmada = new WorkOrder();
        Boolean escreveuComCelula = extractor.aplicar(comCelula, tarefa, null, true, false);
        Boolean escreveuConfirmada = extractor.aplicar(confirmada, tarefa, null, false, true);
        Test.stopTest();

        Assert.isFalse(escreveuComCelula, 'Uma célula já preenchida não se reescreve.');
        Assert.isNull(comCelula.Celula__c, 'E nada é escrito na ordem.');
        Assert.isFalse(escreveuConfirmada, 'Uma classificação confirmada pelo despacho é intocável.');
        Assert.isNull(confirmada.Celula__c, 'E nada é escrito na ordem.');
    }

    @IsTest
    static void tarefaSemCodigoNenhumNaoEscreveNada() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA3', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'OTI-RA3 Correcao de potencia sem referencia de rede';

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        Boolean escreveu = extractor.aplicar(ordem, tarefa, null, false, false);
        Test.stopTest();

        Assert.isFalse(escreveu, 'Sem código no texto não há nada a propor.');
        Assert.areEqual(0, extractor.ocorrencias().size(), 'E não é caso de aviso: é uma ordem por classificar.');
    }
    @IsTest
    static void divergenciaMedeSeAoNivelDoPaiDaZona() {
        Id grupoTejo = SC_NosTestDados.idFalso(ServiceTerritory.SObjectType, 1);
        Id grupoSul = SC_NosTestDados.idFalso(ServiceTerritory.SObjectType, 2);
        Id zonaDoTejo = SC_NosTestDados.idFalso(ServiceTerritory.SObjectType, 3);

        Assert.isFalse(
            SC_NosCelulaExtractor.divergente(zonaDoTejo, grupoTejo, grupoTejo),
            'A zona é filha do grupo que a NOS deu: não é divergência.'
        );
        Assert.isTrue(
            SC_NosCelulaExtractor.divergente(zonaDoTejo, grupoTejo, grupoSul),
            'A zona é filha de outro grupo: é divergência.'
        );
        Assert.isFalse(
            SC_NosCelulaExtractor.divergente(grupoTejo, null, grupoTejo),
            'Território sem pai compara-se consigo próprio: não é divergência.'
        );
        Assert.isTrue(
            SC_NosCelulaExtractor.divergente(grupoTejo, null, grupoSul),
            'Território sem pai e de outro grupo: é divergência.'
        );
        Assert.isFalse(
            SC_NosCelulaExtractor.divergente(null, null, grupoTejo),
            'Célula sem território não dá divergência.'
        );
        Assert.isFalse(
            SC_NosCelulaExtractor.divergente(zonaDoTejo, grupoTejo, null),
            'Grupo desconhecido na NOS não dá divergência: não há com o que comparar.'
        );
    }

    @IsTest
    static void celulaSemZonaFicaNoPaiESemDivergencia() {
        SC_NosTestDados.catalogo();
        Id lote = SC_NosTestDados.lote().Id;
        // A YKM01 é uma das células que só o KML conhece: está pendurada no território de
        // grupo e não numa zona, por isso o "pai" da regra é ela própria.
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS9', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'OTI-RA2 YKM01 - Rua Exemplo, 1 - Sem Sinal';

        Test.startTest();
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(lote);
        extractor.carregar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        Boolean escreveu = extractor.aplicar(
            ordem, tarefa, SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_SUL), false, false
        );
        Test.stopTest();

        Assert.isTrue(escreveu, 'A YKM01 existe e é activa.');
        Assert.areEqual(
            SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_SUL), ordem.ServiceTerritoryId,
            'Sem zona, o território da ordem é o próprio território de grupo.'
        );
        Assert.isFalse(ordem.Divergencia_Territorio__c, 'É o grupo que a NOS deu: sem divergência.');
    }
}