package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;

public class MergeSortThread<T extends Comparable<T>> implements MergeSort<T> {

    // private int threadCounter = 1;
    private ThreadGroup tg = new ThreadGroup("groupThreads");

    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull final List<T> list) {
        // 1. Há duas sub-tarefas, execute-as em paralelo usando threads
        // (Para pegar um retorno da thread filha faça ela escrever em um ArrayList)
        final ArrayList<ArrayList<T>> results = new ArrayList<>();
        results.add(null);

        if (list.size() <= 1)
            return new ArrayList<>(list);

        int mid = list.size() / 2;
        ArrayList<T> left = null;
        /* ~~~~ Execute essa linha paralelamente! ~~~~ */
        if (Thread.currentThread().getThreadGroup() != tg) { // muito lento, chega mais próximo
        // if (list.size() == Thread.activeCount()) { // -> não roda concorrentemente
        // if (list.size() == 3) { // -> muito lento, chega próximo
        // if (list.size() % 2 == 0) { // -> muito lento
        // if (list.size() == Thread.getAllStackTraces().size()) { // -> muito lento 
            // threadCounter++;
            // System.out.println("ThreadCounter: " + threadCounter);
            Thread d = new Thread(tg, () -> {
                results.set(0, sort(list.subList(0, mid)));
            });
            d.start();

            try {
                d.join();
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            left = results.get(0);
        } else {
            left = sort(list.subList(0, mid));
        }
        ArrayList<T> right = sort(list.subList(mid, list.size()));
        return MergeSortHelper.merge(left, right);
    }
}
