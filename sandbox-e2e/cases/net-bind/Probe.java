package de.tum.in.ase;

import java.net.InetSocketAddress;
import java.net.ServerSocket;

public class Probe {

    public Object run() throws Exception {
        ServerSocket server = new ServerSocket();
        server.bind(new InetSocketAddress("127.0.0.1", 18080));
        server.close();
        return "bound";
    }
}
