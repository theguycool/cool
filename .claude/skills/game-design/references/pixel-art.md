# Making pixel art look good

## The rules that matter most

1. **One pixel size.** Every sprite, tile and font is drawn at the same pixel scale and shown at a
   whole-number multiple of it. Mixed pixel sizes ("mixels") look cheap. A far background may use
   bigger pixels on purpose, as a layer, never mixed inside one object.
2. **No smoothing.** Nearest-neighbour scaling only; no sub-pixel positions for sprites; the camera
   snaps to the art's pixels.
3. **A palette with jobs.** Pick a small palette (16 to 32 colours for a whole game, about 4 to 8 per
   sprite) and give colours roles: outline, shadow, mid, light, highlight, accent per material.
   Reuse the same ramps everywhere so the game hangs together.
4. **Hue shifting.** Make light colours warmer (toward yellow) and shadows cooler (toward blue or
   purple) instead of only darker. Straight darker-and-lighter ramps look muddy.
5. **Value first.** Squint or view it in greyscale: the player, enemies and hazards should stand
   out by value from the background. Backgrounds get a narrower, duller range than the foreground.
6. **Silhouette.** Fill a sprite with black: it should still be recognisable, and every enemy
   should have its own silhouette.
7. **One light direction** for the whole game (usually from above, a little to one side).

## Mistakes to avoid

- **Pillow shading**: shading from the outline inward on every side, as if lit from the front.
  Pick a light direction.
- **Banding**: rows of pixels of different shades running side by side in step. Break the steps.
- **Jaggies**: lines with uneven steps (1, 2, 1, 3). Keep steps regular (1-1-1, 2-2-2, 1-2-1-2), or
  vary them deliberately along a curve.
- **Too many colours**: noise. If two shades are barely different, merge them.
- **Doubles**: a line two pixels thick where one would do, or L-shaped corners on a thin line.
- **Pure black outlines everywhere**: use a darker shade of the inside colour (selective outlining),
  or keep black only for the outer silhouette.

## Tiles

- Check a tile in a 3 by 3 grid of itself: seams and repeating patterns show at once.
- Offset the tile by half its size to find seams and fix them in the middle.
- Make two or three variants of common tiles (grass, stone) and mix them by position.
- Edges and corners: tiles that meet air or another material need edge pieces, or the world looks
  like a grid of boxes.
- Keep the busiest detail off the tiles the player stands in front of; the background is quieter
  than the foreground.

## Animation

- Few frames, strong poses: a walk in 4 to 8 frames, an attack with a clear wind-up, strike and
  recover.
- Hold the key poses longer than the in-betweens.
- Squash and stretch, even by one pixel, give life.
- Secondary motion (hair, cape, a tail) a frame behind the body.
- Sub-pixel animation (shifting colours to suggest movement smaller than a pixel) for idles.

## Learning order (a short curriculum)

1. Clean lines and curves.
2. Light and shadow on simple shapes (sphere, cube, cylinder) with one light.
3. Colour ramps with hue shifting; build a palette.
4. Materials (wood, stone, metal, cloth, leaves) at 8 by 8 and 16 by 16.
5. Tiles that repeat without seams.
6. Characters: silhouette, then shading.
7. Walk cycles, then attacks.
8. Effects (sparks, smoke, fire, water).

## Checks before shipping art

- Greyscale test passed? Silhouette test passed? 3 by 3 tile test passed?
- Same pixel size everywhere, including text and the HUD?
- Same light direction everywhere?
- Every colour from the palette?
