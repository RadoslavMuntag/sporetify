# Sporetify

A fast, keyboard-driven Spotify client for Omarchy (Hyprland + Quickshell). It
replaces the official Spotify desktop app and lives in two places:

1. **Shell surface** – an Omarchy shell plugin: bar widget + mini-player popup.
   Scope is deliberately small: play/pause, next/previous, volume, current track.
2. **Full app** – a normal tiled window with library, search, playlists, queue
   and devices. This is what replaces `/usr/bin/spotify`.

Sporetify is its own project with its own identity, code and design. It is not
a fork or port of any other client (see "Independence" at the bottom).

Current state: M0 and M1 are done (sign-in, playback, bar controls,
mini-player, MPRIS, resume); the full app has a working first version
(library sidebar, track lists, play from a list, library search, now-playing
bar); see
`.claude/architecture/06-roadmap.md` for what exists and what is next. This
file holds the rules; the working architecture
plan lives in `.claude/architecture/` (start at its `README.md`). When a
decision changes, update both in the same change.

## Priorities (in this order)

1. **Responsiveness.** No interaction ever waits on the network. Nothing can
   load forever.
2. **Performance.** Low idle CPU, low memory, instant response to every
   action inside the app.
3. **Keyboard first.** Every action has a shortcut and a visible hint.
4. **Native to Omarchy.** Follows the active theme live, behaves like a
   first-party shell plugin.
5. **Character.** Spore-inspired visuals give the app its identity, but never at
   the cost of 1–4.

When two of these conflict, the lower number wins.

## Architecture

```
┌ omarchy-shell (Quickshell) ┐      ┌ sporetify app (own qs process) ┐
│ Service.qml  BarWidget.qml │      │ app/shell.qml  → views         │
│ MiniPlayer.qml             │      │                                │
└──────────┬─────────────────┘      └───────────────┬────────────────┘
           │ MPRIS (transport, volume, metadata)    │
           │ Unix socket, NDJSON (everything else)  │
           └────────────────┬───────────────────────┘
                    ┌───────┴────────┐
                    │  sporetifyd    │  Rust: librespot playback, Web API,
                    │  (systemd user)│  OAuth, cache, MPRIS server
                    └────────────────┘
```

- **`sporetifyd` (Rust)** owns everything slow or stateful: audio (librespot),
  Spotify Web API, auth, disk cache, rate limiting. It exposes MPRIS and a Unix
  socket at `$XDG_RUNTIME_DIR/sporetify.sock`.
- **QML frontends are thin.** They render state and send commands. No HTTP, no
  token handling, no large JSON parsing in QML.
- **The full app is a separate Quickshell process** (`qs -p App.qml`), not a shell
  `panel`. A heavy view or a bug in it must never stall the bar, notifications
  or lock screen, which share the `omarchy-shell` process.
- **No client id of our own.** Sign-in uses librespot's built-in OAuth, and
  library and metadata come from the session's internal API. The public Web
  API answers 429 for that id, so nothing may depend on it (see D11 in the
  architecture README).
- **Frontends drive transport over the socket; the daemon also serves
  MPRIS** (`daemon/src/mpris.rs`) so media keys and `playerctl` work. Both
  paths end in `Playback::command`. The plugin watches MPRIS only to notice
  playback that started while it was disconnected.
- **Search is library search.** Spotify's own search is not reachable without
  a client id (the internal endpoints answer 400), so `library.search` runs
  over cached metadata: Liked Songs, indexed in the background, plus any
  playlist that has been opened.

### Layout

```
manifest.json        Omarchy plugin manifest (must stay at repo root)
Service.qml          plugin service: common/Player plus the `sporetify` IPC target
BarWidget.qml        bar widget
MiniPlayer.qml       popup opened from the bar
App.qml              entry point of the full app (`qs -p App.qml`); at the root so
                     that app/ and common/ are both inside its config folder
app/                 the full app: Main, Theme, Library, Sidebar, TrackList, NowPlayingBar
common/              QML shared by plugin and app: DaemonClient, Player, Keymap.js,
                     Loadable.js, Pages.js, Position.js, HintBar, KeyCap
daemon/              Rust crate `sporetifyd`
systemd/             sporetifyd.socket + .service (socket-activated user units)
scripts/             test.sh, install-dev.sh, uninstall-dev.sh, env.sh
bin/sporetify        launcher: focus the running app or start it
tests/               qmltestrunner tests (tst_*.qml) and lint.sh
.claude/architecture/  architecture plan, protocol draft, visual language, roadmap
```

