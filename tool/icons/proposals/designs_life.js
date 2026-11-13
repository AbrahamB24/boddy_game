// Batch 8: animals, people, wearables. Species share a style set (10 presentations each).
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const build = (fn, rows) => rows.map(([n, d, o]) => [n, d, (c) => fn(c, o)]);
const opt = (n, d, o) => [n, d, o];

const eyes = (c, cx, cy, s, mood, sp = 0.38) => {
  const dx = s * sp, y = cy - s * 0.1;
  for (const d of [-dx, dx]) {
    if (mood === 'sleep') c.shape(path([[cx + d - 1.6, y], [cx + d, y + 1], [cx + d + 1.6, y]], 0.9), 'black', 'flat');
    else if (mood === 'happy') c.shape(path([[cx + d - 1.6, y + 0.6], [cx + d, y - 0.6], [cx + d + 1.6, y + 0.6]], 0.9), 'black', 'flat');
    else { c.shape(ell(cx + d, y, 1.3, 1.5), 'black', 'flat'); c.px(cx + d - 0.5, y - 1, 'face', 4); }
  }
};
const SP = {
  fox: { body: 'orange', draw: (c, x, y, s, m) => {
    for (const k of [-1, 1]) c.shape(poly([[x + k * s * 0.9, y - s * 0.2], [x + k * s * 0.8, y - s * 1.15], [x + k * s * 0.2, y - s * 0.7]]), 'orange', 'diag');
    c.shape(ell(x, y, s, s * 0.85), 'orange', 'orb'); c.shape(poly([[x - s, y + s * 0.1], [x, y + s * 0.85], [x + s, y + s * 0.1], [x, y + s * 0.35]]), 'face', 'diag'); c.shape(ell(x, y + s * 0.45, 1, 0.8), 'black', 'flat'); eyes(c, x, y, s, m); } },
  horse: { body: 'wood', draw: (c, x, y, s, m) => {
    c.shape(rect(x - s * 0.9, y - s * 0.9, x - s * 0.3, y + s * 0.5), 'black2', 'diag'); for (const k of [-1, 1]) c.shape(poly([[x + k * s * 0.6, y - s * 0.7], [x + k * s * 0.5, y - s * 1.2], [x + k * s * 0.15, y - s * 0.7]]), 'wood', 'diag');
    c.shape(ell(x, y, s * 0.75, s), 'wood', 'orb'); c.shape(ell(x, y + s * 0.6, s * 0.5, s * 0.38), 'bread', 'orb'); c.px(x - 1, y + s * 0.62, 'black', 1); c.px(x + 1, y + s * 0.62, 'black', 1); eyes(c, x, y - s * 0.1, s * 0.9, m, 0.5); } },
  camel: { body: 'sand', draw: (c, x, y, s, m) => {
    for (const k of [-1, 1]) c.shape(ell(x + k * s * 0.5, y - s * 0.75, s * 0.42, s * 0.48), 'sand', 'orb');
    c.shape(ell(x, y + s * 0.1, s * 0.85, s * 0.9), 'sand', 'orb'); c.shape(ell(x, y + s * 0.55, s * 0.55, s * 0.36), 'bread', 'orb'); c.px(x - 1, y + s * 0.55, 'black', 1); c.px(x + 1, y + s * 0.55, 'black', 1); eyes(c, x, y, s, m); } },
  turtle: { body: 'green', draw: (c, x, y, s, m) => {
    c.shape(ell(x, y + s * 0.4, s * 1.1, s * 0.85), 'forest', 'orb'); c.shape(ell(x, y + s * 0.4, s * 0.45, s * 0.35), 'leaf', 'flat', 0.1); for (const k of [-1, 1]) c.shape(ell(x + k * s * 0.8, y + s * 0.5, s * 0.25, s * 0.25), 'leaf', 'flat');
    c.shape(ell(x, y - s * 0.15, s * 0.62, s * 0.58), 'leaf', 'orb'); eyes(c, x, y - s * 0.15, s * 0.9, m); } },
  snail: { body: 'orange', draw: (c, x, y, s, m) => {
    c.shape(ell(x, y + s * 0.6, s * 1.1, s * 0.35), 'sand', 'vert'); c.shape(ell(x - s * 0.85, y + s * 0.2, s * 0.35, s * 0.55), 'sand', 'orb'); c.shape(path([[x - s * 0.95, y - s * 0.2], [x - s * 1.05, y - s * 0.7]], 0.7), 'sand', 'flat'); c.shape(path([[x - s * 0.7, y - s * 0.2], [x - s * 0.55, y - s * 0.7]], 0.7), 'sand', 'flat');
    c.shape(ell(x + s * 0.2, y - s * 0.05, s * 0.75, s * 0.75), 'orange', 'orb'); c.shape(ring(x + s * 0.2, y - s * 0.05, s * 0.5, s * 0.34), 'red', 'flat'); c.shape(ell(x + s * 0.2, y - s * 0.05, s * 0.18, s * 0.18), 'red', 'flat'); c.px(x - s * 0.9, y + s * 0.1, 'black', 1); } },
  beaver: { body: 'wood', draw: (c, x, y, s, m) => {
    for (const k of [-1, 1]) c.shape(ell(x + k * s * 0.7, y - s * 0.7, s * 0.28, s * 0.28), 'wood', 'orb');
    c.shape(ell(x, y, s, s * 0.85), 'wood', 'orb'); c.shape(ell(x, y + s * 0.4, s * 0.55, s * 0.4), 'bread', 'orb'); c.shape(rect(x - 1.2, y + s * 0.5, x + 1.2, y + s * 0.85), 'face', 'vert'); c.shape(ell(x, y + s * 0.3, 1.1, 0.8), 'black', 'flat'); eyes(c, x, y, s, m); } },
  chick: { body: 'bolt', draw: (c, x, y, s, m) => {
    c.shape(path([[x, y - s * 0.8], [x - s * 0.2, y - s * 1.2]], 0.8), 'bolt', 'flat'); c.shape(path([[x + s * 0.2, y - s * 0.8], [x + s * 0.4, y - s * 1.15]], 0.8), 'bolt', 'flat');
    c.shape(ell(x, y, s, s * 0.9), 'bolt', 'orb'); c.shape(poly([[x - s * 0.3, y + s * 0.2], [x + s * 0.3, y + s * 0.2], [x, y + s * 0.6]]), 'orange', 'diag'); eyes(c, x, y - s * 0.1, s, m, 0.5); } },
  moai: { body: 'stone', draw: (c, x, y, s, m) => {
    c.shape(poly([[x - s * 0.6, y - s], [x + s * 0.6, y - s], [x + s * 0.75, y + s * 0.95], [x - s * 0.75, y + s * 0.95]]), 'stone', 'diag'); c.shape(rect(x - s * 0.6, y - s * 0.3, x + s * 0.6, y - s * 0.1), 'stone', 'vert', 0.35);
    c.shape(rect(x - 1, y - s * 0.1, x + 1, y + s * 0.55), 'stone2', 'diag'); c.shape(rect(x - s * 0.4, y + s * 0.7, x + s * 0.4, y + s * 0.8), 'black', 'flat', 0); for (const k of [-1, 1]) c.shape(rect(x + k * s * 0.35 - 1, y - s * 0.28, x + k * s * 0.35 + 1, y - s * 0.12), 'black', 'flat'); if (m === 'sleep') c.px(x, y, 'face', 4); } },
};
const zee = (c, x, y, s = 5) => { c.shape(rect(x, y, x + s, y + s * 0.26), 'face', 'flat'); c.shape(rect(x, y + s * 0.74, x + s, y + s), 'face', 'flat'); c.shape(thick(x + s, y + s * 0.2, x, y + s * 0.8, s * 0.26), 'face', 'flat'); };
const STYLES = [
  ['Gesicht', 'Frontal', (c, d) => d(c, 12, 12, 9, 'open')],
  ['Chibi', 'Kopf mit kleinem Körper', (c, d, sp) => { c.shape(ell(12, 20, 5.4, 3), sp.body, 'orb'); d(c, 12, 10, 7.4, 'open'); }],
  ['Im Kreis', 'Medaillon', (c, d) => { c.shape(ell(12, 12, 10.6, 10.6), 'blue', 'orb'); d(c, 12, 12, 6.4, 'open'); }],
  ['Schlafend', 'Mit Z', (c, d) => { d(c, 11, 14, 7.4, 'sleep'); zee(c, 16, 1, 5); zee(c, 20, 6, 3.4); }],
  ['Fröhlich', 'Mit Funken', (c, d) => { d(c, 12, 13, 8.4, 'happy'); sparkle(c, 21, 3, 3); sparkle(c, 3, 4, 2.2); }],
  ['Zwei', 'Zwei Gesichter', (c, d) => { d(c, 7, 14, 5.4, 'open'); d(c, 17, 11, 5.4, 'happy'); }],
  ['Mit Herz', 'Verliebt', (c, d) => { d(c, 12, 14, 7.6, 'open'); c.shape(heart(12, 4, 3.4), 'red', 'orb'); }],
  ['Mit Krone', 'Königlich', (c, d) => { d(c, 12, 14, 7.6, 'open'); c.shape(poly([[7, 6], [7, 1], [9.6, 3.6], [12, 0], [14.4, 3.6], [17, 1], [17, 6]]), 'gold', 'vert'); }],
  ['Groß', 'Füllt das Feld', (c, d) => d(c, 12, 13, 11, 'open')],
  ['Im Rahmen', 'Quadratischer Rahmen', (c, d) => { c.shape(rect(1, 1, 23, 23), 'iron', 'diag'); c.shape(rect(3, 3, 21, 21), 'sand', 'vert', 0.1); d(c, 12, 12, 6.8, 'open'); }],
];
const animal = (key) => STYLES.map(([n, desc, fn]) => [n, desc, (c) => fn(c, SP[key].draw, SP[key])]);

