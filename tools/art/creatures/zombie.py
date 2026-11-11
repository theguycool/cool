# Zombie: hunched, arms held out, one sunken eye with a red glint, a slack jaw full of teeth, torn
# shirt and trousers. Three kinds share the drawing: the green zombie, the desert husk and the drowned.
# The Bow Zombie is a fourth, hooded, that carries a bow and draws it to shoot.
K = 0x16181E

IMP_HEAD = """
.H.......H.
.HH.....HH.
.JHhhhhhhH.
.Jhhhhgggg.
.Jgggddddg.
.Jsggeeregg
.ssgggggggs
..sggmtmtm.
..ssgmmmmm.
...dstmtss.
....ddddd..
"""
IMP_BITE = """
.H.......H.
.HH.....HH.
.JHhhhhhhH.
.Jhhhhgggg.
.Jgggddddg.
.Jsggeeregg
.ssgggggggs
..sggtmtmt.
..ssgmmmmm.
..ssgmmmmm.
...dstmtss.
....ddddd..
"""

def make(name, skin, hair, shirt, pants, eye, bow=False, imp=False):
    sk = ramp(skin, light=0xF4F0B0, dark=0x1E3A4A)
    sh = ramp(shirt, light=0xE8F0D0, dark=0x1A2040)
    pn = ramp(pants, light=0xD8D8F0, dark=0x14142A)
    pal = dict(h=sk[0], g=sk[1], s=sk[2], d=sk[3],
               H=hair, J=mix(hair, 0x000000, 0.35),
               T=sh[0], c=sh[1], C=sh[2], D=sh[3],
               P=pn[0], p=pn[1], q=pn[2], Q=pn[3],
               o=0x4A4048, O=0x2A242C,
               e=0x1A1418, r=eye, w=0xFFF0C0, m=0x3A1420, t=0xEDE8CC, f=0xB8404C, b=0xE8E0C8)
    inner = sk[3]

    head = part("""
    ...HHHHH...
    ..HHHHHHHH.
    .JHHHhhhhh.
    .JHHhhgggg.
    .JHggddddg.
    .Jsggeeregg
    .ssgggggggs
    ..sggmtmtm.
    ..ssgmmmmm.
    ...dstmtss.
    ....ddddd..
    """, pal, outline=K, inner=inner)
    # the imp: horns in place of hair, and a barbed tail
    tail = part("""
    ...O
    ..gs
    .gs.
    gs..
    gg..
    .gsO
    """, pal, outline=K, inner=inner)

    head_bite = part("""
    ...HHHHH...
    ..HHHHHHHH.
    .JHHHhhhhh.
    .JHHhhgggg.
    .JHggddddg.
    .Jsggeeregg
    .ssgggggggs
    ..sggtmtmt.
    ..ssgmmmmm.
    ..ssgmmmmm.
    ...dstmtss.
    ....ddddd..
    """, pal, outline=K, inner=inner)
    if imp:
        head = part(IMP_HEAD, pal, outline=K, inner=inner)
        head_bite = part(IMP_BITE, pal, outline=K, inner=inner)

    torso = part("""
    ...TTTTT..
    ..TTcccccc
    .TTccccccc
    .TcccccccC
    .cccccccCC
    .CcccccCC.
    .CCccccCC.
    ..CCcccCD.
    ..CDcCcD..
    ..D.CD.D..
    """, pal, outline=K, inner=sh[3])

    hips = part("""
    PPpppq
    Ppppqq
    """, pal, outline=K, inner=pn[3])

    arm = part("""
    TTTTc.ghhhg..
    ccccCCgggggs.
    CCCD.ssggs.ss
    ..........s..
    """, pal, outline=K, inner=inner)
    farpal = dict(pal)
    farpal.update(T=sh[1], c=sh[2], C=sh[3], D=sh[3], h=sk[1], g=sk[2], s=sk[3])
    arm_far = part("""
    TTTTc.ghhhg..
    ccccCCgggggs.
    CCCD.ssggs.ss
    ..........s..
    """, farpal, outline=K, inner=sk[3])
    arm_up = part("""
    ........hg.s
    ......hggss.
    ....Tcggs...
    ..TTcC.s....
    TTccC.......
    cCCD........
    """, pal, outline=K, inner=inner)
    arm_up_far = part("""
    ........hg.s
    ......hggss.
    ....Tcggs...
    ..TTcC.s....
    TTccC.......
    cCCD........
    """, farpal, outline=K, inner=sk[3])
    arm_down = part("""
    TTc.........
    cccCg.......
    CCCDgghh....
    ...ssgggh.s.
    .....ssggss.
    .......s.s..
    """, pal, outline=K, inner=inner)
    arm_down_far = part("""
    TTc.........
    cccCg.......
    CCCDgghh....
    ...ssgggh.s.
    .....ssggss.
    .......s.s..
    """, farpal, outline=K, inner=sk[3])

    def leg(text, dark):
        c = dict(pal)
        if dark:
            c.update(P=pn[1], p=pn[2], q=pn[3], o=0x3A3238, O=0x1E1A20, g=sk[2], s=sk[3])
        return part(text, c, outline=K, inner=pn[3], open_top=True)

    stand = """
    Pppq.
    Pppq.
    Pppq.
    .ppq.
    .ppq.
    .pqq.
    .gs..
    .gs..
    oooo.
    ooooO
    """
    fwd = """
    Pppq...
    PPppq..
    .Pppq..
    ..ppqq.
    ..Pppq.
    ...ppq.
    ...gs..
    ...gs..
    ...oooo
    ...oooO
    """
    back = """
    ..Pppq.
    ..Pppq.
    .Pppq..
    .ppqq..
    Pppq...
    ppq....
    gs.....
    gs.....
    ooo....
    oooO...
    """
    lift = """
    Pppq.
    Pppq.
    PPpq.
    .Pppq
    ..ppq
    ..gsq
    ..gs.
    .ooo.
    .oooO
    .....
    """
    L = {k: (leg(v, False), leg(v, True)) for k, v in dict(stand=stand, fwd=fwd, back=back, lift=lift).items()}
    lx = dict(stand=0, fwd=0, back=-2, lift=0)

    # the bow zombie: a bent arm that holds the bow upright at the hip, and the bow drawn with an arrow on it
    wood = dict(pal, W=0xA87840, w=0x7A5228, S=0xE8E0D0, a=0xC8B090, A=0xD8DCE4)
    arm_hold = part("""
    TT...
    cc...
    cC...
    cCggh
    .Dssg
    """, pal, outline=K, inner=inner)
    bow_up = part("""
    .SW..
    .S.W.
    .S..W
    .S..W
    .S..W
    .S..w
    .S.ww
    .S..w
    .S..W
    .S..W
    .S..W
    .S.W.
    .SW..
    """, wood, outline=K)
    bow_drawn = part("""
    ...W.
    ..S.W
    .S..W
    S...W
    S...w
    S..ww
    S...w
    S...W
    .S..W
    ..S.W
    ...W.
    """, wood, outline=K)
    arrow = part("""
    aaaaaaaaaaA
    """, wood, outline=K)

    W, Hh = 34, 34
    def fr(near, far, bob=0, lean=0, arms="out", bite=False):
        """near, far: leg poses; bob: the body's drop; lean: how far the head and arms push forward"""
        hx, hy = 11 + lean, 1 + bob
        tx, ty = 8 + lean // 2, 11 + bob
        layers = []
        if arms in ("hold", "aim"):
            layers.append((L[far][1], 13 + lx[far], 22))
            layers.append((L[near][0], 9 + lx[near], 22))
            layers.append((hips, 9, 20 + bob))
            layers.append((torso, tx, ty))
            layers.append((head_bite if bite else head, hx, hy))
            if arms == "hold":
                layers += [(bow_up, tx + 10, ty + 1), (arm_hold, tx + 5, ty + 2)]
            else:
                layers += [(arrow, tx + 5, ty + 3), (bow_drawn, tx + 14, ty - 2), (arm, tx + 6, ty + 2)]
            return frame(W, Hh, layers)
        a_far = dict(out=(arm_far, tx + 5, ty + 0), up=(arm_up_far, tx + 4, ty - 5), down=(arm_down_far, tx + 5, ty + 1))[arms]
        a_near = dict(out=(arm, tx + 6, ty + 2), up=(arm_up, tx + 5, ty - 3), down=(arm_down, tx + 6, ty + 3))[arms]
        if imp:
            layers.append((tail, 3, 17 + bob))
        layers.append(a_far)
        layers.append((L[far][1], 13 + lx[far], 22))
        layers.append((L[near][0], 9 + lx[near], 22))
        layers.append((hips, 9, 20 + bob))
        layers.append((torso, tx, ty))
        layers.append((head_bite if bite else head, hx, hy))
        layers.append(a_near)
        return frame(W, Hh, layers)

    if bow:
        frames = [
            fr("stand", "stand", arms="hold"),
            fr("fwd", "back", bob=0, arms="hold"),
            fr("stand", "lift", bob=1, arms="hold"),
            fr("back", "fwd", bob=0, arms="hold"),
            fr("lift", "stand", bob=1, arms="hold"),
            fr("stand", "back", bob=0, arms="aim"),
        ]
        sprite(name, frames, {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [5], "shoot": [5]}, foot=31, cx=13.5)
        return

    frames = [
        fr("stand", "stand"),
        fr("fwd", "back", bob=0),
        fr("stand", "lift", bob=1),
        fr("back", "fwd", bob=0),
        fr("lift", "stand", bob=1),
        fr("stand", "back", bob=0, lean=-1, arms="up"),
        fr("fwd", "back", bob=1, lean=2, arms="down", bite=True),
    ]
    poses = {"idle": [0], "walk": [1, 2, 3, 4], "windup": [5], "strike": [6]}
    if imp:
        poses["shoot"] = [5]      # it throws its fire with both arms up
    sprite(name, frames, poses, foot=31, cx=13.5)

make("zombie", 0x7DB658, 0x35482A, 0x3C8C8A, 0x3E4684, 0xFF4A3A)
make("zombie_1", 0xC9B078, 0x8A7648, 0xA88A58, 0x7A6A4A, 0xFFB030)
make("zombie_2", 0x6EA8A4, 0x2A4858, 0x4E7058, 0x3A4A62, 0x60F0FF)
# the Bow Zombie: a drowned one in a hunter's brown hood and a green jerkin, bow in hand
make("archer", 0x6EA8A4, 0x5A4630, 0x5A6A3A, 0x3A4A62, 0xFF4A3A, bow=True)
# the Umbral Imp: red-skinned and horned, yellow-eyed, in a dark tunic, with a barbed tail
make("imp", 0xD04A34, 0x3A1414, 0x5A1E22, 0x4A161C, 0xFFE040, imp=True)
