/**
 * SC_OpportunityPreVendaTeamHandlerTest
 * -------------------------------------------------------------------------
 * Cobre a reconciliacao do membro Pre-Venda da Opportunity Team a partir do
 * campo Opportunity.Pre_Venda_Lider__c.
 *
 * Cenarios:
 *  1. Insert com campo definido     -> cria membro Pre-Venda com acesso Edit + share.
 *  2. Limpar o campo                -> remove o membro Pre-Venda.
 *  3. Mudar de A para B             -> remove A, poe B.
 *  4. Pre-Venda == Owner            -> nao cria membro (sem erro).
 *  5. User ja na equipa noutro papel -> update do papel/acesso (sem duplicado).
 *  6. Bulk (200 opps)               -> bulkificacao.
 */
@IsTest
private class SC_OpportunityPreVendaTeamHandlerTest {

    private static final String ROLE_PRE_VENDA = 'Pré-Venda';

    /** Cria utilizadores activos com um perfil standard para usar como membros de equipa. */
    private static List<User> makeUsers(Integer howMany) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        String uid = String.valueOf(Datetime.now().getTime());
        for (Integer i = 0; i < howMany; i++) {
            users.add(new User(
                FirstName = 'PreVenda',
                LastName  = 'Tester' + i,
                Alias     = 'pvt' + i,
                Email     = 'pv.tester' + i + '.' + uid + '@trh-sc-test.com',
                Username  = 'pv.tester' + i + '.' + uid + '@trh-sc-test.com',
                CommunityNickname = 'pvt' + i + uid,
                ProfileId = p.Id,
                TimeZoneSidKey   = 'Europe/Lisbon',
                LocaleSidKey     = 'pt_PT',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                IsActive  = true
            ));
        }
        insert users;
        return users;
    }

    private static Opportunity makeOpp(Id preVendaUserId) {
        return new Opportunity(
            Name             = 'Opp ' + Math.abs(Crypto.getRandomLong()),
            StageName        = 'Identificada',
            CloseDate        = Date.today().addDays(30),
            Empresa_Lider__c = 'Sinalcabo',
            Pre_Venda_Lider__c = preVendaUserId
        );
    }

    private static List<OpportunityTeamMember> preVendaMembers(Id oppId) {
        return [
            SELECT Id, UserId, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE OpportunityId = :oppId AND TeamMemberRole = :ROLE_PRE_VENDA
        ];
    }

    // 1. Insert com campo definido -> membro Pre-Venda com acesso Edit + share aberta.
    @IsTest
    static void testInsertCreatesPreVendaMemberWithEdit() {
        User u = makeUsers(1)[0];
        Opportunity opp;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            opp = makeOpp(u.Id);
            Test.startTest();
            insert opp;
            Test.stopTest();
        }

        List<OpportunityTeamMember> members = preVendaMembers(opp.Id);
        System.assertEquals(1, members.size(), 'Devia existir exactamente 1 membro Pre-Venda.');
        System.assertEquals(u.Id, members[0].UserId, 'O membro devia ser o user do campo.');
        System.assertEquals('Edit', members[0].OpportunityAccessLevel, 'Acesso devia ser Edit.');

        // Confirma que a share foi criada com acesso Edit (a OWD e' Private).
        List<OpportunityShare> shares = [
            SELECT OpportunityAccessLevel, RowCause
            FROM OpportunityShare
            WHERE OpportunityId = :opp.Id AND UserOrGroupId = :u.Id
        ];
        System.assertEquals(1, shares.size(), 'Devia existir uma OpportunityShare para o membro.');
        System.assertEquals('Edit', shares[0].OpportunityAccessLevel, 'A share devia ser Edit.');

        // runAs do user de Pre-Venda confirma visibilidade da opp.
        System.runAs(u) {
            List<Opportunity> visiveis = [SELECT Id FROM Opportunity WHERE Id = :opp.Id];
            System.assertEquals(1, visiveis.size(),
                'O user de Pre-Venda devia passar a ver a oportunidade.');
        }
    }

    // 2. Limpar o campo -> remove o membro Pre-Venda.
    @IsTest
    static void testClearFieldRemovesMember() {
        User u = makeUsers(1)[0];
        Opportunity opp = makeOpp(u.Id);
        insert opp;
        System.assertEquals(1, preVendaMembers(opp.Id).size(), 'Pre-condicao: 1 membro Pre-Venda.');

        Test.startTest();
        opp.Pre_Venda_Lider__c = null;
        update opp;
        Test.stopTest();

        System.assertEquals(0, preVendaMembers(opp.Id).size(),
            'Limpar o campo devia remover o membro Pre-Venda.');
    }

    // 3. Mudar de A para B -> remove A, poe B.
    @IsTest
    static void testSwapUserAtoB() {
        List<User> users = makeUsers(2);
        User a = users[0];
        User b = users[1];

        Opportunity opp = makeOpp(a.Id);
        insert opp;
        List<OpportunityTeamMember> step1 = preVendaMembers(opp.Id);
        System.assertEquals(1, step1.size(), 'Pre-condicao: A e' + ' membro.');
        System.assertEquals(a.Id, step1[0].UserId, 'Pre-condicao: o membro e' + ' A.');

        Test.startTest();
        opp.Pre_Venda_Lider__c = b.Id;
        update opp;
        Test.stopTest();

        List<OpportunityTeamMember> step2 = preVendaMembers(opp.Id);
        System.assertEquals(1, step2.size(), 'Devia continuar a haver 1 so membro Pre-Venda.');
        System.assertEquals(b.Id, step2[0].UserId, 'O membro Pre-Venda devia passar a ser B.');

        // A nao deve continuar como membro (de todo).
        List<OpportunityTeamMember> aStill = [
            SELECT Id FROM OpportunityTeamMember
            WHERE OpportunityId = :opp.Id AND UserId = :a.Id
        ];
        System.assertEquals(0, aStill.size(), 'A nao devia continuar na equipa.');
    }

    // 4. Pre-Venda == Owner -> nao cria membro, sem erro.
    @IsTest
    static void testOwnerEqualsPreVendaNoMember() {
        Opportunity opp = makeOpp(UserInfo.getUserId()); // owner == running user
        Test.startTest();
        insert opp;
        Test.stopTest();

        System.assertEquals(0, preVendaMembers(opp.Id).size(),
            'Owner == Pre-Venda nao deve criar membro (owner ja tem acesso).');
    }

    // 5. User ja' membro com outro papel -> update do papel/acesso, sem duplicado.
    @IsTest
    static void testExistingMemberOtherRoleUpgraded() {
        User u = makeUsers(1)[0];
        Opportunity opp = makeOpp(null); // sem pre-venda inicial
        insert opp;

        // O user ja' esta' na equipa como 'Comercial' com acesso Read.
        insert new OpportunityTeamMember(
            OpportunityId          = opp.Id,
            UserId                 = u.Id,
            TeamMemberRole         = 'Comercial',
            OpportunityAccessLevel = 'Read'
        );

        Test.startTest();
        opp.Pre_Venda_Lider__c = u.Id;
        update opp;
        Test.stopTest();

        // So' pode existir uma linha para este user (sem duplicado).
        List<OpportunityTeamMember> all = [
            SELECT Id, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opp.Id AND UserId = :u.Id
        ];
        System.assertEquals(1, all.size(), 'Nao deve haver duplicado para o mesmo user.');
        System.assertEquals(ROLE_PRE_VENDA, all[0].TeamMemberRole,
            'O papel devia passar a Pre-Venda.');
        System.assertEquals('Edit', all[0].OpportunityAccessLevel,
            'O acesso devia subir para Edit.');
    }

    // 6. Bulk -> 200 opps de uma vez, cada uma com o seu pre-venda.
    @IsTest
    static void testBulk() {
        List<User> users = makeUsers(5);
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(makeOpp(users[Math.mod(i, 5)].Id));
        }

        Test.startTest();
        insert opps;
        Test.stopTest();

        Integer total = [
            SELECT COUNT()
            FROM OpportunityTeamMember
            WHERE OpportunityId IN :opps AND TeamMemberRole = :ROLE_PRE_VENDA
        ];
        System.assertEquals(200, total, 'Cada opp devia ter o seu membro Pre-Venda.');
    }
}