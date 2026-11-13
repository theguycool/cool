import SwiftUI
import Foundation
// Phase 2 of the physics overhaul, vehicle foundations: vehicles meeting each other cell by cell (pushes
// by mass, a crate carried on a truck's bed, a plane landing on a moving deck, cars head on at speed,
// resting on each other and waking together), parts anywhere (wheels on any side, a rotor boxed in, a
// boxed-in jet, steering away from the seat), several seats, and insides: doors, ladders, stairs,
// chairs, beds, stations and back walls aboard, saved and assembled; the cached picture of big vehicles.

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

// ---------------------------------------------------------------- A. vehicles meeting vehicles
print("== a crate dropped onto a deck")
do {
    var rests: [Double] = []
    for order in 0..<3 {
        let (g, x0) = runway()
        g.pauseVehicles = false
        let base = build(g, (0..<10).map { ($0, 0, .frame, nil) }, left: Double(x0 + 20), bottom: 100)
        let box = crate(g, 2, left: Double(x0 + 24), bottom: 80)
        if order == 1 { g.vehicles.reverse() }
        if order == 2 { box.vy = 20 }
        physOnly(g, 4.0)
        rests.append(box.b.y)
        check(abs(box.b.y - (base.b.top)) < 0.08 && overlap(box, base) == 0 && box.speed < 0.2, "order \(order): a crate falling \(order == 2 ? "fast " : "")onto a frame deck rests on it (its bottom \(f3(box.b.y)), the deck's top \(f3(base.b.top)))")
    }
    check(abs(rests[0] - rests[1]) < 0.05 && abs(rests[0] - rests[2]) < 0.05, "the same rest whichever vehicle is stepped first")
}

print("== pushing by mass")
do {
    let (g, x0) = runway()
    let tank = kit(g, .tankKit, x0 + 20, 100)
    let light = crate(g, 2, left: Double(x0 + 20) + tank.b.w + 2, bottom: 100)
    physOnly(g, 1.0)
    let x1 = light.b.x
    _ = drive(g, tank, 5.0, 1)
    g.inVehicle = nil; tank.rider = false
    check(light.b.x > x1 + 8 && overlap(light, tank) == 0, "a tank drives into a crate of planks and pushes it along (\(f1(light.b.x - x1)) blocks), never inside it")
    // a heavy stone block the same size is pushed far less
    let (g2, y0) = runway()
    let tank2 = kit(g2, .tankKit, y0 + 20, 100)
    let heavy = crate(g2, 2, left: Double(y0 + 20) + tank2.b.w + 2, bottom: 100, tile: .stone)
    physOnly(g2, 1.0)
    let x2 = heavy.b.x
    _ = drive(g2, tank2, 5.0, 1)
    check(heavy.b.x - x2 < light.b.x - x1 && overlap(heavy, tank2) == 0, "a crate of stone is pushed less (\(f1(heavy.b.x - x2)) against \(f1(light.b.x - x1)) blocks)")
}

print("== head on at speed")
do {
    let (g, x0) = runway()
    // in the air, so nothing but each other slows them
    let a = crate(g, 2, left: Double(x0 + 40), bottom: 40)
    let b = crate(g, 2, left: Double(x0 + 120), bottom: 40)
    a.vx = 60; b.vx = -60; a.asleep = false; b.asleep = false
    let p0 = a.mass * a.vx + b.mass * b.vx
    var minGap = 99.0
    var t = 0.0
    var met = false
    while t < 1.0 {
        g.updateVehicles(dt60); t += dt60
        minGap = min(minGap, b.b.left - a.b.right)
        if a.contacts > 0 { met = true }
    }
    check(met && a.b.right <= b.b.left + 0.15 && a.b.x < b.b.x && overlap(a, b) == 0, "two crates meeting in the air at 60 blocks a second each never pass through each other (closest \(f3(minGap)))")
    let p1 = a.mass * a.vx + b.mass * b.vx
    check(abs(p1 - p0) < 0.2 * a.mass * 60 && a.vx < 30 && b.vx > -30, "they stop each other (speeds now \(f1(a.vx)) and \(f1(b.vx)))")
}

print("== carried on a truck's bed")
do {
    let (g, x0) = runway()
    let truck = kit(g, .truckKit, x0 + 20, 100)
    physOnly(g, 1.0)
    // a crate on the bed: the truck's top row, at its back
    let box = crate(g, 1, left: truck.b.left + 0.2, bottom: truck.b.top - 0.02)
    physOnly(g, 1.0)
    let off0 = box.b.x - truck.b.x
    let rest0 = box.restOn
    _ = drive(g, truck, 3.0, 1)
    let off1 = box.b.x - truck.b.x
    check(rest0 == truck.id && box.restOn == truck.id && abs(off1 - off0) < 1.5 && truck.speed > 4, "a crate on a truck rides along as it drives off (truck at \(f1(truck.speed)), the crate moved \(f1(off1 - off0)) on the bed)")
}

