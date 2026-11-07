// Redrawn icons for the realistic fantasy style (user 2026-11-04, "Weg 2": the
// ~25 icons you see all the time get new, more detailed shapes). They REPLACE the
// entries of the same key from icons_base / icons_extra when ICON_STYLE=fantasy.
// Roles painted in this order: a, b, d, e, k, c  (c = highlight / accent).
const { S, C } = require('./icons_base.js');

const circ = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const rect = (x, y, w, h, rx = 0) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}"/>`;
const poly = (p) => `<polygon points="${p}"/>`;
const rot = (deg, inner, cx = 32, cy = 32) => `<g transform="rotate(${deg} ${cx} ${cy})">${inner}</g>`;
const ring = (r, w) => `<circle cx="32" cy="32" r="${r}" fill="none" stroke="#000" stroke-width="${w}"/>`;

const FANTASY = {
  // A struck gold coin: raised rim, a pressed star, a worn highlight.
  coin: C({ a: '#e2b640', b: '#b7852a', d: '#f6dc7e', k: '#8a5f1a', c: '#fff1b8' }, {
    a: circ(32, 32, 28),
    b: ring(22.5, 3.2),
    d: poly('32,18 35.6,27.6 45.5,28 37.8,34.2 40.4,43.6 32,38.2 23.6,43.6 26.2,34.2 18.5,28 28.4,27.6'),
    k: ring(27, 2),
    c: S('M12 27C15 17 22 11 32 9', 3),
  }),

  // Two stacked logs with the end grain showing.
  wood: C({ a: '#7a4e2a', b: '#d8b078', d: '#a8763d', k: '#4a2c14', c: '#b07c45' }, {
    a: rect(3, 8, 42, 23, 7) + rect(14, 34, 42, 23, 7),
    b: circ(44, 19.5, 11.5) + circ(54, 45.5, 11.5),
    d: `<g fill="none" stroke="#000" stroke-width="2"><circle cx="44" cy="19.5" r="7"/><circle cx="44" cy="19.5" r="3"/><circle cx="54" cy="45.5" r="7"/><circle cx="54" cy="45.5" r="3"/></g>`,
    k: S('M9 14H33M9 25H30M20 40H44M20 51H40', 2),
    c: S('M8 12H26', 2) + S('M19 38H36', 2),
  }),

  // A faceted granite block: lit facet, shaded facet, a crack.
  stone: C({ a: '#8b8f96', b: '#5c6068', d: '#b9bdc5', k: '#3d4046', c: '#e0e3e8' }, {
    a: '<path d="M5 46L10 24L26 8L47 12L59 28L55 50L36 59L14 57Z"/>',
    b: '<path d="M47 12L59 28L55 50L36 59L39 38L35 22Z"/>',
    d: '<path d="M10 24L26 8L47 12L35 22L18 31Z"/>',
    k: S('M35 22L39 38L30 47L24 56', 2) + S('M18 31L22 40', 1.6),
    c: S('M15 22L25 13', 2.4),
  }),

  // A river fish: shaded back, pale belly, dorsal fin and tail, scale arcs.
  fish: C({ a: '#5f9fb5', b: '#3f6f86', d: '#d8e4e6', k: '#16222b', c: '#ffffff' }, {
    a: '<path d="M3 32C11 17 30 13 45 24L61 11V53L45 40C30 51 11 47 3 32Z"/>',
    b: '<path d="M21 17L30 6L40 21Z"/><path d="M45 24L61 11V53L45 40L51 32Z"/><path d="M28 44L34 56L40 42Z"/>',
    d: '<path d="M6 35C16 44 31 47 45 40L41 36C28 41 14 39 6 35Z"/>',
    k: circ(13.5, 29.5, 3) + S('M24 27C28 30 28 34 24 37M32 25C36 29 36 35 32 39', 1.6),
    c: circ(14.5, 28.5, 1.1) + S('M12 24C17 20 24 19 30 20', 2),
  }),

  // The housing icon: a timber-framed house (see icons_extra for its first draft).
  timberHouse: C({ a: '#f1e6c9', b: '#c4552b', d: '#8d8a82', k: '#5b3a1e', c: '#ffd27a' }, {
    a: poly('10,34 32,16 54,34 54,56 10,56'),
    b: '<path d="M1 34L32 5L63 34L56 38L32 16L8 38Z"/>',
    d: rect(7, 56, 50, 6, 1) + rect(44, 8, 8, 14, 1),
    k: S('M10 35V56M32 16V56M54 35V56M10 46H54M10 46L21 36M54 46L43 36', 2.4) + rect(27, 46, 10, 10, 1),
    c: rect(13, 48, 9, 6) + rect(42, 48, 9, 6),
  }),

  // Lightning: a lit face and a shaded one.
  bolt: C({ a: '#f4cf45', b: '#c9921d', d: '#fff0a0', k: '#8a5f1a', c: '#fffbe0' }, {
    a: poly('38,2 12,36 27,36 21,62 52,24 35,24'),
    b: poly('35,24 52,24 21,62 27,36'),
    d: poly('38,2 31,12 24,28 30,28'),
    c: S('M30 9L19 30', 2.4),
  }),

  // A navigator's compass: brass ring, aged face, red and pale needle.
  compass: C({ a: '#e8dcc0', b: '#b6372a', d: '#e9e2d0', e: '#5b3a1e', k: '#b98a3c', c: '#fff6dc' }, {
    a: circ(32, 32, 26),
    b: poly('32,8 38,32 26,32'),
    d: poly('32,56 38,32 26,32'),
    e: S('M32 5V10M32 54V59M5 32H10M54 32H59', 2.6) + circ(32, 32, 3),
    k: ring(27, 5),
    c: S('M13 22C16 15 22 11 28 9', 2.4),
  }),

  // A smith's hammer: wooden haft, steel head with a bright edge, two bands.
  hammer: C({ a: '#7a4e2a', b: '#8e97a3', d: '#c9d2dc', k: '#3d4046', c: '#e9eef3' }, {
    a: rot(-40, rect(28, 22, 8, 40, 3)),
    b: rot(-40, rect(6, 6, 46, 18, 3)),
    d: rot(-40, rect(9, 9, 40, 4, 2)),
    k: rot(-40, rect(26, 24, 12, 4)) + rot(-40, rect(24, 6, 3, 18)) + rot(-40, rect(37, 6, 3, 18)),
    c: rot(-40, rect(10, 9, 14, 2)),
  }),

  // A longsword: fullered blade, gilt guard with a jewel, wrapped grip.
  sword: C({ a: '#aab4c0', b: '#c9a24a', d: '#e6ecf2', e: '#5c6672', k: '#5b3a1e', c: '#d9463a' }, {
    a: rot(45, poly('32,0 38,9 38,40 26,40 26,9')),
    b: rot(45, rect(14, 40, 36, 7, 3) + circ(32, 62, 4.5)),
    d: rot(45, rect(28, 7, 3, 32)),
    e: rot(45, rect(31.5, 7, 2, 32)),
    k: rot(45, rect(29, 47, 6, 12, 2)),
    c: rot(45, circ(32, 43.5, 2.6)),
  }),

  // A heater shield: gilt rim, a lit and a shaded half, a cross.
  shield: C({ a: '#3d5f98', b: '#c9a24a', d: '#5f86c4', e: '#27406e', k: '#1d2f66', c: '#ecd27a' }, {
    a: '<path d="M32 4L56 12V32C56 47 45 57 32 62C19 57 8 47 8 32V12Z"/>',
    b: '<path d="M32 4L56 12V32C56 47 45 57 32 62C19 57 8 47 8 32V12Z" fill="none" stroke="#000" stroke-width="4"/>',
    d: '<path d="M32 8L12 14.5V32C12 44 21 53 32 58Z"/>',
    e: '<path d="M32 8L52 14.5V32C52 44 43 53 32 58Z"/>',
    k: S('M32 8V58', 1.5),
    c: rect(29, 17, 6, 34, 1) + rect(19, 27, 26, 6, 1),
  }),

  // A parchment map: a coast, a folded middle, a dotted route and a red X.
  map: C({ a: '#e6d6a6', b: '#cdb87f', d: '#7fb0c8', k: '#8a5a30', c: '#c8362b' }, {
    a: '<path d="M3 11L22 4L42 11L61 4V54L42 61L22 54L3 61Z"/>',
    b: '<path d="M22 4L42 11V61L22 54Z"/>',
    d: '<path d="M3 11L22 4V22C14 24 8 22 3 26Z"/>',
    k: S('M9 44C16 36 22 48 30 38S44 36 54 24', 1.8),
    c: S('M44 14L54 24M54 14L44 24', 3.6),
  }),

  // A bell: gilt body, shaded side, a bright rim and clapper.
  bell: C({ a: '#e1ae3a', b: '#a8761c', d: '#f4d36e', k: '#6b4616', c: '#fff0b0' }, {
    a: '<path d="M32 7C42 7 48 17 48 29C48 39 54 45 58 51H6C10 45 16 39 16 29C16 17 22 7 32 7Z"/>',
    b: '<path d="M32 7C42 7 48 17 48 29C48 39 54 45 58 51H46C48 40 43 19 32 7Z"/>',
    d: rect(6, 48, 52, 5, 2),
    k: circ(32, 5.5, 3.6) + circ(32, 58, 5.5),
    c: S('M22 26C23 18 26 13 30 11', 3),
  }),
};

module.exports = { FANTASY };
