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
  // Draw the creature; off, the lens shows the cover.
  property bool creatures: true
  // The Living ASCII pool is behind this plate (D18): the organism swims
  // there, so the lens is left out and the plate is open water.
  property bool inWater: false
  // Where the organism should swim, in this plate's coordinates, and how
  // much room it has.
  readonly property real waterTop: root.pad + figureRow.height + Theme.spacing.lg
  readonly property real waterBottom: overlay.y - Theme.spacing.lg
  readonly property point waterAt: Qt.point(root.width / 2, (waterTop + waterBottom) / 2)
  readonly property real waterRoom: Math.max(0, Math.min(root.width - root.pad * 2, waterBottom - waterTop))

  readonly property var track: player.track
  readonly property real pad: Theme.spacing.huge

  color: inWater ? "transparent" : Theme.background

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

  Rectangle { visible: !root.inWater; width: Theme.stroke.hair; height: parent.height; color: Theme.line }

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
      id: figureRow
      width: parent.width
      height: figure.height
      Caption {
        id: figure
        text: root.inWater ? "THE POOL" : "FIG. 1 · " + (root.track ? (root.player.playing ? "NOW PLAYING" : "PAUSED") : "AT REST")
      }
      Caption {
        anchors.right: parent.right
        text: root.track ? "NO. " + Specimen.catalogue(root.track.id) : ""
      }
    }

    Lens {
      id: plateLens
      width: parent.width
      height: width
      visible: !root.inWater
      seed: root.track ? root.track.id : ""
      creature: root.creatures
      coverPath: root.track && root.track.art_path ? root.track.art_path : ""
      progress: root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0
      alive: root.live && root.player.playing && root.moving && !root.inWater
      awake: root.player.playing
      pulse: root.moving ? root.player.beat : 0
      palette: Theme.creatureColors
      ground: Theme.sunken
      ink: Theme.foreground
      accent: Theme.accent
      eye: Theme.mode === "light" ? Theme.background : Theme.foreground
      pupil: Theme.mode === "light" ? Theme.foreground : Theme.sunken
      stroke: Theme.stroke.hair
      light: Theme.mode === "light"
    }

    Spectrum {
      visible: root.moving && root.track !== null && !root.inWater
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
      visible: !root.inWater
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

    Rectangle { visible: root.track !== null && !root.inWater; width: parent.width; height: Theme.stroke.hair; color: Theme.line }

    // What the creature is made of, read off the generator, and the length.
    Column {
      visible: root.track !== null && root.creatures && !root.inWater
      width: parent.width
      spacing: Theme.spacing.xs

      Repeater {
        model: root.track ? Specimen.table(root.track.id)
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

  // ---- In the water: the track over the pool, at the bottom.
  Column {
    id: overlay
    visible: root.inWater
    x: root.pad
    width: root.width - root.pad * 2
    y: root.height - root.pad - height
    spacing: Theme.spacing.xs

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.track ? root.track.title : "Nothing playing"
      color: Theme.foreground
      style: Text.Outline
      styleColor: Qt.rgba(Theme.sunken.r, Theme.sunken.g, Theme.sunken.b, 0.4)
      font.family: Theme.font.family
      font.pixelSize: Math.round(Theme.font.body * 1.5)
      font.bold: true
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.track ? root.track.artists.join(", ") : ""
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.body
    }
    Text {
      visible: root.track !== null && root.creatures
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.track ? Specimen.traits(root.track.id) : ""
      color: Theme.muted
      opacity: 0.75
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
  }
}
