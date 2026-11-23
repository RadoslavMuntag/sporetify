#version 440

// Characters from a field of light (D18): one texel per character cell,
// merged from organisms and water by shaders/combine.frag. Each cell shows
// the glyph of its brightness from `atlas` in its colour, as the organism
// studies do; glass spines use line glyphs where nothing brighter is. This
// runs for every pixel, so it reads just the one field and the atlas.
//
// Drawn small (the far layer, the glow), one pixel covers `footprint`
// pixels of the scene. Reading the glyph at one point would hit or miss
// its thin strokes and come out as hard blobs, so it is read at four
// points across the pixel and averaged, as a picture shrunk properly is.
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
  float footprint; // scene px per pixel drawn: 1 at full size
  vec2 inset;     // half an atlas texel, as a fraction of a glyph
};
layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D field;

// The character at a point of the scene, premultiplied.
vec4 glyphAt(vec2 px) {
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 ci = floor(px / csz);
  vec4 s = texture(field, (ci + 0.5) / grid);
  if (s.a <= 0.0) return vec4(0.0);
  float lineG = s.a > 0.81 ? floor((s.a - 0.8) / 0.04 + 0.5) : 0.0;
  float total = lineG > 0.0 ? 0.0 : s.a / 0.8 * 1.4;

  float g, alpha;
  vec3 col = s.rgb;
  if (lineG > 0.0 && total < 0.32) {
    g = 10.0 + lineG; alpha = 0.85;
  } else {
    if (total < 0.04) return vec4(0.0);
    g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
    // The brightest cells are lit beyond their colour, as the studies'
    // second shade of every colour.
    if (total > 0.9) col = mix(col, vec3(1.0 - light), light > 0.5 ? 0.32 : 0.42);
    alpha = clamp(0.2 + total * 1.05, 0.08, 1.0);
  }

  // One atlas texel per pixel; never past half a texel from the glyph's
  // edge, where the filter would read the neighbouring glyph.
  vec2 local = clamp(fract(px / csz), inset, vec2(1.0) - inset);
  float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
  return vec4(col, 1.0) * ink * alpha;
}

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec4 c;
  if (footprint < 1.5) c = glyphAt(px);
  else {
    float q = footprint * 0.25;
    c = (glyphAt(px + vec2(-q, -q)) + glyphAt(px + vec2(q, -q))
       + glyphAt(px + vec2(-q, q)) + glyphAt(px + vec2(q, q))) * 0.25;
  }
  fragColor = c * qt_Opacity;
}
