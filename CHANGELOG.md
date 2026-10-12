# Changelog

Versions follow the plugin's `manifest.json`. The daemon and the plugin are
released together and must be the same version; `scripts/setup.sh` installs
the daemon that matches.

## 0.1.0 (not released yet)

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
