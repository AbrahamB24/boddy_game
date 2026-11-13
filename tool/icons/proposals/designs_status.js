// Batch 3: status / condition icons.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');

const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const bang = (c, cx, top, bot, r = 'black') => { c.shape(rect(cx - 1.1, top, cx + 1.1, bot - 3.2), r, 'flat'); c.shape(rect(cx - 1.1, bot - 1.6, cx + 1.1, bot), r, 'flat'); };
const Z = (c, x, y, s, r = 'face') => { c.shape(rect(x, y, x + s, y + s * 0.26), r, 'vert'); c.shape(rect(x, y + s * 0.74, x + s, y + s), r, 'vert'); c.shape(thick(x + s, y + s * 0.2, x, y + s * 0.8, s * 0.26), r, 'diag'); };
const flake = (c, cx, cy, r, col = 'ice', w = 1.6) => {
  for (let k = 0; k < 3; k++) { const a = (k * Math.PI) / 3, dx = Math.cos(a) * r, dy = Math.sin(a) * r; c.shape(thick(cx - dx, cy - dy, cx + dx, cy + dy, w), col, 'flat'); }
  for (let k = 0; k < 6; k++) { const a = (k * Math.PI) / 3, bx = cx + Math.cos(a) * r * 0.62, by = cy + Math.sin(a) * r * 0.62;
    for (const s of [-1, 1]) { const b = a + s * 0.9; c.shape(thick(bx, by, bx + Math.cos(b) * r * 0.32, by + Math.sin(b) * r * 0.32, 1.1), col, 'flat'); } }
  c.shape(ell(cx, cy, 1.6, 1.6), col, 'orb');
};

// ---- anger ----
const anger = [
  ['Zornmarke', 'Vier rote Bögen', (c) => { for (const [x, y] of [[2, 2], [22, 2], [2, 22], [22, 22]]) { const q = ring(x, y, 9, 5); const sx = x < 12 ? 1 : -1, sy = y < 12 ? 1 : -1; c.shape(both(q, (px, py) => (px - x) * sx > 0 && (py - y) * sy > 0), 'red', 'orb'); } }],
  ['Wütendes Gesicht', 'Rot mit Brauen', (c) => { c.shape(ell(12, 12, 10, 10), 'red', 'orb'); c.shape(poly([[4, 6], [10, 9], [10, 11], [4, 8]]), 'black', 'flat'); c.shape(poly([[20, 6], [14, 9], [14, 11], [20, 8]]), 'black', 'flat'); c.shape(ell(8, 12, 1.6, 1.6), 'face', 'flat'); c.shape(ell(16, 12, 1.6, 1.6), 'face', 'flat'); c.shape(rect(7, 16, 17, 18.5), 'black', 'flat'); for (const x of [9, 11, 13, 15]) c.line(x, 16, x, 18, 'face', 4); }],
  ['Dampf', 'Zwei Dampfwolken', (c) => { c.shape(ell(7, 9, 4.6, 4), 'ice', 'orb'); c.shape(ell(17, 9, 4.6, 4), 'ice', 'orb'); c.shape(ell(12, 6, 3.8, 3.4), 'ice', 'orb'); c.shape(rect(4, 15, 20, 20), 'red', 'vert'); c.line(6, 14, 7, 12, 'steel', 1); c.line(17, 14, 18, 12, 'steel', 1); }],
  ['Faust', 'Geballte Faust', (c) => { c.shape(rect(5, 9, 19, 19), 'skin', 'diag'); for (const x of [6.5, 10, 13.5, 17]) c.shape(ell(x, 9.5, 2.2, 2.6), 'skin', 'orb'); c.shape(rect(8, 3, 17, 7), 'skin', 'vert', 0.15); c.line(7, 13, 18, 13, 'skin', 1); c.shape(thick(2, 12, 6, 17, 3), 'skin', 'diag', 0.1); }],
  ['Zacken-Rufzeichen', 'Roter Stern mit !', (c) => { c.shape(star(12, 12, 11, 6, 9), 'red', 'orb'); bang(c, 12, 6, 18, 'face'); }],
  ['Zornwolke', 'Dunkle Wolke mit Augen', (c) => { c.shape(ell(8, 10, 5.4, 5), 'iron', 'orb'); c.shape(ell(16, 10, 5.4, 5), 'iron', 'orb'); c.shape(ell(12, 8, 6, 5), 'iron', 'orb'); c.shape(rect(4, 10, 20, 15), 'iron', 'vert', -0.1); c.shape(poly([[7, 8], [11, 10], [7, 11]]), 'red', 'flat'); c.shape(poly([[17, 8], [13, 10], [17, 11]]), 'red', 'flat'); c.shape(poly([[11, 16], [13, 16], [10, 21], [8, 20]]), 'bolt', 'flat'); }],
  ['Teufelchen', 'Kopf mit Hörnern', (c) => { c.shape(poly([[4, 8], [2, 1], [8, 5]]), 'red', 'diag'); c.shape(poly([[20, 8], [22, 1], [16, 5]]), 'red', 'diag'); c.shape(ell(12, 13, 9, 8), 'purple', 'orb'); c.shape(poly([[5, 10], [10, 12], [5, 12]]), 'bolt', 'flat'); c.shape(poly([[19, 10], [14, 12], [19, 12]]), 'bolt', 'flat'); c.shape(rect(8, 17, 16, 19), 'black', 'flat'); }],
  ['Rote Augen', 'Zornig funkelnd', (c) => { c.shape(ell(12, 12, 10.5, 8), 'black', 'orb'); c.shape(poly([[3, 8], [10, 11], [8, 14], [3, 12]]), 'red', 'orb'); c.shape(poly([[21, 8], [14, 11], [16, 14], [21, 12]]), 'red', 'orb'); c.px(7, 11, 'face', 4); c.px(17, 11, 'face', 4); }],
  ['Kochender Topf', 'Überkochend', (c) => { c.shape(ell(12, 17, 9, 5), 'iron', 'orb'); c.shape(rect(3, 11, 21, 18), 'iron', 'vert'); c.shape(ell(12, 11, 9, 2.4), 'red', 'orb'); c.shape(ell(7, 7, 2.2, 2.2), 'red', 'orb'); c.shape(ell(14, 5, 2.8, 2.8), 'red', 'orb'); c.shape(ell(18, 8, 1.8, 1.8), 'red', 'orb'); }],
  ['Fangzähne', 'Knurrendes Maul', (c) => { c.shape(ell(12, 12, 10, 8), 'red', 'orb'); c.shape(ell(12, 13, 7.6, 4.6), 'black', 'flat'); c.shape(poly([[7, 9], [10, 9], [8.5, 14]]), 'face', 'diag'); c.shape(poly([[14, 9], [17, 9], [15.5, 14]]), 'face', 'diag'); c.shape(poly([[10, 17], [14, 17], [12, 13]]), 'face', 'diag'); }],
];

