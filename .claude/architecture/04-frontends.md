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

Also here: `Organism.js` and `Organism.qml`, the per-track creature; see
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
manifest.json     kinds: service + bar-widget; settings: showTrackTitle, maxTitleWidth, creatures
Service.qml       Player + IPC target "sporetify" + MPRIS watch + openApp()
BarWidget.qml     icon and track title; owns the mini-player
MiniPlayer.qml    KeyboardPanel: title, seek, transport, volume, keycaps, hint bar
```

- **Bar widget:** left click toggles the mini-player, right click plays or
  pauses, middle click opens the full app, the wheel changes volume. The tooltip names the state and, on a
  fault, the reason. On a vertical bar only the icon is shown.
- **Service:** connected while the mini-player is open or music plays. It
  also watches MPRIS for the "Sporetify" player, so playback started by media
  keys or the app wakes the connection.
- **IPC target `sporetify`:** `playPause`, `next`, `previous`, `volumeUp`,
  `volumeDown`, `mute`, `toggleMini`, `toggleApp`, `signIn`, `status`,
  `nowPlaying`, `wake`. All return at once.
- **Mini-player:** one `Keys.onPressed` asks `Keymap.actionFor` with scopes
  `["mini", "player", "popup"]`. `o` opens the full app and `f` likes the
  playing track (a heart beside the transport buttons shows the state). Built on `KeyboardPanel`,
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
  Library.qml        model: playlists, the place on screen, its rows, history
  Sidebar.qml        Liked Songs and playlists
  TrackList.qml      header and the virtualised track list
  NowPlayingBar.qml  track, transport, seek, volume
  IconButton.qml  Slider.qml
bin/sporetify        focus the window if it exists, otherwise start the app
```

- **Window:** one `FloatingWindow` with app id `sporetify`; Hyprland tiles and
  decorates it. Closing it quits the app; playback continues in the daemon.
- **Panes:** `sidebar` and `list`; `Tab` switches. Each has its own cursor.
- **Places:** the list shows one place at a time: a playlist, search
  results, an album, an artist or up next. `Library.qml` turns each into a
  flat list of rows (tracks, plus `heading` and `album` rows on an artist
  page) and keeps a history: `Backspace` or `[` goes back, `]` forward, and
  the cursor returns to where it was.
- **Artist pages** start with a "Start here" section when Spotify has them:
  the artist's "This Is" playlist and their radio. Then popular tracks,
  albums, singles.
- **Getting around:** `a` opens the artist and `d` the album of the row under
  the cursor, or of the playing track when the cursor is not on a track;
  clicking the title or artist in the now-playing bar does the same. `u`
  opens up next. `Enter` on an album row opens it.
- **Like and queue:** `f` likes or unlikes and `e` queues the track under
  the cursor. In the list pane they act only on that row; on a heading or
  album row they say so instead of acting on something else. From the
  sidebar pane, and from the heart in the now-playing bar, they act on the
  playing track. A like shows at once and is put back if Spotify refuses. A
  one-line toast names the track that was affected.
