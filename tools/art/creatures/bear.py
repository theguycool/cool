# Bears: a heavy body, a low round-eared head with a muzzle and a dark nose, thick legs on wide clawed
# paws. Each kind has its own build: the brown bear; the larger grizzly with a tall silvered hump;
# the polar bear, long and smooth-backed with a narrow head, cream with blue shadows.
BROWN_BODY = """
.............gggggggg.....
.........hhhhggggggggggh..
.....hhhhhhhhhggggggghhhh.
...hhhhhhhhhhhhhhhhhhhhbbb
..hhhbbbbbbbbbbbbbbbbbbbbb
.hhbbbbbbbbbbbbbbsbbbbbbbb
.hbbbbbbbbbbbbbbbsbbbbbbbb
.bbbbbbbbbbbbbbbbbsbbbbbbb
.bbbbbbbbbbbbbbbbbsbbbbbbb
.sbbbbbbbbbbbbbbbbbsbbbbbs
.sbbbbbbbbbbbbbbbbbbbbbbss
..sbbbbbbbbbbbbbbbbbbbbss.
...ssbbbbbbbbbbbbbbbbsss..
.....sssssssssssssssss....
.......ddddddddddddd......
"""
GRIZZLY_BODY = """
................gggggggg......
.............ggggggggggggg....
..........hhhggggggggggggggh..
......hhhhhhhhgggggggggghhhhh.
....hhhhhhhhhhhhhhhhhhhhhhhbbb
..hhhhbbbbbbbbbbbbbbbbbbbbbbbb
.hhhbbbbbbbbbbbbbbbbbsbbbbbbbb
.hhbbbbbbbbbbbbbbbbbbsbbbbbbbb
.hbbbbbbbbbbbbbbbbbbbbsbbbbbbb
.bbbbbbbbbbbbbbbbbbbbbsbbbbbbb
.bbbbbbbbbbbbbbbbbbbbbbsbbbbbs
.sbbbbbbbbbbbbbbbbbbbbbbbbbbss
.sbbbbbbbbbbbbbbbbbbbbbbbbbss.
..sbbbbbbbbbbbbbbbbbbbbbbbss..
...ssbbbbbbbbbbbbbbbbbbbsss...
.....ssssssssssssssssssss.....
.......dddddddddddddddd.......
"""
POLAR_BODY = """
.......hhhhhhhhhhhhhhh........
....hhhhhhhhhhhhhhhhhhhhh.....
..hhhhhhhhhhhhhhhhhhhhhhhhh...
.hhhhbbbbbbbbbbbbbbbbbbbbhhhh.
.hhbbbbbbbbbbbbbbbbbbbbbbbbbbh
hhbbbbbbbbbbbbbbbbbbbsbbbbbbbb
hbbbbbbbbbbbbbbbbbbbbsbbbbbbbb
hbbbbbbbbbbbbbbbbbbbbbsbbbbbbb
bbbbbbbbbbbbbbbbbbbbbbsbbbbbbb
sbbbbbbbbbbbbbbbbbbbbbbbbbbbbs
sbbbbbbbbbbbbbbbbbbbbbbbbbbbss
.sbbbbbbbbbbbbbbbbbbbbbbbbbss.
..ssbbbbbbbbbbbbbbbbbbbbsss...
....ssssssssssssssssssss......
......dddddddddddddddd........
"""
ROUND_HEAD = """
..bbb............
.bsssb...........
.bssbbhhhhhh.....
..bbhhhhhhhhhh...
.hhhbbbbsssbbbh..
hhbbbbbbbwebbbb..
hbbbbbbbbeellllnn
bbbbbbbbbbbmmmmnn
sbbbbbbbbbsmmmmmm
.sbbbbbbbssMMMMM.
..sbbbbbbskkkkk..
...ssbbbbssmmm...
....sssssss......
"""
ROUND_BITE = """
..bbb............
.bsssb...........
.bssbbhhhhhh.....
..bbhhhhhhhhhh...
.hhhbbbbsssbbbh..
hhbbbbbbbwebbbb..
hbbbbbbbbeellllnn
bbbbbbbbbbbmmmmnn
sbbbbbbbbbsmtmtm.
.sbbbbbbbssrrrrr.
..sbbbbbbssrrrrr.
...sbbbbbssmtmtm.
....ssbbbssmmmm..
.....ssssssMMM...
"""
LONG_HEAD = """
..bb...............
.bssb..............
.bsbbhhhhhhh.......
..bhhhhhhhhhhhh....
.hhhbbbbsssbbbbh...
hhbbbbbbbwebbbbbh..
hbbbbbbbbeebbbbbbnn
bbbbbbbbbbbbbbbbbnn
sbbbbbbbbbsbbbbbbb.
.sbbbbbbbsskkkkkk..
..ssbbbbbssbbbb....
....sssssss........
"""
LONG_BITE = """
..bb...............
.bssb..............
.bsbbhhhhhhh.......
..bhhhhhhhhhhhh....
.hhhbbbbsssbbbbh...
hhbbbbbbbwebbbbbh..
hbbbbbbbbeebbbbbbnn
bbbbbbbbbbbbbbbbbnn
sbbbbbbbbbsbtbtbt..
.sbbbbbbbssrrrrrr..
..sbbbbbbssrrrrrr..
...sbbbbbssbtbtbt..
....ssbbbssbbbbb...
......sssssss......
"""

