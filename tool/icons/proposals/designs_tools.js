// Batch 6: tools, healing, research.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const rot = (m, cx, cy, deg) => { const t = (deg * Math.PI) / 180, co = Math.cos(t), si = Math.sin(t); return (x, y) => { const dx = x - cx, dy = y - cy; return m(cx + dx * co + dy * si, cy - dx * si + dy * co); }; };
const up = (c, parts, deg = 0, cx = 12, cy = 12) => parts.forEach(([m, r, mode = 'diag', b = 0]) => c.shape(deg ? rot(m, cx, cy, deg) : m, r, mode, b));
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const handle = (y0 = 8, y1 = 22, w = 1.2, r = 'wood') => [rect(12 - w, y0, 12 + w, y1), r, 'diag'];

const hammer = [
  ['Schmiedehammer', 'Schräg, Eisenkopf', (c) => up(c, [handle(), [rect(6, 2, 18, 8.4), 'iron', 'diag']], 45)],
  ['Aufrecht', 'Senkrecht', (c) => up(c, [handle(), [rect(6, 2, 18, 8.4), 'iron', 'diag']])],
  ['Holzhammer', 'Mallet', (c) => up(c, [handle(7, 22), [rect(5, 2, 19, 9), 'woodl', 'diag']], 45)],
  ['Vorschlaghammer', 'Zwei dicke Köpfe', (c) => up(c, [handle(9, 23), [rect(4, 2, 20, 10), 'steel', 'diag'], [rect(4, 2, 7, 10), 'iron', 'vert'], [rect(17, 2, 20, 10), 'iron', 'vert']], 45)],
  ['Klauenhammer', 'Mit Nagelzieher', (c) => up(c, [handle(), [rect(8, 2, 17, 8.4), 'iron', 'diag'], [poly([[8, 2], [3, 3], [2, 7], [4, 5], [8, 6]]), 'iron', 'diag']], 45)],
  ['Auf Amboss', 'Hammer über Amboss', (c) => { c.shape(poly([[3, 20], [5, 14], [20, 14], [22, 16], [16, 17], [17, 20]]), 'iron', 'diag'); c.shape(rect(2, 20, 20, 22), 'iron', 'vert'); up(c, [handle(6, 14, 1), [rect(7, 1, 17, 6), 'steel', 'diag']], 25, 12, 9); }],
  ['Steinhammer', 'Stein am Stock', (c) => up(c, [handle(), [ell(12, 5, 6, 3.6), 'stone', 'orb'], [rect(10, 8, 14, 10), 'leatherd', 'vert']], 45)],
  ['Golden', 'Goldener Kopf', (c) => up(c, [handle(), [rect(6, 2, 18, 8.4), 'gold', 'diag']], 45)],
  ['Mit Funken', 'Schlag mit Funken', (c) => { up(c, [handle(), [rect(6, 2, 18, 8.4), 'iron', 'diag']], 45, 10, 14); sparkle(c, 20, 18, 3.4); sparkle(c, 4, 4, 2.2); }],
  ['Zwei Hämmer', 'Gekreuzt', (c) => { const h = [handle(), [rect(7, 2, 17, 7.4), 'iron', 'diag']]; up(c, h, -40); up(c, h, 40); }],
];

const axeBlade = (w = 7, h = 9) => [poly([[13, 3], [13 + w, 1], [13 + w, 3 + h], [13, 3 + h * 0.7]]), 'steel', 'diag'];
const axe = [
  ['Holzfälleraxt', 'Klassisch', (c) => up(c, [handle(3, 22, 1.2), axeBlade(), [rect(11, 2, 14, 7), 'iron', 'diag']], 20)],
  ['Doppelaxt', 'Zwei Klingen', (c) => up(c, [handle(3, 22, 1.2), axeBlade(), [poly([[11, 3], [4, 1], [4, 12], [11, 9]]), 'steel', 'diag', 0.1]], 15)],
  ['Beil', 'Kleiner Handbeil', (c) => up(c, [handle(8, 22, 1.4), [poly([[13, 7], [20, 5], [20, 14], [13, 12]]), 'steel', 'diag']], 30)],
  ['Im Stumpf', 'Axt im Block', (c) => { c.shape(rect(4, 16, 20, 22), 'bark', 'vert'); c.shape(ell(12, 16, 8, 2.4), 'ring', 'orb'); up(c, [handle(2, 18, 1.2), axeBlade(6, 8)], 12, 12, 12); }],
  ['Streitaxt', 'Mit Halbmond', (c) => up(c, [handle(3, 22, 1.2, 'leatherd'), [poly([[13, 3], [21, 1], [22, 8], [21, 14], [13, 12]]), 'iron', 'diag'], [ell(16, 7, 2.4, 3), 'steel', 'flat', 0.2]], 20)],
  ['Steinaxt', 'Frühzeit', (c) => up(c, [handle(3, 22, 1.2), [poly([[13, 4], [20, 3], [20, 11], [13, 10]]), 'stone', 'diag'], [rect(11, 5, 14, 9), 'leatherd', 'vert']], 20)],
  ['Wikingeraxt', 'Geschwungen', (c) => up(c, [handle(1, 22, 1.2), [poly([[13, 2], [21, 0], [22, 8], [19, 16], [13, 10]]), 'steel', 'diag'], [rect(10.6, 1, 13.4, 5), 'iron', 'diag']], 20)],
  ['Mit Spänen', 'Axt und Holzspäne', (c) => { up(c, [handle(3, 22, 1.2), axeBlade()], 20, 10, 12); for (const [x, y] of [[18, 20], [21, 17], [15, 22]]) c.shape(rect(x, y, x + 2.4, y + 1.2), 'ring', 'flat'); }],
  ['Rundklinge', 'Große runde Schneide', (c) => up(c, [handle(3, 22, 1.2), [ell(17, 8, 5.4, 6), 'steel', 'orb'], [ell(17, 8, 2, 2.4), 'iron', 'flat']], 15)],
  ['Goldaxt', 'Zeremonienaxt', (c) => up(c, [handle(3, 22, 1.2, 'red'), [poly([[13, 3], [20, 1], [20, 12], [13, 9]]), 'gold', 'diag']], 20)],
];

