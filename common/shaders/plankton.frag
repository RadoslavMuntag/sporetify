#version 440

// A plankton organism drawn as characters (the "organism studies"). The item
// is cut into cells one `cell` px wide and two tall. For each cell the
// organism's light is worked out from its parameters and the time, and the
// cell shows the glyph of that brightness from `atlas`, in the colour of the
// part that lit it most. Thin glass lines (spines) use line glyphs instead.
//
// Everything that moves is a function of `time` (seconds), so the host only
// animates one number, and only while the organism is alive.
//
// Compile with scripts/shaders.sh after a change; the .qsb is checked in.
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
  vec2 area;      // item size, px
  vec2 clipAt;    // centre of the circle drawn inside, px
  float bound;    // its radius, px; 0 for no limit
  float cell;     // cell width, px
  float radius;   // R, px
  float time;
  float seed;     // per-track phase, 0..100
  float kind;
  float light;    // 1 on a light theme
  float glyphs;   // glyphs in the atlas
  vec4 p0;
  vec4 p1;
  vec4 p2;
  vec4 p3;
  vec4 p4;
  vec4 p5;
  vec4 bodyColour;      // body colour
  vec4 markColour;      // detail colour
  vec4 glass;     // the theme's foreground
  vec4 accent;
  vec4 rain0;
  vec4 rain1;
  vec4 rain2;
  vec4 rain3;
  vec4 rain4;
};
layout(binding = 1) uniform sampler2D atlas;

const float TAU = 6.2831853;
const float PI = 3.1415927;

// Atlas: " .·:-=+*#%@" then "-|/\°".
const float G_DASH = 11.0;
const float G_BAR = 12.0;
const float G_FS = 13.0;
const float G_BS = 14.0;
const float G_DEG = 15.0;

// What lights the cell: the sum, and the colour of the brightest part.
float total;
float best;
vec4 colour;
// A glass line glyph, shown where nothing brighter is.
float lineG;
float lineA;
vec4 lineC;

vec2 C;    // cell centre, in R from the organism's centre (y down)
float K;   // cell width in R; a cell is K wide and 2K tall

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

void glassLine(vec2 a, vec2 b, vec4 c, float alpha) {
  float d = segDist(a, b);
  if (d >= K * 0.5 || alpha < lineA) return;
  vec2 dir = b - a;
  float ax = abs(dir.x), ay = abs(dir.y) * 0.5;
  float g = ay < ax * 0.45 ? G_DASH : ax < ay * 0.45 ? G_BAR : dir.x * dir.y < 0.0 ? G_FS : G_BS;
  if (length(C - b) < K) g = G_DEG;
  lineG = g; lineA = alpha; lineC = c;
}

vec2 rot(vec2 p, float a) {
  float c = cos(a), s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}
// World to body: the inverse of rot.
vec2 toBody(vec2 p, float a) { return rot(p, -a); }

float hash1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float ease(float x) { return x * x * (3.0 - 2.0 * x); }