// ---- paw ----
const pawFn = (c, o) => {
  const col = o.col || 'paw';
  if (o.kind === 'badge') c.shape(ell(12, 12, 10.6, 10.6), o.bg || 'blue', 'orb');
  const s = o.kind === 'badge' ? 0.74 : 1; const cx = 12, cy = o.kind === 'badge' ? 13 : 14;
  c.shape(either(ell(cx, cy + 2 * s, 5.4 * s, 4.4 * s), either(ell(cx - 3.4 * s, cy - 0.6 * s, 3 * s, 2.8 * s), ell(cx + 3.4 * s, cy - 0.6 * s, 3 * s, 2.8 * s))), col, 'orb');
  for (const [dx, dy, rx] of [[-5.4, -4, 2], [-1.9, -7, 2.1], [1.9, -7, 2.1], [5.4, -4, 2]]) c.shape(ell(cx + dx * s, cy + dy * s, rx * s, rx * 1.2 * s), col, 'orb');
  if (o.heartPad) c.shape(heart(cx, cy + 2.4 * s, 3 * s), 'pink', 'orb');
};
const paw = build(pawFn, [opt('Pfote', 'Orange', {}), opt('Mit Herz', 'Herz-Ballen', { heartPad: 1 }), opt('Im Kreis', 'Medaillon', { kind: 'badge' }), opt('Braun', 'Bärentatze', { col: 'wood' }), opt('Grau', 'Wolfstatze', { col: 'steel' }), opt('Rosa', 'Rosa', { col: 'pink', heartPad: 1 }), opt('Schwarz', 'Katzentatze', { col: 'black' }), opt('Grün', 'Grün', { col: 'leaf' }), opt('Blau im Kreis', 'Blaue Tatze, Gold', { kind: 'badge', col: 'cyan', bg: 'navy' }), opt('Gold', 'Goldpfote', { col: 'gold' })]);

