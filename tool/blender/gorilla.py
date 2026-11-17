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
import owl  # noqa: E402                                      # eyes() = the phoenix eye recipe

V = Vector
GLOSS = False
YS = 1.0                                                      # lateral squash of everything except the head (set per stage)
BS = 1.0                                                      # bulb size factor (set per stage)
POST = None                                                   # optional hook(ob, stage) run on the voxel mesh before rendering (gorilla_paint.py colours it from the sheet)
NOBULB = False                                                # stone detection builds the model without the hand-placed stone bulbs
HANDBULB = True                                               # False: drop the hand-placed stone bulbs, keep only the stones detected in the sheet
EYE = None                                                    # (y, z) of the +y eye in world units, measured from the sheet by gorilla_paint.py
INFLATE = 1.0                                                 # radius factor for body ellipsoids/tubes (gorilla_copy.py inflates, then cuts with the sheet silhouettes)
EYEMATS = ('dark', 'white', 'eyewhite', 'brow')
HEADG = ('head', 'eye_p', 'eye_n')
PARAMS = {0: {}, 1: {}, 2: {}}                                # per-stage overrides, filled by gorilla_fit.py (silhouette fit against the orthographic sheet)


def prm(st, name, default):
    return PARAMS[st].get(name, default)
for _st in (0, 1, 2):                                          # fitted dimensions (gorilla_fit.py) override the defaults in the stage functions
    _pf = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gorilla_params_s%d.json' % _st)
    if os.path.exists(_pf):
        import json as _json
        PARAMS[_st] = _json.load(open(_pf))


# ── primitives ─────────────────────────────────────────────────────────────────────────────────
def BX(b, x, y, z, rx, ry, rz, m, rot=None, bev=.38):
    """Box by centre and half-extents, optionally rotated (euler radians)."""
    if b.grp not in HEADG:
        y, ry = y * YS, ry * YS
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(rx, ry, rz) * bev, segments=3 if bev > .5 else 2, affect='EDGES')
    ob = K._mesh('box', bm)
    ob.location = (x, y, z)
    if rot:
        ob.rotation_euler = rot
    b.objs.append(K._put(ob, b.M[m], 0, False))


def bulb(b, x, y, z, rx, ry, rz, top='crys', bot='copper', rot=None, hl=True):
    """Glossy bulb of the sheet: blue top, copper underneath, one pale highlight."""
    if (NOBULB or not HANDBULB) and hl:
        return
    if GLOSS:
        b.E(x, y, z, rx, ry, rz, 'gloss', rot)
        return
    rx, ry, rz = rx * BS, ry * BS, rz * BS
    if hl:                                              # stone patch on the fur: gray, three tones of stone (user 2026-11-13)
        warm = top != 'crys'
        top, mid, bot = ('sw1', 'sw2', 'sw3') if warm else ('st1', 'st2', 'st3')
    else:                                               # armour gems keep their colours
        mid = 'mid' if top == 'crys' else top
    b.E(x, y, z, rx, ry, rz, top, rot)
    b.E(x, y, z - .28 * rz, rx * 1.008, ry * 1.008, rz * .55, mid, rot)
    b.E(x, y, z - .52 * rz, rx * 1.02, ry * 1.02, rz * .50, bot, rot)
    if hl:
        b.E(x + .45 * rx, y, z + .55 * rz, rx * .30, ry * .30, rz * .22, 'st0', rot)


