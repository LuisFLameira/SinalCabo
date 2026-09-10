/**
 * Onde o que veio da NOS vira Work Orders. É o ponto de entrada único.
 *
 * Todos os caminhos passam por aqui: o polling de cinco em cinco minutos, a corrida
 * manual, o reprocessamento de um lote guardado e a carga histórica de 30 dias. Nenhum
 * deles chama a API a partir desta classe: recebem o corpo já lido, o que faz do
 * reprocessamento e da carga a mesma coisa que uma corrida normal, sem tocar na NOS.
 *
 * Regras que esta classe garante:
 *  - a chave é a referência completa da NOS, e o upsert é por ela;
 *  - identificadores repetidos no mesmo corpo colapsam, e vence a última linha, que é
 *    a mais recente na ordem em que a API os manda;
 *  - assinatura igual à guardada não escreve nada, para uma leitura de rotina não
 *    marcar 1.300 ordens como alteradas todos os dias;
 *  - uma leitura mais velha do que a última que a ordem viu não escreve nada, para a
 *    carga histórica não regredir o estado que o polling já actualizou;
 *  - o Status e o estado de facturação da SinalCabo nunca são reescritos depois de a
 *    ordem nascer;
 *  - uma ordem que nasce fechada na NOS entra fechada e sem marcação, porque não há
 *    nada para o Field Service lhe fazer;
 *  - uma célula já preenchida ou confirmada nunca é reescrita;
 *  - uma linha que falha não leva as outras atrás (allOrNone a falso) e fica registada
 *    como Rejeição reprocessável.
 */
