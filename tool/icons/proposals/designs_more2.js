// Batch 9: nature, food, objects. Option-table builders.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const build = (fn, rows) => rows.map(([n, d, o]) => [n, d, (c) => fn(c, o)]);
const opt = (n, d, o) => [n, d, o];

// gear
const gearFn = (c, o) => {
  const col = o.col || 'steel', n = o.n || 8, R = o.r || 8;
  for (let a = 0; a < n; a++) { const t = (a * 2 * Math.PI) / n; c.shape(path([[12 + (R - 2) * Math.cos(t), 12 + (R - 2) * Math.sin(t)], [12 + (R + 2.6) * Math.cos(t), 12 + (R + 2.6) * Math.sin(t)]], o.tooth || 3.4), col, 'orb'); }
  c.shape(ell(12, 12, R, R), col, 'orb'); if (o.ring) c.shape(ring(12, 12, R - 1.6, R - 3), 'iron', 'flat'); c.shape(ell(12, 12, o.hole || 3, o.hole || 3), 'black', 'flat');
  if (o.small) { for (let a = 0; a < 6; a++) c.shape(path([[19 + 2 * Math.cos(a), 19 + 2 * Math.sin(a)], [19 + 3.4 * Math.cos(a), 19 + 3.4 * Math.sin(a)]], 1.4), 'gold', 'orb'); c.shape(ell(19, 19, 2.4, 2.4), 'gold', 'orb'); }
};
const gear = build(gearFn, [opt('Zahnrad', 'Stahl', {}), opt('Gold', 'Goldenes Rad', { col: 'gold' }), opt('Mit Ring', 'Mit Rille', { ring: 1 }), opt('Zwölf Zähne', 'Fein', { n: 12, tooth: 2.2 }), opt('Sechs Zähne', 'Grob', { n: 6, tooth: 4 }), opt('Kupfer', 'Kupfer', { col: 'copper', ring: 1 }), opt('Doppel', 'Mit zweitem Rad', { r: 6.6, small: 1 }), opt('Blau', 'Blau', { col: 'blue' }), opt('Eisen', 'Dunkel', { col: 'iron', ring: 1, hole: 3.6 }), opt('Groß', 'Dickes Loch', { hole: 4.6, col: 'steel' })]);

// sparkles
const sparkles = [
  ['Drei Funken', 'Groß, mittel, klein', (c) => { c.shape(star(9, 13, 8, 2, 4), 'bolt', 'orb'); c.shape(star(19, 6, 4.4, 1.2, 4), 'bolt', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'bolt', 'orb'); }],
  ['Weiß', 'Silbern', (c) => { c.shape(star(9, 13, 8, 2, 4), 'face', 'orb'); c.shape(star(19, 6, 4.4, 1.2, 4), 'face', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'ice', 'orb'); }],
  ['Sterne', 'Fünfzackig', (c) => { c.shape(star(9, 14, 7, 3, 5), 'bolt', 'orb'); c.shape(star(19, 6, 4, 1.8, 5), 'bolt', 'orb'); c.shape(star(18, 18, 3, 1.4, 5), 'goldl', 'orb'); }],
  ['Blau', 'Eiskristalle', (c) => { c.shape(star(9, 13, 8, 2, 4), 'cyan', 'orb'); c.shape(star(19, 6, 4.4, 1.2, 4), 'blue', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'cyan', 'orb'); }],
  ['Rosa', 'Zauber', (c) => { c.shape(star(9, 13, 8, 2, 4), 'pink', 'orb'); c.shape(star(19, 6, 4.4, 1.2, 4), 'purple', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'pink', 'orb'); }],
  ['Viele kleine', 'Funkenregen', (c) => { for (const [x, y, s] of [[5, 5, 3], [14, 4, 2.4], [20, 9, 3], [8, 12, 2.4], [16, 15, 3.4], [4, 19, 2.8], [12, 21, 2]]) c.shape(star(x, y, s, 0.8, 4), 'bolt', 'orb'); }],
  ['Mit Herz', 'Funke und Herz', (c) => { c.shape(star(9, 13, 8, 2, 4), 'bolt', 'orb'); c.shape(heart(19, 7, 3.4), 'pink', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'bolt', 'orb'); }],
  ['Im Kreis', 'Funken am Ring', (c) => { c.shape(ring(12, 12, 9, 8), 'gold', 'flat'); c.shape(star(12, 12, 6.6, 1.6, 4), 'bolt', 'orb'); c.shape(star(20, 4, 3, 0.8, 4), 'face', 'flat'); }],
  ['Kreuzfunke', 'Ein großer', (c) => { c.shape(star(12, 12, 11, 1.6, 4), 'bolt', 'orb'); c.shape(star(12, 12, 4, 1.5, 4), 'face', 'flat'); }],
  ['Grün', 'Natur', (c) => { c.shape(star(9, 13, 8, 2, 4), 'leaf', 'orb'); c.shape(star(19, 6, 4.4, 1.2, 4), 'bolt', 'orb'); c.shape(star(18, 18, 3, 0.9, 4), 'leaf', 'orb'); }],
];

