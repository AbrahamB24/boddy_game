"""The Hatchery, photoreal: a fantasy half-timbered brooding house.

    blender --background --python tool/blender/hatchery_pro.py -- \
        --out docs/renders/hatchery_pro.png --samples 128 --scale 4

Pilot for the "pro" pipeline (see pro_kit.py). The reference is the windmill
sheet the owner supplied: warm golden-hour light, orange clay tiles, cream
plaster in a brown frame, a stone base, a cobbled path, grass, and a dozen
small props that say who lives here.

Plan (x east, y north; the camera looks from +x/-y so the SOUTH and EAST faces
are the ones a player sees). The tile is 4 x 3:

    tower  main house (ridge along x)
           wing (ridge along y, its gable faces the camera)
    courtyard: nests, the glowing egg, hay, coop, awning and table
"""
import math
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from pro_kit import *  # noqa: F401,F403,E402
import pro_kit as K  # noqa: E402

PITCH = 50.0
TP = math.tan(math.radians(PITCH))


# ── materials ───────────────────────────────────────────────
def materials():
    M = {}
    M['plaster'] = tex_mat('plaster', 'white_plaster_rough_01', 1.0,
                           tint=(1.0, 0.90, 0.72), sat=0.30, val=2.05,
                           rough=1.0, nstr=0.9, vary=0.05)
    M['timber'] = tex_mat('timber', 'dark_wood', 0.8, tint=(0.95, 0.70, 0.52),
                          sat=1.0, val=0.95, nstr=0.8, vary=0.12)
    M['planks'] = tex_mat('planks', 'weathered_planks', 0.7,
                          tint=(1.7, 1.2, 0.8), sat=1.2, val=1.25, nstr=0.9)
    M['roof'] = tex_mat('roof', 'clay_roof_tiles_02', 1.55,
                        tint=(1.12, 0.92, 0.78), sat=1.05, val=1.15,
                        nstr=1.5, vary=0.05)
    M['roof2'] = tex_mat('roof2', 'clay_roof_tiles_02', 1.55,
                         tint=(1.0, 0.80, 0.70), sat=1.1, val=1.0,
                         nstr=1.5, vary=0.05)
    M['stone'] = tex_mat('stone', 'old_stone_wall', 1.2,
                         tint=(1.18, 1.04, 0.88), sat=0.9, val=1.2,
                         nstr=1.2, vary=0.06)
    M['stone_dk'] = tex_mat('stone_dk', 'old_stone_wall', 1.2,
                            tint=(0.95, 0.85, 0.74), sat=0.9, val=0.95,
                            nstr=1.2, vary=0.10)
    M['cobble'] = plain('cobble', '#d2c4a6', rough=0.85, bump=0.55,
                        bump_scale=40, vary=0.14, speck='#a89878')
    M['grass'] = tex_mat('grass', 'leafy_grass', 1.4, tint=(0.88, 1.12, 0.45),
                         sat=1.7, val=1.1, nstr=0.7, vary=0.04)
    M['dirt'] = tex_mat('dirt', 'park_dirt', 1.2, tint=(1.05, 0.88, 0.62),
                        sat=1.0, val=0.95, nstr=0.8, vary=0.08)
    M['soil'] = tex_mat('soil', 'park_dirt', 1.0, tint=(0.75, 0.55, 0.38),
                        sat=1.0, val=0.7, nstr=1.0, vary=0.04)
    M['hay'] = tex_mat('hay', 'reed_roof_03', 0.55, tint=(1.55, 1.2, 0.62),
                       sat=1.3, val=1.4, nstr=1.0, vary=0.10)
    M['straw'] = plain('straw', '#e2b956', rough=0.85, bump=0.0, vary=0.18)
    M['straw_dk'] = plain('straw_dk', '#b8862f', rough=0.9, bump=0.0, vary=0.2)
    M['iron'] = plain('iron', '#3a3633', rough=0.5, metal=1.0, bump=0.05)
    M['gold'] = plain('gold', '#f2b632', rough=0.28, metal=1.0, bump=0.0)
    M['linen'] = plain('linen', '#ecd9ae', rough=0.95, bump=0.25,
                       bump_scale=120, vary=0.05)
    M['awning'] = plain('awning', '#e6cf9e', rough=0.95, bump=0.3,
                        bump_scale=140, vary=0.04)
    M['sack'] = plain('sack', '#c9ac78', rough=0.95, bump=0.35,
                      bump_scale=90, vary=0.12)
    M['leaf'] = plain('leaf', '#4f8a24', rough=0.7, bump=0.5, bump_scale=70,
                      vary=0.2, speck='#6a9a2a')
    M['leaf2'] = plain('leaf2', '#6a9a2a', rough=0.7, bump=0.5, bump_scale=70,
                       vary=0.2, speck='#8aa636')
    M['stem'] = plain('stem', '#4f7a22', rough=0.8, bump=0.0)
    M['teal'] = plain('teal', '#3c7d78', rough=0.7, vary=0.1)
    M['red'] = plain('red', '#a8402c', rough=0.7, vary=0.1)
    M['mustard'] = plain('mustard', '#d09a2a', rough=0.7, vary=0.1)
    M['pane'] = plain('pane', '#15232a', rough=0.12, bump=0.0, vary=0.0)
    M['pane_glow'] = plain('pane_glow', '#ffb14a', rough=0.4, bump=0.0,
                           emit='#ff9a2e', emit_strength=3.0, vary=0.0)
    M['lamp'] = plain('lamp', '#ffd07a', rough=0.3, bump=0.0, emit='#ffc060',
                      emit_strength=9.0, vary=0.0)
    M['egg_glow'] = plain('egg_glow', '#fff0b0', rough=0.25, bump=0.0,
                          emit='#ffd24a', emit_strength=5.5, vary=0.0)
    M['mote'] = plain('mote', '#fff4c0', rough=0.3, bump=0.0, emit='#ffe9a0',
                      emit_strength=12.0, vary=0.0)
    M['blade'] = blade_mat('blade', '#3e6f1b', '#c4cf45')
    M['blade2'] = blade_mat('blade2', '#4f8420', '#e0d654')
    eggs = {'cream': ('#f1e2bc', '#b99a64'), 'gold': ('#f0bc3e', '#a8741c'),
            'blue': ('#5ba3d6', '#2a5f95'), 'green': ('#8fc766', '#456f2d'),
            'rose': ('#e58a84', '#a04440'), 'brown': ('#c58a54', '#6d4423'),
            'violet': ('#a98ae0', '#5d46a0')}
    for k, (a, b) in eggs.items():
        M['egg_' + k] = plain('egg_' + k, a, rough=0.32, bump=0.05,
                              bump_scale=90, vary=0.07, speck=b)
    for k, c in {'fl_red': '#d8352c', 'fl_blue': '#4b6fd8', 'fl_white': '#f4f0e6',
                 'fl_pink': '#e982b4', 'fl_yel': '#f2cf3a'}.items():
        M[k] = plain(k, c, rough=0.6, bump=0.0, vary=0.1)
    M['hen_w'] = plain('hen_w', '#f1ead8', rough=0.9, bump=0.5, bump_scale=70)
    M['hen_r'] = plain('hen_r', '#b5622c', rough=0.9, bump=0.5, bump_scale=70)
    M['comb'] = plain('comb', '#cc2a24', rough=0.6, bump=0.0)
    M['beak'] = plain('beak', '#e8a22a', rough=0.5, bump=0.0)
    return M


