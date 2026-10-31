import SwiftUI
var s = Settings()
let g = Game(mode: .creative, infinite: true, seed: 4242, settings: s)
g.viewW = 1100; g.viewH = 800
let w = g.world
let x0 = Int(g.pb.x) - 60
let G = 100
w.loadAround(centerX: Int(g.pb.x), radius: 7)
func flat(_ xa: Int, _ xb: Int, _ ground: Int) {
    for x in xa...xb { for y in 20..<ground { w.set(x, y, .air) }; for y in ground..<(ground + 6) { w.set(x, y, .stone) } }
}
flat(x0, x0 + 120, G)
func kit(_ k: Gadget, _ left: Int, _ bottom: Int) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for p in kitLayout(k) { v.parts[PartCell(dx: p.dx, dy: p.dy)] = p.p }
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(left), bottom: Double(bottom))
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
func run(_ v: Vehicle, _ secs: Double, _ thr: Double) -> (Double, Double, Double, Double) {
    var minA = 99.0, maxA = -99.0, maxUp = 0.0
    let startY = v.py
    g.inVehicle = v; v.rider = true
    var t = 0.0
    while t < secs { g.stick = thr; g.tick(1.0/60.0); t += 1.0/60.0
        minA = min(minA, v.angle); maxA = max(maxA, v.angle); maxUp = max(maxUp, startY - v.py) }
    g.stick = 0
    return (minA, maxA, maxUp, v.px)
}
// 1. settle on flat ground
let car = kit(.carKit, x0 + 10, G)
var t = 0.0; while t < 2 { g.tick(1.0/60.0); t += 1.0/60.0 }
print(String(format: "settle: angle %.4f  vy %.3f  bottom %.3f (ground %d) asleep %d", car.angle, car.vy, car.b.y, G, car.asleep ? 1 : 0))
// 2. drive on flat
let sx = car.px
var r = run(car, 4, 1)
print(String(format: "flat drive: dx %.1f  angle %.3f..%.3f  max rise %.2f  speed %.1f", car.px - sx, r.0, r.1, r.2, car.speed))
// 3. ramp: 45 degree slope up from x0+70
for i in 0..<14 { for y in (G - i)..<G { w.set(x0 + 75 + i, y, .stone) } }
for x in (x0 + 89)...(x0 + 110) { for y in (G - 13)..<G { w.set(x, y, .stone) } }
r = run(car, 6, 1)
print(String(format: "ramp: x %.1f (ramp starts %d)  angle range %.3f..%.3f rad  top y %.2f", car.px, x0 + 75, r.0, r.1, car.b.y))
// 4. drop test
let car2 = kit(.carKit, x0 + 30, G - 30)
g.inVehicle = nil; car.rider = false
t = 0; var lowest = 0.0
while t < 3 { g.tick(1.0/60.0); t += 1.0/60.0; lowest = max(lowest, car2.b.y) }
print(String(format: "drop: final bottom %.3f lowest %.3f (ground %d) angle %.3f", car2.b.y, lowest, G, car2.angle))
// 5. boat
for x in (x0 + 40)...(x0 + 66) { for y in (G - 6)..<(G + 4) { w.set(x, y, y < G - 2 ? .air : .water) } }
for x in (x0 + 40)...(x0 + 66) { w.set(x, G + 4, .stone) }
g.vehicles.removeAll { $0 === car2 }
let boat = kit(.boatKit, x0 + 50, G - 3)
t = 0; while t < 4 { g.tick(1.0/60.0); t += 1.0/60.0 }
print(String(format: "boat: bottom %.2f (water surface %d) angle %.3f  vy %.3f submerged %.2f", boat.b.y, G - 2, boat.angle, boat.vy, boat.submerged))
let bx = boat.px
_ = run(boat, 3, 1)
print(String(format: "boat paddle: dx %.2f angle %.3f", boat.px - bx, boat.angle))
// 6. drill car into a stone wall
g.inVehicle = nil; boat.rider = false
flat(x0 + 70, x0 + 118, G)
for x in (x0 + 95)...(x0 + 105) { for y in (G - 6)..<G { w.set(x, y, .stone) } }
let dc = kit(.carKit, x0 + 80, G)
let eng = dc.parts.first { $0.value == .engine }!.key
dc.parts[PartCell(dx: eng.dx + 1, dy: eng.dy)] = .drill
dc.recompute(keepAnchor: true)
dc.fuel = dc.fuelCapacity
var mined0 = 0; for x in (x0 + 95)...(x0 + 105) { for y in (G - 6)..<G { if w.tile(x, y) == .stone { mined0 += 1 } } }
_ = run(dc, 8, 1)
var mined1 = 0; for x in (x0 + 95)...(x0 + 105) { for y in (G - 6)..<G { if w.tile(x, y) == .stone { mined1 += 1 } } }
print("drill: stone blocks in wall \(mined0) -> \(mined1), car x \(String(format: "%.1f", dc.px)) (wall starts \(x0 + 95)) drills \(dc.drills) dir \(String(describing: dc.drillDir.values.first))")
// 7. real terrain: drive the car across natural hills for 40 s
g.vehicles.removeAll()
let rx = Int(g.pb.x) + 200
w.loadAround(centerX: rx + 150, radius: 14)
let gy = w.surfaceY(rx)
let rc = kit(.carKit, rx, gy - 1)
print("terrain profile from", rx)
for yy in (gy - 2)...(gy + 12) {
    var line = ""
    for xx in (rx+25)...(rx + 70) {
        let t = w.tile(xx, yy)
        line += t == .air ? "." : (isLogTile(t) ? "L" : (t.solid ? "#" : (t == .leaves ? "l" : (t == .water ? "~" : "?"))))
    }
    print(line)
}
var stuckT = 0.0, worstStuck = 0.0, maxUpV = 0.0, maxAng = 0.0
g.inVehicle = rc; rc.rider = true
var tt = 0.0, lastX = rc.px
var revT = 0.0
while tt < 40 {
    if stuckT > 1.0 && revT <= 0 { revT = 1.2 }
    if revT > 0 { revT -= 1.0/60.0 }
    g.stick = revT > 0 ? -1 : 1; g.pb.x = rc.px; g.tick(1.0/60.0); tt += 1.0/60.0
    w.loadAround(centerX: Int(rc.px), radius: 4)
    maxUpV = max(maxUpV, -rc.vy); maxAng = max(maxAng, abs(rc.angle))
    if rc.speed < 0.6 && revT <= 0 { stuckT += 1.0/60.0; worstStuck = max(worstStuck, stuckT) } else { stuckT = 0 }
    if rc.fuel < 5 { rc.fuel = rc.fuelCapacity }
    if (tt > 4.0 && tt < 6.5 && Int(tt*60) % 3 == 0) { print(String(format: "  t %.2f x %.1f y %.1f ang %.2f w %.2f vx %.1f vy %.1f c %d wh %d", tt, rc.px, rc.py, rc.angle, rc.angVel, rc.vx, rc.vy, rc.contacts, rc.wheelContacts)) }
}
print(String(format: "terrain: travelled %.0f tiles in 40 s, max up speed %.1f, max |angle| %.2f, longest stall %.1f s", rc.px - lastX, maxUpV, maxAng, worstStuck))
print(String(format: "stuck at px %.1f py %.1f angle %.2f contacts %d wheels %d", rc.px, rc.py, rc.angle, rc.contacts, rc.wheelContacts))
for yy in (Int(rc.py) - 5)...(Int(rc.py) + 3) {
    var line = ""
    for xx in (Int(rc.px) - 4)...(Int(rc.px) + 8) {
        let t = w.tile(xx, yy)
        line += t == .air ? "." : (isLogTile(t) ? "L" : (t.solid ? "#" : (t == .leaves ? "l" : "~")))
    }
    print(line)
}
