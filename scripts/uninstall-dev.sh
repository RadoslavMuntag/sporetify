#!/bin/bash

# Undo scripts/install-dev.sh: the plugin link as well as everything
# uninstall.sh removes. Caches and the sign-in are kept.

set -o pipefail
source "$(dirname "$0")/env.sh"
source "$ROOT/scripts/lib.sh"

omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
[[ -L $PLUGIN_LINK ]] && rm "$PLUGIN_LINK"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
remove_installed

echo "Removed."
