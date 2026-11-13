// Batch 7: research leftovers + time / tasks / rewards. Builders with option tables keep each concept compact.
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sparkle = (c, x, y, s = 3) => c.shape(star(x, y, s, 0.9, 4), 'face', 'flat');
const D = (list) => list;
const opt = (name, desc, o) => [name, desc, o];
const build = (fn, rows) => rows.map(([n, d, o]) => [n, d, (c) => fn(c, o)]);

// ---------- stethoscope ----------
const stetFn = (c, o) => {
  c.shape(path([[6, 3], [6, 11], [12, 16]], 1.6), o.tube || 'iron', 'flat'); c.shape(path([[18, 3], [18, 11], [12, 16]], 1.6), o.tube || 'iron', 'flat'); c.shape(path([[12, 16], [12, 19]], 1.8), o.tube || 'iron', 'flat');
  c.shape(ell(6, 3, 1.8, 1.8), 'steel', 'orb'); c.shape(ell(18, 3, 1.8, 1.8), 'steel', 'orb'); c.shape(ell(12, 20.4, 3.2, 2.6), o.disc || 'steel', 'orb');
  if (o.heart) c.shape(heart(12, 8, 3.2), 'red', 'orb'); if (o.cross) { c.shape(rect(11, 4, 13, 12), 'red', 'flat'); c.shape(rect(8, 7, 16, 9), 'red', 'flat'); } if (o.pulse) c.shape(path([[3, 8], [8, 8], [10, 4], [13, 12], [15, 8], [21, 8]], 1), 'green', 'flat');
};
const stetho = build(stetFn, [opt('Klassisch', 'Grauer Schlauch', {}), opt('Rot', 'Roter Schlauch', { tube: 'red' }), opt('Mit Herz', 'Herz in der Mitte', { heart: 1 }), opt('Blau', 'Blauer Schlauch', { tube: 'blue' }), opt('Gold', 'Goldene Scheibe', { disc: 'gold' }), opt('Mit Kreuz', 'Heilkreuz', { cross: 1, tube: 'green' }), opt('Mit Puls', 'Herzlinie', { pulse: 1 }), opt('Schwarz', 'Dunkler Schlauch', { tube: 'black', disc: 'iron' }), opt('Grün', 'Grüner Schlauch', { tube: 'green', heart: 1 }), opt('Lila', 'Lila Schlauch', { tube: 'purple', disc: 'gold' })]);

// ---------- microscope ----------
const microFn = (c, o) => {
  c.shape(rect(4, 20, 20, 22), o.col || 'brass', 'vert'); c.shape(path([[16, 20], [18, 12], [14, 7]], 2.2), o.col || 'brass', 'diag'); c.shape(thick(8, 3, 13, 14, 4), o.tube || 'iron', 'diag'); c.shape(rect(7, 14, 15, 16), 'steel', 'vert'); c.shape(rect(4, 16.6, 14, 18), 'iron', 'vert'); c.shape(rect(6, 1, 10, 3), 'steel', 'diag');
  if (o.sparkle) sparkle(c, 5, 8, 3); if (o.drop) c.shape(ell(8, 16, 1.2, 1), 'cyan', 'orb');
};
const micro = build(microFn, [opt('Messing', 'Klassisch', {}), opt('Blau', 'Blaues Gehäuse', { col: 'blue' }), opt('Mit Funken', 'Entdeckung', { sparkle: 1 }), opt('Rot', 'Rotes Gehäuse', { col: 'red' }), opt('Mit Tropfen', 'Probe auf dem Glas', { drop: 1 }), opt('Grün', 'Grünes Gehäuse', { col: 'green' }), opt('Gold', 'Goldener Fuß', { col: 'gold', tube: 'steel' }), opt('Stahl', 'Stahlgrau', { col: 'steel' }), opt('Violett', 'Lila', { col: 'purple', sparkle: 1 }), opt('Dunkel', 'Eisen', { col: 'iron', tube: 'black' })]);

// ---------- dna ----------
const dnaFn = (c, o) => {
  const pts = (ph) => { const a = []; for (let i = 0; i <= 12; i++) a.push([12 + 6 * Math.sin(i * 0.55 + ph), 2 + i * 1.65]); return a; };
  const rot = o.diag ? (p) => p.map(([x, y]) => [x * 0.7 + y * 0.6 + 1, y * 0.7 - x * 0.2 + 5]) : (p) => p;
  if (o.rungs !== false) for (let i = 1; i < 12; i += 2) { const A = pts(0)[i], B = pts(Math.PI)[i]; const r = rot([A, B]); c.shape(path(r, 1), 'face', 'flat'); }
  c.shape(path(rot(pts(0)), 2.2), o.a || 'blue', 'diag'); c.shape(path(rot(pts(Math.PI)), 2.2), o.b || 'red', 'diag', 0.1);
  if (o.sparkle) sparkle(c, 20, 4, 3);
};
const dna = build(dnaFn, [opt('Blau-Rot', 'Klassisch', {}), opt('Grün-Gelb', 'Natur', { a: 'green', b: 'bolt' }), opt('Schräg', 'Diagonal', { diag: 1 }), opt('Violett', 'Lila-Cyan', { a: 'purple', b: 'cyan' }), opt('Ohne Sprossen', 'Nur Stränge', { rungs: false }), opt('Gold', 'Gold-Rot', { a: 'gold', b: 'red' }), opt('Mit Funken', 'Glitzernd', { sparkle: 1, a: 'cyan', b: 'pink' }), opt('Orange', 'Orange-Blau', { a: 'orange', b: 'blue' }), opt('Rosa', 'Rosa-Grün', { a: 'pink', b: 'green' }), opt('Schwarz-Weiß', 'Neutral', { a: 'iron', b: 'face' })]);

// ---------- dumbbell ----------
const dumbFn = (c, o) => {
  const col = o.col || 'iron';
  c.shape(rect(6, 10.4, 18, 13.6), 'steel', 'vert');
  if (o.round) { c.shape(ell(4.4, 12, 3.2, 6.6), col, 'orb'); c.shape(ell(19.6, 12, 3.2, 6.6), col, 'orb'); } else { c.shape(rect(2, 6, 7, 18), col, 'diag'); c.shape(rect(17, 6, 22, 18), col, 'diag'); if (o.big !== false) { c.shape(rect(0.5, 8, 2.4, 16), col, 'diag'); c.shape(rect(21.6, 8, 23.5, 16), col, 'diag'); } }
  if (o.sparkle) sparkle(c, 12, 5, 3);
};
const dumb = build(dumbFn, [opt('Hantel', 'Eisen', {}), opt('Gold', 'Goldene Scheiben', { col: 'gold' }), opt('Rund', 'Runde Gewichte', { round: 1 }), opt('Rot', 'Rote Gewichte', { col: 'red' }), opt('Blau', 'Blaue Gewichte', { col: 'blue' }), opt('Holz', 'Holzgewichte', { col: 'wood' }), opt('Stein', 'Steingewichte', { col: 'stone' }), opt('Schlicht', 'Eine Scheibe pro Seite', { big: false }), opt('Glanz', 'Mit Funken', { sparkle: 1, col: 'steel' }), opt('Grün', 'Grüne Gewichte', { col: 'green', round: 1 })]);

