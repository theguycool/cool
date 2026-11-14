# PixelRealm

A 2D sandbox survival game for iPad, written in SwiftUI and run in Swift Playgrounds. The game is eight
files, `PixelRealm1.swift` to `PixelRealm8.swift` (about 68,500 lines in all, indented with tabs). The
user pastes each into its own file of one Swift Playgrounds app. It was one file until the user asked
for four, then six, then eight; deliver all eight, and treat them as one program (Swift doesn't care
which file holds what). `tools/parts.py` lays the sections out over the files from its `LAYOUT`
table and writes each file's header (what it holds, the paragraph about the parts, the imports).

**The iPad has to be able to build it.** As one file, the Mod Creator+ version built here but would not
start on the iPad, with no error shown, even with lighter screens and tab indents (1.93 MB). The last
version known to start there is 598e07b (one file, without Mod Creator+; commit 5e4d8c8 has it with
tabs). The user then asked for Mod Creator+ in four files. A Swift package's debug build compiles
each file in its own job, which needs much less memory at once, if the iPad builds that way (not
confirmed). `tools/buildcost.sh` measures both ways:
- 598e07b as one file: 63 s and 860 MB here. Mod Creator+ as one job: 86 s and 1,059 MB.
- Mod Creator+ as one job per file: 24 to 28 s and 405 to 457 MB per job (four jobs, 102 s in all).
  With the overhaul's phases 1 and 2 (3c0fb81, 1.97 MB): 19 to 22 s and 405 to 461 MB per job; as
  one job 71 s and 1,011 MB. This version builds and starts on the iPad (the user confirmed it), so
  four parts at these sizes are known to work. Phase 3 (2.03 MB) moved creature AI, spawning and
  combat from part 1 to part 2 to keep the parts level: 420 to 450 MB per job. Phase 4, vehicles
  (95c235f, 2.13 MB, most of it in `p33_vehicles` at the start of part 4, the lightest part): 440 to
  455 MB per job, 105 s in all; as one job 95 s and 1,053 MB. The user confirmed phases 3 and 4 build
  and run on the iPad, so four parts of up to about 455 MB per job are known to work. If the iPad
  runs the four jobs at once in one process, they could add up; that is not known. Step 5a (2.22 MB)
  first measured 475 MB in part 4; moving `p33_vehicles` to the end of part 3 and the start of
  `p32_modplus` to the end of part 2 levelled it: 457, 466, 464 and 452 MB, 106 s in all; as one job
  95 s and 1,091 MB. Step 5b, suits built piece by piece (2.27 MB, 61,035 lines), first measured
  489 MB in part 2. The tile table and the tile art became text (`Tile.defText`, `TileArt.text`) and
  creature AI, spawning and combat moved back to the end of part 1: 466, 473, 469 and 464 MB, 89 s in
  all; as one job 93 s and 1,194 MB. Step 5c, rules, weather, machines, vehicles and looks in mods
  (2.33 MB, 62,502 lines), first measured 471, 481, 486 and 487 MB; damage moved to part 1, custom
  infusions to part 2 and the Mod Creator's first screen pieces to part 3: 478, 482, 482 and 479 MB,
  113 s in all; as one job 92 s and 1,228 MB. The user confirmed steps 5a, 5b and 5c build and run
  on the iPad, so four parts of up to about 482 MB per job are known to work.
- Six parts (the art redraw, 2.51 MB, 64,263 lines): the user asked for six files. As four parts this
  version measured 483 to 484 MB per job. A job's peak follows how much SwiftUI is in its own part
  more than its size: cut evenly by size, the part with the Mod Creator+ screens needed 485 MB and the
  one holding the art text 346 MB. Levelled (the art text to part 1, `p33_vehicles` to part 2, the
  Mod Creator screens with the other screens in part 5): 360, 374, 395, 394, 399 and 382 MB, 143 s in
  all; as one job 117 s and 1,225 MB. Not yet confirmed on the iPad. Physics phase 1 (2.54 MB, 65,059
  lines, most of it `p12b_frames` in part 1 and the contact solver in part 2): 367, 376, 395, 394,
  400 and 382 MB, 118 s in all; as one job 97 s and 1,217 MB. Physics phase 2 (2.58 MB, 66,092
  lines): 374, 385, 396, 394, 402 and 382 MB, 119 s in all; as one job 101 s and 1,226 MB. Phase 3
  (2.62 MB, 67,073 lines) first measured 421 MB in part 2; the land painter (`p24_painter`) and the
  hull air moved to part 1: 388, 411, 398, 394, 403 and 384 MB, 110 s in all; as one job 97 s and
  1,279 MB. Phase 4 (2.64 MB, 67,536 lines, most of it `p31d_rails` at the end of part 3): 388, 413,
  402, 395, 403 and 384 MB, 134 s in all; as one job 110 s and 1,285 MB. Phase 5 (2.68 MB, 68,505
  lines, most of it `p34_joints` at the start of part 6): 389, 416, 402, 395, 405 and 397 MB, 135 s in
  all; as one job 107 s and 1,280 MB.
- Eight parts (phase 5, 2.68 MB, 68,526 lines): the user asked for eight files. Laid out by
  `tools/parts.py` with the screens spread over four files (a part's memory is a fixed share plus its
  size, and screen code costs more than game logic): 319, 356, 323, 374, 363, 340, 359 and 339 MB,
  132 s in all; as one job 106 s and 1,277 MB. Not yet confirmed on the iPad. Phase 6 (2.71 MB, 69,157
  lines, `p35_automation` at the end of part 1, the RECEIVER panel in part 6): 330, 359, 326, 376, 364,
  341, 361 and 340 MB, 134 s in all; as one job 102 s and 1,272 MB.
- A job's peak can jump by 30 MB or more after a small edit (taking the recipe lines out of one
  function once raised part 2 from 473 to 509 MB), so a few MB either way is noise; measure again
  after moving code.
