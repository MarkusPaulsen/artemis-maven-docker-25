package de.tum.in.ase;

public class Probe {

    public Object run() throws Exception {
        Process process = Runtime.getRuntime().exec(new String[] { "/bin/sh", "-c", "cd /" });
        int code = process.waitFor();
        return "exit=" + code;
    }
}
