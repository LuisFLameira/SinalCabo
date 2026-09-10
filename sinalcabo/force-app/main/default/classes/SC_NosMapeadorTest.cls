/**
 * Testes da tabela de mapeamento, linha a linha, e das três fronteiras que a API não
 * atravessa depois de a ordem nascer: o Status, o estado de facturação e a conta.
 */
@IsTest
private class SC_NosMapeadorTest {
    private static SC_NosMapeador preparar(List<SC_NosTarefa> tarefas) {
        SC_NosMapeador mapeador = new SC_NosMapeador(SC_NosTestDados.lote().Id);
        mapeador.carregar(tarefas);
        return mapeador;
    }

    @IsTest
    static void ordemNovaRecebeTodosOsCamposDaNos() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS000002533674', 'CLOSED', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.dataFim = Datetime.newInstanceGmt(2026, 8, 4, 9, 0, 53);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual('TAS000002533674', ordem.Referencia_Ordem_Cliente__c, 'A chave é o identificador completo.');
        Assert.areEqual('INCTAS000002533674', ordem.Referencia_Ocorrencia_Cliente__c, 'A ocorrência pai vem do ReferenceID.');
        Assert.areEqual('CLOSED', ordem.Estado_Cliente__c, 'O estado da NOS guarda-se em maiúsculas.');
        Assert.areEqual(SC_NosTestDados.GRUPO_SUL, ordem.Grupo_Cliente__c, 'O grupo da NOS guarda-se como texto.');
        Assert.areEqual('SPGLOBAL', ordem.Contrato_Cliente__c, 'O contrato guarda-se como texto.');
        Assert.areEqual('Medium', ordem.Prioridade_Cliente__c, 'A prioridade da NOS guarda-se sempre.');
        Assert.areEqual(tarefa.dataAtribuicao, ordem.Data_Atribuicao_Cliente__c, 'A data de atribuição é a da NOS.');
        Assert.areEqual(tarefa.dataInicio, ordem.Data_Inicio_Cliente__c, 'A data de início é a da NOS.');
        Assert.areEqual(tarefa.dataFim, ordem.Data_Fim_Cliente__c, 'A data de fim é a da NOS.');
        Assert.areEqual(tarefa.assinatura(), ordem.Assinatura_Origem__c, 'A assinatura guarda-se para a próxima leitura.');
        Assert.isNotNull(ordem.Data_Ultima_Leitura__c, 'Cada escrita carimba a última leitura.');
        Assert.isFalse(ordem.Desaparecida_Origem__c, 'Uma tarefa que apareceu não está desaparecida.');
        Assert.areEqual('Closed', ordem.Status, 'Uma ordem que já nasce fechada na NOS entra fechada.');
        Assert.areEqual(0, mapeador.ocorrencias().size(), 'Um mapeamento limpo não gera ocorrências.');
    }

    /** Configuração com um NIF e um nome de conta escolhidos, sem tocar no registo da org. */
    private static void configurarConta(String nif, String nome) {
        SC_NosConfig.definirConfig(new Sistema_Cliente__mdt(
            DeveloperName = SC_NosConfig.SISTEMA,
            Activo__c = true,
            NIF_Conta_Cliente__c = nif,
            Nome_Conta_Cliente__c = nome
        ));
    }

    @IsTest
    static void aContaDoClienteEncontraSePeloNif() {
        SC_NosTestDados.criarTerritorios();
        SC_NosTestDados.criarTiposDeOrdem();
        configurarConta('502604751', 'Nome que não bate');
        Account certa = new Account(Name = 'NOS Comunicações, S.A.', NIF__c = '502604751');
        Account errada = new Account(Name = 'Outra qualquer', NIF__c = '999999990');
        insert new List<Account>{ errada, certa };
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual(certa.Id, ordem.AccountId, 'A conta encontra-se pelo NIF, que não muda.');
        Assert.areEqual(0, mapeador.ocorrencias().size(), 'E não deixa aviso nenhum.');
    }

    @IsTest
    static void aContaDoClienteEncontraSePeloNomeQuandoNenhumaTemONif() {
        SC_NosTestDados.criarTerritorios();
        SC_NosTestDados.criarTiposDeOrdem();
        configurarConta('000000000', 'NOS');
        Account porNome = new Account(Name = 'NOS', NIF__c = '502604751');
        insert porNome;
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual(porNome.Id, ordem.AccountId, 'Sem NIF a bater, vale o nome.');
        Assert.areEqual(0, mapeador.ocorrencias().size(), 'E também não deixa aviso.');
    }

    @IsTest
    static void semContaAOrdemEntraSemContaEOAvisoSaiUmaVezPorLote() {
        SC_NosTestDados.criarTerritorios();
        SC_NosTestDados.criarTiposDeOrdem();
        configurarConta('000000000', 'Conta que não existe');
        List<SC_NosTarefa> tarefas = new List<SC_NosTarefa>{
            SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL),
            SC_NosTestDados.tarefa('TAS2', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL),
            SC_NosTestDados.tarefa('TAS3', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL)
        };

        Test.startTest();
        SC_NosMapeador mapeador = preparar(tarefas);
        for (SC_NosTarefa tarefa : tarefas) {
            mapeador.aplicar(new WorkOrder(), tarefa, true, false, false);
        }
        Test.stopTest();

        Assert.areEqual(1, mapeador.ocorrencias().size(), 'Três ordens sem conta dão um aviso, não três.');
        Ocorrencia_Integracao__c aviso = mapeador.ocorrencias()[0];
        Assert.areEqual(SC_NosLote.TIPO_AVISO, aviso.Tipo__c, 'É aviso e não rejeição: a ordem entra.');
        Assert.areEqual('WorkOrder.AccountId', aviso.Objecto__c, 'E diz qual é o campo que ficou vazio.');
        Assert.isTrue(aviso.Mensagem__c.contains('000000000'), 'Com o NIF procurado: ' + aviso.Mensagem__c);
        Assert.isTrue(aviso.Mensagem__c.contains('Conta que não existe'), 'E o nome: ' + aviso.Mensagem__c);
    }

    @IsTest
    static void numaActualizacaoAContaNuncaEEscrita() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, false, false, false);
        Test.stopTest();

        Assert.isNull(ordem.AccountId,
            'Depois de a ordem nascer a conta é do back office, que a pode mudar.');
    }

    @IsTest
    static void ordemNovaAindaAbertaNaNosNasceNew() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual('New', ordem.Status, 'Só as que já nascem fechadas entram fechadas.');
    }

    @IsTest
    static void aDataDeLeituraEADeQuemAPassaENaoADeAgora() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        Datetime lida = Datetime.newInstanceGmt(2026, 8, 4, 7, 30, 0);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        SC_NosMapeador mapeador = new SC_NosMapeador(SC_NosTestDados.lote().Id, lida);
        mapeador.carregar(new List<SC_NosTarefa>{ tarefa });
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual(lida, ordem.Data_Ultima_Leitura__c,
            'A carga histórica carimba a hora em que a NOS respondeu, não a de agora.');
    }

    @IsTest
    static void oEstadoDaNosNuncaMexeNoNossoStatus() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'CLOSED', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, false, false, false);
        Test.stopTest();

        Assert.isNull(ordem.Status, 'Numa actualização a API nunca escreve o Status.');
        Assert.isNull(ordem.Estado_Facturacao__c, 'Numa actualização a API nunca escreve o estado de facturação.');
        Assert.areEqual('CLOSED', ordem.Estado_Cliente__c, 'O estado do operador é que muda.');
    }

    @IsTest
    static void avencaDecideOEstadoDeFacturacaoNaCriacao() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa dentro = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        SC_NosTarefa fora = SC_NosTestDados.tarefa('TAS2', 'PENDING', 'OTU-ALF', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ dentro, fora });
        WorkOrder ordemDentro = new WorkOrder();
        WorkOrder ordemFora = new WorkOrder();
        mapeador.aplicar(ordemDentro, dentro, true, false, false);
        mapeador.aplicar(ordemFora, fora, true, false, false);
        Test.stopTest();

        Assert.areEqual('Não aplicável (avença)', ordemDentro.Estado_Facturacao__c, 'Dentro da avença não se factura.');
        Assert.areEqual('Por facturar', ordemFora.Estado_Facturacao__c, 'Fora da avença nasce por facturar.');
    }

    @IsTest
    static void tipoDeOrdemDesconhecidoDeixaAOrdemSemTipoEGeraAviso() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTX-ZZ9', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.isNull(ordem.WorkTypeId, 'Sem correspondência no catálogo, a ordem fica sem tipo.');
        Assert.isNull(ordem.Estado_Facturacao__c, 'Sem tipo não se sabe se está na avença: o campo fica vazio.');
        Assert.areEqual(1, mapeador.ocorrencias().size(), 'Um tipo desconhecido gera uma ocorrência.');
        Ocorrencia_Integracao__c aviso = mapeador.ocorrencias()[0];
        Assert.areEqual('Aviso', aviso.Tipo__c, 'Um tipo desconhecido é aviso e não rejeição.');
        Assert.areEqual('TAS1', aviso.Chave_Origem__c, 'O aviso aponta à tarefa da NOS.');
        Assert.isTrue(aviso.Mensagem__c.contains('OTX-ZZ9'), 'A mensagem nomeia o código: ' + aviso.Mensagem__c);
    }

    @IsTest
    static void grupoDesconhecidoDeixaAOrdemSemTerritorioEGeraAviso() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', 'TX9-Outro');

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.isNull(ordem.ServiceTerritoryId, 'Sem território correspondente, o campo fica vazio.');
        Assert.areEqual('TX9-Outro', ordem.Grupo_Cliente__c, 'O código do grupo guarda-se na mesma.');
        Assert.areEqual(1, mapeador.ocorrencias().size(), 'Um grupo desconhecido gera uma ocorrência.');
        Assert.isTrue(
            mapeador.ocorrencias()[0].Mensagem__c.contains('TX9-Outro'),
            'A mensagem nomeia o grupo: ' + mapeador.ocorrencias()[0].Mensagem__c
        );
    }

    @IsTest
    static void grupoConhecidoResolveOTerritorio() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_TEJO);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Id esperado = SC_NosTestDados.territoriosPorCodigo.get(SC_NosTestDados.GRUPO_TEJO);
        Assert.areEqual(esperado, ordem.ServiceTerritoryId, 'O grupo da NOS resolve o território pela chave externa.');
        Assert.areEqual(esperado, mapeador.territorioDoGrupo(SC_NosTestDados.GRUPO_TEJO), 'O extractor pergunta o mesmo.');
        Assert.isNull(mapeador.territorioDoGrupo(null), 'Sem grupo não há território.');
    }

    @IsTest
    static void classificacaoConfirmadaTravaAEscritaDoTerritorio() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_TEJO);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, false, true, false);
        Test.stopTest();

        Assert.isNull(ordem.ServiceTerritoryId, 'Depois de o despacho confirmar, o território é dele.');
        Assert.areEqual(SC_NosTestDados.GRUPO_TEJO, ordem.Grupo_Cliente__c, 'O grupo da NOS continua a ser guardado.');
    }

    @IsTest
    static void territorioVindoDaCelulaNaoEEscritoPeloGrupo() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_TEJO);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        // A ordem já tem território de uma célula, ou seja uma zona: escrever aqui o
        // território do grupo puxava-a da zona para o pai a cada leitura da NOS.
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, false, false, true);
        Test.stopTest();

        Assert.isNull(ordem.ServiceTerritoryId, 'A zona da célula é mais precisa: o grupo não a substitui.');
        Assert.areEqual(SC_NosTestDados.GRUPO_TEJO, ordem.Grupo_Cliente__c, 'O grupo da NOS continua a ser guardado.');
    }

    @IsTest
    static void prioridadeSoEntraNasAvarias() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa avaria = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        avaria.prioridade = 'Critical';
        SC_NosTarefa manutencao = SC_NosTestDados.tarefa('TAS2', 'PENDING', 'OTM-MR0', SC_NosTestDados.GRUPO_SUL);
        manutencao.prioridade = 'Critical';

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ avaria, manutencao });
        WorkOrder ordemAvaria = new WorkOrder();
        WorkOrder ordemManutencao = new WorkOrder();
        mapeador.aplicar(ordemAvaria, avaria, true, false, false);
        mapeador.aplicar(ordemManutencao, manutencao, true, false, false);
        Test.stopTest();

        Assert.areEqual('Critical', ordemAvaria.Priority, 'Nas avarias a prioridade da NOS é a prioridade da ordem.');
        Assert.isNull(ordemManutencao.Priority, 'Fora das avarias a prioridade fica só no campo do cliente.');
        Assert.areEqual('Critical', ordemManutencao.Prioridade_Cliente__c, 'E o campo do cliente guarda-a sempre.');
    }

    @IsTest
    static void prioridadeForaDasConhecidasNaoChegaAOrdem() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.prioridade = 'Urgentíssima';

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.isNull(ordem.Priority, 'Um valor fora da picklist restrita faria a ordem inteira falhar.');
        Assert.areEqual('Urgentíssima', ordem.Prioridade_Cliente__c, 'Mas fica guardado no campo do cliente.');
        Assert.areEqual(1, mapeador.ocorrencias().size(), 'E deixa aviso.');
    }

    @IsTest
    static void estadoNovoDaNosEntraEDeixaAviso() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'ESCALATED', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ tarefa });
        WorkOrder ordem = new WorkOrder();
        mapeador.aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual('ESCALATED', ordem.Estado_Cliente__c, 'A picklist não é restrita para o estado novo entrar.');
        Assert.areEqual(1, mapeador.ocorrencias().size(), 'Um estado novo deixa aviso para alguém olhar.');
        Assert.isTrue(
            mapeador.ocorrencias()[0].Mensagem__c.contains('ESCALATED'),
            'A mensagem nomeia o estado: ' + mapeador.ocorrencias()[0].Mensagem__c
        );
    }

    @IsTest
    static void tecnicoConhecidoNaoFicaPorMapear() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa conhecido = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        SC_NosTarefa desconhecido = SC_NosTestDados.tarefa('TAS2', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        desconhecido.utilizador = 'U0000000';
        SC_NosTarefa semTecnico = SC_NosTestDados.tarefa('TAS3', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        semTecnico.utilizador = null;

        Test.startTest();
        SC_NosMapeador mapeador = preparar(new List<SC_NosTarefa>{ conhecido, desconhecido, semTecnico });
        WorkOrder a = new WorkOrder();
        WorkOrder b = new WorkOrder();
        WorkOrder c = new WorkOrder();
        mapeador.aplicar(a, conhecido, true, false, false);
        mapeador.aplicar(b, desconhecido, true, false, false);
        mapeador.aplicar(c, semTecnico, true, false, false);
        Test.stopTest();

        Assert.isFalse(a.Recurso_Por_Mapear__c, 'O código bate num recurso: nada por mapear.');
        Assert.areEqual(SC_NosTestDados.CODIGO_TECNICO, a.Codigo_Utilizador_Cliente_Origem__c, 'O código guarda-se sempre.');
        Assert.isTrue(b.Recurso_Por_Mapear__c, 'Sem recurso com o código, fica marcado por mapear.');
        Assert.isFalse(c.Recurso_Por_Mapear__c, 'Sem técnico indicado não há nada por mapear.');
    }

    @IsTest
    static void resumoVaiParaOAssuntoENotasParaADescricao() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosParser.detalhe(SC_NosTestDados.fixture('SC_NosFx_DetalheOk'));

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual(tarefa.resumo, ordem.Subject, 'O assunto é o resumo da NOS.');
        Assert.isFalse(ordem.Description.contains('<div>'), 'A descrição não pode trazer HTML.');
        Assert.isTrue(ordem.Description.contains('Interacções na NOS'), 'A descrição traz a secção das interacções.');
        Assert.isTrue(ordem.Description.contains('General Information'), 'E o tipo de cada interacção.');
        Assert.isTrue(ordem.Description.length() <= 32000, 'A descrição respeita o tecto do campo.');
    }

    @IsTest
    static void listagemNaoApagaADescricaoQueODetalheJaTrouxe() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, false, false, false);
        Test.stopTest();

        Assert.isNull(ordem.Description, 'A listagem não traz notas, por isso não toca na descrição.');
    }

    @IsTest
    static void assuntoLongoEhCortadoAoTectoDoCampo() {
        SC_NosTestDados.catalogo();
        SC_NosTarefa tarefa = SC_NosTestDados.tarefa('TAS1', 'PENDING', 'OTI-RA2', SC_NosTestDados.GRUPO_SUL);
        tarefa.resumo = 'A'.repeat(400);

        Test.startTest();
        WorkOrder ordem = new WorkOrder();
        preparar(new List<SC_NosTarefa>{ tarefa }).aplicar(ordem, tarefa, true, false, false);
        Test.stopTest();

        Assert.areEqual(255, ordem.Subject.length(), 'O assunto tem de caber nos 255 caracteres do campo.');
    }

    @IsTest
    static void descricaoDeTarefaSemNotasNemInteraccoesFicaVazia() {
        SC_NosTarefa tarefa = new SC_NosTarefa();
        tarefa.id = 'TAS1';
        tarefa.veioDoDetalhe = true;

        Assert.isNull(SC_NosMapeador.descricao(tarefa), 'Sem notas nem interacções não há descrição.');
    }
}