# Elephant: a great grey body, a domed head with a wide ear, a long ringed trunk, a curved white
# tusk, pillar legs with pale toenails and a thin tufted tail. Poses: standing, a four-step walk,
# and the trunk thrown up as it strikes.
K = 0x1C1A26
g = ramp(0x969AAC, light=0xF4F0E0, dark=0x2A2448)
pal = dict(h=g[0], b=g[1], s=g[2], d=g[3], p=0xB494A6, P=0x957488, t=0xF6F0DE, T=0xCFC4A6,
           e=0x1E1418, w=0xFFFFFF, n=0xDCD6C8, k=0x3A3648)
inner = g[3]

body = part("""
..............hhhhhhhhhhhhhhhh........
.........hhhhhhhhhhhhhhhhhhhhhhhh.....
......hhhhhhhhhhhhhhhhhhhhhhhhhhhhh...
....hhhhhhhhhbbbbbbbbbbbbbbbbbbhhhhh..
...hhhhbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.
..hhhbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
.hhbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
.hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
hbbbbbbbsbbbbbbbbbbbbbbbbbbbsbbbbbbbbb
bbbbbbbbsbbbbbbbbbbbbbbbbbbbsbbbbbbbbb
bbbbbbbbbsbbbbbbbbbbbbbbbbbsbbbbbbbbbb
bbbbbbbbbsbbbbbbbbbbbbbbbbbsbbbbbbbbbb
sbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbs
sbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbss
ssbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbss.
.ssbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbsss..
..sssbbbbbbbbbbbbbbbbbbbbbbbbbssss....
...ssssssbbbbbbbbbbbbbbbbbssssss......
.....sssssssssssssssssssssssss........
.......ddddddddddddddddddddd..........
""", pal, outline=K, inner=inner)

tail = part("""
.bs
bs.
bs.
bs.
bs.
bs.
bs.
bs.
.bs
.kk
kkk
.k.
""", pal, outline=K, inner=inner)

head = part("""
......hhhhhhh.........
....hhhhhhhhhhh.......
...hhhhhhhhhhhhhh.....
..hhhbbbbbbbbbbbhh....
..hbbbbbbbbbbbbbbbh...
.hbbbbbbbbbbbbbbbbbh..
.hbbbbbbbbbbbbbbbbbb..
.bbbbbbbbbbbwebbbbbbb.
.bbbbbbbbbbbeebbbbbbb.
.bbbbbbbbbbbbbbbbbbbbb
.sbbbbbbbbbbbbbbbbbbbb
.sbbbbbbbbbbbbbbsbbbbb
..sbbbbbbbbbbbbsbbbbbb
..ssbbbbbbbbbbssbbbbbs
...sssbbbbbbbss.hbbbbs
....sssssssss...hbbbbs
................hsssss
................hbbbbs
................hbbbbs
................hsssss
................hbbbs.
...............hbbbbs.
...............hsssss.
...............hbbbs..
...............hbbbs..
...............hssss..
................hbbbs.
................hbbbs.
.................hsss.
.................hbbbs
.................hbbbb
..................ssbb
...................ss.
""", pal, outline=K, inner=inner)

head_up = part("""
......hhhhhhh..............
....hhhhhhhhhhh........hbb.
...hhhhhhhhhhhhhh.....hbbbs
..hhhbbbbbbbbbbbhh....hbbss
..hbbbbbbbbbbbbbbbh..hbbbs.
.hbbbbbbbbbbbbbbbbbhhbsbss.
.hbbbbbbbbbbbbbbbbbbbbbbs..
.bbbbbbbbbbbwebbbbbbbsbss..
.bbbbbbbbbbbeebbbbbbbbbs...
.bbbbbbbbbbbbbbbbbbbsbss...
.sbbbbbbbbbbbbbbbbbbbss....
.sbbbbbbbbbbbbbbsbbbss.....
..sbbbbbbbbbbbbsbbsss......
..ssbbbbbbbbbbssrrr........
...sssbbbbbbbss.rr.........
....sssssssss..............
""", dict(pal, r=0x8A3A4A), outline=K, inner=inner)

ear = part("""
...hhhhh....
..hbbbbbh...
.hbbbbbbbh..
hbbppppbbbb.
hbpppppppbb.
bbppppppppb.
bbpppppppbb.
bbppppppbbs.
sbbpppppbbs.
sbbbpppbbs..
.sbbbbbbbs..
.ssbbbbbs...
..ssbbbss...
...sssss....
""", pal, outline=K, inner=inner)

tusk = part("""
ttt......
TTttt....
.TTTttt.t
...TTtttt
.....TTT.
""", pal, outline=K, inner=0xA89C84)

def leg(dark):
    c = dict(pal)
    if dark:
        c.update(h=g[1], b=g[2], s=g[3], n=0xB0AAA0)
    return part("""
    bbbbbbbb.
    bbbbbbbs.
    bbbbbbbs.
    bbbbbbss.
    hbbbbbss.
    hbbbbbss.
    hbbsbbss.
    hbbbsbss.
    hbbbbbss.
    hbbbbbss.
    hbbbbbss.
    hbbbbbss.
    hbbbbbbs.
    bbbbbbbbs
    nbnbnbbbs
    """, c, outline=K, inner=inner, open_top=True)

near = leg(False)
far = leg(True)
W, H = 64, 46

def fr(bob, nb, nf, up=False):
    fb, ff = nf, nb
    L = [
        (tail, 1, 9 + bob),
        (far, 11 + fb[0], 26 - fb[1]),
        (far, 33 + ff[0], 26 - ff[1]),
        (body, 3, 6 + bob),
        (near, 5 + nb[0], 26 - nb[1]),
        (near, 27 + nf[0], 26 - nf[1]),
    ]
    if up:
        L += [(head_up, 33, 3 + bob), (ear, 32, 7 + bob), (tusk, 46, 15 + bob)]
    else:
        L += [(head, 33, 5 + bob), (ear, 32, 9 + bob), (tusk, 46, 18 + bob)]
    return frame(W, H, L)

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (2, 0), (-2, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(0, (-2, 0), (2, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(-1, (0, 0), (1, 1), up=True),
]
sprite("elephant", frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=40, cx=26)
