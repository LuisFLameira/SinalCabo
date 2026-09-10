/**
 * Testa o flow SC_FS_Ordem_Copiar_Celula: quando a célula da ordem muda, o flow copia
 * tecnologia, território e coordenadas da célula, e recalcula a divergência de território.
 *
 * O território de uma célula é a zona da NOS, que é um território filho do território do
 * grupo, por isso a divergência mede-se ao nível do pai: a zona da célula pertence ao
 * território do grupo que a NOS atribuiu à ordem? Comparar a zona com o grupo directamente
 * daria divergência em todas as ordens.
 *
 * O flow é after-save e só corre em actualização, por isso os testes mudam sempre o
 * lookup num segundo DML. Se o flow entrar inactivo na org, todas as asserções caem.
 */
@IsTest
private class SC_FS_Ordem_Copiar_CelulaTest {
    private static final String COD_TEJO = 'FSTEJO01';
    private static final String COD_TEJO_2 = 'FSTEJO02';
    private static final String COD_SUL = 'FSSUL001';
    /** Célula pendurada no território de grupo, sem zona, como as que só o KML conhece. */
    private static final String COD_SEM_ZONA = 'FSTEJO03';

    private static final String GRUPO_TEJO = 'F4-TL2';
    private static final String GRUPO_SUL = 'F4-TS2';

    @TestSetup
    static void catalogo() {
        OperatingHours horario = new OperatingHours(Name = 'SC FS F4 Teste', TimeZone = 'Europe/Lisbon');
        insert horario;
        // Os pais: os territórios de grupo, com o código que a NOS manda na ordem.
        List<ServiceTerritory> grupos = new List<ServiceTerritory>{
            new ServiceTerritory(
                Name = 'F4 Tejo', OperatingHoursId = horario.Id, IsActive = true,
                Codigo_Grupo_Cliente__c = GRUPO_TEJO
            ),
            new ServiceTerritory(
                Name = 'F4 Sul', OperatingHoursId = horario.Id, IsActive = true,
                Codigo_Grupo_Cliente__c = GRUPO_SUL
            )
        };
        insert grupos;
        // Os filhos: as zonas da NOS, duas no Tejo e uma no Sul.
        List<ServiceTerritory> zonas = new List<ServiceTerritory>{
            new ServiceTerritory(
                Name = 'F4 Zona Tejo 1', OperatingHoursId = horario.Id, IsActive = true,
                ParentTerritoryId = grupos[0].Id, Codigo_Zona_Cliente__c = GRUPO_TEJO + '|Zona 1'
            ),
            new ServiceTerritory(
                Name = 'F4 Zona Tejo 2', OperatingHoursId = horario.Id, IsActive = true,
                ParentTerritoryId = grupos[0].Id, Codigo_Zona_Cliente__c = GRUPO_TEJO + '|Zona 2'
            ),
            new ServiceTerritory(
                Name = 'F4 Zona Sul 1', OperatingHoursId = horario.Id, IsActive = true,
                ParentTerritoryId = grupos[1].Id, Codigo_Zona_Cliente__c = GRUPO_SUL + '|Zona 1'
            )
        };
        insert zonas;

        insert new List<Celula__c>{
            celula(COD_TEJO, zonas[0].Id, 'HFC', 38.711111, -9.111111),
            celula(COD_TEJO_2, zonas[1].Id, 'FTTH', 38.722222, -9.222222),
            celula(COD_SUL, zonas[2].Id, 'FTTH', 38.733333, -9.333333),
            celula(COD_SEM_ZONA, grupos[0].Id, 'HFC', 38.744444, -9.444444)
        };
    }

    private static Celula__c celula(String codigo, Id territorio, String tecnologia, Decimal lat, Decimal lon) {
        return new Celula__c(
            Name = codigo,
            Codigo__c = codigo,
            Territorio__c = territorio,
            Tecnologia__c = tecnologia,
            Localidade__c = 'Lisboa',
            Ruas_Conhecidas__c = 'Rua de Teste; Rua do Exemplo',
            Localizacao__Latitude__s = lat,
            Localizacao__Longitude__s = lon,
            Activa__c = true
        );
    }

    private static Celula__c porCodigo(String codigo) {
        return [
            SELECT Id, Territorio__c, Tecnologia__c, Localizacao__Latitude__s, Localizacao__Longitude__s
            FROM Celula__c
            WHERE Codigo__c = :codigo
            LIMIT 1
        ];
    }

    private static Id territorioPorNome(String nome) {
        return [SELECT Id FROM ServiceTerritory WHERE Name = :nome LIMIT 1].Id;
    }

    private static WorkOrder ordemNaCelula(Celula__c origem) {
        return ordemNaCelula(origem, false, GRUPO_TEJO);
    }

