import QtQuick
import QtTest

import "../common/Pages.js" as Pages

TestCase {
  name: "Pages"

  function test_claims_only_pages_covering_the_range() {
    var pages = Pages.create(50)
    compare(pages.claim(0, 20, 765), [0])
    compare(pages.claim(40, 110, 765), [1, 2])
  }

  function test_a_page_is_claimed_once_until_it_fails() {
    var pages = Pages.create(50)
    compare(pages.claim(0, 10, 100), [0])
    compare(pages.claim(0, 10, 100), [])
    pages.failed(0)
    compare(pages.claim(0, 10, 100), [0])
    pages.done(0)
    compare(pages.claim(0, 10, 100), [])
    verify(pages.isLoaded(0))
  }

  function test_range_is_clamped_to_the_list() {
    var pages = Pages.create(50)
    compare(pages.claim(-10, 500, 60), [0, 1])
    compare(pages.claim(0, 10, 0), [])
    compare(pages.claim(30, 10, 100), [])
  }

  function test_reset_forgets_everything() {
    var pages = Pages.create(50)
    pages.claim(0, 10, 100)
    pages.done(0)
    pages.reset()
    compare(pages.claim(0, 10, 100), [0])
  }

  function test_tracks_are_numbered_within_their_section() {
    var rows = Pages.numberTracks([
      { kind: "heading", title: "Start here" }, { kind: "playlist" },
      { kind: "heading", title: "Popular" }, { uri: "a" }, { uri: "b" },
      { kind: "heading", title: "Albums" }, { kind: "album" }, { uri: "c" }
    ])
    compare(rows[3].n, 1)
    compare(rows[4].n, 2)
    compare(rows[7].n, 1)
    compare(rows[1].n, undefined)
    compare(rows[6].n, undefined)
  }

  function test_a_list_without_headings_counts_straight_through() {
    var rows = Pages.numberTracks([{ uri: "a" }, { kind: "artist" }, { uri: "b" }, null, { uri: "c" }])
    compare(rows[0].n, 1)
    compare(rows[2].n, 2)
    compare(rows[4].n, 3)
  }
}
