# Changelog

Versions follow the plugin's `manifest.json`. The daemon and the plugin are
released together and must be the same version; `scripts/setup.sh` installs
the daemon that matches.

## Unreleased

- Compact player: a small now-playing window for a tiled desktop
  (`sporetify --compact`, or `toggleCompact` from a Hyprland bind). The
  track's creature is drawn as line art under a lens whose ring of ticks
  shows how far the song has played.
- The compact player moves with the music: a fine-line spectrum under the
  lens, and the creature swells on the beat. The daemon analyses the audio
  only while a window that shows it is open and playing.
- The app takes on the same look: ruled lists with a bracket cursor and a
  catalogue number for every track, a ruler for the seek bar, square
  keycaps, and a specimen plate on the right with the playing track's
  creature, its traits and the music (`i` hides it).
- `v` in the app now cycles the visuals between moving, still and off, and
  `Shift C` turns the creatures off everywhere: the app, the compact
  player, the bar and the mini-player.
- Creatures stop animating while their window is on a workspace that is
  not shown, not only when it is closed.
- The search bar, playlist picker, prompts and the shortcut overlay are
  square and ruled like the rest of the app.
- `z` in the app opens the tide pool: the playing track's creature, large,
  in moving light, with the previous and next tracks' creatures at the
  edges, swimming one place along on a track change. `z` in the compact
  player shows the same pool in its lens.
- The now-playing bar shows the cover alone; the creature beside it is
  gone (the plate on the right shows it).
- Fixed: turning creatures off while the app or the compact player was
  running left the lens empty instead of showing the cover.
- A new icon in the Field Guide look: the creature grown from the word
  "sporetify", in line art on a round slide, with a play mark for its
  nucleus and the lens's progress arc around it.

## 0.1.2 (not released yet)

Fixes to editing playlists, and to lists that never refreshed.

- Moving a track never moves the wrong one. If the playlist changed since
  it was shown, nothing moves and the list is reloaded.
- A new playlist appears only once it is complete: a create cut off
  part-way leaves nothing behind, and trying again does not make a
  duplicate.
- Creating or deleting a playlist is no longer reported as failed when
  only the reload of your playlists afterwards was slow.
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
