import QtQuick

// The seek bar as a measuring ruler: a tick every 10 s, a longer one every
// 30 s (every minute and every five on long tracks), the played part as a
// heavier accent line, and a needle where the track is. Works like Slider.
Slider {
  id: root

  // Length of the track, for the ticks.
  property real durationMs: 0

  // Seconds between ticks, and how many ticks make a long one.
  readonly property int every: durationMs > 1200000 ? 60 : 10
  readonly property int longEvery: durationMs > 1200000 ? 5 : 3
  readonly property int count: durationMs > 0 ? Math.floor(durationMs / 1000 / every) + 1 : 0

  Repeater {
    model: root.count

    Rectangle {
      required property int index
      readonly property bool long: index % root.longEvery === 0
      x: root.inset + root.span * (index * root.every * 1000 / root.durationMs) - width / 2
      y: root.height / 2 - height
      width: Theme.stroke.hair
      height: Theme.space(long ? 7 : 4)
      color: index * root.every * 1000 / root.durationMs <= root.shown ? Theme.accent : Theme.border
    }
  }
}
