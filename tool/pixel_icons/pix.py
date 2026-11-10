"""24x24 pixel icons, drawn by shapes with automatic 4-tone hue-shifted shading,
a selective coloured outline and a separate cast shadow (the style notes of the
reference pack: dark coloured outline, 3-4 tone ramps, light from top-left,
specular pixels, own shadow)."""
import colorsys, math, base64, io, json, os
from PIL import Image

N = 24
os.chdir(os.path.dirname(os.path.abspath(__file__)))


def hx(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def ramp(base):
    r, g, b = hx(base)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    def mk(dh, ds, dv):
        hh = (h + dh) % 1.0
        return tuple(int(c * 255) for c in colorsys.hsv_to_rgb(hh, max(0, min(1, s + ds)), max(0, min(1, v + dv))))
    return [mk(-0.07, +0.10, -0.74),   # 0 outline: deep, cool
            mk(-0.045, +0.10, -0.34),  # 1 shade
            mk(0, 0, 0),               # 2 base
            mk(+0.025, -0.10, +0.16),  # 3 light
            mk(+0.04, -0.34, +0.34)]   # 4 highlight


class Cv:
    def __init__(s):
        s.p = [[None] * N for _ in range(N)]   # (ramp, tone)

    def shape(s, mask, rp, mode='orb', bias=0.0, box=None):
        pts = [(x, y) for y in range(N) for x in range(N) if mask(x + .5, y + .5)]
        if not pts: return
        x0 = min(p[0] for p in pts); x1 = max(p[0] for p in pts) + 1
        y0 = min(p[1] for p in pts); y1 = max(p[1] for p in pts) + 1
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rx, ry = max(1, (x1 - x0) / 2), max(1, (y1 - y0) / 2)
        for x, y in pts:
            nx, ny = (x + .5 - cx) / rx, (y + .5 - cy) / ry
            if mode == 'orb':
                sv = 0.5 + (nx * .42 + ny * .58) * .5
            elif mode == 'vert':
                sv = 0.5 + ny * .5
            elif mode == 'diag':
                sv = 0.5 + (nx + ny) * .27
            else:
                sv = 0.5
            sv += bias
            t = 4 if sv < .18 else 3 if sv < .40 else 2 if sv < .72 else 1
            s.p[y][x] = (rp, t)

    def px(s, x, y, rp, t):
        if 0 <= x < N and 0 <= y < N: s.p[y][x] = (rp, t)

    def line(s, a, b, c, d, rp, t):
        n = max(abs(c - a), abs(d - b), 1)
        for i in range(int(n) + 1):
            s.px(round(a + (c - a) * i / n), round(b + (d - b) * i / n), rp, t)

    def render(s, shadow=True, outline=True):
        im = Image.new('RGBA', (N, N), (0, 0, 0, 0)); P = im.load()
        filled = [[s.p[y][x] is not None for x in range(N)] for y in range(N)]
        ys = [y for y in range(N) for x in range(N) if filled[y][x]]
        xs = [x for y in range(N) for x in range(N) if filled[y][x]]
        if shadow and ys:
            gy = max(ys) + 1; gx0, gx1 = min(xs) + 2, max(xs) - 1
            for x in range(gx0, gx1 + 1):
                for yy in (gy, gy + 1):
                    if 0 <= yy < N and not filled[yy][x]:
                        e = (x == gx0 or x == gx1) or yy == gy + 1
                        P[x, yy] = (20, 14, 40, 70 if e else 110)
        if outline:
            for y in range(N):
                for x in range(N):
                    if filled[y][x]: continue
                    best = None
                    for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < N and 0 <= yy < N and filled[yy][xx]:
                            best = s.p[yy][xx][0]; break
                    if best: P[x, y] = best[0] + (255,)
        for y in range(N):
            for x in range(N):
                if filled[y][x]:
                    rp, t = s.p[y][x]; P[x, y] = rp[t] + (255,)
        return im


def ell(cx, cy, rx, ry, clip=None):
    def f(x, y):
        if clip and not clip(x, y): return False
        return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1
    return f


def rect(x0, y0, x1, y1):
    return lambda x, y: x0 <= x < x1 + 1 and y0 <= y < y1 + 1


def poly(pts):
    def f(x, y):
        c = False; j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]; xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi: c = not c
            j = i
        return c
    return f


