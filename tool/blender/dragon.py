"""Red dragon line (3 stages), measured 1:1 from the user's turnaround sheet (front views cropped and upscaled).

    blender --background --python tool/blender/dragon.py -- --out docs/renders/monsters/dragon [--stages 0,1,2] [--views front,side,back,q]

Axes: x = forward (head), y = sideways, z = up. Every stage is built at its own height of 1.0 (horn tip).
Eyes: the phoenix recipe (face() in phoenix3.py) scaled to the head - dark eye, white patch on the outer side, brow ridge.
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


def membrane_fan(b, root, targets, N, mat, thick=.016, scallop=.22):
    """Thin flat slabs from root to a row of target points: fills one wing panel."""
    root = V(root)
    pts = [V(t) for t in targets]
    for a, c in zip(pts, pts[1:]):
        n = max(3, int((c - a).length / .03))
        for i in range(n):
            u = (i + .5) / n
            tgt = a + (c - a) * u
            d = tgt - root
            ln = d.length * (1 - scallop * math.sin(math.pi * u))
            b.feather(root, d, ln, (c - a).length / n * .95 + .012, mat, N, thick)


def dragon_wing(b, sg, S, Wr, tips, B, bone, scallop, thumb=True, inner='mem'):
    """Bat wing: arm S->Wr, fingers Wr->tips, membrane between fingers and back to the body at B."""
    def m(p):
        return V((p[0], sg * p[1], p[2]))
    S, Wr, B = m(S), m(Wr), m(B)
    tips = [m(t) for t in tips]
    N = (Wr - S).cross(tips[len(tips) // 2] - S).normalized()
    membrane_fan(b, Wr, tips, N, 'mem', scallop=scallop)
    membrane_fan(b, Wr, [tips[-1], B], N, inner, scallop=scallop)
    membrane_fan(b, B, [Wr + (S - Wr) * (i / 5) for i in range(6)], N, inner, scallop=0)
    arm_mid = (S + Wr) / 2 + V((0, sg * .0, .02))
    b.chain([(S.x, S.y, S.z, bone * 1.5), (arm_mid.x, arm_mid.y, arm_mid.z, bone * 1.35), (Wr.x, Wr.y, Wr.z, bone * 1.2)], 'bone')
    for t in tips:
        mid = Wr + (t - Wr) * .5
        b.chain([(Wr.x, Wr.y, Wr.z, bone * 1.0), (mid.x, mid.y, mid.z, bone * .9), (t.x, t.y, t.z, bone * .6)], 'bone')
    if thumb:                                                  # cream thumb claw at the wrist
        b.E(Wr.x, Wr.y, Wr.z + bone * .3, bone * 1.1, bone * 1.1, bone * 1.2, 'horn')


def eyes(b, h, hr, k):
    """Phoenix eye recipe (phoenix3.face), no beak."""
    E = b.E
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    for sg in (-1, 1):
        b.grp = "eye_" + ("p" if sg > 0 else "n")
        E(ex, sg * hr[1] * .44, ez, .055 * k, .072 * k, .080 * k, 'dark')
        E(ex - .005 * k, sg * hr[1] * .68, ez + .005 * k, .040 * k, .062 * k, .070 * k, 'eyewhite')
        b.grp = "head"
        E(ex - .02 * k, sg * hr[1] * .50, ez + .095 * k, .06 * k, .11 * k, .034 * k, 'brow', (sg * .25, 0, 0))


def belly_strip(b, prof, rib_from):
    """Cream belly: flattened discs stacked down the front, width/depth from a measured profile (z, half-width, x front)."""
    z, zmin = prof[0][0], prof[-1][0]
    step = .026
    while z > zmin:
        for (z0, w0, x0), (z1, w1, x1) in zip(prof, prof[1:]):
            if z1 <= z <= z0:
                t = (z0 - z) / (z0 - z1)
                w, x = w0 + (w1 - w0) * t, x0 + (x1 - x0) * t
                b.E(x, 0, z, .034, w, step * .62, 'belly2' if (z < rib_from and int(round(z / step)) % 2) else 'belly')
                break
        z -= step


def foot(b, x, y, n, scale):
    """Foot with n cream toe blocks in a row at the front."""
    s = scale
    b.E(x, y, .045 * s, .075 * s, .062 * s, .045 * s, 'body')
    for i in range(n):
        a = (i - (n - 1) / 2) * .042 * s * 1.15
        b.E(x + .075 * s, y + a, .018 * s, .03 * s, .016 * s, .018 * s, 'horn')


# ── measured per stage (front AND side/back views of the sheet) ─────────────────────────────────
P = {
    0: dict(                                                    # sits upright
        head=((.08, 0, .70), (.25, .25, .225)), k=.95, snout=((.31, 0, .655), (.11, .09, .075)),
        horn=((.04, .13, .85), (-.12, .15, 1.02), .05, .04),
        chest=((.0, 0, .42), (.15, .15, .16)), hip=((.0, 0, .22), (.20, .235, .21)),
        belly=[(.52, .075, .15), (.42, .09, .15), (.34, .11, .165), (.26, .13, .19), (.16, .14, .20), (.08, .12, .17), (.05, .07, .13)], rib=.30,
        arm=[((.0, .13, .42), (.04, .29, .385), (.07, .31, .31))],
        legs=dict(y=.172, thigh=((0, .0, .13), (.10, .08, .13)), foot=(.06, 3, 1.0)),
        wing=dict(S=(-.12, .13, .60), Wr=(-.22, .28, .74), tips=[(-.57, .33, .69), (-.46, .30, .48), (-.30, .22, .40)], B=(-.12, .14, .42), bone=.045, scallop=.1),
        tail=[(-.15, 0, .20, .11), (-.32, 0, .17, .07), (-.50, 0, .12, .025)],
        spine=[(-.10, .50), (-.14, .40), (-.18, .30)],
        pal=dict(body='#b8432c', head='#bc4730', head2='#b03c28', mem='#e3b87e', bone='#b0402a'),
    ),
    1: dict(                                                    # four legs, horizontal body
        head=((.15, 0, .70), (.21, .21, .20)), k=.85, snout=((.38, 0, .635), (.09, .075, .07)),
        horn=((.17, .12, .84), (-.05, .14, .98), .048, .038),
        neck=[(.12, 0, .58, .10), (.07, 0, .45, .14)],
        torso=[((.05, 0, .33), (.17, .18, .20)), ((-.12, 0, .33), (.26, .17, .16)), ((-.27, 0, .31), (.17, .19, .17))],
        belly=[(.50, .07, .15), (.42, .08, .17), (.34, .09, .21), (.26, .10, .22), (.18, .09, .19), (.12, .07, .14)], rib=.34,
        front=dict(x=.12, y=.155, top=(.08, .30), foot=(.14, 4, 1.25), thigh=(.12, .105, .16)),
        hind=dict(x=-.27, y=.15, top=.28, foot=(-.30, 4, 1.25), thigh=(.15, .115, .17)),
        wing=dict(S=(-.06, .16, .68), Wr=(-.20, .44, .84), tips=[(-.56, .60, .92), (-.50, .52, .70), (-.40, .40, .54), (-.30, .30, .48)], B=(-.12, .17, .46), bone=.04, scallop=.12),
        tail=[(-.38, 0, .30, .12), (-.60, 0, .25, .075), (-.80, 0, .24, .025)],
        spine=[(.02, .54), (-.10, .50), (-.20, .49), (-.30, .47)],
        pal=dict(body='#b23c28', head='#b6402b', head2='#ab3827', mem='#e3b87e', bone='#aa3a26'),
    ),
    2: dict(
        head=((.17, 0, .765), (.19, .17, .155)), k=.70, snout=((.37, 0, .70), (.09, .065, .055)),
        horn=((.14, .09, .85), (-.10, .115, .98), .052, .042),
        neck=[(.13, 0, .68, .10), (.08, 0, .52, .125), (.04, 0, .40, .16)],
        torso=[((.02, 0, .36), (.19, .19, .21)), ((-.16, 0, .36), (.30, .18, .16)), ((-.36, 0, .35), (.15, .19, .18))],
        belly=[(.64, .055, .11), (.56, .065, .12), (.48, .08, .14), (.40, .10, .17), (.32, .12, .20), (.24, .10, .18), (.16, .07, .14)], rib=.40,
        front=dict(x=.03, y=.14, top=(.02, .30), foot=(.04, 4, 1.2), thigh=(.13, .105, .16)),
        hind=dict(x=-.38, y=.15, top=.30, foot=(-.40, 4, 1.2), thigh=(.15, .115, .18)),
        wing=dict(S=(-.14, .13, .58), Wr=(-.10, .32, 1.00), tips=[(-.65, .64, 1.22), (-.77, .68, .93), (-.70, .58, .74), (-.60, .45, .58), (-.45, .30, .50)], B=(-.20, .14, .48), bone=.032, scallop=.22),
        tail=[(-.48, 0, .32, .12), (-.80, -.05, .24, .07), (-1.0, -.30, .11, .03)],
        spine=[(.0, .56), (-.14, .52), (-.30, .52), (-.42, .50)],
        pal=dict(body='#a8372a', head='#ac3b2c', head2='#a13427', mem='#e9b27c', mem2='#e9b27c', bone='#ab3a28'),
    ),
}


def tail_spikes(b, pts, n):
    """Cream spikes along the top of a tail chain (sampled evenly)."""
    for i in range(n):
        t = (i + .5) / n * (len(pts) - 1)
        j = min(int(t), len(pts) - 2)
        u = t - j
        x, y, z, r = [pts[j][k] + (pts[j + 1][k] - pts[j][k]) * u for k in range(4)]
        b.E(x, y, z + r * .95, .022, .015, .02 + r * .3, 'belly')


def body_upright(b, p):
    E, L = b.E, b.L
    b.grp = "body"
    E(*p['chest'][0], *p['chest'][1], 'body')
    E(*p['hip'][0], *p['hip'][1], 'body')
    belly_strip(b, p['belly'], p['rib'])
    for sg in (-1, 1):
        b.grp = "fleg_" + ("p" if sg > 0 else "n")
        for a0, a1, a2 in p['arm']:
            L((a0[0], sg * a0[1], a0[2]), (a1[0], sg * a1[1], a1[2]), .058, .05, 'body')
            L((a1[0], sg * a1[1], a1[2]), (a2[0], sg * a2[1], a2[2]), .05, .045, 'body'); E(a2[0], sg * a2[1], a2[2] - .01, .05, .045, .05, 'body')
            for k in (-1, 0, 1):
                b.E(a2[0] + .02, sg * a2[1] + k * .016, a2[2] - .03, .012, .008, .012, 'horn')
    lg = p['legs']
    for sg in (-1, 1):
        b.grp = "hleg_" + ("p" if sg > 0 else "n")
        t, tr = lg['thigh']
        y = sg * lg['y']
        E(t[0], y, t[2], *tr, 'body')
        fx, nt, sc = lg['foot']
        L((t[0], y, t[2]), (fx * .6, y, .06), tr[1] * .95, .05 * sc, 'body')
        foot(b, fx * .6, y, nt, sc)
    b.grp = "tail"
    pts = p['tail']
    b.chain(pts, 'body')
    tail_spikes(b, pts, 4)


def body_quad(b, p):
    E, L = b.E, b.L
    b.grp = "body"
    b.chain(p['neck'], 'body')
    for c, r in p['torso']:
        E(*c, *r, 'body')
    belly_strip(b, p['belly'], p['rib'])
    # under-belly cream between the legs
    t0, t1 = p['torso'][0][0], p['torso'][-1][0]
    for i in range(6):
        x = t0[0] - .04 - i * (t0[0] - t1[0]) / 7
        E(x, 0, p['torso'][1][0][2] - p['torso'][1][1][2] * .88, .045, .075, .02, 'belly')
    fr, hd = p['front'], p['hind']
    for sg in (-1, 1):
        b.grp = "fleg_" + ("p" if sg > 0 else "n")
        y = sg * fr['y']                                         # front leg: straight pillar
        tx, tz = fr['top']
        E(tx, y, tz, fr['thigh'][0] * .9, fr['thigh'][1], fr['thigh'][2], 'body')
        L((tx, y, tz), (fr['foot'][0], y, .06), fr['thigh'][1] * .95, .075, 'body')
        foot(b, fr['foot'][0], y, fr['foot'][1], fr['foot'][2])
        b.grp = "hleg_" + ("p" if sg > 0 else "n")
        y = sg * hd['y']                                         # hind leg: thigh, then shin angled back, foot forward
        E(hd['x'], y, hd['top'], *hd['thigh'], 'body')
        knee = (hd['x'] - .03, y, .16)
        L((hd['x'], y, hd['top'] - .04), knee, hd['thigh'][1] * .9, .075, 'body')
        L(knee, (hd['foot'][0], y, .06), .075, .07, 'body')
        foot(b, hd['foot'][0], y, hd['foot'][1], hd['foot'][2])
    b.grp = "tail"
    pts = p['tail']
    b.chain(pts, 'body')
    tail_spikes(b, pts, 7)


def build(b, st):
    p = P[st]
    E = b.E
    (body_upright if st == 0 else body_quad)(b, p)
    # head
    b.grp = "head"
    h, hr = p['head']
    E(*h, *hr, 'head')
    E(h[0] - .04, 0, h[2] + hr[2] * .1, hr[0], hr[1] * .96, hr[2], 'head')
    sx, sr = p['snout']
    E(*sx, *sr, 'head')
    for sg in (-1, 1):
        E(sx[0] + sr[0] * .80, sg * sr[1] * .38, sx[2] + sr[2] * .2, .012, .016, .012, 'nostril')
    eyes(b, h, hr, p['k'])
    # horns: broad flat slabs, swept back
    (bx, by, bz), (tx, ty, tz), r0, r1 = p['horn']
    for sg in (-1, 1):
        b.L((bx, sg * by, bz), (tx, sg * ty, tz), r0 * 1.25, r1 * .85, 'horn', seg=10)    # smooth cone, flat blunt tip
    # wings
    w = p['wing']
    for sg in (-1, 1):
        b.grp = "wing_" + ("p" if sg > 0 else "n")
        dragon_wing(b, sg, w['S'], w['Wr'], w['tips'], w['B'], w['bone'], w['scallop'], thumb=st > 0, inner='mem2')
    # back ridge
    b.grp = "body"
    for x, z in p['spine']:
        E(x, 0, z, .018, .014, .035, 'horn')


def pal_for(st):
    pl = dict(P[st]['pal'])
    pl.setdefault('mem2', pl['mem'])
    pl.update(belly='#e3b97f', belly2='#cfa163', horn='#e8bd84', nostril='#6a1c14', dark='#0e0e1c', white='#ffffff',
              eyewhite='#f4ece0', brow='#8a1c18')
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
        K.render(os.path.join(out, 'dragon_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='front')
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
