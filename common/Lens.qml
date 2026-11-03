import QtQuick

import "Specimen.js" as Specimen

// The Field Guide's lens: a round slide with graph paper, the track's
// creature drawn as line art under it, and a ring of ticks around the rim
// that doubles as the progress bar. With creatures off it shows the cover
// instead, so it still says what is playing.
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
    model: root.creature ? Specimen.chords(6) : []

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
    visible: root.creature
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

  // ---- Cover, when creatures are off: the largest square the lens holds
  Image {
    visible: !root.creature && root.coverPath !== ""
    width: root.r * Math.SQRT2
    height: width
    x: root.cx - width / 2
    y: root.cy - height / 2
    source: visible ? "file://" + root.coverPath : ""
    sourceSize.width: Math.ceil(width)
    sourceSize.height: Math.ceil(height)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
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
