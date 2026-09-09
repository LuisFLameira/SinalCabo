/**
 * Teste do SC_FlowFaultLogger, o tratamento comum dos caminhos de falha.
 *
 * O que se prova aqui: a falha fica gravada com o suficiente para ser corrigida, o método
 * nunca lança seja qual for a entrada, e um lote de falhas dá um lote de registos.
 *
 * O que NÃO se prova por teste: a entrega da notificação no sino. Em contexto de teste a
 * plataforma aceita o send mas não entrega nada observável, por isso o que os testes garantem
 * é que o envio não rebenta nem impede a gravação.
 */
@IsTest
private class SC_FlowFaultLoggerTest {

    private static SC_FlowFaultLogger.Pedido pedido(String origem, String elemento, String msg, String reg) {
        SC_FlowFaultLogger.Pedido p = new SC_FlowFaultLogger.Pedido();
        p.origem = origem;
        p.elemento = elemento;
        p.mensagem = msg;
        p.registoAfectado = reg;
        return p;
    }

    @IsTest
    static void grava_a_falha_com_o_contexto_todo() {
        Account a = new Account(Name = 'PW ERRAUT Acc');
        insert a;

        Test.startTest();
        SC_FlowFaultLogger.registar(new List<SC_FlowFaultLogger.Pedido>{
            pedido('SC_Opportunity_AlertaDeadline', 'Update_Opps_Bulk', 'FIELD_CUSTOM_VALIDATION_EXCEPTION: xpto', a.Id)
        });
        Test.stopTest();

        List<SC_Erro_Automacao_Log__c> logs = [
            SELECT Origem__c, Elemento__c, Mensagem__c, Registo_Afectado__c, Resolvido__c
            FROM SC_Erro_Automacao_Log__c
        ];
        Assert.areEqual(1, logs.size(), 'a falha tem de ficar gravada');
        Assert.areEqual('SC_Opportunity_AlertaDeadline', logs[0].Origem__c, 'sem a origem nao se sabe onde corrigir');
        Assert.areEqual('Update_Opps_Bulk', logs[0].Elemento__c, 'sem o elemento fica a adivinhar qual gravacao rebentou');
        Assert.isTrue(logs[0].Mensagem__c.contains('xpto'), 'a mensagem da plataforma guarda-se inteira');
        Assert.areEqual(a.Id, logs[0].Registo_Afectado__c, 'o registo afectado e o que torna o log corrigivel');
        Assert.isFalse(logs[0].Resolvido__c, 'nasce por resolver, e a list view de trabalho filtra por isso');
    }

    // Um lote de falhas na mesma transacção (record-triggered bulkificado) dá um registo por
    // falha e uma só notificação. O número de registos é o que se pode asserir.
    @IsTest
    static void lote_de_falhas_da_um_registo_por_falha() {
        List<SC_FlowFaultLogger.Pedido> lote = new List<SC_FlowFaultLogger.Pedido>();
        for (Integer i = 0; i < 25; i++) {
            lote.add(pedido('SC_Account_Rollup_Segmento', 'Update_Account', 'erro ' + i, null));
        }

        Test.startTest();
        SC_FlowFaultLogger.registar(lote);
        Test.stopTest();

        Assert.areEqual(25, [SELECT COUNT() FROM SC_Erro_Automacao_Log__c], 'uma linha por falha, nada agregado');
    }

    // O tratamento de um erro não pode ter erros seus. Entradas degeneradas não podem lançar,
    // porque a excepção subiria ao flow e mataria o caminho de falha que o chamou.
    @IsTest
    static void nunca_lanca_seja_qual_for_a_entrada() {
        Test.startTest();
        SC_FlowFaultLogger.registar(null);
        SC_FlowFaultLogger.registar(new List<SC_FlowFaultLogger.Pedido>());
        SC_FlowFaultLogger.registar(new List<SC_FlowFaultLogger.Pedido>{ null });
        // origem vazia, mensagem nula e um Id que não é Id nenhum
        SC_FlowFaultLogger.registar(new List<SC_FlowFaultLogger.Pedido>{
            pedido(null, null, null, 'isto-nao-e-um-id')
        });
        Test.stopTest();

        List<SC_Erro_Automacao_Log__c> logs = [SELECT Registo_Afectado__c FROM SC_Erro_Automacao_Log__c];
        Assert.areEqual(1, logs.size(), 'so a entrada com conteudo gera registo; as vazias sao ignoradas em silencio');
        Assert.isNull(logs[0].Registo_Afectado__c,
            'um Id invalido descarta-se, porque vale mais perder o Id do que perder o registo da falha');
    }

    // A mensagem da plataforma pode ser muito maior do que um Text: tem de caber sem cortar o
    // registo, que é o motivo de o campo ser LongTextArea e a origem ser truncada.
    @IsTest
    static void mensagem_muito_grande_e_origem_muito_longa_nao_perdem_o_registo() {
        String origemEnorme = 'X'.repeat(200);
        String mensagemEnorme = 'Y'.repeat(5000);

        Test.startTest();
        SC_FlowFaultLogger.registar(new List<SC_FlowFaultLogger.Pedido>{
            pedido(origemEnorme, null, mensagemEnorme, null)
        });
        Test.stopTest();

        List<SC_Erro_Automacao_Log__c> logs = [SELECT Origem__c, Mensagem__c FROM SC_Erro_Automacao_Log__c];
        Assert.areEqual(1, logs.size(), 'o registo tem de sobreviver a valores fora de medida');
        Assert.areEqual(80, logs[0].Origem__c.length(), 'a origem trunca ao tamanho do campo');
        Assert.areEqual(5000, logs[0].Mensagem__c.length(), 'a mensagem guarda-se inteira');
    }
}