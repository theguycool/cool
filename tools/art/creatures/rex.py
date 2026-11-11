# Tyrannax the Bonecrown: a great two-legged hunter in dark olive scales with darker stripes over its
# back, a pale throat and belly, a heavy head crowned with a ridge of bone spikes, a red-lit eye, rows
# of teeth, small clawed arms, thick hind legs and a long tail held out straight behind for balance.
# It strides on its hind legs, draws its head back with its jaws parting, and lunges with them wide.
from artlib import Grid, add_outline

K = 0x10140C
sc = ramp(0x4E5A34, light=0xD8E0A0, dark=0x101824)
th = ramp(0xC8C098, light=0xFFF8E0, dark=0x3A3030)
bone = ramp(0xE0D6BC, light=0xFFFFF4, dark=0x5A4E4A)
pal = dict(h=sc[0], b=sc[1], s=sc[2], d=sc[3], z=mix(sc[2], sc[3], 0.6),
           p=th[0], P=th[1], q=th[2], o=bone[0], O=bone[1], Q=bone[2], t=0xF4EEDC,
           e=0xFF5A3A, E=0xFFD0A0, n=0x141010, r=0x8E2A34, R=0x5A1420, c=0xE8E0CC, C=0x9A9080)
inner = sc[3]


def lined(g, inner_col=inner):
    out = Grid(g.w + 2, g.h + 2)
    out.put(g, 1, 1)
    before = [r[:] for r in out.px]
    add_outline(out, K)
    out.edge = set((x, y) for y in range(out.h) for x in range(out.w) if before[y][x] is None and out.px[y][x] is not None)
    out.inner = inner_col
    out.m = 1
    return out


def profile(pts, u):
    for (u0, y0), (u1, y1) in zip(pts, pts[1:]):
        if u0 <= u <= u1:
            t = (u - u0) / (u1 - u0)
            t = t * t * (3 - 2 * t)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


# body and tail, from the tail's tip (u 0) to the base of the neck (u 1)
TOP = [(0.0, 21), (0.2, 18), (0.42, 12), (0.6, 6), (0.72, 5), (0.86, 7), (1.0, 4)]
BOT = [(0.0, 23), (0.2, 23), (0.42, 21), (0.6, 22), (0.72, 27), (0.86, 27), (1.0, 18)]


def body(W=84, sway=0.0):
    g = Grid(W, 40)
    P = {k: grade(v) for k, v in pal.items()}
    for x in range(W):
        u = x / (W - 1)
        wag = sway * (1 - u) ** 2 * 4
        t0 = int(round(profile(TOP, u) + wag)) + 4
        t1 = int(round(profile(BOT, u) + wag)) + 4
        for y in range(t0, t1 + 1):
            v = (y - t0) / max(t1 - t0, 1)
            if y - t0 < 1 and t1 - t0 > 3:
                c = P["h"]
            elif v < 0.55:
                c = P["b"]
            elif u > 0.6 and v > 0.62:
                c = P["p"] if v < 0.85 else P["q"]          # the pale belly under the chest
            elif v < 0.82:
                c = P["s"]
            else:
                c = P["d"]
            # stripes: dark bands slanting down over the back and tail
            if v < 0.5 and (x + int(v * 6)) % 9 in (0, 1) and u < 0.9:
                c = P["z"]
            g.set(x, y, c)
    return lined(g)


