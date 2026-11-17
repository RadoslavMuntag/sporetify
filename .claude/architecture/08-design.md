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
  pale wash, hairs as fine lines, a thin ring for the nucleus (a stippled
  one was tried and looked bad).
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
- Two settings (`common/Visuals.js`), saved in
  `~/.config/sporetify/app.json`: `visuals` with three levels, `full` /
  `reduced` / `off`, cycled by `v` (`reduced` draws, but still); and
  `creatures`, on or off everywhere (`Shift C`, asked for by the owner): the
  app, the compact player, and the plugin's bar and mini-player, whose
  service reads the same file. Off, a lens shows the cover.
- `common/OnScreen.qml`: whether one of our windows is on a workspace being
  shown (active workspace, open special workspace, or pinned). It asks
  `hyprctl` at start and again on Hyprland's workspace and window events,
  and finds its window by owning process (matching by class found the
  owner's own app window when a second copy ran for a test).
  The first version read Quickshell's Hyprland model, which on Hyprland
  0.56 never learns a monitor's workspace until the user switches: every
  window counted as hidden, so nothing moved and no music frames were
  asked for. Found by the owner ("I have a feeling it does not work").
  Animations stop when it is not. Measured on the compact player playing
  on a hidden special workspace: 2 % of a core before, 0 after. The app
  uses it for its plate and tide pool too. A window covered by another on
  the same workspace still counts as shown.
- `common/Organism.qml` draws line art (`lineArt`, `ground`, `stroke`) with
  plain items: every lobe grown by the stroke in the body colour, then every
  lobe in the wash on top, so only the outline of the whole body shows.
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
- With visuals or creatures off the cover fills the lens, cut to the
  circle with a `MultiEffect` mask (drawn once per cover). Wide windows
  keep the lens under half the width so the text has room.
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

## V4 · App chrome (first pass built)

Built, without moving anything:

- Track lists: an eyebrow over the name (what kind of place, and its
  catalogue number), column labels on lists of tracks, a hairline under
  every row, a corner-bracket cursor in the accent colour over a faint
  fill, `▸` on the playing row, and each track's catalogue number after
  its title when there is room.
- Sidebar ruled off with a hairline.
- Now-playing bar: the cover only; the creature that sat beside it was
  removed at the owner's request (2026-11-04), as the plate already shows
  it. The seek bar is a ruler (`app/Ruler.qml`: a tick every
  10 s, longer every 30 s, a needle), the volume a line slider with a
  needle; square keycaps there and in the hint bar (`KeyCap.corner`).
- Specimen plate (`app/SpecimenPlate.qml`) on the right: the lens, the
  spectrum, title, artist, and the creature's traits and the track's
  length. Shown when the window is at least 1000 px wide, visuals are not
  off, and `i` has not hidden it (saved as `plate` in `app.json`). The
  app subscribes to `viz` only while the plate shows and the track plays.
- `capture` on the app's IPC saves a picture of the window, offscreen too,
  for checking a change in any theme without a window on the desktop.

Checked: pictures in gruvbox and catppuccin-latte against the demo
daemon; `i`, `v` and the music subscription driven over IPC.

Second pass (2026-11-04): no rounded box is left in the app.

- The search bar sits on the background, ruled off underneath: which
  search it is as a small capital label, a ruled field, and the result
  types as tabs whose current one is underlined on that rule.
- The picker and the prompt are `app/Sheet.qml`: a square card with a
  hairline border, an eyebrow over the title, ruled off from the content
  and from the line of keys at its foot. Text is typed on
  `app/Field.qml`, a line that turns heavier and accent-coloured while it
  has focus. The picker's rows are ruled and use the bracket cursor
  (`app/Bracket.qml`, shared with the track list and now the sidebar).
- Help overlay: square keycaps, hairline rules.
- Toast, icon buttons and placeholder rows lost their rounding.
- Search bar, picker, prompt and help overlay moved out of `Main.qml`
  (1170 lines to about 700).

Checked: pictures of each in gruvbox and catppuccin-latte against the
demo daemon; picker, prompt, search filters and help driven over IPC.
Not yet driven by the real keyboard: keys sent by Hyprland to a window
that never had focus are dropped, and the owner was at the desktop.

Not yet: frame times on a 5 000-track list not compared; README pictures
not retaken.

## V5 · Into the lens: the tide pool (built, not yet measured)

Zoom into the lens (a key in the app, a view of its own) and it fills with
the tide pool: the playing creature drifting in moving light, the previous
and next tracks' creatures at the edges, swimming in or out on a track
change. Built from the same parts as the compact player, which can show it
too.

Exit: the budget in [05-visuals.md](05-visuals.md) met and measured; the
app is complete with the scene off.

Built (2026-11-04):

- `common/TidePool.qml`, drawn by `Lens` when `pool` is set (made by a
  `Loader`, so it costs nothing elsewhere): three soft pools of light
  (`Shape` radial gradients, moved by position only, so never
  re-tessellated) that brighten with the low end of the music
  (`Specimen.low`); 14 specks at several depths; the playing creature in
  the middle; the previous and next tracks' creatures dozing (eyes shut)
  at the edges. All of it stays inside the circle by geometry: no clip,
  no layer.
- On a track change the creatures swim one place along (150 ms, the
  transition limit). The pool remembers who sits at each edge itself,
  so a swim never starts with the wrong creature; a jump to an unrelated
  track does not swim. Tested in `tests/tst_tide_pool.qml`.
- The previous track is remembered locally. The next one comes from
  `player.up_next` (`common/UpNext.qml`): one request per track, only
  while a pool shows, superseded by the next; on failure the edge stays
  empty.
- App: `z` opens `app/PoolView.qml` in place of the list and the plate,
  the lens as large as the window allows, the track named under it. Keys
  there are the player's plus `z` / `Esc` back and `?`; the list's keys
  do nothing while it is hidden. A search or a link leaves the pool.
  Creatures off or visuals off: the view shows the cover in the lens.
- Compact player: `z` puts the pool in its lens (not saved).

Checked: `Gallery.qml` row in gruvbox and catppuccin-latte; the view
against the demo daemon over IPC.

Not yet: the cost on a real screen while visible and playing (the
budget is a few percent of one core), and the swim seen in motion; both
need a window on the owner's screen.

Plankton (2026-11-17, D17): the lens's specimen and the pool's three
swimmers are now `common/Plankton.qml`, the organisms from the "Organism
studies" mockup. `common/Plankton.js` grows them (same hash and salts as
the mockup) and packs them into six vec4 uniforms; the fragment shader
`common/shaders/plankton.frag` works out each character cell's light and
picks its glyph from an atlas drawn once from `Text`. Motion is one
`clock` uniform animated only while alive. The shader cuts itself to the
lens's circle (`bound`, `clipAt`). If the shader fails to load, the old
line-art creature is drawn. Not yet: seen on a real screen, its cost
measured, and the tentacles that trail with movement in the mockup
(here they sway in place, as nothing simulates per frame).

