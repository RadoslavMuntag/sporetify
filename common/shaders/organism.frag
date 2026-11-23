#version 440

// One plankton organism as a field of light over the character grid (the
// "organism studies", decisions D17 and D18). This runs once per character
// cell, not per pixel: the item covers the box the organism can reach,
// inside a FieldLayer that renders a whole layer one texel per cell, and
// shaders/glyphs.frag turns the cells into characters. So the organism can
// be drawn in detail for the cost of a few thousand fragments. Cells it
// does not light are left alone (discarded), so the water and other
// organisms under its box show.
//
// It swims as the studies' organisms do: shaders/swim.frag simulates it
// (wander targets, turning, strokes and coasting, drag) and keeps its
// position, heading and tentacle chains in a small texture, `swim`, read
// here. Medusae push in strokes and coast, comb jellies glide, radiolarians
// and volvox drift, diatoms glide back and forth; tentacles hang when it
// is still and stream behind a stroke or a turn.
// With `wander` off it stays near `home` and only sways (a lens).
//
// Output, per cell: rgb the colour of the brightest part; alpha a code.
// Up to 0.8 it is the brightness (0..1.4 scaled into 0..0.8); above 0.8 a
// line glyph for glass spines (0.84 -, 0.88 |, 0.92 /, 0.96 \, 1.0 °).
//
// Parameters by kind (lengths in units of the organism's radius R):
//   0 medusa      p0 bell, beat period, tentacles, tentacle length
//                 p1 oral arms, arm length, canals, gonads
//                 p2 tilt, turn
//   1 comb jelly  p0 round, width, egg, plates per row
//                 p1 light speed, tentacle length, spin
//   2 radiolarian p0 shells, threads, thread length, capsule
//                 p1 spines, long spines, every, spin
//                 p2..p4 shells: radius, pores, rings
//   3 volvox      p0 cells, tilt, spin, daughters
//                 p1..p4 daughters: x, y, z, radius
//   4 diatom      p0 pennate, width, tip, striae
//                 p1 rings, rays, oil drops, glide period
//                 p2, p3 oil drops: x, y, x, y

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 origin;    // where this box starts in the layer, px (on a cell corner)
  vec2 box;       // its size, px (whole cells)
  vec2 home;      // px
  vec2 roam;      // px each way around home
  vec2 clipAt;    // centre of a circle to draw inside, px
  float bound;    // its radius, px; 0 for no limit
  float cell;     // cell width, px
  float radius;   // R, px
  float wanderOn; // 1 swims about, 0 stays near home
  float amp;      // brightness, 0..1
  float time;
  float phase;    // per-track, 0..100
  float kindIndex;
  vec4 p0;
  vec4 p1;
  vec4 p2;
  vec4 p3;
  vec4 p4;
  vec4 p5;
  vec4 bodyColour;
  vec4 markColour;
  vec4 glass;     // the theme's foreground
  vec4 accentColour;
  vec4 rain0;
  vec4 rain1;
  vec4 rain2;
  vec4 rain3;
  vec4 rain4;
};
layout(binding = 1) uniform sampler2D swim;   // shaders/swim.frag's state

const float TAU = 6.2831853;
const float PI = 3.1415927;

// What lights the cell: the sum, and the colour of the brightest part.
float total;
float best;
vec4 colour;
// A glass line glyph (code 1..5), shown where nothing brighter is.
float lineG;
float lineA;

vec2 C;    // cell centre, in R from the organism's position, world axes (y down)
float K;   // cell width in R; a cell is K wide and 2K tall
float A;   // heading: 0 points up

void add(float v, vec4 c) {
  if (v <= 0.0) return;
  total += v;
  if (v > best) { best = v; colour = c; }
}

// A point lights only the cell it falls in.
void at(vec2 p, float v, vec4 c) {
  vec2 d = abs(p - C);
  if (d.x <= K * 0.5 && d.y <= K) add(v, c);
}

