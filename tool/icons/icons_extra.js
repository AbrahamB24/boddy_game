// Icons for everything that used to be an emoji: resources, rewards, status
// effects, actions. Each entry: C(palette, layers) + the emoji it replaces
// (see EMOJI at the bottom). viewBox 0..64, roles a b k c (c = highlight/accent).
const { S, C, dot } = require('./icons_base.js');

const circ = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const rect = (x, y, w, h, rx = 0) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}"/>`;
const poly = (p) => `<polygon points="${p}"/>`;
const rot = (deg, inner, cx = 32, cy = 32) => `<g transform="rotate(${deg} ${cx} ${cy})">${inner}</g>`;
const heartPath = 'M32 58C10 42 5 30 5 21C5 12 12 7 19 7C25 7 29 10 32 15C35 10 39 7 45 7C52 7 59 12 59 21C59 30 54 42 32 58Z';

const rock = (a, b, c, fleck, fl2) => C({ a, b, c, k: fl2 || fleck }, {
  a: '<path d="M6 46L12 24L30 10L50 16L59 36L52 54H12Z"/>',
  b: '<path d="M30 10L50 16L59 36L52 54H34L42 32Z"/>',
  c: '<path d="M14 26L30 13L37 15L22 31Z"/>',
  k: circ(22, 42, 3) + circ(40, 44, 3.5) + circ(32, 30, 2.5),
});
const pile = (a, b, c, k) => C({ a, b, c, k }, {
  a: '<path d="M3 54C8 38 20 22 32 22C44 22 56 38 61 54Z"/>',
  b: '<path d="M32 22C44 22 56 38 61 54H40C42 40 38 28 32 22Z"/>',
  c: S('M14 42C18 34 24 29 30 27', 3.5),
  k: circ(22, 48, 1.8) + circ(34, 44, 1.8) + circ(46, 49, 1.8),
});
const gem = (a, b, c) => C({ a, b, c, k: b }, {
  a: poly('14,8 50,8 62,24 32,60 2,24'),
  b: poly('32,60 62,24 46,24 32,60') + poly('2,24 18,24 32,60'),
  c: poly('14,8 22,8 18,24 2,24') + poly('42,8 50,8 62,24 46,24'),
  k: S('M18 24H46M22 8L32 24L42 8', 1.8),
});
const faceBase = '<circle cx="32" cy="32" r="27"/>';
const swordOne = (deg) => rot(deg,
  poly('28,2 36,2 36,38 32,44 28,38'),
  32, 32);

