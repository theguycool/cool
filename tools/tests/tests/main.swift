import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double) -> Bool { return abs(a - b) <= eps }

/// survival game on a flat stone arena, nothing spawning on its own
func arena(_ seed: UInt64 = 4242) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 5)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.hp = g.maxHP
    g.light.valid = false
    return g
}
func step(_ g: Game, _ secs: Double) { var t = 0.0; while t < secs { g.tick(1.0 / 60.0); t += 1.0 / 60.0 } }
func mob(_ g: Game, _ k: MobKind, _ dx: Double) -> Mob {
    let m = g.addMob(k, g.pb.x + dx, 100)
    g.mobGrid.rebuild(g.mobs)
    return m
}

// ---------------------------------------------------------------- determinism
print("== world generation")
do {
    // ore is now spread differently in every world (less iron, new ores), so the check is on the shape:
    // every block that is not rock or ore must match the original generator exactly, and rock and ore
    // must sit in the same places (the hash counts them as one kind of block)
    let rockish: Set<String> = ["Stone", "Slate", "Deep Rock", "Sandstone", "Coal Ore", "Copper Ore", "Iron Ore", "Gold Ore", "Diamond Ore", "Mythril Ore", "Tin Ore", "Saltpeter", "Silver Ore", "Amethyst Geode"]
    var h: UInt64 = 1469598103934665603
    for seed in [UInt64(12345), 777, 9] {
        let wg = WorldGen(seed: seed, infinite: seed != 9, rareChance: 0.28, genVersion: 1)
        for cx in [-40, -3, 0, 5, 77, 130] {
            for b in generateChunk(wg, .overworld, cx).tiles {
                let n: UInt64 = rockish.contains(Tile.make(b).name) ? 255 : UInt64(b)
                h = (h ^ n) &* 1099511628211
            }
        }
    }
    check(h == 8710469465003374273, "version 1 terrain keeps the original generator's exact shape (old saves); only the ore in the rock is redistributed")
    var a: UInt64 = 1, b: UInt64 = 1
    for pass in 0..<2 {
        let wg = WorldGen(seed: 31337, infinite: true, rareChance: 0.28)
        var hh: UInt64 = 1469598103934665603
        // generate out of order the second time: results must not depend on generation order
        let order = pass == 0 ? [-20, -1, 0, 3, 40, 41] : [41, 3, -20, 40, 0, -1]
        var per: [Int: UInt64] = [:]
        for cx in order {
            var x: UInt64 = 1469598103934665603
            for t in generateChunk(wg, .overworld, cx).tiles { x = (x ^ UInt64(t)) &* 1099511628211 }
            per[cx] = x
        }
        for cx in per.keys.sorted() { hh = (hh ^ per[cx]!) &* 1099511628211 }
        if pass == 0 { a = hh } else { b = hh }
    }
    check(a == b, "version 2 generation is deterministic and independent of chunk order")
    var worst = 0
    for (seed, inf) in [(UInt64(12345), true), (777, true), (9, false), (424242, false), (31337, true), (5, true), (2024, true), (88, false)] {
        let wg = WorldGen(seed: seed, infinite: inf, rareChance: 0.28)
        var best = Int.max
        var x = 0
        while x < 2000 && best == Int.max {
            for sx in [wg.spawnX - x, wg.spawnX + x] {
                if !inf && (sx < 0 || sx >= wg.width) { continue }
                if wg.colBase(sx).biome == .ocean { best = x }
            }
            x += 4
        }
        worst = max(worst, best)
    }
    check(worst <= 800, "every tested world has an ocean within 800 blocks of spawn (furthest \(worst))")
}

