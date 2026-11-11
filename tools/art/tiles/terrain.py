# The land: soil, grass, stone, sand, tree trunks, leaves, planks, brick and the ores. Sixteen
# pixels a side, each drawn to repeat without a seam (build.py preview shows a 3 x 3 patch).

def tex(text):
    return rows(text)

def swap(name, base_rows, pal, flip=""):
    tile(name, "\n".join(base_rows), pal, flip)

# ---- soil ----
DIRT = tex("""
bbbbbbddbbbbbbbb
bblbbbbddbbbbbbb
bbbbbbbbDbbblbbb
bbbbbbbbbbbbbbbb
ddbbbbbbbbbddbbb
bdDbbbbpbbbbddbb
bbbbbbbbbbbbbDbb
bbbbblbbbbbbbbbb
bbbbbbbbbddbbbbb
bbbbbbbbbbdDbblb
bbbddbbbbbbbbbbb
bbbbdDbbbbbbbbbb
bbbbbbbbbbbbpbbb
blbbbbbbbbbbbbbb
bbbbbbbbddbbbbbd
Dbbbbbbbbddbbbdd
""")
dirt_pal = dict(b=0x8A5C3C, d=0x774A30, D=0x5E3A26, l=0x9C6C46, p=0xB48C62)
swap("dirt", DIRT, dirt_pal, "hv")
swap("mud", DIRT, dict(b=0x56402E, d=0x483424, D=0x38281C, l=0x64503A, p=0x6E5A44), "hv")

# ---- grass over soil: a lit top, blades hanging over the earth ----
GRASS = tex("""
GGgGGGGgGGGGgGGG
gGggggGggggGgggg
gggggggggggggggg
ggsgggggsggggggs
gsssgggssgggggss
sSbssgsSbssggsSs
SbbbsssbbbSssSbb
bbbbbSbbbbbbSbbb
bbbbbbbbbddbbbbb
bbbbbbbbbbdDbblb
bbbddbbbbbbbbbbb
bbbbdDbbbbbbbbbb
bbbbbbbbbbbbpbbb
blbbbbbbbbbbbbbb
bbbbbbbbddbbbbbd
Dbbbbbbbbddbbbdd
""")
def grass(name, G, g, s, S, soil):
    p = dict(soil)
    p.update(G=G, g=g, s=s, S=S)
    swap(name, GRASS, p, "h")
grass("grass", 0x8CBF55, 0x5E9E3C, 0x3F7A34, 0x2C5A2C, dirt_pal)
grass("dryGrass", 0xE0D478, 0xC4B656, 0x9E8E40, 0x766A30, dirt_pal)
mud_pal = dict(b=0x56402E, d=0x483424, D=0x38281C, l=0x64503A, p=0x6E5A44)
grass("jungleGrass", 0x6CD860, 0x38AC42, 0x227E36, 0x175A2C, mud_pal)
grass("mossGrass", 0x9CB45A, 0x76923E, 0x56702E, 0x3C5024, mud_pal)

# ---- stone: flat plates with cracks between them ----
STONE = tex("""
ssssLLLsssssssss
sssLLLssssmmssss
ssssssssmmddmsss
sdmsssssmddmssLs
sddmsssssmmssLLs
smdmssssssssLLss
ssmsssLLssssssss
sssssLLLssssmsss
mmsssLLsssmmdmss
ddmssssssmddmsss
mddmsssssmdmssss
smmssssssmsssLLs
sssssLssssssLLLs
ssssLLLsssssLsss
sssssLsssmmsssss
ssssssssmddmssss
""")
stone_pal = dict(s=0x8E8E98, L=0xA4A4AE, m=0x787884, d=0x5C5C6A)
swap("stone", STONE, stone_pal, "hv")
swap("slate", STONE, dict(s=0x5E6678, L=0x727A8E, m=0x4C5466, d=0x3A4152), "hv")
swap("deepRock", STONE, dict(s=0x3E3846, L=0x4E4858, m=0x322C3A, d=0x241F2C), "hv")
swap("ashStone", STONE, dict(s=0x4A3A48, L=0x5C4A5A, m=0x3C2E3A, d=0x2C202A), "hv")
swap("sandstone", STONE, dict(s=0xD2B574, L=0xE2C98C, m=0xBEA060, d=0xA4874C), "hv")

