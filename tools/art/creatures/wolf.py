# Wolf: lean, grey, with pricked ears, a long muzzle, yellow eyes and a brush of a tail. Tamed
# (wolf_1) it is a sandy dog with a red collar. Poses: standing, a four-step walk, a snap of the jaws.
def canine(name, fur, belly, K, eye, collar=None, light=0xFFF4DC, dark=0x1E1E3A):
    f = ramp(fur, light=light, dark=dark)
    b = ramp(belly, light=0xFFFFFF, dark=dark)
    pal = dict(h=f[0], b=f[1], s=f[2], d=f[3], l=b[1], L=b[2], m=b[1], n=0x1A1418, y=eye, e=0x14101A,
               t=0xFFFFFF, r=0x9A2A38, c=collar if collar else f[1], C=mix(collar, 0x000000, 0.3) if collar else f[2])
    inner = f[3]
    body = part("""
    ...hhhhhhhhhhhh...
    .hhbbbbbbbbbbbbhh.
    hbbbbbbbbbbbbbbbbh
    bbbbbbbbbbbbbbbbbb
    bbbbbbbbbbbbbbbbbb
    sbbbbbbbbbbbbbbbbs
    .sslllllllllllss..
    ...sLLLLLLLLLs....
    """, pal, outline=K, inner=inner)
    tail = part("""
    .hh...
    hbbh..
    hbbbb.
    .sbbbb
    ..sbbb
    ...ss.
    """, pal, outline=K, inner=inner)
    head = part("""
    ..b...b.....
    .bsb.bsb....
    .bbbhbbbh...
    .hhbbbbbbh..
    hbbbbbyebbb.
    cbbbbbbbbmmm
    cCbbbbbmmmmn
    .sbbbllllll.
    ..ssssLL....
    """, pal, outline=K, inner=inner)
    snap = part("""
    ..b...b......
    .bsb.bsb.....
    .bbbhbbbh....
    .hhbbbbbbh...
    hbbbbbyebbbm.
    cbbbbbbbbmmmn
    cCbbbbbtmtmt.
    .sbbbbrrrrr..
    ..ssbbtltlt..
    ....sslllL...
    """, pal, outline=K, inner=inner)

    def leg(dk):
        c = dict(pal)
        if dk:
            c.update(b=f[2], s=f[3])
        return part("""
        bb
        bs
        bs
        bs
        bs
        bs
        dd
        """, c, outline=K, inner=inner, open_top=True)
    near, far = leg(False), leg(True)

    def fr(bob, nb, nf, biting=False, hx=0):
        fb, ff = nf, nb
        L = [
            (tail, 1, 2 + bob),
            (far, 9 + fb[0], 12 - fb[1]),
            (far, 20 + ff[0], 12 - ff[1]),
            (body, 5, 5 + bob),
            (near, 6 + nb[0], 12 - nb[1]),
            (near, 18 + nf[0], 12 - nf[1]),
            (snap if biting else head, 19 + hx, 1 + bob),
        ]
        return frame(34, 21, L)

    frames = [
        fr(0, (0, 0), (0, 0)),
        fr(0, (2, 0), (-2, 0)),
        fr(-1, (0, 0), (0, 1)),
        fr(0, (-2, 0), (2, 0)),
        fr(-1, (0, 1), (0, 0)),
        fr(0, (-1, 0), (2, 0), biting=True, hx=2),
    ]
    sprite(name, frames, {"idle": [0], "walk": [1, 2, 3, 4], "strike": [5]}, foot=18, cx=14.5)

canine("wolf", 0x8A8E9C, 0xCDD0D8, 0x16161E, 0xFFD23A)
canine("wolf_1", 0xC89A62, 0xF0DCB8, 0x241810, 0x2A1A14, collar=0xD03A3A, dark=0x3A1E2A)