// A soft dot of radius r.
void dot2(vec2 p, float r, float v, vec4 c) {
  if (r < K * 0.8) { at(p, v, c); return; }
  vec2 d = C - p;
  float q = 1.0 - dot(d, d) / (r * r);
  if (q > 0.0) add(v * q, c);
}

float segDist(vec2 a, vec2 b) {
  vec2 ab = b - a, ap = C - a;
  float h = clamp(dot(ap, ab) / max(1e-6, dot(ab, ab)), 0.0, 1.0);
  vec2 d = ap - ab * h;
  // Measured in cells, rows count double.
  return length(vec2(d.x, d.y * 0.5));
}

// A thread one cell wide.
void thread(vec2 a, vec2 b, float v, vec4 c) {
  if (segDist(a, b) < K * 0.5) add(v, c);
}

void glassLine(vec2 a, vec2 b, float alpha) {
  float d = segDist(a, b);
  if (d >= K * 0.5 || alpha < lineA) return;
  vec2 dir = b - a;
  float ax = abs(dir.x), ay = abs(dir.y) * 0.5;
  float g = ay < ax * 0.45 ? 1.0 : ax < ay * 0.45 ? 2.0 : dir.x * dir.y < 0.0 ? 3.0 : 4.0;
  if (length(C - b) < K) g = 5.0;
  lineG = g; lineA = alpha;
}

vec2 rot(vec2 p, float a) {
  float c = cos(a), s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}
// World to body: the inverse of rot.
vec2 toBody(vec2 p, float a) { return rot(p, -a); }

float hash1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float ease(float x) { return x * x * (3.0 - 2.0 * x); }

// ------------------------------------------------------------ motion
// Swimming is simulated, as in the studies, by shaders/swim.frag: each
// organism keeps its own state (OrganismField), read here as `swim`. Kept
// still (a lens: wanderOn 0) it only sways about home, worked out from
// `time`, its tentacles hanging.

float period() { return kindIndex < 0.5 ? p0.y : 5.0; }
// Where in its beat a medusa is: 0..1, contraction in the first 0.3.
float beatAt(float t) { return fract(t / period() + fract(phase * 0.37)); }

bool swims() { return wanderOn > 0.5; }
vec4 swimAt(float i) { return texture(swim, vec2((i + 0.5) / 36.0, 0.5)); }

vec2 swayAt(float t) { return home + radius * vec2(sin(t * 0.07 + phase) * 0.06, sin(t * 0.09 + phase * 2.0) * 0.07); }
float swayHeading(float t) {
  if (kindIndex < 0.5) return sin(t * 0.05 + phase) * 0.12;
  if (kindIndex < 1.5) return sin(t * 0.04 + phase) * 0.25;
  if (kindIndex > 3.5 && p0.x > 0.5) return PI * 0.5 + sin(t * 0.03 + phase) * 0.15;
  return 0.0;
}

// The chains' segments as world directions: `fastChain` the tentacles
// (12 segments), `slowChain` oral arms and comb jelly tentacles (18). Each
// segment eases toward the one before it in swim.frag, so a stroke or a
// turn travels down them; kept still they hang straight down.
vec2 fastChain[12];
vec2 slowChain[18];
void loadChains(bool fast, bool slow) {
  vec2 down = rot(vec2(0.0, 1.0), A);
  bool live = swims();
  if (fast) for (int j = 0; j < 12; j++) {
    float g = swimAt(3.0 + float(j)).x;
    fastChain[j] = live ? vec2(cos(g), sin(g)) : down;
  }
  if (slow) for (int j = 0; j < 18; j++) {
    float g = swimAt(15.0 + float(j)).x;
    slowChain[j] = live ? vec2(cos(g), sin(g)) : down;
  }
}

