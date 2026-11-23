#version 440

// One direction of a Gaussian blur (common/Blur.qml runs it twice, across
// then down). Nine taps read as five, each between two texels so the
// linear filter averages them. The layers it blurs are drawn small, so
// this is cheap; it is what makes them soft the way the organism studies'
// CSS blur does, instead of blocky from being scaled up.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 delta;      // one tap's reach, in texture coordinates
};
layout(binding = 1) uniform sampler2D source;

void main() {
  vec2 uv = qt_TexCoord0;
  vec4 c = texture(source, uv) * 0.2270270;
  c += texture(source, uv + delta * 1.3846154) * 0.3162162;
  c += texture(source, uv - delta * 1.3846154) * 0.3162162;
  c += texture(source, uv + delta * 3.2307692) * 0.0702703;
  c += texture(source, uv - delta * 3.2307692) * 0.0702703;
  fragColor = c * qt_Opacity;
}
