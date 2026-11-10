# Building bigger games

## Design side

- **Pillars.** Three to five short statements of what the game is ("a world that reacts", "build
  anything, then use it"). Every feature must serve one; features that serve none are cut or wait.
- **A vertical slice first.** One small stretch made complete (feel, art, sound, UI) before making
  more of it. It proves the fun and sets the quality bar.
- **Systems over content.** Content made by hand grows linearly; systems that combine grow faster
  (see `systems-and-progression.md`). A bigger game should mostly be more *interactions*, not more
  *things*.
- **Content pipelines.** Make adding a thing cheap: data tables, an editor, templates. If adding an
  enemy takes a day of code, the game will have few enemies. A mod tool is a content pipeline.
- **Players as creators.** Mods, sharing, structures and designs make the game bigger than its
  makers can.
- **Steps the player can check.** Add a big feature in steps, each playable and testable alone.
  After each step: play it, measure it, fix it, write down what was learned.
- **Design document, short and living.** Eight sections are enough: overview and pillars, player
  fantasy, core loop and loops at each scale, systems, progression, world and content, UI and
  controls, art and sound direction. Update it as the game changes; out-of-date plans mislead.

## Production side

- **Scope by cutting.** List features, rank by value for effort, cut from the bottom. A smaller
  game that is finished beats a bigger one that isn't.
- **Playtest early and often.** Watch without helping; write down where players stop, look
  confused, or smile. Players find the problems; you find the solutions.
- **Measure.** Where do players die, quit, get stuck, spend their time? Even without analytics,
  a debug overlay and test worlds tell a lot.
- **Tuning in data.** Keep numbers in tables, not scattered in code, so balance changes are cheap.
- **Automated checks.** Tests for saves loading, generation staying the same, and systems working,
  so growth doesn't break the old.

## Code patterns that scale (Robert Nystrom, *Game Programming Patterns*)

- **Game loop** with a fixed or clamped time step; update and draw separate.
- **Update method** per object; **component** to share behaviour without deep inheritance.
- **State machine** for AI and modes (idle, alert, chase, attack, retreat).
- **Event queue / observer** to decouple systems (a block breaks: sound, particles, power, physics
  all hear it).
- **Flyweight / type object**: one shared definition per kind (a tile table, a creature table),
  instances hold only what differs.
- **Spatial partition** (chunks, grids) so only nearby things are checked.
- **Dirty flag** and caches: recompute only when something changed (light, pictures, stats).
- **Object pool** for particles and projectiles.
- **Data locality**: keep hot data in plain arrays.
- **Command** for undo and replays.
- **Save versioning**: every saved format can grow without breaking old saves.

## Signs a game is getting too big

- New features need changes in many unrelated places.
- Players can't name the main thing the game is about.
- The first hour shows half the systems.
- Old features stop working and nobody notices (missing tests).
- The build or start-up time keeps growing (on PixelRealm, watch `tools/buildcost.sh`).
