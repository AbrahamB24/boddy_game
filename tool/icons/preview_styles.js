// Style preview: current flat vs "realistic" vs voxel, same icons. Not part of the app.
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const fs = require('fs'), path = require('path');
const { ICONS } = require('./icons_base.js');
const { ICONS_EXTRA } = require('./icons_extra.js');
const ALL = { ...ICONS, ...ICONS_EXTRA };
const PICK = ['coin','wood','stone','gem','heart','sword','shield','house','egg','star','bolt','flame','fish','meat','crown','trophy','bell','hammer','backpack','trap','bandage','skull','lock','map','coffee','wine','ironOre','crystalBlue'];
const VB = '-3 -3 70 70', ROLES = ['a','b','k','c'];
const out = process.argv[2];

const hex = (h) => [1,3,5].map(i => parseInt(h.slice(i,i+2),16));
const mixc = (c, t, k) => c.map((v,i) => Math.round(v + (t[i]-v)*k));
const css = (c, a=1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

async function layerImg(inner, color, S) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" width="${S}" height="${S}"><g fill="${color}">${inner.replace(/#000/g, color)}</g></svg>`;
  return loadImage(Buffer.from(svg));
}

// ── realistic ───────────────────────────────────────────────
async function realistic(def, S) {
  const body = createCanvas(S, S), bx = body.getContext('2d');
  for (const r of ROLES) {
    const inner = def.L[r]; if (!inner) continue;
    const col = hex(def.col[r]);
    const mask = await layerImg(inner, '#000000', S);
    const lay = createCanvas(S, S), lx = lay.getContext('2d');
    lx.drawImage(mask, 0, 0);
    lx.globalCompositeOperation = 'source-in';
    const g = lx.createRadialGradient(S*.34, S*.28, S*.04, S*.5, S*.55, S*.75);
    g.addColorStop(0, css(mixc(col,[255,255,255],.45)));
    g.addColorStop(.45, css(col));
    g.addColorStop(1, css(mixc(col,[0,0,0],.45)));
    lx.fillStyle = g; lx.fillRect(0,0,S,S);
    // bevel: light rim top-left, dark rim bottom-right
    const rim = (dx, dy, color, a) => {
      const t = createCanvas(S, S), tx = t.getContext('2d');
      tx.drawImage(mask, 0, 0);
      tx.globalCompositeOperation = 'destination-out';
      tx.drawImage(mask, dx, dy);
      tx.globalCompositeOperation = 'source-in';
      tx.fillStyle = color; tx.globalAlpha = a; tx.fillRect(0,0,S,S);
      lx.globalCompositeOperation = 'source-atop';
      lx.drawImage(t, 0, 0);
    };
    rim(S*.02, S*.02, '#ffffff', .65);
    rim(-S*.02, -S*.02, '#000000', .35);
    bx.drawImage(lay, 0, 0);
  }
  // gloss
  bx.globalCompositeOperation = 'source-atop';
  const gl = bx.createLinearGradient(0, 0, 0, S*.55);
  gl.addColorStop(0, 'rgba(255,255,255,.30)'); gl.addColorStop(1, 'rgba(255,255,255,0)');
  bx.fillStyle = gl; bx.fillRect(0, 0, S, S*.55);
  bx.globalCompositeOperation = 'source-over';
  const o = createCanvas(S, S), ox = o.getContext('2d');
  ox.shadowColor = 'rgba(0,0,0,.55)'; ox.shadowBlur = S*.05; ox.shadowOffsetY = S*.035;
  ox.drawImage(body, 0, 0);
  return o;
}

