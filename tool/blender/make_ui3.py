"""The interface pieces, modelled in more detail (user 2026-11-05: "das ist mir
sehr weit weg vom Original. Ich möchte, dass du dies alles 3D modellierst, um so
nahe wie möglich an das Original zu kommen. Die Drachenflügel braucht es nicht").

    blender --background --python tool/blender/make_ui3.py -- bar divider chest button \
        compass bell [--samples N --px N]

Replaces make_ui2's pieces with carved, studded, glowing ones and runs make_ui's
renderer. Everything is built upright (X right, Z up, face towards -Y).
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon_lib as L  # noqa: E402
import make_ui as U  # noqa: E402
import make_ui2 as U2  # noqa: E402
import pro_kit as K  # noqa: E402
import camp_kit  # noqa: E402
from icon_lib import box, ball, cyl, ring, lathe, poly, circ, starp  # noqa: E402
from pro_kit import plain  # noqa: E402

TAU = math.tau


def mats():
    P = U2.mats()
    walnut = camp_kit.mats()['timber']
    P['walnut'] = walnut
    P['walnut_dk'] = plain('b3_walnut_dk', '#3b2314', rough=0.65, bump=0.5, bump_scale=70, vary=0.1)
    P['panel'] = U.parch_mat('b3_panel', '#e8c98c', '#c79a5c', scale=2.2)
    P['panel_dk'] = plain('b3_panel_dk', '#2a1c10', rough=0.5, bump=0.1, bump_scale=60, vary=0.0)
    P['rivet'] = plain('b3_rivet', '#e6b565', rough=0.28, metal=1.0, bump=0.0, vary=0.0)
    return P


def corner_bracket(P, x, z, sx, sz, T):
    """A bronze L-shaped bracket over a frame corner, with a rivet."""
    box(x, -0.13, z, T * 1.15, 0.06, T * 1.15, P['bronze'], bev=0.03)
    box(x - sx * T * 0.36, -0.15, z, T * 0.4, 0.05, T * 1.15, P['bronze_lt'], bev=0.02)
    ball(x, -0.18, z, 0.045, 0.025, 0.045, P['rivet'], seg=12)


def piece_bar(M):
    """The header beam: a carved walnut frame, bronze corner brackets and a warm
    leather panel with a raised rim. Stretched in the middle by the game."""
    P = mats()
    W, Hh, T = 3.0, 1.0, 0.24
    box(0, 0.05, 0, W - 0.2, 0.06, Hh - 0.2, P['panel'], bev=0.02)
    # raised panel rim
    for z in (Hh / 2 - T - 0.035, -Hh / 2 + T + 0.035):
        box(0, -0.035, z, W - 2 * T - 0.04, 0.06, 0.05, P['walnut_dk'], bev=0.015)
    for sx in (-1, 1):
        box(sx * (W / 2 - T - 0.035), -0.035, 0, 0.05, 0.06, Hh - 2 * T - 0.04, P['walnut_dk'], bev=0.015)
    # the frame beams, each with a carved groove down its middle
    for z in (Hh / 2 - T / 2, -Hh / 2 + T / 2):
        box(0, 0, z, W, 0.22, T, P['walnut'], bev=0.05)
        box(0, -0.115, z, W - 0.5, 0.03, 0.035, P['walnut_dk'], bev=0.01)
    for sx in (-1, 1):
        box(sx * (W / 2 - T / 2), 0, 0, T, 0.22, Hh, P['walnut'], bev=0.05)
        box(sx * (W / 2 - T / 2), -0.115, 0, 0.035, 0.03, Hh - 0.5, P['walnut_dk'], bev=0.01)
        for sz in (-1, 1):
            corner_bracket(P, sx * (W / 2 - T / 2), sz * (Hh / 2 - T / 2), sx, sz, T)
    return [], None


def piece_divider(M):
    """A carved post between two cells: bronze bands, a stud, rounded ends."""
    P = mats()
    box(0, 0, 0, 0.30, 0.20, 1.0, P['walnut'], bev=0.05)
    box(0, -0.105, 0, 0.05, 0.03, 0.78, P['walnut_dk'], bev=0.01)
    for z in (0.40, -0.40):
        box(0, -0.12, z, 0.36, 0.07, 0.10, P['bronze'], bev=0.025)
        ball(0, -0.17, z, 0.04, 0.02, 0.04, P['rivet'], seg=10)
    ball(0, -0.13, 0, 0.055, 0.03, 0.055, P['rivet'], seg=12)
    return [], None


def halo(P, R=1.6, strength=3.0, color='#4fb8ff', y=0.12):
    """A soft glow behind a medal: an emissive disc that fades to nothing."""
    m = bpy.data.materials.new('b3_halo')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = K.hexc(color)
    em.inputs['Strength'].default_value = strength
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    mix = nt.nodes.new('ShaderNodeMixShader')
    co = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Location'].default_value = (-1.0, -1.0, 0.0)
    mp.inputs['Scale'].default_value = (2.0, 2.0, 0.0)
    nt.links.new(co.outputs['Generated'], mp.inputs['Vector'])
    ln = nt.nodes.new('ShaderNodeVectorMath')
    ln.operation = 'LENGTH'
    nt.links.new(mp.outputs['Vector'], ln.inputs[0])
    inv = nt.nodes.new('ShaderNodeMath')
    inv.operation = 'MULTIPLY_ADD'
    inv.inputs[1].default_value = -1.0
    inv.inputs[2].default_value = 1.0
    inv.use_clamp = True
    nt.links.new(ln.outputs['Value'], inv.inputs[0])
    pw = nt.nodes.new('ShaderNodeMath')
    pw.operation = 'POWER'
    pw.inputs[1].default_value = 2.2
    nt.links.new(inv.outputs[0], pw.inputs[0])
    nt.links.new(pw.outputs[0], mix.inputs['Fac'])
    nt.links.new(tr.outputs['BSDF'], mix.inputs[1])
    nt.links.new(em.outputs['Emission'], mix.inputs[2])
    nt.links.new(mix.outputs['Shader'], out.inputs['Surface'])
    bpy.ops.mesh.primitive_plane_add(size=R * 2, location=(0, y, 0), rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.object
    ob.name = 'halo'
    ob.data.materials.append(m)
    return ob


def studded_ring(P, R, ring_m, beads, bead_m='bronze_lt', t=0.13):
    prof = [(0, 0), (R, 0), (R, t), (R * 0.95, t + 0.09), (R * 0.82, t + 0.12), (R * 0.74, t + 0.04), (R * 0.68, 0.06), (0, 0.06)]
    lathe(prof, P[ring_m], rot=(90, 0, 0), sub=1)
    for i in range(beads):
        a = i * TAU / beads
        ball(R * 0.985 * math.cos(a), -t, R * 0.985 * math.sin(a), 0.05 * R, 0.04, 0.05 * R, P[bead_m], seg=12)


def piece_chest(M):
    """The header's medal: dark steel studded ring, blue light, a dark chest."""
    P = mats()
    halo(P, 1.7, 2.2)
    studded_ring(P, 1.0, 'steel_dk', 34, 'steel')
    ring(0, -0.2, 0, 1.0, 0.03, P['bronze'])
    d = lathe([(0, 0.06), (0.69, 0.06), (0.69, 0.08), (0, 0.08)], P['navy'], rot=(90, 0, 0), sub=0)
    ring(0, -0.18, 0, 0.78, 0.035, P['glow_blue'])
    ring(0, -0.21, 0, 0.66, 0.014, P['glow_cyan'])
    # the chest, a little 3/4 turned
    W, D, H = 1.30, 0.74, 0.56
    cz0 = -0.46
    rot = (0, 0, -22)
    objs = []

    def b(x, y, z, sx, sy, sz, m, bev=0.03):
        objs.append(box(x, y, z, sx, sy, sz, m, bev=bev))
    b(0, -0.5, cz0 + H / 2, W, D, H, P['dwood'])
    for x in (-0.44, 0.0, 0.44):
        b(x, -0.5 - D / 2 - 0.012, cz0 + H / 2, 0.11, 0.03, H + 0.03, P['steel'], 0.01)
        for z in (cz0 + 0.07, cz0 + H - 0.07):
            ball(x, -0.5 - D / 2 - 0.035, z, 0.025, 0.015, 0.025, P['rivet'], seg=8)
    b(0, -0.5 - D / 2 - 0.02, cz0 + H - 0.02, W + 0.03, 0.04, 0.08, P['steel_dk'], 0.012)
    bpy.ops.mesh.primitive_cylinder_add(radius=D / 2, depth=W, location=(0, -0.5, cz0 + H), vertices=40, rotation=(0, math.pi / 2, 0))
    lid = bpy.context.object
    lid.scale = (0.5, 1.0, 1.0)
    for p in lid.data.polygons:
        p.use_smooth = True
    lid.data.materials.append(P['dwood'])
    for x in (-0.44, 0.0, 0.44):
        bpy.ops.mesh.primitive_cylinder_add(radius=D / 2 + 0.012, depth=0.11, location=(x, -0.5, cz0 + H), vertices=40, rotation=(0, math.pi / 2, 0))
        bb = bpy.context.object
        bb.scale = (0.5, 1.0, 1.0)
        bb.data.materials.append(P['steel'])
    b(0, -0.5 - D / 2 - 0.045, cz0 + H - 0.04, 0.17, 0.05, 0.21, P['steel_dk'], 0.02)
    ball(0, -0.5 - D / 2 - 0.08, cz0 + H - 0.06, 0.045, 0.025, 0.055, P['glow_cyan'], seg=14)
    for sx in (-1, 1):
        for sz in (0.06, H - 0.06):
            b(sx * (W / 2 - 0.01), -0.5 - D / 2 - 0.022, cz0 + sz, 0.1, 0.03, 0.1, P['steel'], 0.01)
    return [], 3.5


