# Mimic: shut, it is the game's chest to the pixel; awake, the lid lifts on a red mouth ringed with
# teeth, two yellow eyes open on the lid and a tongue lolls out. Frames (the game picks them by
# number): 0 shut, 1 and 2 hopping with its jaws open, 3 biting.
pal = dict(k=0x2A1C14, W=0xD8A866, w=0xB98A4E, d=0x8F6732, D=0x6E4C26, i=0x8A8E98, y=0xF5D142, Y=0xFFF0A0,
           t=0xFFFFFF, r=0x7A1420, R=0x4A0A14, p=0xE86A7A, e=0xFFE040, E=0x14101A)
SHUT = """
.kkkkkkkkkkkkkk.
kWWWWWWWWWWWWWWk
kwwwwwwwwwwwwwwk
kddddddddddddddk
kiiiiiiyyiiiiiik
kwwwwwwyYwwwwwwk
kwwwwwwwwwwwwwwk
kwdwwwwwwwwwwdwk
kwwwwwwwwwwwwwwk
kDDDDDDDDDDDDDDk
.kkkkkkkkkkkkkk.
"""
LID = """
.kkkkkkkkkkkkkk.
kWWWWWWWWWWWWWWk
kwweEwwwwwweEwwk
kddddddddddddddk
ktkttkttkttkttkk
"""
BASE = """
kktkktkktkktkktk
kiiiiiiyyiiiiiik
kwwwwwwyYwwwwwwk
kwwwwwwwwwwwwwwk
kwdwwwwwwwwwwdwk
kwwwwwwwwwwwwwwk
kDDDDDDDDDDDDDDk
.kkkkkkkkkkkkkk.
"""
def mouth(n, tongue):
    rows_ = []
    for y in range(n):
        if tongue and y >= n - 2:
            rows_.append("kRrrrrppppprrrRk")
        else:
            rows_.append("kRrrrrrrrrrrrrRk")
    return "\n".join(rows_)
TONGUE = """
pp.
ppp
.pp
"""
shut = part(SHUT, pal)
lid = part(LID, pal)
base = part(BASE, pal)
m3, m5, m2 = part(mouth(3, True), pal), part(mouth(5, True), pal), part(mouth(2, False), pal)
tongue = part(TONGUE, pal, outline=pal["k"])
W, H = 22, 22
def awake(gap, m, out=False):
    by = 12
    L = [(m, 3, by - gap), (base, 3, by), (lid, 3, by - gap - 5)]
    if out:
        L.append((tongue, 17, by - 1))
    return frame(W, H, L)
frames = [frame(W, H, [(shut, 3, 9)]), awake(3, m3), awake(5, m5), awake(2, m2, out=True)]
sprite("mimic", frames, {"idle": [0], "hop": [1, 2], "strike": [3]}, foot=18, cx=11)
