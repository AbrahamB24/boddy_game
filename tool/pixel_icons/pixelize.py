"""Turn the 3D-rendered icon set into 24x24 pixel art in the new style:
area-downsampled, palette-limited, hue-shifted dark coloured outline, own shadow."""
import colorsys, os, sys, glob
from PIL import Image, ImageEnhance

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'docs', 'renders', 'icons')  # 3D renders: make_icons.py --voxel 0
N = 24
CONTENT = 20


def shade(rgb, dv, dh=-0.05, ds=0.1):
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + dh) % 1; s = min(1, s + ds); v = max(0, min(1, v * dv))
    return tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))


def pixelize(path, colors=9):
    im = Image.open(path).convert('RGBA')
    bb = im.getbbox()
    if not bb: return Image.new('RGBA', (N, N))
    im = im.crop(bb)
    s = max(im.size)
    sq = Image.new('RGBA', (s, s), (0, 0, 0, 0)); sq.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    # premultiplied-ish resize so edges do not bleed dark
    small = sq.resize((CONTENT, CONTENT), Image.BOX)
    a = small.split()[3].point(lambda v: 255 if v > 110 else 0)
    rgb = small.convert('RGB')
    rgb = ImageEnhance.Color(rgb).enhance(1.25)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB')
    out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    off = (N - CONTENT) // 2
    P = out.load(); Q = q.load(); A = a.load()
    filled = {}
    for y in range(CONTENT):
        for x in range(CONTENT):
            if A[x, y]:
                filled[(x + off, y + off - 1)] = Q[x, y]
    # outline
    ol = {}
    for (x, y), c in filled.items():
        for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
            p = (x + dx, y + dy)
            if p not in filled and 0 <= p[0] < N and 0 <= p[1] < N:
                ol.setdefault(p, c)
    # shadow
    ys = [y for (_, y) in filled]; xs = [x for (x, _) in filled]
    sh = {}
    if ys:
        gy = max(ys) + 2
        for x in range(min(xs) + 2, max(xs)):
            for yy in (gy, gy + 1):
                if 0 <= yy < N and (x, yy) not in filled and (x, yy) not in ol:
                    sh[(x, yy)] = (20, 14, 40, 90 if yy == gy else 55)
    for p, c in sh.items(): P[p] = c
    for p, c in ol.items(): P[p] = shade(c, 0.32, -0.06, 0.12) + (255,)
    for p, c in filled.items(): P[p] = c + (255,)
    return out


if __name__ == '__main__':
    keys = sys.argv[1:] or ['alembic', 'axe', 'bank', 'beaver', 'book', 'brick', 'cart', 'castle', 'crown', 'fox', 'gem', 'heart', 'horse', 'shield', 'sword', 'swords', 'tent', 'tree', 'trophy', 'wand']
    S = Image.new('RGBA', (10 * 104, 2 * 104), (30, 78, 98, 255))
    for i, k in enumerate(keys):
        px = pixelize(os.path.join(SRC, k + '.webp'))
        big = px.resize((96, 96), Image.NEAREST)
        S.paste(big, ((i % 10) * 104 + 4, (i // 10) * 104 + 4), big)
    S.save('pixelize_test.png')
