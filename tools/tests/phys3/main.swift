import SwiftUI
import Foundation
// Phase 3 of the physics overhaul, flight and water: liquids that flow (falling, spreading, filling a
// basin, pouring through a hole, levels saved and loaded, a still sea costing nothing), lava meeting water,
// a mod's own liquid floating on water, the bucket; boats floating on the air in their hull, a hole below
// the waterline flooding it, a submarine diving and rising on its ballast with a dry cabin; wings tilted,
// flaps, air brakes and tailplanes; the wind and the shelter of the land.

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


/// A dry stone box: floor at row 100, walls at x0 and x1, open above (rows 80...99 inside are air)
func basin(_ g: Game, _ x0: Int, _ x1: Int, floor: Int = 100, top: Int = 80) {
    for x in x0...x1 {
        for y in top...floor {
            g.world.set(x, y, (x == x0 || x == x1 || y == floor) ? .stone : .air)
        }
    }
}
/// The liquid in a stretch of cells, in blocks
func volume(_ g: Game, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ t: Tile = .water) -> Double {
    var v = 0.0
    for x in x0...x1 { for y in y0...y1 where g.world.tile(x, y) == t { v += g.world.liquidAmount(x, y) } }
    return v
}
/// Runs the world's flow (only) for so many steps
func flow(_ g: Game, _ steps: Int) {
    for _ in 0..<steps { g.world.stepFlow(Liquids.budget) }
}

// ---------------------------------------------------------------- A. liquids that flow
print("== water falls and spreads")
do {
    let (g, x0) = runway()
    basin(g, x0 + 20, x0 + 40)
    // a block of water dropped high in the basin
    g.world.setLiquid(x0 + 30, 85, .water, 1.0)
    let v0 = volume(g, x0 + 21, x0 + 39, 80, 99)
    flow(g, 200)
    let v1 = volume(g, x0 + 21, x0 + 39, 80, 99)
    var lowest = 0
    for y in 80...99 where g.world.tile(x0 + 30, y) == .water { lowest = y }
    check(abs(v1 - v0) < 0.05 && lowest == 99, "a block of water falls to the floor and keeps its amount (\(f3(v0)) then \(f3(v1)))")
    var wide = 0
    for x in (x0 + 21)...(x0 + 39) where g.world.tile(x, 99) == .water { wide += 1 }
    check(wide >= 4 && wide <= 9, "it spreads over the floor as a thin layer, so far and no further (\(wide) cells)")
    check(g.world.flowQ.isEmpty, "then it settles: nothing is left awake")
    // pouring in more fills the basin in a level layer
    for k in 0..<38 { g.world.setLiquid(x0 + 25 + (k % 10), 82, .water, 1.0); flow(g, 6) }
    flow(g, 400)
    let v2 = volume(g, x0 + 21, x0 + 39, 80, 99)
    var rowFull = true
    for x in (x0 + 21)...(x0 + 39) where g.world.liquidAmount(x, 99) < 0.99 { rowFull = false }
    check(rowFull && abs(v2 - (v1 + 38)) < 0.2, "38 more blocks fill the bottom row of the basin and a layer over it (\(f1(v2)) blocks in it)")
    var top = 99.0
    var ends: [Double] = []
    for x in [x0 + 21, x0 + 30, x0 + 39] {
        var y = 99
        while g.world.tile(x, y - 1) == .water { y -= 1 }
        let s = Double(y) + 1.0 - g.world.liquidAmount(x, y)
        ends.append(s); top = min(top, s)
    }
    check(abs(ends[0] - ends[2]) < 0.15 && abs(ends[1] - ends[0]) < 0.15, "its surface is level from one wall to the other (\(f3(ends[0])), \(f3(ends[1])), \(f3(ends[2])))")
    // a hole in the floor: it drains into the room below
    for x in (x0 + 25)...(x0 + 35) { for y in 101...104 { g.world.set(x, y, .air) } }
    g.world.set(x0 + 30, 100, .air)
    flow(g, 900)
    let left = volume(g, x0 + 21, x0 + 39, 80, 99)
    let below = volume(g, x0 + 25, x0 + 35, 100, 104)
    check(left < v2 * 0.5 && below > v2 * 0.5 - 0.5, "a hole in the floor: it pours through into the room below (\(f1(left)) left, \(f1(below)) below)")
}

