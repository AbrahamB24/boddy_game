"""Griffin line (3 stages) from the user's voxel sheet (cream head/chest, yellow beak + bird feet, brown wings/body, lion tail).

    blender --background --python tool/blender/griffin.py -- --out docs/renders/monsters/griffin_vN [--stages 0,1,2] [--views front,q,side,back] --samples 12 --size 360
Compare: powershell -NoProfile -File tool/blender/griffin_cmp.ps1 <abs render dir> <sheet jpg> [progress png]
Measure: blender --background --python tool/blender/griffin_measure.py -- <abs render dir> <sheet jpg> [stages] [out png]

Measured on the sheet (all three rows share one scale, ~140 sheet px per world unit, floor at z = 0):
the HEAD stays about the same absolute size in every stage (~75 px wide = .27 half width, a rounded cube), only body, legs and
wings grow. Front legs = yellow bird feet, hind legs = brown lion paws. Wings: s0 tiny stubs out + back, s1 raised fans
(66 deg out in the front view, swept back 50 deg), s2 broad arch: arm up to a wrist at head-top height, long feathers
hanging DOWN and out like a cape. Side views: sheet stages 1/2 face left, stage 3 faces right (griffin_cmp/measure know).

Axes: x = forward (head), y = sideways, z = up. Groups: body, head, eye_p/n, wing_p/n (+wing_out_), legf_p/n, legh_p/n, tail.
Eyes: owl.eyes() = phoenix recipe.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import owl as ow  # noqa: E402
import phoenix as ph  # noqa: E402
import phoenix3 as p3  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

V = Vector
SPREAD = False
FAST = False
# compare cameras only (the game sprites use griffin_anim's own cameras). The sheet's 3/4 view is side-on (~52 deg)
# and its height differs per row of the AI sheet: stage 3 is seen almost level -> per-stage q elevation (Q_Z)
VIEWS = dict(front=Vector((6.0, 0.01, 1.0)), side=Vector((0.01, -6.0, 1.0)), back=Vector((-6.0, 0.01, 1.0)), q=Vector((3.9, 5.0, 1.6)))
Q_Z = {0: 1.6, 1: 1.6, 2: 0.9}


def SE(b, x, y, z, rx, ry, rz, m, e=.6, rot=None, ez=None, ex=None):
    """Rounded box (super-ellipsoid): e = 1 is an ellipsoid, smaller e gets boxier. ez = separate exponent for z. ex = separate exponent for x."""
    ez = e if ez is None else ez
    ex = e if ex is None else ex
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=1.0)

    def f(c, k):
        return math.copysign(abs(c) ** k, c)
    for v in bm.verts:
        v.co = V((f(v.co.x, ex) * rx, f(v.co.y, e) * ry, f(v.co.z, ez) * rz))
    ob = K._mesh('se', bm)
    ob.location = (x, y, z)
    if rot:
        ob.rotation_euler = rot
    ob = K._put(ob, b.M[m], 0, True)
    ob['grp'] = getattr(b, 'grp', 'body')
    b.objs.append(ob)


def lerp_poly(pts, u):
    """Point on a polyline of control points at u in [0, 1] (equal spacing per segment)."""
    n = len(pts) - 1
    if n == 0:
        return V(pts[0])
    t = min(n - 1e-6, max(0.0, u * n))
    i = int(t)
    f = t - i
    return V(pts[i]).lerp(V(pts[i + 1]), f)


def beak(b, x, z, s):
    """Yellow hooked eagle beak: broad upper mandible with a down-curved tip, lighter lower one. s = 1 -> .11 half width."""
    b.grp = 'head'
    E = b.E
    # flat upper mandible (user 2026-11-15: less tall/thick), hooked point, thin lower one
    # user 2026-11-15: heads narrower -> beak narrower, and the upper mandible KINKS DOWN (clear hook)
    E(x + .01 * s, 0, z + .030 * s, .065 * s, .140 * s, .042 * s, 'beak')         # broad flat top between the eyes
    E(x + .05 * s, 0, z + .005 * s, .085 * s, .115 * s, .046 * s, 'beak')          # long upper mandible, forward (user: wider)
    E(x + .105 * s, 0, z - .015 * s, .05 * s, .080 * s, .036 * s, 'beak')
    E(x + .130 * s, 0, z - .038 * s, .03 * s, .052 * s, .034 * s, 'beak2')          # the kink: bends down (shortened 2026-11-16)
    E(x + .142 * s, 0, z - .064 * s, .022 * s, .040 * s, .032 * s, 'beak2')         # short hook
    E(x + .05 * s, 0, z - .045 * s, .07 * s, .09 * s, .022 * s, 'beak2')           # lower mandible
    # user 2026-11-16: the top must be ARCHED upward (convex culmen), not a flat edge
    E(x + .025 * s, 0, z + .066 * s, .060 * s, .085 * s, .034 * s, 'beak')
    E(x + .080 * s, 0, z + .046 * s, .055 * s, .070 * s, .032 * s, 'beak')
    E(x + .125 * s, 0, z + .010 * s, .032 * s, .050 * s, .028 * s, 'beak')


def ears(b, c, r, tip_z, back=.10, lat=1.0):
    """Feather ears: a tuft of THREE separate feathers per side, laid back (pointing back and up) from the top-back corner
    of the head (user 2026-11-15: no vertical spike, no horns). Thick enough to read from the front as well."""
    for sg in (-1, 1):
        p = V((c[0] - r[0] * .05, sg * r[1] * .68 * lat, c[2] + r[2] * .62))
        h = tip_z - c[2] - r[2] * .62
        # three distinct feathers fanned from steep (front) to flat (back); roots step back along the head top
        # smooth tapered rods (one clean finger each, no segmented plates -> no jagged crown)
        for i, (dx, dy, dz, ln) in enumerate(((-.62, .30, .85, 1.00), (-.92, .18, .50, .95), (-1.0, .10, .12, .85))):
            d = V((dx, sg * dy, dz)).normalized()
            q = p + V((-r[0] * .22 * i, sg * r[1] * .03 * i, -.015 * i))
            # flat blade: wide in the fan plane (x/z), thin in y; norm is exactly sideways so the plate lies in the plane
            L = h * ln * 1.25
            cc = q + d * L * .5
            eul = ph.mr.basis_euler(d, V((0, sg, 0)))
            b.E(cc.x, cc.y, cc.z, L * .5, r[1] * (.26, .20, .15)[i], r[1] * (.26, .20, .15)[i], 'cream', eul)      # ONE smooth blade per feather


def feather(b, p, d, length, width, thick, mats, norm, taper=(1.0, .72, .38)):
    """gfeather2 with a chosen thickness (gfeather2's plates are 1 voxel thin): three tapering segments root -> tip."""
    d = V(d).normalized()
    p = V(p)
    eul = ph.mr.basis_euler(d, V(norm))
    for k, (t0, t1, m) in enumerate(((0, .58, mats[0]), (.50, .86, mats[1]), (.80, 1.0, mats[2]))):
        tc, half = (t0 + t1) / 2, (t1 - t0) / 2
        wf = taper[k]
        c = p + d * length * tc
        b.E(c.x, c.y, c.z, length * half, width * wf, thick * (1 - .25 * k), m, eul)


def prism(b, p0, p1, tip, thick, m):
    """Triangle p0-p1-tip extruded +-thick along x (all straight edges: voxelises to a clean stepped triangle)."""
    bm = bmesh.new()
    vs = []
    for dx in (-thick, thick):
        vs.append([bm.verts.new(V(p) + V((dx, 0, 0))) for p in (p0, p1, tip)])
    a, c = vs
    bm.faces.new(a[::-1])
    bm.faces.new(c)
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[i], a[j], c[j], c[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K._mesh('prism', bm)
    ob = K._put(ob, b.M[m], 0, True)
    ob['grp'] = getattr(b, 'grp', 'body')
    b.objs.append(ob)


def ears_old(b, c, r, tip_z, back=.10, lat=1.0):
    for sg in (-1, 1):
        base = V((c[0] - r[0] * .25, sg * r[1] * .72 * lat, c[2] + r[2] * .70))
        tip = V((base.x - back * 1.1, sg * (r[1] * .80 * lat), tip_z))
        b.L(tuple(base), tuple(tip), r[1] * .40, r[1] * .03, 'cream', seg=8)
        for i, (dx, dz, ln) in enumerate(((-.55, .85, .80), (-.85, .55, .62))):
            d = V((dx, sg * .12, dz)).normalized()
            p = base + V((-.03, 0, -.02 - .03 * i))
            b.gfeather2(p, d, (tip_z - base.z) * ln * 1.5, r[1] * .22, ('cream', 'cream2', 'cream2'), V((0, sg, 0)), (.5, .78))


def head(b, c, r, k, bs, tip_z, back=.10):
    b.grp = 'head'
    # user 2026-11-16: cat-shaped head -> broader than tall, shallower front-to-back, full cheeks tapering to a small chin,
    # ears wide-set at the top corners
    r = (r[0] * .94, r[1] * 1.07, r[2] * .92)
    for sg in (-1, 1):
        SE(b, c[0] + r[0] * .18, sg * r[1] * .64, c[2] - r[2] * .40, r[0] * .46, r[1] * .17, r[2] * .30, 'cream', e=.8)   # cheek puffs
    SE(b, *c, *r, 'cream', e=.86, ez=.78, ex=.88)           # boxy from the front, rounded front-to-back (eyes show in the side view)
    ke = k * 1.25
    ex, ey, ez = c[0] + r[0] * .68, r[1] * .54, c[2] + r[2] * .04
    ow.eyes(b, (ex, ey, ez), ke, patch=False)                  # phoenix eye recipe (dark eye, highlight, brow) ...
    for sg in (-1, 1):                                         # ... user 2026-11-16: too much white -> small, warm patch
        b.grp = 'eye_' + ('p' if sg > 0 else 'n')
        b.E(ex - .005 * ke, sg * (ey + .24 * .30), ez + .005 * ke, .030 * ke, .042 * ke, .052 * ke, 'eyewhite')
    b.grp = 'head'
    b.grp = 'head'
    beak(b, c[0] + r[0] * .97, c[2] - r[2] * .14, bs)
    b.grp = 'head'
    ears(b, c, r, tip_z, back, lat=1.12)
    collar(b, c, r)


def tri_feather(b, p, d, across, length, half, thick, m):
    """A flat TRIANGULAR feather (user 2026-11-16): base centre p, width 2*half along `across`, tip at p + d*length,
    thickness +-thick. All edges straight -> voxelises to a clean stepped triangle."""
    d = V(d).normalized()
    across = V(across).normalized()
    nm = d.cross(across).normalized()
    p = V(p)
    pts = (p - across * half, p + across * half, p + d * length)
    bm = bmesh.new()
    vs = [[bm.verts.new(q + nm * sg) for q in pts] for sg in (-thick, thick)]
    a, c = vs
    bm.faces.new(a[::-1])
    bm.faces.new(c)
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[i], a[j], c[j], c[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K._mesh('trifeather', bm)
    ob = K._put(ob, b.M[m], 0, True)
    ob['grp'] = getattr(b, 'grp', 'body')
    b.objs.append(ob)


def collar(b, c, r):
    """White feather collar all the way round the neck (user 2026-11-16: around the whole head/neck, not steep, with a
    feather shape). A low neck core fills the gap under the head; on it two staggered rings of flat feathers that flare
    outward and only ~25-35 deg downward (a ruff, not a hanging curtain). Front feathers merge with the bib."""
    b.grp = 'head'
    zc = c[2] - r[2] * .86
    cx = c[0] - r[0] * .12
    SE(b, cx, 0, zc + r[2] * .06, r[0] * .56, r[1] * .70, r[2] * .34, 'cream3', e=.8)   # smaller + darker: the feathers must be the visible surface
    # user 2026-11-16: rebuild the collar from TRIANGULAR feathers: 3 staggered rows laid like roof shingles round the neck,
    # every feather a clean pointed triangle, each row a different shade (upper = darkest) so every row and feather reads
    # user 2026-11-16: finer again (v112): 3 rows of 10 triangles, between v108 (3x12) and v111 (2x8)
    rows = ((10, .67, .42, 59, .01, 0.0, 'cream3'),
            (10, .71, .48, 63, -.06, .5, 'cream'),
            (10, .75, .55, 67, -.13, 0.0, 'cream2'))
    for row, (n, rad, ln, drop, dz, off, mt) in enumerate(rows):
        for i in range(n):
            th = 2 * math.pi * (i + off) / n
            ux, uy = math.cos(th), math.sin(th)
            rx, ry = r[0] * rad, r[1] * rad * 1.08
            p = V((cx + ux * rx, uy * ry, zc + r[2] * dz))
            al = math.radians(drop)
            d = V((ux * math.cos(al), uy * math.cos(al), -math.sin(al))).normalized()
            across = V((-uy, ux, 0))
            circ = 2 * math.pi * (rx + ry) / 2
            L = r[1] * ln * 1.15 * (1 - .45 * max(0.0, ux))     # shorter at the front
            tri_feather(b, p, d, across, L, circ / n * .56, r[2] * .08, mt)


def bib(b, c, r, vz, wf=.52):
    """Cream chest under the head: rounded upper block + a pointed V wedge of stepped feather rows down to z = vz
    (the tip points at the belly in the front and 3/4 views)."""
    b.grp = 'body'
    # upper block = the continuation of the head/neck (no wider than the shoulders, tall -> no hovering disc under the chin)
    SE(b, c[0], c[1], c[2] + r[2] * .10, r[0], r[1] * .40, r[2] * 1.0, 'cream', e=.7)   # full-size core = the cream chest (a smaller one sank into the body: no white)
    # user 2026-11-16: chest collar far too long -> ~55% of the old length, and built from INDIVIDUAL feathers (rows
    # narrowing to a V, every other row offset, alternating shade) like the neck collar
    z0 = c[2] + r[2] * .30
    zend = z0 - (z0 - vz) * .45
    R = 4 if r[2] < .25 else 5
    hz = (z0 - zend) / R
    wmax = r[1] * wf * .75
    fw = hz * .88
    sp = fw * 1.8
    for j in range(R):
        t = j / max(1, R - 1)
        half = wmax * (1 - .70 * t ** 1.1) + .02
        zj = z0 - hz * j
        nj = max(1, int(2 * half / sp) + 1)
        for i in range(nj):
            y = (i - (nj - 1) / 2) * sp + (sp / 2 if j % 2 else 0)
            if abs(y) > half + sp * .3:
                continue
            d = V((.42, y / max(wmax, .01) * .24, -.90)).normalized()
            nm = d.cross(V((0, 1, 0))).normalized()
            m1, m2 = ('cream', 'cream2') if (i + j) % 2 == 0 else ('cream3', 'cream')
            tri_feather(b, V((c[0] + r[0] * .94, y, zj)), d, V((0, 1, 0)), hz * 2.0, sp * .56, hz * .30, m1)


def edge_wing(b, sg, roots, tips, n, wid, rows=2, norms=((0, 0, 1),), mats=None, cut=(.55, .82), arm_r=.045, row_k=.30, out_from=1, gold=(), wk=.86, rachis=False, stagger=0.0):
    """Wing whose feathers run from points on the leading edge (roots polyline) to the tips polyline (both for sg = +1,
    mirrored by sg). Row 0 = long flight feathers, later rows = shorter coverts on top. Rows >= out_from go to wing_out_."""
    pn = 'p' if sg > 0 else 'n'
    b.grp = 'wing_' + pn
    M = lambda p: V((p[0], sg * p[1], p[2]))  # noqa: E731
    arm = [M(p) for p in roots]
    for p0, p1 in zip(arm, arm[1:]):
        b.chain([(p0.x, p0.y, p0.z, arm_r), (p1.x, p1.y, p1.z, arm_r * .85)], 'wing3')
    mats = mats or [('wing', 'wing2', 'tip'), ('wing2', 'wing2', 'tip'), ('wing3', 'wing', 'wing2')]
    for r in range(rows):
        b.grp = ('wing_out_' if (r >= out_from and r > 0) else 'wing_') + pn
        m = n + r
        for i in range(m):
            u = (i + .5) / m
            R = M(lerp_poly(roots, u))
            T = M(lerp_poly(tips, u))
            d = T - R
            ln = d.length * (1 - row_k * r)
            if stagger and i % 2:                       # alternate long/short -> scalloped trailing edge, every feather end reads
                ln *= 1 - stagger
            nm = lerp_poly(norms, u)
            nm = V((nm[0], sg * nm[1], nm[2]))
            R = R + V((.012 * r, sg * .012 * r, .006 * r))
            mt = mats[min(r, len(mats) - 1)]
            if i % 2:                                   # neighbouring feathers alternate shade -> separate feathers read
                mt = (mt[1], mt[0], mt[2])
            b.gfeather2(R, d.normalized(), ln, wid * (1 + .12 * r) * .86, mt, nm, (cut[0] - .07, cut[1] - .08))
            if rachis and r < 2:                        # user 2026-11-16: light centre rib per feather -> every feather reads on its own
                dn = d.normalized()
                cc = R + dn * ln * .50 + nm.normalized() * .016
                eul = ph.mr.basis_euler(dn, nm)
                b.E(cc.x, cc.y, cc.z, ln * .46, .011, .009, 'tip', eul)
    for u, f in gold:                                   # small golden accents (sheet stage 3: dotted gold line across the wing)
        b.grp = 'wing_' + pn
        P = M(lerp_poly(roots, u)).lerp(M(lerp_poly(tips, u)), f)
        b.E(P.x, P.y, P.z, .022, .03, .03, 'gold')


def tail(b, pts, tuft, s, tuft_n=5, td=(-1, 0, .1)):
    """Lion tail: brown cord through pts (x, z, r), cream tuft at the end pointing along td."""
    b.grp = 'tail'
    b.chain([(x, 0, z, r) for x, z, r in pts], 'brown')
    tx, tz = tuft
    b.E(tx, 0, tz, .09 * s, .065 * s, .07 * s, 'cream')
    d0 = V(td).normalized()
    for i in range(tuft_n):
        u = (i - (tuft_n - 1) / 2) / max(1, (tuft_n - 1) / 2)
        d = (d0 + V((0, u * .55, .35 * u * u - .1))).normalized()
        b.gfeather2(V((tx - d0.x * -.02, 0, tz)), d, .15 * s, .06 * s, ('cream', 'cream', 'cream2'), V((0, 0, 1)), (.5, .76))


def front_leg(b, sg, top, x_ank, y, r, fs, rr=None, upper=None):
    sd = 'p' if sg > 0 else 'n'
    b.grp = 'legf_' + sd
    if upper:                                   # thick feathered forearm under the chest
        b.E(top[0], sg * y, top[2], *upper, 'brown2')
    zy = .10 * fs                                # bird legs: feathered brown down to here, yellow scaly tarsus below
    b.L((top[0], sg * y, top[2]), (x_ank, sg * y, zy), r, rr or r * .85, 'brown2', seg=8)
    b.L((x_ank, sg * y, zy + .01), (x_ank + .01, sg * y, .02), r * .62, r * .62, 'foot', seg=8)
    ow.foot(b, x_ank + .01, sg * y, fs, toes=3, claw=True, mat='foot')


def hind_leg(b, sg, hip, thigh, x_ank, y, r, paw):
    """Lion hind leg: big thigh, shin down to a brown paw."""
    sd = 'p' if sg > 0 else 'n'
    b.grp = 'legh_' + sd
    hx, hz = hip
    b.E(hx, sg * y, hz, *thigh, 'brown')
    b.L((hx - thigh[0] * .3, sg * y, hz - thigh[2] * .4), (x_ank, sg * y, paw[2]), r, r * .85, 'brown', seg=8)
    SE(b, x_ank + paw[0] * .35, sg * y, paw[2], paw[0], paw[1], paw[2], 'brown2', e=.7)


# ── stage 0: chick ──────────────────────────────────────────────────────────────────────────────
def stage0(b):
    b.grp = 'body'
    SE(b, -.07, 0, .37, .36, .27, .17, 'brown', e=.75)
    b.E(.10, 0, .36, .16, .24, .14, 'brown2')
    bib(b, (.18, 0, .47), (.12, .25, .14), .20)
    head(b, (.14, 0, .76), (.26, .245, .235), .74, .82, 1.07, .22)
    for sg in (-1, 1):
        front_leg(b, sg, (.04, 0, .30), .04, .15, .085, 1.4)
        hind_leg(b, sg, (-.34, .34), (.12, .09, .14), -.38, .15, .07, (.08, .07, .04))
        edge_wing(b, sg, [(-.02, .21, .55), (-.06, .30, .64)], [(-.26, .32, .54), (-.12, .45, .70)], 5, .06, rows=1,
                  norms=((0, .2, 1),), arm_r=.045)
    tail(b, [(-.40, .44, .04), (-.54, .40, .035), (-.64, .45, .03)], (-.68, .46), .9, td=(-1, 0, .25))


# ── stage 1: juvenile, small wings raised and swept back ────────────────────────────────────────
def stage1(b):
    b.grp = 'body'
    SE(b, -.13, 0, .47, .53, .27, .20, 'brown', e=.8)
    b.E(.22, 0, .48, .20, .27, .21, 'brown2')
    bib(b, (.32, 0, .63), (.13, .26, .17), .33)
    head(b, (.27, 0, 1.00), (.30, .26, .30), .82, 1.05, 1.40, .24)
    for sg in (-1, 1):
        front_leg(b, sg, (.06, 0, .30), .05, .17, .10, 1.9, upper=(.11, .10, .12))
        hind_leg(b, sg, (-.52, .38), (.16, .11, .20), -.56, .16, .09, (.09, .085, .04))
        edge_wing(b, sg, [(-.02, .24, .80), (-.28, .42, 1.10)], [(-.64, .36, .70), (-.66, .52, .98), (-.74, .62, 1.32)], 9, .085, rows=3,
                  norms=((1, .4, .2), (1, .3, .3)), arm_r=.055)
    tail(b, [(-.64, .62, .045), (-.78, .55, .04), (-.92, .66, .035)], (-.96, .69), 1.1, td=(-1, 0, .3))


# ── stage 2: adult, broad arched wings, long lion tail ─────────────────────────────────────────
def stage2(b):
    b.grp = 'body'
    SE(b, -.04, 0, .68, .58, .29, .30, 'brown', e=.8)        # shoulders far too wide before (user 2026-11-15)
    b.E(.38, 0, .70, .26, .29, .31, 'brown2')
    bib(b, (.52, 0, .87), (.18, .64, .29), .34, wf=.58)
    head(b, (.42, 0, 1.28), (.38, .30, .33), .86, 1.2, 1.72, .14)
    for sg in (-1, 1):
        front_leg(b, sg, (.32, 0, .52), .32, .24, .11, 2.5, upper=(.15, .13, .17))
        hind_leg(b, sg, (-.50, .58), (.22, .15, .28), -.55, .24, .12, (.12, .10, .045))
        # broad arch: arm up to the wrist at head-top height, hand out and back, long feathers hanging DOWN and out
        # leading edge with a sharp WRIST corner (Fluegelbug) at the top: arm straight up-out, hand straight down-out
        # measured on the sheet: top edge flat at z ~1.56 from y .45 to the corner, outer edge drops to y 1.14,
        # feather ends low and out (front), corner ~.6 behind the head centre (side)
        # sheet (front): flat top edge at z ~1.5 out to a sharp corner at y ~1.04, outer edge falls ~vertically, tips low;
        # (side): leading edge stays near the shoulder, feathers sweep BACK going down -> wing plane tilts back ~30 deg
        # (overlay vs sheet: the sheet wing reaches further BACK and its lower outer edge flares OUT; our top corner was too high/out)
        # user 2026-11-15: the wing needs a sharp CORNER top-outer: flat top edge, then a vertical outer edge (last root segment)
        # sheet: the wing is a TRIANGLE-ish leaf, narrow at the shoulder (inner feathers short, trailing edge a steep diagonal)
        # and widest at the low outer tip
        # STRONG knick: the leading edge climbs to a peak wrist at (y .98, z 1.68), then folds sharply down the outer edge
        # (peak must stay at head-top height: the sheet's cream top == bbox top)
        # user 2026-11-15 (3 crops): (1) the top-outer corner ROUNDED and swinging down the outer edge in one curve, (2) the bottom
        # edge first rises slightly, then drops into the point, (3) in the side view the wing is not flat: the outer part kinks BACK
        edge_wing(b, sg, [(x - .14, y, z) for x, y, z in [(.04, .30, 1.05), (-.04, .36, 1.44), (-.12, .50, 1.52), (-.24, .72, 1.55), (-.40, .90, 1.58), (-.54, 1.02, 1.50), (-.60, 1.06, 1.32)]],  # wings sit .14 further back on the back (user 2026-11-16)
                  # sheet: the feathers are parallel DIAGONAL straps (down + outward), steeper towards the outer edge, so the
                  # tips sit well outside their roots on the inner part of the wing
                  # user 2026-11-15: wing must stand more UPRIGHT and hug the body (no gap at the inner bottom): inner tips closer in
                  [(x - .14, y, z) for x, y, z in [(-.20, .52, .96), (-.34, .62, .98), (-.52, .82, .80), (-.70, .98, .58), (-.82, 1.06, .42), (-.90, 1.10, .32), (-.94, 1.12, .30)]], 16, .085, rows=3,
                  mats=[('wing2', 'wing', 'tip'), ('wing', 'wing2', 'tip'), ('wing3', 'wing', 'wing2')],
                  norms=((1, -.1, 0), (1, .2, 0), (1, .6, 0)), arm_r=.07, row_k=.32, cut=(.62, .9), wk=.62, rachis=True, stagger=.13,
                  gold=((.55, .42), (.68, .45), (.80, .48), (.92, .52)))
    tail(b, [(-.62, .74, .05), (-.82, .56, .04), (-1.02, .46, .035), (-1.20, .45, .035)], (-1.27, .45), 1.3, td=(-1, 0, .05))


STAGES = {0: stage0, 1: stage1, 2: stage2}

BASE = dict(cream='#dbcda7', cream2='#e5dbbc', cream3='#cbbc92', brown='#ad7849', brown2='#9a6638', wing='#76492a', wing2='#a06a35', wing3='#5c3818',
            tip='#d4a465', gold='#e0aa22', beak='#e8b030', beak2='#d89a20', foot='#eab42c', claw='#9a7418', dark='#1d1a48', white='#ffffff',
            eyewhite='#d2c394', brow='#cdb98c')


def pal_for(st):
    return dict(BASE)


def tight(co, corners):
    """Ortho scale that just fits the object's bounding box in this view (+8%)."""
    bpy.context.view_layer.update()
    inv = co.matrix_world.inverted()
    pts = [inv @ p for p in corners]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    h = max(p.y for p in pts) - min(p.y for p in pts)
    return max(w, h) * 1.08


def render_all(st, out, views, samples, size, cached=False):
    """views == ['none']: only build + voxelise and save <out>/vox_s<st>.blend. cached: render from that file
    (voxelising takes 1.5-3 min, so the compare loop splits it from the renders)."""
    import time
    t0 = time.time()
    blend = os.path.abspath(os.path.join(out, 'vox_s%d.blend' % st))
    if cached:
        bpy.ops.wm.open_mainfile(filepath=blend)
        ob = bpy.data.objects['voxels']
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        tw.SMOOTH_MATS = not FAST           # FAST: skip the exact boolean union (holes/cracks; silhouette only)
        tw.DEPTH = 8
        b = ph.P(pal_for(st), 1.0)
        STAGES[st](b)
        print('TIME build %.1f' % (time.time() - t0))
        ob = tw.voxelise(b.objs)
        print('TIME voxelise %.1f' % (time.time() - t0))
        K.lighting(sky=0.9, sun=4.5)
        K.rim_light(Vector((-0.6, 0.5, 0.7)))
        if views == ['none']:
            bpy.ops.wm.save_as_mainfile(filepath=blend)
            return
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
    for v in views:
        cam = bpy.data.cameras.new('cam_' + v)
        cam.type = 'ORTHO'
        co = bpy.data.objects.new('cam_' + v, cam)
        sc.collection.objects.link(co)
        off = VIEWS[v] if v != 'q' else Vector((VIEWS[v].x, VIEWS[v].y, Q_Z[st]))
        co.location = c + off
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = tight(co, corners)
        sc.camera = co
        K.render(os.path.join(out, 'griffin_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='front')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--size', type=int, default=560)
    ap.add_argument('--fast', action='store_true')
    ap.add_argument('--cached', action='store_true')
    a = ap.parse_args(argv)
    global FAST
    FAST = a.fast
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for st in [int(s) for s in a.stages.split(',')]:
        try:
            render_all(st, a.out, a.views.split(','), a.samples, a.size, a.cached)
        except Exception:
            print('FAILED', st)
            traceback.print_exc()


if __name__ == '__main__':
    main()
