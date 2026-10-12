import QtQuick
import Quickshell
import Quickshell.Io

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

  // Closing the window (or Ctrl+C) ends the app; the music lives in the daemon.
  onVisibleChanged: if (!visible) Qt.quit()

  // "sidebar" or "list"
  property string pane: "sidebar"
  readonly property var scopes: player.scope === "player" ? ["browse", "player", "app"] : [player.scope, "app"]

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
  // The library loads as soon as the daemon answers at all: connected, it
  // is fresh; offline, it is what was saved. Coming back online refreshes it.
  property string loadedIn: ""
  function loadWhenReady() {
    var phase = player.phase
    if ((phase !== "ready" && phase !== "offline") || loadedIn === phase) return
    if (loadedIn === "ready" && phase === "offline") return
    loadedIn = phase
    library.loadPlaylists()
  }
  Component.onCompleted: loadWhenReady()

  function openSelected() {
    var item = sidebar.itemAt(sidebar.currentIndex)
    if (!item) return
    if (item.kind === "folder") {
      toggleFolder(item.id)
      return
    }
    if (item.kind === "foryou") {
      library.go({ kind: "foryou", name: "For you" }, tracks.currentIndex)
      pane = "list"
      return
    }
    library.go({ kind: "playlist", uri: item.uri, name: item.name }, tracks.currentIndex)
    pane = "list"
  }

  // The app's few preferences, kept across launches.
  FileView {
    id: preferences
    path: Quickshell.env("HOME") + "/.config/sporetify/app.json"
    blockLoading: true
    printErrors: false
    onAdapterUpdated: writeAdapter()

    JsonAdapter {
      id: prefs
      // Draw each track's creature.
      property bool creatures: true
      // Show covers on the rows of lists.
      property bool covers: true
      // Ids of sidebar folders that are folded shut, comma separated.
      property string foldedFolders: ""
    }
  }

  readonly property var foldedFolders: {
    var out = {}
    var ids = prefs.foldedFolders.split(",")
    for (var i = 0; i < ids.length; i++) if (ids[i] !== "") out[ids[i]] = true
    return out
  }
  function toggleFolder(id) {
    var next = []
    var had = false
    for (var key in foldedFolders) {
      if (key === id) had = true
      else next.push(key)
    }
    if (!had) next.push(id)
    prefs.foldedFolders = next.join(",")
  }

  property bool searchOpen: false
  // Open the search field for "spotify" or "library". The text typed so far
  // is kept when switching between the two.
  function openSearch(mode) {
    searchOpen = true
    searchField.forceActiveFocus()
    if (!library.searching || library.searchMode !== mode) {
      library.search(searchField.text, mode, tracks.currentIndex)
    }
    searchField.selectAll()
  }
  // Enter or Down in the field: on to the results.
  function leaveSearchField() {
    pane = "list"
    keys.forceActiveFocus()
  }
  // Esc: close the search and return to what was on screen before it.
  function cancelSearch() {
    if (!searchOpen && !library.searching) return
    searchOpen = false
    library.leaveSearch(tracks.currentIndex)
    keys.forceActiveFocus()
  }

  property bool helpOpen: false

  // One line of feedback for actions with no other visible effect.
  property string noticeText: ""
  property bool noticeIsError: false
  Connections {
    target: library
    function onNotice(text, isError) {
      window.noticeText = text
      window.noticeIsError = isError
      noticeTimer.restart()
    }
  }
  // A refused action (play while offline, a daemon error) is said out loud.
  Connections {
    target: player
    function onLastErrorChanged() {
      if (player.lastError === "") return
      window.noticeText = player.lastError
      window.noticeIsError = true
      noticeTimer.restart()
    }
  }
  Timer {
    id: noticeTimer
    interval: 2600
    onTriggered: window.noticeText = ""
  }

  function act(action) {
    var target = pane === "sidebar" ? sidebar : tracks
    switch (action) {
    case "search": openSearch("spotify"); return
    case "searchLibrary": openSearch("library"); return
    case "searchType": if (library.searching) library.cycleSearchFilter(1); return
    case "help": helpOpen = true; return
    case "back": library.back(tracks.currentIndex); pane = "list"; return
    case "forward": library.forward(tracks.currentIndex); pane = "list"; return
    case "queue": library.go({ kind: "queue" }, tracks.currentIndex); pane = "list"; return
    case "like": library.toggleLike(pane === "list" ? tracks.currentIndex : -1); return
    case "enqueue": library.enqueue(pane === "list" ? tracks.currentIndex : -1); return
    case "artist":
    case "album":
      // From the sidebar there is no row under the cursor, so it means the playing track.
      library.openRelated(action, pane === "list" ? tracks.currentIndex : -1)
      pane = "list"
      return
    case "creatures": prefs.creatures = !prefs.creatures; return
    case "covers": prefs.covers = !prefs.covers; return
    case "quit": Qt.quit(); return
    case "cancel": cancelSearch(); return
    case "paneNext": pane = pane === "sidebar" ? "list" : "sidebar"; return
    case "down": target.move(1); return
    case "up": target.move(-1); return
    case "pageDown": target.move(target.rowsPerPage); return
    case "pageUp": target.move(-target.rowsPerPage); return
    case "top": target.jump(0); return
    case "bottom": target.jump(1e9); return
    case "activate":
      if (pane === "sidebar") openSelected()
      else library.activate(tracks.currentIndex)
      return
    case "reload":
      library.reload()
      return
    }
    player.run(action)
  }

  // Lets scripts and Hyprland binds drive the app:
  //   qs ipc -p <repo>/App.qml call sporetify.app act queue
  IpcHandler {
    target: "sporetify.app"

    // Run a Keymap action by id, as if its key had been pressed.
    function act(action: string): string {
      window.helpOpen = false
      window.act(action)
      return "ok"
    }
    function searchFor(text: string): string { return search(text, "spotify") }
    function searchLibrary(text: string): string { return search(text, "library") }
    function search(text: string, mode: string): string {
      searchField.text = text
      window.searchOpen = true
      library.search(text, mode, tracks.currentIndex)
      window.pane = "list"
      return "ok"
    }
    // all | songs | artists | albums | playlists
    function searchType(filter: string): string {
      library.setSearchFilter(filter)
      return library.searchFilter
    }
    // What is on screen, as JSON. For tests.
    function describe(): string {
      var rows = []
      for (var i = 0; i < Math.min(library.rows.length, 14); i++) {
        var row = library.rows[i]
        rows.push(!row ? null : (row.kind ? row.kind + ": " + row.title
          : (row.liked ? "♥ " : "") + (row.queued ? "+ " : "") + row.title))
      }
      return JSON.stringify({
        kind: library.kind, mode: library.searching ? library.searchMode : "",
        filter: library.searching ? library.searchFilter : "", name: library.name, subtitle: library.subtitle, total: library.total,
        state: library.collection.state, pane: window.pane, cursor: tracks.currentIndex,
        history: library.historyIndex + 1 + "/" + library.history.length,
        phase: player.phase, help: window.helpOpen, searchOpen: window.searchOpen, notice: window.noticeText,
        playingLiked: library.playingLiked, rows: rows,
        artPath: library.artPath, offline: player.offline, sidebar: sidebar.count,
        playingArt: player.track && player.track.art_path ? player.track.art_path : "",
        // What `like` and `enqueue` would act on right now.
        subject: library.subject(window.pane === "list" ? tracks.currentIndex : -1)
      })
    }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      // The help overlay swallows one key: whichever closes it.
      if (window.helpOpen) {
        window.helpOpen = false
        event.accepted = true
        return
      }
      var action = Keymap.actionFor(event.key, event.text, window.scopes, event.modifiers)
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
      collapsed: window.foldedFolders
      offline: player.offline
      onActivated: window.openSelected()
    }

    // ---- Search: a field, and under it the kind of result to show.
    Rectangle {
      id: searchBar
      visible: window.searchOpen && player.scope === "player"
      anchors.top: parent.top
      anchors.left: sidebar.right
      anchors.right: parent.right
      height: visible ? searchRow.height + chips.height + Theme.spacing.md : 0
      color: Theme.raised

      Item {
        id: searchRow
        width: parent.width
        height: Theme.spacing.rowHeight + Theme.spacing.md

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
        // Which search this is, since both share the field.
        Text {
          id: searchWhere
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: searchIcon.right
          anchors.leftMargin: Theme.spacing.lg
          textFormat: Text.PlainText
          text: library.searchMode === "library" ? "Library" : "Spotify"
          color: Theme.accent
          font.family: Theme.font.family
          font.pixelSize: Theme.font.bodySmall
          font.bold: true
        }
        TextInput {
          id: searchField
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: searchWhere.right
          anchors.leftMargin: Theme.spacing.lg
          anchors.right: searchHelp.left
          anchors.rightMargin: Theme.spacing.lg
          clip: true
          color: Theme.foreground
          selectionColor: Theme.selectedFill
          selectedTextColor: Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
          onTextEdited: library.search(text, library.searchMode, tracks.currentIndex)
          Keys.onEscapePressed: window.cancelSearch()
          Keys.onReturnPressed: window.leaveSearchField()
          Keys.onDownPressed: window.leaveSearchField()
          // Tab walks the result types instead of leaving the field.
          Keys.onTabPressed: library.cycleSearchFilter(1)
          Keys.onBacktabPressed: library.cycleSearchFilter(-1)
          Keys.onPressed: function(event) {
            // Switch between the two searches without leaving the field.
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
              window.openSearch("library")
              event.accepted = true
            }
          }
        }
        Text {
          id: searchHelp
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Theme.spacing.huge
          textFormat: Text.PlainText
          text: searchField.activeFocus ? "⇥ type · ⏎ results · Esc cancel" : "/ Spotify · Ctrl F library · t type · Esc cancel"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }

      Row {
        id: chips
        anchors.top: searchRow.bottom
        x: Theme.spacing.huge
        spacing: Theme.spacing.md

        Repeater {
          model: library.searchFilters

          Rectangle {
            required property string modelData
            readonly property bool current: library.searchFilter === modelData
            width: chipText.implicitWidth + Theme.spacing.xl * 2
            height: chipText.implicitHeight + Theme.spacing.sm * 2
            radius: height / 2
            color: current ? Theme.selectedFill : (chipArea.containsMouse ? Theme.hoverFill : "transparent")
            border.width: 1
            border.color: current ? Theme.accent : Theme.line

            Text {
              id: chipText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: parent.modelData.charAt(0).toUpperCase() + parent.modelData.slice(1)
              color: parent.current ? Theme.accent : Theme.muted
              font.family: Theme.font.family
              font.pixelSize: Theme.font.caption
            }
            MouseArea {
              id: chipArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: library.setSearchFilter(parent.modelData)
            }
          }
        }
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
      covers: prefs.covers
      focused: window.pane === "list"
      onActivated: function(index) {
        window.pane = "list"
        library.activate(index)
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

    // ---- Feedback toast, just above the now-playing bar
    Rectangle {
      visible: opacity > 0
      opacity: window.noticeText !== "" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
      anchors.bottom: nowPlaying.top
      anchors.bottomMargin: Theme.spacing.xl
      anchors.horizontalCenter: tracks.horizontalCenter
      width: Math.min(toast.implicitWidth + Theme.spacing.huge * 2, tracks.width - Theme.spacing.huge * 2)
      height: toast.implicitHeight + Theme.spacing.lg * 2
      radius: Theme.spacing.sm
      color: Theme.raised
      border.width: 1
      border.color: window.noticeIsError ? Theme.urgent : Theme.border
      z: 5

      Text {
        id: toast
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - Theme.spacing.huge * 2)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: window.noticeText
        color: window.noticeIsError ? Theme.urgent : Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
    }

    NowPlayingBar {
      id: nowPlaying
      anchors.bottom: hints.top
      width: parent.width
      player: player
      live: window.visible
      visuals: prefs.creatures
      liked: library.playingLiked
      onLikeRequested: library.toggleLike(-1)
      onAlbumRequested: { library.openRelated("album", -1); window.pane = "list" }
      onArtistRequested: { library.openRelated("artist", -1); window.pane = "list" }
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
        primaryOnly: true
        foreground: Theme.foreground
        muted: Theme.muted
        fontFamily: Theme.font.family
        fontSize: Theme.font.caption
        gap: Theme.spacing.xs
      }
    }

    // ---- Every key, on demand. Any key or click closes it.
    Rectangle {
      id: help
      visible: window.helpOpen
      anchors.fill: parent
      color: Theme.alpha(Theme.background, 0.92)

      MouseArea { anchors.fill: parent; onClicked: window.helpOpen = false }

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacing.huge * 4, Theme.space(620))
        spacing: Theme.spacing.xxl

        Text {
          textFormat: Text.PlainText
          text: "Keyboard"
          color: Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.heading
          font.bold: true
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Theme.spacing.huge * 2
          rowSpacing: Theme.spacing.md

          Repeater {
            model: window.helpOpen ? Keymap.hints(window.scopes, false) : []

            Row {
              required property var modelData
              width: (parent.width - parent.columnSpacing) / 2
              spacing: Theme.spacing.xl

              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.space(44)
                height: cap.implicitHeight
                KeyCap {
                  id: cap
                  anchors.right: parent.right
                  label: parent.parent.modelData.key
                  foreground: Theme.foreground
                  fontFamily: Theme.font.family
                  fontSize: Theme.font.bodySmall
                  padding: Theme.spacing.sm
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.label
                color: Theme.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: "Press any key to close"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.bodySmall
        }
      }
    }
  }
}
