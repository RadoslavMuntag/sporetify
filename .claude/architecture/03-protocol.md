# 03 · Socket protocol (draft v0)

Transport: Unix stream socket at `$XDG_RUNTIME_DIR/sporetify.sock`.
Framing: one JSON object per line (UTF-8, `\n` terminated). No binary frames;
artwork is exchanged as file paths in the cache.

This is a draft. Until v1 is declared, frontends and daemon ship together and
the version check below is a hard equality.

## Handshake

Daemon speaks first, once per connection:

```json
{"ev":"hello","protocol":0,"daemon":"0.1.0","status":"ready","player":{...}}
```

`player` is a full `PlayerState` snapshot, so a client is usable after reading
one line. A client that sees an unknown `protocol` shows an "update needed"
state and sends nothing.

## Requests

```json
{"id":17,"op":"library.playlist","args":{"id":"...","offset":0,"limit":100},"deadline_ms":5000}
```

- `id`: client-chosen integer, unique per connection.
- `deadline_ms`: required. The daemon clamps it to its maximum and rejects a
  request without one (`bad_request`).

## Responses

Every request gets frames carrying its `id`, exactly one of them final:

```json
{"id":17,"ok":true,"stale":false,"final":true,"data":{...}}
```

The protocol also allows an early frame from cache before the final one:

```json
{"id":17,"ok":true,"stale":true,"final":false,"data":{...}}
{"id":17,"ok":true,"stale":false,"final":true,"data":{...}}
```

Clients handle both (`ClientCore.js` is tested for it), but the daemon does
not send early frames yet: library answers come from its memory cache when it
has one, and from Spotify otherwise. After the final frame the id is dead.

Errors are always final:

```json
{"id":17,"ok":false,"final":true,"error":{"code":"timeout","message":"Spotify did not answer in time","retry_after_ms":null}}
```

| Code | Meaning | UI reaction |
| --- | --- | --- |
| `timeout` | Deadline passed | Keep stale data, offer retry |
| `offline` | No network | Offline badge, keep stale data |
| `rate_limited` | Spotify asked us to wait | Auto-retry after `retry_after_ms` |
| `unauthorized` | Signed out or token rejected | Prompt sign-in |
| `no_premium` | Account cannot play | Explain once, keep browsing enabled |
| `no_audio` | No output device | Explain, offer device picker |
| `not_found` | Entity gone | Remove from view |
| `cancelled` | Client cancelled or superseded | Silent |
| `bad_request` | Malformed or missing field | Bug: log it |
| `internal` | Daemon fault | Toast, log |

## Cancel

```json
{"op":"cancel","target":17}
```

No `id`, no reply of its own. The target request ends with `cancelled`.
Closing the connection cancels everything it had in flight.

## Events

Unsolicited frames have `ev` instead of `id`. Sent today:

| Event | Sent when | Shape |
| --- | --- | --- |
| `hello` | Once, first frame of a connection | `{protocol, daemon, status, player}` |
| `player` | Any `PlayerState` change | `{player}`: the whole state, with `seq` |
| `status` | The status changes | `{status}` |
| `auth` | A browser sign-in ended without signing in | `{ok:false, message}` |

`player.position` is `{position_ms, at_ms, rate}`; clients interpolate
locally and never poll. All of the above reach every client without
subscribing. `subscribe` / `unsubscribe` exist and track topics per
connection, for the planned events:

| Planned event | Purpose |
| --- | --- |
| `queue` | Queue contents changed |
| `devices` | Connect device list changed |
| `invalidate` | A cached page a client may be showing has changed |
| `viz` | Band energies and beat, about 30 Hz, lossy |

## Operations

Built:

