#!/bin/bash

# Set Sporetify up after adding the plugin:
#
#   omarchy plugin add <this repository> --enable
#   ~/.config/omarchy/plugins/namelessnovice.sporetify/scripts/setup.sh
#
# Adding a plugin only copies its files. This installs the rest: the daemon
# that plays the music, its systemd user units, and the `sporetify` command.
# Run it again after updating the plugin to bring the daemon up to date.
#
#   --build   build the daemon here (needs Rust) and skip the download
#
# It touches only Sporetify's own files, and never your Hyprland config.

set -eo pipefail
source "$(dirname "$(readlink -f "$0")")/env.sh"
source "$ROOT/scripts/lib.sh"

build=0
for arg in "$@"; do
  case $arg in
    --build) build=1 ;;
    -h | --help) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$arg' (try --help)" ;;
  esac
done

check_requirements

binary=""
if ((build == 0)); then
  say "fetching the daemon for version $VERSION"
  binary="$(download_daemon)" || binary=""
  [[ -n $binary ]] || say "no usable released daemon for $VERSION here; it will be built from source"
fi
if [[ -z $binary ]]; then
  say "building the daemon (this takes a few minutes the first time)"
  binary="$(build_daemon)"
fi

install_daemon "$binary"
install_launcher
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/sporetify/download"

installed="$("$BIN_DIR/sporetifyd" --version 2>/dev/null || true)"
say "installed ${installed:-the daemon}"
cat <<DONE

Sporetify is set up.

  1. If its icon is not in your bar yet:  omarchy plugin enable $PLUGIN_ID
  2. Restart the shell so it loads this version:  omarchy restart shell
  3. Click the icon and choose "Sign in to Spotify" (Premium is required).

Open the full app with:  sporetify
Remove everything with:  $ROOT/scripts/uninstall.sh
DONE
