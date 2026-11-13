"""Duck line (3 stages), from the user's turnaround sheets.

    blender --background --python tool/blender/duck.py -- --out docs/renders/monsters/duck [--stages 0,1,2] [--views front,side,back,q]

Axes: x = forward (head), y = sideways, z = up. Height 1.0 per stage.
Eyes: the phoenix recipe (dark eye, white patch on the outer side, brow ridge).
Beak: the stage-3 flat duck bill (orange, cyan tip, two nostrils) on ALL stages, scaled to the head.
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
NY = V((0, 1, 0))


def eyes(b, h, hr, k, ex_f=.80, ez_f=-.02, yf=.44):
    E = b.E
    ex, ez = h[0] + hr[0] * ex_f, h[2] + hr[2] * ez_f
    for sg in (-1, 1):
        b.grp = 'eye_' + ('p' if sg > 0 else 'n')                 # (rig builder tags every primitive with b.grp; plain builder ignores it)
        E(ex, sg * hr[1] * yf, ez, .055 * k, .072 * k, .080 * k, 'dark')
        E(ex - .005 * k, sg * hr[1] * (yf + .24), ez + .005 * k, .040 * k, .062 * k, .070 * k, 'eyewhite')
        b.grp = 'head'
        E(ex - .02 * k, sg * hr[1] * (yf + .06), ez + .095 * k, .06 * k, .11 * k, .034 * k, 'brow', (sg * .25, 0, 0))
    return (ex, hr[1] * yf, ez)


def bill(b, h, hr, z, length, width, thick, droop=.0):
    """Flat duck bill (stage-3 shape): broad base, spatula tip in cyan, nostrils on top."""
    E = b.E
    b.grp = 'bill'
    x0 = h[0] + hr[0] * .80
    thick *= .8
    n = 7                                                       # continuous flat spatula: constant thickness, widening slightly to a rounded tip
    for i in range(n):
        t = i / (n - 1)
        w = width * (.82 + .22 * math.sin(math.pi * min(1, t * 1.1)) * (1 - t * .3))
        E(x0 + length * (.12 + .95 * t), 0, z - droop * t, length * .16, w, thick, 'beaktip' if t > .72 else 'beak')
    for sg in (-1, 1):
        E(x0 + length * .72, sg * width * .38, z + thick * .75, length * .07, width * .10, thick * .22, 'nostril')
    return (x0, 0, z)


def foot(b, x, y, s, toes=3, claw=True):
    """Webbed foot: flat plate + toe blocks fanning forward."""
    E = b.E
    E(x + .03 * s, y, .022 * s, .075 * s, .075 * s, .022 * s, 'foot')
    for i in range(toes):
        a = (i - (toes - 1) / 2) * .6 / max(1, toes - 1) if toes > 1 else 0
        tx, ty = x + .13 * s * math.cos(a), y + .13 * s * math.sin(a)
        b.L((x + .03 * s, y, .025 * s), (tx, ty, .02 * s), .030 * s, .022 * s, 'foot', seg=6)
        if claw:
            b.E(tx + .025 * s, ty, .012 * s, .016 * s, .010 * s, .010 * s, 'claw')
    if toes > 1:                                                # web between the toes
        E(x + .09 * s, y, .012 * s, .05 * s, .07 * s * toes / 3, .010 * s, 'foot')


def build(b, st):
    E, L = b.E, b.L
    if st == 0:                                                 # yellow duckling, teal wing nubs
        body_c, body_r = (-.06, 0, .35), (.28, .23, .25)
        h, hr = (.10, 0, .72), (.25, .235, .25)
        k = .62
        b.grp = 'body'
        E(*body_c, *body_r, 'body')
        E(.04, 0, body_c[2] - .06, body_r[0] * .9, body_r[1] * .9, body_r[2] * .9, 'body2')
        b.grp = 'head'
        E(*h, *hr, 'head')
        E(h[0] - .02, 0, h[2] + hr[2] * .12, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
        eye = eyes(b, h, hr, k)
        hinge = bill(b, h, hr, h[2] - hr[2] * .26, .20, .105, .040, .012)
        for sg in (-1, 1):                                      # wing nubs
            sd = 'p' if sg > 0 else 'n'
            b.grp = 'wing_' + sd
            E(-.04, sg * .24, .44, .13, .04, .11, 'wing', (0, .3, sg * .1))
            for i in range(3):                                  # pointed swept-back wing tips
                b.feather((-.10 - .03 * i, sg * .23, .46 - .05 * i), (-.9, sg * .15, -.2 - .15 * i), .24 - .02 * i, .06, 'wing2', NY)
            b.grp = 'foot_' + sd
            foot(b, .03, sg * .13, 1.0)
            b.grp = 'leg_' + sd
            L((.0, sg * .13, .10), (.03, sg * .13, .03), .05, .035, 'foot', seg=6)
        b.grp = 'tail'
        for i in range(3):                                      # tail tuft
            b.feather((-.28, 0, .30), (-.8, (i - 1) * .35, .35), .14, .05, 'body', NY)
        return dict(torso=(0, 0, .30), neck=(h[0] - .05, 0, h[2] - hr[2] * .85), hinge=hinge, eye=eye, shoulder=(-.06, .24, .46),
                    hip=(.0, .13, .12), ankle=(.03, .13, .04), tail=(-.28, 0, .30), body_c=body_c, body_r=body_r, tilt=0.0)
    elif st == 1:                                               # bigger yellow duck, blue leaf wing at the back
        body_c, body_r = (-.02, 0, .40), (.36, .31, .32)
        h, hr = (.10, 0, .83), (.22, .21, .21)
        k = .58
        b.grp = 'body'
        E(*body_c, *body_r, 'body', (0, .15, 0))
        E(.10, 0, body_c[2] - .06, body_r[0] * .82, body_r[1] * .86, body_r[2] * .9, 'body2', (0, .15, 0))
        E(h[0] - .06, 0, h[2] - .22, .15, .14, .20, 'body')     # neck
        b.grp = 'head'
        E(*h, *hr, 'head')
        E(h[0] - .02, 0, h[2] + hr[2] * .12, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
        eye = eyes(b, h, hr, k)
        hinge = bill(b, h, hr, h[2] - hr[2] * .26, .25, .115, .045, .015)
        for sg in (-1, 1):
            sd = 'p' if sg > 0 else 'n'
            # blue wing patch on the flank with two feather tips
            b.grp = 'wing_' + sd
            # sits proud of the flank (body surface y~.31) and thick enough that the yellow never shows through when it flaps
            E(-.04, sg * .335, .43, .18, .065, .14, 'wing', (0, .25, sg * .1))
            b.feather((-.06, sg * .345, .40), (-.55, sg * .30, -.55), .20, .09, 'wing2', NY)
            b.feather((-.10, sg * .345, .46), (-.7, sg * .30, -.3), .18, .08, 'wing2', NY)
            b.grp = 'foot_' + sd
            foot(b, .04, sg * .15, 1.1)
            b.grp = 'leg_' + sd
            L((.0, sg * .15, .14), (.04, sg * .15, .05), .055, .04, 'foot', seg=6)
        # big blue leaf tail standing up behind the back
        b.grp = 'tail'
        for j, (dz, ln, w, dy) in enumerate(((.55, .50, .075, .0),)):       # ONE tail leaf: fan of feathers rising up and back, light tips
            b.feather((-.24, 0, .42), (-.50, 0, .85), .56, .17, 'wing', NY, .03)          # flat leaf, seen full from the side
            b.feather((-.26, 0, .46), (-.50, 0, .85), .44, .12, 'wing2', NY, .03)         # lighter inner layer
            b.chain([(-.24, 0, .42, .02), (-.36, 0, .66, .016), (-.44, 0, .86, .012)], 'wing3')   # centre rib
            for sg in (-1, 1):                                  # veins: diagonal ribs from the centre rib out to the edge, both faces
                for t in (.28, .46, .64, .80):
                    cx, cz = -.24 - .20 * t, .42 + .44 * t
                    w = .15 * (1 - .5 * abs(t - .45))
                    b.chain([(cx, sg * .028, cz, .008), (cx - .05, sg * .028, cz + .045, .007), (cx - .10, sg * .028, cz + .06, .006)], 'wing3')
        return dict(torso=(0, 0, .34), neck=(h[0] - .06, 0, h[2] - .24), hinge=hinge, eye=eye, shoulder=(-.04, .29, .46),
                    hip=(.0, .15, .16), ankle=(.04, .15, .05), tail=(-.24, 0, .42), body_c=body_c, body_r=body_r, tilt=.15)
    else:                                                       # blue-grey duck, white belly + collar, feathered wings
        body_c, body_r = (-.10, 0, .47), (.32, .25, .27)          # horizontal egg, chest forward-down
        h, hr = (.20, 0, .86), (.15, .145, .17)
        k = .5
        b.grp = 'body'
        E(*body_c, *body_r, 'body', (0, -.25, 0))
        E(.10, 0, .52, .20, .21, .27, 'body', (0, .1, 0))           # chest bulge
        E(.20, 0, .45, .12, .165, .21, 'belly', (0, .1, 0))       # white belly oval on the chest
        E(h[0] - .05, 0, h[2] - .20, .10, .11, .17, 'body', (0, .2, 0))   # neck
        E(h[0] - .035, 0, h[2] - .165, .125, .13, .024, 'collar', (0, .15, 0))    # white collar ring, proud of the neck
        b.grp = 'head'
        E(*h, *hr, 'head')
        E(h[0] - .02, 0, h[2] + hr[2] * .12, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
        eye = eyes(b, h, hr, k)
        hinge = bill(b, h, hr, h[2] - hr[2] * .26, .30, .105, .042, .04)
        for sg in (-1, 1):
            sd = 'p' if sg > 0 else 'n'
            # folded wing along the flank: overlapping scale rows, light tips towards the back
            b.grp = 'wing_' + sd
            E(-.06, sg * .22, .50, .22, .085, .18, 'wing3', (0, .1, sg * .08))   # wing volume under the feathers
            for r in range(6):                                  # scapular/covert rows: staggered, each feather dark root -> light tip
                for i in range(12):
                    off = .5 * (r % 2)
                    root = V((.16 - .055 * (i + off) - .012 * r, sg * (.222 + .005 * r), .64 - .045 * r - .011 * (i + off)))
                    b.gfeather2(root, (-.95, sg * .10, -.18 - .09 * r - .01 * i), .19 - .007 * i + .01 * r, .056,
                                ('wing3' if r % 2 else 'wing', 'wing3' if r % 2 else 'wing', 'wing2'), NY, (.62, .82))
            for i in range(6):                                  # primaries sticking out past the tail
                b.gfeather2((-.20 - .03 * i, sg * .215, .46 - .03 * i), (-.95, sg * .12, .0 - .05 * i), .26, .042, ('wing', 'wing2', 'wing2'), NY, (.35, .65))
            fx = .02
            b.grp = 'leg_' + sd
            L((-.02, sg * .13, .30), (fx, sg * .13, .08), .055, .034, 'leg', seg=6)    # long grey legs
            b.grp = 'foot_' + sd
            L((fx, sg * .13, .08), (fx, sg * .13, .035), .034, .03, 'leg', seg=6)
            foot(b, fx, sg * .13, 1.45, claw=True)
        b.grp = 'tail'
        for i in range(7):                                      # tail: fan of feathers rising up and back
            u = (i - 3) / 3
            b.gfeather2((-.32, u * .04, .50), (-.75, u * .32, .65), .42 - .05 * abs(u), .06, ('wing', 'wing', 'wing2'), NY, (.5, .75))
        return dict(torso=(0, 0, .40), neck=(h[0] - .06, 0, h[2] - .22), hinge=hinge, eye=eye, shoulder=(.08, .22, .60),
                    hip=(-.02, .13, .31), ankle=(.02, .13, .07), tail=(-.32, 0, .50), body_c=body_c, body_r=body_r, tilt=-.25)


PALS = {
    0: dict(body='#f6dc6c', body2='#fbe88a', head='#f7de72', belly='#fbe88a', wing='#4fa3b0', wing2='#6fc0c8',
            foot='#e8862a', brow='#c8962a'),
    1: dict(body='#ecb43a', body2='#f3c45a', head='#eeb83f', belly='#f3c45a', wing='#4a9eb0', wing2='#6cbcc8',
            foot='#e8862a', brow='#c8962a'),
    2: dict(body='#6f8794', body2='#7c95a2', head='#6d8592', belly='#e4f0ff', wing3='#6a8391', wing='#7c96a6', wing2='#a8bdc9',
            foot='#6c7d8a', leg='#6c7d8a', brow='#4a5e6a', collar='#ece8dc'),
}


def pal_for(st):
    pl = dict(PALS[st])
    pl.setdefault('leg', pl['foot'])
    pl.setdefault('wing3', pl['wing'])
    pl.update(beak='#e87a24', beaktip='#33b8d6', nostril='#8a3c10', claw='#ecd8a8', dark='#0e0e1c', white='#ffffff',
              eyewhite='#f4ece0')
    pl.setdefault('collar', '#ece8dc')
    return pl


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    b = ph.P(pal_for(st), 1.0)
    build(b, st)
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
        K.render(os.path.join(out, 'duck_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='q')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--size', type=int, default=560)
    a = ap.parse_args(argv)
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
