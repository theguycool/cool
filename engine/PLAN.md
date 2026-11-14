# PixelRealm on the web engine

The user's iPad could not build the Swift game any more, so the game is being recreated as one web
page (WebGL 2 + JavaScript) published as a private claude.ai artifact:
https://claude.ai/artifact/MFXcLa1hoKgYo2aeyC4Zi5 (publish the same file path to update it;
capabilities `db`, `user`, `downloads` are declared and carried forward).

The Swift game (`PixelRealm1.swift` ... `PixelRealm5.swift`) is the spec. Port its logic section by
section; take its data and art from the Swift game itself with the exporter, never by hand.

## Layout
- `engine/src/*.js`: the engine and game, concatenated in the order of `engine/build.py`'s list into
  one script (one shared scope, "use strict"). Files are named after the Swift sections they port.
- `engine/src/page.html`: the page's CSS and markup with a `/*SCRIPT*/` marker.
- `engine/tools/export.swift` + `engine/tools/export.sh`: dumps tiles, items, recipes, creatures,
  art and sounds from the Swift game; `engine/tools/pack.py` turns them into `engine/src/data_*.js`.
- `engine/build.py`: writes `engine/dist/pixel-engine.html` (what is published) and
  `engine/dist/test.html` (the same with a doctype, for headless tests).
- `engine/test/*.js`: Playwright tests in headless Chromium (`node engine/test/run.js`).

## Page rules (claude.ai artifact)
No doctype/html/head/body tags; `<title>` first; colours as `:root` tokens; no `confirm()`/`alert()`;
no `<a download>` (use the `downloads` capability); storage may throw (try/catch); saves go to the
viewer's private `data/users/<id>/` documents (256 KiB each, written to a spare slot first), with
`localStorage` as the fallback. Stay under 16 MB.

## Phases
1. Foundation: exporter, real tiles/items/art, world generation v6, light, physics, player, mining
   with tools, placing, inventory, drops, crafting, chests, health and hunger, HUD, menu, saves.
2. Creatures and combat: every creature, AI, spawning, weapons, bows, armour, bosses, death.
3. World content: ruins, mineshafts, grottos, Umbral Realm and portal, map, journal, weather, clouds,
   sounds, ambient life.
4. Building: walls, doors, ladders, stairs, furniture, lifts, block physics, flowing liquids.
5. Sparkworks: power, wires, logic, machines, weather devices.
6. Alchemy: potions, effects, mutation, infusion, the exosuit.
7. Vehicles: parts, building, ground, water and air physics, weapons, damage, assembler, autopilot.
8. Rails, big wheels, joints and mechs, automation.
9. Mod Creator and Mod Creator+.
10. Settings, character creator, creative and hardcore modes, flat worlds, debug tools, polish.

## Status
- Before phase 1: a small demo engine is published (own tiles, pigs, sprite maker, stress test).
  The iPad ran its stress test at 60 fps with 8,000 creatures.
