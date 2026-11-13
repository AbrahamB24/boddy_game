// Batch 5: nature and objects.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const smoke = (c, x, y) => { c.shape(ell(x, y, 2.2, 2), 'ice', 'orb'); c.shape(ell(x + 2, y - 3, 2.6, 2.2), 'ice', 'orb'); };
const xmark = (c, x, y, r = 'red') => { c.shape(thick(x - 2.2, y - 2.2, x + 2.2, y + 2.2, 1.6), r, 'flat'); c.shape(thick(x + 2.2, y - 2.2, x - 2.2, y + 2.2, 1.6), r, 'flat'); };
const land = (c, pts) => c.shape(poly(pts), 'green', 'diag');

const map = [
  ['Pergamentkarte', 'Mit Schatzkreuz', (c) => { c.shape(rect(3, 4, 21, 20), 'paper', 'diag'); c.shape(rect(2, 3, 4, 21), 'leather', 'diag'); c.shape(rect(20, 3, 22, 21), 'leather', 'diag'); land(c, [[7, 14], [9, 8], [14, 9], [12, 15]]); xmark(c, 16, 14); }],
  ['Gefaltet', 'Dreifach gefaltet', (c) => { c.shape(poly([[2, 6], [8, 4], [8, 20], [2, 22]]), 'paper', 'diag'); c.shape(poly([[8, 4], [16, 6], [16, 22], [8, 20]]), 'paper', 'diag', 0.2); c.shape(poly([[16, 6], [22, 4], [22, 20], [16, 22]]), 'paper', 'diag'); land(c, [[10, 10], [14, 11], [13, 16], [10, 15]]); c.line(18, 9, 20, 9, 'blue', 2); }],
  ['Schriftrolle', 'Halb aufgerollt', (c) => { c.shape(rect(4, 5, 20, 19), 'paper', 'diag'); c.shape(ell(5, 12, 3, 8), 'paper', 'orb', -0.1); c.shape(ell(5, 12, 1.4, 6), 'bread', 'flat'); for (const y of [8, 11, 14]) c.line(9, y, 17, y, 'leather', 2); }],
  ['Mit Route', 'Gestrichelter Weg', (c) => { c.shape(rect(2, 3, 22, 21), 'paper', 'diag'); for (const [x, y] of [[5, 17], [8, 14], [11, 15], [14, 11], [17, 8]]) c.shape(ell(x, y, 1, 1), 'red', 'flat'); xmark(c, 19, 6); c.shape(ell(5, 18, 1.6, 1.6), 'blue', 'orb'); }],
  ['Weltkarte', 'Kontinente auf Blau', (c) => { c.shape(rect(2, 4, 22, 20), 'blue', 'diag'); land(c, [[4, 8], [9, 6], [11, 11], [7, 15], [5, 12]]); land(c, [[13, 7], [19, 8], [18, 14], [14, 17], [13, 11]]); }],
  ['Mit Kompassrose', 'Pergament mit Stern', (c) => { c.shape(rect(3, 3, 21, 21), 'paper', 'diag'); c.shape(star(12, 12, 7.4, 2.2, 4), 'red', 'orb'); c.shape(ell(12, 12, 1.4, 1.4), 'face', 'flat'); c.shape(ring(12, 12, 8.6, 8), 'leather', 'flat'); }],
  ['Angebrannt', 'Alte Schatzkarte', (c) => { c.shape(poly([[3, 5], [10, 3], [14, 5], [21, 4], [20, 12], [22, 18], [14, 21], [8, 19], [3, 20]]), 'paper', 'diag', 0.1); c.shape(poly([[3, 5], [5, 5], [3, 8]]), 'coal', 'flat'); c.shape(poly([[22, 18], [19, 20], [22, 20]]), 'coal', 'flat'); xmark(c, 14, 12); c.line(6, 16, 10, 12, 'leather', 2); }],
  ['Poster mit Pin', 'Aufgehängt', (c) => { c.shape(rect(3, 3, 21, 21), 'paper', 'diag'); land(c, [[5, 8], [10, 6], [12, 12], [6, 15]]); c.shape(ell(15, 8, 2, 2), 'red', 'orb'); c.shape(rect(14.4, 10, 15.6, 15), 'steel', 'flat'); }],
  ['Kachelkarte', 'Raster aus Feldern', (c) => { for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) c.shape(rect(2 + i * 5, 2 + j * 5, 6 + i * 5, 6 + j * 5), (i + j * 2) % 3 === 0 ? 'blue' : (i * j) % 2 ? 'green' : 'sand', 'vert'); }],
  ['Minikarte', 'Gerahmt', (c) => { c.shape(rect(2, 2, 22, 22), 'iron', 'diag'); c.shape(rect(4, 4, 20, 20), 'sand', 'vert'); land(c, [[5, 5], [12, 5], [10, 12], [5, 11]]); c.shape(rect(13, 13, 19, 19), 'blue', 'vert'); c.shape(ell(11, 12, 1.8, 1.8), 'red', 'orb'); }],
];

