#!/usr/bin/env python3
"""Builds the Godot project's art, sound and data tables from the Swift game's export.

    tools/export.sh /tmp/prexport
    python3 tools/godot_assets.py /tmp/prexport godot/PixelRealm

Everything written here is generated: PNG sheets under assets/, WAV files under assets/sounds/, and the
data scripts under scripts/data/. The art the Swift game drew with shapes at run time (sun, moon,
projectiles, sticks, buttons, panels, icons) is drawn here as small pixel-art PNGs in the same palette.
"""
import json
import math
import os
import random
import re
import struct
import sys
import wave

from PIL import Image, ImageDraw

SRC = sys.argv[1] if len(sys.argv) > 1 else '/tmp/prexport'
PROJ = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'PixelRealm')
AS = os.path.join(PROJ, 'assets')
DATA = os.path.join(PROJ, 'scripts', 'data')


def mk(*parts):
    d = os.path.join(*parts)
    os.makedirs(d, exist_ok=True)
    return d


def buf(path):
    with open(os.path.join(SRC, path), 'rb') as f:
        w, h = struct.unpack('<II', f.read(8))
        return Image.frombytes('RGBA', (w, h), f.read(w * h * 4))


def load_json(name):
    with open(os.path.join(SRC, name)) as f:
        return json.load(f)


def save(img, *parts):
    path = os.path.join(*parts)
    mk(os.path.dirname(path))
    img.save(path, optimize=True)


def shade(c, f):
    return tuple(int(max(0, min(255, v * f))) for v in c[:3])


# ----------------------------------------------------------------------------------------------- tiles
tiles = load_json('tiles.json')
NT = len(tiles)
terrain = Image.new('RGBA', (4 * 8, NT * 8), (0, 0, 0, 0))
for t in tiles:
    im = buf('tiles/%d.rgba' % t['id'])
    for v in range(4):
        img = im.copy()
        if t['supports'] and t['opaque']:
            px = img.load()
            if v & 1:
                for x in range(8):
                    r, g, b, a = px[x, 0]
                    px[x, 0] = shade((r, g, b), 1.12) + (255,)
            if v & 2:
                for x in range(8):
                    r, g, b, a = px[x, 7]
                    px[x, 7] = shade((r, g, b), 0.7) + (255,)
        terrain.paste(img, (v * 8, t['id'] * 8))
save(terrain, AS, 'tiles', 'terrain.png')

walls_meta = load_json('walls.json')
walls = Image.new('RGBA', (7 * 8, 8), (0, 0, 0, 0))
for k in range(1, 8):
    walls.paste(buf('walls/%d.rgba' % k), ((k - 1) * 8, 0))
save(walls, AS, 'tiles', 'walls.png')

