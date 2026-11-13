// Batch 4: buildings and places.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const smoke = (c, x, y) => { c.shape(ell(x, y, 2.2, 2), 'ice', 'orb'); c.shape(ell(x + 2, y - 3, 2.6, 2.2), 'ice', 'orb'); };
const door = (c, x0, y0, x1, y1, r = 'door') => { c.shape(poly([[x0, y1], [x0, y0 + 1.5], [(x0 + x1) / 2, y0], [x1, y0 + 1.5], [x1, y1]]), r, 'vert'); };
const merlons = (c, x0, x1, y, r) => { for (let x = x0; x < x1; x += 4) c.shape(rect(x, y - 2.4, x + 2, y), r, 'diag'); };

const house = [
  ['Häuschen', 'Schornstein, Tür', (c) => {
    c.shape(rect(16, 3, 18, 9), 'iron', 'diag'); c.shape(rect(5, 11, 19, 20), 'wall', 'diag'); c.shape(poly([[2, 12], [12, 3], [22, 12]]), 'roof', 'vert'); c.shape(rect(10, 14, 13, 20), 'door', 'vert'); c.px(12, 17, 'gold', 4); c.shape(rect(6.5, 13.5, 9, 16), 'bolt', 'flat'); c.shape(rect(15, 13.5, 17.5, 16), 'bolt', 'flat');
  }],
  ['Fachwerk', 'Balken und rotes Dach', (c) => {
    c.shape(rect(4, 11, 20, 20), 'wall', 'diag'); for (const x of [4, 11.5, 19]) c.shape(rect(x - 0.6, 11, x + 0.8, 20), 'bark', 'diag'); c.shape(rect(4, 15, 20, 16), 'bark', 'diag'); c.line(5, 12, 10, 15, 'bark', 1); c.line(19, 12, 14, 15, 'bark', 1);
    c.shape(poly([[1, 12], [12, 2], [23, 12]]), 'roof', 'vert'); c.shape(rect(10, 16, 13, 20), 'door', 'vert');
  }],
  ['Zweistöckig', 'Hohes Haus', (c) => {
    c.shape(rect(6, 8, 18, 21), 'wall', 'diag'); c.shape(poly([[4, 9], [12, 2], [20, 9]]), 'roof', 'vert'); c.shape(rect(10, 16, 14, 21), 'door', 'vert'); for (const [x, y] of [[8, 10], [14, 10], [8, 14.5], [15, 14.5]]) c.shape(rect(x, y, x + 2.4, y + 2.6), 'bolt', 'flat');
  }],
  ['Giebelhaus', 'Rundes Fenster', (c) => {
    c.shape(rect(4, 11, 20, 21), 'wall', 'diag'); c.shape(poly([[3, 11], [12, 2], [21, 11]]), 'wall', 'vert', 0.1); c.shape(path([[3, 11], [12, 2], [21, 11]], 2), 'roof', 'diag'); c.shape(ell(12, 8, 2.6, 2.6), 'bolt', 'orb'); c.shape(rect(9.6, 14, 14.4, 21), 'door', 'vert');
  }],
  ['Isometrisch', 'Würfel mit Dach', (c) => {
    c.shape(poly([[3, 10], [12, 14], [12, 22], [3, 18]]), 'wall', 'diag', 0.05); c.shape(poly([[12, 14], [21, 10], [21, 18], [12, 22]]), 'wall', 'diag', 0.3);
    c.shape(poly([[1, 10], [12, 3], [23, 10], [12, 15]]), 'roof', 'vert'); c.shape(rect(14, 16, 18, 19), 'door', 'flat');
  }],
  ['Strohhütte', 'Reetdach', (c) => {
    c.shape(rect(5, 13, 19, 21), 'clay', 'diag'); c.shape(poly([[1, 14], [12, 2], [23, 14]]), 'sand', 'vert'); for (const y of [8, 11]) c.line(5, y, 19, y, 'bread', 1); c.shape(rect(10, 15, 14, 21), 'door', 'vert');
  }],
  ['Steinhaus', 'Grau mit blauem Dach', (c) => {
    c.shape(rect(4, 11, 20, 21), 'stone', 'diag'); for (const [x, y] of [[7, 14], [14, 17], [16, 13]]) c.line(x, y, x + 3, y, 'stone2', 4); c.shape(poly([[2, 12], [12, 3], [22, 12]]), 'blue', 'vert'); c.shape(rect(10, 15, 14, 21), 'wood', 'vert');
  }],
  ['Mit Zaun', 'Haus hinter Lattenzaun', (c) => {
    c.shape(rect(6, 9, 18, 18), 'wall', 'diag'); c.shape(poly([[4, 10], [12, 3], [20, 10]]), 'roof', 'vert'); c.shape(rect(10.5, 12, 13.5, 18), 'door', 'vert');
    c.shape(rect(1, 18, 23, 19.4), 'woodl', 'vert'); for (let x = 2; x < 23; x += 3) c.shape(rect(x, 15, x + 1.6, 21), 'woodl', 'diag');
  }],
  ['Im Medaillon', 'Haus in Kreis', (c) => { c.shape(ell(12, 12, 10.6, 10.6), 'blue', 'orb'); c.shape(rect(7, 12, 17, 18), 'wall', 'diag'); c.shape(poly([[5, 13], [12, 6], [19, 13]]), 'roof', 'vert'); c.shape(rect(11, 14, 13, 18), 'door', 'flat'); }],
  ['Mit Rauch', 'Rauch und Baum', (c) => {
    c.shape(rect(3, 12, 14, 20), 'wall', 'diag'); c.shape(poly([[1, 13], [8.5, 5], [16, 13]]), 'roof', 'vert'); c.shape(rect(12, 4, 14, 9), 'iron', 'diag'); smoke(c, 14, 3);
    c.shape(rect(18, 15, 20, 21), 'bark', 'diag'); c.shape(ell(19, 13, 4, 4.4), 'moss', 'orb'); c.shape(rect(6, 15, 9, 20), 'door', 'vert');
  }],
];

