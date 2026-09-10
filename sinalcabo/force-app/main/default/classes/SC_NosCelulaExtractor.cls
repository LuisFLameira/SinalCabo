/**
 * Proposta de célula a partir do que a NOS escreve, para poupar tempo ao despacho.
 *
 * É proposta e não decisão: a classificação é do despachante e a acção Classificar
 * é que a confirma. Por isso este código nunca reescreve uma célula já preenchida
 * nem toca numa ordem com Classificacao_Confirmada__c ligada, e o que propõe fica
 * marcado com Origem_Celula__c igual a "Proposta pela API".
 *
 * Onde procura, por esta ordem:
 *  1. NetworkElements[].name do detalhe, quando o nome começa por três letras e dois
 *     dígitos. É a fonte fiável, porque é um campo estruturado da NOS;
 *  2. o resumo da tarefa, onde o código aparece no meio de texto livre.
 * Um código dá proposta, vários dão a primeira mais as candidatas, nenhum deixa a
 * ordem por classificar. Um código que não existe no cadastro não cria nada e deixa
 * uma ocorrência de Aviso.
 */
public with sharing class SC_NosCelulaExtractor {
    // Três letras maiúsculas e dois dígitos, sem letra ou dígito colado de cada lado.
    private static final Pattern PADRAO_CELULA = Pattern.compile('(?<![A-Z0-9])([A-Z]{3}\\d{2})(?![0-9])');
    private static final Integer TECTO_CANDIDATAS = 255;

    private final Map<String, Celula__c> celulasPorCodigo = new Map<String, Celula__c>();
    private final List<Ocorrencia_Integracao__c> ocorrencias = new List<Ocorrencia_Integracao__c>();
    private final Set<String> codigosAvisados = new Set<String>();
    private final Id loteId;

    public SC_NosCelulaExtractor(Id loteId) {
        this.loteId = loteId;
    }

    public List<Ocorrencia_Integracao__c> ocorrencias() {
        return ocorrencias;
    }

    /** Códigos candidatos de um texto, pela ordem em que aparecem e sem repetições. */
    public static List<String> codigos(String texto) {
        List<String> encontrados = new List<String>();
        if (String.isBlank(texto)) {
            return encontrados;
        }
        Set<String> vistos = new Set<String>();
        Matcher leitor = PADRAO_CELULA.matcher(texto.toUpperCase());
        while (leitor.find()) {
            String codigo = leitor.group(1);
            if (vistos.add(codigo)) {
                encontrados.add(codigo);
            }
        }
        return encontrados;
    }

    /** Códigos de uma tarefa: primeiro os elementos de rede, depois o resumo. */
    public static List<String> codigosDaTarefa(SC_NosTarefa tarefa) {
        List<String> encontrados = new List<String>();
        Set<String> vistos = new Set<String>();
        if (tarefa.elementosRede != null) {
            for (String elemento : tarefa.elementosRede) {
                // O elemento de rede só conta quando começa pelo código: é campo estruturado.
                List<String> doElemento = codigos(elemento);
                if (!doElemento.isEmpty() && elemento.toUpperCase().startsWith(doElemento[0])) {
                    if (vistos.add(doElemento[0])) {
                        encontrados.add(doElemento[0]);
                    }
                }
            }
        }
        if (encontrados.isEmpty()) {
            for (String codigo : codigos(tarefa.resumo)) {
                if (vistos.add(codigo)) {
                    encontrados.add(codigo);
                }
            }
        }
        return encontrados;
    }

    /** Lê de uma vez as células que o lote inteiro precisa. Uma consulta. */
    public void carregar(List<SC_NosTarefa> tarefas) {
        Set<String> procurados = new Set<String>();
        for (SC_NosTarefa tarefa : tarefas) {
            procurados.addAll(codigosDaTarefa(tarefa));
        }
        if (procurados.isEmpty()) {
            return;
        }
        for (Celula__c celula : [
            SELECT Id, Codigo__c, Tecnologia__c, Territorio__c, Territorio__r.ParentTerritoryId,
                   Localizacao__Latitude__s, Localizacao__Longitude__s
            FROM Celula__c
            WHERE Codigo__c IN :procurados AND Activa__c = TRUE
        ]) {
            celulasPorCodigo.put(celula.Codigo__c, celula);
        }
    }

    /**
     * A regra da divergência de território, escrita num sítio só.
     *
     * O território de uma célula é a ZONA da NOS, que é um território filho do território
     * do grupo. A NOS só diz o grupo, nunca a zona, por isso a comparação faz-se ao nível
     * do PAI: pertence esta zona ao grupo que a NOS atribuiu? Comparar a zona directamente
     * com o grupo daria divergência em todas as ordens.
     *
     * `paiDoTerritorioDaCelula` a nulo quer dizer que o território da célula não tem pai,
     * e nesse caso é ele próprio o território de grupo (é o que se passa nas 24 células que
     * só o KML conhece, penduradas no pai por não terem zona na NOS).
     */
    public static Boolean divergente(Id territorioDaCelula, Id paiDoTerritorioDaCelula, Id territorioDoGrupo) {
        if (territorioDaCelula == null || territorioDoGrupo == null) {
            return false;
        }
        Id grupoDaCelula = paiDoTerritorioDaCelula == null ? territorioDaCelula : paiDoTerritorioDaCelula;
        return grupoDaCelula != territorioDoGrupo;
    }

    /**
     * Propõe a célula na ordem. `territorioDoGrupo` é o território que a NOS atribuiu:
     * quando difere do da célula, fica a marca de divergência para o despacho decidir.
     * Devolve true quando escreveu alguma coisa.
     */
    public Boolean aplicar(WorkOrder ordem, SC_NosTarefa tarefa, Id territorioDoGrupo, Boolean jaTemCelula, Boolean confirmada) {
        // Uma célula confirmada pelo despacho ou já preenchida nunca é reescrita.
        if (jaTemCelula || confirmada) {
            return false;
        }
        List<String> encontrados = codigosDaTarefa(tarefa);
        if (encontrados.isEmpty()) {
            return false;
        }

        Celula__c escolhida;
        List<String> candidatas = new List<String>();
        for (String codigo : encontrados) {
            Celula__c celula = celulasPorCodigo.get(codigo);
            if (celula == null) {
                if (codigosAvisados.add(codigo)) {
                    ocorrencias.add(SC_NosLote.ocorrencia(
                        loteId, SC_NosLote.TIPO_AVISO, tarefa.id, 'Celula__c',
                        'Código de célula sem cadastro na org: ' + codigo, tarefa.resumo
                    ));
                }
                continue;
            }
            if (escolhida == null) {
                escolhida = celula;
            } else {
                candidatas.add(codigo);
            }
        }
        if (escolhida == null) {
            return false;
        }

        ordem.Celula__c = escolhida.Id;
        ordem.Origem_Celula__c = 'Proposta pela API';
        ordem.Classificacao_Confirmada__c = false;
        ordem.Tecnologia__c = escolhida.Tecnologia__c;
        ordem.Celulas_Candidatas__c = candidatas.isEmpty()
            ? null
            : String.join(candidatas, ', ').abbreviate(TECTO_CANDIDATAS);
        if (escolhida.Localizacao__Latitude__s != null) {
            ordem.Latitude = escolhida.Localizacao__Latitude__s;
            ordem.Longitude = escolhida.Localizacao__Longitude__s;
        }
        // A zona da célula manda no despacho; a divergência com o grupo da NOS fica
        // visível no Sinal para alguém decidir, e mede-se ao nível do pai da zona.
        ordem.Divergencia_Territorio__c = divergente(
            escolhida.Territorio__c,
            escolhida.Territorio__c == null ? null : escolhida.Territorio__r.ParentTerritoryId,
            territorioDoGrupo
        );
        if (escolhida.Territorio__c != null) {
            ordem.ServiceTerritoryId = escolhida.Territorio__c;
        }
        return true;
    }
}