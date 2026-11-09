"""Glimmergnaw: rigid-voxel rig, poses, and sprite-sheet bake (battle + map).

    blender --background --python tool/blender/glimmergnaw_bake.py -- \
        --stage 0 --out docs/renders/monsters/glimmergnaw_s0 \
        [--views front,back,sidel,sider,map] [--anims idle,attack,hurt,walk] \
        [--samples 24] [--still out.png --view front]

Same recipe as monster_voxel.py: the creature at rest is split into rigid parts
(body, head, two arms, two legs, tail), each is voxelised ONCE on one shared grid
and parented to a pivot at its joint, and the animation only moves and turns
finished blocks - blocks never appear, vanish or change colour, so nothing
shimmers. Sheets use the layout the game already reads (8 columns, 560 x 448
battle cells; the map uses the buildings' isometric camera).

Poses are functions of t in [0, 1). Rotations are in degrees about the WORLD axes
of the part's pivot. The creature faces +x, so:
    rot y  > 0 : the top tips FORWARD / the head nods DOWN
    rot y  < 0 : an arm or leg swings FORWARD (and an arm raised overhead)
    rot z      : turn (yaw), also the tail wag
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_voxel as gg  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
import tidelord_sprite as sp  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402

FW, FH, COLS = 560, 448, 8

# joint of every part, at rest (world coordinates)
PIVOT = {
    0: dict(head=(0.14, 0, 0.64), arm_p=(0.02, 0.30, 0.60), arm_n=(0.02, -0.30, 0.60),
            leg_p=(0.12, 0.18, 0.20), leg_n=(0.12, -0.18, 0.20), tail=(-0.32, 0, 0.20)),
    1: dict(head=(0.10, 0, 1.22), arm_p=(0.0, 0.36, 1.10), arm_n=(0.0, -0.36, 1.10),
            farm_p=(0.14, 0.40, 0.86), farm_n=(0.14, -0.40, 0.86),
            leg_p=(0.0, 0.20, 0.66), leg_n=(0.0, -0.20, 0.66), tail=(-0.36, 0, 0.50)),
    2: dict(head=(0.12, 0, 1.20), arm_p=(0.02, 0.46, 1.10), arm_n=(0.02, -0.46, 1.10),
            farm_p=(0.18, 0.54, 0.85), farm_n=(0.18, -0.54, 0.85),
            leg_p=(-0.04, 0.28, 0.72), leg_n=(-0.04, -0.28, 0.72), tail=(-0.44, 0, 0.60)),
}
# how big each stage is on the map, relative to the pup's frame (see monster_walk.py)
MAP_K = {0: 1.30, 1: 1.60, 2: 1.95}

# stage character: amplitude of the idle sway, how hard it hits
CHAR = {0: dict(sway=1.0, hit=0.8), 1: dict(sway=0.8, hit=1.0), 2: dict(sway=0.55, hit=1.3)}


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def curve(t, keys):
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * smooth((t - t0) / (t1 - t0))
    return keys[-1][1]


class Rig:
    def __init__(self, stage):
        self.stage = stage
        gg.P.update(dict(bw=1.0, lr=1.0, head=1.0, seg=24, rings=16, gnaw=False))
        tw.SMOOTH_MATS = True
        tw.DEPTH = 8                      # was 7: half the voxel size
        objs = gg.build(stage)
        groups = {}
        for o in objs:
            groups.setdefault(o['grp'], []).append(o)
        self.face = bpy.data.objects.new('face', None)       # heading
        self.root = bpy.data.objects.new('root', None)       # pose (body)
        for e in (self.face, self.root):
            bpy.context.scene.collection.objects.link(e)
        self.root.parent = self.face
        self.piv, self.base, self.vox = {}, {}, []
        names = sorted(groups, key=lambda n: n.startswith('farm_'))   # arms before forearms
        for name in names:
            vox = tw.voxelise(groups[name])
            vox.name = 'vox_' + name
            self.vox.append(vox)
            if name == 'body':
                vox.parent = self.root
                continue
            piv = bpy.data.objects.new('piv_' + name, None)
            bpy.context.scene.collection.objects.link(piv)
            world = Vector(PIVOT[stage][name])
            if name.startswith('farm_'):                    # forearm hangs off its upper arm
                up = self.piv['arm_' + name[-1]]
                piv.parent = up
                piv.location = world - Vector(PIVOT[stage]['arm_' + name[-1]])
            else:
                piv.parent = self.root
                piv.location = world
            piv.matrix_parent_inverse = Matrix.Identity(4)
            bpy.context.view_layer.update()
            vox.parent = piv
            vox.matrix_parent_inverse = piv.matrix_world.inverted()
            self.piv[name] = piv
            self.base[name] = piv.location.copy()
        self.mats = {m.name: m for m in bpy.data.materials}
        for n, m in self.mats.items():
            # a little self-light: a gap between two parts can never go pitch black
            if n in ('crys', 'crysd', 'white', 'dark'):
                continue
            b = m.node_tree.nodes['Principled BSDF']
            b.inputs['Emission Color'].default_value = b.inputs['Base Color'].default_value
            b.inputs['Emission Strength'].default_value = 0.30
        for n, m in self.mats.items():
            if n not in ('crys', 'crysd', 'white'):
                self.crease_shade(m)
        self.emit0 = {}
        for n, m in self.mats.items():
            b = m.node_tree.nodes['Principled BSDF']
            self.emit0[n] = (tuple(b.inputs['Emission Color'].default_value),
                             b.inputs['Emission Strength'].default_value)
        self.reset()

    @staticmethod
    def crease_shade(m, dist=0.07, floor=0.52):
        """A soft, natural contact shadow in the creases (joints, where parts and materials
        meet): ambient occlusion multiplied into the base colour, never darker than `floor`
        of the colour. It is part of the surface, so it stays put while the parts move."""
        nt = m.node_tree
        b = nt.nodes['Principled BSDF']
        ao = nt.nodes.new('ShaderNodeAmbientOcclusion')
        ao.inputs['Distance'].default_value = dist
        ao.samples = 8
        ao.only_local = False
        rng = nt.nodes.new('ShaderNodeMapRange')
        rng.inputs['From Min'].default_value = 0.0
        rng.inputs['From Max'].default_value = 1.0
        rng.inputs['To Min'].default_value = floor
        rng.inputs['To Max'].default_value = 1.0
        nt.links.new(ao.outputs['AO'], rng.inputs['Value'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        mix.inputs['A'].default_value = b.inputs['Base Color'].default_value
        nt.links.new(rng.outputs['Result'], mix.inputs['B'])
        nt.links.new(mix.outputs['Result'], b.inputs['Base Color'])

    def reset(self):
        self.root.location = (0, 0, 0)
        self.root.rotation_euler = (0, 0, 0)
        for n, p in self.piv.items():
            p.location = self.base[n]
            p.rotation_euler = (0, 0, 0)
        for s in 'pn':
            self.elbow(s, (0, 0, 0))
        self.glow(0.0)
        self.flash(0.0)

    def move(self, name, d=(0, 0, 0), rot=(0, 0, 0)):
        if name == 'root':
            ob = self.root
            ob.location = d
        else:
            ob = self.piv.get(name)
            if ob is None:
                return
            ob.location = self.base[name] + Vector(d)
        ob.rotation_euler = Euler([math.radians(a) for a in rot])
        if name.startswith('arm_'):
            self.elbow(name[-1], rot)

    def elbow(self, side, arm_rot):
        """The forearm follows the arm: a relaxed bend at rest, bending further the
        further the arm swings forward or is raised (rot y < 0 = forward)."""
        fa = self.piv.get('farm_' + side)
        if fa is None:
            return
        bend = -16 + 0.55 * arm_rot[1] - 0.30 * abs(arm_rot[0])
        fa.rotation_euler = Euler((0, math.radians(bend), 0))

    def glow(self, k):
        """Extra crystal light (0 = the resting glow)."""
        for n in ('crys', 'crysd'):
            m = self.mats.get(n)
            if m:
                b = m.node_tree.nodes['Principled BSDF']
                b.inputs['Emission Strength'].default_value = self.emit0[n][1] + k

    def flash(self, v):
        """White hit flash over everything."""
        for n, m in self.mats.items():
            b = m.node_tree.nodes['Principled BSDF']
            if v > 0:
                b.inputs['Emission Color'].default_value = (1, 1, 1, 1)
                b.inputs['Emission Strength'].default_value = v
            else:
                b.inputs['Emission Color'].default_value = self.emit0[n][0]
                if n not in ('crys', 'crysd'):
                    b.inputs['Emission Strength'].default_value = self.emit0[n][1]


# ── poses ─────────────────────────────────────────────────────
def pose_idle(r, t):
    s = 2 * math.pi * t
    c = CHAR[r.stage]['sway']
    br = math.sin(s)
    r.move('root', d=(0, 0, 0.012 * br), rot=(0, 1.2 * br * c, 2.5 * math.sin(s) * c))
    r.move('head', rot=(0, 3 * math.sin(s + 0.8), 8 * math.sin(s) * c))
    r.move('arm_p', rot=(0, -5 * math.sin(s + 0.5), 0))
    r.move('arm_n', rot=(0, 5 * math.sin(s + 0.5), 0))
    r.move('leg_p', rot=(0, 0, 0))
    r.move('leg_n', rot=(0, 0, 0))
    r.move('tail', rot=(0, 3 * math.sin(s), 18 * math.sin(s + 0.6)))
    r.glow(0.15 + 0.15 * math.sin(s) * (1 + r.stage))
    if r.stage == 0:        # the pup lifts a paw and waves it slowly (small, slow)
        w = curve(t, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)])
        r.move('arm_n', rot=(-12 * w, 0, 0))
        r.move('arm_p', rot=(-22 * w, 0, 8 * w * math.sin(s * 2)))
    elif r.stage == 1:      # sniffs and looks around
        r.move('head', rot=(0, 6 * math.sin(2 * s), 14 * math.sin(s)))
    else:                   # heavy breathing, flexing
        r.move('arm_p', rot=(0, -8 * br, 0))
        r.move('arm_n', rot=(0, -8 * br, 0))
        r.move('root', d=(0, 0, 0.02 * br), rot=(0, 1.5 * br, 0))


def pose_walk(r, t):
    s = 2 * math.pi * t
    st = r.stage
    amp = (28, 34, 26)[st]
    r.move('root', d=(0, 0, 0.03 * abs(math.sin(s))),
           rot=(0, (6, 4, 8)[st], 5 * math.sin(s)))
    r.move('leg_p', d=(0, 0, 0.04 * max(0, math.cos(s))), rot=(0, -amp * math.sin(s), 0))
    r.move('leg_n', d=(0, 0, 0.04 * max(0, -math.cos(s))), rot=(0, amp * math.sin(s), 0))
    r.move('arm_p', rot=(0, 22 * math.sin(s), 0))
    r.move('arm_n', rot=(0, -22 * math.sin(s), 0))
    r.move('head', rot=(0, -3 + 3 * math.cos(2 * s), -5 * math.sin(s)))
    r.move('tail', rot=(0, 4 * math.cos(2 * s), 16 * math.sin(s)))
    r.glow(0.1)


def pose_attack(r, t):
    h = CHAR[r.stage]['hit']
    wind = curve(t, [(0, 0), (0.30, 1), (0.42, 0), (1, 0)])
    hit = curve(t, [(0, 0), (0.30, 0), (0.48, 1), (0.62, 0.8), (1, 0)])
    if r.stage == 0:        # headbutt and a hopping bite
        r.move('root', d=(0.14 * hit, 0, 0.05 * wind), rot=(0, -8 * wind + 14 * hit, 0))
        r.move('head', d=(0.10 * hit, 0, 0), rot=(0, -12 * wind + 26 * hit, 0))
        r.move('arm_p', rot=(-35 * wind - 20 * hit, 0, 0))
        r.move('arm_n', rot=(-35 * wind - 20 * hit, 0, 0))
        r.move('leg_p', rot=(0, 18 * wind - 20 * hit, 0))
        r.move('leg_n', rot=(0, 18 * wind - 20 * hit, 0))
        r.move('tail', rot=(0, 0, -24 * hit))
    elif r.stage == 1:      # a lunging claw swipe
        r.move('root', d=(0.20 * hit, 0, 0), rot=(0, -6 * wind + 12 * hit, 14 * wind - 22 * hit))
        r.move('head', d=(0.10 * hit, 0, 0), rot=(0, -8 * wind + 16 * hit, 0))
        r.move('arm_p', rot=(-95 * wind + 55 * hit, 0, 40 * wind - 55 * hit))
        r.move('arm_n', rot=(10 * wind - 25 * hit, 0, 0))
        r.move('leg_p', rot=(0, -20 * hit + 10 * wind, 0))
        r.move('leg_n', rot=(0, 25 * hit - 10 * wind, 0))
        r.move('tail', rot=(0, 0, 30 * hit - 14 * wind))
    else:                   # both fists overhead, then a crushing slam
        r.move('root', d=(0.22 * hit, 0, -0.05 * hit),
               rot=(0, -10 * wind + 20 * hit, 0))
        r.move('head', d=(0.08 * hit, 0, 0), rot=(0, -10 * wind + 20 * hit, 0))
        r.move('arm_p', rot=(-150 * wind + 130 * hit, 0, 0))
        r.move('arm_n', rot=(-150 * wind + 130 * hit, 0, 0))
        r.move('leg_p', rot=(0, 10 * wind - 14 * hit, 0))
        r.move('leg_n', rot=(0, 10 * wind - 14 * hit, 0))
        r.move('tail', rot=(0, -10 * hit, -20 * hit))
    r.glow(1.2 * wind * h + 2.0 * hit * h)


def pose_hurt(r, t):
    hit = curve(t, [(0, 0), (0.15, 1), (0.40, 0.5), (0.70, 0.12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    r.move('root', d=(-0.10 * hit, 0.01 * wob, 0), rot=(0, -9 * hit, 4 * wob))
    r.move('head', d=(-0.05 * hit, 0, 0), rot=(0, -18 * hit, 10 * wob))
    r.move('arm_p', rot=(-30 * hit, 0, 25 * hit))
    r.move('arm_n', rot=(-30 * hit, 0, -25 * hit))
    r.move('leg_p', rot=(0, 14 * hit, 0))
    r.move('leg_n', rot=(0, -10 * hit, 0))
    r.move('tail', rot=(0, 0, 25 * hit))
    r.flash(0.9 if t < 0.12 else (0.45 if t < 0.28 else 0.0))


ANIMS = {   # name: (frames, fps, loop, pose)
    'idle': (16, 12, True, pose_idle),
    'attack': (14, 16, False, pose_attack),
    'hurt': (10, 14, False, pose_hurt),
    'walk': (8, 10, True, pose_walk),
}
MAP_IDLE = (8, 8, True, pose_idle)

# camera directions of the battle views (same as monster_anim_pro.py)
VIEWS = {'front': (0.80, 1.0, 0.38), 'back': (-0.90, 0.55, 0.45),
         'sidel': (0.86, -0.50, 0.30), 'sider': (-0.37, 0.93, 0.30)}
HEADINGS = {'se': 0.0, 'ne': 90.0, 'nw': 180.0, 'sw': 270.0}


# ── scene ─────────────────────────────────────────────────────
def _split_shadows():
    """The creature casts a shadow on the GROUND only, never on itself.

    Self-shadows (a crystal's shadow on the shoulder, the gap between arm and body) read as
    black blotches on voxel steps and flicker in the animations. Light linking: the key sun
    with shadows lights only the ground; a twin without shadows lights only the creature."""
    ground = [o for o in bpy.data.objects if getattr(o, 'is_shadow_catcher', False)]
    body = [o for o in bpy.data.objects if o.name.startswith('vox_')]
    cg = bpy.data.collections.new('ground_rx')
    cb = bpy.data.collections.new('creature_rx')
    bpy.context.scene.collection.children.link(cg)
    bpy.context.scene.collection.children.link(cb)
    for o in ground:
        cg.objects.link(o)
    for o in body:
        cb.objects.link(o)
    for ob in list(bpy.data.objects):
        if ob.type != 'LIGHT' or ob.data.type != 'SUN':
            continue
        if ob.name == 'rim':
            ob.data.use_shadow = False
            continue
        twin = bpy.data.objects.new('key_soft', ob.data.copy())
        twin.rotation_euler = ob.rotation_euler.copy()
        twin.data.use_shadow = False
        bpy.context.scene.collection.objects.link(twin)
        ob.light_linking.receiver_collection = cg
        twin.light_linking.receiver_collection = cb
        # a weak fill from the opposite side: no wall of the creature may face away from
        # every light (a flat side wall of voxels read as a dark patch)
        fill = bpy.data.objects.new('key_fill', ob.data.copy())
        fill.data.use_shadow = False
        fill.data.energy = ob.data.energy * 0.25
        fill.data.color = (0.85, 0.92, 1.0)
        fill.rotation_euler = (Euler((0, 0, math.pi)).to_matrix()
                               @ ob.rotation_euler.to_matrix()).to_euler()
        bpy.context.scene.collection.objects.link(fill)
        fill.light_linking.receiver_collection = cb
        # and one from each flank, low: a big flat voxel wall facing sideways (the outside of
        # an arm, say) would otherwise be the one dark patch on the body
        for sgn in (1, -1):
            side = bpy.data.objects.new('flank', ob.data.copy())
            side.data.use_shadow = False
            side.data.energy = 0.6
            side.data.color = (1.0, 0.95, 0.88)
            side.rotation_euler = Vector((0.1, -sgn, -0.35)).normalized().to_track_quat(
                '-Z', 'Y').to_euler()
            bpy.context.scene.collection.objects.link(side)
            side.light_linking.receiver_collection = cb


def lights(cam_loc, target, exposure):
    # "normal" shadows: a wide, soft sun plus a strong sky fill, so the gaps between
    # parts and the voxel steps never go black (they looked wrong in motion)
    K.lighting(sky=1.5, sun=3.6)
    L = sp.key_light(cam_loc, target)
    for ob in bpy.data.objects:
        if ob.type == 'LIGHT' and ob.data.type == 'SUN':
            ob.rotation_euler = (-L).to_track_quat('-Z', 'Y').to_euler()
            if ob.name != 'rim':
                ob.data.angle = math.radians(14)
    _split_shadows()
    cdir = (Vector(target) - cam_loc).normalized()
    right = cdir.cross(Vector((0, 0, 1))).normalized()
    K.rim_light((-cdir * 0.7 + right * 0.45 + Vector((0, 0, 0.6))).normalized())
    sc = bpy.context.scene
    vs = sc.view_settings
    vs.view_transform = 'AgX'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = exposure


def engine(samples):
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
    cy.max_bounces = 6
    sc.render.film_transparent = True
    sc.render.filter_size = 0.9
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'


def shadow_catcher(size):
    c = K.box(0, 0, -0.012, size, size, 0.01, K.plain('ground', '#bba783', bump=0.0),
              bevel=0)
    c.is_shadow_catcher = True


def contact_shadow(stage, k=1.0):
    """A soft, round contact shadow right under the creature (and its tail), so it stands ON
    the ground instead of hovering over a detached cast shadow. Black with a radial alpha
    falloff - deterministic, no render noise, and the same in every view and animation frame."""
    rx, ry = {0: (0.52, 0.40), 1: (0.60, 0.46), 2: (0.72, 0.56)}[stage]
    cx = {0: -0.04, 1: -0.08, 2: -0.12}[stage]
    me = bpy.data.meshes.new('cs')
    me.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new('contact_shadow', me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (cx, 0, 0.004)
    ob.scale = (rx * k, ry * k, 1)
    ob.visible_shadow = False
    m = bpy.data.materials.new('contact_shadow')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    tc = nt.nodes.new('ShaderNodeTexCoord')
    gr = nt.nodes.new('ShaderNodeTexGradient')
    gr.gradient_type = 'QUADRATIC_SPHERE'
    nt.links.new(tc.outputs['Object'], gr.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeMapRange')
    ramp.inputs['From Min'].default_value = 0.0
    ramp.inputs['From Max'].default_value = 0.55
    ramp.inputs['To Min'].default_value = 0.0
    ramp.inputs['To Max'].default_value = 0.8
    nt.links.new(gr.outputs['Fac'], ramp.inputs['Value'])
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    bl = nt.nodes.new('ShaderNodeEmission')
    bl.inputs['Color'].default_value = (0.02, 0.015, 0.01, 1)
    bl.inputs['Strength'].default_value = 1.0
    mx = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(ramp.outputs['Result'], mx.inputs['Fac'])
    nt.links.new(tr.outputs[0], mx.inputs[1])
    nt.links.new(bl.outputs[0], mx.inputs[2])
    nt.links.new(mx.outputs[0], out.inputs['Surface'])
    me.materials.append(m)
    return ob


def battle_camera(rig, direction, pad=0.24):
    """Ortho camera that frames the whole creature (rest pose + room to move) in
    a 560 x 448 cell, feet near the bottom."""
    sc = bpy.context.scene
    d = Vector(direction).normalized()
    q = (-d)
    R = q.to_track_quat('-Z', 'Y').to_matrix().to_4x4()
    inv = R.inverted()
    xs, ys = [], []
    # The frame must hold the creature in EVERY pose of EVERY animation, not just
    # at rest (user 2026-11-08: a monster's parts must never be cut off at the
    # frame edge), so the box is the union over sampled poses.
    poses = [None] + [(n, k / 8) for n in ANIMS for k in range(8)]
    for spec in poses:
        rig.reset()
        if spec:
            ANIMS[spec[0]][3](rig, spec[1])
        bpy.context.view_layer.update()
        for ob in rig.vox:
            for v in ob.data.vertices:
                p = inv @ (ob.matrix_world @ v.co)
                xs.append(p.x)
                ys.append(p.y)
    rig.reset()
    bpy.context.view_layer.update()
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    w, h = (maxx - minx) * (1 + 2 * pad), (maxy - miny) * (1 + pad)
    scale = max(w, h * FW / FH)                      # ortho_scale = frame WIDTH
    fh = scale * FH / FW
    cx = (minx + maxx) / 2
    cy = miny + fh / 2 - 0.05 * fh
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = scale
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    co.matrix_world = R
    co.location = R @ Vector((cx, cy, 30.0))
    sc.camera = co
    sc.render.resolution_x, sc.render.resolution_y = FW, FH
    cam_loc = co.location.copy()
    return cam_loc


def to_webp(frames, path):
    n = len(frames)
    rows = (n + COLS - 1) // COLS
    h, w = frames[0].shape[:2]
    sheet = np.zeros((rows * h, COLS * w, 4), dtype=np.float32)
    for i, f in enumerate(frames):
        r_, c_ = divmod(i, COLS)
        y = (rows - 1 - r_) * h            # image rows are bottom-up
        sheet[y:y + h, c_ * w:(c_ + 1) * w, :] = f
    img = bpy.data.images.new('sheet', COLS * w, rows * h, alpha=True)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    img.pixels = sheet.ravel().tolist()
    img.file_format = 'WEBP'
    img.filepath_raw = path
    scn = bpy.context.scene
    scn.render.image_settings.quality = 90
    img.save()
    bpy.data.images.remove(img)


def load_rgba(path):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return a


def render_frame(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


CUTS = []


def edge_hits(frame, thr=0.05):
    """Edges (T/B/L/R) of the cell that visible art touches. The ground shadow
    may fade out at the bottom, so B only counts for solid pixels."""
    a = frame[:, :, 3]
    e = ''
    if a[-1, :].max() > thr: e += 'T'       # rows are bottom-up
    if a[0, :].max() > 0.5: e += 'B'
    if a[:, 0].max() > thr: e += 'L'
    if a[:, -1].max() > thr: e += 'R'
    return e


def run_anims(rig, names, table, tag, out, tmp, meta_anims):
    for name in names:
        n, fps, loop, pose = table[name]
        frames = []
        for i in range(n):
            rig.reset()
            pose(rig, i / n)
            bpy.context.view_layer.update()
            p = os.path.join(tmp, f'{tag}_{name}_{i:02d}.png')
            render_frame(p)
            frames.append(load_rgba(p))
            os.remove(p)
            print('frame', tag, name, i, flush=True)
        cut = [(i, e) for i, f in enumerate(frames) if (e := edge_hits(f))]
        if cut:
            print(f'WARNING {tag}_{name}: art touches the cell edge (cut off): '
                  f'{cut}', flush=True)
            CUTS.append(f'{tag}_{name}')
        sheet = f'{tag}_{name}.webp'
        to_webp(frames, os.path.join(out, sheet))
        meta_anims[name] = {'sheet': sheet, 'frames': n, 'fps': fps, 'loop': loop}


def set_pose(rig, spec):
    rig.reset()
    if spec:
        name, t = spec.split(":")
        ANIMS[name][3](rig, float(t))
        bpy.context.view_layer.update()


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, default=0)
    ap.add_argument('--out', required=True)
    ap.add_argument('--views', default='front,back,sidel,sider,map')
    ap.add_argument('--anims', default='idle,attack,hurt')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--still')
    ap.add_argument('--view', default='front')
    ap.add_argument('--pose', help='still only: name:t, e.g. attack:0.45')
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, '_frames')
    os.makedirs(tmp, exist_ok=True)

    for view in ([a.view] if a.still else a.views.split(',')):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = Rig(a.stage)
        engine(a.samples)
        if view == 'map':
            k = MAP_K[a.stage]
            shadow_catcher(3.4 * k)
            contact_shadow(a.stage)
            lights(Vector((1, 1, 1)) * 5, Vector((0, 0, 0)), 0.3)
            rb.frame(1.7 * k, 1.7 * k, 5 / k, 0.80, 0.0, fit=False)
            sc = bpy.context.scene
            W, H = sc.render.resolution_x, sc.render.resolution_y
            meta = {'monster': 'glimmergnaw', 'stage': a.stage, 'view': 'map',
                    'cols': COLS, 'frame_w': W, 'frame_h': H,
                    'headings': {'se': '+x', 'ne': '+y', 'nw': '-x', 'sw': '-y'},
                    'anims': {}}
            for h, yaw in HEADINGS.items():
                rig.face.rotation_euler = (0, 0, math.radians(yaw))
                if a.still:
                    set_pose(rig, a.pose)
                    render_frame(os.path.abspath(a.still))
                    return
                tbl = {'walk': ANIMS['walk'], 'idle': MAP_IDLE}
                run_anims(rig, ['walk', 'idle'], tbl, h, out, tmp,
                          meta['anims'].setdefault(h, {}))
            with open(os.path.join(out, 'meta_map.json'), 'w') as f:
                json.dump(meta, f, indent=2)
        else:
            shadow_catcher(5.0)
            contact_shadow(a.stage)
            cam_loc = battle_camera(rig, VIEWS[view])
            lights(cam_loc, Vector((0, 0, 0.5)), 0.25)
            if a.still:
                set_pose(rig, a.pose)
                render_frame(os.path.abspath(a.still))
                return
            meta = {'monster': 'glimmergnaw', 'stage': a.stage, 'view': view,
                    'frame_w': FW, 'frame_h': FH, 'cols': COLS, 'anims': {}}
            run_anims(rig, a.anims.split(','), ANIMS, view, out, tmp, meta['anims'])
            with open(os.path.join(out, f'meta_{view}.json'), 'w') as f:
                json.dump(meta, f, indent=2)
    if CUTS:
        print('CUT-OFF ART in:', ', '.join(CUTS), '- widen battle_camera pad')
        sys.exit(2)
    print('done', out)


if __name__ == '__main__':
    main()
