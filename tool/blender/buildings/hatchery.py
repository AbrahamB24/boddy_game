"""The Hatchery: a half-timbered brooding house with a stone tower.

Footprint 4 x 3 tiles (20 x 15 m). The reference building of the Fachwerk
set — the voxel render of THIS model (approved 2026-11-03) fixed the style,
the scale (its door is 1 x 2 m) and the voxel size every other building uses.

Reads as: eggs. All four sides are modelled; the ENTRANCE is the south
side's third cell, where the cobbled path to both doors begins. Moving:
flowers, bushes, flower boxes, the hens (pecking), the guild sign, the
awning's edge, sparks over the egg; the egg glows, lanterns flicker. Nests with clutches in the yard, a glowing egg on a stone
shrine, an egg-shaped gable window, a golden egg on the guild sign and on
both finials, hens, hay.

Layout (x east, y north; the camera looks from +x/-y):

    tower  main house (ridge along x)
           wing (ridge along y, its gable faces the camera)
    courtyard: nests, the glowing egg, hay, coop, awning and table

    blender --background --python tool/blender/make_building.py -- hatchery
"""
import math
import random

import bpy
from mathutils import Vector

from fw_kit import *  # noqa: F401,F403
import pro_kit as K  # noqa: F401

ID = 'hatchery'
W, H = 4, 3
# The chimney pots' mouth (smoke anchor), authoring coordinates.
CHIMNEY = (-0.35, 0.69, G + 1.52 + 1.20)
# the entrance: the south side's third cell, where the cobbled path meets
# the road
ENTRANCE = ('s', 2)
# Light layers. The sparks ('mote') are left out: they drift as their own
# bobbing layers, and a light layer would glow where they USED to be.
GLOW = {
    'pane_glow': ('glow', 0.45, 6.0),
    'lamp': ('flicker', 0.7, 1.0),
    'egg_glow': ('glow', 0.6, 3.2),
}


def materials():
    M = base_materials()
    M['egg_glow'] = plain('egg_glow', '#fff0b0', rough=0.25, bump=0.0,
                          emit='#ffd24a', emit_strength=5.5, vary=0.0)
    M['mote'] = plain('mote', '#fff4c0', rough=0.3, bump=0.0, emit='#ffe9a0',
                      emit_strength=12.0, vary=0.0)
    eggs = {'cream': ('#f1e2bc', '#b99a64'), 'gold': ('#f0bc3e', '#a8741c'),
            'blue': ('#5ba3d6', '#2a5f95'), 'green': ('#8fc766', '#456f2d'),
            'rose': ('#e58a84', '#a04440'), 'brown': ('#c58a54', '#6d4423'),
            'violet': ('#a98ae0', '#5d46a0')}
    for k, (a, b) in eggs.items():
        M['egg_' + k] = plain('egg_' + k, a, rough=0.32, bump=0.05,
                              bump_scale=90, vary=0.07, speck=b)
    M['hen_w'] = plain('hen_w', '#f1ead8', rough=0.9, bump=0.5, bump_scale=70)
    M['hen_r'] = plain('hen_r', '#b5622c', rough=0.9, bump=0.5, bump_scale=70)
    M['comb'] = plain('comb', '#cc2a24', rough=0.6, bump=0.0)
    M['beak'] = plain('beak', '#e8a22a', rough=0.5, bump=0.0)
    return M


# ── props ────────────────────────────────────────────────────
def egg(M, key, x, y, z, r, tilt=0.0, glow=False):
    mat = M['egg_glow'] if glow else M['egg_' + key]
    return ellipsoid(x, y, z + r * 1.18, r, r, r * 1.3, mat, egg=0.20,
                     tilt=(0, tilt, 0))


