import QtQuick

// The track after the playing one, for the tide pool's edge. Asked of the
// daemon once per track and only while `active`; a newer question cancels
// the older. "" until known, and when it cannot be found: the pool then
// leaves that edge empty, so there is nothing to wait for.
Item {
  id: root

  required property var player
  property bool active: false
  property string next: ""
  readonly property string current: player.trackId

  function refresh() {
    next = ""
    if (!active || current === "") return
    var asked = current
    player.request("player.up_next", { limit: 1 }, {
      deadline: 5000,
      scope: "upNext",
      onDone: function(result) {
        if (asked !== root.current || !root.active || !result.ok) return
        var items = result.data.items || []
        root.next = items.length > 0 && items[0].uri ? items[0].uri : ""
      }
    })
  }

  visible: false
  onCurrentChanged: refresh()
  onActiveChanged: refresh()
}