HEAD = """
........oo..oo..............
......ooOOooOOoo............
....hhhhhhhhhhhhhhhh........
...hhbbbbbbbbbbbbbbbhhh.....
..hbbbbbbbbbbbbbbbbbbbbhh...
.hbbbbbbbbbbbbbbbbbbbbbbbh..
hbbbbbbbbbbbbbeEbbbbbbbbbbbn
hbbbbbbbbbbbbbeebbbbbbbbbbbb
bbbbbbbbbbbbbbbbbbbbbbbbbbbb
sbbbbbbbbbbbbbbbbsssssssssss
sbbbbbbbbbbbbbbbbntntntntntn
ssbbbbbbbbbbbbbbbstststststs
.sppppppppppppppppppppppppps
..sqqqqqqqqqqqqqqqqqqqqqqqs.
...sssssssssssssssssssssss..
"""
HEAD_OPEN = """
........oo..oo..............
......ooOOooOOoo............
....hhhhhhhhhhhhhhhh........
...hhbbbbbbbbbbbbbbbhhh.....
..hbbbbbbbbbbbbbbbbbbbbhh...
.hbbbbbbbbbbbbbbbbbbbbbbbh..
hbbbbbbbbbbbbbeEbbbbbbbbbbbn
hbbbbbbbbbbbbbeebbbbbbbbbbbb
bbbbbbbbbbbbbbbbbbbbbbbbbbbb
sbbbbbbbbbbbbbbbbsssssssssss
sbbbbbbbbbbbbbbbbtntntntntnt
sbbbbbbbbbbbbbbrrrrrrrrrrrr.
ssbbbbbbbbbbbbrrRRRRRRRRRR..
.sbbbbbbbbbbbrrRRRRRRRRR....
..sbbbbbbbbbrrRRRRRRRRRR....
...sppppppppprrrrrrrrrrrrr..
....sqqqqqqqqtntntntntntntn.
.....sqqqqqqqqqqqqqqqqqqqqq.
......ssssssssssssssssssss..
"""
CROWN = """
o.......o.......
Oo.....oO.....o.
.Oo...oOO....oO.
.OOo.oOOOo..oOO.
..OOoOOOOOooOO..
"""
NECK = """
....hhhhhhh
..hhbbbbbbb
.hbbbbbbbbb
hbbbbbbbbbb
bbbbbbbbbbs
bbbbbbbbbbs
sbbbbbbbbps
sbbbbbbbpps
ssbbbbbpqs.
.ssbbbpqs..
..sssss....
"""
ARM = """
.bbs.
.bbs.
..bbs
..cbs
..c.c
"""
THIGH = """
...hhhhhh...
.hhbbbbbbhh.
hbbbbbbbbbbs
bbbbbbbbbbbs
bbbbbbbbbbss
sbbbbbbbbbss
.sbbbbbbbss.
..sbbbbbss..
...sbbbss...
"""
SHIN = {
    "stand": """
..bbbbbs....
..bbbbbs....
...bbbbs....
...bbbbs....
...bbbss....
....bbbs....
....bbbs....
....bbbs....
....bbbs....
...bbbbs....
..bbbbbbs...
.bbbbbbbbs..
bbbbbbbbbbs.
cCcCcCcCcC..
""",
    "fwd": """
..bbbbbs.....
...bbbbbs....
....bbbbbs...
.....bbbbbs..
......bbbbs..
......bbbbs..
.....bbbbs...
.....bbbbs...
....bbbbs....
....bbbbs....
...bbbbbbs...
..bbbbbbbbs..
.bbbbbbbbbbs.
.cCcCcCcCcC..
""",
    "back": """
..bbbbbs....
.bbbbbs.....
.bbbbs......
.bbbbs......
.bbbbs......
..bbbs......
..bbbbs.....
...bbbs.....
...bbbbs....
....bbbbs...
....bbbbbs..
....bbbbbbs.
....bbbbbbbs
....cCcCcCc.
""",
}

far_pal = dict(pal, h=sc[1], b=sc[2], s=sc[3], p=th[1], q=th[2])
head = part(HEAD, pal, outline=K, inner=inner)
head_open = part(HEAD_OPEN, pal, outline=K, inner=inner)
crown = part(CROWN, pal, outline=K, inner=bone[2])
neck = part(NECK, pal, outline=K, inner=sc[2])
arm_n = part(ARM, pal, outline=K, inner=inner)
arm_f = part(ARM, far_pal, outline=K, inner=inner)
thigh_n = part(THIGH, pal, outline=K, inner=sc[2])
thigh_f = part(THIGH, far_pal, outline=K, inner=sc[3])
shin_n = {k: part(v, pal, outline=K, inner=inner, open_top=True) for k, v in SHIN.items()}
shin_f = {k: part(v, far_pal, outline=K, inner=inner, open_top=True) for k, v in SHIN.items()}

W, Hh = 130, 84
GROUND = 79


def fr(near="stand", far="stand", bob=0, mode="stand", sway=0.0):
    bx, by = 4, 33 + bob
    layers = []
    hip_x = bx + 46
    shin_y = GROUND - 13
    sx = {"stand": 0, "fwd": 2, "back": -2}
    # the far leg, behind
    layers += [(thigh_f, hip_x + 4 + sx[far] // 2, by + 18), (shin_f[far], hip_x + 4 + sx[far], shin_y)]
    layers.append((arm_f, bx + 76, by + 26))
    layers.append((body(sway=sway), bx, by))
    head_dx = {"stand": 0, "windup": -3, "strike": 5}[mode]
    head_dy = {"stand": 0, "windup": -3, "strike": 3}[mode]
    layers.append((neck, bx + 78 + head_dx // 2, by + 4 + head_dy // 2))
    hd = head if mode == "stand" else head_open
    layers.append((hd, bx + 84 + head_dx, by - 6 + head_dy))
    layers.append((crown, bx + 82 + head_dx, by - 11 + head_dy))
    layers.append((arm_n, bx + 79, by + 27))
    # the near leg, in front
    layers += [(shin_n[near], hip_x + sx[near], shin_y), (thigh_n, hip_x + sx[near] // 2, by + 19)]
    return frame(W, Hh, layers)


frames = [
    fr(),
    fr("fwd", "back", 0, "stand", 0.5),
    fr("stand", "stand", -1, "stand", 0.0),
    fr("back", "fwd", 0, "stand", -0.5),
    fr("stand", "stand", -1, "stand", 0.0),
    fr("stand", "back", 0, "windup", 0.3),
    fr("fwd", "back", 1, "strike", -0.3),
]
sprite("rex", frames, {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6]}, foot=GROUND, cx=62)
