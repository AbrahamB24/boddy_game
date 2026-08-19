"""A photoreal Large Quarry — one landmark building, deliberately OUTSIDE the
low-poly kit in tool/blender/render_building.py.

    blender --background --python tool/blender/quarry_photoreal.py -- \
        --out docs/renders/large_quarry_draft.png

── Why this file exists on its own (user 2026-08-16) ──
Every other building in this game is flat-shaded, faceted, one warm hue
family — on purpose, so ~30 buildings and the monsters read as one set (see
docs/blender_pipeline.md, docs/building_art_prompt.md). This one is not that:
the brief is a specific photoreal reference (a sculpted rock quarry, soft
lighting, real material response) and an explicit "unabhängig vom Baukasten".
So: Cycles instead of the flat 'Standard' EEVEE look, sculpted/displaced rock
instead of boxes, and PBR-ish materials instead of one flat colour per facet.
It will not match the other buildings on the map, and that is the ask, not a
bug.

── Stage 1: shape, material, light — no props yet ──
Get the rock mound, its colour response and the lighting mood right FIRST.
Everything else (the derrick, the shelters, the rails) is judged against
whether it sits convincingly on this ground, so building them before the
ground reads as rock would mean re-judging them a second time later.
"""
import argparse
import math
import os
import sys

import bpy
import mathutils
from mathutils import noise as mnoise

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))


# ── The mound's shape: a pure function of (x, y) ──────────────
# Two raised rock masses (the back ridge, and the shoulder the crane will
# stand on at the back-right) minus a worked-out basin in the middle, plus
# fine turbulence for the rock's own roughness. Kept as one function so the
# mesh, the "is this cell part of the island" mask and any later prop
# placement all read the same ground.

# A quarry is a FLOOR with a wall on one side, not a crater — the first pass
# fused the ridge and the shoulder into one continuous mountain because both
# reached toward the centre. Both are now pinned to their own CORNER, with a
# short radius that keeps their influence off the floor entirely, and the
# floor itself is the dominant area: a broad, gently terraced bench most of
# the picture is actually looking at, exactly as in the reference.
RIDGE = (-2.75, 2.7, 1.9, 3.1)       # x, y, radius, height — back-left wall
SHOULDER = (2.85, 2.55, 1.55, 1.85)  # the crane's outcrop, back-right corner
ISLAND_R = 3.35                      # where the mound falls off into a cliff
FLOOR_Z = 0.35                       # the worked floor's base height


def _falloff(dx, dy, r):
    d = math.hypot(dx, dy) / r
    return max(0.0, 1.0 - d) ** 1.8


def macro_height(x, y):
    h = FLOOR_Z
    h += _falloff(x - RIDGE[0], y - RIDGE[1], RIDGE[2]) * RIDGE[3]
    h += _falloff(x - SHOULDER[0], y - SHOULDER[1], SHOULDER[2]) * SHOULDER[3]
    # Terraces: the floor steps DOWN toward the camera (front = −y), in a
    # few big benches rather than a slope — what "worked" looks like.
    bench = -y * 0.11
    step = 0.34
    h += math.floor(bench / step) * step - bench
    return h


def height(x, y):
    on_wall = max(_falloff(x - RIDGE[0], y - RIDGE[1], RIDGE[2]),
                  _falloff(x - SHOULDER[0], y - SHOULDER[1], SHOULDER[2]))
    m = macro_height(x, y)
    # Fine rock grain: two octaves of turbulence. Much rougher on the wall
    # than on the trodden floor — a worked surface is not as broken as a
    # cliff face.
    t = mnoise.turbulence((x * 1.6, y * 1.6, 0.0), 3, False)
    m += (t - 0.5) * (0.10 + 0.5 * on_wall)
    d = math.hypot(x, y)
    if d > ISLAND_R - 0.5:
        # The cliff: falls to a hard base OUTSIDE the island's own radius,
        # so the mound reads as a cut-away outcrop, not a hill fading to grass.
        f = min(1.0, (d - (ISLAND_R - 0.5)) / 0.5)
        m = m * (1 - f) + (-1.6) * f
    return m


def build_mound(res=180, extent=4.0):
    verts = []
    idx = {}
    n = res
    for j in range(n + 1):
        for i in range(n + 1):
            x = -extent + 2 * extent * i / n
            y = -extent + 2 * extent * j / n
            z = height(x, y)
            idx[(i, j)] = len(verts)
            verts.append((x, y, z))
    faces = []
    for j in range(n):
        for i in range(n):
            a, b = idx[(i, j)], idx[(i + 1, j)]
            c, d = idx[(i + 1, j + 1)], idx[(i, j + 1)]
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new('mound')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new('mound', mesh)
    bpy.context.collection.objects.link(ob)
    ob.data.polygons.foreach_set(
        'use_smooth', [True] * len(ob.data.polygons))
    ob.data.update()
    return ob


