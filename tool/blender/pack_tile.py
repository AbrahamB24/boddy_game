"""Packs the ground tile: mirrors the rendered swatch to a seamless 2x2
super-tile, then sets the ground cover (flowers, tufts — see
terrain_voxel.render_decor) on it as UPSIDE-UP sprites with a little shadow.

    blender --background --python tool/blender/pack_tile.py -- <render dir>

Reads <dir>/grass_tile.png and <dir>/decor_*.png (terrain_voxel.py --what tile
and --what decor), writes assets/images/terrain/grass_tile.webp.

Why composited here and not rendered into the tile: the tile has to be
mirrored to tile seamlessly (Flutter's ImageShader cannot mirror-repeat), and
anything standing on it comes out upside down in the flipped copies.
"""
import os
import random
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, '..', '..', 'assets', 'images', 'terrain'))
FLOWERS, TUFTS = 320, 1300


def load(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = 'Non-Color'
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    d = args[0]
    name = args[1] if len(args) > 1 else 'grass'
    a = load(os.path.join(d, 'grass_tile.png' if name == 'grass' else f'{name}_tile.png'))
    h, w = a.shape[:2]
    a[..., 3] = 1
    top = np.concatenate([a, a[:, ::-1]], axis=1)
    sup = np.concatenate([top, top[::-1]], axis=0)
    H, W = sup.shape[:2]

    sprites = {}
    decor = name == 'grass'
    for dn in ('tuft', 'tuft2', 'flower0', 'flower1', 'flower2', 'flower3',
                 'flower4'):
        s = load(os.path.join(d, f'decor_{dn}.png'))
        sh, sw = s.shape[:2]
        ys, xs = np.where(s[..., 3] > 0.02)
        # rows are bottom-up; the foot is the image's centre (the origin)
        sprites[dn] = (s[ys.min():ys.max() + 1, xs.min():xs.max() + 1],
                         sw // 2 - xs.min(), ys.min() - sh // 2)
        print(dn, 'bbox', xs.min(), xs.max(), ys.min(), ys.max(), 'of', sw, sh)

    rnd = random.Random(5)

    def blit(s, fx, fy, shadow=False):
        spr, ox, oy = s
        sh, sw = spr.shape[:2]
        # foot (fx, fy) in bottom-up rows; sprite's lowest row is `oy` below
        # the origin row
        for j in range(sh):
            for i in range(sw):
                al = spr[j, i, 3]
                if al < 0.02:
                    continue
                x = (fx - ox + i) % W
                y = (fy + oy + j) % H
                sup[y, x, :3] = sup[y, x, :3] * (1 - al) + spr[j, i, :3] * al

    def shade(fx, fy, r):
        # a soft dark patch to the lower right of the foot (sun top left)
        for dy in range(-r, r + 1):
            for dx in range(-2 * r, 2 * r + 1):
                k = 1 - ((dx / (2 * r)) ** 2 + (dy / r) ** 2)
                if k > 0:
                    x, y = (fx + 2 + dx) % W, (fy - 1 + dy) % H
                    sup[y, x, :3] *= 1 - 0.28 * k

    placed = [('tuft', 'tuft2')[rnd.random() < 0.15] for _ in range(TUFTS)]
    placed += [f'flower{rnd.randrange(5)}' for _ in range(FLOWERS)]
    rnd.shuffle(placed)
    for dn in (placed if decor else []):
        fx, fy = rnd.randrange(W), rnd.randrange(H)
        shade(fx, fy, 2 if dn.startswith('flower') else 1)
        blit(sprites[dn], fx, fy)

    out = bpy.data.images.new('o', W, H, alpha=False)
    out.colorspace_settings.name = 'Non-Color'
    out.pixels = sup.ravel().tolist()
    sc = bpy.context.scene
    sc.render.image_settings.file_format = 'WEBP'
    sc.render.image_settings.quality = 90
    out.save_render(os.path.join(OUT_DIR, ('grass_tile.webp' if name == 'grass' else f'{name}_tile.webp')), scene=sc)
    print('packed', W, H, name)


main()
