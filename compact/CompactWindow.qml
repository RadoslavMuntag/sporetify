import QtQuick
import Quickshell
import Quickshell.Io

import "../app"
import "../common"
import "../common/Keymap.js" as Keymap
import "../common/Visuals.js" as Visuals

// The compact player's window: a small, good-looking now-playing window
// meant to sit tiled beside a terminal. Its own process, like the app, so
// it can be closed and opened without touching anything else.
FloatingWindow {
  id: window

  title: "Sporetify"
  color: Theme.background
  implicitWidth: Theme.space(340)
  implicitHeight: Theme.space(380)

  // Closing the window ends the process; the music lives in the daemon.
  onVisibleChanged: if (!visible) Qt.quit()

  Player {
    id: player
    wanted: window.visible
    // The daemon only analyses the audio while this is up.
    vizWanted: view.live && player.playing && view.showSpectrum
  }

  // On a workspace being shown; nothing animates otherwise.
  OnScreen { id: screen }

  readonly property var scopes: player.scope === "player" ? ["compact", "mini", "player"] : [player.scope, "compact"]
  property bool keysOpen: false

  // The visuals setting is the app's (~/.config/sporetify/app.json, `v` in
  // the app). Only read here, so the two processes never both write it.
  property string visuals: "full"
  property bool creatures: true
  FileView {
    path: Quickshell.env("HOME") + "/.config/sporetify/app.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        window.visuals = Visuals.level(saved.visuals)
        window.creatures = Visuals.creatures(saved.creatures)
      } catch (e) {
        window.visuals = "full"
        window.creatures = true
      }
    }
  }

  function openApp() {
    Quickshell.execDetached([Qt.resolvedUrl("../bin/sporetify").toString().replace("file://", "")])
  }

  function act(action) {
    switch (action) {
    case "compactKeys": keysOpen = !keysOpen; return
    case "compactClose": Qt.quit(); return
    case "openApp": openApp(); return
    }
    player.run(action)
  }

  // Lets scripts and binds drive it, and tests look at it:
  //   qs ipc --pid <pid> call sporetify.compact act next
  IpcHandler {
    target: "sporetify.compact"

    // Run a Keymap action by id, as if its key had been pressed.
    function act(action: string): string {
      if (window.keysOpen && action !== "compactKeys") {
        window.keysOpen = false
        return "ok"
      }
      window.act(action)
      return "ok"
    }
    function close(): string {
      Qt.quit()
      return "ok"
    }
    // What is on screen, as JSON. For tests.
    function describe(): string {
      return JSON.stringify({
        arrangement: view.arrangement, width: view.width, height: view.height, zoom: view.zoom,
        phase: player.phase, scope: player.scope, playing: player.playing,
        title: view.headline, byline: view.byline, visuals: window.visuals, creatures: window.creatures, keys: window.keysOpen,
        shown: screen.shown, viz: player.vizOn, bands: player.bands.length, beat: player.beat, workspace: screen.toplevel && screen.toplevel.workspace ? screen.toplevel.workspace.name : ""
      })
    }
  }

  Item {
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      // The key list takes any key and closes.
      if (window.keysOpen) {
        event.accepted = true
        window.keysOpen = false
        return
      }
      var action = Keymap.actionFor(event.key, event.text, window.scopes, event.modifiers)
      if (!action) return
      event.accepted = true
      window.act(action)
    }

    CompactView {
      id: view
      anchors.fill: parent
      player: player
      visuals: window.visuals
      creatures: window.creatures
      live: window.visible && screen.shown
      onLensClicked: player.run("playPause")
    }

    // ---- Every key that works here, behind ?
    Rectangle {
      anchors.fill: parent
      visible: opacity > 0
      opacity: window.keysOpen ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.motion.quick } }
      color: Theme.sunken

      Column {
        anchors.centerIn: parent
        width: parent.width - view.pad * 2
        spacing: view.gap

        Text {
          textFormat: Text.PlainText
          text: "KEYS"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: view.px(Theme.font.caption)
          font.letterSpacing: view.px(Theme.font.caption) * 0.12
        }
        Rectangle { width: parent.width; height: Theme.stroke.hair; color: Theme.line }
        HintBar {
          width: parent.width
          scope: window.scopes
          foreground: Theme.foreground
          muted: Theme.muted
          fontFamily: Theme.font.family
          fontSize: view.px(Theme.font.bodySmall)
          gap: view.px(Theme.spacing.sm)
        }
        Rectangle { width: parent.width; height: Theme.stroke.hair; color: Theme.line }
        Text {
          textFormat: Text.PlainText
          text: "Any key closes this list"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: view.px(Theme.font.caption)
        }
      }
    }
  }
}
