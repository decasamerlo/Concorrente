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
	private Map<Product, ReadWriteLock> locks = new HashMap<>();
	private Map<Product, Condition> conditions = new HashMap<>();

	public Market() {
		for (Product product : Product.values()) {
			prices.put(product, 1.99);
			locks.put(product, new ReentrantReadWriteLock());
			conditions.put(product, locks.get(product).writeLock().newCondition());
		}
	}

	public void setPrice(@Nonnull Product product, double value) {
		locks.get(product).writeLock().lock();
		prices.put(product, value);
		conditions.get(product).signalAll();
		locks.get(product).writeLock().unlock();
	}

	public double take(@Nonnull Product product) {
		locks.get(product).readLock().lock();
		return prices.get(product);
	}

	public void putBack(@Nonnull Product product) {
		locks.get(product).readLock().unlock();
	}

	public double waitForOffer(@Nonnull Product product, double maximumValue) throws InterruptedException {
		locks.get(product).writeLock().lock();
		try {
			while (prices.get(product) > maximumValue) {
				conditions.get(product).await();
			}
			locks.get(product).readLock().lock();
		} finally {
			locks.get(product).writeLock().unlock();
		}
		// deveria esperar até que prices.get(product) <= maximumValue
		return prices.get(product);
	}

	public double pay(@Nonnull Product product) {
		double price = prices.get(product);
		locks.get(product).readLock().unlock();
		return price;
	}
}
