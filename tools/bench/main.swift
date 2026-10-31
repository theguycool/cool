import SwiftUI
func now() -> Double { Date().timeIntervalSinceReferenceDate }
var s = Settings()
let g = Game(mode: .survival, infinite: true, seed: 12345, settings: s)
g.viewW = 1180; g.viewH = 820
// 1. chunk generation
var t = now()
for cx in 200..<240 { _ = generateChunk(g.gen, .overworld, cx) }
print(String(format: "chunkgen  %.2f ms/chunk", (now() - t) * 1000 / 40))
// 2. section painting
let ch = g.world.chunks.values.first!
t = now()
for _ in 0..<5 { for sy in 0..<35 { _ = SectionPainter.shared.paint(g.world, ch, sy) } }
print(String(format: "paint     %.3f ms/section", (now() - t) * 1000 / 175))
// warm the world
for _ in 0..<120 { g.tick(1.0/60.0) }
// 3. light full recompute
t = now()
for i in 0..<30 { g.light.valid = false; g.lightTimer = 0; g.pb.x += (i % 2 == 0 ? 1 : -1); g.updateLight(1.0/60.0) }
print(String(format: "light     %.2f ms/update", (now() - t) * 1000 / 30))
// 4. tick with many mobs + particles
g.settings.peaceful = false
let kinds: [MobKind] = [.zombie, .skeleton, .slime, .pig, .cow, .wolf, .bear, .chicken, .bat]
for i in 0..<60 { let m = g.addMob(kinds[i % kinds.count], g.pb.x + Double(i % 30) - 15, g.pb.y - 2); m.persistent = true }
g.godMode = true
t = now()
var maxT = 0.0
for i in 0..<600 {
    let a = now()
    if i % 10 == 0 { g.spawnParticles(g.pb.x, g.pb.y - 1, 0xFFFFFF, 30, 4) }
    g.stick = (i / 120) % 2 == 0 ? 1 : -1
    g.tick(1.0/60.0)
    maxT = max(maxT, now() - a)
}
print(String(format: "tick60mob %.2f ms avg, %.2f ms worst, mobs %d", (now() - t) * 1000 / 600, maxT * 1000, g.mobs.count))
// 5. walk far: streaming + light
t = now(); maxT = 0
g.noclip = true
for _ in 0..<600 { let a = now(); g.stick = 1; g.tick(1.0/60.0); maxT = max(maxT, now() - a) }
print(String(format: "travel    %.2f ms avg, %.2f ms worst, x=%.0f chunks=%d", (now() - t) * 1000 / 600, maxT * 1000, g.pb.x, g.world.chunks.count))
