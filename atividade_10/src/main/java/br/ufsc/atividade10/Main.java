package br.ufsc.atividade10;

import java.io.IOException;

public class Main {
    public static void main( String[] args ) {
        Buffer buffer = new Buffer();
        try (Printer printerX = new Printer();
             Printer printerO = new Printer();
             final Robot robot = new Robot()) {
            Thread consolePrinter = new Thread(new Runnable() {
                @Override
                public void run() {
                    while (true) {
                        try {
                            System.out.printf("Produziu %s\n", robot.getQueue().take());
                        } catch (InterruptedException ignored) {
                            break;
                        }
                    }
                }
            });
            consolePrinter.start();
            printerX.start(buffer, Piece.Type.X);
            printerO.start(buffer, Piece.Type.O);
            robot.start(buffer);

            System.out.println("Fábrica iniciada! aperte ENTER para ecerrar!");
            try {
                //noinspection ResultOfMethodCallIgnored
                System.in.read();
            } catch (IOException ignored) {}
            System.out.println("Terminando...");

            printerO.stop();
            printerX.stop();
            robot.stop();
            consolePrinter.interrupt();
            try {
                consolePrinter.join();
            } catch (InterruptedException ignored) {}
        }
    }
}
