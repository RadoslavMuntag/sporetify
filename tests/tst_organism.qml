import QtQuick
import QtTest

import "../common/Organism.js" as Organism

TestCase {
  name: "Organism"

  readonly property var ids: [
    "spotify:track:4uLU6hMCjMI75M1A2tKUQC", "spotify:track:0VjIjW4GlUZAMYd2vXMi3b",
    "spotify:track:7qiZfU4dY1lWllzX7mPBI3", "spotify:track:3n3Ppam7vgaVa1iaRUc9Lp",
    "spotify:track:2takcwOaAZWiXQijPHIx7B", "", "x"
  ]

  function test_same_id_gives_the_same_creature() {
    for (var i = 0; i < ids.length; i++)
      compare(JSON.stringify(Organism.create(ids[i])), JSON.stringify(Organism.create(ids[i])))
  }

  function test_different_ids_give_different_creatures() {
    var seen = {}
    for (var i = 0; i < ids.length; i++) seen[JSON.stringify(Organism.create(ids[i]))] = true
    compare(Object.keys(seen).length, ids.length)
  }

  // The generator must not change by accident: a creature someone knows
  // would quietly turn into another one.
  function test_hash_is_stable() {
    compare(Organism.hash(""), 0x811c9dc5)
    compare(Organism.hash("a"), 0xe40c292c)
    compare(Organism.hash("foobar"), 0xbf9cf968)
  }

  function test_everything_stays_inside_the_box() {
    for (var n = 0; n < 300; n++) {
      var o = Organism.create("spotify:track:" + n)
      verify(o.lobes.length >= 2 && o.lobes.length <= 7, "lobes: " + o.lobes.length)
      for (var i = 0; i < o.lobes.length; i++) {
        var l = o.lobes[i]
        // Room is left for the lobe's swell and the body's breath.
        verify(l.x - l.r > 0.08 && l.x + l.r < 0.92, "lobe x " + JSON.stringify(l))
        verify(l.y - l.r > 0.08 && l.y + l.r < 0.92, "lobe y " + JSON.stringify(l))
        verify(l.period > 1000 && l.swell > 0 && l.swell < 0.2)
      }
      verify(o.eyes.length >= 1 && o.eyes.length <= 3)
      for (var e = 0; e < o.eyes.length; e++) {
        var eye = o.eyes[e]
        verify(eye.x > 0.25 && eye.x < 0.75 && eye.y > 0.3 && eye.y < 0.6, "eye " + JSON.stringify(eye))
      }
      verify(o.cilia.length <= 9)
      verify(o.tone >= 0 && o.tone < 1 && o.accent >= 0 && o.accent < 1)
      verify(o.breath >= 2800 && o.breath <= 4600)
    }
  }

  function test_population_is_varied() {
    var eyes = {}, lobes = {}, hairless = 0
    for (var n = 0; n < 300; n++) {
      var o = Organism.create("spotify:track:" + n)
      eyes[o.eyes.length] = true
      lobes[o.lobes.length] = true
      if (o.cilia.length === 0) hairless++
    }
    compare(Object.keys(eyes).length, 3)
    verify(Object.keys(lobes).length >= 4)
    verify(hairless > 20 && hairless < 120, "hairless: " + hairless)
  }

  function test_pick() {
    compare(Organism.pick(["a", "b", "c"], 0), "a")
    compare(Organism.pick(["a", "b", "c"], 0.5), "b")
    compare(Organism.pick(["a", "b", "c"], 0.999), "c")
    compare(Organism.pick(["a", "b", "c"], 1), "c")
    compare(Organism.pick([], 0.5), undefined)
  }
}
