import QtQuick
import QtQuick.Shapes

// The tide pool, drawn inside the lens (design milestone V5): the playing
// track's creature drifting in moving light, specks of matter at several
// depths, and the previous and next tracks' creatures dozing at the edges.
// On a track change they swim one place along.
//
// Everything stays inside the lens's circle by its geometry, so nothing
// needs clipping. Plain items and property animations only; nothing moves
// unless `alive`. Colours are passed in by the host.
Item {
  id: root

  // The lens's circle.
  property real r: Math.min(width, height) / 2
  property real cx: width / 2
  property real cy: height / 2

  property string seed: ""
  // The track after this one, once the host knows it; "" leaves the edge empty.
  property string nextSeed: ""
  property bool alive: false
  property bool awake: true
  // 0..1: the beat, and how loud the low end is.
  property real pulse: 0
  property real energy: 0

  property var palette: []
  property color ground
  property color ink
  property color accent
  property color eye
  property color pupil
  property real stroke: 1
  // Length of the swim on a track change; short, like every transition.
  property int swimMs: 150

  // The creatures at the edges. Remembered here, not taken from the host,
  // so a swim never starts with the wrong creature in a place.
  property string previousShown: ""
  property string nextShown: ""
  property string lastSeed: ""
  // -1..1 while swimming: how far the creatures still are from their places.
  property real slide: 0

  onSeedChanged: {
    var old = lastSeed
    var from = 0
    if (old !== "" && seed !== "" && seed === nextShown) {
      previousShown = old
      nextShown = ""
      from = 1
    } else if (old !== "" && seed !== "" && seed === previousShown) {
      nextShown = old
      previousShown = ""
      from = -1
    } else {
      previousShown = old !== "" && seed !== "" ? old : ""
      nextShown = ""
    }
    lastSeed = seed
    swim.stop()
    if (from !== 0 && alive) {
      swim.from = from
      swim.start()
    } else {
      slide = 0
    }
  }
  onNextSeedChanged: if (nextSeed !== "" && nextSeed !== seed) nextShown = nextSeed
  Component.onCompleted: {
    lastSeed = seed
    if (nextSeed !== seed) nextShown = nextSeed
  }

  NumberAnimation {
    id: swim
    target: root
    property: "slide"
    to: 0
    duration: root.swimMs
    easing.type: Easing.OutCubic
  }

  // A fixed scatter, the same every time: 0..1 from an index and a salt.
  function scatter(i, salt) {
    var v = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
    return v - Math.floor(v)
  }
  function faint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ---- Moving light: soft pools of colour wandering under the water.
  //      Each stays far enough from the rim that its edge fades out inside.
  Repeater {
    model: 3

    Shape {
      id: glow
      required property int index
      readonly property color tint: index === 2 || root.palette.length <= index ? root.accent : root.palette[index]
      readonly property real size: root.r * (0.5 + index * 0.06)
      // Each starts somewhere else, so the light is spread from the first frame.
      property real wx: reach * Math.cos(index * 2.1)
      property real wy: reach * 0.8 * Math.sin(index * 2.1)
      width: size * 2
      height: size * 2
      x: root.cx - size + wx
      y: root.cy - size + wy
      opacity: 0.55 + root.energy * 0.45
      Behavior on opacity {
        enabled: root.alive
        NumberAnimation { duration: 120 }
      }

      ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: glow.size; centerY: glow.size; centerRadius: glow.size
          focalX: glow.size; focalY: glow.size
          GradientStop { position: 0; color: root.faint(glow.tint, 0.16) }
          GradientStop { position: 1; color: root.faint(glow.tint, 0) }
        }
        PathAngleArc {
          centerX: glow.size; centerY: glow.size
          radiusX: glow.size; radiusY: glow.size
          startAngle: 0; sweepAngle: 360
        }
      }

      readonly property real reach: root.r - size - root.r * 0.06
      SequentialAnimation on wx {
        running: root.alive
        loops: Animation.Infinite
        NumberAnimation { to: glow.reach; duration: 9000 + glow.index * 2300; easing.type: Easing.InOutSine }
        NumberAnimation { to: -glow.reach; duration: 9000 + glow.index * 2300; easing.type: Easing.InOutSine }
      }
      SequentialAnimation on wy {
        running: root.alive
        loops: Animation.Infinite
        NumberAnimation { to: -glow.reach * 0.8; duration: 7100 + glow.index * 1900; easing.type: Easing.InOutSine }
        NumberAnimation { to: glow.reach * 0.8; duration: 7100 + glow.index * 1900; easing.type: Easing.InOutSine }
      }
    }
  }

  // ---- Specks of matter. Larger ones are nearer: brighter and drifting more.
  Repeater {
    model: 14

    Rectangle {
      id: speck
      required property int index
      readonly property real depth: root.scatter(index, 3)
      readonly property real angle: root.scatter(index, 1) * Math.PI * 2
      readonly property real dist: Math.sqrt(root.scatter(index, 2)) * root.r * 0.74
      readonly property real reach: root.r * (0.03 + depth * 0.07)
      property real ox: reach * (root.scatter(index, 4) * 2 - 1)
      property real oy: reach * (root.scatter(index, 5) * 2 - 1)
      width: root.stroke * (1 + depth * 2.2)
      height: width
      radius: width / 2
      x: root.cx + Math.cos(angle) * dist - width / 2 + ox
      y: root.cy + Math.sin(angle) * dist - height / 2 + oy
      color: root.faint(root.ink, 0.12 + depth * 0.22)

      SequentialAnimation on ox {
        running: root.alive
        loops: Animation.Infinite
        NumberAnimation { to: speck.reach; duration: 5200 + speck.index * 470; easing.type: Easing.InOutSine }
        NumberAnimation { to: -speck.reach; duration: 5200 + speck.index * 470; easing.type: Easing.InOutSine }
      }
      SequentialAnimation on oy {
        running: root.alive
        loops: Animation.Infinite
        NumberAnimation { to: -speck.reach; duration: 6100 + speck.index * 390; easing.type: Easing.InOutSine }
        NumberAnimation { to: speck.reach; duration: 6100 + speck.index * 390; easing.type: Easing.InOutSine }
      }
    }
  }

  // ---- The creatures. `place` is where one is: 0 the middle, -1 and 1 the
  //      edges; past them it fades out. Size and weight follow the place.
  component Swimmer: Organism {
    id: swimmer
    property real place: 0
    property int bob: 0
    readonly property real away: Math.abs(place)
    readonly property real near: Math.min(1, away)
    readonly property real size: 1 - near * 0.62
    property real driftX: 0
    property real driftY: 0

    visible: seed !== "" && away < 1.4
    width: root.r * 1.1
    height: width
    x: root.cx + place * root.r * 0.64 - width / 2 + driftX * size
    y: root.cy - height / 2 + driftY * size
    scale: size * (1 + root.pulse * 0.07 * (1 - near))
    opacity: away <= 1 ? 1 - near * 0.5 : 0.5 * Math.max(0, 1 - (away - 1) / 0.4)
    alive: root.alive && visible
    // The one in the middle is the one playing; the others doze.
    awake: root.awake && away < 0.5
    palette: root.palette
    eye: root.eye
    pupil: root.pupil
    lineArt: true
    ground: root.ground
    // Lines keep their weight when the creature is drawn smaller.
    stroke: root.stroke * 1.5 / Math.max(0.38, size)

    SequentialAnimation on driftX {
      running: swimmer.alive
      loops: Animation.Infinite
      NumberAnimation { from: -root.r * 0.05; to: root.r * 0.05; duration: 3400 + swimmer.bob * 700; easing.type: Easing.InOutSine }
      NumberAnimation { from: root.r * 0.05; to: -root.r * 0.05; duration: 3400 + swimmer.bob * 700; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on driftY {
      running: swimmer.alive
      loops: Animation.Infinite
      NumberAnimation { from: -root.r * 0.05; to: root.r * 0.05; duration: 2900 + swimmer.bob * 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: root.r * 0.05; to: -root.r * 0.05; duration: 2900 + swimmer.bob * 900; easing.type: Easing.InOutSine }
    }
  }

  Swimmer { seed: root.previousShown; place: root.slide - 1; bob: 1 }
  Swimmer { seed: root.nextShown; place: root.slide + 1; bob: 2 }
  Swimmer { seed: root.seed; place: root.slide; bob: 0; z: 1 }
}
