# PixelRealm

A 2D sandbox survival game for iPad, written in SwiftUI and run in Swift Playgrounds. The whole game
is one file, `PixelRealm.swift` (about 31,000 lines), and it must stay one file: the user pastes it
into Swift Playgrounds and asks for every change "all in one file".

## Checking a change

In cloud sessions a SessionStart hook (`.claude/hooks/session-start.sh` → `tools/setup.sh`) installs
Swift 6.0.3 under `/opt/pixelrealm` and builds stand-ins for SwiftUI and AVFoundation so the game
compiles and runs headless on Linux. If `/opt/pixelrealm` is missing, run `tools/setup.sh` (about a minute).

- `tools/typecheck.sh`: about 25 s. Run it after every batch of edits.
- The swift-lsp plugin (if loaded) checks the file as it is edited: `compile_flags.txt` points
  sourcekit-lsp at the stand-ins, and setup.sh installs it. A full check of the file takes about
  30 s, so wait for its diagnostics; `tools/typecheck.sh` remains the check of record.
- `tools/run-tests.sh [suite ...]`: builds and runs suites from `tools/tests`, four at a time (all
  of them take several minutes). Pass only the suites you touched while iterating, and run them all
  before committing. Full output is in `/tmp/pixelrealm-build/<suite>/out.log`.
- `tools/shots.sh power|weather|sky|cloudsheet|stick [folder]`: PNG screenshots from the game's own renderer (`sky`: clouds by day, dusk, night and storm; `cloudsheet`: every cloud template; `stick`: the combat stick's dial).
- `tools/bench.sh`: chunk generation, painting, lighting and tick timings (debug build; compare
  with `GAME_SRC=<old file> tools/bench.sh`).

Suites: `tests`, `round2`, `p2` (general gameplay), `portal`, `boat`, `veh` (vehicles), `combat`,
`mines`, `weather`, `nightai` (night spawning and monster AI), `stick` (the combat stick), `power` (Sparkworks), `snd` (sound
effects ≤ 1.2 s, thunder ≤ 3.2 s), `oldsave` (saves from an older version still load; uses
`tools/fixtures`), and `det` and `det2` (world generation fingerprints for generator versions 1 to 4).

What the stand-ins can't tell you:
- They only declare the SwiftUI and AVFoundation API the game uses. If you use a new API, add it to
  `tools/shim/SwiftUI.swift` with the real signature (setup.sh rebuilds the shim when its source
  changes). Prefer APIs the file already uses: anything that compiles only against the shim breaks
  on the iPad. The shim's `StrokeStyle` takes no `lineCap`, and its `Path` has no `isEmpty` or
  `addRoundedRect`.
- Only the world Canvas is rasterised. SwiftUI panels are compile-checked but never drawn.
- Nothing has been run on a real iPad from here. Say so in reports.

## Rules for the code

- **Type-checker speed.** Write explicit types on locals (`let x: Double = ...`), join strings with
  `joinText(...)` instead of long `+` chains, and split big expressions. Keep typecheck near 25 s.
- **Saves.** Saved enums (`Tile: UInt8`, `MobKind`, `Mat`, `Gadget`, `RecipeCat`, `SoundID` and the
  like) only get new cases appended at the end. Never reorder or remove cases. New `SaveData`
  fields are optional; new `Settings` fields are decoded with `decodeIfPresent` and a default.
- **World generation is frozen for existing worlds.** `det` and `det2` must pass unchanged. Changes
  to generation go behind a new generator version. Version 5 (current) has no villages; versions 1 to 4
  still generate them (`WorldGen.hasVillages`) so saved worlds keep matching, but nothing in the game
  uses villagers, trades or village goals any more (`MobKind.villager` stays only for saved numbering).
- **A new tile needs:** an appended case, a `Tile.makeDef` entry, 8x8 art in `customTileRows`, and,
  as relevant, `needsSupport`, `toolClass`, `isInteractive`/`interact`, and the exclusions in
  `creativeItems` for on/off variants.
- **A new panel** needs its `@Published` show flag added to `updateInputGate` and to the condition
  that hides the HUD in `GameView`.
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
(helpers, walls, doors, HUD logic), `p27_power` (Sparkworks), `u01_art`, `u02_render`
(`WorldRenderer.draw` sets the draw order), `u03_hud`, `u04_panels`, `u05_menu`, `u06_root`.

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

## Working with the user

The user works on an iPad and reads results in the Claude app. Keep reports plain and short. Send
files with SendUserFile. When delivering the game, attach `PixelRealm.swift` itself.
