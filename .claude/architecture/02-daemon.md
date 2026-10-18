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
| `private` | Writes files only the user may read, and closes older ones at start |
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
  and artist pages carry `art_url`). The folder is held to 200 MB: at start
  and every 200 downloads the least recently used covers are removed until
  it is back to 160 MB. "Used" is the file's modification time, refreshed
  at most once a day when a cover is served.
- Library search: `library.search` matches every word of the query against
  title, artists and album of cached tracks in known lists. It never hits
  the network.
- Spotify search: `search` sends the `searchDesktop` persisted GraphQL query
  to `api-partner.spotify.com` with the session's login5 token and client
  token, and maps the answer to track rows, artists, albums and playlists.
  The query is named by a hash (`SEARCH_QUERY_HASH`, overridable with
  `SPORETIFY_SEARCH_HASH`) that Spotify can retire.
- Spotify's own playlists: nothing lists them, so they are found by name
  through Spotify search, keeping only the one owned by "Spotify" with
  exactly that name. `library.made_for_you` looks up a fixed list of names
  (Discover Weekly, Release Radar, daylist, On Repeat, Repeat Rewind, Daily
  Mix 1 to 6) and keeps the answer for the daemon's lifetime;
  `browse.artist` adds "This Is <artist>" the same way. Artist radio comes
  from `/inspiredby-mix/v2/seed_to_playlist/<uri>`, which returns the radio
  playlist's uri; its picture is not returned, but its address depends
  only on the artist, so it is built (`radio_art`). All of them open as
  ordinary playlists. Their pictures come from `pickasso.spotifycdn.com`
  and `daylist.spotifycdn.com`, which `art` accepts beside the cover hosts.
- Playlist edits go through the playlist service as `ListChanges`
  messages, each based on the revision just read:
  - add, remove, move and rename post to
    `/playlist/v2/playlist/<id>/changes`. The playlist is re-read from
    Spotify first, so tracks already there are not added again, tracks not
    there are not "removed", and a move is checked against the real length
    and refused unless the track at `from` is the `track_uri` the app sent.
    A move's destination is sent the way Spotify counts it (the position in
    the list before the track is taken out). The app's positions skip
    entries that cannot be read, as its list does, and are mapped to
    Spotify's, which count them.
  - create posts to `/playlist/v2/playlist`, which answers with the new uri
    but ignores any name sent along, so the playlist is renamed straight
    after and filled, and only then added first in the user's list of
    playlists (`/playlist/v2/user/<user>/rootlist/changes`). A playlist
    outside that list is what Spotify treats as deleted, so a create that
    fails or times out part-way leaves nothing visible behind.
  - delete removes it from that list, which for an owned playlist is what
    Spotify calls deleting.
  - nothing runs after a create or delete has been sent, so a slow step
    cannot turn a change already made into a timeout (and a create tried
    again into a duplicate). The app re-reads the sidebar afterwards.
  The sidebar marks which playlists the user may change, from the
  capabilities Spotify reports.
- Likes: `library.save` / `unsave` write to the collection service; every
  track row carries `liked`, taken from the cached Liked Songs list. A song
  exists under several uris, so "liked" is matched by uri and, failing that,
  by title and first artist (`LikedIndex`). Liking a song already liked
  under another version does nothing; unliking removes the entry that is
  actually in the list.

## Persistence

`$XDG_STATE_HOME/sporetify/state.json`: volume, last context, last track,
position. Written on track change, pause, seek, volume change, session end
and daemon exit; write-then-rename so a crash cannot leave half a file.

Everything the daemon writes is private to the user (`private.rs`): the
resume point and the library cache say what they listen to, name their
playlists and hold their Spotify user id. Files are created 0600 in folders
of mode 0700 regardless of the umask, the daemon sets its umask to 077 at
start (the unit says `UMask=0077` too), and at start it also closes the
folders and files an earlier version left readable by others. Asked for in
the marketplace review, 2026-10-12.

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
- Unit tests beside the code (24): `persist` round trip and old files;
  `catalog` search matching, the offline fallback, liked matching across
  versions, folder parsing and the hand-encoded collection message; `art`
  host checks and eviction order; `player` play/pause clock and volume.
- Still only verified by hand against a real account: `auth`, the session
  loop, MPRIS, and everything that needs Spotify to answer.
- Run a second daemon for experiments with `--socket <path> --debug-ops`.
  `--no-connect` keeps it offline, to test what works from the saved library.
