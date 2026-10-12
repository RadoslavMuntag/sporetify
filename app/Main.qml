import QtQuick
import Quickshell
import Quickshell.Io

import "../common"
import "../common/Keymap.js" as Keymap
import "../common/Faults.js" as Faults

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
      property bool sidebar: true
      onSidebarChanged: if (!sidebar) window.pane = "list"
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

  // ---- Choosing a playlist to add tracks to
  property bool pickerOpen: false
  // [{ uri, title }] being added.
  property var pickerTracks: []
  // What the picker lists: the user's playlists whose name holds every
  // typed word, then, when something has been typed, a row that creates a
  // playlist of that name. Creating comes last so that Enter on a name that
  // already exists adds to it and does not make a second one.
  readonly property var pickerChoices: {
    var typed = pickerFilter.text.trim()
    var words = typed.toLowerCase().split(/\s+/)
    var out = library.editablePlaylists.filter(function(playlist) {
      var name = playlist.name.toLowerCase()
      for (var i = 0; i < words.length; i++) if (words[i] !== "" && name.indexOf(words[i]) === -1) return false
      return true
    })
    if (typed !== "") out = out.concat([{ create: true, name: typed }])
    return out
  }
  function openPicker(index) {
    var tracks = library.selection(index)
    if (tracks.length === 0) return
    pickerTracks = tracks
    pickerFilter.text = ""
    pickerList.currentIndex = 0
    pickerOpen = true
    pickerFilter.forceActiveFocus()
  }
  function closePicker() {
    pickerOpen = false
    keys.forceActiveFocus()
  }
  function confirmPicker() {
    var choice = pickerChoices[pickerList.currentIndex]
    if (choice && pickerTracks.length > 0) {
      if (choice.create) library.createPlaylist(choice.name, pickerTracks)
      else library.addToPlaylist(choice, pickerTracks)
    }
    closePicker()
  }

  // ---- Asking for a line of text (a new playlist's name, a new name)
  property bool promptOpen: false
  property string promptTitle: ""
  property var promptAccept: null
  function ask(title, initial, accept) {
    promptTitle = title
    promptAccept = accept
    promptField.text = initial
    promptOpen = true
    promptField.forceActiveFocus()
    promptField.selectAll()
  }
  function closePrompt() {
    promptOpen = false
    promptAccept = null
    keys.forceActiveFocus()
  }
  function confirmPrompt() {
    var text = promptField.text.trim()
    var accept = promptAccept
    closePrompt()
    if (text !== "" && accept) accept(text)
  }

  // The playlist rename and delete act on: the one under the sidebar's
  // cursor, or from the list pane the one on screen.
  function targetPlaylist() {
    if (pane === "sidebar") return sidebar.itemAt(sidebar.currentIndex)
    if (library.kind !== "playlist") return null
    for (var i = 0; i < library.editablePlaylists.length; i++)
      if (library.editablePlaylists[i].uri === library.uri) return library.editablePlaylists[i]
    return null
  }

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
    case "addToPlaylist": openPicker(pane === "list" ? tracks.currentIndex : -1); return
    case "removeFromPlaylist":
      // In the sidebar it means the playlist; in the list, tracks.
      if (pane === "sidebar") library.deletePlaylist(sidebar.itemAt(sidebar.currentIndex))
      else library.removeFromPlaylist(tracks.currentIndex)
      return
    case "mark":
      if (pane === "list" && library.toggleMark(tracks.currentIndex)) tracks.move(1)
      return
    case "moveDown":
    case "moveUp":
      if (pane !== "list") return
      var landed = library.moveTrack(tracks.currentIndex, action === "moveDown" ? 1 : -1)
      if (landed >= 0) tracks.jump(landed)
      return
    case "newPlaylist":
      ask("Name the new playlist", "", function(name) { library.createPlaylist(name, []) })
      return
    case "rename":
      var playlist = targetPlaylist()
      if (!playlist || playlist.editable !== true) {
        library.notice("Move to one of your own playlists to rename it", true)
        return
      }
      ask("Rename " + playlist.name, playlist.name, function(name) { library.renamePlaylist(playlist.uri, name) })
      return
    case "enqueue": library.enqueue(pane === "list" ? tracks.currentIndex : -1); return
    case "artist":
    case "album":
      // From the sidebar there is no row under the cursor, so it means the playing track.
      library.openRelated(action, pane === "list" ? tracks.currentIndex : -1)
      pane = "list"
      return
    case "creatures": prefs.creatures = !prefs.creatures; return
    case "covers": prefs.covers = !prefs.covers; return
    case "sidebar":
      prefs.sidebar = !prefs.sidebar
      // Focus follows: into the sidebar when it appears, out when it goes.
      pane = prefs.sidebar ? "sidebar" : "list"
      return
    case "quit": Qt.quit(); return
    case "cancel":
      // A selection is cleared before a search is left.
      if (library.markedCount > 0) library.clearMarks()
      else cancelSearch()
      return
    case "paneNext":
      // With the sidebar hidden there is only the list.
      pane = pane === "sidebar" || !prefs.sidebar ? "list" : "sidebar"
      return
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
    // ---- Helpers for tests. Anything that writes names its target
    //      explicitly: tracks by uri, playlists by exact name.

    // Add tracks (uris separated by commas) to the user's playlist of this
    // exact name, as picking it in the playlist picker would.
    function addTo(playlistName: string, trackUris: string): string {
      var tracks = trackUris.split(",").filter(function(uri) { return uri.indexOf("spotify:track:") === 0 })
        .map(function(uri) { return { uri: uri, title: uri } })
      if (tracks.length === 0) return "no track uris"
      for (var i = 0; i < library.editablePlaylists.length; i++) {
        if (library.editablePlaylists[i].name === playlistName) {
          library.addToPlaylist(library.editablePlaylists[i], tracks)
          return "ok"
        }
      }
      return "no such playlist"
    }
    // Type into whichever of the picker or the prompt is open, and confirm.
    function answer(text: string): string {
      if (window.promptOpen) {
        promptField.text = text
        window.confirmPrompt()
        return "prompt"
      }
      if (window.pickerOpen) {
        pickerFilter.text = text
        // The playlist of exactly this name if there is one, else the first row.
        var at = 0
        for (var i = 0; i < window.pickerChoices.length; i++) {
          if (!window.pickerChoices[i].create && window.pickerChoices[i].name === text) at = i
        }
        pickerList.currentIndex = at
        var chosen = window.pickerChoices[at]
        window.confirmPicker()
        return chosen ? (chosen.create ? "created " : "added to ") + chosen.name : "nothing to pick"
      }
      return "nothing open"
    }
    // Put the sidebar's cursor on the entry of this exact name.
    function sidebarTo(name: string): string {
      for (var i = 0; i < sidebar.count; i++) {
        var item = sidebar.itemAt(i)
        if (item && item.name === name) {
          sidebar.currentIndex = i
          window.pane = "sidebar"
          return "ok"
        }
      }
      return "not found"
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
        phase: player.phase, help: window.helpOpen, sidebarShown: prefs.sidebar,
        helpColumns: help.columns.map(function(column) {
          return column.map(function(section) { return section.title + " (" + section.items.length + ")" })
        }), searchOpen: window.searchOpen, notice: window.noticeText,
        playingLiked: library.playingLiked, rows: rows,
        artPath: library.artPath, offline: player.offline, sidebar: sidebar.count,
        picker: window.pickerOpen ? window.pickerChoices.length : -1, editable: library.editablePlaylists.length,
        pickerFirst: window.pickerOpen && window.pickerChoices.length > 0
          ? (window.pickerChoices[0].create ? "create: " : "") + window.pickerChoices[0].name : "",
        prompt: window.promptOpen ? window.promptTitle : "", marked: library.markedCount,
        selection: library.markedCount > 0 ? library.selection(-1).map(function(t) { return t.uri }) : [],
        sidebarItem: sidebar.itemAt(sidebar.currentIndex) ? sidebar.itemAt(sidebar.currentIndex).name : "",
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
      visible: prefs.sidebar
      width: visible ? Math.min(Theme.space(280), parent.width * 0.3) : 0
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
          return Faults.title(player.phase) || Faults.title("unavailable")
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
      // A missing or outdated daemon: the command that installs the right one.
      Text {
        visible: Faults.command(player.phase) !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Faults.advice(player.phase) + "\n" + Faults.command(player.phase)
        color: Theme.foreground
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

    // ---- Playlist picker: type to narrow, arrows to move, Enter to add.
    Rectangle {
      visible: window.pickerOpen
      anchors.fill: parent
      color: Theme.alpha(Theme.background, 0.88)
      z: 8

      MouseArea { anchors.fill: parent; onClicked: window.closePicker() }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacing.huge * 4, Theme.space(460))
        height: Math.min(parent.height - Theme.spacing.huge * 4, Theme.space(480))
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
        radius: Theme.spacing.sm

        MouseArea { anchors.fill: parent }

        Column {
          id: pickerHead
          x: Theme.spacing.huge
          y: Theme.spacing.xxl
          width: parent.width - Theme.spacing.huge * 2
          spacing: Theme.spacing.md

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: window.pickerTracks.length === 0 ? ""
              : "Add " + (window.pickerTracks.length === 1 ? "\u201C" + window.pickerTracks[0].title + "\u201D"
                : window.pickerTracks.length + " tracks") + " to\u2026"
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.title
            font.bold: true
          }
          Rectangle {
            width: parent.width
            height: Theme.spacing.rowHeight
            color: Theme.sunken
            radius: Theme.spacing.xs

            TextInput {
              id: pickerFilter
              anchors.verticalCenter: parent.verticalCenter
              x: Theme.spacing.lg
              width: parent.width - Theme.spacing.lg * 2
              clip: true
              color: Theme.foreground
              selectionColor: Theme.selectedFill
              selectedTextColor: Theme.foreground
              font.family: Theme.font.family
              font.pixelSize: Theme.font.body
              onTextEdited: pickerList.currentIndex = 0
              Keys.onEscapePressed: window.closePicker()
              Keys.onReturnPressed: window.confirmPicker()
              Keys.onDownPressed: pickerList.currentIndex = Math.min(pickerList.count - 1, pickerList.currentIndex + 1)
              Keys.onUpPressed: pickerList.currentIndex = Math.max(0, pickerList.currentIndex - 1)
            }
            Text {
              visible: pickerFilter.text === ""
              anchors.verticalCenter: parent.verticalCenter
              x: Theme.spacing.lg
              textFormat: Text.PlainText
              text: "Type to narrow the list, or a name for a new playlist"
              color: Theme.muted
              font.family: Theme.font.family
              font.pixelSize: Theme.font.body
            }
          }
        }

        ListView {
          id: pickerList
          anchors.top: pickerHead.bottom
          anchors.topMargin: Theme.spacing.lg
          anchors.bottom: pickerFoot.top
          anchors.bottomMargin: Theme.spacing.lg
          width: parent.width
          clip: true
          model: window.pickerChoices.length
          boundsBehavior: Flickable.StopAtBounds
          highlightMoveDuration: 0

          delegate: Rectangle {
            id: choice
            required property int index
            readonly property var playlist: window.pickerChoices[index]
            width: pickerList.width
            height: Theme.spacing.rowHeight
            color: ListView.isCurrentItem ? Theme.selectedFill
              : (choiceArea.containsMouse ? Theme.hoverFill : "transparent")

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: Theme.spacing.huge
              width: parent.width - Theme.spacing.huge * 2 - choiceCount.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: !choice.playlist ? "" : (choice.playlist.create
                ? "+ Create \u201C" + choice.playlist.name + "\u201D" : choice.playlist.name)
              color: choice.playlist && choice.playlist.create ? Theme.accent : Theme.foreground
              font.family: Theme.font.family
              font.pixelSize: Theme.font.body
            }
            Text {
              id: choiceCount
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Theme.spacing.huge
              textFormat: Text.PlainText
              text: choice.playlist && !choice.playlist.create && choice.playlist.length !== null
                && choice.playlist.length !== undefined ? String(choice.playlist.length) : ""
              color: Theme.muted
              font.family: Theme.font.family
              font.pixelSize: Theme.font.bodySmall
            }
            MouseArea {
              id: choiceArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                pickerList.currentIndex = choice.index
                window.confirmPicker()
              }
            }
          }
        }

        Text {
          id: pickerFoot
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Theme.spacing.xl
          x: Theme.spacing.huge
          textFormat: Text.PlainText
          text: window.pickerChoices.length === 0 ? "No playlist of yours matches"
            : "\u2191 \u2193 move \u00b7 \u23ce add \u00b7 Esc cancel"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
    }

    // ---- A one-line question
    Rectangle {
      visible: window.promptOpen
      anchors.fill: parent
      color: Theme.alpha(Theme.background, 0.88)
      z: 9

      MouseArea { anchors.fill: parent; onClicked: window.closePrompt() }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacing.huge * 4, Theme.space(460))
        height: promptBody.implicitHeight + Theme.spacing.xxl * 2
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
        radius: Theme.spacing.sm

        MouseArea { anchors.fill: parent }

        Column {
          id: promptBody
          x: Theme.spacing.huge
          y: Theme.spacing.xxl
          width: parent.width - Theme.spacing.huge * 2
          spacing: Theme.spacing.lg

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: window.promptTitle
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.title
            font.bold: true
          }
          Rectangle {
            width: parent.width
            height: Theme.spacing.rowHeight
            color: Theme.sunken
            radius: Theme.spacing.xs

            TextInput {
              id: promptField
              anchors.verticalCenter: parent.verticalCenter
              x: Theme.spacing.lg
              width: parent.width - Theme.spacing.lg * 2
              clip: true
              color: Theme.foreground
              selectionColor: Theme.selectedFill
              selectedTextColor: Theme.foreground
              font.family: Theme.font.family
              font.pixelSize: Theme.font.body
              Keys.onEscapePressed: window.closePrompt()
              Keys.onReturnPressed: window.confirmPrompt()
            }
          }
          Text {
            textFormat: Text.PlainText
            text: "\u23ce confirm \u00b7 Esc cancel"
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }
    }

    // ---- Every key, on demand, in sections. Any key or click closes it.
    Rectangle {
      id: help
      visible: window.helpOpen
      anchors.fill: parent
      color: Theme.alpha(Theme.background, 0.94)
      z: 10

      MouseArea { anchors.fill: parent; onClicked: window.helpOpen = false }

      // As many columns as fit, three at most.
      readonly property int columnCount: Math.max(1, Math.min(3, Math.floor((width - Theme.spacing.huge * 2) / Theme.space(300))))
      readonly property var columns: window.helpOpen ? Keymap.columns(window.scopes, columnCount) : []

      Flickable {
        id: helpScroll
        anchors.fill: parent
        anchors.margins: Theme.spacing.huge
        contentHeight: helpBody.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: helpBody
          width: Math.min(helpScroll.width, Theme.space(1000))
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Theme.spacing.huge

          Row {
            width: parent.width
            Text {
              textFormat: Text.PlainText
              text: "Keyboard"
              color: Theme.foreground
              font.family: Theme.font.family
              font.pixelSize: Theme.font.heading
              font.bold: true
            }
            Text {
              anchors.baseline: parent.children[0].baseline
              leftPadding: Theme.spacing.xxl
              textFormat: Text.PlainText
              text: "press any key to close"
              color: Theme.muted
              font.family: Theme.font.family
              font.pixelSize: Theme.font.bodySmall
            }
          }

          Row {
            id: helpColumns
            width: parent.width
            spacing: Theme.spacing.huge * 2
            readonly property real columnWidth: (width - spacing * (help.columnCount - 1)) / help.columnCount

            Repeater {
              model: help.columns

              Column {
                id: helpColumn
                required property var modelData
                width: helpColumns.columnWidth
                spacing: Theme.spacing.huge

                Repeater {
                  model: helpColumn.modelData

                  // One section: a title, then its keys.
                  Column {
                    id: section
                    required property var modelData
                    width: helpColumn.width
                    spacing: Theme.spacing.md

                    Text {
                      textFormat: Text.PlainText
                      text: section.modelData.title.toUpperCase()
                      color: Theme.accent
                      font.family: Theme.font.family
                      font.pixelSize: Theme.font.caption
                      font.letterSpacing: 1
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.line }

                    Repeater {
                      model: section.modelData.items

                      Row {
                        id: entry
                        required property var modelData
                        width: section.width
                        spacing: Theme.spacing.xl

                        // Every key that does it, right-aligned in a fixed
                        // column so the labels line up.
                        Item {
                          width: Theme.space(92)
                          height: caps.implicitHeight
                          Row {
                            id: caps
                            anchors.right: parent.right
                            spacing: Theme.spacing.xs
                            Repeater {
                              model: entry.modelData.keys
                              KeyCap {
                                required property string modelData
                                label: modelData
                                foreground: Theme.foreground
                                fontFamily: Theme.font.family
                                fontSize: Theme.font.bodySmall
                                padding: Theme.spacing.sm
                              }
                            }
                          }
                        }
                        Text {
                          width: entry.width - Theme.space(92) - entry.spacing
                          anchors.verticalCenter: parent.verticalCenter
                          wrapMode: Text.WordWrap
                          textFormat: Text.PlainText
                          text: entry.modelData.label
                          color: Theme.foreground
                          font.family: Theme.font.family
                          font.pixelSize: Theme.font.body
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