const castle = [
  ['Burg mit Türmen', 'Zwei Türme, Tor', (c) => {
    c.shape(rect(2, 8, 8, 21), 'stone', 'diag'); c.shape(rect(16, 8, 22, 21), 'stone', 'diag'); c.shape(rect(8, 11, 16, 21), 'stone2', 'diag'); merlons(c, 2, 8, 8, 'stone'); merlons(c, 16, 22, 8, 'stone'); merlons(c, 8, 16, 11, 'stone2');
    door(c, 10.5, 15, 13.5, 21); c.shape(rect(4, 12, 6, 15), 'black', 'flat'); c.shape(rect(18, 12, 20, 15), 'black', 'flat');
  }],
  ['Turm', 'Hoher Turm mit Flagge', (c) => {
    c.shape(rect(7, 6, 17, 21), 'stone', 'diag'); c.shape(rect(6, 6, 18, 8), 'stone2', 'vert'); merlons(c, 6, 18, 6, 'stone2'); c.shape(rect(11, 0, 12, 4), 'wood', 'flat'); c.shape(poly([[12, 0], [17, 1.6], [12, 3]]), 'red', 'flat'); door(c, 10, 16, 14, 21); c.shape(rect(11, 10, 13, 13), 'black', 'flat');
  }],
  ['Burgtor', 'Tor mit Fallgitter', (c) => {
    c.shape(rect(2, 7, 22, 21), 'stone', 'diag'); merlons(c, 2, 22, 7, 'stone2'); c.shape(poly([[8, 21], [8, 13], [12, 10], [16, 13], [16, 21]]), 'black', 'flat'); for (const x of [10, 12, 14]) c.line(x, 11, x, 20, 'iron', 4); c.line(9, 15, 15, 15, 'iron', 4);
  }],
  ['Auf dem Hügel', 'Burg auf Anhöhe', (c) => {
    c.shape(ell(12, 24, 14, 8), 'moss', 'orb'); c.shape(rect(6, 8, 18, 17), 'stone', 'diag'); merlons(c, 6, 18, 8, 'stone'); c.shape(rect(9, 3, 15, 8), 'stone2', 'diag'); merlons(c, 9, 15, 3, 'stone2'); door(c, 10.5, 12, 13.5, 17);
  }],
  ['Bergfried', 'Keep mit Banner', (c) => {
    c.shape(rect(3, 10, 21, 21), 'stone', 'diag'); c.shape(rect(8, 3, 16, 10), 'stone2', 'diag'); merlons(c, 3, 21, 10, 'stone'); merlons(c, 8, 16, 3, 'stone2'); c.shape(rect(11, 12, 13, 16), 'black', 'flat'); door(c, 10, 17, 14, 21); c.shape(poly([[10, 5], [14, 5], [14, 9], [12, 8], [10, 9]]), 'red', 'flat');
  }],
  ['Rundturm', 'Zylinder mit Spitzdach', (c) => {
    c.shape(rect(6, 9, 18, 21), 'stone', 'diag'); c.shape(ell(12, 21, 6, 1.4), 'stone', 'vert'); c.shape(poly([[4, 10], [12, 1], [20, 10]]), 'blue', 'vert'); c.shape(rect(11, 12, 13, 16), 'black', 'flat'); door(c, 10, 17, 14, 21);
  }],
  ['Wachhaus', 'Torhaus', (c) => {
    c.shape(rect(2, 9, 8, 21), 'stone', 'diag'); c.shape(rect(16, 9, 22, 21), 'stone', 'diag'); c.shape(poly([[1, 9], [5, 3], [9, 9]]), 'red', 'vert'); c.shape(poly([[15, 9], [19, 3], [23, 9]]), 'red', 'vert'); c.shape(rect(8, 12, 16, 21), 'stone2', 'diag'); door(c, 9.5, 14, 14.5, 21);
  }],
  ['Isometrisch', 'Würfelburg', (c) => {
    c.shape(poly([[2, 9], [12, 14], [12, 23], [2, 18]]), 'stone', 'diag'); c.shape(poly([[12, 14], [22, 9], [22, 18], [12, 23]]), 'stone', 'diag', 0.28); c.shape(poly([[2, 9], [12, 4], [22, 9], [12, 14]]), 'stone2', 'vert', -0.1); c.shape(rect(10, 1, 14, 6), 'stone2', 'diag'); c.shape(poly([[14, 17], [19, 14.5], [19, 18], [14, 20.5]]), 'black', 'flat');
  }],
  ['Palast', 'Kuppeln', (c) => {
    c.shape(rect(3, 12, 21, 21), 'face', 'diag'); c.shape(both(ell(12, 12, 6, 7), rect(0, 0, 24, 12)), 'gold', 'orb'); c.shape(both(ell(5, 12, 3, 4), rect(0, 0, 24, 12)), 'gold', 'orb'); c.shape(both(ell(19, 12, 3, 4), rect(0, 0, 24, 12)), 'gold', 'orb'); c.shape(rect(11.4, 1, 12.6, 5), 'gold', 'flat'); door(c, 10.5, 15, 13.5, 21, 'blue');
  }],
  ['Mauer', 'Zinnenmauer', (c) => {
    c.shape(rect(1, 10, 23, 21), 'stone', 'diag'); merlons(c, 1, 23, 10, 'stone2'); for (const y of [14, 17.5]) c.line(1, y, 22, y, 'stone2', 1); for (const [x, y0] of [[6, 10], [13, 10], [19, 10], [9, 14], [16, 14], [4, 14], [12, 17.5], [19, 17.5]]) c.line(x, y0, x, y0 + 3, 'stone2', 1);
  }],
];