// trash
const trashFn = (c, o) => {
  const col = o.col || 'steel';
  if (o.kind === 'bag') { c.shape(ell(12, 15, 8, 7), col, 'orb'); c.shape(poly([[8, 9], [16, 9], [14, 4], [10, 4]]), col, 'diag'); c.shape(rect(9.4, 8, 14.6, 9.6), 'iron', 'flat'); return; }
  if (o.kind === 'barrel') { c.shape(ell(12, 12, 8, 10), col, 'orb'); c.shape(rect(4, 6, 20, 7.4), 'iron', 'flat'); c.shape(rect(4, 16, 20, 17.4), 'iron', 'flat'); c.shape(ell(12, 3, 7, 1.8), 'iron', 'orb'); return; }
  c.shape(poly([[5, 7], [19, 7], [17, 22], [7, 22]]), col, 'diag'); c.shape(rect(3, 4, 21, 7), o.lid || 'iron', 'vert'); c.shape(rect(9, 2, 15, 4), o.lid || 'iron', 'diag'); for (const x of [9, 12, 15]) c.line(x, 10, x, 19, 'black', 1);
};
const trash = build(trashFn, [opt('Mülleimer', 'Stahl', {}), opt('Grün', 'Grüne Tonne', { col: 'green', lid: 'forest' }), opt('Sack', 'Müllsack', { kind: 'bag', col: 'iron' }), opt('Fass', 'Tonne', { kind: 'barrel' }), opt('Blau', 'Blau', { col: 'blue', lid: 'navy' }), opt('Rot', 'Rot', { col: 'red', lid: 'ruby' }), opt('Gelb', 'Gelb', { col: 'bolt', lid: 'orange' }), opt('Sack Grün', 'Grüner Sack', { kind: 'bag', col: 'leaf' }), opt('Fass Rot', 'Rotes Fass', { kind: 'barrel', col: 'red' }), opt('Holz', 'Holz', { col: 'wood', lid: 'bark' })]);

// vase
const vaseFn = (c, o) => {
  const col = o.col || 'clay';
  const sh = o.kind === 'tall' ? poly([[9, 2], [15, 2], [14, 8], [18, 14], [16, 22], [8, 22], [6, 14], [10, 8]]) : o.kind === 'amph' ? either(ell(12, 14, 7, 8), rect(10, 2, 14, 7)) : either(ell(12, 14, 8, 8), rect(9, 3, 15, 8));
  c.shape(sh, col, 'orb'); c.shape(ell(12, 3, 3.6, 1.4), col, 'orb', -0.1); if (o.band) c.shape(rect(6, 13, 18, 15), o.band, 'flat'); if (o.handles) { c.shape(ring(5, 11, 3, 1.5), col, 'orb'); c.shape(ring(19, 11, 3, 1.5), col, 'orb'); } if (o.flower) { c.shape(path([[12, 3], [10, -1]], 0.8), 'leaf', 'flat'); c.shape(ell(10, 1, 2, 2), 'red', 'orb'); }
};
const vase = build(vaseFn, [opt('Vase', 'Ton', {}), opt('Mit Band', 'Verziert', { band: 'blue' }), opt('Amphore', 'Mit Henkeln', { kind: 'amph', handles: 1 }), opt('Hoch', 'Schlank', { kind: 'tall' }), opt('Weiß', 'Porzellan', { col: 'face', band: 'blue' }), opt('Blau', 'Blau', { col: 'blue', band: 'face' }), opt('Mit Blume', 'Blume drin', { flower: 1 }), opt('Gold', 'Goldvase', { col: 'gold', band: 'red' }), opt('Grün', 'Grün', { col: 'green', band: 'goldl' }), opt('Rot', 'Rot', { col: 'red', band: 'gold', handles: 1 })]);

// gift
const giftFn = (c, o) => {
  const col = o.col || 'red', rib = o.rib || 'bolt';
  c.shape(rect(3, 10, 21, 22), col, 'diag'); c.shape(rect(2, 7, 22, 11), col, 'vert', -0.1); c.shape(rect(10.4, 7, 13.6, 22), rib, 'diag'); if (o.cross !== false) c.shape(rect(3, 14.4, 21, 17), rib, 'vert');
  if (o.bow !== false) { c.shape(ell(8.6, 5, 3.6, 2.8), rib, 'orb'); c.shape(ell(15.4, 5, 3.6, 2.8), rib, 'orb'); c.shape(ell(12, 6, 1.6, 1.6), rib, 'orb', 0.2); }
  if (o.stars) { c.px(6, 12, 'face', 4); c.px(18, 19, 'face', 4); c.px(7, 20, 'face', 4); }
};
const gift = build(giftFn, [opt('Geschenk', 'Rot mit Schleife', {}), opt('Blau', 'Blau', { col: 'blue', rib: 'face' }), opt('Grün', 'Grün', { col: 'green', rib: 'red' }), opt('Violett', 'Lila', { col: 'purple', rib: 'bolt' }), opt('Gold', 'Gold', { col: 'gold', rib: 'red' }), opt('Ohne Querband', 'Nur senkrecht', { cross: false }), opt('Weiß', 'Weiß', { col: 'face', rib: 'red' }), opt('Mit Punkten', 'Sternchen', { stars: 1, col: 'cyan', rib: 'red' }), opt('Rosa', 'Rosa', { col: 'pink', rib: 'purple' }), opt('Ohne Schleife', 'Schlicht', { bow: false, col: 'orange', rib: 'face' })]);

// basket
const basketFn = (c, o) => {
  const col = o.col || 'wood';
  c.shape(poly([[3, 10], [21, 10], [18, 21], [6, 21]]), col, 'diag'); c.shape(rect(2, 9, 22, 11.4), 'woodl', 'vert'); for (const y of [13.4, 16.6, 19]) c.line(4.4, y, 19.6, y, 'bark', 1); for (const x of [8, 12, 16]) c.line(x, 11, x - 0.5, 21, 'bark', 1);
  if (o.handle !== false) c.shape(ring(12, 10, 7.6, 6.2), 'woodl', 'flat'); if (o.fill === 'apples') { c.shape(ell(8, 8, 3, 2.8), 'apple', 'orb'); c.shape(ell(15, 8, 3, 2.8), 'apple', 'orb'); } if (o.fill === 'bread') { c.shape(ell(9, 8, 4, 2.6), 'bread', 'orb'); c.shape(ell(15, 8, 3, 2.6), 'bread', 'orb'); } if (o.fill === 'flowers') for (const [x, col2] of [[7, 'red'], [12, 'bolt'], [17, 'pink']]) c.shape(ell(x, 7, 2.2, 2.2), col2, 'orb'); if (o.fill === 'fish') { c.shape(ell(9, 8, 4, 2), 'fish', 'orb'); c.shape(ell(15, 8, 3, 2), 'fish', 'orb'); }
};
const basket = build(basketFn, [opt('Korb', 'Mit Henkel', {}), opt('Äpfel', 'Voll Äpfel', { fill: 'apples' }), opt('Brot', 'Voll Brot', { fill: 'bread' }), opt('Blumen', 'Blumenkorb', { fill: 'flowers' }), opt('Fische', 'Fangkorb', { fill: 'fish' }), opt('Ohne Henkel', 'Schale', { handle: false, fill: 'apples' }), opt('Hell', 'Helles Weidengeflecht', { col: 'sand' }), opt('Dunkel', 'Dunkles Holz', { col: 'bark', fill: 'bread' }), opt('Rot', 'Rot', { col: 'red', fill: 'flowers' }), opt('Grün', 'Grün', { col: 'green', fill: 'apples' })]);

