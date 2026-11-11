# Chicken: a plump white hen with a red comb and wattle, a yellow beak, a folded wing and tail
# feathers, on thin yellow legs. Poses: standing, a two-step strut, pecking.
K = 0x241C22
pal = dict(w=0xFCFAF2, W=0xDCD6D2, v=0xB6AEB8, r=0xE2443C, R=0xA82A34, y=0xF4B63A, Y=0xC88420, e=0x1E1418)

body = part("""
w.........
ww..wwww..
wwwwwwwwww
WwwwWWwwww
WwwWWWWwww
.WwwWWwwww
.WWwwwwwwW
..WWWWWWW.
...vvvvv..
""", pal, outline=K, inner=pal["v"])

head = part("""
.rr.r.
.rrrr.
.wwww.
wwwewy
wwwwyY
.wwwr.
.www.R
""", pal, outline=K, inner=pal["v"])

leg = part("""
y
y
y
""", pal, outline=K, open_top=True)
foot = part("""
yyy
""", pal, outline=K)

def fr(bob, a, b, head_at=(8, 0)):
    L = [
        (leg, 6 + a[0], 12 - a[1]), (foot, 6 + a[0], 15 - a[1]),
        (body, 1, 4 + bob),
        (leg, 9 + b[0], 12 - b[1]), (foot, 9 + b[0], 15 - b[1]),
        (head, head_at[0], head_at[1] + bob),
    ]
    return frame(18, 18, L)

frames = [
    fr(0, (0, 0), (0, 0)),
    fr(0, (1, 0), (-1, 0)),
    fr(-1, (0, 1), (0, 0)),
    fr(0, (-1, 0), (1, 0)),
    fr(-1, (0, 0), (0, 1)),
    fr(1, (0, 0), (0, 0), head_at=(10, 6)),
]
sprite("chicken", frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=15, cx=7.5)
