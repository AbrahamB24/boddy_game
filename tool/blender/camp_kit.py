"""Shared parts of the four resource camps (wood and stone, small and large).

Props and materials used by buildings/small_wood_camp.py, large_wood_camp.py,
small_quarry.py and large_stone_camp.py, and by camp_mockups.py (the twenty
concepts these were chosen from, user 2026-11-03). Everything is built from
fw_kit's parts; coordinates are fw_kit's (x east, y north, yard at z = G).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fw_kit as F  # noqa: E402
from fw_kit import (DIM, G, P, D, beam, box, cyl, ellipsoid, rbox,  # noqa: E402,F401
                    plain, tex_mat)
import pro_kit as K  # noqa: E402

TAU = 2 * math.pi


# ── materials ──────────────────────────────────────────────
def mats():
    M = F.base_materials()
    M['bark'] = tex_mat('bark', 'dark_wood', 0.6, tint=(0.8, 0.6, 0.45), val=0.75)
    M['log_end'] = plain('log_end', '#dcb47c', rough=0.9, bump=0.3, bump_scale=80,
                         vary=0.15)
    M['pine'] = plain('pine', '#2f6b3a', rough=0.8, bump=0.5, bump_scale=60,
                      vary=0.15, speck='#3f8045')
    M['pine2'] = plain('pine2', '#3d7a34', rough=0.8, bump=0.5, bump_scale=60,
                       vary=0.15, speck='#58923f')
    M['rock'] = plain('rock', '#6f6c66', rough=0.85, bump=0.7, bump_scale=30,
                      vary=0.12, speck='#6f6b64')
    M['rock_cut'] = plain('rock_cut', '#d9cdb5', rough=0.8, bump=0.45,
                          bump_scale=45, vary=0.08, speck='#c2b49a')
    M['gravel'] = plain('gravel', '#b3a893', rough=0.9, bump=0.8, bump_scale=90,
                        vary=0.1, speck='#8d8473')
    M['water'] = plain('water', '#4a8fb5', rough=0.05, bump=0.08, bump_scale=30)
    M['fire'] = plain('fire', '#ffb347', emit='#ff7a1a', emit_strength=12, bump=0)
    M['ember'] = plain('ember', '#ff6a1a', emit='#ff4a10', emit_strength=5, bump=0)
    M['crystal'] = plain('crystal', '#8fe3ff', rough=0.1, emit='#4fc8ff',
                         emit_strength=6, bump=0)
    M['shingle'] = tex_mat('shingle', 'weathered_planks', 0.45,
                           tint=(1.0, 0.72, 0.5), sat=1.1, val=0.85, nstr=1.2)
    M['coal'] = plain('coal', '#2a2624', rough=0.6, bump=0.6, bump_scale=80)
    M['dark'] = plain('dark', '#1b1714', rough=0.9, bump=0)
    M['ox'] = plain('ox', '#8a5a32', rough=0.9, bump=0.3, bump_scale=80)
    return M


# ── small helpers ──────────────────────────────────────────
def log(M, p0, p1, r, mat='bark', ends=True, seg=12):
    """A round log between two points, with cut ends."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    q = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    ob = cyl(0, 0, -L / 2, r, r, L, M[mat], seg=seg)
    ob.rotation_euler = q
    ob.location = (p0 + p1) / 2
    if ends:
        e = cyl(0, 0, -L / 2 - 0.004, r * 0.86, r * 0.86, L + 0.008, M['log_end'],
                seg=seg)
        e.rotation_euler = q
        e.location = (p0 + p1) / 2
    return ob


def disc(M, c, axis, r, w, mat):
    c = Vector(c)
    a = Vector(axis).normalized()
    log(M, c - a * w / 2, c + a * w / 2, r, mat, ends=False, seg=16)


def fir(M, x, y, h, key='pine'):
    cyl(x, y, G, 0.035 * h, 0.025 * h, h * 0.3, M['bark'], seg=8)
    for f, r in ((0.16, 0.27), (0.38, 0.22), (0.58, 0.16), (0.76, 0.09)):
        cyl(x, y, G + h * f, r * h, 0.0, h * 0.34, M[key], seg=9)