const pickaxe = [
  ['Spitzhacke', 'Klassisch', (c) => up(c, [handle(5, 22, 1.2), [poly([[2, 8], [6, 3], [12, 2], [18, 3], [22, 8], [19, 8], [16, 5], [12, 5], [8, 5], [5, 8]]), 'iron', 'diag']], 35)],
  ['Doppelspitze', 'Zwei spitze Enden', (c) => up(c, [handle(4, 22, 1.2), [poly([[1, 6], [12, 3], [23, 6], [12, 6.4]]), 'steel', 'diag'], [rect(10, 3, 14, 7), 'iron', 'diag']], 40)],
  ['Breithacke', 'Mit flacher Schaufel', (c) => up(c, [handle(4, 22, 1.2), [poly([[4, 3], [20, 1], [22, 5], [12, 7]]), 'steel', 'diag']], 40)],
  ['Mit Gestein', 'Hacke und Brocken', (c) => { c.shape(poly([[2, 21], [2, 16], [6, 12], [11, 14], [12, 21]]), 'stone', 'diag'); up(c, [handle(5, 22, 1.2), [poly([[2, 8], [12, 2], [22, 8], [19, 8], [12, 5], [5, 8]]), 'iron', 'diag']], 40, 14, 12); }],
  ['Gebogen', 'Geschwungener Kopf', (c) => up(c, [handle(5, 22, 1.2), [poly([[1, 10], [4, 4], [12, 2], [20, 4], [23, 10], [20, 8], [12, 5], [4, 8]]), 'steel', 'diag']], 38)],
  ['Goldhacke', 'Goldener Kopf', (c) => up(c, [handle(5, 22, 1.2), [poly([[2, 8], [12, 2], [22, 8], [19, 8], [12, 5], [5, 8]]), 'gold', 'diag']], 38)],
  ['Mit Funken', 'Schlägt Funken', (c) => { up(c, [handle(5, 22, 1.2), [poly([[2, 8], [12, 2], [22, 8], [19, 8], [12, 5], [5, 8]]), 'iron', 'diag']], 38, 10, 14); sparkle(c, 20, 18, 3.4); sparkle(c, 4, 4, 2.2); }],
  ['Schaufel', 'Spaten', (c) => up(c, [handle(2, 14, 1.2), [rect(10, 1, 14, 3), 'wood', 'flat'], [poly([[8, 13], [16, 13], [15, 22], [12, 24], [9, 22]]), 'steel', 'diag']], 30)],
  ['Steinhacke', 'Aus Stein', (c) => up(c, [handle(5, 22, 1.2), [poly([[3, 8], [12, 2], [21, 8], [18, 8], [12, 5], [6, 8]]), 'stone', 'diag'], [rect(10, 4, 14, 8), 'leatherd', 'vert']], 38)],
  ['Hacke und Spaten', 'Gekreuzt', (c) => { up(c, [handle(5, 22, 1.1), [poly([[2, 8], [12, 2], [22, 8], [19, 8], [12, 5], [5, 8]]), 'iron', 'diag']], -40); up(c, [handle(2, 14, 1.1), [poly([[8, 13], [16, 13], [15, 22], [12, 24], [9, 22]]), 'steel', 'diag']], 40); }],
];

