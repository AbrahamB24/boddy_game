// Batch 10: UI glyphs. One glyph drawing per shape, offered in 10 treatments (colour, weight, plate).
const { ell, rect, poly, thick, minus, both, either, ring, heart, star } = require('./engine.js');
const path = (pts, w) => { const ms = []; for (let i = 0; i < pts.length - 1; i++) ms.push(thick(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)); return (x, y) => ms.some((m) => m(x, y)); };
const sc = (m, k, cx = 12, cy = 12) => (x, y) => m(cx + (x - cx) / k, cy + (y - cy) / k);
const hexagon = (r, cx = 12, cy = 12) => poly([0, 1, 2, 3, 4, 5].map((i) => [cx + r * Math.cos(i * 1.047 + 0.52), cy + r * Math.sin(i * 1.047 + 0.52)]));
const tri = (a, b, c2) => poly([a, b, c2]);

// glyph -> list of [role, mask, ramp?]; roles: m (main, treatment colour), p (plate colour of the glyph itself), a (accent)
const GL = {
  plus: (w) => [['m', rect(12 - w / 2, 3, 12 + w / 2, 21)], ['m', rect(3, 12 - w / 2, 21, 12 + w / 2)]],
  minus: (w) => [['m', rect(3, 12 - w / 2, 21, 12 + w / 2)]],
  x: (w) => [['m', thick(4, 4, 20, 20, w * 1.1)], ['m', thick(20, 4, 4, 20, w * 1.1)]],
  left: (w) => [['m', path([[15, 4], [7, 12], [15, 20]], w)]], right: (w) => [['m', path([[9, 4], [17, 12], [9, 20]], w)]],
  up: (w) => [['m', path([[4, 15], [12, 7], [20, 15]], w)]], down: (w) => [['m', path([[4, 9], [12, 17], [20, 9]], w)]],
  arrowRight: (w) => [['m', rect(3, 12 - w / 2, 16, 12 + w / 2)], ['m', tri([22, 12], [13, 3.4], [13, 20.6])]],
  arrowLeft: (w) => [['m', rect(8, 12 - w / 2, 21, 12 + w / 2)], ['m', tri([2, 12], [11, 3.4], [11, 20.6])]],
  arrowUp: (w) => [['m', rect(12 - w / 2, 8, 12 + w / 2, 21)], ['m', tri([12, 2], [3.4, 11], [20.6, 11])]],
  arrowDown: (w) => [['m', rect(12 - w / 2, 3, 12 + w / 2, 16)], ['m', tri([12, 22], [3.4, 13], [20.6, 13])]],
  caretDown: () => [['m', tri([4, 8], [20, 8], [12, 17])]], caretUp: () => [['m', tri([4, 16], [20, 16], [12, 7])]],
  check: (w) => [['m', path([[4, 12.5], [9, 17.5], [20, 6]], w * 1.1)]],
  checkCircle: () => [['p', ell(12, 12, 10, 10)], ['a', path([[7, 12.5], [10.4, 16], [17, 8.6]], 3)]],
  search: (w) => [['m', ring(10, 10, 8, 8 - w * 0.9)], ['m', thick(15.5, 15.5, 21, 21, w)]],
  sort: (w) => [['m', rect(6, 9, 6 + w * 0.6, 20)], ['m', tri([7.5, 3], [2, 10], [13, 10])], ['m', rect(16.4, 4, 16.4 + w * 0.6, 15)], ['m', tri([18, 21], [12.4, 14], [23.6, 14])]],
  filter: () => [['m', poly([[3, 4], [21, 4], [14, 12], [14, 20], [10, 18], [10, 12]])]],
  starO: () => [['m', minus(star(12, 12.6, 10.6, 4.6), star(12, 13, 6, 2.6))]],
  swapH: (w) => [['m', rect(3, 7 - w / 2, 16, 7 + w / 2)], ['m', tri([22, 7], [15, 2], [15, 12])], ['m', rect(8, 17 - w / 2, 21, 17 + w / 2)], ['m', tri([2, 17], [9, 12], [9, 22])]],
  refresh: (w) => { const pts = []; for (let t = -1.1; t <= 3.7; t += 0.15) pts.push([12 + 7.6 * Math.cos(t), 12 + 7.6 * Math.sin(t)]); return [['m', path(pts, w)], ['m', tri([21, 4], [21, 13], [12, 10])]]; },
  info: () => [['p', ell(12, 12, 10, 10)], ['a', ell(12, 7, 1.6, 1.6)], ['a', rect(10.6, 10, 13.4, 18)]],
  help: () => [['p', ell(12, 12, 10, 10)], ['a', path([[8.4, 9], [8.8, 6.6], [12, 5.6], [15.2, 6.8], [15.4, 9], [12, 12.4], [12, 14]], 2.4)], ['a', ell(12, 17.6, 1.5, 1.5)]],
  error: () => [['p', ell(12, 12, 10, 10)], ['a', rect(10.6, 5, 13.4, 14)], ['a', ell(12, 17.4, 1.6, 1.6)]],
  question: () => [['m', path([[7, 8], [7.6, 4.4], [12, 3], [16.4, 4.6], [17, 8.6], [12, 13], [12, 15.4]], 3.2)], ['m', ell(12, 20, 2, 2)]],
  eye: () => [['m', ell(12, 12, 10.6, 6.6)], ['a', ell(12, 12, 4, 4)]],
  eyeOff: () => [['m', ell(12, 12, 10.6, 6.6)], ['a', ell(12, 12, 4, 4)], ['x', thick(3, 20, 21, 4, 2.6)]],
  pencil: () => [['m', thick(6, 18, 17, 7, 4.4)], ['a', tri([3, 21], [4.4, 14.6], [9.4, 19.6])], ['x', thick(18.4, 5.6, 20.4, 3.6, 3.6)]],
  picture: () => [['m', rect(2, 4, 22, 20)], ['a', rect(4, 6, 20, 18)], ['g', poly([[4, 18], [9, 11], [13, 16], [16, 13], [20, 18]])], ['s', ell(16, 9.4, 2, 2)]],
  chart: () => [['m', rect(4, 12, 8.4, 20)], ['m', rect(10, 7, 14.4, 20)], ['m', rect(16, 3, 20.4, 20)]],
  chartBars: () => [['g', rect(4, 12, 8.4, 20)], ['s', rect(10, 7, 14.4, 20)], ['b', rect(16, 3, 20.4, 20)]],
  grid: () => [['m', rect(3, 3, 10.6, 10.6)], ['m', rect(13.4, 3, 21, 10.6)], ['m', rect(3, 13.4, 10.6, 21)], ['m', rect(13.4, 13.4, 21, 21)]],
  hex: (w) => [['m', minus(hexagon(10.6), hexagon(10.6 - w * 1.1))]],
  drag: (w) => [['m', rect(3, 5 - w / 2 + 0.6, 21, 5 + w / 2 + 0.6)], ['m', rect(3, 12 - w / 2, 21, 12 + w / 2)], ['m', rect(3, 19 - w / 2 - 0.6, 21, 19 + w / 2 - 0.6)]],
  move: (w) => [['m', rect(12 - w / 2, 4, 12 + w / 2, 20)], ['m', rect(4, 12 - w / 2, 20, 12 + w / 2)], ['m', tri([12, 1], [8, 6], [16, 6])], ['m', tri([12, 23], [8, 18], [16, 18])], ['m', tri([1, 12], [6, 8], [6, 16])], ['m', tri([23, 12], [18, 8], [18, 16])]],
  box: (w) => [['m', minus(rect(3, 3, 21, 21), rect(3 + w * 0.8, 3 + w * 0.8, 21 - w * 0.8, 21 - w * 0.8))]],
  boxOn: (w) => [['m', minus(rect(3, 3, 21, 21), rect(3 + w * 0.8, 3 + w * 0.8, 21 - w * 0.8, 21 - w * 0.8))], ['g', path([[7, 12.4], [10.4, 16], [17, 8.6]], 2.8)]],
  ring: (w) => [['m', ring(12, 12, 10, 10 - w * 0.9)]],
  vibration: () => [['m', rect(8, 2, 16, 22)], ['a', rect(9.6, 4.4, 14.4, 17.4)], ['m', path([[4, 8], [3, 12], [4, 16]], 1.8)], ['m', path([[20, 8], [21, 12], [20, 16]], 1.8)]],
  volume: () => [['m', poly([[3, 9], [8, 9], [14, 4], [14, 20], [8, 15], [3, 15]])], ['m', path([[17, 8.6], [19, 12], [17, 15.4]], 2)], ['m', path([[19.4, 5], [22.4, 12], [19.4, 19]], 2)]],
  wifiOff: () => [['m', path([[3, 9], [8, 5], [16, 5], [21, 9]], 2.4)], ['m', path([[6.4, 13], [10, 10.4], [14, 10.4], [17.6, 13]], 2.4)], ['m', ell(12, 17, 2, 2)], ['x', thick(3, 21, 21, 3, 2.6)]],
  play: () => [['m', tri([6, 3], [21, 12], [6, 21])]], playBack: () => [['m', tri([18, 3], [3, 12], [18, 21])]],
  forward: () => [['m', tri([2, 4], [12, 12], [2, 20])], ['m', tri([12, 4], [22, 12], [12, 20])]], rewind: () => [['m', tri([22, 4], [12, 12], [22, 20])], ['m', tri([12, 4], [2, 12], [12, 20])]],
  pause: () => [['m', rect(5, 4, 10.4, 20)], ['m', rect(13.6, 4, 19, 20)]],
  dot: () => [['p', ell(12, 12, 8, 8)]], dotBlue: () => [['p', ell(12, 12, 8, 8)]],
};
const PCOL = { checkCircle: 'green', info: 'blue', help: 'blue', error: 'red', dot: 'red', dotBlue: 'blue' };
const ACOL = { checkCircle: 'face', info: 'face', help: 'face', error: 'face', eye: 'black', eyeOff: 'black', picture: 'cyan', pencil: 'bolt', vibration: 'black', boxOn: 'green' };