- Add big features in steps the user can check on the iPad, and keep the parts about equal in
  compiled size (`tools/buildcost.sh` prints each job's peak).

## Checking a change

In cloud sessions a SessionStart hook (`.claude/hooks/session-start.sh` → `tools/setup.sh`) installs
Swift 6.0.3 under `/opt/pixelrealm` and builds stand-ins for SwiftUI and AVFoundation so the game
compiles and runs headless on Linux. If `/opt/pixelrealm` is missing, run `tools/setup.sh` (about a minute).

- `tools/typecheck.sh`: about 39 s. Run it after every batch of edits.
- The swift-lsp plugin (if loaded) checks a file as it is edited: `compile_flags.txt` points
  sourcekit-lsp at the stand-ins, and setup.sh installs it. It sees one part at a time, so names
  from the other parts show as missing; `tools/typecheck.sh` (all eight parts together) is the check
  of record.
- `tools/run-tests.sh [suite ...]`: builds and runs suites from `tools/tests`, four at a time (all
  of them take several minutes). Pass only the suites you touched while iterating, and run them all
  before committing. Full output is in `/tmp/pixelrealm-build/<suite>/out.log`.
- `tools/shots.sh power|weather|sky|cloudsheet|stick|alchemy|modplus|building|vehicles|mod5|suit5|mod5c|art|physics [folder]`: PNG screenshots from the game's own renderer (`sky`: clouds by day, dusk, night and storm; `cloudsheet`: every cloud template; `stick`: the combat stick's dial; `alchemy`: mutated creatures, the worn suit, the new stations, and a sheet of the new icons and suit pictures; `modplus`: two custom dimensions and a boss in a phase; `building`: a furnished house with stairs and a lift, a blast throwing blocks, a beam under strain; `vehicles`: every new kit parked, a plane, helicopter and airship flying, a tank firing at a wrecked truck, a ship built from blocks with the assembler, a plane mid-turn; `mod5`: every tree design shape under a mod's sun with rays, the same land at night under a pictured moon, the Overworld under a mod's sun, a lit cavern dimension, a repainted zombie; `suit5`: a sheet of suit designs in their poses, a turret firing with a plate broken off, jet flight with a wing, a laser and a cannon shell; `mod5c`: a mod's vehicle built from its kit, mod blocks on a power line and falling, rain in a mod's colour, a custom dimension's blizzard; `art`: the hand-drawn creatures and blocks in the world at the size an iPad shows them: a meadow by day, monsters at night, a cave with every ore, the bears and the elephant, the pirates and the deep monsters, the three bosses; `physics`: the player and a pig standing inside a
house that flies under a balloon, riders on a flatbed truck's deck, a plane and a crate parked on a
wheeled deck, a house on wheels with back walls, a door, a ladder, a bed and furniture, water poured
off a ledge filling a basin, a submarine under the sea with a dry cabin, a train of an engine and two
ore carts on stepped rails, a truck on big wheels at a step, a two-legged mech mid-stride, a crane truck
and a piston lift, a turret firing at zombies, a lever and signal post sending a receiver car past a
vehicle sensor).
- `tools/art.sh preview|pack|check|game|compare`: the hand-drawn art (see **Art** below and `tools/art/README.md`): PNG sheets of the drawings, writing them into the game, and before/after sheets.
- `tools/bench.sh`: chunk generation, painting, lighting and tick timings (debug build; compare
  with `GAME_SRC=<old file> tools/bench.sh`).
- `tools/buildcost.sh`: the game's size, and the time and peak memory of a debug build like the
  iPad's, as one job and as one job per file (a few minutes). Run it after adding a lot of code.
- The tools read the parts there are (`pr_game_files` in `tools/env.sh`: every `PixelRealm<n>.swift`). `GAME_SRC` can name another
  version: an older one-file game, or a folder holding its parts. Test programs build the parts as
  one job (`-wmo`) with `@main` removed.

Suites: `tests`, `round2`, `p2` (general gameplay), `portal`, `boat`, `veh` (vehicles), `combat`,
`mines`, `weather`, `nightai` (night spawning and monster AI), `stick` (the combat stick), `power` (Sparkworks), `snd` (sound
effects ≤ 1.2 s, thunder ≤ 3.2 s), `oldsave` (saves from an older version still load; uses
`tools/fixtures`), `mods` (the Mod Creator: file format, store, checks, custom content in play,
structures, test worlds, an end-to-end run; it uses a scratch mod folder, never the real one), `modplus` (Mod Creator+:
changes to game content, folders, versions, dependencies, ore controls, mining times, the sprite tools, custom infusions,
boss phases and summoning, custom dimensions, the Logic Studio and its safety limits), `alchemy`
(potions and status effects, throwing, mutation and its limits, infusions, the exosuit: building, wearing,
modules, power, saving), `overhaul` (dropped items, the bag, live crafting counts, the item browser and
debug give, the held attack stick, neutral animals, armour and creature damage, the bow zombie, doors
closing behind the player, the direct camera, clouds at any zoom, fireflies in place), `ghost` (the
renderer never mixes dimensions' pictures, chunks made again are the same, explore/build/save/quit/load
cycles through all four kinds of dimension, weather stays in its dimension), `world6` (generator 6
against 5: trees, ores by depth, seas; fingerprints of generator 5; saplings; monsters kept out of
lamplight by the real light), `build3` (blocks as walls, ladders built on by holding, furniture,
stairs, lifts, block weight, blasts, storms carrying blocks, structural physics), `mod5` (step 5a:
see-through sprite colours and the paint tools, game creatures repainted by a mod, the clock and light in
custom dimensions, suns and moons of a mod's own, tree designs: pass-through forms, every shape, whole
across chunk edges, saplings, checks; the climbable, sticky and decoration collision types), `suit5` (the
exosuit built piece by piece: coverage and guarding from the pieces there, hits landing by height, layers,
pieces breaking off, bills and mending, old suits rebuilt, the finer sprite and its poses, jets that lift by
thrust against weight, wings, turrets, cannons, lasers, boosters, batteries, solar, the magnet, suit
materials, parts and designs in mods), `mod5c` (step 5c: a mod's rules of the game and each rule at play,
start items, the Overworld's weather from a mod, more dimension weather, mod blocks' weight, falling,
seats, beds and power roles, vehicles in mods and their kits, themes and which mod's theme is used, all
of it saved in the mod and read from older mods), `aero` (vehicles of
every kind: the plane, helicopter, airship, tank and truck kits flown and driven, designs too heavy to
fly, turning in flight, blocks built onto vehicles, rafts that float or sink by their blocks, the
assembler, shots, blasts and crashes, wrecks, mending, the autopilot, saves, a mod block as a part),
`art` (the hand-drawn art: the packed pictures read back whole, every creature hand-drawn with its
look and poses and the frame for each thing it does (pirates, golem, sentinel, the bosses), sprites
standing on their soles and fitting their hit boxes, the player's hair, shirt and trouser styles and
colours, scarf and armour, no marker colour ever left showing, the frame for each thing the player
does, 16-pixel blocks and their mirrored variants, the land painter's edges, a mod's repaint keeping
the size of the drawing it was painted over),
`phys1` (the physics overhaul, phase 1: bodies in a vehicle's frame: standing, walking and jumping on
and inside vehicles that move, climb, turn and tilt; creatures and dropped items riding; walls and
undersides; being pushed; getting up from the seat at speed with the autopilot carrying on; saved
aboard; a rider scraped off by the land; no speed clamps and what sets top speed; 500 blocks a second
against a wall; weight on rafts; pushing; grip and bounce, also in mods; odd builds), `phys2` (phase 2:
vehicles meeting vehicles: landing on a deck in any order, pushing by mass, head on at speed, riding a
truck's bed, a plane landing on a moving deck, resting and waking together, a rider meeting another
vehicle; parts anywhere: wheels on any side, rotors by their room, boxed-in jets, steering away from
the seat; several seats; doors, ladders, stairs, chairs, beds, stations and back walls aboard, saved
and assembled; the cached picture), `phys3` (phase 3: water falling, spreading, levelling, pouring
through a hole, nothing made or lost, levels saved, still seas asleep, lava meeting water, a mod's
liquid floating on water, the bucket; a stone box floating on its air, a holed one sinking, a submarine
diving and rising with a dry cabin; tilted wings, flaps, air brakes, tailplanes; the wind's shelter),
`phys4` (phase 4: rail wheels coasting on rails and dragging off them, the ore cart on a rail and down a
stepped track, a train coupled, pulled, pushed, saved, walked through and uncoupled; big wheels put on,
climbing a step small wheels stop at, saved, taken off whole; a ship of 424 cells and its cost a frame),
`phys5` (phase 5: what is built beyond a hinge, servo or piston split off as a section, also built in
steps or all at once; a hinge swinging to its limit; a servo on button A and B and the stick, holding a
stone, swung hard and fast, through its own base; a machine resting as one and woken by a button; a
piston lifting a platform with a crate; a crane mast on a truck driven along; the joint taken away;
saved joints; a two-legged mech set up by AUTO MECH walking both ways, stopping and standing),
`phys6` (phase 6: a turret firing by itself, sparing animals and what it cannot see; ways of firing round
and saved; button A; a gun on a machine's arm, a machine's shots passing its own sections; the remote
control paired, driving from afar, its buttons, the view, letting go, saved; a route a thousand blocks
from the player; signal posts driving, routing, holding a button and firing; the vehicle sensor;
receivers saved; Logic Studio channels; a mod's gun block firing its own shot; the receiver panel),
and `det` and `det2` (world generation fingerprints for generator versions 1 to 4).

What the stand-ins can't tell you:
- They only declare the SwiftUI and AVFoundation API the game uses. If you use a new API, add it to
  `tools/shim/SwiftUI.swift` with the real signature (setup.sh rebuilds the shim when its source
  changes). Prefer APIs the file already uses: anything that compiles only against the shim breaks
  on the iPad. The shim's `StrokeStyle` takes no `lineCap`, its `Path` has no `isEmpty` or
  `addRoundedRect`, its `Image` has no `aspectRatio`, and there is no `LinearGradient`. The Sprite Studio's clipboard (`UIPasteboard`,
  `UIImage`, `CGContext` drawing) is stood in with a nearest-neighbour copy; the real scaling is untested.
- Only the world Canvas is rasterised. SwiftUI panels are compile-checked but never drawn.
- Nothing has been run on a real iPad from here. Say so in reports.

## Rules for the code

- **Type-checker speed.** Write explicit types on locals (`let x: Double = ...`), join strings with
  `joinText(...)` instead of long `+` chains, and split big expressions. Keep typecheck near 39 s.
- **Small SwiftUI bodies.** The real SwiftUI has far more overloads than the stand-ins, so keep each view
  body short: sections as their own computed properties or functions, button actions in methods,
  closures with typed parameters (`{ (it: Item) in ... }`), strings and colours worked out in `let`s
  first, `Double` ranges written out (`0.0...1.0`, `sbRange`), rows of sliders from a table (`DSlider`),
  and `AnyView` where a `switch` picks between big pages. Indent with tabs (four spaces per level made
  the game a sixth bigger).
- **Big tables as text.** A long table written as Swift code (a `switch` returning literals, or calls
  with many arguments) costs far more to compile than the same data in one string literal read once
  at start-up: see `Tile.defText`, `TileArt.text` and `GameRule.specText`, checked against the old code
  when they changed.
- **Screen colours.** Buttons, panels and text on the game's screens use `Color(ui:)` (a mod's theme
  recolours them, `ThemeRT`); the world, pixel art, previews and colour swatches use `Color(hex:)`.