// ---------------------------------------------------------------- damage system
print("== damage")
do {
    let g = arena()
    let pig = mob(g, .pig, 3)
    var info = DamageInfo(amount: 5, type: .melee, source: .player)
    info.key = 77; info.cooldown = 0.5
    let hp0 = pig.hp
    check(g.applyMobDamage(pig, info), "player melee hits a pig")
    check(!g.applyMobDamage(pig, info), "the same swing cannot hit the same pig twice")
    check(near(pig.hp, hp0 - 5, 0.01), "pig lost exactly 5 hp")
    step(g, 0.6)
    check(g.applyMobDamage(pig, info), "after the cooldown the same key can hit again")

    let wolf = mob(g, .wolf, -3)
    wolf.tame = true
    var arrow = DamageInfo(amount: 6, type: .projectile, source: .player)
    arrow.key = 99
    check(!g.applyMobDamage(wolf, arrow), "player arrows do not hurt a tamed wolf")

    let z1 = mob(g, .zombie, 6), z2 = mob(g, .zombie, 7)
    let zsrc = DamageSource.mob(z1, g.faction(of: z1))
    var zhit = DamageInfo(amount: 4, type: .melee, source: zsrc)
    zhit.key = 5
    check(!g.applyMobDamage(z2, zhit), "a zombie's aimed attack does not hurt another zombie")
    let pig2 = mob(g, .pig, 4)
    check(g.applyMobDamage(pig2, { var i = zhit; i.key = 6; return i }()), "a zombie can hurt a pig")
    var zarea = DamageInfo(amount: 4, type: .explosion, source: zsrc)
    zarea.key = 7
    check(g.applyMobDamage(z2, zarea), "area damage from a zombie does hit its own kind")
    check(!g.applyMobDamage(z1, { var i = zarea; i.key = 8; return i }()), "nothing damages itself")

    // falloff and line of sight
    let g2 = arena()
    let a = mob(g2, .cow, 1.5), b = mob(g2, .cow, 4.0)
    let ah = a.hp, bh = b.hp
    var boom = DamageInfo(amount: 20, type: .explosion, source: .environment)
    boom.key = 1234
    g2.damageArea(g2.pb.x, 99.0, radius: 5, boom, falloff: true, lineOfSight: true)
    check(ah - a.hp > bh - b.hp && bh - b.hp > 0, String(format: "explosion falloff: near cow lost %.1f, far cow lost %.1f", ah - a.hp, bh - b.hp))
    let c = mob(g2, .cow, -4.0)
    let wx = Int(floor(g2.pb.x)) - 2
    for y in 95..<100 { g2.world.set(wx, y, .stone) }
    let ch = c.hp
    var boom2 = boom; boom2.key = 1235
    g2.damageArea(g2.pb.x, 99.0, radius: 5, boom2, falloff: true, lineOfSight: true)
    check(near(c.hp, ch, 0.001), "a wall between the blast and a cow protects it")

    // player damage, kill credit
    let g3 = arena()
    let hp1 = g3.hp
    var hit = DamageInfo(amount: 3, type: .melee, source: .environment)
    hit.key = 42
    check(g3.hurtPlayer(hit), "environment damage hurts the player")
    check(g3.hp < hp1, "player hp went down")
    let sheep = mob(g3, .sheep, 3)
    var poke = DamageInfo(amount: 1, type: .melee, source: .player); poke.key = 500
    g3.applyMobDamage(sheep, poke)
    let kills0 = g3.kills
    var fin = DamageInfo(amount: 100, type: .lava, source: .environment); fin.key = 501
    g3.applyMobDamage(sheep, fin)
    check(g3.kills == kills0 + 1, "lava finishing off a sheep the player hit still credits the player")
    let lone = mob(g3, .sheep, -3)
    var fin2 = fin; fin2.key = 502
    g3.applyMobDamage(lone, fin2)
    check(g3.kills == kills0 + 1, "a creature lava kills on its own is not credited to the player")
}

// ---------------------------------------------------------------- hazards
print("== hazards")
do {
    let g = arena()
    let cow = mob(g, .cow, 6)
    let imp = mob(g, .imp, 9)
    let px = Int(floor(g.pb.x))
    for x in (px + 4)...(px + 11) { g.world.set(x, 99, .lava) }
    g.mobGrid.rebuild(g.mobs)
    let ch = cow.hp, ih = imp.hp
    step(g, 1.5)
    check(cow.hp < ch, String(format: "a cow in lava takes damage (%.0f -> %.0f)", ch, cow.hp))
    check(near(imp.hp, ih, 0.001), "an imp (heat immune) takes no lava damage")

    let g2 = arena()
    let pig = mob(g2, .pig, 5)
    let sx = Int(floor(pig.b.x))
    // pen it in so it cannot wander out from under the sand
    for y in 97...99 { g2.world.set(sx - 1, y, .stone); g2.world.set(sx + 1, y, .stone) }
    pig.b.x = Double(sx) + 0.5
    let top = Int(floor(pig.b.top)) - 6
    for k in 0..<2 { g2.world.set(sx, top + k, .sand) }
    g2.checkFalling(sx, top + 1)
    let ph = pig.hp
    step(g2, 2.0)
    check(pig.hp < ph || pig.removed, "falling sand hurts the pig it lands on")
    check(g2.fallingBlocks.isEmpty, "falling sand settles")

    let g3 = arena()
    let chick = mob(g3, .chicken, 4)
    let cx = Int(floor(chick.b.x))
    g3.world.set(cx, 99, .spikes)
    let chh = chick.hp
    step(g3, 1.0)
    check(chick.hp < chh || chick.hp <= 0, "spikes hurt a chicken standing on them")

    let g4 = arena()
    let goat = mob(g4, .cow, 3)
    goat.b.y = 70; goat.b.vy = 0
    let gh = goat.hp
    step(g4, 2.5)
    check(goat.hp < gh, String(format: "a long fall hurts a cow (%.0f -> %.0f)", gh, goat.hp))
}

