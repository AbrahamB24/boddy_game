# Icon-Liste: was das Spiel heute zeigt und was du liefern kannst

Stand 2026-09-28, aus dem Code gezogen (Tabellen und alle Emoji im UI-Code).

**Heute gibt es fast keine eigenen Icons.** Ressourcen, Items, Typen, Status usw. sind
**Emoji**, die Menü-Knöpfe sind **Material-Icons** (Google). Eigene Bilder gibt es nur
für Gebäude (24 von 82) und Strassen/Gelände. Jeder Eintrag unten ist also ein Platz,
den du durch ein eigenes Icon ersetzen kannst.

## Empfehlung für die Lieferung

| Thema | Vorschlag |
|---|---|
| Format | PNG oder WebP mit Transparenz (SVG geht auch, wird aber nicht direkt geladen) |
| Grösse | **256 × 256 px** Quelle. Angezeigt wird zwischen 12 und 56 px, also muss es klein noch lesbar sein |
| Stil | Ein Stil für alles: gleiche Kontur, gleiches Licht (Licht oben links, wie die Gebäudeschatten) |
| Farbe | Volle Farbe für Ressourcen/Items/Typen. Einfarbig (dunkelbraun `#2A1A0C`) nur für die reinen Menü-Symbole (Abschnitt H) |
| Dateiname | `gruppe_id.png`, z. B. `res_wood.png`, `type_fire.png`, `item_potion.png`, `status_burn.png` |

Die **ID** in den Tabellen ist der Name im Code. Halte dich daran, dann kann ich die
Icons ohne Umbenennen einhängen.

---

## A. Ressourcen (25)

Basis, dann pro Epoche 3 Dinge: ein Versorgungsgut, ein Rohstoff, ein Bauelement.
Epoche I hat nur Fisch (Holz/Stein/Gold gehören zu keiner Epoche).

| ID | Name | Epoche | Art | Heute |
|---|---|---|---|---|
| `wood` | Wood | – | Basis | 🪵 |
| `stone` | Stone | – | Basis | 🪨 |
| `gold` | Gold | – | Basis | 🪙 |
| `fish` | Fish | I | Versorgung | 🐟 |
| `meat` | Meat | II | Versorgung | 🥩 |
| `clay` | Clay | II | Rohstoff | 🟤 |
| `frame` | Timber Frame | II | Bauelement | 🪚 |
| `wine` | Wine | III | Versorgung | 🍷 |
| `lime` | Lime | III | Rohstoff | ⚪ |
| `daub` | Daub Wall | III | Bauelement | 🧱 |
| `spices` | Spices | IV | Versorgung | 🌶️ |
| `ore` | Ore | IV | Rohstoff | ⛏️ |
| `plaster` | Plastered Wall | IV | Bauelement | 🏛️ |
| `salt` | Salt | V | Versorgung | 🧂 |
| `coal` | Coal | V | Rohstoff | ⬛ |
| `truss` | Iron Truss | V | Bauelement | 🔩 |
| `coffee` | Coffee | VI | Versorgung | ☕ |
| `sand` | Sand | VI | Rohstoff | 🟡 |
| `clinker` | Fired Clinker | VI | Bauelement | 🔥 |
| `tea` | Tea | VII | Versorgung | 🍵 |
| `crystal` | Crystal | VII | Rohstoff | 💎 |
| `glasswork` | Glass Front | VII | Bauelement | 🔷 |
| `perfume` | Perfume | VIII | Versorgung | 🌸 |
| `aether` | Aether | VIII | Rohstoff | ✨ |
| `vault` | Crystal Vault | VIII | Bauelement | 💠 |

Hinweis: Die Emoji für Lime (⚪), Coal (⬛), Sand (🟡) und Clay (🟤) sind farbige Punkte
und kaum unterscheidbar. Dort lohnt sich ein eigenes Icon am meisten.

## B. Typen / Elemente (9)

Werden gross (Monsterkarte, Kampf) und klein (Chips) gezeigt. Farbe steht fest.

