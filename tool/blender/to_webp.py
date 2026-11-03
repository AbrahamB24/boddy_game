"""Convert PNG sheets to WebP with Blender (no other image tool on this machine).

    blender --background --python tool/blender/to_webp.py -- <out_dir> <quality> <png> [<png> ...]

Colour management is pinned to Standard so no view transform touches the pixels,
and alpha stays straight; WebP keeps the transparent background the game needs.
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index('--') + 1:]
out_dir, quality, files = argv[0], int(argv[1]), argv[2:]
os.makedirs(out_dir, exist_ok=True)
sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.image_settings.file_format = 'WEBP'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.image_settings.quality = quality
for f in files:
    img = bpy.data.images.load(os.path.abspath(f))
    dst = os.path.join(out_dir, os.path.splitext(os.path.basename(f))[0] + '.webp')
    img.save_render(dst, scene=sc)
    print('webp', dst, os.path.getsize(dst))
    bpy.data.images.remove(img)
