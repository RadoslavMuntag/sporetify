import QtQuick

import "../common/Loadable.js" as Loadable
import "../common/Pages.js" as Pages

// What the app is showing, and how it got there.
//
// One "place" is on screen at a time: a playlist, search results, an album,
// an artist or the up-next list. Every place ends up as a flat list of rows
// for TrackList. Places form a history that can be walked back and forward.
//
// A place is { kind, uri, name, query }; kind is one of
// "playlist" | "search" | "album" | "artist" | "queue".
Item {
  id: root

  // The shared Player (connection + actions).
  required property var player

  readonly property int pageSize: 50

  // Loadable holding [{ uri, name, length }].
  property var playlists: Loadable.loading(null)

  // ---- The place on screen
  property string kind: ""
  property string uri: ""
  property string name: ""
  property string query: ""
  // Line under the title: counts, or whatever explains the place.
  property string subtitle: ""
  property int total: 0
  // rows[i] is a row once it is known. A row is a track, or has a `kind`:
  // "heading" (a section label) or "album" (opens that album).
  property var rows: []
  // Bumped whenever rows change, so delegates re-read their row.
  property int revision: 0
  // Loadable for the place as a whole.
  property var collection: Loadable.ready(null)
  readonly property bool searching: kind === "search"

  // ---- History
  property var history: []
  property int historyIndex: -1
  readonly property bool canGoBack: historyIndex > 0
  readonly property bool canGoForward: historyIndex >= 0 && historyIndex < history.length - 1
  // Where the cursor should land once rows arrive (set when walking history).
  property int restoreCursor: -1
  signal cursorRestoreRequested(int index)

  // Whether the playing track is in Liked Songs.
  property bool playingLiked: false
  // Something worth telling the user once ("Added to queue", a failure).
  signal notice(string text, bool isError)

  property var pages: Pages.create(pageSize)
  // Requests of the current place, cancelled when another one opens.
  property var inFlight: []
  property int generation: 0

  visible: false

  function loadPlaylists() {
    playlists = Loadable.loading(playlists)
    player.request("library.playlists", {}, {
      deadline: 8000,
      scope: "playlists",
      onDone: function(result) {
        root.playlists = Loadable.withResult(root.playlists, result.ok
          ? { ok: true, data: result.data.items } : result)
      }
    })
  }

  // ---- Navigation

  // Go somewhere new. `cursor` is where the cursor is now, remembered so
  // that coming back lands on the same row.
  function go(place, cursor) {
    if (historyIndex >= 0 && cursor !== undefined) history[historyIndex].cursor = cursor
    var next = history.slice(0, historyIndex + 1)
    next.push({ kind: place.kind, uri: place.uri || "", name: place.name || "", query: place.query || "", cursor: 0 })
    history = next
    historyIndex = next.length - 1
    show(next[historyIndex], false)
  }

  function back(cursor) {
    if (!canGoBack) return
    history[historyIndex].cursor = cursor
    historyIndex--
    show(history[historyIndex], false)
  }

  function forward(cursor) {
    if (!canGoForward) return
    history[historyIndex].cursor = cursor
    historyIndex++
    show(history[historyIndex], false)
  }

  function reload() {
    if (historyIndex >= 0) show(history[historyIndex], true)
    loadPlaylists()
  }

  // Search as the user types: the first keystroke opens a search place,
  // later ones update it instead of piling up history.
  function search(text, cursor) {
    if (kind === "search" && historyIndex >= 0) {
      history[historyIndex].query = text
      show(history[historyIndex], false)
    } else {
      go({ kind: "search", query: text }, cursor)
    }
  }

  function leaveCurrent() {
    for (var i = 0; i < inFlight.length; i++) inFlight[i].cancel()
    inFlight = []
    generation++
    pages.reset()
  }

  function show(place, refresh) {
    leaveCurrent()
    kind = place.kind
    uri = place.uri
    query = place.query
    name = place.name
    subtitle = ""
    total = 0
    rows = []
    revision++
    restoreCursor = place.cursor || 0
    collection = Loadable.loading(null)

    switch (place.kind) {
    case "playlist": fetchPage(0, refresh === true); break
    case "search": fetchSearch(place.query); break
    case "album": fetchAlbum(place.uri); break
    case "artist": fetchArtist(place.uri); break
    case "queue": fetchQueue(); break
    }
  }

  // Runs `apply(data)` when `op` answers, unless the place has changed.
  function load(op, args, deadline, apply) {
    var forGeneration = generation
    var handle = player.request(op, args, {
      deadline: deadline,
      onDone: function(result) {
        if (forGeneration !== root.generation) return
        if (!result.ok) {
          if (result.error.code !== "cancelled") root.collection = Loadable.withResult(root.collection, result)
          return
        }
        apply(result.data)
        root.revision++
        root.collection = Loadable.ready(true)
        if (root.restoreCursor >= 0) {
          root.cursorRestoreRequested(root.restoreCursor)
          root.restoreCursor = -1
        }
      }
    })
    inFlight.push(handle)
  }

  function count(n, one, many) {
    return n + " " + (n === 1 ? one : many)
  }

  // ---- Search: the library answers at once, Spotify a moment later.
  property var searchLocal: []
  property var searchRemote: null
  property string searchRemoteError: ""
  property bool searchIndexing: false
  property int searchLocalTotal: 0

  // Spotify is asked only once typing pauses; the library on every key.
  Timer {
    id: remoteSearchTimer
    interval: 280
    property string text: ""
    property int forGeneration: 0
    onTriggered: root.fetchSpotifySearch(text, forGeneration)
  }

  function fetchSearch(text) {
    var term = text.trim()
    name = term === "" ? "Search" : "Results for \u201C" + term + "\u201D"
    searchLocal = []
    searchRemote = null
    searchRemoteError = ""
    remoteSearchTimer.stop()

    load("library.search", { query: text, limit: 50 }, 3000, function(data) {
      searchLocal = data.items
      searchLocalTotal = data.total
      searchIndexing = data.indexing
      composeSearch(term)
    })
    if (term.length >= 2) {
      remoteSearchTimer.text = term
      remoteSearchTimer.forGeneration = generation
      remoteSearchTimer.restart()
    }
  }

  function fetchSpotifySearch(term, forGeneration) {
    if (forGeneration !== generation) return
    var handle = player.request("search", { query: term, limit: 20 }, {
      deadline: 8000,
      onDone: function(result) {
        if (forGeneration !== root.generation) return
        if (result.ok) root.searchRemote = result.data
        else if (result.error.code !== "cancelled") root.searchRemoteError = result.error.message
        root.composeSearch(term)
        root.revision++
      }
    })
    inFlight.push(handle)
  }

  // One list: what the library has, then Spotify's songs, artists, albums
  // and playlists, each under a heading.
  function composeSearch(term) {
    var out = []
    var i
    if (searchLocal.length > 0) {
      out.push({ kind: "heading", title: "In your library" })
      for (i = 0; i < searchLocal.length; i++) out.push(searchLocal[i])
    }
    var remote = searchRemote
    if (remote) {
      // Songs already listed from the library are not repeated.
      var have = {}
      for (i = 0; i < searchLocal.length; i++) have[searchLocal[i].uri] = true
      var songs = remote.tracks.filter(function(t) { return !have[t.uri] })
      if (songs.length > 0) {
        out.push({ kind: "heading", title: "Songs" })
        for (i = 0; i < songs.length; i++) out.push(songs[i])
      }
      if (remote.artists.length > 0) {
        out.push({ kind: "heading", title: "Artists" })
        for (i = 0; i < remote.artists.length; i++)
          out.push({ kind: "artist", uri: remote.artists[i].uri, title: remote.artists[i].name })
      }
      if (remote.albums.length > 0) {
        out.push({ kind: "heading", title: "Albums" })
        for (i = 0; i < remote.albums.length; i++) {
          var album = remote.albums[i]
          out.push({ kind: "album", uri: album.uri, title: album.name, year: album.year, by: album.artists.join(", ") })
        }
      }
      if (remote.playlists.length > 0) {
        out.push({ kind: "heading", title: "Playlists" })
        for (i = 0; i < remote.playlists.length; i++) {
          var playlist = remote.playlists[i]
          out.push({ kind: "playlist", uri: playlist.uri, title: playlist.name, by: playlist.owner })
        }
      }
    }
    rows = out
    total = out.length

    if (term === "") {
      subtitle = "Type to search your library and all of Spotify"
    } else if (searchRemoteError !== "") {
      subtitle = count(searchLocalTotal, "match", "matches") + " in your library · Spotify search failed: " + searchRemoteError
    } else if (!remote && term.length >= 2) {
      subtitle = count(searchLocalTotal, "match", "matches") + " in your library · searching Spotify…"
    } else {
      subtitle = count(searchLocalTotal, "match", "matches") + " in your library"
        + (searchIndexing ? " (still indexing)" : "")
    }
  }

  function fetchAlbum(albumUri) {
    load("browse.album", { uri: albumUri }, 8000, function(data) {
      name = data.album.name
      rows = data.items
      total = rows.length
      subtitle = (data.album.kind === "album" ? "Album" : data.album.kind.toUpperCase().charAt(0) + data.album.kind.slice(1))
        + " · " + data.album.artists.join(", ") + " · " + data.album.year + " · " + count(total, "track", "tracks")
    })
  }

  function fetchArtist(artistUri) {
    load("browse.artist", { uri: artistUri }, 10000, function(data) {
      name = data.artist.name
      var out = []
      function albumRows(list) {
        for (var i = 0; i < list.length; i++) {
          out.push({ kind: "album", uri: list[i].uri, title: list[i].name, year: list[i].year, tracks: list[i].tracks })
        }
      }
      if (data.top_tracks.length > 0) {
        out.push({ kind: "heading", title: "Popular" })
        for (var i = 0; i < data.top_tracks.length; i++) out.push(data.top_tracks[i])
      }
      if (data.albums.length > 0) {
        out.push({ kind: "heading", title: "Albums" })
        albumRows(data.albums)
      }
      if (data.singles.length > 0) {
        out.push({ kind: "heading", title: "Singles and EPs" })
        albumRows(data.singles)
      }
      rows = out
      total = out.length
      subtitle = "Artist · " + count(data.albums.length, "album", "albums")
        + " · " + count(data.singles.length, "single", "singles")
    })
  }

  function fetchQueue() {
    name = "Up next"
    load("player.up_next", { limit: 100 }, 8000, function(data) {
      rows = data.items
      total = rows.length
      if (!data.context_uri) {
        subtitle = total > 0 ? "Queued from here" : "Nothing has been played from this app yet"
      } else {
        // Remembered so a row here plays inside the same list.
        uri = data.context_uri
        subtitle = "From " + data.context_name
          + (data.shuffle ? " · shuffle is on, so the real order will differ" : "")
          + (total === 0 ? " · this is the last track" : "")
      }
    })
  }

  // Playlists arrive a page at a time, for whatever is on screen.
  function ensure(first, last) {
    if (kind !== "playlist" || total === 0) return
    var wanted = pages.claim(first, last, total)
    for (var i = 0; i < wanted.length; i++) fetchPage(wanted[i], false)
  }

  function fetchPage(page, refresh) {
    var forGeneration = generation
    if (page === 0) pages.claim(0, 0, 1)
    var handle = player.request("library.tracks", {
      uri: uri, offset: page * pageSize, limit: pageSize, refresh: refresh
    }, {
      deadline: 8000,
      onDone: function(result) {
        // An answer for a place that is no longer on screen is dropped.
        if (forGeneration !== root.generation) return
        if (!result.ok) {
          root.pages.failed(page)
          if (page === 0 && result.error.code !== "cancelled")
            root.collection = Loadable.withResult(root.collection, result)
          return
        }
        var data = result.data
        var rows = root.rows
        if (rows.length !== data.total) {
          rows = new Array(data.total)
          for (var i = 0; i < root.rows.length && i < data.total; i++) rows[i] = root.rows[i]
        }
        for (var j = 0; j < data.items.length; j++) rows[data.offset + j] = data.items[j]
        root.rows = rows
        root.total = data.total
        if (data.name) root.name = data.name
        root.subtitle = root.count(data.total, "track", "tracks")
        root.pages.done(page)
        root.revision++
        if (page === 0) {
          root.collection = Loadable.ready(true)
          if (root.restoreCursor >= 0) {
            root.cursorRestoreRequested(root.restoreCursor)
            root.restoreCursor = -1
          }
        }
      }
    })
    inFlight.push(handle)
  }

  function rowAt(index) {
    return index >= 0 && index < rows.length ? (rows[index] || null) : null
  }

  function isTrack(row) {
    return row !== null && row.kind === undefined
  }

  // Enter on a row: play a track where it was found, or open an album.
  function activate(index) {
    var row = rowAt(index)
    if (!row) return
    if (row.kind === "album" || row.kind === "artist" || row.kind === "playlist") {
      go({ kind: row.kind, uri: row.uri, name: row.title }, index)
    } else if (isTrack(row) && row.available) {
      // A search result plays inside the list it was found in, or inside
      // its album when it came from Spotify; everything else plays inside
      // the place on screen.
      var context = kind === "search" ? (row.context_uri || row.album_uri) : uri
      player.playContext(context, row.uri)
    }
  }

  // Open the artist or album of the row under the cursor, or of the
  // playing track when the cursor is not on a track.
  function openRelated(what, index) {
    var row = rowAt(index)
    if (isTrack(row)) {
      openFromRow(what, row, index)
      return
    }
    if (!player.track) return
    var cursor = index
    player.request("library.track", { uri: player.track.id }, {
      deadline: 5000,
      scope: "related",
      onDone: function(result) {
        if (result.ok) root.openFromRow(what, result.data.track, cursor)
      }
    })
  }

  function openFromRow(what, row, cursor) {
    if (what === "artist" && row.artist_uris && row.artist_uris.length > 0)
      go({ kind: "artist", uri: row.artist_uris[0], name: row.artists[0] }, cursor)
    else if (what === "album" && row.album_uri)
      go({ kind: "album", uri: row.album_uri, name: row.album }, cursor)
  }

  // ---- Liking and queueing

  // The track that like and queue act on. `index` is the cursor row when
  // the list has focus: it must be a track, there is no falling back to
  // something else the user is not looking at. `index` -1 (the sidebar has
  // focus, or the now-playing heart was clicked) means the playing track.
  // Returns { uri, title, liked, playing } or null.
  function subject(index) {
    if (index < 0) {
      return player.track
        ? { uri: player.track.id, title: player.track.title, liked: playingLiked, playing: true } : null
    }
    var row = rowAt(index)
    if (isTrack(row) && row.available) return { uri: row.uri, title: row.title, liked: row.liked === true, playing: false }
    return null
  }

  function subjectOrExplain(index) {
    var track = subject(index)
    if (!track) notice(index < 0 ? "Nothing is playing" : "Move to a track first", true)
    return track
  }

  // Show a row's new liked state. Rows are replaced, not edited, so the
  // delegates notice.
  function markLiked(uri, liked) {
    var changed = false
    var next = rows.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i] && next[i].uri === uri && next[i].kind === undefined && next[i].liked !== liked) {
        var copy = {}
        for (var key in next[i]) copy[key] = next[i][key]
        copy.liked = liked
        next[i] = copy
        changed = true
      }
    }
    if (changed) {
      rows = next
      revision++
    }
    if (player.track && player.track.id === uri) playingLiked = liked
  }

  function toggleLike(index) {
    var track = subjectOrExplain(index)
    if (!track) return
    var want = !track.liked
    // Shown at once; put back if Spotify refuses.
    markLiked(track.uri, want)
    player.request(want ? "library.save" : "library.unsave", { uri: track.uri }, {
      deadline: 5000,
      onDone: function(result) {
        if (result.ok) {
          root.notice((want ? "Liked " : "Removed from Liked Songs: ") + track.title, false)
        } else {
          root.markLiked(track.uri, !want)
          root.notice(result.error.message, true)
        }
      }
    })
  }

  function enqueue(index) {
    var track = subjectOrExplain(index)
    if (!track) return
    player.request("player.queue_add", { uri: track.uri }, {
      deadline: 5000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        root.notice("Queued " + track.title, false)
        if (root.kind === "queue" && root.historyIndex >= 0) root.show(root.history[root.historyIndex], false)
      }
    })
  }

  function refreshPlayingLiked() {
    if (!player.track) {
      playingLiked = false
      return
    }
    var uri = player.track.id
    player.request("library.is_saved", { uri: uri }, {
      deadline: 5000,
      scope: "playing-liked",
      onDone: function(result) {
        if (result.ok && root.player.track && root.player.track.id === uri) root.playingLiked = result.data.liked
      }
    })
  }

  // Up next follows the music. The track object is replaced on every player
  // event, so compare ids rather than reacting to each one.
  property string lastTrackId: ""
  Connections {
    target: root.player
    function onTrackChanged() {
      var id = root.player.track ? root.player.track.id : ""
      if (id === root.lastTrackId) return
      root.lastTrackId = id
      root.refreshPlayingLiked()
      if (root.kind === "queue" && root.historyIndex >= 0) root.show(root.history[root.historyIndex], false)
    }
  }
}
