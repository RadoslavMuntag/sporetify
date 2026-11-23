import QtQuick

// A cover as a glyph mosaic (Living ASCII, D18): shaders/mosaic.frag reads
// the picture once per character cell. With `mosaic` off, or until the
// picture has loaded, the plain picture is shown.
Item {
  id: root

  property string source: ""
  property bool mosaic: true
  property color deep
  property color ink
  property bool light: false
  // Cell width in px; a cell is twice as tall.
  property real cell: Math.max(3, Math.round(width / 10))

  Image {
    id: picture
    anchors.fill: parent
    visible: !effect.visible
    source: root.source
    sourceSize.width: Math.ceil(width * 2)
    sourceSize.height: Math.ceil(height * 2)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }

  readonly property string glyphs: " .:-=+*#%@"
  Row {
    id: atlasRow
    visible: effect.visible
    Repeater {
      model: root.mosaic ? root.glyphs.length : 0
      Text {
        required property int index
        width: Math.max(3, Math.round(root.cell))
        height: width * 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyphs[index]
        color: root.ink
        font.family: "monospace"
        font.pixelSize: Math.round(width / 0.6)
        font.bold: true
      }
    }
  }
  ShaderEffectSource {
    id: glyphAtlas
    sourceItem: atlasRow
    hideSource: true
    smooth: false
  }

  ShaderEffect {
    id: effect
    anchors.fill: parent
    visible: root.mosaic && picture.status === Image.Ready && status !== ShaderEffect.Error
    fragmentShader: "shaders/mosaic.frag.qsb"
    property var picture: picture
    property var atlas: glyphAtlas
    property size area: Qt.size(width, height)
    property real cell: root.cell
    property real light: root.light ? 1 : 0
    property real glyphs: root.glyphs.length
    property color deep: root.deep
  }
}
