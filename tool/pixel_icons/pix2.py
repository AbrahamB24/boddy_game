import os, io, json, base64, math
os.chdir(os.path.dirname(os.path.abspath(__file__)))
from pix import *  # noqa
import pix

R.update({k: ramp(v) for k, v in dict(pink='#f07aa0', cream='#f6edd3', navy='#3a5aa8', dkgreen='#3f8a5a', amber='#e8a53a', purple='#8a5ac8').items()})


def heart(cx, cy, s):
    def f(x, y):
        u = (x - cx) / s; v = -(y - cy) / s * 1.05 + 0.15
        return (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0
    return f


def star_poly(cx, cy, ro, ri):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5; r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(pts)


SOC = []; PRO = []; CHE = []


def new(lst, name, desc):
    c = Cv(); lst.append((name, desc, c)); return c


# ---------------- SOCIAL ----------------
SOC.append(('Zwei Sprechblasen', 'Blaue Blase mit Punkten, orange mit Herz.', pix.I['people']))

c = new(SOC, 'Herz-Blase', 'Eine große Blase mit rotem Herz.')
c.shape(poly([(3, 3), (20, 3), (21, 4), (21, 15), (20, 16), (14, 16), (9, 21), (9, 16), (4, 16), (3, 15)]), R['blue'], 'diag')
c.shape(heart(12, 9.5, 5.2), R['red'], 'orb')
c.px(10, 7, R['face'], 4); c.px(9, 8, R['face'], 4)

c = new(SOC, 'Schreibt…', 'Helle Blase mit drei Punkten, wie ein Chat.')
c.shape(poly([(2, 4), (21, 4), (22, 5), (22, 15), (21, 16), (11, 16), (6, 21), (6, 16), (3, 16), (2, 15)]), R['paper'], 'diag')
for x in (8, 12, 16): c.shape(ell(x, 10, 1.5, 1.5), R['blue'], 'orb')

c = new(SOC, 'Brief mit Siegel', 'Umschlag, Herz als Siegel.')
c.shape(rect(2, 6, 21, 19), R['paper'], 'diag')
c.shape(poly([(2, 6), (11.5, 13.5), (21, 6)]), R['paper'], 'vert', -.12)
c.line(2, 7, 11, 14, R['paper'], 1); c.line(21, 7, 12, 14, R['paper'], 1)
c.shape(heart(11.5, 13, 3.4), R['red'], 'orb')

c = new(SOC, 'Megafon', 'Rufen, ankündigen, Freunde finden.')
c.shape(rect(5, 14, 8, 20), R['leatherd'], 'diag')
c.shape(poly([(2, 8), (9, 8), (18, 3), (18, 16), (9, 13), (2, 13)]), R['red'], 'diag')
c.shape(ell(18, 9.5, 1.8, 6.6), R['goldl'], 'orb')
c.line(21, 5, 22, 4, R['gold'], 3); c.line(21, 9, 23, 9, R['gold'], 3); c.line(21, 13, 22, 14, R['gold'], 3)
c.line(3, 9, 8, 9, R['red'], 4)

c = new(SOC, 'Netzwerk', 'Drei verbundene Knoten.')
c.line(12, 6, 5, 17, R['iron'], 2); c.line(12, 6, 19, 17, R['iron'], 2); c.line(5, 17, 19, 17, R['iron'], 2)
c.line(13, 6, 6, 17, R['iron'], 1); c.line(13, 6, 20, 17, R['iron'], 1)
c.shape(ell(12, 6, 3.6, 3.6), R['blue'], 'orb'); c.shape(ell(5, 17, 3.6, 3.6), R['orange'], 'orb'); c.shape(ell(19, 17, 3.6, 3.6), R['green'], 'orb')

c = new(SOC, 'Zwei Herzen', 'Großes und kleines Herz.')
c.shape(heart(9, 10, 7), R['red'], 'orb')
c.shape(heart(17, 15.5, 5), R['pink'], 'orb')
c.px(6, 7, R['face'], 4); c.px(5, 8, R['face'], 4)

c = new(SOC, 'Kettenglieder', 'Zwei verbundene Glieder.')
c.shape(minus(ell(15, 12, 7, 5), ell(15, 12, 4, 2.4)), R['iron'], 'diag')
c.shape(minus(ell(9, 12, 7, 5), ell(9, 12, 4, 2.4)), R['gold'], 'diag')
c.shape(both(minus(ell(15, 12, 7, 5), ell(15, 12, 4, 2.4)), rect(11, 7, 14, 10)), R['iron'], 'diag')

c = new(SOC, 'Papierflieger', 'Nachricht schicken.')
c.shape(poly([(2, 11), (21, 3), (11, 14)]), R['paper'], 'diag')
c.shape(poly([(11, 14), (21, 3), (15, 20)]), R['paper'], 'diag', .15)
c.shape(poly([(11, 14), (13, 19), (15, 20)]), R['blue'], 'diag')
c.line(4, 11, 18, 5, R['blue'], 3)

c = new(SOC, 'Zwei Krüge', 'Anstoßen in der Taverne.')
for ox, hx_ in ((0, 1), (9, 20)):
    c.shape(rect(3 + ox, 9, 10 + ox, 19), R['amber'], 'vert')
    c.shape(ell(6.5 + ox, 9, 4.2, 2), R['cream'], 'orb')
    c.shape(minus(ell(hx_, 14, 2.2, 3.6), ell(hx_, 14, 1, 2)), R['iron'], 'diag')
    c.line(4 + ox, 13, 9 + ox, 13, R['amber'], 1); c.line(4 + ox, 16, 9 + ox, 16, R['amber'], 1)
    c.line(4 + ox, 11, 4 + ox, 17, R['amber'], 4)
c.px(11, 6, R['goldl'], 4); c.px(12, 5, R['goldl'], 4); c.px(10, 5, R['goldl'], 4)

# ---------------- PROFILE ----------------
PRO.append(('Ausweis', 'Karte mit Siegel und Textzeilen.', pix.I['person']))

c = new(PRO, 'Wappenschild', 'Schild mit goldenem Stern.')
c.shape(poly([(3, 2), (21, 2), (21, 12), (17, 18), (12, 22), (7, 18), (3, 12)]), R['steel'], 'diag')
c.shape(poly([(5, 4), (19, 4), (19, 11.5), (16, 16.5), (12, 19.5), (8, 16.5), (5, 11.5)]), R['blue'], 'diag')
c.shape(star_poly(12, 11.2, 5.4, 2.4), R['goldl'], 'flat', -.05)

c = new(PRO, 'Krone', 'Rang und Titel.')
c.shape(poly([(3, 18), (3, 8), (8, 12), (12, 5), (16, 12), (21, 8), (21, 18)]), R['gold'], 'diag')
c.shape(rect(3, 16, 20, 19), R['gold'], 'vert', .1)
c.px(12, 14, R['red'], 2); c.px(12, 13, R['red'], 3); c.px(6, 17, R['blue'], 2); c.px(18, 17, R['blue'], 2); c.px(12, 17, R['green'], 2)
for xy in ((3, 7), (12, 4), (21, 7)): c.px(*xy, R['goldl'], 4)
c.line(5, 10, 6, 13, R['goldl'], 4)

c = new(PRO, 'Medaille', 'Auszeichnung mit Band.')
c.shape(poly([(6, 1), (11, 1), (13, 10), (9, 10)]), R['red'], 'diag')
c.shape(poly([(12, 1), (17, 1), (15, 10), (11, 10)]), R['blue'], 'diag')
c.shape(ell(12, 16, 6.4, 6.4), R['gold'], 'orb')
c.shape(ell(12, 16, 4.4, 4.4), R['gold'], 'orb', .2)
c.shape(star_poly(12, 16.2, 3.4, 1.5), R['goldl'], 'flat', -.05)

c = new(PRO, 'Pergament', 'Charakterbogen mit Wachssiegel.')
c.shape(ell(11.5, 4.5, 8, 1.9), R['paper'], 'vert', .1)
c.shape(rect(4, 4, 19, 18), R['paper'], 'diag')
c.shape(ell(11.5, 18.5, 8, 1.9), R['paper'], 'vert', .1)
for yy in (8, 11, 14): c.line(6, yy, 14, yy, R['iron'], 2)
c.line(6, 7, 11, 7, R['black'], 2)
c.shape(ell(16.5, 16.5, 3, 3), R['red'], 'orb'); c.px(16, 16, R['face'], 3)
c.line(14, 19, 13, 22, R['red'], 2); c.line(18, 19, 19, 22, R['red'], 2)

c = new(PRO, 'Chronik-Buch', 'Dickes Buch mit Stern.')
c.shape(rect(4, 3, 19, 20), R['blue'], 'diag')
c.shape(rect(4, 3, 6, 20), R['navy'], 'diag', .1)
c.shape(rect(19, 4, 20, 19), R['paper'], 'vert')
c.shape(star_poly(12.5, 11, 4.4, 2), R['goldl'], 'flat', -.05)
c.line(8, 17, 17, 17, R['gold'], 3)
c.shape(rect(14, 19, 15, 22), R['red'], 'diag')

c = new(PRO, 'Banner', 'Hängende Fahne mit Emblem.')
c.shape(rect(2, 2, 21, 3), R['wood'], 'vert')
c.shape(poly([(4, 3), (20, 3), (20, 17), (12, 21), (4, 17)]), R['red'], 'vert')
c.shape(ell(12, 10, 4.2, 4.2), R['gold'], 'orb'); c.shape(star_poly(12, 10.2, 3, 1.3), R['red'], 'flat', .1)
c.line(5, 4, 5, 15, R['red'], 4); c.px(2, 1, R['gold'], 3); c.px(21, 1, R['gold'], 3)

c = new(PRO, 'Ritterhelm', 'Visierhelm mit Federbusch.')
c.shape(poly([(10, 3), (14, 2), (18, 5), (13, 6)]), R['red'], 'diag')
c.shape(ell(12, 11, 8, 8.5, lambda x, y: y < 14), R['steel'], 'orb')
c.shape(rect(4, 11, 19, 20), R['steel'], 'vert')
c.shape(rect(6, 11, 17, 12), R['black'], 'flat'); c.line(6, 15, 17, 15, R['iron'], 1)
for xy in ((8, 17), (10, 17), (12, 17), (14, 17), (16, 17)): c.px(*xy, R['iron'], 1)
c.line(12, 4, 12, 10, R['steel'], 3)

c = new(PRO, 'Siegelring', 'Goldring mit blauem Stein.')
c.shape(minus(ell(12, 15, 7.4, 7.4), ell(12, 15, 4.6, 4.6)), R['gold'], 'orb')
c.shape(poly([(8, 8), (16, 8), (17, 4), (7, 4)]), R['gold'], 'diag')
c.shape(poly([(8, 3), (16, 3), (18, 6), (12, 9), (6, 6)]), R['blue'], 'diag')
c.px(9, 4, R['face'], 4); c.px(10, 4, R['face'], 4)

c = new(PRO, 'Reisepass', 'Grünes Heft mit goldenem Siegel.')
c.shape(rect(5, 2, 19, 21), R['dkgreen'], 'diag')
c.shape(rect(5, 2, 6, 21), R['dkgreen'], 'diag', .22)
c.shape(ell(12.5, 9.5, 4.6, 4.6), R['gold'], 'orb')
c.line(8, 9.5, 17, 9.5, R['goldl'], 3); c.line(12.5, 5, 12.5, 14, R['goldl'], 3)
c.line(9, 16, 16, 16, R['gold'], 3); c.line(10, 18, 15, 18, R['gold'], 3)

# ---------------- CHEST ----------------
c = new(CHE, 'Geschlossen, Kuppel', 'Hoher Deckel, großes Schloss, Eisenbänder.')
c.shape(poly([(3, 12), (4, 6), (7, 3), (16, 3), (19, 6), (20, 12)]), R['woodl'], 'vert')
c.shape(rect(3, 12, 20, 20), R['wood'], 'vert')
c.shape(rect(3, 11, 20, 13), R['gold'], 'vert')
c.shape(rect(6, 3, 7, 20), R['iron'], 'diag'); c.shape(rect(16, 3, 17, 20), R['iron'], 'diag')
c.shape(rect(10, 10, 13, 17), R['goldl'], 'diag'); c.px(11, 13, R['black'], 2); c.px(12, 13, R['black'], 2); c.px(11, 14, R['black'], 2); c.px(12, 14, R['black'], 2)
c.line(8, 5, 14, 4, R['woodl'], 4)
for xy in ((4, 14), (4, 18), (19, 14), (19, 18)): c.px(*xy, R['goldl'], 3)

c = new(CHE, 'Geschlossen, Funkeln', 'Wie links, mit goldenem Glanz.')
c.shape(poly([(3, 13), (4, 8), (7, 5), (16, 5), (19, 8), (20, 13)]), R['woodl'], 'vert')
c.shape(rect(3, 13, 20, 21), R['wood'], 'vert')
c.shape(rect(3, 12, 20, 14), R['gold'], 'vert')
c.shape(rect(6, 5, 7, 21), R['iron'], 'diag'); c.shape(rect(16, 5, 17, 21), R['iron'], 'diag')
c.shape(rect(10, 12, 13, 18), R['goldl'], 'diag'); c.px(11, 15, R['black'], 2); c.px(12, 15, R['black'], 2)
for x, y in ((3, 3), (20, 4), (12, 1)):
    c.px(x, y, R['goldl'], 4); c.px(x - 1, y, R['goldl'], 3); c.px(x + 1, y, R['goldl'], 3); c.px(x, y - 1, R['goldl'], 3); c.px(x, y + 1, R['goldl'], 3)

c = new(CHE, 'Offen, Goldhaufen', 'Deckel hinten, Goldberg mit Edelsteinen.')
c.shape(poly([(3, 2), (20, 2), (22, 9), (2, 9)]), R['woodl'], 'vert')
c.shape(poly([(5, 4), (18, 4), (19, 8), (4, 8)]), R['leatherd'], 'vert', -.2)
c.shape(rect(2, 11, 21, 21), R['wood'], 'vert')
c.shape(rect(2, 11, 21, 12), R['gold'], 'vert')
c.shape(poly([(3, 12), (6, 7), (10, 4), (14, 4), (18, 7), (21, 12)]), R['gold'], 'orb', -.05)
for x, y, rp in ((8, 8, 'gold'), (12, 6, 'goldl'), (15, 8, 'goldl'), (10, 10, 'goldl')): c.px(x, y, R[rp], 4)
c.shape(ell(16.5, 9.5, 1.3, 1.3), R['red'], 'orb'); c.shape(ell(6.5, 10.2, 1.2, 1.2), R['blue'], 'orb')
c.shape(rect(9, 14, 14, 19), R['goldl'], 'diag'); c.px(11, 16, R['black'], 2); c.px(12, 16, R['black'], 2); c.px(11, 17, R['black'], 2)
c.shape(rect(5, 11, 6, 21), R['iron'], 'diag'); c.shape(rect(17, 11, 18, 21), R['iron'], 'diag')


R.update({k: ramp(v) for k, v in dict(darkwood='#5a3a2a', redwood='#9a4a30', silver='#b9c3d0', violet='#8a5ac8').items()})

c = new(CHE, 'Flach, klassisch', 'Flacher Deckel, Eisenbänder, goldenes Schloss.')
c.shape(rect(3, 11, 20, 19), R['wood'], 'vert')
c.shape(poly([(3, 11), (4, 7), (8, 5), (15, 5), (19, 7), (20, 11)]), R['woodl'], 'vert')
c.shape(rect(3, 10, 20, 12), R['gold'], 'vert')
c.shape(rect(6, 6, 7, 19), R['iron'], 'diag'); c.shape(rect(16, 6, 17, 19), R['iron'], 'diag')
c.shape(rect(10, 11, 13, 15), R['goldl'], 'diag'); c.px(11, 13, R['black'], 2); c.px(12, 13, R['black'], 2)

c = new(CHE, 'Piratentruhe', 'Dunkles Holz mit Totenkopf-Schloss.')
c.shape(poly([(3, 12), (4, 6), (8, 3), (15, 3), (19, 6), (20, 12)]), R['darkwood'], 'vert')
c.shape(rect(3, 12, 20, 20), R['darkwood'], 'vert', .06)
c.shape(rect(3, 11, 20, 13), R['iron'], 'vert')
c.shape(rect(6, 3, 7, 20), R['iron'], 'diag'); c.shape(rect(16, 3, 17, 20), R['iron'], 'diag')
c.shape(ell(11.5, 15, 3.4, 3.2), R['cream'], 'orb'); c.px(10, 14, R['black'], 2); c.px(13, 14, R['black'], 2); c.px(11, 17, R['black'], 2); c.px(12, 17, R['black'], 2)
c.line(9, 5, 14, 4, R['darkwood'], 4)

c = new(CHE, 'Eisentruhe', 'Stahlbeschlagen mit Nieten.')
c.shape(poly([(3, 12), (4, 6), (8, 4), (15, 4), (19, 6), (20, 12)]), R['steel'], 'vert')
c.shape(rect(3, 12, 20, 20), R['iron'], 'vert')
c.shape(rect(3, 11, 20, 13), R['steel'], 'vert', -.1)
for x in (5, 8, 11, 14, 17): c.px(x, 8, R['iron'], 1); c.px(x, 16, R['steel'], 4)
c.shape(rect(10, 11, 13, 16), R['gold'], 'diag'); c.px(11, 14, R['black'], 2); c.px(12, 14, R['black'], 2)
c.line(7, 5, 14, 5, R['steel'], 4)

c = new(CHE, 'Offen, Lichtschein', 'Deckel auf, Licht strahlt heraus.')
c.shape(poly([(5, 1), (10, 8), (12, 0), (14, 8), (19, 1), (18, 9), (6, 9)]), R['goldl'], 'flat', -.15)
c.shape(rect(3, 11, 20, 20), R['wood'], 'vert')
c.shape(poly([(2, 11), (3, 8), (20, 8), (21, 11)]), R['woodl'], 'vert')
c.shape(rect(3, 10, 20, 11), R['gold'], 'vert')
c.shape(rect(6, 8, 7, 20), R['iron'], 'diag'); c.shape(rect(16, 8, 17, 20), R['iron'], 'diag')
c.shape(rect(10, 13, 13, 17), R['goldl'], 'diag'); c.px(11, 15, R['black'], 2); c.px(12, 15, R['black'], 2)

c = new(CHE, 'Edelsteinschloss', 'Violetter Deckel, blauer Stein als Schloss.')
c.shape(poly([(3, 12), (4, 6), (8, 3), (15, 3), (19, 6), (20, 12)]), R['violet'], 'vert')
c.shape(rect(3, 12, 20, 20), R['wood'], 'vert')
c.shape(rect(3, 11, 20, 13), R['gold'], 'vert')
c.shape(rect(6, 3, 7, 20), R['gold'], 'diag'); c.shape(rect(16, 3, 17, 20), R['gold'], 'diag')
c.shape(poly([(11.5, 9), (15, 12.5), (11.5, 17), (8, 12.5)]), R['blue'], 'diag'); c.px(10, 12, R['face'], 4)

c = new(CHE, 'Mit Tragegriffen', 'Breit, seitliche Ringe, runde Schlossplatte.')
c.shape(rect(3, 11, 20, 20), R['redwood'], 'vert')
c.shape(poly([(3, 11), (4, 7), (8, 5), (15, 5), (19, 7), (20, 11)]), R['redwood'], 'vert', -.12)
c.shape(rect(3, 10, 20, 12), R['gold'], 'vert')
c.shape(minus(ell(1.5, 15, 1.6, 2.6), ell(2, 15, .7, 1.3)), R['gold'], 'diag'); c.shape(minus(ell(22, 15, 1.6, 2.6), ell(21.5, 15, .7, 1.3)), R['gold'], 'diag')
c.shape(ell(11.5, 14.5, 3, 3), R['goldl'], 'orb'); c.px(11, 14, R['black'], 2); c.px(11, 15, R['black'], 2)
for x in (6, 17): c.shape(rect(x, 6, x, 19), R['iron'], 'diag')

c = new(CHE, 'Mit Schlüssel', 'Geschlossen, Schlüssel darauf.')
c.shape(rect(3, 12, 20, 20), R['wood'], 'vert')
c.shape(poly([(3, 12), (4, 8), (8, 6), (15, 6), (19, 8), (20, 12)]), R['woodl'], 'vert')
c.shape(rect(3, 11, 20, 13), R['gold'], 'vert')
c.shape(rect(6, 6, 7, 20), R['iron'], 'diag'); c.shape(rect(16, 6, 17, 20), R['iron'], 'diag')
c.shape(rect(10, 12, 13, 16), R['goldl'], 'diag'); c.px(11, 14, R['black'], 2); c.px(12, 14, R['black'], 2)
c.shape(minus(ell(8, 3.5, 2.6, 2.6), ell(8, 3.5, 1.1, 1.1)), R['gold'], 'orb'); c.shape(rect(10, 3, 17, 4), R['gold'], 'diag'); c.px(15, 5, R['gold'], 2); c.px(17, 5, R['gold'], 2)

# ---------------- BELL ----------------
BEL = []
BEL.append(('Goldglocke', 'Die aktuelle.', pix.I['bell']))

c = new(BEL, 'Handglocke', 'Holzgriff oben, Messingkörper.')
c.shape(rect(10, 1, 13, 7), R['wood'], 'diag'); c.shape(rect(9, 0, 14, 1), R['leather'], 'flat')
c.shape(poly([(6, 18), (7, 11), (10, 8), (14, 8), (17, 11), (18, 18), (21, 20), (3, 20)]), R['gold'], 'orb')
c.shape(rect(3, 19, 21, 20), R['brass'], 'vert', .1)
c.shape(ell(12, 22, 1.6, 1.2), R['leatherd'], 'orb'); c.line(9, 12, 9, 17, R['gold'], 4)

c = new(BEL, 'Mitteilung', 'Klassische Glocke mit rotem Punkt.')
c.shape(ell(12, 4, 1.8, 1.8), R['gold'], 'orb')
c.shape(poly([(5, 18), (6, 10), (9, 6), (15, 6), (18, 10), (19, 18), (21, 19), (3, 19)]), R['gold'], 'orb')
c.shape(ell(12, 21, 2.3, 1.6), R['gold'], 'orb'); c.line(8, 9, 8, 15, R['gold'], 4)
c.shape(ell(18, 5, 3.4, 3.4), R['red'], 'orb'); c.px(17, 4, R['face'], 4)

c = new(BEL, 'Glockenstuhl', 'Glocke im Holzgestell.')
c.shape(rect(2, 3, 4, 20), R['wood'], 'diag'); c.shape(rect(19, 3, 21, 20), R['wood'], 'diag'); c.shape(rect(2, 2, 21, 4), R['wood'], 'vert')
c.shape(rect(2, 20, 21, 21), R['wood'], 'vert')
c.shape(rect(11, 5, 12, 8), R['iron'], 'flat')
c.shape(poly([(6, 18), (7, 11), (9, 8), (14, 8), (16, 11), (17, 18), (19, 20), (4, 20)]), R['gold'], 'orb')

c = new(BEL, 'Mit Schleife', 'Festglocke mit roter Schleife.')
c.shape(poly([(5, 20), (6, 12), (9, 8), (15, 8), (18, 12), (19, 20), (21, 21), (3, 21)]), R['gold'], 'orb')
c.shape(ell(12, 22.5, 2, 1.1), R['gold'], 'orb') if False else None
c.shape(poly([(12, 5), (7, 2), (7, 7)]), R['red'], 'diag'); c.shape(poly([(12, 5), (17, 2), (17, 7)]), R['red'], 'diag')
c.shape(poly([(11, 6), (9, 11), (11, 10)]), R['red'], 'diag'); c.shape(poly([(13, 6), (15, 11), (13, 10)]), R['red'], 'diag')
c.shape(ell(12, 5, 1.6, 1.6), R['red'], 'orb'); c.line(8, 13, 8, 18, R['gold'], 4)

c = new(BEL, 'Läutet', 'Glocke mit Klangbögen.')
c.shape(ell(12, 4, 1.6, 1.6), R['gold'], 'orb')
c.shape(poly([(7, 18), (8, 10), (10, 6), (14, 6), (16, 10), (17, 18), (19, 20), (5, 20)]), R['gold'], 'orb')
c.shape(ell(12, 21.5, 2, 1.4), R['gold'], 'orb'); c.line(9, 10, 9, 16, R['gold'], 4)
for x0, x1 in ((2, 3), (0, 1)): c.line(x0, 8 + (x0 == 0) * 0, x0, 13, R['goldl'], 3)
c.line(3, 8, 3, 14, R['goldl'], 3); c.line(1, 9, 1, 13, R['goldl'], 3)
c.line(20, 8, 20, 14, R['goldl'], 3); c.line(22, 9, 22, 13, R['goldl'], 3)

c = new(BEL, 'Wandglocke', 'Hängt an einem Eisenarm.')
c.shape(rect(2, 2, 14, 3), R['iron'], 'vert'); c.shape(rect(2, 2, 3, 21), R['iron'], 'diag')
c.shape(rect(13, 3, 14, 8), R['iron'], 'flat')
c.shape(poly([(8, 18), (9, 12), (11, 9), (16, 9), (18, 12), (19, 18), (21, 20), (6, 20)]), R['gold'], 'orb')
c.shape(ell(13.5, 21.5, 1.6, 1.2), R['leatherd'], 'orb')

c = new(BEL, 'Schellenkugel', 'Kleine runde Schelle mit Öse.')
c.shape(minus(ell(12, 3.6, 3, 2.4), ell(12, 3.6, 1.3, 1)), R['gold'], 'orb')
c.shape(ell(12, 13, 8.5, 8.5), R['gold'], 'orb')
c.shape(rect(5, 14, 19, 15), R['black'], 'flat'); c.shape(ell(12, 17.5, 1.5, 1.5), R['black'], 'flat')
c.px(7, 8, R['face'], 4); c.px(8, 7, R['face'], 4); c.px(7, 9, R['goldl'], 4)

c = new(BEL, 'Kuhglocke', 'Kastenform mit Lederriemen.')
c.shape(rect(10, 1, 13, 6), R['leather'], 'diag')
c.shape(poly([(7, 6), (17, 6), (20, 19), (4, 19)]), R['amber'], 'diag')
c.shape(rect(4, 18, 20, 19), R['brass'], 'vert', .15)
c.shape(rect(11, 20, 13, 22), R['iron'], 'diag'); c.line(9, 8, 6, 16, R['amber'], 4); c.line(14, 8, 16, 14, R['amber'], 1)

c = new(BEL, 'Stahlglocke', 'Silberglocke mit blauem Punkt.')
c.shape(ell(12, 4, 1.8, 1.8), R['silver'], 'orb')
c.shape(poly([(5, 18), (6, 10), (9, 6), (15, 6), (18, 10), (19, 18), (21, 19), (3, 19)]), R['silver'], 'orb')
c.shape(ell(12, 21, 2.3, 1.6), R['silver'], 'orb'); c.line(8, 9, 8, 15, R['silver'], 4)
c.shape(ell(18, 5, 3.4, 3.4), R['blue'], 'orb'); c.px(17, 4, R['face'], 4)

if __name__ == '__main__':
    out = {}
    for tag, lst in (('s', SOC), ('p', PRO), ('c', CHE), ('b', BEL)):
        for i, (n, d, cv) in enumerate(lst):
            im = cv.render() if hasattr(cv, 'render') and not isinstance(cv, Image.Image) else cv
            b = io.BytesIO(); im.save(b, 'PNG')
            out[f'{tag}{i}'] = dict(n=n, d=d, u='data:image/png;base64,' + base64.b64encode(b.getvalue()).decode())
    json.dump(out, open('pix2.json', 'w'))
    sheet = Image.new('RGBA', (10 * 100, 4 * 100), (30, 78, 98, 255))
    for row, lst in enumerate((SOC, PRO, CHE, BEL)):
        for i, (n, d, cv) in enumerate(lst):
            im = cv.render() if not isinstance(cv, Image.Image) else cv
            im = im.resize((96, 96), Image.NEAREST); sheet.paste(im, (i * 100 + 2, row * 100 + 2), im)
    sheet.save('pix2_sheet.png'); print('ok')
