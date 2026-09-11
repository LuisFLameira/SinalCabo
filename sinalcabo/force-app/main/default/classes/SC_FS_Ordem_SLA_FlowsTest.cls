/**
 * Testa os cinco flows de SLA da F6b: arranque, fecho do técnico pela ordem, fecho do
 * técnico pela marcação, conclusão dos milestones e paragem.
 *
 * Porque há métodos com SeeAllData: o encaminhamento de SLA vive numa custom metadata que
 * aponta para Ids de tipo de trabalho, de direito de serviço e de horário. Direitos de
 * serviço, horários e processos são DADOS da org, e nenhum deles se cria em Apex (a
 * plataforma recusa DML em BusinessHours e um SlaProcess não é inserível). Um teste isolado
 * não consegue montar essa cadeia, por isso os testes que a atravessam correm contra o
 * catálogo real, e os que só exercem lógica nossa correm isolados.
 *
 * Se os flows entrarem inactivos na org, ou se o catálogo mudar de régua, estas asserções
 * caem: é o que se pretende.
 */
@IsTest
private class SC_FS_Ordem_SLA_FlowsTest {

    private static final String MOTIVO_SUSPENDE = 'Material da NOS';
    private static final String MOTIVO_NAO_SUSPENDE = 'Meios da SinalCabo';

    private static Account conta() {
        Account a = new Account(Name = 'SC FS Teste SLA');
        insert a;
        return a;
    }

    /** Tipo de trabalho sem código, portanto sem encaminhamento de SLA. */
    private static WorkType tipoSemSla() {
        WorkType w = new WorkType(Name = 'SC FS Teste SLA sem código',
                                  EstimatedDuration = 60, DurationType = 'Minutes');
        insert w;
        return w;
    }

    private static WorkOrder ordem(Id contaId, Id tipoId) {
        WorkOrder o = new WorkOrder(Subject = 'SC FS Teste SLA', AccountId = contaId,
                                    WorkTypeId = tipoId, Status = 'New',
                                    Data_Atribuicao_Cliente__c = System.now().addHours(-1));
        insert o;
        return o;
    }

    // ------------------------------------------------------------------ arranque

    @IsTest(SeeAllData=true)
    static void arranqueCarimbaODireitoEOHorario() {
        SC_FS_SLA_OT__mdt linha = [SELECT Codigo_OT__c, Work_Type_Id__c, Entitlement_Id__c,
                                          Business_Hours_Id__c
                                   FROM SC_FS_SLA_OT__mdt
                                   WHERE Work_Type_Id__c != null LIMIT 1];
        WorkOrder o = new WorkOrder(Subject = 'SC FS Teste SLA arranque',
                                    WorkTypeId = linha.Work_Type_Id__c, Status = 'New',
                                    Data_Atribuicao_Cliente__c = System.now().addHours(-2));
        Test.startTest();
        insert o;
        Test.stopTest();
        WorkOrder lida = [SELECT EntitlementId, BusinessHoursId, SlaStartDate,
                                 Data_Atribuicao_Cliente__c
                          FROM WorkOrder WHERE Id = :o.Id];
        Assert.areEqual(linha.Entitlement_Id__c, String.valueOf(lida.EntitlementId).left(18),
                        'o direito de serviço tem de vir do encaminhamento do tipo de trabalho');
        Assert.areEqual(linha.Business_Hours_Id__c, String.valueOf(lida.BusinessHoursId).left(18),
                        'o horário tem de vir do encaminhamento');
        Assert.areEqual(lida.Data_Atribuicao_Cliente__c, lida.SlaStartDate,
                        'o prazo arranca na hora da atribuição pela NOS, não na criação');
    }

    @IsTest(SeeAllData=true)
    static void arranqueNaoMexeNumaOrdemComPrazoACorrer() {
        List<SC_FS_SLA_OT__mdt> linhas = [SELECT Work_Type_Id__c, Entitlement_Id__c
                                          FROM SC_FS_SLA_OT__mdt
                                          WHERE Work_Type_Id__c != null LIMIT 2];
        Assert.areEqual(2, linhas.size(), 'o catálogo precisa de dois tipos de trabalho na org');
        WorkOrder o = new WorkOrder(Subject = 'SC FS Teste SLA sem troca',
                                    WorkTypeId = linhas[0].Work_Type_Id__c, Status = 'New',
                                    Data_Atribuicao_Cliente__c = System.now().addHours(-2));
        insert o;
        Id primeiro = [SELECT EntitlementId FROM WorkOrder WHERE Id = :o.Id].EntitlementId;
        Assert.isNotNull(primeiro, 'a primeira gravação tem de carimbar o direito de serviço');
        Test.startTest();
        update new WorkOrder(Id = o.Id, WorkTypeId = linhas[1].Work_Type_Id__c);
        Test.stopTest();
        Assert.areEqual(primeiro, [SELECT EntitlementId FROM WorkOrder WHERE Id = :o.Id].EntitlementId,
                        'com um prazo já a contar, mudar o tipo de trabalho não muda a régua');
    }

