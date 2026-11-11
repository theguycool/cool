# PixelRealm: design review and plan

This applies the game design skill (`.claude/skills/game-design`) to PixelRealm. It lists what the
game already does well, where the techniques point to gaps, and steps in order of value for effort.
Nothing here is built yet; each step is sized to be checked on the iPad on its own.

## Pillars (proposed)

1. **A world that reacts.** Weather, light, weight, power and creatures follow rules that combine.
2. **Build anything, then use it.** Houses, machines, vehicles, suits, and mods of your own.
3. **Go further, come home richer.** Each trip out (deeper, farther, another dimension) is a risk
   that pays back at a safe home.

Every new step should serve at least one of these.

## Loops today

| Scale | What the player does now |
|---|---|
| Action | mine, place, swing, shoot, jump; hit stop, shake, particles, white hit flash |
| Goal | a mining trip, a house, a vehicle, a storm sat out, a boss attempt |
| Session | the journal's GOALS chain: workbench, anvil, old mine, grotto, Ursavor, the gate, Tyrannax, Sentinels, the citadel, the Warden, the Sigil, relics |
| Arc | every boss and realm, a base with power and machines, suits and vehicles, mods |

## What already follows the techniques

- **Forgiving controls**: coyote time (0.11 s) and jump buffering (0.13 s); hit stop on solid hits
  (0.03 to 0.07 s); shake with an intensity setting; a placement preview (feedforward); a throw
  trajectory line; camera dead zone, look-ahead and smoothing.
- **Rules, not encounters**: weather that moves blocks and hurts creatures, block weight and blasts,
  structural physics, power networks, potions on creatures, infusions, suits with parts that
  work by thrust and weight, vehicles flown by real airflow.
- **Progression gates that show ahead**: the Portal Key, the sealed gate, the Umbral Realm, the rift
  forge; the journal names each goal and where to look.
- **Home is safe**: lamplight keeps monsters away by the real light; beds set the spawn.
- **Fair failure**: items are kept on death by default; hardcore is a chosen mode; a mod can make
  the bag drop.
- **Players as creators**: the Mod Creator is a full content pipeline; tables as text keep the
  game's own content cheap to add.
- **Information everywhere**: item info, live crafting counts, the item browser.
- **Subtracting**: peaceful mode, night danger, every kind of weather can be switched off, reduce
  flashes, shake intensity.

## Gaps the techniques point to

1. **The help screen is a wall of text** (about twenty long lines). Onboarding works best as doing
   first, short words, one thing at a time, when it is needed.
2. **The next goal is hidden in the journal.** Players who don't know what to do next quit; the
   goal should be visible during play.
3. **The first night has no goal of its own.** The chain starts at the workbench; the first real
   danger (night) is not named as a goal, and there is no warning at dusk.
4. **Systems arrive without a first time.** Power, vehicles, suits, alchemy and infusions are deep,
   but each is met through a recipe and an info line. Each needs a small first success.
