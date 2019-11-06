package br.ufsc.ine5410;

import org.junit.After;
import org.junit.Before;
import org.junit.Ignore;
import org.junit.Test;

import java.util.concurrent.*;

import static org.junit.Assert.*;

public class MessageTest {
    private ExecutorService exec;

    @Before
    public void setUp() {
        exec = Executors.newCachedThreadPool();
    }

    @After
    public void tearDown() throws InterruptedException {
        exec.shutdownNow();
        exec.awaitTermination(1, TimeUnit.SECONDS);
    }

    @Test
    public void testWaitForReplyWaitsInteruptibly() throws Exception {
        Message msg = new Message("s1", "r1", "HI");
        Future<Message> future = exec.submit(msg::waitForReply);
        boolean timedOut = false;
        try {
            future.get(500, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            timedOut = true;
        } finally {
            future.cancel(true);
        }

        exec.shutdown();
        assertTrue(exec.awaitTermination(500, TimeUnit.MILLISECONDS));
        assertTrue(timedOut);;
    }

    @Test
    public void testCannotReplyTwice() {
        Message msg = new Message("s1", "r1", "HOW_ARE_YOU");
        msg.reply(new Message("r1", "s1", "FINE_THANKS"));
        boolean caught = false;
        try {
            msg.reply(new Message("r1", "s1", "WE_ARE_DOOMED"));
        } catch (IllegalStateException ex) {
            caught = true;
        }
        assertTrue("Message.reply() aceitou segundo reply ao invés de " +
                "lançar IllegalStateException", caught);
    }

    @Test
    public void testRetainsEarlyReply() throws Exception {
        Message msg = new Message("s1", "r1", "HI");
        msg.reply(new Message("r1", "s1", "HELLO"));
        Future<Message> future = exec.submit(msg::waitForReply);

        future.get(200, TimeUnit.MILLISECONDS); //may throw TimeoutException
    }

    @Test
    public void testReceivesLateReply() throws Exception {
        Message msg = new Message("s1", "r1", "HI");
        Future<Message> future = exec.submit(msg::waitForReply);
        Thread.sleep(200);
        msg.reply(new Message("r1", "s1", "HELLO"));

        future.get(200, TimeUnit.MILLISECONDS); //may throw TimeoutException
    }
}