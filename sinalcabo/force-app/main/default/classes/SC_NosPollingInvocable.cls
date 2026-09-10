/**
 * Corrida com janela explícita, para o Flow e para a operação.
 *
 * Ao contrário da corrida agendada, esta não continua para os passos seguintes: lê a
 * janela que lhe deram e pára. Serve para reler uma hora que falhou e para provar a
 * ligação depois de uma mudança.
 *
 * Enfileira o trabalho e devolve o Id do lote que abriu. Havia a intenção de publicar o
 * evento SC_NOS_Polling__e para a leitura correr como o utilizador de integração, mas
 * esse caminho está parado pela mesma razão que o do agendador, explicada no
 * SC_NosPollingScheduler.
 *
 * Quem pode invocá-la controla-se pelo acesso à classe Apex, e não por FLS: o trabalho
 * corre em contexto de sistema, tal como a corrida agendada.
 */
public with sharing class SC_NosPollingInvocable {
    public class Pedido {
        @InvocableVariable(label='Tipo de corrida' description='Abertas, Fechadas, Varrimento ou Manual')
        public String tipo;

        @InvocableVariable(label='Início da janela')
        public Datetime inicio;

        @InvocableVariable(label='Fim da janela')
        public Datetime fim;

        @InvocableVariable(label='Horas para trás' description='Usado quando não se dá janela: conta a partir de agora')
        public Decimal horas;
    }

    public class Resposta {
        @InvocableVariable(label='Lote criado')
        public String loteId;

        @InvocableVariable(label='Mensagem')
        public String mensagem;

        @InvocableVariable(label='Arrancou')
        public Boolean arrancou;
    }

    @InvocableMethod(
        label='Ler ordens da NOS numa janela'
        description='Abre um lote e lê a API Field Force Management na janela pedida, sem continuar para os passos seguintes.'
        category='SinalCabo Field Service'
    )
    public static List<Resposta> executar(List<Pedido> pedidos) {
        List<Resposta> respostas = new List<Resposta>();
        for (Pedido pedido : pedidos) {
            respostas.add(correr(pedido));
        }
        return respostas;
    }

    /** Atalho para Apex anónimo e para os scripts de operação. */
    public static Resposta correr(String tipo, Datetime inicio, Datetime fim) {
        Pedido pedido = new Pedido();
        pedido.tipo = tipo;
        pedido.inicio = inicio;
        pedido.fim = fim;
        return correr(pedido);
    }

    private static Resposta correr(Pedido pedido) {
        Resposta resposta = new Resposta();
        resposta.arrancou = false;

        String motivo = SC_NosConfig.motivoParaNaoCorrer();
        if (motivo != null) {
            resposta.mensagem = motivo;
            return resposta;
        }

        String tipo = String.isBlank(pedido.tipo) ? SC_NosConfig.CORRIDA_MANUAL : pedido.tipo.trim();
        Datetime fim = pedido.fim == null ? Datetime.now() : pedido.fim;
        Datetime inicio = pedido.inicio;
        if (inicio == null) {
            Integer horas = pedido.horas == null || pedido.horas <= 0 ? 1 : pedido.horas.intValue();
            inicio = fim.addHours(-horas);
        }
        if (inicio >= fim) {
            resposta.mensagem = 'A janela pedida acaba antes de começar.';
            return resposta;
        }

        Id loteId = SC_NosPollingScheduler.correrJanela(tipo, inicio, fim);
        if (loteId == null) {
            resposta.mensagem = 'A corrida não arrancou. Ver o estado da integração.';
            return resposta;
        }

        resposta.loteId = loteId;
        resposta.arrancou = true;
        resposta.mensagem = 'Corrida ' + tipo + ' de ' + inicio + ' a ' + fim + '.';
        return resposta;
    }
}