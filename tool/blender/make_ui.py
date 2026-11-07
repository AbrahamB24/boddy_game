"""The main screen's UI pieces, rendered in Blender (smooth, not voxel).

    blender --background --python tool/blender/make_ui.py -- bell button compass \
        [--samples 128] [--px 512]

User 2026-11-04, showing a painted concept of the whole interface ("schaffst du
es, genau dieses Interface 1:1 nachzubauen"): brass bell on a timber beam, round
iron buttons, a compass-and-globe button, a stone frame, parchment. The parts a
vector painter cannot do are drawn here, once, as pictures.

Every piece is built facing -Y and photographed head-on by an orthographic
camera, golden-hour key light from the upper left like the buildings. Writes
docs/renders/ui/<piece>.png (archive) and assets/images/ui/<piece>.webp.
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import camp_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
from pro_kit import plain  # noqa: E402

TAU = math.tau


# ── materials ───────────────────────────────────────────────
def ui_mats(M):
    M['brass'] = plain('brass', '#d9a441', rough=0.30, metal=1.0, bump=0.06, bump_scale=90, vary=0.04)
    M['brass_dk'] = plain('brass_dk', '#8f6420', rough=0.38, metal=1.0, bump=0.1, bump_scale=70, vary=0.06)
    M['gunmetal'] = plain('gunmetal', '#4a4e55', rough=0.42, metal=1.0, bump=0.35, bump_scale=45, vary=0.05)
    M['gunmetal_dk'] = plain('gunmetal_dk', '#25282d', rough=0.5, metal=1.0, bump=0.3, bump_scale=40, vary=0.05)
    M['dish'] = plain('dish', '#1a1c20', rough=0.28, metal=0.4, bump=0.05, bump_scale=80, vary=0.0)
    M['steel'] = plain('steel', '#aeb4bb', rough=0.28, metal=1.0, bump=0.04, bump_scale=90, vary=0.03)
    M['leather'] = plain('leather', '#5a3a22', rough=0.8, bump=0.4, bump_scale=70)
    return M


def globe_mat():
    m = bpy.data.materials.new('globe')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.25
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    co = nt.nodes.new('ShaderNodeTexCoord')
    n1 = nt.nodes.new('ShaderNodeTexNoise')
    n1.inputs['Scale'].default_value = 2.6
    n1.inputs['Detail'].default_value = 6.0
    n1.inputs['Roughness'].default_value = 0.55
    nt.links.new(co.outputs['Object'], n1.inputs['Vector'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    e = rp.color_ramp.elements
    e[0].position = 0.46
    e[0].color = K.hexc('1f6fb4')
    e[1].position = 0.50
    e[1].color = K.hexc('5fa63a')
    mid = e.new(0.62)
    mid.color = K.hexc('3f7a28')
    hi = e.new(0.74)
    hi.color = K.hexc('d8d2b8')
    nt.links.new(n1.outputs['Fac'], rp.inputs['Fac'])
    nt.links.new(rp.outputs['Color'], bsdf.inputs['Base Color'])
    return m


# ── geometry ────────────────────────────────────────────────
def link(ob, mat=None, smooth=True, subsurf=0, bevel=0.0):
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    if mat is not None:
        ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    if bevel:
        m = ob.modifiers.new('bevel', 'BEVEL')
        m.width = bevel
        m.segments = 3
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(30)
    if subsurf:
        s = ob.modifiers.new('sub', 'SUBSURF')
        s.levels = subsurf
        s.render_levels = subsurf
    return ob


def spin(name, profile, mat, steps=72, subsurf=0):
    """Revolve a (radius, height) polyline round the Z axis."""
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    for a, b in zip(vs, vs[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:], cent=(0, 0, 0), axis=(0, 0, 1),
                   angle=TAU, steps=steps, use_merge=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me), mat, subsurf=subsurf)


def torus(name, major, minor, mat, loc=(0, 0, 0), rot=(0, 0, 0), seg=64):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=seg, minor_segments=14, location=loc,
                                     rotation=rot)
    ob = bpy.context.object
    ob.name = name
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    return ob


def sphere(name, r, mat, loc=(0, 0, 0), scale=(1, 1, 1), seg=48):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    return ob


def block(name, loc, size, mat, rot=(0, 0, 0), bevel=0.01):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    m = ob.modifiers.new('bevel', 'BEVEL')
    m.width = bevel
    m.segments = 3
    return ob


def face_camera(objs):
    """Build was done with the Z axis as 'up out of the face'; a face-on picture
    wants that axis pointing at the camera (-Y)."""
    for o in objs:
        o.rotation_euler = (math.radians(90), 0, 0) if o.rotation_euler == Euler((0, 0, 0)) else o.rotation_euler


def star_plate(name, n, r_out, r_in, z0, z1, mat, rot=0.0):
    bm = bmesh.new()
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / n
        pts.append((r * math.cos(a), r * math.sin(a)))
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(bot[::-1])
    bm.faces.new(top)
    k = len(pts)
    for i in range(k):
        bm.faces.new((bot[i], bot[(i + 1) % k], top[(i + 1) % k], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me), mat, smooth=False, bevel=0.012)


# ── the pieces ──────────────────────────────────────────────
def piece_button(M):
    """A round iron button: toothed gunmetal rim, brass bezel, dark dish."""
    parts = []
    ring = [(0, 0), (1.0, 0), (1.0, 0.10), (0.95, 0.17), (0.84, 0.19), (0.77, 0.14), (0.72, 0.07), (0, 0.07)]
    parts.append(spin('ring', ring, M['gunmetal'], subsurf=1))
    d = spin('dish', [(0, 0.075), (0.70, 0.075), (0.70, 0.085), (0, 0.085)], M['dish'])
    for p in d.data.polygons:
        p.use_smooth = False
    parts.append(d)
    parts.append(torus('bezel', 0.745, 0.026, M['brass'], loc=(0, 0, 0.115)))
    for i in range(28):
        a = i * TAU / 28
        parts.append(block('tooth', (1.0 * math.cos(a), 1.0 * math.sin(a), 0.06),
                           (0.07, 0.05, 0.12), M['gunmetal_dk'], rot=(0, 0, a), bevel=0.012))
    for i in range(10):
        a = i * TAU / 10 + 0.31
        parts.append(sphere('rivet', 0.045, M['steel'], loc=(0.90 * math.cos(a), 0.90 * math.sin(a), 0.19), scale=(1, 1, 0.7), seg=20))
    return parts, 2.25


def piece_compass(M):
    """A compass rose on a stone ring with a globe in the middle."""
    parts = []
    parts.append(spin('base', [(0, 0), (1.0, 0), (1.0, 0.09), (0.93, 0.14), (0.62, 0.14), (0, 0.14)], M['gunmetal_dk'], subsurf=1))
    parts.append(torus('rim', 0.965, 0.035, M['gunmetal'], loc=(0, 0, 0.12)))
    parts.append(torus('inner', 0.60, 0.03, M['brass'], loc=(0, 0, 0.16)))
    for i in range(48):
        a = i * TAU / 48
        L = 0.07 if i % 6 == 0 else 0.04
        parts.append(block('tick', (0.80 * math.cos(a), 0.80 * math.sin(a), 0.15), (L, 0.016, 0.02),
                           M['brass'], rot=(0, 0, a + math.pi / 2), bevel=0.004))
    parts.append(star_plate('star8', 4, 1.0, 0.18, 0.14, 0.19, M['steel'], rot=math.pi / 2))
    parts.append(star_plate('star4', 4, 0.74, 0.17, 0.19, 0.23, M['brass'], rot=math.pi / 4))
    parts.append(torus('globe_ring', 0.46, 0.04, M['brass'], loc=(0, 0, 0.26)))
    parts.append(sphere('globe', 0.40, globe_mat(), loc=(0, 0, 0.42), seg=64))
    parts.append(torus('globe_ring2', 0.42, 0.018, M['brass_dk'], loc=(0, 0, 0.42), rot=(math.radians(72), 0, math.radians(25))))
    return parts, 2.25


def piece_bell(M):
    """A brass bell hanging from a timber beam, braced to the right (the beam
    runs out of the screen's right edge)."""
    wood = camp_kit.mats()['timber']
    parts = []
    # the bell, revolved about its own vertical axis; hung with its crown up
    outer = [(0.0, 1.0), (0.10, 0.99), (0.17, 0.94), (0.22, 0.84), (0.26, 0.70), (0.30, 0.56),
             (0.35, 0.42), (0.42, 0.26), (0.50, 0.12), (0.58, 0.03), (0.61, 0.0), (0.61, -0.035),
             (0.58, -0.045), (0.52, 0.0), (0.44, 0.10), (0.36, 0.24), (0.30, 0.40), (0.24, 0.58),
             (0.18, 0.76), (0.12, 0.88), (0.0, 0.90)]
    # revolve about Z as built (Z is up here — no turn to the camera)
    b = spin('bell', outer, M['brass'], steps=80, subsurf=1)
    parts.append(b)
    for z, r in ((0.62, 0.285), (0.34, 0.385), (0.10, 0.52)):
        parts.append(torus('band', r + 0.005, 0.016, M['brass_dk'], loc=(0, 0, z), seg=72))
    parts.append(torus('lip', 0.60, 0.022, M['brass_dk'], loc=(0, 0, 0.0), seg=72))
    parts.append(sphere('clapper', 0.12, M['gunmetal'], loc=(0, 0, -0.07), seg=24))
    parts.append(torus('crown_ring', 0.10, 0.028, M['gunmetal'], loc=(0, 0, 1.08), rot=(math.radians(90), 0, 0), seg=28))
    parts.append(block('yoke', (0, 0, 1.0), (0.62, 0.10, 0.07), M['gunmetal_dk'], bevel=0.015))
    # beam and brace
    parts.append(block('beam', (0.62, 0, 1.30), (2.9, 0.34, 0.24), wood, bevel=0.025))
    parts.append(block('brace', (1.425, 0, 0.76), (1.5, 0.2, 0.17), wood, rot=(0, math.radians(40), 0), bevel=0.02))
    parts.append(block('strap', (0.0, -0.18, 1.30), (0.16, 0.04, 0.34), M['gunmetal_dk'], bevel=0.008))
    for x in (-0.55, 1.4):
        parts.append(block('strap2', (x, -0.18, 1.30), (0.12, 0.04, 0.30), M['gunmetal_dk'], bevel=0.008))
    for x in (-0.55, 0.0, 1.4):
        parts.append(sphere('nail', 0.028, M['steel'], loc=(x, -0.21, 1.30), seg=14))
    return parts, None


def parch_mat(name='parch', base='#e6d2a2', dark='#b98f54', scale=3.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.85
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    co = nt.nodes.new('ShaderNodeTexCoord')
    n1 = nt.nodes.new('ShaderNodeTexNoise')
    n1.inputs['Scale'].default_value = scale
    n1.inputs['Detail'].default_value = 8.0
    n1.inputs['Roughness'].default_value = 0.6
    nt.links.new(co.outputs['Object'], n1.inputs['Vector'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    rp.color_ramp.elements[0].position = 0.30
    rp.color_ramp.elements[0].color = K.hexc(dark)
    rp.color_ramp.elements[1].position = 0.66
    rp.color_ramp.elements[1].color = K.hexc(base)
    nt.links.new(n1.outputs['Fac'], rp.inputs['Fac'])
    # scorched, darker edges: distance from the middle of the sheet's own box
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(co.outputs['Generated'], sep.inputs[0])

    def edge(axis):
        sub = nt.nodes.new('ShaderNodeMath')
        sub.operation = 'SUBTRACT'
        sub.inputs[1].default_value = 0.5
        nt.links.new(sep.outputs[axis], sub.inputs[0])
        ab = nt.nodes.new('ShaderNodeMath')
        ab.operation = 'ABSOLUTE'
        nt.links.new(sub.outputs[0], ab.inputs[0])
        return ab
    mx = nt.nodes.new('ShaderNodeMath')
    mx.operation = 'MAXIMUM'
    nt.links.new(edge('X').outputs[0], mx.inputs[0])
    nt.links.new(edge('Z').outputs[0], mx.inputs[1])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = 0.40
    mr.inputs['From Max'].default_value = 0.50
    nt.links.new(mx.outputs[0], mr.inputs['Value'])
    wob = nt.nodes.new('ShaderNodeMath')
    wob.operation = 'MULTIPLY'
    nt.links.new(mr.outputs['Result'], wob.inputs[0])
    nt.links.new(n1.outputs['Fac'], wob.inputs[1])
    wob2 = nt.nodes.new('ShaderNodeMath')
    wob2.operation = 'MULTIPLY'
    wob2.inputs[1].default_value = 1.8
    nt.links.new(wob.outputs[0], wob2.inputs[0])
    burn = nt.nodes.new('ShaderNodeMix')
    burn.data_type = 'RGBA'
    burn.clamp_factor = True
    nt.links.new(wob2.outputs[0], burn.inputs[0])
    nt.links.new(rp.outputs['Color'], burn.inputs[6])
    burn.inputs[7].default_value = K.hexc('5a3718')
    nt.links.new(burn.outputs[2], bsdf.inputs['Base Color'])
    n2 = nt.nodes.new('ShaderNodeTexNoise')
    n2.inputs['Scale'].default_value = 90.0
    n2.inputs['Detail'].default_value = 3.0
    nt.links.new(co.outputs['Object'], n2.inputs['Vector'])
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = 0.25
    bp.inputs['Distance'].default_value = 0.005
    nt.links.new(n2.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def sheet(name, w, h, mat, jitter=0.012, nx=None, ny=8, z=0.0, seed=1):
    """A ragged sheet of paper: a grid whose edge vertices wander."""
    import random
    random.seed(seed)
    nx = nx or max(8, int(w / 0.04))
    bm = bmesh.new()
    rows = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            x = -w / 2 + w * i / nx
            y = -h / 2 + h * j / ny
            edge = (j in (0, ny)) or (i in (0, nx))
            dx = random.uniform(-jitter, jitter) * (1 if edge else 0.2)
            dy = random.uniform(-jitter, jitter) * (1 if edge else 0.2)
            row.append(bm.verts.new((x + dx, z + random.uniform(-0.004, 0.004), y + dy)))
        rows.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me), mat)
    sol = ob.modifiers.new('solid', 'SOLIDIFY')
    sol.thickness = 0.012
    return ob


def roll(name, x, depth, r, mat):
    """A paper roll standing upright at x (axis along Z)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=(x, 0, 0), vertices=40)
    ob = bpy.context.object
    ob.name = name
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    return ob


def piece_parchment(M):
    """The header band: a long parchment with a roll at each end."""
    W, Hh = 6.0, 0.40
    paper = parch_mat()
    dark = parch_mat('parch_dk', '#c9a468', '#8f6a34')
    parts = [sheet('paper', W, Hh, paper, jitter=0.014, ny=6)]
    for sx in (-1, 1):
        parts.append(roll('roll', sx * (W / 2 + 0.02), Hh + 0.06, 0.075, dark))
        parts.append(roll('roll2', sx * (W / 2 - 0.07), Hh + 0.02, 0.05, paper))
    return parts, None


def piece_scroll(M):
    """The production pop-up: a short parchment, rolled at both ends, with two
    leather straps round the rolls."""
    W, Hh = 2.2, 1.35
    paper = parch_mat()
    dark = parch_mat('parch_dk', '#c9a468', '#8f6a34')
    parts = [sheet('paper', W, Hh, paper, jitter=0.012, ny=14)]
    for sx in (-1, 1):
        parts.append(roll('roll', sx * (W / 2 + 0.02), Hh + 0.12, 0.10, dark))
        parts.append(roll('roll2', sx * (W / 2 - 0.10), Hh + 0.04, 0.07, paper))
        for z in (Hh * 0.22, -Hh * 0.22):
            parts.append(block('strap', (sx * (W / 2 + 0.02), 0.0, z), (0.24, 0.24, 0.10), M['leather'], bevel=0.02))
            parts.append(sphere('buckle', 0.022, M['brass'], loc=(sx * (W / 2 + 0.02), -0.13, z), seg=12))
    return parts, None


def piece_frame(M):
    """The screen's stone frame: irregular blocks round an empty middle."""
    import random
    random.seed(7)
    W, Hh, T = 4.6, 2.2, 0.26
    # dark, rough rock like the painted concept's frame
    stone = plain('frame_stone', '#4b4741', rough=0.92, bump=0.9, bump_scale=22, vary=0.22, speck='#6c675d')
    stone2 = plain('frame_stone2', '#3b3833', rough=0.92, bump=0.9, bump_scale=26, vary=0.22, speck='#5a554c')
    parts = []
    mortar = plain('mortar', '#2b2620', rough=0.95, bump=0.4, bump_scale=60)
    # a dark backing under the blocks, so the joints read as mortar, not holes
    parts.append(block('back_t', (0, 0.07, Hh / 2 - T / 2), (W, 0.05, T), mortar, bevel=0.0))
    parts.append(block('back_b', (0, 0.07, -Hh / 2 + T / 2), (W, 0.05, T), mortar, bevel=0.0))
    parts.append(block('back_l', (-W / 2 + T / 2, 0.07, 0), (T, 0.05, Hh - 2 * T + 0.02), mortar, bevel=0.0))
    parts.append(block('back_r', (W / 2 - T / 2, 0.07, 0), (T, 0.05, Hh - 2 * T + 0.02), mortar, bevel=0.0))

    def run(x0, x1, y0, y1, horizontal):
        pos = x0 if horizontal else y0
        end = x1 if horizontal else y1
        while pos < end - 0.02:
            L = min(random.uniform(0.28, 0.55), end - pos)
            if end - pos - L < 0.18:
                L = end - pos
            depth = random.uniform(0.05, 0.11)
            for k in range(2):                                  # two courses
                t = T / 2
                if horizontal:
                    cx, cy = pos + L / 2, y0 + t * k + t / 2
                    size = (L - 0.014, depth, t - 0.014)
                else:
                    cx, cy = x0 + t * k + t / 2, pos + L / 2
                    size = (t - 0.014, depth, L - 0.014)
                parts.append(block('stone', (cx, 0, cy), size, random.choice((stone, stone2)),
                                   bevel=0.022))
            pos += L
    for sy in (-1, 1):                                          # top and bottom
        y0 = (Hh / 2 - T) if sy > 0 else -Hh / 2
        run(-W / 2, W / 2, y0, y0 + T, True)
    for sx in (-1, 1):                                          # left and right
        x0 = (W / 2 - T) if sx > 0 else -W / 2
        run(x0, x0 + T, -Hh / 2 + T, Hh / 2 - T, False)
    return parts, None


def piece_emblem(M, with_star=True):
    """The header's centre piece: a compass rose on a dark brass-rimmed plate."""
    parts = []
    parts.append(spin('plate', [(0, 0), (0.95, 0), (0.95, 0.08), (0.88, 0.12), (0, 0.12)], M['gunmetal_dk'], subsurf=1))
    parts.append(torus('rim', 0.93, 0.04, M['brass'], loc=(0, 0, 0.12)))
    for i in range(36):
        a = i * TAU / 36
        parts.append(block('tick', (0.80 * math.cos(a), 0.80 * math.sin(a), 0.14), (0.06 if i % 3 == 0 else 0.035, 0.014, 0.02),
                           M['brass'], rot=(0, 0, a + math.pi / 2), bevel=0.004))
    for i in range(24):                                          # cogs round the rim
        a = i * TAU / 24
        parts.append(block('cog', (1.0 * math.cos(a), 1.0 * math.sin(a), 0.05), (0.10, 0.08, 0.10),
                           M['gunmetal'], rot=(0, 0, a), bevel=0.012))
    if with_star:
        parts.append(star_plate('star8', 4, 0.92, 0.17, 0.13, 0.18, M['steel'], rot=math.pi / 2))
        parts.append(star_plate('star4', 4, 0.68, 0.16, 0.18, 0.22, M['brass'], rot=math.pi / 4))
        parts.append(torus('hub', 0.16, 0.05, M['brass'], loc=(0, 0, 0.24)))
        parts.append(sphere('hubball', 0.12, M['gunmetal'], loc=(0, 0, 0.27), seg=24))
    # two brass gears turning behind the plate (the painted concept has them)
    for gx, gy, r, n, ph in ((-1.02, 0.12, 0.54, 13, 0.0), (1.02, 0.12, 0.54, 13, 0.22)):
        parts.append(spin('gear', [(0, -0.20), (r, -0.20), (r, -0.12), (0, -0.12)], M['brass_dk'], steps=48))
        parts[-1].location = (gx, gy, 0)
        for i in range(n):
            a = ph + i * TAU / n
            parts.append(block('tooth', (gx + (r + 0.05) * math.cos(a), gy + (r + 0.05) * math.sin(a), -0.16),
                               (0.17, 0.15, 0.08), M['brass_dk'], rot=(0, 0, a), bevel=0.014))
        parts.append(torus('gear_rim', r - 0.07, 0.03, M['brass'], loc=(gx, gy, -0.10)))
        parts.append(torus('gear_hub', 0.12, 0.04, M['steel'], loc=(gx, gy, -0.09)))
        for k in range(4):
            a = ph + k * math.pi / 4
            parts.append(block('spoke', (gx, gy, -0.11), (r * 1.7, 0.05, 0.03), M['brass'], rot=(0, 0, a), bevel=0.01))
    return parts, 3.4


def piece_energy_iron(M):
    """The old iron housing (kept for reference): a riveted bar with a dark inset."""
    parts = []
    W, Hh = 4.4, 1.0
    parts.append(block('plate', (0, 0, 0), (W, 0.2, Hh), M['gunmetal'], bevel=0.12))
    parts.append(block('inset', (0, -0.08, 0), (W - 0.5, 0.1, Hh - 0.36), M['dish'], bevel=0.08))
    parts.append(block('lipTop', (0, -0.11, Hh / 2 - 0.20), (W - 0.45, 0.04, 0.035), M['brass'], bevel=0.01))
    parts.append(block('lipBot', (0, -0.11, -Hh / 2 + 0.20), (W - 0.45, 0.04, 0.035), M['brass'], bevel=0.01))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(sphere('rivet', 0.05, M['steel'], loc=(sx * (W / 2 - 0.16), -0.11, sz * (Hh / 2 - 0.12)), scale=(1, 0.6, 1), seg=18))
        parts.append(sphere('cap', 0.06, M['brass'], loc=(sx * (W / 2 - 0.16), -0.12, 0), scale=(1, 0.6, 1), seg=18))
    return parts, None


def piece_energy(M):
    """The energy bar's frame, from TIMBER beams (user 2026-11-04: "die Umrandung
    der Energieleiste aus Holzbalken anstatt Metall"): two long beams, two posts,
    wooden pegs at the joints, and a dark recess behind."""
    wood = camp_kit.mats()['timber']
    wood2 = camp_kit.mats()['planks']
    peg = plain('peg', '#c9904f', rough=0.7, bump=0.3, bump_scale=90, vary=0.1)
    well = plain('well', '#1d130a', rough=0.5, bump=0.1, bump_scale=60, vary=0.0)
    parts = []
    W, Hh, T, B = 4.4, 1.0, 0.20, 0.27                # outer size, depth, beam width
    parts.append(block('well', (0, 0.05, 0), (W - 0.2, 0.05, Hh - 0.2), well, bevel=0.0))
    parts.append(block('beam_t', (0, 0, Hh / 2 - B / 2), (W, T, B), wood, bevel=0.035))
    parts.append(block('beam_b', (0, 0, -Hh / 2 + B / 2), (W, T, B), wood, bevel=0.035))
    for sx in (-1, 1):
        parts.append(block('post', (sx * (W / 2 - B * 0.62), -0.012, 0), (B * 1.24, T + 0.025, Hh), wood2, bevel=0.035))
        for sz in (-1, 1):
            parts.append(sphere('peg', 0.062, peg, loc=(sx * (W / 2 - B * 0.62), -T / 2 - 0.018, sz * (Hh / 2 - 0.13)), scale=(1, 0.45, 1), seg=18))
        # a lighter cap over each post, like an end-grain plug
        parts.append(block('plug', (sx * (W / 2 - B * 0.62), -T / 2 - 0.006, 0), (B * 0.6, 0.03, 0.3), peg, bevel=0.02))
    for x in (-1.2, 1.2):
        for sz in (-1, 1):
            parts.append(sphere('peg', 0.05, peg, loc=(x, -T / 2 - 0.012, sz * (Hh / 2 - B / 2)), scale=(1, 0.45, 1), seg=16))
    return parts, None


# ── button icons ────────────────────────────────────────────
# Small, chunky and readable at 40 px: modelled upright (Z up, facing -Y) and
# photographed head-on with a slight tilt. Each returns (parts, 2.2).
def icon_mats(M):
    M['copper'] = plain('copper', '#c98a4a', rough=0.40, metal=0.85, bump=0.08, bump_scale=70, vary=0.04)
    M['leather2'] = plain('leather2', '#8a5a32', rough=0.7, bump=0.5, bump_scale=60, vary=0.08)
    M['ink'] = plain('ink', '#3a2a18', rough=0.8, bump=0.0, vary=0.0)
    M['green'] = plain('green', '#3f8a3a', rough=0.5, bump=0.0, vary=0.0)
    M['redp'] = plain('redp', '#b3261e', rough=0.5, bump=0.0, vary=0.0)
    M['bluep'] = plain('bluep', '#4a86b8', rough=0.5, bump=0.0, vary=0.0)
    return M


def piece_icon_hammer(M):
    wood = camp_kit.mats()['timber']
    parts = []
    parts.append(cyl(0, 0, -0.95, 0.095, 0.095, 1.55, wood, seg=20))
    for z in (-0.88, 0.5):
        parts.append(torus('band', 0.10, 0.025, M['brass'], loc=(0, 0, z), rot=(0, 0, 0)))
    parts.append(block('head', (0, 0, 0.66), (1.12, 0.40, 0.44), M['steel'], bevel=0.06))
    parts.append(block('face', (0.62, 0, 0.66), (0.20, 0.44, 0.50), M['gunmetal'], bevel=0.05))
    parts.append(block('peen', (-0.58, 0, 0.66), (0.26, 0.30, 0.30), M['gunmetal'], bevel=0.05))
    parts.append(block('capband', (0, 0, 0.66), (0.14, 0.46, 0.50), M['brass'], bevel=0.03))
    return parts, 2.2


def cyl(x, y, z, r1, r2, h, mat, seg=20):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=h, location=(x, y, z + h / 2),
                                    vertices=seg)
    ob = bpy.context.object
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    return ob


def piece_icon_paw(M):
    parts = [sphere('pad', 1.0, M['copper'], loc=(0, 0, -0.25), scale=(0.52, 0.22, 0.42), seg=32)]
    for x, z, r, rot in ((-0.66, 0.30, 0.17, -25), (-0.24, 0.62, 0.19, -8), (0.24, 0.62, 0.19, 8), (0.66, 0.30, 0.17, 25)):
        s = sphere('toe', 1.0, M['copper'], loc=(x, 0, z), scale=(r, 0.16, r * 1.35), seg=24)
        s.rotation_euler = (0, math.radians(rot), 0)
        parts.append(s)
    return parts, 2.2


def piece_icon_map(M):
    paper = parch_mat('map_paper', '#ead7a6', '#c9a468')
    parts = []
    for i, (x, rot) in enumerate(((-0.62, 14), (0.0, -14), (0.62, 14))):
        b = block('panel', (x, 0, 0), (0.66, 0.04, 1.35), paper, rot=(0, 0, math.radians(rot)), bevel=0.01)
        parts.append(b)
    parts.append(block('sea', (-0.62, -0.03, 0.35), (0.40, 0.02, 0.30), M['bluep'], bevel=0.0))
    parts.append(block('land', (0.0, -0.03, -0.25), (0.34, 0.02, 0.30), M['green'], bevel=0.0))
    for k, (x, z) in enumerate(((-0.55, -0.35), (-0.42, -0.15), (-0.2, 0.0), (0.0, 0.2), (0.18, 0.28))):
        parts.append(block('dot', (x, -0.035, z), (0.07, 0.02, 0.07), M['ink'], bevel=0.0))
    for a in (45, -45):
        parts.append(block('x', (0.62, -0.035, 0.3), (0.34, 0.02, 0.07), M['redp'], rot=(0, math.radians(a), 0), bevel=0.0))
    return parts, 2.2


def _figure(M, x, z, s, mat):
    return [sphere('head', 0.27 * s, mat, loc=(x, 0, z + 0.42 * s), seg=28),
            sphere('body', 1.0, mat, loc=(x, 0, z - 0.18 * s), scale=(0.46 * s, 0.28 * s, 0.42 * s), seg=28)]


def piece_icon_people(M):
    parts = _figure(M, 0.34, 0.08, 0.86, M['steel'])
    parts += _figure(M, -0.28, -0.05, 1.0, M['copper'])
    return parts, 2.2


def piece_icon_person(M):
    return _figure(M, 0.0, 0.0, 1.35, M['copper']), 2.2


def piece_icon_bag(M):
    parts = [block('body', (0, 0, -0.1), (1.1, 0.62, 1.25), M['leather2'], bevel=0.18)]
    parts.append(block('flap', (0, -0.08, 0.38), (1.14, 0.66, 0.52), M['leather'], bevel=0.14))
    parts.append(block('pocket', (0, -0.34, -0.45), (0.8, 0.14, 0.42), M['leather'], bevel=0.07))
    for x in (-0.34, 0.34):
        parts.append(block('strap', (x, -0.36, 0.30), (0.12, 0.05, 0.9), M['leather'], bevel=0.02))
    parts.append(block('buckle', (0, -0.42, 0.18), (0.22, 0.05, 0.18), M['brass'], bevel=0.03))
    parts.append(torus('handle', 0.2, 0.035, M['leather'], loc=(0, 0, 0.72), rot=(math.radians(90), 0, 0), seg=28))
    return parts, 2.2


def piece_icon_tasks(M):
    wood = camp_kit.mats()['planks']
    paper = parch_mat('task_paper', '#f0e2b6', '#d2b57a')
    parts = [block('board', (0, 0.04, 0), (1.25, 0.08, 1.6), wood, bevel=0.05)]
    parts.append(block('sheet', (0, -0.02, -0.02), (1.02, 0.03, 1.36), paper, bevel=0.01))
    parts.append(block('clip', (0, -0.06, 0.78), (0.5, 0.07, 0.18), M['brass'], bevel=0.04))
    for z in (0.38, 0.0, -0.38):
        parts.append(block('line', (0.14, -0.045, z), (0.5, 0.015, 0.06), M['ink'], bevel=0.0))
        parts.append(block('tick1', (-0.36, -0.05, z - 0.02), (0.10, 0.02, 0.05), M['green'], rot=(0, math.radians(-40), 0), bevel=0.0))
        parts.append(block('tick2', (-0.28, -0.05, z + 0.03), (0.20, 0.02, 0.05), M['green'], rot=(0, math.radians(50), 0), bevel=0.0))
    return parts, 2.2


def piece_chest_open(M):
    """A treasure chest, lid open, heaped with coins and gems."""
    import random
    random.seed(11)
    planks = camp_kit.mats()['planks']
    cloth = plain('chest_cloth', '#8e1f2a', rough=0.9, bump=0.3, bump_scale=120, vary=0.05)
    parts = []
    W, D, H = 1.7, 0.95, 0.80
    parts.append(block('body', (0, 0, H / 2), (W, D, H), planks, bevel=0.03))
    parts.append(block('lining', (0, 0, H - 0.01), (W - 0.16, D - 0.16, 0.04), cloth, bevel=0.0))
    for x in (-0.62, 0.0, 0.62):
        parts.append(block('strap', (x, -D / 2 - 0.012, H / 2), (0.15, 0.03, H + 0.02), M['gunmetal_dk'], bevel=0.01))
    parts.append(block('rim_f', (0, -D / 2 - 0.012, H - 0.06), (W + 0.04, 0.03, 0.12), M['brass_dk'], bevel=0.01))
    for sx in (-1, 1):
        for sz in (0.10, H - 0.10):
            parts.append(block('corner', (sx * (W / 2 - 0.02), -D / 2 - 0.02, sz), (0.16, 0.04, 0.16), M['brass'], bevel=0.015))
        parts.append(block('side', (sx * (W / 2 + 0.012), 0, H / 2), (0.03, D * 0.92, 0.13), M['gunmetal_dk'], bevel=0.01))
    parts.append(block('lock', (0, -D / 2 - 0.035, H - 0.20), (0.20, 0.04, 0.24), M['brass'], bevel=0.02))
    parts.append(block('keyhole', (0, -D / 2 - 0.058, H - 0.22), (0.04, 0.02, 0.09), M['dish'], bevel=0.0))
    # the open lid, hinged at the back edge
    a = math.radians(75)
    hinge_y, hinge_z = D / 2, H
    L = D * 0.92
    cy_, cz_ = hinge_y + 0.5 * L * math.cos(a), hinge_z + 0.5 * L * math.sin(a)
    parts.append(block('lid', (0, cy_, cz_), (W, L, 0.14), planks, rot=(a, 0, 0), bevel=0.03))
    parts.append(block('lid_in', (0, cy_ - 0.09 * math.sin(a), cz_ - 0.09 * math.cos(a) * -1), (W - 0.14, L - 0.14, 0.03), cloth, rot=(a, 0, 0), bevel=0.0))
    for x in (-0.62, 0.0, 0.62):
        parts.append(block('lid_strap', (x, cy_ + 0.075 * math.sin(a), cz_ - 0.075 * math.cos(a)), (0.15, L + 0.02, 0.03), M['gunmetal_dk'], rot=(a, 0, 0), bevel=0.01))
    # the hoard: coins heaped in the opening, a few rolling out in front
    gold = M['gold']
    for i in range(190):
        x = random.uniform(-0.66, 0.66)
        y = random.uniform(-0.30, 0.30)
        hgt = 0.14 * max(0.0, 1 - (x / 0.74) ** 2 - (y / 0.40) ** 2) + 0.02
        c = cyl(x, y, H + random.uniform(0, hgt), 0.085, 0.085, 0.022, gold, seg=18)
        c.rotation_euler = (random.uniform(-0.7, 0.7), random.uniform(-0.7, 0.7), random.uniform(0, 3))
        parts.append(c)
    for x, y in ((-0.75, -0.62), (-0.55, -0.7), (0.7, -0.66), (0.9, -0.5), (0.45, -0.78)):
        c = cyl(x, y, 0.0, 0.085, 0.085, 0.022, gold, seg=18)
        c.rotation_euler = (random.uniform(-0.2, 0.2), random.uniform(-0.2, 0.2), random.uniform(0, 3))
        parts.append(c)
    gems = ((-0.30, -0.10, '#d8352c'), (0.24, 0.05, '#3f7fe0'), (0.02, -0.18, '#37b24d'), (-0.52, 0.12, '#b44fd6'), (0.50, -0.16, '#f0d26a'))
    for i, (x, y, col) in enumerate(gems):
        gm = plain('gem%d' % i, col, rough=0.12, metal=0.0, bump=0.0, vary=0.0, emit=col, emit_strength=0.7)
        parts.append(sphere('gem', 0.075, gm, loc=(x, y, H + 0.16), scale=(1, 1, 0.9), seg=12))
    return parts, None


def closed_chest(M):
    """A treasure chest with its domed lid shut: upright (Z up, front -Y)."""
    planks = camp_kit.mats()['planks']
    parts = []
    W, D, H = 1.7, 0.95, 0.80
    parts.append(block('body', (0, 0, H / 2), (W, D, H), planks, bevel=0.03))
    # the domed lid: a cylinder lying along X, its lower half sunk into the body
    def barrel(r_scale, length, mat, name):
        bpy.ops.mesh.primitive_cylinder_add(radius=D / 2, depth=length, location=(0, 0, H), vertices=48,
                                            rotation=(0, math.pi / 2, 0))
        ob = bpy.context.object
        ob.name = name
        ob.scale = (r_scale * 0.92, r_scale, 1)         # local x is the height after the turn
        for p in ob.data.polygons:
            p.use_smooth = True
        ob.data.materials.append(mat)
        return ob
    parts.append(barrel(1.0, W, planks, 'lid'))
    for x in (-0.62, 0.0, 0.62):
        parts.append(barrel(1.035, 0.15, M['gunmetal_dk'], 'lid_band'))
        parts[-1].location.x = x
        parts.append(block('strap', (x, -D / 2 - 0.012, H / 2), (0.15, 0.03, H + 0.02), M['gunmetal_dk'], bevel=0.01))
    parts.append(block('rim_f', (0, -D / 2 - 0.016, H - 0.02), (W + 0.04, 0.034, 0.10), M['brass_dk'], bevel=0.01))
    for sx in (-1, 1):
        for sz in (0.10, H - 0.10):
            parts.append(block('corner', (sx * (W / 2 - 0.02), -D / 2 - 0.02, sz), (0.16, 0.04, 0.16), M['brass'], bevel=0.015))
        parts.append(block('side', (sx * (W / 2 + 0.012), 0, H / 2), (0.03, D * 0.92, 0.13), M['gunmetal_dk'], bevel=0.01))
    parts.append(block('lock', (0, -D / 2 - 0.045, H - 0.06), (0.22, 0.05, 0.28), M['brass'], bevel=0.02))
    parts.append(block('keyhole', (0, -D / 2 - 0.075, H - 0.08), (0.04, 0.02, 0.10), M['dish'], bevel=0.0))
    return parts


def piece_chest(M):
    """The header's centre piece: a closed treasure chest on the same
    brass-rimmed plate, with the same gears behind it, as the compass had."""
    plate, size = piece_emblem(M, with_star=False)
    chest = closed_chest(M)
    return plate, size, chest


# ── scene ───────────────────────────────────────────────────
def frame(parts, size, pitch=0.0):
    """Orthographic camera looking along +Y, square (or fitted) window."""
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    pts = []
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            pts.append(o.matrix_world @ Vector(c))
    xs = [p.x for p in pts]
    zs = [p.z for p in pts]
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(90 - pitch), 0, 0)
    sc.camera = cam
    cam.data.clip_end = 500
    q = Euler(cam.rotation_euler).to_quaternion()
    right, up, back = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), q @ Vector((0, 0, 1))
    if size:                                           # a square piece, centred on the axis
        w = h = size
        cx = cz = 0.0
    else:
        pad = 0.06
        if pitch >= 15:                    # a tilted view: measure in the camera's own axes
            xs = [p.dot(right) for p in pts]
            zs = [p.dot(up) for p in pts]
            pad = 0.10
        w, h = max(xs) - min(xs) + 2 * pad, max(zs) - min(zs) + 2 * pad
        cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
    cam.data.ortho_scale = max(w, h)
    if pitch >= 15 and not size:
        cam.location = right * cx + up * cz + back * 30
    else:
        cam.location = right * cx + up * cz / math.cos(math.radians(pitch)) + back * 30
    return w, h


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
    cy.max_bounces = 8
    cy.glossy_bounces = 5
    sc.render.film_transparent = True
    sc.render.filter_size = 0.9
    vs = sc.view_settings
    names = vs.bl_rna.properties['view_transform'].enum_items.keys()
    vs.view_transform = 'AgX' if 'AgX' in names else 'Filmic'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast', 'AgX - Punchy', 'Punchy'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = 0.2


