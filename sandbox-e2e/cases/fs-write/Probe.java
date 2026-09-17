package de.tum.in.ase;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

public class Probe {

    public Object run() throws Exception {
        Path path = Path.of("/var/tmp/probe/writable.txt");
        Files.write(path, "overwritten".getBytes(), StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING);
        return "written";
    }
}
