import SwiftUI
import Foundation
// Phase 4 of the overhaul, vehicles of every kind: planes, helicopters, airships, tanks and trucks from
// their kits, the flight model (lift from speed, stalls, weight that keeps a design on the ground), blocks
// built onto vehicles, the assembler, weapons and damage, turning round, the autopilot, saves, and a mod
// block working as a part. Everything through the game's own code.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }

/// A long flat stone runway at row 100 (air above), nothing spawning, daytime, calm air
func runway(mode: GameMode = .creative) -> (Game, Int) {
    let g = Game(mode: mode, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false; g.pauseSpawning = true; g.settings.weatherOn = false; g.mobs.removeAll()
    g.godMode = true
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x) + 300, radius: 26)
    for x in x0...(x0 + 760) {
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
/// Drives (flies) for `secs` with the stick at (sx, up); returns the highest point above the runway
@discardableResult
func fly(_ g: Game, _ v: Vehicle, _ secs: Double, _ sx: Double, _ up: Double) -> Double {
    g.inVehicle = v; v.rider = true
    var t = 0.0
    var best = 0.0
    while t < secs {
        g.stick = sx; g.stickY = -up
        g.tick(1.0 / 60.0); g.hunger = 20; t += 1.0 / 60.0
        best = max(best, 100.0 - v.b.y)
    }
    g.stick = 0; g.stickY = 0
    return best
}
func height(_ v: Vehicle) -> Double { return 100.0 - v.b.y }

// ---------------------------------------------------------------- A. planes
print("== planes")
do {
    let (g, x0) = runway()
    let v = kit(g, .planeKit, x0 + 20, 100)
    let ck = g.vehicleCheck(v)
    check(ck.ready && ck.title == "PLANE", "the plane kit is a ready PLANE (\(ck.lines.joined(separator: ", ")))")
    fly(g, v, 1.0, 0, 0)
    let groundY = v.b.y
    // full throttle along the runway, then the stick back to lift off
    fly(g, v, 2.5, 1, 0)
    let rollSpeed = v.speed
    check(height(v) < 0.6, "on the ground, at full throttle it gathers speed along the runway (\(f1(rollSpeed)) blocks/s after 2.5 s)")
    var off = -1.0
    var t = 0.0
    g.inVehicle = v; v.rider = true
    while t < 8.0 {
        g.stick = 1; g.stickY = -0.6
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if off < 0 && v.contacts == 0 && height(v) > 1.5 { off = v.px - Double(x0 + 20) }
    }
    check(off > 0 && height(v) > 6, "with the stick back it lifts off (after \(f1(off)) blocks of runway) and climbs (\(f1(height(v))) blocks up)")
    // hands off: it holds its attitude and keeps flying
    let h0 = height(v)
    fly(g, v, 6.0, 1, 0)
    check(height(v) > h0 - 3 && v.contacts == 0, "hands off at full throttle it flies on (height \(f1(h0)) -> \(f1(height(v))), speed \(f1(v.speed)))")
    check(v.speed > 13 && v.speed < 30, "it cruises at a plane's speed (\(f1(v.speed)) blocks/s; cars top out at 17)")
    // turning round in flight (then the stick goes the way it now flies)
    let vx0 = v.vx
    g.turnVehicle()
    fly(g, v, 1.8, 1, 0)
    check(vx0 > 5 && v.vx < -5 && v.contacts == 0 && v.turnT == 0, "TURN in flight: from \(f1(vx0)) to \(f1(v.vx)) blocks/s across the screen, still flying")
    fly(g, v, 3.0, -1, 0)
    check(v.contacts == 0 && v.speed > 10 && v.vx < 0, "after the turn it flies on the other way (speed \(f1(v.speed)), height \(f1(height(v))))")
    // throttle off and nose up: it slows, stalls and loses height
    var stalled = false
    var sink = 0.0
    g.inVehicle = v; v.rider = true
    t = 0
    let hs = height(v)
    while t < 6.0 {
        g.stick = 0.05; g.stickY = -1
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if v.stall { stalled = true }
        sink = max(sink, v.vy)
    }
    check(v.speed < 13 && (stalled || sink > 2.0), "throttle off and stick back: it slows to \(f1(v.speed)) and sinks (stall seen: \(stalled), fastest sink \(f1(sink)), height \(f1(hs)) -> \(f1(height(v))))")
    _ = groundY
}
do {
    // weight matters: the same plane with four blocks of stone on board never leaves the ground
    let (g, x0) = runway()
    let v = kit(g, .planeKit, x0 + 20, 100)
    let m0 = v.mass
    for (dx, dy) in [(1, 0), (2, 0), (3, 0), (5, 0)] {
        v.parts[PartCell(dx: dx, dy: dy)] = .block
        v.blocks[PartCell(dx: dx, dy: dy)] = .stone
    }
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(x0 + 20), bottom: 100)
    check(abs(v.mass - (m0 + 10.0)) < 0.01, "four stone blocks add their weight (mass \(f1(m0)) -> \(f1(v.mass)))")
    let ck = g.vehicleCheck(v)
    check(!ck.ready, "its checklist says the wings are too small for the weight (\(ck.hint))")
    fly(g, v, 1.0, 0, 0)
    fly(g, v, 4.0, 1, 0)
    let best = fly(g, v, 10.0, 1, 0.8)
    check(best < 1.5, "at full throttle with the stick back it cannot take off (highest \(f1(best)) blocks, speed \(f1(v.speed)))")
}
do {
    // a jet is faster than a propeller
    let (g, x0) = runway()
    let p = kit(g, .planeKit, x0 + 20, 100)
    fly(g, p, 1, 0, 0)
    fly(g, p, 3, 1, 0)
    fly(g, p, 4, 1, 0.5)
    fly(g, p, 6, 1, 0)
    let propSpeed = p.speed
    let (g2, x2) = runway()
    let j = kit(g2, .planeKit, x2 + 20, 100)
    j.parts[PartCell(dx: 7, dy: 1)] = .frame
    j.parts[PartCell(dx: -1, dy: 1)] = .jet
    j.recompute(keepAnchor: false)
    j.placeBox(left: Double(x2 + 20), bottom: 100)
    j.fuel = j.fuelCapacity
    fly(g2, j, 1, 0, 0)
    fly(g2, j, 3, 1, 0)
    fly(g2, j, 4, 1, 0.5)
    fly(g2, j, 6, 1, 0)
    check(j.face[PartCell(dx: -1, dy: 1)]?.0 == -1, "the jet's exhaust faces out of its open end (backward, at the tail)")
    check(j.contacts == 0 && j.speed > propSpeed + 2, "the jet version flies faster (\(f1(j.speed)) against \(f1(propSpeed)) blocks/s)")
}