# ----------------------------------------------------------------------------------------------- items
items = load_json('items.json')
COLS = 16
rows = (len(items) + COLS - 1) // COLS
icons = Image.new('RGBA', (COLS * 16, rows * 16), (0, 0, 0, 0))
for it in items:
    im = buf('items/%d.rgba' % it['icon'])
    i = it['icon']
    ox = (i % COLS) * 16 + (16 - im.width) // 2
    oy = (i // COLS) * 16 + (16 - im.height) // 2
    icons.paste(im, (ox, oy), im)
save(icons, AS, 'items', 'icons.png')

# ----------------------------------------------------------------------------------------------- creatures
mobs = load_json('mobs.json')
creature_meta = {}
for m in mobs:
    key = m['key']
    vs = m['variants']
    cw = max(v['w'] for v in vs)
    chh = max(v['h'] for v in vs)
    nf = max(v['frames'] for v in vs)
    sheet = Image.new('RGBA', (cw * nf, chh * len(vs)), (0, 0, 0, 0))
    metas = []
    for vi, v in enumerate(vs):
        for fi in range(v['frames']):
            im = buf('mobs/%s_%d_%d.rgba' % (key, vi, fi))
            sheet.paste(im, (fi * cw, vi * chh))
        metas.append({'w': v['w'], 'h': v['h'], 'frames': v['frames'], 'foot': v['footRow'], 'center': v['centerCol'],
                      'idleAlt': v['idleAlt'], 'attack': v['attack'], 'hop': v['hop'], 'cycle': v['cycle']})
    save(sheet, AS, 'creatures', key + '.png')
    creature_meta[key] = {'cell': [cw, chh], 'variants': metas}

# ----------------------------------------------------------------------------------------------- player
player = load_json('player.json')
PW, PH, PF = player['w'], player['h'], player['frames']
base = Image.new('RGBA', (PW * PF, PH * 25), (0, 0, 0, 0))
for h in range(5):
    for s in range(5):
        for f in range(PF):
            base.paste(buf('player/base_%d_%d_%d.rgba' % (h, s, f)), (f * PW, (h * 5 + s) * PH))
save(base, AS, 'player', 'base.png')
ref = [buf('player/base_0_0_%d.rgba' % f) for f in range(PF)]
for slot in ['head', 'chest', 'legs']:
    sheet = Image.new('RGBA', (PW * PF, PH * 9), (0, 0, 0, 0))
    for tier in range(1, 10):
        for f in range(PF):
            im = buf('player/armor_%s_%d_%d.rgba' % (slot, tier, f))
            a = im.load()
            b = ref[f].load()
            out = Image.new('RGBA', (PW, PH), (0, 0, 0, 0))
            o = out.load()
            for y in range(PH):
                for x in range(PW):
                    if a[x, y] != b[x, y] and a[x, y][3] > 0:
                        o[x, y] = a[x, y]
            sheet.paste(out, (f * PW, (tier - 1) * PH))
    save(sheet, AS, 'player', 'armor_%s.png' % slot)

# ----------------------------------------------------------------------------------------------- clouds, hud, parts
clouds = load_json('clouds.json')
cloud_sizes = []
i = 0
while os.path.exists(os.path.join(SRC, 'clouds', '%d.rgba' % i)):
    im = buf('clouds/%d.rgba' % i)
    save(im, AS, 'sky', 'cloud_%02d.png' % i)
    cloud_sizes.append([im.width, im.height])
    i += 1
for name in ['heart_full', 'heart_empty', 'food_full', 'food_empty', 'bubble', 'shield']:
    save(buf('misc/%s.rgba' % name), AS, 'ui', name + '.png')
save(buf('misc/pirate_ship.rgba'), AS, 'sprites', 'pirate_ship.png')
parts = {}
for fn in sorted(os.listdir(os.path.join(SRC, 'parts'))):
    name = fn[:-5]
    parts[name] = buf('parts/' + fn)
    save(parts[name], AS, 'sprites', 'parts', name + '.png')


def compose(cells, w, h):
    img = Image.new('RGBA', (w * 8, h * 8), (0, 0, 0, 0))
    for (name, cx, cy) in cells:
        p = parts[name]
        img.paste(p, (int(cx * 8), int(cy * 8)), p)
    return img


save(compose([('frame', 0, 1), ('frame', 1, 1), ('frame', 2, 1), ('frame', 3, 1), ('seat', 1, 0), ('steering', 2, 0),
              ('engine', 3, 0), ('wheel', 0, 1.5), ('wheel', 3, 1.5)], 4, 3), AS, 'sprites', 'car.png')
save(compose([('hull', 0, 1), ('hull', 1, 1), ('hull', 2, 1), ('hull', 3, 1), ('seat', 1, 0), ('paddle', 2, 0)], 4, 2),
     AS, 'sprites', 'boat.png')
save(compose([('hull', 0, 1), ('hull', 1, 1), ('hull', 2, 1), ('hull', 3, 1), ('seat', 1, 0), ('steering', 2, 0),
              ('engine', 0, 0), ('propeller', 0, 1.5)], 4, 3), AS, 'sprites', 'motorboat.png')

# ----------------------------------------------------------------------------------------------- sound
snd = load_json('sound.json')
RATE = int(snd['rate'])


def write_wav(samples_path, out_path):
    with open(os.path.join(SRC, samples_path), 'rb') as f:
        raw = f.read()
    n = len(raw) // 4
    fl = struct.unpack('<%df' % n, raw)
    pcm = struct.pack('<%dh' % n, *[int(max(-1.0, min(1.0, v)) * 32000) for v in fl])
    mk(os.path.dirname(out_path))
    with wave.open(out_path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


for name in snd['sfx']:
    for v in range(3):
        write_wav('sfx/%s_%d.f32' % (name, v), os.path.join(AS, 'sounds', 'sfx', '%s_%d.wav' % (name, v)))
for name in snd['loops']:
    write_wav('loops/%s.f32' % name, os.path.join(AS, 'sounds', 'loops', '%s.wav' % name))

# ----------------------------------------------------------------------------------------------- new pixel art
# Everything below was drawn with shapes at run time in the Swift game; here it becomes real sprites in
# the same palette: one-pixel dark outlines, two or three tones per colour, no anti-aliasing.
OUT = (16, 16, 20, 255)


def canvas(w, h):
    return Image.new('RGBA', (w, h), (0, 0, 0, 0))


def disc(d, cx, cy, r, col):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                d.point((x, y), col)


def outline(img, col=OUT):
    w, h = img.size
    src = img.load()
    out = img.copy()
    o = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and src[xx, yy][3] > 0:
                    o[x, y] = col
                    break
    return out


def from_rows(rows, pal):
    h = len(rows)
    w = max(len(r) for r in rows)
    img = canvas(w, h)
    p = img.load()
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in pal:
                p[x, y] = pal[ch]
    return img


# sky
sun = canvas(24, 24)
d = ImageDraw.Draw(sun)
disc(d, 12, 12, 11.5, (255, 230, 128, 60))
disc(d, 12, 12, 9.5, (255, 230, 128, 110))
disc(d, 12, 12, 7.5, (255, 200, 60, 255))
disc(d, 12, 12, 6.0, (255, 216, 74, 255))
disc(d, 11, 11, 3.5, (255, 242, 160, 255))
save(sun, AS, 'sky', 'sun.png')
moon = canvas(16, 16)
d = ImageDraw.Draw(moon)
disc(d, 8, 8, 7.5, (200, 210, 230, 70))
disc(d, 8, 8, 6.0, (232, 236, 244, 255))
for (cx, cy, r) in ((6, 6, 1.6), (10, 9, 1.3), (7, 11, 1.0)):
    disc(d, cx, cy, r, (192, 198, 208, 255))
save(moon, AS, 'sky', 'moon.png')
save(from_rows(['.w.', 'www', '.w.'], {'w': (255, 255, 255, 255)}), AS, 'sky', 'star.png')

# projectiles (pointing right)
save(outline(from_rows(['ff.......', 'fssssssHh', 'ff.......'],
                       {'f': (240, 240, 240, 255), 's': (150, 100, 50, 255), 'H': (180, 184, 190, 255), 'h': (230, 232, 236, 255)})),
     AS, 'sprites', 'projectiles', 'arrow.png')
save(outline(from_rows(['ffssssssHh', 'ffssssssHH'],
                       {'f': (200, 60, 50, 255), 's': (120, 80, 40, 255), 'H': (150, 155, 165, 255), 'h': (220, 224, 230, 255)})),
     AS, 'sprites', 'projectiles', 'bolt.png')
save(from_rows(['.gg.', 'gGGg', '.gg.'], {'g': (60, 60, 66, 255), 'G': (150, 150, 160, 255)}), AS, 'sprites', 'projectiles', 'bullet.png')
save(outline(from_rows(['.ss.', 'sSss', 'ssss', '.ss.'], {'s': (128, 128, 136, 255), 'S': (176, 176, 184, 255)})),
     AS, 'sprites', 'projectiles', 'stone.png')
save(outline(from_rows(['...f.', '..f..', '.bbb.', 'bBbbb', 'bbbbb', '.bbb.'],
                       {'f': (240, 200, 90, 255), 'b': (40, 40, 48, 255), 'B': (110, 110, 124, 255)})),
     AS, 'sprites', 'projectiles', 'bomb.png')
save(outline(from_rows(['.c.', '.n.', 'ooo', 'oOo', 'ooo'],
                       {'c': (150, 100, 60, 255), 'n': (200, 220, 230, 255), 'o': (240, 110, 40, 255), 'O': (255, 200, 120, 255)})),
     AS, 'sprites', 'projectiles', 'flask.png')
save(from_rows(['.oo.', 'oYYo', 'oYYo', '.oo.'], {'o': (255, 110, 30, 255), 'Y': (255, 230, 140, 255)}), AS, 'sprites', 'projectiles', 'fireball.png')
save(from_rows(['.c.', 'cWc', '.c.'], {'c': (90, 220, 255, 255), 'W': (230, 255, 255, 255)}), AS, 'sprites', 'projectiles', 'shard.png')
save(from_rows(['.vv.', 'vVVv', 'vVVv', '.vv.'], {'v': (150, 70, 230, 255), 'V': (230, 200, 255, 255)}), AS, 'sprites', 'projectiles', 'orb.png')

# effects
save(from_rows(['ww', 'ww'], {'w': (255, 255, 255, 255)}), AS, 'fx', 'particle.png')
save(from_rows(['.w.', 'www', '.w.'], {'w': (255, 255, 255, 255)}), AS, 'fx', 'spark.png')
smoke = canvas(8, 8)
d = ImageDraw.Draw(smoke)
disc(d, 4, 4, 3.8, (255, 255, 255, 90))
disc(d, 4, 4, 2.6, (255, 255, 255, 150))
save(smoke, AS, 'fx', 'smoke.png')
glow = canvas(32, 32)
d = ImageDraw.Draw(glow)
for r, a in ((15.5, 40), (12, 70), (8.5, 110), (5, 170)):
    disc(d, 16, 16, r, (255, 255, 255, a))
save(glow, AS, 'fx', 'glow.png')
save(from_rows(['b', 'b', 'B', 'B'], {'b': (170, 200, 240, 150), 'B': (200, 220, 250, 200)}), AS, 'fx', 'rain.png')
save(from_rows(['ww', 'ww'], {'w': (250, 252, 255, 230)}), AS, 'fx', 'snow.png')
save(from_rows(['hH', 'Hh'], {'h': (210, 228, 250, 255), 'H': (250, 252, 255, 255)}), AS, 'fx', 'hail.png')
crack = canvas(40, 8)
cp = crack.load()
for st in range(5):
    rnd = random.Random(st + 3)
    for _ in range(3 + st * 4):
        cp[st * 8 + rnd.randrange(8), rnd.randrange(8)] = (16, 16, 16, 255)
    dd = ImageDraw.Draw(crack)
    if st >= 2:
        dd.line([(st * 8 + 1, 2), (st * 8 + 6, 5)], fill=(16, 16, 16, 255))
    if st >= 3:
        dd.line([(st * 8 + 5, 0), (st * 8 + 2, 7)], fill=(16, 16, 16, 255))
save(crack, AS, 'fx', 'crack.png')


# ui: sticks, buttons, panels, slots, icons
def ring_img(size, r_out, fill, ring, notch):
    img = canvas(size, size)
    d = ImageDraw.Draw(img)
    c = size / 2
    disc(d, c, c, r_out, ring)
    disc(d, c, c, r_out - 2, fill)
    p = img.load()
    for k in range(8):
        a = k * math.pi / 4
        for rr in (r_out - 7, r_out - 6, r_out - 5):
            x = int(c + math.cos(a) * rr)
            y = int(c + math.sin(a) * rr)
            p[x, y] = notch
    dz = r_out * 0.26
    for k in range(48):
        a = k * math.pi * 2 / 48
        p[int(c + math.cos(a) * dz), int(c + math.sin(a) * dz)] = notch
    return img


save(ring_img(64, 31, (0, 0, 0, 70), (220, 222, 232, 150), (255, 255, 255, 90)), AS, 'ui', 'stick_base.png')
save(ring_img(64, 31, (42, 26, 12, 90), (224, 176, 96, 180), (255, 236, 190, 100)), AS, 'ui', 'stick_base_attack.png')


def thumb_img(col, hi, lo):
    img = canvas(26, 26)
    d = ImageDraw.Draw(img)
    disc(d, 13, 13, 12.5, (20, 20, 24, 160))
    disc(d, 13, 13, 11, lo)
    disc(d, 12, 12, 9.5, col)
    disc(d, 10, 9, 4, hi)
    return img


save(thumb_img((236, 236, 242, 190), (255, 255, 255, 220), (170, 170, 180, 190)), AS, 'ui', 'stick_thumb.png')
save(thumb_img((255, 200, 80, 220), (255, 236, 170, 240), (190, 130, 40, 220)), AS, 'ui', 'stick_thumb_attack.png')
save(from_rows(['a.....', 'aaa...', 'aaaaa.', 'aaaaaa', 'aaaaa.', 'aaa...', 'a.....'], {'a': (255, 224, 128, 230)}), AS, 'ui', 'stick_arrow.png')


def box(w, h, fill, border, top, bottom, b=1):
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=border)
    d.rectangle([b, b, w - 1 - b, h - 1 - b], fill=fill)
    d.rectangle([b, b, w - 1 - b, b], fill=top)
    d.rectangle([b, h - 1 - b, w - 1 - b, h - 1 - b], fill=bottom)
    return img


save(box(12, 12, (190, 190, 196, 255), (12, 12, 16, 255), (236, 236, 240, 255), (120, 120, 128, 255)), AS, 'ui', 'button.png')
save(box(12, 12, (140, 140, 146, 255), (12, 12, 16, 255), (110, 110, 118, 255), (170, 170, 176, 255)), AS, 'ui', 'button_pressed.png')
save(box(16, 16, (40, 42, 52, 235), (12, 12, 16, 255), (70, 72, 86, 235), (28, 28, 36, 235), 2), AS, 'ui', 'panel.png')
save(box(16, 16, (232, 212, 160, 255), (90, 58, 26, 255), (244, 230, 190, 255), (200, 176, 120, 255), 2), AS, 'ui', 'parchment.png')
save(box(20, 20, (0, 0, 0, 140), (120, 120, 132, 170), (0, 0, 0, 140), (0, 0, 0, 140)), AS, 'ui', 'slot.png')
sel = box(20, 20, (0, 0, 0, 140), (255, 255, 255, 255), (0, 0, 0, 140), (0, 0, 0, 140))
ImageDraw.Draw(sel).rectangle([1, 1, 18, 18], outline=(255, 255, 255, 255))
save(sel, AS, 'ui', 'slot_selected.png')
save(box(8, 6, (192, 40, 40, 255), (16, 16, 20, 255), (240, 90, 90, 255), (140, 24, 24, 255)), AS, 'ui', 'bar_fill.png')
save(box(8, 6, (16, 16, 20, 200), (240, 240, 240, 200), (16, 16, 20, 200), (16, 16, 20, 200)), AS, 'ui', 'bar_back.png')

W_ = (255, 255, 255, 255)
icon_rows = {
    'jump': ['....W....', '...WWW...', '..WWWWW..', '.WWWWWWW.', '...WWW...', '...WWW...', '...WWW...'],
    'pause': ['WW..WW', 'WW..WW', 'WW..WW', 'WW..WW', 'WW..WW', 'WW..WW'],
    'swap': ['...W....', '..WWWWWW', '...W....', '........', '....W...', 'WWWWWW..', '....W...'],
    'close': ['W....W', '.W..W.', '..WW..', '..WW..', '.W..W.', 'W....W'],
    'map': ['WWWWWWWW', 'W.W..W.W', 'W..WW..W', 'W.W..W.W', 'W..W...W', 'WWWWWWWW'],
    'book': ['.WWWWWW', 'W.....W', 'W.WWW.W', 'W.....W', 'W.WWW.W', 'W.....W', '.WWWWWW'],
    'down': ['.WWW.', '.WWW.', 'WWWWW', '.WWW.', '..W..'],
    'gear': ['..W.W..', '.WWWWW.', 'WWW.WWW', '.W...W.', 'WWW.WWW', '.WWWWW.', '..W.W..'],
    'sort': ['W.....', 'WWW...', 'WWWWW.', '......', 'WWWWW.', 'WWW...', 'W.....'],
    'craft': ['WWWW...', 'WWWWW..', '..WWWW.', '...W.W.', '..W....', '.W.....', 'W......'],
    'fly': ['W.....W', 'WW...WW', '.WWWWW.', '..WWW..', '...W...'],
    'save': ['WWWWWW.', 'W.WW.WW', 'W.WW..W', 'W.....W', 'W.WWW.W', 'W.WWW.W', 'WWWWWWW'],
}
for name, rows_ in icon_rows.items():
    save(outline(from_rows(rows_, {'W': W_})), AS, 'ui', 'icon_' + name + '.png')

# title: a small block font, drawn big
GLYPHS = {
    'P': ['WWWW', 'W..W', 'WWWW', 'W...', 'W...'], 'I': ['WWW', '.W.', '.W.', '.W.', 'WWW'],
    'X': ['W...W', '.W.W.', '..W..', '.W.W.', 'W...W'], 'E': ['WWWW', 'W...', 'WWW.', 'W...', 'WWWW'],
    'L': ['W...', 'W...', 'W...', 'W...', 'WWWW'], 'R': ['WWWW', 'W..W', 'WWWW', 'W.W.', 'W..W'],
    'A': ['.WW.', 'W..W', 'WWWW', 'W..W', 'W..W'], 'M': ['W...W', 'WW.WW', 'W.W.W', 'W...W', 'W...W'],
    ' ': ['..', '..', '..', '..', '..'],
}
text = 'PIXEL REALM'
gw = sum(len(GLYPHS[c][0]) + 1 for c in text)
logo = canvas(gw + 2, 8)
lp = logo.load()
x0 = 1
for c in text:
    g = GLYPHS[c]
    for y, r in enumerate(g):
        for x, ch in enumerate(r):
            if ch == 'W':
                lp[x0 + x, y + 1] = (255, 216, 74, 255) if y < 2 else ((240, 160, 50, 255) if y < 4 else (200, 110, 30, 255))
    x0 += len(g[0]) + 1
logo = outline(logo, (40, 20, 10, 255))
save(logo, AS, 'ui', 'logo.png')

# the app icon: the hero on a sky-blue tile with a strip of grass
icon = Image.new('RGBA', (32, 32), (62, 134, 216, 255))
d = ImageDraw.Draw(icon)
d.rectangle([0, 24, 31, 31], fill=(122, 82, 48, 255))
d.rectangle([0, 22, 31, 24], fill=(93, 170, 58, 255))
hero = buf('player/base_0_0_0.rgba')
icon.paste(hero, (5, 6), hero)
icon = icon.resize((128, 128), Image.NEAREST)
icon.save(os.path.join(PROJ, 'icon.png'))


# ----------------------------------------------------------------------------------------------- data scripts
def gd(v):
    if v is None:
        return 'null'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return '%d.0' % int(v)
        s = ('%.6f' % v).rstrip('0')
        return s + '0' if s.endswith('.') else s
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return '[' + ', '.join(gd(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{' + ', '.join('%s: %s' % (gd(str(k)), gd(x)) for k, x in v.items()) + '}'
    raise TypeError(type(v))


def snake(name):
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', name)
    return s.upper()


HEADER = '# Generated by tools/godot_assets.py from the Swift game. Do not edit by hand.\n'
mk(DATA)
with open(os.path.join(DATA, 't.gd'), 'w') as f:
    f.write(HEADER + '## Tile ids (the raw values of the Swift Tile enum, so they never change).\nclass_name T\n\n')
    seen = set()
    for t in tiles:
        n = snake(t['key'])
        assert n not in seen, n
        seen.add(n)
        f.write('const %s := %d\n' % (n, t['id']))
    f.write('const COUNT := %d\n' % NT)


def write_table(fname, doc, entries):
    with open(os.path.join(DATA, fname), 'w') as f:
        f.write(HEADER + '## ' + doc + '\n\n')
        for name, value in entries:
            if isinstance(value, list) and value and isinstance(value[0], dict):
                f.write('const %s := [\n' % name)
                for e in value:
                    f.write('\t%s,\n' % gd(e))
                f.write(']\n\n')
            else:
                f.write('const %s := %s\n\n' % (name, gd(value)))


tile_rows = []
for t in tiles:
    tile_rows.append({k: t[k] for k in ['id', 'key', 'name', 'hard', 'tier', 'solid', 'opaque', 'light', 'liquid', 'platform',
                                        'plant', 'hurt', 'noDrop', 'toolClass', 'leaf', 'log', 'supports', 'needsSupport',
                                        'placed', 'sound', 'power', 'weatherDevice', 'color']}
                     | {'drop': t.get('drop', '')})
write_table('tiles_data.gd', 'Every tile: name, hardness, tool tier, collision, light and what it drops.', [('TILES', tile_rows)])
write_table('walls_data.gd', 'Background walls (kind 1..7).', [('WALLS', walls_meta)])

item_rows = []
for it in items:
    e = dict(it)
    item_rows.append(e)
write_table('items_data.gd', 'Every item with its stats; "icon" is its cell in assets/items/icons.png (16 per row).',
            [('ITEMS', item_rows)])
write_table('recipes_data.gd', 'Every recipe: output, count, cost [[item, n]...], station and category.',
            [('RECIPES', load_json('recipes.json'))])

mob_rows = []
for m in mobs:
    e = {k: m[k] for k in ['id', 'key', 'name', 'w', 'h', 'hp', 'speed', 'dmg', 'behavior', 'flying', 'aggro', 'jump', 'hostile',
                           'predator', 'thinks', 'humanoid']}
    e['art'] = creature_meta[m['key']]
    mob_rows.append(e)
write_table('mobs_data.gd', 'Every creature: size, health, speed, damage, behaviour and its sprite sheet layout.', [('MOBS', mob_rows)])

misc = load_json('misc.json')
write_table('misc_data.gd', 'Biomes, tiers, the player sprite layout, clouds and sounds.', [
    ('BIOMES', misc['biomes']),
    ('TIERS', misc['tiers']),
    ('HAIR', misc['hair']),
    ('SCARF', misc['scarf']),
    ('HOTBAR', misc['hotbar']),
    ('BAG', misc['bag']),
    ('PLAYER', {'w': PW, 'h': PH, 'frames': PF, 'foot': player['footRow'], 'center': player['centerCol']}),
    ('CLOUD_CLASSES', clouds['classes']),
    ('CLOUD_SIZES', cloud_sizes),
    ('SFX', snd['sfx']),
    ('LOOPS', snd['loops']),
])

# loot dropped by creatures, read straight from the Swift mobDrops function
swift = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'PixelRealm.swift')).read()
m = re.search(r'func mobDrops\(.*?\n    switch k \{\n(.*?)\n    \}\n', swift, re.S)
loot = {}
item_ids = {it['id'] for it in items}


def swift_item(expr):
    expr = expr.strip()
    mm = re.match(r'^\.(\w+)(?:\((.*)\))?$', expr)
    if not mm:
        return None
    head, args = mm.group(1), mm.group(2)
    if args is None:
        return head
    parts_ = [a.strip().lstrip('.') for a in args.split(',')]
    return head + ':' + ':'.join(parts_)


for line in m.group(1).split('\n'):
    cm = re.match(r'\s*case \.(\w+):(.*)$', line)
    if not cm:
        continue
    kind, body = cm.group(1), cm.group(2)
    entries = []
    for am in re.finditer(r'add\((\.\w+(?:\([^()]*\))?), (\d+), (\d+), ([0-9.]+)\)', body):
        iid = swift_item(am.group(1))
        cond = 'sheared' if '!sheared' in body[:am.start()] and kind == 'sheep' and 'wool' in iid else ''
        assert iid in item_ids, (kind, iid)
        entries.append([iid, int(am.group(2)), int(am.group(3)), float(am.group(4)), cond])
    loot[kind] = entries
write_table('loot_data.gd', 'What each creature drops: [item, min, max, chance, condition].', [('MOB_DROPS', loot)])

# check every recipe and loot item exists
for r in load_json('recipes.json'):
    assert r['out'] in item_ids, r['out']
    for c in r['cost']:
        assert c[0] in item_ids, c[0]
print('assets: %d tiles, %d items, %d creatures, %d sounds; data scripts in %s' % (NT, len(items), len(mobs), len(snd['sfx']) * 3, DATA))
