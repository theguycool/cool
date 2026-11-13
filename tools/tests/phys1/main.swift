import SwiftUI
import Foundation
// Phase 1 of the physics overhaul, core physics: bodies in a vehicle's frame (standing, walking and
// jumping on and inside vehicles while they move, climb and turn; creatures and dropped items riding;
// walls and undersides that block; being pushed; leaving the seat at speed), no speed clamps and what
// sets top speed instead, sub-steps at high speed (nothing passes through a wall at 500 blocks a
// second), materials (friction, bounce), mass in collisions, and builds nobody planned for.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f3(_ v: Double) -> String { return String(format: "%.3f", v) }
let dt60: Double = 1.0 / 60.0

/// A long flat stone runway at row 100 (air above), nothing spawning, daytime, calm air
func runway(mode: GameMode = .creative, length: Int = 760) -> (Game, Int) {
    let g = Game(mode: mode, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false; g.pauseSpawning = true; g.settings.weatherOn = false; g.mobs.removeAll()
    g.godMode = true
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x) + length / 2 - 40, radius: length / 32 + 4)
    for x in x0...(x0 + length) {
        for y in 0..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.timeOfDay = 0.25
    return (g, x0)
}
func kit(_ g: Game, _ k: Gadget, _ left: Int, _ bottom: Int) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for p in kitLayout(k) { v.parts[PartCell(dx: p.dx, dy: p.dy)] = p.p }
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(left), bottom: Double(bottom))
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
/// A vehicle made of blocks and parts: (dx, dy, part, block)
func build(_ g: Game, _ cells: [(Int, Int, PartType, Tile?)], left: Double, bottom: Double) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for c in cells {
        let pc = PartCell(dx: c.0, dy: c.1)
        v.parts[pc] = c.2
        if let t = c.3 { v.blocks[pc] = t }
    }
    v.recompute(keepAnchor: false)
    v.placeBox(left: left, bottom: bottom)
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
func plank(_ x: Int, _ y: Int) -> (Int, Int, PartType, Tile?) { return (x, y, .block, .planks) }
/// A flat deck of planks, w wide
func deck(_ g: Game, _ w: Int, left: Double, bottom: Double) -> Vehicle {
    return build(g, (0..<w).map { plank($0, 0) }, left: left, bottom: bottom)
}
/// A hollow room of planks: w x h outside, the inside open
func room(_ g: Game, _ w: Int, _ h: Int, left: Double, bottom: Double) -> Vehicle {
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<w {
        for y in 0..<h where x == 0 || x == w - 1 || y == 0 || y == h - 1 { cells.append(plank(x, y)) }
    }
    return build(g, cells, left: left, bottom: bottom)
}
/// One frame of a vehicle moved by hand, the way the game moves one: the vehicle, then everybody aboard it
func shift(_ g: Game, _ v: Vehicle, vx: Double, vy: Double = 0, spin: Double = 0) {
    v.vx = vx; v.vy = vy; v.angVel = spin
    v.px += vx * dt60; v.py += vy * dt60; v.angle += spin * dt60
    v.asleep = false
    v.updateBox()
    g.syncRiders()
}
/// Moves a vehicle by hand (the game's own vehicle physics paused) for `secs`: the frames' own test
func carry(_ g: Game, _ v: Vehicle, _ secs: Double, vx: Double, vy: Double = 0, spin: Double = 0, stick: Double = 0, jumpAt: Double = -1) {
    g.pauseVehicles = true
    var t = 0.0
    while t < secs {
        shift(g, v, vx: vx, vy: vy, spin: spin)
        g.stick = stick
        g.jumpHeld = jumpAt >= 0 && t >= jumpAt && t < jumpAt + 0.1
        g.tick(dt60); g.hunger = 20
        t += dt60
    }
    g.stick = 0; g.jumpHeld = false
}
func settle(_ g: Game, _ secs: Double) {
    var t = 0.0
    while t < secs { g.tick(dt60); g.hunger = 20; t += dt60 }
}
/// The player put down just above a place in the world, falling onto whatever is there
func drop(_ g: Game, _ x: Double, _ y: Double) {
    g.inVehicle = nil
    g.pb.ride = 0
    g.pb.x = x; g.pb.y = y; g.pb.vx = 0; g.pb.vy = 0
    g.camX = x; g.camY = y
}

