// New 24x24 pixel icons in the gold UI style (arrows, pencil, check ...): dark outline,
// 4-tone ramp lit from the top left, a soft cast shadow underneath.
// Run: cd tool/icons && node ../pixel_icons/gold_glyphs.js
// (uses the @napi-rs/canvas that tool/icons already installs)
const { createCanvas } = require('../icons/node_modules/@napi-rs/canvas');
const fs = require('fs');
const path = require('path');
const OUT = path.resolve(__dirname, '../../assets/images/icons');
const N = 48; // output grid; shapes below are drawn in 24-unit coordinates and sampled at SC x
const SC = 2;

const RAMPS = {
  gold: { o: '#2d0d02', d: '#934007', b: '#eaaa22', l: '#ffde3f', h: '#fff57c' },
  blue: { o: '#0a1530', d: '#2a4a8a', b: '#4f86c9', l: '#779cf2', h: '#b8ccff' },
  pink: { o: '#3a0a1c', d: '#a02a55', b: '#e8648f', l: '#ff93b5', h: '#ffd0de' },
  cream: { o: '#2d0d02', d: '#b09a6a', b: '#f0e2b8', l: '#fff6dc', h: '#ffffff' },
  stone: { o: '#1d2230', d: '#5d6778', b: '#9aa3b0', l: '#c5ccd6', h: '#eef1f5' },
  red: { o: '#3a0a0a', d: '#8a1f1f', b: '#d23a32', l: '#f06a58', h: '#ffb0a0' },
  ink: { o: '#0c0a12', d: '#1f1b29', b: '#3b3647', l: '#58526a', h: '#7c7690' },
  wood: { o: '#2d0d02', d: '#5a3418', b: '#94602f', l: '#b88048', h: '#dcaa70' },
  orange: { o: '#3a0d02', d: '#9a2c0a', b: '#f06a1a', l: '#ff9a3a', h: '#ffd27a' },
  yellow: { o: '#3a2a02', d: '#b07a0a', b: '#ffd22a', l: '#ffe85a', h: '#fffbb0' },
  green: { o: '#06240f', d: '#2a6a2a', b: '#58b04a', l: '#8ad66a', h: '#c8f5a0' },
  water: { o: '#06183a', d: '#1f5aa0', b: '#3a9ae0', l: '#6cc4ff', h: '#c0eaff' },
  rock: { o: '#201a14', d: '#5a5148', b: '#948a7c', l: '#bdb4a4', h: '#e6e0d2' },
  violet: { o: '#14082a', d: '#4a3a7a', b: '#8a70c0', l: '#a890e0', h: '#d8c8ff' },
  track: { o: '#2d0d02', d: '#3a1f0c', b: '#55321a', l: '#6b4224', h: '#6b4224' },
};
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

const ell = (cx, cy, rx, ry) => (x, y) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
const rect = (x0, y0, x1, y1) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
const minus = (a, b) => (x, y) => a(x, y) && !b(x, y);
const union = (...f) => (x, y) => f.some((g) => g(x, y));
const poly = (pts) => (x, y) => {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
};
const thick = (x0, y0, x1, y1, w) => (x, y) => {
  const dx = x1 - x0, dy = y1 - y0, l2 = dx * dx + dy * dy;
  const t = Math.max(0, Math.min(1, ((x - x0) * dx + (y - y0) * dy) / l2));
  return Math.hypot(x - (x0 + t * dx), y - (y0 + t * dy)) <= w / 2;
};
const ring = (cx, cy, ro, ri) => minus(ell(cx, cy, ro, ro), ell(cx, cy, ri, ri));
// four-pointed star: concave sides
const both = (a, b) => (x, y) => a(x, y) && b(x, y);
const star4 = (cx, cy, r) => (x, y) => (Math.abs(x - cx) / r) ** 0.62 + (Math.abs(y - cy) / r) ** 0.62 <= 1;

