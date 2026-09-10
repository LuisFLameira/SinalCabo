/**
 * A corrida de leitura da NOS, um passo por transacção.
 *
 * A cadeia normal é ABERTAS, FECHADAS, VARRIMENTO (só à hora) e DETALHES. Cada passo
 * corre numa transacção sua, faz primeiro os callouts e só depois escreve, porque uma
 * transacção com DML por confirmar não pode chamar para fora. O lote de cada passo é
 * aberto pela transacção anterior, pela mesma razão.
 *
 * Erros e o que provocam:
 *  - corte do gateway (504): a janela parte-se ao meio e as duas metades entram na
 *    fila; abaixo de seis horas o lote falha de vez. Dois cortes seguidos suspendem;
 *  - endpoint suspenso na NOS (303001): suspende já, sem repetir;
 *  - janela recusada (702): ocorrência de Rejeição e a janela parte-se ao meio, que é
 *    o caminho para uma janela de fechadas acima das 72 horas passar a caber;
 *  - detalhe que não existe (701): a ordem fica marcada como desaparecida na origem.
 *
 * A suspensão começa em 15 minutos e dobra a cada suspensão seguida até duas horas.
 * Uma resposta boa apaga os contadores.
 *
 * Campos novos nesta classe começam sempre por passar por normalizar(): um passo pode
 * ter sido enfileirado por uma versão anterior e chega sem eles.
 */