- **Saves.** Saved enums (`Tile: UInt8`, `MobKind`, `Mat`, `Gadget`, `RecipeCat`, `SoundID`, `Potion`,
  `Infusion`, `ExoMat`, `ExoPart`, `ExoCore`, `ExoModule` (wing ... magnet appended), `ExoSlot`, `SuitBone`,
  `SuitShape`, `SuitKind`, `ModPowerRole`, `ThemeRole`, `ModBlockFunction` (seat, bed appended), `GameRule`
  (its lines in `GameRule.specText` follow the cases), `Dimension` (custom0-2 were appended),
  `PartType` (vehicle parts: `block`, the aircraft parts, then flap, airBrake, stabilizer, ballast,
  railWheel, coupler, bigWheel, hinge, servo, piston, receiver were appended), `GunMode`, `RadioAct`, `ModCollision` (liquid appended), `ProjKind`
  and the like) only get new cases appended at the end. Never reorder or remove cases. `hairChoices`,
  `scarfChoices`, `shirtChoices`, `pantsChoices` and the style lists (`hairStyleNames`,
  `shirtStyleNames`, `pantsStyleNames`, each style with its drawing `player_hair_<n>` and so on) are
  lists a saved choice points into: only add at the end (scarf colour 0 is "none"). New `SaveData` fields are optional; new `Settings`
  fields are decoded with `decodeIfPresent` and a default.
- **Infusions live on the stack** (`Stack.inf`). Code that moves an item between bag, chest, carried and
  dropped must keep the whole `Stack`, or pass `inf:` to `Inventory.add`; infused items never merge.
- **World generation is frozen for existing worlds.** `det`, `det2` and the generator 5 fingerprints
  in `world6` must pass unchanged. Changes to generation go behind a new generator version (test
  `genVersion >= N`). Version 6 (current): more trees (three columns apart, jungle trees four; a grove
  within 110 blocks of the spawn, `treeDensity6`), iron from row 150 and a little more coal, copper
  and tin near the top (`oreRules6`, picked by `WorldGen.oreTable`), smaller seas (`smallSeas`:
  narrower basins, land noise at 700 instead of 800, coasts lifted), and sealed grotto passages that
  stop with four rows of ground over their end. Version 5 has no villages;
  versions 1 to 4 still generate them (`WorldGen.hasVillages`) so saved worlds keep matching, but
  nothing in the game uses villagers, trades or village goals any more (`MobKind.villager` stays only
  for saved numbering).
- **A new tile needs:** an appended case, a line in `Tile.defText` (read by `Tile.makeDef`), art
  (a 16x16 drawing in `tools/art/tiles`, then `tools/art.sh pack`; the older way, 8x8 art as a line in
  `TileArt.text` read by `customTileRows`, still works and is drawn doubled), and,
  as relevant, `needsSupport`, `toolClass`, `isInteractive`/`interact`, and the exclusions in
  `creativeItems` for on/off variants, and a line in `blockPhysOf` (its weight, carry and reach).
  New tiles go after `vehicleSensor` (the last one; all after the 64 mod tiles); `Tile.isMod` is a range
  check, so they are not mistaken for mod blocks. Tile numbers must stay at or under 247 (a wall made
  from a block is stored as 8 + its number in one byte).
- **A new panel** needs its `@Published` show flag added to `updateInputGate` and to the condition
  that hides the HUD in `GameView`.
- **Scrolling.** Every screen that can grow scrolls, with its way back (the top bar) outside the
  `ScrollView`. A picker inside a Mod Creator editor opens through `.modCover(s, key) { ... }`, which
  `ModEditorView` shows above the scrolling page (a pop-up drawn inside the page can open off-screen).
  The sprite canvas takes drags for painting, so a page scrolls from anywhere else.
