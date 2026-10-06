import QtQuick
import Quickshell

import "../common"
import "../common/Keymap.js" as Keymap

// The app window: sidebar, track list, now-playing bar and the hint bar.
// One key handler serves the whole window; what a key means comes from
// Keymap, by the focused pane and the player's state.
FloatingWindow {
  id: window

  title: "Sporetify"
  color: Theme.background
  implicitWidth: Theme.space(1100)
  implicitHeight: Theme.space(720)

  // Closing the window ends the app; the music lives in the daemon.
  onVisibleChanged: if (!visible) Qt.quit()

  // "sidebar" or "list"
  property string pane: "sidebar"
  readonly property var scopes: player.scope === "player" ? ["browse", "player"] : [player.scope]

  Player {
    id: player
    wanted: window.visible
  }

  Library {
    id: library
    player: player
  }

  // The library can only load once the daemon is connected to Spotify.
  Connections {
    target: player
    function onPhaseChanged() { window.loadWhenReady() }
  }
  property bool loadedOnce: false
  function loadWhenReady() {
    if (loadedOnce || player.phase !== "ready") return
    loadedOnce = true
    library.loadPlaylists()
  }
  Component.onCompleted: loadWhenReady()

  function openSelected() {
    var item = sidebar.itemAt(sidebar.currentIndex)
    if (!item) return
    library.open(item.uri, item.name)
    pane = "list"
  }

  property bool searchOpen: false
  function openSearch() {
    searchOpen = true
    searchField.forceActiveFocus()
    searchField.selectAll()
    if (!library.searching) library.search(searchField.text)
  }
  // Back to the lists, keeping the results on screen.
  function leaveSearchField(toResults) {
    if (toResults) pane = "list"
    else searchOpen = false
    keys.forceActiveFocus()
  }

  function act(action) {
    var target = pane === "sidebar" ? sidebar : tracks
    switch (action) {
    case "search": openSearch(); return
    case "close": Qt.quit(); return
    case "paneNext": pane = pane === "sidebar" ? "list" : "sidebar"; return
    case "down": target.move(1); return
    case "up": target.move(-1); return
    case "pageDown": target.move(target.rowsPerPage); return
    case "pageUp": target.move(-target.rowsPerPage); return
    case "top": target.jump(0); return
    case "bottom": target.jump(1e9); return
    case "activate":
      if (pane === "sidebar") openSelected()
      else library.play(tracks.currentIndex)
      return
    case "reload":
      loadedOnce = player.phase === "ready"
      library.reload()
      return
    }
    player.run(action)
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      var action = Keymap.actionFor(event.key, event.text, window.scopes)
      if (!action) return
      event.accepted = true
      window.act(action)
    }

    Sidebar {
      id: sidebar
      anchors.top: parent.top
      anchors.bottom: nowPlaying.top
      width: Math.min(Theme.space(280), parent.width * 0.3)
      library: library
      focused: window.pane === "sidebar"
      onActivated: window.openSelected()
    }

    Rectangle {
      id: searchBar
      visible: window.searchOpen && player.scope === "player"
      anchors.top: parent.top
      anchors.left: sidebar.right
      anchors.right: parent.right
      height: visible ? Theme.spacing.rowHeight + Theme.spacing.lg : 0
      color: Theme.raised

      Text {
        id: searchIcon
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.spacing.huge
        textFormat: Text.PlainText
        // nf-md-magnify
        text: "\uDB80\uDF49"
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.icon
      }
      TextInput {
        id: searchField
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: searchIcon.right
        anchors.leftMargin: Theme.spacing.lg
        anchors.right: searchHelp.left
        anchors.rightMargin: Theme.spacing.lg
        clip: true
        color: Theme.foreground
        selectionColor: Theme.selectedFill
        selectedTextColor: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        onTextEdited: library.search(text)
        Keys.onEscapePressed: window.leaveSearchField(false)
        Keys.onReturnPressed: window.leaveSearchField(true)
        Keys.onDownPressed: window.leaveSearchField(true)
      }
      Text {
        id: searchHelp
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.huge
        textFormat: Text.PlainText
        text: searchField.activeFocus ? "⏎ results · Esc close" : "/ edit"
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }
    }

    TrackList {
      id: tracks
      anchors.top: searchBar.bottom
      anchors.bottom: nowPlaying.top
      anchors.left: sidebar.right
      anchors.right: parent.right
      visible: player.scope === "player"
      library: library
      player: player
      focused: window.pane === "list"
      onActivated: function(index) {
        window.pane = "list"
        library.play(index)
      }
    }

    // Signed out, offline or no daemon: say so, with the one thing to do.
    Column {
      anchors.centerIn: tracks
      visible: player.scope !== "player"
      spacing: Theme.spacing.xl

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: {
          switch (player.phase) {
          case "signed_out": return "Sign in to Spotify to start listening"
          case "offline": return "Can't reach Spotify. Retrying…"
          case "no_premium": return "Spotify Premium is required to play"
          case "incompatible": return "Daemon and app versions differ. Rebuild the daemon"
          default: return "The Sporetify daemon is not reachable"
          }
        }
        color: player.scope === "fault" ? Theme.urgent : Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.title
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "Press " + Keymap.keyLabel(player.scope === "signedOut" ? "signIn" : "retry")
          + " to " + (player.scope === "signedOut" ? "sign in" : "retry")
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
    }

    NowPlayingBar {
      id: nowPlaying
      anchors.bottom: hints.top
      width: parent.width
      player: player
      live: window.visible
    }

    Rectangle {
      id: hints
      anchors.bottom: parent.bottom
      width: parent.width
      height: hintBar.implicitHeight + Theme.spacing.md * 2
      color: Theme.sunken

      Rectangle { width: parent.width; height: 1; color: Theme.line }

      HintBar {
        id: hintBar
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.spacing.huge
        width: parent.width - Theme.spacing.huge * 2
        scope: window.scopes
        foreground: Theme.foreground
        muted: Theme.muted
        fontFamily: Theme.font.family
        fontSize: Theme.font.caption
        gap: Theme.spacing.xs
      }
    }
  }
}
