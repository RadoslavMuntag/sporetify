import QtQuick

import "Visuals.js" as Visuals

// A fine-line spectrum on a hairline: one thin line per step across the
// width, as tall as the music is loud there. The bass end is drawn in the
// accent colour. Colours come from the host.
//
// Each line eases towards its new height over about three frames, so the
// 30 Hz updates read as motion rather than steps.
Item {
  id: root

  // 0..1 per band, low to high; empty draws only the baseline.
  property var bands: []
  // How many lines to draw.
  property int lines: 48
  property color ink
  property color accent
  property real stroke: 1
  // Smoothing on; off draws each frame as it comes.
  property bool smooth: true

  readonly property real step: width / lines

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: root.stroke
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
  }

  Repeater {
    model: root.lines

    Rectangle {
      required property int index
      readonly property real level: Visuals.sample(root.bands, index / Math.max(1, root.lines - 1))
      x: (index + 0.5) * root.step - width / 2
      width: root.stroke
      height: Math.max(0, level * (root.height - root.stroke))
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.stroke
      color: index < root.lines / 4 ? root.accent : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)

      Behavior on height {
        enabled: root.smooth
        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
      }
    }
  }
}
