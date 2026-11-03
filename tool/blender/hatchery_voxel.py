"""The Hatchery as a voxel model — a style test for buildings.

    blender --background --python tool/blender/hatchery_voxel.py -- \
        --out tool/blender/_out/hatchery_voxel.png --depth 6 [--samples 64]

The whole scene (every wall, tile, egg, blade of grass) is joined into one
mesh, voxelised with the Remesh modifier in BLOCKS mode, and each new block
takes the material of the nearest original surface, so tiles stay orange and
plaster stays cream. --depth is the grid resolution: 2^depth blocks along the
longest side (6 = chunky, 7 = fine).
"""
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hatchery_pro as hp  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--depth', type=int, default=6)
    ap.add_argument('--samples', type=int, default=64)
    ap.add_argument('--scale', type=int, default=5)
    ap.add_argument('--no-denoise', action='store_true')
    ap.add_argument('--monster', action='store_true',
                    help='put the Tidelord in the courtyard')
    ap.add_argument('--mscale', type=float, default=0.78)
    ap.add_argument('--smooth', action='store_true',
                    help='skip the voxelising: the plain scene')
    args = ap.parse_args(argv)

    rb.clear()
    K._mats.clear()
    hp.build(ground=False)
    if args.monster:
        import tidelord_pro as tp
        root = tp.build(yaw=215.0, head_yaw=30.0, catcher=0)
        root.location = (-0.86, -0.82, hp.G)
        root.scale = (args.mscale,) * 3
        if not args.smooth:
            # a block is ONE colour: drop the graded fur for flat part colours
            import tidelord_styles as ts
            ts.flat_colours({'sk_top': '#3a86d8', 'sk_head': '#4a96e4',
                             'sk_flip': '#5aa4ea', 'sk_flip_d': '#3a86d8',
                             'sk_belly': '#c4e0f2', 'sk_cream': '#e8d8b2'},
                            1.0, bump=0.0)
    if args.smooth:
        K.lighting()
        K.setup_render(args.samples, args.scale, 4, 3)
        K.render(args.out)
        return

    # one mesh, no modifiers: voxelising a bevelled mesh would only add noise
    for o in [o for o in bpy.data.objects if o.name.startswith('blade')]:
        bpy.data.objects.remove(o)       # single-triangle grass would only become noise
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in meshes:
        for m in list(o.modifiers):
            o.modifiers.remove(m)
    view = bpy.context.view_layer
    for o in bpy.data.objects:
        o.select_set(False)
    for o in meshes:
        o.select_set(True)
    view.objects.active = meshes[0]
    bpy.ops.object.join()
    src = view.objects.active
    src.name = 'src'
    # the join keeps the ACTIVE object's transform, which may be a rotated beam:
    # bake it, so the voxel copy (identity transform) lands where the scene is
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print('joined', len(src.data.polygons), 'faces,', len(src.data.materials),
          'materials')

    # the voxel copy
    vox_me = src.data.copy()
    vox = bpy.data.objects.new('voxels', vox_me)
    bpy.context.scene.collection.objects.link(vox)
    md = vox.modifiers.new('blocks', 'REMESH')
    md.mode = 'BLOCKS'
    md.octree_depth = args.depth
    md.scale = 0.99
    md.use_remove_disconnected = False
    md.use_smooth_shade = False
    view.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = vox.evaluated_get(dg)
    new_me = bpy.data.meshes.new_from_object(ev)

    # nearest-surface material transfer
    bvh = BVHTree.FromObject(src, dg)
    poly_mat = [p.material_index for p in src.data.polygons]
    new_me.materials.clear()
    for m in src.data.materials:
        new_me.materials.append(m)
    for p in new_me.polygons:
        hit = bvh.find_nearest(p.center)
        p.material_index = poly_mat[hit[2]] if hit and hit[2] is not None else 0
        p.use_smooth = False
    bpy.data.objects.remove(vox)
    out = bpy.data.objects.new('hatchery_voxel', new_me)
    bpy.context.scene.collection.objects.link(out)
    bpy.data.objects.remove(src)
    print('voxel faces', len(new_me.polygons))

    K.lighting()
    K.setup_render(args.samples, args.scale, 4, 3)
    if args.no_denoise:
        bpy.context.scene.cycles.use_denoising = False
    K.render(args.out)
    print('ART_BOX', rb.frame.art_box)


if __name__ == '__main__':
    main()
