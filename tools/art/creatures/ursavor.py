# Ursavor, Warden of the Gate: a bear the size of a hut, in near-black fur gone grey at the tips,
# with a row of pale bone plates down its spine, a heavy head with a scar across one amber eye, a
# lighter muzzle and claws like knives. It prowls on four great legs, rears up with its forepaws
# raised to roar or slam, and swipes with one forepaw while its jaws gape.
from artlib import Grid, add_outline

K = 0x120C10
f = ramp(0x4A3A34, light=0xC8B8A0, dark=0x100818)
mz = ramp(0x8A6A50, light=0xF0D8B0, dark=0x2A1828)
bone = ramp(0xD8CCB0, light=0xFFFFF0, dark=0x5A4A50)
pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], H=mix(f[0], 0xFFFFFF, 0.25),
           m=mz[1], M=mz[2], l=mz[0], n=0x1A1014, e=0xFFB030, E=0xFFF0B0, x=0xC88A7A,
           o=bone[0], O=bone[1], q=bone[2], t=0xF4EEDC, r=0x8E2A34, R=0x5A1420, c=0xE8E0CC, C=0x9A9080)
inner = f[3]


def lined(g, inner_col=inner):
    out = Grid(g.w + 2, g.h + 2)
    out.put(g, 1, 1)
    before = [r[:] for r in out.px]
    add_outline(out, K)
    out.edge = set((x, y) for y in range(out.h) for x in range(out.w) if before[y][x] is None and out.px[y][x] is not None)
    out.inner = inner_col
    out.m = 1
    return out


# the body's outline, as (u, y) points from the rump (u 0) to the chest (u 1): the top runs from a round
# rump up to the great hump over the shoulders and down to the neck; the bottom is the belly
TOP = [(0.0, 16), (0.04, 8), (0.12, 4), (0.3, 3), (0.5, 2), (0.64, -2), (0.76, -5), (0.88, -1), (0.96, 7), (1.0, 14)]
BOT = [(0.0, 26), (0.04, 33), (0.15, 37), (0.5, 38), (0.8, 37), (0.93, 33), (1.0, 26)]


def profile(pts, u):
    for (u0, y0), (u1, y1) in zip(pts, pts[1:]):
        if u0 <= u <= u1:
            t = (u - u0) / (u1 - u0)
            t = t * t * (3 - 2 * t)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def body_blob(W=66, tilt=0.0):
    """The body, worked out from its outline and lit from the upper left: a light band along the back,
    fur strokes on the flank, shadow under the belly. `tilt` lifts the front (rearing)."""
    g = Grid(W, 52)
    P = {k: grade(v) for k, v in pal.items()}
    for x in range(W):
        u = x / (W - 1)
        lift = tilt * max(0.0, u - 0.25) * 22
        t0 = int(round(profile(TOP, u) - lift)) + 10
        t1 = int(round(profile(BOT, u) - lift * 0.75)) + 10
        for y in range(t0, t1 + 1):
            v = (y - t0) / max(t1 - t0, 1)
            if y - t0 < 2:
                c = P["h"]
            elif v < 0.6:
                c = P["b"]
            elif v < 0.85:
                c = P["s"]
            else:
                c = P["d"]
            # fur: a few short strokes down the flank, a few grey tips along the back
            if 0.2 < v < 0.75 and ((x * 5 + y * 3) % 37 == 0 or (x * 5 + (y - 1) * 3) % 37 == 0):
                c = P["s"]
            if v < 0.3 and (x * 7 + y * 11) % 31 == 0:
                c = P["H"]
            g.set(x, y, c)
    return lined(g)