def add_stones(b, st):
    """Stones detected in the sheet (gorilla_stones.py): one ellipsoid each, mirrored to both sides. World coordinates, so the
    sideways squash of the builder is undone."""
    if NOBULB:
        return
    pf = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gorilla_stones_s%d.json' % st)
    if not os.path.exists(pf):
        return
    import json
    k = prm(st, 'stone_k', 1.0)
    for (x, y, z, rx, ry, rz) in json.load(open(pf)):
        for sg in ((-1, 1) if y > .03 else (1,)):
            b.grp = 'body' if abs(y) < .3 else ('arm_p' if sg > 0 else 'arm_n')
            b.E(x, sg * y / YS, z, rx * k, ry * k / YS, rz * k, 'stn')


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
    BX(b, hx + .20 * k, 0, hz - .02 * k, .08 * k, .135 * k, .135 * k, 'skin', bev=.3)                # mask: blocky and wide like the sheet's
    BX(b, hx + .255 * k, 0, hz - .085 * k, .055 * k, .105 * k, .075 * k, 'skin3', bev=.4)           # muzzle block
    if brow:
        BX(b, hx + .262 * k, 0, hz + .045 * k, .012 * k, .10 * k, .016 * k, 'skin3')              # light brow bar between the eyes
    # eyes = the phoenix recipe (owl.eyes): dark eye, light patch on the outer side, brow ridge above, ONE highlight voxel
    ey_, ez_ = EYE if EYE else (.095 * k, hz + .07 * k)
    owl.eyes(b, (hx + .30 * k, ey_, ez_), .42, tilt=.0, bk=.55, bz=.10)
    for sg in (-1, 1):
        b.grp = 'head'
        BX(b, hx + .303 * k, sg * .035 * k, hz - .06 * k, .008 * k, .014 * k, .014 * k, 'fur3')     # nostril
        BX(b, hx - .02 * k, sg * .245 * k, hz - .01 * k, .035 * k, .02 * k, .065 * k, 'skin')       # ear plate
        BX(b, hx - .02 * k, sg * .262 * k, hz - .01 * k, .015 * k, .01 * k, .035 * k, 'fur3')
    BX(b, hx + .312 * k, 0, hz - .112 * k, .006 * k, .075 * k, .009 * k, 'fur3')                    # mouth
    b.grp = 'head'


def head_plates(b, hx, top, k=1.0, crest=False):
    """Flat plates on top of the head: gray cap, copper cube, gray bump (stage 0) or a crest column (stage 1)."""
    b.grp = 'head'
    # one FLAT stone slab lying on the skull (user 2026-11-13): gray, flush, no tower, no cube
    b.E(hx - .02 * k, 0, top - .012 * k, .115 * k, .095 * k, .03 * k, 'st1')                     # rounded stone, like the other stone patches
    b.E(hx - .02 * k, 0, top - .026 * k, .125 * k, .105 * k, .028 * k, 'st2')


def head_block(b, dx, dz, dt, dr, dd):
    """Head as the sheet shows it: octagonal prism with vertical sides and a chamfered, nearly flat top."""
    L = b.L
    L((dx, 0, dz), (dx, 0, dt), dr * 1.04, dr * 1.04, 'fur', seg=8)
    L((dx, 0, dt), (dx, 0, dt + dd * .55), dr * 1.04, dr * .82, 'fur', seg=8)           # chamfer
    L((dx, 0, dt + dd * .55), (dx, 0, dt + dd * .85), dr * .82, dr * .70, 'fur', seg=8)


