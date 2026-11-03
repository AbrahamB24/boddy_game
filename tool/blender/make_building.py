"""Build, voxelise, render and ship ONE Fachwerk building.

    blender --background --python tool/blender/make_building.py -- <id> \
        [--samples 128] [--preview] [--smooth] [--out PATH]

<id> names tool/blender/buildings/<id>.py, which exposes build(), W and H.
Writes, unless --preview:

    docs/renders/<id>.png                     full-size archive render
    assets/images/buildings/<id>.webp         what the app ships
    lib/.../building_art_box.dart             the (baseWidth, anchorX, lift)
                                              entry for <id>, rewritten in place
    lib/.../building_art.dart                 <id> added to kBundledBuildingArt
    lib/.../building_definitions.dart         <id>'s kChimneyAnchor, projected
                                              from the module's CHIMNEY point

--preview renders a quick low-sample PNG to the scratch folder only (or --out)
and touches nothing in the repo. --smooth skips the voxelising (debugging).

The SQL migration and the footprint in building_definitions.dart are NOT
touched here: they are a design decision per building, made by hand.
"""
import argparse
import importlib
import math
import os
import re
import sys

import bpy
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import fw_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402

ART_BOX_DART = os.path.join(ROOT, 'lib', 'features', 'settlement', 'data',
                            'building_art_box.dart')
ART_DART = os.path.join(ROOT, 'lib', 'features', 'settlement', 'data',
                        'building_art.dart')

RENDER_SCALE = 5          # px_per_tile handed to frame(); the archive size
# What ships: the archive scaled by this, so every building has the SAME pixel
# density on the map (the Hatchery's 1227 px render shipped at 960). Capped
# at 960 px wide for the decode budget (tool/pack_art.py, main.dart).
SHIP_DENSITY = 960 / 1227
SHIP_MAX_W = 960
WEBP_QUALITY = 88


def lower_to_yard():
    """Authoring puts the yard at z = G; the game wants it at z = 0."""
    for ob in list(bpy.data.objects):
        if ob.parent is None:
            ob.location.z -= K.G


def voxelize(name):
    """Join every mesh, remesh into BLOCKS of edge fw_kit.VOX, and give each
    block the material of the nearest original surface."""
    for o in [o for o in bpy.data.objects if o.name.startswith('blade')]:
        bpy.data.objects.remove(o)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in meshes:
        for md in list(o.modifiers):
            o.modifiers.remove(md)
    view = bpy.context.view_layer
    for o in bpy.data.objects:
        o.select_set(False)
    for o in meshes:
        o.select_set(True)
    view.objects.active = meshes[0]
    bpy.ops.object.join()
    src = view.objects.active
    src.name = 'src'
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    view.update()

    # ── one block size for every building ──
    # Remesh measures its grid against the model's LARGEST dimension: the
    # grid is maxdim / scale wide, split into 2^depth blocks. Pick the depth
    # that just holds maxdim at VOX, then the scale that lands on VOX exactly.
    maxdim = max(src.dimensions)
    depth = max(1, math.ceil(math.log2(maxdim / (fw_kit.VOX * 0.99)) - 1e-4))
    scale = maxdim / (fw_kit.VOX * 2 ** depth)
    print(f'VOXEL maxdim={maxdim:.4f} depth={depth} scale={scale:.5f} '
          f'block={maxdim / scale / 2 ** depth:.5f}')

    vox = bpy.data.objects.new('voxels', src.data.copy())
    bpy.context.scene.collection.objects.link(vox)
    md = vox.modifiers.new('blocks', 'REMESH')
    md.mode = 'BLOCKS'
    md.octree_depth = depth
    md.scale = scale
    md.use_remove_disconnected = False
    md.use_smooth_shade = False
    view.update()
    dg = bpy.context.evaluated_depsgraph_get()
    new_me = bpy.data.meshes.new_from_object(vox.evaluated_get(dg))

    bvh = BVHTree.FromObject(src, dg)
    poly_mat = [p.material_index for p in src.data.polygons]
    new_me.materials.clear()
    for mt in src.data.materials:
        new_me.materials.append(mt)
    for p in new_me.polygons:
        hit = bvh.find_nearest(p.center)
        p.material_index = poly_mat[hit[2]] if hit and hit[2] is not None else 0
        p.use_smooth = False
    bpy.data.objects.remove(vox)
    out = bpy.data.objects.new(name + '_voxel', new_me)
    bpy.context.scene.collection.objects.link(out)
    bpy.data.objects.remove(src)
    print('voxel faces', len(new_me.polygons))


