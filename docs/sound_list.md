# Soundliste: was es gibt und was das Spiel brauchen könnte

Stand 2026-09-28. **Vorhanden = liegt in `assets/sfx` bzw. `assets/music` und wird abgespielt.**
Alles andere ist ein Vorschlag, den du liefern kannst. Nichts davon ist im Code
eingehängt, ausser die vorhandenen. Du lieferst die Datei, ich hänge sie an den
passenden Moment.

## Empfehlung für die Lieferung

| Thema | Vorschlag |
|---|---|
| Kurze Effekte (unter 3 s) | **WAV**, 44,1 kHz, 16 bit, mono |
| Musik und Ambiente (Loops) | **MP3** (oder OGG), 44,1 kHz, stereo, **nahtlos loopbar** |
| Lautstärke | Alle Effekte auf ähnliche Lautheit normalisieren (ca. −16 LUFS), ohne Stille am Anfang |
| Dateiname | `bereich_name.wav`, z. B. `ui_open.wav`, `build_complete.wav`, `battle_crit.wav` |
| Varianten | Wo „(×3)“ steht, bitte 2–3 leicht verschiedene Fassungen. Wiederholte Klänge (Tippen, Treffer) nerven sonst schnell |

Es gibt zwei getrennte Schalter im Profil: **Sound** und **Vibration**. Alle Klänge
hängen am selben Sound-Schalter.

---

## 1. Schon vorhanden (13 Dateien)

| Datei | Wann | Bemerkung |
|---|---|---|
| `tap.wav` | normaler Knopf | wird sehr oft gespielt, muss leise und kurz sein |
| `place.wav` | Gebäude / Strasse abgesetzt | |
| `success.wav` | etwas geschafft (Arbeiter eingestellt, Expedition gesendet) | wird **auch** für „Meldung“ benutzt, siehe 2 |
| `collect.wav` | Ressourcen / Belohnung erhalten | |
| `fanfare.wav` | Level, Entwicklung, Epoche | |
| `deny.wav` | abgelehnt (zu wenig Ressourcen, kein Platz) | |
| `fire_attack.mp3` | Feuer-Angriff im Kampf | |
| `light_attack.mp3` | Licht-Angriff | |
| `neutral_attack.mp3` | Neutral-Angriff (und Ersatz für fehlende Typen) | |
| `plant_attack.mp3` | Pflanzen-Angriff | |
| `shadow_attack.mp3` | Schatten-Angriff | |
| `water_attack.mp3` | Wasser-Angriff | |
| `battle_theme.mp3` | Kampfmusik (Loop) | die **einzige** Musik im Spiel |

**Fehlende Angriffs-Klänge:** `ice_attack`, `lightning_attack`, `stone_attack`. Bis dahin
klingen Eis-, Blitz- und Stein-Angriffe wie Neutral.

---

## 2. Oberfläche (UI)

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `ui_alert.wav` | Meldung: Herausforderung, Nachricht, Gegner in der Lobby. **Heute dasselbe wie `success.wav`**, braucht einen eigenen Klang | hoch |
| `ui_open.wav` | Menü / Dialog / Seite öffnet | hoch |
| `ui_close.wav` | schliessen, zurück | hoch |
| `ui_tab.wav` | Reiter / Filter wechseln | mittel |
| `ui_toggle_on.wav` / `ui_toggle_off.wav` | Schalter im Profil | niedrig |
| `ui_confirm.wav` | wichtiger Bestätigen-Knopf (Goldknopf) | mittel |
| `ui_error.wav` | Fehlermeldung (Netz, Speichern fehlgeschlagen) | mittel |
| `ui_bell.wav` | Glocke: neue Ereignisse | mittel |
| `ui_banner.wav` | Banner oben (PvP, Nachricht) erscheint | niedrig |
| `ui_scroll_end.wav` | Liste am Ende (optional) | niedrig |

