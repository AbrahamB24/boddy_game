// Batch 2: combat icons. Parts are drawn upright and rotated with up().
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');

const rot = (m, cx, cy, deg) => {
  const t = (deg * Math.PI) / 180, co = Math.cos(t), si = Math.sin(t);
  return (x, y) => { const dx = x - cx, dy = y - cy; return m(cx + dx * co + dy * si, cy - dx * si + dy * co); };
};
// parts: [mask, ramp, mode?, bias?]
const up = (c, parts, deg = 0, cx = 12, cy = 12) => parts.forEach(([m, r, mode = 'diag', b = 0]) => c.shape(deg ? rot(m, cx, cy, deg) : m, r, mode, b));
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');

// ---- sword parts (upright, centred x=12) ----
const blade = (w = 1.6, top = 1, bot = 15) => [poly([[12 - w, top + 1.5], [12, top], [12 + w, top + 1.5], [12 + w, bot], [12 - w, bot]]), 'steel', 'diag'];
const fuller = (top = 4, bot = 14) => [rect(11.7, top, 12.3, bot), 'steel', 'flat', -0.4];
const guard = (w = 4, y = 15, col = 'gold') => [rect(12 - w, y, 12 + w, y + 1.8), col, 'vert'];
const grip = (y = 17, h = 3.6) => [rect(11, y, 13, y + h), 'leatherd', 'vert'];
const pommel = (y = 21.6, col = 'gold') => [ell(12, y, 1.8, 1.5), col, 'orb'];
const longsword = (w = 1.6, top = 1) => [blade(w, top), fuller(top + 3), guard(), grip(), pommel()];

const sword = [
  ['Langschwert', 'Schräg, klassisch', (c) => up(c, longsword(), 45)],
  ['Aufrecht', 'Senkrecht, mit Hohlkehle', (c) => up(c, longsword())],
  ['Dolch', 'Kurz mit breiter Parierstange', (c) => up(c, [blade(1.6, 5, 15), fuller(8, 14), guard(4.5), grip(), pommel()], 45)],
  ['Krummsäbel', 'Gebogene Klinge', (c) => {
    c.shape(poly([[19, 2], [21, 5], [18, 12], [11, 15], [9, 13], [14, 10], [17, 5]]), 'steel', 'diag');
    c.shape(thick(8, 12, 12, 16, 2.6), 'gold', 'diag'); c.shape(thick(9, 15, 4, 20, 2), 'leatherd', 'vert'); c.shape(ell(3.6, 20.4, 1.6, 1.6), 'gold', 'orb');
  }],
  ['Breitschwert', 'Dicke Klinge, große Parierstange', (c) => up(c, [blade(2.6), fuller(5), guard(6, 15), grip(), pommel()], 45)],
  ['Rubinknauf', 'Mit rotem Stein', (c) => up(c, [blade(), fuller(), guard(5), grip(), [ell(12, 21.4, 2, 2), 'ruby', 'orb']], 45)],
  ['Rapier', 'Dünn mit Korbgriff', (c) => up(c, [[rect(11.4, 1, 12.6, 15), 'steel', 'diag'], [ring(12, 16.5, 4.4, 3.2), 'gold', 'orb'], [rect(8, 16, 16, 17), 'gold', 'vert'], grip(18, 3), pommel(22)], 45)],
  ['Zweihänder', 'Langer Griff, lange Klinge', (c) => up(c, [[poly([[10.4, 1.5], [12, 0], [13.6, 1.5], [13.6, 13], [10.4, 13]]), 'steel', 'diag'], fuller(3, 12), guard(5.4, 13), [rect(11, 15, 13, 21), 'leatherd', 'vert'], pommel(22)], 45)],
  ['Flammenschwert', 'Glühende Klinge', (c) => up(c, [[poly([[10.4, 2.5], [12, 0.5], [13.6, 2.5], [13.6, 15], [10.4, 15]]), 'orange', 'diag'], fuller(4), guard(), grip(), pommel()], 45)],
  ['Holzschwert', 'Übungsschwert', (c) => up(c, [[poly([[10.6, 3], [12, 1], [13.4, 3], [13.4, 15], [10.6, 15]]), 'woodl', 'diag'], guard(3.6, 15, 'wood'), [rect(11, 17, 13, 21), 'bark', 'vert'], [ell(12, 21.6, 1.7, 1.4), 'wood', 'orb']], 45)],
];

