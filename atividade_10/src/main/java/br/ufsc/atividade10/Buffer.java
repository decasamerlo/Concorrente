package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;

import static br.ufsc.atividade10.Piece.Type.*;

public class Buffer {
    private final int maxSize;

    public Buffer() {
        this(10);
    }
    public Buffer(int maxSize) {
        this.maxSize = maxSize;
    }

    public synchronized void add(Piece piece) throws InterruptedException {
    }

    public synchronized void takeOXO(@Nonnull List<Piece> xList,
                                     @Nonnull List<Piece> oList) throws InterruptedException {
    }
}
