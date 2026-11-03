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