// ------------------------------------------------------------ medusa
void medusa() {
  float bell = p0.x, per = p0.y, tentacles = p0.z, tLen = p0.w;
  float arms = p1.x, armLen = p1.y, canals = p1.z, gonads = p1.w;
  float tilt = p2.x, turn = p2.y;

  // A contraction of about 1.5 s, then a long slow relax.
  float ph = beatAt(time);
  float c = ph < 0.3 ? ease(ph / 0.3) : 1.0 - ease((ph - 0.3) / 0.7);
  float H = bell * (1.0 + 0.3 * c), Wm = 1.0 - 0.12 * c, pinch = 0.07 + c * 0.28, Wr = Wm * (1.0 - pinch);
  vec2 q = toBody(C, A);     // body coordinates, y down, rim at 0

  // Tentacles: from the rim along the chain (hanging, trailing), fanned
  // out around the bell, a little more at each beat (the beat reaches the
  // tips late and softened), and waving slowly along their length.
  if (length(C) < tLen + 1.6) {
    loadChains(true, arms > 0.5);
    float seg = tLen / 12.0;
    for (int i = 0; i < 22; i++) {
      if (float(i) >= tentacles) break;
      float th = float(i) / tentacles * TAU + turn;
      float z = sin(th);
      vec2 p = rot(vec2(cos(th) * Wr * 0.97, sin(th) * Wr * tilt), A);
      if (length(C - p) < K * 1.2 && abs(C.x - p.x) < K * 0.5) add(0.35 + 0.2 * z, markColour);
      float wave = 0.0;
      for (int j = 0; j < 12; j++) {
        float splay = -cos(th) * (0.1 + 0.45 * mix(c, 0.3, min(1.0, float(j) / 5.0)));
        wave += sin(time * 0.4 - float(j) * 0.45 + th * 3.0) * 0.05;
        vec2 q2 = p + rot(fastChain[j], splay + wave) * seg;
        if (segDist(p, q2) < K * 0.5) {
          add((0.2 + 0.1 * z) * (1.0 - 0.65 * float(j) / 12.0), bodyColour);
          break;
        }
        p = q2;
      }
    }

    // Oral arms: thicker, with a slow frill, on the slower chain.
    float aseg = armLen / 9.0;
    for (int i = 0; i < 4; i++) {
      if (float(i) >= arms) break;
      float th = float(i) / arms * TAU + 0.785 + turn;
      vec2 p = rot(vec2(cos(th) * Wr * 0.16, -H * 0.1), A);
      for (int j = 0; j < 9; j++) {
        float f = float(j) / 9.0, wd = 0.07 * (1.0 - f * 0.7);
        vec2 d = rot(slowChain[j], -cos(th) * 0.18);
        p += d * aseg;
        vec2 fr = vec2(-d.y, d.x) * sin(time * 0.35 + float(j) * 1.4 + th) * wd;
        dot2(p + fr, max(wd, K * 0.5), 0.3 * (1.0 - f * 0.5), bodyColour);
      }
    }
  }

  // The bell: clear, brightest at the rim, canals and gonads seen through it.
  float rimW = 0.035 + 0.5 * K;
  float by = q.y, bx = q.x;
  if (by > rimW * 2.0 || by < -H - K * 2.0) return;
  float sv = max(0.0, -by / H);
  float w = Wm * sqrt(max(0.0, 1.0 - sv * sv)) * (1.0 - pinch * pow(1.0 - sv, 3.0));
  if (w < K * 0.4) return;
  float qq = abs(bx) / w;
  if (qq > 1.12) return;
  float rho = sqrt(qq * qq * (1.0 - sv * sv) + sv * sv), v;
  if (rho > 1.0) v = 0.7 * max(0.0, 1.0 - (rho - 1.0) / 0.07);
  else v = 0.05 + 0.75 * pow(rho, 7.0) + 0.13 * exp(-pow((rho - 0.8) / 0.045, 2.0)) * (sv < 0.85 ? 1.0 : 0.0);
  if (qq < 1.0) {
    v += 0.45 * exp(-pow(by / rimW, 2.0));
    for (int m = 0; m < 16; m++) {
      if (float(m) >= canals) break;
      float th = float(m) / canals * TAU + turn;
      float e = (bx / w - cos(th)) / 0.03;
      v += 0.15 * (0.55 + 0.45 * sin(th)) * exp(-e * e) * (1.0 - sv * 0.6);
    }
    if (gonads > 0.5) {
      for (int m = 0; m < 4; m++) {
        float th = float(m) * 1.5708 + 0.785 + turn;
        float gx = (bx - cos(th) * 0.38 * Wm) / (0.16 * Wm);
        float gy = (by - (-H * 0.45 + sin(th) * 0.1 * H)) / (0.11 * H);
        float gd = sqrt(gx * gx + gy * gy);
        add(0.55 * (0.6 + 0.4 * sin(th)) * exp(-pow((gd - 0.75) / 0.28, 2.0)), markColour);
      }
    }
  }
  if (v > 0.02) add(v, bodyColour);
}

