import QtQuick

import "../common/Loadable.js" as Loadable
import "../common/Pages.js" as Pages

// What the app is showing: the playlist list and the open collection's
// rows. Rows arrive a page at a time, for whatever is on screen.
Item {
  id: root

  // The shared Player (connection + actions).
  required property var player

  readonly property int pageSize: 50

  // Loadable holding [{ uri, name, length }].
  property var playlists: Loadable.loading(null)

  // The open collection.
  property string uri: ""
  property string name: ""
  property int total: 0
  // Sparse: rows[i] is a track row once its page has arrived.
  property var rows: []
  // Bumped whenever rows change, so delegates re-read their row.
  property int revision: 0
  // Loadable for the collection as a whole (its first page).
  property var collection: Loadable.ready(null)

  // True while the rows are search results rather than a collection.
  property bool searching: false
  property string query: ""
  // Matches in the whole library; `total` is how many of them are listed.
  property int matches: 0
  // The daemon is still fetching metadata, so results may be incomplete.
  property bool indexing: false

  property var pages: Pages.create(pageSize)
  // Requests of the open collection, cancelled when another one opens.
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

  function leaveCurrent() {
    for (var i = 0; i < inFlight.length; i++) inFlight[i].cancel()
    inFlight = []
    generation++
  }

  // Search the library as the user types. Each call supersedes the last.
  function search(text) {
    leaveCurrent()
    var forGeneration = generation
    query = text
    searching = true
    uri = "search:"
    name = text.trim() === "" ? "Search your library" : "Results for “" + text.trim() + "”"
    pages.reset()
    player.request("library.search", { query: text, limit: 300 }, {
      deadline: 3000,
      scope: "search",
      onDone: function(result) {
        if (forGeneration !== root.generation) return
        if (!result.ok) {
          if (result.error.code !== "cancelled") root.collection = Loadable.withResult(root.collection, result)
          return
        }
        root.rows = result.data.items
        root.total = result.data.items.length
        root.matches = result.data.total
        root.indexing = result.data.indexing
        root.revision++
        root.collection = Loadable.ready(true)
      }
    })
  }

  function open(uri, name, refresh) {
    leaveCurrent()
    searching = false
    root.uri = uri
    root.name = name
    root.total = 0
    root.rows = []
    root.revision++
    pages.reset()
    collection = Loadable.loading(null)
    fetchPage(0, refresh === true)
  }

  function reload() {
    if (searching) search(query)
    else if (uri !== "") open(uri, name, true)
    loadPlaylists()
  }

  // Make sure the pages covering rows first..last are loaded or on their way.
  function ensure(first, last) {
    if (searching || uri === "" || total === 0) return
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
        // An answer for a collection that is no longer open is dropped.
        if (forGeneration !== root.generation) return
        if (!result.ok) {
          root.pages.failed(page)
          if (page === 0) root.collection = Loadable.withResult(root.collection, result)
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
        root.pages.done(page)
        root.revision++
        if (page === 0) root.collection = Loadable.ready(true)
      }
    })
    inFlight.push(handle)
  }

  function rowAt(index) {
    return index >= 0 && index < rows.length ? (rows[index] || null) : null
  }

  function play(index) {
    var row = rowAt(index)
    // A search result plays inside the list it was found in.
    if (row && row.available) player.playContext(searching ? row.context_uri : uri, row.uri)
  }
}
