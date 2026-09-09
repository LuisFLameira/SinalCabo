/**
 * SC_ContaNifVRTest
 *
 * As tres validation rules do NIF da Account (VR06 formato, VR07 digito de controlo,
 * VR08 prefixo) tem todas a mesma guarda: OR(ISNEW(), ISCHANGED(NIF__c)).
 *
 * A guarda tem DOIS LADOS e os dois importam, por isso os dois estao aqui:
 *   1. o lado que bloqueia: um insert ou um update que TOQUE no NIF com valor invalido falha,
 *      e falha pela regra certa (a asserção le a mensagem, nao so o insucesso);
 *   2. o lado que deixa passar: um update que NAO toca no NIF grava na mesma. E' este lado que
 *      permite ao rollup de segmento e ao rollup de grupo escreverem na conta sem serem
 *      bloqueados por dados legado, e e' o lado que ninguem se lembra de testar. Se alguem
 *      trocar a guarda por um ISPICKVAL/NOT(ISBLANK()) simples, os batches nocturnos passam a
 *      falhar em massa e so' se descobre em producao.
 *
 * LIMITE CONHECIDO DESTE TESTE: nao consegue semear uma conta com um NIF JA SUJO, porque o
 * ISNEW() da guarda apanha o insert e a org nao tem bypass de validation rules (os dois que
 * existem sao da numeracao e do rollup de grupo). O lado 2 fica provado com o NIF valido e com
 * o NIF ausente, que sao os dois estados que uma conta pode ter nesta org depois da migracao.
 * O caso "NIF sujo pre-existente" so' e' verificavel com dados carregados antes das VRs.
 *
 * NIF ausente e' ACEITE (decisao de negocio): as tres regras tem NOT(ISBLANK(NIF__c)).
 *
 * SEGUNDA GUARDA: as tres regras tem
 *   NOT(ISPICKVAL(Tipo_Identificador_Fiscal__c, 'Identificador estrangeiro'))
 * na FORMA NEGATIVA, de proposito. So' uma declaracao EXPLICITA de identificador estrangeiro
 * desliga a validacao portuguesa; o valor por omissao e o campo em branco validam na mesma.
 * E' isto que dispensa backfill das contas que ja' existem (nascidas antes do campo, com o
 * campo a null) e que faz um literal mal escrito na formula falhar em seguranca, com a
 * validacao sempre ligada, em vez de a desligar para toda a gente.
 *
 * A GUARDA E' TRIPLA:
 *   OR(ISNEW(), ISCHANGED(NIF__c), ISCHANGED(Tipo_Identificador_Fiscal__c))
 * O terceiro ramo apanha a passagem de estrangeiro para nacional sem tocar no NIF: sem ele,
 * o registo ficava marcado como nacional com um identificador que nao e' um NIF.
 *
 * O terceiro ramo tem um efeito que NAO e' obvio e que por isso esta' testado nos dois
 * sentidos: mudar o tipo PARA estrangeiro tambem passa a disparar a avaliacao, e so' nao
 * bloqueia porque a clausula negativa desliga a regra nesse caso. E' o caminho que o
 * utilizador usa para corrigir uma conta estrangeira que entrou mal, portanto se algum dia a
 * clausula deixar de ser negativa, o utilizador fica sem saida e e' este teste que o denuncia.
 */
@isTest
private class SC_ContaNifVRTest {

    // Digito de controlo calculado pelo algoritmo da AT, para os valores nao serem magicos:
    // 500000000 = empresa (prefixo 5), 123456789 = pessoa singular (prefixo 1).
    private static final String NIF_VALIDO       = '500000000';
    private static final String NIF_VALIDO_OUTRO = '123456789';
    private static final String NIF_FORMATO_MAU  = '5000000';    // 7 digitos
    private static final String NIF_CHECKSUM_MAU = '500000001';  // formato e prefixo bons, digito errado
    private static final String NIF_PREFIXO_MAU  = '023456787';  // formato e digito bons, prefixo 0

    // Identificadores estrangeiros. O CIF cabe nos 9 caracteres (e por isso NAO era o comprimento
    // do campo que o rejeitava, era o REGEX da VR06); o VAT alemao ja' precisa do Text(20).
    private static final String CIF_ESPANHOL = 'B78593092';   // Solutions 30 Iberia, 9 caracteres
    private static final String VAT_ALEMAO   = 'DE123456789'; // 11 caracteres
    private static final String TIPO_ESTRANGEIRO = 'Identificador estrangeiro';
    private static final String TIPO_PORTUGAL    = 'NIF (Portugal)';