// ---------- clipboard ----------
const clipFn = (c, o) => {
  c.shape(rect(4, 3, 20, 22), o.board || 'wood', 'diag'); c.shape(rect(6, 6, 18, 20), 'face', 'vert', 0.05); c.shape(rect(8, 1, 16, 5), 'steel', 'diag'); c.shape(ell(12, 3, 1.4, 1.2), 'iron', 'orb');
  for (let i = 0; i < 3; i++) { const y = 9 + i * 4; if (o.checks) { c.shape(path([[8, y], [9, y + 1], [11, y - 1]], 0.9), 'green', 'flat'); } else c.shape(ell(9, y, 0.9, 0.9), o.dot || 'iron', 'flat'); c.shape(rect(12, y - 0.5, 17, y + 0.5), 'iron', 'flat'); }
};
const clip = build(clipFn, [opt('Brett', 'Holz mit Liste', {}), opt('Mit Haken', 'Erledigt', { checks: 1 }), opt('Blau', 'Blaues Brett', { board: 'blue' }), opt('Rot', 'Rotes Brett', { board: 'red' }), opt('Grün', 'Grünes Brett', { board: 'green', checks: 1 }), opt('Stahl', 'Metallbrett', { board: 'steel' }), opt('Dunkel', 'Eisenbrett', { board: 'iron', checks: 1 }), opt('Violett', 'Lila Brett', { board: 'purple' }), opt('Orange', 'Oranges Brett', { board: 'orange', checks: 1 }), opt('Leder', 'Lederbrett', { board: 'leather' })]);

// ---------- sponge ----------
const spongeFn = (c, o) => {
  c.shape(rect(3, 7, 21, 18), o.col || 'bolt', 'diag'); c.shape(rect(3, 4, 21, 7), o.top || 'green', 'vert');
  for (const [x, y] of [[7, 10], [13, 12], [17, 9], [9, 15], [16, 15]]) c.shape(ell(x, y, 1.3, 1.1), 'black', 'flat', 0.4);
  if (o.drops) { c.shape(ell(5, 21, 1.4, 1.6), 'cyan', 'orb'); c.shape(ell(12, 21, 1.4, 1.6), 'cyan', 'orb'); c.shape(ell(19, 21, 1.4, 1.6), 'cyan', 'orb'); }
};
const sponge = build(spongeFn, [opt('Gelb', 'Klassisch', {}), opt('Tropfend', 'Mit Wasser', { drops: 1 }), opt('Rosa', 'Rosa', { col: 'pink', top: 'purple' }), opt('Blau', 'Blau', { col: 'blue', top: 'cyan' }), opt('Orange', 'Orange', { col: 'orange', top: 'leaf' }), opt('Grün', 'Grün', { col: 'leaf', top: 'forest', drops: 1 }), opt('Weiß', 'Weiß', { col: 'face', top: 'steel' }), opt('Rot', 'Rot', { col: 'red', top: 'orange' }), opt('Braun', 'Naturschwamm', { col: 'sand', top: 'brown' }), opt('Violett', 'Violett', { col: 'purple', top: 'pink', drops: 1 })]);

// ---------- tools set ----------
const toolsFn = (c, o) => {
  const h = (x0, y0, x1, y1) => c.shape(thick(x0, y0, x1, y1, 2.4), 'wood', 'diag');
  if (o.kind === 'hw') { h(4, 21, 17, 7); c.shape(poly([[12, 3], [20, 6], [18, 11], [10, 8]]), 'iron', 'diag'); c.shape(thick(21, 21, 8, 8, 2.8), 'steel', 'diag'); c.shape(ell(7, 7, 3.6, 3.6), 'steel', 'orb'); c.shape(ell(7, 7, 1.4, 1.4), 'black', 'flat'); }
  if (o.kind === 'hs') { h(4, 21, 17, 7); c.shape(poly([[12, 3], [20, 6], [18, 11], [10, 8]]), 'iron', 'diag'); h(20, 21, 7, 7); c.shape(poly([[3, 6], [8, 3], [11, 8], [6, 10]]), 'steel', 'diag'); }
  if (o.kind === 'box') { c.shape(rect(3, 9, 21, 21), o.col || 'red', 'diag'); c.shape(rect(3, 9, 21, 11), 'iron', 'vert'); c.shape(ring(12, 7, 5, 3.4), 'steel', 'flat'); c.shape(rect(10, 13, 14, 16), 'gold', 'diag'); }
  if (o.kind === 'belt') { c.shape(rect(2, 5, 22, 8), 'leather', 'vert'); for (const [x, col] of [[5, 'iron'], [10, 'steel'], [15, 'wood'], [19, 'iron']]) c.shape(rect(x, 8, x + 3, 17), col, 'diag'); }
  if (o.kind === 'gear') { c.shape(ell(10, 12, 7, 7), 'steel', 'orb'); for (let a = 0; a < 8; a++) c.shape(ell(10 + 7.6 * Math.cos(a * 0.785), 12 + 7.6 * Math.sin(a * 0.785), 1.5, 1.5), 'steel', 'orb'); c.shape(ell(10, 12, 2.4, 2.4), 'black', 'flat'); c.shape(thick(21, 21, 13, 11, 2), 'wood', 'diag'); c.shape(ell(12, 10, 3, 3), 'iron', 'orb'); }
  if (o.kind === 'x') { h(4, 21, 20, 5); h(20, 21, 4, 5); c.shape(ell(12, 13, 3, 3), 'iron', 'orb'); }
  if (o.kind === 'roll') { c.shape(rect(3, 6, 21, 20), 'leather', 'diag'); c.shape(rect(3, 6, 21, 9), 'leatherd', 'vert'); for (const x of [6, 10, 14, 18]) c.shape(rect(x, 10, x + 2, 18), 'steel', 'diag'); }
  if (o.kind === 'hammer') { c.shape(thick(5, 21, 17, 9, 2.4), 'wood', 'diag'); c.shape(poly([[12, 5], [21, 8], [18, 13], [9, 10]]), 'iron', 'diag'); }
  if (o.kind === 'saw') { c.shape(poly([[2, 8], [20, 4], [20, 12], [2, 14]]), 'steel', 'diag'); c.shape(thick(4, 20, 14, 12, 2.4), 'wood', 'diag'); c.shape(thick(21, 21, 11, 9, 2.4), 'iron', 'diag'); }
  if (o.kind === 'star') { c.shape(star(12, 12, 10, 4.4, 6), 'steel', 'orb'); c.shape(ell(12, 12, 2.8, 2.8), 'iron', 'orb'); }
};
const tools = build(toolsFn, [opt('Hammer + Schlüssel', 'Gekreuzt', { kind: 'hw' }), opt('Hammer + Hacke', 'Gekreuzt', { kind: 'hs' }), opt('Werkzeugkasten', 'Rot', { kind: 'box' }), opt('Werkzeugkasten blau', 'Blau', { kind: 'box', col: 'blue' }), opt('Werkzeuggürtel', 'Mit Werkzeugen', { kind: 'belt' }), opt('Zahnrad + Griff', 'Reparatur', { kind: 'gear' }), opt('Zwei Stiele', 'X aus Holz', { kind: 'x' }), opt('Werkzeugrolle', 'Aufgerollt', { kind: 'roll' }), opt('Säge + Hammer', 'Zimmermann', { kind: 'saw' }), opt('Sechsstern', 'Mehrzweck', { kind: 'star' })]);