    private static WorkOrder ordemNaCelula(Celula__c origem, Boolean confirmada, String grupoDaNos) {
        WorkOrder ordem = new WorkOrder(
            Subject = 'Avaria de teste',
            Status = 'New',
            Celula__c = origem.Id,
            Tecnologia__c = origem.Tecnologia__c,
            ServiceTerritoryId = origem.Territorio__c,
            Grupo_Cliente__c = grupoDaNos,
            Classificacao_Confirmada__c = confirmada,
            Referencia_Ordem_Cliente__c = 'F4-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert ordem;
        return ordem;
    }

    private static WorkOrder reler(Id ordemId) {
        return [
            SELECT Tecnologia__c, ServiceTerritoryId, Latitude, Longitude, Divergencia_Territorio__c
            FROM WorkOrder
            WHERE Id = :ordemId
        ];
    }

    @IsTest
    static void numaOrdemJaConfirmadaADivergenciaFicaAFalso() {
        Celula__c tejo = porCodigo(COD_TEJO);
        Celula__c sul = porCodigo(COD_SUL);
        WorkOrder ordem = ordemNaCelula(tejo, true, GRUPO_TEJO);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = sul.Id);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual(sul.Territorio__c, depois.ServiceTerritoryId, 'O território tem de vir da célula escolhida.');
        Assert.isFalse(
            depois.Divergencia_Territorio__c,
            'A classificação já está confirmada: o despachante assumiu a célula e a divergência não se levanta.'
        );
    }

    @IsTest
    static void zonaDeOutroGrupoCopiaTudoELevantaADivergencia() {
        Celula__c tejo = porCodigo(COD_TEJO);
        Celula__c sul = porCodigo(COD_SUL);
        WorkOrder ordem = ordemNaCelula(tejo);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = sul.Id);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual('FTTH', depois.Tecnologia__c, 'A tecnologia tem de vir da célula escolhida.');
        Assert.areEqual(sul.Territorio__c, depois.ServiceTerritoryId, 'O território tem de ser a zona da célula escolhida.');
        Assert.isTrue(
            Math.abs(depois.Latitude - sul.Localizacao__Latitude__s) < 0.000001,
            'A latitude tem de vir da célula escolhida.'
        );
        Assert.isTrue(
            Math.abs(depois.Longitude - sul.Localizacao__Longitude__s) < 0.000001,
            'A longitude tem de vir da célula escolhida.'
        );
        Assert.isTrue(
            depois.Divergencia_Territorio__c,
            'A zona da célula é filha do Sul e a NOS deu o grupo do Tejo: divergência.'
        );
    }

    @IsTest
    static void outraZonaDoMesmoGrupoMudaOTerritorioSemDivergencia() {
        Celula__c tejo = porCodigo(COD_TEJO);
        Celula__c tejoDois = porCodigo(COD_TEJO_2);
        WorkOrder ordem = ordemNaCelula(tejo);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = tejoDois.Id);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual('FTTH', depois.Tecnologia__c, 'A tecnologia tem de vir da segunda célula.');
        Assert.areEqual(
            tejoDois.Territorio__c, depois.ServiceTerritoryId,
            'A ordem passa para a zona nova, que é o território da célula escolhida.'
        );
        Assert.areNotEqual(
            tejo.Territorio__c, depois.ServiceTerritoryId,
            'E deixa de estar na zona antiga: são duas zonas diferentes do mesmo grupo.'
        );
        Assert.isFalse(
            depois.Divergencia_Territorio__c,
            'As duas zonas são filhas do mesmo território de grupo: não há divergência.'
        );
    }

    @IsTest
    static void celulaSemZonaFicaNoGrupoESemDivergencia() {
        Celula__c tejo = porCodigo(COD_TEJO);
        Celula__c semZona = porCodigo(COD_SEM_ZONA);
        WorkOrder ordem = ordemNaCelula(tejo);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = semZona.Id);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual(
            territorioPorNome('F4 Tejo'), depois.ServiceTerritoryId,
            'A célula sem zona está no território de grupo, e é para lá que a ordem vai.'
        );
        Assert.isFalse(
            depois.Divergencia_Territorio__c,
            'Um território sem pai compara-se consigo próprio, e é o grupo que a NOS deu.'
        );
    }

    @IsTest
    static void ordemSemGrupoDaNosNaoLevantaDivergencia() {
        Celula__c tejo = porCodigo(COD_TEJO);
        Celula__c sul = porCodigo(COD_SUL);
        // Ordem criada à mão na org, sem grupo da NOS: não há grupo com que comparar.
        WorkOrder ordem = ordemNaCelula(tejo, false, null);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = sul.Id);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual(sul.Territorio__c, depois.ServiceTerritoryId, 'O território vem da célula na mesma.');
        Assert.isFalse(
            depois.Divergencia_Territorio__c,
            'Sem grupo da NOS não há divergência: não existe o outro lado da comparação.'
        );
    }

    @IsTest
    static void limparACelulaNaoDisparaACopia() {
        Celula__c tejo = porCodigo(COD_TEJO);
        WorkOrder ordem = ordemNaCelula(tejo);

        Test.startTest();
        update new WorkOrder(Id = ordem.Id, Celula__c = null);
        Test.stopTest();

        WorkOrder depois = reler(ordem.Id);
        Assert.areEqual(
            tejo.Territorio__c, depois.ServiceTerritoryId,
            'Sem célula o flow não corre, e o território que lá estava tem de ficar como estava.'
        );
        Assert.isFalse(depois.Divergencia_Territorio__c, 'Sem célula não há divergência a calcular.');
    }
}