# ---- sand: soft ripples and a few dark grains ----
SAND = tex("""
ssssssssssssssss
sslllllsssssssgs
sssddddssslllsss
ssgsssssssdddsss
ssssssssssssssss
lllsssssgsssslll
dddssssssssssddd
ssssssllllssssss
sgssssddddssgsss
ssssssssssssssss
ssslllsssssssss
sssdddsssssgssss
ssssssssssllllss
gsssssssssddddss
sssslllsssssssgs
ssssdddsssssssss
""".replace("ssslllsssssssss\n", "ssslllssssssssss\n"))
swap("sand", SAND, dict(s=0xE6D08C, l=0xF4E2A8, d=0xD6BC74, g=0xBE9E5C), "hv")
swap("snow", SAND, dict(s=0xF2F8FF, l=0xFFFFFF, d=0xDCE8F8, g=0xC4D6EE), "hv")

# ---- tree trunks: round, lit from the left, with grooved bark ----
LOG = tex("""
DhhbbGbbbGbbsssD
DhhbbGbbbbbbGssD
DhbbbbbbbGbbGssD
DhhbGbbbbGbbbssD
DhhbGbbbbbbbbssD
DhhbGbbGbbbbGssD
DhbbbbbGbbbbGssD
DhhbbbbGbbGbbssD
DhhbbGbbbbGbbssD
DhhbbGbbbbbbbssD
DhbbbGbbGbbbGssD
DhhbbbbbGbbbGssD
DhhbGbbbGbbbbssD
DhhbGbbbbbbGbssD
DhbbbbbGbbbGbssD
DhhbbbbGbbbbbssD
""")
def log(names, h, b, G, s, D):
    for n in names:
        swap(n, LOG, dict(h=h, b=b, G=G, s=s, D=D))
log(["log", "logBlock"], 0x9A7046, 0x7A5432, 0x5C3C22, 0x5E3E26, 0x3E2818)
log(["jungleLog", "jungleLogBlock"], 0x86703E, 0x66542E, 0x483A1C, 0x4C3E22, 0x302612)
log(["palmLog", "palmLogBlock"], 0xC09A64, 0xA07C4C, 0x7E5E36, 0x84643E, 0x5E4428)

# ---- leaves: one flat green with a few lit leaves, a few shadowed ones and gaps where the sky shows ----
# (kept plain on purpose, as the user asked: no outlined clumps, so a canopy reads as one mass rather
# than a pattern of scales; the land painter adds tufts where a leaf block meets the air, and leaves
# fall from the canopy)
LEAVES = tex("""
gggLLggggggggggg
ggLLgggggggsgggg
gggggggggsssggLL
ggggsgggggsggLLg
gggsss..gggggggg
gggggs...ggggggg
ggLggggd.gggsggg
gLLgggggggggsssg
LLgggggggggggsgg
ggggggggLLgggggg
gggsggggLggggggg
ggsssggggggggs..
gggsgggggggggss.
..gggggLLggggggg
s..ggggLgggggLLg
ggggggggggsggLgg
""")
def leaves(name, L, g, s, d):
    swap(name, LEAVES, dict(L=L, g=g, s=s, d=d), "h")
leaves("leaves", 0x6FA84A, 0x4C8838, 0x3A6B30, 0x2F5A2A)
leaves("jungleLeaves", 0x5AA848, 0x2F8A3E, 0x256E34, 0x1E5A2C)
leaves("birchLeaves", 0x9CC060, 0x76A048, 0x5E8439, 0x4C6E30)
leaves("pineLeaves", 0x4E8A68, 0x316A52, 0x275644, 0x1E4838)

