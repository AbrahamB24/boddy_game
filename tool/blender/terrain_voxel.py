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
# ONE BLOCK OF GROUND = ONE BLOCK OF A BUILDING (user 2026-11-05: "Voxelgrösse des
# Bodens exakt denjenigen der Gebäude anpassen"): the very constant
# fw_kit.VOX is derived from, in cells (= tiles). Props that stand on the ground
# next to buildings (flowers, bushes) use it too.
VOX = 4.1822 / (0.99 * 256)
GU = VOX

# The ground swatch: TILE_CELLS x TILE_CELLS cells at TILE_SCALE x the canvas
# (the buildings' art is 4x the canvas too, so a block is 4 px in both). The
# app draws it at 1 / TILE_SCALE. 4 cells, 8 once mirrored (a 2-cell swatch
# showed its pattern every 4 cells).
TILE_CELLS = 4.0
TILE_SCALE = 5 * 960 / 1227     # = make_prop.PROP_PX, the buildings' own density

# Ground greens: the buildings' leaf / leaf2 family (fw_kit: #4f8a24, #6a9a2a).
GRASS_MID, GRASS_DARK, GRASS_LIGHT = '#548e26', '#487f22', '#639529'
GRASS_DEEP, GRASS_BRIGHT, GRASS_SIDE = '#437a20', '#6f9d2c', '#4a8224'


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


PROP_FLOWERS = ['#d8352c', '#4b6fd8', '#f4f0e6', '#e982b4', '#f2cf3a']


def flower_heather():
    """A flower patch exactly like the ones by the buildings (fw_kit
    flower_patch): stems 3-6 blocks tall, a small head of the kit's own
    colours, a few tufts. Built at the buildings' block size (VOX)."""
    r = random.Random(7)
    v = Vox(['#4f7a22'] + PROP_FLOWERS + ['#6a9a2a', '#8aa636'], VOX)
    for _ in range(26):
        x, y = r.randint(-14, 14), r.randint(-12, 12)
        h = r.randint(3, 6)
        for z in range(h):
            v.put(x, y, z, 0)
        c = 1 + r.randrange(5)
        v.put(x, y, h, c)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if r.random() < 0.55:
                v.put(x + dx, y + dy, h - 1, c)
        v.put(x, y, h + 1, c)
    for _ in range(34):
        x, y = r.randint(-15, 15), r.randint(-13, 13)
        if (x, y, 0) not in v.v:
            v.put(x, y, 0, 6)
            if r.random() < 0.5:
                v.put(x, y, 1, 7)
    return v


def flower_gorse():
    """A bush exactly like the buildings' (fw_kit bush): six overlapping
    rounded masses in leaf / leaf2, dotted with the kit's flowers."""
    r = random.Random(8)
    v = Vox(['#4f8a24', '#6a9a2a', '#437a20', '#8aa636'] +
            PROP_FLOWERS, VOX)
    R = 0.22 / VOX
    for i in range(6):
        a = r.uniform(0, 6.28)
        d = r.uniform(0, R * 0.7)
        rr = R * r.uniform(0.5, 0.85)
        v.ball(math.cos(a) * d, math.sin(a) * d, rr * 0.75, rr, rr, rr * 0.85,
               lambda x, y, z: (1 if r.random() < 0.5 else 0)
               if z > rr * 0.9 else (2 if z < 3 else (0 if r.random() < 0.5 else 1)),
               r, 0.10)
    top = {}
    for (x, y, z) in v.v:
        if z > top.get((x, y), -1):
            top[(x, y)] = z
    for (x, y), z in top.items():
        if z >= 5 and r.random() < 0.045:
            v.put(x, y, z + 1, 4 + r.randrange(5))
    return v
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
def ground_field(cells=TILE_CELLS, margin=1.0):
    # A diamond field must contain the frame's whole RECTANGLE (a diamond does
    # not fill its own bounding box): side >= 2 * cells.
    margin = cells / 2 + 1
    """A field of block columns a block or two high, much larger than the
    frame, so the camera never sees an edge."""
    r = random.Random(21)
    n = int((cells + 2 * margin) / GU)
    # Greens taken from the buildings' own bushes and lawn (fw_kit leaf / leaf2),
    # not a minty green of their own (user 2026-11-05: "die Farbe des Grases
    # anpassen, dass es zu den Gebäuden passt"). 7-11 flower heads, 12 stem,
    # 13 tuft: the same colours fw_kit gives its flower boxes and bushes.
    v = Vox([GRASS_MID, GRASS_DARK, GRASS_LIGHT, GRASS_DEEP, GRASS_BRIGHT,
             '#6e5a38', GRASS_SIDE,
             '#d8352c', '#4b6fd8', '#f4f0e6', '#e982b4', '#f2cf3a',
             '#4f7a22', GRASS_BRIGHT], GU)
    # smooth value noise for the heights
    g = {}
    def noise(x, y, f=20):
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
            h = 1
            for z in range(h):
                top = (z == h - 1)
                if top:
                    t = noise(x + 40, y + 40, 8)
                    c = 1 if t < 0.3 else (0 if t < 0.55 else (2 if t < 0.8
                                                                   else 4))
                    if r.random() < 0.28:      # per-block tone: the voxel grid shows
                        c = r.choice([0, 1, 2, 4])
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


