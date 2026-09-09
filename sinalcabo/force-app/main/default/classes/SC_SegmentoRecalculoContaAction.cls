/**
 * Acção invocável do botão da ficha da conta: recalcula AQUELA conta.
 *
 * Existe como classe própria porque o Apex só admite um @InvocableMethod por classe e há dois
 * botões. Não tem lógica: delega no SC_SegmentoRecalculo.
 *
 * REFERÊNCIAS: ADR-014, em projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoRecalculoContaAction {

    @InvocableMethod(label='Recalcular segmento de uma conta'
                     description='Recalcula os valores e o segmento da conta indicada, e o agregado de grupo se ela tiver filhas.'
                     category='SinalCabo')
    public static List<Resposta> executar(List<Pedido> pedidos) {
        List<Resposta> saida = new List<Resposta>();
        for (Pedido p : pedidos) {
            Resposta r = new Resposta();
            r.mensagem = SC_SegmentoRecalculo.umaConta(p.contaId);
            r.alterou = !r.mensagem.startsWith('Nada a corrigir');
            saida.add(r);
        }
        return saida;
    }

    public class Pedido {
        @InvocableVariable(label='Id da conta' required=true)
        public Id contaId;
    }
    public class Resposta {
        @InvocableVariable(label='Mensagem')
        public String mensagem;
        @InvocableVariable(label='Alterou algo')
        public Boolean alterou;
    }
}