def nest(M, x, y, r=0.12, eggs=('cream', 'blue'), seed=0):
    rnd = random.Random(seed)
    z = G
    cyl(x, y, z, r * 0.95, r * 0.8, 0.025, M['straw_dk'], seg=14)
    lst = []
    n = 46
    for i in range(n):
        a = 2 * math.pi * i / n + rnd.uniform(-0.1, 0.1)
        rr = r * rnd.uniform(0.92, 1.08)
        for layer in range(3):
            aa = a + layer * 0.5
            p0 = Vector((x + math.cos(aa) * rr, y + math.sin(aa) * rr,
                         z + 0.02 + layer * 0.016))
            aa2 = aa + 0.30 + rnd.uniform(-0.05, 0.1)
            p1 = Vector((x + math.cos(aa2) * rr * 1.04, y + math.sin(aa2) * rr * 1.04,
                         z + 0.034 + layer * 0.016 + rnd.uniform(0, 0.01)))
            lst.append((p0, p1, 0.011))
    strands(lst, M['straw'], 'nest')
    k = len(eggs)
    for i, e in enumerate(eggs):
        a = 2 * math.pi * i / k + seed
        egg(M, e, x + math.cos(a) * r * 0.32 * (k > 1), y + math.sin(a) * r * 0.32 * (k > 1),
            z + 0.03, r * 0.52, tilt=rnd.uniform(-0.25, 0.25))



def hen(M, x, y, rot, key='hen_w'):
    c, s = math.cos(rot), math.sin(rot)

    def at(dx, dz):
        return (x + dx * c, y + dx * s, G + dz)
    ellipsoid(*at(0, 0.075), 0.075, 0.052, 0.058, M[key], tilt=(0, 0, rot))
    ellipsoid(*at(0.075, 0.12), 0.03, 0.026, 0.034, M[key], seg=10, rings=8)
    ellipsoid(*at(0.098, 0.115), 0.016, 0.01, 0.01, M['beak'], seg=6, rings=4)
    ellipsoid(*at(0.072, 0.158), 0.016, 0.008, 0.018, M['comb'], seg=8, rings=6)
    ellipsoid(*at(-0.08, 0.115), 0.036, 0.016, 0.05, M[key], seg=10, rings=8,
              tilt=(0, math.radians(-35), rot))
    for sg in (-1, 1):
        px = x + (-s * sg * 0.018)
        py = y + (c * sg * 0.018)
        beam((px, py, G), (px, py, G + 0.04), 0.008, M['beak'], bevel=0)



