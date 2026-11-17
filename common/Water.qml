import QtQuick
import QtQuick.Effects

import "Organism.js" as Organism

// The Living ASCII pool (decision D18): the water (shaders/water.frag), the
// playing track's organism large near `home`, the queue's organisms smaller
// around it, a soft glow under them and, at full blur, one large organism
// drifting past out of focus in front.
//
// Nothing moves unless `alive`: every motion is a property animation or the
// shaders' `time`, and both stop together. Colours come from the host.
Item {
  id: root

  property string seed: ""
  // Other tracks to show around it, nearest first (previous, next, queue).
  property var others: []
  property bool alive: false
  property bool awake: true
  // 0 crisp, 1 balanced, 1.9 dreamy.
  property real blur: 1
  // Where the playing organism lives, as fractions of the scene, and how
  // tall its space is as a fraction of the scene's height.
  property point home: Qt.point(0.5, 0.42)
  property real span: 0.62
  // How much life the water has; small scenes want less.
  property int specks: 30
  property int bubbles: 6
  property int weeds: 0
  property bool passer: true

  property var palette: []
  property color ground
  property color deep
  property color ink
  property color accent
  property color muted
  property bool light: false
  // Cell width in px; a cell is twice as tall.
  property real cell: Math.max(5, Math.round(Math.min(width, height) / 110))

  function colourAt(i, fallback) { return palette && palette.length > i ? palette[i] : fallback }

  // Seconds; one clock for the water and every drift.
  property real clock: 0
  NumberAnimation on clock {
    from: 0
    to: 3600
    duration: 3600000
    loops: Animation.Infinite
    running: true
    paused: !root.alive
  }

  // ---- Glyphs for the water, drawn once.
  readonly property string glyphs: " .·,'-~+*oO°|/\\()"
  Row {
    id: atlasRow
    Repeater {
      model: root.glyphs.length
      Text {
        required property int index
        // At the cell's own size, so strokes keep their full strength.
        width: Math.max(3, Math.round(root.cell))
        height: width * 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyphs[index]
        color: root.ink
        font.family: "monospace"
        font.pixelSize: Math.round(width / 0.6)
        font.weight: Font.Medium
      }
    }
  }
  ShaderEffectSource {
    id: waterAtlas
    sourceItem: atlasRow
    hideSource: true
    smooth: false
    // Mip levels soften the far layer.
    mipmap: true
  }

  ShaderEffect {
    anchors.fill: parent
    fragmentShader: "shaders/water.frag.qsb"
    property var atlas: waterAtlas
    property size area: Qt.size(width, height)
    property real cell: root.cell
    property real time: root.clock
    property real blur: root.blur
    property real light: root.light ? 1 : 0
    property real glyphs: root.glyphs.length
    property real specks: root.specks
    property real bubbles: root.bubbles
    property real weeds: root.weeds
    property real seed: Organism.hash(root.seed) % 997
    property color ground: root.ground
    property color deep: root.deep
    property color accent: root.accent
    property color ink: root.ink
    property color muted: root.muted
    // magenta, yellow and cyan, as the mockup lights its water
    property color tint0: root.colourAt(3, root.accent)
    property color tint1: root.colourAt(4, root.accent)
    property color tint2: root.colourAt(1, root.accent)
    property color weedA: root.colourAt(0, root.accent)
    property color weedB: root.colourAt(1, root.accent)
  }

  // ---- The organisms. The playing one is large; the rest smaller and
  //      spread out, each with a home of its own taken from its id.
  readonly property var swimmers: {
    var out = root.seed !== "" ? [root.seed] : []
    for (var i = 0; i < root.others.length && out.length < 5; i++)
      if (root.others[i] && out.indexOf(root.others[i]) === -1) out.push(root.others[i])
    return out
  }

  Item {
    id: life
    anchors.fill: parent

    Repeater {
      model: root.swimmers

      Plankton {
        id: swimmer
        required property string modelData
        required property int index
        readonly property bool main: index === 0 && root.seed !== ""
        readonly property real side: root.height * root.span * (main ? 1 : 0.4)
        readonly property real hx: main ? root.home.x : 0.2 + (Organism.hash(modelData + "~hx") % 1000) / 1000 * 0.6
        readonly property real hy: main ? root.home.y : 0.25 + (Organism.hash(modelData + "~hy") % 1000) / 1000 * 0.45
        property real dx: 0
        property real dy: 0
        width: side
        height: side
        x: root.width * hx - width / 2 + dx
        y: root.height * hy - height / 2 + dy
        z: main ? 1 : 0
        seed: modelData
        alive: root.alive
        awake: root.awake && main
        palette: root.palette
        ink: root.ink
        accent: root.accent
        light: root.light
        cell: root.cell
        opacity: main ? 1 : 0.8
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        // A slow glide around its home: the playing one stays close, the
        // rest wander further.
        readonly property real reach: root.height * (main ? 0.04 : 0.09)
        SequentialAnimation on dx {
          running: root.alive
          loops: Animation.Infinite
          NumberAnimation { to: swimmer.reach; duration: 11000 + swimmer.index * 2300; easing.type: Easing.InOutSine }
          NumberAnimation { to: -swimmer.reach; duration: 11000 + swimmer.index * 2300; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on dy {
          running: root.alive
          loops: Animation.Infinite
          NumberAnimation { to: -swimmer.reach * 0.7; duration: 8300 + swimmer.index * 1700; easing.type: Easing.InOutSine }
          NumberAnimation { to: swimmer.reach * 0.7; duration: 8300 + swimmer.index * 1700; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  // ---- Glow: a blurred copy of the organisms added on top, so the
  //      glyphs look lit from inside and light spills into the water.
  MultiEffect {
    id: glowBlur
    anchors.fill: life
    visible: false
    layer.enabled: root.blur > 0
    source: life
    blurEnabled: true
    // Tight, as the mockup's bloom: a wide blur thins the light out.
    blurMax: 16
    blur: 0.5 + root.blur * 0.2
    brightness: 0.1
  }
  ShaderEffect {
    anchors.fill: life
    visible: root.blur > 0
    fragmentShader: "shaders/glow.frag.qsb"
    property var source: glowBlur
    property real strength: 0.9 + root.blur * 0.35
    property real light: root.light ? 1 : 0
  }

  // ---- One large organism drifting past in front, out of focus.
  Loader {
    active: root.passer && root.blur > 0 && root.seed !== ""
    anchors.fill: parent
    sourceComponent: Item {
      Plankton {
        id: passing
        width: root.height * 1.1
        height: width
        y: root.height * 0.55
        x: -width + (root.width + width * 2) * ((root.clock / 140) % 1)
        visible: false
        seed: "passer:" + root.seed
        alive: root.alive
        palette: root.palette
        ink: root.ink
        accent: root.accent
        light: root.light
        cell: root.cell * 1.6
      }
      MultiEffect {
        anchors.fill: passing
        source: passing
        blurEnabled: true
        blurMax: 48
        blur: 1
        opacity: root.blur * 0.4
      }
    }
  }
}
