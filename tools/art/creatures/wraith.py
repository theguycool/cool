# Wraith: an empty hooded cloak that drifts above the ground, two yellow lights where a face would
# be, a tattered hem, and a pale clawed hand that reaches out when it strikes.
K = 0x120A1E
c = ramp(0x5A3A8A, light=0xE8D0FF, dark=0x10082A)
pal = dict(h=c[0], p=c[1], s=c[2], d=c[3], k=0x0E0816, y=0xFFE040, Y=0xFFF8B0, b=0xD8D4E8, B=0x9A94B4)
CLOAK_A = """
....hhhhhh......
..hhppppppph....
.hppppppppppp...
.hppkkkkkkppp...
hpppkkkkkYkppp..
hpppkykkkykppp..
hppppkkkkkpppps.
.pppppkkkpppppss
.ppppppppppppps.
hpppppppppppppss
hppppppppppppps.
pppppppppppppps.
ppppppppppppppss
pppppppppppppps.
spppppppppppppss
spppppppppppppss
.sppppppppppppss
.spppppppppppss.
.spp.ppppp.ppss.
..sp..ppp..pss..
..s...sps...s...
......s.........
"""
CLOAK_B = """
....hhhhhh......
..hhppppppph....
.hppppppppppp...
.hppkkkkkkppp...
hpppkkkkkYkppp..
hpppkykkkykppp..
hppppkkkkkpppps.
.pppppkkkpppppss
.ppppppppppppps.
hpppppppppppppss
hppppppppppppps.
pppppppppppppps.
ppppppppppppppss
pppppppppppppps.
spppppppppppppss
spppppppppppppss
.sppppppppppppss
.sppppppppppppss
..spp.ppppp.pss.
..sp...ppp..ps..
...s...sp....s..
........s.......
"""
a = part(CLOAK_A, pal, outline=K, inner=c[3])
b = part(CLOAK_B, pal, outline=K, inner=c[3])
arm = part("""
hppp.....
ppppppbb.
sppppbbBb
.sss..b.b
""", pal, outline=K, inner=c[3])
arm_far = part("""
pppp.....
ssssssBB.
.ssssBBBB
......B.B
""", pal, outline=K, inner=c[3])
W, H = 28, 28
frames = [
    frame(W, H, [(a, 5, 2)]),
    frame(W, H, [(b, 5, 3)]),
    frame(W, H, [(arm_far, 15, 9), (a, 6, 2), (arm, 14, 11)]),
]
sprite("wraith", frames, {"idle": [0], "fly": [0, 1], "strike": [2]}, foot=24, cx=13)
