"""Mirror a swatch into a seamless 2x2 super-tile (Flutter's ImageShader tiles
plainly, so a non-seamless swatch would show a seam at every edge).
    blender --background --python tool/blender/mirror_tile.py -- in.png out.png
"""
import sys
import bpy
import numpy as np
src, dst = sys.argv[sys.argv.index('--') + 1:][:2]
im = bpy.data.images.load(src)
im.colorspace_settings.name = 'Non-Color'
w, h = im.size
a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
top = np.concatenate([a, a[:, ::-1]], axis=1)
full = np.concatenate([top, top[::-1]], axis=0)
out = bpy.data.images.new('m', w * 2, h * 2, alpha=True)
out.colorspace_settings.name = 'Non-Color'
out.pixels = full.ravel().tolist()
out.file_format = 'PNG'
out.filepath_raw = dst
out.save()
