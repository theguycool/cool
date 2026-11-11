"""Building blocks for PixelRealm's hand-drawn art (see tools/art/README.md).

A picture is drawn as rows of letters; a palette says what each letter paints ("." is clear).
Parts (a body, a head, a leg) are drawn once and laid over each other at offsets to make the
frames of an animation, so a creature stays the same from frame to frame. `outline` draws the dark
line round a part. Everything here works on small grids of colours: a pixel is 0xRRGGBB or None.
"""

SPRITES = {}      # name -> Sprite, filled by sprite()
TILES = {}        # tile name -> 16x16 grid of colours (None is clear)
TILE_FLIP = {}    # tile name -> "" (always drawn as it is), "h" (may be mirrored) or "hv" (mirrored and turned over)

PPB = 16          # art pixels per block of the world, for everything


def rows(text):
    """Rows of a picture written as a block of text (blank lines and indentation dropped)."""
    out = [ln.strip() for ln in text.strip("\n").split("\n")]
    out = [ln for ln in out if ln]
    w = max(len(r) for r in out)
    bad = ["row %d is %d wide" % (i, len(r)) for i, r in enumerate(out) if len(r) != w]
    if bad:
        raise ValueError("rows differ in width (widest %d): %s\n%s" % (w, ", ".join(bad), "\n".join(out)))
    return out


