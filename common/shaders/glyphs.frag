#version 440

// Characters from a field of light (D18): one texel per character cell,
// merged from organisms and water by shaders/combine.frag. Each cell shows
// the glyph of its brightness from `atlas` in its colour, as the organism
// studies do; glass spines use line glyphs where nothing brighter is. This
// runs for every pixel, so it reads just the one field and the atlas.
//
// Atlas: " .·:-=+*#%@" then "-|/\°".

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px
  vec2 grid;      // columns, rows of the fields
  float cell;     // cell width, px; a cell is twice as tall
  float light;    // 1 on a light theme
  float glyphs;   // glyphs in the atlas
};
layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D field;

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 ci = floor(px / csz);
  vec2 uv = (ci + 0.5) / grid;
  vec4 s = texture(field, uv);
  if (s.a <= 0.0) discard;
  float lineG = s.a > 0.81 ? floor((s.a - 0.8) / 0.04 + 0.5) : 0.0;
  float total = lineG > 0.0 ? 0.0 : s.a / 0.8 * 1.4;
  vec3 colour = s.rgb, lineC = s.rgb;

  float g, alpha;
  vec3 col;
  if (lineG > 0.0 && total < 0.32) {
    g = 10.0 + lineG; col = lineC; alpha = 0.85;
  } else {
    if (total < 0.04) discard;
    g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
    col = colour;
    // The brightest cells are lit beyond their colour, as the studies'
    // second shade of every colour.
    if (total > 0.9) col = mix(col, vec3(1.0 - light), light > 0.5 ? 0.32 : 0.42);
    alpha = clamp(0.2 + total * 1.05, 0.08, 1.0);
  }

  // A little inside the cell: at its very edge the filter reads the
  // neighbouring glyph, which drew a faint box around characters.
  vec2 local = mix(vec2(0.08, 0.04), vec2(0.92, 0.96), fract(px / csz));
  float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
  fragColor = vec4(col, 1.0) * ink * alpha * qt_Opacity;
}
