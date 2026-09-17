package de.tum.in.ase;

import java.nio.file.Files;
import java.nio.file.Path;

public class Probe {

    public Object run() throws Exception {
        return new String(Files.readAllBytes(Path.of("/var/tmp/probe/secret.txt")));
    }
}
