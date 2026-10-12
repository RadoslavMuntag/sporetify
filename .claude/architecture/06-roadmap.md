# 06 · Roadmap

Each milestone ends in something runnable and is not done until its exit
checks pass. Order follows the priorities in `CLAUDE.md`: responsiveness and
the shell controls first, character last.

## M0 · Skeleton (done)

Built: `daemon/` (socket server, deadlines, cancel, panic safety, idle exit,
systemd socket activation), `common/ClientCore.js`, `common/Loadable.js`,
`common/DaemonClient.qml`, `Service.qml`, `BarWidget.qml`, `manifest.json`,
systemd units, dev scripts, 14 protocol tests and 22 QML tests.

The licence (MIT) was added later. The daemon
reports `signed_out` because there is no sign-in yet, and the widget is a plain
glyph that shows state and wakes the daemon on click.

Original scope:

- Repo scaffold, licence, `manifest.json` that passes `omarchy plugin validate .`
- `sporetifyd` accepts the systemd socket, sends `hello`, answers `player.get`
  with a stub, enforces deadlines, supports `cancel`
- `DaemonClient` + `Loadable` + tests against a fake socket
- Bar widget shows a static icon and the daemon status

Exit: `socat` round trip works; killing the daemon shows the error state in the
bar within the deadline and recovers on its own when it returns.

## M1 · Shell controls (the "quick shell" app) (done)

Built and verified live: sign-in through librespot's OAuth with the refresh
token in the keyring (`daemon/src/auth.rs`); playback as a Spotify Connect
device named Sporetify (`daemon/src/player.rs`); `player.*` and `auth.*` ops;
bar widget with track title; mini-player with seek, volume, keycaps and a
hint bar; `common/Keymap.js`; IPC target `sporetify`. Play with nothing loaded
starts the user's liked songs. A cold start (daemon not running) reaches
audible playback in about two seconds.

Added afterwards: MPRIS server (`daemon/src/mpris.rs`; media keys and
`playerctl` verified), resume of volume, track, position and context across
daemon restarts (`daemon/src/persist.rs`), the plugin following playback
started elsewhere, and a README with the bind snippet.

Left over:
- Media keys cannot wake a daemon that has idled out: MPRIS only exists
  while it runs. The bar shortcuts can.
- When another Spotify device takes over, the UI is not told why controls
  stop responding.

Original scope:

- Auth flow and keyring storage (resolves open question 1)
- librespot playback, Connect device, MPRIS server
- Bar widget states, mini-player with transport, seek and volume
- IPC target `sporetify` and documented Hyprland binds
- `Keymap`, `KeyHint`, `HintBar` in the mini-player

Exit: play/pause, next/previous and volume work from the bar, the popup, media
keys and `omarchy shell -q sporetify …`, each with feedback inside one frame;
all of it usable without a mouse.

## M2 · App shell (first version working)

Built and verified live: `App.qml` + `app/` (window tiled by Hyprland with
app id `sporetify`, live Omarchy theme, sidebar of Liked Songs and playlists,
paged track list with placeholders, play a track in its list, now-playing bar
with seek and volume, hint bar, whole-window keyboard handling from Keymap);
`bin/sporetify` launcher (focus or start), menu entry, plugin `toggleApp` and
`o` in the mini-player; daemon `library.playlists`, `library.tracks`,
`player.play_context` (`daemon/src/catalog.rs`). The player logic the plugin
and app share moved to `common/Player.qml`.

Added on `feature/app-views`: history with back/forward, artist pages
(popular tracks, albums, singles), album pages, an up-next list, shuffle and
repeat buttons, a help overlay, and an IPC handle for driving the app.

Also added there: like and unlike (`f`, and a heart in the now-playing bar)
and add to queue (`e`), both without a client id; hearts on liked rows; up
next lists what was queued from here first.

Checked by hand by the owner on 2026-10-12, and reported working: a queued
track playing next, the bar's right and middle click, the search keys and
`Esc`, the heart, shuffle and repeat. (What exactly was covered, such as a
light theme or a second monitor, was not itemised.)

Still to do: a devices view, reading and reordering the queue. Launch time
was measured at about 970 ms and is no longer a goal (decision D14).