const tent = [
  ['Zelt', 'Dreieck mit Eingang', (c) => { c.shape(poly([[1, 21], [12, 3], [23, 21]]), 'red', 'diag'); c.shape(poly([[9, 21], [12, 12], [15, 21]]), 'black', 'flat'); c.shape(rect(11.4, 1, 12.6, 5), 'wood', 'flat'); }],
  ['Zirkuszelt', 'Gestreift', (c) => { c.shape(poly([[2, 21], [4, 12], [12, 4], [20, 12], [22, 21]]), 'face', 'diag'); c.shape(poly([[4, 12], [8, 8], [8, 21], [4, 21]]), 'red', 'diag'); c.shape(poly([[12, 4], [16, 8], [16, 21], [12, 21]]), 'red', 'diag'); c.shape(poly([[20, 12], [22, 21], [20, 21]]), 'red', 'diag'); c.shape(poly([[10, 21], [12, 14], [14, 21]]), 'black', 'flat'); c.shape(poly([[12, 4], [12, 0], [16, 1.6], [12, 3]]), 'bolt', 'flat'); }],
  ['Lagerfeuer', 'Zelt mit Feuer', (c) => { c.shape(poly([[0, 21], [8, 5], [16, 21]]), 'blue', 'diag'); c.shape(poly([[6, 21], [8, 13], [10, 21]]), 'black', 'flat'); c.shape(poly([[19, 12], [22, 17], [21, 21], [17, 21], [16, 17]]), 'orange', 'vert'); c.shape(ell(19, 19, 1.6, 2), 'goldl', 'orb'); }],
  ['Jurte', 'Rund mit Kegeldach', (c) => { c.shape(rect(4, 12, 20, 21), 'face', 'diag'); c.shape(poly([[2, 13], [12, 3], [22, 13]]), 'leather', 'vert'); door(c, 10, 15, 14, 21, 'red'); c.shape(rect(4, 18, 20, 19), 'leather', 'flat'); }],
  ['Tipi', 'Spitzzelt mit Stangen', (c) => { c.shape(poly([[3, 22], [11, 4], [13, 4], [21, 22]]), 'skin', 'diag'); c.shape(path([[12, 3], [9, 0]], 1.2), 'wood', 'flat'); c.shape(path([[12, 3], [15, 0]], 1.2), 'wood', 'flat'); c.shape(poly([[10, 22], [12, 13], [14, 22]]), 'black', 'flat'); c.line(7, 15, 17, 15, 'red', 2); }],
  ['Pavillon', 'Mit Wimpel und Vorhang', (c) => { c.shape(poly([[2, 11], [12, 3], [22, 11]]), 'blue', 'vert'); c.shape(rect(3, 11, 21, 21), 'face', 'diag'); for (const x of [3, 21]) c.shape(rect(x - 1, 11, x + 1, 21), 'wood', 'diag'); c.shape(poly([[8, 21], [10, 14], [14, 14], [16, 21]]), 'blue', 'diag'); c.shape(poly([[12, 3], [12, 0], [16, 1.4], [12, 2.6]]), 'red', 'flat'); }],
  ['Mit Fahne', 'Zelt mit Wimpel', (c) => { c.shape(poly([[1, 22], [12, 6], [23, 22]]), 'orange', 'diag'); c.shape(poly([[9, 22], [12, 14], [15, 22]]), 'black', 'flat'); c.shape(rect(11.4, 0, 12.6, 7), 'wood', 'flat'); c.shape(poly([[12.6, 0], [19, 2], [12.6, 4]]), 'red', 'flat'); }],
  ['Unterstand', 'Schräges Dach', (c) => { c.shape(poly([[2, 8], [22, 4], [22, 8], [2, 12]]), 'leather', 'vert'); c.shape(rect(3, 11, 5, 21), 'wood', 'diag'); c.shape(rect(19, 7, 21, 21), 'wood', 'diag'); c.shape(rect(1, 20, 23, 21.6), 'sand', 'vert'); }],
  ['Kuppelzelt', 'Rund mit Eingang', (c) => { c.shape(both(ell(12, 21, 11, 16), rect(0, 0, 24, 21.5)), 'green', 'orb'); c.shape(poly([[9, 21], [10, 14], [14, 14], [15, 21]]), 'black', 'flat'); c.line(12, 6, 12, 14, 'leaf', 1); }],
  ['Zwei Zelte', 'Klein und groß', (c) => { c.shape(poly([[0, 21], [7, 8], [14, 21]]), 'blue', 'diag'); c.shape(poly([[10, 21], [17, 4], [24, 21]]), 'red', 'diag'); c.shape(poly([[15, 21], [17, 13], [19, 21]]), 'black', 'flat'); c.shape(poly([[5.4, 21], [7, 15], [8.6, 21]]), 'black', 'flat'); }],
];