const globe = [
  ['Globus', 'Blau mit Land, auf Fuß', (c) => { c.shape(ell(12, 11, 9, 9), 'blue', 'orb'); c.shape(both(ell(12, 11, 9, 9), poly([[5, 9], [10, 5], [13, 9], [9, 14], [6, 13]])), 'green', 'orb'); c.shape(both(ell(12, 11, 9, 9), poly([[14, 12], [19, 11], [17, 17], [14, 16]])), 'green', 'orb'); c.shape(rect(11, 20, 13, 22), 'brass', 'flat'); c.shape(rect(7, 21.4, 17, 23), 'brass', 'vert'); }],
  ['Kugel', 'Nur die Erde', (c) => { c.shape(ell(12, 12, 10, 10), 'blue', 'orb'); c.shape(both(ell(12, 12, 10, 10), poly([[3, 9], [9, 4], [13, 8], [8, 14], [4, 14]])), 'green', 'orb'); c.shape(both(ell(12, 12, 10, 10), poly([[14, 13], [21, 11], [19, 19], [14, 20]])), 'green', 'orb'); }],
  ['Mit Gitter', 'Längen- und Breitenlinien', (c) => { c.shape(ell(12, 12, 10, 10), 'blue', 'orb'); c.shape(ring(12, 12, 10, 9), 'cyan', 'flat'); c.shape(ring(12, 12, 4.6, 3.8), 'cyan', 'flat'); c.shape(rect(2, 11.4, 22, 12.6), 'cyan', 'flat'); c.shape(rect(11.4, 2, 12.6, 22), 'cyan', 'flat'); }],
  ['Im Messingring', 'Mit Gestell', (c) => { c.shape(ell(12, 12, 8, 8), 'blue', 'orb'); c.shape(both(ell(12, 12, 8, 8), poly([[6, 8], [11, 5], [12, 10], [8, 13]])), 'green', 'orb'); c.shape(ring(12, 12, 11, 9.8), 'brass', 'orb'); c.shape(rect(9, 21, 15, 22.6), 'brass', 'vert'); }],
  ['Ringplanet', 'Mit Ring', (c) => { c.shape(ell(12, 12, 7, 7), 'orange', 'orb'); c.shape(minus(ell(12, 12, 11.4, 3.6), ell(12, 12, 7.4, 2)), 'sand', 'vert'); c.shape(both(ell(12, 12, 7, 7), rect(0, 12, 24, 24)), 'orange', 'orb', 0.12); }],
  ['Halbkugel', 'Aufgeschnitten', (c) => { c.shape(both(ell(12, 12, 10, 10), rect(0, 0, 24, 12)), 'blue', 'orb'); c.shape(rect(2, 12, 22, 14), 'stone', 'vert'); c.shape(both(ell(12, 12, 10, 10), poly([[4, 9], [9, 4], [13, 8], [8, 12], [4, 12]])), 'green', 'orb'); c.shape(rect(2, 14, 22, 20), 'clay', 'vert'); }],
  ['Kantig', 'Low-Poly-Kugel', (c) => { c.shape(poly([[12, 2], [19, 5], [22, 12], [19, 19], [12, 22], [5, 19], [2, 12], [5, 5]]), 'blue', 'diag'); c.shape(poly([[12, 2], [19, 5], [12, 12], [5, 5]]), 'cyan', 'vert', -0.1); c.shape(poly([[12, 12], [22, 12], [19, 19]]), 'green', 'diag'); c.shape(poly([[2, 12], [12, 12], [5, 19]]), 'green', 'diag'); }],
  ['Mit Wolken', 'Weiße Wolkenstreifen', (c) => { c.shape(ell(12, 12, 10, 10), 'blue', 'orb'); c.shape(both(ell(12, 12, 10, 10), poly([[4, 9], [9, 4], [13, 8], [8, 14], [4, 14]])), 'green', 'orb'); for (const [x, y, w] of [[6, 7, 6], [13, 14, 7], [5, 17, 4]]) c.shape(both(ell(12, 12, 10, 10), rect(x, y, x + w, y + 1.6)), 'face', 'flat'); }],
  ['Kleine Welt', 'Winziger Globus mit Stern', (c) => { c.shape(ell(10, 13, 7, 7), 'blue', 'orb'); c.shape(both(ell(10, 13, 7, 7), poly([[4, 11], [8, 8], [11, 12], [6, 15]])), 'green', 'orb'); sparkle(c, 19, 5, 4); sparkle(c, 4, 4, 2); }],
  ['Weltscheibe', 'Flache Scheibe', (c) => { c.shape(ell(12, 14, 11, 5), 'green', 'vert'); c.shape(ell(12, 12, 11, 5), 'sand', 'orb'); c.shape(ell(12, 12, 8, 3), 'green', 'orb'); c.shape(ell(12, 12, 4, 1.4), 'blue', 'flat'); }],
];

const compass = [
  ['Messingkompass', 'Nadel rot-weiß', (c) => { c.shape(ell(12, 12, 10, 10), 'brass', 'orb'); c.shape(ell(12, 12, 8, 8), 'face', 'orb', -0.1); c.shape(poly([[12, 3], [15, 12], [9, 12]]), 'red', 'diag'); c.shape(poly([[12, 21], [15, 12], [9, 12]]), 'steel', 'diag'); c.shape(ell(12, 12, 1.2, 1.2), 'brass', 'orb'); }],
  ['Windrose', 'Vierzack', (c) => { c.shape(star(12, 12, 11, 3, 4), 'red', 'orb'); c.shape(poly([[12, 12], [22, 12], [12, 14]]), 'face', 'flat'); c.shape(ell(12, 12, 1.8, 1.8), 'gold', 'orb'); }],
  ['Taschenkompass', 'Mit Deckel und Öse', (c) => { c.shape(ell(12, 14, 8.6, 8.6), 'brass', 'orb'); c.shape(ell(12, 14, 6.6, 6.6), 'face', 'orb', -0.1); c.shape(ring(12, 3.6, 2.4, 1), 'brass', 'orb'); c.shape(poly([[12, 8], [14, 14], [10, 14]]), 'red', 'diag'); c.shape(poly([[12, 20], [14, 14], [10, 14]]), 'steel', 'diag'); }],
  ['Achtstern', 'Acht Zacken', (c) => { c.shape(star(12, 12, 11, 4, 8), 'blue', 'orb'); c.shape(star(12, 12, 5.4, 2, 4), 'goldl', 'orb'); }],
  ['Richtungspfeil', 'Nordost im Kreis', (c) => { c.shape(ell(12, 12, 10, 10), 'iron', 'orb'); c.shape(poly([[17, 7], [15, 16], [12, 12], [8, 9]]), 'red', 'diag'); c.shape(ell(12, 12, 1.2, 1.2), 'face', 'flat'); c.shape(ring(12, 12, 10, 8.8), 'steel', 'flat'); }],
  ['Magnetnadel', 'Nur die Nadel', (c) => { c.shape(poly([[12, 1], [15, 12], [9, 12]]), 'red', 'diag'); c.shape(poly([[12, 23], [15, 12], [9, 12]]), 'steel', 'diag'); c.shape(ell(12, 12, 2.4, 2.4), 'brass', 'orb'); }],
  ['Sechseck-Kompass', 'Eckiges Gehäuse', (c) => { c.shape(poly([[7, 2], [17, 2], [22, 12], [17, 22], [7, 22], [2, 12]]), 'iron', 'diag'); c.shape(ell(12, 12, 7, 7), 'face', 'orb', -0.1); c.shape(poly([[12, 6], [14, 12], [10, 12]]), 'red', 'diag'); c.shape(poly([[12, 18], [14, 12], [10, 12]]), 'blue', 'diag'); }],
  ['Steuerrad', 'Schiffsrad', (c) => { c.shape(ring(12, 12, 7, 5.2), 'wood', 'orb'); for (let a = 0; a < 8; a++) { const t = a * 0.785; c.shape(path([[12 + 6 * Math.cos(t), 12 + 6 * Math.sin(t)], [12 + 11 * Math.cos(t), 12 + 11 * Math.sin(t)]], 2.2), 'woodl', 'diag'); } c.shape(ell(12, 12, 2.6, 2.6), 'brass', 'orb'); }],
  ['Fernglas', 'Spähen', (c) => { c.shape(thick(7, 18, 7, 8, 5), 'iron', 'diag'); c.shape(thick(17, 18, 17, 8, 5), 'iron', 'diag'); c.shape(rect(7, 11, 17, 14), 'iron', 'vert'); c.shape(ell(7, 6, 3.2, 2.4), 'cyan', 'orb'); c.shape(ell(17, 6, 3.2, 2.4), 'cyan', 'orb'); c.shape(rect(4, 18, 10, 21), 'iron', 'vert'); c.shape(rect(14, 18, 20, 21), 'iron', 'vert'); }],
  ['N-Marke', 'Nordpfeil', (c) => { c.shape(ell(12, 12, 10, 10), 'blue', 'orb'); c.shape(poly([[12, 3], [16, 13], [12, 11], [8, 13]]), 'face', 'diag'); c.shape(poly([[12, 21], [14, 14], [12, 12], [10, 14]]), 'red', 'diag'); }],
];

