// node build.js out.html — icon inventory (real game icons) + 10 pixel-art proposals per concept.
const fs = require('fs'), path = require('path');
const { cv } = require('./engine.js');
const CONCEPTS = [...require('./designs_resources.js').CONCEPTS, ...require('./designs_combat.js').CONCEPTS, ...require('./designs_status.js').CONCEPTS, ...require('./designs_places.js').CONCEPTS, ...require('./designs_things.js').CONCEPTS, ...require('./designs_tools.js').CONCEPTS, ...require('./designs_more1.js').CONCEPTS, ...require('./designs_life.js').CONCEPTS, ...require('./designs_more2.js').CONCEPTS, ...require('./designs_ui.js').CONCEPTS];
const outsOf = (k) => k.outs || (k.cols ? Object.entries(k.cols).map(([key, [lbl, hex]]) => [key, lbl, hex, null]) : [[k.key, k.name, undefined, null]]);
const ICON_DIR = path.resolve(__dirname, '../../../assets/images/icons');
const keys = fs.readFileSync(path.resolve(__dirname, '../../../lib/core/theme/game_icon_data.dart'), 'utf8')
  .split('kEmojiToIcon')[0].match(/'([A-Za-z0-9]+)'/g).map((s) => s.slice(1, -1));

const CATS = [
  ['Rohstoffe & Nahrung', 'coin wood stone ironOre copperOre silverOre goldOre coal clay lime sand ruby gem crystalBlue crystalCyan brick nut frame fish meat wine chili salt coffee tea flower basket herb sprout grass tree ice vase gift'],
  ['Werkzeug, Forschung, Heilung', 'hammer saw axe pickaxe wrench scissors tools crane trap bandage stethoscope syringe microscope dna alembic testtube sponge wand medical clipboard dumbbell'],
  ['Kampf & Zustände', 'sword swords shield heart heartPink heartGreen hearts bolt flame blood skull skullBones boom anger dizzy faceFear faceSleep faceCold zzz snow wind drop target goal dot dotBlue banned warning'],
  ['Gebäude & Welt', 'house timberHouse castle tent factory bank derelict road roadOff map globe compass pin flag door moon sun wave candle bed ball cart truck truckSmall train crate backpack lock'],
  ['Monster, Tiere, Leute', 'paw egg beaver horse turtle fox camel snail chick moai person groups personAdd worker gi robot shades gradcap footprints boot shoe'],
  ['Zeit, Aufgaben, Soziales', 'clock hourglass stopwatch bell tasks book bookmark chat tag trophy medal crown star balance exchange cycle save battery party dice'],
];
const seen = new Set(); const cats = [];
for (const [name, list] of CATS) { const ks = list.split(' ').filter((k) => keys.includes(k)); ks.forEach((k) => seen.add(k)); cats.push([name, ks]); }
const rest = keys.filter((k) => !seen.has(k));
const GLYPHS = 'x plus minus left right up down arrowLeft arrowRight arrowUp arrowDown caretDown caretUp check checkCircle search sort filter starO swapH refresh info help question error eyeOff eye pencil picture chart chartBars grid hex drag move box boxOn ring vibration volume wifiOff play playBack forward rewind pause'.split(' ');
cats.push(['Bedienelemente (UI-Glyphen)', rest.filter((k) => GLYPHS.includes(k))]);
const other = rest.filter((k) => !GLYPHS.includes(k));
if (other.length) cats.push(['Weitere', other]);

const uri = (buf, mime = 'image/png') => `data:${mime};base64,${buf.toString('base64')}`;
const cur = (k) => uri(fs.readFileSync(path.join(ICON_DIR, k + '.webp')), 'image/webp');
const img = (src, alt, cls = '') => `<img class="px ${cls}" src="${src}" alt="${alt}" width="96" height="96">`;

const inv = cats.map(([n, ks]) => `<section class="cat"><h3>${n} <span>${ks.length}</span></h3><div class="inv">${ks.map((k) => `<figure>${img(cur(k), k)}<figcaption>${k}</figcaption></figure>`).join('')}</div></section>`).join('');

