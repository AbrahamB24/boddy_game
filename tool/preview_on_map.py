"""Put a render on the map, at the size the map actually draws it.

    python tool/preview_on_map.py docs/renders/breeding_hut.png 3 4

A render viewed at 672 px always looks fine. The map draws a 3x4 building 224 px
wide on a phone, and that is where a design either reads or does not — so judge
it there. The left panel is life size; the right is the same pixels enlarged, to
see WHY it reads the way it does, not to flatter it.

The placement is the app's own rule (artPlacement with 1 / 0.5 / 0): the base
fills the image's width and its near corner sits on the footprint's near corner.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

TILE_W, TILE_H = 64, 32          # iso_grid.dart
GROUND = (62, 107, 69, 255)      # the era-I ground the map paints
SEAM = (255, 255, 255, 40)
PAD = 28


def tiles(w, h, scale):
    """The footprint's cells, drawn the way the map draws them."""
    base_w = (w + h) * TILE_W // 2 * scale
    base_h = base_w // 2
    img = Image.new('RGBA', (base_w, base_h), (0, 0, 0, 0))
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def p(gx, gy):
        return ((h + gx - gy) * TILE_W * scale / 2,
                (gx + gy) * TILE_H * scale / 2)

    d.polygon([p(0, 0), p(w, 0), p(w, h), p(0, h)],
              fill=(255, 255, 255, 26), outline=(255, 255, 255, 90), width=scale)
    for i in range(1, w):
        d.line([p(i, 0), p(i, h)], fill=SEAM, width=max(1, scale))
    for j in range(1, h):
        d.line([p(0, j), p(w, j)], fill=SEAM, width=max(1, scale))
    return Image.alpha_composite(img, layer)


def panel(art, w, h, scale, label):
    base_w = (w + h) * TILE_W // 2 * scale
    base_h = base_w // 2
    # baseWidth 1 => the art is exactly as wide as the base.
    sprite = art.resize((base_w, round(art.height * base_w / art.width)),
                        Image.LANCZOS)

    box_w = base_w + PAD * 2
    box_h = sprite.height + base_h + PAD * 2
    out = Image.new('RGBA', (box_w, box_h), GROUND)

    foot = tiles(w, h, scale)
    foot_top = box_h - PAD - base_h
    out.alpha_composite(foot, (PAD, foot_top))
    # lift 0 => the picture's bottom edge meets the footprint's near corner,
    # which is half a base-height below the footprint's top.
    out.alpha_composite(sprite, (PAD, box_h - PAD - sprite.height))

    d = ImageDraw.Draw(out)
    d.text((PAD, 8), label, fill=(255, 255, 255, 200))
    return out


def main():
    src, w, h = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    art = Image.open(src).convert('RGBA')
    # Trim the empty sky the render leaves above the building. The WIDTH is
    # untouched — it is the base, and cropping it would break the placement.
    bbox = art.getbbox()
    if bbox:
        art = art.crop((0, bbox[1], art.width, art.height))

    left = panel(art, w, h, 1, f'{w}x{h} - life size, {(w + h) * TILE_W // 2}px')
    right = panel(art, w, h, 3, f'{w}x{h} - 3x')

    gap = 24
    out = Image.new('RGBA', (left.width + right.width + gap,
                             max(left.height, right.height)), GROUND)
    out.alpha_composite(left, (0, out.height - left.height))
    out.alpha_composite(right, (left.width + gap, out.height - right.height))

    dst = src.with_name(src.stem + '_on_map.png')
    out.save(dst)
    print(f'{dst}  {out.width}x{out.height}')


main()
