# The player, after the user's own two drawings: short black hair, tan skin, a dark red T-shirt with
# bare arms, navy trousers and dark shoes, seen from the side (moving and fighting) and from the front
# (standing at rest, and on the character screen).
#
# The look is chosen in the game: a hair style and colour, a shirt style and colour, a trouser style and
# colour, and a scarf. So the drawing is made in layers. "player" is the bare figure (bald, no shirt,
# bare legs, shoes on); each style is a picture of only what it changes, frame for frame, worked out
# here by drawing the figure with and without it ("player_hair_2", "player_shirt_1", ...). The game lays
# them on in the order trousers, shirt, scarf, hair, helmet, and swaps each one's marker colours (MARK)
# for the colour chosen (PlayerInk in the game lists the same markers: keep them alike).
from artlib import part, frame, add_outline, Grid, grade, ramp, rows, SPRITES, Sprite, sprite

K = 0x14121A

# marker colours, light to deep: never drawn as they are (the game always swaps them)
MARK = {
    "hair": [0xF00001, 0xF00002, 0xF00003, 0xF00004],
    "shirt": [0x00F001, 0x00F002, 0x00F003, 0x00F004],
    "pants": [0x0000F1, 0x0000F2, 0x0000F3, 0x0000F4],
    "shoe": [0xF0F001, 0xF0F002, 0xF0F003, 0xF0F004],
    "scarf": [0x00F0F1, 0x00F0F2, 0x00F0F3, 0x00F0F4],
    "helm": [0xF000F1, 0xF000F2, 0xF000F3, 0xF000F4],
}
# what each is shown as in previews (the game's first choices)
DEFAULT = {"hair": 0x0A0A14, "shirt": 0x4B2A31, "pants": 0x25385B, "shoe": 0x24242E, "scarf": 0xD03A3A, "helm": 0xAAB2C0}
SKIN = [grade(c) for c in (0xD9B08C, 0xC19573, 0xAD7757, 0x8A5A44)]

HAIR_STYLES = ["Short", "Spiky", "Long", "Ponytail", "Buzz", "Curly"]
SHIRT_STYLES = ["T-shirt", "Long sleeves", "Tank top", "Hoodie"]
PANTS_STYLES = ["Trousers", "Shorts", "Cropped"]


def tones(cat, far=False):
    m = MARK[cat]
    return m[1:] + [m[3]] if far else m


def skin(far=False):
    return SKIN[1:] + [SKIN[3]] if far else SKIN


def pal_for(far=False, sleeve="none", pants="none"):
    """Letters: l s d D skin; e eye; m mouth; n ear; I H J G hair; T t u U shirt; P p q Q trousers;
    O o c shoe; arms 1-3 upper arm, 4-6 forearm, 8-9 hand; legs 1-3 thigh, 4-6 knee, 7-9 shin."""
    sk = skin(far)
    hr, sh, pn, so = tones("hair", far), tones("shirt", far), tones("pants", far), tones("shoe", far)
    p = dict(l=sk[0], s=sk[1], d=sk[2], D=sk[3], e=grade(0x0A0A12), m=grade(0x6E3A3A), n=sk[3],
             I=hr[0], H=hr[1], J=hr[2], G=hr[3], T=sh[0], t=sh[1], u=sh[2], U=sh[3],
             P=pn[0], p=pn[1], q=pn[2], Q=pn[3], O=so[0], o=so[1], c=so[2])
    return p


def arm_pal(far, sleeve):
    """An arm: upper arm (1-3) and forearm (4-6) in the shirt's colours or bare, hands (8, 9) bare"""
    sk, sh = skin(far), tones("shirt", far)
    up = sh if sleeve in ("short", "long") else sk
    lo = sh if sleeve == "long" else sk
    return {"1": up[0], "2": up[1], "3": up[2], "4": lo[0], "5": lo[1], "6": lo[2], "8": sk[1], "9": sk[2]}


