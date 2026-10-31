import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }
func biomeX(_ g: Game, _ b: Biome) -> Int? {
    var x = 0
    while x < 60000 {
        if g.gen.col(x).biome == b && g.gen.col(x - 60).biome == b && g.gen.col(x + 60).biome == b { return x }
        x += 16
    }
    return nil
}

/// a real generated world, the player standing on the surface (optionally in a biome)
func world(_ opts: WorldOptions = .standard, biome: Biome? = nil, settings: Settings = Settings()) -> Game {
    let probe = Game(mode: .survival, infinite: true, seed: 4242, settings: settings, options: opts)
    var x = Int(probe.pb.x)
    if let b = biome { x = biomeX(probe, b) ?? x }
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: settings, options: opts)
    g.viewW = 1100; g.viewH = 800
    g.settings.weatherOn = false
    g.mobs.removeAll()
    g.world.loadAround(centerX: x, radius: 6)
    g.pb.x = Double(x) + 0.5
    g.pb.y = Double(g.world.surfaceY(x))
    g.camX = g.pb.x; g.camY = g.pb.y - 2
    g.godMode = true
    return g
}

/// open ground: air above row 100, stone below, wide enough for spawning on both sides
func arena(_ half: Int = 70) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings(), options: .standard)
    g.viewW = 1100; g.viewH = 800
    g.settings.weatherOn = false
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - half
    w.loadAround(centerX: Int(g.pb.x), radius: 8)
    for x in x0...(x0 + half * 2) {
        for y in 30..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + half) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.hp = g.maxHP
    g.light.valid = false
    g.camX = g.pb.x; g.camY = g.pb.y - 2
    return g
}

func monsters(_ g: Game) -> [Mob] { return g.mobs.filter { $0.hp > 0 && !$0.removed && $0.def.hostile && !$0.kind.isPredator } }