// ---------- clock ----------
const clockFn = (c, o) => {
  if (o.shape === 'sq') c.shape(rect(2, 2, 22, 22), o.rim || 'brass', 'diag'); else c.shape(ell(12, 12, 10.4, 10.4), o.rim || 'brass', 'orb');
  if (o.shape === 'sq') c.shape(rect(4.4, 4.4, 19.6, 19.6), 'face', 'orb', -0.1); else c.shape(ell(12, 12, 8.2, 8.2), 'face', 'orb', -0.1);
  c.shape(rect(11.4, 5, 12.6, 12.6), 'black', 'flat'); c.shape(rect(12, 11.4, 17, 12.6), 'red', 'flat'); c.shape(ell(12, 12, 1.2, 1.2), 'black', 'flat');
  for (const [x, y] of [[12, 4.4], [19.6, 12], [12, 19.6], [4.4, 12]]) c.px(x, y, 'iron', 2);
  if (o.bells) { c.shape(ell(5, 3, 3, 2.6), 'steel', 'orb'); c.shape(ell(19, 3, 3, 2.6), 'steel', 'orb'); c.shape(rect(3, 21, 6, 23), 'steel', 'flat'); c.shape(rect(18, 21, 21, 23), 'steel', 'flat'); }
  if (o.crown) c.shape(rect(10, 0, 14, 2.6), o.rim || 'brass', 'vert'); if (o.chain) c.shape(ring(12, 0.6, 2, 0.8), 'steel', 'flat');
};
const clock = build(clockFn, [opt('Wanduhr', 'Messing', {}), opt('Eckig', 'Quadratisch', { shape: 'sq' }), opt('Taschenuhr', 'Mit Krone', { crown: 1, chain: 1 }), opt('Wecker', 'Mit Glocken', { bells: 1, rim: 'red' }), opt('Silber', 'Silberrand', { rim: 'steel' }), opt('Holz', 'Holzrand', { rim: 'wood' }), opt('Blau', 'Blauer Rand', { rim: 'blue' }), opt('Gold', 'Goldrand', { rim: 'gold' }), opt('Eisen', 'Dunkel', { rim: 'iron' }), opt('Grün', 'Grüner Rand', { rim: 'green', crown: 1 })]);

// ---------- hourglass ----------
const hgFn = (c, o) => {
  const sand = o.sand || 'sand';
  c.shape(rect(3, 1, 21, 3.4), o.frame || 'wood', 'vert'); c.shape(rect(3, 20.6, 21, 23), o.frame || 'wood', 'vert');
  c.shape(poly([[5, 3.4], [19, 3.4], [13, 12], [19, 20.6], [5, 20.6], [11, 12]]), 'ice', 'diag');
  c.shape(poly([[6.4, 4.4], [17.6, 4.4], [13, 10], [11, 10]]), sand, 'vert', o.low ? 0.4 : 0);
  c.shape(poly([[6.4, 19.6], [17.6, 19.6], [14.6, 15.4], [9.4, 15.4]]), sand, 'vert');
  if (!o.low) c.shape(rect(11.6, 11, 12.4, 15.4), sand, 'flat');
  if (o.sparkle) sparkle(c, 20, 8, 2.6); if (o.sides) { c.shape(rect(3, 3, 4.4, 21), o.frame || 'wood', 'diag'); c.shape(rect(19.6, 3, 21, 21), o.frame || 'wood', 'diag'); }
};
const hourglass = build(hgFn, [opt('Sanduhr', 'Holzrahmen', {}), opt('Blauer Sand', 'Blau', { sand: 'blue' }), opt('Gold', 'Goldrahmen', { frame: 'gold', sand: 'goldl' }), opt('Mit Pfosten', 'Seitenstützen', { sides: 1 }), opt('Fast leer', 'Wenig oben', { low: 1 }), opt('Rot', 'Roter Sand', { sand: 'red', frame: 'iron' }), opt('Stein', 'Steinrahmen', { frame: 'stone' }), opt('Mit Funken', 'Magisch', { sparkle: 1, sand: 'purple' }), opt('Grün', 'Grüner Sand', { sand: 'leaf', frame: 'bark' }), opt('Silber', 'Silberrahmen', { frame: 'steel', sand: 'face' })]);

// ---------- stopwatch ----------
const swFn = (c, o) => {
  c.shape(rect(10, 1, 14, 4), 'steel', 'vert'); c.shape(rect(11, 3, 13, 5), 'iron', 'flat'); c.shape(ell(12, 14, 9, 9), o.rim || 'steel', 'orb'); c.shape(ell(12, 14, 7.2, 7.2), 'face', 'orb', -0.1);
  c.shape(path([[12, 14], [12, 9]], 1.2), 'black', 'flat'); if (!o.nohand2) c.shape(path([[12, 14], [16, 16]], 1), 'red', 'flat'); c.shape(ell(12, 14, 1, 1), 'black', 'flat');
  if (o.side) c.shape(thick(18, 6, 21, 4, 1.8), o.rim || 'steel', 'flat'); if (o.wedge) c.shape(poly([[12, 14], [12, 7.4], [17.4, 11]]), 'red', 'flat', 0.1); if (o.bolt) c.shape(poly([[13, 9], [10, 14], [12, 14], [11, 19], [15, 13], [13, 13]]), 'bolt', 'flat');
};
const stopwatch = build(swFn, [opt('Stoppuhr', 'Klassisch', {}), opt('Mit Knopf', 'Seitlicher Knopf', { side: 1 }), opt('Rot', 'Rotes Gehäuse', { rim: 'red' }), opt('Mit Sektor', 'Roter Sektor', { wedge: 1 }), opt('Gold', 'Gold', { rim: 'gold' }), opt('Blau', 'Blau', { rim: 'blue', side: 1 }), opt('Mit Blitz', 'Schnell', { bolt: 1 }), opt('Grün', 'Grün', { rim: 'green', wedge: 1 }), opt('Eine Hand', 'Schlicht', { nohand2: 1, rim: 'iron' }), opt('Orange', 'Orange', { rim: 'orange', side: 1 })]);

// ---------- bell ----------
const bellFn = (c, o) => {
  const col = o.col || 'gold';
  c.shape(poly([[12, 2], [17, 6], [18, 14], [21, 18], [3, 18], [6, 14], [7, 6]]), col, 'diag'); c.shape(rect(3, 17, 21, 19), col, 'vert', -0.1); c.shape(ell(12, 21, 2.6, 2.2), o.clap || 'brass', 'orb'); c.shape(rect(10.6, 0, 13.4, 3), 'iron', 'flat');
  if (o.dot) c.shape(ell(19, 5, 3, 3), 'red', 'orb'); if (o.waves) { c.shape(path([[2, 6], [1, 11]], 1), 'bolt', 'flat'); c.shape(path([[22, 6], [23, 11]], 1), 'bolt', 'flat'); } if (o.band) c.shape(rect(7, 11, 17, 12.6), 'red', 'flat');
};
const bell = build(bellFn, [opt('Messing', 'Klassisch', {}), opt('Mit Wellen', 'Läutend', { waves: 1 }), opt('Silber', 'Silberglocke', { col: 'steel', clap: 'iron' }), opt('Mit Punkt', 'Neue Nachricht', { dot: 1 }), opt('Rotes Band', 'Mit Schleife', { band: 1 }), opt('Blau', 'Blau', { col: 'blue' }), opt('Kupfer', 'Kupfer', { col: 'copper' }), opt('Grün', 'Grün', { col: 'green', waves: 1 }), opt('Eisen', 'Schwere Glocke', { col: 'iron', clap: 'steel' }), opt('Violett', 'Lila', { col: 'purple', dot: 1 })]);