def leg_pal(far, pants):
    """A leg: thigh (1-3), knee (4-6), shin (7-9) in the trousers' colours or bare; shoe (O o c)"""
    sk, pn, so = skin(far), tones("pants", far), tones("shoe", far)
    cover = {"none": 0, "shorts": 1, "cropped": 2, "trousers": 3}[pants]
    out = {"O": so[0], "o": so[1], "c": so[2]}
    for band, keys in enumerate((("1", "2", "3"), ("4", "5", "6"), ("7", "8", "9"))):
        src = pn if band < cover else sk
        for k, c in zip(keys, src[:3]):
            out[k] = c
    return out


def merged(layers, outline=K, inner=None):
    """Parts drawn without lines, laid together, then one dark line round the lot (a head and its
    hair are one shape, with no line between the face and the fringe)"""
    x0 = min(x for _, x, _ in layers)
    y0 = min(y for _, _, y in layers)
    x1 = max(x + g.w for g, x, _ in layers)
    y1 = max(y + g.h for g, _, y in layers)
    g = Grid(x1 - x0 + 2, y1 - y0 + 2)
    for p, x, y in layers:
        g.put(p, x - x0 + 1, y - y0 + 1)
    before = [r[:] for r in g.px]
    add_outline(g, outline)
    g.edge = set((x, y) for y in range(g.h) for x in range(g.w) if before[y][x] is None and g.px[y][x] is not None)
    g.inner = inner
    g.m = 1
    return g, x0, y0


def flat(text, pal):
    return part(text, pal, raw=True)


# ---------------------------------------------------------------- the side view
HEAD = """
..llllll..
.llllssss.
llssssssss
lsssssssdd
sssddssdes
ssdndssses
sssddsssss
.sssssssss
..sssssssd
...dddddd.
"""
# hair: (rows, dx, dy) from the head's top left corner
HAIR = {
    0: ("""
..IIIIII..
.IHHHHHHH.
HHHHHHHHHH
HHHHHHHH..
HHHHHH....
HHHH......
HH........
.H........
""", 0, 0),
    1: ("""
..I...I.....
.IHI.IH..I..
.IHHIHHHIHI.
.HHHHHHHHHH.
HHHHHHHHHHH.
HHHHHHHHHJ..
.HHHHHHJ....
.HHHHH......
.HHH........
.HH.........
""", -1, -3),
    2: ("""
...IIIIII..
..IHHHHHHH.
.HHHHHHHHHH
HHHHHHHHHHJ
HHHHHHHH...
HHHHHJ.....
HHHHJ......
HHHJ.......
HHHJ.......
HHJJ.......
HHJ........
HJJ........
.J.........
""", -1, 0),
    3: ("""
.....IIIIII..
....IHHHHHHH.
...HHHHHHHHHH
.IHHHHHHHHHH.
IHHJHHHHHH...
HHJ.HHHH.....
HJ..HH.......
J...H........
""", -3, 0),
    4: ("""
..HHHHHH..
.HJJJJJJH.
HJJJJJJJJ.
HJJJJJJ...
HJJJ......
HJ........
""", 0, 0),
    5: ("""
...IIIII....
..IHHHHHHI..
.IHHHHHHHHH.
IHHHHHHHHHHJ
HHHHHHHHHHJ.
HHHHHHHHJ...
HHHHHHJ.....
HHHHHJ......
HHHHJ.......
.HHJ........
..J.........
""", -1, -2),
}
NECK = "sdd"

TORSO = {
    "none": """
.lsssss.
lssssssd
lssssssd
ssssssdd
ssssssdd
dssssssD
dssssssD
ddssssDD
""",
    "tee": """
.TTtttt.
TTtttttu
Ttttttuu
ttttttuu
ttttttuu
utttttuU
utttttuU
uuttttUU
""",
    "tank": """
.lltttl.
lsTtttsd
Ttttttuu
ttttttuu
ttttttuu
utttttuU
utttttuU
uuttttUU
""",
    "hoodie": """
.TTtttt.
TTttTttu
TtttTtuu
tttttuuu
ttUUUUuu
utUtttuU
utUUUUuU
UUUUUUUU
""",
}
HOOD = """
.Ttt.
Tttuu
ttuuU
.uuU.
"""
SHIRT_SET = {0: ("tee", "short", False), 1: ("tee", "long", False), 2: ("tank", "none", False), 3: ("hoodie", "long", True)}
HIPS = {"none": "lssssd\nlsssdd", "pants": "Pppppq\nPppqqq"}

