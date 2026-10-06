import QtQuick

// A small keycap showing which key triggers the control it sits beside.
// Colours and sizes are passed in by the host so this file stays free of
// host-specific theme imports.
Rectangle {
  id: root

  property string label: ""
  property color foreground
  property string fontFamily
  property int fontSize
  property int padding

  visible: label !== ""
  implicitWidth: Math.max(implicitHeight, text.implicitWidth + padding * 2)
  implicitHeight: text.implicitHeight + padding
  radius: padding
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)

  Text {
    id: text
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }
}