# ── Material: rock, from noise, not from a flat swatch ────────
def rock_material():
    mat = bpy.data.materials.new('rock')
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)

    out = nodes.new('ShaderNodeOutputMaterial')
    out.location = (600, 0)
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-900, 0)

    # Large-scale colour variation: warm ochre rock with cooler grey seams,
    # driven by two noise scales mixed together — one broad (patches of
    # lichen/weather), one fine (the strata banding).
    noise_big = nodes.new('ShaderNodeTexNoise')
    noise_big.location = (-700, 200)
    noise_big.inputs['Scale'].default_value = 1.1
    noise_big.inputs['Detail'].default_value = 4.0
    noise_big.inputs['Roughness'].default_value = 0.6

    noise_small = nodes.new('ShaderNodeTexNoise')
    noise_small.location = (-700, -100)
    noise_small.inputs['Scale'].default_value = 9.0
    noise_small.inputs['Detail'].default_value = 8.0
    noise_small.inputs['Roughness'].default_value = 0.75

    # Streaks, not bands: a Voronoi's DISTANCE-TO-EDGE field gives seams
    # between cells rather than a Wave's perfectly regular corduroy (that
    # read as woven fabric, not rock). But Voronoi cells ALONE are still too
    # regular — every seam the same width reads as crazy paving / dried mud.
    # DOMAIN WARPING is the fix: distort the coordinate the cells are built
    # from with two octaves of noise BEFORE it reaches Voronoi, so the cell
    # walls bend and vary like real fracture lines instead of tiling.
    warp1 = nodes.new('ShaderNodeTexNoise')
    warp1.location = (-1000, -500)
    warp1.inputs['Scale'].default_value = 0.9
    warp1.inputs['Detail'].default_value = 3.0
    warp2 = nodes.new('ShaderNodeTexNoise')
    warp2.location = (-1000, -700)
    warp2.inputs['Scale'].default_value = 3.5
    warp2.inputs['Detail'].default_value = 4.0

    warp_mix = nodes.new('ShaderNodeVectorMath')
    warp_mix.location = (-820, -600)
    warp_mix.operation = 'MULTIPLY'
    warp_mix.inputs[1].default_value = (0.45, 0.45, 0.45)
    links.new(warp1.outputs['Color'], warp_mix.inputs[0])
    warp_add = nodes.new('ShaderNodeVectorMath')
    warp_add.location = (-820, -450)
    warp_add.operation = 'MULTIPLY'
    warp_add.inputs[1].default_value = (0.18, 0.18, 0.18)
    links.new(warp2.outputs['Color'], warp_add.inputs[0])

    warp_combine = nodes.new('ShaderNodeVectorMath')
    warp_combine.location = (-620, -550)
    warp_combine.operation = 'ADD'
    links.new(warp_mix.outputs['Vector'], warp_combine.inputs[0])
    links.new(warp_add.outputs['Vector'], warp_combine.inputs[1])
    warp_final = nodes.new('ShaderNodeVectorMath')
    warp_final.location = (-480, -550)
    warp_final.operation = 'ADD'
    links.new(warp_combine.outputs['Vector'], warp_final.inputs[1])

    voronoi = nodes.new('ShaderNodeTexVoronoi')
    voronoi.location = (-300, -350)
    voronoi.voronoi_dimensions = '3D'
    voronoi.feature = 'DISTANCE_TO_EDGE'
    voronoi.inputs['Scale'].default_value = 2.4

    links.new(tex_coord.outputs['Object'], noise_big.inputs['Vector'])
    links.new(tex_coord.outputs['Object'], noise_small.inputs['Vector'])
    links.new(tex_coord.outputs['Object'], warp1.inputs['Vector'])
    links.new(tex_coord.outputs['Object'], warp2.inputs['Vector'])
    links.new(tex_coord.outputs['Object'], warp_final.inputs[0])
    links.new(warp_final.outputs['Vector'], voronoi.inputs['Vector'])

    ramp_base = nodes.new('ShaderNodeValToRGB')
    ramp_base.location = (-400, 250)
    ramp_base.color_ramp.elements[0].position = 0.35
    ramp_base.color_ramp.elements[0].color = (0.36, 0.27, 0.18, 1)
    ramp_base.color_ramp.elements[1].position = 0.7
    ramp_base.color_ramp.elements[1].color = (0.68, 0.54, 0.38, 1)
    links.new(noise_big.outputs['Fac'], ramp_base.inputs['Fac'])

    ramp_seam = nodes.new('ShaderNodeValToRGB')
    ramp_seam.location = (-150, -350)
    ramp_seam.color_ramp.elements[0].position = 0.0
    ramp_seam.color_ramp.elements[0].color = (0.34, 0.28, 0.21, 1)
    ramp_seam.color_ramp.elements[1].position = 0.4
    ramp_seam.color_ramp.elements[1].color = (0.78, 0.70, 0.58, 1)
    links.new(voronoi.outputs['Distance'], ramp_seam.inputs['Fac'])

    mix_color = nodes.new('ShaderNodeMixRGB')
    mix_color.location = (150, 100)
    mix_color.blend_type = 'MULTIPLY'
    mix_color.inputs['Fac'].default_value = 0.28
    links.new(ramp_base.outputs['Color'], mix_color.inputs['Color1'])
    links.new(ramp_seam.outputs['Color'], mix_color.inputs['Color2'])
    links.new(mix_color.outputs['Color'], bsdf.inputs['Base Color'])

    # Roughness varies with the same fine noise, so wet-looking hot-spots
    # never happen — a uniform roughness is the thing that makes procedural
    # rock look like plastic.
    ramp_rough = nodes.new('ShaderNodeValToRGB')
    ramp_rough.location = (-400, -600)
    ramp_rough.color_ramp.elements[0].position = 0.3
    ramp_rough.color_ramp.elements[0].color = (0.75, 0.75, 0.75, 1)
    ramp_rough.color_ramp.elements[1].position = 0.7
    ramp_rough.color_ramp.elements[1].color = (0.95, 0.95, 0.95, 1)
    links.new(noise_small.outputs['Fac'], ramp_rough.inputs['Fac'])
    links.new(ramp_rough.outputs['Color'], bsdf.inputs['Roughness'])

    bump = nodes.new('ShaderNodeBump')
    bump.location = (0, -250)
    bump.inputs['Strength'].default_value = 0.35
    links.new(noise_small.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    bsdf.inputs['Specular IOR Level'].default_value = 0.3
    return mat


# ── Props: a small, independent mesh kit ───────────────────────
# Not tool/blender/render_building.py's box()/cyl() — those exist to build
# FLAT-SHADED facets for the toy style. These are beveled and smooth-shaded
# for a photoreal read, which is a different enough contract to warrant its
# own copies rather than a shared function with a style flag threaded
# through it.

def box(name, x, y, z, sx, sy, sz, mat, bevel=0.02):
    verts = [(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
             (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
             (-sx / 2, -sy / 2, sz), (sx / 2, -sy / 2, sz),
             (sx / 2, sy / 2, sz), (-sx / 2, sy / 2, sz)]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2),
             (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    if bevel:
        m = ob.modifiers.new('bevel', 'BEVEL')
        m.width = bevel
        m.segments = 3
        m.limit_method = 'ANGLE'
    return ob


def cyl(name, x, y, z, r, h, mat, sides=12, axis='z'):
    bot = [(r * math.cos(2 * math.pi * i / sides),
            r * math.sin(2 * math.pi * i / sides), 0) for i in range(sides)]
    top = [(r * math.cos(2 * math.pi * i / sides),
            r * math.sin(2 * math.pi * i / sides), h) for i in range(sides)]
    verts = bot + top
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i)
             for i in range(sides)]
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, 2 * sides)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    if axis == 'x':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'y':
        ob.rotation_euler = (-math.pi / 2, 0, 0)
    return ob


