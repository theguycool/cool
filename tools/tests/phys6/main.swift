import SwiftUI
import Foundation
// Phase 6 of the physics overhaul, automation and attachments: guns that fire by themselves (turrets)
// or on a button, guns on a machine's sections, the receiver and the remote control, autopilots far
// from the player, signal posts and the vehicle sensor, the Logic Studio's signal channels, and mods'
// own guns with their own shots.

setvbuf(stdout, nil, _IONBF, 0)
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


/// A machine built as one vehicle, split at its joint parts into sections
func machine(_ g: Game, _ cells: [(Int, Int, PartType, Tile?)], left: Double, bottom: Double) -> Vehicle {
    let v = build(g, cells, left: left, bottom: bottom)
    g.splitJointSections(v)
    return v
}
/// The gap between a joint's two pivot points (they should be one point)
func gap(_ g: Game, _ a: Vehicle, _ j: VJoint) -> Double {
    guard let b = g.vehicleByID(j.child) else { return 99 }
    let pa = a.toWorld(j.pa[0], j.pa[1])
    let pb = b.toWorld(j.pb[0], j.pb[1])
    return sqrt((pa.0 - pb.0) * (pa.0 - pb.0) + (pa.1 - pb.1) * (pa.1 - pb.1))
}
func relAngle(_ g: Game, _ a: Vehicle, _ j: VJoint) -> Double {
    guard let b = g.vehicleByID(j.child) else { return 0 }
    return remainder(b.angle - a.angle - j.base, 2 * Double.pi)
}
/// A heavy stone base three wide and two high standing on the runway, with whatever is put beside it
func base(_ extra: [(Int, Int, PartType, Tile?)], high: Int = 2) -> [(Int, Int, PartType, Tile?)] {
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<3 { for y in 0..<high { cells.append((x, y, .block, .stone)) } }
    return cells + extra
}


/// A gun post: three frames on the runway with a seat, a steering wheel and, at the right-hand end, a
/// machine gun (its right side open, so it points right and turns up and down from there)
func gunPost(_ g: Game, _ x0: Int) -> (Vehicle, PartCell) {
    let v = build(g, [(0, 0, .frame, nil), (1, 0, .frame, nil), (2, 0, .frame, nil), (0, -1, .seat, nil), (1, -1, .steering, nil), (2, -1, .autoGun, nil)], left: Double(x0 + 20), bottom: 100)
    return (v, PartCell(dx: 2, dy: -1))
}
/// Shots in flight from a vehicle's guns
func shotsFrom(_ g: Game, _ v: Vehicle) -> Int {
    return g.projectiles.filter { $0.owner >= 2_000_000 }.count
}
/// A creature standing still on the runway, a few blocks right of the gun post
func target(_ g: Game, _ kind: MobKind, _ x: Double) -> Mob {
    let m = g.addMob(kind, x, 100)
    m.persistent = true
    return m
}
func run(_ g: Game, _ secs: Double) {
    var t = 0.0
    while t < secs { g.tick(dt60); g.hunger = 20; t += dt60 }
}


/// Holds the attack for a while, aimed at a point in the world (as the attack stick does)
func attack(_ g: Game, _ secs: Double, _ ax: Double, _ ay: Double) {
    var t = 0.0
    while t < secs {
        g.useHeld = true; g.aimX = ax; g.aimY = ay; g.aimValid = true
        g.tick(dt60); g.hunger = 20; t += dt60
    }
    g.useHeld = false
}

// ---------------------------------------------------------------- A. guns that fire by themselves
print("== a turret")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    let (v, c) = gunPost(g, x0)
    let z = target(g, .zombie, Double(x0 + 30))
    let hp0 = z.hp
    run(g, 2.0)
    check(z.hp == hp0, "a gun as built fires only for its driver: with nobody aboard the zombie is left alone")
    g.interactVehicle(v, c)
    run(g, 3.0)
    check(z.hp < hp0, "tapped once it is a turret: it shoots the zombie by itself (\(f1(hp0)) -> \(f1(max(0, z.hp))))")
}

