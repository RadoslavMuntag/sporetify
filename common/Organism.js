.pragma library

// Every track is an organism. This turns a track id into the small set of
// numbers that describe one, and nothing else: no drawing, no randomness
// beyond the id itself. The same id gives the same creature everywhere.
//
// All lengths are fractions of the creature's bounding box (0..1), with the
// box centred on (0.5, 0.5), so the drawing side can render at any size.

// FNV-1a, 32 bit.
function hash(text) {
  var h = 0x811c9dc5
  for (var i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

// mulberry32: a small, well-mixed generator; returns a function giving 0..1.
function generator(seed) {
  var a = seed >>> 0
  return function() {
    a = (a + 0x6d2b79f5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// The creature for `id`. An empty id gives the same resting creature each time.
//
// {
//   lobes:  [{ x, y, r, period, swell }]   soft circles that form the body
//   core:   { x, y, r }                     the lighter nucleus
//   eyes:   [{ x, y, r }]
//   cilia:  [{ angle, length, width }]      hairs around the body, degrees
//   tone:   0..1   picks the body colour from the host's palette
//   accent: 0..1   picks the detail colour
//   breath: ms     one slow breath of the whole body
//   drift:  0..1   how restless it is
// }
function create(id) {
  var random = generator(hash(String(id || "")))
  function between(low, high) { return low + random() * (high - low) }
  function whole(low, high) { return Math.floor(between(low, high + 1)) }

  var bilateral = random() < 0.7
  var lobes = [{ x: 0.5, y: 0.5, r: between(0.2, 0.26), period: between(2600, 4200), swell: between(0.03, 0.07) }]

  // Around the centre lobe: pairs mirrored left/right, or a ring.
  var extra = whole(1, 3)
  for (var i = 0; i < extra; i++) {
    var angle = bilateral ? between(-70, 70) : (i / extra) * 360 + between(-20, 20)
    var reach = between(0.1, 0.19)
    var radius = between(0.12, 0.19)
    var lobe = function(a) {
      var rad = (a - 90) * Math.PI / 180
      return {
        x: 0.5 + Math.cos(rad) * reach,
        y: 0.5 + Math.sin(rad) * reach,
        r: radius,
        period: between(1800, 3600),
        swell: between(0.04, 0.1)
      }
    }
    if (bilateral) {
      // Mirror across the vertical axis by building the left one from the right.
      var right = lobe(90 + angle)
      lobes.push(right)
      lobes.push({ x: 1 - right.x, y: right.y, r: right.r, period: right.period, swell: right.swell })
    } else {
      lobes.push(lobe(angle))
    }
  }

  var eyeCount = bilateral ? (random() < 0.75 ? 2 : 1) : whole(1, 3)
  var eyeSize = between(0.045, 0.075)
  var eyeHeight = between(0.4, 0.5)
  var eyes = []
  if (eyeCount === 1) {
    eyes.push({ x: 0.5, y: eyeHeight, r: eyeSize * 1.25 })
  } else if (eyeCount === 2) {
    var apart = between(0.07, 0.12)
    eyes.push({ x: 0.5 - apart, y: eyeHeight, r: eyeSize })
    eyes.push({ x: 0.5 + apart, y: eyeHeight, r: eyeSize })
  } else {
    for (var e = 0; e < 3; e++) eyes.push({ x: 0.5 + (e - 1) * 0.1, y: eyeHeight - (e === 1 ? 0.04 : 0), r: eyeSize * 0.85 })
  }

  var cilia = []
  var hairs = random() < 0.8 ? whole(3, 9) : 0
  var hairLength = between(0.08, 0.16)
  var start = between(0, 360)
  for (var c = 0; c < hairs; c++) {
    cilia.push({
      angle: start + (c / hairs) * 360,
      length: hairLength * between(0.8, 1.2),
      width: between(0.018, 0.03)
    })
  }

  return {
    lobes: lobes,
    core: { x: 0.5 + between(-0.03, 0.03), y: 0.5 + between(-0.02, 0.05), r: lobes[0].r * between(0.45, 0.65) },
    eyes: eyes,
    cilia: cilia,
    tone: random(),
    accent: random(),
    breath: between(2800, 4600),
    drift: random()
  }
}

// Pick from a list by a 0..1 value; safe for empty lists.
function pick(list, value) {
  if (!list || list.length === 0) return undefined
  return list[Math.min(list.length - 1, Math.floor(value * list.length))]
}
