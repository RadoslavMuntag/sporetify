.pragma library

// Playback position is sent as a point in time ({ position_ms, at_ms, rate })
// so the UI can show a moving clock without asking the daemon again.

function at(position, nowMs, durationMs) {
  if (!position) return 0
  var value = position.position_ms + Math.max(0, nowMs - position.at_ms) * position.rate
  if (durationMs > 0) value = Math.min(value, durationMs)
  return Math.max(0, value)
}

// 83000 -> "1:23"
function clock(ms) {
  var seconds = Math.max(0, Math.floor(ms / 1000))
  var rest = seconds % 60
  return Math.floor(seconds / 60) + ":" + (rest < 10 ? "0" : "") + rest
}