// treatments: [name, desc, opts]
const TR = [
  ['Eisweiß', 'Wie bisher', { col: 'ice', w: 4 }],
  ['Gold', 'Goldene Glyphe', { col: 'gold', w: 4 }],
  ['Blaues Plättchen', 'Eisweiß auf Blau', { col: 'ice', w: 4, plate: 'sq', pc: 'blue' }],
  ['Roter Knopf', 'Rund, Rot', { col: 'ice', w: 4, plate: 'circ', pc: 'red' }],
  ['Stahl', 'Stahlgrau', { col: 'steel', w: 4 }],
  ['Fein', 'Dünne Striche', { col: 'ice', w: 2.2 }],
  ['Fett', 'Dicke Striche', { col: 'ice', w: 5.4 }],
  ['Grün', 'Grüne Glyphe', { col: 'green', w: 4 }],
  ['Holzplatte', 'Auf Holz', { col: 'face', w: 4, plate: 'sq', pc: 'wood' }],
  ['Dunkles Plättchen', 'Gold auf Eisen', { col: 'gold', w: 4, plate: 'sq', pc: 'iron' }],
];
const draw = (c, kind, t) => {
  const k = t.plate ? 0.62 : 1;
  if (t.plate === 'sq') c.shape(poly([[2, 4], [4, 2], [20, 2], [22, 4], [22, 20], [20, 22], [4, 22], [2, 20]]), t.pc, 'diag');
  if (t.plate === 'circ') c.shape(ell(12, 12, 10.6, 10.6), t.pc, 'orb');
  for (const [role, m, r] of GL[kind](t.w)) {
    const mm = k === 1 ? m : sc(m, k);
    if (role === 'm') c.shape(mm, t.col, 'diag');
    else if (role === 'p') c.shape(mm, t.col === 'ice' || t.plate ? PCOL[kind] : t.col, 'orb');
    else if (role === 'a') c.shape(mm, ACOL[kind] || 'face', 'flat');
    else if (role === 'x') c.shape(mm, kind === 'pencil' ? 'red' : 'red', 'flat');
    else if (role === 'g') c.shape(mm, 'green', 'diag');
    else if (role === 's') c.shape(mm, 'bolt', 'orb');
    else if (role === 'b') c.shape(mm, 'blue', 'diag');
  }
};
const designs = (kinds) => TR.map(([n, d, t]) => [n, d, (c, kind) => draw(c, kind || kinds[0], t)]);
const fam = (key, name, kinds) => ({ cat: 'Bedienelemente', key, name, designs: designs(kinds), outs: kinds.map((k) => [k, k, k, null]) });
const CONCEPTS = [
  fam('plus', 'Plus, Minus, Schließen', ['plus', 'minus', 'x']),
  fam('left', 'Winkel (links, rechts, hoch, runter)', ['left', 'right', 'up', 'down']),
  fam('arrowLeft', 'Pfeile (vier Richtungen)', ['arrowLeft', 'arrowRight', 'arrowUp', 'arrowDown']),
  fam('caretUp', 'Dreieck (hoch, runter)', ['caretUp', 'caretDown']),
  fam('check', 'Haken', ['check', 'checkCircle']),
  fam('search', 'Suche', ['search']),
  fam('sort', 'Sortieren', ['sort']),
  fam('filter', 'Filter', ['filter']),
  fam('starO', 'Stern-Umriss', ['starO']),
  fam('swapH', 'Tauschen', ['swapH']),
  fam('refresh', 'Neu laden', ['refresh']),
  fam('info', 'Hinweise (Info, Hilfe, Fehler, Frage)', ['info', 'help', 'error', 'question']),
  fam('eye', 'Auge (an, aus)', ['eye', 'eyeOff']),
  fam('pencil', 'Stift', ['pencil']),
  fam('picture', 'Bild', ['picture']),
  fam('chart', 'Diagramm', ['chart', 'chartBars']),
  fam('grid', 'Raster', ['grid']),
  fam('hex', 'Sechseck', ['hex']),
  fam('drag', 'Menü / Ziehen', ['drag']),
  fam('move', 'Verschieben', ['move']),
  fam('box', 'Kästchen', ['box', 'boxOn', 'ring']),
  fam('vibration', 'Vibration', ['vibration']),
  fam('volume', 'Lautstärke', ['volume']),
  fam('wifiOff', 'Keine Verbindung', ['wifiOff']),
  fam('play', 'Wiedergabe', ['play', 'playBack', 'forward', 'rewind', 'pause']),
  fam('dot', 'Punkt (rot, blau)', ['dot', 'dotBlue']),
];
module.exports = { CONCEPTS };