const two = (c, a, b, deg = 42) => { up(c, a, -deg); up(c, b, deg); };
const sw2 = longsword(1.4);
const dag = [blade(1.4, 5, 15), fuller(8, 14), guard(4), grip(), pommel()];
const axe = [[rect(11.2, 3, 12.8, 21), 'wood', 'diag'], [poly([[13, 3], [19, 1], [19, 10], [13, 8]]), 'steel', 'diag']];
const mace = [[rect(11.2, 9, 12.8, 21), 'wood', 'diag'], [ell(12, 6, 4.2, 4.2), 'iron', 'orb'], [rect(11, 0.5, 13, 3), 'iron', 'diag'], [rect(6.5, 5, 8.5, 7), 'iron', 'diag'], [rect(15.5, 5, 17.5, 7), 'iron', 'diag']];
const swords = [
  ['Gekreuzt', 'Zwei Schwerter', (c) => two(c, sw2, sw2)],
  ['Mit Schild', 'Schilde hinter den Klingen', (c) => { c.shape(ell(12, 12, 9, 9), 'iron', 'orb'); c.shape(ell(12, 12, 7, 7), 'blue', 'orb'); two(c, sw2, sw2); }],
  ['Mit Stern', 'Stern im Kreuzungspunkt', (c) => { two(c, sw2, sw2); c.shape(star(12, 12, 4.4, 1.9), 'gold', 'orb'); }],
  ['Mit Krone', 'Krone über dem Kreuz', (c) => { two(c, [blade(1.4, 5, 15), fuller(8, 14), guard(4), grip(), pommel()], [blade(1.4, 5, 15), fuller(8, 14), guard(4), grip(), pommel()]); c.shape(poly([[7, 8], [7, 2], [9.5, 5], [12, 1], [14.5, 5], [17, 2], [17, 8]]), 'gold', 'vert'); }],
  ['Axt und Schwert', 'Gemischtes Paar', (c) => { up(c, sw2, 42); up(c, axe, -42); }],
  ['Zwei Dolche', 'Kurze Klingen', (c) => two(c, dag, dag, 40)],
  ['Parallel', 'Nebeneinander, Spitzen nach oben', (c) => { const s = (dx) => longsword(1.4).map(([m, r, mo, b]) => [(x, y) => m(x - dx, y), r, mo, b]); up(c, s(-4)); up(c, s(4)); }],
  ['Schwert und Streitkolben', 'Zwei Waffenarten', (c) => { up(c, sw2, 42); up(c, mace, -42); }],
  ['Im Ring', 'Gekreuzt vor Metallring', (c) => { c.shape(ring(12, 12, 10.6, 8.6), 'iron', 'orb'); two(c, sw2, sw2); }],
  ['Schwert und Schild', 'Rundschild vorn', (c) => { up(c, longsword(1.4), 30, 14, 10); c.shape(ell(10, 15, 7, 7), 'leather', 'orb'); c.shape(ell(10, 15, 2.2, 2.2), 'steel', 'orb'); c.shape(ring(10, 15, 7, 6), 'iron', 'flat'); }],
];

