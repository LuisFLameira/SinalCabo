/**
 * Acção invocável do botão da lista de contas: arranca o recálculo COMPLETO.
 *
 * É a rede da decisão de só recalcular as contas na fronteira todos os meses: se a lógica
 * incremental deixar contas de fora, corre-se isto e fica tudo coerente. Corre em segundo plano,
 * portanto a mensagem diz onde ver o resultado em vez de o prometer para já.
 *
 * REFERÊNCIAS: ADR-014, em projectos/sinalcabo/adr-log.md; desenho da fase em
 * projectos/sinalcabo/outputs/desenho-fase6-segmentacao-2026-08-04.md
 */
public with sharing class SC_SegmentoRecalculoTodasAction {

    @InvocableMethod(label='Recalcular segmento de todas as contas'
                     description='Arranca o recálculo completo do segmento em todas as contas. Corre em segundo plano e o resultado fica no objecto SC Recálculo Log.'
                     category='SinalCabo')
    public static List<Resposta> executar(List<Pedido> pedidos) {
        SC_SegmentoRecalculo.completo();
        Resposta r = new Resposta();
        r.mensagem = 'Recálculo completo arrancado. Corre em segundo plano; '
                   + 'o resumo do que foi avaliado e alterado fica no objecto SC Recálculo Log.';
        return new List<Resposta>{ r };
    }

    /** O Screen Flow não precisa de passar nada, mas um invocável tem de receber uma lista. */
    public class Pedido {
        @InvocableVariable(label='Não usado')
        public String reservado;
    }
    public class Resposta {
        @InvocableVariable(label='Mensagem')
        public String mensagem;
    }
}