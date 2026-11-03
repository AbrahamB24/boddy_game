"""Collision audit for one Fachwerk building: what stands inside what.

    blender --background --python tool/blender/audit.py -- <id>

Every object is labelled with the helper that made it (barrel#3, bench#1,
window#7, ...; the walls and plinths built directly in build() are 'body').
Then two lists are printed:

  PROP IN BODY   a yard prop whose box reaches more than a voxel into the
                 house's own volume (a barrel standing in a wall)
  PROP IN PROP   two different props overlapping (a sack inside a crate)

Boxes are world-space bounds of the actual vertices, so a rotated part is a
little generous; every hit is a place to LOOK at, not a verdict.
"""
import importlib
import itertools
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fw_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402

PROPS = {'barrel', 'sack', 'crate', 'bush', 'hay_bale', 'nest', 'egg', 'hen',
         'bench', 'woodpile', 'cat', 'washing_line', 'fence', 'veg_bed',
         'flower_patch', 'lantern', 'cobble_path', 'hay_scatter'}
WRAP = PROPS | {'window', 'door', 'wall_frame', 'gable_wall', 'gable_roof',
                'chimney', 'hanging_sign'}

_stack = []
_count = {}


def wrap(mod, name):
    fn = getattr(mod, name, None)
    if fn is None or getattr(fn, '_audited', False):
        return

    def w(*a, **k):
        if _stack:
            return fn(*a, **k)
        _count[name] = _count.get(name, 0) + 1
        label = f'{name}#{_count[name]}'
        _stack.append(label)
        before = set(bpy.data.objects)
        try:
            return fn(*a, **k)
        finally:
            _stack.pop()
            for o in bpy.data.objects:
                if o not in before:
                    o['part'] = label
    w._audited = True
    setattr(mod, name, w)


def bounds(o):
    mw = o.matrix_world
    vs = [mw @ v.co for v in o.data.vertices]
    return ([min(v[i] for v in vs) for i in range(3)],
            [max(v[i] for v in vs) for i in range(3)])


def overlap(a, b):
    return [max(0.0, min(a[1][i], b[1][i]) - max(a[0][i], b[0][i])) for i in range(3)]


def main():
    bid = sys.argv[sys.argv.index('--') + 1:][0]
    mod = importlib.import_module('buildings.' + bid)
    for name in WRAP:
        wrap(fw_kit, name)
        wrap(mod, name)
    rb.clear()
    K._mats.clear()
    fw_kit.reset_anims()
    mod.build()
    bpy.context.view_layer.update()
    V = fw_kit.VOX
    objs = [o for o in bpy.data.objects if o.type == 'MESH' and o.data.vertices]
    body = [o for o in objs if 'part' not in o.keys()
            and o.data.materials and o.data.materials[0].name in
            ('plaster', 'stone', 'stone_dk')]
    props = {}
    for o in objs:
        p = o.get('part', '')
        if p.split('#')[0] in PROPS:
            props.setdefault(p, []).append(o)
    pb = {p: [bounds(o) for o in obs] for p, obs in props.items()}
    bb = [(o, bounds(o)) for o in body]

    print('== PROP IN BODY')
    for p, boxes in sorted(pb.items()):
        if p.startswith(('cobble_path', 'lantern', 'hay_scatter')):
            continue
        worst = 0.0
        for b in boxes:
            for o, ob in bb:
                ov = overlap(b, ob)
                worst = max(worst, min(ov))
        if worst > V:
            print(f'  {p:22s} reaches {worst / V:4.1f} voxels into the house')

    print('== PROP IN PROP')
    keys = sorted(pb)
    for a, b in itertools.combinations(keys, 2):
        if a.split('#')[0] == 'cobble_path' or b.split('#')[0] == 'cobble_path':
            continue
        worst = 0.0
        for x in pb[a]:
            for y in pb[b]:
                worst = max(worst, min(overlap(x, y)))
        if worst > V:
            print(f'  {a:22s} x {b:22s} {worst / V:4.1f} voxels')

    print('== PATH ON PROP')
    paths = [k for k in keys if k.startswith('cobble_path')]
    for pth in paths:
        for k in keys:
            if k.startswith(('cobble_path', 'fence', 'veg_bed', 'flower_patch',
                             'washing_line', 'hay_scatter')):
                continue
            worst = 0.0
            for x in pb[pth]:
                for y in pb[k]:
                    worst = max(worst, min(overlap(x, y)[:2]))
            if worst > 2 * V:
                print(f'  {k:22s} stands on the path ({worst / V:.1f} vox)')


main()
