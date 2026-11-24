# Changelog

Versions follow the plugin's `manifest.json`. The daemon and the plugin are
released together and must be the same version; `scripts/setup.sh` installs
the daemon that matches.

## Not released yet

- The app opens where the playing track was played from: its playlist,
  Liked Songs or album, with the cursor on the track, instead of an empty
  page. When that is not known, it opens the track's album.
- A track link opens its album with the cursor on that track.

## 0.2.0 (2026-11-24)

A new look, a compact player, and fixes to playback and playlists. Version
0.1.2 was never released; its fixes are listed here.

- A new look, Living ASCII: the app and the compact player sit on a pool
  drawn in characters, with light moving through the water, marine snow,
  and glass panes over it. With visuals or creatures off the app is plain
  and flat.
- Every track has a plankton organism of its own, drawn in characters: a
  medusa, comb jelly, radiolarian, volvox colony or diatom. They swim in
  the pool, and on a track change the new one grows and swims to the
  middle.
- Compact player: a small now-playing window for a tiled desktop
  (`sporetify --compact`, or `toggleCompact` from a Hyprland bind).
- `z` opens the tide pool: the playing track's organism, large, in the
  app or in the compact player's lens.
- A plate on the right shows the playing track's organism and its traits
  (`i` hides it).
- The daemon can follow the music for the visuals. It analyses the audio
  only while a window that shows it is open and playing.
- `v` cycles the visuals between moving, still and off, and `Shift C` turns
  the creatures off in the app and the compact player. Visuals turned off
  in an earlier version stay off.
- The track playing in a list is easy to spot, each row shows a small mark
  of its organism, and the progress bar and volume are drawn in characters.
- The search bar, playlist picker, prompts and shortcut overlay match the
  new look. `?` also lists the keys for typing in a field.
- The bar and the mini-player no longer draw a creature. The animated bar
  icon kept the GPU busy even with the app closed. The bar widget's
  Creatures setting is gone with it.
- Animations stop while their window is on a workspace that is not shown.
- A new icon.
- Moving a track never moves the wrong one. If the playlist changed since
  it was shown, nothing moves and the list is reloaded.
- A new playlist appears only once it is complete: a create cut off
  part-way leaves nothing behind, and trying again does not make a
  duplicate.
- Creating or deleting a playlist is no longer reported as failed when
  only the reload of your playlists afterwards was slow.
- The player no longer gets stuck when the network changes under it (a
  cable pulled, a switch to Wi-Fi). It used to keep saying "playing" with
  no sound, and nothing could start it again short of restarting the
  daemon. Now it reconnects once Spotify's connection is found dead (about
  a minute and a half) and carries on from where the sound stopped, if
  that was within the last five minutes. A machine that slept wakes up
  silent.
- Playlists Spotify rewrites on a schedule (Discover Weekly, Release Radar,
  the Daily Mixes, daylist) and playlists edited on another device no
  longer keep the tracks they had when Sporetify first saved them. A saved list
  still opens at once; the app now checks it against Spotify in the
  background and swaps in the new version when it has changed. Reported by
  lutzlstein in #12.

## 0.1.1 (2026-10-13)

Two fixes asked for in the marketplace review.

- The daemon's files are private. The resume point and the library cache
  are written with mode 0600 into folders of mode 0700, the service runs
  with a umask of 077, and files an earlier version left readable by other
  users are closed the next time the daemon starts.
- Setup installs a downloaded daemon only if its SHA-256 is the one
  committed in `scripts/daemon.sha256`, so a release changed after the
  fact is never installed. Without a pinned build it builds from source.

## 0.1.0 (2026-10-12)

First version.

- Bar widget and mini-player: play, pause, skip, seek, volume, like.
- Full app window: library with folders, Liked Songs, "For you", artist and
  album pages, artist radio and "This Is", up next.
- Two searches: all of Spotify (`/`) and your library (`Ctrl F`), filtered
  by songs, artists, albums or playlists.
- Like, queue, and playlist editing: add, remove, reorder, create, rename,
  delete.
- Works offline from the saved library; covers cached on disk.
- Media keys and `playerctl` through MPRIS; playback resumes where it
  stopped.
- A creature generated for every track.
- `b` hides and shows the sidebar.
- Opens `spotify:` links and `open.spotify.com` addresses
  (`sporetify <link>`); has its own icon.
- `scripts/setup.sh` and `scripts/uninstall.sh` for installing from the
  plugin folder.