const sun = [
  ['Sonne', 'Scheibe mit Dreieckstrahlen', (c) => { c.shape(star(12, 12, 11, 7, 12), 'orange', 'orb'); c.shape(ell(12, 12, 6.4, 6.4), 'bolt', 'orb'); }],
  ['Strahlenkranz', 'Linienstrahlen', (c) => { c.shape(ell(12, 12, 6, 6), 'bolt', 'orb'); for (let a = 0; a < 8; a++) { const t = a * 0.785; c.shape(path([[12 + 8 * Math.cos(t), 12 + 8 * Math.sin(t)], [12 + 11 * Math.cos(t), 12 + 11 * Math.sin(t)]], 2), 'orange', 'flat'); } }],
  ['Sonnenaufgang', 'Halb über dem Horizont', (c) => { c.shape(both(ell(12, 17, 8, 8), rect(0, 0, 24, 17)), 'bolt', 'orb'); c.shape(rect(1, 17, 23, 19), 'orange', 'vert'); for (const [a, b, d, e] of [[12, 3, 12, 6], [4, 7, 6, 9], [20, 7, 18, 9], [1, 14, 4, 14], [23, 14, 20, 14]]) c.line(a, b, d, e, 'orange', 2); c.shape(rect(1, 19, 23, 22), 'blue', 'vert'); }],
  ['Sonnengesicht', 'Lächelnd', (c) => { c.shape(star(12, 12, 11, 8, 12), 'orange', 'orb'); c.shape(ell(12, 12, 7.4, 7.4), 'bolt', 'orb'); c.px(9, 10, 'black', 1); c.px(15, 10, 'black', 1); c.shape(path([[9, 14], [12, 16], [15, 14]], 1), 'black', 'flat'); }],
  ['Sonne und Wolke', 'Wolke davor', (c) => { c.shape(star(9, 9, 8, 5.4, 10), 'orange', 'orb'); c.shape(ell(9, 9, 4.6, 4.6), 'bolt', 'orb'); c.shape(ell(10, 16, 5, 4), 'face', 'orb'); c.shape(ell(16, 15, 5, 4.4), 'face', 'orb'); c.shape(rect(6, 16, 20, 20), 'ice', 'vert'); }],
  ['Gleißend', 'Spitze Sternform', (c) => { c.shape(star(12, 12, 11.4, 4.6, 8), 'bolt', 'orb'); c.shape(ell(12, 12, 4.4, 4.4), 'face', 'orb', -0.1); }],
  ['Im Ring', 'Sonne in Medaillon', (c) => { c.shape(ell(12, 12, 10.6, 10.6), 'blue', 'orb'); c.shape(ell(12, 12, 5.4, 5.4), 'bolt', 'orb'); for (let a = 0; a < 8; a++) { const t = a * 0.785; c.shape(ell(12 + 8 * Math.cos(t), 12 + 8 * Math.sin(t), 1, 1), 'bolt', 'flat'); } }],
  ['Goldsonne', 'Wie eine Münze', (c) => { c.shape(star(12, 12, 11, 8.4, 16), 'gold', 'orb'); c.shape(ell(12, 12, 7, 7), 'goldl', 'orb'); c.shape(ring(12, 12, 4.4, 3.4), 'gold', 'flat'); }],
  ['Blume', 'Sonnenblume', (c) => { for (let a = 0; a < 10; a++) { const t = a * 0.628; c.shape(ell(12 + 7.4 * Math.cos(t), 12 + 7.4 * Math.sin(t), 3, 3), 'bolt', 'orb'); } c.shape(ell(12, 12, 5, 5), 'bark', 'orb'); }],
  ['Abendsonne', 'Tief über dem Wasser', (c) => { c.shape(both(ell(12, 13, 7, 7), rect(0, 0, 24, 14)), 'orange', 'orb'); c.shape(rect(1, 14, 23, 22), 'blue', 'vert'); c.shape(rect(6, 16, 18, 17.4), 'orange', 'flat'); c.shape(rect(9, 19, 15, 20.4), 'orange', 'flat'); }],
];

const moon = [
  ['Mondsichel', 'Klassisch', (c) => c.shape(minus(ell(11, 12, 9, 9), ell(15, 10, 8, 8)), 'bolt', 'orb')],
  ['Vollmond', 'Mit Kratern', (c) => { c.shape(ell(12, 12, 10, 10), 'face', 'orb'); for (const [x, y, r] of [[8, 9, 2.2], [15, 14, 2.6], [10, 16, 1.4], [16, 7, 1.2]]) c.shape(ell(x, y, r, r), 'stone2', 'orb', 0.3); }],
  ['Mond und Stern', 'Sichel mit Stern', (c) => { c.shape(minus(ell(10, 12, 8, 8), ell(14, 10, 7, 7)), 'bolt', 'orb'); c.shape(star(18, 8, 3.6, 1.6, 5), 'bolt', 'orb'); sparkle(c, 6, 20, 2); }],
  ['Mondgesicht', 'Schlafende Sichel', (c) => { c.shape(minus(ell(11, 12, 9.4, 9.4), ell(16, 10, 8.4, 8.4)), 'bolt', 'orb'); c.shape(path([[6, 10], [8, 11]], 1), 'black', 'flat'); c.shape(path([[8, 15], [9, 17]], 1), 'black', 'flat'); }],
  ['Halbmond', 'Halber Mond', (c) => { c.shape(both(ell(12, 12, 10, 10), rect(0, 0, 12, 24)), 'face', 'orb'); c.shape(both(ell(12, 12, 10, 10), rect(12, 0, 24, 24)), 'steel', 'orb', 0.25); }],
  ['Hinter Wolken', 'Mond und Wolke', (c) => { c.shape(minus(ell(10, 9, 8, 8), ell(14, 7, 7, 7)), 'bolt', 'orb'); c.shape(ell(9, 17, 5.4, 4), 'steel', 'orb'); c.shape(ell(15, 16, 5.6, 4.6), 'steel', 'orb'); c.shape(rect(5, 17, 20, 20), 'iron', 'vert', -0.1); }],
  ['Medaillon', 'Mond in blauem Kreis', (c) => { c.shape(ell(12, 12, 10.6, 10.6), 'navy', 'orb'); c.shape(minus(ell(11, 12, 6, 6), ell(14, 10.5, 5.2, 5.2)), 'bolt', 'orb'); sparkle(c, 18, 6, 2); sparkle(c, 6, 17, 1.8); }],
  ['Sternenhimmel', 'Sichel und Sterne', (c) => { c.shape(minus(ell(9, 11, 7, 7), ell(12, 9, 6, 6)), 'bolt', 'orb'); for (const [x, y, s] of [[17, 5, 2.6], [20, 13, 2], [14, 19, 3], [5, 20, 2]]) c.shape(star(x, y, s, s * 0.45, 5), 'bolt', 'orb'); }],
  ['Dicker Mond', 'Fast voll', (c) => { c.shape(minus(ell(12, 12, 10, 10), ell(18, 12, 6.4, 8.6)), 'bolt', 'orb'); c.px(8, 9, 'orange', 2); c.px(9, 15, 'orange', 2); }],
  ['Über Hügeln', 'Mond am Horizont', (c) => { c.shape(ell(14, 9, 6, 6), 'face', 'orb'); c.shape(ell(6, 22, 10, 6), 'forest', 'orb'); c.shape(ell(19, 23, 9, 5), 'forest', 'orb', 0.1); }],
];