// ---- dizzy ----
const ringStars = (c, cx, cy, rx, ry, n, s, a0 = 0) => { for (let i = 0; i < n; i++) { const a = a0 + (i * 2 * Math.PI) / n; c.shape(star(cx + rx * Math.cos(a), cy + ry * Math.sin(a), s, s * 0.45, 5), 'bolt', 'orb'); } };
const dizzy = [
  ['Sternenkranz', 'Fünf Sterne im Kreis', (c) => ringStars(c, 12, 12, 8, 4.4, 5, 3.6, -1.2)],
  ['Spirale', 'Hypnose-Wirbel', (c) => { const pts = []; for (let t = 0; t < 22; t++) { const a = t * 0.55, r = 1 + t * 0.42; pts.push([12 + r * Math.cos(a), 12 + r * Math.sin(a)]); } c.shape(path(pts, 2.2), 'purple', 'diag'); }],
  ['Drei Sterne', 'Sterne um den Kopf', (c) => { c.shape(star(12, 5, 4.4, 2, 5), 'bolt', 'orb'); c.shape(star(5, 14, 4.4, 2, 5), 'bolt', 'orb'); c.shape(star(19, 14, 4.4, 2, 5), 'bolt', 'orb'); c.shape(ell(12, 17, 4, 2.6), 'ice', 'orb'); }],
  ['Sternenschauer', 'Funkelnde Sterne', (c) => { c.shape(star(12, 12, 6, 2.6, 5), 'bolt', 'orb'); sparkle(c, 4, 5, 3); sparkle(c, 20, 6, 2.6); sparkle(c, 5, 19, 2.4); sparkle(c, 19, 19, 3); }],
  ['Kreuzaugen', 'Zwei X-Augen', (c) => { for (const x of [7, 17]) { c.shape(thick(x - 3.4, 8.6, x + 3.4, 15.4, 2.2), 'black', 'flat'); c.shape(thick(x + 3.4, 8.6, x - 3.4, 15.4, 2.2), 'black', 'flat'); } c.shape(rect(8, 19, 16, 20.2), 'black', 'flat'); }],
  ['Wirbelaugen', 'Zwei Spiralen', (c) => { for (const x of [7, 17]) { c.shape(ell(x, 12, 5, 5), 'face', 'orb'); c.shape(ring(x, 12, 3.4, 2.2), 'black', 'flat'); c.shape(ell(x, 12, 1, 1), 'black', 'flat'); } }],
  ['Beule', 'Beule mit Sternen', (c) => { c.shape(ell(12, 15, 9, 6.6), 'skin', 'orb'); c.shape(ell(12, 11, 5, 4.4), 'red', 'orb', 0.1); c.shape(star(5, 5, 3.2, 1.4, 5), 'bolt', 'orb'); c.shape(star(19, 5, 3.2, 1.4, 5), 'bolt', 'orb'); c.shape(star(12, 3, 2.6, 1.2, 5), 'bolt', 'orb'); }],
  ['Kometen', 'Kreisende Schweife', (c) => { for (const [x, y, a] of [[18, 7, 0], [5, 10, 1], [14, 19, 2]]) { c.shape(poly([[x, y], [x - 7, y - 1 - a], [x - 7, y + 3 - a]]), 'bolt', 'diag', 0.2); c.shape(star(x, y, 3.2, 1.4, 5), 'bolt', 'orb'); } }],
  ['Heiligenschein', 'Ring über dem Kopf', (c) => { c.shape(ring(12, 8, 8, 5.6), 'gold', 'orb'); sparkle(c, 12, 17, 4); sparkle(c, 5, 15, 2); sparkle(c, 19, 15, 2); }],
  ['Kreispunkte', 'Wirbelnde Punkte', (c) => { for (let i = 0; i < 8; i++) { const a = i * 0.785, r = 1.2 + i * 0.28; c.shape(ell(12 + 8 * Math.cos(a), 12 + 8 * Math.sin(a), r + 0.4, r + 0.4), 'cyan', 'orb'); } }],
];

