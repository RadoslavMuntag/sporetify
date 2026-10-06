# 04 · Frontends

Two QML frontends share one small library in `common/`. Neither holds state
that cannot be rebuilt from the daemon.

## `common/` (shared)

| File | Role |
| --- | --- |
| `DaemonClient.qml` | `Quickshell.Io.Socket` wrapper: line framing, request table, deadlines, generations, reconnect with backoff, event signals |
| `Loadable.js` | The only loading-state type: `loading`, `ready`, `stale`, `error` (+ retry). Views bind to it and nothing else |
| `Coalescer.js` | First value now, then at most one per interval, last value always sent (volume, seek) |
| `Keymap.js` | The key table and lookup: `{ id, keys, label, scope }` |
| `KeyHint.qml` | Keycap badge drawn next to a control, fed from `Keymap` |
| `HintBar.qml` | Footer strip listing actions valid in the current scope |
| `Position.js` | Interpolates playback position from `{position_ms, at_ms, rate}` |
| `Organism.js` | Pure function: track id → organism parameters (see 05) |
| `Organism.qml`, `Helix.qml` | Shader-backed visuals used by both frontends |

Rules for `common/`: no colour or size literals (tokens are passed in or read
from the theme object the host provides), no network, no host-specific imports
(`qs.Commons` is plugin-only), and every `.js` file is unit tested.

`DaemonClient` contract:

- `request(op, args, { deadline, scope })` returns a handle with `onFrame`,
  `onDone`, `cancel()`.
- A new request in the same `scope` cancels the previous one automatically
  (search-as-you-type, view changes).
- If the socket is down, the request still resolves: with `offline` once its
  deadline passes, or normally if the reconnect wins. A request already sent
  on a connection that then drops fails `offline` immediately.
- The connection is demand-driven: open while `active`, while a request is in
  flight, and for a 10 s linger afterwards; otherwise closed (`link: asleep`).
- A client-side timer mirrors every deadline, so a dead daemon cannot leave a
  request open either.

## Shell plugin

```
manifest.json     kinds: service + bar-widget
Service.qml       MPRIS player lookup, DaemonClient, IpcHandler "sporetify"
BarWidget.qml     icon/organism + optional track text; click or key opens MiniPlayer
MiniPlayer.qml    PopupCard: artwork/organism, title, transport, seek, volume, hint bar
```

- **Transport path:** `Quickshell.Services.Mpris`, filtered to the daemon's
  player. Volume writes go through `Coalescer`.
- **Socket path:** only for `status` (signed out, offline), opening the app,
  and the `viz` subscription while the mini-player is visible.
- **IPC target `sporetify`:** `playPause`, `next`, `previous`, `volumeUp`,
  `volumeDown`, `toggleMini`, `toggleApp`. Each returns a short string
  (`ok`, `starting`, `unavailable`) immediately; none waits on the network.
- **Bar states:** hidden-text icon (nothing loaded), playing, paused,
  starting, offline, signed out, error. Every state has a tooltip that names
  it and the key to fix it.
- **Settings** (manifest `schema`): show track text, max text width, show
  organism in bar, visuals on/off, shortcut hints on/off, volume step.
- **Keyboard:** `PanelKeyCatcher` wraps the mini-player; arrows move between
  controls, the default key table applies, `o` opens the full app, `Esc`
  closes.
- Uses `qs.Ui` components and `qs.Commons` tokens exclusively.

## Full app

```
app/
  shell.qml          window, single-instance IPC target, wiring
  Theme.qml          singleton: Omarchy theme tokens, live reload
  Router.qml         view stack with back/forward and generation scopes
  views/
    Library.qml      playlists, saved albums, artists, liked songs
    Collection.qml   playlist or album: header + virtualised track list
    Artist.qml
    Search.qml
    Queue.qml
    Devices.qml
    Settings.qml
    NowPlaying.qml   the tide-pool scene (05)
    Galaxy.qml       optional spatial library view (05)
  parts/
    Sidebar.qml  NowPlayingBar.qml  TrackRow.qml  PagedList.qml
    Toast.qml    HelpOverlay.qml    StatusBadge.qml
```

- **Window:** one regular toplevel that Hyprland tiles and decorates. No
  client-side decorations. Closing the window hides it if playback is local
  and active; `bin/sporetify` shows it again.
- **Layout:** sidebar, content, now-playing bar, hint bar. `Tab` cycles panes.
- **Router:** each view owns a request scope; leaving a view cancels its
  requests. Back restores scroll position and selection from memory, not from
  a refetch.
- **Lists:** `PagedList` wraps `ListView` with fixed-height delegates,
  fetch-ahead by page, and placeholder rows sized exactly like real ones so
  nothing jumps when data lands.
- **Search:** results update as the daemon answers; each keystroke supersedes
  the previous request. Local cache hits appear before network results.
- **Theme:** `Theme.qml` watches
  `~/.local/state/omarchy/current/theme/colors.toml`, that theme's
  `shell.toml`, and `~/.config/omarchy/shell.toml`, and exposes the same token
  names the shell uses (`foreground`, `background`, `accent`, `urgent`,
  `muted`, spacing and font scales) plus the named palette colours for
  visuals. Parsing happens once per change, not per binding.
- **Single instance:** the app registers an IPC target; `bin/sporetify` calls
  `show` on it and only starts a new process if that fails.

## Keymap scopes

`global` (transport, volume, help, search focus) → `pane` (sidebar, list,
player) → `view` (view-specific actions) → `overlay` (help, menus, dialogs).
Lookup walks from the innermost scope outwards; an overlay blocks everything
beneath it except `global` transport keys. Text fields suspend single-letter
keys while focused.

Hints follow the same walk, so the hint bar always shows exactly what the next
keypress would do.

## Tests

- `tests/tst_*.qml` with `qmltestrunner` for every `.js` library and for
  `DaemonClient` against a fake socket (delays, drops, half-written lines).
- A lint script: no hex colours, no bare pixel literals, no key names outside
  `Keymap.js`, no `XMLHttpRequest`.
- Manual checklist per surface: keyboard-only walkthrough, dark and light
  theme, daemon killed mid-use, network off.
