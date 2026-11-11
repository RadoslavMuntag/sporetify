import QtQuick

// The Field Guide cursor: corner brackets, top left and bottom right, in
// the accent colour. Fills its parent.
Item {
  id: root

  property real insetX: Theme.spacing.md
  property real insetY: Theme.spacing.xs
  property real arm: Theme.space(10)
  property real weight: Theme.stroke.bold
  property color color: Theme.accent

  anchors.fill: parent

  Rectangle { x: root.insetX; y: root.insetY; width: root.arm; height: root.weight; color: root.color }
  Rectangle { x: root.insetX; y: root.insetY; width: root.weight; height: root.arm; color: root.color }
  Rectangle {
    x: root.width - root.insetX - width; y: root.height - root.insetY - height
    width: root.arm; height: root.weight; color: root.color
  }
  Rectangle {
    x: root.width - root.insetX - width; y: root.height - root.insetY - height
    width: root.weight; height: root.arm; color: root.color
  }
}
