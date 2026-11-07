"""The main screen in the buildings' own look (user 2026-11-05: "mache mir den
Hauptscreen ähnlich dem Look der Gebäude").

    blender --background --python tool/blender/make_ui4.py -- bar divider chest button \
        compass bell badge_bolt badge_knot [--samples N --px N]

The buildings are voxel pieces in timber, plaster, rubble stone and terracotta
tiles under a golden-hour sun. These interface pieces are built from the same
materials, voxelised on a coarse grid by the buildings' union voxeliser, and lit
and photographed the same way. Replaces make_ui3's pieces; renders through
make_ui's own runner into assets/images/ui/.
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon_lib as L  # noqa: E402
import make_ui as U  # noqa: E402
import pro_kit as K  # noqa: E402
import voxelizer  # noqa: E402
from icon_lib import box, ball, cyl, ring, lathe, poly, circ, starp, heartp  # noqa: E402

TAU = math.tau
_VOX = {'v': 0.07}


def vox(v):
    _VOX['v'] = v


def finish():
    """Voxelise everything built so far on one grid."""
    voxelizer.voxelize(_VOX['v'], 'ui_voxel')


# ── pieces ──────────────────────────────────────────────────
def piece_bar(M):
    """The header: a timber-framed wall with plaster panel, tiled eave on top."""
    vox(0.040)
    W, Hh, T = 3.0, 1.3, 0.20
    box(0, 0.06, 0, W - 0.2, 0.12, Hh - 0.2, 'plaster', bev=0.0)
    for z in (Hh / 2 - T / 2, -Hh / 2 + T / 2):
        box(0, 0, z, W, 0.26, T, 'timber', bev=0.0)
    for sx in (-1, 1):
        box(sx * (W / 2 - T / 2), 0, 0, T, 0.26, Hh, 'timber', bev=0.0)
    # a tiled eave over the top, sloping out like a roof
    box(0, -0.12, Hh / 2 + 0.17, W + 0.16, 0.5, 0.2, 'roof', rot=(-22, 0, 0), bev=0.0)
    box(0, -0.02, Hh / 2 + 0.05, W + 0.04, 0.3, 0.07, 'timber', bev=0.0)
    finish()
    return [], None


def piece_divider(M):
    vox(0.040)
    box(0, 0, 0, 0.30, 0.26, 1.0, 'timber', bev=0.0)
    box(0, -0.14, 0.34, 0.12, 0.06, 0.12, 'mustard', bev=0.0)
    box(0, -0.14, -0.34, 0.12, 0.06, 0.12, 'mustard', bev=0.0)
    finish()
    return [], None


# User 2026-11-05: the main screen's round boards are now drawn in Flutter (timber
# grain), so the *_bare pieces below are the voxel glyphs ALONE: no ring, no dish.
BARE = False


def medal_ring(R, inner, ring_m='timber', dish_m='planks', studs=0, t=0.2):
    """A round medal: a thick rubble ring and a recessed dish."""
    if BARE:
        return
    prof = [(0, 0), (R, 0), (R, t), (R * 0.9, t + 0.06), (R * inner, t + 0.04), (R * inner * 0.92, 0.06), (0, 0.06)]
    lathe(prof, ring_m, rot=(90, 0, 0), sub=0, steps=36)
    lathe([(0, 0.05), (R * inner, 0.05), (R * inner, 0.15), (0, 0.15)], dish_m, rot=(90, 0, 0), sub=0, steps=36)
    for i in range(studs):
        a = i * TAU / studs
        ball(R * 0.86 * math.cos(a), -t - 0.02, R * 0.86 * math.sin(a), 0.07, 0.05, 0.07, 'gold', seg=8)


def piece_button(M):
    vox(0.034)
    medal_ring(1.0, 0.72, 'timber', 'plaster', studs=8)
    finish()
    return [], 2.3


def piece_compass(M):
    """Timber medal with coloured gems, a plaster face, a red-and-timber rose and
    the globe in the middle."""
    vox(0.034)
    medal_ring(1.0, 0.74, 'timber', 'plaster', studs=12, t=0.22)
    # the rose stands IN FRONT of the ring and its tips reach past the wooden rim
    # (user 2026-11-05: "der Kompass soll über die Ränder hinausschauen")
    if BARE:
        # User 2026-11-05 ("1"): the rose of mock-up 1. Four red spikes only (no
        # gold diagonals) that rise from behind the timber board, a wide gold ring
        # round the globe, and a gold "N" plate on the north spike. The board is
        # drawn in Flutter at radius ~1.15 units here, so the spikes start at 1.0.
        tip, base, hw = 1.67, 1.0, 0.34
        for ang in (0, 90, 180, 270):
            a = math.radians(ang)
            ux, uy = math.cos(a), math.sin(a)
            px_, py_ = -uy, ux
            pts = [(ux * base + px_ * hw, uy * base + py_ * hw), (ux * tip, uy * tip),
                   (ux * base - px_ * hw, uy * base - py_ * hw), (ux * (base - 0.2), uy * (base - 0.2))]
            poly(pts, 0.08, 'red', y=-0.34, bev=0.0)
        ring(0, -0.42, 0, 0.98, 0.09, 'gold')
        # the N plate straddling the board's top rim
        pz = 1.22
        box(0, -0.46, pz, 0.52, 0.07, 0.46, 'gold', bev=0.0)
        for sx in (-1, 1):
            box(sx * 0.12, -0.52, pz, 0.07, 0.05, 0.28, 'timber', bev=0.0)
        box(0, -0.52, pz, 0.06, 0.05, 0.40, 'timber', rot=(0, -35, 0), bev=0.0)
    else:
        for ang, ro, ri, m, y in ((90, 1.22, 0.30, 'red', -0.34), (45, 0.95, 0.24, 'mustard', -0.30)):
            n = 4
            pts = [((ro if i % 2 == 0 else ri) * math.cos(math.radians(ang) + i * math.pi / n),
                    (ro if i % 2 == 0 else ri) * math.sin(math.radians(ang) + i * math.pi / n)) for i in range(2 * n)]
            poly(pts, 0.08, m, y=y, bev=0.0)
        ring(0, -0.40, 0, 0.45, 0.06, 'gold')
    finish()
    return [], 3.6 if BARE else 2.95


def turn_z(objs, deg, pivot):
    """Swing finished objects about the vertical axis through `pivot`."""
    import mathutils
    bpy.context.view_layer.update()
    pv = mathutils.Vector(pivot)
    rz = (mathutils.Matrix.Translation(pv) @ mathutils.Matrix.Rotation(math.radians(deg), 4, 'Z')
          @ mathutils.Matrix.Translation(-pv))
    for o in objs:
        o.matrix_world = rz @ o.matrix_world
    bpy.context.view_layer.update()


def piece_chest(M):
    """The header's centre: a timber medal with a warm ring, and a timber chest
    with iron bands, a tiled round lid and a lock that glows like a window."""
    # User 2026-11-05: chest higher, turned ~30 deg so its side shows, gold trim.
    vox(0.026)
    medal_ring(1.0, 0.76, 'timber', 'plaster', studs=12, t=0.22)
    # Mock-up 1 (user 2026-11-05): a gold ring round the chest after all, on the
    # bare piece only (the dark dish inside it is drawn in Flutter).
    if BARE:
        ring(0, -0.30, 0, 0.84, 0.08, 'gold')
    before = L.snapshot()
    W, D, H = 1.02, 0.62, 0.42
    cy, cz0 = -0.5, -0.16
    fy = cy - D / 2
    box(0, cy, cz0 + H / 2, W, D, H, 'planks', bev=0.0)

    def lid_part(x, depth, extra, mat):
        bpy.ops.mesh.primitive_cylinder_add(radius=D / 2 + extra, depth=depth, location=(x, cy, cz0 + H), vertices=24, rotation=(0, math.pi / 2, 0))
        o = bpy.context.object
        o.scale = (0.5, 1.0, 1.0)
        o.data.materials.append(L._m(mat))
    lid_part(0, W, 0, 'planks')
    for x in (-0.30, 0.0, 0.30):  # gold bands over body and lid
        box(x, fy - 0.015, cz0 + H / 2, 0.075, 0.03, H + 0.01, 'gold', bev=0.0)
        lid_part(x, 0.075, 0.02, 'gold')
    box(0, cy, cz0 + H - 0.02, W + 0.04, D + 0.04, 0.05, 'gold', bev=0.0)  # seam rim
    for sx in (-1, 1):  # corner brackets
        for sy in (-1, 1):
            box(sx * (W / 2 - 0.02), cy + sy * (D / 2 - 0.02), cz0 + H / 2, 0.06, 0.06, H + 0.03, 'gold', bev=0.0)
            box(sx * (W / 2 - 0.02), cy + sy * (D / 2 - 0.02), cz0 + 0.02, 0.09, 0.09, 0.04, 'gold', bev=0.0)
    for x in (-0.15, 0.15):  # studs
        for z in (cz0 + 0.09, cz0 + H - 0.1):
            ball(x, fy - 0.04, z, 0.03, 0.02, 0.03, 'gold', seg=8)
    box(0, fy - 0.04, cz0 + H - 0.03, 0.16, 0.05, 0.19, 'gold', bev=0.0)  # lock plate
    box(0, fy - 0.07, cz0 + H - 0.04, 0.05, 0.03, 0.09, 'pane_glow', bev=0.0)
    turn_z(L.new_since(before), -30, (0, cy, cz0))
    # User 2026-11-05: the chest alone a bit larger, so it reaches over the timber ring.
    import mathutils
    pv = mathutils.Vector((0, cy, cz0 + H / 2))
    S = 1.2
    sc = (mathutils.Matrix.Translation(pv) @ mathutils.Matrix.Scale(S, 4) @ mathutils.Matrix.Translation(-pv))
    for o in L.new_since(before):
        o.matrix_world = sc @ o.matrix_world
    bpy.context.view_layer.update()
    finish()
    return [], 2.5


def piece_badge_bolt(M):
    vox(0.034)
    medal_ring(1.0, 0.74, 'timber', 'planks', studs=0, t=0.2)
    pts = [(0.14, 0.7), (-0.36, -0.04), (-0.03, -0.04), (-0.16, -0.7), (0.38, 0.12), (0.04, 0.12)]
    poly(pts, 0.1, 'pane_glow', y=-0.16, bev=0.0)
    finish()
    return [], 2.3


def piece_badge_knot(M):
    vox(0.034)
    medal_ring(1.0, 0.74, 'timber', 'planks', studs=0, t=0.2)
    for k in range(3):
        a = k * 120
        ring(0.15 * math.cos(math.radians(a + 90)), -0.17 - k * 0.01, 0.15 * math.sin(math.radians(a + 90)), 0.32, 0.07, 'mustard')
    finish()
    return [], 2.3


def piece_bell(M):
    # no struts: the screen's own edge is the post the beam hangs from (user 2026-11-05)
    """A bell of brass under a timber beam, braced with a timber strut."""
    # User 2026-11-05: smaller, and hung from the header beam itself (not from the
    # side edge): no long beam any more, just a timber mounting block at the top
    # that sits against the header's underside, an iron strap and the bell.
    # User 2026-11-05 (2): the sign hangs on TWO CHAINS from the header; a timber
    # beam at their lower ends carries the bell, which is smaller again.
    vox(0.03)
    s = 0.62
    outer = [(0.0, 1.0), (0.10, 0.99), (0.17, 0.94), (0.22, 0.84), (0.26, 0.70), (0.30, 0.56),
             (0.35, 0.42), (0.42, 0.26), (0.50, 0.12), (0.58, 0.03), (0.61, 0.0), (0.61, -0.035),
             (0.58, -0.045), (0.52, 0.0), (0.44, 0.10), (0.36, 0.24), (0.30, 0.40), (0.24, 0.58),
             (0.18, 0.76), (0.12, 0.88), (0.0, 0.90)]
    lathe([(x * s, z * s) for x, z in outer], 'gold', steps=28, sub=0)
    ball(0, 0, -0.07 * s, 0.12 * s, 0.12 * s, 0.12 * s, 'iron_dk', seg=10)
    top = s * 1.0
    box(0.0, 0, top + 0.07, 0.08, 0.08, 0.18, 'iron_dk', bev=0.0)   # strap up to the beam
    beam_z = top + 0.22
    box(0.0, 0, beam_z, 1.05, 0.26, 0.16, 'timber', bev=0.0)         # the beam
    box(0.0, -0.14, beam_z + 0.03, 1.05, 0.03, 0.04, 'mustard', bev=0.0)
    # two chains from the beam's ends up to the header (alternating face-on / edge-on links)
    chain_top = beam_z + 0.62
    for cx in (-0.42, 0.42):
        z = beam_z + 0.08
        k = 0
        while z < chain_top:
            if k % 2 == 0:
                box(cx, 0, z + 0.07, 0.11, 0.035, 0.17, 'iron_dk', bev=0.0)
            else:
                box(cx, 0, z + 0.07, 0.035, 0.11, 0.17, 'iron_dk', bev=0.0)
            z += 0.11
            k += 1
    finish()
    return [], None


# ── the quick-button glyphs, in the buildings' voxel look ─────
# (user 2026-11-05: "ersetze alle Icons auf dem Titelscreen mit der neuen
# Methode"; Profile and Social are new designs: a heraldic shield and speech bubbles
# instead of the old blob figures.)  Camera sits at -y, z is up.
def turn_y(objs, deg, pivot=(0, 0, 0)):
    """Swing objects about the view axis (a tilt in the picture plane)."""
    import mathutils
    bpy.context.view_layer.update()
    pv = mathutils.Vector(pivot)
    r = (mathutils.Matrix.Translation(pv) @ mathutils.Matrix.Rotation(math.radians(deg), 4, 'Y')
         @ mathutils.Matrix.Translation(-pv))
    for o in objs:
        o.matrix_world = r @ o.matrix_world
    bpy.context.view_layer.update()


def piece_icon_hammer(M):
    vox(0.030)
    before = L.snapshot()
    box(0, 0, -0.15, 0.17, 0.17, 1.6, 'timber', bev=0.0)
    box(0, 0, -0.9, 0.22, 0.22, 0.12, 'gold', bev=0.0)
    box(0, 0, 0.58, 1.0, 0.42, 0.40, 'iron', bev=0.0)
    box(0.55, 0, 0.58, 0.16, 0.46, 0.48, 'iron_dk', bev=0.0)
    box(-0.55, 0, 0.58, 0.20, 0.34, 0.30, 'iron_dk', bev=0.0)
    box(0, 0, 0.58, 0.14, 0.46, 0.46, 'gold', bev=0.0)
    turn_y(L.new_since(before), 35)
    finish()
    return [], 2.2


def piece_icon_paw(M):
    vox(0.030)
    ball(0, 0, -0.28, 0.54, 0.24, 0.42, 'mustard', seg=20)
    for x, z, r, a in ((-0.68, 0.22, 0.17, -25), (-0.26, 0.62, 0.19, -8), (0.26, 0.62, 0.19, 8), (0.68, 0.22, 0.17, 25)):
        ball(x, 0, z, r, 0.17, r * 1.35, 'mustard', seg=14, rot=(0, a, 0))
    ball(0, -0.2, -0.3, 0.30, 0.05, 0.22, 'gold', seg=14)
    finish()
    return [], 2.2


def piece_icon_map(M):
    vox(0.020)
    # A map unfolded a little: three leaves with a fold between each (every
    # leaf swung about the vertical, alternately), the whole sheet turned and
    # tilted a few degrees (user 2026-11-05: "schräg, mit leichtem Knick").
    before = L.snapshot()
    for x, a in ((-0.58, 24), (0.0, -24), (0.58, 24)):
        box(x, 0, 0, 0.66, 0.08, 1.35, 'linen', rot=(0, 0, a), bev=0.0)
        # (a leaf is drawn on its own face by the pieces below)
    box(-0.56, -0.07, 0.38, 0.34, 0.03, 0.28, 'teal', rot=(0, 0, 24), bev=0.0)
    box(0.0, -0.07, -0.22, 0.30, 0.03, 0.30, 'green', rot=(0, 0, -24), bev=0.0)
    for x, z in ((-0.56, -0.36), (-0.40, -0.16), (-0.18, 0.0), (0.04, 0.2), (0.2, 0.3)):
        box(x, -0.09, z, 0.08, 0.03, 0.08, 'iron_dk', bev=0.0)
    for a in (45, -45):
        box(0.58, -0.09, 0.3, 0.30, 0.03, 0.09, 'red', rot=(0, a, 24), bev=0.0)
    turn_z(L.new_since(before), 14, (0, 0, 0))
    turn_y(L.new_since(before), 12)
    finish()
    return [], 2.2


def piece_icon_bag(M):
    vox(0.030)
    box(0, 0, -0.1, 1.1, 0.62, 1.1, 'leather', bev=0.0)
    box(0, -0.06, 0.40, 1.14, 0.66, 0.46, 'leather_dk', bev=0.0)
    box(0, -0.34, -0.42, 0.8, 0.14, 0.38, 'leather_dk', bev=0.0)
    for x in (-0.34, 0.34):
        box(x, -0.36, 0.30, 0.12, 0.05, 0.78, 'leather_dk', bev=0.0)
    box(0, -0.40, 0.14, 0.22, 0.05, 0.18, 'gold', bev=0.0)
    ring(0, 0, 0.78, 0.24, 0.05, 'leather_dk')
    finish()
    return [], 2.2


def piece_icon_tasks(M):
    vox(0.030)
    box(0, 0.04, 0, 1.25, 0.10, 1.6, 'planks', bev=0.0)
    box(0, -0.03, -0.02, 1.02, 0.04, 1.36, 'linen', bev=0.0)
    box(0, -0.08, 0.78, 0.5, 0.09, 0.18, 'gold', bev=0.0)
    for z in (0.38, 0.0, -0.38):
        box(0.14, -0.06, z, 0.5, 0.03, 0.07, 'iron_dk', bev=0.0)
        box(-0.38, -0.06, z - 0.03, 0.10, 0.03, 0.06, 'green', rot=(0, -40, 0), bev=0.0)
        box(-0.28, -0.06, z + 0.03, 0.22, 0.03, 0.06, 'green', rot=(0, 50, 0), bev=0.0)
    finish()
    return [], 2.2


def piece_icon_person(M):
    """PROFILE: a heraldic shield, gold-rimmed, with a bust in its blue field."""
    vox(0.030)
    out = [(-0.66, 0.78), (0.66, 0.78), (0.66, 0.05), (0.48, -0.5), (0, -0.92), (-0.48, -0.5), (-0.66, 0.05)]
    inn = [(x * 0.82, z * 0.82 - 0.02) for x, z in out]
    poly(out, 0.16, 'gold', y=0.0, bev=0.0)
    poly(inn, 0.12, 'blue_dk', y=-0.06, bev=0.0)
    ball(0, -0.14, 0.34, 0.17, 0.12, 0.19, 'cream', seg=14)
    ball(0, -0.14, -0.22, 0.50, 0.10, 0.30, 'cream', seg=14)
    box(0, -0.2, -0.46, 0.7, 0.12, 0.16, 'blue_dk', bev=0.0)  # hides the shoulders' lower half
    for sx in (-1, 1):
        box(sx * 0.5, -0.15, 0.60, 0.1, 0.08, 0.1, 'gold', bev=0.0)
    finish()
    return [], 2.2


def piece_icon_people(M):
    """SOCIAL: two speech bubbles, one plaster with three dots, one gold with a heart."""
    vox(0.030)
    # back bubble (gold, up right) with a red heart
    ball(0.28, 0.1, 0.30, 0.62, 0.10, 0.46, 'mustard', seg=24)
    box(0.52, 0.1, -0.1, 0.22, 0.10, 0.22, 'mustard', rot=(0, 45, 0), bev=0.0)
    poly(heartp(0.34, 0.28, 0.32), 0.06, 'red', y=0.0, bev=0.0)
    # front bubble (plaster, down left) with three dots
    ball(-0.22, -0.12, -0.18, 0.66, 0.10, 0.46, 'plaster', seg=24)
    box(-0.5, -0.12, -0.6, 0.22, 0.10, 0.22, 'plaster', rot=(0, 45, 0), bev=0.0)
    for x in (-0.5, -0.22, 0.06):
        ball(x, -0.24, -0.18, 0.09, 0.05, 0.09, 'iron_dk', seg=8)
    finish()
    return [], 2.2


GLOBE_FRAMES = 48
def globe_mat_rot(deg):
    """make_ui's globe material with its Object-space noise turned about the
    vertical axis: the voxeliser makes a fresh unrotated object, so spinning the
    ball itself would change nothing."""
    m = U.globe_mat()
    nt = m.node_tree
    n1 = next(n for n in nt.nodes if n.bl_idname == 'ShaderNodeTexNoise')
    co = next(n for n in nt.nodes if n.bl_idname == 'ShaderNodeTexCoord')
    # The axis leans 23 degrees to the right in the picture (user 2026-11-05: "die
    # Erde soll etwas schräg stehen"): look the texture up through the inverse
    # tilt first, then through the spin about the (now tilted) vertical.
    tl = nt.nodes.new('ShaderNodeMapping')
    tl.inputs['Rotation'].default_value = (0, -math.radians(23), 0)
    nt.links.new(co.outputs['Object'], tl.inputs['Vector'])
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Rotation'].default_value = (0, 0, math.radians(deg))
    nt.links.new(tl.outputs['Vector'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], n1.inputs['Vector'])
    return m




def piece_globe(deg):
    """One frame of the spinning globe in the compass (the sphere alone; the gold
    ring stays in compass.webp). Window 0.9 units."""
    vox(0.026)
    ball(0, -0.44, 0, 0.38, 0.38, 0.38, globe_mat_rot(deg), seg=24)
    finish()
    return [], 0.9


def _bare(fn):
    def run(M):
        global BARE
        BARE = True
        try:
            return fn(M)
        finally:
            BARE = False
    return run


NEW = {
    'chest_bare': (_bare(piece_chest), False, 12.0),
    'compass_bare': (_bare(piece_compass), False, 12.0),
    'badge_bolt_bare': (_bare(piece_badge_bolt), False, 12.0),
    'badge_knot_bare': (_bare(piece_badge_knot), False, 12.0),
    'icon_hammer': (piece_icon_hammer, False, 8.0),
    'icon_paw': (piece_icon_paw, False, 8.0),
    'icon_map': (piece_icon_map, False, 8.0),
    'icon_bag': (piece_icon_bag, False, 8.0),
    'icon_tasks': (piece_icon_tasks, False, 8.0),
    'icon_person': (piece_icon_person, False, 8.0),
    'icon_people': (piece_icon_people, False, 8.0),
    'bar': (piece_bar, False, 14.0),
    'divider': (piece_divider, False, 10.0),
    'chest': (piece_chest, False, 12.0),
    'button': (piece_button, False, 12.0),
    'compass': (piece_compass, False, 12.0),
    'bell': (piece_bell, False, 8.0),
    'badge_bolt': (piece_badge_bolt, False, 12.0),
    'badge_knot': (piece_badge_knot, False, 12.0),
}
for _i in range(GLOBE_FRAMES):
    NEW['globe_%d' % _i] = ((lambda M, d=_i * 360.0 / GLOBE_FRAMES: piece_globe(d)), False, 12.0)
U.PIECES.update(NEW)

if __name__ == '__main__':
    U.main()
