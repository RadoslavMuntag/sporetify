import QtQuick
import QtTest

import "../common/Pool.js" as Pool

TestCase {
  name: "Pool"

  function test_first_assignment_fills_in_order() {
    compare(Pool.assign([], ["a", "b", "c"], 5), ["a", "b", "c", "", ""])
  }

  function test_a_track_change_moves_nobody() {
    var slots = Pool.assign([], ["a", "b", "c"], 5)
    // b starts playing, a falls into the queue: everyone keeps their slot.
    compare(Pool.assign(slots, ["b", "a", "c"], 5), ["a", "b", "c", "", ""])
  }

  function test_newcomers_use_empty_slots_first() {
    var slots = ["a", "b", "c", "", ""]
    // a is no longer wanted: it stays to shrink, d takes an empty slot.
    compare(Pool.assign(slots, ["b", "c", "d"], 5), ["a", "b", "c", "d", ""])
  }

  function test_unwanted_ones_give_way_when_full() {
    var slots = ["a", "b", "c", "d", "e"]
    compare(Pool.assign(slots, ["b", "f"], 5), ["f", "b", "c", "d", "e"])
  }

  function test_duplicates_and_empties_are_ignored() {
    compare(Pool.assign([], ["a", "", "a", "b"], 3), ["a", "b", ""])
  }

  function test_never_more_than_the_slots() {
    compare(Pool.assign([], ["a", "b", "c", "d"], 2), ["a", "b"])
  }

  function test_roles() {
    compare(Pool.role("a", ["a", "b"]), "main")
    compare(Pool.role("b", ["a", "b"]), "queue")
    compare(Pool.role("c", ["a", "b"]), "gone")
    compare(Pool.role("", ["a", "b"]), "gone")
  }
}
