import QtQuick

import "../common"
import "../common/Keymap.js" as Keymap
import "../common/Position.js" as Position

// Bottom strip: what is playing, transport, seek and volume.
Rectangle {
  id: root

  required property var player
  // Whether the window is showing, so the clock only ticks when seen.
  property bool live: true
  // Whether creatures are drawn at all.
  property bool visuals: true
  // The user clicked the title (album) or the artist line.
  signal albumRequested()
  signal artistRequested()
  // Whether the playing track is liked, and a request to flip it.
  property bool liked: false
  signal likeRequested()

  readonly property var track: player.track
  property real nowMs: Date.now()
  readonly property real positionMs: player.player && track
    ? Position.at(player.player.position, nowMs, track.duration_ms) : 0

  color: Theme.sunken
  implicitHeight: content.implicitHeight + Theme.spacing.xl * 2

  Timer {
    interval: 500
    repeat: true
    running: root.live && root.player.playing
    onTriggered: root.nowMs = Date.now()
  }
  Connections {
    target: root.player
    function onPlayerChanged() { root.nowMs = Date.now() }
  }

  Rectangle { width: parent.width; height: 1; color: Theme.line }

  component Cap: KeyCap {
    foreground: Theme.foreground
    fontFamily: Theme.font.family
    fontSize: Theme.font.caption
    padding: Theme.spacing.xs
  }

  Item {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    x: Theme.spacing.huge
    width: parent.width - Theme.spacing.huge * 2
    implicitHeight: middle.implicitHeight

    // ---- Cover, fetched by the daemon and shown from its file
    Image {
      id: cover
      readonly property string path: root.track && root.track.art_path ? root.track.art_path : ""
      visible: path !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? Theme.space(46) : 0
      height: Theme.space(46)
      source: path !== "" ? "file://" + path : ""
      sourceSize.width: Theme.space(92)
      sourceSize.height: Theme.space(92)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }

    // ---- The track's creature
    Organism {
      id: creature
      visible: root.visuals && root.track !== null
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: cover.right
      anchors.leftMargin: cover.visible ? Theme.spacing.lg : 0
      width: visible ? Theme.space(46) : 0
      height: Theme.space(46)
      seed: root.track ? root.track.id : ""
      alive: visible && root.live && root.player.playing
      awake: root.player.playing
      palette: Theme.creatureColors
      eye: Theme.foreground
      pupil: Theme.sunken
    }

    // ---- Track
    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: creature.right
      anchors.leftMargin: creature.visible ? Theme.spacing.xl : 0
      width: parent.width * 0.28 - creature.width - cover.width - anchors.leftMargin - creature.anchors.leftMargin
      spacing: Theme.spacing.xs

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.track ? root.track.title : "Nothing playing"
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.subtitle
        font.bold: true

        MouseArea {
          anchors.fill: parent
          enabled: root.track !== null
          cursorShape: Qt.PointingHandCursor
          onClicked: root.albumRequested()
        }
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.track ? root.track.artists.join(", ") : (root.player.lastError !== "" ? root.player.lastError : "")
        color: root.track ? Theme.muted : Theme.urgent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall

        MouseArea {
          anchors.fill: parent
          enabled: root.track !== null
          cursorShape: Qt.PointingHandCursor
          onClicked: root.artistRequested()
        }
      }
    }

    // ---- Transport and seek
    Column {
      id: middle
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width * 0.4
      spacing: Theme.spacing.xs

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacing.lg

        // nf-md-heart / nf-md-heart_outline for the playing track.
        IconButton {
          icon: root.liked ? "󰋑" : "󰋕"
          enabled: root.track !== null
          tint: root.liked ? Theme.accent : Theme.muted
          onClicked: root.likeRequested()
        }
        // nf-md-shuffle_variant; lit when on.
        IconButton {
          icon: "󰒟"
          tint: root.player.player && root.player.player.shuffle ? Theme.accent : Theme.muted
          onClicked: root.player.run("shuffle")
        }
        Cap { anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("previous") }
        // nf-md-skip_previous, nf-md-pause / nf-md-play, nf-md-skip_next
        IconButton { icon: "󰒮"; enabled: root.track !== null; onClicked: root.player.run("previous") }
        IconButton {
          icon: root.player.playing ? "󰏤" : "󰐊"
          iconSize: Theme.font.iconLarge
          onClicked: root.player.run("playPause")
        }
        IconButton { icon: "󰒭"; enabled: root.track !== null; onClicked: root.player.run("next") }
        Cap { anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("next") }
        // nf-md-repeat; lit when on.
        IconButton {
          icon: "󰑖"
          tint: root.player.player && root.player.player.repeat ? Theme.accent : Theme.muted
          onClicked: root.player.run("repeat")
        }
      }

      Row {
        width: parent.width
        spacing: Theme.spacing.lg

        Text {
          id: elapsed
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.space(40)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: Position.clock(seek.dragging && root.track ? seek.dragValue * root.track.duration_ms : root.positionMs)
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
        Slider {
          id: seek
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - elapsed.width - remaining.width - parent.spacing * 2
          value: root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0
          // Seeking commits on release so a drag does not re-buffer per frame.
          onReleased: function(value) {
            if (root.track) root.player.seekTo(value * root.track.duration_ms)
          }
        }
        Text {
          id: remaining
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.space(40)
          textFormat: Text.PlainText
          text: root.track ? Position.clock(root.track.duration_ms) : "0:00"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
    }

    // ---- Volume
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spacing.md

      Cap { anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("volumeDown") }
      Slider {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.space(130)
        value: root.player.volume
        onMoved: function(value) { root.player.setVolume(value) }
      }
      Cap { anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("volumeUp") }
    }
  }
}
