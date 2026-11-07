"""Pack docs/renders/ui/globe_0..23.png into assets/images/ui/globe.webp (6 x 4).

    blender --background --python tool/blender/globe_sheet.py

make_ui4.py renders the frames (globe_N pieces); this sheet is what the compass
button spins. The per-frame webp files make_ui4 ships are deleted afterwards.
"""
import os

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'docs', 'renders', 'ui')
OUT = os.path.join(ROOT, 'assets', 'images', 'ui')
COLS, ROWS = 8, 6

frames = []
for i in range(COLS * ROWS):
    img = bpy.data.images.load(os.path.join(SRC, 'globe_%d.png' % i))
    w, h = img.size
    frames.append(np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4))
fh, fw = frames[0].shape[:2]
sheet = np.zeros((fh * ROWS, fw * COLS, 4), dtype=np.float32)
for i, f in enumerate(frames):
    r, c = divmod(i, COLS)
    # Blender's rows run bottom-up: row 0 of the sheet is its TOP.
    y0 = (ROWS - 1 - r) * fh
    sheet[y0:y0 + fh, c * fw:(c + 1) * fw] = f
out = bpy.data.images.new('globe_sheet', fw * COLS, fh * ROWS, alpha=True)
out.pixels = sheet.ravel().tolist()
sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
out.file_format = 'WEBP'
sc.render.image_settings.file_format = 'WEBP'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.image_settings.quality = 90
out.save_render(os.path.join(OUT, 'globe.webp'), scene=sc)
for i in range(COLS * ROWS):
    p = os.path.join(OUT, 'globe_%d.webp' % i)
    if os.path.exists(p):
        os.remove(p)
print('SHEET', fw * COLS, 'x', fh * ROWS)
