package de.tum.in.ase;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.net.InetSocketAddress;
import java.net.ServerSocket;

import org.junit.jupiter.api.Test;

import de.tum.cit.ase.ares.api.Policy;
import de.tum.cit.ase.ares.api.jupiter.Public;

@Public
public class ProbeTest {

    @Test
    @Policy(value = "SecurityConfiguration.yaml", withinPath = "classes/de/tum/in/ase")
    public void access() throws Exception {
        ServerSocket server = new ServerSocket();
        server.bind(new InetSocketAddress("127.0.0.1", 18080));
        Thread acceptor = new Thread(() -> {
            try {
                server.accept();
            } catch (Exception ignored) {
            }
        });
        acceptor.setDaemon(true);
        acceptor.start();
        try {
            Object result = new Probe().run();
            assertNotNull(result);
        } finally {
            server.close();
        }
    }
}
