import QtQuick
import QtQuick.Window

import "Organism.js" as Organism
import "Plankton.js" as Plankton
import "Pool.js" as Pool

// The Living ASCII pool (D18), built as the organism studies build theirs:
//
//   the water's colour   shaders/backdrop.frag
//   the far layer        ripples of light and small organisms far off,
//                        out of focus
//   the near layer       marine snow, the playing track's organism and the
//                        queue's around it, sharp
//   glow                 a soft copy of the near layer, screened on top
//   a passer-by          one large organism in front, very out of focus
//   calm                 the near layer making room around text on it
//   the vignette         the edges sinking into the deep
//
// Organisms and the water are fields of light over one character grid,
// one value per cell: each layer's fields are drawn together into one
// texture (FieldLayer). They swim by themselves (shaders/organism.frag);
// this item only moves one clock, and only while `alive`. On a track
// change the new organism grows and glides to the middle while the old one
// shrinks back into the queue (see Pool.js).
//
// Cost. On an integrated GPU every full-screen pass is expensive, so there
// is one: everything but the sharp characters is drawn small (a quarter, a
// third, an eighth of the size) and shaders/compose.frag puts it all
// together. The pool is redrawn at most `fps` times a second (its motion
// is slow), the water's colour four times a second, and nothing at all
// while it is still.
//
// Softness. Scaling a small layer up makes it blocky, not soft, and a
// layer of characters drawn small at one point per pixel comes out as hard
// specks. So the small glyph layers average each pixel's glyphs
// (GlyphLayer's `footprint`), and every soft layer goes through one
// Gaussian blur (Blur) at its small size, as the studies' CSS blur does.
// The colour discs fade as a Gaussian too.
//
// `surface` is a small, blurred copy of the whole scene for Glass panes,
// so the water is drawn and blurred once however many panes sit over it.
Item {
  id: root

  property string seed: ""
  // Other tracks to show around it, nearest first (next, queue).
  property var others: []
  property bool alive: false
  property bool awake: true
  // 0 crisp, 1 balanced, 1.9 dreamy.
  property real blur: 1
  // Where the playing organism lives, as fractions of the scene, and how
  // much of the scene's height its space is.
  property point home: Qt.point(0.5, 0.42)
  property real span: 0.6
  // Where the queue's organisms keep their homes, as fractions of the scene.
  property rect roam: Qt.rect(0.12, 0.2, 0.76, 0.55)
  // How much life the water has; small scenes want less.
  property int specks: 40       // flakes of marine snow
  property int bubbles: 0
  property int weeds: 0
  property bool passer: true
  // Where text sits straight on the water, as rects in this item: the
  // near layer's characters and their glow clear away around them, with a
  // ragged edge, so the text reads on open water. Up to three.
  property var calm: []
  property int farCount: 4
  // The open water, in this item: the water's colour and the vignette are
  // laid out over it. Where glass covers part of the scene for good (the
  // app's bar), leave that part out, or the water's darkest part sits
  // under the glass.
  property rect region: Qt.rect(0, 0, width, height)

  property var palette: []
  property color ground
  property color deep
  property color ink
  property color accent
  property color muted
  property bool light: false
  // About this many columns across, cells 4.4 to 7 px wide as in the studies
  // (their large pool has about 6.5 px cells).
  property int columns: 140
  // A whole number of device pixels, so each character is drawn from the
  // atlas one texel per pixel, as sharp as the studies' (GlyphAtlas).
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  property real cell: Math.round(Math.max(4.4, Math.min(7, width / columns)) * dpr) / dpr

  readonly property size grid: Qt.size(Math.max(1, Math.ceil(width / cell)), Math.max(1, Math.ceil(height / (cell * 2))))
  readonly property Item surface: surfaceBlur.texture
  readonly property bool soft: blur > 0

  function colourAt(i, fallback) { return palette && palette.length > i ? palette[i] : fallback }
  function calmAt(i) {
    var r = root.calm && root.calm.length > i ? root.calm[i] : null
    return r && r.width > 0 && r.height > 0 ? Qt.vector4d(r.x, r.y, r.width, r.height) : Qt.vector4d(0, 0, 0, 0)
  }
  function frac(id, salt) { return (Organism.hash(id + "~" + salt) % 1000) / 1000 }

  // Seconds; one clock for everything that moves, stepped `fps` times a
  // second while alive, so the pool is redrawn no more often than that.
  // The slow parts read it in coarser steps and are redrawn less often.
  property int fps: 30
  property real clock: 30
  Timer {
    interval: Math.round(1000 / Math.max(1, root.fps))
    repeat: true
    running: root.alive
    onTriggered: root.clock += interval / 1000
  }
  // The far layer and the passer-by are blurred and slow: ten steps a
  // second look as smooth there and cost half of twenty.
  readonly property real farClock: Math.floor(clock * 10) / 10
  readonly property real colourClock: Math.floor(clock * 4) / 4

  // ---- Who swims where.
  readonly property real mainR: height * span * 0.5
  readonly property var swimmers: {
    var out = root.seed !== "" ? [root.seed] : []
    // Four of the five slots, so the one leaving on a track change can
    // shrink away in the fifth instead of turning into the newcomer.
    for (var i = 0; i < root.others.length && out.length < 4; i++)
      if (root.others[i] && out.indexOf(root.others[i]) === -1) out.push(root.others[i])
    return out
  }
  property var slots: []
  property bool settled: false
  onSwimmersChanged: slots = Pool.assign(slots, swimmers, 5)
  Component.onCompleted: {
    slots = Pool.assign([], swimmers, 5)
    Qt.callLater(function() { root.settled = true })
  }

  // One organism in a slot: the playing one large near `home`, one of the
  // queue smaller about a home of its own, or shrinking away.
  component Swimmer: OrganismField {
    property int slot: 0
    // With no track playing, nobody in the queue takes the playing role.
    readonly property string job: Pool.role(seed, root.seed !== "" ? root.swimmers : [""].concat(root.swimmers))
    readonly property real presence: Plankton.presence[shape.kind] || 0.7
    seed: root.slots.length > slot ? root.slots[slot] : ""
    time: root.clock
    cell: root.cell
    palette: root.palette
    ink: root.ink
    accentColour: root.accent
    amp: job === "main" && !root.awake ? 0.8 : 1

    radius: job === "main" ? root.mainR * presence : job === "queue" ? root.mainR * 0.34 * presence : 0
    Behavior on radius {
      enabled: root.settled && root.alive
      NumberAnimation { duration: 2500; easing.type: Easing.InOutSine }
    }
    property real homeX: job === "main" ? root.home.x * root.width : (root.roam.x + root.frac(seed, "hx") * root.roam.width) * root.width
    property real homeY: job === "main" ? root.home.y * root.height : (root.roam.y + root.frac(seed, "hy") * root.roam.height) * root.height
    Behavior on homeX { enabled: root.settled && root.alive; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    Behavior on homeY { enabled: root.settled && root.alive; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    home: Qt.point(homeX, homeY)
    roam: job === "main"
      ? Qt.size(Math.min(root.width * 0.08, root.mainR * 0.6), Math.min(root.height * 0.08, root.mainR * 0.5))
      : Qt.size(root.roam.width * root.width * 0.3, root.roam.height * root.height * 0.3)
  }

  // A small organism far off: not a track, the same every time.
  component Faraway: OrganismField {
    property int slot: 0
    seed: "far:" + slot
    kind: Plankton.kinds[(slot + 1) % 5]
    time: root.farClock
    cell: root.cell
    palette: root.palette
    ink: root.ink
    accentColour: root.accent
    amp: 0.75
    radius: slot < root.farCount ? root.mainR * (0.2 + root.frac(seed, "r") * 0.14) * (Plankton.presence[kind] || 0.7) : 0
    home: Qt.point((0.08 + root.frac(seed, "x") * 0.84) * root.width, (0.12 + root.frac(seed, "y") * 0.6) * root.height)
    roam: Qt.size(root.width * 0.22, root.height * 0.22)
  }

  // ---- The parts, drawn small and never shown themselves: each is the
  //      source of a ShaderEffectSource that hides it.
  ShaderEffect {
    id: colourFx
    width: root.width
    height: root.height
    fragmentShader: "shaders/backdrop.frag.qsb"
    property size area: Qt.size(width, height)
    property vector4d region: Qt.vector4d(root.region.x, root.region.y, root.region.width, root.region.height)
    property real time: root.colourClock
    property real blur: root.blur
    property color ground: root.ground
    property color deep: root.deep
    property color accent: root.accent
    // blue, magenta and green, as the studies light their water
    property color c0: root.colourAt(2, root.accent)
    property color c1: root.colourAt(3, root.accent)
    property color c2: root.colourAt(0, root.accent)
  }
  ShaderEffectSource {
    id: colourTex
    sourceItem: colourFx
    hideSource: true
    smooth: true
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 4)), Math.max(1, Math.ceil(root.height / 4)))
  }

  Item {
    id: farLayer
    width: root.width
    height: root.height
    FieldLayer {
      id: farField
      cell: root.cell
      grid: root.grid
      PondField {
        part: 1
        time: root.farClock
        grid: root.grid
        ink: root.ink
        accent: root.accent
        muted: root.muted
      }
      Faraway { slot: 0 }
      Faraway { slot: 1 }
      Faraway { slot: 2 }
      Faraway { slot: 3 }
    }
    GlyphLayer {
      anchors.fill: parent
      cell: root.cell
      grid: root.grid
      light: root.light
      ink: root.ink
      field: farField.texture
      footprint: 3
    }
  }
  // Drawn at a third of the size, each pixel the average of the glyphs it
  // covers, then blurred: out of focus as the studies' far layer is (CSS
  // blur 2.6 px, at 0.9), soft characters rather than blobs.
  ShaderEffectSource {
    id: farTex
    sourceItem: farLayer
    hideSource: true
    smooth: true
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 3)), Math.max(1, Math.ceil(root.height / 3)))
  }
  Blur {
    id: farBlur
    width: root.width
    height: root.height
    source: farTex
    textureSize: farTex.textureSize
    sigma: Math.max(0.35, root.blur * 2.6 / 3)
  }

  FieldLayer {
    id: nearField
    cell: root.cell
    grid: root.grid
    PondField {
      part: 2
      time: root.clock
      grid: root.grid
      snow: root.specks
      bubbles: root.bubbles
      weeds: root.weeds
      seed: Organism.hash(root.seed) % 997
      ink: root.ink
      accent: root.accent
      muted: root.muted
      tint: root.colourAt(1, root.accent)
      weedA: root.colourAt(0, root.accent)
      weedB: root.colourAt(1, root.accent)
    }
    Swimmer { slot: 0 }
    Swimmer { slot: 1 }
    Swimmer { slot: 2 }
    Swimmer { slot: 3 }
    Swimmer { slot: 4 }
  }

  // The near layer's light, a quarter of the size and blurred, for the
  // glow: the studies' bloom (a half-size copy, CSS blur 7 px, screened
  // over the scene). Each cell's share of ink stands in for its glyph
  // (shaders/glowfield.frag); blurred this much, they look the same.
  ShaderEffect {
    id: glowLayer
    width: root.width
    height: root.height
    fragmentShader: "shaders/glowfield.frag.qsb"
    property var field: nearField.texture
    property size area: Qt.size(width, height)
    property size grid: root.grid
    property real cell: root.cell
    property real light: root.light ? 1 : 0
  }
  ShaderEffectSource {
    id: glowTex
    sourceItem: glowLayer
    hideSource: true
    smooth: true
    live: root.soft
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 4)), Math.max(1, Math.ceil(root.height / 4)))
  }
  Blur {
    id: glowBlur
    width: root.width
    height: root.height
    source: glowTex
    live: root.soft
    textureSize: glowTex.textureSize
    sigma: (3 + root.blur * 4) / 4
  }

  Item {
    id: passerLayer
    width: root.width
    height: root.height
    FieldLayer {
      id: passerField
      cell: root.cell
      grid: root.grid
      OrganismField {
        seed: "near:passer"
        kind: "medusa"
        time: root.farClock
        cell: root.cell
        palette: root.palette
        ink: root.ink
        accentColour: root.accent
        amp: 0.9
        radius: root.passer && root.soft ? root.mainR * 1.5 * 0.72 : 0
        home: Qt.point(root.width * 0.06, root.height * 0.72)
        roam: Qt.size(root.width * 0.12, root.height * 0.1)
      }
    }
    GlyphLayer {
      anchors.fill: parent
      cell: root.cell
      grid: root.grid
      light: root.light
      ink: root.ink
      field: passerField.texture
      footprint: 8
    }
  }
  // An eighth of the size and blurred: very out of focus (CSS blur 9 px).
  ShaderEffectSource {
    id: passerTex
    sourceItem: passerLayer
    hideSource: true
    smooth: true
    live: root.passer && root.soft
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 8)), Math.max(1, Math.ceil(root.height / 8)))
  }
  Blur {
    id: passerBlur
    width: root.width
    height: root.height
    source: passerTex
    live: root.passer && root.soft
    textureSize: passerTex.textureSize
    sigma: root.blur * 9 / 8
  }

  // The water's colour and the far layer together, a third of the size.
  ShaderEffect {
    id: underFx
    width: root.width
    height: root.height
    fragmentShader: "shaders/underlay.frag.qsb"
    property var back: colourTex
    property var far: farBlur.texture
    property real farAlpha: 0.9
  }
  ShaderEffectSource {
    id: underTex
    sourceItem: underFx
    hideSource: true
    smooth: true
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 3)), Math.max(1, Math.ceil(root.height / 3)))
  }

  GlyphAtlas {
    id: glyphAtlas
    cell: root.cell
    ink: root.ink
  }

  // ---- Everything together: the one pass over the screen.
  ShaderEffect {
    id: scene
    anchors.fill: parent
    fragmentShader: "shaders/compose.frag.qsb"
    property var under: underTex
    property var near: nearField.texture
    property var atlas: glyphAtlas
    property var glow: glowBlur.texture
    property var passer: passerBlur.texture
    // The studies' passer-by: blur 9 px, at 0.45 (balanced).
    property real passerAlpha: root.passer && root.soft ? root.blur * 0.45 : 0
    property size area: Qt.size(width, height)
    property size grid: root.grid
    property real cell: root.cell
    property real light: root.light ? 1 : 0
    property real glyphs: glyphAtlas.glyphs.length
    // Screened on as the studies' bloom (0.62 at balanced), but stronger:
    // this glow is blurred at a quarter of the size, not half, so it comes
    // out wider and fainter; at 0.76 it added about 0.7 of the studies'
    // light around the same kind of organism (measured 2026-11-22).
    property real glowStrength: root.soft ? Math.min(1, 0.45 + root.blur * 0.45) : 0
    property color deep: root.deep
    property size inset: glyphAtlas.inset
    property vector4d calm0: root.calmAt(0)
    property vector4d calm1: root.calmAt(1)
    property vector4d calm2: root.calmAt(2)
    property vector4d region: Qt.vector4d(root.region.x, root.region.y, root.region.width, root.region.height)
  }

  // ---- A small copy of the whole scene, blurred once for every pane of
  //      glass (the studies' backdrop-filter: blur 13 px). It has no size
  //      of its own, so it is never shown.
  ShaderEffectSource {
    id: surfaceCopy
    sourceItem: scene
    textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 6)), Math.max(1, Math.ceil(root.height / 6)))
    smooth: true
  }
  Blur {
    id: surfaceBlur
    width: root.width
    height: root.height
    source: surfaceCopy
    textureSize: surfaceCopy.textureSize
    sigma: (2 + root.blur * 11) / 6
  }
}