// ---- shields ----
const shield = [
  ['Wappenschild', 'Rot mit goldenem Kreuz', (c) => {
    const S = poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]);
    c.shape(S, 'red', 'diag'); c.shape(both(S, rect(10.5, 3, 13.5, 24)), 'gold', 'vert'); c.shape(both(S, rect(3, 7.5, 21, 10.5)), 'gold', 'vert');
  }],
  ['Rundschild', 'Holz mit Eisenbuckel', (c) => {
    c.shape(ell(12, 12, 10, 10), 'wood', 'orb'); c.shape(ring(12, 12, 10, 8.6), 'iron', 'flat'); c.shape(ell(12, 12, 3.4, 3.4), 'steel', 'orb');
    for (const a of [0, 1, 2, 3, 4, 5]) c.px(12 + 6.4 * Math.cos(a * 1.047), 12 + 6.4 * Math.sin(a * 1.047), 'woodl', 4);
  }],
  ['Sternschild', 'Blau mit Stern', (c) => {
    const S = poly([[4, 3], [20, 3], [20, 12], [12, 22], [4, 12]]); c.shape(S, 'blue', 'diag'); c.shape(star(12, 11.5, 5.6, 2.4), 'goldl', 'orb'); c.shape(ring(12, 12, 14, 13), 'blue', 'flat');
  }],
  ['Turmschild', 'Hoch, aus Stahl', (c) => {
    c.shape(rect(5, 2, 18, 21), 'steel', 'diag'); c.shape(rect(5, 2, 18, 4), 'iron', 'vert'); c.line(6, 6, 6, 20, 'steel', 4); c.shape(rect(10, 9, 13, 16), 'iron', 'vert', 0.1);
    for (const [x, y] of [[7, 5], [16, 5], [7, 19], [16, 19]]) c.px(x, y, 'face', 4);
  }],
  ['Schwertschild', 'Schwert als Wappen', (c) => {
    c.shape(poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]), 'blue', 'diag'); up(c, [blade(1.1, 5, 14), guard(3, 14), grip(15.5, 3)], 0, 12, 12);
  }],
  ['Streifenschild', 'Zwei Farben', (c) => {
    const S = poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]); c.shape(S, 'face', 'diag'); c.shape(both(S, rect(0, 0, 12, 24)), 'red', 'diag');
    c.shape(both(S, rect(12, 0, 24, 24)), 'face', 'diag');
  }],
  ['Vikingerschild', 'Gedrittelt', (c) => {
    c.shape(ell(12, 12, 10, 10), 'red', 'orb'); c.shape(both(ell(12, 12, 10, 10), poly([[12, 12], [22, 4], [22, 20]])), 'face', 'diag'); c.shape(both(ell(12, 12, 10, 10), poly([[12, 12], [2, 4], [2, 20]])), 'face', 'diag');
    c.shape(ell(12, 12, 3, 3), 'steel', 'orb'); c.shape(ring(12, 12, 10, 9), 'iron', 'flat');
  }],
  ['Sechseck', 'Kantiger Schild', (c) => {
    c.shape(poly([[7, 2], [17, 2], [22, 12], [17, 22], [7, 22], [2, 12]]), 'iron', 'diag'); c.shape(poly([[9, 6], [15, 6], [18, 12], [15, 18], [9, 18], [6, 12]]), 'steel', 'diag', 0.1);
  }],
  ['Tartsche', 'Klein und rund', (c) => {
    c.shape(ell(12, 12, 7.5, 7.5), 'steel', 'orb'); c.shape(ring(12, 12, 7.5, 6.2), 'iron', 'flat'); c.shape(ell(12, 12, 2.4, 2.4), 'gold', 'orb'); c.px(8, 8, 'face', 4);
  }],
  ['Geflügelt', 'Schild mit Flügeln', (c) => {
    c.shape(poly([[2, 5], [8, 8], [8, 14], [4, 15], [2, 11]]), 'face', 'diag'); c.shape(poly([[22, 5], [16, 8], [16, 14], [20, 15], [22, 11]]), 'face', 'diag', 0.1);
    c.shape(poly([[7, 3], [17, 3], [17, 12], [12, 21], [7, 12]]), 'blue', 'diag'); c.shape(star(12, 10, 3, 1.3), 'goldl', 'orb');
  }],
];

// ---- hearts (family: heart, heartPink, heartGreen) ----
const H = (c, o, x = 12, y = 12, s = 9.2) => c.shape(heart(x, y, s), o, 'orb');
const hearts = [
  ['Klassisch', 'Einfaches Herz', (c, o) => { H(c, o); c.px(6, 8, 'face', 4); c.px(7, 7, 'face', 4); }],
  ['Mit Glanz', 'Herz, hellere Mitte', (c, o) => { H(c, o); c.shape(heart(12, 12, 5.4), o, 'orb', -0.2); sparkle(c, 7, 7, 2.2); }],
  ['Mit Kreuz', 'Heilendes Herz', (c, o) => { H(c, o); c.shape(rect(10.5, 7, 13.5, 16), 'face', 'flat', -0.1); c.shape(rect(7.5, 10, 16.5, 13), 'face', 'flat', -0.1); }],
  ['Geteilt', 'Halbes Herz', (c, o) => { H(c, o); c.shape(both(heart(12, 12, 9.2), rect(12, 0, 24, 24)), o, 'vert', 0.35); c.line(12, 4, 12, 20, o, 0); }],
  ['Mit Flügeln', 'Geflügeltes Herz', (c, o) => { c.shape(poly([[1, 8], [8, 9], [8, 14], [3, 14]]), 'face', 'diag'); c.shape(poly([[23, 8], [16, 9], [16, 14], [21, 14]]), 'face', 'diag'); H(c, o, 12, 11.5, 7.6); }],
  ['Im Ring', 'Herz in Goldrahmen', (c, o) => { c.shape(ring(12, 12, 10.5, 8.8), 'gold', 'orb'); H(c, o, 12, 12.5, 6); }],
  ['Kristall', 'Facettiertes Herz', (c, o) => { H(c, o); c.line(12, 6, 12, 20, o, 0); c.line(5, 9, 12, 14, o, 1); c.line(19, 9, 12, 14, o, 1); c.shape(poly([[4, 8], [9, 4], [12, 8], [8, 11]]), o, 'vert', -0.3); }],
  ['Mit Pflaster', 'Verbunden', (c, o) => { H(c, o); c.shape(thick(6, 16, 18, 7, 4), 'bread', 'diag'); c.px(11, 11, 'leatherd', 2); c.px(13, 12, 'leatherd', 2); }],
  ['Im Fläschchen', 'Heiltrank', (c, o) => {
    c.shape(rect(10, 2, 14, 7), 'ice', 'diag'); c.shape(rect(9.5, 1.5, 14.5, 3), 'leather', 'vert'); c.shape(ell(12, 15, 8, 7), 'ice', 'orb'); c.shape(ell(12, 16, 6.4, 5.2), o, 'orb'); c.px(8, 12, 'face', 4);
  }],
  ['Drei kleine', 'Drei Herzen', (c, o) => { H(c, o, 6.5, 14.5, 4.4); H(c, o, 17.5, 14.5, 4.4); H(c, o, 12, 7, 4.8); }],
];