public with sharing class SC_NosUpsertService {
    /** Estado com que entra uma ordem que já nasce fechada na NOS. */
    public static final String STATUS_FECHADO = 'Closed';
    /** Estado inicial da marcação que a plataforma cria sozinha. */
    private static final String MARCACAO_POR_TOCAR = 'None';

    /** Contadores e ocorrências de uma passagem, para o lote fechar com números. */
    public class Resultado {
        public Integer lidos = 0;
        public Integer criados = 0;
        public Integer actualizados = 0;
        public Integer rejeitados = 0;
        public Integer inalterados = 0;
        /** Lidos mas descartados por a ordem já ter uma leitura mais recente. */
        public Integer ignorados = 0;
        /** Marcações vazias apagadas nas ordens que nasceram fechadas. */
        public Integer marcacoesApagadas = 0;
        public List<Ocorrencia_Integracao__c> ocorrencias = new List<Ocorrencia_Integracao__c>();
        /** Referências da NOS que este corpo trouxe, para o varrimento saber o que viu. */
        public Set<String> referencias = new Set<String>();
        /** Referências das ordens criadas agora: são as primeiras a pedir detalhe. */
        public Set<String> criadas = new Set<String>();

        public Boolean temOcorrencias() {
            return !ocorrencias.isEmpty();
        }

        public void juntar(Resultado outro) {
            this.lidos += outro.lidos;
            this.criados += outro.criados;
            this.actualizados += outro.actualizados;
            this.rejeitados += outro.rejeitados;
            this.inalterados += outro.inalterados;
            this.ignorados += outro.ignorados;
            this.marcacoesApagadas += outro.marcacoesApagadas;
            this.ocorrencias.addAll(outro.ocorrencias);
            this.referencias.addAll(outro.referencias);
            this.criadas.addAll(outro.criadas);
        }
    }

    // ------------------------------------------------------------------
    // Entradas públicas
    // ------------------------------------------------------------------

    public static Resultado processarListagem(String corpoJson, Id loteId) {
        return processarListagem(corpoJson, loteId, Datetime.now());
    }

    public static Resultado processarListagem(String corpoJson, Id loteId, Datetime dataLeitura) {
        return processar(SC_NosParser.listagem(corpoJson), loteId, dataLeitura);
    }

    public static Resultado processarDetalhe(String corpoJson, Id loteId) {
        return processarDetalhe(corpoJson, loteId, Datetime.now());
    }

    public static Resultado processarDetalhe(String corpoJson, Id loteId, Datetime dataLeitura) {
        return processarDetalhes(new List<String>{ corpoJson }, loteId, dataLeitura);
    }

    public static Resultado processarDetalhes(List<String> corposJson, Id loteId) {
        return processarDetalhes(corposJson, loteId, Datetime.now());
    }

    /** Vários detalhes de uma vez: a passagem de detalhes lê três por transacção. */
    public static Resultado processarDetalhes(List<String> corposJson, Id loteId, Datetime dataLeitura) {
        List<SC_NosTarefa> tarefas = new List<SC_NosTarefa>();
        for (String corpo : corposJson) {
            SC_NosTarefa tarefa = SC_NosParser.detalhe(corpo);
            if (tarefa != null) {
                tarefas.add(tarefa);
            }
        }
        return processar(tarefas, loteId, dataLeitura);
    }

    /** Marca como desaparecidas na origem as ordens cujo detalhe devolveu 701. */
    public static List<Ocorrencia_Integracao__c> marcarDesaparecidas(Set<String> referencias, Id loteId) {
        List<Ocorrencia_Integracao__c> ocorrencias = new List<Ocorrencia_Integracao__c>();
        if (referencias == null || referencias.isEmpty()) {
            return ocorrencias;
        }
        List<WorkOrder> ordens = [
            SELECT Id, Referencia_Ordem_Cliente__c
            FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c IN :referencias
        ];
        for (WorkOrder ordem : ordens) {
            ordem.Desaparecida_Origem__c = true;
            ordem.Data_Ultima_Leitura__c = Datetime.now();
            Ocorrencia_Integracao__c ocorrencia = SC_NosLote.ocorrencia(
                loteId, SC_NosLote.TIPO_AVISO, ordem.Referencia_Ordem_Cliente__c, 'WorkOrder',
                'A NOS já não conhece esta ordem (701).', null
            );
            ocorrencia.Ordem__c = ordem.Id;
            ocorrencias.add(ocorrencia);
        }
        if (!ordens.isEmpty()) {
            update ordens;
        }
        return ocorrencias;
    }

    // ------------------------------------------------------------------
    // Motor
    // ------------------------------------------------------------------

    public static Resultado processar(List<SC_NosTarefa> tarefas, Id loteId) {
        return processar(tarefas, loteId, Datetime.now());
    }

    /**
     * `dataLeitura` é o instante em que a NOS respondeu: `Datetime.now()` no polling ao
     * vivo, o carimbo do envelope guardado no reprocessamento e na carga histórica.
     */
    public static Resultado processar(List<SC_NosTarefa> tarefas, Id loteId, Datetime dataLeitura) {
        Resultado resultado = new Resultado();
        if (tarefas == null || tarefas.isEmpty()) {
            return resultado;
        }
        resultado.lidos = tarefas.size();
        Datetime lida = dataLeitura == null ? Datetime.now() : dataLeitura;

        // Identificadores repetidos no mesmo corpo: vence a última linha.
        Map<String, SC_NosTarefa> porReferencia = new Map<String, SC_NosTarefa>();
        for (SC_NosTarefa tarefa : tarefas) {
            if (String.isNotBlank(tarefa.id)) {
                porReferencia.put(tarefa.id, tarefa);
            }
        }
        resultado.referencias = porReferencia.keySet().clone();

        Map<String, WorkOrder> existentes = existentesPorReferencia(porReferencia.keySet());
        List<SC_NosTarefa> aTratar = porReferencia.values();

        SC_NosMapeador mapeador = new SC_NosMapeador(loteId, lida);
        mapeador.carregar(aTratar);
        SC_NosCelulaExtractor extractor = new SC_NosCelulaExtractor(loteId);
        extractor.carregar(aTratar);

        List<WorkOrder> paraGravar = new List<WorkOrder>();
        List<String> referenciasParaGravar = new List<String>();
        List<Boolean> ehNova = new List<Boolean>();

        for (SC_NosTarefa tarefa : aTratar) {
            WorkOrder existente = existentes.get(tarefa.id);
            Boolean nova = existente == null;

            // Leitura mais velha do que a última que esta ordem viu: não se escreve. É
            // o que impede a carga dos 30 dias de regredir o que o polling já actualizou.
            if (!nova && existente.Data_Ultima_Leitura__c != null
                && existente.Data_Ultima_Leitura__c > lida) {
                resultado.ignorados++;
                continue;
            }

            // Cabeçalho igual ao que já está guardado: não se escreve. O detalhe escreve
            // sempre, porque traz notas e interacções que a assinatura não cobre.
            if (!nova && !tarefa.veioDoDetalhe && tarefa.assinatura() == existente.Assinatura_Origem__c) {
                resultado.inalterados++;
                continue;
            }

            Boolean confirmada = !nova && existente.Classificacao_Confirmada__c == true;
            Boolean jaTemCelula = !nova && existente.Celula__c != null;
            Id territorioDoGrupo = mapeador.territorioDoGrupo(tarefa.grupo);
            // A célula que já lá está manda no território: é a zona, mais precisa do que o
            // território do grupo, que é só o pai dessa zona.
            Boolean territorioJaEDaCelula = jaTemCelula && existente.ServiceTerritoryId != null;

            WorkOrder ordem = new WorkOrder();
            mapeador.aplicar(ordem, tarefa, nova, confirmada, territorioJaEDaCelula);
            extractor.aplicar(ordem, tarefa, territorioDoGrupo, jaTemCelula, confirmada);

            // Ordem com célula do dia anterior e ainda por classificar: a divergência
            // recalcula-se, porque a NOS pode ter mudado o grupo desde a última leitura.
            if (jaTemCelula && !confirmada) {
                ordem.Divergencia_Territorio__c = SC_NosCelulaExtractor.divergente(
                    existente.Celula__r.Territorio__c,
                    existente.Celula__r.Territorio__c == null
                        ? null
                        : existente.Celula__r.Territorio__r.ParentTerritoryId,
                    territorioDoGrupo
                );
            }

            if (!nova && existente.Estado_Cliente__c != tarefa.estado) {
                resultado.ocorrencias.add(SC_NosLote.ocorrencia(
                    loteId, SC_NosLote.TIPO_ALTERACAO, tarefa.id, 'WorkOrder.Estado_Cliente__c',
                    'Estado na NOS: ' + existente.Estado_Cliente__c + ' passou a ' + tarefa.estado,
                    null
                ));
            }

            paraGravar.add(ordem);
            referenciasParaGravar.add(tarefa.id);
            ehNova.add(nova);
        }

        resultado.ocorrencias.addAll(mapeador.ocorrencias());
        resultado.ocorrencias.addAll(extractor.ocorrencias());

        if (paraGravar.isEmpty()) {
            return resultado;
        }

        Map<String, Id> idsPorReferencia = new Map<String, Id>();
        for (String referencia : existentes.keySet()) {
            idsPorReferencia.put(referencia, existentes.get(referencia).Id);
        }

        List<Database.UpsertResult> gravados = Database.upsert(
            paraGravar, WorkOrder.Referencia_Ordem_Cliente__c, false
        );
        Map<Integer, Id> recuperadas = recuperarNascidasFechadas(
            gravados, paraGravar, ehNova, loteId, resultado
        );

        Set<Id> fechadasCriadas = new Set<Id>();
        for (Integer i = 0; i < gravados.size(); i++) {
            String referencia = referenciasParaGravar.get(i);
            Id gravadoId = gravados.get(i).isSuccess() ? gravados.get(i).getId() : recuperadas.get(i);
            if (gravadoId != null) {
                idsPorReferencia.put(referencia, gravadoId);
                if (ehNova.get(i)) {
                    resultado.criados++;
                    resultado.criadas.add(referencia);
                    if (STATUS_FECHADO.equals(paraGravar.get(i).Status)) {
                        fechadasCriadas.add(gravadoId);
                    }
                } else {
                    resultado.actualizados++;
                }
            } else {
                resultado.rejeitados++;
                resultado.ocorrencias.add(SC_NosLote.ocorrencia(
                    loteId, SC_NosLote.TIPO_REJEICAO, referencia, 'WorkOrder',
                    mensagemDeErro(gravados.get(i)), JSON.serialize(paraGravar.get(i))
                ));
            }
        }

        resultado.marcacoesApagadas = apagarMarcacoesPorTocar(fechadasCriadas);

        // Só agora existe Id para as ordens criadas nesta passagem.
        for (Ocorrencia_Integracao__c ocorrencia : resultado.ocorrencias) {
            if (ocorrencia.Ordem__c == null && ocorrencia.Chave_Origem__c != null) {
                ocorrencia.Ordem__c = idsPorReferencia.get(ocorrencia.Chave_Origem__c);
            }
        }
        return resultado;
    }

    // ------------------------------------------------------------------
    // Ordens que nascem fechadas
    // ------------------------------------------------------------------

    /**
     * Segunda tentativa das ordens que nascem fechadas e que o upsert recusou: entram
     * New e fecham-se na mesma transacção. O caminho é auto-diagnóstico, porque só
     * resulta quando a recusa foi mesmo do estado inicial; qualquer outra causa falha
     * outra vez e a rejeição original mantém-se de pé.
     *
     * Na fsbuild o pacote FSL aceita inserir uma ordem já Closed (verificado a
     * 10/09/2026), por isso este caminho existe para as orgs onde isso não seja verdade.
     *
     * Devolve o índice de cada linha recuperada e o Id que lhe ficou.
     */
    @TestVisible
    private static Map<Integer, Id> recuperarNascidasFechadas(
        List<Database.UpsertResult> gravados,
        List<WorkOrder> paraGravar,
        List<Boolean> ehNova,
        Id loteId,
        Resultado resultado
    ) {
        Map<Integer, Id> recuperadas = new Map<Integer, Id>();
        List<WorkOrder> segundaTentativa = new List<WorkOrder>();
        List<Integer> indices = new List<Integer>();
        for (Integer i = 0; i < gravados.size(); i++) {
            if (gravados.get(i).isSuccess() || !ehNova.get(i)
                || !STATUS_FECHADO.equals(paraGravar.get(i).Status)) {
                continue;
            }
            WorkOrder copia = paraGravar.get(i).clone(false, true, false, false);
            copia.Status = 'New';
            segundaTentativa.add(copia);
            indices.add(i);
        }
        if (segundaTentativa.isEmpty()) {
            return recuperadas;
        }

        List<Database.SaveResult> inseridas = Database.insert(segundaTentativa, false);
        List<WorkOrder> aFechar = new List<WorkOrder>();
        for (Integer j = 0; j < inseridas.size(); j++) {
            if (!inseridas.get(j).isSuccess()) {
                continue;
            }
            recuperadas.put(indices.get(j), inseridas.get(j).getId());
            aFechar.add(new WorkOrder(Id = inseridas.get(j).getId(), Status = STATUS_FECHADO));
            resultado.ocorrencias.add(SC_NosLote.ocorrencia(
                loteId, SC_NosLote.TIPO_AVISO, segundaTentativa.get(j).Referencia_Ordem_Cliente__c,
                'WorkOrder.Status',
                'A ordem nasceu fechada em dois passos: a org recusou inseri-la já fechada.',
                null
            ));
        }
        if (!aFechar.isEmpty()) {
            Database.update(aFechar, false);
        }
        return recuperadas;
    }

    /**
     * A plataforma cria a marcação sozinha quando o Work Type o manda. Numa ordem que
     * nasce fechada não há nada para agendar, e uma marcação vazia só entra no Gantt e
     * nas filas do despacho a fingir trabalho. Apaga-se só a que ninguém tocou: sem
     * hora agendada e ainda no estado inicial.
     */
    private static Integer apagarMarcacoesPorTocar(Set<Id> ordens) {
        if (ordens.isEmpty()) {
            return 0;
        }
        List<ServiceAppointment> marcacoes = [
            SELECT Id
            FROM ServiceAppointment
            WHERE ParentRecordId IN :ordens
              AND SchedStartTime = NULL
              AND Status = :MARCACAO_POR_TOCAR
        ];
        if (marcacoes.isEmpty()) {
            return 0;
        }
        Integer apagadas = 0;
        for (Database.DeleteResult resultado : Database.delete(marcacoes, false)) {
            if (resultado.isSuccess()) {
                apagadas++;
            }
        }
        return apagadas;
    }

    // ------------------------------------------------------------------
    // Apoio
    // ------------------------------------------------------------------

    private static Map<String, WorkOrder> existentesPorReferencia(Set<String> referencias) {
        Map<String, WorkOrder> porReferencia = new Map<String, WorkOrder>();
        for (WorkOrder ordem : [
            SELECT Id, Referencia_Ordem_Cliente__c, Assinatura_Origem__c, Estado_Cliente__c,
                   Celula__c, Classificacao_Confirmada__c, Status, Data_Ultima_Leitura__c,
                   ServiceTerritoryId, Celula__r.Territorio__c, Celula__r.Territorio__r.ParentTerritoryId
            FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c IN :referencias
        ]) {
            porReferencia.put(ordem.Referencia_Ordem_Cliente__c, ordem);
        }
        return porReferencia;
    }

    private static String mensagemDeErro(Database.UpsertResult resultado) {
        List<String> partes = new List<String>();
        for (Database.Error erro : resultado.getErrors()) {
            partes.add(erro.getStatusCode() + ': ' + erro.getMessage());
        }
        return String.join(partes, ' | ');
    }
}