// ------------------------------------------------------------ comb jelly
vec4 rain(float i) {
  i = mod(i, 5.0);
  return i < 0.5 ? rain0 : i < 1.5 ? rain1 : i < 2.5 ? rain2 : i < 3.5 ? rain3 : rain4;
}

void ctenophore() {
  bool isRound = p0.x > 0.5;
  float a = 0.95, b = p0.y, egg = p0.z, plates = p0.w;
  float wave = p1.x, tLen = p1.y, spin = time * p1.z + phase;
  vec2 q = toBody(C, A);

  // Two fishing tentacles streaming behind, with side filaments.
  if (isRound && length(C) < tLen + 1.6) {
    loadChains(false, true);
    float seg = tLen / 18.0;
    for (int i = 0; i < 2; i++) {
      float side = i == 0 ? 1.0 : -1.0;
      vec2 p = rot(vec2(side * 0.45 * b, 0.15 * a), A);
      float wave = 0.0;
      for (int j = 0; j < 18; j++) {
        wave += sin(time * 0.4 - float(j) * 0.45 + side * 2.0) * 0.06;
        vec2 d = rot(slowChain[j], -side * 0.3 + wave);
        vec2 q2 = p + d * seg;
        thread(p, q2, 0.15 * (1.0 - 0.5 * float(j) / 18.0), bodyColour);
        if (j >= 3 && mod(float(j), 2.0) > 0.5) {
          float fl = 0.22 * (1.0 - float(j) / 18.0);
          float fa = side * (1.1 + 0.15 * sin(time * 0.3 + float(j)));
          thread(q2, q2 + rot(d, fa) * fl, 0.09, bodyColour);
        }
        p = q2;
      }
    }
  }

  // The body: a clear egg, rim-lit, the pharynx and tentacle sheaths inside.
  float tt = q.y / a;
  if (abs(tt) <= 1.06) {
    float bw = b * (1.0 + egg * tt) * sqrt(max(0.0, 1.0 - tt * tt));
    if (bw >= K * 0.4) {
      float qq = abs(q.x) / bw;
      if (qq <= 1.12) {
        float rho = sqrt(qq * qq * (1.0 - tt * tt) + tt * tt), v;
        if (rho > 1.0) v = 0.62 * max(0.0, 1.0 - (rho - 1.0) / 0.07);
        else {
          v = 0.05 + 0.62 * pow(rho, 6.0);
          if (q.y > 0.0) v += 0.15 * exp(-pow(q.x / (0.1 * b + 0.4 * K), 2.0)) * tt;
          if (isRound) v += 0.14 * exp(-(pow((abs(q.x) - 0.45 * b) / (0.12 * b + 0.3 * K), 2.0) + pow((q.y - 0.02 * a) / (0.32 * a), 2.0)));
        }
        if (v > 0.02) add(v, bodyColour);
      }
    }
  }

  // The statocyst at the leading pole.
  dot2(rot(vec2(0.0, -0.9 * a), A), max(K * 0.6, 0.04), 0.8, accentColour);

  // Eight comb rows; light runs down them and splits into colours.
  if (length(C) < 1.4) {
    for (int i = 0; i < 8; i++) {
      float th = float(i) / 8.0 * TAU + spin, z = cos(th);
      float vis = z < -0.2 ? 0.25 : 0.45 + 0.55 * max(0.0, z);
      for (int j = 0; j < 22; j++) {
        if (float(j) >= plates) break;
        float u = -0.84 + 1.56 * float(j) / (plates - 1.0);
        float rr = b * (1.0 + egg * u) * sqrt(max(0.0, 1.0 - u * u));
        vec2 p = rot(vec2(sin(th) * rr * 1.02, u * a), A);
        if (abs(p.x - C.x) > K * 0.5 || abs(p.y - C.y) > K) continue;
        float br = pow(max(0.0, sin(float(j) * 0.5 - time * wave * TAU)), 3.0);
        add((0.08 + 0.55 * br) * vis, rain(floor(float(j) * 0.35 + float(i) * 0.6 - time * wave * 1.2)));
      }
    }
  }
}

