import QtQuick

import "../app"
import "../common"
import "../common/Faults.js" as Faults
import "../common/Keymap.js" as Keymap
import "../common/Position.js" as Position
import "../common/Specimen.js" as Specimen
import "../common/Visuals.js" as Visuals

// What the compact player shows, in the Living ASCII look (D18): the pool
// fills the window with the playing track's organism in it, and a glass
// card holds its name, artist and time, below the organism when square or
// tall, beside it when wide. Scales up with the window. `pool` (`z`) hides
// the card, leaving just the water.
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
  // Just the pool, without the card (`z`); and the track after this one,
  // which swims nearby.
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

  readonly property bool scene: Visuals.drawn(root.visuals) && root.creatures
  readonly property bool showCard: !root.pool || !root.scene

  // ---- The pool, behind everything
  Water {
    id: water
    anchors.fill: parent
    visible: root.scene
    seed: root.track ? root.track.id : ""
    others: root.nextSeed !== "" ? [root.nextSeed] : []
    alive: root.live && root.playing && Visuals.moving(root.visuals)
    awake: root.playing
    blur: Visuals.moving(root.visuals) ? 1 : 0
    home: !root.showCard ? Qt.point(0.5, 0.5) : root.side ? Qt.point(0.22, 0.5) : Qt.point(0.5, 0.36)
    span: !root.showCard ? 0.8 : root.side ? 0.8 : 0.55
    specks: 12
    bubbles: 4
    passer: !root.side
    palette: Theme.creatureColors
    ground: Theme.background
    deep: Theme.sunken
    ink: Theme.foreground
    accent: Theme.accent
    muted: Theme.muted
    light: Theme.mode === "light"
    cell: Math.max(5, root.px(5))

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.lensClicked()
    }
  }

  // ---- Without the scene: the cover where the organism would be.
  Rectangle {
    anchors.fill: parent
    visible: !root.scene
    color: Theme.sunken
  }
  Image {
    visible: !root.scene && status === Image.Ready
    readonly property real room: root.side
      ? Math.min(root.height - root.pad * 2, root.width * 0.4 - root.pad * 2)
      : Math.min(root.width - root.pad * 2, card.y - labels.y - labels.height - root.gap * 2)
    width: Math.max(0, room)
    height: width
    x: root.side ? root.pad : (root.width - width) / 2
    y: root.side ? (root.height - height) / 2 : labels.y + labels.height + root.gap
    source: root.track && root.track.art_path ? "file://" + root.track.art_path : ""
    sourceSize.width: Math.ceil(width)
    sourceSize.height: Math.ceil(height)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }

  // ---- Top line: state and catalogue number, and where the keys are
  Item {
    id: labels
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    height: keysHint.height

    Label {
      anchors.left: parent.left
      anchors.right: keysHint.left
      anchors.rightMargin: root.gap
      anchors.verticalCenter: parent.verticalCenter
      text: (root.track ? (root.playing ? "now playing" : "paused") + " · No. " + Specimen.catalogue(root.track.id) : "sporetify").toUpperCase()
      color: Theme.muted
      style: Text.Outline
      styleColor: Qt.rgba(Theme.sunken.r, Theme.sunken.g, Theme.sunken.b, 0.5)
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

  // ---- The card: glass over the water
  Glass {
    id: card
    visible: root.showCard
    readonly property int inset: root.px(Theme.spacing.lg)
    x: root.side ? Math.round(root.width * 0.42) : root.pad
    width: root.width - x - root.pad
    height: root.side ? root.height - labels.y - labels.height - root.gap - root.pad : info.implicitHeight + inset * 2
    y: root.side ? labels.y + labels.height + root.gap : root.height - root.pad - height
    backdrop: root.scene ? water : null
    area: Qt.rect(x, y, width, height)
    blur: water.blur
    tint: Theme.background
    edge: Theme.foreground
    light: Theme.mode === "light"
    radius: root.px(Theme.space(6))

    // ---- Name, artist, time and traits
    Column {
      id: info
      x: card.inset
      width: card.width - card.inset * 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.px(Theme.spacing.xs)

      Spectrum {
        id: spectrum
        visible: root.showSpectrum && root.side
        width: parent.width
        height: visible ? root.px(Theme.space(22)) : 0
        bands: root.player.bands
        lines: Math.max(16, Math.round(width / root.px(Theme.space(7))))
        ink: Theme.foreground
        accent: Theme.accent
        stroke: Math.max(Theme.stroke.hair, root.zoom)
        smooth: root.live
      }
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
      Label {
        width: parent.width
        text: root.byline
        // Messages wrap; a long setup command may break anywhere.
        wrapMode: root.track ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: root.track ? 1 : 5
        color: root.bylineIsError ? Theme.urgent : Theme.muted
      }
      Label {
        width: parent.width
        visible: root.track !== null && root.side && root.track.album !== undefined && root.track.album !== ""
        text: root.track && root.track.album ? root.track.album : ""
        color: Theme.muted
        font.pixelSize: root.px(Theme.font.bodySmall)
      }
      // The position, in characters: lit up to where the track is.
      Text {
        id: progressBar
        visible: root.track !== null
        width: parent.width
        clip: true
        textFormat: Text.StyledText
        font.family: Theme.font.family
        font.pixelSize: root.px(Theme.font.bodySmall)
        readonly property int cells: Math.max(4, Math.floor(width / Math.max(1, metrics.averageCharacterWidth)))
        readonly property var parts: Specimen.bar(root.track && root.track.duration_ms > 0 ? root.positionMs / root.track.duration_ms : 0, cells)
        color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.3)
        text: "<font color=\"" + Theme.accent + "\">" + parts.done + "</font>" + parts.rest
        FontMetrics {
          id: metrics
          font: progressBar.font
        }
      }
      Item {
        visible: root.track !== null
        width: parent.width
        height: clock.implicitHeight
        Label {
          id: clock
          text: root.track ? Position.clock(root.positionMs) : ""
          color: Theme.muted
          font.pixelSize: root.px(Theme.font.caption)
        }
        Label {
          anchors.right: parent.right
          text: root.track ? Position.clock(root.track.duration_ms) : ""
          color: Theme.muted
          font.pixelSize: root.px(Theme.font.caption)
        }
      }
      Label {
        width: parent.width
        visible: root.track !== null && root.scene
        text: root.track ? Specimen.traits(root.track.id) : ""
        color: Theme.muted
        opacity: 0.75
        font.pixelSize: root.px(Theme.font.caption)
      }
    }
  }
}