// ---- zzz ----
const zzz = [
  ['Z-Folge', 'Drei wachsende Z', (c) => { Z(c, 2, 14, 6); Z(c, 8, 8, 8); Z(c, 15, 1, 10); }],
  ['Sprechblase', 'Z in Blase', (c) => { c.shape(poly([[2, 3], [22, 3], [22, 16], [14, 16], [8, 21], [8, 16], [2, 16]]), 'ice', 'diag'); Z(c, 7, 6, 10, 'blue'); }],
  ['Mond und Z', 'Mondsichel', (c) => { c.shape(minus(ell(10, 12, 9, 9), ell(15, 10, 8, 8)), 'bolt', 'orb'); Z(c, 15, 4, 7); Z(c, 11, 13, 5); }],
  ['Kissen', 'Kissen mit Z', (c) => { c.shape(poly([[2, 8], [22, 8], [20, 20], [4, 20]]), 'face', 'diag'); c.shape(rect(2, 8, 22, 10), 'ice', 'vert'); Z(c, 8, 11, 8, 'blue'); }],
  ['Schlafmütze', 'Zipfelmütze', (c) => { c.shape(poly([[3, 20], [11, 3], [20, 8], [21, 20]]), 'blue', 'diag'); c.shape(rect(3, 17, 21, 21), 'face', 'vert'); c.shape(ell(19, 8, 3, 3), 'face', 'orb'); Z(c, 8, 8, 7, 'face'); }],
  ['Bett', 'Bett mit Z', (c) => { c.shape(rect(2, 12, 22, 17), 'blue', 'vert'); c.shape(rect(2, 9, 8, 13), 'face', 'diag'); c.shape(rect(2, 17, 4, 21), 'wood', 'diag'); c.shape(rect(20, 17, 22, 21), 'wood', 'diag'); Z(c, 13, 2, 7, 'ice'); }],
  ['Großes Z', 'Ein großes Z mit Glanz', (c) => { Z(c, 4, 4, 15, 'ice'); sparkle(c, 19, 5, 3); }],
  ['Geschlossenes Auge', 'Auge zu', (c) => { c.shape(both(ell(12, 8, 10, 8), rect(0, 8, 24, 24)), 'face', 'vert'); c.shape(path([[2, 9], [7, 14], [12, 15.5], [17, 14], [22, 9]], 1.6), 'black', 'flat'); for (const x of [6, 9, 12, 15, 18]) c.line(x, 15, x + (x - 12) * 0.3, 19, 'black', 1); Z(c, 15, 1, 6, 'ice'); }],
  ['Z-Punkte', 'Zs in Reihe', (c) => { Z(c, 1, 8, 7); Z(c, 8.5, 8, 7); Z(c, 16, 8, 7); for (const x of [4, 12, 20]) c.shape(ell(x, 19, 1.4, 1.4), 'ice', 'orb'); }],
  ['Nachtwolke', 'Wolke mit Z', (c) => { c.shape(ell(8, 11, 5.6, 5), 'steel', 'orb'); c.shape(ell(16, 11, 5.6, 5), 'steel', 'orb'); c.shape(ell(12, 8, 6, 5.4), 'steel', 'orb'); c.shape(rect(4, 11, 20, 16), 'iron', 'vert', -0.1); Z(c, 9, 6, 7, 'face'); c.shape(star(20, 3, 2, 0.8, 4), 'bolt', 'flat'); }],
];

