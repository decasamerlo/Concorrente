package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;

public class MergeSortThread<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull final List<T> list) {
        //1. Há duas sub-tarefas, execute-as em paralelo usando threads
        //  (Para pegar um retorno da thread filha faça ela escrever em um ArrayList)
        final ArrayList<ArrayList<T>> results = new ArrayList<>();
        results.add(null);

        if (list.size() <= 1)
            return new ArrayList<>(list);

        int mid = list.size() / 2;
        ArrayList<T> left = null;
        /* ~~~~ Execute essa linha paralelamente! ~~~~ */
        
        Thread d = new Thread(() -> {
            results.set(0, sort(list.subList(0, mid)));
        });
        d.start();

        try {
            d.join();
        } catch(InterruptedException e) {
            e.printStackTrace();
        }
        left = results.get(0);
        ArrayList<T> right = sort(list.subList(mid, list.size()));
        return MergeSortHelper.merge(left, right);
    }
}
