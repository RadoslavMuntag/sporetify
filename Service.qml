import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

import "common"

// Plugin service: one Player shared by every bar instance, plus the IPC
// target that Hyprland binds call.
Player {
  id: root

  property var shell: null
  property var manifest: null

  // Bar widgets raise this while the mini-player is open.
  property bool surfaceOpen: false

  // The daemon as the desktop sees it. Watching this costs nothing and tells
  // us when playback was started from somewhere else (media keys, the app)
  // while this service was disconnected.
  readonly property var mprisPlayer: {
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].identity === "Sporetify") return players[i]
    }
    return null
  }
  wanted: surfaceOpen || (mprisPlayer !== null && mprisPlayer.isPlaying)

  signal toggleMiniRequested()

  // Focus the full app's window, or start it.
  function openApp() {
    Quickshell.execDetached([Qt.resolvedUrl("bin/sporetify").toString().replace("file://", "")])
  }

  IpcHandler {
    target: "sporetify"

    function status(): string { return root.phase }
    function wake(): string { root.wake(); return "ok" }
    function playPause(): string { root.run("playPause"); return "ok" }
    function next(): string { root.run("next"); return "ok" }
    function previous(): string { root.run("previous"); return "ok" }
    function volumeUp(): string { root.run("volumeUp"); return "ok" }
    function volumeDown(): string { root.run("volumeDown"); return "ok" }
    function mute(): string { root.run("mute"); return "ok" }
    function signIn(): string { root.run("signIn"); return "ok" }
    function toggleMini(): string { root.toggleMiniRequested(); return "ok" }
    function toggleApp(): string { root.openApp(); return "ok" }
    function nowPlaying(): string {
      return root.track ? root.track.title + " — " + root.track.artists.join(", ") : ""
    }
  }
}