print("== landing on a moving deck")
do {
    let (g, x0) = runway(length: 900)
    let carrier = build(g, (0..<40).map { ($0, 0, .frame, nil) } + (0..<40).map { ($0, 1, .frame, nil) }, left: Double(x0 + 20), bottom: 100)
    // the deck goes at 8 a second; the plane comes in a little faster, just above it
    let plane = kit(g, .planeKit, x0 + 24, 96)
    plane.vx = 9
    var t = 0.0
    while t < 5.0 {
        carrier.vx = 8; carrier.asleep = false
        g.updateVehicles(dt60); t += dt60
    }
    print("  plane restOn \(plane.restOn) carrier \(carrier.id) bottom \(f3(plane.b.y)) deck top \(f3(carrier.b.top)) overlap \(f3(overlap(plane, carrier))) contacts \(plane.contacts) angle \(f3(plane.angle))")
    check(plane.restOn == carrier.id && abs(plane.vx - carrier.vx) < 1.5 && plane.b.y <= carrier.b.top + 0.1 && overlap(plane, carrier) == 0, "a plane coming down onto a deck moving at 8 a second rests on it and goes with it (plane \(f1(plane.vx)), deck \(f1(carrier.vx)))")
}

print("== asleep together")
do {
    let (g, x0) = runway()
    let base = build(g, (0..<8).map { ($0, 0, .frame, nil) }, left: Double(x0 + 20), bottom: 100)
    let box = crate(g, 1, left: Double(x0 + 23), bottom: 99)
    physOnly(g, 3.0)
    check(base.asleep && box.asleep, "a crate at rest on a vehicle at rest: both asleep")
    base.vx = 6; base.asleep = false
    physOnly(g, 0.3)
    check(!box.asleep && box.vx > 1.0, "the vehicle under it is shoved: the crate wakes and goes with it (\(f1(box.vx)))")
}

