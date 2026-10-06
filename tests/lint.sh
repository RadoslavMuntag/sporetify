#!/bin/bash

# Enforces the QML rules from CLAUDE.md that a grep can check:
#   - no colour literals (theme tokens only)
#   - no network from QML (the daemon owns it)
#   - a valid plugin manifest

set -o pipefail
cd "$(dirname "$0")/.." || exit 1

failed=0

report() {
  echo "lint: $1" >&2
  echo "$2" | sed 's/^/  /' >&2
  failed=1
}

mapfile -t qml < <(find . -path ./tests -prune -o -path ./.git -prune -o \
  \( -name '*.qml' -o -name '*.js' \) -type f -print | sort)

if ((${#qml[@]})); then
  hits=$(grep -nE '"#[0-9a-fA-F]{3,8}"|Qt\.rgba\([0-9. ]+,[0-9. ]+,[0-9. ]+' "${qml[@]}")
  [[ -z $hits ]] || report "colour literal; use a theme token" "$hits"

  hits=$(grep -nE 'XMLHttpRequest|\bfetch\(' "${qml[@]}")
  [[ -z $hits ]] || report "network call in QML; this belongs in the daemon" "$hits"
fi

if command -v omarchy >/dev/null 2>&1; then
  out=$(omarchy plugin validate . 2>&1) || report "manifest does not validate" "$out"
fi

exit $failed
