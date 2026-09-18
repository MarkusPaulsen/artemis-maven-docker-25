# Sandbox E2E matrix

An end-to-end test that both security layers of this image act, and act together:

- **Ares** guards the JVM (bytecode instrumentation, attached as a `-javaagent`, configured by a
  `SecurityConfiguration.yaml` policy).
- **Phobos** guards the operating system (Landlock for files and TCP ports, a seccomp connect-guard,
  rlimits and a timeout; embedded under `/var/tmp/opt/core`, configured by `Base*.cfg` files).

Every case wraps a real `mvn test` with `phobos.sh` inside a container that is started
`--network none`, with no `--privileged`, no `--cap-add` and no `--security-opt`, and runs as a
non-root user:

```
phobos.sh --config <maven base> -- mvn -o test
```

A tiny supervised probe in `de.tum.in.ase` performs exactly one guarded access; a trusted
`@Public` test invokes it; the harness classifies the outcome (from the process exit code, the
Surefire report and the thrown-exception type) and compares it to the expected verdict.

## The matrix

Nine access types times four quadrants. A quadrant sets each layer to allow or deny:
Q1 Ares-deny / Phobos-allow, Q2 Ares-allow / Phobos-deny, Q3 both deny, Q4 both allow.

| Access type | Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|---|
| fs-read, fs-write, fs-create, fs-delete | Ares | Phobos | Ares | allowed |
| net-connect, net-bind | Ares | Phobos | Ares | allowed |
| execute (run an executable file) | Ares | Phobos | Ares | allowed |
| command (run a console/shell built-in) | Ares | allowed | Ares | allowed |
| threads | Ares | Phobos | Ares | allowed |
| timeout | Ares | Phobos | Phobos | allowed |

Most types block statically in Ares (an empty policy category installs an ArchUnit deny-all rule
that fires before the call runs) and block at the OS level in Phobos (`EACCES` from Landlock, a
refused connect, a fork refusal, or a hard timeout kill). Three rows deviate for real reasons:

- **command** (a shell built-in such as `cd` via `sh -c`) is Ares-only. Phobos governs OS
  resources, not a shell's internal logic, and `/bin/sh` must stay executable for the build, so Q2
  and Q4 are allowed. This is the mirror image of `net-bind`, where Ares' runtime layer has no
  local-bind concept and only Phobos closes the gap.
- **timeout** Q3 is Phobos, not Ares. Ares' `@StrictTimeout` is a soft check that reports only
  after the method returns; Phobos' timeout is a hard wall-clock kill that fires first.
- **threads** Q2 relies on Phobos' `nproc` rlimit, which the kernel enforces only for a non-root
  process (root bypasses `RLIMIT_NPROC`). The harness runs as a non-root user for this reason; a
  preflight skips this one cell where `RLIMIT_NPROC` is not enforced (for example Docker Desktop's
  linuxkit kernel) rather than reporting a false failure.

Two access types from the original sketch are deliberately absent:

- **fs-execute as a filesystem permission** does not exist in Ares: `executeAllFiles` governs
  native-library loading (`System.load`), which Ares forbids categorically and no policy can
  permit. Running an executable file is the `execute` row above (a `Runtime.exec`, governed by
  Landlock's `[execute]` right and Ares' command policy).

## Running it

Locally, against a built or pulled image (`<image>`), from the repository root:

```
docker volume create sandbox-e2e-m2
docker run --rm -v sandbox-e2e-m2:/home/sandbox/.m2 -v "$PWD/sandbox-e2e:/e2e:ro" <image> bash /e2e/prewarm.sh
docker run --rm --network none -v sandbox-e2e-m2:/home/sandbox/.m2 -v "$PWD/sandbox-e2e:/e2e:ro" <image> bash /e2e/run-nonroot.sh
```

`ONLY_TYPES="threads timeout"` selects a subset. In CI this is `.github/workflows/sandbox-e2e.yml`,
run natively per architecture (never under QEMU, because Landlock and the connect-guard are
unreliable emulated).

## Layout

```
base-project/     minimal Maven project (pom + empty source trees); the probe is overlaid per case
base-policy/      the non-root Maven Phobos base the harness stages per run
cases/<type>/     Probe.java, ProbeTest.java, ares-allow.yaml, ares-deny.yaml, phobos-*.cfg, expect
prewarm.sh        one-time cache warm-up (with network), as the sandbox user
run-matrix.sh     the driver: stages each case, runs it, classifies, compares to expect
run-nonroot.sh    creates the sandbox user, gives it its own core copy and Maven repo, runs the driver
```
