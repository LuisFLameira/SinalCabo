/**
 * A tabela de mapeamento entre a tarefa da NOS e a Work Order.
 *
 * Duas fronteiras que este código nunca atravessa:
 *  1. o Status da ordem é da SinalCabo. Depois de a ordem nascer, a API escreve
 *     Estado_Cliente__c e mais nada, e o desencontro entre os dois estados aparece na
 *     fórmula Fechada_Cliente_Sem_Fecho__c, nunca numa transição automática. Só na
 *     criação o Status se decide aqui: New, ou Closed quando a ordem já nasce fechada
 *     na NOS e não há trabalho nenhum para agendar;
 *  2. o Estado_Facturacao__c decide-se uma vez, quando a ordem nasce, a partir da
 *     avença do Work Type. Depois disso é do back office e a API não lhe toca;
 *  3. o AccountId também se decide uma vez, na criação, e vem da configuração e não da
 *     resposta da NOS. Depois disso é do back office, que pode mudar a conta.
 *
 * Os valores que a NOS manda e que não conhecemos entram na mesma: um estado novo
 * entra na picklist não restrita, um tipo ou um grupo desconhecidos deixam o campo
 * vazio. Nos três casos fica uma ocorrência de Aviso para alguém olhar.
 *
 * Bulk: carregar() lê os três catálogos numa consulta cada, para todo o lote.
 */
