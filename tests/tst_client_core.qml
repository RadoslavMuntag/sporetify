import QtQuick
import QtTest

import "../common/ClientCore.js" as ClientCore

TestCase {
  name: "ClientCore"

  // A core wired to a fake socket and a clock the test controls.
  function harness() {
    var h = { sent: [], time: 1000, events: [], hellos: 0, incompatibles: 0, counts: [] }
    h.core = ClientCore.create({
      send: function(line) { h.sent.push(JSON.parse(line)) },
      now: function() { return h.time },
      onHello: function() { h.hellos++ },
      onIncompatible: function() { h.incompatibles++ },
      onEvent: function(name, frame) { h.events.push(name) },
      onPendingChanged: function(count) { h.counts.push(count) }
    })
    h.hello = function() {
      h.core.feed(JSON.stringify({ ev: "hello", protocol: ClientCore.PROTOCOL, status: "ready", player: {} }))
    }
    h.reply = function(frame) { h.core.feed(JSON.stringify(frame)) }
    return h
  }

  // Collects what a request reported, to assert it ended exactly once.
  function recorder() {
    var r = { frames: [], results: [] }
    r.onFrame = function(data, meta) { r.frames.push({ data: data, stale: meta.stale }) }
    r.onDone = function(result) { r.results.push(result) }
    return r
  }

  function test_request_without_deadline_throws() {
    var h = harness()
    var threw = false
    try { h.core.request("player.get", {}, {}) } catch (e) { threw = true }
    verify(threw)
    compare(h.core.pendingCount(), 0)
  }

  function test_request_is_sent_once_ready() {
    var h = harness()
    h.hello()
    var r = recorder()
    h.core.request("player.get", { a: 1 }, { deadline: 500, onDone: r.onDone })
    compare(h.sent.length, 1)
    compare(h.sent[0].op, "player.get")
    compare(h.sent[0].args.a, 1)
    compare(h.sent[0].deadline_ms, 500)

    h.reply({ id: h.sent[0].id, ok: true, stale: false, final: true, data: { x: 2 } })
    compare(r.results.length, 1)
    verify(r.results[0].ok)
    compare(r.results[0].data.x, 2)
    compare(h.core.pendingCount(), 0)
  }

  function test_request_before_hello_waits_and_sends_remaining_deadline() {
    var h = harness()
    var r = recorder()
    h.core.request("player.get", {}, { deadline: 1000, onDone: r.onDone })
    compare(h.sent.length, 0)

    h.time += 400
    h.hello()
    compare(h.sent.length, 1)
    compare(h.sent[0].deadline_ms, 600)
    compare(r.results.length, 0)
  }

  function test_unsent_request_ends_offline_at_its_deadline() {
    var h = harness()
    var r = recorder()
    h.core.request("player.get", {}, { deadline: 1000, onDone: r.onDone })
    compare(h.core.nextExpiry(), 2000)

    h.time = 1999
    h.core.expire()
    compare(r.results.length, 0)

    h.time = 2000
    h.core.expire()
    compare(r.results.length, 1)
    compare(r.results[0].error.code, "offline")
    compare(h.core.nextExpiry(), -1)
  }

  function test_sent_request_times_out_after_grace_and_cancels_remotely() {
    var h = harness()
    h.hello()
    var r = recorder()
    h.core.request("search", {}, { deadline: 1000, onDone: r.onDone })
    compare(h.core.nextExpiry(), 2000 + ClientCore.GRACE_MS)

    h.time = 2000
    h.core.expire()
    compare(r.results.length, 0, "the daemon gets a grace period to answer first")

    h.time = 2000 + ClientCore.GRACE_MS
    h.core.expire()
    compare(r.results.length, 1)
    compare(r.results[0].error.code, "timeout")
    compare(h.sent[h.sent.length - 1].op, "cancel")
    compare(h.sent[h.sent.length - 1].target, h.sent[0].id)
  }

  function test_stale_frame_then_final_frame() {
    var h = harness()
    h.hello()
    var r = recorder()
    h.core.request("library.playlist", {}, { deadline: 1000, onFrame: r.onFrame, onDone: r.onDone })
    var id = h.sent[0].id

    h.reply({ id: id, ok: true, stale: true, final: false, data: { rows: 1 } })
    compare(r.frames.length, 1)
    verify(r.frames[0].stale)
    compare(r.results.length, 0)
    compare(h.core.pendingCount(), 1)

    h.reply({ id: id, ok: true, stale: false, final: true, unchanged: true })
    compare(r.results.length, 1)
    verify(r.results[0].unchanged)
  }

  function test_error_frame_is_final() {
    var h = harness()
    h.hello()
    var r = recorder()
    h.core.request("search", {}, { deadline: 1000, onDone: r.onDone })
    h.reply({ id: h.sent[0].id, ok: false, final: true,
      error: { code: "rate_limited", message: "slow down", retry_after_ms: 3000 } })
    compare(r.results.length, 1)
    verify(!r.results[0].ok)
    compare(r.results[0].error.code, "rate_limited")
    compare(r.results[0].error.retry_after_ms, 3000)
  }

  function test_late_frames_are_dropped_not_delivered() {
    var h = harness()
    h.hello()
    var r = recorder()
    var handle = h.core.request("search", {}, { deadline: 1000, onFrame: r.onFrame, onDone: r.onDone })
    handle.cancel()
    compare(r.results.length, 1)
    compare(r.results[0].error.code, "cancelled")

    h.reply({ id: handle.id, ok: true, stale: false, final: true, data: { late: true } })
    compare(r.results.length, 1, "a request ends exactly once")
    compare(r.frames.length, 0)
    compare(h.core.droppedFrames(), 1)
  }

  function test_cancel_tells_the_daemon_only_if_it_was_sent() {
    var h = harness()
    var unsent = h.core.request("search", {}, { deadline: 1000 })
    unsent.cancel()
    compare(h.sent.length, 0)

    h.hello()
    var sent = h.core.request("search", {}, { deadline: 1000 })
    sent.cancel()
    compare(h.sent.length, 2)
    compare(h.sent[1].op, "cancel")
    compare(h.sent[1].target, sent.id)
  }

  function test_new_request_in_a_scope_supersedes_the_previous() {
    var h = harness()
    h.hello()
    var first = recorder()
    var second = recorder()
    h.core.request("search", { q: "a" }, { deadline: 1000, scope: "search", onDone: first.onDone })
    h.core.request("search", { q: "ab" }, { deadline: 1000, scope: "search", onDone: second.onDone })

    compare(first.results.length, 1)
    compare(first.results[0].error.code, "cancelled")
    compare(second.results.length, 0)
    compare(h.core.pendingCount(), 1)

    // The answer to the superseded request must never surface.
    h.reply({ id: h.sent[0].id, ok: true, stale: false, final: true, data: { q: "a" } })
    compare(first.results.length, 1)
    compare(second.results.length, 0)
  }

  function test_requests_in_different_scopes_do_not_interfere() {
    var h = harness()
    h.hello()
    h.core.request("search", {}, { deadline: 1000, scope: "search" })
    h.core.request("library.playlists", {}, { deadline: 1000, scope: "library" })
    h.core.request("player.get", {}, { deadline: 1000 })
    compare(h.core.pendingCount(), 3)
  }

  function test_connection_loss_fails_sent_requests_and_keeps_unsent_ones() {
    var h = harness()
    h.hello()
    var sent = recorder()
    h.core.request("search", {}, { deadline: 5000, onDone: sent.onDone })
    h.core.connectionLost()
    compare(sent.results.length, 1)
    compare(sent.results[0].error.code, "offline")
    verify(!h.core.isReady())

    var waiting = recorder()
    h.core.request("player.get", {}, { deadline: 5000, onDone: waiting.onDone })
    compare(waiting.results.length, 0)
    var before = h.sent.length
    h.hello()
    compare(h.sent.length, before + 1, "queued requests go out on reconnect")
  }

  function test_incompatible_daemon_fails_everything_and_sends_nothing() {
    var h = harness()
    var r = recorder()
    h.core.request("player.get", {}, { deadline: 1000, onDone: r.onDone })
    h.core.feed(JSON.stringify({ ev: "hello", protocol: ClientCore.PROTOCOL + 1 }))

    compare(h.incompatibles, 1)
    compare(h.hellos, 0)
    verify(h.core.isIncompatible())
    compare(r.results.length, 1)
    compare(r.results[0].error.code, "internal")

    var later = recorder()
    h.core.request("player.get", {}, { deadline: 1000, onDone: later.onDone })
    compare(later.results.length, 1)
    compare(h.sent.length, 0)
  }

  function test_events_are_forwarded() {
    var h = harness()
    h.hello()
    h.reply({ ev: "status", status: "offline" })
    compare(h.events.length, 1)
    compare(h.events[0], "status")
  }

  function test_garbage_lines_are_ignored() {
    var h = harness()
    h.hello()
    h.core.feed("{not json")
    h.core.feed("42")
    h.core.feed("")
    compare(h.core.droppedFrames(), 2)
    verify(h.core.isReady())
  }

  function test_pending_count_is_reported() {
    var h = harness()
    h.hello()
    var handle = h.core.request("search", {}, { deadline: 1000 })
    handle.cancel()
    compare(h.counts.length, 2)
    compare(h.counts[0], 1)
    compare(h.counts[1], 0)
  }
}
