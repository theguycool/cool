import SwiftUI
import Foundation
// Phase 4 of the physics overhaul, big vehicles and rails: rail wheels that coast on rails and drag off
// them, the ore cart on a rail, rolling down a slope of rails, a train coupled and uncoupled, walked
// through, saved; the big wheel (three cells across) put on, climbing a step small wheels stop at, taken
// off whole and saved; a ship of four hundred cells and what a frame of it costs.

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

/// The world-space bottom of a vehicle's lowest cells (its box)
func bottomOf(_ v: Vehicle) -> Double { return v.b.y }
/// A crate: a square of planks, n x n
func crate(_ g: Game, _ n: Int, left: Double, bottom: Double, tile: Tile = .planks) -> Vehicle {
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<n { for y in 0..<n { cells.append((x, y, .block, tile)) } }
    return build(g, cells, left: left, bottom: bottom)
}
/// Steps only the vehicles (no player tick), for `secs`
func physOnly(_ g: Game, _ secs: Double, each: (() -> Void)? = nil) {
    var t = 0.0
    while t < secs {
        each?()
        g.updateVehicles(dt60)
        g.syncRiders()
        t += dt60
    }
}
/// Whether two vehicles have any cell centres closer than a block on both axes (overlapping cells)
func overlap(_ a: Vehicle, _ b: Vehicle) -> Double {
    var worst = 0.0
    for (c, _) in a.parts {
        let p = a.cellCenter(c)
        let l = b.toLocal(p.0, p.1)
        let cell = PartCell(dx: Int(floor(l.0)), dy: Int(floor(l.1)))
        if b.parts[cell] != nil {
            let fx = l.0 - floor(l.0); let fy = l.1 - floor(l.1)
            worst = max(worst, 0.5 - max(abs(fx - 0.5), abs(fy - 0.5)) + 0.5)
        }
    }
    return worst
}


/// A row of rails on the runway from x0 to x1 (the rail tiles sit on the ground, row 99)
func rails(_ g: Game, _ x0: Int, _ x1: Int, row: Int = 99) {
    for x in x0...x1 { g.world.set(x, row, .rail) }
}
/// A cart of two crates on two rail wheels (as the ore cart is), with a coupler at each end if asked
func cart(_ g: Game, left: Double, bottom: Double, couplers: Bool = false, engine: Bool = false) -> Vehicle {
    var cells: [(Int, Int, PartType, Tile?)] = [(0, 0, .cargo, nil), (1, 0, .cargo, nil), (0, 1, .railWheel, nil), (1, 1, .railWheel, nil)]
    if engine { cells = [(0, 0, .seat, nil), (1, 0, .engine, nil), (1, -1, .steering, nil), (0, 1, .railWheel, nil), (1, 1, .railWheel, nil)] }
    if couplers { cells.append((-1, 0, .coupler, nil)); cells.append((2, 0, .coupler, nil)) }
    return build(g, cells, left: left, bottom: bottom)
}

// ---------------------------------------------------------------- A. rails
print("== rail wheels")
do {
    let (g, x0) = runway()
    rails(g, x0 + 20, x0 + 400)
    let onRails = cart(g, left: Double(x0 + 30), bottom: 100)
    let offRails = cart(g, left: Double(x0 + 30), bottom: 100)
    // the second one far away, on bare stone
    offRails.px += 420; offRails.updateBox()
    physOnly(g, 0.5)
    onRails.vx = 8; offRails.vx = 8
    onRails.asleep = false; offRails.asleep = false
    let a0 = onRails.px, b0 = offRails.px
    physOnly(g, 3.0)
    check(onRails.px - a0 > 18 && offRails.px - b0 < 6, "pushed at 8 a second, a cart on rails coasts on (\(f1(onRails.px - a0)) blocks), one on bare stone drags to a stop (\(f1(offRails.px - b0)))")
}

