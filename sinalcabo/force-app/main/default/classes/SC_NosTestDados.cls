/**
 * Dados de referência para os testes da entrada da NOS.
 *
 * Os testes correm sem SeeAllData, por isso o catálogo cria-se aqui: os dois
 * territórios de grupo com o respectivo código, uma zona filha em cada um, os tipos de
 * ordem com o código da NOS e a marca de avença, as células que aparecem nos fixtures e
 * um recurso com código de técnico.
 *
 * A hierarquia é a da org: o território de grupo é o pai (TL2-Sinalcabo, TS2-Sinalcabo),
 * as zonas da NOS são filhas, e é numa zona que a célula vive. A `YKM01` fica pendurada
 * directamente no pai, como as 24 células que só o KML conhece e que a NOS não põe em
 * zona nenhuma: é ela que exercita o ramo "sem pai" da regra da divergência.
 *
 * O recurso nasce com ResourceType 'D' de propósito: a plataforma só deixa um recurso
 * técnico por utilizador e o utilizador que corre os testes já tem o dele na org.
 * O mapeador procura o recurso pelo código e não pelo tipo, por isso a escolha não
 * muda o que se está a testar.
 */
@IsTest
public class SC_NosTestDados {
    public static final String GRUPO_TEJO = 'TL2-Sinalcabo';
    public static final String GRUPO_SUL = 'TS2-Sinalcabo';
    /** As zonas da NOS, filhas dos territórios de grupo. A chave é "grupo|zona". */
    public static final String ZONA_TEJO = GRUPO_TEJO + '|Zona Centro 1';
    public static final String ZONA_SUL = GRUPO_SUL + '|Zona Sul 1';
    /** Código de técnico que existe na listagem de fixture SC_NosFx_ListaOk. */
    public static final String CODIGO_TECNICO = 'U9351539';

    /** Os territórios de grupo (os pais), pelo código do grupo da NOS. */
    public static Map<String, Id> territoriosPorCodigo = new Map<String, Id>();
    /** As zonas (os filhos), pelo código da zona. */
    public static Map<String, Id> zonasPorCodigo = new Map<String, Id>();
    public static Map<String, Id> celulasPorCodigo = new Map<String, Id>();

    /** Cria territórios, tipos de ordem, células, recurso e a conta do operador. */
    public static void catalogo() {
        criarTerritorios();
        criarTiposDeOrdem();
        criarCelulas();
        criarRecurso(CODIGO_TECNICO);
        criarContaCliente();
    }

    /**
     * A conta a que as ordens ficam ligadas, com o NIF e o nome que a configuração da org
     * manda. Lê-se da configuração e não se escreve à mão aqui, para uma mudança no custom
     * metadata não deixar os testes a apontar para uma conta que já não é a certa.
     */
    public static Account criarContaCliente() {
        String nif = SC_NosConfig.nifDaContaCliente();
        String nome = SC_NosConfig.nomeDaContaCliente();
        Account conta = new Account(
            Name = String.isBlank(nome) ? 'Operador de teste' : nome,
            NIF__c = String.isBlank(nif) ? '999999990' : nif
        );
        insert conta;
        return conta;
    }

