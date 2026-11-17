#version 440

// The water of the Living ASCII look (decision D18): a soft colour field
// with light rippling across it, drifting plankton specks, rising bubbles
// and weeds swaying at the bottom, all drawn as characters from `atlas`.
// The organisms are drawn over it by Plankton.qml.
//
// Everything that moves is a function of `time`, so the host animates one
// number, and only while the scene is alive. `blur` (0 crisp, 1 balanced,
// 1.9 dreamy) softens the far layer by sampling smaller mip levels.
//
// Atlas glyphs: " .·,'-~+*oO°|/\()"

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px
  float cell;     // cell width, px; a cell is twice as tall
  float time;
  float blur;
  float light;
  float glyphs;
  float specks;   // drifting plankton specks, up to 40
  float bubbles;  // rising bubbles, up to 12
  float weeds;    // weeds along the bottom, up to 12
  float seed;
  vec4 ground;    // the theme's background
  vec4 deep;      // its darkest background
  vec4 accent;
  vec4 ink;       // foreground
  vec4 muted;
  vec4 tint0;     // three palette colours for the drifting light
  vec4 tint1;
  vec4 tint2;
  vec4 weedA;
  vec4 weedB;
};
layout(binding = 1) uniform sampler2D atlas;

const float PI = 3.1415927;
const float G_DOT = 1.0, G_MID = 2.0, G_COMMA = 3.0, G_APOS = 4.0, G_DASH = 5.0, G_TILDE = 6.0;
const float G_PLUS = 7.0, G_STAR = 8.0, G_o = 9.0, G_O = 10.0, G_DEG = 11.0, G_BAR = 12.0;
const float G_FS = 13.0, G_BS = 14.0, G_LP = 15.0, G_RP = 16.0;

float hash1(float n) { return fract(sin(n * 12.9898 + seed * 0.7311 + 4.1414) * 43758.5453); }

// The glyph `g` at this pixel, softened by `soft` mip levels.
float glyph(float g, vec2 local, float soft) {
  return texture(atlas, vec2((g + local.x) / glyphs, local.y), soft).a;
}

