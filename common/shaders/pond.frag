#version 440

// The water's own light, as a field over the character grid like
// shaders/organism.frag: one fragment per cell, the same output code (rgb
// the colour, alpha the brightness scaled into 0..0.8), turned into
// characters by shaders/glyphs.frag.
//
//   part 1, the far layer: light rippling through the water, as in the
//           organism studies, brightest near the surface.
//   part 2, the near layer: marine snow sinking and swaying, and, if asked
//           for, plankton specks, rising bubbles and weeds on the bottom.
//
// World units as in the studies: one column wide, a row two tall.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 grid;      // columns, rows
  float time;
  float part;
  float snow;     // flakes of marine snow, up to 60
  float specks;   // coloured plankton specks, up to 40
  float bubbles;  // up to 12
  float weeds;    // up to 12
  float seed;
  vec4 ink;       // foreground
  vec4 accent;
  vec4 muted;
  vec4 tint;      // a palette colour for specks
  vec4 weedA;
  vec4 weedB;
};

const float PI = 3.1415927;

float total;
float best;
vec3 colour;

void add(float v, vec3 c) {
  if (v <= 0.0) return;
  total += v;
  if (v > best) { best = v; colour = c; }
}

float hash1(float n) { return fract(sin(n * 12.9898 + seed * 0.7311 + 4.1414) * 43758.5453); }

void main() {
  vec2 ci = floor(qt_TexCoord0 * grid);
  float x = ci.x, y = ci.y, W = grid.x, H = grid.y * 2.0;
  total = 0.0; best = 0.0; colour = ink.rgb;

  if (part < 1.5) {
    // ---- Ripples of light, as the studies draw them.
    float py = y * 2.0, dep = 1.0 - y / grid.y * 0.75;
    float s1 = 1.7 * sin(py * 0.09 - time * 0.05), c2 = py * 0.16 + time * 0.07;
    float v = sin(x * 0.11 + time * 0.08 + s1) + sin(c2 + 1.3 * sin(x * 0.07 + time * 0.045));
    float e = abs(v - 0.95);
    if (e < 0.09) add(0.13 * dep, accent.rgb);
    else if (v < -1.93) add(0.07 * dep, muted.rgb);
  } else {
    // ---- Marine snow: sinking slowly, swaying a little.
    for (int i = 0; i < 60; i++) {
      float fi = float(i);
      if (fi >= snow) break;
      float vy = 0.25 + hash1(fi * 1.3 + 1.0) * 0.55, ph = hash1(fi * 2.7 + 2.0) * 6.283;
      float fy = mod(hash1(fi * 3.1 + 3.0) * (H + 2.0) + vy * time, H + 2.0) - 1.0;
      float fx = mod(hash1(fi * 4.3 + 4.0) * W + sin(time * 0.15 + ph) * 1.67, W);
      if (floor(fx) == x && floor(fy * 0.5) == y) add(0.1 + hash1(fi * 5.9 + 5.0) * 0.2, ink.rgb);
    }
    // ---- Coloured plankton specks drifting down and across.
    for (int i = 0; i < 40; i++) {
      float fi = float(i);
      if (fi >= specks) break;
      float ph = hash1(fi * 1.7 + 5.0) * 6.283;
      float vx = (hash1(fi * 2.9 + 6.0) - 0.5) * 0.6, vy = 0.08 + hash1(fi * 3.3 + 7.0) * 0.3;
      float fx = mod(hash1(fi * 4.1 + 8.0) * (W + 2.0) + vx * time + sin(time * 0.2 + ph) * 1.75, W + 2.0) - 1.0;
      float fy = mod(hash1(fi * 6.7 + 9.0) * (H + 2.0) + vy * time + sin(time * 0.17 + ph * 1.3) * 1.5, H + 2.0) - 1.0;
      if (floor(fx) == x && floor(fy * 0.5) == y) add(0.3 + hash1(fi * 9.9) * 0.4, hash1(fi * 8.3) < 0.5 ? accent.rgb : tint.rgb);
    }
    // ---- Bubbles rising.
    for (int i = 0; i < 12; i++) {
      float fi = float(i);
      if (fi >= bubbles) break;
      float speed = 1.3 + hash1(fi * 3.1 + 11.0) * 1.6;
      float fy = H + 2.0 - mod(hash1(fi * 5.3 + 12.0) * (H + 4.0) + time * speed, H + 4.0);
      float fx = hash1(fi * 7.9 + 13.0) * W + sin(time * (0.5 + hash1(fi) * 0.6) + fi) * 0.9;
      if (floor(fx) == x && floor(fy * 0.5) == y) add(0.35, ink.rgb);
    }
    // ---- Weeds, rooted on the bottom row, swaying.
    float fromBottom = grid.y - 1.0 - y;
    for (int i = 0; i < 12; i++) {
      float fi = float(i);
      if (fi >= weeds) break;
      float h = 3.0 + floor(hash1(fi * 3.7 + 1.0) * 8.0);
      if (fromBottom < 0.0 || fromBottom >= h) continue;
      float x0 = floor(hash1(fi * 5.1 + 2.0) * W), ph = hash1(fi * 2.3 + 3.0) * 6.283;
      float cx = floor(x0 + sin(time * 0.3 + fromBottom * 0.3 + ph) * fromBottom * 0.16 + 0.5);
      if (abs(x - cx) < 0.5) add(0.6 - 0.35 * fromBottom / h, hash1(fi * 1.3) < 0.5 ? weedA.rgb : weedB.rgb);
    }
  }

  fragColor = total >= 0.04 ? vec4(colour, min(total, 1.4) / 1.4 * 0.8) : vec4(0.0);
}
