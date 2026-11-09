# PixelRealm

A 2D sandbox survival game for iPad, written in SwiftUI and run in Swift Playgrounds. The game is four
files, `PixelRealm1.swift` to `PixelRealm4.swift` (about 57,200 lines in all, indented with tabs). The
user pastes each into its own file of one Swift Playgrounds app. It was one file until the user asked
for four; deliver all four, and treat them as one program (Swift doesn't care which file holds what).

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
  runs the four jobs at once in one process, they could add up; that is not known.
- Add big features in steps the user can check on the iPad, and keep the parts about equal in
  compiled size (`tools/buildcost.sh` prints each job's peak).

## Checking a change

In cloud sessions a SessionStart hook (`.claude/hooks/session-start.sh` → `tools/setup.sh`) installs
Swift 6.0.3 under `/opt/pixelrealm` and builds stand-ins for SwiftUI and AVFoundation so the game
compiles and runs headless on Linux. If `/opt/pixelrealm` is missing, run `tools/setup.sh` (about a minute).

- `tools/typecheck.sh`: about 39 s. Run it after every batch of edits.
- The swift-lsp plugin (if loaded) checks a file as it is edited: `compile_flags.txt` points
  sourcekit-lsp at the stand-ins, and setup.sh installs it. It sees one part at a time, so names
  from the other parts show as missing; `tools/typecheck.sh` (all four parts together) is the check
  of record.
- `tools/run-tests.sh [suite ...]`: builds and runs suites from `tools/tests`, four at a time (all
  of them take several minutes). Pass only the suites you touched while iterating, and run them all
  before committing. Full output is in `/tmp/pixelrealm-build/<suite>/out.log`.
- `tools/shots.sh power|weather|sky|cloudsheet|stick|alchemy|modplus|building|vehicles [folder]`: PNG screenshots from the game's own renderer (`sky`: clouds by day, dusk, night and storm; `cloudsheet`: every cloud template; `stick`: the combat stick's dial; `alchemy`: mutated creatures, the worn suit, the new stations, and a sheet of the new icons and suit pictures; `modplus`: two custom dimensions and a boss in a phase; `building`: a furnished house with stairs and a lift, a blast throwing blocks, a beam under strain; `vehicles`: every new kit parked, a plane, helicopter and airship flying, a tank firing at a wrecked truck, a ship built from blocks with the assembler, a plane mid-turn).
- `tools/bench.sh`: chunk generation, painting, lighting and tick timings (debug build; compare
  with `GAME_SRC=<old file> tools/bench.sh`).
- `tools/buildcost.sh`: the game's size, and the time and peak memory of a debug build like the
  iPad's, as one job and as one job per file (a few minutes). Run it after adding a lot of code.
- The tools read the four parts (`pr_game_files` in `tools/env.sh`). `GAME_SRC` can name another
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
stairs, lifts, block weight, blasts, storms carrying blocks, structural physics), `aero` (vehicles of
every kind: the plane, helicopter, airship, tank and truck kits flown and driven, designs too heavy to
fly, turning in flight, blocks built onto vehicles, rafts that float or sink by their blocks, the
assembler, shots, blasts and crashes, wrecks, mending, the autopilot, saves, a mod block as a part),
and `det` and `det2` (world generation fingerprints for generator versions 1 to 4).

What the stand-ins can't tell you:
- They only declare the SwiftUI and AVFoundation API the game uses. If you use a new API, add it to
  `tools/shim/SwiftUI.swift` with the real signature (setup.sh rebuilds the shim when its source
  changes). Prefer APIs the file already uses: anything that compiles only against the shim breaks
  on the iPad. The shim's `StrokeStyle` takes no `lineCap`, its `Path` has no `isEmpty` or
  `addRoundedRect`, and there is no `LinearGradient`. The Sprite Studio's clipboard (`UIPasteboard`,
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
- **Saves.** Saved enums (`Tile: UInt8`, `MobKind`, `Mat`, `Gadget`, `RecipeCat`, `SoundID`, `Potion`,
  `Infusion`, `ExoMat`, `ExoPart`, `ExoCore`, `ExoModule`, `ExoSlot`, `Dimension` (custom0-2 were appended),
  `PartType` (vehicle parts: `block` and the aircraft parts were appended), `ProjKind`
  and the like) only get new cases appended at the end. Never reorder or remove cases. New `SaveData` fields are optional; new `Settings`
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
- **A new tile needs:** an appended case, a `Tile.makeDef` entry, 8x8 art in `customTileRows`, and,
  as relevant, `needsSupport`, `toolClass`, `isInteractive`/`interact`, and the exclusions in
  `creativeItems` for on/off variants, and a line in `blockPhysOf` (its weight, carry and reach).
  New tiles go after `liftCar` (the last one; all after the 64 mod tiles); `Tile.isMod` is a range
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
  `LEvent`, `LOp`, `LEOp`). References inside a mod are content keys: renamed in `ModStore.rekey` and
  counted in `ModStore.dependencies` (game tiles are `"tile:<n>"`, never renamed). A mod block can work as a
  vehicle part (`ModBlock.vehRole`, `vehMass`, `vehPower`; `ModVehicleRole` is append-only). Tests never touch the real mod folder or saves: set `ModStore.overrideDir` and
  use `makeSave()` with a JSON round trip.
- **Comments** are plain-language doc comments explaining what something does in the game. Match the
  surrounding style. Each part starts with the same header and imports; keep them alike.
