# Monster art — the prompt

The prompt for Gemini / Nano Banana that produces every monster sprite. Two
images per monster: **front** (the enemy side sees this) and **back** (your own
team is drawn from behind — see `_bigSprite(back:)` in `battle_screen.dart`).

The style block is **verbatim, every time**. That is the whole trick: an image
model is consistent with a constant prompt and inconsistent with a paraphrased
one, so nothing in the STYLE section may be reworded per monster — only the
CHARACTER lines change.

---

## 1 · The front view (text → image)

```
Low-poly vector game character, front view.

STYLE (do not deviate):
- Faceted low-poly illustration: the whole body is built from flat triangles
  and hard-edged polygons, like a papercraft model.
- Every facet is ONE flat colour. No gradients, no soft shading, no airbrush,
  no texture. Shading exists only as neighbouring facets in lighter and darker
  tones of the same hue.
- No outlines, no black contour lines. Shapes are separated by colour alone.
- 3 to 5 tones per colour family: a bright highlight facet, a mid body tone, a
  deep shadow tone, used in sharp angular patches.
- Bold, saturated, warm-lit palette. Clean and toy-like, not gritty.
- Crisp geometric silhouette with pointed, angular extremities.
- Flat 2D presentation, no perspective distortion, no depth of field.

FRAMING (identical for every character):
- Full body, standing, facing the viewer straight on, head slightly turned to
  its left, weight on both feet.
- Whole figure inside the frame, centred horizontally, feet at the bottom with
  a small margin. Nothing cropped.
- Square image.
- Fully TRANSPARENT background. No ground, no shadow under the feet, no scene,
  no props, no text, no logo, no border.

CHARACTER:
- <name>, a <one-line description: animal base, size, mood>.
- Colours: <primary>, <secondary>, <accent>.
- Features: <horns / wings / tail / armour — 2 to 4 concrete shapes>.
```

## 2 · The back view (image + text → image)

Do **not** write the back view from scratch. Hand the model the finished front
image and ask for a turnaround — that is the only way the two match:

```
Here is a character sheet image. Draw THE SAME character seen from directly
behind, at exactly the same scale, pose, proportions and colours.

- Same faceted low-poly style, same flat colour palette, same facet sizes.
- Same framing: full body, centred, feet at the bottom, same height in frame as
  the reference, square image, fully transparent background.
- No shadow, no ground, no scene.
- The head faces away from the viewer; no face, no eyes visible.
- Show what the back actually has: the back of the head, the spine line, the
  wings/tail/fins from behind.
```

---

## Why these constraints, specifically

**Transparent background.** The app composites the sprite over the battlefield
scene and over the map's building tiles. A white background becomes a white box.

**No shadow, no ground.** The battle screen draws both itself: a hard offset
silhouette behind the sprite (`_spriteWithShadow`) and the element platform the
monster stands on (`TypePodium`). A baked-in shadow lands on top of those and
reads as a second, misregistered monster.

**Same scale and the same feet line in both views.** The app sizes sprites by
HEIGHT and bottom-aligns them on the platform. If the back view sits higher in
its frame, the monster hops when the camera turns.

**No outlines.** The whole app is flat-shaded with facet edges — a black contour
is the one thing that would make the sprites read as a different set of art.

**Square.** `BoxFit.contain` means a non-square image is letterboxed and lands
smaller than its neighbours.

## Checklist before uploading

- [ ] Background really transparent (not white)
- [ ] Front and back the same size, same colours, feet at the same line
- [ ] No shadow, no ground plane
- [ ] Nothing cropped at any edge
- [ ] PNG
