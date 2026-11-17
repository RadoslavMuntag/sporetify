import QtQuick

// A glyph button. `hint` is the keycap shown under it, if any.
Item {
  id: root

  property string icon: ""
  property real iconSize: Theme.font.icon
  property string hint: ""
  property bool enabled: true
  property color tint: Theme.foreground
  // The Living ASCII look (D18): a rounded box around the glyph, and for
  // the main control a box filled with the accent.
  property bool boxed: false
  property bool filled: false
  signal clicked()

  implicitWidth: Math.max(Theme.spacing.controlHeight, glyph.implicitWidth + Theme.spacing.lg * 2)
  implicitHeight: Theme.spacing.controlHeight
  opacity: enabled ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: root.boxed || root.filled ? Theme.space(4) : 0
    color: root.filled ? Theme.accent
      : area.pressed ? Theme.selectedFill
      : area.containsMouse ? (root.boxed ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.24) : Theme.hoverFill)
      : root.boxed ? Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.09) : "transparent"
    border.width: root.boxed || root.filled ? 1 : 0
    border.color: root.filled ? Theme.accent : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.16)
    // Squash a little on press: soft, quick, never delays the click.
    scale: area.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 80 } }
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.icon
    color: root.filled ? Theme.background : root.tint
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