    // --------------------------------------------------------- fecho do técnico

    @IsTest
    static void fechoPelaOrdemUsaOFimDaIntervencaoNaNos() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Datetime fimNaNos = System.now().addMinutes(-90);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Status = 'Completed', Data_Fim_Cliente__c = fimNaNos);
        Test.stopTest();
        Assert.areEqual(fimNaNos, [SELECT Data_Fecho_Tecnico__c FROM WorkOrder WHERE Id = :o.Id].Data_Fecho_Tecnico__c,
                        'sem marcação, o fecho do técnico é o fim da última intervenção na NOS');
    }

    @IsTest
    static void fechoPelaOrdemSemDataDaNosUsaOMomentoDoFecho() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Datetime antes = System.now().addSeconds(-5);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Status = 'Closed');
        Test.stopTest();
        Datetime fecho = [SELECT Data_Fecho_Tecnico__c FROM WorkOrder WHERE Id = :o.Id].Data_Fecho_Tecnico__c;
        Assert.isNotNull(fecho, 'fechar a ordem sem data da NOS carimba a hora do fecho');
        Assert.isTrue(fecho >= antes, 'a data carimbada é a do momento do fecho');
    }

    @IsTest
    static void fechoNaoReescreveUmaDataQueJaExiste() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Datetime doTerreno = System.now().addDays(-2);
        update new WorkOrder(Id = o.Id, Data_Fecho_Tecnico__c = doTerreno);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Status = 'Completed', Data_Fim_Cliente__c = System.now());
        Test.stopTest();
        Assert.areEqual(doTerreno, [SELECT Data_Fecho_Tecnico__c FROM WorkOrder WHERE Id = :o.Id].Data_Fecho_Tecnico__c,
                        'uma data escrita à mão com prova do terreno não é reescrita pelo fecho');
    }

    @IsTest
    static void marcacaoConcluidaCarimbaOFechoNaOrdem() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Datetime fimReal = System.now().addMinutes(-20);
        ServiceAppointment m = new ServiceAppointment(ParentRecordId = o.Id, Ordem__c = o.Id,
                                                      Subject = 'SC FS Teste SLA marcação',
                                                      EarliestStartTime = System.now().addHours(-3),
                                                      DueDate = System.now().addHours(3));
        insert m;
        // A plataforma nao deixa saltar de None para Completed ("Cannot change status from
        // None to Completed"): a marcacao passa pelos estados como passa no terreno.
        for (String estado : new List<String>{'Scheduled', 'Dispatched', 'In Progress'}) {
            update new ServiceAppointment(Id = m.Id, Status = estado);
        }
        Test.startTest();
        update new ServiceAppointment(Id = m.Id, Status = 'Completed', ActualEndTime = fimReal,
                                      ActualStartTime = System.now().addMinutes(-60));
        Test.stopTest();
        Assert.areEqual(fimReal, [SELECT Data_Fecho_Tecnico__c FROM WorkOrder WHERE Id = :o.Id].Data_Fecho_Tecnico__c,
                        'o fecho do técnico é o fim real da marcação, que é a fonte precisa');
    }

    // ------------------------------------------------------------------ paragem

    @IsTest
    static void paragemDeTerceirosAbreRegistoESuspende() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Estado_Cliente__c = 'PENDING',
                             Motivo_Paragem__c = MOTIVO_SUSPENDE, Responsavel_Paragem__c = 'NOS');
        Test.stopTest();
        Assert.isTrue([SELECT IsStopped FROM WorkOrder WHERE Id = :o.Id].IsStopped,
                      'um motivo de terceiros suspende o relógio da ordem');
        List<Paragem_Ordem__c> ps = [SELECT Inicio__c, Fim__c, Motivo__c, Responsavel__c, Minutos__c
                                     FROM Paragem_Ordem__c WHERE Ordem__c = :o.Id];
        Assert.areEqual(1, ps.size(), 'a suspensão abre uma paragem, que é a prova contra a penalidade');
        Assert.areEqual(MOTIVO_SUSPENDE, ps[0].Motivo__c, 'a paragem guarda o motivo do momento');
        Assert.areEqual('NOS', ps[0].Responsavel__c, 'a paragem guarda o responsável do momento');
        Assert.isNotNull(ps[0].Inicio__c, 'a paragem tem de ter início');
        Assert.isNull(ps[0].Fim__c, 'uma paragem em curso não tem fim');
    }

    @IsTest
    static void sairDePendenteFechaAParagemESomaOsMinutos() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        update new WorkOrder(Id = o.Id, Estado_Cliente__c = 'PENDING',
                             Motivo_Paragem__c = MOTIVO_SUSPENDE, Responsavel_Paragem__c = 'NOS');
        // Recua o início para haver minutos a contar sem esperar pelo relógio.
        Paragem_Ordem__c p = [SELECT Id FROM Paragem_Ordem__c WHERE Ordem__c = :o.Id];
        update new Paragem_Ordem__c(Id = p.Id, Inicio__c = System.now().addMinutes(-30));
        Test.startTest();
        update new WorkOrder(Id = o.Id, Estado_Cliente__c = 'WORK_IN_PROGRESS');
        Test.stopTest();
        WorkOrder lida = [SELECT IsStopped, Minutos_Parado__c FROM WorkOrder WHERE Id = :o.Id];
        Assert.isFalse(lida.IsStopped, 'sair de Pendente retoma o relógio');
        Paragem_Ordem__c fechada = [SELECT Fim__c, Minutos__c FROM Paragem_Ordem__c WHERE Id = :p.Id];
        Assert.isNotNull(fechada.Fim__c, 'a paragem tem de fechar');
        Assert.isTrue(fechada.Minutos__c >= 29 && fechada.Minutos__c <= 31,
                      'trinta minutos parados contam trinta minutos, e deram ' + fechada.Minutos__c);
        Assert.areEqual(fechada.Minutos__c, lida.Minutos_Parado__c,
                        'o tempo parado da ordem é a soma dos minutos das paragens');
    }

    @IsTest
    static void motivoDaSinalCaboNaoSuspende() {
        Account a = conta();
        WorkType w = tipoSemSla();
        WorkOrder o = ordem(a.Id, w.Id);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Estado_Cliente__c = 'PENDING',
                             Motivo_Paragem__c = MOTIVO_NAO_SUSPENDE,
                             Responsavel_Paragem__c = 'SinalCabo');
        Test.stopTest();
        Assert.isFalse([SELECT IsStopped FROM WorkOrder WHERE Id = :o.Id].IsStopped,
                       'a falta de meios da SinalCabo não suspende o prazo do operador');
        Assert.areEqual(0, [SELECT COUNT() FROM Paragem_Ordem__c WHERE Ordem__c = :o.Id],
                        'sem suspensão não há paragem a registar');
    }

    // -------------------------------------------------------------- milestones

    @IsTest(SeeAllData=true)
    static void asDatasConcluemOsDoisPrazos() {
        SC_FS_SLA_OT__mdt linha = [SELECT Work_Type_Id__c FROM SC_FS_SLA_OT__mdt
                                   WHERE Work_Type_Id__c != null AND Tem_TE__c = true
                                     AND Tem_TEC__c = true LIMIT 1];
        WorkOrder o = new WorkOrder(Subject = 'SC FS Teste SLA milestones',
                                    WorkTypeId = linha.Work_Type_Id__c, Status = 'New',
                                    Data_Atribuicao_Cliente__c = System.now().addHours(-2));
        insert o;
        Datetime fecho = System.now().addMinutes(-30);
        Test.startTest();
        update new WorkOrder(Id = o.Id, Data_Fecho_Tecnico__c = fecho);
        update new WorkOrder(Id = o.Id, Data_Entrega_Cadastro__c = System.now());
        Test.stopTest();
        Map<String, EntityMilestone> porTipo = new Map<String, EntityMilestone>();
        for (EntityMilestone m : [SELECT MilestoneType.Name, CompletionDate, IsCompleted
                                  FROM EntityMilestone WHERE ParentEntityId = :o.Id]) {
            porTipo.put(m.MilestoneType.Name, m);
        }
        Assert.areEqual(2, porTipo.size(), 'o par de prazos tem de dar dois milestones');
        for (String tipo : porTipo.keySet()) {
            Assert.isTrue(porTipo.get(tipo).IsCompleted,
                          'o prazo ' + tipo + ' tem de ficar concluído quando a sua data é escrita');
        }
        Assert.areEqual(fecho, porTipo.get('TE (intervenção)').CompletionDate,
                        'a conclusão do TE é a data de fecho do técnico, não a hora da gravação');
    }
}