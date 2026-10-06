import QtQuick
import QtTest

import "../common/Loadable.js" as Loadable

TestCase {
  name: "Loadable"

  function error(code) {
    return { ok: false, error: { code: code, message: "", retry_after_ms: null } }
  }

  function test_loading_keeps_what_was_shown() {
    var first = Loadable.loading(null)
    compare(first.state, "loading")
    verify(!Loadable.hasData(first))

    var again = Loadable.loading(Loadable.ready([1, 2]))
    compare(again.state, "loading")
    compare(again.data.length, 2)
  }

  function test_frame_then_result() {
    var value = Loadable.loading(null)
    value = Loadable.withFrame(value, { rows: 1 })
    compare(value.state, "stale")
    compare(value.data.rows, 1)

    value = Loadable.withResult(value, { ok: true, data: { rows: 2 }, unchanged: false })
    compare(value.state, "ready")
    compare(value.data.rows, 2)
  }

  function test_unchanged_result_promotes_stale_data() {
    var value = Loadable.stale({ rows: 1 })
    value = Loadable.withResult(value, { ok: true, unchanged: true })
    compare(value.state, "ready")
    compare(value.data.rows, 1)
  }

  function test_error_keeps_last_good_data() {
    var value = Loadable.withResult(Loadable.stale({ rows: 1 }), error("timeout"))
    compare(value.state, "error")
    compare(value.data.rows, 1)
    compare(value.error.code, "timeout")
  }

  function test_cancelled_changes_nothing() {
    var before = Loadable.stale({ rows: 1 })
    var after = Loadable.withResult(before, error("cancelled"))
    compare(after, before)
  }

  function test_retry_is_offered_only_where_it_can_help() {
    verify(Loadable.canRetry(Loadable.failed({ code: "timeout" }, null)))
    verify(Loadable.canRetry(Loadable.failed({ code: "offline" }, null)))
    verify(!Loadable.canRetry(Loadable.failed({ code: "not_found" }, null)))
    verify(!Loadable.canRetry(Loadable.failed({ code: "unauthorized" }, null)))
    verify(!Loadable.canRetry(Loadable.ready(1)))
  }
}
