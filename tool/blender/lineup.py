"""Proportion check: several Fachwerk buildings side by side, same camera.

    blender --background --python tool/blender/lineup.py -- hatchery small_house \
        --out tool/blender/_out/lineup.png [--voxel] [--samples 24]

Each building stands on its own footprint along the camera's screen-right
axis, with a 1.8 m reference figure (fw_kit.person) at its front corner.
Doors, windows and storeys must line up across the row: a door that comes
out taller than the figure's head, or a storey that is higher on one house
than the next, is caught here rather than on the map.
"""
import argparse
import importlib
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fw_kit  # noqa: E402
import make_building as mb  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='+')
    ap.add_argument('--out', default=os.path.join(HERE, '_out', 'lineup.png'))
    ap.add_argument('--voxel', action='store_true')
    ap.add_argument('--samples', type=int, default=24)
    ap.add_argument('--scale', type=int, default=3)
    args = ap.parse_args(argv)

    rb.clear()
    K._mats.clear()
    ux, uy = math.cos(math.radians(45)), math.sin(math.radians(45))
    d = 0.0
    prev = None
    for bid in args.ids:
        mod = importlib.import_module('buildings.' + bid)
        ext = (mod.W + mod.H) / math.sqrt(2)
        if prev is not None:
            d += (prev + ext) / 2 + 0.6
        prev = ext
        before = set(bpy.data.objects)
        mod.build()
        fw_kit.person(K._mats, mod.W / 2 + 0.12, -mod.H / 2 - 0.12)
        for ob in set(bpy.data.objects) - before:
            if ob.parent is None:
                ob.location.x += ux * d
                ob.location.y += uy * d
    mb.lower_to_yard()
    if args.voxel:
        mb.voxelize('lineup')
    K.lighting()
    K.setup_render(args.samples, args.scale, 1, 1)
    K.render(args.out)


if __name__ == '__main__':
    main()
