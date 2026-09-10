/**
 * Testa o flow SC_FS_Marcacao_Copiar_Ordem: a marcação que nasce de uma ordem tem de
 * ficar com Ordem__c preenchido, senão os cinco campos espelho da consola ficam vazios.
 *
 * A plataforma cria a marcação sozinha quando a ordem nasce com um tipo de trabalho
 * marcado para isso. Se essa criação automática não disparar no contexto de teste, o
 * teste cria a marcação à mão: o que se está a provar é o flow, não a plataforma.
 */
@IsTest
private class SC_FS_Marcacao_Copiar_OrdemTest {

    @TestSetup
    static void catalogo() {
        OperatingHours horario = new OperatingHours(Name = 'SC FS F4 Marcação', TimeZone = 'Europe/Lisbon');
        insert horario;
        insert new ServiceTerritory(
            Name = 'F4 Marcação Tejo', OperatingHoursId = horario.Id, IsActive = true
        );
        insert new WorkType(
            Name = 'F4-AUTO',
            Codigo_Cliente__c = 'F4-AUTO',
            Familia__c = 'Avaria',
            Dentro_Avenca__c = true,
            EstimatedDuration = 120,
            DurationType = 'Minutes',
            ShouldAutoCreateSvcAppt = true
        );
    }

    private static WorkOrder criarOrdem() {
        WorkType tipo = [SELECT Id FROM WorkType WHERE Codigo_Cliente__c = 'F4-AUTO' LIMIT 1];
        ServiceTerritory territorio = [SELECT Id FROM ServiceTerritory WHERE Name = 'F4 Marcação Tejo' LIMIT 1];
        WorkOrder ordem = new WorkOrder(
            Subject = 'Avaria com marcação',
            Status = 'New',
            WorkTypeId = tipo.Id,
            ServiceTerritoryId = territorio.Id,
            StartDate = Datetime.now(),
            EndDate = Datetime.now().addHours(2),
            Referencia_Ordem_Cliente__c = 'F4M-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert ordem;
        return ordem;
    }

    @IsTest
    static void aMarcacaoDaOrdemFicaComAOrdemPreenchida() {
        Test.startTest();
        WorkOrder ordem = criarOrdem();

        List<ServiceAppointment> automaticas = [
            SELECT Id, Ordem__c, ParentRecordId FROM ServiceAppointment WHERE ParentRecordId = :ordem.Id
        ];
        if (automaticas.isEmpty()) {
            // A criação automática não disparou neste contexto: cria-se à mão, porque o
            // que se está a provar é o flow que copia o pai para o campo próprio.
            insert new ServiceAppointment(
                ParentRecordId = ordem.Id,
                Subject = 'Marcação à mão',
                EarliestStartTime = Datetime.now(),
                DueDate = Datetime.now().addHours(4)
            );
        }
        Test.stopTest();

        List<ServiceAppointment> marcacoes = [
            SELECT Id, Ordem__c FROM ServiceAppointment WHERE ParentRecordId = :ordem.Id
        ];
        Assert.isFalse(marcacoes.isEmpty(), 'A ordem tem de ter pelo menos uma marcação.');
        for (ServiceAppointment marcacao : marcacoes) {
            Assert.areEqual(
                ordem.Id, marcacao.Ordem__c,
                'O flow tem de copiar o registo pai para Ordem__c, senão os espelhos ficam vazios.'
            );
        }
    }

    @IsTest
    static void osEspelhosLeemAOrdemDepoisDaCopia() {
        WorkOrder ordem = criarOrdem();
        ordem.Estado_Cliente__c = 'CLOSED';
        ordem.Classificacao_Confirmada__c = true;
        update ordem;

        Test.startTest();
        insert new ServiceAppointment(
            ParentRecordId = ordem.Id,
            Subject = 'Marcação para os espelhos',
            EarliestStartTime = Datetime.now(),
            DueDate = Datetime.now().addHours(4)
        );
        Test.stopTest();

        ServiceAppointment marcacao = [
            SELECT Ordem__c, Estado_Cliente__c, Sinal_Classificacao__c, Resumo_Cliente__c
            FROM ServiceAppointment
            WHERE ParentRecordId = :ordem.Id AND Subject = 'Marcação para os espelhos'
            LIMIT 1
        ];
        Assert.areEqual(ordem.Id, marcacao.Ordem__c, 'A cópia da ordem é a condição dos espelhos.');
        Assert.areEqual('Fechada', marcacao.Estado_Cliente__c, 'O espelho traduz o estado da NOS para português.');
        Assert.areEqual(
            'Avaria com marcação', marcacao.Resumo_Cliente__c,
            'O resumo da marcação são os primeiros 80 caracteres do assunto da ordem.'
        );
        Assert.isTrue(
            marcacao.Sinal_Classificacao__c.contains('Classificada'),
            'Com a classificação confirmada e sem divergência, o sinal diz Classificada.'
        );
    }

    @IsTest
    static void marcacaoComPaiQueNaoEOrdemFicaSemOrdem() {
        Account conta = new Account(Name = 'Conta de teste F4');
        insert conta;

        Test.startTest();
        insert new ServiceAppointment(
            ParentRecordId = conta.Id,
            Subject = 'Marcação de conta',
            EarliestStartTime = Datetime.now(),
            DueDate = Datetime.now().addHours(4)
        );
        Test.stopTest();

        ServiceAppointment marcacao = [
            SELECT Ordem__c FROM ServiceAppointment WHERE ParentRecordId = :conta.Id LIMIT 1
        ];
        Assert.isNull(
            marcacao.Ordem__c,
            'Só um pai que comece por 0WO é ordem de trabalho; o resto não pode entrar no lookup.'
        );
    }
}