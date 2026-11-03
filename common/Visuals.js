.pragma library

// The visuals setting: "full" draws and animates the creatures and scenes,
// "reduced" draws them still, "off" leaves them out. Older preference files
// only have `creatures` (true or false), which still counts.

var levels = ["full", "reduced", "off"]

function level(saved, creatures) {
  if (levels.indexOf(saved) !== -1) return saved
  return creatures === false ? "off" : "full"
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
