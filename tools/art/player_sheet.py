#!/usr/bin/env python3
"""A sheet of the player's styles in their default colours (or chosen ones), laid together the way the
game does it: the bare figure, then trousers, shirt, scarf, hair and helmet, with the marker colours
swapped for graded ramps of the chosen colours.

  player_sheet.py <out.png>
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "creatures"))
import build
from artlib import SPRITES, grade, ramp
from PIL import Image, ImageDraw


def swap_map(colors):
    import player
    m = {}
    for cat, c in colors.items():
        tones = [grade(t) for t in ramp(c)]
        for mk, t in zip(player.MARK[cat], tones):
            m[mk] = t
    return m


def look_frames(look, colors):
    import player
    fr = player.dressed(look)
    m = swap_map(colors)
    return [g.recolor(m) for g in fr]


def sheet(out, k=4):
    build.load_all()
    import player
    base = dict(player.DEFAULT)
    looks = []
    for h in range(len(player.HAIR_STYLES)):
        looks.append(("hair: " + player.HAIR_STYLES[h], {"hair": h, "shirt": 0, "pants": 0}, base))
    for s in range(len(player.SHIRT_STYLES)):
        looks.append(("shirt: " + player.SHIRT_STYLES[s], {"hair": 0, "shirt": s, "pants": 0}, base))
    for p in range(len(player.PANTS_STYLES)):
        looks.append(("pants: " + player.PANTS_STYLES[p], {"hair": 0, "shirt": 0, "pants": p}, base))
    c2 = dict(base); c2.update(hair=0xC8501E, shirt=0x2E5A6A, pants=0x6A5A42)
    looks.append(("auburn, teal tee, khaki", {"hair": 3, "shirt": 3, "pants": 1, "scarf": True}, c2))
    c3 = dict(base); c3.update(hair=0xE8D080, shirt=0x8A6A2A, pants=0x1E1E24, helm=0xAAB2C0)
    looks.append(("blonde, helmet", {"hair": 2, "shirt": 1, "pants": 0, "helm": True}, c3))
    W = SPRITES["player"].w * k
    H = SPRITES["player"].h * k
    cols = 2   # front, then idle side, then walk frames
    show = [9, 0, 1, 2, 3, 4, 5, 6, 7]
    im = Image.new("RGB", (len(show) * (W + 6) + 180, len(looks) * (H + 8) + 8), (74, 69, 72))
    d = ImageDraw.Draw(im)
    for r, (name, look, colors) in enumerate(looks):
        fr = look_frames(look, colors)
        y = 8 + r * (H + 8)
        d.text((6, y + H // 2), name, fill=(236, 232, 222))
        for i, f in enumerate(show):
            im.paste(build.to_image(fr[f], k), (180 + i * (W + 6), y), build.to_image(fr[f], k))
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    sheet(sys.argv[1])
