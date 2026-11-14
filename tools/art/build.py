#!/usr/bin/env python3
"""PixelRealm's art, from drawings to the game (see tools/art/README.md).

  build.py preview <out folder> [names...]   sheets of the drawings as PNG, large and at play size
  build.py dump <out folder>                 the drawings as raw pixels, for sheets.py compare
  build.py pack                              writes the drawings into the game's source as text
  build.py check                             says what the game's text would change, writes nothing

Drawings live in tools/art/creatures/*.py and tools/art/tiles/*.py; each file calls sprite(...)
or tile(...) from artlib.
"""
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "creatures"))
import artlib
from artlib import SPRITES, TILES, TILE_FLIP, PPB


def load_all():
    for folder in ("creatures", "tiles"):
        for f in sorted(glob.glob(os.path.join(HERE, folder, "*.py"))):
            if os.path.basename(f).startswith("_"):
                continue        # shared helpers, loaded by the drawings that use them
            src = open(f).read()
            env = {"__file__": f, "__name__": "art_" + os.path.basename(f)[:-3]}
            exec(compile("from artlib import *\n" + src, f, "exec"), env)


# ---- packing: the text the game reads ----

LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&*+<=>?@^_~"


def rle(seq):
    out = []
    i = 0
    while i < len(seq):
        j = i
        while j < len(seq) and seq[j] == seq[i]:
            j += 1
        n = j - i
        out.append((str(n) if n > 1 else "") + seq[i])
        i = j
    return "".join(out)


def pack_sprite(s, wrap=170):
    """A creature as lines of text: "name|w|h|foot|cx|colours|poses", then its frames (one after
    another with "/" between) on lines that start with "+", wrapped so no line is long."""
    colours = []
    for f in s.frames:
        for row in f.px:
            for c in row:
                if c is not None and c not in colours:
                    colours.append(c)
    if len(colours) > len(LETTERS):
        raise ValueError("%s uses %d colours (at most %d)" % (s.name, len(colours), len(LETTERS)))
    letter = {c: LETTERS[i] for i, c in enumerate(colours)}
    pal = ",".join("%s%06X" % (letter[c], c) for c in colours)
    poses = ";".join("%s:%s" % (k, ",".join(str(i) for i in v)) for k, v in s.anim.items())
    frames = []
    for f in s.frames:
        seq = "".join("." if c is None else letter[c] for row in f.px for c in row)
        frames.append(rle(seq))
    cx = ("%g" % s.cx)
    out = ["|".join([s.name, str(s.w), str(s.h), str(s.foot), cx, pal, poses])]
    body = "/".join(frames)
    for i in range(0, len(body), wrap):
        out.append("+" + body[i:i + wrap])
    return out


def pack_tile(name, g):
    colours = []
    for row in g.px:
        for c in row:
            if c is not None and c not in colours:
                colours.append(c)
    letter = {c: LETTERS[i] for i, c in enumerate(colours)}
    pal = ",".join("%s%06X" % (letter[c], c) for c in colours)
    seq = "".join("." if c is None else letter[c] for row in g.px for c in row)
    return "|".join([name, TILE_FLIP.get(name, ""), pal, rle(seq)])


def packed_text():
    cre = []
    for n in sorted(SPRITES):
        cre += pack_sprite(SPRITES[n])
    til = [pack_tile(n, TILES[n]) for n in sorted(TILES)]
    return cre, til


def inject(path, marker, lines, indent="\t\t"):
    """Replaces what is between `// <marker>` and `// </marker>` in a source file."""
    src = open(path).read()
    a = src.find("<" + marker + ">")
    b = src.find("</" + marker + ">")
    if a < 0 or b < 0:
        return None
    a_end = src.find("\n", a) + 1
    b_start = src.rfind("\n", 0, b) + 1
    body = "".join(indent + ln + "\n" for ln in lines)
    new = src[:a_end] + body + src[b_start:]
    return src, new


def game_files():
    """The game's parts, PixelRealm1.swift onwards (the art sheet is in one of them)"""
    return sorted(glob.glob(os.path.join(ROOT, "PixelRealm[0-9]*.swift")))


def pack(write=True):
    cre, til = packed_text()
    done = {"art:creatures": False, "art:tiles": False}
    for path in game_files():
        for marker, lines in (("art:creatures", cre), ("art:tiles", til)):
            r = inject(path, marker, lines)
            if r is None:
                continue
            done[marker] = True
            old, new = r
            if old != new:
                print("%s: %s %s (%d lines, %d bytes)" % (os.path.basename(path), marker, "written" if write else "would change", len(lines), sum(len(l) + 3 for l in lines)))
                if write:
                    open(path, "w").write(new)
            else:
                print("%s: %s is up to date (%d lines)" % (os.path.basename(path), marker, len(lines)))
    for m, ok in done.items():
        if not ok:
            print("no <%s> marker found in the game's source" % m)


# ---- pictures ----