// ---------------------------------------------------------------- B. helicopters
print("== helicopters")
do {
    let (g, x0) = runway()
    let v = kit(g, .heliKit, x0 + 20, 100)
    let ck = g.vehicleCheck(v)
    check(ck.ready && ck.title == "HELICOPTER", "the helicopter kit is a ready HELICOPTER (\(ck.lines.joined(separator: ", ")))")
    fly(g, v, 1, 0, 0)
    fly(g, v, 2.5, 0, 1)
    check(height(v) > 4 && v.contacts == 0, "stick up: it lifts straight off (\(f1(height(v))) blocks up, drift \(f1(v.px - Double(x0 + 20) - 2.5)))")
    fly(g, v, 3, 0, 0)
    let h0 = height(v)
    let x1 = v.px
    var maxVy = 0.0
    g.inVehicle = v; v.rider = true
    for _ in 0..<240 { g.stick = 0; g.stickY = 0; g.tick(1.0 / 60.0); maxVy = max(maxVy, abs(v.vy)) }
    check(abs(height(v) - h0) < 1.5 && maxVy < 1.5 && abs(v.px - x1) < 4, "hands off it hovers (height \(f1(h0)) -> \(f1(height(v))), drift \(f1(v.px - x1)), fastest climb or sink \(f1(maxVy)))")
    fly(g, v, 4, 1, 0)
    check(v.vx > 8 && v.vx < 25 && v.angle > 0.05, "stick right: it tilts (\(f1(v.angle)) rad) and flies that way at \(f1(v.vx)) blocks/s")
    fly(g, v, 3, 0, 0)
    check(abs(v.vx) < 3, "let go: it brakes back to a hover (\(f1(v.vx)) blocks/s)")
    fly(g, v, 4, 0, -1)
    fly(g, v, 1, 0, 0)
    check(v.contacts > 0 && v.dmg.isEmpty && v.collective < 0.1, "stick down: it comes down and lands without a scratch")
}
do {
    // one engine is not enough for its weight
    let (g, x0) = runway()
    let v = kit(g, .heliKit, x0 + 20, 100)
    v.parts[PartCell(dx: 3, dy: 2)] = .frame
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(x0 + 20), bottom: 100)
    check(g.rotorMax(v) < v.mass * gravityG, "with one engine the rotor cannot lift its weight (\(f1(g.rotorMax(v))) against \(f1(v.mass * gravityG)))")
    fly(g, v, 1, 0, 0)
    let best = fly(g, v, 4, 0, 1)
    check(best < 0.8, "and it does not leave the ground (highest \(f1(best)))")
    check(!g.vehicleCheck(v).ready, "its checklist says so")
}
do {
    // without the tail rotor it cannot hold steady
    var spread: [Double] = []
    for tail in [true, false] {
        let (g, x0) = runway()
        let v = kit(g, .heliKit, x0 + 20, 100)
        if !tail {
            v.parts[PartCell(dx: 0, dy: 1)] = nil
            v.recompute(keepAnchor: false)
            v.placeBox(left: Double(x0 + 21), bottom: 100)
        }
        fly(g, v, 1, 0, 0)
        fly(g, v, 2.5, 0, 1)
        var worst = 0.0
        g.inVehicle = v; v.rider = true
        for _ in 0..<300 { g.stick = 0; g.stickY = 0; g.tick(1.0 / 60.0); worst = max(worst, abs(remainder(v.angle, 2 * Double.pi))) }
        spread.append(worst)
    }
    check(spread[1] > spread[0] * 1.5 + 0.05, "without a tail rotor it sways far more (\(f1(spread[1])) rad against \(f1(spread[0])))")
}

