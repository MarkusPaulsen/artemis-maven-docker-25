#!/usr/bin/env bash
# Ares-2-plus-Phobos sandbox E2E matrix driver. Runs inside the amd25 image.
#
# For every access type under cases/<type>/ and every quadrant it runs
#   phobos.sh --config <case base> -- mvn -o test
# once, classifies the outcome and compares it to the type's expected verdict.
#
# Layers under test:
#   Ares  = JVM instrumentation (-javaagent), config in SecurityConfiguration.yaml
#   Phobos = OS sandbox (Landlock + connect-guard + rlimits), config in Base*.cfg
#
# Quadrant -> (Ares, Phobos): Q1 deny/allow, Q2 allow/deny, Q3 deny/deny, Q4 allow/allow.
set -u

E2E_DIR="${E2E_DIR:-/e2e}"
CORE="${CORE:-/var/tmp/opt/core}"
WORK=/var/tmp/testing-dir
PROBE_DIR=/var/tmp/probe
LOG_DIR="${LOG_DIR:-/var/tmp/e2e-logs}"
mkdir -p "$LOG_DIR"

TYPES=(fs-read fs-write fs-create fs-delete net-connect net-bind execute command threads timeout)
# For fast iteration a subset can be selected: ONLY_TYPES="threads timeout" bash run-matrix.sh
if [ -n "${ONLY_TYPES:-}" ]; then read -ra TYPES <<< "$ONLY_TYPES"; fi
QUADRANTS=(Q1 Q2 Q3 Q4)

fail_count=0
skip_count=0

# Preflight: is RLIMIT_NPROC actually enforced here? Docker Desktop's linuxkit kernel does not
# enforce it, so the threads Phobos-deny case (Q2, which relies on nproc) is gated off where it
# cannot bite, rather than reported as a false failure. A native CI runner enforces it.
nproc_enforced() {
  # bash retries a failed fork and still reports success for `&`, so count nothing: set a low
  # limit, spawn well past it, and look for the kernel's fork-refusal on stderr. Root bypasses
  # RLIMIT_NPROC, so this reads "no" for root and "yes" for an ordinary user.
  # Lowering the soft limit is always allowed; if it cannot be set to 30 the user's hard limit is
  # already below 30, which itself means nproc is constrained, so do not bail out on that failure.
  local err
  err="$( ( ulimit -u 30 2>/dev/null
            i=0; while [ "$i" -lt 200 ]; do sleep 2 & i=$((i+1)); done
            wait ) 2>&1 1>/dev/null )"
  case "$err" in
    *"Resource temporarily unavailable"*|*"fork: retry"*|*"Cannot allocate"*) echo yes;;
    *) echo no;;
  esac
}
NPROC_ENFORCED="$(nproc_enforced)"
echo "preflight: RLIMIT_NPROC enforced = $NPROC_ENFORCED"

# --- one-time: swap the shipped Gradle base for our Maven base in the core dir ---
rm -f "$CORE"/BaseLanguage-java.cfg "$CORE"/Base*.cfg 2>/dev/null
cp "$E2E_DIR/base-policy/BaseSandboxMaven.cfg" "$CORE/BaseSandboxMaven.cfg"

# ares_config <type> <allow|deny>  -> writes WORK/SecurityConfiguration.yaml
write_ares_config() {
  local type="$1" mode="$2"
  if [ "$mode" = allow ]; then
    cp "$E2E_DIR/cases/$type/ares-allow.yaml" "$WORK/SecurityConfiguration.yaml"
  else
    cp "$E2E_DIR/cases/$type/ares-deny.yaml" "$WORK/SecurityConfiguration.yaml"
  fi
}

# phobos_base <type> <allow|deny> -> stages the per-case Base*.cfg beside the maven base
write_phobos_base() {
  local type="$1" mode="$2"
  rm -f "$CORE"/BaseCase.cfg
  local src="$E2E_DIR/cases/$type/phobos-$mode.cfg"
  [ -f "$src" ] && cp "$src" "$CORE/BaseCase.cfg"
}

# classify <phobos_rc> <build_log> <surefire_report> -> prints a verdict token
classify() {
  local rc="$1" build="$2" report="$3"
  # 1. phobos setup aborts and build/dependency failures: the run never happened
  case "$rc" in 11|12|13|15) echo "HARNESS_ERROR(phb-$rc)"; return;; esac
  if grep -qE "Could not resolve dependencies|Cannot access central|COMPILATION ERROR|Cannot create resource|Unknown lifecycle phase" "$build" 2>/dev/null; then
    echo "HARNESS_ERROR(build)"; return
  fi
  # 2. wall-clock timeout enforced by the phobos timeout layer
  if [ "$rc" = 14 ]; then echo "BLOCKED_BY_PHOBOS(timeout)"; return; fi
  # 3. read the probe test outcome. Classify only on the thrown-exception header lines
  # (column 0), never on indented stack frames: every test is wrapped by Ares'
  # JupiterStrictTimeoutExtension, so its frame appears in every trace and must not be matched.
  if [ ! -f "$report" ]; then echo "HARNESS_ERROR(no-report)"; return; fi
  local hdr
  hdr="$(grep -E '^[^[:space:]]' "$report")"
  if printf '%s' "$hdr" | grep -qE "blocked by Ares|Ares Security Error|von Ares blockiert|Ares Sicherheitsfehler"; then
    if grep -qE "archunit|Architecture" "$report"; then echo "BLOCKED_BY_ARES(static)"; else echo "BLOCKED_BY_ARES(runtime)"; fi
    return
  fi
  if printf '%s' "$hdr" | grep -qE "execution timed out|timed out after|TimeoutException|AssertionFailedError.*timed out"; then
    echo "BLOCKED_BY_ARES(timeout)"; return
  fi
  if printf '%s' "$hdr" | grep -qE "AccessDeniedException|Permission denied|EACCES|EROFS|error=13|Operation not permitted|EPERM|unable to create native thread|Resource temporarily unavailable|Cannot run program|SocketException|BindException|ConnectException"; then
    echo "BLOCKED_BY_PHOBOS"; return
  fi
  # 4. the probe ran to completion with no denial signal
  if grep -qE "Tests run: 1, Failures: 0, Errors: 0" "$report"; then echo "ALLOWED"; return; fi
  echo "UNKNOWN"
}

