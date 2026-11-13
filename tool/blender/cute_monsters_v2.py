"""Round 2: less real animal, more fantasy creature. Four test monsters first.

    blender --background --python tool/blender/cute_monsters_v2.py -- --out docs/renders/monsters/proposals_v2
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute_monsters as cm  # noqa: E402

GLOW_O = ('#ffd36b', '#ff8a1f', 1.4)


def embit2(b):
    """Fox around a coal heart: glowing belly, flame ears, a tail that floats free as a spark."""
    b.E(-0.02, 0, .40, .38, .28, .27, 'body')
    b.E(.10, 0, .38, .30, .24, .22, 'core')                      # the coal heart, shows through the fur
    b.E(.16, 0, .40, .20, .17, .16, 'core2')
    b.legs4(.26, -.24, .17, .30, .09, 'body', 'paw')
    h, r = (.44, 0, .72), (.37, .35, .32)
    b.E(*h, *r, 'body'); b.E(.74, 0, .64, .14, .13, .10, 'belly')
    b.nose((.74, 0, .64), (.14, .13, .10), .04, 8)
    b.eyes(h, r, .10, 36, 10)
    for sg in (-1, 1):                                            # ears: dark fox ear that turns into flame
        b.L((.38, sg * .20, .94), (.30, sg * .32, 1.22), .12, .05, 'body')
        b.spike(.30, sg * .32, 1.20, .30, .09, 0, sg * .1, 'glow')
        b.spike(.30, sg * .32, 1.20, .18, .05, .3, sg * .5, 'glow2')
    b.spike(.44, 0, .98, .26, .08, .1, 0, 'glow'); b.spike(.40, .05, .98, .16, .05, .5, .3, 'glow2')
    # the tail floats: a flame body with three sparks rising off it, no fur connection
    b.E(-.58, 0, .62, .15, .13, .20, 'glow', (0, -.3, 0))
    b.spike(-.58, 0, .72, .38, .13, .35, 0, 'glow'); b.spike(-.56, .05, .74, .22, .07, .7, .3, 'glow2')
    b.E(-.74, .10, 1.08, .06, .06, .06, 'glow'); b.E(-.64, -.12, 1.22, .05, .05, .05, 'glow2'); b.E(-.80, -.05, 1.34, .04, .04, .04, 'glow')
    b.E(-.34, 0, .40, .10, .10, .10, 'core')


def dribblet2(b):
    """Seal-pup jellyfish: a water dome with a face, a small body below, two trailing tendrils."""
    b.E(0, 0, .44, .26, .24, .30, 'belly')
    b.E(0, 0, .30, .30, .28, .22, 'body')
    h, r = (.10, 0, .98), (.50, .50, .38)
    b.E(*h, *r, 'dome')                                           # the bell
    for k in range(10):                                           # scalloped rim
        a = k / 10 * 2 * math.pi
        b.E(h[0] + math.cos(a) * .46, math.sin(a) * .46, .66, .10, .10, .07, 'rim')
    b.E(.34, 0, .96, .20, .26, .20, 'face')
    b.eyes(h, r, .105, 34, 6); b.nose((.50, 0, .88), (.01, .01, .01), .04, 0)
    b.E(.42, 0, .84, .05, .07, .04, 'nose')
    for sg in (-1, 1):                                            # flippers
        b.E(.06, sg * .38, .44, .22, .07, .10, 'body', (0.5 * sg, 0, 0))
        b.chain([(-.10, sg * .30, .62, .06), (-.30, sg * .42, .46, .055), (-.46, sg * .36, .26, .05), (-.62, sg * .44, .12, .045)], 'tent')
        b.E(.14, sg * .16, .06, .17, .11, .06, 'body')
    b.chain([(-.10, 0, .64, .06), (-.30, 0, .50, .055), (-.40, 0, .30, .05), (-.56, 0, .20, .045)], 'tent')
    b.E(.06, .22, 1.46, .07, .07, .07, 'glow'); b.E(-.10, -.14, 1.54, .05, .05, .05, 'glow')   # bubbles
    b.E(.20, -.20, 1.36, .045, .045, .045, 'glow')
    b.spike(.0, 0, 1.30, .22, .07, 0, 0, 'glow')


def seedling2(b):
    """Onion-bulb sloth: root legs, vine arms, a whole flower bed on top."""
    b.E(0, 0, .52, .40, .38, .46, 'bulb')
    b.E(-.02, 0, 1.02, .20, .20, .20, 'bulb')                     # onion tip
    b.E(.28, 0, .42, .12, .20, .20, 'face')
    for sg in (-1, 1):
        b.E(.30, sg * .19, .64, .12, .09, .12, 'mask', (0.4 * sg, 0, 0))
    b.eyes((.0, 0, .62), (.44, .42, .30), .095, 32, 6)
    b.nose((.0, 0, .62), (.44, .42, .30), .045, -22)
    for k, sg in enumerate((-1, 0, 1)):                           # root legs
        b.chain([(.10, sg * .16, .12, .07), (.18, sg * .24, .06, .06), (.30, sg * .30, .04, .05)], 'root')
    for sg in (-1, 1):                                            # vine arms with leaf hands
        b.chain([(.0, sg * .38, .62, .05), (.12, sg * .54, .50, .045), (.24, sg * .60, .36, .04)], 'vine')
        b.E(.30, sg * .62, .30, .12, .04, .07, 'leaf', (0, 0, sg * .5))
    b.E(.0, 0, 1.22, .24, .24, .08, 'soil')                       # the flower bed
    for k in range(5):
        a = k / 5 * 2 * math.pi
        b.E(math.cos(a) * .16, math.sin(a) * .16, 1.36, .15, .045, .07, 'leaf', (0, -.5, a))
    for k in range(6):                                            # the flower
        a = k / 6 * 2 * math.pi
        b.E(math.cos(a) * .10, math.sin(a) * .10, 1.50, .09, .05, .035, 'petal', (0, 0, a))
    b.E(0, 0, 1.52, .06, .06, .05, 'glow')


def zipnut2(b):
    """Squirrel whose tail is a storm cloud with a lightning bolt hanging from it."""
    b.E(0, 0, .40, .34, .30, .38, 'body'); b.E(.14, 0, .34, .24, .24, .30, 'belly')
    h, r = (.18, 0, .88), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.E(.50, 0, .78, .15, .15, .11, 'belly'); b.nose((.50, 0, .78), (.15, .15, .11), .045, 8)
    b.eyes(h, r, .10, 36, 10); b.tooth(.52, .68, .04)
    for sg in (-1, 1):                                            # ear tufts shaped like bolts
        b.E(.08, sg * .22, 1.20, .05, .05, .09, 'glow', (0, 0, sg * .3))
        b.E(.06, sg * .30, 1.34, .05, .05, .09, 'glow', (0, 0, -sg * .3))
        b.E(.08, sg * .24, 1.48, .045, .045, .08, 'glow')
        b.L((.02, sg * .26, .60), (.30, sg * .12, .50), .08, .075, 'body')
    # the cloud tail
    for (x, y, z, rr, m) in ((-.50, 0, .86, .26, 'cloud'), (-.36, .18, .96, .20, 'cloud2'), (-.38, -.18, .92, .20, 'cloud2'),
                             (-.62, .16, 1.10, .18, 'cloud'), (-.60, -.14, 1.08, .17, 'cloud2'), (-.74, 0, .84, .18, 'cloud'),
                             (-.50, 0, 1.18, .17, 'cloud2')):
        b.E(x, y, z, rr, rr * .95, rr * .85, m)
    b.chain([(-.40, 0, .70, .05), (-.52, .04, .58, .05), (-.42, .0, .46, .045), (-.56, .04, .32, .04)], 'glow')
    b.E(-.58, .04, .26, .06, .06, .08, 'glow')
    b.E(.34, 0, .44, .13, .13, .13, 'nut'); b.E(.34, 0, .50, .07, .07, .08, 'glow')
    b.E2(.12, .16, .07, .18, .11, .07, 'body')
    b.chain([(-.26, 0, .28, .10), (-.36, 0, .52, .10), (-.40, 0, .70, .10)], 'body')


YEL = ('#fff29a', '#ffe030', 1.5)
cm.SPECIES.update({
    'embit2': (embit2, dict(body='#c96a3a', belly='#fff0d6', paw='#8a3c24', core=('#ffb02e', '#ff6a10', 2.2),
                            core2=('#ffe08a', '#ffc21a', 2.2), glow=('#ffd36b', '#ff7a14', 2.2), glow2=('#ff7a2e', '#e83c08', 2.0))),
    'dribblet2': (dribblet2, dict(body='#7fc6ee', belly='#e9f7ff', dome='#a8dcf7', rim='#8ecbee', face='#e9f7ff',
                                  tent='#8ecbee', glow=('#bff0ff', '#4fd0ff', 1.2))),
    'seedling2': (seedling2, dict(bulb='#ecdcc2', ridge='#d4c0a0', face='#f6eddb', mask='#8a7a5a', root='#8a6a44',
                                  vine='#6fae4e', leaf='#5fb04a', soil='#6b4a32', petal='#f6a8c8',
                                  glow=('#fff29a', '#ffe030', 1.4))),
    'zipnut2': (zipnut2, dict(body='#e6b84a', belly='#fff2c9', nut='#8a6a3a', cloud='#9a96c8', cloud2='#c4c1e6',
                              glow=YEL)),
})

if __name__ == '__main__':
    cm.main()
