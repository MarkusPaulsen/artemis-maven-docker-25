package de.tum.in.ase;

import java.nio.file.Files;
import java.nio.file.Path;

public class Probe {

    public Object run() throws Exception {
        Files.delete(Path.of("/var/tmp/probe/deletable.txt"));
        return "deleted";
    }
}
