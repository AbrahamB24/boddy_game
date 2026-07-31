# Balancing-Referenz

Single Source of Truth für alle Zielwerte. Werkzeuge (Balance-Simulator,
Kampf-Monte-Carlo, Stat-Budget-Validator) prüfen die Ist-Werte **gegen dieses
Dokument** — geändert wird zuerst hier, dann im Code.

Stand: 2026-07-16 · Anker vom User festgelegt.

## 1. Anker (Spielgefühl, entschieden)

| Anker | Ziel |
|---|---|
| Era-I-Abschluss (aktiver Spieler, täglich) | **~5–7 Tage** |
| Ressourcen-Split passiv (Gebäude) / aktiv (Expeditionen) | **≈40 % / 60 %** |
| Normaler Kampf (3er-Team vs. gleichstarkes Wild) | **~4–6 Aktionen**, ~10–25 % Team-HP-Verlust |
| Fang-Tempo (Commons, aktiver Tag) | **~5–8 / Tag** |

Annahmen: „aktiver Spieler" = ~20–30 min aktives Spielen + mehrfaches
Einchecken; Energie-Uptime ≈ 100 % (≥ 10 000 Schritte/Tag, s. kDrainPerHour).

## 2. Abgeleitete Tagesziele (Era I)

**BP: GELÖSCHT.** Forschungspunkte, der Tech-Tree und die BP-Kosten der
Evolution existieren nicht mehr (`kFallbackTechDefs`, `kEvolutionBaseCostBp`,
`kBpPerResearchPowerHour` sind alle weg): Technologien sind **Orte auf der Karte**
— hinreisen, Prüfung gewinnen, freigeschaltet — und Evolution kostet nur noch
Level. Das ganze BP-Tagesziel, das hier stand, ist damit gegenstandslos; es blieb
als Rechnung stehen, die niemand mehr nachrechnen kann.

**Holz/Stein.** Gesamtausgaben Era I (Gebäude + Era-Aufstieg 1000/800) ≈
~5 000 Holz / ~4 000 Stein → **~850 Holz/Tag, ~700 Stein/Tag**, davon:
- passiv: ~340 Holz/Tag (**≈14/h**), ~280 Stein/Tag (**≈12/h**)
- aktiv: ~510 Holz/Tag ≈ **2–3 Gather-Trips à ~150–250**

**Fänge.** 5–8 Commons/Tag = ~2 Jagden à 3 Funde (je ~72 min + Reise) bei
~85–90 % QTE-Erfolg für Commons. Konsequenz: Basis-Slots (2) sind knapp → Slots
kommen heute vom **Scout Post** (`expeditionSlots`-Effekt, Ära I), nicht aus
einem Tech-Baum. **Folge-Baustelle:**
Release-/Verwertungs-Mechanik (5–8/Tag füllt Housing schnell).

**Kampf-Umrechnung.** „4–6 Aktionen": gleichstarkes Wild stirbt nach ~4–6
Treffern des Teams → Wild-EHP ≈ 5 × Ø-Teamschaden pro Aktion. Bosse (+20 %
Stats) ≈ 8–10 Aktionen. Messgröße im Monte-Carlo: Median-Aktionen bis Sieg,
Siegquote (Ziel ≥ 95 % bei gleichem Level, ~50 % bei Level +8 = nächste Stage).

## 3. Stat-Budget-Framework

**Skala-Anker (TIER 1, User 2026-07-17):** Gesamt-Base-Budget und Growth sind
FESTE Pro-Rarität-Werte (`kBaseBudgetByRarity`), Growth = Base ÷ 30:

| Rarität | Base | Growth (= Base ÷ 30) |
|---|---|---|
| Common | 270 | 9,00 |
| Uncommon | 280 | 9,33 |
| Rare | 290 | 9,67 |
| Epic | 300 | 10,00 |
| Legendary | 310 | 10,33 |

> **Spread KOMPRIMIERT (User 2026-07-17)** von 270→390 auf **270→310 (+10/Stufe)** —
> „seltene nur ein bisschen besser, fast alle Monster nützlich". Legendary = nur
> 1,15× Common ≈ ~1,5× Kampfkraft, also schlägt ein Level-Vorsprung den
> Rarität-Bonus (früher 1,44× → Lv30-Common gewann nur 1% vs Lv10-Legendary;
> jetzt 100% bei +10 Levels, Sim-geprüft). Zusätzlich **Combat-Floor 45–60%** im
> `rollBudget` (war 35–80%) → kein reines Kampf-Nietenmonster mehr.

Der Default-**Split** ist combat:work = **180:190** (`kDefaultCombatShare` ≈ 0,486)
— d. h. ein Common verteilt ~131 Base auf die 4 Kampf-Stats (HP/ATK/DEF/SPD) und
~139 auf die 10 Nicht-Kampf-Stats (8 Work-Roles + carry + catchRate). Nur der
Split ist frei, die Summe pro Rarität fix.

> **Änderungen 2026-07-17:** (1) `energy` als Stat **entfernt** (Kampf läuft über
> Aktionspunkte, §4a), `catchRate` ist **Nicht-Kampf-Utility** wie `carry`
> (`isWorkRole` false, wählbar als Work-Priorität). (2) Base/Growth sind jetzt
> **feste Pro-Rarität-Totals** (oben) statt `370 × budgetMultiplier`. Die alte
> `budgetMultiplier`/`kRarityBudgetBonus`/`kTierBudgetBonus`-Formel ist WEG.
> Der **Region-Tier-Soft-Gate (+20 %/Tier) entfällt vorerst** — die Werte sind
> die Tier-1-Spezifikation; Tier 2 wird später definiert (aktuell nutzt jeder
> Tier die Tier-1-Werte). ⚠️ Common-Base fiel 370→270 → Kampf-Stats ~27 %
> kleiner; **Combat-Kalibrierung (§4a) via ⚗️ Combat Lab neu prüfen.**

**Kampf-Archetypen** (`CombatArchetype`, je Summe 180 — vier isolierte +
Mischformen, User 2026-07-17):

| Archetyp | HP | ATK | DEF | SPD |
|---|---|---|---|---|
| Allrounder | 60 | 40 | 40 | 40 |
| Bulwark (HP) | 90 | 30 | 40 | 20 |
| Berserker (ATK) | 40 | 90 | 25 | 25 |
| Guardian (DEF) | 45 | 25 | 90 | 20 |
| Sprinter (SPD) | 40 | 30 | 20 | 90 |
| Tank (HP+DEF) | 75 | 25 | 60 | 20 |
| Bruiser (HP+ATK) | 65 | 65 | 30 | 20 |
| Glaskanone (ATK+SPD) | 35 | 70 | 20 | 55 |
| Skirmisher (schneller Angreifer) | 45 | 55 | 25 | 55 |
| Duelist (DEF+SPD) | 45 | 30 | 60 | 45 |

