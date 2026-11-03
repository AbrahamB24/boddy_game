"""Bake the Tidelord's animations as VOXELS — rigid blocks, no flicker.

    blender --background --python tool/blender/monster_voxel.py -- battle \
        --view front --out docs/renders/monsters/tidelord_voxel [--only idle]
    blender --background --python tool/blender/monster_voxel.py -- map \
        --out docs/renders/monsters/tidelord_voxel

The first word picks the pipeline (battle = monster_anim_pro.py, map =
monster_walk.py); everything after it is that script's own arguments.

── Why parts are voxelised ONCE ──
The first version re-voxelised the whole creature for every frame. A block grid
laid over a moving, curved surface changes which cells are "inside" from one
frame to the next, and nearest-surface colouring flips cells near a part's
border between two colours — measured: 5-15 % of the pixels that stayed
inside the silhouette changed by more than 15 % of full scale between
consecutive frames (smooth render: 1-5 %). On screen that is shimmer.

Now the creature at REST is split into its rigid parts (body, head with all its
features, the four flippers), each voxelised once on one shared grid, and each
block mesh is parented to the original pivot of that part. The animation then
moves finished blocks like a model made of LEGO pieces: blocks never appear,
vanish or change colour; they only move, exactly how voxel characters are
normally animated. Eyes are part of the head, so there is no blink.

The shared grid is pinned by two anchor specks at fixed corners of a 2 x 2
world square (the Remesh grid follows the bounding box); their blocks are
deleted afterwards. A block takes the material of the nearest original surface
of ITS OWN part; the fur's graded colours are replaced with one flat colour per
part first, because a block is a single colour.
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster_anim as ma  # noqa: E402
import tidelord_styles as ts  # noqa: E402

# 2^6 blocks across the 2.0 anchor square = 0.031 per block. Bigger creatures (the
# evolutions) widen the square and add a level so the BLOCK stays the same size.
DEPTH = int(os.environ.get('MV_DEPTH', '6'))
HALF = float(os.environ.get('MV_HALF', '1.0'))
FLAT = {'sk_top': '#3a86d8', 'sk_head': '#4a96e4', 'sk_flip': '#5aa4ea',
        'sk_flip_d': '#3a86d8', 'sk_belly': '#c4e0f2', 'sk_cream': '#e8d8b2'}
PIVOTS = ('head', 'fl_near', 'fl_far', 'fl_rear_a', 'fl_rear_b')


def group_of(o):
    """Which rigid part an object belongs to: its nearest pivot ancestor."""
    p = o
    while p is not None:
        if p.name in PIVOTS:
            return p.name
        p = p.parent
    return 'body'


def voxelise(objs, dg, name):
    """One block mesh (world space, rest pose) for [objs], on the shared grid."""
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

    src_me = bpy.data.meshes.new('vsrc')
    bm.to_mesh(src_me)
    bm.free()
    tmp = bpy.data.objects.new('vtmp', src_me)
    bpy.context.scene.collection.objects.link(tmp)
    md = tmp.modifiers.new('blocks', 'REMESH')
    md.mode = 'BLOCKS'
    md.octree_depth = DEPTH
    md.scale = 0.99
    md.use_remove_disconnected = False
    md.use_smooth_shade = False
    bpy.context.view_layer.update()
    dg2 = bpy.context.evaluated_depsgraph_get()
    new_me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg2))
    bpy.data.objects.remove(tmp)
    bpy.data.meshes.remove(src_me)

    new_me.materials.clear()
    for m in mats:
        new_me.materials.append(m)
    for p in new_me.polygons:
        hit = bvh.find_nearest(p.center)
        p.material_index = fmat[hit[2]] if hit and hit[2] is not None else 0
        p.use_smooth = False
    b2 = bmesh.new()
    b2.from_mesh(new_me)
    bmesh.ops.delete(b2, geom=[f for f in b2.faces if f.material_index == anchor],
                     context='FACES')
    b2.to_mesh(new_me)
    b2.free()
    return bpy.data.objects.new(name, new_me)


def one_block_highlights(vox, catches):
    """Trim each eye's highlight to exactly ONE block.

    The highlight sphere covers a different number of blocks per stage (the
    evolutions are scaled up, the block is not), so the sphere's size cannot
    guarantee it. Instead: per highlight object, keep the block whose centre
    is nearest the sphere's centre and repaint every other highlight face as
    pupil."""
    names = [m.name if m else '' for m in vox.data.materials]
    if 'eye_hi' not in names or 'pupil' not in names:
        return
    hi, pupil = names.index('eye_hi'), names.index('pupil')
    bs = 2.0 * HALF / (2 ** DEPTH)
    polys = [p for p in vox.data.polygons if p.material_index == hi]
    cells = [p.center - p.normal * (bs * 0.5) for p in polys]
    keep = []
    for c in catches:
        if not cells:
            break
        best = min(cells, key=lambda q: (q - c).length)
        keep.append(best)
    for p, q in zip(polys, cells):
        if not any((q - k).length < bs * 0.3 for k in keep):
            p.material_index = pupil


def build_rigid_voxels():
    """Called once per scene, with the creature at rest."""
    scene = bpy.context.scene
    stage = int(os.environ.get('MV_STAGE', '0'))
    if stage:
        import tidelord_evo as evo
        FLAT.update(evo.PALETTE[stage])
    ts.flat_colours(FLAT, 1.0, bump=0.0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    objs = [o for o in bpy.data.objects
            if o.type == 'MESH' and not o.name.startswith('vox_')
            and not getattr(o, 'is_shadow_catcher', False)]
    groups = {}
    for o in objs:
        groups.setdefault(group_of(o), []).append(o)
    for name, members in groups.items():
        vox = voxelise(members, dg, 'vox_' + name)
        catches = [sum((o.matrix_world @ Vector(b) for b in o.bound_box),
                       Vector()) / 8.0
                   for o in members if o.name.startswith('catch')]
        one_block_highlights(vox, catches)
        scene.collection.objects.link(vox)
        pivot = bpy.data.objects[name] if name in bpy.data.objects else None
        if pivot is None:
            continue
        vox.parent = pivot
        vox.matrix_parent_inverse = pivot.matrix_world.inverted()
    for o in objs:
        o.hide_render = True
    print('rigid voxel parts:', {k: len(v) for k, v in groups.items()})


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    mode, rest = argv[0], argv[1:]
    sys.argv = sys.argv[:sys.argv.index('--') + 1] + rest
    ma.ON_RIG = build_rigid_voxels
    ma.NO_SCALE = True
    if mode == 'battle':
        import monster_anim_pro as target
    else:
        import monster_walk as target
    target.main()


if __name__ == '__main__':
    main()
