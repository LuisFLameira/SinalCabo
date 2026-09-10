/**
 * Executa os pedidos de corrida que chegam pelo evento SC_NOS_Polling__e.
 *
 * Este trigger é o único sítio onde a cadeia de leitura arranca, e corre como o
 * utilizador do PlatformEventSubscriberConfig SC_NosPollingSubscriber, que é o
 * utilizador de integração. Os Queueable que ele enfileira herdam esse utilizador, e é
 * por isso que os lotes e as ordens ficam com o CreatedBy da integração, mesmo quando
 * quem agendou foi uma pessoa.
 *
 * Não decide nada: as regras de arranque (travão, suspensão, lote Em curso) vivem no
 * SC_NosPollingScheduler e são as mesmas para o agendador e para uma corrida manual.
 *
 * Mudar o utilizador do subscritor obriga a re-subscrever, e é isso que um deploy deste
 * ficheiro faz: sem ele a plataforma continua a correr o trigger como Automated Process,
 * que não tem acesso ao principal da credencial e faz todos os lotes falhar.
 */
trigger SC_NosPollingTrigger on SC_NOS_Polling__e (after insert) {
    SC_NosPollingScheduler.executar(Trigger.new);
}