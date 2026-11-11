# Pig: a round pink body, a floppy ear, a flat snout with two nostrils, a curly tail and short legs
# on dark trotters. Poses: standing, a four-step walk, rooting in the ground.
K = 0x3A1826
pal = dict(h=0xFFC8C0, p=0xF29CA8, s=0xD4748C, d=0xA85070, n=0xFFB6B6, N=0x8C3A56, e=0x1E1418, w=0xFFFFFF, f=0x5E2E40)

body = part("""
......hhhhhhhhh....
....hhhhhhhhhhhhh..
...hhppppppppppppp.
.s.ppppppppppppppp.
s.sppppppppppppppp.
s..ppppppppppppppp.
.sspppppppppppppps.
...sppppppppppppss.
...ssppppppppppsss.
....ssssssssssssd..
.....ddddddddddd...
""", pal, outline=K, inner=pal["d"])

head = part("""
..pp........
.pspp.......
.psphhhh....
.hhhhhhhh...
hhpppewpp...
hppppeeppnnn
ppppppppnnNn
spppppppnnnn
.spppppdnnNn
..ssppppdd..
...sssss....
""", pal, outline=K, inner=pal["d"])

def leg(dark):
    c = dict(pal)
    if dark:
        c["p"] = pal["s"]
        c["s"] = pal["d"]
    return part("""
ppp
ppp
pps
pps
fff
""", c, outline=K, open_top=True, inner=pal["d"])

near = leg(False)
far = leg(True)

def fr(bob, nb, nf, head_at=(16, 2)):
    """bob: how far the body sits down; nb, nf: the near back and near front legs as (dx, lift).
    The far legs do the opposite of the near ones."""
    fb, ff = nf, nb
    L = [
        (far, 8 + fb[0], 12 - fb[1]),
        (far, 16 + ff[0], 12 - ff[1]),
        (body, 1, 3 + bob),
        (near, 5 + nb[0], 12 - nb[1]),
        (near, 13 + nf[0], 12 - nf[1]),
        (head, head_at[0], head_at[1] + bob),
    ]
    return frame(30, 18, L)

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (2, 0), (-2, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(0, (-2, 0), (2, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(0, (0, 0), (0, 0), head_at=(17, 6)),
]
sprite("pig", frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=16, cx=11.5)
