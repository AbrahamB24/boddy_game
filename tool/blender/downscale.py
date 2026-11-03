"""Scale a PNG to a width (keeps aspect), for the 960 px app-art cap.
    blender --background --python tool/blender/downscale.py -- in.png out.png 960
"""
import sys
import bpy
src, dst, w = sys.argv[sys.argv.index('--') + 1:][:3]
w = int(w)
im = bpy.data.images.load(src)
iw, ih = im.size
im.scale(w, round(ih * w / iw))
im.file_format = 'PNG'
im.filepath_raw = dst
im.save()
