# Pirates, drawn on the player's own figure so every person in the game has the same build: the same
# head, arms, legs and poses, dressed differently. The deckhand wears a red bandana, an eye patch and a
# striped shirt and fights with a cutlass; the gunner wears blue and carries a flintlock pistol; the
# captain wears a tricorn hat with a gold edge, a long red coat with brass buttons and a black beard.
# Swordsmen walk with the cutlass in hand, raise it over the shoulder to wind up, cut forward with a
# swish in the air, and hold it across their face to parry. The gunner aims, then fires with a flash.
import player
from player import side, fist, MARK, SKIN, K

STEEL = dict(S=0xE8ECF2, s=0xA8B0BE, e=0x6A7284, y=0xE0B048, Y=0x9A7028, h=0x5A3A22, H=0x7A5232)
GUNPAL = dict(STEEL, o=0x4A4E58, O=0x2A2C34, w=0x8A5A30, W=0x6A4224, f=0xFFF2A0, F=0xFFB040, R=0xE85A20)


def tone_map(colors):
    """The figure's marker colours swapped for graded ramps of the chosen ones"""
    m = {}
    for cat, c in colors.items():
        for mk, t in zip(MARK[cat], [grade(x) for x in ramp(c)]):
            m[mk] = t
    return m


def cloth(c):
    r = [grade(x) for x in ramp(c)]
    return dict(b=r[0], B=r[1], r=r[2], k=r[2], q=r[3])


# ---- what goes on the head (head pixel (c, r) is at hx + c, hy + r; the eye is at (8, 4)) ----
BANDANA = """
.....bbbbBB..
....bbBBBBBB.
..krBBBBBBBBr
.kqrBBBBrrr..
kq.rBBBr.....
kq..rrr......
.k...........
"""
PATCH = """
qq..
..qq
..qq
"""
MUSTACHE = """
qqq
"""
BEARD = """
...qq.
..qqqq
qqqqqq
.qqqq.
..qq..
"""
TRICORN = """
....bbbbb.....
..bbBBBBBBb...
y.BBBBBBBBBB.y
yBBBBBBBBBBBBy
.yyyyyyyyyyyy.
"""
# a long coat's tails: behind the legs, and the front panel over the near thigh
TAIL_BACK = """
BBBr
BBBr
BBrr
Brrq
Brq.
rq..
"""
TAIL_FRONT = """
bBr
BBr
BBr
Brq
"""
BELT = """
qqqyqq
"""

# ---- the cutlass, each pose with the fist's place in the drawing (the fist closes over the grip) ----
CUT_LOW = ("""
h....
hh...
.yY..
.ySs.
..Ss.
..sS.
...Ss
...sS
....s
""", 0, 1)
CUT_BACK = ("""
S......
sS.....
.sS....
..sS...
...sSy.
....yhh
.....h.
""", 5, 5)
CUT_FWD = ("""
.y..........
hhySSSSSSSs.
hhysssssssSS
.Y..........
""", 0, 1)
CUT_GUARD = ("""
......Ss
.....Ss.
....Ss..
...Ss...
..yy....
.hhY....
.h......
""", 1, 5)
SWISH = """
SSSS........
....SSS.....
.......SS...
.........Ss.
..........s.
"""
# the pistol: low in the hand, levelled, and levelled with the flash of the shot
GUN_LOW = ("""
hh.
.oo
.oo
..o
..O
""", 0, 0)
GUN_AIM = ("""
.oooooO
hhwo...
hhW....
""", 0, 1)
FLASH = """
.f.
ffF
FfR
.F.
"""


def piece(spec, pal, x, y):
    """A held thing laid so its grip sits under the fist at (x, y)"""
    text, gx, gy = spec
    return (part(text, pal, outline=K), x - gx, y - gy)


