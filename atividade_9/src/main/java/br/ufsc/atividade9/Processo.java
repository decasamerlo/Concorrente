package br.ufsc.atividade9;

public class Processo {
    private final int id;
    private final Tipo tipo;

    public enum Tipo {
        LATROCINIO,
        HOMICIDIO,
        NAO_INDENTACAO,
        FURTO,
        SONEGACAO,
        LAVAGEM_DE_DINHEIRO;

        boolean isGrave() {
            switch (this) {
                case HOMICIDIO:
                case LATROCINIO:
                case NAO_INDENTACAO:
                    return true;
                default: return false;
            }
        }
    }

    public Processo(int id, Tipo tipo) {
        this.id = id;
        this.tipo = tipo;
    }

    public int getId() {
        return id;
    }

    public Tipo getTipo() {
        return tipo;
    }

    @Override
    public String toString() {
        return String.format("Processo{id=%d, tipo=%s}", id, tipo.name());
    }
}