vec3 over(vec3 base, vec3 c, float a) { return mix(base, c, clamp(a, 0.0, 1.0)); }

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 csz = vec2(cell, cell * 2.0);
  vec2 ci = floor(px / csz);
  vec2 local = fract(px / csz);
  vec2 grid = floor(area / csz);
  // World units, as the mockup: one column wide, a row two tall.
  vec2 w = vec2(ci.x, ci.y * 2.0);
  vec2 uv = px / area;

  // ---- The colour field: lit from above, deepest at the bottom.
  vec2 g = (uv - vec2(0.5, -0.1)) / vec2(1.1, 0.85);
  float d = length(g);
  vec3 top = mix(ground.rgb, accent.rgb, 0.22);
  vec3 col = d < 0.52 ? mix(top, ground.rgb, d / 0.52) : mix(ground.rgb, deep.rgb, clamp((d - 0.52) / 0.48, 0.0, 1.0));

  // Three large soft lights drifting slowly.
  float aspect = area.x / area.y;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    vec2 c = vec2(fi == 0.0 ? -0.04 : fi == 1.0 ? 0.87 : 0.61, fi == 0.0 ? 0.45 : fi == 1.0 ? 0.09 : 1.09);
    float per = 38.0 + fi * 9.0;
    float s = sin(time / per * PI + fi * 1.7);
    c += vec2(0.075, 0.055) * s;
    float r = 0.23 * (1.0 + 0.08 * (s + 1.0));
    vec2 q = (uv - c) * vec2(aspect, 1.0) / max(aspect, 1.0);
    float k = exp(-dot(q, q) / (r * r) * 1.6);
    vec4 t = fi == 0.0 ? tint0 : fi == 1.0 ? tint1 : tint2;
    col = over(col, t.rgb, k * (0.07 + blur * 0.09));
  }

  float depth = 1.0 - ci.y / max(1.0, grid.y) * 0.75;
  float farSoft = blur * 1.3;

  // ---- Light rippling across the far layer.
  float py = w.y;
  float s1 = 1.7 * sin(py * 0.09 - time * 0.06);
  float c2 = py * 0.16 + time * 0.08;
  float v = sin(w.x * 0.11 + time * 0.09 + s1) + sin(c2 + 1.3 * sin(w.x * 0.07 + time * 0.05));
  float e = abs(v - 0.95);
  if (e < 0.1) col = over(col, accent.rgb, glyph(e < 0.04 ? G_TILDE : G_DASH, local, farSoft) * 0.5 * depth * 0.9);
  else if (v > 1.9) col = over(col, mix(accent.rgb, vec3(1.0 - light), 0.4), glyph(G_PLUS, local, farSoft) * 0.8 * depth * 0.9);
  else if (v < -1.92) col = over(col, muted.rgb, glyph(G_DOT, local, farSoft) * 0.6 * depth * 0.9);

  // ---- Weeds, rooted on the bottom row; far ones soft, near ones sharp.
  float fromBottom = grid.y - 1.0 - ci.y;
  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    if (fi >= weeds) break;
    float h = 3.0 + floor(hash1(fi * 3.7 + 1.0) * 8.0);
    if (fromBottom < 0.0 || fromBottom >= h) continue;
    float x0 = floor(hash1(fi * 5.1 + 2.0) * grid.x);
    float ph = hash1(fi * 2.3 + 3.0) * 6.283;
    float k = fromBottom;
    float cx = floor(x0 + sin(time * 0.3 + k * 0.3 + ph) * k * 0.16 + 0.5);
    if (abs(ci.x - cx) > 0.5) continue;
    float prev = k > 0.0 ? floor(x0 + sin(time * 0.3 + (k - 1.0) * 0.3 + ph) * (k - 1.0) * 0.16 + 0.5) : cx;
    bool tip = k == h - 1.0 && hash1(fi * 7.3) < 0.65;
    float sym = tip ? G_STAR : cx > prev ? G_FS : cx < prev ? G_BS : mod(k, 3.0) < 0.5 ? G_RP : mod(k, 3.0) < 1.5 ? G_LP : G_BAR;
    bool far = hash1(fi * 9.1 + 4.0) < 0.45;
    vec3 wc = tip ? accent.rgb : hash1(fi * 1.3) < 0.5 ? weedA.rgb : weedB.rgb;
    col = over(col, wc, glyph(sym, local, far ? farSoft : 0.0) * (0.9 - 0.45 * k / h) * (far ? 0.7 : 1.0));
  }

  // ---- Plankton specks drifting down and across.
  for (int i = 0; i < 40; i++) {
    float fi = float(i);
    if (fi >= specks) break;
    float ph = hash1(fi * 1.7 + 5.0) * 6.283;
    float vx = (hash1(fi * 2.9 + 6.0) - 0.5) * 0.6;
    float vy = 0.08 + hash1(fi * 3.3 + 7.0) * 0.3;
    float W = grid.x + 2.0, H = grid.y * 2.0 + 2.0;
    float x = mod(hash1(fi * 4.1 + 8.0) * W + vx * time + sin(time * 0.2 + ph) * 1.75, W) - 1.0;
    float y = mod(hash1(fi * 6.7 + 9.0) * H + vy * time + sin(time * 0.17 + ph * 1.3) * 1.5, H) - 1.0;
    if (floor(x) != ci.x || floor(y / 2.0) != ci.y) continue;
    float pick = hash1(fi * 8.3 + 10.0);
    bool twinkle = mod(time * 0.4 + ph, 6.0) < 0.5;
    float sym = twinkle ? G_STAR : pick < 0.4 ? G_DOT : pick < 0.6 ? G_COMMA : pick < 0.8 ? G_APOS : G_MID;
    vec3 pc = pick < 0.5 ? accent.rgb : tint0.rgb;
    col = over(col, pc, glyph(sym, local, 0.0) * (0.45 + hash1(fi * 9.9) * 0.5));
  }

  // ---- Bubbles rising slowly.
  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    if (fi >= bubbles) break;
    float speed = 1.3 + hash1(fi * 3.1 + 11.0) * 1.6;
    float H = grid.y * 2.0 + 4.0;
    float y = H - mod(hash1(fi * 5.3 + 12.0) * H + time * speed, H) - 2.0;
    float x = hash1(fi * 7.9 + 13.0) * grid.x + sin(time * (0.5 + hash1(fi) * 0.6) + fi) * (0.6 + hash1(fi * 2.0) * 0.6);
    if (floor(x) != ci.x || floor(y / 2.0) != ci.y) continue;
    float sz = hash1(fi * 4.4 + 14.0);
    col = over(col, ink.rgb, glyph(sz < 0.45 ? G_DOT : sz < 0.85 ? G_o : G_O, local, 0.0) * 0.55);
  }

  // ---- Vignette: the edges sink into the deep.
  vec2 vq = (uv - vec2(0.5, 0.45)) / vec2(1.2, 1.0);
  float vd = length(vq) * 2.0;
  col = over(col, deep.rgb, smoothstep(0.55, 1.0, vd) * 0.72);

  fragColor = vec4(col, 1.0) * qt_Opacity;
}
