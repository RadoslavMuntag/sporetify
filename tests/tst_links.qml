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
}