// flower
const flowerFn = (c, o) => {
  const pet = o.pet || 'pink', n = o.n || 6;
  if (o.kind === 'tulip') { c.shape(rect(11, 12, 13, 22), 'leaf', 'diag'); c.shape(poly([[7, 4], [9, 8], [12, 5], [15, 8], [17, 4], [17, 12], [12, 15], [7, 12]]), pet, 'orb'); c.shape(poly([[5, 17], [11, 18], [11, 21]]), 'leaf', 'diag'); return; }
  c.shape(rect(11, 13, 13, 23), 'leaf', 'diag'); c.shape(poly([[13, 18], [20, 14], [19, 20]]), 'leaf', 'diag');
  for (let i = 0; i < n; i++) { const t = (i * 2 * Math.PI) / n; c.shape(ell(12 + 5 * Math.cos(t), 9 + 5 * Math.sin(t), 3, 3), pet, 'orb'); }
  c.shape(ell(12, 9, 3, 3), o.mid || 'bolt', 'orb');
};
const flower = build(flowerFn, [opt('Blume', 'Rosa', {}), opt('Rot', 'Rot', { pet: 'red' }), opt('Gelb', 'Gelb', { pet: 'bolt', mid: 'orange' }), opt('Blau', 'Blau', { pet: 'blue', mid: 'face' }), opt('Weiß', 'Gänseblümchen', { pet: 'face', n: 8 }), opt('Violett', 'Lila', { pet: 'purple', n: 5 }), opt('Tulpe', 'Rote Tulpe', { kind: 'tulip', pet: 'red' }), opt('Tulpe gelb', 'Gelbe Tulpe', { kind: 'tulip', pet: 'bolt' }), opt('Orange', 'Orange', { pet: 'orange', n: 8, mid: 'bark' }), opt('Tulpe rosa', 'Rosa Tulpe', { kind: 'tulip', pet: 'pink' })]);

// herb / sprout / grass
const herbFn = (c, o) => {
  const col = o.col || 'leaf';
  if (o.kind === 'sprout') { c.shape(rect(11, 10, 13, 21), col, 'diag'); c.shape(poly([[12, 13], [3, 9], [5, 4], [12, 9]]), col, 'diag'); c.shape(poly([[12, 10], [21, 7], [20, 2], [12, 6]]), col, 'diag', 0.15); c.shape(ell(12, 21.4, 5, 1.6), 'bark', 'vert'); return; }
  if (o.kind === 'grass') { for (const [x, h, k] of [[6, 12, -1], [10, 18, 0], [14, 20, 0.5], [18, 14, 1]]) c.shape(poly([[x - 1.4, 22], [x + k * 2, 22 - h], [x + 1.4, 22]]), col, 'diag'); return; }
  c.shape(rect(11, 8, 13, 22), 'forest', 'diag'); for (const [x, y, s] of [[7, 8, -1], [17, 8, 1], [6, 14, -1], [18, 14, 1], [12, 3, 0]]) c.shape(ell(12 + s * 4.6, y, 3.6, 2.4), col, 'orb');
};
const herb = build(herbFn, [opt('Kraut', 'Grün', {}), opt('Blaugrün', 'Salbei', { col: 'cyan' }), opt('Hell', 'Hellgrün', { col: 'leaf' }), opt('Violett', 'Lavendel', { col: 'purple' }), opt('Rot', 'Rotblatt', { col: 'red' }), opt('Gelb', 'Trockenkraut', { col: 'bolt' }), opt('Dunkel', 'Dunkelgrün', { col: 'forest' }), opt('Orange', 'Herbst', { col: 'orange' }), opt('Mint', 'Minze', { col: 'moss' }), opt('Blau', 'Blau', { col: 'blue' })]);
const sprout = build((c, o) => herbFn(c, { ...o, kind: 'sprout' }), [opt('Setzling', 'Grün', {}), opt('Hell', 'Hellgrün', { col: 'leaf' }), opt('Dunkel', 'Dunkelgrün', { col: 'forest' }), opt('Gelb', 'Gelb', { col: 'bolt' }), opt('Blau', 'Blau', { col: 'cyan' }), opt('Moos', 'Moosgrün', { col: 'moss' }), opt('Orange', 'Orange', { col: 'orange' }), opt('Rosa', 'Rosa', { col: 'pink' }), opt('Violett', 'Lila', { col: 'purple' }), opt('Rot', 'Rot', { col: 'red' })]);
const grass = build((c, o) => herbFn(c, { ...o, kind: 'grass' }), [opt('Gras', 'Grün', {}), opt('Hell', 'Hellgrün', { col: 'leaf' }), opt('Dunkel', 'Dunkelgrün', { col: 'forest' }), opt('Gelb', 'Trocken', { col: 'bread' }), opt('Blau', 'Blaugras', { col: 'cyan' }), opt('Moos', 'Moos', { col: 'moss' }), opt('Orange', 'Herbst', { col: 'orange' }), opt('Rot', 'Rot', { col: 'red' }), opt('Violett', 'Lila', { col: 'purple' }), opt('Sand', 'Dünengras', { col: 'sand' })]);

