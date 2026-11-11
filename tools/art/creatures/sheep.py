# Sheep: a round fleece with curls, a dark face with a pale eye, a floppy ear and thin dark legs.
# Shorn (sheep_1) it is a slim pinkish body with the same head and legs. Poses: standing, a four-step
# walk, grazing.
K = 0x1E1A24
pal = dict(w=0xF8F4EC, W=0xDED8D4, v=0xBAB2BC, f=0x524C5A, F=0x6C6676, d=0x3A3442, n=0x2A2430, e=0xFFFFFF, k=0x16141A,
           p=0xECC8B8, P=0xF8DCCC, q=0xCDA498, Q=0xA88078)

fleece = part("""
...ww.www.www.ww....
.wwwwwwwwwwwwwwwww..
wwWwwwwwwwwwwwwwwww.
wwwwwwwwwWwwwwwwwwww
wwwwwwwwwwwwwwwwwwww
wWwwwwwwwwwwwwWwwwww
wwwwwwwwwwwwwwwwwwww
vwwwwWwwwwwwwwwwwwwv
vvwwwwwwwwwwwwwwwwvv
.vvvwwwwwwwwwwwwvvv.
..vvv.vvvv.vvvv.vv..
""", pal, outline=K, inner=pal["v"])

shorn = part("""
....PPPPPPPPPPPP....
..PPPPPPPPPPPPPPPP..
.PPppppppppppppppp..
.pppppppppppppppppp.
.pppppppppppppppppp.
.qpppppppppppppppqq.
.qqppppppppppppqqq..
..qqqqqqqqqqqqqqq...
....QQQQQQQQQQQ.....
""", pal, outline=K, inner=pal["Q"])

head = part("""
.dd......
dFFff....
.Fffffff.
.fffekfff
.ffffffff
..fffffdn
...ffffdn
....dddd.
""", pal, outline=K, inner=pal["d"])

def leg(dark):
    c = dict(pal)
    if dark:
        c.update(f=pal["d"], F=pal["f"])
    return part("""
    Ff
    Ff
    Ff
    Ff
    ff
    nn
    """, c, outline=K, inner=pal["d"], open_top=True)

near = leg(False)
far = leg(True)

def make(name, body, by):
    def fr(bob, nb, nf, head_at=(18, 3)):
        fb, ff = nf, nb
        L = [
            (far, 8 + fb[0], 14 - fb[1]),
            (far, 18 + ff[0], 14 - ff[1]),
            (body, 1, by + bob),
            (near, 5 + nb[0], 14 - nb[1]),
            (near, 15 + nf[0], 14 - nf[1]),
            (head, head_at[0], head_at[1] + bob),
        ]
        return frame(30, 22, L)
    frames = [
        fr(0, (0, 0), (0, 0)),
        fr(0, (2, 0), (-2, 0)),
        fr(-1, (0, 0), (0, 1)),
        fr(0, (-2, 0), (2, 0)),
        fr(-1, (0, 1), (0, 0)),
        fr(0, (0, 0), (0, 0), head_at=(20, 10)),
    ]
    sprite(name, frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=19, cx=12)

make("sheep", fleece, 3)
make("sheep_1", shorn, 5)
