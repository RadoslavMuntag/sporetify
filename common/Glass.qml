import QtQuick
import QtQuick.Effects

// A pane of glass over the Living ASCII water (D18): whatever swims behind
// it, blurred and tinted, so text on it stays readable while the pool
// stays present as colour. Samples `backdrop` directly; no desktop blur.
//
// `area` is this pane's rectangle in `backdrop`'s coordinates. The host
// knows it (both are usually children of the same item) and passes it, so
// nothing is mapped per frame.
Item {
  id: root

  property Item backdrop: null
  property rect area: Qt.rect(x, y, width, height)
  // 0 crisp, 1 balanced, 1.9 dreamy; at 0 the pane is plain.
  property real blur: 1
  property color tint
  property color edge

  // Drawn under the effect: a hidden source is never rendered, which left
  // the pane empty.
  ShaderEffectSource {
    id: behind
    anchors.fill: parent
    visible: live
    sourceItem: root.backdrop
    sourceRect: root.area
    live: root.blur > 0 && root.backdrop !== null
  }

  MultiEffect {
    anchors.fill: parent
    visible: root.blur > 0 && root.backdrop !== null
    source: behind
    blurEnabled: true
    blurMax: 48
    blur: 1
    blurMultiplier: 0.5 + root.blur * 0.5
    saturation: 0.5
  }

  Rectangle {
    anchors.fill: parent
    // Without blur the pane is nearly opaque, so text never sits on detail.
    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.blur > 0 ? 0.56 : 0.9)
    border.width: 1
    border.color: Qt.rgba(root.edge.r, root.edge.g, root.edge.b, 0.13)
  }
}
