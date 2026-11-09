"""Glimmergnaw stage 1 / 2 on ALL FOURS, front still (pose study for a less stiff walk).

    blender --background --python tool/blender/glimmergnaw_quad.py -- \
        --stage 1 --out docs/renders/monsters/quad_s1_front.png [--samples 64]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
import glimmergnaw_voxel as gv  # noqa: E402


PIV = {}      # rig pivots (world, rest pose) filled by build_quad: used by glimmergnaw_quad_bake.py


def build_quad(stage):
    flat, p = tw.flat, gv.PAL[stage]
    big = stage == 2
    # pose-study palette: limbs only a hair darker than the body (one fur, not two colours)
    p = dict(p, **{
        0: dict(body='#ab946a', head='#b8a27a', belly='#c9b88f', limb='#9f8860', cream='#866c44'),
        1: dict(body='#ad9048', head='#bb9e5a', belly='#cdb986', limb='#a08440', cream='#775628'),
        2: dict(body='#5c4022', head='#68482a', belly='#a88c5e', limb='#523a1e', cream='#40291470'[:7]),
    }[stage])
    M = {k: flat(k, v) for k, v in p.items() if not k.startswith('crys')}
    glow = {0: 0.6, 1: 0.7, 2: 0.8}[stage]          # crystals clearly glowing (pose study)
    M['crys'] = flat('crys', '#0078e0', '#0096ff', glow)
    M['crysd'] = flat('crysd', '#0050d0', '#0066ff', glow * 0.8)
    M['ivory'] = flat('ivory', '#fff6dc')
    M['tooth'] = flat('tooth', '#ffffff', '#ffffff', 0.15)     # pure white teeth
    M['claw'] = flat('claw', '#d4c4a2')                         # claws: a warmer horn tone, not the teeth's white
    M['dark'] = flat('dark', '#141830')
    M['white'] = flat('white', '#ffffff', '#ffffff', 1.0)
    M['plate'] = flat('plate', '#7a5a34')
    objs = []
    G = ['body']
    PIV.clear()
    pup = stage == 0
    k = 1.2 if big else (0.82 if pup else 1.0)   # stage 2 broader / heavier, stage 0 a small pup
    seg, rings = 24, 16

    def E(x, y, z, rx, ry, rz, m, tilt=None):
        objs.append(K.ellipsoid(x, y, z, rx, ry, rz, M[m], seg=seg, rings=rings, tilt=tilt))
        objs[-1]['grp'] = G[0]

    def limb(p0, p1, r0, r1, m, seg_=12):
        a, b = Vector(p0), Vector(p1)
        d = b - a
        c = K.cyl(0, 0, 0, r0, r1, d.length, M[m], seg=seg_, smooth=True)
        c.location = a
        c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        objs.append(c)
        c['grp'] = G[0]

    def crystal(x, y, z, length, r, lean=0.0, side=0.0, m='crys', fur='body'):
        limb((x, y, z), (x - math.sin(lean) * length, y + side * length,
                         z + math.cos(lean) * length), r, 0.012, m, 6)

    def claws(x, y, z, n=3):
        """Well-defined claws: thick at the toe, hooking down to a sharp tip.
        Two segments each, a visible gap between claws, pale ivory against the fur."""
        for c in range(n):
            o = (c - (n - 1) / 2) * 0.075
            # one chunky cone per claw (no thin joints that voxelise into specks), hooking down
            limb((x, y + o, z + 0.004), (x + 0.105, y + o * 1.15, z - 0.04), 0.032, 0.015, 'claw', 8)

    # body: long, low, slightly raised at the shoulders; belly painted-look ellipsoid
    E(0.00, 0, 0.58, 0.62 * k, 0.34 * k, 0.32 * k, 'body', (0, 0.10, 0))
    E(0.12, 0, 0.46, 0.42 * k, 0.26 * k, 0.20 * k, 'belly', (0, 0.10, 0))
    E(-0.40, 0, 0.56, 0.34 * k, 0.34 * k, 0.34 * k, 'body')
    # head carried low and forward, like a real beaver
    hx, hz, hs = (0.58, 0.58, 1.2) if pup else (0.68, 0.70, 1.0)
    EO = 0.11 if pup else 0.0          # pup: eyes sit further out on the big round head
    G[0] = 'head'
    E(hx, 0, hz, 0.33 * hs, 0.30 * hs, 0.28 * hs, 'head')
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        G[0] = 'head'
        E(hx + 0.20 * hs + EO, sg * 0.17, hz + 0.07, 0.065 * hs, 0.055 * hs, 0.075 * hs, 'dark')
        E(hx + 0.26 * hs + EO, sg * 0.155, hz + 0.11, 0.012, 0.012, 0.014, 'white')
        E(hx - 0.08, sg * 0.25, hz + 0.20, 0.08, 0.05, 0.11, 'head')        # round ear
        E(hx - 0.08, sg * 0.25, hz + 0.20, 0.045, 0.035, 0.065, 'belly')
        E(hx + 0.30 * hs, sg * 0.04, hz - 0.17, 0.024, 0.04, 0.09, 'tooth')      # buck teeth
        # front legs: shoulder -> elbow -> forearm -> paw, slightly splayed
        fy = 0.30 * k
        r = 0.12 * k
        # front leg: shoulder -> elbow (back/out) -> wrist (forward) -> paw. A ball at every
        # joint and the radii overlap, so the bend is one smooth mass, not two stacked tubes.
        S, Eb, W = (0.34, sg * fy * 0.8, 0.54), (0.28, sg * (fy + 0.07), 0.30), (0.45, sg * (fy + 0.03), 0.11)
        PIV.update({'arm_' + sd: S, 'farm_' + sd: Eb})
        G[0] = 'arm_' + sd
        E(S[0], S[1], S[2], r * 1.15, r * 1.05, r * 1.2, 'limb')            # shoulder muscle
        limb(S, Eb, r * 1.05, r * 0.85, 'limb', 14)
        E(Eb[0], Eb[1], Eb[2], r * 0.9, r * 0.9, r * 0.9, 'limb')           # elbow
        G[0] = 'farm_' + sd
        limb(Eb, W, r * 0.85, r * 0.6, 'limb', 14)                          # forearm tapers to the wrist
        E(W[0], W[1], W[2], r * 0.62, r * 0.62, r * 0.62, 'limb')           # wrist
        E(0.56, sg * (fy + 0.03), 0.065, 0.17, 0.105, 0.065, 'limb', (0, -0.12, 0))   # paw
        claws(0.70, sg * (fy + 0.03), 0.07)
        # hind leg: big thigh -> knee (forward) -> ankle (back) -> long foot
        hr = 0.15 * k
        Hp, Kn, An = (-0.38, sg * 0.26 * k, 0.50), (-0.20, sg * 0.33 * k, 0.30), (-0.40, sg * 0.31 * k, 0.12)
        PIV.update({'leg_' + sd: Hp, 'sfarm_' + sd: Kn})
        G[0] = 'leg_' + sd
        E(Hp[0], Hp[1], Hp[2], hr * 1.5, hr * 1.2, hr * 1.5, 'limb')        # thigh
        limb(Hp, Kn, hr * 1.1, hr * 0.8, 'limb', 14)
        E(Kn[0], Kn[1], Kn[2], hr * 0.8, hr * 0.8, hr * 0.8, 'limb')        # knee
        G[0] = 'sfarm_' + sd
        limb(Kn, An, hr * 0.8, hr * 0.55, 'limb', 14)                       # shin
        E(An[0], An[1], An[2], hr * 0.58, hr * 0.58, hr * 0.58, 'limb')     # ankle
        E(-0.30, sg * 0.31 * k, 0.06, 0.22, 0.11, 0.06, 'limb', (0, -0.10, 0))
        claws(-0.12, sg * 0.31 * k, 0.07)
    G[0] = 'head'
    PIV['head'] = (hx - 0.22 * hs, 0, hz - 0.12)
    PIV['tail'] = (-0.70 * k, 0, 0.42)
    E(hx + 0.22 * hs, 0, hz - 0.08 * hs, 0.15, 0.17, 0.11, 'cream')            # muzzle
    E(hx + 0.35 * hs, 0, hz - 0.05 * hs, 0.045, 0.06, 0.04, 'dark')             # nose
    # paddle tail on the floor + crystals
    G[0] = 'tail'
    E(-1.02, 0, 0.30, 0.52 * k, 0.30 * k, 0.06, 'limb', (0, -0.22, 0))
    for i in range(3 if big else (1 if pup else 2)):
        crystal(-0.92 - i * 0.2, 0, 0.36 + i * 0.05, 0.30, 0.08, 0.9, fur='limb')
    # head crystals
    G[0] = 'head'
    crystal(hx + 0.06, 0, hz + 0.26, 0.30 if big else 0.24, 0.09, 0.1, fur='head')
    crystal(hx - 0.04, 0.10, hz + 0.24, 0.20, 0.06, 0.5, 0.3, 'crysd', 'head')
    crystal(hx - 0.04, -0.10, hz + 0.24, 0.20, 0.06, 0.5, -0.3, 'crysd', 'head')
    # back crest
    G[0] = 'body'
    for i in range(6 if big else (2 if pup else 4)):
        crystal(0.36 - i * 0.14, 0, 0.78 + 0.12 * k, (0.36 if big else 0.28) - i * 0.02, 0.09,
                0.9, 0.0, 'crys' if i % 2 == 0 else 'crysd')
    return objs


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, default=1)
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=64)
    ap.add_argument('--size', type=int, default=720)
    ap.add_argument('--depth', type=int, default=8)          # voxel grid: 8 = 0.0156, 9 = 0.0078
    a = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.DEPTH = a.depth
    objs = build_quad(a.stage)
    tw.voxelise(objs)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((0.6, 0.5, 0.7)))
    for ob in bpy.data.objects:
        if ob.type == 'LIGHT' and ob.data.type == 'SUN':
            ob.data.use_shadow = False          # self-shadows show as black blotches on voxel steps
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = 2.3 if a.stage == 0 else 2.6
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    tgt = Vector((0.0, 0.0, 0.55))
    co.location = tgt + Vector((5.0, 1.3, 1.8))          # from the front, a touch to the side, slightly above
    co.rotation_euler = (tgt - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = a.size
    sc.render.film_transparent = True
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = a.samples
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    K.render(a.out)


if __name__ == '__main__':
    main()