# ---- planks: four boards with their grain, joints and nails ----
tile("planks", """
hhhhhdhhhhhhhhhh
bbbbndbbbbgggbbb
bgggbdbbbbbbbbbb
dddddddddddddddd
hhhhhhhhhhhhdhhh
bbbgggbbbbbndbbb
bbbbbbbbggbbdbbb
dddddddddddddddd
hhdhhhhhhhhhhhhh
bndbbbbgggbbbbbb
bbdbbbbbbbbbgggb
dddddddddddddddd
hhhhhhhhhdhhhhhh
bbgggbbbndbbbbbb
bbbbbbbbbdbbgggb
dddddddddddddddd
""", dict(h=0xD8AE74, b=0xC0935A, g=0xA97E48, d=0x7E5830, n=0x5A3A1E))

# ---- brick: four courses, each brick lit on top and dark below ----
BRICK = tex("""
hhhhhhhmHHHHHHHm
bbbbbbbmBBBBBBBm
sssssssmsssssssm
mmmmmmmmmmmmmmmm
HHHmhhhhhhhmHHHH
BBBmbbbbbbbmBBBB
sssmsssssssmssss
mmmmmmmmmmmmmmmm
hhhhhhhmhhhhhhhm
bbbbbbbmbbbbbbbm
sssssssmsssssssm
mmmmmmmmmmmmmmmm
hhhmHHHHHHHmhhhh
bbbmBBBBBBBmbbbb
sssmsssssssmssss
mmmmmmmmmmmmmmmm
""")
swap("brick", BRICK, dict(h=0xC8664E, b=0xAE4E3C, s=0x8C3A30, H=0xD27458, B=0xB85A44, m=0x8A8684))
swap("mossBrick", BRICK, dict(h=0x8EA872, b=0x748E5C, s=0x566E46, H=0x9AB47C, B=0x7E9866, m=0x4C5E3E))
swap("crackedBrick", BRICK, dict(h=0xA69280, b=0x8E7A68, s=0x705E50, H=0xB09C8A, B=0x988472, m=0x6A5A4C))

# ---- ores: stone with lumps of ore set into it, a shape for each so they tell apart in the dark ----
def ore(name, mask, o, O, k, base=STONE, base_pal=stone_pal):
    m = rows(mask)
    out = []
    for y in range(16):
        out.append("".join(base[y][x] if m[y][x] == "." else m[y][x] for x in range(16)))
    p = dict(base_pal)
    p.update(o=o, O=O, k=k, W=0xFFFFFF)
    tile(name, "\n".join(out), p, "hv")