# ── face helpers: 's' = south wall (normal -y), 'e' = east wall (+x) ──────
def P(face, fixed, a, z, off=0.0):
    return Vector((a, fixed - off, z)) if face == 's' else Vector((fixed + off, a, z))


def D(face, along, depth, h):
    return (along, depth, h) if face == 's' else (depth, along, h)


def wall_frame(M, face, fixed, a0, a1, z0, z1, nb, braces=(), t=0.052,
               mid=False, holes=()):
    """The half-timber: sill, plate, posts and diagonal braces on one wall.

    holes = [(a, w)] â€” openings (windows, doors) on this wall. Posts, braces
    and the mid rail keep out of them, so no timber ever crosses a pane.
    Rails stop at the outer post's centre and posts stop at the rails'
    centres, so no two end faces sit coplanar (that z-fights as black squares).
    """
    xs = [a0 + (a1 - a0) * i / nb for i in range(nb + 1)]
    off = 0.012
    spans = [(a - (w / 2 + w * 0.36 + 0.02), a + (w / 2 + w * 0.36 + 0.02))
             for a, w in holes]
    pspans = [(a - (w / 2 + 0.03), a + (w / 2 + 0.03)) for a, w in holes]

    def hit(lo, hi):
        return any(hi > l and lo < h for l, h in spans)
    beam(P(face, fixed, a0, z0 + t / 2, off),
         P(face, fixed, a1, z0 + t / 2, off), t, M['timber'])
    beam(P(face, fixed, a0, z1 - t / 2, off),
         P(face, fixed, a1, z1 - t / 2, off), t, M['timber'])
    if mid:
        zm = (z0 + z1) / 2
        cuts = sorted([a0, a1] + [v for sp in spans for v in sp])
        # segments between holes
        segs = []
        cur = a0
        for l, h in sorted(spans):
            if l > cur + 0.05:
                segs.append((cur, min(l, a1)))
            cur = max(cur, h)
        if a1 > cur + 0.05:
            segs.append((cur, a1))
        for l, h in segs:
            beam(P(face, fixed, l, zm, off), P(face, fixed, h, zm, off),
                 t * 0.85, M['timber'])
    for i, a in enumerate(xs):
        if any(l < a < h for l, h in pspans) and 0 < i < nb:
            continue
        beam(P(face, fixed, a, z0 + t / 2, off),
             P(face, fixed, a, z1 - t / 2, off), t, M['timber'])
    for i in braces:
        if hit(xs[i], xs[i + 1]):
            continue
        sgn = 1 if i % 2 == 0 else -1
        pa = P(face, fixed, xs[i], z0 + t / 2 if sgn > 0 else z1 - t / 2, off * 0.6)
        pb = P(face, fixed, xs[i + 1], z1 - t / 2 if sgn > 0 else z0 + t / 2, off * 0.6)
        beam(pa, pb, t * 0.8, M['timber'])
    return xs

