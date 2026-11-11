# Bats: a small furred body with big ears, bright eyes and two fangs, on leathery wings that beat up,
# level and down. The cave bat is dusk purple; the cinder bat of the Umbral Realm glows like a coal.
def bat(name, fur, wing, eye, K):
    f = ramp(fur, light=0xF0E0FF, dark=0x14102A)
    w = ramp(wing, light=0xF0E0FF, dark=0x14102A)
    pal = dict(h=f[0], b=f[1], s=f[2], H=w[0], w=w[1], W=w[2], D=w[3], y=eye, t=0xFFFFFF)
    body = part("""
    b....b
    bb..bb
    bhbbhb
    bybbyb
    .bbbb.
    .sbbs.
    ..tt..
    """, pal, outline=K, inner=f[3])
    up = part("""
    H.....
    wH....
    wwH...
    WwwH..
    .WwwH.
    ..WwwH
    ...WWw
    """, pal, outline=K, inner=w[3])
    mid = part("""
    HHHHHHH
    WwwwwwH
    .W.W.Ww
    """, pal, outline=K, inner=w[3])
    down = part("""
    ...WWw
    ..WwwH
    .WwwH.
    WwwH..
    wwH...
    wH....
    H.....
    """, pal, outline=K, inner=w[3])
    W, H = 24, 16
    def fr(wing_l, wy, by):
        wing_r = wing_l.flipped()
        return frame(W, H, [(wing_l, 9 - wing_l.w + wing_l.m * 0 , wy), (wing_r, 15, wy), (body, 9, by)])
    frames = [fr(up, 1, 6), fr(mid, 6, 5), fr(down, 7, 4)]
    sprite(name, frames, {"idle": [0], "fly": [0, 1, 2, 1]}, foot=13, cx=12)

bat("bat", 0x5A4A72, 0x3E3456, 0xFF4A4A, 0x120E1C)
bat("cinderBat", 0x4A2A22, 0xD0541E, 0xFFE060, 0x1E0C08)
