"""Quantitative griffin check: silhouette + colour-class IoU of each render against the matching sheet crop.

    blender --background --python tool/blender/griffin_measure.py -- <render dir> <sheet jpg> [stages] [out png]

Each view is cut to its bbox and scaled to height H (aspect kept), centred on the bbox middle, bottom aligned.
Prints per view: aspect (w/h) ref vs render, silhouette IoU, cream/brown/yellow IoU, and the cream (head+bib)
bbox width/top as a fraction of the total height. Writes an overlay grid (red = sheet only, green = render only,
grey = both) so the misses are visible. Side views of sheet stages 1/2 face left (render is mirrored), stage 3 right.
"""
import os
import sys

import bpy
import numpy as np

H = 220
RECTS = {  # sheet px (x0, y0, x1, y1), y from the top
    0: {'front': (100, 55, 250, 232), 'q': (430, 55, 620, 232), 'side': (760, 55, 985, 232), 'back': (1130, 55, 1280, 232)},
    1: {'front': (78, 262, 272, 465), 'q': (405, 262, 632, 465), 'side': (735, 262, 1010, 465), 'back': (1100, 262, 1300, 465)},
    2: {'front': (8, 500, 342, 738), 'q': (352, 500, 652, 738), 'side': (692, 500, 1040, 738), 'back': (1048, 500, 1362, 738)},
}
FLIP_SIDE = {0: True, 1: True, 2: False}
VIEWS = ('front', 'q', 'side', 'back')


def load(p):
    im = bpy.data.images.load(p)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]  # top row first
    bpy.data.images.remove(im)
    if p.lower().endswith('.png'):
        # renders are linear-ish floats in [0,1] already displayed as sRGB bytes
        pass
    return a


def classes(rgb, mask):
    r, g, b = rgb[..., 0] * 255, rgb[..., 1] * 255, rgb[..., 2] * 255
    yellow = mask & (r > 165) & (g > 105) & (b < 95) & (r - b > 110)
    cream = mask & ~yellow & (r > 150) & (g > 128) & (b > 88) & (r - b < 95)
    brown = mask & ~yellow & ~cream & (r > g) & (g >= b - 8) & (r > 60)
    return cream, brown, yellow


def norm(mask, cls):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    # robust bbox: ignore stray specks (jpeg noise, label remnants) that would shift the centring
    x0, x1 = (int(v) for v in np.percentile(xs, (0.15, 99.85)))
    y0, y1 = (int(v) for v in np.percentile(ys, (0.15, 99.85)))
    x1, y1 = x1 + 1, y1 + 1
    keep = np.zeros_like(mask)
    keep[y0:y1, x0:x1] = True
    mask = mask & keep
    cls = [c & keep for c in cls]
    hh = y1 - y0
    k = H / hh
    W = 3 * H
    out = np.zeros((len(cls) + 1, H, W), bool)
    cx = (x0 + x1) / 2
    # nearest sampling of every output pixel
    oy, ox = np.mgrid[0:H, 0:W]
    sy = (y0 + (oy + .5) / k).astype(int)
    sx = (cx + (ox - W / 2 + .5) / k).astype(int)
    ok = (sy >= 0) & (sy < mask.shape[0]) & (sx >= 0) & (sx < mask.shape[1])
    syc, sxc = np.clip(sy, 0, mask.shape[0] - 1), np.clip(sx, 0, mask.shape[1] - 1)
    for i, m in enumerate([mask] + list(cls)):
        out[i] = m[syc, sxc] & ok
    return out, (x1 - x0) / hh


def iou(a, b):
    u = (a | b).sum()
    return (a & b).sum() / u if u else 1.0


def stats(n):
    m, cr = n[0], n[1]
    ys, xs = np.nonzero(cr)
    if len(ys) < 20:
        return (0, 0, 0)
    x0, x1 = np.percentile(xs, (2, 98))
    y0, y1 = np.percentile(ys, (1, 99))
    return ((x1 - x0) / H, y0 / H, y1 / H)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    d, sheet = argv[0], argv[1]
    stages = [int(s) for s in (argv[2] if len(argv) > 2 else '0,1,2').split(',')]
    outp = argv[3] if len(argv) > 3 else os.path.join(d, 'measure.png')
    sh = load(sheet)
    rgb = sh[..., :3]
    lum = rgb.max(axis=2) * 255
    sat = (rgb.max(axis=2) - rgb.min(axis=2)) * 255
    smask_all = (lum > 72) | (sat > 40) | ((rgb[..., 2] - rgb[..., 0]) * 255 > 18)   # last term: the navy eyes
    tiles = []
    tot = []
    for st in stages:
        row = []
        for v in VIEWS:
            x0, y0, x1, y1 = RECTS[st][v]
            m = smask_all[y0:y1, x0:x1].copy()
            # drop tiny specks (jpeg noise / label remnants): keep rows/cols with enough pixels
            c = rgb[y0:y1, x0:x1]
            refn = norm(m, classes(c, m))
            f = os.path.join(d, 'griffin_s%d_%s.png' % (st, v))
            if not os.path.exists(f) or refn is None:
                row.append(None)
                continue
            r = load(f)
            if v == 'q' or (v == 'side' and FLIP_SIDE[st]):
                r = r[:, ::-1]
            rm = r[..., 3] > .5
            rn = norm(rm, classes(r[..., :3], rm))
            (A, ar), (B, br) = refn, rn
            ious = [iou(A[i], B[i]) for i in range(4)]
            sa, sb = stats(A), stats(B)
            score = .4 * ious[0] + .25 * ious[1] + .25 * ious[2] + .1 * ious[3]
            tot.append(score)
            print('S%d %-5s aspect ref %.2f ren %.2f | IoU sil %.2f cream %.2f brown %.2f yellow %.2f | score %.2f'
                  ' | cream w %.2f/%.2f top %.2f/%.2f bot %.2f/%.2f' % (st, v, ar, br, *ious, score, sa[0], sb[0], sa[1], sb[1], sa[2], sb[2]))
            img = np.zeros((H, 3 * H, 4), np.float32)
            img[..., 3] = 1
            both, ro, rn_ = A[0] & B[0], A[0] & ~B[0], B[0] & ~A[0]
            img[both] = (.55, .55, .55, 1)
            img[ro] = (.9, .15, .15, 1)
            img[rn_] = (.15, .85, .2, 1)
            img[A[1] & B[1]] = (.95, .92, .8, 1)
            row.append(img)
        tiles.append(row)
    if tot:
        print('MEAN SCORE %.3f' % (sum(tot) / len(tot)))
    # grid
    th, tw_ = H, 3 * H
    grid = np.zeros((th * len(tiles), tw_ * 4, 4), np.float32)
    grid[..., 3] = 1
    for i, row in enumerate(tiles):
        for j, t in enumerate(row):
            if t is not None:
                grid[i * th:(i + 1) * th, j * tw_:(j + 1) * tw_] = t
    im = bpy.data.images.new('m', grid.shape[1], grid.shape[0])
    im.pixels[:] = grid[::-1].ravel()
    im.filepath_raw = outp
    im.file_format = 'PNG'
    im.save()


main()