| ID | Name | Farbe | Heute |
|---|---|---|---|
| `type_fire` | Fire | `#E25822` | 🔥 |
| `type_ice` | Ice | `#8ED8F0` | 🧊 |
| `type_plant` | Plant | `#3BAE78` | 🌿 |
| `type_lightning` | Lightning | `#6C63FF` | ⚡ |
| `type_water` | Water | `#018ABE` | 💧 |
| `type_stone` | Stone | `#9B8365` | 🪨 |
| `type_light` | Light | `#E9B44C` | ✨ |
| `type_shadow` | Shadow | `#6B5B95` | 🌑 |
| `type_neutral` | Neutral | `#8B95A5` | ⚪ |

## C. Status-Effekte im Kampf (11 Hauptstatus + 13 Nebeneffekte)

Hauptstatus (ein Monster hat höchstens einen):

| ID | Name | Heute |
|---|---|---|
| `status_burn` | Burn | 🔥 |
| `status_frost` | Frost | ❄️ |
| `status_freeze` | Freeze | 🥶 |
| `status_poison` | Poison | ☠️ |
| `status_fear` | Fear | 😨 |
| `status_sleep` | Sleep | 😴 |
| `status_petrify` | Petrify | 🗿 |
| `status_paralysis` | Paralysis | ⚡ |
| `status_soaked` | Soaked | 💧 |
| `status_dazzled` | Dazzled | ✨ |
| `status_confusion` | Confusion | 💫 |

Nebeneffekte von Fähigkeiten (Buffs, Debuffs, Kosten):

| ID | Name | Heute | | ID | Name | Heute |
|---|---|---|---|---|---|---|
| `fx_blind` | Blind | 👁️ | | `fx_heal` | Heal | 💚 |
| `fx_slow` | Slow | 🐌 | | `fx_regen` | Regen | 🌱 |
| `fx_attack_down` | Attack down | 💤 | | `fx_lifesteal` | Lifesteal | 🩸 |
| `fx_defense_down` | Defense down | 🪓 | | `fx_recoil` | Recoil | 💥 |
| `fx_regression` | Regression | ⏪ | | `fx_armor` | Armor | 🛡️ |
| `fx_rage` | Rage | 💢 | | `fx_haste` | Haste | ⏱️ |
| `fx_self_cost` | Self-cost (Def/Speed) | ⚠️ | | | | |

## D. Items (Tasche)

### D1. Einzelne Items (heute 4 sinnvolle Icons)

| ID | Name | Heute |
|---|---|---|
| `item_minor_potion` | Minor Potion | 🧪 |
| `item_potion` | Potion | ⚗️ |
| `item_revive_charm` | Revive Charm | 💗 |
| `item_catch_lure` | Catch Lure | 🎏 |

### D2. Heil- und Reinigungsmittel (26 Items, aber nur wenige Bilder nötig)

Jede Krankheit hat ein **Remedy** (schwach) und ein **Elixir** (stark). Sinnvoll wären
**ein Flaschen-Icon pro Status mit dem Status-Symbol drauf** (11 Status × 2 Stärken,
oder ein Icon je Status plus ein Rahmen für „stark“). Dazu: `cure_any_weak` (Full Heal),
`cure_any_strong` (Full Restore), `cleanse_weak` (Cleansing Herb), `cleanse_strong`
(Cleansing Charm).

**Achtung, heute falsch belegt (Platzhalter):** Frost-Mittel zeigt ☀️, Freeze-Mittel 🔥,
Petrify-Mittel 🔨, Paralysis-Mittel 🔋, Soaked-Mittel 🧺, Fear-Mittel 🕯️. Diese Emoji
passen nicht zum Status, hier bringt ein eigenes Icon die grösste Verbesserung.

### D3. Ressourcen-Pakete (über 100 Items)

Jede Ressource hat Pakete in bis zu 6 Grössen. Es werden **nur 6 Paket-Symbole**
gebraucht, das Ressourcen-Icon (Abschnitt A) wird darübergelegt:

