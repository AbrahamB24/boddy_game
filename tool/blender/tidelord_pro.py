"""Tidelord (stage 0), in the buildings' photoreal style: a furry horned seal pup.

    blender --background --python tool/blender/tidelord_pro.py -- \
        --out docs/renders/tidelord_pro.png --samples 200 --scale 10

Same world as hatchery_pro.py: pro_kit's Cycles setup, the golden-hour sun, AgX,
real shadows. build() is also what monster_anim_pro.py animates, so every part
the animation needs has a stable name: seal_root, body, head, fl_near, fl_far,
fl_rear_a, fl_rear_b, eye, catch.

Detail the buildings' look asks for: real fur (hair particles with children, a
clump and a little kink so it does not read as a brush), wet glossy eyes with
an iris, a sheen on the nose, whiskers, claws, a crystal horn with side shards,
speckled sub-surface skin colour that grades from back to belly.
"""
import math
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from pro_kit import *  # noqa: F401,F403,E402
import pro_kit as K  # noqa: E402


def skin(key, top, belly, rough=0.55, sss=0.35, ramp=(0.10, 0.26), axis='Z',
         spots=0.0, spots_scale=18.0):
    """Fur/skin colour: grades belly -> back along an object axis, with soft
    mottling, a sheen, a little sub-surface and a micro bump."""
    if key in K._mats:
        return K._mats[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    b = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(b.outputs['BSDF'], out.inputs['Surface'])
    co = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(co.outputs['Object'], sep.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = ramp[0]
    mr.inputs['From Max'].default_value = ramp[1]
    nt.links.new(sep.outputs[axis], mr.inputs['Value'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    rp.color_ramp.elements[0].color = hexc(belly)
    rp.color_ramp.elements[1].color = hexc(top)
    nt.links.new(mr.outputs['Result'], rp.inputs['Fac'])
    n1 = nt.nodes.new('ShaderNodeTexNoise')
    n1.inputs['Scale'].default_value = 11.0
    n1.inputs['Detail'].default_value = 4.0
    nt.links.new(co.outputs['Object'], n1.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 0.30
    nt.links.new(rp.outputs['Color'], mix.inputs[6])
    nt.links.new(n1.outputs['Color'], mix.inputs[7])
    # soft dark spots, the way a pup's coat is dappled along the back
    vor = nt.nodes.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = spots_scale
    nt.links.new(co.outputs['Object'], vor.inputs['Vector'])
    sr = nt.nodes.new('ShaderNodeValToRGB')
    sr.color_ramp.elements[0].position = 0.0
    sr.color_ramp.elements[0].color = (0.62, 0.70, 0.86, 1)
    sr.color_ramp.elements[1].position = 0.20
    sr.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(vor.outputs['Distance'], sr.inputs['Fac'])
    mix2 = nt.nodes.new('ShaderNodeMix')
    mix2.data_type = 'RGBA'
    mix2.blend_type = 'MULTIPLY'
    mix2.inputs[0].default_value = spots
    nt.links.new(mix.outputs[2], mix2.inputs[6])
    nt.links.new(sr.outputs['Color'], mix2.inputs[7])
    nt.links.new(mix2.outputs[2], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = rough
    for k, v in (('Subsurface Weight', sss), ('Sheen Weight', 0.12),
                 ('Sheen Roughness', 0.35), ('Coat Weight', 0.05),
                 ('Coat Roughness', 0.3)):
        if k in b.inputs:
            b.inputs[k].default_value = v
    if 'Subsurface Radius' in b.inputs:
        b.inputs['Subsurface Radius'].default_value = (0.5, 0.35, 0.2)
    n2 = nt.nodes.new('ShaderNodeTexNoise')
    n2.inputs['Scale'].default_value = 150.0
    n2.inputs['Detail'].default_value = 2.0
    nt.links.new(co.outputs['Object'], n2.inputs['Vector'])
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = 0.55
    bp.inputs['Distance'].default_value = 0.004
    nt.links.new(n2.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    K._mats[key] = m
    return m


def glossy(key, rgb, rough=0.05, coat=1.0, emit=None, es=0.0):
    if key in K._mats:
        return K._mats[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = hexc(rgb)
    b.inputs['Roughness'].default_value = rough
    if 'Coat Weight' in b.inputs:
        b.inputs['Coat Weight'].default_value = coat
        b.inputs['Coat Roughness'].default_value = 0.02
    if emit:
        b.inputs['Emission Color'].default_value = hexc(emit)
        b.inputs['Emission Strength'].default_value = es
    K._mats[key] = m
    return m


def ice_mat():
    if 'ice' in K._mats:
        return K._mats['ice']
    m = bpy.data.materials.new('ice')
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = hexc('bfe4f7')
    b.inputs['Roughness'].default_value = 0.1
    b.inputs['IOR'].default_value = 1.31
    for k, v in (('Transmission Weight', 0.85), ('Subsurface Weight', 0.2)):
        if k in b.inputs:
            b.inputs[k].default_value = v
    b.inputs['Emission Color'].default_value = hexc('8fd6ff')
    b.inputs['Emission Strength'].default_value = 0.5
    K._mats['ice'] = m
    return m


def fur(ob, count, length, children=12, thick=0.0016, seed=1, name='fur'):
    """Hair particles on a mesh: short, dense, clumped, with a little kink."""
    md = ob.modifiers.new(name, 'PARTICLE_SYSTEM')
    ps = md.particle_system
    st = ps.settings
    st.type = 'HAIR'
    st.count = count
    st.hair_length = length
    st.hair_step = 3
    st.render_type = 'PATH'
    st.use_advanced_hair = False
    st.child_type = 'INTERPOLATED'
    st.rendered_child_count = children
    st.child_percent = 10
    st.child_length = 1.0
    st.child_radius = 0.02
    st.child_roundness = 1.0
    st.clump_factor = 0.35
    st.kink = 'CURL'
    st.kink_amplitude = 0.0025
    st.kink_frequency = 6.0
    st.root_radius = thick * 100
    st.tip_radius = 0.0
    st.radius_scale = 0.01
    st.length_random = 0.25
    st.material = 1
    ps.seed = seed
    return ps


# local frame: +x forward (head), +y left, +z up; the seal lies on z = 0
def paddle(mat, L, W, T, yaw=0.0, pitch=0.0, roll=0.0, at=(0, 0, 0),
           ridge_mat=None, claw_mat=None, parent=None, name='paddle'):
    """A flipper: narrow at the root, fanning to a rounded three-fingered tip."""
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=24, radius=1.0)
    for v in bm.verts:
        t = max(0.0, min(1.0, (v.co.x + 1.0) / 2.0))
        fan = 0.30 + 0.70 * (t ** 1.1)
        lobe = 1.0 - 0.10 * max(0.0, t - 0.72) / 0.28 * (
            0.5 + 0.5 * math.cos(3 * math.atan2(v.co.y, 0.4)))
        v.co = Vector((t * L, v.co.y * W * fan * lobe,
                       v.co.z * T * (1.0 - 0.55 * t)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    ob.location = at
    ob.rotation_euler = (math.radians(roll), math.radians(pitch),
                         math.radians(yaw))
    ob.parent = parent
    if ridge_mat is not None:
        for k in (-1, 0, 1):
            r = ellipsoid(L * 0.80, k * W * 0.50, T * 0.30, L * 0.20, W * 0.07,
                          T * 0.22, ridge_mat, seg=16, rings=10)
            r.parent = ob
    if claw_mat is not None:
        for k in (-1, 0, 1):
            c = cyl(0, 0, 0, 0.011, 0.001, 0.045, claw_mat, seg=8)
            c.location = (L * 0.99, k * W * 0.60, 0.0)
            c.rotation_euler = (0, math.radians(90 - 8), math.radians(k * 14))
            c.parent = ob
    return ob


def build(yaw=212.0, furry=False, head_yaw=48.0, catcher=1.5):
    random.seed(3)
    blue = skin('sk_top', '#1a78e4', '#bfe0f6', ramp=(0.06, 0.22), spots=0.55)
    head_m = skin('sk_head', '#2c8cf0', '#c9e6f8', ramp=(-0.06, 0.12), spots=0.3, spots_scale=26.0)
    flip_m = skin('sk_flip', '#4aa8f2', '#b9defa', ramp=(-0.03, 0.05), spots=0.35, spots_scale=24.0)
    flip_d = skin('sk_flip_d', '#2c8ae0', '#8cc6ee', ramp=(-0.03, 0.05))
    belly = skin('sk_belly', '#c4e2f3', '#dff0f9', ramp=(-0.1, 0.1), sss=0.4)
    cream = skin('sk_cream', '#e8dcc2', '#cdbf9f', rough=0.7, sss=0.25,
                 ramp=(-0.05, 0.05))
    navy = glossy('navy', '#07142e', rough=0.04, coat=1.0)
    nose = glossy('nose', '#14243f', rough=0.18, coat=0.8)
    ivory = glossy('ivory', '#f2ead4', rough=0.4, coat=0.3)
    white_e = plain('catch', '#ffffff', rough=0.3, bump=0.0, emit='#ffffff',
                    emit_strength=8.0, vary=0.0)
    sclera = plain('sclera', '#f6f4ec', rough=0.3, bump=0.0, vary=0.0)
    # matte, so the pupil stays black instead of mirroring the blue sky
    pupil = plain('pupil', '#0b0f1a', rough=0.55, bump=0.0, vary=0.0)
    # a soft glow only: the old emission-8 catch bloomed into a white smear
    eye_hi = plain('eye_hi', '#ffffff', rough=0.3, bump=0.0, emit='#ffffff',
                   emit_strength=1.2, vary=0.0)
    ice = ice_mat()

    root = bpy.data.objects.new('seal_root', None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (0, 0, math.radians(yaw))

    def reg(ob, parent=None):
        ob.parent = parent or root
        return ob

    # ── body: metaball = one continuous skin ──
    mb = bpy.data.metaballs.new('body')
    mb.resolution = 0.010
    mb.render_resolution = 0.008
    mb.threshold = 0.5

    def el(x, y, z, r, sx=1.0, sy=1.0, sz=1.0, stiff=2.0):
        e = mb.elements.new(type='ELLIPSOID')
        e.co = (x, y, z)
        e.radius = r
        e.size_x, e.size_y, e.size_z = sx, sy, sz
        e.stiffness = stiff
    el(0.16, 0.0, 0.25, 0.30, 1.00, 1.00, 0.95)
    el(-0.02, 0.0, 0.23, 0.31, 1.00, 1.00, 0.88)
    el(-0.14, 0.0, 0.21, 0.27, 1.00, 0.92, 0.82)
    el(-0.25, 0.0, 0.19, 0.20, 1.00, 0.78, 0.70)
    el(-0.34, 0.0, 0.18, 0.13, 1.00, 0.66, 0.62)
    bo = bpy.data.objects.new('body', mb)
    bpy.context.scene.collection.objects.link(bo)
    bo.data.materials.append(blue)

    reg(ellipsoid(0.27, 0.0, 0.15, 0.14, 0.17, 0.10, belly, seg=32, rings=20))

    # ── head ──
    head = bpy.data.objects.new('head', None)
    bpy.context.scene.collection.objects.link(head)
    head.location = (0.22, 0, 0.30)
    head.rotation_euler = (0, math.radians(-4), math.radians(head_yaw))
    head.scale = (1.14, 1.14, 1.14)
    reg(head)

    def hp(ob):
        return reg(ob, head)

    skull = hp(ellipsoid(0.12, 0, 0.07, 0.19, 0.20, 0.175, head_m, seg=48,
                         rings=32))
    skull.name = 'skull'
    for sg in (-1, 1):
        hp(ellipsoid(0.245, sg * 0.055, -0.03, 0.075, 0.085, 0.065, cream,
                     seg=28, rings=18))
    hp(ellipsoid(0.27, 0, -0.02, 0.085, 0.10, 0.065, cream, seg=28, rings=18))
    hp(ellipsoid(0.235, 0, -0.085, 0.08, 0.085, 0.04, cream, seg=24, rings=14))
    hp(ellipsoid(0.335, 0, 0.022, 0.04, 0.052, 0.034, nose, seg=24, rings=16))
    for sg in (-1, 1):
        hp(ellipsoid(0.368, sg * 0.016, 0.018, 0.006, 0.010, 0.007, navy,
                     seg=8, rings=6))
    # ── eyes: built to survive the voxel grid (one block ~0.027 here) ──
    # A white eyeball, a big near-black pupil set a little toward the nose and
    # pushed proud of the white, and one large highlight block-pair at the
    # upper outer edge of the pupil: white / black / white reads at 5-6
    # blocks across on any skin tone (the old dark-blue iris inside a navy
    # eye inside a dark-blue socket melted into the stage-2 skin). A thick
    # navy brow sits on top of each eye for expression.
    for sg in (-1, 1):
        hp(ellipsoid(0.252, sg * 0.108, 0.112, 0.048, 0.066, 0.080, sclera,
                     seg=28, rings=18)).name = 'eye'
        hp(ellipsoid(0.288, sg * 0.102, 0.106, 0.036, 0.050, 0.062, pupil,
                     seg=28, rings=18)).name = 'eye'
        hp(ellipsoid(0.318, sg * 0.120, 0.132, 0.016, 0.016, 0.016,
                     eye_hi, seg=12, rings=8)).name = 'catch'
        hp(ellipsoid(0.236, sg * 0.112, 0.206, 0.040, 0.062, 0.017, navy,
                     seg=16, rings=10,
                     tilt=(math.radians(-sg * 14), 0, math.radians(-sg * 10)))
           ).name = 'brow'
        tk = cyl(0, 0, 0, 0.013, 0.002, 0.065, ivory, seg=12)
        tk.location = (0.30, sg * 0.04, -0.05)
        tk.rotation_euler = (math.radians(180 + sg * 10), math.radians(-12), 0)
        hp(tk)
    rnd = random.Random(2)
    for sg in (-1, 1):
        for i in range(7):
            a = rnd.uniform(-0.5, 0.5)
            hp(ellipsoid(0.335 - abs(a) * 0.03, sg * (0.055 + rnd.uniform(0.0, 0.03)),
                         -0.02 + a * 0.05, 0.005, 0.005, 0.005, nose, seg=8,
                         rings=6))
        for i in range(3):
            p0 = Vector((0.31, sg * 0.07, -0.005 - i * 0.016))
            p1 = Vector((0.33 + i * 0.008, sg * (0.13 + i * 0.010), -0.035 - i * 0.022))
            hp(beam(p0, p1, 0.0022, ivory, bevel=0))

    def crystal(x, y, z, r, h, tilt):
        c = cyl(0, 0, 0, r, 0.003, h, ice, seg=6, smooth=False)
        c.location = (x, y, z)
        c.rotation_euler = tilt
        return hp(c)
    crystal(0.16, 0, 0.215, 0.045, 0.17, (0, math.radians(18), 0))
    crystal(0.13, 0.04, 0.205, 0.026, 0.10, (math.radians(-22), math.radians(8), 0))
    crystal(0.14, -0.04, 0.205, 0.022, 0.085, (math.radians(24), math.radians(12), 0))
    hb = cyl(0, 0, 0, 0.058, 0.046, 0.03, ice, seg=6, smooth=False)
    hb.location = (0.155, 0, 0.212)
    hp(hb)

    # ── flippers ──
    p1 = paddle(flip_m, 0.44, 0.17, 0.06, yaw=140, pitch=3, roll=-5,
                at=(0.10, 0.15, 0.07), ridge_mat=flip_d, claw_mat=ivory,
                parent=root, name='fl_near')
    p2 = paddle(flip_m, 0.40, 0.15, 0.06, yaw=-22, pitch=3, roll=5,
                at=(0.22, -0.16, 0.07), ridge_mat=flip_d, claw_mat=ivory,
                parent=root, name='fl_far')
    r1 = paddle(flip_m, 0.36, 0.17, 0.06, yaw=152, pitch=-20, roll=6,
                at=(-0.34, 0.05, 0.13), ridge_mat=flip_d, parent=root,
                name='fl_rear_a')
    r2 = paddle(flip_m, 0.36, 0.17, 0.06, yaw=-152, pitch=-20, roll=-6,
                at=(-0.34, -0.05, 0.13), ridge_mat=flip_d, parent=root,
                name='fl_rear_b')

    # ── convert the metaball ──
    bpy.context.view_layer.objects.active = bo
    bo.select_set(True)
    bpy.ops.object.convert(target='MESH')
    bo = bpy.context.view_layer.objects.active
    bo.name = 'body'
    bo.parent = root
    for p in bo.data.polygons:
        p.use_smooth = True

    # ── fur ──
    if furry:
        fur(bo, 7000, 0.016, children=14, seed=1)
        fur(skull, 4500, 0.013, children=14, seed=2)
        for pd in (p1, p2, r1, r2):
            fur(pd, 1800, 0.006, children=10, seed=3)

    if catcher:
        cat = box(0, 0, -0.012, catcher, catcher, 0.01,
                  plain('ground', '#bba783', bump=0.0), bevel=0)
        cat.is_shadow_catcher = True
    return root


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='docs/renders/tidelord_pro.png')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--scale', type=int, default=10)
    ap.add_argument('--blend')
    args = ap.parse_args(argv)
    rb.clear()
    build()
    lighting(sky=0.85, sun=5.5)
    rim_light(Vector((-0.6, 0.5, 0.7)))
    setup_render(args.samples, args.scale, 1, 1)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.blend)
    render(args.out)


if __name__ == '__main__':
    main()