const factory = [
  ['Sägedach', 'Fabrik mit Schornstein', (c) => { c.shape(rect(2, 12, 22, 21), 'roof', 'diag'); for (const x of [2, 8, 14]) c.shape(poly([[x, 12], [x, 7], [x + 6, 12]]), 'iron', 'diag'); c.shape(rect(18, 3, 21, 12), 'iron', 'diag'); smoke(c, 19, 2); for (const x of [5, 11, 16]) c.shape(rect(x, 15, x + 2.4, 18), 'bolt', 'flat'); }],
  ['Backstein', 'Hoher Schlot', (c) => { c.shape(rect(3, 11, 15, 21), 'clay', 'diag'); c.shape(rect(16, 2, 20, 21), 'clay', 'diag'); c.shape(rect(15.4, 1, 20.6, 3), 'iron', 'vert'); smoke(c, 18, 0.5); c.shape(rect(6, 14, 12, 21), 'black', 'flat'); }],
  ['Zahnrad-Halle', 'Gebäude mit Zahnrad', (c) => { c.shape(rect(2, 11, 22, 21), 'iron', 'diag'); c.shape(minus(ell(12, 8, 6, 6), ell(12, 8, 2.4, 2.4)), 'steel', 'orb'); for (let a = 0; a < 8; a++) c.shape(ell(12 + 7 * Math.cos(a * 0.785), 8 + 7 * Math.sin(a * 0.785), 1.6, 1.6), 'steel', 'orb'); }],
  ['Wassermühle', 'Mühle mit Rad', (c) => { c.shape(rect(3, 8, 14, 21), 'wall', 'diag'); c.shape(poly([[2, 9], [8.5, 2], [15, 9]]), 'roof', 'vert'); c.shape(minus(ell(17, 15, 6, 6), ell(17, 15, 3.2, 3.2)), 'wood', 'orb'); c.shape(rect(16.2, 9, 17.8, 21), 'wood', 'flat'); c.shape(rect(10, 15, 13, 21), 'black', 'flat'); c.shape(rect(1, 20, 23, 22), 'water', 'vert'); }],
  ['Schmiede', 'Mit Amboss und Glut', (c) => { c.shape(rect(3, 10, 21, 21), 'stone', 'diag'); c.shape(poly([[2, 11], [12, 4], [22, 11]]), 'iron', 'vert'); c.shape(rect(16, 1, 19, 8), 'stone2', 'diag'); c.shape(poly([[6, 21], [6, 17], [11, 17], [14, 15], [17, 15], [17, 17], [14, 18], [14, 21]]), 'black', 'diag'); c.shape(ell(8, 14, 2, 1.4), 'orange', 'orb'); }],
  ['Schlot', 'Nur der Schornstein', (c) => { c.shape(poly([[8, 21], [9, 6], [15, 6], [16, 21]]), 'clay', 'diag'); c.shape(rect(7.4, 4, 16.6, 6.4), 'iron', 'vert'); c.line(10, 12, 15, 12, 'iron', 1); c.line(9, 17, 15, 17, 'iron', 1); smoke(c, 12, 2); }],
  ['Zahnrad', 'Großes Zahnrad', (c) => { c.shape(ell(12, 12, 7.6, 7.6), 'steel', 'orb'); for (let a = 0; a < 8; a++) { const t = a * 0.785; c.shape(path([[12 + 6 * Math.cos(t), 12 + 6 * Math.sin(t)], [12 + 10 * Math.cos(t), 12 + 10 * Math.sin(t)]], 3.4), 'steel', 'orb'); } c.shape(ell(12, 12, 3, 3), 'iron', 'flat', 0.2); }],
  ['Kran', 'Baukran', (c) => { c.shape(rect(5, 6, 8, 21), 'bolt', 'diag'); c.shape(rect(2, 4, 22, 6.4), 'bolt', 'vert'); c.line(18, 6, 18, 14, 'iron', 2); c.shape(rect(16, 14, 20, 17), 'iron', 'diag'); c.shape(rect(3, 19, 10, 21), 'iron', 'vert'); c.line(5, 7, 8, 12, 'iron', 1); c.line(8, 7, 5, 12, 'iron', 1); }],
  ['Lagerhalle', 'Flache Halle', (c) => { c.shape(rect(2, 9, 22, 21), 'steel', 'diag'); c.shape(poly([[1, 10], [12, 3], [23, 10]]), 'iron', 'vert'); c.shape(rect(6, 13, 18, 21), 'iron', 'vert', 0.1); for (const x of [10, 14]) c.line(x, 13, x, 21, 'steel', 4); }],
  ['Hochofen', 'Ofen mit Flamme', (c) => { c.shape(poly([[5, 21], [7, 6], [17, 6], [19, 21]]), 'iron', 'diag'); c.shape(rect(9, 2, 15, 6), 'iron', 'vert'); c.shape(both(ell(12, 17, 4.6, 5), rect(0, 12, 24, 24)), 'orange', 'orb'); c.shape(ell(12, 18, 2.2, 2.6), 'goldl', 'orb'); c.shape(rect(4, 20, 20, 22), 'stone', 'vert'); }],
];