// tree
const treeFn = (c, o) => {
  const col = o.col || 'moss';
  if (o.kind === 'pine') { c.shape(rect(11, 17, 13, 22), 'bark', 'diag'); for (const [y, w] of [[15, 7], [10, 6], [5, 4.6]]) c.shape(poly([[12 - w, y + 5], [12, y - 3], [12 + w, y + 5]]), col, 'diag'); return; }
  if (o.kind === 'palm') { c.shape(path([[11, 22], [12, 12], [14, 8]], 2), 'bark', 'diag'); for (const [dx, dy] of [[-8, 2], [-6, -3], [8, 2], [6, -3], [0, -5]]) c.shape(path([[14, 8], [14 + dx, 8 + dy]], 2.6), col, 'orb'); return; }
  if (o.kind === 'dead') { c.shape(path([[12, 22], [12, 10]], 2.6), 'bark', 'diag'); c.shape(path([[12, 14], [6, 8]], 1.6), 'bark', 'flat'); c.shape(path([[12, 11], [18, 5]], 1.6), 'bark', 'flat'); c.shape(path([[12, 9], [9, 3]], 1.4), 'bark', 'flat'); return; }
  if (o.kind === 'birch') { c.shape(rect(10.6, 12, 13.4, 22), 'face', 'diag'); for (const y of [14, 17, 20]) c.line(11, y, 13, y, 'black', 1); c.shape(ell(12, 8, 7, 6.6), col, 'orb'); return; }
  c.shape(rect(10.6, 13, 13.4, 22), 'bark', 'diag'); c.shape(ell(12, 9, 8.4, 7), col, 'orb'); c.shape(ell(7, 12, 4.6, 3.6), col, 'orb', -0.02); c.shape(ell(17, 12, 4.6, 3.6), col, 'orb', 0.04); if (o.fruit) for (const [x, y] of [[8, 8], [15, 6], [16, 12], [11, 11]]) c.shape(ell(x, y, 1.2, 1.2), o.fruit, 'orb');
};
const tree = build(treeFn, [opt('Laubbaum', 'Rund', {}), opt('Tanne', 'Nadelbaum', { kind: 'pine', col: 'forest' }), opt('Palme', 'Tropisch', { kind: 'palm', col: 'leaf' }), opt('Apfelbaum', 'Mit Früchten', { fruit: 'red' }), opt('Birke', 'Weiße Rinde', { kind: 'birch', col: 'leaf' }), opt('Herbst', 'Orange Krone', { col: 'orange', fruit: 'red' }), opt('Kahl', 'Abgestorben', { kind: 'dead' }), opt('Dunkel', 'Dunkler Laubbaum', { col: 'forest' }), opt('Schnee-Tanne', 'Blaugrün', { kind: 'pine', col: 'cyan' }), opt('Kirschblüte', 'Rosa Krone', { col: 'pink' })]);

// ice
const iceFn = (c, o) => {
  const col = o.col || 'cyan';
  if (o.kind === 'cubes') { c.shape(rect(2, 11, 12, 21), col, 'diag'); c.shape(rect(11, 5, 21, 15), col, 'diag', 0.1); c.shape(rect(3, 12, 6, 14), 'ice', 'flat'); c.shape(rect(12, 6, 15, 8), 'ice', 'flat'); return; }
  if (o.kind === 'shard') { c.shape(poly([[12, 1], [19, 11], [15, 22], [8, 22], [5, 11]]), col, 'diag'); c.shape(poly([[12, 1], [19, 11], [12, 11]]), 'ice', 'vert', -0.1); c.line(12, 11, 11, 21, 'ice', 4); return; }
  c.shape(poly([[4, 8], [12, 4], [20, 8], [12, 12]]), 'ice', 'vert', -0.1); c.shape(poly([[4, 8], [12, 12], [12, 21], [4, 17]]), col, 'diag'); c.shape(poly([[12, 12], [20, 8], [20, 17], [12, 21]]), col, 'diag', 0.28); if (o.drip) c.shape(ell(19, 21, 1.4, 1.8), 'cyan', 'orb');
};
const ice = build(iceFn, [opt('Eiswürfel', 'Würfel', {}), opt('Zwei Würfel', 'Gestapelt', { kind: 'cubes' }), opt('Splitter', 'Spitz', { kind: 'shard' }), opt('Tropfend', 'Schmilzt', { drip: 1 }), opt('Blau', 'Tiefblau', { col: 'blue' }), opt('Zwei Blau', 'Blaue Würfel', { kind: 'cubes', col: 'blue' }), opt('Splitter Blau', 'Blauer Splitter', { kind: 'shard', col: 'blue' }), opt('Hell', 'Weißes Eis', { col: 'ice' }), opt('Türkis', 'Türkis tropfend', { col: 'cyan', drip: 1 }), opt('Violett', 'Violettes Eis', { col: 'purple' })]);

