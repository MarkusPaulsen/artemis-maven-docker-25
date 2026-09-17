package de.tum.in.ase;

public class Probe {

    public Object run() throws Exception {
        Process process = Runtime.getRuntime().exec(new String[] { "/var/tmp/probe/tool" });
        int code = process.waitFor();
        return "exit=" + code;
    }
}
