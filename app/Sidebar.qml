import QtQuick

import "../common/Loadable.js" as Loadable

// Liked Songs and the user's playlists.
Rectangle {
  id: root

  required property var library
  property bool focused: false
  property alias currentIndex: list.currentIndex
  readonly property int count: list.count
  signal activated(int index)

  color: Theme.sunken

  // Folder ids that are folded shut: { id: true }.
  property var collapsed: ({})
  property bool offline: false
  signal folderToggled(string id)

  readonly property var all: Loadable.hasData(library.playlists) ? library.playlists.data : []
  // What is listed: everything except the contents of folded folders.
  readonly property var items: {
    var out = []
    var hiddenBelow = -1   // depth of the folded folder we are inside, or -1
    for (var i = 0; i < all.length; i++) {
      var item = all[i]
      var depth = item.depth || 0
      if (hiddenBelow >= 0 && depth > hiddenBelow) continue
      hiddenBelow = -1
      out.push(item)
      if (item.kind === "folder" && collapsed[item.id] === true) hiddenBelow = depth
    }
    return out
  }

  function itemAt(index) {
    return index >= 0 && index < items.length ? items[index] : null
  }
  function move(delta) {
    list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta))
  }
  function jump(index) {
    list.currentIndex = Math.max(0, Math.min(list.count - 1, index))
  }
  readonly property int rowsPerPage: Math.max(1, Math.floor(list.height / Theme.spacing.rowHeight) - 1)

  Text {
    id: heading
    x: Theme.spacing.xxl
    y: Theme.spacing.xl
    textFormat: Text.PlainText
    text: root.offline ? "LIBRARY · OFFLINE, SHOWING WHAT WAS SAVED" : "LIBRARY"
    color: root.offline ? Theme.urgent : Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.letterSpacing: 1
  }

  // Loading or failed, with nothing cached to show instead.
  Text {
    anchors.top: heading.bottom
    anchors.topMargin: Theme.spacing.xl
    x: Theme.spacing.xxl
    width: parent.width - Theme.spacing.xxl * 2
    visible: root.items.length === 0
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: root.library.playlists.state === "error"
      ? root.library.playlists.error.message + "\nPress R to retry."
      : "Loading…"
    color: root.library.playlists.state === "error" ? Theme.urgent : Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.bodySmall
  }

  ListView {
    id: list
    anchors.top: heading.bottom
    anchors.topMargin: Theme.spacing.md
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    model: root.items.length
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0

    delegate: Rectangle {
      id: row
      required property int index
      readonly property var item: root.itemAt(index)
      readonly property bool folder: !!item && item.kind === "folder"
      readonly property real indent: Theme.spacing.xxl + (item ? (item.depth || 0) : 0) * Theme.spacing.xl
      readonly property bool open: !!item && !folder && root.library.kind === "playlist"
        && item.uri === root.library.uri
      readonly property bool cursor: ListView.isCurrentItem && root.focused

      width: list.width
      height: Theme.spacing.rowHeight
      color: cursor ? Theme.selectedFill : (hover.containsMouse ? Theme.hoverFill : "transparent")

      Rectangle {
        visible: row.open
        width: Theme.space(2)
        height: parent.height
        color: Theme.accent
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: row.indent
        width: parent.width - row.indent - Theme.spacing.xxl
        elide: Text.ElideRight
        textFormat: Text.PlainText
        // A folder shows whether it is folded.
        text: !row.item ? "" : (row.folder
          ? (root.collapsed[row.item.id] === true ? "▸ " : "▾ ") + row.item.name : row.item.name)
        color: row.open ? Theme.accent : (row.folder ? Theme.muted : Theme.foreground)
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          list.currentIndex = row.index
          root.activated(row.index)
        }
      }
    }
  }
}
