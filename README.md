# Sporetify

A fast, keyboard-first Spotify client for [Omarchy](https://omarchy.org/):
transport and volume in the bar, a mini-player under it, and a full app
window for your library. Needs Spotify Premium. No Spotify developer app or
client ID is required.

Status: early. Playback, your playlists, Liked Songs, library search, artist
and album pages, likes, add to queue, an up-next list and search across all
of Spotify work. Artwork does not exist yet.

## Install (development)

```bash
scripts/install-dev.sh
omarchy plugin enable namelessnovice.sporetify
```

This builds the daemon into `~/.local/bin`, installs two systemd user units,
links the checkout as an Omarchy shell plugin and adds a `sporetify` launcher.
`scripts/uninstall-dev.sh` removes all of it.

The first time, click the bar icon and choose **Sign in to Spotify**; the
login is kept in your desktop keyring.

## Use

| Where | How |
| --- | --- |
| Full app | `sporetify`, the application menu, or `o` in the mini-player |
| Mini-player | click the bar icon |
| Play / pause | middle-click the bar icon, or your media keys |
| Volume | scroll on the bar icon |

Each track has its own small creature, grown from the track itself, shown
beside it while it plays. Turn them off with `v` in the app or the Creatures
setting of the bar widget.

Every surface lists its shortcuts in a footer. The main ones:

| Key | Action | Key | Action |
| --- | --- | --- | --- |
| `Space` | Play / pause | `/` | Search all of Spotify |
| `Tab` (in search) | Songs / artists / albums / playlists | `Ctrl F` | Search your library |
| `n` / `p` | Next / previous | `j` `k` / arrows | Move |
| `+` / `-` | Volume | `Enter` | Play / open |
| `m` | Mute | `Tab` | Switch pane |
| `a` / `d` | Artist / album of a track | `u` | Up next |
| `f` | Like / unlike | `e` | Add to queue |
| `Backspace` | Back | `?` | Every shortcut |
| `←` / `→` | Seek 10 s | `Esc` / `q` | Close |

## Keybinds

Sporetify never edits your Hyprland config. To bind keys yourself, add lines
like these to `~/.config/hypr/bindings.lua`, then run `hyprctl reload` and
check `hyprctl configerrors`:

```lua
o.bind("SUPER + SHIFT + M", "Sporetify", "omarchy shell -q sporetify toggleApp")
o.bind("SUPER + ALT + M", "Sporetify mini-player", "omarchy shell -q sporetify toggleMini")
```

`SUPER + SHIFT + M` is Omarchy's stock Music binding; put
`hl.unbind("SUPER + SHIFT + M")` before the first line to replace it.

Other commands the same way: `playPause`, `next`, `previous`, `volumeUp`,
`volumeDown`, `mute`.

## Licence

MIT, see `LICENSE`. Sporetify is not affiliated with Spotify. It signs in
through librespot and uses Spotify's internal API, which is unofficial and can
stop working at any time.

## Development

See `CLAUDE.md` for the rules and `.claude/architecture/` for the design.
`scripts/test.sh` runs every check.
