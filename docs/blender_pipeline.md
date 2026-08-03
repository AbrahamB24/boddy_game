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
