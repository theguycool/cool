import SwiftUI
import Foundation

// Boat scenarios. Sea: water rows 98...109 (surface at y = 98), stone floor below. A sand beach rises
// out of the water at the right end.
func sea(_ seed: UInt64 = 4242) -> (Game, Int) {
    let g = Game(mode: .creative, infinite: true, seed: seed, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false; g.pauseSpawning = true; g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 90
    w.loadAround(centerX: Int(g.pb.x), radius: 9)
    for x in x0...(x0 + 180) {
        for y in 40..<98 { w.set(x, y, .air) }
        for y in 98..<110 { w.set(x, y, .water) }
        for y in 110..<116 { w.set(x, y, .stone) }
    }
    // beach: slope up from the sea floor to dry land over 14 columns, starting at x0+150
    for i in 0..<30 {
        let x = x0 + 150 + i
        let top = max(95, 110 - i)
        for y in top..<110 { w.set(x, y, .sand) }
    }
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
struct Trace { var minA = 99.0, maxA = -99.0, minY = 999.0, maxY = -999.0, maxVy = 0.0, maxJerk = 0.0, maxSpin = 0.0 }
func run(_ g: Game, _ v: Vehicle, _ secs: Double, _ thr: Double, dt: Double = 1.0 / 60.0, from: Double = 0) -> Trace {
    var tr = Trace()
    g.inVehicle = v; v.rider = true
    var t = 0.0
    var lastVy = v.vy
    while t < secs {
        g.stick = thr
        g.tick(dt)
        t += dt
        if t >= from {
            tr.minA = min(tr.minA, v.angle); tr.maxA = max(tr.maxA, v.angle)
            tr.minY = min(tr.minY, v.py); tr.maxY = max(tr.maxY, v.py)
            tr.maxVy = max(tr.maxVy, abs(v.vy))
            tr.maxJerk = max(tr.maxJerk, abs(v.vy - lastVy) / dt)
            tr.maxSpin = max(tr.maxSpin, abs(v.angVel))
        }
        lastVy = v.vy
    }
    g.stick = 0
    return tr
}
func show(_ name: String, _ v: Vehicle, _ tr: Trace) {
    print(String(format: "%@: x %.2f  y %.3f  angle %.3f..%.3f  bob %.3f  |vy| max %.3f  vy jerk max %.1f  spin max %.3f  vx %.2f  sub %.2f",
                 name, v.px, v.py, tr.minA, tr.maxA, tr.maxY - tr.minY, tr.maxVy, tr.maxJerk, tr.maxSpin, v.vx, v.submerged))
}

for k in [Gadget.boatKit, .motorboatKit] {
    print("=== \(k == .boatKit ? "rowboat" : "motorboat")")
    let (g, x0) = sea()
    let v = kit(g, k, x0 + 60, 97)
    _ = run(g, v, 3, 0)
    let calm = run(g, v, 6, 0)
    show("calm (last 6 s)", v, calm)
    let x1 = v.px
    let fwd = run(g, v, 6, 1, from: 2)
    show("forward 6 s", v, fwd)
    print(String(format: "   forward distance %.1f", v.px - x1))
    let x2 = v.px
    let rev = run(g, v, 6, -1, from: 2)
    show("reverse 6 s", v, rev)
    print(String(format: "   reverse distance %.1f", v.px - x2))
    let stop = run(g, v, 4, 0, from: 2)
    show("coast to stop", v, stop)
    // frame rate independence: same scenario at 30 and 60 fps
    var ends: [(Double, Double, Double)] = []
    for dt in [1.0 / 60.0, 1.0 / 30.0] {
        let (g2, x02) = sea()
        let v2 = kit(g2, k, x02 + 60, 97)
        _ = run(g2, v2, 3, 0, dt: dt)
        _ = run(g2, v2, 4, 1, dt: dt)
        ends.append((v2.px, v2.py, v2.angle))
    }
    print(String(format: "   60 fps vs 30 fps after 7 s: dx %.3f  dy %.3f  dangle %.4f", ends[0].0 - ends[1].0, ends[0].1 - ends[1].1, ends[0].2 - ends[1].2))
    // drive onto the beach and then try to reverse off it
    let (g3, x03) = sea()
    let v3 = kit(g3, k, x03 + 135, 97)
    _ = run(g3, v3, 2, 0)
    let beach = run(g3, v3, 10, 1)
    show("beach run 10 s", v3, beach)
    let bx = v3.px
    _ = run(g3, v3, 8, -1)
    print(String(format: "   reversed off the beach: moved %.1f (x %.1f -> %.1f)", v3.px - bx, bx, v3.px))
}

print("=== chunk edges, collisions, the player")
do {
    // a boat straddling a chunk edge whose neighbour is unloaded waits instead of hitting "stone"
    let (g, x0) = sea()
    let v = kit(g, .boatKit, x0 + 60, 97)
    _ = run(g, v, 3, 0)
    let edge = (Int(floor(v.b.right)) / chunkW + 1) * chunkW
    // move the boat so it overlaps the next chunk, then unload that chunk
    v.px += Double(edge) - v.b.right + 1.5
    v.updateBox()
    let cxn = floorDiv(Int(floor(v.b.right)) + 1, chunkW)
    g.world.unloadChunk(cxn)
    let before = (v.px, v.py, v.angle)
    for _ in 0..<120 { g.stepVehicle(v, 1.0 / 60.0) }
    print(String(format: "unloaded neighbour: moved dx %.4f dy %.4f dangle %.4f (should be 0)", v.px - before.0, v.py - before.1, v.angle - before.2))
    g.world.loadChunk(cxn)
    for y in 40..<98 { for xx in (cxn * chunkW)..<(cxn * chunkW + chunkW) { g.world.set(xx, y, .air) } }
    for y in 98..<110 { for xx in (cxn * chunkW)..<(cxn * chunkW + chunkW) { g.world.set(xx, y, .water) } }
    for y in 110..<116 { for xx in (cxn * chunkW)..<(cxn * chunkW + chunkW) { g.world.set(xx, y, .stone) } }
    var jump = 0.0
    var py0 = v.py
    for _ in 0..<120 { g.stepVehicle(v, 1.0 / 60.0); jump = max(jump, abs(v.py - py0)); py0 = v.py }
    print(String(format: "after the chunk loads: largest per-frame vertical move %.4f", jump))
    // drive across several chunks while chunks stream around the player
    g.inVehicle = v; v.rider = true
    let startX = v.px
    var maxJump = 0.0
    var last = v.py
    var t = 0.0
    while t < 25 { g.stick = 1; g.tick(1.0 / 60.0); t += 1.0 / 60.0; maxJump = max(maxJump, abs(v.py - last)); last = v.py
        if v.px > Double(x0 + 140) { break } }
    g.stick = 0
    print(String(format: "crossed %.0f blocks (%d chunk edges): largest per-frame vertical move %.4f, angle %.3f", v.px - startX, Int(v.px) / chunkW - Int(startX) / chunkW, maxJump, v.angle))
}
do {
    // ram a parked boat
    let (g, x0) = sea()
    let a = kit(g, .motorboatKit, x0 + 40, 97)
    let b = kit(g, .boatKit, x0 + 58, 97)
    _ = run(g, a, 2, 0); g.inVehicle = nil; a.rider = false
    var maxV = 0.0
    var overlapEnd = 0.0
    g.inVehicle = a; a.rider = true
    var t = 0.0
    while t < 8 { g.stick = 1; g.tick(1.0 / 60.0); t += 1.0 / 60.0; maxV = max(maxV, abs(b.vx), abs(b.vy) * 3, abs(a.vy) * 3) }
    g.stick = 0
    overlapEnd = min(a.b.right, b.b.right) - max(a.b.left, b.b.left)
    print(String(format: "motorboat into rowboat: rowboat pushed to x %.1f, overlap at end %.2f, max speed seen %.2f, angles %.3f / %.3f", b.px - Double(x0 + 58), overlapEnd, maxV, a.angle, b.angle))
}
do {
    // the player stands on a parked boat and walks along it; then boards and gets off
    let (g, x0) = sea()
    let v = kit(g, .boatKit, x0 + 60, 97)
    _ = run(g, v, 3, 0); g.inVehicle = nil; v.rider = false
    _ = g.mobs.isEmpty
    g.pb.x = v.b.x; g.pb.y = v.b.top - 2; g.pb.vx = 0; g.pb.vy = 0
    for _ in 0..<90 { g.tick(1.0 / 60.0) }
    print(String(format: "player dropped onto the parked boat: feet y %.2f, boat top %.2f, on ground %@", g.pb.y, v.b.top, g.pb.onGround ? "yes" : "no"))
    g.mountVehicle(v)
    for _ in 0..<60 { g.tick(1.0 / 60.0) }
    let seatOK = abs(g.pb.x - v.b.x) < 2.5
    g.dismount()
    for _ in 0..<60 { g.tick(1.0 / 60.0) }
    print(String(format: "boarded (seat follows boat: %@), dismounted: player y %.2f, boat angle %.3f, boat dy since %.3f", seatOK ? "yes" : "no", g.pb.y, v.angle, v.py - 97.56))
}
