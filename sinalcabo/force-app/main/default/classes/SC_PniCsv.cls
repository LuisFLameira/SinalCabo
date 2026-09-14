/**
 * Leitura de um pedaço do ficheiro do PNI, e limpeza do que vem sujo.
 *
 * O ficheiro inteiro nunca entra aqui. Tem 10,4 MB e a memória de uma transacção são
 * 6 MB em síncrono e 12 MB em assíncrono, com o texto e o original a coexistirem.
 * O ecrã corta-o em pedaços e manda um de cada vez; esta classe lê um pedaço e
 * devolve a cauda, que é o que ficou depois do último registo completo, para o
 * pedaço seguinte começar por ela. Assim uma linha nunca é cortada ao meio.
 *
 * Um registo pode ter mudanças de linha lá dentro, desde que dentro de aspas. Por
 * isso a fronteira do registo não é a mudança de linha, é a mudança de linha com as
 * aspas fechadas. É a única forma de não partir as 1.577 linhas do ficheiro que
 * trazem aspas ou ponto e vírgula no texto.
 *
 * Nada aqui escreve na base de dados nem lança para fora. Uma linha com formato
 * inesperado sai como rejeição, com o texto original, e as boas seguem caminho.
 *
 * SUJIDADE MEDIDA no ficheiro de 04/09/2026, e que esta classe trata:
 *   4.997 linhas com a data 1970-01-01 a fazer de nulo;
 *   o literal `null` 717 vezes e `N/A` 6.989 vezes;
 *   o orçamento em texto no formato `EUR 286.75`;
 *   três colunas de observações cortadas nos 255 caracteres pelo Access.
 */