// ---- snow ----
const snow = [
  ['Schneeflocke', 'Sechsarmig', (c) => flake(c, 12, 12, 10)],
  ['Eiskristall', 'Sechseck', (c) => { c.shape(poly([[12, 2], [20, 7], [20, 17], [12, 22], [4, 17], [4, 7]]), 'cyan', 'diag'); c.shape(poly([[12, 2], [20, 7], [12, 12], [4, 7]]), 'ice', 'vert', -0.2); c.line(12, 12, 12, 21, 'cyan', 1); }],
  ['Schneemann', 'Drei Kugeln', (c) => { c.shape(ell(12, 17, 6.4, 5.4), 'face', 'orb'); c.shape(ell(12, 9, 4.6, 4.2), 'face', 'orb'); c.shape(rect(8, 3, 16, 5), 'black', 'diag'); c.shape(rect(9.4, 0.6, 14.6, 3.2), 'black', 'diag'); c.px(10, 8, 'black', 1); c.px(14, 8, 'black', 1); c.shape(poly([[12, 9], [16, 10], [12, 10.8]]), 'orange', 'flat'); }],
  ['Eissplitter', 'Zackiger Eisblock', (c) => { c.shape(poly([[2, 21], [5, 8], [8, 14], [11, 2], [15, 13], [18, 7], [22, 21]]), 'cyan', 'diag'); c.line(11, 4, 11, 20, 'ice', 4); c.line(5, 10, 5, 19, 'ice', 3); }],
  ['Schneewolke', 'Wolke mit Flocken', (c) => { c.shape(ell(8, 8, 5, 4.4), 'steel', 'orb'); c.shape(ell(16, 8, 5, 4.4), 'steel', 'orb'); c.shape(ell(12, 6, 5.6, 4.6), 'steel', 'orb'); c.shape(rect(3, 8, 21, 12), 'steel', 'vert', 0.05); for (const [x, y] of [[6, 16], [12, 19], [18, 16], [9, 22], [15, 22]]) sparkle(c, x, y, 2.2); }],
  ['Zarte Flocke', 'Dünner Stern', (c) => { for (let k = 0; k < 3; k++) { const a = (k * Math.PI) / 3; c.shape(thick(12 - Math.cos(a) * 10, 12 - Math.sin(a) * 10, 12 + Math.cos(a) * 10, 12 + Math.sin(a) * 10, 1.2), 'ice', 'flat'); } c.shape(ring(12, 12, 6, 4.8), 'cyan', 'flat'); c.shape(ell(12, 12, 2, 2), 'ice', 'orb'); }],
  ['Eiszapfen', 'Reihe von Zapfen', (c) => { c.shape(rect(2, 2, 22, 5), 'ice', 'vert'); for (const [x, h] of [[4, 12], [8, 19], [12, 9], [16, 16], [20, 11]]) c.shape(poly([[x - 2, 5], [x + 2, 5], [x, h]]), 'cyan', 'diag'); }],
  ['Schneeball', 'Kugel mit Spritzern', (c) => { c.shape(ell(12, 12, 8.4, 8.4), 'face', 'orb'); c.px(8, 9, 'cyan', 2); c.px(14, 15, 'cyan', 2); c.px(10, 15, 'cyan', 2); c.shape(ell(21, 4, 1.4, 1.4), 'face', 'orb'); c.shape(ell(3, 20, 1.4, 1.4), 'face', 'orb'); }],
  ['Eissäule', 'Hoher Kristall', (c) => { c.shape(poly([[12, 1], [17, 6], [16, 20], [12, 23], [8, 20], [7, 6]]), 'cyan', 'diag'); c.shape(poly([[12, 1], [17, 6], [12, 9], [7, 6]]), 'ice', 'vert', -0.25); c.line(12, 9, 12, 22, 'ice', 4); }],
  ['Frosthandschuh', 'Handschuh', (c) => { c.shape(rect(7, 9, 17, 19), 'blue', 'diag'); for (const x of [8, 11, 14]) c.shape(rect(x - 1, 3, x + 1.2, 10), 'blue', 'diag', 0.05); c.shape(thick(18, 11, 21, 7, 3), 'blue', 'diag', 0.1); c.shape(rect(6, 18, 18, 22), 'face', 'vert'); }],
];

