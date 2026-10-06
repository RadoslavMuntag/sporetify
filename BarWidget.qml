import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

import "common"

// Bar entry: an icon and, while something is loaded, the track title.
//   left click    open the mini-player
//   right click   play / pause
//   middle click  open the full app
//   wheel         volume
BarWidget {
  id: root

  moduleName: "namelessnovice.sporetify"

  readonly property var service: bar && bar.shell
    ? bar.shell.serviceFor("namelessnovice.sporetify") : null
  readonly property string phase: service ? service.phase : "unavailable"
  readonly property var track: service ? service.track : null
  readonly property bool playing: service ? service.playing : false

  // Needs the user's attention, as opposed to merely not running.
  readonly property bool faulted: phase === "unavailable" || phase === "incompatible"
  readonly property bool dormant: !playing

  readonly property bool showTitle: String(setting("showTrackTitle", "On")) !== "Off"
  readonly property int maxTitleWidth: Style.space(Number(setting("maxTitleWidth", 220)))
  readonly property bool titleVisible: showTitle && !vertical && track !== null

  // Each track's creature replaces the plain icon when this is on.
  readonly property bool creatures: String(setting("creatures", "On")) !== "Off"
  readonly property color ink: bar ? bar.barForeground : Color.foreground
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  // The shell exposes few colours, so the creature palette is mixed from them.
  readonly property var creatureColors: [
    Color.accent, mix(Color.accent, ink, 0.35), mix(Color.accent, Color.urgent, 0.5),
    Color.urgent, mix(Color.urgent, ink, 0.3)
  ]

  readonly property string stateText: {
    switch (phase) {
    case "asleep": return track ? "Paused" : "Asleep"
    case "starting": return "Starting…"
    case "ready": return track ? (playing ? "Playing" : "Paused") : "Ready · nothing loaded"
    case "signed_out": return "Not signed in · click to sign in"
    case "offline": return "Offline"
    case "no_premium": return "Spotify Premium is required to play"
    case "incompatible": return "Daemon and plugin versions differ · rebuild the daemon"
    default: return "Daemon not reachable"
    }
  }
  readonly property string tooltip: {
    var lines = ["Sporetify · " + stateText]
    if (track) lines.push(track.title + " — " + track.artists.join(", "))
    if (service && service.lastError !== "") lines.push(service.lastError)
    return lines.join("\n")
  }

  // ---- Popup contract the bar expects from a widget that owns a panel.
  property bool popupOpen: false
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  // A bar exists per monitor but a global shortcut should open one popup.
  readonly property bool primary: {
    var all = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    return !all || all.length === 0 || all[0] === root
  }

  // The icon and the title beside it answer clicks the same way.
  function clicked(button) {
    if (button === Qt.RightButton) {
      if (service) service.run("playPause")
    } else if (button === Qt.MiddleButton) {
      if (service) service.openApp()
    } else {
      toggle()
    }
  }

  onPopupOpenChanged: if (service) service.surfaceOpen = popupOpen

  Connections {
    target: root.service
    function onToggleMiniRequested() {
      if (root.primary) root.toggle()
    }
  }

  implicitWidth: row.implicitWidth
  implicitHeight: barSize

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      anchors.verticalCenter: parent.verticalCenter
      // nf-md-music
      text: "󰝚"
      iconComponent: root.creatures && root.track !== null ? creatureIcon : null
      active: root.faulted
      opacity: root.dormant ? Style.normalBorderAlpha * 1.5 : 1
      tooltipText: root.tooltip
      onPressed: function(b) {
        if (!root.service) return
        root.clicked(b)
      }
      onWheelMoved: function(delta) {
        if (root.service) root.service.run(delta > 0 ? "volumeUp" : "volumeDown")
      }
    }

    Text {
      id: title
      visible: root.titleVisible
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? Math.min(implicitWidth, root.maxTitleWidth) : 0
      rightPadding: Style.spacing.lg
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.track ? root.track.title : ""
      color: root.bar ? root.bar.barForeground : Color.foreground
      opacity: button.opacity
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          root.clicked(mouse.button)
        }
      }
    }
  }

  Component {
    id: creatureIcon
    Organism {
      seed: root.track ? root.track.id : ""
      // The bar is always on screen, so only a playing track animates.
      alive: root.playing
      awake: root.playing
      palette: root.creatureColors
      eye: root.ink
      pupil: Color.background
    }
  }

  MiniPlayer {
    creatures: root.creatures
    creatureColors: root.creatureColors
    anchorItem: button
    bar: root.bar
    owner: root
    service: root.service
    open: root.popupOpen
  }
}
