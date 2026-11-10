"""UI glyphs (plus, minus, arrows, search ...) in the same 24x24 pixel style.
Light-ice body with the dark outline, so they read on cyan buttons and dark cards."""
import os, math
os.chdir(os.path.dirname(os.path.abspath(__file__)))
from pix import *  # noqa
import pix
import pix2  # noqa  (adds ramps)
from pix2 import star_poly  # noqa

R.update({'ice': ramp('#e6f1f6'), 'ok': ramp('#58b04a'), 'bad': ramp('#e0553f'), 'info': ramp('#4f9bd6')})
ICE = R['ice']
G = {}


def new(name):
    c = Cv(); G[name] = c; return c


def bar(c, x0, y0, x1, y1, w=4, rp=ICE, mode='diag'):
    c.shape(thick(x0, y0, x1, y1, w), rp, mode)


def tri(c, pts, rp=ICE):
    c.shape(poly(pts), rp, 'diag')


def ring(cx, cy, ro, ri): return minus(ell(cx, cy, ro, ro), ell(cx, cy, ri, ri))


# plus / minus / x
c = new('plus'); c.shape(rect(9, 3, 14, 20), ICE, 'diag'); c.shape(rect(3, 9, 20, 14), ICE, 'diag'); c.shape(rect(9, 9, 14, 14), ICE, 'diag')
c = new('minus'); c.shape(rect(3, 9, 20, 14), ICE, 'vert')
c = new('x'); bar(c, 4, 4, 19, 19, 4.4); bar(c, 19, 4, 4, 19, 4.4)

# chevrons
c = new('left'); bar(c, 15, 4, 7, 12, 4); bar(c, 7, 12, 15, 20, 4)
c = new('right'); bar(c, 8, 4, 16, 12, 4); bar(c, 16, 12, 8, 20, 4)
c = new('up'); bar(c, 4, 15, 12, 7, 4); bar(c, 12, 7, 20, 15, 4)
c = new('down'); bar(c, 4, 8, 12, 16, 4); bar(c, 12, 16, 20, 8, 4)

# arrows
c = new('arrowLeft'); c.shape(rect(8, 10, 20, 14), ICE, 'vert'); tri(c, [(3, 12), (11, 4), (11, 20)])
c = new('arrowRight'); c.shape(rect(3, 10, 15, 14), ICE, 'vert'); tri(c, [(20, 12), (12, 4), (12, 20)])
c = new('arrowDown'); c.shape(rect(10, 3, 14, 15), ICE, 'diag'); tri(c, [(12, 20), (4, 11), (20, 11)])

# carets
c = new('caretDown'); tri(c, [(5, 8), (19, 8), (12, 17)])
c = new('caretUp'); tri(c, [(5, 16), (19, 16), (12, 7)])

# check circle
c = new('checkCircle'); c.shape(ell(12, 12, 9.5, 9.5), R['ok'], 'orb'); bar(c, 7, 12, 10.5, 15.5, 3.2); bar(c, 10.5, 15.5, 17, 8.5, 3.2)
for s_ in (c,): pass

# search
c = new('search'); c.shape(ring(10, 10, 7.5, 4.2), ICE, 'orb'); c.shape(ell(10, 10, 4.2, 4.2), R['info'], 'orb', .1); bar(c, 15.5, 15.5, 20.5, 20.5, 3.6)

# sort (two arrows)
c = new('sort'); c.shape(rect(6, 8, 8, 20), ICE, 'diag'); tri(c, [(7, 3), (2, 10), (12, 10)]); c.shape(rect(15, 4, 17, 16), ICE, 'diag'); tri(c, [(16, 21), (11, 14), (21, 14)])

# filter funnel
c = new('filter'); tri(c, [(3, 4), (21, 4), (14, 13), (14, 20), (10, 17), (10, 13)])

# star outline
c = new('starO'); c.shape(minus(star_poly(12, 12.5, 10.5, 4.8), star_poly(12, 12.8, 6.2, 2.7)), ICE, 'diag')

# swap horizontal
c = new('swapH'); c.shape(rect(4, 6, 15, 8), ICE, 'vert'); tri(c, [(21, 7), (14, 2), (14, 12)]); c.shape(rect(8, 15, 19, 17), ICE, 'vert'); tri(c, [(3, 16), (10, 11), (10, 21)])

# refresh
c = new('refresh'); c.shape(both(ring(12, 12, 9, 5.2), lambda x, y: not (x > 12 and y < 8)), ICE, 'orb'); tri(c, [(13, 2), (21, 7), (13, 12)])

# info / help / error
def disc(name, rp):
    c = new(name); c.shape(ell(12, 12, 9.5, 9.5), rp, 'orb'); return c
c = disc('info', R['info']); c.shape(rect(11, 10, 13, 17), ICE, 'flat'); c.shape(rect(11, 6, 13, 8), ICE, 'flat')
c = disc('help', R['info']); c.shape(rect(11, 16, 13, 18), ICE, 'flat'); bar(c, 8, 8.5, 12, 6.5, 2.6); bar(c, 12, 6.5, 15.5, 9.5, 2.6); bar(c, 15.5, 9.5, 12, 13, 2.6); c.shape(rect(11, 12, 13, 14), ICE, 'flat')
c = disc('error', R['bad']); c.shape(rect(11, 6, 13, 13), ICE, 'flat'); c.shape(rect(11, 15, 13, 17), ICE, 'flat')