// ---------------------------------------------------------------- A. standing on something that moves
print("== standing on a moving vehicle")
do {
    let (g, x0) = runway()
    g.godMode = false
    let v = deck(g, 9, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    drop(g, Double(x0) + 24.5, 88.5)
    settle(g, 0.6)
    check(g.pb.ride == v.id && g.pb.onGround && abs(g.pb.y - 89.0) < 0.001, "the player comes down onto a deck of planks hanging in the air and is aboard (feet at \(f3(g.pb.y)))")
    let lx0 = g.pb.rlx
    let hp0 = g.hp
    let wx0 = g.pb.x
    carry(g, v, 3.0, vx: 20)
    check(abs(g.pb.rlx - lx0) < 1e-6 && g.pb.x > wx0 + 59.9 && abs(g.pb.x - (v.b.left + 4.5)) < 1e-6 && g.pb.onGround, "carried \(f1(g.pb.x - wx0)) blocks at 20 a second without moving on the deck (drift \(g.pb.rlx - lx0))")
    carry(g, v, 3.0, vx: 0, vy: -10)
    carry(g, v, 1.0, vx: 0, vy: 25)
    check(g.pb.ride == v.id && g.pb.onGround && abs(g.pb.y - (v.b.y - 1.0)) < 0.01 && g.hp == hp0, "up at 10 and down at 25 a second: still standing on it, unhurt (health \(Int(g.hp)))")
    carry(g, v, 1.0, vx: 500)
    check(g.pb.ride == v.id && abs(g.pb.rlx - lx0) < 1e-6 && g.pb.onGround && abs(g.pb.x - (v.b.left + 4.5)) < 1e-6, "at 500 blocks a second: still standing in the same place on the deck")
    // walking and jumping while it moves
    let lxA = g.pb.rlx
    carry(g, v, 0.4, vx: 30, stick: 1)
    check(g.pb.rlx > lxA + 1.5 && g.pb.rlx < lxA + 3.4 && g.pb.ride == v.id, "walking along the deck while it does 30 a second: \(f1(g.pb.rlx - lxA)) blocks along it in 0.4 s")
    settle(g, 0.3)
    let lxB = g.pb.rlx
    let deckTop = v.b.y - 1.0
    var top = 0.0
    var t = 0.0
    while t < 1.2 {
        shift(g, v, vx: 30)
        g.jumpHeld = t < 0.1
        g.tick(dt60); t += dt60
        top = max(top, deckTop - g.pb.y)
    }
    g.jumpHeld = false
    check(top > 2.0 && g.pb.ride == v.id && g.pb.onGround && abs(g.pb.rlx - lxB) < 0.01, "a jump \(f1(top)) blocks high comes down where it left the deck, 36 blocks further on in the world")
    // off the end: back on the land's frame with the speed it was carried at
    var leftAt = -1.0
    t = 0
    while t < 1.5 && leftAt < 0 {
        carry(g, v, dt60 * 0.5, vx: 30, stick: 1)
        t += dt60
        if g.pb.ride == 0 { leftAt = g.pb.vx }
    }
    check(g.pb.ride == 0 && leftAt > 34, "walking off the front edge: no longer aboard, and going \(f1(leftAt)) blocks a second through the air (the deck's 30 and their own walk)")
}

// ---------------------------------------------------------------- B. inside a room that flies
print("== inside a moving room")
do {
    let (g, x0) = runway()
    g.godMode = false
    let v = room(g, 9, 6, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    // the room spans rows 84...89; its floor is the bottom row, so feet stand at 89
    drop(g, Double(x0) + 24.5, 88.0)
    settle(g, 0.5)
    check(g.pb.ride == v.id && g.pb.onGround && abs(g.pb.y - 89.0) < 0.001, "the player stands on the floor inside a hollow room of planks")
    let hp0 = g.hp
    carry(g, v, 2.0, vx: 40, vy: -6)
    carry(g, v, 2.0, vx: -40, vy: 6, stick: 1)
    // walking right inside: stopped by the right wall (inner face at cell 8)
    check(g.pb.ride == v.id && g.pb.rlx > 7.0 && g.pb.rlx < 8.0 - g.pb.w * 0.5 + 0.01 && g.pb.hitWall, "walking across it while it flies: stopped by the far wall, inside (at \(f1(g.pb.rlx)) of 9)")
    // a jump inside meets the ceiling (inner height 4 blocks: the head stops at row 1)
    var top = 9.0
    var t = 0.0
    while t < 1.0 {
        shift(g, v, vx: 40)
        g.jumpHeld = t < 0.3
        g.tick(dt60); t += dt60
        top = min(top, g.pb.rly - g.pb.h)
    }
    g.jumpHeld = false
    check(top >= 0.999 && top < 1.6 && g.pb.ride == v.id && g.hp == hp0, "a jump inside bumps the ceiling and lands back on the floor, unhurt (head got to \(f3(top)))")
    // it tilts: the floor is still the floor
    carry(g, v, 1.0, vx: 20, spin: 0.3)
    carry(g, v, 2.0, vx: 20)
    check(g.pb.ride == v.id && g.pb.onGround && abs(v.angle - 0.3) < 0.02, "tilted 17 degrees and flying on: still standing on its floor")
    carry(g, v, 1.0, vx: 20, spin: -0.3)
    // too steep to stand: the player slides to the low wall
    carry(g, v, 1.0, vx: 0, spin: 1.0)
    carry(g, v, 1.5, vx: 0)
    check(g.pb.ride == v.id && g.pb.rlx > 7.0, "tipped a full radian the player slides down the floor to the low wall (at \(f1(g.pb.rlx)))")
}

// ---------------------------------------------------------------- C. walls, undersides, being pushed
print("== meeting a vehicle from the land")
do {
    let (g, x0) = runway()
    // a solid block of planks 3 wide and 3 high standing on the runway
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<3 { for y in 0..<3 { cells.append(plank(x, y)) } }
    let v = build(g, cells, left: Double(x0 + 30), bottom: 100)
    g.pauseVehicles = true
    drop(g, Double(x0) + 26.0, 100)
    var t = 0.0
    while t < 2.0 { g.stick = 1; g.tick(dt60); t += dt60 }
    g.stick = 0
    check(g.pb.ride == 0 && g.pb.x < Double(x0 + 30) - g.pb.w * 0.5 + 0.06 && g.pb.x > Double(x0 + 30) - 1.0, "walking into the side of a parked block of planks: stopped at its face (at \(f1(g.pb.x - Double(x0 + 30))))")
    // jumping onto it
    t = 0
    while t < 1.2 { g.stick = 1; g.jumpHeld = t < 0.4; g.tick(dt60); t += dt60 }
    g.stick = 0; g.jumpHeld = false
    settle(g, 0.3)
    check(g.pb.ride == 0 || g.pb.ride == v.id, "a jump at it does not pass through")
    // it drives into the player: the player is pushed along ahead of it
    drop(g, Double(x0) + 36.0, 100)
    settle(g, 0.2)
    let px0 = g.pb.x
    carry(g, v, 2.0, vx: 4)
    check(g.pb.x > px0 + 4.0 && g.pb.x >= v.b.right + g.pb.w * 0.5 - 0.1 && g.pb.ride == 0, "the block driven at the player pushes them along ahead of it (\(f1(g.pb.x - px0)) blocks)")
    // under a deck: a jump bumps its underside
    let (g2, x2) = runway()
    let d = deck(g2, 7, left: Double(x2 + 20), bottom: 97.5)
    g2.pauseVehicles = true
    drop(g2, Double(x2) + 23.5, 100)
    settle(g2, 0.2)
    var hi = 100.0
    t = 0
    while t < 1.0 { g2.jumpHeld = t < 0.3; g2.tick(dt60); t += dt60; hi = min(hi, g2.pb.y - g2.pb.h) }
    g2.jumpHeld = false
    check(hi >= d.b.y - 0.05 && g2.pb.ride == 0, "a jump under a low deck bumps its underside (head reached \(f3(hi)), underside at \(f1(d.b.y)))")
}

// ---------------------------------------------------------------- D. creatures and dropped things ride
print("== creatures and dropped items aboard")
do {
    let (g, x0) = runway()
    let v = deck(g, 9, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    g.pauseMobs = false
    let pig = g.addMob(.pig, Double(x0) + 23.0, 88.5)
    pig.persistent = true
    g.spawnDrop(Stack(item: .mat(.coal), count: 3), Double(x0) + 26.0, 88.5, 0, 0)
    drop(g, Double(x0) + 60.0, 100)
    settle(g, 1.0)
    check(pig.b.ride == v.id && g.drops.count == 1 && g.drops[0].ride == v.id, "a pig and a dropped stack come down onto the deck and are aboard")
    let dropL = g.drops.first?.rlx ?? -1
    carry(g, v, 2.0, vx: 25, vy: -3)
    check(pig.b.ride == v.id && abs(pig.b.y - (v.b.y - 1.0)) < 0.01 && pig.b.rlx > 0 && pig.b.rlx < 9, "the pig is carried up and along with the deck (it has wandered to \(f1(pig.b.rlx)) of 9)")
    check(g.drops.count == 1 && g.drops[0].ride == v.id && abs((g.drops.first?.rlx ?? 0) - dropL) < 0.01 && abs(g.drops[0].y - (v.b.y - 1.0)) < 0.01, "the dropped stack lies where it fell on the deck, 50 blocks further on")
    // turned to face the other way: everybody aboard is turned with it
    let before = pig.b.rlx
    let dBefore = g.drops[0].rlx
    _ = g.mirrorVehicle(v, check: false)
    g.syncRiders()
    check(abs(pig.b.rlx - (9.0 - before)) < 1e-6 && abs(g.drops[0].rlx - (9.0 - dBefore)) < 1e-6 && pig.b.ride == v.id, "TURN mirrors the vehicle and those aboard with it")
}

// ---------------------------------------------------------------- E. no speed clamps; what sets speed
print("== speed: no clamps, and what sets it")
/// Drives with the stick held for `secs`; returns the top speed along the ground
@discardableResult
func drive(_ g: Game, _ v: Vehicle, _ secs: Double, _ sx: Double, up: Double = 0) -> Double {
    g.pauseVehicles = false
    g.inVehicle = v; v.rider = true
    var t = 0.0
    var top = 0.0
    while t < secs {
        g.stick = sx; g.stickY = -up
        g.tick(dt60); g.hunger = 20; t += dt60
        top = max(top, abs(v.vx))
    }
    g.stick = 0; g.stickY = 0
    return top
}
/// A car: frames in a row with a wheel under each end, a seat and a steering wheel on top, and engines
func car(_ g: Game, engines: Int, left: Int, extra: [(Int, Int, PartType, Tile?)] = []) -> Vehicle {
    let n = max(4, engines + 2)
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<n { cells.append((x, 0, .frame, nil)) }
    cells.append((0, 1, .wheel, nil)); cells.append((n - 1, 1, .wheel, nil))
    cells.append((0, -1, .seat, nil)); cells.append((1, -1, .steering, nil))
    for e in 0..<engines { cells.append((2 + e, -1, .engine, nil)) }
    cells.append(contentsOf: extra)
    return build(g, cells, left: Double(left), bottom: 100)
}
do {
    var tops: [Double] = []
    var masses: [Double] = []
    for e in [1, 2, 4, 8] {
        let (g, x0) = runway()
        let v = car(g, engines: e, left: x0 + 20)
        tops.append(drive(g, v, 12.0, 1))
        masses.append(v.mass)
    }
    check(tops[0] > 7.5 && tops[0] < 11.5, "a one-engine car tops out about where it always did (\(f1(tops[0])) blocks a second)")
    check(tops[1] > tops[0] + 1.5 && tops[2] > tops[1] + 1.5 && tops[3] > tops[2] + 1.5 && tops[3] > 17.5, "more engines are faster with no ceiling: 1, 2, 4, 8 engines reach \(tops.map { f1($0) }.joined(separator: ", ")) (the old ceiling was 17)")
    // the same two engines carrying a load of stone are slower
    let (g, x0) = runway()
    let light = car(g, engines: 2, left: x0 + 20)
    let a = drive(g, light, 12.0, 1)
    let (g2, x2) = runway()
    var load: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<4 { load.append((x, -2, .block, .stone)); load.append((x, -3, .block, .stone)) }
    let heavy = car(g2, engines: 2, left: x2 + 20, extra: load)
    let b = drive(g2, heavy, 12.0, 1)
    check(heavy.mass > light.mass * 2.5 && b < a - 1.0 && b > 3.0, "the same car under eight blocks of stone is slower: \(f1(a)) against \(f1(b)) (mass \(f1(light.mass)) against \(f1(heavy.mass)))")
}
do {
    // a jet sled: past anything the old clamp of 30 allowed
    let (g, x0) = runway()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<5 { cells.append((x, 0, .frame, nil)) }
    cells.append((0, 1, .wheel, nil)); cells.append((4, 1, .wheel, nil))
    cells.append((4, -1, .cockpit, nil))
    for y in 0..<3 { cells.append((-1, -y, .jet, nil)) }
    cells.append((0, -1, .frame, nil)); cells.append((0, -2, .frame, nil)); cells.append((1, -1, .fuelTank, nil))
    let v = build(g, cells, left: Double(x0 + 20), bottom: 100)
    var top = 0.0
    g.inVehicle = v; v.rider = true
    var t = 0.0
    while t < 6.0 && v.px < Double(x0 + 700) {
        g.stick = 1
        g.tick(dt60); g.hunger = 20; t += dt60
        top = max(top, v.speed)
    }
    g.stick = 0
    check(top > 38 && v.parts.count >= 10, "a sled with three jets passes the old limit of 30 on the runway: \(f1(top)) blocks a second after \(f1(t)) s, in one piece")
}
do {
    // 500 blocks a second at a stone wall: it does not pass, whole or in pieces
    for thick in [1, 3] {
        let (g, x0) = runway()
        let wallX = x0 + 90
        for x in wallX..<(wallX + thick) { for y in 80..<100 { g.world.set(x, y, .stone) } }
        var cells: [(Int, Int, PartType, Tile?)] = []
        for x in 0..<3 { for y in 0..<2 { cells.append((x, y, .block, .stone)) } }
        let v = build(g, cells, left: Double(x0 + 60), bottom: 95)
        g.settings.vehicleDamage = false
        v.vx = 500
        drop(g, Double(x0) + 60, 100)
        var t = 0.0
        var past = false
        var hitAt = 0.0
        while t < 1.5 {
            let before = v.vx
            g.tick(dt60); t += dt60
            if hitAt == 0 && v.vx < before * 0.5 { hitAt = before }
            for o in g.vehicles where o.b.right > Double(wallX) + 0.6 { past = true }
        }
        check(!past && hitAt > 250 && v.b.right <= Double(wallX) + 0.3, "six blocks of stone flung at 500 a second meet a wall \(thick) block\(thick > 1 ? "s" : "") thick at \(Int(hitAt)) a second and do not pass it (they end \(f1(Double(wallX) - v.b.right)) from it)")
    }
    // dropped from far up in the sky: it reaches the speed the air allows and stops on the ground
    let (g, x0) = runway()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<3 { for y in 0..<3 { cells.append((x, y, .block, .stone)) } }
    let v = build(g, cells, left: Double(x0 + 60), bottom: -900)
    g.settings.vehicleDamage = false
    drop(g, Double(x0) + 61.5, 100)
    g.pb.x = Double(x0) + 80
    var t = 0.0
    var fastest = 0.0
    while t < 30.0 && !(v.contacts > 0 && v.speed < 0.5 && t > 3) {
        g.tick(dt60); t += dt60
        fastest = max(fastest, v.vy)
    }
    check(fastest > 45 && fastest < 200 && abs(v.b.y - 100.0) < 0.3, "nine blocks of stone dropped from 1,000 up fall at \(f1(fastest)) blocks a second (the air's drag, not a clamp) and stop on the runway (bottom at \(f1(v.b.y)))")
}

// ---------------------------------------------------------------- F. weight
print("== weight")
/// A sea: water from row 100 to 107 over stone
func sea() -> (Game, Int) {
    let (g, x0) = runway()
    for x in x0...(x0 + 300) {
        for y in 100..<108 { g.world.set(x, y, .water) }
        for y in 108..<112 { g.world.set(x, y, .stone) }
    }
    return (g, x0)
}
func raft(_ g: Game, _ x0: Int) -> Vehicle {
    return build(g, (0..<12).map { ($0, 0, .block, .logBlock) }, left: Double(x0 + 40), bottom: 100.6)
}
do {
    var draught: [Double] = []
    for kind in [MobKind.chicken, .pig, .elephant] {
        let (g, x0) = sea()
        let v = raft(g, x0)
        drop(g, Double(x0) + 20, 100)
        settle(g, 4.0)
        let y0 = v.py
        let m = g.addMob(kind, Double(x0) + 46.0, v.b.top - 0.2)
        m.persistent = true
        var t = 0.0
        while t < 6.0 {
            g.tick(dt60); t += dt60
            // (kept from wandering off, so only its weight is tested)
            if m.b.ride == v.id { m.b.rlx = 6.0; m.b.vx = 0 }
        }
        draught.append(v.py - y0)
        if kind == .elephant {
            check(mobMass(m) > 5.0 && v.b.top > 100.3, "an elephant (mass \(f1(mobMass(m)))) is more than a raft of twelve logs can carry: it goes under (deck \(f1(v.b.top - 100.0)) below the surface)")
        } else if kind == .pig {
            check(m.b.ride == v.id && v.b.top < 100.0, "a pig rides the raft and it stays afloat (deck \(f3(100.0 - v.b.top)) above the surface)")
        }
    }
    check(draught[0] < draught[1] && draught[1] < draught[2] && draught[1] - draught[0] > 0.002, "the raft sits deeper the heavier its passenger: chicken \(f3(draught[0])), pig \(f3(draught[1])), elephant \(f3(draught[2]))")
}
do {
    // pushing: the player shoves a plank crate along, and cannot shift a block of stone
    let (g, x0) = runway()
    let light = build(g, [plank(0, 0)], left: Double(x0 + 30), bottom: 100)
    drop(g, Double(x0) + 27.0, 100)
    settle(g, 0.3)
    g.pauseVehicles = false
    var t = 0.0
    while t < 2.0 { g.stick = 1; g.tick(dt60); t += dt60 }
    g.stick = 0
    let movedLight = light.px - (Double(x0) + 30.5)
    let (g2, x2) = runway()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<3 { for y in 0..<3 { cells.append((x, y, .block, .stone)) } }
    let heavy = build(g2, cells, left: Double(x2 + 30), bottom: 100)
    let hx0 = heavy.px
    drop(g2, Double(x2) + 27.0, 100)
    settle(g2, 0.3)
    t = 0
    while t < 2.0 { g2.stick = 1; g2.tick(dt60); t += dt60 }
    g2.stick = 0
    check(movedLight > 2.0 && abs(heavy.px - hx0) < 0.3 && g2.pb.x < heavy.b.left, "the player pushes a plank crate \(f1(movedLight)) blocks in two seconds and cannot shift nine blocks of stone (\(f3(heavy.px - hx0)))")
}

// ---------------------------------------------------------------- G. getting up at speed; the autopilot carries on
print("== leaving the seat at speed")
do {
    let (g, x0) = runway()
    // a flat truck: a deck of frames with the seat and wheel standing on it, an engine, an autopilot
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<8 { cells.append((x, 0, .frame, nil)) }
    cells.append((0, 1, .wheel, nil)); cells.append((7, 1, .wheel, nil)); cells.append((4, 1, .wheel, nil))
    cells.append((6, -1, .seat, nil)); cells.append((7, -1, .steering, nil))
    cells.append((0, -1, .engine, nil)); cells.append((1, -1, .autopilot, nil)); cells.append((2, -1, .fuelTank, nil))
    let v = build(g, cells, left: Double(x0 + 20), bottom: 100)
    let top = drive(g, v, 5.0, 1)
    g.cycleAutopilot()
    check(v.auto == 1 && top > 6, "a truck with an autopilot at speed (\(f1(top)) blocks a second), cruise switched on")
    drive(g, v, 0.5, 0)
    let vAt = v.vx
    // jump: stand up from the seat
    g.jumpHeld = true; g.tick(dt60); g.jumpHeld = false
    check(g.inVehicle == nil && g.pb.ride == v.id && !v.rider, "jump at speed: the driver stands up on the deck instead of being thrown off")
    let lx = g.pb.rlx
    settle(g, 3.0)
    check(g.pb.ride == v.id && abs(g.pb.rlx - lx) < 0.05 && v.vx > vAt * 0.8, "three seconds on, the truck still cruises (\(f1(v.vx)) of \(f1(vAt))) with the driver standing where they got up")
    // a walk to the back of the deck and back to the seat
    var t = 0.0
    while t < 0.6 { g.stick = -1; g.tick(dt60); t += dt60 }
    g.stick = 0
    check(g.pb.ride == v.id && g.pb.rlx < lx - 2.0 && v.vx > vAt * 0.8, "walking back along the moving deck (\(f1(lx - g.pb.rlx)) blocks)")
    // with no floor under the seat nobody is dropped out of a moving vehicle
    let (g2, x2) = runway()
    let c2 = kit(g2, .carKit, x2 + 20, 100)
    drive(g2, c2, 3.0, 1)
    let seat = g2.seatCell(c2)
    let noFloor = seat.map { c2.walkAt($0.dx, $0.dy + 1) == cellOpen } ?? false
    g2.jumpHeld = true; g2.tick(dt60); g2.jumpHeld = false
    check(!noFloor || g2.inVehicle === c2, "a seat with nothing under it keeps its driver in at speed (the car kit: \(noFloor ? "no floor under the seat" : "has a floor"))")
}

// ---------------------------------------------------------------- H. saved and loaded aboard
print("== saved aboard")
do {
    let (g, x0) = runway(mode: .survival)
    let v = room(g, 9, 6, left: Double(x0 + 20), bottom: 100)
    drop(g, Double(x0) + 24.5, 98.0)
    settle(g, 1.0)
    check(g.pb.ride == v.id, "the player stands in a room that rests on the runway")
    let lx = g.pb.rlx
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    g2.monstersEnabled = false; g2.pauseSpawning = true
    settle(g2, 0.5)
    let v2 = g2.vehicles.first
    check(g2.vehicles.count == 1 && g2.pb.ride == (v2?.id ?? -1) && abs(g2.pb.rlx - lx) < 0.01 && g2.pb.onGround, "loaded again: one room, the player aboard it in the same place (at \(f1(g2.pb.rlx)) of 9)")
}

// ---------------------------------------------------------------- I. the land in the way of a rider
print("== scraped off by the land")
do {
    let (g, x0) = runway()
    let v = deck(g, 9, left: Double(x0 + 20), bottom: 96)
    g.pauseVehicles = true
    // a stone beam the deck passes under: its underside one block above the deck
    for x in (x0 + 50)..<(x0 + 53) { for y in 90..<94 { g.world.set(x, y, .stone) } }
    drop(g, Double(x0) + 24.5, 94.5)
    settle(g, 0.5)
    check(g.pb.ride == v.id, "the player rides a deck that will pass under a low beam")
    carry(g, v, 4.0, vx: 10)
    check(g.pb.x < Double(x0 + 50) && g.pb.ride == 0 && v.b.left > Double(x0 + 53), "the beam stops the rider and the deck goes on without them (rider at \(f1(g.pb.x - Double(x0 + 50))) from the beam, deck \(f1(v.b.left - Double(x0 + 53))) past it)")
}

// ---------------------------------------------------------------- J. builds nobody planned for
print("== odd builds")
do {
    // three wheels, a sofa, a jet at the back and a wing on top
    let (g, x0) = runway()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<5 { cells.append((x, 0, .block, .planks)) }
    cells.append((0, 1, .wheel, nil)); cells.append((2, 1, .wheel, nil)); cells.append((4, 1, .wheel, nil))
    cells.append((2, -1, .block, .sofa)); cells.append((3, -1, .cockpit, nil)); cells.append((1, -1, .wing, nil))
    cells.append((-1, 0, .jet, nil)); cells.append((0, -1, .fuelTank, nil))
    let v = build(g, cells, left: Double(x0 + 20), bottom: 100)
    g.settings.vehicleDamage = false
    g.inVehicle = v; v.rider = true
    var t = 0.0
    var top = 0.0
    var ok = true
    while t < 5.0 && v.px < Double(x0 + 650) {
        g.stick = 1
        g.tick(dt60); g.hunger = 20; t += dt60
        top = max(top, v.speed)
        if !(v.px.isFinite && v.py.isFinite && v.angle.isFinite) { ok = false }
    }
    g.stick = 0
    check(ok && top > 12 && v.parts.count == cells.count, "three wheels, a sofa, a wing and a jet: it goes (\(f1(top)) blocks a second), nothing falls off, the numbers stay numbers")
    // a room with a balloon over it and a burner: the player walks about inside while it rises
    let (g2, x2) = runway()
    var rc: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<7 { for y in 0..<5 where (x == 0 || x == 6 || y == 0 || y == 4) && !(y == 0 && x >= 2 && x <= 4) { rc.append(plank(x, y)) } }
    for x in 0..<7 { for y in (-4)..<0 { rc.append((x, y, .envelope, nil)) } }
    // three burners in the ceiling under the balloon; the cockpit, a tank and the autopilot on the floor
    for x in 2...4 { rc.append((x, 0, .burner, nil)) }
    rc.append((1, 3, .cockpit, nil)); rc.append((5, 3, .fuelTank, nil)); rc.append((5, 2, .autopilot, nil))
    let b = build(g2, rc, left: Double(x2 + 20), bottom: 100)
    g2.inVehicle = b; b.rider = true
    g2.pauseVehicles = false
    t = 0
    while t < 14.0 { g2.stick = 0; g2.stickY = -1; g2.tick(dt60); g2.hunger = 20; t += dt60 }
    g2.stickY = 0
    let rose = 100.0 - b.b.y
    g2.cycleAutopilot()
    g2.jumpHeld = true; g2.tick(dt60); g2.jumpHeld = false
    let stood = g2.pb.ride == b.id
    t = 0
    while t < 1.0 { g2.stick = 1; g2.tick(dt60); t += dt60 }
    g2.stick = 0
    settle(g2, 3.0)
    check(rose > 3 && stood, "a room under a balloon lifts off (\(f1(rose)) blocks up) and the pilot gets up from the cockpit inside it")
    check(g2.pb.ride == b.id && g2.pb.onGround && 100.0 - b.b.y > 20 && b.contacts == 0, "the pilot walks about inside while the autopilot keeps it in the air (now \(f1(100.0 - b.b.y)) up, the pilot at \(f1(g2.pb.rlx)) of 7)")
}

// ---------------------------------------------------------------- K. what things are made of
print("== materials")
do {
    var slid: [Double] = []
    for ground in [Tile.stone, .ice] {
        let (g, x0) = runway()
        for x in (x0 + 60)...(x0 + 400) { g.world.set(x, 100, ground) }
        let v = kit(g, .carKit, x0 + 20, 100)
        drive(g, v, 5.0, 1)
        // let go: the brakes come on
        let from = v.px
        g.inVehicle = v; v.rider = true
        var t = 0.0
        while t < 12.0 && abs(v.vx) > 0.2 { g.stick = 0; g.tick(dt60); t += dt60 }
        slid.append(v.px - from)
    }
    check(slid[1] > slid[0] * 2.5, "braking on ice takes far longer than on stone: \(f1(slid[0])) blocks against \(f1(slid[1]))")
    check(blockPhys(.ice).grip < 0.2 && blockPhys(.stone).grip == 1.0 && blockPhys(.hay).bounce > 0.2 && mobMass(.elephant) > mobMass(.pig) * 8 && mobMass(.golem) > mobMass(.zombie) * 2, "materials have grip and bounce, creatures have mass by size and build (elephant \(f1(mobMass(.elephant))), pig \(f1(mobMass(.pig))), golem \(f1(mobMass(.golem))), zombie \(f1(mobMass(.zombie))))")
}

// ---------------------------------------------------------------- L. a mod's own materials
print("== materials in mods")
do {
    ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prphys1-" + String(Int.random(in: 1000...999999)), isDirectory: true)
    var p = ModPack(); p.id = "mt"; p.name = "Materials"
    func block(_ id: String, _ f: (inout ModBlock) -> Void) -> ModBlock {
        var b = ModBlock(); b.id = id; b.name = id.capitalized
        var px = ModPixels(w: 8, h: 8)
        for y in 0..<8 { for x in 0..<8 { px.setARGB(x, y, 0xFF8A6A4A) } }
        b.art = px
        f(&b)
        return b
    }
    p.blocks = [block("grease") { $0.grip = 0.05; $0.hardness = 1 }, block("rubber") { $0.grip = 1.6; $0.bounce = 0.8; $0.hardness = 1 }, block("plain") { $0.hardness = 1 }]
    var wild = p
    wild.blocks[0].grip = -5
    wild.blocks[1].bounce = 99
    _ = ModValidator.check(&wild, known: [:])
    check(wild.blocks[0].grip == 0.02 && wild.blocks[1].bounce == 0.9, "a mod block's grip and bounce are held to their ranges")
    let back: ModPack? = (try? JSONEncoder().encode(p)).flatMap { try? JSONDecoder().decode(ModPack.self, from: $0) }
    check(back?.blocks[0].grip == 0.05 && back?.blocks[1].bounce == 0.8, "they are saved in the mod and read back")
    let older: ModBlock? = try? JSONDecoder().decode(ModBlock.self, from: Data("{\"id\": \"old\", \"name\": \"Old\"}".utf8))
    check(older?.grip == 1.0 && older?.bounce == 0.0, "a block from a mod made before them grips like stone and does not bounce")
    ModRuntime.activate([p], world: nil)
    let rt: ModRuntime = ModRuntime.shared
    if let grease = rt.tileForKey["mt:grease"], let rubber = rt.tileForKey["mt:rubber"], let plain = rt.tileForKey["mt:plain"] {
        check(blockPhys(grease).grip == 0.05 && blockPhys(rubber).bounce == 0.8 && blockPhys(plain).grip == 1.0, "the world uses them")
        // nine blocks of stone dropped on rubber bounce far higher than on the mod's plain block
        var rebound: [Double] = []
        for ground in [plain, rubber] {
            let (g, x0) = runway()
            for x in (x0 + 50)...(x0 + 70) { g.world.set(x, 100, ground) }
            var cells: [(Int, Int, PartType, Tile?)] = []
            for x in 0..<3 { for y in 0..<3 { cells.append((x, y, .block, .stone)) } }
            let v = build(g, cells, left: Double(x0 + 58), bottom: 80)
            g.settings.vehicleDamage = false
            drop(g, Double(x0) + 90, 100)
            var t = 0.0
            var up = 0.0
            while t < 4.0 { g.tick(dt60); t += dt60; up = max(up, -v.vy) }
            rebound.append(up)
        }
        check(rebound[1] > rebound[0] * 3 && rebound[1] > 8, "stone dropped 20 blocks onto the mod's rubber comes back up at \(f1(rebound[1])) blocks a second, off its plain block at \(f1(rebound[0]))")
    } else {
        check(false, "the mod's blocks are in the world")
    }
    ModRuntime.activate([], world: nil)
}

// ---------------------------------------------------------------- M. moved by something else while aboard
print("== taken off a vehicle by something else")
do {
    let (g, x0) = runway()
    let v = deck(g, 9, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    drop(g, Double(x0) + 24.5, 88.5)
    settle(g, 0.6)
    check(g.pb.ride == v.id, "the player is aboard a deck")
    // a knock that shifts them a little keeps them aboard, where they now are
    g.pb.x += 0.3
    g.tick(dt60)
    carry(g, v, 0.5, vx: 10)
    check(g.pb.ride == v.id && abs(g.pb.rlx - 4.8) < 0.01, "a small shove along the deck is kept (now at \(f1(g.pb.rlx)) of 9)")
    // a jump to another place (a respawn, a doorway) takes them off it
    g.world.loadAround(centerX: x0 + 200, radius: 3)
    g.pb.x = Double(x0) + 200; g.pb.y = 100
    g.camX = g.pb.x; g.camY = 98
    g.tick(dt60)
    carry(g, v, 0.5, vx: 10)
    check(g.pb.ride == 0 && abs(g.pb.x - (Double(x0) + 200)) < 0.5 && abs(g.pb.y - 100) < 0.01, "moved somewhere else entirely, the player is no longer aboard and stays where they were put")
}

// ---------------------------------------------------------------- N. shots from something moving
print("== shots from a moving deck")
do {
    let (g, x0) = runway()
    let v = deck(g, 9, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    drop(g, Double(x0) + 24.5, 88.5)
    settle(g, 0.6)
    carry(g, v, 0.5, vx: 25)
    g.aimX = g.pb.x + 10; g.aimY = g.pb.y - 1.2
    g.facing = 1
    let still = runway()
    let gs = still.0
    gs.pb.x = Double(still.1) + 30; gs.pb.y = 100; gs.pb.vx = 0; gs.pb.vy = 0
    gs.aimX = gs.pb.x + 10; gs.aimY = gs.pb.y - 1.2
    gs.facing = 1
    let moving = g.arrowLaunch(1.0)
    let standing = gs.arrowLaunch(1.0)
    check(g.pb.ride == v.id && abs((moving.2 - standing.2) - 25.0) < 0.5 && abs(moving.3 - standing.3) < 0.5, "an arrow loosed from a deck doing 25 a second leaves with the deck's speed added (\(f1(moving.2)) against \(f1(standing.2)) standing on the ground)")
}

print(fails == 0 ? "phys1: \(passes) passed, 0 failed" : "phys1: \(passes) passed, \(fails) FAILED")
exit(fails == 0 ? 0 : 1)
