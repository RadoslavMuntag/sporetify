.pragma library

// Spotify links, as other programs hand them over: `spotify:album:<id>` and
// `https://open.spotify.com/album/<id>?si=...`. Pure text handling.

var kinds = ["track", "album", "artist", "playlist"]

function validId(id) {
  return /^[0-9A-Za-z]{10,40}$/.test(id)
}

// { kind, uri } for a link Sporetify can open, or null.
function parse(text) {
  var link = String(text || "").trim()
  var parts
  if (link.indexOf("spotify:") === 0) {
    parts = link.split(":").slice(1)
    // The old form of a playlist link names its owner first.
    if (parts.length === 4 && parts[0] === "user" && parts[2] === "playlist") parts = ["playlist", parts[3]]
  } else {
    var match = /^https?:\/\/open\.spotify\.com\/(?:intl-[a-z-]+\/)?([a-z]+)\/([^/?#]+)/i.exec(link)
    if (!match) return null
    parts = [match[1].toLowerCase(), match[2]]
  }
  if (parts.length !== 2 || kinds.indexOf(parts[0]) < 0 || !validId(parts[1])) return null
  return { kind: parts[0], uri: "spotify:" + parts[0] + ":" + parts[1] }
}

// Where the playing track was played from, as a place the app can open,
// from the daemon's `player.up_next` answer. Null when the daemon knows no
// context or the track is not in it (the context is remembered from an
// earlier play, and the track may since have come from another device).
// A playlist or Liked Songs opens with the cursor on the track's position;
// an album or artist page finds the track by uri once its rows are in.
function playingPlace(upNext, trackUri) {
  if (!upNext || typeof upNext.context_uri !== "string" || typeof upNext.position !== "number") return null
  var uri = upNext.context_uri
  var name = upNext.context_name || ""
  if (/^spotify:user:[^:]+:collection$/.test(uri))
    return { kind: "playlist", uri: uri, name: name || "Liked Songs", cursor: upNext.position }
  var link = parse(uri)
  if (!link) return null
  if (link.kind === "playlist") return { kind: "playlist", uri: uri, name: name, cursor: upNext.position }
  if (link.kind === "album" || link.kind === "artist") return { kind: link.kind, uri: uri, name: name, focus: trackUri || "" }
  return null
}
