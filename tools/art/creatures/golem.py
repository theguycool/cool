# Stone Golem: a hunched giant of grey stone, cracked and mossy along its back, with a small head
# thrust forward under the hump, one glowing eye under a heavy brow, a cyan crystal set in its chest,
# long arms that hang to its knees and end in great fists, and short legs like pillars. It plods with
# its fists swinging, raises both fists over its head, slams them into the ground, and hurls a rock.
K = 0x16141A
st = ramp(0x7E7A74, light=0xF0E8D8, dark=0x20203A)
mo = ramp(0x5E8A3E, light=0xE8F0B0, dark=0x1A2A30)
pal = dict(h=st[0], b=st[1], s=st[2], d=st[3], k=mix(st[3], 0x000000, 0.25),
           m=mo[1], M=mo[0], n=mo[2], c=0x5AD8D0, C=0xC8FFF8, e=0x7AF8F0, E=0xE8FFFC, r=0x8A847C, R=0x5E5A56)
inner = st[3]

TORSO = """
........mmMMm.........
.....mmMMmmMMmm.......
...hmmnmhhhmmMmh......
..hhhhbbbbbbbhhhh.....
.hhbbbbbbbbbbbbbbh....
.hbbbbbbbbbbbbbbbbh...
hhbbbbbkbbbbbbbbbbbs..
hbbbbbbbkbbbbbbbbbbs..
hbbbbbbbbkbbbbbbbbbbs.
bbbbbbbbbbbbbbbbbbbbs.
bbbbbbbbbbbbbbbbbbbbbs
bbbbbkbbbbbbbbbbbbbbbs
bbbbbbkbbbbbbbbbbcCbss
sbbbbbbbbbbbbbbbcCCcbs
sbbbbbbbbbbbbbbbbcCbss
sbbbbbbbbbbbbbbbbbbsss
ssbbbbbbbbbbbbbbbbssss
.ssbbbbbbbbbbbbbbsssd.
.sssbbbbbbbbbbbssssdd.
..sssssssssssssssddd..
...ssssdddsssssddd....
"""
HEAD = """
..hhhhh..
.hbbbbbh.
hbbbbbbbh
kkkkkkkbs
bbbbbbeEs
bbbbbbbbs
sbbkkkkks
.sssssss.
"""
LEG = """
.hbbbs..
hbbbbbs.
bbbbbbs.
bbkbbbs.
bbbbbss.
sbbbbss.
hbbbbbs.
bbbbbbs.
bbbbbbbs
"""
# an arm is three stones, each with its own line so the joints show: the upper arm, the forearm and
# the fist, laid along the arm's pose from the shoulder
UPPER = """
.hhhh.
hbbbbh
bbbbbs
bbbbbs
sbbbss
.ssss.
"""
FORE = """
.hhh.
hbbbs
bbbbs
bbbbs
sbbss
.sss.
"""
FIST = """
.hhhhh.
hbbbbbh
bbbbbbs
bbbbbks
bbbbbbs
sbbbbks
.sssss.
"""
# where the three stones go from the shoulder, for each pose
ARM_POSE = {
    "hang": ((-3, 0), (-2, 6), (-3, 11)),
    "up": ((-2, -5), (-1, -10), (-2, -17)),
    "slam": ((0, 1), (5, 5), (9, 11)),
    "throw": ((0, 2), (6, 3), (11, 2)),
}
ROCK = """
.rrrr.
rrrrrR
rrrrRR
.RRRR.
"""
DUST = """
r.....r.....r
.r...r.r...r.
"""

torso = part(TORSO, pal, outline=K, inner=inner)
head = part(HEAD, pal, outline=K, inner=inner)
far_pal = dict(pal, h=st[1], b=st[2], s=st[3], k=mix(st[3], 0x000000, 0.4), m=mo[2], M=mo[1])
leg_n = part(LEG, pal, outline=K, inner=inner, open_top=True)
leg_f = part(LEG, far_pal, outline=K, inner=inner, open_top=True)
# the arm's own lines are dark even where they cross the body, so it reads as a limb in front of it
ARM_LINE = mix(K, st[3], 0.35)
stones = {name: (part(t, pal, outline=K, inner=ARM_LINE), part(t, far_pal, outline=K, inner=ARM_LINE))
          for name, t in dict(upper=UPPER, fore=FORE, fist=FIST).items()}


def arm_layers(pose, sx, sy, far, swing=0):
    (ux, uy), (fx, fy), (kx, ky) = ARM_POSE[pose]
    i = 1 if far else 0
    return [(stones["upper"][i], sx + ux, sy + uy), (stones["fore"][i], sx + fx + swing // 2, sy + fy),
            (stones["fist"][i], sx + kx + swing, sy + ky)]


rock = part(ROCK, pal, outline=K)
dust = part(DUST, pal)

W, Hh = 48, 50
FOOT = 45


def fr(step=0, bob=0, arms="hang", swing=0):
    """step: how far the near leg is ahead (the far one is behind by as much); swing: the arms' sway"""
    tx, ty = 8, 18 + bob
    layers = []
    layers += arm_layers("hang" if arms == "throw" else arms, tx + 9, ty + 4, True, -swing)
    layers.append((leg_f, tx + 10 - step, ty + 19 - bob))
    layers.append((leg_n, tx + 4 + step, ty + 19 - bob))
    layers.append((torso, tx, ty))
    layers += arm_layers(arms, tx + 13, ty + 6, False, swing)
    layers.append((head, tx + 17, ty + 4))
    if arms == "throw":
        layers.append((rock, tx + 31, ty + 1))
    if arms == "slam":
        layers.append((dust, tx + 19, FOOT - 1))
    return frame(W, Hh, layers)


frames = [
    fr(),
    fr(2, 0, "hang", 2),
    fr(0, 1, "hang", 0),
    fr(-2, 0, "hang", -2),
    fr(0, 1, "hang", 0),
    fr(0, -1, "up"),
    fr(1, 2, "slam"),
    fr(0, 0, "throw"),
]
sprite("golem", frames, {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6], "throw": [7]}, foot=FOOT, cx=20)
