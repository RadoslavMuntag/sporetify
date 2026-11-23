import QtQuick

import "../common"
import "../common/Keymap.js" as Keymap

// Every key, on demand, in sections. The window sends it the moving keys
// (`scroll`); any other key or a click closes it.
Rectangle {
  id: help

  // The scopes whose keys are listed, most specific first.
  property var scopes: []
  property bool open: false
  signal closeRequested()

  visible: open
  anchors.fill: parent
  color: Theme.alpha(Theme.background, 0.94)

  MouseArea { anchors.fill: parent; onClicked: help.closeRequested() }

  // As many columns as fit, three at most.
  readonly property int columnCount: Math.max(1, Math.min(3, Math.floor((width - Theme.spacing.huge * 2) / Theme.space(300))))
  readonly property var columns: open ? Keymap.columns(scopes, columnCount) : []
  readonly property real scrollY: helpScroll.contentY
  readonly property bool scrollable: helpScroll.contentHeight > helpScroll.height + 1
  onVisibleChanged: helpScroll.contentY = 0

  // Scroll for a moving action. False when the key should close instead:
  // it is not a moving key, or everything is already on screen.
  function scroll(action) {
    if (!scrollable) return false
    var end = helpScroll.contentHeight - helpScroll.height
    var step = Theme.space(80)
    var to
    switch (action) {
    case "down": to = helpScroll.contentY + step; break
    case "up": to = helpScroll.contentY - step; break
    case "pageDown": to = helpScroll.contentY + helpScroll.height * 0.8; break
    case "pageUp": to = helpScroll.contentY - helpScroll.height * 0.8; break
    case "top": to = 0; break
    case "bottom": to = end; break
    default: return false
    }
    helpScroll.contentY = Math.max(0, Math.min(end, to))
    return true
  }

  Flickable {
    id: helpScroll
    anchors.fill: parent
    anchors.margins: Theme.spacing.huge
    contentHeight: helpBody.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: helpBody
      width: Math.min(helpScroll.width, Theme.space(1000))
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Theme.spacing.huge

      Row {
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: "Keyboard"
          color: Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.heading
          font.bold: true
        }
        Text {
          anchors.baseline: parent.children[0].baseline
          leftPadding: Theme.spacing.xxl
          textFormat: Text.PlainText
          text: help.scrollable ? Keymap.keyLabel("down") + " " + Keymap.keyLabel("up") + " scroll · any other key closes"
            : "press any key to close"
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.bodySmall
        }
      }

      Row {
        id: helpColumns
        width: parent.width
        spacing: Theme.spacing.huge * 2
        readonly property real columnWidth: (width - spacing * (help.columnCount - 1)) / help.columnCount

        Repeater {
          model: help.columns

          Column {
            id: helpColumn
            required property var modelData
            width: helpColumns.columnWidth
            spacing: Theme.spacing.huge

            Repeater {
              model: helpColumn.modelData

              // One section: a title, then its keys.
              Column {
                id: section
                required property var modelData
                width: helpColumn.width
                spacing: Theme.spacing.md

                Text {
                  textFormat: Text.PlainText
                  text: section.modelData.title.toUpperCase()
                  color: Theme.accent
                  font.family: Theme.font.family
                  font.pixelSize: Theme.font.caption
                  font.letterSpacing: Theme.font.caption * 0.12
                }
                Rectangle { width: parent.width; height: Theme.stroke.hair; color: Theme.line }

                Repeater {
                  model: section.modelData.items

                  Row {
                    id: entry
                    required property var modelData
                    width: section.width
                    spacing: Theme.spacing.xl

                    // Every key that does it, right-aligned in a fixed
                    // column so the labels line up.
                    Item {
                      width: Theme.space(92)
                      height: caps.implicitHeight
                      Row {
                        id: caps
                        anchors.right: parent.right
                        spacing: Theme.spacing.xs
                        Repeater {
                          model: entry.modelData.keys
                          KeyCap {
                            required property string modelData
                            label: modelData
                            foreground: Theme.foreground
                            fontFamily: Theme.font.family
                            fontSize: Theme.font.bodySmall
                            padding: Theme.spacing.sm
                            corner: 0
                          }
                        }
                      }
                    }
                    Text {
                      width: entry.width - Theme.space(92) - entry.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: entry.modelData.label
                      color: Theme.foreground
                      font.family: Theme.font.family
                      font.pixelSize: Theme.font.body
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