const ICONS_EXTRA = {
  coin: C({ a: '#f5c542', b: '#c98f1e', c: '#fff3b0', k: '#a8741a' }, {
    a: circ(32, 32, 27), b: '<circle cx="32" cy="32" r="27" fill="none" stroke="#000" stroke-width="5"/>',
    k: S('M32 16V48M25 24C25 19 39 19 39 26C39 33 25 31 25 38C25 45 39 45 39 40', 3.5), c: S('M15 22C18 16 23 12 28 10', 3.5) }),
  wood: C({ a: '#b9814a', b: '#e6c28a', c: '#d9a468', k: '#6b4129' }, {
    a: rect(4, 8, 44, 22, 9) + rect(8, 32, 44, 24, 9),
    b: '<ellipse cx="48" cy="19" rx="9" ry="11"/><ellipse cx="52" cy="44" rx="9" ry="12"/>',
    k: '<ellipse cx="48" cy="19" rx="4" ry="5.5" fill="none" stroke="#000" stroke-width="2.2"/><ellipse cx="52" cy="44" rx="4" ry="6" fill="none" stroke="#000" stroke-width="2.2"/>' + S('M12 16H32M14 40H36', 2.5),
    c: S('M12 13H34M14 37H38', 2.5) }),
  stone: rock('#9a968c', '#6e6a62', '#d4d0c4', '#5e5a52'),
  ironOre: C({ a: '#4a4f58', b: '#2f333a', c: '#8a93a0', k: '#c9d1dc' }, {
    a: '<path d="M6 46L12 24L30 10L50 16L59 36L52 54H12Z"/>', b: '<path d="M30 10L50 16L59 36L52 54H34L42 32Z"/>',
    c: '<path d="M14 26L30 13L37 15L22 31Z"/>', k: circ(22, 42, 3.5) + circ(40, 44, 3) + circ(30, 32, 2.5) + circ(44, 28, 2) }),
  copperOre: C({ a: '#8a5a3a', b: '#5e3b24', c: '#c58a5a', k: '#e8903f' }, {
    a: '<path d="M6 46L12 24L30 10L50 16L59 36L52 54H12Z"/>', b: '<path d="M30 10L50 16L59 36L52 54H34L42 32Z"/>',
    c: '<path d="M14 26L30 13L37 15L22 31Z"/>', k: circ(22, 42, 3.5) + circ(40, 44, 3) + circ(30, 32, 2.5) + circ(44, 28, 2) }),
  silverOre: C({ a: '#8f939b', b: '#62666e', c: '#cfd3da', k: '#f4f7fb' }, {
    a: '<path d="M6 46L12 24L30 10L50 16L59 36L52 54H12Z"/>', b: '<path d="M30 10L50 16L59 36L52 54H34L42 32Z"/>',
    c: '<path d="M14 26L30 13L37 15L22 31Z"/>', k: circ(22, 42, 3.5) + circ(40, 44, 3) + circ(30, 32, 2.5) + circ(44, 28, 2) }),
  goldOre: C({ a: '#7d6f4a', b: '#574c31', c: '#b4a572', k: '#f7cc3d' }, {
    a: '<path d="M6 46L12 24L30 10L50 16L59 36L52 54H12Z"/>', b: '<path d="M30 10L50 16L59 36L52 54H34L42 32Z"/>',
    c: '<path d="M14 26L30 13L37 15L22 31Z"/>', k: circ(22, 42, 4) + circ(40, 44, 3.5) + circ(30, 32, 3) + circ(44, 28, 2.5) }),
  coal: C({ a: '#3a3d44', b: '#23252a', c: '#6a6f7a', k: '#101114' }, {
    a: '<path d="M8 50L10 28L26 14L44 18L58 32L54 52H14Z"/>', b: '<path d="M26 14L44 18L58 32L54 52H36L40 30Z"/>',
    c: '<path d="M13 30L26 17L33 19L20 33Z"/>', k: S('M20 44L30 40M40 46L48 40', 2) }),
  clay: pile('#b5683a', '#8a4a26', '#dc9468', '#7a3f20'),
  lime: pile('#ece8dc', '#c3beae', '#ffffff', '#a9a392'),
  sand: pile('#e8c76a', '#c49a3a', '#fff0b0', '#a67c20'),
  ruby: gem('#e0384b', '#a81f35', '#ff9aa6'),
  gem: gem('#6fc7ea', '#3f8fc0', '#d8f4ff'),
  crystalBlue: C({ a: '#4a8fe0', b: '#2f64b0', c: '#a8cdf8', k: '#1d3f80' }, {
    a: poly('32,2 48,22 40,60 24,60 16,22'), b: poly('32,2 48,22 40,60 34,60 34,18'),
    c: poly('32,6 22,22 24,56 28,26'), k: poly('16,22 48,22 44,26 20,26') }),
  crystalCyan: C({ a: '#46d0d8', b: '#2896a4', c: '#c4f6f8', k: '#1b6470' }, {
    a: poly('32,2 60,32 32,62 4,32'), b: poly('32,2 60,32 32,62 32,32'),
    c: poly('32,7 12,32 24,30'), k: S('M4 32H60M32 2V62', 1.8) }),
  brick: C({ a: '#c4623a', b: '#9a4426', c: '#e89a72', k: '#e8d6b8' }, {
    a: rect(4, 12, 56, 40, 3), b: rect(4, 42, 56, 10, 3),
    k: '<path d="M4 25H60M4 38H60M22 12V25M42 25V38M22 38V52" fill="none" stroke="#000" stroke-width="2.8"/>', c: rect(7, 14, 24, 3) }),
  nut: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#3a4350' }, {
    a: poly('32,2 56,16 56,46 32,60 8,46 8,16'), b: poly('32,60 56,46 56,16 44,24 44,48'),
    k: circ(32, 31, 11), c: poly('32,5 12,17 12,24 32,12') }),
  frame: C({ a: '#b9814a', b: '#7a4a22', c: '#e0b27a', k: '#5a3a1a' }, {
    a: '<path d="M4 8H60V56H4Z"/>', b: rect(4, 8, 8, 48) + rect(52, 8, 8, 48) + rect(4, 8, 56, 8) + rect(4, 48, 56, 8),
    k: S('M12 16L52 48M52 16L12 48', 5), c: circ(32, 32, 3) }),
  saw: C({ a: '#aab4c0', b: '#6f7b89', c: '#eef3f8', k: '#7a4a22' }, {
    a: '<path d="M4 18H44L38 26L33 20L28 28L22 20L16 28L10 20L4 26Z"/>', b: '<path d="M4 18H44V22H4Z"/>',
    k: '<path d="M44 12H62V30H44Z"/>', c: rect(8, 19, 30, 2) }),
  axe: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#7a4a22' }, {
    k: rot(35, rect(29, 6, 6, 56, 2)), a: rot(35, '<path d="M32 6C46 4 52 14 52 22C52 30 46 34 32 32Z"/>'),
    b: rot(35, '<path d="M32 26C46 28 52 24 52 22C52 30 46 34 32 32Z"/>'), c: rot(35, S('M36 10C44 10 48 14 48 18', 2.6)) }),
  pickaxe: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#7a4a22' }, {
    k: rot(40, rect(29, 6, 6, 56, 2)), a: rot(40, '<path d="M4 20C14 4 50 4 60 20C48 12 40 12 36 14H28C24 12 16 12 4 20Z"/>'),
    b: rot(40, '<path d="M28 14H36L36 20H28Z"/>'), c: rot(40, S('M12 17C22 10 42 10 52 17', 2.2)) }),
  wrench: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#3a4350' }, {
    a: rot(-40, '<path d="M24 4H40V16C44 18 46 22 46 26H18C18 22 20 18 24 16Z"/>' + rect(27, 24, 10, 36, 4)),
    k: rot(-40, rect(30, 6, 4, 10)), c: rot(-40, rect(29, 28, 3, 28)) }),
  scissors: C({ a: '#9aa6b4', b: '#d9463a', c: '#e4ebf2', k: '#3a4350' }, {
    a: poly('8,6 36,36 30,42 4,12') + poly('56,6 28,36 34,42 60,12'), b: '<circle cx="14" cy="50" r="9"/><circle cx="50" cy="50" r="9"/>',
    k: '<circle cx="14" cy="50" r="4"/><circle cx="50" cy="50" r="4"/>', c: S('M10 8L30 30', 2) }),
  tools: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#7a4a22' }, {
    k: rot(45, rect(29, 20, 6, 42, 2)) + rot(-45, rect(29, 20, 6, 42, 2)),
    a: rot(45, rect(14, 4, 36, 16, 3)) + rot(-45, '<path d="M26 4H38V14C42 16 44 20 44 24H20C20 20 22 16 26 14Z"/>'),
    c: rot(45, rect(17, 7, 30, 3)), b: rot(45, rect(14, 15, 36, 5)) }),
  swords: C({ a: '#cfd8e3', b: '#e0b13a', k: '#7a4a22', c: '#ffffff' }, {
    a: rot(45, poly('28,0 36,0 36,40 32,46 28,40')) + rot(-45, poly('28,0 36,0 36,40 32,46 28,40')),
    b: rot(45, rect(21, 42, 22, 5, 2) + circ(32, 62, 3.5)) + rot(-45, rect(21, 42, 22, 5, 2) + circ(32, 62, 3.5)),
    k: rot(45, rect(29.5, 47, 5, 12, 2)) + rot(-45, rect(29.5, 47, 5, 12, 2)),
    c: rot(45, rect(31, 4, 2, 32)) + rot(-45, rect(31, 4, 2, 32)) }),
  crown: C({ a: '#f2c13a', b: '#c98f1e', c: '#fff1a8', k: '#d9463a' }, {
    a: '<path d="M6 48L4 14L20 28L32 8L44 28L60 14L58 48Z"/>', b: rect(6, 44, 52, 10, 3),
    k: circ(32, 36, 4.5) + circ(14, 38, 3) + circ(50, 38, 3), c: S('M10 22L14 40', 3) }),
  heartPink: C({ a: '#f472b6', b: '#c2488a', c: '#ffd0ea', k: '#000' }, {
    a: `<path d="${heartPath}"/>`, b: '<path d="M32 58C46 48 56 38 58 26C52 40 44 46 32 50Z"/>', c: circ(18, 20, 4.5) }),
  heartGreen: C({ a: '#43c06a', b: '#2a8d4a', c: '#b8f2c8', k: '#000' }, {
    a: `<path d="${heartPath}"/>`, b: '<path d="M32 58C46 48 56 38 58 26C52 40 44 46 32 50Z"/>', c: circ(18, 20, 4.5) }),
  hearts: C({ a: '#e0384b', b: '#f472b6', c: '#ffd0ea', k: '#000' }, {
    b: `<g transform="translate(22 0) scale(.62)"><path d="${heartPath}"/></g>`,
    a: `<g transform="translate(-2 14) scale(.72)"><path d="${heartPath}"/></g>`, c: circ(12, 30, 3) }),
  trap: C({ a: '#c89a5a', b: '#9aa6b4', c: '#f5c542', k: '#5a3a1a' }, {
    a: rect(4, 28, 56, 30, 4), b: S('M10 38C10 10 54 10 54 38', 4.5),
    c: poly('34,46 54,46 54,56 34,56'), k: S('M14 40H30M20 34V46', 3) }),
  bandage: C({ a: '#f0c9a0', b: '#ffffff', c: '#d9a070', k: '#c08a5a' }, {
    a: rot(-45, rect(2, 20, 60, 24, 12)), b: rot(-45, rect(22, 20, 20, 24)),
    k: rot(-45, circ(32, 28, 1.6) + circ(32, 36, 1.6) + circ(27, 32, 1.6) + circ(37, 32, 1.6)), c: rot(-45, rect(6, 23, 12, 3, 1.5)) }),
  stethoscope: C({ a: '#5a6672', b: '#9aa6b4', c: '#e4ebf2', k: '#2a323c' }, {
    a: S('M14 6V28C14 40 32 40 32 28V6', 4.5) + S('M32 38V44C32 52 40 54 46 54', 4.5),
    b: '<circle cx="48" cy="48" r="11"/>', k: circ(48, 48, 5), c: circ(14, 6, 3) + circ(32, 6, 3) }),
  syringe: C({ a: '#e8eef4', b: '#9aa6b4', c: '#e0384b', k: '#3a4350' }, {
    a: rot(45, rect(22, 12, 20, 34, 3)), b: rot(45, rect(18, 8, 28, 6, 2) + rect(30, 2, 4, 8) + rect(30, 46, 4, 14)),
    c: rot(45, rect(25, 26, 14, 18)), k: rot(45, S('M22 20H27M22 26H27M22 32H27', 1.8)) }),
  microscope: C({ a: '#6f7b89', b: '#3f6fd1', c: '#cfd8e3', k: '#3a4350' }, {
    a: rot(25, rect(24, 4, 12, 36, 3), 30, 24) + '<path d="M14 46C14 32 36 28 42 38V44H14Z"/>',
    b: rot(25, rect(22, 2, 16, 8, 2), 30, 24), k: rect(8, 54, 48, 7, 2) + rect(30, 46, 6, 10), c: S('M20 40H38', 2) }),
  dna: C({ a: '#3f9ad6', b: '#e0b13a', c: '#ffffff', k: '#2a323c' }, {
    a: S('M16 4C16 20 48 20 48 34S16 48 16 60', 6), b: S('M48 4C48 20 16 20 16 34S48 48 48 60', 6),
    k: S('M24 14H40M20 34H44M24 52H40', 3), c: circ(20, 8, 0.1) }),
  compass: C({ a: '#e8d6a8', b: '#8a5a30', c: '#d9463a', k: '#f5f0e0' }, {
    a: circ(32, 32, 27), b: '<circle cx="32" cy="32" r="27" fill="none" stroke="#000" stroke-width="5"/>',
    c: poly('32,10 38,32 26,32'), k: poly('32,54 26,32 38,32') }),
  cycle: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: S('M52 24A22 22 0 0 0 14 20', 7) + S('M12 40A22 22 0 0 0 50 44', 7),
    b: poly('56,6 56,28 34,26') + poly('8,58 8,36 30,38'), c: S('M20 14C26 10 32 9 38 10', 3) }),
  crane: C({ a: '#f0b429', b: '#c88a10', c: '#ffe08a', k: '#3a4350' }, {
    a: rect(8, 6, 8, 54) + rect(4, 6, 56, 8), b: '<path d="M8 14L16 24M16 14L8 24M8 24L16 34M16 24L8 34M8 34L16 44M16 44L8 54" fill="none" stroke="#000" stroke-width="2.4"/>',
    k: rect(40, 14, 3, 22) + rect(36, 36, 12, 10, 2) + rect(2, 56, 24, 6, 2), c: rect(10, 8, 4, 2) }),
  factory: C({ a: '#a89f90', b: '#7a7266', c: '#f5d98a', k: '#4a4338' }, {
    a: '<path d="M4 58V28L20 36V28L36 36V28L52 36V12H60V58Z"/>', b: rect(44, 6, 12, 22),
    k: rect(10, 44, 8, 10) + rect(24, 44, 8, 10) + rect(38, 44, 8, 10), c: rect(11, 45, 6, 4) + rect(25, 45, 6, 4) + rect(39, 45, 6, 4) }),
  castle: C({ a: '#b9b3a6', b: '#8a847a', c: '#e6e1d4', k: '#4a4338' }, {
    a: '<path d="M4 58V20H12V14H20V20H24V14H32V8H40V14H44V20H52V14H60V58Z"/>' .replace('M4 58V20H12V14H20V20H24V14H32V8H40V14H44V20H52V14H60V58Z', 'M4 58V18H14V24H20V18H28V24H36V18H44V24H50V18H60V58Z'),
    b: '<path d="M44 18H60V58H44Z"/>', k: '<path d="M26 58V44C26 38 38 38 38 44V58Z"/>', c: rect(8, 22, 3, 30) }),
  tent: C({ a: '#d9a05a', b: '#a87430', c: '#f0cf96', k: '#4a2f1a' }, {
    a: poly('32,6 62,56 2,56'), b: poly('32,6 62,56 40,56'), k: poly('32,30 42,56 22,56'), c: S('M30 12L10 50', 3) }),
  worker: C({ a: '#e8b98a', b: '#f0b429', c: '#ffe08a', k: '#e8742a' }, {
    a: circ(32, 30, 15), b: '<path d="M14 28C14 12 50 12 50 28Z"/>' + rect(10, 26, 44, 5, 2),
    k: '<path d="M8 62C8 48 18 44 32 44C46 44 56 48 56 62Z"/>', c: S('M22 18C26 14 34 14 38 16', 3) }),
  trash: C({ a: '#8fa0b0', b: '#6a7a8a', c: '#d4dde6', k: '#3a4350' }, {
    a: '<path d="M10 20H54L50 60H14Z"/>', b: rect(6, 10, 52, 8, 3) + rect(24, 4, 16, 8, 2),
    k: S('M24 28V52M32 28V52M40 28V52', 3.5), c: S('M14 24L16 36', 3) }),
  wind: C({ a: '#cfe6f6', b: '#8fc0e0', c: '#ffffff', k: '#000' }, {
    a: S('M6 24H40C52 24 52 8 40 10', 6) + S('M6 40H46C58 40 58 56 46 54', 6), b: S('M6 32H30C38 32 38 46 30 44', 5), c: S('M10 21H30', 2.5) }),
  drop: C({ a: '#3fa0e8', b: '#2672b8', c: '#bfe3ff', k: '#000' }, {
    a: '<path d="M32 4C44 22 54 32 54 42C54 54 44 61 32 61C20 61 10 54 10 42C10 32 20 22 32 4Z"/>',
    b: '<path d="M32 61C44 61 54 54 54 42C54 40 53 38 52 36C48 48 42 54 32 55Z"/>', c: S('M20 38C21 32 24 28 27 25', 3.5) }),
  blood: C({ a: '#d92b3a', b: '#9a1424', c: '#ff9aa2', k: '#000' }, {
    a: '<path d="M32 4C44 22 54 32 54 42C54 54 44 61 32 61C20 61 10 54 10 42C10 32 20 22 32 4Z"/>',
    b: '<path d="M32 61C44 61 54 54 54 42C54 40 53 38 52 36C48 48 42 54 32 55Z"/>', c: S('M20 38C21 32 24 28 27 25', 3.5) }),
  sprout: C({ a: '#5fae4a', b: '#3d7a38', c: '#a4e08a', k: '#7a4a22' }, {
    a: '<path d="M30 34C14 34 6 26 6 12C20 12 30 20 30 34Z"/><path d="M34 40C34 26 42 18 58 18C58 32 48 40 34 40Z"/>',
    b: '<path d="M30 34C30 20 20 12 6 12C22 16 26 26 30 34Z"/>', k: rect(29, 34, 6, 26, 3), c: S('M12 16C18 18 22 22 24 28', 2.5) }),
  herb: C({ a: '#5fae4a', b: '#3d7a38', c: '#a4e08a', k: '#4a3a22' }, {
    a: '<path d="M32 6C44 14 44 30 32 38C20 30 20 14 32 6Z"/><path d="M30 34C18 28 8 30 4 40C14 46 26 44 30 34Z"/><path d="M34 34C46 28 56 30 60 40C50 46 38 44 34 34Z"/>',
    b: '<path d="M32 6C44 14 44 30 32 38Z"/>', k: S('M32 36V60', 4), c: S('M32 12V32', 2) }),
  beaver: C({ a: '#8a5a3a', b: '#f5f0e0', c: '#c58a5a', k: '#2a1a10' }, {
    a: circ(32, 34, 25) + circ(11, 14, 8) + circ(53, 14, 8), b: rect(26, 44, 12, 14, 3) + '<ellipse cx="32" cy="40" rx="11" ry="8"/>',
    k: circ(22, 28, 3.5) + circ(42, 28, 3.5) + '<ellipse cx="32" cy="36" rx="5" ry="3.5"/>' + S('M32 46V57', 1.6), c: S('M16 22C18 16 24 13 30 12', 3) }),
  gi: C({ a: '#f4f0e6', b: '#cfc8b4', c: '#ffffff', k: '#2a2a2a' }, {
    a: '<path d="M18 6L32 20L46 6L62 18L52 30V58H12V30L2 18Z"/>', b: '<path d="M32 20L46 6L62 18L52 30V58H36Z"/>',
    k: rect(10, 38, 44, 7, 2), c: S('M14 14L24 26', 3) }),
  cart: C({ a: '#9aa6b4', b: '#6f7b89', c: '#e4ebf2', k: '#3a4350' }, {
    a: '<path d="M2 8H12L18 40H52L58 16H16Z"/>', b: S('M18 46H50', 4),
    k: circ(22, 55, 5) + circ(46, 55, 5), c: S('M20 22H54M22 30H52', 2.4) }),
  exchange: C({ a: '#43a047', b: '#f0b429', c: '#a8e6aa', k: '#000' }, {
    a: S('M8 22H48', 7) + poly('44,8 60,22 44,36'), b: S('M56 44H16', 7) + poly('20,30 4,44 20,58'), c: S('M12 18H34', 2.4) }),
  boom: C({ a: '#f08a24', b: '#ffd23a', c: '#fff3b0', k: '#d9462a' }, {
    a: poly('32,2 39,18 56,8 48,25 62,32 48,39 56,56 39,46 32,62 25,46 8,56 16,39 2,32 16,25 8,8 25,18'),
    b: poly('32,14 37,26 48,22 42,32 50,38 38,38 32,50 26,38 14,38 22,32 16,22 27,26'), c: poly('32,22 35,30 32,40 29,30') }),
  check: C({ a: '#43a047', b: '#2e7d32', c: '#a8e6aa', k: '#000' }, {
    a: S('M8 34L24 50L56 12', 11), b: S('M24 50L56 12', 11), c: S('M10 32L24 46', 3) }),
  arrowUp: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: poly('32,3 58,32 42,32 42,60 22,60 22,32 6,32'), b: poly('32,3 58,32 42,32 42,60 32,60'), c: S('M20 28L32 12', 3) }),
  play: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: poly('10,4 58,32 10,60'), b: poly('10,32 58,32 10,60'), c: S('M16 14L16 40', 3) }),
  playBack: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: poly('54,4 6,32 54,60'), b: poly('54,32 6,32 54,60'), c: S('M48 14L48 40', 3) }),
  forward: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: poly('2,8 30,32 2,56') + poly('32,8 60,32 32,56'), b: poly('2,32 30,32 2,56') + poly('32,32 60,32 32,56'), c: S('M7 18V34M37 18V34', 3) }),
  rewind: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: poly('62,8 34,32 62,56') + poly('32,8 4,32 32,56'), b: poly('62,32 34,32 62,56') + poly('32,32 4,32 32,56'), c: S('M57 18V34M27 18V34', 3) }),
  pause: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, {
    a: rect(10, 6, 18, 52, 4) + rect(36, 6, 18, 52, 4), b: rect(21, 6, 7, 52, 3) + rect(47, 6, 7, 52, 3), c: rect(13, 10, 3, 30) + rect(39, 10, 3, 30) }),
  chartBars: C({ a: '#3f9ad6', b: '#43a047', c: '#f0b429', k: '#3a4350' }, {
    a: rect(6, 34, 14, 24, 2), b: rect(25, 20, 14, 38, 2), c: rect(44, 6, 14, 52, 2), k: rect(2, 58, 60, 4, 2) }),
  snow: C({ a: '#bfe3ff', b: '#7fb8e8', c: '#ffffff', k: '#000' }, {
    a: S('M32 4V60M8 18L56 46M56 18L8 46', 5) , b: S('M24 8L32 14L40 8M24 56L32 50L40 56M6 28L14 28L12 20M58 36L50 36L52 44M6 36L14 36L12 44M58 28L50 28L52 20', 3.5), c: circ(32, 32, 4) }),
  moai: C({ a: '#8f8a7e', b: '#6a665c', c: '#c4bfb2', k: '#3a362e' }, {
    a: '<path d="M18 60V30C16 14 24 4 34 4C46 4 50 14 48 30V60Z"/>', b: '<path d="M34 4C46 4 50 14 48 30V60H38V20Z"/>',
    k: '<path d="M22 24H40V30H22Z"/><path d="M30 32L34 46L26 46Z"/>' + S('M26 52H42', 3), c: S('M22 14C24 10 28 8 32 8', 3) }),
  eye: C({ a: '#ffffff', b: '#3f9ad6', c: '#bfe3ff', k: '#1a1a1a' }, {
    a: '<path d="M2 32C14 12 50 12 62 32C50 52 14 52 2 32Z"/>', b: circ(32, 32, 13), k: circ(32, 32, 6.5), c: circ(27, 27, 3) }),
  snail: C({ a: '#e0c9a0', b: '#b9622e', c: '#e89a62', k: '#5a3a1a' }, {
    a: '<path d="M2 54C2 44 12 42 18 46L44 46V54Z"/><path d="M6 46V32" fill="none" stroke="#000" stroke-width="5"/>',
    b: circ(40, 30, 21), k: '<path d="M40 30m-12 0a12 12 0 1 1 12 12" fill="none" stroke="#000" stroke-width="3.5"/>' + circ(6, 28, 2.5), c: S('M28 20C30 14 36 11 42 11', 3) }),
  question: C({ a: '#8f9bb0', b: '#5f6b80', c: '#e4ebf2', k: '#000' }, {
    a: S('M20 20C20 6 44 6 44 20C44 32 32 32 32 42', 10) + circ(32, 55, 6), b: S('M44 20C44 32 32 32 32 42', 10), c: S('M24 16C26 12 30 11 33 11', 2.6) }),
  horse: C({ a: '#9a6340', b: '#6b4129', c: '#c28a63', k: '#1a1008' }, {
    a: '<path d="M20 60L24 36C14 30 8 20 14 10L22 2L26 12C34 10 44 16 46 28L50 60Z"/>', b: '<path d="M26 12L22 2L14 10L18 22Z"/><path d="M46 28L50 60H38L40 40Z"/>',
    k: circ(24, 22, 2.6) + circ(12, 24, 1.6), c: S('M20 8L26 18', 3) }),
  // A DRUMSTICK (user 2026-11-04: "Fleisch soll eine Fleischkeule werden"): the
  // round meat on top left, a shaded underside, the bone with its two knobs.
  meat: C({ a: '#c2552f', b: '#8f3a1f', k: '#f3ead2', c: '#f19a74' }, {
    a: '<path d="M6 26C6 12 18 3 31 5C46 7 53 21 47 33L40 40L34 46L24 41C13 39 6 34 6 26Z"/>',
    b: '<path d="M47 33L40 40L34 46L24 41C34 43 44 36 46 24C49 26 49 30 47 33Z"/>',
    k: S('M36 43L51 56', 6) + circ(49, 61, 4.6) + circ(59, 51, 4.6) + circ(55, 58, 3),
    c: S('M14 20C17 13 24 10 31 10', 3.5) + circ(20, 28, 2.2) }),
  wine: C({ a: '#8a1c3a', b: '#cfe8f4', c: '#ffffff', k: '#5a1024' }, {
    b: '<path d="M16 4H48C50 28 46 38 32 40C18 38 14 28 16 4Z"/>' + rect(29, 40, 6, 16) + rect(18, 56, 28, 5, 2),
    a: '<path d="M17 16H47C47 30 42 36 32 38C22 36 17 30 17 16Z"/>', k: rect(17, 16, 30, 2), c: S('M21 8L22 24', 2.5) }),
  chili: C({ a: '#d9463a', b: '#a82e24', c: '#ff9a8c', k: '#3f8f3f' }, {
    a: '<path d="M10 20C30 14 52 22 54 46C54 56 48 60 46 58C46 42 34 34 10 32Z"/>', b: '<path d="M54 46C54 56 48 60 46 58C46 52 44 46 40 42C48 42 52 44 54 46Z"/>',
    k: '<path d="M10 20C4 18 4 8 10 6C12 12 16 14 18 18Z"/>', c: S('M16 24C28 22 40 26 46 34', 3) }),
  salt: C({ a: '#f4f6f8', b: '#cfd5dc', c: '#ffffff', k: '#7a8594' }, {
    a: '<path d="M14 20H50L54 58H10Z"/>', b: '<path d="M14 20H50L54 58H40L44 20Z"/>', k: rect(12, 6, 40, 14, 4) + circ(24, 12, 1.8) + circ(32, 12, 1.8) + circ(40, 12, 1.8),
    c: S('M18 28L16 52', 3) }),
  coffee: C({ a: '#f4f0e6', b: '#4a2f1a', c: '#ffffff', k: '#c9c2ae' }, {
    a: '<path d="M6 24H46V40C46 52 38 58 26 58C14 58 6 52 6 40Z"/>' + S('M46 28H52C58 28 58 44 50 44H44', 5), b: '<ellipse cx="26" cy="25" rx="19" ry="5"/>',
    k: S('M10 56H44', 3), c: S('M18 12C14 8 22 6 18 2M30 12C26 8 34 6 30 2', 2.6) }),
  tea: C({ a: '#f4f0e6', b: '#8fbf5a', c: '#ffffff', k: '#c9c2ae' }, {
    a: '<path d="M6 26H50V38C50 50 40 58 28 58C16 58 6 50 6 38Z"/>' + S('M48 30H54C60 30 60 44 52 44H46', 5), b: '<ellipse cx="28" cy="27" rx="21" ry="5"/>',
    k: S('M12 54H44', 3), c: S('M20 14C16 10 24 8 20 4M32 14C28 10 36 8 32 4', 2.6) }),
  flower: C({ a: '#f472b6', b: '#c2488a', c: '#ffd0ea', k: '#f5c542' }, {
    a: circ(32, 14, 12) + circ(50, 28, 12) + circ(44, 50, 12) + circ(20, 50, 12) + circ(14, 28, 12), b: circ(32, 32, 15), k: circ(32, 32, 9), c: circ(30, 11, 3) }),
  basket: C({ a: '#c89a5a', b: '#9a6c35', c: '#e6c48f', k: '#5a3a1a' }, {
    a: '<path d="M4 26H60L54 58H10Z"/>', b: S('M16 26C16 4 48 4 48 26', 5), k: S('M12 36H52M14 46H50M24 28L22 56M40 28L42 56', 2.4), c: S('M8 29H56', 2.4) }),
  footprints: C({ a: '#8a5a3a', b: '#6b4129', c: '#c28a63', k: '#000' }, {
    a: '<ellipse cx="20" cy="40" rx="9" ry="14"/><ellipse cx="44" cy="22" rx="9" ry="14"/>', b: '<ellipse cx="20" cy="58" rx="6" ry="5"/><ellipse cx="44" cy="42" rx="6" ry="5"/>',
    c: '<ellipse cx="17" cy="35" rx="3" ry="6"/>' }),
  goal: C({ a: '#f4f0e6', b: '#cfd5dc', c: '#ffffff', k: '#7a8594' }, {
    a: S('M6 58V10H58V58', 6), k: S('M6 22H58M6 34H58M6 46H58M18 10V58M30 10V58M42 10V58M52 10V58', 1.8), b: '<path d="M6 58V10H12V58Z"/>', c: rect(8, 8, 48, 2) }),
  turtle: C({ a: '#5fae4a', b: '#3d7a38', c: '#a4e08a', k: '#2a1a10' }, {
    a: '<path d="M6 44C6 24 20 14 34 14C48 14 58 24 58 44Z"/><ellipse cx="58" cy="38" rx="6" ry="7"/><rect x="12" y="42" width="10" height="14" rx="4"/><rect x="40" y="42" width="10" height="14" rx="4"/>',
    b: '<path d="M34 14C48 14 58 24 58 44H44C46 30 42 20 34 14Z"/>', k: S('M20 32L34 26L48 32M34 26V44', 2.5) + circ(60, 36, 1.5), c: S('M14 34C16 26 22 20 28 18', 3) }),
  fox: C({ a: '#e8742a', b: '#f5f0e6', c: '#ffb27a', k: '#2a1a10' }, {
    a: '<path d="M4 6L24 16H40L60 6L58 38C54 52 42 60 32 60C22 60 10 52 6 38Z"/>', b: '<path d="M12 40C20 44 26 52 32 60C38 52 44 44 52 40C44 38 38 46 32 46C26 46 20 38 12 40Z"/>',
    k: circ(22, 30, 3) + circ(42, 30, 3) + circ(32, 54, 3), c: S('M10 12L20 18', 3) }),
  camel: C({ a: '#c8a064', b: '#9a7440', c: '#e6c68f', k: '#3a2a16' }, {
    a: '<path d="M4 34C8 24 14 28 18 34C22 18 30 16 34 28C38 20 44 22 46 30C50 20 54 10 58 10L62 16C56 24 54 34 52 44L50 60H42L40 46H20L18 60H10L8 44C6 40 4 38 4 34Z"/>',
    b: '<path d="M34 28C38 20 44 22 46 30C50 20 54 10 58 10L62 16C56 24 54 34 52 44H40Z"/>', k: circ(56, 15, 1.8), c: S('M10 36C14 30 18 32 20 36', 2.6) }),
  fish: C({ a: '#4aa3df', b: '#2a74b0', c: '#b8e0f8', k: '#1a1a1a' }, {
    a: '<path d="M2 32C14 12 40 10 50 26L62 12V52L50 38C40 54 14 52 2 32Z"/>', b: '<path d="M50 26L62 12V52L50 38C54 34 54 30 50 26Z"/><path d="M2 32C14 52 40 54 50 38C40 44 14 44 2 32Z"/>',
    k: circ(16, 28, 3), c: S('M14 22C20 17 30 16 38 20', 3) }),
  ice: C({ a: '#bfe3ff', b: '#8fc0e8', c: '#ffffff', k: '#5a8fc0' }, {
    a: poly('10,18 36,8 58,20 58,46 32,58 8,46'), b: poly('32,58 58,46 58,20 32,32'), c: poly('10,18 36,8 58,20 32,32'), k: S('M32 32V58M14 26L24 38', 2) }),
  moon: C({ a: '#454b6a', b: '#2f3450', c: '#7a82a8', k: '#2f3450' }, {
    a: circ(32, 32, 27), b: '<path d="M32 5A27 27 0 0 1 32 59C46 50 52 32 44 16C41 11 37 7 32 5Z"/>', k: circ(22, 24, 4) + circ(36, 40, 5) + circ(24, 44, 2.5), c: S('M14 22C16 16 20 12 26 9', 3) }),
  wave: C({ a: '#3fa0e8', b: '#2672b8', c: '#bfe3ff', k: '#000' }, {
    a: '<path d="M2 36C10 24 18 24 26 34C34 44 44 44 52 30L62 20V58H2Z"/>', b: '<path d="M2 46C10 40 18 42 26 48C36 54 46 52 62 40V58H2Z"/>', c: S('M8 33C13 28 17 28 21 32', 3) }),
  sun: C({ a: '#f5c542', b: '#e0a21c', c: '#fff3b0', k: '#f08a24' }, {
    a: circ(32, 32, 16), k: S('M32 4V12M32 52V60M4 32H12M52 32H60M12 12L18 18M46 46L52 52M52 12L46 18M18 46L12 52', 5), b: '<path d="M32 16A16 16 0 0 1 32 48C42 42 46 28 40 20C38 18 35 16 32 16Z"/>', c: S('M24 24C26 20 29 18 32 18', 3) }),
  candle: C({ a: '#f1e6c8', b: '#d6c49a', c: '#ffa93a', k: '#3a2a16' }, {
    a: rect(18, 24, 28, 36, 4), b: rect(36, 24, 10, 36, 3), k: S('M32 24V16', 3), c: '<path d="M32 2C40 10 40 18 32 18C24 18 24 10 32 2Z"/>' }),
  battery: C({ a: '#4caf50', b: '#2e7d32', c: '#a8e6aa', k: '#3a4350' }, {
    a: rect(4, 14, 50, 36, 6), b: rect(30, 14, 24, 36, 6), k: rect(54, 24, 7, 16, 2) + S('M14 24V40M24 24V40', 4), c: rect(8, 17, 38, 3) }),
  shades: C({ a: '#2a2a2a', b: '#4a4a52', c: '#9aa6b4', k: '#000' }, {
    a: '<path d="M4 24H60L56 44C54 52 40 52 38 44L36 38H28L26 44C24 52 10 52 8 44Z"/>', b: S('M4 24H60', 5), c: S('M12 32L18 44M42 32L48 44', 3), k: circ(0, 0, 0.1) }),
  target: C({ a: '#d9463a', b: '#f4f0e6', c: '#fff', k: '#3a4350' }, {
    a: circ(32, 32, 28), b: circ(32, 32, 20), k: circ(32, 32, 12), c: circ(32, 32, 5) }),
  sponge: C({ a: '#f5d442', b: '#d6a81e', c: '#fff0a0', k: '#a67c20' }, {
    a: rect(4, 16, 56, 34, 8), b: rect(4, 42, 56, 8, 4), k: circ(18, 28, 4) + circ(34, 24, 3) + circ(46, 34, 4) + circ(26, 40, 3), c: rect(8, 19, 30, 3, 1.5) }),
  wand: C({ a: '#6b4129', b: '#f5f0e0', c: '#f5c542', k: '#3a2a16' }, {
    a: rot(45, rect(29, 20, 6, 42, 3)), b: rot(45, rect(29, 20, 6, 8, 2)),
    c: poly('46,2 50,12 60,16 50,20 46,30 42,20 32,16 42,12'), k: rot(45, rect(29, 46, 6, 3)) }),
  train: C({ a: '#d9463a', b: '#a82e24', c: '#ffa59c', k: '#2a323c' }, {
    a: rect(4, 22, 36, 28, 3) + rect(36, 10, 22, 40, 3), b: rect(38, 8, 20, 6, 2) + rect(6, 8, 10, 14, 2),
    k: circ(14, 54, 6) + circ(30, 54, 6) + circ(48, 54, 6) + rect(42, 18, 12, 12, 2), c: rect(7, 25, 28, 3) }),
  truck: C({ a: '#3f6fd1', b: '#f4f0e6', c: '#9ac0f6', k: '#2a323c' }, {
    a: rect(2, 14, 36, 34, 3) + '<path d="M40 24H52L62 34V48H40Z"/>', b: rect(4, 16, 32, 30, 2),
    k: circ(14, 52, 6.5) + circ(50, 52, 6.5) + rect(44, 27, 10, 8, 2), c: rect(7, 19, 22, 3) }),
  truckSmall: C({ a: '#43a047', b: '#2e7d32', c: '#a8e6aa', k: '#2a323c' }, {
    a: rect(2, 20, 34, 28, 3) + '<path d="M38 26H50L62 36V48H38Z"/>', b: rect(2, 40, 34, 8, 2),
    k: circ(14, 52, 6.5) + circ(50, 52, 6.5) + rect(42, 29, 10, 8, 2), c: rect(6, 24, 22, 3) }),
  gradcap: C({ a: '#2a323c', b: '#1a2028', c: '#5a6672', k: '#f0b429' }, {
    a: poly('32,8 62,22 32,36 2,22') + '<path d="M14 30V44C14 52 50 52 50 44V30L32 38Z"/>', b: '<path d="M32 38L50 30V44C50 52 32 52 32 52Z"/>', k: S('M56 24V44', 3) + circ(56, 48, 4), c: S('M10 22L30 12', 2.4) }),
  // A TIMBER-FRAMED HOUSE for housing (user 2026-11-04: "das Bett soll in ein
  // Fachwerkhaus werden"): plaster gable wall, terracotta roof, dark beams.
  timberHouse: C({ a: '#f1e6c9', b: '#c4552b', k: '#5b3a1e', c: '#ffd27a' }, {
    a: poly('10,34 32,16 54,34 54,60 10,60'),
    b: '<path d="M1 34L32 5L63 34L56 38L32 16L8 38Z"/>',
    k: S('M10 35V60M32 16V60M54 35V60M10 60H54M10 46H54M10 46L21 36M54 46L43 36', 2.4) + rect(27, 48, 10, 12, 1),
    c: rect(13, 49, 9, 8) + rect(42, 49, 9, 8) }),
  // DAILY TASKS (user 2026-11-04: "Daily task neu machen"): a clipboard with
  // three ticked lines.
  tasks: C({ a: '#f4efe0', b: '#c89a5a', k: '#6b4129', c: '#3f9a4a' }, {
    a: rect(10, 10, 44, 50, 4),
    b: rect(22, 4, 20, 10, 3),
    k: S('M30 26H48M30 38H48M30 50H48', 4),
    c: S('M15 26l3 3 6-7M15 38l3 3 6-7M15 50l3 3 6-7', 3) }),
  bed: C({ a: '#c89a5a', b: '#3f6fd1', c: '#9ac0f6', k: '#7a4a22' }, {
    k: rect(4, 8, 7, 52, 2) + rect(53, 28, 7, 32, 2) + rect(4, 44, 56, 6, 2), a: '<path d="M10 24H44V44H10Z"/>' ,
    b: '<path d="M16 32H58V46H16Z"/>', c: rect(12, 26, 26, 8, 4) }),
  banned: C({ a: '#e0384b', b: '#a81f35', c: '#ffb0b9', k: '#000' }, {
    a: '<circle cx="32" cy="32" r="25" fill="none" stroke="#000" stroke-width="9"/>', b: S('M14 50L50 14', 9), c: S('M16 20C18 14 22 10 28 8', 3) }),
  warning: C({ a: '#f5c542', b: '#c98f1e', c: '#fff3b0', k: '#3a2a16' }, {
    a: '<path d="M32 4L62 58H2Z" stroke="#000" stroke-width="6" stroke-linejoin="round"/>', b: poly('32,4 62,58 36,58'), k: S('M32 22V40', 6) + circ(32, 49, 3.6), c: S('M20 40L30 20', 2.6) }),
  stopwatch: C({ a: '#f1e6c8', b: '#7a4a22', c: '#ffffff', k: '#d9463a' }, {
    a: circ(32, 36, 24), b: '<circle cx="32" cy="36" r="24" fill="none" stroke="#000" stroke-width="5"/>' + rect(26, 4, 12, 6, 2) + rect(30, 8, 4, 6),
    k: S('M32 36L42 24', 5), c: S('M14 30C16 24 20 20 26 18', 3) }),
  chick: C({ a: '#ffd23a', b: '#f4f0e6', c: '#fff3a0', k: '#e8742a' }, {
    a: circ(32, 24, 17), b: '<path d="M4 44L12 36L20 44L28 36L36 44L44 36L52 44L60 36V60H4Z"/>',
    k: poly('26,26 38,26 32,34') + circ(25, 20, 2.4) + circ(39, 20, 2.4), c: S('M22 14C24 11 28 9 32 9', 3) }),
  derelict: C({ a: '#8f8a7e', b: '#b0a998', c: '#d4cfc0', k: '#4a4338' }, {
    a: '<path d="M3 33L32 6L45 18L38 24L44 30L36 34L40 36L55 36L61 33L52 26V58H12V36Z"/>', b: rect(12, 34, 40, 24),
    k: rect(27, 42, 10, 16) + S('M12 36L24 44L18 58M44 34L36 42L48 50', 2) + rect(16, 38, 8, 8), c: rect(14, 36, 3, 18) }),
  skull: C({ a: '#f1ead8', b: '#c9c2ae', c: '#ffffff', k: '#2a2a2a' }, {
    a: circ(32, 28, 24) + rect(18, 44, 28, 16, 5), b: '<path d="M32 4A24 24 0 0 1 32 52V44H46V54C46 58 44 60 40 60H32Z"/>',
    k: circ(22, 30, 7) + circ(42, 30, 7) + poly('32,36 28,44 36,44') + S('M26 50V58M32 50V58M38 50V58', 2), c: S('M14 22C16 14 22 9 28 8', 3) }),
  skullBones: C({ a: '#f1ead8', b: '#c9c2ae', c: '#ffffff', k: '#2a2a2a' }, {
    b: rot(30, rect(2, 28, 60, 7, 3.5) + circ(4, 28, 5) + circ(4, 36, 5) + circ(60, 28, 5) + circ(60, 36, 5)) + rot(-30, rect(2, 28, 60, 7, 3.5) + circ(4, 28, 5) + circ(4, 36, 5) + circ(60, 28, 5) + circ(60, 36, 5)),
    a: circ(32, 24, 19) + rect(21, 38, 22, 14, 4), k: circ(25, 25, 5.5) + circ(39, 25, 5.5) + poly('32,30 29,36 35,36') + S('M27 44V50M32 44V50M37 44V50', 1.8), c: S('M18 18C20 12 25 9 30 8', 2.6) }),
  zzz: C({ a: '#8fb4ff', b: '#5f82d0', c: '#dbe6ff', k: '#000' }, {
    a: S('M8 30H28L8 54H28', 8) + S('M36 8H50L36 26H50', 6), b: S('M44 40H58L44 56H58', 5), c: S('M10 28H24', 2.4) }),
  dice: C({ a: '#f5f0e0', b: '#cfc8b4', c: '#ffffff', k: '#2a2a2a' }, {
    a: rot(12, rect(8, 8, 48, 48, 9)), b: rot(12, '<path d="M32 56H47C52 56 56 52 56 47V8Z"/>'),
    k: rot(12, circ(20, 20, 4.5) + circ(44, 20, 4.5) + circ(32, 32, 4.5) + circ(20, 44, 4.5) + circ(44, 44, 4.5)), c: rot(12, rect(12, 11, 20, 3, 1.5)) }),
  party: C({ a: '#f0b429', b: '#c98f1e', c: '#e0384b', k: '#3f9ad6' }, {
    a: '<path d="M4 60L16 22L42 48Z"/>', b: '<path d="M4 60L28 36L42 48Z"/>', c: circ(30, 14, 3.5) + circ(52, 26, 3.5) + circ(46, 8, 3) + S('M30 24C34 16 42 20 40 12', 3.5),
    k: circ(54, 44, 3.5) + circ(20, 8, 3) + S('M42 28C46 24 52 28 56 20', 3.5) }),
  gift: C({ a: '#d9463a', b: '#f5c542', c: '#ff9a8c', k: '#a82e24' }, {
    a: rect(6, 26, 52, 34, 3) + rect(4, 16, 56, 12, 3), k: rect(32, 28, 26, 32) , b: rect(27, 16, 10, 44) + '<path d="M32 16C20 4 8 8 14 16C18 20 28 18 32 16Z"/><path d="M32 16C44 4 56 8 50 16C46 20 36 18 32 16Z"/>', c: rect(9, 30, 4, 26) }),
  alembic: C({ a: '#7fd35a', b: '#cfe8f4', c: '#ffffff', k: '#5a8fa8' }, {
    b: '<path d="M24 4H40V22L58 54C60 58 58 60 54 60H10C6 60 4 58 6 54L24 22Z"/>', a: '<path d="M16 42H48L58 56C60 60 58 60 54 60H10C6 60 4 60 6 56Z"/>',
    k: S('M24 4H40', 3.5) + circ(24, 50, 2.5) + circ(38, 46, 2), c: S('M26 10V24', 3) }),
  testtube: C({ a: '#7fd35a', b: '#cfe8f4', c: '#ffffff', k: '#5a8fa8' }, {
    b: rot(35, '<path d="M24 4H40V48C40 58 24 58 24 48Z"/>'), a: rot(35, '<path d="M25 30H39V48C39 56 25 56 25 48Z"/>'), k: rot(35, rect(20, 2, 24, 5, 2)), c: rot(35, rect(27, 10, 3, 24)) }),
  boot: C({ a: '#8a5a3a', b: '#4a2f1a', c: '#c28a63', k: '#e8d6b8' }, {
    a: '<path d="M14 4H36V32L56 42C60 44 60 58 56 58H10V4Z"/>', b: rect(8, 52, 54, 8, 3), k: S('M16 12H34M16 20H34M16 28H34', 2.6), c: rect(17, 36, 6, 12, 2) }),
  shoe: C({ a: '#f4f0e6', b: '#3f6fd1', c: '#ffffff', k: '#2a323c' }, {
    a: '<path d="M4 12H22L26 22C34 24 54 28 60 40V50H4Z"/>', b: rect(2, 46, 60, 10, 4) + poly('4,12 22,12 24,20 4,20'), k: S('M28 28L34 34M34 24L40 30', 2.6), c: S('M8 28C14 28 18 32 20 36', 3) }),
  dumbbell: C({ a: '#7a8594', b: '#4f5a68', c: '#c4ccd8', k: '#2a323c' }, {
    a: rect(6, 14, 10, 36, 3) + rect(16, 20, 8, 24, 2) + rect(40, 20, 8, 24, 2) + rect(48, 14, 10, 36, 3), k: rect(24, 29, 16, 6, 2), b: rect(12, 14, 4, 36) + rect(54, 14, 4, 36), c: rect(8, 17, 3, 22) }),
  pin: C({ a: '#e0384b', b: '#a81f35', c: '#ff9aa6', k: '#f5f0e0' }, {
    a: '<path d="M32 2C46 2 54 12 54 24C54 40 38 50 32 62C26 50 10 40 10 24C10 12 18 2 32 2Z"/>', b: '<path d="M32 62C38 50 54 40 54 24C54 20 53 16 51 13C50 30 40 44 32 52Z"/>', k: circ(32, 24, 9), c: S('M18 16C20 11 25 8 30 7', 3) }),
  basketFruit: null,
  clipboard: C({ a: '#c89a5a', b: '#f4f0e6', c: '#9aa6b4', k: '#6b4129' }, {
    a: rect(8, 8, 48, 54, 5), b: rect(14, 16, 36, 42, 2), c: rect(20, 2, 24, 12, 4), k: S('M20 28H44M20 38H44M20 48H36', 3) }),
  vase: C({ a: '#b9622e', b: '#8a4420', c: '#e89a62', k: '#f5d9a0' }, {
    a: '<path d="M22 4H42V14C42 20 54 26 54 40C54 54 46 62 32 62C18 62 10 54 10 40C10 26 22 20 22 14Z"/>', b: '<path d="M42 14C42 20 54 26 54 40C54 54 46 62 32 62C48 58 50 40 42 24Z"/>', k: S('M12 36H52M14 46H50', 3), c: S('M16 34C16 28 20 24 24 22', 3) }),
  mountains: null,
  leafGreen: null,
  prohibited: null,
  dot: C({ a: '#e0384b', b: '#a81f35', c: '#ff9aa6', k: '#000' }, { a: circ(32, 32, 26), b: '<path d="M32 58A26 26 0 0 0 58 32C50 46 44 52 32 54Z"/>', c: circ(22, 22, 5) }),
  dotBlue: C({ a: '#3f9ad6', b: '#2a6fa4', c: '#9ad0f2', k: '#000' }, { a: circ(32, 32, 26), b: '<path d="M32 58A26 26 0 0 0 58 32C50 46 44 52 32 54Z"/>', c: circ(22, 22, 5) }),
  faceFear: C({ a: '#ffd54a', b: '#e0a21c', c: '#7fc8ff', k: '#2a1a10' }, {
    a: faceBase, b: '<path d="M32 59A27 27 0 0 0 59 32C54 48 46 56 32 59Z"/>',
    k: '<ellipse cx="22" cy="28" rx="4" ry="6"/><ellipse cx="42" cy="28" rx="4" ry="6"/><ellipse cx="32" cy="46" rx="6" ry="8"/>' + S('M14 16L26 20M50 16L38 20', 3), c: '<path d="M54 12C58 18 58 22 54 24C50 22 50 18 54 12Z"/>' }),
  faceSleep: C({ a: '#ffd54a', b: '#e0a21c', c: '#8fb4ff', k: '#2a1a10' }, {
    a: faceBase, b: '<path d="M32 59A27 27 0 0 0 59 32C54 48 46 56 32 59Z"/>', k: S('M14 30C18 36 26 36 28 30M36 30C40 36 48 36 50 30', 3.5) + '<ellipse cx="32" cy="46" rx="4" ry="3"/>',
    c: S('M46 4H58L46 16H58', 3.5) }),
  faceCold: C({ a: '#9bd3ff', b: '#6aa8e0', c: '#ffffff', k: '#2a1a10' }, {
    a: faceBase, b: '<path d="M32 59A27 27 0 0 0 59 32C54 48 46 56 32 59Z"/>', k: circ(22, 28, 4) + circ(42, 28, 4) + S('M18 46L24 42L30 46L36 42L42 46L46 42', 3),
    c: S('M8 14L14 20M56 14L50 20M32 2V8', 3) }),
  dizzy: C({ a: '#ffd54a', b: '#e0a21c', c: '#ffffff', k: '#3f9ad6' }, {
    a: poly('32,2 38,20 56,22 42,34 46,52 32,42 18,52 22,34 8,22 26,20'), b: poly('32,42 46,52 42,34 38,30'), k: S('M10 56C24 62 48 60 58 48', 3.5), c: S('M6 8C14 4 22 6 24 12', 3) }),
  anger: C({ a: '#e0384b', b: '#a81f35', c: '#ff9aa6', k: '#000' }, {
    a: S('M6 24C20 24 24 20 24 6M58 24C44 24 40 20 40 6M6 40C20 40 24 44 24 58M58 40C44 40 40 44 40 58', 8), b: S('M24 6V12M40 6V12', 3), c: S('M8 22C14 22 18 20 21 17', 2.4) }),
};
Object.keys(ICONS_EXTRA).forEach((k) => ICONS_EXTRA[k] === null && delete ICONS_EXTRA[k]);