# ── stage 0: hunched young gorilla (long horizontal trunk, head forward, round rump) ──────────
def stage0(b):
    g = lambda n, d: prm(0, n, d)                                         # every main dimension is fitted against the orthographic sheet
    E, L = b.E, b.L
    tx, tz = g('tx', .04), g('tz', .49)
    b.grp = 'body'
    E(tx, 0, tz, g('trx', .27), g('try', .25), g('trz', .24), 'fur', (0, -.22, 0))        # trunk
    E(g('hx', .13), 0, g('hz', .58), g('hrx', .19), g('hry', .27), g('hrz', .13), 'fur2')  # shoulder hump
    px, pz = g('px', -.12), g('pz', .34)
    E(px, 0, pz, g('prx', .15), g('pry', .20), g('prz', .17), 'fur')                       # rump
    for sg in (-1, 1):
        E(px - .05, sg * .08, pz - .04, .09, .09, .12, 'fur2')                             # round cheeks, clearly separated
        BX(b, tx + .18, sg * .07, .41, .05, .075, .07, 'skin', (0, .15, 0))                # pec lobes
    for z, w in ((.35, .09), (.31, .085), (.27, .075), (.23, .06)):                        # finer belly rows
        BX(b, tx + .21, 0, z, .035, w, .016, 'skin', (0, .15, 0))
    b.grp = 'head'
    dx, dz, dt, dr, dd = g('dx', .33), g('dz', .55), g('dt', .85), g('dr', .27), g('dd', .20)
    head_block(b, dx, dz, dt, dr, dd)
    head_plates(b, dx + .02, dt + dd - .01)
    face(b, dx - .01, dt - g('fzo', .17), g('fk', 1.3))
    sx, sy, sz = g('sx', .19), g('sy', .26), g('sz', .54)
    ex, ey, ez = g('ex', .26), g('ey', .33), g('ez', .31)
    ax, ay = g('ax', .38), g('ay', .31)
    a1, a2 = g('ar1', .16), g('ar2', .14)
    lx, ly, fx = g('lx', -.15), g('ly', .25), g('fx', -.05)
    bxo = g('bxo', 0.0)                                                                    # x offset of the back bulbs (spine columns)
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        E(sx, sg * sy, sz, .14, .14, .14, 'fur2')
        L((sx, sg * sy, sz), (ex, sg * ey, ez), a1, a2, 'fur', seg=8)
        L((ex, sg * ey, ez), (ax, sg * ay, .10), a2, a2, 'fur', seg=8)
        foot(b, ax + .01, sg * ay, .95)                                                    # gray hand block
        bulb(b, sx + .01, sg * (sy + .09), sz + .05, .12, .10, .12, rot=(0, 0, sg * .4))   # shoulder bulb
        bulb(b, ex - .01, sg * (ey + .06), ez + .05, .12, .095, .13, 'copper2', 'copper')
        bulb(b, ax + .04, sg * ay, .17, .11, .095, .12)
        b.grp = 'leg_' + sd
        E(lx + .02, sg * ly, .28, .14, .13, .16, 'fur2')
        L((lx, sg * ly, .28), (fx - .01, sg * (ly - .01), .10), g('lr1', .15), g('lr2', .11), 'fur', seg=8)
        foot(b, fx, sg * (ly - .01), 1.0)
        bulb(b, fx + .10, sg * ly, .19, .13, .10, .13)                                     # knee
        b.grp = 'body'
        bulb(b, lx + .03, sg * (ly + .06), .30, .10, .075, .11, 'copper2', 'copper')       # thigh
        bulb(b, tx + .16, sg * .26, .43, .09, .07, .10, 'copper2', 'copper')
        for (x, y, z, r, tp, bt) in ((-.04, .15, .70, .06, 'copper2', 'copper'), (-.13, .17, .62, .06, 'crys', 'copper'),   # side columns
                                    (-.20, .20, .52, .06, 'copper2', 'copper'), (-.22, .24, .40, .055, 'crys', 'copper')):
            bulb(b, x + .05 + bxo, sg * y, z, r * .95, r * .85, r, tp, bt)
    b.grp = 'body'
    for (x, z, r) in ((.09, .80, .085), (.01, .75, .08), (-.07, .68, .08), (-.15, .60, .075), (-.21, .52, .07)):   # blue-silver column down the spine
        bulb(b, x + bxo, 0, z, r, r * 1.05, r * .85, 'crys', 'copper')
    add_stones(b, 0)


