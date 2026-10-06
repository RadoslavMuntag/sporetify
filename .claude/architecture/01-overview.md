# 01 · Overview

## Processes

| Process | Tech | Lifetime | Owns |
| --- | --- | --- | --- |
| `sporetifyd` | Rust | Socket-activated, exits after idle | Audio, Spotify session, Web API, tokens, cache, MPRIS server, player state |
| Shell plugin | QML inside `omarchy-shell` | Lives with the shell | Bar widget, mini-player, global IPC target |
| Full app | QML, own `qs -p app` process | While the window is wanted | Library, search, queue, devices, settings, visuals |

Rule of ownership: **state lives in the daemon, pixels live in QML.** A
frontend can be killed and restarted at any moment and must rebuild itself
from one `hello` snapshot.

## Channels

```
            MPRIS (D-Bus)                    Unix socket (NDJSON)
plugin ◄──────────────────► sporetifyd ◄────────────────────────► plugin
                                 ▲     ◄────────────────────────► app
                                 │
                 Spotify (librespot session + Web API over HTTPS)
```

- **MPRIS**: play, pause, next, previous, seek, volume, metadata, position.
  Used by the plugin, by media keys, by `playerctl`, and by anything else on
  the desktop. This is the compatibility surface.
- **Socket**: everything MPRIS cannot say: library, search, queue editing,
  devices, auth, cache-backed pages, visualisation data. This is the product
  surface. See [03-protocol.md](03-protocol.md).

## Lifecycles

**Daemon start.** `sporetifyd.socket` (systemd user unit) listens on
`$XDG_RUNTIME_DIR/sporetify.sock`. The first connection starts
`sporetifyd.service`. Frontends never spawn or supervise the daemon; they just
connect, and reconnect with backoff if the socket drops.

**Daemon stop.** The daemon exits by itself when there are no socket clients
and playback has been stopped or paused for the configured idle time
(default 15 min, 0 = never). Paused track and position are persisted so the
next start resumes where it left off.

**Cold control path.** A global `playPause` with the daemon down: the plugin
connects (which activates the daemon), sends the command with a deadline, and
shows "starting" on the bar icon immediately. If the deadline passes the icon
shows the error state; it never spins indefinitely.

**App launch.** `bin/sporetify` asks a running app instance to show and focus
its window; if none answers it starts `qs -p app`. The app renders its frame
and last cached view first, then connects to the daemon.

**Shell hot reload.** Saving plugin files reloads the plugin. All plugin state
is derived from MPRIS and the daemon snapshot, so a reload is invisible apart
from a closed popup.

## Typical flows

**Press Space in the mini-player**

1. Key handler flips the local `playing` flag; icon changes this frame.
2. MPRIS `PlayPause` is called.
3. MPRIS property change arrives; if it disagrees after the reconcile window
   (about 1 s) the local flag snaps to the daemon's value and a toast explains.

**Open a playlist in the app**

1. Router pushes the view; header renders from the row that was activated.
2. `library.playlist` request goes out with a deadline and a generation id.
3. Daemon answers at once from cache (`stale: true`) if it has anything, and
   revalidates against the Web API in the background.
4. A second frame with `final: true` replaces the rows if they changed.
5. If the user left the view, the app sends `cancel` and drops late frames.

**Network drops mid-session**

1. In-flight requests end with `error.code = "offline"` at their deadline or
   sooner.
2. Daemon emits a `status` event; frontends show an offline badge.
3. Cached views keep working; playback continues for whatever is buffered.
4. Daemon retries with backoff and emits `status` again when back.

## Where each rule from CLAUDE.md is enforced

| Rule | Enforced in |
| --- | --- |
| Deadline on every request | Daemon request dispatcher; client refuses to send without one |
| Three exits for loading states | `common/Loadable.js` state type: `loading / ready / stale / error` only |
| Cancel superseded work | Generation counter in `DaemonClient`; `cancel` op in daemon |
| Events not polling | `subscribe` op; position interpolated in QML |
| Coalesced bursts | `common/Coalescer.js` in front of volume and seek |
| Rate limits | Daemon `api` module only |
| No literals for colour or spacing | Lint script in tests (grep for hex colours and bare pixel sizes in QML) |
