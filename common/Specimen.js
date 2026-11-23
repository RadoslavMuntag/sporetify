.pragma library
.import "Organism.js" as Organism
.import "Plankton.js" as Plankton

// The Field Guide's view of a track: every track is a specimen with a
// catalogue number and a few traits read off its creature, studied under a
// lens. Pure functions only, so they can be tested without a UI.

// Catalogue number: the first four hex digits of the id's hash. "" for none.
function catalogue(id) {
  if (!id) return ""
  var text = Organism.hash(String(id)).toString(16).toUpperCase()
  while (text.length < 8) text = "0" + text
  return text.slice(0, 4)
}

function count(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

// What the organism for `id` is, in a line: "medusa · 16 tentacles · 8 canals".
function traits(id) {
  var P = Plankton.create(id)
  return Plankton.table(P)[0].value + " · " + Plankton.traits(P)
}

// The same as table rows, [{ name, value }], the kind first.
function table(id) {
  return Plankton.table(Plankton.create(id))
}

// Graph-paper lines across a circle of radius 1, `steps` to a radius:
// [{ offset, half }], where a line sits `offset` from the centre and runs
// `half` either way, so it ends on the rim without clipping.
function chords(steps) {
  var out = []
  for (var i = 1 - steps; i < steps; i++) {
    var offset = i / steps
    out.push({ offset: offset, half: Math.sqrt(1 - offset * offset) })
  }
  return out
}

// How many of `total` ticks are lit at `progress` (0..1).
function lit(progress, total) {
  if (!(progress > 0)) return 0
  return Math.min(total, Math.floor(progress * total + 1e-9))
}

// How a compact surface arranges itself: "side" puts the lens beside the
// text (a wide window), "stack" puts it above (square or tall).
function arrangement(width, height) {
  return width >= height * 1.5 ? "side" : "stack"
}

// How loud the low end of a music frame is, 0..1: the mean of the lowest
// quarter of the bands. 0 when there is no frame.
function low(bands) {
  if (!bands || bands.length === 0) return 0
  var n = Math.max(1, Math.floor(bands.length / 4))
  var sum = 0
  for (var i = 0; i < n; i++) sum += Math.max(0, Math.min(1, bands[i] || 0))
  return sum / n
}

// A progress bar in characters, as the Living ASCII cards draw it: `done`
// is "=" up to the playing position followed by "●", `rest` is "-" for the
// remainder, `cells` characters in all.
function bar(progress, cells) {
  var n = Math.max(2, Math.floor(cells))
  var p = Math.max(0, Math.min(1, progress || 0))
  var on = Math.round(p * (n - 1))
  return { done: new Array(on + 1).join("=") + "●", rest: new Array(n - on).join("-") }
}
