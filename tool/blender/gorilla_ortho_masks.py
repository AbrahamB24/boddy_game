"""Cut the four orthographic views (front, back, side, top) of one gorilla stage out of the user's 2x2 sheet and write mask previews.

    blender --background --python tool/blender/gorilla_ortho_masks.py -- <sheet.png> <out dir> <stage 0..2>
"""
import os
import sys
from collections import deque

import bpy
import numpy as np

sheet, out, stage = sys.argv[sys.argv.index('--') + 1:][:3]
stage = int(stage)
os.makedirs(out, exist_ok=True)

# (x0, y0, x1, y1) panel windows in the 1024x1024 sheet, label text excluded. Order: front, back, side, top
PANELS = {
    0: [(15, 15, 505, 478), (520, 15, 1010, 478), (15, 530, 505, 980), (520, 530, 1010, 980)],
    1: [(15, 65, 505, 500), (520, 65, 1010, 500), (15, 575, 505, 1010), (520, 580, 1010, 1010)],
    2: [(15, 62, 505, 505), (520, 62, 1010, 505), (15, 575, 505, 1010), (520, 575, 1010, 1010)],
}
NAMES = ['front', 'back', 'side', 'top']


def load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3] * 255.0
    return a


def largest_component(m):
    h, w = m.shape
    seen = np.zeros_like(m)
    best = None
    for y in range(h):
        for x in range(w):
            if m[y, x] and not seen[y, x]:
                comp = []
                dq = deque([(y, x)])
                seen[y, x] = True
                while dq:
                    cy, cx = dq.popleft()
                    comp.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
                if best is None or len(comp) > len(best):
                    best = comp
    r = np.zeros_like(m)
    for cy, cx in best:
        r[cy, cx] = True
    return r


def fill_outside(m):
    o = np.zeros_like(m)
    o[0, :] = ~m[0, :]
    o[-1, :] = ~m[-1, :]
    o[:, 0] = ~m[:, 0]
    o[:, -1] = ~m[:, -1]
    for _ in range(600):
        n = o.copy()
        n[1:, :] |= o[:-1, :]
        n[:-1, :] |= o[1:, :]
        n[:, 1:] |= o[:, :-1]
        n[:, :-1] |= o[:, 1:]
        n &= ~m
        if (n == o).all():
            break
        o = n
    return ~o


def mask_of(reg, thr):
    bg = np.median(np.concatenate([reg[:5].reshape(-1, 3), reg[-5:].reshape(-1, 3), reg[:, :5].reshape(-1, 3), reg[:, -5:].reshape(-1, 3)]), axis=0)
    # blur a little to ignore bg grain
    k = reg.copy()
    for ax in (0, 1):
        k = (np.roll(k, 1, ax) + k + np.roll(k, -1, ax)) / 3.0
    d = np.sqrt(((k - bg) ** 2).sum(axis=2))
    chroma = k.max(axis=2) - k.min(axis=2)                       # bg is neutral gray, fur has a slight purple tint
    m = (d > thr) | (chroma > 5.5)
    m = largest_component(m)
    m = fill_outside(m)
    return m, bg


if __name__ == '__main__':
    px = load(sheet)
    for i, (x0, y0, x1, y1) in enumerate(PANELS[stage]):
        reg = px[y0:y1, x0:x1]
        m, bg = mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
        ys, xs = np.where(m)
        print(NAMES[i], 'bg', bg.round(), 'bbox', int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()), 'fill', round(float(m.mean()), 3))
        vis = np.zeros((reg.shape[0], reg.shape[1], 4), np.float32)
        vis[..., :3] = np.where(m[..., None], reg / 255.0, 0.0)
        vis[..., 3] = 1.0
        o = bpy.data.images.new('m', reg.shape[1], reg.shape[0], alpha=True)
        o.pixels = vis[::-1].reshape(-1)
        o.filepath_raw = os.path.join(out, 'omask_s%d_%s.png' % (stage, NAMES[i]))
        o.file_format = 'PNG'
        o.save()
