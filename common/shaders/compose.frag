#version 440

// The whole Living ASCII pool in one pass over the screen (D18). On an
// integrated GPU every full-screen pass costs a lot, and so does every
// texture read in it, so everything else is drawn small beforehand and
// read here once:
//
//   under    the water's colour, the far layer and the passer-by, put
//            together at a third of the size (shaders/underlay.frag)
//   near     the near layer's field, a texel per character cell; its
//            characters are drawn here, sharp, from `atlas`
//   glow     the near layer's characters at a quarter of the size, which
//            comes out soft when scaled up, added on top
//   and the vignette, worked out here.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px
  vec2 grid;      // columns, rows of the near field
  float cell;     // cell width, px; a cell is twice as tall
  float light;    // 1 on a light theme
  float glyphs;   // glyphs in the atlas
  float glowStrength;
  vec4 deep;
};
layout(binding = 1) uniform sampler2D under;
layout(binding = 2) uniform sampler2D near;
layout(binding = 3) uniform sampler2D atlas;
layout(binding = 4) uniform sampler2D glow;

// Premultiplied colour over colour.
vec3 over(vec3 base, vec4 top) { return base * (1.0 - top.a) + top.rgb; }

void main() {
  vec2 uv = qt_TexCoord0;
  vec2 px = uv * area;
  vec3 col = texture(under, uv).rgb;

  // The near layer's characters.
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 ci = floor(px / csz);
  vec4 s = texture(near, (ci + 0.5) / grid);
  if (s.a > 0.0) {
    float lineG = s.a > 0.81 ? floor((s.a - 0.8) / 0.04 + 0.5) : 0.0;
    float total = lineG > 0.0 ? 0.0 : s.a / 0.8 * 1.4;
    float g = 0.0, alpha = 0.0;
    vec3 c = s.rgb;
    if (lineG > 0.0) { g = 10.0 + lineG; alpha = 0.85; }
    else if (total >= 0.04) {
      g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
      if (total > 0.9) c = mix(c, vec3(1.0 - light), light > 0.5 ? 0.32 : 0.42);
      alpha = clamp(0.2 + total * 1.05, 0.08, 1.0);
    }
    if (g > 0.0) {
      vec2 local = mix(vec2(0.08, 0.04), vec2(0.92, 0.96), fract(px / csz));
      float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
      col = mix(col, c, ink * alpha);
    }
  }

  // Glow, added like a screen blend; on a light theme a slight darkening.
  if (glowStrength > 0.0) {
    vec4 g = texture(glow, uv);
    if (light > 0.5) col = over(col, g * glowStrength * 0.35);
    else col += g.rgb * glowStrength;
  }

  // The vignette: the edges sink into the deep.
  float d = length((uv - vec2(0.5, 0.45)) / vec2(1.2, 1.0));
  col = mix(col, deep.rgb, clamp((d - 0.55) / 0.45, 0.0, 1.0) * 0.72);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
