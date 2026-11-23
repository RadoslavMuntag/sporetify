import QtQuick

// A pane of glass over the Living ASCII water (D18): whatever swims behind
// it, softened, its colour lifted and lightly tinted, so text on it stays
// readable while the pool shows through as colour (shaders/glass.frag).
//
// It reads the water from `surface`, Water's small copy of the whole scene,
// so the water is drawn once however many panes there are. `area` is this
// pane's rectangle in the scene, `scene` the scene's size; the host knows
// both (pane and water are usually children of one item) and passes them,
// so nothing is mapped per frame. Without a surface the pane is plain.
Item {
  id: root

  property Item surface: null
  property size scene: Qt.size(1, 1)
  property rect area: Qt.rect(x, y, width, height)
  // 0 crisp, 1 balanced, 1.9 dreamy; at 0 the pane is plain.
  property real blur: 1
  property color tint
  property color edge
  property bool light: false
  property real radius: 0

  readonly property bool sampling: blur > 0 && surface !== null

  ShaderEffect {
    anchors.fill: parent
    fragmentShader: "shaders/glass.frag.qsb"
    property size extent: Qt.size(width, height)
    property rect pane: root.area
    property size scene: root.scene
    property real radius: root.radius
    property real blur: root.blur
    property real sampling: root.sampling ? 1 : 0
    // The mockup's glass: the background colour at 55% over the water.
    property real strength: root.light ? 0.6 : 0.55
    property color tint: root.tint
    property color edge: root.edge
    property size texels: root.surface && root.surface.textureSize ? root.surface.textureSize : Qt.size(1, 1)
    // Something must be bound even when there is no water; it is not read.
    property var surface: root.surface ? root.surface : blank
  }
  ShaderEffectSource {
    id: blank
    sourceItem: Item { width: 1; height: 1 }
    textureSize: Qt.size(1, 1)
  }
}
