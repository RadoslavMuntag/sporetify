import QtQuick
import Quickshell
import Quickshell.Io

import "ClientCore.js" as ClientCore

// Connection to sporetifyd. Owns the socket and its one-shot timers; all
// protocol logic lives in ClientCore.js.
//
// The connection is held only while something wants it (`active`, a request
// in flight, or a short linger after the last one), so an unused frontend
// lets the daemon reach its idle exit.
Item {
  id: root

  // Set by the host while a surface that shows daemon state is open.
  property bool active: false
  property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sporetify.sock"

  // asleep | connecting | up | down | incompatible
  property string link: "asleep"
  // Daemon status from hello and status events; "" until first contact.
  property string status: ""
  property var player: null
  property string daemonVersion: ""

  // Any unsolicited frame other than hello.
  signal event(string name, var frame)

  property int pendingCount: 0
  property bool lingering: false
  readonly property bool wanted: active || pendingCount > 0 || lingering

  property var core: null
  property var socket: null
  property int backoffMs: 250
  readonly property int lingerMs: 10000
  readonly property int helloTimeoutMs: 2000
  readonly property int maxBackoffMs: 30000

  visible: false

  // See ClientCore.request. Always resolves through opts.onDone, connected or not.
  function request(op, args, opts) {
    var handle = core.request(op, args, opts)
    armDeadline()
    return handle
  }

  function armDeadline() {
    var at = core.nextExpiry()
    if (at < 0) {
      deadlineTimer.stop()
      return
    }
    deadlineTimer.interval = Math.max(1, at - Date.now())
    deadlineTimer.restart()
  }

  function connectNow() {
    retryTimer.stop()
    if (socket) return
    link = "connecting"
    // A Quickshell Socket does not reconnect after a failed attempt, so
    // every attempt gets a fresh one.
    socket = socketComponent.createObject(root, { path: socketPath })
    socket.connected = true
  }

  function dropSocket() {
    helloTimer.stop()
    if (!socket) return
    var old = socket
    socket = null
    old.destroy()
  }

  // The current socket failed to connect, was closed by the daemon, or
  // stayed silent past the hello timeout.
  function handleDown() {
    dropSocket()
    core.connectionLost()
    armDeadline()
    if (!wanted) {
      link = "asleep"
      return
    }
    link = "down"
    retryTimer.interval = backoffMs
    retryTimer.restart()
    backoffMs = Math.min(maxBackoffMs, backoffMs * 2)
  }

  onWantedChanged: {
    // Initial bindings resolve before the core exists; onCompleted connects then.
    if (!core) return
    if (wanted) {
      backoffMs = 250
      connectNow()
    } else {
      retryTimer.stop()
      dropSocket()
      core.connectionLost()
      armDeadline()
      link = "asleep"
    }
  }

  onPendingCountChanged: {
    if (pendingCount === 0) {
      lingering = true
      lingerTimer.restart()
    }
  }

  Component.onCompleted: {
    core = ClientCore.create({
      send: function(line) {
        if (!root.socket) return
        root.socket.write(line + "\n")
        root.socket.flush()
      },
      now: function() { return Date.now() },
      onHello: function(frame) {
        helloTimer.stop()
        root.backoffMs = 250
        root.daemonVersion = frame.daemon || ""
        root.status = frame.status || ""
        root.player = frame.player || null
        root.link = "up"
      },
      onIncompatible: function(frame) {
        helloTimer.stop()
        root.daemonVersion = frame.daemon || ""
        root.link = "incompatible"
      },
      onEvent: function(name, frame) {
        if (name === "status") root.status = frame.status || ""
        else if (name === "player") root.player = frame.player || null
        root.event(name, frame)
      },
      onPendingChanged: function(count) { root.pendingCount = count }
    })
    if (wanted) connectNow()
  }

  Component.onDestruction: dropSocket()

  Component {
    id: socketComponent

    Socket {
      id: self

      // Signals from a socket that has already been replaced are ignored.
      readonly property bool current: root.socket === self

      parser: SplitParser {
        onRead: function(line) {
          if (!self.current) return
          root.core.feed(line)
          root.armDeadline()
        }
      }
      onConnectionStateChanged: {
        if (!self.current) return
        // A successful connect stays "connecting" until hello arrives.
        if (self.connected) helloTimer.restart()
        else root.handleDown()
      }
      onError: function(error) {
        if (self.current && !self.connected) root.handleDown()
      }
    }
  }

  Timer {
    id: deadlineTimer
    repeat: false
    onTriggered: {
      root.core.expire()
      root.armDeadline()
    }
  }

  // A daemon that accepts but never says hello is treated as down.
  Timer {
    id: helloTimer
    interval: root.helloTimeoutMs
    repeat: false
    onTriggered: if (root.link === "connecting") root.handleDown()
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: if (root.wanted) root.connectNow()
  }

  Timer {
    id: lingerTimer
    interval: root.lingerMs
    repeat: false
    onTriggered: root.lingering = false
  }
}