| Grösse | Heute |
|---|---|
| 10 | 🧺 (Korb) |
| 100 | 📦 (Kiste) |
| 500 | 🛒 (Karren) |
| 1 000 | 🚚 (Wagen) |
| 5 000 | 🚛 (Lastwagen) |
| 10 000 | 🚂 (Zug) |

Lastwagen und Zug passen nicht zum Mittelalter-Stil, dort besser Handkarren,
Pferdewagen, Schiff o. ä.

## E. Ereignisse (Glocke / Welcome back) (7)

| ID | Bedeutung | Heute |
|---|---|---|
| `event_levelup` | Level-up, geheilt, Fähigkeit gelernt | ⭐ |
| `event_expedition` | Expedition zurück | 🎒 |
| `event_caught` | Gefangen / Jagdergebnis | 🐾 |
| `event_research` | Forschung | 🔬 |
| `event_building` | Gebäude fertig | 🏕 |
| `event_breeding` | Zucht / Ei | 🥚 |
| `event_craft` | Handwerk / Handel | 🔨 |

## F. Arbeitsposten / Rollen (15)

Erscheinen im Gebäudedialog und bei den Sitzen der Arbeiter.

| ID | Rolle | Heute |
|---|---|---|
| `role_construction` | Bauen | 🔨 |
| `role_crafting` | Handwerk | ⚗️ |
| `role_training` | Training | 🏋️ |
| `role_legendary` | Legendär-Boost | ⭐ |
| `role_breeding` | Zucht | 💞 |
| `role_hatching` | Schlüpfen | 🐣 |
| `role_heal` | Heilen | 🩹 |
| `role_trade` | Handel | 💱 |
| `role_exp_travel` | Expedition: Reisezeit | 🥾 |
| `role_exp_carry` | Expedition: Traglast | 🎒 |
| `role_exp_goods` | Expedition: Güter | 📦 |
| `role_expedition` | Expedition | 🧭 |
| `role_caravan` | Karawane | 🐫 |
| `role_caravan_carry` | Karawane: Ladung | 🛒 |
| `role_storage` | Lagerraum | 🏚 |

## G. Monster-Werte, Seltenheit, Geschlecht

| Gruppe | Einträge | Heute |
|---|---|---|
| Kampfwerte | HP, Attack, Defense, Speed, Catch Rate | nur Text |
| Arbeitswerte | Gathering, Production, Construction, Crafting, Breeding, Healing, Trade, Logistics, Carry | nur Text |
| Seltenheit | Common, Uncommon, Rare, Epic, Legendary | nur Farbe (Grau/Grün/Blau/Violett/Gold) |
| Geschlecht | männlich, weiblich | ♂ ♀ |
| Kraft (Power) | ein Symbol für die Gesamtstärke | ⚡ |
| Weitere Symbole | Krone (Boss) 👑, K.O. 💀, schläft/erschöpft 💤, unterwegs 🎒, Zeit ⏳ ⏱, Gold 🪙, Herz/HP 💗 | Emoji |

Die 14 Werte haben aktuell gar kein Bild. Ein kleines Symbol je Wert würde die
Monsterseite deutlich lesbarer machen.

## H. Menü- und Bedienknöpfe (heute Material-Icons)

Diese sind einfarbig und klein. Hier reicht ein Satz Symbole in Dunkelbraun.

**Hauptknöpfe (Schnellleiste, 8):** Build, Manage, Map, Monsters, Social, Profile, Bag,
Daily tasks. (Heute runde farbige Knöpfe mit Material-Symbol; Farben stehen fest:
Build Gold, Monsters Grün, Map Blau, Social Koralle, Manage Braun, Profile Violett,
Bag Orange, Daily Türkis.)

**Baukategorien (5):** Production (Wald), Habitats (Gras), Civic (Gebäude mit Säulen),
Military (Schild), Special (Knoten).

**Umbaumodus / Karte:** verschieben, Strasse hinzufügen, Strasse entfernen,
Gebäude zurücknehmen, löschen, bestätigen ✓, abbrechen ✗, Pause, Play.

