import QtQuick
import QtTest
import "../common/Links.js" as Links

TestCase {
  name: "Links"

  readonly property string id: "0k17h0D3J5VfsdmQ1iZtE9"

  function test_spotify_uris() {
    var kinds = ["track", "album", "artist", "playlist"]
    for (var i = 0; i < kinds.length; i++) {
      var link = Links.parse("spotify:" + kinds[i] + ":" + id)
      compare(link.kind, kinds[i])
      compare(link.uri, "spotify:" + kinds[i] + ":" + id)
    }
  }

  function test_web_addresses() {
    compare(Links.parse("https://open.spotify.com/album/" + id + "?si=abc").uri, "spotify:album:" + id)
    compare(Links.parse("https://open.spotify.com/intl-de/track/" + id).kind, "track")
    compare(Links.parse("  http://open.spotify.com/artist/" + id + "#x \n").uri, "spotify:artist:" + id)
  }

  function test_old_playlist_form() {
    compare(Links.parse("spotify:user:someone:playlist:" + id).uri, "spotify:playlist:" + id)
  }

  function test_everything_else_is_refused() {
    var bad = ["", "hello", "spotify:", "spotify:show:" + id, "spotify:track:", "spotify:track:../../etc",
      "spotify:track:" + id + ":extra", "https://example.com/album/" + id,
      "https://open.spotify.com.evil.example/album/" + id, "https://open.spotify.com/album/", "file:///etc/passwd"]
    for (var i = 0; i < bad.length; i++) compare(Links.parse(bad[i]), null, bad[i])
    compare(Links.parse(undefined), null)
  }

  // What the app opens at launch, from the daemon's `player.up_next` answer.
  readonly property string track: "spotify:track:4uLU6hMCjMI75M1A2tKUQC"

  function test_a_playlist_opens_on_the_playing_track() {
    var place = Links.playingPlace({ context_uri: "spotify:playlist:" + id, context_name: "Night Drive", position: 41 }, track)
    compare(place.kind, "playlist")
    compare(place.uri, "spotify:playlist:" + id)
    compare(place.name, "Night Drive")
    compare(place.cursor, 41)
  }

  function test_liked_songs_open_as_their_list() {
    var place = Links.playingPlace({ context_uri: "spotify:user:some.one:collection", position: 0 }, track)
    compare(place.kind, "playlist")
    compare(place.uri, "spotify:user:some.one:collection")
    compare(place.name, "Liked Songs")
    compare(place.cursor, 0)
  }

  function test_an_album_or_artist_finds_the_track_by_uri() {
    var album = Links.playingPlace({ context_uri: "spotify:album:" + id, context_name: "Meddle", position: 3 }, track)
    compare(album.kind, "album")
    compare(album.focus, track)
    var artist = Links.playingPlace({ context_uri: "spotify:artist:" + id, position: 0 }, track)
    compare(artist.kind, "artist")
    compare(artist.focus, track)
  }

  function test_nothing_when_the_track_is_not_in_its_context() {
    // A context remembered from earlier, while the track came from elsewhere.
    compare(Links.playingPlace({ context_uri: "spotify:playlist:" + id, position: null }, track), null)
    compare(Links.playingPlace({ context_uri: null, items: [], total: 0 }, track), null)
    compare(Links.playingPlace({ context_uri: "spotify:show:" + id, position: 0 }, track), null)
    compare(Links.playingPlace(null, track), null)
  }
}
