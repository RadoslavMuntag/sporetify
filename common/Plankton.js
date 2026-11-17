.pragma library
.import "Organism.js" as Organism

// Every track is a plankton organism (the "organism studies"): a medusa, a
// comb jelly, a radiolarian, a volvox colony or a diatom, grown from the
// track id. Pure data, like Organism.create: the same id gives the same
// organism everywhere. Drawing lives in shaders/plankton.frag, motion in its
// `time` uniform.
//
// Lengths are in units of the organism's radius R. Colours are names from
// the theme's palette (`colourNames`), or "fg" for the theme's foreground.

var kinds = ["medusa", "ctenophore", "radiolarian", "volvox", "diatom"]
var colourNames = ["green", "cyan", "blue", "magenta", "yellow", "orange", "red"]
// R for each kind as a fraction of the space given to it, so they read as
// equally present: a medusa's tentacles reach three R below its bell and a
// radiolarian's threads two and a half R out, a volvox is just a ball.
var size = { medusa: 0.21, ctenophore: 0.19, radiolarian: 0.2, volvox: 0.4, diatom: 0.4 }

function rng(id, salt) {
  var g = Organism.generator(Organism.hash(String(id) + "~" + salt))
  return {
    f: g,
    b: function(l, h) { return l + g() * (h - l) },
    w: function(l, h) { return Math.floor(l + g() * (h - l + 1)) },
    p: function(list) { return list[Math.floor(g() * list.length)] }
  }
}

// Weighted toward medusae and comb jellies, which have the most presence.
function kindOf(id) {
  var v = Organism.generator(Organism.hash(String(id || "") + "~kind"))()
  return v < 0.32 ? "medusa" : v < 0.54 ? "ctenophore" : v < 0.72 ? "radiolarian" : v < 0.86 ? "volvox" : "diatom"
}

var grow = {
  medusa: function(id) {
    var r = rng(id, "medusa")
    return {
      kind: "medusa", bell: r.b(0.5, 0.85), period: r.b(4.2, 6.5), tentacles: r.w(10, 22), tentacleLength: r.b(1.5, 3.1),
      oralArms: r.f() < 0.75 ? 4 : 0, armLength: r.b(0.8, 1.5), canals: r.p([4, 8, 8, 16]), gonads: r.f() < 0.65, tilt: r.b(0.18, 0.3),
      body: r.p(["cyan", "blue", "fg", "magenta", "cyan"]), mark: r.p(["magenta", "orange", "yellow", "red"]), turn: r.f() * 6.283
    }
  },
  ctenophore: function(id) {
    var r = rng(id, "cteno"), round = r.f() < 0.55
    return {
      kind: "ctenophore", form: round ? "cydippid" : "beroid", width: round ? r.b(0.72, 0.9) : r.b(0.48, 0.62), egg: r.b(-0.15, 0.15),
      plates: r.w(14, 22), wave: r.b(0.28, 0.42), tentacleLength: round ? r.b(2.4, 3.8) : 0, body: r.p(["fg", "cyan", "blue"]),
      spin: r.b(0.08, 0.16) * (r.f() < 0.5 ? -1 : 1)
    }
  },
  radiolarian: function(id) {
    var r = rng(id, "radio"), n = r.w(1, 3), shells = [], i
    for (i = 0; i < n; i++) shells.push({ r: n === 1 ? r.b(0.78, 0.95) : 0.45 + i / (n - 1) * r.b(0.42, 0.52), pores: r.w(9, 22), rings: r.w(2, 4) })
    var sp = r.w(6, 20), spines = [], long = r.f() < 0.55, every = Math.max(2, Math.floor(sp / 4))
    for (i = 0; i < sp; i++) spines.push({ a: i / sp * 6.283 + r.b(-0.12, 0.12), length: long && i % every === 0 ? r.b(1.55, 1.9) : r.b(1.12, 1.4) })
    return {
      kind: "radiolarian", shells: shells, spines: spines, axopods: r.w(16, 34), podLength: r.b(1.7, 2.5), capsule: r.b(0.26, 0.36),
      core: r.p(["orange", "yellow", "red", "magenta"]), spin: r.b(0.015, 0.04) * (r.f() < 0.5 ? -1 : 1),
      // Not in the studies' output: what the shader needs to place the spines.
      long: long, every: every
    }
  },
  volvox: function(id) {
    var r = rng(id, "volvox"), d = r.w(2, 7), daughters = []
    for (var i = 0; i < d; i++) {
      var a = r.f() * 6.283, rr = r.b(0.15, 0.5)
      daughters.push({ x: Math.cos(a) * rr, y: Math.sin(a) * rr, z: r.b(-0.35, 0.35), r: r.b(0.14, 0.25), cells: r.w(26, 46), spin: r.b(0.6, 1.6) })
    }
    return { kind: "volvox", cells: r.w(160, 300), daughters: daughters, tilt: r.b(0.3, 1.1), spin: r.b(0.1, 0.18), body: r.p(["green", "green", "cyan", "yellow"]) }
  },
  diatom: function(id) {
    var r = rng(id, "diatom"), pennate = r.f() < 0.7
    var P = {
      kind: "diatom", form: pennate ? "pennate" : "centric", width: r.b(0.17, 0.3), tip: r.b(0.5, 1.1), striae: r.w(16, 32), rings: r.w(3, 6), rays: r.w(24, 48),
      plastid: r.p(["yellow", "orange", "yellow"]), oil: r.w(1, 4), glide: r.b(10, 16), glass: r.p(["fg", "cyan"])
    }
    // Oil droplets, placed as the studies place them.
    var q = rng(id, "plastids")
    P.drops = []
    for (var i = 0; i < P.oil; i++) P.drops.push([q.b(-0.15, 0.15), q.b(-0.6, 0.6)])
    return P
  }
}

