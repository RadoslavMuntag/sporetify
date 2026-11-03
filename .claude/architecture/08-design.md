# 08 · Design milestones

Written 2026-11-03. The roadmap ([06-roadmap.md](06-roadmap.md)) and the plan
([07-plan.md](07-plan.md)) cover what works; this covers how it looks. It
takes over the visual half of phase 4 in the plan. The rules in `CLAUDE.md`
still win: theme tokens only, GPU only, nothing animates while hidden or
paused, every visual has an off switch, and the list is always there.

Each milestone is one branch and ends in something that can be opened and
judged. A milestone is done when its exit checks pass in a dark and a light
theme, with visuals on and off.

## Direction: Field Guide, with the tide pool inside the lens (D16)

Chosen by the owner on 2026-11-03 from four mockups (Tide Pool, Field
Guide, Primordial Pixel, Cover Glow). The owner liked Tide Pool and Field
Guide, and found that Field Guide sits well with Omarchy's own style.

**Field Guide** treats every track as a specimen in a naturalist's
catalogue. Character comes from line work, not effects:

- Hairline rules and column headers, tabular monospace, square keycaps.
- A corner-bracket cursor on the selected row.
- Catalogue numbers taken from the track id (`Specimen.catalogue`, four hex
  digits of its hash) and traits read off its creature ("3 lobes · 2 eyes ·
  7 hairs").
- The creature drawn as line art: an outline in the body colour around a
  pale wash, hairs as fine lines, a stippled nucleus.
- The lens: a round slide with graph paper, the creature under it, and a
  ring of 72 ticks around the rim that is also the progress bar.
- Progress elsewhere as a ruler with ticks every 30 s.

**Tide Pool** survives inside the lens: zooming into it (now playing, the
screensaver) fills it with the drifting pool, its moving light and the
neighbouring tracks' creatures. The app's chrome stays flat and square.

Not taken: Primordial Pixel (its dithered covers could still become a
setting), Cover Glow.

## V0 · Pick a direction (done 2026-11-03)

Recorded as D16 in the README.

## V1 · Foundations (built)

- `app/Theme.qml`: `stroke.hair` / `stroke.bold` line weights and
  `motion.quick` / `motion.standard` (80 and 150 ms).
- Visuals setting with three levels, `full` / `reduced` / `off`
  (`common/Visuals.js`). `v` in the app cycles it; it is saved as
  `visuals` in `~/.config/sporetify/app.json`, and older files that only
  have `creatures` still count. `reduced` draws creatures but keeps them
  still. The plugin still has its on/off `creatures` setting; moving it to
  the three levels is left for V4.
- `common/OnScreen.qml`: whether one of our windows is on a workspace being
  shown (active workspace, open special workspace, or pinned). It asks
  `hyprctl` at start and again on Hyprland's workspace and window events.
  The first version read Quickshell's Hyprland model, which on Hyprland
  0.56 never learns a monitor's workspace until the user switches: every
  window counted as hidden, so nothing moved and no music frames were
  asked for. Found by the owner ("I have a feeling it does not work").
  Animations stop when it is not. Measured on the compact player playing
  on a hidden special workspace: 2 % of a core before, 0 after. The app
  uses it for its now-playing creature too. A window covered by another on
  the same workspace still counts as shown.
- `common/Organism.qml` draws line art (`lineArt`, `ground`, `stroke`) with
  plain items: every lobe grown by the stroke in the body colour, then every
  lobe in the wash on top, so only the outline of the whole body shows.
  `Organism.stipple` gives the nucleus dots.
- `common/Lens.qml`, host-agnostic like the creature (colours passed in).
- `Gallery.qml`: every part in every state, with made-up tracks. It can save
  a picture of itself offscreen (`SPORETIFY_GALLERY_SHOT`), which needs no
  window on the desktop; with `HOME` pointed at a folder holding another
  theme's `colors.toml` it shows that theme.

Checked: gallery rendered in gruvbox (dark) and catppuccin-latte (light).

## V2 · Compact player (built)

The "show it off in a rice screenshot" mode, and the smallest surface on
which to prove the direction before restyling the app.

- `Compact.qml` + `compact/`: its own Quickshell process with app id
  `sporetify-compact`. `sporetify --compact` focuses or starts it,
  `sporetify --compact-toggle` closes or starts it, and the plugin's IPC
  has `toggleCompact` for a Hyprland bind.
- The lens, the catalogue number, title, artist, time and the creature's
  traits; the album too when wide. Lens above the text when square or tall,
  beside it when wide (`Specimen.arrangement`); everything scales with the
  window from about 300 px up.
- Keys from `Keymap.js` (scopes `compact`, `mini`, `player`): the player's
  keys, `o` app, `f` like, `?` the key list, `q` / `Ctrl C` close. `Esc` does
  nothing, so it is never closed by accident. Click the lens to play or
  pause. The only hint on screen is `? keys`, to keep screenshots clean.
- Without a track or with a fault it says why, with the same words as the
  other surfaces (`Faults.js`); the creature rests in the lens.
- With visuals off the lens shows the cover.
- IPC `sporetify.compact`: `act`, `close`, `describe`.

Measured (demo daemon): paused 0.1 % of a core; playing on a hidden
workspace 0; resident memory about 150–190 MB (the app is about 185 MB).
Not yet measured: the cost while visible and playing on a real screen;
that needs the window on the owner's screen.

Not yet: a desktop-widget mode that sits on the wallpaper (layer shell),
and audio reactivity (V3).

## V3 · Pulse (audio tap) (built in the daemon and the compact player)

- `daemon/src/viz.rs`: a `Tap` around the sound server sink passes audio
  through and, only while some connection subscribes to `viz`, runs a
  4096-point FFT summed into 16 bands, and a beat detector, 30 frames a
  second. (The first version used a band-pass filter per band; their
  skirts leaked so much that every frame looked like the same hill around
  the loudest note. A test now requires two far-apart tones to show as two
  bands with a dip between.) Each
  frame is held until its audio is heard (the sink counts what it wrote
  since it started; the sound server plays that back in real time), so
  the picture is not ahead of the sound. Delivered on a lossy stream of
  its own.
- Measured: 0.20 % of one core while analysing (release build, 10 s of
  audio); nothing without a subscriber.
- Compact player: a fine-line spectrum under the lens (above the text when
  wide) and the creature swelling on the beat. It subscribes only while
  visible, playing and at full visuals.
- `scripts/demo-daemon.py` sends made-up frames, so the client side can be
  tried without Spotify.
- Playback on another device has no audio here: the spectrum lies flat on
  its hairline and the creature keeps its slow drift.

Checked on real music (owner's daemon, 2026-11-03): 85 frames in 3 s.
With the compact player on the active workspace it subscribes; moved to a
hidden workspace it reports hidden and unsubscribes; moved back it
resumes.

Tested: the analyser (bands, separation, volume, beats, silence, timing) and the
socket path (subscribe, frame, unsubscribe) in `cargo test`; the compact
player against the demo daemon (subscribes when playing, drops it and
clears when paused).

Not yet: the FFT version on real music (needs the daemon reinstalled),
the cost while visible on a real screen, and the mini-player and app.

## V4 · App chrome

Restyle what already exists in the Field Guide manner, without moving
anything: sidebar, track rows (hairline rules, catalogue numbers), the
corner-bracket cursor, headers with column labels, the now-playing bar
(ruler progress), square keycaps, the hint bar, search and the help
overlay. A specimen plate on the right of the app showing the lens and the
playing creature's traits, hidden when the window is narrow. The plugin's
`creatures` setting becomes the three-level `visuals`.

Exit: every view opened by keyboard in both themes; scrolling a 5 000-track
list is as smooth as before (compare frame times before and after); new
README pictures taken (with the demo daemon, per `CLAUDE.md`).

## V5 · Into the lens: the tide pool

Zoom into the lens (a key in the app, a view of its own) and it fills with
the tide pool: the playing creature drifting in moving light, the previous
and next tracks' creatures at the edges, swimming in or out on a track
change. Built from the same parts as the compact player, which can show it
too.

Exit: the budget in [05-visuals.md](05-visuals.md) met and measured; the
app is complete with the scene off.

## V6 · Motion

The helix loader (bounded by the request deadline, appears only after
~150 ms), the zoom into and out of the lens, press and settle on controls.
All ≤ 150 ms and none delays input.

Exit: every transition off under `reduced` and `off`; input latency
unchanged, measured.

## V7 · Screensaver

From the wishlist: the tide pool full screen, with nothing staying in one
place for long. See whether Omarchy's screensaver hook can launch it.

Exit: an hour left running shows no static element; cost measured.

## V8 · Showcase

New screenshots for the README and the plugin's `preview.png`, a short
clip of the compact player, a "rice" section in the README (compact player
tiled next to a terminal, the window rule, the IPC bind).

Exit: pictures show no real library; the marketplace listing updated with
the owner's go-ahead.
