"""The settlement map's ground and its props, as VOXELS.

    blender --background --python tool/blender/terrain_voxel.py -- \
        --what all --out docs/renders/terrain_voxel

    --what  tile | tree_conifer | tree_broadleaf | stone | stone_flat |
            stone_boulder | flower_heather | flower_gorse | driftwood |
            shell | dirt_patch | all

Same world as make_building.py (the Fachwerk voxel buildings): flat-colour blocks, the pro_kit golden-hour sun
and sky, AgX, the map's own isometric camera. The ground is a field of columns a
block or two high; every prop is a little block model.

Each prop is rendered on a transparent background, cropped to what it actually
covers, and fitted into the pixel size of the picture it replaces (anchored at
its foot, bottom centre) — terrain_layer.dart places props by the image size, so
a replacement with the same canvas lands exactly where the old one did.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402

# the canvas of the picture each prop replaces (pixels)
SIZES = {
    'tree_conifer': (400, 493), 'tree_broadleaf': (400, 481),
    'stone': (153, 168), 'stone_flat': (168, 185), 'stone_boulder': (148, 163),
    'flower_heather': (128, 141), 'flower_gorse': (128, 141),
    'driftwood': (185, 204), 'shell': (64, 70), 'dirt_patch': (204, 224),
}
FILES = {
    'tree_conifer': 'prop_tree_conifer', 'tree_broadleaf': 'prop_tree_broadleaf',
    'stone': 'prop_stone', 'stone_flat': 'prop_stone_flat',
    'stone_boulder': 'prop_stone_boulder',
    'flower_heather': 'prop_wildflower_heather',
    'flower_gorse': 'prop_wildflower_gorse', 'driftwood': 'prop_driftwood',
    'shell': 'prop_shell', 'dirt_patch': 'prop_dirt_patch',
}

U = 1 / 32            # one block, in cells, for props
GU = 1 / 16           # one block of ground


# ── voxel plumbing ─────────────────────────────────────────
class Vox:
    def __init__(self, palette, u):
        self.v = {}
        self.palette = palette
        self.u = u

    def put(self, x, y, z, c):
        self.v[(x, y, z)] = c

    def box(self, x0, y0, z0, x1, y1, z1, c):
        for x in range(x0, x1):
            for y in range(y0, y1):
                for z in range(z0, z1):
                    self.put(x, y, z, c)

    def ball(self, cx, cy, cz, rx, ry, rz, c, rng=None, jitter=0.0):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
                for z in range(int(cz - rz) - 1, int(cz + rz) + 2):
                    d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + \
                        ((z - cz) / rz) ** 2
                    if rng:
                        d += rng.uniform(-jitter, jitter)
                    if d <= 1.0:
                        self.put(x, y, z, c(x, y, z) if callable(c) else c)


def build_mesh(vox, name='vox'):
    mats = [K.plain(f'tv_{i}_{h}', h, rough=0.9, bump=0.0, vary=0.0)
            for i, h in enumerate(vox.palette)]
    bm = bmesh.new()
    u = vox.u
    dirs = [((1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
            ((-1, 0, 0), ((0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1))),
            ((0, 1, 0), ((1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1))),
            ((0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
            ((0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
            ((0, 0, -1), ((0, 1, 0), (1, 1, 0), (1, 0, 0), (0, 0, 0)))]
    cache = {}
    for (x, y, z), c in vox.v.items():
        for d, quad in dirs:
            if (x + d[0], y + d[1], z + d[2]) in vox.v:
                continue
            vs = []
            for o in quad:
                k = (x + o[0], y + o[1], z + o[2])
                if k not in cache:
                    cache[k] = bm.verts.new((k[0] * u, k[1] * u, k[2] * u))
                vs.append(cache[k])
            f = bm.faces.new(vs)
            f.material_index = c
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ── props ──────────────────────────────────────────────────
def tree_conifer():
    r = random.Random(4)
    v = Vox(['#5b3a22', '#2f6b34', '#3b8040', '#27592c', '#4a954a'], U)
    v.box(-1, -1, 0, 1, 1, 6, 0)                       # trunk
    tiers = [(8, 5.6, 6), (6, 4.8, 5), (4, 3.8, 5), (2, 2.8, 4), (0, 1.8, 3)]
    z = 5
    for i, (_, rad, hgt) in enumerate(tiers):
        for dz in range(hgt):
            rr = rad * (1 - dz / (hgt + 1.0))
            for x in range(-7, 7):
                for y in range(-7, 7):
                    d = math.hypot(x + 0.5, y + 0.5)
                    if d <= rr + r.uniform(-0.35, 0.35):
                        shade = 1 if (x + y + dz) % 5 else 2
                        if d > rr - 0.9 and dz < hgt - 1:
                            shade = 3
                        v.put(x, y, z + dz, shade)
        z += hgt - 2
    v.put(0, 0, z + 1, 4)
    return v


def tree_broadleaf():
    r = random.Random(9)
    v = Vox(['#5b3a22', '#3e8a38', '#4fa343', '#2f7230', '#6bb85a'], U)
    v.box(-1, -1, 0, 1, 1, 8, 0)
    for bx, by, bz, rad in [(0, 0, 13, 7), (-5, 1, 11, 4.5), (5, -1, 11, 4.5),
                            (1, 5, 11, 4), (-1, -5, 12, 4)]:
        v.ball(bx, by, bz, rad, rad, rad * 0.85, lambda x, y, z: (
            4 if z > 14 and r.random() < 0.5 else
            (3 if z < 10 else (2 if r.random() < 0.6 else 1))), r, 0.18)
    return v


def _stone(seed, blobs, palette=None):
    r = random.Random(seed)
    v = Vox(palette or ['#8c8a84', '#a3a19a', '#6f6d68', '#b7b5ad'], U)
    for bx, by, bz, rx, ry, rz in blobs:
        v.ball(bx, by, bz, rx, ry, rz, lambda x, y, z: (
            3 if z >= bz + rz * 0.5 else (2 if (x - y) % 4 == 0 and z < bz
                                           else (1 if r.random() < .5 else 0))),
               r, 0.12)
    return v


def stone():
    return _stone(2, [(0, 0, 3, 5, 4, 3), (5, 2, 2, 3, 3, 2),
                      (-4, 3, 2, 3, 2.5, 2)])


def stone_flat():
    return _stone(3, [(0, 0, 1.5, 8, 5, 1.8), (6, 3, 1, 3.5, 2.5, 1.2)])


def stone_boulder():
    return _stone(5, [(0, 0, 5, 6.5, 6, 5), (-5, 3, 2, 2.5, 2.5, 2)])


def _flowers(seed, head, head2):
    r = random.Random(seed)
    v = Vox(['#3f7a2e', head, head2, '#2d5e22', '#6aa04a'], U)
    for _ in range(9):
        x, y = r.randint(-6, 6), r.randint(-5, 5)
        h = r.randint(3, 6)
        for z in range(h):
            v.put(x, y, z, 0)
        for dx, dy, dz in [(0, 0, 0), (1, 0, 0), (-1, 0, 0), (0, 1, 0),
                           (0, 0, 1)]:
            if r.random() < 0.85:
                v.put(x + dx, y + dy, h + dz, 1 if r.random() < .6 else 2)
        for dx in (-1, 1):
            v.put(x + dx, y, 1, 3)
    for _ in range(14):
        v.put(r.randint(-7, 7), r.randint(-6, 6), 0, 4)
    return v


def flower_heather():
    return _flowers(7, '#a35fbf', '#c88ae0')


def flower_gorse():
    return _flowers(8, '#f0c322', '#ffe066')


def driftwood():
    r = random.Random(11)
    v = Vox(['#9a8566', '#7d6a4f', '#b8a583', '#5e4f3a'], U)
    for x in range(-9, 10):
        for dy in (0, 1):
            for dz in (0, 1):
                v.put(x, dy + (x // 6), dz, 0 if r.random() < .6 else 1)
    v.box(-3, 2, 0, -1, 5, 2, 1)
    v.box(4, -3, 0, 6, 0, 2, 0)
    for x in range(-9, 10, 3):
        v.put(x, 0, 2, 2)
    return v


def shell():
    v = Vox(['#f0d7c0', '#e0b99c', '#fff0e2'], U)
    for x in range(-2, 3):
        for y in range(-2, 3):
            if abs(x) + abs(y) <= 3:
                v.put(x, y, 0, 0 if (x + y) % 2 else 1)
    for x in range(-1, 2):
        for y in range(-1, 2):
            if abs(x) + abs(y) <= 1:
                v.put(x, y, 1, 2)
    v.put(0, 0, 2, 0)
    return v


def dirt_patch():
    r = random.Random(13)
    v = Vox(['#8a6a43', '#7a5c38', '#9c7b50', '#6b4f2f'], U)
    for x in range(-9, 10):
        for y in range(-8, 9):
            d = (x / 9.5) ** 2 + (y / 8.5) ** 2 + r.uniform(-0.18, 0.18)
            if d <= 1.0:
                v.put(x, y, 0, r.choice([0, 0, 1, 2, 3]))
    return v


PROPS = {
    'tree_conifer': tree_conifer, 'tree_broadleaf': tree_broadleaf,
    'stone': stone, 'stone_flat': stone_flat, 'stone_boulder': stone_boulder,
    'flower_heather': flower_heather, 'flower_gorse': flower_gorse,
    'driftwood': driftwood, 'shell': shell, 'dirt_patch': dirt_patch,
}


# ── ground ─────────────────────────────────────────────────
def ground_field(cells=2.0, margin=1.0):
    """A field of block columns a block or two high, much larger than the
    frame, so the camera never sees an edge."""
    r = random.Random(21)
    n = int((cells + 2 * margin) / GU)
    v = Vox(['#4a8a32', '#52933a', '#5d9f42', '#417c2c', '#559b3c',
             '#6e5a38', '#386c27'], GU)
    # smooth value noise for the heights
    g = {}
    def noise(x, y, f=5):
        gx, gy = x // f, y // f
        def n(a, b):
            if (a, b) not in g:
                g[(a, b)] = r.random()
            return g[(a, b)]
        tx, ty = (x % f) / f, (y % f) / f
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = n(gx, gy) * (1 - tx) + n(gx + 1, gy) * tx
        b = n(gx, gy + 1) * (1 - tx) + n(gx + 1, gy + 1) * tx
        return a * (1 - ty) + b * ty
    for x in range(-n // 2, n // 2):
        for y in range(-n // 2, n // 2):
            h = 1 + (1 if noise(x, y) > 0.58 else 0) + \
                (1 if noise(x + 99, y + 7, 3) > 0.8 else 0)
            for z in range(h):
                top = (z == h - 1)
                if top:
                    t = noise(x + 40, y + 40, 2)
                    c = 1 if t < 0.3 else (0 if t < 0.55 else (2 if t < 0.8
                                                                   else 4))
                    if r.random() < 0.012:
                        c = 5
                    if r.random() < 0.05:
                        c = 3
                else:
                    c = 6
                v.put(x, y, z, c)
    return v


# ── scene + render ─────────────────────────────────────────
def fit_iso_camera(pad=0.02, bbox_obj=None, frame_wh=None):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.new('cam', cam_data)
    scene.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(90 - rb.ELEVATION), 0, math.radians(45))
    scene.camera = cam
    q = Euler(cam.rotation_euler).to_quaternion()
    right, up, back = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), \
        q @ Vector((0, 0, 1))
    return cam, right, up, back


def render_prop(name, outdir, samples):
    vox = PROPS[name]()
    # stand it on the origin, centred on x/y
    xs = [k[0] for k in vox.v]
    ys = [k[1] for k in vox.v]
    cx, cy = (min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2
    vox.v = {(x, y, z): c for (x, y, z), c in vox.v.items()}
    ob = build_mesh(vox)
    ob.location = (-cx * vox.u, -cy * vox.u, 0)
    K.lighting()
    cam, right, up, back = fit_iso_camera()
    bpy.context.view_layer.update()
    pts = []
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        pts.append((p.dot(right), p.dot(up)))
    x0, x1 = min(p[0] for p in pts), max(p[0] for p in pts)
    y0, y1 = min(p[1] for p in pts), max(p[1] for p in pts)
    w, h = x1 - x0, y1 - y0
    pad = 0.06 * max(w, h)
    W, H = SIZES[name]
    # render big, then crop+fit
    R = 4
    ow, oh = int((w + 2 * pad) / max(w, h) * 900), int((h + 2 * pad) / max(w, h) * 900)
    ow, oh = max(ow, 8), max(oh, 8)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = ow, oh
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(w + 2 * pad, h + 2 * pad)
    cam.data.shift_x = 0
    cam.data.shift_y = 0
    ax, ay = (x0 + x1) / 2, (y0 + y1) / 2
    cam.location = right * ax + up * ay + back * 60
    cam.data.clip_start = 0.1
    cam.data.clip_end = 200
    setup_cycles(scene, samples, transparent=True)
    path = os.path.join(outdir, f'{FILES[name]}_raw.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    fit_to_canvas(path, os.path.join(outdir, f'{FILES[name]}.png'), W, H)


def setup_cycles(scene, samples, transparent):
    scene.render.engine = 'CYCLES'
    cy = scene.cycles
    cy.device = 'CPU'
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.use_denoising = True
    try:
        cy.denoiser = 'OPENIMAGEDENOISE'
    except TypeError:
        pass
    cy.max_bounces = 4
    scene.render.film_transparent = transparent
    scene.render.filter_size = 0.8
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = 0.3
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'


def fit_to_canvas(src, dst, W, H):
    """Crop to what is drawn, scale to fit W x H, stand it bottom-centre."""
    img = bpy.data.images.load(src)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.where(a[..., 3] > 0.02)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    ch, cw = a.shape[:2]
    k = min((W * 0.98) / cw, (H * 0.98) / ch)
    nw, nh = max(1, int(cw * k)), max(1, int(ch * k))
    tmp = bpy.data.images.new('crop', cw, ch, alpha=True)
    tmp.colorspace_settings.name = 'Non-Color'
    tmp.alpha_mode = 'STRAIGHT'
    tmp.pixels = a.ravel().tolist()
    tmp.scale(nw, nh)
    b = np.array(tmp.pixels[:], dtype=np.float32).reshape(nh, nw, 4)
    out = np.zeros((H, W, 4), dtype=np.float32)
    ox = (W - nw) // 2
    out[0:nh, ox:ox + nw] = b        # image rows are bottom-up: row 0 = foot
    res = bpy.data.images.new('out', W, H, alpha=True)
    res.colorspace_settings.name = 'Non-Color'
    res.alpha_mode = 'STRAIGHT'
    res.pixels = out.ravel().tolist()
    res.file_format = 'PNG'
    res.filepath_raw = dst
    res.save()


def render_tile(outdir, samples):
    ob = build_mesh(ground_field(), 'ground')
    K.lighting()
    scene = bpy.context.scene
    # the map's own swatch frame: a 2 x 2 patch, diamond bounding box 2:1
    cells = 2.0
    scale = 4
    rb.frame(cells, cells, scale, 0.5, fit=False)
    setup_cycles(scene, samples, transparent=False)
    scene.view_settings.exposure = -0.35
    path = os.path.join(outdir, 'grass_tile.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print('tile', scene.render.resolution_x, 'x', scene.render.resolution_y)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--what', default='all')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    args = ap.parse_args(argv)
    outdir = os.path.abspath(args.out)
    os.makedirs(outdir, exist_ok=True)
    names = (['tile'] + list(PROPS)) if args.what == 'all' else [args.what]
    for n in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        if n == 'tile':
            render_tile(outdir, args.samples)
        else:
            render_prop(n, outdir, args.samples)
        print('done', n, flush=True)


if __name__ == '__main__':
    main()
