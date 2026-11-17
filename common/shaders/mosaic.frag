#version 440

// A cover drawn as characters (the Living ASCII look, D18): each cell takes
// the picture's colour at its centre, a faint wash of it as the ground, and
// a glyph from the brightness ramp " .:-=+*#%@" in a stronger version of it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px
  float cell;     // cell width, px; a cell is twice as tall
  float light;
  float glyphs;
  vec4 deep;
};
layout(binding = 1) uniform sampler2D picture;
layout(binding = 2) uniform sampler2D atlas;

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 cols = max(vec2(1.0), floor(area / csz));
  // Cells stretched a little to fill the cover exactly.
  vec2 fit = area / cols;
  vec2 ci = floor(px / fit);
  vec2 local = fract(px / fit);
  vec3 c = texture(picture, (ci + 0.5) / cols).rgb;
  float lum = dot(c, vec3(0.3, 0.59, 0.11));
  float level = light > 0.5 ? 1.0 - lum : lum;
  float g = 1.0 + min(8.0, floor(level * 9.0));
  local = mix(vec2(0.08, 0.04), vec2(0.92, 0.96), local);
  float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
  vec3 ground = mix(deep.rgb, c, light > 0.5 ? 0.35 : 0.3);
  vec3 fg = clamp(c * (light > 0.5 ? 0.55 : 1.25), 0.0, 1.0);
  fragColor = vec4(mix(ground, fg, ink), 1.0) * qt_Opacity;
}
