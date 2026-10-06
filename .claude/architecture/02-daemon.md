# 02 · Daemon (`sporetifyd`)

Rust, single binary, systemd user service started by socket activation.
Tokio current-thread runtime on a `LocalSet` (MPRIS callbacks are not `Send`);
audio decoding runs on librespot's own threads.

## Modules

Built:

| Module | Responsibility |
| --- | --- |
| `main` | Take the listening socket from systemd (or bind one), wire modules, signals, idle exit |
| `proto` | Wire types, error codes, frame builders, protocol limits |
| `ipc` | Socket server: line framing, request supervision, cancellation, event delivery |
| `ops` | One function mapping op names to handlers; `debug.*` ops behind `--debug-ops` |
| `state` | The single authoritative `PlayerState` and status, and their change stream |
| `auth` | Sign-in through librespot's OAuth; refresh token in the desktop keyring |
| `player` | librespot session, Spotify Connect device, commands, player events to state |
| `catalog` | Playlists, track lists, track metadata, library search (session internal API) |
| `persist` | Volume and resume point on disk |
| `art` | Cover images fetched once and kept as files |
| `mpris` | MPRIS server mirroring `state`, calling the same commands as the socket |

Planned, not built:

| Module | Responsibility |
| --- | --- |
| `viz` | Band energies and beat pulses from the playback path, for subscribers only |
| `remote` | Player state when another Connect device is the active one |
| `api` | Optional public Web API client, only with a user-supplied client id |

Dependency direction: `ipc` → `ops` → `player`, `catalog`, `state`. `mpris`
→ `player`, `state`. Nothing depends on `ipc` or `mpris`. `state` is the only
place `player` and the frontends meet.

## State

One `PlayerState` (track, playing, position as a point in time, volume,
shuffle, repeat, device) plus a `Status` (`starting`, `ready`, `offline`,
`signed_out`, `no_premium`). All changes go through `Shared::update_player`
or `set_status`, which bump `seq` and broadcast. Subscribers get the **whole**
player state on every change, not a diff: it is small, and a client can never
apply a diff to the wrong base.

Commands are optimistic inside the daemon too: `Playback::command` hands the
command to librespot's queue, updates state at once, and returns. librespot's
player events then confirm or correct it.

## Requests and deadlines

Every socket request becomes a supervised task with a deadline (client-supplied,
clamped to 30 s), a cancel channel (fired by `cancel` or by the client
disconnecting), and exactly one terminal frame: `ok`, or `error` with a code.
A handler that panics still produces `error: internal`. Requests run
concurrently; a slow one never queues a fast one.

Ops that need Spotify call `Playback::settle()` first, which waits out a
connection attempt in progress (bounded by the request deadline). That is what
lets a command sent to a just-started daemon land instead of failing.

A client that stops reading is disconnected once 256 lines are queued for it.
Lines longer than 64 KiB end the connection.

## Sign-in

- No client id of our own. `auth` uses the `librespot-oauth` flow with the id
  librespot ships (Spotify's desktop client), redirect `127.0.0.1:8898`.
- Only the refresh token is kept, in the desktop keyring through
  `secret-tool` (attributes `service=sporetify account=spotify`). It is passed
  on stdin, never on a command line.
- At start the refresh token is exchanged for an access token. A refusal from
  Spotify signs the user out; any other failure means `offline` and a retry
  with backoff (2 s doubling to 60 s).
- The sign-in URL is printed to the journal by the OAuth library. It holds a
  PKCE challenge, not a token.

## Playback

- One librespot `Session`, `Player` (PulseAudio backend, soft volume) and
  `Spirc`. The device is named "Sporetify".
- A Connect device ignores everything except activate until it is active, and
  activation resets its volume. So "play" with nothing loaded activates,
  re-applies the volume, then loads; `Playback::loaded` tracks whether a track
  is really loaded as opposed to merely remembered.
- With nothing loaded, play resumes the remembered track at its position in
  its remembered context, or starts Liked Songs.
- When the session ends the loop reconnects; a sign-out ends it for good.

## Library

- Everything goes through the session's internal API (`spclient` and
  `librespot-metadata`). The public Web API answers 429 for the built-in
  client id and is not used.
