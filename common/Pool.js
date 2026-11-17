.pragma library

// Which organism swims in which slot of the pool (D18). A slot keeps its
// organism while it is wanted, so on a track change the old one shrinks
// back where it is and the new one grows: nothing jumps. A slot whose
// organism is no longer wanted keeps it (shrinking away) until the slot is
// needed for a newcomer; empty slots are used first.
//
// `slots`: the seeds in each slot now ("" for empty). `wanted`: the seeds
// to show, the playing one first. Returns the new slots, same length.
function assign(slots, wanted, count) {
  var out = []
  for (var i = 0; i < count; i++) out.push(slots && i < slots.length ? slots[i] : "")
  var want = []
  for (var w = 0; w < wanted.length && want.length < count; w++)
    if (wanted[w] && want.indexOf(wanted[w]) === -1) want.push(wanted[w])
  var placed = {}
  for (var s = 0; s < count; s++) if (out[s] !== "" && want.indexOf(out[s]) !== -1) placed[out[s]] = true
  for (var n = 0; n < want.length; n++) {
    var seed = want[n]
    if (placed[seed]) continue
    var free = out.indexOf("")
    if (free === -1) {
      for (var k = 0; k < count; k++) if (want.indexOf(out[k]) === -1) { free = k; break }
    }
    if (free === -1) break
    out[free] = seed
    placed[seed] = true
  }
  return out
}

// What the organism in a slot is doing: "main" (playing), "queue" or
// "gone" (shrinking away, or empty).
function role(seed, wanted) {
  if (!seed) return "gone"
  var at = wanted.indexOf(seed)
  return at === 0 ? "main" : at > 0 ? "queue" : "gone"
}
