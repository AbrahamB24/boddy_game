// Node port of tool/pixel_icons/pix.py (24x24, 4-tone hue-shifted ramps, coloured outline,
// own cast shadow, light from top-left) so icon proposals can be drawn without Python.
const { createCanvas } = require('@napi-rs/canvas');
const N = 24;

const hx = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
function rgb2hsv(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) {
    if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
    h /= 6; if (h < 0) h += 1;
  }
  return [h, mx ? d / mx : 0, mx];
}
function hsv2rgb(h, s, v) {
  const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  const m = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6];
  return m.map((c) => Math.round(c * 255));
}
const cl = (x) => Math.max(0, Math.min(1, x));
function ramp(base) {
  const [r, g, b] = hx(base); const [h, s, v] = rgb2hsv(r, g, b);
  const mk = (dh, ds, dv) => hsv2rgb((h + dh + 1) % 1, cl(s + ds), cl(v + dv));
  return [mk(-0.07, 0.10, -0.74), mk(-0.045, 0.10, -0.34), mk(0, 0, 0), mk(0.025, -0.10, 0.16), mk(0.04, -0.34, 0.34)];
}

const PAL = {
  bark: '#94602f', ring: '#ecca8f', stone: '#8e9aa8', stone2: '#a9a398', moss: '#5fae48', fish: '#4f9bd6', fishb: '#d3e8f5',
  fin: '#2f6db0', gold: '#eaaa22', goldl: '#ffe27a', wall: '#ead7a6', roof: '#c95238', door: '#8a5530', brass: '#d8a43a',
  face: '#f4ecd2', red: '#d6452f', wood: '#aa6a30', woodl: '#cd904a', iron: '#66727f', steel: '#93a1b3', paper: '#f0e2b4',
  green: '#58b04a', blue: '#4f86c9', skin: '#f2c493', orange: '#eaa23c', leather: '#a8672d', leatherd: '#6b4020',
  black: '#2d2733', coal: '#3a3640', clay: '#b9744a', sand: '#e4cb84', lime: '#e6e2d6', copper: '#c8743c', silver: '#c9d3dc',
  ironore: '#8a6a5a', ruby: '#d8344f', cyan: '#48c8d8', crystal: '#4f86f0', purple: '#8a5ac8', pink: '#f07aa0',
  meat: '#d8604a', fat: '#f2b8a8', bread: '#d9a050', apple: '#d64a38', leaf: '#58b04a', water: '#4a9ae0', ice: '#e6f1f6', bolt: '#ffd93d', black2: '#14121a', paw: '#e8873a', navy: '#2e4690', forest: '#2f6a3f', brown: '#7a4a2a',
};
const R = {};
for (const [k, v] of Object.entries(PAL)) R[k] = ramp(v);
const rp = (name) => (typeof name === 'string' ? (R[name] || (R[name] = ramp(name))) : name);

// ---- shape predicates ------------------------------------------------------
const ell = (cx, cy, rx, ry) => (x, y) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
const rect = (x0, y0, x1, y1) => (x, y) => x >= x0 && x < x1 + 1 && y >= y0 && y < y1 + 1;
const poly = (pts) => (x, y) => {
  let c = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
};
const rrect = (cx, cy, along, perp, deg) => {
  const ca = Math.cos((deg * Math.PI) / 180), sa = Math.sin((deg * Math.PI) / 180);
  return (x, y) => { const dx = x - cx, dy = y - cy; return Math.abs(dx * ca + dy * sa) <= along / 2 && Math.abs(-dx * sa + dy * ca) <= perp / 2; };
};
const thick = (x0, y0, x1, y1, w) => rrect((x0 + x1) / 2, (y0 + y1) / 2, Math.hypot(x1 - x0, y1 - y0), w, (Math.atan2(y1 - y0, x1 - x0) * 180) / Math.PI);
const minus = (a, b) => (x, y) => a(x, y) && !b(x, y);
const both = (a, b) => (x, y) => a(x, y) && b(x, y);
const either = (a, b) => (x, y) => a(x, y) || b(x, y);
const ring = (cx, cy, ro, ri) => minus(ell(cx, cy, ro, ro), ell(cx, cy, ri, ri));
const heart = (cx, cy, s) => (x, y) => { const u = (x - cx) / s, v = (-(y - cy) / s) * 1.05 + 0.15; return (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0; };
const star = (cx, cy, ro, ri, n = 5) => {
  const pts = [];
  for (let i = 0; i < n * 2; i++) { const a = -Math.PI / 2 + (i * Math.PI) / n, r = i % 2 ? ri : ro; pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); }
  return poly(pts);
};

