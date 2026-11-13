// node apply_picks.js — writes the chosen proposals listed in picks.txt ("Konzeptname: Nr. N · ...")
// over assets/images/icons/<key>.webp. Picks are matched by the concept names shown on the proposal page.
const fs = require('fs'), path = require('path');
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const { cv } = require('./engine.js');
const CONCEPTS = ['resources', 'combat', 'status', 'places', 'things', 'tools', 'more1', 'life', 'more2', 'ui'].flatMap((n) => require(`./designs_${n}.js`).CONCEPTS);
const picks = Object.fromEntries(fs.readFileSync(path.join(__dirname, 'picks.txt'), 'utf8').trim().split(' · ').map((s) => { const m = s.match(/^(.*): Nr\. (\d+)$/); return [m[1], +m[2]]; }));
const OUT = path.resolve(__dirname, '../../../assets/images/icons');
(async () => {
  const unknown = Object.keys(picks).filter((n) => !CONCEPTS.some((k) => k.name === n)); if (unknown.length) console.log('UNKNOWN', unknown);
  let n = 0;
  for (const k of CONCEPTS) {
    if (!picks[k.name]) continue;
    const fn = k.designs[picks[k.name] - 1][2];
    const jobs = k.outs ? k.outs.map((o) => [o[0], o[2], o[3], o[4]]) : k.cols ? Object.entries(k.cols).map(([key, [, hex]]) => [key, hex]) : [[k.key, undefined]];
    for (const [key, hex, pre, post] of jobs) {
      const file = path.join(OUT, key + '.webp');
      if (!fs.existsSync(file)) { console.log('SKIP (no such icon)', key); continue; }
      const c = cv(); if (pre) pre(c); fn(c, hex); if (post) post(c);
      const cvs = createCanvas(24, 24); cvs.getContext('2d').drawImage(await loadImage(c.render()), 0, 0);
      fs.writeFileSync(file, cvs.toBuffer('image/webp', 100)); n++;
    }
  }
  console.log('written', n);
})();
