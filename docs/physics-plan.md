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
  phase 2 (done); vehicles met each other as boxes until phase 2; the player, creatures and loose
  blocks still fall no faster than 26 blocks a second (as before; it becomes air drag with the
  structural work of phase 7, which also gives loose blocks sub-steps).

### Phase 2: vehicle foundations (done)
- Vehicles meet each other cell by cell (`meetVehicleCells`): a vehicle's samples inside another's
  cells become contacts solved with the land's, pushing both by their masses (`VContact.other`).
  All vehicles are stepped together (`stepVehicles`: fixed step k of every vehicle before k + 1 of
  any), each split as finely as how fast it closes on the others. Wheels are round to other
  vehicles. A vehicle rests on another (`restOn`), sleeps while that one does and wakes with it;
  wheels driving on another vehicle push it back; a hard blow wakes one at rest and damages both.
  A turn (TURN) carries vehicles parked on the one turning. Tests: a crate landing on a deck in any
  order, a tank pushing a light and a heavy crate, two crates meeting at 60 a second each, a crate
  riding a truck, a plane landing on a moving deck, sleeping together.
- Any part anywhere: placement only needs a free cell that touches. How it works there is physics:
  a wheel drives wherever it touches (upright as before; on its roof or against a wall along what it
  touches, by its grip: `wheelsAlongContacts`), a rotor lifts by the room its blades have
  (`rotorRoom`), a thruster, gun or drill with no open side waits for one (`boxed`), the steering
  wheel works from any seat. The game says so when a part goes somewhere unusual (`partNote`).
- Several seats: the driver sits in the seat tapped (`seatAt`, saved).
- Insides: doors open as somebody walks into them and close behind them (`vehicleDoorTouch`), ladders
  are climbed in the vehicle's frame (and one reached from the land takes the climber aboard),
  stairs are steps, chairs and sofas are passenger seats (`seatAboard`), beds pass the night (not a
  spawn point: it moves), a station aboard counts as near, back walls go behind cells (AS WALL with ON
  VEHICLE; saved; weigh a fifth of their block; the assembler takes a house's walls along and gives
  them back). A body aboard one vehicle meets another's cells (in its way, or stepped onto).
- A vehicle of 24 cells or more, or with back walls, is drawn from one cached picture of its still
  cells (`VehicleArt`), made again only when it changes.
- Not done (moved to phase 4): parts bigger than one cell. Creature AI still reads the land's tiles.

### Phase 3: flight and water (done)
- Liquids flow (`p12c_fluids`): a cell holds 0...255 of its liquid (a part-full cell keeps its level in
  `Chunk.level`); cells wake when they or a neighbour change (`World.set` → `wakeFlow`), fall first,
  then even out along their row as far as the floor goes (`levelRow`), in whole 255ths so nothing is
  made or lost; a thin layer covers only so many cells (`reach`) and a lone film dries up; a cell with
  nothing to do sleeps, so the world's own seas cost nothing. 20 steps a second, 1,600 cells a step.
  Levels are saved (`ChunkSave.levels`) and wake again when their ground loads. Part-full cells are
  drawn live over the land (`drawLiquids`); the section painter leaves them out. The storm surge's
  water is held still (`flowHold`). Hand-built pools that should stay put: `World.calmLiquids()`.
