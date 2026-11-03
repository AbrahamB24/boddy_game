"""Shared kit for the photoreal ("pro") building renders.

The older render_building.py draws flat-colour boxes with procedural grain. This
kit is what the reference look needs instead: real photographic PBR textures
(Poly Haven, CC0 — see fetch_textures.py), real geometry for the small things
(tiles' ridge caps, straw, cobbles, grass blades), a golden-hour light rig and
Cycles. It reuses render_building.frame() so the footprint, camera and framing
are byte-for-byte the ones the map already expects.

Everything is built in WORLD coordinates unless it is a beam or a rotated slab,
which are built in their own local space so a texture's grain follows the part.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import render_building as rb  # noqa: E402  (frame(), clear(), guide_plane())

TEX = os.path.join(HERE, 'textures')
G = 0.18            # height of the ground tile's top face

_mats = {}


# ── colour ──────────────────────────────────────────────────
def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h, a=1.0):
    h = h.lstrip('#')
    return (lin(int(h[0:2], 16) / 255), lin(int(h[2:4], 16) / 255),
            lin(int(h[4:6], 16) / 255), a)


# ── materials ───────────────────────────────────────────────
def _img(nt, path, srgb):
    n = nt.nodes.new('ShaderNodeTexImage')
    n.image = bpy.data.images.load(path, check_existing=True)
    n.image.colorspace_settings.name = 'sRGB' if srgb else 'Non-Color'
    n.interpolation = 'Cubic'
    return n


def tex_mat(key, tex, size=1.0, tint=(1, 1, 1), sat=1.0, val=1.0, rough=1.0,
            nstr=1.0, vary=0.10, uv_scale=None, sheen=0.0):
    """A photo-textured material, box-projected in OBJECT space.

    Each object gets its own random offset into the texture and its own small
    brightness shift, so ten boxes of one material do not look stamped.
    uv_scale=(u, v) switches to the mesh's UVs (cones, which box-projection
    smears) with that many repeats.
    """
    if key in _mats:
        return _mats[key]
    d = os.path.join(TEX, tex)
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    info = nt.nodes.new('ShaderNodeObjectInfo')
    rnd = info.outputs['Random']
    comb = nt.nodes.new('ShaderNodeCombineXYZ')
    for i, k in enumerate((7.13, 11.7, 5.31)):
        mu = nt.nodes.new('ShaderNodeMath')
        mu.operation = 'MULTIPLY'
        mu.inputs[1].default_value = k
        nt.links.new(rnd, mu.inputs[0])
        nt.links.new(mu.outputs[0], comb.inputs[i])

    mp = nt.nodes.new('ShaderNodeMapping')
    if uv_scale:
        co = nt.nodes.new('ShaderNodeUVMap')
        mp.inputs['Scale'].default_value = (uv_scale[0], uv_scale[1], 1)
        nt.links.new(co.outputs['UV'], mp.inputs['Vector'])
    else:
        co = nt.nodes.new('ShaderNodeTexCoord')
        mp.inputs['Scale'].default_value = (1 / size,) * 3
        nt.links.new(co.outputs['Object'], mp.inputs['Vector'])
        nt.links.new(comb.outputs[0], mp.inputs['Location'])

    def sample(name, srgb):
        n = _img(nt, os.path.join(d, name + '.jpg'), srgb)
        if not uv_scale:
            n.projection = 'BOX'
            n.projection_blend = 0.18
        nt.links.new(mp.outputs[0], n.inputs['Vector'])
        return n

    diff = sample('Diffuse', True)
    hsv = nt.nodes.new('ShaderNodeHueSaturation')
    hsv.inputs['Saturation'].default_value = sat
    hsv.inputs['Value'].default_value = val
    nt.links.new(diff.outputs['Color'], hsv.inputs['Color'])

    mx = nt.nodes.new('ShaderNodeMix')
    mx.data_type = 'RGBA'
    mx.blend_type = 'MULTIPLY'
    mx.inputs[0].default_value = 1.0
    mx.inputs[7].default_value = (*tint, 1)
    nt.links.new(hsv.outputs['Color'], mx.inputs[6])

    # per-object brightness shift: 1 - vary .. 1 + vary
    var = nt.nodes.new('ShaderNodeHueSaturation')
    sc = nt.nodes.new('ShaderNodeMath')
    sc.operation = 'MULTIPLY_ADD'
    sc.inputs[1].default_value = 2 * vary
    sc.inputs[2].default_value = 1 - vary
    nt.links.new(rnd, sc.inputs[0])
    nt.links.new(sc.outputs[0], var.inputs['Value'])
    nt.links.new(mx.outputs[2], var.inputs['Color'])
    nt.links.new(var.outputs['Color'], bsdf.inputs['Base Color'])

    r = sample('Rough', False)
    rm = nt.nodes.new('ShaderNodeMath')
    rm.operation = 'MULTIPLY'
    rm.inputs[1].default_value = rough
    nt.links.new(r.outputs['Color'], rm.inputs[0])
    nt.links.new(rm.outputs[0], bsdf.inputs['Roughness'])

    nrm = sample('nor_gl', False)
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nm.inputs['Strength'].default_value = nstr
    nt.links.new(nrm.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if sheen:
        for k in ('Sheen Weight',):
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = sheen
    _mats[key] = m
    return m


def plain(key, rgb, rough=0.7, metal=0.0, bump=0.12, bump_scale=60.0,
          emit=None, emit_strength=0.0, vary=0.08, speck=None, alpha=None):
    """A painted/dyed surface: one colour, fine noise relief, per-object shift."""
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    base = hexc(rgb) if isinstance(rgb, str) else (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal

    coord = nt.nodes.new('ShaderNodeTexCoord')
    info = nt.nodes.new('ShaderNodeObjectInfo')
    var = nt.nodes.new('ShaderNodeHueSaturation')
    sc = nt.nodes.new('ShaderNodeMath')
    sc.operation = 'MULTIPLY_ADD'
    sc.inputs[1].default_value = 2 * vary
    sc.inputs[2].default_value = 1 - vary
    nt.links.new(info.outputs['Random'], sc.inputs[0])
    nt.links.new(sc.outputs[0], var.inputs['Value'])

    colsrc = None
    if speck:
        n2 = nt.nodes.new('ShaderNodeTexNoise')
        n2.inputs['Scale'].default_value = 38.0
        n2.inputs['Detail'].default_value = 1.0
        nt.links.new(coord.outputs['Object'], n2.inputs['Vector'])
        rp = nt.nodes.new('ShaderNodeValToRGB')
        rp.color_ramp.elements[0].position = 0.60
        rp.color_ramp.elements[1].position = 0.64
        nt.links.new(n2.outputs['Fac'], rp.inputs['Fac'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs[6].default_value = base
        mix.inputs[7].default_value = hexc(speck) if isinstance(speck, str) else (*speck, 1)
        nt.links.new(rp.outputs['Color'], mix.inputs[0])
        colsrc = mix.outputs[2]
    if colsrc is not None:
        nt.links.new(colsrc, var.inputs['Color'])
    else:
        var.inputs['Color'].default_value = base
    nt.links.new(var.outputs['Color'], bsdf.inputs['Base Color'])

    if bump > 0:
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = bump_scale
        n.inputs['Detail'].default_value = 5.0
        nt.links.new(coord.outputs['Object'], n.inputs['Vector'])
        b = nt.nodes.new('ShaderNodeBump')
        b.inputs['Strength'].default_value = bump
        b.inputs['Distance'].default_value = 0.01
        nt.links.new(n.outputs['Fac'], b.inputs['Height'])
        nt.links.new(b.outputs['Normal'], bsdf.inputs['Normal'])
    if emit:
        c = hexc(emit) if isinstance(emit, str) else (*emit, 1)
        bsdf.inputs['Emission Color'].default_value = c
        bsdf.inputs['Emission Strength'].default_value = emit_strength
    _mats[key] = m
    return m


def blade_mat(key, base, tip):
    """Grass blade: dark at the root, sun-bleached at the tip — height-driven."""
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.6
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(geo.outputs['Position'], sep.inputs[0])
    mp = nt.nodes.new('ShaderNodeMapRange')
    mp.inputs['From Min'].default_value = G
    mp.inputs['From Max'].default_value = G + 0.11
    nt.links.new(sep.outputs['Z'], mp.inputs['Value'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    rp.color_ramp.elements[0].color = hexc(base)
    rp.color_ramp.elements[1].color = hexc(tip)
    nt.links.new(mp.outputs['Result'], rp.inputs['Fac'])
    nt.links.new(rp.outputs['Color'], bsdf.inputs['Base Color'])
    _mats[key] = m
    return m


# ── geometry ────────────────────────────────────────────────
def _put(ob, mat, bevel, smooth=False):
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    if bevel:
        m = ob.modifiers.new('bevel', 'BEVEL')
        m.width = bevel
        m.segments = 2
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(35)
    return ob


def _mesh(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def box(x, y, z, sx, sy, sz, mat, bevel=0.006, name='box'):
    """Axis-aligned box by centre-bottom, built in world coordinates."""
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx + x, v.co.y * sy + y, v.co.z * sz + z + sz / 2))
    return _put(_mesh(name, bm), mat, bevel)


def rbox(c, dims, euler, mat, bevel=0.006, name='rbox'):
    """A box built in its own local space, then placed: texture follows the part."""
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    for v in bm.verts:
        v.co = Vector((v.co.x * dims[0], v.co.y * dims[1], v.co.z * dims[2]))
    ob = _mesh(name, bm)
    ob.location = c
    ob.rotation_euler = euler
    return _put(ob, mat, bevel)


def beam(p0, p1, t, mat, t2=None, bevel=0.004, name='beam'):
    """A square-section beam between two points; local x runs along it."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = Vector((1, 0, 0)).rotation_difference(d.normalized())
    return rbox((p0 + p1) / 2, (d.length, t, t2 or t), q.to_euler(), mat,
                bevel, name)