- **Plain page switches, plain grids.** The dimension editor crashed on the iPad when switching pages
  (Playgrounds says "unknown crash" for every crash, even a trap in the game's own code). It wrapped
  each page in `AnyView` and had lazy grids (`ChoiceRow`) on its pages; every page builds fine here.
  It now switches pages with a plain `@ViewBuilder` switch, as the creature editor that has always
  worked, and uses `ChoiceRows` and `PlainGrid` (plain rows); `ModColorRow` draws plain rows too, and
  the SKY page shows one palette with a choice of which colour it sets. Whether that is the fix is not
  confirmed; build new paged screens the same way. The Logic Studio, the game-content editor and the
  ore controls still use `AnyView`.
- **Mod data.** New fields of mod content (`ModBlock`, `ModItem`, `ModMob` and the rest) get a default
  and are decoded with `c.val(.key, default)`, and get a clamp in `ModValidator.check`. Mod enums only
  get cases appended (also `ModInfuseTrigger`, `ModPhaseWhen`, `ModSummonHow`, and the Logic Studio's
  `LEvent`, `LOp`, `LEOp`; `channelOn`, `setChannel` and `channel` were appended). References inside a mod are content keys: renamed in `ModStore.rekey` and
  counted in `ModStore.dependencies` (game tiles are `"tile:<n>"`, never renamed). A mod block can work as a
  vehicle part (`ModBlock.vehRole`, `vehMass`, `vehPower`; `ModVehicleRole` is append-only). `ModCollision`
  is append-only too (`climbable`, `sticky`, `decor` were appended). Tests never touch the real mod folder or saves: set `ModStore.overrideDir` and
  use `makeSave()` with a JSON round trip.
- **Art.** Creatures, the player and blocks are drawn by hand at 16 art pixels a block, after the
  user's reference sheets (dark outlines, three or four tones a material, light from the upper left,
  a face that reads). The drawings are Python files in `tools/art` (parts as rows of letters, laid
  over each other into frames); `tools/art.sh pack` writes them as text into `ArtSheet`
  (`a01_artsheet`, in part 2), between the `<art:creatures>` and `<art:tiles>` markers.
  Never edit that text by hand, and run `tools/art.sh check` before committing. Every creature is
  hand-drawn; the older pictures made in code (`p05*`, 8 pixels a block) stay for mods that repainted
  over them (`ModOverride.fine` false): `creatureLook(kind, variant)` gives either, with its own pixel
  size, soles and frame roles, so use it (or `lookSpriteSet`) rather than assuming a size or frame
  numbers. Poses are by name (`CreatureAnim.pose("strike", 4)`: the hand-drawn frame, or the older
  fixed number): windup, strike, block, shoot, fire, throw, charge, cast, rear, front; walks go
  through `CreatureAnim.walkFrame`. Every colour drawn goes through the grade (`grade` in
  `tools/art/artlib.py`, `artGrade` in the game; keep `GRADE_SAT` and `GRADE_VAL` alike), which takes
  the candy brightness off strong colours (the user found the old colours too bright). The player is
  drawn in layers (`player.py`: the bare figure, and one drawing for each hair, shirt and trouser
  style, the scarf and the helmet, in the marker colours listed in `PlayerInk`, which must match) and
  dressed by `playerFrames(PlayerLookChoice)`; the pirates are drawn on the same figure (`player.side`
  with `extra`). Blocks: `tileBuf` is always 16x16 (`tileArtPx`); older 8x8 art and mod blocks' art
  are doubled by `fitTileArt`. Still on older art: about 170 blocks (machines, furniture), item icons,
  vehicle parts, the suit (built on the older figure, see `playerSet`), mod block art (8x8). See
  `tools/art/README.md` for how to draw and the look to keep.
- **Physics.** The overhaul's plan is `docs/physics-plan.md` (what exists, the shared foundation, the
  phases); read it before a physics step and update it when one lands. Never clamp a speed: what
  keeps fast things out of the land is the step rule (`Phys.maxStep`: nothing moves further between
  collision checks; `stepVehicle` splits its step as often as the speed needs and skips the checks
  where `World.boxOpen` finds nothing to meet), and what sets a top speed is power against drag
  (`Drive`, `Aero`). A body that can be on a vehicle moves through `Game.moveThing`, never
  `World.moveBody` directly; aboard, its `vx`, `vy` are measured against the vehicle (`worldVel`
  gives the real one). Vehicles move only in `updateVehicles`, with `syncRiders` straight after:
  code that moves one by hand (tests) must call `syncRiders` itself. Vehicle parts are iterated in
  dictionary order, which differs from run to run: a physics test must hold for any order.
- **Comments** are plain-language doc comments explaining what something does in the game. Match the
  surrounding style. Each part starts with the same header and imports (`tools/parts.py` writes them).
- Commit and push to the branch the session names. Never put model names in commits.

## Map of the parts

Sections start with `// ===== <name> =====` (grep for them). `tools/parts.py` (its `LAYOUT`) puts
them in the parts: part 1 `p01_util` to `p08b_ruins`, `p35_automation`; part 2 `p09_umbral` to `p12_phys`, `p12b_frames`
(bodies on and inside vehicles), `p12c_fluids` (with the air inside hulls), `p24_painter`, `a01_artsheet`
(the hand-drawn pictures as text, and their readers), then `p13a_mobdefs` to `p14d_tools`; part 3
`p15a_mobai` to `p26_vehicle_ux` (without `p24`), `p33_vehicles`, `p27_power`; part 4 `p28_mods` to
`p31c_blockphys`, `p31d_rails`; part 5 `p32_modplus`, `u03_hud`, `u04_panels`; part 6 `u01_art` (the art
store, the player's look, sound, the weather simulation, ambient and animal life, the journal, telegraphed
attacks), `u05_menu`, `u10_automation` (the RECEIVER panel), `u08_alchemy`; part 7 `u02_render`, `u07_mods`, `p34_joints`, `u06_root`; part 8
`u09_modplus`. New code goes into the section it belongs to; a new section goes into `LAYOUT` (then run
`python3 tools/parts.py`, `tools/typecheck.sh` and `tools/buildcost.sh`). A `private` or `fileprivate`
name can only be used in its own part, so anything used across parts is internal (no modifier).

The sections:
`p01_util`, `p02_tiles` (Tile, defs, art), `p03_items`, `p04_recipes` (RecipeBook), `p05*` (creature
sprites), `p06_worldgen`, `p07_chunk`, `p08*` (villages, ruins), `p09_umbral`, `p10_world` (World,
chunks, `set`), `p11_light`, `p12_phys`, `p12b_frames` (`Phys`, `mobMass`, `moveThing`, `rideStep`,
`moveInCells`, `meetVehicles`, `syncRiders`, the insides of vehicles), `p12c_fluids` (liquids that flow,
the bucket), `p13a_mobdefs` (MobKind, MobDef, spawn rules, Mob),
`p13b_vehicles`, `p14a_game` (Game state, Settings), `p14b_player` (`tick`, the frame), `p14c_input`
(pointer, `interact`), `p14d_tools` (item use, mining, placing), `p15a_mobai` (`updateMobs`,
`think`, the per-kind AIs), `p15b_spawn` (`updateSpawning`), `p16*` (combat, damage, bosses), `p17`
(vehicles, ships), `p18` (portal, map), `p19_save` (`SaveData`, `makeSave`, `Game.load`), `p20`–`p26`
(helpers, walls, doors, HUD logic), `p34_joints` (hinges, servos, pistons: sections, joints, controls,
mechs, the JOINT panel), `p35_automation` (gun modes and turrets, the remote control, land kept round
vehicles at work, signal channels and receivers, the vehicle sensor's sight, mod gun blocks), `p27_power` (Sparkworks), `p28_mods` (Mod Creator: data,
store, checks, runtime, custom creature AI, structures and capture, test tools), `p32_modplus` (Mod Creator+: changes
to game content, ore controls, sprite tools, custom infusions, boss phases and summoning, custom dimensions with
their suns, moons and tree designs, the Logic Studio), `p29_alchemy` (rarity, potions, effects on creatures, smoke,
mutation and its limits, chest extras, the recipes of all three new systems), `p30_infusion`,
`p31_exosuit` (suits built piece by piece: pieces, materials, the body map, stats and the guard map, hits
and piece damage, bills and mending, old suits rebuilt, working parts, ready-made designs, suit modding), `p31b_building` (block
walls, ladders, furniture, lifts), `p31c_blockphys` (block weight, flying blocks, blasts, structural
physics), `p33_vehicles` (the flight model, power sharing, damage and wrecks, weapons, turning round,
building blocks onto vehicles, the assembler, the autopilot, the checklist and instruments), `u01_art`, `u02_render`
(`WorldRenderer.draw` sets the draw order), `u03_hud`, `u04_panels`, `u05_menu`, `u07_mods` (Mod
Creator screens and editors, the capture and Mod Test panels), `u08_alchemy` (the HUD's effect strip and
suit bar and its SUIT FIRE control, the Infusion Crucible screen, the Assembly Station's suit designer, the
Mod Creator's SUITS tab), `u09_modplus` (the Mod Creator+ screens: game
content, ore controls, hardness reference, Sprite Studio, infusion, phase, summoning, dimension and script editors,
the Mod Test LOGIC tab, the sun and moon editor, the tree design editor), `u06_root`.

