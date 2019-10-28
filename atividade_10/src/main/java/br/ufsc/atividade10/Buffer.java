package br.ufsc.atividade10;

import javax.annotation.Nonnull;

import br.ufsc.atividade10.Piece.Type;

import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;

public class Buffer {
    private final int maxSize;
    private final int xMaxSize;
    private final int oMaxSize;
    private List<Piece> listaDePecas;

    public Buffer() {
        this(10);
    }

    public Buffer(int maxSize) {
        this.maxSize = maxSize;
        this.xMaxSize = maxSize - 2;
        this.oMaxSize = maxSize - 1;
        this.listaDePecas = new LinkedList<>();
    }

    public synchronized void add(Piece piece) throws InterruptedException {
        while (!podeAdicionar(piece)) {
            wait();
        }
        this.listaDePecas.add(piece);
        notifyAll();
    }

    public synchronized void takeOXO(@Nonnull List<Piece> xList, @Nonnull List<Piece> oList)
            throws InterruptedException {
        while (!temPecasSuficiente()) {
            wait();
        }

        takeX(xList);
        takeO(oList);

        notifyAll();
    }

    private boolean podeAdicionar(Piece piece) {
        if (this.listaDePecas.size() == this.maxSize) {
            return false;
        } else {
            int xSize = 0, oSize = 0;
            Iterator<Piece> it = listaDePecas.iterator();
            while (it.hasNext()) {
                Piece p = it.next();
                if (Type.X.equals(p.getType())) {
                    xSize++;
                } else {
                    oSize++;
                }
            }
            if (Type.X.equals(piece.getType())) {
                return xSize < this.xMaxSize;
            } else {
                return oSize < this.oMaxSize;
            }
        }
    }

    private boolean temPecasSuficiente() {
        int xSize = 0, oSize = 0;
        Iterator<Piece> it = listaDePecas.iterator();
        while (it.hasNext()) {
            Piece p = it.next();
            if (Type.X.equals(p.getType())) {
                xSize++;
            } else {
                oSize++;
            }
        }
        return xSize >= 1 && oSize >= 2;
    }

    private void takeX(List<Piece> list) {
        Iterator<Piece> it = listaDePecas.iterator();
        while (it.hasNext() && list.size() < 1) {
            Piece p = it.next();
            if (Type.X.equals(p.getType())) {
                list.add(p);
                it.remove();
            }
        }
        notifyAll();
    }

    private void takeO(List<Piece> list) {
        Iterator<Piece> it = listaDePecas.iterator();
        while (it.hasNext() && list.size() < 2) {
            Piece p = it.next();
            if (Type.O.equals(p.getType())) {
                list.add(p);
                it.remove();
            }
        }
        notifyAll();
    }
}
