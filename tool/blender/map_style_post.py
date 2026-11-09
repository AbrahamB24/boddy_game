"""Post pass of make_map_style.py: grade, size, mirror, ship as webp.

    py tool/blender/map_style_post.py C:/tmp/map            # ship into assets/
    py tool/blender/map_style_post.py C:/tmp/map --grade-only   # only the sprites
                                                              # nobody re-rendered

The grade is ONE function (GRADE) applied to everything on the map's ground, so
the ground, the trees and the animals share one look. Originals of the files it
touches are copied to <dir>/orig/ the first time, and the grade always starts
from those, so running it twice never grades twice.
"""
import glob
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'images', 'terrain')

# between the shipped look (sat 1.16, contrast 1.04) and "Goldene Stunde"
# (sat 1.3, warm tint, violet shadows): brighter and more colourful than the
# first, much less extreme than the second.
GRADE = dict(sat=1.26, contrast=1.05, lift=3, tint=(1.02, 1.0, 0.97),
             shadow=(0.01, 0.0, 0.03))

OLD = {   # picture sizes (px) of what each prop replaces: the area they keep
    'conifer_s': (214, 376), 'conifer_m': (294, 515), 'conifer_l': (368, 651),
    'broadleaf_s': (232, 288), 'broadleaf_m': (300, 383), 'broadleaf_l': (316, 516),
    'stone_a': (50, 42), 'stone_b': (106, 75), 'stone_c': (162, 85),
    'stone_d': (108, 108), 'stone_e': (202, 139), 'stone_f': (70, 47),
}
AREA_K = {'stone': 1.0, 'conifer': 1.0, 'broadleaf': 1.0}


def grade(img, g=GRADE):
    a = np.array(img.convert('RGBA'))
    x = a[..., :3].astype(np.float32)
    lum = (x * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    x = lum + (x - lum) * g['sat']
    x = (x - 128) * g['contrast'] + 128 + g['lift']
    x = x * np.array(g['tint'])
    x = x + (1 - lum / 255.0) * np.array(g['shadow']) * 255
    a[..., :3] = np.clip(x, 0, 255).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


def save(img, name):
    img.save(os.path.join(OUT, name + '.webp'), 'WEBP', quality=92, method=6)


def ship_tile(src, name):
    img = Image.open(src).convert('RGBA')
    w, h = img.size
    m = Image.new('RGBA', (w * 2, h * 2))
    m.paste(img, (0, 0))
    m.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
    m.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
    m.paste(img.transpose(Image.ROTATE_180), (w, h))
    save(grade(m), name)


def ship_prop(src, name):
    img = Image.open(src).convert('RGBA')
    foot = float(open(src[:-4] + '.foot').read())
    a = np.array(img)[..., 3]
    ys, xs = np.where(a > 8)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    half = int(np.ceil(max(foot - x0, x1 - foot))) + 1
    cx = int(round(foot))
    canvas = Image.new('RGBA', (2 * half, y1 - y0))
    canvas.paste(img.crop((x0, y0, x1, y1)), (x0 - (cx - half), 0))
    ow, oh = OLD[name]
    aspect = canvas.width / canvas.height
    nh = (ow * oh / aspect) ** 0.5
    nw = nh * aspect
    nw = max(2, round(nw))
    nw += nw % 2
    nh = max(2, round(nw / aspect))
    out = canvas.resize((nw, nh), Image.LANCZOS)
    save(grade(out), 'prop_' + name)
    print('prop', name, (nw, nh), 'was', (ow, oh))


def regrade_rest(work):
    """Props / animals that were not re-rendered: the same grade, from their
    originals (backed up once)."""
    orig = os.path.join(work, 'orig')
    os.makedirs(orig, exist_ok=True)
    done = {'prop_' + k for k in OLD}
    n = 0
    for f in sorted(glob.glob(os.path.join(OUT, '*.webp'))):
        base = os.path.basename(f)[:-5]
        if base in done or base.endswith('_tile'):
            continue
        bak = os.path.join(orig, base + '.webp')
        if not os.path.exists(bak):
            shutil.copy(f, bak)
        img = Image.open(bak)
        img.load()
        save(grade(img), base)
        n += 1
    print('graded', n, 'sprites')


def main():
    work = sys.argv[1]
    if '--grade-only' not in sys.argv:
        for t in ('grass', 'sand', 'water'):
            p = os.path.join(work, t + '_tile.png')
            if os.path.exists(p):
                ship_tile(p, t + '_tile')
                print('tile', t)
        for name in OLD:
            p = os.path.join(work, f'prop_{name}.png')
            if os.path.exists(p):
                ship_prop(p, name)
    regrade_rest(work)


if __name__ == '__main__':
    main()