def make(name, look, colors, head_parts, stripes=None, coat=None, frames_spec=None, poses=None):
    def extra(tx, ty, hx, hy, arm, weapon):
        add = {"back": [], "head": [], "hand": [], "front": []}
        fx, fy = fist(arm)
        fx, fy = tx + fx, ty + fy
        for text, pal, dx, dy, lined in head_parts:
            add["head"].append((part(text, pal, outline=K if lined else None, inner=SKIN[3]), hx + dx, hy + dy))
        if coat:
            add["back"].append((part(TAIL_BACK, coat, outline=K, inner=coat["q"]), tx - 1, ty + 8))
            add["head"].append((part(TAIL_FRONT, coat, outline=K, inner=coat["q"]), tx + 5, ty + 8))
        else:
            add["head"].append((part(BELT, dict(q=0x3A2A20, y=0xE0B048)), tx + 1, ty + 7))
        if weapon == "cutlass":
            if arm == "back":
                add["back"].append(piece(CUT_BACK, STEEL, fx, fy))
            elif arm == "fwd":
                add["back"].append((part(SWISH, dict(S=0xE8EEF8, s=0xA8B4C8)), fx, fy - 5))
                add["hand"].append(piece(CUT_FWD, STEEL, fx, fy))
            elif arm == "guard":
                add["hand"].append(piece(CUT_GUARD, STEEL, fx, fy))
            else:
                add["hand"].append(piece(CUT_LOW, STEEL, fx, fy))
        elif weapon in ("pistol", "fire"):
            if arm == "aim":
                add["hand"].append(piece(GUN_AIM, GUNPAL, fx, fy))
                if weapon == "fire":
                    add["front"].append((part(FLASH, GUNPAL), fx + 7, fy - 2))
            else:
                add["hand"].append(piece(GUN_LOW, GUNPAL, fx, fy))
        return add

    swap = tone_map(colors)
    frames = []
    for near, farl, bob, lean, arm, weapon in frames_spec:
        g = side(near, farl, bob, lean, arm, look,
                 extra=lambda tx, ty, hx, hy, a, w=weapon: extra(tx, ty, hx, hy, a, w))
        if stripes:
            # every other row of the shirt (the torso's rows, whatever the pose) in the stripe's colour
            ty = player.AT["torso"][1] + bob
            sr = [grade(x) for x in ramp(stripes)]
            for y in range(g.h):
                if (y - ty) % 2 == 1:
                    for x in range(g.w):
                        c = g.px[y][x]
                        if c in MARK["shirt"]:
                            g.px[y][x] = sr[MARK["shirt"].index(c)]
        frames.append(g.recolor(swap))
    sprite(name, frames, poses, foot=player.FOOT, cx=player.CX)


SWORDSMAN = [
    ("stand", "stand", 0, 0, "rest", "cutlass"),
    ("fwd", "back", 0, 0, "swing_b", "cutlass"),
    ("stand", "lift", 1, 0, "rest", "cutlass"),
    ("back", "fwd", 0, 0, "swing_f", "cutlass"),
    ("lift", "stand", 1, 0, "rest", "cutlass"),
    ("stand", "back", 0, -1, "back", "cutlass"),
    ("fwd", "back", 1, 1, "fwd", "cutlass"),
    ("stand", "stand", 0, 0, "guard", "cutlass"),
]
SWORD_POSES = {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6], "block": [7]}
GUNNER = [
    ("stand", "stand", 0, 0, "rest", "pistol"),
    ("fwd", "back", 0, 0, "swing_b", "pistol"),
    ("stand", "lift", 1, 0, "rest", "pistol"),
    ("back", "fwd", 0, 0, "swing_f", "pistol"),
    ("lift", "stand", 1, 0, "rest", "pistol"),
    ("stand", "back", 0, 0, "aim", "pistol"),
    ("stand", "back", 0, -1, "aim", "fire"),
]
GUN_POSES = {"idle": [0], "walk": [1, 2, 3, 4], "shoot": [5], "fire": [6], "strike": [6]}

red = cloth(0xB83A34)
blue = cloth(0x2E4E86)
dark = cloth(0x1E1A1E)
brown = cloth(0x4A3020)
hat = cloth(0x2A2A3A)
hat["y"] = grade(0xD8B050)
coat = cloth(0x9A2E2E)

make("pirate", {"hair": 4, "shirt": 1, "pants": 2},
     {"hair": 0x3A2418, "shirt": 0xE4DCC8, "pants": 0x6A5440, "shoe": 0x2A2024},
     [(BANDANA, red, -3, 0, True), (PATCH, dark, 5, 3, False)], stripes=0xA83A34,
     frames_spec=SWORDSMAN, poses=SWORD_POSES)
make("pirateGunner", {"hair": 4, "shirt": 1, "pants": 0},
     {"hair": 0x2A1A10, "shirt": 0x3E62A0, "pants": 0x5A4A3A, "shoe": 0x2A2024},
     [(BANDANA, blue, -3, 0, True), (MUSTACHE, brown, 7, 7, False)],
     frames_spec=GUNNER, poses=GUN_POSES)
make("pirateCaptain", {"hair": 0, "shirt": 1, "pants": 0},
     {"hair": 0x4A3020, "shirt": 0x9A2E2E, "pants": 0x2E2E3E, "shoe": 0x1E1A20},
     [(BEARD, brown, 5, 6, True), (TRICORN, hat, -2, -3, True)], coat=coat,
     frames_spec=SWORDSMAN, poses=SWORD_POSES)
