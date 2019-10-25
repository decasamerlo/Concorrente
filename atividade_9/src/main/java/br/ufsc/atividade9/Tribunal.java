package br.ufsc.atividade9;

import javax.annotation.Nonnull;
import java.util.concurrent.*;

public class Tribunal implements AutoCloseable {
    protected final ExecutorService executor;

    public Tribunal(int  nJuizes, int tamFila) {
        this.executor = Executors.newSingleThreadExecutor();
    }

    public boolean julgar(@Nonnull final Processo processo)  throws TribunalSobrecarregadoException {
        return checkGuilty(processo);
    }

    protected boolean checkGuilty(Processo processo) {
        try {
            Thread.sleep((long) (50 + 50*Math.random()));
        } catch (InterruptedException ignored) {}
        return processo.getId() % 7 == 0;
    }

    @Override
    public void close() throws Exception {
    }
}