Keep QML files small and single-purpose (aim under ~400 lines). Pure logic goes
in `.js` libraries so it can be unit tested without a UI.

## Responsiveness rules

These are hard rules. A change that breaks one is a bug even if it "works".

- **Optimistic UI.** A keypress or click updates the visible state in the same
  frame, then sends the command. Reconcile when the daemon confirms; on failure
  roll back and show a short toast. Never disable a control while waiting.
- **Every request has a deadline.** Default 5 s total, 8 s for search and large
  pages. The daemon enforces it and always answers: `ok`, `error`, or `timeout`.
  A request without a deadline must not compile/merge.
- **Every loading state has three exits:** data, stale cached data, or an error
  with a retry action. There is no code path that leaves a spinner up.
- **Stale-while-revalidate.** Library, playlists, albums and artwork are served
  from disk cache immediately and refreshed in the background. Opening the app
  offline shows the last known library, not a loader.
- **Cancel superseded work.** Typing in search, changing view, or scrolling past
  a page cancels the older request (request id + generation counter). A late
  response for an old generation is dropped, never rendered.
- **Events, not polling.** The daemon pushes state changes over the socket.
  Frontends interpolate playback position locally from the last event. No
  timers that fetch.
- **Coalesce bursts.** Volume and seek drags send the first value immediately
  and then at most one per ~80 ms; the last value always lands.
- **Rate limits are the daemon's problem.** Honour `429 Retry-After`, back off
  with jitter, dedupe identical in-flight requests. The UI just sees cached
  data plus a "retrying" state.
- **Nothing blocks the UI thread.** No synchronous `Process` waits, no
  `XMLHttpRequest`, no loops over thousands of items in a binding. Lists are
  virtualised `ListView`s fed in pages; delegates stay cheap.
- **Fail soft.** Daemon down, no network, expired token, no Premium: each has a
  specific message and a one-key recovery action. The bar widget never
  disappears or throws; it degrades to an icon.

### Budgets

| What | Target |
| --- | --- |
| Input to visible feedback | ≤ 1 frame (16 ms), never more than 50 ms |
| Mini-player open | ≤ 100 ms |
| Open a playlist already seen, search, move the cursor | ≤ 1 frame, from cache |
| First page of a playlist never seen | ≤ 1 s, with placeholder rows meanwhile |
| Idle CPU with every surface hidden | ~0 %, no running timers or animations |
| Memory, plugin + daemon while playing | ≤ 80 MB |

App launch time is deliberately not a budget (about one second today). What
has to feel instant is everything done inside the app: playing, browsing,
searching.

Measure before claiming an improvement, and say what was measured.

## Keyboard and hints

- **One source of truth:** `common/Keymap.js` holds a table of
  `{ id, keys, label, scope }`. Key handling, hint badges and the help overlay
  are all generated from it. Never hard-code a key in a view.
- **Hints are always discoverable:** a footer strip lists the actions valid in
  the current context (`Space Play  n Next  / Search  ? Help`); holding a
  modifier shows keycap badges on the matching controls; `?` opens the full
  list. Hints can be turned off in settings, shortcuts keep working.
- Every action reachable by mouse is reachable by keyboard. `Esc` always backs
  out one level and finally closes. Focus is always visible.
- Surfaces handle keys with one `Keys.onPressed` that asks
  `Keymap.actionFor(key, text, scope)` and passes the action to
  `Service.run()`. Do not use `PanelKeyCatcher` from `qs.Ui`: it hard-codes
  its own meanings for Space, arrows and letters.

Default keys (app and mini-player):

| Key | Action | Key | Action |
| --- | --- | --- | --- |
| `Space` | Play / pause | `/` | Search |
| `n` / `p` | Next / previous | `j` `k` / arrows | Move |
| `+` / `-` | Volume ±5 % | `Enter` | Play / open |
| `m` | Mute | `Tab` | Next pane |
| `←` / `→` | Seek ±10 s | `?` | Shortcut help |
| `s` / `r` | Shuffle / repeat | `Esc` / `q` | Back / close |

Global control goes through the plugin's IPC target so Hyprland binds work
without any window open:

```bash
omarchy shell -q sporetify playPause | next | previous | volumeUp | volumeDown | toggleMini | toggleApp
```