print("== what a turret leaves alone")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    let (v, c) = gunPost(g, x0)
    g.interactVehicle(v, c)
    let pig = target(g, .pig, Double(x0 + 30))
    let hp0 = pig.hp
    run(g, 3.0)
    check(pig.hp == hp0, "it leaves a pig alone")
    // a zombie behind a stone wall
    let (g2, y0) = runway()
    g2.pauseMobs = true
    let (w, wc) = gunPost(g2, y0)
    g2.interactVehicle(w, wc)
    for y in 90..<100 { g2.world.set(y0 + 26, y, .stone) }
    let z = target(g2, .zombie, Double(y0 + 30))
    let zh = z.hp
    run(g2, 3.0)
    check(z.hp == zh, "and a zombie behind a wall it cannot see through")
}

print("== how a gun fires, round and saved")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    let (v, c) = gunPost(g, x0)
    g.interactVehicle(v, c)
    let saved = Vehicle.restore(v.save())
    check(saved.gunMode[c] == v.gunMode[c] && v.gunMode[c] != nil, "a turret is saved as a turret")
    for _ in 1..<GunMode.allCases.count { g.interactVehicle(v, c) }
    let z = target(g, .zombie, Double(x0 + 30))
    let hp0 = z.hp
    run(g, 2.0)
    check(z.hp == hp0, "tapped round through every way of firing it is back to firing only for its driver")
}

print("== a gun on button A")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    let (v, c) = gunPost(g, x0)
    v.gunMode[c] = GunMode.buttonA.rawValue
    g.inVehicle = v; v.rider = true
    run(g, 1.0)
    check(shotsFrom(g, v) == 0, "driven, with A not held it does not fire")
    g.jointButtons[0] = true
    run(g, 0.5)
    g.jointButtons[0] = false
    check(shotsFrom(g, v) > 0, "holding A it fires")
}


// ---------------------------------------------------------------- B. guns on a machine
print("== a gun on an arm")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    // a crane: the seat on the base, a servo, and an arm of two planks with a machine gun at its end
    let v = machine(g, base([(1, -1, .seat, nil), (0, -1, .steering, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .autoGun, nil)]), left: Double(x0 + 20), bottom: 100)
    let arm = g.vehicleByID(v.joints[0].child)!
    g.inVehicle = v; v.rider = true
    let muzzle = arm.cellCenter(PartCell(dx: 6, dy: 0))
    check(g.useLabel == "FIRE", "driving it, the attack button fires (the machine's only gun is on its arm)")
    attack(g, 1.0, muzzle.0 + 20, muzzle.1)
    check(shotsFrom(g, arm) > 0, "the gun on the arm fires with its driver's attack")
}

