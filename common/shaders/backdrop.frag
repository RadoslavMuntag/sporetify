#version 440

// The water's colour, as the organism studies paint it (D18).
//
//   part 0: lit from above (the accent mixed into the background at the top,
//           the background in the middle, the deep at the bottom), with
//           three large discs of palette colour drifting slowly, blurred
//           soft, each faint, so the water is full of colour without
//           being bright.
//   part 1: the vignette over everything: the edges sink into the deep.
//
// Soft everywhere, so the host draws it small and lets it scale up.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 area;      // px of the scene
  float time;
  float blur;     // 0 crisp, 1 balanced, 1.9 dreamy
  float part;
  vec4 ground;    // background
  vec4 deep;      // darkest background
  vec4 accent;
  vec4 c0;        // three palette colours for the discs
  vec4 c1;
  vec4 c2;
};

const float PI = 3.1415927;

// One drifting disc: its box is 46% of the width square, placed as in the
// studies, moving from (-5%, -3%) to (7%, 6%) of its size and growing 15%,
// back and forth over `dur` seconds.
float disc(vec2 px, vec2 corner, float dur, float phase) {
  float W = area.x, s = W * 0.46;
  float k = 0.5 - 0.5 * cos(PI * (time / dur + phase));
  vec2 shift = mix(vec2(-0.05, -0.03), vec2(0.07, 0.06), k) * s;
  float r = s * 0.5 * mix(1.0, 1.15, k);
  float d = length(px - (corner + vec2(s * 0.5) + shift));
  float soft = 14.0 + blur * 26.0;
  return 1.0 - smoothstep(r - soft, r + soft, d);
}

void main() {
  vec2 uv = qt_TexCoord0;
  vec2 px = uv * area;
  if (part > 0.5) {
    float d = length((uv - vec2(0.5, 0.45)) / vec2(1.2, 1.0));
    float a = clamp((d - 0.55) / 0.45, 0.0, 1.0) * 0.72;
    fragColor = vec4(deep.rgb, 1.0) * a * qt_Opacity;
    return;
  }
  float d = length((uv - vec2(0.5, -0.1)) / vec2(1.1, 0.85));
  vec3 top = mix(ground.rgb, accent.rgb, 0.22);
  vec3 col = d < 0.5 ? mix(top, ground.rgb, d / 0.5) : mix(ground.rgb, deep.rgb, clamp((d - 0.5) / 0.5, 0.0, 1.0));
  float W = area.x, H = area.y, s = W * 0.46, o = 0.07 + blur * 0.09;
  col = mix(col, c0.rgb, disc(px, vec2(-0.08 * W, 0.22 * H), 48.0, 0.0) * o);
  col = mix(col, c1.rgb, disc(px, vec2(W + 0.10 * W - s, -0.14 * H), 59.0, 1.0) * o);
  col = mix(col, c2.rgb, disc(px, vec2(0.38 * W, H + 0.32 * H - s), 67.0, 0.0) * o);
  fragColor = vec4(col, 1.0) * qt_Opacity;
}
