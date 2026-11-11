#!/usr/bin/env python3
"""A quick mock of the game's world from the drawings alone (no Swift build), for judging colours,
blocks and creatures together: sky, a strip of land, trees and creatures standing on it.

  scene.py <out.png> [meadow|night]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "creatures"))
import build
from artlib import SPRITES, TILES, PPB, grade, mix
from PIL import Image

SCALE = 3          # screen pixels per art pixel (48 a block, as an iPad shows it)
BW, BH = 36, 16    # blocks across and down


def sky(img, top, bot, horizon):
    px = img.load()
    for y in range(img.height):
        t = min(1.0, y / max(1, horizon))
        c = mix(top, bot, t)
        for x in range(img.width):
            px[x, y] = ((c >> 16) & 255, (c >> 8) & 255, c & 255, 255)


def put_tile(img, name, bx, by):
    if name not in TILES:
        return
    t = build.to_image(TILES[name], SCALE)
    img.alpha_composite(t, (bx * PPB * SCALE, by * PPB * SCALE))


def put_sprite(img, name, fx, ground_by, frame=0, left=False):
    """A creature with its soles on the ground row `ground_by`, its middle at block column fx."""
    s = SPRITES[name]
    f = s.frames[frame].flipped() if left else s.frames[frame]
    im = build.to_image(f, SCALE)
    cx = (s.w - s.cx) if left else s.cx
    x = int(round(fx * PPB * SCALE - cx * SCALE))
    y = int(ground_by * PPB * SCALE - (s.foot + 1) * SCALE)
    img.alpha_composite(im, (x, y))


def scene(out, kind="meadow"):
    build.load_all()
    W, H = BW * PPB * SCALE, BH * PPB * SCALE
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    if kind == "night":
        sky(img, grade(0x060A1E), grade(0x18223E), H * 0.7)
    else:
        sky(img, grade(0x3E86D8), grade(0xB4DCFF), H * 0.7)
    ground = 11
    for bx in range(BW):
        put_tile(img, "grass", bx, ground)
        for by in range(ground + 1, ground + 3):
            put_tile(img, "dirt", bx, by)
        for by in range(ground + 3, BH):
            put_tile(img, "stone", bx, by)
    # two trees
    for tx, h, log, leaf in ((4, 5, "log", "leaves"), (27, 6, "log", "leaves"), (14, 4, "birchLog", "birchLeaves")):
        for by in range(ground - h, ground):
            put_tile(img, log, tx, by)
        top = ground - h
        for dy in (-3, -2, -1, 0):
            r = 1 if dy == -3 else 2
            for dx in range(-r, r + 1):
                put_tile(img, leaf, tx + dx, top + dy)
    for bx in (8, 9, 20, 23):
        put_tile(img, "tallGrass", bx, ground - 1)
    put_tile(img, "flowerR", 11, ground - 1)
    put_tile(img, "flowerY", 22, ground - 1)
    put_tile(img, "torch", 18, ground - 1)
    if kind == "night":
        cast = [("zombie", 21.5, 0, True), ("zombie_1", 24.0, 1, True), ("skeleton", 12.5, 0, False), ("slime", 26.5, 0, True), ("player", 17.0, 0, False)]
    else:
        cast = [("bear", 6.5, 0, False), ("cow", 10.5, 0, True), ("pig", 13.0, 0, False), ("player", 16.5, 9, False),
                ("chicken", 19.0, 0, True), ("sheep", 24.0, 0, True), ("wolf_1", 30.5, 0, False), ("tiger", 33.0, 0, True)]
    for name, x, fr, left in cast:
        if name in SPRITES:
            put_sprite(img, name, x, ground, min(fr, len(SPRITES[name].frames) - 1), left)
    img.convert("RGB").save(out)
    print(out, img.size)


if __name__ == "__main__":
    scene(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "meadow")
