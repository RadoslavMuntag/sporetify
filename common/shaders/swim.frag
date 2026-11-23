#version 440

// How an organism swims (D18), as the organism studies simulate it, kept
// on the GPU: a row of 36 texels that is its own input (a recursive
// ShaderEffectSource, see OrganismField), advanced by one step whenever
// the pool's clock moves. No script runs per frame.
//
//   texel 0      position (px), velocity (px/s)
//   texel 1      heading (0 points up), turning speed, wander target (px)
//   texel 2      time to the next target, targets so far, last time, id
//   texels 3-14  the tentacle chain: each segment's world angle
//   texels 15-32 a second, slower chain: oral arms, a comb jelly's tentacles
//   texel 33     home as it was at the last step
//
// The rules are the studies': every 14 to 30 s (or on reaching it) a new
// target somewhere around home; swimmers turn toward it no faster than
// 0.06 to 0.08 rad/s and push along their own axis (a medusa only while
// its bell contracts, then it coasts and sinks a little), drifters are
// pulled toward it, everything slows in the water. A chain's segments
// each ease toward the one before, and lean back against the way the body
// moves, so tentacles hang when it is still and stream behind a stroke.
// When the host moves home (another view, a track change, which it
// animates), the water carries the organism and its target along, so it
// keeps swimming about its home instead of being left behind.
// Each fragment works out the body's step itself (it is cheap) and keeps
// the texel it owns; a segment follows its neighbour as it was a step ago.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 home;      // px
  vec2 roam;      // how far targets lie from home, px each way
  vec2 pond;     // the pond's size, px
  float cell;     // px per world unit (a column; a row is two)
  float radius;   // R, px
  float time;     // s
  float phase;    // per-track id, 0..100
  float kindIndex;
  vec4 p0;        // the kind's parameters, as organism.frag reads them
  vec4 p1;
};
layout(binding = 1) uniform sampler2D swim;

const float N = 36.0;
const float TAU = 6.2831853;
const float PI = 3.1415927;

