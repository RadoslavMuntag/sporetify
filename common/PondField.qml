import QtQuick

// The water's own light as a field over the character grid
// (shaders/pond.frag), filling a FieldLayer: part 1 the ripples of the far
// layer, part 2 the snow, specks, bubbles and weeds of the near one. Put
// it first in the layer; organisms draw over it.
ShaderEffect {
  id: root

  property real part: 1
  property real time: 0
  property size grid: Qt.size(1, 1)
  property real snow: 0
  property real specks: 0
  property real bubbles: 0
  property real weeds: 0
  property real seed: 0
  property color ink
  property color accent
  property color muted
  property color tint
  property color weedA
  property color weedB

  // Counts and `part` are reals: the shader reads floats, and an int
  // property reaches it as an int's bits, which read as about zero (the
  // ripples then filled the near layer and no snow fell, until 2026-11-22).
  anchors.fill: parent
  blending: false
  fragmentShader: "shaders/pond.frag.qsb"
}
