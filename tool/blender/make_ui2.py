"""The second interface look (user 2026-11-05): bronze medals, framed plaques, a
dark-steel treasure chest with blue light, no continuous header band.

    blender --background --python tool/blender/make_ui2.py -- button compass chest \
        badge_bolt badge_knot plaque_wood plaque_stone plaque_scroll [--samples N --px N]

Registers its pieces into make_ui.PIECES (replacing button / compass / chest) and
runs make_ui's own renderer, so the output lands in assets/images/ui/ as before.
Everything here is built upright (X right, Z up, face towards -Y).
"""
import math
import sys
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon_lib as L  # noqa: E402
import make_ui as U  # noqa: E402
import pro_kit as K  # noqa: E402
from icon_lib import box, ball, cyl, ring, lathe, poly, circ, starp  # noqa: E402
from pro_kit import plain  # noqa: E402

TAU = math.tau


def mats():
    P = {}
    P['bronze'] = plain('b2_bronze', '#b9833f', rough=0.34, metal=1.0, bump=0.1, bump_scale=60, vary=0.05)
    P['bronze_dk'] = plain('b2_bronze_dk', '#7a4c20', rough=0.42, metal=1.0, bump=0.14, bump_scale=50, vary=0.06)
    P['bronze_lt'] = plain('b2_bronze_lt', '#dca25a', rough=0.3, metal=1.0, bump=0.05, bump_scale=80, vary=0.04)
    P['dish'] = plain('b2_dish', '#241810', rough=0.45, metal=0.2, bump=0.05, bump_scale=60, vary=0.0)
    P['navy'] = plain('b2_navy', '#121a2a', rough=0.35, metal=0.3, bump=0.06, bump_scale=70, vary=0.0)
    P['steel'] = plain('b2_steel', '#7d8aa0', rough=0.34, metal=1.0, bump=0.12, bump_scale=60, vary=0.04)
    P['steel_dk'] = plain('b2_steel_dk', '#3a4458', rough=0.42, metal=1.0, bump=0.15, bump_scale=50, vary=0.05)
    P['silver'] = plain('b2_silver', '#cfd5dc', rough=0.25, metal=1.0, bump=0.04, bump_scale=90, vary=0.03)
    P['glow_blue'] = plain('b2_glow_blue', '#7ad4ff', rough=0.3, bump=0, vary=0.0, emit='#4fb8ff', emit_strength=6.0)
    P['glow_cyan'] = plain('b2_glow_cyan', '#c8f4ff', rough=0.3, bump=0, vary=0.0, emit='#8fe8ff', emit_strength=8.0)
    P['ruby'] = plain('b2_ruby', '#d8262c', rough=0.1, bump=0, vary=0.0, emit='#d8262c', emit_strength=0.8)
    P['sapph'] = plain('b2_sapph', '#2a6fe0', rough=0.1, bump=0, vary=0.0, emit='#2a6fe0', emit_strength=0.8)
    P['emer'] = plain('b2_emer', '#2fa84f', rough=0.1, bump=0, vary=0.0, emit='#2fa84f', emit_strength=0.6)
    P['dwood'] = plain('b2_dwood', '#3a2616', rough=0.7, bump=0.4, bump_scale=70, vary=0.08)
    P['wood_lt'] = plain('b2_wood_lt', '#c9955a', rough=0.7, bump=0.4, bump_scale=60, vary=0.1)
    P['slate'] = plain('b2_slate', '#3d4a5e', rough=0.6, bump=0.3, bump_scale=60, vary=0.06)
    P['patina'] = plain('b2_patina', '#2f6a55', rough=0.7, metal=0.4, bump=0.3, bump_scale=60, vary=0.06)
    return P


def medal(P, R=1.0, ring_m='bronze', dish_m='dish', beads=28, groove=True):
    """A round medal: a bevelled ring, a beaded edge and a dark dish."""
    prof = [(0, 0), (R, 0), (R, 0.12), (R * 0.94, 0.20), (R * 0.80, 0.22), (R * 0.72, 0.14), (R * 0.66, 0.08), (0, 0.08)]
    lathe(prof, P[ring_m], rot=(90, 0, 0), sub=1)
    d = lathe([(0, 0.075), (R * 0.67, 0.075), (R * 0.67, 0.09), (0, 0.09)], P[dish_m], rot=(90, 0, 0), sub=0)
    for p in d.data.polygons:
        p.use_smooth = False
    for i in range(beads):
        a = i * TAU / beads
        ball(R * 0.985 * math.cos(a), -0.12, R * 0.985 * math.sin(a), 0.052 * R, 0.04, 0.052 * R, P['bronze_lt'], seg=12)
    if groove:
        ring(0, -0.16, 0, R * 0.70, 0.02 * R, P['bronze_dk'])