// ---- egg ----
const eggFn = (c, o) => {
  const col = o.col || 'face';
  if (o.nest) { c.shape(ell(12, 19, 11, 4), 'bark', 'vert'); for (const x of [4, 9, 15, 20]) c.line(x, 17, x + 2, 21, 'wood', 4); }
  const y = o.nest ? 11 : 12.4;
  c.shape(either(ell(12, y + 2, 7.4, 8), poly([[12, y - 9], [18, y + 1], [6, y + 1]])), col, 'orb');
  if (o.spots) for (const [x, yy] of [[9, y], [14, y + 3], [11, y + 6], [15, y - 2]]) c.shape(ell(x, yy, 1.4, 1.2), o.spots, 'orb');
  if (o.stripe) c.shape(path([[5, y + 2], [9, y], [12, y + 2], [15, y], [19, y + 2]], 1.4), o.stripe, 'flat');
  if (o.crack) { c.shape(path([[6, y + 1], [9, y - 1], [11, y + 1], [14, y - 1], [18, y + 1]], 1), 'black', 'flat'); c.shape(poly([[12, y - 9], [14, y - 5], [11, y - 6]]), 'black', 'flat', 0.2); }
  if (o.glow) sparkle(c, 12, y + 1, 4);
};
const egg = build(eggFn, [opt('Ei', 'Hell', {}), opt('Gefleckt', 'Braune Flecken', { spots: 'wood', col: 'sand' }), opt('Gerissen', 'Schlüpft', { crack: 1 }), opt('Golden', 'Goldei', { col: 'gold', glow: 1 }), opt('Im Nest', 'Auf Stroh', { nest: 1 }), opt('Blau', 'Blaues Ei', { col: 'cyan', spots: 'blue' }), opt('Rosa', 'Rosa Ei', { col: 'pink', stripe: 'face' }), opt('Grün', 'Grün gefleckt', { col: 'leaf', spots: 'forest' }), opt('Violett', 'Streifen', { col: 'purple', stripe: 'face' }), opt('Rot', 'Rot, Funke', { col: 'red', glow: 1, spots: 'orange' })]);