const saw = [
  ['Handsäge', 'Mit Griff', (c) => { c.shape(poly([[2, 4], [21, 8], [21, 14], [2, 13]]), 'steel', 'diag'); for (let x = 3; x < 21; x += 2) c.shape(poly([[x, 13.4], [x + 1, 16], [x + 2, 13.8]]), 'steel', 'flat'); c.shape(poly([[17, 7], [22, 8], [22, 17], [17, 16]]), 'wood', 'diag'); c.shape(ell(19.4, 12, 1, 1.6), 'black', 'flat'); }],
  ['Zweimannsäge', 'Lang', (c) => { c.shape(path([[1, 18], [23, 6]], 3.6), 'steel', 'diag'); for (let i = 0; i < 9; i++) c.px(3 + i * 2.4, 19 - i * 1.3 + 1, 'steel', 1); c.shape(rect(0, 17, 3, 23), 'wood', 'diag'); c.shape(rect(21, 2, 24, 8), 'wood', 'diag'); }],
  ['Kreissäge', 'Sägeblatt', (c) => { c.shape(star(12, 12, 11, 8.4, 14), 'steel', 'orb'); c.shape(ell(12, 12, 8.4, 8.4), 'steel', 'orb'); c.shape(ell(12, 12, 2.4, 2.4), 'iron', 'flat'); c.shape(ring(12, 12, 6, 5), 'iron', 'flat'); }],
  ['Bügelsäge', 'Mit Bogen', (c) => { c.shape(path([[4, 4], [4, 18], [20, 18], [20, 4]], 1.6), 'wood', 'diag'); c.shape(rect(3, 17, 21, 19.4), 'steel', 'vert'); for (let x = 4; x < 21; x += 2) c.px(x, 20, 'steel', 1); c.shape(rect(2, 3, 6, 5), 'wood', 'flat'); }],
  ['Säge und Stamm', 'Beim Sägen', (c) => { c.shape(rect(2, 13, 22, 21), 'bark', 'vert'); c.shape(ell(22, 17, 1.6, 4), 'ring', 'orb'); c.shape(poly([[3, 4], [17, 4], [17, 10], [3, 12]]), 'steel', 'diag'); for (let x = 4; x < 17; x += 2) c.px(x, 12, 'steel', 1); c.shape(rect(15, 3, 21, 9), 'wood', 'diag'); }],
  ['Metallsäge', 'Rahmen', (c) => { c.shape(path([[3, 7], [18, 7], [20, 14]], 1.6), 'iron', 'diag'); c.shape(rect(2, 14, 21, 17), 'steel', 'vert'); for (let x = 3; x < 20; x += 2) c.px(x, 18, 'steel', 1); c.shape(rect(2, 6, 5, 16), 'red', 'diag'); }],
  ['Sägeblatt', 'Senkrechtes Blatt', (c) => { c.shape(poly([[8, 2], [16, 2], [16, 22], [8, 22]]), 'steel', 'diag'); for (let y = 3; y < 22; y += 2.4) c.shape(poly([[16, y], [20, y + 1.2], [16, y + 2.4]]), 'steel', 'flat'); c.line(11, 4, 11, 20, 'face', 4); }],
  ['Kettensäge', 'Mit Kette', (c) => { c.shape(rect(2, 8, 10, 18), 'orange', 'diag'); c.shape(poly([[10, 10], [22, 10], [22, 16], [10, 16]]), 'steel', 'diag'); for (let x = 11; x < 22; x += 2) { c.px(x, 9, 'iron', 2); c.px(x, 17, 'iron', 2); } c.shape(rect(3, 5, 8, 8), 'iron', 'vert'); }],
  ['Säge auf Brett', 'Brett mit Schnitt', (c) => { c.shape(rect(2, 14, 22, 20), 'woodl', 'diag'); c.line(12, 14, 12, 20, 'black', 1); up(c, [[poly([[2, 2], [14, 2], [14, 6], [2, 8]]), 'steel', 'diag'], [rect(12, 1, 18, 7), 'wood', 'diag']], 0); }],
  ['Astsäge', 'Gebogene Klinge', (c) => { c.shape(poly([[2, 18], [4, 9], [12, 4], [22, 6], [20, 9], [12, 8], [6, 12]]), 'steel', 'diag'); for (let i = 0; i < 7; i++) c.px(5 + i * 2, 12 - i * 0.8, 'steel', 1); c.shape(rect(1, 16, 5, 22), 'wood', 'diag'); }],
];

const wrench = [
  ['Maulschlüssel', 'Offen', (c) => up(c, [handle(9, 22, 1.8, 'steel'), [ell(12, 6, 5.4, 5.4), 'steel', 'orb'], [rect(10.2, 0.4, 13.8, 6), 'black', 'flat']], 40)],
  ['Doppelmaul', 'Zwei Enden', (c) => up(c, [handle(4, 20, 1.6, 'steel'), [ell(12, 4, 4.6, 4.6), 'steel', 'orb'], [ell(12, 20, 4.6, 4.6), 'steel', 'orb'], [rect(10.4, 0.6, 13.6, 5), 'black', 'flat'], [rect(10.4, 19, 13.6, 23.4), 'black', 'flat']], 40)],
  ['Rollgabel', 'Verstellbar', (c) => up(c, [handle(8, 22, 1.8, 'iron'), [rect(8, 2, 16, 9), 'steel', 'diag'], [rect(10.4, 2, 13.6, 7), 'black', 'flat'], [ell(15, 9, 1.8, 1.8), 'gold', 'orb']], 40)],
  ['Rohrzange', 'Mit Zahnbacken', (c) => up(c, [handle(7, 22, 2, 'red'), [poly([[8, 1], [16, 1], [16, 8], [8, 8]]), 'iron', 'diag'], [rect(10.6, 1, 13.4, 5), 'black', 'flat']], 40)],
  ['Mit Mutter', 'Schlüssel und Mutter', (c) => { c.shape(poly([[6, 14], [10, 12], [14, 14], [14, 19], [10, 21], [6, 19]]), 'iron', 'diag'); c.shape(ell(10, 16.6, 1.8, 1.8), 'black', 'flat'); up(c, [handle(9, 22, 1.4, 'steel'), [ell(12, 6, 4.4, 4.4), 'steel', 'orb'], [rect(10.4, 0.8, 13.6, 6), 'black', 'flat']], 35, 16, 10); }],
  ['Mit Zahnrad', 'Zahnrad und Schlüssel', (c) => { c.shape(ell(9, 14, 7, 7), 'iron', 'orb'); for (let a = 0; a < 8; a++) { const t = a * 0.785; c.shape(ell(9 + 7.6 * Math.cos(t), 14 + 7.6 * Math.sin(t), 1.5, 1.5), 'iron', 'orb'); } c.shape(ell(9, 14, 2.4, 2.4), 'black', 'flat'); up(c, [handle(10, 23, 1.2, 'steel'), [ell(12, 7, 4, 4), 'steel', 'orb'], [rect(10.6, 2, 13.4, 7), 'black', 'flat']], 40, 17, 9); }],
  ['Ringschlüssel', 'Geschlossen', (c) => up(c, [handle(8, 22, 1.6, 'steel'), [ring(12, 5, 5, 2.6), 'steel', 'orb']], 40)],
  ['Sechskantschlüssel', 'Gewinkelt', (c) => { c.shape(path([[4, 4], [4, 18], [18, 18]], 2.8), 'steel', 'diag'); c.shape(ell(4, 4, 1.6, 1.6), 'steel', 'orb'); }],
  ['Schlüssel und Hammer', 'Werkzeugpaar', (c) => { up(c, [handle(9, 22, 1.4, 'steel'), [ell(12, 6, 4.4, 4.4), 'steel', 'orb'], [rect(10.4, 0.8, 13.6, 6), 'black', 'flat']], -40); up(c, [handle(7, 22, 1.2), [rect(7, 2, 17, 7.4), 'iron', 'diag']], 40); }],
  ['Goldschlüssel', 'Vergoldet', (c) => up(c, [handle(9, 22, 1.8, 'gold'), [ell(12, 6, 5.4, 5.4), 'gold', 'orb'], [rect(10.2, 0.4, 13.8, 6), 'black', 'flat']], 40)],
];

