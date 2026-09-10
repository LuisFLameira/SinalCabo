/**
 * Uma tarefa da NOS, já lida do JSON e sem depender do formato da origem.
 *
 * A listagem e o detalhe trazem os mesmos campos de cabeçalho; o detalhe acrescenta
 * as notas, os elementos de rede e as interacções. Por isso a assinatura calcula-se
 * só sobre os campos de cabeçalho: assim a mesma tarefa dá a mesma assinatura venha
 * da listagem ou do detalhe, e uma segunda leitura sem alterações não escreve nada.
 */
public with sharing class SC_NosTarefa {
    public String id;
    public String referenciaOcorrencia;
    public String estado;
    public String tipoPedido;
    public String grupo;
    public String prioridade;
    public String utilizador;
    public String resumo;
    public String contrato;
    public Datetime dataAtribuicao;
    public Datetime dataInicio;
    public Datetime dataFim;

    /** Só o detalhe traz estes três. */
    public String notas;
    public List<String> elementosRede = new List<String>();
    public List<Interaccao> interaccoes = new List<Interaccao>();
    public Boolean veioDoDetalhe = false;

    public class Interaccao {
        public String id;
        public String tipo;
        public String resumo;
        public String notas;
        public String fonte;
        public Datetime criadaEm;
    }

    public Boolean estaFechada() {
        return 'CLOSED'.equals(this.estado) || 'RESOLVED'.equals(this.estado);
    }

    /** SHA-256 dos campos de cabeçalho, em hexadecimal (64 caracteres). */
    public String assinatura() {
        List<String> partes = new List<String>{
            texto(this.id),
            texto(this.referenciaOcorrencia),
            texto(this.estado),
            texto(this.tipoPedido),
            texto(this.grupo),
            texto(this.prioridade),
            texto(this.utilizador),
            texto(this.resumo),
            texto(this.contrato),
            instante(this.dataAtribuicao),
            instante(this.dataInicio),
            instante(this.dataFim)
        };
        Blob digerido = Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(partes, '|')));
        return EncodingUtil.convertToHex(digerido);
    }

    private static String texto(String valor) {
        return valor == null ? '' : valor;
    }

    /** Sempre em GMT: a mesma hora chega da NOS ora com offset ora em Z. */
    private static String instante(Datetime valor) {
        return valor == null ? '' : valor.formatGmt('yyyy-MM-dd HH:mm:ss');
    }
}