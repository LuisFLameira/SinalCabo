/**
 * SC_RevisaoPropostaService (B.2)
 *
 * Motor da revisao de proposta. Dois caminhos, um so historico (Revisao_Proposta__c):
 *
 *  1) Pedido do cliente (em negociacao): @InvocableMethod chamado pelo screen flow
 *     SC_Rever_Proposta. Faz o snapshot antes/depois, incrementa a versao, devolve a
 *     opp a "Em Elaboracao" e limpa o Approval_Status. Ao re-avancar pelo Guiar Pipeline,
 *     o motor de aprovacao re-avalia a matriz com os novos valores (re-aprova so se preciso).
 *     Liga Stage_Update_Via_Flow__c para nao disparar a VR_Stage_Via_Flow_Obrigatorio; a
 *     correccao de valores em fase pos-elaboracao passa por aqui (a VR_Valores_Bloqueados
 *     key-a no NOVO stage = Em Elaboracao, por isso nao bloqueia). Fecha tambem o ciclo de
 *     aprovacao anterior (reset do ADR-010): uma opp ja aprovada chega aqui com o
 *     Requer_Aprovacao__c a true e, sem o reset, ressubmetia-se sozinha ao aprovador antigo.
 *
 *  2) Recusa interna: registarRevisaoRecusa(...), chamado pelo SC_RejeicaoStampService
 *     (async, ja com o motivo do aprovador). So cria o registo no historico; a regressao a
 *     Em Elaboracao e o Approval_Status=Recusado ja sao feitos pelo Approval Process.
 *
 * Margem em pontos percentuais (30 = 30%), coerente com Opportunity.Margem_Percentual__c.
 */