const scissors = [
  ['Schere', 'Klassisch offen', (c) => { c.shape(thick(11, 11, 20, 2, 2.4), 'steel', 'diag'); c.shape(thick(13, 11, 4, 2, 2.4), 'steel', 'diag'); c.shape(ring(8, 17, 3.6, 1.8), 'red', 'orb'); c.shape(ring(16, 17, 3.6, 1.8), 'red', 'orb'); c.shape(thick(9, 14, 13, 11, 2), 'iron', 'diag'); }],
  ['Gartenschere', 'Mit Federgriff', (c) => { c.shape(thick(12, 11, 21, 2, 2.2), 'steel', 'diag'); c.shape(thick(12, 11, 18, 4, 2), 'iron', 'diag'); c.shape(thick(11, 11, 4, 21, 3), 'red', 'diag'); c.shape(thick(13, 11, 18, 21, 3), 'red', 'diag'); c.shape(ell(12, 11, 1.4, 1.4), 'gold', 'orb'); }],
  ['Geschlossen', 'Zu', (c) => { c.shape(thick(12, 3, 12, 14, 3), 'steel', 'diag'); c.shape(ring(8, 18, 3.6, 1.8), 'blue', 'orb'); c.shape(ring(16, 18, 3.6, 1.8), 'blue', 'orb'); c.shape(rect(10.4, 13, 13.6, 15), 'iron', 'diag'); }],
  ['Mit Faden', 'Schneiderschere', (c) => { c.shape(thick(11, 12, 21, 3, 2.6), 'steel', 'diag'); c.shape(thick(13, 12, 3, 3, 2.6), 'steel', 'diag'); c.shape(ring(7, 18, 3.8, 1.8), 'iron', 'orb'); c.shape(ring(17, 18, 3.8, 1.8), 'iron', 'orb'); c.shape(path([[2, 21], [5, 20], [3, 23]], 1), 'red', 'flat'); }],
  ['Große Schneiderschere', 'Lange Klingen', (c) => { c.shape(poly([[11, 12], [22, 2], [23, 4], [13, 14]]), 'steel', 'diag'); c.shape(poly([[13, 12], [2, 2], [1, 4], [11, 14]]), 'steel', 'diag'); c.shape(ring(8, 18, 4, 2), 'black', 'orb'); c.shape(ring(16, 18, 4, 2), 'black', 'orb'); }],
  ['Heckenschere', 'Mit langen Griffen', (c) => { c.shape(thick(12, 11, 21, 3, 2.6), 'steel', 'diag'); c.shape(thick(12, 11, 3, 3, 2.6), 'steel', 'diag'); c.shape(thick(11, 11, 6, 22, 2.8), 'green', 'diag'); c.shape(thick(13, 11, 18, 22, 2.8), 'green', 'diag'); }],
  ['Schnippel', 'Schneidet Papier', (c) => { c.shape(rect(2, 14, 22, 21), 'face', 'diag'); c.shape(thick(8, 11, 16, 3, 2.2), 'steel', 'diag'); c.shape(thick(10, 11, 4, 5, 2.2), 'steel', 'diag'); c.shape(ring(6, 19, 2.4, 1.2), 'red', 'orb'); }],
  ['Kleine Schere', 'Nagelschere', (c) => { c.shape(thick(12, 12, 18, 3, 1.8), 'steel', 'diag'); c.shape(thick(12, 12, 8, 3, 1.8), 'steel', 'diag'); c.shape(ring(9, 18, 2.8, 1.4), 'gold', 'orb'); c.shape(ring(15, 18, 2.8, 1.4), 'gold', 'orb'); }],
  ['Bastelschere', 'Bunt', (c) => { c.shape(thick(11, 11, 20, 2, 2.4), 'steel', 'diag'); c.shape(thick(13, 11, 4, 2, 2.4), 'steel', 'diag'); c.shape(ring(8, 17, 3.8, 1.8), 'purple', 'orb'); c.shape(ring(16, 17, 3.8, 1.8), 'orange', 'orb'); }],
  ['Blechschere', 'Kräftig', (c) => { c.shape(thick(12, 12, 21, 4, 3.4), 'steel', 'diag'); c.shape(thick(12, 12, 6, 4, 3.4), 'iron', 'diag'); c.shape(thick(11, 12, 5, 22, 3), 'orange', 'diag'); c.shape(thick(13, 12, 19, 22, 3), 'orange', 'diag'); c.shape(ell(12, 12, 1.4, 1.4), 'black', 'flat'); }],
];