LUMPS = """
................
....kkk.........
...kOook........
...koooook..kk..
....kooook.kOok.
.....kkkk..kook.
............kk..
..kk............
.kOok...........
.koook....kkk...
..kook...kOook..
...kk....koooook
..........koook.
...........kkk..
................
................
"""
ROUNDS = """
................
..kkk...........
.kOOok.....kk...
.kOoook...kOok..
.koooook..kook..
..koook....kk...
...kkk..........
.........kkk....
........kOOok...
..kk....kOooook.
.kOok...koooook.
.kook....kooook.
..kk......kkkk..
................
.....kk.........
....kOok........
"""
CHUNKS = """
................
.kkkk...........
.kOOok......kk..
.kOoook....kOok.
..koook...kOook.
...kkk....kook..
...........kk...
................
....kkkk........
...kOOook....kk.
...kOoook...kOok
....kooook..kook
.....kkkk....kk.
.kk.............
kOok............
kook............
"""
NUGGETS = """
................
...kk......W....
..kOok....WOW...
..kook.....W....
...kk...........
.........kk.....
........kOok....
.W......koook...
WOW......kook...
.W........kk....
....kk..........
...kOok.....kk..
...koook...kOok.
....kkk....kook.
............kk..
................
"""
GEMS = """
................
....k...........
...kOk......k...
..kOWok....kOk..
.kOooook..kOWok.
..koook....kok..
...kok......k...
....k...........
.........k......
........kOk.....
..k....kOWok....
.kOk..kOooook...
kOWok..koook....
.kok....kok.....
..k......k......
................
"""
SHARDS = """
................
.....kk.........
....kOok........
....kOok....kk..
...kOook...kOok.
...kook....kOok.
....kk....kOook.
..........kook..
...kk......kk...
..kOok..........
..kOok...kk.....
.kOook..kOok....
.kook...kOok....
..kk...kOook....
.......kook.....
........kk......
"""
ore("coal", LUMPS, 0x2A2A32, 0x4A4A56, 0x16161C)
ore("copper", ROUNDS, 0xD2793A, 0xF4AA6A, 0x8A4A22)
ore("iron", CHUNKS, 0xC89878, 0xEAC4A2, 0x80584A)
ore("gold", NUGGETS, 0xF2C83A, 0xFFEC90, 0xA87A1E)
ore("diamond", GEMS, 0x4FDCE4, 0xB8FBFF, 0x1E8A9C)
ore("mythril", SHARDS, 0x6A5CFF, 0xB8AEFF, 0x3A2EA8)
ash_pal = dict(s=0x4A3A48, L=0x5C4A5A, m=0x3C2E3A, d=0x2C202A)
ore("emberOre", ROUNDS, 0xFF7A1E, 0xFFD060, 0xA83A0C, base_pal=ash_pal)
ore("voidOre", SHARDS, 0xB04CFF, 0xECB4FF, 0x5A1E9A, base_pal=ash_pal)

# ---- more ores, each on the rock it is found in ----
VEINS = """
................
...........kk...
.........kkOok..
.......kkOook...
.....kkOook.....
....kOook.......
....kok.........
.....k......kk..
..........kkOk..
........kkOok...
..kk..kkOook....
.kOokkOook......
.koOOook........
..kkkkk.........
................
................
"""
CRUST = """
................
..kkkkk.........
.kOOooook.......
..kkkkkk....kk..
..........kkOok.
........kkOOook.
.......kOooookk.
........kkkkk...
................
...kkkk.........
..kOOookk.......
.kOooooook...kk.
..kkkkkkk..kkOok
..........kOoook
...........kkkk.
................
"""
ore("tin", ROUNDS, 0xC8D2DA, 0xF2F6FA, 0x7E8894)
ore("silver", VEINS, 0xC4CCD8, 0xFFFFFF, 0x6A7484)
ore("saltpeter", CRUST, 0xDCD8CC, 0xFFFFFF, 0x8A867C)
ore("amethyst", GEMS, 0x9A5ADC, 0xE0C0FF, 0x5A2A8A)
ore("crystalOre", SHARDS, 0x8AF0E8, 0xE8FFFF, 0x2E8A94, base_pal=dict(s=0x5E6678, L=0x727A8E, m=0x4C5466, d=0x3A4152))

# ---- birch: white bark with dark scars, round like the other trunks ----
BIRCH = tex("""
DhhbbbbbbbbbbssD
DhhbbkkkbbbbbssD
DhhbbbbbbbbbbssD
DhbbbbbbbbkkkssD
DhhbbbbbbbbbbssD
DhhbbbbbbbbbbssD
DhkkkbbbbbbbbssD
DhhbbbbbbbbbbssD
DhhbbbbbkkbbbssD
DhhbbbbbbbbbbssD
DhbbbbbbbbbbbssD
DhhbkkbbbbbbbssD
DhhbbbbbbbbkkssD
DhhbbbbbbbbbbssD
DhhbbbbbkkkbbssD
DhhbbbbbbbbbbssD
""")
for n in ("birchLog", "birchLogBlock"):
    swap(n, BIRCH, dict(h=0xFFFFFF, b=0xE8E4DA, k=0x3A3632, s=0xBEB8AE, D=0x7A746C))