// meat
const meatFn = (c, o) => {
  const col = o.col || 'meat';
  if (o.kind === 'steak') { c.shape(poly([[3, 12], [6, 5], [14, 3], [21, 8], [20, 17], [12, 21], [5, 19]]), col, 'orb'); c.shape(ell(14, 10, 3.4, 2.6), 'fat', 'orb'); c.shape(ell(8, 15, 2, 1.6), 'fat', 'orb'); return; }
  if (o.kind === 'sausage') { c.shape(path([[4, 16], [12, 8], [20, 8]], 5.6), col, 'orb'); c.shape(path([[4, 16], [12, 8], [20, 8]], 1), 'fat', 'flat', -0.3); return; }
  if (o.kind === 'ribs') { c.shape(rect(3, 5, 21, 19), col, 'diag'); for (const x of [7, 12, 17]) c.shape(rect(x, 4, x + 2, 20), 'face', 'diag'); return; }
  c.shape(ell(9, 11, 7, 7), col, 'orb'); c.shape(ell(7, 8, 3.4, 2.2), 'fat', 'orb'); c.shape(thick(14, 15, 20, 21, 3), 'face', 'diag'); c.shape(ell(21, 21.4, 2, 2), 'face', 'orb');
};
const meat = build(meatFn, [opt('Keule', 'Mit Knochen', {}), opt('Steak', 'Gebraten', { kind: 'steak' }), opt('Wurst', 'Bratwurst', { kind: 'sausage', col: 'clay' }), opt('Rippchen', 'Mit Knochen', { kind: 'ribs', col: 'clay' }), opt('Keule braun', 'Gegrillt', { col: 'wood' }), opt('Steak braun', 'Durch', { kind: 'steak', col: 'wood' }), opt('Wurst rot', 'Salami', { kind: 'sausage', col: 'red' }), opt('Rippchen rot', 'Rot', { kind: 'ribs', col: 'meat' }), opt('Keule hell', 'Hähnchen', { col: 'bread' }), opt('Steak roh', 'Roh', { kind: 'steak', col: 'ruby' })]);

// wine
const wineFn = (c, o) => {
  const col = o.col || 'red', glass = o.glass || 'ice';
  if (o.kind === 'glass') { c.shape(both(ell(12, 8, 6, 7), rect(0, 0, 24, 11)), glass, 'orb'); c.shape(both(ell(12, 8, 6, 7), rect(0, 7, 24, 11)), col, 'vert'); c.shape(rect(11, 14, 13, 20), glass, 'diag'); c.shape(rect(7, 20, 17, 22), glass, 'vert'); return; }
  if (o.kind === 'barrel') { c.shape(ell(12, 12, 8, 10), 'wood', 'orb'); c.shape(rect(4, 6, 20, 7.4), 'iron', 'flat'); c.shape(rect(4, 16, 20, 17.4), 'iron', 'flat'); c.shape(rect(11, 11, 13, 15), col, 'diag'); return; }
  if (o.kind === 'goblet') { c.shape(poly([[5, 4], [19, 4], [17, 12], [12, 15], [7, 12]]), 'gold', 'diag'); c.shape(rect(4, 4, 20, 6.4), col, 'vert'); c.shape(rect(11, 14, 13, 19), 'gold', 'diag'); c.shape(rect(7, 19, 17, 22), 'gold', 'vert'); return; }
  c.shape(rect(9, 1, 15, 4), 'leatherd', 'vert'); c.shape(rect(10, 4, 14, 9), 'forest', 'diag'); c.shape(poly([[10, 9], [14, 9], [17, 13], [17, 22], [7, 22], [7, 13]]), 'forest', 'diag'); c.shape(rect(7, 14, 17, 19), 'face', 'flat'); c.shape(rect(9, 15, 15, 16), col, 'flat');
};
const wine = build(wineFn, [opt('Weinflasche', 'Grün mit Etikett', {}), opt('Weinglas', 'Rotwein', { kind: 'glass' }), opt('Weinfass', 'Fass', { kind: 'barrel' }), opt('Kelch', 'Goldkelch', { kind: 'goblet' }), opt('Flasche weiß', 'Weißwein', { col: 'bolt' }), opt('Glas weiß', 'Weißwein', { kind: 'glass', col: 'bolt' }), opt('Kelch blau', 'Blauer Trank', { kind: 'goblet', col: 'blue' }), opt('Glas rosé', 'Rosé', { kind: 'glass', col: 'pink' }), opt('Flasche blau', 'Blauer Wein', { col: 'blue' }), opt('Fass grün', 'Grüner Zapfen', { kind: 'barrel', col: 'leaf' })]);

// chili
const chiliFn = (c, o) => {
  const col = o.col || 'red';
  if (o.kind === 'two') { c.shape(path([[3, 21], [9, 14], [14, 7]], 4), col, 'orb'); c.shape(path([[8, 21], [14, 15], [20, 9]], 4), o.col2 || 'green', 'orb'); c.shape(rect(13, 3, 16, 7), 'leaf', 'diag'); c.shape(rect(19, 5, 22, 9), 'leaf', 'diag'); return; }
  if (o.kind === 'round') { c.shape(ell(12, 14, 7, 7), col, 'orb'); c.shape(rect(10.6, 3, 13.4, 8), 'leaf', 'diag'); c.shape(poly([[8, 8], [12, 6], [16, 8], [12, 10]]), 'leaf', 'diag'); return; }
  c.shape(path([[4, 20], [10, 13], [17, 6]], 5), col, 'orb'); c.shape(rect(16, 2, 21, 7), 'leaf', 'diag'); c.shape(path([[18, 3], [22, 1]], 1.6), 'leaf', 'flat'); c.px(7, 15, 'face', 4);
};
const chili = build(chiliFn, [opt('Chili', 'Rot', {}), opt('Grün', 'Grüne Schote', { col: 'green' }), opt('Orange', 'Orange', { col: 'orange' }), opt('Paar', 'Rot und grün', { kind: 'two' }), opt('Rund', 'Paprika', { kind: 'round' }), opt('Rund gelb', 'Gelbe Paprika', { kind: 'round', col: 'bolt' }), opt('Violett', 'Lila', { col: 'purple' }), opt('Paar gelb', 'Gelb und orange', { kind: 'two', col: 'bolt', col2: 'orange' }), opt('Rund grün', 'Grüne Paprika', { kind: 'round', col: 'green' }), opt('Dunkel', 'Dunkelrot', { col: 'ruby' })]);