// emoji -> icon key. (Variation selector U+FE0F is stripped before lookup.)
const EMOJI = {
  '🪙': 'coin', '🪵': 'wood', '🪨': 'stone', '⛏': 'pickaxe', '🟤': 'clay', '⚪': 'lime', '⬛': 'coal', '🟡': 'sand',
  '💎': 'gem', '🔷': 'crystalBlue', '💠': 'crystalCyan', '🧱': 'brick', '🔩': 'nut', '🪚': 'saw', '🪓': 'axe',
  '✨': 'sparkles', '🔥': 'flame', '🏛': 'bank', '🔴': 'dot',
  '⚔': 'swords', '🔨': 'hammer', '🛠': 'tools', '⚒': 'tools', '👑': 'crown', '🏆': 'trophy',
  '❤': 'heart', '💗': 'heartPink', '💚': 'heartGreen', '💞': 'hearts', '⭐': 'star', '🌟': 'star',
  '🪤': 'trap', '🩹': 'bandage', '🩺': 'stethoscope', '💉': 'syringe', '🔬': 'microscope', '🧬': 'dna', '🧪': 'testtube', '⚗': 'alembic',
  '🧭': 'compass', '🔄': 'cycle', '🔁': 'cycle', '🏗': 'crane', '🏭': 'factory', '🏰': 'castle', '🏕': 'tent', '👷': 'worker',
  '🗑': 'trash', '💨': 'wind', '💧': 'drop', '🩸': 'blood', '🌱': 'sprout', '🌿': 'herb', '🦫': 'beaver', '🥋': 'gi',
  '🛒': 'cart', '💱': 'exchange', '💥': 'boom', '✔': 'check', '⬆': 'arrowUp', '▶': 'play', '◀': 'playBack', '⏩': 'forward', '⏪': 'rewind', '⏸': 'pause',
  '📊': 'chartBars', '❄': 'snow', '🥶': 'faceCold', '🗿': 'moai', '😨': 'faceFear', '😴': 'faceSleep', '💫': 'dizzy', '👁': 'eye',
  '🐌': 'snail', '💢': 'anger', '❔': 'question', '🐎': 'horse', '🥩': 'meat', '🍷': 'wine', '🌶': 'chili', '🧂': 'salt', '☕': 'coffee', '🍵': 'tea',
  '🌸': 'flower', '🧺': 'basket', '📍': 'pin', '👣': 'footprints', '👟': 'shoe', '🥾': 'boot', '🥅': 'goal', '🐢': 'turtle', '🦊': 'fox', '🐫': 'camel',
  '🐟': 'fish', '🧊': 'ice', '🌑': 'moon', '🌊': 'wave', '☀': 'sun', '🕯': 'candle', '🔋': 'battery', '🕶': 'shades', '🎯': 'target', '🧽': 'sponge',
  '🪄': 'wand', '🚂': 'train', '🚛': 'truck', '🚚': 'truckSmall', '🏺': 'vase', '🎓': 'gradcap', '🛏': 'timberHouse', '🍖': 'meat', '🚫': 'banned', '⚠': 'warning', '⏱': 'stopwatch',
  '🐣': 'chick', '🏚': 'derelict', '💀': 'skull', '☠': 'skullBones', '💤': 'zzz', '🎲': 'dice', '🎉': 'party', '🎁': 'gift', '🏋': 'dumbbell',
  '📋': 'clipboard', '🩹_': 'bandage', '⏳': 'hourglass', '⏰': 'clock', '🕒': 'clock', '⚖': 'balance', '🔒': 'lock',
  '⛏_': 'pickaxe', '🥚': 'egg', '🎒': 'backpack', '📦': 'crate', '🏠': 'house', '🐾': 'paw', '⚡': 'bolt', '🗺': 'map', '📖': 'book', '🛡': 'shield',
  '👥': 'groups',
};
delete EMOJI['🩹_']; delete EMOJI['⛏_'];

module.exports = { ICONS_EXTRA, EMOJI };
