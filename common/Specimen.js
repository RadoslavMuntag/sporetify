.pragma library
.import "Organism.js" as Organism

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

// What the creature for `id` is made of: "3 lobes · 2 eyes · 7 hairs".
function traits(id) {
  var shape = Organism.create(id)
  return [count(shape.lobes.length, "lobe"), count(shape.eyes.length, "eye"), count(shape.cilia.length, "hair")].join(" · ")
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