// ------------------------------------------------------------ radiolarian
void radiolarian() {
  float shells = p0.x, pods = p0.y, podLen = p0.z, rc = p0.w;
  float spines = p1.x, longSpines = p1.y, every = p1.z, a = time * p1.w + phase;

  // Fine threads, with granules creeping outward.
  for (int i = 0; i < 34; i++) {
    if (float(i) >= pods) break;
    float h1 = hash1(float(i) * 3.1 + 0.5), h2 = hash1(float(i) * 7.7 + 1.3), h3 = hash1(float(i) * 1.9 + 2.9);
    float an = float(i) / pods * TAU + a * 0.6 + h1 * 0.2;
    vec2 d = vec2(cos(an), sin(an));
    float r0 = 0.8, r1 = podLen * (0.85 + 0.3 * h2);
    thread(d * r0, d * r1, 0.075, glass);
    for (int j = 0; j < 2; j++) {
      float fr = fract(time * 0.012 + h3 + float(j) * 0.5);
      at(d * (r0 + (r1 - r0) * fr), 0.35 * sin(fr * PI), glass);
    }
  }

  // Glass spines.
  for (int i = 0; i < 20; i++) {
    if (float(i) >= spines) break;
    float an = float(i) / spines * TAU + (hash1(float(i) + 9.1) - 0.5) * 0.24 + a;
    float isLong = longSpines > 0.5 && mod(float(i), every) < 0.5 ? 1.0 : 0.0;
    float e = mix(1.12, 1.4, hash1(float(i) + 4.4)) + isLong * 0.45;
    vec2 d = vec2(cos(an), sin(an));
    glassLine(d * rc, d * e, 0.85);
    thread(d * 0.95, d * e, 0.12, glass);
  }

  // Lattice shells and the central capsule.
  float r = length(C), th = atan(C.y, C.x) - a, ring = 0.03 + 0.5 * K, v = 0.0;
  for (int m = 0; m < 3; m++) {
    if (float(m) >= shells) break;
    vec4 sh = m == 0 ? p2 : m == 1 ? p3 : p4;
    v += 0.42 * exp(-pow((r - sh.x) / ring, 2.0));
    if (r < sh.x) {
      float u = r / sh.x, phh = asin(min(1.0, u));
      float l1 = pow(abs(cos(sh.y * th * 0.5)), 14.0), l2 = pow(abs(cos(sh.z * phh * 2.0)), 14.0);
      v += max(l1, l2) * 0.22 * (0.55 + 0.45 * sqrt(1.0 - u * u));
    }
  }
  if (v > 0.03) add(v, glass);
  if (r < rc) {
    float uu = r / rc, s2 = 0.22 + 0.24 * sqrt(1.0 - uu * uu) - 0.1 * (C.x * 0.6 + C.y * 0.8) / rc;
    if (uu < 0.36) s2 += 0.32;
    add(s2, markColour);
  }
}

// ------------------------------------------------------------ volvox
// The surface cells of a ball seen at a point: a lattice on the sphere, so
// each cell of the ball lights where a colony cell faces it.
float cellsAt(vec3 n, float count) {
  float bands = max(4.0, floor(sqrt(count) * 0.9));
  float lat = acos(clamp(n.y, -1.0, 1.0)) / PI * bands;
  float band = floor(lat);
  float inBand = max(3.0, floor(sin((band + 0.5) / bands * PI) * bands * 2.0));
  float lon = (atan(n.z, n.x) / TAU + 0.5) * inBand + hash1(band) * 3.0;
  vec2 f = vec2(fract(lon), fract(lat)) - 0.5;
  return 1.0 - smoothstep(0.18, 0.32, length(f));
}

