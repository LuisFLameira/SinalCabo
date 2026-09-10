/**
 * Fábrica de HttpCalloutMock para os testes da entrada de ordens da NOS.
 *
 * Regista respostas por fragmento do URL, por ordem de registo: a primeira regra que casa
 * ganha, e por isso a regra mais específica regista-se primeiro. Uma regra pode ainda exigir
 * que o URL NÃO contenha um fragmento, para separar a listagem de fechadas (com status=CLOSED)
 * da listagem de abertas (sem status). Cada regra pode devolver sempre a mesma resposta ou
 * uma sequência, para simular dois 504 seguidos ou um 504 seguido de sucesso.
 *
 * Os corpos vivem nos static resources SC_NosFx_*, gerados por scripts/data/build_fixtures.py
 * a partir das respostas reais da API, já anonimizados. São lidos numa única consulta e
 * ficam em cache na transacção.
 *
 * A fábrica guarda os pedidos que recebeu, pela ordem em que chegaram, para os testes
 * assertarem a sequência de chamadas do polling.
 *
 * Exemplo:
 *   SC_NosMockFactory mock = new SC_NosMockFactory()
 *       .registar('listByPartner', 'status=', SC_NosMockFactory.ok('SC_NosFx_ListaAbertas'))
 *       .registar('status=CLOSED', SC_NosMockFactory.ok('SC_NosFx_ListaOk'))
 *       .registar('getByWorkitemId', SC_NosMockFactory.ok('SC_NosFx_DetalheOk'));
 *   Test.setMock(HttpCalloutMock.class, mock);
 */