function render(layers) {
  const px = Array.from({ length: N }, () => Array(N).fill(null)); // {ramp, tone}
  for (const [fn, ramp] of layers) {
    const cells = [];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (fn.raw ? fn(x, y) : fn((x + 0.5) / SC, (y + 0.5) / SC)) cells.push([x, y]);
    const has = (x, y) => cells.some((c) => c[0] === x && c[1] === y);
    const set = new Set(cells.map((c) => c[0] + ',' + c[1]));
    const at = (x, y) => set.has(x + ',' + y);
    // Light from the top left: a bevel of light tones along the upper/left edges, a dark band along the
    // lower/right edges, a bright spot on the upper-left third (like the bell and arrows of the old set).
    const run = (x, y, dx, dy) => { let k = 0; while (at(x + dx * (k + 1), y + dy * (k + 1))) k++; return k; };
    const sums = cells.map((c) => c[0] + c[1]);
    const sMin = Math.min(...sums), sMax = Math.max(...sums);
    for (const [x, y] of cells) {
      const ul = Math.min(run(x, y, 0, -1), run(x, y, -1, 0)) + 1;
      const br = Math.min(run(x, y, 0, 1), run(x, y, 1, 0)) + 1;
      let t = 'b';
      if (ul <= 3) t = 'l';
      if (ul <= 2 && x + y < sMin + (sMax - sMin) * 0.42) t = 'h';
      if (br <= 2 && ul > 1) t = 'd';
      else if (br <= 4 && ul > 5) t = 'd';
      px[y][x] = { ramp, t };
    }
  }
  const filled = (x, y) => x >= 0 && y >= 0 && x < N && y < N && px[y][x];
  const out = createCanvas(N, N);
  const g = out.getContext('2d');
  const img = g.createImageData(N, N);
  const put = (x, y, c, a = 255) => { const i = (y * N + x) * 4; img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2]; img.data[i + 3] = a; };
  let maxY = 0, minX = N, maxX = 0;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (filled(x, y)) { maxY = Math.max(maxY, y); minX = Math.min(minX, x); maxX = Math.max(maxX, x); }
  for (let x = minX + 4; x <= maxX - 2; x++) for (const [yy, a] of [[maxY + 3, 110], [maxY + 5, 70]]) if (yy < N && !filled(x, yy)) put(x, yy, [15, 15, 36], a);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (filled(x, y)) continue;
    for (const [dx, dy] of [[0, 1], [1, 0], [-1, 0], [0, -1]]) {
      const q = filled(x + dx, y + dy);
      if (q) { put(x, y, rgb(RAMPS[q.ramp].o)); break; }
    }
  }
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) { const p = filled(x, y); if (p) put(x, y, rgb(RAMPS[p.ramp][p.t])); }
  g.putImageData(img, 0, 0);
  return out;
}

const ICONS = {
  // General tab: a rolled parchment with three lines of text
  scroll: [
    [rect(5, 3, 18, 19), 'cream'],
    [rect(7, 7, 16, 8), 'gold'], [rect(7, 11, 16, 12), 'gold'], [rect(7, 15, 12, 16), 'gold'],
    [union(ell(11.5, 3.5, 8, 2.2), rect(3.5, 3, 19.5, 4)), 'gold'],
    [union(ell(11.5, 19.5, 8, 2.2), rect(3.5, 19, 19.5, 20)), 'gold'],
  ],
  // Stats tab: three value bars, each on its track
  statBars: [
    [rect(3, 3, 20, 6), 'track'], [rect(3, 9, 20, 12), 'track'], [rect(3, 15, 20, 18), 'track'],
    [rect(3, 3, 16, 6), 'gold'], [rect(3, 9, 11, 12), 'gold'], [rect(3, 15, 19, 18), 'gold'],
  ],
  // Abilities tab: a four-pointed spark with a small one
  sparkle: [
    [star4(10.5, 13, 9.5), 'gold'],
    [star4(19, 5, 3.8), 'gold'],
  ],
  // Filter: a gold funnel
  filter: [
    [poly([[2, 3], [21.5, 3], [14, 12.5], [14, 20.5], [9.5, 22.5], [9.5, 12.5]]), 'gold'],
    [rect(2, 3, 21, 4), 'cream'],
  ],
  // Teams: a gold-rimmed heater shield with a four-pointed spark
  shield: [
    [poly([[3, 2], [21, 2], [21, 12], [18, 17.5], [12, 22.5], [6, 17.5], [3, 12]]), 'gold'],
    [poly([[5.5, 4.5], [18.5, 4.5], [18.5, 11.5], [16, 15.5], [12, 19], [8, 15.5], [5.5, 11.5]]), 'blue'],
    [star4(12, 11, 5), 'cream'],
  ],
  // Breeding: a cream egg in a straw nest, blue speckles
  egg: [
    [ell(12, 19, 10.5, 3.6), 'wood'],
    [ell(12, 10, 6, 8), 'cream'],
    [rect(9, 7, 10, 8), 'blue'], [rect(13, 11, 14, 12), 'blue'], [rect(10, 14, 11, 14), 'blue'],
    [both(ell(12, 19.5, 10.5, 3.4), rect(0, 17.5, 23, 23)), 'wood'],
  ],
  // Lairs: a stone tower with battlements, a window, a door and a red flag
  castle: [
    [rect(11, 2, 12, 6), 'wood'], [rect(13, 2, 17, 4), 'red'],
    [rect(5, 6, 8, 9), 'stone'], [rect(10, 6, 13, 9), 'stone'], [rect(15, 6, 18, 9), 'stone'],
    [rect(5, 9, 18, 21), 'stone'],
    [rect(10.5, 11, 12, 14), 'track'],
    [rect(9, 17, 13, 21), 'wood'],
  ],
  // Bestiary: a dark book, a gold band, a gold mark, pages on the right edge
  book: [
    [rect(4, 2, 19, 21), 'ink'],
    [rect(6, 6, 17, 8), 'gold'],
    [rect(10.5, 12, 12, 14.5), 'gold'],
    [rect(19, 3, 20, 20), 'cream'],
  ],
  male: [
    [ring(9.5, 14.5, 6.6, 3.4), 'gold'],
    [thick(13.5, 10.5, 19, 5, 2.8), 'gold'],
    [poly([[13, 2.5], [21.5, 2.5], [21.5, 11]]), 'gold'],
  ],
  female: [
    [ring(12, 8.5, 6.6, 3.4), 'gold'],
    [rect(10.5, 14, 13.5, 21), 'gold'],
    [rect(7, 17, 17, 19.5), 'gold'],
  ],
};


