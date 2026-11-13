// Batch 1: resource icons. 10 drawings per concept; the "families" (ore, pile, gem) are drawn once per
// design and tinted per resource, so choosing design #n gives one coherent look for the whole family.
const { ell, rect, poly, thick, minus, both, ring, heart, star } = require('./engine.js');

// ---------- helpers ----------
function logH(c, x0, x1, yc, h) {
  c.shape(rect(x0, yc - h / 2, x1, yc + h / 2), 'bark', 'vert');
  c.shape(ell(x1 + 0.5, yc, h * 0.34, h / 2), 'ring', 'orb', -0.1);
  c.shape(ell(x1 + 0.5, yc, h * 0.17, h * 0.26), 'wood', 'flat');
  c.px(x1 + 0.5, yc, 'bark', 1);
  c.line(x0 + 1, yc - h / 4, x1 - 3, yc - h / 4, 'bark', 4);
  c.line(x0 + 2, yc + h / 4 - 0.5, x1 - 4, yc + h / 4 - 0.5, 'bark', 1);
}
const ingot = (c, x, y, w, col) => {
  c.shape(poly([[x + 2, y], [x + w - 2, y], [x + w + 1, y + 3], [x - 1, y + 3]]), col, 'vert', -0.2);
  c.shape(rect(x - 1, y + 3, x + w, y + 7), col, 'vert');
  c.line(x + 1, y + 4, x + w - 2, y + 4, col, 4);
};
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');

// ---------- WOOD ----------
const wood = [
  ['Holzstapel', 'Drei Stämme, Stirnseite', (c) => {
    for (const [x, y] of [[7, 16], [17, 16], [12, 8]]) {
      c.shape(ell(x, y, 5, 5), 'bark', 'orb'); c.shape(ell(x, y, 3.6, 3.6), 'ring', 'orb', -0.05);
      c.shape(ell(x, y, 1.6, 1.6), 'wood', 'flat'); c.px(x, y, 'bark', 1);
    }
  }],
  ['Einzelner Stamm', 'Liegender Stamm', (c) => logH(c, 2, 18, 12, 9)],
  ['Baumstumpf', 'Stumpf mit Jahresringen', (c) => {
    c.shape(poly([[4, 19], [6, 11], [17, 11], [20, 19]]), 'bark', 'vert');
    c.shape(ell(11.5, 11, 6.5, 3.4), 'ring', 'orb', -0.1); c.shape(ell(11.5, 11, 4, 1.9), 'wood', 'flat');
    c.shape(ell(11.5, 11, 1.8, 0.9), 'ring', 'flat'); c.line(8, 15, 8, 18, 'bark', 1); c.line(14, 14, 15, 18, 'bark', 1);
  }],
  ['Bretter', 'Gestapelte Bretter', (c) => {
    c.shape(rect(3, 14, 20, 18), 'woodl', 'vert'); c.shape(rect(4, 9, 21, 13), 'wood', 'vert'); c.shape(rect(3, 4, 20, 8), 'woodl', 'vert');
    for (const y of [6, 11, 16]) { c.line(5, y, 12, y, 'wood', 1); c.px(18, y, 'iron', 3); }
  }],
  ['Bündel', 'Drei Scheite mit Seil', (c) => {
    for (const x of [5, 10, 15]) {
      c.shape(rect(x, 6, x + 4, 19), 'bark', 'diag'); c.shape(ell(x + 2.5, 6, 2.6, 1.8), 'ring', 'orb', -0.1);
    }
    c.shape(rect(4, 12, 20, 13.5), 'leatherd', 'vert'); c.line(20, 13, 22, 17, 'leatherd', 2);
  }],
  ['Baum', 'Laubbaum', (c) => {
    c.shape(rect(10, 13, 13, 20), 'bark', 'diag'); c.shape(ell(12, 9, 8, 6.5), 'moss', 'orb');
    c.shape(ell(7.5, 11.5, 4.5, 3.5), 'moss', 'orb', -0.02); c.shape(ell(16.5, 11.5, 4.5, 3.5), 'moss', 'orb', 0.04);
    c.px(9, 6, 'face', 4); c.px(10, 5, 'face', 4);
  }],
  ['Stammscheibe', 'Große Scheibe mit Ringen', (c) => {
    c.shape(ell(12, 12, 10, 10), 'bark', 'orb'); c.shape(ell(12, 12, 8, 8), 'ring', 'orb', -0.08);
    c.shape(ring(12, 12, 5.6, 4.6), 'wood', 'flat'); c.shape(ring(12, 12, 3, 2.1), 'wood', 'flat'); c.px(12, 12, 'bark', 1);
    c.line(12, 12, 19, 8, 'bark', 1);
  }],
  ['Axt im Stamm', 'Axt steckt im Holz', (c) => {
    logH(c, 2, 19, 17, 7);
    c.shape(thick(15, 4, 10, 16, 2.3), 'wood', 'diag');
    c.shape(poly([[11, 3], [20, 2], [19, 9], [11, 8]]), 'steel', 'diag'); c.line(12, 3, 19, 3, 'face', 4);
  }],
  ['Gekreuzt', 'Zwei gekreuzte Stämme', (c) => {
    c.shape(thick(3, 5, 21, 19, 5), 'bark', 'diag'); c.shape(thick(3, 19, 21, 5, 5), 'bark', 'diag', 0.08);
    for (const [x, y] of [[20.5, 18.5], [20.5, 5.5]]) { c.shape(ell(x, y, 2.4, 2.4), 'ring', 'orb'); c.px(x, y, 'bark', 1); }
  }],
  ['Brett mit Nägeln', 'Einzelnes Brett schräg', (c) => {
    c.shape(thick(3, 19, 20, 5, 7), 'woodl', 'diag'); c.line(5, 16, 16, 7, 'wood', 1);
    c.px(7, 17, 'iron', 4); c.px(17, 8, 'iron', 4); c.px(11, 12, 'wood', 1);
  }],
];