ARMS = {
    "rest": """
123
223
223
233
456
456
556
.89
""",
    "swing_f": """
123...
2233..
.2346.
..4556
...456
....89
""",
    "swing_b": """
..123
.2233
4563.
456..
556..
89...
""",
    "back": """
..89
.456
4563
233.
223.
""",
    "fwd": """
123....
2234455
.33566689
""",
    "guard": """
....89
...456
12356.
223...
.33...
""",
}
# (fwd's last row is a little longer: the fist)
ARMS["fwd"] = """
123......
223445589
.33556699
"""

LEGS = {
    "stand": """
1123.
1223.
1223.
.456.
.456.
.556.
.789.
.789.
oOOc.
ooooc
""",
    "fwd": """
1123...
11223..
.1223..
..4566.
..4556.
...456.
...789.
...789.
...oOOc
...oooc
""",
    "back": """
..1123.
..1223.
.1223..
.4566..
4556...
456....
789....
789....
oOOc...
oooc...
""",
    "lift": """
1123.
1223.
11223
.4556
..456
..456
..789
.oOOc
.oooc
.....
""",
}
LDX = dict(stand=0, fwd=0, back=-2, lift=0)

SCARF_S = """
.yYYYYy..
zyyyyyyy.
zz.zzzz..
z........
"""
HELM_S = """
..MMMMMM..
.MiiiiiiA.
MiiiiiiiiA
MiiiiiiAA.
iiiiiAA...
iiiiAA....
iAA.......
"""

W, Hh = 32, 38
AT = dict(head=(11, 4), torso=(12, 15), hips=(13, 22), near_leg=(12, 24), far_leg=(15, 24))


def wear_pal(cat):
    m = MARK[cat]
    if cat == "scarf":
        return dict(Y=m[0], y=m[1], z=m[2], Z=m[3])
    return dict(M=m[0], i=m[1], A=m[2], a=m[3])