// ---- the gold set: every UI icon is gold, with dark engraved lines where the outline alone is not enough.
// Only the element ("type") icons keep their own colour. Run: cd tool/icons && node ../pixel_icons/gold_glyphs.js
const ellR = (cx, cy, rx, ry, t) => minus(ell(cx, cy, rx, ry), ell(cx, cy, rx - t, ry - t));
const clipY = (fn, y1) => (x, y) => fn(x, y) && y < y1;
const star5 = (cx, cy, ro, ri) => {
  const p = [];
  for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? ri : ro; p.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); }
  return poly(p);
};
const rays = (cx, cy, r0, r1, n, w) => union(...Array.from({ length: n }, (_, i) => { const a = (i * 2 * Math.PI) / n; return thick(cx + r0 * Math.cos(a), cy + r0 * Math.sin(a), cx + r1 * Math.cos(a), cy + r1 * Math.sin(a), w); }));
const T = 'track', Gd = 'gold', Cr = 'cream';
const MORE = {
  paw: [[ell(5, 10.5, 2.4, 3.2), Gd], [ell(9.5, 5.5, 2.4, 3.2), Gd], [ell(14.5, 5.5, 2.4, 3.2), Gd], [ell(19, 10.5, 2.4, 3.2), Gd], [ell(12, 16.5, 6.6, 5.2), Gd]],
  trash: [[poly([[5, 8], [19, 8], [17.5, 21.5], [6.5, 21.5]]), Gd], [rect(3, 5, 20, 7), Gd], [rect(9, 2, 14, 4), Gd], [rect(9, 11, 9, 18), T], [rect(12, 11, 12, 18), T], [rect(15, 11, 15, 18), T]],
  checkCircle: [[ell(12, 12, 10, 10), Gd], [thick(7, 12.5, 10.5, 16, 2.6), T], [thick(10.5, 16, 17, 8.5, 2.6), T]],
  info: [[ell(12, 12, 10, 10), Gd], [rect(11, 10, 12, 17), T], [rect(11, 6, 12, 7.5), T]],
  error: [[ell(12, 12, 10, 10), Gd], [rect(11, 6, 12, 13.5), T], [rect(11, 16, 12, 17.5), T]],
  help: [[ell(12, 12, 10, 10), Gd], [ring(12, 9.5, 4.4, 2.2), T], [rect(8, 10, 10.5, 14), Gd], [rect(11, 12.5, 12.5, 15), T], [rect(11, 17, 12.5, 18.5), T]],
  question: [[ell(12, 12, 10, 10), Gd], [ring(12, 9.5, 4.4, 2.2), T], [rect(8, 10, 10.5, 14), Gd], [rect(11, 12.5, 12.5, 15), T], [rect(11, 17, 12.5, 18.5), T]],
  box: [[rect(3, 3, 20, 20), Gd], [rect(6, 6, 17, 17), T]],
  boxOn: [[rect(3, 3, 20, 20), Gd], [rect(6, 6, 17, 17), T], [thick(8, 12, 11, 15, 2.4), Gd], [thick(11, 15, 16, 8, 2.4), Gd]],
  groups: [[clipY(ell(12, 19, 6.5, 6), 21), Gd], [clipY(ell(4.5, 18.5, 4, 4), 21), Gd], [clipY(ell(19.5, 18.5, 4, 4), 21), Gd], [ell(12, 8, 3.6, 3.6), Gd], [ell(4.5, 11, 2.4, 2.4), Gd], [ell(19.5, 11, 2.4, 2.4), Gd]],
  house: [[rect(5, 12, 18, 21), Cr], [poly([[2, 12], [12, 3], [22, 12]]), Gd], [rect(16, 4, 18, 8), Gd], [rect(10, 15, 13, 21), T]],
  hammer: [[thick(6, 19, 15, 10, 2.8), Cr], [thick(12, 4, 19, 11, 6), Gd]],
  refresh: [[(x, y) => ring(12, 13, 9, 5.5)(x, y) && !(x > 13 && y < 11), Gd], [poly([[13, 1.5], [21, 6.5], [13, 11.5]]), Gd]],
  bell: [[ell(12, 10, 6.5, 7), Gd], [poly([[4, 18], [20, 18], [17.5, 10], [6.5, 10]]), Gd], [rect(3, 17, 20, 19), Cr], [ell(12, 21, 2.2, 1.4), Gd], [rect(11, 1.5, 12, 3), Gd]],
  crate: [[rect(3, 5, 20, 20), Gd], [rect(3, 11, 20, 12), T], [rect(11, 5, 12, 20), T]],
  sword: [[thick(4, 20, 8, 16, 2.4), 'wood'], [thick(6, 13, 11, 18, 2.6), Gd], [thick(9, 15, 20, 4, 3.2), Cr]],
  clock: [[ell(12, 12, 10, 10), Gd], [ell(12, 12, 7.2, 7.2), Cr], [rect(11, 7, 12, 12.5), T], [thick(12, 12, 16, 14, 1.8), T]],
  backpack: [[ell(11.5, 9, 6.5, 6), Gd], [rect(5, 9, 18, 21), Gd], [rect(9, 2, 14, 4), Gd], [rect(8, 15, 15, 20), Cr], [rect(5, 12, 18, 12), T]],
  compass: [[ell(12, 12, 10, 10), Gd], [ell(12, 12, 7.4, 7.4), T], [poly([[12, 4.5], [15, 12], [9, 12]]), Gd], [poly([[12, 19.5], [15, 12], [9, 12]]), Cr]],
  person: [[ell(12, 7, 4.2, 4.2), Gd], [clipY(ell(12, 20, 8, 8), 21.5), Gd]],
  door: [[ell(11.5, 8, 6.5, 6), Gd], [rect(5, 8, 18, 21), Gd], [rect(11, 4, 12, 20), T], [rect(14, 13, 15.5, 14.5), Cr]],
  chart: [[rect(3, 13, 7, 20), Gd], [rect(9, 8, 13, 20), Gd], [rect(15, 3, 19, 20), Gd]],
  chartBars: [[rect(3, 13, 7, 20), Gd], [rect(9, 8, 13, 20), Gd], [rect(15, 3, 19, 20), Gd]],
  medal: [[poly([[5, 2], [10, 2], [14, 11], [9, 13]]), Cr], [poly([[19, 2], [14, 2], [10, 11], [15, 13]]), Cr], [ell(12, 16, 6.6, 6.6), Gd], [star4(12, 16, 3.6), T]],
  ball: [[ell(12, 12, 10, 10), Cr], [both(ell(12, 12, 10, 10), rect(0, 0, 23, 11)), Gd], [rect(2, 11, 21, 12.5), T], [ell(12, 12, 3, 3), Cr], [ell(12, 12, 1.4, 1.4), T]],
  balance: [[rect(3, 6, 20, 7), Gd], [rect(11, 3, 12, 20), Gd], [rect(7, 20, 16, 21), Gd], [poly([[2, 14], [9, 14], [5.5, 19]]), Cr], [poly([[14, 14], [21, 14], [17.5, 19]]), Cr], [thick(5.5, 7, 5.5, 14, 1), T], [thick(17.5, 7, 17.5, 14, 1), T]],
  tag: [[poly([[3, 4], [13, 4], [21, 12], [13, 20], [3, 20]]), Gd], [ell(7.5, 12, 1.9, 1.9), T]],
  chat: [[rect(2, 3, 21, 16), Gd], [poly([[5, 15], [11, 15], [5, 21]]), Gd], [rect(6, 7, 17, 8), T], [rect(6, 11, 13, 12), T]],
  globe: [[ell(12, 12, 10, 10), Gd], [rect(2, 11, 21, 12), T], [ellR(12, 12, 4.5, 10, 1.3), T]],
  picture: [[rect(2, 4, 21, 19), Gd], [rect(4, 6, 19, 17), Cr], [poly([[4, 17], [10, 9], [15, 17]]), Gd], [ell(16, 9.5, 2, 2), Gd]],
  hex: [[poly([[12, 1.5], [21, 6.5], [21, 17.5], [12, 22.5], [3, 17.5], [3, 6.5]]), Gd], [poly([[12, 6], [17, 9], [17, 15], [12, 18], [7, 15], [7, 9]]), T]],
  coin: [[ell(12, 12, 10, 10), Gd], [ellR(12, 12, 7.5, 7.5, 1.4), T], [star4(12, 12, 3.6), T]],
  gear: [[ell(12, 12, 7.6, 7.6), Gd], [rays(12, 12, 6, 10, 8, 3.4), Gd], [ell(12, 12, 3, 3), T]],
  hourglass: [[poly([[5, 3], [19, 3], [12, 12]]), Gd], [poly([[5, 21], [19, 21], [12, 12]]), Gd], [rect(4, 2, 19, 3), Cr], [rect(4, 21, 19, 22), Cr], [poly([[9, 5], [15, 5], [12, 9]]), Cr], [poly([[8, 20], [16, 20], [12, 16]]), Cr]],
  trophy: [[poly([[6, 3], [18, 3], [16, 12], [12, 15], [8, 12]]), Gd], [ring(5.5, 7, 3.4, 1.8), Gd], [ring(18.5, 7, 3.4, 1.8), Gd], [rect(11, 14, 12, 18), Gd], [rect(7, 18, 16, 21), Gd]],
  map: [[rect(2, 4, 21, 19), Cr], [rect(8, 4, 8, 19), T], [rect(15, 4, 15, 19), T], [thick(10, 9, 14, 14, 2), Gd], [thick(14, 9, 10, 14, 2), Gd]],
  tasks: [[rect(4, 3, 19, 21), Cr], [rect(8, 1, 15, 4), Gd], [rect(7, 8, 16, 9), Gd], [rect(7, 12, 16, 13), Gd], [rect(7, 16, 12, 17), Gd]],
  // ---- element icons keep their colour, in the same style
  flame: [[poly([[12, 1.5], [15.5, 7], [19.5, 13], [18.5, 19], [12, 22.5], [5.5, 19], [4.5, 13], [8, 8.5], [10, 12]]), 'orange'], [ell(12, 17.5, 3.6, 4.6), 'yellow']],
  sprout: [[rect(11, 10, 12, 21), 'green'], [poly([[11, 13], [2, 8], [5, 3], [11, 8]]), 'green'], [poly([[12, 11], [21, 6], [19, 2], [12, 6]]), 'green'], [ell(12, 21, 6.5, 1.8), 'wood']],
  bolt: [[poly([[14, 1], [5, 13], [11, 13], [8, 23], [19, 9], [13, 9]]), 'yellow']],
  drop: [[ell(12, 15.5, 6.6, 6.6), 'water'], [poly([[12, 1.5], [17.8, 12.5], [6.2, 12.5]]), 'water'], [rect(8.5, 14, 9.5, 17.5), Cr]],
  stone: [[poly([[4, 19], [3, 12], [8, 6], [15, 5], [21, 11], [21, 19], [17, 21.5], [8, 21.5]]), 'rock'], [thick(11, 9, 13, 14, 1.2), T], [thick(13, 14, 16, 15, 1.2), T]],
  sun: [[rays(12, 12, 6.5, 10.5, 8, 2.2), 'yellow'], [ell(12, 12, 5.8, 5.8), 'yellow']],
  moon: [[minus(ell(12, 12, 9.5, 9.5), ell(16.5, 9.5, 7.8, 7.8)), 'violet']],
  star: [[star5(12, 12.5, 10.5, 4.6), 'yellow']],
};
Object.assign(ICONS, MORE);

