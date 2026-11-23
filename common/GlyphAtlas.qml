import QtQuick
import QtQuick.Window

// The glyphs the pool draws with: " .·:-=+*#%@" for brightness, then
// "-|/\°" for glass spines. Use it as a shader's texture; it is never
// shown itself.
//
// Each glyph is drawn at the cell's own size in device pixels, as the
// organism studies draw theirs, so a cell on screen reads its glyph one
// texel per pixel when the cell is a whole number of device pixels wide
// (Water snaps it so). Shrinking larger glyphs averaged thin strokes into
// grey; stretching smaller ones made strokes uneven. Read it filtered and
// keep half a texel inside each glyph (`inset`), so a neighbour never
// bleeds in.
ShaderEffectSource {
  id: root

  property real cell: 6
  property color ink
  readonly property string glyphs: " .·:-=+*#%@-|/\\°"
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // One glyph's width in texels.
  readonly property int texels: Math.max(3, Math.round(cell * dpr))
  // Half a texel, as a fraction of a glyph's width and height.
  readonly property size inset: Qt.size(0.5 / texels, 0.25 / texels)

  sourceItem: Row {
    Repeater {
      model: root.glyphs.length
      Text {
        required property int index
        width: root.texels / root.dpr
        height: width * 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyphs[index]
        color: root.ink
        font.family: "monospace"
        font.pixelSize: Math.round(width / 0.6)
        font.weight: Font.Medium
      }
    }
  }
  textureSize: Qt.size(root.texels * root.glyphs.length, root.texels * 2)
  smooth: true
}