// ---- bolt ----
const B = (c, pts, r = 'bolt', mode = 'diag') => c.shape(poly(pts), r, mode);
const bolt = [
  ['Klassisch', 'Zickzack', (c) => B(c, [[14, 1], [5, 13], [11, 13], [9, 23], [19, 9], [13, 9], [16, 1]])],
  ['Mit Aura', 'Blitz vor Lichtkreis', (c) => { c.shape(ell(12, 12, 10, 10), 'orange', 'orb', 0.25); B(c, [[14, 2], [6, 13], [11, 13], [9, 22], [18, 10], [13, 10], [16, 2]]); }],
  ['Doppelt', 'Zwei Blitze', (c) => { B(c, [[9, 2], [3, 11], [7, 11], [5, 21], [13, 9], [9, 9], [11, 2]]); B(c, [[18, 3], [12, 13], [16, 13], [15, 22], [22, 11], [19, 11], [21, 3]], 'bolt', 'orb'); }],
  ['Im Kreis', 'Blitz in Medaillon', (c) => { c.shape(ell(12, 12, 10.4, 10.4), 'blue', 'orb'); B(c, [[13, 4], [7, 13], [11, 13], [10, 20], [17, 10], [13, 10], [15, 4]]); }],
  ['Im Sechseck', 'Blitz in Fassung', (c) => { c.shape(poly([[7, 2], [17, 2], [22, 12], [17, 22], [7, 22], [2, 12]]), 'iron', 'diag'); B(c, [[13, 4], [7, 13], [11, 13], [10, 20], [17, 10], [13, 10], [15, 4]]); }],
  ['Gewitterwolke', 'Wolke mit Blitz', (c) => {
    c.shape(ell(8, 8, 5, 4), 'steel', 'orb'); c.shape(ell(15, 7, 6, 5), 'steel', 'orb'); c.shape(rect(4, 8, 20, 12), 'iron', 'vert', -0.1); B(c, [[13, 11], [9, 17], [12, 17], [11, 23], [17, 15], [14, 15], [15, 11]]);
  }],
  ['Spitz', 'Dünner Blitz', (c) => B(c, [[15, 1], [7, 11], [11, 12], [8, 23], [17, 9], [13, 9], [15, 1]], 'bolt', 'vert')],
  ['Mit Funken', 'Blitz und Funken', (c) => { B(c, [[13, 3], [6, 13], [11, 13], [9, 22], [17, 10], [13, 10], [15, 3]]); sparkle(c, 19, 5, 2.6); sparkle(c, 4, 18, 2.2); sparkle(c, 20, 18, 1.8); }],
  ['Raute', 'Blitz in Raute', (c) => { c.shape(poly([[12, 1], [22, 12], [12, 23], [2, 12]]), 'purple', 'diag'); B(c, [[13, 5], [8, 12], [11, 12], [10, 19], [16, 11], [13, 11], [14, 5]]); }],
  ['Kugelblitz', 'Energiekugel', (c) => { c.shape(ell(12, 12, 6, 6), 'cyan', 'orb'); c.shape(ell(12, 12, 3, 3), 'face', 'orb', -0.2); for (const [a, b, d, e] of [[12, 1, 12, 5], [12, 19, 12, 23], [1, 12, 5, 12], [19, 12, 23, 12], [4, 4, 7, 7], [17, 17, 20, 20], [20, 4, 17, 7], [4, 20, 7, 17]]) c.line(a, b, d, e, 'bolt', 3); }],
];

