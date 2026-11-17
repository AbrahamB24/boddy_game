"""Halve every monster sprite sheet IN PLACE (the game decodes them at 0.5 anyway).

    blender --background --python tool/blender/halve_sheets.py -- assets/images/monsters [quality]

Why: MonsterSheets decode every sheet at decodeScale 0.5, but a WebP can only be
decoded at full size and scaled afterwards - a 4352 x 1740 idle sheet is 30 MB
of pixels to decode (and ~900 KB to download on web) just to keep 7.5 MB. Shipping
the half-size file makes that decode ~4x faster and the download ~3x smaller, and
the code needs no change: instantiateImageCodec(targetWidth: <the file's width>)
is a no-op and the painter derives its cell scale from the image's real width.

Idempotent: a sheet already <= 2300 px wide is left alone. Re-bake pipelines
that write full-size sheets just need this run once afterwards.
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index('--') + 1:]
root = os.path.abspath(argv[0])
quality = int(argv[1]) if len(argv) > 1 else 90

sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.image_settings.file_format = 'WEBP'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.image_settings.quality = quality

before = after = 0
for d, _, files in os.walk(root):
    for f in sorted(files):
        if not f.endswith('.webp'):
            continue
        p = os.path.join(d, f)
        img = bpy.data.images.load(p)
        w, h = img.size
        if w <= 2300:
            bpy.data.images.remove(img)
            continue
        size0 = os.path.getsize(p)
        img.scale(round(w / 2), round(h / 2))
        img.save_render(p, scene=sc)
        size1 = os.path.getsize(p)
        before += size0
        after += size1
        print('halved', p, f'{w}x{h}', size0, '->', size1)
        bpy.data.images.remove(img)
print('TOTAL', before, '->', after)