| Op | Args | Result |
| --- | --- | --- |
| `player.get` | | `{status, player}` |
| `player.play` `pause` `toggle` `next` `previous` | | `{}` |
| `player.seek` | `position_ms` | `{}` |
| `player.volume` | `value` 0..1 | `{}` |
| `player.volume_step` | `delta` | `{}` |
| `player.shuffle` `player.repeat` | `on` | `{}` |
| `player.play_context` | `uri`, optional `track_uri` | `{}` |
| `library.playlists` | | `{items, stale}`: the sidebar, Liked Songs first. An item is `{uri, name, length, depth}` or a folder `{kind:"folder", id, name, depth}` |
| `library.tracks` | `uri`, `offset`, `limit` (max 200), optional `refresh` | `{uri, name, total, offset, items}` |
| `library.search` | `query`, optional `limit` (max 500) | `{query, items, total, indexing}`; cached library only, never the network |
| `search` | `query`, optional `limit` per section (max 50) | `{query, tracks, artists, albums, playlists}`; all of Spotify |
| `library.track` | `uri` | `{track}`: one track row |
| `art.get` | `url` (a Spotify image address) | `{path}`: the cover as a local file |
| `library.save` `library.unsave` | `uri` | `{uri, liked}`; writes to Liked Songs |
| `library.is_saved` | `uri` | `{uri, liked}`, from the cached Liked Songs list |
| `player.queue_add` | `uri` | `{}`; puts the track at the front of the queue |
| `browse.album` | `uri` | `{album: {uri, name, artists, year, kind, tracks}, items}` |
| `browse.artist` | `uri` | `{artist: {uri, name}, top_tracks, albums, singles}` |
| `player.up_next` | optional `limit` (max 200) | `{context_uri, context_name, position, total, shuffle, items}` |
| `auth.begin` | | `{started}`; opens the browser, outcome arrives as events |
| `auth.sign_out` `auth.retry` | | `{}` |
| `subscribe` `unsubscribe` | `topics` | `{topics}` |
| `cancel` | `target` (no `id`) | none |

A track row is `{uri, title, artists, artist_uris, album, album_uri,
duration_ms, available, liked}`; search results add `context_uri` and
`context_name`, the list the track was found in. `player.play_context`
accepts playlist, collection, album and artist uris.

The player state's `track` carries `art_url` and, once the daemon has the
file, `art_path`. Album and artist answers carry `art_url`. Frontends never
load covers from the network; they show the file.

`library.playlists` and `library.tracks` keep working without a connection,
from what was saved (`stale: true`).

`player.up_next` lists first the tracks queued from Sporetify that have not
played yet (rows with `queued: true`), then what follows the current track in
the list it was started from, in that list's own order. Spotify's queue
cannot be read back, so anything queued from another device is missing, the
context is only known when playback was started from Sporetify, and with
shuffle on the real order differs (`shuffle` says so).

`search` returns track rows like any other, artists as `{uri, name}`, albums
as `{uri, name, artists, year, kind}` and playlists as `{uri, name, owner}`.
It fails with `internal` if Spotify stops accepting the query, and
`rate_limited` on a 429; clients should keep showing library results.

How the two writes work without a client id:

- **Likes** go to Spotify's collection service (`POST /collection/v2/write`,
  a small protobuf encoded by hand in `catalog.rs`).
- **Queueing** sends the same request another device's "add to queue" would
  (`POST /connect-state/v1/player/command/from/<self>/to/<self>`); Spotify
  routes it back and librespot handles it as a remote command.

A track can exist under several uris, and the version in Liked Songs is
often not the version the player or an artist page reports, so `liked` can
be false for a song the user does have liked.

With `--debug-ops` only: `debug.sleep {ms}`, `debug.panic`,
`debug.mercury {uri}`, `debug.spclient {endpoint}`.

Planned: `devices.list`, `player.transfer`, `player.play_tracks`,
`settings.*`. Reading, reordering and clearing the queue need support
librespot does not offer yet.

## Compatibility rules (from v1 on)

- New optional fields and new events may appear at any time; clients ignore
  what they do not know.
- Removing or changing a field bumps `protocol`.

## Debugging

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/sporetify.sock
{"id":1,"op":"player.get","args":{},"deadline_ms":1000}
```
