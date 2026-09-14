/**
 * A fronteira de confiança entre o ecrã de carregamento e a importação do PNI.
 *
 * Ao contrário da entrada da NOS, que é um job sem ninguém à frente, aqui há uma
 * pessoa a carregar um ficheiro. Por isso todos os métodos começam por verificar a
 * permissão própria: sem ela recusam, mesmo a quem tenha acesso à aplicação.
 *
 * O ficheiro nunca chega inteiro. O ecrã corta-o e manda um pedaço de cada vez, e
 * cada chamada é uma transacção sua. Os contadores vivem no lote, que é o que a
 * pessoa vê a crescer enquanto espera, e é também o que fica para auditoria.
 */
public with sharing class SC_PniCarregamentoController {

    /** O que uma chamada devolve ao ecrã. */
    public class Passagem {
        @AuraEnabled public Id loteId;
        @AuraEnabled public List<String> colunas;
        @AuraEnabled public String cauda;
        @AuraEnabled public String erro;
        @AuraEnabled public Integer lidos = 0;
        @AuraEnabled public Integer criados = 0;
        @AuraEnabled public Integer actualizados = 0;
        @AuraEnabled public Integer inalterados = 0;
        @AuraEnabled public Integer rejeitados = 0;
        @AuraEnabled public Integer forasDeJanela = 0;
        @AuraEnabled public Integer divergentes = 0;
    }

    // ------------------------------------------------------------------
    // Abrir
    // ------------------------------------------------------------------

    /**
     * Abre o lote de uma importação. Devolve o identificador que o ecrã usa em todas
     * as chamadas seguintes.
     */
    @AuraEnabled
    public static Passagem iniciar(String nomeFicheiro, Boolean simulacao) {
        exigirPermissao();
        if (!SC_PniConfig.activo()) {
            throw erro('A importação do ficheiro do PNI está desligada. '
                + 'Fale com o administrador antes de voltar a tentar.');
        }
        Lote_Integracao__c lote = new Lote_Integracao__c(
            Interface__c = SC_PniConfig.INTERFACE_ENTRADA,
            Direccao__c = 'Entrada',
            Tipo_Corrida__c = simulacao == true
                ? SC_PniConfig.CORRIDA_SIMULACAO : SC_PniConfig.CORRIDA_FICHEIRO,
            Janela_Inicio__c = Datetime.now(),
            Estado__c = SC_NosLote.ESTADO_EM_CURSO,
            Chave_Execucao__c = chaveDe(nomeFicheiro, simulacao),
            Registos_Lidos__c = 0,
            Criados__c = 0,
            Actualizados__c = 0,
            Rejeitados__c = 0
        );
        insert lote;

        Passagem p = new Passagem();
        p.loteId = lote.Id;
        return p;
    }

    // ------------------------------------------------------------------
    // Processar um pedaço
    // ------------------------------------------------------------------

    /**
     * Lê um pedaço e escreve o que dele sair. As colunas vêm nulas no primeiro pedaço,
     * que traz o cabeçalho, e a seguir voltam sempre as mesmas, porque o cabeçalho só
     * aparece uma vez no ficheiro.
     *
     * Devolve a cauda, que é o que ficou depois do último registo completo. O ecrã põe
     * essa cauda à frente do pedaço seguinte.
     */
    @AuraEnabled
    public static Passagem processar(Id loteId, String pedaco, List<String> colunas,
                                     Integer numeroInicial, Boolean ultimo,
                                     Boolean simulacao) {
        exigirPermissao();
        Passagem p = new Passagem();
        p.loteId = loteId;

        SC_PniCsv.Resultado leitura = SC_PniCsv.ler(
            pedaco, colunas, numeroInicial == null ? 1 : numeroInicial, ultimo == true);
        p.colunas = leitura.colunas;
        p.cauda = leitura.cauda;
        if (colunas == null || colunas.isEmpty()) {
            // O cabecalho so vem no primeiro pedaco. Fica guardado no lote porque
            // sem ele nao ha como reler uma linha rejeitada mais tarde.
            guardarCabecalho(loteId, leitura.colunas);
        }
        if (!leitura.valido()) {
            p.erro = leitura.erroCabecalho;
            falhar(loteId, leitura.erroCabecalho);
            return p;
        }

        SC_PniUpsertService servico = new SC_PniUpsertService(loteId, simulacao == true);
        SC_PniUpsertService.Resultado r = servico.tratar(leitura.linhas);

        p.lidos = leitura.lidas;
        p.criados = r.criados;
        p.actualizados = r.actualizados;
        p.inalterados = r.inalterados;
        p.rejeitados = r.rejeitados + leitura.rejeicoes.size();
        p.forasDeJanela = r.forasDeJanela;
        p.divergentes = r.divergentes;

        registarOcorrencias(loteId, leitura.rejeicoes, r.rejeicoes, simulacao == true);
        somarNoLote(loteId, p);
        return p;
    }

    // ------------------------------------------------------------------
    // Fechar
    // ------------------------------------------------------------------

    /** Fecha o lote. Com rejeições fica concluído com erros, que é o que se quer ver. */
    @AuraEnabled
    public static Passagem concluir(Id loteId) {
        exigirPermissao();
        Lote_Integracao__c lote = [
            SELECT Id, Registos_Lidos__c, Criados__c, Actualizados__c, Rejeitados__c,
                   Janela_Inicio__c, Estado__c
            FROM Lote_Integracao__c WHERE Id = :loteId LIMIT 1
        ];
        if (lote.Estado__c != SC_NosLote.ESTADO_FALHADO) {
            lote.Estado__c = lote.Rejeitados__c > 0
                ? SC_NosLote.ESTADO_CONCLUIDO_COM_ERROS : SC_NosLote.ESTADO_CONCLUIDO;
            lote.Resultado__c = lote.Registos_Lidos__c > 0 ? 'Sucesso' : 'Vazio';
        }
        lote.Janela_Fim__c = Datetime.now();
        if (lote.Janela_Inicio__c != null) {
            lote.Duracao_ms__c = lote.Janela_Fim__c.getTime()
                                 - lote.Janela_Inicio__c.getTime();
        }
        update lote;

        Passagem p = new Passagem();
        p.loteId = lote.Id;
        p.lidos = inteiro(lote.Registos_Lidos__c);
        p.criados = inteiro(lote.Criados__c);
        p.actualizados = inteiro(lote.Actualizados__c);
        p.rejeitados = inteiro(lote.Rejeitados__c);
        return p;
    }

    /** O ecrã pergunta por isto de cinco em cinco segundos enquanto espera. */
    @AuraEnabled(cacheable=false)
    public static Lote_Integracao__c lote(Id loteId) {
        exigirPermissao();
        return [
            SELECT Id, Name, Estado__c, Registos_Lidos__c, Criados__c, Actualizados__c,
                   Rejeitados__c, Duracao_ms__c, Erro__c, Tipo_Corrida__c
            FROM Lote_Integracao__c WHERE Id = :loteId LIMIT 1
        ];
    }

    // ------------------------------------------------------------------
    // Apoio
    // ------------------------------------------------------------------

    private static void exigirPermissao() {
        if (!SC_PniConfig.podeImportar()) {
            throw erro('Não tem permissão para importar o ficheiro do PNI. '
                + 'Peça ao administrador a permissão de importação.');
        }
    }

    private static AuraHandledException erro(String mensagem) {
        AuraHandledException e = new AuraHandledException(mensagem);
        e.setMessage(mensagem);
        return e;
    }

    private static String chaveDe(String nomeFicheiro, Boolean simulacao) {
        String nome = String.isBlank(nomeFicheiro) ? 'ficheiro' : nomeFicheiro;
        return ('PNI|' + (simulacao == true ? 'ensaio' : 'real') + '|' + nome + '|'
                + String.valueOf(System.currentTimeMillis())).abbreviate(255);
    }

    private static void registarOcorrencias(Id loteId,
            List<SC_PniCsv.Rejeicao> deLeitura, List<SC_PniCsv.Rejeicao> deEscrita,
            Boolean simulacao) {
        List<Ocorrencia_Integracao__c> todas = new List<Ocorrencia_Integracao__c>();
        for (SC_PniCsv.Rejeicao r : deLeitura) {
            todas.add(SC_NosLote.ocorrencia(loteId, SC_NosLote.TIPO_REJEICAO,
                r.chave, 'WorkOrder',
                'Linha ' + r.numero + ': ' + r.motivo, r.bruto));
        }
        for (SC_PniCsv.Rejeicao r : deEscrita) {
            todas.add(SC_NosLote.ocorrencia(loteId, SC_NosLote.TIPO_REJEICAO,
                r.chave, 'WorkOrder',
                'Linha ' + r.numero + ': ' + r.motivo, r.bruto));
        }
        if (!todas.isEmpty()) {
            SC_NosLote.guardar(todas);
        }
    }

    /** O cabecalho do ficheiro, guardado para o reprocessamento o poder reutilizar. */
    private static void guardarCabecalho(Id loteId, List<String> colunas) {
        if (loteId == null || colunas == null || colunas.isEmpty()) {
            return;
        }
        update new Lote_Integracao__c(
            Id = loteId,
            Payload__c = String.join(colunas, SC_PniCsv.SEPARADOR)
        );
    }

    private static void somarNoLote(Id loteId, Passagem p) {
        Lote_Integracao__c lote = [
            SELECT Id, Registos_Lidos__c, Criados__c, Actualizados__c, Rejeitados__c
            FROM Lote_Integracao__c WHERE Id = :loteId LIMIT 1
        ];
        lote.Registos_Lidos__c = inteiro(lote.Registos_Lidos__c) + p.lidos;
        lote.Criados__c = inteiro(lote.Criados__c) + p.criados;
        lote.Actualizados__c = inteiro(lote.Actualizados__c) + p.actualizados;
        lote.Rejeitados__c = inteiro(lote.Rejeitados__c) + p.rejeitados;
        update lote;
    }

    private static void falhar(Id loteId, String mensagem) {
        if (loteId == null) {
            return;
        }
        update new Lote_Integracao__c(
            Id = loteId,
            Estado__c = SC_NosLote.ESTADO_FALHADO,
            Resultado__c = 'Erro',
            Erro__c = mensagem == null ? null : mensagem.abbreviate(255),
            Janela_Fim__c = Datetime.now()
        );
    }

    private static Integer inteiro(Decimal d) {
        return d == null ? 0 : Integer.valueOf(d);
    }
}