def piece_button(M):
    P = mats()
    medal(P)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        ball(0.87 * math.cos(a), -0.2, 0.87 * math.sin(a), 0.045, 0.03, 0.045, P['bronze_lt'], seg=12)
    return [], 2.3


def piece_compass(M):
    """The bottom-left medal: bronze ring set with gems, a compass rose, a globe."""
    P = mats()
    medal(P, 1.0, 'bronze', 'navy', beads=36)
    for ang, g in ((180, 'ruby'), (90, 'sapph'), (0, 'ruby'), (270, 'sapph')):
        a = math.radians(ang)
        x, z = 0.86 * math.cos(a), 0.86 * math.sin(a)
        ring(x, -0.2, z, 0.12, 0.025, P['bronze_lt'])
        ball(x, -0.2, z, 0.095, 0.05, 0.095, P[g], seg=16)
    # compass rose
    for ang, ro, ri, m in ((90, 0.60, 0.11, 'silver'), (45, 0.42, 0.09, 'steel')):
        n = 4
        pts = [((ro if i % 2 == 0 else ri) * math.cos(math.radians(ang) + i * math.pi / n),
                (ro if i % 2 == 0 else ri) * math.sin(math.radians(ang) + i * math.pi / n)) for i in range(2 * n)]
        poly(pts, 0.05, P[m], y=-0.14 - (0.02 if m == 'steel' else 0), bev=0.01)
    ring(0, -0.18, 0, 0.55, 0.018, P['bronze'])
    ring(0, -0.2, 0, 0.27, 0.035, P['bronze_lt'])
    ball(0, -0.21, 0, 0.2, 0.12, 0.2, U.globe_mat(), seg=32)
    return [], 2.3


def piece_chest(M):
    """The header's centre: a dark-steel medal with a blue glow, and a closed
    dark treasure chest whose lock burns blue."""
    P = mats()
    medal(P, 1.0, 'steel', 'navy', beads=32)
    ring(0, -0.15, 0, 0.8, 0.028, P['glow_blue'])
    ring(0, -0.18, 0, 0.64, 0.012, P['glow_cyan'])
    W, D, H = 1.1, 0.62, 0.50
    cx, cz0 = 0.0, -0.40
    box(cx, -0.45, cz0 + H / 2, W, D, H, P['dwood'], bev=0.03)
    # domed lid
    bpy.ops.mesh.primitive_cylinder_add(radius=D / 2, depth=W, location=(cx, -0.45, cz0 + H), vertices=40, rotation=(0, math.pi / 2, 0))
    lid = bpy.context.object
    lid.scale = (0.55, 1.0, 1.0)
    for p in lid.data.polygons:
        p.use_smooth = True
    lid.data.materials.append(P['dwood'])
    for x in (-0.38, 0.0, 0.38):
        box(cx + x, -0.45 - D / 2 - 0.012, cz0 + H / 2, 0.1, 0.03, H + 0.04, P['steel_dk'], bev=0.01)
        bpy.ops.mesh.primitive_cylinder_add(radius=D / 2 + 0.012, depth=0.1, location=(cx + x, -0.45, cz0 + H), vertices=40, rotation=(0, math.pi / 2, 0))
        b = bpy.context.object
        b.scale = (0.55, 1.0, 1.0)
        b.data.materials.append(P['steel'])
    box(cx, -0.45 - D / 2 - 0.02, cz0 + H - 0.03, W + 0.03, 0.04, 0.07, P['steel'], bev=0.01)
    for sx in (-1, 1):
        for sz in (0.06, H - 0.06):
            box(cx + sx * (W / 2 - 0.01), -0.45 - D / 2 - 0.02, cz0 + sz, 0.1, 0.03, 0.1, P['steel'], bev=0.01)
    box(cx, -0.45 - D / 2 - 0.04, cz0 + H - 0.02, 0.16, 0.04, 0.2, P['steel_dk'], bev=0.015)
    ball(cx, -0.45 - D / 2 - 0.07, cz0 + H - 0.04, 0.04, 0.02, 0.05, P['glow_cyan'], seg=12)
    return [], 2.3