print("== a machine's shots pass its own sections")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    g.settings.vehicleDamage = true
    // a gun on the base's top corner aims down across the arm below it
    let v = machine(g, base([(1, -1, .seat, nil), (0, -1, .steering, nil), (2, -1, .autoGun, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    let arm = g.vehicleByID(v.joints[0].child)!
    g.inVehicle = v; v.rider = true
    let gun = v.cellCenter(PartCell(dx: 2, dy: -1))
    attack(g, 1.5, gun.0 + 5.5, gun.1 + 2.5)
    check(arm.parts.count == 3 && arm.dmg.values.allSatisfy { $0 <= 0 }, "shooting across its own arm leaves the arm whole and unhurt (\(arm.parts.count) of 3 planks left)")
}


// ---------------------------------------------------------------- C. the receiver and the remote control
/// A small car (seat, steering, an engine) on the runway, with a receiver on its roof if asked
func remoteCar(_ g: Game, _ x0: Int, receiver: Bool, at dx: Int = 30) -> Vehicle {
    var extra: [(Int, Int, PartType, Tile?)] = []
    if receiver { extra.append((3, -1, .receiver, nil)) }
    return car(g, engines: 1, left: x0 + dx, extra: extra)
}
/// The player holding the remote control, standing at a place on the runway
func holdRemote(_ g: Game, at x: Double) {
    g.inv.slots[0] = Stack(item: .gadget(.remote), count: 1)
    g.setSel(0)
    drop(g, x, 100)
    settle(g, 0.3)
}
/// Uses the remote with the aim at a point (as a tap does)
func useRemote(_ g: Game, _ x: Double, _ y: Double) {
    g.aimX = x; g.aimY = y; g.aimValid = true
    g.useCD = 0
    g.useGadget(.remote, true)
}
/// Pairs the remote with a car (standing beside it), then walks off to a place
func pairAndWalk(_ g: Game, _ v: Vehicle, to x: Double) {
    holdRemote(g, at: v.b.left - 1.5)
    let p = v.cellCenter(PartCell(dx: 1, dy: 0))
    useRemote(g, p.0, p.1)
    drop(g, x, 100)
    settle(g, 0.3)
}

print("== pairing the remote")
do {
    let (g, x0) = runway()
    let plain = remoteCar(g, x0, receiver: false)
    holdRemote(g, at: plain.b.left - 1.5)
    let p = plain.cellCenter(PartCell(dx: 1, dy: 0))
    useRemote(g, p.0, p.1)
    check(g.remotePair == 0, "a car with no receiver will not pair with the remote")
    let fitted = remoteCar(g, x0, receiver: true, at: 60)
    holdRemote(g, at: fitted.b.left - 1.5)
    let q = fitted.cellCenter(PartCell(dx: 1, dy: 0))
    useRemote(g, q.0, q.1)
    check(g.remotePair == fitted.id, "a car with a receiver pairs with it")
}

print("== driving by remote")
do {
    let (g, x0) = runway()
    let v = remoteCar(g, x0, receiver: true)
    pairAndWalk(g, v, to: Double(x0 + 8))
    let px0 = g.pb.x
    useRemote(g, g.pb.x + 3, 97)
    check(g.remoteID == v.id && v.rider, "used away from any vehicle, it takes the paired car's controls")
    let vx0 = v.px
    var t = 0.0
    while t < 2.0 { g.stick = 1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.stick = 0
    check(v.px > vx0 + 4 && abs(g.pb.x - px0) < 0.3, "the stick drives the car (\(f1(v.px - vx0)) blocks) while the player stays where they are")
    check(abs(g.camX - v.px) < 5, "the view follows the car")
    let had = g.remoteID == v.id
    g.jumpHeld = true; g.tick(dt60); g.jumpHeld = false; g.tick(dt60)
    check(had && g.remoteID == 0 && !v.rider, "JUMP lets go of the remote")
}

print("== what ends remote driving")
do {
    let (g, x0) = runway(mode: .survival)
    g.godMode = false
    let v = remoteCar(g, x0, receiver: true)
    pairAndWalk(g, v, to: Double(x0 + 8))
    useRemote(g, g.pb.x + 3, 97)
    let had = g.remoteID == v.id
    g.invuln = 0
    g.damagePlayer(3, from: g.pb.x + 1)
    check(had && g.remoteID == 0 && !v.rider, "getting hurt lets go of the remote")
    useRemote(g, g.pb.x + 3, 97)
    let again = g.remoteID == v.id
    v.placeBox(left: v.b.left + 400, bottom: 100)
    v.updateBox()
    settle(g, 0.2)
    check(again && g.remoteID == 0, "a car taken far out of the remote's reach is let go")
}

print("== the pairing is saved")
do {
    let (g, x0) = runway()
    let v = remoteCar(g, x0, receiver: true)
    pairAndWalk(g, v, to: Double(x0 + 8))
    let data = try! JSONEncoder().encode(g.makeSave())
    let s2 = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(s2, settings: Settings())
    check(g2.remotePair == v.id && g2.vehicleByID(v.id) != nil, "the remote stays paired with the car after saving and loading")
}


print("== a remote car's gun")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    // a car with a receiver on its roof and a machine gun on its nose
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil), (4, 0, .autoGun, nil)])
    pairAndWalk(g, v, to: Double(x0 + 8))
    useRemote(g, g.pb.x + 3, 97)
    check(g.remoteID == v.id && g.useLabel == "FIRE", "driving an armed car by remote, the attack button fires")
    let m = v.cellCenter(PartCell(dx: 4, dy: 0))
    attack(g, 0.6, m.0 + 20, m.1)
    check(shotsFrom(g, v) > 0 && g.remoteID == v.id, "and the car's gun fires, the remote still in hand")
}


