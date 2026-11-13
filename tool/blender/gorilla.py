"""Gorilla line (3 stages, replaces Terraking), voxel style, from the user's turnaround sheet.

    blender --background --python tool/blender/gorilla.py -- --out docs/renders/monsters/gorilla [--stages 0,1,2] [--views front,side,back,q]

Axes: x = forward (face), y = sideways, z = up. Height ~1.0.
Look of the sheet: tall flat-topped head with plates on top, gray box-shaped face mask, glossy bulbs (blue on top, copper below),
box-like armour blocks, gray flat feet that also serve as hands. Groups: body, head, eye_p/n, arm_p/n, leg_p/n.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phoenix as ph  # noqa: E402
import phoenix3 as p3  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

V = Vector
GLOSS = False
YS = 1.0                                                      # lateral squash of everything except the head (set per stage)
BS = 1.0                                                      # bulb size factor (set per stage)
HEADG = ('head', 'eye_p', 'eye_n')


# ── primitives ─────────────────────────────────────────────────────────────────────────────────
def BX(b, x, y, z, rx, ry, rz, m, rot=None):
    """Box by centre and half-extents, optionally rotated (euler radians)."""
    if b.grp not in HEADG:
        y, ry = y * YS, ry * YS
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(rx, ry, rz) * .38, segments=2, affect='EDGES')
    ob = K._mesh('box', bm)
    ob.location = (x, y, z)
    if rot:
        ob.rotation_euler = rot
    b.objs.append(K._put(ob, b.M[m], 0, False))


def bulb(b, x, y, z, rx, ry, rz, top='crys', bot='copper', rot=None, hl=True):
    """Glossy bulb of the sheet: blue top, copper underneath, one pale highlight."""
    if GLOSS:
        b.E(x, y, z, rx, ry, rz, 'gloss', rot)
        return
    rx, ry, rz = rx * BS, ry * BS, rz * BS
    b.E(x, y, z, rx, ry, rz, top, rot)
    mid = 'mid' if top == 'crys' else top
    b.E(x, y, z - .28 * rz, rx * 1.008, ry * 1.008, rz * .55, mid, rot)
    b.E(x, y, z - .52 * rz, rx * 1.02, ry * 1.02, rz * .50, bot, rot)
    if hl:
        b.E(x + .45 * rx, y, z + .55 * rz, rx * .30, ry * .30, rz * .22, 'crys2', rot)


def spike(b, base, d, ln, r, mats=('copper2', 'crys', 'crys2')):
    """Hexagonal crystal prism: tan base, blue body, pale tip."""
    d = V(d).normalized()
    p0 = V(base)
    if GLOSS:
        mats = ('gloss', 'gloss', 'gloss')
    p1, p2, p3_ = p0 + d * ln * .30, p0 + d * ln * .72, p0 + d * ln
    b.L(tuple(p0), tuple(p1), r, r * .98, mats[0], seg=6)
    b.L(tuple(p1), tuple(p2), r * .98, r * .92, mats[1], seg=6)
    b.L(tuple(p2), tuple(p3_), r * .92, r * .12, mats[2], seg=6)


def foot(b, x, y, s=1.0):
    """Flat gray block foot (also the hand): heel block + lower toe step."""
    BX(b, x, y, .05 * s, .10 * s, .10 * s, .05 * s, 'foot')
    BX(b, x + .105 * s, y, .03 * s, .055 * s, .095 * s, .03 * s, 'foot2')


def face(b, hx, hz, k=1.0, brow=False):
    """Gorilla face of the sheet: rounded gray mask, muzzle with nostrils, ears, dark eyes with ONE highlight voxel, brow."""
    b.grp = 'head'
    E = b.E
    E(hx + .17 * k, 0, hz - .02 * k, .105 * k, .15 * k, .15 * k, 'skin')                          # mask
    E(hx + .235 * k, 0, hz - .085 * k, .075 * k, .12 * k, .085 * k, 'skin3')                      # muzzle
    if brow:
        BX(b, hx + .262 * k, 0, hz + .045 * k, .012 * k, .10 * k, .016 * k, 'skin3')              # light brow bar between the eyes
    E(hx + .15 * k, 0, hz + .105 * k, .07 * k, .165 * k, .035 * k, 'fur')                        # brow ridge
    for sg in (-1, 1):
        b.grp = 'eye_' + ('p' if sg > 0 else 'n')
        E(hx + .262 * k, sg * .068 * k, hz + .04 * k, .022 * k, .034 * k, .040 * k, 'dark')
        E(hx + .283 * k, sg * .060 * k, hz + .062 * k, .012 * k, .012 * k, .012 * k, 'white')
        b.grp = 'head'
        BX(b, hx + .303 * k, sg * .035 * k, hz - .06 * k, .008 * k, .014 * k, .014 * k, 'dark')     # nostril
        BX(b, hx - .02 * k, sg * .245 * k, hz - .01 * k, .035 * k, .02 * k, .065 * k, 'skin')       # ear plate
        BX(b, hx - .02 * k, sg * .262 * k, hz - .01 * k, .015 * k, .01 * k, .035 * k, 'fur3')
    BX(b, hx + .312 * k, 0, hz - .112 * k, .006 * k, .075 * k, .009 * k, 'dark')                    # mouth
    b.grp = 'head'


def head_plates(b, hx, top, k=1.0, crest=False):
    """Flat plates on top of the head: gray cap, copper cube, gray bump (stage 0) or a crest column (stage 1)."""
    b.grp = 'head'
    BX(b, hx - .02 * k, 0, top - .018 * k, .09 * k, .075 * k, .02 * k, 'skin')
    BX(b, hx - .09 * k, .12 * k, top - .045 * k, .04 * k, .04 * k, .035 * k, 'copper')
    BX(b, hx - .06 * k, -.13 * k, top - .06 * k, .045 * k, .04 * k, .03 * k, 'skin2')
    if crest:
        BX(b, hx - .02 * k, 0, top + .03 * k, .07 * k, .05 * k, .02 * k, 'crys')
        BX(b, hx - .02 * k, 0, top + .065 * k, .09 * k, .06 * k, .018 * k, 'skin')


# ── stage 0: hunched young gorilla (long horizontal trunk, head forward, round rump) ──────────
def stage0(b):
    E, L = b.E, b.L
    b.grp = 'body'
    E(-.05, 0, .50, .36, .27, .26, 'fur', (0, -.22, 0))                   # long trunk, shoulders higher than hips
    E(.08, 0, .62, .20, .29, .14, 'fur2')                                 # shoulder hump
    E(-.30, 0, .36, .20, .26, .21, 'fur')                                 # rump
    for sg in (-1, 1):
        E(-.37, sg * .11, .33, .13, .12, .15, 'fur2')                     # round cheeks
        BX(b, .20, sg * .07, .41, .05, .075, .07, 'skin', (0, .15, 0))    # pec lobes
    BX(b, .22, 0, .30, .04, .10, .06, 'skin', (0, .15, 0))
    b.grp = 'head'
    E(.29, 0, .74, .25, .30, .29, 'fur')                                  # tall head, far forward
    head_plates(b, .29, 1.03)
    face(b, .29, .74, 1.18)
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        E(.10, sg * .28, .54, .14, .14, .14, 'fur2')
        L((.10, sg * .28, .54), (.17, sg * .36, .31), .16, .14, 'fur', seg=8)
        L((.17, sg * .36, .31), (.31, sg * .33, .10), .14, .14, 'fur', seg=8)
        foot(b, .32, sg * .33, .95)                                       # gray hand block
        bulb(b, .11, sg * .40, .59, .15, .12, .15, rot=(0, 0, sg * .4))   # shoulder bulb
        bulb(b, .16, sg * .43, .36, .12, .095, .13, 'copper2', 'copper')
        bulb(b, .35, sg * .33, .17, .11, .095, .12)
        b.grp = 'leg_' + sd
        E(-.27, sg * .27, .28, .17, .15, .19, 'fur2')
        L((-.27, sg * .27, .28), (-.14, sg * .25, .10), .15, .11, 'fur', seg=8)
        foot(b, -.12, sg * .25, 1.0)
        bulb(b, .01, sg * .27, .19, .13, .10, .13)                       # knee
        b.grp = 'body'
        bulb(b, -.28, sg * .37, .34, .13, .095, .14, 'copper2', 'copper')  # thigh
        bulb(b, .18, sg * .27, .43, .09, .07, .10, 'copper2', 'copper')
        for (x, y, z, r, tp, bt) in ((.0, .15, .70, .08, 'crys', 'copper'), (-.12, .10, .72, .07, 'copper2', 'copper'),   # back rows
                                    (-.10, .22, .62, .08, 'crys', 'copper'), (-.22, .15, .62, .09, 'copper2', 'copper'),
                                    (-.22, .27, .50, .075, 'crys', 'copper'), (-.32, .12, .50, .08, 'crys', 'copper')):
            bulb(b, x, sg * y, z, r * .72, r * .62, r * .76, tp, bt)


# ── stage 1: broad, armoured ───────────────────────────────────────────────────────────────────
def stage1(b):
    E, L = b.E, b.L
    b.grp = 'body'
    E(-.06, 0, .48, .40, .35, .29, 'fur', (0, -.2, 0))
    E(-.32, 0, .35, .23, .30, .23, 'fur')
    for sg in (-1, 1):
        E(-.39, sg * .12, .32, .14, .13, .16, 'fur2')                     # rump cheeks
        BX(b, .22, sg * .09, .44, .05, .10, .085, 'skin', (0, .12, 0))    # pec lobes
        for i in range(4):                                                # copper collar, V down the chest
            BX(b, .25 - .012 * i, sg * (.07 + .06 * i), .66 - .035 * i, .035, .07, .03,
               'copper2' if i % 2 else 'copper', (sg * -.5, 0, 0))
    for z, w in ((.34, .13), (.27, .11), (.20, .09)):                     # abs
        BX(b, .25, 0, z, .04, w, .028, 'skin')
    BX(b, -.02, 0, .73, .14, .30, .07, 'copper', (0, -.12, 0))            # back armour: shoulder plate
    BX(b, -.18, 0, .66, .12, .24, .06, 'copper', (0, -.2, 0))             # second plate
    BX(b, -.32, 0, .56, .10, .18, .05, 'copper', (0, -.3, 0))             # lower plate
    for x, z in ((.0, .79), (-.16, .72), (-.30, .62)):                    # spine ridge
        BX(b, x, 0, z, .07, .035, .03, 'copper2')
    b.grp = 'head'
    E(.26, 0, .80, .26, .31, .29, 'fur')
    head_plates(b, .26, 1.07, 1.05, crest=True)
    face(b, .26, .80, 1.2, brow=True)
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        BX(b, .08, sg * .40, .58, .17, .14, .12, 'copper', (0, 0, sg * .1))         # pauldron block
        E(.08, sg * .385, .70, .16, .13, .035, 'skin2')                        # gray top plate
        for z in (.63, .57, .51):                                                   # ridge lines
            BX(b, .08, sg * .405, z, .175, .145, .012, 'copper2', (0, 0, sg * .1))
        BX(b, .08, sg * .43, .45, .19, .16, .028, 'copper2', (0, 0, sg * .1))       # rim
        L((.10, sg * .38, .50), (.19, sg * .43, .28), .16, .145, 'fur', seg=8)
        L((.19, sg * .43, .28), (.30, sg * .41, .10), .145, .145, 'fur', seg=8)
        foot(b, .32, sg * .41, 1.05)                                                # gray hand block
        bulb(b, .36, sg * .41, .19, .12, .10, .125)                                 # forearm bulb
        b.grp = 'leg_' + sd
        E(-.28, sg * .29, .26, .19, .17, .21, 'fur2')
        L((-.28, sg * .28, .26), (-.13, sg * .26, .10), .16, .12, 'fur', seg=8)
        foot(b, -.11, sg * .26, 1.05)
        bulb(b, .02, sg * .28, .20, .13, .105, .13, 'copper2', 'copper')           # knee
        b.grp = 'body'
        bulb(b, -.30, sg * .39, .34, .13, .09, .14, 'copper2', 'copper')
        BX(b, -.06, sg * .30, .66, .12, .06, .10, 'copper', (sg * .35, -.15, 0))     # shoulder-blade plate


# ── stage 2: crowned king (leaning forward, spine crystals, thick ankle bracers) ──────────────
def stage2(b):
    E, L = b.E, b.L
    b.grp = 'body'
    E(-.08, 0, .44, .34, .30, .28, 'fur', (0, -.15, 0))                   # barrel trunk
    E(.02, 0, .62, .22, .42, .19, 'fur')                                  # broad shoulders
    E(.12, 0, .74, .18, .28, .10, 'fur2')                                 # trapezius slope
    E(-.30, 0, .30, .22, .27, .22, 'fur')                                 # rump
    for sg in (-1, 1):
        E(-.38, sg * .11, .28, .14, .13, .16, 'fur2')
        BX(b, .24, sg * .10, .54, .06, .12, .10, 'skin')                  # big pec lobes
    for z, w in ((.40, .20), (.32, .18), (.25, .14)):                     # ab stack
        BX(b, .27, 0, z, .04, w, .03, 'skin')
    b.grp = 'head'
    for dz in (-.10, -.03, .04, .11):
        E(.20, 0, .77 + dz, .245, .27, .11, 'fur')
    face(b, .20, .77, 1.22, brow=False)
    for k in range(16):                                                   # crown = ring of rounded beads, head top stays visible inside
        a = 2 * math.pi * k / 16
        E(.19 + .21 * math.cos(a), .245 * math.sin(a), .955, .05, .05, .05, 'copper' if k % 2 == 0 else 'copper2')
        E(.19 + .215 * math.cos(a), .25 * math.sin(a), .915, .045, .045, .035, 'copper2')
    for sg in (-1, 0, 1):
        BX(b, .36, sg * .09, .965, .012, .03, .03, 'crys2')
    for i in range(5):                                                    # crown crystals
        a = (i - 2) / 2
        ln = .30 if i == 2 else (.21 if i % 2 == 0 else .15)
        spike(b, (.15 + .06 * math.cos(a * 1.4), a * .17, .98), (-.05, a * .32, 1), ln, .055 if i == 2 else .04,
              ('copper2', 'crys', 'crys2') if i % 2 == 0 else ('copper', 'copper2', 'crys'))
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        E(.04, sg * .46, .60, .18, .17, .17, 'fur2')
        BX(b, .04, sg * .49, .68, .16, .15, .03, 'copper2')                          # tan rim plate
        E(.04, sg * .49, .75, .15, .14, .11, 'gloss' if GLOSS else 'crys')                                 # blue mass
        spike(b, (.02, sg * .50, .77), (-.15, sg * .62, .55), .40, .08)             # big diagonal crystal, outward
        spike(b, (.02, sg * .42, .79), (.0, -sg * .25, 1), .16, .05)               # small inward crystal
        spike(b, (.04, sg * .58, .74), (.0, sg * 1.0, .3), .16, .045)              # side stub
        bulb(b, .16, sg * .47, .74, .05, .05, .05, 'copper2', 'copper', hl=False)   # tan ball on the front
        L((.04, sg * .46, .60), (.11, sg * .52, .34), .16, .21, 'fur', seg=8)
        L((.11, sg * .52, .34), (.16, sg * .46, .10), .21, .20, 'fur', seg=8)
        for z in (.30, .10):                                                         # bracer: tan bands top and bottom
            L((.14, sg * .49, z - .022), (.14, sg * .49, z + .022), .205, .205, 'copper2', seg=14)
        L((.14, sg * .49, .12), (.14, sg * .49, .28), .19, .19, 'fur3', seg=14)
        bulb(b, .26, sg * .49, .20, .06, .11, .08, 'crys', 'copper', hl=False)      # bracer gem
        BX(b, .14, sg * .70, .20, .015, .06, .08, 'crys2')                           # side crystal
        foot(b, .17, sg * .46, 1.6)                                                  # gray hand block
        b.grp = 'leg_' + sd
        E(-.28, sg * .23, .24, .21, .18, .20, 'fur2')
        L((-.28, sg * .23, .24), (-.20, sg * .23, .10), .18, .15, 'fur', seg=8)
        for z in (.17, .09):                                                         # ankle bracer bands
            L((-.20, sg * .23, z - .02), (-.20, sg * .23, z + .02), .185, .185, 'copper2', seg=14)
        bulb(b, -.10, sg * .23, .13, .04, .09, .06, 'crys', 'copper', hl=False)
        foot(b, -.17, sg * .23, 1.6)
        b.grp = 'body'
        E(-.28, sg * .30, .52, .06, .08, .09, 'copper')
    for (x, y, z, ln, r) in ((.10, 0, .84, .26, .05), (-.04, 0, .78, .26, .055), (-.18, 0, .70, .24, .055), (-.30, 0, .60, .22, .05),
                              (-.04, .14, .76, .18, .04), (-.04, -.14, .76, .18, .04), (-.20, .13, .66, .17, .04), (-.20, -.13, .66, .17, .04)):
        spike(b, (x, y, z), (-.55, y * 1.6, .85), ln, r)                                   # crystals along the spine
    for sg in (-1, 1):
        bulb(b, -.12, sg * .26, .62, .07, .06, .075, 'crys', 'copper')
        bulb(b, -.26, sg * .22, .52, .07, .06, .075, 'copper2', 'copper')
        for (x, y, z, r) in ((-.02, .10, .79, .05), (-.10, .20, .74, .055), (-.14, .08, .74, .05), (-.24, .14, .64, .05), (-.30, .20, .54, .055)):
            bulb(b, x, sg * y, z, r, r * .9, r, 'crys', 'copper2')


STAGES = {0: stage0, 1: stage1, 2: stage2}

BASE = dict(fur='#3b3340', fur2='#4c4252', fur3='#2a242e', skin='#7f8b9a', skin2='#6a768a', skin3='#97a2b0',
            foot='#8e99a8', foot2='#a2acba', crys='#5f88c0', crys2='#a9c4de', copper='#7c695a', copper2='#9d8b7a')


def pal_for(st):
    pl = dict(BASE)
    pl.update(dark='#16131a', white='#ffffff', gloss='#b9c6d8', mid='#8c97a8')
    return pl


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    b = ph.P(pal_for(st), 1.0)
    nd = b.M['gloss'].node_tree.nodes['Principled BSDF']
    nd.inputs['Metallic'].default_value = 1.0
    nd.inputs['Roughness'].default_value = .24
    global YS
    YS = {0: .96, 1: .96, 2: .76}[st]
    global BS
    BS = {0: 1.22, 1: 1.15, 2: 1.0}[st]
    _E, _L = b.E, b.L

    def E2(x, y, z, rx, ry, rz, m, tilt=None):                           # body parts are squashed sideways, the head is not
        s = 1.0 if b.grp in HEADG else YS
        _E(x, y * s, z, rx, ry * s, rz, m, tilt)

    def L2(p0, p1, r0, r1, m, seg=12):
        s = 1.0 if b.grp in HEADG else YS
        _L((p0[0], p0[1] * s, p0[2]), (p1[0], p1[1] * s, p1[2]), r0, r1, m, seg)
    b.E, b.L = E2, L2
    STAGES[st](b)
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
        K.render(os.path.join(out, 'gorilla_s%d_%s.png' % (st, v)))


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
