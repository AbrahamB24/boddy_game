// node preview.js out.png  — contact sheet of all drawn designs (rows = concept, first colour for families)
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const fs = require('fs');
const { cv } = require('./engine.js');
const { CONCEPTS } = require(process.argv[3] || './designs_resources.js');

(async () => {
  const S = 5, P = 24 * S + 8;
  const rows = CONCEPTS.flatMap((k) => (k.outs ? k.outs.map((o) => o[0]) : k.cols ? Object.keys(k.cols) : [null]).map((ck) => [k, ck]));
  const c = createCanvas(10 * P, rows.length * P), g = c.getContext('2d');
  g.fillStyle = '#243645'; g.fillRect(0, 0, c.width, c.height); g.imageSmoothingEnabled = false;
  for (let r = 0; r < rows.length; r++) {
    const [k, ck] = rows[r];
    for (let i = 0; i < k.designs.length; i++) {
      const cc = cv(); const o = k.outs ? k.outs.find((q) => q[0] === ck) : null; if (o && o[3]) o[3](cc); k.designs[i][2](cc, o ? o[2] : ck && k.cols ? k.cols[ck][1] : undefined); if (o && o[4]) o[4](cc);
      g.drawImage(await loadImage(cc.render()), i * P + 4, r * P + 4, 24 * S, 24 * S);
    }
  }
  fs.writeFileSync(process.argv[2], c.toBuffer('image/png'));
})();
