import QtQuick

import "Organism.js" as Organism

// Draws the creature for a track: a soft body of overlapping lobes, a
// nucleus, eyes, and hairs that sway. Every moving part is a plain property
// animation, so nothing runs per frame in JavaScript, and nothing runs at
// all unless `alive` is true.
//
// Colours come from the host (theme tokens); the creature only chooses
// among them.
Item {
  id: root

  // What the creature is grown from; normally a track uri.
  property string seed: ""
  // Animate. The host should make this false whenever the creature is not
  // on screen or nothing is playing.
  property bool alive: false
  // Eyes open. A paused track's creature dozes.
  property bool awake: true
  // Body colours to choose from.
  property var palette: []
  property color eye
  property color pupil

  readonly property var shape: Organism.create(seed)
  readonly property real unit: Math.min(width, height)
  // Below this size hairs and the nucleus are noise, so they are left out.
  readonly property bool detailed: unit >= 28

  readonly property color body: {
    var chosen = Organism.pick(palette, shape.tone)
    return chosen !== undefined ? chosen : eye
  }
  readonly property color detail: {
    var chosen = Organism.pick(palette, shape.accent)
    return chosen !== undefined ? chosen : pupil
  }

  // 1 = open, towards 0 = closed. Blinking animates this.
  property real lid: 1
  readonly property real eyeOpen: (awake ? 1 : 0.3) * lid

  SequentialAnimation {
    running: root.alive && root.awake && root.detailed
    loops: Animation.Infinite
    PauseAnimation { duration: 2400 + root.shape.drift * 3600 }
    NumberAnimation { target: root; property: "lid"; to: 0.1; duration: 70 }
    NumberAnimation { target: root; property: "lid"; to: 1; duration: 110 }
    onRunningChanged: if (!running) root.lid = 1
  }

  Item {
    id: creature
    width: root.unit
    height: root.unit
    anchors.centerIn: parent

    // One slow breath of the whole body.
    SequentialAnimation on scale {
      running: root.alive
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 1.05; duration: root.shape.breath / 2; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.05; to: 1; duration: root.shape.breath / 2; easing.type: Easing.InOutSine }
    }

    // ---- Hairs, drawn first so the body covers their roots.
    Repeater {
      model: root.detailed ? root.shape.cilia : []

      Item {
        id: hair
        required property var modelData
        required property int index
        x: creature.width / 2
        y: creature.height / 2
        rotation: modelData.angle

        SequentialAnimation on rotation {
          running: root.alive
          loops: Animation.Infinite
          NumberAnimation {
            from: hair.modelData.angle - 7; to: hair.modelData.angle + 7
            duration: 1300 + hair.index * 170; easing.type: Easing.InOutSine
          }
          NumberAnimation {
            from: hair.modelData.angle + 7; to: hair.modelData.angle - 7
            duration: 1300 + hair.index * 170; easing.type: Easing.InOutSine
          }
        }

        Rectangle {
          width: hair.modelData.width * root.unit
          height: (root.shape.lobes[0].r + hair.modelData.length) * root.unit
          x: -width / 2
          y: -height
          radius: width / 2
          color: Qt.darker(root.body, 1.25)
        }
      }
    }

    // ---- Body: overlapping circles of one colour read as a single blob.
    Repeater {
      model: root.shape.lobes

      Rectangle {
        id: lobe
        required property var modelData
        width: modelData.r * 2 * root.unit
        height: width
        radius: width / 2
        x: modelData.x * root.unit - width / 2
        y: modelData.y * root.unit - height / 2
        color: root.body

        SequentialAnimation on scale {
          running: root.alive
          loops: Animation.Infinite
          NumberAnimation {
            from: 1; to: 1 + lobe.modelData.swell
            duration: lobe.modelData.period / 2; easing.type: Easing.InOutSine
          }
          NumberAnimation {
            from: 1 + lobe.modelData.swell; to: 1
            duration: lobe.modelData.period / 2; easing.type: Easing.InOutSine
          }
        }
      }
    }

    // ---- Nucleus
    Rectangle {
      visible: root.detailed
      width: root.shape.core.r * 2 * root.unit
      height: width
      radius: width / 2
      x: root.shape.core.x * root.unit - width / 2
      y: (root.shape.core.y + 0.1) * root.unit - height / 2
      color: root.detail
      opacity: 0.5
    }

    // ---- Eyes
    Repeater {
      // At icon size a single eye reads better than a cluster of dots.
      model: root.detailed ? root.shape.eyes : [{ x: 0.5, y: 0.47, r: 0.13 }]

      Item {
        id: socket
        required property var modelData
        readonly property real size: modelData.r * 2 * root.unit
        x: modelData.x * root.unit - size / 2
        y: modelData.y * root.unit - size / 2
        width: size
        height: size

        Rectangle {
          anchors.centerIn: parent
          width: socket.size
          height: Math.max(1, socket.size * root.eyeOpen)
          radius: Math.min(width, height) / 2
          color: root.eye
          clip: true
          Behavior on height { NumberAnimation { duration: 120 } }

          Rectangle {
            anchors.centerIn: parent
            width: socket.size * 0.5
            height: width
            radius: width / 2
            color: root.pupil
          }
        }
      }
    }
  }
}
