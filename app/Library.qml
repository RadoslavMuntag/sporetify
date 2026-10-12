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
  // Local file of the album cover or artist portrait for this place, or "".
  property string artPath: ""
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

  // Whether the playing track is in Liked Songs; kept by the shared player.
  readonly property bool playingLiked: player.playingLiked
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
    // Covers still waiting belong to rows that are about to disappear.
    for (var q = 0; q < artQueue.length; q++) delete artPaths[artQueue[q]]
    artQueue = []
    generation++
    pages.reset()
    // A selection belongs to the place it was made in.
    marked = {}
    markedCount = 0
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
    artPath = ""
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
    case "foryou": fetchForYou(refresh === true); break
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

  // ---- Thumbnails for rows
  // Address -> local file, or "" while it is being fetched or if it failed.
  property var artPaths: ({})
  // Bumped when a thumbnail arrives, so rows re-read theirs.
  property int artRevision: 0
  property var artQueue: []
  property int artInFlight: 0

  function artAddress(row) {
    return row ? (row.art_url || row.thumb_url || "") : ""
  }

  // The local file of a row's cover, or "" if it is not there (yet).
  function artFor(row) {
    if (!row) return ""
    if (row.art_path) return row.art_path
    var known = artPaths[artAddress(row)]
    return known ? known : ""
  }

  // Ask for a cover. A few are fetched at a time; the rest wait their turn.
  function wantArt(url) {
    if (!url || artPaths[url] !== undefined) return
    artPaths[url] = ""
    artQueue.push(url)
    pumpArt()
  }

  function pumpArt() {
    while (artInFlight < 4 && artQueue.length > 0) {
      fetchArt(artQueue.shift())
    }
  }

  function fetchArt(url) {
    artInFlight++
    player.request("art.get", { url: url }, {
      deadline: 8000,
      onDone: function(result) {
        root.artInFlight--
        if (result.ok) {
          root.artPaths[url] = result.data.path
          root.artRevision++
        }
        root.pumpArt()
      }
    })
  }

  // Ask the daemon for a cover as a local file, for the place on screen.
  function loadArt(url) {
    if (!url) return
    var forGeneration = generation
    var handle = player.request("art.get", { url: url }, {
      deadline: 8000,
      onDone: function(result) {
        if (result.ok && forGeneration === root.generation) root.artPath = result.data.path
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
      if (lists[p].kind !== "folder" && matchesTerm(lists[p].name, term)) out.playlists.push({ uri: lists[p].uri, name: lists[p].name, owner: "" })
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
        return { kind: "artist", uri: a.uri, title: a.name, art_url: a.art_url }
      })
      section("albums", "Albums", found.albums, function(a) {
        return { kind: "album", uri: a.uri, title: a.name, year: a.year, by: a.artists.join(", "), art_url: a.art_url }
      })
      section("playlists", "Playlists", found.playlists, function(p) {
        return { kind: "playlist", uri: p.uri, title: p.name, by: p.owner, art_url: p.art_url }
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
      loadArt(data.album.art_url)
      rows = data.items
      total = rows.length
      subtitle = (data.album.kind === "album" ? "Album" : data.album.kind.toUpperCase().charAt(0) + data.album.kind.slice(1))
        + " · " + data.album.artists.join(", ") + " · " + data.album.year + " · " + count(total, "track", "tracks")
    })
  }

  function fetchArtist(artistUri) {
    load("browse.artist", { uri: artistUri }, 10000, function(data) {
      name = data.artist.name
      loadArt(data.artist.art_url)
      var out = []
      function albumRows(list) {
        for (var i = 0; i < list.length; i++) {
          out.push({
            kind: "album", uri: list[i].uri, title: list[i].name, year: list[i].year,
            tracks: list[i].tracks, art_url: list[i].thumb_url
          })
        }
      }
      // Spotify's own playlists for the artist, when it has them.
      var own = []
      if (data.this_is) own.push({ kind: "playlist", uri: data.this_is.uri, title: data.this_is.name,
        by: "The essentials, by Spotify", art_url: data.this_is.art_url })
      if (data.radio) own.push({ kind: "playlist", uri: data.radio.uri, title: data.radio.name,
        by: "Songs like theirs, by Spotify", art_url: data.radio.art_url })
      if (own.length > 0) {
        out.push({ kind: "heading", title: "Start here" })
        for (var o = 0; o < own.length; o++) out.push(own[o])
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

  // The playlists Spotify makes for this user.
  function fetchForYou(refresh) {
    name = "For you"
    load("library.made_for_you", { refresh: refresh }, 15000, function(data) {
      var out = []
      for (var i = 0; i < data.items.length; i++) {
        var playlist = data.items[i]
        out.push({ kind: "playlist", uri: playlist.uri, title: playlist.name, by: "Made for you", art_url: playlist.art_url })
      }
      rows = out
      total = out.length
      subtitle = count(total, "playlist", "playlists") + " from Spotify, made for you"
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
        if (page === 0 && data.art_url && root.artPath === "") root.loadArt(data.art_url)
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
    if (player.track && player.track.id === uri) player.playingLiked = liked
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

  // ---- Selecting several tracks
  // uri -> title of the tracks marked in the place on screen.
  property var marked: ({})
  property int markedCount: 0

  function isMarked(row) {
    return !!row && row.kind === undefined && marked[row.uri] !== undefined
  }

  // Mark or unmark the track at `index`. Returns false if it is not a track.
  function toggleMark(index) {
    var row = rowAt(index)
    if (!isTrack(row) || !row.available) {
      notice("Move to a track first", true)
      return false
    }
    var next = {}
    for (var key in marked) if (key !== row.uri) next[key] = marked[key]
    if (marked[row.uri] === undefined) next[row.uri] = row.title
    marked = next
    markedCount = Object.keys(next).length
    revision++
    return true
  }

  function clearMarks() {
    if (markedCount === 0) return
    marked = {}
    markedCount = 0
    revision++
  }

  // What an action on "the selection" applies to: the marked tracks, in the
  // order they appear, or failing that the one track `subject` gives.
  // Returns [{ uri, title }], empty when there is nothing to act on.
  function selection(index) {
    if (markedCount > 0) {
      var out = []
      for (var i = 0; i < rows.length; i++) if (isMarked(rows[i])) out.push({ uri: rows[i].uri, title: rows[i].title })
      // Marked rows whose page has since been dropped still count.
      if (out.length > 0) return out
    }
    var one = subjectOrExplain(index)
    return one ? [{ uri: one.uri, title: one.title }] : []
  }

  function describeTracks(tracks) {
    return tracks.length === 1 ? tracks[0].title : tracks.length + " tracks"
  }

  // ---- Playlists the user can change

  // [{ uri, name, length }] of the user's own (or collaborative) playlists.
  readonly property var editablePlaylists: {
    var out = []
    var all = Loadable.hasData(playlists) ? playlists.data : []
    for (var i = 0; i < all.length; i++) if (all[i].editable === true) out.push(all[i])
    return out
  }

  function isEditable(playlistUri) {
    for (var i = 0; i < editablePlaylists.length; i++) if (editablePlaylists[i].uri === playlistUri) return true
    return false
  }

  // Show the playlist on screen again after it changed, cursor at `cursor`.
  function refreshIfShowing(playlistUri, cursor) {
    if (kind !== "playlist" || uri !== playlistUri || historyIndex < 0) return
    if (cursor !== undefined) history[historyIndex].cursor = Math.max(0, cursor)
    show(history[historyIndex], true)
  }

  // Add tracks ([{ uri, title }]) to a playlist. Says what happened.
  function addToPlaylist(playlist, tracks) {
    if (tracks.length === 0) return
    var uris = tracks.map(function(track) { return track.uri })
    player.request("playlist.add", { playlist_uri: playlist.uri, track_uris: uris }, {
      deadline: 10000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        var data = result.data
        if (!data.changed) {
          root.notice(root.describeTracks(tracks) + (tracks.length === 1 ? " is" : " are") + " already in " + data.playlist, false)
          return
        }
        root.notice("Added " + (tracks.length === 1 ? tracks[0].title : data.added + " tracks") + " to " + data.playlist
          + (data.skipped > 0 ? " (" + data.skipped + " already there)" : ""), false)
        root.clearMarks()
        root.loadPlaylists()
        root.refreshIfShowing(playlist.uri)
      }
    })
  }

  // Create a playlist, with `tracks` in it if any are given.
  function createPlaylist(name, tracks) {
    var args = { name: name }
    if (tracks && tracks.length > 0) args.track_uris = tracks.map(function(track) { return track.uri })
    player.request("playlist.create", args, {
      deadline: 15000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        root.notice("Created " + result.data.playlist
          + (result.data.total > 0 ? " with " + root.count(result.data.total, "track", "tracks") : ""), false)
        root.clearMarks()
        root.loadPlaylists()
      }
    })
  }

  function renamePlaylist(playlistUri, name) {
    player.request("playlist.rename", { playlist_uri: playlistUri, name: name }, {
      deadline: 10000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        root.notice(result.data.changed ? "Renamed to " + result.data.playlist : "It is already called that", false)
        root.loadPlaylists()
        if (root.kind === "playlist" && root.uri === playlistUri) root.name = result.data.playlist
      }
    })
  }

  // Dangerous actions take two presses: the first names what would happen,
  // the second, within a few seconds, does it. `armed` is what is pending.
  property string armed: ""
  Timer {
    id: disarm
    interval: 3500
    onTriggered: root.armed = ""
  }
  // True on the second press for `key`; on the first it says `question`.
  function confirmed(key, question) {
    if (armed === key) {
      armed = ""
      return true
    }
    armed = key
    disarm.restart()
    notice(question, false)
    return false
  }

  // Delete one of the user's playlists (from the sidebar).
  function deletePlaylist(playlist) {
    if (!playlist || !playlist.uri || playlist.editable !== true) {
      notice("Only your own playlists can be deleted", true)
      return
    }
    if (!confirmed("delete:" + playlist.uri, "Press again to delete the playlist " + playlist.name)) return
    player.request("playlist.delete", { playlist_uri: playlist.uri }, {
      deadline: 10000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        root.notice("Deleted " + playlist.name, false)
        root.loadPlaylists()
        // If it was on screen, there is nothing left to show.
        if (root.kind === "playlist" && root.uri === playlist.uri) root.leaveDeleted()
      }
    })
  }

  function leaveDeleted() {
    if (canGoBack) {
      history = history.slice(0, historyIndex)
      historyIndex = history.length - 1
      show(history[historyIndex], false)
    } else {
      leaveCurrent()
      history = []
      historyIndex = -1
      kind = ""
      uri = ""
      name = ""
      subtitle = ""
      rows = []
      total = 0
      revision++
      collection = Loadable.ready(null)
    }
  }

  // Why the playlist on screen cannot be changed, or "" if it can.
  function whyNotEditable() {
    if (kind !== "playlist") return "Open one of your playlists first"
    if (uri.indexOf(":collection") !== -1) return "Liked Songs: press f on a track to unlike it"
    if (!isEditable(uri)) return "This playlist is not yours to change"
    return ""
  }

  // Remove the selection from the playlist on screen.
  function removeFromPlaylist(index) {
    var why = whyNotEditable()
    if (why !== "") {
      notice(why, true)
      return
    }
    var tracks = selection(index)
    if (tracks.length === 0) return
    var key = "remove:" + tracks.map(function(track) { return track.uri }).join(",")
    if (!confirmed(key, "Press again to remove " + describeTracks(tracks) + " from " + name)) return
    var playlistUri = uri
    player.request("playlist.remove", {
      playlist_uri: playlistUri, track_uris: tracks.map(function(track) { return track.uri })
    }, {
      deadline: 10000,
      onDone: function(result) {
        if (!result.ok) {
          root.notice(result.error.message, true)
          return
        }
        root.notice(result.data.changed ? "Removed " + root.describeTracks(tracks) + " from " + result.data.playlist
          : "Nothing to remove", false)
        root.clearMarks()
        root.loadPlaylists()
        root.refreshIfShowing(playlistUri, index)
      }
    })
  }

  // ---- Reordering. Moves are sent one at a time, in order, because each
  //      is described by positions that the one before it changes.
  property var moveQueue: []
  property bool moving: false

  // Move the track at `index` up (-1) or down (+1) in the playlist on
  // screen. Returns the row's new index, or -1 if it did not move.
  function moveTrack(index, delta) {
    var why = whyNotEditable()
    if (why !== "") {
      notice(why, true)
      return -1
    }
    var to = index + delta
    if (!isTrack(rowAt(index)) || to < 0 || to >= total) return -1
    // Shown at once.
    var next = rows.slice()
    var moved = next[index]
    next[index] = next[to]
    next[to] = moved
    rows = next
    revision++
    moveQueue.push({ playlist: uri, from: index, to: to })
    pumpMoves()
    return to
  }

  function pumpMoves() {
    if (moving || moveQueue.length === 0) return
    var move = moveQueue.shift()
    moving = true
    player.request("playlist.move", { playlist_uri: move.playlist, from: move.from, to: move.to }, {
      deadline: 10000,
      onDone: function(result) {
        root.moving = false
        if (!result.ok) {
          // The screen no longer matches Spotify: drop what was queued and reload.
          root.moveQueue = []
          root.notice(result.error.message, true)
          root.refreshIfShowing(move.playlist, move.to)
          return
        }
        root.pumpMoves()
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

  // Up next follows the music. The track object is replaced on every player
  // event, so compare ids rather than reacting to each one.
  property string lastTrackId: ""
  Connections {
    target: root.player
    function onTrackChanged() {
      var id = root.player.track ? root.player.track.id : ""
      if (id === root.lastTrackId) return
      root.lastTrackId = id
      if (root.kind === "queue" && root.historyIndex >= 0) root.show(root.history[root.historyIndex], false)
    }
  }
}
