import QtQuick
import QtTest

import "../common"

// The tide pool keeps its own idea of who sits at each edge, so a swim
// never starts with the wrong creature in a place.
TestCase {
  name: "TidePool"

  Component {
    id: poolComponent
    TidePool { width: 200; height: 200; alive: true; palette: []; seed: "a"; nextSeed: "b" }
  }

  function test_forward_swims_in_from_the_right() {
    var pool = createTemporaryObject(poolComponent, this)
    compare(pool.nextShown, "b")
    compare(pool.previousShown, "")
    pool.seed = "b"
    compare(pool.previousShown, "a")
    compare(pool.nextShown, "")
    // It starts where the next creature sat and swims to the middle.
    compare(pool.slide, 1)
    tryCompare(pool, "slide", 0, 1000)
    // The host's next, once known, takes the edge; the playing one never does.
    pool.nextSeed = "b"
    compare(pool.nextShown, "")
    pool.nextSeed = "c"
    compare(pool.nextShown, "c")
  }

  function test_back_swims_in_from_the_left() {
    var pool = createTemporaryObject(poolComponent, this)
    pool.seed = "b"
    pool.seed = "a"
    compare(pool.nextShown, "b")
    compare(pool.previousShown, "")
    compare(pool.slide, -1)
  }

  function test_a_jump_does_not_swim() {
    var pool = createTemporaryObject(poolComponent, this)
    pool.seed = "z"
    compare(pool.previousShown, "a")
    compare(pool.nextShown, "")
    compare(pool.slide, 0)
  }

  function test_nothing_moves_while_still() {
    var pool = createTemporaryObject(poolComponent, this, { alive: false })
    pool.seed = "b"
    compare(pool.previousShown, "a")
    compare(pool.slide, 0)
  }
}