// ---- flame ----
const F = (c) => { c.shape(poly([[12, 1], [16, 7], [19, 12], [18, 18], [12, 22], [6, 18], [5, 12], [8, 9], [9, 12], [10, 6]]), 'orange', 'vert'); };
const flame = [
  ['Klassisch', 'Flamme mit Kern', (c) => { F(c); c.shape(poly([[12, 12], [15, 16], [14, 20], [10, 20], [9, 16]]), 'goldl', 'vert', -0.1); }],
  ['Zwei Zungen', 'Flamme mit hellem Innern', (c) => { F(c); c.shape(ell(12, 17, 3.4, 4), 'bolt', 'orb', -0.1); c.shape(ell(12, 18.5, 1.6, 2), 'face', 'flat'); }],
  ['Kerzenflamme', 'Tropfenform', (c) => { c.shape(poly([[12, 2], [17, 12], [16, 19], [12, 22], [8, 19], [7, 12]]), 'orange', 'vert'); c.shape(ell(12, 17, 2.8, 3.6), 'goldl', 'orb'); }],
  ['Dreierflamme', 'Drei Zungen', (c) => {
    c.shape(poly([[4, 21], [4, 11], [7, 4], [9, 11], [10, 21]]), 'red', 'vert'); c.shape(poly([[9, 21], [10, 8], [12, 1], [15, 8], [16, 21]]), 'orange', 'vert'); c.shape(poly([[14, 21], [16, 11], [18, 5], [20, 11], [20, 21]]), 'red', 'vert');
    c.shape(poly([[10, 21], [12, 12], [14, 21]]), 'goldl', 'vert');
  }],
  ['Lagerfeuer', 'Feuer mit Holz', (c) => {
    c.shape(poly([[12, 2], [17, 9], [18, 15], [12, 18], [6, 15], [7, 9]]), 'orange', 'vert'); c.shape(ell(12, 14, 2.6, 3.4), 'goldl', 'orb');
    c.shape(thick(3, 20, 17, 15, 3), 'bark', 'diag'); c.shape(thick(21, 20, 7, 15, 3), 'bark', 'diag', 0.1);
  }],
  ['Fackel', 'Brennende Fackel', (c) => {
    c.shape(thick(12, 22, 12, 11, 3.4), 'wood', 'diag'); c.shape(rect(10, 10, 14, 13), 'iron', 'vert');
    c.shape(poly([[12, 1], [16, 6], [16, 10], [12, 12], [8, 10], [8, 6]]), 'orange', 'vert'); c.shape(ell(12, 9, 2, 2.6), 'goldl', 'orb');
  }],
  ['Funke', 'Flamme mit Funken', (c) => { c.shape(poly([[11, 6], [15, 11], [16, 17], [11, 21], [6, 17], [6, 12], [9, 10]]), 'orange', 'vert'); c.shape(ell(11, 17, 2.6, 3), 'goldl', 'orb'); sparkle(c, 18, 5, 3); sparkle(c, 5, 6, 2); }],
  ['Glut', 'Glühende Kohlen', (c) => {
    for (const [x, y, rx] of [[6, 18, 4], [13, 19, 4.6], [18, 16, 3.4], [10, 14, 3.4]]) { c.shape(ell(x, y, rx, 3), 'coal', 'orb'); c.shape(ell(x - 1, y - 1, rx * 0.5, 1.2), 'orange', 'flat'); }
    c.shape(poly([[11, 3], [14, 8], [13, 12], [9, 12], [8, 8]]), 'orange', 'vert');
  }],
  ['Feuerball', 'Geschoss mit Schweif', (c) => {
    c.shape(poly([[2, 3], [14, 8], [18, 12], [14, 16], [2, 21], [8, 12]]), 'red', 'vert'); c.shape(ell(16, 12, 6, 6), 'orange', 'orb'); c.shape(ell(17, 12, 3.2, 3.2), 'goldl', 'orb');
  }],
  ['Feuerschale', 'Flamme in Schale', (c) => {
    c.shape(poly([[12, 1], [16, 6], [17, 11], [12, 13], [7, 11], [8, 6]]), 'orange', 'vert'); c.shape(ell(12, 10, 2.2, 2.8), 'goldl', 'orb');
    c.shape(both(ell(12, 13, 9, 7), rect(0, 13, 24, 24)), 'iron', 'vert'); c.shape(rect(10, 19, 14, 22), 'iron', 'diag'); c.shape(rect(6, 21, 18, 22.5), 'iron', 'vert');
  }],
];

