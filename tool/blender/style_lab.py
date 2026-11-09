"""Style lab: the game's REAL buildings, ground and props rendered in several looks.

    blender --background --python tool/blender/style_lab.py -- \
        --style 1 --what small_house,tile,tree_conifer --out C:/tmp/lab --samples 24

Nothing here touches the shipped assets or the Dart code. It reuses the real
pipeline (buildings/<id>.py, fw_kit, pro_kit, voxelizer, terrain_voxel) and only
changes what a STYLE can change:

  * voxel size            (voxelizer at fw_kit.VOX * style.vox)
  * material mode         ('pbr' = the shipped photo textures, 'flat' = one
                           colour per material, colour-graded by the style)
  * colour transform      (saturation / value / hue, hue remap, palette snap)
  * light rig             (sun colour, strength, height, sky colours)
  * view transform

Post effects that Blender is not needed for (outline, pixel grid, palette,
dither) live in style_post.py.
"""
import colorsys
import importlib
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fw_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import make_building as mb  # noqa: E402
import terrain_voxel as T  # noqa: E402

# One flat colour per photo-textured material of fw_kit.base_materials().
FLAT = {
    'plaster': '#e8dcc0', 'timber': '#7a4528', 'planks': '#a87c4c',
    'roof': '#c4552e', 'roof2': '#b24b2b', 'stone': '#b5a68c',
    'stone_dk': '#90846f', 'grass': '#5fae33', 'dirt': '#a98a5a',
    'soil': '#6b4a2e', 'hay': '#e3b94f',
}
PROP_W = {'tree_conifer': 0.85, 'tree_broadleaf': 0.95, 'stone': 0.34}   # tiles wide
GREEN_HUES = (0.17, 0.46)          # hue range the "autumn" remap moves

STYLES = {
    1: dict(name='Referenz-Voxel', mode='flat', vox=2.5, sat=1.28, val=1.04,
            rough=0.95, vary=0.05, sun=((1.0, 0.92, 0.80), 4.4, 50, -38),
            sky=1.0, view='Standard', exp=0.0),
    2: dict(name='Fein-Voxel', mode='flat', vox=1.5, sat=1.32, val=1.04,
            rough=0.95, vary=0.07, sun=((1.0, 0.92, 0.80), 4.4, 50, -38),
            sky=1.0, view='Standard', exp=0.0),
    3: dict(name='Foto-Voxel', mode='pbr', vox=1.0, sat=1.0, val=1.0,
            rough=0.8, vary=0.0, sun=((1.0, 0.86, 0.66), 5.0, 44, -38),
            sky=1.15, view='AgX', exp=0.0),
    4: dict(name='Tinten-Outline', mode='flat', vox=3.0, sat=1.12, val=1.02,
            rough=0.95, vary=0.04, sun=((1.0, 0.95, 0.88), 4.0, 52, -38),
            sky=1.1, view='Standard', exp=0.0),
    5: dict(name='Pastell-Diorama', mode='flat', vox=2.5, sat=0.72, val=1.14,
            rough=1.0, vary=0.04, sun=((1.0, 0.97, 0.94), 2.4, 56, -38),
            sky=1.9, view='Standard', exp=0.15, soft=14),
    6: dict(name='Goldene Stunde', mode='flat', vox=2.5, sat=1.3, val=1.02,
            rough=0.95, vary=0.05, sun=((1.0, 0.74, 0.46), 6.2, 26, -38),
            sky=1.0, view='Standard', exp=0.0,
            world=('#7a6a3c', '#f2a870', '#8c80e0')),
    7: dict(name='Nacht', mode='flat', vox=2.5, sat=1.1, val=0.95,
            rough=0.95, vary=0.05, sun=((0.55, 0.65, 1.0), 1.5, 42, -38),
            sky=0.35, view='Standard', exp=0.35, glow=4.0,
            world=('#10182e', '#2a3c70', '#1a2a5c')),
    8: dict(name='Herbst', mode='flat', vox=2.5, sat=1.3, val=1.0,
            rough=0.95, vary=0.06, sun=((1.0, 0.86, 0.66), 4.8, 40, -38),
            sky=1.05, view='Standard', exp=0.0, autumn=True),
    9: dict(name='32 Farben', mode='flat', vox=4.0, sat=1.25, val=1.04,
            rough=0.95, vary=0.0, sun=((1.0, 0.93, 0.82), 4.4, 50, -38),
            sky=1.0, view='Standard', exp=0.0, snap='E32'),
    10: dict(name='Spielzeug', mode='flat', vox=2.5, sat=1.5, val=1.1,
             rough=0.22, vary=0.0, sun=((1.0, 0.97, 0.92), 5.5, 48, -38),
             sky=1.35, view='Standard', exp=0.0, glossy=True),
}

E32 = ['#be4a2f', '#d77643', '#ead4aa', '#e4a672', '#b86f50', '#733e39',
       '#3e2731', '#a22633', '#e43b44', '#f77622', '#feae34', '#fee761',
       '#63c74d', '#3e8948', '#265c42', '#193c3e', '#124e89', '#0099db',
       '#2ce8f5', '#ffffff', '#c0cbdc', '#8b9bb4', '#5a6988', '#3a4466',
       '#262b44', '#181425', '#ff0044', '#68386c', '#b55088', '#f6757a',
       '#e8b796', '#c28569']


def srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb_hex(rgb):
    return '#%02x%02x%02x' % tuple(int(round(max(0, min(1, v)) * 255)) for v in rgb)


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def nearest(rgb, pal):
    return min(pal, key=lambda p: sum((a - b) ** 2 for a, b in zip(rgb, p)))


def transform(hexs, st):
    """The style's colour transform on one sRGB hex colour -> sRGB tuple."""
    r, g, b = hex_rgb(hexs)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if st.get('autumn') and GREEN_HUES[0] < h < GREEN_HUES[1] and s > 0.25:
        t = (h - GREEN_HUES[0]) / (GREEN_HUES[1] - GREEN_HUES[0])
        h = 0.04 + 0.08 * (1 - t)            # orange .. gold
        s = min(1, s * 1.05)
        v = v * 1.02
    s = min(1.0, s * st['sat'])
    v = min(1.0, v * st['val'])
    out = colorsys.hsv_to_rgb(h, s, v)
    if st.get('snap'):
        out = nearest(out, [hex_rgb(x) for x in E32])
    return out


def mat_hex(m):
    """The flat colour of a material, as an sRGB hex, or None."""
    n = m.name
    if n.startswith('tv_'):
        return n.split('_', 2)[2]
    if n in FLAT:
        return FLAT[n]
    nt = m.node_tree
    if not nt:
        return None
    if any(x.type == 'TEX_IMAGE' for x in nt.nodes):
        print('LAB unknown textured material', n)
        return '#a89878'
    base = None
    for x in nt.nodes:
        if x.type == 'MIX' and x.data_type == 'RGBA':
            base = x.inputs[6].default_value
            break
    if base is None:
        for x in nt.nodes:
            if x.type == 'HUE_SAT' and not x.inputs['Color'].is_linked:
                base = x.inputs['Color'].default_value
                break
    if base is None:
        return None
    return rgb_hex([srgb(base[i]) for i in range(3)])


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flatten(st, vox):
    """Replace every material with one flat colour (+ a faint per-voxel tone)."""
    done = 0
    for m in list(bpy.data.materials):
        if m.name == 'Dots Stroke' or not m.use_nodes:
            continue
        hx = mat_hex(m)
        if hx is None:
            continue
        old = next((x for x in m.node_tree.nodes if x.type == 'BSDF_PRINCIPLED'), None)
        metal = old.inputs['Metallic'].default_value if old else 0.0
        emit = old.inputs['Emission Strength'].default_value if old else 0.0
        alpha = old.inputs['Alpha'].default_value if old else 1.0
        rgb = transform(hx, st)
        base = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
        bsdf.inputs['Roughness'].default_value = (
            st['rough'] if (metal < 0.5 or st.get('glossy')) else 0.45)
        bsdf.inputs['Metallic'].default_value = 0.0 if st.get('glossy') else metal
        bsdf.inputs['Alpha'].default_value = alpha
        if st.get('glossy'):
            for k in ('Specular IOR Level',):
                if k in bsdf.inputs:
                    bsdf.inputs[k].default_value = 0.8
        if emit > 0.0:
            bsdf.inputs['Emission Color'].default_value = base
            bsdf.inputs['Emission Strength'].default_value = emit * st.get('glow', 1.0)
        v = st['vary']
        if v > 0 and emit <= 0.0:
            # a faint tone per VOXEL: floor((P - n * vox/4) / vox) -> white noise
            geo = nt.nodes.new('ShaderNodeNewGeometry')
            nrm = nt.nodes.new('ShaderNodeVectorMath')
            nrm.operation = 'SCALE'
            nrm.inputs['Scale'].default_value = -0.25 * vox
            nt.links.new(geo.outputs['Normal'], nrm.inputs[0])
            add = nt.nodes.new('ShaderNodeVectorMath')
            add.operation = 'ADD'
            nt.links.new(geo.outputs['Position'], add.inputs[0])
            nt.links.new(nrm.outputs[0], add.inputs[1])
            dv = nt.nodes.new('ShaderNodeVectorMath')
            dv.operation = 'SCALE'
            dv.inputs['Scale'].default_value = 1.0 / vox
            nt.links.new(add.outputs[0], dv.inputs[0])
            fl = nt.nodes.new('ShaderNodeVectorMath')
            fl.operation = 'FLOOR'
            nt.links.new(dv.outputs[0], fl.inputs[0])
            wn = nt.nodes.new('ShaderNodeTexWhiteNoise')
            wn.noise_dimensions = '3D'
            nt.links.new(fl.outputs[0], wn.inputs['Vector'])
            sc = nt.nodes.new('ShaderNodeMath')
            sc.operation = 'MULTIPLY_ADD'
            sc.inputs[1].default_value = 2 * v
            sc.inputs[2].default_value = 1 - v
            nt.links.new(wn.outputs['Value'], sc.inputs[0])
            mx = nt.nodes.new('ShaderNodeMix')
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs[0].default_value = 1.0
            mx.inputs[6].default_value = base
            nt.links.new(sc.outputs[0], mx.inputs[7])
            nt.links.new(mx.outputs[2], bsdf.inputs['Base Color'])
        else:
            bsdf.inputs['Base Color'].default_value = base
        done += 1
    print('LAB flattened', done, 'materials')