print("== the ore cart")
do {
    let (g, x0) = runway()
    g.mode = .survival
    rails(g, x0 + 20, x0 + 60)
    // a slope of rails down from x0 + 61: a block lower every three columns
    for k in 0..<6 {
        for j in 0..<3 {
            let x = x0 + 61 + k * 3 + j
            for y in 99...(100 + k) { g.world.set(x, y, .air) }
            g.world.set(x, 100 + k, .rail)
            g.world.set(x, 101 + k, .stone)
        }
    }
    for x in (x0 + 79)...(x0 + 130) { g.world.set(x, 106, .rail); for y in 99...105 { g.world.set(x, y, .air) }; g.world.set(x, 107, .stone) }
    g.inv.add(.block(.oreCart), 1)
    g.sel = g.inv.slots.firstIndex(where: { $0?.item == .block(.oreCart) }) ?? 0
    g.pb.x = Double(x0 + 32); g.pb.y = 99
    g.aimX = Double(x0) + 34.5; g.aimY = 99.5
    let n0 = g.vehicles.count
    g.pb.x = Double(x0 + 52)
    g.aimX = Double(x0) + 54.5
    _ = g.placeOreCart(x0 + 54, 99)
    let c = g.vehicles.last!
    check(g.vehicles.count == n0 + 1 && c.parts.count == 4 && c.wheels == 2 && g.inv.total(.block(.oreCart)) == 0, "an ore cart put on a rail becomes a cart: two crates on two rail wheels")
    check(g.vehicleStores(c, PartCell(dx: 0, dy: 0)), "its crates hold things")
    // pushed to the top of the slope, it rolls down by itself
    physOnly(g, 0.5)
    c.vx = 5; c.asleep = false
    physOnly(g, 6.0)
    check(c.b.y > 105.5 && c.px > Double(x0 + 81), "pushed over the top of a slope of rails it rolls down by itself and on (now at \(f1(c.px - Double(x0))), row \(f1(c.b.y)))")
}

print("== a train")
do {
    let (g, x0) = runway(length: 900)
    rails(g, x0 + 10, x0 + 800)
    let loco = cart(g, left: Double(x0 + 30), bottom: 100, couplers: true, engine: true)
    let wagon = cart(g, left: Double(x0) + 34.2, bottom: 100, couplers: true)
    physOnly(g, 1.0)
    check(loco.links.count == 1 && wagon.links.count == 1 && loco.links[0].other == wagon.id, "two couplers that touch link the engine and the wagon")
    let gap0 = wagon.px - loco.px
    _ = drive(g, loco, 6.0, 1)
    let gap1 = wagon.px - loco.px
    check(loco.speed > 3 && abs(gap1 - gap0) < 0.4 && wagon.speed > 3, "the engine pulls the wagon along at \(f1(wagon.speed)) a second, the gap held (\(f3(gap0)) then \(f3(gap1)))")
    _ = drive(g, loco, 3.0, -1)
    check(wagon.px - loco.px < gap0 + 0.4, "backing up, it pushes the wagon too")
    let r = Vehicle.restore(loco.save())
    check(r.links.count == 1 && r.links[0].other == wagon.id, "the coupling is saved")
    // walk through: from the engine's top to the wagon's
    g.inVehicle = nil; loco.rider = false
    physOnly(g, 3.0)
    g.pauseVehicles = true
    let deck = loco.toWorld(1.5, 0.0)
    drop(g, deck.0, deck.1 - 0.05)
    settle(g, 0.4)
    var crossed = false
    var t = 0.0
    while t < 2.0 {
        g.stick = 1
        g.tick(dt60); t += dt60
        if g.pb.ride == wagon.id { crossed = true }
    }
    g.stick = 0
    check(crossed, "the player walks from the engine across onto the wagon")
    g.pauseVehicles = false
    // uncoupled by a tap, they part
    g.uncouple(loco, loco.links.first?.cell ?? PartCell(dx: 2, dy: 0))
    check(loco.links.isEmpty && wagon.links.isEmpty, "a tap on the coupler lets go (both forget the link)")
    physOnly(g, 0.5)
    check(loco.links.isEmpty, "and they do not link again straight away")
}

