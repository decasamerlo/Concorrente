package br.ufsc.atividade10;

import javax.annotation.Nonnull;

public class Printer implements AutoCloseable {
    private int nextId = 1;
    private Thread thread;

    public synchronized void start(@Nonnull final Buffer destination,
                                   @Nonnull final Piece.Type type) {
        if (thread != null) return;

        thread = new Thread(new Runnable() {
            @Override
            public void run() {
                while (true) {
                    try {
                        destination.add(print(type));
                    } catch (InterruptedException e) {
                        break;
                    }
                }
            }
        }, String.format("Printer-%x", System.identityHashCode(this)));
        thread.start();
    }

    protected Piece print(@Nonnull Piece.Type type) throws InterruptedException {
        Thread.sleep((long) (50 + Math.random()*50));
        return new Piece(++nextId, type);
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
