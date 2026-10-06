import QtQuick

import "../common/Position.js" as Position

// The open collection's tracks. Rows are fixed height and exist for the
// whole list from the start; a row shows a placeholder until its page of
// metadata arrives, so nothing jumps when data lands.
Item {
  id: root

  required property var library
  required property var player
  property bool focused: false
  property alias currentIndex: list.currentIndex
  signal activated(int index)

  readonly property int rowsPerPage: Math.max(1, Math.floor(list.height / Theme.spacing.rowHeight) - 1)
  readonly property string playingUri: player.track ? player.track.id : ""

  function move(delta) {
    list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta))
  }
  function jump(index) {
    list.currentIndex = Math.max(0, Math.min(list.count - 1, index))
  }

  // Ask for the pages behind the rows on screen, plus one screen ahead.
  function ensureVisible() {
    if (list.count === 0) return
    var first = Math.max(0, Math.floor(list.contentY / Theme.spacing.rowHeight))
    var onScreen = Math.ceil(list.height / Theme.spacing.rowHeight)
    library.ensure(first, first + onScreen * 2)
  }

  Connections {
    target: root.library
    function onGenerationChanged() {
      list.currentIndex = 0
      list.positionViewAtBeginning()
    }
    function onTotalChanged() { root.ensureVisible() }
    // Coming back to a place puts the cursor where it was.
    function onCursorRestoreRequested(index) {
      list.currentIndex = Math.max(0, Math.min(list.count - 1, index))
      list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
  }

  Column {
    id: header
    x: Theme.spacing.huge
    y: Theme.spacing.xl
    width: parent.width - Theme.spacing.huge * 2
    spacing: Theme.spacing.xs

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.library.name
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: Theme.font.heading
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      text: {
        if (root.library.kind === "") return "Pick a playlist on the left, or press / to search"
        if (root.library.collection.state === "error")
          return root.library.collection.error.message + " · press R to retry"
        if (root.library.collection.state === "loading" && root.library.subtitle === "") return "Loading…"
        return root.library.subtitle
      }
      color: root.library.collection.state === "error" ? Theme.urgent : Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.bodySmall
    }
  }

  Rectangle {
    id: rule
    anchors.top: header.bottom
    anchors.topMargin: Theme.spacing.xl
    width: parent.width
    height: 1
    color: Theme.line
  }

  ListView {
    id: list
    anchors.top: rule.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    model: root.library.total
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0
    onContentYChanged: root.ensureVisible()
    onHeightChanged: root.ensureVisible()

    delegate: Rectangle {
      id: row
      required property int index
      readonly property var track: {
        root.library.revision
        return root.library.rowAt(index)
      }
      // "" for a track, otherwise "heading" or "album".
      readonly property string kind: track !== null && track.kind !== undefined ? track.kind : ""
      readonly property bool isPlaying: track !== null && kind === "" && track.uri === root.playingUri
      readonly property bool cursor: ListView.isCurrentItem && root.focused
      readonly property color ink: isPlaying ? Theme.accent
        : (track && kind === "" && !track.available ? Theme.muted : Theme.foreground)

      width: list.width
      height: Theme.spacing.rowHeight
      color: cursor ? Theme.selectedFill
        : (hover.containsMouse && kind !== "heading" ? Theme.hoverFill : "transparent")

      // A section label inside an artist page.
      Text {
        visible: row.kind === "heading"
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.md
        x: row.pad
        textFormat: Text.PlainText
        text: row.track ? String(row.track.title).toUpperCase() : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: 1
      }

      readonly property real pad: Theme.spacing.huge
      readonly property real numberWidth: Theme.space(44)
      readonly property real timeWidth: Theme.space(52)
      readonly property real flexible: width - pad * 2 - numberWidth - timeWidth - Theme.spacing.xxl * 2

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad
        width: row.numberWidth
        textFormat: Text.PlainText
        visible: row.kind !== "heading"
        // nf-md-volume_high marks the playing row, nf-md-album an album.
        text: row.isPlaying ? "󰕾" : (row.kind === "album" ? "󰀥" : String(row.index + 1))
        color: row.isPlaying ? Theme.accent : Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      // Placeholder until the row's metadata arrives.
      Rectangle {
        visible: row.track === null
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad + row.numberWidth
        width: row.flexible * (0.25 + (row.index % 5) * 0.06)
        height: Theme.space(6)
        radius: height / 2
        color: Theme.hoverFill
      }

      Text {
        visible: row.track !== null && row.kind !== "heading"
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad + row.numberWidth
        width: row.flexible * 0.45
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: row.track ? row.track.title : ""
        color: row.ink
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Text {
        visible: row.track !== null && row.kind !== "heading"
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad + row.numberWidth + row.flexible * 0.45 + Theme.spacing.xxl
        width: row.flexible * 0.3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: !row.track ? "" : (row.kind === "album" ? String(row.track.year)
          : (row.kind === "" ? row.track.artists.join(", ") : ""))
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Text {
        visible: row.track !== null && row.kind !== "heading"
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad + row.numberWidth + row.flexible * 0.75 + Theme.spacing.xxl * 2
        width: row.flexible * 0.25 - Theme.space(22)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: !row.track ? "" : (row.kind === "album"
          ? row.track.tracks + (row.track.tracks === 1 ? " track" : " tracks")
          : (row.kind === "" ? row.track.album : ""))
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      // nf-md-heart on liked tracks, nf-md-playlist_plus on ones queued from here.
      Text {
        visible: row.track !== null && row.kind === "" && (row.track.liked === true || row.track.queued === true)
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: row.pad + row.timeWidth
        textFormat: Text.PlainText
        text: row.track && row.track.queued === true ? "󰐒" : "󰋑"
        color: Theme.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      Text {
        visible: row.track !== null && row.kind === "" && row.track.available
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: row.pad
        textFormat: Text.PlainText
        text: row.track ? Position.clock(row.track.duration_ms) : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: list.currentIndex = row.index
        onDoubleClicked: root.activated(row.index)
      }
    }
  }
}
