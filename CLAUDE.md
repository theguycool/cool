# PixelRealm

A 2D sandbox survival game for iPad, written in SwiftUI and run in Swift Playgrounds. The whole game
is one file, `PixelRealm.swift` (about 43,600 lines, indented with tabs), and it must stay one file:
the user pastes it into Swift Playgrounds and asks for every change "all in one file".

**The iPad has to be able to build it: the game is at that limit now.** This is the last version known
to start on the user's iPad (commit 598e07b, re-indented with tabs). The Mod Creator+ round added about
21% more compiled code; it built and passed every test here, but would not start on the iPad, with no
error shown, even after its screens were slimmed and the file re-indented. It was taken back out. Its
code is parked in git: commit 98fd773 (the stages are debd213, 9d3845f, f77eabd, 03be003, f11ccad).
- Treat this version's debug build as the budget: `tools/buildcost.sh` gives 63 s and 860 MB here,
  against 86 s and 1,059 MB for the Mod Creator+ version on the same machine. Times vary between
  machines, so compare on one machine (`GAME_SRC=<other file> tools/buildcost.sh`); memory varies less.
- Add code in small steps, and have the user check each one starts before building on it.
- Make room by slimming existing code (same features, less code), or ask the user what to drop.

## Checking a change

In cloud sessions a SessionStart hook (`.claude/hooks/session-start.sh` → `tools/setup.sh`) installs
Swift 6.0.3 under `/opt/pixelrealm` and builds stand-ins for SwiftUI and AVFoundation so the game
compiles and runs headless on Linux. If `/opt/pixelrealm` is missing, run `tools/setup.sh` (about a minute).

- `tools/typecheck.sh`: about 39 s. Run it after every batch of edits.
- The swift-lsp plugin (if loaded) checks the file as it is edited: `compile_flags.txt` points
  sourcekit-lsp at the stand-ins, and setup.sh installs it. A full check of the file takes about
  30 s, so wait for its diagnostics; `tools/typecheck.sh` remains the check of record.
- `tools/run-tests.sh [suite ...]`: builds and runs suites from `tools/tests`, four at a time (all
  of them take several minutes). Pass only the suites you touched while iterating, and run them all
  before committing. Full output is in `/tmp/pixelrealm-build/<suite>/out.log`.
- `tools/shots.sh power|weather|sky|cloudsheet|stick|alchemy [folder]`: PNG screenshots from the game's own renderer (`sky`: clouds by day, dusk, night and storm; `cloudsheet`: every cloud template; `stick`: the combat stick's dial; `alchemy`: mutated creatures, the worn suit, the new stations, and a sheet of the new icons and suit pictures).
- `tools/bench.sh`: chunk generation, painting, lighting and tick timings (debug build; compare
  with `GAME_SRC=<old file> tools/bench.sh`).
- `tools/buildcost.sh`: file size, and the time and peak memory of a debug build like the iPad's
  (about 80 s). Run it before delivering anything that adds code, and compare with the budget above.

Suites: `tests`, `round2`, `p2` (general gameplay), `portal`, `boat`, `veh` (vehicles), `combat`,
`mines`, `weather`, `nightai` (night spawning and monster AI), `stick` (the combat stick), `power` (Sparkworks), `snd` (sound
effects ≤ 1.2 s, thunder ≤ 3.2 s), `oldsave` (saves from an older version still load; uses
`tools/fixtures`), `mods` (the Mod Creator: file format, store, checks, custom content in play,
structures, test worlds, an end-to-end run; it uses a scratch mod folder, never the real one), `alchemy`
(potions and status effects, throwing, mutation and its limits, infusions, the exosuit: building, wearing,
modules, power, saving), and
`det` and `det2` (world generation fingerprints for generator versions 1 to 4).

What the stand-ins can't tell you:
- They only declare the SwiftUI and AVFoundation API the game uses. If you use a new API, add it to
  `tools/shim/SwiftUI.swift` with the real signature (setup.sh rebuilds the shim when its source
  changes). Prefer APIs the file already uses: anything that compiles only against the shim breaks
  on the iPad. The shim's `StrokeStyle` takes no `lineCap`, its `Path` has no `isEmpty` or
  `addRoundedRect`, and there is no `LinearGradient`. (It also stands in for `UIPasteboard`, `UIImage`
  and `CGContext` drawing, which only the parked Sprite Studio used.)
- Only the world Canvas is rasterised. SwiftUI panels are compile-checked but never drawn.
- Nothing has been run on a real iPad from here. Say so in reports.

## Rules for the code

- **Type-checker speed.** Write explicit types on locals (`let x: Double = ...`), join strings with
  `joinText(...)` instead of long `+` chains, and split big expressions. Keep typecheck near 39 s.
