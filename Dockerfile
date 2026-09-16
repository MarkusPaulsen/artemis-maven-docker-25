FROM maven:3.9.11-eclipse-temurin-25

LABEL maintainer="Stephan Krusche <krusche@tum.de>"

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends gnupg && \
    rm -rf /var/lib/apt/lists/*

ENV M2_HOME=/usr/share/maven

RUN echo "$LANG -- $LANGUAGE -- $LC_ALL" \
    && curl --version \
    && gpg --version \
    && git --version \
    && mvn --version \
    && java --version \
    && javac --version

ADD artemis-java-template /opt/artemis-java-template

RUN cd /opt/artemis-java-template && pwd && ls -la && mvn clean install test && mvn spotbugs:spotbugs checkstyle:checkstyle pmd:pmd

RUN cd /opt/artemis-java-template && pwd && ls -la && ./gradlew clean test check -x test publishToMavenLocal && ./gradlew --version && ./gradlew --stop

RUN rm -rf /opt/artemis-java-template

# Embed Phobos, the operating-system sandbox layer, from its own published multi-arch image.
# Only its compiled core is copied (the scripts, the Landlock wrapper, the connect guard and
# the per-architecture libnetblocker.so), not that image's base, and buildx pulls the copy
# that matches the architecture being built. Its binaries are static-pie and its library
# needs no glibc newer than this base ships, so they load here. Ares guards the JVM, Phobos
# the operating system, the container the machine: separate layers, and this image now carries
# the first two so a grading run can wrap its build command with phobos.sh.
COPY --from=ghcr.io/ls1intum/phobos:latest /var/tmp/opt/core /var/tmp/opt/core
ENV PHOBOS_HOME=/var/tmp/opt/core
ENV PATH=/var/tmp/opt/core:$PATH
RUN test -x /var/tmp/opt/core/phobos.sh \
    && test -x /var/tmp/opt/core/phobos-connect-guard \
    && test -x /var/tmp/opt/core/phobos-landlock \
    && test -f /var/tmp/opt/core/libnetblocker.so

CMD ["mvn"]
