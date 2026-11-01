# Pixel Realm for Godot (Xogot) — working notes

The Godot project lives in `godot/PixelRealm/` (open that folder in Xogot / Godot 4.3+). It is a rebuild of
`PixelRealm.swift` in GDScript. Art, sounds and data tables are exported from the Swift game itself:

- `tools/export.sh [out]` builds `tools/export/main.swift` against the game and dumps raw pixel buffers,
  sound samples and JSON tables (default `/tmp/prexport`).
- `tools/godot_assets.py <export dir> <godot project>` turns them into PNG sheets, WAV files and the
  generated data scripts in `scripts/data/` (never edit those by hand).
- `tools/godot_check.py <godot project>` is the static checker (gdparse syntax check of every script,
  res:// paths, scene files, autoload and class references, calls on known classes).
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