// ---------------------------------------------------------------- A. spawning through a day and night
print("== night spawning")
do {
    let g = world(biome: .plains)
    g.timeOfDay = 0.25
    step(g, 60, 1.0 / 30.0)
    check(monsters(g).isEmpty, "no night monsters come out at noon (\(monsters(g).count))")
    // dusk into night
    g.timeOfDay = 0.5
    var firstNight = -1.0
    var t = 0.0
    var maxActive = 0
    var spawnDists: [Double] = []
    var seen = Set<Int>()
    while t < 140 {
        g.tick(1.0 / 30.0); t += 1.0 / 30.0
        for m in monsters(g) where !seen.contains(m.id) {
            seen.insert(m.id)
            spawnDists.append(abs(m.b.x - g.pb.x))
            if firstNight < 0 && g.isNight { firstNight = t }
        }
        maxActive = max(maxActive, g.monstersAbout())
    }
    let nightStart = (0.545 - 0.5) * g.dayLength
    check(firstNight >= 0 && firstNight - nightStart < 20, "the first monster comes out within 20 s of nightfall (\(f1(firstNight - nightStart)) s)")
    check(seen.count >= 4, "a night on the plains brings several monsters (\(seen.count) in 140 s)")
    check(maxActive <= g.monsterCap(.surface), "never more than the limit about at once (\(maxActive) / \(g.monsterCap(.surface)))")
    let half = g.viewTilesW * 0.5
    check(!spawnDists.isEmpty && spawnDists.allSatisfy { $0 > half && $0 < half + 22 }, "they appear just past the edge of the screen (\(f1(spawnDists.min() ?? 0))...\(f1(spawnDists.max() ?? 0)), screen half \(f1(half)))")
    let near = monsters(g).filter { abs($0.b.x - g.pb.x) < 16 }.count
    check(near >= 2, "the night's monsters find the player (\(near) within 16 blocks)")
    // kill them all: new ones come
    for m in monsters(g) { m.hp = 0; m.removed = true }
    step(g, 25, 1.0 / 30.0)
    check(monsters(g).count >= 2, "after the monsters die, new ones replace them (\(monsters(g).count) in 25 s)")
    // daybreak: the hunters out of sight go home
    g.timeOfDay = 0.99
    step(g, 30, 1.0 / 30.0)
    let off = monsters(g).filter { abs($0.b.x - g.pb.x) > g.viewTilesW * 0.5 + 6 && $0.hunter }.count
    check(off == 0, "by morning the night's monsters out of sight are gone (\(off) left)")
    check(g.spawnLog["monster limit reached", default: 0] > 0, "the spawner's log says why attempts stopped (limit reached \(g.spawnLog["monster limit reached", default: 0]) times)")
}
do {
    // predators about by day don't use up the night's monsters (the original bug)
    let g = world(biome: .forest)
    g.timeOfDay = 0.5
    for i in 0..<6 { let m = g.addMob(.grizzly, g.pb.x + 30 + Double(i) * 3, Double(g.world.surfaceY(Int(g.pb.x) + 30 + i * 3))); m.homeX = m.b.x }
    g.timeOfDay = 0.6
    step(g, 60, 1.0 / 30.0)
    check(monsters(g).count >= 2, "six bears nearby still leave room for the night's monsters (\(monsters(g).count))")
}
do {
    var o = WorldOptions(); o.flat = true
    let g = world(o)
    g.timeOfDay = 0.6
    step(g, 60, 1.0 / 30.0)
    check(monsters(g).count >= 2, "monsters come out at night in a flat world (\(monsters(g).count))")
}
do {
    // the danger setting changes how many
    var counts: [Int] = []
    for d in [0, 2] {
        var st = Settings(); st.nightDanger = d
        let g = arena()
        g.settings = st
        g.settings.weatherOn = false
        g.godMode = true
        g.timeOfDay = 0.6
        var mx = 0
        var t = 0.0
        while t < 90 { g.tick(1.0 / 30.0); t += 1.0 / 30.0; mx = max(mx, g.monstersAbout()) }
        counts.append(mx)
    }
    check(counts[0] <= 3 && counts[1] > counts[0], "calm nights hold fewer monsters than deadly ones (\(counts[0]) vs \(counts[1]))")
}
do {
    // peaceful and the monsters switch keep them away
    var st = Settings(); st.peaceful = true
    let g = arena()
    g.settings = st; g.settings.weatherOn = false
    g.timeOfDay = 0.6
    step(g, 40, 1.0 / 30.0)
    check(monsters(g).isEmpty, "peaceful: no monsters at night")
}
do {
    // lamps keep monsters away: torches every few blocks along the whole ground
    let g = arena(80)
    let px = Int(g.pb.x)
    for x in stride(from: px - 80, through: px + 80, by: 6) { g.world.set(x, 99, .torch) }
    g.godMode = true
    g.timeOfDay = 0.6
    step(g, 60, 1.0 / 30.0)
    check(monsters(g).isEmpty && g.spawnLog["lit by a lamp", default: 0] > 0, "monsters don't come out where lamps light the ground (\(monsters(g).count), refused as lit \(g.spawnLog["lit by a lamp", default: 0]) times)")
}
do {
    // a floor of planks (a building) gets no monsters on it
    let g = arena(80)
    let px = Int(g.pb.x)
    for x in (px - 80)...(px + 80) { g.world.set(x, 100, .planks) }
    g.godMode = true
    g.timeOfDay = 0.6
    step(g, 40, 1.0 / 30.0)
    check(monsters(g).isEmpty && g.spawnLog["on a building", default: 0] > 0, "monsters don't spawn on building floors or roofs (\(monsters(g).count))")
}
do {
    // the player at a chunk border: spawning still works on both sides
    let g = arena(80)
    let cw = chunkW
    let border = (Int(g.pb.x) / cw) * cw
    g.pb.x = Double(border) + 0.02
    g.godMode = true
    g.timeOfDay = 0.6
    var left = 0, right = 0
    var seen = Set<Int>()
    var t = 0.0
    while t < 120 {
        g.tick(1.0 / 30.0); t += 1.0 / 30.0
        for m in monsters(g) where !seen.contains(m.id) { seen.insert(m.id); if m.b.x < g.pb.x { left += 1 } else { right += 1 } }
        // keep making room
        if monsters(g).count >= 4 { for m in monsters(g) { m.hp = 0; m.removed = true } }
    }
    check(left > 0 && right > 0, "standing on a chunk border, monsters come from both sides (\(left) left, \(right) right)")
}
do {
    // after saving and loading at night, monsters come again
    let g = world(biome: .plains)
    g.timeOfDay = 0.65
    step(g, 20, 1.0 / 30.0)
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    g2.viewW = 1100; g2.viewH = 800
    g2.settings.weatherOn = false
    g2.godMode = true
    check(g2.isNight && monsters(g2).isEmpty, "a loaded game starts at night with no stale monsters")
    step(g2, 40, 1.0 / 30.0)
    check(monsters(g2).count >= 2, "after loading, the night's monsters come again (\(monsters(g2).count))")
}
do {
    // caves: their own monsters, day or night
    let g = arena()
    let px = Int(g.pb.x)
    // a dark cave room deep below the arena
    let depth = 300
    for x in (px - 70)...(px + 70) { for y in (depth - 6)..<depth { g.world.set(x, y, .air) }; g.world.set(x, depth, .stone); g.world.set(x, depth - 7, .stone) }
    g.world.loadAround(centerX: px, radius: 8)
    g.pb.y = Double(depth)
    g.timeOfDay = 0.25
    g.godMode = true
    g.light.valid = false
    var kinds = Set<String>()
    var t = 0.0
    while t < 60 { g.tick(1.0 / 30.0); t += 1.0 / 30.0; for m in monsters(g) { kinds.insert(m.def.name) } }
    check(!kinds.isEmpty, "cave monsters still come out underground by day (\(kinds.sorted()))")
}
do {
    // the Umbral realm keeps its own creatures
    let g = world()
    g.debugSwitchDimension()
    g.godMode = true
    var kinds = Set<String>()
    var t = 0.0
    while t < 60 { g.tick(1.0 / 30.0); t += 1.0 / 30.0; for m in monsters(g) { kinds.insert(m.def.name) } }
    check(g.world.dim == .umbral && !kinds.isEmpty, "the Umbral realm spawns its creatures (\(kinds.sorted()))")
}
do {
    // the debug spawn test
    let g = arena()
    g.debugSpawnTest()
    check(g.isNight && monsters(g).count >= 2, "the debug spawn test makes it night and brings monsters (\(monsters(g).count))")
}