def bear(name, fur, muzzle, K, body, head, bite, at, claw=0xEDE4CC, nose=0x1E1418, light=0xFFE2A8, dark=0x24183A, hump=None, pads=None):
    f = ramp(fur, light=light, dark=dark)
    m = ramp(muzzle, light=0xFFF8E8, dark=dark)
    pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], m=m[1], M=m[2], l=m[0], n=nose, e=0x1A1216, w=0xFFFFFF,
               c=claw, t=0xF4EEDC, r=0x8E2A34, g=hump if hump else f[0], D=pads if pads else f[3], k=mix(f[3], 0x000000, 0.45))
    inner = f[3]
    bd = part(body, pal, outline=K, inner=inner)
    hd = part(head, pal, outline=K, inner=inner)
    hb = part(bite, pal, outline=K, inner=inner)

    def leg(dk):
        c = dict(pal)
        if dk:
            c.update(h=f[1], b=f[2], s=f[3])
        return part("""
        bbbbb.
        bbbbb.
        bbbbs.
        bbbbs.
        bbbss.
        bbbss.
        bbbbss
        bbbbbs
        DcDcDc
        """, c, outline=K, inner=inner, open_top=True)

    near, far = leg(False), leg(True)
    W, H, by, ly, legs_x, hx0, hy0, cx = at
    def fr(bob, nb, nf, biting=False, hx=0):
        fb, ff = nf, nb
        L = [
            (far, legs_x[1] + fb[0], ly - fb[1]),
            (far, legs_x[3] + ff[0], ly - ff[1]),
            (bd, 1, by + bob),
            (near, legs_x[0] + nb[0], ly - nb[1]),
            (near, legs_x[2] + nf[0], ly - nf[1]),
            (hb if biting else hd, hx0 + hx, hy0 + bob),
        ]
        return frame(W, H, L)

    frames = [
        fr(0, (0, 0), (0, 0)),
        fr(0, (2, 0), (-2, 0)),
        fr(-1, (0, 0), (0, 1)),
        fr(0, (-2, 0), (2, 0)),
        fr(-1, (0, 1), (0, 0)),
        fr(0, (-1, 0), (2, 1), biting=True, hx=2),
    ]
    sprite(name, frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=ly + 8, cx=cx)

# (canvas w, h, body y, legs y, legs x: near back, far back, near front, far front, head x, head y, centre)
bear("bear", 0x8A5A38, 0xC8A070, 0x1C1418, BROWN_BODY, ROUND_HEAD, ROUND_BITE,
     (46, 26, 3, 15, (3, 8, 18, 23), 22, 4, 16))
bear("grizzly", 0x6E4A30, 0xB89468, 0x181014, GRIZZLY_BODY, ROUND_HEAD, ROUND_BITE,
     (50, 28, 3, 17, (3, 9, 21, 27), 26, 6, 18), hump=0xB8A894)
bear("polarBear", 0xEDE8DA, 0xEDE8DA, 0x1E2434, POLAR_BODY, LONG_HEAD, LONG_BITE,
     (52, 26, 3, 15, (3, 9, 21, 27), 26, 4, 18), claw=0x3A3A44, light=0xFFFFFF, dark=0x3A5A9A, pads=0x8A94AA)
