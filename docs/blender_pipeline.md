# Gebäude aus Blender

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background `
    --python tool/blender/render_building.py -- `
    --preset breeding_hut --out docs/renders/breeding_hut.png
```

Das Ergebnis geht direkt ins Spiel: **Base width 1, Anchor X 0.5, Lift 0.** Keine
Feinjustierung, keine Nachbearbeitung.

## Warum das gegenüber Gemini gewonnen hat

Die zwei Dinge, die ein Bildmodell jedes Mal falsch macht, sind genau die zwei,
die Geometrie gratis richtig macht:

- **Parallelprojektion.** Eine orthografische Kamera *kann* keinen Fluchtpunkt
  erfinden. Die Kamera steht auf 60° / 45°, was ein Feld exakt doppelt so breit
  wie hoch abbildet — dieselbe 2:1-Form wie `iso_grid.dart`.
- **Die Grundfläche.** Die vier Bodenecken werden durch die Kamera *projiziert*,
  und `ortho_scale` und Kameraposition werden daraus gelöst. Die Basis füllt die
  Bildbreite und berührt die Unterkante, weil es ausgerechnet wurde.

Der Preis ist Charakter: ein Generator liefert Bausatz, kein Handgezeichnetes.

## Kontrollieren, nicht hoffen

```
--guides   # markiert die Grundfläche magenta
```

Die Ecken der markierten Fläche müssen den linken, rechten und unteren Bildrand
berühren. Tun sie das, stimmt die Einbettung. Nie mit `--guides` ausliefern.

## In Blender anschauen

Ohne `--background`, mit `--no-render` — dann baut das Skript die Szene und hört
auf, und du stehst vor dem Ding statt vor einem PNG:

```powershell
Start-Process "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" `
    -ArgumentList '--python','tool/blender/render_building.py','--', `
                  '--preset','breeding_hut','--no-render' `
    -WorkingDirectory "C:\Users\olivi\BoddyGame"
```

Es öffnet in der Kameraansicht mit gerendertem Shading. Mittlere Maustaste dreht,
Mausrad zoomt, `Numpad 0` zurück in die Kamera — dort ist der Ausschnitt exakt
der, den die Karte zeichnet.

## Auf der Karte anschauen

```powershell
python tool/preview_on_map.py docs/renders/breeding_hut.png 3 4
```

Legt den Render in Originalgrösse auf den Ära-I-Boden über seine eigene
Grundfläche, daneben dasselbe in 3×. **Beurteile bei 224 px**, nicht bei 672 —
ein Render in voller Grösse sieht immer gut aus.

## Weitere Schalter

| | |
|---|---|
| `--scale N` | Pixel pro Kachel. 3 reicht, 4 für Wahrzeichen |
| `--headroom F` | Bildhöhe als Vielfaches der Basisbreite. Höher für Türme |
| `--guides` | s.o. |
| `--no-render` | Szene bauen und aufhören (für die GUI) |
| `--blend PFAD` | Szene zusätzlich als .blend speichern |

## Der Stil: Fantasy römisch-mittelalterlich

Römisch liefert das Dach und den Bogen, mittelalterlich das Holzwerk und die
Neigung, Fantasy die Erlaubnis, alles zu sättigen. `PALETTE` in
[render_building.py](../tool/blender/render_building.py) ist die einzige
Farbquelle — greif nie zu einem rohen RGB, so hört ein Set nach dem dritten
Gebäude auf zusammenzupassen.

**Drei Signale tragen den Stil bei 224 px, alles andere ist Zierde:**

1. **Terrakotta-Dach**, gewalmt mit kurzem First und tiefem Überstand. Das
   lauteste Signal — und der Grund, warum der Stil zum Spiel passt: die
   Materialleiter raffiniert in Stufe II bereits Lehm. Die Dächer *sind*, was
   die Siedlung zu brennen lernt.
2. **Helle Wände** darunter — Kalkputz, Travertin. Der Kontrast zwischen heissem
   Dach und kühler Wand *ist* der Look.
3. **Ein Steinsockel.** Römer setzten keine Wand auf Erde. Löst nebenbei ein
   Bildproblem: das Gebäude wirkt auf seine Kacheln gegründet statt daraufgelegt.

