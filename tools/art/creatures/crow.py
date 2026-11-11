# Crow: a glossy black bird with a grey beak, a bright eye, fanned tail feathers and broad wings
# that beat up, level and down as it flies.
K = 0x0E0E16
pal = dict(k=0x2C2C40, K=0x45455E, h=0x5E5E7C, d=0x1C1C2A, b=0xA8A8B0, B=0x74747E, e=0xFFE070, f=0x8A8A94)

body = part("""
.........hhh....
d.......hhhhk...
dd....kkhhekkbb.
.ddkkkkkkkkkkBbb
..dkkkkkkkkkk...
...kkkkkkkkk....
....dkkkkkd.....
......ff........
""", pal, outline=K, inner=pal["d"])

wing_up = part("""
....hK..
...hKKK.
..hKKKK.
.hKKKKk.
hKKKKkk.
KKKKkk..
.kkkk...
""", pal, outline=K, inner=pal["d"])
wing_mid = part("""
hhKKKKKKKk
.hKKKKKkk.
...kkkk...
""", pal, outline=K, inner=pal["d"])
wing_down = part("""
.kkkk...
KKKKkk..
hKKKKkk.
.hKKKKk.
..hKKKK.
...hKKk.
....hk..
""", pal, outline=K, inner=pal["d"])

W, H = 20, 18
frames = [
    frame(W, H, [(body, 2, 7), (wing_up, 5, 1)]),
    frame(W, H, [(body, 2, 6), (wing_mid, 3, 8)]),
    frame(W, H, [(body, 2, 5), (wing_down, 5, 8)]),
]
sprite("crow", frames, {"idle": [0], "fly": [0, 1, 2, 1]}, foot=15, cx=9.5)
