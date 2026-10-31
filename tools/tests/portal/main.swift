import SwiftUI
func show(_ g: Game, _ base: Int) {
    let px = g.gen.portalX
    for y in (base - 10)...(base + 1) {
        var line = ""
        for x in (px - 6)...(px + 6) {
            let t = g.world.tile(x, y)
            line += t == .portalFrame ? "A" : (t == .portalOff ? "o" : (t == .portalOn ? "O" : (t.solid ? "#" : ".")))
        }
        print("  " + line)
    }
}
var fails = 0
func check(_ ok: Bool, _ msg: String) { print((ok ? "PASS " : "FAIL ") + msg); if !ok { fails += 1 } }

// new world: rift shape, open it, walk in, travel, no bounce back
let g = Game(mode: .creative, infinite: true, seed: 777, settings: Settings())
g.viewW = 1100; g.viewH = 800
let px = g.gen.portalX
g.world.loadAround(centerX: px, radius: 3)
let base = g.riftBase
print("overworld rift (v\(g.gen.genVersion)):"); show(g, base)
check(g.world.tile(px, base - 4) == .portalOff, "dormant rift at centre")
check(!g.world.tile(px - 3, base - 2).solid && !g.world.tile(px + 3, base - 1).solid, "sides open at walking height")
g.tryOpenPortal(px, base - 4)
check(g.world.tile(px, base - 4) == .portalOn && g.world.tile(px - 2, base - 4) == .portalOn, "key opens the whole oval")
// walk in from the right
let sp = g.portalArrival(.overworld); g.pb.x = sp.0; g.pb.y = sp.1; g.pb.vx = 0; g.pb.vy = 0
print("start", sp)
var t = 0.0; var arrived = false
while t < 6 { g.stick = g.pb.x > Double(px) + 0.6 ? -1 : 0; g.tick(1.0/60.0); t += 1.0/60.0; if Int(t*60) % 30 == 0 { print(String(format:"   x %.2f y %.2f", g.pb.x, g.pb.y)) }; if g.world.dim == .umbral { arrived = true; break } }
g.stick = 0
check(arrived, String(format: "walking into the rift crosses to the umbral realm (%.1f s)", t))
check(g.portalNeedsExit, "rift is resting after the trip")
// stand inside the umbral rift for 3 s: must not bounce back while needsExit
let ub = g.riftBase
print("umbral rift:"); show(g, ub)
g.pb.x = Double(px) + 0.5; g.pb.y = Double(ub); g.pb.vx = 0
g.portalNeedsExit = true
t = 0
while t < 3 { g.tick(1.0/60.0); t += 1.0/60.0; g.pb.x = Double(px) + 0.5 }
check(g.world.dim == .umbral, "standing in the rift after arriving does not teleport again")
// step out and back in: now it works
g.pb.x = Double(px) + 6.5; g.pb.y = Double(ub)
for _ in 0..<10 { g.tick(1.0/60.0) }
check(!g.portalNeedsExit, "stepping out re-arms the rift")
g.pb.x = Double(px) + 0.5; g.pb.y = Double(ub)
t = 0
while t < 3 && g.world.dim == .umbral { g.tick(1.0/60.0); t += 1.0/60.0; g.pb.x = Double(px) + 0.5 }
check(g.world.dim == .overworld, "re-entering returns to the overworld")

// old world (v1): rectangular frame gets migrated once loaded
let o = Game(mode: .creative, infinite: true, seed: 777, settings: Settings(), genVersion: 1)
o.viewW = 1100; o.viewH = 800
o.world.loadAround(centerX: o.gen.portalX, radius: 3)
let ob = o.riftBase
check(o.world.tile(o.gen.portalX - 3, ob - 8) == .portalFrame, "v1 world generates the old closed frame")
o.migrateOldRift()
print("v1 after migration:"); show(o, ob)
check(o.world.tile(o.gen.portalX - 3, ob - 8) != .portalFrame && o.world.tile(o.gen.portalX, ob - 4) == .portalOff, "v1 frame rebuilt as the open rift")
print(fails == 0 ? "ALL PORTAL TESTS PASSED" : "\(fails) FAILED")
