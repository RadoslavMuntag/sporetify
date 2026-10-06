import QtQuick
import QtTest

import "../common/Keymap.js" as Keymap
import "../common/Position.js" as Position

TestCase {
  name: "KeymapAndPosition"

  function test_printable_and_named_keys_resolve() {
    compare(Keymap.actionFor(Qt.Key_Space, " ", "player"), "playPause")
    compare(Keymap.actionFor(Qt.Key_N, "n", "player"), "next")
    compare(Keymap.actionFor(Qt.Key_Plus, "+", "player"), "volumeUp")
    compare(Keymap.actionFor(Qt.Key_Equal, "=", "player"), "volumeUp")
    compare(Keymap.actionFor(Qt.Key_Left, "", "player"), "seekBack")
    compare(Keymap.actionFor(Qt.Key_Escape, "", "player"), "close")
  }

  function test_scope_limits_actions() {
    compare(Keymap.actionFor(Qt.Key_N, "n", "signedOut"), null)
    compare(Keymap.actionFor(Qt.Key_Return, "", "signedOut"), "signIn")
    compare(Keymap.actionFor(Qt.Key_Return, "", "fault"), "retry")
    compare(Keymap.actionFor(Qt.Key_Return, "", "player"), null)
    compare(Keymap.actionFor(Qt.Key_Escape, "", "signedOut"), "close")
  }

  function test_scope_lists_resolve_most_specific_first() {
    var scopes = ["browse", "player"]
    compare(Keymap.actionFor(Qt.Key_J, "j", scopes), "down")
    compare(Keymap.actionFor(Qt.Key_Return, "", scopes), "activate")
    compare(Keymap.actionFor(Qt.Key_Space, " ", scopes), "playPause")
    compare(Keymap.actionFor(Qt.Key_Q, "q", scopes), "close")
    compare(Keymap.actionFor(Qt.Key_PageDown, "", scopes), "pageDown")
    // Signed out, Return signs in rather than activating a row.
    compare(Keymap.actionFor(Qt.Key_Return, "", ["signedOut", "browse"]), "signIn")
  }

  function test_scopes_shown_together_share_no_key() {
    var together = [["browse", "player"], ["mini", "player"]]
    for (var t = 0; t < together.length; t++) {
      var seen = {}
      for (var i = 0; i < Keymap.actions.length; i++) {
        var action = Keymap.actions[i]
        if (together[t].indexOf(action.scope) === -1 && action.scope !== "any") continue
        for (var k = 0; k < action.keys.length; k++) {
          verify(!seen[action.keys[k]], action.keys[k] + " means both " + seen[action.keys[k]] + " and " + action.id)
          seen[action.keys[k]] = action.id
        }
      }
    }
  }

  function test_primary_hints_are_a_subset() {
    var all = Keymap.hints(["browse", "player"], false)
    var primary = Keymap.hints(["browse", "player"], true)
    verify(primary.length > 0 && primary.length < all.length)
    compare(primary[primary.length - 1].label, "Close")
    compare(Keymap.actionFor(Qt.Key_Backspace, "", ["browse", "player"]), "back")
    compare(Keymap.actionFor(Qt.Key_Question, "?", ["browse", "player"]), "help")
  }

  function test_unknown_keys_do_nothing() {
    compare(Keymap.actionFor(Qt.Key_F5, "", "player"), null)
    compare(Keymap.actionFor(Qt.Key_Z, "z", "player"), null)
  }

  function test_no_key_is_bound_twice_in_a_scope() {
    var seen = {}
    for (var i = 0; i < Keymap.actions.length; i++) {
      var action = Keymap.actions[i]
      for (var k = 0; k < action.keys.length; k++) {
        var slot = action.scope + "/" + action.keys[k]
        verify(!seen[slot], slot + " is bound to both " + seen[slot] + " and " + action.id)
        seen[slot] = action.id
        // A scoped key must not shadow an "any" key either.
        if (action.scope !== "any") verify(!seen["any/" + action.keys[k]], action.keys[k] + " shadows a global key")
      }
    }
  }

  function test_hints_come_from_the_same_table() {
    var hints = Keymap.hints("player")
    compare(hints[0].key, "␣")
    compare(hints[0].label, "Play/Pause")
    compare(hints[hints.length - 1].label, "Close")
    compare(Keymap.keyLabel("next"), "n")
    compare(Keymap.keyLabel("seekForward"), "→")
  }

  function test_position_interpolates_only_while_playing() {
    var playing = { position_ms: 10000, at_ms: 5000, rate: 1 }
    compare(Position.at(playing, 8000, 200000), 13000)
    var paused = { position_ms: 10000, at_ms: 5000, rate: 0 }
    compare(Position.at(paused, 8000, 200000), 10000)
  }

  function test_position_is_clamped() {
    var playing = { position_ms: 199000, at_ms: 0, rate: 1 }
    compare(Position.at(playing, 60000, 200000), 200000)
    compare(Position.at(null, 1, 1), 0)
    // A clock that runs behind the daemon's must not move the position backwards.
    compare(Position.at({ position_ms: 500, at_ms: 9000, rate: 1 }, 8000, 200000), 500)
  }

  function test_clock_format() {
    compare(Position.clock(0), "0:00")
    compare(Position.clock(83000), "1:23")
    compare(Position.clock(600000), "10:00")
  }
}
