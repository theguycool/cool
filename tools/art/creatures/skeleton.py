# Skeleton Knight: a skull under an iron helm with a pale light in its socket, a ribcage, thin limb
# bones with knobbly joints, iron boots, a round wooden shield on its back arm and a knight's sword:
# a two-pixel blade with a bright edge, a gold crossguard, a leather grip and a pommel. It walks with
# the sword held upright at the ready, raises it over its shoulder to wind up, and cuts forward with
# a swish in the air; it can also crouch behind its shield.
K = 0x16141C
bone = [0xFBF7E8, 0xE8E0CA, 0xBEB49E, 0x8A7E74]
iron = [0xDDE3EC, 0xAAB2C0, 0x7C8494, 0x555C6C]
wood = [0xB88A50, 0x8E6034, 0x6A4424, 0x48301C]
pal = dict(l=bone[0], b=bone[1], B=bone[2], D=bone[3], k=0x2A2632, g=0x8AF0FF, t=0xFFFFF4,
           I=iron[0], i=iron[1], A=iron[2], a=iron[3],
           W=wood[0], w=wood[1], v=wood[2], V=wood[3],
           S=0xF4F7FC, s=0xB4BCCA, e=0x7A8294, y=0xE8C050, Y=0xA87828, h=0x6A4220, H=0x8A5A30)
far = dict(pal)
far.update(l=bone[1], b=bone[2], B=bone[3], I=iron[1], i=iron[2], A=iron[3])

head = part("""
...IIIII...
.IIiiiiiii.
IIiiiiiiiiA
AaaaaaaaaaA
.lbbbbbbbbb
.lbbbkkkbbb
.bbbkkkgkbb
.bbbbkkkbkb
.Bbbbbbbbbb
..BbbtktktB
..kkkkkkkk.
...BbtktktB
....BBBBBB.
""", pal, outline=K, inner=bone[3])

torso = part("""
.llbbbbb.
lbkkkkkbb
.lbbbbbbb
.bkkkkkkB
.lbbbbbbb
.bkkkkkkB
.lbbbbbb.
..kbBkk..
.lbbbbb..
""", pal, outline=K, inner=bone[3])

def leg(text, pl):
    return part(text, pl, outline=K, inner=bone[3], open_top=True)

LEGS = {
    "stand": """
.lb..
.bB..
.bB..
.lbb.
.bB..
.bB..
.bB..
.IiA.
IiiiA
""",
    "fwd": """
.lb....
..bB...
..bB...
...lbb.
...bB..
....bB.
....bB.
...IiiA
...IiiA
""",
    "back": """
...lb..
..bB...
..bB...
.lbb...
.bB....
bB.....
bB.....
IiA....
IiiA...
""",
    "lift": """
.lb...
..bB..
...bB.
...lbb
...bB.
...bB.
..IiA.
..IiiA
......
""",
}
L = {k: (leg(v, pal), leg(v, far)) for k, v in LEGS.items()}
LDX = dict(stand=0, fwd=0, back=-2, lift=0)

# arms: an upper arm, an elbow and a forearm, each pose ending in a fist where the grip goes
arm_far = part("""
lb
bB
bB
lb
bB
bB
lb
""", far, outline=K, inner=bone[3])
# at the ready: the forearm held out in front, the fist well forward of the face
arm_ready = part("""
lb.....
bB.....
bB.....
lbbbbbl
.BBBBBB
""", pal, outline=K, inner=bone[3])
# wound up: the arm raised over the shoulder, the fist above and behind the head
arm_up = part("""
lb...
bBl..
.bBl.
..bBl
...bB
""", pal, outline=K, inner=bone[3])
arm_cut = part("""
lbblbbl
BBBBBBb
""", pal, outline=K, inner=bone[3])
arm_guard = part("""
...lb
..bB.
lbbB.
bB...
""", pal, outline=K, inner=bone[3])

# the sword: upright (at the ready), slanting back behind the head (wound up), level (the cut)
sword_up = part("""
.S.
.Ss
.Ss
.Ss
.Ss
.Ss
.Ss
.Ss
.Ss
.Ss
Yyy
.hH
.hH
.y.
""", pal, outline=K)
sword_back = part("""
......yH...
.....hYy...
....SyhY...
...SsY.....
..Ss.......
.Ss........
Ss.........
s..........
""", pal, outline=K)
sword_cut = part("""
.............
..Ysssssssss.
yhhySSSSSSSSS
..Y..........
""", pal, outline=K)
swish = part("""
....SSS....
......SS...
.......sS..
........sS.
.........s.
""", dict(S=0xE8EEF8, s=0xA8B4C8))

shield = part("""
.AiiiA.
AWWwwwA
iWwwwwA
iwwIiva
iwwiAva
iwwwvva
AwvvvvA
.AvvvA.
..AAA..
""", pal, outline=K)
shield_back = part("""
Ai.
iW.
iw.
iw.
iw.
Aw.
.A.
""", pal, outline=K)

W, Hh = 42, 42
AT = dict(head=(13, 6), torso=(14, 19), near_leg=(14, 28), far_leg=(17, 28))

def fr(near, farl, bob=0, lean=0, arm="ready", sway=0):
    tx, ty = AT["torso"][0] + lean // 2, AT["torso"][1] + bob
    hx, hy = AT["head"][0] + lean, AT["head"][1] + bob
    layers = []
    if arm != "guard":
        layers.append((shield_back, tx - 3, ty + 1))
    if arm == "up":
        # the blade slants down behind the head, which covers part of it
        layers.append((sword_back, tx - 9, ty - 17))
    if arm == "guard":
        # held back while the shield takes the blow: only the blade shows over the shoulder
        layers.append((sword_up, tx - 1, ty - 12))
    layers.append((arm_far, tx + 5 - sway, ty + 1))
    layers.append((L[farl][1], AT["far_leg"][0] + LDX[farl], AT["far_leg"][1]))
    layers.append((L[near][0], AT["near_leg"][0] + LDX[near], AT["near_leg"][1]))
    layers.append((torso, tx, ty))
    layers.append((head, hx, hy))
    if arm == "ready":
        layers += [(arm_ready, tx + 4 + sway, ty + 1), (sword_up, tx + 10 + sway, ty - 9)]
    elif arm == "up":
        layers += [(arm_up, tx - 1, ty - 13)]
    elif arm == "cut":
        layers += [(swish, tx + 9, ty - 6), (arm_cut, tx + 4, ty + 2), (sword_cut, tx + 9, ty + 1)]
    elif arm == "guard":
        layers += [(arm_guard, tx + 4, ty + 0), (shield, tx + 7, ty - 2)]
    return frame(W, Hh, layers)

frames = [
    fr("stand", "stand"),
    fr("fwd", "back", 0, 0, "ready", 1),
    fr("stand", "lift", 1, 0, "ready", 0),
    fr("back", "fwd", 0, 0, "ready", -1),
    fr("lift", "stand", 1, 0, "ready", 0),
    fr("stand", "back", 0, -1, "up"),
    fr("fwd", "back", 1, 2, "cut"),
    fr("stand", "stand", 0, 0, "guard"),
]
sprite("skeleton", frames, {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6], "block": [7], "shoot": [6]}, foot=36, cx=18)