- **Editing playlists** (the user's own only):
  - `V` selects the track under the cursor and moves down; the header counts
    the selection and `Esc` clears it. Add and remove act on the selection,
    or on the cursor's track when nothing is selected.
  - `A` opens a picker: type to narrow the user's playlists, `Enter` to add.
    When something is typed the last row creates a playlist of that name
    with the tracks in it (last, so a name that exists adds to it).
  - `N` asks for a name and creates an empty playlist.
  - `x` or `Delete` removes tracks from the playlist on screen; with the
    sidebar focused it deletes the playlist under the cursor. Both take two
    presses: the first names what would go, the second, within a few
    seconds, does it.
  - `J` / `K` move the track under the cursor down or up. The row moves at
    once; the moves are sent one at a time in order, and a failure reloads
    the playlist.
  - `F2` renames the playlist under the sidebar's cursor, or the one on
    screen.
- **Lists:** a playlist has a row for every track as soon as the total is
  known; a row is a placeholder until its page arrives, at the same height.
  `Library.ensure` claims pages for the visible rows plus one screen ahead
  through `Pages.js`. Other places arrive whole.
- **Search:** two searches share one field. `/` searches all of Spotify,
  `Ctrl F` the user's library; the field shows which one is active and keeps
  the text when switching. Each is its own place in the history. Under the
  field a row of chips picks the kind of result: All, Songs, Artists, Albums
  or Playlists. `Tab` and `Shift Tab` walk the chips while typing, `t` does
  from the results, and they can be clicked. With All, each kind is a
  section under a heading; with one kind, Spotify is asked for 50 of it.
  - Spotify is asked once typing pauses (280 ms), from two characters on.
  - The library answers on every key. Its artists and albums are the ones
    named by matching tracks; its playlists are matched by name.
  - A library song plays inside the list it was found in, a Spotify song
    inside its album.
  - `Esc` cancels the search from the field or the results: the bar closes
    and the last place that was not a search comes back.
- **Leaving:** `Ctrl C` quits the app, as does closing the window. `Esc` and
  `q` do not: in the app `Esc` only cancels a search. (In the mini-player,
  a popup, `Esc` and `q` still close it.)
- **Sidebar:** Liked Songs (with a heart), "For you" (the playlists Spotify
  makes for the user), then playlists and folders. A folder folds and
  unfolds with `Enter`; which ones are folded is kept in the preferences.
- **Offline:** not a fault. The sidebar says it is showing what was saved,
  playlists and library search work from the daemon's files, and anything
  that needs Spotify says why it failed in a toast.
- **Covers:** shown from files the daemon fetched: the playing track's in
  the now-playing bar and mini-player, the album's or artist's beside the
  title of its page, and a thumbnail on every row of a list.
- **Rows:** tall enough for a thumbnail and two lines: the title over the
  artists (or over what kind of thing the row opens), then the album, a
  liked or queued mark and the duration. Album pages show no thumbnails,
  since every row would be the same picture. `c` turns thumbnails off.
  A row asks for its cover only after staying on screen for 140 ms, four
  are fetched at a time, and covers still waiting are dropped when the
  place changes; a cover already on disk comes with the row and costs no
  request at all.
- **Now-playing bar:** cover, creature, title, artist, shuffle and repeat (lit when
  on), transport, seek, volume.
- **Help:** `?` shows every key valid right now; the footer shows only the
  ones marked `primary` in the keymap. Any key closes the overlay.
- **IPC:** target `sporetify.app` with `act <action>`, `searchFor <text>`,
  `searchLibrary <text>`, `searchType <kind>`, `addTo <playlist> <track uris>`,
  `answer <text>` (for the open picker or prompt), `sidebarTo <name>` and
  `describe` (what is on screen, as JSON, including the `subject` that like
  and queue would act on). Tests drive the app through it,
  which needs no key injection and works with the screen off.
- **Theme:** `Theme.qml` watches the active theme's `colors.toml` and the
  user's `shell.toml` (for the font base size) and exposes `foreground`,
  `background`, `accent`, `muted`, `urgent`, fills, spacing and a type scale.
  The font family is `monospace`, which fontconfig resolves to the Omarchy
  font. Not read yet: the theme's own `shell.toml` overrides.
- **Faults:** signed out, offline or no daemon replaces the list with a
  one-line explanation and the key that fixes it.

Planned: a devices view, reordering the queue.

## Keymap scopes

| Scope | Used by | Keys |
| --- | --- | --- |
| `player` | everywhere playback is possible | `Space` `n` `p` `+` `-` `m` `←` `→` `s` `r` |
| `mini` | mini-player | `o` `f` |
| `browse` | app | `j` `k` arrows `Enter` `Tab` `g` `G` `PgUp` `PgDn` `/` `Ctrl F` `t` `a` `d` `u` `f` `e` `A` `x` `V` `J` `K` `N` `F2` `⌫` `[` `]` `R` `v` `c` `?` |
| `signedOut` | signed out | `Enter` signs in |
| `fault` | offline / no daemon | `Enter` retries |
| `popup` | mini-player | `Esc` `q` close |
| `app` | app | `Esc` cancel search, `Ctrl C` quit |

Keys held with Ctrl are separate keys (`Ctrl+f` in the table), so a chord
never triggers the plain letter's action. Surfaces pass the event's
modifiers to `actionFor`.

A surface passes a list of scopes, most specific first; `actionFor` returns
the first match. The hint bar is generated from the
same list, so it shows exactly what a keypress would do. A test checks that
scopes used together never bind the same key twice.

## Tests

- `tests/tst_client_core.qml`, `tst_loadable.qml`, `tst_keymap.qml`,
  `tst_pages.qml`, `tst_organism.qml`: 45 tests, run with the Qt 6 `qmltestrunner`.
- `tests/lint.sh`: no colour literals, no network calls in QML, valid manifest.
- UI checks are manual: drive with `wtype`, capture with `grim`.
- Not automated: `DaemonClient.qml` against a real socket, and any view.
