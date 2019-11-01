package br.ufsc.atividade11;

import javax.annotation.Nonnull;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class Market {
    private Map<Product, Double> prices = new HashMap<>();

    public Market() {
        for (Product product : Product.values()) {
            prices.put(product, 1.99);
        }
    }

    public void setPrice(@Nonnull Product product, double value) {
        prices.put(product, value);
    }

    public double take(@Nonnull Product product) {
        return prices.get(product);
    }

    public void putBack(@Nonnull Product product) {
    }

    public double waitForOffer(@Nonnull Product product,
                               double maximumValue) throws InterruptedException {
        //deveria esperar até que prices.get(product) <= maximumValue
        return prices.get(product);
    }

    public double pay(@Nonnull Product product) {
        return prices.get(product);
    }
}
