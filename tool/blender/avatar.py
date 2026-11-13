"""Player avatar: a chibi voxel figure in the monsters' voxel style, rendered as LAYERS.

    blender --background --python tool/blender/avatar.py -- --out docs/renders/avatar [--only hair_front/short,top/tunic] [--views full,bust]

Every part (hair style, top, hat ...) is rendered on its own on a transparent canvas, all with the SAME
camera, so the app can stack any combination and tint it. Tintable layers are built in neutral light grey
(t1 / t2 / t3 = three grey tones, so a part keeps its own shading), the app multiplies them by the chosen
colour. Layers with fixed colours (eye whites, mouth, glass, metal) use real colours.

Axes: x = forward (the face looks along +x), y = sideways, z = up. Height ~1.0, like the monsters.

Layer order (back to front) and the colour slot each is tinted with -- see lib/features/avatar/avatar_catalog.dart,
which is written from the SAME table (`--catalog`), so script and app cannot drift apart.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute_monsters as cm  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

PAL = dict(
    t1='#e2e2e2', t2='#bcbcbc', t3='#f6f6f6', t4='#8e8e8e',        # neutral tones, tinted in the app
    eyew='#fbf6ee', mouth='#8a2f3a', tongue='#d4606c', teeth='#fffaf0', brow_f='#3a2a22',
    metal='#aab4c0', metal2='#7d8996', gold='#f2c340', gold2='#c99a22', glass='#cfe9f4', leather='#6a4a30',
    wood='#8a6038',
)

# ── layer table: layer -> (z order, colour slot) ─────────────────────────────────────────────
LAYERS = {
    'acc_back':   (10, 'acc'),
    'hair_back':  (20, 'hair'),
    'body':       (30, 'skin'),
    'bottom':     (40, 'bottom'),
    'shoes':      (50, 'shoes'),
    'top':        (60, 'top'),
    'top_trim':   (61, 'top2'),
    'head':       (70, 'skin'),
    'eyes_white': (80, None),
    'eyes':       (81, 'eyes'),
    'brows':      (82, 'hair'),
    'beard':      (82.5, 'hair'),
    'mouth':      (83, None),
    'hair_front': (100, 'hair'),
    'hat':        (110, 'hat'),
    'hat_trim':   (111, 'top2'),
    'acc_front':  (120, 'acc'),
}

HEAD = (0.0, 0.0, 0.76)
HR = (0.20, 0.19, 0.20)
SKIN = 't1'

PARTS = []          # (layer, id, fn)


def part(layer, pid):
    def deco(fn):
        PARTS.append((layer, pid, fn))
        return fn
    return deco


def sym(b, fn):
    for sg in (-1, 1):
        fn(sg)


# ── body & head (always drawn) ──────────────────────────────────────────────────────────────
@part('body', 'base')
def body(b):
    E, L = b.E, b.L
    E(0, 0, .43, .100, .132, .150, SKIN)                       # torso (clothes sit over it)
    L((0, 0, .58), (0, 0, .66), .055, .05, SKIN)               # neck
    for sg in (-1, 1):
        L((0, sg * .165, .52), (.01, sg * .205, .40), .033, .030, SKIN)
        L((.01, sg * .205, .40), (.045, sg * .205, .31), .030, .028, SKIN)
        E(.055, sg * .205, .275, .040, .038, .044, SKIN)       # hand
        L((0, sg * .07, .30), (0, sg * .07, .09), .042, .036, SKIN)   # leg
        E(.0, sg * .07, .075, .042, .042, .040, SKIN)


@part('head', 'base')
def head(b):
    E = b.E
    E(*HEAD, *HR, SKIN)
    E(HEAD[0] - .01, 0, HEAD[2] - .03, HR[0] * .97, HR[1] * .97, HR[2] * .9, SKIN)    # a rounder jaw
    for sg in (-1, 1):
        E(0, sg * .19, .76, .028, .022, .05, SKIN)             # ears
    E(.20, 0, .735, .030, .026, .030, 't3')                    # nose


# ── hair ────────────────────────────────────────────────────────────────────────────────────
def cap(b, lift=0.0, back=0.0, thick=1.0, fringe=True):
    E = b.E
    E(-.045 - back, 0, .805 + lift, .215 * thick, .208 * thick, .182 * thick, 't1')
    if fringe:
        E(.09, 0, .905 + lift, .125, .16, .05, 't3')                     # brow-high fringe
        for sg in (-1, 1):
            E(.11, sg * .15, .85 + lift, .075, .045, .09, 't1')            # sideburn-high tufts


@part('hair_front', 'short')
def hair_short(b):
    cap(b)


@part('hair_front', 'spiky')
def hair_spiky(b):
    cap(b, fringe=False)
    for i, (x, y, a) in enumerate(((.06, 0, 0), (.0, -.10, -.35), (.0, .10, .35), (-.08, -.06, -.2), (-.08, .06, .2), (.12, 0, .15))):
        b.L((x, y, .94), (x - .02, y + a * .16, 1.10 - .02 * (i % 2)), .06, .012, 't1' if i % 2 == 0 else 't3', seg=6)


@part('hair_front', 'long')
def hair_long(b):
    cap(b)
    for sg in (-1, 1):
        b.L((.0, sg * .19, .82), (-.02, sg * .205, .52), .06, .045, 't1', seg=8)


@part('hair_back', 'long')
def hair_long_back(b):
    b.E(-.10, 0, .66, .125, .20, .28, 't1')
    b.E(-.13, 0, .50, .10, .17, .14, 't2')


@part('hair_front', 'bun')
def hair_bun(b):
    cap(b)
    b.E(-.07, 0, 1.0, .09, .09, .09, 't3')


@part('hair_front', 'ponytail')
def hair_pony(b):
    cap(b)


@part('hair_back', 'ponytail')
def hair_pony_back(b):
    b.chain([(-.17, 0, .88, .06), (-.27, 0, .80, .055), (-.30, 0, .66, .05), (-.27, 0, .52, .035)], 't1')


@part('hair_front', 'mohawk')
def hair_mohawk(b):
    b.E(-.02, 0, .90, .20, .045, .13, 't1')
    for i in range(5):
        b.E(.10 - i * .055, 0, .99 + .02 * (i % 2), .05, .035, .09, 't3')


@part('hair_front', 'curly')
def hair_curly(b):
    import random
    rng = random.Random(7)
    cap(b, thick=1.05, fringe=False)
    for i in range(18):
        a = rng.uniform(0, math.pi * 2)
        r = rng.uniform(.07, .19)
        b.E(-.04 + math.cos(a) * r * .9, math.sin(a) * r, .90 + rng.uniform(.02, .12), .075, .075, .075, 't1' if i % 2 else 't3')


@part('hair_front', 'braids')
def hair_braids(b):
    cap(b)
    for sg in (-1, 1):
        for i in range(5):
            b.E(.08, sg * (.17 + .01 * (i % 2)), .70 - i * .075, .05, .05, .05, 't1' if i % 2 else 't2')


# ── eyes (white + highlight fixed, pupil tinted, brows tinted with the hair) ───────────────────
EX, EZ, EY = .200, .765, .075


def eye_pair(b, wx=.032, wy=.038, wz=.048, px=.022, py=.026, pz=.038, dz=0.0):
    for sg in (-1, 1):
        b.E(EX, sg * EY, EZ + dz, wx, wy, wz, 'eyew')


def pupils(b, pr=(.026, .022, .034), dz=0.0, hl=True):
    for sg in (-1, 1):
        b.E(EX + .013, sg * EY, EZ + dz - .004, *pr, 't1')


def brows(b, ang=0.0, z=.835, thick=.016, length=.058):
    for sg in (-1, 1):
        b.E(EX - .01, sg * (EY + .002), z, .016, length * .5, thick, 't1', (sg * ang, 0, 0))


@part('eyes_white', 'round')
def ew_round(b):
    eye_pair(b)


@part('eyes', 'round')
def ey_round(b):
    pupils(b)


@part('brows', 'round')
def br_round(b):
    brows(b, .10)


@part('eyes_white', 'big')
def ew_big(b):
    eye_pair(b, .034, .046, .062)


@part('eyes', 'big')
def ey_big(b):
    pupils(b, (.030, .032, .046))


@part('brows', 'big')
def br_big(b):
    brows(b, .0, .85)


@part('eyes_white', 'narrow')
def ew_narrow(b):
    eye_pair(b, .030, .042, .032)


@part('eyes', 'narrow')
def ey_narrow(b):
    pupils(b, (.024, .026, .022))


@part('brows', 'narrow')
def br_narrow(b):
    brows(b, -.30, .815, .020, .064)


@part('eyes', 'sleepy')
def ey_sleepy(b):
    pupils(b, (.024, .024, .024), dz=-.012)


@part('eyes_white', 'sleepy')
def ew_sleepy(b):
    eye_pair(b, .030, .040, .034, dz=-.012)


@part('brows', 'sleepy')
def br_sleepy(b):
    brows(b, .0, .83)


@part('eyes_white', 'happy')
def ew_happy(b):
    pass


@part('eyes', 'happy')
def ey_happy(b):
    for sg in (-1, 1):                                              # closed, smiling arcs
        for i, dz in enumerate((-.012, .006, .014, .006, -.012)):
            b.E(EX + .012, sg * (EY - .036 + i * .018), EZ + dz, .014, .014, .014, 't1')


@part('brows', 'happy')
def br_happy(b):
    brows(b, .15, .84)


# ── mouths (fixed colours) ───────────────────────────────────────────────────────────────────
MX, MZ = .198, .668


@part('mouth', 'smile')
def m_smile(b):
    for i, dz in enumerate((.014, .004, -.003, .004, .014)):
        b.E(MX - .004 * abs(i - 2), (i - 2) * .021, MZ + dz, .014, .014, .013, 'mouth')


@part('mouth', 'grin')
def m_grin(b):
    b.E(MX - .01, 0, MZ, .018, .068, .030, 'mouth')
    b.E(MX + .004, 0, MZ + .013, .010, .056, .012, 'teeth')


@part('mouth', 'neutral')
def m_neutral(b):
    b.E(MX, 0, MZ + .004, .013, .045, .011, 'mouth')


@part('mouth', 'open')
def m_open(b):
    b.E(MX - .006, 0, MZ, .018, .034, .034, 'mouth')
    b.E(MX - .002, 0, MZ - .014, .012, .022, .012, 'tongue')


@part('mouth', 'smirk')
def m_smirk(b):
    for i, dz in enumerate((-.004, 0, .004, .010, .016)):
        b.E(MX, (i - 2) * .021 + .010, MZ + dz, .013, .014, .012, 'mouth')


# ── facial hair (tinted with the hair) ───────────────────────────────────────────────────────
@part('beard', 'moustache')
def b_must(b):
    for sg in (-1, 1):
        b.E(.198, sg * .035, .700, .026, .048, .020, 't1', (sg * -.35, 0, 0))


@part('beard', 'goatee')
def b_goatee(b):
    b.E(.193, 0, .625, .028, .042, .05, 't1')
    for sg in (-1, 1):
        b.E(.198, sg * .035, .700, .022, .042, .016, 't1', (sg * -.35, 0, 0))


@part('beard', 'beard')
def b_beard(b):
    b.E(.150, 0, .655, .090, .175, .085, 't1')
    b.E(.185, 0, .600, .060, .120, .070, 't3')
    for sg in (-1, 1):
        b.E(.198, sg * .04, .700, .022, .045, .018, 't3', (sg * -.35, 0, 0))


@part('beard', 'longbeard')
def b_long(b):
    b.E(.150, 0, .650, .090, .180, .095, 't1')
    b.chain([(.165, 0, .60, .09), (.172, 0, .50, .085), (.165, 0, .40, .07), (.15, 0, .31, .045)], 't1')
    for sg in (-1, 1):
        b.E(.198, sg * .04, .700, .022, .045, .018, 't3', (sg * -.35, 0, 0))


@part('beard', 'mutton')
def b_mutton(b):
    for sg in (-1, 1):
        b.E(.130, sg * .170, .70, .060, .035, .095, 't1')
        b.E(.198, sg * .035, .700, .026, .048, .020, 't1', (sg * -.35, 0, 0))


# ── tops (tinted main + trim) ────────────────────────────────────────────────────────────────
def torso(b, flare=0.0, hem=.27, m='t1'):
    b.E(0, 0, .43, .135, .170, .182, m)
    b.E(0, 0, hem + .07, .142 + flare * .02, .178 + flare, .090, m)


def sleeves(b, length=1.0, rad=.054, m='t1'):
    for sg in (-1, 1):
        b.L((0, sg * .165, .52), (.01, sg * .205, .40), rad, rad * .9, m, seg=10)
        if length > .7:
            b.L((.01, sg * .205, .40), (.04 + .01 * length, sg * .205, .31), rad * .9, rad * .82, m, seg=10)


def collar(b, m='t2', z=.60):
    b.E(0, 0, z, .085, .105, .035, m)


@part('top', 'tunic')
def top_tunic(b):
    torso(b)
    sleeves(b, .5)


@part('top_trim', 'tunic')
def tt_tunic(b):
    b.E(0, 0, .335, .152, .190, .030, 't1')                     # belt
    b.E(.150, 0, .335, .022, .040, .034, 't3')                    # buckle
    collar(b)


@part('top', 'vest')
def top_vest(b):
    torso(b, hem=.30)


@part('top_trim', 'vest')
def tt_vest(b):
    for sg in (-1, 1):
        b.L((.12, sg * .02, .60), (.14, sg * .02, .30), .016, .016, 't3', seg=6)    # front opening trim
    for z in (.50, .43, .36):
        b.E(.14, 0, z, .012, .012, .012, 't3')


@part('top', 'robe')
def top_robe(b):
    torso(b, flare=.05, hem=.14)
    b.E(0, 0, .21, .150, .190, .115, 't1')
    sleeves(b, 1.0, .056)
    for sg in (-1, 1):
        b.E(.05, sg * .205, .30, .06, .06, .07, 't1')           # wide cuffs


@part('top_trim', 'robe')
def tt_robe(b):
    b.E(0, 0, .335, .156, .194, .028, 't1')
    b.E(0, 0, .105, .160, .202, .026, 't1')                     # hem
    collar(b, 't1')


@part('top', 'armor')
def top_armor(b):
    torso(b, hem=.30)
    for sg in (-1, 1):
        b.E(0, sg * .185, .565, .075, .075, .06, 't1')            # pauldrons
        b.L((0, sg * .165, .50), (.01, sg * .205, .40), .042, .038, 't2', seg=8)


@part('top_trim', 'armor')
def tt_armor(b):
    b.E(.120, 0, .46, .050, .115, .110, 't1')                    # breast plate
    b.E(0, 0, .335, .152, .190, .030, 't1')
    for sg in (-1, 1):
        b.E(0, sg * .185, .54, .090, .090, .026, 't3')


@part('top', 'hoodie')
def top_hoodie(b):
    torso(b, hem=.28)
    sleeves(b, 1.0, .054)
    b.E(-.09, 0, .64, .12, .165, .10, 't1')                      # hood on the back


@part('top_trim', 'hoodie')
def tt_hoodie(b):
    b.E(.12, 0, .30, .030, .12, .045, 't1')                      # pocket
    for sg in (-1, 1):
        b.L((.13, sg * .035, .60), (.14, sg * .035, .46), .014, .014, 't1', seg=6)   # drawstrings


@part('top', 'apron')
def top_apron(b):
    torso(b, hem=.30)
    sleeves(b, .5, .046)


@part('top_trim', 'apron')
def tt_apron(b):
    b.E(.128, 0, .37, .020, .115, .17, 't1')
    for sg in (-1, 1):
        b.L((.12, sg * .08, .53), (.02, sg * .10, .60), .014, .014, 't1', seg=6)


@part('top', 'jacket')
def top_jacket(b):
    torso(b, flare=.01, hem=.26)
    sleeves(b, 1.0, .054)


@part('top_trim', 'jacket')
def tt_jacket(b):
    collar(b, 't1', .595)
    b.E(.140, 0, .43, .010, .012, .16, 't3')                     # zip / seam
    for sg in (-1, 1):
        b.E(.05, sg * .205, .295, .05, .05, .028, 't1')          # cuffs


@part('top', 'tank')
def top_tank(b):
    torso(b, hem=.31)


@part('top_trim', 'tank')
def tt_tank(b):
    b.E(0, 0, .56, .12, .162, .030, 't1')


# ── bottoms ──────────────────────────────────────────────────────────────────────────────────
@part('bottom', 'trousers')
def bt_trousers(b):
    b.E(0, 0, .30, .130, .170, .068, 't1')
    for sg in (-1, 1):
        b.L((0, sg * .07, .30), (0, sg * .07, .095), .064, .056, 't1', seg=10)


@part('bottom', 'shorts')
def bt_shorts(b):
    b.E(0, 0, .30, .130, .170, .068, 't1')
    for sg in (-1, 1):
        b.L((0, sg * .07, .30), (0, sg * .07, .20), .064, .060, 't1', seg=10)


@part('bottom', 'skirt')
def bt_skirt(b):
    b.E(0, 0, .30, .130, .170, .068, 't1')
    b.E(0, 0, .22, .165, .205, .090, 't1')
    b.E(0, 0, .17, .170, .212, .030, 't2')


@part('bottom', 'greaves')
def bt_greaves(b):
    b.E(0, 0, .30, .130, .170, .068, 't1')
    for sg in (-1, 1):
        b.L((0, sg * .07, .30), (0, sg * .07, .095), .064, .056, 't1', seg=10)
        b.E(.045, sg * .07, .20, .035, .045, .040, 't2')          # knee plates


# ── shoes ────────────────────────────────────────────────────────────────────────────────────
@part('shoes', 'shoes')
def sh_shoes(b):
    for sg in (-1, 1):
        b.E(.04, sg * .07, .040, .095, .060, .045, 't1')
        b.E(.075, sg * .07, .050, .045, .050, .030, 't3')


@part('shoes', 'boots')
def sh_boots(b):
    for sg in (-1, 1):
        b.E(.04, sg * .07, .040, .100, .064, .048, 't1')
        b.L((0, sg * .07, .15), (0, sg * .07, .05), .066, .060, 't1', seg=10)
        b.E(0, sg * .07, .165, .070, .070, .020, 't2')           # cuff


@part('shoes', 'sandals')
def sh_sandals(b):
    for sg in (-1, 1):
        b.E(.04, sg * .07, .020, .100, .060, .018, 't1')
        b.E(.02, sg * .07, .060, .028, .062, .030, 't2')          # strap


# ── hats (main + trim) ───────────────────────────────────────────────────────────────────────
@part('hat', 'cap')
def hat_cap(b):
    b.E(-.03, 0, .870, .216, .207, .118, 't1')
    b.E(.19, 0, .835, .095, .150, .030, 't2', (0, .35, 0))      # peak, tipped down


@part('hat_trim', 'cap')
def ht_cap(b):
    b.E(-.03, 0, .775, .218, .208, .018, 't1')
    b.E(-.03, 0, 1.0, .030, .030, .030, 't3')


@part('hat', 'wide')
def hat_wide(b):
    b.E(-.02, 0, .905, .150, .150, .115, 't1')
    b.E(-.02, 0, .835, .320, .320, .026, 't1')


@part('hat_trim', 'wide')
def ht_wide(b):
    b.E(-.02, 0, .865, .160, .160, .026, 't1')


@part('hat', 'helmet')
def hat_helmet(b):
    b.E(-.02, 0, .835, .225, .215, .185, 't1')
    b.E(.12, 0, .74, .095, .19, .090, 't2')
    b.E(.20, 0, .77, .020, .018, .120, 't2')                     # nose guard


@part('hat_trim', 'helmet')
def ht_helmet(b):
    b.E(-.02, 0, 1.0, .030, .030, .060, 't1')
    b.E(-.02, 0, .93, .060, .025, .120, 't1')


@part('hat', 'crown')
def hat_crown(b):
    b.E(-.02, 0, .915, .180, .175, .060, 't1')
    for i in range(6):
        a = i * math.pi / 3
        b.L((-.02 + math.cos(a) * .16, math.sin(a) * .16, .94), (-.02 + math.cos(a) * .17, math.sin(a) * .17, 1.06), .036, .012, 't3', seg=6)


@part('hat_trim', 'crown')
def ht_crown(b):
    for i in range(3):
        a = i * math.pi * 2 / 3 + .5
        b.E(-.02 + math.cos(a) * .17, math.sin(a) * .17, .93, .022, .022, .022, 't1')


@part('hat', 'wizard')
def hat_wizard(b):
    b.E(-.02, 0, .875, .290, .290, .024, 't1')
    b.L((-.02, 0, .88), (-.06, 0, 1.18), .17, .020, 't1', seg=14)
    b.E(-.10, 0, 1.19, .045, .045, .045, 't1')


@part('hat_trim', 'wizard')
def ht_wizard(b):
    b.E(-.02, 0, .905, .185, .185, .030, 't1')
    b.E(.07, 0, 1.0, .022, .022, .022, 't3')


@part('hat', 'headband')
def hat_headband(b):
    b.E(-.03, 0, .845, .213, .205, .036, 't1')


@part('hat_trim', 'headband')
def ht_headband(b):
    b.E(-.20, 0, .84, .050, .050, .060, 't1')
    b.E(-.24, 0, .80, .045, .040, .08, 't1', (0, -.3, 0))


@part('hat', 'hood')
def hat_hood(b):
    b.E(-.06, 0, .79, .235, .225, .215, 't1')
    b.E(-.20, 0, .66, .120, .190, .150, 't1')


@part('hat_trim', 'hood')
def ht_hood(b):
    for sg in (-1, 1):
        b.E(.09, sg * .165, .84, .050, .040, .130, 't1')


# ── accessories ──────────────────────────────────────────────────────────────────────────────
@part('acc_front', 'glasses')
def ac_glasses(b):
    for sg in (-1, 1):
        b.E(.198, sg * EY, EZ, .016, .062, .066, 't1')
    b.E(.205, 0, EZ + .01, .012, .030, .014, 't1')
    for sg in (-1, 1):
        b.L((.19, sg * .135, EZ + .01), (-.0, sg * .19, EZ + .01), .012, .012, 't1', seg=6)


@part('acc_front', 'scarf')
def ac_scarf(b):
    b.E(0, 0, .595, .105, .130, .050, 't1')
    b.E(.110, -.04, .50, .028, .050, .105, 't1')
    b.E(.118, -.04, .44, .026, .046, .040, 't2')


@part('acc_front', 'eyepatch')
def ac_eyepatch(b):
    b.E(.190, EY, EZ, .020, .060, .065, 't1')
    b.L((.17, EY, EZ + .06), (-.02, 0, .90), .010, .010, 't1', seg=6)
    b.L((.17, EY, EZ - .05), (-.02, -.03, .70), .010, .010, 't1', seg=6)


@part('acc_back', 'cape')
def ac_cape(b):
    b.E(-.115, 0, .43, .045, .185, .25, 't1')
    b.E(-.125, 0, .22, .045, .200, .13, 't2')
    for sg in (-1, 1):
        b.E(-.02, sg * .17, .585, .060, .060, .045, 't3')


@part('acc_back', 'backpack')
def ac_backpack(b):
    b.E(-.165, 0, .43, .075, .115, .130, 't1')
    b.E(-.185, 0, .35, .060, .100, .060, 't2')
    for sg in (-1, 1):
        b.L((-.06, sg * .10, .56), (-.15, sg * .10, .50), .014, .014, 't3', seg=6)


# ── pipeline ─────────────────────────────────────────────────────────────────────────────────
VIEWS = {   # name: (centre z, ortho scale, px)
    'full': (.50, 1.42, 288),
    'bust': (.76, .66, 224),
}


PARTNER = {'top_trim': 'top', 'hat_trim': 'hat', 'eyes': 'eyes_white'}     # a layer is hidden by the main layer it sits on


def holdout_material():
    m = bpy.data.materials.new('hold')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    h = nt.nodes.new('ShaderNodeHoldout')
    o = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(h.outputs[0], o.inputs['Surface'])
    return m


def occluder(layer, pid):
    """The body and head (and the part this layer sits on) as a HOLDOUT: whatever of the layer lies behind or
    inside them is cut away, so the flat layers stack the way the solid figure would look."""
    if layer in ('body', 'head'):
        return
    b = cm.B(PAL)
    body(b)
    head(b)
    pl = PARTNER.get(layer)
    if pl:
        for l, p, f in PARTS:
            if l == pl and p == pid:
                f(b)
    ob = tw.voxelise(b.objs)
    hm = holdout_material()
    ob.data.materials.clear()
    ob.data.materials.append(hm)
    for pg in ob.data.polygons:
        pg.material_index = 0


def render_layer(layer, pid, fn, outdir, views, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    tw.PAINT = []
    occluder(layer, pid)
    b = cm.B(PAL)
    try:
        fn(b)
    except Exception:
        import traceback
        print('FAILED build', layer, pid)
        traceback.print_exc()
        return False
    if not b.objs:
        return False
    ob = tw.voxelise(b.objs)
    K.lighting(sky=1.0, sun=3.2)
    K.rim_light(Vector((-0.6, 0.5, 0.7)), 1.2)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = 0.0
    for v in views:
        zc, ortho, px = VIEWS[v]
        sc.render.resolution_x = sc.render.resolution_y = px
        cam = bpy.data.cameras.new('cam_' + v)
        cam.type = 'ORTHO'
        cam.ortho_scale = ortho
        co = bpy.data.objects.new('cam_' + v, cam)
        sc.collection.objects.link(co)
        c = Vector((0, 0, zc))
        co.location = c + Vector((6.0, 0.01, 1.2))
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        sc.camera = co
        d = os.path.join(outdir, v, layer)
        os.makedirs(d, exist_ok=True)
        K.render(os.path.join(d, pid + '.png'))
    return True


def catalog():
    """The ids per layer, for the Dart side (written next to the renders as catalog.json)."""
    out = {}
    for layer, pid, _ in PARTS:
        out.setdefault(layer, []).append(pid)
    return {'layers': {k: {'order': LAYERS[k][0], 'slot': LAYERS[k][1], 'ids': v} for k, v in out.items()}}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--only', default='')
    ap.add_argument('--views', default='full,bust')
    ap.add_argument('--samples', type=int, default=24)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    only = set(x for x in a.only.split(',') if x)
    views = a.views.split(',')
    made = {}
    for layer, pid, fn in PARTS:
        key = layer + '/' + pid
        if only and key not in only and layer not in only:
            continue
        ok = render_layer(layer, pid, fn, a.out, views, a.samples)
        made[key] = ok
    with open(os.path.join(a.out, 'catalog.json'), 'w') as f:
        json.dump(catalog(), f, indent=1)
    print('DONE', sum(1 for v in made.values() if v), 'layers')


if __name__ == '__main__':
    main()