// ---- wind ----
const wind = [
  ['Drei Böen', 'Geschwungene Linien', (c) => { c.shape(path([[2, 7], [14, 7], [17, 4], [20, 6]], 2), 'ice', 'diag'); c.shape(path([[2, 12], [19, 12], [22, 15], [19, 18]], 2), 'ice', 'diag'); c.shape(path([[2, 17], [11, 17], [14, 20], [11, 22]], 2), 'ice', 'diag'); }],
  ['Wirbel', 'Spirale', (c) => { const pts = []; for (let t = 0; t < 20; t++) { const a = t * 0.5, r = 1 + t * 0.5; pts.push([12 + r * Math.cos(a), 12 + r * Math.sin(a)]); } c.shape(path(pts, 2), 'ice', 'diag'); }],
  ['Windhose', 'Trichter', (c) => { c.shape(ell(12, 4, 10, 2.6), 'steel', 'orb'); c.shape(ell(12, 9, 8, 2.4), 'ice', 'orb'); c.shape(ell(12, 13, 6, 2.2), 'steel', 'orb'); c.shape(ell(12, 17, 4, 2), 'ice', 'orb'); c.shape(ell(12, 21, 2, 1.4), 'steel', 'orb'); }],
  ['Fliegendes Blatt', 'Blatt im Wind', (c) => { c.shape(poly([[10, 4], [19, 6], [17, 15], [8, 13]]), 'leaf', 'diag'); c.line(10, 6, 17, 13, 'leaf', 1); c.shape(path([[2, 17], [8, 17], [11, 20]], 1.8), 'ice', 'diag'); c.shape(path([[2, 21], [9, 21]], 1.8), 'ice', 'diag'); }],
  ['Pfeile', 'Drei Windpfeile', (c) => { for (const y of [6, 12, 18]) { c.shape(rect(2, y - 1, 15, y + 0.4), 'ice', 'vert'); c.shape(poly([[22, y - 0.3], [14, y - 3.4], [14, y + 3]]), 'ice', 'diag'); } }],
  ['Pustegesicht', 'Wolke pustet', (c) => { c.shape(ell(8, 12, 7, 7), 'steel', 'orb'); c.shape(ell(8, 12, 1.4, 1.4), 'black', 'flat'); c.shape(ell(12, 14, 1.6, 1.8), 'black', 'flat'); for (const [y, x] of [[10, 22], [14, 21], [18, 20]]) c.shape(path([[14, y], [x - 3, y], [x, y - 2]], 1.4), 'ice', 'diag'); }],
  ['Flagge', 'Wehende Fahne', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(poly([[5, 3], [12, 5], [19, 3], [22, 5], [20, 12], [14, 14], [5, 12]]), 'red', 'diag'); c.shape(poly([[5, 7], [12, 9], [20, 8], [20, 10], [12, 11], [5, 10]]), 'face', 'vert', -0.1); }],
  ['Windsack', 'Gestreift', (c) => { c.shape(rect(3, 2, 5, 22), 'iron', 'diag'); c.shape(poly([[5, 4], [21, 7], [21, 13], [5, 12]]), 'orange', 'diag'); c.shape(poly([[11, 5], [14, 6], [14, 12], [11, 12]]), 'face', 'vert'); }],
  ['Staubwolke', 'Böe mit Staub', (c) => { c.shape(path([[2, 10], [16, 10], [19, 7], [22, 9]], 2), 'ice', 'diag'); for (const [x, y, r] of [[6, 17, 2.4], [11, 15, 2], [15, 19, 2.6], [20, 16, 1.8], [9, 21, 1.6]]) c.shape(ell(x, y, r, r), 'sand', 'orb'); }],
  ['Windrad', 'Vierblatt', (c) => { c.shape(rect(11, 11, 13, 22), 'wood', 'diag'); for (const [a, b, d, e] of [[12, 12, 12, 1], [12, 12, 23, 12], [12, 12, 12, 23], [12, 12, 1, 12]]) c.shape(path([[a, b], [d, e]], 3.4), 'face', 'diag', 0.05); c.shape(ell(12, 12, 2.2, 2.2), 'iron', 'orb'); }],
];

// ---- target (target + goal) ----
const target = [
  ['Zielscheibe mit Pfeil', 'Rot-weiß', (c) => { c.shape(ell(11, 13, 9.4, 9.4), 'red', 'orb'); c.shape(ell(11, 13, 6.4, 6.4), 'face', 'orb'); c.shape(ell(11, 13, 3.4, 3.4), 'red', 'orb'); c.shape(path([[11, 13], [21, 3]], 1.4), 'wood', 'flat'); c.shape(poly([[19, 2], [22, 2], [22, 5]]), 'face', 'flat'); }],
  ['Ringe', 'Drei Ringe', (c) => { c.shape(ring(12, 12, 10, 7.4), 'red', 'orb'); c.shape(ring(12, 12, 6, 3.4), 'red', 'orb'); c.shape(ell(12, 12, 2, 2), 'red', 'orb'); }],
  ['Fadenkreuz', 'Zielfernrohr', (c) => { c.shape(ring(12, 12, 9, 7.6), 'iron', 'orb'); c.shape(rect(11.3, 1, 12.7, 23), 'black', 'flat'); c.shape(rect(1, 11.3, 23, 12.7), 'black', 'flat'); c.shape(ell(12, 12, 1.8, 1.8), 'red', 'orb'); }],
  ['Dartscheibe', 'Mit Dart', (c) => { c.shape(ell(12, 12, 10, 10), 'black', 'orb'); c.shape(ring(12, 12, 8, 5.6), 'green', 'flat', 0.1); c.shape(ring(12, 12, 4, 2.2), 'red', 'flat'); c.shape(path([[12, 12], [19, 5]], 1.2), 'steel', 'flat'); c.shape(poly([[18, 3], [22, 4], [21, 8]]), 'red', 'flat'); }],
  ['Goldener Ring', 'Gold mit Mitte', (c) => { c.shape(ell(12, 12, 10, 10), 'gold', 'orb'); c.shape(ell(12, 12, 6.6, 6.6), 'goldl', 'orb'); c.shape(ell(12, 12, 3.2, 3.2), 'red', 'orb'); }],
  ['Pfeil im Zentrum', 'Treffer', (c) => { c.shape(ell(12, 13, 9, 9), 'face', 'orb'); c.shape(ring(12, 13, 9, 7.6), 'red', 'flat'); c.shape(ring(12, 13, 5, 3.6), 'red', 'flat'); c.shape(rect(11, 13, 13, 22), 'wood', 'diag'); c.shape(poly([[8, 22], [12, 18], [16, 22]]), 'red', 'diag'); }],
  ['Auf Pfosten', 'Zielscheibe auf Ständer', (c) => { c.shape(rect(11, 12, 13, 22), 'wood', 'diag'); c.shape(rect(6, 21, 18, 22.5), 'wood', 'vert'); c.shape(ell(12, 8, 8, 6.4), 'red', 'orb'); c.shape(ell(12, 8, 5, 3.8), 'face', 'orb'); c.shape(ell(12, 8, 2, 1.6), 'red', 'orb'); }],
  ['Kompass-Ziel', 'Kreis mit Spitzen', (c) => { c.shape(ring(12, 12, 8, 6.4), 'blue', 'orb'); for (const [x, y, d, e] of [[12, 1, 12, 7], [12, 17, 12, 23], [1, 12, 7, 12], [17, 12, 23, 12]]) c.shape(path([[x, y], [d, e]], 2.2), 'blue', 'diag'); c.shape(ell(12, 12, 2.4, 2.4), 'red', 'orb'); }],
  ['Fahne im Ziel', 'Fahne auf Scheibe', (c) => { c.shape(ell(12, 17, 9, 4.4), 'red', 'orb'); c.shape(ell(12, 17, 5, 2.4), 'face', 'orb'); c.shape(rect(11, 3, 12.6, 18), 'wood', 'diag'); c.shape(poly([[12.6, 3], [20, 6], [12.6, 9]]), 'bolt', 'diag'); }],
  ['Pfeilkreuz', 'Pfeile zeigen aufs Ziel', (c) => { c.shape(ell(12, 12, 4.6, 4.6), 'red', 'orb'); for (const [a, b, d, e] of [[12, 1, 12, 6], [12, 18, 12, 23], [1, 12, 6, 12], [18, 12, 23, 12]]) c.shape(path([[a, b], [d, e]], 2), 'steel', 'diag'); c.shape(ell(12, 12, 1.4, 1.4), 'face', 'flat'); }],
];

