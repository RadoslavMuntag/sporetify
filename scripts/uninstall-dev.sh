#!/bin/bash

# Undo scripts/install-dev.sh.

set -o pipefail
source "$(dirname "$0")/env.sh"

omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
[[ -L $PLUGIN_LINK ]] && rm "$PLUGIN_LINK"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

systemctl --user disable --now sporetifyd.socket sporetifyd.service 2>/dev/null || true
rm -f "$BIN_DIR/sporetify" "$APP_DIR/sporetify.desktop"
rm -f "$UNIT_DIR/sporetifyd.socket" "$UNIT_DIR/sporetifyd.service" "$BIN_DIR/sporetifyd"
systemctl --user daemon-reload

echo "Removed."
