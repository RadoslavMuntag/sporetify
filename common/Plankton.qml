import QtQuick

import "Plankton.js" as Plankton

// The track's plankton organism on its own, kept in place (a lens, the
// tide pool): an OrganismField that stays near the middle and a GlyphLayer
// that draws it in characters. All of its motion comes from one number,
// `clock`, which runs only while `alive`. Paused, hidden or reduced, the
// organism is drawn still and costs nothing.
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

  readonly property real unit: Math.min(width, height)
  readonly property size grid: Qt.size(Math.max(1, Math.ceil(width / cell)), Math.max(1, Math.ceil(height / (cell * 2))))

  // Seconds. Looping once an hour is a small jump nobody watches for.
  property real clock: 30
  NumberAnimation on clock {
    from: 30
    to: 3630
    duration: 3600000
    loops: Animation.Infinite
    running: true
    paused: !root.alive
  }

  FieldLayer {
    id: organismLayer
    cell: root.cell
    grid: root.grid
    OrganismField {
      seed: root.seed
      kind: root.kind
      wander: false
      radius: root.seed !== "" ? root.unit * (Plankton.size[shape.kind] || 0.25) : 0
      home: Qt.point(root.width / 2, root.height / 2)
      time: root.clock
      cell: root.cell
      bound: root.bound
      clipAt: root.clipAt
      // A dozing organism is a little dimmer.
      amp: root.awake ? 1 : 0.75
      palette: root.palette
      ink: root.ink
      accentColour: root.accent
    }
  }

  GlyphLayer {
    id: glyphs
    anchors.fill: parent
    visible: root.seed !== "" && !failed
    cell: root.cell
    grid: root.grid
    light: root.light
    ink: root.ink
    field: organismLayer.texture
  }

  Loader {
    anchors.fill: parent
    active: glyphs.failed && root.seed !== ""
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