    public static void criarTerritorios() {
        OperatingHours horario = new OperatingHours(Name = 'SC FS Teste', TimeZone = 'Europe/Lisbon');
        insert horario;
        List<ServiceTerritory> territorios = new List<ServiceTerritory>{
            new ServiceTerritory(
                Name = 'Tejo (TL2)', OperatingHoursId = horario.Id, IsActive = true,
                Codigo_Grupo_Cliente__c = GRUPO_TEJO
            ),
            new ServiceTerritory(
                Name = 'Sul (TS2)', OperatingHoursId = horario.Id, IsActive = true,
                Codigo_Grupo_Cliente__c = GRUPO_SUL
            )
        };
        insert territorios;
        for (ServiceTerritory territorio : territorios) {
            territoriosPorCodigo.put(territorio.Codigo_Grupo_Cliente__c, territorio.Id);
        }
        // As zonas da NOS: filhas do território de grupo, com o horário do pai.
        List<ServiceTerritory> zonas = new List<ServiceTerritory>{
            new ServiceTerritory(
                Name = 'Zona Centro 1', OperatingHoursId = horario.Id, IsActive = true,
                ParentTerritoryId = territoriosPorCodigo.get(GRUPO_TEJO),
                Codigo_Zona_Cliente__c = ZONA_TEJO
            ),
            new ServiceTerritory(
                Name = 'Zona Sul 1', OperatingHoursId = horario.Id, IsActive = true,
                ParentTerritoryId = territoriosPorCodigo.get(GRUPO_SUL),
                Codigo_Zona_Cliente__c = ZONA_SUL
            )
        };
        insert zonas;
        for (ServiceTerritory zona : zonas) {
            zonasPorCodigo.put(zona.Codigo_Zona_Cliente__c, zona.Id);
        }
    }

    public static void criarTiposDeOrdem() {
        insert new List<WorkType>{
            tipo('OTI-RA1', 'Avaria', true),
            tipo('OTI-RA2', 'Avaria', true),
            tipo('OTI-RA3', 'Avaria', true),
            tipo('OTI-MR0', 'Avaria', true),
            tipo('OTM-MR0', 'Manutenção', true),
            // O único fora da avença: é o que prova o "Por facturar" na criação.
            tipo('OTU-ALF', 'Obra', false)
        };
    }

    public static WorkType tipo(String codigo, String familia, Boolean avenca) {
        return new WorkType(
            Name = codigo,
            Codigo_Cliente__c = codigo,
            Familia__c = familia,
            Dentro_Avenca__c = avenca,
            EstimatedDuration = 120,
            DurationType = 'Minutes',
            ShouldAutoCreateSvcAppt = false
        );
    }

    /**
     * Liga a criação automática da marcação num tipo de ordem. Na org os tipos vêm
     * todos com ela ligada; nos testes fica desligada por omissão, para os cenários que
     * não são sobre marcações não arrastarem o que a plataforma cria sozinha.
     */
    public static void ligarMarcacaoAutomatica(String codigo) {
        WorkType tipo = [SELECT Id FROM WorkType WHERE Codigo_Cliente__c = :codigo LIMIT 1];
        tipo.ShouldAutoCreateSvcAppt = true;
        update tipo;
    }

    public static void criarCelulas() {
        // A célula vive na ZONA e não no território de grupo. O pai só entra na YKM01,
        // que é a célula sem zona na NOS.
        Id tejo = zonasPorCodigo.get(ZONA_TEJO);
        Id sul = zonasPorCodigo.get(ZONA_SUL);
        List<Celula__c> celulas = new List<Celula__c>{
            // BAR03 fica numa zona do Tejo e a NOS atribui as ordens dela ao grupo do
            // Sul: é o caso de divergência de território que o Sinal tem de mostrar.
            celula('BAR03', tejo, 'HFC', 38.736946, -9.142685, true),
            celula('ESO09', sul, 'HFC', 38.700000, -9.200000, true),
            celula('MAS17', sul, 'FTTH', 38.710000, -9.210000, true),
            celula('ALM13', sul, 'HFC', 38.720000, -9.220000, true),
            celula('COR15', sul, 'HFC', 38.730000, -9.230000, true),
            celula('CAI04', tejo, 'FTTH', 38.740000, -9.240000, true),
            celula('CAI07', tejo, 'HFC', 38.750000, -9.250000, true),
            celula('ALB06', sul, 'HFC', 38.760000, -9.260000, true),
            celula('ABD01', tejo, 'HFC', 38.770000, -9.270000, true),
            celula('AMA06', tejo, 'HFC', 38.780000, -9.280000, true),
            celula('YCL02', tejo, 'FTTH', 38.790000, -9.290000, true),
            celula('YPI12', sul, 'HFC', 38.800000, -9.300000, true),
            celula('STB51', sul, 'HFC', 38.810000, -9.310000, true),
            // Sem zona na NOS: pendurada no território de grupo, como as 24 do KML.
            celula('YKM01', territoriosPorCodigo.get(GRUPO_SUL), 'FTTH', 38.830000, -9.330000, true),
            // Desactivada: o extractor não a pode propor.
            celula('INA01', tejo, 'HFC', 38.820000, -9.320000, false)
        };
        insert celulas;
        for (Celula__c celula : celulas) {
            celulasPorCodigo.put(celula.Codigo__c, celula.Id);
        }
    }

