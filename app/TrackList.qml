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
  // Show a cover on each row.
  property bool covers: true
  property alias currentIndex: list.currentIndex
  signal activated(int index)

  readonly property int rowsPerPage: Math.max(1, Math.floor(list.height / Theme.spacing.trackRow) - 1)
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
    var first = Math.max(0, Math.floor(list.contentY / Theme.spacing.trackRow))
    var onScreen = Math.ceil(list.height / Theme.spacing.trackRow)
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

  Row {
    id: header
    x: Theme.spacing.huge
    y: Theme.spacing.xl
    width: parent.width - Theme.spacing.huge * 2
    spacing: Theme.spacing.xxl

    // Album cover or artist portrait, when the place has one.
    Image {
      id: art
      visible: root.library.artPath !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? Theme.space(72) : 0
      height: Theme.space(72)
      source: root.library.artPath !== "" ? "file://" + root.library.artPath : ""
      sourceSize.width: Theme.space(144)
      sourceSize.height: Theme.space(144)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (art.visible ? art.width + parent.spacing : 0)
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
      // "" for a track, otherwise "heading", "album", "artist" or "playlist".
      readonly property string kind: track !== null && track.kind !== undefined ? track.kind : ""
      readonly property bool isPlaying: track !== null && kind === "" && track.uri === root.playingUri
      readonly property bool cursor: ListView.isCurrentItem && root.focused
      readonly property color ink: isPlaying ? Theme.accent
        : (track && kind === "" && !track.available ? Theme.muted : Theme.foreground)

      // ---- Layout: number, cover, two lines of text, album, mark, time.
      readonly property real pad: Theme.spacing.huge
      readonly property real numberWidth: Theme.space(36)
      readonly property real timeWidth: Theme.space(52)
      readonly property real markWidth: Theme.space(24)
      // On an album page every row would show the same cover.
      readonly property bool hasThumb: root.covers && kind !== "heading" && root.library.kind !== "album"
      readonly property real thumbWidth: hasThumb ? Theme.spacing.thumb + Theme.spacing.xl : 0
      readonly property real textX: pad + numberWidth + thumbWidth
      readonly property real flexible: width - textX - pad - timeWidth - markWidth
      // Rows that open something have no album column, so their text runs on.
      readonly property real mainWidth: kind === "" ? flexible * 0.6 : flexible

      // The second line: who it is by, or what kind of thing it is.
      readonly property string detail: {
        if (!track) return ""
        switch (kind) {
        case "": return track.artists.join(", ")
        case "album":
          var parts = ["Album"]
          if (track.by) parts.push(track.by)
          if (track.year) parts.push(String(track.year))
          if (track.tracks !== undefined) parts.push(track.tracks + (track.tracks === 1 ? " track" : " tracks"))
          return parts.join(" · ")
        case "artist": return "Artist"
        case "playlist": return track.by ? "Playlist · " + track.by : "Playlist"
        }
        return ""
      }

      // ---- Cover: shown from the daemon's file; asked for only once the
      //      row has stayed on screen a moment, so fast scrolling asks for nothing.
      readonly property string artUrl: hasThumb ? root.library.artAddress(track) : ""
      readonly property string artPath: {
        root.library.artRevision
        return hasThumb ? root.library.artFor(track) : ""
      }
      Timer {
        interval: 140
        running: row.artUrl !== "" && row.artPath === ""
        onTriggered: root.library.wantArt(row.artUrl)
      }

      width: list.width
      height: Theme.spacing.trackRow
      color: cursor ? Theme.selectedFill
        : (hover.containsMouse && kind !== "heading" ? Theme.hoverFill : "transparent")

      // A section label inside an artist page or search results.
      Text {
        visible: row.kind === "heading"
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.lg
        x: row.pad
        textFormat: Text.PlainText
        text: row.track ? String(row.track.title).toUpperCase() : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad
        width: row.numberWidth
        textFormat: Text.PlainText
        visible: row.kind !== "heading"
        // nf-md-volume_high marks the playing row; the others the kind of row.
        text: {
          if (row.isPlaying) return "󰕾"
          switch (row.kind) {
          case "album": return "󰀥"
          case "artist": return "󰠃"
          case "playlist": return "󰲸"
          }
          return String(row.index + 1)
        }
        color: row.isPlaying ? Theme.accent : Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      Rectangle {
        visible: row.hasThumb
        anchors.verticalCenter: parent.verticalCenter
        x: row.pad + row.numberWidth
        width: Theme.spacing.thumb
        height: Theme.spacing.thumb
        // Shows through until the picture is there.
        color: Theme.hoverFill

        Image {
          anchors.fill: parent
          visible: row.artPath !== ""
          source: row.artPath !== "" ? "file://" + row.artPath : ""
          sourceSize.width: Theme.spacing.thumb * 2
          sourceSize.height: Theme.spacing.thumb * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }

      // Placeholder until the row's metadata arrives.
      Column {
        visible: row.track === null
        anchors.verticalCenter: parent.verticalCenter
        x: row.textX
        spacing: Theme.spacing.lg
        Rectangle {
          width: row.flexible * (0.22 + (row.index % 5) * 0.05)
          height: Theme.space(6)
          radius: height / 2
          color: Theme.hoverFill
        }
        Rectangle {
          width: row.flexible * (0.14 + (row.index % 3) * 0.04)
          height: Theme.space(5)
          radius: height / 2
          color: Theme.hoverFill
        }
      }

      // Title over artists (or over what kind of thing the row is).
      Column {
        visible: !!row.track && row.kind !== "heading"
        anchors.verticalCenter: parent.verticalCenter
        x: row.textX
        width: row.mainWidth - Theme.spacing.xxl
        spacing: Theme.spacing.xs

        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.track ? row.track.title : ""
          color: row.ink
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Text {
          width: parent.width
          visible: text !== ""
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.detail
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.bodySmall
        }
      }

      Text {
        visible: !!row.track && row.kind === ""
        anchors.verticalCenter: parent.verticalCenter
        x: row.textX + row.flexible * 0.6
        width: row.flexible * 0.4 - Theme.spacing.lg
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: row.track && row.kind === "" ? row.track.album : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      // nf-md-heart on liked tracks, nf-md-playlist_plus on ones queued from here.
      Text {
        visible: !!row.track && row.kind === "" && (row.track.liked === true || row.track.queued === true)
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
        visible: !!row.track && row.kind === "" && row.track.available === true
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