def rrect(cx, cy, along, perp, deg):
    """A rectangle centred on (cx, cy), `along` long on the axis at `deg`, `perp` wide."""
    ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    def f(x, y):
        dx, dy = x - cx, y - cy
        u = dx * ca + dy * sa; v = -dx * sa + dy * ca
        return abs(u) <= along / 2 and abs(v) <= perp / 2
    return f


def thick(x0, y0, x1, y1, w):
    ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
    return rrect((x0 + x1) / 2, (y0 + y1) / 2, math.hypot(x1 - x0, y1 - y0), w, ang)


def minus(a, b): return lambda x, y: a(x, y) and not b(x, y)


def both(a, b): return lambda x, y: a(x, y) and b(x, y)


R = {k: ramp(v) for k, v in dict(
    bark='#94602f', ring='#ecca8f', stone='#8e9aa8', stone2='#a9a398', moss='#5fae48', fish='#4f9bd6', fishb='#d3e8f5', fin='#2f6db0',
    gold='#eaaa22', goldl='#ffe27a', wall='#ead7a6', roof='#c95238', door='#8a5530', win='#ffd55c', chim='#8e8f98',
    brass='#d8a43a', face='#f4ecd2', red='#d6452f', bolt='#ffd93d', wood='#aa6a30', woodl='#cd904a', iron='#66727f', steel='#93a1b3',
    paw='#e8873a', pawl='#f3ab5c', paper='#f0e2b4', green='#58b04a', blue='#4f86c9', skin='#f2c493', hair='#5a3920', orange='#eaa23c',
    leather='#a8672d', leatherd='#6b4020', sea='#3b82d6', black='#2d2733').items()}

I = {}

# --- log pile -------------------------------------------------------------
c = Cv()
c.shape(rect(2, 4, 16, 10), R['bark'], 'vert'); c.shape(ell(17, 7, 2.7, 3.6), R['ring'], 'orb', -.1)
c.shape(ell(17, 7, 1.4, 2.2), R['wood'], 'flat'); c.px(17, 7, R['bark'], 1)
c.shape(rect(5, 12, 19, 18), R['bark'], 'vert'); c.shape(ell(20, 15, 2.7, 3.4), R['ring'], 'orb', -.1)
c.shape(ell(20, 15, 1.4, 2.1), R['wood'], 'flat'); c.px(20, 15, R['bark'], 1)
for a, b, d in ((4, 6, 9), (6, 8, 13), (8, 15, 14), (10, 16, 18)):
    c.line(a, b, d, b, R['bark'], 1)
c.line(3, 5, 12, 5, R['bark'], 4); c.line(6, 13, 15, 13, R['bark'], 4)
I['log'] = c

# --- stone ----------------------------------------------------------------
c = Cv()
c.shape(poly([(2, 18), (2, 13), (6, 8), (12, 7), (17, 10), (18, 18)]), R['stone'], 'diag')
c.shape(poly([(11, 19), (11, 15), (14, 12), (19, 12), (22, 16), (21, 19)]), R['stone2'], 'diag')
c.shape(poly([(5, 18), (6, 15), (9, 15), (10, 18)]), R['stone2'], 'diag', .05)
c.line(8, 10, 12, 9, R['stone'], 4); c.line(4, 13, 5, 11, R['stone'], 4)
c.px(14, 13, R['stone2'], 4); c.line(15, 13, 18, 13, R['stone2'], 4)
for xy in ((7, 8), (8, 8), (9, 8), (8, 7)): c.px(*xy, R['moss'], 3)
c.px(7, 9, R['moss'], 2); c.px(10, 8, R['moss'], 2)
c.line(9, 12, 10, 15, R['stone'], 1)
I['stone'] = c

# --- fish -----------------------------------------------------------------
c = Cv()
c.shape(poly([(17, 11), (22, 6), (21, 11), (22, 16)]), R['fin'], 'diag')
c.shape(poly([(8, 8), (11, 3), (15, 8)]), R['fin'], 'diag')
c.shape(poly([(9, 15), (11, 18), (14, 15)]), R['fin'], 'diag')
c.shape(ell(11, 11.5, 8.2, 4.8), R['fish'], 'orb')
c.shape(both(ell(11, 11.5, 8.2, 4.8), rect(2, 12.5, 20, 17)), R['fishb'], 'vert', -.1)
c.line(8, 8, 11, 7, R['fish'], 4)
for xy in ((11, 10), (13, 10), (15, 10), (12, 12), (14, 12)): c.px(*xy, R['fish'], 1)
c.line(8, 9, 8, 14, R['fin'], 1)
c.px(5, 10, R['face'], 4); c.px(5, 11, R['black'], 1); c.px(4, 12, R['fishb'], 4)
I['fish'] = c