def strut(name, p0, p1, r, mat, sides=8):
    """A cylinder BETWEEN two points — every raking leg, brace and rope is
    two ground/anchor points, not a length-and-two-angles guess."""
    p0, p1 = mathutils.Vector(p0), mathutils.Vector(p1)
    d = p1 - p0
    length = d.length
    if length < 1e-5:
        return None
    ob = cyl(name, p0.x, p0.y, p0.z, r, length, mat, sides=sides)
    rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.rotation_euler = rot.to_euler()
    return ob


def lerp(p0, p1, t):
    return tuple(a + (b - a) * t for a, b in zip(p0, p1))


def ground(x, y):
    return height(x, y)


def wood_material():
    mat = bpy.data.materials.new('wood')
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes['Principled BSDF']
    tex_coord = nodes.new('ShaderNodeTexCoord')
    mapping = nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = (1, 1, 7)
    links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 3.5
    noise.inputs['Detail'].default_value = 5.0
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.14, 0.09, 0.05, 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (0.40, 0.27, 0.15, 1)
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.12
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def metal_material():
    mat = bpy.data.materials.new('iron')
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (0.09, 0.075, 0.065, 1)
    bsdf.inputs['Roughness'].default_value = 0.4
    bsdf.inputs['Metallic'].default_value = 0.75
    return mat


