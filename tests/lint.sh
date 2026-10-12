#!/bin/bash

# Enforces the QML rules from CLAUDE.md that a grep can check:
#   - no colour literals (theme tokens only)
#   - no network from QML (the daemon owns it)
#   - a valid plugin manifest
#   - one version in the manifest, the daemon and the changelog

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

# One version everywhere: setup.sh downloads the daemon named by the
# manifest, and the changelog has to describe it.
manifest_version=$(jq -r .version manifest.json)
daemon_version=$(sed -n 's/^version = "\(.*\)"/\1/p' daemon/Cargo.toml | head -n1)
[[ $manifest_version == "$daemon_version" ]] ||
  report "versions differ" "manifest.json $manifest_version, daemon/Cargo.toml $daemon_version"
grep -q "^## $manifest_version" CHANGELOG.md 2>/dev/null ||
  report "no changelog entry" "CHANGELOG.md has no '## $manifest_version' section"

if command -v omarchy >/dev/null 2>&1; then
  out=$(omarchy plugin validate . 2>&1) || report "manifest does not validate" "$out"
fi

exit $failed