class Cv {
  constructor() { this.p = Array.from({ length: N }, () => new Array(N).fill(null)); }
  shape(mask, r, mode = 'orb', bias = 0) {
    const R_ = rp(r), pts = [];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (mask(x + 0.5, y + 0.5)) pts.push([x, y]);
    if (!pts.length) return this;
    const x0 = Math.min(...pts.map((p) => p[0])), x1 = Math.max(...pts.map((p) => p[0])) + 1;
    const y0 = Math.min(...pts.map((p) => p[1])), y1 = Math.max(...pts.map((p) => p[1])) + 1;
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = Math.max(1, (x1 - x0) / 2), ry = Math.max(1, (y1 - y0) / 2);
    for (const [x, y] of pts) {
      const nx = (x + 0.5 - cx) / rx, ny = (y + 0.5 - cy) / ry;
      let sv = mode === 'orb' ? 0.5 + (nx * 0.42 + ny * 0.58) * 0.5 : mode === 'vert' ? 0.5 + ny * 0.5 : mode === 'diag' ? 0.5 + (nx + ny) * 0.27 : 0.5;
      sv += bias;
      this.p[y][x] = [R_, sv < 0.18 ? 4 : sv < 0.4 ? 3 : sv < 0.72 ? 2 : 1];
    }
    return this;
  }
  px(x, y, r, t) { if (x >= 0 && x < N && y >= 0 && y < N) this.p[Math.round(y)][Math.round(x)] = [rp(r), t]; return this; }
  line(a, b, c, d, r, t) {
    const n = Math.max(Math.abs(c - a), Math.abs(d - b), 1);
    for (let i = 0; i <= n; i++) this.px(Math.round(a + ((c - a) * i) / n), Math.round(b + ((d - b) * i) / n), r, t);
    return this;
  }
  render() {
    const cv = createCanvas(N, N), g = cv.getContext('2d'), im = g.createImageData(N, N), d = im.data;
    const set = (x, y, c, a = 255) => { const i = (y * N + x) * 4; d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = a; };
    const filled = (x, y) => x >= 0 && y >= 0 && x < N && y < N && this.p[y][x] !== null;
    let xs = [], ys = [];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (filled(x, y)) { xs.push(x); ys.push(y); }
    if (ys.length) {
      const gy = Math.max(...ys) + 1, gx0 = Math.min(...xs) + 2, gx1 = Math.max(...xs) - 1;
      for (let x = gx0; x <= gx1; x++) for (const yy of [gy, gy + 1]) if (yy < N && !filled(x, yy)) set(x, yy, [20, 14, 40], x === gx0 || x === gx1 || yy === gy + 1 ? 70 : 110);
    }
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (filled(x, y)) continue;
      for (const [dx, dy] of [[0, 1], [1, 0], [-1, 0], [0, -1]]) if (filled(x + dx, y + dy)) { set(x, y, this.p[y + dy][x + dx][0][0]); break; }
    }
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (filled(x, y)) { const [r, t] = this.p[y][x]; set(x, y, r[t]); }
    g.putImageData(im, 0, 0);
    return cv.toBuffer('image/png');
  }
}
const cv = () => new Cv();

module.exports = { Cv, cv, R, rp, ramp, PAL, ell, rect, poly, rrect, thick, minus, both, either, ring, heart, star };
