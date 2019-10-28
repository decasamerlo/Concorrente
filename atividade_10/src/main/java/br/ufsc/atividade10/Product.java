package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.Arrays;
import java.util.List;

public class Product {
    private final @Nonnull List<Piece> pieces;

    public Product(@Nonnull Piece x, @Nonnull Piece base, @Nonnull Piece top) {
        if (x.getType() != Piece.Type.X) throw new IllegalArgumentException();
        if (base.getType() != Piece.Type.O) throw new IllegalArgumentException();
        if (top.getType() != Piece.Type.O) throw new IllegalArgumentException();

        pieces = Arrays.asList(base, x, top);
    }

    @Override
    public String toString() {
        return String.format("Product{%d, %d, %d}", pieces.get(0).getId(),
                pieces.get(1).getId(), pieces.get(2).getId());
    }
}
