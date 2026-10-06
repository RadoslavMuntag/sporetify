#!/bin/bash

# Install this checkout for development:
#   - sporetifyd (release build) into ~/.local/bin
#   - socket-activated systemd user units
#   - the checkout symlinked as an Omarchy shell plugin
#   - the `sporetify` launcher in ~/.local/bin and an application menu entry
#
# Touches nothing else. Enabling the bar widget is left to you:
#   omarchy plugin enable <id>

set -eo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

cargo build --release --manifest-path daemon/Cargo.toml

mkdir -p "$BIN_DIR" "$UNIT_DIR"
systemctl --user stop sporetifyd.service 2>/dev/null || true
install -m 755 "$CARGO_TARGET_DIR/release/sporetifyd" "$BIN_DIR/sporetifyd"
install -m 644 systemd/sporetifyd.socket systemd/sporetifyd.service "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now sporetifyd.socket

# The app launcher and its entry in the application menu.
ln -sfn "$ROOT/bin/sporetify" "$BIN_DIR/sporetify"
mkdir -p "$APP_DIR"
cat >"$APP_DIR/sporetify.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Sporetify
Comment=Keyboard-first Spotify client
Exec=$BIN_DIR/sporetify
Icon=audio-x-generic
Categories=AudioVideo;Audio;Player;
StartupWMClass=sporetify
DESKTOP

if [[ -e $PLUGIN_LINK && ! -L $PLUGIN_LINK ]]; then
  echo "install-dev: $PLUGIN_LINK exists and is not a symlink; leaving it alone" >&2
  exit 1
fi
ln -sfn "$ROOT" "$PLUGIN_LINK"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed. Open the app with: sporetify"
echo "Enable the bar widget with: omarchy plugin enable $PLUGIN_ID"
