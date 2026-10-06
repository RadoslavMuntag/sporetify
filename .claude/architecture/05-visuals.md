# 05 · Visual language (Spore-inspired)

The idea borrowed from *Spore* is a feeling, not its assets: life that is
**procedurally grown**, **soft and slightly wobbly**, and seen at **scales from
a cell to a galaxy**. Nothing from the game is reused: no art, names, logos,
fonts, sounds or recognisable creature designs.

## Scale as metaphor

| Spore stage | Sporetify level | Where it shows |
| --- | --- | --- |
| Cell | Track | Organism in the bar, mini-player and now-playing scene |
| Creature | Album | Album header: the organisms of its tracks gathered as one body |
| Tribe | Artist | Artist page: a cluster of that artist's creatures |
| Civilisation | Playlist | Playlist header: a colony pattern built from its tracks |
| Space | Library / all of Spotify | Optional galaxy view of the library; search as "looking outward" |

Moving between levels uses a short zoom (≤ 150 ms) in the matching direction:
opening an album from a track zooms out, opening a track zooms in. With
visuals off the same navigation is an instant cut.

## Organisms

Each track id is hashed into a seed, and `common/Organism.js` turns the seed
into a small parameter set:

- body: 2–5 soft lobes (metaball centres and radii)
- symmetry: bilateral or radial
- appendages: count and length of cilia or a tail
- eyes: 0–3, size and spacing
- palette slots: which theme colours the body, core and accents use
- temperament: drift speed, wobble amount, how strongly it reacts to the beat

Properties:

- **Deterministic.** Same id, same organism, everywhere. The function is pure
  and unit tested with fixed seeds.
- **Cheap.** One fragment shader draws the whole organism from about twenty
  uniforms. No textures, no per-frame JavaScript.
- **Scalable.** The same shader renders at 16 px in the bar (simplified: body
  and one eye) and at several hundred px in the now-playing scene.
- **Composable.** Album, artist and playlist visuals are arrangements of
  member organisms, capped at a fixed count so cost does not grow with size.

## Scenes

**Bar cell.** The current track's organism as the widget icon. Playing: slow
breathing. Paused: still, eyes closed. Starting: helix. Offline or signed out:
desaturated towards `muted`. Falls back to a plain glyph when visuals are off
or the bar is too small.

**Tide pool (now playing).** The organism drifts in a soft-lit pool with a few
out-of-focus particles for depth. Band energies swell the lobes, the beat pulse
gives a small squash-and-stretch. The previous and next tracks' organisms sit
at the edges and swim in or out on track change.

**Evolution line (progress).** The seek bar is a thin timeline; the played
part is drawn as a growing strand. Functionally an ordinary slider with
ordinary hit targets and keyboard seeking.

**Helix (loading).** A turning double helix replaces the generic spinner.
It only appears after ~150 ms of waiting and always ends at the request
deadline in data, stale data or an error.

**Galaxy (optional library view).** Playlists, albums or artists as stars on a
spiral, placed by a stable hash so the map never reshuffles; size by track
count, brightness by recency. Fully keyboard navigable (arrows move to the
nearest star in that direction, `Enter` opens, `/` filters) and always one key
away from the plain list.

**Micro-motion.** Buttons squash slightly on press, toggles settle with a
small overshoot, rows slide rather than pop. All ≤ 150 ms, none blocking
input.

## Colour

- Organisms and scenes take their colours from theme tokens: body from
  `accent`, core and eyes from `foreground`/`background`, detail colours from
  the theme's named palette (the app has all of them; the plugin, which only
  gets the shell's five base colours, derives details by mixing those).
- Optional album-art tint: one dominant colour extracted by the daemon when it
  caches artwork, blended into the organism only. Text, controls and chrome
  never take colour from artwork.
- Must read correctly in light themes; contrast is computed from tokens, not
  assumed.

## Audio reactivity

- Source: the daemon's `viz` events (band energies + beat), about 30 Hz.
- QML feeds them straight into shader uniforms through a smoothing
  `Behavior`; the shader does the rest.
- When playback is on another device there is no audio tap; scenes fall back
  to a tempo-free idle drift.

## Budget and switches

- A visible, playing tide pool should cost no more than a few percent of one
  core on integrated graphics. Measure it; if it cannot be met, simplify the
  shader before anything else.
- Zero frames when the surface is hidden, the window is not visible, or
  playback is paused (a paused scene renders one still frame).
- Settings: `visuals` = `full` / `reduced` (no audio reactivity, no drift) /
  `off`. The app must be complete and pleasant at `off`.

## Build order

1. `Organism.js` + tests (pure, no UI).
2. Organism shader at one size; then the bar-size simplification.
3. Helix loader.
4. Tide pool with `viz`.
5. Zoom transitions.
6. Galaxy view (only if question 7 in the README has a good answer).