// The organism for `id`, of its own kind unless `kind` names one.
function create(id, kind) {
  var k = kinds.indexOf(kind) !== -1 ? kind : kindOf(id)
  return grow[k](String(id || ""))
}

// One line on what it is, for captions: "16 tentacles · 8 canals".
function traits(P) {
  switch (P.kind) {
  case "medusa": return P.tentacles + " tentacles · " + P.canals + " canals" + (P.oralArms ? " · 4 oral arms" : "")
  case "ctenophore": return (P.form === "cydippid" ? "round · 2 tentacles" : "long") + " · 8 comb rows"
  case "radiolarian": return P.shells.length + (P.shells.length > 1 ? " shells · " : " shell · ") + P.spines.length + " spines"
  case "volvox": return P.cells + " cells · " + P.daughters.length + " daughters"
  case "diatom": return P.form === "pennate" ? "pennate · " + P.striae + " striae" : "centric · " + P.rays + " rays"
  }
  return ""
}

// The same, as rows for a table: [{ name, value }], the kind first.
var kindName = { medusa: "medusa", ctenophore: "comb jelly", radiolarian: "radiolarian", volvox: "volvox", diatom: "diatom" }
function table(P) {
  var rows = [{ name: "kind", value: kindName[P.kind] }]
  function row(name, value) { rows.push({ name: name, value: String(value) }) }
  switch (P.kind) {
  case "medusa": row("tentacles", P.tentacles); row("canals", P.canals); row("arms", P.oralArms || "none"); break
  case "ctenophore": row("form", P.form === "cydippid" ? "round" : "long"); row("rows", 8); row("plates", P.plates); break
  case "radiolarian": row("shells", P.shells.length); row("spines", P.spines.length); row("threads", P.axopods); break
  case "volvox": row("cells", P.cells); row("daughters", P.daughters.length); break
  case "diatom":
    row("form", P.form)
    if (P.form === "pennate") row("striae", P.striae); else row("rays", P.rays)
    break
  }
  return rows
}

var kindIndex = { medusa: 0, ctenophore: 1, radiolarian: 2, volvox: 3, diatom: 4 }

function v4(a, b, c, d) { return { x: a || 0, y: b || 0, z: c || 0, w: d || 0 } }

// The organism as the shader's uniforms: a kind number, six vec4s whose
// meaning depends on the kind (listed in shaders/plankton.frag), and the
// names of its two colours. Only the first four volvox daughters and the
// first three radiolarian shells are drawn.
function uniforms(P) {
  var out = { kind: kindIndex[P.kind], p: [], main: "fg", mark: "fg" }
  var p = out.p, i
  switch (P.kind) {
  case "medusa":
    p.push(v4(P.bell, P.period, P.tentacles, P.tentacleLength))
    p.push(v4(P.oralArms, P.armLength, P.canals, P.gonads ? 1 : 0))
    p.push(v4(P.tilt, P.turn, 0, 0))
    out.main = P.body; out.mark = P.mark
    break
  case "ctenophore":
    p.push(v4(P.form === "cydippid" ? 1 : 0, P.width, P.egg, P.plates))
    p.push(v4(P.wave, P.tentacleLength, P.spin, 0))
    out.main = P.body; out.mark = "fg"
    break
  case "radiolarian":
    p.push(v4(P.shells.length, P.axopods, P.podLength, P.capsule))
    p.push(v4(P.spines.length, P.long ? 1 : 0, P.every, P.spin))
    for (i = 0; i < 3; i++) {
      var s = P.shells[i]
      p.push(s ? v4(s.r, s.pores, s.rings, 0) : v4(0, 0, 0, 0))
    }
    out.main = "fg"; out.mark = P.core
    break
  case "volvox":
    p.push(v4(P.cells, P.tilt, P.spin, Math.min(4, P.daughters.length)))
    for (i = 0; i < 4; i++) {
      var d = P.daughters[i]
      p.push(d ? v4(d.x, d.y, d.z, d.r) : v4(0, 0, 0, 0))
    }
    out.main = P.body; out.mark = "green"
    break
  case "diatom":
    p.push(v4(P.form === "pennate" ? 1 : 0, P.width, P.tip, P.striae))
    p.push(v4(P.rings, P.rays, P.drops.length, P.glide))
    var d0 = P.drops[0] || [0, 0], d1 = P.drops[1] || [0, 0], d2 = P.drops[2] || [0, 0], d3 = P.drops[3] || [0, 0]
    p.push(v4(d0[0], d0[1], d1[0], d1[1]))
    p.push(v4(d2[0], d2[1], d3[0], d3[1]))
    out.main = P.glass; out.mark = P.plastid
    break
  }
  while (p.length < 6) p.push(v4(0, 0, 0, 0))
  return out
}

// The colour named `name` from a host palette given in `colourNames` order,
// or `fallback` ("fg", or a name the theme lacks).
function colour(palette, name, fallback) {
  var i = colourNames.indexOf(name)
  if (i === -1 || !palette || i >= palette.length) return fallback
  return palette[i]
}

// A per-track number 0..100 that offsets its motion, so two organisms of
// one kind never beat or sway in step.
function phase(id) { return Organism.generator(Organism.hash(String(id || "") + "~life"))() * 100 }
