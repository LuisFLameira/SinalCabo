/**
 * Leitura do JSON da NOS para objectos SC_NosTarefa.
 *
 * Usa deserializeUntyped porque o envelope muda de forma entre métodos: na listagem
 * result_data.data é uma lista, no detalhe é um objecto, e num erro pode não existir.
 * Nada aqui escreve na base de dados nem lança para fora: um campo que a origem
 * mande com formato inesperado fica a null e o mapeador trata disso.
 *
 * Datas: a NOS mistura offset (+01:00) e Z na mesma resposta. Tudo é convertido para
 * GMT à entrada, para que a assinatura não mude só por a origem ter mudado de formato.
 */
public with sharing class SC_NosParser {
    // yyyy-MM-ddTHH:mm:ss com milissegundos e fuso opcionais.
    private static final Pattern PADRAO_DATA = Pattern.compile(
        '^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d{1,6}))?(Z|z|[+-]\\d{2}:?\\d{2})?$'
    );
    private static final Pattern PADRAO_ETIQUETA = Pattern.compile('(?i)<(br|/p|/div|/li|/tr)[^>]*>');
    private static final Pattern PADRAO_HTML = Pattern.compile('<[^>]+>');
    private static final Pattern PADRAO_ENTIDADE = Pattern.compile('&#\\d+;');

    // ------------------------------------------------------------------
    // Envelope
    // ------------------------------------------------------------------

    /** Tarefas de uma listagem. Devolve lista vazia quando o corpo não traz nenhuma. */
    public static List<SC_NosTarefa> listagem(String corpo) {
        List<SC_NosTarefa> tarefas = new List<SC_NosTarefa>();
        Object dados = conteudo(corpo);
        if (dados instanceof List<Object>) {
            for (Object linha : (List<Object>) dados) {
                SC_NosTarefa tarefa = daLinha(linha, false);
                if (tarefa != null) {
                    tarefas.add(tarefa);
                }
            }
        } else if (dados instanceof Map<String, Object>) {
            // A API já devolveu result_data.data como objecto único numa listagem.
            SC_NosTarefa tarefa = daLinha(dados, false);
            if (tarefa != null) {
                tarefas.add(tarefa);
            }
        }
        return tarefas;
    }

    /** Tarefa de um detalhe, ou null quando o corpo não a traz. */
    public static SC_NosTarefa detalhe(String corpo) {
        Object dados = conteudo(corpo);
        if (dados instanceof Map<String, Object>) {
            return daLinha(dados, true);
        }
        if (dados instanceof List<Object> && !((List<Object>) dados).isEmpty()) {
            return daLinha(((List<Object>) dados).get(0), true);
        }
        return null;
    }

    /**
     * O instante em que a NOS respondeu, lido do `timestamp` do envelope (milissegundos).
     * É a data de leitura de um corpo guardado: um reprocessamento e a carga histórica
     * dizem quando a resposta foi lida, e não quando estão a ser corridos. Null quando o
     * envelope não o traz.
     */
    public static Datetime instanteDoEnvelope(String corpo) {
        if (String.isBlank(corpo)) {
            return null;
        }
        try {
            Object raiz = JSON.deserializeUntyped(corpo);
            if (!(raiz instanceof Map<String, Object>)) {
                return null;
            }
            Object carimbo = ((Map<String, Object>) raiz).get('timestamp');
            if (carimbo == null) {
                return null;
            }
            // Por String, porque deserializeUntyped devolve Integer, Long ou Double
            // conforme a grandeza do número, e o carimbo não cabe sempre no mesmo tipo.
            Long milissegundos = Long.valueOf(String.valueOf(carimbo).split('\\.')[0]);
            // Um carimbo fora de qualquer época plausível é lixo, não uma data.
            return milissegundos < 946684800000L ? null : Datetime.newInstance(milissegundos);
        } catch (Exception e) {
            return null;
        }
    }

    private static Object conteudo(String corpo) {
        if (String.isBlank(corpo)) {
            return null;
        }
        try {
            Object raiz = JSON.deserializeUntyped(corpo);
            if (!(raiz instanceof Map<String, Object>)) {
                return null;
            }
            Object resultado = ((Map<String, Object>) raiz).get('result_data');
            if (!(resultado instanceof Map<String, Object>)) {
                return null;
            }
            return ((Map<String, Object>) resultado).get('data');
        } catch (Exception e) {
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Linha
    // ------------------------------------------------------------------

    private static SC_NosTarefa daLinha(Object linha, Boolean doDetalhe) {
        if (!(linha instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> campos = (Map<String, Object>) linha;
        String identificador = texto(campos.get('ID'));
        if (String.isBlank(identificador)) {
            return null;
        }

        SC_NosTarefa tarefa = new SC_NosTarefa();
        tarefa.veioDoDetalhe = doDetalhe;
        tarefa.id = identificador;
        tarefa.referenciaOcorrencia = texto(campos.get('ReferenceID'));
        tarefa.estado = estadoNormalizado(texto(campos.get('Status')));
        tarefa.tipoPedido = texto(campos.get('RequestType'));
        tarefa.grupo = texto(campos.get('AssignedGroup'));
        tarefa.prioridade = texto(campos.get('Priority'));
        tarefa.utilizador = texto(campos.get('AssignedUser'));
        tarefa.resumo = texto(campos.get('Summary'));
        tarefa.contrato = texto(campos.get('ServiceContract'));
        tarefa.dataAtribuicao = paraGmt(texto(campos.get('AssignedDate')));
        tarefa.dataInicio = paraGmt(texto(campos.get('StartDate')));
        tarefa.dataFim = paraGmt(texto(campos.get('EndDate')));
        tarefa.notas = texto(campos.get('Notes'));

        Object elementos = campos.get('NetworkElements');
        if (elementos instanceof List<Object>) {
            for (Object elemento : (List<Object>) elementos) {
                String nome = elemento instanceof Map<String, Object>
                    ? texto(((Map<String, Object>) elemento).get('name'))
                    : texto(elemento);
                if (String.isNotBlank(nome)) {
                    tarefa.elementosRede.add(nome);
                }
            }
        }

        Object interaccoes = campos.get('Interactions');
        if (interaccoes instanceof List<Object>) {
            for (Object bruta : (List<Object>) interaccoes) {
                if (!(bruta instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> item = (Map<String, Object>) bruta;
                SC_NosTarefa.Interaccao interaccao = new SC_NosTarefa.Interaccao();
                interaccao.id = texto(item.get('ID'));
                interaccao.tipo = texto(item.get('Type'));
                interaccao.resumo = texto(item.get('Summary'));
                interaccao.notas = texto(item.get('Notes'));
                interaccao.fonte = texto(item.get('Source'));
                interaccao.criadaEm = paraGmt(texto(item.get('CreatedDate')));
                tarefa.interaccoes.add(interaccao);
            }
        }
        return tarefa;
    }

    /**
     * A NOS escreve o mesmo estado de duas maneiras (CLOSED e Closed). Guarda-se em
     * maiúsculas, que é o que a picklist Estado_Cliente__c tem como valor de API.
     */
    public static String estadoNormalizado(String valor) {
        return String.isBlank(valor) ? null : valor.trim().toUpperCase();
    }

    // ------------------------------------------------------------------
    // Datas
    // ------------------------------------------------------------------

    /** Converte a data da NOS para GMT. Devolve null se o formato não for reconhecido. */
    public static Datetime paraGmt(String valor) {
        if (String.isBlank(valor)) {
            return null;
        }
        Matcher leitor = PADRAO_DATA.matcher(valor.trim());
        if (!leitor.matches()) {
            return null;
        }
        try {
            Integer mes = Integer.valueOf(leitor.group(2));
            Integer dia = Integer.valueOf(leitor.group(3));
            Integer hora = Integer.valueOf(leitor.group(4));
            Integer minuto = Integer.valueOf(leitor.group(5));
            Integer segundo = Integer.valueOf(leitor.group(6));
            // Datetime.newInstanceGmt aceita valores fora do intervalo e roda o calendário:
            // um mês 13 daria Janeiro do ano seguinte. Uma data impossível é dado inválido.
            if (mes < 1 || mes > 12 || dia < 1 || dia > 31 || hora > 23 || minuto > 59 || segundo > 59) {
                return null;
            }
            Datetime instante = Datetime.newInstanceGmt(
                Integer.valueOf(leitor.group(1)), mes, dia, hora, minuto, segundo
            );
            return instante.addMinutes(-minutosDeOffset(leitor.group(8)));
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer minutosDeOffset(String fuso) {
        if (String.isBlank(fuso) || 'Z'.equalsIgnoreCase(fuso)) {
            return 0;
        }
        String limpo = fuso.replace(':', '');
        Integer sinal = limpo.startsWith('-') ? -1 : 1;
        Integer horas = Integer.valueOf(limpo.substring(1, 3));
        Integer minutos = Integer.valueOf(limpo.substring(3, 5));
        return sinal * (horas * 60 + minutos);
    }

    // ------------------------------------------------------------------
    // Texto
    // ------------------------------------------------------------------

    /**
     * Notes chega em HTML. As etiquetas de fim de bloco viram mudança de linha para o
     * texto continuar legível, as restantes desaparecem e as entidades voltam a texto.
     */
    public static String textoSemHtml(String valor) {
        if (String.isBlank(valor)) {
            return '';
        }
        String limpo = PADRAO_ETIQUETA.matcher(valor).replaceAll('\n');
        limpo = PADRAO_HTML.matcher(limpo).replaceAll('');
        limpo = limpo.unescapeHtml4();
        // A NOS escapa duas vezes: o corpo traz &amp;#124; onde queria uma barra. Uma
        // segunda passagem só quando sobram entidades numéricas, para não adivinhar.
        if (PADRAO_ENTIDADE.matcher(limpo).find()) {
            limpo = limpo.unescapeHtml4();
        }
        // Sobras de linhas vazias que as etiquetas deixaram para trás.
        limpo = limpo.replaceAll('[ \\t]+\n', '\n').replaceAll('\n{3,}', '\n\n');
        return limpo.trim();
    }

    private static String texto(Object valor) {
        if (valor == null) {
            return null;
        }
        String bruto = String.valueOf(valor).trim();
        return bruto.length() == 0 ? null : bruto;
    }
}