// ---- warning ----
const warning = [
  ['Dreieck', 'Klassisches Warnschild', (c) => { c.shape(poly([[12, 2], [22, 21], [2, 21]]), 'bolt', 'diag'); bang(c, 12, 8, 19); }],
  ['Dreieck mit Rand', 'Roter Rahmen', (c) => { c.shape(poly([[12, 1], [23, 22], [1, 22]]), 'red', 'diag'); c.shape(poly([[12, 6], [19, 19], [5, 19]]), 'face', 'diag'); bang(c, 12, 9, 18); }],
  ['Raute', 'Gelbe Raute', (c) => { c.shape(poly([[12, 1], [23, 12], [12, 23], [1, 12]]), 'bolt', 'diag'); bang(c, 12, 6, 18); }],
  ['Dreieck mit Schädel', 'Giftwarnung', (c) => { c.shape(poly([[12, 2], [22, 21], [2, 21]]), 'bolt', 'diag'); c.shape(ell(12, 13, 4, 3.6), 'black', 'flat'); c.shape(rect(9.6, 14, 14.4, 17.5), 'black', 'flat'); c.px(10, 12, 'bolt', 3); c.px(14, 12, 'bolt', 3); }],
  ['Achteck', 'Stopp-Schild', (c) => { c.shape(poly([[8, 2], [16, 2], [22, 8], [22, 16], [16, 22], [8, 22], [2, 16], [2, 8]]), 'red', 'diag'); c.shape(rect(4, 10.6, 20, 13.4), 'face', 'flat'); }],
  ['Fahne', 'Rote Warnflagge', (c) => { c.shape(rect(4, 2, 6, 22), 'wood', 'diag'); c.shape(poly([[6, 3], [21, 3], [17, 8], [21, 13], [6, 13]]), 'red', 'diag'); bang(c, 12, 5, 11, 'face'); }],
  ['Schild mit !', 'Wappenform', (c) => { c.shape(poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]), 'orange', 'diag'); bang(c, 12, 6, 17, 'face'); }],
  ['Glocke', 'Alarmglocke', (c) => { c.shape(poly([[12, 3], [18, 8], [19, 16], [21, 18], [3, 18], [5, 16], [6, 8]]), 'gold', 'diag'); c.shape(ell(12, 20, 2.6, 2), 'gold', 'orb'); bang(c, 12, 7, 15, 'red'); }],
  ['Wegweiser', 'Schild am Pfosten', (c) => { c.shape(rect(11, 8, 13, 22), 'wood', 'diag'); c.shape(poly([[12, 1], [20, 7], [4, 7]]), 'bolt', 'diag'); c.shape(rect(4, 7, 20, 10), 'bolt', 'vert', 0.2); bang(c, 12, 3.4, 8, 'black'); }],
  ['Gelber Kreis', 'Rund mit !', (c) => { c.shape(ell(12, 12, 10, 10), 'bolt', 'orb'); c.shape(ring(12, 12, 10, 8.6), 'orange', 'flat'); bang(c, 12, 5, 19); }],
];