**Zivile Archetypen** (10, `CivilArchetype`): Generalist, Träger, Sammler,
Produzent, Handwerker, Baumeister, Züchter, Mediziner, Händler, Quartiermeister.
Der Fokus-Stat bekommt `kCivilFocusShare` = **40 %** des 190er-Budgets, der Rest
verteilt sich gleichmässig. `quartermaster` ist mit dem Stat `logistics` am
2026-07-26 verschwunden und am **2026-07-30 zurückgekommen** — diesmal mit einem
eigenen Gebäude (Lager), s. §Lager. Der Editor nutzt heute aber v. a. **Work-Prioritäten**
(bis zu 3 Stats), nicht die Zivil-Archetypen. catchRate wird so als Priorität
gewählt (der „Fänger" ist eine Work-Priorität, kein Kampf-Archetyp mehr).

**Alles lebt in `creatures/services/stat_budget.dart`** — Audit
(`auditStatBudget`) und Bauer (`buildArchetypeCurves`) lesen dieselben
Pro-Rarität-Totals (`budgetBaseTotal`/`budgetGrowthTotal`), können also nicht
auseinanderdriften. Der Spezies-Editor wendet Archetypen per Knopf an; ein Test
prüft alle Kombinationen auf exaktes Budget. **Archetypen verteilen nur um —
niemand wird stärker.** Nur die Rarität ändert die Summe (Tier-2-Skalierung TBD).

**Seltenheit als Power-Achse** (User 2026-07-17): Base 270→390 (Legendary ≈
1,44× Common), Ratio wie die alte +0/8/18/30/45 %-Kurve, aber jetzt absolute
Fixwerte statt Multiplikator. ⚠️ Base skaliert Power ~**kubisch** (§4c): Legendary
× 1,2 Boss-Elite ≈ 1,73 — knapp unter der ~1,8-Grenze, ab der der Region-Boss
unschaffbar wird. Ein Test wacht darüber.

## 4. Stellschrauben-Inventar (die Dials)

| Dial | Datei | Ist | Status |
|---|---|---|---|
| WorkshopRole.mult (Ressourcen) | building_definitions | 0.3–0.7 | gegen 14 Holz/h-Ziel prüfen |
| WorkshopRole.mult (research/crafting) | building_definitions | 30–40 | Skala dokumentieren |
| kBuildPointsForHalfTime | building_definitions | 100 | **Bauzeit-Kurve (2026-07-26 umgebaut).** Bau-Punkte sind keine Sekunden-Währung mehr, sondern kaufen **% Kürzung** auf die angeschriebene Bauzeit: `cut = P / (P + 100)`. 0 Punkte = −0 %, d. h. die eingetragene Zeit ist die echte Zeit und eine unbesetzte Baustelle steht **nicht** mehr still. 100 P = −50 %, 400 P = −80 %, 900 P = −90 % — abflachend, aber **ohne Deckel** (gleiche Begründung wie beim Breeding-Cap: sonst wird Aufstufen ab einem Punkt wertlos). `kBuildSecondsPerPoint` / `kHallBuildPointsPerLevel` und der 20-Punkte-Eichwert sind ersatzlos weg. |
| Bau-Punkte (Arbeiter + passiv) | building_definitions / settlement_controller | Builder Camp mult 1.0 | Jeder Punkt zählt 1:1, egal woher. Arbeiter: Stat × mult × Stufenfaktor — das mult ist der Dial „Bau-Punkte pro Statpunkt" (10 = 1 Statpunkt → 10 Punkte). Passiv: ein `production`-Effekt mit Schlüssel `construction` landet roh als Punkte im selben Topf. Gegen die Kurve oben prüfen: mit mult 1.0 ist EIN Bauarbeiter mit Stat 70 schon −41 %. |
| kGatherRefStat / kTravelSecondsPerDanger | gather_math | 25 / 300 | gegen Trip-Ziele prüfen |
| kTradeBaseHours / kTradeSpeedForHalfTime | trade_caravan | 2 h / 100 | **Handel ist eine Expedition (2026-07-26).** Ein Handel wird nicht mehr über die Theke abgewickelt: er lädt eine Karawane. `speed` (Σ der mitgeschickten Monster) kürzt die Reise über dieselbe abflachende Kurve wie Bauzeit/Breeding — `cut = S/(S+100)`, 0 Speed = volle 2 h, 100 = 1 h, 400 = 24 min, kein Deckel. `carry` deckelt die Ladung über die **bestehenden** `unitsPerCarry`-Dials, ein Tausch ist durch **beide** Beine begrenzt (hin **und** zurück). Preise bleiben Sache des Trade Centers (`tradeDiscount` = Gebäudestufe + stationierte `trade`-Arbeiter) — die Karawane ändert **wann** und **wieviel**, nie den Kurs. Scout Post (travelMult) und Warehouse (carryMult) wirken mit. Der Item-Shop bleibt bewusst sofort. |
| Trip-Verstärker-Posten | building_definitions | mult 0.002–0.003 | Jeder Posten liest den Wert, den er verstärkt: Scout Post → `speed`, Warehouse → `carry`, Smokehouse → `gathering` — **nicht** `logistics` (der Stat war 2026-07-26 genau deswegen gelöscht). DB-Zeilen mit `stat:"logistics"` werden in `WorkshopRole.fromJson` **nach Posten** aufgelöst, nicht per flachem Rename; seit 2026-07-30 gilt das nur noch für diese drei Trip-Keys, sonst meint der Name wieder den echten Stat. |
| Lager-Posten (`logistics`) | building_effects | Storehouse 10 je Ware, Gold Vault 40, je +25 %/Stufe | **Lager beherbergen Monster (2026-07-30, User).** Jeder Punkt `logistics` eines stationierten Monsters wird zu Lagerraum, **pro Ressource einzeln einstellbar** (`WorkshopRole.mults`, nach Ressourcen-Id; `mult` ist nur noch der Fallback für Waren ohne eigenen Dial). Die Dials kommen aus den `storage`-Effekten DESSELBEN Gebäudes — was das Lager nicht hält, bekommt keinen Raum. Deshalb 40 im Vault: der hält nur Gold, der Storehouse gibt allen vier Waren ihren eigenen Betrag. Raum ist **gebäudelokal** (`storageRoomPosted(b, resource)`), landet also NICHT in `workshopPower` — sonst würde ein Vault-Arbeiter den Storehouse verbreitern. Der Stat wächst standardmässig nur 10 + 1/Level: ohne Budget-Neuverteilung in Species-Budget sitzt jede Spezies auf dem Default. |
| Spot-Yields/Capacity/Regen | area.dart (+ area_defs DB) | s. Fallbacks | gegen 150–250/Trip prüfen |
| kCaptureHuntOptions / kCaptureBaseSeconds | capture_math | 1/1.8/2.4 · 1800 s | passt zu 5–8/Tag |
| Scout Post: `huntOptions` / `expeditionSlots` | building_definitions | 1 +{2,3,5,7} / 1 +{4,8} | **Ersetzt die gelöschten Feature-Unlocks (2026-07-26).** Das ganze `unlockedFeatures`-System ist weg — Jagdlängen und Expeditions-Slots kommen jetzt aus dem **Scout Post** (dafür von Ära II auf **Ära I** gezogen), Zucht aus der Zuchthütte, Evolution allein aus dem **Level**. Beide Effekte sind ZÄHLER mit `levelSteps`, nicht die +50 %/Stufe-Ertragskurve. Stufe 1 → 2. Jagd + 1 Slot; alle sechs Jagdlängen ab Stufe 7, 3 Extra-Slots ab Stufe 8. `maxCount: 2` → zwei Posten stapeln. |
| QTE (BaseSeconds/Window/Slow/Hits) | capture_math | s. Konstanten | Erfolgsquote Commons ~85–90 % |
| catchHpThreshold | capture_math | 0.70…0.12 | ok, im Playtest prüfen |
| kThreatPerDanger (Risiko) | expedition_risk | 60 | Verlustquote < 10 % bei passender Truppe |
| wildLevelForStage / Boss +20 % | dungeon.dart / combatant | 5+8·(s−1) | via Monte-Carlo |
| CombatEngine.damageScale | combat_engine / CombatTuning | 0.55 | ✅ kalibriert (5 Akt. @ 3v1 gleich, level-stabil); jetzt Live-Dial im Dev-Tool ⚗️ Lab |
| CombatTuning.defenseWeight | combat_tuning | 1.0 | atk/(atk+def·w): >1 Def zählt mehr, <1 Angriff dominiert; Live-Dial ⚗️ Lab |
| kMaxHitHpFraction (Oneshot-Sperre) | combat_engine | 0.5 | HARTE Garantie (kein Dial): ein Treffer nie >50% max-HP → Oneshot aus Vollleben unmöglich. Normale Treffer ~20%, greift nur bei STAB×Typ×Crit-Stacks (User 2026-07-17) |
| ⚔️ KAMPFMODELL: Feld + Bank | combat_engine | `fieldSlots` = 3 | **Seit 2026-07-27 kämpfen bis zu 3 Monster pro Seite GLEICHZEITIG** (User: "wie in einem jrpg … sie tauchen in der Rundenleiste auf"), der Rest wartet auf der Bank und rückt bei K.O. nach (Gegner auto, Spieler per Picker). Ersetzt das 1v1-Reservemodell von 2026-07-17, in dem eine Vierergruppe vier aufeinanderfolgende Duelle war. Freiwilliger Switch kostet keine RUNDE, nur AP. ⚠️ Die alten symmetrischen 3v3-Anker sind gelöscht — via ⚗️ Combat Lab neu einstellen |
| Fähigkeits-EFFEKTE (Dauer + Wert) | ability_defs-Zeile (Dev: Fähigkeit → Effects) | 0 = Katalog-Default | **Pro Fähigkeit einstellbar seit 2026-07-30 (User).** Die Zahlen lagen als globale Konstanten in `status_effects.dart` — jeder Burn im Spiel war derselbe Burn. Jetzt trägt jeder Effekt seine eigene **Dauer** und seinen eigenen **Wert**; `0` heisst weiterhin Katalogwert, darum hat sich an keiner bestehenden Fähigkeit etwas geändert. Der Wert ist immer ein **positiver Bruchteil** („wieviel"): Schaden/Zug bei Burn+Poison, verlorene Speed bei Frost, Zugausfall-Chance bei Fear, verlorene Treffsicherheit bei Blind, gewonnener Stat beim Buff. Ein Effekt pro Familie (Status/Debuff/Buff/Heal/Lifesteal/Selbstkosten) — mehr könnte die Engine nicht anwenden. **Nicht** authorbar bleiben: Burns −20 % ATK, Frosts 10 % Zugausfall, Poisons +2 pp/Zug-Steigerung; die Form sagt sie aber explizit an |
| Power → AP Umrechnung | Dials (Monster → AP · Kosten) | Power pro AP 13, Boden 2, Buff-Boden 2, Prio 15 | **Alles Dials seit 2026-07-30** (vorher: `13` und `15` als Literale in der Formel, also genau die Zahlen, die jeden Preis bestimmen, unerreichbar für Dev Mode). Kosten = (totalPower + Prio × PrioPower) ÷ PowerProAP, geklammert auf [Boden, AP-Vorrat der Endform]. Der **Buff-Dial ist ein BODEN**, kein Festpreis mehr — sonst war er für jeden Buff mit Effekt wirkungslos. ⚠️ Über `kMaxPricedPower` (= 8 AP × 13 = **104 Power**) ist der Preis am Anschlag und jede weitere Stärke gratis; `AbilityDef.isOverPricedOut` meldet das, und die Form sagt um wieviel. Gleiches gilt für die Stufen-Kappung: ein zu starker Move als **Startfähigkeit** kostet nur 4 AP — die Form warnt jetzt auch hier |
| Effekt-POWER (→ AP) | ability_effects.dart `powerCoefficient` | 200 / 40 / 70 | **Jeder Effekt hat einen Powerwert (User 2026-07-30: „damit es vergleichbar wird mit den AP").** Power = Wert × Dauer × Chance × Koeffizient, negativ bei Selbstkosten. Drei Koeffizienten: **200** = bewegte HP (Anteil einer Lebensleiste), **40** = ein gebogener Zug (Speed/Treffer/ATK/DEF/Zugausfall), **70** = ein Anteil DIESES Treffers (Lifesteal/Rückstoss). Anker: Power 40 = Standardangriff = 3 AP. Ersetzt die alten Pauschalen (+8 Status, +8 Debuff, +20 Lifesteal) **und den 4-AP-Deckel für Statusmoves** — der machte längere/stärkere Effekte gratis. Ein Standard-Status bei 30 % Chance ≈ 9 Power, also fast wie früher; ein 9-Züge-Burn mit 25 %/Zug kostet jetzt 8 AP. `AbilityDef.totalPower` ist die Summe, die Dev-Form zeigt sie pro Effekt und als Rechnung |
| Neue Effekte (Pokémon-Anleihen) | ability_effects.dart, Migration 0032 | — | **2026-07-30, noch von keinem Monster benutzt:** `sleep` (Hauptstatus, 85 % Zugausfall, 2 Züge — der schwerste Zugfresser, darum kurz), `attackDown`/`defenseDown` (Sekundär-Debuffs à la Growl/Screech — vorher konnte man nur Zugzahl senken, nie Härte), `regen` (HP/Zug auf dem Anwender, tickt im gleichen Upkeep wie ein DoT), `recoil` (Rückstoss, kann den Anwender selbst K.O. schlagen). Alle mit Power/AP-Preis wie oben |
| ⚡ AP AKTIONSPUNKTE (statt Energie) | creature_enums + Dials (Monster → AP) | Vorrat 4/6/8, Regen 3/4/5 | **Vorrat pro EVOLUTIONSSTUFE, Rest bleibt liegen** (User 2026-07-20; nicht level-abhängig): zu Beginn jedes eigenen Zuges kommen die Regen-AP dazu, gedeckelt auf den Vorrat — kein Vollauffüllen, alles darüber verfällt. Start: wer zuerst dran ist 2 AP, alle anderen 3. Angriff 3 AP, Switch 2 AP (zahlt das ABGEHENDE Monster, das eintretende regeneriert nicht), Buff 2 AP, sonstige Fähigkeit 2–8 AP aus `AbilityDef.resolvedApCost`. Ein Zug endet erst, wenn die günstigste Aktion nicht mehr bezahlbar ist — oder per «End Turn», was den Rest anspart. Das `energyCost`-Feld ist gelöscht, Fähigkeiten kosten nur AP |
| catchRate (Fang) | capture_math | — | NUR noch Fenster-Breite (kQteMaxWidthBonus +120%, kQteWindowCatchK 100), NICHT Ring-Tempo. Zählt das AKTIVE Monster beim Fang, nicht die Gruppe → Catcher einwechseln (User 2026-07-17) |
| kWildStatMult (nicht-Boss-Wilde) | combatant.dart | 0.85 | Nur Battle-Stats; gefangene behalten volle Gene. 3v1-Fangkampf gleiches Lv ≈ 100 % / ~17 % HP (nach Budget-Umstellung 2026-07-17) |
| kCaptureWildStatMult (nur Fang-Kämpfe) | capture_math | 0.75 | ×0.85 Wild-Malus ≈ 0.64 gesamt. Fangen ist QTE-Skill-Check, der Kampf davor nur der Hebel (User-Report 2026-07-17: Oneshots durch STAB×Typ×Crit-Stack bis 4,5×). Achtung: Stack kann Oneshots bei Off-Budget-Spezies weiterhin erlauben — Budgets via Dev Mode ⚖️ fixen |
| xpToNextLevel (Faktor·L^Exponent) | xp_balance (Dev: ⚖️ → XP) | 6 · L^2.5 | Level-Tempo an Stage-Tempo koppeln. Seit 2026-07-26 dev-authorbar statt konstant — der Reiter zeigt zu jeder Kurve die XP UND die Stunden pro Level |
| Kill-XP (Faktor·Stufe^Exponent) | xp_balance (Dev: ⚖️ → XP) | 9 · L^2.3, Boss ×6 | Was ein besiegtes Monster NACH SEINER STUFE zahlt, summiert über das Gegnerteam und auf die eigene Gruppe aufgeteilt. Seit 2026-07-26 authorbar — DIE Schraube fürs Level-Tempo, weil Kämpfen der Hauptweg ist. Der Reiter zeigt dazu „Siege bis zum Level-Up" |
| kTrainingXpPerHour (Training Grounds) | xp_balance (Dev: ⚖️ → XP) | 250 | Die HÖHERE der zwei automatischen Raten; Trainee produziert NICHTS (Opportunitätskosten). ~1,3 h/Level @ Lv5, ~7,6 h @ Lv10, ~1,8 d @ Lv20, ~5 d @ Lv30 — Kämpfen bleibt der schnellste Weg (40→100→250 am 2026-07-17) |
| workPerHour / workLevelGrowth (Arbeit) | xp_balance (Dev: ⚖️ → XP) | 10 XP/h, ×1,05 pro Gebäudestufe | EIN Wert für JEDES Gebäude mit Monster-Slots (User 2026-07-30: „Jedes Gebäude, welches Monster anstellt soll EP geben. Jedes Gebäude gibt genau gleich viel EP"). Wachstum bewusst schwach („nicht sehr stark"): ×1,6 auf Stufe 10, ×2,9 auf Stufe 24 — primäre EP-Quelle bleibt Kampf/Training. Ersetzt den per-Gebäude-`xp`-Effekt, der auf 11 Ära-I-Gebäuden lag und auf ~40 späteren mit Arbeitsplätzen NICHT |
| ~~per-Gebäude `xp`-Effekt~~ | — | GELÖSCHT 2026-07-30 | War pro Gebäude einstellbar und darum pro Gebäude anders — Lehmgruben, Raffinerien und Spezialgebäude ab Ära II zahlten gar nichts. Regel jetzt in `CreaturesController.xpRatePerHour`, Zahl in `XpConfig.workPerHour`; DB-Zeilen mit `xp` werden beim Laden verworfen |
| ~~kPassiveXpPerHour~~ / ~~eraXpMultiplier~~ | — | GELÖSCHT 2026-07-26 | Der pauschale Arbeits-Floor und der Ära-Aufholfaktor sind weg (User: „das braucht es nicht"). Seit 2026-07-30 zahlt jeder Arbeitsplatz wieder etwas — aber als EINE settlement-weite Rate, nicht als Floor pro Gebäude; eine spätere Ära zahlt mehr, weil ihre Monster höherstufig sind, nicht wegen eines Multiplikators |
| breedHours / hatchHours (pro Seltenheit) | species_balance (Dev: ⚖️ → Breeding) | 4/6/8/16 h | ZWEI getrennte Uhren seit 2026-07-26 (Paarung im Breeding Hut, Ausbrüten in der Hatchery), gleich vorbelegt. Der Reiter rechnet Wunschdauer → nötige Power |
| kBreedingK (Halbwertspunkt) | creature_enums | 60 | Arbeiter-Beschleunigung: Power = Σ(breeding-Stat × Rollen-mult × Stufenfaktor); Ersparnis = P/(P+60). KEIN Deckel mehr (2026-07-26, vorher −50 %) — nur abflachend: Power 60 = −50 %, 240 = −80 %, 540 = −90 %; Dauer geht gegen 0, wird aber nie 0. Der Deckel machte Gebäudestufen ab dem zweiten Brüter wertlos |
| Gebäude-/Era-Kosten, researchSeconds (=bpCost×72) | building/tech/era defs | — | gegen 5–7-Tage-Anker |
| buildingYieldFactor (Gebäude-Level) | building_definitions | 1+0.5·(L−1) | Ertrag/Boni pro Level: L5 = ×3. Skaliert workshopPower, Housing, buildSpeed/queue-Boni |
| buildingCostFactor / buildingTimeFactor | building_definitions | 1.6^(L−1) | Upgrade-Kosten & -Zeit: L5 = ×6.55. Kosten wachsen schneller als Ertrag → Upgrade ist Platz/Bequemlichkeit-Trade |
| kFreeBuildingLevelCap / kMaxBuildingLevel | building_definitions | 5 / 10 | Level 1–5 ohne Forschung. kMaxBuildingLevel ist seit 2026-07-26 nur noch der DEFAULT für Defs ohne eigene `maxLevelPerEra` — eine authorierte Stufenzahl (z. B. 21) gilt wirklich, und alle per-Level-Effekte inkl. `slotSteps` skalieren mit hoch |

### Kampf-Kalibrierung (2026-07-16, per Monte-Carlo abgeschlossen)

Ursprünglicher Befund: Pokémon-Basis `((2·L/5+2)·Power·ATK/DEF)/50+2` machte
Kämpfe zu lang (Schaden zu niedrig vs. HP) und level-instabil (Level-Faktor
wuchs 7×, HP nur 2,7× → 16→7 Aktionen Drift); der reine ATK/DEF-Quotient
neutralisierte den Stat-Growth beider Seiten → Action-Economy dominierte
alles (3v1 trivial selbst bei −8; 3v3 = 80–89 % HP-Verlust bei 73–83 %).

**Fix (implementiert):**
- Neue Basis `(Power/40)·ATK·(ATK/(ATK+DEF))·damageScale + 2` — ATK trägt
  den Growth (Kampflänge level-stabil), DEF = %-Mitigation, Gaps wirken in
  beide Richtungen. Dial: `CombatEngine.damageScale = 0.55`.
- Wilde (nicht-Boss) kämpfen mit `kWildStatMult = 0.85` (combatant.dart) —
  nur Battle-Stats, gefangene behalten volle Gene. Boss bleibt ×1,2.

> **3v3-Anker GELÖSCHT (User 2026-07-17):** die alten symmetrischen
> „alle-gegen-alle"-Anker sind weg; nur der **3v1-Fangkampf** bleibt als Anker
> (Team von 3 gegen 1 Wild), und die Monte-Carlo-Probe testet nur noch
> enemyCount=1.
>
> ⚠️ Das *Modell* ist seit 2026-07-27 nicht mehr 1v1 — bis zu **3 Monster pro
> Seite** stehen gleichzeitig im Feld (s. Zeile «KAMPFMODELL» oben). Dieser
> Absatz behauptete beides gleichzeitig.

**Kalibrierter Ist-Stand (= neue Anker, gemessen — nach Budget-Umstellung
2026-07-17 neu geprüft):**

| Matchup | Ergebnis |
|---|---|
| 3v1 gleiches Lv (Fangkampf) | ~100 %, **~4 Aktionen**, ~17 % HP — im Anker-Bereich |
| 3v1, Team −8 | ~94 %, ~5 Akt., ~26 % HP |

Bewusste Abweichungen von den ursprünglich abgeleiteten Ankern: 3v1-Verlust
liegt UNTER 10–25 % (ok — Multi-Fund-Jagden ketten Kämpfe), und −8 heißt
nicht ~50 % Siege, sondern hohe Kosten (besseres Spielgefühl als Münzwurf).
Level-Sensitivität ist bei linearem 2,5 %-Growth SYSTEMISCH mild — große
Sprünge kommen designgemäß aus Evolution (Stufen-Bonus), Seltenheit und
Zucht, nicht aus Leveln allein.

### 4b. Kleine Teams & Dungeon-Länge (2026-07-16, Region-Redesign)

Der Start ist seit dem Region-Redesign **1v1** (Team-Größe ist selbst
tech-gegatet) — die Kampf-Kalibrierung (§4a) lief aber für 3er-Teams.
Nachgemessen (Team Lv5, Wilde Lv5, Boss Lv11 +20 %):

| Matchup | Sieg | HP/Kampf |
|---|---|---|
| 1 vs 1 | 100 % | **55 %** |
| 2 vs 1 | 100 % | 13 % |
| 2 vs 2 | 100 % | 42 % |
| 2 vs Boss | **24 %** | 95 % |
| 3 vs 1 | 100 % | 5 % |
| 3 vs 2 | 100 % | 18 % |
| 3 vs 3 | 100 % | 39 % |
| 3 vs Boss | 100 % | 41 % |

**Entscheidende Einsicht:** Ohne Heilung im Run summieren sich die HP-Kosten —
die Leiter-Länge ist damit *kein* freier Parameter. Zwei Blocker gefunden und
behoben:

1. **Tech-Gate war unmöglich**: `[1,1]` = 55 % + 55 % → der Starter stirbt im
   zweiten Kampf. → **`kTechDungeonPackSizes = [1]`** (ein Trial, danach heilen).
2. **Region-Dungeon war ein Deadlock**: `[1,2,2,3]`+Boss kostet selbst ein
   3er-Team 5+18+18+39+41 = **121 %** — und `team_size_3` ist Era II, also
   *hinter genau diesem Boss*. → **`kRegionDungeonPackSizes = [1,2]`** (2 Kämpfe
   + Boss), machbar für ein hochgeleveltes 2er-Team (Lv12-2er vs Boss: 100 % /
   13 % HP), unmöglich für ein frisches — korrektes Meilenstein-Gating.
3. **Kein Heil-Gebäude existierte** (nur die Konvention-ID): HP sind persistent
   ohne Regeneration → jeder Kampf drainte dauerhaft. → **Healing Hut als
   ungegateter Start-Content** (Gating hätte deadlockt: kein Heilen → Gate-Kampf
   nicht schaffbar → Heilung nie freischaltbar).

### 4c. Budget skaliert ~kubisch — die wichtigste Balancing-Regel

**Ein Budget-Multiplikator ist KEIN linearer Machtregler.** Er hebt HP, Angriff,
Verteidigung *und* Tempo gleichzeitig — vier multiplikative Vorteile (länger
überleben, härter treffen, weniger einstecken, öfter handeln). Gemessen
(2 Monster Lv10 gegen 1 Gegner Lv10):

| Gegner-Budget | Siegquote des 2er-Teams |
|---|---|
| ×1.00 | 100 % |
| ×1.20 | 98 % |
| **×1.40** | **15 %** |
| ×1.70 | 0 % |

**Ein Gegner mit +40 % Budget schlägt zwei gleichstufige Monster.** Jede
scheinbar kleine Prozentzahl hier ist also ein massiver Eingriff.

**Seltenheits-Kurve (User-Entscheid 2026-07-16):** „je seltener, desto mehr
Punkte" → **+0/8/18/30/45 %**. Legendary ×1.45 ≈ „zwei gewöhnliche Monster
wert". Ein erster Versuch mit +70 % machte den Region-Boss (ein Legendary,
plus ×1.2 Elite) **unschaffbar — 0 % selbst für ein Lv20-Team**.

**Boss-Machbarkeit mit den finalen Werten** (Boss = 1.45 × 1.2 = **1.74**;
Elite-Bonus bleibt, User-Entscheid):

| 3er-Team | Lv11 | Lv14 | Lv17 | **Lv20** | Lv24 |
|---|---|---|---|---|---|
| Siegquote | 3 % | 12 % | 54 % | **99 %** | 100 % |

Der Region-Boss verlangt also ein **gelevelltes 3er-Team (~Lv20)** — korrekt
für ein Ära-Gate. In der Praxis leichter, da die Simulation **Evolution nicht
abbildet** (Evolution I liegt in Era I und ist ein echter Power-Sprung).

**Daraus folgt zwingend:** `team_size_3` musste von Era II nach **Era I**
wandern — ein 2er-Team schlägt den Boss bei *keinem* Level, und Era II liegt
hinter genau diesem Boss (sonst: Deadlock).

## 5. Werkzeuge & Vorgehen

1. ✅ **Expeditions-Ökonomie** (Dev → Balance → Expeditions): Ertrag/Tag pro
   Spot (Burst vs. nachhaltig), Trips/Tag, Fang-Durchsatz — gegen die
   Tagesziele. (`expedition_economy.dart`)
2. ✅ **Kampf-Monte-Carlo** (Dev → Balance → Combat): headless CombatEngine,
   Siegquote/Median-Aktionen/HP-Verlust pro Stage. Hat die Schadensformel-
   Kalibrierung getrieben (§4a). (`combat_monte_carlo.dart`)
3. ✅ **Stat-Budget-Validator** (Species-Editor): Live-Audit der Kurven gegen
   die §3-Budgets (rarity-skaliert, ±10 % Toleranz, Rahmen grün/rot);
   neue Spezies starten exakt auf Budget (Allrounder-Defaults).
   (`stat_budget.dart`)
4. Laufendes Vorgehen: Dial ändern → Tool misst → Playtest → hier nachführen.

## 6. Intro & Jumpstart (erste Spielstunde)

**Die Regel: der Jumpstart ist ein befristeter Multiplikator, NIE ein neuer
Basiswert.** Die Anker in §1 (Era I in 5–7 Tagen, 5–8 Fänge/Tag) sind **Raten**.
Ein einmaliger Zeitgewinn verschiebt die Kurve um eine Konstante — ~4–6 h auf
120–168 h ≈ 3 %, das liegt innerhalb der Breite des Ankers selbst. Würde man
stattdessen `kCaptureBaseSeconds` o. ä. dauerhaft senken, **kippt die Kurve**
und beide Anker sind hinfällig. Deshalb: `timeScale`/`statScale` sind
**Parameter mit Default 1.0** an den reinen Funktionen (`planGather`,
`captureDuration`, `Combatant.fromSpecies`, `buildTechDungeon`), und der
Aufrufer reicht den Boost rein. Ein Test bewacht, dass der Default-Pfad
unskaliert bleibt.

**Fenster: fortschrittsbasiert** (User-Entscheid 2026-07-16), nicht Wall-Clock
— wer nach 10 Minuten schliesst, verliert den Boost nicht. Aktiv = solange die
Intro-Kette läuft (`IntroStep.isActive`, persistiert auf `profiles.intro_step`,
Migration 0005).

Die Kette (`lib/features/onboarding/intro_flow.dart`) ist der **echte kritische
Pfad**, keine Führung nebenher: Starter wählen → sammeln → fangen → **eines in
ein Gebäude setzen** → erste **bewachte** Technologie.

**Die Reihenfolge ist von beiden Seiten festgenagelt, nicht Geschmack:**
- „Einsetzen" muss **nach** dem ersten Fang kommen: `availableForExpedition()`
  schliesst zugewiesene Kreaturen aus — mit *einem* Monster schliessen sich
  „einsetzen" und „losschicken" gegenseitig aus. Erst zu zweit ist die Wahl
  bezahlbar. (`battleTeam()` schliesst Zugewiesene **nicht** aus — ein
  stationiertes Monster kämpft weiter, nur Expeditionen sperren es.)
- „Einsetzen" muss **vor** die erste Technologie: `researchRatePerHour` ist die
  Summe der zugewiesenen **Research**-Arbeiter — ohne einen laufen die
  `researchSeconds` nie, und die Forschung wird nie fertig. Die geschenkten BP
  zahlen die **Kosten**, nicht die **Zeit**.

Der letzte Schritt zählt
bewusst nur bei `techIsGated` (bpCost > 0): `tribal_knowledge` ist gratis und
sofort fertig, daran zu enden hiesse, das Intro ohne je einen Mini-Dungeon zu
bestehen.

**Warum das Intro überhaupt existiert:** ein frischer Account hat **0
Kreaturen**, und Kreaturen SIND die Arbeitskraft (`workshopPower()` summiert
zugewiesene Kreaturen). Ohne Starter ist die Holz-, Forschungs- und Baurate
exakt **0** — das Spiel wirkt kaputt, und der Starter-Picker lag hinter einem
unbeschrifteten 🐾-Button.

| Boost | Wert | Wirkung in Stunde 1 |
|---|---|---|
| `kJumpstartTimeScale` | 0.2 | Erster Hunt 35 min → **~7 min**; `expansion` 28.8 min → **~5.8 min**; Bau ×5 |
| `kJumpstartEnemyStatMult` | 0.6 | Fang-Kampf + Tech-Prüfung (solo, sonst ~55 % HP-Kosten) |
| `kJumpstartGiftBp` | 60 | `expansion` kostet 24 BP bei **0 BP Einkommen** → Baum wäre sonst zu |
| `kJumpstartGiftFish/Fur` | 20 / 20 | Regions-Dungeon-Eintritt; Gebäude liefern bewusst kaum (mult 0.12) |
| `kJumpstartFreeTechId` | `team_size_2` | Gratis **beim ersten Fang** → der letzte Mini-Dungeon ist 2v1, nicht solo |

**Invariante:** `statScale` senkt nur **Kampfwerte**, nie die Gene — ein im
Intro gefangenes Monster ist ein vollwertiges Individuum. Der QTE wird
ebenfalls **nicht** erleichtert: der Fang bleibt Skill, nur der Kampf davor
wird milder.

**Bekannte Kante:** fortschrittsbasiert heisst, wer die Kette nie abschliesst,
behält den Boost. Abgefangen wird nur der klare Fall (`dungeonMaxStage > 1` →
Intro sofort beendet). Wer bewusst nie eine bewachte Technologie erforscht,
kann bis zum ersten Regionsboss mit ×5 Bau/Forschung spielen — bewusst
akzeptiert (Solo-Spiel), aber hier notiert, falls die Era-I-Messung je
unerklärlich zu schnell aussieht.

## 7. Forschung = Stärke, nicht Voraussetzungen

**User-Entscheid 2026-07-16:** Technologien hängen **nicht mehr voneinander
ab**. Das `prerequisites`-Feld ist gelöscht. Zwei Dinge gaten eine Technologie:

1. **Region erreicht** — die Techs einer Ära liegen in ihrer Region (Region↔Ära
   1:1), und eine unerreichte Region liegt im Nebel.
2. **Prüfung gewonnen** — jede BP-kostende Technologie hat einen Mini-Dungeon,
   dessen Level mit dem Preis steigt.

**`bpCost` ist damit ein Schwierigkeits-Regler, nicht nur ein Preis.**

**Band pro Ära:** `techTrialLevel` verteilt die Prüfungen zwischen dem
gewöhnlichen Wild-Level der Ära und dem Level ihres Bosses — Era I **Lv 5…11**,
Era II **Lv 13…19**. Nie darüber: der Regionsboss ist das Ära-Tor, keine
Prüfung darin darf ihn überholen.

**Verteilt wird nach RANG, nicht nach absolutem Preis.** Interpolation auf den
Rohkosten klingt sauberer und spielt schlechter: Era I läuft 24…500 BP, der
500er-Ausreisser (`bronze_age_preparation`) presste **sechs** Techs auf Lv 5 —
gar keine Rampe. Ein Test bewacht das. Folge: das Prüfungs-Level einer
Technologie hängt von der *Menge* der Techs ihrer Ära ab — eine neue Technologie
verteilt die Ära neu. Gewollt: die Ära bleibt gleichmässig getaktet, egal wie
viel Content dazukommt.

**Nichts verfällt.** Forschung ist an die **erreichte Region** gebunden
(`techRegionReached`), nicht an den Ära-Index. Vorher waren nur Techs der
*aktuellen* Ära erforschbar — und `advanceEraFromBoss` schiebt die Ära ohne
Warnung weiter, also vernichtete ein Bosssieg jede unerforschte Ära-I-Technologie
(Evolution, Zucht, halbes Housing) **für immer**, während der Dungeon-Screen den
Ära-Aufstieg als Belohnung bewarb. Jetzt gilt dieselbe Regel wie auf der Karte:
was du siehst, kannst du erforschen. Eine Ära ist ein Meilenstein, kein Fenster.

**Empfohlenes Team-Level = Wild-Level der Prüfung** (`techTrialRecommendedLevel`).
Begründet in §4b: ein gleichstufiges 1v1 — die Form der Prüfung
(`kTechDungeonPackSizes = [1]`) — gewinnt zu 100 %, kostet aber ~55 % HP. Also
machbar, teuer, und mit einem zweiten Monster bequem. Eine **Empfehlung**, keine
Sperre: der Spieler darf unterlevelt reingehen und zahlen.

Angezeigt wird sie zweimal: als Abzeichen am Karten-Knoten und im Tech-Sheet,
beide **gegen das eigene Teamlevel eingefärbt** (grün bereit / gelb knapp / rot
zu schwach). Ist-Stand mit dem Fallback-Content:

| Ära I | Lv | | Ära II | Lv |
|---|---|---|---|---|
| Expansion (24 BP) | 5 | | Expedition Corps (250) | 13 |
| Pack Tactics (40) | 5 | | Great Hunts (250) | 15 |
| Primitive Woodworking/Masonry (50) | 6 | | Evolution II (400) | 17 |
| Trailblazing · Long Hunts (60) | 7 | | Grand Expeditions (600) | 19 |
| Fishing · Hunting · Husbandry (100) | 8 | | | |
| Evolution I (120) · Longhouse (150) | 9 | | | |
| Construction Planning (200) · Barter (250) | 10 | | | |
| Warband (250) · Bronze Age Prep (500) | 11 | | | |

`tribal_knowledge` (0 BP) hat keine Prüfung — der bewusst sanfte erste Griff.

**Offene Spannung (vorbestehend, nicht durch diese Änderung entstanden):** die
Level-Kurve sagt Region 2 = Lv 13, aber §4c misst, dass der Boss von Region 1
ein **Lv-20**-3er-Team braucht (Budget ×1.74). Prüfungen und Boss sind also
nicht auf derselben Skala. Beim nächsten Balancing-Durchgang anschauen.

## 8. Spezialressourcen: Senken & Skalierung

**Entfernt (User 2026-07-16):** das Needs-System der Wohngebäude (Hütte frisst
1 Fisch/h für +20 % Holz, Langhaus 1 Fell/h für +20 % Stein). Damit war der
einzige regelmässige Verbraucher weg — Fisch/Felle hatten nur noch den
Dungeon-Eintritt.

**Neue Senke: HEILEN.** Der mit Abstand häufigste Vorgang — HP sind persistent
und regenerieren nie, jeder Kampf zieht ab. Es war bisher **gratis und sofort**
(ein Tap = ganze Sammlung voll), womit jede HP-Kostenrechnung im Spiel
bedeutungslos war, inklusive der 55 %/Prüfung aus §4b. Jetzt:

- **pro Monster, proportional zu fehlenden HP** (`kHealGoodsPerHp = 0.1`) —
  nur Verletzte zahlen, und zwar was sie wirklich fehlen. Ein Pauschalpreis
  hätte belohnt, Schaden zu horten und alles auf einmal zu heilen.
- **K.O. kostet doppelt** (`kHealKoMultiplier = 2.0`) — sonst kostet
  Umgefallensein genauso viel wie mit 1 HP überleben, und Rückzug wäre sinnlos.
- Kosten runden pro Good **auf**: eine Heilung darf nie durch Rundung gratis
  werden.
- Grössenordnung: ein 3er-Team à ~60 HP nach einer Prüfung (−55 %) ≈ **10
  Goods**, gegen einen Gather-Trip mit dutzenden. Routine bezahlbar, ein
  schlechter Lauf spürbar.

**Heilen kostet auch ZEIT** (User 2026-07-16). Goods allein waren zu schwach:
sie sind leicht zu sammeln, also kostete ein Wipe eine Sammelrunde statt einer
Entscheidung. Die **Wartezeit** ist, was Rückzug bei 30 % von Weiterkämpfen
unterscheidet.

- `kHealSecondsPerHp = 25`, ×`kHealKoMultiplier` bei K.O. — dieselbe Regel wie
  beim Preis.
- Ein ~60-HP-Monster nach einer Prüfung (−55 %, ~33 HP) ≈ **~14 Min**. Dasselbe
  Monster **k.o.** ≈ **~50 Min**. Genau diese Lücke ist der Grund, nicht
  umzufallen.
- **Pro Monster, parallel** — ein Kratzer wartet nicht auf einen K.O.
  (`healDurationFor` = das Schlimmste, nicht die Summe).

**Seit 2026-07-26 dev-authorbar und PRO SELTENHEIT** (Species-Budget →
🩹 Heilung): Sekunden pro HP und Güter pro HP liegen in `RarityConfig`
(persistiert mit `species_balance`), der globale K.O.-Faktor in
`game_config`/`heal_balance`. Der Reiter rechnet jede Zeile sofort auf ein
Referenz-Monster um (−55 % und K.O.), weil ein Wert „pro HP" für sich nichts
aussagt.

Default-Leiter für die Dauer (Preis bleibt flach bei 0,1/HP): common 25 ·
uncommon 30 · rare 40 · epic 55 · legendary 75 Sekunden/HP. Bei ~60 HP heisst
das nach einer Prüfung ~14 Min (common) bis ~41 Min (legendary), k.o. ~50 Min
bis ~2,5 h.

**Welche** Güter bezahlt werden, richtet sich nach der **Ära des MONSTERS**
(= `SpeciesDef.tier`, Region N = Ära N), nicht nach der Siedlung: ein Region-1-
Fang kostet immer Ära-1-Güter, ein Region-3-Fang Ära-3-Güter. Da `goodsForEra`
kumulativ ist, wird von der NIEDRIGSTEN Ära zuerst abgerechnet — sonst frisst
ein spätes Monster die Fische, auf die ein frühes angewiesen ist. Rabatte kommen
weiterhin vom Gebäude (`heal`-Effekt speed/cost + besetzter `medicine`-Posten,
zusammen max. −90 %).
- Ein Monster in Behandlung ist **raus**: kein Team, keine Expedition, keine
  Zucht. Ohne das wäre die Zeit folgenlos.
- Persistiert als `creatures.healing_until` (Migration 0007), **lazy aufgelöst**
  auf Load und im Tick — wie Expeditionen und Zucht. Nicht energie-gekoppelt:
  ein Monster heilt, ob du gelaufen bist oder nicht.
- Mit **Gold abkürzbar** wie jeder andere Timer (§9), nach Restzeit bepreist.

**Skalierung (User-Anforderung: „muss skalierbar sein, da in einer neuen Ära
neue Ressourcen dazukommen").** Nichts, was Goods ausgibt, nennt `fish` oder
`fur` beim Namen:

- `GoodsDef.eraOrder` — eine Ära **führt** ein Good ein, es bleibt danach
  verfügbar (kumulativ: Fisch zählt auch in Ära III).
- `goodsForEra(order)` + `goodsCost(total, order, stock)` — **die eine Stelle**,
  bei der Senken nach Goods fragen.

  ⚠️ **Bezahlt wird aus dem, was du HAST** (reichstes Good zuerst), nicht „eines
  von jedem". Die erste Fassung teilte gleichmässig auf und rundete pro Good
  auf — womit **jede** Kostenstelle mindestens 1 von **jedem** Ära-Good
  verlangte. Ära I hat Fisch *und Fell*, Region 1 hat **keinen Fell-Spot**, und
  Fell gibt es erst hinter dem Boss von Region 1. Fell alle = keine Heilung
  mehr = kein Kampf mehr = kein Fell. Exakt der Deadlock, gegen den die
  Heilhütte in §4b ungegatet wurde, nur eine Ebene tiefer: nicht das Gebäude
  war gegatet, sondern die Währung. Die alte Regel machte **jedes Ära-Good ohne
  frühe Quelle** zu einer tickenden Sperre. Tests bewachen das.
- Speicherung: **`resources.goods` jsonb** (Migration 0006) statt einer Spalte
  pro Good. Vorher brauchte eine neue Ressource eine Migration **und** zwei
  Zeilen in `ResourceModel` — genau das, was „nächste Ära, neue Ressource"
  teuer machte. Alt-Zeilen werden gelesen (Fallback auf die Spalten), die alten
  `fish`/`fur`-Spalten bleiben vorerst stehen.
- Auch der **Dungeon-Eintritt** ist umgestellt: `regionDungeonEntryCost(stage)`
  = `spreadOverGoods(16 + 8·stage, stage)` — Region↔Ära ist 1:1, also zahlt
  jede Region in ihren eigenen Goods.

**Eine neue Ressource kostet damit genau einen Eintrag** in `kGoodsDefs` mit
der passenden `eraOrder`. Heilen und Dungeon-Eintritt greifen sie automatisch
ab. Ein Test prüft, dass ein unbekanntes Good (`bronze`) ohne Schemaänderung
durch Speichern/Abziehen läuft.

**Bewusst NICHT gewählt:** passiver Unterhalt (bestraft Pausen — und genau so
eine Mechanik wurde gerade abgebaut) und Expeditions-Proviant (Expeditionen
sind die Hauptquelle für Goods; das wird zirkulär). Züchten als zusätzliche
Senke bleibt offen — es ist seltener (tech-gegatet, 4h+/Auftrag), also Würze,
nicht Grundlast.

## 9. Gold: Überschuss → Zeit

**Befund (2026-07-16):** Gold hatte **null Senken** — kein Gebäude, keine
Technologie, kein Ära-Aufstieg, kein Dungeon-Eintritt kostete je Gold. Zwei
Kommentare behaupteten das Gegenteil (`spendResources`: „gold's decided
spending sink"; `catch_logic`: „protecting the gold sink") — beide Reste aus
der Zeit, als Gold die Dungeon-Währung war. Beim Region-Redesign zog der
Eintritt auf Fisch/Felle um, Gold blieb liegen.

**Entscheid (User):** Gold = **Beschleuniger + Handelsware**, abbaubar auf der
Karte und per Gebäude. Ein Kreislauf:

> Überschuss verkaufen → 🪙 → Wartezeit überspringen

**Gold gatet nichts.** Wer es ignoriert, verliert keinen Inhalt — nur Geduld.
Das ist der Punkt: es gibt jedem Überschuss einen Zweck (ein Holzstapel, den
man nicht ausgeben kann, ist totes Gewicht), ohne zur Pflicht zu werden.

**Der Wechselkurs des Spiels** (`services/gold_economy.dart`, eine Datei für
alles — Verkauf und alle drei Skip-Knöpfe lesen dieselben Raten):

| Regler | Wert | Bedeutung |
|---|---|---|
| `kBasicSellRate` | 0.1 | 10 Holz/Stein → 🪙 1 |
| `kGoodsSellRate` | 0.35 | ~3 Fisch/Fell → 🪙 1 (knapp UND mit echter Senke) |
| `kSecondsPerGold` | 60 | 🪙 1 ≈ 1 Minute |

**Zusammen gelesen: 100 Holz kaufen 10 Minuten.** Ein Tagesertrag Holz (§2:
~850) ≈ 🪙 85 ≈ 1,5 h Überspringen. Ein Test bewacht beide Seiten davon: genug,
um sich zu lohnen, zu wenig, um das Spiel wegzukaufen.

**Preis nach RESTZEIT, nicht nach Gesamtdauer** (`goldToSkip`). Die letzte
Minute eines 8h-Zuchtauftrags kostet eine Minute. Damit ist Abwarten *immer*
der günstigere Weg und Gold bleibt Komfort statt Königsweg. Ein unfertiger
Timer kostet nie 0.

**Skip-Stellen:** Bau (Gebäude-Info), Forschung (Tech-Sheet), Expedition
(Expeditions-Karte). Der Bau-Preis rechnet mit der **echten** Wartezeit
(`buildRatePerHour`, ohne Teilung — jede Baustelle baut mit vollem Tempo) — ein
Gebäude mit zehn Bauarbeitern ist fast fertig und kostet fast nichts. Die Expedition kauft nur die **Reise**
frei: eine Fangjagd muss danach weiterhin von Hand gespielt werden. **Gold
kauft Zeit, nie ein Ergebnis.**

**Verfügbarkeit.** Gold war vorher praktisch unerreichbar (einzige Ader in
Region 3, Handelsposten hinter `barter_trade`) — ein Beschleuniger, an den man
nicht rankommt, beschleunigt nichts. Neu: `vh_placer` in **Region 1**
(6/h, Kapazität 90 — bewusst dünn, das ist der Bach, nicht die Mine). Der
**Markt** (Handelsposten → „🪙 Open Market") bleibt hinter `barter_trade`
(Prüfung Lv 10): früh hat man ohnehin keinen Überschuss, ab Mitte Ära I wird
er zu Zeit.

Skaliert wie die Goods: `sellRate` ist **abgeleitet** („ist das ein Good?"),
keine Tabelle pro Ressource — eine Ära-II-Ressource verkauft sich am Tag ihrer
Einführung ohne Codeänderung. Ein Test prüft genau das.

## 10. Offene Folgen
- Release-/Verwertungs-Mechanik (Fang-Tempo 5–8/Tag).
- Era II+: Kosten so staffeln, dass spätere Eras länger dauern dürfen.
- Energie-Anker (10 000 Schritte = 24 h = 100 % Uptime) bewusst beibehalten — einzige
  Fitness-Kopplung.
