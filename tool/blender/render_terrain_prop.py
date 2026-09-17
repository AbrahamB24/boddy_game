"""Renders ONE small, standalone map-detail prop as a transparent sprite —
the same "small, sharp, individually placed" idea render_ground_tile.py
gives the ground itself, but for the things that used to be baked INTO the
old whole-map background (flowers, stones, trees, dirt) and can't be baked
into a repeating tile (they must NOT repeat every tile, or the map reads as
a printed pattern instead of scattered detail).

    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop wildflower_heather --out docs/renders/prop_wildflower_heather.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop wildflower_gorse --out docs/renders/prop_wildflower_gorse.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop stone --out docs/renders/prop_stone.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop tree_conifer --out docs/renders/prop_tree_conifer.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop tree_broadleaf --out docs/renders/prop_tree_broadleaf.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop dirt_patch --out docs/renders/prop_dirt_patch.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop stone_flat --out docs/renders/prop_stone_flat.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop stone_boulder --out docs/renders/prop_stone_boulder.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop driftwood --out docs/renders/prop_driftwood.png
    blender --background --python tool/blender/render_terrain_prop.py -- \
        --prop shell --out docs/renders/prop_shell.png

stone_flat/stone_boulder (user 2026-09-14: "Die Steine bitte in
unterschiedlichen Grössen und Formen") are two more rock silhouettes
alongside the original stone, for outcrops/beach pebbles to pick from
instead of one shape rescaled. driftwood/shell (user 2026-09-14: "der
Strand soll noch Holz und kleine Muscheln haben") are new beach-only detail.

wildflower_heather/wildflower_gorse replace the earlier flower_bed prop
(user 2026-09-07: "das Blumenbeet durch einzelne Blumen ersetzen" — the
stone-edged garden box read fine bolted to a building, but scattered loose
across open grass it read as a planted garden, not wild growth). They port
terrain.py's own flowers() detail — heather/gorse, the two flower notes its
own palette already defines for exactly this — as two standalone single-
clump props instead of loose boxes scattered in place. stone is a small
rock built fresh here, matching terrain.py's own pebbles()/stone() shape and
materials. tree_conifer/tree_broadleaf port terrain.py's own tree() — the
"handful of boxes read as a silhouette" shape the old baked forest already
used — as two fixed, individually-placed instances instead of terrain.py's
per-instance random seed (user 2026-09-07: "Bäume als Scatterterrain").
dirt_patch is a flat, irregular bare-ground decal in the 'dirt' tone (user
2026-09-07: "Dreck/Erde").
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
    """See render_ground_tile.py's copy of this same function for why this
    reads terrain.py as text rather than importing it."""
    import ast
    path = os.path.join(_HERE, 'terrain.py')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    start = text.index('TERRAIN = {')
    end = text.index('\n}', start)
    return ast.literal_eval(text[start + len('TERRAIN = '):end + 2])


TERRAIN = _terrain_palette()


def tmat(key):
    if key not in rb._MATS:
        rb._MATS[key] = rb.flat(key, TERRAIN[key])
    return rb._MATS[key]


def _stone_small():
    """The original stone — same shape/material split terrain.py's own
    pebbles()/stone() scatter uses, just built here as one importable prop
    instead of many scattered-in-place instances. Kept as 'stone' (the id
    everything already references) so it stays the default/first variant —
    see stone_flat/stone_boulder for the others (user 2026-09-14: "Die
    Steine bitte in unterschiedlichen Grössen und Formen")."""
    rb.box('stone_a', 0, 0, 0, 0.5, 0.42, 0.24, tmat('rock'))
    ob = rb.box('stone_b', 0.14, -0.1, 0, 0.26, 0.24, 0.15, tmat('rock_dark'))
    ob.rotation_euler = (0, 0, 0.6)
    return 0.6, 0.6  # footprint (w, h) for frame()


def _stone_flat():
    """A wide, low slab — a beach pebble worn smooth and flat, not the same
    silhouette as the small stone just scaled."""
    rb.box('stone_a', 0, 0, 0, 0.62, 0.50, 0.14, tmat('rock'))
    ob = rb.box('stone_b', -0.14, 0.10, 0, 0.30, 0.26, 0.08, tmat('rock_dark'))
    ob.rotation_euler = (0, 0, -0.35)
    return 0.7, 0.62


def _stone_boulder():
    """A taller, chunkier boulder — three offset, staggered chunks (same
    trick as terrain.py's own boulder()) instead of two flat slabs, so it
    reads as a genuinely bigger, rougher rock, not just a scaled-up pebble."""
    rb.box('stone_a', 0, 0, 0, 0.38, 0.34, 0.32, tmat('rock'))
    ob = rb.box('stone_b', 0.17, 0.13, 0.16, 0.24, 0.22, 0.22, tmat('rock_dark'))
    ob.rotation_euler = (0, 0, 0.9)
    ob2 = rb.box('stone_c', -0.15, -0.11, 0.05, 0.20, 0.19, 0.16, tmat('rock'))
    ob2.rotation_euler = (0, 0, -0.5)
    return 0.58, 0.58


def _wildflower(tone):
    """One small flower clump, no bed or edging — terrain.py's own
    flowers() detail (a couple of staggered boxes in the 'heather'/'gorse'
    tone, its own palette's two flower notes), built here as a single
    standalone prop instead of a loose scatter of boxes."""
    rb.box('wf_a', 0, 0, 0, 0.34, 0.30, 0.22, tmat(tone))
    ob = rb.box('wf_b', 0.12, -0.08, 0, 0.22, 0.20, 0.16, tmat(tone))
    ob.rotation_euler = (0, 0, 0.5)
    return 0.5, 0.5  # footprint (w, h) for frame()


def _wildflower_heather():
    return _wildflower('heather')


def _wildflower_gorse():
    return _wildflower('gorse')


def _tree(shape):
    """Port of terrain.py's own tree(name, x, y, h, seed): a tapering stack
    reads as conifer, a fat double blob reads as broadleaf, and nothing finer
    survives the size this is drawn at. Fixed at one representative height
    and shape instead of terrain.py's per-instance random seed — there is no
    "one picture, many instances" here, just a single clean prop meant to be
    placed many times over."""
    h = 2.4
    rb.box('tree_t', 0, 0, 0.0, h * 0.13, h * 0.13, h * 0.44, tmat('trunk'))
    if shape == 'conifer':
        for i in range(3):
            f = 1.0 - i * 0.3
            tone = 'canopy' if i % 2 else 'canopy_light'
            rb.box(f'tree_c{i}', 0, 0, h * (0.32 + i * 0.24),
                   h * 0.62 * f, h * 0.62 * f, h * 0.3, tmat(tone))
    else:
        rb.box('tree_c0', 0, 0, h * 0.3, h * 0.76, h * 0.76, h * 0.44,
               tmat('canopy'))
        rb.box('tree_c1', 0, 0, h * 0.64, h * 0.5, h * 0.5, h * 0.32,
               tmat('canopy_dark'))
    return h * 0.8, h * 0.8  # footprint (w, h) for frame()


def _tree_conifer():
    return _tree('conifer')


def _tree_broadleaf():
    return _tree('broadleaf')


def _dirt_patch():
    """A small irregular bare-ground decal — three overlapping thin slabs in
    the 'dirt' tone, offset and rotated (same trick as terrain.py's own
    boulder()/stone(): a handful of staggered boxes reads as an irregular
    blotch, not a hard rectangle) — for worn ground, cart tracks, a bare
    patch among the grass."""
    rb.box('dirt_a', 0, 0, 0, 0.5, 0.34, 0.01, tmat('dirt'))
    ob = rb.box('dirt_b', 0.16, 0.1, 0, 0.32, 0.24, 0.01, tmat('dirt'))
    ob.rotation_euler = (0, 0, 0.5)
    ob2 = rb.box('dirt_c', -0.14, -0.08, 0, 0.28, 0.22, 0.01, tmat('dirt'))
    ob2.rotation_euler = (0, 0, -0.4)
    return 0.9, 0.7  # footprint (w, h) for frame()


def _driftwood():
    """A weathered branch washed up on the sand (user 2026-09-14: "der
    Strand soll noch Holz... haben") — two tapered, crossed pieces in the
    palette's shore tones (bleached pale, not the buildings' warm oak),
    which reads as driftwood rather than a felled log at this size."""
    ob = rb.box('wood_a', 0, 0, 0, 0.85, 0.16, 0.09, tmat('shore_wet'))
    ob.rotation_euler = (0, 0, 0.25)
    ob2 = rb.box('wood_b', 0.30, 0.16, 0, 0.26, 0.11, 0.07, tmat('shore'))
    ob2.rotation_euler = (0, 0, 0.85)
    return 0.9, 0.55


def _shell():
    """A small pale seashell (user 2026-09-14: "kleine Muscheln") — two
    shallow, offset slabs standing in for the ribbed fan shape at this
    size. 'foam', the palette's lightest cool tone, reads as bleached shell
    against the warm sand; 'shore_wet' gives it a shadowed underside."""
    rb.box('shell_a', 0, 0, 0, 0.22, 0.18, 0.06, tmat('foam'))
    ob = rb.box('shell_b', 0.02, -0.02, 0.02, 0.14, 0.11, 0.05, tmat('shore_wet'))
    ob.rotation_euler = (0, 0, 0.3)
    return 0.26, 0.24


PROPS = {
    'stone': _stone_small,
    'stone_flat': _stone_flat,
    'stone_boulder': _stone_boulder,
    'wildflower_heather': _wildflower_heather,
    'wildflower_gorse': _wildflower_gorse,
    'tree_conifer': _tree_conifer,
    'tree_broadleaf': _tree_broadleaf,
    'dirt_patch': _dirt_patch,
    'driftwood': _driftwood,
    'shell': _shell,
}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--prop', required=True, choices=sorted(PROPS))
    ap.add_argument('--scale', type=int, default=rb.SCALE)
    ap.add_argument('--headroom', type=float, default=1.1)
    ap.add_argument('--out', required=True)
    args = ap.parse_args(argv)

    rb.clear()
    w, h = PROPS[args.prop]()
    rb.light()
    rb.frame(w, h, args.scale, args.headroom, fit=True)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if eng in engines:
            scene.render.engine = eng
            break
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