// ---- drop (family: drop = water, blood = red) ----
const D = (x, y, s) => poly([[x, y - s], [x + s * 0.7, y + s * 0.3], [x, y + s * 1.1], [x - s * 0.7, y + s * 0.3]]);
const dropShape = (c, o, x = 12, y = 12, s = 9) => { c.shape(either(D(x, y, s), ell(x, y + s * 0.35, s * 0.72, s * 0.72)), o, 'orb'); };
const drop = [
  ['Tropfen', 'Klassisch', (c, o) => { dropShape(c, o); c.px(8, 14, 'face', 4); c.px(8, 15, 'face', 4); c.px(9, 17, 'face', 4); }],
  ['Mit Welle', 'Tropfen über Ringen', (c, o) => { dropShape(c, o, 12, 9, 7); c.shape(minus(ell(12, 19.5, 10, 3.6), ell(12, 19.5, 7, 1.9)), o, 'vert', -0.1); }],
  ['Zwei Tropfen', 'Groß und klein', (c, o) => { dropShape(c, o, 9, 11, 7.5); dropShape(c, o, 18, 16, 4); }],
  ['Spritzer', 'Aufprall', (c, o) => { c.shape(ell(12, 17, 4, 4), o, 'orb'); for (const [x, y] of [[4, 11], [8, 5], [16, 5], [20, 11]]) c.shape(ell(x, y, 2, 2), o, 'orb'); c.shape(rect(2, 18, 22, 20), o, 'vert'); }],
  ['Pfütze', 'Tropfen und Lache', (c, o) => { dropShape(c, o, 12, 7, 6); c.shape(ell(12, 19, 10, 3.4), o, 'vert', -0.1); }],
  ['Fläschchen', 'Rundkolben', (c, o) => { c.shape(rect(10, 2, 14, 8), 'ice', 'diag'); c.shape(ell(12, 15, 8, 7), 'ice', 'orb'); c.shape(ell(12, 16, 6.4, 5.2), o, 'orb'); c.shape(rect(9, 1.5, 15, 3), 'leather', 'vert'); }],
  ['Tropfenreihe', 'Drei fallende Tropfen', (c, o) => { dropShape(c, o, 5, 14, 4.6); dropShape(c, o, 12, 10, 5.6); dropShape(c, o, 19, 14, 4.6); }],
  ['Facettiert', 'Eckiger Tropfen', (c, o) => { c.shape(poly([[12, 1], [19, 12], [17, 19], [12, 22], [7, 19], [5, 12]]), o, 'diag'); c.shape(poly([[12, 1], [19, 12], [12, 13], [5, 12]]), o, 'vert', -0.25); c.line(12, 13, 12, 21, o, 1); }],
  ['Im Kreis', 'Tropfen in Medaillon', (c, o) => { c.shape(ell(12, 12, 10.4, 10.4), 'iron', 'orb'); dropShape(c, o, 12, 11, 6.4); }],
  ['Klecks', 'Unregelmäßiger Fleck', (c, o) => { c.shape(poly([[3, 12], [6, 6], [11, 8], [14, 3], [18, 8], [21, 11], [18, 17], [13, 15], [10, 21], [6, 17]]), o, 'orb'); c.shape(ell(14, 20, 2, 2), o, 'orb'); c.px(8, 10, 'face', 4); }],
];