DECOR = {          # name: voxels (dx, dy, dz, palette index)
    'tuft': [(0, 0, 0, 13)],
    'tuft2': [(0, 0, 0, 13), (0, 0, 1, 13)],
}
for _i, _c in enumerate(range(7, 12)):
    DECOR[f'flower{_i}'] = [(0, 0, 0, 12), (0, 0, 1, _c)]


def render_decor(outdir, samples):
    """Each bit of ground cover as its own upright, transparent sprite at the
    tile's own scale. They are composited onto the finished (mirrored) tile
    by pack_tile.py: baked into the tile they came out UPSIDE DOWN in every
    mirrored copy (user 2026-11-05: "einige Blumen auf dem Kopf")."""
    pal = [GRASS_MID, GRASS_DARK, GRASS_LIGHT, GRASS_DEEP, GRASS_BRIGHT,
           '#6e5a38', GRASS_SIDE, '#d8352c', '#4b6fd8', '#f4f0e6',
           '#e982b4', '#f2cf3a', '#4f7a22', GRASS_BRIGHT]
    for name, vs in DECOR.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        v = Vox(pal, GU)
        for dx, dy, dz, c in vs:
            v.put(dx, dy, dz, c)
        build_mesh(v, 'decor')
        K.lighting()
        scene = bpy.context.scene
        rb.frame(2.0, 2.0, TILE_SCALE, 0.5, fit=False)
        setup_cycles(scene, samples, transparent=True)
        scene.view_settings.exposure = -1.05
        scene.render.filepath = os.path.join(outdir, f'decor_{name}.png')
        bpy.ops.render.render(write_still=True)
        print('decor', name, scene.render.resolution_x, scene.render.resolution_y)


def render_tile(outdir, samples):
    ob = build_mesh(ground_field(), 'ground')
    K.lighting()
    scene = bpy.context.scene
    # the map's own swatch frame: a 2 x 2 patch, diamond bounding box 2:1
    cells = TILE_CELLS
    scale = TILE_SCALE
    rb.frame(cells, cells, scale, 0.5, fit=False)
    setup_cycles(scene, samples, transparent=False)
    scene.view_settings.exposure = -1.05
    path = os.path.join(outdir, 'grass_tile.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print('tile', scene.render.resolution_x, 'x', scene.render.resolution_y)



# ── sand and water: the same flat voxel ground, other colours ──────────
SAND = ['#e6d3a4', '#decb98', '#eddcb2', '#d6c08c', '#f2e6c4',   # 0-4 tones
        '#b09a6c', '#bdb49c', '#c9ae78']                         # 5-7 flecks                         # 5-7 flecks
WATER = ['#2fa6cc', '#279cc4', '#3bb4d6', '#2092b8', '#8fe0ee',  # 0-3 tones, 4 crest
         '#1c88b0']


def _value_noise(r):
    g = {}

    def noise(x, y, f=20):
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
    return noise


def flat_field(palette, pick, seed, cells=TILE_CELLS):
    """One block thick, no relief: what makes it voxel is the per-block tone
    (same size as the grass's and the buildings')."""
    r = random.Random(seed)
    noise = _value_noise(r)
    n = int((2 * cells + 2) / GU)
    v = Vox(palette, GU)
    for x in range(-n // 2, n // 2):
        for y in range(-n // 2, n // 2):
            v.put(x, y, 0, pick(x, y, r, noise))
    return v


def sand_pick(x, y, r, noise):
    t = noise(x, y, 14)
    c = 3 if t < 0.28 else (0 if t < 0.55 else (2 if t < 0.82 else 4))
    if r.random() < 0.30:
        c = r.choice([0, 1, 2, 3])
    if r.random() < 0.035:
        c = r.choice([5, 6, 7])
    return c


def water_pick(x, y, r, noise):
    t = noise(x, y, 16)
    c = 3 if t < 0.3 else (0 if t < 0.6 else 2)
    # ripples: short crest dashes along the ground's diagonal
    if (x + y) % 13 == 0 and noise(x + 300, y, 7) > 0.62:
        c = 4
    if r.random() < 0.25:
        c = r.choice([0, 1, 2, 3])
    if r.random() < 0.006:
        c = 4
    return c


def render_flat(outdir, samples, name):
    pal, pick, seed = {'sand': (SAND, sand_pick, 31),
                       'water': (WATER, water_pick, 41)}[name]
    ob = build_mesh(flat_field(pal, pick, seed), name)
    K.lighting()
    scene = bpy.context.scene
    rb.frame(TILE_CELLS, TILE_CELLS, TILE_SCALE, 0.5, fit=False)
    setup_cycles(scene, samples, transparent=False)
    scene.view_settings.exposure = -0.3 if name == 'sand' else -0.7
    scene.render.filepath = os.path.join(outdir, f'{name}_tile.png')
    bpy.ops.render.render(write_still=True)
    print('tile', name, scene.render.resolution_x, 'x', scene.render.resolution_y)



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
    if args.what in ('sand', 'water'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        render_flat(outdir, args.samples, args.what)
        return
    if args.what == 'decor':
        render_decor(outdir, args.samples)
        return
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
