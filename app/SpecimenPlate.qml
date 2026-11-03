import QtQuick

import "../common"
import "../common/Position.js" as Position
import "../common/Specimen.js" as Specimen

// The panel on the right of the app: the playing track as a specimen
// plate. Its creature in line art under the lens (the ring is the
// progress), what it is made of, and the music as a fine-line spectrum.
Rectangle {
  id: root

  required property var player
  // Draw and move (the visuals setting), and whether the window is seen.
  property bool moving: true
  property bool live: true

  readonly property var track: player.track
  readonly property real pad: Theme.spacing.huge

  color: Theme.background

  property real nowMs: Date.now()
  readonly property real positionMs: player.player && track
    ? Position.at(player.player.position, nowMs, track.duration_ms) : 0
  Timer {
    interval: 500
    repeat: true
    running: root.live && root.player.playing && root.track !== null
    onTriggered: root.nowMs = Date.now()
  }
  Connections {
    target: root.player
    function onPlayerChanged() { root.nowMs = Date.now() }
  }

  Rectangle { width: Theme.stroke.hair; height: parent.height; color: Theme.line }

  component Caption: Text {
    textFormat: Text.PlainText
    color: Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.letterSpacing: Theme.font.caption * 0.12
  }

  Column {
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Theme.spacing.lg

    Item {
      width: parent.width
      height: figure.height
      Caption {
        id: figure
        text: "FIG. 1 · " + (root.track ? (root.player.playing ? "NOW PLAYING" : "PAUSED") : "AT REST")
      }
      Caption {
        anchors.right: parent.right
        text: root.track ? "NO. " + Specimen.catalogue(root.track.id) : ""
      }
    }

    Lens {
      width: parent.width
      height: width
      seed: root.track ? root.track.id : ""
      progress: root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0
      alive: root.live && root.player.playing && root.moving
      awake: root.player.playing
      pulse: root.moving ? root.player.beat : 0
      palette: Theme.creatureColors
      ground: Theme.sunken
      ink: Theme.foreground
      accent: Theme.accent
      eye: Theme.mode === "light" ? Theme.background : Theme.foreground
      pupil: Theme.mode === "light" ? Theme.foreground : Theme.sunken
      stroke: Theme.stroke.hair
    }

    Spectrum {
      visible: root.moving && root.track !== null
      width: parent.width
      height: Theme.space(26)
      bands: root.player.bands
      lines: Math.max(16, Math.round(width / Theme.space(6)))
      ink: Theme.foreground
      accent: Theme.accent
      stroke: Theme.stroke.hair
      smooth: root.live
    }

    Column {
      width: parent.width
      spacing: Theme.spacing.xs

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.track ? root.track.title : "Nothing playing"
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.track ? root.track.artists.join(", ") : ""
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
    }

    Rectangle { visible: root.track !== null; width: parent.width; height: Theme.stroke.hair; color: Theme.line }

    // What the creature is made of, read off the generator, and the length.
    Column {
      visible: root.track !== null
      width: parent.width
      spacing: Theme.spacing.xs

      Repeater {
        // "3 lobes" -> { name: "lobes", value: "3" }
        model: root.track ? Specimen.traits(root.track.id).split(" · ")
          .map(function(trait) {
            var space = trait.indexOf(" ")
            return { name: trait.slice(space + 1), value: trait.slice(0, space) }
          })
          .concat([{ name: "length", value: Position.clock(root.track.duration_ms) }]) : []

        Row {
          required property var modelData
          Text {
            width: Theme.space(64)
            textFormat: Text.PlainText
            text: parent.modelData.name
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: parent.modelData.value
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }
    }
  }
}
