#version 440

// Everything behind the sharp characters, put together small (D18): the
// water's colour, the far layer (out of focus) and the passer-by (very out
// of focus), into one texture that shaders/compose.frag reads once per
// pixel. Drawn at a third of the size: it is all soft anyway.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float farAlpha;
  float passerAlpha;
};
layout(binding = 1) uniform sampler2D back;
layout(binding = 2) uniform sampler2D far;
layout(binding = 3) uniform sampler2D passer;

vec3 over(vec3 base, vec4 top) { return base * (1.0 - top.a) + top.rgb; }

void main() {
  vec2 uv = qt_TexCoord0;
  vec3 col = texture(back, uv).rgb;
  col = over(col, texture(far, uv) * farAlpha);
  if (passerAlpha > 0.0) col = over(col, texture(passer, uv) * passerAlpha);
  fragColor = vec4(col, 1.0);
}
