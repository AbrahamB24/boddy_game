# Building art — the prompt

For Gemini / Nano Banana. Fill in **two** things: what the building is, and how
big (`<W>×<H>` tiles). Everything else is fixed, and the STYLE line is the
monsters' one condensed — same faceted language, so the two sets belong together
(see [monster_art_prompt.md](monster_art_prompt.md)).

```text
Isometric low-poly building, single object, game asset.

STYLE: faceted low-poly — flat colour per facet, no gradients, no textures, no
outlines. 3-5 tones per colour family: one lit facet, one mid, one shadow, in
sharp angular patches. Bold, saturated, warm-lit, toy-like, not gritty.

VIEW: true 2:1 isometric, PARALLEL projection — no perspective, no vanishing
point. The near corner points at the bottom of the image; one wall faces
bottom-left, the other bottom-right, roof visible. Upright, not tilted.

NO GROUND: no terrain, no grass, no dirt, no stone base, no platform, no
shadow, no fences or props outside the building, no scene, no text. Fully
transparent background — the building alone, nothing under it.

BASE: the building's footprint covers exactly <W> by <H> isometric tiles (a
diamond when W = H, otherwise a parallelogram of that many tiles). It fills the
image's width and touches its bottom edge. The building may be as tall as it
needs; leave the space above it empty.

BUILDING: <TYPE> — <one line: what it is, what happens there>. Materials:
<timber and thatch / clay brick / cut stone / iron and glass>. Colours:
<primary>, <secondary>, <accent>. Features: <2-4 concrete shapes>.
```

**Why no ground:** the map draws the tile the building stands on. Any terrain in
the PNG lands as a patch of someone else's grass on top of it — which is exactly
what makes a building look pasted on instead of built there.

**Why no loose props:** a fence standing outside the base makes the picture wider
than the ground it occupies, and the building then reads as pushed back. Keep
them inside the footprint.

## Sizes

| Footprint | Base width | | Footprint | Base width |
|---|---|---|---|---|
| 1 × 1 | 64 px | | 3 × 4 · 4 × 3 | 224 px |
| 2 × 2 | 128 px | | 4 × 4 | 256 px |
| 3 × 2 · 2 × 3 | 160 px | | 5 × 5 | 320 px |
| 3 × 3 | 192 px | | | |

`base width = (W + H) × 32 px`, bounding box always 2:1.

## If the base does not fill the image

It usually will not — a generator returns a square with air round the building.
Do not crop: Dev Mode ▸ the building ▸ under the PNG, three numbers place it.

| | |
|---|---|
| **Base width** | how much of the picture's width the base spans (`0.62`). Below 1 draws the building **bigger**, above 1 **smaller** |
| **Anchor X** | where its front point sits across the picture (`0.5` = centred) |
| **Lift** | how far that point sits above the picture's bottom edge, in fractions of its width (`0.08`) |

`1 / 0.5 / 0` = drawn exactly to the contract. Nudge **Base width** until the
building sits on its own tiles, then **Lift** until its foot meets them.

## Checklist

- [ ] Transparent — no white, no ground, no shadow, no props outside the base
- [ ] Parallel projection: a wall's top and bottom edges are PARALLEL
- [ ] Base covers exactly W × H tiles (a diamond only when W = H)
- [ ] Flat facets: no gradient, no texture, no outline
- [ ] Nothing cropped, PNG