# --- coin -----------------------------------------------------------------
c = Cv()
c.shape(ell(12, 12, 9, 9), R['gold'], 'orb')
c.shape(ell(12, 12, 6.7, 6.7), R['gold'], 'orb', .18)
star = []
for i in range(10):
    a = -math.pi / 2 + i * math.pi / 5; r = 5.6 if i % 2 == 0 else 2.5
    star.append((12 + r * math.cos(a), 12.4 + r * math.sin(a)))
c.shape(poly(star), R['goldl'], 'flat', -.05)
c.line(12, 8, 12, 10, R['face'], 4)
c.px(6, 6, R['gold'], 4); c.px(7, 5, R['gold'], 4); c.px(5, 7, R['gold'], 4); c.px(6, 5, R['face'], 4)
I['coin'] = c

# --- house ----------------------------------------------------------------
c = Cv()
c.shape(rect(16, 3, 18, 9), R['chim'], 'diag')
c.shape(rect(5, 11, 19, 19), R['wall'], 'diag')
c.shape(poly([(2, 12), (12, 3), (22, 12)]), R['roof'], 'vert')
c.line(5, 11, 19, 11, R['roof'], 1)
for yy, a, b in ((9, 8, 16), (7, 10, 14)): c.line(a, yy, b, yy, R['roof'], 1)
c.line(6, 10, 18, 10, R['roof'], 3)
c.shape(rect(10, 14, 13, 19), R['door'], 'vert'); c.px(12, 17, R['gold'], 4)
c.shape(rect(6, 13, 8, 15), R['win'], 'flat'); c.shape(rect(16, 13, 18, 15), R['win'], 'flat')
c.px(7, 14, R['door'], 1); c.px(17, 14, R['door'], 1)
I['house'] = c

# --- clock ----------------------------------------------------------------
c = Cv()
c.shape(ell(12, 12, 9.3, 9.3), R['brass'], 'orb')
c.shape(ell(12, 12, 7, 7), R['face'], 'orb', .08)
for xy in ((12, 6), (12, 17), (6, 12), (17, 12)): c.px(*xy, R['black'], 2)
c.px(12, 5, R['black'], 2) if False else None
c.line(12, 12, 12, 8, R['black'], 2); c.line(12, 12, 15, 13, R['black'], 2)
c.px(12, 12, R['red'], 2); c.px(7, 7, R['face'], 4); c.px(5, 6, R['brass'], 4)
I['clock'] = c

# --- bolt -----------------------------------------------------------------
c = Cv()
c.shape(poly([(14, 2), (6, 13), (11, 13), (9, 22), (19, 9), (13, 9), (16, 2)]), R['bolt'], 'diag')
c.line(13, 4, 9, 11, R['bolt'], 4); c.px(14, 3, R['face'], 4)
c.line(13, 14, 11, 19, R['bolt'], 1)
I['bolt'] = c

# --- chest (open, gold inside) ----------------------------------------
c = Cv()
c.shape(poly([(4, 2), (19, 2), (21, 9), (2, 9)]), R['woodl'], 'vert')
c.shape(poly([(6, 4), (17, 4), (18, 8), (5, 8)]), R['leatherd'], 'vert', -.25)
c.shape(rect(2, 10, 21, 20), R['wood'], 'vert')
c.shape(rect(2, 10, 21, 11), R['gold'], 'vert')
c.shape(rect(5, 10, 6, 20), R['iron'], 'diag'); c.shape(rect(17, 10, 18, 20), R['iron'], 'diag')
c.shape(ell(11.5, 10.3, 8.6, 2.7, lambda x, y: y < 11.2), R['gold'], 'orb', -.1)
for xy in ((7, 8), (10, 7), (13, 8), (16, 8), (11, 9), (8, 9)): c.px(*xy, R['goldl'], 4 if xy[0] % 2 else 3)
c.shape(rect(9, 13, 14, 18), R['goldl'], 'diag'); c.px(11, 15, R['black'], 2); c.px(12, 15, R['black'], 2); c.px(11, 16, R['black'], 2); c.px(12, 16, R['black'], 2)
for xy in ((3, 13), (3, 18), (20, 13), (20, 18)): c.px(*xy, R['goldl'], 3)
c.line(3, 3, 3, 8, R['woodl'], 4); c.line(3, 14, 3, 16, R['wood'], 4)
I['chest'] = c