// ---------------------------------------------------------------- C. airships
print("== airships")
do {
    let (g, x0) = runway()
    let v = kit(g, .airshipKit, x0 + 20, 100)
    let ck = g.vehicleCheck(v)
    check(ck.ready && ck.title == "AIRSHIP", "the airship kit is a ready AIRSHIP (\(ck.lines.joined(separator: ", ")))")
    fly(g, v, 1, 0, 0)
    fly(g, v, 6, 0, 1)
    check(height(v) > 3 && v.heat > 0.5, "stick up: the burners heat the balloon and it rises (\(f1(height(v))) blocks, heat \(f1(v.heat)))")
    fly(g, v, 8, 0, 0)
    let h0 = height(v)
    fly(g, v, 4, 0, 0)
    check(abs(height(v) - h0) < 1.5 && abs(v.vy) < 0.6, "hands off it floats at its height (\(f1(h0)) -> \(f1(height(v))))")
    let px = v.px
    fly(g, v, 6, 1, 0)
    check(v.px - px > 25 && v.vx < 20, "the propellers move it along (\(f1(v.px - px)) blocks in 6 s, \(f1(v.vx)) blocks/s)")
    var fastest = 0.0
    g.inVehicle = v; v.rider = true
    for _ in 0..<(60 * 12) { g.stick = 0; g.stickY = 1; g.tick(1.0 / 60.0); fastest = max(fastest, v.vy) }
    g.stickY = 0
    fly(g, v, 2, 0, 0)
    check(v.contacts > 0 && v.dmg.isEmpty, "stick down: it cools, comes down (at most \(f1(fastest)) blocks/s) and lands in one piece (\(v.dmg.count) parts hurt, \(v.parts.count) cells)")
}
do {
    // too little balloon for the weight
    let (g, x0) = runway()
    let v = kit(g, .airshipKit, x0 + 20, 100)
    // keep four envelopes, just over the burners
    for x in 1...6 { v.parts[PartCell(dx: x, dy: 0)] = nil }
    for x in 0...7 where x != 3 && x != 4 { v.parts[PartCell(dx: x, dy: 1)] = nil }
    for x in 1...6 where x != 3 && x != 4 { v.parts[PartCell(dx: x, dy: 2)] = nil }
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(x0 + 20), bottom: 100)
    check(g.balloonMax(v) < v.mass * gravityG, "a balloon of \(v.envelopes) envelopes cannot lift \(f1(v.mass)) mass")
    fly(g, v, 1, 0, 0)
    let best = fly(g, v, 10, 0, 1)
    check(best < 0.8, "full heat and it stays on the ground (highest \(f1(best)))")
}