const wave = [
  ['Welle', 'Brechende Welle', (c) => { c.shape(poly([[1, 21], [1, 14], [5, 8], [11, 5], [17, 7], [19, 11], [16, 11], [13, 9], [9, 11], [10, 16], [22, 16], [22, 21]]), 'blue', 'diag'); c.shape(poly([[11, 5], [17, 7], [19, 11], [16, 11], [13, 9]]), 'face', 'vert'); }],
  ['Drei Wellenlinien', 'Stilisiert', (c) => { for (const y of [6, 12, 18]) c.shape(path([[2, y], [6, y - 3], [10, y], [14, y - 3], [18, y], [22, y - 3]], 2.4), 'blue', 'diag'); }],
  ['Schaumkrone', 'Mit Gischt', (c) => { c.shape(rect(1, 14, 23, 22), 'blue', 'vert'); c.shape(poly([[1, 14], [6, 8], [12, 11], [17, 6], [23, 14]]), 'blue', 'diag'); c.shape(path([[3, 13], [6, 9], [9, 11]], 1.6), 'face', 'flat'); c.shape(path([[14, 10], [17, 7], [20, 10]], 1.6), 'face', 'flat'); for (const [x, y] of [[8, 6], [19, 4], [4, 5]]) c.shape(ell(x, y, 1, 1), 'face', 'orb'); }],
  ['Hokusai', 'Große Kurvenwelle', (c) => { c.shape(poly([[1, 22], [2, 14], [7, 6], [14, 3], [19, 6], [17, 9], [13, 8], [10, 11], [11, 17], [23, 17], [23, 22]]), 'navy', 'diag'); for (const [x, y] of [[9, 4], [13, 2], [17, 4]]) c.shape(ell(x, y, 1.6, 1.6), 'face', 'orb'); c.shape(path([[8, 8], [12, 5], [16, 7]], 1.6), 'face', 'flat'); }],
  ['Ringwellen', 'Kreise im Wasser', (c) => { c.shape(ring(12, 12, 10, 8.6), 'cyan', 'flat'); c.shape(ring(12, 12, 6.6, 5.2), 'cyan', 'flat'); c.shape(ell(12, 12, 2.4, 2.4), 'blue', 'orb'); }],
  ['Wasserschnitt', 'Meer von der Seite', (c) => { c.shape(rect(1, 8, 23, 22), 'blue', 'vert'); c.shape(path([[1, 8], [5, 5], [9, 8], [13, 5], [17, 8], [21, 5], [23, 7]], 2.2), 'cyan', 'diag'); c.line(4, 14, 9, 14, 'cyan', 1); c.line(13, 18, 19, 18, 'cyan', 1); }],
  ['Im Kreis', 'Welle in Medaillon', (c) => { c.shape(ell(12, 12, 10.6, 10.6), 'blue', 'orb'); c.shape(path([[4, 12], [8, 8], [12, 12], [16, 8], [20, 12]], 2), 'face', 'flat'); c.shape(path([[4, 17], [8, 13], [12, 17], [16, 13], [20, 17]], 1.6), 'cyan', 'flat'); }],
  ['Tropfen auf See', 'Tropfen und Ringe', (c) => { c.shape(poly([[12, 2], [16, 8], [12, 11], [8, 8]]), 'cyan', 'orb'); c.shape(ell(12, 8.4, 4, 3.6), 'cyan', 'orb'); c.shape(ring(12, 18, 10, 8), 'blue', 'flat'); c.shape(ring(12, 18, 5, 3.4), 'blue', 'flat'); }],
  ['Segelboot', 'Boot auf Wellen', (c) => { c.shape(poly([[11, 2], [11, 14], [4, 14]]), 'face', 'diag'); c.shape(poly([[13, 5], [13, 14], [19, 14]]), 'face', 'diag', 0.2); c.shape(poly([[3, 14], [21, 14], [18, 18], [6, 18]]), 'wood', 'vert'); c.shape(rect(1, 18, 23, 22), 'blue', 'vert'); c.shape(path([[1, 18], [5, 16.4], [9, 18], [13, 16.4], [17, 18], [21, 16.4]], 1.6), 'cyan', 'flat'); }],
  ['Zackenwelle', 'Eckig', (c) => { c.shape(poly([[1, 22], [1, 12], [5, 7], [9, 12], [13, 7], [17, 12], [21, 7], [23, 10], [23, 22]]), 'blue', 'diag'); c.shape(poly([[1, 12], [5, 7], [9, 12], [5, 10]]), 'cyan', 'vert'); }],
];