# ── the build ────────────────────────────────────────────────
def build():
    """The smooth model, yard at z = G, no ground (make_building lowers it)."""
    random.seed(11)
    M = materials()

    # path ---------------------------------------------------
    # from the ENTRANCE cell's outer edge (where the road is) to both doors
    ex, ey = entrance_point(W, H, *ENTRANCE)
    paths = [[(ex, ey), (0.42, -1.22), (0.40, -0.75), (0.40, -0.25),
              (0.40, 0.10)],
             [(0.42, -1.25), (0.80, -1.33), (1.17, -1.30)]]
    rnd = random.Random(5)
    for pl in paths:
        for i in range(len(pl) - 1):
            a, b = Vector(pl[i] + (0,)), Vector(pl[i + 1] + (0,))
            L =(b - a).length
            n = int(L / 0.115) + 1
            dirv = (b - a).normalized()
            nrm = Vector((-dirv.y, dirv.x, 0))
            for k in range(n + 1):
                for side in (-0.135, 0.0, 0.135):
                    p = a + dirv * (L * k / max(n, 1)) + nrm * (side + rnd.uniform(-0.03, 0.03))
                    p += dirv * rnd.uniform(-0.03, 0.03)
                    sx = rnd.uniform(0.085, 0.135)
                    sy = rnd.uniform(0.085, 0.125)
                    ellipsoid(p.x, p.y, G + 0.004, sx * 0.62, sy * 0.62, 0.03,
                              M['cobble'], seg=12, rings=7,
                              tilt=(0, 0, rnd.uniform(0, 3.14)))

    # tower ------------------------------------------------
    tx, ty, tr = -1.45, 0.52, 0.44
    cyl(tx, ty, G, tr + 0.04, tr + 0.02, 0.1, M['stone_dk'], seg=24)
    cyl(tx, ty, G + 0.1, tr, tr * 0.93, 1.70, M['stone'], seg=24)
    cyl(tx, ty, G + 1.75, tr * 1.0, tr * 1.12, 0.07, M['stone_dk'], seg=24)
    cone_h, cone_r = 0.95, 0.56
    slant = math.hypot(cone_h, cone_r)
    cm = tex_mat('roofcone', 'clay_roof_tiles_02', tint=(1.0, 0.82, 0.70),
                 sat=1.1, val=1.1, nstr=1.5, vary=0.05,
                 uv_scale=(2 * math.pi * cone_r / 1.55, slant / 1.55))
    cyl(tx, ty, G + 1.82, cone_r, 0.015, cone_h, cm, seg=24, uv=True)
    ellipsoid(tx, ty, G + 1.82 + cone_h + 0.06, 0.045, 0.045, 0.06, M['gold'],
              egg=0.2)
    # arched slit window + door at the tower foot, facing the camera
    for ang, zc, kind in ((-62, 0.95, 'slit'), (-20, 0.95, 'slit'),
                          (-100, 0.30, 'door'),
                          # the back of the tower, for when the map turns
                          (60, 0.95, 'slit'), (140, 0.95, 'slit'),
                          (200, 1.40, 'slit'), (20, 1.40, 'slit')):
        a = math.radians(ang)
        px, py = tx + math.cos(a) * (tr * 0.96), ty + math.sin(a) * (tr * 0.96)
        w, h = (0.07, 0.2) if kind == 'slit' else (0.17, 0.3)
        rbox((px, py, G + zc), (0.045, w + 0.07, h + 0.07), (0, 0, a),
             M['stone_dk'], bevel=0.006)
        rbox((px + math.cos(a) * 0.012, py + math.sin(a) * 0.012, G + zc),
             (0.03, w, h), (0, 0, a),
             M['pane_glow'] if kind == 'slit' else M['planks'], bevel=0.004)

    # main house -------------------------------------------
    mx0, mx1, my0, my1 = -0.95, 1.85, 0.15, 1.30
    low, up = 0.84, 1.52          # lower-floor top and wall top, above G
    j = 0.07                       # jetty
    # stone plinth
    box((mx0 + mx1) / 2, (my0 + my1) / 2, G, mx1 - mx0 + 0.06, my1 - my0 + 0.06,
        0.1, M['stone_dk'], bevel=0.01)
    box((mx0 + mx1) / 2, (my0 + my1) / 2, G + 0.1, mx1 - mx0, my1 - my0,
        low - 0.1, M['plaster'], bevel=0.008)
    # upper floor, jettied south and east
    ux0, ux1, uy0, uy1 = mx0, mx1 + j, my0 - j, my1
    box((ux0 + ux1) / 2, (uy0 + uy1) / 2, G + low, ux1 - ux0, uy1 - uy0,
        up - low, M['plaster'], bevel=0.008)
    # joist ends under the jetty, south and east
    nxs = 15
    for i in range(nxs):
        x = ux0 + 0.1 + (ux1 - ux0 - 0.2) * i / (nxs - 1)
        rbox((x, my0 - j / 2 + 0.005, G + low - 0.03), (0.05, j + 0.02, 0.05),
             (0, 0, 0), M['timber'])
    for i in range(7):
        y = my0 + 0.08 + (my1 - my0 - 0.16) * i / 6
        rbox((mx1 + j / 2 - 0.005, y, G + low - 0.03), (j + 0.02, 0.05, 0.05),
             (0, 0, 0), M['timber'])
    # bressummers
    beam((ux0, my0 - j, G + low + 0.02), (ux1, my0 - j, G + low + 0.02), 0.075,
         M['timber'])
    beam((mx1 + j, my0 - j, G + low + 0.02), (mx1 + j, my1, G + low + 0.02),
         0.075, M['timber'])
    # frames — south
    sxs = wall_frame(M, 's', my0, mx0, 0.60, G + 0.1, G + low, 4, braces=(0,),
                     holes=[(-0.37, 0.17), (0.0, 0.17), (0.40, 0.2)])
    sxu = wall_frame(M, 's', uy0, ux0, ux1, G + low + 0.045, G + up - 0.07, 7,
                     braces=(0, 1, 5, 6), mid=False,
                     holes=[(-0.55, 0.2), (0.02, 0.2)])
    # frames — east (main)
    wall_frame(M, 'e', mx1, my0, my1, G + 0.1, G + low, 3, braces=(0, 2), holes=[(0.72, 0.17)])
    wall_frame(M, 'e', ux1, uy0, uy1, G + low + 0.045, G + up - 0.07, 3, braces=(1,), holes=[(0.72, 0.2), (1.12, 0.12)])
    # openings — south
    window(M, 's', my0, -0.37, G + 0.52, 0.17, 0.22, 'red', planter=['fl_red', 'fl_yel'])
    window(M, 's', my0, 0.0, G + 0.52, 0.17, 0.22, 'teal', glow=True)
    door(M, 's', my0, 0.40, 0.2, 0.40, G + 0.1)
    window(M, 's', uy0, -0.55, G + 1.18, 0.2, 0.26, 'teal', glow=True,
           planter=['fl_pink', 'fl_white'])
    window(M, 's', uy0, 0.02, G + 1.18, 0.2, 0.26, 'red')
    # openings — east
    window(M, 'e', mx1, 0.72, G + 0.52, 0.17, 0.22, 'mustard',
           planter=['fl_blue', 'fl_white'])
    window(M, 'e', ux1, 0.72, G + 1.18, 0.2, 0.26, 'teal', glow=True)
    window(M, 'e', ux1, 1.12, G + 1.18, 0.12, 0.24, 'red')
    # frames + openings — north (the back, modelled for turning the map)
    wall_frame(M, 'n', my1, mx0, mx1, G + 0.1, G + low, 7, braces=(0, 3, 6),
               holes=[(-0.55, 0.17), (0.25, 0.17), (1.05, 0.17), (1.55, 0.17)])
    for a, sh, gl in ((-0.55, 'teal', False), (0.25, 'red', True),
                      (1.05, 'mustard', False), (1.55, 'teal', True)):
        window(M, 'n', my1, a, G + 0.52, 0.17, 0.22, sh, glow=gl)
    wall_frame(M, 'n', uy1, ux0, ux1, G + low + 0.045, G + up - 0.07, 7,
               braces=(0, 1, 5, 6), holes=[(-0.40, 0.2), (0.60, 0.2), (1.40, 0.2)])
    window(M, 'n', uy1, -0.40, G + 1.18, 0.2, 0.26, 'red', glow=True,
           planter=['fl_yel', 'fl_white'])
    window(M, 'n', uy1, 0.60, G + 1.18, 0.2, 0.26, 'teal')
    window(M, 'n', uy1, 1.40, G + 1.18, 0.2, 0.26, 'mustard', glow=True)
    # east gable: plaster, king post and rafters (under the tiles), and the
    # round egg window
    ridge_z = G + up + (my1 - my0 + j) / 2 * TP
    gm = (my0 - j + my1) / 2
    gable_wall(M, 'e', ux1, uy0, uy1, G + up)
    ellipsoid(ux1 + 0.025, gm, G + up + 0.17, 0.016, 0.07, 0.085, M['pane_glow'],
              egg=0.2, seg=14, rings=10)
    # west gable, above the tower's shoulder
    gable_wall(M, 'w', ux0, uy0, uy1, G + up)
    ellipsoid(ux0 - 0.025, gm, G + up + 0.17, 0.016, 0.07, 0.085, M['pane_glow'],
              egg=0.2, seg=14, rings=10)
    # roof
    ridge_z = gable_roof(M, (mx0 + mx1 + j) / 2, (my0 - j + my1) / 2, G + up,
               mx1 + j - mx0, my1 - my0 + j, 'x', M['roof'], oh=0.16, oe=0.17)
    # chimney
    cxh = -0.35
    cyh = (my0 - j + my1) / 2
    box(cxh, cyh, G + up + 0.45, 0.22, 0.22, 0.62, M['stone'], bevel=0.01)
    box(cxh, cyh, G + up + 1.05, 0.28, 0.28, 0.05, M['stone_dk'], bevel=0.008)
    for dx in (-0.05, 0.05):
        cyl(cxh + dx, cyh, G + up + 1.10, 0.036, 0.03, 0.1, M['roof2'], seg=12)
    # east-gable apex finial: a golden egg
    ellipsoid(mx1 + j + 0.17, gm, ridge_z + 0.02, 0.04, 0.04, 0.055, M['gold'],
              egg=0.2)

    # wing ---------------------------------------------------
    wx0, wx1, wy0, wy1 = 0.60, 1.75, -1.15, 0.15
    wh = 1.10
    box((wx0 + wx1) / 2, (wy0 + wy1) / 2, G, wx1 - wx0 + 0.06, wy1 - wy0 + 0.06,
        0.1, M['stone_dk'], bevel=0.01)
    box((wx0 + wx1) / 2, (wy0 + wy1) / 2, G + 0.1, wx1 - wx0, wy1 - wy0 + 0.0,
        wh - 0.1, M['plaster'], bevel=0.008)
    wall_frame(M, 's', wy0, wx0, wx1, G + 0.1, G + wh - 0.07, 4, braces=(0, 3), mid=False,
               holes=[(1.175, 0.2), (0.74, 0.15), (1.61, 0.15)])
    wall_frame(M, 'e', wx1, wy0, wy1, G + 0.1, G + wh - 0.07, 5, braces=(0, 1, 3, 4), mid=True,
               holes=[(-0.80, 0.15), (-0.34, 0.15)])
    # south face: door, loft window
    door(M, 's', wy0, 1.175, 0.2, 0.42, G + 0.1)
    window(M, 's', wy0, 0.74, G + 0.60, 0.15, 0.22, 'mustard', glow=True,
           planter=['fl_pink', 'fl_red', 'fl_white'])
    window(M, 's', wy0, 1.61, G + 0.60, 0.15, 0.22, 'teal')
    # east face windows
    window(M, 'e', wx1, -0.80, G + 0.60, 0.15, 0.22, 'red', glow=True)
    window(M, 'e', wx1, -0.34, G + 0.60, 0.15, 0.22, 'teal',
           planter=['fl_yel', 'fl_blue'])
    # west face of the wing (toward the courtyard's back, seen once turned)
    wall_frame(M, 'w', wx0, wy0, wy1, G + 0.1, G + wh - 0.07, 5,
               braces=(0, 1, 3, 4), mid=True, holes=[(-0.80, 0.15), (-0.34, 0.15)])
    window(M, 'w', wx0, -0.80, G + 0.60, 0.15, 0.22, 'teal', glow=True)
    window(M, 'w', wx0, -0.34, G + 0.60, 0.15, 0.22, 'red',
           planter=['fl_pink', 'fl_white'])
    # south gable of the wing (faces the camera on the left)
    wmid = (wx0 + wx1) / 2
    wspan = wx1 - wx0
    wrise = wspan / 2 * TP
    gable_wall(M, 's', wy0, wx0, wx1, G + wh)

    # the egg emblem in the gable
    ellipsoid(wmid, wy0 - 0.02, G + wh + 0.3, 0.075, 0.016, 0.1, M['pane_glow'],
              egg=0.2, seg=14, rings=10)
    # roof: extends back into the main house's roof
    wlen = (0.62) - (wy0 - 0.0)       # from wy0 to y=0.62, centred below
    wing_ridge = gable_roof(M, wmid, (wy0 + 0.62) / 2, G + wh, wlen, wspan, 'y', M['roof2'],
               oh=0.15, oe=0.16)
    ellipsoid(wmid, wy0 - 0.16, wing_ridge + 0.02, 0.04, 0.04, 0.055, M['gold'],
              egg=0.2)

    # awning + table (south wall, west of the door) --------------
    pole_h = 0.5
    for px in (-0.93, -0.12):
        beam((px, -0.28, G), (px, -0.28, G + pole_h), 0.035, M['timber'])
    tilt = math.atan2(0.16, 0.43)
    rbox((-0.525, -0.065, G + 0.54), (0.83, 0.49, 0.02), (tilt, 0, 0),
         M['awning'], bevel=0.006)
    # the scalloped edge flutters
    with anim('awning_edge', 'sway', pivot=(-0.525, -0.31, G + 0.465),
              amp=0.10, period=2.1):
        for i in range(10):
            rbox((-0.93 + 0.0 + i * 0.09 + 0.045, -0.31, G + 0.44),
                 (0.085, 0.012, 0.045), (tilt, 0, 0), M['awning'], bevel=0.004)
    # table + goods
    rbox((-0.52, -0.06, G + 0.17), (0.74, 0.22, 0.03), (0, 0, 0), M['planks'])
    for px in (-0.86, -0.18):
        for py in (-0.14, 0.02):
            beam((px, py, G), (px, py, G + 0.17), 0.026, M['timber'])
    for i, e in enumerate(('cream', 'blue', 'gold', 'rose', 'green')):
        egg(M, e, -0.82 + i * 0.1, -0.08, G + 0.185, 0.04, tilt=0.15 * (i % 3 - 1))
    crate(M, -0.2, -0.04, 0.1, 0.2, z=G + 0.185)
    ellipsoid(-0.52, -0.02, G + 0.23, 0.05, 0.05, 0.035, M['straw'], seg=14,
              rings=8)
    for k, e in enumerate(('brown', 'cream')):
        egg(M, e, -0.53 + k * 0.03, -0.02, G + 0.235, 0.035)

    # glowing egg shrine -------------------------------------
    sx, sy = -0.45, -0.95
    cyl(sx, sy, G, 0.24, 0.22, 0.07, M['stone_dk'], seg=14)
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        rbox((sx + math.cos(a) * 0.17, sy + math.sin(a) * 0.17, G + 0.16),
             (0.07, 0.07, 0.19), (0.18 * math.cos(a), 0.18 * math.sin(a), a),
             M['stone'], bevel=0.012)
    cyl(sx, sy, G + 0.07, 0.16, 0.14, 0.04, M['straw'], seg=14)
    egg(M, 'gold', sx, sy, G + 0.11, 0.115, glow=True)
    # sparks drifting over the egg, in two clouds out of step
    for k in range(2):
        with anim(f'motes{k}', 'bob', pivot=(sx, sy, G + 0.4), amp=0.008,
                  period=3.6 + k * 1.3):
            for i in range(5):
                a = random.uniform(0, 6.28)
                d = random.uniform(0.05, 0.28)
                ellipsoid(sx + math.cos(a) * d, sy + math.sin(a) * d,
                          G + random.uniform(0.25, 0.55), 0.011, 0.011, 0.011,
                          M['mote'], seg=6, rings=4)
    bpy.ops.object.light_add(type='POINT', location=(sx, sy, G + 0.3))
    pl = bpy.context.object
    pl.data.energy = 14
    pl.data.color = (1.0, 0.78, 0.4)
    pl.data.shadow_soft_size = 0.12

    # nests -------------------------------------------------
    nest(M, -1.28, -0.55, 0.17, ('cream', 'blue'), 1)
    nest(M, -0.98, -1.30, 0.16, ('green', 'rose', 'cream'), 2)
    nest(M, 0.02, -0.82, 0.15, ('gold', 'brown'), 3)
    nest(M, -1.72, -1.0, 0.16, ('violet', 'cream'), 4)
    # a clutch of big eggs, wing corner
    egg(M, 'cream', 1.50, -1.33, G, 0.11)
    egg(M, 'gold', 1.74, -1.28, G, 0.09, tilt=0.2)
    egg(M, 'blue', 1.92, -1.16, G, 0.10, tilt=-0.2)

    # hay, coop, hens ---------------------------------------
    hay_bale(M, -1.62, -0.18, G, 0.34, 0.24, 0.2, 0.3)
    hay_bale(M, -1.55, -0.2, G + 0.2, 0.3, 0.22, 0.18, -0.1)
    hay_bale(M, -1.30, 0.04, G, 0.3, 0.2, 0.18, 0.1)
    hay_scatter(M, -1.35, -0.2, 0.45, 70, 9)
    hay_scatter(M, -0.5, -0.5, 0.7, 60, 10)
    # coop
    cx, cy = -1.62, -1.15
    rbox((cx, cy, G + 0.09), (0.36, 0.26, 0.18), (0, 0, 0.25), M['planks'],
         bevel=0.008)
    rbox((cx - 0.01, cy, G + 0.215), (0.40, 0.31, 0.02), (0.0, 0.35, 0.25),
         M['roof2'], bevel=0.008)
    rbox((cx + 0.06, cy - 0.131, G + 0.07), (0.07, 0.01, 0.09), (0, 0, 0.25),
         M['pane'])
    beam((cx + 0.28, cy - 0.05, G), (cx + 0.09, cy - 0.12, G + 0.07), 0.04, M['planks'])
    # the hens peck: each one leans about its feet, at its own pace
    for i, (hx, hy, rot, key) in enumerate(((-1.20, -0.88, 0.5, 'hen_w'),
                                            (-1.0, -1.18, 2.6, 'hen_r'),
                                            (-1.45, -0.62, -0.7, 'hen_r'))):
        with anim(f'hen{i}', 'sway', pivot=(hx, hy, G), amp=0.22,
                  period=1.5 + 0.35 * i):
            hen(M, hx, hy, rot, key)

    # barrels, sacks, crates ----------------------------------
    # (the two barrels moved off the entrance path to the back wall)
    barrel(M, 0.40, 1.40)
    barrel(M, 0.56, 1.41, 0.075, 0.17)
    sack(M, 1.45, -1.33, 1.0, 0.2)
    sack(M, 1.38, -1.40, 0.9, -0.3, 'sack')
    crate(M, 1.95, -0.7, 0.14, 0.3)
    crate(M, 1.97, -0.55, 0.12, -0.2)
    sack(M, 1.92, -0.05, 1.0)
    barrel(M, 1.9, 0.5)
    crate(M, 1.78, -1.4, 0.12, 0.1)

    # bushes, flowers -----------------------------------------
    bush(M, 1.93, 0.85, 0.2, 1, ['fl_white', 'fl_pink'])
    bush(M, -0.2, 1.42, 0.2, 2)
    bush(M, 1.0, 1.42, 0.18, 3, ['fl_yel'])
    bush(M, -1.8, 0.2, 0.17, 4, ['fl_red'])
    # flower patches (each sways on its own — fw_kit.flower_patch)
    for k, (cx, cy, n, cols) in enumerate(((-1.85, -1.3, 8, ['fl_white', 'fl_pink']),
                                           (-0.15, -1.38, 6, ['fl_red', 'fl_yel']),
                                           (-0.9, 0.35, 7, ['fl_blue', 'fl_white']),
                                           (1.85, -1.0, 6, ['fl_blue', 'fl_pink']),
                                           (-1.4, -1.4, 5, ['fl_yel']),
                                           (1.40, 1.42, 6, ['fl_pink', 'fl_white']))):
        flower_patch(M, cx, cy, n, cols, 21 + k)
    # hanging sign (golden egg) on the wing's south-west corner — it swings
    # from its bracket — and lanterns at the wing's door ------------------
    sy_ = wy0 - 0.02
    beam((0.60, sy_, G + 0.86), (0.36, sy_, G + 0.86), 0.03, M['timber'])
    beam((0.60, sy_, G + 0.70), (0.44, sy_, G + 0.84), 0.022, M['timber'])
    with anim('sign', 'sway', pivot=(0.45, sy_, G + 0.86), amp=0.07,
              period=3.0):
        for dx in (0.40, 0.50):
            beam((dx, sy_, G + 0.86), (dx, sy_, G + 0.78), 0.006, M['iron'],
                 bevel=0)
        rbox((0.45, sy_, G + 0.69), (0.19, 0.02, 0.15), (0, 0, 0), M['planks'])
        ellipsoid(0.45, sy_ - 0.016, G + 0.69, 0.045, 0.012, 0.06, M['gold'],
                  egg=0.2)
    for lx in (0.95, 1.40):
        beam((lx, wy0 - 0.012, G + 0.66), (lx, wy0 - 0.075, G + 0.66), 0.014,
             M['iron'], bevel=0)
        ellipsoid(lx, wy0 - 0.085, G + 0.61, 0.026, 0.026, 0.04, M['lamp'],
                  seg=10, rings=8)