def piece_button(M):
    """A round dark-metal button with a bronze outline."""
    P = mats()
    studded_ring(P, 1.0, 'steel_dk', 0, t=0.12)
    ring(0, -0.15, 0, 0.995, 0.035, P['bronze'])
    ring(0, -0.2, 0, 0.74, 0.022, P['bronze_dk'])
    for i in range(24):
        a = i * TAU / 24
        ball(0.86 * math.cos(a), -0.2, 0.86 * math.sin(a), 0.025, 0.018, 0.025, P['bronze'], seg=8)
    d = lathe([(0, 0.07), (0.7, 0.07), (0.7, 0.085), (0, 0.085)], P['dish'], rot=(90, 0, 0), sub=0)
    return [], 2.3


def piece_compass(M):
    """The bottom-left medal: bronze ring set with gems, a dark face ringed with
    marks, a silver compass rose with a blue glowing heart."""
    P = mats()
    studded_ring(P, 1.0, 'bronze', 40, 'bronze_lt', t=0.14)
    ring(0, -0.22, 0, 0.74, 0.03, P['bronze_dk'])
    lathe([(0, 0.07), (0.72, 0.07), (0.72, 0.09), (0, 0.09)], P['navy'], rot=(90, 0, 0), sub=0)
    for ang, g in ((180, 'ruby'), (90, 'sapph'), (0, 'ruby'), (270, 'sapph'), (135, 'emer'), (45, 'emer'), (225, 'emer'), (315, 'emer')):
        a = math.radians(ang)
        r = 0.87 if ang % 90 == 0 else 0.86
        x, z = r * math.cos(a), r * math.sin(a)
        s = 0.12 if ang % 90 == 0 else 0.07
        ring(x, -0.25, z, s + 0.025, 0.022, P['bronze_lt'])
        ball(x, -0.25, z, s, 0.05, s, P[g], seg=16)
    for i in range(48):
        a = i * TAU / 48
        L = 0.07 if i % 4 == 0 else 0.035
        box(0.62 * math.cos(a), -0.17, 0.62 * math.sin(a), L, 0.015, 0.018, P['silver'], rot=(0, -math.degrees(a) + 90, 0), bev=0.004)
    for ang, ro, ri, m, dz in ((90, 0.58, 0.10, 'silver', 0.0), (45, 0.40, 0.08, 'steel', 0.02)):
        n = 4
        pts = [((ro if i % 2 == 0 else ri) * math.cos(math.radians(ang) + i * math.pi / n),
                (ro if i % 2 == 0 else ri) * math.sin(math.radians(ang) + i * math.pi / n)) for i in range(2 * n)]
        poly(pts, 0.05, P[m], y=-0.15 - dz, bev=0.01)
    ring(0, -0.2, 0, 0.2, 0.03, P['bronze_lt'])
    ball(0, -0.22, 0, 0.15, 0.1, 0.15, P['glow_blue'], seg=24)
    return [], 2.3


