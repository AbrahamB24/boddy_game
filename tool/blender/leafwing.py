"""Leaf line (3 stages): a green leaf-winged manta that grows into a leaf dragon (user sheet 2026-11-15).

    blender --background --python tool/blender/leafwing.py -- --out docs/renders/monsters/leafwing_vN [--stages 0,1,2] [--views front,q,side,back] --samples 12 --size 360

s0 flat manta-cube with two small leaf wings, horns, dorsal sprout, tail with a leaf tip; s1 bigger leaves swept back, longer curved tail;
s2 upright dragon with a cream belly, snout, horns and big fanned leaf wings, feet, tail with leaves.
Axes: x = forward, y = sideways, z = up. Groups: body, head, eye_p/n, wing_p/n, tail. Eyes: owl.eyes() = phoenix recipe.
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
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
import griffin as gr  # noqa: E402

V = Vector
SPREAD = False
FAST = False
VIEWS = dict(front=Vector((6.0, 0.01, 1.0)), side=Vector((0.01, -6.0, 1.0)), back=Vector((-6.0, 0.01, 1.0)), q=Vector((3.9, 5.0, 2.8)))
SE = gr.SE


def leaf(b, root, d, length, width, norm, mat='leaf', vmat='vein', thick=.028, curl=.25, droop=.0, veins=4):
    """Pointed leaf plate from root along d (length), width across (norm = face direction). Curl bends the sides up,
    droop bends the tip down along -norm. Darker midrib + side veins on the upper face."""
    d = V(d).normalized()
    root = V(root)
    s = d.cross(V(norm)).normalized()
    n = s.cross(d).normalized()
    nt, nv = 14, 7

    def wid(t):
        return width * max(.03, math.sin(math.pi * (t ** .78)) ** .85)

    def at(t, v, off=0.0):
        return (root + d * (length * t) + s * (wid(t) * v)
                + n * (curl * width * v * v * math.sin(math.pi * t * .9 + .2) - droop * length * t * t + off))

    bm = bmesh.new()
    layers = []
    for sgn in (1, -1):
        g = []
        for i in range(nt):
            t = i / (nt - 1)
            g.append([bm.verts.new(at(t, (j / (nv - 1)) * 2 - 1, sgn * thick)) for j in range(nv)])
        layers.append(g)
    for k, g in enumerate(layers):
        for i in range(nt - 1):
            for j in range(nv - 1):
                f = [g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1]]
                bm.faces.new(f if k == 0 else f[::-1])
    top, bot = layers
    for i in range(nt - 1):
        for j in (0, nv - 1):
            bm.faces.new([top[i][j], top[i + 1][j], bot[i + 1][j], bot[i][j]])
    for i in (0, nt - 1):
        for j in range(nv - 1):
            bm.faces.new([top[i][j], top[i][j + 1], bot[i][j + 1], bot[i][j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K._mesh('leaf', bm)
    ob = K._put(ob, b.M[mat], 0, True)
    ob['grp'] = getattr(b, 'grp', 'body')
    b.objs.append(ob)
    # veins: midrib + paired side veins, standing a little proud of the upper face
    up = thick + .012
    rr = max(.010, width * .07)
    b.L(tuple(at(.04, 0, up)), tuple(at(.93, 0, up)), rr, rr * .6, vmat, seg=6)
    for k in range(veins):
        t0 = .18 + .68 * k / max(1, veins)
        for sg in (-1, 1):
            b.L(tuple(at(t0, 0, up)), tuple(at(min(.95, t0 + .24), sg * .82, up)), rr * .65, rr * .4, vmat, seg=6)


def fan(b, sg, root, dirs, norm, mat='leaf', **kw):
    """Cluster of leaves from one root; dirs = [(dx, dy, dz, length, width)] for the +y side, mirrored by sg."""
    pn = 'p' if sg > 0 else 'n'
    for i, (dx, dy, dz, ln, wd) in enumerate(dirs):
        b.grp = 'wing_' + pn
        r = V((root[0], sg * root[1], root[2]))
        leaf(b, r, (dx, sg * dy, dz), ln, wd, (norm[0], sg * norm[1], norm[2]), mat if i % 2 == 0 else mat + '2', **kw)


def face(b, c, r, k, ey=.62, ex=.70, ez=.06):
    ow.eyes(b, (c[0] + r[0] * ex, r[1] * ey, c[2] + r[2] * ez), k)
    b.grp = 'head'


def horns(b, c, r, ln, spread=.52):
    for sg in (-1, 1):
        p0 = V((c[0] - r[0] * .15, sg * r[1] * spread, c[2] + r[2] * .78))
        p1 = p0 + V((-ln * .35, sg * ln * .25, ln))
        b.L(tuple(p0), tuple(p1), r[1] * .15, r[1] * .03, 'horn', seg=8)


def tailchain(b, pts, mat='body', sway=0.0):
    """Tail along pts (x, z, r); sway bends it sideways (+y) in a gentle S: out first, easing back a little at the tip."""
    b.grp = 'tail'
    n = len(pts) - 1
    ys = [sway * (math.sin(math.pi * .5 * (i / n) ** 1.1) ** 1.6 - .12 * (i / n) ** 4) for i in range(n + 1)]
    b.chain([(x, ys[i], z, r) for i, (x, z, r) in enumerate(pts)], mat)
    return ys[-1]


def panel(b, pts, thick, mat, n=(1, .15, .1)):
    """Flat membrane panel over the polygon pts (fan-triangulated around the centre), extruded +-thick along n."""
    pts = [V(p) for p in pts]
    n = V(n).normalized()
    c = sum(pts, V()) / len(pts)
    bm = bmesh.new()
    top = [bm.verts.new(p + n * thick) for p in pts]
    bot = [bm.verts.new(p - n * thick) for p in pts]
    ct, cb = bm.verts.new(c + n * thick), bm.verts.new(c - n * thick)
    m = len(pts)
    for i in range(m):
        j = (i + 1) % m
        bm.faces.new((ct, top[i], top[j]))
        bm.faces.new((cb, bot[j], bot[i]))
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K._mesh('panel', bm)
    ob = K._put(ob, b.M[mat], 0, True)
    ob['grp'] = getattr(b, 'grp', 'body')
    b.objs.append(ob)


def bezier(p0, p1, p2, n=4):
    """Points of a quadratic bezier curve from p0 over p1 to p2."""
    return [(1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2 for t in (j / n for j in range(n + 1))]


def vein(b, pts, r0, r1, mat='vein_lt'):
    """A tapering curved vein: short limbs through pts, radius r0 -> r1."""
    n = len(pts) - 1
    for j in range(n):
        b.L(tuple(pts[j]), tuple(pts[j + 1]), r0 + (r1 - r0) * j / n, r0 + (r1 - r0) * (j + 1) / n, mat, seg=6)


def organic_veins(b, sg, idx, W, a, c2, mid, thick, nrm=(1, .15, .1), n_pairs=1):
    """The pattern of one membrane panel, drawn like a real leaf: ONE clear midrib from the wrist to the scallop tip, and side veins
    in matching pairs, evenly spaced, all at the same angle, curving gently towards the tip and getting thinner towards the edge.
    No randomness, no twigs. Identical on both faces."""
    along = mid - W
    for face in (1, -1):
        up = V((nrm[0], nrm[1] * sg, nrm[2])).normalized() * (thick + .004) * face
        vein(b, bezier(W + along * .0 + up, W + along * .50 + up, mid + up, 6), .026, .018)
        for j in range(n_pairs):
            k = .56 + .30 * j / max(1, n_pairs - 1)                                 # evenly spaced along the midrib
            P = W + along * k + up
            for st in (a, c2):                                  # one vein to each side, mirror images of each other
                Q = W + (st - W) * min(.96, k + .22) + up
                Q = P + (Q - P) * 1.0
                ctrl = P + (Q - P) * .5 + along * .02           # the same gentle bow towards the tip on every vein
                vein(b, bezier(P, ctrl, Q, 4), .021, .015)


def strut_branches(b, sg, W, ends, thick, ks=(.40, .66), nrm=(1, .15, .1)):
    """The wing's only pattern: every finger strut W -> ends[i] carries a few branches, one to each side, all leaving at the same
    angle and bowed towards the tip, each stopping halfway to the neighbouring strut. The membrane between stays plain. Both faces."""
    for face in (1, -1):
        up = V((nrm[0], nrm[1] * sg, nrm[2])).normalized() * (thick + .004) * face
        for i, e in enumerate(ends):
            along = (e - W).normalized()
            for k in ks:
                P = W + (e - W) * k + up
                for j in (i - 1, i + 1):
                    if j < 0 or j >= len(ends):
                        continue
                    target = W + (ends[j] - W) * min(.97, k + .20) + up
                    Q = P + (target - P) * .38
                    ctrl = P + (Q - P) * .5 + along * .05
                    vein(b, bezier(P, ctrl, Q, 3), .020, .010)


def dragon_wing(b, sg, S, E, W, tips, B, scallop=.22, thick=.024, nrm=(1, .15, .1), arm=1.0, pairs=1):
    """Bat/dragon wing made of leaf: arm S -> E -> W (wrist), finger struts W -> tips (= the main ribs), a membrane panel between each pair
    of struts with a scalloped trailing edge, and an inner panel from the last strut to the body point B. Every panel is a leaf:
    midrib to the scallop tip + paired side veins running out to the struts."""
    pn = 'p' if sg > 0 else 'n'
    b.grp = 'wing_' + pn
    M = lambda p: V((p[0], sg * p[1], p[2]))  # noqa: E731
    S, E, W, B = M(S), M(E), M(W), M(B)
    T = [M(t) for t in tips]
    b.L(tuple(S), tuple(E), .054 * arm, .044 * arm, 'leaf3', seg=8)
    b.L(tuple(E), tuple(W), .044 * arm, .036 * arm, 'leaf3', seg=8)
    for t in T:
        b.L(tuple(W), tuple(t), .038, .016, 'vein_lt', seg=6)
    # the fingers' panels, then two panels towards the body (last finger -> body point B -> shoulder S): EVERY panel is a leaf with its own
    # midrib, so the inner part of the wing is no longer bare
    ends = list(zip(T, T[1:])) + [(T[-1], B), (B, S)]
    for i, (a, c2) in enumerate(ends):
        mid = (a + c2) / 2
        mid = mid + (W - mid) * (scallop if i < len(ends) - 1 else scallop * .6)
        panel(b, [W, a, mid, c2], thick, "memb" if i % 2 == 0 else "memb2", n=(nrm[0], nrm[1] * sg, nrm[2]))
    b.L(tuple(W), tuple(B), .034, .015, "vein_lt", seg=6)
    for i, (a, c2) in enumerate(ends):                  # every panel is a leaf: midrib + herringbone side veins
        mid = (a + c2) / 2
        mid = mid + (W - mid) * (scallop if i < len(ends) - 1 else scallop * .6)
        organic_veins(b, sg, i, W, a, c2, mid, thick, nrm, pairs)


# â”€â”€ shared pieces â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def smile(b, x, z, k=1.0, w=.05):
    """Tiny dark smile on the front of the head: a flat arc of small voxels."""
    b.grp = 'head'
    for i, (dy, dz) in enumerate(((-2, .018), (-1, .004), (0, 0), (1, .004), (2, .018))):
        b.E(x, dy * w * .5 * k, z + dz * k, .012 * k, .016 * k, .012 * k, 'dark')


def ear_nubs(b, c, r, k=1.0):
    """Small leaf nubs on the head sides (sheet: little side ears)."""
    for sg in (-1, 1):
        b.grp = 'head'
        leaf(b, (c[0] - r[0] * .1, sg * r[1] * .92, c[2] + r[2] * .35), (-.1, sg * 1, .55), .17 * k, .05 * k, (0, 0, 1), 'leaf2', curl=.05, veins=1, thick=.02)


def sprout(b, c, r, ln):
    b.grp = 'head'
    leaf(b, (c[0] - r[0] * .1, 0, c[2] + r[2] * .88), (-.15, 0, 1), ln, ln * .30, (1, 0, 0), 'leaf2', curl=.08, veins=2, thick=.022)


def membrane(b, sg, root, main, extra, norm, **kw):
    """One big leaf wing per side: a main leaf + a lower trailing leaf and a short front leaf that overlap it."""
    fan(b, sg, root, [main] + extra, norm, **kw)


# stage 0: chunky manta cube, small leaf wings flat out to the sides
def stage0(b):
    b.grp = 'body'
    SE(b, -.06, 0, .20, .34, .33, .17, 'body', e=.65)
    SE(b, .10, 0, .14, .26, .30, .10, 'belly', e=.65, ez=.5)
    b.grp = 'head'
    c, r = (.22, 0, .31), (.27, .31, .23)
    SE(b, *c, *r, 'body', e=.55)
    face(b, c, r, 1.15, ey=.50, ex=.92, ez=-.01)
    smile(b, c[0] + r[0] * .93, c[2] - r[2] * .42, 1.0, .06)
    horns(b, c, r, .15, .50)
    sprout(b, c, r, .26)
    main = (-.30, 1, .26, .85, .30)
    ex = [(-.80, .60, .20, .50, .20)]
    for sg in (-1, 1):
        membrane(b, sg, (-.02, .22, .27), main, ex, (0, -.25, 1), droop=.02, curl=.08, veins=1)
    ty = tailchain(b, [(-.30, .20, .09), (-.52, .17, .065), (-.70, .22, .045), (-.82, .34, .03)], sway=.26)
    b.grp = 'tailtip'
    leaf(b, (-.82, ty, .34), (-.2, .25, 1), .24, .06, (1, 0, 0), 'leaf2', curl=.05, veins=2, thick=.022)


# stage 1: bigger leaf wings, swept back, longer tail
def stage1(b):
    b.grp = 'body'
    SE(b, -.10, 0, .24, .42, .34, .19, 'body', e=.65)
    SE(b, .12, 0, .17, .31, .30, .12, 'belly', e=.65, ez=.5)
    b.grp = 'head'
    c, r = (.27, 0, .38), (.27, .31, .24)
    SE(b, *c, *r, 'body', e=.55)
    face(b, c, r, 1.15, ey=.50, ex=.92, ez=-.01)
    smile(b, c[0] + r[0] * .93, c[2] - r[2] * .42, 1.0, .06)
    ear_nubs(b, c, r, 1.1)
    horns(b, c, r, .16, .50)
    sprout(b, c, r, .30)
    tips = [(-.10, 1.20, 1.00), (-.48, 1.18, .82), (-.72, .92, .60)]
    for sg in (-1, 1):                                   # small dragon wing, held out sideways and a little up
        dragon_wing(b, sg, (-.04, .26, .36), (-.12, .55, .66), (-.18, .84, .92), tips, (-.44, .30, .42), scallop=.20, thick=.022, nrm=(.05, -.55, 1), arm=.8, pairs=1)
    for sg in (-1, 1):                                   # small feet: a front and a back pair, tiny toes
        b.grp = 'body'
        for fx in (-.20,):
            SE(b, fx, sg * .17, .05, .10, .08, .05, 'belly', e=.7)
            for k in (-1, 0, 1):
                b.E(fx + .09, sg * (.17 + k * .045), .025, .035, .02, .022, 'belly2')
    ty = tailchain(b, [(-.42, .24, .10), (-.68, .22, .07), (-.92, .27, .05), (-1.10, .42, .035), (-1.16, .60, .028)], sway=.34)
    b.grp = 'tailtip'
    leaf(b, (-1.16, ty, .60), (-.15, .25, 1), .30, .07, (1, 0, 0), 'leaf2', curl=.05, veins=2, thick=.022)


def pose(b, deg, piv, lift):
    """Hover pose: pitch every part forward by deg around piv (hips), then lift the whole thing off the ground."""
    from mathutils import Matrix
    p = V(piv)
    M = Matrix.Translation(V((0, 0, lift))) @ Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, 'Y') @ Matrix.Translation(-p)
    for ob in b.objs:
        ob.matrix_basis = M @ ob.matrix_basis


# stage 2: upright leaf dragon, two big leaf wings held up in a V, long tail curling out
def stage2(b):
    b.grp = 'body'
    SE(b, -.04, 0, .88, .27, .25, .34, 'body', e=.8)
    SE(b, -.05, 0, .46, .37, .34, .36, 'body', e=.8)
    SE(b, .14, 0, .74, .14, .18, .36, 'belly', e=.8)
    SE(b, .17, 0, .44, .20, .27, .28, 'belly', e=.8)
    for i in range(6):                                   # belly plates
        b.E(.22, 0, .36 + i * .14, .02, .135 - .008 * i, .05, 'belly2')
    b.grp = 'head'
    c, r = (.15, 0, 1.40), (.27, .26, .24)
    SE(b, *c, *r, 'body', e=.7)
    SE(b, c[0] + .24, 0, c[2] - .06, .18, .13, .10, 'body', e=.8)
    b.E(c[0] + .04, 0, c[2] - .26, .15, .14, .22, 'belly')          # cream throat running into the chest
    face(b, c, r, 1.3, ey=.60, ex=.88, ez=.08)
    b.E(c[0] + .41, .045, c[2] - .02, .012, .02, .016, 'dark')
    b.E(c[0] + .41, -.045, c[2] - .02, .012, .02, .016, 'dark')
    horns(b, c, r, .30, .44)
    sprout(b, c, r, .24)
    # dragon wing made of leaf: arm + 4 finger struts (= leaf ribs) with membrane panels between them, scalloped trailing edge
    tips = [(-.30, 1.48, 1.72), (-.52, 1.42, 1.22), (-.66, 1.12, .82), (-.54, .76, .60)]
    for sg in (-1, 1):
        dragon_wing(b, sg, (-.04, .22, 1.02), (-.14, .52, 1.34), (-.22, .82, 1.58), tips, (-.12, .30, .74))
    for sg in (-1, 1):
        b.grp = 'leg_' + ('p' if sg > 0 else 'n')
        b.E(.04, sg * .17, .24, .13, .11, .17, 'body')
        SE(b, .13, sg * .17, .07, .19, .11, .07, 'belly', e=.7)
        for k in (-1, 0, 1):
            b.E(.29, sg * (.17 + k * .055), .05, .05, .025, .03, 'belly2')
        b.grp = 'body'
        leaf(b, (-.20, sg * .26, .26), (-.5, sg * 1, .5), .26, .08, (0, 0, 1), 'leaf2', curl=.1, veins=2, thick=.022)   # hip leaves
    ty = tailchain(b, [(-.20, .22, .17), (-.48, .10, .13), (-.76, .14, .10), (-.98, .30, .07), (-1.06, .50, .05)], sway=.32)
    b.grp = 'tailtip'
    leaf(b, (-1.06, ty, .50), (-.1, .2, 1), .30, .09, (1, 0, 0), 'leaf', curl=.1, veins=2, thick=.022)
    leaf(b, (-1.06, ty, .50), (-.8, .3, .6), .26, .08, (0, 1, 0), 'leaf2', curl=.1, veins=2, thick=.022)
    pose(b, 20, (0, 0, .6), .55)


STAGES = {0: stage0, 1: stage1, 2: stage2}

BASE = dict(body='#97d264', belly='#cfe79c', belly2='#dff0b4', leaf='#8ccd58', leaf2='#79bb4a', vein='#6fae45', rib='#5a9a38', vein_lt='#bfe985', memb='#74b448', memb2='#68aa42', leaf3='#a6dc72', leaf4='#6aab42', horn='#b9de82',
            dark='#16241a', white='#ffffff', eyewhite='#e8f2cc', brow='#7fbe55')


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
        co.location = c + VIEWS[v]
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = tight(co, corners)
        sc.camera = co
        K.render(os.path.join(out, 'leafwing_s%d_%s.png' % (st, v)))


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