const bank = [
  ['Säulenhaus', 'Tempel mit Münze', (c) => { c.shape(poly([[1, 9], [12, 2], [23, 9]]), 'face', 'vert'); c.shape(rect(2, 9, 22, 10.6), 'face', 'diag'); for (const x of [4, 9, 14, 19]) c.shape(rect(x, 11, x + 2, 19), 'face', 'diag'); c.shape(rect(1, 19, 23, 21.4), 'face', 'vert'); c.shape(ell(12, 6.4, 1.8, 1.8), 'gold', 'orb'); }],
  ['Tresortür', 'Runde Tresortür', (c) => { c.shape(rect(3, 3, 21, 21), 'iron', 'diag'); c.shape(ell(12, 12, 7, 7), 'steel', 'orb'); c.shape(ring(12, 12, 4, 2.6), 'iron', 'flat'); c.shape(ell(12, 12, 1.4, 1.4), 'gold', 'orb'); for (const a of [0, 1.57, 3.14, 4.71]) c.px(12 + 3.3 * Math.cos(a), 12 + 3.3 * Math.sin(a), 'face', 4); c.shape(rect(21, 6, 22.6, 9), 'iron', 'diag'); }],
  ['Truhe', 'Geschlossen mit Schloss', (c) => { c.shape(rect(3, 11, 21, 21), 'wood', 'diag'); c.shape(both(ell(12, 11, 9, 7), rect(0, 3, 24, 11)), 'woodl', 'vert'); c.shape(rect(3, 14, 21, 15.4), 'iron', 'vert'); c.shape(rect(10, 12, 14, 17), 'gold', 'diag'); c.px(12, 14, 'black', 1); }],
  ['Kuppelbank', 'Gebäude mit Kuppel', (c) => { c.shape(rect(3, 12, 21, 21), 'face', 'diag'); c.shape(both(ell(12, 12, 7, 8), rect(0, 0, 24, 12)), 'blue', 'orb'); c.shape(rect(11.4, 1, 12.6, 5), 'gold', 'flat'); for (const x of [5, 9, 14, 18]) c.shape(rect(x, 13, x + 1.6, 19), 'iron', 'diag'); }],
  ['Münzsäulen', 'Säulen aus Münzen', (c) => { for (const [x, h] of [[3, 8], [9, 14], [15, 11]]) for (let i = 0; i < Math.floor(h / 2.6); i++) { const y = 20 - i * 2.6; c.shape(rect(x, y - 1, x + 6, y + 1.6), 'gold', 'vert'); c.shape(ell(x + 3, y - 1, 3, 1.3), 'goldl', 'orb'); } }],
  ['Geldschrank', 'Schrank mit Griff', (c) => { c.shape(rect(4, 3, 20, 21), 'iron', 'diag'); c.shape(rect(6, 5, 18, 19), 'steel', 'vert', 0.1); c.shape(ell(12, 12, 3, 3), 'gold', 'orb'); c.shape(rect(11.4, 12, 12.6, 16), 'black', 'flat'); c.shape(rect(5, 21, 8, 22.4), 'iron', 'flat'); c.shape(rect(16, 21, 19, 22.4), 'iron', 'flat'); }],
  ['Offene Truhe', 'Gold quillt über', (c) => { c.shape(rect(3, 13, 21, 21), 'wood', 'diag'); c.shape(poly([[3, 13], [5, 6], [19, 6], [21, 13]]), 'woodl', 'vert'); c.shape(poly([[4, 13], [20, 13], [18, 9], [6, 9]]), 'gold', 'vert'); for (const [x, y] of [[8, 10], [12, 9], [16, 10], [10, 12], [14, 12]]) c.shape(ell(x, y, 1.8, 1.4), 'goldl', 'orb'); c.shape(rect(3, 16, 21, 17.4), 'iron', 'vert'); }],
  ['Geldbörse', 'Beutel am Turm', (c) => { c.shape(rect(9, 2, 15, 20), 'stone', 'diag'); c.shape(ell(12, 14, 7, 5.4), 'leather', 'orb'); c.shape(ell(12, 14, 2.2, 2.2), 'gold', 'orb'); c.shape(rect(8, 21, 16, 22.4), 'stone', 'vert'); }],
  ['Torbogen', 'Bogen mit Münzen', (c) => { c.shape(minus(rect(2, 4, 22, 21), poly([[7, 21], [7, 11], [9, 8], [15, 8], [17, 11], [17, 21]])), 'face', 'diag'); c.shape(ell(12, 4, 3, 3), 'gold', 'orb'); c.shape(ell(12, 17, 3.4, 3.4), 'gold', 'orb'); c.shape(ell(12, 17, 1.8, 1.8), 'goldl', 'orb'); }],
  ['Münzturm', 'Im Rahmen', (c) => { c.shape(minus(rect(2, 2, 22, 22), rect(4.6, 4.6, 19.4, 19.4)), 'gold', 'diag'); for (let i = 0; i < 4; i++) { const y = 17 - i * 3.2; c.shape(rect(7, y, 17, y + 2.4), 'goldl', 'vert'); c.shape(ell(12, y, 5, 1.6), 'goldl', 'orb'); } }],
];

const derelict = [
  ['Mauerrest', 'Schiefes Dach', (c) => { c.shape(poly([[4, 21], [4, 12], [8, 10], [11, 14], [14, 11], [19, 13], [19, 21]]), 'stone', 'diag'); c.shape(poly([[2, 12], [8, 5], [12, 8], [10, 10]]), 'roof', 'vert', 0.2); c.shape(rect(8, 16, 12, 21), 'black', 'flat'); c.px(15, 17, 'moss', 2); }],
  ['Eingestürzt', 'Haus mit Loch', (c) => { c.shape(poly([[3, 21], [3, 11], [10, 11], [14, 16], [21, 13], [21, 21]]), 'wall', 'diag', 0.2); c.shape(poly([[1, 12], [8, 5], [13, 8], [9, 12]]), 'roof', 'vert', 0.2); c.shape(thick(11, 14, 18, 9, 2), 'bark', 'diag'); c.shape(rect(6, 15, 9, 21), 'black', 'flat'); }],
  ['Schornsteinrest', 'Nur der Kamin', (c) => { c.shape(rect(9, 6, 15, 21), 'clay', 'diag'); c.shape(poly([[9, 6], [11, 3], [13, 6]]), 'clay', 'diag'); c.shape(ell(5, 20, 3, 1.8), 'stone', 'orb'); c.shape(ell(19, 20, 3.4, 2), 'stone', 'orb'); c.shape(rect(10, 15, 14, 21), 'black', 'flat'); }],
  ['Bogenruine', 'Gebrochener Bogen', (c) => { c.shape(minus(poly([[2, 21], [2, 9], [12, 3], [22, 12], [22, 21]]), poly([[7, 21], [7, 12], [10, 9], [14, 9], [17, 12], [17, 21]])), 'stone', 'diag'); c.shape(ell(20, 21, 2.6, 1.6), 'stone2', 'orb'); }],
  ['Schutthaufen', 'Trümmer und Balken', (c) => { for (const [x, y, rx, r] of [[6, 18, 4, 'stone'], [13, 19, 5, 'stone2'], [18, 17, 3, 'stone']]) c.shape(ell(x, y, rx, 3), r, 'orb'); c.shape(thick(3, 12, 17, 19, 2.4), 'bark', 'diag'); c.shape(thick(18, 9, 12, 18, 2.4), 'wood', 'diag'); }],
  ['Abgebrannt', 'Geschwärztes Haus', (c) => { c.shape(rect(4, 12, 20, 21), 'coal', 'diag'); c.shape(poly([[2, 13], [8, 4], [10, 9], [14, 6], [22, 13]]), 'black', 'vert'); c.shape(poly([[11, 13], [13, 8], [15, 13]]), 'orange', 'vert'); c.shape(rect(9, 15, 12, 21), 'black', 'flat'); }],
  ['Turmstumpf', 'Gebrochener Turm', (c) => { c.shape(poly([[6, 21], [6, 8], [9, 6], [11, 10], [14, 5], [18, 9], [18, 21]]), 'stone', 'diag'); c.shape(rect(11, 13, 13, 17), 'black', 'flat'); c.shape(ell(21, 20, 2.4, 1.8), 'stone2', 'orb'); c.shape(ell(3, 20, 2.4, 1.8), 'stone2', 'orb'); }],
  ['Bewachsen', 'Mauer mit Efeu', (c) => { c.shape(poly([[3, 21], [3, 8], [9, 8], [11, 12], [15, 10], [21, 12], [21, 21]]), 'stone', 'diag'); for (const [x, y] of [[5, 9], [7, 12], [6, 16], [17, 12], [19, 15]]) c.shape(ell(x, y, 2, 2.4), 'leaf', 'orb'); }],
  ['Bretterkreuz', 'Vernagelt', (c) => { c.shape(rect(4, 5, 20, 21), 'wall', 'diag', 0.2); c.shape(thick(3, 6, 21, 20, 3.4), 'bark', 'diag'); c.shape(thick(3, 20, 21, 6, 3.4), 'wood', 'diag'); c.px(5, 7, 'iron', 4); c.px(19, 19, 'iron', 4); }],
  ['Spukhaus', 'Mit Fledermaus', (c) => { c.shape(rect(5, 11, 19, 21), 'iron', 'diag'); c.shape(poly([[3, 12], [12, 2], [21, 12]]), 'purple', 'vert'); for (const x of [8, 14]) c.shape(rect(x, 13, x + 3, 16.4), 'bolt', 'flat'); door(c, 10.4, 17, 13.6, 21, 'black'); c.shape(poly([[17, 4], [19, 2], [20, 4], [22, 2], [22, 5], [20, 6], [18, 6]]), 'black', 'flat'); }],
];

