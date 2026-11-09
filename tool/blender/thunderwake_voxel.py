"""Thunderwake, three stages, as VOXELS in the Tidelord style (draft sprites).

    blender --background --python tool/blender/thunderwake_voxel.py -- \
        --stage 0 --out docs/renders/thunderwake_s0.png [--samples 64]

A towering brute, same recipe as monster_voxel.py: build the creature from smooth
primitives, flat colour per part, then turn it into one block mesh on a fixed
grid (block size is the same for every stage, so a bigger stage simply has
more blocks). Each block takes the colour of the nearest original surface.

stage 0 THUNDERWAKE  violet brute, single bolt horn
stage 1 THUNDERCREST bigger, deeper violet, a crest of bolts down the spine
stage 2 STORMLORD    biggest, near-midnight, storm-cloud cape, bolt crown
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
HALF, DEPTH = 2.0, 7          # 4.0 / 128 = 0.031 per block, like Tidelord stage 1/2

# stage 0 cuddly butter-yellow cub, 1 orange sprinter, 2 charcoal-violet titan
PAL = {
    0: dict(body='#f4c542', head='#f9d868', belly='#fff1cc', limb='#e39a2a',
            bolt='#9a6bff', boltd='#6f3fe0'),
    1: dict(body='#ea8a2b', head='#f29d3e', belly='#ffe3b2', limb='#a85a20',
            bolt='#9a6bff', boltd='#6f3fe0'),
    2: dict(body='#9a4a1c', head='#b05a24', belly='#f0c98a', limb='#6e3414',
            bolt='#c2a8ff', boltd='#8a5cf0'),
}
SCALE = {0: 1.0, 1: 1.15, 2: 1.35}


def flat(key, hexv, emit=None, strength=0.0):
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = K.hexc(hexv)
    b.inputs['Roughness'].default_value = 1.0
    if emit:
        b.inputs['Emission Color'].default_value = K.hexc(emit)
        b.inputs['Emission Strength'].default_value = strength
    return m


def build(stage):
    p = PAL[stage]
    M = {k: flat(k, v) for k, v in p.items() if not k.startswith('bolt')}
    glow = {0: 0.10, 1: 0.25, 2: 0.60}[stage]
    M['bolt'] = flat('bolt', p['bolt'], p['boltd'], glow)
    M['boltd'] = flat('boltd', p['boltd'], p['boltd'], glow * 0.6)
    M['cream'] = flat('cream', '#f1e2bd')
    M['ivory'] = flat('ivory', '#f4ecd6')
    M['dark'] = flat('dark', '#141830')
    M['white'] = flat('white', '#ffffff', '#ffffff', 1.0)
    M['plate'] = flat('plate', '#5a4636')
    objs = []

    def E(x, y, z, rx, ry, rz, m, tilt=None):
        objs.append(K.ellipsoid(x, y, z, rx, ry, rz, M[m], seg=24, rings=16,
                                tilt=tilt))

    def limb(p0, p1, r0, r1, m, seg=14):
        a, b = Vector(p0), Vector(p1)
        d = b - a
        c = K.cyl(0, 0, 0, r0, r1, d.length, M[m], seg=seg, smooth=True)
        c.location = a
        c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        objs.append(c)

    def spike(x, y, z, length, r, back, m='bolt', side=0.0):
        limb((x, y, z), (x - math.sin(back) * length, y + side * length,
                         z + math.cos(back) * length), r, 0.0, m, seg=5)

    def zig(pts, r, m='bolt'):
        for i in range(len(pts) - 1):
            k = 1.0 - 0.55 * i / max(1, len(pts) - 2)
            limb(pts[i], pts[i + 1], r * k, r * k * 0.7, m, seg=5)

    def face(hx, hz, hs, ex, ez, brows):
        """Eyes, glint, nose, muzzle for a head centred (hx, 0, hz), scale hs."""
        for sg in (-1, 1):
            E(ex, sg * 0.19 * hs, ez, 0.125 * hs, 0.11 * hs, 0.14 * hs, 'dark')
            E(ex + 0.08 * hs, sg * 0.17 * hs, ez + 0.06 * hs,
              0.04 * hs, 0.036 * hs, 0.045 * hs, 'white')
            if brows:
                E(ex - 0.02, sg * 0.17 * hs, ez + 0.17 * hs, 0.15 * hs, 0.04 * hs,
                  0.035 * hs, 'dark', (math.radians(-sg * 20), 0.2,
                                       math.radians(sg * 16)))
        E(hx + 0.27 * hs, 0, hz - 0.10 * hs, 0.15 * hs, 0.17 * hs, 0.11 * hs, 'cream')
        E(hx + 0.41 * hs, 0, hz - 0.07 * hs, 0.045 * hs, 0.065 * hs, 0.04 * hs, 'dark')

    if stage == 0:
        # cuddly cub: round, huge head, stubby legs, one paw waving
        E(-0.04, 0, 0.36, 0.36, 0.32, 0.31, 'body')
        E(0.12, 0, 0.30, 0.24, 0.24, 0.22, 'belly')
        E(0.26, 0, 0.74, 0.40, 0.38, 0.35, 'head')
        face(0.26, 0.74, 1.15, 0.54, 0.80, False)
        for sg in (-1, 1):
            E(0.14, sg * 0.30, 1.04, 0.09, 0.09, 0.12, 'head')
            E(0.14, sg * 0.30, 1.04, 0.05, 0.05, 0.07, 'belly')
            E(0.28, sg * 0.12, 0.10, 0.17, 0.12, 0.10, 'limb')
            E(-0.10, sg * 0.27, 0.12, 0.17, 0.12, 0.10, 'limb')
        E(0.36, 0.30, 0.34, 0.12, 0.10, 0.14, 'limb', (0, 0.3, 0.3))
        E(0.42, -0.30, 0.60, 0.12, 0.10, 0.14, 'limb', (0, -0.5, -0.3))
        spike(0.30, 0, 1.06, 0.34, 0.10, 0.25, 'bolt')
        spike(0.22, 0.07, 1.04, 0.26, 0.075, 0.6, 'boltd', 0.25)
        spike(0.22, -0.07, 1.04, 0.26, 0.075, 0.6, 'boltd', -0.25)
        for i in range(3):
            spike(-0.02 - i * 0.16, 0, 0.64 - i * 0.04, 0.17, 0.05, 1.0, 'boltd')
        zig([(-0.36, 0, 0.36), (-0.52, 0.0, 0.44), (-0.46, 0.0, 0.54),
             (-0.62, 0.0, 0.64)], 0.05)
    elif stage == 1:
        # sprinter: slim, mid-stride, mane and horns
        E(0.00, 0, 0.66, 0.54, 0.25, 0.28, 'body', (0, 0.16, 0))
        E(0.16, 0, 0.55, 0.32, 0.19, 0.15, 'belly', (0, 0.16, 0))
        E(-0.36, 0, 0.74, 0.27, 0.25, 0.27, 'body')
        E(0.42, 0, 0.78, 0.2, 0.2, 0.22, 'body', (0, 0.5, 0))
        E(0.66, 0, 0.82, 0.31, 0.28, 0.26, 'head')
        face(0.66, 0.82, 0.9, 0.84, 0.90, True)
        for sg in (-1, 1):
            E(0.56, sg * 0.24, 1.00, 0.07, 0.045, 0.11, 'head')
            zig([(0.62, sg * 0.13, 0.98), (0.56, sg * 0.20, 1.12),
                 (0.47, sg * 0.20, 1.20), (0.36, sg * 0.24, 1.32)], 0.055)
            limb((0.93, sg * 0.08, 0.62), (0.93, sg * 0.11, 0.50), 0.028, 0.0, 'ivory')
        for i in range(6):
            t = i / 5
            spike(0.46 - t * 0.95, 0, 0.96 - 0.20 * t, 0.34 + 0.12 * (1 - t), 0.07,
                  1.0 + 0.2 * t, 'bolt' if i % 2 == 0 else 'boltd')

        def leg(sh, kn, pw, r):
            limb(sh, kn, r, r * 0.8, 'limb')
            limb(kn, pw, r * 0.8, r * 0.62, 'limb')
            E(pw[0] + 0.07, pw[1], pw[2] + 0.03, 0.15, 0.10, 0.065, 'dark')
        leg((0.30, -0.22, 0.56), (0.54, -0.27, 0.36), (0.72, -0.27, 0.08), 0.14)
        leg((0.28, 0.22, 0.56), (0.10, 0.26, 0.34), (-0.08, 0.26, 0.07), 0.13)
        leg((-0.36, -0.24, 0.62), (-0.66, -0.28, 0.36), (-0.92, -0.26, 0.07), 0.14)
        leg((-0.36, 0.24, 0.62), (-0.14, 0.28, 0.40), (0.06, 0.26, 0.06), 0.13)
        zig([(-0.60, 0, 0.84), (-0.86, 0, 0.92), (-0.80, 0, 1.10),
             (-1.10, 0, 1.22), (-1.02, 0, 1.42)], 0.065)
        for sg in (-1, 1):
            spike(0.28, sg * 0.28, 0.84, 0.28, 0.07, 0.4, 'bolt', sg * 0.35)
    else:
        # titan: the sprinter grown mighty - same stride, far more mass
        E(0.00, 0, 0.78, 0.62, 0.36, 0.38, 'body', (0, 0.10, 0))
        E(0.18, 0, 0.64, 0.38, 0.27, 0.22, 'belly', (0, 0.10, 0))
        E(0.30, 0, 1.00, 0.34, 0.34, 0.32, 'body')                 # shoulder hump
        E(-0.42, 0, 0.86, 0.34, 0.33, 0.34, 'body')                # haunch
        E(0.52, 0, 0.98, 0.26, 0.27, 0.28, 'body', (0, 0.5, 0))    # thick neck
        E(0.78, 0, 1.00, 0.38, 0.35, 0.31, 'head', (0, 0.05, 0))   # head, lowered
        face(0.78, 1.00, 1.0, 1.02, 1.06, True)
        for sg in (-1, 1):
            E(0.64, sg * 0.30, 1.22, 0.10, 0.06, 0.14, 'head')     # round ears
            E(0.64, sg * 0.30, 1.22, 0.055, 0.04, 0.08, 'belly')
            # armour plate on the shoulder with a bolt spike
            E(0.26, sg * 0.42, 1.22, 0.22, 0.17, 0.15, 'plate', (0, 0, sg * 0.3))
            spike(0.22, sg * 0.46, 1.32, 0.40, 0.10, 0.5, 'bolt', sg * 0.4)
            # antlers of bolt crystal, sweeping up and back
            zig([(0.72, sg * 0.16, 1.22), (0.64, sg * 0.26, 1.46),
                 (0.50, sg * 0.30, 1.60), (0.56, sg * 0.40, 1.82),
                 (0.38, sg * 0.46, 1.98)], 0.075)
            zig([(0.64, sg * 0.26, 1.46), (0.80, sg * 0.36, 1.62),
                 (0.76, sg * 0.42, 1.78)], 0.05, 'boltd')
            # long tusks
            limb((1.10, sg * 0.11, 0.86), (1.16, sg * 0.14, 0.62), 0.05, 0.0, 'ivory')
        for i in range(8):                                          # blazing mane
            t = i / 7
            spike(0.50 - t * 1.05, 0, 1.18 - 0.28 * t, 0.52 + 0.20 * (1 - t), 0.10,
                  0.9 + 0.25 * t, 'bolt' if i % 2 == 0 else 'boltd')

        def leg(sh, kn, pw, r):
            limb(sh, kn, r, r * 0.8, 'limb')
            limb(kn, pw, r * 0.8, r * 0.6, 'limb')
            E(kn[0], kn[1], kn[2], r * 0.85, r * 0.85, r * 0.85, 'limb')   # knee
            E(pw[0] + 0.08, pw[1], pw[2] + 0.03, 0.18, 0.12, 0.075, 'dark')
        leg((0.34, -0.28, 0.70), (0.62, -0.34, 0.44), (0.84, -0.34, 0.08), 0.19)
        leg((0.30, 0.28, 0.70), (0.08, 0.34, 0.42), (-0.10, 0.34, 0.07), 0.18)
        leg((-0.42, -0.30, 0.74), (-0.76, -0.36, 0.42), (-1.02, -0.34, 0.07), 0.20)
        leg((-0.42, 0.30, 0.74), (-0.16, 0.36, 0.46), (0.06, 0.34, 0.06), 0.18)
        zig([(-0.70, 0, 0.98), (-1.00, 0, 1.08), (-0.92, 0, 1.30),
             (-1.28, 0, 1.44), (-1.16, 0, 1.70)], 0.10)
        spike(0.56, 0, 0.60, 0.30, 0.09, -0.4, 'bolt')             # chest crystal
    s = SCALE[stage]
    for o in objs:
        o.location = (o.location[0] * s, o.location[1] * s, o.location[2] * s)
        o.scale = (s, s, s)
    return objs


SMOOTH_MATS = False     # glimmergnaw switches this on: clean seams between materials


PAINT = []              # (group, centre, radii, material name, only-over material name)


def _paint(me, grp, mats):
    """Colour a patch of the surface WITHOUT adding geometry: every voxel face of `grp` whose
    centre lies inside the ellipsoid and is currently the `over` material takes the new one.
    A second overlapping mesh leaves a shelf that casts a dark shadow line; a painted patch
    is flush, so its border is one clean stepped line."""
    names = [m.name if m else None for m in mats]
    for g, c, r, mat, over in PAINT:
        if g != grp or over not in names:
            continue
        if mat not in names:                       # no modelled part of that colour here
            me.materials.append(bpy.data.materials[mat])
            names.append(mat)
        mi, oi = names.index(mat), names.index(over)
        for pl in me.polygons:
            if pl.material_index != oi:
                continue
            p = pl.center
            if sum(((p[k] - c[k]) / r[k]) ** 2 for k in range(3)) <= 1.0:
                pl.material_index = mi


def _smooth_materials(me, anchor, passes=6):
    """Majority filter over the voxel faces: where two ellipsoids overlap the nearest-face
    lookup flips colour from block to block, which shows as specks along the seam. Each
    face takes the most common material among itself and its neighbours (faces that share
    a vertex), so a seam becomes one clean line and lone odd blocks disappear."""
    from collections import Counter
    around = {}
    for pl in me.polygons:
        for v in pl.vertices:
            around.setdefault(v, []).append(pl.index)
    nbr = []
    for pl in me.polygons:
        s = set()
        for v in pl.vertices:
            s.update(around[v])
        s.discard(pl.index)
        nbr.append(s)
    for _ in range(passes):
        cur = [pl.material_index for pl in me.polygons]
        for pl in me.polygons:
            if cur[pl.index] == anchor:
                continue
            c = Counter(cur[i] for i in nbr[pl.index] if cur[i] != anchor)
            c[cur[pl.index]] += 3                  # keep ties on the current colour
            pl.material_index = c.most_common(1)[0][0]


def _union_shells(bm):
    """Merge overlapping shells into ONE closed surface (exact boolean, self-intersection on).

    The block remesh decides inside/outside by parity, so where two shells overlap (shoulder
    cap, arm, elbow, crystal base...) the overlap reads as 'outside': hollow pockets and pits
    in the voxel surface, which showed up as dark blotches. Unioned first, nothing overlaps."""
    me = bpy.data.meshes.new('ushell')
    bm.to_mesh(me)
    ob = bpy.data.objects.new('ushell', me)
    bpy.context.scene.collection.objects.link(ob)
    empty = bpy.data.collections.new('ushell_none')
    md = ob.modifiers.new('u', 'BOOLEAN')
    md.operation = 'UNION'
    md.solver = 'EXACT'
    md.operand_type = 'COLLECTION'
    md.collection = empty
    md.use_self = True
    bpy.context.view_layer.update()
    ev = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bm.clear()
    bm.from_mesh(ev)
    bpy.data.meshes.remove(ev)
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    bpy.data.collections.remove(empty)


def _drop_islands(bm, min_faces=30):
    """Delete loose bits made of only a few voxels (a 2x2x2 block is 24 faces)."""
    bm.faces.ensure_lookup_table()
    seen, kill = set(), []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        comp, stack = [], [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            comp.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        if len(comp) < min_faces:
            kill += comp
    if kill:
        bmesh.ops.delete(bm, geom=kill, context='FACES')


def voxelise(objs):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    mats, index = [], {}
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        me.transform(o.matrix_world)
        slots = [s.material for s in o.material_slots]
        t = bmesh.new()
        t.from_mesh(me)
        vm = {v: bm.verts.new(v.co) for v in t.verts}
        for f in t.faces:
            mat = slots[f.material_index] if f.material_index < len(slots) else None
            key = mat.name if mat else '__none'
            if key not in index:
                index[key] = len(mats)
                mats.append(mat)
            try:
                nf = bm.faces.new([vm[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = index[key]
        t.free()
        bpy.data.meshes.remove(me)
    if SMOOTH_MATS:
        _union_shells(bm)
    anchor = len(mats)
    mats.append(None)
    e = 0.002
    for c in ((-HALF, -HALF, -0.05), (HALF, HALF, HALF - 0.05)):
        a = bm.verts.new(c)
        b = bm.verts.new((c[0] + e, c[1], c[2]))
        d = bm.verts.new((c[0], c[1] + e, c[2]))
        bm.faces.new((a, b, d)).material_index = anchor
    bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    fmat = [f.material_index for f in bm.faces]
    src = bpy.data.meshes.new('vsrc')
    bm.to_mesh(src)
    bm.free()
    tmp = bpy.data.objects.new('vtmp', src)
    bpy.context.scene.collection.objects.link(tmp)
    md = tmp.modifiers.new('blocks', 'REMESH')
    md.mode = 'BLOCKS'
    md.octree_depth = DEPTH
    md.scale = 0.99
    md.use_remove_disconnected = False
    md.use_smooth_shade = False
    bpy.context.view_layer.update()
    dg2 = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg2))
    bpy.data.objects.remove(tmp)
    new.materials.clear()
    for m in mats:
        new.materials.append(m)
    for pl in new.polygons:
        hit = bvh.find_nearest(pl.center)
        pl.material_index = fmat[hit[2]] if hit and hit[2] is not None else 0
        pl.use_smooth = False
    if PAINT and objs and objs[0].get('grp') is not None:
        _paint(new, objs[0]['grp'], mats)
    if SMOOTH_MATS:
        _smooth_materials(new, anchor)
    b2 = bmesh.new()
    b2.from_mesh(new)
    bmesh.ops.delete(b2, geom=[f for f in b2.faces if f.material_index == anchor],
                     context='FACES')
    _drop_islands(b2)               # house rule: no stray single-voxel specks (claw tips, details)
    if SMOOTH_MATS:
        bmesh.ops.recalc_face_normals(b2, faces=b2.faces)
    b2.to_mesh(new)
    b2.free()
    ob = bpy.data.objects.new('voxels', new)
    bpy.context.scene.collection.objects.link(ob)
    for o in objs:
        bpy.data.objects.remove(o)
    return ob


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, default=0)
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=64)
    ap.add_argument('--size', type=int, default=720)
    a = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = build(a.stage)
    voxelise(objs)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))

    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = {0: 2.4, 1: 3.6, 2: 4.6}[a.stage]
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    tgt = Vector(({0: 0.0, 1: -0.2, 2: -0.25}[a.stage], 0.0, {0: 0.5, 1: 0.7, 2: 0.9}[a.stage]))
    co.location = tgt + Vector((5.2, -4.0, 2.8))
    co.rotation_euler = (tgt - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = a.size
    sc.render.engine = 'CYCLES'
    cy = sc.cycles
    cy.device = 'CPU'
    cy.samples = a.samples
    cy.use_denoising = True
    sc.render.film_transparent = True
    vs = sc.view_settings
    vs.view_transform = 'AgX'
    vs.exposure = 0.3
    K.render(a.out)


if __name__ == '__main__':
    main()
