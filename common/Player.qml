import QtQuick
import Quickshell
import Quickshell.Io

import "Position.js" as Position

// A frontend's view of the daemon: connection, player state, and the actions
// every surface runs. Shared by the shell plugin and the full app.
//
// Actions change what is shown first and talk to the daemon second; a
// refusal rolls the change back and leaves the reason in `lastError`.
Item {
  id: root

  // Raised by the host while a surface that shows daemon state is open.
  property bool wanted: false

  // One word describing what the user can expect right now:
  // asleep | starting | ready | signed_out | offline | no_premium |
  // unavailable | incompatible
  readonly property string phase: {
    switch (client.link) {
    case "asleep": return "asleep"
    case "connecting": return "starting"
    case "down": return "unavailable"
    case "incompatible": return "incompatible"
    default: return client.status !== "" ? client.status : "starting"
    }
  }
  // Which set of shortcuts applies; see common/Keymap.js.
  // Offline is not a fault: the saved library can still be browsed.
  readonly property string scope: phase === "signed_out" ? "signedOut"
    : (phase === "unavailable" || phase === "incompatible" || phase === "no_premium") ? "fault"
    : "player"
  readonly property bool offline: phase === "offline"

  readonly property var player: client.player
  readonly property var track: player && player.track ? player.track : null

  // What the user just asked for, shown until the daemon answers.
  property var playingIntent: undefined
  property var volumeIntent: undefined
  readonly property bool playing: playingIntent !== undefined ? playingIntent : !!(player && player.playing)
  readonly property real volume: volumeIntent !== undefined ? volumeIntent : (player ? player.volume : 0.5)

  readonly property real volumeStep: 0.05
  readonly property int seekStepMs: 10000
  property real volumeBeforeMute: 0.5
  // Why the last action failed; "" when it did not.
  property string lastError: ""

  // A request on the shared connection; see ClientCore.request.
  function request(op, args, opts) {
    return client.request(op, args, opts)
  }

  function send(op, args, settled) {
    lastError = ""
    client.request(op, args || {}, {
      deadline: 5000,
      onDone: function(result) {
        if (!result.ok && result.error.code !== "cancelled") root.lastError = result.error.message
        if (settled) settled(result)
      }
    })
  }

  function positionMs() {
    return player && track ? Position.at(player.position, Date.now(), track.duration_ms) : 0
  }

  function setPlaying(want) {
    playingIntent = want
    send(want ? "player.play" : "player.pause", {}, function() { root.playingIntent = undefined })
  }

  // The first value goes out at once; a drag then sends at most one value
  // per flush interval, and always the last one.
  function setVolume(value) {
    volumeIntent = Math.max(0, Math.min(1, value))
    if (volumeFlush.running) {
      volumeFlush.dirty = true
      return
    }
    sendVolume()
    volumeFlush.restart()
  }

  function sendVolume() {
    send("player.volume", { value: volumeIntent })
    volumeSettle.restart()
  }

  function seekTo(ms) {
    if (track) send("player.seek", { position_ms: Math.max(0, Math.min(track.duration_ms, Math.round(ms))) })
  }

  // Run a Keymap action. Returns false for actions a surface must handle itself.
  function run(action) {
    switch (action) {
    case "playPause":
      if (scope === "signedOut") return run("signIn")
      setPlaying(!playing)
      return true
    case "next": send("player.next"); return true
    case "previous": send("player.previous"); return true
    case "volumeUp": setVolume(volume + volumeStep); return true
    case "volumeDown": setVolume(volume - volumeStep); return true
    case "mute":
      if (volume > 0) {
        volumeBeforeMute = volume
        setVolume(0)
      } else {
        setVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 0.5)
      }
      return true
    case "seekForward": seekTo(positionMs() + seekStepMs); return true
    case "seekBack": seekTo(positionMs() - seekStepMs); return true
    case "shuffle": send("player.shuffle", { on: !(player && player.shuffle) }); return true
    case "repeat": send("player.repeat", { on: !(player && player.repeat) }); return true
    case "signIn": send("auth.begin"); return true
    case "retry": send("auth.retry"); return true
    }
    return false
  }

  // Bring the daemon up and refresh what we know about it. Returns at once.
  function playContext(uri, trackUri) {
    var args = { uri: uri }
    if (trackUri) args.track_uri = trackUri
    playingIntent = true
    send("player.play_context", args, function() { root.playingIntent = undefined })
  }

  function wake() {
    send("player.get")
  }

  DaemonClient {
    id: client
    // Stay connected while there is something to show: an open surface, or
    // music whose track changes the bar should follow.
    active: root.wanted || !!(root.player && root.player.playing)
  }

  Timer {
    id: volumeFlush
    property bool dirty: false
    interval: 80
    repeat: false
    onTriggered: {
      if (!dirty) return
      dirty = false
      root.sendVolume()
      restart()
    }
  }

  // The daemon echoes each volume it applied. During a drag those echoes
  // trail the knob, so the user's value wins until changes have stopped.
  Timer {
    id: volumeSettle
    interval: 400
    repeat: false
    onTriggered: root.volumeIntent = undefined
  }
}