public with sharing class SC_NosPollingQueueable implements Queueable, Database.AllowsCallouts {
    /** Tecto de janelas partidas numa cadeia, para um 504 em cadeia não a fazer crescer. */
    private static final Integer MAXIMO_DE_JANELAS = 20;
    /** Tecto de rondas de detalhes por ciclo, para o ciclo caber nos cinco minutos. */
    private static final Integer MAXIMO_DE_RONDAS = 3;

    public String passo;
    public Id loteId;
    public Datetime inicio;
    public Datetime fim;
    /** Janelas por fazer neste passo, cada uma como 'millisInicio|millisFim'. */
    public List<String> janelasPendentes = new List<String>();
    public Integer janelasFeitas = 0;
    /** Referências que ainda esperam leitura de detalhe nesta cadeia. */
    public List<String> detalhesPendentes = new List<String>();
    public Integer ronda = 0;
    /** Uma corrida manual não continua para os passos seguintes. */
    public Boolean encadear = true;
    /**
     * Se esta cadeia inclui o varrimento. Decide-se uma vez, quando o agendador arranca,
     * e viaja com a cadeia: assim um ciclo que atravesse o minuto cinco não muda de ideias
     * a meio, e o ramo deixa de depender do relógio para ser testado.
     */
    public Boolean varrer = false;

    public SC_NosPollingQueueable(String passo, Id loteId, Datetime inicio, Datetime fim) {
        this.passo = passo;
        this.loteId = loteId;
        this.inicio = inicio;
        this.fim = fim;
    }

    // ------------------------------------------------------------------
    // Execução
    // ------------------------------------------------------------------

    public void execute(QueueableContext contexto) {
        System.attachFinalizer(new Vigilante(this.loteId));
        normalizar();
        if (this.loteId == null) {
            return;
        }
        String motivo = SC_NosConfig.motivoParaNaoCorrer();
        if (motivo != null) {
            SC_NosLote.falharPorId(this.loteId, motivo);
            return;
        }
        if (SC_NosConfig.CORRIDA_DETALHES.equals(this.passo)) {
            passoDeDetalhes();
        } else {
            passoDeListagem();
        }
    }

    /**
     * Um passo enfileirado por uma versão da classe pode ser executado por outra: quem
     * deploya a meio de um ciclo desserializa um passo sem os campos novos, e esses
     * chegam a nulo em vez do valor de arranque. Aconteceu na fsbuild a 10/09/2026, com
     * o passo de fechadas a morrer num NullPointerException no campo do varrimento.
     */
    private void normalizar() {
        if (this.encadear == null) {
            this.encadear = true;
        }
        if (this.varrer == null) {
            this.varrer = false;
        }
        if (this.ronda == null) {
            this.ronda = 0;
        }
        if (this.janelasFeitas == null) {
            this.janelasFeitas = 0;
        }
        if (this.janelasPendentes == null) {
            this.janelasPendentes = new List<String>();
        }
        if (this.detalhesPendentes == null) {
            this.detalhesPendentes = new List<String>();
        }
    }

    // ------------------------------------------------------------------
    // Listagem
    // ------------------------------------------------------------------

    private void passoDeListagem() {
        String status = SC_NosConfig.CORRIDA_FECHADAS.equals(this.passo) ? 'CLOSED' : null;
        SC_NosResponse resposta = SC_NosClient.listar(this.inicio, this.fim, status);

        Lote_Integracao__c lote = lote();
        if (resposta.corteDeGateway() || resposta.suspensoNaOrigem()) {
            tratarFalhaDeRede(lote, resposta);
            return;
        }
        if (resposta.situacao == SC_NosResponse.Classe.JANELA) {
            tratarJanelaRecusada(lote, resposta);
            return;
        }
        if (!resposta.ok()) {
            SC_NosLote.falhar(lote, resposta, resposta.resumo());
            seguir();
            return;
        }

        SC_NosConfig.limparCortes();
        SC_NosConfig.gravarEstado();

        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarListagem(resposta.corpo, this.loteId);
        SC_NosLote.guardar(r.ocorrencias);
        SC_NosLote.concluir(lote, resposta, resposta.duracaoMs, r, proximaChegada());
        this.detalhesPendentes.addAll(new List<String>(r.criadas));
        seguir();
    }

    // ------------------------------------------------------------------
    // Detalhes
    // ------------------------------------------------------------------

    private void passoDeDetalhes() {
        List<String> referencias = referenciasParaDetalhe();
        if (referencias.isEmpty()) {
            SC_NosLote.concluir(lote(), null, 0, new SC_NosUpsertService.Resultado(), proximaChegada());
            return;
        }

        // Todos os callouts antes de qualquer escrita.
        List<String> corpos = new List<String>();
        Set<String> ausentes = new Set<String>();
        SC_NosResponse cortada;
        SC_NosResponse representativa;
        Long duracao = 0;
        for (String referencia : referencias) {
            SC_NosResponse resposta = SC_NosClient.detalhe(referencia);
            duracao += resposta.duracaoMs == null ? 0 : resposta.duracaoMs;
            if (resposta.corteDeGateway() || resposta.suspensoNaOrigem()) {
                cortada = resposta;
                break;
            }
            if (representativa == null || (!representativa.ok() && resposta.ok())) {
                representativa = resposta;
            }
            if (resposta.situacao == SC_NosResponse.Classe.AUSENTE) {
                ausentes.add(referencia);
            } else if (resposta.ok()) {
                corpos.add(resposta.corpo);
            }
        }

        Lote_Integracao__c lote = lote();
        if (cortada != null) {
            tratarFalhaDeRede(lote, cortada);
            return;
        }

        SC_NosConfig.limparCortes();
        SC_NosConfig.gravarEstado();

        SC_NosUpsertService.Resultado r = SC_NosUpsertService.processarDetalhes(corpos, this.loteId);
        // Um detalhe que a NOS já não conhece é aviso e não rejeição: nada falhou a gravar.
        r.ocorrencias.addAll(SC_NosUpsertService.marcarDesaparecidas(ausentes, this.loteId));
        r.lidos = referencias.size();
        SC_NosLote.guardar(r.ocorrencias);
        SC_NosLote.concluir(lote, representativa, duracao, r, proximaChegada());
        seguir();
    }

    /** Primeiro as ordens que nasceram nesta cadeia, depois a mais antiga por ler. */
    @TestVisible
    private List<String> referenciasParaDetalhe() {
        Integer quantidade = SC_NosConfig.detalhesPorTransaccao();
        List<String> escolhidas = new List<String>();
        while (!this.detalhesPendentes.isEmpty() && escolhidas.size() < quantidade) {
            escolhidas.add(this.detalhesPendentes.remove(0));
        }
        if (escolhidas.size() >= quantidade) {
            return escolhidas;
        }
        Integer emFalta = quantidade - escolhidas.size();
        Set<String> jaEscolhidas = new Set<String>(escolhidas);
        for (WorkOrder ordem : [
            SELECT Referencia_Ordem_Cliente__c
            FROM WorkOrder
            WHERE Referencia_Ordem_Cliente__c != NULL
              AND IsClosed = FALSE
              AND Desaparecida_Origem__c = FALSE
              AND Referencia_Ordem_Cliente__c NOT IN :jaEscolhidas
            ORDER BY Data_Ultima_Leitura__c ASC NULLS FIRST
            LIMIT :emFalta
        ]) {
            escolhidas.add(ordem.Referencia_Ordem_Cliente__c);
        }
        return escolhidas;
    }

    // ------------------------------------------------------------------
    // Erros
    // ------------------------------------------------------------------

    private void tratarFalhaDeRede(Lote_Integracao__c lote, SC_NosResponse resposta) {
        Boolean suspender = resposta.suspensoNaOrigem() || SC_NosConfig.registarCorte504();
        if (suspender) {
            Integer minutos = SC_NosConfig.suspender();
            SC_NosConfig.gravarEstado();
            SC_NosLote.falhar(lote, resposta,
                resposta.resumo() + ' Integração suspensa por ' + minutos + ' minutos.');
            return;
        }
        SC_NosConfig.gravarEstado();

        Integer horas = horasDaJanela();
        if (SC_NosConfig.CORRIDA_DETALHES.equals(this.passo) || horas <= SC_NosConfig.JANELA_MINIMA_HORAS) {
            SC_NosLote.falhar(lote, resposta,
                resposta.resumo() + ' A janela já não se pode partir mais.');
            return;
        }
        partirJanela();
        SC_NosLote.falhar(lote, resposta,
            resposta.resumo() + ' A janela de ' + horas + ' h foi partida ao meio.');
        seguir();
    }

    private void tratarJanelaRecusada(Lote_Integracao__c lote, SC_NosResponse resposta) {
        List<Ocorrencia_Integracao__c> ocorrencias = new List<Ocorrencia_Integracao__c>{
            SC_NosLote.ocorrencia(
                this.loteId, SC_NosLote.TIPO_REJEICAO, null, 'Lote_Integracao__c',
                'A NOS recusou a janela: ' + resposta.mensagem, resposta.corpo
            )
        };
        Integer horas = horasDaJanela();
        if (horas > 1) {
            partirJanela();
        }
        SC_NosLote.guardar(ocorrencias);
        SC_NosUpsertService.Resultado r = new SC_NosUpsertService.Resultado();
        r.rejeitados = 1;
        r.ocorrencias = ocorrencias;
        SC_NosLote.concluir(lote, resposta, resposta.duracaoMs, r, proximaChegada());
        seguir();
    }

    private Integer horasDaJanela() {
        if (this.inicio == null || this.fim == null) {
            return 0;
        }
        return (Integer) ((this.fim.getTime() - this.inicio.getTime()) / (1000 * 60 * 60));
    }

    private void partirJanela() {
        Datetime meio = Datetime.newInstance((this.inicio.getTime() + this.fim.getTime()) / 2);
        List<String> novas = new List<String>{
            janela(this.inicio, meio),
            janela(meio, this.fim)
        };
        novas.addAll(this.janelasPendentes);
        this.janelasPendentes = novas;
    }

    // ------------------------------------------------------------------
    // Cadeia
    // ------------------------------------------------------------------

    /** A cadeia agendada volta de cinco em cinco minutos; a manual não volta. */
    private Datetime proximaChegada() {
        return this.encadear ? Datetime.now().addMinutes(5) : null;
    }

    private Lote_Integracao__c lote() {
        return new Lote_Integracao__c(Id = this.loteId);
    }

    /** Descritor do passo seguinte, ou null quando a cadeia termina. */
    @TestVisible
    private SC_NosPollingQueueable proximo() {
        if (!this.janelasPendentes.isEmpty() && this.janelasFeitas < MAXIMO_DE_JANELAS) {
            List<String> restantes = this.janelasPendentes.clone();
            String proxima = restantes.remove(0);
            SC_NosPollingQueueable seguinte = comJanela(this.passo, proxima);
            seguinte.janelasPendentes = restantes;
            seguinte.janelasFeitas = this.janelasFeitas + 1;
            return seguinte;
        }
        if (!this.encadear) {
            return null;
        }
        Datetime agora = Datetime.now();
        if (SC_NosConfig.CORRIDA_ABERTAS.equals(this.passo)) {
            return novo(SC_NosConfig.CORRIDA_FECHADAS,
                agora.addHours(-SC_NosConfig.janelaFechadasHoras()), agora);
        }
        if (SC_NosConfig.CORRIDA_FECHADAS.equals(this.passo)) {
            return this.varrer ? varrimento(agora) : detalhes();
        }
        if (SC_NosConfig.CORRIDA_VARRIMENTO.equals(this.passo)) {
            return detalhes();
        }
        if (SC_NosConfig.CORRIDA_DETALHES.equals(this.passo)
            && !this.detalhesPendentes.isEmpty()
            && this.ronda + 1 < MAXIMO_DE_RONDAS) {
            SC_NosPollingQueueable seguinte = detalhes();
            seguinte.ronda = this.ronda + 1;
            return seguinte;
        }
        return null;
    }

    private void seguir() {
        SC_NosPollingQueueable seguinte = proximo();
        if (seguinte == null || !podeEncadear()) {
            return;
        }
        // A passagem de detalhes não tem janela: duas rondas no mesmo minuto dariam a
        // mesma chave e a segunda morria como duplicado. Quem impede duas cadeias ao
        // mesmo tempo é o lote Em curso que o agendador vê, não a chave dos detalhes.
        Lote_Integracao__c lote = SC_NosConfig.CORRIDA_DETALHES.equals(seguinte.passo)
            ? SC_NosLote.abrirRepetivel(seguinte.passo, seguinte.inicio, seguinte.fim)
            : SC_NosLote.abrir(seguinte.passo, seguinte.inicio, seguinte.fim);
        if (lote == null) {
            return;
        }
        seguinte.loteId = lote.Id;
        System.enqueueJob(seguinte);
    }

    /**
     * Nos testes não se encadeia: a plataforma só deixa enfileirar um job e o segundo
     * rebentaria com limite de profundidade. O passo seguinte assere-se por proximo().
     */
    private Boolean podeEncadear() {
        return !Test.isRunningTest() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    }

    /**
     * Uma janela de sete dias por hora, a rodar pelas sete janelas dos 45 dias. O plano
     * previa as sete de seguida; passam a uma por hora porque o limite de chamadas da
     * NOS ainda não está confirmado e sete janelas seguidas gastavam-no quase todo. Em
     * sete horas o alcance fica coberto na mesma, e as manutenções vivem 43 dias.
     */
    private SC_NosPollingQueueable varrimento(Datetime agora) {
        SC_NosConfig.estado().Ultimo_Varrimento__c = agora;
        SC_NosConfig.gravarEstado();
        Datetime fimJanela = fimDaJanelaDeVarrimento(agora);
        return novo(
            SC_NosConfig.CORRIDA_VARRIMENTO,
            fimJanela.addDays(-SC_NosConfig.passoVarrimentoDias()),
            fimJanela
        );
    }

    /** Onde acaba a janela desta hora, a rodar pelas janelas que cobrem o alcance. */
    @TestVisible
    private static Datetime fimDaJanelaDeVarrimento(Datetime agora) {
        Integer passoDias = SC_NosConfig.passoVarrimentoDias();
        Integer janelas = Math.max(1, SC_NosConfig.alcanceVarrimentoDias() / passoDias);
        // Hora GMT e não local: a rotação não pode saltar uma janela na mudança da hora.
        return agora.addDays(-Math.mod(agora.hourGmt(), janelas) * passoDias);
    }

    private SC_NosPollingQueueable detalhes() {
        Datetime agora = Datetime.now();
        SC_NosPollingQueueable seguinte = novo(SC_NosConfig.CORRIDA_DETALHES, agora, agora);
        seguinte.detalhesPendentes = this.detalhesPendentes.clone();
        return seguinte;
    }

    private SC_NosPollingQueueable novo(String proximoPasso, Datetime inicioJanela, Datetime fimJanela) {
        SC_NosPollingQueueable seguinte = new SC_NosPollingQueueable(proximoPasso, null, inicioJanela, fimJanela);
        seguinte.detalhesPendentes = this.detalhesPendentes.clone();
        seguinte.encadear = this.encadear;
        seguinte.varrer = this.varrer;
        return seguinte;
    }

    private SC_NosPollingQueueable comJanela(String mesmoPasso, String codificada) {
        List<String> partes = codificada.split('\\|');
        return novo(mesmoPasso,
            Datetime.newInstance(Long.valueOf(partes[0])),
            Datetime.newInstance(Long.valueOf(partes[1])));
    }

    private static String janela(Datetime inicioJanela, Datetime fimJanela) {
        return String.valueOf(inicioJanela.getTime()) + '|' + String.valueOf(fimJanela.getTime());
    }

    /** O varrimento entra na corrida do minuto zero e mais nenhuma. */
    public static Boolean horaDeVarrimento() {
        return Datetime.now().minute() < 5;
    }

    // ------------------------------------------------------------------
    // Vigilante
    // ------------------------------------------------------------------

    /**
     * Corre sempre depois do passo, mesmo quando a transacção morre. É o único sítio
     * que fecha um lote que ficaria Em curso para todo o sempre.
     */
    public class Vigilante implements Finalizer {
        private final Id loteId;

        public Vigilante(Id loteId) {
            this.loteId = loteId;
        }

        public void execute(FinalizerContext contexto) {
            if (contexto == null || contexto.getResult() == ParentJobResult.SUCCESS) {
                return;
            }
            fechar(this.loteId, contexto.getException());
        }
    }

    /** Separado do Vigilante para se poder testar sem um contexto de finalizador. */
    @TestVisible
    private static void fechar(Id loteId, Exception erro) {
        SC_NosLote.falharPorId(
            loteId,
            erro == null
                ? 'A transacção do passo morreu sem mensagem.'
                : erro.getTypeName() + ': ' + erro.getMessage() + '\n' + erro.getStackTraceString()
        );
    }
}