// ---------------------------------------------------------------- D. tanks and trucks
print("== tanks and trucks")
do {
    let (g, x0) = runway(mode: .survival)
    let tank = kit(g, .tankKit, x0 + 20, 100)
    let ck = g.vehicleCheck(tank)
    check(tank.tracks == 6 && ck.title == "TANK", "the tank kit is a TANK on six tracks (\(ck.lines.joined(separator: ", ")))")
    fly(g, tank, 1, 0, 0)
    let tx = tank.px
    fly(g, tank, 4, 1, 0)
    let tankSpeed = (tank.px - tx) / 4.0
    let (gt, xt) = runway()
    let truck = kit(gt, .truckKit, xt + 20, 100)
    fly(gt, truck, 1, 0, 0)
    let rx = truck.px
    fly(gt, truck, 4, 1, 0)
    let truckSpeed = (truck.px - rx) / 4.0
    check(tankSpeed > 3 && tankSpeed < 9 && truckSpeed > tankSpeed + 3, "the heavy tank is slow (\(f1(tankSpeed)) blocks/s), the truck quicker (\(f1(truckSpeed)))")
    // a slope rising one block every two columns, eight blocks high
    fly(g, tank, 0.5, 0, 0)
    let sx = Int(floor(tank.b.right)) + 3
    for i in 0..<16 { let h = i / 2 + 1; for y in (100 - h)..<100 { g.world.set(sx + i, y, .stone) } }
    for x in (sx + 16)...(sx + 50) { for y in 92..<100 { g.world.set(x, y, .stone) } }
    fly(g, tank, 11, 1, 0)
    check(tank.b.y < 92.3, "the tracks take the heavy tank up a 1-in-2 slope eight blocks high (bottom \(f1(tank.b.y)))")
    // the cannon: aim, fire, a shell that bursts, the recoil, gunpowder used
    g.inv.slots[5] = Stack(item: .mat(.gunpowder), count: 3)
    fly(g, tank, 1, 0, 0)
    tank.asleep = false
    g.inVehicle = tank; tank.rider = true
    let wallX = Int(floor(tank.px)) + 14
    for y in 80..<98 { g.world.set(wallX, y, .stone) }
    g.aimX = Double(wallX); g.aimY = tank.py - 0.5; g.aimValid = true
    var fired = false
    var burst = false
    let vx0 = tank.vx
    var minVX = 0.0
    for _ in 0..<150 {
        g.useHeld = true; g.aimX = Double(wallX); g.aimY = tank.py - 0.5; g.aimValid = true
        g.stick = 0; g.stickY = 0
        let before = g.projectiles.count
        g.tick(1.0 / 60.0)
        if g.projectiles.contains(where: { $0.kind == .shell }) { fired = true }
        if fired && !g.projectiles.contains(where: { $0.kind == .shell }) && before > 0 { burst = true }
        minVX = min(minVX, tank.vx - vx0)
    }
    g.useHeld = false
    check(fired && burst, "the attack stick fires a cannon shell that bursts on the wall")
    check(minVX < -0.05, "the cannon kicks the tank back (\(String(format: "%.2f", minVX)) blocks/s)")
    check(g.inv.total(.mat(.gunpowder)) < 3, "each shell uses gunpowder (\(g.inv.total(.mat(.gunpowder))) of 3 left)")
}