// road (+ roadOff = same with a red slash)
const slash = (c) => { c.shape(ring(12, 12, 11, 9.4), 'red', 'orb'); c.shape(thick(4.6, 4.6, 19.4, 19.4, 2.6), 'red', 'diag'); };
const road = [
  ['Perspektive', 'Straße mit Mittelstrich', (c) => { c.shape(poly([[10, 2], [14, 2], [23, 22], [1, 22]]), 'stone', 'vert'); for (const [y, h] of [[4, 2], [9, 3], [16, 4]]) c.shape(rect(11.4, y, 12.6, y + h), 'bolt', 'flat'); }],
  ['Pflaster', 'Gepflasterter Weg', (c) => { c.shape(poly([[4, 3], [20, 3], [23, 22], [1, 22]]), 'stone2', 'vert'); for (const [x, y, w] of [[6, 6, 4], [11, 6, 5], [5, 11, 5], [11, 11, 4], [16, 11, 4], [3, 17, 6], [10, 17, 5], [16, 17, 5]]) c.line(x, y, x + w, y, 'stone', 1); }],
  ['Kurve', 'Geschwungener Weg', (c) => { c.shape(path([[4, 22], [6, 14], [16, 12], [18, 4]], 5.4), 'sand', 'vert'); c.shape(path([[4, 22], [6, 14], [16, 12], [18, 4]], 0.8), 'bark', 'flat'); }],
  ['Wegweiser', 'Schild am Weg', (c) => { c.shape(rect(11, 5, 13, 22), 'wood', 'diag'); c.shape(poly([[4, 4], [15, 4], [18, 7], [15, 10], [4, 10]]), 'woodl', 'diag'); c.shape(poly([[20, 12], [9, 12], [6, 15], [9, 18], [20, 18]]), 'wood', 'diag'); }],
  ['Kreuzung', 'Wege kreuzen sich', (c) => { c.shape(rect(9, 1, 15, 23), 'sand', 'vert'); c.shape(rect(1, 9, 23, 15), 'sand', 'vert'); c.shape(rect(9, 9, 15, 15), 'bread', 'orb', 0.1); }],
  ['Steinplatten', 'Trittsteine', (c) => { for (const [x, y, r] of [[6, 20, 3.4], [10, 15, 3], [14, 10, 2.6], [17, 5.5, 2.2]]) c.shape(ell(x, y, r * 1.3, r), 'stone', 'orb'); }],
  ['Brücke', 'Bogenbrücke', (c) => { c.shape(rect(1, 19, 23, 22), 'water', 'vert'); c.shape(minus(rect(2, 9, 22, 19), ell(12, 19, 6, 6.4)), 'stone', 'diag'); c.shape(rect(2, 7, 22, 9.4), 'stone2', 'vert'); }],
  ['Trampelpfad', 'Spuren im Staub', (c) => { c.shape(path([[5, 22], [10, 12], [14, 3]], 6), 'sand', 'vert'); for (const [x, y] of [[8, 19], [11, 14], [13, 9]]) c.shape(ell(x, y, 1, 1.6), 'clay', 'flat'); }],
  ['Pfeil', 'Weg mit Richtung', (c) => { c.shape(poly([[7, 22], [17, 22], [17, 12], [22, 12], [12, 2], [2, 12], [7, 12]]), 'stone', 'diag'); c.line(12, 6, 12, 20, 'bolt', 4); }],
  ['Gabelung', 'Weg teilt sich', (c) => { c.shape(path([[12, 22], [12, 13]], 5), 'sand', 'vert'); c.shape(path([[12, 13], [5, 3]], 4.4), 'sand', 'diag'); c.shape(path([[12, 13], [19, 3]], 4.4), 'sand', 'diag', 0.1); }],
];

