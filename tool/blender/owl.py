"""Owl line (3 stages, right-hand variants of the user's turnaround sheet), voxel style.

    blender --background --python tool/blender/owl.py -- --out docs/renders/monsters/owl [--stages 0,1,2] [--views front,side,back,q]

Axes: x = forward (head), y = sideways, z = up. Every stage is built at height ~1.0 (ear / horn tip).
Eyes: phoenix recipe (dark eye, light patch on the outer side = the face disc, brow ridge where the sheet has one).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phoenix as ph  # noqa: E402
import phoenix3 as p3  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

V = Vector
SPREAD = False                                                  # stage 2 wings: folded (rest pose) or spread (animation pose)


def foot(b, x, y, s, toes=3, claw=True, mat='foot'):
    """Perching foot: pad + toes fanning forward, dark claws."""
    E = b.E
    E(x + .02 * s, y, .02 * s, .05 * s, .05 * s, .02 * s, mat)
    for i in range(toes):
        a = (i - (toes - 1) / 2) * .55
        tx, ty = x + .115 * s * math.cos(a), y + .115 * s * math.sin(a)
        b.L((x + .02 * s, y, .022 * s), (tx, ty, .018 * s), .026 * s, .018 * s, mat, seg=6)
        if claw:
            E(tx + .02 * s, ty, .012 * s, .016 * s, .010 * s, .010 * s, 'claw')


def eyes(b, c, k, wy=.24, tilt=.25, bk=1.0, bz=.095, patch=True):
    """Phoenix eye recipe (as face() in phoenix3.py): dark eye, light patch on the outer side, brow ridge above.
    c = (x, y, z) of the +y eye; k scales the recipe to the head."""
    E = b.E
    ex, ey, ez = c
    for sg in (-1, 1):
        b.grp = 'eye_' + ('p' if sg > 0 else 'n')
        E(ex, sg * ey, ez, .055 * k, .072 * k, .080 * k, 'dark')
        E(ex + .045 * k, sg * (ey - .018 * k), ez + .05 * k, .016 * k, .016 * k, .016 * k, 'white')             # one highlight voxel
        if patch:
            E(ex - .005 * k, sg * (ey + wy * .30), ez + .005 * k, .040 * k, .062 * k, .070 * k, 'eyewhite')
        b.grp = 'head'
        E(ex - .02 * k, sg * (ey + .02), ez + bz * k, .06 * k, .11 * k * (.9 if bk < 1 else 1), .034 * k * bk, 'brow', (sg * tilt, 0, 0))


def horn(b, base, mid, tip, r, mats, sg):
    """Tapered curved ear tuft: root colour, mid colour, coloured tip."""
    p0, pm, pt = [V((p[0], sg * p[1], p[2])) for p in (base, mid, tip)]
    p1 = pm + (pt - pm) * .55
    b.L(tuple(p0), tuple(pm), r, r * .78, mats[0], seg=8)
    b.L(tuple(pm), tuple(p1), r * .78, r * .5, mats[1], seg=8)
    b.L(tuple(p1), tuple(pt), r * .5, r * .12, mats[2], seg=8)


def tuft(b, base, d, ln, w, mats, sg, norm=V((1, 0, 0)), cut=(.5, .76)):
    b.gfeather2(V((base[0], sg * base[1], base[2])), V((d[0], sg * d[1], d[2])), ln, w, mats, norm, cut)


# ── stage 0: round baby owl ────────────────────────────────────────────────────────────────────
def stage0(b):
    b.grp = 'body'
    E, L = b.E, b.L
    E(-.02, 0, .27, .27, .29, .26, 'body')                       # body egg, blue top
    E(.02, 0, .20, .25, .28, .19, 'body2')                       # purple belly
    for sg in (-1, 1):                                          # pale V-shaped chest tuft (two chevron rows)
        E(.225, sg * .075, .36, .022, .10, .035, 'chest', (sg * -.6, 0, 0))
        E(.235, sg * .055, .29, .020, .075, .030, 'chest', (sg * -.6, 0, 0))
    b.grp = 'head'
    h, hr = (.0, 0, .685), (.27, .30, .25)
    E(*h, *hr, 'head')
    for sg in (-1, 1):                                          # pale face disc around each eye
        E(.14, sg * .135, .67, .15, .155, .19, 'disc')
    E(.20, 0, .67, .08, .05, .12, 'disc')
    eyes(b, (.262, .125, .675), 1.05, tilt=.05, bk=.15, bz=.14)
    L((.27, 0, .625), (.345, 0, .585), .042, .012, 'beak', seg=8)       # small orange beak
    for sg in (-1, 1):                                          # ear tufts: blue root, pink tip
        b.grp = 'head'
        horn(b, (.0, .19, .90), (-.01, .21, .98), (-.03, .25, 1.10), .065, ("tuftb", "tuftb", "pink"), sg)
        horn(b, (-.05, .19, .90), (-.07, .22, .96), (-.11, .25, 1.04), .04, ("tuftb", "tuftb", "pink"), sg)
        b.grp = 'wing_' + ('p' if sg > 0 else 'n')
        # wing nub with three tips
        E(-.04, sg * .295, .30, .13, .04, .16, 'wing', (0, .25, sg * .1))
        for i in range(3):
            tuft(b, (-.10 - .02 * i, .285, .35 - .04 * i), (-.9, .08, -.45 - .1 * i), .22 - .02 * i, .05, ('wing', 'wing', 'wing2'), sg, V((0, 1, 0)))
        b.grp = 'leg_' + ('p' if sg > 0 else 'n')
        foot(b, .06, sg * .12, 1.4)
        L((.04, sg * .12, .08), (.05, sg * .12, .03), .045, .035, 'foot', seg=6)
    b.grp = 'tail'
    for i in range(3):                                          # stub tail with pale tip
        b.gfeather2(V((-.26, (i - 1) * .05, .12)), V((-1, (i - 1) * .22, -.20)), .17, .05, ('body2', 'body2', 'tail'), V((0, 1, 0)), (.55, .78))


# ── stage 1: tall juvenile owl ─────────────────────────────────────────────────────────────────
def stage1(b):
    b.grp = 'body'
    E, L = b.E, b.L
    E(-.03, 0, .27, .25, .27, .27, 'body')
    E(.04, 0, .25, .20, .23, .22, 'body2')
    b.grp = 'head'
    h, hr = (.0, 0, .675), (.255, .29, .255)
    E(*h, *hr, 'head')
    for sg in (-1, 1):                                          # light face disc, rounded octagon on each side
        E(.10, sg * .14, .655, .17, .155, .185, 'disc')
        E(.0, sg * .272, .65, .12, .03, .14, 'disc2')       # side plate (shows in profile)
    E(.20, 0, .67, .08, .05, .12, 'disc')
    eyes(b, (.245, .125, .67), 1.0, tilt=.0, bk=.25, bz=.13)
    L((.26, 0, .625), (.345, 0, .585), .042, .012, 'beak', seg=8)
    for sg in (-1, 1):                                          # ear tufts: dark purple root, pink and cyan tips
        b.grp = 'head'
        horn(b, (.0, .17, .90), (-.01, .21, 1.00), (-.03, .27, 1.13), .06, ("tdark", "tdark", "pink"), sg)
        horn(b, (-.05, .20, .90), (-.07, .24, .98), (-.12, .29, 1.07), .04, ("tdark", "tdark", "tcyan"), sg)
        # chest chevrons and belly hearts
    b.grp = 'body'
    for i, z in enumerate((.43, .37)):
        for sg in (-1, 1):
            E(.235 - .02 * i, sg * .06, z + .012, .018, .07, .016, 'cyan', (sg * -.55, 0, 0))
    for z, wy in ((.30, .08), (.24, .06)):
        for sg in (-1, 1):
            E(.245 - (.43 - z) * .15, sg * wy, z, .016, .05, .014, 'heart', (sg * -.5, 0, 0))
    for sg in (-1, 1):
        b.grp = 'wing_' + ('p' if sg > 0 else 'n')
        # folded wing: one broad dark leaf hugging the flank, pink stripes, long cyan-tipped point trailing behind
        E(-.04, sg * .282, .36, .16, .055, .28, 'wing', (0, .12, 0))
        for i in range(3):
            E(-.05 - .03 * i, sg * .326, .46 - .09 * i, .13 - .015 * i, .012, .022, 'pink', (0, .55, 0))
        tuft(b, (-.10, .285, .24), (-1.0, .06, -.45), .44, .065, ('wing', 'wing2', 'tcyan'), sg, V((0, 1, 0)))
        tuft(b, (-.08, .285, .30), (-1.0, .06, -.30), .36, .055, ('wing', 'wing', 'pink'), sg, V((0, 1, 0)))
        b.grp = 'leg_' + ('p' if sg > 0 else 'n')
        foot(b, .07, sg * .12, 1.5)
        L((.04, sg * .12, .10), (.06, sg * .12, .035), .05, .038, 'foot', seg=6)
    b.grp = 'body'
    # back: cyan sparkle star + side marks
    for (sx, sy, sz, ax, az) in ((-.272, 0, .45, .078, .02), (-.272, 0, .45, .02, .078)):
        E(sx, sy, sz, .014, ax, az, 'cyan')
    for sg in (-1, 1):
        for zz in (.52, .38):
            E(-.258, sg * .13, zz, .012, .022, .022, 'cyan', (0, 0, .7))
    b.grp = 'tail'
    for i in range(5):                                          # tail fan with blue tips
        u = (i - 2) / 2
        tuft(b, (-.22, 0, .18), (-.5, u * .55, -1.0), .36 - .03 * abs(u), .08, ('body2', 'wing', 'tcyan'), 1, V((1, 0, 0)))


def wing_folded(b, sg):
    """Wing laid against the body (rest pose): one smooth, rounded teardrop leaf from shoulder to a soft tip, no kink."""
    E = b.E
    sd = 'p' if sg > 0 else 'n'
    b.grp = 'wing_' + sd

    def P(t):                                                                  # smooth arc down and back (x, z) + tangent
        return (.06 - .26 * t ** 1.5, .60 - .38 * t), (-.39 * t ** .5, -.38)
    for k in range(9):                                                         # rounded backing, widest in the middle
        t = k / 8
        (x, z), _ = P(t)
        r = .15 * math.sin(math.pi * (.12 + .76 * t)) + .03
        E(x - .02, sg * (.31 + .015 * math.sin(math.pi * t)), z, r * .95, .06, r * 1.15, 'wing3')
    for layer in range(2):                                                     # two staggered layers of broad, rounded feathers
        for i in range(9):
            t = (i + .5 * layer) / 9
            (x, z), (dx, dz) = P(t)
            d = (dx, .14, dz)
            w = (.11 + .06 * math.sin(math.pi * (.1 + .8 * t))) * (1 + .12 * layer)
            ln = (.28 - .05 * layer) * (1 - .9 * max(0.0, t - .5))
            mats = ('wing3', 'wing3', 'wing3') if layer == 0 else ('wing3', 'wing', 'tcyan' if i % 2 == 0 else 'tpink')
            b.grp = 'wing_' + sd if layer == 0 else 'wing_out_' + sd
            tuft(b, (x, .305 + .014 * layer, z), d, ln, w, mats, sg, V((0, 1, 0)), (.55, .82))
    b.grp = 'wing_tip_' + sd
    for j in range(3):                                                         # soft rounded tip feathers
        tuft(b, (-.17 - .02 * j, .33, .24 - .02 * j), (-.30, .10, -.90 - .1 * j), .17 - .02 * j, .10,
             ('wing3', 'wing', 'tcyan' if j % 2 == 0 else 'tpink'), sg, V((0, 1, 0)), (.55, .82))


def wing_spread(b, sg):
    """Wings spread (animation pose): arm arches up and out, two staggered fans of slim feathers."""
    b.grp = 'wing_' + ('p' if sg > 0 else 'n')
    S = V((-.01, sg * .21, .56))
    b.chain([(S.x, S.y, S.z, .05), (-.05, sg * .36, .70, .04), (-.15, sg * .56, .80, .028)], 'wing3')
    sw = math.radians(38)
    nrm = V((.35, sg * .9, .1))
    for row, (n, w, lm, mats) in enumerate(((8, .09, 1.0, ('wing', 'wing2', None)), (7, .085, .50, ('wing3', 'wing', None)))):
        for i in range(n):
            u = i / (n - 1)
            el = math.radians(30 - 92 * u + (4 if row else 0))
            d = V((-math.sin(sw) * math.cos(el), sg * math.cos(sw) * math.cos(el), math.sin(el)))
            ln = (.78 - .40 * u * u - .06 * u) * lm
            root = S + V((-.012 * row, sg * (.03 + .05 * row), -.02 * i * (1 - .3 * row)))
            tip = 'tcyan' if (i + row) % 2 == 0 else 'tpink'
            b.gfeather2(root, d, ln, w, (mats[0], mats[1], tip), nrm, (.5, .76))


# ── stage 2: dark owl, wings folded (spread=True for the animation pose) ────────────────────────────────────────────────────────
def stage2(b, spread=False):
    b.grp = 'body'
    E, L = b.E, b.L
    E(-.01, 0, .37, .25, .31, .31, 'body')                      # torso
    E(.10, 0, .37, .15, .20, .26, 'chest0')                     # lighter chest
    E(.00, 0, .14, .17, .16, .15, 'body')                       # hips
    b.grp = 'head'
    h, hr = (.06, 0, .67), (.19, .22, .17)
    E(*h, *hr, 'head')
    E(h[0] - .03, 0, h[2] + hr[2] * .12, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
    for sg in (-1, 1):                                          # face disc: pale cyan-lilac, slanted around the eyes
        E(.17, sg * .115, .675, .09, .12, .10, 'disc', (sg * .25, 0, 0))
        E(.15, sg * .17, .66, .05, .08, .09, 'disc2')
    eyes(b, (.245, .105, .675), .70, tilt=.55, bk=.9, bz=.10)
    L((.22, 0, .625), (.285, 0, .58), .034, .009, 'beak', seg=8)
    for sg in (-1, 1):                                          # long curved horns: rise outward from the head corners, tips curl in
        horn(b, (.0, .12, .80), (-.02, .23, .94), (-.03, .20, 1.07), .05, ('horn2', 'horn', 'horn'), sg)
        horn(b, (-.04, .10, .80), (-.07, .17, .89), (-.09, .15, .97), .03, ('horn2', 'horn2', 'crest'), sg)
        for j in range(3):                                      # crest streaks on the back of the head
            b.gfeather2(V((-.06, sg * (.08 + .03 * j), .74 - .03 * j)), V((-.7, sg * .25, -.25)), .18, .03, ('crest', 'wing', 'wing3'), V((0, 1, 0)))
    b.grp = 'body'
    for i in range(4):                                          # chest: layered V feathers, cyan and lilac rows
        z = .52 - .075 * i
        for sg in (-1, 1):
            E(.245 - .008 * i, sg * (.07 + .035 * i), z, .018, .11 - .004 * i, .026, 'cyan' if i % 2 == 0 else 'chest1', (sg * -.7, 0, 0))
    for sg in (-1, 1):
        (wing_spread if spread else wing_folded)(b, sg)
        b.grp = 'leg_' + ('p' if sg > 0 else 'n')
        E(.02, sg * .10, .10, .06, .07, .10, 'wing3')
        L((.02, sg * .10, .12), (.04, sg * .10, .04), .05, .04, 'foot', seg=6)
        foot(b, .06, sg * .10, 1.2, claw=True)
    b.grp = 'body'
    for (ax, az) in ((.07, .018), (.018, .07)):                  # cyan sparkle on the back
        E(-.255, 0, .45, .014, ax, az, 'cyan')
    for sg in (-1, 1):
        E(-.24, sg * .13, .40, .012, .02, .02, 'cyan', (0, 0, .7))
        E(-.24, sg * .13, .50, .012, .02, .02, 'cyan', (0, 0, .7))
    b.grp = 'tail'
    for i in range(5):                                          # tail fan down/back, lilac -> cyan
        u = (i - 2) / 2
        b.gfeather2(V((-.12, u * .03, .22)), V((-.5, u * .5, -1.0)), .32 - .04 * abs(u), .045, ('wing3', 'wing', 'tcyan'), V((1, 0, 0)), (.5, .76))


STAGES = {0: stage0, 1: stage1, 2: stage2}

PALS = {
    0: dict(body='#8fa6e6', body2='#9a88d6', head='#8fa4e4', disc='#cdd6f6', chest='#a9c4ee', tuftb='#6f8fe0', pink='#e47ac8',
            wing='#7b84d2', brow='#7a8ad8', wing2='#8a82d8', foot='#c98f72', beak='#e8a248', tail='#c0b2ee', claw='#7a5a4a'),
    1: dict(body='#8f8ac8', body2='#8a74bc', head='#9a96cc', disc='#e2e2f8', disc2='#a8a4d4', brow='#3a2f72',
            tdark='#3d3278', pink='#e07acc', tcyan='#58c8e0', cyan='#4fc4e8', heart='#b07ad0',
            wing='#52308a', wing2='#8a58c0', wingtip='#6a40a4', foot='#e69a3a', beak='#e8a248', claw='#7a5030'),
    2: dict(body='#54489a', body2='#54489a', chest0='#8a78cc', chest1='#a88ae0', head='#6e56a6', disc='#b0bcf0', disc2='#7a82c4', brow='#2a2058',
            horn='#b46ad4', horn2='#8a58c0', crest='#6e8ad8', cyan='#58d0e8',
            wing='#8a68cc', wing2='#b898f0', wing3='#6652ae', tcyan='#6ad6ee', tpink='#d078e0',
            foot='#c0884a', beak='#e8a248', claw='#2a2028'),
}


def pal_for(st):
    pl = dict(PALS[st])
    pl.setdefault('foot', '#e69a3a')
    pl.update(dark='#32265a', white='#ffffff', eyewhite='#e6ecfb')
    return pl


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    b = ph.P(pal_for(st), 1.0)
    STAGES[st](b, **({'spread': SPREAD} if st == 2 else {}))
    ob = tw.voxelise(b.objs)
    K.lighting(sky=0.9, sun=4.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    c = sum(corners, Vector()) / 8
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = 0.0
    ortho = 2.05 * max((q - c).length for q in corners)
    for v in views:
        cam = bpy.data.cameras.new('cam_' + v)
        cam.type = 'ORTHO'
        co = bpy.data.objects.new('cam_' + v, cam)
        sc.collection.objects.link(co)
        co.location = c + p3.VIEWS[v]
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = ortho * .85
        sc.camera = co
        K.render(os.path.join(out, 'owl_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='front')
    ap.add_argument('--out', required=True)
    ap.add_argument('--spread', action='store_true')
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--size', type=int, default=560)
    a = ap.parse_args(argv)
    global SPREAD
    SPREAD = a.spread
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for st in [int(s) for s in a.stages.split(',')]:
        try:
            render_all(st, a.out, a.views.split(','), a.samples, a.size)
        except Exception:
            print('FAILED', st)
            traceback.print_exc()


if __name__ == '__main__':
    main()
