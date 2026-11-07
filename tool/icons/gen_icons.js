// Renders every coloured icon as a voxel sprite ("Voxel fein") (icons_base.js + icons_extra.js) to a
// 160 px WebP and writes
//   assets/images/icons/<key>.webp
//   lib/core/theme/game_icon_data.dart   (key list + emoji -> key map)
// Run:  cd tool/icons && npm i && node gen_icons.js [sheet.png]
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const fs = require('fs');
const path = require('path');
const { ICONS } = require('./icons_base.js');
const { ICONS_EXTRA, EMOJI } = require('./icons_extra.js');

const ALL = { ...ICONS, ...ICONS_EXTRA };
// The realistic fantasy style (user 2026-11-04) is the default: the sheet's
// redrawn icons replace their first drafts, and everything is painted by
// fantasy_render.js. ICON_STYLE=pixel|glyph|smooth|voxel keeps the others.
const STYLE = process.env.ICON_STYLE || 'fantasy';
if (STYLE === 'fantasy') Object.assign(ALL, require('./icons_fantasy.js').FANTASY);
const { fantasy } = require('./fantasy_render.js');
const SIZE = 160;
const VB = '-3 -3 70 70';
const OUTLINE = '#2a1a0e';
const ROLES = ['a', 'b', 'k', 'c'];
const OUT_DIR = path.resolve(__dirname, '../../assets/images/icons');
fs.mkdirSync(OUT_DIR, { recursive: true });