# eye off
c = new('eyeOff'); c.shape(ell(12, 12, 10, 5.5), ICE, 'orb'); c.shape(ell(12, 12, 3.4, 3.4), R['info'], 'orb'); bar(c, 4, 20, 20, 4, 2.8, R['bad'])

# pencil
c = new('pencil'); bar(c, 4, 20, 17, 7, 5, R['gold']); tri(c, [(3, 21), (5, 15), (9, 19)], R['paper']); bar(c, 17.5, 6.5, 20, 4, 5, R['red'])

# picture
c = new('picture'); c.shape(rect(3, 4, 20, 19), ICE, 'diag'); c.shape(rect(5, 6, 18, 17), R['sea'], 'vert'); tri(c, [(5, 17), (10, 10), (14, 17)], R['green']); tri(c, [(11, 17), (15, 12), (18, 17)], R['green']); c.shape(ell(15, 9, 1.8, 1.8), R['gold'], 'orb')

# chart
c = new('chart'); c.shape(rect(3, 13, 7, 20), R['info'], 'diag'); c.shape(rect(9, 8, 13, 20), R['ok'], 'diag'); c.shape(rect(15, 3, 19, 20), R['gold'], 'diag'); c.shape(rect(2, 20, 20, 21), ICE, 'flat')

# grid
c = new('grid')
for x in (3, 13):
    for y in (3, 13): c.shape(rect(x, y, x + 7, y + 7), ICE, 'diag')

# hex
c = new('hex'); pts = [(12 + 10 * math.cos(math.radians(60 * i - 90)), 12 + 10 * math.sin(math.radians(60 * i - 90))) for i in range(6)]
pts2 = [(12 + 6 * math.cos(math.radians(60 * i - 90)), 12 + 6 * math.sin(math.radians(60 * i - 90))) for i in range(6)]
c.shape(minus(poly(pts), poly(pts2)), ICE, 'diag')

# drag (grip)
c = new('drag')
for y in (6, 11, 16): c.shape(rect(4, y, 19, y + 2), ICE, 'vert')

# move (four arrows)
c = new('move'); c.shape(rect(10, 4, 13, 19), ICE, 'diag'); c.shape(rect(4, 10, 19, 13), ICE, 'diag')
tri(c, [(12, 1), (7, 6), (17, 6)]); tri(c, [(12, 22), (7, 17), (17, 17)]); tri(c, [(1, 12), (6, 7), (6, 17)]); tri(c, [(22, 12), (17, 7), (17, 17)])

# door
c = new('door'); c.shape(rect(5, 3, 18, 21), R['wood'], 'diag'); c.shape(rect(7, 5, 16, 19), R['woodl'], 'vert'); c.shape(ell(14, 12, 1.3, 1.3), R['gold'], 'orb')

# checkboxes + ring
c = new('box'); c.shape(minus(rect(3, 3, 20, 20), rect(6, 6, 17, 17)), ICE, 'diag')
c = new('boxOn'); c.shape(minus(rect(3, 3, 20, 20), rect(6, 6, 17, 17)), ICE, 'diag'); bar(c, 7, 12, 10, 15, 3, R['ok']); bar(c, 10, 15, 17, 8, 3, R['ok'])
c = new('ring'); c.shape(ring(12, 12, 9, 5.5), ICE, 'orb')

# vibration: phone + waves
c = new('vibration'); c.shape(rect(8, 3, 15, 20), ICE, 'diag'); c.shape(rect(10, 5, 13, 16), R['info'], 'vert'); bar(c, 4, 7, 4, 16, 2); bar(c, 19, 7, 19, 16, 2); bar(c, 1.5, 9, 1.5, 14, 1.6); bar(c, 21.5, 9, 21.5, 14, 1.6)

# volume: speaker + waves
c = new('volume'); c.shape(rect(3, 9, 8, 15), ICE, 'diag'); tri(c, [(8, 9), (14, 4), (14, 20), (8, 15)]); bar(c, 17, 9, 17, 15, 2.4); bar(c, 20.5, 6, 20.5, 18, 2.4)

# wifi off
c = new('wifiOff'); c.shape(both(ring(12, 19, 15, 11.5), lambda x, y: y < 14), ICE, 'orb'); c.shape(both(ring(12, 19, 10, 6.5), lambda x, y: y < 15), ICE, 'orb'); c.shape(ell(12, 18.5, 2.2, 2.2), ICE, 'orb'); bar(c, 4, 20, 20, 4, 2.6, R['bad'])

if __name__ == '__main__':
    import io
    from PIL import Image
    names = list(G)
    sheet = Image.new('RGBA', (10 * 60, ((len(names) + 9) // 10) * 60), (30, 78, 98, 255))
    for i, n in enumerate(names):
        im = G[n].render().resize((48, 48), Image.NEAREST); sheet.paste(im, ((i % 10) * 60 + 6, (i // 10) * 60 + 6), im)
    sheet.save('pix3_sheet.png')
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'images', 'icons')
    if os.environ.get('PIX3_SHIP'):
        for n in names:
            G[n].render().save(os.path.join(out, n + '.webp'), 'WEBP', lossless=True, quality=100)
        print('shipped', len(names))
    print(len(names), names)