# ── stage 1: broad, armoured ───────────────────────────────────────────────────────────────────
def stage1(b):
    g = lambda n, d: prm(1, n, d)                                         # main dimensions are fitted against the orthographic sheet
    E, L = b.E, b.L
    b.grp = 'body'
    tx, tz = g('tx', -.03), g('tz', .48)
    E(tx, 0, tz, g('trx', .30), g('try', .34), g('trz', .28), 'fur', (0, -.2, 0))
    px, pz = g('px', -.22), g('pz', .35)
    E(px, 0, pz, g('prx', .17), g('pry', .24), g('prz', .19), 'fur')
    for sg in (-1, 1):
        E(px - .05, sg * .09, pz - .04, .10, .10, .12, 'fur2')                # rump cheeks
        BX(b, tx + .25, sg * .09, .44, .05, .10, .085, 'skin', (0, .12, 0))   # pec lobes
        for i in range(5):                                                # thick copper collar: from the pauldron, round the neck, V to the chest centre
            E(tx + .30 + .012 * i, sg * (.32 - .066 * i), .585 - .03 * i, .06, .085, .05,
              'copper2' if i % 2 else 'copper', (sg * .55, 0, 0))
    for z, w in ((.36, .12), (.32, .115), (.28, .105), (.24, .095), (.20, .08)):   # finer abs
        BX(b, tx + .28, 0, z, .035, w, .016, 'skin')
    rx_, rz_ = g('rx', .0), g('rz', .72)
    BX(b, rx_, 0, rz_, .15, .30, .115, 'copper', bev=.9)                  # back roll: thick rounded block right behind the head, with bands
    for z in (rz_ - .08, rz_, rz_ + .08):
        BX(b, rx_, 0, z, .158, .308, .012, 'copper2', bev=.5)
    E(rx_, 0, rz_ + .11, .12, .27, .035, 'copper2')                       # lighter rounded top of the roll
    for (dxp, z, ry) in ((-.09, .64, .14), (-.13, .54, .13), (-.17, .44, .12)):   # three rounded plates down the spine
        E(px + dxp, 0, z, .06, ry, .075, 'copper')
        E(px + dxp - .035, 0, z + .015, .03, ry * .8, .05, 'copper2')
    b.grp = 'head'
    dx, dz, dt, dr, dd = g('dx', .24), g('dz', .58), g('dt', .90), g('dr', .29), g('dd', .205)
    head_block(b, dx, dz, dt, dr, dd)
    head_plates(b, dx + .02, dt + dd, 1.05, crest=True)
    face(b, dx - .01, dt - g('fzo', .17), g('fk', 1.32), brow=False)
    qx, qy, qz = g('qx', .08), g('qy', .50), g('qz', .60)
    sx, sy, sz = g('sx', .10), g('sy', .38), g('sz', .50)
    ex, ey, ez = g('ex', .19), g('ey', .43), g('ez', .28)
    ax, ay = g('ax', .30), g('ay', .41)
    a1, a2 = g('ar1', .16), g('ar2', .145)
    lx, ly, fx = g('lx', -.22), g('ly', .28), g('fx', -.08)
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        E(qx, sg * qy, qz, g('qrx', .18), g('qry', .17), g('qrz', .155), 'copper')                  # one smooth rounded shoulder block
        E(qx, sg * (qy - .01), qz + .125, .14, .13, .045, 'skin2')                                 # light gray-blue top, inside the footprint
        E(qx, sg * (qy + .01), qz - .12, .16, .15, .035, 'copper2')                                # lower rim, rounded
        L((sx, sg * sy, sz), (ex, sg * ey, ez), a1, a2, 'fur', seg=8)
        L((ex, sg * ey, ez), (ax, sg * ay, .10), a2, a2, 'fur', seg=8)
        foot(b, ax + .02, sg * ay, 1.05)                                                           # gray hand block
        bulb(b, ax + .06, sg * ay, .19, .12, .10, .125)                                            # forearm bulb
        b.grp = 'leg_' + sd
        E(lx + .03, sg * ly, .26, .15, .14, .18, 'fur2')
        L((lx, sg * ly, .26), (fx + .01, sg * (ly - .02), .10), g('lr1', .16), g('lr2', .12), 'fur', seg=8)
        foot(b, fx, sg * (ly - .02), 1.05)
        bulb(b, fx + .10, sg * ly, .20, .13, .105, .13, 'copper2', 'copper')                       # knee
        b.grp = 'body'
        bulb(b, lx + .01, sg * (ly + .09), .32, .10, .07, .11, 'copper2', 'copper')
        BX(b, tx - .03, sg * .30, .66, .12, .06, .10, 'copper', (sg * .35, -.15, 0))                # shoulder-blade plate
    add_stones(b, 1)


