"""Calmer blue-plaster menu backgrounds (user 2026-11-16: "blauer Putz ... zu realistisch, nicht so auffällig").

    blender --background --python tool/blender/menu_bg_plaster.py -- <out_dir>

Same plaster scan as menu_backgrounds.py, but the colour is a flat blue and the
photo only modulates it (tex = share of the texture), the relief is softened,
and two variants are rendered at low resolution for a block look.
"""
import math, os, sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, 'textures', 'white_plaster_rough_01')

def hexrgb(h):
    h = h.lstrip('#')
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4))

# key, flat colour, texture share, normal strength, tiles, pixel width (0 = smooth)
V = [
    ('ruhig',     '#3f6f8c', 0.35, 0.6, 0.7, 0),
    ('leise',     '#2f5a74', 0.20, 0.4, 0.5, 0),
    ('voxel_grob','#3a6a88', 0.50, 0.8, 0.8, 117),
    ('voxel_fein','#3a6a88', 0.45, 0.8, 0.8, 233),
    ('tiefblau',  '#1f3f5c', 0.30, 0.5, 0.7, 0),
    ('hellblau',  '#5f8fb0', 0.30, 0.5, 0.7, 0),
]

def build(flat, tex, nstr, tiles, pw):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    sc.cycles.samples = 32 if not pw else 64
    sc.cycles.use_denoising = not pw
    rx = pw or 1400
    sc.render.resolution_x, sc.render.resolution_y = rx, round(rx * 650 / 1400)
    sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 90
    sc.view_settings.view_transform = 'Standard'
    asp = 1400 / 650
    bpy.ops.mesh.primitive_plane_add(size=1)
    pl = bpy.context.object; pl.scale = (asp * 2, 2, 1)
    m = bpy.data.materials.new('bg'); m.use_nodes = True; nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    uv = nt.nodes.new('ShaderNodeTexCoord'); mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (tiles * asp, tiles, 1)
    nt.links.new(uv.outputs['UV'], mp.inputs['Vector'])
    def tx(name, cs):
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(os.path.join(TEX, name)); t.image.colorspace_settings.name = cs
        nt.links.new(mp.outputs['Vector'], t.inputs['Vector']); return t
    d, r, n = tx('Diffuse.jpg', 'sRGB'), tx('Rough.jpg', 'Non-Color'), tx('nor_gl.jpg', 'Non-Color')
    hs = nt.nodes.new('ShaderNodeHueSaturation')
    hs.inputs['Saturation'].default_value = 0.0; hs.inputs['Value'].default_value = 1.15
    nt.links.new(d.outputs['Color'], hs.inputs['Color'])
    col = (*hexrgb(flat), 1)
    mul = nt.nodes.new('ShaderNodeMix'); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'
    mul.inputs['Factor'].default_value = 1.0
    mul.inputs['B'].default_value = tuple(min(1, c * 1.5) for c in col[:3]) + (1,)
    nt.links.new(hs.outputs['Color'], mul.inputs['A'])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    mix.inputs['Factor'].default_value = tex
    mix.inputs['A'].default_value = col
    nt.links.new(mul.outputs['Result'], mix.inputs['B'])
    nt.links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])
    nt.links.new(r.outputs['Color'], bsdf.inputs['Roughness'])
    nm = nt.nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value = nstr
    nt.links.new(n.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface']); pl.data.materials.append(m)
    cam = bpy.data.cameras.new('c'); cam.type = 'ORTHO'; cam.ortho_scale = 2 * asp
    co = bpy.data.objects.new('c', cam); co.location = (0, 0, 5); sc.collection.objects.link(co); sc.camera = co
    sun = bpy.data.lights.new('s', 'SUN'); sun.energy = 3.0; sun.angle = math.radians(25)
    so = bpy.data.objects.new('s', sun); so.rotation_euler = (math.radians(40), math.radians(-12), math.radians(28))
    sc.collection.objects.link(so)
    w = bpy.data.worlds.new('w'); w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.6, 0.65, 0.75, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.7; sc.world = w

out = sys.argv[sys.argv.index('--') + 1]; os.makedirs(out, exist_ok=True)
for key, flat, tex, nstr, tiles, pw in V:
    build(flat, tex, nstr, tiles, pw)
    bpy.context.scene.render.filepath = os.path.join(out, key + '.jpg')
    bpy.ops.render.render(write_still=True); print('done', key)