print("== the driving buttons by remote")
do {
    let (g, x0) = runway()
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil), (2, -2, .autopilot, nil)])
    pairAndWalk(g, v, to: Double(x0 + 8))
    useRemote(g, g.pb.x + 3, 97)
    var t = 0.0
    while t < 1.0 { g.stick = 1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.cycleAutopilot()
    g.stick = 0
    check(g.remoteID == v.id && v.auto == 1, "AUTO switches the remote car's autopilot on")
    g.markWaypoint()
    check(v.route.count == 1, "MARK marks a point on its route")
    // (AUTO again: off, with one point there is no route to run) and the car brought to a stop
    g.cycleAutopilot()
    settle(g, 3.0)
    let dir0 = v.dir
    g.turnVehicle()
    settle(g, 1.5)
    check(v.auto == 0 && v.dir == -dir0, "TURN turns the remote car round")
}


// ---------------------------------------------------------------- D. autopilots far from the player
print("== a route far away")
do {
    let (g, x0) = runway(length: 1300)
    // a car with an autopilot, sent along a route to a point a thousand blocks off; the player stays home
    let v = car(g, engines: 2, left: x0 + 40, extra: [(1, -2, .autopilot, nil)])
    v.route = [VWaypoint(x: Double(x0 + 45), y: v.py), VWaypoint(x: Double(x0 + 1100), y: v.py)]
    v.routeAt = 1
    v.auto = 2
    drop(g, Double(x0 + 20), 100)
    var far = 0.0
    var back = false
    var t = 0.0
    while t < 260.0 {
        g.tick(dt60); g.hunger = 20; t += dt60
        far = max(far, v.px - Double(x0))
        if far > 1090 && v.px < Double(x0 + 100) { back = true; break }
    }
    check(far > 1090, "it drives on through land nobody is near (\(f1(far)) of 1100 blocks out)")
    check(back, "and comes back round its route")
}


// ---------------------------------------------------------------- E. signal posts, receivers and the vehicle sensor
@discardableResult
func put(_ g: Game, _ x: Int, _ y: Int, _ t: Tile) -> PowerDev? {
    g.world.set(x, y, t)
    return g.world.powerDev(x, y)
}
/// a straight run of wire on one layer (0 power, 1 amber pulse, 2 teal pulse)
func wire(_ g: Game, _ layer: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    var x = x0, y = y0
    while true {
        g.world.setWire(x, y, g.world.wireAt(x, y) | Wire.bit(layer))
        if x == x1 && y == y1 { break }
        if x != x1 { x += x1 > x ? 1 : -1 } else { y += y1 > y ? 1 : -1 }
    }
}
/// A battery powering a signal post on a channel, a lever on the post's pulse wire; gives the lever's place
func signalStation(_ g: Game, _ x: Int, channel: Int) -> (Int, Int) {
    let bat = put(g, x, 99, .battery)!
    bat.charge = 600
    let post = put(g, x + 3, 99, .signalPost)!
    post.mode = channel - 1
    wire(g, 0, x, 99, x + 3, 99)
    put(g, x + 3, 96, .lever)
    wire(g, 1, x + 3, 96, x + 3, 99)
    return (x + 3, 96)
}
func pull(_ g: Game, _ lever: (Int, Int)) { g.usePowerDevice(lever.0, lever.1, .lever) }

