#!/usr/bin/env bash
# Runs the matrix as a non-root user. Root bypasses RLIMIT_NPROC, so the threads Phobos-deny case
# only bites for a non-root process. Real grading should be non-root anyway, so this is also the
# faithful condition. Phobos itself needs no privileges, so the sandboxed run works unprivileged.
#
# Invoked as root inside the image; it creates the sandbox user, gives it its own copy of the
# phobos core (the driver rewrites the base cfgs) and its own Maven repo, then drops privileges.
set -eu

HOME_DIR=/home/sandbox
CORE_DIR="$HOME_DIR/core"
E2E_DIR="${E2E_DIR:-/e2e}"

id sandbox >/dev/null 2>&1 || useradd -m -s /bin/bash sandbox

rm -rf "$CORE_DIR"
cp -a /var/tmp/opt/core "$CORE_DIR"
mkdir -p "$HOME_DIR/.m2"
chown -R sandbox:sandbox "$HOME_DIR"

exec runuser -u sandbox -- env \
  HOME="$HOME_DIR" \
  CORE="$CORE_DIR" \
  E2E_DIR="$E2E_DIR" \
  ONLY_TYPES="${ONLY_TYPES:-}" \
  bash "$E2E_DIR/run-matrix.sh"
