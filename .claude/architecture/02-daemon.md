# 02 · Daemon (`sporetifyd`)

Rust, single binary, runs as a systemd user service. Tokio runtime; control
logic on a current-thread executor, audio decoding on librespot's own threads.

## Modules

| Module | Responsibility |
| --- | --- |
| `main` | Take the listening socket from systemd, wire modules, signal handling, idle exit |
| `config` | Paths (XDG), settings pushed by frontends, defaults |
| `auth` | OAuth authorisation-code + PKCE with a loopback redirect, token refresh, keyring storage |
| `catalog` | Library, playlists and metadata through the librespot session's internal API (the default data path; needs no client id) |
| `api` | Optional public Web API client, only with a user-supplied client id: deadlines, in-flight dedupe, retry/backoff, `429 Retry-After`, ETags |
| `cache` | Disk cache of entities and pages, artwork files, eviction |
| `player` | librespot session, local playback, Spotify Connect device, volume |
| `remote` | Player state when another Connect device is the active one |
| `state` | The single authoritative `PlayerState` and its change stream |
| `mpris` | MPRIS server mirroring `state` and translating method calls into commands |
| `ipc` | Socket server: framing, request dispatch, cancellation, subscriptions |
| `viz` | Band energies and beat pulses taken from the playback path, for subscribers only |

Dependency direction: `ipc` and `mpris` depend on `state`, `player`, `api`,
`cache`. Nothing depends on `ipc` or `mpris`. `api` and `player` do not know
about each other; `state` is the only meeting point.

## State

One `PlayerState` struct (track, context, position + timestamp, playing,
volume, shuffle, repeat, active device, queue head). All mutations go through
one function that bumps a sequence number and broadcasts the diff. MPRIS and
socket subscribers both read from that broadcast, so they cannot disagree.

Commands are applied optimistically inside the daemon too: `state` updates
first, then the backend call runs; on failure the state reverts and an error
event carries the reason.

## Requests and deadlines

Every socket request becomes a task with:

- a deadline (client-supplied, clamped to a server maximum),
- a cancellation token (fired by `cancel`, by client disconnect, or by the
  deadline),
- exactly one terminal frame: `ok`, or `error` with a code.

A task that panics still produces a terminal `error: internal` frame. There is
a test that fires every op against a black-holed network and asserts a
terminal frame arrives within the deadline.

## Web API client

- One shared HTTPS client with connect and total timeouts below the request
  deadline.
- Identical GETs in flight are merged into one upstream call.
- Retries: idempotent requests only, exponential backoff with jitter, capped
  by the remaining deadline.
- `429`: obey `Retry-After`, pause the whole client (not just one request),
  and report `rate_limited` with `retry_after_ms` to callers that cannot wait.
- `401`: refresh the token once and replay; a second `401` becomes
  `unauthorized` and an auth event.

## Cache

- Location: `$XDG_CACHE_HOME/sporetify/`.
- Entities (track, album, artist, playlist header) keyed by Spotify id.
- Pages (playlist tracks, saved albums, search results) keyed by request
  signature, storing ids plus fetch time and ETag.
- Artwork as files, addressed by URL hash, with a size cap and LRU eviction.
- Read path is always cache first. Freshness decides only whether a background
  revalidation is started, never whether the caller waits.
- Writes are atomic (transaction or write-then-rename) so a kill mid-write
  cannot corrupt the cache.

## Auth and secrets

- Browser-based login via `xdg-open`; the daemon listens on a loopback port for
  the redirect, with PKCE and a state nonce.
- Tokens are stored in the desktop keyring (Secret Service). Never written to
  the cache directory, logs, socket events or `shell.json`.
- Socket file mode `0600` in `$XDG_RUNTIME_DIR`; the daemon accepts only
  connections from the same uid.
- Logs redact anything that looks like a token.

## Visualisation tap

- Taps PCM just before the audio sink, computes a small FFT, reduces it to a
  handful of band energies plus a beat pulse, at about 30 Hz.
- Does no work at all unless a client holds a `viz` subscription.
- Frames are tiny and lossy by design: if a client is slow, drop frames, never
  queue.

## Failure behaviour

| Situation | Daemon behaviour |
| --- | --- |
| No network | `status: offline`, serve cache, fail writes fast with `offline` |
| Token expired and refresh fails | `status: signed_out`, keep cache readable |
| Account without Premium | `status: no_premium`; browsing works, playback ops return `no_premium` |
| Audio device missing | Playback ops return `no_audio`; state stays paused |
| Another device takes over | Switch to `remote` mode and keep emitting state |
| Client stops reading | Drop its events past a small buffer, then disconnect it |

## Testing

- Unit tests per module; `api` against a local mock server that can delay,
  drop, 429 and 401.
- Protocol conformance tests driven over a real socket.
- A soak test: random ops with random cancellation and a flaky mock network,
  asserting no request is left without a terminal frame and memory stays flat.
