package br.ufsc.atividade10;

import org.junit.Assert;
import org.junit.Test;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.*;

import static br.ufsc.atividade10.Piece.Type.*;
import static java.lang.String.format;
import static java.util.concurrent.TimeUnit.MILLISECONDS;

public class BufferTest {
    private static final int TIMEOUT = 200;

    private boolean blocks(@Nonnull final Runnable runnable)
            throws InterruptedException {
        final boolean[] returned = {false};
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                runnable.run();
                returned[0] = true;
            }
        });
        thread.start();

        Thread.sleep(BufferTest.TIMEOUT);
        boolean fail = returned[0];
        thread.interrupt();
        thread.join();

        return !fail;
    }

    private boolean takeBlocks(@Nonnull final Buffer buffer) throws InterruptedException {
        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        return blocks(new Runnable() {
            @Override
            public void run() {
                try {
                    buffer.takeOXO(xs, os);
                } catch (InterruptedException ignored) {}
            }
        });
    }

    private boolean addBlocks(@Nonnull final Buffer buffer,
                              @Nonnull final Piece piece) throws InterruptedException {
        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        return blocks(new Runnable() {
            @Override
            public void run() {
                try {
                    buffer.add(piece);
                } catch (InterruptedException ignored) {}
            }
        });
    }

    @Test(timeout = 1000)
    public void testWellBehaved() throws InterruptedException {
        final Buffer buffer = new Buffer(10);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, X));
        buffer.add(new Piece(3, O));

        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        buffer.takeOXO(xs, os);

        List<Piece> expectedO = Arrays.asList(new Piece(1, O), new Piece(3, O)),
                    expectedX = Collections.singletonList(new Piece(2, X));
        Assert.assertEquals(expectedO, os);
        Assert.assertEquals(expectedX, xs);

        Assert.assertTrue("Segundo takeOXO() retornou quando deveria " +
                "bloquear para sempre", takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT)
    public void testBlockOnEmpty() throws InterruptedException {
        Buffer buffer = new Buffer(10);
        Assert.assertTrue(takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT*2)
    public void testBlockWithPartial() throws InterruptedException {
        Buffer buffer = new Buffer(10);
        buffer.add(new Piece(1, O));
        Assert.assertTrue(takeBlocks(buffer));
        buffer.add(new Piece(2, X));
        Assert.assertTrue(takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT)
    public void testAddBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(3);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, X));
        buffer.add(new Piece(3, O));

        Assert.assertTrue(addBlocks(buffer, new Piece(4, O)));
    }

    @Test(timeout = 1000 + TIMEOUT*2)
    public void testAddXBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(4);
        buffer.add(new Piece(1, X));
        buffer.add(new Piece(2, X));

        Assert.assertTrue(addBlocks(buffer, new Piece(3, X)));

        buffer.add(new Piece(4, O)); //no timeout
        buffer.add(new Piece(5, O)); //no timeout

        List<Piece> xs = new ArrayList<>(), os = new ArrayList<>();
        buffer.takeOXO(xs, os);
        //queue state: X

        buffer.add(new Piece(6, X)); //no timeout

        Assert.assertTrue(addBlocks(buffer, new Piece(7, X)));
    }

    @Test(timeout = 2000)
    public void testAddOBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(4);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, O));
        buffer.add(new Piece(3, O));

        Assert.assertTrue(addBlocks(buffer, new Piece(4, O)));

        buffer.add(new Piece(5, X)); //no timeout

        List<Piece> xs = new ArrayList<>(), os = new ArrayList<>();
        buffer.takeOXO(xs, os);
        //buffer state: O

        buffer.add(new Piece(6, O)); //no timeout
        buffer.add(new Piece(7, O)); //no timeout

        Assert.assertTrue(addBlocks(buffer, new Piece(8, O)));
    }

    @Test
    public void testUsingIfWithMonitorsBringsPainAndSuffering() throws Exception {
        Buffer buffer = new Buffer(3);
        buffer.add(new Piece(1, X));
        Assert.assertTrue(addBlocks(buffer, new Piece(2, X)));

        CompletableFuture<?> added = new CompletableFuture<>();
        Thread adder = new Thread(() -> {
            try {
                buffer.add(new Piece(3, X));
                added.complete(null);
            } catch (InterruptedException ignored) {
            }
        });
        adder.start();

        Thread.sleep(200); //chute para esperar adder chegar no add(X)
        buffer.add(new Piece(4, O)); //gerará um notifyAll()
        boolean addXTimeouts = false; // mas add(X) NÃO pode adicionar
        try {
            added.get(300, MILLISECONDS);
        } catch (TimeoutException e) {
            addXTimeouts = true;
        }
        Assert.assertTrue(addXTimeouts);

        adder.interrupt();
        adder.join();
    }

    private static void serialProducer(@Nonnull Buffer buffer, @Nonnull Piece.Type type,
                                       int base, int count) {
        for (int i = 0; i < count; i++) {
            try {
                buffer.add(new Piece(base+i, type));
            } catch (InterruptedException e) {
                break;
            }
        }
    }

    private static void serialConsumer(@Nonnull Buffer buffer, int count,
                                       @Nonnull List<String> errors)  {
        for (int j = 0; j < count; j++) {
            List<Piece> xList = new ArrayList<>(), oList = new ArrayList<>();
            try {
                buffer.takeOXO(xList, oList);
            } catch (InterruptedException e) {
                errors.add("InterruptedException");
                break;
            }
            if (xList.size() != 1)
                errors.add(format("xList.size()=%d", xList.size()));
            if (xList.get(0).getType() != X)
                errors.add("xList.get(0).getType() != X");
            if (oList.size() != 2)
                errors.add(format("oList.size()=%d", xList.size()));
            if (!oList.stream().allMatch(p -> p.getType().equals(O)))
                errors.add("oList contains non-O pieces");
        }
    }

    @Test
    public void testStress() throws InterruptedException {
        Buffer buffer = new Buffer(4);
        ExecutorService exec = Executors.newCachedThreadPool();
        final int count = 1000;
        List<String> errors = Collections.synchronizedList(new ArrayList<>());
        for (int i = 0; i < 10; i++) {
            exec.submit(() -> serialProducer(buffer, O, 0, count));
            exec.submit(() -> serialProducer(buffer, O, count, count));
            exec.submit(() -> serialProducer(buffer, X, count, count));
            exec.submit(() -> serialConsumer(buffer, count, errors));
        }
        exec.shutdown();
        exec.awaitTermination(10, TimeUnit.SECONDS);
        Assert.assertEquals(errors, Collections.emptyList());
    }
}