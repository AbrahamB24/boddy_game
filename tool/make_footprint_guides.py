"""Draw the isometric footprint guides you hand to the image model.

    python tool/make_footprint_guides.py

Writes one PNG per footprint the roster uses into docs/footprint_guides/.

── Why a picture and not a sentence ──
"The base covers 3 by 4 isometric tiles" is a sentence an image model will nod
at and then draw a diamond anyway. A REFERENCE IMAGE is not a request, it is a
measurement: hand it the guide, say "the building's ground base fills the marked
area exactly", and the shape stops being negotiable.

── The geometry is the app's ──
Tile 64 x 32 (2:1), base width (W + H) x 32 — the same numbers iso_grid.dart
uses. The guides are drawn at SCALE x that, so they are crisp enough to see, and
the proportions are what matter, not the pixel count: the app scales whatever
comes back to the footprint's width.

The base sits at the BOTTOM of the guide with empty room above it, because that
is where the building goes and how much of it there is.
"""
from pathlib import Path

from PIL import Image, ImageDraw

# The app's tile, from iso_grid.dart.
TILE_W = 64
TILE_H = 32
# Bigger pictures read better in a prompt; the ratio is what carries the rule.
SCALE = 4
# How much sky the building gets, as a multiple of the base's own height. A
# building is usually about one and a half times its base tall; more room than
# that and the model draws something small in a big empty frame.
HEADROOM = 1.5

# The footprints the roster actually uses.
SIZES = [(1, 1), (2, 2), (2, 3), (3, 2), (3, 3), (3, 4), (4, 3), (4, 4), (5, 5)]

OUT = Path('docs/footprint_guides')

INK = (255, 255, 255, 210)
SEAM = (255, 255, 255, 120)
FILL = (255, 255, 255, 38)
SKY = (30, 36, 42, 255)


def corner(gx, gy, w, h):
    """A grid corner in the guide's own pixels — the app's projection, scaled."""
    a = TILE_W * SCALE / 2
    b = TILE_H * SCALE / 2
    return ((h + gx - gy) * a, (gx + gy) * b)


def draw(w, h):
    base_w = (w + h) * TILE_W * SCALE / 2
    base_h = base_w / 2
    img_w = int(base_w)
    img_h = int(base_h * (1 + HEADROOM))
    img = Image.new('RGBA', (img_w, img_h), SKY)
    # A SEPARATE LAYER, composited at the end. ImageDraw WRITES the colour it is
    # given, alpha and all, instead of blending it — draw the translucent fill
    # straight onto the sky and you get an opaque white slab with no seams on it.
    layer = Image.new('RGBA', (img_w, img_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    top = img_h - base_h  # the base sits at the foot of the picture

    def p(gx, gy):
        x, y = corner(gx, gy, w, h)
        return (x, y + top)

    # The footprint itself.
    d.polygon([p(0, 0), p(w, 0), p(w, h), p(0, h)], fill=FILL, outline=INK,
              width=max(2, SCALE // 2))
    # The seams between its cells, so the count is readable, not just the area.
    for i in range(1, w):
        d.line([p(i, 0), p(i, h)], fill=SEAM, width=max(1, SCALE // 3))
    for j in range(1, h):
        d.line([p(0, j), p(w, j)], fill=SEAM, width=max(1, SCALE // 3))

    img = Image.alpha_composite(img, layer)
    OUT.mkdir(parents=True, exist_ok=True)
    name = OUT / f'{w}x{h}.png'
    img.save(name)
    return name, img_w, img_h


if __name__ == '__main__':
    for w, h in SIZES:
        name, iw, ih = draw(w, h)
        print(f'{w}x{h}  {iw}x{ih}px  ->  {name}')
