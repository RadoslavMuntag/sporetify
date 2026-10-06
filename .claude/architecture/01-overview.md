# 01 · Overview

## Processes

| Process | Tech | Lifetime | Owns |
| --- | --- | --- | --- |
| `sporetifyd` | Rust | Socket-activated, exits after idle | Audio, Spotify session, sign-in, library cache, MPRIS server, player state |
| Shell plugin | QML inside `omarchy-shell` | Lives with the shell | Bar widget, mini-player, global IPC target |
| Full app | QML, own `qs -p App.qml` process | While its window is open | Library browsing, search, now-playing bar |

Rule of ownership: **state lives in the daemon, pixels live in QML.** A
frontend can be killed and restarted at any moment and must rebuild itself
from one `hello` snapshot.

## Channels

```
 media keys, playerctl ──MPRIS (D-Bus)──┐
                                        ▼
 plugin ◄──── Unix socket (NDJSON) ──► sporetifyd ◄──► Spotify
 app    ◄──── Unix socket (NDJSON) ──►              (librespot session)
```

- **Socket**: what both frontends use for everything, transport included:
  commands, state events, library, search, sign-in. See
  [03-protocol.md](03-protocol.md).
- **MPRIS**: the compatibility surface for the rest of the desktop (media
  keys, `playerctl`, other widgets). The plugin only reads it, to notice
  playback that started while its socket was closed.

Both end in the same `Playback::command`, so they cannot disagree.

## Lifecycles

**Daemon start.** `sporetifyd.socket` (systemd user unit) listens on
`$XDG_RUNTIME_DIR/sporetify.sock`. The first connection starts
`sporetifyd.service`. Frontends never spawn or supervise the daemon; they just
connect, and reconnect with backoff if the socket drops.

**Daemon stop.** The daemon exits by itself after the idle time (default
15 min) with no socket clients, unless music is playing. Volume, track,
position and context are saved, so the next start resumes where it left off.

**Connections are held on demand.** A frontend connects while a surface is
open, while a request is in flight, and for 10 s afterwards; the plugin also
stays connected while music plays. Otherwise it is disconnected, so an unused
bar does not keep the daemon alive.

**Cold control path.** A `playPause` with the daemon down: the plugin connects
(which starts the daemon), sends the command with a deadline, and shows the
intent at once. The daemon holds the command until its Spotify session is up.
Measured at about two seconds to audible playback. If the deadline passes the
request fails with a reason; nothing waits forever.

**App launch.** `bin/sporetify` focuses the running window if there is one,
otherwise starts `qs -p App.qml`. Closing the window ends the app process;
the music is in the daemon and keeps playing.

**Shell reload.** The shell keeps a running plugin service across its hot
reloads, so plugin changes need `omarchy restart shell` during development.
All plugin state is rebuilt from the daemon's `hello`.

## Typical flows

**Press Space in the mini-player**

1. The key handler asks `Keymap` for the action and calls `Player.run`.
2. `Player` sets its `playingIntent`; the icon changes this frame.
3. `player.play` or `player.pause` goes over the socket; the daemon updates
   its state at once and emits a `player` event.
4. When the request ends the intent is dropped and the daemon's state shows
   through. A failure leaves the reason in `lastError`.

**Open a playlist in the app**

1. `Library.open` cancels the previous collection's requests and bumps its
   generation counter.
2. `library.tracks` for page 0 goes out; the list shows the name at once.
3. The answer sets the total, so the list has every row from then on, with
   placeholders for rows whose page has not arrived.
4. Scrolling claims the pages behind the visible rows plus one screen ahead.
5. An answer for a collection that is no longer open is dropped.

**Network drops mid-session**

1. In-flight requests end with `error.code = "offline"` at their deadline or
   sooner.
2. Daemon emits a `status` event; frontends show an offline badge.
3. Cached views keep working; playback continues for whatever is buffered.
4. Daemon retries with backoff and emits `status` again when back.

## Where each rule from CLAUDE.md is enforced

| Rule | Enforced in |
| --- | --- |
| Deadline on every request | `ipc` rejects a request without one; `ClientCore.request` throws |
| Exactly one end per request | `ipc::supervise` in the daemon; `ClientCore` mirrors every deadline client-side |
| Three exits for loading states | `common/Loadable.js`: `loading / stale / ready / error` only |
| Cancel superseded work | Request scopes in `ClientCore`; generation counter in `app/Library.qml`; `cancel` op |
| Events not polling | `player` and `status` events; position interpolated by `common/Position.js` |
| Coalesced bursts | `Player.setVolume`: first value at once, then one per 80 ms, last always sent |
| One keymap | `common/Keymap.js`; surfaces only call `actionFor` and `hints` |
| No colour literals, no network in QML | `tests/lint.sh` |
