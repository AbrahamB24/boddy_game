// The REALISTIC FANTASY renderer (user 2026-11-04): embossed, grained, inked.
// One icon = layers in the roles a b d e k c (painted in that order), each filled
// with a lit-to-shaded gradient, grain, a bevel and a thin dark contour, then one
// heavy ink outline and a soft shadow round the whole.
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const VB = '-3 -3 70 70';
const ROLES = ['a', 'b', 'd', 'e', 'k', 'c'];
const hex = (h) => { if (h.length === 4) h = '#' + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]; return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)); };
const mix = (c, t, k) => c.map((v, i) => Math.round(v + (t[i] - v) * k));
const rgb = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
const lum = (c) => (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255;

// Earthy, slightly desaturated: leather, steel, gold, bone — not toy colours.
function tone(h) {
  const c = hex(h);
  const g = Math.round(lum(c) * 255);
  return mix(mix(c, [g, g, g], 0.22), [30, 18, 8], 0.08);
}

async function layerMask(inner, size) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" width="${size}" height="${size}"><g fill="#000">${inner}</g></svg>`;
  return loadImage(Buffer.from(svg));
}

let seed = 7;
const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;

async function fantasy(def, size) {
  const body = createCanvas(size, size);
  const bx = body.getContext('2d');
  for (const r of ROLES) {
    const inner = def.L[r];
    if (!inner) continue;
    const base = tone((def.col && def.col[r]) || '#d8d0bc');
    const mask = await layerMask(inner, size);
    const lay = createCanvas(size, size);
    const lx = lay.getContext('2d');
    lx.drawImage(mask, 0, 0);
    lx.globalCompositeOperation = 'source-in';
    // light from the top left: lit, base, then a deep shade
    const g = lx.createLinearGradient(size * 0.15, size * 0.05, size * 0.85, size * 0.95);
    g.addColorStop(0, rgb(mix(base, [255, 245, 220], 0.42)));
    g.addColorStop(0.38, rgb(base));
    g.addColorStop(1, rgb(mix(base, [10, 6, 2], 0.58)));
    lx.fillStyle = g;
    lx.fillRect(0, 0, size, size);
    // grain: a fine, fixed noise so the surface is not a plastic fill
    const grain = lx.getImageData(0, 0, size, size);
    const d = grain.data;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] === 0) continue;
      const n = (rnd() - 0.5) * 26;
      d[i] = Math.max(0, Math.min(255, d[i] + n));
      d[i + 1] = Math.max(0, Math.min(255, d[i + 1] + n));
      d[i + 2] = Math.max(0, Math.min(255, d[i + 2] + n));
    }
    lx.putImageData(grain, 0, 0);
    // bevel: a lit rim on the top-left edge, a dark one on the bottom-right
    const rim = (dx, dy, col, a) => {
      const t = createCanvas(size, size);
      const tx = t.getContext('2d');
      tx.drawImage(mask, 0, 0);
      tx.globalCompositeOperation = 'destination-out';
      tx.drawImage(mask, dx, dy);
      tx.globalCompositeOperation = 'source-in';
      tx.fillStyle = col;
      tx.globalAlpha = a;
      tx.fillRect(0, 0, size, size);
      lx.globalCompositeOperation = 'source-atop';
      lx.drawImage(t, 0, 0);
    };
    rim(size * 0.016, size * 0.016, '#fff4d6', 0.6);
    rim(-size * 0.016, -size * 0.016, '#120a04', 0.5);
    // a thin dark edge round every part, as an engraved line
    const edge = createCanvas(size, size);
    const ex = edge.getContext('2d');
    ex.drawImage(mask, 0, 0);
    ex.globalCompositeOperation = 'destination-out';
    ex.drawImage(mask, 0, 0);
    bx.drawImage(lay, 0, 0);
    // contour of this part
    const o = size * 0.008;
    const c2 = createCanvas(size, size);
    const cx = c2.getContext('2d');
    for (let i = 0; i < 8; i++) {
      const t = (i / 8) * Math.PI * 2;
      cx.drawImage(mask, Math.cos(t) * o, Math.sin(t) * o);
    }
    cx.globalCompositeOperation = 'destination-out';
    cx.drawImage(mask, 0, 0);
    cx.globalCompositeOperation = 'source-in';
    cx.fillStyle = 'rgba(25,14,6,0.7)';
    cx.fillRect(0, 0, size, size);
    bx.drawImage(c2, 0, 0);
  }
  // ambient shade over the lower part, a soft gloss over the upper
  bx.globalCompositeOperation = 'source-atop';
  const sh = bx.createLinearGradient(0, size * 0.5, 0, size);
  sh.addColorStop(0, 'rgba(0,0,0,0)');
  sh.addColorStop(1, 'rgba(10,5,0,0.28)');
  bx.fillStyle = sh;
  bx.fillRect(0, 0, size, size);
  bx.globalCompositeOperation = 'source-over';
  // heavy dark outline + soft shadow, like an inked miniature
  const sil = createCanvas(size, size);
  const sx = sil.getContext('2d');
  sx.drawImage(body, 0, 0);
  sx.globalCompositeOperation = 'source-in';
  sx.fillStyle = '#1a0f07';
  sx.fillRect(0, 0, size, size);
  const out = createCanvas(size, size);
  const ox = out.getContext('2d');
  const w = size * 0.022;
  ox.shadowColor = 'rgba(0,0,0,0.5)';
  ox.shadowBlur = size * 0.04;
  ox.shadowOffsetY = size * 0.02;
  for (let i = 0; i < 16; i++) {
    const t = (i / 16) * Math.PI * 2;
    ox.drawImage(sil, Math.cos(t) * w, Math.sin(t) * w);
  }
  ox.shadowColor = 'transparent';
  ox.drawImage(body, 0, 0);
  return out;
}


module.exports = { fantasy };
