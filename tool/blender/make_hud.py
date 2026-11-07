"""The main screen's tower, wall and bell sign, in the buildings' voxel look.

    blender --background --python tool/blender/make_hud.py -- \
        tower_flag tower wall_mid pier_r pier_l sign [--samples 96] [--px 16]

User 2026-11-04: "kannst du es auch in der gleichen Voxeloptik machen wie die
Gebäude". The pieces go through the buildings' own path (fw_kit materials, the
union voxeliser, the golden-hour light, Cycles), only the camera differs: it is
orthographic and looks straight along +y, pitched down by PITCH, so a wall
reads as a front elevation with a sliver of its top, the way the HUD shows it.

Units: everything is laid out in VOXELS (v). One voxel is VOXDP dp on screen
(lib/core/theme/castle_hud.dart, Castle.voxDp) and PX pixels in the render.
The front face of every piece stands on y = 0, so the bottom edge of the
picture is the bottom of the front face — the screen's own bottom edge.

Writes assets/images/hud/<piece>.webp and docs/renders/hud/<piece>.png and
prints each picture's size in voxels (what Castle.* must be set to).
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import camp_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import voxelizer  # noqa: E402
from pro_kit import beam, box, cyl, ellipsoid, rbox  # noqa: E402

V = 0.6 / 17          # one voxel in tiles: the tower's shaft is 17 voxels across
PITCH = 24.0          # degrees the camera looks down
COS, SIN = math.cos(math.radians(PITCH)), math.sin(math.radians(PITCH))

SHAFT = 17            # tower diameter, voxels
SHAFT_H = 22
PERIOD = 8            # one merlon + one gap
BODY = 14             # wall body height, coping included
MERLON = 2
DEPTH = 5


def v(n):
    return n * V


# ── the pieces ──────────────────────────────────────────────
def tower(M, flag):
    r = SHAFT / 2
    cy = v(r + 0.5)                                    # the front stands on y = 0
    tile = K.plain('hud_tile', '#c9622e', rough=0.7, bump=0.45, bump_scale=50,
                   vary=0.18, speck='#e58b4c')
    cyl(0, cy, 0, v(r + 0.5), v(r + 0.5), v(2), M['stone_dk'], seg=28)
    cyl(0, cy, 0, v(r), v(r), v(SHAFT_H), M['stone'], seg=28)
    cyl(0, cy, v(SHAFT_H), v(r + 0.5), v(r + 0.5), v(2), M['stone_dk'], seg=28)
    # the cone: one stepped course per voxel of height, so every step reads as a
    # row of tiles (a smooth cone's texture runs up the slope like bamboo)
    n = 13
    for i in range(n):
        rr = (r + 0.5) * (1 - i / (n + 0.8))
        cyl(0, cy, v(SHAFT_H + 2 + i), v(rr), v(rr), v(1.02), tile, seg=28)
    ellipsoid(0, cy, v(SHAFT_H + 15.6), v(0.9), v(0.9), v(1.2), M['gold'], seg=10, rings=8)
    # a lit slit, set into the front
    rbox((0, v(-0.1), v(14)), (v(1.7), v(1.6), v(4.4)), (0, 0, 0), M['pane_glow'], bevel=0)
    if flag:
        beam((0, cy, v(SHAFT_H + 16)), (0, cy, v(SHAFT_H + 22)), v(0.3), M['iron'], bevel=0)
        rbox((v(1.7), cy, v(SHAFT_H + 20.6)), (v(3.2), v(0.6), v(1.8)), (0, 0, 0), M['red'], bevel=0)


def wall(M, x0, x1, pier=None):
    """A wall front-on from x0 to x1 (voxels): body, coping, merlons; `pier`
    ('l' or 'r') adds the end pier, 3 voxels wide."""
    xa, xb = x0, x1
    if pier == 'l':
        xa = x0 + 3
    if pier == 'r':
        xb = x1 - 3
    box(v((xa + xb) / 2), v(DEPTH / 2), 0, v(xb - xa), v(DEPTH), v(BODY - 1), M['stone'], bevel=0)
    box(v((xa + xb) / 2), v(DEPTH / 2), v(BODY - 1), v(xb - xa), v(DEPTH + 1), v(1), M['stone_dk'], bevel=0)
    k0 = math.floor(xa / PERIOD) - 1
    k1 = math.ceil(xb / PERIOD) + 1
    for k in range(k0, k1):
        ma, mb = k * PERIOD + 1.5, k * PERIOD + 6.5
        ma, mb = max(ma, xa), min(mb, xb)
        if mb - ma < 1:
            continue
        box(v((ma + mb) / 2), v(DEPTH / 2), v(BODY), v(mb - ma), v(DEPTH - 2), v(MERLON), M['stone'], bevel=0)
    if pier:
        px = x0 if pier == 'l' else x1 - 3
        box(v(px + 1.5), v(DEPTH / 2), 0, v(3), v(DEPTH), v(BODY + MERLON), M['stone'], bevel=0)
        box(v(px + 1.5), v(DEPTH / 2), v(BODY + MERLON), v(4), v(DEPTH + 1), v(1), M['stone_dk'], bevel=0)


def sign(M):
    # arm out of the right edge (x = 14), chains, board
    beam((v(0.4), v(1), v(13)), (v(14), v(1), v(13)), v(0.35), M['iron'], bevel=0)
    beam((v(0.4), v(1), v(13)), (v(0.4), v(1), v(11.2)), v(0.35), M['iron'], bevel=0)
    for x in (2.2, 10.6):
        beam((v(x), v(1), v(12.8)), (v(x), v(1), v(8.8)), v(0.25), M['iron'], bevel=0)
    box(v(6.4), v(1), v(0.2), v(11), v(1.8), v(8.8), M['planks'], bevel=0)
    for z0, z1 in ((0.2, 1.1), (8.1, 9.0)):
        box(v(6.4), v(1), v(z0), v(11.6), v(2.2), v(z1 - z0), M['timber'], bevel=0)
    for x0, x1 in ((0.6, 1.5), (11.3, 12.2)):
        box(v((x0 + x1) / 2), v(1), v(0.2), v(x1 - x0), v(2.2), v(8.8), M['timber'], bevel=0)
    for x in (2.2, 10.6):
        for z in (1.8, 7.0):
            box(v(x), v(0.1), v(z), v(0.6), v(0.5), v(0.6), M['iron'], bevel=0)


def fit(piece):
    """(sx0, sx1, sy0, sy1) in voxels — the picture's window."""
    if piece in ('tower', 'tower_flag'):
        top = (SHAFT_H + 23 if piece == 'tower_flag' else SHAFT_H + 18)
        return (-(SHAFT / 2 + 0.5), SHAFT / 2 + 0.5, 0, top * COS + (SHAFT + 1) * SIN)
    h = (BODY + MERLON + 1) * COS + (DEPTH + 1) * SIN
    if piece == 'wall_mid':
        return (2 * PERIOD, 3 * PERIOD, 0, h)
    if piece == 'pier_r':
        return (4 * PERIOD - 3 - 0.5, 4 * PERIOD + 0.5, 0, h)
    if piece == 'pier_l':
        return (-0.5, 3.5, 0, h)
    if piece == 'sign':
        return (0, 14, 0, 13.6 * COS + 2 * SIN)
    raise SystemExit('unknown piece ' + piece)