const candle = [
  ['Kerze', 'Mit Flamme', (c) => { c.shape(rect(8, 10, 16, 21), 'face', 'diag'); c.shape(ell(12, 10, 4, 1.6), 'face', 'orb'); c.line(12, 8, 12, 10, 'black', 1); c.shape(poly([[12, 2], [15, 6], [14, 9], [12, 10], [10, 9], [9, 6]]), 'orange', 'vert'); c.shape(ell(12, 7.4, 1.4, 2), 'goldl', 'orb'); }],
  ['Im Halter', 'Messinghalter', (c) => { c.shape(rect(9, 7, 15, 15), 'face', 'diag'); c.shape(poly([[12, 1], [14.6, 4.4], [13.8, 7], [12, 7.4], [10.2, 7], [9.4, 4.4]]), 'orange', 'vert'); c.shape(minus(ell(12, 17, 8, 3), ell(12, 16, 5, 1.4)), 'brass', 'orb'); c.shape(rect(11, 17, 13, 20), 'brass', 'diag'); c.shape(ell(12, 21, 6, 1.6), 'brass', 'vert'); }],
  ['Drei Kerzen', 'Unterschiedlich hoch', (c) => { for (const [x, y] of [[3, 12], [9, 6], [15, 10]]) { c.shape(rect(x, y, x + 5, 21), 'face', 'diag'); c.shape(poly([[x + 2.5, y - 5], [x + 4.4, y - 2], [x + 2.5, y - 0.4], [x + 0.6, y - 2]]), 'orange', 'vert'); } }],
  ['Laterne', 'Mit Glas', (c) => { c.shape(rect(6, 6, 18, 20), 'iron', 'diag'); c.shape(rect(8, 8, 16, 18), 'goldl', 'orb', -0.1); c.shape(poly([[7, 6], [12, 1], [17, 6]]), 'iron', 'vert'); c.shape(ring(12, 2, 2, 1), 'iron', 'flat'); c.shape(ell(12, 14, 2, 3), 'orange', 'orb'); c.shape(rect(5, 20, 19, 22), 'iron', 'vert'); }],
  ['Kerzenleuchter', 'Drei Arme', (c) => { c.shape(rect(11, 8, 13, 20), 'brass', 'diag'); c.shape(path([[3, 10], [6, 15], [12, 16], [18, 15], [21, 10]], 1.8), 'brass', 'diag'); for (const x of [3, 12, 21]) { const y = x === 12 ? 4 : 6; c.shape(rect(x - 1.4, y, x + 1.4, y + 4), 'face', 'diag'); c.shape(poly([[x, y - 3.5], [x + 1.4, y - 1], [x, y + 0.2], [x - 1.4, y - 1]]), 'orange', 'vert'); } c.shape(rect(7, 20, 17, 22), 'brass', 'vert'); }],
  ['Stummel', 'Heruntergebrannt', (c) => { c.shape(rect(7, 14, 17, 20), 'face', 'diag'); c.shape(ell(12, 14, 5, 1.6), 'face', 'orb'); c.shape(rect(6, 19, 18, 21), 'face', 'vert', 0.1); c.shape(poly([[12, 7], [14.4, 11], [12, 13], [9.6, 11]]), 'orange', 'vert'); c.line(8, 15, 8, 19, 'face', 4); }],
  ['Öllampe', 'Mit Henkel', (c) => { c.shape(ell(12, 15, 8, 5), 'brass', 'orb'); c.shape(rect(10, 8, 14, 11), 'brass', 'diag'); c.shape(poly([[12, 2], [14.4, 5], [12, 8], [9.6, 5]]), 'orange', 'vert'); c.shape(path([[4, 14], [2, 10], [6, 9]], 1.4), 'brass', 'diag'); c.shape(poly([[19, 14], [23, 12], [20, 17]]), 'brass', 'diag'); }],
  ['Auf Schale', 'Kerze mit Untersetzer', (c) => { c.shape(rect(9, 6, 15, 17), 'face', 'diag'); c.shape(poly([[12, 0], [14.4, 3], [12, 6], [9.6, 3]]), 'orange', 'vert'); c.shape(ell(12, 19, 9, 3), 'blue', 'orb'); c.shape(ell(12, 18, 6.6, 1.6), 'face', 'flat'); }],
  ['Leuchtkugel', 'Magisches Licht', (c) => { c.shape(ell(12, 12, 9, 9), 'goldl', 'orb'); c.shape(ell(12, 12, 5, 5), 'face', 'orb', -0.2); for (const [x, y] of [[3, 3], [21, 4], [20, 21], [3, 20]]) sparkle(c, x, y, 2.4); }],
  ['Fackelkerze', 'Dicke Wachskerze', (c) => { c.shape(rect(6, 8, 18, 21), 'red', 'diag'); c.shape(ell(12, 8, 6, 2), 'red', 'orb', -0.1); c.shape(poly([[12, 0], [15.4, 5], [12, 8], [8.6, 5]]), 'orange', 'vert'); c.shape(poly([[8, 8], [8, 13], [10, 13], [10, 8]]), 'red', 'vert', 0.2); }],
];

const crate = [
  ['Holzkiste', 'Mit Kreuzlatten', (c) => { c.shape(rect(2, 3, 22, 21), 'wood', 'diag'); c.shape(minus(rect(2, 3, 22, 21), rect(4.4, 5.4, 19.6, 18.6)), 'woodl', 'vert'); c.shape(thick(4, 5, 20, 19, 2), 'woodl', 'diag'); c.shape(thick(20, 5, 4, 19, 2), 'woodl', 'diag', 0.1); }],
  ['Offene Kiste', 'Mit Inhalt', (c) => { c.shape(rect(3, 10, 21, 21), 'wood', 'diag'); c.shape(rect(3, 10, 21, 12), 'woodl', 'vert'); c.shape(ell(8, 8, 3.4, 3), 'apple', 'orb'); c.shape(ell(15, 8, 3.4, 3), 'bread', 'orb'); c.line(5, 16, 19, 16, 'bark', 1); }],
  ['Fass', 'Holzfass mit Reifen', (c) => { c.shape(ell(12, 12, 9, 10), 'wood', 'orb'); c.shape(rect(3.2, 6, 20.8, 7.6), 'iron', 'vert'); c.shape(rect(3, 16, 21, 17.6), 'iron', 'vert'); c.shape(ell(12, 3.6, 6, 1.6), 'woodl', 'orb'); }],
  ['Kasten mit Gurt', 'Verschlossen', (c) => { c.shape(rect(2, 6, 22, 20), 'leather', 'diag'); c.shape(rect(2, 6, 22, 9), 'leatherd', 'vert'); c.shape(rect(10.4, 6, 13.6, 20), 'iron', 'vert'); c.shape(rect(10, 12, 14, 15), 'gold', 'diag'); }],
  ['Kistenstapel', 'Drei Kisten', (c) => { for (const [x, y] of [[1, 13], [12, 13], [6, 3]]) { c.shape(rect(x, y, x + 10, y + 8), 'wood', 'diag'); c.shape(rect(x, y + 3.2, x + 10, y + 4.6), 'woodl', 'vert'); } }],
  ['Pappkarton', 'Mit Klebeband', (c) => { c.shape(rect(3, 7, 21, 21), 'bread', 'diag'); c.shape(poly([[3, 7], [8, 3], [16, 3], [21, 7]]), 'sand', 'vert'); c.shape(rect(10.4, 3, 13.6, 21), 'brass', 'vert', 0.1); }],
  ['Weinfass', 'Liegendes Fass', (c) => { c.shape(ell(12, 12, 10, 7.4), 'wood', 'orb'); c.shape(rect(6, 5, 7.6, 19), 'iron', 'flat'); c.shape(rect(16.4, 5, 18, 19), 'iron', 'flat'); c.shape(ell(3.4, 12, 1.6, 5.6), 'woodl', 'orb'); c.shape(rect(11, 17, 13, 21), 'iron', 'diag'); }],
  ['Palette', 'Kiste auf Palette', (c) => { c.shape(rect(4, 3, 20, 16), 'wood', 'diag'); c.shape(rect(4, 8, 20, 9.4), 'woodl', 'vert'); c.shape(rect(1, 17, 23, 19), 'woodl', 'vert'); for (const x of [2, 11, 20]) c.shape(rect(x, 19, x + 2, 22), 'wood', 'diag'); }],
  ['Eisenkiste', 'Stahl mit Nieten', (c) => { c.shape(rect(2, 4, 22, 21), 'iron', 'diag'); c.shape(rect(4, 6, 20, 19), 'steel', 'vert', 0.1); for (const [x, y] of [[3, 5], [21, 5], [3, 20], [21, 20]]) c.px(x, y, 'face', 4); c.shape(rect(10, 11, 14, 14), 'iron', 'diag'); }],
  ['Schatzkiste', 'Mit Goldrand', (c) => { c.shape(rect(2, 10, 22, 21), 'wood', 'diag'); c.shape(both(ell(12, 10, 10, 7), rect(0, 3, 24, 10)), 'woodl', 'vert'); c.shape(rect(2, 10, 22, 12), 'gold', 'vert'); c.shape(rect(10, 10, 14, 16), 'gold', 'diag'); }],
];

