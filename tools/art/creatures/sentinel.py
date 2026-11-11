# Crystal Sentinel: a floating construct, a tall crystal cut in facets, lit on its left faces, with a
# bright core in its heart that watches like an eye, two great shards that hover at its sides and
# small shards circling it. It bobs as it hovers; to charge it draws its shards in close and its core
# flares; it strikes by flinging the shards forward in a burst of light.
K = 0x141A30
cr = ramp(0x8AB8E0, light=0xF0F8FF, dark=0x241A50)
pal = dict(H=0xF4FCFF, h=cr[0], b=cr[1], s=cr[2], S=mix(cr[2], cr[3], 0.5), d=cr[3], c=0x7AE8F8, C=0xC8FCFF,
           W=0xFFFFFF, g=0xA8F0FF)
inner = cr[3]

BODY = """
......hh......
.....Hhbb.....
....HhbbbS....
...HhbbbbsS...
..HhbbbbbbsS..
.HhbbbbbbbbsS.
HhbbbbbbbbbbsS
Hhbbbbbbbbbbbs
hhbbbbbccbbbbs
hbbbbbcCCcbbbs
hbbbbcCWWCcbbs
hbbbbcCWWCcbbs
hbbbbbcCCcbbbs
hbbbbbbccbbbbs
sbbbbbbbbbbbbd
ssbbbbbbbbbbdd
.ssbbbbbbbbdd.
..ssbbbbbbdd..
...ssbbbbdd...
....ssbbdd....
.....ssdd.....
......sd......
"""
BODY_FLARE = """
......hh......
.....Hhbb.....
....HhbbbS....
...HhbbbbsS...
..HhbbccbbsS..
.HhbbcCCcbbsS.
HhbbcCWWCcbbsS
HhbcCWWWWCcbbs
hhbcWWWWWWcbbs
hbcCWWWWWWCcbs
hbcWWWWWWWWcbs
hbcWWWWWWWWcbs
hbcCWWWWWWCcbs
hbbcWWWWWWcbbs
sbbcCWWWWCcbbd
ssbbcCWWCcbbdd
.ssbbcCCcbbdd.
..ssbbccbbdd..
...ssbbbbdd...
....ssbbdd....
.....ssdd.....
......sd......
"""
SHARD = """
..h..
.Hbs.
Hhbbs
hbbbs
hbbbs
hbbbs
.hbs.
..s..
"""
SHARD_SIDE = """
..hh....
.Hhbbbs.
Hhbbbbbbs
.sbbbbs..
...ss....
"""
CHIP = """
.h.
hbs
.s.
"""
BURST = """
...g...
.g.W.g.
..WWW..
gWWWWWg
..WWW..
.g.W.g.
...g...
"""

def fix(text):
    rs = [r.strip() for r in text.strip().split("\n")]
    w = max(len(r) for r in rs)
    return "\n".join(r.ljust(w, ".") for r in rs)

body = part(BODY, pal, outline=K, inner=inner)
flare = part(BODY_FLARE, pal, outline=K, inner=inner)
shard = part(SHARD, pal, outline=K, inner=inner)
shard_fly = part(fix(SHARD_SIDE), pal, outline=K, inner=inner)
chip = part(CHIP, pal, outline=K, inner=inner)
burst = part(BURST, pal)

W, Hh = 50, 42
FOOT = 36

# the small shards' places round the body, in turn
ORBIT = [(3, 6), (36, 10), (6, 30), (34, 28), (20, 1)]


def fr(bob=0, mode="hover", turn=0):
    bx, by = 15, 8 + bob
    layers = []
    for i, (ox, oy) in enumerate(ORBIT):
        if mode == "hover" and (i + turn) % 2 == 0:
            layers.append((chip, ox, oy + bob))
    if mode == "hover":
        layers += [(shard, bx - 8, by + 7 + turn), (body, bx, by), (shard, bx + 17, by + 8 - turn)]
    elif mode == "charge":
        layers += [(shard, bx - 4, by + 8), (flare, bx, by - 1), (shard, bx + 13, by + 8)]
        layers += [(chip, bx - 6, by + 2), (chip, bx + 18, by + 2), (chip, bx - 5, by + 20), (chip, bx + 17, by + 20)]
    else:
        layers += [(body, bx + 1, by), (shard_fly, bx + 17, by + 6), (shard_fly, bx + 19, by + 13), (burst, bx + 27, by + 8)]
    return frame(W, Hh, layers)


frames = [fr(0, "hover", 0), fr(1, "hover", 1), fr(-1, "charge"), fr(0, "strike")]
sprite("sentinel", frames, {"idle": [0], "fly": [0, 1], "charge": [2], "strike": [3]}, foot=FOOT, cx=22)
