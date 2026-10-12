#!/bin/bash

# Install this checkout for development: build the daemon here, install it
# with its units and the launcher, and link the checkout as an Omarchy shell
# plugin. Run it again after changing the daemon.
#
# Enabling the bar widget is left to you:  omarchy plugin enable <id>

set -eo pipefail
source "$(dirname "$0")/env.sh"
source "$ROOT/scripts/lib.sh"

install_daemon "$(build_daemon)"
install_launcher

if [[ -e $PLUGIN_LINK && ! -L $PLUGIN_LINK ]]; then
  die "$PLUGIN_LINK exists and is not a symlink; leaving it alone"
fi
ln -sfn "$ROOT" "$PLUGIN_LINK"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed. Open the app with: sporetify"
echo "Enable the bar widget with: omarchy plugin enable $PLUGIN_ID"