const COUNT = CONCEPTS.length;
let lastCat = '';
const BATCH = { Forschung: ['Entwürfe: Forschung und Werkzeug-Rest', 'Stethoskop, Mikroskop, DNA, Hantel, Klemmbrett, Schwamm und Werkzeugset. Hier sind die Entwürfe über Farbe und Beigaben unterschiedlich.'], Zeit: ['Entwürfe: Zeit, Aufgaben, Belohnungen', 'Uhr, Sanduhr, Stoppuhr, Glocke, Aufgabenliste, Buch, Lesezeichen, Chat, Preisschild, Pokal, Medaille, Krone, Stern, Waage, Tausch, Kreislauf, Speichern, Batterie, Feier und Würfel.'], Leute: ['Entwürfe: Tiere, Leute, Kleidung', 'Die acht Tiere haben denselben Satz Darstellungen (Gesicht, Chibi, Medaillon, Schlafend und so weiter), damit sie zusammenpassen. Der Rucksack steht unter Natur und Gegenstände.'], Natur: ['Entwürfe: Natur, Essen, Dinge', 'Zahnrad, Funken, Mülleimer, Vase, Geschenk, Korb, Pflanzen, Baum, Eis, Fleisch, Wein, Chili, Salz, Kaffee, Tee, Mutter, Ziegel, Rahmen, Ball, Kran und Tor.'], Bedienelemente: ['Entwürfe: Bedienelemente', 'Jede Form ist einmal gezeichnet und in zehn Behandlungen gezeigt: Eisweiß (wie bisher), Gold, Plättchen, rund, Stahl, fein, fett, grün, Holz, dunkel. Familien wie Plus/Minus/Schließen oder die vier Pfeile ändern sich gemeinsam.'],  Rohstoffe: ['Entwürfe: Rohstoffe', 'Auswahl vom 10.11. ist im Spiel (Holz 1, Stein 1, Münze 6, Fisch 1, Erze 1, Lehm/Sand/Kalk 1, Edelsteine 10). Erze, Lehm/Sand/Kalk und Edelsteine sind je eine Familie: eine Zeichnung gilt für alle Farben.'], Werkzeug: ['Entwürfe: Werkzeug und Heilung', 'Kolben und Reagenzglas sind eine Familie (alembic und testtube, gleiche Farbe und Machart). Stethoskop, Mikroskop, DNA, Hantel, Klemmbrett, Schwamm und Werkzeugset folgen noch.'], Dinge: ['Entwürfe: Natur und Gegenstände', 'Auswahl ist im Spiel (Karte 2, Globus 2, Kompass 1, Sonne 1, Mond 2, Welle 1, Kerze 1, Kiste 10, Schloss 1, Karren 2, Bett 1). Der Rucksack ist offen. Zu Karren, Truck und Lok gibt es nur einen gemeinsamen Karren-Entwurf („cart"). Zug und Lastwagen sind als Varianten 7 und 8 dabei.'], Gebäude: ['Entwürfe: Gebäude und Orte', 'Straße und gesperrte Straße sind eine Familie: Das Verbot ist dieselbe Straße mit rotem Balken.'], Zustände: ['Entwürfe: Zustände', 'Die drei Gesichter (Angst, Schlaf, Kälte) sind eine Familie: Eine Wahl bestimmt den Stil aller drei.'], Kampf: ['Entwürfe: Kampf', 'Auswahl ist im Spiel (Schwert 1, Gekreuzt 1, Schild 2, Herz 1, Blitz 1, Flamme 2, Tropfen 1, Totenkopf 1, Explosion 1). Herzen, Tropfen/Blut und Totenkopf sind Familien: Eine Wahl gilt für alle Varianten (Herz rot/rosa/grün, Tropfen/Blut, Totenkopf mit und ohne Knochen).'] };
const props = CONCEPTS.map((k, ci) => {
  const head = k.cat !== lastCat ? (lastCat = k.cat, `<h2>${BATCH[k.cat][0]}</h2><p class="lead">${BATCH[k.cat][1]}</p>`) : '';
  const id = k.key || k.family;
  const outs = outsOf(k), multi = outs.length > 1;
  const currents = outs.map((o) => o[0]);
  const cards = k.designs.map(([name, desc, fn], i) => {
    const imgs = outs.map(([ok, cn, hex, pre, post]) => { const c = cv(); if (pre) pre(c); fn(c, hex); if (post) post(c); return img(uri(c.render()), cn, multi ? 'sm' : ''); }).join('');
    return `<button type="button" class="card" data-c="${id}" data-i="${i + 1}" aria-pressed="false"><span class="no">${i + 1}</span><span class="art ${multi ? 'fam' : ''}">${imgs}</span><b>${name}</b><small>${desc}</small></button>`;
  }).join('');
  const now = currents.map((ck) => `<figure>${img(cur(ck), ck, 'sm')}<figcaption>${ck}</figcaption></figure>`).join('');
  return head + `<section class="concept" data-name="${k.name}"><header><h3>${k.name}</h3><div class="now"><span>Bisher</span>${now}</div></header><div class="grid">${cards}</div></section>`;
}).join('');