print("== levels are saved, a still sea costs nothing")
do {
    let (g, x0) = runway()
    basin(g, x0 + 20, x0 + 30)
    g.world.setLiquid(x0 + 25, 99, .water, 0.6)
    g.world.setLiquid(x0 + 26, 99, .water, 0.3)
    g.world.flowQ.removeAll(); g.world.flowSet.removeAll()
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    g2.world.loadAround(centerX: x0 + 25, radius: 3)
    check(abs(g2.world.liquidAmount(x0 + 25, 99) - 0.6) < 0.01 && abs(g2.world.liquidAmount(x0 + 26, 99) - 0.3) < 0.01, "part-full cells are saved and loaded at their levels")
    check(!g2.world.flowQ.isEmpty, "and wake again when their ground loads (they were mid-flow)")
    // a sea that was made, not poured: nothing awake
    let (g3, _) = runway()
    check(g3.world.flowQ.isEmpty, "the world's own seas and lakes are still: nothing flows until something changes")
}

print("== lava meets water")
do {
    let (g, x0) = runway()
    basin(g, x0 + 20, x0 + 30)
    for x in (x0 + 21)...(x0 + 29) { g.world.setLiquid(x, 99, .lava, 1.0) }
    g.world.flowQ.removeAll(); g.world.flowSet.removeAll()
    g.world.setLiquid(x0 + 25, 97, .water, 1.0)
    flow(g, 60)
    let made = g.world.tile(x0 + 25, 99)
    check(made == .obsidian || made == .stone, "water poured on a full pool of lava turns it to \(made == .obsidian ? "obsidian" : "stone") where they meet")
}

print("== a mod's liquid")
do {
    let (g, x0) = runway()
    // a light oil: a mod block that is a liquid, density 0.6
    let slot: Tile = Tile.mod00
    var oil = LiquidDef(tile: slot)
    oil.density = 0.6
    oil.color = 0x302010
    ModRuntime.shared.liquidDefs[slot.rawValue] = oil
    var d = Tile.mod00.def
    d.liquid = true; d.solid = false; d.opaque = false
    Tile.patch(slot, d, tool: .pickaxe)
    basin(g, x0 + 20, x0 + 22, top: 90)
    g.world.setLiquid(x0 + 21, 99, slot, 1.0)
    g.world.setLiquid(x0 + 21, 98, .water, 1.0)
    flow(g, 40)
    check(g.world.tile(x0 + 21, 99) == .water && g.world.tile(x0 + 21, 98) == slot, "a light oil poured under water rises and floats on it")
    // the bucket
    g.inv.add(.gadget(.bucket), 1)
    g.sel = g.inv.slots.firstIndex(where: { $0?.item == .gadget(.bucket) }) ?? 0
    g.useCD = 0
    g.pb.x = Double(x0 + 21); g.pb.y = 97
    g.aimX = Double(x0) + 21.5; g.aimY = 99.5
    g.useBucket()
    check(g.inv.slots[g.sel]?.extra == Int(Tile.water.rawValue) + 1 && g.world.tile(x0 + 21, 99) != .water, "a bucket takes up a block of water")
    g.useCD = 0
    g.aimX = Double(x0) + 26.5; g.aimY = 95.5
    g.useBucket()
    check(g.inv.slots[g.sel]?.extra == 0 && g.world.tile(x0 + 26, 95) == .water, "and pours it out again somewhere else")
    ModRuntime.shared.liquidDefs[slot.rawValue] = nil
}

// ---------------------------------------------------------------- B. ships and submarines
func sea2() -> (Game, Int) {
    let (g, x0) = runway()
    for x in x0...(x0 + 300) {
        for y in 100..<112 { g.world.set(x, y, .water) }
        for y in 112..<116 { g.world.set(x, y, .stone) }
    }
    g.world.flowQ.removeAll(); g.world.flowSet.removeAll()
    return (g, x0)
}
/// A hollow box of a block, w x h, open on top or closed
func hollow(_ g: Game, _ w: Int, _ h: Int, _ t: Tile, left: Double, bottom: Double, roof: Bool, extra: [(Int, Int, PartType, Tile?)] = [], hole: PartCell? = nil) -> Vehicle {
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<w { for y in 0..<h where x == 0 || x == w - 1 || y == h - 1 || (roof && y == 0) {
        if let k = hole, k.dx == x, k.dy == y { continue }
        cells.append((x, y, .block, t))
    } }
    cells.append(contentsOf: extra)
    return build(g, cells, left: left, bottom: bottom)
}