print("== a signal drives a car")
do {
    let (g, x0) = runway()
    let lever = signalStation(g, x0 + 2, channel: 2)
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil)])
    v.channel = 2
    v.radioAct = RadioAct.forward.rawValue
    let other = car(g, engines: 1, left: x0 + 60, extra: [(3, -1, .receiver, nil)])
    other.channel = 3
    other.radioAct = RadioAct.forward.rawValue
    run(g, 1.0)
    let a0 = v.px
    let b0 = other.px
    pull(g, lever)
    run(g, 2.0)
    let moved = v.px > a0 + 3
    check(moved, "a lever turns a signal post's channel on: a car listening to it drives off with nobody aboard (\(f1(v.px - a0)) blocks)")
    check(moved && abs(other.px - b0) < 0.3, "a car listening to another channel stays put")
    pull(g, lever)
    run(g, 2.0)
    check(moved && v.speed < 0.5, "the lever back: the channel goes off and the car stops")
}

print("== a signal runs a route")
do {
    let (g, x0) = runway()
    let lever = signalStation(g, x0 + 2, channel: 1)
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil), (2, -2, .autopilot, nil)])
    v.route = [VWaypoint(x: Double(x0 + 32), y: v.py), VWaypoint(x: Double(x0 + 80), y: v.py)]
    v.channel = 1
    v.radioAct = RadioAct.route.rawValue
    pull(g, lever)
    run(g, 0.5)
    let ran = v.auto == 2
    check(ran, "a car set to run its route does when its channel comes on")
    pull(g, lever)
    run(g, 0.5)
    check(ran && v.auto == 0, "and stops running it when the channel goes off")
}

print("== a signal holds a button")
do {
    let (g, x0) = runway()
    let lever = signalStation(g, x0 + 2, channel: 4)
    let v = machine(g, base([(1, -1, .seat, nil), (0, -1, .receiver, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks)]), left: Double(x0 + 30), bottom: 100)
    v.joints[0].input = JointInput.buttonA.rawValue
    v.joints[0].lo = -1.0; v.joints[0].hi = 0.0
    v.channel = 4
    v.radioAct = RadioAct.buttonA.rawValue
    run(g, 1.5)
    let low = relAngle(g, v, v.joints[0])
    pull(g, lever)
    run(g, 1.5)
    let high = relAngle(g, v, v.joints[0])
    check(abs(low + 1.0) < 0.15 && abs(high) < 0.15, "a machine's receiver set to button A holds A while its channel is on: the arm goes up (\(f3(low)) -> \(f3(high)))")
}

print("== a signal fires a gun")
do {
    let (g, x0) = runway()
    g.pauseMobs = true
    let lever = signalStation(g, x0 + 2, channel: 5)
    let (v, c) = gunPost(g, x0 + 10)
    v.parts[PartCell(dx: 1, dy: 1)] = .receiver
    v.recompute(keepAnchor: true)
    v.channel = 5
    v.gunMode[c] = GunMode.signal.rawValue
    run(g, 1.0)
    check(shotsFrom(g, v) == 0, "a gun set to fire on a signal is quiet while its channel is off")
    pull(g, lever)
    run(g, 0.6)
    check(shotsFrom(g, v) > 0, "and fires while it is on")
}

print("== the vehicle sensor")
do {
    let (g, x0) = runway()
    let px = x0 + 10
    let bat = put(g, px + 10, 99, .battery)!
    bat.charge = 600
    let vs = put(g, px + 8, 97, .vehicleSensor)!
    vs.param = 3
    put(g, px + 10, 97, .lampOff)
    wire(g, 0, px + 8, 97, px + 10, 97); wire(g, 0, px + 10, 97, px + 10, 99)
    wire(g, 1, px + 8, 97, px + 10, 97)
    run(g, 1.0)
    check(g.world.tile(px + 10, 97) == .lampOff, "with no vehicle near, its lamp stays dark")
    let v = car(g, engines: 1, left: px + 4, extra: [])
    run(g, 1.0)
    let lit = g.world.tile(px + 10, 97) == .lampOn
    check(lit, "a car beside it lights the lamp")
    v.placeBox(left: v.b.left + 40, bottom: 100)
    v.updateBox()
    run(g, 1.0)
    check(lit && g.world.tile(px + 10, 97) == .lampOff, "the car gone, dark again")
}

