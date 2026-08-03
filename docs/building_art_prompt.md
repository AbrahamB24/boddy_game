# Building art — the prompt

The prompt for Gemini / Nano Banana that produces every building on the
settlement map.

Two things have to be true at once:

1. **It belongs to the monsters.** Same faceted low-poly language, same flat
   fills, same saturated palette — the STYLE block below is the monsters' one,
   word for word (see [monster_art_prompt.md](monster_art_prompt.md)). Do not
   reword it; a paraphrased style prompt is an inconsistent one.
2. **It fits the grid.** The map is isometric (2:1, Forge of Empires shape), so
   the base has to cover exactly the tiles the building occupies. That is the
   one thing no amount of retouching fixes later.

You fill in **two** things per building: **what it is** and **how big**.

---

## Pick the size first

`W × H` is the footprint in tiles — `gridW` / `gridH` on the building's def. It
decides the image's width, and nothing else about the picture.

| Footprint | Base width | Used by |
|---|---|---|
| 1 × 1 | **64 px** | roads |
| 2 × 2 | **128 px** | huts, small camps |
| 3 × 2 · 2 × 3 | **160 px** | works, oblong yards |
| 3 × 3 | **192 px** | the common production building |
| 3 × 4 · 4 × 3 | **224 px** | larger works |
| 4 × 4 | **256 px** | refineries, big halls |
| 5 × 5 | **320 px** | the main hall, grand works |

The rule behind the table: **base width = (W + H) × 32 px**, and its bounding box
is always twice as wide as it is tall. A square footprint draws a diamond;
anything else draws a parallelogram of that many tiles — a 3 × 2 is *not* a
squashed diamond, and drawn as one it will not sit on its own cells.

---

## The prompt

```text
Isometric low-poly building for a city-builder game, single object.

STYLE (do not deviate — this is the same style sheet the creatures use):
- Faceted low-poly illustration: the whole building is built from flat
  triangles and hard-edged polygons, like a papercraft model.
- Every facet is ONE flat colour. No gradients, no soft shading, no airbrush,
  no texture, no bricks or shingles drawn one by one.
- No outlines, no black contour lines. Shapes are separated by colour alone.
- 3 to 5 tones per colour family: a bright highlight facet, a mid body tone, a
  deep shadow tone, used in sharp angular patches. The two visible walls differ
  clearly in tone — one faces the light, the other does not.
- Bold, saturated, warm-lit palette. Clean and toy-like, not gritty, not
  realistic, no weathering or dirt.
- Crisp geometric silhouette with pointed, angular extremities.
- Flat 2D presentation, no depth of field, no glow, no particles.

CAMERA (identical for every building — this is what makes them tile):
- True isometric / 2:1 dimetric projection. PARALLEL projection only: no
  vanishing point, no perspective convergence, no lens distortion. Vertical
  edges stay vertical; the two ground edges run at the same shallow angle.
- Seen from above at a shallow angle, the near corner of the building pointing
  toward the bottom of the image: one wall faces bottom-left, the other
  bottom-right, and the roof is visible.
- The building stands upright, not rotated or tilted in the frame.

FOOTPRINT AND FRAMING:
- The building's ground base covers exactly <W> by <H> tiles of the isometric
  grid — a diamond when <W> equals <H>, otherwise a parallelogram of that many
  tiles. Its bounding box is twice as wide as it is tall.
- The base fills the full width of the image and touches its bottom edge.
- The building may be as tall as it needs; leave the space above it empty.
- Fully TRANSPARENT background. No ground, no grass, no shadow under the
  building, no scene, no people, no props, no text, no labels, no borders.

BUILDING:
- <TYPE>: <one line — what it is and what happens there>.
- Era and materials: <primitive timber and thatch / clay brick and tile /
  cut stone / iron and glass / …>.
- Colours: <primary>, <secondary>, <accent>.
- Features: <2 to 4 concrete shapes — a chimney, a waterwheel, drying racks,
  stacked barrels, a crane arm>.
- Show what the building DOES: a workplace has its work visible from outside.
```

## Filling it in — an example

```text
FOOTPRINT AND FRAMING:
- … covers exactly 3 by 3 tiles …

BUILDING:
- Wood Works: a timber yard where trunks are cut into planks.
- Era and materials: primitive timber, thatch, rope.
- Colours: warm brown, ochre, moss green accents.
- Features: a saw frame under an open shelter, stacked logs, a plank rack,
  a low fence along the near edge.
```

## After the image

Ideally the base already fills the width and touches the bottom edge. It usually
will not: a generator returns a square picture with the building somewhere
inside it and air all round.

**You do not have to crop it.** Dev Mode ▸ the building ▸ under the PNG there are
three numbers that tell the map where the base is:

| | |
|---|---|
| **Base width** | how much of the picture's WIDTH the base spans — e.g. `0.62` |
| **Anchor X** | where the base's front point sits across it — `0.5` if centred |
| **Lift** | how far that point sits above the picture's bottom edge, in fractions of its width — e.g. `0.08` |

`1 / 0.5 / 0` means "drawn exactly to the contract". Nudge Base width until the
building sits on its own tiles, then Lift until its foot meets them.

**Loose props are the usual culprit.** In the first test image the fences stood
well outside the building's base, so the picture was much wider than the ground
it occupies — the building then reads as pushed back. Either keep props inside
the footprint, or set Base width to the building's real base and let the fences
overhang, which is what the overhang is for.

**The one check before you generate thirty more:** drop it on the map and look at
where the base meets the ground. Too wide and it overlaps its neighbours; too
narrow and grass shows through. That is fixable with the three numbers — a base
drawn in the wrong SHAPE (a diamond where the footprint is oblong) is not.

## Checklist

- [ ] Transparent background (not white)
- [ ] No shadow, no ground plane, no grass
- [ ] Parallel projection — a wall's top and bottom edges are PARALLEL
- [ ] Base covers exactly W × H tiles (a diamond only when W == H)
- [ ] Base spans the full image width and touches the bottom edge
- [ ] Flat facets only: no gradient, no texture, no outline
- [ ] Nothing cropped at the sides
- [ ] PNG