const bandage = [
  ['Pflaster', 'Schräg', (c) => { c.shape(thick(3, 20, 20, 3, 8), 'skin', 'diag'); c.shape(thick(9.4, 13.6, 13.6, 9.4, 4), 'face', 'flat'); for (const [x, y] of [[6, 14], [8, 16], [16, 8], [14, 6]]) c.px(x, y, 'clay', 2); }],
  ['Rolle', 'Mullbinde', (c) => { c.shape(ell(12, 12, 9, 9), 'face', 'orb'); c.shape(ring(12, 12, 9, 7.4), 'ice', 'flat'); c.shape(ell(12, 12, 3.4, 3.4), 'black', 'flat'); c.shape(path([[12, 3], [22, 3]], 2.6), 'face', 'diag'); }],
  ['Zwei Pflaster', 'Gekreuzt', (c) => { c.shape(thick(3, 19, 19, 3, 6), 'skin', 'diag'); c.shape(thick(3, 3, 19, 19, 6), 'skin', 'diag', 0.1); c.shape(rect(9, 9, 13, 13), 'face', 'flat'); }],
  ['Verband', 'Gewickelt', (c) => { c.shape(rect(4, 5, 20, 19), 'face', 'diag'); for (const y of [8, 11.4, 14.8]) c.shape(thick(4, y + 3, 20, y - 1, 1.4), 'ice', 'flat'); c.shape(rect(4, 5, 20, 6.4), 'ice', 'vert'); }],
  ['Mullkompresse', 'Quadrat', (c) => { c.shape(rect(3, 3, 21, 21), 'face', 'diag'); c.shape(rect(7, 7, 17, 17), 'ice', 'vert', 0.1); c.shape(rect(11, 7, 13, 17), 'red', 'flat'); c.shape(rect(7, 11, 17, 13), 'red', 'flat'); }],
  ['Herzpflaster', 'Mit Herz', (c) => { c.shape(thick(3, 20, 20, 3, 8), 'skin', 'diag'); c.shape(heart(12, 12, 3.4), 'red', 'orb'); }],
  ['Arm im Verband', 'Verbundener Arm', (c) => { c.shape(thick(4, 18, 20, 6, 6), 'skin', 'diag'); c.shape(thick(9, 16, 15, 7.4, 6), 'face', 'diag'); for (const t of [0, 1, 2]) c.shape(thick(9 + t * 2, 18 - t * 1.3, 11 + t * 2, 5.4 - t * 0.4, 1.2), 'ice', 'flat'); }],
  ['Kreuzpflaster', 'Rotes Kreuz', (c) => { c.shape(rect(2, 2, 22, 22), 'face', 'diag'); c.shape(rect(10, 5, 14, 19), 'red', 'diag'); c.shape(rect(5, 10, 19, 14), 'red', 'diag'); }],
  ['Verbandskasten', 'Erste Hilfe', (c) => { c.shape(rect(2, 6, 22, 20), 'green', 'diag'); c.shape(rect(8, 3, 16, 7), 'green', 'vert', 0.2); c.shape(rect(10.4, 9, 13.6, 17), 'face', 'flat'); c.shape(rect(7.6, 11.4, 16.4, 14.6), 'face', 'flat'); }],
  ['Klebeband', 'Rolle Pflaster', (c) => { c.shape(minus(ell(12, 12, 9, 9), ell(12, 12, 3.6, 3.6)), 'skin', 'orb'); c.shape(ring(12, 12, 5.2, 3.6), 'clay', 'flat'); c.shape(rect(10, 20, 22, 22), 'skin', 'vert'); }],
];

const syringe = [
  ['Spritze', 'Schräg', (c) => up(c, [[rect(9, 8, 15, 19), 'ice', 'diag'], [rect(9, 12, 15, 19), 'cyan', 'diag', 0.1], [rect(7, 7, 17, 9), 'steel', 'vert'], [rect(11, 1, 13, 7), 'steel', 'flat'], [rect(10.6, 19, 13.4, 22), 'steel', 'diag']], 40)],
  ['Ampulle mit Nadel', 'Fläschchen und Nadel', (c) => { c.shape(rect(6, 8, 14, 20), 'ice', 'diag'); c.shape(rect(6, 12, 14, 20), 'green', 'diag', 0.1); c.shape(rect(7, 5, 13, 8), 'steel', 'vert'); c.shape(thick(18, 3, 21, 20, 1), 'steel', 'flat'); }],
  ['Große Spritze', 'Mit grüner Füllung', (c) => up(c, [[rect(8, 7, 16, 19), 'ice', 'diag'], [rect(8, 11, 16, 19), 'green', 'diag', 0.1], [rect(5, 6, 19, 8.4), 'steel', 'vert'], [rect(10.6, 0, 13.4, 6), 'steel', 'flat'], [rect(11.2, 19, 12.8, 23), 'steel', 'flat']], 40)],
  ['Tropfer', 'Pipette', (c) => { c.shape(ell(12, 5, 4, 4), 'red', 'orb'); c.shape(poly([[9, 8], [15, 8], [13, 19], [11, 19]]), 'ice', 'diag'); c.shape(poly([[11, 19], [13, 19], [12, 23]]), 'ice', 'diag'); c.shape(ell(12, 12, 1.4, 3), 'cyan', 'orb'); }],
  ['Spritzkörper', 'Auto-Injektor', (c) => up(c, [[rect(8, 5, 16, 18), 'orange', 'diag'], [rect(10, 7, 14, 13), 'ice', 'flat'], [rect(10, 1, 14, 5), 'iron', 'diag'], [rect(11.4, 18, 12.6, 22), 'steel', 'flat']], 35)],
  ['Spritze und Tropfen', 'Mit Tropfen', (c) => { up(c, [[rect(9, 8, 15, 19), 'ice', 'diag'], [rect(9, 12, 15, 19), 'red', 'diag'], [rect(7, 7, 17, 9), 'steel', 'vert'], [rect(11, 1, 13, 7), 'steel', 'flat'], [rect(11.2, 19, 12.8, 22), 'steel', 'flat']], 40, 10, 12); c.shape(poly([[20, 15], [22, 19], [20, 21], [18, 19]]), 'red', 'orb'); }],
  ['Zauber-Ampulle', 'Leuchtend', (c) => { c.shape(ell(12, 14, 6, 7), 'ice', 'orb'); c.shape(rect(10, 4, 14, 9), 'ice', 'diag'); c.shape(rect(9.4, 3, 14.6, 5), 'leather', 'vert'); c.shape(ell(12, 15, 4.6, 5), 'purple', 'orb'); sparkle(c, 12, 14, 2.6); }],
  ['Goldspritze', 'Gold', (c) => up(c, [[rect(9, 8, 15, 19), 'ice', 'diag'], [rect(9, 12, 15, 19), 'gold', 'diag'], [rect(7, 7, 17, 9), 'gold', 'vert'], [rect(11, 1, 13, 7), 'gold', 'flat'], [rect(11.2, 19, 12.8, 22), 'steel', 'flat']], 40)],
  ['Aufrecht', 'Senkrechte Spritze', (c) => up(c, [[rect(9, 7, 15, 19), 'ice', 'diag'], [rect(9, 12, 15, 19), 'cyan', 'diag', 0.1], [rect(6, 6, 18, 8), 'steel', 'vert'], [rect(11, 0, 13, 6), 'steel', 'flat'], [rect(11.2, 19, 12.8, 23), 'steel', 'flat']])],
  ['Zwei Spritzen', 'Gekreuzt', (c) => { const s = [[rect(9, 8, 15, 18), 'ice', 'diag'], [rect(9, 12, 15, 18), 'cyan', 'diag'], [rect(7, 7, 17, 9), 'steel', 'vert'], [rect(11, 1, 13, 7), 'steel', 'flat'], [rect(11.2, 18, 12.8, 22), 'steel', 'flat']]; up(c, s, -40); up(c, s, 40); }],
];