# ── stage 2: crowned king (leaning forward, spine crystals, thick ankle bracers) ──────────────
def stage2(b):
    g = lambda n, d: prm(2, n, d)                                         # main dimensions are fitted against the orthographic sheet
    E, L = b.E, b.L
    b.grp = 'body'
    E(g('tx', -.08), 0, g('tz', .44), g('trx', .34), g('try', .30), g('trz', .28), 'fur', (0, -.15, 0))      # barrel trunk
    E(g('shx', .02), 0, g('shz', .62), g('shrx', .22), g('shry', .42), g('shrz', .19), 'fur')               # broad shoulders
    E(.12, 0, .74, .18, .28, .10, 'fur2')                                 # trapezius slope
    E(.10, 0, .72, .15, .20, .13, 'fur')                                  # neck
    px, pz = g('px', -.30), g('pz', .30)
    E(px, 0, pz, g('prx', .22), g('pry', .27), g('prz', .22), 'fur')      # rump
    for sg in (-1, 1):
        E(px - .08, sg * .11, pz - .02, .14, .13, .16, 'fur2')
        BX(b, .25, sg * .11, .55, .07, .14, .115, 'skin')                  # big pec lobes
    for z, w in ((.47, .17), (.425, .165), (.38, .155), (.335, .145), (.29, .13), (.245, .11), (.20, .09)):   # finer ab rows
        BX(b, .27, 0, z, .035, w, .017, 'skin')
    b.grp = 'head'
    dx, dz, dt, dr, dd = g('dx', .20), g('dz', .62), g('dt', .90), g('dr', .265), g('dd', .19)
    top = dt + dd
    head_block(b, dx, dz, dt, dr, dd)
    face(b, dx - .03, dt - g('fzo', .17), g('fk', 1.3), brow=False)
    E(dx - .01, 0, top + .005, .175, .20, .035, 'copper')                 # crown: flat band resting on the head, spikes grow out of it
    E(dx - .01, 0, top - .035, .18, .205, .02, 'copper2')
    for sg in (-1, 0, 1):
        BX(b, dx + .16, sg * .09, top - .005, .012, .03, .03, 'crys2')
    for i in range(5):                                                    # crown crystals
        a = (i - 2) / 2
        ln = .30 if i == 2 else (.21 if i % 2 == 0 else .15)
        spike(b, (dx - .05 + .06 * math.cos(a * 1.4), a * .17, top + .01), (-.05, a * .32, 1), ln, .055 if i == 2 else .04,
              ('copper2', 'crys', 'crys2') if i % 2 == 0 else ('copper', 'copper2', 'crys'))
    sx, sy, sz = g('sx', .04), g('sy', .46), g('sz', .60)
    ex, ey, ez = g('ex', .11), g('ey', .52), g('ez', .34)
    ax, ay = g('ax', .16), g('ay', .46)
    a1, a2, a3 = g('ar1', .14), g('ar2', .17), g('ar3', .165)
    lx, ly, fx = g('lx', -.28), g('ly', .23), g('fx', -.17)
    for sg in (-1, 1):
        sd = 'p' if sg > 0 else 'n'
        b.grp = 'arm_' + sd
        E(sx, sg * sy, sz, .18, .17, .17, 'fur2')
        pw, ph = g('pw', 1.0), g('ph', 1.0)
        BX(b, sx, sg * (sy + .03), sz + .08, .15 * pw, .135 * pw, .025, 'copper2')         # tan rim plate
        E(sx, sg * (sy + .03), sz + .15, .14 * pw, .125 * pw, .10 * ph, 'gloss' if GLOSS else 'crys')    # blue mass
        spike(b, (sx - .02, sg * (sy + .04), sz + .17), (-.15, sg * g('cdy', .62), g('cdz', .55)), g('cl', .40), g('cr', .08))   # big diagonal crystal, outward
        spike(b, (sx - .02, sg * (sy - .04), sz + .19), (.0, -sg * .25, 1), .16 * g('cl', .40) / .40, .05)      # small inward crystal
        spike(b, (sx, sg * (sy + .12), sz + .14), (.0, sg * 1.0, .3), .16 * g('cl', .40) / .40, .045)           # side stub
        bulb(b, sx + .12, sg * (sy + .01), sz + .14, .05, .05, .05, 'copper2', 'copper', hl=False)   # tan ball on the front
        L((sx, sg * sy, sz), (ex, sg * ey, ez), a1, a2, 'fur', seg=8)
        L((ex, sg * ey, ez), (ax, sg * ay, .10), a2, a3, 'fur', seg=8)
        for z in (.30, .10):                                                         # bracer: tan bands top and bottom
            L((ax - .02, sg * (ay + .03), z - .018), (ax - .02, sg * (ay + .03), z + .018), g('br', .19), g('br', .19), 'copper2', seg=14)
        L((ax - .02, sg * (ay + .03), .12), (ax - .02, sg * (ay + .03), .28), g('br', .19) - .01, g('br', .19) - .01, 'fur3', seg=14)
        bulb(b, ax + .10, sg * (ay + .03), .20, .06, .11, .08, 'crys', 'copper', hl=False)   # bracer gem
        BX(b, ax - .02, sg * (ay + .24), .20, .015, .06, .08, 'crys2')                      # side crystal
        foot(b, ax + .01, sg * ay, 1.6)                                                      # gray hand block
        b.grp = 'leg_' + sd
        E(lx, sg * ly, .24, .21, .18, .20, 'fur2')
        L((lx, sg * ly, .24), (lx + .08, sg * ly, .10), .18, .15, 'fur', seg=8)
        for z in (.17, .09):                                                         # ankle bracer bands
            L((lx + .08, sg * ly, z - .02), (lx + .08, sg * ly, z + .02), .185, .185, 'copper2', seg=14)
        bulb(b, lx + .18, sg * ly, .13, .04, .09, .06, 'crys', 'copper', hl=False)
        foot(b, fx, sg * ly, 1.6)
        b.grp = 'body'
        E(px, sg * .30, .52, .06, .08, .09, 'copper')
    bxo = g('bxo', 0.0)
    for (x, y, z, ln, r) in ((.10, 0, .84, .26, .05), (-.04, 0, .78, .26, .055), (-.18, 0, .70, .24, .055), (-.30, 0, .60, .22, .05),
                              (-.04, .14, .76, .18, .04), (-.04, -.14, .76, .18, .04), (-.20, .13, .66, .17, .04), (-.20, -.13, .66, .17, .04)):
        spike(b, (x + bxo, y, z), (-.55, y * 1.6, .85), ln, r)                              # crystals along the spine
    for sg in (-1, 1):
        bulb(b, -.12 + bxo, sg * .26, .62, .07, .06, .075, 'crys', 'copper')
        bulb(b, -.26 + bxo, sg * .22, .52, .07, .06, .075, 'copper2', 'copper')
        for (x, y, z, r) in ((-.02, .10, .79, .05), (-.10, .20, .74, .055), (-.14, .08, .74, .05), (-.24, .14, .64, .05), (-.30, .20, .54, .055)):
            bulb(b, x + bxo, sg * y, z, r, r * .9, r, 'crys', 'copper2')


