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
  // For a search place: "spotify" (all of Spotify) or "library" (what the
  // user has), and which kind of result to show:
  // "all" | "songs" | "artists" | "albums" | "playlists".
  property string searchMode: "spotify"
  property string searchFilter: "all"
  readonly property var searchFilters: ["all", "songs", "artists", "albums", "playlists"]
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
    next.push({
      kind: place.kind, uri: place.uri || "", name: place.name || "", query: place.query || "",
      mode: place.mode || "spotify", filter: place.filter || "all", cursor: 0
    })
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
  // later ones update it instead of piling up history. Switching between
  // Spotify and the library is a new place, so Back returns to the other.
  function search(text, mode, cursor) {
    if (kind === "search" && searchMode === mode && historyIndex >= 0) {
      history[historyIndex].query = text
      show(history[historyIndex], false)
    } else {
      go({ kind: "search", query: text, mode: mode, filter: searchFilter }, cursor)
    }
  }

  // Leave a search: back to the last place that was not a search, or to an
  // empty window if searching was the first thing done.
  function leaveSearch(cursor) {
    if (kind !== "search") return
    // Past every search on the way back, so one Esc leaves both the Spotify
    // and the library search.
    for (var i = historyIndex - 1; i >= 0; i--) {
      if (history[i].kind !== "search") {
        history[historyIndex].cursor = cursor
        historyIndex = i
        show(history[i], false)
        return
      }
    }
    leaveCurrent()
    history = []
    historyIndex = -1
    kind = ""
    uri = ""
    name = ""
    subtitle = ""
    query = ""
    rows = []
    total = 0
    revision++
    collection = Loadable.ready(null)
  }

  // Show only one kind of result. Results already fetched are re-used.
  function setSearchFilter(filter) {
    if (searchFilters.indexOf(filter) === -1) return
    searchFilter = filter
    if (kind !== "search" || historyIndex < 0) return
    history[historyIndex].filter = filter
    // Spotify returns more per section when asked for just one.
    if (searchMode === "spotify") show(history[historyIndex], false)
    else composeSearch(query.trim())
    revision++
  }

  function cycleSearchFilter(step) {
    var at = searchFilters.indexOf(searchFilter)
    setSearchFilter(searchFilters[(at + step + searchFilters.length) % searchFilters.length])
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
    if (place.kind === "search") {
      searchMode = place.mode
      searchFilter = place.filter
    }
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

  // ---- Search
  property var searchLocal: []
  property var searchRemote: null
  property string searchError: ""
  property bool searchIndexing: false
  property bool searchPending: false

  // Spotify is asked only once typing pauses.
  Timer {
    id: remoteSearchTimer
    interval: 280
    property string text: ""
    property int forGeneration: 0
    onTriggered: root.fetchSpotifySearch(text, forGeneration)
  }

  function fetchSearch(text) {
    var term = text.trim()
    var where = searchMode === "library" ? "your library" : "Spotify"
    name = term === "" ? "Search " + where : "\u201C" + term + "\u201D in " + where
    searchLocal = []
    searchRemote = null
    searchError = ""
    searchPending = false
    remoteSearchTimer.stop()

    if (searchMode === "library") {
      load("library.search", { query: text, limit: 300 }, 3000, function(data) {
        searchLocal = data.items
        searchIndexing = data.indexing
        composeSearch(term)
      })
      return
    }
    if (term.length >= 2) {
      searchPending = true
      remoteSearchTimer.text = term
      remoteSearchTimer.forGeneration = generation
      remoteSearchTimer.restart()
    }
    composeSearch(term)
    collection = Loadable.ready(true)
    revision++
  }

  function fetchSpotifySearch(term, forGeneration) {
    if (forGeneration !== generation) return
    // One kind of result: ask for as many as the service gives at once.
    var handle = player.request("search", { query: term, limit: searchFilter === "all" ? 10 : 50 }, {
      deadline: 8000,
      onDone: function(result) {
        if (forGeneration !== root.generation) return
        if (result.ok) root.searchRemote = result.data
        else if (result.error.code === "cancelled") return
        else root.searchError = result.error.message
        root.searchPending = false
        root.composeSearch(term)
        root.revision++
        if (root.restoreCursor >= 0) {
          root.cursorRestoreRequested(root.restoreCursor)
          root.restoreCursor = -1
        }
      }
    })
    inFlight.push(handle)
  }

  function matchesTerm(text, term) {
    var words = term.toLowerCase().split(/\s+/)
    var hay = String(text).toLowerCase()
    for (var i = 0; i < words.length; i++) if (words[i] !== "" && hay.indexOf(words[i]) === -1) return false
    return true
  }

  // What the library knows, as the same four sections Spotify returns.
  // Artists and albums are the ones named by matching tracks; playlists are
  // matched by name.
  function librarySections(term) {
    var out = { tracks: searchLocal, artists: [], albums: [], playlists: [] }
    var seenArtists = {}, seenAlbums = {}
    for (var i = 0; i < searchLocal.length; i++) {
      var row = searchLocal[i]
      for (var a = 0; a < row.artists.length; a++) {
        var artistUri = row.artist_uris ? row.artist_uris[a] : undefined
        if (artistUri && !seenArtists[artistUri] && matchesTerm(row.artists[a], term)) {
          seenArtists[artistUri] = true
          out.artists.push({ uri: artistUri, name: row.artists[a] })
        }
      }
      if (row.album_uri && !seenAlbums[row.album_uri] && matchesTerm(row.album, term)) {
        seenAlbums[row.album_uri] = true
        out.albums.push({ uri: row.album_uri, name: row.album, artists: row.artists })
      }
    }
    var lists = Loadable.hasData(playlists) ? playlists.data : []
    for (var p = 0; p < lists.length; p++) {
      if (matchesTerm(lists[p].name, term)) out.playlists.push({ uri: lists[p].uri, name: lists[p].name, owner: "" })
    }
    return out
  }

  // The rows for the current mode and filter, sections under headings.
  function composeSearch(term) {
    var library = searchMode === "library"
    var found = term === "" ? null : (library ? librarySections(term) : searchRemote)
    var out = []
    var only = searchFilter
    var counts = { songs: 0, artists: 0, albums: 0, playlists: 0 }

    function section(key, title, list, make) {
      counts[key] = list.length
      if ((only !== "all" && only !== key) || list.length === 0) return
      // A single kind needs no heading.
      if (only === "all") out.push({ kind: "heading", title: title })
      for (var i = 0; i < list.length; i++) out.push(make(list[i]))
    }
    if (found) {
      section("songs", "Songs", found.tracks, function(t) { return t })
      section("artists", "Artists", found.artists, function(a) {
        return { kind: "artist", uri: a.uri, title: a.name }
      })
      section("albums", "Albums", found.albums, function(a) {
        return { kind: "album", uri: a.uri, title: a.name, year: a.year, by: a.artists.join(", ") }
      })
      section("playlists", "Playlists", found.playlists, function(p) {
        return { kind: "playlist", uri: p.uri, title: p.name, by: p.owner }
      })
    }
    rows = out
    total = out.length

    if (term === "") {
      subtitle = library ? "Type to search your liked songs and everything you have opened"
        : "Type to search all of Spotify"
    } else if (searchError !== "") {
      subtitle = "Spotify search failed: " + searchError
    } else if (searchPending) {
      subtitle = "Searching Spotify…"
    } else if (!library && term.length < 2) {
      subtitle = "Keep typing…"
    } else {
      var shown = only === "all"
        ? count(counts.songs, "song", "songs") + " · " + count(counts.artists, "artist", "artists")
          + " · " + count(counts.albums, "album", "albums") + " · " + count(counts.playlists, "playlist", "playlists")
        : count(total, only.slice(0, -1), only)
      subtitle = shown + (library && searchIndexing ? " · still indexing your liked songs" : "")
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