def window(M, face, fixed, a, zc, w, h, shut='teal', glow=False, planter=None):
    t = 0.034
    off = 0.010
    pane = M['pane_glow'] if glow else M['pane']
    rbox(P(face, fixed, a, zc, 0.002), D(face, w, 0.012, h), (0, 0, 0), pane)
    for da in (-w / 2, w / 2):
        beam(P(face, fixed, a + da, zc - h / 2, off),
             P(face, fixed, a + da, zc + h / 2, off), t, M['timber'])
    for dz in (-h / 2, h / 2):
        beam(P(face, fixed, a - w / 2, zc + dz, off),
             P(face, fixed, a + w / 2, zc + dz, off), t, M['timber'])
    beam(P(face, fixed, a, zc - h / 2, off), P(face, fixed, a, zc + h / 2, off),
         0.016, M['timber'])
    beam(P(face, fixed, a - w / 2, zc, off), P(face, fixed, a + w / 2, zc, off),
         0.016, M['timber'])
    sill = P(face, fixed, a, zc - h / 2 - 0.02, 0.03)
    rbox(sill, D(face, w + 0.1, 0.07, 0.03), (0, 0, 0), M['stone'])
    if shut:
        sw = w * 0.36
        for sgn in (-1, 1):
            c = P(face, fixed, a + sgn * (w / 2 + sw / 2 + 0.03), zc, 0.03)
            d = D(face, sw, 0.02, h)
            box(c.x, c.y, c.z - h / 2, d[0], d[1], d[2], M[shut], bevel=0.003)
    if planter:
        c = P(face, fixed, a, zc - h / 2 - 0.075, 0.07)
        rbox(c, D(face, w + 0.04, 0.07, 0.06), (0, 0, 0), M['planks'])
        flowers(face, fixed, a, zc - h / 2 - 0.04, w, planter)