    private static Account comNif(String nif) {
        Account a = new Account(Name = 'Conta NIF', NIF__c = nif);
        insert a;
        return a;
    }

    private static String erroDe(Database.SaveResult sr) {
        System.assertEquals(false, sr.isSuccess(), 'Esperava-se que esta gravacao fosse bloqueada.');
        return String.valueOf(sr.getErrors());
    }

    // ── Lado 1: quem toca no NIF e' validado ──────────────────────────────────────

    @isTest static void insert_com_nif_valido_passa() {
        Test.startTest();
        Account a = comNif(NIF_VALIDO);
        Test.stopTest();
        System.assertEquals(NIF_VALIDO, [SELECT NIF__c FROM Account WHERE Id = :a.Id].NIF__c);
    }

    @isTest static void update_que_toca_no_nif_e_bloqueado_pela_regra_certa() {
        Account a = comNif(NIF_VALIDO);

        Test.startTest();
        String eFormato  = erroDe(Database.update(new Account(Id = a.Id, NIF__c = NIF_FORMATO_MAU), false));
        String eChecksum = erroDe(Database.update(new Account(Id = a.Id, NIF__c = NIF_CHECKSUM_MAU), false));
        String ePrefixo  = erroDe(Database.update(new Account(Id = a.Id, NIF__c = NIF_PREFIXO_MAU), false));
        Test.stopTest();

        System.assert(eFormato.contains('exactamente 9 dígitos'),
            'VR06: 7 digitos tem de falhar pelo formato, e nao por outra regra: ' + eFormato);
        System.assert(eChecksum.contains('não é reconhecido como válido'),
            'VR07: formato e prefixo bons com digito de controlo errado tem de falhar pelo checksum: ' + eChecksum);
        System.assert(ePrefixo.contains('primeiro dígito'),
            'VR08: prefixo 0 nao e um tipo de contribuinte valido: ' + ePrefixo);

        System.assertEquals(NIF_VALIDO, [SELECT NIF__c FROM Account WHERE Id = :a.Id].NIF__c,
            'Nenhuma das tres tentativas pode ter gravado.');
    }

    @isTest static void insert_com_nif_invalido_e_bloqueado_na_criacao() {
        // O ISNEW() da guarda: a migracao para producao carrega contas de raiz e as VRs ficam
        // activas durante a carga, portanto a linha suja volta no ficheiro de erros.
        Test.startTest();
        String erro = erroDe(Database.insert(
            new Account(Name = 'Conta NIF Novo', NIF__c = NIF_CHECKSUM_MAU), false));
        Test.stopTest();
        System.assert(erro.contains('não é reconhecido como válido'), erro);
    }

    // ── Lado 2: quem nao toca no NIF passa ────────────────────────────────────────

    @isTest static void update_que_nao_toca_no_nif_passa() {
        // O cenario dos rollups nocturnos: escrever noutros campos da conta sem mexer no NIF.
        Account a = comNif(NIF_VALIDO);

        Test.startTest();
        Database.SaveResult sr = Database.update(
            new Account(Id = a.Id, Name = 'Conta NIF renomeada', Description = 'toque de rollup'), false);
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(),
            'Um update que nao toca no NIF nao pode ser travado pelas VRs do NIF: ' + sr.getErrors());
        Account rec = [SELECT Name, NIF__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('Conta NIF renomeada', rec.Name);
        System.assertEquals(NIF_VALIDO, rec.NIF__c, 'E o NIF fica como estava.');
    }

    @isTest static void reescrever_o_mesmo_nif_nao_e_alteracao() {
        // ISCHANGED e' por VALOR, nao por presenca no payload. Uma integracao que reenvia a conta
        // inteira todas as noites nao pode ser tratada como edicao do NIF.
        Account a = comNif(NIF_VALIDO);
        Test.startTest();
        Database.SaveResult sr = Database.update(
            new Account(Id = a.Id, NIF__c = NIF_VALIDO, Name = 'Conta NIF reenviada'), false);
        Test.stopTest();
        System.assertEquals(true, sr.isSuccess(), String.valueOf(sr.getErrors()));
    }