// ---------- STONE ----------
const stone = [
  ['Felsbrocken', 'Ein großer Brocken', (c) => {
    c.shape(poly([[3, 19], [2, 12], [6, 6], [13, 4], [19, 8], [21, 14], [19, 19]]), 'stone', 'diag');
    c.line(8, 8, 13, 6, 'stone', 4); c.line(10, 11, 9, 16, 'stone', 1); c.line(15, 12, 17, 16, 'stone', 1);
  }],
  ['Drei Steine', 'Kleiner Haufen', (c) => {
    c.shape(ell(7, 16, 5.5, 4.5), 'stone', 'orb'); c.shape(ell(16.5, 16, 6, 4.8), 'stone2', 'orb'); c.shape(ell(11.5, 9, 5.5, 4.5), 'stone', 'orb', -0.04);
  }],
  ['Quader', 'Behauener Würfel', (c) => {
    c.shape(poly([[3, 8], [12, 3], [21, 8], [12, 13]]), 'stone2', 'vert', -0.18);
    c.shape(poly([[3, 8], [12, 13], [12, 21], [3, 16]]), 'stone', 'diag', 0.05);
    c.shape(poly([[12, 13], [21, 8], [21, 16], [12, 21]]), 'stone', 'diag', 0.25);
  }],
  ['Mauerstück', 'Mauerwerk', (c) => {
    c.shape(rect(2, 5, 21, 19), 'stone2', 'diag');
    for (const y of [9.5, 14]) c.line(2, y, 21, y, 'stone', 1);
    for (const [x, y0, y1] of [[8, 5, 9], [15, 5, 9], [5, 10, 14], [12, 10, 14], [18, 10, 14], [8, 15, 19], [15, 15, 19]]) c.line(x, y0, x, y1, 'stone', 1);
  }],
  ['Fels + Spitzhacke', 'Brocken mit Hacke', (c) => {
    c.shape(poly([[2, 20], [2, 15], [6, 11], [12, 12], [14, 20]]), 'stone', 'diag');
    c.shape(thick(9, 21, 18, 6, 2.4), 'wood', 'diag');
    c.shape(poly([[11, 6], [17, 2], [22, 7], [20, 8], [17, 5], [13, 8]]), 'iron', 'diag');
  }],
  ['Plattenstapel', 'Flache Platten', (c) => {
    c.shape(rect(3, 14, 20, 19), 'stone', 'vert'); c.shape(rect(5, 9, 21, 13), 'stone2', 'vert'); c.shape(rect(4, 4, 18, 8), 'stone', 'vert');
    c.line(4, 5, 16, 5, 'stone2', 4); c.line(6, 10, 19, 10, 'stone2', 4);
  }],
  ['Kiesel', 'Verstreute Kiesel', (c) => {
    for (const [x, y, rx, ry, r] of [[7, 8, 4, 3, 'stone'], [16, 7, 3.5, 3, 'stone2'], [11, 14, 5, 4, 'stone2'], [5, 17, 2.6, 2, 'stone'], [18, 17, 3.6, 2.8, 'stone']])
      c.shape(ell(x, y, rx, ry), r, 'orb');
  }],
  ['Spitzer Stein', 'Kantiger Splitter', (c) => {
    c.shape(poly([[12, 2], [19, 10], [17, 20], [7, 20], [5, 10]]), 'stone', 'vert');
    c.shape(poly([[12, 2], [19, 10], [14, 12]]), 'stone2', 'diag'); c.line(12, 3, 11, 19, 'stone', 1);
  }],
  ['Moosstein', 'Rund mit Moos', (c) => {
    c.shape(ell(12, 13, 10, 7.5), 'stone', 'orb'); c.shape(both(ell(12, 13, 10, 7.5), rect(0, 0, 24, 10.5)), 'moss', 'vert', -0.05);
    c.px(7, 11, 'moss', 2); c.px(16, 11, 'moss', 2); c.px(9, 8, 'moss', 4);
  }],
  ['Gemeißelt', 'Block mit Meißel', (c) => {
    c.shape(rect(3, 8, 19, 20), 'stone2', 'diag'); c.shape(rect(7, 12, 15, 17), 'stone', 'vert', 0.2);
    c.shape(thick(14, 3, 20, 9, 2.4), 'iron', 'diag'); c.px(21, 10, 'face', 4);
  }],
];

