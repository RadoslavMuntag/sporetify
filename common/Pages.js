.pragma library

// Which pages of a long list still need fetching for the rows on screen.
// Pure bookkeeping: the caller does the fetching and reports back.

function create(pageSize) {
  var loaded = {}
  var loading = {}

  return {
    pageSize: pageSize,

    // Pages covering rows first..last (inclusive) that are neither loaded
    // nor on their way. They are marked as on their way.
    claim: function(first, last, total) {
      var out = []
      if (total <= 0 || last < first) return out
      var from = Math.floor(Math.max(0, first) / pageSize)
      var to = Math.floor(Math.min(total - 1, last) / pageSize)
      for (var page = from; page <= to; page++) {
        if (loaded[page] || loading[page]) continue
        loading[page] = true
        out.push(page)
      }
      return out
    },
    done: function(page) {
      delete loading[page]
      loaded[page] = true
    },
    // A failed page may be claimed again.
    failed: function(page) { delete loading[page] },
    isLoaded: function(page) { return loaded[page] === true },
    reset: function() {
      loaded = {}
      loading = {}
    }
  }
}

// Number the tracks of a list that also holds other rows (headings, albums,
// artists, playlists): each track gets `n`, counted within its section, so
// the first track under a heading is 1 whatever sits above it.
function numberTracks(rows) {
  var n = 0
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row) continue
    if (row.kind === "heading") { n = 0; continue }
    if (row.kind === undefined || row.kind === "") row.n = ++n
  }
  return rows
}