// ---------------------------------------------------------------- B. monsters that fight
print("== monsters attack")

/// a monster placed `dist` blocks from the player on open ground; returns damage taken, hits, the shortest
/// time between hits and whether a wind-up was seen before the first hit
func duel(_ kind: MobKind, _ dist: Double, secs: Double = 12, wall: Int = 0) -> (Double, Int, Double, Bool, Mob, Game) {
    let g = arena(40)
    g.timeOfDay = 0.25
    g.pauseSpawning = true
    let px = Int(floor(g.pb.x))
    if wall > 0 { for y in (100 - wall)..<100 { g.world.set(px + 5, y, .stone) } }
    var my = 100.0
    if mobDef(kind).flying { my -= 2 }
    let m = g.addMob(kind, g.pb.x + dist, my)
    m.homeX = m.b.x; m.homeY = my
    var dmg = 0.0, hits = 0
    var last = -10.0, minGap = 99.0
    var lastHP = g.hp
    var windup = false
    var t = 0.0
    while t < secs {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if m.st == 3 { windup = true }
        if g.hp < lastHP {
            dmg += lastHP - g.hp; hits += 1
            minGap = min(minGap, t - last); last = t
        }
        if g.hp < g.maxHP * 0.4 { g.hp = g.maxHP }
        lastHP = g.hp
        if m.hp <= 0 || m.removed { break }
    }
    return (dmg, hits, minGap, windup, m, g)
}