// ---------- COIN / GOLD ----------
const coin = [
  ['Münze mit Stern', 'Klassisch, Vorderseite', (c) => {
    c.shape(ell(12, 12, 9, 9), 'gold', 'orb'); c.shape(ell(12, 12, 6.7, 6.7), 'gold', 'orb', 0.18);
    c.shape(star(12, 12.4, 5.6, 2.5), 'goldl', 'flat', -0.05); c.px(6, 6, 'face', 4); c.px(7, 5, 'face', 4);
  }],
  ['Münzstapel', 'Vier Münzen übereinander', (c) => {
    for (let i = 0; i < 4; i++) {
      const y = 17 - i * 3.6;
      c.shape(rect(5, y, 18, y + 2.6), 'gold', 'vert'); c.shape(ell(11.5, y, 6.8, 2.6), 'goldl', 'orb', -0.05);
    }
  }],
  ['Münze kantig', 'Schräg gekippt', (c) => {
    c.shape(ell(14.5, 12, 5, 9), 'gold', 'diag', 0.25); c.shape(ell(11.5, 12, 5.2, 9), 'goldl', 'orb'); c.shape(ell(11.5, 12, 3, 6.6), 'gold', 'orb', 0.12);
    c.line(11, 8, 11, 16, 'goldl', 4);
  }],
  ['Beutel', 'Geldsack mit Münze', (c) => {
    c.shape(ell(12, 15.5, 8.5, 6.5), 'leather', 'orb'); c.shape(poly([[8, 8], [16, 8], [15, 12], [9, 12]]), 'leather', 'diag');
    c.shape(rect(8, 7.5, 15, 9.5), 'red', 'vert'); c.shape(poly([[6, 4], [9, 7], [15, 7], [18, 4], [12, 6]]), 'leather', 'diag', 0.1);
    c.shape(ell(12, 16, 2.8, 2.8), 'gold', 'orb'); c.px(11, 15, 'goldl', 4);
  }],
  ['Krönchen-Münze', 'Münze mit Krone', (c) => {
    c.shape(ell(12, 12, 9, 9), 'gold', 'orb'); c.shape(ell(12, 12, 6.8, 6.8), 'gold', 'orb', 0.18);
    c.shape(poly([[7, 16], [7, 8], [9.5, 11], [12, 7], [14.5, 11], [17, 8], [17, 16]]), 'goldl', 'flat'); c.px(12, 9, 'red', 2);
  }],
  ['Münze mit Loch', 'Quadratisches Loch', (c) => {
    c.shape(minus(ell(12, 12, 9.5, 9.5), rect(10, 10, 13, 13)), 'gold', 'orb'); c.shape(ring(12, 12, 8, 7), 'goldl', 'flat', -0.05);
  }],
  ['Münzhaufen', 'Drei Münzen', (c) => {
    for (const [x, y] of [[7, 17], [16.5, 17], [11.5, 9]]) { c.shape(ell(x, y, 5.2, 5.2), 'gold', 'orb'); c.shape(ell(x, y, 3.4, 3.4), 'goldl', 'orb', 0.12); }
  }],
  ['Goldbarren', 'Barren im Schnitt', (c) => {
    c.shape(poly([[6, 7], [18, 7], [22, 12], [2, 12]]), 'goldl', 'vert', -0.1); c.shape(rect(2, 12, 21, 19), 'gold', 'vert');
    c.line(4, 13, 19, 13, 'goldl', 4); sparkle(c, 19, 5, 3);
  }],
  ['Münze mit Glanz', 'Funkelnde Münze', (c) => {
    c.shape(ell(11, 13, 8, 8), 'gold', 'orb'); c.shape(ell(11, 13, 5.7, 5.7), 'gold', 'orb', 0.18); c.line(11, 9, 11, 17, 'goldl', 3); c.line(9, 11, 13, 11, 'goldl', 3);
    sparkle(c, 19.5, 5.5, 3.6);
  }],
  ['Schatzhaufen', 'Haufen aus Münzen', (c) => {
    c.shape(poly([[1, 20], [5, 13], [10, 9], [14, 9], [19, 13], [23, 20]]), 'gold', 'vert');
    for (const [x, y, r] of [[8, 14, 'goldl'], [14, 12, 'goldl'], [11, 17, 'goldl'], [18, 17, 'goldl'], [5, 18, 'goldl'], [12, 10, 'face']]) c.shape(ell(x, y, 2.2, 2.2), r, 'orb');
  }],
];

