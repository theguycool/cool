# Cow: white with black patches, short horns, a dark ear, a pink muzzle, an udder, a tail with a
# dark tuft, and four legs on dark hooves. Poses: standing, a four-step walk, grazing.
K = 0x1E1A22
pal = dict(w=0xF8F4EC, W=0xD8D2D4, v=0xB0A8B6, b=0x38343E, B=0x54505E, m=0xF4AAB2, M=0xD27C8E, n=0x8A4056,
           y=0xEADFC4, Y=0xC4B490, f=0x3A3038, u=0xF6B8C0, U=0xD88898, e=0x1E1418, t=0xD8D2D4, T=0x38343E)

body = part("""
.....wwwwwwwwwwwwwww..
...wwwwbbbbwwwwwwbbww.
..wwwwbbbbbbwwwwbbbbww
.twwwwbbbbbbwwwwwbbbww
t.wwwwwbbbbwwwwwwwbbww
t.wwwwwwwwwwwwbbwwwwww
t.wwwwwwwwwwwbbbbwwwww
t.WwwwwwwwwwwbbbbwwwwW
t.WWwwwwwwwwwwbbwwwwWW
T..WWWwwwwwwwwwwwwWWW.
T...vvWWWWWWWWWWWWvv..
......vvvvvvvvvvvv....
""", pal, outline=K, inner=pal["v"])

udder = part("""
uuu
uUu
.u.
""", pal, outline=K, inner=pal["U"], open_top=True)

head = part("""
..yy.......
.yY........
bbbwwwww...
.bbbwwwwww.
..bwwwwewww
..wwwwwewmm
..wwwwwwmmm
...Wwwwmmnm
...WWwwmmmm
....WWWMMM.
""", pal, outline=K, inner=pal["v"])

def leg(dark):
    c = dict(pal)
    if dark:
        c["w"] = pal["W"]
        c["W"] = pal["v"]
    return part("""
www
www
wwW
wwW
wwW
wwW
fff
fff
""", c, outline=K, inner=pal["v"], open_top=True)

near = leg(False)
far = leg(True)

def fr(bob, nb, nf, head_at=(20, 1)):
    fb, ff = nf, nb
    L = [
        (far, 8 + fb[0], 14 - fb[1]),
        (far, 20 + ff[0], 14 - ff[1]),
        (udder, 8, 15 + bob),
        (body, 1, 4 + bob),
        (near, 4 + nb[0], 14 - nb[1]),
        (near, 16 + nf[0], 14 - nf[1]),
        (head, head_at[0], head_at[1] + bob),
    ]
    return frame(34, 24, L)

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (2, 0), (-2, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(0, (-2, 0), (2, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(0, (0, 0), (0, 0), head_at=(22, 9)),
]
sprite("cow", frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=21, cx=14)