const backpack = [
  ['Rucksack', 'Mit Klappe', (c) => { c.shape(ell(12, 14, 8, 8), 'leather', 'orb'); c.shape(rect(4, 14, 20, 20), 'leather', 'diag'); c.shape(both(ell(12, 8, 8, 6), rect(0, 0, 24, 12)), 'leatherd', 'vert', -0.1); c.shape(rect(10.4, 9, 13.6, 13), 'gold', 'diag'); c.shape(ell(12, 3, 3, 1.6), 'leatherd', 'orb'); }],
  ['Umhängetasche', 'Mit Riemen', (c) => { c.shape(rect(5, 11, 19, 21), 'leather', 'diag'); c.shape(poly([[5, 11], [19, 11], [17, 16], [7, 16]]), 'leatherd', 'vert'); c.shape(path([[7, 11], [4, 5], [10, 2], [17, 3]], 1.6), 'leatherd', 'flat'); c.shape(rect(10.4, 14, 13.6, 17), 'gold', 'diag'); }],
  ['Bündel am Stock', 'Wanderer', (c) => { c.shape(thick(3, 21, 20, 5, 1.6), 'wood', 'flat'); c.shape(ell(17, 7, 5, 5), 'red', 'orb'); c.shape(ell(17, 7, 1.4, 1.4), 'face', 'flat'); c.shape(rect(15, 10, 19, 12), 'leatherd', 'vert'); }],
  ['Beutel', 'Gürteltasche', (c) => { c.shape(ell(12, 15, 8, 6.6), 'leather', 'orb'); c.shape(rect(2, 4, 22, 7), 'leatherd', 'vert'); c.shape(poly([[7, 7], [17, 7], [15, 12], [9, 12]]), 'leatherd', 'diag'); c.shape(rect(10.6, 10, 13.4, 12.4), 'gold', 'diag'); }],
  ['Mit Schlafrolle', 'Rucksack, Rolle oben', (c) => { c.shape(ell(12, 6, 9, 3), 'blue', 'orb'); c.shape(ell(12, 15, 8, 7), 'leather', 'orb'); c.shape(rect(4, 15, 20, 21), 'leather', 'diag'); c.shape(rect(9, 14, 15, 19), 'leatherd', 'vert'); }],
  ['Korb', 'Tragekorb', (c) => { c.shape(poly([[3, 8], [21, 8], [18, 21], [6, 21]]), 'wood', 'diag'); c.shape(rect(3, 8, 21, 10), 'woodl', 'vert'); for (const y of [13, 17]) c.line(5, y, 19, y, 'bark', 1); c.shape(ring(12, 8, 7, 5.6), 'woodl', 'flat'); }],
  ['Lederschnalle', 'Große Tasche', (c) => { c.shape(rect(3, 6, 21, 21), 'leather', 'diag'); c.shape(poly([[3, 6], [21, 6], [21, 13], [12, 16], [3, 13]]), 'leatherd', 'vert'); c.shape(rect(10, 13, 14, 17), 'steel', 'diag'); c.shape(ell(12, 4, 4, 1.6), 'leatherd', 'orb'); }],
  ['Satteltasche', 'Zwei Seiten', (c) => { c.shape(rect(2, 9, 10, 21), 'leather', 'diag'); c.shape(rect(14, 9, 22, 21), 'leather', 'diag'); c.shape(rect(9, 7, 15, 11), 'leatherd', 'vert'); c.shape(rect(2, 9, 10, 13), 'leatherd', 'vert'); c.shape(rect(14, 9, 22, 13), 'leatherd', 'vert'); }],
  ['Kleiner Rucksack', 'Rund', (c) => { c.shape(ell(12, 13, 7, 8), 'green', 'orb'); c.shape(both(ell(12, 8, 7, 5), rect(0, 0, 24, 11)), 'moss', 'vert'); c.shape(rect(10.6, 10, 13.4, 14), 'gold', 'diag'); c.shape(ring(12, 3, 2.6, 1.2), 'moss', 'flat'); }],
  ['Seesack', 'Zugband', (c) => { c.shape(poly([[7, 4], [17, 4], [20, 21], [4, 21]]), 'blue', 'diag'); c.shape(rect(6, 4, 18, 6.4), 'navy', 'vert'); c.shape(rect(5, 10, 19, 11.4), 'navy', 'vert'); c.shape(ring(12, 2.4, 3, 1.6), 'navy', 'flat'); }],
];