def piece_badge_bolt(M):
    P = mats()
    medal(P, 1.0, 'bronze_dk', 'navy', beads=0, groove=False)
    ring(0, -0.15, 0, 0.78, 0.025, P['glow_blue'])
    pts = [(0.12, 0.74), (-0.36, -0.04), (-0.03, -0.04), (-0.16, -0.74), (0.38, 0.12), (0.04, 0.12)]
    poly(pts, 0.09, P['glow_cyan'], y=-0.2, bev=0.02)
    return [], 2.3


def piece_badge_knot(M):
    """A small bronze medal with a triple knot."""
    P = mats()
    medal(P, 1.0, 'bronze', 'navy', beads=0, groove=False)
    for k in range(3):
        a = k * 120
        o = ring(0.16 * math.cos(math.radians(a + 90)), -0.17 - k * 0.01, 0.16 * math.sin(math.radians(a + 90)), 0.34, 0.05, P['bronze_lt'])
    ring(0, -0.15, 0, 0.78, 0.02, P['bronze_dk'])
    return [], 2.3


def plaque(P, W, Hh, frame_m, panel_m, cap_m, T=0.2):
    box(0, 0.03, 0, W - 0.2, 0.06, Hh - 0.2, P[panel_m], bev=0.02)
    box(0, 0, Hh / 2 - T / 2, W, 0.2, T, P[frame_m], bev=0.04)
    box(0, 0, -Hh / 2 + T / 2, W, 0.2, T, P[frame_m], bev=0.04)
    for sx in (-1, 1):
        box(sx * (W / 2 - T / 2), 0, 0, T, 0.2, Hh, P[frame_m], bev=0.04)
        for sz in (-1, 1):
            box(sx * (W / 2 - T / 2), -0.12, sz * (Hh / 2 - T / 2), T * 1.05, 0.06, T * 1.05, P[cap_m], bev=0.03)
            ball(sx * (W / 2 - T / 2), -0.17, sz * (Hh / 2 - T / 2), 0.035, 0.02, 0.035, P['bronze_lt'], seg=10)
    # an inner lip
    box(0, -0.05, Hh / 2 - T - 0.02, W - 0.5, 0.05, 0.03, P['dwood'], bev=0.01)
    box(0, -0.05, -Hh / 2 + T + 0.02, W - 0.5, 0.05, 0.03, P['dwood'], bev=0.01)


def piece_plaque_wood(M):
    P = mats()
    plaque(P, 3.0, 1.0, 'dwood', 'wood_lt', 'bronze')
    return [], None


def piece_plaque_stone(M):
    P = mats()
    plaque(P, 3.0, 1.0, 'steel_dk', 'slate', 'steel')
    return [], None


def piece_plaque_scroll(M):
    P = mats()
    paper = U.parch_mat('b2_paper', '#f2e6c4', '#d8c28a')
    dark = U.parch_mat('b2_paper_dk', '#c9a468', '#8f6a34')
    W, Hh = 3.0, 0.85
    U.sheet('paper', W, Hh, paper, jitter=0.012, ny=6)
    for sx in (-1, 1):
        U.roll('roll', sx * (W / 2 + 0.02), Hh + 0.12, 0.085, dark)
        U.roll('roll2', sx * (W / 2 - 0.08), Hh + 0.04, 0.06, paper)
    return [], None


NEW = {
    'button': (piece_button, False, 8.0),
    'compass': (piece_compass, False, 8.0),
    'chest': (piece_chest, False, 8.0),
    'badge_bolt': (piece_badge_bolt, False, 8.0),
    'badge_knot': (piece_badge_knot, False, 8.0),
    'plaque_wood': (piece_plaque_wood, False, 0.0),
    'plaque_stone': (piece_plaque_stone, False, 0.0),
    'plaque_scroll': (piece_plaque_scroll, False, 0.0),
}
U.PIECES.update(NEW)

if __name__ == '__main__':
    U.main()