## 3. Siedlung und Bauen

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `build_start.wav` | Bau beginnt (Hammer, Holz) | hoch |
| `build_complete.wav` | Gebäude fertig (kurzes Jingle) | hoch |
| `build_upgrade.wav` | Ausbau auf nächste Stufe fertig | mittel |
| `build_select.wav` | Gebäude auf der Karte antippen | mittel |
| `build_pickup.wav` | Gebäude aufnehmen (Umbau) | mittel |
| `build_recall_all.wav` | „Recall all“ | niedrig |
| `build_demolish.wav` | löschen | niedrig |
| `road_paint.wav` (×3) | Strassenstück legen | mittel |
| `worker_assign.wav` | Arbeiter eingestellt | hoch |
| `worker_remove.wav` | Arbeiter abgezogen | niedrig |
| `building_pause.wav` / `building_resume.wav` | Pause an / aus | niedrig |
| `era_up.wav` | neue Epoche (grosser Moment, länger als `fanfare`) | hoch |
| `store_full.wav` | Lager voll (Warnung, dezent) | mittel |
| `energy_low.wav` | Energie fast leer | mittel |
| `energy_full.wav` | Energie voll | niedrig |

## 4. Wirtschaft

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `gold_gain.wav` | Gold erhalten | hoch |
| `gold_spend.wav` | Gold bezahlt (Zeit abkürzen) | mittel |
| `trade_sell.wav` / `trade_buy.wav` | Markt: verkaufen / kaufen | mittel |
| `trade_swap.wav` | tauschen | niedrig |
| `caravan_depart.wav` | Karawane bricht auf (Glocke, Huf) | mittel |
| `caravan_arrive.wav` | Karawane zurück | mittel |
| `craft_start.wav` | Handwerk beginnt | niedrig |
| `craft_done.wav` | Gegenstand fertig | mittel |
| `pack_open.wav` | Ressourcen-Paket öffnen | niedrig |
| `chest_open.wav` | Tageskiste | mittel |
| `daily_claim.wav` | Tagesaufgabe eingelöst | mittel |
| `streak_up.wav` | Serie verlängert | niedrig |

## 5. Monster

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `monster_levelup.wav` | Level-up | hoch |
| `monster_evolve.wav` | Entwicklung (länger, mit Aufbau) | hoch |
| `monster_learn.wav` | Fähigkeit gelernt | mittel |
| `monster_equip.wav` | Fähigkeit ausrüsten | niedrig |
| `monster_heal_start.wav` / `monster_heal_done.wav` | Behandlung beginnt / fertig | mittel |
| `monster_release.wav` | Monster freilassen | niedrig |
| `monster_tap_<typ>.wav` | Monster antippen: ein kurzer Ruf **pro Typ** (9 Typen) | niedrig, aber sehr charmant |
| `egg_place.wav` | Ei in den Brutkasten | mittel |
| `egg_hatch.wav` | Ei schlüpft (Knacken, dann Jingle) | hoch |
| `breed_start.wav` / `breed_done.wav` | Zucht beginnt / Ei bereit | mittel |
| `expedition_send.wav` | Expedition los (Horn, Schritte) | mittel |
| `expedition_return.wav` | Expedition zurück | mittel |
| `hunt_found.wav` | Jagd: etwas gefunden | niedrig |

