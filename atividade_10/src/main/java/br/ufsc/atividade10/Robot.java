package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.concurrent.SynchronousQueue;

public class Robot implements AutoCloseable {
    private Thread thread;
    private SynchronousQueue<Product> queue = new SynchronousQueue<>();

    public synchronized void start(@Nonnull final Buffer buffer) {
        if (thread != null) return;

        thread = new Thread(new Runnable() {
            @Override
            public void run() {
                while (true) {
                    ArrayList<Piece> xList = new ArrayList<>(), oList = new ArrayList<>();
                    try {
                        buffer.takeOXO(xList, oList);
                        assert xList.size() == 1;
                        assert oList.size() == 2;
                        queue.put(new Product(xList.get(0), oList.get(0), oList.get(1)));
                    } catch (InterruptedException e) {
                        break;
                    }
                }
            }
        }, String.format("Robot-%x", System.identityHashCode(this)));
        thread.start();
    }

    public SynchronousQueue<Product> getQueue() {
        return queue;
    }

    public synchronized void stop() {
        if (thread == null) return;
        thread.interrupt();
        try {
            thread.join();
        } catch (InterruptedException ignored) {}
        thread = null;
    }


    @Override
    public void close() {
        stop();
    }
}
