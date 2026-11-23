#version 440

// Glow: a small copy of the near layer (`source`, a quarter of the size),
// softened further with a few taps as it is read, added onto whatever is
// below like a screen blend: the output's alpha is 0, so Qt Quick's
// premultiplied blending adds its colour instead of covering. On a light
// theme it darkens a little instead, as light glowing would wash out.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 spread;    // one tap's reach, in texture coordinates
  float strength;
  float light;
};
layout(binding = 1) uniform sampler2D source;

void main() {
  vec2 uv = qt_TexCoord0;
  vec4 c = texture(source, uv) * 0.36;
  c += texture(source, uv + spread * vec2(1.2, 0.0)) * 0.16;
  c += texture(source, uv - spread * vec2(1.2, 0.0)) * 0.16;
  c += texture(source, uv + spread * vec2(0.0, 1.2)) * 0.16;
  c += texture(source, uv - spread * vec2(0.0, 1.2)) * 0.16;
  if (light > 0.5) fragColor = c * strength * 0.35 * qt_Opacity;
  else fragColor = vec4(c.rgb * strength * qt_Opacity, 0.0);
}