- Sidebar: the rootlist, with Liked Songs added in front. Folders are
  entries of their own (`kind: "folder"`); every entry carries the `depth`
  of the folders it sits in.
- Track lists: playlist contents, or the collection context for Liked Songs.
- Saved for offline use in `$XDG_CACHE_HOME/sporetify/library.json`: the
  sidebar as last fetched and every list that has been loaded. Without a
  session `library.playlists` and `library.tracks` answer from it (`stale:
  true`), with placeholder rows for tracks whose metadata was never cached.
- Track metadata: one lookup per track, bounded concurrency (8 for a page a
  view asked for), cached on disk for good in
  `$XDG_CACHE_HOME/sporetify/tracks.json`, written atomically.
- Indexing: the first library request starts a background pass over Liked
  Songs and then every playlist (20 tracks at a time, 3 in flight, retries
  with backoff), so search covers the whole library and all of it can be
  shown offline. Entries that can never be looked up (episodes, local
  files) get fewer retries and do not hold the index open.
- Covers: `art` downloads an image from Spotify's image hosts once, into
  `$XDG_CACHE_HOME/sporetify/art/`, and hands out the file path. The playing
  track's cover is fetched on every track change and added to the state as
  `track.art_path`; `art.get` does the same for any cover address (album
  and artist pages carry `art_url`). Nothing is evicted yet.
- Library search: `library.search` matches every word of the query against
  title, artists and album of cached tracks in known lists. It never hits
  the network.
- Spotify search: `search` sends the `searchDesktop` persisted GraphQL query
  to `api-partner.spotify.com` with the session's login5 token and client
  token, and maps the answer to track rows, artists, albums and playlists.
  The query is named by a hash (`SEARCH_QUERY_HASH`, overridable with
  `SPORETIFY_SEARCH_HASH`) that Spotify can retire.
- Likes: `library.save` / `unsave` write to the collection service; every
  track row carries `liked`, taken from the cached Liked Songs list.

## Persistence

`$XDG_STATE_HOME/sporetify/state.json`: volume, last context, last track,
position. Written on track change, pause, seek, volume change, session end
and daemon exit; write-then-rename so a crash cannot leave half a file.

## MPRIS

Bus name suffix `sporetify`, identity "Sporetify". Play, pause, play/pause,
next, previous, seek, set position, volume and shuffle map to the same
`Playback::command` the socket uses. Metadata, status, volume and shuffle are
pushed on change; `Seeked` is emitted when the position moves without a track
or play-state change; the Position property is refreshed once a second while
playing. MPRIS exists only while the daemon runs, so media keys cannot wake a
daemon that has idled out.

## Idle exit

The daemon exits after `--idle-secs` (default 900) with no socket clients,
unless something is playing. systemd restarts it on the next connection.

## Failure behaviour

| Situation | Daemon behaviour |
| --- | --- |
| No network at start | `status: offline`, retry with backoff; library ops answer from disk |
| Stored sign-in rejected | Token removed, `status: signed_out` |
| Account without Premium | `status: no_premium`; playback ops return `no_premium` |
| Session drops | State reset to the remembered track, `offline`, reconnect |
| Command while signed out or offline | Fails at once with `unauthorized` / `offline` |
| Library lookup fails | Row comes back `available: false` and is not cached |
| Client stops reading | Disconnected past a small buffer |
| No session bus | MPRIS disabled, socket unaffected |

Not handled yet: another device taking over is not reported to clients.

## Testing

- `daemon/tests/protocol.rs`: 16 tests over a real Unix socket (hello,
  deadlines, cancel, panics, malformed input, concurrency, events, argument
  validation, fail-fast when signed out).
- No automated tests yet for `auth`, `player`, `catalog`, `persist` or
  `mpris`; they were verified by hand against a real account. Pure parts worth
  testing first: `persist` round trip, `catalog` search matching, `player`
  state transitions from events.
- Run a second daemon for experiments with `--socket <path> --debug-ops`.
  `--no-connect` keeps it offline, to test what works from the saved library.