// ---------- tasks ----------
const tasksFn = (c, o) => {
  c.shape(rect(3, 3, 21, 22), o.paper || 'face', 'diag'); if (o.roll) { c.shape(ell(3, 12.5, 2.4, 9.6), 'bread', 'orb'); c.shape(ell(21, 12.5, 2.4, 9.6), 'bread', 'orb'); }
  for (let i = 0; i < 4; i++) { const y = 6.5 + i * 4.2; c.shape(path([[6, y], [7.4, y + 1.4], [9.6, y - 1.2]], 1), o.check || 'green', 'flat'); c.shape(rect(11, y - 0.5, 18, y + 0.5), 'iron', 'flat'); }
  if (o.top) c.shape(rect(3, 3, 21, 5), o.top, 'vert');
};
const tasks = build(tasksFn, [opt('Checkliste', 'Haken auf Papier', {}), opt('Pergament', 'Alte Rolle', { roll: 1, paper: 'paper' }), opt('Mit Kopf', 'Roter Kopf', { top: 'red' }), opt('Blau', 'Blaue Haken', { check: 'blue', top: 'blue' }), opt('Gold', 'Goldhaken', { check: 'gold', paper: 'paper' }), opt('Grünkopf', 'Grüner Kopf', { top: 'green' }), opt('Rot', 'Rote Haken', { check: 'red' }), opt('Violett', 'Lila', { check: 'purple', top: 'purple' }), opt('Notizzettel', 'Gelb', { paper: 'bolt', check: 'red' }), opt('Orange', 'Orange', { top: 'orange', check: 'orange' })]);

// ---------- book ----------
const bookFn = (c, o) => {
  const col = o.col || 'red';
  if (o.open) { c.shape(poly([[2, 6], [12, 8], [12, 21], [2, 19]]), 'face', 'diag'); c.shape(poly([[22, 6], [12, 8], [12, 21], [22, 19]]), 'face', 'diag', 0.2); c.shape(rect(11.4, 8, 12.6, 21), 'leatherd', 'flat'); for (const y of [11, 14, 17]) { c.line(4, y, 10, y + 1, 'iron', 2); c.line(14, y + 1, 20, y, 'iron', 2); } }
  else { c.shape(rect(4, 2, 19, 22), col, 'diag'); c.shape(rect(4, 2, 7, 22), col, 'vert', 0.2); c.shape(rect(8, 5, 17, 9), 'gold', 'vert'); if (o.lock) { c.shape(rect(17, 10, 21, 15), 'steel', 'diag'); } c.shape(rect(19, 3, 21, 21), 'face', 'vert'); }
  if (o.sparkle) sparkle(c, 19, 5, 3.4); if (o.star) c.shape(star(12, 14, 3, 1.4), 'gold', 'flat');
};
const book = build(bookFn, [opt('Rotes Buch', 'Mit Titel', {}), opt('Aufgeschlagen', 'Offenes Buch', { open: 1 }), opt('Zauberbuch', 'Blau mit Stern', { col: 'blue', star: 1 }), opt('Grün', 'Grünes Buch', { col: 'green' }), opt('Mit Schloss', 'Verschlossen', { col: 'purple', lock: 1 }), opt('Braun', 'Lederband', { col: 'leather' }), opt('Offen mit Funken', 'Magisch', { open: 1, sparkle: 1 }), opt('Schwarz', 'Düsteres Buch', { col: 'black', star: 1 }), opt('Orange', 'Orangenes Buch', { col: 'orange' }), opt('Gold', 'Goldenes Buch', { col: 'gold', star: 1 })]);

// ---------- bookmark ----------
const bmFn = (c, o) => {
  const col = o.col || 'red';
  if (o.kind === 'flag') c.shape(poly([[6, 2], [18, 2], [18, 22], [12, 17], [6, 22]]), col, 'diag');
  else if (o.kind === 'swallow') c.shape(poly([[6, 2], [18, 2], [18, 22], [12, 16], [6, 22]]), col, 'diag');
  else if (o.kind === 'tag') { c.shape(poly([[7, 2], [17, 2], [17, 22], [7, 22]]), col, 'diag'); c.shape(ell(12, 5.4, 1.4, 1.4), 'black', 'flat'); }
  else if (o.kind === 'corner') { c.shape(poly([[3, 3], [21, 3], [21, 21], [3, 21]]), 'face', 'diag'); c.shape(poly([[14, 3], [21, 3], [21, 10]]), col, 'diag'); }
  else c.shape(poly([[7, 1], [17, 1], [17, 22], [12, 18], [7, 22]]), col, 'diag');
  if (o.star) c.shape(star(12, 8, 3.4, 1.5), 'goldl', 'orb'); if (o.heart) c.shape(heart(12, 9, 3.6), 'face', 'flat'); if (o.stripe) c.shape(rect(7, 4, 17, 5.4), 'gold', 'flat');
};
const bookmark = build(bmFn, [opt('Lesezeichen', 'Rotes Band', {}), opt('Gold', 'Goldband', { col: 'gold' }), opt('Wimpel', 'Flaggenform', { kind: 'flag', col: 'blue' }), opt('Schwalbenschwanz', 'Zweizipflig', { kind: 'swallow', col: 'green' }), opt('Mit Stern', 'Stern oben', { star: 1 }), opt('Mit Herz', 'Herz oben', { heart: 1, col: 'purple' }), opt('Anhänger', 'Mit Loch', { kind: 'tag', col: 'leather' }), opt('Eselsohr', 'Ecke gefaltet', { kind: 'corner' }), opt('Blau', 'Blau mit Streifen', { col: 'blue', stripe: 1 }), opt('Orange', 'Orange', { col: 'orange', star: 1 })]);

// ---------- chat ----------
const chatFn = (c, o) => {
  const col = o.col || 'face';
  if (o.kind === 'round') c.shape(either(ell(12, 10, 10, 8), poly([[5, 15], [4, 22], [11, 17]])), col, 'orb');
  else if (o.kind === 'cloud') { c.shape(ell(8, 10, 5, 4.6), col, 'orb'); c.shape(ell(16, 10, 5, 4.6), col, 'orb'); c.shape(ell(12, 8, 5, 4.6), col, 'orb'); c.shape(rect(4, 10, 20, 15), col, 'vert', -0.1); c.shape(poly([[7, 15], [6, 21], [12, 15]]), col, 'diag'); }
  else if (o.kind === 'two') { c.shape(poly([[1, 3], [14, 3], [14, 12], [8, 12], [4, 16], [4, 12], [1, 12]]), col, 'diag'); c.shape(poly([[10, 9], [23, 9], [23, 18], [20, 18], [20, 22], [16, 18], [10, 18]]), o.col2 || 'blue', 'diag', 0.1); }
  else c.shape(poly([[2, 3], [22, 3], [22, 16], [14, 16], [8, 21], [8, 16], [2, 16]]), col, 'diag');
  const cy = o.kind === 'two' ? 0 : 0;
  if (o.dots) for (const x of [8, 12, 16]) c.shape(ell(x, 9.6 + cy, 1.4, 1.4), 'iron', 'orb'); if (o.heart) c.shape(heart(12, 9.4, 4), 'red', 'orb'); if (o.bang) { c.shape(rect(11, 5, 13, 10), 'red', 'flat'); c.shape(rect(11, 11.4, 13, 13), 'red', 'flat'); }
};
const chat = build(chatFn, [opt('Sprechblase', 'Eckig mit Punkten', { dots: 1 }), opt('Rund', 'Runde Blase', { kind: 'round', dots: 1 }), opt('Zwei Blasen', 'Dialog', { kind: 'two' }), opt('Mit Herz', 'Nette Nachricht', { heart: 1 }), opt('Ausrufezeichen', 'Wichtig', { bang: 1, col: 'bolt' }), opt('Wolke', 'Gedankenblase', { kind: 'cloud', dots: 1 }), opt('Blau', 'Blaue Blase', { col: 'blue', dots: 1 }), opt('Grün', 'Grüne Blase', { col: 'green', dots: 1 }), opt('Rund mit Herz', 'Rund, Herz', { kind: 'round', heart: 1 }), opt('Rot', 'Rote Blase', { col: 'red', bang: 1 })]);

