#version 440

// Adds `source` (a blurred copy of the organisms) onto whatever is below,
// like a screen blend: the output's alpha is 0, so Qt Quick's
// premultiplied blending adds its colour instead of covering. On a light
// theme it darkens a little instead, as light glowing would wash out.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float strength;
  float light;
};
layout(binding = 1) uniform sampler2D source;

void main() {
  vec4 c = texture(source, qt_TexCoord0);
  if (light > 0.5) fragColor = vec4(c.rgb, c.a) * strength * 0.35 * qt_Opacity;
  else fragColor = vec4(c.rgb * strength * qt_Opacity, 0.0);
}