STAGES = {0: stage0, 1: stage1, 2: stage2}

BASE = dict(fur='#3b3340', fur2='#4c4252', fur3='#2a242e', skin='#7f8b9a', skin2='#6a768a', skin3='#97a2b0',
            foot='#8e99a8', foot2='#a2acba', crys='#5f88c0', stn='#5f88c0', crys2='#a9c4de', copper='#7c695a', copper2='#9d8b7a',
            st0='#b4bcc6', st1='#99a2ae', st2='#7f8996', st3='#666f7c', sw0='#b2b4b8', sw1='#9a9ca1', sw2='#82848a', sw3='#6a6c72')


def pal_for(st):
    pl = dict(BASE)
    pl.update(dark='#241a48', white='#ffffff', eyewhite='#e6ecfb', brow='#2a2438', gloss='#b9c6d8', mid='#8c97a8')
    return pl


def new_builder(st):
    """Builder with the per-stage lateral squash (YS) and bulb size (BS); the stage function then adds its primitives."""
    b = ph.P(pal_for(st), 1.0)
    nd = b.M['gloss'].node_tree.nodes['Principled BSDF']
    nd.inputs['Metallic'].default_value = 1.0
    nd.inputs['Roughness'].default_value = .24
    global YS, BS
    YS = prm(st, 'ys', {0: .90, 1: .96, 2: .76}[st])
    BS = prm(st, 'bs', {0: .92, 1: .88, 2: 1.0}[st])
    _E, _L = b.E, b.L

    def E2(x, y, z, rx, ry, rz, m, tilt=None):                           # body parts are squashed sideways, the head is not
        s = 1.0 if b.grp in HEADG else YS
        k = 1.0 if m in EYEMATS else INFLATE
        _E(x, y * s, z, rx * k, ry * s * k, rz * k, m, tilt)

    def L2(p0, p1, r0, r1, m, seg=12):
        s = 1.0 if b.grp in HEADG else YS
        k = 1.0 if m in EYEMATS else INFLATE
        _L((p0[0], p0[1] * s, p0[2]), (p1[0], p1[1] * s, p1[2]), r0 * k, r1 * k, m, seg)
    b.E, b.L = E2, L2
    return b


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = int(os.environ.get('GORILLA_DEPTH', 8))                  # 7 = chunkier voxels like the sheet's
    b = new_builder(st)
    STAGES[st](b)
    ob = tw.voxelise(b.objs)
    if POST:
        POST(ob, st)
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
        if v.startswith('o'):                                   # exact orthographic views for the sheet comparison (fixed frame)
            ctr = Vector((0, 0, .55))
            off = {'ofront': Vector((6, 0, 0)), 'oback': Vector((-6, 0, 0)), 'oside': Vector((0, -6, 0)), 'otop': Vector((0, 0, 6))}[v]
            co.location = ctr + off
            if v == 'otop':
                co.rotation_euler = (0, 0, math.pi / 2)         # image up = -x, so the face is at the bottom like in the sheet
            else:
                co.rotation_euler = (ctr - co.location).to_track_quat('-Z', 'Y').to_euler()
            cam.ortho_scale = 1.5
        else:
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