# --- bell -----------------------------------------------------------------
c = Cv()
c.shape(rect(11, 2, 13, 5), R['leatherd'], 'diag')
c.shape(poly([(8, 17), (8, 11), (10, 7), (14, 7), (16, 11), (16, 17), (20, 19), (4, 19)]), R['gold'], 'orb', -.05)
c.shape(rect(4, 18, 20, 19), R['brass'], 'vert', .1)
c.shape(ell(12, 21, 1.8, 1.4), R['leatherd'], 'orb')
c.line(9, 10, 9, 15, R['gold'], 4); c.px(10, 8, R['face'], 4)
c.line(15, 12, 15, 16, R['gold'], 1)
I['bell'] = c

# --- build: hammer and wrench crossed ---------------------------------
c = Cv()
c.shape(thick(3.5, 20.5, 17, 7, 2.6), R['wood'], 'diag')
c.shape(rrect(17.7, 6.3, 4.6, 11, -45), R['steel'], 'diag', .02)
c.shape(rrect(19.2, 7.8, 1.6, 8, -45), R['steel'], 'diag', .25)
c.line(16, 8, 19, 5, R['steel'], 4); c.px(15, 9, R['leather'], 2)
for k in (0, 1): c.px(5 + k * 2, 18 - k * 2, R['leatherd'], 1)
c.shape(thick(5, 5, 19, 19, 3.2), R['iron'], 'diag', -.04)
head = minus(ell(5.2, 5.2, 4.3, 4.3), rrect(3.2, 3.2, 5, 3, 45))
c.shape(head, R['steel'], 'diag')
c.shape(minus(ell(19, 19, 3.6, 3.6), ell(20, 20, 1.4, 1.4)), R['steel'], 'diag')
c.line(8, 8, 17, 17, R['steel'], 3)
c.px(4, 6, R['face'], 4); c.px(6, 4, R['face'], 4)
I['hammer'] = c

# --- paw ------------------------------------------------------------------
c = Cv()
c.shape(ell(12, 16, 5.8, 4.4), R['paw'], 'orb')
for cx, cy in ((4.5, 11), (9, 6.5), (15, 6.5), (19.5, 11)):
    c.shape(ell(cx, cy, 2.3, 3.1), R['pawl'], 'orb')
c.px(10, 14, R['pawl'], 4); c.px(11, 14, R['pawl'], 4)
I['paw'] = c

# --- map ------------------------------------------------------------------
c = Cv()
c.shape(poly([(2, 5), (9, 4), (15, 6), (22, 4), (22, 19), (15, 21), (9, 19), (2, 20)]), R['paper'], 'diag')
c.line(9, 5, 9, 19, R['paper'], 1); c.line(15, 7, 15, 20, R['paper'], 1)
c.shape(rect(3, 6, 7, 10), R['green'], 'diag'); c.shape(rect(10, 13, 13, 17), R['green'], 'diag')
c.shape(poly([(17, 15), (20, 11), (21, 15)]), R['stone2'], 'diag')
for xy in ((4, 15), (6, 14), (8, 13), (11, 11), (13, 10)): c.px(*xy, R['black'], 2)
for xy in ((16, 7), (18, 7), (17, 8), (16, 9), (18, 9)): c.px(*xy, R['red'], 2)
I['map'] = c

# --- social (two speech bubbles, no people) ---------------------------
c = Cv()
c.shape(poly([(10, 2), (20, 2), (21, 3), (21, 9), (20, 10), (17, 10), (16, 13), (13, 10), (10, 10), (9, 9), (9, 3)]), R['blue'], 'diag')
for x in (12, 15, 18): c.px(x, 6, R['face'], 4)
c.shape(poly([(4, 9), (14, 9), (15, 10), (15, 16), (14, 17), (10, 17), (7, 20), (7, 17), (4, 17), (3, 16), (3, 10)]), R['orange'], 'diag')
for xy in ((5, 11), (6, 11), (8, 11), (9, 11), (5, 12), (6, 12), (7, 12), (8, 12), (9, 12), (6, 13), (7, 13), (8, 13), (7, 14)):
    c.px(*xy, R['red'], 2)
c.px(5, 11, R['red'], 4); c.px(6, 11, R['red'], 3)
I['people'] = c

