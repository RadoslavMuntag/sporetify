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

    // ---- Track
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.28
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
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.track ? root.track.artists.join(", ") : (root.player.lastError !== "" ? root.player.lastError : "")
        color: root.track ? Theme.muted : Theme.urgent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
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
