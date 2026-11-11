#!/usr/bin/env python3
"""Lays out art dumped by tools/art/dump (see tools/art.sh) as labelled sheets.

  sheets.py roster <dump folder> <out.png> [mob|tile] [pixels per block]
  sheets.py compare <old dump> <new dump> <out.png> [mob|tile] [pixels per block] [names...]

Every picture is drawn at the size it has in the game: `pixels per block` screen pixels for one
block of the world, so an old 8-pixel-a-block sprite and a new 16-pixel one line up.
"""
import os, sys
from PIL import Image, ImageDraw

BG = (74, 69, 72)
BG2 = (58, 54, 58)
INK = (236, 232, 222)

def load(folder):
    out = {}
    order = []
    for line in open(os.path.join(folder, "manifest.txt")):
        f = line.split()
        if len(f) < 6:
            continue
        kind, name, w, h, n, scale = f[0], f[1], int(f[2]), int(f[3]), int(f[4]), float(f[5])
        raw = open(os.path.join(folder, name + ".rgba"), "rb").read()
        frames = [Image.frombytes("RGBA", (w, h), raw[i * w * h * 4:(i + 1) * w * h * 4]) for i in range(n)]
        out[name] = dict(kind=kind, name=name, w=w, h=h, frames=frames, scale=scale)
        order.append(name)
    return out, order

def scaled(img, scale, ppb):
    """One frame at `ppb` screen pixels a block (nearest neighbour)."""
    k = scale * ppb
    w = max(1, round(img.width * k))
    h = max(1, round(img.height * k))
    return img.resize((w, h), Image.NEAREST)

def strip(entry, ppb, maxframes=8, gap=6):
    fr = [scaled(f, entry["scale"], ppb) for f in entry["frames"][:maxframes]]
    w = sum(f.width for f in fr) + gap * (len(fr) - 1)
    h = max(f.height for f in fr)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for f in fr:
        im.alpha_composite(f, (x, h - f.height))
        x += f.width + gap
    return im

def roster(folder, out, kind="mob", ppb=48, names=None, cols_w=1500):
    data, order = load(folder)
    names = [n for n in (names or order) if n in data and data[n]["kind"] == kind]
    cells = []
    for n in names:
        s = strip(data[n], ppb, maxframes=1 if kind == "tile" else 8)
        cells.append((n, s))
    pad, lab = 10, 14
    x = y = pad
    rowh = 0
    places = []
    for n, s in cells:
        cw = max(s.width, 7 * len(n)) + pad
        if x + cw > cols_w:
            x = pad
            y += rowh + lab + pad
            rowh = 0
        places.append((n, s, x, y))
        rowh = max(rowh, s.height)
        x += cw
    H = y + rowh + lab + pad
    im = Image.new("RGBA", (cols_w, H), BG + (255,))
    d = ImageDraw.Draw(im)
    for n, s, x, y in places:
        im.alpha_composite(s, (x, y))
        d.text((x, y + s.height + 2), n, fill=INK)
    im.convert("RGB").save(out)
    print(out, im.size)

def compare(oldf, newf, out, kind="mob", ppb=48, names=None, width=1500):
    old, order_old = load(oldf)
    new, order_new = load(newf)
    names = [n for n in (names or order_new) if n in new and new[n]["kind"] == kind and n in old]
    pad, lab = 12, 16
    rows = []
    for n in names:
        a = strip(old[n], ppb, maxframes=1 if kind == "tile" else 5)
        b = strip(new[n], ppb, maxframes=1 if kind == "tile" else 8)
        rows.append((n, a, b))
    if kind == "tile":
        # tiles in a grid of old | new pairs
        cw = ppb * 2 + pad * 3
        percol = max(1, width // (cw + 90))
        top = pad + lab + 4
        H = top + ((len(rows) + percol - 1) // percol) * (ppb + lab + pad)
        im = Image.new("RGBA", (width, H), BG + (255,))
        d = ImageDraw.Draw(im)
        d.text((pad, 4), "BLOCKS: each pair is BEFORE, then AFTER", fill=INK)
        for i, (n, a, b) in enumerate(rows):
            x = pad + (i % percol) * (cw + 90)
            y = top + (i // percol) * (ppb + lab + pad)
            im.alpha_composite(a, (x, y))
            im.alpha_composite(b, (x + ppb + pad, y))
            d.text((x, y + ppb + 2), n, fill=INK)
        im.convert("RGB").save(out)
        print(out, im.size)
        return
    half = width // 2
    H = pad + lab
    for n, a, b in rows:
        H += max(a.height, b.height) + lab + pad
    im = Image.new("RGBA", (width, H), BG + (255,))
    d = ImageDraw.Draw(im)
    d.rectangle([half, 0, width, H], fill=BG2)
    d.text((pad, 4), "BEFORE", fill=INK)
    d.text((half + pad, 4), "AFTER", fill=INK)
    y = pad + lab
    for n, a, b in rows:
        h = max(a.height, b.height)
        im.alpha_composite(a.crop((0, 0, min(a.width, half - 2 * pad), a.height)), (pad, y + h - a.height))
        im.alpha_composite(b.crop((0, 0, min(b.width, half - 2 * pad), b.height)), (half + pad, y + h - b.height))
        d.text((pad, y + h + 2), n, fill=INK)
        y += h + lab + pad
    im.convert("RGB").save(out)
    print(out, im.size)

if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "roster":
        roster(a[1], a[2], a[3] if len(a) > 3 else "mob", int(a[4]) if len(a) > 4 else 48, a[5:] or None)
    elif a and a[0] == "compare":
        compare(a[1], a[2], a[3], a[4] if len(a) > 4 else "mob", int(a[5]) if len(a) > 5 else 48, a[6:] or None)
    else:
        print(__doc__)