    @isTest static void conta_sem_nif_e_aceite_e_editavel() {
        // Decisao de negocio: pode existir conta sem NIF. As tres VRs tem
        // NOT(ISBLANK(NIF__c)), logo nem a criacao nem os updates seguintes sao travados.
        Test.startTest();
        Account a = new Account(Name = 'Conta Sem NIF');
        Database.SaveResult insercao = Database.insert(a, false);
        Database.SaveResult edicao = Database.update(
            new Account(Id = a.Id, Description = 'toque de rollup'), false);
        Test.stopTest();

        System.assertEquals(true, insercao.isSuccess(),
            'Conta sem NIF tem de poder nascer: ' + insercao.getErrors());
        System.assertEquals(true, edicao.isSuccess(),
            'E tem de continuar editavel: ' + edicao.getErrors());
    }

    // ── Terceiro lado: a declaracao do tipo de identificador ──────────────────────

    @isTest static void identificador_estrangeiro_desliga_as_tres_regras() {
        // O caso central: uma conta espanhola com CIF nao cabe em nenhuma das tres regras
        // portuguesas. Testa-se com um CIF (9 caracteres, morre no REGEX da VR06) e com um
        // VAT de 11 caracteres, que o campo Text(20) comporta.
        Test.startTest();
        Database.SaveResult cif = Database.insert(new Account(
            Name = 'Conta Estrangeira CIF', NIF__c = CIF_ESPANHOL,
            Tipo_Identificador_Fiscal__c = TIPO_ESTRANGEIRO), false);
        Database.SaveResult vat = Database.insert(new Account(
            Name = 'Conta Estrangeira VAT', NIF__c = VAT_ALEMAO,
            Tipo_Identificador_Fiscal__c = TIPO_ESTRANGEIRO), false);
        Test.stopTest();

        System.assertEquals(true, cif.isSuccess(),
            'Um CIF declarado como estrangeiro nao pode ser travado pelas regras do NIF: ' + cif.getErrors());
        System.assertEquals(true, vat.isSuccess(),
            'Um VAT de 11 caracteres precisa do Text(20) e da declaracao: ' + vat.getErrors());
        System.assertEquals(CIF_ESPANHOL, [SELECT NIF__c FROM Account WHERE Id = :cif.getId()].NIF__c);
        System.assertEquals(VAT_ALEMAO, [SELECT NIF__c FROM Account WHERE Id = :vat.getId()].NIF__c,
            'O identificador longo tem de ficar inteiro, sem truncar.');
    }

    @isTest static void tipo_em_branco_continua_a_validar() {
        // O lado fail-closed, e o que dispensa backfill: as contas que ja' existiam nasceram
        // antes do campo e tem-no a null. Um null NAO pode valer como "estrangeiro", senao a
        // criacao do campo teria desligado a validacao em toda a base instalada de uma vez.
        Test.startTest();
        String erro = erroDe(Database.insert(new Account(
            Name = 'Conta Tipo Nulo', NIF__c = NIF_CHECKSUM_MAU,
            Tipo_Identificador_Fiscal__c = null), false));
        Test.stopTest();
        System.assert(erro.contains('não é reconhecido como válido'),
            'Com o tipo em branco a validacao portuguesa tem de continuar ligada: ' + erro);
    }

    @isTest static void tipo_nacional_explicito_valida_como_sempre() {
        // O simetrico: declarar o tipo como nacional nao pode ser uma via de escape.
        Test.startTest();
        String erro = erroDe(Database.insert(new Account(
            Name = 'Conta Tipo PT', NIF__c = CIF_ESPANHOL,
            Tipo_Identificador_Fiscal__c = TIPO_PORTUGAL), false));
        Test.stopTest();
        System.assert(erro.contains('exactamente 9 dígitos'),
            'Um CIF declarado como NIF portugues tem de falhar pelo formato: ' + erro);
    }

    @isTest static void valor_por_omissao_e_aplicado_no_insert() {
        // A carga da migracao deixa a coluna vazia nas 704 linhas nacionais e conta com o
        // default. Se o default deixar de ser aplicado, essas linhas passam a entrar com o
        // campo a null: continuam validadas (o teste acima), mas o relatorio por tipo mente.
        Test.startTest();
        Account a = comNif(NIF_VALIDO);
        Test.stopTest();
        System.assertEquals(TIPO_PORTUGAL,
            [SELECT Tipo_Identificador_Fiscal__c FROM Account WHERE Id = :a.Id].Tipo_Identificador_Fiscal__c,
            'Uma conta inserida sem o campo tem de ficar no valor por omissao.');
    }

