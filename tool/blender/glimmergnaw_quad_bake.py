"""Glimmergnaw on ALL FOURS: rigid-voxel rig, poses and sprite-sheet bake.

    blender --background --python tool/blender/glimmergnaw_quad_bake.py -- \
        --stage 2 --out docs/renders/monsters/glimmergnaw_quad_s2 \
        [--views front,back,sidel,sider,map] [--anims idle,attack,hurt] [--samples 24] \
        [--still out.png --view sidel --pose walk:0.25]

Reuses everything of glimmergnaw_bake.py (cameras, lights, sheet layout, map headings) and only
swaps the creature: the quadruped from glimmergnaw_quad.py, cut into rigid parts -
body, head, tail and FOUR two-part legs (upper + lower, jointed at elbow / knee):
    arm_p/n  front upper leg   (pivot = shoulder)      farm_p/n   front lower leg (elbow)
    leg_p/n  hind upper leg    (pivot = hip)           sfarm_p/n  hind lower leg  (knee)
Rotations are degrees about WORLD axes of the pivot; the creature faces +x:
    rot y < 0 : a leg swings FORWARD; a lower leg: rot y > 0 folds the foot BACK/up
    rot y > 0 : head / body tips forward (nod down)      rot z : yaw (tail wag)
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import glimmergnaw_quad as gq  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

PARENT = {'farm_p': 'arm_p', 'farm_n': 'arm_n', 'sfarm_p': 'leg_p', 'sfarm_n': 'leg_n'}
curve = gb.curve


class QRig(gb.Rig):
    def __init__(self, stage):
        self.stage = stage
        tw.SMOOTH_MATS = True
        tw.DEPTH = 8                      # the voxel size the user signed off (0.0156)
        tw.PAINT = []
        objs = gq.build_quad(stage)
        piv_world = dict(gq.PIV)
        groups = {}
        for o in objs:
            groups.setdefault(o['grp'], []).append(o)
        self.face = bpy.data.objects.new('face', None)
        self.root = bpy.data.objects.new('root', None)
        for e in (self.face, self.root):
            bpy.context.scene.collection.objects.link(e)
        self.root.parent = self.face
        self.piv, self.base, self.vox = {}, {}, []
        for name in sorted(groups, key=lambda n: n in PARENT):        # upper legs before lower
            vox = tw.voxelise(groups[name])
            vox.name = 'vox_' + name
            self.vox.append(vox)
            if name == 'body':
                vox.parent = self.root
                continue
            piv = bpy.data.objects.new('piv_' + name, None)
            bpy.context.scene.collection.objects.link(piv)
            world = Vector(piv_world[name])
            if name in PARENT:
                up = PARENT[name]
                piv.parent = self.piv[up]
                piv.location = world - Vector(piv_world[up])
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

    def elbow(self, side, arm_rot):          # joints are posed explicitly in the quad poses
        pass


# ── poses ─────────────────────────────────────────────────────
FRONT = {'p': ('arm_p', 'farm_p'), 'n': ('arm_n', 'farm_n')}
HIND = {'p': ('leg_p', 'sfarm_p'), 'n': ('leg_n', 'sfarm_n')}
CHAR = {0: dict(sway=1.0, hit=0.8), 1: dict(sway=0.8, hit=1.0), 2: dict(sway=0.55, hit=1.3)}


def leg(r, pair, swing, flex=0.0, side=0.0):
    """swing > 0 = forward, flex > 0 = lower leg folds back, side = splay about x."""
    up, lo = pair
    r.move(up, rot=(side, -swing, 0))
    r.move(lo, rot=(0, flex, 0))


def pose_idle(r, t):
    s = 2 * math.pi * t
    st = r.stage
    c = CHAR[st]['sway']
    br = math.sin(s)
    r.move('root', d=(0, 0, 0.008 * br), rot=(0, 0.8 * br * c, 1.5 * math.sin(s) * c))
    r.move('head', rot=(0, 3 * math.sin(s + 0.8), 9 * math.sin(s) * c))
    r.move('tail', rot=(0, 2 * math.sin(s), 16 * math.sin(s + 0.6)))
    for sd in 'pn':
        leg(r, FRONT[sd], 0)
        leg(r, HIND[sd], 0)
    r.glow(0.15 + 0.15 * math.sin(s) * (1 + st))
    if st == 0:             # the pup sits up a bit and waves a paw slowly
        w = curve(t, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)])
        r.move('root', d=(0, 0, 0.008 * br), rot=(0, -4 * w, 0))
        leg(r, FRONT['p'], 38 * w + 6 * w * math.sin(2 * s), 62 * w)
        r.move('head', rot=(0, -6 * w, 8 * math.sin(s) * c))
    elif st == 1:           # sniffs, looks around, shifts a paw
        r.move('head', rot=(0, 6 * math.sin(2 * s), 16 * math.sin(s)))
        leg(r, FRONT['n'], 6 * max(0, math.sin(s)), 14 * max(0, math.sin(s)))
    else:                   # heavy breathing, one paw scrapes the ground
        sc = curve(t, [(0, 0), (0.2, 1), (0.8, 1), (1, 0)])
        r.move('root', d=(0, 0, 0.014 * br), rot=(0, 1.2 * br, 0))
        leg(r, FRONT['p'], 18 * sc + 10 * sc * math.sin(3 * s), 30 * sc)
        r.move('head', rot=(0, 5 * sc, 4 * math.sin(s)))


def pose_walk(r, t):
    """Diagonal walk: front-right with hind-left, then the other pair, half a cycle later."""
    s = 2 * math.pi * t
    st = r.stage
    fa, ha = (22, 24, 20)[st], (20, 22, 18)[st]
    r.move('root', d=(0, 0, 0.022 * math.cos(2 * s) - 0.004),
           rot=(2.5 * math.sin(s), (1.2 + 1.0 * st * 0.3) * math.cos(2 * s), 3.0 * math.sin(s)))
    for sd, ph in (('p', 0.0), ('n', math.pi)):           # front p + hind n | front n + hind p
        a = s + ph
        sw, lift = math.sin(a), max(0.0, math.cos(a))
        leg(r, FRONT[sd], fa * sw, 46 * lift ** 1.2 + 8 * max(0.0, -sw))
        b = s + ph + math.pi
        sw2, lift2 = math.sin(b), max(0.0, math.cos(b))
        leg(r, HIND[sd], ha * sw2, 50 * lift2 ** 1.2 + 6 * max(0.0, -sw2))
    r.move('head', rot=(0, 1.5 + 3 * math.cos(2 * s), -6 * math.sin(s)))
    r.move('tail', rot=(0, 3 * math.cos(2 * s), 15 * math.sin(s + 0.5)))
    r.glow(0.1)


def pose_attack(r, t):
    st = r.stage
    h = CHAR[st]['hit']
    wind = curve(t, [(0, 0), (0.30, 1), (0.42, 0), (1, 0)])
    hit = curve(t, [(0, 0), (0.30, 0), (0.48, 1), (0.62, 0.8), (1, 0)])
    if st == 0:             # crouch, then a hopping bite
        r.move('root', d=(0.16 * hit, 0, 0.05 * hit * (1 - hit) * 4 - 0.02 * wind),
               rot=(0, -5 * wind + 8 * hit, 0))
        r.move('head', d=(0.08 * hit, 0, 0), rot=(0, -12 * wind + 26 * hit, 0))
        for sd in 'pn':
            leg(r, FRONT[sd], -10 * wind + 26 * hit, 20 * wind + 24 * hit)
            leg(r, HIND[sd], 8 * wind - 22 * hit, 28 * wind + 14 * hit)
        r.move('tail', rot=(0, 0, -24 * hit))
    elif st == 1:           # rears the right paw and rakes across
        r.move('root', d=(0.18 * hit, 0, 0), rot=(0, -6 * wind + 8 * hit, 8 * wind - 14 * hit))
        r.move('head', d=(0.08 * hit, 0, 0), rot=(0, -8 * wind + 16 * hit, 0))
        leg(r, FRONT['p'], 80 * wind - 10 * hit, 70 * wind + 10 * hit,
            side=-20 * wind + 35 * hit)
        leg(r, FRONT['n'], -6 * wind + 10 * hit, 12 * wind)
        for sd in 'pn':
            leg(r, HIND[sd], 6 * wind - 14 * hit, 18 * wind + 10 * hit)
        r.move('tail', rot=(0, 0, 30 * hit - 14 * wind))
    else:                   # rears up on the hind legs, then both paws crash down
        tilt = -24 * wind + 12 * hit
        lift = 0.34 * math.sin(math.radians(abs(tilt))) if tilt < 0 else 0.0
        r.move('root', d=(0.20 * hit, 0, 0.05 + lift - 0.06 * hit if wind > 0.01 else -0.05 * hit),
               rot=(0, tilt, 0))
        r.move('head', d=(0.06 * hit, 0, 0), rot=(0, -6 * wind + 18 * hit, 0))
        for sd in 'pn':
            leg(r, FRONT[sd], 70 * wind - 14 * hit, 80 * wind - 6 * hit, side=(-12 if sd == 'p' else 12) * wind)
            leg(r, HIND[sd], 4 * wind - 10 * hit, 14 * wind + 6 * hit)
        r.move('tail', rot=(0, -10 * hit, -20 * hit))
    r.glow(1.2 * wind * h + 2.0 * hit * h)


def pose_hurt(r, t):
    hit = curve(t, [(0, 0), (0.15, 1), (0.40, 0.5), (0.70, 0.12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    r.move('root', d=(-0.10 * hit, 0.01 * wob, 0.01 * hit), rot=(0, -8 * hit, 4 * wob))
    r.move('head', d=(-0.04 * hit, 0, 0), rot=(0, -20 * hit, 10 * wob))
    for sd in 'pn':
        leg(r, FRONT[sd], -12 * hit, 20 * hit)
        leg(r, HIND[sd], 10 * hit, 22 * hit)
    r.move('tail', rot=(0, -6 * hit, 25 * hit))
    r.flash(0.9 if t < 0.12 else (0.45 if t < 0.28 else 0.0))


def install():
    gb.Rig = QRig
    gb.ANIMS.update({'idle': (16, 12, True, pose_idle), 'attack': (14, 16, False, pose_attack),
                     'hurt': (10, 14, False, pose_hurt), 'walk': (8, 10, True, pose_walk)})
    gb.MAP_IDLE = (8, 8, True, pose_idle)
    orig = gb.contact_shadow

    def wide_shadow(stage, k=1.0):            # the quadruped is long, not tall
        ob = orig(stage, k)
        rx, ry = {0: (0.85, 0.42), 1: (1.05, 0.50), 2: (1.25, 0.60)}[stage]
        ob.scale = (rx * k, ry * k, 1)
        ob.location = (-0.14, 0, 0.004)
        return ob
    gb.contact_shadow = wide_shadow


if __name__ == '__main__':
    install()
    gb.main()
