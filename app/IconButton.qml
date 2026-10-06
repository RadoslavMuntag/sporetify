import QtQuick

// A glyph button. `hint` is the keycap shown under it, if any.
Item {
  id: root

  property string icon: ""
  property real iconSize: Theme.font.icon
  property string hint: ""
  property bool enabled: true
  property color tint: Theme.foreground
  signal clicked()

  implicitWidth: Math.max(Theme.spacing.controlHeight, glyph.implicitWidth + Theme.spacing.lg * 2)
  implicitHeight: Theme.spacing.controlHeight
  opacity: enabled ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: Theme.spacing.sm
    color: area.pressed ? Theme.selectedFill : (area.containsMouse ? Theme.hoverFill : "transparent")
    // Squash a little on press: soft, quick, never delays the click.
    scale: area.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 80 } }
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.icon
    color: root.tint
    font.family: Theme.font.family
    font.pixelSize: root.iconSize
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