- **Small SwiftUI bodies.** The real SwiftUI has far more overloads than the stand-ins, so keep each view
  body short: sections as their own computed properties or functions, button actions in methods,
  closures with typed parameters (`{ (it: Item) in ... }`), strings and colours worked out in `let`s
  first, `Double` ranges written out (`0.0...1.0`), and rows of similar controls built from a table.
- **Indent with tabs.** Four spaces per level made the file a sixth bigger.
- **Saves.** Saved enums (`Tile: UInt8`, `MobKind`, `Mat`, `Gadget`, `RecipeCat`, `SoundID`, `Potion`,
  `Infusion`, `ExoMat`, `ExoPart`, `ExoCore`, `ExoModule`, `ExoSlot` and the like) only get new cases
  appended at the end. Never reorder or remove cases. New `SaveData` fields are optional; new `Settings`
  fields are decoded with `decodeIfPresent` and a default.
- **Infusions live on the stack** (`Stack.inf`). Code that moves an item between bag, chest, carried and
  dropped must keep the whole `Stack`, or pass `inf:` to `Inventory.add`; infused items never merge.
- **World generation is frozen for existing worlds.** `det` and `det2` must pass unchanged. Changes
  to generation go behind a new generator version. Version 5 (current) has no villages; versions 1 to 4
  still generate them (`WorldGen.hasVillages`) so saved worlds keep matching, but nothing in the game
  uses villagers, trades or village goals any more (`MobKind.villager` stays only for saved numbering).
- **A new tile needs:** an appended case, a `Tile.makeDef` entry, 8x8 art in `customTileRows`, and,
  as relevant, `needsSupport`, `toolClass`, `isInteractive`/`interact`, and the exclusions in
  `creativeItems` for on/off variants. New tiles go after `exoStation` (after the 64 mod tiles);
  `Tile.isMod` is a range check, so they are not mistaken for mod blocks.
- **A new panel** needs its `@Published` show flag added to `updateInputGate` and to the condition
  that hides the HUD in `GameView`.
- **Mod data.** New fields of mod content (`ModBlock`, `ModItem`, `ModMob` and the rest) get a default
  and are decoded with `c.val(.key, default)`, and get a clamp in `ModValidator.check`. Mod enums only
  get cases appended. Tests never touch the real mod folder or saves: set `ModStore.overrideDir` and
  use `makeSave()` with a JSON round trip.
- **Comments** are plain-language doc comments explaining what something does in the game. Match the
  surrounding style.
- Commit and push to the branch the session names. Never put model names in commits.

## Map of the file

Sections start with `// ===== <name> =====` (grep for them):
`p01_util`, `p02_tiles` (Tile, defs, art), `p03_items`, `p04_recipes` (RecipeBook), `p05*` (creature
sprites), `p06_worldgen`, `p07_chunk`, `p08*` (villages, ruins), `p09_umbral`, `p10_world` (World,
chunks, `set`), `p11_light`, `p12_phys`, `p13a_mobdefs` (MobKind, MobDef, spawn rules, Mob),
`p13b_vehicles`, `p14a_game` (Game state, Settings), `p14b_player` (`tick`, the frame), `p14c_input`
(pointer, `interact`), `p14d_tools` (item use, mining, placing), `p15a_mobai` (`updateMobs`,
`think`, the per-kind AIs), `p15b_spawn` (`updateSpawning`), `p16*` (combat, damage, bosses), `p17`
(vehicles, ships), `p18` (portal, map), `p19_save` (`SaveData`, `makeSave`, `Game.load`), `p20`–`p26`
(helpers, walls, doors, HUD logic), `p27_power` (Sparkworks), `p28_mods` (Mod Creator: data,
store, checks, runtime, custom creature AI, structures and capture, test tools), `p29_alchemy` (rarity, potions, effects on creatures, smoke,
mutation and its limits, chest extras, the recipes of all three new systems), `p30_infusion`,
`p31_exosuit` (parts, stats, energy, modules, the worn look, the builder's pictures), `u01_art`, `u02_render`
(`WorldRenderer.draw` sets the draw order), `u03_hud`, `u04_panels`, `u05_menu`, `u07_mods` (Mod
Creator screens and editors, the capture and Mod Test panels), `u08_alchemy` (the HUD's effect strip and
suit bar, the Infusion Crucible screen, the Assembly Station builder), `u06_root`.

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
  weather devices update in `updateWeatherDevices`.
- **Night monsters.** `updateSpawning`:
  - monsters have their own limit (`monsterCap`, set by the Nights setting); wild predators have a
    separate one;
  - `monsterSpawnCD` paces new arrivals;
  - `spawnLog` records why each spawn attempt failed (shown in the debug panel).
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

## Working with the user

The user works on an iPad and reads results in the Claude app. Keep reports plain and short. Send
files with SendUserFile. When delivering the game, attach `PixelRealm.swift` itself.