def flowers(face, fixed, a, z, w, cols):
    rnd = random.Random(int(a * 977) + 3)
    for i in range(7):
        aa = a + (i / 6 - 0.5) * w * 0.9
        p = P(face, fixed, aa, z, 0.07 + rnd.uniform(-0.01, 0.01))
        h = rnd.uniform(0.04, 0.08)
        beam(p, p + Vector((0, 0, h)), 0.006, K._mats['stem'], bevel=0)
        ellipsoid(p.x, p.y, p.z + h, 0.017, 0.017, 0.014,
                  K._mats[rnd.choice(cols)], seg=8, rings=6)
        ellipsoid(p.x, p.y, p.z + 0.02, 0.03, 0.03, 0.03, K._mats['leaf'],
                  seg=8, rings=6)


def door(M, face, fixed, a, w, h, z0):
    t = 0.04
    off = 0.012
    rbox(P(face, fixed, a, z0 + h / 2, -0.01), D(face, w, 0.03, h), (0, 0, 0),
         M['planks'])
    for da in (-w / 2 - t / 2, w / 2 + t / 2):
        beam(P(face, fixed, a + da, z0, off), P(face, fixed, a + da, z0 + h + t / 2, off),
             t, M['timber'])
    beam(P(face, fixed, a - w / 2 - t / 2, z0 + h + t / 2, off),
         P(face, fixed, a + w / 2 + t / 2, z0 + h + t / 2, off), t * 1.1, M['timber'])
    for fz in (0.2, 0.75):
        beam(P(face, fixed, a - w / 2, z0 + h * fz, 0.006),
             P(face, fixed, a + w / 2, z0 + h * fz, 0.006), 0.02, M['iron'],
             bevel=0)
    # ring handle
    c = P(face, fixed, a + w * 0.3, z0 + h * 0.5, 0.012)
    ellipsoid(c.x, c.y, c.z, 0.012, 0.012, 0.012, M['iron'], seg=8, rings=6)
    # stone step
    rbox(P(face, fixed, a, z0 - 0.012, 0.09), D(face, w + 0.2, 0.18, 0.045),
         (0, 0, 0), M['stone'])


# ── roofs ────────────────────────────────────────────────────
def gable_roof(M, cx, cy, z0, length, span, axis, mat, oh=0.15, oe=0.16,
               thick=0.075):
    """Two tile slabs meeting at a ridge. z0 = eave height of the WALL top."""
    s = span / 2.0
    rise = s * TP
    zr = z0 + rise
    reach = s + oh
    slope = reach / math.cos(math.radians(PITCH))
    d = reach / 2.0
    p = math.radians(PITCH)
    for sgn in (-1, 1):
        top_c = (zr - d * TP)
        # slab centre = top-surface centre pushed down by thick/2 along normal
        nz, nh = math.cos(p), math.sin(p)
        cz = top_c - thick / 2 * nz
        off = d * sgn - thick / 2 * nh * sgn
        if axis == 'x':
            c = (cx, cy + off, cz)
            eul = (-p * sgn, 0, 0)
            dims = (length + 2 * oe, slope + 0.02, thick)
        else:
            c = (cx + off, cy, cz)
            eul = (0, p * sgn, 0)
            dims = (slope + 0.02, length + 2 * oe, thick)
        rbox(c, dims, eul, mat, bevel=0.012)
    # ridge cap
    if axis == 'x':
        rbox((cx, cy, zr + 0.012), (length + 2 * oe, 0.1, 0.1),
             (math.radians(45), 0, 0), M['roof2'], bevel=0.01)
    else:
        rbox((cx, cy, zr + 0.012), (0.1, length + 2 * oe, 0.1),
             (0, math.radians(45), 0), M['roof2'], bevel=0.01)
    return zr


