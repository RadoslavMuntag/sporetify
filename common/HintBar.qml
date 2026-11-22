import QtQuick

import "Keymap.js" as Keymap

// Footer listing what each key does in the current scope. Always generated
// from Keymap, so it shows exactly what the next keypress would do.
Flow {
  id: root

  // One scope name or a list of them; see Keymap.hints.
  property var scope: "player"
  // Show only the actions marked primary; the rest live in a help overlay.
  property bool primaryOnly: false
  // Keep to one line: hints that do not fit are left out, from the end,
  // except the `pinned` ones (action ids), which always show.
  property bool singleLine: false
  property var pinned: []
  property color foreground
  property color muted
  property string fontFamily
  property int fontSize
  property int gap
  // Keycap corner rounding; -1 keeps KeyCap's own.
  property real corner: -1

  readonly property var hints: Keymap.hints(root.scope, root.primaryOnly)
  // Which hints show, by index; only worked out on one line.
  property var shown: []

  function fit() {
    if (!singleLine) return
    var widths = []
    for (var i = 0; i < hints.length; i++) {
      var item = repeater.itemAt(i)
      if (!item) return
      widths.push(item.implicitWidth)
    }
    var used = 0
    var out = []
    for (i = 0; i < hints.length; i++) {
      out.push(pinned.indexOf(hints[i].id) !== -1)
      if (out[i]) used += widths[i] + (used > 0 ? spacing : 0)
    }
    for (i = 0; i < hints.length; i++) {
      if (out[i]) continue
      var need = widths[i] + (used > 0 ? spacing : 0)
      if (used + need > width) break
      out[i] = true
      used += need
    }
    shown = out
  }
  onWidthChanged: fit()
  onHintsChanged: Qt.callLater(fit)

  spacing: gap * 2

  Repeater {
    id: repeater
    model: root.hints

    Row {
      required property var modelData
      required property int index
      visible: !root.singleLine || root.shown[index] !== false
      spacing: root.gap
      Component.onCompleted: Qt.callLater(root.fit)

      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        label: parent.modelData.key
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        padding: root.gap
        corner: root.corner >= 0 ? root.corner : root.gap
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
