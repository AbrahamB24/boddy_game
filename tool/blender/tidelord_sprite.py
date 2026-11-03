"""Tidelord stage 0 as a 3D model that renders 1:1 like its sprite.

    blender --background --python tool/blender/tidelord_sprite.py -- \
        --out docs/renders/tidelord_sprite.png [--overlay sprite.png]

The game's sprite (creature-images/tidelord_0.png) is a low-poly seal painted
in flat facets: every facet is one of four or five blues chosen by which way it
faces the light. This script does the same on purpose. The model is faceted
(icospheres, flat shading, no bevel, no relief), and every part gets a
"toon" emission material: colour = ramp(dot(facet normal, key light)), with
hard steps and no lighting maths in between. What the render shows is the
palette, not a simulation of light, so the colours cannot drift.

The camera is orthographic and fitted so the model's silhouette lands in the
same box of the 1654 x 1654 canvas as the sprite's (x 321..1407, y 582..1428).
--overlay writes a 50/50 blend of the render over a given image for checking.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

CANVAS = 1654
BOX = (321, 1407, 582, 1428)            # the sprite's silhouette, in pixels


def hexc(h, a=1.0):
    h = h.lstrip('#')
    f = lambda c: (c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(int(h[0:2], 16) / 255), f(int(h[2:4], 16) / 255),
            f(int(h[4:6], 16) / 255), a)


# palettes, darkest facet first
PAL = {
    'blue':   ['#3589c4', '#55abd6', '#77c4de', '#a9dcec', '#e4f3f8'],
    'belly':  ['#7cbcdc', '#a8d6ea', '#c6e5f0', '#d9edf3', '#ecf6f9'],
    'flip':   ['#4a9fd0', '#69b9dc', '#85cbe2', '#b4dfec', '#d6eef5'],
    'horn':   ['#7cc3e4', '#9fd6ec', '#bce5f1', '#d6f0f8', '#f1fafc'],
    'cream':  ['#a29fa6', '#c4c0c0', '#e0ddd0', '#ecebdf', '#f6f5ec'],
    'navy':   ['#0c1535', '#121e47', '#172552', '#27407a', '#3a5aa0'],
    'brow':   ['#2a4f8a', '#2f5a9c', '#3b6cb0', '#4c80c2', '#5b90d0'],
    'tusk':   ['#c9c6bb', '#dcdace', '#ecebe0', '#f6f5ee', '#ffffff'],
}
_mats = {}
STEPS = (0.0, 0.36, 0.56, 0.78, 0.93)


def toon(key, light):
    if key in _mats:
        return _mats[key]
    cols = PAL[key]
    m = bpy.data.materials.new('toon_' + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    dot = nt.nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = tuple(light)
    nt.links.new(geo.outputs['Normal'], dot.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = -1.0
    mr.inputs['From Max'].default_value = 1.0
    nt.links.new(dot.outputs['Value'], mr.inputs['Value'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    rp.color_ramp.interpolation = 'CONSTANT'
    e = rp.color_ramp.elements
    e[0].position = STEPS[0]
    e[0].color = hexc(cols[0])
    e[1].position = STEPS[1]
    e[1].color = hexc(cols[1])
    for pos, c in zip(STEPS[2:], cols[2:]):
        n = e.new(pos)
        n.color = hexc(c)
    nt.links.new(mr.outputs['Result'], rp.inputs['Fac'])
    # white hit-flash: a mix toward white, driven per frame by the animator
    fl = nt.nodes.new('ShaderNodeMix')
    fl.name = 'flash'
    fl.data_type = 'RGBA'
    fl.inputs[0].default_value = 0.0
    fl.inputs[7].default_value = (1, 1, 1, 1)
    nt.links.new(rp.outputs['Color'], fl.inputs[6])
    nt.links.new(fl.outputs[2], em.inputs['Color'])
    _mats[key] = m
    return m


def flat_emit(key, rgb):
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = hexc(rgb)
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    _mats[key] = m
    return m


# ── low-poly parts, all flat-shaded ──────────────────────────
def _obj(name, bm, mat, loc, rot, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    ob.parent = parent
    return ob


def facet(name, r, mat, loc=(0, 0, 0), rot=(0, 0, 0), sub=2, parent=None,
          squash=None, tweak=None):
    """A faceted ellipsoid (icosphere). r = (rx, ry, rz)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    for v in bm.verts:
        c = Vector(v.co)
        if tweak:
            c = tweak(c)
        v.co = Vector((c.x * r[0], c.y * r[1], c.z * r[2]))
    return _obj(name, bm, mat, loc, rot, parent)


