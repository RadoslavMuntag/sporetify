import QtQuick

// A one-line text field ruled underneath, as on a printed form: a hairline,
// heavier and in the accent colour while it has focus.
Item {
  id: root

  property alias text: input.text
  readonly property bool typing: input.activeFocus
  property string placeholder: ""
  signal edited()
  signal accepted()
  signal cancelled()
  signal moved(int delta)
  // Tab and Shift Tab; taken so focus never leaves the field by accident.
  signal tabbed(int delta)
  // Any other key, to add shortcuts that work while typing.
  signal otherKey(var event)

  function grab(selectAll) {
    input.forceActiveFocus()
    if (selectAll) input.selectAll()
  }

  implicitHeight: Theme.spacing.rowHeight

  TextInput {
    id: input
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    clip: true
    color: Theme.foreground
    selectionColor: Theme.selectedFill
    selectedTextColor: Theme.foreground
    font.family: Theme.font.family
    font.pixelSize: Theme.font.body
    onTextEdited: root.edited()
    Keys.onEscapePressed: root.cancelled()
    Keys.onReturnPressed: root.accepted()
    Keys.onEnterPressed: root.accepted()
    Keys.onUpPressed: root.moved(-1)
    Keys.onDownPressed: root.moved(1)
    Keys.onTabPressed: root.tabbed(1)
    Keys.onBacktabPressed: root.tabbed(-1)
    Keys.onPressed: function(event) { root.otherKey(event) }
  }
  Text {
    visible: input.text === ""
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: root.placeholder
    color: Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.body
  }
  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: root.typing ? Theme.stroke.bold : Theme.stroke.hair
    color: root.typing ? Theme.accent : Theme.border
  }
}
