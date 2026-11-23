#version 440

// The whole Living ASCII pool in one pass over the screen (D18). On an
// integrated GPU every full-screen pass costs a lot, and so does every
// texture read in it, so everything else is drawn small beforehand and
// read here once:
//
//   under    the water's colour and the far layer, put together at a
//            third of the size (shaders/underlay.frag)
//   near     the near layer's field, a texel per character cell; its
//            characters are drawn here, sharp, from `atlas`
//   glow     the near layer's characters at a quarter of the size, which
//            comes out soft when scaled up, added on top
//   passer   one large organism in front of everything, very out of
//            focus, at an eighth of the size, as the studies lay theirs
//            over the sharp layer and its glow
//   the clearing around text on the water and the vignette, worked out here.

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
  vec2 inset;     // half an atlas texel, as a fraction of a glyph
  vec4 calm0;     // up to three places text sits on the water: x, y, w, h px
  vec4 calm1;
  vec4 calm2;
  vec4 region;    // the open water, px: the vignette is laid out over it
  float passerAlpha; // 0 when there is no passer-by
};
layout(binding = 1) uniform sampler2D under;
layout(binding = 2) uniform sampler2D near;
layout(binding = 3) uniform sampler2D atlas;
layout(binding = 4) uniform sampler2D glow;
layout(binding = 5) uniform sampler2D passer;

// Premultiplied colour over colour.
vec3 over(vec3 base, vec4 top) { return base * (1.0 - top.a) + top.rgb; }

// How clear of characters the water is around one place for text: 1 over
// the text and a cell beside it, falling to 0 over the next three cells.
// Nothing is darkened; the characters (and their glow) just make room.
float calm(vec2 px, vec4 r) {
  if (r.z <= 0.0) return 0.0;
  vec2 half_ = r.zw * 0.5;
  vec2 q = abs(px - (r.xy + half_)) - half_ - vec2(cell, cell * 0.5);
  return 1.0 - smoothstep(0.0, cell * 3.0, length(max(q, vec2(0.0))));
}
float calmAll(vec2 px) { return max(calm(px, calm0), max(calm(px, calm1), calm(px, calm2))); }

// A hash without sine (cheap enough to run for every pixel).
float hash2(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

void main() {
  vec2 uv = qt_TexCoord0;
  vec2 px = uv * area;
  vec3 col = texture(under, uv).rgb;

  // The near layer's characters.
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 ci = floor(px / csz);
  vec4 s = texture(near, (ci + 0.5) / grid);
  // Around text on the water the near layer's characters make room: a
  // cell is left out when its clearing beats its own random threshold, so
  // the edge is ragged, a cell at a time, and the text stands on open
  // water instead of a shadow.
  float cleared = calmAll((ci + 0.5) * csz);
  if (s.a > 0.0 && cleared < 0.02 + 0.97 * hash2(ci + 41.0)) {
    float lineG = s.a > 0.81 ? floor((s.a - 0.8) / 0.04 + 0.5) : 0.0;
    float total = lineG > 0.0 ? 0.0 : s.a / 0.8 * 1.4;
    float g = 0.0, alpha = 0.0;
    vec3 c = s.rgb;
    if (lineG > 0.0) { g = 10.0 + lineG; alpha = 0.85; }
    else if (total >= 0.04) {
      g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
      // A little stronger than the studies' so the near layer stands out
      // from the blurred water behind it.
      if (total > 0.85) c = mix(c, vec3(1.0 - light), light > 0.5 ? 0.32 : 0.42);
      alpha = clamp(0.26 + total * 1.15, 0.1, 1.0);
    }
    if (g > 0.0) {
      vec2 local = clamp(fract(px / csz), inset, vec2(1.0) - inset);
      float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
      col = mix(col, c, ink * alpha);
    }
  }

  // Glow, blended as the studies blend theirs: screen on a dark theme
  // (light only adds, never past white), multiply on a light one at a
  // fifth of the strength (light glowing would wash out).
  // The clearing, pixel by pixel, for what is not drawn in cells.
  float open = calmAll(px);
  if (glowStrength > 0.0) {
    vec4 g = texture(glow, uv) * (1.0 - open);
    if (light > 0.5) {
      float k = glowStrength * 0.38;
      col *= vec3(1.0) - k * (vec3(g.a) - g.rgb);
    } else {
      col = vec3(1.0) - (vec3(1.0) - col) * (vec3(1.0) - g.rgb * glowStrength);
    }
  }

  // The passer-by, in front.
  if (passerAlpha > 0.0) col = over(col, texture(passer, uv) * passerAlpha);

  // The vignette: the edges of the open water sink into the deep.
  vec2 ru = (px - region.xy) / max(region.zw, vec2(1.0));
  float d = length((ru - vec2(0.5, 0.45)) / vec2(1.2, 1.0));
  col = mix(col, deep.rgb, clamp((d - 0.55) / 0.45, 0.0, 1.0) * 0.72);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