// ---------------------------------------------------------------- E. blocks on vehicles, the assembler
print("== blocks on vehicles")
do {
    let (g, x0) = runway()
    let v = kit(g, .carKit, x0 + 20, 100)
    fly(g, v, 0.5, 0, 0)
    g.inVehicle = nil; v.rider = false
    g.pb.x = v.b.x; g.pb.y = 100
    let m0 = v.mass
    g.inv.slots[0] = Stack(item: .block(.stone), count: 4)
    g.setSel(0)
    check(g.canBuildOnVehicle, "holding a block near a vehicle offers ON VEHICLE")
    g.toggleVehicleBuild()
    // tap just above the seat
    let seat = v.parts.first { $0.value == .seat }!.key
    let spot = v.cellCenter(PartCell(dx: seat.dx, dy: seat.dy - 1))
    g.aimX = spot.0; g.aimY = spot.1; g.aimValid = true
    g.placeCD = 0
    g.usePlaceBlock(.stone, 1.0 / 60.0)
    check(v.blocks[PartCell(dx: seat.dx, dy: seat.dy - 1)] == .stone && abs(v.mass - m0 - 2.5) < 0.01, "a stone block goes onto the car as one of its cells, with its weight (mass \(f1(m0)) -> \(f1(v.mass)))")
    check(g.world.tile(Int(floor(spot.0)), Int(floor(spot.1))) == .air, "and not into the world")
    check(!g.vehicleGhosts().isEmpty, "green squares show where else a block can go")
    g.toggleVehicleBuild()
    // it travels with the car
    let bx = v.cellCenter(PartCell(dx: seat.dx, dy: seat.dy - 1)).0
    fly(g, v, 2, 1, 0)
    check(v.cellCenter(PartCell(dx: seat.dx, dy: seat.dy - 1)).0 - bx > 5, "it moves with the car")
    // a torch built on lights the way at night
    v.parts[PartCell(dx: seat.dx + 1, dy: seat.dy - 1)] = .block
    v.blocks[PartCell(dx: seat.dx + 1, dy: seat.dy - 1)] = .torch
    v.recompute(keepAnchor: true)
    g.timeOfDay = 0.8
    g.light.valid = false
    fly(g, v, 0.3, 0, 0)
    let tc = v.cellCenter(PartCell(dx: seat.dx + 1, dy: seat.dy - 1))
    check(g.light.level(Int(floor(tc.0)), Int(floor(tc.1))).1 >= 10, "a torch built onto it gives light where it goes")
    g.timeOfDay = 0.25
}
do {
    // a raft of planks floats, one of stone sinks
    var depth: [Double] = []
    for t in [Tile.planks, .stone] {
        let (g, x0) = runway()
        for x in (x0 + 60)...(x0 + 90) { for y in 90..<100 { g.world.set(x, y, .water) } ; for y in 100..<104 { g.world.set(x, y, .water) } }
        for x in (x0 + 60)...(x0 + 90) { g.world.set(x, 104, .stone) }
        let v = Vehicle(id: g.newID(), first: .block, x: 0, y: 0)
        v.parts.removeAll()
        for x in 0..<5 { v.parts[PartCell(dx: x, dy: 0)] = .block; v.blocks[PartCell(dx: x, dy: 0)] = t }
        v.recompute(keepAnchor: false)
        v.placeBox(left: Double(x0 + 72), bottom: 91)
        g.vehicles.append(v)
        for _ in 0..<360 { g.tick(1.0 / 60.0) }
        depth.append(v.b.y)
    }
    check(depth[0] < 92.5 && depth[1] > 101, "a raft of planks floats at the surface (bottom \(f1(depth[0]))), one of stone sinks (\(f1(depth[1])))")
}
do {
    // the assembler: a structure built in the world becomes one vehicle, and goes back
    let (g, x0) = runway()
    g.inv.slots[0] = Stack(item: .gadget(.assembler), count: 1)
    g.setSel(0)
    let bx = x0 + 30
    for x in bx..<(bx + 6) { for y in 97..<100 { g.world.set(x, y, .planks); g.world.setBuilt(x, y, true) } }
    g.world.set(bx + 2, 96, .chest); g.world.setBuilt(bx + 2, 96, true)
    g.world.setChestItems(bx + 2, 96, [Stack(item: .mat(.ironBar), count: 5)])
    g.pb.x = Double(bx) - 1.5; g.pb.y = 100
    g.aimX = Double(bx) + 0.5; g.aimY = 99.5; g.aimValid = true
    g.useCD = 0
    g.useAssembler(true)
    let v = g.vehicles.last
    check(v != nil && v!.parts.count == 19 && v!.blocks.count == 19, "tapped with the assembler, 19 built blocks become one vehicle (\(v?.parts.count ?? 0) cells)")
    check(g.world.tile(bx, 99) == .air && g.world.tile(bx + 2, 96) == .air, "and leave the world")
    let chestCell = v!.blocks.first { $0.value == .chest }!.key
    let k = g.cargoSpot(v!, chestCell)
    check(g.world.chestItems(k.x, k.y).first?.count == 5, "the chest's things travel with it")
    check(abs(v!.mass - (18 * 0.6 + 1.0)) < 0.01, "its mass is its blocks' weight (\(f1(v!.mass)))")
    // add a cockpit and wheels and it is a car made of planks... park it again and take it apart
    for _ in 0..<60 { g.tick(1.0 / 60.0) }
    g.useCD = 0
    g.aimX = v!.b.x; g.aimY = v!.b.y - 0.5
    g.useAssembler(true)
    check(!g.vehicles.contains { $0 === v! } && g.world.tile(bx, 99) == .planks && g.world.isBuilt(bx, 99), "tapped again, it is taken apart: the blocks are back in place")
    check(g.world.chestItems(bx + 2, 96).first?.count == 5, "the chest is back with its things")
}