// salt
const saltFn = (c, o) => {
  const col = o.col || 'face';
  if (o.kind === 'pile') { c.shape(both(ell(12, 22, 10, 13), rect(0, 0, 24, 22)), col, 'vert'); for (const [x, y] of [[8, 16], [14, 13], [16, 18], [11, 19]]) c.px(x, y, 'steel', 2); return; }
  if (o.kind === 'sack') { c.shape(ell(12, 15, 8, 7), 'leather', 'orb'); c.shape(ell(12, 8, 5, 3), col, 'orb'); c.shape(rect(8, 10, 15, 11.6), 'red', 'flat'); return; }
  if (o.kind === 'crystal') { c.shape(poly([[12, 2], [19, 8], [17, 21], [7, 21], [5, 8]]), col, 'diag'); c.shape(poly([[12, 2], [19, 8], [12, 9], [5, 8]]), 'ice', 'vert', -0.2); return; }
  c.shape(rect(6, 8, 18, 21), 'ice', 'diag'); c.shape(rect(6, 8, 18, 14), col, 'vert', 0.1); c.shape(both(ell(12, 6.4, 6.4, 3), rect(0, 0, 24, 8)), 'steel', 'orb'); for (const x of [10, 12, 14]) c.px(x, 5, 'black', 1);
};
const salt = build(saltFn, [opt('Salzstreuer', 'Klassisch', {}), opt('Häufchen', 'Salzhaufen', { kind: 'pile' }), opt('Salzsack', 'Sack', { kind: 'sack' }), opt('Kristall', 'Salzkristall', { kind: 'crystal' }), opt('Rosa Streuer', 'Himalaya', { col: 'pink' }), opt('Rosa Häufchen', 'Rosa Salz', { kind: 'pile', col: 'pink' }), opt('Rosa Sack', 'Rosa Sack', { kind: 'sack', col: 'pink' }), opt('Rosa Kristall', 'Rosa Kristall', { kind: 'crystal', col: 'pink' }), opt('Grauer Streuer', 'Meersalz', { col: 'steel' }), opt('Blauer Kristall', 'Blau', { kind: 'crystal', col: 'cyan' })]);

// coffee / tea
const cupFn = (c, o) => {
  const col = o.col || 'face', liq = o.liq || 'bark';
  if (o.kind === 'pot') { c.shape(ell(11, 14, 7, 6.4), col, 'orb'); c.shape(rect(8, 6, 14, 9), col, 'diag'); c.shape(poly([[17, 11], [22, 8], [22, 10], [18, 15]]), col, 'diag'); c.shape(ring(4, 14, 3, 1.6), col, 'orb'); c.shape(ell(11, 6, 2, 1.4), 'gold', 'orb'); return; }
  if (o.kind === 'glass') { c.shape(poly([[6, 5], [18, 5], [16, 21], [8, 21]]), 'ice', 'diag'); c.shape(poly([[7, 10], [17, 10], [15.6, 20], [8.4, 20]]), liq, 'diag'); return; }
  c.shape(poly([[4, 8], [18, 8], [16, 19], [6, 19]]), col, 'diag'); c.shape(ell(11, 8, 7, 2), liq, 'orb'); c.shape(ring(19, 12, 3.4, 1.8), col, 'orb'); c.shape(ell(11, 21, 9, 1.6), col, 'vert', 0.1); if (o.steam) { c.shape(path([[8, 5], [9, 2]], 0.9), 'face', 'flat'); c.shape(path([[13, 5], [14, 1]], 0.9), 'face', 'flat'); }
};
const coffee = build(cupFn, [opt('Tasse', 'Kaffee mit Dampf', { steam: 1 }), opt('Blau', 'Blaue Tasse', { col: 'blue', steam: 1 }), opt('Rot', 'Rote Tasse', { col: 'red' }), opt('Kanne', 'Kaffeekanne', { kind: 'pot', col: 'iron' }), opt('Glas', 'Kaffeeglas', { kind: 'glass' }), opt('Grün', 'Grüne Tasse', { col: 'green', steam: 1 }), opt('Kanne Rot', 'Rote Kanne', { kind: 'pot', col: 'red' }), opt('Violett', 'Lila Tasse', { col: 'purple' }), opt('Gold', 'Goldtasse', { col: 'gold', steam: 1 }), opt('Kanne Silber', 'Silberkanne', { kind: 'pot', col: 'steel' })]);
const tea = build((c, o) => cupFn(c, { ...o, liq: o.liq || 'orange' }), [opt('Teetasse', 'Orange Tee', { steam: 1 }), opt('Grüner Tee', 'Grün', { liq: 'leaf', steam: 1 }), opt('Kanne', 'Teekanne', { kind: 'pot', col: 'blue' }), opt('Glas', 'Teeglas', { kind: 'glass' }), opt('Rosa Tasse', 'Rosa', { col: 'pink', steam: 1 }), opt('Kanne Weiß', 'Porzellankanne', { kind: 'pot', col: 'face' }), opt('Glas Grün', 'Grüntee im Glas', { kind: 'glass', liq: 'leaf' }), opt('Blaue Tasse', 'Blau', { col: 'blue', liq: 'red' }), opt('Kanne Grün', 'Grüne Kanne', { kind: 'pot', col: 'green' }), opt('Goldtasse', 'Gold', { col: 'gold', steam: 1 })]);

