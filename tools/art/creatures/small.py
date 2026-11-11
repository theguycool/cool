# Small animals: the cat (a tabby with pricked ears, green eyes and a tail held high), the frog
# (squat and green with eyes on top, legs thrown out when it leaps) and the fish (a blue darter
# with a forked tail that flicks).

# ---- cat ----
K = 0x22140E
f = ramp(0xE8983A, light=0xFFF0C0, dark=0x40183A)
cat = dict(h=f[0], b=f[1], s=f[2], d=f[3], S=0xB86820, l=0xF8E6C4, L=0xD8C09C, y=0x7ADC5A, e=0x14101A, n=0xF08A9A, w=0xFFFFFF)
cat_body = part("""
.hhhhhhhhhh.
hbbSbbSbbSbh
bbbSbbSbbSbb
sbbbbbbbbbbs
.sllllllLs..
""", cat, outline=K, inner=f[3])
cat_tail = part("""
.bh
bh.
b..
b..
bS.
.bb
""", cat, outline=K, inner=f[3])
cat_head = part("""
b.....b.
bb...bbh
bbhhhbbb
bSbSbbSb
bybbbybb
bebbbebb
.bbnbbb.
..llll..
""", cat, outline=K, inner=f[3])
def cat_leg(dk):
    c = dict(cat)
    if dk:
        c.update(b=f[2], l=cat["L"])
    return part("""
    bb
    bb
    bb
    ll
    """, c, outline=K, inner=f[3], open_top=True)
cn, cf = cat_leg(False), cat_leg(True)
def cat_fr(bob, nb, nf):
    fb, ff = nf, nb
    return frame(24, 17, [
        (cat_tail, 1, 2 + bob),
        (cf, 6 + fb[0], 11 - fb[1]), (cf, 13 + ff[0], 11 - ff[1]),
        (cat_body, 3, 7 + bob),
        (cn, 4 + nb[0], 11 - nb[1]), (cn, 11 + nf[0], 11 - nf[1]),
        (cat_head, 13, 1 + bob),
    ])
sprite("cat", [cat_fr(0, (0, 0), (0, 0)), cat_fr(0, (1, 0), (-1, 0)), cat_fr(-1, (0, 0), (0, 1)), cat_fr(0, (-1, 0), (1, 0)), cat_fr(-1, (0, 1), (0, 0))],
       {"idle": [0], "walk": [1, 2, 3, 4]}, foot=14, cx=10.5)

# ---- frog ----
FK = 0x10301E
g = ramp(0x58B84A, light=0xF0FFB0, dark=0x103A4A)
frog = dict(h=g[0], b=g[1], s=g[2], d=g[3], l=0xE8F0B0, w=0xFFFFFF, e=0x14101A, m=0x2A5A30)
frog_sit = part("""
..ww....ww..
.wewb..bwew.
.bbbbhhbbbb.
bbbbbbbbbbbb
bmmmmmmmmmmb
sbllllllllbs
ssb.llll.bss
dd........dd
""", frog, outline=FK, inner=g[3])
frog_leap = part("""
......ww....ww..
.....wewb..bwew.
....hbbbhhbbbbb.
..hbbbbbbbbbbbbb
.sbbbbmmmmmmmmb.
sbb.sbllllllbs..
bb...sb....bb...
d.....d.....d...
""", frog, outline=FK, inner=g[3])
sprite("frog", [frame(20, 13, [(frog_sit, 4, 3)]), frame(20, 13, [(frog_leap, 2, 1)])], {"idle": [0], "hop": [1]}, foot=10, cx=10)

# ---- fish ----
WK = 0x0E1E3A
fb_ = ramp(0x4A9AE0, light=0xE0F8FF, dark=0x101A4A)
fish = dict(h=fb_[0], b=fb_[1], s=fb_[2], d=fb_[3], l=0xDCEEFF, y=0xFFD84A, w=0xFFFFFF, e=0x14101A)
fish_a = part("""
d....hhhhh....
dd.hhbbbbbbh..
sdbbbbbbbbwebh
sdbbyybbbbbbbs
dd.sllllllls..
d....sssss....
""", fish, outline=WK, inner=fb_[3])
fish_b = part("""
.....hhhhh....
.d.hhbbbbbbh..
dsbbbbbbbbwebh
dsbbyybbbbbbbs
.d.sllllllls..
.....sssss....
""", fish, outline=WK, inner=fb_[3])
sprite("fish", [frame(18, 10, [(fish_a, 2, 2)]), frame(18, 10, [(fish_b, 2, 2)])], {"idle": [0], "fly": [0, 1]}, foot=8, cx=9)
