"""The Small House: a narrow half-timbered family home on its own plot.

Footprint 2 x 2 tiles (10 x 10 m) — tier D, the smallest a building with a
yard can be. The house itself is 5.5 x 6.5 m: a full ground floor and a lower
upper floor under a 50-degree roof, its gable to the camera.

Reads as: people live here. Washing on a line, a fenced vegetable bed, a bench
with a cat by the door, firewood against the wall, a chimney (the app draws
its smoke), flower boxes, warm windows. No guild sign — a home has none.

All four sides are modelled (the house can later be turned). The ENTRANCE is
the east side's southern cell: the door opens east and the cobbled path runs
to that cell's outer edge, where the road has to be.

Moving parts: each piece of washing (hanging from the line), every flower
box, flower patch and bush, the cat's tail; the lantern flickers and the lit
windows breathe.

Layout (x east, y north; the camera looks from +x/-y):

    house (ridge along y, gable south)        woodpile, bush
    vegetable bed + fence    washing line     path from the door to the
                                              entrance cell (east, south)
"""
import math
import random

from mathutils import Vector

from fw_kit import *  # noqa: F401,F403

ID = 'small_house'
W, H = 2, 2

# the house box, authoring coordinates
X0, X1, Y0, Y1 = -0.80, 0.30, -0.45, 0.85
J = DIM['jetty'] * 1.0          # upper floor overhangs the south gable
Z_PL = G + DIM['plinth']        # top of the stone plinth
Z_UP = G + 0.80                 # ground floor top / upper floor bottom
Z_EAVE = G + 1.42               # wall top = eave
# the chimney pots' mouth (smoke anchor)
CHX, CHY, CHZ0, CHH = -0.25, 0.52, G + 1.67, 0.62
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)
# the door on the east wall, and the entrance cell its path leads to
YD = -0.20
ENTRANCE = ('e', 0)


def materials():
    M = base_materials()
    M['cabbage'] = plain('cabbage', '#7fae3c', rough=0.7, bump=0.5,
                         bump_scale=60, vary=0.15, speck='#a6c95a')
    M['carrot_top'] = plain('carrot_top', '#4e8d2a', rough=0.8, bump=0.0,
                            vary=0.2)
    M['bed'] = tex_mat('bed', 'park_dirt', 0.8, tint=(0.62, 0.45, 0.32),
                       sat=1.0, val=0.6, nstr=1.2, vary=0.05)
    M['shirt_b'] = plain('shirt_b', '#4f7fc4', rough=0.95, bump=0.2,
                         bump_scale=120, vary=0.05)
    M['shirt_r'] = plain('shirt_r', '#c8463a', rough=0.95, bump=0.2,
                         bump_scale=120, vary=0.05)
    M['cat'] = plain('cat', '#d9822b', rough=0.9, bump=0.4, bump_scale=90,
                     vary=0.05)
    M['log_end'] = plain('log_end', '#d8b07a', rough=0.9, bump=0.3,
                         bump_scale=80, vary=0.15)
    return M


def fence(M, pts, h=0.16, step=0.06):
    """A picket fence along a polyline at yard level."""
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i] + (G,)), Vector(pts[i + 1] + (G,))
        L = (b - a).length
        n = max(1, int(L / step))
        for k in range(n + 1):
            p = a + (b - a) * (k / n)
            beam(p, p + Vector((0, 0, h)), 0.022, M['planks'], bevel=0.003)
        for z in (h * 0.35, h * 0.8):
            beam(a + Vector((0, 0, z)), b + Vector((0, 0, z)), 0.016,
                 M['timber'], bevel=0.002)