print("== receivers saved")
do {
    let (g, x0) = runway()
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil)])
    v.channel = 6
    v.radioAct = RadioAct.back.rawValue
    let r = Vehicle.restore(v.save())
    check(r.channel == 6 && r.radioAct == RadioAct.back.rawValue, "a receiver's channel and what it does are saved")
}


// ---------------------------------------------------------------- F. the Logic Studio and the signal channels
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prphys6-" + String(Int.random(in: 1000...999999)), isDirectory: true)
func lnode(_ op: LOp, _ f: (inout LNode) -> Void = { _ in }) -> LNode { var n = LNode(op); f(&n); return n }
func lscript(_ id: String, _ e: LEvent, _ blocks: [LNode], _ f: (inout ModScript) -> Void = { _ in }) -> ModScript {
    var s = ModScript(); s.id = id; s.name = id; s.event = e; s.blocks = blocks; f(&s); return s
}

print("== the Logic Studio and the signal channels")
do {
    var p = ModPack()
    p.id = "sig"; p.name = "Signals"
    p.variables = ["heard", "seen"]
    p.scripts = [
        lscript("start", .worldStart, [lnode(.setChannel) { $0.a = 2; $0.b = 1 }]),
        lscript("hear", .channelOn, [lnode(.setVar) { $0.s = "heard"; $0.args = [LExpr(1)] }]) { $0.ev = 3 },
        lscript("look", .every, [lnode(.setVar) { $0.s = "seen"; var e = LExpr(op: .channel); e.v = 5; $0.args = [e] }]) { $0.ev = 0.25 },
    ]
    let rep = ModValidator.check(&p, known: [:])
    check(!rep.fatal && p.scripts.allSatisfy { $0.enabled }, "a mod with signal scripts passes its checks")
    ModRuntime.activate([p], world: nil)
    let (g, x0) = runway()
    g.modInfo = ModRuntime.shared.worldInfo()
    func lv(_ k: String) -> Double { return g.logicVars["sig:" + k] ?? -1 }
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil)])
    v.channel = 2
    v.radioAct = RadioAct.forward.rawValue
    let a0 = v.px
    run(g, 2.0)
    check(v.px > a0 + 3, "a script's 'set a signal channel' turns channel 2 on: a car listening to it drives off (\(f1(v.px - a0)) blocks)")
    let heard0 = lv("heard")
    let lever = signalStation(g, x0 + 2, channel: 3)
    pull(g, lever)
    run(g, 0.5)
    check(heard0 != 1 && lv("heard") == 1, "when a lever turns channel 3 on, a script waiting for it runs")
    let seen0 = lv("seen")
    let lever5 = signalStation(g, x0 + 12, channel: 5)
    pull(g, lever5)
    run(g, 0.6)
    check(seen0 == 0 && lv("seen") == 1, "a script reads channel 5: off, then on once a lever turns it on")
    let data = try! JSONEncoder().encode(g.makeSave())
    let s2 = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(s2, settings: Settings())
    check(g2.logicChannels[1] && !g2.logicChannels[2], "the channels a script set are saved")
    ModRuntime.activate([], world: nil)
}


