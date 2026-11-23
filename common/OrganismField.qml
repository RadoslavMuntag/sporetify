import QtQuick

import "Plankton.js" as Plankton

// One organism as a field of light, inside a FieldLayer
// (shaders/organism.frag). The item covers only the box the organism can
// reach (snapped to whole cells), so a layer of several organisms costs
// little more than one. It swims about `home` by itself; the host moves
// `time`.
ShaderEffect {
  id: root

  property string seed: ""
  // "" for the track's own kind, or one of Plankton.kinds.
  property string kind: ""
  // R, px; 0 draws nothing.
  property real radius: 0
  property point home: Qt.point(0, 0)
  // How far it roams each way, px; with `wander` off it stays at home.
  property size roam: Qt.size(0, 0)
  property bool wander: true
  // 0..1: how brightly it is drawn.
  property real amp: 1
  property real time: 0
  property real cell: 6
  // A circle to draw inside (a lens), px; a bound of 0 is no limit.
  property real bound: 0
  property point clipAt: Qt.point(0, 0)
  property var palette: []
  property color ink
  property color accentColour

  readonly property var shape: Plankton.create(seed, kind)
  readonly property var packed: Plankton.uniforms(shape)
  function named(name) { return name === "fg" ? ink : Plankton.colour(palette, name, ink) }

  // How far it can reach from where it is, in R.
  readonly property real reach: {
    switch (shape.kind) {
    case "medusa": return shape.tentacleLength + 1.6
    case "ctenophore": return shape.form === "cydippid" ? shape.tentacleLength + 1.6 : 1.3
    case "radiolarian": return shape.podLength * 1.2 + 0.2
    }
    return 1.4
  }
  readonly property real spanX: (wander ? roam.width * 1.35 : radius * 0.1) + radius * (reach + 1)
  readonly property real spanY: (wander ? roam.height * 1.35 : radius * 0.1) + radius * (reach + 1)
  readonly property real layerW: parent ? parent.width : 0
  readonly property real layerH: parent ? parent.height : 0
  readonly property real x0: Math.max(0, Math.floor((home.x - spanX) / cell) * cell)
  readonly property real y0: Math.max(0, Math.floor((home.y - spanY) / (cell * 2)) * cell * 2)
  readonly property real x1: Math.min(layerW, Math.ceil((home.x + spanX) / cell) * cell)
  readonly property real y1: Math.min(layerH, Math.ceil((home.y + spanY) / (cell * 2)) * cell * 2)

  visible: radius >= cell * 0.9 && seed !== "" && x1 > x0 && y1 > y0
  x: x0
  y: y0
  width: Math.max(cell, x1 - x0)
  height: Math.max(cell * 2, y1 - y0)
  // Written as data, not blended: the alpha is a code (see the shader).
  blending: false
  fragmentShader: "shaders/organism.frag.qsb"

  property point origin: Qt.point(x, y)
  property size box: Qt.size(width, height)
  property real wanderOn: wander ? 1 : 0
  property real phase: Plankton.phase(seed)
  property real kindIndex: packed.kind
  property vector4d p0: Qt.vector4d(packed.p[0].x, packed.p[0].y, packed.p[0].z, packed.p[0].w)
  property vector4d p1: Qt.vector4d(packed.p[1].x, packed.p[1].y, packed.p[1].z, packed.p[1].w)
  property vector4d p2: Qt.vector4d(packed.p[2].x, packed.p[2].y, packed.p[2].z, packed.p[2].w)
  property vector4d p3: Qt.vector4d(packed.p[3].x, packed.p[3].y, packed.p[3].z, packed.p[3].w)
  property vector4d p4: Qt.vector4d(packed.p[4].x, packed.p[4].y, packed.p[4].z, packed.p[4].w)
  property vector4d p5: Qt.vector4d(packed.p[5].x, packed.p[5].y, packed.p[5].z, packed.p[5].w)
  property color bodyColour: named(packed.main)
  property color markColour: named(packed.mark)
  property color glass: ink
  // The comb rows' light: cyan, blue, magenta, green, yellow.
  property color rain0: named("cyan")
  property color rain1: named("blue")
  property color rain2: named("magenta")
  property color rain3: named("green")
  property color rain4: named("yellow")
}