def to_webp(png, dst):
    sc = bpy.context.scene
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    img = bpy.data.images.load(png)
    st = sc.render.image_settings
    st.file_format = 'WEBP'
    st.color_mode = 'RGBA'
    st.quality = 92
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save_render(dst, scene=sc)
    bpy.data.images.remove(img)
    print('SHIPPED', dst, os.path.getsize(dst), 'bytes')


PIECES = {
    'button': (piece_button, True, 0.0),
    'compass': (piece_compass, True, 0.0),
    'bell': (piece_bell, False, 6.0),
    'parchment': (piece_parchment, False, 0.0),
    'scroll': (piece_scroll, False, 0.0),
    'frame': (piece_frame, False, 0.0),
    'emblem': (piece_emblem, True, 0.0),
    'energy': (piece_energy, False, 0.0),
    'chest_open': (piece_chest_open, False, 24.0),
    'chest': (piece_chest, True, 20.0),
    'icon_hammer': (piece_icon_hammer, False, 8.0),
    'icon_paw': (piece_icon_paw, False, 8.0),
    'icon_map': (piece_icon_map, False, 8.0),
    'icon_people': (piece_icon_people, False, 8.0),
    'icon_person': (piece_icon_person, False, 8.0),
    'icon_bag': (piece_icon_bag, False, 8.0),
    'icon_tasks': (piece_icon_tasks, False, 8.0),
}
TILT = {'icon_hammer': 35.0}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('pieces', nargs='+')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--px', type=int, default=512)
    args = ap.parse_args(argv)
    for name in args.pieces:
        fn, faces_camera, pitch = PIECES[name]
        rb.clear()
        K._mats.clear()
        M = icon_mats(ui_mats(camp_kit.mats()))
        res = fn(M)
        parts, size = res[0], res[1]
        upright = res[2] if len(res) > 2 else []
        if faces_camera:
            # built with Z out of the face; stand it up so Z points at the camera
            root = bpy.data.objects.new('root', None)
            bpy.context.scene.collection.objects.link(root)
            root.rotation_euler = (math.radians(90), 0, 0)
            for o in parts:
                o.parent = root
        if upright:
            # parts that stand on their own (not turned with the face): in front of it
            chest_root = bpy.data.objects.new('chest_root', None)
            bpy.context.scene.collection.objects.link(chest_root)
            chest_root.location = (0, -0.17, -0.52)
            chest_root.scale = (0.80, 0.80, 0.80)
            chest_root.rotation_euler = (0, 0, math.radians(-30))
            for o in upright:
                o.parent = chest_root
        if TILT.get(name):
            tilt = bpy.data.objects.new('tilt', None)
            bpy.context.scene.collection.objects.link(tilt)
            tilt.rotation_euler = (0, math.radians(TILT[name]), 0)
            for o in parts:
                o.parent = tilt
        K.lighting(azimuth=0, elev=52, swing=-28)
        w, h = frame(parts, size, pitch)
        sc = bpy.context.scene
        k = args.px / max(w, h)
        sc.render.resolution_x = round(w * k)
        sc.render.resolution_y = round(h * k)
        cycles(args.samples)
        png = os.path.join(ROOT, 'docs', 'renders', 'ui', name + '.png')
        os.makedirs(os.path.dirname(png), exist_ok=True)
        K.render(png)
        to_webp(png, os.path.join(ROOT, 'assets', 'images', 'ui', name + '.webp'))


if __name__ == '__main__':
    main()