## Living ASCII (2026-11-17, D18)

The look moves from Field Guide to Living ASCII, the owner's pick from the
"Living ASCII" mockup. Built in one pass:

- `common/Water.qml`: the pool. `shaders/water.frag` draws the colour
  field, three drifting lights, caustics on a soft far layer, weeds,
  plankton specks and bubbles as characters, with a vignette. Over it the
  playing organism (Plankton.qml) near `home` and the up-next one smaller,
  each gliding on property animations; a blurred copy under them for glow;
  in the compact player one large organism passing out of focus in front.
  One clock for all of it, paused unless alive.
- `common/Glass.qml`: a pane sampling the water behind it (a visible
  `ShaderEffectSource` of its own rectangle, blurred by `MultiEffect`) under
  a tint. A hidden source is never rendered and left the pane empty.
- Compact player: water fills the window, a glass card holds the track
  with an ASCII progress bar; `z` hides the card.
- App: water behind the window; sidebar, list and bar (with hints) are
  glass; the plate and the pool view are open water and the organism
  swims where their lens was.
- Visuals or creatures off: no water, panels opaque, the lens/cover as
  before.

Layout pass (same day): a small gap of water between the glass panes;
the open playlist an accent fill; list rows show the organism's one-line
mark (`Plankton.mark`, e.g. `(¯)~`, `<=>`) in a LIFE column, the cursor
row an accent fill with an accent edge, the playing title bold in accent;
the plate reads THE POOL; the list header's and the bar's covers are
glyph mosaics (`common/GlyphCover.qml`, `shaders/mosaic.frag`). Row
covers stay plain, as a shader per delegate is not a cheap delegate. The
bar keeps its ruler and slider (they are dragged), not the mockup's
character progress and volume.

Checked: GPU captures of both surfaces against the demo daemon in a dark
theme and catppuccin-latte. Not yet: cost measured on a real screen (two
shaders plus a blurred copy and three glass panes are drawn every frame
while playing), the row-size form for lists, and the mockup's glyph
mosaic covers.

Rebuilt like the studies (2026-11-17, owner: the studies' pool was "far
superior": more natural motion, better blur, fuller colour, more
detail). What changed, and why:

- Fields at a texel per character cell, as the studies compute theirs:
  `shaders/organism.frag` and `shaders/pond.frag` write into one small
  texture per layer (`FieldLayer`), each organism only within the box it
  can reach. Cells 4.4 to 7 px (`columns` 140), as the studies.
- Organisms swim: a slow meandering loop about their home, medusae in
  strokes that coast, comb jellies gliding, at the studies' speeds and
  turning no faster than 0.06 rad/s; medusae stay within 20° of upright.
  Tentacles hang and lean back toward where the body came from, by up to
  half with speed, each segment following the path a moment further back
  (the studies' chains). All analytic in `time`: no per-frame script.
- Track change: `Pool.js` keeps each organism in its slot; the new one
  grows (2.5 s) and glides home (4 s), the old shrinks into the queue.
- The studies' water: the gradient, three large blurred discs drifting
  over 48 to 67 s at about 16%, the ripples in the far layer, marine snow,
  four far organisms, a passer-by, the vignette.
- Cost: first build measured 96% GPU busy (app copy, 1400x820 at 1.25x,
  playing). One full-screen pass costs ~10 points here, so: one pass over
  the screen (`compose.frag`), background, far layer and passer merged at
  a third of the size (`underlay.frag`), glow from a quarter-size copy,
  glass reading one 1/6 copy of the scene, no MultiEffect, the pool's clock
  stepped at 30 fps, the water's colour at 4. Measured after: app list
  view 47% busy at 550 MHz, pool view 34%, compact player 13% at 450 MHz
  (of 1200 MHz max); paused 0.4%.

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