def gable_end(M, axis, fixed, mid, span, z_base, depth, inward=1, frame=True,
              face='e'):
    """Plaster triangle + the king post and rafter braces of a gable wall."""
    s = span / 2.0
    rise = s * TP
    y0, y1 = (fixed - depth, fixed) if inward > 0 else (fixed, fixed + depth)
    tri_prism((mid - s, z_base), (mid + s, z_base), (mid, z_base + rise), y0, y1,
              M['plaster'], axis=axis)
    return rise


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


def hay_bale(M, x, y, z, sx, sy, sz, rot=0.0):
    rbox((x, y, z + sz / 2), (sx, sy, sz), (0, 0, rot), M['hay'], bevel=0.02)
    for f in (-0.28, 0.28):
        c = Vector((f * sx, 0, 0))
        c = Vector((x + c.x * math.cos(rot), y + c.x * math.sin(rot), z + sz / 2))
        rbox(c, (0.014, sy + 0.012, sz + 0.012), (0, 0, rot), M['iron'], bevel=0)


def hay_scatter(M, cx, cy, r, n, seed=1):
    rnd = random.Random(seed)
    lst = []
    for _ in range(n):
        a = rnd.uniform(0, 6.28)
        d = r * math.sqrt(rnd.random())
        p = Vector((cx + math.cos(a) * d, cy + math.sin(a) * d, G + 0.004))
        b = rnd.uniform(0, 6.28)
        L = rnd.uniform(0.05, 0.11)
        q = p + Vector((math.cos(b) * L, math.sin(b) * L, rnd.uniform(0, 0.018)))
        lst.append((p, q, 0.006))
    strands(lst, M['straw'], 'hayscatter')


def barrel(M, x, y, r=0.085, h=0.2):
    cyl(x, y, G, r * 0.88, r, h * 0.5, M['planks'], seg=16)
    cyl(x, y, G + h * 0.5, r, r * 0.88, h * 0.5, M['planks'], seg=16)
    for fz in (0.14, 0.5, 0.86):
        rr = r * (0.88 + 0.12 * (1 - abs(fz - 0.5) * 2))
        cyl(x, y, G + h * fz - 0.008, rr + 0.004, rr + 0.004, 0.016, M['iron'],
            seg=16)
    cyl(x, y, G + h - 0.002, r * 0.86, r * 0.86, 0.006, M['timber'], seg=16)


def sack(M, x, y, s=1.0, rot=0.0, key='sack'):
    ellipsoid(x, y, G + 0.07 * s, 0.075 * s, 0.062 * s, 0.085 * s, M[key], egg=0.35,
              tilt=(0, 0, rot))
    ellipsoid(x, y, G + 0.152 * s, 0.026 * s, 0.026 * s, 0.022 * s, M[key], seg=10,
              rings=6)


def crate(M, x, y, s=0.14, rot=0.0, z=None):
    z0 = G if z is None else z
    rbox((x, y, z0 + s / 2), (s, s, s), (0, 0, rot), M['planks'], bevel=0.008)
    for sg in (-1, 1):
        rbox((x, y, z0 + s / 2), (s + 0.01, 0.014, s + 0.01), (0, 0, rot),
             M['timber'], bevel=0.003)


