/**
 * Uma linha do ficheiro do PNI, já lida e limpa, sem depender do formato da origem.
 *
 * Guarda os valores todos por nome de coluna, e não só os que hoje sabemos mapear:
 * o ficheiro tem quarenta colunas e a maioria ainda não tem destino acordado com o
 * cliente. Assim o leitor não precisa de mudar quando o mapeamento crescer.
 *
 * A assinatura calcula-se sobre os valores que vão parar à ordem, para uma segunda
 * importação do mesmo ficheiro não reescrever nada. É separada da assinatura da NOS
 * de propósito: as duas origens escrevem campos diferentes e nenhuma pode saltar a
 * escrita da outra.
 */
public with sharing class SC_PniLinha {
    /** Nome da coluna que identifica a ordem no ficheiro. */
    public static final String COL_CHAVE = 'Project ID';
    /** Nome da coluna com o estado do PNI, que é o que manda no contrato. */
    public static final String COL_ESTADO = 'Status';
    /** Nome da coluna com a data da última alteração. Só tem data, nunca hora. */
    public static final String COL_ALTERACAO = 'Last Changed On';
    /** Célula da rede, para o mapeador resolver contra o catálogo. */
    public static final String COL_CELULA = 'Célula';
    /** Tipo de ordem no vocabulário do catálogo do contrato. */
    public static final String COL_TIPO = 'Tipo OT';

    /** As colunas sem as quais a linha não serve para nada. */
    public static final List<String> COLUNAS_OBRIGATORIAS = new List<String>{
        COL_CHAVE, COL_ESTADO, COL_ALTERACAO
    };

    public Map<String, String> valores = new Map<String, String>();
    /** Número da linha dentro do ficheiro, para a mensagem de erro ser útil. */
    public Integer numero;
    /** O texto original, guardado para o registo da rejeição e o reprocessamento. */
    public String bruto;

    public SC_PniLinha(Integer numero, String bruto) {
        this.numero = numero;
        this.bruto = bruto;
    }

    public String valor(String coluna) {
        return valores.get(coluna);
    }

    public String chave() {
        return valores.get(COL_CHAVE);
    }

    public String estado() {
        return valores.get(COL_ESTADO);
    }

    public Date dataAlteracao() {
        return SC_PniCsv.comoData(valores.get(COL_ALTERACAO));
    }

    public String celula() {
        return valores.get(COL_CELULA);
    }

    public String tipoOrdem() {
        return valores.get(COL_TIPO);
    }

    /**
     * Resumo dos campos que esta importação escreve na ordem. Muda a assinatura,
     * muda a ordem; não muda, a ordem nem é tocada.
     */
    public String assinatura() {
        List<String> partes = new List<String>{
            texto(chave()), texto(estado()), texto(valores.get(COL_ALTERACAO)),
            texto(celula()), texto(tipoOrdem())
        };
        return SC_PniCsv.resumo(String.join(partes, '|'));
    }

    private String texto(String v) {
        return v == null ? '' : v;
    }
}