// ---- person ----
const personFn = (c, o) => {
  const skin = o.skin || 'skin', cx = o.cx ?? 12, sc = o.sc ?? 1;
  const head = (x, y, r) => { c.shape(ell(x, y, r, r * 1.05), skin, 'orb'); c.shape(both(ell(x, y - r * 0.2, r * 1.1, r * 0.95), rect(0, 0, 24, y - r * 0.1)), o.hair || 'bark', 'vert'); c.px(x - r * 0.4, y + r * 0.1, 'black', 1); c.px(x + r * 0.4, y + r * 0.1, 'black', 1); };
  const body = (x, y, w, h) => c.shape(poly([[x - w, y + h], [x - w * 0.8, y + 1], [x - w * 0.3, y], [x + w * 0.3, y], [x + w * 0.8, y + 1], [x + w, y + h]]), o.shirt || 'blue', 'diag');
  if (o.group) { body(5, 14, 4.4, 8); head(5, 9, 3); body(19, 14, 4.4, 8); head(19, 9, 3); c.shape(ell(12, 22, 5, 2), 'black', 'flat', 0.4); body(12, 12, 5.6, 10); head(12, 7, 3.8); return; }
  body(cx, 13, 8, 10); head(cx, 8, 5);
  if (o.hat === 'helmet') { c.shape(both(ell(cx, 7, 6, 5.4), rect(0, 0, 24, 8)), 'bolt', 'orb'); c.shape(rect(cx - 7, 7, cx + 7, 8.6), 'bolt', 'vert'); }
  if (o.hat === 'cap') c.shape(poly([[cx - 6, 7], [cx - 5, 2], [cx + 5, 2], [cx + 6, 7], [cx + 10, 8], [cx + 6, 8.4]]), 'red', 'diag');
  if (o.hat === 'crown') c.shape(poly([[cx - 4, 4], [cx - 4, 0], [cx - 2, 2], [cx, -1], [cx + 2, 2], [cx + 4, 0], [cx + 4, 4]]), 'gold', 'vert');
  if (o.plus) { c.shape(ell(19, 18, 4.6, 4.6), 'green', 'orb'); c.shape(rect(18.2, 15, 19.8, 21), 'face', 'flat'); c.shape(rect(16, 17.2, 22, 18.8), 'face', 'flat'); }
  if (o.glasses) c.shape(rect(cx - 5, 7, cx + 5, 9.4), 'black', 'flat');
};
const person = build(personFn, [opt('Person', 'Blau', {}), opt('Rot', 'Rotes Hemd', { shirt: 'red', hair: 'wood' }), opt('Grün', 'Grünes Hemd', { shirt: 'green', hair: 'black' }), opt('Mit Kappe', 'Rote Kappe', { hat: 'cap' }), opt('Mit Krone', 'König', { hat: 'crown', shirt: 'purple' }), opt('Violett', 'Violett', { shirt: 'purple', hair: 'orange' }), opt('Orange', 'Orange', { shirt: 'orange', hair: 'bark', skin: 'clay' }), opt('Grau', 'Neutral', { shirt: 'steel', hair: 'iron' }), opt('Blond', 'Blond', { hair: 'goldl', shirt: 'cyan' }), opt('Dunkel', 'Dunkel', { shirt: 'iron', skin: 'clay', hair: 'black' })]);
const groups = build(personFn, [opt('Gruppe', 'Drei Personen', { group: 1 }), opt('Rot-Blau', 'Bunt', { group: 1, shirt: 'red' }), opt('Grün', 'Grün', { group: 1, shirt: 'green' }), opt('Violett', 'Violett', { group: 1, shirt: 'purple' }), opt('Orange', 'Orange', { group: 1, shirt: 'orange', hair: 'wood' }), opt('Cyan', 'Cyan', { group: 1, shirt: 'cyan', hair: 'goldl' }), opt('Grau', 'Grau', { group: 1, shirt: 'steel' }), opt('Gold', 'Gold', { group: 1, shirt: 'gold', hair: 'wood' }), opt('Dunkelrot', 'Dunkelrot', { group: 1, shirt: 'ruby', hair: 'black' }), opt('Dunkel', 'Eisen', { group: 1, shirt: 'iron' })]);
const personAdd = build(personFn, [opt('Mit Plus', 'Grün', { plus: 1, cx: 9 }), opt('Rot', 'Rotes Hemd', { plus: 1, cx: 9, shirt: 'red' }), opt('Kappe', 'Mit Kappe', { plus: 1, cx: 9, hat: 'cap' }), opt('Violett', 'Violett', { plus: 1, cx: 9, shirt: 'purple', hair: 'orange' }), opt('Grau', 'Grau', { plus: 1, cx: 9, shirt: 'steel' }), opt('Orange', 'Orange', { plus: 1, cx: 9, shirt: 'orange' }), opt('Blond', 'Blond', { plus: 1, cx: 9, hair: 'goldl', shirt: 'cyan' }), opt('Krone', 'Mit Krone', { plus: 1, cx: 9, hat: 'crown', shirt: 'purple' }), opt('Dunkel', 'Dunkel', { plus: 1, cx: 9, skin: 'clay', hair: 'black', shirt: 'iron' }), opt('Grün', 'Grünes Hemd', { plus: 1, cx: 9, shirt: 'green' })]);
const worker = build(personFn, [opt('Bauarbeiter', 'Gelber Helm', { hat: 'helmet', shirt: 'orange' }), opt('Blau', 'Blaues Hemd', { hat: 'helmet', shirt: 'blue' }), opt('Rot', 'Roter Helm', { hat: 'cap', shirt: 'orange' }), opt('Grün', 'Grün', { hat: 'helmet', shirt: 'green' }), opt('Grau', 'Grau', { hat: 'helmet', shirt: 'steel' }), opt('Violett', 'Violett', { hat: 'helmet', shirt: 'purple' }), opt('Mit Brille', 'Schutzbrille', { hat: 'helmet', shirt: 'orange', glasses: 1 }), opt('Dunkel', 'Dunkel', { hat: 'helmet', skin: 'clay', hair: 'black', shirt: 'orange' }), opt('Weiß', 'Weiß', { hat: 'helmet', shirt: 'face' }), opt('Rot-Weiß', 'Rot', { hat: 'helmet', shirt: 'red' })]);

