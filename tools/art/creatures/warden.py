# The Hollow Warden: an empty suit of dark armour under a ragged violet hood, with two cold violet
# lights where its eyes should be, a breastplate marked with a sigil, a long tattered cloak in place
# of legs (it floats), and a great scythe with a pale curved blade. It hovers with the scythe upright,
# draws it back over its shoulder, sweeps it low in front with a violet trail, and casts with its
# free hand raised and a light gathering in its palm.
from artlib import Grid, add_outline

K = 0x100C18
cl = ramp(0x3A2E4A, light=0xC8B8E8, dark=0x0C0818)
ar = ramp(0x5A5E6E, light=0xE8E8F8, dark=0x141428)
pal = dict(h=cl[0], b=cl[1], s=cl[2], d=cl[3], k=0x0A0612,
           A=ar[0], a=ar[1], g=ar[2], G=ar[3], v=0xA878E0, V=0xE0C8FF,
           e=0xD8A8FF, E=0xFFF0FF, w=0xD8DCE6, W=0xF4F6FA, x=0x9AA0B0, X=0x6A7080,
           t=0x5A4636, T=0x3A2C22, m=0xC890FF, M=0xF4E4FF)
inner = cl[3]

HOOD = """
.......hh.......
......hbbh......
.....hbbbbh.....
....hbbbbbbh....
...hbbbbbbbbs...
..hbbbbbbkkkks..
.hbbbbbbkkkkkks.
.hbbbbbkkkkkkks.
hbbbbbkkkkkeEks.
hbbbbbkkkkkkkks.
hbbbbbkkkkekkks.
sbbbbbbkkkkkkss.
sbbbbbbbkkkkss..
.ssbsbbsbskss...
..s..s.ss..s....
"""
CHEST = """
....AAAAAAAAA...
..AAAAaaaaaaaaa.
.AAaaaaaaaaaaaag
.Aaaaaaaavaaaagg
Aaaaaaaavvvaaagg
aaaaaaaaaVaaaagg
gaaaaaaaavaaaagg
ggaaaaaaaaaaaggG
.ggaaaaaaaaaaggG
..gggggggggggGG.
"""
PAULDRON = """
....AAAAAa...
..AAAAaaaaag.
.AAaaaaaaaggg
AAaaaaaaaggG.
aaaaaaaagggG.
.gggggggGGG..
"""
# the near arm in each pose: forearm and gauntlet; the hand is where the shaft passes
ARM_HOLD = """
.aag.
Aaagg
aaagG
.agG.
.aag.
AaaaG
aagGG
.gGG.
"""
ARM_BACK = """
.....AAa.
...AAaag.
..Aaagg..
.AaagG...
Aaagg....
aaGG.....
.GG......
"""
ARM_SWEEP = """
.AAaa.......
Aaaaaaaaaag.
aaggggaaaaaG
.GG...gGGaGG
.........GG.
"""
ARM_CAST = """
.AAa.........
Aaaagaaaaa...
aaggggaaaaaAa
.GG....ggGaaG
.........gGG.
"""
ORB = """
..m.m..
.mMMMm.
mMMEMMm
.mMMMm.
..m.m..
"""
BLADE_UP = """
XXxxwwwwwwwW........
.XXxxwwwwwwwwWWWW...
...XX.....xxwwwwWWW.
...............wwWW.
.................wWW
..................WW
...................W
"""
BLADE_BACK = """
.........WWw....
.......WWwwx....
.....WWwwx......
....Wwwx........
...Wwwx.........
..Www...........
.Www............
.Ww.............
Ww..............
W...............
"""
BLADE_LOW = """
W...............
WW..............
.WWw............
..WWwww.........
....wwwwwwxxxXX.
.......wwxxxXXX.
...........XX...
"""
TRAIL = """
mm.............
..mm...........
....mmm........
.......mmmm....
...........mmmm
"""


def lined(g):
    """A part from a picture drawn in code: a margin and a dark line round it"""
    out = Grid(g.w + 2, g.h + 2)
    out.put(g, 1, 1)
    before = [r[:] for r in out.px]
    add_outline(out, K)
    out.edge = set((x, y) for y in range(out.h) for x in range(out.w) if before[y][x] is None and out.px[y][x] is not None)
    out.inner = cl[3]
    out.m = 1
    return out