- Commit and push to the branch the session names. Never put model names in commits.

## Map of the parts

Sections start with `// ===== <name> =====` (grep for them). They are spread over the parts in order:
part 1 `p01_util` to `p14d_tools`; part 2 `p15a_mobai` to `p31c_blockphys`; part 3 `p32_modplus`, then
`u01_art` to `u05_menu`; part 4 `p33_vehicles`, then `u07_mods`, `u08_alchemy`, `u09_modplus`, `u06_root`. New code goes into
the section it belongs to. A `private` or `fileprivate` name can only be used in its own part, so
anything used across parts is internal (no modifier).

The sections:
`p01_util`, `p02_tiles` (Tile, defs, art), `p03_items`, `p04_recipes` (RecipeBook), `p05*` (creature
sprites), `p06_worldgen`, `p07_chunk`, `p08*` (villages, ruins), `p09_umbral`, `p10_world` (World,
chunks, `set`), `p11_light`, `p12_phys`, `p13a_mobdefs` (MobKind, MobDef, spawn rules, Mob),
`p13b_vehicles`, `p14a_game` (Game state, Settings), `p14b_player` (`tick`, the frame), `p14c_input`
(pointer, `interact`), `p14d_tools` (item use, mining, placing), `p15a_mobai` (`updateMobs`,
`think`, the per-kind AIs), `p15b_spawn` (`updateSpawning`), `p16*` (combat, damage, bosses), `p17`
(vehicles, ships), `p18` (portal, map), `p19_save` (`SaveData`, `makeSave`, `Game.load`), `p20`–`p26`
(helpers, walls, doors, HUD logic), `p27_power` (Sparkworks), `p28_mods` (Mod Creator: data,
store, checks, runtime, custom creature AI, structures and capture, test tools), `p32_modplus` (Mod Creator+: changes
to game content, ore controls, sprite tools, custom infusions, boss phases and summoning, custom dimensions, the
Logic Studio), `p29_alchemy` (rarity, potions, effects on creatures, smoke,
mutation and its limits, chest extras, the recipes of all three new systems), `p30_infusion`,
`p31_exosuit` (parts, stats, energy, modules, the worn look, the builder's pictures), `p31b_building` (block
walls, ladders, furniture, lifts), `p31c_blockphys` (block weight, flying blocks, blasts, structural
physics), `p33_vehicles` (the flight model, power sharing, damage and wrecks, weapons, turning round,
building blocks onto vehicles, the assembler, the autopilot, the checklist and instruments), `u01_art`, `u02_render`
(`WorldRenderer.draw` sets the draw order), `u03_hud`, `u04_panels`, `u05_menu`, `u07_mods` (Mod
Creator screens and editors, the capture and Mod Test panels), `u08_alchemy` (the HUD's effect strip and
suit bar, the Infusion Crucible screen, the Assembly Station builder), `u09_modplus` (the Mod Creator+ screens: game
content, ore controls, hardness reference, Sprite Studio, infusion, phase, summoning, dimension and script editors,
the Mod Test LOGIC tab), `u06_root`.

## Systems in brief

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
- **Exosuit.** `Game.suit` (`ExoSuit`: a `Stack` per `ExoSlot`, worn, energy) with `suitStats` cached
  by `suitRev` (call `suitChanged()` after any change). The builder edits a plan and `applySuit` fits it
  all at once (parts come from the suit or the bag, the rest go back; all or nothing). Modules spend
  energy through `suitRun` (within the core's output) and `suitSpend`; the Assembly Station is a
  Sparkworks machine that charges a worn suit nearby (`runSuitDock`). The sprite draws the suit
  (`HumanStyle.suit`, `paintSuit`).

- **Mod Creator+.**
  - Changes to game content (`ModOverride`) are built into `OverrideRT` at activation; it restores the
    game's own tables first (`Tile.setGameDef`, `mobDefTable`), so switching a mod off undoes it. `Item.melee`
    goes through `baseMelee`.
  - Ores keep the old placement for old settings (`ModOreRT.place`); new controls use their own random seed.
  - Custom infusions are numbered from 1000 per world (`ModWorldInfo.infusions`) and live in `Stack.inf` beside
    the game's; their compound is a mod item under the same key.
  - Phases: `stepPhases`/`enterPhase` in `updateCustomMob`; numbers on the `Mob` (`mphase`, `phaseDmg`...).
    Summoning: `ModSummonRT` (an item, a shape, conditions); dimension ways in are summonings with `dimSlot`.
  - Custom dimensions take slots 2-4 (`Dimension.custom0`...); `dimCount` is 5 everywhere a list is kept per
    dimension. Their land is `fillCustomChunk`; sky `drawCustomSky`; weather `customWeather`; only their own
    creatures spawn. A world saved in a dimension whose mod is missing starts at the Overworld spawn.
  - Logic Studio: scripts are data compiled to `LInstr` and run by `runLogic` a little each frame (`LLimits`:
    300 steps a script per frame, 3000 in all, groups 8 deep, a loop that never waits is stopped after 10 s).
    Events are fired from the game with `fireLogic`; variables are saved per world (`SaveData.logicVars`).

## Working with the user

The user works on an iPad and reads results in the Claude app. Keep reports plain and short. Send
files with SendUserFile. When delivering the game, attach all four parts, `PixelRealm1.swift` to
`PixelRealm4.swift`, and say which changed.