## Systems in brief

- **Art (a01_artsheet, p05*, u01_art).** `ArtSheet.creatureText` and `tileText` hold the hand-drawn
  pictures (run-length text; a creature is a header line and `+` lines of frames). `CreatureSheet`
  parses once and unpacks a creature's frames when first asked; `TileSheet` gives the 16x16 blocks and
  how each may be flipped. `creatureLook` picks the drawing or the older code-made picture
  (`olderCreatureArt`), `Art.mobSet` caches sprite sets by kind and variant, `mobFrame` picks the
  frame by state. The player: `playerFrames` lays the chosen trouser, shirt, scarf, hair and helmet
  drawings on the bare figure and swaps the `PlayerInk` markers for graded ramps of the chosen colours
  (`lookRamp`); armour takes the place of the shirt and trousers in its metal; `PlayerLookChoice.key`
  names the sprite set; the CHARACTER screen (`CharacterView`) picks styles and colours and shows the
  figure from the front and the side (`previewPlayer`). Settings saved before the styles start the
  look afresh. After standing still (`Game.restT`) the sprite turns to its `front` frame; a worn suit
  is still built on the older figure. Land: `SectionPainter` keeps four pictures
  of each block (as drawn, mirrored, turned over, both), picks one by position where the block
  allows it, and draws a lit top and dark lines where solid ground meets open space (also across
  chunk edges: `World.set` and `loadChunk` mark the neighbour's sections). Leaf blocks are plain on
  purpose, with gaps where the sky shows; where they meet the air the painter adds tufts that stick
  out (`LeafTufts`, `paintTufts`), and leaves drift down from canopies and broken leaf blocks
  (`LeafFlake`, `updateLeafFall`, `dropLeaf`, drawn by `drawLeafFall`). A section picture is
  256x256 pixels; `RenderCache` keeps about 200. A mod's repaint of a game creature says which
  drawing it was painted over (`ModOverride.fine`) and keeps that drawing's size and frame order.
- **Sky.** `drawSky` paints gradient, stars, sun and moon, then the clouds (`drawClouds`), all behind
  the terrain. There are no background hills. Clouds are `CloudField.layers` (four layers: far, middle,
  near, storm deck), each a row of cells holding nothing, a cloud or a formation; the templates are
  generated once in `CloudArt` (five size classes) and drawn as cached images. Weather sets how many
  cells fill (`wxHere.cloud`) and how dark they are.
- **Attack control.** `CombatStickView` (right side of the HUD) feeds `actState` (`stickAt`,
  `stickReleased`); `applyActButton` runs every frame before `tick`. Inside the dead zone the game
  auto-aims as before; past it `stickAim` turns the direction into an aim point per item kind. The
  walking stick, JUMP and the attack stick each have their own `DragGesture`, so they work together;
  `releaseAllInput` clears all of them when a panel covers the controls.

- **Weather.** One `WeatherSim` for the world. `weatherAt(x, y)` gives a `LocalWeather`, and
  weather devices update in `updateWeatherDevices`. Rain blends from column to column
  (`landWetness`), so it never steps at a biome border. The ground's wet and snow strips
  (`updateGroundCells`) belong to the Overworld and only change there. Weather loops are silenced
  when leaving a world (`Sound.silenceLoops`).
- **Land pictures.** `RenderCache` keeps a picture of each 16-row section, keyed by dimension, chunk
  and section (`key`, room for 8 dimensions) and only reused for the chunk it was drawn from
  (`Chunk.serial`). The key once had room for two dimensions, so custom dimensions showed Overworld
  and Umbral pictures and the other way round: the "ghost terrain". `Game.load` makes a game with
  `loadSpawn: false` (the land comes from the save, not made around the spawn first).
- **Trees, saplings, doors, drops.** Leaves drop saplings (8.5%); a sapling on soil grows on a random
  world tick (`growSapling`: the biome's kind of tree, a custom region's own log and leaves, only into
  open air or wild plants). Doors the player walks through close behind them (`walkDoors`); a stack the
  player throws away waits until they walk off (`DropItem.heldBack`). A hold that uses up the stack in
  hand does not turn into mining by hand until the next press (`handEmptied`).
- **Building (p31b_building).** The HUD's AS WALL/AS BLOCK switch (`wallMode`) puts any solid block up
  as a background wall: wall values 1-7 are the old wall kinds, 8+n is a wall of tile n
  (`blockWallValue`, `blockWallTile`; the painter keeps a darkened copy of every tile's art). Holding
  ladders on a ladder builds it on toward the aim (`extendLadder`). Furniture tiles (`chair` ...
  `sofa`): seats (`seat`, `stayInSeat`), beds (two tiles, `sleepIn` sets the spawn and skips the night),
  storage (`cabinet`, `wardrobe`: World.chests like a chest). Stairs (`stairWoodR`... R/L) are not
  solid: `moveBody` collides with their two half-tile steps (`stairHit`, `stairLanding`,
  `stairCeiling`) and steps up half a tile at a time when `stairsNear` (per-chunk counts). Lifts:
  `Lift` cars on `liftRail` columns with `liftButton` floors two blocks beside, a deck in
  `buildDecks`, moved by `updateLifts` before the decks are built (riders carried), saved per
  dimension (`SaveData.lifts`).
- **Block physics (p31c_blockphys).** `BlockPhys` (weight, carry, span) per tile, `tileWeight`; item
  info shows them (`weightLine`). `World.isBuilt` (a per-chunk layer, `ChunkSave.built`) marks what the
  player placed; `World.set` clears it and placing code sets it. `FallingBlock` is every block on the
  move (sand, blasts, storms, collapses): it flies, turns, is carried by the wind (`windOnBlock`),
  bounces and slides, and settles back into a block (`settleBlock`). `blastBlocks` destroys, throws
  (toward the open side) or spares each block by hardness and weight; storms throw torn building
  blocks (`stormTear`). Structural physics (`Settings.structural`, off by default): edits are noted by
  `World.set` while `structWatch`; `checkStructure` gathers the built blocks around one (up to 5000),
  finds the standing ones bottom-up, spreads reach from them, then passes loads down the support
  tree; crushed blocks break, unsupported ones fall, strained ones are drawn cracked (`stress`).
- **Frames: bodies on vehicles (p12b_frames).** A `Body` (the player, a creature, a dropped item) is in
  the land's frame or a vehicle's (`Body.ride`, its feet in the vehicle's cell coordinates `rlx`,
  `rly`, its `vx`, `vy` then measured against the vehicle). `Game.moveThing` moves it: aboard,
  `rideStep` runs `moveInCells` (the land's rules on the vehicle's cells: `Vehicle.walkGrid` from
  `walkKind`: solid parts and blocks are floors, walls and ceilings; wings, tails, balloon tops,
  platforms and stairs are stood on from above; seats, wheels and the like are walked past), checks
  the land at the place that gives in the world (a wall stops it, ground under it takes it off the
  vehicle), tilts gravity with the vehicle (past `Phys.steep` a floor no longer holds) and rests its
  weight on the vehicle (`Vehicle.push`). On the land, `meetVehicles` puts a body aboard when it
  comes down onto a cell and pushes it out of cells that reach into it (the body's lost motion goes
  into the vehicle by its mass: `mobMass`, `playerMass`). `syncRiders` (after `updateVehicles`)
  places everything aboard where its vehicle now is, and leaves a rider behind where the land is in
  the way. Being moved by other code more than half a block (a respawn) drops the ride. Jump at the
  controls is `leaveSeat`: with a floor under the seat the driver stands up at any speed (the
  autopilot, cruise or route, keeps the controls; `v.rider || v.auto != 0`); without one they hop out
  only when slow. `mirrorRiders` turns riders with a TURN. The view is carried with the vehicle
  (`updateCamera`). Creature AI still looks at the land's tiles, so creatures aboard mostly stand.
- **Vehicles meeting vehicles (p17).** `stepVehicles` steps every vehicle together (`VRun`: start, fixed
  steps in lockstep, finish); `stepVehicle(v)` steps one (others are pushed as if at rest).
  `meetVehicleCells` turns a vehicle's samples inside another's cells (`Vehicle.meetGrid`: every part
  solid, wheels round, blocks as on the land) into `VContact`s with `other` set, solved with the
  land's and pushing both; `settleVehicleMeet` moves them apart (half from each side, since each meets
  the other's samples). `restOn`/`leanOn`: what it rests on (sleeps while that sleeps; woken with it;
  carried round by `mirrorVehicle`). Riders meet other vehicles in `rideStep` (`vehicleInWay`,
  `meetOtherVehicle`).
- **Parts anywhere (p17, p33).** `attachProblem` only asks for a free cell that touches (and room in
  the land). `findBoxedParts`: thrusters, guns and drills with no open side (`boxed`) do nothing,
  rotors lift by `rotorRoom`, `openProps`/`openPaddles`/`openTails`; `partNote` says so. Wheels drive
  upright as before, otherwise along what they touch (`wheelsAlongContacts`, `Drive.tyreGrip`).
  Several seats: `seatAt` (the seat tapped; `seatCell`).
- **Insides of vehicles (p12b_frames).** `vehicleBlock`, ladders (`ladderSpot`, `ladderIn`), doors
  (`vehicleDoorTouch`, `updateVehicleDoors`, `setVehicleDoor`; ON VEHICLE builds a door two cells high),
  `sitAboard`/`stayInSeatAboard` (`Game.seatAboard`), `sleepAboard`, `stationAboard` (in `stationNear`),
  back walls (`Vehicle.walls`, `attachWallToVehicle`, `removeVehicleWall`, `vehicleWallMass`, saved in
  `VehicleSave.walls`, carried by the assembler). Stairs are solid cells aboard (stepped up). A big
  vehicle (24 cells) or one with walls is drawn from `VehicleArt.picture` (cached on the vehicle by
  `artRev` and `Art.gen`); wheels, propellers and drills are drawn over it.
- **Liquids (p12c_fluids).** See docs/physics-plan.md, phase 3. A liquid cell's level is 0...255
  (`liquidLevel`, `setLiquidLevel`; `liquidAmount` 0...1); `World.set` wakes the liquid round any change
  unless `flowHold`; `stepFlow` (from `Game.updateFlow`) falls, evens out rows (`levelRow`), reacts
  (`meetLiquids`). `Liquids.def(t)` gives a `LiquidDef` (water, lava, `ModRuntime.liquidDefs`);
  `Liquids.hotTable` marks burning ones. Tests that build pools by hand call `world.calmLiquids()`.
  Ships: `Vehicle.hullAir` (cells under the surface and how flooded), `updateHullAir`,
  `hullAirForces`, `dryAt`; `headUnderWater`; ballast (`Vehicle.ballast`, `ballastAndBrakes`).
  Flight extras: `Vehicle.tilt` (`tiltWing`), flaps, air brakes (`brakeOpen`), tailplanes, all in `Aero`;
  `windAtVehicle`, `windShelter`. New recipes go in `addPhysicsRecipes` (appended last).
- **Rails, trains, big parts (p31d_rails).** Rail wheels (`VSample.rail`, `railGrip`, `railPenetration` over
  `railSurface`, `railHold`), the ore cart (`placeOreCart`, from `placeSpecial`), couplers (`VLink` on
  both vehicles, `formCouplings` after the vehicles move, `solveCouplings` between fixed steps,
  `uncouple`), the big wheel (`partSpan`, `Vehicle.spanOf`, `attachBigWheel`; `cutAway` takes a big part
  whole). Collision samples are cached per vehicle (`sampleCache`, keyed by `artRev`).
- **Joints and mechs (p34_joints).** See docs/physics-plan.md, phase 5. What is built beyond a hinge,
  servo or piston is its own `Vehicle` (a section), its `parentID` the section it hangs from, which
  keeps a `VJoint` (cell, child, pivot in both, kind, limits, speed, strength, input, role, leg,
  target); `splitJointSections` after any build. `jointControls` (first in `updateVehicles`) frees
  orphans and runs `machineControls` per machine (wake and step together, targets from the driver's
  stick and `jointButtons`, the walk, `walkMachine`, `balanceMachine`); `solveJoints` between fixed
  steps (`pivotStep`, `pistonStep`, the footing of sections on the land, `closeJointGap`).
  `machineRoot`, `machineSections`. The JOINT panel (`JointPanel`, `showJoint`, `jointEdit`) opens on a
  tap of a joint part; A, B and C show while driving a machine (`jointButtonRow`). Tests that move a
  machine by hand call `updateVehicles`, never step one section alone.
- **Automation (p35_automation).** See docs/physics-plan.md, phase 6. Guns: `Vehicle.gunMode` (`GunMode`,
  a tap cycles it: `cycleGunMode`), `runVehicleWeapons` (turrets: `turretTarget`; buttons:
  `machineButtonsHeld`; signals: `machineSignalOn`), `playerDrives`, `machineGuns`, mod guns (`modGun`,
  `ModRuntime.blockShot`). The remote: `remotePair`, `remoteID`, `drivenVehicle` (the HUD's vehicle
  controls and the attack use it), `useRemote`, `startRemote`, `driveRemote`, `endRemote`. Far vehicles:
  `vehicleWorking`, `keepWorkingLand` (from `updateStreaming`). Signals: `channels` (posts'
  `postChannels` from `machineTick`, the Logic Studio's `logicChannels`, saved), `radioControls` (first in
  `updateVehicles`; `Vehicle.channel`, `radioAct`, `signalOn`, `signalDrive`), the RECEIVER panel
  (`ReceiverPanel`, `showRadio`, `radioEdit`, `setRadio`), the vehicle sensor (`vehicleNearSensor`).
- **Speed and contact (p17, p33).** No clamps. `stepVehicle`: sub-steps by speed, the open-sky path.
  `vehicleSubstep` gathers `VContact`s and gives their blows together over four rounds (normal push
  held at zero or more, friction within `mu` times it, bounce and grip from the block touched:
  `BlockPhys.grip`, `.bounce`, also `ModBlock.grip`, `.bounce`). Wheels: push falls as speed rises
  (`Drive.power`), the gearing takes `Drive.loss` per block a second, more with weight and tracks;
  the kits keep their old top speeds (car 9.3, truck 12.5, tank 6.9) and more engines go faster.
  Boats: propeller power and a paddle's stroke against water drag. Vehicles without wings feel the
  air by their box (`Aero.kDrag`); aircraft part by part as before.
- **Vehicles (p13b, p17, p26, p33).** A `Vehicle` is a rigid body of 1x1 cells: `parts` (a `PartType`
  each) plus `blocks` for cells that are blocks (`.block`, or a mod block working as a part: then
  `parts` holds the part it works as and `blocks` its look). A cell weighs its part's mass or its
  block's `tileWeight` (`cellMass`); `recompute` counts parts, the centre of mass, inertia, facings
  (`face`, the open side of thrusters, guns and tail rotors) and mod strengths (`boost`). Saved in
  `VehicleSave` (`VPartSave.tile`, `.dmg`, the autopilot's `auto` and `route`). The ground and boat
  physics are as before; `airForces` runs only when `aero` (wings, elevators, air propellers, jets,
  rotors, envelopes): per part, drag on faces that meet the air (`faceDrag`), lift and drag on wings
  from the real airflow (`wingForce`: camber, stall at `Aero.stallAngle`), thrust along the vehicle's
  axis, rotor lift along its shaft, hot-air lift straight up; all numbers in `Aero`. Engines share
  their power (`airPower`, `groundShare`). Controls: stick x is the throttle (screen-relative) or a
  helicopter's tilt (`cyclic`, which hovers in place hands-off); stick y is a pitch-rate command
  for elevators with a learned `trim`, a stall guard and hands-off levelling (`pitchRateWanted`), a
  climb rate for rotors, heat for burners (`flightControls`). TURN mirrors the vehicle
  (`mirrorVehicle`; in flight halfway through a banked turn, `stepTurn`). Damage
  (`Settings.vehicleDamage`): `damageVehicle` per cell up to `vehicleCellHP`, `breakVehicleCell`
  keeps the driver's group and makes the rest wrecks (`makeWrecks`); shots hit cells
  (`vehicleOnPath`; vehicle guns have `owner` 2,000,000 + id, the player's own shots pass), blasts
  (`blastVehicles`), crashes over `vehicleCrashSpeed`. Cargo keys: `cargoSpot` (a second form for
  cells far out). ON VEHICLE (`vehicleBuild`) builds blocks in hand onto a vehicle; the Vehicle
  Assembler turns built blocks into a vehicle and back. Autopilot: cruise and route
  (`autopilotSteer`), routes run with nobody aboard.
- **Night monsters.** `updateSpawning`:
  - monsters have their own limit (`monsterCap`, set by the Nights setting); wild predators have a
    separate one;
  - `monsterSpawnCD` paces new arrivals;
  - lamplight keeps monsters away by the real light: `lightForSpawn` floods a separate `LightMap`
    (`spawnLight`, `compute(..., noteSeen: false)` so the screen's light map still sees its edits)
    around the spot, on screen or not; a monster needs glow of `spawnGlowMax` (4) or less at its own
    cells, and caves also refuse daylight over 6;
  - `spawnLog` records why each spawn attempt failed (shown in the debug panel).
- **Animals and armour.** Wild animals (`isWildAnimal`) leave the player alone until hit
  (`wildProvoked`: 12 s after the player's last hit); `isThreat` is what targeting and auto-aim use.
  Armour takes `armorShare(defense)` of each blow (4% a point, at most 80%). `.archer` is the Bow Zombie.
- **Monster AI.** `think` gives every monster its senses and state (`MobAI`: idle, alert, chase,
  search, back, retreat). The per-kind functions supply the attacks: `st` 3 and up are wind-ups and
  blows, 0 and 1 are walking. The debug panel's AI overlay shows each monster's state and its reason
  for not attacking (`why`).
- **Sparkworks (power and automation).**
  - Wiring is an overlay per chunk (`Chunk.wires`, bits in `Wire`: power, amber pulse, teal pulse).
  - Devices live in `World.devs` (`PowerDev`), kept in step with tiles by `World.set` →
    `powerTileChanged`.
  - Networks are rebuilt only when `world.powerRev` changes. Updates run at three rates:
    `powerTick` 4 Hz, `pulseTick` 20 Hz (a queue, with a delay per logic part and burnout for
    loops), and `machineTick` 10 Hz.

- **Mods (the Mod Creator).**
  - A mod is a JSON `ModPack` in `ModStore` (one file each, plus an order and on/off index). It is read
    leniently, then `ModValidator.check` clamps every number (`ModLimits`, `ModRange`; a sandbox mode
    allows more) and switches off broken content with a `ModReport`. Content keys are `"modID:contentID"`.
    No code runs from a mod: it is data only.
  - `ModRuntime.activate(packs, world:)` runs before a world is made or loaded and builds the content;
    `RootView.leave` deactivates it. Blocks take the reserved tiles `mod00`…`mod63`, numbered per world
    in `ModWorldInfo` (saved as `SaveData.mods`, which is also how a world remembers its mods); items are
    `Item.custom(key)`; creatures are `MobKind.custom` with `Mob.cslot` (`updateCustomMob`), and their
    attacks use the shared damage functions. Loading a world whose mods are missing asks first and keeps
    placeholders, so nothing is lost.
  - Custom ores and structures generate in `applyModGen` only when a world's mods add some, so
    generation without mods is untouched (`det`, `det2`). Structure capture: pause → Capture Structure
    (`startCapture`, `saveCapture`). Test worlds: `ModTest.makeWorld` (creative, `testMod` set, never
    saved), tools in `ModTestPanel` (TEST button on the HUD).

- **Potions and effects.** `PlayerEffects` (kinds are `ModEffectKind`, shared with mods) runs in every
  world through `updateEffects` (regeneration, fire protection, slow falling, smoke, the suit). Drinks:
  `drinkPotion`; mending has a rest (`mendCD`). Thrown potions are `.flask` projectiles with `potion` set;
  `burstPotion` applies them in a radius with line of sight (harmful ones spare the player and pets).
  Creatures carry `slowT`, `poisonT`, `weakT`, `regenT` (ticked by `mobStatus` only while set). A
  creature's blows are scaled through `DamageSource.mult` (`Mob.dmgMul`). Effects are saved
  (`SaveData.effects`).
- **Mutation.** `mutate(m)`: each dose doubles size, health and strength up to `MutationLimits`; the body
  size and the drawn size are the same number (`mutSize`), and growth stops where there is no room.
  Bosses take one milder dose. Mutated creatures are persistent and saved (`SaveData.mutants`, pets in
  `MobSave.mut`), at most 16 at a time.
- **Infusion.** `Infusion` compounds are worked in at the Infusion Crucible (`infuse(slot:)`, checked again
  every time; `infuseProblem` says why not). Slots by tier (`infusionSlots`). Melee goes through
  `infusedMelee`, shots through `infuseShot`, mining through `mineBoost`/`minedDrops`, armour through the
  cached `armorInf`.
- **Exosuit (built piece by piece).** `Game.suit` (`ExoSuit`: worn, energy, and its `design`, a
  `SuitDesign` of `SuitPiece`s: kind plate/frame/core/module, the body part it is fixed to (`SuitBone`),
  centre and size in suit units (3 to a sprite pixel), turn, shape, thickness, metal (`ExoMat` or a mod's
  `modMat`), paint, damage `dmg`, and `src`: the group of the item it was made from in `design.items`).
  `suitStats` (`ExoStats.of`) is cached by `suitRev` (call `suitChanged()` after any change): weight,
  energy, working parts by module (`counts`, `power`), jets' `thrust` against weight, and the guard map
  (`SuitGuardMap`: coverage and guard per `SuitSection`, sampled over `SuitBody`'s cells). A blow
  (`suitGuard` → `suitTakeBlow`) lands on a body point at the attacker's height; the pieces over it,
  outermost first, each stop their share (`suitShare`) and take that damage themselves; broken pieces stop
  nothing and are not drawn. `applyDesign` builds a plan, paying the bill (`SuitDesign.bill`: bars of each
  piece's metal by size, cores and parts from the bag; what comes off is given back) all or nothing;
  `repairSuit` mends. Old slot-built suits (`parts`) are rebuilt on load (`ExoSuit.migrate`, keeping the
  old parts with their infusions as item groups). The player's sprite with a suit is drawn three times
  finer (`suitFrames`, `paintSuitPieces`; `BoneMove` moves pieces with the legs and the striking arm).
  Working parts: jets, wings, turrets, cannons and lasers (SUIT FIRE on the HUD, `suitFireHeld`), boosters,
  pistons, batteries, solar panels, the magnet, and the old modules. Modules spend energy through
  `suitRun` (within the cores' output) and `suitSpend`; the Assembly Station charges a worn suit nearby
  (`runSuitDock`). Mods add `suitMats`, `suitParts` (each also an item) and `suitDesigns` (the SUITS tab;
  a design is saved from a TEST world's Assembly Station).
- **Rules, weather, machines, vehicles and looks in mods (step 5c).** `ModPack.rules` holds numbers by
  rule id (`GameRule`; names, ranges and help in `GameRule.specText`); `ModRuntime.rules` is what the
  world's mods set (the lowest in the load order wins each rule) and `rule(_:)` reads it: `gravityG` and
  `dayLength` are computed from it, and the hooks are in `updateSurvival` (hunger, healing),
  `damagePlayer` (damage taken), `hurtMob` (dealt), `mineStep`, `monsterCap`/`animalCap`, the landing
  (falls), `runMax` (walk), the jump, `skyLight` (night light), `die` → `dropBagOnDeath`, and
  `applyHealthRule` (new worlds and `Game.load`). `ModPack.startItems` are given in `setupStartingKit`.
  `ModPack.weather` (`ModWeather`: chance per `WeatherKind`, rain, wind, spell length, rain colour) is
  used in `planStep`, `allowedProfile` and `drawPrecip`; custom dimensions have presets 0-8
  (`customWeather`). Mod blocks: `weight`/`carry` (`blockPhys`), `falls` (`fallsLikeSand`,
  `checkFalling`), the `seat` and `bed` functions, and `powerRole` (`ModPowerRole`: generator, solar,
  battery, powered lamp, signal light) with `powerAmt`, through `powerRole`, `Tile.isPower` (the static
  `powerTable` holds only game tiles), `PowerSpec`, `modGeneratorRate` and `modPowerLamp` (a lamp swaps
  to its lit `#alt` tile). `ModPack.vehicles` (`ModVehicle` of `ModVehicleCell`s: a part, or a block
  `tile:<n>` or a mod block key) are items too (their kit, `vehicleItem`); `useModItem` →
  `placeModVehicle`; a TEST world keeps a vehicle with SAVE VEHICLE (`vehicleDesign`). `ModPack.theme`
  (`ModTheme`): `ThemeRT` takes it from the enabled mods (the last one with a theme; `refresh` at the
  title screen and after the Mod Creator) and maps the game's screen colours by `ThemeRole`, sets the
  letters (`Font.pixel`), `PixelBox` corners and outline, the title screen and the HUD's size, solidity
  and sides. Editors: the Mod Creator's WORLD & RULES, VEHICLES and LOOK tabs, and the block editor's
  BUILDING MATERIAL and POWER sections.

- **Mod Creator+.**
  - Changes to game content (`ModOverride`) are built into `OverrideRT` at activation; it restores the
    game's own tables first (`Tile.setGameDef`, `mobDefTable`), so switching a mod off undoes it. `Item.melee`
    goes through `baseMelee`.
  - Ores keep the old placement for old settings (`ModOreRT.place`); new controls use their own random seed.
  - Sprites: `ModPixels` keeps each pixel's real opacity (under 8 of 255 reads as clear), up to 96 pixels
    a side; the editor's brushes, blending, shading, shapes and selections are `SpritePaint`. A game
    creature repainted by a mod: `ModOverride.frames` → `OverrideRT.creatureArt` → `Art.buildMobSet`.
  - Custom infusions are numbered from 1000 per world (`ModWorldInfo.infusions`) and live in `Stack.inf` beside
    the game's; their compound is a mod item under the same key.
  - Phases: `stepPhases`/`enterPhase` in `updateCustomMob`; numbers on the `Mob` (`mphase`, `phaseDmg`...).
    Summoning: `ModSummonRT` (an item, a shape, conditions); dimension ways in are summonings with `dimSlot`.
  - Custom dimensions take slots 2-4 (`Dimension.custom0`...); `dimCount` is 5 everywhere a list is kept per
    dimension. Their land is `fillCustomChunk`; sky `drawCustomSky`; weather `customWeather`; only their own
    creatures spawn. A world saved in a dimension whose mod is missing starts at the Overworld spawn.
  - Light in custom dimensions: the world clock runs there when the dimension has a cycle (`updateTime`; it
    used to stop outside the Overworld, so a dimension entered at night stayed dark); a cavern dimension's
    least light follows its light setting (`ambientLight`). Suns and moons of a mod's own are `ModSkyBody`
    (`ModDimension.sunBody`/`moonBody`, the Overworld's `ModPack.skySun`/`skyMoon` as `ModRuntime.overSun`/
    `overMoon`, the last mod wins): drawn by `drawSkyBody`, their `bright` scales the light (`skyLight`:
    a sun the daylight it adds, a moon the night's).
  - Tree designs: `ModPack.trees` (`ModTree`: shape, blocks, sizes, a painted `ModTreeGrid`), chosen per
    region by id (`ModDimZone.treeKinds`). `TreeShapes.cells` makes a tree's cells from one seed;
    `plantTreeDesigns` (after the old trees in `fillCustomChunk`, only in regions with designs) works out
    every root within `treeReach` of the chunk from the seed alone (`designTreeAt`), so trees across chunk
    edges are whole. A solid block used for a trunk or leaves gets a pass-through tree form in a mod block
    slot (keys `<block>#tree`, `<block>#leaf`, numbered after all blocks; `treeTile`, `slotTreeBase`), which
    drops the block it stands for; regions' simple trees use them too. Tree forms count as logs and
    leaves (`isLogTile`, `isLeafTile`: an axe fells them, cut crowns wither, leaves give saplings). A world
    keeps the forms it has even when its mod stops needing them. Saplings grow designs (`growDesign`)
    and take root in a dimension's own ground (`World.isSoil`, `ModDimRT.soils`).
  - Logic Studio: scripts are data compiled to `LInstr` and run by `runLogic` a little each frame (`LLimits`:
    300 steps a script per frame, 3000 in all, groups 8 deep, a loop that never waits is stopped after 10 s).
    Events are fired from the game with `fireLogic`; variables are saved per world (`SaveData.logicVars`).

## Game design

The `game-design` skill (`.claude/skills/game-design`) holds the design method and references: fun
and motivation, loops and retention, game feel, systems and progression, UI and UX, onboarding,
pixel art, monetization and its ethics, building bigger games, a critique checklist, and tools and a
reading list for studying talks. `docs/design-plan.md` applies it to PixelRealm: pillars, what the
game already does well, gaps, and steps in order of value for effort. Read the plan before
proposing a new step, and update it when a step lands.

## Working with the user

The user works on an iPad and reads results in the Claude app. Keep reports plain and short. Send
files with SendUserFile. When delivering the game, attach all eight parts, `PixelRealm1.swift` to
`PixelRealm8.swift`, and say which changed.
