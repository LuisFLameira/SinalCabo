/**
 * SC_PreverAprovacao (C11, previsao do gate G2)
 *
 * Diz ao comercial, ANTES de confirmar a submissao, o que a matriz de aprovacao vai decidir com os
 * valores que ele acabou de introduzir: se precisa de aprovacao, de quem, ate' que nivel, e se foi
 * o valor ou a margem a exigi-la.
 *
 * NAO GRAVA NADA. E' a razao de existir desta classe em vez de se chamar o SC_AvaliacaoAprovacao:
 * o avaliar grava os campos de decisao na oportunidade, e esse update dispara o
 * SC_AutoSubmit_Aprovacao, ou seja usar o motor para pre-visualizar SUBMETIA a proposta. Aqui ha
 * zero DML, portanto nao ha submissao, nem OpportunityShare, nem campos de decisao escritos.
 *
 * MESMA DECISAO, NAO UMA SEGUNDA IMPLEMENTACAO: a decisao vem do
 * SC_AvaliacaoAprovacao.prever, que corre o mesmo carregarContexto e o mesmo decidirUma que o
 * avaliar corre a seguir. Por isso a previsao reflecte, de graca, a autonomia total, os
 * substitutos de aprovadores ausentes, o fallback pelo director da Empresa Lider e a lacuna de
 * configuracao (SemGovernacao). O ecra nunca esconde nenhum destes casos.
 *
 * A MARGEM: chega calculada por SC_AvaliacaoAprovacao.margemDe(amount, custo), porque o
 * Margem_Percentual__c e' formula e nao existe numa oportunidade em memoria com valores novos. O
 * margemDe replica a formula, arredondamento a uma casa incluido, para a fronteira da previsao ser
 * a mesma da decisao (uma proposta com 21,875% de margem e' avaliada a 21,9% nos dois lados).
 *
 * Uma oportunidade por chamada, que e' como o ecra do G2 pergunta. O metodo aceita lista por ser
 * invocable, e cada elemento paga o seu contexto (3 a 4 SOQL); prever lotes grandes exigiria
 * carregar o contexto uma vez, e hoje nao ha quem o peca.
 */