// flask family: alembic (kind 'a') + test tube (kind 't'), 10 styles
const flaskArt = (liq, extra) => (c, kind) => {
  if (kind === 't') {
    c.shape(rect(9, 2, 15, 16), 'ice', 'diag'); c.shape(both(ell(12, 16, 3, 3), rect(0, 16, 24, 24)), 'ice', 'orb'); c.shape(rect(9, 9, 15, 16), liq, 'diag', 0.05); c.shape(both(ell(12, 16, 3, 3), rect(0, 16, 24, 24)), liq, 'orb'); c.shape(rect(8, 1, 16, 3), 'ice', 'vert');
    if (extra) extra(c, 12, 6, 't');
  } else {
    c.shape(rect(10, 2, 14, 8), 'ice', 'diag'); c.shape(ell(12, 15, 8, 7), 'ice', 'orb'); c.shape(ell(12, 16, 6.4, 5.4), liq, 'orb'); c.shape(rect(9, 1, 15, 3), 'ice', 'vert');
    if (extra) extra(c, 12, 14, 'a');
  }
};
const bub = (c, x, y) => { c.shape(ell(x - 2, y - 2, 1.2, 1.2), 'face', 'orb'); c.shape(ell(x + 2, y - 5, 1.6, 1.6), 'face', 'orb'); };
const flask = [
  ['Grün', 'Grüner Trank', flaskArt('green')],
  ['Blau', 'Blauer Trank', flaskArt('blue')],
  ['Rot', 'Roter Trank', flaskArt('red')],
  ['Blubbernd', 'Mit Blasen', flaskArt('green', (c, x, y) => { c.shape(ell(x - 1, y - 4, 1.2, 1.2), 'face', 'orb'); c.shape(ell(x + 2, y - 7, 1.6, 1.6), 'face', 'orb'); c.shape(ell(x - 2, y - 9, 1, 1), 'face', 'orb'); })],
  ['Mit Korken', 'Verkorkt', (c, k) => { flaskArt('orange')(c, k); c.shape(rect(9.6, 0, 14.4, 3), 'leather', 'vert'); }],
  ['Leuchtend', 'Magisch', flaskArt('purple', (c, x, y) => { c.shape(star(x, y, 2.6, 1, 4), 'face', 'flat'); })],
  ['Golden', 'Goldelixier', flaskArt('gold', (c, x, y) => { c.px(x - 2, y, 'face', 4); c.px(x + 2, y + 2, 'face', 4); })],
  ['Mit Herz', 'Heiltrank', flaskArt('red', (c, x, y) => { c.shape(heart(x, y + 1, 2.6), 'face', 'flat'); })],
  ['Giftig', 'Mit Totenkopf', flaskArt('leaf', (c, x, y) => { c.shape(ell(x, y, 2, 1.8), 'face', 'flat'); c.px(x - 1, y, 'black', 1); c.px(x + 1, y, 'black', 1); })],
  ['Eisig', 'Kalter Trank', flaskArt('cyan', (c, x, y) => { c.shape(star(x, y, 2.6, 0.9, 6), 'ice', 'flat'); })],
];

