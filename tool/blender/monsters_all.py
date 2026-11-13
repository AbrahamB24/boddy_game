"""All 30 monsters of the photo list, three stages each, as voxels (Glimmergnaw recipe).

    blender --background --python tool/blender/monsters_all.py -- \
        --only cinderchick,scorchling --out docs/renders/monsters/all3 [--samples 40]

Writes <id>_s0.png, <id>_s1.png, <id>_s2.png. All three stages of one monster share the same
camera zoom, so growth between stages is visible. Facing +x, z up.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute_monsters as cm  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

SC = [1.0, 1.22, 1.5]                 # overall growth per stage

FIRE = dict(glow=('#ffd36b', '#ff7a14', 2.2), glow2=('#ff7a2e', '#e83c08', 2.0))
ICE = dict(glow=('#bff0ff', '#4fd0ff', 1.3), glow2=('#9ad8ff', '#3fb0ff', 1.1))
YEL = dict(glow=('#fff29a', '#ffe030', 1.6), glow2=('#ffd23a', '#ffb800', 1.4))
GRN = dict(glow=('#d6ff8a', '#8ae83a', 1.3), glow2=('#8aff9a', '#30d060', 1.2))
PUR = dict(glow=('#c8a0ff', '#a070ff', 1.4), glow2=('#9a70e8', '#7040d0', 1.2))
SUN = dict(glow=('#ffe08a', '#ffc21a', 1.5), glow2=('#ffb040', '#ff8a10', 1.3))
AQU = dict(glow=('#bff0ff', '#4fd0ff', 1.1), glow2=('#8ad8ff', '#2fa8f0', 1.0))
CYN = dict(glow=('#9ff0ff', '#3fd0ff', 1.3), glow2=('#7affc8', '#20e8a0', 1.2))


class S(cm.B):
    """The kit builder with a global scale, so one function builds all three stages."""
    def __init__(s, pal, k):
        super().__init__(pal)
        s.k = k

    def E(s, x, y, z, rx, ry, rz, m, tilt=None):
        k = s.k
        super().E(x * k, y * k, z * k, rx * k, ry * k, rz * k, m, tilt)

    def L(s, p0, p1, r0, r1, m, seg=12):
        k = s.k
        super().L(tuple(v * k for v in p0), tuple(v * k for v in p1), r0 * k, r1 * k, m, seg)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def quad(b, st, body='body', belly='belly', head='body', foot='paw', bl=.44, bw=.30, bh=.28, zc=.40,
         hr=(.35, .33, .31), lr=.085, muz=.14, ear='round', er=.10, eyer=.10, nose=True, legs=True):
    """The shared four-legged chibi: body, belly, legs, head, muzzle, eyes, ears."""
    bl *= [1, 1.08, 1.18][st]
    hs = [1, .93, .86][st]
    hr = tuple(v * hs for v in hr)
    b.E(0, 0, zc, bl, bw, bh, body)
    b.E(bl * .28, 0, zc - .06, bl * .7, bw * .78, bh * .75, belly)
    if legs:
        b.legs4(bl * .6, -bl * .6, bw * .62, zc - .1, lr, body, foot)
    hx, hz = bl * .92, zc + .28
    b.E(hx, 0, hz, *hr, head)
    if muz:
        mx = hx + hr[0] * .80
        b.E(mx, 0, hz - hr[2] * .22, muz, muz * .92, muz * .72, belly)
        if nose:
            b.nose((mx, 0, hz - hr[2] * .22), (muz, muz * .92, muz * .72), .045, 10)
    b.eyes((hx, 0, hz), hr, eyer, 36, 10)
    if ear == 'round':
        b.E2(hx - .05, hr[1] * .72, hz + hr[2] * .85, er, er * .7, er, head)
    elif ear in ('point', 'long'):
        h = er * (3.2 if ear == 'point' else 5.0)
        b.L2((hx - .04, hr[1] * .55, hz + hr[2] * .8), (hx - .10, hr[1] * .85, hz + hr[2] * .8 + h), er * 1.2, .015, head)
    return dict(hx=hx, hz=hz, hr=hr, bl=bl, bw=bw, bh=bh, zc=zc)


def stripes(b, q, xs, m='stripe'):
    for x in xs:
        t = math.sqrt(max(.05, 1 - (x / q['bl']) ** 2))
        b.E(x, 0, q['zc'], .03, q['bw'] * t * 1.08, q['bh'] * t * 1.08, m)


def upright(b, st, body='body', belly='belly', head='body', bw=(.36, .32, .38), z=.46, hr=(.38, .36, .32), hz=.82, eyer=.095):
    """Chibi standing blob: body + belly + big head with eyes. Returns the head anchor."""
    b.E(0, 0, z, *bw, body)
    b.E(.14, 0, z - .06, bw[0] * .66, bw[1] * .72, bw[2] * .78, belly)
    hs = [1, .94, .88][st]
    hr = tuple(v * hs for v in hr)
    b.E(.12, 0, hz, *hr, head)
    b.eyes((.12, 0, hz), hr, eyer, 36, 8)
    return dict(hx=.12, hz=hz, hr=hr)


def feather_wing(b, sg, p0, p1, n, ln, m1, m2, base='body', r=.08):
    b.L(p0, p1, r, .03, base)
    for i in range(n):
        t = (i + 1) / (n + 1)
        p = [p0[j] + (p1[j] - p0[j]) * t for j in range(3)]
        b.spike(p[0], p[1], p[2], ln * (1 - .15 * i), .05, -.2, sg * .9, m1 if i % 2 == 0 else m2)


# ═══════════════════ FIRE ═══════════════════
def cinderchick(st):
    pal = dict(body=['#d9402e', '#c62d2a', '#a8222a'][st], belly='#f6c35a', beak='#f0a030', **FIRE)

    def build(b):
        h = upright(b, st, bw=(.36, .32, .38))
        hx, hz, hr = h['hx'], h['hz'], h['hr']
        b.L((hx + .30, 0, hz - .04), (hx + .52, 0, hz - .12), .07, .025, 'beak')
        for i in range(1 + st):
            b.spike(hx - .02 - i * .06, 0, hz + hr[2] * .9, .26 + .08 * st, .06, .3 + .2 * i, 0, 'glow' if i % 2 == 0 else 'glow2')
        for sg in (-1, 1):
            feather_wing(b, sg, (0, sg * .30, .62), (-.08, sg * (.66 + .12 * st), .98 + .1 * st), 4 + st, .26 + .06 * st, 'glow', 'glow2')
        for i in range(2 + st):
            b.spike(-.30, (i - (1 + st) / 2) * .10, .36, .30 + .12 * st, .05, 1.2, 0, 'glow' if i % 2 == 0 else 'glow2')
        b.E2(.08, .14, .06, .12, .07, .05, 'beak')
        if st == 2:
            for i, y in enumerate((-.1, 0, .1)):
                b.spike(hx, y, hz + hr[2] * 1.2, .34 - abs(y), .06, 0, y * 2, 'glow')
    return pal, build


def scorchling(st):
    pal = dict(body=['#d8402e', '#c42f28', '#a62326'][st], belly='#f4d9a0', horn='#f0e0c0', wing='#e8a070',
               **FIRE)

    def build(b):
        h = upright(b, st, bw=(.34, .31, .38), z=.44, hr=(.40, .38, .34), hz=.88)
        hx, hz, hr = h['hx'], h['hz'], h['hr']
        b.E(hx + .36, 0, hz - .06, .14, .15, .10, 'body')                         # snout
        for sg in (-1, 1):
            b.L((hx - .06, sg * .18, hz + hr[2] * .8), (hx - .12, sg * (.24 + .04 * st), hz + hr[2] * .8 + .16 + .08 * st), .06, .015, 'horn')
            ws = .5 + .18 * st
            b.L((-.04, sg * .26, .62), (-.12, sg * ws, .94 + .12 * st), .06, .03, 'body')
            b.E(-.10, sg * ws * .75, .72 + .06 * st, .04, ws * .45, .26 + .08 * st, 'wing', (0, 0, sg * .35))
            b.E(.14, sg * .15, .06, .14, .09, .06, 'body')
        b.chain([(-.30, 0, .30, .12), (-.52, 0, .22, .09), (-.72, 0, .26, .06)], 'body')
        b.spike(-.72, 0, .28, .14 + .12 * st, .07, 0, 0, 'glow' if st else 'horn')
        for i in range(2 + st):
            b.spike(-.14 - i * .09, 0, .74 - i * .05, .14 + .03 * st, .05, .4, 0, 'horn')
        if st == 2:
            for (x, z) in ((.10, .40), (-.08, .56), (.20, .56)):
                b.E(.30, 0, z, .04, .04, .04, 'glow')
    return pal, build


def tigerember(st):
    pal = dict(body=['#f0a030', '#ee8f26', '#e87a1c'][st], belly='#fff0d0', paw='#c06a20', stripe='#5a2a18', **FIRE)

    def build(b):
        q = quad(b, st, ear='none', muz=.13, bl=.46)
        stripes(b, q, [-.22, -.08, .06, .20] if st < 2 else [-.28, -.16, -.04, .08, .20, .32])
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for sg in (-1, 1):
            b.L((hx - .04, sg * hr[1] * .55, hz + hr[2] * .8), (hx - .10, sg * hr[1] * .85, hz + hr[2] * .8 + .24), .12, .02, 'body')
            b.spike(hx - .10, sg * hr[1] * .85, hz + hr[2] * .8 + .22, .18 + .08 * st, .07, 0, 0, 'glow')
        b.chain([(-.40, 0, .36, .09), (-.62, 0, .44, .09), (-.72, 0, .62, .08)], 'body')
        b.spike(-.72, 0, .66, .30 + .08 * st, .09, .2, 0, 'glow'); b.spike(-.70, .04, .66, .2, .06, .6, .3, 'glow2')
        for i in range(1 + st * 2):
            b.spike(.20 - i * .10, 0, q['zc'] + q['bh'] * .95, .18 + .06 * st, .06, .3, 0, 'glow' if i % 2 == 0 else 'glow2')
    return pal, build


def embermane(st):
    pal = dict(body=['#e8b050', '#e0a040', '#d89030'][st], belly='#fff0d0', paw='#b8742c', mane='#c8702a', **FIRE)

    def build(b):
        q = quad(b, st, ear='round', er=.08, muz=.13)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        mr = [.46, .54, .62][st]
        b.E(hx - .08, 0, hz - .02, mr * .62, mr, mr * .95, 'mane')
        b.E(hx, 0, hz, *hr, 'body'); b.E(hx + hr[0] * .80, 0, hz - hr[2] * .22, .13, .12, .095, 'belly')
        b.nose((hx + hr[0] * .8, 0, hz - hr[2] * .22), (.13, .12, .095), .045, 10)
        b.eyes((hx, 0, hz), hr, .10, 36, 10)
        n = 8 + 3 * st
        for i in range(n):
            a = i / n * 2 * math.pi
            b.spike(hx - .10, math.sin(a) * mr * .92, hz + math.cos(a) * mr * .92, .16 + .05 * st, .06,
                    math.cos(a) * .6, math.sin(a) * .6, 'glow' if i % 2 == 0 else 'glow2')
        b.chain([(-.40, 0, .34, .06), (-.60, 0, .40, .06), (-.68, 0, .56, .06)], 'body'); b.E(-.68, 0, .64, .10, .10, .12, 'glow')
        if st == 2:
            for i, y in enumerate((-.14, 0, .14)):
                b.spike(hx - .04, y, hz + hr[2] * 1.0, .34 - abs(y) * .6, .06, 0, y * 1.5, 'glow')
            for (x, y, z) in ((.2, .5, .9), (-.3, -.5, .8), (.5, .4, 1.1), (-.1, -.4, 1.2)):
                b.E(x, y, z, .04, .04, .04, 'glow')
    return pal, build


# ═══════════════════ WATER ═══════════════════
def bubblepony(st):
    pal = dict(body=['#5fb3c8', '#4aa0c0', '#3a8cb8'][st], belly='#f0d8b0', fin='#a77ad8', **AQU)

    def build(b):
        pts = [(0, 0, .96, .20), (-.05, 0, .72, .22), (-.10, 0, .48, .19), (-.20, 0, .30, .13), (-.38, 0, .24, .09),
               (-.50, 0, .34, .07), (-.46, 0, .48, .06), (-.38, 0, .44, .05)]
        b.chain(pts, 'body')
        b.E(.10, 0, .60, .12, .16, .26, 'belly')
        b.E(.10, 0, 1.04, .22, .20, .20, 'body')
        b.chain([(.24, 0, 1.00, .08), (.44, 0, .96, .07)], 'body')
        b.eyes((.10, 0, 1.04), (.22, .20, .20), .08, 40, 12)
        for i in range(2 + st):
            b.spike(.0 - i * .05, 0, 1.2 - i * .02, .22 + .06 * st, .05, .3 + i * .3, 0, 'fin')
        b.E2(.0, .20, .66, .12, .04, .12, 'fin', (0.5, 0, 0))
        b.E(-.20, 0, .66, .04, .16, .24, 'fin')
        for (x, z) in ((.34, 1.38), (.22, 1.52), (.42, 1.58)):
            b.E(x, .1, z, .05, .05, .05, 'glow')
        if st >= 1:
            for k in range(3):
                b.E(-.06, 0, 1.18 + k * .02, .05, .05, .05, 'coral' if k % 2 else 'fin')
        if st == 2:
            for sg in (-1, 1):
                b.spike(.02, sg * .16, 1.16, .30, .05, .3, sg * .6, 'coral')
            b.E2(-.10, .26, .50, .22, .04, .14, 'fin', (0.4, 0, 0))
    pal['coral'] = '#f08a70'
    return pal, build


def tortide(st):
    pal = dict(body=['#7cc060', '#68b050', '#58a048'][st], belly='#e8e0a0', shell=['#9a6a40', '#8c5e38', '#7c5230'][st],
               tile='#b58450', coral='#f08a70', coral2='#f0c040', soil='#7a5a38', leaf='#4fa040', **AQU)

    def build(b):
        b.E(-.04, 0, .34, .46, .40, .28, 'shell')
        for (x, y, z, r) in ((0, 0, .60, .15), (.2, .12, .56, .11), (.2, -.12, .56, .11), (-.2, .12, .54, .11), (-.2, -.12, .54, .11), (-.02, .26, .44, .10), (-.02, -.26, .44, .10)):
            b.E(x, y, z, r, r, r * .45, 'tile')
        h = (.44, 0, .44)
        b.E(.40, 0, .42, .18, .14, .14, 'body')
        b.E(*h, .22, .22, .20, 'body'); b.eyes(h, (.22, .22, .20), .08, 42, 14); b.nose(h, (.22, .22, .20), .035, -20)
        for x, sg in ((.28, 1), (.28, -1), (-.30, 1), (-.30, -1)):
            b.E(x, sg * .38, .08, .15, .10, .06, 'body')
        b.chain([(-.46, 0, .20, .08), (-.62, 0, .16, .05)], 'body')
        if st >= 1:
            for (x, y, z) in ((-.10, .20, .62), (.06, -.16, .64), (-.24, -.12, .60)):
                b.E(x, y, z, .06, .06, .09, 'coral' if x > -.2 else 'coral2')
        if st == 2:
            b.E(-.04, 0, .74, .34, .30, .06, 'soil')
            b.L((-.10, 0, .78), (-.14, 0, 1.18), .05, .035, 'shell')
            for a in range(5):
                an = a / 5 * 2 * math.pi
                b.E(-.14 + math.cos(an) * .14, math.sin(an) * .14, 1.22, .14, .035, .05, 'leaf', (0, -.4, an))
            b.E(.12, .26, .62, .05, .05, .10, 'glow')
    return pal, build


def rilltail(st):
    pal = dict(body=['#7e8a96', '#6e7c8c', '#5e6e84'][st], belly='#c8d0d8', **AQU)

    def build(b):
        q = quad(b, st, belly='belly', foot='body', ear='round', er=.07, muz=.14, bl=.50, bw=.26, bh=.24, zc=.36, hr=(.33, .31, .29), lr=.075)
        b.chain([(-.46, 0, .34, .12), (-.74, 0, .28, .11), (-.98, 0, .22, .09), (-1.14, 0, .24, .06)], 'body')
        ribs = [0, 2, 3][st]
        for i in range(ribs):
            y = (-1) ** i * (.20 + .06 * i)
            b.chain([(.20 - i * .1, y, .88 + i * .06, .045), (-.10 - i * .1, y * 1.4, .98 + i * .06, .045), (-.42 - i * .1, y * 1.8, .82 + i * .06, .04)], 'glow2')
        if st == 2:
            b.E(0, 0, .96, .30, .10, .12, 'glow'); b.E(.1, 0, 1.08, .16, .05, .12, 'glow2')
            b.chain([(.30, .22, .70, .06), (.10, .30, .84, .06), (-.14, .26, .74, .05)], 'glow')
    return pal, build


def quackwave(st):
    pal = dict(body=['#f6d84a', '#f2e0a0', '#eaf4fa'][st], belly=['#fff0a0', '#fff6d0', '#ffffff'][st], beak='#f09a2a',
               wingc=['#9ad8f0', '#7ac8f0', '#6ac0f4'][st], **AQU)

    def build(b):
        if st < 2:
            h = upright(b, st, bw=(.38, .34, .36), z=.44, hr=(.36, .34, .32), hz=.88)
            hx, hz = h['hx'], h['hz']
            b.E(hx + .36, 0, hz - .10, .18, .14, .05, 'beak')
            b.E2(.0, .38, .50, .14, .07, .22, 'wingc', (0.3, 0, 0))
            b.E2(.08, .16, .05, .14, .09, .04, 'beak')
            b.chain([(-.34, 0, .34, .10), (-.46, 0, .42, .08)], 'body')
            if st == 1:
                for i in range(3):
                    b.spike(hx - .02 - i * .05, 0, hz + .30, .20, .06, .2 + i * .3, 0, 'glow')
        else:                                                      # swan
            b.E(0, 0, .44, .46, .32, .30, 'body'); b.E(.12, 0, .40, .34, .24, .22, 'belly')
            b.chain([(.32, 0, .56, .12), (.48, 0, .86, .10), (.40, 0, 1.14, .09), (.50, 0, 1.38, .09)], 'body')
            hh = (.60, 0, 1.46)
            b.E(*hh, .15, .13, .13, 'body'); b.eyes(hh, (.15, .13, .13), .06, 40, 10)
            b.E(.76, 0, 1.40, .10, .06, .04, 'beak')
            for sg in (-1, 1):
                b.E(-.04, sg * .34, .62, .34, .08, .26, 'wingc', (0.5 * sg, 0, 0))
                for i in range(4):
                    b.spike(-.14 - i * .12, sg * .40, .72, .26, .05, .6, sg * .5, 'glow')
            b.chain([(-.40, 0, .44, .10), (-.56, 0, .56, .09)], 'body')
            for (x, y, z) in ((.2, .4, 1.5), (-.2, -.5, 1.2), (.4, -.3, 1.7)):
                b.E(x, y, z, .06, .06, .06, 'glow')
    return pal, build


# ═══════════════════ PLANT ═══════════════════
def leafmoth(st):
    pal = dict(body='#8ed048', seg='#b8d858', brown='#8a5a38', leaf=['#5fc050', '#58b448', '#4aa83e'][st], petal='#f6a8c8',
               rib='#3c8a34', **GRN)

    def build(b):
        for i in range(4 + st):
            x = .26 - i * .22
            r = [.26, .24, .24, .22, .20, .18, .16][i] * (.9 + .1 * (i % 2))
            b.E(x, 0, r + .05, r, r * .95, r, 'body' if i % 2 == 0 else 'seg')
            b.E2(x, r * .5, .05, .06, .05, .06, 'brown') if i < 3 else None
        hr = (.26, .26, .26)
        h = (.38, 0, .34)
        b.E(*h, *hr, 'body'); b.eyes(h, hr, .09, 40, 8)
        for sg in (-1, 1):
            b.L((.36, sg * .08, .56), (.28, sg * .20, .76), .02, .02, 'brown'); b.E(.28, sg * .20, .78, .04, .04, .04, 'brown')
        ws = [.38, .54, .70][st]
        for sg in (-1, 1):
            b.E(-.08, sg * .16, .56 + ws * .5, ws * .22, .03, ws * .55, 'leaf', (sg * .4, 0, 0))
            b.E(-.08, sg * .16, .56 + ws * .5, ws * .02, .035, ws * .5, 'rib', (sg * .4, 0, 0))
            if st == 2:
                for (z, rr) in ((.60, .06), (.82, .05), (1.0, .06)):
                    b.E(-.08, sg * (.26 + (z - .5) * .3), z + .1, rr, .04, rr, 'petal')
    return pal, build


def chromeleaf(st):
    pal = dict(body=['#8cd860', '#7ccb58', '#6cbc50'][st], belly='#f4f0b0', c1='#ff7a7a', c2='#ffd060', c3='#7ae0a0', c4='#7ab8f4',
               c5='#c08af0', branch='#7a5230', leaf='#4aa83e', **GRN)

    def build(b):
        b.L((-.80, 0, .20), (.80, 0, .20), .07, .06, 'branch', 10)
        b.E(0, 0, .46, .40, .22, .26, 'body'); b.E(.1, 0, .40, .28, .18, .18, 'belly')
        for i, m in enumerate(('c1', 'c2', 'c3', 'c4', 'c5')):
            b.E(.28 - i * .13, 0, .56 + .02 * (i % 2), .07, .20, .10, m)
        h = (.44, 0, .60)
        b.E(*h, .24, .24, .22, 'body'); b.eyes(h, (.24, .24, .22), .10, 44, 14)
        b.E(.54, 0, .52, .10, .14, .08, 'belly')
        for x, sg in ((.22, 1), (.22, -1), (-.20, 1), (-.20, -1)):
            b.E(x, sg * .24, .28, .08, .06, .10, 'body')
        sp = [(-.38, 0, .42, .10), (-.64, 0, .36, .09), (-.80, 0, .26, .08), (-.78, 0, .12, .07), (-.66, 0, .10, .06), (-.62, 0, .20, .05)]
        b.chain(sp, 'c1' if st == 0 else 'body')
        b.E2(.34, .16, .86, .06, .04, .10, 'c4')
        n = 2 + 2 * st
        for i in range(n):
            b.E(.34 - i * .10, 0, .76 + .06 * (i % 2), .08, .06, .06, 'leaf')
        if st == 2:
            for i in range(3):
                b.spike(.30 - i * .14, 0, .80, .26, .06, .2, 0, 'leaf')
            b.E(.0, 0, .76, .14, .12, .08, 'branch')
    return pal, build


def blossomfawn(st):
    pal = dict(body=['#c8844c', '#be7a44', '#b4703c'][st], belly='#f6e6cc', limb='#a8703c', hoof='#5c4632', dots='#fff3de',
               wood='#7a5a38', pink='#f6b0cc', **GRN)

    def build(b):
        q = quad(b, st, foot='hoof', ear='round', er=.08, muz=.12, bl=.42, bw=.27, bh=.26, zc=.46, hr=(.33, .30, .29), lr=.065)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for (x, y, z) in ((.10, .20, .68), (-.10, .18, .72), (.0, -.20, .70), (-.22, -.12, .66), (.18, -.12, .74)):
            b.E(x, y, z + .02, .05, .05, .03, 'dots')
        for sg in (-1, 1):
            b.chain([(hx - .02, sg * .10, hz + hr[2] * .9, .04), (hx - .08, sg * .16, hz + hr[2] + .20 + .08 * st, .035)], 'wood')
            tips = 1 + st
            for t in range(tips + 1):
                z = hz + hr[2] + .22 + .08 * st + t * .1
                b.chain([(hx - .08, sg * .16, hz + hr[2] + .16 + .08 * st, .03), (hx - .14 - t * .05, sg * (.26 + t * .08), z, .028)], 'wood')
                b.E(hx - .14 - t * .05, sg * (.26 + t * .08), z + .02, .06, .06, .06, 'pink')
        b.E(-.42, 0, .54, .07, .07, .08, 'belly')
        if st == 2:
            for (x, y, z) in ((.0, .4, 1.5), (.3, -.4, 1.4), (-.3, .3, 1.7)):
                b.E(x, y, z, .04, .03, .02, 'pink')
    return pal, build


def leafray(st):
    pal = dict(leaf=['#6fbf5a', '#62b250', '#54a648'][st], rib='#3a8a34', body='#8ad060', tree='#4a8a3a', trunk='#7a5a38', **GRN)

    def build(b):
        z0 = [.46, .62, .80][st]
        w = [.55, .70, .86][st]
        b.E(0, 0, z0, .52, w, .07, 'leaf')
        b.E(0, 0, z0 + .02, .50, .03, .07, 'rib')
        for sg in (-1, 1):
            b.E(-.1, sg * w * .55, z0 + .02, .22, .04, .075, 'rib', (0, 0, sg * .6))
        b.E(.30, 0, z0 + .06, .26, .24, .16, 'body')
        b.eyes((.30, 0, z0 + .06), (.26, .24, .16), .085, 42, 10)
        b.chain([(-.46, 0, z0, .05), (-.74, 0, z0 - .06, .04), (-.96, 0, z0 - .14, .03)], 'leaf')
        b.E(.54, 0, z0 - .02, .05, .08, .05, 'nose') if False else None
        for sg in (-1, 1):
            b.E(.44, sg * .10, z0 - .06, .06, .06, .06, 'glow')
        if st == 2:
            for (x, y) in ((-.1, .4), (.1, -.5), (-.3, -.2)):
                b.L((x, y, z0 + .05), (x, y, z0 + .22), .03, .025, 'trunk'); b.E(x, y, z0 + .30, .12, .12, .12, 'tree')
    return pal, build


# ═══════════════════ ICE ═══════════════════
def icepaw(st):
    pal = dict(body=['#a8724a', '#9a6642', '#8c5c3c'][st], belly='#e8cdb0', paw='#8c5c3c', plate='#cfeaff', **ICE)

    def build(b):
        q = quad(b, st, ear='round', er=.10, muz=.13, bl=.38, bw=.34, bh=.34, zc=.44, hr=(.38, .36, .33), lr=.11)
        for x in (q['bl'] * .6, -q['bl'] * .6):
            for sg in (-1, 1):
                for k in range(2 + st):
                    b.spike(x + .1, sg * (q['bw'] * .62 + (k - .5) * .05), .06, .16 + .05 * st, .04, 1.4, 0, 'glow' if k % 2 == 0 else 'glow2')
        if st >= 1:
            for sg in (-1, 1):
                b.spike(q['bl'] * .5, sg * q['bw'] * .8, q['zc'] + q['bh'] * .6, .22 + .06 * st, .06, .3, sg * .7, 'glow')
        if st == 2:
            for i in range(4):
                b.spike(.20 - i * .16, 0, q['zc'] + q['bh'] * .95, .26 - i * .02, .07, .2, 0, 'glow' if i % 2 == 0 else 'glow2')
            b.E(.0, 0, q['zc'] + .20, .26, .26, .10, 'plate')
        b.E(-.40, 0, .30, .10, .10, .10, 'body')
    return pal, build


def flakeseal(st):
    pal = dict(body=['#b8d4ec', '#a8c8e8', '#98bce4'][st], belly='#f0f8ff', slab='#dff2ff', tusk='#fffbe8', **ICE)

    def build(b):
        b.E(-.04, 0, .06, .72, .50, .10, 'slab')
        b.E(-.10, 0, .30, .52, .28, .24, 'body'); b.E(.0, 0, .24, .42, .22, .16, 'belly')
        h = (.46, 0, .62)
        b.E(*h, .32, .30, .28, 'body'); b.E(.74, 0, .52, .12, .13, .09, 'belly')
        b.nose((.74, 0, .52), (.12, .13, .09), .045, 8)
        b.eyes(h, (.32, .30, .28), .10, 38, 10)
        for sg in (-1, 1):
            b.E(.06, sg * .34, .20, .22, .07, .07, 'body', (0, 0, sg * -.6))
        b.E(-.60, 0, .20, .20, .12, .06, 'body', (0, -.3, 0))
        if st >= 1:
            for sg in (-1, 1):
                b.L((.70, sg * .07, .44), (.74, sg * .09, .22), .04, .015, 'tusk')
        n = [0, 2, 4][st]
        for i in range(n):
            b.spike(.12 - i * .16, 0, .50, .26 + .04 * i, .08, .1, 0, 'glow' if i % 2 == 0 else 'glow2')
        if st == 2:
            b.chain([(-.2, .2, .88, .05), (-.4, .1, 1.04, .05), (-.6, .2, 1.1, .045), (-.8, .1, 1.0, .04)], 'glow')
    return pal, build


def frostwaddle(st):
    pal = dict(body=['#7ea0c8', '#6e90c0', '#5c80b8'][st], belly='#f4f8fc', beak='#f3a43b', plate='#cfeaff', **ICE)

    def build(b):
        h = upright(b, st, bw=(.40, .36, .44), z=.48, hr=(.38, .36, .32), hz=.96)
        hx, hz = h['hx'], h['hz']
        b.L((hx + .32, 0, hz - .06), (hx + .52, 0, hz - .12), .075, .03, 'beak')
        for sg in (-1, 1):
            b.E(0, sg * .40, .50, .12, .06, .26 + .04 * st, 'body', (0.4 * sg, 0, 0))
            b.E(.14, sg * .15, .05, .17, .10, .05, 'beak')
        for i in range(3 + st):
            y = (i - (2 + st) / 2) * .11
            b.spike(hx - .0, y, hz + .28, .20 + .12 * st - abs(y) * .5, .06, .1, y * 1.5, 'glow' if i % 2 == 0 else 'glow2')
        if st == 2:
            b.E(.20, 0, .70, .22, .26, .16, 'plate')
            for sg in (-1, 1):
                b.spike(0, sg * .44, .70, .36, .07, .1, sg * 1.3, 'glow')
    return pal, build


def rimewing(st):
    pal = dict(body=['#bfe2f4', '#b0d8f2', '#a0ceee'][st], belly='#f0fbff', wingc='#d8f0fc', beak='#8ab8d8', **ICE)

    def build(b):
        b.E(0, 0, .56, .24, .22, .30, 'body', (0, .3, 0)); b.E(.08, 0, .50, .14, .16, .22, 'belly', (0, .3, 0))
        h = (.18, 0, .92)
        b.E(*h, .22, .21, .20, 'body'); b.eyes(h, (.22, .21, .20), .09, 40, 10)
        b.L((.34, 0, .92), (.72 + .1 * st, 0, .84), .035, .012, 'beak')
        for sg in (-1, 1):
            b.E(-.05, sg * .38, .88 + .06 * st, .16, .30 + .08 * st, .03, 'wingc', (sg * .5, 0, 0))
            b.E(-.30, sg * .36, .98 + .06 * st, .12, .22 + .06 * st, .025, 'wingc', (sg * .4, 0, 0))
        b.chain([(-.12, 0, .38, .07), (-.30, 0, .24, .06), (-.46, 0, .14, .04)], 'body')
        n = 3 + 2 * st
        for i in range(n):
            b.E(.1 - i * .12, (-1) ** i * (.3 + .06 * i), .5 - .03 * i, .035, .035, .035, 'glow')
        if st == 2:
            for sg in (-1, 1):
                b.chain([(-.30, sg * .06, .20, .05), (-.70, sg * .22, .16, .045), (-1.04, sg * .12, .26, .04), (-1.30, sg * .24, .34, .035)], 'glow2')
    return pal, build


# ═══════════════════ LIGHTNING ═══════════════════
def zapchick(st):
    pal = dict(body=['#f2dc88', '#eed070', '#e8c458'][st], belly='#fff6d0', beak='#f09a2a', cloud='#a8a4d0', **YEL)

    def build(b):
        h = upright(b, st, bw=(.38, .34, .40), z=.46, hr=(.38, .36, .33), hz=.88, eyer=.10)
        hx, hz = h['hx'], h['hz']
        b.L((hx + .34, 0, hz - .06), (hx + .54, 0, hz - .12), .07, .03, 'beak')
        for sg in (-1, 1):
            ws = .40 + .22 * st
            b.E(0, sg * ws * .6, .50 + .06 * st, .12, ws * .5, .08 + .04 * st, 'body', (sg * .3, .2, 0))
            b.E2(.06, .15, .05, .12, .08, .04, 'beak')
            if st >= 1:
                for i in range(3 + st):
                    b.spike(-.10 - i * .06, sg * (.30 + i * .1), .56 + .06 * st, .16, .04, .5, sg * .8, 'glow')
        for i in range(1 + st):
            b.spike(hx - .02 - i * .05, 0, hz + .30, .20, .05, .2 + i * .3, 0, 'glow')
        b.chain([(-.32, 0, .34, .09), (-.50, 0, .30, .07)], 'body')
        if st == 2:
            for (x, y, z, r) in ((-.4, .5, .9, .12), (-.5, -.4, .8, .12), (-.2, .7, .7, .10)):
                b.E(x, y, z, r, r, r * .8, 'cloud')
    return pal, build


def zapfox(st):
    pal = dict(body=['#f09a30', '#ec8a28', '#e67a20'][st], belly='#fff0d0', paw='#8a4a20', ear='#5a2a18', **YEL)

    def build(b):
        q = quad(b, st, ear='point', er=.085, muz=.14, bl=.42)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        n = 1 + st
        for i in range(n):
            y = (i - (n - 1) / 2) * .18
            b.chain([(-.36, 0, .36, .09), (-.58, y, .46, .11), (-.70, y * 1.6, .66, .10), (-.62, y * 2, .84, .08)], 'body')
            b.E(-.62, y * 2, .88, .07, .07, .10, 'belly')
        for sg in (-1, 1):
            for j, (dx, dz) in enumerate(((.0, .0), (.08, .12))):
                b.E(.0 + dx, sg * (.44 + .1 * j), .72 + dz + j * .12, .035, .035, .09, 'glow', (0, 0, sg * (.5 - j)))
        if st == 2:
            for k in range(12):
                a = k / 12 * 2 * math.pi
                b.E(hx - .2, math.sin(a) * .52, hz + math.cos(a) * .52, .04, .04, .04, 'glow')
    return pal, build


def voltwool(st):
    pal = dict(wool=['#f6e070', '#f2d85a', '#b4b0d8'][st], wool2=['#fff2a0', '#ffe888', '#d4d2f0'][st], face='#6a6068', leg='#5a5058',
               horn='#d8c8a0', **YEL)

    def build(b):
        for (x, y, z, r) in ((0, 0, .56, .34), (.18, .16, .52, .26), (.18, -.16, .52, .26), (-.22, .14, .58, .26), (-.22, -.14, .58, .26), (0, 0, .78, .24), (-.40, 0, .54, .20)):
            b.E(x, y, z, r, r * .95, r * .9, 'wool' if (x + y) < .1 else 'wool2')
        for x in (.22, -.24):
            b.L2((x, .16, .26), (x, .16, .06), .05, .04, 'leg'); b.E2(x + .03, .16, .05, .07, .06, .04, 'leg')
        h = (.50, 0, .66)
        b.E(*h, .24, .22, .24, 'face'); b.eyes(h, (.24, .22, .24), .08, 40, 8)
        b.E(.60, 0, .56, .10, .10, .08, 'face'); b.nose(h, (.24, .22, .24), .03, -22)
        b.E2(.44, .26, .74, .12, .05, .06, 'face', (0, 0, .5))
        if st >= 1:
            for sg in (-1, 1):
                b.chain([(.46, sg * .12, .84, .05), (.40, sg * .26, .94, .045), (.34, sg * .34, .84, .04), (.38, sg * .34, .72, .035)], 'horn')
        if st == 2:
            for sg in (-1, 1):
                b.spike(.46, sg * .14, .90, .30, .06, .2, sg * .6, 'glow')
        n = 3 + 2 * st
        for i in range(n):
            a = i / n * 2 * math.pi
            b.E(-.1 + math.cos(a) * .52, math.sin(a) * .5, .72 + (i % 3) * .1, .035, .035, .08, 'glow', (0, 0, a))
    return pal, build


def stormfox(st):
    pal = dict(body=['#f0c050', '#ecb440', '#e6a830'][st], belly='#fff4d8', paw='#a8742c', **YEL)

    def build(b):
        q = quad(b, st, ear='long', er=.09, muz=.14, bl=.40, bw=.24, bh=.24, zc=.42 + .1 * st, hr=(.32, .30, .28), lr=.07)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for sg in (-1, 1):
            b.E(hx - .30, sg * .12, hz + .32 + .08 * st, .10, .04, .04, 'glow', (0, 0, 0)) if False else None
            b.spike(hx - .06, sg * hr[1] * .8, hz + hr[2] * .8 + .34, .20, .05, 0, sg * .1, 'glow') if st == 0 else None
        for sg in (-1, 1):
            b.spike(hx - .2, sg * .30, hz + .50 + .1 * st, .30, .05, .2, sg * .8, 'glow')
        if st >= 1:
            for i in range(5 + 3 * (st - 1)):
                a = (i - 3) / 6 * math.pi
                b.spike(hx - .16, math.sin(a) * hr[1] * 1.1, hz - .1 + math.cos(a) * hr[2] * 1.0, .18, .05, math.cos(a) * .6, math.sin(a) * .6, 'glow' if i % 2 else 'glow2')
        b.chain([(-.34, 0, .40, .08), (-.56, 0, .52, .08), (-.62, 0, .70, .07)], 'body')
        b.spike(-.62, 0, .72, .40 + .10 * st, .10, .5, 0, 'glow')
        for k in range(2 + st):
            b.E(-.74 - k * .08, 0, .88 + k * .14, .05, .05, .05, 'glow')
    return pal, build


# ═══════════════════ STONE ═══════════════════
def pebblebat(st):
    pal = dict(body=['#7a7480', '#6c6674', '#5c5868'][st], belly='#b4aebc', wingc='#9a94a8', inner='#c8b4d0', crys='#7fe0ff', **CYN)

    def build(b):
        b.E(0, 0, .44, .30, .27, .34, 'body'); b.E(.12, 0, .40, .20, .20, .26, 'belly')
        h = (.14, 0, .86)
        b.E(*h, .34, .32, .29, 'body'); b.eyes(h, (.34, .32, .29), .10, 36, 8)
        b.nose(h, (.34, .32, .29), .04, -14)
        for sg in (-1, 1):
            b.L((.08, sg * .16, 1.04), (-.02, sg * .30, 1.38 + .1 * st), .13, .02, 'body')
            b.L((.09, sg * .16, 1.04), (.0, sg * .28, 1.28 + .1 * st), .07, .02, 'inner')
            ws = .64 + .16 * st
            b.L((.0, sg * .26, .62), (-.06, sg * ws, .78 + .1 * st), .05, .03, 'body')
            b.E(-.10, sg * ws * .62, .52, .20, ws * .4, .03, 'wingc', (sg * .35, 0, 0))
            b.E(-.10, sg * ws * .90, .70 + .08 * st, .08, .06, .06, 'wingc')
            b.E2(.10, .14, .06, .13, .08, .05, 'body')
        if st >= 1:
            b.tooth(.40, .66, .06)
            for sg in (-1, 1):
                b.spike(.05, sg * .28, .96, .20 + .1 * st, .05, 0, sg * .3, 'glow')
        if st == 2:
            b.E(-.16, 0, .64, .12, .24, .10, 'crys')
            for sg in (-1, 1):
                b.E(.26, sg * .14, .94, .05, .04, .04, 'glow')
    return pal, build


def rubbleape(st):
    pal = dict(body=['#5e5a62', '#524e58', '#46424e'][st], belly='#8a8690', face='#7a7680', rock=['#8c8a84', '#9a9890', '#aaa89c'][st],
               moss='#6aa84f', **CYN)

    def build(b):
        b.E(0, 0, .56, .46, .42, .46, 'body'); b.E(.22, 0, .50, .28, .30, .34, 'belly')
        h = (.30, 0, 1.02)
        b.E(*h, .34, .32, .30, 'body'); b.E(.50, 0, .94, .16, .20, .13, 'face')
        b.eyes(h, (.34, .32, .30), .10, 36, 10); b.nose((.50, 0, .94), (.16, .20, .13), .045, 4)
        for sg in (-1, 1):
            b.L((.0, sg * .44, .84), (.30, sg * .56, .28), .16, .14, 'body'); b.E(.34, sg * .58, .20, .16, .12, .10, 'body')
            b.E2(.04, .24, .12, .22, .13, .10, 'body')
            b.E(.0, sg * .50, .96, .15 + .04 * st, .14 + .03 * st, .13 + .03 * st, 'rock')
        for i, (x, y, z, r) in enumerate(((-.2, .2, .96, .16), (-.2, -.2, .98, .15), (-.34, 0, .8, .18), (-.1, 0, 1.0, .12))[:2 + st * 1 + (1 if st else 0)]):
            b.E(x, y, z, r, r, r * .8, 'rock')
        if st == 2:
            b.E(.34, 0, .64, .05, .12, .05, 'glow'); b.E(.34, 0, .52, .05, .08, .05, 'glow')
            b.E(-.1, .2, 1.18, .08, .08, .06, 'moss')
    return pal, build


def gryphlet(st):
    pal = dict(body=['#b07a44', '#a46e3c', '#966434'][st], belly='#e8cc98', head='#f2ead8', beak='#f0b030', wing=['#8a5a34', '#7e5030', '#6e4628'][st],
               plume='#9a98a0', crys='#7fe0ff', **CYN)

    def build(b):
        q = quad(b, st, head='head', foot='beak', ear='none', muz=0, bl=.40, bw=.27, bh=.26, hr=(.34, .32, .30))
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        b.L((hx + hr[0] * .6, 0, hz - .04), (hx + hr[0] * 1.3, 0, hz - .12), .09, .02, 'beak')
        b.E(hx + hr[0] * .7, 0, hz - .08, .10, .09, .08, 'beak')
        for sg in (-1, 1):
            b.L((hx - .04, sg * hr[1] * .5, hz + hr[2] * .8), (hx - .10, sg * hr[1] * .7, hz + hr[2] * .8 + .16), .07, .015, 'head')
            ws = .34 + .2 * st
            b.L((0, sg * .22, .60), (-.10, sg * ws, .86 + .16 * st), .07, .03, 'wing')
            for i in range(4 + st):
                t = (i + 1) / (5 + st)
                p = (-.10 * t, sg * (.22 + (ws - .22) * t), .60 + (.26 + .16 * st) * t)
                b.spike(p[0], p[1], p[2], .26 + .06 * st, .06, -.2 + .1 * i, sg * .7, 'plume' if st == 2 and i % 2 else 'wing')
        b.chain([(-.40, 0, .40, .08), (-.62, 0, .34, .07), (-.74, 0, .20, .06)], 'body'); b.E(-.76, 0, .18, .09, .07, .10, 'belly')
        if st == 2:
            b.spike(hx - .02, 0, hz + hr[2] * .9, .30, .08, .2, 0, 'crys')
    return pal, build


def pebblephant(st):
    pal = dict(body=['#9cc4e0', '#8cb8d8', '#7caad0'][st], belly='#cfe4f2', rock='#8a8a8a', tusk='#fff6e0', snow='#f4faff',
               foot='#7a98b4', paw='#7a98b4', stone='#7a7a80', **dict(CYN, glow=('#bff0ff', '#4fd0ff', 1.2)))

    def build(b):
        q = quad(b, st, foot='foot', ear='none', muz=0, bl=.46, bw=.36, bh=.34, zc=.46, hr=(.36, .34, .32), lr=.12)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for sg in (-1, 1):
            b.E(hx - .10, sg * (hr[1] + .06), hz, .09, .22 + .04 * st, .24 + .04 * st, 'body', (0, 0, sg * .3))
            b.L((hx + .26, sg * .12, hz - .10), (hx + .34, sg * .20, hz - .30), .04, .015, 'tusk')
        b.chain([(hx + .30, 0, hz - .06, .10), (hx + .42, 0, hz - .22, .085), (hx + .44, 0, hz - .40, .07), (hx + .36, 0, hz - .52, .06)], 'body')
        if st < 2:
            for (x, y, z, r) in ((-.10, .14, .84, .16), (.10, -.12, .86, .14), (-.28, -.10, .80, .13))[:1 + st * 2]:
                b.E(x, y, z, r, r, r * .8, 'rock')
        else:
            b.E(-.06, 0, .84, .34, .30, .10, 'stone')
            b.L((-.06, 0, .88), (-.10, 0, 1.46), .30, .02, 'stone', 10)
            b.L((-.10, 0, 1.30), (-.10, 0, 1.52), .12, .01, 'snow', 10)
            b.E(.16, .12, .98, .035, .05, .20, 'glow')
        b.chain([(-.46, 0, .46, .05), (-.54, 0, .34, .04)], 'body')
    return pal, build


# ═══════════════════ LIGHT ═══════════════════
def goldkid(st):
    pal = dict(body=['#f6d46a', '#f2c850', '#eebc3a'][st], belly='#fff3cc', fleece='#f8e08a', hoof='#8a6a3a', horn='#e8d4a0', **SUN)

    def build(b):
        q = quad(b, st, ear='round', er=.08, muz=.12, foot='hoof', bl=.42, lr=.07)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for (x, y, z, r) in ((0, .0, q['zc'] + .16, .3), (.20, .12, q['zc'] + .12, .2), (-.20, .12, q['zc'] + .12, .2), (.20, -.12, q['zc'] + .12, .2), (-.20, -.12, q['zc'] + .12, .2)):
            b.E(x, y, z, r, r * .9, r * .75, 'fleece')
        b.E(hx, 0, hz + hr[2] * .85, .14, .12, .06, 'fleece')
        for sg in (-1, 1):
            b.chain([(hx - .02, sg * .12, hz + hr[2] * .8, .05), (hx - .10, sg * .20, hz + hr[2] + .16 + .05 * st, .045), (hx - .22, sg * .24, hz + hr[2] + .20 + .08 * st, .04), (hx - .28, sg * .22, hz + hr[2] + .06, .035)], 'horn')
        if st >= 1:
            b.E(hx - .10, 0, hz + hr[2] + .46, .12, .12, .12, 'glow')
            for i in range(8):
                a = i / 8 * 2 * math.pi
                b.spike(hx - .10, math.sin(a) * .12, hz + hr[2] + .46 + math.cos(a) * .12, .10, .03, math.cos(a) * 1.2, math.sin(a) * 1.2, 'glow2')
        if st == 2:
            for sg in (-1, 1):
                b.spike(hx - .22, sg * .24, hz + hr[2] + .24, .22, .05, 0, sg * .3, 'glow')
        b.E(-.40, 0, .5, .08, .06, .09, 'belly')
    return pal, build


def glowbell(st):
    pal = dict(dome='#b8e6f4', dome2='#c8b6f0', rim='#f4a8d8', face='#eaf8fc', tent='#9ad8f0',
               glow=('#ffe0f8', '#ff9ad8', 1.2), glow2=('#bff0ff', '#4fd0ff', 1.2))

    def build(b):
        zc = .70 + .14 * st
        b.E(0, 0, zc, .50, .50, .38, 'dome')
        b.E(0, 0, zc + .12, .38, .38, .30, 'dome2')
        for k in range(12):
            a = k / 12 * 2 * math.pi
            b.E(math.cos(a) * .46, math.sin(a) * .46, zc - .26, .10, .10, .07, 'rim')
        b.E(.26, 0, zc - .06, .20, .26, .18, 'face')
        b.eyes((.0, 0, zc), (.50, .50, .38), .10, 34, 4)
        n = 4 + 2 * st
        for k in range(n):
            a = k / n * 2 * math.pi
            x, y = math.cos(a) * .30, math.sin(a) * .30
            b.chain([(x, y, zc - .30, .05), (x * 1.2, y * 1.2, zc - .52, .045), (x * .9, y * .9, zc - .72, .04), (x * 1.1, y * 1.1, .10, .035)], 'tent')
            b.E(x * 1.1, y * 1.1, .08, .06, .06, .06, 'glow2')
        for (x, y, z) in ((.1, .3, zc + .5), (-.2, -.1, zc + .6), (.2, -.3, zc + .44)):
            b.E(x, y, z, .05, .05, .05, 'glow')
        if st == 2:
            for sg in (-1, 1):
                b.chain([(.1, sg * .3, zc - .3, .07), (-.2, sg * .5, zc - .6, .06), (-.3, sg * .46, .30, .05)], 'glow')
    return pal, build


def gleamowl(st):
    pal = dict(body=['#b8b4e0', '#a8a4d8', '#6a68b8'][st], belly='#e4e2f6', wingc=['#8c88c8', '#7c78c0', '#4a4898'][st], beak='#f0a040',
               ring='#e8e4ff', **dict(SUN, glow=('#fff2b0', '#ffe070', 1.6)))

    def build(b):
        h = upright(b, st, bw=(.38, .34, .42), z=.50, hr=(.40, .40, .34), hz=.98, eyer=.13)
        hx, hz = h['hx'], h['hz']
        for sg in (-1, 1):
            b.E(hx + .30, sg * .17, hz + .02, .04, .17, .17, 'ring')
        b.L((hx + .38, 0, hz - .06), (hx + .52, 0, hz - .14), .06, .02, 'beak')
        for sg in (-1, 1):
            b.L((hx - .04, sg * .24, hz + .30), (hx - .10, sg * .32, hz + .52), .11, .02, 'body')
            ws = .42 + .16 * st
            b.E(-.02, sg * ws * .75, .56, .12 + .03 * st, ws * .5, .30 + .06 * st, 'wingc', (0.3 * sg, 0, 0))
            b.E2(.10, .15, .05, .15, .09, .05, 'beak')
        n = 3 + 3 * st
        for i in range(n):
            a = i * 2.4
            b.E(math.cos(a) * .7, math.sin(a) * .7, .6 + (i % 4) * .28, .04, .04, .04, 'glow')
        if st == 2:
            for sg in (-1, 1):
                for i in range(4):
                    b.E(-.04, sg * (.5 + .1 * i), .46 + .12 * i, .05, .05, .05, 'glow')
        b.spike(hx - .06, 0, hz + .34, .16, .05, .2, 0, 'glow')
    return pal, build


# ═══════════════════ SHADOW ═══════════════════
def duskkit(st):
    pal = dict(body=['#3a3446', '#302a3e', '#262034'][st], belly='#524a64', paw='#2a2438', **dict(PUR, glow=('#d8b8ff', '#a070ff', 1.8)))

    def build(b):
        q = quad(b, st, ear='point', er=.085, muz=.12, bl=.40)
        hx, hz, hr = q['hx'], q['hz'], q['hr']
        for sg in (-1, 1):
            b.E(hx + hr[0] * .8, sg * hr[1] * .55, hz + .06, .045, .05, .05, 'glow')
        b.chain([(-.36, 0, .36, .08), (-.58, 0, .40, .08), (-.70, 0, .58, .07), (-.62, 0, .78, .06), (-.50, 0, .84, .05)], 'body')
        n = 3 + 3 * st
        for i in range(n):
            b.E(.34 - i * .14, ((-1) ** i) * .26, .74 + (i % 2) * .08, .06, .06, .06, 'glow2')
        if st == 2:
            for i in range(5):
                b.spike(.26 - i * .14, 0, q['zc'] + q['bh'] * .95, .28, .08, .5, 0, 'glow2')
        for k in range(4 + st * 2):
            a = k * 1.7
            b.E(math.cos(a) * .7, math.sin(a) * .5, .3 + (k % 3) * .3, .04, .04, .04, 'glow')
    return pal, build


def inkpuff(st):
    pal = dict(body=['#46406a', '#3a345c', '#2e2850'][st], belly='#6c6694', fin='#58528a', **dict(PUR, glow=('#d8b8ff', '#a070ff', 1.8)))

    def build(b):
        zc = .56 + .06 * st
        b.E(-.04, 0, zc, .36, .32, .44, 'body', (0, .3, 0))
        b.E(-.30, 0, zc + .34, .26, .22, .38, 'body', (0, .5, 0))
        b.E2(-.28, .24, zc + .40, .08, .22, .24, 'fin', (0, .5, 0))
        h = (.12, 0, zc - .06)
        b.eyes(h, (.40, .34, .36), .13, 34, 6)
        n = 4 + 2 * st
        for k in range(n):
            a = (k - (n - 1) / 2) / n * math.pi * 1.2
            y = math.sin(a) * .30
            b.chain([(.06, y * .6, zc - .30, .07), (.16, y, zc - .50, .06), (.20, y * 1.4, .20 + (k % 2) * .05, .05), (.34, y * 1.8, .08, .04)], 'body')
        for i in range(3 + st * 2):
            b.E(.2 + (i % 3) * .05, ((i % 5) - 2) * .09, zc + .22 - (i // 3) * .12, .035, .035, .035, 'glow')
        if st == 2:
            b.E(.0, .0, zc + .5, .10, .10, .10, 'glow')
    return pal, build


def duskhood(st):
    pal = dict(body=['#44425c', '#3a3852', '#302e48'][st], belly='#8a86a8', hood='#54526e', eye='#ffe070',
               **dict(PUR, glow=('#d8b8ff', '#a070ff', 1.8)))

    def build(b):
        r = [.17, .19, .22][st]
        spiral = []
        for i in range(16):
            a = i * .55
            spiral.append((-.3 - math.cos(a) * (.18 + i * .016), math.sin(a) * (.18 + i * .016), r * (1.0 - i * .02) + .02, r * (1.0 - i * .03)))
        b.chain(spiral, 'body')
        lift = [.5, .62, .78][st]
        neck = [(-.18, 0, .22, r), (-.12, 0, .34, r), (-.04, 0, .52, r * .95), (.0, 0, .72, r * .9), (.06, 0, lift + .20, r * .85)]
        b.chain(neck, 'body')
        hx, hz = .12, lift + .30
        b.E(hx - .06, 0, hz - .06, .10, .30 + .06 * st, .30 + .05 * st, 'hood')
        b.E(hx - .02, 0, hz - .16, .09, .18 + .04 * st, .20, 'belly')
        b.E(hx + .12, 0, hz + .04, .22, .20, .18, 'body')
        b.eyes((hx + .12, 0, hz + .04), (.22, .20, .18), .09, 38, 8)
        b.E(hx + .30, 0, hz - .06, .06, .07, .05, 'body')
        if st >= 1:
            b.E(hx - .17, 0, hz + .0, .02, .10, .10, 'glow')
        if st == 2:
            b.E(hx - .18, 0, hz + .02, .02, .17, .17, 'glow2'); b.E(hx - .19, 0, hz + .02, .02, .11, .11, 'hood')
        b.E(hx + .36, 0, hz - .10, .06, .02, .02, 'glow')
    return pal, build


SPECIES = {
    'cinderchick': cinderchick, 'scorchling': scorchling, 'tigerember': tigerember, 'embermane': embermane,
    'bubblepony': bubblepony, 'tortide': tortide, 'rilltail': rilltail, 'quackwave': quackwave,
    'leafmoth': leafmoth, 'chromeleaf': chromeleaf, 'blossomfawn': blossomfawn, 'leafray': leafray,
    'icepaw': icepaw, 'flakeseal': flakeseal, 'frostwaddle': frostwaddle, 'rimewing': rimewing,
    'zapchick': zapchick, 'zapfox': zapfox, 'voltwool': voltwool, 'stormfox': stormfox,
    'pebblebat': pebblebat, 'rubbleape': rubbleape, 'gryphlet': gryphlet, 'pebblephant': pebblephant,
    'goldkid': goldkid, 'glowbell': glowbell, 'gleamowl': gleamowl,
    'duskkit': duskkit, 'inkpuff': inkpuff, 'duskhood': duskhood,
}


def build_stage(name, st):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal, build = SPECIES[name](st)
    b = S(pal, SC[st])
    build(b)
    ob = tw.voxelise(b.objs)
    return ob


CAM_OFF = Vector((5.2, -4.0, 2.8))


def cam_extents(ob, ctr):
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    c = sum(corners, Vector()) / 8
    tmp = Vector((c.x, c.y, ctr)) if ctr is not None else c
    look = (tmp - (tmp + CAM_OFF)).to_track_quat('-Z', 'Y').to_matrix().to_4x4()
    cam_m = look.copy()
    cam_m.translation = tmp + CAM_OFF
    inv = cam_m.inverted()
    pts = [inv @ p for p in corners]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    h = max(p.y for p in pts) - min(p.y for p in pts)
    return c, w, h


def render_stage(name, st, out, samples, size, ortho, tz):
    ob = build_stage(name, st)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = ortho
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    c = sum(corners, Vector()) / 8
    tgt = Vector((c.x, c.y, tz))
    co.location = tgt + CAM_OFF
    co.rotation_euler = (tgt - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    K.render(os.path.join(out, '%s_s%d.png' % (name, st)))


def do_monster(name, out, samples, size):
    ob = build_stage(name, 2)                      # the biggest stage decides the zoom for all three
    ctr, w, h = cam_extents(ob, None)
    ortho = max(w, h) * 1.14
    tz = ctr.z
    for st in (0, 1, 2):
        render_stage(name, st, out, samples, size, ortho, tz)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=40)
    ap.add_argument('--size', type=int, default=560)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for n in [n for n in a.only.split(',') if n] or list(SPECIES):
        try:
            do_monster(n, a.out, a.samples, a.size)
        except Exception:
            print('FAILED', n)
            traceback.print_exc()


if __name__ == '__main__':
    main()