def piece_bell(M):
    """A bronze bell hung from a dark timber beam on a bronze bracket (no wings)."""
    P = mats()
    wood = P['walnut']
    outer = [(0.0, 1.0), (0.10, 0.99), (0.17, 0.94), (0.22, 0.84), (0.26, 0.70), (0.30, 0.56),
             (0.35, 0.42), (0.42, 0.26), (0.50, 0.12), (0.58, 0.03), (0.61, 0.0), (0.61, -0.035),
             (0.58, -0.045), (0.52, 0.0), (0.44, 0.10), (0.36, 0.24), (0.30, 0.40), (0.24, 0.58),
             (0.18, 0.76), (0.12, 0.88), (0.0, 0.90)]
    lathe(outer, P['bronze_lt'], steps=80, sub=1)
    for z, r in ((0.62, 0.285), (0.34, 0.385), (0.10, 0.52)):
        ring(0, 0, z, r + 0.005, 0.016, P['bronze_dk'], axis='z', seg=72)
    ring(0, 0, 0.0, 0.60, 0.024, P['bronze_dk'], axis='z', seg=72)
    ball(0, 0, -0.07, 0.12, 0.12, 0.12, P['iron'] if 'iron' in P else P['steel_dk'], seg=24)
    ring(0, 0, 1.08, 0.10, 0.028, P['steel_dk'], axis='y', seg=28)
    box(0, 0, 1.0, 0.62, 0.10, 0.07, P['steel_dk'], bev=0.015)
    # the beam and a scrolled bronze bracket under it
    box(0.62, 0, 1.30, 2.9, 0.34, 0.26, wood, bev=0.03)
    box(1.35, 0, 1.30, 0.12, 0.40, 0.30, P['bronze'], bev=0.02)
    box(-0.55, 0, 1.30, 0.12, 0.40, 0.30, P['bronze'], bev=0.02)
    box(0.0, -0.19, 1.30, 0.16, 0.04, 0.36, P['steel_dk'], bev=0.01)
    box(1.45, -0.04, 0.78, 0.12, 0.10, 1.05, P['bronze'], bev=0.02)
    box(1.12, -0.04, 0.80, 0.12, 0.10, 0.95, P['bronze'], rot=(0, 38, 0), bev=0.02)
    ball(1.45, -0.1, 0.30, 0.07, 0.04, 0.07, P['bronze_lt'], seg=14)
    ball(1.45, -0.1, 1.12, 0.05, 0.03, 0.05, P['rivet'], seg=10)
    for x in (-0.55, 0.0, 1.35):
        ball(x, -0.22, 1.30, 0.028, 0.015, 0.028, P['rivet'], seg=10)
    return [], None


NEW = {
    'bar': (piece_bar, False, 0.0),
    'divider': (piece_divider, False, 0.0),
    'chest': (piece_chest, False, 8.0),
    'button': (piece_button, False, 8.0),
    'compass': (piece_compass, False, 8.0),
    'bell': (piece_bell, False, 6.0),
}
U.PIECES.update(NEW)

if __name__ == '__main__':
    U.main()
