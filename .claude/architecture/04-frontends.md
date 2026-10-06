# 04 · Frontends

Two QML frontends share one library in `common/`. Neither holds state that
cannot be rebuilt from the daemon.

## `common/` (shared)

| File | Role |
| --- | --- |
| `ClientCore.js` | Protocol state machine with no I/O: request table, deadlines, scopes, hello check. Unit tested |
| `DaemonClient.qml` | Owns the socket and timers around `ClientCore`: connect on demand, reconnect with backoff, linger |
| `Player.qml` | A frontend's view of the daemon: `phase`, `scope`, track, optimistic `playing` and `volume`, and `run(action)` |
| `Loadable.js` | The only loading-state type: `loading`, `stale`, `ready`, `error` |
| `Pages.js` | Which pages of a long list still need fetching for the rows on screen |
| `Keymap.js` | The key table and lookups: `actionFor`, `keyLabel`, `hints` |
| `Position.js` | Interpolates playback position; formats `m:ss` |
| `KeyCap.qml` | Keycap badge shown beside a control |
| `HintBar.qml` | Footer listing the actions valid in the current scopes |

Rules for `common/`: no host-specific imports (`qs.Commons` is plugin-only;
`Theme` is app-only), so colours and sizes are passed in as properties; no
network; every `.js` file has tests in `tests/`.

Planned here: `Organism.js` and the shader components from
[05-visuals.md](05-visuals.md).

### `DaemonClient` and `ClientCore`

- `request(op, args, { deadline, scope, onFrame, onDone })` returns a handle
  with `cancel()`. `deadline` is required. `onDone` is called exactly once.
- A new request in the same `scope` cancels the previous one.
- Not connected: the request waits and is sent on `hello` with the remaining
  deadline, or ends `offline` when its deadline passes.
- A request already sent on a connection that drops ends `offline` at once.
- Sent requests get 200 ms past their deadline for the daemon's own answer,
  then end `timeout` and a `cancel` is sent.
- The connection is demand-driven: open while `active`, while a request is in
  flight, and for a 10 s linger afterwards; otherwise `link: asleep`.
- A Quickshell `Socket` does not reconnect after a failed attempt, so each
  attempt creates a new one. A connection with no `hello` within 2 s is
  treated as down.
- `link` is `asleep | connecting | up | down | incompatible`.

### `Player`

- `phase`: `asleep | starting | ready | signed_out | offline | no_premium |
  unavailable | incompatible`, derived from the link and the daemon status.
- `scope`: which shortcuts apply: `player`, `signedOut` or `fault`.
- `run(action)` executes a Keymap action. Play/pause and volume show the
  intent immediately (`playingIntent`, `volumeIntent`) and drop it when the
  daemon has answered or volume changes have settled.
- `request()` passes through to the connection for library calls.

## Shell plugin

```
manifest.json     kinds: service + bar-widget; settings: showTrackTitle, maxTitleWidth
Service.qml       Player + IPC target "sporetify" + MPRIS watch + openApp()
BarWidget.qml     icon and track title; owns the mini-player
MiniPlayer.qml    KeyboardPanel: title, seek, transport, volume, keycaps, hint bar
```

- **Bar widget:** left click toggles the mini-player, middle click plays or
  pauses, the wheel changes volume. The tooltip names the state and, on a
  fault, the reason. On a vertical bar only the icon is shown.
- **Service:** connected while the mini-player is open or music plays. It
  also watches MPRIS for the "Sporetify" player, so playback started by media
  keys or the app wakes the connection.
- **IPC target `sporetify`:** `playPause`, `next`, `previous`, `volumeUp`,
  `volumeDown`, `mute`, `toggleMini`, `toggleApp`, `signIn`, `status`,
  `nowPlaying`, `wake`. All return at once.
- **Mini-player:** one `Keys.onPressed` asks `Keymap.actionFor` with scopes
  `["mini", "player"]`. `o` opens the full app. Built on `KeyboardPanel`,
  `Button`, `PanelSlider` and `PanelSeparator` from `qs.Ui`.
- With several monitors a bar exists per monitor; `toggleMini` opens the
  popup on the first one only.
- The shell does not reliably hot-reload this plugin; use
  `omarchy restart shell` after changing its QML.

## Full app

```
App.qml              entry point at the repo root (so app/ and common/ are in the config folder)
app/
  Main.qml           window, panes, the one key handler, search bar
  Theme.qml          singleton: Omarchy theme tokens, live reload
  Library.qml        model: playlists, the open collection's rows, search
  Sidebar.qml        Liked Songs and playlists
  TrackList.qml      header and the virtualised track list
  NowPlayingBar.qml  track, transport, seek, volume
  IconButton.qml  Slider.qml
bin/sporetify        focus the window if it exists, otherwise start the app
```

- **Window:** one `FloatingWindow` with app id `sporetify`; Hyprland tiles and
  decorates it. Closing it quits the app; playback continues in the daemon.
- **Panes:** `sidebar` and `list`; `Tab` switches. Each has its own cursor.
- **Lists:** `TrackList` has a row for every track as soon as the total is
  known. A row is a placeholder until its page arrives, at the same height,
  so nothing moves when data lands. `Library.ensure` claims pages for the
  visible rows plus one screen ahead through `Pages.js`.
- **Search:** `/` opens a field above the list. Every keystroke calls
  `library.search`, superseding the previous request. Results replace the
  list; a result plays inside the list it was found in. `Enter` or `Down`
  moves to the results, `Esc` leaves the field.
- **Theme:** `Theme.qml` watches the active theme's `colors.toml` and the
  user's `shell.toml` (for the font base size) and exposes `foreground`,
  `background`, `accent`, `muted`, `urgent`, fills, spacing and a type scale.
  The font family is `monospace`, which fontconfig resolves to the Omarchy
  font. Not read yet: the theme's own `shell.toml` overrides.
- **Faults:** signed out, offline or no daemon replaces the list with a
  one-line explanation and the key that fixes it.

Planned: a router with back/forward, album and artist views, queue and
devices views, a help overlay, artwork, playlist folders.

## Keymap scopes

| Scope | Used by | Keys |
| --- | --- | --- |
| `player` | everywhere playback is possible | `Space` `n` `p` `+` `-` `m` `←` `→` `s` `r` |
| `mini` | mini-player | `o` |
| `browse` | app | `j` `k` arrows `Enter` `Tab` `g` `G` `PgUp` `PgDn` `/` `R` |
| `signedOut` | signed out | `Enter` signs in |
| `fault` | offline / no daemon | `Enter` retries |
| `any` | always | `Esc` `q` close |

A surface passes a list of scopes, most specific first; `actionFor` returns
the first match and falls back to `any`. The hint bar is generated from the
same list, so it shows exactly what a keypress would do. A test checks that
scopes used together never bind the same key twice.

## Tests

- `tests/tst_client_core.qml`, `tst_loadable.qml`, `tst_keymap.qml`,
  `tst_pages.qml`: 39 tests, run with the Qt 6 `qmltestrunner`.
- `tests/lint.sh`: no colour literals, no network calls in QML, valid manifest.
- UI checks are manual: drive with `wtype`, capture with `grim`.
- Not automated: `DaemonClient.qml` against a real socket, and any view.
