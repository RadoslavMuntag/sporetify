import QtQuick

// Horizontal slider, 0..1, drawn as Field Guide line work: a hairline, the
// set part as a heavier accent line, and a needle. `moved` fires while
// dragging, `released` once at the end.
Item {
  id: root

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
    x: root.inset
    anchors.verticalCenter: parent.verticalCenter
    width: root.span
    height: Theme.stroke.hair
    color: Theme.border
  }
  Rectangle {
    x: root.inset
    anchors.verticalCenter: parent.verticalCenter
    width: root.span * root.shown
    height: Theme.stroke.bold
    color: Theme.accent
  }
  Rectangle {
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