def leafy(M, x, y, h, seed=0):
    rnd = random.Random(seed)
    cyl(x, y, G, 0.05 * h, 0.035 * h, h * 0.55, M['bark'], seg=8)
    for i in range(7):
        a = rnd.uniform(0, TAU)
        d = rnd.uniform(0, 0.18 * h)
        r = rnd.uniform(0.16, 0.24) * h
        ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d,
                  G + h * rnd.uniform(0.6, 0.85), r, r, r * 0.85,
                  M['leaf' if i % 2 else 'leaf2'], seg=12, rings=8)


def stump(M, x, y, r=0.09, h=0.1, axe=False):
    cyl(x, y, G, r * 1.15, r, h, M['bark'], seg=12)
    cyl(x, y, G + h - 0.002, r * 0.9, r * 0.9, 0.008, M['log_end'], seg=12)
    if axe:
        beam((x - 0.02, y + 0.01, G + h), (x - 0.12, y + 0.06, G + h + 0.16),
             0.018, M['timber'])
        rbox((x - 0.005, y, G + h + 0.01), (0.06, 0.012, 0.045), (0, 0.5, 0.3),
             M['iron'])


def log_stack(M, x, y, length, rows, r, axis='x', mat='bark'):
    """A pyramid of logs, lying along `axis`."""
    for i in range(rows):
        n = rows - i
        for k in range(n):
            o = (k - (n - 1) / 2) * 2 * r
            z = G + r + i * r * 1.72
            if axis == 'x':
                log(M, (x - length / 2, y + o, z), (x + length / 2, y + o, z), r, mat)
            else:
                log(M, (x + o, y - length / 2, z), (x + o, y + length / 2, z), r, mat)


def board_stack(M, x, y, sx, sy, h, rot=0.0, layers=6):
    """Sawn boards, stacked with spacers to dry."""
    t = h / layers
    for i in range(layers):
        rbox((x, y, G + t * (i + 0.5)), (sx, sy, t * 0.7), (0, 0, rot), M['planks'],
             bevel=0.003)
        for f in (-0.4, 0, 0.4):
            dx, dy = math.cos(rot) * f * sx, math.sin(rot) * f * sx
            rbox((x + dx, y + dy, G + t * i + t * 0.85), (0.02, sy + 0.01, t * 0.3),
                 (0, 0, rot), M['timber'], bevel=0)


def billets(M, x, y, length, h, depth=0.12, axis='x'):
    """Metre wood: split billets stacked between end posts."""
    rnd = random.Random(int(x * 100 + y * 7))
    r = 0.022
    nz = int(h / (2 * r))
    nl = int(length / (2 * r))
    for i in range(nz):
        for k in range(nl):
            o = -length / 2 + r + k * 2 * r + (i % 2) * r * 0.5
            z = G + r + i * 2 * r * 0.95
            j = rnd.uniform(-0.005, 0.005)
            if axis == 'x':
                beam((x + o, y - depth / 2 + j, z), (x + o, y + depth / 2 + j, z), 2 * r * 0.92,
                     M['log_end'] if (i + k) % 3 == 0 else M['planks'], bevel=0.005)
            else:
                beam((x - depth / 2 + j, y + o, z), (x + depth / 2 + j, y + o, z), 2 * r * 0.92,
                     M['log_end'] if (i + k) % 3 == 0 else M['planks'], bevel=0.005)
    for s in (-1, 1):
        if axis == 'x':
            beam((x + s * (length / 2 + 0.02), y, G), (x + s * (length / 2 + 0.02), y, G + h + 0.04),
                 0.03, M['timber'])
        else:
            beam((x, y + s * (length / 2 + 0.02), G), (x, y + s * (length / 2 + 0.02), G + h + 0.04),
                 0.03, M['timber'])


def holzmiete(M, x, y, r, h):
    """A round beehive woodpile with a bark cap."""
    n = int(h / 0.045)
    for i in range(n):
        rr = r * (1 - 0.25 * (i / n) ** 2)
        cyl(x, y, G + i * 0.045, rr, rr, 0.043, M['log_end' if i % 2 else 'planks'], seg=20)
    cyl(x, y, G + n * 0.045, r * 0.8, 0.02, r * 0.55, M['bark'], seg=20)


def sawhorse(M, x, y, rot=0.0, with_log=True):
    c, s = math.cos(rot), math.sin(rot)
    for f in (-0.13, 0.13):
        px, py = x + c * f, y + s * f
        for g in (-1, 1):
            beam((px - s * 0.08 * g, py + c * 0.08 * g, G), (px + s * 0.03 * g, py - c * 0.03 * g, G + 0.17),
                 0.02, M['timber'])
    if with_log:
        log(M, (x - c * 0.25, y - s * 0.25, G + 0.19), (x + c * 0.25, y + s * 0.25, G + 0.19), 0.045)
        rbox((x + c * 0.05, y + s * 0.05, G + 0.27), (0.008, 0.18, 0.08), (0, 0, rot), M['iron'])


