import QtQuick

import "Plankton.js" as Plankton

// The track's plankton organism, drawn as characters on the GPU
// (shaders/plankton.frag). The shape comes from Plankton.js; all of its
// motion comes from one number, `clock`, which runs only while `alive`.
// Paused, hidden or reduced, the organism is drawn still and costs nothing.
//
// If the shader cannot be loaded the old line-art creature is drawn
// instead, so a lens is never empty.
Item {
  id: root

  property string seed: ""
  // "" for the track's own kind, or one of Plankton.kinds.
  property string kind: ""
  property bool alive: false
  property bool awake: true
  // The theme's palette in Plankton.colourNames order (Theme.creatureColors).
  property var palette: []
  property color ink
  property color accent
  property bool light: false
  // Cell width in px; a cell is twice as tall.
  property real cell: Math.max(4, Math.round(unit / 80))
  // Nothing is drawn outside this circle (in this item's own px, before
  // any scale); a bound of 0 is no limit. A lens passes its own circle, so
  // tentacles end at its rim.
  property real bound: 0
  property point clipAt: Qt.point(width / 2, height / 2)
  // For the fallback creature.
  property color eye
  property color pupil
  property color ground
  property real stroke: 1

  readonly property var shape: Plankton.create(seed, kind)
  readonly property var packed: Plankton.uniforms(shape)
  readonly property real unit: Math.min(width, height)

  function named(name) { return name === "fg" ? ink : Plankton.colour(palette, name, ink) }

  // Seconds. Looping once an hour is a small jump nobody watches for.
  property real clock: 6
  NumberAnimation on clock {
    from: 6
    to: 3606
    duration: 3600000
    loops: Animation.Infinite
    running: true
    paused: !root.alive
  }

  // ---- The glyphs, drawn once into a texture: blank, the brightness ramp,
  //      then the line glyphs for glass spines.
  readonly property string glyphs: " .·:-=+*#%@-|/\\°"
  // Drawn at the cell's own size: shrinking larger glyphs averaged their
  // thin strokes into faint grey.
  readonly property int atlasCell: Math.max(3, Math.round(cell))

  Row {
    id: atlasRow
    Repeater {
      model: root.glyphs.length
      Text {
        required property int index
        width: root.atlasCell
        height: root.atlasCell * 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyphs[index]
        color: root.ink
        font.family: "monospace"
        font.pixelSize: Math.round(root.atlasCell / 0.6)
        font.weight: Font.Medium
      }
    }
  }

  ShaderEffectSource {
    id: glyphAtlas
    sourceItem: atlasRow
    hideSource: true
    smooth: false
    // Redrawn only when a glyph changes, never per frame.
  }

  ShaderEffect {
    id: effect
    anchors.fill: parent
    visible: root.seed !== "" && status !== ShaderEffect.Error
    fragmentShader: "shaders/plankton.frag.qsb"

    property var atlas: glyphAtlas
    property size area: Qt.size(width, height)
    property real bound: root.bound
    property point clipAt: root.clipAt
    property real cell: root.cell
    property real radius: root.unit * Plankton.size[root.shape.kind]
    property real time: root.clock
    property real seed: Plankton.phase(root.seed)
    property real kind: root.packed.kind
    property real light: root.light ? 1 : 0
    property real glyphs: root.glyphs.length
    property vector4d p0: Qt.vector4d(root.packed.p[0].x, root.packed.p[0].y, root.packed.p[0].z, root.packed.p[0].w)
    property vector4d p1: Qt.vector4d(root.packed.p[1].x, root.packed.p[1].y, root.packed.p[1].z, root.packed.p[1].w)
    property vector4d p2: Qt.vector4d(root.packed.p[2].x, root.packed.p[2].y, root.packed.p[2].z, root.packed.p[2].w)
    property vector4d p3: Qt.vector4d(root.packed.p[3].x, root.packed.p[3].y, root.packed.p[3].z, root.packed.p[3].w)
    property vector4d p4: Qt.vector4d(root.packed.p[4].x, root.packed.p[4].y, root.packed.p[4].z, root.packed.p[4].w)
    property vector4d p5: Qt.vector4d(root.packed.p[5].x, root.packed.p[5].y, root.packed.p[5].z, root.packed.p[5].w)
    property color bodyColour: root.named(root.packed.main)
    property color markColour: root.named(root.packed.mark)
    property color glass: root.ink
    property color accent: root.accent
    // The comb rows' light: cyan, blue, magenta, green, yellow.
    property color rain0: root.named("cyan")
    property color rain1: root.named("blue")
    property color rain2: root.named("magenta")
    property color rain3: root.named("green")
    property color rain4: root.named("yellow")
    // A dozing organism is a little dimmer.
    opacity: root.awake ? 1 : 0.75
  }

  Loader {
    anchors.fill: parent
    active: effect.status === ShaderEffect.Error && root.seed !== ""
    sourceComponent: Organism {
      seed: root.seed
      alive: root.alive
      awake: root.awake
      palette: root.palette
      eye: root.eye
      pupil: root.pupil
      lineArt: true
      ground: root.ground
      stroke: root.stroke
    }
  }
}
