#!/bin/bash

# Everything that must pass before work is called done.

set -eo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

echo "== daemon: clippy"
cargo clippy --quiet --manifest-path daemon/Cargo.toml --all-targets -- -D warnings

echo "== daemon: tests"
cargo test --quiet --manifest-path daemon/Cargo.toml

echo "== qml: tests"
# Arch's /usr/bin/qmltestrunner is Qt 5, and Qt logs to the journal unless told otherwise.
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner -input tests | grep -Ev '^PASS'

echo "== shaders"
# The checked-in .qsb files must match their sources. Skipped without qsb
# (qt6-shadertools); CI installs it.
if command -v qsb >/dev/null 2>&1 || [[ -x /usr/lib/qt6/bin/qsb ]]; then
  scripts/shaders.sh --check
else
  echo "qsb not installed; shader check skipped"
fi

echo "== lint"
tests/lint.sh

echo "ok"