# --- profile (an ID card) ----------------------------------------------
c = Cv()
c.shape(rect(10, 1, 13, 4), R['steel'], 'diag'); c.px(11, 2, R['black'], 2); c.px(12, 2, R['black'], 2)
c.shape(rect(2, 4, 21, 20), R['paper'], 'diag')
c.shape(rect(2, 4, 21, 8), R['blue'], 'vert')
c.line(4, 6, 9, 6, R['face'], 4)
c.shape(ell(7.5, 14, 3.6, 3.6), R['gold'], 'orb')
star = []
for i in range(10):
    a = -math.pi / 2 + i * math.pi / 5; r = 2.5 if i % 2 == 0 else 1.1
    star.append((7.5 + r * math.cos(a), 14.2 + r * math.sin(a)))
c.shape(poly(star), R['goldl'], 'flat', -.05)
c.line(13, 11, 19, 11, R['black'], 2); c.line(13, 14, 19, 14, R['iron'], 3); c.line(13, 17, 17, 17, R['iron'], 3)
c.px(19, 6, R['goldl'], 4); c.px(18, 6, R['gold'], 3)
I['person'] = c

# --- bag (a proper tall backpack) ---------------------------------------
c = Cv()
c.shape(rect(9, 1, 14, 2), R['leatherd'], 'flat'); c.shape(rect(9, 1, 10, 5), R['leatherd'], 'flat'); c.shape(rect(13, 1, 14, 5), R['leatherd'], 'flat')
c.shape(rect(2, 13, 4, 20), R['leatherd'], 'diag'); c.shape(rect(19, 13, 21, 20), R['leatherd'], 'diag')
c.shape(poly([(5, 7), (7, 4), (16, 4), (18, 7), (19, 21), (4, 21)]), R['leather'], 'diag')
c.shape(poly([(5, 7), (7, 4), (16, 4), (18, 7), (18, 12), (11.5, 14), (5, 12)]), R['woodl'], 'vert')
c.shape(rect(7, 15, 16, 20), R['leatherd'], 'vert', -.08)
c.line(7, 15, 16, 15, R['leather'], 3)
c.shape(rect(10, 11, 13, 14), R['gold'], 'diag'); c.px(11, 13, R['black'], 2)
c.line(6, 7, 10, 5, R['woodl'], 4); c.line(5, 14, 5, 19, R['leather'], 3)
I['bag'] = c

# --- tasks (clipboard) ----------------------------------------------------
c = Cv()
c.shape(rect(5, 3, 19, 21), R['wood'], 'diag')
c.shape(rect(7, 6, 17, 19), R['paper'], 'diag')
c.shape(rect(9, 2, 15, 5), R['steel'], 'diag'); c.px(12, 3, R['black'], 2)
for yy in (9, 13, 17):
    c.line(8, yy, 9, yy + 1, R['green'], 2); c.line(9, yy + 1, 11, yy - 1, R['green'], 3)
    c.line(13, yy, 16, yy, R['black'], 2)
I['tasks'] = c

# --- globe (just the Earth) -------------------------------------------------
c = Cv()
E = ell(12, 12, 10, 10)
c.shape(E, R['sea'], 'orb')
c.shape(both(poly([(4, 6), (8, 3), (11, 5), (9, 8), (12, 11), (10, 14), (9, 19), (6, 17), (7, 12), (4, 10)]), E), R['green'], 'diag')
c.shape(both(poly([(13, 4), (18, 4), (21, 8), (18, 10), (19, 14), (16, 19), (14, 15), (14, 11), (12, 8)]), E), R['green'], 'diag')
c.line(9, 3, 16, 3, R['face'], 4); c.line(10, 20, 14, 20, R['face'], 4)
c.px(16, 6, R['face'], 3); c.px(17, 6, R['face'], 3); c.px(7, 15, R['face'], 3)
c.px(6, 5, R['face'], 4); c.px(5, 6, R['face'], 4)
I['globe'] = c

SPR = {k: v.render() for k, v in I.items()}
if __name__ == '__main__':
    keys = list(SPR)
    S = Image.new('RGBA', (9 * 112, 2 * 112), (30, 78, 98, 255))
    for k, n in enumerate(keys):
        im = SPR[n].resize((96, 96), Image.NEAREST); S.paste(im, ((k % 9) * 112 + 8, (k // 9) * 112 + 8), im)
    S.save('pix_sheet.png')
    D = {}
    for n, im in SPR.items():
        b = io.BytesIO(); im.save(b, 'PNG'); D[n] = 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()
    json.dump(D, open('pix.json', 'w'))
    print('ok', len(D))
