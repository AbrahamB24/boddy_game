"""Glimmergnaw, three stages, as VOXELS (draft sprites, same recipe as thunderwake_voxel).

    blender --background --python tool/blender/glimmergnaw_voxel.py -- \
        --stage 0 --out docs/renders/glimmergnaw_s0.png [--samples 64]

An upright beaver-like gnawer that grows crystals of light.
stage 0 GLIMMERGNAW  pearl-cream pup, huge head, one little crystal
stage 1 BOLTSTREAK   champagne-gold, standing tall, crystal crest and cheeks
stage 2 LIGHTHUNTER  bronze, broad and armoured, a lance-horn and a blazing crest
The family: round ears, big eyes with a glint, buck teeth, flat paddle tail with
crystals, an ice-blue crystal accent that grows and glows more each stage.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

PAL = {
    0: dict(body='#f1e6cf', head='#f8f0df', belly='#fffaf0', limb='#d6bf94', cream='#c9a672',
            crys='#6fe0ff', crysd='#2fb0ec'),
    1: dict(body='#e4c883', head='#edd699', belly='#faefcc', limb='#ab8444', cream='#a67c45',
            crys='#6fe0ff', crysd='#2fb0ec'),
    2: dict(body='#97703c', head='#a9804a', belly='#e6cf9c', limb='#684925', cream='#6e4a26',
            crys='#9defff', crysd='#4cc8f4'),
}
GLOW = {0: 0.10, 1: 0.20, 2: 0.40}
# variant knobs (see VARIANTS): width of the stance, limb thickness, head size,
# mesh smoothness, whether the arms hold a crystal log up to the teeth
P = dict(bw=1.0, lr=1.0, head=1.0, seg=24, rings=16, gnaw=False)
CAM = {0: (2.1, 0.55), 1: (2.6, 0.82), 2: (2.9, 0.88)}      # ortho scale, target z


def build(stage):
    flat = tw.flat
    p = PAL[stage]
    M = {k: flat(k, v) for k, v in p.items() if not k.startswith('crys')}
    M['crys'] = flat('crys', p['crys'], p['crysd'], GLOW[stage])
    M['crysd'] = flat('crysd', p['crysd'], p['crysd'], GLOW[stage] * 0.6)
    M['ivory'] = flat('ivory', '#fff6dc')
    M['tooth'] = flat('tooth', '#fff6dc')            # same ivory as the claws, clear of the darker muzzle
    M['dark'] = flat('dark', '#141830')
    M['white'] = flat('white', '#ffffff', '#ffffff', 1.0)
    M['plate'] = flat('plate', '#7a5a34')
    objs = []
    G = ['body']

    body_m = ('body', 'belly', 'plate', 'limb')
    in_face = [False]

    tw.PAINT = []

    def E(x, y, z, rx, ry, rz, m, tilt=None):
        if m == 'belly' and G[0] == 'body':
            # painted, not modelled: a protruding belly shell casts a dark shadow line
            k = 1.2
            tw.PAINT.append(('body', (x, y * P['bw'], z), (rx * k, ry * k * P['bw'], rz * k),
                             'belly', 'body'))
            return
        if G[0].startswith('arm_') and m in ('plate', 'head'):
            # shoulder cap: one fur colour with the arm - a second colour interleaving with the
            # limb where the meshes cross showed up as dark blotches
            m = 'limb'
        if not in_face[0] and m in body_m:
            y *= P['bw']
            if m == 'limb':
                rx, ry = rx * P['lr'], ry * P['lr']
        if m == 'head' and rx > 0.2:
            rx, ry, rz = rx * P['head'], ry * P['head'], rz * P['head']
        objs.append(K.ellipsoid(x, y, z, rx, ry, rz, M[m], seg=P['seg'],
                                rings=P['rings'], tilt=tilt))
        objs[-1]['grp'] = G[0]

    def limb(p0, p1, r0, r1, m, seg=14):
        if not in_face[0]:
            p0 = (p0[0], p0[1] * P['bw'], p0[2])
            p1 = (p1[0], p1[1] * P['bw'], p1[2])
            if m == 'limb':
                r0, r1 = r0 * P['lr'], r1 * P['lr']
        seg = min(seg, P['seg'] // 2 + 2)
        a, b = Vector(p0), Vector(p1)
        d = b - a
        c = K.cyl(0, 0, 0, r0, r1, d.length, M[m], seg=seg, smooth=True)
        c.location = a
        c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        objs.append(c)
        c['grp'] = G[0]

    def crystal(x, y, z, length, r, lean=0.0, side=0.0, m='crys'):
        """A faceted shard: wide near the base, pointed, leaning back/out."""
        limb((x, y, z), (x - math.sin(lean) * length, y + side * length,
                         z + math.cos(lean) * length), r, 0.016, m, seg=6)

    def face(hx, hz, hs, brows, teeth=0.11):
        in_face[0] = True
        try:
            _face(hx, hz, hs, brows, teeth)
        finally:
            in_face[0] = False

    def _face(hx, hz, hs, brows, teeth):
        ex, ez = hx + 0.28 * hs, hz + 0.06 * hs
        for sg in (-1, 1):
            k = 0.6                                  # eyes: 60 % of the old size
            E(ex + 0.03 * hs, sg * 0.19 * hs, ez, 0.125 * hs * k, 0.11 * hs * k,
              0.14 * hs * k, 'dark')
            # glint: PAINTED on the eye surface (flush, never sticks out, cannot vanish)
            cx, cy, cz = ex + 0.03 * hs, sg * 0.19 * hs, ez
            tw.PAINT.append(('head', (cx + 0.125 * hs * k * 0.80, cy - sg * 0.01 * hs, cz + 0.14 * hs * k * 0.55),
                             (0.013 * hs, 0.013 * hs, 0.013 * hs), 'white', 'dark'))
            if brows:
                E(ex - 0.02, sg * 0.17 * hs, ez + 0.17 * hs, 0.15 * hs, 0.04 * hs,
                  0.035 * hs, 'dark', (math.radians(-sg * 20), 0.2,
                                       math.radians(sg * 14)))
            E(hx - 0.02, sg * 0.23 * hs, hz + 0.22 * hs, 0.09 * hs, 0.06 * hs,
              0.12 * hs, 'head')                                      # round ear
            E(hx - 0.02, sg * 0.23 * hs, hz + 0.22 * hs, 0.05 * hs, 0.04 * hs,
              0.07 * hs, 'belly')
            tl = teeth * hs * 0.75                                    # buck teeth: two flat
            E(hx + 0.38 * hs, sg * 0.047 * hs, hz - 0.14 * hs - tl * 0.5,   # incisors, their
              0.024 * hs, 0.047 * hs, tl, 'tooth')                    # top buried in the muzzle
        E(hx + 0.27 * hs, 0, hz - 0.10 * hs, 0.15 * hs, 0.20 * hs, 0.12 * hs, 'cream')
        E(hx + 0.41 * hs, 0, hz - 0.07 * hs, 0.045 * hs, 0.065 * hs, 0.04 * hs, 'dark')

    def claws(x, y, z, n=3, size=0.07):
        for k in range(n):
            o = (k - (n - 1) / 2) * size * 1.1
            # thick at the toe, hooking down to a sharp tip (two segments; thin cones vanish when voxelised)
            m1 = (x + size * 0.7, y + o * 1.12, z - size * 0.05)
            limb((x, y + o, z), m1, size * 0.42, size * 0.34, 'ivory', seg=8)
            limb(m1, (x + size * 1.25, y + o * 1.2, z - size * 0.55), size * 0.34, 0.0, 'ivory', seg=8)

    def side(sg):
        return 'p' if sg > 0 else 'n'

    if stage == 0:
        # cuddly pup: pear body, huge head, paws on the tummy, tiny paddle tail
        G[0] = 'body'
        E(0.00, 0, 0.42, 0.34, 0.31, 0.36, 'body')
        E(0.14, 0, 0.38, 0.22, 0.22, 0.28, 'belly')
        crystal(-0.16, 0.14, 0.72, 0.20, 0.06, 0.7, 0.2, 'crysd')
        crystal(-0.16, -0.14, 0.72, 0.20, 0.06, 0.7, -0.2, 'crysd')
        G[0] = 'head'
        E(0.20, 0, 0.90, 0.40, 0.38, 0.34, 'head')
        face(0.20, 0.90, 1.15, False)
        crystal(0.26, 0, 1.22, 0.34, 0.09, 0.15)
        crystal(0.18, 0.09, 1.20, 0.22, 0.06, 0.45, 0.2, 'crysd')
        crystal(0.18, -0.09, 1.20, 0.22, 0.06, 0.45, -0.2, 'crysd')
        for sg in (-1, 1):
            G[0] = 'leg_' + side(sg)
            E(0.14, sg * 0.18, 0.07, 0.20, 0.12, 0.08, 'limb')
            G[0] = 'arm_' + side(sg)
            E(0.36, sg * 0.12, 0.46, 0.10, 0.09, 0.10, 'limb')
            limb((0.02, sg * 0.30, 0.60), (0.30, sg * 0.20, 0.50), 0.09, 0.08, 'limb')
        G[0] = 'tail'
        E(-0.42, 0, 0.18, 0.30, 0.20, 0.05, 'limb', (0, -0.45, 0))
    elif stage == 1:
        # standing tall: shoulders, long arms, crystal crest and cheeks
        G[0] = 'body'
        E(0.00, 0, 0.88, 0.36, 0.33, 0.40, 'body')
        E(0.16, 0, 0.84, 0.24, 0.24, 0.32, 'belly')
        for i in range(3):                                         # back crest
            crystal(-0.12 - i * 0.05, 0, 1.18 - i * 0.16, 0.34 - i * 0.03, 0.08,
                    0.9 + 0.05 * i, 0.0, 'crys' if i % 2 == 0 else 'crysd')
        G[0] = 'head'
        E(0.22, 0, 1.44, 0.35, 0.33, 0.31, 'head')
        face(0.22, 1.44, 1.1, False, 0.11)
        crystal(0.28, 0, 1.70, 0.34, 0.09, 0.15)
        crystal(0.20, 0.10, 1.68, 0.24, 0.06, 0.5, 0.25, 'crysd')
        crystal(0.20, -0.10, 1.68, 0.24, 0.06, 0.5, -0.25, 'crysd')
        for sg in (-1, 1):
            G[0] = 'head'
            G[0] = 'leg_' + side(sg)
            E(-0.02, sg * 0.20, 0.42, 0.22, 0.18, 0.30, 'limb')
            E(0.14, sg * 0.20, 0.08, 0.22, 0.13, 0.09, 'limb')
            G[0] = 'arm_' + side(sg)
            E(0.0, sg * 0.36, 1.10, 0.15, 0.14, 0.15, 'head')
            limb((0.02, sg * 0.38, 1.06), (0.14, sg * 0.40, 0.86), 0.12, 0.11, 'limb')
            E(0.14, sg * 0.40, 0.86, 0.125, 0.125, 0.125, 'limb')        # elbow ball
            G[0] = 'farm_' + side(sg)                                   # forearm bends at it
            limb((0.14, sg * 0.40, 0.86), (0.26, sg * 0.42, 0.66), 0.095, 0.10, 'limb')
            E(0.30, sg * 0.42, 0.60, 0.13, 0.12, 0.13, 'limb')
            claws(0.40, sg * 0.42, 0.56)
        G[0] = 'tail'
        E(-0.50, 0, 0.46, 0.42, 0.34, 0.06, 'limb', (0, -0.45, 0))   # big flat paddle
    else:
        # mighty: broad, hunched forward, armour plates, lance-horn, blazing crest
        G[0] = 'body'
        E(0.00, 0, 0.90, 0.46, 0.44, 0.42, 'body', (0, 0.12, 0))
        E(0.20, 0, 0.84, 0.28, 0.30, 0.34, 'belly', (0, 0.12, 0))
        for i in range(4):                                         # blazing crest
            crystal(-0.10 - i * 0.06, 0, 1.28 - i * 0.13, 0.46 - i * 0.03, 0.10,
                    0.9 + 0.04 * i, 0.0, 'crys' if i % 2 == 0 else 'crysd')
        G[0] = 'head'
        E(0.28, 0, 1.40, 0.37, 0.35, 0.30, 'head')
        face(0.28, 1.40, 1.05, False, 0.12)
        crystal(0.38, 0, 1.66, 0.28, 0.10, 0.1)                     # lance-horn
        crystal(0.26, 0.12, 1.62, 0.22, 0.07, 0.5, 0.3, 'crysd')
        crystal(0.26, -0.12, 1.62, 0.22, 0.07, 0.5, -0.3, 'crysd')
        for sg in (-1, 1):
            G[0] = 'head'
            G[0] = 'leg_' + side(sg)
            E(-0.06, sg * 0.28, 0.42, 0.28, 0.23, 0.34, 'limb')
            E(0.12, sg * 0.28, 0.08, 0.26, 0.16, 0.09, 'limb')
            G[0] = 'arm_' + side(sg)
            E(0.02, sg * 0.44, 1.14, 0.25, 0.20, 0.17, 'plate', (0, 0, sg * 0.3))
            crystal(0.00, sg * 0.50, 1.22, 0.34, 0.09, 0.4, sg * 0.4)
            limb((0.04, sg * 0.50, 1.08), (0.18, sg * 0.54, 0.85), 0.17, 0.155, 'limb')
            E(0.18, sg * 0.54, 0.85, 0.17, 0.17, 0.17, 'limb')     # elbow ball
            E(0.08, sg * 0.52, 0.98, 0.19, 0.18, 0.19, 'limb')       # fills the notch between shoulder and elbow
            G[0] = 'farm_' + side(sg)                                   # forearm bends at it
            limb((0.18, sg * 0.54, 0.85), (0.32, sg * 0.58, 0.62), 0.13, 0.14, 'limb')
            E(0.38, sg * 0.58, 0.54, 0.19, 0.17, 0.19, 'limb')
            claws(0.52, sg * 0.58, 0.50, 3, 0.09)
        G[0] = 'tail'
        E(-0.62, 0, 0.58, 0.52, 0.42, 0.07, 'limb', (0, -0.45, 0))   # big flat paddle
    return objs


def build_quad():
    """A real beaver's stance: on all fours, long low body, huge paddle tail."""
    flat = tw.flat
    p = PAL[2]
    M = {k: flat(k, v) for k, v in p.items() if not k.startswith('crys')}
    M['crys'] = flat('crys', p['crys'], p['crysd'], GLOW[2])
    M['crysd'] = flat('crysd', p['crysd'], p['crysd'], GLOW[2] * 0.6)
    M['ivory'] = flat('ivory', '#fff6dc')
    M['dark'] = flat('dark', '#141830')
    M['white'] = flat('white', '#ffffff', '#ffffff', 1.0)
    objs = []

    def E(x, y, z, rx, ry, rz, m, tilt=None):
        objs.append(K.ellipsoid(x, y, z, rx, ry, rz, M[m], seg=P['seg'],
                                rings=P['rings'], tilt=tilt))

    def limb(p0, p1, r0, r1, m, seg=12):
        a, b = Vector(p0), Vector(p1)
        d = b - a
        c = K.cyl(0, 0, 0, r0, r1, d.length, M[m], seg=min(seg, P['seg'] // 2 + 2),
                  smooth=True)
        c.location = a
        c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        objs.append(c)

    def crystal(x, y, z, length, r, lean=0.0, side=0.0, m='crys'):
        limb((x, y, z), (x - math.sin(lean) * length, y + side * length,
                         z + math.cos(lean) * length), r, 0.016, m, seg=6)

    E(0.00, 0, 0.56, 0.62, 0.34, 0.32, 'body', (0, 0.10, 0))
    E(0.12, 0, 0.44, 0.42, 0.26, 0.20, 'belly', (0, 0.10, 0))
    E(-0.40, 0, 0.56, 0.34, 0.34, 0.34, 'body')
    E(0.66, 0, 0.72, 0.33, 0.30, 0.28, 'head')
    for sg in (-1, 1):
        E(0.86, sg * 0.17, 0.78, 0.10, 0.09, 0.12, 'dark')
        E(0.93, sg * 0.15, 0.83, 0.032, 0.03, 0.036, 'white')
        E(0.84, sg * 0.15, 0.94, 0.12, 0.035, 0.03, 'dark',
          (math.radians(-sg * 18), 0.2, math.radians(sg * 14)))
        E(0.58, sg * 0.26, 0.94, 0.08, 0.05, 0.11, 'head')
        E(0.58, sg * 0.26, 0.94, 0.045, 0.035, 0.065, 'belly')
        E(1.00, sg * 0.04, 0.54, 0.03, 0.04, 0.10, 'ivory')
        limb((0.38, sg * 0.24, 0.46), (0.52, sg * 0.28, 0.08), 0.12, 0.09, 'limb')
        E(0.62, sg * 0.28, 0.06, 0.16, 0.10, 0.06, 'limb')
        limb((-0.40, sg * 0.26, 0.44), (-0.50, sg * 0.30, 0.08), 0.14, 0.10, 'limb')
        E(-0.38, sg * 0.30, 0.06, 0.20, 0.11, 0.06, 'limb')
        for k in (-1, 0, 1):
            limb((0.74, sg * 0.28 + k * 0.045, 0.06), (0.82, sg * 0.28 + k * 0.05, 0.03),
                 0.022, 0.0, 'ivory', seg=6)
    E(0.88, 0, 0.62, 0.15, 0.17, 0.11, 'cream')
    E(1.01, 0, 0.66, 0.045, 0.065, 0.04, 'dark')
    E(-1.02, 0, 0.30, 0.52, 0.30, 0.06, 'limb', (0, -0.22, 0))
    for i in range(3):
        crystal(-0.92 - i * 0.2, 0, 0.36 + i * 0.05, 0.30, 0.08, 0.9)
    crystal(0.72, 0, 0.96, 0.26, 0.09, 0.1)
    crystal(0.62, 0.10, 0.94, 0.20, 0.06, 0.5, 0.3, 'crysd')
    crystal(0.62, -0.10, 0.94, 0.20, 0.06, 0.5, -0.3, 'crysd')
    for i in range(7):
        crystal(0.36 - i * 0.13, 0, 0.84 - i * 0.02, 0.40 - i * 0.025, 0.09,
                0.9, 0.0, 'crys' if i % 2 == 0 else 'crysd')
    crystal(0.56, 0.26, 0.64, 0.2, 0.06, 0.4, 0.4, 'crysd')
    return objs


# name: (builder, P overrides, voxel depth or None, style, size)
SLIM = dict(bw=0.78, lr=0.70, head=1.05)
VARIANTS = {
    'v01': ('up', {}, 8, 'cycles', 720),
    'v02': ('up', SLIM, 8, 'cycles', 720),
    'v03': ('quad', {}, 8, 'cycles', 720),
    'v04': ('up', dict(SLIM, gnaw=True), 8, 'cycles', 720),
    'v05': ('up', SLIM, None, 'cycles', 720),
    'v06': ('up', dict(SLIM, seg=7, rings=5), None, 'lowpoly', 720),
    'v07': ('up', SLIM, None, 'toon', 720),
    'v08': ('up', SLIM, 6, 'pixel', 128),
    'v09': ('up', SLIM, None, 'vinyl', 720),
    'v10': ('quad', dict(seg=40, rings=28), None, 'clay', 720),
}


def apply_style(style, objs):
    for m in bpy.data.materials:
        if m.use_nodes and 'Principled BSDF' in m.node_tree.nodes:
            b = m.node_tree.nodes['Principled BSDF']
            c = b.inputs['Base Color'].default_value
            m.diffuse_color = (c[0], c[1], c[2], 1.0)
            if style == 'vinyl':
                b.inputs['Roughness'].default_value = 0.12
                if 'Coat Weight' in b.inputs:
                    b.inputs['Coat Weight'].default_value = 1.0
            if style == 'clay':
                b.inputs['Base Color'].default_value = (0.72, 0.62, 0.50, 1)
                b.inputs['Emission Strength'].default_value = 0.0
                m.diffuse_color = (0.72, 0.62, 0.50, 1)
    if style == 'lowpoly':
        for o in objs:
            for pl in o.data.polygons:
                pl.use_smooth = False


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, default=0)
    ap.add_argument('--variant')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=64)
    ap.add_argument('--size', type=int, default=720)
    a = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    style, size, quad = 'cycles', a.size, False
    ortho, tz = CAM[a.stage]
    voxel = True
    if a.variant:
        builder, over, depth, style, size = VARIANTS[a.variant]
        P.update(over)
        quad = builder == 'quad'
        voxel = depth is not None
        if depth:
            tw.DEPTH = depth
        ortho, tz = (3.2, 0.55) if quad else CAM[2]
        a.stage = 2
    objs = build_quad() if quad else build(a.stage)
    apply_style(style, objs)
    if voxel:
        tw.voxelise(objs)
    K.lighting(sky=1.0 if style == 'clay' else 0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = ortho
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    tgt = Vector((0.0, 0.0, tz))
    co.location = tgt + Vector((5.2, -4.0, 2.8))
    co.rotation_euler = (tgt - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.film_transparent = True
    if style in ('toon', 'pixel'):
        sc.render.engine = 'BLENDER_WORKBENCH'
        sh = sc.display.shading
        sh.light = 'FLAT'
        sh.color_type = 'MATERIAL'
        sh.show_object_outline = style == 'toon'
        sh.object_outline_color = (0.10, 0.07, 0.04)
        sc.render.filter_size = 0.0 if style == 'pixel' else 1.0
        sc.view_settings.view_transform = 'Standard'
        sc.render.image_settings.file_format = 'PNG'
        sc.render.image_settings.color_mode = 'RGBA'
        sc.render.filepath = os.path.abspath(a.out)
        bpy.ops.render.render(write_still=True)
        print('wrote', a.out)
        return
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = a.samples
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    K.render(a.out)


if __name__ == '__main__':
    main()
