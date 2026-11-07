// One-off: switch every lib file that uses Text(...) to the emoji-aware Text.
const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '../../lib');
const target = path.join(root, 'core/ui/game_text.dart');
let changed = 0;
(function walk(d) {
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name);
    if (f.isDirectory()) { walk(p); continue; }
    if (!f.name.endsWith('.dart') || p === target) continue;
    let s = fs.readFileSync(p, 'utf8');
    if (s.includes("core/ui/game_text.dart") || s.includes('game_text.dart')) continue;
    if (!/(?<![\w.])Text(\.rich)?\(/.test(s)) continue;
    const re = /import 'package:flutter\/(material|widgets|cupertino)\.dart';/g;
    if (!re.test(s)) continue;
    s = s.replace(re, (m, lib) => `import 'package:flutter/${lib}.dart' hide Text;`);
    let rel = path.relative(path.dirname(p), target).split(path.sep).join('/');
    const nl = s.includes('\r\n') ? '\r\n' : '\n';
    // insert after the last import line
    const lines = s.split(/\r?\n/);
    let last = -1;
    lines.forEach((l, i) => { if (/^import\s/.test(l)) last = i; });
    lines.splice(last + 1, 0, `import '${rel}';`);
    fs.writeFileSync(p, lines.join(nl));
    changed++;
  }
})(root);
console.log('files changed:', changed);
