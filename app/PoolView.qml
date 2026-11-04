import QtQuick

import "../common"
import "../common/Position.js" as Position
import "../common/Specimen.js" as Specimen

// Into the lens (design milestone V5): the playing track's lens as large
// as the window allows, with the tide pool in it, and the track named
// under it. `z` opens it from the list; `z` or Esc goes back.
Rectangle {
  id: root

  required property var player
  // The track after this one, for the pool's edge ("" when not known).
  property string nextSeed: ""
  // Draw and move (the visuals setting), and whether the window is seen.
  property bool drawn: true
  property bool moving: true
  property bool live: true
  property bool creatures: true

  readonly property var track: player.track
  readonly property real pad: Theme.spacing.huge

  color: Theme.background

  property real nowMs: Date.now()
  readonly property real positionMs: player.player && track
    ? Position.at(player.player.position, nowMs, track.duration_ms) : 0
  Timer {
    interval: 500
    repeat: true
    running: root.visible && root.live && root.player.playing && root.track !== null
    onTriggered: root.nowMs = Date.now()
  }
  Connections {
    target: root.player
    function onPlayerChanged() { root.nowMs = Date.now() }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: Theme.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.letterSpacing: Theme.font.caption * 0.12
  }

  Item {
    id: head
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    height: figure.height
    Caption {
      id: figure
      text: "FIG. 2 · " + (!root.drawn || !root.creatures ? "THE COVER"
        : root.player.playing ? "TIDE POOL" : "TIDE POOL, STILL")
    }
    Caption {
      anchors.right: parent.right
      text: root.track ? "NO. " + Specimen.catalogue(root.track.id) : ""
    }
  }

  Lens {
    id: lens
    readonly property real room: Math.min(root.width - root.pad * 2,
      root.height - head.height - words.height - root.pad * 4)
    width: Math.max(0, room)
    height: width
    x: (root.width - width) / 2
    y: head.y + head.height + root.pad
    pool: true
    seed: root.track ? root.track.id : ""
    nextSeed: root.nextSeed
    creature: root.drawn && root.creatures
    coverPath: root.track && root.track.art_path ? root.track.art_path : ""
    progress: root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0
    alive: root.visible && root.live && root.player.playing && root.moving
    awake: root.player.playing
    pulse: root.moving ? root.player.beat : 0
    energy: root.moving ? Specimen.low(root.player.bands) : 0
    palette: Theme.creatureColors
    ground: Theme.sunken
    ink: Theme.foreground
    accent: Theme.accent
    eye: Theme.mode === "light" ? Theme.background : Theme.foreground
    pupil: Theme.mode === "light" ? Theme.foreground : Theme.sunken
    stroke: Math.max(Theme.stroke.hair, Theme.stroke.hair * lens.width / Theme.space(260))
  }

  Column {
    id: words
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.pad
    x: root.pad
    width: root.width - root.pad * 2
    spacing: Theme.spacing.xs

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.track ? root.track.title : "Nothing playing"
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: Theme.font.heading
      font.bold: true
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.track ? root.track.artists.join(", ") : ""
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.body
    }
    Caption {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.track && root.drawn && root.creatures ? Specimen.traits(root.track.id).toUpperCase() : ""
    }
  }
}
