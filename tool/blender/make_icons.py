"""Render the whole game icon set in 3D.

    blender --background --python tool/blender/make_icons.py -- [keys...|--all]
        [--samples 48] [--px 320] [--out 160] [--no-ship]

Each key is a function in tool/blender/icons3d_*.py. Writes docs/renders/icons/<key>.png
(archive) and, unless --no-ship, assets/images/icons/<key>.webp at --out px.
"""
import argparse
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import icon_lib as L  # noqa: E402
import icons3d_a  # noqa: E402,F401
import icons3d_b  # noqa: E402,F401
import icons3d_c  # noqa: E402,F401
import icons3d_d  # noqa: E402,F401


def ship(png, dst, size):
    sc = bpy.context.scene
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    img = bpy.data.images.load(png)
    img.scale(size, size)
    st = sc.render.image_settings
    st.file_format = 'WEBP'
    st.color_mode = 'RGBA'
    st.quality = 90
    img.save_render(dst, scene=sc)
    bpy.data.images.remove(img)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('keys', nargs='*')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--samples', type=int, default=48)
    ap.add_argument('--px', type=int, default=320)
    ap.add_argument('--out', type=int, default=160)
    ap.add_argument('--voxel', type=int, default=0, help='blocks across the longest side (0 = smooth)')
    ap.add_argument('--no-ship', action='store_true')
    ap.add_argument('--ship-new', action='store_true', help='also ship keys without an existing asset')
    args = ap.parse_args(argv)
    L.VOXELS['n'] = args.voxel
    keys = L.ORDER if args.all else args.keys
    os.makedirs(os.path.join(ROOT, 'docs', 'renders', 'icons'), exist_ok=True)
    for k in keys:
        if k not in L.REG:
            print('NO ICON', k)
            continue
        png = os.path.join(ROOT, 'docs', 'renders', 'icons', k + '.png')
        try:
            L.render_icon(k, png, args.samples, args.px)
        except Exception as e:  # keep going: one bad icon must not stop the set
            print('ICON FAILED', k, repr(e))
            continue
        dest = os.path.join(ROOT, 'assets', 'images', 'icons', k + '.webp')
        # Only icons the game already names are shipped; the others stay archive renders.
        if not args.no_ship and (os.path.exists(dest) or args.ship_new):
            ship(png, dest, args.out)
        print('ICON OK', k)


if __name__ == '__main__':
    main()
