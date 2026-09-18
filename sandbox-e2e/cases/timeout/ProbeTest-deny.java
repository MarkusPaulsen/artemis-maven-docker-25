package de.tum.in.ase;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

import de.tum.cit.ase.ares.api.Policy;
import de.tum.cit.ase.ares.api.StrictTimeout;
import de.tum.cit.ase.ares.api.jupiter.Public;

@Public
public class ProbeTest {

    @Test
    @Policy(value = "SecurityConfiguration.yaml", withinPath = "classes/de/tum/in/ase")
    @StrictTimeout(5)
    public void access() throws Exception {
        Object result = new Probe().run();
        assertNotNull(result);
    }
}
