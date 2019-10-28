package br.ufsc.atividade10;

import java.util.Objects;

public class Piece {
    public enum Type {
        X,
        O;
    }
    private final int id;
    private final Type type;

    public Piece(int id, Type type) {
        this.id = id;
        this.type = type;
    }

    public int getId() {
        return id;
    }

    public Type getType() {
        return type;
    }

    @Override
    public String toString() {
        return String.format("%s(%d)", type, id);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Piece piece = (Piece) o;
        return id == piece.id &&
                type == piece.type;
    }

    @Override
    public int hashCode() {
        return Objects.hash(id, type);
    }
}