const doorC = [
  ['Holztür', 'Rundbogen', (c) => { c.shape(poly([[4, 22], [4, 9], [8, 3], [16, 3], [20, 9], [20, 22]]), 'wood', 'diag'); c.shape(rect(11.4, 4, 12.6, 22), 'bark', 'flat'); c.shape(rect(4, 12, 20, 13), 'iron', 'vert'); c.shape(ell(15, 16, 1.2, 1.2), 'gold', 'orb'); }],
  ['Offene Tür', 'Mit Pfeil nach außen', (c) => { c.shape(rect(3, 3, 17, 21), 'black', 'flat'); c.shape(poly([[3, 3], [10, 5], [10, 19], [3, 21]]), 'wood', 'diag'); c.shape(rect(11, 11, 21, 13), 'bolt', 'vert'); c.shape(poly([[22, 12], [17, 8], [17, 16]]), 'bolt', 'diag'); }],
  ['Gittertor', 'Eisentor', (c) => { c.shape(minus(rect(3, 3, 21, 21), either(rect(6, 6, 10, 20), either(rect(11, 6, 13, 20), rect(14, 6, 18, 20)))), 'iron', 'diag'); for (const x of [8, 12, 16]) c.shape(rect(x - 0.6, 3, x + 0.6, 21), 'steel', 'flat'); }],
  ['Burgtür', 'Mit Eisenbeschlag', (c) => { c.shape(rect(3, 3, 21, 22), 'stone', 'diag'); c.shape(poly([[7, 22], [7, 11], [9, 8], [15, 8], [17, 11], [17, 22]]), 'wood', 'diag'); for (const y of [12, 17]) c.shape(rect(7, y, 17, y + 1.2), 'iron', 'vert'); }],
  ['Lichtspalt', 'Helle Öffnung', (c) => { c.shape(rect(3, 3, 21, 22), 'wood', 'diag'); c.shape(poly([[8, 22], [8, 8], [12, 4], [16, 8], [16, 22]]), 'goldl', 'orb', -0.1); c.shape(rect(11, 6, 13, 22), 'bolt', 'flat', -0.2); }],
  ['Rundtür', 'Hobbit-Tür', (c) => { c.shape(rect(1, 4, 23, 22), 'moss', 'vert'); c.shape(ell(12, 13, 7.6, 7.6), 'wood', 'orb'); c.shape(ring(12, 13, 7.6, 6.4), 'iron', 'flat'); c.shape(ell(12, 13, 1.6, 1.6), 'gold', 'orb'); }],
  ['Eisentür', 'Mit Riegel', (c) => { c.shape(rect(4, 3, 20, 22), 'iron', 'diag'); c.shape(rect(6, 5, 18, 20), 'steel', 'vert', 0.1); c.shape(rect(5, 11, 19, 13), 'black', 'vert'); for (const [x, y] of [[7, 7], [16, 7], [7, 17], [16, 17]]) c.px(x, y, 'face', 4); }],
  ['Doppeltür', 'Zwei Flügel', (c) => { c.shape(poly([[3, 22], [3, 8], [12, 3], [21, 8], [21, 22]]), 'wood', 'diag'); c.shape(rect(11.4, 4, 12.6, 22), 'black', 'flat'); c.shape(ell(10, 15, 0.9, 0.9), 'gold', 'orb'); c.shape(ell(14, 15, 0.9, 0.9), 'gold', 'orb'); }],
  ['Ausgangsschild', 'Tür mit Pfeil', (c) => { c.shape(rect(2, 4, 22, 20), 'green', 'diag'); c.shape(rect(5, 7, 10, 17), 'face', 'flat'); c.shape(rect(11, 11, 19, 13), 'face', 'vert'); c.shape(poly([[21, 12], [16, 8], [16, 16]]), 'face', 'diag'); }],
  ['Treppe hinaus', 'Stufen zur Tür', (c) => { c.shape(poly([[8, 3], [18, 3], [18, 14], [8, 14]]), 'wood', 'diag'); for (const [x, y] of [[2, 20], [5, 17], [8, 14]]) c.shape(rect(x, y, x + 10, y + 3), 'stone', 'vert'); }],
];