// ---------- FOOD ----------
const fishBody = (c, x, y, s = 1) => {
  c.shape(poly([[x + 6 * s, y], [x + 11 * s, y - 4 * s], [x + 10 * s, y], [x + 11 * s, y + 4 * s]]), 'fin', 'diag');
  c.shape(ell(x, y, 8 * s, 4.6 * s), 'fish', 'orb');
  c.shape(both(ell(x, y, 8 * s, 4.6 * s), rect(0, y + 1, 24, 24)), 'fishb', 'vert', -0.1);
  c.px(x - 6 * s, y - 1, 'face', 4); c.px(x - 6 * s, y, 'black', 1);
};
const food = [
  ['Fisch', 'Wie bisher, ein Fisch', (c) => fishBody(c, 10, 12)],
  ['Zwei Fische', 'Fangkorb-Ausbeute', (c) => { fishBody(c, 9, 8, 0.78); fishBody(c, 11, 17, 0.78); }],
  ['Brotlaib', 'Ofenfrisch', (c) => {
    c.shape(ell(12, 13, 10, 6.5), 'bread', 'orb'); for (const x of [8, 12, 16]) c.line(x - 1, 10, x + 1, 15, 'bread', 1);
    c.line(6, 9, 10, 8, 'bread', 4); c.line(14, 8, 17, 9, 'bread', 4);
  }],
  ['Apfel', 'Roter Apfel mit Blatt', (c) => {
    c.shape(ell(12, 14, 8, 7.5), 'apple', 'orb'); c.shape(ell(12, 8, 2.5, 2), 'apple', 'orb', 0.25);
    c.shape(thick(12, 8, 13, 3, 1.4), 'leatherd', 'flat'); c.shape(ell(16.5, 5, 3.4, 1.8), 'leaf', 'orb'); c.px(8, 11, 'face', 4); c.px(9, 10, 'face', 4);
  }],
  ['Schinken', 'Keule mit Knochen', (c) => {
    c.shape(thick(15, 15, 20, 20, 3), 'face', 'diag'); c.shape(ell(21, 20.5, 2, 2), 'face', 'orb'); c.shape(ell(10, 12, 8, 7), 'meat', 'orb');
    c.shape(ell(8, 9.5, 3.6, 2.2), 'fat', 'orb', -0.1); c.px(13, 14, 'meat', 1);
  }],
  ['Käse', 'Käsekeil', (c) => {
    c.shape(poly([[2, 17], [2, 10], [21, 5], [22, 17]]), '#f0c040', 'diag'); c.shape(poly([[2, 10], [21, 5], [22, 8], [2, 13]]), '#f8dc78', 'vert');
    for (const [x, y] of [[8, 14], [15, 13], [18, 9]]) c.shape(ell(x, y, 1.6, 1.4), '#f0c040', 'orb', 0.3);
  }],
  ['Weizen', 'Ähre', (c) => {
    c.line(12, 22, 12, 7, 'leaf', 2);
    for (let i = 0; i < 4; i++) { const y = 7 + i * 3.4; c.shape(ell(9.2, y, 2.5, 1.5), '#e0b040', 'orb'); c.shape(ell(14.8, y, 2.5, 1.5), '#e0b040', 'orb'); }
    c.shape(ell(12, 3.6, 1.4, 2.6), '#e0b040', 'orb');
  }],
  ['Suppenschüssel', 'Dampfende Schüssel', (c) => {
    c.shape(both(ell(12, 11, 10, 10), rect(0, 11, 24, 24)), 'leatherd', 'vert', -0.1); c.shape(ell(12, 11, 9.4, 2.6), 'orange', 'orb');
    c.line(8, 4, 9, 8, 'face', 4); c.line(13, 3, 14, 8, 'face', 4); c.line(17, 5, 17, 8, 'face', 3);
  }],
  ['Vorratskorb', 'Korb mit Brot und Apfel', (c) => {
    c.shape(ell(8.5, 8, 3.6, 3.2), 'apple', 'orb'); c.shape(ell(15, 7.5, 4.6, 3), 'bread', 'orb');
    c.shape(poly([[3, 11], [21, 11], [19, 21], [5, 21]]), 'leather', 'diag'); c.line(4, 15, 20, 15, 'leatherd', 1); c.line(5, 18, 19, 18, 'leatherd', 1);
  }],
  ['Fischgräte', 'Abgenagtes Skelett', (c) => {
    c.line(4, 12, 19, 12, 'face', 4); c.line(4, 13, 19, 13, 'face', 3);
    for (const x of [8, 11, 14, 17]) { c.line(x, 12, x - 2, 7, 'face', 4); c.line(x, 13, x - 2, 18, 'face', 4); }
    c.shape(ell(5, 12.5, 3.4, 3.2), 'face', 'orb'); c.shape(poly([[19, 12], [23, 8], [23, 17]]), 'face', 'diag');
  }],
];

