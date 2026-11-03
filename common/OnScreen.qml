import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// Whether a window of ours is on a workspace that is being shown, so that
// animations can stop when it is not. A window on a hidden workspace gets
// no frames drawn, but its animations would still tick and cost CPU.
//
// Hyprland only. It asks `hyprctl` which workspace this process's window is
// on and which workspaces the monitors show, special ones
// included; a pinned window counts as shown. It asks once at the start and
// again when Hyprland reports a change of workspace or window, never on a
// timer. If it cannot tell, the window counts as shown. A window covered by
// another on the same workspace still counts as shown.
//
// Quickshell's own Hyprland model is only used for its event stream: on
// Hyprland 0.56 it never learns which workspace a monitor shows until the
// user switches, so every window looked hidden.
QtObject {
  id: root

  property bool shown: true

  // Prints "true" or "false". The window is found by its owner, this
  // process, which is the shell's parent ($PPID): matching by class would
  // find another window of the same kind. jq is already required by setup.
  readonly property string script: "c=$(hyprctl -j clients | jq -c --argjson p \"$PPID\" '[.[] | select(.pid == $p)][0]'); "
    + "m=$(hyprctl -j monitors); "
    + "jq -n --argjson c \"${c:-null}\" --argjson m \"${m:-[]}\" "
    + "'if $c == null or $c.pinned then true "
    + "else ([$m[] | .activeWorkspace.name, .specialWorkspace.name] | index($c.workspace.name)) != null end'"

  property var query: Process {
    command: ["sh", "-c", root.script]
    stdout: StdioCollector {
      onStreamFinished: {
        var answer = text.trim()
        if (answer === "true" || answer === "false") root.shown = answer === "true"
      }
    }
  }

  function ask() {
    if (query.running) {
      again.restart()
      return
    }
    query.running = true
  }

  // A burst of events (a workspace switch sends several) makes one query.
  property var again: Timer {
    interval: 120
    onTriggered: root.ask()
  }

  property var watcher: Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "workspacev2":
      case "focusedmonv2":
      case "activespecialv2":
      case "moveworkspacev2":
      case "openwindow":
      case "movewindowv2":
      case "pin":
      case "monitoraddedv2":
      case "monitorremovedv2":
        root.again.restart()
      }
    }
  }

  Component.onCompleted: ask()
}
