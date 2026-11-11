//@ pragma AppId sporetify-compact

import Quickshell

import "compact"

// Entry point of the compact player:  qs -p <repo>/Compact.qml
// (normally through `sporetify --compact`). At the repo root for the same
// reason as App.qml: so that app/, common/ and compact/ all resolve.
ShellRoot {
  CompactWindow {}
}
