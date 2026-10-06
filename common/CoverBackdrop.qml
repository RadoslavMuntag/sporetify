import QtQuick

// A cover used as a backdrop that dissolves upward: sharp and solid at the
// bottom, and towards the top both fainter and coarser, like pixel art
// losing resolution. Text placed over the upper part stays readable.
//
// Experimental. It is built from horizontal bands, each showing its slice of
// the same picture decoded at a lower resolution and drawn without
// smoothing, so there is no shader and nothing animates.
Item {
  id: root

  // Local file url of the cover, or "".
  property string source: ""
  // How many steps the dissolve has.
  property int bands: 12
  // Pixel size of the coarsest (top) band, in screen pixels.
  property int coarsest: 18
  // Opacity of the top band; the bottom one is opaque.
  property real faintest: 0.04

  clip: true

  // The cover is square: it is drawn as wide as the backdrop and centred
  // vertically, with the overflow cut off. Every band uses this same
  // geometry, so the slices line up whatever resolution each is decoded at.
  readonly property real side: Math.max(width, height)
  readonly property real offsetX: (width - side) / 2
  readonly property real offsetY: (height - side) / 2

  function bandTop(index) {
    return Math.round(index * height / bands)
  }

  Repeater {
    model: root.source !== "" ? root.bands : 0

    Item {
      id: band
      required property int index
      // 0 at the top, 1 at the bottom.
      readonly property real t: root.bands > 1 ? index / (root.bands - 1) : 1
      // Resolution falls off faster than opacity, so the picture is still
      // recognisable where it has become blocky.
      readonly property int block: Math.max(1, Math.round(root.coarsest * Math.pow(1 - t, 1.6)))
      readonly property int cells: Math.max(2, Math.round(root.side / block))

      // Whole pixels, each band ending exactly where the next begins.
      y: root.bandTop(index)
      width: root.width
      height: root.bandTop(index + 1) - y
      clip: true
      opacity: root.faintest + (1 - root.faintest) * Math.pow(t, 1.5)

      Image {
        x: root.offsetX
        y: root.offsetY - band.y
        width: root.side
        height: root.side
        source: root.source
        fillMode: Image.Stretch
        // Decoded small and scaled back up unsmoothed: that is the pixel look.
        sourceSize.width: band.cells
        sourceSize.height: band.cells
        smooth: false
        mipmap: false
        asynchronous: true
      }
    }
  }
}
