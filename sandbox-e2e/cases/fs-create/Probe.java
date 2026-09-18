package de.tum.in.ase;

import java.nio.file.Files;
import java.nio.file.Path;

public class Probe {

    public Object run() throws Exception {
        Path created = Files.createDirectory(Path.of("/var/tmp/probe/created-dir"));
        return created.toString();
    }
}