def ship_webp(png, dst):
    """Scale the archive render to the shipping density and write WebP."""
    sc = bpy.context.scene
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    img = bpy.data.images.load(png)
    iw, ih = img.size
    w = min(SHIP_MAX_W, round(iw * SHIP_DENSITY))
    img.scale(w, max(1, round(ih * w / iw)))
    st = sc.render.image_settings
    st.file_format = 'WEBP'
    st.color_mode = 'RGBA'
    st.quality = WEBP_QUALITY
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save_render(dst, scene=sc)
    print('SHIPPED', dst, f'{w}x{img.size[1]}', os.path.getsize(dst), 'bytes')


def _rw(path, fn):
    with open(path, 'rb') as f:
        raw = f.read().decode('utf-8')
    crlf = '\r\n' in raw
    text = fn(raw.replace('\r\n', '\n'))
    if crlf:
        text = text.replace('\n', '\r\n')
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))


def write_art_box(bid, box):
    entry = f"  '{bid}': ({box[0]:.5f}, {box[1]:.5f}, {box[2]:.5f}),"

    def fn(t):
        pat = re.compile(r"^  '" + re.escape(bid) + r"': \([^)]*\),[^\n]*$", re.M)
        if pat.search(t):
            return pat.sub(entry, t, count=1)
        i = t.rindex('};')
        return t[:i] + entry + '\n' + t[i:]
    _rw(ART_BOX_DART, fn)
    print('ART_BOX', bid, box)


def register_bundled(bid):
    def fn(t):
        m = re.search(r'kBundledBuildingArt\s*=\s*(?:<String>)?\{(.*?)\};', t, re.S)
        if not m or re.search(r"'" + re.escape(bid) + r"'", m.group(1)):
            return t
        i = m.end() - 2
        return t[:i] + f"  '{bid}',\n" + t[i:]
    _rw(ART_DART, fn)


def chimney_anchor(pt):
    """The chimney mouth as kChimneyAnchor wants it: a fraction of the
    OVERLAY box, which is the art's width wide, 1.25 x that tall, and stands
    on the art's bottom edge (_LifeOverlay in settlement_map.dart).
    pt is in AUTHORING coordinates (yard at z = G)."""
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    u, v, _ = world_to_camera_view(sc, sc.camera, Vector((pt[0], pt[1], pt[2] - K.G)))
    iw, ih = sc.render.resolution_x, sc.render.resolution_y
    yb = v * ih                                    # px above the image bottom
    return (round(u, 3), round(1 - yb / (1.25 * iw), 3))


def write_chimney(bid, anchor):
    """Rewrite (or add, or drop when anchor is None) <id>'s kChimneyAnchor."""
    path = os.path.join(ROOT, 'lib', 'features', 'settlement', 'data',
                        'building_definitions.dart')

    def fn(t):
        m = re.search(r'const Map<String, \(double, double\)> kChimneyAnchor = \{(.*?)\n\};',
                      t, re.S)
        body = m.group(1)
        pat = re.compile(r"\n  '" + re.escape(bid) + r"': \([^)]*\),[^\n]*")
        body = pat.sub('', body)
        if anchor is not None:
            body += f"\n  '{bid}': ({anchor[0]:.3f}, {anchor[1]:.3f}),"
        return t[:m.start(1)] + body + t[m.end(1):]
    _rw(path, fn)
    print('CHIMNEY', bid, anchor)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('id')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--preview', action='store_true')
    ap.add_argument('--smooth', action='store_true')
    ap.add_argument('--out')
    ap.add_argument('--anchors-only', action='store_true',
                    help='build + voxelise + frame, write the art box and the '
                         'chimney anchor, render nothing')
    args = ap.parse_args(argv)

    mod = importlib.import_module('buildings.' + args.id)
    rb.clear()
    K._mats.clear()
    mod.build()
    lower_to_yard()
    if not args.smooth:
        voxelize(args.id)
    K.lighting()
    samples = min(args.samples, 24) if args.preview else args.samples
    K.setup_render(samples, RENDER_SCALE, mod.W, mod.H)
    box = rb.frame.art_box
    chim = getattr(mod, 'CHIMNEY', None)
    anchor = chimney_anchor(chim) if chim else None

    if args.preview or args.out:
        out = args.out or os.path.join(HERE, '_out', f'{args.id}_preview.png')
        K.render(out)
        print('ART_BOX', args.id, box)
        print('CHIMNEY', args.id, anchor)
        return
    if args.anchors_only:
        write_art_box(args.id, box)
        write_chimney(args.id, anchor)
        return
    png = os.path.join(ROOT, 'docs', 'renders', f'{args.id}.png')
    K.render(png)
    ship_webp(png, os.path.join(ROOT, 'assets', 'images', 'buildings',
                                f'{args.id}.webp'))
    write_art_box(args.id, box)
    write_chimney(args.id, anchor)
    register_bundled(args.id)


if __name__ == '__main__':
    main()
