.pragma library

// Two settings, both in ~/.config/sporetify/app.json:
//
// `visuals`: "full" draws and animates the scenes (lens, spectrum, plate),
// "reduced" draws them still, "off" leaves them out.
// `creatures`: whether any creature is drawn, anywhere: in the app, the
// compact player, the bar and the mini-player. Off, a lens shows the cover.

var levels = ["full", "reduced", "off"]

function level(saved) {
  return levels.indexOf(saved) !== -1 ? saved : "full"
}

function creatures(saved) {
  return saved !== false
}

function next(current) {
  var at = levels.indexOf(current)
  return levels[(at + 1) % levels.length]
}

// Whether anything is drawn, and whether it may move.
function drawn(current) { return current !== "off" }
function moving(current) { return current === "full" }

// The level at `at` (0..1 across the spectrum) of `bands`, read between
// neighbouring bands so a few bands can be drawn as many fine lines.
function sample(bands, at) {
  if (!bands || bands.length === 0) return 0
  if (bands.length === 1) return bands[0]
  var position = Math.max(0, Math.min(1, at)) * (bands.length - 1)
  var low = Math.floor(position)
  var high = Math.min(bands.length - 1, low + 1)
  var t = position - low
  return bands[low] * (1 - t) + bands[high] * t
}