    // ── Quarto lado: o terceiro ramo da guarda, ISCHANGED do tipo ─────────────────

    @isTest static void passar_de_estrangeiro_para_nacional_sem_tocar_no_nif_bloqueia() {
        // A porta que o terceiro ramo da guarda fecha. Sem ele, este update passava e a conta
        // ficava declarada como nacional a guardar um CIF.
        Account a = new Account(Name = 'Conta Vira Nacional', NIF__c = CIF_ESPANHOL,
            Tipo_Identificador_Fiscal__c = TIPO_ESTRANGEIRO);
        insert a;

        Test.startTest();
        String erro = erroDe(Database.update(new Account(
            Id = a.Id, Tipo_Identificador_Fiscal__c = TIPO_PORTUGAL), false));
        Test.stopTest();

        System.assert(erro.contains('exactamente 9 dígitos'),
            'Declarar como NIF portugues um CIF ja' + ' gravado tem de falhar pelo formato: ' + erro);
        System.assertEquals(TIPO_ESTRANGEIRO,
            [SELECT Tipo_Identificador_Fiscal__c FROM Account WHERE Id = :a.Id].Tipo_Identificador_Fiscal__c,
            'E o tipo nao pode ter mudado.');
    }

    @isTest static void passar_de_nacional_para_estrangeiro_sem_tocar_no_nif_grava() {
        // O sentido inverso, e o caminho real de correcao de uma conta que entrou mal. A guarda
        // DISPARA (o tipo mudou), mas a clausula negativa desliga as tres regras, logo grava.
        Account a = comNif(NIF_VALIDO);

        Test.startTest();
        Database.SaveResult sr = Database.update(new Account(
            Id = a.Id, Tipo_Identificador_Fiscal__c = TIPO_ESTRANGEIRO), false);
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(),
            'Marcar uma conta como estrangeira nao pode ser bloqueado, senao nao ha' +
            ' forma de corrigir uma conta que entrou mal: ' + sr.getErrors());
        System.assertEquals(TIPO_ESTRANGEIRO,
            [SELECT Tipo_Identificador_Fiscal__c FROM Account WHERE Id = :a.Id].Tipo_Identificador_Fiscal__c);
    }

    @isTest static void mudar_so_o_name_de_conta_estrangeira_grava() {
        // O terceiro ramo nao pode ter alargado a guarda a updates que nao tocam em nenhum dos
        // dois campos: e' a mesma proteccao dos rollups nocturnos, agora com um CIF gravado.
        Account a = new Account(Name = 'Conta Estrangeira Renomear', NIF__c = CIF_ESPANHOL,
            Tipo_Identificador_Fiscal__c = TIPO_ESTRANGEIRO);
        insert a;

        Test.startTest();
        Database.SaveResult sr = Database.update(new Account(
            Id = a.Id, Name = 'Conta Estrangeira Renomeada', Description = 'toque de rollup'), false);
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(),
            'Um update que nao toca no NIF nem no tipo tem de passar: ' + sr.getErrors());
        Account rec = [SELECT Name, NIF__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('Conta Estrangeira Renomeada', rec.Name);
        System.assertEquals(CIF_ESPANHOL, rec.NIF__c);
    }

    @isTest static void preencher_o_nif_mais_tarde_e_validado() {
        // O reverso do teste anterior: aceitar a conta sem NIF nao pode abrir a porta a que o NIF
        // entre invalido depois, por um update que a guarda ISCHANGED apanha.
        Account a = new Account(Name = 'Conta Sem NIF 2');
        insert a;
        Test.startTest();
        String erro = erroDe(Database.update(new Account(Id = a.Id, NIF__c = NIF_PREFIXO_MAU), false));
        Database.SaveResult bom = Database.update(new Account(Id = a.Id, NIF__c = NIF_VALIDO_OUTRO), false);
        Test.stopTest();
        System.assert(erro.contains('primeiro dígito'), erro);
        System.assertEquals(true, bom.isSuccess(), String.valueOf(bom.getErrors()));
    }
}