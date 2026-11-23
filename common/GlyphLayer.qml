import QtQuick

// Characters from a FieldLayer's texture (shaders/glyphs.frag): each cell
// shows the glyph of its brightness in its colour.
Item {
  id: root

  // A FieldLayer's `texture`.
  property Item field: null
  property real cell: 6
  property size grid: Qt.size(1, 1)
  property bool light: false
  property color ink
  // Scene px per pixel drawn, when the layer is drawn small: its glyphs
  // are then averaged across each pixel instead of read at one point.
  property real footprint: 1
  readonly property bool failed: shader.status === ShaderEffect.Error

  GlyphAtlas {
    id: glyphAtlas
    cell: root.cell
    ink: root.ink
  }

  // ---- The characters, for every pixel: one field and the atlas.
  ShaderEffect {
    id: shader
    anchors.fill: parent
    fragmentShader: "shaders/glyphs.frag.qsb"
    property var atlas: glyphAtlas
    property var field: root.field
    property size area: Qt.size(width, height)
    property size grid: root.grid
    property real cell: root.cell
    property real light: root.light ? 1 : 0
    property real glyphs: glyphAtlas.glyphs.length
    property real footprint: root.footprint
    property size inset: glyphAtlas.inset
  }
}
