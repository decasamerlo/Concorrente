package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;

public class MergeSortSerial<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull List<T> list) {
        if (list.size() <= 1)
            return new ArrayList<>(list);
        int mid = list.size() / 2;
        ArrayList<T> left = sort(list.subList(0, mid));
        ArrayList<T> right = sort(list.subList(mid, list.size()));
        return MergeSortHelper.merge(left, right);
    }
}
