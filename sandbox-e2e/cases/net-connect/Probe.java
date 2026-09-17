package de.tum.in.ase;

import java.net.InetSocketAddress;
import java.net.Socket;

public class Probe {

    public Object run() throws Exception {
        Socket socket = new Socket();
        socket.connect(new InetSocketAddress("127.0.0.1", 18080), 3000);
        socket.close();
        return "connected";
    }
}
