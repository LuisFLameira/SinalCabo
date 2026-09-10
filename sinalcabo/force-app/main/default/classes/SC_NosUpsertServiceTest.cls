/**
 * Testes do motor de escrita: o que cria, o que actualiza, o que se recusa a tocar e
 * o que regista quando uma linha não entra.
 */
@IsTest
private class SC_NosUpsertServiceTest {
    private static Id lote() {
        return SC_NosTestDados.lote().Id;
    }

    @IsTest
    static void listagemRealCriaAsCinquentaESeisOrdens() {
        SC_NosTestDados.catalogo();
        Id loteId = lote();

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.fixture('SC_NosFx_ListaOk'), loteId
        );
        Test.stopTest();

        Assert.areEqual(56, r.lidos, 'A listagem traz 56 tarefas.');
        Assert.areEqual(56, r.criados, 'Todas nascem como ordem nova.');
        Assert.areEqual(0, r.actualizados, 'Nenhuma existia antes.');
        Assert.areEqual(0, r.rejeitados, 'Nenhuma pode ser recusada.');
        Assert.areEqual(56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL], 'Ordens na org.');
        Assert.areEqual(56, r.criadas.size(), 'As criadas ficam listadas para a passagem de detalhes.');

        WorkOrder primeira = [
            SELECT Status, Estado_Cliente__c, Estado_Facturacao__c, Celula__c, Tecnologia__c,
                   Divergencia_Territorio__c, Origem_Celula__c, Assinatura_Origem__c, Ultimo_Lote__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002533674' LIMIT 1
        ];
        Assert.areEqual('Closed', primeira.Status, 'Vinda fechada da NOS, a ordem nasce fechada.');
        Assert.areEqual('CLOSED', primeira.Estado_Cliente__c, 'O estado do operador é o que a API escreve.');
        Assert.areEqual('Não aplicável (avença)', primeira.Estado_Facturacao__c, 'OTI-RA2 está dentro da avença.');
        Assert.areEqual(SC_NosTestDados.celulasPorCodigo.get('BAR03'), primeira.Celula__c, 'A célula é proposta do resumo.');
        Assert.areEqual('HFC', primeira.Tecnologia__c, 'A tecnologia vem da célula.');
        Assert.isTrue(primeira.Divergencia_Territorio__c, 'BAR03 é do Tejo e o grupo é do Sul.');
        Assert.areEqual('Proposta pela API', primeira.Origem_Celula__c, 'A origem da célula é a API.');
        Assert.areEqual(64, primeira.Assinatura_Origem__c.length(), 'A assinatura fica guardada.');
        Assert.areEqual(loteId, primeira.Ultimo_Lote__c, 'A ordem aponta ao lote que a escreveu.');
    }

    @IsTest
    static void segundaLeituraIgualNaoEscreveNadaNemDuplica() {
        SC_NosTestDados.catalogo();
        String corpo = SC_NosTestDados.fixture('SC_NosFx_ListaOk');
        SC_NosUpsertService.processarListagem(corpo, lote());

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(corpo, lote());
        Test.stopTest();

        Assert.areEqual(56, r.lidos, 'A segunda leitura lê o mesmo.');
        Assert.areEqual(0, r.criados, 'E não cria nada.');
        Assert.areEqual(0, r.actualizados, 'E não actualiza nada, porque a assinatura não mudou.');
        Assert.areEqual(56, r.inalterados, 'Todas ficam contadas como inalteradas.');
        Assert.areEqual(56, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL], 'Sem duplicados.');
    }

    @IsTest
    static void identificadoresRepetidosNoMesmoCorpoColapsam() {
        SC_NosTestDados.catalogo();

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.fixture('SC_NosFx_ListaMista'), lote()
        );
        Test.stopTest();

        Assert.areEqual(12, r.lidos, 'A listagem mista tem 12 linhas.');
        Assert.areEqual(11, r.criados, 'Duas linhas são a mesma ordem: ficam 11.');
        WorkOrder repetida = [
            SELECT Estado_Cliente__c, Data_Fim_Cliente__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002533674' LIMIT 1
        ];
        Assert.areEqual('CLOSED', repetida.Estado_Cliente__c, 'Vence a última linha do corpo, que é a mais recente.');
        Assert.isNotNull(repetida.Data_Fim_Cliente__c, 'E é a que traz a data de fim.');
    }

    @IsTest
    static void mudancaDeEstadoNaNosDeixaOcorrenciaDeAlteracao() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo",' +
            '"Summary":"OTI-RA2 BAR03 sem sinal"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('PENDING', 'RESOLVED')), lote()
        );
        Test.stopTest();

        Assert.areEqual(1, r.actualizados, 'A assinatura mudou, por isso a ordem é actualizada.');
        Ocorrencia_Integracao__c alteracao;
        for (Ocorrencia_Integracao__c o : r.ocorrencias) {
            if (o.Tipo__c == 'Alteração') {
                alteracao = o;
            }
        }
        Assert.isNotNull(alteracao, 'Uma mudança de estado tem de deixar ocorrência de Alteração.');
        Assert.isTrue(
            alteracao.Mensagem__c.contains('PENDING') && alteracao.Mensagem__c.contains('RESOLVED'),
            'A mensagem tem de dizer de onde para onde: ' + alteracao.Mensagem__c
        );
        Assert.isNotNull(alteracao.Ordem__c, 'A ocorrência aponta à ordem afectada.');
    }

    @IsTest
    static void leituraSeguinteNaoPuxaAOrdemDaZonaParaOPai() {
        SC_NosTestDados.catalogo();
        Id zonaDoTejo = SC_NosTestDados.zonasPorCodigo.get(SC_NosTestDados.ZONA_TEJO);
        Id grupoDoTejo = SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_TEJO);
        // BAR03 vive na Zona Centro 1, que é filha do Tejo, e a NOS atribui ao grupo do Tejo.
        String linha = '{"ID":"TAS7","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TL2-Sinalcabo",' +
            '"Summary":"OTI-RA2 BAR03 sem sinal"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        WorkOrder nascida = [
            SELECT ServiceTerritoryId, Divergencia_Territorio__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS7' LIMIT 1
        ];
        Assert.areEqual(zonaDoTejo, nascida.ServiceTerritoryId, 'A ordem nasce na zona da célula.');
        Assert.isFalse(nascida.Divergencia_Territorio__c, 'A zona é filha do grupo que a NOS deu.');

        Test.startTest();
        // Segunda leitura, mesmo grupo e estado novo: a ordem já tem célula, por isso o
        // extractor não escreve nada e é o mapeador que poderia estragar o território.
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('PENDING', 'WORK_IN_PROGRESS')), lote()
        );
        Test.stopTest();

        WorkOrder depois = [
            SELECT ServiceTerritoryId, Divergencia_Territorio__c, Estado_Cliente__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS7' LIMIT 1
        ];
        Assert.areEqual('WORK_IN_PROGRESS', depois.Estado_Cliente__c, 'A leitura escreveu, senão o teste não prova nada.');
        Assert.areEqual(zonaDoTejo, depois.ServiceTerritoryId, 'A ordem fica na zona: o grupo não a puxa para o pai.');
        Assert.areNotEqual(grupoDoTejo, depois.ServiceTerritoryId, 'E não sobe ao território de grupo.');
        Assert.isFalse(depois.Divergencia_Territorio__c, 'Nem acende divergência por a zona não ser o grupo.');
    }

    @IsTest
    static void grupoNovoNaNosAcendeDivergenciaNaOrdemComCelula() {
        SC_NosTestDados.catalogo();
        Id zonaDoTejo = SC_NosTestDados.zonasPorCodigo.get(SC_NosTestDados.ZONA_TEJO);
        String linha = '{"ID":"TAS8","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TL2-Sinalcabo",' +
            '"Summary":"OTI-RA2 BAR03 sem sinal"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        Test.startTest();
        // A NOS muda o grupo da ordem para o Sul, com a célula a ficar no Tejo.
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('TL2-Sinalcabo', 'TS2-Sinalcabo')), lote()
        );
        Test.stopTest();

        WorkOrder depois = [
            SELECT ServiceTerritoryId, Divergencia_Territorio__c, Grupo_Cliente__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS8' LIMIT 1
        ];
        Assert.areEqual('TS2-Sinalcabo', depois.Grupo_Cliente__c, 'O grupo novo da NOS fica guardado.');
        Assert.isTrue(depois.Divergencia_Territorio__c, 'A zona da célula já não pertence ao grupo: divergência.');
        Assert.areEqual(zonaDoTejo, depois.ServiceTerritoryId, 'E o território continua a ser a zona da célula.');
    }

    @IsTest
    static void classificacaoConfirmadaSobreviveAsLeiturasSeguintes() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo",' +
            '"Summary":"OTI-RA2 BAR03 sem sinal"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        WorkOrder ordem = [SELECT Id FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1];
        ordem.Celula__c = SC_NosTestDados.celulasPorCodigo.get('COR15');
        ordem.Classificacao_Confirmada__c = true;
        ordem.Origem_Celula__c = 'Despacho';
        ordem.Status = 'In Progress';
        ordem.Estado_Facturacao__c = 'Facturado';
        update ordem;

        Test.startTest();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('PENDING', 'CLOSED').replace('BAR03', 'ALM13')), lote()
        );
        Test.stopTest();

        WorkOrder depois = [
            SELECT Celula__c, Origem_Celula__c, Classificacao_Confirmada__c, Status,
                   Estado_Facturacao__c, Estado_Cliente__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1
        ];
        Assert.areEqual(SC_NosTestDados.celulasPorCodigo.get('COR15'), depois.Celula__c, 'A célula do despacho fica.');
        Assert.areEqual('Despacho', depois.Origem_Celula__c, 'E a origem também.');
        Assert.isTrue(depois.Classificacao_Confirmada__c, 'A confirmação não se apaga.');
        Assert.areEqual('In Progress', depois.Status, 'O Status é da SinalCabo e a API não lhe toca.');
        Assert.areEqual('Facturado', depois.Estado_Facturacao__c, 'O estado de facturação é do back office.');
        Assert.areEqual('CLOSED', depois.Estado_Cliente__c, 'Só o estado do operador é que a API muda.');
    }

    @IsTest
    static void linhaRecusadaNaoLevaAsOutrasAtras() {
        SC_NosTestDados.catalogo();
        // Uma referência acima dos 50 caracteres do campo: a plataforma recusa a linha.
        String longa = 'TAS' + '9'.repeat(60);
        String boa = '{"ID":"TAS1","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo"}';
        String ma = '{"ID":"' + longa + '","Status":"PENDING","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo"}';

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(boa + ',' + ma), lote()
        );
        Test.stopTest();

        Assert.areEqual(1, r.criados, 'A linha boa entra.');
        Assert.areEqual(1, r.rejeitados, 'A linha má fica de fora.');
        Ocorrencia_Integracao__c rejeicao;
        for (Ocorrencia_Integracao__c o : r.ocorrencias) {
            if (o.Tipo__c == 'Rejeição') {
                rejeicao = o;
            }
        }
        Assert.isNotNull(rejeicao, 'A linha recusada deixa ocorrência de Rejeição.');
        Assert.isTrue(rejeicao.Reprocessavel__c, 'Uma rejeição é reprocessável depois de corrigida a causa.');
        Assert.isNotNull(rejeicao.Conteudo__c, 'A ocorrência guarda o registo que não entrou.');
    }

    @IsTest
    static void detalheEnriqueceAOrdemQueAListagemJaCriou() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS000002537686","Status":"PENDING","RequestType":"OTI-RA3",' +
            '"AssignedGroup":"TL2-Sinalcabo","Summary":"OTI-RA3 sem referencia"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarDetalhe(
            SC_NosTestDados.fixture('SC_NosFx_DetalheOk'), lote()
        );
        Test.stopTest();

        Assert.areEqual(1, r.actualizados, 'O detalhe actualiza a ordem que já existia.');
        WorkOrder ordem = [
            SELECT Description, Celula__c, Tecnologia__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS000002537686' LIMIT 1
        ];
        Assert.isTrue(ordem.Description.contains('Interacções na NOS'), 'A descrição vem do detalhe.');
        Assert.areEqual(SC_NosTestDados.celulasPorCodigo.get('CAI04'), ordem.Celula__c, 'O elemento de rede propõe a célula.');
        Assert.areEqual('FTTH', ordem.Tecnologia__c, 'E a tecnologia vem dessa célula.');
    }

    @IsTest
    static void detalheEscreveMesmoComOCabecalhoIgual() {
        SC_NosTestDados.catalogo();
        String corpo = SC_NosTestDados.fixture('SC_NosFx_DetalheOk');
        SC_NosUpsertService.processarDetalhe(corpo, lote());

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarDetalhe(corpo, lote());
        Test.stopTest();

        Assert.areEqual(1, r.actualizados, 'O detalhe traz notas que a assinatura não cobre: escreve sempre.');
        Assert.areEqual(0, r.inalterados, 'Por isso nunca conta como inalterado.');
    }

    @IsTest
    static void ordemQueDesapareceuNaOrigemFicaMarcada() {
        SC_NosTestDados.catalogo();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem('{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2"}'), lote()
        );

        Test.startTest();
        List<Ocorrencia_Integracao__c> ocorrencias = SC_NosUpsertService.marcarDesaparecidas(
            new Set<String>{ 'TAS9', 'TAS_QUE_NAO_EXISTE' }, lote()
        );
        Test.stopTest();

        Assert.areEqual(1, ocorrencias.size(), 'Só a ordem que existe na org gera ocorrência.');
        Assert.areEqual('Aviso', ocorrencias[0].Tipo__c, 'Desaparecer na origem é aviso e não rejeição.');
        Assert.isTrue(
            [SELECT Desaparecida_Origem__c FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1]
                .Desaparecida_Origem__c,
            'A ordem fica marcada como desaparecida na NOS.'
        );
        Assert.areEqual(0, SC_NosUpsertService.marcarDesaparecidas(null, lote()).size(), 'Sem referências não faz nada.');
    }

    @IsTest
    static void ordemQueVoltaAAparecerDeixaDeEstarDesaparecida() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());
        SC_NosUpsertService.marcarDesaparecidas(new Set<String>{ 'TAS9' }, lote());

        Test.startTest();
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha.replace('PENDING', 'RESOLVED')), lote());
        Test.stopTest();

        Assert.isFalse(
            [SELECT Desaparecida_Origem__c FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1]
                .Desaparecida_Origem__c,
            'Se a tarefa voltou a aparecer, já não está desaparecida.'
        );
    }

    @IsTest
    static void ordemQueNasceFechadaEntraFechadaESemMarcacaoVazia() {
        SC_NosTestDados.catalogo();
        SC_NosTestDados.ligarMarcacaoAutomatica('OTI-RA2');

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(
                '{"ID":"TAS9","Status":"CLOSED","RequestType":"OTI-RA2"},' +
                '{"ID":"TAS7","Status":"RESOLVED","RequestType":"OTI-RA2"},' +
                '{"ID":"TAS8","Status":"PENDING","RequestType":"OTI-RA2"}'
            ),
            lote()
        );
        Test.stopTest();

        Map<String, WorkOrder> ordens = new Map<String, WorkOrder>();
        for (WorkOrder ordem : [
            SELECT Id, Referencia_Ordem_Cliente__c, Status, IsClosed
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL
        ]) {
            ordens.put(ordem.Referencia_Ordem_Cliente__c, ordem);
        }
        Assert.areEqual('Closed', ordens.get('TAS9').Status, 'CLOSED na NOS à nascença entra fechada.');
        Assert.areEqual('Closed', ordens.get('TAS7').Status, 'RESOLVED conta como fechada na NOS.');
        Assert.areEqual('New', ordens.get('TAS8').Status, 'As que ainda estão abertas na NOS entram New.');
        Assert.areEqual(2, r.marcacoesApagadas, 'As duas marcações vazias das fechadas foram apagadas.');

        Assert.areEqual(
            0,
            [
                SELECT COUNT() FROM ServiceAppointment
                WHERE ParentRecordId IN (:ordens.get('TAS9').Id, :ordens.get('TAS7').Id)
            ],
            'Uma ordem que nasce fechada não deixa marcação nenhuma para trás.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ServiceAppointment WHERE ParentRecordId = :ordens.get('TAS8').Id],
            'A marcação da ordem que continua aberta fica de pé.'
        );
    }

    @IsTest
    static void ordemJaCriadaQueANosFechaDepoisNaoMudaDeStatus() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"PENDING","RequestType":"OTI-RA2"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote());

        Test.startTest();
        SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('PENDING', 'CLOSED')), lote()
        );
        Test.stopTest();

        WorkOrder depois = [
            SELECT Status, Estado_Cliente__c, Fechada_Cliente_Sem_Fecho__c
            FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1
        ];
        Assert.areEqual('New', depois.Status, 'O fecho na NOS não fecha uma ordem que já cá estava aberta.');
        Assert.areEqual('CLOSED', depois.Estado_Cliente__c, 'O estado do operador é que muda.');
        Assert.isTrue(depois.Fechada_Cliente_Sem_Fecho__c, 'E é a fórmula que denuncia o desencontro.');
    }

    @IsTest
    static void nascidaFechadaRecusadaEntraEmDoisPassos() {
        SC_NosTestDados.catalogo();
        Id loteId = lote();
        WorkOrder recusada = new WorkOrder(
            Subject = 'Recusada à primeira',
            Status = SC_NosUpsertService.STATUS_FECHADO,
            Estado_Cliente__c = 'CLOSED',
            Referencia_Ordem_Cliente__c = 'TAS-RECUSADA'
        );
        // Um upsert que falhou de propósito, para exercitar a segunda tentativa sem
        // precisar de uma org onde o pacote recuse mesmo inserir uma ordem fechada.
        List<Database.UpsertResult> gravados = Database.upsert(
            new List<WorkOrder>{
                new WorkOrder(Subject = 'Sem chave', Referencia_Ordem_Cliente__c = null)
            },
            WorkOrder.Referencia_Ordem_Cliente__c,
            false
        );
        Assert.isFalse(gravados[0].isSuccess(), 'A linha sem chave tem mesmo de ser recusada.');

        SC_NosUpsertService.Resultado resultado = new SC_NosUpsertService.Resultado();

        Test.startTest();
        Map<Integer, Id> recuperadas = SC_NosUpsertService.recuperarNascidasFechadas(
            gravados, new List<WorkOrder>{ recusada }, new List<Boolean>{ true }, loteId, resultado
        );
        Test.stopTest();

        Assert.areEqual(1, recuperadas.size(), 'A ordem recusada é recuperada.');
        Assert.areEqual(
            'Closed',
            [SELECT Status FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS-RECUSADA' LIMIT 1].Status,
            'Entra New e fecha-se na mesma transacção.'
        );
        Assert.areEqual(1, resultado.ocorrencias.size(), 'E fica registado que entrou em dois passos.');
        Assert.areEqual(SC_NosLote.TIPO_AVISO, resultado.ocorrencias[0].Tipo__c, 'É aviso e não rejeição.');
    }

    @IsTest
    static void leituraMaisVelhaNaoEscrevePorCimaDaMaisRecente() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"WORK_IN_PROGRESS","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote(), Datetime.now());

        Test.startTest();
        // A mesma ordem, como estava há trinta dias, a chegar pela carga histórica.
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('WORK_IN_PROGRESS', 'ASSIGNED_TO_COMPANY')),
            lote(),
            Datetime.now().addDays(-30)
        );
        Test.stopTest();

        Assert.areEqual(1, r.lidos, 'A linha é lida.');
        Assert.areEqual(1, r.ignorados, 'E descartada, porque a ordem já viu uma leitura mais recente.');
        Assert.areEqual(0, r.actualizados, 'Nada é escrito.');
        Assert.areEqual(
            'WORK_IN_PROGRESS',
            [SELECT Estado_Cliente__c FROM WorkOrder WHERE Referencia_Ordem_Cliente__c = 'TAS9' LIMIT 1].Estado_Cliente__c,
            'O estado que o polling já tinha escrito fica de pé.'
        );
    }

    @IsTest
    static void leituraMaisRecenteQueAGuardadaEscreve() {
        SC_NosTestDados.catalogo();
        String linha = '{"ID":"TAS9","Status":"ASSIGNED_TO_COMPANY","RequestType":"OTI-RA2","AssignedGroup":"TS2-Sinalcabo"}';
        SC_NosUpsertService.processarListagem(SC_NosTestDados.listagem(linha), lote(), Datetime.now().addDays(-30));

        Test.startTest();
        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(
            SC_NosTestDados.listagem(linha.replace('ASSIGNED_TO_COMPANY', 'WORK_IN_PROGRESS')),
            lote(),
            Datetime.now()
        );
        Test.stopTest();

        Assert.areEqual(0, r.ignorados, 'Uma leitura mais recente não é descartada.');
        Assert.areEqual(1, r.actualizados, 'E escreve.');
    }

    @IsTest
    static void corpoSemTarefasNaoEscreveNada() {
        SC_NosTestDados.catalogo();

        Test.startTest();
        SC_NosUpsertService.Resultado vazio = SC_NosUpsertService.processarListagem('{"result_code":0}', lote());
        SC_NosUpsertService.Resultado semTarefas = SC_NosUpsertService.processar(null, lote());
        Test.stopTest();

        Assert.areEqual(0, vazio.lidos, 'Um corpo sem tarefas não lê nada.');
        Assert.areEqual(0, semTarefas.lidos, 'Uma lista nula também não.');
        Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder WHERE Referencia_Ordem_Cliente__c != NULL], 'E nada é escrito.');
    }

    @IsTest
    static void resultadosJuntamSeParaOLoteFecharComOsTotais() {
        SC_NosUpsertService.Resultado a = new SC_NosUpsertService.Resultado();
        a.lidos = 3;
        a.criados = 2;
        a.referencias.add('TAS1');
        SC_NosUpsertService.Resultado b = new SC_NosUpsertService.Resultado();
        b.lidos = 1;
        b.actualizados = 1;
        b.rejeitados = 1;
        b.inalterados = 2;
        b.ignorados = 3;
        b.marcacoesApagadas = 1;
        b.criadas.add('TAS2');

        a.juntar(b);

        Assert.areEqual(4, a.lidos, 'Os lidos somam.');
        Assert.areEqual(2, a.criados, 'Os criados somam.');
        Assert.areEqual(1, a.actualizados, 'Os actualizados somam.');
        Assert.areEqual(1, a.rejeitados, 'Os rejeitados somam.');
        Assert.areEqual(2, a.inalterados, 'Os inalterados somam.');
        Assert.areEqual(3, a.ignorados, 'Os ignorados por leitura mais velha somam.');
        Assert.areEqual(1, a.marcacoesApagadas, 'As marcações apagadas somam.');
        Assert.areEqual(1, a.referencias.size(), 'As referências juntam-se.');
        Assert.areEqual(1, a.criadas.size(), 'E as criadas também.');
        Assert.isFalse(a.temOcorrencias(), 'Sem ocorrências não há nada para investigar.');
    }
}