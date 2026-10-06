//@ pragma AppId sporetify

import Quickshell

import "app"

// Entry point of the full app:  qs -p <repo>/App.qml
// It lives at the repo root so that both app/ and common/ are inside the
// Quickshell config folder (see .claude/architecture, open question 2).
ShellRoot {
  Main {}
}
