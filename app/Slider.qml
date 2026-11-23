import QtQuick

// Horizontal slider, 0..1, drawn as Field Guide line work: a hairline, the
// set part as a heavier accent line, and a needle. With `ascii` it is drawn
// in characters as in the Living ASCII mockup: `====●-----`, or with
// `brackets` `[=======---]`. `moved` fires while dragging, `released` once
// at the end.
Item {
  id: root

  property bool ascii: false
  property bool brackets: false
  property real value: 0
  property bool dragging: false
  // What is drawn: the dragged value while dragging, otherwise `value`.
  property real shown: dragging ? dragValue : Math.max(0, Math.min(1, value))
  property real dragValue: 0
  signal moved(real value)
  signal released(real value)

  implicitHeight: Theme.spacing.controlHeight
  implicitWidth: Theme.space(160)

  // Room at each end for the needle.
  readonly property real inset: Theme.stroke.bold
  readonly property real span: Math.max(1, width - inset * 2)
  readonly property real needleX: inset + span * shown

  Rectangle {
    visible: !root.ascii
    x: root.inset
    anchors.verticalCenter: parent.verticalCenter
    width: root.span
    height: Theme.stroke.hair
    color: Theme.border
  }
  Rectangle {
    visible: !root.ascii
    x: root.inset
    anchors.verticalCenter: parent.verticalCenter
    width: root.span * root.shown
    height: Theme.stroke.bold
    color: Theme.accent
  }

  // ---- In characters: as many cells as fit, the set part in accent.
  FontMetrics {
    id: metrics
    font.family: Theme.font.family
    font.pixelSize: Theme.font.bodySmall
  }
  // A property, unlike FontMetrics' method, so a font change is followed.
  TextMetrics { id: cellMetrics; font: metrics.font; text: "=" }
  readonly property int cells: Math.max(4, Math.floor(width / Math.max(1, cellMetrics.advanceWidth))
    - (brackets ? 2 : 0))
  // With a knob the knob is one of the cells.
  readonly property int setCells: brackets ? Math.round(shown * cells) : Math.round(shown * (cells - 1))
  Row {
    visible: root.ascii
    anchors.verticalCenter: parent.verticalCenter
    Text { visible: root.brackets; textFormat: Text.PlainText; font: metrics.font; text: "["; color: Theme.subtle }
    Text {
      textFormat: Text.PlainText
      font.family: metrics.font.family
      font.pixelSize: metrics.font.pixelSize
      font.bold: true
      text: "=".repeat(root.setCells) + (root.brackets ? "" : "●")
      color: Theme.accent
    }
    Text {
      textFormat: Text.PlainText
      font: metrics.font
      text: "-".repeat(Math.max(0, root.cells - root.setCells - (root.brackets ? 0 : 1)))
      color: Theme.faint
    }
    Text { visible: root.brackets; textFormat: Text.PlainText; font: metrics.font; text: "]"; color: Theme.subtle }
  }

  Rectangle {
    visible: !root.ascii
    x: root.needleX - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: Theme.stroke.bold
    height: Theme.space(area.pressed || area.containsMouse ? 16 : 12)
    color: Theme.foreground
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    function at(x) {
      return Math.max(0, Math.min(1, (x - root.inset) / root.span))
    }
    onPressed: function(mouse) {
      root.dragValue = at(mouse.x)
      root.dragging = true
      root.moved(root.dragValue)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      root.dragValue = at(mouse.x)
      root.moved(root.dragValue)
    }
    onReleased: {
      root.dragging = false
      root.released(root.dragValue)
    }
    onCanceled: root.dragging = false
  }
}
