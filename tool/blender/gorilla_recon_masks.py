"""Test: cut the gorilla out of the user's sheet (per stage x view) and write mask previews.

    blender --background --python tool/blender/gorilla_recon_masks.py -- <sheet.jpg> <out dir>
"""
import os
import sys

import bpy
import numpy as np

sheet, out = sys.argv[sys.argv.index('--') + 1:][:2]
os.makedirs(out, exist_ok=True)
img = bpy.data.images.load(sheet)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3] * 255.0     # top-down rows, RGB 0..255
print('sheet', W, H, 'bg sample', px[300, 15], px[600, 700], 'fur sample', px[330, 150])

# (x0, y0, x1, y1) search windows (below the label text, inside the row separators)
ROWS = [(52, 245), (292, 500), (540, 766)]
COLS = {'front': (30, 280), 'q': (330, 580), 'side': (840, 1070), 'back': (1100, 1350)}
for si, (y0, y1) in enumerate(ROWS):
    for name, (x0, x1) in COLS.items():
        reg = px[y0:y1, x0:x1]
        bg = np.median(np.concatenate([reg[:6].reshape(-1, 3), reg[-6:].reshape(-1, 3)]), axis=0)
        d = np.sqrt(((reg - bg) ** 2).sum(axis=2))
        m = d > 14.0
        # remove tiny specks: keep pixels with >=3 of 8 neighbours set
        mm = m.astype(np.uint8)
        nb = sum(np.roll(np.roll(mm, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - mm
        m = m & (nb >= 3)
        ys, xs = np.where(m)
        print(si, name, 'bg', bg.round(), 'bbox', (xs.min(), ys.min(), xs.max(), ys.max()) if len(xs) else None, 'fill', round(m.mean(), 3))
        vis = np.zeros((reg.shape[0], reg.shape[1], 4), np.float32)
        vis[..., :3] = np.where(m[..., None], reg / 255.0, 0.0)
        vis[..., 3] = 1.0
        o = bpy.data.images.new('m', reg.shape[1], reg.shape[0], alpha=True)
        o.pixels = vis[::-1].reshape(-1)
        o.filepath_raw = os.path.join(out, 'mask_s%d_%s.png' % (si, name))
        o.file_format = 'PNG'
        o.save()
