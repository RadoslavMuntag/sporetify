import QtQuick
import QtTest
import "../common/Faults.js" as Faults

TestCase {
  name: "Faults"

  function test_a_missing_or_old_daemon_names_the_setup_command() {
    var phases = ["unavailable", "incompatible"]
    for (var i = 0; i < phases.length; i++) {
      verify(Faults.title(phases[i]) !== "")
      verify(Faults.advice(phases[i]) !== "")
      verify(Faults.command(phases[i]).indexOf("scripts/setup.sh") > 0)
    }
    verify(Faults.title("unavailable") !== Faults.title("incompatible"))
  }

  function test_other_faults_have_a_title_and_no_command() {
    var phases = ["signed_out", "offline", "no_premium"]
    for (var i = 0; i < phases.length; i++) {
      verify(Faults.title(phases[i]) !== "")
      compare(Faults.command(phases[i]), "")
      compare(Faults.advice(phases[i]), "")
    }
  }

  function test_working_phases_are_not_faults() {
    var phases = ["ready", "starting", "asleep", "something new"]
    for (var i = 0; i < phases.length; i++) {
      compare(Faults.title(phases[i]), "")
      compare(Faults.command(phases[i]), "")
    }
  }
}