// ---------------------------------------------------------------- bow and projectiles
print("== projectiles")
do {
    let g = arena()
    let target = mob(g, .pig, 8)
    target.b.vx = 0
    let th = target.hp
    var p = Projectile(kind: .arrow, x: g.pb.x + 0.5, y: 99.4, vx: 60, vy: 0, dmg: 6, fromPlayer: true, gravity: 0)
    p.source = .player; p.uid = g.newID()
    g.projectiles.append(p)
    step(g, 0.4)
    check(target.hp < th, "a fast arrow (60 blocks/s) hits a pig 8 blocks away instead of tunnelling through it")
    let g2 = arena()
    let wall = Int(floor(g2.pb.x)) + 4
    for y in 95..<100 { g2.world.set(wall, y, .stone) }
    let behind = mob(g2, .pig, 7)
    let bh = behind.hp
    var p2 = Projectile(kind: .arrow, x: g2.pb.x + 0.5, y: 99.4, vx: 60, vy: 0, dmg: 6, fromPlayer: true, gravity: 0)
    p2.source = .player; p2.uid = g2.newID()
    g2.projectiles.append(p2)
    step(g2, 0.3)
    check(near(behind.hp, bh, 0.001), "an arrow stops at a wall and does not hit the pig behind it")
    step(g2, 6)
    check(g2.projectiles.isEmpty, "stuck arrows expire")
}

// ---------------------------------------------------------------- inventory
print("== inventory")
do {
    let g = arena()
    g.inv = Inventory()
    g.inv.slots[12] = Stack(item: .mat(.coal), count: 50)
    g.inv.slots[13] = Stack(item: .mat(.coal), count: 30)
    g.dragStack(from: .inv(12), to: .inv(13))
    let max = Item.mat(.coal).maxStack
    check(g.inv.slots[13]?.count == min(80, max) && (g.inv.slots[12]?.count ?? 0) == 80 - min(80, max), "dragging coal onto coal merges up to the stack limit (\(g.inv.slots[13]?.count ?? 0) + \(g.inv.slots[12]?.count ?? 0))")
    g.inv.slots[20] = Stack(item: .sword(.iron), count: 1)
    g.inv.slots[21] = Stack(item: .bow, count: 1)
    g.dragStack(from: .inv(20), to: .inv(21))
    check(g.inv.slots[21]?.item == .sword(.iron) && g.inv.slots[20]?.item == .bow, "dragging onto a different item swaps them")
    g.dragStack(from: .inv(20), to: .armor(0))
    check(g.inv.slots[20]?.item == .bow && g.inv.armor[0] == nil, "a bow dragged onto the helmet slot stays where it was")
    g.inv.slots[25] = Stack(item: .armor(.head, .iron), count: 1)
    g.dragStack(from: .inv(25), to: .armor(0))
    check(g.inv.armor[0]?.item == .armor(.head, .iron) && g.inv.slots[25] == nil, "a helmet dragged onto the helmet slot is equipped")
    let drops0 = g.drops.count
    g.dragStack(from: .inv(21), to: .drop)
    check(g.inv.slots[21] == nil && g.drops.count == drops0 + 1, "dragging onto DROP throws the stack into the world")
    check(g.carry == nil, "the hand is empty after every drag")
    // sort keeps the hotbar, merges and groups
    g.inv.slots[0] = Stack(item: .tool(.pickaxe, .stone), count: 1)
    g.inv.slots[30] = Stack(item: .mat(.coal), count: 5)
    g.inv.slots[35] = Stack(item: .block(.dirt), count: 10)
    g.inv.slots[38] = Stack(item: .sword(.wood), count: 1)
    let total0 = g.inv.total(.mat(.coal))
    g.sortBag()
    check(g.inv.slots[0]?.item == .tool(.pickaxe, .stone), "sorting leaves the hotbar alone")
    check(g.inv.total(.mat(.coal)) == total0, "sorting never loses items")
    check(g.inv.slots[10]?.item == .sword(.wood), "weapons sort first in the bag")
    var gaps = false, seenEmpty = false
    for i in 10..<g.inv.slots.count { if g.inv.slots[i] == nil { seenEmpty = true } else if seenEmpty { gaps = true } }
    check(!gaps, "sorted bag has no gaps")
    // chest drag and quick stack
    let cxp = Int(floor(g.pb.x)) + 2, cyp = 99
    g.world.set(cxp, cyp, .chest)
    g.world.setChestItems(cxp, cyp, [Stack(item: .block(.dirt), count: 5)])
    g.openChest = IntPair(x: cxp, y: cyp)
    let dirt0 = g.inv.total(.block(.dirt))
    g.quickStack()
    check(g.inv.total(.block(.dirt)) == 0 && g.world.chestItems(cxp, cyp).reduce(0) { $0 + ($1.item == .block(.dirt) ? $1.count : 0) } == dirt0 + 5, "quick stack moves matching bag items into the chest")
    g.dragStack(from: .chest(0), to: .inv(39))
    check(g.inv.slots[39]?.item == .block(.dirt), "dragging from the chest into the bag works")
    check(g.world.chestItems(cxp, cyp).isEmpty, "chest is empty after taking its only stack")
}