// nut (hardware) / brick / frame / ball / crane / goal
const nutFn = (c, o) => {
  const col = o.col || 'steel';
  if (o.kind === 'bolt') { c.shape(poly([[6, 2], [18, 2], [21, 7], [18, 11], [6, 11], [3, 7]]), col, 'diag'); c.shape(rect(9, 11, 15, 22), col, 'diag'); for (const y of [13, 16, 19]) c.line(9, y, 14, y, 'iron', 1); return; }
  if (o.kind === 'screw') { c.shape(ell(12, 4, 6, 2.4), col, 'orb'); c.shape(poly([[9, 5], [15, 5], [13, 22], [11, 22]]), col, 'diag'); for (const y of [8, 11, 14, 17]) c.line(10, y, 14, y + 1, 'iron', 1); return; }
  if (o.kind === 'washer') { c.shape(ring(12, 12, 10, 4), col, 'orb'); return; }
  c.shape(poly([[6, 3], [18, 3], [22, 12], [18, 21], [6, 21], [2, 12]]), col, 'diag'); c.shape(ell(12, 12, 4.4, 4.4), 'black', 'flat'); c.shape(ring(12, 12, 4.4, 3.2), 'iron', 'flat');
};
const nut = build(nutFn, [opt('Mutter', 'Sechskant', {}), opt('Schraube', 'Sechskantschraube', { kind: 'bolt' }), opt('Holzschraube', 'Rund', { kind: 'screw' }), opt('Scheibe', 'Unterlegscheibe', { kind: 'washer' }), opt('Messing', 'Messingmutter', { col: 'brass' }), opt('Kupfer', 'Kupferschraube', { kind: 'bolt', col: 'copper' }), opt('Gold', 'Goldschraube', { kind: 'screw', col: 'gold' }), opt('Eisen', 'Dunkle Mutter', { col: 'iron' }), opt('Blau', 'Blaue Scheibe', { kind: 'washer', col: 'blue' }), opt('Rot', 'Rote Schraube', { kind: 'bolt', col: 'red' })]);

const brickFn = (c, o) => {
  const col = o.col || 'clay';
  if (o.kind === 'one') { c.shape(poly([[3, 10], [12, 5], [21, 10], [12, 15]]), col, 'vert', -0.15); c.shape(poly([[3, 10], [12, 15], [12, 21], [3, 16]]), col, 'diag'); c.shape(poly([[12, 15], [21, 10], [21, 16], [12, 21]]), col, 'diag', 0.28); return; }
  if (o.kind === 'stack') { for (const [x, y] of [[2, 15], [12, 15], [7, 8], [2, 1.4]]) c.shape(rect(x, y, x + 9, y + 6), col, 'diag'); return; }
  c.shape(rect(2, 5, 22, 19), col, 'diag'); for (const y of [9.6, 14.2]) c.line(2, y, 22, y, 'iron', 1); for (const [x, y0] of [[8, 5], [15, 5], [5, 10], [12, 10], [19, 10], [8, 15], [15, 15]]) c.line(x, y0, x, y0 + 4, 'iron', 1);
};
const brick = build(brickFn, [opt('Mauer', 'Rote Ziegel', {}), opt('Ein Ziegel', 'Isometrisch', { kind: 'one' }), opt('Stapel', 'Gestapelt', { kind: 'stack' }), opt('Gelb', 'Gelbe Ziegel', { col: 'sand' }), opt('Grau', 'Graue Steine', { col: 'stone' }), opt('Ein gelber', 'Gelb', { kind: 'one', col: 'sand' }), opt('Stapel grau', 'Graue Steine', { kind: 'stack', col: 'stone' }), opt('Dunkel', 'Klinker', { col: 'brown' }), opt('Ein Grauer', 'Grau', { kind: 'one', col: 'stone2' }), opt('Orange', 'Orange', { col: 'orange', kind: 'stack' })]);

const frameFn = (c, o) => {
  const col = o.col || 'wood';
  c.shape(rect(2, 2, 22, 22), col, 'diag'); c.shape(rect(5, 5, 19, 19), o.inner || 'face', 'vert', 0.1); c.shape(rect(2, 2, 22, 4), col, 'vert', -0.2);
  if (o.pic) { c.shape(ell(16, 9, 2, 2), 'bolt', 'orb'); c.shape(poly([[5, 19], [10, 11], [14, 16], [17, 13], [19, 19]]), 'green', 'diag'); } if (o.gem) for (const [x, y] of [[3, 3], [21, 3], [3, 21], [21, 21]]) c.px(x, y, 'goldl', 4);
};
const frame = build(frameFn, [opt('Rahmen', 'Holz, leer', {}), opt('Mit Bild', 'Landschaft', { pic: 1 }), opt('Gold', 'Goldrahmen', { col: 'gold', gem: 1 }), opt('Silber', 'Silberrahmen', { col: 'steel' }), opt('Dunkel', 'Eisenrahmen', { col: 'iron', pic: 1 }), opt('Rot', 'Roter Rahmen', { col: 'red' }), opt('Blau', 'Blau mit Bild', { col: 'blue', pic: 1 }), opt('Grün', 'Grün', { col: 'green' }), opt('Weiß', 'Weiß', { col: 'face', inner: 'ice' }), opt('Gold mit Bild', 'Gold, Landschaft', { col: 'gold', pic: 1 })]);

const ballFn = (c, o) => {
  const col = o.col || 'face';
  c.shape(ell(12, 12, 10, 10), col, 'orb');
  if (o.kind === 'soccer') { c.shape(poly([[12, 8], [15, 10], [14, 14], [10, 14], [9, 10]]), 'black', 'flat'); for (const [x, y] of [[12, 2], [3, 9], [21, 9], [6, 20], [18, 20]]) c.shape(ell(x, y, 2, 2), 'black', 'flat'); }
  if (o.kind === 'stripe') c.shape(path([[3, 8], [12, 11], [21, 8]], 1.6), o.line || 'red', 'flat');
  if (o.kind === 'beach') for (const t of [0, 1, 2, 3, 4, 5]) c.shape(both(ell(12, 12, 10, 10), poly([[12, 12], [12 + 14 * Math.cos(t * 1.047), 12 + 14 * Math.sin(t * 1.047)], [12 + 14 * Math.cos((t + 1) * 1.047), 12 + 14 * Math.sin((t + 1) * 1.047)]])), ['red', 'face', 'bolt', 'face', 'blue', 'face'][t], 'diag');
  if (o.kind === 'seam') c.shape(path([[4, 9], [8, 12], [4, 15]], 0.9), 'face', 'flat');
};
const ball = build(ballFn, [opt('Fußball', 'Schwarz-weiß', { kind: 'soccer' }), opt('Ball', 'Weiß', {}), opt('Rot', 'Roter Ball', { col: 'red' }), opt('Strandball', 'Bunt', { kind: 'beach' }), opt('Blau gestreift', 'Mit Streifen', { col: 'blue', kind: 'stripe', line: 'face' }), opt('Gelb', 'Gelber Ball', { col: 'bolt' }), opt('Orange', 'Orange mit Naht', { col: 'orange', kind: 'seam' }), opt('Grün', 'Grün', { col: 'green', kind: 'stripe', line: 'face' }), opt('Violett', 'Lila', { col: 'purple' }), opt('Schwarz', 'Schwarz', { col: 'black', kind: 'stripe', line: 'face' })]);

