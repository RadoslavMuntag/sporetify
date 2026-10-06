import QtQuick
import QtQuick.Window

// A cover used as a backdrop whose upper part dissolves into pixel art: the
// lower part is shown as it is, and above that the picture is drawn in rows
// of square pixels that grow steadily bigger, and fainter, towards the top.
// Text placed over the upper part stays readable.
//
// Experimental. Each row of pixels is its own strip: the cover decoded at
// that row's resolution and drawn unsmoothed, placed so the strip shows
// exactly one row of it. There is no shader and nothing animates.
Item {
  id: root

  // Local file url of the cover, or "".
  property string source: ""
  // How much of the height, from the top, the dissolve covers. Below that
  // the cover is shown as it is.
  property real span: 0.7
  // Size of the biggest pixels, at the very top.
  property real coarsest: 20
  // Each row's pixels are this much smaller than the row above; closer to 1
  // gives more, gentler steps.
  property real falloff: 0.86
  // Opacity of the top row; where the dissolve ends the cover is opaque.
  property real faintest: 0.04

  clip: true

  // The cover is square: it is drawn as wide as the backdrop and centred
  // vertically, with the overflow cut off.
  readonly property real side: Math.max(width, height)
  readonly property real offsetX: (width - side) / 2
  readonly property real offsetY: (height - side) / 2
  // Where the dissolve ends and the untouched cover begins.
  readonly property int dissolveEnd: Math.round(height * span)

  // The rows of the dissolve, top to bottom: [{ y, size, t }]. A row is as
  // tall as its pixels are wide. Sizes shrink by `falloff` per row until
  // they reach the cover's own resolution, then the whole run is scaled to
  // fill the dissolve exactly, on whole pixels so rows meet without seams.
  readonly property var rows: {
    var total = dissolveEnd
    if (total <= 0 || source === "") return []
    var sizes = []
    for (var size = coarsest; size > 1 && sizes.length < 64; size *= falloff) sizes.push(size)
    var sum = 0
    for (var i = 0; i < sizes.length; i++) sum += sizes[i]
    var out = []
    var edge = 0
    for (var j = 0; j < sizes.length; j++) {
      var top = Math.round(edge)
      edge += sizes[j] * total / sum
      var bottom = Math.round(edge)
      if (bottom > top) out.push({ y: top, size: bottom - top, t: (top + bottom) / 2 / total })
    }
    return out
  }

  Repeater {
    model: root.rows

    Item {
      id: row
      required property var modelData
      // How many pixels of this size the cover is across.
      readonly property int cells: Math.max(2, Math.round(root.side / modelData.size))
      // Which of the cover's rows of pixels falls on this strip.
      readonly property int line: Math.max(0, Math.min(cells - 1,
        Math.floor((modelData.y + modelData.size / 2 - root.offsetY) / root.side * cells)))

      y: modelData.y
      width: root.width
      height: modelData.size
      clip: true
      opacity: root.faintest + (1 - root.faintest) * Math.pow(modelData.t, 1.5)

      Image {
        x: root.offsetX
        // Stretched so one row of the decoded picture is exactly as tall as
        // the strip, and shifted so the strip shows the row chosen above.
        y: -row.line * row.height
        width: root.side
        height: row.cells * row.height
        source: root.source
        fillMode: Image.Stretch
        sourceSize.width: row.cells
        sourceSize.height: row.cells
        smooth: false
        mipmap: false
        asynchronous: true
      }
    }
  }

  // ---- Below the dissolve: the cover as it is.
  Item {
    visible: root.source !== ""
    y: root.dissolveEnd
    width: root.width
    height: root.height - root.dissolveEnd
    clip: true

    Image {
      x: root.offsetX
      y: root.offsetY - root.dissolveEnd
      width: root.side
      height: root.side
      source: root.source
      fillMode: Image.Stretch
      sourceSize.width: Math.round(root.side * Screen.devicePixelRatio)
      sourceSize.height: Math.round(root.side * Screen.devicePixelRatio)
      asynchronous: true
    }
  }
}