print("== floating on the air in the hull")
do {
    // a hollow box of stone, 10 by 6: its walls alone would sink, the air inside holds it up
    let (g, x0) = sea2()
    let v = hollow(g, 10, 6, .stone, left: Double(x0 + 40), bottom: 101, roof: false)
    var t = 0.0
    while t < 8 { g.updateVehicles(dt60); for v in g.vehicles { g.vehicleExtras(v, dt60) }; t += dt60 }
    check(v.b.y < 107 && v.b.top < 100 && !v.hullAir.isEmpty, "an open box of stone floats on the air in it, its rim above the water (bottom at \(f1(v.b.y)), sea level 100)")
    // the same box with a hole in its floor floods and sinks
    let (g2, y0) = sea2()
    let h = hollow(g2, 10, 6, .stone, left: Double(y0 + 40), bottom: 101, roof: false, hole: PartCell(dx: 4, dy: 5))
    t = 0
    while t < 12 { g2.updateVehicles(dt60); for v in g2.vehicles { g2.vehicleExtras(v, dt60) }; t += dt60 }
    check(h.b.y > 110, "with a hole in its floor it floods and sinks to the bottom (bottom at \(f1(h.b.y)))")
}

print("== a submarine")
do {
    let (g, x0) = sea2()
    // a sealed hull: a stone keel, plank sides and roof, eight ballast tanks on the floor inside, a
    // cockpit, and an engine and propeller at the back
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<10 {
        cells.append((x, 4, .block, .stone))
        cells.append((x, 0, .block, .planks))
    }
    for y in 1...3 { cells.append((0, y, .block, .planks)); cells.append((9, y, .block, .planks)) }
    for x in 1...8 { cells.append((x, 3, .ballast, nil)) }
    cells.append((2, 2, .cockpit, nil)); cells.append((-1, 2, .propeller, nil)); cells.append((-1, 1, .engine, nil))
    let v = build(g, cells, left: Double(x0 + 40), bottom: 101)
    g.inVehicle = v; v.rider = true
    var t = 0.0
    while t < 6 { g.stickY = 0; g.tick(dt60); t += dt60 }
    let floatY = v.py
    t = 0
    while t < 10 {
        g.stickY = 1; g.tick(dt60); g.hunger = 20; t += dt60
    }
    g.stickY = 0
    let deep = v.py
    check(deep > floatY + 3 && v.ballast > 0.5, "stick down floods the ballast tanks and it dives (\(f1(deep - floatY)) blocks down)")
    // the player inside: dry
    g.inVehicle = nil; v.rider = false
    g.boardFrame(&g.pb, v, 5.5, 3.0)
    g.pb.onGround = true
    g.mode = .survival
    g.air = 10
    t = 0
    while t < 4 { g.tick(dt60); g.hunger = 20; t += dt60 }
    check(!g.pb.inWater && g.air >= 9.9 && v.dryAt(5.5, 2.0) && v.b.top > 100.5, "inside the sealed hull under water the player is dry and breathes (air \(f1(g.air)))")
    g.mode = .creative
    g.mountVehicle(v, at: PartCell(dx: 2, dy: 2))
    t = 0
    while t < 12 { g.stickY = -1; g.tick(dt60); g.hunger = 20; t += dt60 }
    g.stickY = 0
    check(v.py < deep - 3 && v.ballast < 0.3, "stick up blows the tanks and it rises again (\(f1(deep - v.py)) blocks up)")
}

