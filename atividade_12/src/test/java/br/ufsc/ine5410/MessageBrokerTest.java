package br.ufsc.ine5410;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.util.*;
import java.util.concurrent.*;

import static org.junit.Assert.*;

public class MessageBrokerTest {
    private final String s1 = "s1", r1 = "r1", r2 = "r2";
    private final String HI = "HOW_ARE_YOU", FINE = "FINE_THANKS";

    private MessageBroker broker;
    private ExecutorService exec;

    @Before
    public void setUp() {
        exec = Executors.newCachedThreadPool();
        broker = new MessageBroker();
    }

    @After
    public void tearDown() throws InterruptedException {
        exec.shutdownNow();
        exec.awaitTermination(1, TimeUnit.SECONDS);
    }

    @Test(timeout = 2000)
    public void testSendThenReceive() throws Exception {
        Message sent = new Message(s1, r1, HI);
        broker.send(sent);
        Message received = broker.receive(r1);
        assertSame(sent, received);
    }

    @Test(timeout = 2000)
    public void testReceiveBeforeSend() throws Exception {
        Message sent = new Message(s1, r1, HI);
        Future<Message> receiveFuture = exec.submit(() -> broker.receive(r1));
        Thread.sleep(100);
        broker.send(sent);
        Message received = receiveFuture.get(200, TimeUnit.MILLISECONDS);
        assertSame(sent, received);
    }

    @Test(timeout = 2000)
    public void testReceiveInOder() throws Exception {
        List<Message> sent = new ArrayList<>(), received = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            Message msg = new Message(s1, r1, HI + i);
            sent.add(msg);
            broker.send(msg);
        }
        for (int i = 0; i < 10; i++)
            received.add(broker.receive(r1));
        assertEquals(sent, received);
    }

    @Test(timeout = 1000)
    public void testIndependentReceivers() throws Exception {
        Future<Message> m1 = exec.submit(() -> broker.receive(r1));
        Future<Message> m2 = exec.submit(() -> broker.receive(r2));
        Thread.sleep(100);
        Message sent1 = new Message(s1, r1, HI), sent2 = new Message(s1, r2, HI);
        broker.send(sent1);
        broker.send(new Message(s1, r1, HI+2));

        Message received1 = m1.get(100, TimeUnit.MILLISECONDS); //throws if timeout
        assertSame(received1, sent1);

        // m2 não lerá mensagens enviadas para r1...
        broker.send(new Message(s1, r1, HI+3));
        Thread.sleep(100);
        assertFalse(m2.isDone());

        broker.send(sent2); // libera m2
        Message received2 = m2.get(100, TimeUnit.MILLISECONDS);// throws if timeout
        assertSame(sent2, received2);
    }

    @Test(timeout = 1000)
    public void testSendAndReceive() throws Exception {
        Message sent = new Message(s1, r1, HI);
        Message reply = new Message(r1, s1, FINE);
        Future<?> replyFuture = exec.submit(() -> {
            Message msg = broker.receive(r1);
            assertSame(sent, msg); // re-lançado no get()
            msg.reply(reply);
            return null;
        });
        Thread.sleep(200);
        assertFalse(replyFuture.isDone()); // está bloqueado no receive()

        Message received = broker.sendAndReceive(sent);
        replyFuture.get(100, TimeUnit.MILLISECONDS); // throws if timeout

        assertSame(reply, received);
    }

    @Test(timeout = 5000)
    public void testConcurrentReceiveInOrder() throws Exception {
        List<Message> sent = new ArrayList<>(), received = new ArrayList<>();
        Future<?> sender = exec.submit(() -> {
            for (int i = 0; i < 23000; i++) {
                Message msg = new Message(s1, r1, HI + i);
                sent.add(msg);
                broker.send(msg);
            }
        });
        Future<?> receiver = exec.submit(() -> {
            for (int i = 0; i < 23000; i++)
                received.add(broker.receive(r1));
            return null;
        });

        sender.get(2, TimeUnit.SECONDS);   // throws if times out
        receiver.get(2, TimeUnit.SECONDS); // throws if times out

        assertSetEquals(sent, received);
    }

    @Test(timeout = 7000)
    public void testConcurrentReceive() throws Exception {
        Queue<Message> sent = new LinkedList<>(), received = new ConcurrentLinkedQueue<>();
        int nThreads = Runtime.getRuntime().availableProcessors() * 2;
        for (int i = 0; i < nThreads; i++) {
            exec.submit(() -> {
                for (int j = 0; j < 2300; j++)
                    received.add(broker.receive(r1));
                return null;
            });
        }
        for (int i = 0; i < nThreads * 2300; i++) {
            Message msg = new Message(s1, r1, HI + i);
            sent.add(msg);
            broker.send(msg);
        }
        exec.shutdown();
        // Espera até todas as mensagens serem recebidas.
        // Travou aqui? Você pode ter um deadlock/starvation ou extrabiou uma mensagem.
        // O número de receives é igual ao número de sends
        assertTrue(exec.awaitTermination(5, TimeUnit.SECONDS));

        assertSetEquals(sent, received);
    }


    @Test(timeout = 5000)
    public void testConcurrentSend() throws Exception {
        Queue<Message> sent = new ConcurrentLinkedQueue<>(), received = new LinkedList<>();
        int nThreads = Runtime.getRuntime().availableProcessors() * 2;
        for (int i = 0; i < nThreads; i++) {
            exec.submit(() -> {
                for (int j = 0; j < 2300; j++) {
                    Message msg = new Message(s1, r1, HI + j);
                    sent.add(msg);
                    broker.send(msg);
                }
            });
        }
        for (int i = 0; i < nThreads * 2300; i++)
            received.add(broker.receive(r1));
        exec.shutdown();
        assertTrue(exec.awaitTermination(1, TimeUnit.SECONDS));

        assertSetEquals(sent, received);
    }

    @Test(timeout = 11000)
    public void testConcurrentSendThenReceive() throws Exception {
        Queue<Message> sent = new ConcurrentLinkedQueue<>();
        Queue<Message> received = new ConcurrentLinkedQueue<>();
        int nThreads = Runtime.getRuntime().availableProcessors() * 2;
        for (int i = 0; i < nThreads; i++) {
            exec.submit(() -> {
                for (int j = 0; j < 2300; j++) {
                    Message msg = new Message(s1, r1, HI + j);
                    sent.add(msg);
                    broker.send(msg);
                }
            });
            exec.submit(() -> {
                for (int j = 0; j < 2300; j++)
                    received.add(broker.receive(r1));
                return null;
            });
        }
        exec.shutdown();
        assertTrue(exec.awaitTermination(10, TimeUnit.SECONDS));

        assertSetEquals(sent, received);
    }

    /**
     * Creates sets for the arguments and compare for equality.
     *
     * Complexity is justified by less disturbing JUnit output for large non-equal input
     */
    private static void assertSetEquals(Collection<Message> sent,
                                        Collection<Message> received) {
        assertEquals(sent.size(), received.size());
        Set<Message> sentSet = new HashSet<>(sent), receivedSet = new HashSet<>(received);

        Set<Message> missing = new HashSet<>(sentSet);
        missing.removeAll(receivedSet);
        assertTrue(missing.isEmpty());

        HashSet<Message> extra = new HashSet<>(received);
        extra.removeAll(sentSet);
        assertTrue(extra.isEmpty());
    }

}