// ---------- ORE family (ramp name o) ----------
const rock = (c) => c.shape(poly([[2, 19], [2, 12], [6, 6], [13, 4], [19, 8], [22, 14], [20, 19]]), 'stone', 'diag');
const ore = [
  ['Gesteinsbrocken', 'Fels mit Erzkörnern', (c, o) => {
    rock(c); for (const [x, y] of [[7, 10], [12, 8], [16, 12], [9, 15], [14, 16], [5, 14]]) { c.shape(rect(x, y, x + 1.6, y + 1.6), o, 'orb'); }
  }],
  ['Nuggethaufen', 'Drei Klumpen', (c, o) => {
    c.shape(ell(7, 16, 5, 4), o, 'orb'); c.shape(ell(16.5, 16, 5.5, 4.5), o, 'orb', 0.05); c.shape(ell(11.5, 9, 5, 4.2), o, 'orb', -0.05); c.px(10, 8, 'face', 4); c.px(5, 15, 'face', 4);
  }],
  ['Barren', 'Ein Barren', (c, o) => { ingot(c, 4, 9, 17, o); sparkle(c, 19, 5, 2.6); }],
  ['Barrenstapel', 'Drei Barren', (c, o) => { ingot(c, 2, 13, 10, o); ingot(c, 12, 13, 10, o); ingot(c, 7, 6, 10, o); }],
  ['Aderstein', 'Fels mit Erzader', (c, o) => {
    rock(c); c.shape(thick(6, 17, 17, 8, 3), o, 'diag'); c.shape(thick(11, 14, 18, 15, 2), o, 'diag'); c.px(8, 15, 'face', 4);
  }],
  ['Nugget + Hacke', 'Klumpen und Spitzhacke', (c, o) => {
    c.shape(ell(8, 16, 6.5, 4.8), o, 'orb'); c.shape(thick(10, 21, 19, 5, 2.4), 'wood', 'diag');
    c.shape(poly([[12, 5], [18, 1], [23, 6], [21, 7], [18, 4], [14, 7]]), 'iron', 'diag');
  }],
  ['Facettenklumpen', 'Kantiger Brocken', (c, o) => {
    c.shape(poly([[3, 15], [6, 7], [12, 3], [19, 6], [22, 14], [16, 20], [7, 20]]), o, 'diag');
    c.shape(poly([[6, 7], [12, 3], [13, 11], [8, 13]]), o, 'vert', -0.25); c.shape(poly([[13, 11], [19, 6], [22, 14], [16, 20]]), o, 'diag', 0.22);
  }],
  ['Erzsack', 'Sack voll Erz', (c, o) => {
    c.shape(ell(12, 16, 8.5, 6), 'leather', 'orb'); c.shape(poly([[8, 10], [16, 10], [15, 13], [9, 13]]), 'leather', 'diag');
    c.shape(ell(12, 8.5, 5, 3.3), o, 'orb'); c.shape(ell(9.5, 7, 2.4, 1.8), o, 'orb', -0.1); c.shape(rect(8, 10.5, 15, 12), 'red', 'vert');
  }],
  ['Kristallader', 'Drei Erzprismen', (c, o) => {
    c.shape(poly([[3, 20], [5, 9], [8, 4], [11, 9], [12, 20]]), o, 'diag');
    c.shape(poly([[10, 20], [12, 6], [15, 1], [18, 7], [19, 20]]), o, 'diag', 0.08); c.shape(poly([[15, 20], [17, 12], [20, 9], [22, 20]]), o, 'diag', 0.18);
    c.line(8, 5, 8, 17, 'face', 4); c.line(15, 3, 14, 16, 'face', 4);
  }],
  ['Funkelfels', 'Fels mit Glitzer', (c, o) => {
    c.shape(ell(10, 15, 8, 5.5), 'stone', 'orb'); c.shape(ell(10, 14, 4.4, 3.4), o, 'orb'); c.shape(ell(15, 16, 3, 2.4), o, 'orb', 0.1);
    sparkle(c, 17, 7, 4.4); sparkle(c, 6, 6, 2.4);
  }],
];

