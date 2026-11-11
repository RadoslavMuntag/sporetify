import QtQuick

// A modal card in the Field Guide manner: square, a hairline border, an
// eyebrow over a title, ruled off from its content and from a line of keys
// at the foot. A click outside it dismisses it.
Rectangle {
  id: root

  property string eyebrow: ""
  property string title: ""
  property string footer: ""
  property color footerColor: Theme.muted
  property real panelWidth: Theme.space(460)
  // Height of the content; 0 lets the content fill a panel of panelHeight.
  property real contentHeight: 0
  property real panelHeight: Theme.space(480)
  // Left and right margin for content that is not edge to edge.
  readonly property real pad: Theme.spacing.huge
  default property alias content: body.data
  signal dismissed()

  anchors.fill: parent
  color: Theme.alpha(Theme.background, 0.88)

  MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

  Rectangle {
    id: panel
    // Everything but the content: margins, head, two rules, foot.
    readonly property real chrome: Theme.spacing.xxl + head.height + Theme.spacing.lg * 5
      + Theme.stroke.hair * 2 + foot.height
    anchors.centerIn: parent
    width: Math.min(parent.width - Theme.spacing.huge * 4, root.panelWidth)
    height: Math.min(parent.height - Theme.spacing.huge * 4,
      root.contentHeight > 0 ? chrome + root.contentHeight : root.panelHeight)
    color: Theme.background
    border.width: Theme.stroke.hair
    border.color: Theme.border

    MouseArea { anchors.fill: parent }

    Column {
      id: head
      x: root.pad
      y: Theme.spacing.xxl
      width: parent.width - root.pad * 2
      spacing: Theme.spacing.xs

      Text {
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.eyebrow.toUpperCase()
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: Theme.font.caption * 0.12
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.title
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.title
        font.bold: true
      }
    }
    Rectangle {
      id: topRule
      anchors.top: head.bottom
      anchors.topMargin: Theme.spacing.lg
      width: parent.width
      height: Theme.stroke.hair
      color: Theme.line
    }
    Item {
      id: body
      anchors.top: topRule.bottom
      anchors.topMargin: Theme.spacing.lg
      anchors.bottom: footRule.top
      anchors.bottomMargin: Theme.spacing.lg
      width: parent.width
    }
    Rectangle {
      id: footRule
      anchors.bottom: foot.top
      anchors.bottomMargin: Theme.spacing.lg
      width: parent.width
      height: Theme.stroke.hair
      color: Theme.line
    }
    Text {
      id: foot
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Theme.spacing.lg
      x: root.pad
      width: parent.width - root.pad * 2
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.footer
      color: root.footerColor
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
  }
}