// ---------- tag ----------
const tagFn = (c, o) => {
  const col = o.col || 'bread';
  if (o.kind === 'round') c.shape(ell(12, 13, 8.4, 8.4), col, 'orb'); else if (o.kind === 'ticket') { c.shape(rect(3, 6, 21, 18), col, 'diag'); } else c.shape(poly([[3, 4], [14, 4], [21, 11], [14, 20], [3, 20]]), col, 'diag');
  if (o.kind !== 'ticket') c.shape(ell(7, 12, 1.6, 1.6), 'black', 'flat');
  if (o.string) c.shape(path([[7, 12], [3, 4], [10, 2]], 0.9), 'leatherd', 'flat'); if (o.coin) c.shape(ell(14, 12, 3, 3), 'gold', 'orb'); if (o.line) { c.shape(rect(11, 9, 18, 10), 'iron', 'flat'); c.shape(rect(11, 13, 16, 14), 'iron', 'flat'); }
};
const tag = build((c, o) => { if (o.kind === 'ticket') { c.shape(rect(3, 6, 21, 18), o.col || 'bread', 'diag'); c.shape(rect(14, 6, 15, 18), 'iron', 'flat'); c.shape(star(8.5, 12, 3, 1.4), 'gold', 'flat'); return; } tagFn(c, o); }, [opt('Preisschild', 'Mit Loch', { line: 1 }), opt('Mit Schnur', 'Angebunden', { string: 1, line: 1 }), opt('Gold', 'Goldschild', { col: 'gold', coin: 1 }), opt('Rund', 'Runde Marke', { kind: 'round', line: 1 }), opt('Eintrittskarte', 'Ticket', { kind: 'ticket' }), opt('Rot', 'Rot', { col: 'red', coin: 1 }), opt('Blau', 'Blau', { col: 'blue', line: 1 }), opt('Silber', 'Silber', { col: 'steel', string: 1 }), opt('Grün', 'Grün', { col: 'green', coin: 1 }), opt('Holz', 'Holz', { col: 'wood', string: 1 })]);

// ---------- trophy ----------
const trophyFn = (c, o) => {
  const col = o.col || 'gold';
  c.shape(poly([[6, 3], [18, 3], [17, 10], [14, 14], [10, 14], [7, 10]]), col, 'diag'); if (o.handles !== false) { c.shape(ring(5, 7, 3.4, 1.8), col, 'orb'); c.shape(ring(19, 7, 3.4, 1.8), col, 'orb'); }
  c.shape(rect(10.6, 13, 13.4, 18), col, 'diag'); c.shape(rect(7, 18, 17, 21), o.base || 'wood', 'vert'); c.shape(rect(6, 21, 18, 22.6), o.base || 'wood', 'vert', 0.2);
  if (o.star) c.shape(star(12, 8, 3, 1.4), 'face', 'flat'); if (o.gem) c.shape(ell(12, 8, 1.8, 1.8), 'red', 'orb'); if (o.laurel) { c.shape(path([[8, 16], [7, 9]], 1), 'leaf', 'flat'); c.shape(path([[16, 16], [17, 9]], 1), 'leaf', 'flat'); }
};
const trophy = build(trophyFn, [opt('Pokal', 'Gold, Sockel', {}), opt('Mit Stern', 'Stern auf dem Kelch', { star: 1 }), opt('Silber', 'Silberpokal', { col: 'steel', base: 'iron' }), opt('Mit Edelstein', 'Rubin', { gem: 1 }), opt('Bronze', 'Bronzepokal', { col: 'copper' }), opt('Ohne Henkel', 'Schlicht', { handles: false, star: 1 }), opt('Lorbeer', 'Mit Zweigen', { laurel: 1 }), opt('Blauer Sockel', 'Blau', { base: 'blue', star: 1 }), opt('Roter Sockel', 'Rot', { base: 'red', gem: 1 }), opt('Marmorsockel', 'Hell', { base: 'face', star: 1 })]);

// ---------- medal ----------
const medalFn = (c, o) => {
  const col = o.col || 'gold';
  c.shape(poly([[7, 1], [12, 1], [14, 11], [9, 11]]), o.rib || 'red', 'diag'); c.shape(poly([[12, 1], [17, 1], [15, 11], [10, 11]]), o.rib2 || 'blue', 'diag', 0.1);
  if (o.rosette) { c.shape(star(12, 15, 8, 6, 12), col, 'orb'); c.shape(ell(12, 15, 5, 5), col, 'orb', 0.15); } else { c.shape(ell(12, 15, 7, 7), col, 'orb'); c.shape(ell(12, 15, 5, 5), col, 'orb', 0.18); }
  if (o.star !== false) c.shape(star(12, 15.4, 3.6, 1.6), 'face', 'flat', -0.1); if (o.num) c.shape(rect(11, 12, 13, 18), 'face', 'flat');
};
const medal = build(medalFn, [opt('Goldmedaille', 'Rot-blaues Band', {}), opt('Silber', 'Silbermedaille', { col: 'steel' }), opt('Bronze', 'Bronzemedaille', { col: 'copper' }), opt('Mit Ziffer 1', 'Erster Platz', { star: false, num: 1 }), opt('Rosette', 'Gezackt', { rosette: 1 }), opt('Grünes Band', 'Grün', { rib: 'green', rib2: 'leaf' }), opt('Schwarzes Band', 'Dunkel', { rib: 'black', rib2: 'iron', col: 'steel' }), opt('Rot-Rot', 'Rotes Band', { rib: 'red', rib2: 'orange' }), opt('Violett', 'Violett', { rib: 'purple', rib2: 'pink', rosette: 1 }), opt('Blau', 'Blau', { rib: 'blue', rib2: 'cyan', col: 'goldl' })]);