vec3 tiltSpin(vec3 p, float spin, float tilt) {
  float cs = cos(spin), ss = sin(spin), ct = cos(tilt), st = sin(tilt);
  float x = p.x * cs + p.z * ss, z = -p.x * ss + p.z * cs;
  return vec3(x, p.y * ct - z * st, p.y * st + z * ct);
}
// The inverse, for a point on the screen back to the colony's own frame.
vec3 untilt(vec3 q, float spin, float tilt) {
  float cs = cos(spin), ss = sin(spin), ct = cos(tilt), st = sin(tilt);
  float y = q.y * ct + q.z * st, z = -q.y * st + q.z * ct;
  return vec3(q.x * cs - z * ss, y, q.x * ss + z * cs);
}

void volvox() {
  float count = p0.x, tilt = p0.y, spin = time * p0.z + phase, daughters = p0.w;
  float u = length(C), v;
  if (u > 1.0) v = 0.3 * max(0.0, 1.0 - (u - 1.0) / (0.04 + K));
  else v = 0.035 + 0.3 * pow(u, 10.0);
  if (v > 0.02) add(v, bodyColour);

  // Daughter colonies inside, each turning on its own.
  for (int i = 0; i < 4; i++) {
    if (float(i) >= daughters) break;
    vec4 d = i == 0 ? p1 : i == 1 ? p2 : i == 2 ? p3 : p4;
    vec3 q = tiltSpin(d.xyz, spin, tilt);
    float depth = 0.65 + 0.35 * q.z;
    vec2 dc = q.xy, rel = (C - dc) / d.w;
    dot2(dc, d.w, 0.22 * depth, markColour);
    float rr = dot(rel, rel);
    if (rr < 1.0) {
      vec3 n = vec3(rel, sqrt(1.0 - rr));
      float s = spin * 3.0 * (1.0 + float(i) * 0.3);
      add(cellsAt(untilt(n, s, 0.0), 36.0) * (0.2 + 0.25 * n.z) * depth, markColour);
    }
  }

  // Hundreds of surface cells, the near side bright, the far side dim.
  if (u < 1.0) {
    float z = sqrt(1.0 - u * u);
    add(cellsAt(untilt(vec3(C, z), spin, tilt), count) * (0.14 + 0.36 * z), bodyColour);
    add(cellsAt(untilt(vec3(C, -z), spin, tilt), count) * 0.06, bodyColour);
  }
}

