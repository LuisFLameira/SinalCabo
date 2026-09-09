/**
 * SC_NumeroPropostaService (B.4)
 *
 * Atribui o numero da proposta na criacao da oportunidade, no formato SIGLA/NNNNN/AA
 * (ex. UN SOLAR/00001/26): sigla da unidade de negocio, sequencial com cinco casas, ano com
 * dois digitos. Regra definida pelo cliente.
 *
 * DECISOES DE NEGOCIO QUE ESTE CODIGO IMPLEMENTA
 *   - O numero e' atribuido a TODAS as oportunidades, no momento da criacao (Joel, 31/07).
 *     Consequencia aceite: as series tem numeros em falta, porque uma oportunidade cancelada
 *     nao devolve o numero, e existem numeros em oportunidades que nunca geraram proposta.
 *   - O numero NAO leva componente de empresa (Daniela, 03/08). A sigla da unidade substitui-a;
 *     a Empresa Lider continua no seu campo proprio.
 *   - A serie e' por SIGLA e ANO, nao por area. Duas areas com a mesma sigla partilham serie de
 *     proposito, o que a Daniela confirmou a 03/08 para a Inovacao de Produto e o DN 360.
 *   - Sem sigla mapeada, a oportunidade nasce SEM numero e nao e' bloqueada (Joel, 04/08).
 *     Bloquear a criacao de negocio por configuracao em falta e' agressivo; o administrador
 *     corrige a sigla no Custom Metadata sem deploy e a oportunidade seguinte ja leva numero.
 *
 * PORQUE APEX E NAO FLOW: o reset anual sai de graca se o contador for chaveado por sigla e ano,
 * mas a atribuicao precisa de um lock pessimista. Sem ele, duas pessoas a criar oportunidade no
 * mesmo instante recebem o mesmo numero. O `FOR UPDATE` nao existe em Flow.
 *
 * ORDEM DE EXECUCAO: corre em before insert, logo o numero e' gravado no mesmo save, sem segundo
 * DML na Opportunity. Os flows before-save da Opportunity correm ANTES deste trigger; nenhum
 * deles depende do numero.
 *
 * O QUE NAO E TESTAVEL EM APEX: a correccao do lock. Um teste corre numa unica transaccao,
 * portanto uma suite verde NAO prova ausencia de numeros duplicados. So' duas sessoes em
 * paralelo provam isso, e esse teste e' manual.
 *
 * REFERENCIA: desenho e decisoes desta fase em
 * projectos/sinalcabo/outputs/desenho-numeracao-propostas-2026-07-31.md
 */
