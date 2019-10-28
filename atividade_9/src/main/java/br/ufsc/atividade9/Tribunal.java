package br.ufsc.atividade9;

import javax.annotation.Nonnull;
import java.util.concurrent.*;

public class Tribunal implements AutoCloseable {
    protected final ExecutorService executor;

    public Tribunal(int nJuizes, int tamFila) {
        this.executor = new ThreadPoolExecutor(nJuizes, nJuizes, Long.MAX_VALUE, TimeUnit.NANOSECONDS,
                new ArrayBlockingQueue<>(tamFila));
        System.out.println("Executor " + ((ThreadPoolExecutor) executor).getRejectedExecutionHandler());
    }

    public boolean julgar(@Nonnull final Processo processo) throws TribunalSobrecarregadoException {
        Future<Boolean> future = null;
        try {
            future = executor.submit(new Callable<Boolean>() {

                @Override
                public Boolean call() throws Exception {
                	System.out.println("julgando processo " + processo.getId());
                    return checkGuilty(processo);
                }

            });
            Boolean b = future.get();
        	System.out.println("processo " + processo.getId() + " retornou " + b);
            if (b == null) {
            	throw new TribunalSobrecarregadoException();
            } else {
            	return b;
            }
        
        } catch (InterruptedException | ExecutionException e) {
            e.printStackTrace();
            return false;
        } catch (RejectedExecutionException e) {
        	System.out.println("processo " + processo.getId() + " foi rejeitado ");
        	throw new TribunalSobrecarregadoException();
		}
    }

    protected boolean checkGuilty(Processo processo) {
        try {
            Thread.sleep((long) (50 + 50 * Math.random()));
        } catch (InterruptedException ignored) {
        }
        return processo.getId() % 7 == 0;
    }

    @Override
    public void close() throws Exception {
    	executor.shutdown();
        executor.awaitTermination(Long.MAX_VALUE, TimeUnit.SECONDS);
    }
}