// Icons whose outline already reads: the old drawing's silhouette becomes gold (one pixel off the edge, the render adds the outline back).
const AUTO = ['x', 'right', 'left', 'up', 'down', 'plus', 'minus', 'check', 'arrowDown', 'arrowLeft', 'arrowRight', 'arrowUp', 'caretDown', 'caretUp', 'sort', 'search', 'swapH', 'pencil', 'heart', 'lock', 'bookmark', 'flag', 'crown', 'medical', 'move', 'starO', 'swords', 'sparkles', 'forward', 'rewind', 'play', 'playBack', 'pause', 'volume', 'power', 'banned', 'wand', 'pickaxe', 'axe', 'saw', 'shades'];
const face = (extra) => [[ell(12, 12, 10, 10), Gd], ...extra];
const MORE2 = {
  faceCold: face([[rect(7.5, 9, 9, 11.5), T], [rect(15, 9, 16.5, 11.5), T], [thick(7, 17, 9.5, 15.5, 1), T], [thick(9.5, 15.5, 12, 17, 1), T], [thick(12, 17, 14.5, 15.5, 1), T], [thick(14.5, 15.5, 17, 17, 1), T], [rect(4.5, 14, 6, 16), Cr], [rect(18, 14, 19.5, 16), Cr]]),
  faceFear: face([[ell(8.5, 10, 2.2, 2.6), Cr], [ell(15.5, 10, 2.2, 2.6), Cr], [ell(8.5, 10, 0.9, 1.2), T], [ell(15.5, 10, 0.9, 1.2), T], [ell(12, 16.5, 2.4, 3), T]]),
  faceSleep: face([[rect(6.5, 10, 10, 11), T], [rect(14, 10, 17.5, 11), T], [rect(10, 16, 14, 17), T], [rect(17, 3, 21, 4), Cr], [thick(21, 4, 17, 8, 1), Cr], [rect(17, 8, 21, 9), Cr]]),
  crystalBlue: [[poly([[12, 1.5], [19, 8], [17, 21.5], [7, 21.5], [5, 8]]), Gd], [thick(5, 8, 19, 8, 0.9), T], [thick(12, 1.5, 9, 8, 0.9), T], [thick(12, 1.5, 15, 8, 0.9), T], [thick(9, 8, 10, 21, 0.9), T], [thick(15, 8, 14, 21, 0.9), T]],
  crystalCyan: [[poly([[12, 1.5], [19, 8], [17, 21.5], [7, 21.5], [5, 8]]), Gd], [thick(5, 8, 19, 8, 0.9), T], [thick(12, 1.5, 9, 8, 0.9), T], [thick(12, 1.5, 15, 8, 0.9), T], [thick(9, 8, 10, 21, 0.9), T], [thick(15, 8, 14, 21, 0.9), T]],
  gem: [[poly([[6, 3], [18, 3], [22, 9], [12, 21], [2, 9]]), Gd], [thick(2, 9, 22, 9, 0.9), T], [thick(8, 3, 6.5, 9, 0.9), T], [thick(16, 3, 17.5, 9, 0.9), T], [thick(6.5, 9, 12, 21, 0.9), T], [thick(17.5, 9, 12, 21, 0.9), T]],
  frame: [[rect(2, 2, 21, 21), Gd], [rect(5, 5, 18, 18), T], [rect(6, 6, 17, 17), Cr]],
  grid: [[rect(2, 2, 21, 21), Gd], [rect(11, 2, 12, 21), T], [rect(2, 11, 21, 12), T]],
  target: [[ell(12, 12, 10, 10), Gd], [ellR(12, 12, 7, 7, 1.2), T], [ell(12, 12, 4.4, 4.4), Gd], [ell(12, 12, 1.8, 1.8), T]],
  stopwatch: [[rect(10, 1.5, 13, 4), Gd], [rect(17, 4, 19, 6), Gd], [ell(12, 13, 9, 9), Gd], [ell(12, 13, 6.4, 6.4), Cr], [rect(11.5, 8, 12.5, 13.5), T], [thick(12, 13, 15, 15, 1.2), T]],
  clay: [[poly([[2, 20], [6, 11], [12, 7], [18, 11], [22, 20]]), Gd], [thick(8, 14, 11, 15.5, 0.9), T], [thick(13, 12.5, 17, 15, 0.9), T], [thick(7, 18, 12, 17.5, 0.9), T]],
  coal: [[ell(7, 16, 5, 4.5), Gd], [ell(16.5, 16, 5.5, 4.5), Gd], [ell(11.5, 9.5, 5, 4.5), Gd], [rect(6, 14, 7, 15), Cr], [rect(10, 7.5, 11, 8.5), Cr], [rect(15, 14, 16, 15), Cr]],
  sand: [[poly([[1, 20], [7, 12], [12, 10], [17, 12], [23, 20]]), Gd], [rect(8, 16, 9, 17), T], [rect(13, 14, 14, 15), T], [rect(16, 18, 17, 19), T], [rect(5, 18, 6, 19), T]],
  lime: [[rect(3, 12, 20, 20), Cr], [rect(6, 4, 17, 12), Gd], [rect(3, 16, 20, 16.5), T]],
  salt: [[rect(8, 5, 15, 21), Cr], [rect(7, 2, 16, 5), Gd], [rect(10, 8, 10.7, 8.7), T], [rect(13, 10, 13.7, 10.7), T], [rect(10, 13, 10.7, 13.7), T], [rect(13, 16, 13.7, 16.7), T]],
  ice: [[rect(3, 3, 20, 20), Cr], [rect(3, 3, 20, 4), Gd], [thick(6, 17, 15, 8, 1.1), Gd], [thick(8, 19, 12, 15, 0.9), Gd]],
  sponge: [[rect(3, 6, 20, 19), Gd], [ell(8, 10, 1.6, 1.4), T], [ell(15, 9, 1.4, 1.6), T], [ell(11.5, 14, 1.8, 1.4), T], [ell(17, 15, 1.2, 1.2), T], [ell(6.5, 15.5, 1.2, 1.2), T]],
  clipboard: [[rect(4, 3, 19, 21), Gd], [rect(7, 6, 16, 19), Cr], [rect(8, 1, 15, 4), Gd], [rect(9, 9, 14, 9.7), T], [rect(9, 12, 14, 12.7), T], [rect(9, 15, 12, 15.7), T]],
  battery: [[rect(5, 5, 18, 21), Gd], [rect(9, 2, 14, 5), Gd], [rect(8, 17, 15, 18.5), Cr], [rect(8, 12.5, 15, 14), Cr], [rect(8, 8, 15, 9.5), Cr]],
  nut: [[poly([[12, 1.5], [20, 6], [20, 18], [12, 22.5], [4, 18], [4, 6]]), Gd], [ell(12, 12, 4.2, 4.2), T]],
  moai: [[poly([[7, 2], [17, 2], [18, 10], [17, 22], [7, 22], [6, 10]]), Gd], [rect(7.5, 8, 16.5, 9), T], [rect(11, 10, 13, 15), T], [rect(8.5, 18, 15.5, 19), T]],
  road: [[poly([[9, 2], [15, 2], [22, 22], [2, 22]]), Gd], [rect(11.4, 4, 12.6, 7), T], [rect(11.2, 10, 12.8, 13.5), T], [rect(11, 17, 13, 21), T]],
  roadOff: [[poly([[9, 2], [15, 2], [22, 22], [2, 22]]), Gd], [rect(11.4, 4, 12.6, 7), T], [thick(5, 8, 19, 20, 3.2), T], [thick(5, 8, 19, 20, 1.6), Cr], [thick(19, 8, 5, 20, 3.2), T], [thick(19, 8, 5, 20, 1.6), Cr]],
  eye: [[ell(12, 12, 10.5, 6.5), Cr], [ell(12, 12, 4.6, 4.6), Gd], [ell(12, 12, 2, 2), T]],
  eyeOff: [[ell(12, 12, 10.5, 6.5), Cr], [ell(12, 12, 4.6, 4.6), Gd], [ell(12, 12, 2, 2), T], [thick(4, 20, 20, 4, 3.2), T], [thick(4, 20, 20, 4, 1.6), Gd]],
  brick: [[rect(2, 6, 21, 18), Gd], [rect(2, 12, 21, 12.8), T], [rect(8, 6, 8.8, 11.5), T], [rect(15, 13, 15.8, 18), T]],
  wood: [[ell(7.5, 16, 5.2, 5.2), Cr], [ell(16.5, 16, 5.2, 5.2), Cr], [ell(12, 8.5, 5.2, 5.2), Cr], [ellR(7.5, 16, 3, 3, 0.9), T], [ellR(16.5, 16, 3, 3, 0.9), T], [ellR(12, 8.5, 3, 3, 0.9), T]],
  skull: [[ell(12, 10, 8, 8), Gd], [rect(8, 14, 15, 20), Gd], [ell(8.5, 10, 2.2, 2.6), T], [ell(15.5, 10, 2.2, 2.6), T], [rect(11, 14, 12, 16), T], [rect(10, 18, 10.7, 20), T], [rect(13, 18, 13.7, 20), T]],
  tent: [[poly([[12, 2], [22, 21], [2, 21]]), Gd], [poly([[12, 11], [16, 21], [8, 21]]), T], [thick(12, 2, 12, 11, 0.9), T]],
  warning: [[poly([[12, 2], [22.5, 21], [1.5, 21]]), Gd], [rect(11.2, 8.5, 12.8, 15), T], [rect(11.2, 17, 12.8, 18.7), T]],
  testtube: [[rect(8, 2, 15, 21), Gd], [rect(7, 2, 16, 3.5), Cr], [rect(8, 12, 15, 21), Cr]],
  meat: [[ell(10, 12, 8.5, 7), Gd], [ell(10, 12, 3, 2.5), T], [thick(15, 15, 20, 20, 3), Cr], [ell(20.5, 20.5, 2.2, 2.2), Cr]],
  tent2: [],
};
delete MORE2.tent2;
ICONS.medical = [[rect(8.5, 2.5, 14.5, 20.5), Gd], [rect(2.5, 8.5, 20.5, 14.5), Gd]];
Object.assign(ICONS, MORE2);