// ---------- crown ----------
const crownFn = (c, o) => {
  const col = o.col || 'gold';
  if (o.kind === 'circlet') { c.shape(rect(3, 11, 21, 17), col, 'vert'); c.shape(poly([[12, 6], [15, 11], [9, 11]]), col, 'diag'); }
  else if (o.kind === 'tall') c.shape(poly([[3, 20], [3, 4], [8, 11], [12, 2], [16, 11], [21, 4], [21, 20]]), col, 'diag');
  else if (o.kind === 'spiky') c.shape(poly([[2, 20], [2, 6], [6, 12], [8, 3], [11, 12], [12, 2], [13, 12], [16, 3], [18, 12], [22, 6], [22, 20]]), col, 'diag');
  else c.shape(poly([[3, 20], [3, 7], [8, 12], [12, 5], [16, 12], [21, 7], [21, 20]]), col, 'diag');
  c.shape(rect(3, 17, 21, 20), o.band || col, 'vert', 0.12);
  if (o.gems) for (const [x, g] of [[7, 'red'], [12, 'blue'], [17, 'green']]) c.shape(ell(x, 17.5, 1.4, 1.4), g, 'orb'); if (o.velvet) c.shape(rect(5, 12, 19, 17), 'red', 'vert', 0.1);
};
const crown = build(crownFn, [opt('Krone', 'Klassisch', { gems: 1 }), opt('Schlicht', 'Ohne Steine', {}), opt('Hoch', 'Hohe Zinken', { kind: 'tall', gems: 1 }), opt('Reif', 'Stirnreif', { kind: 'circlet', gems: 1 }), opt('Samt', 'Roter Samt', { velvet: 1 }), opt('Spitz', 'Spitze Zinken', { kind: 'spiky' }), opt('Silber', 'Silberkrone', { col: 'steel', gems: 1 }), opt('Kupfer', 'Kupferkrone', { col: 'copper', kind: 'tall' }), opt('Blau-Band', 'Blaues Band', { band: 'blue', gems: 1 }), opt('Dunkel', 'Eisenkrone', { col: 'iron', kind: 'spiky', gems: 1 })]);

// ---------- star ----------
const starFn = (c, o) => {
  const col = o.col || 'bolt';
  if (o.kind === 'ring') c.shape(ell(12, 12, 10.6, 10.6), 'blue', 'orb'); if (o.kind === 'badge') { c.shape(star(12, 12, 11, 8, 12), 'steel', 'orb'); }
  c.shape(star(12, 12.6, o.r || 10.4, o.ri || 4.4, o.n || 5), col, 'orb', o.bias || 0);
  if (o.kind === 'badge') c.shape(ell(12, 12.6, 1.6, 1.6), 'steel', 'orb'); if (o.sparkle) { sparkle(c, 20, 4, 3); sparkle(c, 4, 20, 2); }
};
const starC = build((c, o) => { if (o.kind === 'out') { c.shape(star(12, 12.6, 10.4, 4.4, 5), 'bolt', 'orb'); c.shape(star(12, 12.8, 6, 2.6, 5), 'iron', 'flat'); return; } if (o.kind === 'shoot') { c.shape(poly([[2, 21], [10, 10], [12, 14]]), 'bolt', 'diag', 0.2); c.shape(star(15, 9, 7, 3, 5), 'bolt', 'orb'); return; } starFn(c, o); }, [opt('Stern', 'Goldstern', {}), opt('Rund', 'Dicke Spitzen', { ri: 5.6 }), opt('Funkelnd', 'Mit Funken', { sparkle: 1 }), opt('Achtzack', 'Acht Zacken', { n: 8, ri: 5 }), opt('Sheriffstern', 'Abzeichen', { kind: 'badge' }), opt('Im Kreis', 'Medaillon', { kind: 'ring', r: 7, ri: 3 }), opt('Orange', 'Orange', { col: 'orange' }), opt('Silber', 'Silberstern', { col: 'steel' }), opt('Schlank', 'Spitz', { ri: 3 }), opt('Sechszack', 'Sechs Zacken', { n: 6, ri: 5, col: 'goldl' })]);

// ---------- balance ----------
const balFn = (c, o) => {
  const col = o.col || 'gold';
  c.shape(rect(11, 3, 13, 20), col, 'diag'); c.shape(rect(7, 20, 17, 22), col, 'vert'); c.shape(ell(12, 3, 2, 2), col, 'orb'); c.shape(rect(3, 5, 21, 6.6), col, 'vert');
  const y = (s) => 6 + (o.tilt ? s * 3 : 0);
  for (const s of [-1, 1]) { const x = 12 + s * 8; c.shape(path([[x, y(s)], [x - 3, y(s) + 7]], 0.7), 'iron', 'flat'); c.shape(path([[x, y(s)], [x + 3, y(s) + 7]], 0.7), 'iron', 'flat'); c.shape(both(ell(x, y(s) + 7, 4, 3), rect(0, y(s) + 7, 24, 30)), col, 'vert'); if (o.coins && s === -1) c.shape(ell(x, y(s) + 6, 1.6, 1.2), 'goldl', 'orb'); }
};
const balance = build(balFn, [opt('Waage', 'Gold', {}), opt('Geneigt', 'Schwer links', { tilt: 1, coins: 1 }), opt('Silber', 'Silberwaage', { col: 'steel' }), opt('Mit Münzen', 'Gold gewogen', { coins: 1 }), opt('Eisen', 'Eisenwaage', { col: 'iron' }), opt('Kupfer', 'Kupfer', { col: 'copper', coins: 1 }), opt('Geneigt Silber', 'Ungleich', { tilt: 1, col: 'steel' }), opt('Holz', 'Holzwaage', { col: 'wood' }), opt('Messing', 'Messing', { col: 'brass', tilt: 1 }), opt('Hell', 'Elfenbein', { col: 'face' })]);

// ---------- exchange ----------
const exFn = (c, o) => {
  const a = o.a || 'green', b = o.b || 'orange';
  if (o.kind === 'coins') { c.shape(ell(6, 8, 4.6, 4.6), 'gold', 'orb'); c.shape(ell(18, 16, 4.6, 4.6), 'steel', 'orb'); c.shape(path([[8, 15], [14, 15]], 1.4), a, 'flat'); c.shape(poly([[14, 12], [18, 15], [14, 18]]), a, 'diag'); c.shape(path([[16, 9], [10, 9]], 1.4), b, 'flat'); c.shape(poly([[10, 6], [6, 9], [10, 12]]), b, 'diag'); return; }
  if (o.kind === 'ud') { c.shape(rect(5, 9, 8, 22), a, 'diag'); c.shape(poly([[6.5, 2], [1, 10], [12, 10]]), a, 'diag'); c.shape(rect(16, 2, 19, 15), b, 'diag'); c.shape(poly([[17.5, 22], [12, 14], [23, 14]]), b, 'diag'); return; }
  c.shape(rect(3, 6, 15, 9), a, 'vert'); c.shape(poly([[22, 7.5], [14, 2], [14, 13]]), a, 'diag'); c.shape(rect(9, 15, 21, 18), b, 'vert'); c.shape(poly([[2, 16.5], [10, 11], [10, 22]]), b, 'diag');
  if (o.coin) { c.shape(ell(12, 12, 2.6, 2.6), 'gold', 'orb'); }
};
const exchange = build(exFn, [opt('Tausch', 'Zwei Pfeile', {}), opt('Mit Münze', 'Münze in der Mitte', { coin: 1 }), opt('Hoch-Runter', 'Senkrecht', { kind: 'ud' }), opt('Münztausch', 'Gold gegen Silber', { kind: 'coins' }), opt('Blau-Rot', 'Farbig', { a: 'blue', b: 'red' }), opt('Violett', 'Lila', { a: 'purple', b: 'pink', coin: 1 }), opt('Gold-Silber', 'Edel', { a: 'gold', b: 'steel' }), opt('Cyan', 'Türkis', { a: 'cyan', b: 'blue' }), opt('Senkrecht Rot', 'Hoch-Runter, rot', { kind: 'ud', a: 'red', b: 'orange' }), opt('Schlicht', 'Grau', { a: 'iron', b: 'steel' })]);

