"""Every road piece, one render each, named by the neighbours it joins.

    blender --background --python tool/blender/roads.py -- \
        --out docs/renders/roads
    python tool/pack_art.py "docs/renders/roads/*.png" assets/images/roads

Sixteen pictures, because a road cell has four neighbours and each is either a
road or it is not. The game does no compositing and no rotating: it counts its
neighbours, and that number IS the file name. See road_tiles.dart, which holds
the same bit order and must keep holding it.

── Why these are bundled assets and not image_url rows ──
Every other building carries one uploaded picture, and a road cannot: the whole
point is that it has sixteen. Roads are also not authored content — no levels,
no effects, no per-region variant — they are terrain, and terrain ships with the
app the way assets/images/map_background.png does.

── The framing has to be EXACT ──
headroom 0.5 makes the picture the tile's own bounding box, 2:1, with the
diamond's four corners on the four edges. Anything else and the tiles no longer
line up on the map, which for a road is the only thing that matters: a road that
is one pixel short is a road with a gap at every junction.
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


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    # Renders go to docs like every other one; tool/pack_art.py is what
    # puts the shippable .webp into assets (user 2026-08-12: the art has
    # grain now, and a palette PNG cannot hold grain).
    ap.add_argument('--out', default='docs/renders/roads',
                    help='directory to write road_NN.png into')
    ap.add_argument('--scale', type=int, default=rb.SCALE)
    ap.add_argument('--only', type=int, default=None,
                    help='render a single mask, for looking at one piece')
    args = ap.parse_args(argv)

    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    masks = [args.only] if args.only is not None else range(16)

    for mask in masks:
        rb.clear()
        rb.road_tile(mask)
        rb.vary_tones()
        rb.bevel_everything()
        rb.light()
        rb.frame(1, 1, args.scale, 0.5)

        scene = bpy.context.scene
        engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
        for e in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
            if e in engines:
                scene.render.engine = e
                break
        scene.render.image_settings.file_format = 'PNG'
        scene.render.image_settings.color_mode = 'RGBA'
        path = os.path.join(out, f'road_{mask:02d}.png')
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f'  road_{mask:02d}  {scene.render.resolution_x}x'
              f'{scene.render.resolution_y}')
    print(f'wrote {len(list(masks))} road tiles to {out}')


main()