vec4 texel(float i) { return texture(swim, vec2((i + 0.5) / N, 0.5)); }
float hh(float a, float b) { return fract(sin(dot(vec3(phase, a, b), vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float angDiff(float a, float b) { float d = a - b; return d - TAU * floor((d + PI) / TAU); }
float wrap(float a) { return angDiff(a, 0.0); }

void main() {
  float idx = floor(qt_TexCoord0.x * N);
  vec4 s0 = texel(0.0), s1 = texel(1.0), s2 = texel(2.0);
  bool fresh = abs(s2.w - (phase + 1.0)) > 0.001;
  float dt = fresh ? 0.0 : clamp(time - s2.z, 0.0, 0.1);
  if (!fresh && dt <= 0.0) { fragColor = texel(idx); return; }

  float u = cell, Ru = radius / max(cell, 1.0);
  bool pennate = kindIndex > 3.5 && p0.x > 0.5;
  vec2 pos, vel, tgt;
  float a, va, tt, count;

  if (fresh) {
    pos = home + (vec2(hh(1.0, 1.0), hh(1.0, 2.0)) - 0.5) * roam * 0.6;
    vel = vec2(0.0);
    a = pennate ? PI * 0.5 + (hh(1.0, 3.0) - 0.5) * 0.8 : (hh(1.0, 3.0) - 0.5) * 0.5;
    va = 0.0; tgt = pos; tt = 0.0; count = 0.0;
  } else {
    vec2 carry = home - texel(33.0).xy;
    pos = s0.xy + carry; vel = s0.zw; a = s1.x; va = s1.y; tgt = s1.zw + carry; tt = s2.x; count = s2.y;
  }

  // ---- A new place to go, now and then.
  tt -= dt;
  vec2 dT = tgt - pos;
  if (tt <= 0.0 || dot(dT, dT) < radius * radius * 0.5) {
    count += 1.0;
    float m = radius * 1.4 + 3.0 * u;
    tgt = home + (vec2(hh(count, 4.0), hh(count, 5.0)) * 2.0 - 1.0) * roam;
    tgt = clamp(tgt, vec2(min(m, pond.x * 0.5), min(m, pond.y * 0.5)), max(pond - vec2(m), pond * 0.5));
    tt = 14.0 + hh(count, 6.0) * 16.0;
  }

  // ---- Moving, each kind its own way.
  vec2 fwd = vec2(sin(a), -cos(a));
  if (kindIndex < 1.5 && !fresh) {
    // Swimmers turn toward the target.
    float maxTurn = kindIndex < 0.5 ? 0.08 : 0.06;
    float want = atan(tgt.x - pos.x, -(tgt.y - pos.y));
    va += (clamp(angDiff(want, a), -1.0, 1.0) * maxTurn - va) * min(1.0, dt * 0.5);
    a = wrap(a + va * dt);
    fwd = vec2(sin(a), -cos(a));
  }
  if (kindIndex < 0.5) {
    // A stroke while the bell contracts, then coasting; sinking slowly.
    float ph = fract(time / p0.y + fract(phase * 0.37));
    float push = ph < 0.3 ? sin(ph / 0.3 * PI) : 0.0;
    vel += fwd * push * (0.05 * Ru + 0.5) * 3.0 * u * dt;
    vel.y += (0.004 * Ru + 0.03) * u * dt;
    vel *= exp(-dt * 0.55);
  } else if (kindIndex < 1.5) {
    // A steady glide.
    vel += fwd * (0.035 * Ru + 0.45) * u * dt * 0.6;
    vel *= exp(-dt * 0.6);
  } else if (kindIndex < 3.5 || !pennate) {
    // Drifters, and round diatoms: pulled gently toward the target.
    float d = max(length(tgt - pos), 1e-3);
    float k = kindIndex > 3.5 ? 0.08 * u : (0.012 * Ru + 0.15) * u * min(1.0, d / ((Ru + 4.0) * u));
    vel += (tgt - pos) / d * k * dt;
    vel *= exp(-dt * (kindIndex > 2.5 && kindIndex < 3.5 ? 0.45 : 0.4));
  } else {
    // A boat-shaped diatom glides along its axis, stops, glides back.
    float g = sin(fract(time / p1.w + phase) * TAU);
    vec2 want = fwd * (0.03 * Ru + 0.35) * u * (abs(g) > 0.25 ? g : 0.0);
    vel += (want - vel) * min(1.0, dt * 0.8);
    a = wrap(a + sin(time * 0.03 + phase) * 0.01 * dt);
  }

  // Kept in the pond and not too far from home: pushed back softly.
  float m = radius * 1.4 + 3.0 * u;
  vec2 lo = vec2(min(m, pond.x * 0.5), min(m, pond.y * 0.5)), hi = max(pond - vec2(m), pond * 0.5);
  vel += (max(lo - pos, 0.0) - max(pos - hi, 0.0)) * 0.03 * dt;
  vec2 off = (pos - home) / max(roam * 1.6, vec2(radius * 0.8));
  float e = length(off);
  if (e > 1.0) vel -= (pos - home) / e * (e - 1.0) * 0.2 * dt;
  pos += vel * dt;

  if (idx < 0.5) { fragColor = vec4(pos, vel); return; }
  if (idx < 1.5) { fragColor = vec4(a, va, tgt); return; }
  if (idx < 2.5) { fragColor = vec4(tt, count, time, phase + 1.0); return; }
  if (idx > 32.5) { fragColor = vec4(home, 0.0, 0.0); return; }

  // ---- Chains. Leaning back against the motion, by up to a half.
  float sp = length(vel) / u;
  // atan(0, 0) is undefined, and a NaN here would stay in the state for good.
  float back = sp > 0.0 ? atan(-vel.y, -vel.x) : 0.0;
  float bw = min(0.5, sp / (0.08 * Ru + 1.0) * 0.45);
  float down = a + PI * 0.5;
  bool slow = idx >= 14.5;
  float j = slow ? idx - 15.0 : idx - 3.0;
  if (j > (slow ? 17.0 : 11.0)) { fragColor = vec4(0.0); return; }
  float rate = slow ? 0.6 : 0.9;
  float lead = down;
  // Oral arms do not lean at the root; tentacles and comb tentacles do.
  if (!(slow && kindIndex < 0.5)) lead += angDiff(back, lead) * bw;
  // Each segment eases toward the one before it as that one is after this
  // step, as the studies walk their chains from the root: so this
  // fragment walks its chain from the root to itself. Using the one before
  // as it was a step ago instead held a turn back one step (1/15 s) per
  // segment, most of a second at a tentacle's tip.
  float first = slow ? 15.0 : 3.0;
  float prev = lead, ang = lead;
  for (int k = 0; k < 18; k++) {
    float fk = float(k);
    if (fk > j) break;
    float want = prev;
    if (bw > 0.0) want += angDiff(back, want) * bw * 0.25;
    if (fresh) ang = want;
    else {
      ang = texel(first + fk).x;
      ang += angDiff(want, ang) * min(1.0, dt * max(0.22, rate - fk * 0.04));
    }
    prev = ang;
  }
  fragColor = vec4(wrap(ang), 0.0, 0.0, 0.0);
}