// ── voxel ───────────────────────────────────────────────────
async function voxelGrid(def, G) {
  const px = new Array(G*G).fill(null);
  for (const r of ROLES) {
    const inner = def.L[r]; if (!inner) continue;
    const img = await layerImg(inner, '#000000', G);
    const c = createCanvas(G, G), x = c.getContext('2d'); x.drawImage(img, 0, 0);
    const d = x.getImageData(0,0,G,G).data;
    for (let i = 0; i < G*G; i++) if (d[i*4+3] >= 120) px[i] = def.col[r];
  }
  return px;
}
function voxel(px, G, u, D, seed) {
  const W = G*u + D*u*.5 + 8, H = G*u + D*u*.5 + 8;
  const c = createCanvas(Math.ceil(W), Math.ceil(H)), x = c.getContext('2d');
  const ox = 4, oy = D*u*.5 + 4;
  let s = seed; const rnd = () => (s = (s*1664525 + 1013904223) >>> 0) / 4294967296;
  const has = (gx, gy) => gx >= 0 && gy >= 0 && gx < G && gy < G && px[gy*G+gx];
  const poly = (pts, color) => { x.beginPath(); pts.forEach(([a,b],i)=> i? x.lineTo(a,b): x.moveTo(a,b)); x.closePath(); x.fillStyle = color; x.fill(); x.strokeStyle='rgba(0,0,0,.28)'; x.lineWidth=.8; x.stroke(); };
  const dx = u*.5, dy = -u*.5;
  // back to front, within a layer top-left to bottom-right so nearer cubes overdraw
  for (let z = D-1; z >= 0; z--) {
    for (let gy = 0; gy < G; gy++) for (let gx = G-1; gx >= 0; gx--) {
      const hexc = has(gx, gy); if (!hexc) continue;
      const base = hex(hexc), j = (rnd()-.5)*18;
      const col = base.map(v => Math.max(0, Math.min(255, v + j)));
      const X = ox + gx*u + z*dx, Y = oy + gy*u + z*dy + (D*u*.0);
      const frontOnly = z === 0;
      // right face (visible if no neighbour right) and top face (no neighbour above)
      if (!has(gx+1, gy)) poly([[X+u,Y],[X+u+dx,Y+dy],[X+u+dx,Y+u+dy],[X+u,Y+u]], css(mixc(col,[0,0,0],.38)));
      if (!has(gx, gy-1)) poly([[X,Y],[X+dx,Y+dy],[X+u+dx,Y+dy],[X+u,Y]], css(mixc(col,[255,255,255],.30)));
      if (frontOnly) poly([[X,Y],[X+u,Y],[X+u,Y+u],[X,Y+u]], css(col));
    }
  }
  return c;
}

(async () => {
  const cell = 150, cols = 7, rows = Math.ceil(PICK.length/cols);
  const mk = (bg) => { const c = createCanvas(cols*cell, rows*cell); const x = c.getContext('2d'); x.fillStyle = bg; x.fillRect(0,0,c.width,c.height); return [c,x]; };
  const [R, rx] = mk('#4a3d30'), [V, vx] = mk('#4a3d30'), [V2, v2x] = mk('#4a3d30');
  let i = 0;
  for (const k of PICK) {
    const def = ALL[k], cx = (i%cols)*cell, cy = Math.floor(i/cols)*cell; i++;
    const r = await realistic(def, 160);
    rx.drawImage(r, cx+5, cy+5, 140, 140);
    const g = await voxelGrid(def, 22);
    const v = voxel(g, 22, 5.2, 4, 7 + i);
    vx.drawImage(v, cx + (cell-v.width)/2, cy + (cell-v.height)/2);
    const g2 = await voxelGrid(def, 14);
    const v2 = voxel(g2, 14, 8, 6, 3 + i);
    v2x.drawImage(v2, cx + (cell-v2.width)/2, cy + (cell-v2.height)/2);
  }
  fs.writeFileSync(path.join(out, 'realistic.png'), R.toBuffer('image/png'));
  fs.writeFileSync(path.join(out, 'voxel22.png'), V.toBuffer('image/png'));
  fs.writeFileSync(path.join(out, 'voxel14.png'), V2.toBuffer('image/png'));
  console.log('ok', PICK.length);
})();
