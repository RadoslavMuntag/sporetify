import QtQuick
import "../common/Keymap.js" as Keymap

// A one-line question (a new playlist's name, a new name). The window
// opens it and decides what the answer does.
Sheet {
  id: root

  property alias text: field.text
  signal confirmed()
  signal cancelled()

  function grab() {
    field.grab(true)
  }

  footer: Keymap.keyLabel("fieldAccept") + " confirm · " + Keymap.keyLabel("fieldCancel") + " cancel"
  contentHeight: field.height
  onDismissed: cancelled()

  Field {
    id: field
    x: root.pad
    width: parent.width - root.pad * 2
    onCancelled: root.cancelled()
    onAccepted: root.confirmed()
  }
}