// ---------- PILE family (ramp name o) ----------
const pile = [
  ['Haufen', 'Aufgeschütteter Haufen', (c, o) => {
    c.shape(both(ell(12, 20, 11, 13), rect(0, 0, 24, 20)), o, 'vert', -0.05); c.line(8, 14, 11, 12, o, 4); c.px(15, 15, o, 1); c.px(9, 17, o, 1); c.px(13, 18, o, 4);
  }],
  ['Sack', 'Gefüllter Sack', (c, o) => {
    c.shape(ell(12, 15, 8.5, 7), o, 'orb'); c.shape(poly([[8, 4], [16, 4], [15, 9], [9, 9]]), o, 'diag', 0.1);
    c.shape(rect(8, 8, 15, 9.8), 'leatherd', 'vert'); c.px(9, 13, o, 4); c.px(10, 12, o, 4);
  }],
  ['Eimer', 'Eimer voll', (c, o) => {
    c.shape(ell(12, 8, 6.4, 2.6), o, 'orb'); c.shape(poly([[5, 8], [19, 8], [17, 20], [7, 20]]), 'iron', 'diag'); c.shape(ell(12, 8, 5, 1.8), o, 'orb', -0.05);
    c.line(6, 12, 18, 12, 'steel', 1); c.line(7, 16, 17, 16, 'steel', 1); c.shape(ring(12, 8, 8, 7), 'iron', 'flat');
  }],
  ['Ziegel', 'Drei geformte Blöcke', (c, o) => {
    c.shape(rect(2, 13, 11, 19), o, 'diag'); c.shape(rect(12, 13, 21, 19), o, 'diag', 0.1); c.shape(rect(6.5, 6, 16.5, 12), o, 'diag', -0.05);
    c.line(3, 14, 9, 14, o, 4); c.line(13, 14, 19, 14, o, 4); c.line(8, 7, 15, 7, o, 4);
  }],
  ['Schaufel im Haufen', 'Mit Spaten', (c, o) => {
    c.shape(both(ell(11, 21, 10, 9), rect(0, 0, 24, 21)), o, 'vert'); c.shape(thick(18, 3, 13, 16, 2.2), 'wood', 'diag');
    c.shape(poly([[10, 13], [16, 13], [15, 20], [11, 20]]), 'steel', 'diag');
  }],
  ['Spitzkegel', 'Hoher Kegel', (c, o) => {
    c.shape(poly([[2, 20], [11, 3], [13, 3], [22, 20]]), o, 'diag'); c.line(10, 8, 6, 17, o, 4); c.px(14, 12, o, 1); c.px(12, 16, o, 1); c.px(16, 17, o, 1);
  }],
  ['Schubkarre', 'Voll beladen', (c, o) => {
    c.shape(ell(10, 10, 7, 3.6), o, 'orb'); c.shape(poly([[2, 11], [18, 11], [15, 18], [5, 18]]), 'leather', 'diag');
    c.shape(thick(15, 14, 22, 11, 1.8), 'wood', 'flat'); c.shape(ell(10.5, 19.5, 2.6, 2.6), 'iron', 'orb');
  }],
  ['Fliese', 'Gebrannte Platte', (c, o) => {
    c.shape(poly([[3, 10], [16, 5], [22, 9], [9, 15]]), o, 'vert', -0.15); c.shape(poly([[3, 10], [9, 15], [9, 19], [3, 14]]), o, 'diag', 0.1);
    c.shape(poly([[9, 15], [22, 9], [22, 13], [9, 19]]), o, 'diag', 0.28); c.line(8, 9, 15, 11, o, 1);
  }],
  ['Schale', 'Schale mit Füllung', (c, o) => {
    c.shape(ell(12, 11, 7.5, 3.6), o, 'orb'); c.shape(both(ell(12, 11, 10, 8), rect(0, 11, 24, 24)), 'leatherd', 'vert', -0.1); c.shape(ell(12, 11, 9.4, 2.4), o, 'orb', -0.05);
  }],
  ['Krug', 'Tonkrug', (c, o) => {
    c.shape(ell(12, 14, 7.5, 7.5), o, 'orb'); c.shape(rect(9, 4, 14, 9), o, 'diag'); c.shape(ell(11.5, 4, 3.6, 1.6), o, 'orb', -0.1);
    c.line(6, 12, 18, 12, o, 1); c.px(8, 10, 'face', 4);
  }],
];