def wheelbarrow(M, x, y, rot=0.0, load='rock', s=1.0):
    """A wheelbarrow heaped with `load`; s scales it (1.5 reads on the map)."""
    c, sn = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + (f * c - side * sn) * s, y + (f * sn + side * c) * s, G + z * s)
    rbox(at(0, 0, 0.1), (0.2 * s, 0.13 * s, 0.07 * s), (0, 0, rot), M['planks'], bevel=0.006)
    for g in (-1, 1):
        rbox(at(0.0, g * 0.065, 0.12), (0.2 * s, 0.015 * s, 0.07 * s), (0, 0, rot), M['planks'],
             bevel=0.004)
    rbox(at(0.1, 0, 0.12), (0.015 * s, 0.13 * s, 0.07 * s), (0, 0, rot), M['planks'], bevel=0.004)
    wp = at(0.15, 0, 0.05)
    disc(M, wp, (-sn, c, 0), 0.05 * s, 0.025 * s, 'timber')
    for g in (-1, 1):
        beam(at(0.14, g * 0.06, 0.05), at(-0.22, g * 0.07, 0.15), 0.02 * s, M['timber'])
        beam(at(-0.1, g * 0.07, 0.1), at(-0.12, g * 0.07, 0.0), 0.018 * s, M['timber'])
    for i in range(5):
        a = TAU * i / 5
        p = at(math.cos(a) * 0.05 + 0.01, math.sin(a) * 0.04, 0.17)
        ellipsoid(p[0], p[1], p[2], 0.04 * s, 0.035 * s, 0.03 * s, M[load], seg=8, rings=6)


def stone_block(M, x, y, z=None, s=(0.16, 0.12, 0.1), rot=0.0, mat='rock_cut'):
    z0 = G if z is None else z
    rbox((x, y, z0 + s[2] / 2), s, (0, 0, rot), M[mat], bevel=0.008)


def block_stack(M, x, y, nx, ny, nz, s=(0.16, 0.12, 0.1), seed=0):
    rnd = random.Random(seed)
    for k in range(nz):
        for i in range(nx - k):
            for j in range(ny):
                stone_block(M, x + (i - (nx - k - 1) / 2) * s[0] * 1.04,
                            y + (j - (ny - 1) / 2) * s[1] * 1.04, G + k * s[2],
                            s, rnd.uniform(-0.05, 0.05))


def rock_mass(M, cx, cy, sx, sy, h, seed=0, n=26, mat='rock', grass=True):
    """A rough outcrop of tilted boulders, highest in the middle."""
    rnd = random.Random(seed)
    rbox((cx, cy, G + h * 0.3), (sx * 0.72, sy * 0.72, h * 0.6), (0, 0, 0.2), M[mat],
         bevel=0.03)
    for _ in range(n):
        u, v = rnd.uniform(-1, 1), rnd.uniform(-1, 1)
        f = max(0.15, 1 - 0.6 * (u * u + v * v))
        s = rnd.uniform(0.22, 0.42) * min(sx, sy)
        hh = h * f * rnd.uniform(0.75, 1.05)
        rbox((cx + u * sx * 0.42, cy + v * sy * 0.42, G + hh / 2),
             (s, s * rnd.uniform(0.7, 1.3), hh),
             (rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), rnd.uniform(0, 3.14)),
             M[mat], bevel=0.02)
    if grass:
        for i in range(int(n / 3)):
            u, v = rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8)
            f = max(0.15, 1 - 0.6 * (u * u + v * v))
            r = rnd.uniform(0.07, 0.13)
            ellipsoid(cx + u * sx * 0.4, cy + v * sy * 0.4, G + h * f * 0.98, r, r, r * 0.45,
                      M['leaf2' if i % 2 else 'leaf'], seg=10, rings=6)


def cut_step(M, x0, x1, y0, y1, z0, z1, top='gravel'):
    """A quarried bench: a clean light block with a thin tread on top."""
    box((x0 + x1) / 2, (y0 + y1) / 2, z0, x1 - x0, y1 - y0, z1 - z0, M['rock_cut'],
        bevel=0.012)
    if top:
        box((x0 + x1) / 2, (y0 + y1) / 2, z1 - 0.005, x1 - x0 - 0.02, y1 - y0 - 0.02, 0.015,
            M[top], bevel=0.004)