def veg_bed(M, x0, x1, y0, y1, seed=3):
    rnd = random.Random(seed)
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 0.03, M['bed'],
        bevel=0.008)
    rows = 3
    for r in range(rows):
        y = y0 + (y1 - y0) * (r + 0.5) / rows
        n = int((x1 - x0) / 0.08)
        for k in range(n):
            x = x0 + 0.05 + (x1 - x0 - 0.1) * k / max(1, n - 1)
            if r == 1:                       # carrots: a tuft of leaves
                for _ in range(3):
                    a = rnd.uniform(0, 6.28)
                    beam((x, y, G + 0.03), (x + math.cos(a) * 0.02,
                                           y + math.sin(a) * 0.02, G + 0.08),
                         0.012, M['carrot_top'], bevel=0)
            else:                            # cabbages
                rr = rnd.uniform(0.028, 0.036)
                ellipsoid(x, y, G + 0.03 + rr * 0.7, rr, rr, rr * 0.8,
                          M['cabbage'], seg=10, rings=8)


def washing_line(M, a, b, h=0.40):
    """Two posts, a line, and laundry hanging from it."""
    a, b = Vector(a + (G,)), Vector(b + (G,))
    for p in (a, b):
        beam(p, p + Vector((0, 0, h + 0.02)), 0.03, M['timber'])
    top_a, top_b = a + Vector((0, 0, h)), b + Vector((0, 0, h))
    beam(top_a, top_b, 0.012, M['linen'], bevel=0)
    d = (top_b - top_a)
    rot = math.atan2(d.y, d.x)
    items = [(0.17, 0.15, 'linen'), (0.09, 0.11, 'shirt_b'),
             (0.09, 0.11, 'shirt_r'), (0.15, 0.13, 'awning'),
             (0.07, 0.09, 'mustard')]
    total = sum(w for w, _, _ in items) + 0.03 * (len(items) - 1)
    t = (1 - total / d.length) / 2
    for w, hh, key in items:
        c = top_a + d * (t + w / 2 / d.length)
        # each piece swings on its own from where it is pegged
        with anim(f'wash_{key}', 'sway', pivot=(c.x, c.y, c.z), amp=0.16,
                  period=2.4):
            rbox((c.x, c.y, c.z - hh / 2 - 0.006), (w, 0.012, hh), (0, 0, rot),
                 M[key], bevel=0.003)
        t += (w + 0.03) / d.length


def woodpile(M, x, y0, y1, h=0.2):
    """Split logs stacked against the east wall, ends toward the camera."""
    rnd = random.Random(8)
    r = 0.028
    rows = int(h / (2 * r))
    n = int((y1 - y0) / (2 * r))
    for i in range(rows):
        for k in range(n - (i % 2)):
            y = y0 + r + k * 2 * r + (i % 2) * r
            z = G + r + i * 2 * r * 0.92
            xx = x + rnd.uniform(-0.01, 0.01)
            beam((xx - 0.07, y, z), (xx + 0.07, y, z), 2 * r * 0.95,
                 M['log_end'] if (i + k) % 3 == 0 else M['planks'], bevel=0.006)
    # a little roof over the pile
    rbox((x, (y0 + y1) / 2, G + h + 0.05), (0.2, y1 - y0 + 0.08, 0.025),
         (0, math.radians(-18), 0), M['roof2'], bevel=0.005)


def cat(M, x, y, z, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)

    def at(dx, dz):
        return (x + dx * c, y + dx * s, z + dz)
    ellipsoid(*at(0, 0.035), 0.05, 0.032, 0.035, M['cat'], tilt=(0, 0, rot))
    ellipsoid(*at(0.05, 0.065), 0.024, 0.024, 0.022, M['cat'], seg=10, rings=8)
    for sg in (-1, 1):
        ex, ey = x + 0.055 * c - sg * 0.013 * s, y + 0.055 * s + sg * 0.013 * c
        ellipsoid(ex, ey, z + 0.09, 0.008, 0.008, 0.014, M['cat'], seg=6,
                  rings=4)
    # the tail hangs over the bench's edge and flicks
    with anim('cat_tail', 'sway', pivot=at(-0.04, 0.012), amp=0.35, period=1.9):
        beam(at(-0.04, 0.012), at(-0.07, -0.085), 0.02, M['cat'], bevel=0)