## 6. Kampf

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `ice_attack.mp3`, `lightning_attack.mp3`, `stone_attack.mp3` | fehlende Typen (siehe oben) | **hoch** |
| `battle_start.wav` | Kampf beginnt (Horn) | hoch |
| `battle_boss_intro.wav` | Boss erscheint | mittel |
| `battle_turn.wav` | dein Zug beginnt | mittel |
| `battle_select.wav` | Fähigkeit wählen | niedrig |
| `battle_hit.wav` (×3) | Schaden landet (normal) | hoch |
| `battle_hit_super.wav` | sehr effektiv | hoch |
| `battle_hit_resist.wav` | schwach / resistent | mittel |
| `battle_miss.wav` | daneben | mittel |
| `battle_crit.wav` | Volltreffer (falls es das gibt) | niedrig |
| `battle_ko.wav` | Monster besiegt | hoch |
| `battle_heal.wav` | Heilung | mittel |
| `battle_buff.wav` / `battle_debuff.wav` | Wert steigt / sinkt | mittel |
| `status_<name>.wav` | Status wird verhängt, je einer für **burn, frost, freeze, poison, fear, sleep, petrify, paralysis, soaked, dazzled, confusion** (11) | mittel |
| `status_tick_burn.wav`, `status_tick_poison.wav` | Schaden am Zugende | niedrig |
| `battle_item.wav` | Item benutzt | mittel |
| `battle_switch.wav` | Monster gewechselt | mittel |
| `battle_flee.wav` | Flucht | niedrig |
| `battle_victory.wav` | Sieg (Jingle) | hoch |
| `battle_defeat.wav` | Niederlage | hoch |
| `battle_xp.wav` | XP-Balken füllt sich (Loop-Tick) | niedrig |
| `capture_throw.wav` | Fangversuch wirft | mittel |
| `capture_shake.wav` (×3) | Kugel wackelt | mittel |
| `capture_success.wav` | gefangen | hoch |
| `capture_fail.wav` | ausgebrochen | mittel |

## 7. PvP und Soziales

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `pvp_challenge.wav` | Herausforderung erhalten | hoch |
| `pvp_joined.wav` | Gegner betritt die Lobby | hoch |
| `pvp_ready.wav` | Gegner ist bereit | mittel |
| `pvp_countdown.wav` | Start-Countdown | mittel |
| `pvp_your_turn.wav` | du bist dran (ausserhalb des Kampfs) | mittel |
| `pvp_win.wav` / `pvp_lose.wav` | Ergebnis | mittel |
| `chat_message.wav` | neue Nachricht | hoch |
| `friend_request.wav` | Freundschaftsanfrage | niedrig |

## 8. Tutorial

| Datei-Vorschlag | Moment | Priorität |
|---|---|---|
| `tutorial_step.wav` | nächster Schritt | niedrig |
| `tutorial_hint.wav` | Hinweis leuchtet auf | niedrig |
| `tutorial_done.wav` | Tutorial abgeschlossen | mittel |

---

## 9. Musik und Ambiente (Loops)

Heute läuft **nur im Kampf** Musik. Die Siedlung ist still.

| Datei-Vorschlag | Wo | Priorität |
|---|---|---|
| `music_settlement.mp3` | Siedlungskarte, ruhig, darf lange laufen | **hoch** |
| `music_menu.mp3` | Menüs (Monster, Tasche, Markt …), oder einfach die Siedlungsmusik leiser | mittel |
| `music_login.mp3` | Login / Ladebildschirm | mittel |
| `music_overworld.mp3` | Weltkarte / Kampfpfad | mittel |
| `music_boss.mp3` | Bosskampf | mittel |
| `music_pvp.mp3` | PvP-Kampf | niedrig |
| `stinger_victory.mp3` / `stinger_defeat.mp3` | kurze Musikmarke am Kampfende | mittel |
| `amb_day.mp3` | Vogelgezwitscher, Wind (unter der Musik) | niedrig |
| `amb_night.mp3` | Grillen, Nachtwind (falls es Tag/Nacht gibt) | niedrig |
| `amb_workshop.wav` | leises Hämmern und Sägen, wenn viel gearbeitet wird | niedrig |

---

## Vorschlag zur Priorität

1. **Drei fehlende Angriffs-Klänge** (Eis, Blitz, Stein): heute klingen sie falsch.
2. **`ui_alert`**: ein eigener Klang für Meldungen.
3. **Siedlungsmusik**: das Spiel ist heute dort völlig still.
4. **Grosse Momente**: Gebäude fertig, Level-up, Ei schlüpft, Sieg/Niederlage, Epoche.
5. **Kampfdetails**: Treffer, K.O., Status.
6. Der Rest nach Lust und Zeit. Die Wirtschaftsklänge (Gold, Handel) sind schnell
   gemacht und geben viel Gefühl.