`toggleApp` focuses the app window or starts it. Also available: `mute`, `signIn`,
`status`, `nowPlaying`, `wake`.

Hyprland binds belong to the user (`~/.config/hypr/bindings.lua`,
`o.bind("SUPER + SHIFT + M", "Sporetify", "omarchy shell -q sporetify toggleApp")`).
The description string is what shows up in Omarchy's keybinding hints, so always
supply one. Document binds in the README; never edit the user's Hyprland config
from code or an install script. Media keys already work through MPRIS.

## Omarchy compliance

**Plugin**

- Follows the shell plugin contract in `/usr/share/omarchy/shell/README.md`
  (read-only reference; never edit anything under `/usr/share/omarchy/`).
- `manifest.json` at the repo root, `schemaVersion: 1`, kinds `service` +
  `bar-widget`. All user settings are declared in
  `barWidget.schema` with `defaults`, and are read with `root.setting(key, default)`.
  Settings live inline in `~/.config/omarchy/shell.json`; do not invent a
  second config file.
- Build on `qs.Ui` components (`BarWidget`, `PopupCard`, `PanelSlider`,
  `Button`, `KeyboardPanel`, `PanelSeparator`) before writing custom ones.
- Must survive hot reload: saving a file reloads the plugin, so no state that
  cannot be rebuilt from the daemon.
- Works with the bar on any edge (`vertical` bars get the icon-only form).

**Theme**

- No colour, font size or spacing literals in QML. Ever.
- Plugin: `import qs.Commons` and use `Color.foreground / background / accent /
  urgent / muted`, surface roles such as `Color.popups.*`, and `Style.spacing.*`,
  `Style.font.*`, `Style.hoverFill`, `Style.selectedFill` and friends.
- App (separate process, cannot import `qs.Commons`): `app/Theme.qml` is a
  singleton that watches `~/.local/state/omarchy/current/theme/colors.toml`,
  that theme's `shell.toml`, and the user override `~/.config/omarchy/shell.toml`,
  and exposes the same token names. Theme switches apply live, no restart.
- Light themes (`mode = "light"`) must look right; derive contrast from tokens,
  never assume a dark background.
- Window borders, gaps, rounding and opacity belong to Hyprland. No client-side
  decorations, no custom title bar.
- Album-art colours may tint visuals only, never text, controls or chrome.

**Replacing Spotify**

- `sporetify.desktop` with `MimeType=x-scheme-handler/spotify` so `spotify:`
  links open here; `bin/sporetify` focuses the existing window instead of
  starting a second one.
- Requires Spotify Premium (librespot and the Web API both need it). Tokens are
  stored with `secret-tool` in the keyring: never in `shell.json`, the cache,
  logs or the repo.

## Visuals: the Spore language

The look takes its cues from the game *Spore*: life that is procedurally grown,
soft and a little wobbly, seen at scales from a single cell up to a galaxy.
Full detail is in `.claude/architecture/05-visuals.md`; the essentials:

- **Every track is an organism.** A small creature is generated
  deterministically from the track id (same track, same creature, on every
  machine). It drifts in a tide-pool scene on the now-playing view and pulses
  with the music. A tiny version is the bar icon.
- **Scale is the navigation metaphor.** Track = cell, album = creature,
  artist = tribe, playlist = civilisation, all of Spotify = space. Moving
  between levels zooms rather than cuts. The library can be shown as a spiral
  galaxy of stars as an optional view next to the plain list.
- **Organic motion.** Soft blobs, squash-and-stretch on press, gentle drift.
  Loading is a turning double helix, and like any loader it is bounded by the
  request deadline.
- **Inspired, not copied.** No assets, names, logos, fonts, sounds or creature
  designs from the game. Everything is our own procedural art.
- **Theme still rules.** Organisms and scenes are coloured from theme tokens
  (optionally tinted by album art). A list is always available wherever a
  spatial view exists; the visuals decorate the app, they are never the only
  way to do something.

Technical limits for all visuals:

- GPU only: `ShaderEffect` / `MultiEffect` and property animations. No
  per-frame JavaScript, no `Canvas` repaint loops.
- Animate only while visible **and** playing. Hidden, occluded or paused means
  zero frames rendered.
- Every visual has an off switch in settings and the app is fully usable with
  all of them off. Transitions stay ≤ 150 ms and never delay input.

## Commands

