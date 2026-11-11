import QtQuick

import "../common/Keymap.js" as Keymap
import "../common/Position.js" as Position
import "../common/Specimen.js" as Specimen

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

  // ---- Column layout, shared by the column labels and every row.
  readonly property real pad: Theme.spacing.huge
  readonly property real numberWidth: Theme.space(36)
  readonly property real timeWidth: Theme.space(52)
  readonly property real markWidth: Theme.space(24)
  // On an album page every row would show the same cover.
  readonly property bool thumbs: covers && library.kind !== "album"
  // Places that are lists of tracks get column labels.
  readonly property bool trackList: ["playlist", "album", "queue"].indexOf(library.kind) !== -1

  // What kind of place this is, over its name.
  readonly property string eyebrow: {
    var names = { playlist: "Playlist", album: "Album", artist: "Artist", queue: "Up next", foryou: "Made for you" }
    var label = library.searching ? "Search · " + (library.searchMode === "library" ? "your library" : "Spotify")
      : (names[library.kind] || "")
    var number = library.uri !== "" && !library.searching ? Specimen.catalogue(library.uri) : ""
    return (label + (number !== "" ? " · No. " + number : "")).toUpperCase()
  }

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
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.eyebrow
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: Theme.font.caption * 0.12
      }
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
          if (root.library.markedCount > 0)
          return root.library.markedCount + " selected · " + Keymap.keyLabel("addToPlaylist") + " add to playlist · "
            + Keymap.keyLabel("removeFromPlaylist") + " remove · " + Keymap.keyLabel("cancel") + " clear"
        if (root.library.kind === "") return "Pick a playlist on the left, or press " + Keymap.keyLabel("search") + " to search"
          if (root.library.collection.state === "error")
            return root.library.collection.error.message + " · press " + Keymap.keyLabel("reload") + " to retry"
          if (root.library.collection.state === "loading" && root.library.subtitle === "") return "Loading…"
          return root.library.subtitle
        }
        color: root.library.markedCount > 0 ? Theme.accent
        : (root.library.collection.state === "error" ? Theme.urgent : Theme.muted)
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
    height: Theme.stroke.hair
    color: Theme.line
  }

  component ColumnLabel: Text {
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    color: Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.letterSpacing: Theme.font.caption * 0.12
  }

  // ---- Column labels, on lists of tracks
  Item {
    id: columns
    anchors.top: rule.bottom
    width: parent.width
    height: root.trackList ? labelRow.height + Theme.spacing.md * 2 : 0
    visible: root.trackList

    readonly property real textX: root.pad + root.numberWidth + (root.thumbs ? Theme.spacing.thumb + Theme.spacing.xl : 0)
    readonly property real flexible: width - textX - root.pad - root.timeWidth - root.markWidth

    Item {
      id: labelRow
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: Theme.font.caption * 1.4
      ColumnLabel { x: root.pad; text: "#" }
      ColumnLabel { x: columns.textX; text: "TITLE" }
      ColumnLabel { x: columns.textX + columns.flexible * 0.6; text: "ALBUM" }
      ColumnLabel { anchors.right: parent.right; anchors.rightMargin: root.pad; text: "TIME" }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: Theme.stroke.hair
      color: Theme.line
    }
  }

  ListView {
    id: list
    anchors.top: columns.bottom
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
      readonly property bool marked: {
        root.library.revision
        return root.library.isMarked(track)
      }
      readonly property color ink: isPlaying ? Theme.accent
        : (track && kind === "" && !track.available ? Theme.muted : Theme.foreground)

      // ---- Layout: number, cover, two lines of text, album, mark, time.
      readonly property real pad: root.pad
      readonly property real numberWidth: root.numberWidth
      readonly property real timeWidth: root.timeWidth
      readonly property real markWidth: root.markWidth
      readonly property bool hasThumb: root.thumbs && kind !== "heading"
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
      color: (cursor || hover.containsMouse) && kind !== "heading" ? Theme.hoverFill : "transparent"

      // A hairline under every row, as in a ruled catalogue.
      Rectangle {
        visible: row.kind !== "heading"
        anchors.bottom: parent.bottom
        x: row.pad
        width: parent.width - row.pad * 2
        height: Theme.stroke.hair
        color: Theme.line
      }

      // The cursor: corner brackets, top left and bottom right.
      Bracket { visible: row.cursor }

      // A bar down the left edge of a selected row.
      Rectangle {
        visible: row.marked
        width: Theme.space(3)
        height: parent.height
        color: Theme.accent
      }

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
          // nf-md-check on a selected row.
          if (row.marked) return "󰄬"
          if (row.isPlaying) return "▸"
          switch (row.kind) {
          case "album": return "󰀥"
          case "artist": return "󰠃"
          case "playlist": return "󰲸"
          }
          // A list with sections numbers its tracks itself (see Pages.numberTracks).
          return String(row.track && row.track.n ? row.track.n : row.index + 1)
        }
        color: row.isPlaying || row.marked ? Theme.accent : Theme.muted
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
          color: Theme.hoverFill
        }
        Rectangle {
          width: row.flexible * (0.14 + (row.index % 3) * 0.04)
          height: Theme.space(5)
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

        // The title, and the track's catalogue number when there is room.
        Row {
          width: parent.width
          spacing: Theme.spacing.lg

          Text {
            id: title
            width: Math.min(implicitWidth, parent.width - (number.visible ? number.implicitWidth + parent.spacing : 0))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: row.track ? row.track.title : ""
            color: row.ink
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            id: number
            visible: row.kind === "" && row.track !== null && parent.width > Theme.space(150)
            anchors.baseline: title.baseline
            textFormat: Text.PlainText
            text: visible ? "No. " + Specimen.catalogue(row.track.uri) : ""
            color: Theme.muted
            opacity: 0.7
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
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
