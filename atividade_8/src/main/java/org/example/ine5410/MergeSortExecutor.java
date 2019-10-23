package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;

public class MergeSortExecutor<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull List<T> list) {
        //1. Crie um Cached ExecutorService
        // (Executors Single thread ou fixed thread pool) causarão starvation!
        //2. Submete uma tarefa incial ao executor
        //3. Essa tarefa inicial vai se subdividir em novas tarefas enviadas para
        //   o mesmo executor
        //4. Desligue o executor ao sair!

        if (list.size() <= 1)
            return new ArrayList<>(list);

        /* ~~~~ O tipo do executor precisa ser Cached!!!! ~~~~ */
        ExecutorService executor = Executors.newCachedThreadPool();

        int mid = list.size() / 2;
        ArrayList<T> left = null;
        /* ~~~~ Execute essa linha paralelamente! ~~~~ */
        //left = sort(list.subList(0, mid));
        ArrayList<T> right = sort(list.subList(mid, list.size()));

        return MergeSortHelper.merge(left, right);
    }
}