// ---------- GEM family (ramp name o) ----------
const gem = [
  ['Diamantschliff', 'Klassischer Schliff', (c, o) => {
    c.shape(poly([[12, 21], [2, 9], [6, 3], [18, 3], [22, 9]]), o, 'diag');
    c.shape(poly([[2, 9], [22, 9], [18, 3], [6, 3]]), o, 'vert', -0.2); c.line(8, 9, 12, 20, o, 1); c.line(16, 9, 12, 20, o, 1); c.line(12, 4, 12, 9, o, 4); c.px(7, 5, 'face', 4);
  }],
  ['Brillant', 'Runder Schliff', (c, o) => {
    c.shape(ell(12, 12, 9.5, 9.5), o, 'orb'); c.shape(ell(12, 12, 5.4, 5.4), o, 'orb', -0.18);
    c.line(12, 3, 12, 7, o, 4); c.line(12, 17, 12, 21, o, 1); c.line(3, 12, 7, 12, o, 4); c.line(17, 12, 21, 12, o, 1); c.px(7, 7, 'face', 4);
  }],
  ['Cabochon', 'Glatter Oval', (c, o) => {
    c.shape(ell(12, 12, 7, 9.5), o, 'orb'); c.shape(ell(9.5, 8.5, 2, 3), 'face', 'flat', -0.1);
  }],
  ['Gruppe', 'Drei Kristalle', (c, o) => {
    c.shape(poly([[2, 20], [4, 10], [7, 6], [10, 10], [11, 20]]), o, 'diag'); c.shape(poly([[9, 20], [11, 7], [14, 2], [17, 7], [18, 20]]), o, 'diag', 0.08);
    c.shape(poly([[15, 20], [17, 13], [20, 10], [22, 20]]), o, 'diag', 0.18); c.line(7, 8, 6, 17, 'face', 4); c.line(14, 4, 13, 16, 'face', 4);
  }],
  ['Sechskant', 'Einzelner Kristall', (c, o) => {
    c.shape(poly([[12, 2], [18, 6], [18, 18], [12, 22], [6, 18], [6, 6]]), o, 'diag'); c.shape(poly([[12, 2], [18, 6], [12, 10], [6, 6]]), o, 'vert', -0.2);
    c.line(12, 10, 12, 21, o, 1); c.px(8, 8, 'face', 4);
  }],
  ['Splitter', 'Schräger Scherben', (c, o) => {
    c.shape(poly([[4, 21], [6, 11], [16, 2], [20, 8], [10, 20]]), o, 'diag'); c.shape(poly([[6, 11], [16, 2], [14, 11]]), o, 'vert', -0.2); c.line(14, 11, 10, 20, o, 1);
  }],
  ['Ring', 'Goldring mit Stein', (c, o) => {
    c.shape(ring(12, 15, 7, 4.6), 'gold', 'orb'); c.shape(poly([[12, 11], [8, 7], [10, 3], [14, 3], [16, 7]]), o, 'diag'); c.line(10, 6, 14, 6, o, 4);
  }],
  ['Auf Kissen', 'Stein auf Samtkissen', (c, o) => {
    c.shape(ell(12, 17, 10, 4.4), 'red', 'orb'); c.shape(rect(2, 15, 22, 19), 'red', 'vert'); c.shape(ell(12, 15, 10, 3.6), 'red', 'orb', -0.1);
    c.shape(poly([[12, 14], [7, 8], [9, 3], [15, 3], [17, 8]]), o, 'diag'); c.line(9, 6, 15, 6, o, 4);
  }],
  ['Tropfen', 'Tropfenschliff', (c, o) => {
    c.shape(poly([[12, 2], [18, 12], [12, 22], [6, 12]]), o, 'diag'); c.shape(ell(12, 14, 6, 6.6), o, 'orb'); c.px(10, 11, 'face', 4); c.px(10, 12, 'face', 4);
  }],
  ['Smaragdschliff', 'Achteck', (c, o) => {
    c.shape(poly([[7, 3], [17, 3], [21, 7], [21, 17], [17, 21], [7, 21], [3, 17], [3, 7]]), o, 'diag');
    c.shape(poly([[9, 7], [15, 7], [17, 9], [17, 15], [15, 17], [9, 17], [7, 15], [7, 9]]), o, 'vert', 0.2); c.px(5, 5, 'face', 4);
  }],
];