// ---------------------------------------------------------------- entity cleanup
print("== entities")
do {
    let g = arena()
    for i in 0..<20 { _ = mob(g, i % 2 == 0 ? .zombie : .pig, Double(i) - 10) }
    g.spawnParticles(g.pb.x, 99, 0xFFFFFF, 30, 3, 1, 0)
    g.spawnDrop(Stack(item: .mat(.coal), count: 1), g.pb.x + 2, 98, 0, 0)
    var p = Projectile(kind: .arrow, x: g.pb.x, y: 98, vx: 5, vy: 0, dmg: 1, fromPlayer: true, gravity: 0)
    p.uid = 1
    g.projectiles.append(p)
    let k = g.mobs[0]
    g.debugSelected = k
    g.debugDeleteAllEntities(includeVehicles: true)
    let c = g.entityCounts()
    check(g.mobs.isEmpty && c.projectiles == 0 && c.drops == 0 && c.particles == 0 && c.vehicles == 0, "delete all entities clears creatures, projectiles, drops, particles and vehicles")
    check(g.debugSelected == nil && g.activeBoss == nil && g.rex == nil, "no references to deleted entities remain")
    step(g, 1.0)
    check(g.mobs.isEmpty, "nothing comes back immediately (spawning paused, lairs suppressed)")

    let g2 = arena()
    let cow = mob(g2, .cow, 3)
    g2.killMob(cow, true)
    step(g2, 0.3)
    check(g2.mobs.contains { $0 === cow }, "a killed cow stays briefly for its death animation")
    step(g2, 0.7)
    check(!g2.mobs.contains { $0 === cow }, "and is removed after it")

    // bear lair boss: suppressed after delete-all until the player leaves
    let g3 = arena()
    g3.debugToLair(.bear)
    step(g3, 0.5)
    let had = g3.mobs.contains { $0.kind == .bearBoss }
    g3.debugDeleteAllEntities(includeVehicles: false)
    step(g3, 1.0)
    check(had && !g3.mobs.contains { $0.kind == .bearBoss }, "the bear boss does not respawn right after delete-all")
}

// ---------------------------------------------------------------- clouds, camera
print("== clouds and camera")
do {
    let a = CloudField.clouds(99, 1, 12.5, 0, 400, fill: 0.7).map { $0.x }
    let b = CloudField.clouds(99, 1, 12.5, 0, 400, fill: 0.7).map { $0.x }
    check(!a.isEmpty && a == b, "clouds are deterministic for a seed and time")
    let g = arena()
    g.settings.camDeadZone = 1.0
    step(g, 1)
    let cx0 = g.camX
    g.pb.x += 0.6
    g.updateCamera(1.0 / 60.0)
    check(near(g.camX, cx0, 0.25), "small moves inside the dead zone barely move the camera")
    g.settings.camSmoothOn = false
    g.pb.x += 10
    g.updateCamera(1.0 / 60.0)
    check(abs(g.camX - (g.pb.x + g.camLead)) <= 1.01, "with smoothing off the camera snaps to the player")
}

print("")
print(fails == 0 ? "ALL \(passes) TESTS PASSED" : "\(fails) FAILED, \(passes) passed")