const craneFn = (c, o) => {
  const col = o.col || 'bolt';
  c.shape(rect(5, 6, 8, 22), col, 'diag'); c.shape(rect(2, 4, 22, 6.6), col, 'vert'); c.line(5, 7, 8, 21, 'iron', 1); c.line(8, 7, 5, 21, 'iron', 1); c.line(18, 7, 18, o.drop || 14, 'iron', 4);
  if (o.load === 'crate') c.shape(rect(15.6, 13, 20.6, 18), 'wood', 'diag'); else if (o.load === 'hook') c.shape(ring(18, 15, 2, 1), 'steel', 'flat'); else c.shape(rect(16, 14, 20, 17), 'iron', 'diag'); c.shape(rect(2, 20, 11, 22), 'iron', 'vert');
};
const crane = build(craneFn, [opt('Baukran', 'Gelb', {}), opt('Mit Kiste', 'Lastet', { load: 'crate' }), opt('Mit Haken', 'Haken', { load: 'hook' }), opt('Rot', 'Roter Kran', { col: 'red' }), opt('Blau', 'Blau', { col: 'blue', load: 'crate' }), opt('Orange', 'Orange', { col: 'orange' }), opt('Grün', 'Grün', { col: 'green', load: 'hook' }), opt('Grau', 'Stahl', { col: 'steel' }), opt('Violett', 'Lila', { col: 'purple', load: 'crate' }), opt('Weiß', 'Weiß', { col: 'face', load: 'hook' })]);

const goalFn = (c, o) => {
  const col = o.col || 'face';
  c.shape(minus(rect(2, 4, 22, 20), rect(4.4, 6.4, 19.6, 20)), col, 'diag'); for (const x of [8, 12, 16]) c.line(x, 7, x, 19, 'steel', 2); for (const y of [10, 14, 18]) c.line(5, y, 19, y, 'steel', 2); if (o.ball) c.shape(ell(15, 17, 2.8, 2.8), 'face', 'orb'); if (o.flag) { c.shape(rect(21, 2, 22, 8), 'iron', 'flat'); c.shape(poly([[22, 2], [24, 3.4], [22, 5]]), 'red', 'flat'); }
};
const goal = build(goalFn, [opt('Tor', 'Weißer Rahmen', {}), opt('Mit Ball', 'Treffer', { ball: 1 }), opt('Rot', 'Rotes Tor', { col: 'red' }), opt('Blau', 'Blaues Tor', { col: 'blue', ball: 1 }), opt('Gold', 'Gold', { col: 'gold' }), opt('Holz', 'Holztor', { col: 'wood' }), opt('Grün', 'Grün', { col: 'green', ball: 1 }), opt('Eisen', 'Eisen', { col: 'iron' }), opt('Violett', 'Lila', { col: 'purple', ball: 1 }), opt('Orange', 'Orange', { col: 'orange' })]);

const CONCEPTS = [
  { cat: 'Natur', key: 'gear', name: 'Zahnrad', designs: gear },
  { cat: 'Natur', key: 'sparkles', name: 'Funken', designs: sparkles },
  { cat: 'Natur', key: 'trash', name: 'Mülleimer', designs: trash },
  { cat: 'Natur', key: 'vase', name: 'Vase', designs: vase },
  { cat: 'Natur', key: 'gift', name: 'Geschenk', designs: gift },
  { cat: 'Natur', key: 'basket', name: 'Korb', designs: basket },
  { cat: 'Natur', key: 'flower', name: 'Blume', designs: flower },
  { cat: 'Natur', key: 'herb', name: 'Kraut', designs: herb },
  { cat: 'Natur', key: 'sprout', name: 'Setzling', designs: sprout },
  { cat: 'Natur', key: 'grass', name: 'Gras', designs: grass },
  { cat: 'Natur', key: 'tree', name: 'Baum', designs: tree },
  { cat: 'Natur', key: 'ice', name: 'Eis', designs: ice },
  { cat: 'Natur', key: 'meat', name: 'Fleisch', designs: meat },
  { cat: 'Natur', key: 'wine', name: 'Wein', designs: wine },
  { cat: 'Natur', key: 'chili', name: 'Chili', designs: chili },
  { cat: 'Natur', key: 'salt', name: 'Salz', designs: salt },
  { cat: 'Natur', key: 'coffee', name: 'Kaffee', designs: coffee },
  { cat: 'Natur', key: 'tea', name: 'Tee', designs: tea },
  { cat: 'Natur', key: 'nut', name: 'Schraubenmutter', designs: nut },
  { cat: 'Natur', key: 'brick', name: 'Ziegel', designs: brick },
  { cat: 'Natur', key: 'frame', name: 'Rahmen', designs: frame },
  { cat: 'Natur', key: 'ball', name: 'Ball', designs: ball },
  { cat: 'Natur', key: 'crane', name: 'Kran', designs: crane },
  { cat: 'Natur', key: 'goal', name: 'Tor (Ziel)', designs: goal },
];
module.exports = { CONCEPTS };