const flag = [
  ['Wimpel', 'Stange mit roter Fahne', (c) => { c.shape(rect(4, 2, 6, 22), 'wood', 'diag'); c.shape(poly([[6, 3], [20, 3], [20, 12], [6, 12]]), 'red', 'diag'); c.shape(ell(5, 2, 1.8, 1.8), 'gold', 'orb'); }],
  ['Wehende Fahne', 'Mit Welle', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(poly([[5, 3], [10, 5], [15, 3], [21, 5], [21, 13], [15, 11], [10, 13], [5, 11]]), 'blue', 'diag'); c.shape(star(13, 8, 3, 1.3), 'goldl', 'orb'); }],
  ['Banner', 'Hängend', (c) => { c.shape(rect(3, 2, 21, 4), 'wood', 'vert'); c.shape(poly([[5, 4], [19, 4], [19, 18], [12, 22], [5, 18]]), 'red', 'diag'); c.shape(star(12, 11, 4, 1.8), 'goldl', 'orb'); }],
  ['Schwalbenschwanz', 'Zweizipflig', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(poly([[5, 3], [22, 3], [17, 8], [22, 13], [5, 13]]), 'orange', 'diag'); }],
  ['Zielflagge', 'Schachbrett', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(rect(5, 3, 21, 13), 'face', 'diag'); for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) if ((i + j) % 2 === 0) c.shape(rect(5 + i * 4, 3 + j * 3.34, 9 + i * 4, 6.34 + j * 3.34), 'black', 'flat'); }],
  ['Auf Hügel', 'Fahne im Boden', (c) => { c.shape(ell(12, 22, 11, 5), 'moss', 'orb'); c.shape(rect(11, 3, 12.6, 19), 'wood', 'diag'); c.shape(poly([[12.6, 3], [20, 6], [12.6, 9]]), 'red', 'diag'); }],
  ['Dreieckswimpel', 'Spitz', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(poly([[5, 3], [22, 8], [5, 13]]), 'bolt', 'diag'); }],
  ['Wappenfahne', 'Fahne mit Schild', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(rect(5, 3, 21, 14), 'blue', 'diag'); c.shape(poly([[10, 5], [16, 5], [16, 10], [13, 13], [10, 10]]), 'face', 'diag'); }],
  ['Zwei Fahnen', 'Gekreuzte Stangen', (c) => { c.shape(thick(4, 21, 17, 3, 1.6), 'wood', 'flat'); c.shape(thick(20, 21, 7, 3, 1.6), 'wood', 'flat'); c.shape(poly([[17, 3], [23, 6], [15, 9]]), 'red', 'diag'); c.shape(poly([[7, 3], [1, 6], [9, 9]]), 'blue', 'diag'); }],
  ['Zerfetzt', 'Alte Fahne', (c) => { c.shape(rect(3, 2, 5, 22), 'wood', 'diag'); c.shape(poly([[5, 3], [21, 4], [18, 7], [22, 10], [17, 12], [20, 14], [5, 12]]), 'red', 'diag', 0.15); c.line(8, 7, 14, 7, 'red', 1); }],
];

const pin = [
  ['Kartenmarker', 'Roter Tropfen', (c) => { c.shape(poly([[12, 22], [5, 12], [5, 8], [8, 3], [16, 3], [19, 8], [19, 12]]), 'red', 'orb'); c.shape(ell(12, 9, 3, 3), 'face', 'orb'); }],
  ['Reißzwecke', 'Pinnnadel', (c) => { c.shape(ell(12, 7, 6, 5), 'red', 'orb'); c.shape(rect(9, 11, 15, 13), 'red', 'vert'); c.shape(poly([[11, 13], [13, 13], [12, 22]]), 'steel', 'diag'); c.px(10, 5, 'face', 4); }],
  ['Fähnchen', 'Pin mit Flagge', (c) => { c.shape(rect(6, 3, 7.6, 21), 'wood', 'diag'); c.shape(poly([[7.6, 3], [19, 6], [7.6, 10]]), 'red', 'diag'); c.shape(ell(7, 21, 3, 1.4), 'wood', 'orb'); }],
  ['Goldmarker', 'Mit Ring', (c) => { c.shape(poly([[12, 22], [5, 12], [5, 8], [8, 3], [16, 3], [19, 8], [19, 12]]), 'gold', 'orb'); c.shape(ring(12, 9, 3.6, 1.8), 'red', 'orb'); }],
  ['Runde Marke', 'Kreis mit Punkt', (c) => { c.shape(ell(12, 12, 9, 9), 'blue', 'orb'); c.shape(ell(12, 12, 4, 4), 'face', 'orb'); c.shape(ring(12, 12, 10.6, 9), 'cyan', 'flat'); }],
  ['Mit Schatten', 'Marker auf Boden', (c) => { c.shape(ell(12, 21, 6, 2), 'black', 'flat'); c.shape(poly([[12, 20], [6, 11], [6, 8], [8, 3], [16, 3], [18, 8], [18, 11]]), 'red', 'orb'); c.shape(ell(12, 9, 2.6, 2.6), 'face', 'orb'); }],
  ['Nagel', 'Großer Nagel', (c) => { c.shape(rect(7, 3, 17, 6), 'iron', 'vert'); c.shape(poly([[10, 6], [14, 6], [12, 22]]), 'steel', 'diag'); }],
  ['Pfeilmarker', 'Zeigt nach unten', (c) => { c.shape(poly([[8, 2], [16, 2], [16, 11], [21, 11], [12, 22], [3, 11], [8, 11]]), 'green', 'diag'); }],
  ['Raute', 'Rautenmarker', (c) => { c.shape(poly([[12, 1], [20, 10], [12, 23], [4, 10]]), 'purple', 'diag'); c.shape(ell(12, 10, 2.6, 2.6), 'face', 'orb'); }],
  ['X markiert die Stelle', 'Schatzkreuz', (c) => { c.shape(thick(4, 4, 20, 20, 4.4), 'red', 'diag'); c.shape(thick(20, 4, 4, 20, 4.4), 'red', 'diag'); c.shape(ell(12, 22, 6, 1.4), 'sand', 'vert'); }],
];

const CONCEPTS = [
  { cat: 'Gebäude', key: 'house', name: 'Haus', designs: house },
  { cat: 'Gebäude', key: 'castle', name: 'Burg', designs: castle },
  { cat: 'Gebäude', key: 'tent', name: 'Zelt', designs: tent },
  { cat: 'Gebäude', key: 'factory', name: 'Fabrik', designs: factory },
  { cat: 'Gebäude', key: 'bank', name: 'Bank / Tresor', designs: bank },
  { cat: 'Gebäude', key: 'derelict', name: 'Ruine', designs: derelict },
  { cat: 'Gebäude', key: 'road', name: 'Straße (und gesperrte Straße)', designs: road, outs: [['road', 'road', undefined, null], ['roadOff', 'roadOff', undefined, null, slash]] },
  { cat: 'Gebäude', key: 'door', name: 'Tür', designs: doorC },
  { cat: 'Gebäude', key: 'flag', name: 'Flagge', designs: flag },
  { cat: 'Gebäude', key: 'pin', name: 'Kartenmarker', designs: pin },
];
module.exports = { CONCEPTS };