// ---------------------------------------------------------------- G. a mod's own gun
func gunMod(rate: Double, damage: Double) -> ModPack {
    var p = ModPack()
    p.id = "mg"; p.name = "Mod Guns"
    var spark = ModProjectile(); spark.id = "spark"; spark.name = "Spark"; spark.color = 0x40E0FF
    p.projectiles = [spark]
    var zap = ModBlock(); zap.id = "zapper"; zap.name = "Zapper"; zap.vehRole = .machineGun
    zap.shot = "spark"; zap.shotDamage = damage; zap.fireRate = rate
    var plain = ModBlock(); plain.id = "plain"; plain.name = "Plain Gun"; plain.vehRole = .machineGun
    p.blocks = [zap, plain]
    return p
}
/// A gun post whose gun is a mod block (by its key), driven, firing for a second; the shots it fired
func modGunShots(_ key: String) -> [Projectile] {
    let (g, x0) = runway()
    g.pauseMobs = true
    let tile: Tile = ModRuntime.shared.tileForKey[key]!
    let v = build(g, [(0, 0, .frame, nil), (1, 0, .frame, nil), (2, 0, .frame, nil), (0, -1, .seat, nil), (1, -1, .steering, nil), (2, -1, .autoGun, tile)], left: Double(x0 + 20), bottom: 100)
    g.inVehicle = v; v.rider = true
    let m = v.cellCenter(PartCell(dx: 2, dy: -1))
    var seen: [Int: Projectile] = [:]
    var t = 0.0
    while t < 1.0 {
        g.useHeld = true; g.aimX = m.0 + 30; g.aimY = m.1; g.aimValid = true
        g.tick(dt60); g.hunger = 20; t += dt60
        for p in g.projectiles where p.owner >= 2_000_000 { seen[p.uid] = p }
    }
    g.useHeld = false
    return Array(seen.values)
}

print("== a mod's gun fires the mod's own shot")
do {
    var p = gunMod(rate: 4, damage: 9)
    let rep = ModValidator.check(&p, known: [:])
    check(!rep.fatal, "a mod with a gun block passes its checks")
    ModRuntime.activate([p], world: nil)
    let si: Int = ModRuntime.shared.shotIndex["mg:spark"] ?? -9
    let shots = modGunShots("mg:zapper")
    check(!shots.isEmpty && shots.allSatisfy { $0.mod == si && abs($0.dmg - 9) < 0.01 }, "its gun block fires the mod's spark, as hard as the mod says (\(shots.count) shots)")
    check(shots.count >= 3 && shots.count <= 5, "four shots a second, as the mod says (\(shots.count) in a second)")
    let plain = modGunShots("mg:plain")
    check(plain.count >= 6 && plain.allSatisfy { $0.mod < 0 }, "a gun block with no shot of its own fires the game's bullets (\(plain.count) in a second)")
    ModRuntime.activate([], world: nil)
}

print("== a mod gun's numbers")
do {
    var p = gunMod(rate: 1000, damage: 99999)
    _ = ModValidator.check(&p, known: [:])
    let z = p.blocks[0]
    check(z.fireRate <= 30 && z.fireRate > 0 && z.shotDamage <= 500, "a gun's rate and damage are kept within limits (\(z.fireRate), \(z.shotDamage))")
    let kept: ModBlock = try! JSONDecoder().decode(ModBlock.self, from: try! JSONEncoder().encode(gunMod(rate: 4, damage: 9).blocks[0]))
    check(kept.shot == "spark" && kept.fireRate == 4 && kept.shotDamage == 9, "a gun block's shot, rate and damage are kept in the mod file")
    let old: ModBlock = try! JSONDecoder().decode(ModBlock.self, from: "{\"id\":\"old\",\"name\":\"Old\"}".data(using: .utf8)!)
    check(old.shot.isEmpty && old.fireRate == 0 && old.shotDamage == 0 && old.shotSpeed == 0, "a block from an older mod has none of its own")
}


// ---------------------------------------------------------------- H. setting a receiver up
print("== the receiver's panel")
do {
    let (g, x0) = runway()
    let v = car(g, engines: 1, left: x0 + 30, extra: [(3, -1, .receiver, nil)])
    g.updateInputGate()
    check(!g.inputBlocked, "(the controls are free)")
    g.interactVehicle(v, PartCell(dx: 3, dy: -1))
    g.updateInputGate()
    let opened = g.showRadio && g.radioEdit == v.id && g.inputBlocked
    check(opened, "tapping a receiver opens its panel (which takes the controls)")
    g.setRadio(channel: 7, act: .route)
    check(v.channel == 7 && v.radioAct == RadioAct.route.rawValue, "the panel sets its channel and what it does")
    g.closeRadio()
    g.updateInputGate()
    check(opened && !g.showRadio && !g.inputBlocked, "DONE closes it")
}

print("phys6: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