def light(st):
    """K.lighting with the style's rig; the sun colour and world are patched after."""
    col, energy, elev, swing = st['sun']
    return dict(sun=energy, sky=st['sky'], elev=elev, swing=swing)


def post_light(st):
    col = st['sun'][0]
    for o in bpy.data.objects:
        if o.type == 'LIGHT' and o.data.type == 'SUN' and o.name != 'rim':
            o.data.color = col
            if st.get('soft'):
                o.data.angle = math.radians(st['soft'])
    w = bpy.context.scene.world
    if st.get('world') and w and w.node_tree:
        for n in w.node_tree.nodes:
            if n.type == 'VALTORGB':
                e = n.color_ramp.elements
                e[0].color = K.hexc(st['world'][0][1:])
                e[1].color = K.hexc(st['world'][2][1:])
                e[len(e) - 1].color = K.hexc(st['world'][2][1:])
                for el in e:
                    if 0.2 < el.position < 0.8:
                        el.color = K.hexc(st['world'][1][1:])


def view(st):
    vs = bpy.context.scene.view_settings
    vs.view_transform = st['view']
    if st['view'] == 'Standard':
        vs.look = 'None'
    vs.exposure = vs.exposure + st['exp']


def install_hooks(st, vox):
    orig = K.lighting

    def lighting(*a, **k):
        k = dict(k)
        k.update(light(st))
        orig(*a, **k)
        post_light(st)
        if st['mode'] == 'flat':
            flatten(st, vox)
    K.lighting = lighting
    T.GU = vox                          # ground blocks = building blocks
    T.TILE_SCALE = 3.0                  # px per tile of the swatch (page: 2x of 96 px tiles)
    cur = {'n': None}
    orp = T.render_prop

    def render_prop(name, outdir, samples):
        cur['n'] = name
        return orp(name, outdir, samples)
    T.render_prop = render_prop
    ob_ = T.build_mesh

    def build_mesh(v, name='vox'):
        ob = ob_(v, name)
        if name == 'vox' and st['vox'] > 1.01 and cur['n'] in PROP_W:
            # props: scale to the style's world size, then re-voxelise at the
            # SAME block size as the buildings (user wants one voxel grid)
            import voxelizer
            bpy.context.view_layer.update()
            sc = PROP_W[cur['n']] / max(ob.dimensions.x, ob.dimensions.y)
            ob.scale = (sc, sc, sc)
            return voxelizer.voxelize(vox, 'vox_c', objs=[ob])
        return ob
    T.build_mesh = build_mesh
    oc = T.setup_cycles

    def setup_cycles(scene, samples, transparent):
        oc(scene, samples, transparent)
        view(st)
    T.setup_cycles = setup_cycles


def render_building(bid, st, out, samples, scale):
    mod = importlib.import_module('buildings.' + bid)
    rb.clear()
    K._mats.clear()
    fw_kit.reset_anims()
    mod.build()
    mb.lower_to_yard()
    vox = fw_kit.VOX * st['vox']
    import voxelizer
    voxelizer.voxelize(vox, bid + '_voxel')
    K.lighting()                      # hooked: style rig + flat materials
    K.setup_render(samples, scale, mod.W, mod.H,
                   headroom=getattr(mod, 'HEADROOM', 1.25))
    view(st)
    K.render(out)
    chim = getattr(mod, 'CHIMNEY', None)
    anchor = mb.chimney_anchor(chim) if chim else None
    with open(out[:-4] + '.json', 'w') as f:
        json.dump(dict(W=mod.W, H=mod.H, box=list(rb.frame.art_box),
                       chimney=list(anchor) if anchor else None,
                       size=[bpy.context.scene.render.resolution_x,
                             bpy.context.scene.render.resolution_y]), f)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--style', type=int, required=True)
    ap.add_argument('--what', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=24)
    ap.add_argument('--scale', type=float, default=3.0)
    a = ap.parse_args(argv)
    st = STYLES[a.style]
    outdir = os.path.abspath(os.path.join(a.out, f's{a.style}'))
    os.makedirs(outdir, exist_ok=True)
    install_hooks(st, fw_kit.VOX * st['vox'])
    for what in a.what.split(','):
        if what in T.PROPS or what == 'tile':
            bpy.ops.wm.read_factory_settings(use_empty=True)
            K._mats.clear()
            if what == 'tile':
                T.render_tile(outdir, a.samples)
            else:
                T.render_prop(what, outdir, a.samples)
        elif what in ('sand', 'water'):
            bpy.ops.wm.read_factory_settings(use_empty=True)
            K._mats.clear()
            T.render_flat(outdir, a.samples, what)
        else:
            render_building(what, st, os.path.join(outdir, what + '.png'),
                            a.samples, a.scale)
        print('LAB done', a.style, what, flush=True)


if __name__ == '__main__':
    main()