def to_image(g, scale=1):
    from PIL import Image
    im = Image.new("RGBA", (g.w, g.h), (0, 0, 0, 0))
    px = im.load()
    for y in range(g.h):
        for x in range(g.w):
            c = g.px[y][x]
            if c is not None:
                px[x, y] = ((c >> 16) & 255, (c >> 8) & 255, c & 255, 255)
    if scale != 1:
        im = im.resize((g.w * scale, g.h * scale), Image.NEAREST)
    return im


def preview(out, names=None, big=8, small=3):
    from PIL import Image, ImageDraw
    os.makedirs(out, exist_ok=True)
    names = [n for n in (names or sorted(SPRITES)) if n in SPRITES]
    for n in names:
        s = SPRITES[n]
        k = big if max(s.w, s.h) <= 48 else max(3, big // 2)
        pad = 10
        W = pad + len(s.frames) * (s.w * k + pad)
        H = pad + s.h * k + 16 + s.h * small + 3 * pad
        W = max(W, 3 * (len(s.frames) * (s.w * small + 4) + pad) + pad)
        im = Image.new("RGBA", (W, H), (74, 69, 72, 255))
        d = ImageDraw.Draw(im)
        order = {}
        for pose, idx in s.anim.items():
            for i in idx:
                order.setdefault(i, []).append(pose)
        x = pad
        for i, f in enumerate(s.frames):
            im.alpha_composite(to_image(f, k), (x, pad))
            d.text((x, pad + s.h * k + 2), "%d %s" % (i, " ".join(order.get(i, []))), fill=(236, 232, 222))
            x += s.w * k + pad
        # at play size, on the kinds of ground they will stand in front of
        y0 = pad + s.h * k + 16 + pad
        x = pad
        for bg, floor in (((126, 184, 232), (74, 150, 60)), ((38, 34, 44), (70, 66, 74)), ((216, 200, 150), (190, 170, 110))):
            bw = len(s.frames) * (s.w * small + 4) + 4
            d.rectangle([x, y0, x + bw, y0 + s.h * small + pad], fill=bg + (255,))
            d.rectangle([x, y0 + (s.foot + 1) * small, x + bw, y0 + s.h * small + pad], fill=floor + (255,))
            xx = x + 4
            for f in s.frames:
                im.alpha_composite(to_image(f, small), (xx, y0))
                xx += s.w * small + 4
            x += bw + pad
        im.convert("RGB").save(os.path.join(out, n + ".png"))
    print("previews of", len(names), "creatures in", out)
    if TILES and not names_given(names):
        tile_sheet(out)


def names_given(names):
    return len(names) != len(SPRITES)


def tile_sheet(out, k=6):
    """Every drawn block alone, and as a 3 x 3 patch of itself to show seams and repeats."""
    from PIL import Image, ImageDraw
    names = sorted(TILES)
    pad = 12
    cell = PPB * k * 4 + pad * 2
    cols = max(1, min(6, len(names)))
    rws = (len(names) + cols - 1) // cols
    im = Image.new("RGBA", (pad + cols * (cell + pad), pad + rws * (PPB * k * 3 + 16 + pad)), (74, 69, 72, 255))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x = pad + (i % cols) * (cell + pad)
        y = pad + (i // cols) * (PPB * k * 3 + 16 + pad)
        t = to_image(TILES[n], k)
        im.alpha_composite(t, (x, y + PPB * k))
        for yy in range(3):
            for xx in range(3):
                im.alpha_composite(t, (x + PPB * k + pad + xx * PPB * k, y + yy * PPB * k))
        d.text((x, y + PPB * k * 3 + 2), n, fill=(236, 232, 222))
    im.convert("RGB").save(os.path.join(out, "_tiles.png"))
    print("tile sheet:", os.path.join(out, "_tiles.png"))


def dump(out):
    os.makedirs(out, exist_ok=True)
    man = []
    for n in sorted(SPRITES):
        s = SPRITES[n]
        raw = bytearray()
        for f in s.frames:
            for row in f.px:
                for c in row:
                    raw += bytes((0, 0, 0, 0)) if c is None else bytes(((c >> 16) & 255, (c >> 8) & 255, c & 255, 255))
        open(os.path.join(out, n + ".rgba"), "wb").write(raw)
        man.append("mob %s %d %d %d %g" % (n, s.w, s.h, len(s.frames), 1.0 / PPB))
    for n in sorted(TILES):
        g = TILES[n]
        raw = bytearray()
        for row in g.px:
            for c in row:
                raw += bytes((0, 0, 0, 0)) if c is None else bytes(((c >> 16) & 255, (c >> 8) & 255, c & 255, 255))
        open(os.path.join(out, n + ".rgba"), "wb").write(raw)
        man.append("tile %s %d %d 1 %g" % (n, g.w, g.h, 1.0 / PPB))
    open(os.path.join(out, "manifest.txt"), "w").write("\n".join(man) + "\n")
    print("wrote", len(man), "pictures to", out)


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(0)
    load_all()
    if a[0] == "preview":
        preview(a[1], a[2:] or None)
    elif a[0] == "dump":
        dump(a[1])
    elif a[0] == "pack":
        pack(True)
    elif a[0] == "check":
        pack(False)
    else:
        print(__doc__)
