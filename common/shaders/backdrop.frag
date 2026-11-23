#version 440

// The water's colour, as the organism studies paint it (D18): lit from
// above (the accent mixed into the background at the top, the background
// in the middle, the deep at the bottom), with three large discs of
// palette colour drifting slowly, blurred soft, each faint, so the water
// is full of colour without being bright.
//
// It is laid out over `region`, the open water, not the whole scene: in
// the app the bar's glass covers the bottom of the window, and laid out
// over the window the water's darkest part would sit under the glass and
// the open water would never get dark.
//
// Soft everywhere, so the host draws it small and lets it scale up.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px of the scene
  vec4 region;    // the open water in the scene: x, y, width, height, px
  float time;
  float blur;     // 0 crisp, 1 balanced, 1.9 dreamy
  vec4 ground;    // background
  vec4 deep;      // darkest background
  vec4 accent;
  vec4 c0;        // three palette colours for the discs
  vec4 c1;
  vec4 c2;
};

const float PI = 3.1415927;

// The discs' size: 46% of the width, as in the studies. A scene taller
// than the studies' 16:10 pools is sized as one of those would be for its
// height, so the middle is not left dark; sizing every scene as their
// 21:9 hero made the discs so large that a 3:2 window was lit all over
// and lost the dark water between them (measured 2026-11-22).
float discSize() { return 0.46 * max(region.z, region.w * 1.6); }

// One drifting disc: its box is discSize() square, placed as in the
// studies, moving from (-5%, -3%) to (7%, 6%) of its size and growing 15%,
// back and forth over `dur` seconds.
float disc(vec2 px, vec2 corner, float dur, float phase) {
  float s = discSize();
  float k = 0.5 - 0.5 * cos(PI * (time / dur + phase));
  vec2 shift = mix(vec2(-0.05, -0.03), vec2(0.07, 0.06), k) * s;
  float r = s * 0.5 * mix(1.0, 1.15, k);
  float d = length(px - (corner + vec2(s * 0.5) + shift));
  // The studies blur each disc with CSS blur(14 to 40 px) on a disc about
  // 600 px across: a Gaussian, so the edge fades over a fifth of the disc
  // and no edge is ever seen. A smoothstep over the same width left a
  // visible rim; this is the Gaussian's own fade (the logistic curve is
  // within a percent of it), scaled to the disc.
  float sigma = s * (0.023 + blur * 0.043) + 2.0;
  return 1.0 / (1.0 + exp(1.702 * (d - r) / sigma));
}

void main() {
  vec2 px = qt_TexCoord0 * area - region.xy;
  vec2 uv = px / max(region.zw, vec2(1.0));
  float d = length((uv - vec2(0.5, -0.1)) / vec2(1.1, 0.85));
  vec3 top = mix(ground.rgb, accent.rgb, 0.22);
  vec3 col = d < 0.5 ? mix(top, ground.rgb, d / 0.5) : mix(ground.rgb, deep.rgb, clamp((d - 0.5) / 0.5, 0.0, 1.0));
  float W = region.z, H = region.w, s = discSize(), o = 0.07 + blur * 0.09;
  col = mix(col, c0.rgb, disc(px, vec2(-0.08 * W, 0.22 * H), 48.0, 0.0) * o);
  col = mix(col, c1.rgb, disc(px, vec2(W + 0.10 * W - s, -0.14 * H), 59.0, 1.0) * o);
  col = mix(col, c2.rgb, disc(px, vec2(0.38 * W, H + 0.32 * H - s), 67.0, 0.0) * o);
  fragColor = vec4(col, 1.0) * qt_Opacity;
}
