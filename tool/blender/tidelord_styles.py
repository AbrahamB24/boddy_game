"""Ten ways to render the same monster — a style board, not a pipeline.

    blender --background --python tool/blender/tidelord_styles.py -- \
        --style clay --out tool/blender/_out/styles/clay.png [--samples 48]

The model is tidelord_pro.build(); each style changes only materials, a
modifier or two, and how the picture is taken, so the ten results are
comparable like for like. Styles: smooth, lowpoly, fur, clay, vinyl, ink,
crystal, voxel, pixel, flat.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tidelord_pro as tp  # noqa: E402
import tidelord_sprite as sp  # noqa: E402
import pro_kit as K  # noqa: E402

TOON = {'ink', 'pixel', 'flat'}

# which toon palette each of tidelord_pro's materials maps to
TOON_KEY = {
    'sk_top': 'blue', 'sk_head': 'blue', 'sk_flip': 'flip', 'sk_flip_d': 'blue',
    'sk_belly': 'belly', 'sk_cream': 'cream', 'navy': 'navy', 'iris': 'navy',
    'nose': 'navy', 'ivory': 'tusk', 'sk_brow': 'brow', 'ice': 'horn',
}
OUTLINE_OBJECTS = ('body', 'skull', 'fl_near', 'fl_far', 'fl_rear_a', 'fl_rear_b')


def principled(m):
    return m.node_tree.nodes.get('Principled BSDF') or next(
        (n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)


def set_in(b, name, v):
    if name in b.inputs:
        b.inputs[name].default_value = v


def tweak_skin(fn):
    for key in ('sk_top', 'sk_head', 'sk_flip', 'sk_flip_d', 'sk_belly',
                'sk_cream'):
        m = K._mats.get(key)
        b = principled(m) if m else None
        if b:
            fn(m, b)


def flat_colours(pal, rough, coat=0.0, bump=None):
    """Drop the graded fur colour for one flat colour per part."""
    for key, hexv in pal.items():
        m = K._mats.get(key)
        b = principled(m) if m else None
        if not b:
            continue
        for l in list(m.node_tree.links):
            if l.to_socket == b.inputs['Base Color']:
                m.node_tree.links.remove(l)
        b.inputs['Base Color'].default_value = K.hexc(hexv)
        set_in(b, 'Roughness', rough)
        set_in(b, 'Coat Weight', coat)
        set_in(b, 'Sheen Weight', 0.0)
        set_in(b, 'Subsurface Weight', 0.0)
        for n in m.node_tree.nodes:
            if n.type == 'BUMP' and bump is not None:
                n.inputs['Strength'].default_value = bump


CLAY = {'sk_top': '#6f9fbd', 'sk_head': '#79a9c6', 'sk_flip': '#84b1c9',
        'sk_flip_d': '#6f9fbd', 'sk_belly': '#cfdde2', 'sk_cream': '#dccaa8'}
VINYL = {'sk_top': '#0f6fff', 'sk_head': '#2a84ff', 'sk_flip': '#3a93ff',
         'sk_flip_d': '#0f6fff', 'sk_belly': '#a6d2ff', 'sk_cream': '#fff0c4'}


def style_clay(m, b):
    set_in(b, 'Roughness', 0.93)
    set_in(b, 'Coat Weight', 0.0)
    set_in(b, 'Sheen Weight', 0.0)
    set_in(b, 'Specular IOR Level', 0.15)
    set_in(b, 'Subsurface Weight', 0.25)
    for n in m.node_tree.nodes:
        if n.type == 'BUMP':
            n.inputs['Strength'].default_value = 1.4
        if n.type == 'TEX_NOISE' and n.inputs['Scale'].default_value > 100:
            n.inputs['Scale'].default_value = 55.0


def style_vinyl(m, b):
    set_in(b, 'Roughness', 0.10)
    set_in(b, 'Coat Weight', 1.0)
    set_in(b, 'Coat Roughness', 0.03)
    set_in(b, 'Sheen Weight', 0.0)
    set_in(b, 'Subsurface Weight', 0.0)
    set_in(b, 'Specular IOR Level', 0.9)
    for n in m.node_tree.nodes:
        if n.type == 'BUMP':
            n.inputs['Strength'].default_value = 0.0


def style_crystal(m, b):
    set_in(b, 'Transmission Weight', 1.0)
    set_in(b, 'Roughness', 0.05)
    set_in(b, 'IOR', 1.45)
    set_in(b, 'Coat Weight', 0.0)
    set_in(b, 'Subsurface Weight', 0.0)
    set_in(b, 'Emission Color', K.hexc('4aa8f2'))
    set_in(b, 'Emission Strength', 0.25)
    for n in m.node_tree.nodes:
        if n.type == 'BUMP':
            n.inputs['Strength'].default_value = 0.0


def to_toon(light, outline=0.0, flat=False):
    if flat:
        for k, cols in sp.PAL.items():
            sp.PAL[k] = [cols[1], cols[1], cols[2], cols[3], cols[3]]
    ink = None
    if outline:
        # Cycles has no back-face culling, so fake it: show the shell only where
        # its (flipped) normal faces the lens, i.e. the far side that peeks out
        # around the silhouette; transparent everywhere else.
        ink = bpy.data.materials.new('ink')
        ink.use_nodes = True
        nt = ink.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        mix = nt.nodes.new('ShaderNodeMixShader')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Color'].default_value = K.hexc('0e1c3a')
        tr = nt.nodes.new('ShaderNodeBsdfTransparent')
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        nt.links.new(geo.outputs['Backfacing'], mix.inputs[0])
        nt.links.new(em.outputs[0], mix.inputs[1])
        nt.links.new(tr.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs['Surface'])
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or getattr(ob, 'is_shadow_catcher', False):
            continue
        for i, slot in enumerate(ob.material_slots):
            key = TOON_KEY.get(slot.material.name if slot.material else '')
            if key:
                ob.material_slots[i].material = sp.toon(key, light)
        if outline and ob.name.split('.')[0] in OUTLINE_OBJECTS:
            ob.data.materials.append(ink)
            md = ob.modifiers.new('outline', 'SOLIDIFY')
            md.thickness = outline
            md.offset = 1.0
            md.use_flip_normals = True
            md.use_rim = False
            md.material_offset = len(ob.data.materials) - 1


def style_voxel():
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.name.split('.')[0] in OUTLINE_OBJECTS:
            md = ob.modifiers.new('voxel', 'REMESH')
            md.mode = 'BLOCKS'
            md.octree_depth = 5
            md.scale = 0.95
            md.use_smooth_shade = False
            md.use_remove_disconnected = False


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--style', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    args = ap.parse_args(argv)
    st = args.style
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    target = Vector((-0.05, 0, 0.25))
    cam_loc = Vector((0.80, 1.0, 0.38)) * 4.0 + target
    light = sp.key_light(cam_loc, target)

    if st == 'lowpoly':
        sp.build(light)
    else:
        tp.build(yaw=0.0, furry=(st == 'fur'))
        if st == 'fur':
            for ps in bpy.data.particles:
                ps.root_radius *= 3.2
                ps.hair_length *= 1.5
        if st == 'clay':
            flat_colours(CLAY, 1.0, bump=1.6)
            tweak_skin(style_clay)
        elif st == 'vinyl':
            flat_colours(VINYL, 0.08, coat=1.0, bump=0.0)
            tweak_skin(style_vinyl)
        elif st == 'crystal':
            tweak_skin(style_crystal)
        elif st == 'voxel':
            flat_colours({'sk_top': '#3b8fe0', 'sk_head': '#4a9cec', 'sk_flip': '#5aa8f0', 'sk_flip_d': '#3b8fe0', 'sk_belly': '#bfe0f6', 'sk_cream': '#e6d6b0'}, 1.0, bump=0.0)
            style_voxel()
        elif st == 'ink':
            to_toon(light, outline=0.012)
        elif st == 'flat':
            to_toon(light, outline=0.02, flat=True)
        elif st == 'pixel':
            to_toon(light)

    if st not in TOON and st != 'lowpoly':
        K.lighting(sky=0.85, sun=5.5)
        cdir = (Vector(target) - cam_loc).normalized()
        right = cdir.cross(Vector((0, 0, 1))).normalized()
        K.rim_light((-cdir * 0.7 + right * 0.45 + Vector((0, 0, 0.6))).normalized())
    sp.fit_camera(cam_loc, target)

    scene.render.engine = 'CYCLES'
    cy = scene.cycles
    cy.device = 'CPU'
    cy.samples = 1 if st == 'pixel' else args.samples
    cy.use_denoising = st not in TOON and st != 'lowpoly'
    cy.max_bounces = 8 if st == 'crystal' else 5
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = True
    scene.render.filter_size = 0.0 if st == 'pixel' else 0.9
    vs = scene.view_settings
    if st in TOON or st == 'lowpoly':
        vs.view_transform = 'Standard'
        vs.look = 'None'
    else:
        vs.view_transform = 'AgX'
        for want in ('AgX - Medium High Contrast', 'Medium High Contrast'):
            if want in vs.bl_rna.properties['look'].enum_items.keys():
                vs.look = want
                break
        vs.exposure = 0.55
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print('wrote', args.out)


if __name__ == '__main__':
    main()
