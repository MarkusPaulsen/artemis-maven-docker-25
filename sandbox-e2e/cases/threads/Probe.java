package de.tum.in.ase;

import java.util.ArrayList;
import java.util.List;

public class Probe {

    public Object run() throws Exception {
        List<Thread> threads = new ArrayList<>();
        Throwable failure = null;
        try {
            for (int i = 0; i < 400; i++) {
                Thread thread = new Thread(() -> {
                    try {
                        Thread.sleep(300);
                    } catch (InterruptedException ignored) {
                    }
                });
                thread.start();
                threads.add(thread);
            }
        } catch (Throwable creationFailure) {
            // nproc exhausted: catch it here so the started threads can drain and free the limit
            // before we report, otherwise surefire itself cannot spawn its reporting thread.
            failure = creationFailure;
        }
        for (Thread thread : threads) {
            thread.join();
        }
        if (failure != null) {
            throw new RuntimeException("unable to create native thread (blocked): " + failure, failure);
        }
        return "spawned " + threads.size();
    }
}
