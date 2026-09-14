/**
 * Onde uma linha do ficheiro do PNI vira uma Work Order. É o ponto de entrada único.
 *
 * Todos os caminhos passam por aqui: o carregamento de um pedaço pelo ecrã, a
 * simulação, que faz tudo menos gravar, e o reprocessamento de linhas rejeitadas.
 * Nenhum deles lê o ficheiro a partir desta classe: recebem as linhas já lidas, o que
 * faz do reprocessamento a mesma coisa que um carregamento normal.
 *
 * Regras que esta classe garante:
 *  - a chave é o identificador completo do PNI, sem tirar sufixos. Está medido que
 *    normalizar não ganha um único par e funde 1.155 chaves distintas, porque
 *    250894029_AIR e 250894029_AIR_TAB são duas ordens da mesma obra;
 *  - identificadores repetidos no mesmo pedaço colapsam, e vence a última linha;
 *  - linhas alteradas antes da data de corte não entram;
 *  - assinatura igual à guardada não escreve nada, para uma segunda importação do
 *    mesmo ficheiro não marcar milhares de ordens como alteradas;
 *  - o ficheiro do PNI ganha sobre o que a ligação à NOS escreveu, mas só nos campos
 *    que são dele: o estado do PNI, a data de alteração e a origem. O estado do
 *    NetGuard, as datas da NOS e a assinatura da NOS nunca são tocados;
 *  - uma ordem que não existe nasce, marcada com a origem, para o despacho saber que
 *    ainda não foi confirmada pela ligação;
 *  - uma linha que falha não leva as outras atrás, e fica registada como rejeição
 *    reprocessável.
 */