const lock = [
  ['Vorhängeschloss', 'Gold', (c) => { c.shape(minus(ell(12, 8, 6, 7), ell(12, 9, 3.2, 4.4)), 'steel', 'orb'); c.shape(rect(4, 10, 20, 21), 'gold', 'diag'); c.shape(ell(12, 15, 1.8, 1.8), 'black', 'flat'); c.shape(rect(11.2, 15, 12.8, 19), 'black', 'flat'); }],
  ['Stahlschloss', 'Grau', (c) => { c.shape(minus(ell(12, 8, 6, 7), ell(12, 9, 3.2, 4.4)), 'steel', 'orb'); c.shape(rect(4, 10, 20, 21), 'iron', 'diag'); c.shape(ell(12, 15, 1.8, 1.8), 'black', 'flat'); c.shape(rect(11.2, 15, 12.8, 19), 'black', 'flat'); }],
  ['Schlüsselloch', 'Beschlag', (c) => { c.shape(poly([[7, 2], [17, 2], [17, 20], [12, 23], [7, 20]]), 'brass', 'diag'); c.shape(ell(12, 9, 2.6, 2.6), 'black', 'flat'); c.shape(poly([[10.6, 10], [13.4, 10], [14.2, 17], [9.8, 17]]), 'black', 'flat'); }],
  ['Schloss und Schlüssel', 'Mit Schlüssel', (c) => { c.shape(minus(ell(9, 7, 5, 5.6), ell(9, 8, 2.6, 3.4)), 'steel', 'orb'); c.shape(rect(3, 9, 15, 20), 'gold', 'diag'); c.shape(ell(9, 14, 1.4, 1.4), 'black', 'flat'); c.shape(thick(14, 21, 22, 11, 1.6), 'brass', 'flat'); c.shape(ring(22, 10, 2, 0.8), 'brass', 'orb'); }],
  ['Kettenschloss', 'Mit Kette', (c) => { c.shape(rect(7, 9, 17, 19), 'iron', 'diag'); c.shape(minus(ell(12, 9, 4, 5), ell(12, 10, 2, 3)), 'steel', 'orb'); c.shape(ring(3, 5, 3, 1.5), 'steel', 'orb'); c.shape(ring(21, 5, 3, 1.5), 'steel', 'orb'); c.shape(ring(3, 19, 3, 1.5), 'steel', 'orb'); c.shape(ring(21, 19, 3, 1.5), 'steel', 'orb'); }],
  ['Rundschloss', 'Rund mit Dreh', (c) => { c.shape(ell(12, 12, 10, 10), 'iron', 'orb'); c.shape(ell(12, 12, 7, 7), 'steel', 'orb'); c.shape(ell(12, 11, 2, 2), 'black', 'flat'); c.shape(rect(11.2, 12, 12.8, 17), 'black', 'flat'); }],
  ['Offenes Schloss', 'Bügel offen', (c) => { c.shape(path([[16, 10], [16, 5], [13, 2], [10, 3]], 2.2), 'steel', 'diag'); c.shape(rect(4, 10, 20, 21), 'gold', 'diag'); c.shape(ell(12, 15, 1.8, 1.8), 'black', 'flat'); c.shape(rect(11.2, 15, 12.8, 19), 'black', 'flat'); }],
  ['Schildschloss', 'Wappenform', (c) => { c.shape(poly([[3, 3], [21, 3], [21, 13], [12, 22], [3, 13]]), 'blue', 'diag'); c.shape(rect(8, 10, 16, 17), 'gold', 'diag'); c.shape(minus(ell(12, 10, 3.6, 4), ell(12, 10.4, 1.8, 2.4)), 'steel', 'orb'); }],
  ['Eisenschloss', 'Groß und schwer', (c) => { c.shape(minus(ell(12, 8, 7, 8), ell(12, 9, 3.8, 5)), 'iron', 'orb'); c.shape(rect(3, 11, 21, 22), 'iron', 'diag'); c.shape(rect(5, 13, 19, 20), 'steel', 'vert', 0.15); c.shape(ell(12, 16, 2, 2), 'black', 'flat'); }],
  ['Zahlenschloss', 'Mit Wählscheibe', (c) => { c.shape(minus(ell(12, 7, 5.6, 6.6), ell(12, 8, 3, 4.2)), 'steel', 'orb'); c.shape(rect(3, 10, 21, 22), 'brass', 'diag'); c.shape(ell(12, 16, 4.6, 4.6), 'iron', 'orb'); c.shape(ell(12, 16, 1.4, 1.4), 'face', 'flat'); for (const [x, y] of [[12, 12.4], [12, 19.6], [8.4, 16], [15.6, 16]]) c.px(x, y, 'face', 4); }],
];

const cart = [
  ['Handkarren', 'Mit Last', (c) => { c.shape(poly([[3, 10], [19, 10], [17, 17], [5, 17]]), 'wood', 'diag'); c.shape(ell(8, 8, 3.4, 3), 'bread', 'orb'); c.shape(ell(14, 7, 3.6, 3.4), 'moss', 'orb'); c.shape(ell(10, 20, 3.4, 3.4), 'iron', 'orb'); c.shape(ell(10, 20, 1.2, 1.2), 'steel', 'flat'); c.shape(thick(18, 12, 23, 6, 1.6), 'wood', 'flat'); }],
  ['Planwagen', 'Mit Abdeckung', (c) => { c.shape(rect(3, 13, 21, 18), 'wood', 'diag'); c.shape(both(ell(12, 13, 9, 9), rect(0, 3, 24, 13)), 'face', 'vert'); c.shape(ell(7, 20, 3.2, 3.2), 'wood', 'orb'); c.shape(ell(17, 20, 3.2, 3.2), 'wood', 'orb'); c.shape(ell(7, 20, 1, 1), 'iron', 'flat'); c.shape(ell(17, 20, 1, 1), 'iron', 'flat'); }],
  ['Schubkarre', 'Einrad', (c) => { c.shape(poly([[3, 7], [16, 7], [13, 15], [6, 15]]), 'iron', 'diag'); c.shape(ell(9, 6, 5, 2.4), 'sand', 'orb'); c.shape(ell(15, 18, 3.4, 3.4), 'wood', 'orb'); c.shape(thick(16, 10, 23, 7, 1.6), 'wood', 'flat'); c.shape(thick(7, 15, 4, 22, 1.6), 'wood', 'flat'); }],
  ['Warenkarren', 'Mit Kisten', (c) => { c.shape(rect(2, 14, 22, 17), 'wood', 'vert'); c.shape(rect(4, 7, 11, 14), 'woodl', 'diag'); c.shape(rect(12, 9, 19, 14), 'woodl', 'diag', 0.1); c.shape(ell(7, 19.5, 3, 3), 'iron', 'orb'); c.shape(ell(17, 19.5, 3, 3), 'iron', 'orb'); }],
  ['Lore', 'Mit Erz', (c) => { c.shape(poly([[2, 10], [22, 10], [19, 18], [5, 18]]), 'iron', 'diag'); c.shape(ell(8, 8, 3.4, 2.6), 'silver', 'orb'); c.shape(ell(14, 7, 3.6, 3), 'goldl', 'orb'); c.shape(ell(7, 20, 2.4, 2.4), 'steel', 'orb'); c.shape(ell(17, 20, 2.4, 2.4), 'steel', 'orb'); c.shape(rect(1, 21.4, 23, 22.6), 'bark', 'vert'); }],
  ['Frontansicht', 'Karren von vorn', (c) => { c.shape(rect(5, 6, 19, 16), 'wood', 'diag'); c.shape(rect(5, 9, 19, 10.4), 'woodl', 'vert'); c.shape(ell(3, 18, 2, 3.6), 'iron', 'orb'); c.shape(ell(21, 18, 2, 3.6), 'iron', 'orb'); c.shape(rect(8, 16, 16, 18), 'bark', 'vert'); }],
  ['Lastwagen', 'Kleiner Truck', (c) => { c.shape(rect(2, 6, 15, 17), 'blue', 'diag'); c.shape(poly([[15, 10], [20, 10], [22, 14], [22, 17], [15, 17]]), 'red', 'diag'); c.shape(rect(17, 11, 20, 14), 'cyan', 'flat'); c.shape(ell(6, 18, 3, 3), 'iron', 'orb'); c.shape(ell(18, 18, 3, 3), 'iron', 'orb'); }],
  ['Lokomotive', 'Kleine Dampflok', (c) => { c.shape(rect(2, 9, 14, 17), 'iron', 'diag'); c.shape(rect(14, 6, 22, 17), 'red', 'diag'); c.shape(rect(3, 4, 7, 9), 'iron', 'diag'); smoke(c, 5, 3); for (const x of [6, 12, 18]) c.shape(ell(x, 19, 2.6, 2.6), 'steel', 'orb'); }],
  ['Einkaufswagen', 'Gitterwagen', (c) => { c.shape(poly([[3, 6], [21, 6], [18, 15], [6, 15]]), 'steel', 'diag'); for (const x of [8, 12, 16]) c.line(x, 7, x - 1 + (x - 12) * 0.2, 14, 'iron', 1); c.shape(ell(7, 19, 2.2, 2.2), 'iron', 'orb'); c.shape(ell(17, 19, 2.2, 2.2), 'iron', 'orb'); c.shape(path([[3, 6], [1, 3]], 1.6), 'iron', 'flat'); }],
  ['Ochsenkarren', 'Zweirädrig', (c) => { c.shape(rect(4, 9, 18, 15), 'wood', 'diag'); c.shape(rect(4, 9, 18, 10.4), 'woodl', 'vert'); c.shape(ring(11, 17, 5, 3.4), 'wood', 'orb'); c.shape(rect(10.4, 12, 11.6, 22), 'wood', 'flat'); c.shape(thick(18, 12, 23, 14, 1.6), 'wood', 'flat'); }],
];