public with sharing class SC_PreverAprovacao {

    // A oportunidade nao e' legivel (apagada, ou sem acesso a quem corre o ecra). Vai por excepcao
    // e nao por um Result vazio, para o flow cair no faultConnector da acao e mostrar a frase
    // neutra: a previsao falhar nunca pode impedir a submissao.
    public class PrevisaoIndisponivelException extends Exception {}

    public class Request {
        @InvocableVariable(required=true label='Opportunity ID') public Id opportunityId;
        @InvocableVariable(label='Valor da proposta') public Decimal amount;
        @InvocableVariable(label='Custo estimado') public Decimal custoEstimado;
    }

    public class Result {
        @InvocableVariable(label='Requer Aprovacao') public Boolean requerAprovacao;
        @InvocableVariable(label='Requer N2') public Boolean requerN2;
        @InvocableVariable(label='Requer N3') public Boolean requerN3;
        // 0 autonomo, 1 N1, 2 cadeia N1+N2, 3 cadeia N1+N2+N3 (ja com o clamp ao nº de aprovadores)
        @InvocableVariable(label='Nivel de aprovacao') public Integer nivel;
        // 'Regra', 'Fallback', 'SemGovernacao' ou 'AutonomiaTotal' (ver SC_AvaliacaoAprovacao)
        @InvocableVariable(label='Origem da decisao') public String origem;
        // nomes de quem vai receber o pedido, com os substitutos de ausentes ja aplicados; nulo
        // quando o nivel nao chega la' ou quando o utilizador nao e' legivel a quem ve o ecra
        @InvocableVariable(label='Aprovador N1 (nome)') public String aprovadorN1Nome;
        @InvocableVariable(label='Aprovador N2 (nome)') public String aprovadorN2Nome;
        @InvocableVariable(label='Aprovador N3 (nome)') public String aprovadorN3Nome;
        // a autonomia da regra que decidiu: tecto de valor e piso de margem do nivel 0
        @InvocableVariable(label='Autonomia de valor') public Decimal autonomiaValor;
        @InvocableVariable(label='Autonomia de margem') public Decimal autonomiaMargem;
        @InvocableVariable(label='Margem calculada') public Decimal margemCalculada;
        // os mesmos tres numeros ja escritos para o ecra. O flow nao os pode formatar: o TEXT()
        // de uma formula preserva a escala do campo e escreve "150000.00" e "13.00". A formatacao
        // e' feita aqui, em pt-PT (ponto nos milhares, virgula nos decimais) e sem depender do
        // locale de quem corre o ecra.
        @InvocableVariable(label='Autonomia de valor (texto)') public String autonomiaValorTexto;
        @InvocableVariable(label='Autonomia de margem (texto)') public String autonomiaMargemTexto;
        @InvocableVariable(label='Margem calculada (texto)') public String margemCalculadaTexto;
        // 'Valor', 'Margem', 'Ambos' ou 'Nenhum': qual dos dois eixos exigiu a aprovacao
        @InvocableVariable(label='Eixo decisor') public String eixoDecisor;
        @InvocableVariable(label='Condicao da regra') public String condicao;
    }

    @InvocableMethod(label='Prever Aprovacao (matriz, sem gravar)'
                     description='Devolve o que a matriz vai decidir para estes valores, sem gravar nem submeter')
    public static List<Result> prever(List<Request> pedidos) {
        List<Result> resultados = new List<Result>();
        if (pedidos == null || pedidos.isEmpty()) return resultados;

        Set<Id> oppIds = new Set<Id>();
        for (Request p : pedidos) if (p != null && p.opportunityId != null) oppIds.add(p.opportunityId);

        // 1 SOQL: a classificacao da oportunidade, que e' o que a matriz usa como chave. O Amount e
        // o Custo_Estimado__c vem do ecra e nao da base de dados, que e' o ponto da previsao.
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, OwnerId, Tipo_Negocio__c, Area_Negocio__c, Empresa_Lider__c
            FROM Opportunity WHERE Id IN :oppIds WITH USER_MODE
        ]);

        List<SC_AvaliacaoAprovacao.Result> decisoes = new List<SC_AvaliacaoAprovacao.Result>();
        List<Decimal> margens = new List<Decimal>();
        Set<Id> porNomear = new Set<Id>();

        for (Request p : pedidos) {
            Opportunity base = (p != null && p.opportunityId != null) ? opps.get(p.opportunityId) : null;
            if (base == null) {
                throw new PrevisaoIndisponivelException(
                    'A oportunidade nao esta acessivel para prever a aprovacao: '
                    + (p == null ? 'pedido vazio' : String.valueOf(p.opportunityId)));
            }

            Opportunity emMemoria = base.clone(true, false, false, false);
            emMemoria.Amount = p.amount;
            emMemoria.Custo_Estimado__c = p.custoEstimado;

            SC_AvaliacaoAprovacao.Result d = SC_AvaliacaoAprovacao.prever(emMemoria);
            decisoes.add(d);
            margens.add(SC_AvaliacaoAprovacao.margemDe(p.amount, p.custoEstimado));
            for (Id a : new List<Id>{ d.aprovadorN1, d.aprovadorN2, d.aprovadorN3 }) {
                if (a != null) porNomear.add(a);
            }
        }

        // 1 SOQL: os nomes de todos os aprovadores designados, de uma vez. Em USER_MODE, um
        // utilizador que o comercial nao consiga ler simplesmente nao vem, e o nome fica nulo (o
        // ecra tem de aguentar o nome em falta sem deixar de dizer que ha aprovacao).
        Map<Id, String> nomes = new Map<Id, String>();
        if (!porNomear.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :porNomear WITH USER_MODE]) {
                nomes.put(u.Id, u.Name);
            }
        }

        for (Integer i = 0; i < decisoes.size(); i++) {
            resultados.add(paraResult(decisoes[i], margens[i], nomes));
        }
        return resultados;
    }

    private static Result paraResult(SC_AvaliacaoAprovacao.Result d, Decimal margem, Map<Id, String> nomes) {
        Result r = new Result();
        r.requerAprovacao = (d.requerAprovacao == true);
        r.requerN2 = (d.requerN2 == true);
        r.requerN3 = (d.requerN3 == true);
        r.nivel = r.requerN3 ? 3 : (r.requerN2 ? 2 : (r.requerAprovacao ? 1 : 0));
        r.origem = d.origem;
        r.aprovadorN1Nome = nomes.get(d.aprovadorN1);
        r.aprovadorN2Nome = nomes.get(d.aprovadorN2);
        r.aprovadorN3Nome = nomes.get(d.aprovadorN3);
        r.autonomiaValor = d.autonomiaValor;
        r.autonomiaMargem = d.autonomiaMargem;
        r.margemCalculada = margem;
        r.autonomiaValorTexto = formatarValor(d.autonomiaValor);
        r.autonomiaMargemTexto = formatarPercentagem(d.autonomiaMargem, null);
        r.margemCalculadaTexto = formatarPercentagem(margem, 1);
        r.eixoDecisor = eixoDecisor(r.nivel, d.nivelValor, d.nivelMargem);
        r.condicao = d.condicao;
        return r;
    }

    /**
     * Qual dos dois eixos da matriz exigiu a aprovacao, para o ecra poder dizer "e' a margem, e nao
     * o valor, que exige aprovacao".
     *
     * Compara os niveis dos dois eixos ANTES do clamp: quem conta mais tectos furados e' quem
     * decide. 'Nenhum' quando a proposta e' autonoma e tambem quando nao houve regra a decidir
     * (fallback, lacuna de configuracao ou autonomia total nao tem eixos, e os niveis vem nulos).
     */
    private static String eixoDecisor(Integer nivel, Integer nivelValor, Integer nivelMargem) {
        if (nivel == 0 || nivelValor == null || nivelMargem == null) return 'Nenhum';
        if (nivelMargem > nivelValor) return 'Margem';
        if (nivelValor > nivelMargem) return 'Valor';
        return (nivelValor > 0) ? 'Ambos' : 'Nenhum';
    }

    // ══════════════ formatacao pt-PT ══════════════
    //
    // Nao se usa Decimal.format(): esse depende do locale de quem corre o flow, e o mesmo ecra
    // escreveria "150,000" a um utilizador em ingles. Aqui o resultado e' o mesmo para todos.

    /**
     * Um valor em euros: milhares separados por ponto, sem simbolo de moeda. Inteiro quando nao ha
     * centimos ("150.000"), duas casas quando ha ("1.234,50"). Nulo devolve nulo, para o ecra poder
     * distinguir "nao ha tecto" de "o tecto e' zero".
     */
    @TestVisible
    private static String formatarValor(Decimal v) {
        if (v == null) return null;
        Decimal x = v.setScale(2, System.RoundingMode.HALF_UP);
        Integer casas = (x == x.setScale(0, System.RoundingMode.DOWN)) ? 0 : 2;
        return escrever(x, casas, true);
    }

    /**
     * Uma percentagem sem o simbolo, que o texto do ecra ja traz.
     *
     * Com casas a nulo escreve o minimo que representa o numero ("20", "12,5"), que e' o que serve
     * para um tecto da matriz. Com casas fixas arredonda e preenche ("13,0"), que e' o que serve
     * para a margem calculada, sempre comparavel com o Margem_Percentual__c (scale 1).
     */
    @TestVisible
    private static String formatarPercentagem(Decimal v, Integer casas) {
        if (v == null) return null;
        Integer usar = casas;
        if (usar == null) {
            Decimal x = v.setScale(2, System.RoundingMode.HALF_UP);
            usar = (x == x.setScale(0, System.RoundingMode.DOWN))
                 ? 0
                 : ((x == x.setScale(1, System.RoundingMode.DOWN)) ? 1 : 2);
        }
        return escrever(v, usar, false);
    }

    // O escritor que os dois partilham: arredonda, agrupa os milhares se lhe pedirem, e junta a
    // parte decimal com virgula e com o numero de casas pedido.
    private static String escrever(Decimal v, Integer casas, Boolean agruparMilhares) {
        Decimal x = v.setScale(casas, System.RoundingMode.HALF_UP);
        Boolean negativo = x < 0;
        Decimal abs = x.abs();
        Long inteiro = abs.longValue();
        String texto = agruparMilhares ? agrupar(inteiro) : String.valueOf(inteiro);
        if (casas > 0) {
            Integer factor = 1;
            for (Integer i = 0; i < casas; i++) factor *= 10;
            String decimais = String.valueOf(((abs - inteiro) * factor)
                                             .setScale(0, System.RoundingMode.HALF_UP).longValue());
            while (decimais.length() < casas) decimais = '0' + decimais;
            texto += ',' + decimais;
        }
        return (negativo ? '-' : '') + texto;
    }

    // Ponto de tres em tres digitos, a contar da direita.
    private static String agrupar(Long inteiro) {
        String digitos = String.valueOf(inteiro);
        String saida = '';
        Integer contados = 0;
        for (Integer i = digitos.length() - 1; i >= 0; i--) {
            saida = digitos.substring(i, i + 1) + saida;
            contados++;
            if (Math.mod(contados, 3) == 0 && i > 0) saida = '.' + saida;
        }
        return saida;
    }
}