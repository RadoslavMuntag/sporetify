import QtQuick

import "Keymap.js" as Keymap

// Footer listing what each key does in the current scope. Always generated
// from Keymap, so it shows exactly what the next keypress would do.
Flow {
  id: root

  // One scope name or a list of them; see Keymap.hints.
  property var scope: "player"
  property color foreground
  property color muted
  property string fontFamily
  property int fontSize
  property int gap

  spacing: gap * 2

  Repeater {
    model: Keymap.hints(root.scope)

    Row {
      required property var modelData
      spacing: root.gap

      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        label: parent.modelData.key
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        padding: root.gap
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: parent.modelData.label
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }
  }
}