// ---- gi (karate) ----
const giFn = (c, o) => {
  c.shape(ell(12, 6, 4.6, 4.8), 'skin', 'orb'); c.shape(both(ell(12, 4.6, 5, 4.4), rect(0, 0, 24, 5.4)), 'black', 'vert'); c.px(10.4, 7, 'black', 1); c.px(13.6, 7, 'black', 1);
  c.shape(poly([[4, 22], [6, 11], [10, 10], [12, 14], [14, 10], [18, 11], [20, 22]]), o.col || 'face', 'diag'); c.shape(poly([[10, 10], [12, 14], [14, 10], [12, 11.6]]), 'skin', 'diag'); c.shape(rect(5, 16, 19, 18.4), o.belt || 'black', 'vert');
  if (o.kick) c.shape(thick(15, 18, 22, 13, 3), o.col || 'face', 'diag');
};
const gi = build(giFn, [opt('Kampfanzug', 'Schwarzer Gürtel', {}), opt('Rot', 'Roter Gürtel', { belt: 'red' }), opt('Blau', 'Blauer Anzug', { col: 'blue', belt: 'face' }), opt('Mit Tritt', 'In Bewegung', { kick: 1 }), opt('Gelb', 'Gelber Gürtel', { belt: 'bolt' }), opt('Grün', 'Grüner Gürtel', { belt: 'green' }), opt('Schwarz', 'Schwarzer Anzug', { col: 'black', belt: 'red' }), opt('Orange', 'Orange', { belt: 'orange' }), opt('Rot-Anzug', 'Rot', { col: 'red', belt: 'black' }), opt('Grau', 'Grauer Anzug', { col: 'steel', belt: 'iron' })]);