// ---------------------------------------------------------------- B. big parts
print("== the big wheel")
do {
    let (g, x0) = runway()
    let v = car(g, engines: 2, left: x0 + 20)
    physOnly(g, 0.5)
    g.inv.add(.part(.bigWheel), 2)
    g.sel = g.inv.slots.firstIndex(where: { $0?.item == .part(.bigWheel) }) ?? 0
    // replace the small wheels: off with them, a big wheel under each end
    for (c, t) in v.parts where t == .wheel { _ = v.cutAway(c) }
    v.recompute(keepAnchor: true)
    for end in [0, 3] {
        let mid = PartCell(dx: end, dy: 2)
        let w = v.cellCenter(mid)
        g.aimX = w.0; g.aimY = w.1
        g.pb.x = w.0 - 2; g.pb.y = 99
        g.useCD = 0
        _ = g.attachBigWheel()
    }
    check(v.spanOf.count == 18 && v.wheels == 2 && v.parts.count >= 18, "two big wheels put on, three cells across each (the car lifted to make room)")
    let m = v.mass
    // a step two blocks high
    for x in (x0 + 40)...(x0 + 200) { g.world.set(x, 99, .stone); g.world.set(x, 98, .stone) }
    physOnly(g, 1.0)
    let x1 = v.px
    _ = drive(g, v, 8.0, 1)
    check(v.px > Double(x0 + 44) && v.b.y < 98.2, "the big wheels climb a step two blocks high (now at \(f1(v.px - Double(x0))), mass \(f1(m)))")
    // (the far end of the runway may have been put away while the player drove: load it again first)
    g.world.loadAround(centerX: x0 + 320, radius: 4)
    let small = car(g, engines: 2, left: x0 + 300)
    for x in (x0 + 320)...(x0 + 330) { g.world.set(x, 99, .stone); g.world.set(x, 98, .stone) }
    physOnly(g, 0.5)
    _ = drive(g, small, 8.0, 1)
    check(small.px < Double(x0 + 320), "a car on small wheels stops at it (\(f1(small.px - Double(x0 + 300))) blocks)")
    _ = x1
    let saved = Vehicle.restore(v.save())
    check(saved.spanOf.count == 18 && saved.wheels == 2, "big wheels are saved whole")
    // off with one: all nine cells go, and one big wheel comes back
    g.inVehicle = nil; v.rider = false
    let bag0 = g.inv.total(.part(.bigWheel))
    var any: PartCell? = nil
    for (c, mid) in v.spanOf where c != mid { any = c; break }
    if let c = any { g.removeVehiclePart(v, c) }
    check(v.spanOf.count == 9 && g.inv.total(.part(.bigWheel)) == bag0 + 1, "the wrench on any cell of one takes the whole wheel off and gives one back")
}

// ---------------------------------------------------------------- C. big vehicles
print("== a ship of four hundred cells")
do {
    let (g, x0) = runway(length: 900)
    for x in x0...(x0 + 400) {
        for y in 100..<112 { g.world.set(x, y, .water) }
        for y in 112..<116 { g.world.set(x, y, .stone) }
    }
    g.world.calmLiquids()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<70 {
        cells.append((x, 5, .hull, nil))
        for y in 0...4 { cells.append((x, y, .block, .planks)) }
    }
    cells.append((-1, 2, .propeller, nil))
    for e in 0..<4 { cells.append((-1 - e, 1, .engine, nil)) }
    cells.append((5, -1, .cockpit, nil))
    let v = build(g, cells, left: Double(x0 + 100), bottom: 101)
    check(v.parts.count >= 400, "a ship of \(v.parts.count) cells")
    var t = 0.0
    while t < 3 { g.updateVehicles(dt60); t += dt60 }
    let samples = g.vehicleSamples(v).count
    let key = v.sampleKey
    _ = g.vehicleSamples(v)
    check(v.sampleKey == key, "its collision samples (\(samples)) are kept until it changes")
    g.inVehicle = v; v.rider = true
    let t0 = Date()
    var frames = 0
    while frames < 120 { v.throttle = 1; v.rider = true; g.updateVehicles(dt60); frames += 1 }
    let ms = Date().timeIntervalSince(t0) * 1000 / 120
    print("  a frame of the ship under way: \(f1(ms)) ms (debug build)")
    check(ms < 60 && v.speed > 0.2, "under way (\(f1(v.speed)) a second) it costs \(f1(ms)) ms a frame in a debug build")
    g.stick = 0
    // at rest it sleeps and costs nothing
    g.inVehicle = nil; v.rider = false
    t = 0
    while t < 20 && !v.asleep { g.updateVehicles(dt60); t += dt60 }
    check(v.asleep, "left alone it comes to rest and sleeps")
}

print("phys4: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
