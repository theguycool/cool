# UI and UX design for games

## Two jobs (Celia Hodent, *The Gamer's Brain*)

- **Usability**: can the player understand and use it without friction? (Clarity, feedback,
  consistency, low memory load, error prevention and recovery.)
- **Engage-ability**: does it make them want to keep going? (Motivation, emotion, flow.)
A screen must pass the first before the second matters.

## How players' minds limit the screen

- **Attention** is narrow: the player is looking at the action, not the corners. Put critical
  information near where the eyes already are, or make it move, flash or sound.
- **Working memory** holds about four things. Don't make players remember codes, numbers or which
  button was which; show it.
- **Hick's law**: more choices, slower decisions. Group and hide what isn't needed now.
- **Fitts's law**: big, near targets are faster to hit. Frequent actions get big buttons near the
  thumbs.

## Hierarchy

Rank what each screen shows: what must be seen at a glance (health, danger), what is checked often
(the hotbar, ammo), what is looked up (stats, recipes). Use size, contrast, colour, position,
spacing and motion to make the rank visible. One focal point per screen.

## Readability

- Text at least 28 px at 1080p on a TV; on an iPad, body text at least 13 to 15 points, labels
  never under 11. Offer a text size setting.
- Contrast at least 4.5:1 for text (WCAG AA); 3:1 for large text and icons.
- Never use colour alone: add a shape, icon, pattern or label (rarity, team, danger).
- Short labels in plain words. Numbers with units.
- Pixel fonts: draw them at whole multiples of their pixel size.

## Touch (iPad)

- Targets at least 44 by 44 points, with space between them.
- Thumb zones: frequent controls near the lower corners; nothing important under the palm.
- Drags and holds need feedback while they happen.
- Give a left-handed option (swap sides).
- Avoid actions that need precise taps on small world objects; snap the aim to the likely target.

## HUD styles

- **Diegetic** (in the world, seen by the character: a watch, a lamp's glow), **spatial** (in the
  world, not seen by the character: outlines, markers), **meta** (on the screen, part of the story:
  blood at the edges), **non-diegetic** (classic HUD bars). Use diegetic where it reads well; fall
  back to the HUD when clarity matters.
- Show what changes; hide what doesn't. Health can fade out when full.
- Let players turn parts of the HUD off and move them.

## Feedback

- Every action: something changes on screen right away.
- **Signifiers** show what can be done (a handle looks pullable), **feedforward** shows what will
  happen (a placement ghost, a trajectory line), **feedback** shows what happened.
- Errors in plain words that say what to do: "Too far, move closer" not "Invalid".
- Confirm in proportion to the stakes: no box for small things, undo for medium things, a held
  button or typed name for destroying a world.

## Menus and screens

- The top bar (the way back) is always visible; long pages scroll under it.
- The same action is in the same place on every screen.
- Remember the last tab, the last filter, the last item chosen.
- Inventories: sort, search, categories, quick move, show counts of what can be crafted.
- Hover/hold info everywhere: what it is, what it does, where it comes from, what it makes.

## Accessibility (cheap wins)

Text size, colour-blind safe palettes or patterns, reduce flashes, reduce shake, hold-to-toggle
options, remappable or movable controls, subtitles or captions for important sounds, difficulty and
assist options that don't shame the player.
