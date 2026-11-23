#version 440

// A pane of glass over the water (D18): the water behind it, taken from a
// small, blurred copy of the whole scene (`surface`), its
// colour lifted (saturate 150%), under a tint, with rounded corners, a
// hairline edge and a highlight along the top. One small copy serves every
// pane, so the water is never drawn again for the glass.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 extent;    // the pane, px
  vec4 pane;      // the pane in the scene: x, y, width, height, px
  vec2 scene;     // the scene, px
  float radius;
  float blur;     // 0 crisp, 1 balanced, 1.9 dreamy
  float sampling; // 1 when there is water to show
  float strength; // how much tint covers the water
  vec4 tint;
  vec4 edge;
  vec2 texels;    // the surface's size in texels
};
layout(binding = 1) uniform sampler2D surface;

// The surface comes already blurred, and small: read straight, its texels
// would show as soft squares six pixels wide. A cubic B-spline across
// them is smooth everywhere, in four reads (each between texels, so the
// linear filter does part of the weighing).
vec4 smoothRead(vec2 uv) {
  vec2 size = max(texels, vec2(1.0));
  vec2 p = uv * size - 0.5;
  vec2 i = floor(p), f = p - i;
  vec2 f2 = f * f, f3 = f2 * f;
  vec2 w0 = (-f3 + 3.0 * f2 - 3.0 * f + 1.0) / 6.0;
  vec2 w1 = (3.0 * f3 - 6.0 * f2 + 4.0) / 6.0;
  vec2 w2 = (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) / 6.0;
  vec2 w3 = f3 / 6.0;
  vec2 g0 = w0 + w1, g1 = w2 + w3;
  vec2 h0 = (i - 0.5 + w1 / g0) / size;
  vec2 h1 = (i + 1.5 + w3 / g1) / size;
  return g0.y * (g0.x * texture(surface, h0) + g1.x * texture(surface, vec2(h1.x, h0.y)))
       + g1.y * (g0.x * texture(surface, vec2(h0.x, h1.y)) + g1.x * texture(surface, h1));
}

void main() {
  vec2 px = qt_TexCoord0 * extent;
  vec3 col = tint.rgb;
  float cover = 0.9;
  if (sampling > 0.5) {
    vec3 water = smoothRead((pane.xy + px) / scene).rgb;
    float lum = dot(water, vec3(0.3, 0.59, 0.11));
    water = clamp(mix(vec3(lum), water, 1.5), 0.0, 1.0);
    col = mix(water, tint.rgb, strength);
    cover = 1.0;
  }
  // Rounded corners, with a pixel of softness.
  vec2 q = abs(px - extent * 0.5) - (extent * 0.5 - vec2(radius));
  float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
  float inside = clamp(0.5 - dist, 0.0, 1.0);
  if (inside <= 0.0) discard;
  // The edge, and light catching the top.
  float rim = clamp(1.0 - abs(dist + 0.5), 0.0, 1.0);
  col = mix(col, edge.rgb, rim * 0.13);
  if (sampling > 0.5 && px.y > 0.5 && px.y < 1.5 && px.x > radius && px.x < extent.x - radius) col = mix(col, edge.rgb, 0.08);
  fragColor = vec4(col, 1.0) * cover * inside * qt_Opacity;
}