def stone_block_material():
    mat = bpy.data.materials.new('cutstone')
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes['Principled BSDF']
    tex_coord = nodes.new('ShaderNodeTexCoord')
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 9.0
    links.new(tex_coord.outputs['Object'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.4
    ramp.color_ramp.elements[0].color = (0.58, 0.54, 0.47, 1)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.76, 0.72, 0.63, 1)
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55
    return mat


def build_crane(x, y, mat_wood, mat_iron, hh=3.1):
    """A raking timber derrick: two splayed legs to an apex, a back stay,
    cross bracing, a pulley and a hanging rope — the single most
    identity-giving object in the reference, so it goes in first."""
    base_z = ground(x, y)
    top = (x - 0.35, y - 0.25, base_z + hh)
    leg_a0 = (x + 0.55, y + 0.65, ground(x + 0.55, y + 0.65))
    leg_b0 = (x + 0.95, y - 0.25, ground(x + 0.95, y - 0.25))
    strut('crane_legA', leg_a0, top, 0.10, mat_wood)
    strut('crane_legB', leg_b0, top, 0.10, mat_wood)
    for t in (0.32, 0.58, 0.82):
        strut(f'crane_brace{t}', lerp(leg_a0, top, t), lerp(leg_b0, top, t),
              0.04, mat_wood)
    back0 = (x - 1.1, y - 1.05, ground(x - 1.1, y - 1.05))
    strut('crane_back', back0, top, 0.085, mat_wood)
    for t in (0.4, 0.75):
        strut(f'crane_backbrace{t}', lerp(back0, top, t),
              lerp(leg_a0, top, t * 0.9), 0.035, mat_wood)
    cyl('crane_pulley', top[0], top[1] + 0.02, top[2] - 0.06, 0.13, 0.07,
        mat_iron, sides=14, axis='x')
    rope_end = (top[0] + 0.15, top[1], base_z + 0.35)
    strut('crane_rope', (top[0], top[1] + 0.02, top[2] - 0.06), rope_end,
          0.018, mat_iron, sides=6)
    box('crane_hook', rope_end[0], rope_end[1], rope_end[2] - 0.12, 0.12,
        0.08, 0.14, mat_iron, bevel=0.01)


def build_leanto(name, x, y, mat_wood, w=1.05, d=0.85, h=1.0, drop=0.32):
    base_z = ground(x, y)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            px, py = x + sx_ * (w / 2 - 0.06), y + sy_ * (d / 2 - 0.06)
            ph = h - (drop if sy_ < 0 else 0)
            strut(f'{name}_p{sx_}{sy_}', (px, py, ground(px, py)),
                  (px, py, ground(px, py) + ph), 0.035, mat_wood, sides=6)
    roof = box(f'{name}_roof', x, y, base_z + h - drop * 0.35, w + 0.18,
              d + 0.18, 0.045, mat_wood, bevel=0.006)
    roof.rotation_euler = (math.atan2(drop, d), 0, 0)


def build_stone_stack(name, x, y, mat_stone, n=6, spread=0.55):
    for i in range(n):
        j = ((i * 37 + 11) % 97) / 97.0
        k = ((i * 53 + 29) % 97) / 97.0
        bx, by = x + (j - 0.5) * spread, y + (k - 0.5) * spread * 0.85
        s = 0.24 + 0.11 * j
        b = box(f'{name}{i}', bx, by, ground(bx, by), s, s * 0.85, s * 0.6,
               mat_stone, bevel=0.012)
        b.rotation_euler = (0, 0, k * 3.0)


def build_rails(name, p0, p1, mat_iron, mat_wood, gauge=0.3, ties=9):
    p0v, p1v = mathutils.Vector(p0[:2]), mathutils.Vector(p1[:2])
    d = p1v - p0v
    perp = mathutils.Vector((-d.y, d.x)).normalized() * gauge / 2
    for s in (-1, 1):
        pts = []
        n = 10
        for i in range(n + 1):
            c = p0v.lerp(p1v, i / n) + perp * s
            pts.append((c.x, c.y, ground(c.x, c.y) + 0.05))
        for i in range(n):
            strut(f'{name}_r{s}_{i}', pts[i], pts[i + 1], 0.022, mat_iron,
                  sides=6)
    for i in range(ties):
        t = (i + 0.5) / ties
        c = p0v.lerp(p1v, t)
        gz = ground(c.x, c.y) + 0.02
        a = (c - perp * 1.25).to_tuple()
        b_ = (c + perp * 1.25).to_tuple()
        strut(f'{name}_tie{i}', (a[0], a[1], gz), (b_[0], b_[1], gz), 0.05,
              mat_wood, sides=6)


def sky_world(strength=0.9):
    """A plain two-tone gradient for ambient fill, at a strength I control —
    not ShaderNodeTexSky: that node outputs true physical radiance (the sun
    disc alone is tens of thousands of W/m^2/sr), and no scene-referred
    'strength' multiplier tames that predictably. A flat gradient plus one
    Sun lamp gives the same soft-fill-plus-key-light look with an exposure I
    can actually reason about.
    """
    world = bpy.data.worlds.new('sky')
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    bg = nodes.new('ShaderNodeBackground')
    grad = nodes.new('ShaderNodeTexGradient')
    grad.gradient_type = 'SPHERICAL'
    mapping = nodes.new('ShaderNodeMapping')
    tex_coord = nodes.new('ShaderNodeTexCoord')
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.62, 0.66, 0.72, 1)   # zenith
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.86, 0.80, 0.68, 1)   # horizon
    out = nodes.new('ShaderNodeOutputWorld')
    links.new(tex_coord.outputs['Generated'], mapping.inputs['Vector'])
    links.new(mapping.outputs['Vector'], grad.inputs['Vector'])
    links.new(grad.outputs['Color'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = strength
    links.new(bg.outputs['Background'], out.inputs['Surface'])


def sun():
    light_data = bpy.data.lights.new('sun', type='SUN')
    light_data.energy = 3.2
    light_data.angle = math.radians(4.0)   # a soft-ish shadow, not razor
    ob = bpy.data.objects.new('sun', light_data)
    bpy.context.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(58), 0, math.radians(-20))
    return ob


def camera(dist=15.0, elev=34, azim=-35, ortho=False):
    cam_data = bpy.data.cameras.new('cam')
    if ortho:
        cam_data.type = 'ORTHO'
        cam_data.ortho_scale = 8.5
    else:
        cam_data.lens = 32
    ob = bpy.data.objects.new('cam', cam_data)
    bpy.context.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    er, ea = math.radians(elev), math.radians(azim)
    ob.location = (dist * math.cos(er) * math.sin(ea),
                   -dist * math.cos(er) * math.cos(ea),
                   dist * math.sin(er) + 0.5)
    ob.rotation_euler = (math.radians(90 - elev), 0, ea)
    return ob


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='docs/renders/large_quarry_draft.png')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--res', type=int, default=180)
    ap.add_argument('--width', type=int, default=1200)
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    mound = build_mound(res=args.res)
    mound.data.materials.append(rock_material())
    # NO Subsurf: it was averaging the terrace steps and the ridge/shoulder's
    # sharp corners straight into one smooth dome — the actual cause of the
    # mound reading as a hill instead of a floor with a wall on one side.
    # Smooth SHADING (set in build_mound) already softens the small bumps
    # without moving a single vertex.

    mat_wood = wood_material()
    mat_iron = metal_material()
    mat_stone = stone_block_material()

    build_crane(2.3, 2.0, mat_wood, mat_iron, hh=3.0)
    build_leanto('leanto0', -1.85, 1.55, mat_wood, w=1.1, d=0.9, h=1.05)
    build_leanto('leanto1', -1.15, 0.35, mat_wood, w=0.95, d=0.8, h=0.9)
    build_stone_stack('stack0', -0.4, -0.6, mat_stone, n=7)
    build_stone_stack('stack1', 0.9, -1.15, mat_stone, n=6)
    build_stone_stack('stack2', -1.7, -0.5, mat_stone, n=5)
    build_rails('rail0', (0.1, -2.1), (1.9, 1.1), mat_iron, mat_wood)

    sky_world()
    sun()
    camera()

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.cycles.adaptive_threshold = 0.02
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'CUDA'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = 'GPU'
    except Exception as e:
        print(f'  GPU unavailable, using CPU  ({e})')
        scene.cycles.device = 'CPU'

    scene.render.film_transparent = True
    scene.render.resolution_x = args.width
    scene.render.resolution_y = round(args.width * 0.82)
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'

    out_path = os.path.abspath(os.path.join(_ROOT, args.out))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f'wrote {out_path}')


main()