def paddle(name, L, W, T, mat, loc, rot, parent=None, rows=7, cols=10):
    """A faceted flipper: narrow at the root, fanned and rounded at the tip."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=cols, v_segments=rows, radius=1.0)
    for v in bm.verts:
        t = (v.co.x + 1) / 2
        fan = 0.32 + 0.68 * t ** 1.1
        v.co = Vector((t * L, v.co.y * W * fan, v.co.z * T * (1 - 0.5 * t)))
    return _obj(name, bm, mat, loc, rot, parent)


def cone(name, r1, r2, h, mat, loc, rot, sides=5, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides,
                          radius1=r1, radius2=r2, depth=h)
    for v in bm.verts:
        v.co.z += h / 2
    return _obj(name, bm, mat, loc, rot, parent)


def build(light):
    T = lambda k: toon(k, light)
    root = bpy.data.objects.new('seal', None)
    bpy.context.scene.collection.objects.link(root)

    # body, belly patch, tail
    facet('body', (0.38, 0.35, 0.31), T('blue'), (-0.10, 0, 0.26), (0, 0, 0),
          parent=root)
    facet('belly', (0.22, 0.25, 0.16), T('belly'), (0.24, 0.04, 0.10),
          (0, 0, 20), parent=root)
    facet('tail', (0.24, 0.18, 0.16), T('blue'), (-0.40, 0, 0.20), (0, -8, 0),
          parent=root)
    # rear flippers = the heart-shaped fluke: one big lobe and a smaller,
    # rounder one behind it, both low
    paddle('fl_rear_near', 0.40, 0.22, 0.07, T('flip'), (-0.50, 0.05, 0.22),
           (8, -10, -168), parent=root)
    facet('fl_rear_far', (0.13, 0.10, 0.13), T('flip'), (-0.62, -0.10, 0.35),
          (0, 0, 10), parent=root)
    # front flippers
    near = paddle('fl_near', 0.50, 0.29, 0.09, T('flip'), (0.22, 0.24, 0.09),
                  (6, 8, 78), parent=root)
    for k in (-1, 0, 1):
        facet(f'fl_ln{k}', (0.11, 0.013, 0.012), T('blue'),
              (0.36, k * 0.065, 0.06), (0, 0, 0), sub=1, parent=near)
    paddle('fl_far', 0.28, 0.17, 0.08, T('flip'), (0.30, -0.20, 0.08),
           (0, 0, -20), parent=root)
    # head, big, turned to the camera
    head = bpy.data.objects.new('head', None)
    bpy.context.scene.collection.objects.link(head)
    head.location = (0.30, 0.0, 0.43)
    head.rotation_euler = Euler((0, 0, math.radians(32)), 'XYZ')
    head.scale = (1.12, 1.12, 1.12)
    head.parent = root
    facet('skull', (0.30, 0.31, 0.28), T('blue'), (0, 0, 0), parent=head)
    facet('face', (0.17, 0.26, 0.19), T('belly'), (0.15, 0, 0.0), parent=head)
    facet('muzzle', (0.14, 0.18, 0.12), T('cream'), (0.25, 0, -0.10),
          parent=head)
    facet('chin', (0.10, 0.13, 0.06), T('cream'), (0.22, 0, -0.19),
          parent=head)
    facet('nose', (0.034, 0.046, 0.026), T('navy'), (0.385, 0, 0.0), sub=1,
          parent=head)
    cream_dot = flat_emit('dot', '#8a8791')
    for sg in (-1, 1):
        facet('eye', (0.058, 0.060, 0.076), T('navy'), (0.255, sg * 0.125, 0.045),
              (0, 0, sg * 10), sub=1, parent=head)
        facet('catch', (0.026, 0.026, 0.026), flat_emit('white', '#ffffff'),
              (0.310, sg * 0.125 - sg * 0.022, 0.092), sub=1, parent=head)
        facet('brow', (0.05, 0.016, 0.010), T('brow'), (0.21, sg * 0.13, 0.145),
              (0, 0, -sg * 18), sub=1, parent=head)
        cone('tusk', 0.017, 0.004, 0.085, T('tusk'), (0.31, sg * 0.06, -0.15),
             (180, 0, 0), sides=5, parent=head)
        for i in range(4):
            facet('dot', (0.008, 0.008, 0.008), cream_dot,
                  (0.34 + 0.005 * (i % 2), sg * (0.075 + 0.025 * i),
                   -0.09 + 0.014 * i), sub=0, parent=head)
    # the horn
    cone('horn', 0.075, 0.006, 0.19, T('horn'), (0.10, -0.07, 0.18), (6, -14, 0),
         sides=5, parent=head)
    return root


def key_light(cam_loc, target):
    """Key direction (toward the light) in the camera's frame, as a world
    vector: up-left-front of the lens, the way the sprite is lit."""
    q = (Vector(target) - Vector(cam_loc)).normalized()
    up = Vector((0, 0, 1))
    right = q.cross(up).normalized()
    upc = right.cross(q).normalized()
    return (-right * 0.55 + upc * 0.75 - q * 0.45).normalized()


def fit_camera(cam_loc, target, ortho_pad=1.0):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.new('cam', cam_data)
    scene.collection.objects.link(cam)
    cam.location = cam_loc
    d = (Vector(target) - Vector(cam_loc)).normalized()
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    xs, ys = [], []
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or getattr(ob, 'is_shadow_catcher', False):
            continue
        for v in ob.data.vertices:
            p = inv @ (ob.matrix_world @ v.co)
            xs.append(p.x)
            ys.append(p.y)
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    bw = (BOX[1] - BOX[0]) / CANVAS
    scale = (maxx - minx) / bw                      # ortho_scale = frame width
    cam_data.ortho_scale = scale
    # where the subject's centre should land, as a fraction of the frame
    fx = (BOX[0] + BOX[1]) / 2 / CANVAS
    fy = (BOX[2] + BOX[3]) / 2 / CANVAS
    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    # move the camera over the subject, then shift to the target fraction
    cam.location = cam.location + cam.matrix_world.to_quaternion() @ Vector((cx, cy, 0))
    cam_data.shift_x = 0.5 - fx
    cam_data.shift_y = fy - 0.5
    return cam


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='docs/renders/tidelord_sprite.png')
    ap.add_argument('--overlay')
    ap.add_argument('--samples', type=int, default=24)
    ap.add_argument('--blend')
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    cam_loc = Vector((0.80, 1.0, 0.38)) * 4.0 + Vector((-0.05, 0, 0.25))
    target = Vector((-0.05, 0, 0.25))
    light = key_light(cam_loc, target)
    build(light)
    fit_camera(cam_loc, target)

    scene.render.engine = 'CYCLES'
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = False
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = CANVAS
    scene.render.resolution_y = CANVAS
    scene.render.film_transparent = True
    scene.render.filter_size = 0.8
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(args.out)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    bpy.ops.render.render(write_still=True)
    print('wrote', args.out)


if __name__ == '__main__':
    main()