def shaft(x0, y0, x1, y1):
    """The scythe's shaft, two pixels wide, lit on its upper side"""
    w, h = abs(x1 - x0) + 2, abs(y1 - y0) + 2
    g = Grid(w, h)
    ox, oy = min(x0, x1), min(y0, y1)
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        x = round(x0 + (x1 - x0) * i / steps) - ox
        y = round(y0 + (y1 - y0) * i / steps) - oy
        g.set(x, y, grade(pal["t"]))
        g.set(x + 1, y, grade(pal["T"]))
    return lined(g), ox, oy


def cloak(sway):
    """The cloak: narrow under the chest, wide at the hem, folds in long lines, a torn hem that the
    hover sways"""
    H, top, bottom = 44, 20, 40
    rows = []
    for y in range(H):
        wdt = round(top + (bottom - top) * (y / (H - 1)) ** 0.8)
        left = (bottom - wdt) // 2 + (round(sway * y / H) if y > H // 2 else 0)
        r = ["."] * (bottom + 4)
        for x in range(wdt):
            fx = x / max(wdt - 1, 1)
            ch = "b"
            if x == 0:
                ch = "h"
            elif x >= wdt - 2:
                ch = "s" if x == wdt - 2 else "d"
            elif abs(fx - 0.3) < 0.04 or abs(fx - 0.62) < 0.04:
                ch = "s"
            elif fx < 0.12:
                ch = "h"
            r[left + x + 1] = ch
        rows.append(r)
    # the torn hem: some columns end early, a few hang lower
    for x in range(bottom + 4):
        cut = (x * 7 + 3) % 5
        for y in range(H - cut, H):
            rows[y][x] = "."
    return part("\n".join("".join(r) for r in rows), pal, outline=K, inner=inner)


W, Hh = 84, 94
FOOT = 90


def fr(mode="hover", bob=0, sway=0):
    bx, by = 30, 20 + bob            # the hood's corner
    layers = []
    near = []
    # the scythe goes behind or in front, by pose
    if mode in ("hover", "cast"):
        hx = bx + 22 if mode == "hover" else bx - 2
        sh, ox, oy = shaft(hx, by - 8, hx, by + 52)
        layers.append((sh, ox, oy))
        layers.append((part(BLADE_UP, pal, outline=K), hx - 1, by - 11))
    elif mode == "back":
        sh, ox, oy = shaft(bx + 18, by + 30, bx - 6, by - 10)
        layers.append((sh, ox, oy))
        layers.append((part(BLADE_BACK, pal, outline=K), bx - 16, by - 11))
    layers.append((cloak(sway), bx - 12, by + 27))
    layers.append((part(CHEST, pal, outline=K, inner=ar[3]), bx - 1, by + 16))
    layers.append((part(HOOD, pal, outline=K, inner=inner), bx, by))
    layers.append((part(PAULDRON, pal, outline=K, inner=ar[3]), bx + 3, by + 14))
    if mode == "hover":
        near.append((part(ARM_HOLD, pal, outline=K, inner=ar[3]), bx + 20, by + 20))
    elif mode == "back":
        near.append((part(ARM_BACK, pal, outline=K, inner=ar[3]), bx + 9, by + 18))
    elif mode == "sweep":
        sh, ox, oy = shaft(bx + 6, by + 14, bx + 40, by + 44)
        near.append((part(TRAIL, pal), bx + 30, by + 30))
        near.append((sh, ox, oy))
        near.append((part(BLADE_LOW, pal, outline=K), bx + 38, by + 41))
        near.append((part(ARM_SWEEP, pal, outline=K, inner=ar[3]), bx + 9, by + 19))
    elif mode == "cast":
        near.append((part(ARM_CAST, pal, outline=K, inner=ar[3]), bx + 9, by + 19))
        near.append((part(ORB, pal), bx + 23, by + 16))
    return frame(W, Hh, layers + near)


frames = [fr("hover", 0, 0), fr("hover", 1, 2), fr("back", 0, -1), fr("sweep", 1, 2), fr("cast", -1, 0)]
sprite("warden", frames, {"idle": [0], "fly": [0, 1], "windup": [2], "strike": [3], "cast": [4]}, foot=FOOT, cx=42)
