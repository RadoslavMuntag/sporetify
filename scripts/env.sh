# Sourced by the other scripts.
#
# Build output stays out of the checkout: the checkout is symlinked into
# ~/.config/omarchy/plugins/, where the shell reloads plugins on file changes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ID="$(jq -r .id "$ROOT/manifest.json")"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sporetify/target}"

BIN_DIR="$HOME/.local/bin"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
PLUGIN_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
VERSION="$(jq -r .version "$ROOT/manifest.json")"
REPOSITORY="$(jq -r .repository "$ROOT/manifest.json")"