- Liquids as data (`LiquidDef`): colour, see-through, density, thickness, spread, harm, burning,
  what it hardens into where it meets another liquid, drying, an effect. Water and lava are two of
  them (lava meeting water sets into obsidian, or stone where thin); a mod block with the new Liquid
  collision is one too (the block editor's AS A LIQUID section), floating on a denser liquid or
  sinking under a lighter one. Bodies swim by how full their cells are; vehicles float by the
  liquid's density (lava holds things up three times as hard). The bucket carries a block of any liquid;
  the sump pump pumps a block's worth a stroke.
- Ships: the air in a hull holds it up (`updateHullAir`: liquid reaches only cells under the surface,
  from outside or a flooded neighbour; solid cells keep it out), so an open boat of stone floats on
  the air inside it, a hole below the waterline floods it a few cells a second and it sinks, and a
  sealed hull stays dry however deep. Riders in a dry cabin under water breathe and do not swim.
  Ballast tanks (new part) flood and blow with the stick: a submarine.
- Flight: wings tilt in steps (tap a parked wing; saved), flapped wings drop their flaps when slow,
  air brakes open against the motion or rolling to a stop, tailplanes steady the nose. Wind reaches
  every vehicle (also the box drag of those without wings), rolls in gusts along the land and is
  sheltered by land close upwind or overhead.
- Not done: intakes (nothing in this model needs one), freezing water, rain filling containers.

### Phase 4: big vehicles and rails (done)
- Rail wheels (new part): on rails they roll almost freely (braking only when the driver pulls
  against the motion), off them they drag. Rails are a smooth surface to them: a track built in
  steps is a ramp between the middles of neighbouring columns (`railSurface`), and a rail wheel in
  the air over rails is held down onto them (`railHold`), so carts follow stepped track.
- The ore cart (now craftable) put on a rail is a little vehicle: two crates on two rail wheels,
  pushed, ridden, loaded, or pulled.
- Couplers (new part) that touch link two vehicles (`VLink`, kept by both, saved): each pulls and
  pushes the other at the coupler (`solveCouplings`, between fixed steps), a tap lets go, a hard
  enough pull breaks the link. Trains are walked through from car to car.
- Parts bigger than one cell: the big wheel, three across (`Vehicle.spanOf` maps its cells to its
  middle, where it is counted, weighed, sampled as one ring and drawn round); put on with the cell
  tapped as its middle (the vehicle lifted up to three blocks to make room), taken off whole.
- Big vehicles: collision samples cached per vehicle until it changes; a ship of 424 cells costs
  about 3 ms a frame under way in a debug build here, and sleeps at rest.
- Not done: switches between tracks (in a side view tracks only cross at different heights),
  passenger aircraft and carriers as ready-made kits (they can be built from parts).

### Phase 5: mechanical systems (done)
- Three new parts: the hinge (swings free between its limits), the servo (turns to where it is told,
  as fast and as hard as set) and the piston (pushes out and pulls back in a straight line, up to four
  blocks). What is built beyond one becomes a section of its own (`splitJointSections`, `splitAt`): a
  separate rigid body (a `Vehicle`) that the section it hangs from keeps a `VJoint` to (`parentID` on
  the child). The side that stays is the one joined to the section above, else the one with the seat,
  else the heavier; joints built into the side that goes go with it, so a leg built all at once splits
  into thigh and shin whatever order its cells are looked at in.
- Joints are worked out between the fixed steps with the couplers (`solveJoints`): a few rounds of
  each joint's turn (servo motor up to `Joints.torque` times its strength, hinge limits) then its pivot
  (both sections made to move the same there, and its gap closed); a piston's push along its line,
  then its turn and line held. Where a section stands on the land its footing is worked out again in
  the same rounds (`heldContacts`, `footingPass`), or a servo's turning push slid a resting base along
  the ground. A gap over `Joints.slack` is closed by moving the sections (`closeJointGap`).
- A machine's sections wake, step (the same fixed steps) and rest together; a section counts as held
  up by the one it hangs from, and stillness is judged by how far it really went in a frame. Sections
  of one machine never meet each other (`meetVehicleCells` skips them); everything else they meet.
- What moves a joint is set on it (tap it): nothing, the stick up/down or left/right (an arm sticking
  out sideways goes up with the stick), the buttons A, B and C on the screen (held: to one end, let
  go: back), or a walk. Speed, strength and both limits are sliders on the JOINT panel.
- Mechs: AUTO MECH makes the joints under the body hips and the joints below them knees, legs
  taking turns from one end of the body to the other; the walk (`gaitTarget`) swings hips and bends
  knees as the leg comes forward, fading in and out as the stick is pushed and let go. A walking
  machine's feet carry it toward `Joints.walkSpeed` (the swing is what is seen; the push is shared by
  all its sections, so it does not tip it) and brake it when the stick is let go; while it walks its
  feet slide rather than plant. With a driver, its body is kept upright (`balanceMachine`), so a mech
  can walk on two legs.
- Saved: joints, `parent`, `gait` in `VehicleSave`; vehicle ids are kept across saves.
- Not done: naming head, torso and arms as body parts (roles are on joints: hip, knee, shoulder,
  elbow, neck, tail); the walk's speed and stride are not settable; three fixed buttons, not buttons
  the player adds; a section's own engines and wheels drive only when the driver's seat is in it (a
  trailer section is pulled); a machine cannot TURN round.

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
- A vehicle is rigid; since phase 5 a machine bends at its joints, each section rigid.
- Riders are held to their vehicle's frame while in the air inside it (a jump in an accelerating
  aircraft lands where it started). This is deliberate: the user asked that nobody slides off
  because a vehicle moves.
- The iPad builds in debug mode. Hundreds of cells are fine; thousands need the cached drawing and
  sleeping of phases 2 and 4.

## Risks
- **Build memory on the iPad**: eight parts at 320 to 375 MB each, with about 480 known to work.
  New code is spread so no part grows alone; `tools/buildcost.sh` after every phase.
- **Old saves**: new fields are optional; vehicles saved before keep working.
- **World generation**: untouched. Flowing water starts from the same still water.
- **Tuned behaviour**: the car, boat and aircraft kits are pinned by the `veh`, `boat` and `aero`
  suites; they must still pass, with changed numbers explained.
