"""Twenty menu backgrounds from the Poly Haven materials — real renders to choose from.

    blender --background --python tool/blender/menu_backgrounds.py -- <out_dir> [key ...]

User 2026-11-16: "gib mir 20 komplett neue Hintergründe ... für menüs wie
monsterscreen oder breeding". A flat material plane lit at a grazing angle so
the normal map reads, tinted per variant. 1400x650 (the app's 932x430 at ~1.5x).
Textures come from tool/blender/textures (fetch_textures.py).
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, 'textures')

# key, texture folder, tiles across, (hue, saturation, value), title, blurb
V = [
    ('stein',      'old_stone_wall',        1.0, (0.5, 1.0, 0.85), 'Alte Steinmauer',    'Grauer Naturstein, tiefe Fugen.'),
    ('stein_blau', 'old_stone_wall',        1.0, (0.5, 0.0, 1.5, (0.45, 0.65, 1.15)), 'Blaue Steinmauer',   'Dieselbe Mauer in das Blau des Spiels getaucht.'),
    ('holz_dunkel','dark_wood',             2.0, (0.5, 1.0, 0.9),  'Dunkles Holz',       'Tiefbraune Bretter, feine Maserung.'),
    ('bohlen',     'weathered_planks',      0.7, (0.5, 1.0, 0.95), 'Verwitterte Bohlen', 'Silbergraues Holz mit Rissen.'),
    ('bohlen_blau','weathered_planks',      2.0, (0.5, 0.0, 1.5, (0.5, 0.7, 1.1)), 'Blaue Bohlen',       'Bohlen mit blauer Lasur.'),
    ('putz',       'white_plaster_rough_01',2.0, (0.5, 1.0, 0.85), 'Weißer Putz',        'Rauer Kalkputz, wie die Hauswände.'),
    ('putz_blau',  'white_plaster_rough_01',2.0, (0.5, 0.0, 1.0, (0.55, 0.75, 1.15)), 'Blauer Putz',        'Kalkputz in Spielblau.'),
    ('putz_ziegel','rough_plaster_brick_02',2.5, (0.5, 1.0, 0.85), 'Putz mit Ziegel',    'Abgeplatzter Putz, Ziegel darunter.'),
    ('moosziegel', 'mossy_brick',           0.9, (0.5, 1.0, 0.85), 'Moosziegel',         'Alte Ziegel, grün überwachsen.'),
    ('fels',       'rock_wall_08',          0.7, (0.5, 1.0, 0.85), 'Felswand',           'Geschichteter Fels, grob.'),
    ('fels_violett','rock_wall_08',         2.0, (0.5, 0.0, 1.5, (0.8, 0.55, 1.1)), 'Violetter Fels',     'Dieselbe Wand im Kristallhöhlen-Licht.'),
    ('dach',       'roof_tiles_14',         1.0, (0.5, 1.0, 0.8),  'Dachziegel',         'Dunkle Schindeln, wie die Dächer der Gebäude.'),
    ('dach_blau',  'roof_tiles_14',         1.0, (0.5, 0.0, 1.7, (0.5, 0.65, 1.1)), 'Blauer Schiefer',    'Kühle Schieferziegel.'),
    ('ton',        'clay_roof_tiles_02',    1.0, (0.5, 1.0, 0.85), 'Tonziegel',          'Terrakotta, warm.'),
    ('stroh',      'thatch_roof_angled',    0.7, (0.5, 1.0, 0.85), 'Strohdach',          'Goldenes Stroh, schräg gelegt.'),
    ('schilf',     'reed_roof_03',          0.7, (0.5, 1.0, 0.8),  'Schilfdach',         'Dichtes Schilf, ruhig.'),
    ('pflaster',   'grassy_cobblestone',    0.9, (0.5, 1.0, 0.85), 'Pflaster mit Gras',  'Kopfstein, Gras in den Fugen.'),
    ('erde',       'park_dirt',             0.7, (0.5, 1.0, 0.8),  'Erdboden',           'Festgetretene Erde.'),
    ('laub',       'leafy_grass',           0.7, (0.5, 1.0, 0.75), 'Laubgrund',          'Gras und Blätter, dunkel.'),
    ('holz_teal',  'dark_wood',             0.7, (0.5, 0.0, 1.5, (0.45, 0.95, 0.9)), 'Türkises Holz',      'Dunkles Holz mit Petrol-Lasur.'),
]


def img(folder, name):
    p = os.path.join(TEX, folder, name)
    return bpy.data.images.load(p, check_existing=True)


def build(folder, tiles, hsv):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 40
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1400, 650
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = 88
    sc.view_settings.view_transform = 'Standard'

    asp = 1400 / 650
    bpy.ops.mesh.primitive_plane_add(size=1)
    pl = bpy.context.object
    pl.scale = (asp * 2, 2, 1)
    # UVs 0..1 across; mapping scales to the tile count.
    m = bpy.data.materials.new('bg')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    uv = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (tiles * asp, tiles, 1)

    def tex(name, cs):
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = img(folder, name)
        t.image.colorspace_settings.name = cs
        nt.links.new(mp.outputs['Vector'], t.inputs['Vector'])
        return t

    nt.links.new(uv.outputs['UV'], mp.inputs['Vector'])
    d = tex('Diffuse.jpg', 'sRGB')
    r = tex('Rough.jpg', 'Non-Color')
    n = tex('nor_gl.jpg', 'Non-Color')
    hs = nt.nodes.new('ShaderNodeHueSaturation')
    hs.inputs['Hue'].default_value, hs.inputs['Saturation'].default_value, hs.inputs['Value'].default_value = hsv[:3]
    nt.links.new(d.outputs['Color'], hs.inputs['Color'])
    last = hs.outputs['Color']
    if len(hsv) > 3:
        mx = nt.nodes.new('ShaderNodeMix')
        mx.data_type = 'RGBA'
        mx.blend_type = 'MULTIPLY'
        mx.inputs['Factor'].default_value = 1.0
        mx.inputs['B'].default_value = (*hsv[3], 1)
        nt.links.new(hs.outputs['Color'], mx.inputs['A'])
        last = mx.outputs['Result']
    nt.links.new(last, bsdf.inputs['Base Color'])
    nt.links.new(r.outputs['Color'], bsdf.inputs['Roughness'])
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nm.inputs['Strength'].default_value = 1.6
    nt.links.new(n.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    pl.data.materials.append(m)

    cam = bpy.data.cameras.new('c')
    cam.type = 'ORTHO'
    cam.ortho_scale = 2 * asp * 1.0
    co = bpy.data.objects.new('c', cam)
    co.location = (0, 0, 5)
    sc.collection.objects.link(co)
    sc.camera = co

    sun = bpy.data.lights.new('s', 'SUN')
    sun.energy = 3.2
    sun.angle = math.radians(6)
    so = bpy.data.objects.new('s', sun)
    so.rotation_euler = (math.radians(52), math.radians(-12), math.radians(28))
    sc.collection.objects.link(so)

    w = bpy.data.worlds.new('w')
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.6, 0.7, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.55
    sc.world = w


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = args[0]
    keys = args[1:]
    os.makedirs(out, exist_ok=True)
    for key, folder, tiles, hsv, _t, _b in V:
        if keys and key not in keys:
            continue
        build(folder, tiles, hsv)
        bpy.context.scene.render.filepath = os.path.join(out, key + '.jpg')
        bpy.ops.render.render(write_still=True)
        print('done', key)


main()
