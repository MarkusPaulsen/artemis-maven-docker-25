package de.tum.in.ase;

import java.net.URISyntaxException;

import org.junit.jupiter.api.DynamicContainer;
import org.junit.jupiter.api.TestFactory;

import de.tum.cit.ase.ares.api.StrictTimeout;
import de.tum.cit.ase.ares.api.jupiter.Public;
import de.tum.cit.ase.ares.api.structural.MethodTestProvider;
import de.tum.cit.ase.ares.api.Policy;

/**
 * @author Stephan Krusche (krusche@in.tum.de)
 * @version 5.0 (11.11.2020)
 * <br><br>
 * This test evaluates if the specified methods in the structure oracle are correctly implemented with the expected name, return type, parameter types, visibility modifiers
 * and annotations, based on its definition in the structure oracle (test.json)
 */
@Public
public class MethodTest extends MethodTestProvider {

    /**
     * This method collects the classes in the structure oracle file for which methods are specified.
     * These classes are then transformed into JUnit 5 dynamic tests.
     * @return A dynamic test container containing the test for each class which is then executed by JUnit.
     */
    @StrictTimeout(10)
    @TestFactory
    @Policy(
            value = "SecurityConfiguration.yaml",
            withinPath = "classes/java/main/de/tum/in/ase"
    )
    public DynamicContainer generateTestsForAllClasses() throws URISyntaxException {
        structureOracleJSON = retrieveStructureOracleJSON(this.getClass().getResource("test.json"));
        return super.generateTestsForAllClasses();
    }
}