// ---- skull (+ skullBones = same skull over crossed bones) ----
const SK = (c, x = 12, y = 10, s = 1) => {
  c.shape(ell(x, y, 8 * s, 7.4 * s), 'face', 'orb'); c.shape(rect(x - 4.6 * s, y + 4 * s, x + 4.6 * s, y + 9 * s), 'face', 'diag', 0.05);
  c.shape(ell(x - 3.4 * s, y + 0.5 * s, 2.3 * s, 2.5 * s), 'black', 'flat'); c.shape(ell(x + 3.4 * s, y + 0.5 * s, 2.3 * s, 2.5 * s), 'black', 'flat');
  c.shape(poly([[x, y + 3 * s], [x - 1.1 * s, y + 5 * s], [x + 1.1 * s, y + 5 * s]]), 'black', 'flat');
  for (const dx of [-2.4, 0, 2.4]) c.line(x + dx * s, y + 7 * s, x + dx * s, y + 9 * s, 'black', 1);
};
const bones = (c) => { c.shape(thick(3, 6, 21, 21, 2.6), 'face', 'diag'); c.shape(thick(21, 6, 3, 21, 2.6), 'face', 'diag'); for (const [x, y] of [[3, 6], [21, 6], [3, 21], [21, 21]]) c.shape(ell(x, y, 2, 2), 'face', 'orb'); };
const skull = [
  ['Klassisch', 'Frontal', (c) => SK(c)],
  ['Grinsend', 'Breites Zahnreihen-Grinsen', (c) => { c.shape(ell(12, 10, 9, 8), 'face', 'orb'); c.shape(rect(6, 15, 18, 19), 'face', 'diag'); c.shape(ell(8, 9, 2.6, 3), 'black', 'flat'); c.shape(ell(16, 9, 2.6, 3), 'black', 'flat'); c.shape(rect(6, 15, 18, 16.2), 'black', 'flat'); for (const x of [8, 10, 12, 14, 16]) c.line(x, 16, x, 19, 'black', 1); }],
  ['Seitlich', 'Im Profil', (c) => {
    c.shape(ell(11, 9, 8, 7.4), 'face', 'orb'); c.shape(rect(13, 10, 21, 15), 'face', 'diag'); c.shape(rect(11, 15, 20, 18), 'face', 'vert', 0.1);
    c.shape(ell(13, 8, 2.8, 3), 'black', 'flat'); c.line(14, 15, 14, 18, 'black', 1); c.line(17, 15, 17, 18, 'black', 1);
  }],
  ['Mit Helm', 'Eisenhelm', (c) => { SK(c, 12, 12, 0.86); c.shape(both(ell(12, 9, 9.6, 8), rect(0, 0, 24, 9)), 'iron', 'vert'); c.shape(rect(2, 8, 22, 10), 'steel', 'vert'); c.shape(rect(11, 2, 13, 9), 'steel', 'diag'); }],
  ['Große Augen', 'Comic', (c) => {
    c.shape(ell(12, 10, 9, 8), 'face', 'orb'); c.shape(rect(7, 14, 17, 20), 'face', 'diag'); c.shape(ell(8, 10, 3.2, 3.6), 'black', 'flat'); c.shape(ell(16, 10, 3.2, 3.6), 'black', 'flat'); c.px(7, 9, 'face', 4); c.px(15, 9, 'face', 4);
    for (const x of [9, 12, 15]) c.line(x, 16, x, 19, 'black', 1);
  }],
  ['Mit Krone', 'Totenkönig', (c) => { SK(c, 12, 12, 0.86); c.shape(poly([[6, 6], [6, 1], [9, 4], [12, 0], [15, 4], [18, 1], [18, 6]]), 'gold', 'vert'); }],
  ['Rissig', 'Gesprungen', (c) => { SK(c); c.line(13, 2, 11, 7, 'black', 1); c.line(11, 7, 13, 10, 'black', 1); c.line(9, 4, 8, 6, 'stone', 1); }],
  ['Gehörnt', 'Mit Hörnern', (c) => { c.shape(poly([[4, 8], [1, 2], [7, 5]]), 'face', 'diag'); c.shape(poly([[20, 8], [23, 2], [17, 5]]), 'face', 'diag'); SK(c, 12, 11, 0.9); }],
  ['Mit Kerze', 'Kerze auf Schädel', (c) => { SK(c, 12, 13, 0.82); c.shape(rect(10.5, 3, 13.5, 6.5), 'face', 'vert'); c.shape(poly([[12, 0], [14, 2], [12, 3], [10, 2]]), 'orange', 'vert'); }],
  ['Knochenhaufen', 'Schädel auf Knochen', (c) => { c.shape(thick(2, 20, 22, 19, 3), 'face', 'vert'); c.shape(ell(3, 20.2, 2, 2), 'face', 'orb'); c.shape(ell(21, 18.8, 2, 2), 'face', 'orb'); SK(c, 12, 9, 0.9); }],
];