const bed = [
  ['Bett', 'Seitenansicht', (c) => { c.shape(rect(2, 13, 22, 18), 'blue', 'vert'); c.shape(rect(2, 9, 8, 14), 'face', 'diag'); c.shape(rect(1, 8, 3, 21), 'wood', 'diag'); c.shape(rect(21, 12, 23, 21), 'wood', 'diag'); }],
  ['Himmelbett', 'Mit Vorhängen', (c) => { c.shape(rect(2, 14, 22, 19), 'red', 'vert'); c.shape(rect(2, 11, 8, 15), 'face', 'diag'); for (const x of [2, 20]) c.shape(rect(x, 2, x + 1.6, 21), 'wood', 'diag'); c.shape(rect(2, 2, 22, 4.4), 'red', 'vert'); c.shape(poly([[3.6, 4], [8, 4], [3.6, 14]]), 'red', 'diag'); }],
  ['Hängematte', 'Zwischen Bäumen', (c) => { c.shape(rect(2, 3, 4, 22), 'bark', 'diag'); c.shape(rect(20, 3, 22, 22), 'bark', 'diag'); c.shape(path([[4, 8], [8, 14], [16, 14], [20, 8]], 3.6), 'red', 'vert'); c.shape(ell(12, 13, 6, 2), 'face', 'flat', 0.1); }],
  ['Etagenbett', 'Zwei Ebenen', (c) => { for (const y of [4, 13]) { c.shape(rect(3, y, 21, y + 4), 'blue', 'vert'); c.shape(rect(3, y - 1.4, 8, y + 1), 'face', 'diag'); } for (const x of [2, 21]) c.shape(rect(x, 2, x + 1.4, 21), 'wood', 'diag'); }],
  ['Schlafrolle', 'Aufgerollt', (c) => { c.shape(rect(3, 8, 21, 17), 'green', 'diag'); c.shape(ell(3, 12.5, 2.6, 4.6), 'moss', 'orb'); c.shape(ell(3, 12.5, 1, 2), 'iron', 'flat'); c.shape(rect(6, 8, 7.4, 17), 'leatherd', 'flat'); c.shape(rect(15, 8, 16.4, 17), 'leatherd', 'flat'); }],
  ['Kissen', 'Nur das Kissen', (c) => { c.shape(poly([[3, 7], [21, 7], [22, 15], [2, 15]]), 'face', 'diag'); c.shape(ell(12, 11, 7, 2.6), 'ice', 'orb', -0.1); c.shape(ell(3, 11, 1.6, 4), 'face', 'orb'); c.shape(ell(21, 11, 1.6, 4), 'face', 'orb'); }],
  ['Strohlager', 'Stroh auf Boden', (c) => { c.shape(poly([[2, 18], [4, 12], [20, 12], [22, 18]]), 'bread', 'vert'); for (const [a, b, d, e] of [[5, 13, 8, 17], [10, 13, 9, 18], [14, 13, 17, 17], [18, 14, 20, 17]]) c.line(a, b, d, e, 'sand', 4); c.shape(ell(12, 20, 10, 1.8), 'sand', 'vert'); }],
  ['Pritsche', 'Einfach mit Decke', (c) => { c.shape(rect(2, 12, 22, 16), 'brown', 'vert'); c.shape(rect(6, 11, 21, 14), 'green', 'vert'); c.shape(rect(2, 10, 7, 13), 'face', 'diag'); c.shape(rect(3, 16, 5, 21), 'wood', 'diag'); c.shape(rect(19, 16, 21, 21), 'wood', 'diag'); }],
  ['Sofa', 'Gepolstert', (c) => { c.shape(rect(3, 6, 21, 14), 'purple', 'diag'); c.shape(rect(1, 11, 5, 19), 'purple', 'diag', 0.2); c.shape(rect(19, 11, 23, 19), 'purple', 'diag', 0.2); c.shape(rect(5, 13, 19, 18), 'purple', 'vert', -0.1); c.shape(rect(3, 19, 5, 21), 'wood', 'flat'); c.shape(rect(19, 19, 21, 21), 'wood', 'flat'); }],
  ['Bett mit Mond', 'Gute Nacht', (c) => { c.shape(rect(2, 14, 22, 19), 'blue', 'vert'); c.shape(rect(2, 11, 8, 15), 'face', 'diag'); c.shape(rect(1, 10, 3, 21), 'wood', 'diag'); c.shape(rect(21, 13, 23, 21), 'wood', 'diag'); c.shape(minus(ell(16, 6, 4.4, 4.4), ell(18.4, 5, 3.8, 3.8)), 'bolt', 'orb'); sparkle(c, 8, 5, 2.4); }],
];

const CONCEPTS = [
  { cat: 'Dinge', key: 'map', name: 'Karte', designs: map },
  { cat: 'Dinge', key: 'globe', name: 'Globus', designs: globe },
  { cat: 'Dinge', key: 'compass', name: 'Kompass', designs: compass },
  { cat: 'Dinge', key: 'sun', name: 'Sonne', designs: sun },
  { cat: 'Dinge', key: 'moon', name: 'Mond', designs: moon },
  { cat: 'Dinge', key: 'wave', name: 'Welle', designs: wave },
  { cat: 'Dinge', key: 'candle', name: 'Kerze', designs: candle },
  { cat: 'Dinge', key: 'crate', name: 'Kiste', designs: crate },
  { cat: 'Dinge', key: 'backpack', name: 'Rucksack', designs: backpack },
  { cat: 'Dinge', key: 'lock', name: 'Schloss', designs: lock },
  { cat: 'Dinge', key: 'cart', name: 'Karren', designs: cart },
  { cat: 'Dinge', key: 'bed', name: 'Bett', designs: bed },
];
module.exports = { CONCEPTS };