// ---- banned ----
const banned = [
  ['Verbotskreis', 'Roter Ring, Balken', (c) => { c.shape(ring(12, 12, 10.4, 7.6), 'red', 'orb'); c.shape(thick(5.4, 5.4, 18.6, 18.6, 3), 'red', 'diag'); }],
  ['Kreis mit X', 'Roter Ring, Kreuz', (c) => { c.shape(ring(12, 12, 10.4, 8), 'red', 'orb'); c.shape(thick(7, 7, 17, 17, 2.8), 'red', 'diag'); c.shape(thick(17, 7, 7, 17, 2.8), 'red', 'diag'); }],
  ['Einfahrt verboten', 'Rot mit Balken', (c) => { c.shape(ell(12, 12, 10.4, 10.4), 'red', 'orb'); c.shape(rect(5, 10, 19, 14), 'face', 'flat'); }],
  ['Fettes X', 'Großes rotes Kreuz', (c) => { c.shape(thick(3, 3, 21, 21, 5), 'red', 'diag'); c.shape(thick(21, 3, 3, 21, 5), 'red', 'diag'); }],
  ['Grauer Kreis', 'Gedämpft, Balken', (c) => { c.shape(ring(12, 12, 10.4, 7.6), 'steel', 'orb'); c.shape(thick(5.4, 5.4, 18.6, 18.6, 3), 'steel', 'diag'); }],
  ['Quadrat', 'Quadrat mit Balken', (c) => { c.shape(minus(rect(2, 2, 21, 21), rect(5, 5, 18, 18)), 'red', 'diag'); c.shape(thick(4, 19, 19, 4, 3), 'red', 'diag'); }],
  ['Schloss', 'Gesperrt', (c) => { c.shape(rect(5, 11, 18, 21), 'gold', 'diag'); c.shape(ring(11.5, 10, 5, 3), 'steel', 'orb'); c.shape(rect(6.5, 9, 16.5, 11), 'gold', 'vert'); c.shape(ell(11.5, 16, 1.6, 1.8), 'black', 'flat'); }],
  ['Ketten', 'Gekreuzte Kettenglieder', (c) => { for (const [x, y] of [[5, 5], [9, 9], [15, 15], [19, 19]]) c.shape(ring(x, y, 3.4, 1.8), 'iron', 'orb'); for (const [x, y] of [[19, 5], [15, 9], [9, 15], [5, 19]]) c.shape(ring(x, y, 3.4, 1.8), 'steel', 'orb'); }],
  ['Karte mit Balken', 'Durchgestrichen', (c) => { c.shape(rect(4, 3, 19, 21), 'face', 'diag'); c.line(7, 8, 16, 8, 'steel', 1); c.line(7, 12, 16, 12, 'steel', 1); c.shape(thick(3, 20, 20, 4, 3), 'red', 'diag'); }],
  ['Handzeichen', 'Stopphand', (c) => { c.shape(rect(6, 10, 18, 20), 'skin', 'diag'); for (const x of [7, 10.4, 13.8, 17]) c.shape(rect(x - 1.1, 3 + Math.abs(x - 12) * 0.5, x + 1.1, 11), 'skin', 'diag', 0.05); c.shape(thick(5, 14, 2, 9, 2.6), 'skin', 'diag', 0.1); }],
];