const wand = [
  ['Sternenstab', 'Zauberstab mit Stern', (c) => { c.shape(thick(4, 21, 17, 8, 2.2), 'wood', 'diag'); c.shape(star(18, 6, 5, 2.2, 5), 'bolt', 'orb'); sparkle(c, 21, 14, 2); }],
  ['Kristallstab', 'Stab mit Kristall', (c) => { c.shape(thick(4, 21, 16, 9, 2.2), 'wood', 'diag'); c.shape(poly([[17, 1], [21, 5], [18, 10], [14, 6]]), 'cyan', 'diag'); }],
  ['Magierstab', 'Mit Leuchtkugel', (c) => { c.shape(thick(7, 23, 13, 9, 2.4), 'wood', 'diag'); c.shape(ell(14, 6, 4.6, 4.6), 'purple', 'orb'); c.shape(ring(14, 6, 5.8, 4.6), 'gold', 'flat'); }],
  ['Spiralstab', 'Gedreht', (c) => { c.shape(thick(4, 21, 18, 7, 2.2), 'purple', 'diag'); for (let i = 0; i < 5; i++) c.shape(thick(5 + i * 3, 20 - i * 3, 7 + i * 3, 18 - i * 3 - 1, 1), 'face', 'flat'); sparkle(c, 19, 5, 3.4); }],
  ['Funkenstab', 'Sprühende Funken', (c) => { c.shape(thick(3, 21, 15, 9, 2), 'iron', 'diag'); c.shape(star(17, 7, 3.6, 1.6, 4), 'bolt', 'orb'); sparkle(c, 22, 3, 2.4); sparkle(c, 14, 2, 2); sparkle(c, 22, 12, 2); }],
  ['Ringstab', 'Stab mit Ring', (c) => { c.shape(thick(5, 22, 15, 10, 2.2), 'wood', 'diag'); c.shape(ring(16, 7, 5, 3), 'gold', 'orb'); c.shape(ell(16, 7, 1.6, 1.6), 'red', 'orb'); }],
  ['Edelsteinstab', 'Roter Stein', (c) => { c.shape(thick(5, 22, 16, 9, 2.2), 'leatherd', 'diag'); c.shape(poly([[17, 2], [21, 6], [17, 11], [13, 6]]), 'ruby', 'diag'); c.shape(path([[15, 12], [19, 12]], 1.4), 'gold', 'flat'); }],
  ['Mondstab', 'Sichel an der Spitze', (c) => { c.shape(thick(5, 22, 15, 10, 2.2), 'wood', 'diag'); c.shape(minus(ell(15, 6, 5, 5), ell(18, 4.4, 4.2, 4.2)), 'bolt', 'orb'); }],
  ['Knochenstab', 'Mit Schädel', (c) => { c.shape(thick(5, 22, 15, 10, 2.2), 'face', 'diag'); c.shape(ell(16, 6, 4.4, 4), 'face', 'orb'); c.px(14, 6, 'black', 1); c.px(18, 6, 'black', 1); c.px(16, 9, 'black', 1); }],
  ['Blattstab', 'Naturstab', (c) => { c.shape(thick(5, 22, 15, 10, 2.2), 'bark', 'diag'); c.shape(poly([[14, 10], [16, 2], [22, 5], [19, 11]]), 'leaf', 'diag'); c.line(16, 9, 20, 4, 'leaf', 1); }],
];

const medical = [
  ['Rotes Kreuz', 'Klassisch', (c) => { c.shape(rect(9, 2, 15, 22), 'red', 'diag'); c.shape(rect(2, 9, 22, 15), 'red', 'diag'); c.shape(rect(9, 9, 15, 15), 'red', 'orb', -0.1); }],
  ['Grünes Kreuz', 'Apotheke', (c) => { c.shape(rect(9, 2, 15, 22), 'green', 'diag'); c.shape(rect(2, 9, 22, 15), 'green', 'diag'); }],
  ['Kreuz im Kreis', 'Medaillon', (c) => { c.shape(ell(12, 12, 10.6, 10.6), 'face', 'orb'); c.shape(rect(10, 5, 14, 19), 'red', 'diag'); c.shape(rect(5, 10, 19, 14), 'red', 'diag'); c.shape(ring(12, 12, 10.6, 9.4), 'red', 'flat'); }],
  ['Kreuz auf Schild', 'Schild mit Kreuz', (c) => { c.shape(poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]), 'face', 'diag'); c.shape(rect(10.4, 5, 13.6, 17), 'red', 'diag'); c.shape(rect(6, 8, 18, 11.4), 'red', 'diag'); }],
  ['Auf Tasche', 'Arzttasche', (c) => { c.shape(rect(3, 9, 21, 21), 'leather', 'diag'); c.shape(ring(12, 8, 5, 3.4), 'leatherd', 'flat'); c.shape(rect(10.4, 11, 13.6, 19), 'face', 'flat'); c.shape(rect(7.6, 13.4, 16.4, 16.6), 'face', 'flat'); }],
  ['Kreuz im Herz', 'Heilendes Herz', (c) => { c.shape(heart(12, 12, 9.4), 'red', 'orb'); c.shape(rect(10.4, 7, 13.6, 16), 'face', 'flat'); c.shape(rect(7.4, 10, 16.6, 13), 'face', 'flat'); }],
  ['Rundes Kreuz', 'Weiche Enden', (c) => { c.shape(path([[12, 4], [12, 20]], 6), 'red', 'orb'); c.shape(path([[4, 12], [20, 12]], 6), 'red', 'orb'); c.shape(ell(12, 4, 3, 3), 'red', 'orb'); c.shape(ell(12, 20, 3, 3), 'red', 'orb'); c.shape(ell(4, 12, 3, 3), 'red', 'orb'); c.shape(ell(20, 12, 3, 3), 'red', 'orb'); }],
  ['Weiß auf Rot', 'Quadrat', (c) => { c.shape(rect(2, 2, 22, 22), 'red', 'diag'); c.shape(rect(10, 5, 14, 19), 'face', 'flat'); c.shape(rect(5, 10, 19, 14), 'face', 'flat'); }],
  ['Geflügelt', 'Kreuz mit Flügeln', (c) => { c.shape(poly([[1, 8], [8, 9], [8, 14], [3, 14]]), 'face', 'diag'); c.shape(poly([[23, 8], [16, 9], [16, 14], [21, 14]]), 'face', 'diag'); c.shape(rect(10, 3, 14, 21), 'red', 'diag'); c.shape(rect(6, 8, 18, 12), 'red', 'diag'); }],
  ['Auf Fahne', 'Heilerflagge', (c) => { c.shape(rect(4, 2, 6, 22), 'wood', 'diag'); c.shape(poly([[6, 3], [21, 3], [21, 14], [6, 14]]), 'face', 'diag'); c.shape(rect(12, 5, 15, 12), 'red', 'flat'); c.shape(rect(9, 7.4, 18, 10), 'red', 'flat'); }],
];