// ---- boom ----
const burst = (cx, cy, ro, ri, n) => star(cx, cy, ro, ri, n);
const boom = [
  ['Sternexplosion', 'Gelb auf Rot', (c) => { c.shape(burst(12, 12, 11, 5.5, 8), 'red', 'orb'); c.shape(burst(12, 12, 7.5, 3.5, 8), 'goldl', 'orb'); }],
  ['Rauchpilz', 'Wolke mit Feuer', (c) => { c.shape(ell(8, 10, 5, 4.4), 'steel', 'orb'); c.shape(ell(16, 10, 5, 4.4), 'steel', 'orb'); c.shape(ell(12, 7, 5.6, 4.6), 'steel', 'orb'); c.shape(poly([[7, 14], [17, 14], [20, 21], [4, 21]]), 'orange', 'vert'); c.shape(ell(12, 17, 4, 3), 'goldl', 'orb'); }],
  ['Bombe', 'Schwarze Bombe', (c) => { c.shape(ell(11, 15, 7.5, 7.5), 'black', 'orb'); c.shape(rect(9, 5, 13, 8), 'iron', 'diag'); c.line(13, 5, 17, 2, 'leatherd', 2); sparkle(c, 18, 2.5, 3); c.px(8, 12, 'face', 4); c.px(8, 13, 'face', 4); }],
  ['Zacken', 'Scharfe Spitzen', (c) => c.shape(burst(12, 12, 11, 4, 11), 'orange', 'orb')],
  ['Aufprall', 'Ring mit Rissen', (c) => { c.shape(ring(12, 12, 10, 7), 'goldl', 'orb'); c.shape(ell(12, 12, 4, 4), 'orange', 'orb'); for (const [a, b, d, e] of [[12, 1, 12, 5], [12, 19, 12, 23], [1, 12, 5, 12], [19, 12, 23, 12]]) c.line(a, b, d, e, 'red', 2); }],
  ['Feuerwerk', 'Funkenregen', (c) => { for (const [x, y, r] of [[12, 12, 'bolt'], [5, 6, 'red'], [19, 6, 'cyan'], [5, 19, 'cyan'], [19, 19, 'red']]) { c.shape(burst(x, y, x === 12 ? 6 : 3.6, 1.2, 6), r, 'flat'); } }],
  ['Dynamit', 'Stange mit Lunte', (c) => { c.shape(thick(6, 20, 15, 8, 5), 'red', 'diag'); c.shape(thick(7, 18, 14, 9, 1.4), 'face', 'flat'); c.line(16, 7, 19, 3, 'leatherd', 2); sparkle(c, 20, 2.5, 3); }],
  ['Feuerball', 'Kugel mit Flammen', (c) => { c.shape(poly([[12, 1], [16, 5], [21, 8], [19, 14], [20, 20], [12, 18], [4, 20], [5, 14], [3, 8], [8, 5]]), 'red', 'orb'); c.shape(ell(12, 13, 6, 6), 'orange', 'orb'); c.shape(ell(12, 13, 3, 3), 'goldl', 'orb'); }],
  ['Splitter', 'Fliegende Scherben', (c) => { c.shape(burst(12, 12, 5, 2, 6), 'goldl', 'orb'); for (const [pts, r] of [[[[2, 4], [7, 2], [6, 7]], 'orange'], [[[17, 2], [22, 5], [16, 7]], 'orange'], [[[2, 17], [7, 15], [6, 21]], 'red'], [[[17, 16], [22, 18], [17, 22]], 'red'], [[[11, 1], [13, 1], [12, 5]], 'bolt'], [[[11, 19], [13, 19], [12, 23]], 'bolt']]) c.shape(poly(pts), r, 'flat'); }],
  ['Comic-Pow', 'Runde Wolke', (c) => { c.shape(burst(12, 12, 11, 7, 12), 'bolt', 'orb'); c.shape(burst(12, 12, 7, 4, 12), 'red', 'orb'); c.shape(burst(12, 12, 3, 1.5, 6), 'face', 'flat'); }],
];

const CONCEPTS = [
  { cat: 'Kampf', key: 'sword', name: 'Schwert', designs: sword },
  { cat: 'Kampf', key: 'swords', name: 'Gekreuzte Schwerter', designs: swords },
  { cat: 'Kampf', key: 'shield', name: 'Schild', designs: shield },
  { cat: 'Kampf', family: 'heart', name: 'Herzen (Leben, Heilung)', designs: hearts, cols: { heart: ['Herz', '#e0364f'], heartPink: ['Herz rosa', '#f07aa0'], heartGreen: ['Herz grün', '#58b04a'] } },
  { cat: 'Kampf', key: 'bolt', name: 'Blitz', designs: bolt },
  { cat: 'Kampf', key: 'flame', name: 'Flamme', designs: flame },
  { cat: 'Kampf', family: 'drop', name: 'Tropfen & Blut', designs: drop, cols: { drop: ['Tropfen', '#4a9ae0'], blood: ['Blut', '#d02a3a'] } },
  { cat: 'Kampf', key: 'skull', name: 'Totenkopf', designs: skull, outs: [['skull', 'skull', undefined, null], ['skullBones', 'skullBones', undefined, bones]] },
  { cat: 'Kampf', key: 'boom', name: 'Explosion', designs: boom },
];
module.exports = { CONCEPTS };
