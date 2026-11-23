import QtQuick

// The water's own light as a field over the character grid
// (shaders/pond.frag), filling a FieldLayer: part 1 the ripples of the far
// layer, part 2 the snow, specks, bubbles and weeds of the near one. Put
// it first in the layer; organisms draw over it.
ShaderEffect {
  id: root

  property int part: 1
  property real time: 0
  property size grid: Qt.size(1, 1)
  property int snow: 0
  property int specks: 0
  property int bubbles: 0
  property int weeds: 0
  property real seed: 0
  property color ink
  property color accent
  property color muted
  property color tint
  property color weedA
  property color weedB

  anchors.fill: parent
  blending: false
  fragmentShader: "shaders/pond.frag.qsb"
}
