#!/usr/bin/env bash
# One-time cache warm-up, run WITH network before the offline matrix. It populates the sandbox
# user's Maven repo with the exact transitive set the probe project resolves (Ares 2.1.5 pulls
# newer transitives than the image's baked repo has). Run this once against a persistent
# /home/sandbox/.m2 volume, then run the matrix offline against the same volume.
set -eu

HOME_DIR=/home/sandbox
E2E_DIR="${E2E_DIR:-/e2e}"

id sandbox >/dev/null 2>&1 || useradd -m -s /bin/bash sandbox
mkdir -p "$HOME_DIR/.m2"
chown -R sandbox:sandbox "$HOME_DIR"

runuser -u sandbox -- env HOME="$HOME_DIR" bash -c '
  set -e
  WORK=/var/tmp/testing-dir
  rm -rf "$WORK"
  mkdir -p "$WORK/assignment/src/de/tum/in/ase" "$WORK/test/de/tum/in/ase" "$WORK/target"
  cp '"$E2E_DIR"'/base-project/pom.xml "$WORK/"
  cp '"$E2E_DIR"'/cases/fs-read/Probe.java "$WORK/assignment/src/de/tum/in/ase/"
  cp '"$E2E_DIR"'/cases/fs-read/ProbeTest.java "$WORK/test/de/tum/in/ase/"
  cp '"$E2E_DIR"'/cases/fs-read/ares-allow.yaml "$WORK/SecurityConfiguration.yaml"
  mkdir -p /var/tmp/probe; echo seed > /var/tmp/probe/secret.txt
  cd "$WORK"
  # The test outcome is irrelevant; this only needs to resolve and cache every dependency and plugin.
  mvn -B test || true
  echo "prewarm done"
'