public with sharing class SC_NosMapeador {
    private static final Set<String> PRIORIDADES_PADRAO = new Set<String>{ 'Low', 'Medium', 'High', 'Critical' };
    private static final Set<String> ESTADOS_CONHECIDOS = new Set<String>{
        'ASSIGNED_TO_COMPANY', 'ASSIGNED_TO_USER', 'WORK_IN_PROGRESS', 'PENDING', 'RESOLVED', 'CLOSED'
    };
    private static final Integer TECTO_ASSUNTO = 255;
    private static final Integer TECTO_DESCRICAO = 32000;

    /** Só as famílias de avaria carregam a prioridade da NOS para a prioridade da ordem. */
    private static final String FAMILIA_AVARIA = 'Avaria';

    private final Map<String, WorkType> tiposPorCodigo = new Map<String, WorkType>();
    private final Map<String, ServiceTerritory> territoriosPorCodigo = new Map<String, ServiceTerritory>();
    private final Set<String> codigosDeRecurso = new Set<String>();
    private final List<Ocorrencia_Integracao__c> ocorrencias = new List<Ocorrencia_Integracao__c>();

    /** Conta do operador, procurada uma vez por transacção em carregar(). */
    private Id contaCliente;
    /** O aviso de conta em falta sai uma vez por lote e não uma vez por ordem. */
    private Boolean avisoDaContaDado = false;

    private Id loteId;
    /** Instante em que a NOS respondeu; é o que fica em Data_Ultima_Leitura__c. */
    private Datetime dataLeitura;

    public SC_NosMapeador(Id loteId) {
        this(loteId, Datetime.now());
    }

    public SC_NosMapeador(Id loteId, Datetime dataLeitura) {
        this.loteId = loteId;
        this.dataLeitura = dataLeitura == null ? Datetime.now() : dataLeitura;
    }

    /** Lê os catálogos de que o lote inteiro precisa. Três consultas, sempre três. */
    public void carregar(List<SC_NosTarefa> tarefas) {
        Set<String> codigosTipo = new Set<String>();
        Set<String> codigosGrupo = new Set<String>();
        Set<String> codigosUtilizador = new Set<String>();
        for (SC_NosTarefa tarefa : tarefas) {
            if (String.isNotBlank(tarefa.tipoPedido)) {
                codigosTipo.add(tarefa.tipoPedido);
            }
            if (String.isNotBlank(tarefa.grupo)) {
                codigosGrupo.add(tarefa.grupo);
            }
            if (String.isNotBlank(tarefa.utilizador)) {
                codigosUtilizador.add(tarefa.utilizador);
            }
        }

        for (WorkType tipo : [
            SELECT Id, Codigo_Cliente__c, Familia__c, Dentro_Avenca__c
            FROM WorkType
            WHERE Codigo_Cliente__c IN :codigosTipo
        ]) {
            tiposPorCodigo.put(tipo.Codigo_Cliente__c, tipo);
        }
        for (ServiceTerritory territorio : [
            SELECT Id, Codigo_Grupo_Cliente__c
            FROM ServiceTerritory
            WHERE Codigo_Grupo_Cliente__c IN :codigosGrupo
        ]) {
            territoriosPorCodigo.put(territorio.Codigo_Grupo_Cliente__c, territorio);
        }
        for (ServiceResource recurso : [
            SELECT Codigo_Utilizador_Cliente__c
            FROM ServiceResource
            WHERE Codigo_Utilizador_Cliente__c IN :codigosUtilizador AND IsActive = TRUE
        ]) {
            codigosDeRecurso.add(recurso.Codigo_Utilizador_Cliente__c);
        }
        carregarContaCliente();
    }

    /**
     * A conta do operador, uma consulta por transacção e fora de qualquer ciclo.
     *
     * Procura-se pelo NIF, que não muda, e só depois pelo nome, que muda. A API não
     * traz conta nenhuma: o `RequesterCompany` que a NOS manda é sempre "NOS" e é texto
     * livre, por isso a conta vem da configuração e não do corpo da resposta.
     */
    private void carregarContaCliente() {
        String nif = SC_NosConfig.nifDaContaCliente();
        String nome = SC_NosConfig.nomeDaContaCliente();
        if (String.isBlank(nif) && String.isBlank(nome)) {
            return;
        }
        Id porNome;
        for (Account conta : [
            SELECT Id, Name, NIF__c
            FROM Account
            WHERE NIF__c = :nif OR Name = :nome
            ORDER BY CreatedDate ASC
        ]) {
            if (String.isNotBlank(nif) && nif.equals(conta.NIF__c)) {
                this.contaCliente = conta.Id;
                return;
            }
            if (porNome == null && String.isNotBlank(nome) && nome.equals(conta.Name)) {
                porNome = conta.Id;
            }
        }
        this.contaCliente = porNome;
    }

    /** Território que a NOS atribuiu, para o extractor comparar com o da célula. */
    public Id territorioDoGrupo(String grupo) {
        ServiceTerritory territorio = String.isBlank(grupo) ? null : territoriosPorCodigo.get(grupo);
        return territorio == null ? null : territorio.Id;
    }

    public List<Ocorrencia_Integracao__c> ocorrencias() {
        return ocorrencias;
    }

    /**
     * Escreve na ordem os campos que a API detém. `nova` decide os dois campos que só
     * se escrevem uma vez: o Status e o estado de facturação.
     *
     * `territorioJaEDaCelula` diz que a ordem já tem território vindo de uma célula, ou
     * seja uma zona. Nesse caso o grupo da NOS não escreve o território: escrever o
     * território do grupo puxaria a ordem da zona para o pai a cada leitura.
     */
    public void aplicar(WorkOrder ordem, SC_NosTarefa tarefa, Boolean nova,
            Boolean classificacaoConfirmada, Boolean territorioJaEDaCelula) {
        ordem.Referencia_Ordem_Cliente__c = tarefa.id;
        ordem.Referencia_Ocorrencia_Cliente__c = corta(tarefa.referenciaOcorrencia, 50);
        ordem.Grupo_Cliente__c = corta(tarefa.grupo, 40);
        ordem.Contrato_Cliente__c = corta(tarefa.contrato, 40);
        ordem.Prioridade_Cliente__c = corta(tarefa.prioridade, 20);
        ordem.Data_Atribuicao_Cliente__c = tarefa.dataAtribuicao;
        ordem.Data_Inicio_Cliente__c = tarefa.dataInicio;
        ordem.Data_Fim_Cliente__c = tarefa.dataFim;
        ordem.Data_Ultima_Leitura__c = this.dataLeitura;
        ordem.Assinatura_Origem__c = tarefa.assinatura();
        ordem.Ultimo_Lote__c = loteId;
        // Se a tarefa voltou a aparecer, já não está desaparecida na origem.
        ordem.Desaparecida_Origem__c = false;

        estado(ordem, tarefa);
        tipoDeTrabalho(ordem, tarefa, nova);
        // Depois de o despacho confirmar a classificação, o território é dele: a NOS
        // pode mudar de grupo à vontade que o campo Grupo_Cliente__c guarda a mudança.
        // O território do grupo é o valor de recurso: só entra quando a ordem não tem
        // território de uma célula, porque a zona da célula é mais precisa do que o pai.
        if (!classificacaoConfirmada && territorioJaEDaCelula != true) {
            territorio(ordem, tarefa);
        }
        tecnico(ordem, tarefa);
        textos(ordem, tarefa);

        if (nova) {
            // Uma ordem que já nasce fechada na NOS entra fechada: não há nada para o
            // Field Service lhe fazer. As que a NOS fecha depois de existirem aqui
            // continuam a não ter o Status tocado, e é isso que a fórmula
            // Fechada_Cliente_Sem_Fecho__c denuncia.
            ordem.Status = tarefa.estaFechada() ? SC_NosUpsertService.STATUS_FECHADO : 'New';
            conta(ordem, tarefa);
        }
    }

    /**
     * A conta do cliente, só na criação. Depois disso é do back office, que pode mudá-la
     * para uma conta filha ou para outra empresa do grupo, e a API não lhe volta a tocar.
     *
     * A marcação que a plataforma cria a seguir herda a conta da ordem sozinha, porque
     * `ServiceAppointment.AccountId` é derivado e não se escreve.
     */
    private void conta(WorkOrder ordem, SC_NosTarefa tarefa) {
        if (this.contaCliente != null) {
            ordem.AccountId = this.contaCliente;
            return;
        }
        if (this.avisoDaContaDado) {
            return;
        }
        this.avisoDaContaDado = true;
        aviso(tarefa.id, 'WorkOrder.AccountId',
            'Conta do cliente não encontrada (NIF ' + SC_NosConfig.nifDaContaCliente()
                + ', nome ' + SC_NosConfig.nomeDaContaCliente() + ').',
            null);
    }

    // ------------------------------------------------------------------
    // Linhas da tabela
    // ------------------------------------------------------------------

    private void estado(WorkOrder ordem, SC_NosTarefa tarefa) {
        if (String.isBlank(tarefa.estado)) {
            return;
        }
        ordem.Estado_Cliente__c = tarefa.estado;
        if (!ESTADOS_CONHECIDOS.contains(tarefa.estado)) {
            aviso(tarefa.id, 'WorkOrder.Estado_Cliente__c',
                'Estado novo na NOS: ' + tarefa.estado, tarefa.estado);
        }
    }

    private void tipoDeTrabalho(WorkOrder ordem, SC_NosTarefa tarefa, Boolean nova) {
        WorkType tipo = String.isBlank(tarefa.tipoPedido) ? null : tiposPorCodigo.get(tarefa.tipoPedido);
        if (tipo == null) {
            if (nova) {
                // Sem tipo não há família nem avença: o estado de facturação fica por decidir.
                aviso(tarefa.id, 'WorkOrder.WorkTypeId',
                    'Tipo de ordem sem correspondência no catálogo: ' + tarefa.tipoPedido, tarefa.resumo);
            }
            return;
        }
        ordem.WorkTypeId = tipo.Id;
        prioridade(ordem, tarefa, tipo);
        if (nova) {
            ordem.Estado_Facturacao__c = tipo.Dentro_Avenca__c == true
                ? 'Não aplicável (avença)'
                : 'Por facturar';
        }
    }

    private void prioridade(WorkOrder ordem, SC_NosTarefa tarefa, WorkType tipo) {
        if (String.isBlank(tarefa.prioridade) || !FAMILIA_AVARIA.equals(tipo.Familia__c)) {
            return;
        }
        // Fora das quatro conhecidas o valor fica só em Prioridade_Cliente__c: a
        // picklist standard é restrita e um valor novo faria a ordem inteira falhar.
        if (PRIORIDADES_PADRAO.contains(tarefa.prioridade)) {
            ordem.Priority = tarefa.prioridade;
        } else {
            aviso(tarefa.id, 'WorkOrder.Priority',
                'Prioridade fora das conhecidas: ' + tarefa.prioridade, tarefa.prioridade);
        }
    }

    private void territorio(WorkOrder ordem, SC_NosTarefa tarefa) {
        if (String.isBlank(tarefa.grupo)) {
            return;
        }
        ServiceTerritory territorio = territoriosPorCodigo.get(tarefa.grupo);
        if (territorio == null) {
            aviso(tarefa.id, 'WorkOrder.ServiceTerritoryId',
                'Grupo da NOS sem território correspondente: ' + tarefa.grupo, tarefa.resumo);
            return;
        }
        ordem.ServiceTerritoryId = territorio.Id;
    }

    private void tecnico(WorkOrder ordem, SC_NosTarefa tarefa) {
        ordem.Codigo_Utilizador_Cliente_Origem__c = corta(tarefa.utilizador, 40);
        // Não atribuímos recursos nem marcações: o despacho é humano. Só sinalizamos.
        ordem.Recurso_Por_Mapear__c = String.isNotBlank(tarefa.utilizador)
            && !codigosDeRecurso.contains(tarefa.utilizador);
    }

    private void textos(WorkOrder ordem, SC_NosTarefa tarefa) {
        if (String.isNotBlank(tarefa.resumo)) {
            ordem.Subject = corta(tarefa.resumo, TECTO_ASSUNTO);
        }
        // A descrição só existe no detalhe: numa listagem não se apaga o que já lá está.
        if (tarefa.veioDoDetalhe) {
            ordem.Description = descricao(tarefa);
        }
    }

    /** Notas sem HTML, seguidas das interacções da NOS, uma por linha. */
    @TestVisible
    private static String descricao(SC_NosTarefa tarefa) {
        List<String> blocos = new List<String>();
        String notas = SC_NosParser.textoSemHtml(tarefa.notas);
        if (String.isNotBlank(notas)) {
            blocos.add(notas);
        }
        if (tarefa.interaccoes != null && !tarefa.interaccoes.isEmpty()) {
            List<String> linhas = new List<String>{ 'Interacções na NOS' };
            for (SC_NosTarefa.Interaccao interaccao : tarefa.interaccoes) {
                String data = interaccao.criadaEm == null
                    ? 'sem data'
                    : interaccao.criadaEm.format('yyyy-MM-dd HH:mm', SC_NosConfig.fuso());
                String descricaoCurta = String.isNotBlank(interaccao.resumo) ? interaccao.resumo : interaccao.notas;
                linhas.add(data + ' · ' + (String.isBlank(interaccao.tipo) ? 'Interacção' : interaccao.tipo) +
                    ' · ' + SC_NosParser.textoSemHtml(descricaoCurta));
            }
            blocos.add(String.join(linhas, '\n'));
        }
        return blocos.isEmpty() ? null : String.join(blocos, '\n\n').abbreviate(TECTO_DESCRICAO);
    }

    // ------------------------------------------------------------------
    // Apoio
    // ------------------------------------------------------------------

    private void aviso(String chaveOrigem, String campo, String mensagem, String conteudo) {
        ocorrencias.add(SC_NosLote.ocorrencia(
            loteId, SC_NosLote.TIPO_AVISO, chaveOrigem, campo, mensagem, conteudo
        ));
    }

    private static String corta(String valor, Integer tecto) {
        return String.isBlank(valor) ? null : valor.abbreviate(tecto);
    }
}