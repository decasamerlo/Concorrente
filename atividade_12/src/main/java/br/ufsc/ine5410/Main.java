package br.ufsc.ine5410;

import org.kohsuke.args4j.CmdLineException;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;

import javax.annotation.Nonnull;
import java.io.PrintStream;
import java.util.ArrayList;
import java.util.List;

public class Main {
    @Option(name = "--help", aliases = {"-h"}, help = true)
    private boolean help = false;

    @Option(name = "--n-threads", usage = "Número de threads enviando e recebendo")
    private int nThreads = Runtime.getRuntime().availableProcessors();

    public static void main(String[] args) throws Exception {
        Main app = new Main();
        CmdLineParser parser = new CmdLineParser(app);
        try {
            parser.parseArgument(args);
            if (app.help)
                printHelp(parser, System.out);
            else
                app.run();
        } catch (CmdLineException e) {
            e.printStackTrace();
            printHelp(parser, System.err);
        }
    }

    private @Nonnull Thread createSender(int idx, @Nonnull MessageBroker broker) {
        Thread t = new Thread(() -> {
            boolean end = false;
            for (int i = 0; !end; i++) {
                String from = "s"+idx, to = "r"+idx, payload = "msg"+i;
                Message msg = new Message(from, to, payload);
                System.out.printf("SEND %s\n", msg);
                try {
                    broker.sendAndReceive(msg);
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    end = true;
                }
            }
        });
        t.start();
        return t;
    }
    private @Nonnull Thread createReceiver(int idx, @Nonnull MessageBroker broker) {
        Thread t = new Thread(() -> {
            boolean end = false;
            for (int i = 0; !end; i++) {
                try {
                    Message m = broker.receive("r" + idx);
                    m.reply(new Message(m.getReceiver(), m.getSender(), "OK from"+idx));
                    System.out.printf("RCV %s\n", m);
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    end = true;
                }
            }
        });
        t.start();
        return t;
    }

    private void run() throws Exception {
        MessageBroker broker = new MessageBroker();
        System.out.println("%d threads enviando %d mensagens para %d threads " +
                "que responder-las-ão.");

        List<Thread> senders = new ArrayList<>(), receivers = new ArrayList<>();
        for (int i = 0; i < nThreads; i++) {
            senders.add(createSender(i, broker));
            receivers.add(createReceiver(i, broker));
        }

        System.out.println("Aperte ENTER para terminar");
        //noinspection ResultOfMethodCallIgnored
        System.in.read();

        receivers.forEach(Thread::interrupt);
        for (Thread receiver : receivers) receiver.join();
        senders.forEach(Thread::interrupt);
        for (Thread sender : senders) sender.join();
    }

    private static void printHelp(CmdLineParser parser, PrintStream out) {
        out.print("java -jar JAR ");
        parser.printSingleLineUsage(out);
        parser.printUsage(out);
    }
}