// ---- robot ----
const robotFn = (c, o) => {
  const col = o.col || 'steel';
  c.shape(rect(11.2, 1, 12.8, 5), 'iron', 'flat'); c.shape(ell(12, 1.6, 1.8, 1.8), o.ant || 'red', 'orb'); c.shape(rect(4, 5, 20, 17), col, 'diag'); c.shape(rect(2, 8, 4, 14), 'iron', 'diag'); c.shape(rect(20, 8, 22, 14), 'iron', 'diag');
  c.shape(rect(6, 8, 18, 14), 'black', 'flat'); if (o.eyes === 'round') { c.shape(ell(9.4, 11, 2, 2), o.eye || 'cyan', 'orb'); c.shape(ell(14.6, 11, 2, 2), o.eye || 'cyan', 'orb'); } else { c.shape(rect(7, 10, 11, 12.4), o.eye || 'cyan', 'flat'); c.shape(rect(13, 10, 17, 12.4), o.eye || 'cyan', 'flat'); }
  c.shape(rect(7, 19, 17, 22), col, 'vert'); c.shape(rect(8, 15, 16, 16.6), 'iron', 'flat'); if (o.heart) c.shape(heart(12, 20.4, 1.6), 'red', 'flat');
};
const robot = build(robotFn, [opt('Roboter', 'Cyan-Augen', {}), opt('Runde Augen', 'Rund', { eyes: 'round' }), opt('Rot', 'Rote Augen', { eye: 'red', ant: 'bolt' }), opt('Gold', 'Goldgehäuse', { col: 'gold', eye: 'black2' }), opt('Blau', 'Blaues Gehäuse', { col: 'blue' }), opt('Grün', 'Grünes Gehäuse', { col: 'green', eye: 'bolt' }), opt('Mit Herz', 'Freundlich', { heart: 1, eyes: 'round', col: 'pink' }), opt('Dunkel', 'Eisen', { col: 'iron', eye: 'red' }), opt('Orange', 'Orange', { col: 'orange', eye: 'face' }), opt('Violett', 'Lila', { col: 'purple', eyes: 'round', eye: 'bolt' })]);

// ---- shades ----
const shadesFn = (c, o) => {
  const col = o.col || 'black';
  if (o.kind === 'round') { c.shape(ell(7, 12, 5, 5), col, 'orb'); c.shape(ell(17, 12, 5, 5), col, 'orb'); c.shape(path([[11, 11], [13, 11]], 1.4), 'iron', 'flat'); c.px(5, 10, 'face', 4); c.px(15, 10, 'face', 4); return; }
  c.shape(poly([[2, 8], [11, 8], [10, 15], [5, 16], [2, 12]]), col, 'diag'); c.shape(poly([[13, 8], [22, 8], [22, 12], [19, 16], [14, 15]]), col, 'diag'); c.shape(rect(10, 9, 14, 10.4), 'iron', 'flat'); c.shape(path([[3, 8], [1, 5]], 1), 'iron', 'flat'); c.shape(path([[21, 8], [23, 5]], 1), 'iron', 'flat');
  if (o.shine) { sparkle(c, 6, 11, 2.4); sparkle(c, 18, 11, 2.4); }
};
const shades = build(shadesFn, [opt('Sonnenbrille', 'Schwarz', {}), opt('Rund', 'Runde Gläser', { kind: 'round' }), opt('Mit Glanz', 'Funkelnd', { shine: 1 }), opt('Blau', 'Blaue Gläser', { col: 'blue', shine: 1 }), opt('Rund Rot', 'Rot, rund', { kind: 'round', col: 'red' }), opt('Orange', 'Orange Gläser', { col: 'orange' }), opt('Grün', 'Grüne Gläser', { col: 'green', shine: 1 }), opt('Violett', 'Lila Gläser', { col: 'purple' }), opt('Rund Gold', 'Rund, Gold', { kind: 'round', col: 'gold' }), opt('Eisgrau', 'Grau', { col: 'steel' })]);

