# PixelRealm: the physics overhaul, plan

The aim (the user's words): players build practically anything from blocks, parts, servos, engines,
wheels, rotors, wings, liquids and electronics, and the game works out what happens from what was
built, with no fixed vehicle types, no arbitrary speed caps and no templates.

This plan was written after reading the physics in all six parts. It says what exists, what the
shared foundation is, and the order of the phases. Each phase is delivered on its own so it can be
checked on the iPad before the next one starts.

## What the game has today

| Area | Today | Gap |
|---|---|---|
| Bodies (player, creatures, drops) | `Body` + `World.moveBody`: swept in steps of 0.3 blocks, stairs, platforms, step-up | Bodies only know the land. A vehicle is one flat "deck" across the top of its box, and only while parked and level |
| Vehicles | A rigid body of 1x1 cells (`Vehicle`): mass per cell, centre of mass, inertia, rotation, contact impulses with friction at sample points, per-part buoyancy, per-part air forces (lift, drag, stall, thrust, rotors, hot air) | Speed clamped to 30, spin to 12; engines stop pushing above a fixed top speed; a step is split in two at most, so anything fast could pass through thin walls; vehicles only shove each other's boxes apart |
| Riding | The driver is pinned to the seat. Jump leaves the seat only below 2.5 blocks a second | Nobody can stand, walk or jump on or inside a moving vehicle |
| Blocks | `BlockPhys` (weight, carry, span) per tile; `FallingBlock` flies, bounces and settles; blasts; storms; optional structural physics | Reach is 1 to 5 blocks; no friction or bounce per material; no beams |
| Water | A still tile. Never flows. No other liquids | No fluid simulation at all |
| Rails, ore cart | Decoration found in mines (a plant-like tile and a loot box) | Nothing runs on rails |
| Wind | Weather gives a wind at every place; it moves flying blocks, shots, the player and aircraft | No gusts on aircraft, no setting for its strength |
| Joints, servos, mechs | None | New |
| Autopilot | Cruise and routes; a route runs with nobody aboard, but only near the player (loaded land) | Cruise stops when the pilot stands up; nothing runs far away |
| Power and logic | Sparkworks networks and the Logic Studio | Not connected to vehicles |
| Mods | Blocks as vehicle parts, whole vehicles, weight and carry, rules, weather | The new systems need their own editors |

## The shared foundation

One set of ideas that everything uses, instead of one physics per feature.

1. **Material properties** (`BlockPhys`, one table for every tile and mod block): weight, carry,
   span, and now friction and bounce. Used by vehicles (what a cell weighs, how a wheel or a hull
   grips the ground it touches), falling blocks, blasts, structures. Later phases add density for
   floating and strength for beams to the same table.
2. **Mass for everything that moves**: every creature has a mass from its size and build
   (`mobMass`), the player has one, a vehicle's is the sum of its cells. Collisions and loads use
   them: a heavy creature tips a small raft, a light cart is pushed by a bear, a car slows more
   when it hits something heavy.
3. **Frames** (new, `p12b_frames`): a body is either in the land's frame or in a vehicle's. In a
   vehicle's frame its position is kept in the vehicle's own cell coordinates and it collides with
   the vehicle's cells as if they were land (floors, walls, ceilings, one-way platforms like wings).
   Its world position is worked out from the vehicle every frame, so it is carried exactly through
   any speed, climb or turn with no drift. The frame changes by contact: land on a vehicle and you
   are in its frame, step onto the ground and you are back in the land's. Bodies in the land's
   frame are pushed out of vehicle cells that reach them (being bulldozed), and a rider the land
   gets in the way of is scraped off. The player, creatures and dropped items all use it. Servo
   sections (phase 5) will be frames too.
4. **One step rule**: nothing moves more than a fraction of a block between collision checks.
   Bodies already did this; vehicles now split their step as many times as their speed needs, and
   skip the checks altogether when no land, water or vehicle is near (open sky costs nothing).
   There are no speed clamps: top speed comes from thrust, weight, drag and friction.
5. **Forces on cells**: gravity, buoyancy, drag, lift, thrust and contact all act on a vehicle at
   the cell they come from (this was already so). New parts in later phases (joints, ballast,
   rail wheels, couplers) add forces the same way.
6. **Cell grids with insides** (phase 3 onward): the same grid that bodies walk on tells which
   empty cells are enclosed. Enclosed air is what makes a hollow hull float; an opening under
   water floods it.

## Phases

The user's parts 1 to 16 are all covered. The order is theirs with three changes, explained below.

### Phase 1: core physics (done)
- Material friction and bounce in `BlockPhys` (ice, snow, mud, sand, glass, sandbags, hay, crates),
  and in the Mod Creator's block editor; mass for creatures by size and build, and the player.
- Frames: stand, walk and jump on and inside vehicles while they move, climb and turn; creatures
  and dropped items ride too; riders weigh on the vehicle where they stand; vehicle sides and
  undersides block bodies; a moving vehicle pushes what it meets, and bodies push back by weight.
- Leaving the seat at any speed when there is a floor under it; the autopilot (cruise or route)
  keeps the controls when the pilot stands up. Shots from a moving vehicle keep its speed. The
  view is carried with the vehicle, so it keeps up at any speed.
- No speed clamps. Engines give power rather than a top speed (force falls as speed rises; drag
  and drivetrain loss set the top speed, so more engines or less weight is faster). Boats lose
  their fixed top speed too. The kits keep their old speeds.
- High speed: as many sub-steps as the speed needs, open-air fast path; contacts solved together
  over four rounds (the old one-pass response made a block landing flat bounce and spin
  differently every run, and once let one fall through the ground).
- Tests (`phys1`, 54 checks): unusual builds (three wheels, a sofa, a wing and a jet; a house under
  a balloon walked about in flight), 500 blocks a second against walls one and three blocks thick,
  riders at 500, a raft carrying a chicken, a pig and an elephant, pushing light and heavy loads.
- Known limits: creature AI still reads the land's tiles, so creatures aboard mostly stand or
  wander and do not plan around the vehicle; ladders, doors and background walls on vehicles are
  phase 2; vehicles still meet each other as boxes until phase 2; the player, creatures and loose
  blocks still fall no faster than 26 blocks a second (as before; it becomes air drag with the
  structural work of phase 7, which also gives loose blocks sub-steps).

### Phase 2: vehicle foundations
- Vehicles collide with each other cell by cell with real impulses (a plane lands on a carrier's
  deck and is carried by it; a tank pushes a car).
- Any part anywhere: the fixed attachment rules (wheels only underneath, rotors only on top) become
  physics (a wheel works where it touches the ground, a rotor lifts along its shaft).
- Insides: background walls on vehicles, doors, ladders, stairs, furniture, chests and machines
  working inside a moving vehicle; several seats.
- Vehicle blocks of other sizes and weights; drawing a big vehicle from one cached picture.

### Phase 3: flight and water
- Wind with gusts on everything exposed; wings at any angle and size, flaps, air brakes,
  stabilisers, intakes (in a side view there is no roll or yaw, so ailerons and rudders become
  pitch and drag surfaces: said plainly in the game).
- Flowing water: levels per cell, flows down and sideways, fills containers, pours through
  openings; sleeping cells so oceans cost nothing.
- Liquids as data: density, thickness, flow speed, heat, what it does to who is in it, how two
  liquids react. Water and lava become two of them. The Mod Creator's liquid editor.
- Floating from enclosed volume, flooding, ballast tanks: ships and submarines.

### Phase 4: big vehicles and rails
- Rails that carry: rail wheels held to the track, slopes, switches; the ore cart ridden and
  loaded; trains of coupled cars you can walk through.
- Passenger aircraft, carriers, ships: tests at hundreds of cells, sleeping, the cost per frame.

### Phase 5: mechanical systems
- Sections joined by hinges, pivots, pistons and telescopes, driven by servos with range, speed and
  strength; each section is a frame and collides.
- Mechs: free building, an optional mode to name head, torso, arms, legs and joints, a walk worked
  out from them, every number adjustable; on-screen buttons the player adds and assigns.

### Phase 6: automation and attachments
- Autopilot for every kind of vehicle, working far from the player; remote controls paired to a
  vehicle; vehicles on Sparkworks (sensors, switches) and in the Logic Studio.
- Weapons as parts on anything; custom mounted weapons and projectiles from the Mod Creator.

### Phase 7: structures and settings
- Reach from 5 blocks (weakest) to 40 (strongest); steel beams, columns, reinforced blocks.
- Creatures against buildings by their weight.
- The physics settings page: weather strength, how easily things break, structural strength,
  fluid quality, limits on moving objects.

### Phase 8: the Mod Creator
- Editors for every new kind of thing, showing only the numbers that kind has. (Each earlier phase
  already stores its data in mods; this phase is the screens and what is left.)

### Why the order changed
- **Riding comes first, not vehicle parts.** Everything large (airliners, carriers, trains, mechs)
  needs people standing inside something that moves. It is the piece the rest stands on.
- **The cruise autopilot fix moves from phase 6 to phase 1**, because walking about a flying
  aircraft cannot be tried without it. Far-away autopilot stays in phase 6.
- **Rails move to phase 4** with big vehicles (as the user had it) but after vehicle-to-vehicle
  contact in phase 2, which couplers and carriers both need.

## Limits to keep honest about
- The world is a side view. Roll, yaw and banking do not exist; a "turn" mirrors the vehicle.
- A vehicle is rigid until phase 5; it cannot bend, only break.
- Riders are held to their vehicle's frame while in the air inside it (a jump in an accelerating
  aircraft lands where it started). This is deliberate: the user asked that nobody slides off
  because a vehicle moves.
- The iPad builds in debug mode. Hundreds of cells are fine; thousands need the cached drawing and
  sleeping of phases 2 and 4.

## Risks
- **Build memory on the iPad**: six parts at 360 to 400 MB each, with about 480 known to work.
  New code is spread so no part grows alone; `tools/buildcost.sh` after every phase.
- **Old saves**: new fields are optional; vehicles saved before keep working.
- **World generation**: untouched. Flowing water starts from the same still water.
- **Tuned behaviour**: the car, boat and aircraft kits are pinned by the `veh`, `boat` and `aero`
  suites; they must still pass, with changed numbers explained.