**Allgemein (meistgenutzt):** schliessen ✕ (17×), Zurück, Pfeile auf/ab/rechts,
Plus, Minus, Suchen, Filter, Sortieren, Info (i), Schloss, Häkchen, Stern, Glocke
(aktiv/inaktiv), Hilfe, Uhr/Sanduhr, Blitz (Energie), Schritte (Laufender), Kompass,
Rucksack, Ei, Herz, Person/Gruppe, Chat, Abmelden, Bearbeiten, Reset, Wifi-aus, Cloud-aus.

Die vollständige Zählung der verwendeten Material-Icons hat über 120 verschiedene Symbole.
Die häufigsten sind `pets` (20×), `close` (17×), `swap_vert` (9×), `add` (9×),
`filter_alt_outlined` (8×), `arrow_upward` (8×), `arrow_downward` (7×).

## I. Gebäude (82)

Nur **24 haben ein eigenes Bild**. Für die restlichen 58 kommt ein hochgeladenes Bild
aus dem Dev-Modus, oder es fehlt.

**Vorhanden (bundled):** castle, building_plot, small_wood_camp, large_wood_camp,
small_quarry, large_stone_camp, small_house, large_house, fish_shop, church, marketplace,
builder_camp, healing_hut, trading_post, breeding_hut, hatchery, scout_post, caravanserai,
storehouse, gold_vault, refinery_e2, butcher_shop, thinker_circle, training_grounds.

**Ohne Bild (Auswahl nach Art), pro Epoche 2–8:**
- Rohstofflager: `clay_camp_e2`, `clay_works_e2`, `lime_camp_e3`, `lime_works_e3`, `ore_camp_e4`,
  `ore_works_e4`, `coal_camp_e5`, `coal_works_e5`, `sand_camp_e6`, `sand_works_e6`,
  `crystal_camp_e7`, `crystal_works_e7`, `aether_camp_e8`, `aether_works_e8`
- Veredler: `refinery_e3` bis `refinery_e8`
- Wohnhäuser: `pen_a_e2`…`pen_a_e8` (klein) und `pen_b_e2`…`pen_b_e8` (gross)
- Luxus: `lux_wine`, `lux_spices`, `lux_salt`, `lux_coffee`, `lux_tea`, `lux_perfume`
- Spezial: `special_materials_e2`…`e8` (Kirchen), `special_treasury_e2`…`e8` (Marktplätze)
- Einzelne: `combat_school`, `warehouse`, `smokehouse`, `road`

**Wichtig für die Bildgrösse:** Türen, Fenster und Lampen sollen überall gleich gross
sein (deine Liste). Ich kann das per Code nicht sicherstellen, weil die Bilder nur
als Ganzes skaliert werden. Bei neuen Bildern also **alle im selben Massstab** rendern
(z. B. ein Kachelfeld = fixe Pixelbreite, und eine Tür ist immer gleich viele Pixel hoch).

## J. Sonstiges Bildmaterial (kein Icon, aber Bild)

- Monsterbilder (vorn/hinten pro Stufe, kommen aus dem Dev-Modus)
- Gebiets-/Regionsbilder (Overworld)
- Gelände-Requisiten (Bäume, Steine), Strassen-Kacheln (je nach Verbindung eine andere)
- App-Icon (Android `ic_launcher`, Web `icons/Icon-192/512` + maskable)
- Logo/Titel „Bøddy Game“ (Login, Ladebildschirm)

---

## Vorschlag zur Priorität

1. **Ressourcen (A)** und **Typen (B)**: überall sichtbar, heute am meisten Emoji-Look.
2. **Status (C)** und **Heilmittel (D2)**: mehrere Platzhalter sind sachlich falsch.
3. **Kraft-/Wert-Symbole (G)**: fehlen komplett.
4. **Rollen (F)** und **Ereignisse (E)**.
5. Menüknöpfe (H) zuletzt, die Material-Icons wirken neutral.
