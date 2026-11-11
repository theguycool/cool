# Giraffe: sandy with brown patches, a long neck leaning forward, a small head with two horn stubs
# and ears, stilt legs on dark hooves and a tufted tail. Poses: standing, a four-step walk, the head
# brought down to graze.
K = 0x24160C
f = ramp(0xE8C060, light=0xFFF4C8, dark=0x40203A)
pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], P=0xA8682A, Q=0x86501E, l=0xF8E8B8, e=0x14101A, w=0xFFFFFF, n=0x4A2A1A,
           o=0x6A4424, k=0x3A2414, f=0x3A2A20)
inner = f[3]
body = part("""
............hhhhhh
.......hhhhhbbPPbb
...hhhhbbPPbbbPPbb
.hhbPPbbbPPbbbbbbb
hbbbPPbbbbbbPPbbbb
bbbbbbbPPbbbPPbbbb
bbPPbbbPPbbbbbbbPb
sbPPbbbbbbbPPbbbbb
sbbbbbbbbbbPPbbbbs
.ssblllllllllllbs.
...sssssssssssss..
""", pal, outline=K, inner=inner)

# the neck leans forward as it rises: a band five wide that steps right every few rows
def neck_rows(n):
    out = []
    for y in range(n):
        shift = round((n - 1 - y) * 4.0 / (n - 1)) if n > 1 else 0   # 4 at the top, 0 at the bottom
        patch = (y % 6) in (1, 2)
        band = "hbPPs" if patch else ("hPbbs" if (y % 6) == 4 else "hbbbs")
        out.append("." * shift + band + "." * (4 - shift))
    return "\n".join(out)
neck = part(neck_rows(24), pal, outline=K, inner=inner)
neck_low = part(neck_rows(9), pal, outline=K, inner=inner)

head = part("""
..o.o......
..k.k......
.bbhhhh....
bbbbbbbhh..
sbbbewbbbbl
.sbbbbbbbln
..sbbbbllll
...sssslll.
""", pal, outline=K, inner=inner)

def leg(dk):
    c = dict(pal)
    if dk:
        c.update(h=f[1], b=f[2], s=f[3], P=pal["Q"])
    return part("""
    bPb
    bPb
    bbs
    bbs
    bPs
    bbs
    bbs
    bbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    hbs
    fff
    fff
    """, c, outline=K, inner=inner, open_top=True)
near, far = leg(False), leg(True)
tail = part("""
b.
bs
bs
bs
bs
bs
kk
kk
""", pal, outline=K, inner=inner)
W, H = 40, 62

def fr(bob, nb, nf, graze=False):
    fb, ff = nf, nb
    L = [
        (tail, 1, 31 + bob),
        (far, 7 + fb[0], 38 - fb[1]), (far, 17 + ff[0], 38 - ff[1]),
        (body, 2, 28 + bob),
        (near, 4 + nb[0], 38 - nb[1]), (near, 14 + nf[0], 38 - nf[1]),
    ]
    if graze:
        L += [(neck_low, 17, 30 + bob), (head, 22, 37 + bob)]
    else:
        L += [(neck, 15, 6 + bob), (head, 20, 1 + bob)]
    return frame(W, H, L)

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (2, 0), (-2, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(0, (-2, 0), (2, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(0, (0, 0), (0, 0), graze=True),
]
sprite("giraffe", frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=58, cx=12)
