#!/bin/bash

# Remove what setup.sh installed: the daemon, its systemd units, the
# `sporetify` command and its menu entry.
#
#   --purge   also remove the caches, the saved resume point, the app's
#             preferences and the Spotify sign-in kept in the keyring
#
# The plugin itself is removed with:  omarchy plugin remove <id>

set -o pipefail
source "$(dirname "$(readlink -f "$0")")/env.sh"
source "$ROOT/scripts/lib.sh"

purge=0
for arg in "$@"; do
  case $arg in
    --purge) purge=1 ;;
    -h | --help) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$arg' (try --help)" ;;
  esac
done

remove_installed
say "removed the daemon, its units and the launcher"

if ((purge)); then
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/sporetify" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/sporetify" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/sporetify"
  secret-tool clear service sporetify account spotify 2>/dev/null || true
  say "removed caches, saved state, preferences and the Spotify sign-in"
else
  say "kept your caches and sign-in; run with --purge to remove them too"
fi

echo "To remove the plugin as well:  omarchy plugin remove $PLUGIN_ID"