def wheel(M, c, R, axis='x', n=12, width=0.1, paddles=False, t=0.028):
    c = Vector(c)
    ax = Vector((1, 0, 0)) if axis == 'x' else Vector((0, 1, 0))

    def pt(a, w, r=R):
        if axis == 'x':
            return c + Vector((w, math.cos(a) * r, math.sin(a) * r))
        return c + Vector((math.cos(a) * r, w, math.sin(a) * r))
    for side in (-width / 2, width / 2):
        for i in range(n):
            a0, a1 = TAU * i / n, TAU * (i + 1) / n
            beam(pt(a0, side), pt(a1, side), t, M['timber'])
        for i in range(0, n, 2):
            beam(c + ax * side, pt(TAU * i / n, side), t * 0.8, M['timber'])
    for i in range(n):
        a = TAU * (i + 0.5) / n
        if paddles:
            for k in range(3):
                rr = R + 0.02 + k * 0.035
                beam(pt(a, -width / 2 - 0.01, rr), pt(a, width / 2 + 0.01, rr), 0.03,
                     M['planks'])
        else:
            beam(pt(a, -width / 2, R * 0.97), pt(a, width / 2, R * 0.97), 0.022, M['planks'])
    beam(c - ax * (width / 2 + 0.08), c + ax * (width / 2 + 0.08), 0.045, M['iron'])


def rails(M, pts, z=None):
    z0 = G if z is None else z
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i] + (0,)), Vector(pts[i + 1] + (0,))
        d = (b - a)
        L = d.length
        dn = d.normalized()
        nrm = Vector((-dn.y, dn.x, 0))
        for g in (-0.055, 0.055):
            beam(a + nrm * g + Vector((0, 0, z0 + 0.03)), b + nrm * g + Vector((0, 0, z0 + 0.03)),
                 0.016, M['iron'], bevel=0)
        for k in range(int(L / 0.07) + 1):
            p = a + dn * (k * 0.07) + Vector((0, 0, z0 + 0.008))
            beam(p - nrm * 0.09, p + nrm * 0.09, 0.025, M['timber'], t2=0.016)


def mine_cart(M, x, y, rot=0.0, z=None, load='rock'):
    z0 = G if z is None else z
    c, s = math.cos(rot), math.sin(rot)
    rbox((x, y, z0 + 0.1), (0.2, 0.15, 0.09), (0, 0, rot), M['planks'], bevel=0.006)
    rbox((x, y, z0 + 0.1), (0.21, 0.155, 0.02), (0, 0, rot), M['iron'], bevel=0)
    for f in (-0.065, 0.065):
        for g in (-0.08, 0.08):
            disc(M, (x + c * f - s * g, y + s * f + c * g, z0 + 0.045), (-s, c, 0), 0.035, 0.015,
                 'iron')
    for i in range(5):
        a = TAU * i / 5
        ellipsoid(x + math.cos(a) * 0.04, y + math.sin(a) * 0.035, z0 + 0.155, 0.04, 0.035, 0.03,
                  M[load], seg=8, rings=6)


def tripod(M, x, y, h, hang=None):
    top = Vector((x, y, G + h))
    for a in (0.3, 2.4, 4.5):
        beam(top + Vector((0, 0, 0.03)), (x + math.cos(a) * h * 0.42, y + math.sin(a) * h * 0.42, G),
             0.03, M['timber'])
    if hang:
        beam(top, top - Vector((0, 0, h - hang - 0.02)), 0.008, M['iron'], bevel=0)
        ellipsoid(x, y, G + h - 0.04, 0.03, 0.03, 0.03, M['timber'], seg=8, rings=6)
        stone_block(M, x, y, G + hang - 0.12, (0.15, 0.12, 0.11), 0.3)


