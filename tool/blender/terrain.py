"""The map's ground: grass, a river, a lake and mountains round the rim.

    blender --background --python tool/blender/terrain.py -- \
        --out assets/images/map_background.png

── What is in here and what is NOT ──
The terrain only. No trees.

That split is the whole design, and it comes straight from what the ground has
to DO: "wenn ich die Fläche freischalte, wird gerodet und die Fläche wird frei".
Anything that gets cleared has to exist as its own object the app can take
away, so trees are per-cell sprites (see the `tree` preset in
render_building.py) scattered over the locked ground and removed a region at a
time. Bake them in here and unlocking could only ever reveal a picture of a
forest that is still standing.

What IS in here is everything that never changes: water, rock, and the shape of
the land. A river is not cleared, it is built around.

── Size ──
The map is 60 x 40 cells and a cell is 64 x 32 px, so the diamond that holds it
is (60 + 40) x 32 = 3200 px across and half that tall. That is exactly
isoCanvasSize in iso_grid.dart, and the frame is solved from the grid the same
way a building's is — so the picture cannot drift from the map it is under.
"""
import argparse
import importlib.util
import math
import os
import sys

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'render_building', os.path.join(_HERE, 'render_building.py'))
rb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rb)

# iso_grid.dart's own numbers. Wrong here means a background that slides under
# its own buildings.
COLS, ROWS = 60, 40

TERRAIN = {
    'grass': (0.36, 0.55, 0.26),
    'grass_dry': (0.52, 0.60, 0.28),
    'grass_dark': (0.26, 0.44, 0.21),
    'water': (0.20, 0.48, 0.68),
    'water_deep': (0.13, 0.34, 0.55),
    'shore': (0.74, 0.68, 0.46),
    'rock': (0.52, 0.50, 0.50),
    'rock_dark': (0.38, 0.37, 0.38),
    'snow': (0.92, 0.93, 0.95),
}


def tmat(key):
    if key not in rb._MATS:
        rb._MATS[key] = rb.flat(key, TERRAIN[key])
    return rb._MATS[key]


def slab(name, x, y, w, d, z, h, key):
    """Ground is drawn as flat slabs at slightly different heights, so the
    edges between them are real geometry catching real light rather than a
    painted line. A painted boundary reads as a texture; a step reads as a
    bank."""
    return rb.box(name, x, y, z, w, d, h, tmat(key))


def mountains(name, count=26, key='rock'):
    """A ring of peaks OUTSIDE the playable diamond.

    They are scenery in the strict sense: the player can never reach them, and
    their only job is to close the horizon so the map ends in something rather
    than in nothing. Set beyond the grid's own corners, so nothing buildable is
    ever in their shadow.
    """
    cx, cy = 0.0, 0.0
    rx, ry = COLS * 0.62, ROWS * 0.72
    for i in range(count):
        a = 2 * math.pi * i / count
        # Pushed out along the diamond rather than a circle: the map is not
        # round, and a round ring of hills round a diamond leaves gaps at the
        # corners and crowds the sides.
        x = cx + rx * math.cos(a)
        y = cy + ry * math.sin(a)
        hgt = 5.0 + 4.5 * (0.5 + 0.5 * math.sin(a * 3.1 + 1.2))
        w = 5.5 + 3.0 * (0.5 + 0.5 * math.cos(a * 2.3))
        bpy.ops.mesh.primitive_cone_add(
            vertices=6, radius1=w, radius2=w * 0.06, depth=hgt,
            location=(x, y, hgt / 2 - 1.0))
        ob = bpy.context.object
        ob.name = f'{name}_{i}'
        ob.rotation_euler = (0, 0, a)
        ob.data.materials.append(tmat(key if i % 2 else 'rock_dark'))
        for p in ob.data.polygons:
            p.use_smooth = False
        if hgt > 7.4:
            bpy.ops.mesh.primitive_cone_add(
                vertices=6, radius1=w * 0.34, radius2=w * 0.05,
                depth=hgt * 0.3,
                location=(x, y, hgt - 1.0 - hgt * 0.14))
            cap = bpy.context.object
            cap.name = f'{name}_snow_{i}'
            cap.rotation_euler = (0, 0, a)
            cap.data.materials.append(tmat('snow'))
            for p in cap.data.polygons:
                p.use_smooth = False


def river(name):
    """A river across the map, and a lake it runs into.

    Laid as a chain of overlapping slabs rather than a curve: everything else
    in this world is faceted, and a smooth ribbon of water would be the one
    thing in the picture that is not. The bank is a second, wider chain
    underneath — sand showing at the edge is what makes water look like it is
    IN the ground rather than on it.
    """
    pts = []
    n = 26
    for i in range(n + 1):
        t = i / n
        # A shallow S: two bends, so the river divides the map into buildable
        # pieces of different shapes instead of cutting it in half.
        x = COLS * (-0.42 + 0.84 * t)
        y = ROWS * (-0.20 + 0.26 * math.sin(t * math.pi * 1.6 + 0.4))
        pts.append((x, y, 2.4 + 0.8 * math.sin(t * 5)))
    for i, (x, y, w) in enumerate(pts):
        slab(f'{name}_bank{i}', x, y, w + 1.5, w + 1.5, -0.14, 0.16, 'shore')
    for i, (x, y, w) in enumerate(pts):
        slab(f'{name}_{i}', x, y, w, w, -0.06, 0.14, 'water')

    # The lake, at the end the river runs to.
    lx, ly = COLS * 0.30, ROWS * 0.16
    slab(f'{name}_lakebank', lx, ly, 17.0, 13.0, -0.14, 0.16, 'shore')
    slab(f'{name}_lake', lx, ly, 15.0, 11.0, -0.06, 0.14, 'water')
    slab(f'{name}_lakedeep', lx, ly, 9.5, 6.5, -0.02, 0.12, 'water_deep')


def meadow(name, count=90):
    """Patches of a slightly different green over the base grass.

    Flat green over 3200 px is the same failure as a flat roof: the eye needs
    a break in a surface that large. Deterministic, spread by the golden angle,
    and only two tones — more and it stops reading as grass.
    """
    cx, cy = 0.0, 0.0
    for i in range(count):
        a = 2.399963 * i
        r = math.sqrt((i + 0.5) / count)
        x = cx + math.cos(a) * r * COLS * 0.56
        y = cy + math.sin(a) * r * ROWS * 0.56
        s = 2.2 + 3.4 * ((i * 7) % 5) / 4
        slab(f'{name}_{i}', x, y, s, s * 0.8, -0.2,
             0.1, 'grass_dry' if i % 3 else 'grass_dark')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='assets/images/map_background.png')
    ap.add_argument('--scale', type=int, default=1)
    args = ap.parse_args(argv)

    rb.clear()
    # The base: one slab covering the whole grid and well past it, so the
    # diamond never shows an edge where the ground simply stops.
    slab('ground', 0, 0, COLS * 1.9, ROWS * 2.4, -0.3, 0.3,
         'grass')
    meadow('meadow')
    river('river')
    mountains('mts')

    rb.vary_tones(spread=0.05)
    rb.bevel_everything()
    rb.light()
    # Framed on the GRID, exactly as a building is framed on its footprint —
    # which is what guarantees the picture lines up with iso_grid.dart instead
    # of merely looking as though it does.
    rb.frame(COLS, ROWS, args.scale, 0.5)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for e in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if e in engines:
            scene.render.engine = e
            break
    # OPAQUE: this is the ground, and everything else is drawn on top of it.
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