@IsTest
public with sharing class SC_NosMockFactory implements HttpCalloutMock {
    public class SC_NosMockException extends Exception {}

    private static final String TIPO_JSON = 'application/json';

    // Corpos dos static resources já lidos nesta transacção.
    private static final Map<String, String> CORPO_POR_RECURSO = new Map<String, String>();

    private final List<Regra> regras = new List<Regra>();
    private final Set<String> recursosRegistados = new Set<String>();
    private final List<HttpRequest> pedidos = new List<HttpRequest>();
    private final List<String> urls = new List<String>();
    private Resposta omissao;

    // ------------------------------------------------------------------
    // Registo
    // ------------------------------------------------------------------

    /** Responde a qualquer URL que contenha o fragmento. */
    public SC_NosMockFactory registar(String fragmento, Resposta resposta) {
        return registar(fragmento, null, resposta);
    }

    /** Responde ao URL que contém o fragmento e não contém o excluído (listagem sem status). */
    public SC_NosMockFactory registar(String fragmento, String excluir, Resposta resposta) {
        Regra regra = new Regra();
        regra.fragmento = fragmento;
        regra.excluir = excluir;
        regra.resposta = resposta;
        this.regras.add(regra);
        this.recursosRegistados.addAll(resposta.recursos());
        return this;
    }

    /** Resposta para os URLs que nenhuma regra apanha. Sem ela, um URL desconhecido rebenta. */
    public SC_NosMockFactory registarOmissao(Resposta resposta) {
        this.omissao = resposta;
        this.recursosRegistados.addAll(resposta.recursos());
        return this;
    }

    // ------------------------------------------------------------------
    // Respostas
    // ------------------------------------------------------------------

    /** 200 com o corpo do static resource (por omissão application/json). */
    public static Resposta ok(String nomeRecurso) {
        Resposta resposta = new Resposta();
        resposta.codigo = 200;
        resposta.estado = 'OK';
        resposta.nomeRecurso = nomeRecurso;
        resposta.tipoConteudo = TIPO_JSON;
        return resposta;
    }

    /** Código HTTP e corpo literal, para os casos que não têm fixture. */
    public static Resposta http(Integer codigo, String corpo) {
        Resposta resposta = new Resposta();
        resposta.codigo = codigo;
        resposta.estado = codigo == 200 ? 'OK' : 'Error';
        resposta.corpo = corpo;
        resposta.tipoConteudo = TIPO_JSON;
        return resposta;
    }

    /** Uma resposta por chamada, pela ordem da lista. A última repete-se nas seguintes. */
    public static Resposta sequencia(List<Resposta> passos) {
        if (passos == null || passos.isEmpty()) {
            throw new SC_NosMockException('A sequência tem de ter pelo menos uma resposta.');
        }
        Resposta resposta = new Resposta();
        resposta.passos = passos;
        return resposta;
    }

    /** Callout que rebenta, para o cenário de timeout do cliente. */
    public static Resposta excepcao(String mensagem) {
        Resposta resposta = new Resposta();
        resposta.mensagemDeErro = mensagem;
        return resposta;
    }

    // ------------------------------------------------------------------
    // HttpCalloutMock
    // ------------------------------------------------------------------

    public HttpResponse respond(HttpRequest pedido) {
        this.pedidos.add(pedido);
        this.urls.add(pedido.getEndpoint());
        carregarRecursos(this.recursosRegistados);

        Resposta escolhida;
        for (Regra regra : this.regras) {
            if (regra.casa(pedido.getEndpoint())) {
                escolhida = regra.proxima();
                break;
            }
        }
        if (escolhida == null) {
            escolhida = this.omissao;
        }
        if (escolhida == null) {
            throw new SC_NosMockException(
                'Nenhuma regra registada para o URL ' + pedido.getEndpoint()
            );
        }
        return escolhida.constroi();
    }

    // ------------------------------------------------------------------
    // O que os testes perguntam depois
    // ------------------------------------------------------------------

    /** Número de callouts que a fábrica atendeu. */
    public Integer numeroDeChamadas() {
        return this.urls.size();
    }

    /** URL da chamada na posição pedida, a contar de zero. */
    public String urlDaChamada(Integer indice) {
        if (indice == null || indice < 0 || indice >= this.urls.size()) {
            throw new SC_NosMockException('Não houve chamada na posição ' + indice);
        }
        return this.urls.get(indice);
    }

    /** Todos os URLs, pela ordem em que foram chamados. */
    public List<String> urlsChamados() {
        return this.urls.clone();
    }

    /** Pedido completo da posição pedida, para assertar cabeçalhos ou método. */
    public HttpRequest pedidoDaChamada(Integer indice) {
        if (indice == null || indice < 0 || indice >= this.pedidos.size()) {
            throw new SC_NosMockException('Não houve chamada na posição ' + indice);
        }
        return this.pedidos.get(indice);
    }

    /** Quantas chamadas trouxeram o fragmento no URL. */
    public Integer chamadasQueContem(String fragmento) {
        Integer total = 0;
        for (String url : this.urls) {
            if (url != null && url.contains(fragmento)) {
                total++;
            }
        }
        return total;
    }

    // ------------------------------------------------------------------
    // Static resources
    // ------------------------------------------------------------------

    /** Corpo de um fixture, para os testes compararem sem repetir a consulta. */
    public static String corpoDoRecurso(String nome) {
        carregarRecursos(new Set<String>{ nome });
        return CORPO_POR_RECURSO.get(nome);
    }

    private static void carregarRecursos(Set<String> nomes) {
        Set<String> emFalta = new Set<String>(nomes);
        emFalta.removeAll(CORPO_POR_RECURSO.keySet());
        if (emFalta.isEmpty()) {
            return;
        }
        // Sem USER_MODE de propósito: isto lê metadata dos testes, não dados de negócio,
        // e a consulta tem de funcionar dentro de um System.runAs com uma persona sem
        // acesso a Setup.
        for (StaticResource recurso : [
            SELECT Name, Body
            FROM StaticResource
            WHERE Name IN :emFalta
        ]) {
            CORPO_POR_RECURSO.put(recurso.Name, recurso.Body.toString());
        }
        emFalta.removeAll(CORPO_POR_RECURSO.keySet());
        if (!emFalta.isEmpty()) {
            throw new SC_NosMockException(
                'Static resource não encontrado na org: ' + String.join(new List<String>(emFalta), ', ')
            );
        }
    }

    // ------------------------------------------------------------------
    // Tipos internos
    // ------------------------------------------------------------------

    public class Resposta {
        private Integer codigo;
        private String estado;
        private String corpo;
        private String nomeRecurso;
        private String tipoConteudo;
        private String mensagemDeErro;
        private List<Resposta> passos;
        private Integer chamadasFeitas = 0;
        private Map<String, String> cabecalhos = new Map<String, String>();

        /** Troca o código HTTP, para servir um fixture como 504 ou como 500. */
        public Resposta comCodigo(Integer novoCodigo) {
            this.codigo = novoCodigo;
            this.estado = novoCodigo == 200 ? 'OK' : 'Error';
            return this;
        }

        /** Troca o Content-Type, para o 504 em texto e o 500 do WSO2 em XML. */
        public Resposta comTipo(String novoTipo) {
            this.tipoConteudo = novoTipo;
            return this;
        }

        /** Cabeçalho extra na resposta. */
        public Resposta comCabecalho(String nome, String valor) {
            this.cabecalhos.put(nome, valor);
            return this;
        }

        private Set<String> recursos() {
            Set<String> nomes = new Set<String>();
            if (this.nomeRecurso != null) {
                nomes.add(this.nomeRecurso);
            }
            if (this.passos != null) {
                for (Resposta passo : this.passos) {
                    nomes.addAll(passo.recursos());
                }
            }
            return nomes;
        }

        private Resposta proxima() {
            if (this.passos == null) {
                return this;
            }
            Integer indice = Math.min(this.chamadasFeitas, this.passos.size() - 1);
            this.chamadasFeitas++;
            return this.passos.get(indice);
        }

        private HttpResponse constroi() {
            if (this.mensagemDeErro != null) {
                throw new CalloutException(this.mensagemDeErro);
            }
            HttpResponse resposta = new HttpResponse();
            resposta.setStatusCode(this.codigo);
            resposta.setStatus(this.estado);
            resposta.setHeader('Content-Type', this.tipoConteudo);
            for (String nome : this.cabecalhos.keySet()) {
                resposta.setHeader(nome, this.cabecalhos.get(nome));
            }
            resposta.setBody(
                this.nomeRecurso == null ? this.corpo : CORPO_POR_RECURSO.get(this.nomeRecurso)
            );
            return resposta;
        }
    }

    private class Regra {
        private String fragmento;
        private String excluir;
        private Resposta resposta;

        private Boolean casa(String url) {
            if (url == null) {
                return false;
            }
            if (this.fragmento != null && !url.contains(this.fragmento)) {
                return false;
            }
            return this.excluir == null || !url.contains(this.excluir);
        }

        private Resposta proxima() {
            return this.resposta.proxima();
        }
    }
}