// ---------- registry ----------
const ORE_COL = { ironOre: ['Eisenerz', '#9a7a6c'], copperOre: ['Kupfererz', '#d0763a'], silverOre: ['Silbererz', '#cfd8e0'], goldOre: ['Golderz', '#eaaa22'], coal: ['Kohle', '#3e3a46'] };
const PILE_COL = { clay: ['Lehm', '#b9744a'], sand: ['Sand', '#e4cb84'], lime: ['Kalk', '#ece8dc'] };
const GEM_COL = { gem: ['Edelstein', '#b07af0'], ruby: ['Rubin', '#e0344f'], crystalBlue: ['Kristall blau', '#4f86f0'], crystalCyan: ['Kristall türkis', '#48d0e0'] };

const CONCEPTS = [
  { cat: 'Rohstoffe', key: 'wood', name: 'Holz', designs: wood },
  { cat: 'Rohstoffe', key: 'stone', name: 'Stein', designs: stone },
  { cat: 'Rohstoffe', key: 'coin', name: 'Gold / Münze', designs: coin },
  { cat: 'Rohstoffe', key: 'fish', name: 'Nahrung (Fisch)', designs: food },
  { cat: 'Rohstoffe', family: 'ore', name: 'Erze & Kohle', designs: ore, cols: ORE_COL },
  { cat: 'Rohstoffe', family: 'pile', name: 'Lehm, Sand, Kalk', designs: pile, cols: PILE_COL },
  { cat: 'Rohstoffe', family: 'gem', name: 'Edelsteine & Kristalle', designs: gem, cols: GEM_COL },
];
module.exports = { CONCEPTS };