class Grid:
    """A small picture: w x h pixels, each 0xRRGGBB or None."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]
        self.m = 0          # the margin a part keeps for its outline
        self.edge = set()   # which pixels are that outline
        self.inner = None   # the softer colour the outline takes where it crosses another part

    def copy(self):
        g = Grid(self.w, self.h)
        g.px = [r[:] for r in self.px]
        g.m = self.m
        g.edge = set(self.edge)
        g.inner = self.inner
        return g

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return None

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def put(self, other, ox=0, oy=0):
        """Lays another picture on top. Where its outline crosses what is already there, the line
        is drawn in its softer `inner` colour: hard edges against the world, soft ones inside."""
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c is None:
                    continue
                if other.inner is not None and (x, y) in other.edge and self.get(ox + x, oy + y) is not None:
                    c = other.inner
                self.set(ox + x, oy + y, c)
        return self

    def flipped(self):
        g = Grid(self.w, self.h)
        g.px = [r[::-1] for r in self.px]
        g.m = self.m
        g.edge = set((self.w - 1 - x, y) for (x, y) in self.edge)
        g.inner = self.inner
        return g

    def bounds(self):
        xs = [x for y in range(self.h) for x in range(self.w) if self.px[y][x] is not None]
        ys = [y for y in range(self.h) for x in range(self.w) if self.px[y][x] is not None]
        if not xs:
            return (0, 0, self.w - 1, self.h - 1)
        return (min(xs), min(ys), max(xs), max(ys))

    def recolor(self, table):
        """The same picture with some colours swapped (a dict of old colour -> new)."""
        g = self.copy()
        for y in range(g.h):
            for x in range(g.w):
                c = g.px[y][x]
                if c in table:
                    g.px[y][x] = table[c]
        return g


def part(text, pal, outline=None, margin=1, open_top=False, open_bottom=False, inner=None, raw=False):
    """A part drawn as text. With `outline` (a colour) a one-pixel line is drawn round it, in a
    margin added on every side, so parts laid over each other keep their own edges. `open_top`
    leaves the line off above the part (a leg that joins the body there)."""
    rs = rows(text)
    h, w = len(rs), len(rs[0])
    m = margin if outline is not None else 0
    if not raw:
        # (raw: marker colours the game swaps for chosen ones, which it grades itself)
        pal = graded(pal)
        outline = grade(outline)
        inner = grade(inner)
    g = Grid(w + 2 * m, h + 2 * m)
    for y, r in enumerate(rs):
        for x, ch in enumerate(r):
            if ch in ". ":
                continue
            if ch not in pal:
                raise ValueError("letter %r is not in the palette (row %d: %s)" % (ch, y, r))
            g.px[y + m][x + m] = pal[ch]
    g.m = m
    g.inner = inner
    if outline is not None:
        before = [r[:] for r in g.px]
        add_outline(g, outline)
        if open_top:
            for x in range(g.w):
                g.px[0][x] = None
        if open_bottom:
            for x in range(g.w):
                g.px[g.h - 1][x] = None
        g.edge = set((x, y) for y in range(g.h) for x in range(g.w) if before[y][x] is None and g.px[y][x] is not None)
    return g


def add_outline(g, color, diagonal=False):
    """Paints every clear pixel that touches the picture (up, down, left, right)."""
    near = [(0, 1), (0, -1), (1, 0), (-1, 0)]
    if diagonal:
        near += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    todo = []
    for y in range(g.h):
        for x in range(g.w):
            if g.px[y][x] is not None:
                continue
            if any(g.get(x + dx, y + dy) is not None for dx, dy in near):
                todo.append((x, y))
    for x, y in todo:
        g.px[y][x] = color
    return g


def frame(w, h, layers):
    """One frame: parts laid down in order, each (part, x, y) with x, y where the top left corner
    of its drawing goes (its outline sits one pixel further out)."""
    g = Grid(w, h)
    for layer in layers:
        p, x, y = layer[0], layer[1], layer[2]
        g.put(p, x - p.m, y - p.m)
    return g


class Sprite:
    def __init__(self, name, frames, anim, foot=None, cx=None, like=None, note=""):
        self.name = name
        self.frames = frames
        self.anim = anim          # {"idle": [0], "walk": [1, 2, 3, 4], ...}
        self.w = frames[0].w
        self.h = frames[0].h
        for f in frames:
            if f.w != self.w or f.h != self.h:
                raise ValueError(name + ": frames differ in size")
        b = frames[0].bounds()
        self.foot = b[3] if foot is None else foot                 # row of the soles (stands on the ground)
        self.cx = (b[0] + b[2] + 1) / 2.0 if cx is None else cx    # column of the body's middle
        self.note = note


def sprite(name, frames, anim, foot=None, cx=None, note=""):
    s = Sprite(name, frames, anim, foot, cx, note=note)
    SPRITES[name] = s
    return s


def tile(name, text, pal, flip="", raw=False):
    """A block's picture. `flip` says how the game may vary it from place to place so a wall of it
    does not look like wallpaper: "h" mirrored left to right, "hv" also top to bottom (only for
    textures with no up or down and no light from one side)."""
    rs = rows(text)
    if not raw:
        pal = graded(pal)
    if len(rs) != PPB or any(len(r) != PPB for r in rs):
        raise ValueError("tile %s must be %dx%d (it is %dx%d)" % (name, PPB, PPB, len(rs[0]), len(rs)))
    g = Grid(PPB, PPB)
    for y, r in enumerate(rs):
        for x, ch in enumerate(r):
            if ch in ". ":
                continue
            if ch not in pal:
                raise ValueError("tile %s: letter %r is not in the palette" % (name, ch))
            g.px[y][x] = pal[ch]
    TILES[name] = g
    TILE_FLIP[name] = flip
    return g


# ---- colours ----

def mix(a, b, t):
    ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
    br, bg, bb = (b >> 16) & 255, (b >> 8) & 255, b & 255
    r = round(ar + (br - ar) * t)
    g = round(ag + (bg - ag) * t)
    bl = round(ab + (bb - ab) * t)
    return (r << 16) | (g << 8) | bl


def ramp(base, light=0xFFF0C8, dark=0x241A38):
    """Four tones of one colour: highlight (warmer), base, shadow and deep shadow (cooler)."""
    return [mix(base, light, 0.28), base, mix(mix(base, 0x000000, 0.22), dark, 0.18), mix(mix(base, 0x000000, 0.42), dark, 0.30)]


# ---- the game's colour grade ----
# Every colour drawn here goes through grade() on its way into a picture: strong colours lose some of
# their saturation and the brightest of them a little of their brightness, so the world reads earthy
# rather than candy-bright (the reference sheets' look). Greys and dark tones barely move. The game
# has the same function (artGrade in Swift) for what is still drawn in code and for colours a player
# picks; keep the two the same.
GRADE_SAT = 0.42      # how much saturation strong colours lose (s -> s * (1 - GRADE_SAT * s))
GRADE_VAL = 0.20      # how much bright strong colours darken (v -> v * (1 - GRADE_VAL * v * s))


def grade(c):
    if c is None:
        return None
    r, g, b = ((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0
    mx, mn = max(r, g, b), min(r, g, b)
    if mx <= 0 or mx == mn:
        return c
    s = (mx - mn) / mx
    v = mx
    # where the colour sits between its lowest and highest channel stays the same: only the spread
    # and the top move
    s2 = s * (1.0 - GRADE_SAT * s)
    v2 = v * (1.0 - GRADE_VAL * v * s)
    lo2 = v2 * (1.0 - s2)
    def ch(x):
        t = (x - mn) / (mx - mn)
        return int(round((lo2 + (v2 - lo2) * t) * 255.0))
    return (ch(r) << 16) | (ch(g) << 8) | ch(b)


def graded(pal):
    return {k: grade(v) for k, v in pal.items()}
