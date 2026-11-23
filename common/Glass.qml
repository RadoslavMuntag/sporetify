import QtQuick
import QtQuick.Effects

// A pane of glass over the Living ASCII water (D18): whatever swims behind
// it, blurred, a little more saturated and lightly tinted, so text on it
// stays readable while the pool shows through as colour. Samples
// `backdrop` directly; no desktop blur.
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
  property bool light: false
  property real radius: 0

  readonly property bool sampling: blur > 0 && backdrop !== null

  // The glass itself, cut to the rounded shape as one layer. The mask is
  // made with the layer, so the effect has it from the start.
  Item {
    id: pane
    anchors.fill: parent
    layer.enabled: root.radius > 0
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: shape
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    // Drawn under the blur: a hidden source is never rendered, which left
    // the pane empty.
    ShaderEffectSource {
      id: behind
      anchors.fill: parent
      visible: root.sampling
      sourceItem: root.backdrop
      sourceRect: root.area
      live: root.sampling
    }
    MultiEffect {
      anchors.fill: parent
      visible: root.sampling
      source: behind
      blurEnabled: true
      blurMax: 48
      blur: 1
      blurMultiplier: 0.5 + root.blur * 0.5
      // The mockup lifts the colour behind its glass (saturate 150%).
      saturation: 0.5
    }
    Rectangle {
      anchors.fill: parent
      // Without blur the pane is nearly opaque, so text never sits on detail.
      color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, !root.sampling ? 0.9 : root.light ? 0.5 : 0.42)
    }
  }
  Rectangle {
    id: shape
    anchors.fill: parent
    visible: false
    layer.enabled: true
    radius: root.radius
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(root.edge.r, root.edge.g, root.edge.b, 0.13)
  }
  // A highlight along the top edge, as light catches glass.
  Rectangle {
    visible: root.sampling
    x: root.radius
    width: parent.width - root.radius * 2
    height: 1
    y: 1
    color: Qt.rgba(root.edge.r, root.edge.g, root.edge.b, 0.08)
  }
}