// ---- gradcap ----
const capFn = (c, o) => {
  const col = o.col || 'black';
  c.shape(poly([[12, 3], [23, 8], [12, 13], [1, 8]]), col, 'vert', -0.1); c.shape(poly([[6, 11], [6, 16], [12, 19], [18, 16], [18, 11], [12, 14]]), o.base || 'iron', 'diag'); c.shape(path([[21, 9], [21, 17]], 0.9), o.tassel || 'gold', 'flat'); c.shape(ell(21, 18, 1.4, 1.8), o.tassel || 'gold', 'orb');
  if (o.star) c.shape(star(12, 8, 2.6, 1.2), 'goldl', 'flat'); if (o.scroll) { c.shape(rect(3, 19, 12, 22), 'paper', 'vert'); }
};
const gradcap = build(capFn, [opt('Doktorhut', 'Schwarz mit Quaste', {}), opt('Blau', 'Blauer Hut', { col: 'blue', base: 'navy' }), opt('Mit Stern', 'Stern', { star: 1 }), opt('Rot', 'Roter Hut', { col: 'red', base: 'ruby' }), opt('Mit Urkunde', 'Mit Rolle', { scroll: 1 }), opt('Grün', 'Grüner Hut', { col: 'green', base: 'forest', tassel: 'bolt' }), opt('Violett', 'Lila', { col: 'purple', base: 'navy' }), opt('Gold', 'Goldene Quaste', { col: 'iron', tassel: 'goldl', star: 1 }), opt('Weiß', 'Heller Hut', { col: 'face', base: 'steel', tassel: 'red' }), opt('Orange', 'Orange', { col: 'orange', base: 'brown', tassel: 'face' })]);

// ---- footprints ----
const printFn = (c, o) => {
  const col = o.col || 'clay';
  const foot = (x, y, flip) => { c.shape(ell(x, y + 2, 3.2, 4.4), col, 'orb'); c.shape(ell(x, y - 4, 2.4, 2.8), col, 'orb'); for (const [dx, dy] of [[-2.4, -6.4], [-0.4, -7.4], [1.6, -7], [3, -5.6]]) c.shape(ell(x + dx * (flip ? -1 : 1), y + dy + 1, 0.8, 0.9), col, 'orb'); };
  if (o.kind === 'one') { foot(12, 14); return; }
  if (o.kind === 'shoe') { for (const [x, y] of [[8, 17], [16, 9]]) { c.shape(poly([[x - 3, y + 5], [x - 3, y - 1], [x - 1, y - 5], [x + 2, y - 5], [x + 3, y - 1], [x + 3, y + 5]]), col, 'orb'); c.shape(rect(x - 3, y + 2, x + 3, y + 4), 'iron', 'flat'); } return; }
  foot(8, 15, false); foot(16, 9, true);
};
const footprints = build(printFn, [opt('Fußspuren', 'Zwei Abdrücke', {}), opt('Ein Abdruck', 'Barfuß', { kind: 'one' }), opt('Stiefelspur', 'Profilsohle', { kind: 'shoe', col: 'bark' }), opt('Grau', 'Grau', { col: 'steel' }), opt('Blau', 'Blau', { col: 'blue' }), opt('Grün', 'Grün', { col: 'leaf' }), opt('Rot', 'Rot', { col: 'red' }), opt('Gold', 'Gold', { col: 'gold' }), opt('Schlamm', 'Dunkelbraun', { col: 'bark', kind: 'one' }), opt('Violett', 'Violett', { col: 'purple' })]);