def cyl(x, y, z, r1, r2, h, mat, seg=20, bevel=0.0, smooth=True, name='cyl',
        uv=False):
    bm = bmesh.new()
    if uv:
        bm.loops.layers.uv.verify()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r1, radius2=r2, depth=h, calc_uvs=uv)
    for v in bm.verts:
        v.co = Vector((v.co.x + x, v.co.y + y, v.co.z + z + h / 2))
    return _put(_mesh(name, bm), mat, bevel, smooth)


def ellipsoid(x, y, z, rx, ry, rz, mat, seg=20, rings=14, egg=0.0, tilt=None,
              name='ell', bump_free=True):
    """Ellipsoid by centre. egg>0 narrows the top into an egg."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    for v in bm.verts:
        t = v.co.z
        k = 1.0 - egg * t
        v.co = Vector((v.co.x * rx * k, v.co.y * ry * k, v.co.z * rz))
    ob = _mesh(name, bm)
    ob.location = (x, y, z)
    if tilt:
        ob.rotation_euler = tilt
    return _put(ob, mat, 0, True)


def tri_prism(p_left, p_right, p_top, y0, y1, mat, axis='x', bevel=0.004,
              name='gable'):
    """A triangular prism: the triangle lies in (a, z), extruded from y0 to y1.

    axis='x': triangle in x-z, extruded along y. axis='y': in y-z, along x.
    """
    bm = bmesh.new()
    pts = [p_left, p_right, p_top]

    def P(a, z, d):
        return (a, d, z) if axis == 'x' else (d, a, z)
    v0 = [bm.verts.new(P(a, z, y0)) for a, z in pts]
    v1 = [bm.verts.new(P(a, z, y1)) for a, z in pts]
    bm.faces.new(v0)
    bm.faces.new(v1[::-1])
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _put(_mesh(name, bm), mat, bevel)


def blob(x, y, rx, ry, z, h, mat, seed=0, seg=22, bevel=0.0, name='blob'):
    """A flat, irregular patch (worn dirt, a trampled yard) — world coordinates."""
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    bm = bmesh.new()
    top, bot = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        k = 1 + 0.16 * math.sin(3 * a + ph[0]) + 0.08 * math.sin(5 * a + ph[1])
        px, py = x + math.cos(a) * rx * k, y + math.sin(a) * ry * k
        top.append(bm.verts.new((px, py, z + h)))
        bot.append(bm.verts.new((px, py, z)))
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _put(_mesh(name, bm), mat, bevel)


def strands(lst, mat, name='strands'):
    """Many thin boxes (p0, p1, thickness) merged into ONE object — straw, hay."""
    bm = bmesh.new()
    for p0, p1, t in lst:
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        q = Vector((1, 0, 0)).rotation_difference(d.normalized())
        c = (p0 + p1) / 2
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            v.co = c + q @ Vector((v.co.x * d.length, v.co.y * t, v.co.z * t))
        mp = {}
        for v in tmp.verts:
            mp[v] = bm.verts.new(v.co)
        for f in tmp.faces:
            bm.faces.new([mp[v] for v in f.verts])
        tmp.free()
    return _put(_mesh(name, bm), mat, 0)


# ── light & render ─────────────────────────────────────────
def lighting(azimuth=0.0, sun=5.0, sky=1.15, elev=44, swing=-38):
    scene = bpy.context.scene
    bpy.ops.object.light_add(type='SUN')
    s = bpy.context.object
    s.data.energy = sun
    s.data.angle = math.radians(3.2)
    s.data.color = (1.0, 0.86, 0.66)           # golden hour
    s.rotation_euler = (math.radians(elev), 0, math.radians(swing + azimuth))

    w = scene.world or bpy.data.worlds.new('w')
    scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Strength'].default_value = sky
    nt.links.new(bg.outputs[0], out.inputs[0])
    co = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(co.outputs['Object'], sep.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = -0.6
    mr.inputs['From Max'].default_value = 0.9
    nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    e = rp.color_ramp.elements
    e[0].position = 0.0
    e[0].color = hexc('8a7a52')                # warm bounce off the grass
    e[1].position = 1.0
    e[1].color = hexc('9fc4ee')                # open sky
    mid = e.new(0.46)
    mid.color = hexc('f2d2a0')                 # horizon glow
    nt.links.new(mr.outputs['Result'], rp.inputs['Fac'])
    nt.links.new(rp.outputs['Color'], bg.inputs['Color'])


def rim_light(toward, strength=2.0):
    """A cool back light: lifts a silhouette off the ground the way sky does.

    `toward` is the direction FROM the subject TO the light.
    """
    bpy.ops.object.light_add(type='SUN')
    s = bpy.context.object
    s.name = 'rim'
    s.data.energy = strength
    s.data.angle = math.radians(12)
    s.data.color = (0.70, 0.84, 1.0)
    s.rotation_euler = (-Vector(toward)).normalized().to_track_quat('-Z', 'Y').to_euler()
    return s


def setup_render(samples, scale, w, h, grade=True):
    scene = bpy.context.scene
    rb.frame(w, h, scale, 1.25, 0.0)
    scene.render.engine = 'CYCLES'
    cy = scene.cycles
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
    scene.render.film_transparent = True
    scene.render.filter_size = 0.9
    vs = scene.view_settings
    names = vs.bl_rna.properties['view_transform'].enum_items.keys()
    vs.view_transform = 'AgX' if 'AgX' in names else 'Filmic'
    looks = vs.bl_rna.properties['look'].enum_items.keys()
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast',
                 'AgX - Punchy', 'Punchy'):
        if want in looks:
            vs.look = want
            break
    vs.exposure = 0.3


def render(path):
    scene = bpy.context.scene
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    print('wrote', path, scene.render.resolution_x, 'x', scene.render.resolution_y)