// ---------------------------------------------------------------- C. flight
print("== wings, flaps, air brakes, tailplanes")
do {
    let (g, x0) = runway()
    let plane = kit(g, .planeKit, x0 + 40, 60)
    var wc: [PartCell] = []
    for (c, t) in plane.parts where t == .wing { wc.append(c) }
    func liftAt(_ speed: Double) -> Double {
        plane.angle = 0; plane.vx = speed; plane.vy = 0; plane.angVel = 0; plane.rider = true; plane.fuel = 50
        plane.airspeed = speed
        g.airForces(plane, 1.0 / 120.0, 0)
        return plane.liftNow
    }
    let flat = liftAt(14)
    for c in wc { plane.tilt[c] = 2 }
    let tilted = liftAt(14)
    check(tilted > flat * 1.2, "wings tilted up two steps lift more at the same speed (\(f1(tilted)) against \(f1(flat)))")
    let r = Vehicle.restore(plane.save())
    check(r.tilt.count == wc.count, "the tilt is kept in the save")
    for c in wc { plane.tilt[c] = nil }
    for c in wc { plane.parts[c] = .flap }
    plane.recompute(keepAnchor: true)
    let slowFlap = liftAt(9)
    for c in wc { plane.parts[c] = .wing }
    plane.recompute(keepAnchor: true)
    let slowWing = liftAt(9)
    check(slowFlap > slowWing * 1.3 && plane.wings == wc.count, "flapped wings lift more when slow (\(f1(slowFlap)) against \(f1(slowWing)))")
    // an air brake: open, it slows a glide
    let (g2, y0) = runway()
    let a = kit(g2, .planeKit, y0 + 40, 60)
    let b = kit(g2, .planeKit, y0 + 140, 60)
    b.parts[PartCell(dx: (b.minX + b.maxX) / 2, dy: b.minY - 1)] = .airBrake
    b.recompute(keepAnchor: true)
    for v in [a, b] { v.vx = 30; v.rider = true; v.throttle = -1 }
    var t = 0.0
    while t < 1.5 {
        for v in [a, b] { v.throttle = -1; v.rider = true; g2.ballastAndBrakes(v, dt60) }
        g2.stepVehicles([a, b], dt60)
        t += dt60
    }
    check(b.brakeOpen > 0.9 && b.vx < a.vx - 0.5, "an air brake opens against the motion and slows it (\(f1(b.vx)) against \(f1(a.vx)))")
    // a tailplane steadies the nose: a glider with none tumbles, one with a tailplane at the end of a
    // boom keeps its nose into the wind
    func glider(_ g: Game, _ left: Double, tail: Bool) -> Vehicle {
        var cells: [(Int, Int, PartType, Tile?)] = [(4, 0, .cockpit, nil), (3, 1, .wing, nil), (4, 1, .wing, nil), (5, 1, .wing, nil), (5, 0, .block, .stone)]
        for x in 0...2 { cells.append((x, 1, .frame, nil)) }
        if tail { cells.append((-1, 1, .stabilizer, nil)) }
        return build(g, cells, left: left, bottom: 40)
    }
    let (g3, z0) = runway()
    let q1 = glider(g3, Double(z0 + 40), tail: false)
    let q2 = glider(g3, Double(z0 + 160), tail: true)
    var worst1 = 0.0
    var worst2 = 0.0
    for q in [q1, q2] { q.vx = 24; q.angle = 0.25; q.rider = false }
    t = 0
    while t < 2.0 {
        g3.stepVehicles([q1, q2], dt60)
        t += dt60
        worst1 = max(worst1, abs(remainder(q1.angle, 2 * Double.pi)))
        worst2 = max(worst2, abs(remainder(q2.angle, 2 * Double.pi)))
    }
    check(worst2 < worst1 && worst2 < 0.8, "a tailplane keeps a glider's nose steady (it tips \(f3(worst2)) at most, without one \(f3(worst1)))")
}

print("== the wind and the shelter of the land")
do {
    let (g, x0) = runway()
    g.settings.weatherOn = true
    // a wall upwind of one place: the wind there is far less
    for y in 80...99 { g.world.set(x0 + 60, y, .stone); g.world.set(x0 + 61, y, .stone) }
    check(g.windShelter(Double(x0 + 63), 95, -1) < 0.5 && g.windShelter(Double(x0 + 120), 95, -1) == 1.0, "a wall just upwind takes most of the wind; open ground takes none of it")
}


print("phys3: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
