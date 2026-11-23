#version 440

// The source of the pool's glow (D18): the near layer's characters as
// they look from far enough away, drawn small. The glow is blurred to
// about a cell across, so each cell only needs its glyph's share of ink
// (measured from the font at the pool's cell sizes) in its colour, not the
// glyph itself: one read of the field per pixel and none of the atlas.
// Decoded as shaders/glyphs.frag decodes it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px
  vec2 grid;      // columns, rows of the field
  float cell;     // cell width, px; a cell is twice as tall
  float light;    // 1 on a light theme
};
layout(binding = 1) uniform sampler2D field;

// Ink per glyph of " .·:-=+*#%@" then "-|/\°", as a share of the cell.
const float INK[16] = float[16](0.0, 0.03, 0.03, 0.06, 0.04, 0.10, 0.11, 0.15,
                                0.23, 0.25, 0.30, 0.04, 0.13, 0.13, 0.13, 0.07);

void main() {
  vec2 ci = floor(qt_TexCoord0 * area / vec2(cell, cell * 2.0));
  vec4 s = texture(field, (ci + 0.5) / grid);
  if (s.a <= 0.0) { fragColor = vec4(0.0); return; }
  float lineG = s.a > 0.81 ? floor((s.a - 0.8) / 0.04 + 0.5) : 0.0;
  float total = lineG > 0.0 ? 0.0 : s.a / 0.8 * 1.4;
  vec3 col = s.rgb;
  float g, alpha;
  if (lineG > 0.0 && total < 0.32) {
    g = 10.0 + lineG; alpha = 0.85;
  } else {
    if (total < 0.04) { fragColor = vec4(0.0); return; }
    g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
    if (total > 0.9) col = mix(col, vec3(1.0 - light), light > 0.5 ? 0.32 : 0.42);
    alpha = clamp(0.2 + total * 1.05, 0.08, 1.0);
  }
  fragColor = vec4(col, 1.0) * INK[int(g)] * alpha * qt_Opacity;
}
