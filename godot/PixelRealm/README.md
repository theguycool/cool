# Pixel Realm for Godot / Xogot

Pixel Realm rebuilt as a Godot 4 project (GDScript), made for Xogot on iPad. The art, sounds and data
tables come from the original Swift game.

## Opening it in Xogot (iPad)

1. In the Files app, tap `PixelRealm-Godot.zip` to unpack it. You get a folder named `PixelRealm`
   that contains `project.godot`.
2. Open Xogot. In the project list, choose Import (or Open) and pick the `PixelRealm` folder.
3. The first time, Xogot imports about 350 images and sounds, which takes a minute. If the Output
   panel shows class or script errors during that first import, wait until it finishes, then close
   and reopen the project.
4. Press Play. The game starts on the main menu.

The project targets Godot 4.3. If Xogot runs a newer Godot and offers to upgrade the project, accept.

## Controls

- Left stick: walk; pull down to drop through platforms or climb down ladders.
- JUMP: jump, swim up, climb.
- Right (attack) stick: hold to attack or use the item in hand. With your thumb in the middle the
  game aims for you; slide out to aim in any direction.
- Tap the world: mine, attack, place or use there. A quick tap on a door, chest, crafting station,
  pet or vehicle uses it.
- Hotbar: tap a slot. BAG opens the inventory and crafting. The button above JUMP swaps weapons.
- Top right: zoom, MAP (once you have the treasure map), LOG (journal), DBG (debug menu), II (pause).
- Keyboard (optional): A/D, W or Space, S, 1-0, Q, E, J, M, R, F, F3, Esc.

## Project layout

- `scenes/`: main menu, level, player, creature, dropped item, projectile, vehicle.
- `scripts/autoload/`: DB (game data), Art (textures, tile set, animations), Sfx (sound), Game
  (settings, saves, scene changes).
- `scripts/world/`: world generation, chunks, structures, loot, the tile view and lighting.
- `scripts/entities/`: player (CharacterBody2D), player actions, creatures, drops, projectiles,
  vehicles.
- `scripts/systems/`: inventory, input, effects, journal, saves, spawning, weather, sky, debug tools.
- `scripts/ui/`: HUD, sticks and buttons, panels (inventory and crafting, pause, death, journal,
  map, weather, debug), main menu.
- `scripts/data/`: tables generated from the Swift game (tiles, items, recipes, creatures, loot).
- `assets/`: pixel art (tiles, items, creatures, player and armour, sky, UI, effects) and sounds.

Saves go to `user://saves` (six slots) and settings to `user://settings.json`.