const RENDERS = path.resolve(__dirname, '../../docs/renders/icons');
const origDir = path.join(__dirname, 'orig_icons');
// A silhouette from the 320 px 3D render (alpha), cropped and fitted into the 48 grid (room left for outline + shadow).
const loadMask = async (k) => {
  const { loadImage } = require('../icons/node_modules/@napi-rs/canvas');
  const rp = path.join(RENDERS, k + '.png');
  let im, solidAt;
  if (fs.existsSync(rp)) im = await loadImage(rp); else im = await loadImage(path.join(origDir, k + '.webp'));
  const W = im.width, H = im.height;
  const c = createCanvas(W, H), g = c.getContext('2d');
  g.drawImage(im, 0, 0);
  const d = g.getImageData(0, 0, W, H).data;
  let x0 = W, y0 = H, x1 = 0, y1 = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (d[(y * W + x) * 4 + 3] > 128) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  const bw = x1 - x0 + 1, bh = y1 - y0 + 1, box = 40, k2 = Math.min(box / bw, box / bh);
  const ox = Math.round((N - bw * k2) / 2), oy = Math.round(2 + (box - bh * k2) / 2);
  const fit = createCanvas(N, N), fg = fit.getContext('2d');
  fg.drawImage(c, x0, y0, bw, bh, ox, oy, bw * k2, bh * k2);
  const fd = fg.getImageData(0, 0, N, N).data;
  const fn = (x, y) => x >= 0 && y >= 0 && x < N && y < N && fd[(y * N + x) * 4 + 3] > 128;
  fn.raw = true;
  return fn;
};