const html = `<title>Icon-Entwürfe Boddy</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* Layout: sticky pick bar, inventory grid, then one band of 10 proposals per icon concept. Icons always sit on the game's steel-blue ground. */
:root{--bg:#eef1f4;--fg:#1c2733;--mut:#5b6b7a;--line:#cdd5dd;--panel:#fff;--accent:#c58a12;--ground:#243645;--ground2:#2d4357;--cap:#9fb4c6}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#14202b;--fg:#e6edf3;--mut:#93a5b5;--line:#2c3e4d;--panel:#1b2b39;--accent:#f0b43a;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#14202b;--fg:#e6edf3;--mut:#93a5b5;--line:#2c3e4d;--panel:#1b2b39;--accent:#f0b43a;color-scheme:dark}
body{background:var(--bg);color:var(--fg);font:15px/1.5 "Barlow",system-ui,sans-serif;padding-block:0 4rem;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
.wrap{max-width:1180px;margin:0 auto}
h1,h2,h3{font-family:"Barlow Condensed","Arial Narrow",sans-serif;letter-spacing:.02em;text-wrap:balance;margin:0}
h1{font-size:2.4rem;line-height:1.05;margin-top:1.6rem}h2{font-size:1.7rem;margin:2.6rem 0 .3rem}h3{font-size:1.25rem}
p.lead{max-width:65ch;color:var(--mut);margin:.6rem 0 0}
.px{image-rendering:pixelated;display:block;width:96px;height:96px}.px.sm{width:48px;height:48px}
.cat h3{margin:1.6rem 0 .6rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}.cat h3 span{color:var(--mut);font-size:.95rem;font-weight:500;margin-left:.4rem}
.inv{display:grid;grid-template-columns:repeat(auto-fill,minmax(84px,1fr));gap:8px}
.inv figure,.now figure{margin:0;background:var(--ground);border-radius:4px;padding:8px 4px 4px;text-align:center;display:flex;flex-direction:column;align-items:center;min-width:0}
.inv .px{width:64px;height:64px}
figcaption{font-size:.7rem;color:var(--cap);margin-top:2px;overflow-wrap:anywhere}
.concept{margin-top:1.8rem;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:14px}
.concept header{display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center;justify-content:space-between;margin-bottom:12px}
.now{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.now span{font-size:.75rem;text-transform:uppercase;letter-spacing:.08em;color:var(--mut);margin-right:4px}
.now .px{width:36px;height:36px}.now figure{padding:4px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.card{font:inherit;color:var(--cap);text-align:left;background:var(--ground);border:2px solid transparent;border-radius:6px;padding:8px;cursor:pointer;display:flex;flex-direction:column;gap:2px;position:relative;min-width:0}
.card:hover{background:var(--ground2)}.card:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.card[aria-pressed="true"]{border-color:var(--accent);background:var(--ground2)}
.card b{color:#e6edf3;font-weight:600;font-size:.9rem}.card small{font-size:.75rem;line-height:1.3}
.no{position:absolute;top:6px;left:8px;font:600 .8rem "Barlow Condensed",sans-serif;color:var(--accent)}
.art{display:flex;justify-content:center;min-height:96px;align-items:center}.art.fam{flex-wrap:wrap;gap:0;min-height:96px;align-content:center}
.card[aria-pressed="true"] .no::after{content:" ✓"}
#bar{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:8px 12px;margin-top:1rem;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
#bar output{flex:1 1 260px;font-size:.85rem;color:var(--mut);min-width:0}
#bar button{font:inherit;font-weight:600;background:var(--accent);color:#1c1500;border:0;border-radius:4px;padding:6px 14px;cursor:pointer}
.todo{margin-top:2rem;color:var(--mut);max-width:70ch}
</style>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow:wght@400;600&family=Barlow+Condensed:wght@500;700&display=swap">
<div class="wrap">
<h1>Icons für Boddy</h1>
<p class="lead">Teil 1 listet alle ${keys.length} Icons, die das Spiel heute hat, in der echten Darstellung (24 × 24 Pixel, vierfach vergrößert). Danach folgen zu jedem Icon 10 Entwürfe im gleichen Pixelstil. Tippe einen Entwurf an, um ihn zu merken.</p>
<div id="bar"><output id="pick">Noch nichts gewählt.</output><button id="copy" type="button">Auswahl kopieren</button></div>

<h2>1 · Alle Icons im Spiel</h2>
${inv}

${props}
<p class="todo">Alle Gruppen aus Teil 1 haben jetzt Entwürfe. Nur gezeichnet ist noch nichts für die drei Fahrzeug-Icons truck, truckSmall und train, die als Karren-Varianten dabei sind.</p>
</div>
<script>
const sel={};try{Object.assign(sel,JSON.parse(localStorage.getItem('boddyIconPicks')||'{}'))}catch(e){}
const names={};document.querySelectorAll('.concept').forEach(s=>{const c=s.querySelector('.card').dataset.c;names[c]=s.dataset.name});
function paint(){document.querySelectorAll('.card').forEach(b=>b.setAttribute('aria-pressed',String(sel[b.dataset.c]==b.dataset.i)));
const t=Object.entries(sel).map(([c,i])=>names[c]+': Nr. '+i);document.getElementById('pick').textContent=t.length?t.join(' · '):'Noch nichts gewählt.';
try{localStorage.setItem('boddyIconPicks',JSON.stringify(sel))}catch(e){}}
document.addEventListener('click',e=>{const b=e.target.closest('.card');if(!b)return;if(sel[b.dataset.c]==b.dataset.i)delete sel[b.dataset.c];else sel[b.dataset.c]=b.dataset.i;paint()});
document.getElementById('copy').onclick=()=>{const t=document.getElementById('pick').textContent;try{navigator.clipboard.writeText(t).then(()=>{},()=>{})}catch(e){}};
paint();
</script>`;
fs.writeFileSync(process.argv[2], html);
console.log('keys', keys.length, 'uncat', other, 'bytes', html.length);