// ---------------------------------------------------------------- F. damage
print("== damage")
do {
    let (g, x0) = runway(mode: .survival)
    let v = kit(g, .planeKit, x0 + 20, 100)
    fly(g, v, 0.5, 0, 0)
    g.inVehicle = nil; v.rider = false
    let wing = PartCell(dx: 2, dy: 1)
    let at = v.cellCenter(wing)
    // a monster's arrow comes down on the wing
    var p = Projectile(kind: .arrow, x: at.0, y: at.1 - 3, vx: 0, vy: 30, dmg: 8, fromPlayer: false, gravity: 0)
    p.source = DamageSource(kind: .mob, id: 99, faction: .hostile)
    p.uid = g.newID()
    g.projectiles.append(p)
    for _ in 0..<20 { g.tick(1.0 / 60.0) }
    check((v.dmg[wing] ?? 0) >= 7.9, "a monster's arrow damages the part it hits (\(f1(v.dmg[wing] ?? 0)) of \(f1(vehicleCellHP(v, wing, .wing))))")
    // the player's own shots pass their vehicles
    var q = Projectile(kind: .arrow, x: at.0, y: at.1 - 3, vx: 0, vy: 30, dmg: 8, fromPlayer: true, gravity: 0)
    q.source = .player
    q.uid = g.newID()
    g.projectiles.append(q)
    let d0 = v.dmg[wing] ?? 0
    for _ in 0..<20 { g.tick(1.0 / 60.0) }
    check((v.dmg[wing] ?? 0) == d0, "the player's own arrows pass through")
    // break the tail off: it becomes a wreck of its own
    let n0 = g.vehicles.count
    let parts0 = v.parts.count
    g.damageVehicle(v, PartCell(dx: 1, dy: 1), 200, at.0, at.1)
    check(v.parts[PartCell(dx: 1, dy: 1)] == nil && g.vehicles.count == n0 + 1 && v.parts.count < parts0 - 2, "breaking the frame behind the wings drops the tail off as a wreck (\(g.vehicles.count - n0) wreck, \(parts0) -> \(v.parts.count) cells)")
    if let w = g.vehicles.last, w !== v {
        let y0 = w.py
        for _ in 0..<60 { g.tick(1.0 / 60.0) }
        check(!w.hasSeat && w.py >= y0 - 0.01, "the wreck has no seat and falls with its own physics")
    }
    // a blast near the cockpit damages several parts and shoves the plane
    let c = v.cellCenter(PartCell(dx: 4, dy: 0))
    v.asleep = false
    let vx0 = v.vx
    g.explode(c.0 + 1.5, c.1, radius: 3, power: 12, source: .environment, breakBlocks: false)
    let hurt = v.dmg.filter { $0.value > 0 }.count
    check(hurt >= 3 && abs(v.vx - vx0) > 0.1, "a blast damages \(hurt) parts and pushes the plane")
    // mending
    g.inv.slots[0] = Stack(item: .mat(.ironBar), count: 2)
    g.setSel(0)
    let worst = v.dmg.max { $0.value < $1.value }!.key
    g.interactVehicle(v, worst)
    check(v.dmg[worst] == nil && g.inv.total(.mat(.ironBar)) == 1, "an iron bar mends a damaged part")
}
do {
    // a hard crash breaks what hits the ground; an ordinary landing does not
    let (g, x0) = runway()
    let v = kit(g, .truckKit, x0 + 20, 55)
    let n0 = v.parts.count
    for _ in 0..<180 { g.tick(1.0 / 60.0) }
    check(!v.dmg.isEmpty || v.parts.count < n0, "a truck dropped 45 blocks is damaged where it hits (\(v.dmg.count) parts hurt, \(n0) -> \(v.parts.count) cells)")
    let soft = kit(g, .truckKit, x0 + 60, 96)
    for _ in 0..<120 { g.tick(1.0 / 60.0) }
    check(soft.dmg.isEmpty, "dropped 4 blocks, nothing breaks")
    let (g2, x2) = runway()
    g2.settings.vehicleDamage = false
    let w = kit(g2, .truckKit, x2 + 20, 55)
    for _ in 0..<180 { g2.tick(1.0 / 60.0) }
    check(w.dmg.isEmpty && w.parts.count == n0, "with vehicle damage switched off in Settings, nothing breaks")
}

