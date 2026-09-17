"""Renders a small, tileable ground swatch at building-matching pixel
density -- the fix for the map background's resolution gap against the
buildings standing on it (user 2026-09-07, measured: ~22 px/world-unit for
the old single whole-map bake vs ~270 px/world-unit for a building — the
whole map in one image can never match that: doing so would need a
117760x58880 source). Instead of one enormous baked image, the app tiles
this small, sharp swatch as a repeating ground material — the same idea a
game engine's ground shader already is, and the same "small, sharp, reused"
idea the buildings themselves are built from.

    blender --background --python tool/blender/render_ground_tile.py -- \
        --key grass --size 2 --out docs/renders/grass_tile.png

Renders ONE tile; tool/pack_terrain_tile.py mirrors it into a seamless 2x2
super-tile and packs it to webp afterwards — Flutter's ImageShader only
tiles a texture PLAINLY (no built-in mirror-repeat), so a straight repeat of
a non-seamless swatch shows a visible seam at every edge. Mirroring is the
standard fix for that: any texture, seamless-authored or not, matches
itself exactly at a mirrored boundary.
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


def _terrain_palette():
    """Reads terrain.py's TERRAIN dict WITHOUT importing (and so running) the
    module — its own `main()` fires unconditionally at the bottom of the
    file, args parsed straight from sys.argv, and would re-render the whole
    map / overwrite water_cells.dart the moment the module loaded."""
    import ast
    path = os.path.join(_HERE, 'terrain.py')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    start = text.index('TERRAIN = {')
    end = text.index('\n}', start)
    return ast.literal_eval(text[start + len('TERRAIN = '):end + 2])


TERRAIN = _terrain_palette()


def tmat(key):
    """terrain.py's own tmat(), reimplemented against the dict read above
    instead of the live module — same flat()/grain machinery, just keyed
    off TERRAIN instead of render_building.py's PALETTE."""
    if key not in rb._MATS:
        rb._MATS[key] = rb.flat(key, TERRAIN[key])
    return rb._MATS[key]


def flat_plane(name, size, mat):
    """A single flat face, no side walls — unlike rb.box(), which is a full
    6-face box and renders visible vertical edges the moment its top isn't
    perfectly flush with the frame (exactly what happened on the first
    render here: a slab of boxes tiled into a grid of visible box edges,
    not a seamless ground). Sized much larger than the framed w×h area so
    the camera's whole view is filled by material with no edge anywhere in
    frame — a tileable ground has no boundary of its own to draw; the frame
    is what crops it to one tile's worth."""
    half = size / 2
    verts = [
        (-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0),
    ]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = False
    return ob


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--key', default='grass',
                    help='a PALETTE/FINISH key, e.g. grass, dirt, sand')
    ap.add_argument('--size', type=float, default=2.0,
                    help="the swatch's own size, in world units (tiles)")
    ap.add_argument('--scale', type=int, default=rb.SCALE,
                    help='same meaning as render_building.py\'s own SCALE — '
                         'the default already matches the buildings')
    ap.add_argument('--out', required=True)
    args = ap.parse_args(argv)

    rb.clear()
    w = h = args.size
    flat_plane('swatch', max(w, h) * 4, tmat(args.key))
    rb.light()
    # fit=False: EXACTLY the slab's own bounding box, no auto-grow headroom.
    # A flat tile has nothing rising above it to make room for — any extra
    # margin would just be dead space baked into the repeating pattern.
    # headroom=0.5 is the diamond's own NATURAL aspect (width = 2x height
    # for an equal-sided w=h patch, same maths as isoCanvasSize) — a taller
    # headroom would leave the same dead space this comment just ruled out.
    rb.frame(w, h, args.scale, 0.5, fit=False)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if eng in engines:
            scene.render.engine = eng
            break
    # OPAQUE: this tiles edge-to-edge with nothing meant to show through —
    # same reasoning as terrain.py's own whole-map ground render.
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