# normalise a detailed verdict to the coarse expectation vocabulary
coarse() {
  case "$1" in
    BLOCKED_BY_ARES*) echo BLOCKED_BY_ARES;;
    BLOCKED_BY_PHOBOS*) echo BLOCKED_BY_PHOBOS;;
    ALLOWED) echo ALLOWED;;
    *) echo "$1";;
  esac
}

run_case() {
  local type="$1" quad="$2"
  local ares phb
  case "$quad" in
    Q1) ares=deny;  phb=allow;;
    Q2) ares=allow; phb=deny;;
    Q3) ares=deny;  phb=deny;;
    Q4) ares=allow; phb=allow;;
  esac

  # threads Q2 (Ares allow, Phobos deny via nproc) can only bite where RLIMIT_NPROC is enforced.
  if [ "$type" = threads ] && [ "$quad" = Q2 ] && [ "$NPROC_ENFORCED" != yes ]; then
    printf '  %-11s %s  %-26s  -- SKIPPED (RLIMIT_NPROC not enforced here; runs on a native CI runner)\n' "$type" "$quad" "SKIPPED(env)"
    skip_count=$((skip_count+1)); return
  fi

  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$E2E_DIR/base-project/pom.xml" "$WORK/"
  mkdir -p "$WORK/assignment/src/de/tum/in/ase" "$WORK/test/de/tum/in/ase" "$WORK/target"
  cp "$E2E_DIR/cases/$type/Probe.java" "$WORK/assignment/src/de/tum/in/ase/Probe.java"
  # A type may ship an Ares-mode-specific test (e.g. timeout needs @StrictTimeout(1) vs (60)).
  local testsrc="$E2E_DIR/cases/$type/ProbeTest.java"
  [ -f "$E2E_DIR/cases/$type/ProbeTest-$ares.java" ] && testsrc="$E2E_DIR/cases/$type/ProbeTest-$ares.java"
  cp "$testsrc" "$WORK/test/de/tum/in/ase/ProbeTest.java"
  write_ares_config "$type" "$ares"
  write_phobos_base "$type" "$phb"

  rm -rf "$PROBE_DIR"; mkdir -p "$PROBE_DIR"
  # per-type target setup + optional -D args on stdout as MVN_ARGS=...
  local mvn_args=""
  if [ -f "$E2E_DIR/cases/$type/setup.sh" ]; then
    mvn_args="$(bash "$E2E_DIR/cases/$type/setup.sh" "$phb")"
  fi

  local build="$LOG_DIR/${type}-${quad}.build.log"
  ( cd "$WORK" && "$CORE/phobos.sh" --config "$CORE/BaseSandboxMaven.cfg" -- mvn -o -B $mvn_args test ) > "$build" 2>&1
  local rc=$?
  # The supervised probe test is always de.tum.in.ase.ProbeTest, so name its plain-text Surefire
  # report explicitly rather than globbing (the JUnit XML carries a TEST- prefix, the .txt does not).
  local report="$WORK/target/surefire-reports/de.tum.in.ase.ProbeTest.txt"
  local verdict
  verdict="$(classify "$rc" "$build" "${report:-/nonexistent}")"

  local want
  want="$(sed -n "$(( ${quad#Q} ))p" "$E2E_DIR/cases/$type/expect")"
  local got
  got="$(coarse "$verdict")"
  if [ "$got" = "$want" ]; then
    printf '  %-11s %s  %-26s  == %s  OK\n' "$type" "$quad" "$verdict" "$want"
  else
    printf '  %-11s %s  %-26s  != %s  FAIL\n' "$type" "$quad" "$verdict" "$want"
    fail_count=$((fail_count+1))
  fi
}

echo "=== Ares + Phobos sandbox E2E matrix ==="
for type in "${TYPES[@]}"; do
  [ -d "$E2E_DIR/cases/$type" ] || { echo "  $type  (no case dir, skipped)"; continue; }
  for quad in "${QUADRANTS[@]}"; do
    run_case "$type" "$quad"
  done
done

echo "=== $fail_count mismatch(es), $skip_count env-skipped ==="
exit $(( fail_count > 0 ? 1 : 0 ))