PLATE = """
..o..
.ooO.
ooOOq
oOOqq
"""
HEAD = """
.....bbb..................
....bsssb.................
....bssbbhhhhhhh..........
.....bbhhhhhhhhhhhh.......
...hhhhbbbbbbbbbbbhh......
..hhbbbbbbbbbbbbbbbbh.....
.hhbbbbbbbbbxbbbbbbbbh....
hhbbbbbbbbbbbxssssbbbbh...
hbbbbbbbbbbbbxEebbbbbbbb..
hbbbbbbbbbbbbbxeebllllllnn
bbbbbbbbbbbbbbbxlllllllnnn
bbbbbbbbbbbbbbbbmmmmmmmmnn
sbbbbbbbbbbbbbbsmmmmmmmmmm
sbbbbbbbbbbbbbssmmmmmmmmm.
.sbbbbbbbbbbbssMMMMMMMMM..
..sbbbbbbbbbbsnnnnnnnnn...
...sbbbbbbbbssmmmmmmmm....
....ssbbbbbbsssMMMMMM.....
......sssssssss...........
"""
HEAD_ROAR = """
.....bbb..................
....bsssb.................
....bssbbhhhhhhh..........
.....bbhhhhhhhhhhhh.......
...hhhhbbbbbbbbbbbhh......
..hhbbbbbbbbbbbbbbbbh.....
.hhbbbbbbbbbxbbbbbbbbh....
hhbbbbbbbbbbbxssssbbbbh...
hbbbbbbbbbbbbxEebbbbbbbb..
hbbbbbbbbbbbbbxeebllllllnn
bbbbbbbbbbbbbbbxlllllllnnn
bbbbbbbbbbbbbbbbmmmmmmmmnn
sbbbbbbbbbbbbbbsmtmtmtmtm.
sbbbbbbbbbbbbbssRRRRRRRR..
.sbbbbbbbbbbbssrrrrrrrrR..
..sbbbbbbbbbbsrrrrrrrrrR..
...sbbbbbbbbssrrrrrrrrR...
....sbbbbbbbsstmtmtmtmm...
.....ssbbbbbssmmmmmmmm....
.......ssssssssMMMMM......
"""
LEG_HIND = """
.bbbbbbbbb..
bbbbbbbbbbb.
bbbbbbbbbbbs
bbbbbbbbbbbs
.bbbbbbbbbss
..bbbbbbbss.
..bbbbbbbs..
..bbbbbbbs..
..bbbbbbss..
..bbbbbbss..
..bbbbbbss..
..bbbbbbss..
..bbbbbbbss.
..bbbbbbbbs.
..bbbbbbbbbs
..ssssssssss
..cCcCcCcCc.
"""
LEG = """
bbbbbbbbb..
bbbbbbbbbs.
bbbbbbbbbs.
bbbbbbbbss.
bbbbbbbbss.
bbbbbbbbss.
.bbbbbbbss.
.bbbbbbbss.
.bbbbbbbss.
.bbbbbbbss.
.bbbbbbbss.
.bbbbbbbbss
.bbbbbbbbbs
.bbbbbbbbbs
.ssssssssss
.cCcCcCcCc.
"""
PAW_UP = """
.bbbbbbb...
bbbbbbbbs..
bbbbbbbbs..
bbbbbbbbss.
.bbbbbbbbs.
..bbbbbbbss
...bbbbbbbs
....bbbbbbs
....sssssss
....cCcCcCc
....c.c.c.c
"""
SWIPE = """
................c..
.............c..C..
..........c..C..c..
.......bbbbbbbbbC..
...bbbbbbbbbbbbbbs.
.bbbbbbbbbbbbbbbbbs
bbbbbbbbbbbbbbbbbss
bbbbbbbsssssssssss.
.sssss.............
"""
TRAIL = """
...........x...
.........xx....
......xxx......
..xxxx.........
xx.............
"""

far_pal = dict(pal, h=f[1], b=f[2], s=f[3], H=f[1])
head = part(HEAD, pal, outline=K, inner=inner)
roar = part(HEAD_ROAR, pal, outline=K, inner=inner)
leg_n = part(LEG, pal, outline=K, inner=inner, open_top=True)
leg_f = part(LEG, far_pal, outline=K, inner=inner, open_top=True)
hind_n = part(LEG_HIND, pal, outline=K, inner=inner, open_top=True)
hind_f = part(LEG_HIND, far_pal, outline=K, inner=inner, open_top=True)
paw_n = part(PAW_UP, pal, outline=K, inner=inner)
paw_f = part(PAW_UP, far_pal, outline=K, inner=inner)
swipe = part(SWIPE, pal, outline=K, inner=inner)
plate = part(PLATE, pal, outline=K, inner=bone[2])
trail = part(TRAIL, dict(x=0xE8E0D0))

W, Hh = 112, 92
GROUND = 88
BODY_X = 10


def spine(bx, by, tilt):
    """Bone plates along the back, from the rump to the hump"""
    out = []
    for u in (0.16, 0.3, 0.44, 0.56, 0.67, 0.77, 0.86):
        x = bx + int(u * 65) - 2
        lift = tilt * max(0.0, u - 0.25) * 22
        y = by + int(round(profile(TOP, u) - lift)) + 10 - 3
        out.append((plate, x, y))
    return out


def fr(mode="stand", step=0, bob=0):
    """mode: stand, rear (forepaws up, head raised and roaring), swipe (one forepaw lashing out)"""
    tilt = 1.0 if mode == "rear" else 0.0
    bx, by = BODY_X, 30 + bob
    layers = []
    back_x, front_x = bx + 4, bx + 45
    ly = GROUND - 15
    if mode == "rear":
        layers += [(hind_f, back_x + 7, ly), (paw_f, front_x + 12, by - 8)]
    else:
        layers += [(hind_f, back_x + 7 - step, ly), (leg_f, front_x + 6 + step, ly)]
    layers.append((body_blob(tilt=tilt), bx, by))
    layers += spine(bx + 1, by, tilt)
    if mode == "rear":
        layers += [(hind_n, back_x, ly), (paw_n, front_x + 6, by - 3)]
        layers.append((roar, bx + 57, by - 18))
    elif mode == "swipe":
        layers += [(hind_n, back_x + 1, ly), (swipe, front_x + 4, by + 16)]
        layers.append((roar, bx + 57, by + 6))
        layers.append((trail, front_x + 18, by + 8))
    else:
        layers += [(hind_n, back_x + step, ly), (leg_n, front_x - step, ly)]
        layers.append((head, bx + 57, by + 5))
    return frame(W, Hh, layers)


frames = [fr("stand"), fr("stand", 3, 0), fr("stand", 0, 1), fr("stand", -3, 0), fr("stand", 0, 1),
          fr("rear"), fr("swipe")]
sprite("bearBoss", frames, {"idle": [0], "walk": [1, 2, 3, 4], "rear": [5], "strike": [6]}, foot=GROUND, cx=50)
