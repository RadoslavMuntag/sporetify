import QtQuick
import QtTest

import "../common/Plankton.js" as Plankton

TestCase {
  name: "Plankton"

  function ids(n) {
    var out = []
    for (var i = 0; i < n; i++) out.push("spotify:track:" + i)
    return out
  }

  function test_same_id_gives_the_same_organism() {
    var list = ids(50).concat(["", "x"])
    for (var i = 0; i < list.length; i++)
      compare(JSON.stringify(Plankton.create(list[i])), JSON.stringify(Plankton.create(list[i])))
  }

  // The organism studies (artifact) grow these from the same hash and salts;
  // a change here turns a track someone knows into another organism.
  function test_generators_are_stable() {
    compare(Plankton.kindOf("spotify:track:silver-lining:north-atlas"), Plankton.kindOf("spotify:track:silver-lining:north-atlas"))
    var m = Plankton.create("spotify:track:0", "medusa")
    verify(m.tentacles >= 10 && m.tentacles <= 22)
    verify([4, 8, 16].indexOf(m.canals) !== -1)
  }

  function test_mixed_weights_every_kind() {
    var count = {}
    var list = ids(2000)
    for (var i = 0; i < list.length; i++) {
      var k = Plankton.kindOf(list[i])
      count[k] = (count[k] || 0) + 1
    }
    for (var j = 0; j < Plankton.kinds.length; j++) verify(count[Plankton.kinds[j]] > 150, Plankton.kinds[j] + ": " + count[Plankton.kinds[j]])
    verify(count.medusa > count.diatom, "medusae outnumber diatoms")
  }

  function test_a_kind_can_be_asked_for() {
    for (var j = 0; j < Plankton.kinds.length; j++)
      compare(Plankton.create("spotify:track:7", Plankton.kinds[j]).kind, Plankton.kinds[j])
    compare(Plankton.create("spotify:track:7", "nonsense").kind, Plankton.kindOf("spotify:track:7"))
  }

  function test_uniforms_are_complete_and_finite() {
    var list = ids(300)
    for (var j = 0; j < Plankton.kinds.length; j++) {
      for (var i = 0; i < list.length; i += 7) {
        var P = Plankton.create(list[i], Plankton.kinds[j])
        var u = Plankton.uniforms(P)
        compare(u.kind, j)
        compare(u.p.length, 6)
        for (var n = 0; n < 6; n++) {
          var v = u.p[n]
          verify(isFinite(v.x) && isFinite(v.y) && isFinite(v.z) && isFinite(v.w), P.kind + " p" + n)
        }
        verify(u.main === "fg" || Plankton.colourNames.indexOf(u.main) !== -1, u.main)
        verify(u.mark === "fg" || Plankton.colourNames.indexOf(u.mark) !== -1, u.mark)
        verify(Plankton.traits(P).length > 0)
      }
    }
  }

  // The shader's loops stop at these counts; more would be cut off silently.
  function test_counts_fit_the_shader() {
    var list = ids(500)
    for (var i = 0; i < list.length; i++) {
      var m = Plankton.create(list[i], "medusa"), c = Plankton.create(list[i], "ctenophore")
      var r = Plankton.create(list[i], "radiolarian"), d = Plankton.create(list[i], "diatom")
      verify(m.tentacles <= 22 && m.canals <= 16 && m.oralArms <= 4)
      verify(c.plates <= 22)
      verify(r.axopods <= 34 && r.spines.length <= 20 && r.shells.length <= 3)
      verify(d.drops.length <= 4)
    }
  }

  function test_colour() {
    var palette = ["g", "c", "b", "m", "y", "o", "r"]
    compare(Plankton.colour(palette, "cyan", "f"), "c")
    compare(Plankton.colour(palette, "red", "f"), "r")
    compare(Plankton.colour(palette, "fg", "f"), "f")
    compare(Plankton.colour(["g"], "red", "f"), "f")
    compare(Plankton.colour([], "green", "f"), "f")
  }

  function test_phase_differs_between_tracks() {
    verify(Plankton.phase("a") !== Plankton.phase("b"))
    verify(Plankton.phase("a") >= 0 && Plankton.phase("a") < 100)
  }
}