def crane(M, x, y, h, jib_to, hang_h, load='block'):
    """A post-and-jib crane: post, jib, strut, rope, load."""
    beam((x, y, G), (x, y, G + h), 0.06, M['timber'])
    box(x, y, G, 0.2, 0.2, 0.06, M['stone_dk'])
    tip = Vector((jib_to[0], jib_to[1], G + h + 0.1))
    beam((x, y, G + h - 0.05), tip, 0.045, M['timber'])
    top = Vector((x, y, G + h))
    beam((x, y, G + h * 0.55), top.lerp(tip, 0.5), 0.035, M["timber"])
    with F.anim("hoist", "bob", pivot=(tip.x, tip.y, tip.z), amp=0.05, period=2.6):
        beam(tip, (tip.x, tip.y, G + hang_h + 0.02), 0.014, M["iron"], bevel=0)
        if load == "block":
            stone_block(M, tip.x, tip.y, G + hang_h - 0.12, (0.17, 0.13, 0.12), 0.4)
        else:
            log(M, (tip.x - 0.22, tip.y, G + hang_h - 0.05), (tip.x + 0.22, tip.y, G + hang_h - 0.05), 0.045)
    return tip


def treadwheel_crane(M, x, y, h, jib_dir, jib_len, hang_h, load='block'):
    """A medieval treadwheel crane: a big wheel in an A-frame, a jib over it."""
    R = 0.32
    wheel(M, (x, y, G + R + 0.06), R, 'x', n=16, width=0.2)
    for g in (-1, 1):
        beam((x + g * 0.16, y - 0.3, G), (x + g * 0.16, y, G + R * 2 + 0.12), 0.04, M['timber'])
        beam((x + g * 0.16, y + 0.3, G), (x + g * 0.16, y, G + R * 2 + 0.12), 0.04, M['timber'])
    beam((x, y, G), (x, y, G + h), 0.07, M['timber'])
    d = Vector(jib_dir).normalized()
    tip = Vector((x + d.x * jib_len, y + d.y * jib_len, G + h + 0.15))
    beam((x - d.x * 0.25, y - d.y * 0.25, G + h - 0.06), tip, 0.05, M['timber'])
    beam((x, y, G + h * 0.6), (x + d.x * jib_len * 0.55, y + d.y * jib_len * 0.55, G + h + 0.02),
         0.035, M['timber'])
    with F.anim("hoist", "bob", pivot=(tip.x, tip.y, tip.z), amp=0.05, period=2.6):
        beam(tip, (tip.x, tip.y, G + hang_h + 0.02), 0.014, M["iron"], bevel=0)
        if load == "block":
            stone_block(M, tip.x, tip.y, G + hang_h - 0.13, (0.18, 0.14, 0.13), 0.4)
        else:
            log(M, (tip.x - 0.25, tip.y, G + hang_h - 0.05), (tip.x + 0.25, tip.y, G + hang_h - 0.05),
                0.05)
    return tip


def lean_to(M, x0, x1, y0, y1, zh, zl, low='s', mat='roof2', posts=True):
    """A shed roof on posts. `low` is the side the roof drains to."""
    if posts:
        for x in (x0 + 0.03, x1 - 0.03):
            for y in (y0 + 0.03, y1 - 0.03):
                lowside = ((low == 's' and y < (y0 + y1) / 2) or (low == 'n' and y > (y0 + y1) / 2) or
                           (low == 'e' and x > (x0 + x1) / 2) or (low == 'w' and x < (x0 + x1) / 2))
                beam((x, y, G), (x, y, zl if lowside else zh), 0.04, M['timber'])
    if low in ('s', 'n'):
        run = y1 - y0
        ang = math.atan2(zh - zl, run)
        L = math.hypot(run, zh - zl)
        eul = (ang if low == 's' else -ang, 0, 0)
        dims = (x1 - x0 + 0.12, L + 0.14, 0.04)
    else:
        run = x1 - x0
        ang = math.atan2(zh - zl, run)
        L = math.hypot(run, zh - zl)
        eul = (0, ang if low == 'e' else -ang, 0)
        dims = (L + 0.14, y1 - y0 + 0.12, 0.04)
    rbox(((x0 + x1) / 2, (y0 + y1) / 2, (zh + zl) / 2 + 0.03), dims, eul, M[mat], bevel=0.008)