public with sharing class SC_RevisaoPropostaService {

    // ---------- Caminho 1: pedido do cliente (invocavel pelo flow) ----------
    public class Request {
        @InvocableVariable(required=true label='Opportunity ID') public Id opportunityId;
        @InvocableVariable(label='Motivo') public String motivo;
        @InvocableVariable(label='Nota') public String nota;
        @InvocableVariable(required=true label='Novo Valor') public Decimal novoValor;
        @InvocableVariable(required=true label='Novo Custo') public Decimal novoCusto;
    }
    public class Result {
        @InvocableVariable(label='Nova Versao') public Decimal novaVersao;
        @InvocableVariable(label='Mensagem') public String mensagem;
    }

    @InvocableMethod(label='Registar Revisao de Proposta (cliente)' description='Cria a revisao, versiona e devolve a oportunidade a Em Elaboracao')
    public static List<Result> registarRevisaoCliente(List<Request> pedidos) {
        List<Result> resultados = new List<Result>();
        if (pedidos == null || pedidos.isEmpty()) return resultados;

        Set<Id> oppIds = new Set<Id>();
        for (Request r : pedidos) if (r != null && r.opportunityId != null) oppIds.add(r.opportunityId);

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Amount, Custo_Estimado__c, Margem_Percentual__c, StageName, Versao_Proposta__c
            FROM Opportunity WHERE Id IN :oppIds
        ]);

        List<Revisao_Proposta__c> aInserir = new List<Revisao_Proposta__c>();
        List<Opportunity> aActualizar = new List<Opportunity>();

        for (Request req : pedidos) {
            Result res = new Result();
            Opportunity o = (req != null) ? opps.get(req.opportunityId) : null;
            if (o == null) { res.mensagem = 'Oportunidade nao encontrada.'; resultados.add(res); continue; }

            // Governacao: a revisao do cliente so faz sentido depois da proposta sair.
            if (o.StageName != 'Proposta Enviada' && o.StageName != 'Em Negociação') {
                res.mensagem = 'A revisao so esta disponivel em Proposta Enviada ou Em Negociacao.';
                resultados.add(res);
                continue;
            }

            Decimal versaoActual = (o.Versao_Proposta__c == null) ? 1 : o.Versao_Proposta__c;
            Decimal novaVersao = versaoActual + 1;
            Decimal margemDepois = calcularMargem(req.novoValor, req.novoCusto);

            aInserir.add(new Revisao_Proposta__c(
                Oportunidade__c = o.Id,
                Versao__c = novaVersao,
                Origem__c = 'Pedido do cliente',
                Motivo__c = req.motivo,
                Nota__c = req.nota,
                Valor_Antes__c = o.Amount,
                Valor_Depois__c = req.novoValor,
                Custo_Antes__c = o.Custo_Estimado__c,
                Custo_Depois__c = req.novoCusto,
                Margem_Antes__c = o.Margem_Percentual__c,
                Margem_Depois__c = margemDepois,
                Data__c = System.now()
            ));

            aActualizar.add(new Opportunity(
                Id = o.Id,
                Amount = req.novoValor,
                Custo_Estimado__c = req.novoCusto,
                StageName = 'Em Elaboração',
                Approval_Status__c = null,
                // Reset do ciclo de aprovacao anterior, o mesmo do ADR-010 (rejeicao) e do recall.
                // A revisao e' a TERCEIRA via de fechar um ciclo, e nao passa pelo flow
                // SC_Reset_Aprovacao_Rejeicao, que so dispara em Recusado ou Recolhido. Sem isto:
                //  1) Requer_Aprovacao__c fica a true de um ciclo ja aprovado e, ao limpar o
                //     Approval_Status__c aqui, cumpre-se a condicao de entrada do
                //     SC_AutoSubmit_Aprovacao; a revisao ressubmetia-se sozinha ao aprovador do
                //     ciclo anterior e trancava a opp (recordEditability = AdminOnly) antes de o
                //     KAM chegar a rever valor nenhum;
                //  2) os carimbos G2_Lx_Aprovador__c sobreviviam, e como o SC_AprovacaoStampService
                //     so escreve na DECISAO, o ciclo novo mostrava o aprovador do ciclo anterior
                //     durante toda a fase em que ainda ninguem decidiu;
                //  3) as datas G2_Lx_Data_Aprovacao__c sobreviviam, e um ciclo novo nascia com o
                //     nivel L1 a parecer ja aprovado.
                // Os campos de rejeicao (G2_Rejeitado_Por/Motivo/Data) e os Aprovador_Alvo_Nx
                // ficam intactos, como no ADR-010: o motor recalcula os alvos no reavanco.
                Requer_Aprovacao__c = false,
                G2_L1_Aprovador__c = null,
                G2_L2_Aprovador__c = null,
                G2_L3_Aprovador__c = null,
                G2_L1_Data_Aprovacao__c = null,
                G2_L2_Data_Aprovacao__c = null,
                G2_L3_Data_Aprovacao__c = null,
                Versao_Proposta__c = novaVersao,
                Stage_Update_Via_Flow__c = true
            ));

            res.novaVersao = novaVersao;
            res.mensagem = 'Revisao registada (versao ' + novaVersao + '). A oportunidade voltou a Em Elaboracao para reveres os valores e re-submeteres.';
            resultados.add(res);
        }

        if (!aInserir.isEmpty()) insert aInserir;
        if (!aActualizar.isEmpty()) update aActualizar;
        return resultados;
    }

    // ---------- Caminho 2: recusa interna (chamado pelo SC_RejeicaoStampService) ----------
    // Cria o registo no historico para as opps recusadas. motivoPorOpp = comentario do aprovador.
    public static void registarRevisaoRecusa(Set<Id> oppIds, Map<Id, String> motivoPorOpp) {
        if (oppIds == null || oppIds.isEmpty()) return;

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Amount, Custo_Estimado__c, Margem_Percentual__c, Versao_Proposta__c
            FROM Opportunity WHERE Id IN :oppIds
        ]);

        List<Revisao_Proposta__c> aInserir = new List<Revisao_Proposta__c>();
        for (Id oppId : oppIds) {
            Opportunity o = opps.get(oppId);
            if (o == null) continue;
            String motivo = (motivoPorOpp != null) ? motivoPorOpp.get(oppId) : null;
            aInserir.add(new Revisao_Proposta__c(
                Oportunidade__c = o.Id,
                Versao__c = (o.Versao_Proposta__c == null) ? 1 : o.Versao_Proposta__c,
                Origem__c = 'Recusa interna',
                Nota__c = motivo,
                Valor_Antes__c = o.Amount,
                Valor_Depois__c = o.Amount,
                Custo_Antes__c = o.Custo_Estimado__c,
                Custo_Depois__c = o.Custo_Estimado__c,
                Margem_Antes__c = o.Margem_Percentual__c,
                Margem_Depois__c = o.Margem_Percentual__c,
                Data__c = System.now()
            ));
        }
        if (!aInserir.isEmpty()) insert aInserir;
    }

    // Margem em pontos percentuais (30 = 30%). Custo > Valor da margem negativa (bloqueada pela VR).
    @TestVisible
    private static Decimal calcularMargem(Decimal valor, Decimal custo) {
        if (valor == null || valor == 0) return 0;
        Decimal c = (custo == null) ? 0 : custo;
        return ((valor - c) / valor * 100).setScale(2);
    }
}