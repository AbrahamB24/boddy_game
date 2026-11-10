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
    assets/images/buildings/<id>_base.webp    the picture minus its swaying
    assets/images/buildings/<id>_anim.webp    parts, and the atlas of moving
                                              layers (anim_pass.py)
    lib/.../building_model.dart               kBuildingAnim + kBuildingEntrance

A module may also define ENTRANCE = (face, k) (fw_kit.entrance_point) and
GLOW = {material: (kind, amp, period)} to override anim_pass.GLOW_LAYERS.

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


def voxelize(name, objs=None):
    """The shipped path: the union voxeliser (voxelizer.py) at fw_kit.VOX."""
    import voxelizer
    return voxelizer.voxelize(fw_kit.VOX, name + "_voxel", objs=objs)


def voxelize_remesh(name):
    """OLD path (--remesh), kept for comparison: Remesh BLOCKS on the joined
    scene. Overlapping parts come out hollow (ray parity) — see voxelizer.py.
    Join every mesh, remesh into BLOCKS of edge fw_kit.VOX, and give each
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


def _cell_turned(W, H, cell, r):
    """A grid cell of the unturned footprint after r quarter turns CLOCKWISE
    on the map — the same turn as fw_kit.entrance_turned, done on the cell's
    centre in Blender coordinates (grid y runs against Blender y)."""
    x, y = cell[0] + 0.5 - W / 2, -(cell[1] + 0.5 - H / 2)
    w, h = W, H
    for _ in range(r % 4):
        x, y = y, -x
        w, h = h, w
    return (int(math.floor(x + w / 2)), int(math.floor(-y + h / 2)))


def check_overlaps(bid, depth=0.04):
    """Report every part that PIERCES a roof slab (user 2026-11-09: 'keine
    Stuecke, die das Dach durchstossen'). Runs on the smooth model, before
    voxelising. A roof piece is any mesh whose material name starts with
    'roof' or 'shingle'. A vertex of another part counts when it lies more than
    `depth` INSIDE a slab - judged by the nearest surface point's outward
    normal - so timber that merely sits on or touches a roof is not reported.
    Chimneys are meant to pass through a roof: they are listed, but as such."""
    from mathutils import Vector
    dg = bpy.context.evaluated_depsgraph_get()

    def is_roof(o):
        return any(s.material and s.material.name.startswith(('roof', 'shingle'))
                   for s in o.material_slots)

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    roofs = [o for o in meshes if is_roof(o) and max(o.dimensions) > 0.3]
    trees = []
    for r in roofs:
        bb = [r.matrix_world @ Vector(c) for c in r.bound_box]
        lo = Vector((min(b[i] for b in bb) for i in range(3)))
        hi = Vector((max(b[i] for b in bb) for i in range(3)))
        trees.append((r, BVHTree.FromObject(r, dg), lo, hi, r.matrix_world.inverted()))
    hits = {}
    for o in meshes:
        if is_roof(o) or o.name.startswith('maptree'):
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        pts = [mw @ v.co for v in me.vertices]
        for e in me.edges:                      # a post pierces a slab with its middle, not its ends
            a, b = me.vertices[e.vertices[0]].co, me.vertices[e.vertices[1]].co
            pts += [mw @ a.lerp(b, k / 8) for k in range(1, 8)]
        ev.to_mesh_clear()
        for r, t, lo, hi, inv in trees:
            n, worst, where = 0, 0.0, None
            for p in pts:
                if not all(lo[i] - 0.02 <= p[i] <= hi[i] + 0.02 for i in range(3)):
                    continue
                lp = inv @ p                    # the BVH lives in the roof's LOCAL space
                loc, nrm, idx, dist = t.find_nearest(lp)
                if loc is not None and (lp - loc).dot(nrm) < 0 and dist > depth:
                    n += 1
                    if dist > worst:
                        worst, where = dist, p
            if n:
                hits.setdefault(o.name, (n, worst, where, r.name))
    print(f'OVERLAPS {bid}: {len(hits)} parts pierce a roof')
    for name, (n, worst, p, rn) in sorted(hits.items(), key=lambda kv: -kv[1][1]):
        print('  OVERLAP %-10s at x=%.2f y=%.2f z=%.2f  %d vertices, deepest %.3f, in %s'
              % (name, p.x, p.y, p.z, n, worst, rn))


def _tile_grid(W, H, lw=0.025, z=0.03):
    """The footprint's tile lines as thin flat strips (the base is W x H tiles
    centred on the origin), so the review sheet shows where the tiles are
    (user 2026-11-09). Only the sheet calls this."""
    verts, faces = [], []

    def strip(x0, y0, x1, y1):
        i = len(verts)
        verts.extend([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)])
        faces.append((i, i + 1, i + 2, i + 3))

    for k in range(W + 1):
        x = -W / 2 + k
        strip(x - lw, -H / 2 - lw, x + lw, H / 2 + lw)
    for k in range(H + 1):
        y = -H / 2 + k
        strip(-W / 2 - lw, y - lw, W / 2 + lw, y + lw)
    me = bpy.data.meshes.new('tile_grid')
    me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new('tile_grid', me)
    bpy.context.scene.collection.objects.link(ob)
    mt = bpy.data.materials.new('tile_grid')
    mt.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    mt.use_nodes = True
    bsdf = mt.node_tree.nodes.get('Principled BSDF')
    if bsdf:
        bsdf.inputs['Base Color'].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs['Roughness'].default_value = 1.0
    me.materials.append(mt)
    return ob


def sheet(mod, headroom, samples, bid):
    """The four quarter turns of the building, side by side, for the user's
    review BEFORE the full render (user 2026-11-09)."""
    import numpy as np
    out_dir = os.path.join(ROOT, 'docs', 'renders', 'review')
    os.makedirs(out_dir, exist_ok=True)
    scale = 3
    paths = []
    grid = _tile_grid(mod.W, mod.H)             # review only: the real renders never get it
    for r in range(4):
        az = 90.0 * r
        for o in list(bpy.data.objects):
            if o.type == 'CAMERA' or (o.type == 'LIGHT' and o.data.type == 'SUN'):
                bpy.data.objects.remove(o)
        K.lighting(azimuth=az)
        rb.frame(mod.W, mod.H, scale, headroom, az)
        p = os.path.join(out_dir, f'_{bid}_v{r}.png')
        K.render(p)
        paths.append(p)
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        a = np.empty(w * h * 4, np.float32)
        im.pixels.foreach_get(a)
        imgs.append(a.reshape(h, w, 4))
        bpy.data.images.remove(im)
    # the four views differ by a few pixels (the frame re-solves per turn):
    # centre each in a common cell
    h = max(a.shape[0] for a in imgs)
    w = max(a.shape[1] for a in imgs)
    canvas = np.zeros((2 * h, 2 * w, 4), np.float32)
    canvas[:, :] = (0.45, 0.70, 0.25, 1.0)          # a grass green
    for i, a in enumerate(imgs):
        row, col = divmod(i, 2)
        ih, iw = a.shape[:2]
        y0 = (1 - row) * h + (h - ih) // 2          # row 0 on top (bottom-up image)
        x0 = col * w + (w - iw) // 2
        tile = canvas[y0:y0 + ih, x0:x0 + iw]
        al = a[:, :, 3:4]
        tile[:, :, :3] = a[:, :, :3] * al + tile[:, :, :3] * (1 - al)
    res = bpy.data.images.new('sheet', 2 * w, 2 * h, alpha=True)
    res.pixels.foreach_set(canvas.ravel())
    res.filepath_raw = os.path.join(out_dir, f'{bid}_4views.png')
    res.file_format = 'PNG'
    res.save()
    bpy.data.objects.remove(grid)
    for p in paths:
        os.remove(p)
    print('SHEET', res.filepath_raw)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('id')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--preview', action='store_true')
    ap.add_argument('--smooth', action='store_true')
    ap.add_argument('--out')
    ap.add_argument('--remesh', action='store_true',
                    help='old Remesh voxeliser, for comparison')
    ap.add_argument('--turns', help='only these quarter turns, e.g. 2,3 (to finish an interrupted run)')
    ap.add_argument('--overlaps', action='store_true',
                    help='list the parts that touch a roof, then stop')
    ap.add_argument('--sheet', action='store_true',
                    help='review sheet: all four quarter turns in one 2x2 PNG '
                         '(docs/renders/review/<id>_4views.png), touches nothing else')
    ap.add_argument('--anchors-only', action='store_true',
                    help='build + voxelise + frame, write the art box and the '
                         'chimney anchor, render nothing')
    args = ap.parse_args(argv)

    mod = importlib.import_module('buildings.' + args.id)
    rb.clear()
    K._mats.clear()
    fw_kit.reset_anims()
    mod.build()
    lower_to_yard()
    if args.overlaps:
        check_overlaps(args.id)
        return
    groups = {}
    if args.remesh:
        voxelize_remesh(args.id)
    elif not args.smooth:
        # The moving parts first, each on its own, then the rest: one grid,
        # so a group's blocks line up with the building's exactly.
        import voxelizer
        specs = {s['name']: s for s in fw_kit.ANIMS}
        tagged = {}
        for o in bpy.data.objects:
            if o.type == 'MESH' and 'anim' in o.keys():
                tagged.setdefault(o['anim'], []).append(o)
        for name, obs in tagged.items():
            g = voxelizer.voxelize(fw_kit.VOX, f'anim_{name}', objs=obs)
            g['anim'] = name
            groups[name] = (g, specs[name])
        rest = [o for o in bpy.data.objects
                if o.type == 'MESH' and 'anim' not in o.keys()]
        voxelize(args.id, objs=rest)
    K.lighting()
    samples = min(args.samples, 24) if args.preview else args.samples
    # the picture's MINIMUM height, in widths (it always grows to hold the
    # model): a wide, low building like the Castle would otherwise carry a
    # tall band of empty pixels
    headroom = getattr(mod, 'HEADROOM', 1.25)
    K.setup_render(samples, RENDER_SCALE, mod.W, mod.H, headroom=headroom)
    box = rb.frame.art_box
    chim = getattr(mod, 'CHIMNEY', None)
    anchor = chimney_anchor(chim) if chim else None

    if args.sheet:
        sheet(mod, headroom, args.samples, args.id)
        return
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
    import anim_pass as ap_
    tmp = os.path.join(HERE, '_out', 'layers')
    os.makedirs(tmp, exist_ok=True)
    glow = getattr(mod, 'GLOW', ap_.GLOW_LAYERS)
    model_dart = os.path.join(ROOT, 'lib', 'features', 'settlement', 'data',
                              'building_model.dart')
    ent = getattr(mod, 'ENTRANCE', None)
    # one entrance (face, k) or several [(face, k), ...] — the Castle's gates
    ents = [] if ent is None else ([ent] if isinstance(ent[0], str) else list(ent))
    turns = range(4) if getattr(mod, 'ROTATE', True) else range(1)
    if args.turns:
        turns = [int(t) for t in args.turns.split(',')]

    # ── every quarter turn (user 2026-11-03: "Gebäude um 90° drehen") ──
    # Turn r is the building turned r x 90 degrees CLOCKWISE on the map. The
    # model stays put and the CAMERA (and the sun with it, so the light on
    # screen does not change) orbits +90 per turn — which is the same picture,
    # and keeps everything projected through the camera right by itself: the
    # art box, the chimney's smoke anchor, every moving layer's pivot. Only
    # the entrance is grid arithmetic (fw_kit.entrance_turned).
    for r in turns:
        art = args.id if r == 0 else f'{args.id}_r{r}'
        az = 90.0 * r
        if r:
            for o in list(bpy.data.objects):
                if o.type == 'CAMERA' or (o.type == 'LIGHT' and o.data.type == 'SUN'):
                    bpy.data.objects.remove(o)
            K.lighting(azimuth=az)
            rb.frame(mod.W, mod.H, RENDER_SCALE, headroom, az)
            box = rb.frame.art_box
            anchor = chimney_anchor(chim) if chim else None
        w, h = (mod.H, mod.W) if r % 2 else (mod.W, mod.H)
        png = os.path.join(ROOT, 'docs', 'renders', f'{art}.png')
        K.render(png)
        base_png, layers = ap_.render_layers(art, groups, glow, tmp, samples)
        spec = ap_.pack(art, png, base_png, layers,
                        os.path.join(ROOT, 'assets', 'images', 'buildings'),
                        lambda iw: min(getattr(mod, 'SHIP_MAX_W', SHIP_MAX_W),
                                       round(iw * SHIP_DENSITY)),
                        WEBP_QUALITY)
        ap_.write_anim(model_dart, art, spec)
        ap_.write_entrance(model_dart, art, [
            fw_kit.entrance_grid(*fw_kit.entrance_turned(mod.W, mod.H, *e, r))
            for e in ents])
        # the footprint this picture was made for: the app ignores the
        # entrance and the moving parts while a def says otherwise
        ap_._set_map_entry(model_dart, 'kModelFootprint', art,
                           f"  '{art}': ({w}, {h}),")
        # Walkways (user 2026-11-03: "die Strasse durch die Burg … in der
        # Mitte zum Versammlungsplatz"): from every entrance straight in to
        # the module's WALKWAY_TO cells — cells the monsters on the roads
        # may walk, and that a road tile in front of a gate joins up with.
        plaza = getattr(mod, 'WALKWAY_TO', None)
        if plaza:
            cells = set(map(tuple, plaza))
            for e in ents:
                cx, cy, dx, dy = fw_kit.entrance_grid(mod.W, mod.H, *e)
                while (cx, cy) not in plaza and 0 <= cx < mod.W and 0 <= cy < mod.H:
                    cells.add((cx, cy))
                    cx, cy = cx - dx, cy - dy
            cells = sorted(_cell_turned(mod.W, mod.H, c, r) for c in cells)
            ap_._set_map_entry(model_dart, 'kBuildingWalkways', art,
                               f"  '{art}': [" + ', '.join(f'({x}, {y})' for x, y in cells)
                               + '],')
            # … and since monsters walk INTO it, which pixel stands in front
            # of which ground (depth_pass.py; the map's _BuildingOccluder)
            import depth_pass
            depth_pass.render_depth(
                os.path.join(ROOT, 'assets', 'images', 'buildings', f'{art}_depth.png'),
                tmp, mod.W, mod.H)
        write_art_box(art, box)
        write_chimney(art, anchor)
        register_bundled(art)


if __name__ == '__main__':
    main()