def bush(M, x, y, r=0.22, seed=0, flowers_cols=None):
    rnd = random.Random(seed)
    for i in range(6):
        a = rnd.uniform(0, 6.28)
        d = rnd.uniform(0, r * 0.7)
        rr = r * rnd.uniform(0.5, 0.85)
        ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d, G + rr * 0.75,
                  rr, rr, rr * 0.85, M['leaf'] if i % 2 else M['leaf2'], seg=14,
                  rings=10)
    if flowers_cols:
        for i in range(10):
            a = rnd.uniform(0, 6.28)
            d = rnd.uniform(0.3, 1.0) * r
            ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d,
                      G + rnd.uniform(0.12, 0.3), 0.022, 0.022, 0.02,
                      M[rnd.choice(flowers_cols)], seg=8, rings=6)


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
def build(ground=True):
    """ground=False builds the building WITHOUT its plinth: no soil slab, no
    turf, no worn-dirt patches, no dirt strip under the path, no grass blades,
    and the whole scene is lowered so the yard stands at z = 0 — the game draws
    it on its own map ground (user 2026-11-03: kein Podest oder Boden)."""
    random.seed(11)
    M = materials()
    W, H = 4, 3

    # ground ------------------------------------------------
    if ground:
        box(0, 0, 0, 4.0, 3.0, G - 0.05, M['soil'], bevel=0.012, name='soil')
        box(0, 0, G - 0.06, 4.0, 3.0, 0.06, M['grass'], bevel=0.03,
            name='turf')

        # dirt patches (worn ground in the yard)
        for i, (x, y, rx, ry) in enumerate(((-0.65, -0.75, 0.95, 0.55),
                                             (0.75, -0.7, 0.35, 0.5),
                                             (-1.35, -0.1, 0.45, 0.3),
                                             (-0.3, 0.0, 0.55, 0.2))):
            blob(x, y, rx, ry, G - 0.002, 0.008, M['dirt'], seed=i)

    # path ---------------------------------------------------
    paths = [[(0.02, -1.46), (0.30, -1.22), (0.40, -0.75), (0.40, -0.25),
              (0.40, 0.10)],
             [(0.30, -1.25), (0.80, -1.33), (1.17, -1.30)]]
    rnd = random.Random(5)
    for pl in paths:
        for i in range(len(pl) - 1):
            a, b = Vector(pl[i] + (0,)), Vector(pl[i + 1] + (0,))
            if ground:
                beam((a.x, a.y, G + 0.004), (b.x, b.y, G + 0.004), 0.40,
                     M['dirt'], t2=0.01, bevel=0)
            L = (b - a).length
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
                          (-100, 0.30, 'door')):
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
    # east gable
    ridge_z = G + up + (my1 - my0 + 2 * 0.0) / 2 * TP
    tri_prism((my0 - j, G + up), (my1, G + up), ((my0 - j + my1) / 2, ridge_z),
              ux1 - 0.07, ux1, M['plaster'], axis='y')
    gm = (my0 - j + my1) / 2
    # gable framing: king post + two rafters' braces + a round egg window
    beam((ux1 + 0.012, gm, G + up + 0.27), (ux1 + 0.012, gm, ridge_z - 0.03), 0.05,
         M['timber'])
    for sgn in (-1, 1):
        beam((ux1 + 0.012, gm + sgn * 0.02, ridge_z - 0.06),
             (ux1 + 0.012, gm + sgn * (my1 - my0 + j) / 2 * 0.98, G + up + 0.03), 0.045,
             M['timber'])

    ellipsoid(ux1 + 0.025, gm, G + up + 0.17, 0.016, 0.07, 0.085, M['pane_glow'],
              egg=0.2, seg=14, rings=10)
    # roof
    gable_roof(M, (mx0 + mx1 + j) / 2, (my0 - j + my1) / 2, G + up,
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
    # south gable of the wing (faces the camera on the left)
    wmid = (wx0 + wx1) / 2
    wspan = wx1 - wx0
    wrise = wspan / 2 * TP
    tri_prism((wx0, G + wh), (wx1, G + wh), (wmid, G + wh + wrise), wy0, wy0 + 0.07,
              M['plaster'], axis='x')
    fz = wy0 - 0.012
    beam((wmid, fz, G + wh + 0.40), (wmid, fz, G + wh + wrise - 0.03), 0.05, M['timber'])
    for sgn in (-1, 1):
        beam((wmid + sgn * 0.02, fz, G + wh + wrise - 0.06),
             (wmid + sgn * (wspan / 2) * 0.98, fz, G + wh + 0.03), 0.045, M['timber'])

    # the egg emblem in the gable
    ellipsoid(wmid, wy0 - 0.02, G + wh + 0.3, 0.075, 0.016, 0.1, M['pane_glow'],
              egg=0.2, seg=14, rings=10)
    # roof: extends back into the main house's roof
    wlen = (0.62) - (wy0 - 0.0)       # from wy0 to y=0.62, centred below
    gable_roof(M, wmid, (wy0 + 0.62) / 2, G + wh, wlen, wspan, 'y', M['roof2'],
               oh=0.15, oe=0.16)
    ellipsoid(wmid, wy0 - 0.16, G + wh + wrise + 0.02, 0.04, 0.04, 0.055, M['gold'],
              egg=0.2)

    # awning + table (south wall, west of the door) --------------
    pole_h = 0.5
    for px in (-0.93, -0.12):
        beam((px, -0.28, G), (px, -0.28, G + pole_h), 0.035, M['timber'])
    tilt = math.atan2(0.16, 0.43)
    rbox((-0.525, -0.065, G + 0.54), (0.83, 0.49, 0.02), (tilt, 0, 0),
         M['awning'], bevel=0.006)
    for i in range(10):          # scalloped edge
        rbox((-0.93 + 0.0 + i * 0.09 + 0.045, -0.31, G + 0.44), (0.085, 0.012, 0.045),
             (tilt, 0, 0), M['awning'], bevel=0.004)
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
    for i in range(10):
        a = random.uniform(0, 6.28)
        d = random.uniform(0.05, 0.28)
        ellipsoid(sx + math.cos(a) * d, sy + math.sin(a) * d,
                  G + random.uniform(0.25, 0.55), 0.011, 0.011, 0.011, M['mote'],
                  seg=6, rings=4)
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
    hen(M, -1.20, -0.88, 0.5, 'hen_w')
    hen(M, -1.0, -1.18, 2.6, 'hen_r')
    hen(M, -1.45, -0.62, -0.7, 'hen_r')

    # barrels, sacks, crates ----------------------------------
    barrel(M, 0.70, -1.30)
    barrel(M, 0.83, -1.40, 0.075, 0.17)
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
    rnd = random.Random(21)
    for (cx, cy, n, cols) in ((-1.85, -1.3, 8, ['fl_white', 'fl_pink']),
                              (0.1, -1.38, 6, ['fl_red', 'fl_yel']),
                              (-0.9, 0.35, 7, ['fl_blue', 'fl_white']),
                              (1.85, -1.0, 6, ['fl_blue', 'fl_pink']),
                              (-1.4, -1.4, 5, ['fl_yel'])):
        for i in range(n):
            x = cx + rnd.uniform(-0.18, 0.18)
            y = cy + rnd.uniform(-0.12, 0.12)
            h = rnd.uniform(0.05, 0.11)
            beam((x, y, G), (x, y, G + h), 0.006, M['stem'], bevel=0)
            ellipsoid(x, y, G + h, 0.02, 0.02, 0.016, M[rnd.choice(cols)], seg=8,
                      rings=6)
    # hanging sign (golden egg) on the wing's south-west corner, lanterns at
    # its door ------------------------------------------------------------
    sy_ = wy0 - 0.02
    beam((0.60, sy_, G + 0.86), (0.36, sy_, G + 0.86), 0.03, M['timber'])
    beam((0.60, sy_, G + 0.70), (0.44, sy_, G + 0.84), 0.022, M['timber'])
    for dx in (0.40, 0.50):
        beam((dx, sy_, G + 0.86), (dx, sy_, G + 0.78), 0.006, M['iron'], bevel=0)
    rbox((0.45, sy_, G + 0.69), (0.19, 0.02, 0.15), (0, 0, 0), M['planks'])
    ellipsoid(0.45, sy_ - 0.016, G + 0.69, 0.045, 0.012, 0.06, M['gold'],
              egg=0.2)
    for lx in (0.95, 1.40):
        beam((lx, wy0 - 0.012, G + 0.66), (lx, wy0 - 0.075, G + 0.66), 0.014,
             M['iron'], bevel=0)
        ellipsoid(lx, wy0 - 0.085, G + 0.61, 0.026, 0.026, 0.04, M['lamp'],
                  seg=10, rings=8)
    # grass --------------------------------------------------
    if ground:
        grass(M)
    else:
        # lower everything so the yard level (G) becomes z = 0
        for ob in list(bpy.data.objects):
            if ob.parent is None:
                ob.location.z -= G


def grass(M):
    """A few thousand single-triangle blades, kept off buildings and the path."""
    import bmesh
    rnd = random.Random(99)
    avoid = [(-1.72, -0.99, 0.2, 1.45), (-0.99, 1.88, 0.1, 1.33),
             (0.57, 1.78, -1.18, 0.2)]
    path = [((0.02, -1.46), (0.30, -1.22)), ((0.30, -1.22), (0.40, -0.75)),
            ((0.40, -0.75), (0.40, 0.1)), ((0.30, -1.25), (0.80, -1.33)),
            ((0.80, -1.33), (1.17, -1.30))]

    def near_path(x, y):
        for (ax, ay), (bx, by) in path:
            dx, dy = bx - ax, by - ay
            t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
            if math.hypot(x - ax - dx * t, y - ay - dy * t) < 0.24:
                return True
        return False

    def in_building(x, y):
        # tower
        if math.hypot(x + 1.25, y - 0.85) < 0.5:
            return True
        # main house
        if -0.99 <= x <= 1.95 and 0.08 <= y <= 1.36:
            return True
        # wing
        if 0.55 <= x <= 1.80 and -1.2 <= y <= 0.2:
            return True
        return False

    for key in ('blade', 'blade2'):
        bm = bmesh.new()
        n = 0
        tries = 0
        while n < 1500 and tries < 60000:
            tries += 1
            x = rnd.uniform(-1.97, 1.97)
            y = rnd.uniform(-1.47, 1.47)
            if in_building(x, y) or near_path(x, y):
                continue
            for _ in range(rnd.randint(2, 4)):
                bx = x + rnd.uniform(-0.02, 0.02)
                by = y + rnd.uniform(-0.02, 0.02)
                h = rnd.uniform(0.03, 0.075)
                a = rnd.uniform(0, 6.28)
                lean = rnd.uniform(0.0, 0.05)
                wdt = 0.0085
                dx, dy = math.cos(a + 1.57) * wdt, math.sin(a + 1.57) * wdt
                p0 = bm.verts.new((bx - dx, by - dy, G - 0.004))
                p1 = bm.verts.new((bx + dx, by + dy, G - 0.004))
                p2 = bm.verts.new((bx + math.cos(a) * lean, by + math.sin(a) * lean,
                                   G + h))
                bm.faces.new((p0, p1, p2))
            n += 1
        me = bpy.data.meshes.new(key)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(key, me)
        me.materials.append(M[key])
        bpy.context.scene.collection.objects.link(ob)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='docs/renders/hatchery_pro.png')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--scale', type=int, default=4)
    ap.add_argument('--blend')
    args = ap.parse_args(argv)
    rb.clear()
    build()
    lighting()
    setup_render(args.samples, args.scale, 4, 3)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.blend)
    render(args.out)


if __name__ == "__main__":
    main()