def side(near, farl, bob, lean, arm, look, extra=None):
    """One side frame. look: hair (style or None), shirt (style or None), pants (style or None),
    scarf and helm (True or False). `extra` (for other people drawn on this figure, like the pirates)
    is called with (tx, ty, hx, hy, arm), where the torso and head go, and gives parts to add: a dict
    of "back" (behind everything), "head" (over the head), "hand" (under the near arm, so the fist
    closes round a grip) and "front" (over everything), each a list of (part, x, y)."""
    add = extra(AT["torso"][0] + lean // 2, AT["torso"][1] + bob, AT["head"][0] + lean, AT["head"][1] + bob, arm) if extra else {}
    hair, shirt, pants = look.get("hair"), look.get("shirt"), look.get("pants")
    torso_key, sleeve, hood = SHIRT_SET[shirt] if shirt is not None else ("none", "none", False)
    pants_key = PANTS_STYLES[pants].lower() if pants is not None else "none"
    tx, ty = AT["torso"][0] + lean // 2, AT["torso"][1] + bob
    hx, hy = AT["head"][0] + lean, AT["head"][1] + bob
    near_p, far_p = pal_for(False), pal_for(True)
    shirt_inner = MARK["shirt"][3] if torso_key != "none" else SKIN[3]
    layers = list(add.get("back", []))

    def arm_part(name, far):
        inner = tones("shirt", far)[3] if sleeve != "none" else skin(far)[3]
        return part(ARMS[name], arm_pal(far, sleeve), outline=K, inner=inner, raw=True)

    def leg_part(name, far):
        inner = tones("pants", far)[3] if pants_key != "none" else skin(far)[3]
        return part(LEGS[name], leg_pal(far, pants_key), outline=K, inner=inner, raw=True, open_top=True)

    far_arm = {"rest": ("rest", 5, 1), "swing_f": ("rest", 4, 1), "swing_b": ("rest", 6, 1), "back": ("rest", 5, 1),
               "fwd": ("rest", 5, 1), "guard": ("rest", 5, 1), "aim": ("fwd", 5, 0)}[arm]
    near_arm = {"rest": ("rest", 2, 1), "swing_f": ("swing_f", 2, 1), "swing_b": ("swing_b", -1, 1), "back": ("back", -3, -1),
                "fwd": ("fwd", 3, 1), "guard": ("guard", 3, -2), "aim": ("fwd", 3, 1)}[arm]
    layers.append((arm_part(far_arm[0], True), tx + far_arm[1], ty + far_arm[2]))
    layers.append((leg_part(farl, True), AT["far_leg"][0] + LDX[farl], AT["far_leg"][1]))
    layers.append((leg_part(near, False), AT["near_leg"][0] + LDX[near], AT["near_leg"][1]))
    hip_key = "pants" if pants_key != "none" else "none"
    layers.append((part(HIPS[hip_key], near_p, outline=K, inner=MARK["pants"][3] if hip_key == "pants" else SKIN[3], raw=True), AT["hips"][0], AT["hips"][1] + bob))
    layers.append((part(TORSO[torso_key], near_p, outline=K, inner=shirt_inner, raw=True), tx, ty))
    layers.append((part(NECK, near_p, outline=K, inner=SKIN[3], raw=True), tx + 3, ty - 1))
    if hood:
        layers.append((part(HOOD, near_p, outline=K, inner=MARK["shirt"][3], raw=True), tx - 2, ty - 3))
    if look.get("scarf"):
        layers.append((part(SCARF_S, wear_pal("scarf"), outline=K, inner=MARK["scarf"][3], raw=True), hx - 1, hy + 9))
    head_layers = [(flat(HEAD, near_p), 0, 0)]
    if hair is not None:
        text, dx, dy = HAIR[hair]
        head_layers.append((flat(text, near_p), dx, dy))
    hg, ox, oy = merged(head_layers, K, SKIN[3])
    layers.append((hg, hx + ox, hy + oy))
    if look.get("helm"):
        layers.append((part(HELM_S, wear_pal("helm"), outline=K, inner=MARK["helm"][3], raw=True), hx, hy))
    layers += add.get("head", [])
    layers += add.get("hand", [])
    layers.append((arm_part(near_arm[0], False), tx + near_arm[1], ty + near_arm[2]))
    layers += add.get("front", [])
    return frame(W, Hh, layers)


# where each pose of the near arm puts the fist, from the torso's corner (other figures hold things there)
NEAR_ARM = {"rest": ("rest", 2, 1), "swing_f": ("swing_f", 2, 1), "swing_b": ("swing_b", -1, 1), "back": ("back", -3, -1),
            "fwd": ("fwd", 3, 1), "guard": ("guard", 3, -2), "aim": ("fwd", 3, 1)}


def fist(arm):
    """The fist's first pixel (its top left) for a pose of the near arm, from the torso's corner"""
    name, dx, dy = NEAR_ARM[arm]
    rs = rows(ARMS[name])
    for r, row in enumerate(rs):
        for c, ch in enumerate(row):
            if ch in "89":
                return dx + c, dy + r
    return dx, dy


# ---------------------------------------------------------------- the front view
HEAD_F = """
.llllllll.
llllssssss
lsssssssss
lsssssssss
dssssssssd
dsessssesd
dsessssesd
ssssssssss
dsssmmsssd
.dssssssd.
"""
HAIR_F = {
    0: ("""
.IIIIIIII.
IHHHHHHHHH
HHHHHHHHHH
H........H
H........H
""", 0, 0),
    1: ("""
.I...I...I..
.HI.IHI.IHI.
.HHIHHHIHHH.
IHHHHHHHHHHI
HHHHHHHHHHHH
.H........H.
""", -1, -3),
    2: ("""
..IIIIIIII..
.IHHHHHHHHH.
.HHHHHHHHHH.
HHHHHHHHHHHH
HH........HH
HH........HH
HH........HH
HJ........JH
HJ........JH
J..........J
""", -1, 0),
    3: ("""
.IIIIIIII.
IHHHHHHHHH
HHHHHHHHHH
H........H
""", 0, 0),
    4: ("""
.HHHHHHHH.
HJJJJJJJJH
J........J
""", 0, 0),
    5: ("""
...IIIIII...
.IIHHHHHHII.
IHHHHHHHHHHI
HHHHHHHHHHHH
HHHHHHHHHHHH
HH........HH
H..........H
""", -1, -2),
}
BODY_F = {
    # shirt body, with the arms down the sides: upper arm rows 0-4, forearm 5-7, hands 8-9
    "none": """
..lsssssssss..
lsssssssssssdd
lsssssssssssdd
12ssssssssssd1
12ssssssssssd1
45sssssssssd45
45dsssssssdd45
55dddddddddd56
89..........89
89..........89
""",
    "tee": """
..TTtttttttt..
TTttttttttttuu
TttttttttttUuu
12UttttttttU12
12UttttttttU12
45UuttttttuU45
45UuuttttuuU45
55UuuuuuuuuU56
89.uuuuuuuu.89
89..........89
""",
    "tank": """
..lsttttttsl..
lsTttttttttsdd
lTtttttttttUdd
12UttttttttU12
12UttttttttU12
45UuttttttuU45
45UuuttttuuU45
55UuuuuuuuuU56
89.uuuuuuuu.89
89..........89
""",
    "hoodie": """
..TTtttttttt..
TTttTttttTttuu
TtttTttttTtUuu
12UttttttttU12
12UttUUUUttU12
45UutUttUtuU45
45UuuUUUUuuU45
55UUUUUUUUUU56
89.UUUUUUUU.89
89..........89
""",
}
HOOD_F = """
.TttttT.
TtuuuutT
"""
LEGS_F = {
    "body": """
1122222211
1122332211
1123..3211
4456..6544
4456..6544
4556..6554
7789..9877
7789..9877
OOoc..cooO
oooc..cooo
""",
}
SCARF_F = """
.yYYYYYYy.
..zyyyyz..
....yz....
....yz....
"""
HELM_F = """
.MMMMMMMM.
MiiiiiiiiA
MiiiiiiiiA
iiAAAAAAii
iA......Ai
"""


def front(look):
    hair, shirt, pants = look.get("hair"), look.get("shirt"), look.get("pants")
    torso_key, sleeve, hood = SHIRT_SET[shirt] if shirt is not None else ("none", "none", False)
    pants_key = PANTS_STYLES[pants].lower() if pants is not None else "none"
    p = pal_for(False)
    bp = dict(p)
    bp.update(arm_pal(False, sleeve))
    lp = dict(p)
    lp.update(leg_pal(False, pants_key))
    layers = [
        (part(LEGS_F["body"], lp, outline=K, inner=MARK["pants"][3] if pants_key != "none" else SKIN[3], raw=True, open_top=True), 11, 24),
        (part("ssdd", p, outline=K, inner=SKIN[3], raw=True), 14, 14),
        (part(BODY_F[torso_key], bp, outline=K, inner=MARK["shirt"][3] if torso_key != "none" else SKIN[3], raw=True), 9, 15),
    ]
    if hood:
        layers.append((part(HOOD_F, p, outline=K, inner=MARK["shirt"][3], raw=True), 12, 13))
    if look.get("scarf"):
        layers.append((part(SCARF_F, wear_pal("scarf"), outline=K, inner=MARK["scarf"][3], raw=True), 11, 13))
    head_layers = [(flat(HEAD_F, p), 0, 0)]
    if hair is not None:
        text, dx, dy = HAIR_F[hair]
        head_layers.append((flat(text, p), dx, dy))
    hg, ox, oy = merged(head_layers, K, SKIN[3])
    layers.append((hg, 11 + ox, 4 + oy))
    if look.get("helm"):
        layers.append((part(HELM_F, wear_pal("helm"), outline=K, inner=MARK["helm"][3], raw=True), 11, 4))
    return frame(W, Hh, layers)


# ---------------------------------------------------------------- frames, base and layers
SIDE = [
    ("stand", "stand", 0, 0, "rest"),
    ("fwd", "back", 0, 0, "swing_b"),
    ("stand", "lift", 1, 0, "rest"),
    ("back", "fwd", 0, 0, "swing_f"),
    ("lift", "stand", 1, 0, "rest"),
    ("stand", "back", 0, -1, "back"),
    ("fwd", "back", 1, 1, "fwd"),
    ("stand", "stand", 0, 0, "guard"),
    ("stand", "back", 0, 0, "aim"),
]
POSES = {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6], "block": [7], "shoot": [8], "front": [9]}
FOOT, CX = 33, 16


