import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

import "common"
import "common/Keymap.js" as Keymap
import "common/Position.js" as Position

// The popup under the bar icon: what is playing, transport, seek, volume,
// and a footer listing every key that works here. Keyboard handling and all
// hints come from Keymap, so they cannot drift apart.
KeyboardPanel {
  id: panel

  property var service: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string scope: service ? service.scope : "fault"
  readonly property var scopes: scope === "player" ? ["mini", "player"] : [scope]
  readonly property var track: service ? service.track : null
  readonly property bool playing: service ? service.playing : false

  // Refreshed by the ticker below; only moves while the popup is open and playing.
  property real nowMs: Date.now()
  readonly property real positionMs: service && service.player && track
    ? Position.at(service.player.position, nowMs, track.duration_ms) : 0

  readonly property string message: {
    if (!service) return "The Sporetify service is not loaded"
    if (service.lastError !== "") return service.lastError
    switch (service.phase) {
    case "signed_out": return "Sign in to Spotify to start listening"
    case "offline": return "Can't reach Spotify. Retrying…"
    case "no_premium": return "Spotify Premium is required to play"
    case "unavailable": return "The Sporetify daemon is not reachable"
    case "incompatible": return "Daemon and plugin versions differ. Rebuild the daemon"
    case "starting": return "Starting…"
    }
    return ""
  }
  readonly property bool messageIsError: service && (service.lastError !== "" || scope === "fault")

  focusTarget: keys
  contentWidth: panel.fittedContentWidth(Style.space(340))
  contentHeight: panel.fittedContentHeight(column.implicitHeight)

  function act(action) {
    if (action === "close") panel.close()
    else if (action === "openApp") {
      if (service) service.openApp()
      panel.close()
    } else if (service) service.run(action)
  }

  onOpenChanged: if (open) nowMs = Date.now()

  component Cap: KeyCap {
    foreground: panel.fg
    fontFamily: panel.family
    fontSize: Style.font.caption
    padding: Style.spacing.xs
  }

  // A transport button with the key that triggers it underneath.
  component Control: Column {
    id: control
    property string action
    property string icon
    property real iconSize: Style.font.icon
    property bool enabled: true
    spacing: Style.spacing.sm

    // Same slot height for every button, so the keycaps line up under
    // icons of different sizes.
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      implicitWidth: button.implicitWidth
      implicitHeight: Style.spacing.controlHeight + Style.spacing.lg

      Button {
        id: button
        anchors.centerIn: parent
        iconText: control.icon
        iconSize: control.iconSize
        foreground: panel.fg
        enabled: control.enabled
        opacity: enabled ? 1 : Style.normalBorderAlpha
        onClicked: panel.act(control.action)
      }
    }
    Cap {
      anchors.horizontalCenter: parent.horizontalCenter
      label: Keymap.keyLabel(control.action)
    }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Timer {
      interval: 500
      repeat: true
      running: panel.open && panel.playing
      onTriggered: panel.nowMs = Date.now()
    }

    Keys.onPressed: function(event) {
      var action = Keymap.actionFor(event.key, event.text, panel.scopes)
      if (!action) return
      event.accepted = true
      panel.act(action)
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.spacing.xxl

      // ---- What is playing
      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: panel.track ? panel.track.title : "Nothing playing"
          color: panel.fg
          font.family: panel.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: panel.track ? panel.track.artists.join(", ") : ""
          color: Color.muted
          font.family: panel.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ---- Why nothing can happen right now, if so
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: panel.message
        color: panel.messageIsError ? Color.urgent : Color.muted
        font.family: panel.family
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Seek
      Column {
        width: parent.width
        visible: panel.scope === "player" && panel.track !== null
        spacing: Style.spacing.xs

        PanelSlider {
          width: parent.width
          bar: panel.bar
          value: panel.track && panel.track.duration_ms > 0 ? panel.positionMs / panel.track.duration_ms : 0
          // Seeking commits on release so a drag does not re-buffer per frame.
          onReleased: function(value) {
            if (panel.service && panel.track) panel.service.seekTo(value * panel.track.duration_ms)
          }
        }
        Item {
          width: parent.width
          implicitHeight: elapsed.implicitHeight
          Text {
            id: elapsed
            textFormat: Text.PlainText
            text: Position.clock(panel.positionMs)
            color: Color.muted
            font.family: panel.family
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: panel.track ? Position.clock(panel.track.duration_ms) : ""
            color: Color.muted
            font.family: panel.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- Transport
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: panel.scope === "player"
        spacing: Style.spacing.huge

        // nf-md-skip_previous, nf-md-pause / nf-md-play, nf-md-skip_next
        Control { action: "previous"; icon: "󰒮"; enabled: panel.track !== null }
        Control {
          action: "playPause"
          icon: panel.playing ? "󰏤" : "󰐊"
          iconSize: Style.font.iconLarge
        }
        Control { action: "next"; icon: "󰒭"; enabled: panel.track !== null }
      }

      // ---- Volume
      Row {
        width: parent.width
        visible: panel.scope === "player"
        spacing: Style.spacing.lg

        Cap { id: volumeDownCap; anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("volumeDown") }
        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - volumeDownCap.width - volumeUpCap.width - parent.spacing * 2
          bar: panel.bar
          value: panel.service ? panel.service.volume : 0
          onMoved: function(value) { if (panel.service) panel.service.setVolume(value) }
        }
        Cap { id: volumeUpCap; anchors.verticalCenter: parent.verticalCenter; label: Keymap.keyLabel("volumeUp") }
      }

      // ---- The one thing to do when signed out or faulted
      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: panel.scope !== "player"
        text: panel.scope === "signedOut" ? "Sign in to Spotify" : "Retry"
        bordered: true
        foreground: panel.fg
        onClicked: panel.act(panel.scope === "signedOut" ? "signIn" : "retry")
      }

      PanelSeparator { width: parent.width }

      HintBar {
        width: parent.width
        scope: panel.scopes
        foreground: panel.fg
        muted: Color.muted
        fontFamily: panel.family
        fontSize: Style.font.caption
        gap: Style.spacing.xs
      }
    }
  }
}
