# Monster art — the prompt

The prompt for Gemini / Nano Banana that produces every monster sprite.

A species has **three evolution stages** (`StatCurve.stageBase` is always length
3) and every stage needs a **front** and a **back** view — the enemy side is
drawn facing you, your own team from behind (`_bigSprite(back:)` in
`battle_screen.dart`). That is six images per species, and they all have to
belong to each other.

So they are made in **two sheets**: all three stages at once, front, then the
same sheet turned around. Generating six images separately is how a line ends up
with three unrelated animals in a family album.

The STYLE block is used **verbatim, every time**. That is the whole trick: an
image model is consistent with a constant prompt and inconsistent with a
paraphrased one, so nothing in it may be reworded per monster — only the
CHARACTER lines change.

---

## 1 · The evolution sheet (text → image)

```text
Low-poly vector game character sheet: ONE creature in its three evolution
stages, side by side, front view.

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

THE THREE STAGES (same creature, growing up — not three creatures):
- Stage 1, left: small, round, few facets, short limbs, big head, harmless and
  cute. About 45% the height of stage 3.
- Stage 2, middle: adolescent. Longer limbs, the adult features starting —
  horns/wings/tail still small. About 70% the height of stage 3.
- Stage 3, right: full grown. Tallest, sharpest silhouette, the most facets,
  imposing.
- The SAME colour palette, the same markings and the same signature feature
  across all three — you must be able to tell they are one line at a glance.
  Each stage adds to the previous silhouette; nothing disappears between them.

LAYOUT (this is a cutting sheet — keep it mechanical):
- Exactly three figures, left to right, in stage order.
- All three standing on the SAME invisible ground line, feet aligned.
- Equal horizontal gaps, and the same margin left of the first and right of the
  last. Generous space between them — no overlap, nothing touching.
- Every figure fully inside the frame. Nothing cropped.
- Wide image, 3:1.
- Fully TRANSPARENT background. No ground, no shadows under the feet, no scene,
  no props, no text, no labels, no numbers, no borders, no frames.

CHARACTER:
- <name>, a <one-line description: animal base, mood>.
- Element: <fire / water / plant / …>.
- Colours: <primary>, <secondary>, <accent>.
- Signature feature carried through all three stages: <horns / crest / tail
  flame / shell — one or two concrete shapes>.
```

## 2 · The back sheet (image + text → image)

Do **not** write this one from scratch. Hand the model the finished front sheet:

```text
Here is a character sheet with three evolution stages. Draw THE SAME three
creatures seen from directly behind.

- Same order, same positions, same sizes, same ground line, same gaps.
- Same faceted low-poly style, same flat palette, same facet sizes.
- Wide 3:1 image, fully transparent background, no shadow, no ground, no text.
- The heads face away from the viewer; no faces, no eyes.
- Show what the back actually has: the back of the head, the spine, the
  wings/tail/shell from behind.
```

## 3 · Cutting it up

The app wants one **square PNG per stage per view** — six files.

Cut the sheet into **three equal squares**, each centred on one figure, all cut
at the same height. Do **not** re-crop each stage to fit its own figure: the
size difference between the stages is the point. The app scales a sprite by
HEIGHT inside its box, so a stage-1 monster that sits small in its square shows
up small in the game, and the line grows on screen for free. Crop each one to
its own outline and all three come out the same size — which is exactly the
mistake that makes an evolution feel like a re-skin.

---

## Why these constraints, specifically

**Transparent background.** The app composites the sprite over the battlefield
scene and over the map's building tiles. A white background becomes a white box.

**No shadow, no ground.** The battle screen draws both itself: a hard offset
silhouette behind the sprite (`_spriteWithShadow`) and the element platform the
monster stands on (`TypePodium`). A baked-in shadow lands on top of those and
reads as a second, misregistered monster.

**One ground line across the sheet.** The app bottom-aligns sprites on the
platform. If a stage sits higher in its square than its neighbours, it floats.

**Front and back from one sheet.** Same scale, same colours, same feet line — so
the monster does not hop or change size when the camera turns to your side of
the field.

**No outlines.** The whole app is flat-shaded with facet edges — a black contour
is the one thing that would make the sprites read as a different set of art.

**Square per stage.** `BoxFit.contain` letterboxes anything else, so a
non-square file lands smaller than its neighbours for no reason.

## Checklist before uploading

- [ ] Background really transparent (not white)
- [ ] Six files: three stages × front/back
- [ ] Front and back match per stage: size, colours, feet line
- [ ] The three stages cut from equal squares — stage 1 IS smaller
- [ ] No shadow, no ground plane, no labels
- [ ] Nothing cropped at any edge
- [ ] PNG