5. **Items say what they are, not what they lead to.** Recipes should point ahead ("used to make
   a furnace, torches, an anvil").
6. **No text size setting**, and the left-handed swap only exists in mod themes.
7. **Pixel size is mixed on purpose**: the suit is drawn three times finer than everything else.
   It reads as detail now; keep an eye on it, and don't spread finer pixels to other things.
8. **No reason the world differs from day to day** apart from the weather; no shared challenge.
9. **No measure of the economy**: which resources pile up unused and which run short is not known.

## Steps, in order of value for effort

Each step is small enough to check on the iPad. Sizes are rough (S: a day's work here, M: a few,
L: a week).

### 1. Goal tracker on the HUD (S) — pillars 2 and 3
One line under the hearts with the journal's current goal and a small arrow when its place is
known. Tap it to open the journal. Fades while fighting; can be turned off in settings. Uses the
existing `journalAims()`.

### 2. First-night goals and dusk warning (S) — pillar 3
Add three goals before the workbench: make a torch, build a shelter (walls and a roof around you),
eat something. A short line at dusk ("Night is coming: get under a roof"), once a night for the
first three nights, then only if the player is out in the open. Uses `say(...)` and the journal.

### 3. Contextual first-time tips (M) — teaching
Show a tip the first time a situation happens, at most about eight words with an icon, once, and
keep it in a new TIPS page of the journal: first ore, first cave, first night, first storm, first
hurt, first chest, first station, first wire, first vehicle part, first potion, first suit piece.
The help screen stays, split into short pages, for players who want to read. Saved as a set of
seen tips (a new optional `SaveData` field).

### 4. Recipes point ahead (S) — teaching, pillar 2
Item info gains one line: "Makes: furnace, torch, anvil (+4)", from the recipe book. Tap to open
the item browser on that item.

### 5. Text size and left-handed controls (S) — reading
A text size setting (three steps) that scales `Font.pixel`, and a left-handed switch that uses the
HUD's existing side swap. New `Settings` fields decoded with a default.

### 6. A first success for each deep system (M) — teaching, pillar 2
For power, vehicles, suits, alchemy and infusions: when the player first makes the station, a short
goal in the journal leads to one working result (light a lamp from a generator; roll a cart down a
hill; fit one plate; brew one potion). Introduce, develop, twist, test: the next goal uses it
harder (a switch, a powered door; a flight; a jet).

### 7. Juice audit (S) — feel
Go through every common action and check it has sound, particles and a response under 100 ms:
mining each material, placing, landing, hits, pickups, crafting, opening chests. Fix what is
missing; check the big effects (blasts, storms, boss blows) are kept for big moments.

### 8. Pixel art: the redraw (L, in progress) — looks
The user asked for the creatures and blocks to be redrawn after their reference sheets. Direction
set: 16 art pixels a block, dark outlines, three or four tones a material, light from the upper left,
colours graded earthy (the user found the first colours too bright); drawings in `tools/art`, packed
into the game as text. Done: every creature and boss (the player from the user's own two drawings,
with a front view at rest and a choice of hair, shirt and trouser styles and colours; zombies, the
skeleton, the pirates on the player's own figure, bears, farm animals, the deep monsters, Ursavor,
Tyrannax and the Hollow Warden), and about fifty blocks (land, trees with plain leaves, gaps, tufts
and falling leaves, planks, brick, ores, plants, torch, workbench, furnace, chest). To do, in this
order: the remaining blocks (machines, furniture), item icons, the suit on the new figure, mod block
art at 16 pixels. The audit below still applies to whatever is drawn.

### 8b. Pixel art audit (M) — looks
A shot sheet that tests the art: every tile in a 3 by 3 grid of itself (seams), every creature as
a black silhouette (unique shapes), screenshots in greyscale (the player and dangers stand out),
and a count of the colours in use with near-duplicates flagged. Fix the worst offenders; note the
palette as a table for mod makers.

### 9. Seed of the day (S) — retention without pressure
On the new-world screen, a "seed of the day" button: the same world for everyone that day, with a
short goal set from the seed (reach a place, survive three nights, beat a boss). No streaks, no
losses for missing a day.

### 10. Economy watch (M) — systems
A test world that plays scripted trips and logs every resource's sources and sinks; a debug page
listing what the player has gathered and spent. Use it to find resources with no late use and give
them a sink (repairs, fuel, building, trade at a station).

### 11. Graduated death choice (S) — fair failure
A world setting, not only a mod rule: keep everything (as now), drop the bag where you die with a
marker on the map, or hardcore. The marker makes the drop a trip back, not a loss.

### 12. Late twists (L) — fun as learning
Keep new patterns coming after the Warden: rarer weather that changes rules for a day (a meteor
night, an eclipse), new materials found only by machines or vehicles, and creatures that answer
the player's own tools (shielded against fire, attracted by power lines).

## How to tell a step worked

Play a new world on the iPad for twenty minutes and write down: when the first goal was reached,
when the first night came and how it went, any moment of not knowing what to do, and anything
that was hard to read or hit. Repeat after each step. The test suites check the code; only play
checks the fun.

## Rules that stay

The six parts stay level in build memory (`tools/buildcost.sh`), saved enums only grow, new
`SaveData` and `Settings` fields are optional with defaults, mods stay data only, and world
generation stays the same for existing worlds.
