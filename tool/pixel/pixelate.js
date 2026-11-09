// Pixelates the HUD's rendered glyphs for the pixel-wood look (UiArt.pixelWood).
//
// What it does to each picture: trim to the opaque box, area-average down to a
// tiny grid (long side = the number in JOBS), snap alpha to on/off, posterise
// the colours to steps of 24, then add the carved edge: one dark pixel outside
// the top-left rim and one light pixel outside the bottom-right rim, so the
// glyph reads as cut into the wood board it sits on.
//
// The app draws the result with FilterQuality.none at scale 0.5, i.e. every
// pixel is 2 logical px. Needs node + ffmpeg on PATH.
//   node tool/pixel/pixelate.js
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', '..', 'assets', 'images', 'ui');
const OUT = path.join(__dirname, '..', '..', 'assets', 'images', 'ui_px');
const JOBS = [
  // name, long side in pixels, optional pre-crop (ffmpeg crop filter)
  ['hud_log', 12], ['hud_stone', 12], ['hud_fish', 12], ['hud_coin', 12],
  ['hud_house', 12], ['hud_clock', 12],
  ['icon_hammer', 20], ['icon_paw', 20], ['icon_map', 20], ['icon_people', 20],
  ['icon_person', 20], ['icon_bag', 20], ['icon_tasks', 20], ['icon_monster', 20],
  ['chest_nr', 40],
  ['badge_bolt_bare', 16], ['badge_gear_bare', 16], ['chest_nr', 16, null, 'chest_s'],
  ['globe', 32, 'crop=512:512:0:0'],
  ['bell', 56],
];
const DARK = [46, 26, 14, 190];
const LIGHT = [242, 232, 204, 230];

function raw(src, vf, w, h) {
  return execFileSync('ffmpeg', ['-loglevel', 'error', '-i', src, '-vf', vf, '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'],
    { maxBuffer: 1 << 28 });
}
function probe(src, pre) {
  const vf = (pre ? pre + ',' : '') + 'format=rgba';
  const out = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', src]).toString().trim().split(',');
  return [Number(out[0]), Number(out[1]), vf];
}

for (const [name, n, pre, outName] of JOBS) {
  const src = path.join(SRC, name + '.webp');
  let [w, h] = probe(src);
  if (pre) { const m = /crop=(\d+):(\d+)/.exec(pre); w = +m[1]; h = +m[2]; }
  const full = raw(src, (pre ? pre + ',' : '') + 'format=rgba');
  // opaque bounding box
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (full[(y * w + x) * 4 + 3] > 24) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  }
  const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  const k = n / Math.max(bw, bh);
  const tw = Math.max(1, Math.round(bw * k)), th = Math.max(1, Math.round(bh * k));
  const vf = `${pre ? pre + ',' : ''}crop=${bw}:${bh}:${x0}:${y0},scale=${tw}:${th}:flags=area,format=rgba`;
  const small = raw(src, vf);
  const mw = tw + 2, mh = th + 2;
  const out = Buffer.alloc(mw * mh * 4);
  const op = new Uint8Array(mw * mh);
  for (let y = 0; y < th; y++) for (let x = 0; x < tw; x++) {
    const i = (y * tw + x) * 4, o = ((y + 1) * mw + (x + 1)) * 4;
    if (small[i + 3] > 110) {
      op[(y + 1) * mw + (x + 1)] = 1;
      for (let c = 0; c < 3; c++) out[o + c] = Math.min(255, Math.round(small[i + c] / 24) * 24);
      out[o + 3] = 255;
    }
  }
  const at = (x, y) => x >= 0 && y >= 0 && x < mw && y < mh && op[y * mw + x];
  for (let y = 0; y < mh; y++) for (let x = 0; x < mw; x++) {
    if (op[y * mw + x]) continue;
    const o = (y * mw + x) * 4;
    const c = at(x + 1, y + 1) ? DARK : at(x - 1, y - 1) ? LIGHT : null;
    if (c) { out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2]; out[o + 3] = c[3]; }
  }
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${mw}x${mh}`, '-i', '-', path.join(OUT, (outName || name) + '.png')], { input: out });
  console.log(outName || name, `${mw}x${mh}`);
}
