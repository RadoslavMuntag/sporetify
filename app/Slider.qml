import QtQuick

// Horizontal slider, 0..1. `moved` fires while dragging, `released` once at the end.
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

  readonly property real knob: Theme.space(12)

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    x: root.knob / 2
    width: parent.width - root.knob
    height: Theme.space(3)
    radius: height / 2
    color: Theme.selectedFill

    Rectangle {
      width: parent.width * root.shown
      height: parent.height
      radius: parent.radius
      color: Theme.foreground
    }
  }

  Rectangle {
    width: root.knob
    height: root.knob
    radius: root.knob / 2
    anchors.verticalCenter: parent.verticalCenter
    x: track.width * root.shown
    color: Theme.foreground
    scale: area.pressed ? 1.25 : 1
    Behavior on scale { NumberAnimation { duration: 80 } }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    function at(x) {
      return Math.max(0, Math.min(1, (x - root.knob / 2) / Math.max(1, track.width)))
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