def build(piece, M):
    if piece == 'tower':
        tower(M, False)
    elif piece == 'tower_flag':
        tower(M, True)
    elif piece == 'wall_mid':
        wall(M, -PERIOD, 6 * PERIOD)
    elif piece == 'pier_r':
        wall(M, 0, 4 * PERIOD, 'r')
    elif piece == 'pier_l':
        wall(M, 0, 4 * PERIOD, 'l')
    elif piece == 'sign':
        sign(M)


# ── camera, render, ship ────────────────────────────────────
def camera(win, px):
    sx0, sx1, sy0, sy1 = (c * V for c in win)
    sc = bpy.context.scene
    sc.render.resolution_x = round((sx1 - sx0) / V * px)
    sc.render.resolution_y = round((sy1 - sy0) / V * px)
    sc.render.film_transparent = True
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(90 - PITCH), 0, 0)
    sc.camera = cam
    q = Euler(cam.rotation_euler).to_quaternion()
    right, up, back = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), q @ Vector((0, 0, 1))
    cam.data.ortho_scale = max(sx1 - sx0, sy1 - sy0)
    cam.data.clip_end = 200
    cam.location = right * ((sx0 + sx1) / 2) + up * ((sy0 + sy1) / 2) + back * 40


def cycles(samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    cy = sc.cycles
    cy.device = 'CPU'
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.use_denoising = True
    try:
        cy.denoiser = 'OPENIMAGEDENOISE'
    except TypeError:
        pass
    cy.max_bounces = 6
    cy.diffuse_bounces = 3
    cy.glossy_bounces = 3
    sc.render.filter_size = 0.9
    vs = sc.view_settings
    names = vs.bl_rna.properties['view_transform'].enum_items.keys()
    vs.view_transform = 'AgX' if 'AgX' in names else 'Filmic'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast', 'AgX - Punchy', 'Punchy'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = 0.3


def to_webp(png, dst):
    sc = bpy.context.scene
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    img = bpy.data.images.load(png)
    st = sc.render.image_settings
    st.file_format = 'WEBP'
    st.color_mode = 'RGBA'
    st.quality = 90
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save_render(dst, scene=sc)
    bpy.data.images.remove(img)
    print('SHIPPED', dst, os.path.getsize(dst), 'bytes')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('pieces', nargs='+')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--px', type=int, default=16, help='pixels per voxel')
    args = ap.parse_args(argv)
    for piece in args.pieces:
        rb.clear()
        K._mats.clear()
        M = camp_kit.mats()
        build(piece, M)
        voxelizer.voxelize(V, piece + '_voxel')
        K.lighting(azimuth=-45)
        win = fit(piece)
        camera(win, args.px)
        cycles(args.samples)
        png = os.path.join(ROOT, 'docs', 'renders', 'hud', piece + '.png')
        os.makedirs(os.path.dirname(png), exist_ok=True)
        K.render(png)
        to_webp(png, os.path.join(ROOT, 'assets', 'images', 'hud', piece + '.webp'))
        print('SIZE_VOXELS', piece, round(win[1] - win[0], 3), 'x', round(win[3] - win[2], 3))


if __name__ == '__main__':
    main()