// ---------------------------------------------------------------- G. the autopilot, saves
print("== autopilot and saves")
do {
    let (g, x0) = runway()
    let v = kit(g, .heliKit, x0 + 20, 100)
    v.parts[PartCell(dx: 5, dy: 2)] = .autopilot
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(x0 + 20), bottom: 100)
    fly(g, v, 1, 0, 0)
    fly(g, v, 2.5, 0, 1)
    fly(g, v, 2, 0, 0)
    g.inVehicle = v; v.rider = true
    g.markWaypoint()
    fly(g, v, 4, 1, 0)
    fly(g, v, 2, 0, 0)
    g.markWaypoint()
    check(v.route.count == 2, "MARK records two route points")
    g.cycleAutopilot()
    check(v.auto == 1, "AUTO: cruise")
    let h0 = height(v)
    fly(g, v, 5, 0, 0)
    check(abs(height(v) - h0) < 2, "cruise holds the height (\(f1(h0)) -> \(f1(height(v))))")
    g.cycleAutopilot()
    check(v.auto == 2, "AUTO again: route")
    // nobody aboard: it flies its route by itself
    g.inVehicle = nil; v.rider = false
    let a = v.route[0]
    let b = v.route[1]
    var reachedA = false
    var reachedB = false
    for _ in 0..<(60 * 25) {
        g.pb.x = v.px; g.pb.y = v.py + 2
        g.tick(1.0 / 60.0)
        if abs(v.px - a.x) < 3 && abs(v.py - a.y) < 3 { reachedA = true }
        if reachedA && abs(v.px - b.x) < 3 && abs(v.py - b.y) < 3 { reachedB = true }
    }
    check(reachedA && reachedB, "with nobody aboard it flies its marked route (reached the first point: \(reachedA), then the second: \(reachedB))")
    // saved and loaded with its blocks, damage and route
    v.parts[PartCell(dx: 5, dy: 1)] = .block
    v.blocks[PartCell(dx: 5, dy: 1)] = .brick
    v.dmg[PartCell(dx: 4, dy: 1)] = 7
    v.recompute(keepAnchor: true)
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    let v2 = g2.vehicles.first { $0.id == v.id }
    check(v2?.blocks[PartCell(dx: 5, dy: 1)] == .brick && v2?.dmg[PartCell(dx: 4, dy: 1)] == 7 && v2?.route.count == 2 && v2?.auto == 2, "after saving and loading: its blocks, damage, route and autopilot are kept")
    check(v2?.parts.count == v.parts.count && abs((v2?.mass ?? 0) - v.mass) < 0.01, "and its parts and mass")
}

