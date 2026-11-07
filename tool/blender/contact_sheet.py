"""Lay rendered icon PNGs out in one picture: blender -b -P contact_sheet.py -- out.png key1 key2 ..."""
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
argv = sys.argv[sys.argv.index('--') + 1:]
out, keys = argv[0], argv[1:]
cell, cols = 200, 6
rows = (len(keys) + cols - 1) // cols
W, H = cols * cell, rows * cell
canvas = np.zeros((H, W, 4), dtype=np.float32)
canvas[:, :] = (0.30, 0.45, 0.20, 1.0)
for i, k in enumerate(keys):
    p = os.path.join(ROOT, 'docs', 'renders', 'icons', k + '.png')
    if not os.path.exists(p):
        continue
    img = bpy.data.images.load(p)
    img.scale(cell, cell)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(cell, cell, 4)
    a = px[:, :, 3:4]
    r, c = divmod(i, cols)
    y0 = H - (r + 1) * cell
    x0 = c * cell
    tile = canvas[y0:y0 + cell, x0:x0 + cell]
    tile[:] = px[:, :, :3].tolist() and np.concatenate([px[:, :, :3] * a + tile[:, :, :3] * (1 - a), np.ones((cell, cell, 1), dtype=np.float32)], axis=2)
    bpy.data.images.remove(img)
res = bpy.data.images.new('sheet', W, H, alpha=True)
res.pixels = canvas.ravel().tolist()
res.filepath_raw = out
res.file_format = 'PNG'
res.save()
