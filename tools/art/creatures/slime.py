# Slimes: a wobbling see-through blob with a shine on its brow, two dark eyes and a wide mouth.
# Poses: sitting, stretched in the air, lunging with its mouth open. The ember slime of the Umbral
# Realm is the same creature in molten colours with a glowing core.
def slime(name, col, K, eye=0x12241A, core=None, light=0xFFFFD8, dark=0x143848):
    c = ramp(col, light=light, dark=dark)
    pal = dict(h=c[0], g=c[1], s=c[2], d=c[3], w=0xFFFFFF, k=eye, e=0xFFFFFF, m=mix(c[3], 0x000000, 0.45),
               c=core if core else c[1], t=0xFFFFFF)
    sit = part("""
    ......hhhhhhhh......
    ....hhhwwhhhhhgg....
    ...hhwwwhhgggggggg..
    ..hhwwhgggggggggggs.
    .hhhggggggggggggggs.
    .hgggkeggggggkegggss
    hggggkkggggggkkgggss
    hgggggggggggggggggss
    gggggggggggggggggssd
    gggggggmmmmmmggggssd
    sggccggggggggggggssd
    .sssggggggggggggssd.
    ..dssssssssssssssd..
    """, pal, outline=K)
    air = part("""
    .....hhhhhh.....
    ...hhhwwhhhgg...
    ..hhwwwhgggggg..
    ..hwwhgggggggs..
    .hhhgggggggggs..
    .hggkeggggkeggs.
    .hggkkggggkkggs.
    .hggggggggggggs.
    .ggggggggggggss.
    .gggggmmmmgggss.
    .ggccggggggggss.
    .sgggggggggggsd.
    ..sgggggggggssd.
    ..ssggggggggsd..
    ...ssssssssss...
    ....dddddddd....
    """, pal, outline=K)
    lunge = part("""
    .......hhhhhhhh.......
    .....hhhwwhhhhhggg....
    ...hhhwwwhgggggggggg..
    ..hhhwwhggggggkegggggs
    .hhhgggggggkegkkgggggs
    .hgggggggggkkgggggggss
    hgggggggggggmmmmmmmgss
    hggggggggggmtmtmtmmgsd
    gggggggggggmmmmmmmmgsd
    sggccgggggggmtmtmtggsd
    .ssggggggggggggggggssd
    ..dsssssssssssssssssd.
    """, pal, outline=K)
    W, H = 26, 20
    frames = [
        frame(W, H, [(sit, 3, 5)]),
        frame(W, H, [(air, 5, 1)]),
        frame(W, H, [(lunge, 3, 6)]),
    ]
    sprite(name, frames, {"idle": [0], "hop": [1], "strike": [2]}, foot=17, cx=13)

slime("slime", 0x6FD05A, 0x12382C)
slime("emberSlime", 0xF07A2A, 0x3A1408, eye=0x2A0C04, core=0xFFE070, light=0xFFF0A0, dark=0x5A1030)