(async () => {
  const all = fs.readdirSync(OUT).filter((f) => f.endsWith('.webp')).map((f) => f.replace('.webp', ''));
  for (const k of all) if (!ICONS[k]) ICONS[k] = [[await loadMask(k), 'gold']];
  for (const [k, layers] of Object.entries(ICONS)) {
    fs.writeFileSync(path.join(OUT, k + '.webp'), render(layers).toBuffer('image/webp', 100));
  }
  console.log('wrote', Object.keys(ICONS).length, 'icons');
  if (process.argv[2]) { // preview sheet
    const keys = Object.keys(ICONS), cols = 16, cell = 56;
    const sheet = createCanvas(cols * cell, Math.ceil(keys.length / cols) * (cell + 10));
    const sc = sheet.getContext('2d');
    sc.fillStyle = '#2b4a3d'; sc.fillRect(0, 0, sheet.width, sheet.height);
    sc.imageSmoothingEnabled = false; sc.font = '8px sans-serif'; sc.fillStyle = '#fff';
    keys.forEach((k, i) => { const x = (i % cols) * cell, y = Math.floor(i / cols) * (cell + 10); sc.drawImage(render(ICONS[k]), x + 4, y + 2, 48, 48); sc.fillText(k, x + 4, y + 58); });
    fs.writeFileSync(process.argv[2], sheet.toBuffer('image/png'));
  }
})();


