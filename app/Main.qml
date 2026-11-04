import QtQuick
import Quickshell
import Quickshell.Io

import "../common"
import "../common/Keymap.js" as Keymap
import "../common/Faults.js" as Faults
import "../common/Links.js" as Links
import "../common/Visuals.js" as Visuals

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
    // The daemon analyses the audio only while the plate shows it.
    vizWanted: plate.visible && window.visible && screen.shown && player.playing && Visuals.moving(window.visuals)
  }

  Library {
    id: library
    player: player
  }

  // On a workspace being shown; the creature only moves then.
  OnScreen { id: screen }

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
    if (pendingLink !== "") {
      var link = pendingLink
      pendingLink = ""
      openLink(link)
    }
  }
  Component.onCompleted: loadWhenReady()

  // A Spotify link to show: given when the app was started for one
  // (SPORETIFY_OPEN, set by bin/sporetify), or over IPC while it runs.
  property string pendingLink: Quickshell.env("SPORETIFY_OPEN") || ""
  function openLink(text) {
    var link = Links.parse(text)
    if (!link) return "not a Spotify link Sporetify can open"
    if (loadedIn === "") {
      pendingLink = text
      return "opening " + link.uri + " once connected"
    }
    if (link.kind !== "track") {
      library.go({ kind: link.kind, uri: link.uri }, tracks.currentIndex)
      pane = "list"
      return "opened " + link.uri
    }
    // A track is shown in its album.
    player.request("library.track", { uri: link.uri }, {
      deadline: 5000, scope: "open-link",
      onDone: function(result) {
        var row = result.ok ? result.data.track : null
        if (!row || !row.album_uri) {
          library.notice("Could not open that track" + (result.ok ? "" : ": " + result.error.message), true)
          return
        }
        library.go({ kind: "album", uri: row.album_uri, name: row.album }, tracks.currentIndex)
        window.pane = "list"
      }
    })
    return "opening " + link.uri
  }

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
      // full | reduced | off; see common/Visuals.js.
      property string visuals: ""
      // Draw creatures at all, here and in the compact player, the bar and
      // the mini-player (which read this file).
      property bool creatures: true
      // Show covers on the rows of lists.
      property bool covers: true
      property bool sidebar: true
      // The specimen plate on the right (when the window is wide enough).
      property bool plate: true
      onSidebarChanged: if (!sidebar) window.pane = "list"
      // Ids of sidebar folders that are folded shut, comma separated.
      property string foldedFolders: ""
    }
  }

  readonly property string visuals: Visuals.level(prefs.visuals)

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
    searchBar.grab()
    if (!library.searching || library.searchMode !== mode) {
      library.search(searchBar.text, mode, tracks.currentIndex)
    }
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
  readonly property var pickerChoices: picker.choices
  function openPicker(index) {
    var tracks = library.selection(index)
    if (tracks.length === 0) return
    pickerTracks = tracks
    pickerOpen = true
    picker.reset()
  }
  function closePicker() {
    pickerOpen = false
    keys.forceActiveFocus()
  }
  function confirmPicker() {
    var choice = pickerChoices[picker.currentIndex]
    if (choice && pickerTracks.length > 0) {
      if (choice.create) library.createPlaylist(choice.name, pickerTracks)
      else library.addToPlaylist(choice, pickerTracks)
    }
    closePicker()
  }

  // ---- Asking for a line of text (a new playlist's name, a new name)
  property bool promptOpen: false
  property string promptEyebrow: ""
  property string promptTitle: ""
  property var promptAccept: null
  function ask(eyebrow, title, initial, accept) {
    promptEyebrow = eyebrow
    promptTitle = title
    promptAccept = accept
    prompt.text = initial
    promptOpen = true
    prompt.grab()
  }
  function closePrompt() {
    promptOpen = false
    promptAccept = null
    keys.forceActiveFocus()
  }
  function confirmPrompt() {
    var text = prompt.text.trim()
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
      ask("New playlist", "Name the new playlist", "", function(name) { library.createPlaylist(name, []) })
      return
    case "rename":
      var playlist = targetPlaylist()
      if (!playlist || playlist.editable !== true) {
        library.notice("Move to one of your own playlists to rename it", true)
        return
      }
      ask("Rename playlist", "Rename " + playlist.name, playlist.name, function(name) { library.renamePlaylist(playlist.uri, name) })
      return
    case "enqueue": library.enqueue(pane === "list" ? tracks.currentIndex : -1); return
    case "artist":
    case "album":
      // From the sidebar there is no row under the cursor, so it means the playing track.
      library.openRelated(action, pane === "list" ? tracks.currentIndex : -1)
      pane = "list"
      return
    case "visuals":
      prefs.visuals = Visuals.next(visuals)
      library.notice("Visuals: " + prefs.visuals, false)
      return
    case "creatures":
      prefs.creatures = !prefs.creatures
      library.notice("Creatures " + (prefs.creatures ? "on" : "off") + ", everywhere", false)
      return
    case "covers": prefs.covers = !prefs.covers; return
    case "plate":
      if (!plate.room) {
        library.notice("The window is too narrow for the specimen plate", true)
        return
      }
      prefs.plate = !prefs.plate
      return
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
      // Like a key press: an open help overlay takes it (scrolls or closes).
      if (window.helpOpen) {
        if (!help.scroll(action)) window.helpOpen = false
        return "ok"
      }
      window.act(action)
      return "ok"
    }
    function searchFor(text: string): string { return search(text, "spotify") }
    function searchLibrary(text: string): string { return search(text, "library") }
    function search(text: string, mode: string): string {
      searchBar.text = text
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
        prompt.text = text
        window.confirmPrompt()
        return "prompt"
      }
      if (window.pickerOpen) {
        picker.text = text
        // The playlist of exactly this name if there is one, else the first row.
        var at = 0
        for (var i = 0; i < window.pickerChoices.length; i++) {
          if (!window.pickerChoices[i].create && window.pickerChoices[i].name === text) at = i
        }
        picker.currentIndex = at
        var chosen = window.pickerChoices[at]
        window.confirmPicker()
        return chosen ? (chosen.create ? "created " : "added to ") + chosen.name : "nothing to pick"
      }
      return "nothing open"
    }
    // Show a Spotify link (spotify:album:..., https://open.spotify.com/...).
    function open(link: string): string { return window.openLink(link) }
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
    // Save a picture of the window as PNG. For tests; runs offscreen too
    // (QT_QPA_PLATFORM=offscreen). Areas the window colour fills come out
    // transparent: flatten onto the theme's background to view.
    function capture(path: string): string {
      keys.grabToImage(function(result) { result.saveToFile(path) })
      return "ok"
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
        helpScroll: Math.round(help.scrollY), helpScrollable: help.scrollable,
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
        plate: plate.visible, viz: player.vizOn, creatures: prefs.creatures,
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

    // Under everything, so pictures taken with `capture` have it too.
    Rectangle { anchors.fill: parent; color: Theme.background }

    Keys.onPressed: function(event) {
      // The help overlay swallows every key: the moving keys scroll it when
      // it does not fit, any other key closes it.
      if (window.helpOpen) {
        event.accepted = true
        var moving = Keymap.actionFor(event.key, event.text, ["browse"], event.modifiers)
        if (!help.scroll(moving)) window.helpOpen = false
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

    SearchBar {
      id: searchBar
      visible: window.searchOpen && player.scope === "player"
      anchors.top: parent.top
      anchors.left: sidebar.right
      anchors.right: parent.right
      library: library
      cursor: tracks.currentIndex
      onCancelled: window.cancelSearch()
      onFinished: window.leaveSearchField()
      onSwitchTo: function(mode) { window.openSearch(mode) }
    }

    TrackList {
      id: tracks
      anchors.top: searchBar.bottom
      anchors.bottom: nowPlaying.top
      anchors.left: sidebar.right
      anchors.right: plate.left
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
      color: Theme.raised
      border.width: Theme.stroke.hair
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

    // ---- The playing track as a specimen, when there is room and visuals are on.
    SpecimenPlate {
      id: plate
      // Wide enough that the list keeps most of the window.
      readonly property bool room: window.width >= Theme.space(1000)
      visible: room && prefs.plate && Visuals.drawn(window.visuals) && player.scope === "player"
      anchors.top: searchBar.bottom
      anchors.bottom: nowPlaying.top
      anchors.right: parent.right
      width: visible ? Theme.space(260) : 0
      player: player
      moving: Visuals.moving(window.visuals)
      creatures: prefs.creatures
      live: window.visible && screen.shown
    }

    NowPlayingBar {
      id: nowPlaying
      anchors.bottom: hints.top
      width: parent.width
      player: player
      live: window.visible && screen.shown
      visuals: Visuals.drawn(window.visuals) && prefs.creatures
      motion: Visuals.moving(window.visuals)
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
        corner: 0
      }
    }

    PlaylistPicker {
      id: picker
      visible: window.pickerOpen
      z: 8
      playlists: library.editablePlaylists
      tracks: window.pickerTracks
      onConfirmed: window.confirmPicker()
      onCancelled: window.closePicker()
    }

    Prompt {
      id: prompt
      visible: window.promptOpen
      z: 9
      eyebrow: window.promptEyebrow
      title: window.promptTitle
      onConfirmed: window.confirmPrompt()
      onCancelled: window.closePrompt()
    }

    HelpOverlay {
      id: help
      z: 10
      open: window.helpOpen
      scopes: window.scopes
      onCloseRequested: window.helpOpen = false
    }
  }
}
