"""A painted look from 3D models (user 2026-11-05: "alles wirkt sehr steril. Kannst
du den gezeichneten Look mit den 3D Modellen simulieren? Bitte mit der Kiste
testen. Diese soll von der Seite sein und einen runden Deckel wie beim
Referenzbild").

    blender --background --python tool/blender/make_paint.py -- chest [--px 1024] [--samples 96]

How the drawn look is faked:
  * materials with hand-painted variation: noise-driven colour drift, stretched
    "brush" bump, lit edges (Bevel node) and dark crevices (ambient occlusion);
  * warm key light, cool rim light, a small blue light where the lock glows;
  * Freestyle ink lines (dark brown, a little thicker on silhouettes);
  * the compositor's anisotropic Kuwahara filter, which turns surfaces into
    brush strokes, and a touch of canvas grain.
Writes docs/renders/paint/<name>.png.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import icon_lib as L  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import make_ui as U  # noqa: E402


def hexc(h, a=1.0):
    return K.hexc(h, a)


def paint_mat(name, base, base2=None, rough=0.7, metal=0.0, streak=0.5, edge='#fff0c8', edge_k=0.35,
              ao_k=0.55, scale=6.0, emit=None, emit_k=0.0):
    """A painted surface: two tones drifting through noise, brush streaks in the
    relief, lit edges and dark crevices."""
    base2 = base2 or base
    m = bpy.data.materials.new('p_' + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    co = nt.nodes.new('ShaderNodeTexCoord')
    # colour drift
    n1 = nt.nodes.new('ShaderNodeTexNoise')
    n1.inputs['Scale'].default_value = scale
    n1.inputs['Detail'].default_value = 4.0
    nt.links.new(co.outputs['Object'], n1.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = hexc(base)
    ramp.color_ramp.elements[1].color = hexc(base2)
    nt.links.new(n1.outputs['Fac'], ramp.inputs['Fac'])
    # brush streaks: noise stretched along Z
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (14.0, 14.0, 2.5)
    nt.links.new(co.outputs['Object'], mp.inputs['Vector'])
    n2 = nt.nodes.new('ShaderNodeTexNoise')
    n2.inputs['Scale'].default_value = 3.0
    n2.inputs['Detail'].default_value = 3.0
    nt.links.new(mp.outputs['Vector'], n2.inputs['Vector'])
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = streak
    bump.inputs['Distance'].default_value = 0.01
    nt.links.new(n2.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    # lit edges: where the bevelled normal parts from the real one
    bv = nt.nodes.new('ShaderNodeBevel')
    bv.inputs['Radius'].default_value = 0.035
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    dot = nt.nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    nt.links.new(bv.outputs['Normal'], dot.inputs[0])
    nt.links.new(geo.outputs['Normal'], dot.inputs[1])
    er = nt.nodes.new('ShaderNodeMapRange')
    er.inputs['From Min'].default_value = 0.985
    er.inputs['From Max'].default_value = 0.80
    nt.links.new(dot.outputs['Value'], er.inputs['Value'])
    mix1 = nt.nodes.new('ShaderNodeMix')
    mix1.data_type = 'RGBA'
    mix1.inputs[7].default_value = hexc(edge)
    nt.links.new(er.outputs['Result'], mix1.inputs[0])
    nt.links.new(ramp.outputs['Color'], mix1.inputs[6])
    mul = nt.nodes.new('ShaderNodeMath')
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = edge_k
    nt.links.new(er.outputs['Result'], mul.inputs[0])
    nt.links.new(mul.outputs[0], mix1.inputs[0])
    # dark crevices
    ao = nt.nodes.new('ShaderNodeAmbientOcclusion')
    ao.inputs['Distance'].default_value = 0.25
    nt.links.new(mix1.outputs[2], ao.inputs['Color'])
    mix2 = nt.nodes.new('ShaderNodeMix')
    mix2.data_type = 'RGBA'
    mix2.inputs[6].default_value = (0.05, 0.03, 0.02, 1)
    nt.links.new(ao.outputs['Color'], mix2.inputs[7])
    mix2.inputs[0].default_value = 1.0
    # blend: AO output already multiplies colour; keep a floor so shadows stay warm
    nt.links.new(ao.outputs['Color'], bsdf.inputs['Base Color'])
    if emit:
        bsdf.inputs['Emission Color'].default_value = hexc(emit)
        bsdf.inputs['Emission Strength'].default_value = emit_k
    return m


def lights():
    scene = bpy.context.scene
    bpy.ops.object.light_add(type='SUN')
    key = bpy.context.object
    key.data.energy = 5.0
    key.data.angle = math.radians(18)
    key.data.color = (1.0, 0.84, 0.62)
    key.rotation_euler = (math.radians(52), 0, math.radians(-32))
    bpy.ops.object.light_add(type='SUN')
    rim = bpy.context.object
    rim.data.energy = 4.5
    rim.data.color = (0.55, 0.75, 1.0)
    rim.rotation_euler = (math.radians(70), 0, math.radians(150))
    w = scene.world or bpy.data.worlds.new('w')
    scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Color'].default_value = (0.42, 0.46, 0.55, 1)
    bg.inputs['Strength'].default_value = 0.55
    nt.links.new(bg.outputs[0], out.inputs[0])


def ink(thickness=2.4):
    sc = bpy.context.scene
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = 'ABSOLUTE'
    sc.render.line_thickness = thickness
    vl = bpy.context.view_layer
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    ls = fs.linesets.new('ink')
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_by_visibility = True
    st = ls.linestyle
    st.color = (0.05, 0.03, 0.02)
    st.thickness = thickness
    fs.crease_angle = math.radians(38)
    fs.as_render_pass = True          # keep the lines out of the painted pass; laid on top later


def compositor(size=5):
    """Brush strokes (Kuwahara), a soft bloom on the glowing parts, then the ink
    lines laid over the painted picture."""
    sc = bpy.context.scene
    g = bpy.data.node_groups.new('paint', 'CompositorNodeTree')
    g.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
    rl = g.nodes.new('CompositorNodeRLayers')
    ku = g.nodes.new('CompositorNodeKuwahara')
    try:
        ku.variation = 'ANISOTROPIC'
    except Exception:
        pass
    for k, v in (('Size', size), ('Sharpness', 0.6), ('Eccentricity', 0.9)):
        if k in ku.inputs:
            ku.inputs[k].default_value = v
    gl = g.nodes.new('CompositorNodeGlare')
    for k, v in (('Type', 'Bloom'), ('Quality', 'High')):
        try:
            gl.inputs[k].default_value = v
        except Exception as e:
            print('GLARE SET FAIL', k, e)
    for k, v in (('Threshold', 1.0), ('Strength', 0.9), ('Size', 0.6), ('Saturation', 1.0)):
        if k in gl.inputs:
            gl.inputs[k].default_value = v
    ao = g.nodes.new('CompositorNodeAlphaOver')
    go = g.nodes.new('NodeGroupOutput')
    g.links.new(rl.outputs['Image'], ku.inputs['Image'])
    g.links.new(ku.outputs['Image'], gl.inputs['Image'])
    print('ALPHAOVER inputs', [i.name for i in ao.inputs], 'RL outputs', [o.name for o in rl.outputs], 'GLARE', [i.name for i in gl.inputs])
    g.links.new(gl.outputs['Image'], ao.inputs['Background'])
    if 'Freestyle' in rl.outputs:
        g.links.new(rl.outputs['Freestyle'], ao.inputs['Foreground'])
    g.links.new(ao.outputs['Image'], go.inputs['Image'])
    sc.compositing_node_group = g
    sc.render.use_compositing = True


def chest():
    """A treasure chest seen from the side, with a round lid and a blue lock."""
    wood = paint_mat('wood', '#3a2114', '#2a170d', rough=0.75, streak=0.8, scale=5.0, edge='#c98a52', edge_k=0.45)
    wood_lt = paint_mat('wood_lt', '#55341e', '#40260f', rough=0.7, streak=0.35, scale=4.0, edge='#e0a468', edge_k=0.5)
    steel = paint_mat('steel', '#46567a', '#34425f', rough=0.38, metal=1.0, streak=0.3, edge='#bcd8ff', edge_k=0.7)
    steel_dk = paint_mat('steel_dk', '#27324a', '#1b2438', rough=0.5, metal=1.0, streak=0.3, edge='#7fa6e0', edge_k=0.6)
    rivet = paint_mat('rivet', '#c89a52', '#a87a38', rough=0.35, metal=1.0, streak=0.0)
    glow = L.plain('glow', '#4fb8ff', rough=0.3, bump=0, vary=0.0, emit='#2f9cff', emit_strength=14.0)
    W, D, H = 1.5, 0.95, 0.62
    # body
    L.box(0, 0, H / 2, W, D, H, wood, bev=0.05)
    for z in (H * 0.33, H * 0.66):
        L.box(0, -D / 2 - 0.004, z, W - 0.06, 0.015, 0.012, 'black', bev=0.0)
    # lid: a cylinder lying along X, only its upper half shows
    bpy.ops.mesh.primitive_cylinder_add(radius=D / 2, depth=W, location=(0, 0, H), vertices=64, rotation=(0, math.pi / 2, 0))
    lid = bpy.context.object
    lid.scale = (0.62, 1.0, 1.0)
    for p in lid.data.polygons:
        p.use_smooth = True
    lid.data.materials.append(wood_lt)
    # steel bands round the body and over the lid
    for x in (-0.52, 0.0, 0.52):
        L.box(x, 0, H / 2, 0.14, D + 0.04, H + 0.02, steel, bev=0.02)
        bpy.ops.mesh.primitive_cylinder_add(radius=D / 2 + 0.02, depth=0.14, location=(x, 0, H), vertices=64, rotation=(0, math.pi / 2, 0))
        b = bpy.context.object
        b.scale = (0.62, 1.0, 1.0)
        for p in b.data.polygons:
            p.use_smooth = True
        b.data.materials.append(steel)
        for z in (0.08, H - 0.06):
            for s in (-1, 1):
                L.ball(x, s * (D / 2 + 0.03), z, 0.032, 0.02, 0.032, rivet, seg=10)
    # a lower rim and corner plates
    L.box(0, 0, 0.05, W + 0.05, D + 0.05, 0.1, steel_dk, bev=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            L.box(sx * (W / 2 - 0.02), sy * (D / 2 - 0.02), H * 0.5, 0.1, 0.1, H + 0.04, steel_dk, bev=0.02)
    # the lock, front and centre
    L.box(0, -D / 2 - 0.07, H - 0.12, 0.2, 0.08, 0.26, steel_dk, bev=0.025)
    L.box(0, -D / 2 - 0.13, H - 0.12, 0.1, 0.03, 0.14, glow, bev=0.02)
    L.ball(0, -D / 2 - 0.14, H - 0.12, 0.034, 0.02, 0.05, glow, seg=14)
    # side handles
    for sx in (-1, 1):
        L.ring(sx * (W / 2 + 0.06), 0, H * 0.6, 0.12, 0.022, steel, axis='x')
    # a small blue light where the lock burns
    bpy.ops.object.light_add(type='POINT', location=(0, -D / 2 - 0.35, H - 0.1))
    pl = bpy.context.object
    pl.data.energy = 18
    pl.data.color = (0.45, 0.8, 1.0)
    pl.data.shadow_soft_size = 0.2


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('what', nargs='?', default='chest')
    ap.add_argument('--px', type=int, default=1024)
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--yaw', type=float, default=-48.0)
    ap.add_argument('--pitch', type=float, default=16.0)
    ap.add_argument('--kuwahara', type=int, default=6)
    args = ap.parse_args(argv)
    rb.clear()
    K._mats.clear()
    before = L.snapshot()
    chest()
    objs = L.new_since(before)
    # turn the chest to a side / three-quarter view
    root = bpy.data.objects.new('turn', None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        o.parent = root
    root.rotation_euler = (0, 0, math.radians(args.yaw))
    bpy.context.view_layer.update()
    lights()
    L.fit_camera(objs, args.pitch, margin=1.12)
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = args.px
    U.cycles(args.samples)
    ink(3.4 * args.px / 1024)
    compositor(args.kuwahara)
    out = os.path.join(ROOT, 'docs', 'renders', 'paint', args.what + '.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    K.render(out)


if __name__ == '__main__':
    main()