// ---------- cycle ----------
const cycFn = (c, o) => {
  const a = o.a || 'cyan';
  const arc = (a0, a1, r, w, col) => { const pts = []; for (let t = a0; t <= a1; t += 0.12) pts.push([12 + r * Math.cos(t), 12 + r * Math.sin(t)]); c.shape(path(pts, w), col, 'orb'); };
  const head = (ang, r, col) => { const x = 12 + r * Math.cos(ang), y = 12 + r * Math.sin(ang), d = ang + Math.PI / 2; c.shape(poly([[x + 4.4 * Math.cos(d), y + 4.4 * Math.sin(d)], [x - 4.4 * Math.cos(d), y - 4.4 * Math.sin(d)], [x + 4.6 * Math.cos(ang + 0), y + 4.6 * Math.sin(ang)]]), col, 'diag'); };
  const n = o.n || 2; const span = (2 * Math.PI) / n;
  for (let i = 0; i < n; i++) { const s0 = i * span + 0.25, s1 = (i + 1) * span - 0.7; arc(s0, s1, 7.6, 2.8, i % 2 ? (o.b || a) : a); head(s1 + 0.05, 7.6, i % 2 ? (o.b || a) : a); }
  if (o.dot) c.shape(ell(12, 12, 2.6, 2.6), 'gold', 'orb');
};
const cycle = build(cycFn, [opt('Kreislauf', 'Zwei Pfeile', {}), opt('Drei Pfeile', 'Dreieck', { n: 3, a: 'green' }), opt('Mit Münze', 'Gold in der Mitte', { dot: 1 }), opt('Orange', 'Orange', { a: 'orange', b: 'red' }), opt('Violett', 'Lila', { a: 'purple', b: 'pink' }), opt('Grün', 'Grün', { a: 'leaf' }), opt('Rot', 'Rot', { a: 'red', dot: 1 }), opt('Blau', 'Blau', { a: 'blue', b: 'cyan' }), opt('Vier Pfeile', 'Vierteilig', { n: 4, a: 'gold' }), opt('Silber', 'Silber', { a: 'steel', b: 'iron' })]);

// ---------- save ----------
const saveFn = (c, o) => {
  const col = o.col || 'blue';
  if (o.kind === 'cloud') { c.shape(ell(8, 13, 5.4, 5), col, 'orb'); c.shape(ell(15, 12, 6.4, 6), col, 'orb'); c.shape(rect(5, 14, 20, 18), col, 'vert'); c.shape(poly([[12, 11], [16, 15], [13, 15], [13, 21], [11, 21], [11, 15], [8, 15]]), 'face', 'flat'); return; }
  if (o.kind === 'chest') { c.shape(rect(3, 10, 21, 21), 'wood', 'diag'); c.shape(both(ell(12, 10, 9, 7), rect(0, 3, 24, 10)), 'woodl', 'vert'); c.shape(rect(10, 12, 14, 16), 'gold', 'diag'); return; }
  if (o.kind === 'scroll') { c.shape(rect(4, 4, 20, 20), 'paper', 'diag'); c.shape(ell(4, 12, 2, 8.6), 'bread', 'orb'); c.shape(ell(20, 12, 2, 8.6), 'bread', 'orb'); c.shape(ell(14, 16, 3, 3), 'red', 'orb'); return; }
  c.shape(poly([[3, 3], [18, 3], [21, 6], [21, 21], [3, 21]]), col, 'diag'); c.shape(rect(7, 3, 16, 9), 'steel', 'vert'); c.shape(rect(13, 4, 15, 8), 'iron', 'flat'); c.shape(rect(6, 13, 18, 21), 'face', 'diag');
  if (o.check) c.shape(path([[8, 17], [11, 19], [16, 15]], 1.2), 'green', 'flat');
};
const save = build(saveFn, [opt('Diskette', 'Blau', {}), opt('Mit Haken', 'Gespeichert', { check: 1 }), opt('Wolke', 'Cloud', { kind: 'cloud', col: 'cyan' }), opt('Truhe', 'Im Schatz', { kind: 'chest' }), opt('Siegel', 'Schriftrolle mit Siegel', { kind: 'scroll' }), opt('Rot', 'Rote Diskette', { col: 'red' }), opt('Grün', 'Grüne Diskette', { col: 'green', check: 1 }), opt('Schwarz', 'Dunkel', { col: 'iron' }), opt('Violett', 'Lila', { col: 'purple' }), opt('Gold', 'Gold', { col: 'gold', check: 1 })]);

// ---------- battery ----------
const batFn = (c, o) => {
  const col = o.col || 'green'; const n = o.n ?? 3;
  if (o.vertical) { c.shape(rect(9, 1, 15, 3), 'steel', 'vert'); c.shape(rect(5, 3, 19, 22), 'iron', 'diag'); c.shape(rect(7, 5, 17, 20), 'black', 'flat'); for (let i = 0; i < n; i++) c.shape(rect(8, 17.4 - i * 4.4, 16, 19.4 - i * 4.4), col, 'vert'); }
  else { c.shape(rect(21, 9, 23, 15), 'steel', 'diag'); c.shape(rect(1, 5, 21, 19), 'iron', 'diag'); c.shape(rect(3, 7, 19, 17), 'black', 'flat'); for (let i = 0; i < n; i++) c.shape(rect(4 + i * 5.2, 8, 8 + i * 5.2, 16), col, 'vert'); }
  if (o.bolt) c.shape(poly([[13, 6], [8, 13], [11, 13], [10, 18], [15, 11], [12, 11]]), 'bolt', 'flat');
};
const battery = build(batFn, [opt('Batterie', 'Drei Balken', {}), opt('Aufrecht', 'Stehend', { vertical: 1 }), opt('Mit Blitz', 'Lädt', { bolt: 1, n: 2 }), opt('Fast leer', 'Rot, ein Balken', { col: 'red', n: 1 }), opt('Voll', 'Volle Ladung', { n: 4, col: 'leaf' }), opt('Blau', 'Blaue Ladung', { col: 'cyan', n: 3 }), opt('Gelb', 'Gelbe Ladung', { col: 'bolt', n: 2 }), opt('Aufrecht mit Blitz', 'Stehend, lädt', { vertical: 1, bolt: 1, n: 2 }), opt('Orange', 'Orange', { col: 'orange', n: 2 }), opt('Violett', 'Lila', { col: 'purple', vertical: 1, n: 3 })]);

