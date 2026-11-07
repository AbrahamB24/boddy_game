// Vector sources of the coloured icons (viewBox 0..64). Roles: a main, b second, k dark, c highlight.
const S = (d, w = 6) =>
  `<path d="${d}" fill="none" stroke="#000" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const ST = (inner, w = 6) =>
  `<g fill="none" stroke="#000" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${inner}</g>`;
const ring = (r = 24, w = 6) =>
  `<circle cx="32" cy="32" r="${r}" fill="none" stroke="#000" stroke-width="${w}"/>`;
const dot = (x, y, r = 3.6) => `<circle cx="${x}" cy="${y}" r="${r}"/>`;
const T = (a) => ({ L: { a } }); // tinted glyph
const C = (col, L) => ({ col, L }); // coloured icon

const star = '<polygon points="32,3 40,23 61,24 44,38 50,59 32,47 14,59 20,38 3,24 24,23"/>';

const ICONS = {
  // ── coloured icons ──────────────────────────────────────────────────────
  sword: C({ a: '#cfd8e3', b: '#e0b13a', k: '#7a4a22', c: '#ffffff' }, {
    a: '<polygon points="20,38 28,46 56,18 56,8 46,8"/>',
    b: S('M14 34L34 54', 6) + '<circle cx="9" cy="59" r="4.5"/>',
    k: S('M22 46L11 57', 5),
    c: S('M29 41L51 14', 2),
  }),
  shield: C({ a: '#3f6fd1', b: '#f0c64a', k: '#1d2f66', c: '#7ea6f2' }, {
    a: '<path d="M32 4L56 13V32C56 47 45 57 32 62C19 57 8 47 8 32V13Z"/>',
    c: '<path d="M32 12L16 18V32C16 42 22 49 32 54Z"/>',
    b: '<rect x="29" y="16" width="6" height="34"/><rect x="19" y="26" width="26" height="6"/>',
  }),
  heart: C({ a: '#e0384b', b: '#b81f35', c: '#ffb0b9', k: '#000' }, {
    a: '<path d="M32 58C10 42 5 30 5 21C5 12 12 7 19 7C25 7 29 10 32 15C35 10 39 7 45 7C52 7 59 12 59 21C59 30 54 42 32 58Z"/>',
    b: '<path d="M32 58C46 48 56 38 58 26C52 40 44 46 32 50Z"/>',
    c: '<circle cx="18" cy="20" r="4.5"/>',
  }),
  star: C({ a: '#f5c542', b: '#d79a1c', c: '#fff3b0', k: '#000' }, {
    a: star,
    b: '<polygon points="32,47 50,59 44,38 38,34 36,44"/>',
    c: '<polygon points="32,10 36,22 28,22"/>',
  }),
  paw: C({ a: '#9a6340', b: '#6b4129', c: '#c28a63', k: '#000' }, {
    a: '<ellipse cx="32" cy="42" rx="15" ry="12"/><ellipse cx="12" cy="29" rx="5.5" ry="7.5"/><ellipse cx="24" cy="16" rx="5.5" ry="8"/><ellipse cx="40" cy="16" rx="5.5" ry="8"/><ellipse cx="52" cy="29" rx="5.5" ry="7.5"/>',
    b: '<ellipse cx="32" cy="47" rx="8" ry="5"/>',
    c: '<ellipse cx="25" cy="38" rx="4" ry="3"/>',
  }),
  house: C({ a: '#c8453b', b: '#efe0b8', k: '#6b4129', c: '#8fc6e8' }, {
    a: '<polygon points="3,33 32,6 61,33 55,36 32,15 9,36"/><rect x="42" y="10" width="7" height="14"/>',
    b: '<rect x="11" y="32" width="42" height="27"/>',
    k: '<rect x="27" y="42" width="11" height="17"/>',
    c: '<rect x="15" y="38" width="8" height="8"/><rect x="43" y="38" width="7" height="8"/>',
  }),
  egg: C({ a: '#f3ead2', b: '#7fb069', c: '#ffffff', k: '#b89f70' }, {
    a: '<path d="M32 4C47 4 56 26 56 39C56 51 46 60 32 60C18 60 8 51 8 39C8 26 17 4 32 4Z"/>',
    b: '<circle cx="24" cy="38" r="5"/><circle cx="41" cy="29" r="4"/><circle cx="37" cy="48" r="4.5"/>',
    c: '<ellipse cx="21" cy="21" rx="3" ry="6" transform="rotate(25 21 21)"/>',
  }),
  bolt: C({ a: '#f7d23e', b: '#e0a21c', c: '#fff6b0', k: '#000' }, {
    a: '<polygon points="38,2 12,36 28,36 22,62 52,26 36,26"/>',
    b: '<polygon points="36,26 52,26 22,62 30,38"/>',
    c: '<polygon points="36,8 20,32 28,32 34,12"/>',
  }),
  bell: C({ a: '#e8b53a', b: '#b9801f', c: '#fff0a0', k: '#000' }, {
    a: '<path d="M32 8C43 8 47 17 47 28V38L56 48H8L17 38V28C17 17 21 8 32 8Z"/>',
    b: '<circle cx="32" cy="55" r="5.5"/><circle cx="32" cy="6" r="3.5"/>',
    c: S('M24 14C21 18 21 24 21 30V38', 3),
  }),
  hammer: C({ a: '#9aa6b4', b: '#6f7b89', k: '#7a4a22', c: '#e4ebf2' }, {
    k: '<g transform="rotate(35 32 32)"><rect x="29" y="18" width="6" height="42"/></g>',
    a: '<g transform="rotate(35 32 32)"><rect x="10" y="6" width="44" height="18"/></g>',
    c: '<g transform="rotate(35 32 32)"><rect x="13" y="9" width="38" height="4"/></g>',
    b: '<g transform="rotate(35 32 32)"><rect x="10" y="20" width="44" height="4"/></g>',
  }),
  trophy: C({ a: '#f2c13a', b: '#c98f1e', c: '#fff1a8', k: '#7a4a22' }, {
    a: '<path d="M16 6H48V28C48 38 41 44 32 44C23 44 16 38 16 28Z"/>',
    b: S('M16 12H7V20C7 28 12 32 18 32', 5) + S('M48 12H57V20C57 28 52 32 46 32', 5) + '<rect x="29" y="44" width="6" height="9"/>',
    k: '<rect x="17" y="52" width="30" height="8"/>',
    c: S('M23 12V28', 3),
  }),
  medal: C({ a: '#e8b53a', b: '#c8453b', c: '#fff0a0', k: '#000' }, {
    a: '<circle cx="32" cy="40" r="19"/>',
    b: '<polygon points="14,2 28,2 36,26 24,30"/><polygon points="50,2 36,2 28,26 40,30"/>',
    c: '<circle cx="32" cy="40" r="10" fill="none" stroke="#000" stroke-width="3.5"/>',
  }),
  flame: C({ a: '#f08a24', b: '#d9462a', c: '#ffd860', k: '#000' }, {
    a: '<path d="M32 3C34 16 53 24 53 40C53 52 44 61 32 61C20 61 11 52 11 40C11 30 17 26 21 17C24 23 28 26 28 26C27 18 28 10 32 3Z"/>',
    b: '<path d="M32 61C20 61 11 52 11 40C20 45 26 45 32 41C38 45 44 45 53 40C53 52 44 61 32 61Z"/>',
    c: '<path d="M32 30C34 37 42 40 42 47C42 53 38 57 32 57C26 57 22 53 22 47C22 40 30 37 32 30Z"/>',
  }),
  // Less childlike (user 2026-11-04): a LEATHER rucksack with side pockets,
  // a buckled flap and a brass fitting, not a bright green blob.
  backpack: C({ a: '#8a5a32', b: '#5f3a1d', c: '#a8703f', k: '#d1ab55' }, {
    a: '<path d="M16 24C16 14 23 8 32 8C41 8 48 14 48 24V54C48 58 46 60 42 60H22C18 60 16 58 16 54Z"/>',
    b: '<path d="M16 24C16 14 23 8 32 8C41 8 48 14 48 24V30C40 34 24 34 16 30Z"/><rect x="8" y="38" width="10" height="16" rx="3"/><rect x="46" y="38" width="10" height="16" rx="3"/>',
    k: '<rect x="28" y="28" width="8" height="9" rx="1"/>' + S('M24 32V42M40 32V42', 3),
    c: '<rect x="22" y="44" width="20" height="12" rx="2"/>',
  }),
  crate: C({ a: '#c89a5a', b: '#9a6c35', k: '#5a3a1a', c: '#e6c48f' }, {
    a: '<rect x="6" y="18" width="52" height="40"/>',
    b: '<rect x="3" y="8" width="58" height="12"/>',
    k: '<rect x="23" y="30" width="18" height="6"/>',
    c: '<rect x="8" y="22" width="48" height="3"/>',
  }),
  person: C({ a: '#27415e', b: '#a7bdd2', c: '#e3eef8', k: '#c9a24a' }, {
    a: '<circle cx="32" cy="32" r="26"/>',
    b: '<circle cx="32" cy="25" r="9"/><path d="M15 54C15 41 23 36 32 36C41 36 49 41 49 54Z"/>',
    k: '<circle cx="32" cy="32" r="27" fill="none" stroke="#000" stroke-width="4"/>',
    c: S('M26 22C27 19 29 17 32 17', 2.2),
  }),
  groups: C({ a: '#5f7a94', b: '#a7bdd2', c: '#e3eef8', k: '#27415e' }, {
    a: '<circle cx="12" cy="26" r="7"/><circle cx="52" cy="26" r="7"/><path d="M0 58C0 47 4 40 12 40C20 40 24 47 24 58Z"/><path d="M40 58C40 47 44 40 52 40C60 40 64 47 64 58Z"/>',
    b: '<circle cx="32" cy="17" r="10"/><path d="M14 60C14 44 21 33 32 33C43 33 50 44 50 60Z"/>',
    c: S('M24 16C25 12 28 9 32 8', 2.5),
  }),
  personAdd: C({ a: '#a7bdd2', b: '#6f8aa3', c: '#5fbf6a', k: '#000' }, {
    a: '<circle cx="24" cy="18" r="11"/>',
    b: '<path d="M2 60C2 44 11 35 24 35C37 35 46 44 46 60Z"/>',
    c: S('M52 14V36M41 25H63', 7),
  }),
  lock: C({ a: '#e0b13a', b: '#9aa6b4', k: '#5a3a1a', c: '#fff0a0' }, {
    a: '<rect x="9" y="28" width="46" height="32" rx="4"/>',
    b: S('M19 28V20C19 11 25 6 32 6C39 6 45 11 45 20V28', 6),
    k: '<circle cx="32" cy="41" r="5"/><rect x="30" y="41" width="4" height="10"/>',
    c: '<rect x="12" y="31" width="40" height="3"/>',
  }),
  flag: C({ a: '#d9463a', b: '#a82e24', c: '#ffa59c', k: '#7a4a22' }, {
    k: '<rect x="9" y="3" width="6" height="58"/>',
    a: '<path d="M15 8C25 3 33 13 44 8C50 6 54 8 57 10V36C54 34 50 32 44 34C33 40 25 30 15 35Z"/>',
    c: S('M20 14C26 14 30 18 36 16', 3),
  }),
  hourglass: C({ a: '#bfe3f0', b: '#e0b13a', c: '#ffffff', k: '#7a4a22' }, {
    a: '<polygon points="12,8 52,8 52,12 37,32 52,52 52,56 12,56 12,52 27,32 12,12"/>',
    b: '<polygon points="19,12 45,12 35,26 29,26"/><polygon points="20,52 44,52 36,40 28,40"/>',
    k: '<rect x="8" y="1" width="48" height="8"/><rect x="8" y="55" width="48" height="8"/>',
    c: S('M17 14L28 32', 2.5),
  }),
  clock: C({ a: '#f1e6c8', b: '#7a4a22', c: '#ffffff', k: '#5a3a1a' }, {
    a: '<circle cx="32" cy="32" r="27"/>',
    b: '<circle cx="32" cy="32" r="27" fill="none" stroke="#000" stroke-width="5"/>',
    k: S('M32 15V32H45', 5),
    c: S('M14 24C16 18 20 14 25 12', 3),
  }),
  bank: C({ a: '#e8dcc0', b: '#b9801f', k: '#7a6a5a', c: '#fff4d6' }, {
    a: '<rect x="11" y="26" width="8" height="24"/><rect x="24" y="26" width="8" height="24"/><rect x="36" y="26" width="8" height="24"/><rect x="49" y="26" width="8" height="24" transform="translate(-4 0)"/>',
    b: '<polygon points="2,22 32,3 62,22"/>',
    k: '<rect x="5" y="50" width="54" height="9"/>',
    c: '<rect x="13" y="28" width="2" height="20"/><rect x="26" y="28" width="2" height="20"/><rect x="38" y="28" width="2" height="20"/>',
  }),
  gear: C({ a: '#9aa6b4', b: '#6f7b89', c: '#dfe6ee', k: '#3a4350' }, {
    a: '<circle cx="32" cy="32" r="24" fill="none" stroke="#000" stroke-width="10" stroke-dasharray="9.4 9.4"/><circle cx="32" cy="32" r="19"/>',
    b: '<circle cx="32" cy="32" r="19" fill="none" stroke="#000" stroke-width="4"/>',
    k: '<circle cx="32" cy="32" r="8"/>',
    c: S('M18 24C20 20 23 17 27 15', 3),
  }),
  tree: C({ a: '#4f9a4a', b: '#3d7a38', c: '#8fd47a', k: '#7a4a22' }, {
    a: '<path d="M32 3L50 28H41L55 47H9L23 28H14Z"/>',
    b: '<polygon points="32,3 50,28 41,28 55,47 32,47"/>',
    k: '<rect x="27" y="47" width="10" height="14"/>',
    c: S('M30 12L20 28', 3),
  }),
  grass: C({ a: '#5fae4a', b: '#3d7a38', c: '#a4e08a', k: '#000' }, {
    a: '<polygon points="6,60 12,20 20,60"/><polygon points="22,60 30,6 40,60"/><polygon points="38,60 48,22 58,60"/>',
    b: '<polygon points="30,6 40,60 32,60"/><polygon points="12,20 20,60 14,60"/><polygon points="48,22 58,60 50,60"/>',
    c: S('M28 18L25 44', 2.5),
  }),
  sparkles: C({ a: '#ffe27a', b: '#fff7cf', c: '#f5a623', k: '#000' }, {
    a: '<polygon points="24,2 30,22 48,28 30,34 24,54 18,34 0,28 18,22"/>',
    b: '<polygon points="49,34 52,44 62,47 52,50 49,60 46,50 36,47 46,44"/>',
    c: '<polygon points="52,4 54,10 60,12 54,14 52,20 50,14 44,12 50,10"/>',
  }),
  balance: C({ a: '#e0b13a', b: '#c98f1e', c: '#fff0a0', k: '#7a4a22' }, {
    k: '<rect x="29" y="8" width="6" height="48"/><rect x="14" y="54" width="36" height="7"/>',
    a: '<rect x="4" y="10" width="56" height="6"/>',
    b: S('M10 16L3 38M10 16L21 38M54 16L43 38M54 16L61 38', 2.2) + '<path d="M1 38H23C23 47 18 51 12 51C6 51 1 47 1 38Z"/><path d="M41 38H63C63 47 58 51 52 51C46 51 41 47 41 38Z"/>',
    c: '<rect x="6" y="11" width="22" height="2"/>',
  }),
  robot: C({ a: '#9aa6b4', b: '#6f7b89', c: '#f05a4a', k: '#222a35' }, {
    a: '<rect x="9" y="16" width="46" height="36" rx="6"/>',
    b: '<rect x="2" y="27" width="7" height="15"/><rect x="55" y="27" width="7" height="15"/>' + S('M32 16V8', 3),
    k: '<rect x="17" y="27" width="11" height="11"/><rect x="36" y="27" width="11" height="11"/><rect x="21" y="44" width="22" height="4"/>',
    c: '<circle cx="32" cy="6" r="4"/>',
  }),
  save: C({ a: '#3f6fd1', b: '#9aa6b4', c: '#f1e6c8', k: '#1d2f66' }, {
    a: '<path d="M6 6H46L58 18V58H6Z"/>',
    b: '<rect x="18" y="6" width="26" height="16"/>',
    k: '<rect x="35" y="9" width="5" height="10"/>',
    c: '<rect x="14" y="34" width="36" height="24"/>',
  }),
  chat: C({ a: '#f1e6c8', b: '#c9b98f', k: '#6b4129', c: '#ffffff' }, {
    a: '<path d="M6 6H58V42H30L14 58V42H6Z"/>',
    b: '<path d="M30 42H58V36L38 42Z"/>',
    k: '<circle cx="20" cy="24" r="4"/><circle cx="32" cy="24" r="4"/><circle cx="44" cy="24" r="4"/>',
    c: '<rect x="9" y="9" width="40" height="3"/>',
  }),
  medical: C({ a: '#e0384b', b: '#b81f35', c: '#ffb0b9', k: '#000' }, {
    a: '<rect x="22" y="4" width="20" height="56"/><rect x="4" y="22" width="56" height="20"/>',
    b: '<rect x="22" y="42" width="20" height="18"/>',
    c: '<rect x="25" y="7" width="5" height="50"/>',
  }),
  bookmark: C({ a: '#d9463a', b: '#a82e24', c: '#ffa59c', k: '#000' }, {
    a: '<path d="M12 3H52V61L32 46L12 61Z"/>',
    b: '<path d="M32 46L52 61V3H44V50Z"/>',
    c: '<rect x="17" y="7" width="4" height="40"/>',
  }),
  road: C({ a: '#6b6358', b: '#e8d6a8', k: '#3a342c', c: '#000' }, {
    a: '<polygon points="24,3 40,3 62,61 2,61"/>',
    b: '<rect x="30" y="8" width="4" height="9"/><rect x="29.5" y="23" width="5" height="11"/><rect x="29" y="41" width="6" height="15"/>',
    k: S('M24 3L2 61M40 3L62 61', 2.5),
  }),
  roadOff: C({ a: '#6b6358', b: '#e8d6a8', k: '#3a342c', c: '#e0384b' }, {
    a: '<polygon points="24,3 40,3 62,61 2,61"/>',
    b: '<rect x="30" y="8" width="4" height="9"/><rect x="29.5" y="23" width="5" height="11"/><rect x="29" y="41" width="6" height="15"/>',
    k: S('M24 3L2 61M40 3L62 61', 2.5),
    c: S('M6 58L58 6', 6.5),
  }),
  map: C({ a: '#efe0b8', b: '#d8c590', c: '#d9463a', k: '#8a5a30' }, {
    a: '<polygon points="3,12 22,6 42,14 61,8 61,54 42,60 22,52 3,58"/>',
    b: '<polygon points="22,6 42,14 42,60 22,52"/>',
    k: S('M9 44C17 34 27 46 36 36C42 30 48 36 55 28', 2.5),
    c: '<circle cx="44" cy="24" r="6"/>',
  }),
  book: C({ a: '#f1e6c8', b: '#3f6fd1', k: '#7a6a58', c: '#ffffff' }, {
    a: '<path d="M32 12C24 6 12 6 3 10V50C12 46 24 46 32 52C40 46 52 46 61 50V10C52 6 40 6 32 12Z"/>',
    b: '<path d="M0 52C12 48 24 48 32 55C40 48 52 48 64 52V60C52 56 40 56 32 63C24 56 12 56 0 60Z"/>',
    k: S('M10 18C16 16 22 16 27 19M10 28C16 26 22 26 27 29M37 19C42 16 48 16 54 18M37 29C42 26 48 26 54 28', 2.5) + S('M32 14V54', 2),
    c: '<rect x="6" y="46" width="22" height="2"/>',
  }),
  globe: C({ a: '#4a8fd6', b: '#5fae4a', c: '#bfe3ff', k: '#000' }, {
    a: '<circle cx="32" cy="32" r="27"/>',
    b: '<path d="M14 18C21 10 31 13 29 22C27 29 18 28 16 35C11 31 10 24 14 18Z"/><path d="M38 30C47 26 56 32 54 42C51 52 42 54 38 47Z"/>',
    c: S('M15 22C18 14 26 9 34 8', 3),
  }),
  ball: C({ a: '#e0384b', b: '#f1e6c8', c: '#f1e6c8', k: '#2a1a0e' }, {
    a: '<path d="M5 32A27 27 0 0 1 59 32Z"/>',
    b: '<path d="M5 32A27 27 0 0 0 59 32Z"/>',
    k: '<rect x="5" y="29" width="54" height="6"/>' + '<circle cx="32" cy="32" r="9" fill="none" stroke="#000" stroke-width="5"/>',
    c: '<circle cx="32" cy="32" r="4.5"/>',
  }),
  tag: C({ a: '#e0b13a', b: '#9a6c35', c: '#fff0a0', k: '#5a3a1a' }, {
    a: '<path d="M7 7H32L59 34L34 59L7 32Z"/>',
    b: S('M14 14L50 50', 0.1),
    k: '<circle cx="19" cy="19" r="5"/>',
    c: S('M30 14L50 34', 3),
  }),
};


module.exports = { ICONS, S, ST, C, ring, dot, star };
