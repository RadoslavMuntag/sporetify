import QtQuick

// The glyphs the pool draws with, drawn once at the cell's own size (shrinking
// larger ones averaged thin strokes into grey): " .·:-=+*#%@" for brightness,
// then "-|/\°" for glass spines. Use it as a shader's texture; it is never
// shown itself.
ShaderEffectSource {
  id: root

  property real cell: 6
  property color ink
  readonly property string glyphs: " .·:-=+*#%@-|/\\°"

  sourceItem: Row {
    Repeater {
      model: root.glyphs.length
      Text {
        required property int index
        width: Math.max(3, Math.round(root.cell))
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
  smooth: false
}