def hut(M, x0, x1, y0, y1, eave, axis='y', door=None, wins=(), roof='roof', sign=None):
    """A one-storey half-timbered house. door = (face, a); wins = [(face, a, shut, glow)]."""
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    box(xm, ym, G, x1 - x0 + 0.06, y1 - y0 + 0.06, DIM['plinth'], M['stone_dk'], bevel=0.01)
    zpl = G + DIM['plinth']
    box(xm, ym, zpl, x1 - x0, y1 - y0, eave - zpl, M['plaster'], bevel=0.008)
    faces = {'s': (y0, x0, x1), 'n': (y1, x0, x1), 'e': (x1, y0, y1), 'w': (x0, y0, y1)}
    holes = {f: [] for f in faces}
    if door:
        holes[door[0]].append((door[1], DIM['door'][0]))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.3))
        F.wall_frame(M, f, fx, a0, a1, zpl, eave, nb, braces=(0, nb - 1), holes=holes[f])
    if door:
        f, a = door
        F.door(M, f, faces[f][0], a, *DIM['door'], zpl)
        F.lantern(M, f, faces[f][0], a + 0.16, zpl + DIM['door'][1] - 0.02)
    zc = zpl + min(0.36, (eave - zpl) * 0.55)
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, zc, *DIM['window'], shut, glow)
    if axis == 'y':
        F.gable_wall(M, 's', y0, x0, x1, eave)
        F.gable_wall(M, 'n', y1, x0, x1, eave)
        zr = F.gable_roof(M, xm, ym, eave, y1 - y0, x1 - x0, 'y', M[roof], oh=0.1, oe=0.1)
    else:
        F.gable_wall(M, 'e', x1, y0, y1, eave)
        F.gable_wall(M, 'w', x0, y0, y1, eave)
        zr = F.gable_roof(M, xm, ym, eave, x1 - x0, y1 - y0, 'x', M[roof], oh=0.1, oe=0.1)
    if sign:
        f, a, emb, *sz = sign
        F.hanging_sign(M, f, faces[f][0], a, eave - 0.02, emblem(M, f, emb),
                       size=sz[0] if sz else F.m(1.4))
    return zr


def log_cabin(M, x0, x1, y0, y1, eave, axis='y', door=None, wins=(), roof='shingle', sign=None):
    """Walls of stacked round logs with crossed corners."""
    r = 0.04
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    box(xm, ym, G, x1 - x0 + 0.1, y1 - y0 + 0.1, 0.05, M['stone_dk'], bevel=0.01)
    box(xm, ym, G + 0.05, x1 - x0 - 0.02, y1 - y0 - 0.02, eave - G - 0.05, M['planks'], bevel=0)
    z = G + 0.05 + r
    i = 0
    while z < eave:
        ov = 0.07
        if i % 2 == 0:
            for y in (y0, y1):
                log(M, (x0 - ov, y, z), (x1 + ov, y, z), r)
        else:
            for x in (x0, x1):
                log(M, (x, y0 - ov, z), (x, y1 + ov, z), r)
        z += r * 1.0
        i += 1
    faces = {'s': (y0 - r, x0, x1), 'n': (y1 + r, x0, x1), 'e': (x1 + r, y0, y1),
             'w': (x0 - r, y0, y1)}
    zpl = G + 0.05
    if door:
        f, a = door
        F.door(M, f, faces[f][0], a, *DIM['door'], zpl)
        F.lantern(M, f, faces[f][0], a + 0.16, zpl + DIM['door'][1] - 0.02)
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, zpl + 0.36, *DIM['window'], shut, glow)
    if axis == 'y':
        for f, fy in (('s', y0), ('n', y1)):
            F.gable_fill(M, f, fy, x0 - 0.02, x1 + 0.02, eave, mat='planks')
        zr = F.gable_roof(M, xm, ym, eave, y1 - y0, x1 - x0, 'y', M[roof], oh=0.12, oe=0.12)
    else:
        for f, fx in (('e', x1), ('w', x0)):
            F.gable_fill(M, f, fx, y0 - 0.02, y1 + 0.02, eave, mat='planks')
        zr = F.gable_roof(M, xm, ym, eave, x1 - x0, y1 - y0, 'x', M[roof], oh=0.12, oe=0.12)
    if sign:
        f, a, emb, *sz = sign
        F.hanging_sign(M, f, faces[f][0], a, eave - 0.02, emblem(M, f, emb),
                       size=sz[0] if sz else F.m(1.4))
    return zr