// ---------- party ----------
const partyFn = (c, o) => {
  if (o.kind === 'balloons') { for (const [x, y, col] of [[7, 8, 'red'], [14, 7, 'blue'], [11, 13, 'bolt']]) { c.shape(ell(x, y, 4.4, 5.2), col, 'orb'); c.shape(path([[x, y + 5], [12, 22]], 0.6), 'iron', 'flat'); } return; }
  if (o.kind === 'cake') { c.shape(rect(4, 12, 20, 21), 'pink', 'diag'); c.shape(rect(4, 10, 20, 13), 'face', 'vert'); c.shape(rect(11, 4, 13, 10), 'bolt', 'flat'); c.shape(poly([[12, 1], [13.6, 3.4], [12, 4.4], [10.4, 3.4]]), 'orange', 'vert'); return; }
  if (o.kind === 'hat') { c.shape(poly([[3, 21], [12, 2], [21, 21]]), 'purple', 'diag'); for (const [x, y] of [[9, 14], [13, 11], [14, 17]]) c.shape(ell(x, y, 1.2, 1.2), 'bolt', 'orb'); c.shape(ell(12, 2.4, 2, 2), 'pink', 'orb'); return; }
  if (o.kind === 'flags') { c.shape(path([[1, 5], [12, 9], [23, 5]], 0.8), 'iron', 'flat'); for (const [x, y, col] of [[4, 6.4, 'red'], [9, 8, 'blue'], [15, 8, 'bolt'], [20, 6.4, 'green']]) c.shape(poly([[x - 2, y], [x + 2, y], [x, y + 5]]), col, 'diag'); return; }
  c.shape(poly([[2, 22], [8, 8], [14, 14]]), o.col || 'red', 'diag'); c.shape(path([[10, 8], [16, 2]], 1), 'bolt', 'flat'); for (const [x, y, col] of [[16, 4, 'blue'], [19, 9, 'bolt'], [14, 10, 'pink'], [21, 14, 'green'], [8, 3, 'orange']]) c.shape(rect(x, y, x + 2, y + 2), col, 'flat');
};
const party = build(partyFn, [opt('Konfettikanone', 'Popper', {}), opt('Luftballons', 'Drei Ballons', { kind: 'balloons' }), opt('Torte', 'Mit Kerze', { kind: 'cake' }), opt('Wimpelkette', 'Girlande', { kind: 'flags' }), opt('Partyhut', 'Mit Punkten', { kind: 'hat' }), opt('Blauer Popper', 'Blau', { col: 'blue' }), opt('Grüner Popper', 'Grün', { col: 'green' }), opt('Violetter Popper', 'Lila', { col: 'purple' }), opt('Goldener Popper', 'Gold', { col: 'gold' }), opt('Rosa Popper', 'Rosa', { col: 'pink' })]);

// ---------- dice ----------
const pips = { 1: [[12, 12]], 2: [[8, 8], [16, 16]], 3: [[8, 8], [12, 12], [16, 16]], 4: [[8, 8], [16, 8], [8, 16], [16, 16]], 5: [[8, 8], [16, 8], [12, 12], [8, 16], [16, 16]], 6: [[8, 7.4], [16, 7.4], [8, 12], [16, 12], [8, 16.6], [16, 16.6]] };
const diceFn = (c, o) => {
  const col = o.col || 'face';
  if (o.kind === 'd20') { c.shape(poly([[12, 1], [21, 6], [21, 17], [12, 22], [3, 17], [3, 6]]), col, 'diag'); c.shape(poly([[12, 1], [21, 6], [12, 9], [3, 6]]), col, 'vert', -0.2); c.shape(poly([[12, 9], [18, 15], [6, 15]]), col, 'diag', 0.15); c.shape(rect(11, 11, 13, 13.4), o.pip || 'black', 'flat'); return; }
  if (o.kind === 'd4') { c.shape(poly([[12, 2], [22, 20], [2, 20]]), col, 'diag'); c.shape(poly([[12, 2], [12, 20], [2, 20]]), col, 'diag', 0.22); c.shape(ell(12, 13, 1.2, 1.2), o.pip || 'black', 'flat'); return; }
  if (o.kind === 'iso') { c.shape(poly([[12, 2], [22, 7], [12, 12], [2, 7]]), col, 'vert', -0.15); c.shape(poly([[2, 7], [12, 12], [12, 22], [2, 17]]), col, 'diag'); c.shape(poly([[12, 12], [22, 7], [22, 17], [12, 22]]), col, 'diag', 0.3); for (const [x, y] of [[12, 7], [7, 13], [17, 13], [7, 17], [17, 17]].slice(0, 3)) c.shape(ell(x, y, 1, 1), o.pip || 'black', 'flat'); return; }
  c.shape(poly([[4, 2], [20, 2], [22, 4], [22, 20], [20, 22], [4, 22], [2, 20], [2, 4]]), col, 'diag'); for (const [x, y] of pips[o.n || 5]) c.shape(ell(x, y, 1.7, 1.7), o.pip || 'black', 'orb');
};
const dice = build(diceFn, [opt('Würfel', 'Fünf', {}), opt('Sechs', 'Sechs Augen', { n: 6 }), opt('Rot', 'Roter Würfel', { col: 'red', pip: 'face' }), opt('Zwanzigseiter', 'D20', { kind: 'd20' }), opt('Isometrisch', 'Dreiseitig', { kind: 'iso' }), opt('Vierseiter', 'D4', { kind: 'd4', col: 'green' }), opt('Gold', 'Goldwürfel', { col: 'gold', n: 3 }), opt('Blau', 'Blauer Würfel', { col: 'blue', pip: 'face', n: 6 }), opt('Schwarz', 'Schwarzer Würfel', { col: 'black', pip: 'face', n: 4 }), opt('Grün', 'Grüner D20', { kind: 'd20', col: 'green', pip: 'face' })]);

const CONCEPTS = [
  { cat: 'Forschung', key: 'stethoscope', name: 'Stethoskop', designs: stetho },
  { cat: 'Forschung', key: 'microscope', name: 'Mikroskop', designs: micro },
  { cat: 'Forschung', key: 'dna', name: 'DNA', designs: dna },
  { cat: 'Forschung', key: 'dumbbell', name: 'Hantel', designs: dumb },
  { cat: 'Forschung', key: 'clipboard', name: 'Klemmbrett', designs: clip },
  { cat: 'Forschung', key: 'sponge', name: 'Schwamm', designs: sponge },
  { cat: 'Forschung', key: 'tools', name: 'Werkzeugset', designs: tools },
  { cat: 'Zeit', key: 'clock', name: 'Uhr', designs: clock },
  { cat: 'Zeit', key: 'hourglass', name: 'Sanduhr', designs: hourglass },
  { cat: 'Zeit', key: 'stopwatch', name: 'Stoppuhr', designs: stopwatch },
  { cat: 'Zeit', key: 'bell', name: 'Glocke', designs: bell },
  { cat: 'Zeit', key: 'tasks', name: 'Aufgabenliste', designs: tasks },
  { cat: 'Zeit', key: 'book', name: 'Buch', designs: book },
  { cat: 'Zeit', key: 'bookmark', name: 'Lesezeichen', designs: bookmark },
  { cat: 'Zeit', key: 'chat', name: 'Chat', designs: chat },
  { cat: 'Zeit', key: 'tag', name: 'Preisschild', designs: tag },
  { cat: 'Zeit', key: 'trophy', name: 'Pokal', designs: trophy },
  { cat: 'Zeit', key: 'medal', name: 'Medaille', designs: medal },
  { cat: 'Zeit', key: 'crown', name: 'Krone', designs: crown },
  { cat: 'Zeit', key: 'star', name: 'Stern', designs: starC },
  { cat: 'Zeit', key: 'balance', name: 'Waage', designs: balance },
  { cat: 'Zeit', key: 'exchange', name: 'Tausch', designs: exchange },
  { cat: 'Zeit', key: 'cycle', name: 'Kreislauf', designs: cycle },
  { cat: 'Zeit', key: 'save', name: 'Speichern', designs: save },
  { cat: 'Zeit', key: 'battery', name: 'Batterie', designs: battery },
  { cat: 'Zeit', key: 'party', name: 'Feier', designs: party },
  { cat: 'Zeit', key: 'dice', name: 'Würfel', designs: dice },
];
module.exports = { CONCEPTS };
