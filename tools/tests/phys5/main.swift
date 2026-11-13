import SwiftUI
import Foundation
// Phase 5 of the physics overhaul, joints, servos and mechs: what is built beyond a joint part becomes a
// section of its own; a hinge swings to its limit and stays together; a servo turns as a button says and
// back, and holds a load; a piston pushes a platform up with a crate on it; joints saved and loaded; a
// fast swing that does not fly apart; a mech set up by AUTO MECH that walks.

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

// ---------------------------------------------------------------- A. joints
print("== sections")
do {
    let (g, x0) = runway()
    let n0 = g.vehicles.count
    // a seat on the base, a servo on its right side at the top, an arm of three planks beyond it
    let v = machine(g, base([(1, -1, .seat, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    check(g.vehicles.count == n0 + 2 && v.joints.count == 1 && v.parts[PartCell(dx: 4, dy: 0)] == nil, "what is built beyond a servo becomes a section of its own, joined there")
    let arm = g.vehicleByID(v.joints[0].child)!
    check(arm.parts.count == 3 && arm.parentID == v.id && gap(g, v, v.joints[0]) < 0.01, "the arm: three cells, hanging from the base at the servo")
}

print("== a hinge")
do {
    let (g, x0) = runway()
    // the base six high, so the arm has room to swing down
    let v = machine(g, base([(1, -1, .seat, nil), (3, 0, .hinge, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)], high: 6), left: Double(x0 + 20), bottom: 100)
    let j = v.joints[0]
    physOnly(g, 3.0)
    let a = relAngle(g, v, j)
    check(a > 0.8 && a < 1.3 && gap(g, v, j) < 0.1, "an arm on a hinge swings down to the hinge's limit (\(f3(a)) radians) and stays on it (gap \(f3(gap(g, v, j))))")
}

print("== a servo")
do {
    let (g, x0) = runway()
    let v = machine(g, base([(1, -1, .seat, nil), (2, -1, .steering, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    v.joints[0].input = JointInput.buttonA.rawValue
    v.joints[0].lo = -1.0; v.joints[0].hi = 0.0
    v.joints[0].speed = 2.0
    g.inVehicle = v; v.rider = true
    physOnly(g, 1.5)
    let rest = relAngle(g, v, v.joints[0])
    check(abs(rest - (-1.0)) < 0.15, "with nothing pressed the servo holds its arm at its low end (\(f3(rest)))")
    g.jointButtons[0] = true
    physOnly(g, 1.5)
    let up = relAngle(g, v, v.joints[0])
    check(abs(up) < 0.15, "holding A it turns the arm up to the other end (\(f3(up)))")
    g.jointButtons[0] = false
    physOnly(g, 1.5)
    check(abs(relAngle(g, v, v.joints[0]) - (-1.0)) < 0.15, "letting go, back down")
    // a stone on the end of the arm: it still holds it up
    let arm = g.vehicleByID(v.joints[0].child)!
    arm.parts[PartCell(dx: 6, dy: -1)] = .block; arm.blocks[PartCell(dx: 6, dy: -1)] = .stone
    arm.recompute(keepAnchor: true)
    g.jointButtons[0] = true
    physOnly(g, 2.0)
    check(abs(relAngle(g, v, v.joints[0])) < 0.25 && gap(g, v, v.joints[0]) < 0.1, "with a block of stone on its end it still lifts and holds the arm (\(f3(relAngle(g, v, v.joints[0]))))")
    g.jointButtons[0] = false
    let r = Vehicle.restore(v.save())
    let ra = Vehicle.restore(arm.save())
    check(r.joints.count == 1 && r.joints[0].input == JointInput.buttonA.rawValue && ra.parentID == v.id, "the joint, its settings and the section it holds are saved")
}

print("== resting and waking")
do {
    let (g, x0) = runway()
    let v = machine(g, base([(1, -1, .seat, nil), (2, -1, .steering, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    v.joints[0].input = JointInput.buttonB.rawValue
    v.joints[0].lo = -1.0; v.joints[0].hi = 0.0
    g.inVehicle = v; v.rider = true
    physOnly(g, 3.0)
    let arm = g.vehicleByID(v.joints[0].child)!
    check(v.asleep && arm.asleep, "a machine standing still goes to rest as one (its arm out over the air too)")
    let before = relAngle(g, v, v.joints[0])
    physOnly(g, 1.0)
    check(abs(relAngle(g, v, v.joints[0]) - before) < 0.01, "and stays where it was")
    g.jointButtons[1] = true
    physOnly(g, 1.0)
    g.jointButtons[1] = false
    check(abs(relAngle(g, v, v.joints[0])) < 0.15 && !arm.asleep, "button B wakes it and raises the arm (\(f3(relAngle(g, v, v.joints[0]))))")
}

print("== a piston")
do {
    let (g, x0) = runway()
    // a piston on top of the base pushing up a post with a platform of five planks on it
    var cells = base([(1, -1, .piston, nil), (1, -2, .block, .planks), (1, -3, .block, .planks), (0, -3, .block, .planks), (2, -3, .block, .planks), (-1, -3, .block, .planks), (3, -3, .block, .planks)])
    cells.append((0, -1, .seat, nil))
    let v = machine(g, cells, left: Double(x0 + 20), bottom: 100)
    check(v.joints.count == 1 && v.joints[0].kind == 2, "a piston splits off the platform built on it")
    let plat = g.vehicleByID(v.joints[0].child)!
    let y0 = plat.py
    // a crate on the platform
    let box = crate(g, 1, left: plat.b.left + 1.0, bottom: plat.b.top - 0.02)
    v.joints[0].target = 3.0
    v.joints[0].hi = 3.0
    physOnly(g, 3.0)
    check(y0 - plat.py > 2.6 && plat.restOn == 0 && box.b.y < plat.b.top + 0.2 && abs(plat.angle) < 0.1, "it pushes the platform up three blocks (\(f1(y0 - plat.py))), level, with the crate still on it")
}

print("== a fast swing")
do {
    let (g, x0) = runway()
    let v = machine(g, base([(1, -1, .seat, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks), (7, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    v.joints[0].lo = -2.5; v.joints[0].hi = 2.5; v.joints[0].speed = 8; v.joints[0].strength = 4
    var worst = 0.0
    var fine = true
    for k in 0..<6 {
        v.joints[0].target = k % 2 == 0 ? 2.5 : -2.5
        var t = 0.0
        while t < 0.8 {
            g.updateVehicles(dt60); t += dt60
            worst = max(worst, gap(g, v, v.joints[0]))
            for w in g.vehicles where !(w.px.isFinite && w.vx.isFinite && w.angVel.isFinite) { fine = false }
        }
    }
    check(fine && worst < 0.35, "swung back and forth hard and fast, it stays together (the pivot opened \(f3(worst)) at most)")
}

print("== the stick, and through its own base")
do {
    let (g, x0) = runway()
    let v = machine(g, base([(1, -1, .seat, nil), (2, -1, .steering, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    v.joints[0].input = JointInput.stickUpDown.rawValue
    v.joints[0].lo = -2.6; v.joints[0].hi = 0.5
    g.inVehicle = v; v.rider = true
    g.pauseVehicles = false
    var t = 0.0
    while t < 1.0 { g.stickY = -1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.stickY = 0
    let up = relAngle(g, v, v.joints[0])
    check(up < -1.0, "stick up raises an arm that sticks out sideways (\(f3(up)))")
    t = 0
    while t < 2.0 { g.stickY = -1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.stickY = 0
    let over = relAngle(g, v, v.joints[0])
    check(abs(over - (-2.6)) < 0.12, "and on over the top of its own base to its limit (\(f3(over))): a machine's sections do not meet each other")
    settle(g, 0.5)
    check(abs(relAngle(g, v, v.joints[0]) - over) < 0.1, "let go, the stick leaves it where it is")
}

print("== building onto a machine")
do {
    let (g, x0) = runway()
    let v = machine(g, base([(1, -1, .seat, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks)]), left: Double(x0 + 20), bottom: 100)
    let arm = g.vehicleByID(v.joints[0].child)!
    // a second servo on the arm's end and a plank beyond it: an elbow
    arm.parts[PartCell(dx: 6, dy: 0)] = .servo
    arm.recompute(keepAnchor: true)
    g.splitJointSections(arm)
    check(arm.joints.isEmpty, "a servo with nothing beyond it yet is just a part")
    arm.parts[PartCell(dx: 7, dy: 0)] = .block; arm.blocks[PartCell(dx: 7, dy: 0)] = .planks
    arm.recompute(keepAnchor: true)
    g.splitJointSections(arm)
    let fore = arm.joints.first.flatMap { g.vehicleByID($0.child) }
    check(arm.joints.count == 1 && fore != nil && fore!.parentID == arm.id && v.joints.count == 1, "a block put beyond it makes a third section, hanging from the arm")
    // the same built the other way round, all at once, splits the same
    let (g2, y0) = runway()
    let w = machine(g2, base([(1, -1, .seat, nil), (3, 0, .servo, nil), (4, 0, .block, .planks), (5, 0, .block, .planks), (6, 0, .servo, nil), (7, 0, .block, .planks)]), left: Double(y0 + 20), bottom: 100)
    let a2 = g2.vehicleByID(w.joints[0].child)
    check(w.joints.count == 1 && a2 != nil && a2!.joints.count == 1 && a2!.parts.count == 3, "built all at once it splits the same way: base, arm, forearm")
    physOnly(g, 1.0)
    check(gap(g, v, v.joints[0]) < 0.05 && gap(g, arm, arm.joints[0]) < 0.05, "both joints hold")
    // the servo taken away: what hung from it is free
    v.parts[v.joints[0].cell] = nil
    v.recompute(keepAnchor: true)
    physOnly(g, 0.2)
    check(v.joints.isEmpty && arm.parentID == 0, "with its servo taken away the arm comes free")
}

print("== a crane on a truck")
do {
    let (g, x0) = runway()
    // a car with a mast on a servo: driven along, the mast stays up and on
    let v = car(g, engines: 2, left: x0 + 20, extra: [(3, -1, .servo, nil), (3, -2, .block, .planks), (3, -3, .block, .planks), (3, -4, .block, .planks)])
    g.splitJointSections(v)
    check(v.joints.count == 1, "the mast is a section of its own")
    let x1 = v.px
    var worst = 0.0
    g.inVehicle = v; v.rider = true; g.pauseVehicles = false
    var t = 0.0
    while t < 4.0 {
        g.stick = 1; g.tick(dt60); g.hunger = 20; t += dt60
        worst = max(worst, gap(g, v, v.joints[0]))
    }
    g.stick = 0
    check(v.px > x1 + 15 && worst < 0.1 && abs(relAngle(g, v, v.joints[0])) < 0.2, "driven along (\(f1(v.px - x1)) blocks) the mast stays up and on (gap \(f3(worst)) at most)")
}

// ---------------------------------------------------------------- B. a mech
print("== a mech")
do {
    let (g, x0) = runway()
    // a body of five frames with a cockpit; a leg under each end: hip servo, thigh, knee servo, shin, foot
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<5 { cells.append((x, 0, .frame, nil)) }
    cells.append((2, -1, .cockpit, nil)); cells.append((1, -1, .engine, nil))
    for lx in [0, 4] {
        cells.append((lx, 1, .servo, nil)); cells.append((lx, 2, .frame, nil)); cells.append((lx, 3, .servo, nil))
        cells.append((lx, 4, .frame, nil)); cells.append((lx, 5, .block, .planks))
    }
    let body = machine(g, cells, left: Double(x0 + 40), bottom: 100)
    var sections = 1
    var stack = [body]
    while let s = stack.popLast() { for j in s.joints { if let c = g.vehicleByID(j.child) { sections += 1; stack.append(c) } } }
    check(sections == 5, "hips and knees split it into five sections: the body, two thighs, two shins")
    physOnly(g, 2.0)
    check(body.speed < 0.5 && abs(body.angle) < 0.3, "it stands on its own legs")
    g.autoMech(body)
    var walkJoints = 0
    stack = [body]
    while let s = stack.popLast() { for j in s.joints { if j.input == JointInput.walk.rawValue { walkJoints += 1 }; if let c = g.vehicleByID(j.child) { stack.append(c) } } }
    check(walkJoints == 4, "AUTO MECH sets its four joints walking (hips and knees)")
    let x1 = body.px
    var tilt = 0.0
    g.inVehicle = body; body.rider = true
    var t = 0.0
    while t < 5.0 {
        g.stick = 1
        g.tick(dt60); g.hunger = 20; t += dt60
        tilt = max(tilt, abs(remainder(body.angle, 2 * Double.pi)))
    }
    g.stick = 0
    check(body.px > x1 + 6 && tilt < 0.4, "driven with the stick it walks along (\(f1(body.px - x1)) blocks in 5 s) without falling over on its two legs (tilts \(f3(tilt)) at most)")
    settle(g, 1.5)
    check(body.speed < 0.6 && abs(body.angle) < 0.2, "let go, it stops and stands")
    let x2 = body.px
    t = 0
    while t < 4.0 { g.stick = -1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.stick = 0
    check(body.px < x2 - 5 && abs(body.angle) < 0.4, "and walks back the other way (\(f1(x2 - body.px)) blocks)")
    let s = Vehicle.restore(body.save())
    check(abs(s.gait - body.gait) < 1e-9, "its stride is saved")
    // the driver gets out: it stands
    g.inVehicle = nil; body.rider = false
    settle(g, 2.0)
    check(abs(body.angle) < 0.3 && body.speed < 0.5, "with nobody at the controls it stands still")
}

print("phys5: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
