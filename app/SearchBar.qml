import QtQuick

// Search: which search it is, a ruled field, and under it the kinds of
// result as tabs. The window decides what Esc, Enter and the switch do.
Rectangle {
  id: root

  required property var library
  // The track list's cursor, kept for when the search is left.
  property int cursor: 0
  property alias text: field.text
  signal cancelled()
  signal finished()
  signal switchTo(string mode)

  function grab() {
    field.grab(true)
  }

  height: visible ? searchRow.height + tabs.height + Theme.stroke.hair : 0
  color: Theme.background

  Item {
    id: searchRow
    width: parent.width
    height: Theme.spacing.rowHeight + Theme.spacing.md

    Text {
      id: searchIcon
      anchors.verticalCenter: parent.verticalCenter
      x: Theme.spacing.huge
      textFormat: Text.PlainText
      // nf-md-magnify
      text: "󰍉"
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.icon
    }
    // Which search this is, since both share the field.
    Text {
      id: searchWhere
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: searchIcon.right
      anchors.leftMargin: Theme.spacing.lg
      textFormat: Text.PlainText
      text: root.library.searchMode === "library" ? "LIBRARY" : "SPOTIFY"
      color: Theme.accent
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
      font.letterSpacing: Theme.font.caption * 0.12
    }
    Field {
      id: field
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: searchWhere.right
      anchors.leftMargin: Theme.spacing.lg
      anchors.right: searchHelp.left
      anchors.rightMargin: Theme.spacing.lg
      onEdited: root.library.search(text, root.library.searchMode, root.cursor)
      onCancelled: root.cancelled()
      onAccepted: root.finished()
      onMoved: function(delta) { if (delta > 0) root.finished() }
      // Tab walks the result types instead of leaving the field.
      onTabbed: function(delta) { root.library.cycleSearchFilter(delta) }
      onOtherKey: function(event) {
        // Switch between the two searches without leaving the field.
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          root.switchTo("library")
          event.accepted = true
        }
      }
    }
    Text {
      id: searchHelp
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Theme.spacing.huge
      textFormat: Text.PlainText
      text: field.typing ? "⇥ type · ⏎ results · Esc cancel" : "/ Spotify · Ctrl F library · t type · Esc cancel"
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
  }

  // The kinds of result, as tabs: the current one in the accent, underlined.
  Row {
    id: tabs
    anchors.top: searchRow.bottom
    x: Theme.spacing.huge
    spacing: Theme.spacing.xxl

    Repeater {
      model: root.library.searchFilters

      Item {
        id: tab
        required property string modelData
        readonly property bool current: root.library.searchFilter === modelData
        width: tabText.implicitWidth
        height: tabText.implicitHeight + Theme.spacing.md + Theme.stroke.bold

        Text {
          id: tabText
          textFormat: Text.PlainText
          text: tab.modelData.toUpperCase()
          color: tab.current ? Theme.accent : (tabArea.containsMouse ? Theme.foreground : Theme.muted)
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
          font.letterSpacing: Theme.font.caption * 0.12
        }
        Rectangle {
          visible: tab.current
          anchors.bottom: parent.bottom
          width: parent.width
          height: Theme.stroke.bold
          color: Theme.accent
        }
        MouseArea {
          id: tabArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.library.setSearchFilter(tab.modelData)
        }
      }
    }
  }

  // The current tab's underline sits on this rule.
  Rectangle {
    anchors.top: tabs.bottom
    width: parent.width
    height: Theme.stroke.hair
    color: Theme.line
  }
}