# ── guild emblems (drawn flat on a sign board) ─────────────
def emblem(M, face, kind):
    def flat(c, u, v, w, h, rot, mat):
        if face in ('s', 'n'):
            p = Vector((c.x + u, c.y, c.z + v))
            eul = (0, rot, 0)
        else:
            p = Vector((c.x, c.y + u, c.z + v))
            eul = (rot, 0, 0)
        rbox(p, D(face, w, 0.04, h), eul, M[mat], bevel=0.002)

    def draw(c, size):
        s = size
        if kind == 'axe':
            flat(c, 0, -0.02 * s, 0.09 * s, 0.75 * s, 0.5, 'timber')
            flat(c, 0.13 * s, 0.17 * s, 0.32 * s, 0.24 * s, 0.5, 'iron')
        elif kind == 'saw':
            flat(c, 0, 0, 0.7 * s, 0.16 * s, 0.0, 'iron')
            flat(c, -0.38 * s, 0, 0.1 * s, 0.3 * s, 0.0, 'timber')
            for i in range(6):
                flat(c, (-0.28 + i * 0.11) * s, -0.1 * s, 0.05 * s, 0.05 * s, 0.78, 'iron')
        elif kind == 'tree':
            flat(c, 0, -0.26 * s, 0.08 * s, 0.18 * s, 0, 'timber')
            for k, (w, z) in enumerate(((0.6, -0.1), (0.44, 0.08), (0.26, 0.24))):
                flat(c, 0, z * s, w * s, 0.17 * s, 0, 'pine')
        elif kind == 'pick':
            flat(c, 0, -0.04 * s, 0.08 * s, 0.7 * s, -0.5, 'timber')
            flat(c, -0.1 * s, 0.2 * s, 0.6 * s, 0.08 * s, -0.5 + 0.25, 'iron')
        elif kind == 'hammer':
            flat(c, -0.1 * s, -0.04 * s, 0.07 * s, 0.6 * s, 0.6, 'timber')
            flat(c, 0.05 * s, 0.2 * s, 0.32 * s, 0.17 * s, 0.6, 'iron')
            flat(c, 0.1 * s, -0.02 * s, 0.06 * s, 0.6 * s, -0.6, 'iron')
        elif kind == 'block':
            flat(c, 0, 0, 0.55 * s, 0.42 * s, 0, 'rock_cut')
            flat(c, 0, 0, 0.58 * s, 0.03 * s, 0, 'dark')
            flat(c, 0, 0, 0.03 * s, 0.44 * s, 0, 'dark')
        elif kind == 'crystal':
            for u, h, r in ((-0.15, 0.45, 0.2), (0.05, 0.62, -0.1), (0.2, 0.38, -0.35)):
                flat(c, u * s, 0, 0.13 * s, h * s, r, 'crystal')
    return draw


def signpost(M, x, y, face, kind, h=0.5, size=0.3):
    beam((x, y, G), (x, y, G + h + size * 0.45), 0.04, M['timber'])
    off = 0.025
    c = P(face, y if face in ('s', 'n') else x, x if face in ('s', 'n') else y, G + h, off)
    rbox(c, D(face, size, 0.025, size * 0.8), (0, 0, 0), M['planks'], bevel=0.004)
    emblem(M, face, kind)(P(face, y if face in ('s', 'n') else x, x if face in ('s', 'n') else y,
                             G + h, off + 0.02), size)


def ladder(M, p0, p1, w=0.1):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    side = Vector((-d.y, d.x, 0)).normalized() if abs(d.x) + abs(d.y) > 1e-4 else Vector((1, 0, 0))
    for g in (-1, 1):
        beam(p0 + side * g * w / 2, p1 + side * g * w / 2, 0.018, M['timber'])
    n = int(d.length / 0.07)
    for k in range(1, n):
        p = p0 + d * (k / n)
        beam(p - side * w / 2, p + side * w / 2, 0.012, M['timber'])


def dirt(M, x, y, rx, ry, seed=0, mat='dirt'):
    """A worn patch of yard. 3 cm thick so the voxeliser keeps it."""
    K.blob(x, y, rx, ry, G - 0.004, 0.03, M[mat], seed=seed)


def water_channel(M, x0, x1, y0, y1, z=None):
    z0 = G if z is None else z
    box((x0 + x1) / 2, (y0 + y1) / 2, z0, x1 - x0, y1 - y0, 0.06, M['planks'], bevel=0.004)
    box((x0 + x1) / 2, (y0 + y1) / 2, z0 + 0.045, x1 - x0 - 0.04, y1 - y0 - 0.04, 0.01,
        M['water'], bevel=0)


def path(pts, seed=3, width=0.27):
    """Mockups only: cobbles with the palette the mockup main() registered."""
    F.cobble_path(K._mats_ref, pts, seed=seed, width=width)