```bash
scripts/test.sh          # clippy, daemon tests, QML tests, lint: run before calling work done
scripts/install-dev.sh   # release build to ~/.local/bin, systemd user units, plugin symlink
scripts/uninstall-dev.sh # undo the above

omarchy plugin enable namelessnovice.sporetify   # put the widget in the bar
omarchy shell sporetify status                   # ask the running plugin for its state
omarchy-shell shell rescanPlugins                # force a plugin reload (saves auto-reload)

sporetify                # open the full app (focuses it if already running)
qs -p App.qml            # run the app from the checkout, logs in the terminal

# talk to the daemon by hand
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/sporetify.sock
```

CI: `.github/workflows/ci.yml` runs `scripts/test.sh` and a release build in
an Arch container on every push to `main` and every pull request. Anything a
check needs must therefore be in `scripts/test.sh`, not only run by hand.

Things that bite:

- **Never build into the checkout.** It is symlinked into
  `~/.config/omarchy/plugins/`, where the shell reloads on every file change.
  The scripts set `CARGO_TARGET_DIR` to `~/.cache/sporetify/target`; when
  calling `cargo` directly, `source scripts/env.sh` first.
- **No symlinks anywhere in the repo.** `omarchy plugin validate` rejects them.
- `/usr/bin/qmltestrunner` is Qt 5. Use `/usr/lib/qt6/bin/qmltestrunner`.
- Qt logs to the journal when stderr is not a terminal. Set
  `QT_FORCE_STDERR_LOGGING=1` or failures are silent.
- Shell-side QML warnings: `qs log -p /usr/share/omarchy/shell -t 200`.
- A Quickshell `Socket` never reconnects after a failed attempt; create a new
  one per attempt (see `common/DaemonClient.qml`).
- Quickshell refuses absolute-path imports and warns on modules outside the
  config folder, so shared QML must sit under the config root that uses it.
- `state` is already a property of every QML `Item`; do not reuse the name.
- Running the app prints "Ignoring unresolvable import .../Commons" for
  `BarWidget.qml` and `MiniPlayer.qml`. That is Quickshell scanning the
  plugin's files, which only resolve inside omarchy-shell. Harmless.
- `hyprctl clients` reports logical pixels; multiply by the monitor scale
  before cropping a `grim` screenshot.
- Drive the UI in tests with `wtype` (`wtype j`, `wtype -k Return`).
- **Plugin hot reload is not reliable for this plugin.** The shell keeps a
  running service across reloads, and edited widget files were observed to
  keep their old contents. After changing any plugin QML, run
  `omarchy restart shell`, then confirm with
  `qs ipc -p /usr/share/omarchy/shell show | grep -A12 "target sporetify"`
  and the shell log.
- librespot-core 0.8.0 needs `vergen` 9.0.4 and `vergen-gitcl` 1.0.5 (pinned
  in `daemon/Cargo.lock`); newer ones break its build script. Do not
  `cargo update` blindly.
- The daemon runs on a `LocalSet` because MPRIS callbacks are not `Send`.
  Request handlers run under `tokio::spawn`, where `spawn_local` panics; use
  `tokio::spawn` from them.
- Run a second daemon for experiments with
  `sporetifyd --socket /tmp/x.sock --debug-ops` (stop the service first).
  `debug.mercury` and `debug.spclient` make raw internal-API calls.
- Never `pkill -f` a pattern that also appears in your own command line.
- A Connect device ignores every command except activate until it is active,
  and activation resets its volume. See `Playback::command` in
  `daemon/src/player.rs`.

Before calling work done: `scripts/test.sh` passes and the changed surface was actually opened and driven by keyboard in
both a dark and a light theme (`omarchy theme set <name>`).

## Notes for working here

- **Independence.** Do not copy or adapt code, file structure, naming, UI
  layout, copy text or assets from `../Omarchy-Spotify` or any other Spotify
  client, and do not read it for "how they did it". Design from this spec, the
  Omarchy shell docs, and the upstream docs of the libraries used (Quickshell,
  librespot, Spotify Web API). The only thing that matters about that plugin
  is operational: it is installed as `quickshell.spotify` and also registers a
  Spotify Connect device, so only one of the two should be enabled at a time.
  Ask before disabling it.
- Spotify's Web API is restricted for new apps (several endpoints such as
  recommendations and audio features are unavailable). Check the current API
  reference before designing a feature around an endpoint.
- Plugins run unsandboxed inside `omarchy-shell`. Do not add install hooks,
  network calls from QML, or anything that runs at shell start beyond a cheap
  service mount.