// ---- faces (family: faceFear, faceSleep, faceCold) ----
const BASE = { fear: null, sleep: null, cold: '#8fd0e8' };
const expr = (c, e, cx = 12, cy = 12) => {
  if (e === 'fear') {
    for (const dx of [-3.6, 3.6]) { c.shape(ell(cx + dx, cy - 1, 2.6, 3), 'face', 'flat'); c.shape(ell(cx + dx, cy - 0.6, 1.1, 1.3), 'black', 'flat'); }
    c.shape(ell(cx, cy + 5, 1.8, 2.4), 'black', 'flat'); c.shape(path([[cx - 6, cy - 5], [cx - 2, cy - 4]], 1.1), 'black', 'flat'); c.shape(path([[cx + 6, cy - 5], [cx + 2, cy - 4]], 1.1), 'black', 'flat');
    c.shape(ell(cx + 8, cy - 5, 1.4, 2), 'cyan', 'orb');
  } else if (e === 'sleep') {
    for (const dx of [-3.6, 3.6]) c.shape(path([[cx + dx - 2, cy - 0.5], [cx + dx, cy + 0.8], [cx + dx + 2, cy - 0.5]], 1), 'black', 'flat');
    c.shape(ell(cx + 0.5, cy + 4.6, 1.3, 1), 'black', 'flat');
    c.shape(rect(cx + 6, cy - 9, cx + 9, cy - 8), 'face', 'flat'); c.shape(path([[cx + 9, cy - 8], [cx + 6, cy - 5.6]], 1), 'face', 'flat'); c.shape(rect(cx + 6, cy - 6, cx + 9, cy - 5), 'face', 'flat');
  } else {
    for (const dx of [-3.4, 3.4]) c.shape(ell(cx + dx, cy - 1, 1.2, 1.4), 'black', 'flat');
    c.shape(path([[cx - 5, cy + 4], [cx - 2.5, cy + 5.4], [cx, cy + 4], [cx + 2.5, cy + 5.4], [cx + 5, cy + 4]], 1.2), 'black', 'flat');
    c.shape(path([[cx - 6, cy - 4.5], [cx - 2, cy - 3.4]], 1), 'black', 'flat'); c.shape(path([[cx + 6, cy - 4.5], [cx + 2, cy - 3.4]], 1), 'black', 'flat');
    c.px(cx - 7, cy + 1, 'face', 4); c.px(cx + 7, cy + 1, 'face', 4); sparkle(c, cx + 8.5, cy - 7, 2.2);
  }
};
const faceStyle = (hex, draw, ey = 12) => (c, e) => { draw(c, BASE[e] || hex); expr(c, e, 12, ey); };
const faces = [
  ['Rundgesicht', 'Gelbe Kugel', faceStyle('#f0c840', (c, h) => c.shape(ell(12, 12, 10, 10), h, 'orb'))],
  ['Blob', 'Weiches Monster', faceStyle('#9a6ad8', (c, h) => { c.shape(ell(5, 5, 2.6, 3), h, 'orb'); c.shape(ell(19, 5, 2.6, 3), h, 'orb'); c.shape(ell(12, 13, 9.6, 8.6), h, 'orb'); }, 13)],
  ['Katze', 'Mit Spitzohren', faceStyle('#e8a050', (c, h) => { c.shape(poly([[3, 10], [3, 1], [10, 6]]), h, 'diag'); c.shape(poly([[21, 10], [21, 1], [14, 6]]), h, 'diag'); c.shape(ell(12, 14, 9.6, 8), h, 'orb'); }, 13)],
  ['Kantig', 'Abgerundetes Quadrat', faceStyle('#78b8e8', (c, h) => c.shape(poly([[5, 3], [19, 3], [22, 6], [22, 18], [19, 21], [5, 21], [2, 18], [2, 6]]), h, 'diag'))],
  ['Geist', 'Weißes Gespenst', faceStyle('#f0f0f8', (c, h) => { c.shape(either(both(ell(12, 10, 9, 8), rect(0, 0, 24, 12)), rect(3, 10, 21, 20)), h, 'orb'); for (const x of [6, 12, 18]) c.shape(ell(x, 20, 3.2, 2.6), h, 'orb'); }, 10)],
  ['Schleim', 'Grüne Kuppel', faceStyle('#58c060', (c, h) => c.shape(both(ell(12, 21, 11, 17), rect(0, 0, 24, 21.5)), h, 'orb'), 15)],
  ['Kürbis', 'Orange mit Stiel', faceStyle('#e87a2a', (c, h) => { c.shape(ell(12, 13, 10.4, 8.6), h, 'orb'); c.shape(rect(11, 2, 13, 5.4), 'leaf', 'diag'); }, 13)],
  ['Ei', 'Heller Eiform', faceStyle('#f4ecd2', (c, h) => c.shape(ell(12, 13, 8.4, 10), h, 'orb'), 13)],
  ['Maske', 'Sechseck', faceStyle('#aab4c0', (c, h) => c.shape(poly([[7, 2], [17, 2], [22, 12], [17, 22], [7, 22], [2, 12]]), h, 'diag'))],
  ['Tropfenwesen', 'Wasserwesen', faceStyle('#4a9ae0', (c, h) => c.shape(either(poly([[12, 1], [20, 14], [4, 14]]), ell(12, 14, 8.6, 8.6)), h, 'orb'), 14)],
];

const CONCEPTS = [
  { cat: 'Zustände', key: 'anger', name: 'Wut', designs: anger },
  { cat: 'Zustände', key: 'dizzy', name: 'Schwindel', designs: dizzy },
  { cat: 'Zustände', key: 'zzz', name: 'Schlaf (zzz)', designs: zzz },
  { cat: 'Zustände', key: 'snow', name: 'Schnee', designs: snow },
  { cat: 'Zustände', key: 'wind', name: 'Wind', designs: wind },
  { cat: 'Zustände', key: 'target', name: 'Ziel', designs: target },
  { cat: 'Zustände', key: 'warning', name: 'Warnung', designs: warning },
  { cat: 'Zustände', key: 'banned', name: 'Verboten', designs: banned },
  { cat: 'Zustände', family: 'faces', name: 'Gesichter (Angst, Schlaf, Kälte)', designs: faces, outs: [['faceFear', 'Angst', 'fear', null], ['faceSleep', 'Schlaf', 'sleep', null], ['faceCold', 'Kälte', 'cold', null]] },
];
module.exports = { CONCEPTS };