public with sharing class SC_PniCsv {
    public static final String SEPARADOR = ';';
    private static final String ASPA = '"';
    /** O Access grava datas assim quando exporta em texto. */
    private static final Pattern PADRAO_DATA = Pattern.compile(
        '^(\\d{4})-(\\d{2})-(\\d{2})(?:[ T](\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d+)?)?$'
    );
    /** O valor vem como "EUR 286.75", com o símbolo colado ao número. */
    private static final Pattern PADRAO_VALOR = Pattern.compile(
        '^\\s*(?:EUR|€)?\\s*(-?\\d+(?:[.,]\\d+)?)\\s*$'
    );
    /** Textos que a origem usa para dizer vazio sem o dizer. */
    private static final Set<String> VAZIOS = new Set<String>{
        '', 'null', 'n/a', 'na', '-', '#n/a'
    };

    // ------------------------------------------------------------------
    // O que a leitura devolve
    // ------------------------------------------------------------------

    public class Rejeicao {
        public String chave;
        public String motivo;
        public String bruto;
        public Integer numero;
        public Rejeicao(Integer numero, String chave, String motivo, String bruto) {
            this.numero = numero;
            this.chave = chave;
            this.motivo = motivo;
            this.bruto = bruto;
        }
    }

    public class Resultado {
        public List<SC_PniLinha> linhas = new List<SC_PniLinha>();
        public List<Rejeicao> rejeicoes = new List<Rejeicao>();
        /** O que sobrou depois do último registo completo. Vai à frente do pedaço seguinte. */
        public String cauda = '';
        /** As colunas lidas do cabeçalho, pela ordem em que vieram. */
        public List<String> colunas = new List<String>();
        /** Nulo quando o cabeçalho serve. Com texto, o pedaço não foi lido de todo. */
        public String erroCabecalho;
        public Integer lidas = 0;

        public Boolean valido() {
            return erroCabecalho == null;
        }
    }

    // ------------------------------------------------------------------
    // Leitura
    // ------------------------------------------------------------------

    /**
     * Lê um pedaço de texto.
     *
     * @param texto    o pedaço, já com a cauda do anterior à frente
     * @param colunas  nulo no primeiro pedaço, que traz o cabeçalho; nos seguintes
     *                 são as colunas já conhecidas, porque o cabeçalho só vem uma vez
     * @param numeroInicial  número da primeira linha deste pedaço dentro do ficheiro
     * @param ultimo   verdadeiro no último pedaço, onde não pode sobrar cauda
     */
    public static Resultado ler(String texto, List<String> colunas,
                                Integer numeroInicial, Boolean ultimo) {
        Resultado r = new Resultado();
        if (texto == null) {
            texto = '';
        }
        List<String> registos = separarRegistos(texto, r, ultimo);

        Integer indice = 0;
        if (colunas == null || colunas.isEmpty()) {
            if (registos.isEmpty()) {
                r.erroCabecalho = 'O ficheiro está vazio.';
                return r;
            }
            r.colunas = campos(registos[0]);
            indice = 1;
            String falta = colunaEmFalta(r.colunas);
            if (falta != null) {
                r.erroCabecalho = 'O ficheiro não traz a coluna ' + falta + '.';
                return r;
            }
        } else {
            r.colunas = colunas;
        }

        Integer numero = numeroInicial + indice;
        for (Integer i = indice; i < registos.size(); i++) {
            String registo = registos[i];
            r.lidas++;
            if (String.isBlank(registo)) {
                numero++;
                continue;
            }
            List<String> valores = campos(registo);
            if (valores.size() != r.colunas.size()) {
                r.rejeicoes.add(new Rejeicao(numero, null,
                    'A linha tem ' + valores.size() + ' campos e o cabeçalho tem '
                    + r.colunas.size() + '.', registo));
                numero++;
                continue;
            }
            SC_PniLinha linha = new SC_PniLinha(numero, registo);
            for (Integer c = 0; c < r.colunas.size(); c++) {
                linha.valores.put(r.colunas[c], limpar(valores[c]));
            }
            if (String.isBlank(linha.chave())) {
                r.rejeicoes.add(new Rejeicao(numero, null,
                    'A linha não traz identificador da ordem.', registo));
                numero++;
                continue;
            }
            r.linhas.add(linha);
            numero++;
        }
        return r;
    }

    /**
     * Parte o texto em registos, tratando a mudança de linha dentro de aspas como
     * parte do registo. O que ficar depois do último registo completo é cauda.
     */
    private static List<String> separarRegistos(String texto, Resultado r, Boolean ultimo) {
        List<String> registos = new List<String>();
        List<String> linhas = texto.replace('\r\n', '\n').replace('\r', '\n').split('\n', -1);
        String acumulado = '';
        Boolean temAcumulado = false;
        for (Integer i = 0; i < linhas.size(); i++) {
            acumulado = temAcumulado ? acumulado + '\n' + linhas[i] : linhas[i];
            temAcumulado = true;
            if (Math.mod(acumulado.countMatches(ASPA), 2) == 0) {
                registos.add(acumulado);
                acumulado = '';
                temAcumulado = false;
            }
        }
        // O split com -1 deixa uma entrada vazia quando o texto acaba em mudança de
        // linha: nesse caso o último registo está completo e não há cauda.
        if (temAcumulado) {
            // Aspas por fechar: o registo continua no pedaço seguinte.
            r.cauda = acumulado;
        } else if (!registos.isEmpty() && !texto.endsWith('\n') && !ultimo) {
            // O pedaço acabou a meio de uma linha sem aspas abertas.
            r.cauda = registos.remove(registos.size() - 1);
        }
        if (ultimo && String.isNotBlank(r.cauda)) {
            registos.add(r.cauda);
            r.cauda = '';
        }
        return registos;
    }

    /** Parte um registo nos seus campos, respeitando as aspas. */
    @TestVisible
    private static List<String> campos(String registo) {
        if (registo.indexOf(ASPA) < 0) {
            // Caminho rápido: a grande maioria das linhas não tem aspas nenhumas.
            return registo.split(SEPARADOR, -1);
        }
        List<String> saida = new List<String>();
        String actual = '';
        Boolean dentro = false;
        Integer n = registo.length();
        for (Integer i = 0; i < n; i++) {
            String c = registo.substring(i, i + 1);
            if (dentro) {
                if (c == ASPA) {
                    if (i + 1 < n && registo.substring(i + 1, i + 2) == ASPA) {
                        actual += ASPA;
                        i++;
                    } else {
                        dentro = false;
                    }
                } else {
                    actual += c;
                }
            } else if (c == ASPA) {
                dentro = true;
            } else if (c == SEPARADOR) {
                saida.add(actual);
                actual = '';
            } else {
                actual += c;
            }
        }
        saida.add(actual);
        return saida;
    }

    private static String colunaEmFalta(List<String> colunas) {
        Set<String> presentes = new Set<String>();
        for (String c : colunas) {
            presentes.add(c == null ? '' : c.trim());
        }
        for (String obrigatoria : SC_PniLinha.COLUNAS_OBRIGATORIAS) {
            if (!presentes.contains(obrigatoria)) {
                return obrigatoria;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Limpeza
    // ------------------------------------------------------------------

    /** Espaços fora, e os textos que querem dizer vazio passam a nulo. */
    public static String limpar(String valor) {
        if (valor == null) {
            return null;
        }
        String v = valor.trim();
        if (VAZIOS.contains(v.toLowerCase())) {
            return null;
        }
        return v;
    }

    /**
     * Converte a data do ficheiro. Devolve nulo para o que não for data e para as
     * datas de 1970, que na origem são um nulo disfarçado: são 4.997 linhas.
     */
    public static Date comoData(String valor) {
        String v = limpar(valor);
        if (v == null) {
            return null;
        }
        Matcher m = PADRAO_DATA.matcher(v);
        if (!m.matches()) {
            return null;
        }
        Integer ano = Integer.valueOf(m.group(1));
        if (ano <= 1970) {
            return null;
        }
        try {
            return Date.newInstance(ano, Integer.valueOf(m.group(2)),
                                    Integer.valueOf(m.group(3)));
        } catch (Exception e) {
            return null;
        }
    }

    /** O valor vem em texto, com a moeda colada. Devolve nulo quando não é número. */
    public static Decimal comoValor(String valor) {
        String v = limpar(valor);
        if (v == null) {
            return null;
        }
        Matcher m = PADRAO_VALOR.matcher(v);
        if (!m.matches()) {
            return null;
        }
        try {
            return Decimal.valueOf(m.group(1).replace(',', '.'));
        } catch (Exception e) {
            return null;
        }
    }

    /** Corta o texto ao comprimento do campo, sem rebentar quando já é mais curto. */
    public static String ate(String valor, Integer comprimento) {
        String v = limpar(valor);
        if (v == null) {
            return null;
        }
        return v.length() <= comprimento ? v : v.substring(0, comprimento);
    }

    /** Resumo curto e estável de um texto, para servir de assinatura. */
    public static String resumo(String texto) {
        if (texto == null) {
            texto = '';
        }
        Blob digerido = Crypto.generateDigest('SHA-256', Blob.valueOf(texto));
        return EncodingUtil.convertToHex(digerido).substring(0, 64);
    }
}