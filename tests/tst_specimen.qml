import QtQuick
import QtTest

import "../common/Specimen.js" as Specimen
import "../common/Organism.js" as Organism
import "../common/Visuals.js" as Visuals

TestCase {
  name: "Specimen"

  function test_catalogue_number_is_stable_and_short() {
    compare(Specimen.catalogue(""), "")
    var id = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
    compare(Specimen.catalogue(id), Specimen.catalogue(id))
    compare(Specimen.catalogue(id).length, 4)
    verify(/^[0-9A-F]{4}$/.test(Specimen.catalogue(id)))
    // A hash with leading zeros still gives four digits.
    compare(Specimen.catalogue("x").length, 4)
  }

  function test_traits_name_the_organism() {
    var ids = ["spotify:track:7qiZfU4dY1lWllzX7mPBI3", "a", "b", "c", "d", "e", "f"]
    for (var i = 0; i < ids.length; i++) {
      var rows = Specimen.table(ids[i])
      compare(rows[0].name, "kind")
      verify(rows.length >= 3, JSON.stringify(rows))
      // The line starts with the kind, as the table does.
      compare(Specimen.traits(ids[i]).indexOf(rows[0].value), 0)
    }
    compare(Specimen.count(1, "eye"), "1 eye")
    compare(Specimen.count(0, "hair"), "0 hairs")
  }

  function test_chords_stay_inside_the_circle() {
    var lines = Specimen.chords(6)
    compare(lines.length, 11)
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      verify(Math.abs(l.offset) < 1)
      // The line's ends lie on the rim.
      fuzzyCompare(l.offset * l.offset + l.half * l.half, 1, 1e-9)
    }
  }

  function test_lit_ticks() {
    compare(Specimen.lit(0, 72), 0)
    compare(Specimen.lit(NaN, 72), 0)
    compare(Specimen.lit(-1, 72), 0)
    compare(Specimen.lit(0.5, 72), 36)
    compare(Specimen.lit(1, 72), 72)
    compare(Specimen.lit(2, 72), 72)
  }

  function test_arrangement() {
    compare(Specimen.arrangement(340, 380), "stack")
    compare(Specimen.arrangement(300, 300), "stack")
    compare(Specimen.arrangement(260, 600), "stack")
    compare(Specimen.arrangement(600, 220), "side")
    compare(Specimen.arrangement(450, 300), "side")
  }

  function test_spectrum_sampling_reads_between_bands() {
    compare(Visuals.sample([], 0.5), 0)
    compare(Visuals.sample(undefined, 0.5), 0)
    compare(Visuals.sample([0.4], 0.9), 0.4)
    compare(Visuals.sample([0, 1], 0), 0)
    compare(Visuals.sample([0, 1], 1), 1)
    fuzzyCompare(Visuals.sample([0, 1], 0.25), 0.25, 1e-9)
    fuzzyCompare(Visuals.sample([0, 1, 0], 0.5), 1, 1e-9)
    fuzzyCompare(Visuals.sample([0, 1, 0], 0.75), 0.5, 1e-9)
    // Out of range clamps to the ends.
    compare(Visuals.sample([0.2, 0.8], -1), 0.2)
    compare(Visuals.sample([0.2, 0.8], 2), 0.8)
  }

  function test_visuals_levels() {
    compare(Visuals.level("reduced"), "reduced")
    compare(Visuals.level(""), "full")
    compare(Visuals.level(undefined), "full")
    compare(Visuals.level("bogus"), "full")
    // Creatures are a switch of their own, on unless saved as false.
    verify(Visuals.creatures(undefined) && Visuals.creatures(true))
    verify(!Visuals.creatures(false))
    compare(Visuals.next("full"), "reduced")
    compare(Visuals.next("reduced"), "off")
    compare(Visuals.next("off"), "full")
    verify(Visuals.drawn("reduced") && !Visuals.moving("reduced"))
    verify(!Visuals.drawn("off") && Visuals.moving("full"))
  }

  function test_low_end_of_a_frame() {
    compare(Specimen.low([]), 0)
    compare(Specimen.low(undefined), 0)
    var frame = [1, 0.5, 0.5, 0, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9]
    fuzzyCompare(Specimen.low(frame), 0.5, 1e-9)
    // Out-of-range levels are held to 0..1.
    compare(Specimen.low([2, 2, 2, 2]), 1)
    compare(Specimen.low([-1]), 0)
  }

  function test_bar_is_always_the_given_width() {
    for (var p = 0; p <= 1.0001; p += 0.05) {
      var b = Specimen.bar(p, 20)
      compare(b.done.length + b.rest.length, 20)
    }
    compare(Specimen.bar(0, 10).done, "●")
    compare(Specimen.bar(1, 10).rest, "")
    compare(Specimen.bar(0.5, 11).done, "=====●")
    // Nonsense is held in range.
    compare(Specimen.bar(-3, 5).done, "●")
    compare(Specimen.bar(NaN, 5).done, "●")
  }
}
