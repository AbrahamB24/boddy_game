# Building art — the prompt

The prompt for Gemini / Nano Banana that produces every building sprite for the
settlement map.

The map is **isometric**, Forge of Empires shape (user 2026-08-01: "Ich will das
Raster … um 45° gedreht"). That means **one image per building** — an isometric
camera already shows two walls and the roof, so a single picture reads as a
solid object. There is no second view to draw and no map rotation.

The numbers below are not suggestions. They come from `iso_grid.dart`, and art
that ignores them will not tile.

| | |
|---|---|
| Tile | **64 × 32 px** (2:1) |
| Base width | `footprint_width_in_cells × 64 px` … see below |
| Camera | fixed, parallel projection, ~30° above, front face toward the **bottom-right** |
| Background | fully transparent |
| Shadow | none — the map draws the tile the building stands on |

**The base width is the diamond's width, not the building's:** a building that
covers `w × h` cells has a base spanning `(w + h) × 32 px`. A 2×2 building is
therefore **128 px** wide at the base, a 3×2 building **160 px**.

---

## The prompt

```text
Isometric low-poly building for a city-builder game, single object.

STYLE (do not deviate):
- Faceted low-poly illustration: the whole building is built from flat
  triangles and hard-edged polygons, like a papercraft model.
- Every facet is ONE flat colour. No gradients, no soft shading, no airbrush,
  no texture, no bricks drawn one by one.
- No outlines, no black contour lines. Shapes are separated by colour alone.
- 3 to 5 tones per colour family: a bright lit facet, a mid tone, a deep shadow
  tone, in sharp angular patches. The two visible walls must differ in tone —
  the one facing the light is clearly brighter.
- Bold, saturated, warm-lit palette. Clean and toy-like, not gritty.

CAMERA (identical for every building — this is what makes them tile):
- True isometric / 2:1 dimetric projection. PARALLEL projection only: no
  vanishing point, no perspective convergence, no lens distortion.
- Seen from above at a shallow angle, the front corner of the building pointing
  toward the bottom of the image; one wall faces bottom-left, the other
  bottom-right, the roof is visible.
- The building stands upright and is not rotated or tilted in the frame.

FOOTPRINT AND FRAMING:
- The building's ground base is a DIAMOND (rhombus) twice as wide as it is
  tall, drawn as if it covered exactly <W> by <H> tiles of an isometric grid.
- The base diamond touches the bottom point of the image, centred horizontally.
- The building may be as tall as it needs; leave the space above it empty.
- Fully TRANSPARENT background. No ground, no grass, no shadow under the
  building, no scene, no people, no props, no text, no labels, no borders.

BUILDING:
- <name>: <what it is, one line>.
- Era / material: <primitive timber / clay brick / iron and glass / …>.
- Colours: <primary>, <secondary>, <accent>.
- Features: <2 to 4 concrete shapes — a chimney, a waterwheel, drying racks>.
```

## Per building, fill in

- `<W>` × `<H>` — the footprint from the building's def (`gridW` / `gridH`).
- Then scale the finished PNG so its **base diamond** is `(W + H) × 32 px`
  wide. The image's own height is whatever the building needs.

## The one thing to check before uploading

Put the sprite's bottom point on a cell's south corner and see whether the base
covers exactly its footprint. If the diamond is too wide the building will
overlap its neighbours; too narrow and the ground shows through between them.
Everything else can be fixed later — this cannot, without redrawing.

## Checklist

- [ ] Transparent background (not white)
- [ ] No shadow, no ground plane, no grass
- [ ] Parallel projection — the top and bottom edges of a wall are PARALLEL
- [ ] Base diamond is 2:1 and the right width for the footprint
- [ ] Base touches the bottom of the image, centred
- [ ] Nothing cropped at the sides
- [ ] PNG