for k in [MobKind.zombie, .skeleton, .slime, .archer, .crawler, .golem, .bat, .wraith, .imp, .emberSlime, .cinderBat, .pirate, .pirateGunner, .scorpion, .grizzly, .tiger] {
    let r = duel(k, 8)
    check(r.0 > 0, "\(mobDef(k).name) 8 blocks away notices, closes in and hurts the player (\(Int(r.0)) damage in \(r.1) hits)")
    if r.1 > 1 { check(r.2 >= 0.5, "  ...with a pause between blows, never every frame (shortest gap \(f1(r.2)) s)") }
}
do {
    let r = duel(.zombie, 6)
    check(r.3 && r.0 > 0, "a zombie's swipe has a wind-up before it lands")
    // the swipe can be dodged: step back during the wind-up
    let g = arena(40)
    g.pauseSpawning = true
    let m = g.addMob(.zombie, g.pb.x + 1.2, 100)
    m.ai = .chase; m.cd = 0
    var dodged = true
    var t = 0.0
    var sawWindup = false
    while t < 3 {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if m.st == 3 && !sawWindup { sawWindup = true; g.stick = -1 }
        if g.hp < g.maxHP { dodged = false }
        if sawWindup && m.st == 0 { break }
    }
    g.stick = 0
    check(sawWindup && dodged, "stepping back during the wind-up dodges the swipe")
}
do {
    // over a two-block wall, melee and ranged both reach the player
    for k in [MobKind.zombie, .skeleton, .slime, .crawler, .archer, .pirateGunner] {
        let r = duel(k, 8, secs: 18, wall: 2)
        check(r.0 > 0, "\(mobDef(k).name) gets past or over a two-block wall to hurt the player (\(Int(r.0)))")
    }
    // a four-block wall stops a zombie: it backs off and tries again instead of pushing forever
    let r = duel(.zombie, 8, secs: 12, wall: 4)
    var regrouped = false
    let g = r.5, m = r.4
    var t = 0.0
    while t < 10 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; if m.ai == .retreat { regrouped = true } }
    check(r.0 == 0 && (regrouped || m.ai == .retreat || m.blockedT > 0), "a wall too high to climb: the zombie backs off to try again (no damage through it)")
}
do {
    // out of sight, it searches where the player was, then goes home
    let g = arena(40)
    g.pauseSpawning = true
    g.godMode = true
    let px = Int(floor(g.pb.x))
    let m = g.addMob(.skeleton, g.pb.x + 10, 100)
    m.homeX = m.b.x + 6
    step(g, 1.0)
    let saw = m.ai == .chase || m.ai == .alert
    // the player vanishes far away behind thick walls
    for y in 60..<100 { g.world.set(px - 3, y, .stone); g.world.set(px - 4, y, .stone) }
    g.pb.x = Double(px - 30)
    var searched = false, back = false
    var t = 0.0
    while t < 25 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; if m.ai == .search { searched = true }; if searched && (m.ai == .back || m.ai == .idle) { back = true; break } }
    check(saw && searched && back, "a monster that loses the player searches, then gives up and goes back (saw \(saw), searched \(searched), went back \(back))")
}
do {
    // the overlay's reasons
    let g = arena(40)
    g.pauseSpawning = true
    g.godMode = true
    let a = g.addMob(.archer, g.pb.x + 30, 100)
    let z = g.addMob(.zombie, g.pb.x - 6, 100)
    step(g, 0.5)
    check(a.why == .notSeen || a.why == .outOfRange, "an archer far off says it hasn't seen the player or is out of range (\(a.why.name))")
    step(g, 0.6)
    check(z.ai == .chase && (z.why == .outOfRange || z.why == .none || z.why == .cooldown), "a zombie on its way says out of range (\(z.ai.name), \(z.why.name))")
    g.settings.peaceful = true
    step(g, 0.2)
    check(z.why == .peaceful && z.ai != .chase, "peaceful: a monster stands down and says why")
}
do {
    // many at once: thinking stays cheap
    let g = arena(70)
    g.pauseSpawning = true
    g.godMode = true
    step(g, 1.0)
    let t0 = Date()
    step(g, 3.0)
    let base = Date().timeIntervalSince(t0) / 180.0 * 1000.0
    for i in 0..<40 {
        let s: Double = i % 2 == 0 ? 1 : -1
        let k: MobKind = [.zombie, .skeleton, .slime, .archer, .crawler][i % 5]
        _ = g.addMob(k, g.pb.x + s * Double(6 + i), 100)
    }
    let t1 = Date()
    step(g, 3.0)
    let with = Date().timeIntervalSince(t1) / 180.0 * 1000.0
    check(with - base < 12.0, "forty monsters fighting at once add little to a frame (\(f1(base)) -> \(f1(with)) ms, debug build)")
}

print(fails == 0 ? "ALL NIGHT AND AI TESTS PASSED" : "\(fails) FAILED, \(passes) passed")