const trap = [
  ['Bärenfalle', 'Zwei Zackenbügel', (c) => { c.shape(rect(2, 15, 22, 19), 'iron', 'vert'); c.shape(poly([[3, 15], [5, 8], [8, 15], [10, 7], [12, 15], [14, 7], [16, 15], [19, 8], [21, 15]]), 'steel', 'diag'); c.shape(ell(12, 17, 2.4, 1.4), 'bolt', 'orb'); }],
  ['Grube', 'Fallgrube mit Spitzen', (c) => { c.shape(rect(1, 6, 23, 9), 'moss', 'vert'); c.shape(rect(3, 9, 21, 22), 'coal', 'vert'); for (const x of [6, 10, 14, 18]) c.shape(poly([[x - 1.4, 22], [x, 14], [x + 1.4, 22]]), 'wood', 'diag'); }],
  ['Schlinge', 'Seilschlinge', (c) => { c.shape(ring(12, 11, 7, 4.6), 'sand', 'orb'); c.shape(path([[12, 18], [12, 22]], 1.6), 'sand', 'flat'); c.shape(rect(10, 2, 14, 5), 'wood', 'diag'); c.shape(path([[12, 5], [12, 6]], 1.4), 'sand', 'flat'); }],
  ['Käfigfalle', 'Holzkäfig', (c) => { c.shape(rect(3, 5, 21, 20), 'wood', 'diag'); c.shape(minus(rect(5, 7, 19, 18), rect(5, 7, 5, 7)), 'black', 'flat'); for (const x of [5.4, 9, 12.6, 16.2]) c.shape(rect(x, 5, x + 1.8, 20), 'woodl', 'diag'); c.shape(rect(3, 5, 21, 6.6), 'wood', 'vert'); }],
  ['Mausefalle', 'Brett mit Bügel', (c) => { c.shape(rect(3, 11, 21, 20), 'woodl', 'diag'); c.shape(path([[5, 14], [5, 6], [16, 6]], 1.2), 'steel', 'flat'); c.shape(rect(16, 12, 19, 15), 'bolt', 'flat'); c.px(7, 17, 'iron', 4); }],
  ['Fangnetz', 'Netz', (c) => { c.shape(ell(12, 12, 10, 10), 'sand', 'orb', 0.1); for (const v of [-6, -2, 2, 6]) { c.shape(rect(12 + v - 0.5, 2, 12 + v + 0.5, 22), 'leather', 'flat'); c.shape(rect(2, 12 + v - 0.5, 22, 12 + v + 0.5), 'leather', 'flat'); } c.shape(ring(12, 12, 10.6, 9.6), 'leather', 'flat'); }],
  ['Stolperdraht', 'Draht zwischen Pflöcken', (c) => { c.shape(rect(3, 8, 5, 20), 'wood', 'diag'); c.shape(rect(19, 8, 21, 20), 'wood', 'diag'); c.shape(path([[5, 14], [12, 16], [19, 14]], 1), 'steel', 'flat'); c.shape(ell(12, 21, 11, 1.4), 'moss', 'vert'); }],
  ['Mit Köder', 'Käfig mit Köder', (c) => { c.shape(poly([[3, 20], [3, 10], [12, 3], [21, 10], [21, 20]]), 'iron', 'diag'); c.shape(poly([[7, 20], [7, 12], [12, 8], [17, 12], [17, 20]]), 'black', 'flat'); c.shape(ell(12, 17, 2.4, 2), 'meat', 'orb'); }],
  ['Fangeisen', 'Offen im Gras', (c) => { c.shape(ell(12, 20, 11, 2.6), 'moss', 'vert'); c.shape(ring(12, 15, 8, 5), 'iron', 'orb'); c.shape(poly([[5, 15], [7, 11], [9, 15]]), 'steel', 'diag'); c.shape(poly([[15, 15], [17, 11], [19, 15]]), 'steel', 'diag'); c.shape(ell(12, 15, 2, 1.2), 'bolt', 'orb'); }],
  ['Zugfalle', 'Fallbrett', (c) => { c.shape(rect(2, 4, 22, 8), 'wood', 'vert'); c.shape(rect(4, 8, 6, 20), 'wood', 'diag'); c.shape(rect(18, 8, 20, 20), 'wood', 'diag'); c.shape(rect(1, 20, 23, 22), 'moss', 'vert'); c.shape(ell(12, 17, 2.4, 2), 'bread', 'orb'); }],
];

const CONCEPTS = [
  { cat: 'Werkzeug', key: 'hammer', name: 'Hammer', designs: hammer },
  { cat: 'Werkzeug', key: 'axe', name: 'Axt', designs: axe },
  { cat: 'Werkzeug', key: 'pickaxe', name: 'Spitzhacke', designs: pickaxe },
  { cat: 'Werkzeug', key: 'saw', name: 'Säge', designs: saw },
  { cat: 'Werkzeug', key: 'wrench', name: 'Schraubenschlüssel', designs: wrench },
  { cat: 'Werkzeug', key: 'scissors', name: 'Schere', designs: scissors },
  { cat: 'Werkzeug', key: 'bandage', name: 'Verband', designs: bandage },
  { cat: 'Werkzeug', key: 'syringe', name: 'Spritze', designs: syringe },
  { cat: 'Werkzeug', family: 'flask', name: 'Kolben & Reagenzglas', designs: flask, outs: [['alembic', 'Kolben', 'a', null], ['testtube', 'Reagenzglas', 't', null]] },
  { cat: 'Werkzeug', key: 'wand', name: 'Zauberstab', designs: wand },
  { cat: 'Werkzeug', key: 'medical', name: 'Heilkreuz', designs: medical },
  { cat: 'Werkzeug', key: 'trap', name: 'Falle', designs: trap },
];
module.exports = { CONCEPTS };