    public static Celula__c celula(
        String codigo, Id territorio, String tecnologia, Decimal latitude, Decimal longitude, Boolean activa
    ) {
        return new Celula__c(
            Name = codigo,
            Codigo__c = codigo,
            Territorio__c = territorio,
            Tecnologia__c = tecnologia,
            Localizacao__Latitude__s = latitude,
            Localizacao__Longitude__s = longitude,
            Activa__c = activa
        );
    }

    public static ServiceResource criarRecurso(String codigo) {
        ServiceResource recurso = new ServiceResource(
            Name = 'Técnico de teste',
            RelatedRecordId = UserInfo.getUserId(),
            ResourceType = 'D',
            IsActive = true,
            Codigo_Utilizador_Cliente__c = codigo
        );
        insert recurso;
        return recurso;
    }

    /**
     * Um Id sintético do tipo pedido, para exercitar uma regra pura sem tocar na base de
     * dados. `indice` distingue os Ids entre si; nunca corresponde a um registo real.
     */
    public static Id idFalso(Schema.SObjectType tipo, Integer indice) {
        String sufixo = String.valueOf(indice);
        return Id.valueOf(tipo.getDescribe().getKeyPrefix()
            + '000000000000'.substring(0, 12 - sufixo.length()) + sufixo);
    }

    /** Lote aberto, para as classes que precisam de um pai para as ocorrências. */
    public static Lote_Integracao__c lote() {
        return lote(SC_NosConfig.CORRIDA_ABERTAS);
    }

    public static Lote_Integracao__c lote(String tipoCorrida) {
        Datetime agora = Datetime.now();
        return SC_NosLote.abrirRepetivel(tipoCorrida, agora.addHours(-1), agora);
    }

    /** Corpo de um static resource de fixture. */
    public static String fixture(String nome) {
        return SC_NosMockFactory.corpoDoRecurso(nome);
    }

    /** Uma linha de listagem construída à mão, para os casos que os fixtures não têm. */
    public static String listagem(String linhasJson) {
        return '{"result_message":"Success","result_code":0,"result_data":{"data":[' + linhasJson + '],"count":1}}';
    }

    /** Uma tarefa mínima, para testar o mapeador sem passar pelo parser. */
    public static SC_NosTarefa tarefa(String id, String estado, String tipoPedido, String grupo) {
        SC_NosTarefa tarefa = new SC_NosTarefa();
        tarefa.id = id;
        tarefa.referenciaOcorrencia = 'INC' + id;
        tarefa.estado = estado;
        tarefa.tipoPedido = tipoPedido;
        tarefa.grupo = grupo;
        tarefa.prioridade = 'Medium';
        tarefa.utilizador = CODIGO_TECNICO;
        tarefa.resumo = tipoPedido + ' BAR03 - 3A4 - Rua Exemplo, 1 - Sem Sinal';
        tarefa.contrato = 'SPGLOBAL';
        tarefa.dataAtribuicao = Datetime.newInstanceGmt(2026, 8, 4, 7, 9, 9);
        tarefa.dataInicio = Datetime.newInstanceGmt(2026, 8, 4, 7, 9, 14);
        return tarefa;
    }
}