public with sharing class SC_NumeroPropostaService {

    @TestVisible private static final String SEPARADOR = '/';
    @TestVisible private static final Integer CASAS = 5;

    /** Data usada para o ano da serie. Injectavel para o teste nao ser uma bomba a 1 de Janeiro. */
    @TestVisible private static Date hoje = null;
    private static Date dataDeReferencia() {
        return hoje != null ? hoje : Date.today();
    }

    /**
     * Atribui Numero_Proposta__c a cada oportunidade da lista que ainda nao o tenha.
     * Chamado do before insert. Bulk-safe: 1 SOQL ao contador e 1 DML, independentemente do lote.
     */
    public static void atribuir(List<Opportunity> novas) {
        if (novas == null || novas.isEmpty()) return;
        if (bypassLigado()) return;

        Integer ano = dataDeReferencia().year();
        String anoCurto = String.valueOf(ano).right(2);

        // 1. area -> sigla, do Custom Metadata. getAll() nao gasta SOQL.
        Map<String, String> siglaPorArea = new Map<String, String>();
        for (SC_Area_Sigla__mdt m : SC_Area_Sigla__mdt.getAll().values()) {
            if (m.Activa__c == true && String.isNotBlank(m.Area_Label__c) && String.isNotBlank(m.Sigla__c)) {
                siglaPorArea.put(m.Area_Label__c, m.Sigla__c);
            }
        }

        // 2. agrupar por sigla: e' a sigla que define a serie, nunca a area.
        Map<String, List<Opportunity>> porSigla = new Map<String, List<Opportunity>>();
        for (Opportunity o : novas) {
            if (String.isNotBlank(o.Numero_Proposta__c)) continue;   // ja traz numero (migracao)
            String sigla = siglaPorArea.get(o.Area_Negocio__c);
            if (String.isBlank(sigla)) continue;                     // sem sigla: fica sem numero
            if (!porSigla.containsKey(sigla)) porSigla.put(sigla, new List<Opportunity>());
            porSigla.get(sigla).add(o);
        }
        if (porSigla.isEmpty()) return;

        // 3. trancar os contadores das siglas em jogo, todos de uma vez.
        Set<String> chaves = new Set<String>();
        for (String s : porSigla.keySet()) chaves.add(chave(s, ano));

        Map<String, Contador_Proposta__c> contadores = new Map<String, Contador_Proposta__c>();
        // FOR UPDATE nao combina com ORDER BY.
        for (Contador_Proposta__c c : [
            SELECT Id, Chave__c, Sigla__c, Ano__c, Ultimo_Numero__c, Activo__c
            FROM Contador_Proposta__c WHERE Chave__c IN :chaves FOR UPDATE
        ]) {
            contadores.put(c.Chave__c, c);
        }

        // 4. criar os que faltam. Duas transaccoes concorrentes podem tentar criar o mesmo:
        //    a unicidade da Chave__c faz a segunda falhar, e nesse caso re-le a linha e segue.
        List<Contador_Proposta__c> aCriar = new List<Contador_Proposta__c>();
        for (String s : porSigla.keySet()) {
            String k = chave(s, ano);
            if (!contadores.containsKey(k)) {
                aCriar.add(new Contador_Proposta__c(
                    Name = k, Chave__c = k, Sigla__c = s, Ano__c = ano,
                    Ultimo_Numero__c = 0, Activo__c = true));
            }
        }
        if (!aCriar.isEmpty()) {
            List<Database.SaveResult> rs = Database.insert(aCriar, false);
            Set<String> reler = new Set<String>();
            for (Integer i = 0; i < rs.size(); i++) {
                if (rs[i].isSuccess()) {
                    contadores.put(aCriar[i].Chave__c, aCriar[i]);
                } else {
                    // tipicamente DUPLICATE_VALUE: outra transaccao criou-o entretanto.
                    reler.add(aCriar[i].Chave__c);
                }
            }
            if (!reler.isEmpty()) {
                for (Contador_Proposta__c c : [
                    SELECT Id, Chave__c, Sigla__c, Ano__c, Ultimo_Numero__c, Activo__c
                    FROM Contador_Proposta__c WHERE Chave__c IN :reler FOR UPDATE
                ]) {
                    contadores.put(c.Chave__c, c);
                }
            }
        }

        // 5. alocar em memoria e escrever o numero.
        List<Contador_Proposta__c> aActualizar = new List<Contador_Proposta__c>();
        for (String sigla : porSigla.keySet()) {
            Contador_Proposta__c c = contadores.get(chave(sigla, ano));
            if (c == null || c.Activo__c != true) continue;   // contador travado: sem numero

            Decimal ultimo = (c.Ultimo_Numero__c == null) ? 0 : c.Ultimo_Numero__c;
            for (Opportunity o : porSigla.get(sigla)) {
                ultimo = ultimo + 1;
                o.Numero_Proposta__c = formatar(sigla, ultimo, anoCurto);
            }
            c.Ultimo_Numero__c = ultimo;
            aActualizar.add(c);
        }
        if (!aActualizar.isEmpty()) update aActualizar;
    }

    /** SIGLA|AAAA. O ano vai com quatro digitos na chave e dois no numero visivel. */
    @TestVisible
    private static String chave(String sigla, Integer ano) {
        return sigla + '|' + String.valueOf(ano);
    }

    /** SIGLA/NNNNN/AA, com o sequencial preenchido a zeros a esquerda. */
    @TestVisible
    private static String formatar(String sigla, Decimal seq, String anoCurto) {
        String n = String.valueOf(seq.longValue());
        while (n.length() < CASAS) n = '0' + n;
        return sigla + SEPARADOR + n + SEPARADOR + anoCurto;
    }

    /**
     * Bypass para a migracao. Custom Setting hierarquico ja existente (SC_Aprovacao_Config),
     * ligado apenas no utilizador que faz a carga, para o historico entrar sem consumir a serie.
     */
    @TestVisible
    private static Boolean bypassLigado() {
        SC_Aprovacao_Config__c cfg = SC_Aprovacao_Config__c.getInstance();
        return cfg != null && cfg.Bypass_Numeracao__c == true;
    }
}