def bench(M, x, y0, y1):
    """A plank bench against the east wall, seat 45 cm high."""
    seat = m(0.45)
    rbox((x, (y0 + y1) / 2, G + seat), (0.07, y1 - y0, 0.018), (0, 0, 0),
         M['planks'], bevel=0.004)
    for y in (y0 + 0.03, y1 - 0.03):
        rbox((x, y, G + seat / 2), (0.06, 0.02, seat), (0, 0, 0), M['timber'],
             bevel=0.003)


def build():
    random.seed(17)
    M = materials()
    xm = (X0 + X1) / 2
    span = X1 - X0

    # ── the house ─────────────────────────────────────────
    box(xm, (Y0 + Y1) / 2, G, span + 0.06, Y1 - Y0 + 0.06, DIM['plinth'],
        M['stone_dk'], bevel=0.01)
    box(xm, (Y0 + Y1) / 2, Z_PL, span, Y1 - Y0, Z_UP - Z_PL, M['plaster'],
        bevel=0.008)
    box(xm, (Y0 - J + Y1) / 2, Z_UP, span, Y1 - Y0 + J, Z_EAVE - Z_UP,
        M['plaster'], bevel=0.008)
    # joist ends under the south jetty + the bressummer over them
    for i in range(9):
        x = X0 + 0.07 + (span - 0.14) * i / 8
        rbox((x, Y0 - J / 2 + 0.005, Z_UP - 0.03), (0.05, J + 0.02, 0.05),
             (0, 0, 0), M['timber'])
    beam((X0, Y0 - J, Z_UP + 0.02), (X1, Y0 - J, Z_UP + 0.02), 0.075,
         M['timber'])

    win, win_up, win_s = DIM['window'], DIM['window_up'], DIM['window_small']
    door_w, door_h = DIM['door']
    zc0 = Z_PL + 0.42                   # ground-floor window centre
    zc1 = Z_UP + 0.25                   # upper-floor window centre

    # south (gable) face
    wall_frame(M, 's', Y0, X0, X1, Z_PL, Z_UP, 4, braces=(0, 3),
               holes=[(-0.55, win[0]), (-0.05, win[0])])
    window(M, 's', Y0, -0.55, zc0, *win, 'teal', glow=True,
           planter=['fl_red', 'fl_white'])
    window(M, 's', Y0, -0.05, zc0, *win, 'teal',
           planter=['fl_pink', 'fl_yel'])
    wall_frame(M, 's', Y0 - J, X0, X1, Z_UP + 0.045, Z_EAVE - 0.03, 4,
               braces=(0, 3), holes=[(xm, win_up[0])])
    window(M, 's', Y0 - J, xm, zc1, *win_up, 'red', glow=True)
    gable_wall(M, 's', Y0 - J, X0 - 0.0, X1, Z_EAVE)
    window(M, 's', Y0 - J, xm, Z_EAVE + 0.17, win_s[0] * 0.9, win_s[1] * 0.9,
           shut=None)

    # north (back gable) face — modelled like the front, so the house can
    # later be turned (user 2026-11-03)
    wall_frame(M, 'n', Y1, X0, X1, Z_PL, Z_UP, 4, braces=(0, 3),
               holes=[(-0.55, win[0]), (-0.05, win[0])])
    window(M, 'n', Y1, -0.55, zc0, *win, 'teal')
    window(M, 'n', Y1, -0.05, zc0, *win, 'red', glow=True,
           planter=['fl_white', 'fl_blue'])
    wall_frame(M, 'n', Y1, X0, X1, Z_UP + 0.045, Z_EAVE - 0.03, 4,
               braces=(0, 3), holes=[(xm, win_up[0])])
    window(M, 'n', Y1, xm, zc1, *win_up, 'teal', glow=True)
    gable_wall(M, 'n', Y1, X0, X1, Z_EAVE)
    window(M, 'n', Y1, xm, Z_EAVE + 0.17, win_s[0] * 0.9, win_s[1] * 0.9,
           shut=None)

    # east (long) face: the door, a window with the bench under it, woodpile
    wall_frame(M, 'e', X1, Y0, Y1, Z_PL, Z_UP, 5, braces=(0, 4), mid=True,
               holes=[(YD, door_w), (0.32, win[0])])
    door(M, 'e', X1, YD, door_w, door_h, Z_PL)
    window(M, 'e', X1, 0.32, zc0, *win, 'mustard', glow=True)
    wall_frame(M, 'e', X1, Y0 - J, Y1, Z_UP + 0.045, Z_EAVE - 0.03, 5,
               braces=(0, 1, 3, 4), holes=[(-0.20, win_up[0]), (0.50, win_up[0])])
    window(M, 'e', X1, -0.20, zc1, *win_up, 'teal')
    window(M, 'e', X1, 0.50, zc1, *win_up, 'red', glow=True,
           planter=['fl_red', 'fl_pink'])
    lantern(M, 'e', X1, YD + 0.17, Z_PL + door_h - 0.02)

    # west (long) face
    wall_frame(M, 'w', X0, Y0, Y1, Z_PL, Z_UP, 5, braces=(0, 4), mid=True,
               holes=[(-0.12, win[0]), (0.48, win[0])])
    window(M, 'w', X0, -0.12, zc0, *win, 'teal', planter=['fl_yel', 'fl_red'])
    window(M, 'w', X0, 0.48, zc0, *win, 'red', glow=True)
    wall_frame(M, 'w', X0, Y0 - J, Y1, Z_UP + 0.045, Z_EAVE - 0.03, 5,
               braces=(0, 1, 3, 4), holes=[(-0.20, win_up[0]), (0.50, win_up[0])])
    window(M, 'w', X0, -0.20, zc1, *win_up, 'mustard', glow=True)
    window(M, 'w', X0, 0.50, zc1, *win_up, 'teal')

    # roof + chimney
    gable_roof(M, xm, (Y0 - J + Y1) / 2, Z_EAVE, Y1 - (Y0 - J), span, 'y',
               M['roof'], oh=0.13, oe=0.14)
    chimney(M, CHX, CHY, CHZ0, CHH)

    # ── the yard ──────────────────────────────────────────
    # The path runs from the door to the middle of the entrance cell's outer
    # edge, where the road has to be.
    ex, ey = entrance_point(W, H, *ENTRANCE)
    cobble_path(M, [(X1 + 0.10, YD), (0.70, ey + 0.08), (ex, ey)], seed=4)
    bench(M, X1 + 0.07, 0.18, 0.46)
    cat(M, X1 + 0.07, 0.30, G + m(0.45) + 0.01, rot=math.radians(-110))
    woodpile(M, X1 + 0.09, 0.58, 0.84)
    barrel(M, X1 + 0.09, -0.52, r=0.07, h=0.17)          # rain butt

    veg_bed(M, -0.92, -0.32, -0.94, -0.64)
    fence(M, [(-0.97, -0.58), (-0.27, -0.58), (-0.27, -0.98)])
    washing_line(M, (-0.12, -0.92), (0.50, -0.66))

    bush(M, 0.80, 0.78, 0.17, 1, ['fl_white', 'fl_pink'])
    bush(M, -0.92, 0.92, 0.14, 2)
    bush(M, 0.88, 0.30, 0.12, 3, ['fl_yel'])
    flower_patch(M, 0.12, -0.62, 7, ['fl_red', 'fl_yel'], 5)
    flower_patch(M, 0.62, 0.52, 6, ['fl_blue', 'fl_white'], 6)
    flower_patch(M, -0.92, -0.30, 5, ['fl_pink'], 7, rx=0.06)
    flower_patch(M, -0.30, 0.95, 5, ['fl_yel', 'fl_white'], 8, ry=0.04)