Holz ist **Zierde, nicht Konstruktion** — Balken, Türen, Läden, Geländer. Ein
überwiegend hölzernes Gebäude rutscht zurück in die nordeuropäische Hütte.

## Bauteile

| Struktur | Dach | Wand | Hof |
|---|---|---|---|
| `box()` Mitte-Boden | `pantiles()` Ziegelreihen | `window()` Bogenfenster | `column()` Säule |
| `hip_roof()` Walmdach | `hip_ridges()` Gratziegel | `frieze()` Zierband | `pot()` Amphore |
| `plinth()` Steinsockel | `antefixes()` Stirnziegel | `dentils()` Zahnschnitt | `plant()` Kübelpflanze |
| `arch()` Rundbogen | `acroterion()` Firstzier | `banner()` Wimpel | `trough()` Tränke |
| `wall_box()` Wandtrimm | | `garland()` Girlande | `brazier()` Feuerschale |
| `egg()` Facettenkugel | | `sconce()` Wandlampe | `nest()` Nest |
| `steps()` Freitreppe | | `lantern()` Hängelampe | `straw_bale()` Strohballen |
| `pergola()` Laube | | | `straw_scatter()` loses Stroh |
| | | | `mosaic()` Bodenmuster |

**Verzierung ist nicht Schmuck, sondern Massstab.** Eine leere Wand hat keine
Grösse; eine Wand mit Zahnschnitt unter der Traufe ist unverkennbar ein Gebäude
statt einer Kiste. Bei 224 px hört das Ornament auf, als es selbst lesbar zu
sein, und wird Textur — das ist das Ziel, nicht das Scheitern: man soll
„verziert" lesen, nicht die Verzierungen zählen.

### Drei Fallen, jede einen Render teuer

- **`arch()` ist ein massiver Körper, kein Ring.** Das Gewände muss *hinter* der
  Öffnung liegen und grösser sein — davor verstopft es sie einfach.
- **Die beiden Ausrichtungen zeigen entgegengesetzt.** Eine für −Y gezeichnete
  Wand wird mit wachsendem y tiefer, eine +X-Wand mit *kleinerem* x. Falsches
  Vorzeichen = derselbe Fehler wie oben, gespiegelt. Deshalb heisst der Parameter
  `into` und nicht `out`.
- **Der Firstbalken muss *im* First sitzen.** Darüber liest er mit den
  Gratlinien zusammen als Kreuz auf dem Dach.

## Ein neues Gebäude

Eine Funktion in `tool/blender/render_building.py`, ein Eintrag in `PRESETS`:

```python
def foo(w, h):
    wall = flat('wall', (0.36, 0.20, 0.10))
    box('body', 0, 0, 0, w - 0.4, h - 0.4, 1.0, wall)

PRESETS = {..., 'foo': (foo, 3, 3)}
```

`box()` setzt bei **Mitte-Boden** an, weil Gebäude auf dem Boden stehen.
`gable()` ist ein Satteldach, `egg()` eine facettierte Kugel.

**Die Regel:** Nichts darf die Grundfläche verlassen ausser dem Dachüberstand.
Ein Zaun, der über die Basis hinausragt, macht das Bild breiter als sein Boden —
und das Gebäude wirkt dann nach hinten geschoben.

**Der Lesbarkeitstest:** 224 px auf einem Handy. Was ein Gebäude über sich sagt,
muss es über *Silhouette* und *eine* Akzentfarbe sagen. Die Brutstätte macht das
mit einem tiefen Dach über einer dunklen Öffnung und drei hellen Eiern in
leuchtendem Stroh — vor denen nichts stehen darf.

## Farbtransform

`view_transform = 'Standard'`. Blenders Standardeinstellung AgX zieht gesättigte
Farben absichtlich Richtung Grau — gut für Fotorealismus, tödlich für flache
Farbflächen. Der erste Render kam einheitlich beige heraus, genau deswegen.

## Was die Gemini-Strecke noch macht

[building_art_prompt.md](building_art_prompt.md) bleibt für die paar Wahrzeichen,
die auffallen dürfen. Beides erfüllt denselben Vertrag: 2:1, Basis füllt die
Breite, transparent, kein Terrain.
