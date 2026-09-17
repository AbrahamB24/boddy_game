"""Builds a seamless 2x2 mirrored super-tile from a single rendered ground
swatch (tool/blender/render_ground_tile.py), then packs it to webp.

Flutter's ImageShader only tiles a texture PLAINLY (TileMode.repeated —
no built-in mirror-repeat), and a straight repeat of a non-seamless swatch
shows a visible seam at every edge. Mirroring is the standard fix: paste the
swatch plus a horizontally-flipped, a vertically-flipped and a both-flipped
copy into a 2x2 grid, and EVERY boundary — within the super-tile and between
repeats of it — is a mirror match, for any source image, seamless-authored
or not.

    python3 tool/pack_terrain_tile.py docs/renders/grass_tile.png assets/images/terrain/grass_tile.webp
"""
import os
import sys

from PIL import Image


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: pack_terrain_tile.py <src.png> <out.webp>')
    src_path, out_path = sys.argv[1], sys.argv[2]

    im = Image.open(src_path).convert('RGB')
    w, h = im.size
    super_tile = Image.new('RGB', (w * 2, h * 2))
    super_tile.paste(im, (0, 0))
    super_tile.paste(im.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
    super_tile.paste(im.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
    super_tile.paste(im.transpose(Image.ROTATE_180), (w, h))

    os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
    super_tile.save(out_path, 'WEBP', quality=90)
    print(f'wrote {out_path}  {super_tile.size[0]}x{super_tile.size[1]}')


main()
