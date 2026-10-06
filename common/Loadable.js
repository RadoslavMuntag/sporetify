.pragma library

// The only loading-state type views bind to. A value is always in exactly one
// of four states, and three of them are exits from "loading":
//
//   loading  nothing to show yet (data may still hold what was shown before)
//   stale    cached data shown while a fresh answer is on its way
//   ready    fresh data
//   error    the request ended without fresh data; `data` keeps the last
//            good value so the view never goes blank, `error` says why
//
// There is deliberately no "idle" or open-ended state: every request has a
// deadline, so `loading` and `stale` always resolve.

function loading(previous) {
  return { state: "loading", data: previous ? previous.data : undefined, error: null }
}

function stale(data) {
  return { state: "stale", data: data, error: null }
}

function ready(data) {
  return { state: "ready", data: data, error: null }
}

function failed(error, previous) {
  return { state: "error", data: previous ? previous.data : undefined, error: error }
}

// Fold an early frame from DaemonClient into the current value.
function withFrame(previous, data) {
  return stale(data)
}

// Fold a request's final result into the current value.
function withResult(previous, result) {
  if (result.ok) {
    // `unchanged` confirms the stale data already shown is current.
    if (result.unchanged && previous && previous.data !== undefined) return ready(previous.data)
    return ready(result.data)
  }
  // A cancelled request was superseded or abandoned; it changes nothing.
  if (result.error.code === "cancelled") return previous
  return failed(result.error, previous)
}

function hasData(value) {
  return !!value && value.data !== undefined
}

// A retry is worth offering for anything that could succeed on a second try.
function canRetry(value) {
  if (!value || value.state !== "error") return false
  var code = value.error.code
  return code === "timeout" || code === "offline" || code === "rate_limited" || code === "internal"
}