// ------------------------------------------------------------ medusa
void medusa() {
  float bell = p0.x, period = p0.y, tentacles = p0.z, tLen = p0.w;
  float arms = p1.x, armLen = p1.y, canals = p1.z, gonads = p1.w;
  float tilt = p2.x, turn = p2.y;

  // A contraction of about 1.5 s, then a long slow relax.
  float ph = fract(time / period + seed);
  float c = ph < 0.3 ? ease(ph / 0.3) : 1.0 - ease((ph - 0.3) / 0.7);
  float H = bell * (1.0 + 0.3 * c), Wm = 1.0 - 0.12 * c, pinch = 0.07 + c * 0.28, Wr = Wm * (1.0 - pinch);
  float a = sin(time * 0.05 + seed) * 0.12;
  // Bell and tentacles together are centred, so the rim sits above the middle.
  vec2 o = vec2(0.0, -(tLen - bell) * 0.5);
  vec2 q = toBody(C - o, a);     // body coordinates, y down, rim at 0

  // Tentacles hang from the rim, splay with each beat and sway slowly.
  for (int i = 0; i < 22; i++) {
    if (float(i) >= tentacles) break;
    float th = float(i) / tentacles * TAU + turn;
    float z = sin(th);
    vec2 root = vec2(cos(th) * Wr * 0.97, sin(th) * Wr * tilt);
    float s = q.y - root.y;
    if (s < 0.0 || s > tLen) continue;
    float spread = sin(cos(th) * (0.1 + 0.45 * c));
    float sway = sin(time * 0.4 - s * 3.0 + th * 3.0) * 0.05 * s;
    float x = root.x + spread * s + sway;
    if (abs(q.x - x) < K * 0.5) add((0.2 + 0.1 * z) * (1.0 - 0.65 * s / tLen), bodyColour);
    if (s < K * 2.0 && abs(q.x - root.x) < K * 0.5) add(0.35 + 0.2 * z, markColour);
  }

  // Oral arms: thicker, with a slow frill.
  for (int i = 0; i < 4; i++) {
    if (float(i) >= arms) break;
    float th = float(i) / arms * TAU + 0.785 + turn;
    vec2 root = vec2(cos(th) * Wr * 0.16, -H * 0.1);
    float s = q.y - root.y;
    if (s < 0.0 || s > armLen) continue;
    float f = s / armLen, wd = 0.07 * (1.0 - f * 0.7);
    float x = root.x - sin(cos(th) * 0.18) * s + sin(time * 0.35 + f * 12.6 + th) * wd;
    float d = abs(q.x - x) / max(wd, K * 0.5);
    if (d < 1.0) add(0.3 * (1.0 - f * 0.5) * (1.0 - d * d), bodyColour);
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
  float wave = p1.x, tLen = p1.y, spin = time * p1.z + seed;
  float ang = sin(time * 0.04 + seed) * 0.25;
  vec2 o = isRound ? vec2(0.0, -(tLen - 0.95) * 0.5) : vec2(0.0, 0.0);
  vec2 q = toBody(C - o, ang);

  // Two fishing tentacles trailing behind, with side filaments.
  if (isRound) {
    for (int i = 0; i < 2; i++) {
      float side = i == 0 ? 1.0 : -1.0;
      vec2 root = vec2(side * 0.45 * b, 0.15 * a);
      float s = q.y - root.y;
      if (s >= 0.0 && s <= tLen) {
        float x = root.x + side * 0.3 * s + sin(time * 0.4 - s * 2.5 + side * 2.0) * 0.06 * s;
        if (abs(q.x - x) < K * 0.5) add(0.15 * (1.0 - 0.5 * s / tLen), bodyColour);
      }
      for (int j = 1; j < 9; j++) {
        float sj = tLen * float(j) / 9.0;
        vec2 p = root + vec2(side * 0.3 * sj + sin(time * 0.4 - sj * 2.5 + side * 2.0) * 0.06 * sj, sj);
        float fl = 0.22 * (1.0 - float(j) / 9.0);
        float fa = PI * 0.5 - side * (1.1 + 0.15 * sin(time * 0.3 + float(j)));
        vec2 e = p + vec2(cos(fa), sin(fa)) * fl;
        if (segDist(rot(p, ang) + o, rot(e, ang) + o) < K * 0.5) add(0.09, bodyColour);
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
  dot2(rot(vec2(0.0, -0.9 * a), ang) + o, max(K * 0.6, 0.04), 0.8, accent);

  // Eight comb rows; light runs down them and splits into colours.
  for (int i = 0; i < 8; i++) {
    float th = float(i) / 8.0 * TAU + spin, z = cos(th);
    float vis = z < -0.2 ? 0.25 : 0.45 + 0.55 * max(0.0, z);
    for (int j = 0; j < 22; j++) {
      if (float(j) >= plates) break;
      float u = -0.84 + 1.56 * float(j) / (plates - 1.0);
      float rr = b * (1.0 + egg * u) * sqrt(max(0.0, 1.0 - u * u));
      vec2 p = rot(vec2(sin(th) * rr * 1.02, u * a), ang) + o;
      if (abs(p.x - C.x) > K * 0.5 || abs(p.y - C.y) > K) continue;
      float br = pow(max(0.0, sin(float(j) * 0.5 - time * wave * TAU)), 3.0);
      add((0.08 + 0.55 * br) * vis, rain(floor(float(j) * 0.35 + float(i) * 0.6 - time * wave * 1.2)));
    }
  }
}

// ------------------------------------------------------------ radiolarian
void radiolarian() {
  float shells = p0.x, pods = p0.y, podLen = p0.z, rc = p0.w;
  float spines = p1.x, longSpines = p1.y, every = p1.z, a = time * p1.w + seed;

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
    glassLine(d * rc, d * e, glass, 0.85);
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
  float count = p0.x, tilt = p0.y, spin = time * p0.z + seed, daughters = p0.w;
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
    // Glides along its longSpines axis, stops, glides back.
    float ang = PI * 0.5 + sin(time * 0.03 + seed) * 0.15;
    float g = sin(fract(time / glide + seed) * TAU) * 0.12;
    vec2 o = rot(vec2(0.0, -g), ang);
    vec2 q = toBody(C - o, ang);
    float A = 1.15, B = width * 1.4, k = tip * 0.6;
    float tt = q.y / A;
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
      dot2(rot(vec2(d.x * B, d.y * A), ang) + o, max(K * 0.6, 0.05), 0.75, markColour);
    }
  } else {
    // Round ones only turn.
    float a = time * 0.012 + seed, Rd = 0.95;
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

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 cellIndex = floor(px / vec2(cell, cell * 2.0));
  vec2 centre = (cellIndex + 0.5) * vec2(cell, cell * 2.0);
  if (bound > 0.0 && length(centre - clipAt) > bound) discard;
  C = (centre - area * 0.5) / radius;
  K = cell / radius;
  total = 0.0; best = 0.0; colour = glass;
  lineG = 0.0; lineA = 0.0; lineC = glass;

  if (kind < 0.5) medusa();
  else if (kind < 1.5) ctenophore();
  else if (kind < 2.5) radiolarian();
  else if (kind < 3.5) volvox();
  else diatom();

  float g, alpha;
  vec4 col;
  if (lineG > 0.0 && total < 0.32) {
    g = lineG; col = lineC; alpha = lineA;
  } else {
    if (total < 0.04) discard;
    g = 1.0 + min(9.0, floor(pow(min(1.0, total / 1.4), 1.05) * 10.0));
    col = colour;
    // The brightest cells are lit a little beyond their colour.
    // The brightest cells are lit beyond their colour, the rim and core
    // most: that is what makes the organism glow against the water.
    if (total > 0.9) col.rgb = mix(col.rgb, vec3(1.0 - light), light > 0.5 ? 0.3 : 0.45);
    else if (total > 0.55) col.rgb = mix(col.rgb, vec3(1.0 - light), light > 0.5 ? 0.12 : 0.18);
    alpha = clamp(0.25 + total * 1.2, 0.08, 1.0);
  }

  vec2 local = fract(px / vec2(cell, cell * 2.0));
  // A little inside the cell: at its very edge the filter reads the
  // neighbouring glyph, which drew a faint box around characters.
  local = mix(vec2(0.08, 0.04), vec2(0.92, 0.96), local);
  float ink = texture(atlas, vec2((g + local.x) / glyphs, local.y)).a;
  fragColor = vec4(col.rgb, 1.0) * ink * alpha * qt_Opacity;
}
