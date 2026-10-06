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

Every request gets one or two frames carrying its `id`:

```json
{"id":17,"ok":true,"stale":true,"final":false,"data":{...}}
{"id":17,"ok":true,"stale":false,"final":true,"data":{...}}
```

- A cached answer may arrive first with `final:false`; the fresh one follows
  with `final:true`. If cache and network agree the final frame may carry
  `"unchanged":true` and no `data`.
- With nothing cached there is just the one final frame.
- Exactly one frame per request has `final:true`. After it, the id is dead.

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

Unsolicited frames have `ev` instead of `id`:

| Event | Sent when | Notes |
| --- | --- | --- |
| `player` | Any `PlayerState` change | Diff plus `seq`; position is `{position_ms, at_ms, rate}` for local interpolation |
| `queue` | Queue contents change | Subscribe first |
| `status` | `ready / offline / signed_out / no_premium / starting` changes | Always sent |
| `devices` | Connect device list changes | Subscribe first |
| `invalidate` | A cached page a client may be showing has changed | Carries the request signature |
| `viz` | About 30 Hz while subscribed | `{bands:[...], beat:0..1}`; lossy |

`player` and `status` are always delivered. Others need
`{"id":n,"op":"subscribe","args":{"topics":["queue","viz"]},"deadline_ms":1000}`
and stop on `unsubscribe` or disconnect.

A client that detects a gap in `seq` asks for `player.get` to resync.

## Operations (initial set)

| Group | Ops |
| --- | --- |
| `player.*` | `get`, `play`, `pause`, `toggle`, `next`, `previous`, `seek`, `volume`, `shuffle`, `repeat`, `play_context`, `play_tracks`, `transfer` |
| `queue.*` | `get`, `add`, `remove`, `move`, `clear` |
| `library.*` | `playlists`, `playlist`, `saved_tracks`, `saved_albums`, `followed_artists`, `save`, `unsave` |
| `browse.*` | `album`, `artist`, `artist_albums`, `artist_top_tracks` |
| `search` | One op; `args.types` selects tracks, albums, artists, playlists |
| `devices.*` | `list` |
| `auth.*` | `status`, `begin`, `sign_out` |
| `settings.*` | `get`, `set` (daemon-side only: device name, idle time, quality) |
| `subscribe`, `unsubscribe`, `cancel` | As above |

Paged ops take `offset` and `limit` and return `{items, total, next_offset}`.

## Compatibility rules (from v1 on)

- New optional fields and new events may appear at any time; clients ignore
  what they do not know.
- Removing or changing a field bumps `protocol`.

## Debugging

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/sporetify.sock
{"id":1,"op":"player.get","args":{},"deadline_ms":1000}
```