// ---------------------------------------------------------------- H. a mod block as a vehicle part
print("== mod parts")
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aero-mods-\(getpid())")
    try? FileManager.default.removeItem(at: dir)
    ModStore.overrideDir = dir
    var pack = ModPack()
    pack.id = "skyworks"
    pack.name = "Skyworks"
    var b = ModBlock()
    b.id = "silkwing"
    b.name = "Silk Wing"
    b.hardness = 0.5
    b.vehRole = .wing
    b.vehMass = 0.2
    b.vehPower = 1.5
    b.art = ModPixels(w: 8, h: 8)
    pack.blocks = [b]
    var checked = pack
    _ = ModValidator.check(&checked, known: [:])
    check(checked.blocks[0].vehRole == .wing && checked.blocks[0].vehPower == 1.5, "a mod block can be made to work as a wing (strength kept)")
    var wild = b
    wild.vehPower = 99
    wild.vehMass = -4
    var c2 = pack
    c2.blocks = [wild]
    _ = ModValidator.check(&c2, known: [:])
    check(c2.blocks[0].vehPower <= 4 && c2.blocks[0].vehMass >= 0, "its strength and mass are kept within limits (\(c2.blocks[0].vehPower), \(c2.blocks[0].vehMass))")
    let json = try! JSONEncoder().encode(checked)
    let again = try! JSONDecoder().decode(ModPack.self, from: json)
    check(again.blocks[0].vehRole == .wing && again.blocks[0].vehMass == 0.2, "and saved in the mod file")
    // in a world with the mod: built onto a plane it lifts like a stronger wing
    let (g, x0) = runway()
    ModRuntime.activate([checked], world: nil)
    let tile: Tile? = ModRuntime.shared.tile("skyworks:silkwing")
    check(tile != nil, "the mod block has a block number in the world")
    if let t = tile {
        let v = kit(g, .planeKit, x0 + 20, 100)
        fly(g, v, 0.5, 0, 0)
        g.inVehicle = nil; v.rider = false
        g.pb.x = v.b.x; g.pb.y = 100
        g.inv.slots[0] = Stack(item: .block(t), count: 1)
        g.setSel(0)
        g.vehicleBuild = true
        let spot = v.cellCenter(PartCell(dx: 1, dy: 0))
        g.aimX = spot.0; g.aimY = spot.1; g.aimValid = true
        g.placeCD = 0
        g.usePlaceBlock(t, 1.0 / 60.0)
        let c = PartCell(dx: 1, dy: 0)
        check(v.parts[c] == .wing && v.blocks[c] == t && v.wings == 4, "built onto a plane, it is one more wing with its own look")
        check(abs((v.boost[c] ?? 1) - 1.5) < 0.001 && abs(v.cellMass(c, .wing) - 0.2) < 0.001, "with the mod's strength (1.5) and mass (0.2)")
        g.vehicleBuild = false
    }
    ModRuntime.deactivate()
    try? FileManager.default.removeItem(at: dir)
}

print("aero: \(passes) passed, \(fails) failed")
