.pragma library

// Protocol state machine for the daemon socket, free of any I/O so it can be
// unit tested. The host (DaemonClient.qml) owns the socket and the timer and
// feeds this core; the core guarantees every request ends exactly once.
//
// Contract: .claude/architecture/03-protocol.md

var PROTOCOL = 0

// A sent request waits this long past its deadline for the daemon's own
// terminal frame before the client gives up on it locally.
var GRACE_MS = 200

// io: {
//   send(line)        write one line to the socket (no terminator)
//   now()             current time in ms
//   onHello(frame)    optional, compatible daemon said hello
//   onIncompatible(frame)  optional, daemon speaks another protocol
//   onEvent(name, frame)   optional, any other unsolicited frame
//   onPendingChanged(count)  optional
// }
function create(io) {
  var nextId = 1
  var pending = {}   // id -> entry
  var count = 0
  var scopes = {}    // scope name -> id of its current request
  var ready = false  // connected and a compatible hello was read
  var incompatible = false
  var dropped = 0    // frames that arrived for ids no longer alive

  function notifyCount() {
    if (io.onPendingChanged) io.onPendingChanged(count)
  }

  function failure(code, message) {
    return { ok: false, error: { code: code, message: message, retry_after_ms: null } }
  }

  function finish(entry, result) {
    if (!pending[entry.id]) return
    delete pending[entry.id]
    count--
    if (entry.scope && scopes[entry.scope] === entry.id) delete scopes[entry.scope]
    notifyCount()
    if (entry.onDone) entry.onDone(result)
  }

  function transmit(entry, now) {
    var remaining = entry.expiresAt - now
    if (remaining <= 0) return
    entry.sent = true
    io.send(JSON.stringify({
      id: entry.id, op: entry.op, args: entry.args, deadline_ms: Math.ceil(remaining)
    }))
  }

  function cancel(id) {
    var entry = pending[id]
    if (!entry) return
    if (entry.sent && ready) io.send(JSON.stringify({ op: "cancel", target: id }))
    finish(entry, failure("cancelled", "cancelled"))
  }

  // opts: { deadline: ms (required), scope: string, onFrame(data, meta), onDone(result) }
  // onFrame receives early (stale) data; onDone is called exactly once with
  // { ok: true, data, unchanged } or { ok: false, error: { code, message, retry_after_ms } }.
  function request(op, args, opts) {
    if (!opts || !(opts.deadline > 0))
      throw new Error("request('" + op + "') needs a deadline")

    var now = io.now()
    var entry = {
      id: nextId++,
      op: op,
      args: args || {},
      expiresAt: now + opts.deadline,
      scope: opts.scope || "",
      onFrame: opts.onFrame || null,
      onDone: opts.onDone || null,
      sent: false
    }

    // A newer request in a scope supersedes the one before it.
    if (entry.scope) {
      if (scopes[entry.scope] !== undefined) cancel(scopes[entry.scope])
      scopes[entry.scope] = entry.id
    }

    pending[entry.id] = entry
    count++
    notifyCount()

    if (incompatible) finish(entry, failure("internal", "the daemon and this app are different versions"))
    else if (ready) transmit(entry, now)
    // Otherwise it waits: sent on hello, or ended `offline` at its deadline.

    var id = entry.id
    return { id: id, cancel: function() { cancel(id) } }
  }

  function handleHello(frame) {
    if (frame.protocol !== PROTOCOL) {
      incompatible = true
      ready = false
      var ids = Object.keys(pending)
      for (var i = 0; i < ids.length; i++) {
        if (pending[ids[i]])
          finish(pending[ids[i]], failure("internal", "the daemon and this app are different versions"))
      }
      if (io.onIncompatible) io.onIncompatible(frame)
      return
    }
    incompatible = false
    ready = true
    if (io.onHello) io.onHello(frame)
    var now = io.now()
    var waiting = Object.keys(pending)
    for (var j = 0; j < waiting.length; j++) {
      var entry = pending[waiting[j]]
      if (entry && !entry.sent) transmit(entry, now)
    }
  }

  // One line read from the socket.
  function feed(line) {
    if (!line) return
    var frame
    try {
      frame = JSON.parse(line)
    } catch (e) {
      dropped++
      return
    }
    if (frame === null || typeof frame !== "object") { dropped++; return }

    if (frame.ev !== undefined) {
      if (frame.ev === "hello") handleHello(frame)
      else if (io.onEvent) io.onEvent(String(frame.ev), frame)
      return
    }

    var entry = pending[frame.id]
    // Late frames for finished, cancelled or superseded requests are never rendered.
    if (!entry) { dropped++; return }

    if (frame.ok === false) {
      var error = frame.error || {}
      finish(entry, {
        ok: false,
        error: {
          code: error.code || "internal",
          message: error.message || "",
          retry_after_ms: error.retry_after_ms === undefined ? null : error.retry_after_ms
        }
      })
    } else if (frame.final === false) {
      if (entry.onFrame) entry.onFrame(frame.data, { stale: frame.stale === true })
    } else {
      finish(entry, { ok: true, data: frame.data, unchanged: frame.unchanged === true })
    }
  }

  // The socket dropped. What was sent on it is gone, so it fails now rather
  // than at its deadline; what was still waiting keeps waiting for a reconnect.
  function connectionLost() {
    ready = false
    incompatible = false
    var ids = Object.keys(pending)
    for (var i = 0; i < ids.length; i++) {
      var entry = pending[ids[i]]
      if (entry && entry.sent) finish(entry, failure("offline", "lost the connection to the daemon"))
    }
  }

  // End everything whose time is up. Call when the deadline timer fires.
  function expire() {
    var now = io.now()
    var ids = Object.keys(pending)
    for (var i = 0; i < ids.length; i++) {
      var entry = pending[ids[i]]
      if (!entry) continue
      if (!entry.sent) {
        if (entry.expiresAt <= now) finish(entry, failure("offline", "the daemon is not reachable"))
      } else if (entry.expiresAt + GRACE_MS <= now) {
        if (ready) io.send(JSON.stringify({ op: "cancel", target: entry.id }))
        finish(entry, failure("timeout", "the daemon did not answer in time"))
      }
    }
  }

  // When expire() next has work, in ms since epoch, or -1 with nothing pending.
  function nextExpiry() {
    var soonest = -1
    for (var id in pending) {
      var entry = pending[id]
      var at = entry.sent ? entry.expiresAt + GRACE_MS : entry.expiresAt
      if (soonest < 0 || at < soonest) soonest = at
    }
    return soonest
  }

  return {
    request: request,
    feed: feed,
    connectionLost: connectionLost,
    expire: expire,
    nextExpiry: nextExpiry,
    pendingCount: function() { return count },
    isReady: function() { return ready },
    isIncompatible: function() { return incompatible },
    droppedFrames: function() { return dropped }
  }
}
