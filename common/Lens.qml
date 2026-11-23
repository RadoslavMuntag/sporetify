import QtQuick
import QtQuick.Effects

import "Specimen.js" as Specimen

// The Field Guide's lens: a round slide with graph paper, the track's
// creature drawn as line art under it, and a ring of ticks around the rim
// that doubles as the progress bar. With creatures off the cover fills the
// lens instead, so it still says what is playing.
//
// Plain items only. Nothing moves unless `alive`; progress changes only
// when the host updates `progress`.
Item {
  id: root

  property string seed: ""
  // 0..1 through the track.
  property real progress: 0
  // Drift and breathe. The host clears this when hidden, paused or reduced.
  property bool alive: false
  property bool awake: true
  // 0..1: the beat. The specimen swells with it.
  property real pulse: 0
  // Draw the creature; when false the cover is shown in the lens.
  property bool creature: true
  property string coverPath: ""
  // Show the tide pool in the lens instead of the slide (common/TidePool.qml),
  // with the next track's creature at its edge once known, and the low end
  // of the music (0..1) brightening its light.
  property bool pool: false
  property string nextSeed: ""
  property real energy: 0
  readonly property bool showPool: pool && creature

  // Colours, from the host's theme.
  property var palette: []
  // Inside of the lens.
  property color ground
  // Rim, ticks and grid.
  property color ink
  property color accent
  property color eye
  property color pupil
  property real stroke: 1

  // Ticks run out to 1.15 r and the cross marks to 1.34 r.
  readonly property real r: Math.min(width, height) / 2 / 1.36
  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property int ticks: 72
  readonly property int lit: Specimen.lit(progress, ticks)

  function faint(a) { return Qt.rgba(ink.r, ink.g, ink.b, a) }

  // ---- The slide
  Rectangle {
    x: root.cx - root.r
    y: root.cy - root.r
    width: root.r * 2
    height: width
    radius: root.r
    color: root.ground
  }

  // ---- Graph paper, each line cut to the rim
  Repeater {
    model: root.creature && !root.pool ? Specimen.chords(6) : []

    Item {
      required property var modelData
      Rectangle {
        x: root.cx + parent.modelData.offset * root.r - width / 2
        y: root.cy - parent.modelData.half * root.r
        width: root.stroke
        height: parent.modelData.half * root.r * 2
        color: root.faint(0.07)
      }
      Rectangle {
        x: root.cx - parent.modelData.half * root.r
        y: root.cy + parent.modelData.offset * root.r - height / 2
        width: parent.modelData.half * root.r * 2
        height: root.stroke
        color: root.faint(0.07)
      }
    }
  }

  // ---- The specimen, drifting a little while alive
  Organism {
    id: specimen
    visible: root.creature && !root.pool
    width: root.r * 1.6
    height: width
    x: root.cx - width / 2 + driftX
    y: root.cy - height / 2 + driftY
    property real driftX: 0
    property real driftY: 0
    seed: root.seed
    alive: root.alive && visible
    awake: root.awake
    palette: root.palette
    eye: root.eye
    pupil: root.pupil
    lineArt: true
    ground: root.ground
    stroke: root.stroke * 1.5
    scale: 1 + root.pulse * 0.07
    Behavior on scale {
      enabled: specimen.alive
      NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
    }

    SequentialAnimation on driftX {
      running: specimen.alive
      loops: Animation.Infinite
      NumberAnimation { from: -root.r * 0.05; to: root.r * 0.05; duration: 3400; easing.type: Easing.InOutSine }
      NumberAnimation { from: root.r * 0.05; to: -root.r * 0.05; duration: 3400; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on driftY {
      running: specimen.alive
      loops: Animation.Infinite
      NumberAnimation { from: -root.r * 0.04; to: root.r * 0.04; duration: 2900; easing.type: Easing.InOutSine }
      NumberAnimation { from: root.r * 0.04; to: -root.r * 0.04; duration: 2900; easing.type: Easing.InOutSine }
    }
  }

  // ---- The tide pool, made only while it shows.
  Loader {
    anchors.fill: parent
    active: root.showPool
    sourceComponent: TidePool {
      r: root.r
      cx: root.cx
      cy: root.cy
      seed: root.seed
      nextSeed: root.nextSeed
      alive: root.alive
      awake: root.awake
      pulse: root.pulse
      energy: root.energy
      palette: root.palette
      ground: root.ground
      ink: root.ink
      accent: root.accent
      eye: root.eye
      pupil: root.pupil
      stroke: root.stroke
    }
  }

  // ---- Cover, when creatures are off: filling the lens, cut to its circle.
  //      The mask is drawn once per cover, not per frame. Made only while it
  //      shows: the effect takes its mask when it is created, so a mask made
  //      later (creatures turned off while running) left the lens empty.
  readonly property bool showCover: !creature && coverPath !== ""

  Loader {
    active: root.showCover
    x: root.cx - root.r
    y: root.cy - root.r
    width: root.r * 2
    height: width

    sourceComponent: Item {
      Image {
        id: cover
        visible: false
        anchors.fill: parent
        source: "file://" + root.coverPath
        sourceSize.width: Math.ceil(width)
        sourceSize.height: Math.ceil(height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
      Rectangle {
        id: circle
        visible: false
        layer.enabled: true
        layer.smooth: true
        anchors.fill: parent
        radius: width / 2
        color: root.ink
      }
      MultiEffect {
        visible: cover.status === Image.Ready
        source: cover
        anchors.fill: parent
        maskEnabled: true
        maskSource: circle
        // Soft by a pixel at the edge, so the circle is not jagged.
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
  }

  // ---- Rim
  Rectangle {
    x: root.cx - root.r
    y: root.cy - root.r
    width: root.r * 2
    height: width
    radius: root.r
    color: "transparent"
    border.width: root.stroke
    border.color: root.faint(0.4)
  }

  // ---- Ticks: one per five degrees, longer every thirty; lit up to the
  //      playing position.
  Repeater {
    model: root.ticks

    Item {
      required property int index
      readonly property bool long: index % 6 === 0
      readonly property bool on: index < root.lit
      x: root.cx
      y: root.cy
      rotation: index * 360 / root.ticks

      Rectangle {
        width: parent.on ? root.stroke * 1.6 : root.stroke
        height: root.r * (parent.long ? 0.09 : 0.04)
        x: -width / 2
        y: -root.r * 1.06 - height
        color: parent.on ? root.accent : root.faint(0.35)
      }
    }
  }

  // ---- Where the track is now
  Item {
    visible: root.progress > 0
    x: root.cx
    y: root.cy
    rotation: root.progress * 360

    Rectangle {
      width: root.stroke * 2.5
      height: root.r * 0.1
      x: -width / 2
      y: -root.r * 1.26
      radius: width / 2
      color: root.accent
    }
  }

  // ---- Cross marks at the four quarters
  Repeater {
    model: 4

    Item {
      required property int index
      x: root.cx
      y: root.cy
      rotation: index * 90

      Rectangle {
        width: root.stroke
        height: root.r * 0.08
        x: -width / 2
        y: -root.r * 1.34
        color: root.faint(0.5)
      }
    }
  }
}
