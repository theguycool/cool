# PixelRealm's hand-drawn art

Creatures, the player and blocks are drawn here at **16 pixels to a block** and packed into the game
as text (`ArtSheet`, the `a01_artsheet` section at the end of `PixelRealm1.swift`). The game only reads that text; these tools
make it.

```
tools/art.sh preview [folder] [names...]   look at the drawings (PNG sheets)
tools/art.sh pack                          write them into the game
tools/art.sh check                         is the game's text up to date?
tools/art.sh game [folder]                 the pictures the game ends up with (raw pixels)
tools/art.sh compare <old dump> out.png    a before / after sheet
```

After changing a drawing: `preview`, look, `pack`, then `tools/typecheck.sh` and
`tools/run-tests.sh art`. `tools/shots.sh art` draws the art in the world.

## The look

- **One pixel size**: 16 art pixels a block for everything drawn here. (Older pictures made in code
  are 8 a block and are drawn doubled until each is redrawn.)
- **A dark line round every shape**, never pure black: a very dark shade of the creature. Where one
  part crosses another (a leg over the belly, the head over the body) the line is softer (`inner`).
- **Three or four tones a material**: a warm light, the colour, a shadow and a deep shadow that lean
  cool (`ramp`). Tones sit in clusters; no speckle, no dithering.
- **Earthy, not candy-bright**: every colour goes through `grade()` on its way into a picture (strong
  colours lose some saturation, the brightest of them a little brightness). The game has the same
  function (`artGrade`) for what it still draws in code and for colours the player picks; keep
  `GRADE_SAT` and `GRADE_VAL` the same in both. Pass `raw=True` only for marker colours.
- **Light from the upper left.** Light tones on top and left, shadows under and right.
- **A face that reads**: a dark eye with one bright pixel, a mouth or muzzle, and the feature that
  names the creature (a pig's snout, a skull's socket, a bear's brow and nose).
- **A shape of its own**: fill the creature black and it should still be told from the others.
- Sprites are about as tall as their hit boxes (`tools/tests/art` checks this).

## Creatures (`creatures/*.py`)

A creature is built from **parts** drawn as rows of letters, with a palette saying what each letter
paints (`.` is clear):

```python
head = part("""
..pp........
.pspp.......
""", pal, outline=K, inner=pal["d"])
```

`part` draws the dark line round it (`open_top=True` leaves it off where a leg joins the body).
Frames are parts laid in order at offsets, so the creature is the same in every frame:

```python
frame(30, 18, [(far_leg, 8, 12), (body, 1, 3), (near_leg, 5, 12), (head, 16, 2)])
sprite("pig", frames, {"idle": [0], "walk": [1, 2, 3, 4], "alt": [5]}, foot=16, cx=11.5)
```

- The name is the creature's `MobKind` case (`zombie`, `polarBear`); a variant adds `_1`, `_2`.
- `foot` is the row of the soles (the outline under them sinks into the ground); `cx` is the column
  of the body's middle, which stands over the middle of the hit box.
- Poses the game knows: `idle` (always frame 0), `walk` (four frames), `alt` (grazing, pecking),
  `strike`, `windup`, `block`, `shoot`, `fire` (the gunner's shot), `throw` (the golem's rock),
  `charge` (the sentinel), `cast` (the Warden), `rear` (Ursavor), `hop` (in the air), `fly` (a loop),
  `front` (the player). `WorldRenderer.mobFrame` picks them by what the creature is doing.
- `_human.py` holds what two-legged creatures share (leg poses and how a figure is put together).
- The player (`player.py`) is drawn in layers: `player` is the bare figure, and each hair, shirt and
  trouser style, the scarf and the helmet is a drawing of only what it changes, frame for frame
  (`player_hair_2`, `player_shirt_1`, ...), worked out by drawing the figure with and without it. All
  are painted in marker colours the game swaps for the chosen ones (`PlayerInk` in the game must list
  the same colours). `player_sheet.py <out.png>` draws every style dressed. A new style goes at the end
  of its list (saved settings point into it) and needs its name in the game's style list.
- Other people are drawn on the player's figure so everyone has one build: `pirate.py` calls
  `player.side(..., extra=...)`, which hands back where the torso and head go and takes parts to add
  behind, over the head, under the near hand (a grip the fist closes over) and in front; `player.fist`
  says where the fist is in each arm pose.
- Big creatures (`ursavor.py`, `rex.py`) work their bodies out from an outline (points along the top
  and the belly, lit from above, with fur strokes or stripes), and draw their heads, legs and claws by
  hand; thin legs (`crawler.py`) and long shafts (`warden.py`) are drawn as lines.

## Blocks (`tiles/*.py`)

`tile(name, rows, palette, flip)` draws a 16 x 16 block named after its `Tile` case. It must repeat
without seams: `preview` shows each as a 3 x 3 patch. `flip` lets the land painter vary a block from
place to place so a wall of it is not wallpaper: `"h"` mirrored, `"hv"` also turned over (only for
textures with no up, down or lit side: soil, stone, sand, ores). Families share one drawing with
other colours (`swap`, `log`, `leaves`, `ore`).

## Not yet redrawn

Every creature has a drawing. Blocks without one (machines, furniture, about 170), item icons, vehicle
parts and the suit keep their older pictures. To redraw one, add its file, `pack`, and run the `art`
suite.