public with sharing class SC_PniUpsertService {
    /** Estado com que nasce uma ordem que só existe no ficheiro. */
    public static final String STATUS_NOVA = 'New';

    /** Contadores de uma passagem, para o lote fechar com números. */
    public class Resultado {
        public Integer lidos = 0;
        public Integer criados = 0;
        public Integer actualizados = 0;
        public Integer rejeitados = 0;
        public Integer inalterados = 0;
        /** Linhas descartadas por serem anteriores à data de corte. */
        public Integer forasDeJanela = 0;
        /** Ordens em que o estado do ficheiro difere do que a ligação tinha escrito. */
        public Integer divergentes = 0;
        public List<SC_PniCsv.Rejeicao> rejeicoes = new List<SC_PniCsv.Rejeicao>();
        public List<String> criadas = new List<String>();

        public void juntar(Resultado outro) {
            lidos += outro.lidos;
            criados += outro.criados;
            actualizados += outro.actualizados;
            rejeitados += outro.rejeitados;
            inalterados += outro.inalterados;
            forasDeJanela += outro.forasDeJanela;
            divergentes += outro.divergentes;
            rejeicoes.addAll(outro.rejeicoes);
            criadas.addAll(outro.criadas);
        }
    }

    private final Id loteId;
    private final Boolean simulacao;
    private final Date corte;
    private Id contaCliente;
    private Boolean contaProcurada = false;

    public SC_PniUpsertService(Id loteId, Boolean simulacao) {
        this(loteId, simulacao, SC_PniConfig.dataCorte());
    }

    @TestVisible
    private SC_PniUpsertService(Id loteId, Boolean simulacao, Date corte) {
        this.loteId = loteId;
        this.simulacao = simulacao == true;
        this.corte = corte;
    }

    // ------------------------------------------------------------------
    // Entrada
    // ------------------------------------------------------------------

    /**
     * Trata um conjunto de linhas já lidas. Numa simulação faz tudo menos gravar, para
     * a pessoa ver o impacto antes de confirmar.
     */
    public Resultado tratar(List<SC_PniLinha> linhas) {
        Resultado r = new Resultado();
        if (linhas == null || linhas.isEmpty()) {
            return r;
        }
        r.lidos = linhas.size();

        // Repetidos no mesmo pedaço colapsam e vence o último, que é o mais recente na
        // ordem em que o ficheiro os traz.
        Map<String, SC_PniLinha> porChave = new Map<String, SC_PniLinha>();
        for (SC_PniLinha linha : linhas) {
            if (foraDaJanela(linha)) {
                r.forasDeJanela++;
                continue;
            }
            porChave.put(linha.chave(), linha);
        }
        if (porChave.isEmpty()) {
            return r;
        }

        Map<String, WorkOrder> existentes = lerExistentes(porChave.keySet());

        List<WorkOrder> paraGravar = new List<WorkOrder>();
        List<String> referencias = new List<String>();
        List<Boolean> ehNova = new List<Boolean>();

        for (String chave : porChave.keySet()) {
            SC_PniLinha linha = porChave.get(chave);
            WorkOrder existente = existentes.get(chave);
            Boolean nova = existente == null;

            if (!nova && linha.assinatura() == existente.Assinatura_PNI__c) {
                r.inalterados++;
                continue;
            }
            if (!nova && divergeDaLigacao(existente, linha)) {
                r.divergentes++;
            }

            WorkOrder ordem = new WorkOrder();
            aplicar(ordem, linha, nova);
            paraGravar.add(ordem);
            referencias.add(chave);
            ehNova.add(nova);
        }

        if (paraGravar.isEmpty()) {
            return r;
        }
        if (simulacao) {
            // A simulação conta o que aconteceria e não toca em nenhuma ordem.
            for (Integer i = 0; i < paraGravar.size(); i++) {
                if (ehNova[i]) {
                    r.criados++;
                    r.criadas.add(referencias[i]);
                } else {
                    r.actualizados++;
                }
            }
            return r;
        }

        List<Database.UpsertResult> gravados = Database.upsert(
            paraGravar, WorkOrder.Referencia_Ordem_Cliente__c, false
        );
        for (Integer i = 0; i < gravados.size(); i++) {
            if (gravados[i].isSuccess()) {
                if (ehNova[i]) {
                    r.criados++;
                    r.criadas.add(referencias[i]);
                } else {
                    r.actualizados++;
                }
            } else {
                r.rejeitados++;
                r.rejeicoes.add(new SC_PniCsv.Rejeicao(
                    porChave.get(referencias[i]).numero, referencias[i],
                    motivo(gravados[i]), porChave.get(referencias[i]).bruto));
            }
        }
        return r;
    }

    // ------------------------------------------------------------------
    // Regras
    // ------------------------------------------------------------------

    /** Linhas alteradas antes da data de corte não entram. Sem data, também não. */
    private Boolean foraDaJanela(SC_PniLinha linha) {
        Date alterada = linha.dataAlteracao();
        if (alterada == null) {
            return true;
        }
        return corte != null && alterada < corte;
    }

    /**
     * O ficheiro traz um estado e a ordem tinha outro escrito pela ligação. Não impede
     * a escrita, porque o ficheiro ganha, mas fica contado para dar ocorrência.
     */
    private Boolean divergeDaLigacao(WorkOrder existente, SC_PniLinha linha) {
        return existente.Estado_Aceitacao_Cliente__c != null
            && linha.estado() != null
            && existente.Estado_Aceitacao_Cliente__c != linha.estado();
    }

    /**
     * Escreve na ordem só os campos que o ficheiro do PNI detém. Tudo o resto é da
     * ligação à NOS e fica como está.
     */
    private void aplicar(WorkOrder ordem, SC_PniLinha linha, Boolean nova) {
        ordem.Referencia_Ordem_Cliente__c = linha.chave();
        ordem.Estado_Aceitacao_Cliente__c = SC_PniCsv.ate(linha.estado(), 40);
        ordem.Data_Alteracao_PNI__c = linha.dataAlteracao();
        ordem.Assinatura_PNI__c = linha.assinatura();
        ordem.Origem_Registo__c = SC_PniConfig.ORIGEM_PNI;
        ordem.Ultimo_Lote__c = loteId;
        if (nova) {
            // Só na criação: uma ordem que já existe tem o Status na mão do Field
            // Service e o ficheiro não lho toca.
            ordem.Status = STATUS_NOVA;
            ordem.Subject = assunto(linha);
            Id conta = contaDoCliente();
            if (conta != null) {
                ordem.AccountId = conta;
            }
        }
    }

    private String assunto(SC_PniLinha linha) {
        String tipo = linha.tipoOrdem();
        String base = tipo == null ? 'Ordem do PNI' : tipo;
        return SC_PniCsv.ate(base + ' ' + linha.chave(), 255);
    }

    /** A mesma conta do cliente que a ligação à NOS usa: é o mesmo cliente. */
    private Id contaDoCliente() {
        if (!contaProcurada) {
            contaProcurada = true;
            String nif = SC_NosConfig.nifDaContaCliente();
            if (String.isNotBlank(nif)) {
                List<Account> contas = [
                    SELECT Id FROM Account WHERE NIF__c = :nif LIMIT 1
                ];
                if (!contas.isEmpty()) {
                    contaCliente = contas[0].Id;
                }
            }
        }
        return contaCliente;
    }

    private Map<String, WorkOrder> lerExistentes(Set<String> chaves) {
        Map<String, WorkOrder> porChave = new Map<String, WorkOrder>();
        for (WorkOrder o : [
            SELECT Id, Referencia_Ordem_Cliente__c, Assinatura_PNI__c,
                   Estado_Aceitacao_Cliente__c, Data_Alteracao_PNI__c,
                   Origem_Registo__c, Status
            FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c IN :chaves
        ]) {
            porChave.put(o.Referencia_Ordem_Cliente__c, o);
        }
        return porChave;
    }

    private String motivo(Database.UpsertResult resultado) {
        List<String> partes = new List<String>();
        for (Database.Error e : resultado.getErrors()) {
            partes.add(e.getStatusCode() + ': ' + e.getMessage());
        }
        return partes.isEmpty() ? 'Erro desconhecido ao gravar.'
                                : String.join(partes, ' | ');
    }
}