// ------------------------------------------------------------ diatom
void diatom() {
  bool pennate = p0.x > 0.5;
  float width = p0.y, tip = p0.z, striae = p0.w, rings = p1.x, rays = p1.y, drops = p1.z, glide = p1.w;
  if (pennate) {
    // Glides along its long axis, stops, glides back: swimming, swim.frag
    // moves it; kept still, it slides a little about its place.
    float g = swims() ? 0.0 : sin(fract(time / glide + phase) * TAU) * 0.12;
    vec2 o = rot(vec2(0.0, -g), A);
    vec2 q = toBody(C - o, A);
    float AA = 1.15, B = width * 1.4, k = tip * 0.6;
    float tt = q.y / AA;
    if (abs(tt) <= 1.04) {
      float w = B * pow(max(0.0, 1.0 - tt * tt), k);
      if (w >= K * 0.3) {
        float qq = abs(q.x) / w;
        if (qq <= 1.15) {
          float at2 = abs(tt), v = 0.55 * exp(-pow((qq - 1.0) / 0.09, 2.0));
          if (qq < 1.0) {
            v += 0.05;
            if (qq > 0.22) v += pow(abs(cos(tt * striae * PI)), 10.0) * 0.2 * (0.6 + 0.4 * qq);
            if (qq < 0.08 && at2 > 0.07) v += 0.32;
            if (at2 < 0.08 && qq < 0.28) v += 0.28;
            if (at2 > 0.88 && qq < 0.3) v += 0.25;
            add(0.42 * exp(-pow((qq - 0.58) / 0.2, 2.0)) * (1.0 - pow(min(1.0, at2 / 0.82), 6.0)), markColour);
          }
          if (v > 0.02) add(v, bodyColour);
        }
      }
    }
    for (int i = 0; i < 4; i++) {
      if (float(i) >= drops) break;
      vec2 d = i == 0 ? p2.xy : i == 1 ? p2.zw : i == 2 ? p3.xy : p3.zw;
      dot2(rot(vec2(d.x * B, d.y * AA), A) + o, max(K * 0.6, 0.05), 0.75, markColour);
    }
  } else {
    // Round ones only turn.
    float a = time * 0.012 + phase, Rd = 0.95;
    float r = length(C), u = r / Rd;
    if (u <= 1.1) {
      float th = atan(C.y, C.x) - a, v = 0.55 * exp(-pow((u - 1.0) / 0.05, 2.0));
      if (u < 1.0) {
        v += 0.04 + pow(abs(cos(u * rings * PI)), 14.0) * 0.17 + pow(abs(cos(th * rays * 0.5)), 14.0) * 0.2 * u;
        if (u < 0.14) v += 0.22;
      }
      if (v > 0.02) add(v, bodyColour);
    }
    for (int i = 0; i < 14; i++) {
      float an = hash1(float(i) * 5.3 + 1.0) * TAU, rr = sqrt(hash1(float(i) * 2.1 + 7.0)) * 0.72;
      dot2(rot(vec2(cos(an), sin(an)) * rr * Rd, a), max(K * 0.6, 0.09), 0.45, markColour);
    }
  }
}

// How far the organism reaches from its position, in R.
float extent() {
  if (kindIndex < 0.5) return p0.w + 1.6;
  if (kindIndex < 1.5) return p0.x > 0.5 ? p1.y + 1.6 : 1.3;
  if (kindIndex < 2.5) return p0.z * 1.2 + 0.2;
  return 1.4;
}

void main() {
  // Each fragment is one cell; its centre in px.
  vec2 px = origin + qt_TexCoord0 * box;
  if (radius < cell * 0.9 || amp <= 0.0) discard;
  if (bound > 0.0 && length(px - clipAt) > bound) discard;

  vec2 pos = swayAt(time);
  A = swayHeading(time);
  if (swims()) {
    // Until swim.frag has taken its first step for this track, it is at home.
    vec4 s0 = swimAt(0.0), s1 = swimAt(1.0), s2 = swimAt(2.0);
    if (abs(s2.w - (phase + 1.0)) < 0.001) { pos = s0.xy; A = s1.x; }
    else pos = home;
  }
  // A medusa or comb jelly kept still (a lens) is centred on its whole
  // length, so the bell and the tentacles share the space.
  if (!swims()) {
    if (kindIndex < 0.5) pos += rot(vec2(0.0, -(p0.w - p0.x) * 0.5), A) * radius;
    else if (kindIndex < 1.5 && p0.x > 0.5) pos += rot(vec2(0.0, -(p1.y - 0.95) * 0.5), A) * radius;
  }
  C = (px - pos) / radius;
  K = cell / radius;
  if (length(C) > extent() + 1.0) discard;

  total = 0.0; best = 0.0; colour = glass;
  lineG = 0.0; lineA = 0.0;

  if (kindIndex < 0.5) medusa();
  else if (kindIndex < 1.5) ctenophore();
  else if (kindIndex < 2.5) radiolarian();
  else if (kindIndex < 3.5) volvox();
  else diatom();

  // Small organisms fade in as they grow, as in the studies.
  total *= amp * min(1.0, radius / (cell * 3.0));
  if (lineG > 0.0 && total < 0.32) fragColor = vec4(glass.rgb, 0.8 + 0.04 * lineG);
  else if (total >= 0.04) fragColor = vec4(colour.rgb, min(total, 1.4) / 1.4 * 0.8);
  else discard;
}
