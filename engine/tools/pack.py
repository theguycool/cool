#!/usr/bin/env python3
"""Packs what engine/tools/export/main.swift dumped into engine/src/data_gen.js:
one texture sheet (tiles, walls, item icons, then every sprite) as a PNG in base64, and the tables."""
import base64, glob, io, json, os, struct, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
W = 1024

def load(path):
    raw = open(path, "rb").read()
    w, h = struct.unpack("<II", raw[:8])
    return Image.frombytes("RGBA", (w, h), raw[8:])

def J(name):
    return json.load(open(os.path.join(src, name)))

tiles, items, recipes, mobs, sheet, clouds, misc = J("tiles.json"), J("items.json"), J("recipes.json"), J("mobs.json"), J("sheet.json"), J("clouds.json"), J("misc.json")

placed = []   # (image, x, y)
rects = {}
y = 0
# tiles: 64 to a row
for t in tiles:
    i = t["id"]
    placed.append((load(f"{src}/tiles/{i}.rgba"), (i % 64) * 16, y + (i // 64) * 16))
tile_rows = (len(tiles) + 63) // 64
y += tile_rows * 16
wall_y = y
n_walls = len(glob.glob(f"{src}/walls/*.rgba"))
for i in range(n_walls):
    placed.append((load(f"{src}/walls/{i}.rgba"), i * 16, y))
y += 16
item_y = y
for it in items:
    i = it["icon"]
    im = load(f"{src}/items/{i}.rgba")
    it["isz"] = im.size[0]
    placed.append((im, (i % 64) * 16, y + (i // 64) * 16))
y += ((len(items) + 63) // 64) * 16

# sprites: shelves, tallest first
sprites = []
for m in mobs:
    for v, var in enumerate(m["variants"]):
        for f in range(var["frames"]):
            sprites.append((f"mob:{m['key']}:{v}", f, load(f"{src}/mobs/{m['key']}_{v}_{f}.rgba")))
for s in sheet:
    if not s["name"].startswith("player"):
        continue
    for f in range(s["frames"]):
        sprites.append((f"sheet:{s['name']}", f, load(f"{src}/sheet/{s['name']}_{f}.rgba")))
for i in range(len(glob.glob(f"{src}/clouds/*.rgba"))):
    sprites.append((f"cloud:{i}", 0, load(f"{src}/clouds/{i}.rgba")))
for p in sorted(glob.glob(f"{src}/misc/*.rgba")):
    sprites.append(("misc:" + os.path.basename(p)[:-5], 0, load(p)))
for p in sorted(glob.glob(f"{src}/parts/*.rgba")):
    sprites.append(("part:" + os.path.basename(p)[:-5], 0, load(p)))
order = sorted(range(len(sprites)), key=lambda k: (-sprites[k][2].size[1], -sprites[k][2].size[0]))
x, shelf_h = 0, 0
for k in order:
    name, f, im = sprites[k]
    w, h = im.size
    if x + w + 1 > W:
        y += shelf_h + 1
        x, shelf_h = 0, 0
    placed.append((im, x, y))
    rects.setdefault(name, {})[f] = [x, y, w, h]
    x += w + 1
    shelf_h = max(shelf_h, h)
y += shelf_h + 1
free_y = y
y += 72   # room kept for the shapes the engine draws into the sheet itself
H = 1
while H < y:
    H *= 2
atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for im, px, py in placed:
    atlas.paste(im, (px, py))
buf = io.BytesIO()
atlas.save(buf, "PNG", optimize=True)
png = buf.getvalue()

sheet_meta = {s["name"]: {k: s[k] for k in ("frames", "w", "h", "foot", "cx", "poses")} for s in sheet if s["name"].startswith("player")}
data = {
    "tiles": tiles, "items": items, "recipes": recipes, "mobs": mobs, "sheet": sheet_meta, "clouds": clouds["classes"], "misc": misc,
    "atlas": {"w": W, "h": H, "wallY": wall_y, "walls": n_walls, "itemY": item_y, "freeY": free_y, "rects": {k: [v[i] for i in sorted(v)] for k, v in rects.items()}},
}
out = "// Made by engine/tools/pack.py from the Swift game's own data and art. Do not edit by hand.\n"
out += "const DATA = " + json.dumps(data, separators=(",", ":")) + ";\n"
out += 'const ATLAS_PNG = "data:image/png;base64,' + base64.b64encode(png).decode() + '";\n'
open(os.path.join(dst, "data_gen.js"), "w").write(out)
atlas.save(os.path.join(dst, "..", "dist", "atlas.png"))
print(f"atlas {W}x{H}, png {len(png)//1024} KB, data_gen.js {len(out)//1024} KB, {len(rects)} sprite sets")
