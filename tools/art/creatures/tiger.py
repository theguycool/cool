# Tiger: long and low, orange with dark stripes, a white chest and cheeks, round ears, yellow eyes and
# a striped tail that curls up at the tip. Poses: standing, a four-step prowl, a bite.
K = 0x1E120C
f = ramp(0xF08A2A, light=0xFFF0B0, dark=0x40143A)
pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], S=0x2A1A16, l=0xFAF2E2, L=0xD8CCBC, y=0xFFE04A, e=0x14101A, n=0xE87A8A,
           k=0x3A1A1A, t=0xFFFFFF, r=0x9A2A38)
inner = f[3]
body = part("""
....hhhhhhhhhhhhhhhh....
..hhbbSbbbSbbbSbbbSbhh..
.hbbbbSbbbSbbbSbbbSbbbh.
hbbbbbSbbbSbbbSbbbSbbbbb
bbbbbbbbbbbbbbbbbbbbbbbb
bbbSbbbbSbbbbSbbbbSbbbbb
sbbSbbbbSbbbbSbbbbSbbbbs
.sslllllllllllllllllss..
...sLLLLLLLLLLLLLLLs....
""", pal, outline=K, inner=inner)
tail = part("""
hb......
b.......
S.......
bb......
.bSb....
...bSbb.
......bb
""", pal, outline=K, inner=inner)
head = part("""
.bb.....bb...
bSSb...bSSb..
bbbbhhhbbbbh.
.hbSbbbSbbbbh
hbbbbbbbbybbb
bSbbbbbbbebbl
bbbbbbbllllln
sSbbbbllllll.
.sbbbbllkkkl.
..sssllllll..
....sssss....
""", pal, outline=K, inner=inner)
bite = part("""
.bb.....bb....
bSSb...bSSb...
bbbbhhhbbbbh..
.hbSbbbSbbbbh.
hbbbbbbbbybbbl
bSbbbbbbbebbln
bbbbbbbltltlt.
sSbbbblrrrrr..
.sbbbblrrrrr..
..sssbltltlt..
....sssllll...
""", pal, outline=K, inner=inner)

def leg(dk):
    c = dict(pal)
    if dk:
        c.update(h=f[1], b=f[2], s=f[3], l=pal["L"])
    return part("""
    bbb
    bSb
    bbs
    bSs
    bbs
    bbs
    lll
    llL
    """, c, outline=K, inner=inner, open_top=True)
near, far = leg(False), leg(True)

def fr(bob, nb, nf, biting=False, hx=0):
    fb, ff = nf, nb
    return frame(46, 24, [
        (tail, 1, 3 + bob),
        (far, 12 + fb[0], 13 - fb[1]), (far, 28 + ff[0], 13 - ff[1]),
        (body, 7, 6 + bob),
        (near, 8 + nb[0], 13 - nb[1]), (near, 25 + nf[0], 13 - nf[1]),
        (bite if biting else head, 28 + hx, 2 + bob),
    ])

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (2, 0), (-2, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(0, (-2, 0), (2, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(0, (-1, 0), (2, 0), biting=True, hx=2),
]
sprite("tiger", frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=20, cx=20)
