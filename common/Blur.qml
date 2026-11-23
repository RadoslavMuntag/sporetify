import QtQuick

// A Gaussian blur of a small texture (shaders/blur.frag, across then
// down), for the pool's soft layers: the far water, the glow, the copy of
// the scene behind glass. The organism studies blur theirs with CSS
// filters; scaling a small copy up instead looks blocky, so every soft
// layer goes through this once, at its small size, and is read once.
//
// `source` is a texture provider (a ShaderEffectSource), `textureSize`
// what to blur it at, `sigma` the blur in texels of that size. Use
// `texture` as a shader's sampler; it is never shown itself.
Item {
  id: root

  property var source: null
  property size textureSize: Qt.size(1, 1)
  property real sigma: 2
  property bool live: true
  readonly property Item texture: down

  // The kernel's spread is about 1.7 taps; past ~3 taps apart it would
  // leave gaps, so a larger blur is better asked of a smaller texture.
  readonly property real reach: Math.max(0.01, sigma / 1.7)

  ShaderEffect {
    id: acrossFx
    width: root.width
    height: root.height
    fragmentShader: "shaders/blur.frag.qsb"
    property var source: root.source
    property point delta: Qt.point(root.reach / Math.max(1, root.textureSize.width), 0)
  }
  ShaderEffectSource {
    id: across
    sourceItem: acrossFx
    hideSource: true
    smooth: true
    live: root.live
    textureSize: root.textureSize
  }
  ShaderEffect {
    id: downFx
    width: root.width
    height: root.height
    fragmentShader: "shaders/blur.frag.qsb"
    property var source: across
    property point delta: Qt.point(0, root.reach / Math.max(1, root.textureSize.height))
  }
  ShaderEffectSource {
    id: down
    sourceItem: downFx
    hideSource: true
    smooth: true
    live: root.live
    textureSize: root.textureSize
  }
}
