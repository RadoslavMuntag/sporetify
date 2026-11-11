import QtQuick
import "../common/Keymap.js" as Keymap

// Choosing a playlist to add tracks to: type to narrow, arrows to move,
// Enter to add. The window opens and closes it and acts on the choice.
Sheet {
  id: root

  // The user's playlists that can be added to.
  property var playlists: []
  // [{ uri, title }] being added.
  property var tracks: []
  property alias text: filter.text
  property alias currentIndex: list.currentIndex
  signal confirmed()
  signal cancelled()

  // The playlists whose name holds every typed word, then, when something
  // has been typed, a row that creates a playlist of that name. Creating
  // comes last so that Enter on a name that already exists adds to it and
  // does not make a second one.
  readonly property var choices: {
    var typed = filter.text.trim()
    var words = typed.toLowerCase().split(/\s+/)
    var out = playlists.filter(function(playlist) {
      var name = playlist.name.toLowerCase()
      for (var i = 0; i < words.length; i++) if (words[i] !== "" && name.indexOf(words[i]) === -1) return false
      return true
    })
    if (typed !== "") out = out.concat([{ create: true, name: typed }])
    return out
  }

  function reset() {
    filter.text = ""
    list.currentIndex = 0
    filter.grab(false)
  }

  eyebrow: "Add to playlist"
  title: tracks.length === 0 ? "" : (tracks.length === 1 ? "“" + tracks[0].title + "”" : tracks.length + " tracks")
  footer: choices.length === 0 ? "No playlist of yours matches"
    : Keymap.keyLabel("fieldUp") + " " + Keymap.keyLabel("fieldDown") + " move · "
      + Keymap.keyLabel("fieldAccept") + " add · " + Keymap.keyLabel("fieldCancel") + " cancel"
  onDismissed: cancelled()

  Field {
    id: filter
    x: root.pad
    width: parent.width - root.pad * 2
    placeholder: "Type to narrow the list, or a name for a new playlist"
    onEdited: list.currentIndex = 0
    onCancelled: root.cancelled()
    onAccepted: root.confirmed()
    onMoved: function(delta) {
      list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta))
    }
  }

  ListView {
    id: list
    anchors.top: filter.bottom
    anchors.topMargin: Theme.spacing.lg
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    model: root.choices.length
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0

    delegate: Rectangle {
      id: choice
      required property int index
      readonly property var playlist: root.choices[index]
      readonly property bool cursor: ListView.isCurrentItem
      width: list.width
      height: Theme.spacing.rowHeight
      color: cursor || choiceArea.containsMouse ? Theme.hoverFill : "transparent"

      Rectangle {
        anchors.bottom: parent.bottom
        x: root.pad
        width: parent.width - root.pad * 2
        height: Theme.stroke.hair
        color: Theme.line
      }
      Bracket { visible: choice.cursor }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: root.pad
        width: parent.width - root.pad * 2 - choiceCount.width - Theme.spacing.lg
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: !choice.playlist ? "" : (choice.playlist.create
          ? "+ Create “" + choice.playlist.name + "”" : choice.playlist.name)
        color: choice.playlist && choice.playlist.create ? Theme.accent : Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Text {
        id: choiceCount
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        textFormat: Text.PlainText
        text: choice.playlist && !choice.playlist.create && choice.playlist.length !== null
          && choice.playlist.length !== undefined ? String(choice.playlist.length) : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      MouseArea {
        id: choiceArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          list.currentIndex = choice.index
          root.confirmed()
        }
      }
    }
  }
}