// ---- boot & shoe ----
const bootFn = (c, o) => {
  const col = o.col || 'leather', sole = o.sole || 'leatherd';
  if (o.kind === 'shoe') { c.shape(poly([[3, 12], [10, 10], [13, 14], [21, 15], [21, 19], [3, 19]]), col, 'diag'); c.shape(rect(3, 18, 21, 21), sole, 'vert'); c.shape(path([[10, 11], [12, 14]], 0.9), 'face', 'flat'); c.shape(path([[13, 12], [15, 15]], 0.9), 'face', 'flat'); return; }
  c.shape(poly([[7, 2], [14, 2], [14, 13], [21, 16], [21, 20], [7, 20]]), col, 'diag'); c.shape(rect(7, 2, 14, 4.4), o.cuff || 'leatherd', 'vert'); c.shape(rect(6, 19, 22, 22), sole, 'vert'); if (o.buckle) c.shape(rect(8, 9, 13, 11), 'gold', 'flat'); if (o.fur) c.shape(rect(6, 1, 15, 4), 'face', 'vert');
};
const boot = build(bootFn, [opt('Stiefel', 'Leder', {}), opt('Mit Schnalle', 'Goldschnalle', { buckle: 1 }), opt('Pelzbesatz', 'Winterstiefel', { fur: 1 }), opt('Schwarz', 'Schwarz', { col: 'black', sole: 'iron', cuff: 'iron' }), opt('Rot', 'Rot', { col: 'red', sole: 'iron', buckle: 1 }), opt('Grün', 'Grün', { col: 'green', sole: 'bark' }), opt('Blau', 'Blau', { col: 'blue', sole: 'iron' }), opt('Grau', 'Stahl', { col: 'steel', sole: 'iron', cuff: 'iron' }), opt('Violett', 'Lila', { col: 'purple', sole: 'iron', fur: 1 }), opt('Gold', 'Goldstiefel', { col: 'gold', sole: 'brass', cuff: 'brass' })]);
const shoe = build((c, o) => bootFn(c, { ...o, kind: 'shoe' }), [opt('Schuh', 'Leder', {}), opt('Blau', 'Sportschuh', { col: 'blue', sole: 'face' }), opt('Rot', 'Rot', { col: 'red', sole: 'face' }), opt('Weiß', 'Weiß', { col: 'face', sole: 'steel' }), opt('Schwarz', 'Schwarz', { col: 'black', sole: 'iron' }), opt('Grün', 'Grün', { col: 'green', sole: 'face' }), opt('Gelb', 'Gelb', { col: 'bolt', sole: 'iron' }), opt('Violett', 'Lila', { col: 'purple', sole: 'face' }), opt('Orange', 'Orange', { col: 'orange', sole: 'bark' }), opt('Gold', 'Gold', { col: 'gold', sole: 'brass' })]);

const CONCEPTS = [
  { cat: 'Leute', key: 'fox', name: 'Fuchs', designs: animal('fox') },
  { cat: 'Leute', key: 'horse', name: 'Pferd', designs: animal('horse') },
  { cat: 'Leute', key: 'camel', name: 'Kamel', designs: animal('camel') },
  { cat: 'Leute', key: 'turtle', name: 'Schildkröte', designs: animal('turtle') },
  { cat: 'Leute', key: 'snail', name: 'Schnecke', designs: animal('snail') },
  { cat: 'Leute', key: 'beaver', name: 'Biber', designs: animal('beaver') },
  { cat: 'Leute', key: 'chick', name: 'Küken', designs: animal('chick') },
  { cat: 'Leute', key: 'moai', name: 'Moai', designs: animal('moai') },
  { cat: 'Leute', key: 'paw', name: 'Pfote', designs: paw },
  { cat: 'Leute', key: 'egg', name: 'Ei', designs: egg },
  { cat: 'Leute', key: 'person', name: 'Person', designs: person },
  { cat: 'Leute', key: 'groups', name: 'Gruppe', designs: groups },
  { cat: 'Leute', key: 'personAdd', name: 'Person hinzufügen', designs: personAdd },
  { cat: 'Leute', key: 'worker', name: 'Arbeiter', designs: worker },
  { cat: 'Leute', key: 'gi', name: 'Kämpfer', designs: gi },
  { cat: 'Leute', key: 'robot', name: 'Roboter', designs: robot },
  { cat: 'Leute', key: 'shades', name: 'Sonnenbrille', designs: shades },
  { cat: 'Leute', key: 'gradcap', name: 'Doktorhut', designs: gradcap },
  { cat: 'Leute', key: 'footprints', name: 'Fußspuren', designs: footprints },
  { cat: 'Leute', key: 'boot', name: 'Stiefel', designs: boot },
  { cat: 'Leute', key: 'shoe', name: 'Schuh', designs: shoe },
];
module.exports = { CONCEPTS };
