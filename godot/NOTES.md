# Pixel Realm for Godot (Xogot) — working notes

The Godot project lives in `godot/PixelRealm/` (open that folder in Xogot / Godot 4.3+). It is a rebuild of
`PixelRealm.swift` in GDScript. Art, sounds and data tables are exported from the Swift game itself:

- `tools/export.sh [out]` builds `tools/export/main.swift` against the game and dumps raw pixel buffers,
  sound samples and JSON tables (default `/tmp/prexport`).
- `tools/godot_assets.py <export dir> <godot project>` turns them into PNG sheets, WAV files and the
  generated data scripts in `scripts/data/` (never edit those by hand).
- `tools/godot_check.py <godot project>` is the static checker (gdparse syntax check of every script,
  res:// paths, scene files, autoload and class references, calls on known classes).
- `python3 tools/godot_check.py godot/PixelRealm` must report 0 errors before a commit. It was tested by planting
  mistakes (unknown methods, wrong argument counts, Variant `:=`, bad scene properties); it caught all of them.
- Godot itself could not be downloaded in the cloud session, so nothing here has been run in Godot.

## Units and coordinates
- One block = 8 px (all art is 8 px per block). y grows downward. World rows 0..559, sea level 120.
- Tile (x, y) covers pixels [x*8, x*8+8) × [y*8, y*8+8). `TILE = 8`.
- Bodies (player, creatures) have their origin at the feet, horizontally centred (like the Swift `Body`).
- Speeds from Swift (blocks/s) × 8 = px/s. Gravity 34 b/s² = 272 px/s², terminal 26 b/s = 208 px/s,
  jump −15.9 b/s = −127.2 px/s, run 7.4 b/s = 59.2 px/s.
- Camera zoom 4 at the 1280×720 base size (≈40×22 blocks on screen), stretch mode canvas_items, aspect expand.

## Autoloads (project.godot)
- `DB` (scripts/autoload/db.gd): tile, item, recipe, creature tables + lookups (built from scripts/data/*).
- `Art` (scripts/autoload/art.gd): textures, TileSet, SpriteFrames for creatures and the player, icons.
- `Sfx` (scripts/autoload/sfx.gd): sound pool and ambience loops.
- `Game` (scripts/autoload/game.gd): settings, the running session (world, player, inventory), save/load,
  scene changes. No class_name on autoload scripts.

## Ids
- Tiles: ints (the Swift `Tile` raw values). `T.STONE` etc. in scripts/data/t.gd (generated, class_name T).
- Items: strings, the Swift enum path: "block:stone", "tool:pickaxe:iron", "sword:iron", "armor:head:iron",
  "mat:coal", "food:bread", "bow", "gun:pistol", "ammo:arrow", "part:wheel", "gadget:bomb", "wall:2",
  "spear:iron", "hammer:iron", "gear:headlamp", "knife:iron", "club:mace", "sling", "relic:moonDagger".
- Creatures: string keys ("zombie", "bearBoss"...). Tiers: ints 1..9 (wood..voidium).
- Inventory slot = null or {"id": String, "n": int, "x": int (loaded shots / extra)}.

## Layout
scripts/autoload, scripts/data (generated), scripts/world (gen, chunks, view, light, structures),
scripts/entities (player, mob, drop, projectile), scripts/systems (combat, spawner, sky, weather,
inventory, crafting, saves), scripts/ui (hud, sticks, buttons, panels, menu). scenes/*.tscn.

## Touch input (multi-touch)
- Every HUD control (sticks, buttons, hotbar slots) handles `InputEventScreenTouch`/`ScreenDrag` in
  `_gui_input`, keyed by the touch index, and accepts the event; Godot routes a touch to the control
  it started on, so the walking stick, JUMP and the attack stick work at the same time.
- Emulated mouse events (device -1) are ignored by those controls and by the level; real mouse input
  still works for desktop testing. Panels use ordinary Buttons (fed by the emulated mouse) plus
  `ScrollList` and `SlotBoard`, which handle touch themselves (drag to scroll, tap, hold, drag stacks).
- Taps that hit no control reach `Level._unhandled_input` and become the world pointer.

## UI building blocks (scripts/ui)
- `PanelBase`: dimmed backdrop, centred framed box that fits the screen, works while paused, Escape closes.
- `UIKit`: theme, buttons, labels, the settings rows shared by the pause menu and the main menu.
- `ScrollList`: rows with icons, wrapped text, cost icons, right-hand buttons and ON/OFF switches.
- `SlotBoard`: bag, hotbar, armour, gear, chest and DROP as one drawn board (tap, hold, drag).

## Not recreated (see the report)
- Sparkworks power and automation (wires, generators, batteries, logic, machines). Levers and switches
  toggle lamps and steel gates within 6 blocks instead; the wiring items say they are not available.
- Pirate ships at sea (replaced by pirate landing parties on coasts; the captain drops the treasure).
- Building vehicles from parts (the kits work), ground snow and puddles, hurricane surges and wind
  tearing blocks loose, falling sand as a moving block (sand drops straight to where it lands).