async function layerImg(inner, color) {
  const body = inner.replace(/#000/g, color).replace(/<(circle|rect|polygon|path|ellipse|g)(?![^>]*\b(fill|stroke)=)/g, '<$1');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" width="${SIZE}" height="${SIZE}"><g fill="${color}">${body}</g></svg>`;
  return loadImage(Buffer.from(svg));
}

// ── voxel rendering ("Voxel fein": 22 x 22 cubes, 4 deep) ──────────────────
const G = 22, DEPTH = 4;
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mixc = (c, t, k) => c.map((v, i) => Math.round(v + (t[i] - v) * k));
const css = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;

async function voxelGrid(def) {
  const px = new Array(G * G).fill(null);
  for (const r of ROLES) {
    const inner = def.L[r];
    if (!inner) continue;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" width="${G}" height="${G}"><g fill="#000">${inner}</g></svg>`;
    const img = await loadImage(Buffer.from(svg));
    const c = createCanvas(G, G);
    const x = c.getContext('2d');
    x.drawImage(img, 0, 0);
    const d = x.getImageData(0, 0, G, G).data;
    for (let i = 0; i < G * G; i++) if (d[i * 4 + 3] >= 70) px[i] = def.col[r];
  }
  return px;
}

function drawVoxels(px, u, seedKey) {
  const dx = u * 0.5, dy = -u * 0.5;
  const W = Math.ceil(G * u + DEPTH * dx + 8), H = Math.ceil(G * u + DEPTH * u * 0.5 + 8);
  const c = createCanvas(W, H);
  const x = c.getContext('2d');
  const ox = 4, oy = DEPTH * u * 0.5 + 4;
  let seed = 0;
  for (const ch of seedKey) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
  const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
  const has = (gx, gy) => gx >= 0 && gy >= 0 && gx < G && gy < G && px[gy * G + gx];
  const poly = (pts, color) => {
    x.beginPath();
    pts.forEach(([a, b], i) => (i ? x.lineTo(a, b) : x.moveTo(a, b)));
    x.closePath();
    x.fillStyle = color;
    x.fill();
    x.strokeStyle = 'rgba(0,0,0,.28)';
    x.lineWidth = Math.max(0.6, u * 0.15);
    x.stroke();
  };
  for (let z = DEPTH - 1; z >= 0; z--) {
    for (let gy = 0; gy < G; gy++) {
      for (let gx = G - 1; gx >= 0; gx--) {
        const hc = has(gx, gy);
        if (!hc) continue;
        const j = (rnd() - 0.5) * 18;
        const col = hexRgb(hc).map((v) => Math.max(0, Math.min(255, v + j)));
        const X = ox + gx * u + z * dx, Y = oy + gy * u + z * dy;
        if (!has(gx + 1, gy)) poly([[X + u, Y], [X + u + dx, Y + dy], [X + u + dx, Y + u + dy], [X + u, Y + u]], css(mixc(col, [0, 0, 0], 0.38)));
        if (!has(gx, gy - 1)) poly([[X, Y], [X + dx, Y + dy], [X + u + dx, Y + dy], [X + u, Y]], css(mixc(col, [255, 255, 255], 0.3)));
        if (z === 0) poly([[X, Y], [X + u, Y], [X + u, Y + u], [X, Y + u]], css(col));
      }
    }
  }
  return c;
}

// ── smooth rendering (user 2026-11-04: "glatte Icons, die Voxel-Icons sind schwer
// lesbar"): the SAME vector layers, filled flat in the role colours, with a dark
// outline all round and a soft drop shadow. ICON_STYLE=voxel brings the voxel
// sprites back.
async function renderSmooth(def) {
  const body = createCanvas(SIZE, SIZE);
  const bx = body.getContext('2d');
  for (const r of ROLES) {
    const inner = def.L[r];
    if (!inner) continue;
    bx.drawImage(await layerImg(inner, def.col ? def.col[r] : '#ffffff'), 0, 0);
  }
  // Silhouette in the outline colour, stamped round the body for the outline.
  const sil = createCanvas(SIZE, SIZE);
  const sx = sil.getContext('2d');
  sx.drawImage(body, 0, 0);
  sx.globalCompositeOperation = 'source-in';
  sx.fillStyle = OUTLINE;
  sx.fillRect(0, 0, SIZE, SIZE);
  const out = createCanvas(SIZE, SIZE);
  const ox = out.getContext('2d');
  const o = SIZE * 0.02;
  ox.shadowColor = 'rgba(0,0,0,.35)';
  ox.shadowBlur = SIZE * 0.03;
  ox.shadowOffsetY = SIZE * 0.015;
  for (let i = 0; i < 12; i++) {
    const t = (i / 12) * Math.PI * 2;
    ox.drawImage(sil, Math.cos(t) * o, Math.sin(t) * o);
  }
  ox.shadowColor = 'transparent';
  ox.drawImage(body, 0, 0);
  return out;
}

// ── glyph rendering (user 2026-11-04: "im gleichen Stil wie die System-Icons"):
// ONE flat colour per icon, no outline, no shadow, and the parts of the picture
// separated by thin gaps cut out of it — the way the system's own symbols are
// drawn. The colour is the icon's main one, pulled into a mid-tone so it reads
// on both the light parchment and the dark iron.
const lum = (c) => (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255;
function glyphColor(def) {
  let c = hexRgb(def.col ? def.col.a || Object.values(def.col)[0] : '#d8d0bc');
  const l = lum(c);
  if (l > 0.62) c = mixc(c, [0, 0, 0], (l - 0.62) * 1.1);
  if (l < 0.28) c = mixc(c, [255, 255, 255], (0.28 - l) * 1.4);
  return css(c);
}
async function renderGlyph(def) {
  const color = glyphColor(def);
  const out = createCanvas(SIZE, SIZE);
  const ox = out.getContext('2d');
  const gap = SIZE * 0.018;
  let first = true;
  for (const r of ROLES) {
    const inner = def.L[r];
    if (!inner) continue;
    const mask = await layerImg(inner, '#000000');
    if (!first) {
      // cut a thin gap round this part out of what is already there
      ox.globalCompositeOperation = 'destination-out';
      for (let i = 0; i < 12; i++) {
        const t = (i / 12) * Math.PI * 2;
        ox.drawImage(mask, Math.cos(t) * gap, Math.sin(t) * gap);
      }
      ox.globalCompositeOperation = 'source-over';
    }
    const lay = createCanvas(SIZE, SIZE);
    const lx = lay.getContext('2d');
    lx.drawImage(mask, 0, 0);
    lx.globalCompositeOperation = 'source-in';
    lx.fillStyle = color;
    lx.fillRect(0, 0, SIZE, SIZE);
    ox.drawImage(lay, 0, 0);
    first = false;
  }
  return out;
}

// ── hand-pixeled rendering (user 2026-11-04, after showing a pixel-art item
// sheet: "diesen Stil kopieren"). The style, not anybody's art: the picture is
// rasterised to a 48 x 48 grid in its own colours, every pixel on the lit side
// (top / left edge) is a step lighter, every one on the shaded side (bottom /
// right edge) a step darker, and the silhouette gets a one-pixel outline in a
// darkened version of the colour it surrounds. Scaled up 4 x (192 px) with no smoothing.
const PN = 48; // grid (user 2026-11-04: "mehr Detail"; was 32)
async function renderPixel(def) {
  const inner = PN - 2; // room for the outline
  const px = new Array(PN * PN).fill(null);
  for (const r of ROLES) {
    const l = def.L[r];
    if (!l) continue;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" width="${inner}" height="${inner}"><g fill="#000">${l}</g></svg>`;
    const img = await loadImage(Buffer.from(svg));
    const c = createCanvas(inner, inner);
    const x = c.getContext('2d');
    x.drawImage(img, 0, 0);
    const d = x.getImageData(0, 0, inner, inner).data;
    for (let i = 0; i < inner * inner; i++) {
      if (d[i * 4 + 3] >= 96) {
        const gx = (i % inner) + 1, gy = Math.floor(i / inner) + 1;
        // A little less saturated and a touch darker than the source colour
        // (user 2026-11-04: "die Icons wirken etwas kindlich").
        const base = hexRgb(def.col ? def.col[r] : '#d8d0bc');
        const gray = Math.round(lum(base) * 255);
        px[gy * PN + gx] = mixc(mixc(base, [gray, gray, gray], 0.16), [0, 0, 0], 0.05);
      }
    }
  }
  const at = (x, y) => (x >= 0 && y >= 0 && x < PN && y < PN ? px[y * PN + x] : null);
  const out = createCanvas(PN * 4, PN * 4);
  const ox = out.getContext('2d');
  ox.imageSmoothingEnabled = false;
  const u = 4;
  const put = (x, y, col) => { ox.fillStyle = css(col); ox.fillRect(Math.floor(x * u), Math.floor(y * u), Math.ceil(u), Math.ceil(u)); };
  for (let y = 0; y < PN; y++) {
    for (let x = 0; x < PN; x++) {
      const c = at(x, y);
      if (c) {
        const litEdge = !at(x, y - 1) || !at(x - 1, y);
        const shadeEdge = !at(x, y + 1) || !at(x + 1, y);
        // one more step in from the shaded edge, so a broad area still turns
        let col = c;
        if (litEdge && !shadeEdge) col = mixc(c, [255, 255, 255], 0.32);
        else if (shadeEdge) col = mixc(c, [0, 0, 0], 0.28);
        else if (!at(x + 1, y + 1) || !at(x, y + 2) || !at(x + 2, y)) col = mixc(c, [0, 0, 0], 0.12);
        put(x, y, col);
      } else {
        // outline: an empty pixel touching a filled one on a side
        let n = null;
        for (const [dx, dy] of [[0, -1], [-1, 0], [1, 0], [0, 1]]) { const q = at(x + dx, y + dy); if (q) { n = q; break; } }
        if (n) put(x, y, mixc(n, [20, 10, 4], 0.72));
      }
    }
  }
  return out;
}

async function render(def, key) {
  if (STYLE === 'fantasy') return fantasy(def, 192);
  if (process.env.ICON_STYLE === 'pixel') return renderPixel(def);
  if (process.env.ICON_STYLE === 'glyph') return renderGlyph(def);
  if (process.env.ICON_STYLE === 'smooth') return renderSmooth(def);
  if (process.env.ICON_STYLE !== 'voxel') return renderGlyph(def);
  const big = drawVoxels(await voxelGrid(def), 12, key); // draw large, then fit
  const out = createCanvas(SIZE, SIZE);
  const ox = out.getContext('2d');
  ox.imageSmoothingQuality = 'high';
  const k = Math.min((SIZE - 6) / big.width, (SIZE - 6) / big.height);
  const w = big.width * k, h = big.height * k;
  ox.shadowColor = 'rgba(0,0,0,.4)';
  ox.shadowBlur = SIZE * 0.025;
  ox.shadowOffsetY = SIZE * 0.012;
  ox.drawImage(big, (SIZE - w) / 2, (SIZE - h) / 2, w, h);
  return out;
}

(async () => {
  const keys = Object.keys(ALL);
  const canvases = {};
  for (const k of keys) {
    canvases[k] = await render(ALL[k], k);
    fs.writeFileSync(path.join(OUT_DIR, k + '.webp'), canvases[k].toBuffer('image/webp', 90));
  }
  // remove stale files
  for (const f of fs.readdirSync(OUT_DIR)) if (!keys.includes(f.replace('.webp', ''))) fs.unlinkSync(path.join(OUT_DIR, f));

  const missing = Object.entries(EMOJI).filter(([, v]) => !ALL[v]);
  if (missing.length) { console.error('EMOJI -> unknown icon:', missing); process.exit(1); }

  let dart = '// GENERATED by tool/icons/gen_icons.js — do not edit by hand.\n\n';
  dart += '/// Every icon that has a drawing in assets/images/icons/.\n';
  dart += 'const Set<String> kGameIconKeys = {\n' + keys.map((k) => `  '${k}',`).join('\n') + '\n};\n\n';
  dart += '/// Emoji (variation selector stripped) -> icon key.\n';
  dart += 'const Map<String, String> kEmojiToIcon = {\n' + Object.entries(EMOJI).map(([e, k]) => `  '${[...e].map((c) => '\\u{' + c.codePointAt(0).toString(16).toUpperCase() + '}').join('')}': '${k}', // ${k}`).join('\n') + '\n};\n';
  fs.writeFileSync(path.resolve(__dirname, '../../lib/core/theme/game_icon_data.dart'), dart);

  if (process.argv[2]) { // contact sheet
    const cols = 14, cell = 96, rows = Math.ceil(keys.length / cols);
    const sheet = createCanvas(cols * cell, rows * cell);
    const sc = sheet.getContext('2d');
    sc.fillStyle = '#4a3d30'; sc.fillRect(0, 0, sheet.width, sheet.height);
    keys.forEach((k, i) => sc.drawImage(canvases[k], (i % cols) * cell, Math.floor(i / cols) * cell, cell, cell));
    fs.writeFileSync(process.argv[2], sheet.toBuffer('image/png'));
  }
  console.log('icons:', keys.length, 'emoji mapped:', Object.keys(EMOJI).length);
})();
