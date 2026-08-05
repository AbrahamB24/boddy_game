"""Every building in one Blender file, standing in a row.

    blender --background --python tool/blender/all_buildings.py -- \
        --blend docs/renders/all_buildings.blend --out docs/renders/all.png

Open the .blend and the whole set is there at once, on one ground, under one
light. That is the only way to answer the question that actually matters as the
roster grows — do these look like they come from the same place? — and it is a
question no single render can answer, because every single render looks fine on
its own.

Each preset builds itself around the origin, so the layout works by BUILDING
ONE AND THEN MOVING IT: take a note of which objects exist, build, and shift
whatever is new into its slot. That way no preset has to know it is part of a
line-up, and adding one to PRESETS puts it in this file for free.
"""
import argparse
import importlib.util
import os
import sys

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'render_building', os.path.join(_HERE, 'render_building.py'))
rb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rb)

# How far apart the slots stand, in tiles. Wider than the widest footprint so
# nothing overlaps, tight enough that the row still reads as one set.
SPACING = 7.0


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--blend', default='docs/renders/all_buildings.blend')
    ap.add_argument('--out', help='also render an overview PNG')
    ap.add_argument('--scale', type=int, default=2)
    args = ap.parse_args(argv)

    rb.clear()
    names = sorted(rb.PRESETS)
    n = len(names)

    for i, name in enumerate(names):
        build, w, h = rb.PRESETS[name]
        before = set(bpy.data.objects)
        build(w, h)
        # ── The row runs along SCREEN X, and that is +x AND +y ──
        # Not the same convention as the Dart projection, which is the trap: in
        # iso_grid.dart +x goes down-right and +y down-LEFT, so screen-right is
        # (+x, −y). Under this Blender camera BOTH axes go right — their
        # horizontal parts add and their vertical parts cancel — so screen-right
        # is (+x, +y). Getting it backwards stacks the row vertically, which is
        # exactly what it did.
        d = (i - (n - 1) / 2) * SPACING
        made = [ob for ob in bpy.data.objects if ob not in before]
        for ob in made:
            ob.location.x += d
            ob.location.y += d
        # One collection per building, so the outliner is a list of BUILDINGS
        # rather than four thousand boxes. This is most of what makes the file
        # usable at all.
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
        for ob in made:
            for c in ob.users_collection:
                c.objects.unlink(ob)
            col.objects.link(ob)
        print(f'  {name}: {len(made)} objects at {d:+.1f}')

    rb.vary_tones()
    rb.bevel_everything()
    rb.light()
    # The row as one big footprint. It spreads the same distance along +x as
    # along −y, so the box that holds it is square and as wide as the whole
    # spread plus one building.
    span = int(n * SPACING) + 5
    rb.frame(span, span, args.scale, 0.62)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for e in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if e in engines:
            scene.render.engine = e
            break

    if args.out:
        scene.render.image_settings.file_format = 'PNG'
        scene.render.image_settings.color_mode = 'RGBA'
        scene.render.filepath = os.path.abspath(args.out)
        bpy.ops.render.render(write_still=True)
        print(f'wrote {args.out}')

    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    print(f'saved {args.blend} — {n} buildings')


main()
