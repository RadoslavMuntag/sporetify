import QtQuick

// A layer of fields of light (PondField, OrganismField) drawn together
// into one texture, a texel per character cell, for a GlyphLayer. One
// render pass for the whole layer, however many organisms are in it: the
// water fills it, and each organism draws only within the box it can
// reach, leaving the cells it does not light alone.
Item {
  id: root

  property real cell: 6
  property size grid: Qt.size(1, 1)
  default property alias content: holder.data
  readonly property Item texture: field

  Item {
    id: holder
    width: root.grid.width * root.cell
    height: root.grid.height * root.cell * 2
  }
  // Never shown itself: it has no size.
  ShaderEffectSource {
    id: field
    sourceItem: holder
    hideSource: true
    textureSize: root.grid
    smooth: false
  }
}