Original scope:

- `app/` window, `Theme.qml` with live theme switching, single-instance
  launcher (resolves open questions 2 and 3)
- Router, sidebar, now-playing bar, hint bar, help overlay
- Queue and Devices views (small, exercise the socket path end to end)

Exit: launch budget measured; theme switch applies live in dark and light;
every control reachable by keyboard with a visible hint.

## M3 · Library and search (done, apart from the list below)

Done: track metadata cached on disk for good; Liked Songs indexed in the
background with retries; `library.search` over the cache, with a search box
in the app (`/`). Spotify-wide search works too, without a client id,
through Spotify's GraphQL search service (`search` op, on
`feature/app-views`); the `searchview` endpoints tried first never did.

Added on `feature/library-polish`: playlist folders in the sidebar; the
sidebar and every loaded list saved to disk, so the library opens offline;
background indexing of every playlist; cover art fetched and cached by the
daemon, shown for the playing track and on album and artist pages.

Also there: taller two-line rows with a cover thumbnail on every row of a
list and of search results (track cache moved to `tracks.v3.json`).

Added in phase 1 of [07-plan.md](07-plan.md): a song counts as liked under
any of its versions (matched by title and first artist), so hearts are right
on artist pages and for the playing track, and unliking removes the entry
that is really there; the cover cache is held to 200 MB by dropping the
least recently used; a like button in the mini-player.

Not done: stale-while-revalidate frames, batched metadata lookups, a devices
view, and
telling the user when another device takes over playback (both of the last
two need information librespot does not hand out).

Original scope:

- Cache with stale-while-revalidate (resolves open questions 4 and 5)
- Library, Collection, Artist, Search views on `PagedList`
- Offline behaviour, rate-limit handling, save/unsave with optimistic updates

Exit: app opens to a full library with the network unplugged; the soak test
passes; scrolling a 5 000-track playlist stays smooth.

## M4 · Spore visuals (organisms done)

Built: the organism generator and component, shown in the bar, mini-player
and app, with off switches (see "What exists" in
[05-visuals.md](05-visuals.md)).

Still to do: audio reactivity (needs the daemon's `viz` tap), the helix
loader, the tide-pool now-playing view, zoom transitions, collection-level
visuals (album, artist, playlist), the galaxy view, a `reduced` setting
between on and off, and measuring the cost on integrated graphics.

Original scope:

- Build order from [05-visuals.md](05-visuals.md): organism generator and
  shader, helix, tide pool with `viz`, zoom transitions, then galaxy
- `visuals` setting with `full / reduced / off`

Exit: visual budgets measured and met; nothing renders while hidden or paused;
app verified complete with visuals off.

## Owner's wishlist (noted 2026-10-06)

1. **Heart next to Liked Songs in the sidebar.** Done in phase 2.
2. **"For you" / Discover section.** Done in phase 2: a "For you" entry
   under Liked Songs lists Discover Weekly, Release Radar, daylist, On
   Repeat, Repeat Rewind and the daily mixes. They are found by name through
   Spotify-wide search (owner must be Spotify), because nothing lists them.
3. **Artist radio and "This Is" on artist pages.** Done in phase 2: a "Start
   here" section at the top of an artist page.
4. **Full-screen screensaver** (least important). Not started. A procedural,
   shader-like animation, possibly Spore themed, for people who keep the
   screen on and want to avoid burn-in from a static window: nothing may
   stay in one place for long. Fits with the tide-pool idea in
   [05-visuals.md](05-visuals.md); Omarchy already has a screensaver hook it
   might plug into.

## Playlist editing (added 2026-10-12)

Add a track to one of the user's playlists (`A`, a picker) and remove one
from the playlist on screen (`x`, two presses). Both verified against a real
playlist, which was left as it was found. Not built: creating, renaming and
deleting playlists, reordering tracks, adding several tracks at once.

## M5 · Replace Spotify

- `sporetify.desktop`, `spotify:` URI handling, icon
- Install and uninstall scripts that touch nothing outside the project's own
  files and never edit Hyprland config
- README with setup, binds and screenshots; first tagged release

Exit: a clean Omarchy install can add the plugin, sign in and use Sporetify as
the only Spotify client.
