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
}
