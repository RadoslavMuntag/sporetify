import QtQuick

import "../app"
import "../common"
import "../common/Faults.js" as Faults
import "../common/Keymap.js" as Keymap
import "../common/Position.js" as Position
import "../common/Specimen.js" as Specimen
import "../common/Visuals.js" as Visuals

// What the compact player shows: the playing track as a specimen under the
// lens, with its name, artist and time. Lays itself out from its own
// proportions, lens above the text when square or tall, beside it when
// wide, and scales up with the window so it looks right at any size.
Item {
  id: root

  // A Player (common/Player.qml), or anything with the same properties.
  required property var player
  // full | reduced | off
  property string visuals: "full"
  // Draw the creature; off, the lens shows the cover.
  property bool creatures: true
  // Whether the window is showing; nothing moves or ticks otherwise.
  property bool live: true
  // The tide pool in the lens (`z`), and the track after this one for its edge.
  property bool pool: false
  property string nextSeed: ""
  signal lensClicked()

  readonly property var track: player.track
  readonly property bool playing: player.playing
  readonly property string arrangement: Specimen.arrangement(width, height)
  readonly property bool side: arrangement === "side"

  // Everything grows with the window, from 1 at about 300 px.
  // When wide, the text has about half the width, so that half decides.
  readonly property real zoom: Math.max(1, Math.min(2.4, Math.min(side ? width * 0.5 : width, height) / Theme.space(300)))
  function px(size) { return Math.round(size * zoom) }
  readonly property int pad: px(Theme.spacing.huge)
  readonly property int gap: px(Theme.spacing.lg)

  property real nowMs: Date.now()
  readonly property real positionMs: player.player && track
    ? Position.at(player.player.position, nowMs, track.duration_ms) : 0
  Timer {
    interval: 500
    repeat: true
    running: root.live && root.playing && root.track !== null
    onTriggered: root.nowMs = Date.now()
  }
  Connections {
    target: root.player
    function onPlayerChanged() { root.nowMs = Date.now() }
  }

  // ---- Words. Without a track the lens rests and the text says why.
  readonly property string headline: {
    if (track) return track.title
    if (player.phase === "starting" || player.phase === "asleep") return "Starting…"
    return Faults.title(player.phase) || "Nothing playing"
  }
  readonly property string byline: {
    if (player.lastError !== "") return player.lastError
    if (track) return track.artists.join(", ")
    if (player.scope === "signedOut") return "Press " + Keymap.keyLabel("signIn") + " to sign in"
    if (player.scope === "fault") {
      return Faults.command(player.phase) !== ""
        ? Faults.advice(player.phase) + " " + Faults.command(player.phase)
        : "Press " + Keymap.keyLabel("retry") + " to retry"
    }
    if (player.phase === "ready") return "Press " + Keymap.keyLabel("playPause") + " to play"
    return ""
  }
  readonly property bool bylineIsError: player.lastError !== "" || player.scope === "fault"
  // The spectrum is part of the moving picture: only with visuals at full.
  readonly property bool showSpectrum: track !== null && Visuals.moving(visuals)

  component Label: Text {
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.foreground
    font.family: Theme.font.family
    font.pixelSize: root.px(Theme.font.body)
  }

  // ---- Top line: state and catalogue number, and where the keys are
  Item {
    id: labels
    x: root.side ? lens.x + lens.width + root.pad : root.pad
    y: root.pad
    width: root.width - x - root.pad
    height: keysHint.height

    Label {
      anchors.left: parent.left
      anchors.right: keysHint.left
      anchors.rightMargin: root.gap
      anchors.verticalCenter: parent.verticalCenter
      text: (root.track ? (root.playing ? "now playing" : "paused") + " · No. " + Specimen.catalogue(root.track.id) : "sporetify").toUpperCase()
      color: Theme.muted
      font.pixelSize: root.px(Theme.font.caption)
      font.letterSpacing: root.px(Theme.font.caption) * 0.12
    }
    Row {
      id: keysHint
      anchors.right: parent.right
      spacing: root.px(Theme.spacing.sm)

      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        label: Keymap.keyLabel("compactKeys")
        foreground: Theme.foreground
        fontFamily: Theme.font.family
        fontSize: root.px(Theme.font.caption)
        padding: root.px(Theme.spacing.xs)
        radius: 0
      }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: "keys"
        color: Theme.muted
        font.pixelSize: root.px(Theme.font.caption)
      }
    }
  }

  // ---- The lens
  Lens {
    id: lens
    // Wide: at most a little under half the width, so the text keeps room.
    readonly property real room: root.side
      ? Math.min(root.height - root.pad * 2, root.width * 0.45)
      : Math.min(root.width - root.pad * 2, above.y - labels.y - labels.height - root.gap * 2)
    width: Math.max(0, room)
    height: width
    x: root.side ? root.pad : (root.width - width) / 2
    y: root.side ? (root.height - height) / 2 : labels.y + labels.height + root.gap + (above.y - root.gap - labels.y - labels.height - root.gap - height) / 2

    seed: root.track ? root.track.id : ""
    progress: root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0
    creature: Visuals.drawn(root.visuals) && root.creatures
    coverPath: root.track && root.track.art_path ? root.track.art_path : ""
    alive: root.live && root.playing && Visuals.moving(root.visuals)
    awake: root.playing
    pulse: root.showSpectrum ? root.player.beat : 0
    pool: root.pool
    nextSeed: root.nextSeed
    energy: root.showSpectrum ? Specimen.low(root.player.bands) : 0
    palette: Theme.creatureColors
    ground: Theme.sunken
    ink: Theme.foreground
    accent: Theme.accent
    // Eyes are drawn light with dark pupils in either kind of theme.
    eye: Theme.mode === "light" ? Theme.background : Theme.foreground
    pupil: Theme.mode === "light" ? Theme.foreground : Theme.sunken
    stroke: Math.max(Theme.stroke.hair, root.zoom)

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.lensClicked()
    }
  }

  // What the lens sits above when stacked: the spectrum, or the text.
  readonly property Item above: spectrum.visible ? spectrum : info

  // ---- The music, as fine lines on a hairline
  Spectrum {
    id: spectrum
    visible: root.showSpectrum
    x: labels.x
    width: labels.width
    height: root.px(Theme.space(26))
    y: info.y - root.gap - height
    bands: root.player.bands
    lines: Math.max(16, Math.round(width / root.px(Theme.space(7))))
    ink: Theme.foreground
    accent: Theme.accent
    stroke: Math.max(Theme.stroke.hair, root.zoom)
    smooth: root.live
  }

  // ---- Name, artist, time and traits
  Column {
    id: info
    x: labels.x
    width: labels.width
    y: root.height - root.pad - height
    spacing: root.px(Theme.spacing.xs)

    Label {
      width: parent.width
      text: root.headline
      // A track's name stays on one line; a message may need two.
      wrapMode: root.track ? Text.NoWrap : Text.Wrap
      maximumLineCount: root.track ? 1 : 2
      font.pixelSize: root.px(Theme.font.heading)
      font.bold: true
      color: !root.track && root.player.scope === "fault" ? Theme.urgent : Theme.foreground
    }
    Item {
      width: parent.width
      height: byline.implicitHeight

      Label {
        id: byline
        anchors.left: parent.left
        anchors.right: clock.left
        anchors.rightMargin: root.gap
        text: root.byline
        // Messages wrap; a long setup command may break anywhere.
        wrapMode: root.track ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: root.track ? 1 : 5
        color: root.bylineIsError ? Theme.urgent : Theme.muted
      }
      Label {
        id: clock
        anchors.right: parent.right
        visible: root.track !== null
        width: visible ? implicitWidth : 0
        text: root.track ? Position.clock(root.positionMs) + " / " + Position.clock(root.track.duration_ms) : ""
        color: Theme.muted
        font.pixelSize: root.px(Theme.font.bodySmall)
      }
    }
    Label {
      width: parent.width
      visible: root.track !== null && root.side && root.track.album !== undefined && root.track.album !== ""
      text: root.track && root.track.album ? root.track.album : ""
      color: Theme.muted
      font.pixelSize: root.px(Theme.font.bodySmall)
    }
    Label {
      width: parent.width
      visible: root.track !== null && Visuals.drawn(root.visuals) && root.creatures
      text: root.track ? Specimen.traits(root.track.id) : ""
      color: Theme.muted
      opacity: 0.75
      font.pixelSize: root.px(Theme.font.caption)
    }
  }
}