def frames_for(look):
    return [side(*f, look) for f in SIDE] + [front(look)]


def diff(a, b):
    """What `a` has that differs from `b`, the rest clear"""
    g = Grid(a.w, a.h)
    for y in range(a.h):
        for x in range(a.w):
            if a.px[y][x] != b.px[y][x]:
                g.px[y][x] = a.px[y][x]
    return g


BASE = frames_for({})
sprite("player", BASE, POSES, foot=FOOT, cx=CX)
LAYERS = []
for cat, styles in (("pants", range(len(PANTS_STYLES))), ("shirt", range(len(SHIRT_STYLES))), ("hair", range(len(HAIR_STYLES)))):
    for s in styles:
        fr = frames_for({cat: s})
        sprite("player_%s_%d" % (cat, s), [diff(a, b) for a, b in zip(fr, BASE)], POSES, foot=FOOT, cx=CX)
for cat in ("scarf", "helm"):
    fr = frames_for({cat: True})
    sprite("player_" + cat, [diff(a, b) for a, b in zip(fr, BASE)], POSES, foot=FOOT, cx=CX)


def dressed(look):
    """The figure as the game lays it together: base, then trousers, shirt, scarf, hair, helmet"""
    out = []
    for i, b in enumerate(BASE):
        g = b.copy()
        for name in (("player_pants_%d" % look["pants"]) if look.get("pants") is not None else None,
                     ("player_shirt_%d" % look["shirt"]) if look.get("shirt") is not None else None,
                     "player_scarf" if look.get("scarf") else None,
                     ("player_hair_%d" % look["hair"]) if look.get("hair") is not None else None,
                     "player_helm" if look.get("helm") else None):
            if name:
                g.put(SPRITES[name].frames[i])
        out.append(g)
    return out


def check_layers():
    """Laying the layers together must give the same picture as drawing the figure whole"""
    bad = []
    for look in ({"hair": 0, "shirt": 0, "pants": 0}, {"hair": 2, "shirt": 3, "pants": 1, "scarf": True},
                 {"hair": 5, "shirt": 2, "pants": 2, "helm": True}, {"hair": 3, "shirt": 1, "pants": 0, "scarf": True, "helm": True}):
        whole = frames_for(look)
        laid = dressed(look)
        for i, (a, b) in enumerate(zip(whole, laid)):
            n = sum(1 for y in range(a.h) for x in range(a.w) if a.px[y][x] != b.px[y][x])
            # a few outline pixels may take the softer inner shade in one and the hard line in the
            # other where a scarf, a hood and long hair all meet; more than that is a real mistake
            if n > 8:
                bad.append((look, i, n))
    return bad


_bad = check_layers()
if _bad:
    print("player layers differ from the whole figure:", _bad[:6])
