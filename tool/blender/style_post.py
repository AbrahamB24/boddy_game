"""Post pass of the style lab (no Blender needed): colour grade, outline, pixel grid,
palette + dither, and the seamless mirror of the ground swatches.

    py tool/blender/style_post.py C:/tmp/lab C:/tmp/pub
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

E32 = ['#be4a2f', '#d77643', '#ead4aa', '#e4a672', '#b86f50', '#733e39',
       '#3e2731', '#a22633', '#e43b44', '#f77622', '#feae34', '#fee761',
       '#63c74d', '#3e8948', '#265c42', '#193c3e', '#124e89', '#0099db',
       '#2ce8f5', '#ffffff', '#c0cbdc', '#8b9bb4', '#5a6988', '#3a4466',
       '#262b44', '#181425', '#ff0044', '#68386c', '#b55088', '#f6757a',
       '#e8b796', '#c28569']

# What the post pass does per style (everything else is Blender's work).
POST = {
    3: dict(sat=1.16, contrast=1.04),
    4: dict(outline=4),
    5: dict(lift=14, contrast=0.9),
    6: dict(tint=(1.05, 0.98, 0.92), shadow=(0.03, 0.0, 0.08)),
    9: dict(pixel=2, quant='E32', dither=0.30),
}
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 15.0


def grade(rgb, p):
    x = rgb.astype(np.float32)
    lum = (x * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    if 'sat' in p:
        x = lum + (x - lum) * p['sat']
    if 'contrast' in p:
        x = (x - 128) * p['contrast'] + 128
    if 'lift' in p:
        x = x + p['lift']
    if 'tint' in p:
        x = x * np.array(p['tint'])
    if 'shadow' in p:
        x = x + (1 - lum / 255.0) * np.array(p['shadow']) * 255
    return np.clip(x, 0, 255)


def outline(img, r):
    a = np.array(img)
    rgb, al = a[..., :3].astype(np.float32), a[..., 3]
    solid = al > 128
    out_rgb, out_a = rgb.copy(), solid.copy()
    pad = np.pad(solid, r)
    prgb = np.pad(rgb, ((r, r), (r, r), (0, 0)))
    h, w = solid.shape
    best = np.zeros((h, w), bool)
    col = np.zeros((h, w, 3), np.float32)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx == 0 and dy == 0:
                continue
            nb = pad[r + dy:r + dy + h, r + dx:r + dx + w]
            nc = prgb[r + dy:r + dy + h, r + dx:r + dx + w]
            take = nb & ~best
            col[take] = nc[take]
            best |= nb
    edge = best & ~solid
    ink = col * 0.30 + np.array([18, 10, 34]) * 0.7
    out_rgb[edge] = ink[edge]
    out_a = solid | edge
    # inner contour: darken where a solid pixel touches transparent space
    res = np.dstack([np.clip(out_rgb, 0, 255), np.where(out_a, 255, 0)]).astype(np.uint8)
    return Image.fromarray(res, 'RGBA')


def quant(rgb, pal, dither):
    pal = np.array([[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in pal], np.float32)
    h, w = rgb.shape[:2]
    t = (BAYER[np.arange(h)[:, None] % 4, np.arange(w)[None, :] % 4] - 0.5) * dither * 64
    x = rgb + t[..., None]
    d = ((x[:, :, None, :] - pal[None, None]) ** 2 * np.array([1, 1.2, 1])).sum(-1)
    return pal[d.argmin(-1)]


def process(src, dst, style, is_tile):
    p = POST.get(style, {})
    img = Image.open(src).convert('RGBA')
    if is_tile:
        # the shipped ground is a MIRRORED 2 x 2 swatch: seamless when repeated
        w, h = img.size
        m = Image.new('RGBA', (w * 2, h * 2))
        m.paste(img, (0, 0))
        m.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
        m.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
        m.paste(img.transpose(Image.ROTATE_180), (w, h))
        img = m
    if p.get('pixel'):
        k = p['pixel']
        img = img.resize((max(1, img.width // k), max(1, img.height // k)), Image.BOX)
    a = np.array(img)
    rgb, al = a[..., :3].astype(np.float32), a[..., 3]
    rgb = grade(rgb, p) if p else rgb
    if p.get('quant'):
        rgb = quant(rgb, E32, p.get('dither', 0))
    if p.get('pixel') or p.get('quant'):
        al = np.where(al > 128, 255, 0)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), al]).astype(np.uint8), 'RGBA')
    if p.get('outline') and not is_tile:
        img = outline(img, p['outline'])
    img.save(dst, optimize=True)


# ── "ohne Blender": the SHIPPED assets, restyled by this pass alone ──────────
# A median filter flattens the photo textures towards flat colour; the rest is
# colour work. This is what a Flutter shader / an offline PIL step can do to the
# assets that already exist.
NB = {
    1: dict(median=5, sat=1.30, contrast=1.05),
    2: dict(median=3, sat=1.34, contrast=1.05),
    3: dict(sat=1.16, contrast=1.04),
    4: dict(median=5, sat=1.12, outline=4),
    5: dict(median=5, sat=0.72, lift=22, contrast=0.9),
    6: dict(median=5, sat=1.25, tint=(1.07, 0.97, 0.88), shadow=(0.03, 0.0, 0.09)),
    7: dict(median=5, sat=1.05, tint=(0.42, 0.55, 0.95), lift=6),
    8: dict(median=5, sat=1.3, autumn=True),
    9: dict(median=5, sat=1.25, pixel=3, quant='E32', dither=0.3),
    10: dict(median=3, sat=1.5, contrast=1.08),
}
NB_SRC = {   # lab name -> shipped file
    'small_house': 'buildings/small_house.webp', 'large_house': 'buildings/large_house.webp',
    'small_wood_camp': 'buildings/small_wood_camp.webp', 'storehouse': 'buildings/storehouse.webp',
    'healing_hut': 'buildings/healing_hut.webp',
    'grass_tile': 'terrain/grass_tile.webp', 'water_tile': 'terrain/water_tile.webp',
    'sand_tile': 'terrain/sand_tile.webp',
    'prop_tree_conifer': 'terrain/prop_conifer_m.webp', 'prop_tree_broadleaf': 'terrain/prop_broadleaf_m.webp',
    'prop_stone': 'terrain/prop_stone_a.webp',
}


def autumn(rgb):
    import colorsys
    flat = rgb.reshape(-1, 3) / 255.0
    out = np.empty_like(flat)
    for i, (r, g, b) in enumerate(flat):
        h, s_, v = colorsys.rgb_to_hsv(r, g, b)
        if 0.17 < h < 0.46 and s_ > 0.25:
            h = 0.04 + 0.08 * (1 - (h - 0.17) / 0.29)
        out[i] = colorsys.hsv_to_rgb(h, s_, v)
    return (out * 255).reshape(rgb.shape)


def process_nb(src, dst, style, size, is_tile):
    from PIL import ImageFilter
    p = NB[style]
    img = Image.open(src).convert('RGBA')
    if is_tile:
        img = img.resize(size, Image.LANCZOS)
    else:
        k = size[0] / img.width
        img = img.resize((size[0], max(1, round(img.height * k))), Image.LANCZOS)
    if p.get('median'):
        al = img.getchannel('A')
        img = img.convert('RGB').filter(ImageFilter.MedianFilter(p['median'])).convert('RGBA')
        img.putalpha(al)
    if p.get('pixel'):
        k = p['pixel']
        img = img.resize((max(1, img.width // k), max(1, img.height // k)), Image.BOX)
    a = np.array(img)
    rgb, al = a[..., :3].astype(np.float32), a[..., 3]
    if p.get('autumn'):
        rgb = autumn(rgb)
    rgb = grade(rgb, p)
    if p.get('quant'):
        rgb = quant(rgb, E32, p.get('dither', 0))
    if p.get('pixel') or p.get('quant'):
        al = np.where(al > 128, 255, 0)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), al]).astype(np.uint8), 'RGBA')
    if p.get('outline') and not is_tile:
        img = outline(img, p['outline'])
    img.save(dst, optimize=True)


def main_nb():
    """py style_post.py --nb <assets dir> <lab dir (for target sizes)> <out dir>"""
    assets, lab, dst = sys.argv[2], sys.argv[3], sys.argv[4]
    only = os.environ.get('ONLY')
    for n in range(1, 11):
        if only and str(n) not in only.split(','):
            continue
        od = os.path.join(dst, f'n{n}')
        os.makedirs(od, exist_ok=True)
        for name, rel in NB_SRC.items():
            ref = os.path.join(lab, 's1', name + '.png')
            if not os.path.exists(ref):
                ref = os.path.join(lab, 's3', name + '.png')
            tile = name.endswith('_tile')
            size = Image.open(ref).size
            if tile:
                size = (size[0] * 2, size[1] * 2)
            process_nb(os.path.join(assets, rel), os.path.join(od, name + '.png'), n, size, tile)
        print('nb', n, flush=True)


def main():
    if sys.argv[1] == '--nb':
        return main_nb()
    src, dst = sys.argv[1], sys.argv[2]
    meta = {}
    only = os.environ.get('ONLY')
    for sd in sorted(glob.glob(os.path.join(src, 's*'))):
        n = int(os.path.basename(sd)[1:])
        if only and str(n) not in only.split(','):
            continue
        od = os.path.join(dst, f's{n}')
        os.makedirs(od, exist_ok=True)
        for f in sorted(glob.glob(os.path.join(sd, '*.png'))):
            base = os.path.basename(f)
            if base.endswith('_raw.png'):
                continue
            process(f, os.path.join(od, base), n, base.endswith('_tile.png'))
        for f in glob.glob(os.path.join(sd, '*.json')):
            meta.setdefault(str(n), {})[os.path.basename(f)[:-5]] = json.load(open(f))
        print('post', n, flush=True)
    json.dump(meta, open(os.path.join(dst, 'meta.json'), 'w'))


if __name__ == '__main__':
    main()
