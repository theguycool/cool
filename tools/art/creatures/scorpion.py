# Scorpion: a low plated body the colour of sand, two heavy pincers held out in front, four legs a
# side, and a ringed tail arched over its back to a dark sting. Poses: standing, a four-step scuttle,
# the sting whipped forward.
K = 0x2A160C
f = ramp(0xC88A3C, light=0xFFF0B0, dark=0x40183A)
pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], S=0x8A5A22, k=0x3A1410, y=0xFF4A3A, e=0x14101A)
inner = f[3]
body = part("""
.hhShhShhShhhh..
hbbSbbSbbSbbbbh.
bbbSbbSbbSbbybbb
sbbbbbbbbbbbbbbs
.ssssssssssssss.
""", pal, outline=K, inner=inner)
tail_up = part("""
...hhhh...
..hbSbbh..
.hbb..bbh.
.bS....bS.
.bb.....bk
hb......kk
bS......k.
bb........
""", pal, outline=K, inner=inner)
tail_strike = part("""
...hhhhhhhh......
..hbSbbSbbSbh....
.hbb.......bbSh..
.bS..........bbkk
.bb............kk
hb...............
bS...............
bb...............
""", pal, outline=K, inner=inner)
claw = part("""
....hbb
hbbbb..b
..sbbbbb
....sss.
""".replace("hbbbb..b", "hbbbb..b").replace("....hbb\n", "....hbb.\n"), pal, outline=K, inner=inner)
def legs(a):
    rows_ = ["b..b..b..b", "b..b..b..b", "d..d..d..d"] if a == 0 else (["b..b..b..b", ".b..b..b..b", ".d..d..d..d"] if a == 1 else ["b..b..b..b", "b...b.b...b", "d...d.d...d"])
    w = max(len(r) for r in rows_)
    return part("\n".join(r.ljust(w, ".") for r in rows_), pal, outline=K, inner=inner, open_top=True)
L0, L1, L2 = legs(0), legs(1), legs(2)

def fr(lg, bob=0, strike=False):
    layers = [(lg, 7, 14), (tail_strike if strike else tail_up, 2, 3 + bob), (body, 4, 10 + bob), (claw, 18, 9 + bob)]
    return frame(32, 19, layers)

frames = [fr(L0), fr(L1), fr(L0, -1), fr(L2), fr(L0, -1), fr(L0, 0, True)]
sprite("scorpion", frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=16, cx=13)