print("== a rider meets another vehicle")
do {
    let (g, x0) = runway()
    g.godMode = false
    let base = build(g, (0..<16).map { ($0, 0, .frame, nil) }, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    // a crate of two by two standing on the deck (another vehicle)
    let box = crate(g, 2, left: Double(x0 + 30), bottom: 89)
    drop(g, Double(x0) + 23.5, 88.5)
    settle(g, 0.5)
    check(g.pb.ride == base.id, "the player stands on the deck")
    var t = 0.0
    while t < 2.0 {
        shift(g, base, vx: 6); shift(g, box, vx: 6)
        g.stick = 1
        g.tick(dt60); t += dt60
    }
    g.stick = 0
    check(g.pb.ride == base.id && g.pb.right <= box.b.left + 0.05, "walking into a crate parked on the deck: it is in the way (feet \(f3(g.pb.right)), crate \(f3(box.b.left)))")
    // jump onto it
    t = 0
    var onIt = false
    while t < 1.5 {
        shift(g, base, vx: 6); shift(g, box, vx: 6)
        // (right until over the crate, then back a little to come down on it)
        g.stick = g.pb.x < box.b.left + 0.5 ? 1 : (g.pb.vx > 0.5 ? -1 : 0)
        g.jumpHeld = t < 0.25
        g.tick(dt60); t += dt60
        if g.pb.ride == box.id { onIt = true }
    }
    g.stick = 0; g.jumpHeld = false
    check(onIt && g.pb.ride == box.id && g.pb.onGround, "jumping onto it: aboard the crate now, carried by it")
}

// ---------------------------------------------------------------- B. parts anywhere
print("== parts anywhere")
do {
    let (g, x0) = runway()
    let v = car(g, engines: 1, left: x0 + 20)
    // a wheel on the roof, a wheel on the side, a rotor under a frame, a jet between two frames
    check(g.attachProblem(v, PartCell(dx: 2, dy: -2), .wheel) == nil, "a wheel can go on top")
    check(g.attachProblem(v, PartCell(dx: -1, dy: 0), .wheel) == nil, "a wheel can go on the side")
    check(g.attachProblem(v, PartCell(dx: 1, dy: 1), .rotor) == nil, "a rotor can go under the body")
    check(g.attachProblem(v, PartCell(dx: 0, dy: 0), .wheel) != nil, "a taken cell is still taken")
    check(g.attachProblem(v, PartCell(dx: 9, dy: 9), .wheel) != nil, "a part must still touch the vehicle")
    // rotors lift by their room
    let h1 = kit(g, .heliKit, x0 + 60, 100)
    let free = g.rotorMax(h1, anyway: true)
    var rc: PartCell? = nil
    for (c, t) in h1.parts where t == .rotor { rc = c }
    if let r = rc {
        h1.parts[PartCell(dx: r.dx - 1, dy: r.dy - 1)] = .frame
        h1.parts[PartCell(dx: r.dx, dy: r.dy - 1)] = .frame
        h1.recompute(keepAnchor: true)
    }
    let crowded = g.rotorMax(h1, anyway: true)
    check(crowded < free * 0.7 && crowded > 0, "a rotor with frames in its blades' row lifts less (\(f1(crowded)) against \(f1(free)))")
    check(g.partNote(h1, rc ?? PartCell(dx: 0, dy: 0), .rotor) != nil, "and the game says so when it is put there")
    // a jet boxed in on both sides gives no thrust
    let jetV = build(g, [(0, 0, .frame, nil), (1, 0, .jet, nil), (2, 0, .frame, nil), (1, -1, .cockpit, nil), (0, -1, .fuelTank, nil)], left: Double(x0 + 100), bottom: 60)
    check(jetV.boxed.contains(PartCell(dx: 1, dy: 0)), "a jet between two frames is boxed in")
    jetV.rider = true; jetV.throttle = 1
    g.airForces(jetV, 1.0 / 120.0, 1)
    check(jetV.thrustNow == 0, "and pushes nothing (thrust \(f1(jetV.thrustNow)))")
    jetV.parts[PartCell(dx: 2, dy: 0)] = nil
    jetV.recompute(keepAnchor: true)
    g.airForces(jetV, 1.0 / 120.0, 1)
    check(!jetV.boxed.contains(PartCell(dx: 1, dy: 0)) && jetV.thrustNow > 0, "opened on one side it pushes (\(f1(jetV.thrustNow)))")
}

print("== wheels that work where they touch")
do {
    // a car with wheels above and below, lying on its roof: the roof wheels drive it
    let (g, x0) = runway()
    let v = build(g, [(0, 0, .frame, nil), (1, 0, .seat, nil), (2, 0, .steering, nil), (3, 0, .engine, nil),
                      (0, 1, .wheel, nil), (3, 1, .wheel, nil), (0, -1, .wheel, nil), (3, -1, .wheel, nil)], left: Double(x0 + 40), bottom: 100)
    v.angle = Double.pi
    v.updateBox()
    physOnly(g, 1.0)
    let x1 = v.px
    _ = drive(g, v, 3.0, 1)
    check(v.px > x1 + 4, "upside down on its roof wheels it still drives (\(f1(v.px - x1)) blocks in 3 s)")
    // steering at the far end from the seat
    let (g2, y0) = runway()
    let c2 = build(g2, [(0, 0, .frame, nil), (1, 0, .frame, nil), (2, 0, .frame, nil), (3, 0, .frame, nil), (4, 0, .frame, nil),
                        (0, 1, .wheel, nil), (4, 1, .wheel, nil), (0, -1, .seat, nil), (4, -1, .steering, nil), (2, -1, .engine, nil)], left: Double(y0 + 40), bottom: 100)
    physOnly(g2, 0.5)
    let x2 = c2.px
    _ = drive(g2, c2, 2.0, 1)
    check(c2.px > x2 + 5, "the steering wheel at the far end from the seat still steers (\(f1(c2.px - x2)) blocks)")
}

print("== several seats")
do {
    let (g, x0) = runway()
    let v = build(g, [(0, 0, .frame, nil), (1, 0, .frame, nil), (2, 0, .frame, nil), (3, 0, .frame, nil), (4, 0, .frame, nil),
                      (0, 1, .wheel, nil), (4, 1, .wheel, nil), (0, -1, .seat, nil), (1, -1, .steering, nil), (4, -1, .seat, nil), (2, -1, .engine, nil)], left: Double(x0 + 40), bottom: 100)
    physOnly(g, 0.5)
    g.mountVehicle(v, at: PartCell(dx: 4, dy: -1))
    g.tick(dt60)
    let seatW = v.toWorld(4.5, -0.05)
    check(g.inVehicle === v && g.seatCell(v) == PartCell(dx: 4, dy: -1) && abs(g.pb.x - seatW.0) < 0.1, "tapping the back seat: driving from the back seat")
    let s = v.save()
    let r = Vehicle.restore(s)
    check(r.seatAt == PartCell(dx: 4, dy: -1), "the seat is kept in the save")
}

// ---------------------------------------------------------------- D. insides
/// A long room of planks w x h (inside open), standing on the runway, with whatever else is put in
func house(_ g: Game, _ w: Int, _ h: Int, left: Double, bottom: Double, extra: [(Int, Int, PartType, Tile?)] = [], skip: Set<PartCell> = []) -> Vehicle {
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<w {
        for y in 0..<h where (x == 0 || x == w - 1 || y == 0 || y == h - 1) && !skip.contains(PartCell(dx: x, dy: y)) { cells.append(plank(x, y)) }
    }
    cells.append(contentsOf: extra)
    return build(g, cells, left: left, bottom: bottom)
}

print("== doors aboard")
do {
    let (g, x0) = runway()
    g.godMode = false
    // a room 12 wide with an inner wall of planks at x 6, a door in it (rows 3 and 4: the floor is row 5)
    var extra: [(Int, Int, PartType, Tile?)] = []
    for y in 1...2 { extra.append(plank(6, y)) }
    extra.append((6, 3, .block, .doorClosed)); extra.append((6, 4, .block, .doorClosed))
    let v = house(g, 12, 6, left: Double(x0 + 20), bottom: 90, extra: extra)
    g.pauseVehicles = true
    drop(g, Double(x0) + 22.5, 88.5)
    settle(g, 0.5)
    check(g.pb.ride == v.id && g.pb.rlx < 6, "the player stands in the room, left of the door")
    var opened = false
    var t = 0.0
    while t < 2.0 {
        shift(g, v, vx: 10)
        g.stick = 1
        g.tick(dt60); t += dt60
        if g.vehicleBlock(v, PartCell(dx: 6, dy: 3)) == .doorOpen { opened = true }
    }
    g.stick = 0
    check(opened && g.pb.rlx > 7.0 && g.pb.ride == v.id, "walking into the door while the room moves: it opens and they go through (at \(f1(g.pb.rlx)))")
    t = 0
    while t < 2.0 { shift(g, v, vx: 10); g.tick(dt60); t += dt60 }
    check(g.vehicleBlock(v, PartCell(dx: 6, dy: 3)) == .doorClosed, "it shuts behind them")
    // a tap opens and shuts it
    _ = g.useVehicleBlock(v, PartCell(dx: 6, dy: 4))
    check(g.vehicleBlock(v, PartCell(dx: 6, dy: 3)) == .doorOpen && g.vehicleBlock(v, PartCell(dx: 6, dy: 4)) == .doorOpen, "a tap opens both of its cells")
}

print("== ladders and stairs aboard")
do {
    let (g, x0) = runway()
    g.godMode = false
    // a tower: floor 8 wide at row 0, a ladder column at x 3 from row -1 up to row -6, a top deck at row -7
    var cells: [(Int, Int, PartType, Tile?)] = (0..<8).map { plank($0, 0) }
    for y in 1...6 { cells.append((3, -y, .block, .ladder)) }
    for x in 0..<8 where x != 3 { cells.append(plank(x, -7)) }
    cells.append((3, -7, .block, .platform))
    cells.append((6, -1, .block, .stairWoodR))
    let v = build(g, cells, left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    drop(g, Double(x0) + 23.5, 88.0)
    settle(g, 0.5)
    check(g.pb.ride == v.id, "the player stands at the foot of a ladder on a vehicle")
    let ly0 = g.pb.rly
    var t = 0.0
    while t < 2.0 {
        shift(g, v, vx: 8)
        g.jumpHeld = true
        g.tick(dt60); t += dt60
    }
    g.jumpHeld = false
    check(g.pb.ride == v.id && g.pb.rly < ly0 - 4.5, "holding up climbs the ladder while the vehicle moves (\(f1(ly0 - g.pb.rly)) blocks up it)")
    // stairs: walking into a stair cell steps up onto it
    let (g2, y0) = runway()
    g2.godMode = false
    let v2 = build(g2, (0..<10).map { plank($0, 0) } + [(6, -1, .block, .stairWoodR), (7, -1, .block, .planks), (7, -2, .block, .stairWoodR)], left: Double(y0 + 20), bottom: 90)
    g2.pauseVehicles = true
    drop(g2, Double(y0) + 22.5, 88.5)
    settle(g2, 0.5)
    t = 0
    var high = 9.0
    while t < 1.2 {
        shift(g2, v2, vx: 5)
        g2.stick = 1
        g2.tick(dt60); t += dt60
        if g2.pb.ride == v2.id { high = min(high, g2.pb.rly) }
    }
    g2.stick = 0
    check(high <= -1.9, "walking into stairs on a vehicle climbs them (feet up to row \(f1(high)))")
    // a ladder reached from the land takes the player aboard
    let (g3, z0) = runway()
    let v3 = build(g3, [(0, 0, .frame, nil), (1, 0, .frame, nil), (0, -1, .block, .ladder), (0, -2, .block, .ladder), (0, -3, .block, .ladder), (1, -3, .frame, nil)], left: Double(z0 + 30), bottom: 100)
    g3.pauseVehicles = true
    drop(g3, Double(z0) + 30.5, 99.0)
    g3.pb.y = 99.0
    t = 0
    while t < 1.0 { g3.jumpHeld = true; g3.tick(dt60); t += dt60 }
    g3.jumpHeld = false
    check(g3.pb.ride == v3.id, "a vehicle's ladder climbed from the land takes the player aboard")
}

print("== chairs, beds and stations aboard")
do {
    let (g, x0) = runway()
    g.godMode = false
    let v = build(g, (0..<10).map { plank($0, 0) } + [(2, -1, .block, .chair), (4, -1, .block, .bedL), (5, -1, .block, .bedR), (7, -1, .block, .workbench)], left: Double(x0 + 20), bottom: 90)
    g.pauseVehicles = true
    drop(g, Double(x0) + 21.5, 88.5)
    settle(g, 0.4)
    check(g.useVehicleBlock(v, PartCell(dx: 2, dy: -1)) && g.seatAboard == PartCell(dx: 2, dy: -1), "tapping a chair on a vehicle sits the player in it")
    carry(g, v, 2.0, vx: 25, vy: -3)
    let at = v.toWorld(2.5, 0.0)
    check(g.seatAboard != nil && abs(g.pb.x - at.0) < 0.05 && abs(g.pb.y - at.1) < 0.05, "a passenger: carried in the chair while it flies at 25 a second")
    carry(g, v, 0.3, vx: 25, jumpAt: 0.0)
    check(g.seatAboard == nil && g.pb.ride == v.id, "jumping stands them up, still aboard")
    check(g.stationNear(.workbench), "a workbench built on the vehicle counts as a station within reach")
    let sx = g.spawnX
    g.timeOfDay = 0.8
    _ = g.useVehicleBlock(v, PartCell(dx: 4, dy: -1))
    check(g.timeOfDay < 0.1 && g.spawnX == sx, "a bed aboard passes the night (and is not where they wake)")
}

print("== back walls aboard")
do {
    let (g, x0) = runway()
    g.mode = .survival
    let v = house(g, 8, 5, left: Double(x0 + 20), bottom: 100)
    physOnly(g, 0.5)
    let m0 = v.mass
    let inside = v.cellCenter(PartCell(dx: 3, dy: 2))
    g.aimX = inside.0; g.aimY = inside.1
    g.inv.add(.block(.planks), 4)
    g.wallMode = true; g.vehicleBuild = true
    g.sel = g.inv.slots.firstIndex(where: { $0?.item == .block(.planks) }) ?? 0
    g.placeCD = 0
    let ok = g.attachWallToVehicle(.planks)
    check(ok && v.walls[PartCell(dx: 3, dy: 2)] != nil && v.mass > m0, "a plank put up as a back wall inside the vehicle (mass \(f1(m0)) to \(f1(v.mass)))")
    let r = Vehicle.restore(v.save())
    check(r.walls[PartCell(dx: 3, dy: 2)] == v.walls[PartCell(dx: 3, dy: 2)], "the wall is kept in the save")
    check(VehicleArt.picture(v) != nil, "a vehicle with a back wall is drawn from its picture")
    let key = v.artKey
    _ = VehicleArt.picture(v)
    check(v.artKey == key, "the picture is kept while nothing changes")
    _ = g.removeVehicleWall(v, PartCell(dx: 3, dy: 2))
    _ = VehicleArt.picture(v)
    check(v.walls.isEmpty && v.artKey != key, "taking the wall down: gone, and the picture made again")
    // the assembler takes a house's back walls with it
    for x in 60...65 { for y in 94...99 where x == 60 || x == 65 || y == 94 || y == 99 { g.world.set(x0 + x, y, .planks); g.world.setBuilt(x0 + x, y, true) } }
    for x in 61...64 { for y in 95...98 { g.world.setWall(x0 + x, y, blockWallValue(.planks)) } }
    g.assembleStructure(x0 + 60, 99)
    let hv = g.vehicles.last!
    check(hv.walls.count == 16 && g.world.wallAt(x0 + 62, 96) == 0, "a house turned into a vehicle takes its 16 back walls along (\(hv.walls.count))")
}

print("phys2: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
