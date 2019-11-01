package br.ufsc.atividade11;

import org.junit.After;
import org.junit.Assert;
import org.junit.Test;

import javax.annotation.Nonnull;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Semaphore;

import static br.ufsc.atividade11.Product.*;

public class MarketTest {
    private static final int TEST_TIMEOUT = 1000;
    private static final int BLOCK_TIMEOUT = 200;

    private ArrayList<Thread> stopList = new ArrayList<>();

    @After
    public void tearDown() throws InterruptedException {
        for (Thread thread : stopList) {
            thread.interrupt();
            thread.join();
        }
    }

    private boolean blocks(@Nonnull final Runnable runnable)
            throws InterruptedException {
        final boolean returned[] = {false};
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                runnable.run();
                returned[0] = true;
            }
        });
        thread.start();

        Thread.sleep(BLOCK_TIMEOUT);
        boolean fail = returned[0];
        stopList.add(thread);

        return !fail;
    }


    @Test(timeout = TEST_TIMEOUT + BLOCK_TIMEOUT)
    public void testSetPriceBlocks() throws InterruptedException {
        final Market m = new Market();
        double expected = m.take(COFFEE);
        Assert.assertTrue(blocks(new Runnable() {
            @Override
            public void run() {
                m.setPrice(COFFEE, 2);
            }
        }));
        Assert.assertEquals(expected, m.pay(COFFEE), 0);
    }

    @Test(timeout = TEST_TIMEOUT)
    public void testSetUnrelatedPrice() throws InterruptedException {
        final Market m = new Market();
        double expected = m.take(COFFEE);
        Assert.assertTrue(blocks(new Runnable() {
            @Override
            public void run() {
                m.setPrice(COFFEE, 63);
            }
        }));
        m.setPrice(NOODLES, 3);
        Assert.assertEquals(expected, m.pay(COFFEE), 0);
    }

    @Test(timeout = TEST_TIMEOUT)
    public void testPutBack() throws InterruptedException {
        final Market m = new Market();
        m.take(COFFEE);
        Assert.assertTrue(blocks(new Runnable() {
            @Override
            public void run() {
                m.setPrice(COFFEE, 23);
            }
        }));
        m.putBack(COFFEE);
        Assert.assertFalse(blocks(new Runnable() {
            @Override
            public void run() {
                m.setPrice(COFFEE, 23);
            }
        }));
        Assert.assertEquals(23, m.take(COFFEE), 0);
    }

    @Test(timeout = TEST_TIMEOUT + 2*BLOCK_TIMEOUT)
    public void testCountTakes() throws InterruptedException {
        final Market m = new Market();
        double expected = m.take(COKE);
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                m.setPrice(COKE, 47);
            }
        });
        thread.start();
        Thread.sleep(BLOCK_TIMEOUT);
        Assert.assertEquals(expected, m.take(COKE), 0);

        m.putBack(COKE);
        Thread.sleep(BLOCK_TIMEOUT);
        Assert.assertEquals(expected, m.pay(COKE), 0);

        thread.join();
        Assert.assertEquals(47, m.take(COKE), 0);
        m.putBack(COKE);
    }

    @Test(timeout = TEST_TIMEOUT + 2*BLOCK_TIMEOUT)
    public void waitForOffer() throws InterruptedException {
        final Market m = new Market();

        m.setPrice(NOODLES, 1.5);

        final boolean interrupted[] = {false};
        final double wakeupPrice[] = {0};
        final double waiterPayedValue[] = {0};
        final Semaphore waiterAwaked = new Semaphore(0);
        final Semaphore waiterPay = new Semaphore(0);
        final Semaphore waiterPayed = new Semaphore(0);
        Thread waiter = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    wakeupPrice[0] = m.waitForOffer(NOODLES, 0.75);
                    waiterAwaked.release();
                    waiterPay.acquire();
                    waiterPayedValue[0] = m.pay(NOODLES);
                    waiterPayed.release();
                } catch (InterruptedException e) {
                    interrupted[0] = true;
                }
            }
        });
        waiter.start();

        //pega dois itens, devolve 1...
        Assert.assertEquals(1.5, m.take(NOODLES), 0);
        Assert.assertEquals(1.5, m.take(NOODLES), 0);
        Assert.assertEquals(1.5, m.pay(NOODLES), 0);

        //seta preço em outra thread
        final Semaphore priceUpdated = new Semaphore(0);
        Thread setter = new Thread(new Runnable() {
            @Override
            public void run() {
                m.setPrice(NOODLES, 0.76);
                priceUpdated.release();
            }
        });
        setter.start();

        //outra thread não consegue setar o preço, pois está bloqueada
        Thread.sleep(BLOCK_TIMEOUT);
        Assert.assertEquals(0, waiterAwaked.availablePermits());
        Assert.assertEquals(0, priceUpdated.availablePermits());
        //libera item, setter vai ser desbloqueada
        m.putBack(NOODLES);
        priceUpdated.acquire();

        // atualizou preço, mas não dispara condição
        Assert.assertEquals(0.76, m.take(NOODLES), 0);
        m.putBack(NOODLES);
        Assert.assertEquals(0, waiterAwaked.availablePermits());

        // novo preço: dispara condição
        m.setPrice(NOODLES, 0.65);
        Thread.sleep(BLOCK_TIMEOUT);
        waiterAwaked.acquire();
        Assert.assertFalse(interrupted[0]);
        Assert.assertEquals(wakeupPrice[0], 0.65, 0);

        //thread waiter tem o item na cesta, setPrice() bloqueia
        Assert.assertTrue(blocks(new Runnable() {
            @Override
            public void run() {
                m.setPrice(NOODLES, 1);
            }
        }));
        //faz o waiter pagar
        waiterPay.release();
        waiterPayed.acquire(); //espera pagamento feito
        //verifica valor pago (ultimo setPrice() não teve efeito)
        Assert.assertEquals(0.65, waiterPayedValue[0], 0);
    }

    @Test(timeout = 100*20*5 + TEST_TIMEOUT)
    public void testWaitForOfferHasNoStarvation() throws InterruptedException {
        final Market m = new Market();
        double price = 4;
        m.setPrice(COKE, price);

        for (int i = 0; i < 100; i++) {
            List<Thread> waiters = new ArrayList<>();
            for (int j = 0; j < 20; j++) {
                Thread waiter = new Thread(() -> {
                    try {
                        m.waitForOffer(COKE, 3);
                    } catch (InterruptedException ignored) { }
                });
                waiter.start();
                waiters.add(waiter);
            }
            m.setPrice(COKE, price -= 0.01);
            for (Thread waiter : waiters) waiter.interrupt();
            for (Thread waiter : waiters) waiter.join();
        }
    }
}
