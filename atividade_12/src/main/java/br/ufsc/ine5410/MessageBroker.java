package br.ufsc.ine5410;

import javax.annotation.Nonnull;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class MessageBroker {
    // DICA: Crie um Map<String, XXXX> que mapeia do edereço do receptor para sua
    // caixa postal, onde mensagens enviadas serão enfileiradas e de onde ele
    // retirará mensagens com receive()

    public void send(@Nonnull Message message) {
        // Envia uma mensagem o mais rápido possível (não bloqueia)
        throw new UnsupportedOperationException(); // me remova quando implementar o método
    }

    public @Nonnull Message sendAndReceive(@Nonnull Message message) throws InterruptedException {
        // Envia uma mensagem e espera sua resposta (Message.waitForReply())
        throw new UnsupportedOperationException(); // me remova quando implementar o método
    }

    public @Nonnull Message receive(@Nonnull String receiverAddress) {
        // Espera uma mensagem enviada para o endereço dado e a retorna
        throw new UnsupportedOperationException(); // me remova quando implementar o método
    }
}
