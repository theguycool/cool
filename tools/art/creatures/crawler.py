# Cave Crawler: a low hunter of the deep caves, in dull violet chitin with pale bands, a ridged
# back, a round head with a cluster of red eyes over hooked mandibles, and four thin legs a side
# that bend at a high knee, like a spider's. It scuttles on its legs in two sets, and pounces with
# its front legs raised and its mandibles spread.
K = 0x16101C
c = ramp(0x6A5078, light=0xE8D8F0, dark=0x1E1030)
pal = dict(h=c[0], b=c[1], s=c[2], d=c[3], p=mix(c[0], 0xE8E0C8, 0.45), e=0xE8483C, E=0xFFB0A0,
           m=0xD8CCB4, M=0x9A8A78)
inner = c[3]
LEG_NEAR = grade(mix(c[1], 0x000000, 0.25))
LEG_FAR = grade(mix(c[3], 0x000000, 0.25))
FOOT = grade(0x120C18)

BODY = """
.......hh..hh..hh...
....hhhbbhhbbhhbbh..
..hhbbbbbbbbbbbbbbh.
.hbbpbbbbpbbbbpbbbbh
hbbbbbbbbbbbbbbbbbbb
sbbbsbbbbsbbbbsbbbbb
.ssssssssssssssssss.
...dddddddddddddd...
"""
HEAD = """
.hhhh...
hbbbbh..
bbeEbbh.
bbbbeEb.
sbbbbbbm
.ssbbsMm
...ss.M.
"""
HEAD_OPEN = """
.hhhh...m
hbbbbh.mM
bbeEbbhM.
bbbbeEb..
sbbbbbb..
.ssbbsM..
...ss.Mm.
.......M.
"""
body = part(BODY, pal, outline=K, inner=inner)
head = part(HEAD, pal, outline=K, inner=inner)
head_open = part(HEAD_OPEN, pal, outline=K, inner=inner)


def line(g, x0, y0, x1, y1, col):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        g.set(x0, y0, col)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def leg_layer(W, H, legs, col):
    """Thin legs, each from its root on the body up to a high knee and down to a foot"""
    g = Grid(W, H)
    for (rx, ry), (kx, ky), (fx, fy) in legs:
        line(g, rx, ry, kx, ky, col)
        line(g, kx, ky, fx, fy, col)
        g.set(fx, fy, FOOT)
    return g


W, Hh = 36, 18
GROUND = 15
ROOTS = [9, 14, 19, 24]       # where each leg leaves the body, back to front


def legs_for(phase, far, bob, pounce=False):
    """phase 0: standing; 1 and 2: the two sets stepping; far legs sit a little behind"""
    out = []
    for i, rx in enumerate(ROOTS):
        side = 1 if i >= 2 else -1          # front legs reach forward, back legs back
        step = 0
        if phase:
            step = 2 if (i + phase) % 2 == 0 else -1
        ox = -1 if far else 0
        ry = 10 + bob
        kx = rx + side * 3 + ox + step // 2
        ky = 4 + bob + (0 if (i + phase) % 2 == 0 or not phase else 1)
        fx = rx + side * 6 + ox + step
        fy = GROUND
        if pounce and i >= 2:
            kx, ky, fx, fy = rx + 4 + ox, 3, rx + 8 + ox, 6 + (i - 2) * 2
        elif pounce:
            kx, ky, fx, fy = rx - 2 + ox, 8, rx - 7 + ox, GROUND
        out.append(((rx + ox, ry), (kx, ky), (fx, fy)))
    return out


def fr(phase, bob=0, pounce=False):
    far = leg_layer(W, Hh, legs_for(phase, True, bob, pounce), LEG_FAR)
    near = leg_layer(W, Hh, legs_for(3 - phase if phase else 0, False, bob, pounce), LEG_NEAR)
    g = Grid(W, Hh)
    g.put(far)
    if pounce:
        g.put(body, 5 - body.m, 5 + bob - body.m)
        g.put(head_open, 25 - head_open.m, 2 - head_open.m)
    else:
        g.put(body, 6 - body.m, 5 + bob - body.m)
        g.put(head, 25 - head.m, 6 + bob - head.m)
    g.put(near)
    return g


frames = [fr(0), fr(1), fr(0, -1), fr(2), fr(0, -1), fr(0, 0, True)]
sprite("crawler", frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=GROUND - 1, cx=18)
