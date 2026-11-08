import SwiftUI
import Foundation
// The gameplay overhaul, phase 1: dropped items, the bag (merging, filters, the creative return), live
// crafting counts, the item browser and debug give, the held attack stick, neutral animals, armour and
// creature damage, the bow zombie, doors that close behind the player, the direct camera, clouds at any
// zoom, and fireflies that keep their place.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f2(_ v: Double) -> String { return String(format: "%.2f", v) }

/// A flat stone floor at row 100, nothing spawning, daytime
func arena(_ seed: UInt64 = 4242, mode: GameMode = .survival) -> Game {
    let g = Game(mode: mode, infinite: true, seed: seed, settings: Settings())
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
    g.timeOfDay = 0.25
    return g
}
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }
func put(_ g: Game, _ k: MobKind, _ dx: Double, dir: Int = -1) -> Mob {
    let m = g.addMob(k, g.pb.x + dx, 100)
    m.b.vx = 0; m.b.vy = 0; m.dir = dir
    g.mobGrid.rebuild(g.mobs)
    return m
}

// ---------------------------------------------------------------- 1. a stack thrown away stays down
print("== dropped items")
do {
    let g = arena()
    g.inv = Inventory()
    g.carry = Stack(item: .block(.dirt), count: 20)
    g.dropCarried()
    step(g, 3.0)
    check(g.inv.total(.block(.dirt)) == 0 && g.drops.count == 1, "a stack the player throws away is not picked straight back up while they stand there (\(g.inv.total(.block(.dirt))) in the bag after 3 s)")
    let home: Double = g.pb.x
    g.pb.x = home + 8
    step(g, 0.3)
    g.pb.x = home
    step(g, 2.0)
    check(g.inv.total(.block(.dirt)) == 20 && g.drops.isEmpty, "after walking off and coming back the player picks it up as usual (\(g.inv.total(.block(.dirt))))")
    g.spawnDrop(Stack(item: .mat(.coal), count: 3), g.pb.x + 1.5, 99.5, 0, 0)
    step(g, 1.5)
    check(g.inv.total(.mat(.coal)) == 3, "loot that was not thrown by the player is still pulled in and picked up (\(g.inv.total(.mat(.coal))))")
}

// ---------------------------------------------------------------- 2. the bag
print("== the bag")
do {
    var inv = Inventory()
    inv.slots[3] = Stack(item: .mat(.coal), count: 10)
    inv.slots[15] = Stack(item: .mat(.coal), count: 30)
    inv.slots[22] = Stack(item: .mat(.coal), count: 50)
    inv.slots[30] = Stack(item: .block(.dirt), count: 5)
    let ms: Int = Item.mat(.coal).maxStack
    let n: Int = inv.mergeStacks()
    let coalSlots: Int = inv.slots.compactMap { $0 }.filter { $0.item == .mat(.coal) }.count
    check(n > 0 && inv.total(.mat(.coal)) == 90 && coalSlots == (90 + ms - 1) / ms && inv.slots[3]?.count == min(90, ms), "STACK folds partial stacks into the first one (90 coal in \(coalSlots) slots, the hotbar's stack topped up to \(inv.slots[3]?.count ?? 0))")
    var inf = Inventory()
    inf.slots[0] = Stack(item: .ammo(.arrow), count: 10)
    inf.slots[1] = Stack(item: .ammo(.arrow), count: 10, extra: 0, inf: [Infusion.reinforced.rawValue])
    _ = inf.mergeStacks()
    check(inf.slots[1]?.count == 10 && inf.slots[0]?.count == 10, "an infused stack never merges with a plain one")
    check(Item.block(.dirt).bagGroup == 0 && Item.tool(.pickaxe, .iron).bagGroup == 1 && Item.sword(.iron).bagGroup == 2 && Item.armor(.chest, .iron).bagGroup == 3
          && Item.mat(.coal).bagGroup == 4 && Item.food(.bread).bagGroup == 5, "each kind of item falls in its bag filter group")
    let g = arena(mode: .creative)
    g.carry = Stack(item: .block(.stone), count: 64)
    g.discardCarried()
    check(g.carry == nil && g.drops.isEmpty, "in creative, RETURN puts the held stack back in the menu (nothing dropped)")
    let s = arena()
    s.carry = Stack(item: .block(.stone), count: 4)
    s.discardCarried()
    check(s.carry == nil && s.drops.count == 1, "in survival nothing vanishes: it is thrown down instead")
    s.inv.slots[5] = Stack(item: .block(.dirt), count: 8)
    s.dragStack(from: .inv(5), to: .trash)
    check(s.inv.slots[5] == nil && s.drops.count == 2, "dragging onto RETURN in survival throws the stack down as well")
}

// ---------------------------------------------------------------- 3. live crafting counts
print("== crafting counts")
do {
    let g = arena()
    g.inv = Inventory()
    guard let r = RecipeBook.all.first(where: { $0.out == .block(.workbench) }) ?? RecipeBook.all.first(where: { !$0.cost.isEmpty }) else { fatalError("no recipe") }
    let before: RecipeRow = RecipeRow.live(g, r)
    let item: Item = r.cost[0].item
    _ = g.inv.add(item, r.cost[0].n + 3)
    let after: RecipeRow = RecipeRow.live(g, r)
    check(before.have[0] == 0 && after.have[0] == r.cost[0].n + 3, "a crafting row carries what the bag holds, so it changes as soon as the bag does (\(before.have[0]) then \(after.have[0]) \(item.name))")
    for c in r.cost { _ = g.inv.add(c.item, c.n) }
    let ready: RecipeRow = RecipeRow.live(g, r)
    g.craftStation = .hand
    let canNow: Bool = g.canCraft(r)
    check(ready.ok == canNow, "and whether it can be made right now (\(ready.ok))")
    let held: Int = g.inv.total(item)
    if canNow { g.craft(r) }
    let used: RecipeRow = RecipeRow.live(g, r)
    check(!canNow || used.have[0] == held - r.cost[0].n, "crafting shows the ingredients used straight away (\(held) then \(used.have[0]))")
}

// ---------------------------------------------------------------- 4. the item browser and debug give
print("== item browser")
do {
    let g = arena()
    let items: [Item] = g.creativeItems()
    let iron: [Item] = ItemBrowser.filter(items, "iron", 0)
    check(!iron.isEmpty && iron.allSatisfy { $0.name.lowercased().contains("iron") }, "searching finds items by name (\(iron.count) with \"iron\")")
    let tools: [Item] = ItemBrowser.filter(items, "", 2)
    check(!tools.isEmpty && tools.allSatisfy { $0.bagGroup == 1 }, "a group shows only its own kind (\(tools.count) tools)")
    check(ItemBrowser.filter(items, "", 0).count == items.count, "ALL shows everything (\(items.count))")
    g.inv = Inventory()
    g.debugGive(.mat(.ironBar), 150)
    check(g.inv.total(.mat(.ironBar)) == 150, "the debug menu gives any item, as many as asked (\(g.inv.total(.mat(.ironBar))) iron bars)")
    g.debugGive(.sword(.diamond), 3)
    check(g.inv.total(.sword(.diamond)) == 3, "single items come one to a slot (\(g.inv.total(.sword(.diamond))) diamond swords)")
}

// ---------------------------------------------------------------- 5. the held attack stick
print("== held attack")
do {
    func swings(_ onStick: Bool) -> Int {
        let g = arena()
        g.inv.slots[0] = Stack(item: .sword(.iron), count: 1)
        g.setSel(0)
        actState.stickReleased(); actState.was = false
        var count: Int = 0
        var last: Double = 0
        var t: Double = 0
        while t < 3.0 {
            if onStick {
                actState.stickAt(0.9, 0)
                g.applyActButton()
            } else {
                g.touchActive = true
                g.aimX = g.pb.x + 1.5; g.aimY = g.pb.y - 1.2; g.aimValid = true
                g.useHeld = true
            }
            g.tick(1.0 / 60.0)
            if g.swingT > last + 0.01 { count += 1 }
            last = g.swingT
            t += 1.0 / 60.0
        }
        actState.stickReleased()
        g.touchActive = false
        g.useHeld = false
        return count
    }
    let held: Int = swings(true)
    let cd: Double = Item.sword(.iron).melee.cooldown
    let most: Int = Int(ceil(3.0 / max(0.05, cd))) + 1
    check(held >= 3 && held <= most, "holding the attack stick keeps swinging, at the sword's own pace (\(held) swings in 3 s, at most \(most) at \(f2(cd)) s each)")
    check(swings(false) <= 1, "a finger held on empty ground still does not waste swings")
}

// ---------------------------------------------------------------- 6. neutral animals, hostile monsters
print("== animals")
do {
    for k in [MobKind.bear, .elephant, .wolf, .grizzly, .polarBear, .tiger, .scorpion] {
        let g = arena()
        g.timeOfDay = 0.75
        let m = put(g, k, 2.5)
        let hp0: Double = g.hp
        step(g, 15.0)
        check(g.hp >= hp0 - 0.01, "\(mobDef(k).name) next to the player for 15 s leaves them alone (health \(f1(hp0)) then \(f1(g.hp)))")
        m.hp = m.maxHP
        g.hurtMob(m, 1, 1, 0, true)
        let hp1: Double = g.hp
        var t = 0.0
        while t < 12.0 && g.hp >= hp1 - 0.01 {
            if abs(m.b.x - g.pb.x) > 1.0 { m.b.x += (g.pb.x - m.b.x) * 0.02 }
            g.tick(1.0 / 60.0); t += 1.0 / 60.0
        }
        check(g.hp < hp1, "\(mobDef(k).name) fights back once the player hits it (\(f1(hp1 - g.hp)) damage after \(f1(t)) s)")
    }
    let g = arena()
    let z = put(g, .zombie, 3.0)
    z.ai = .chase
    let hp0: Double = g.hp
    step(g, 10.0)
    check(g.hp < hp0, "a zombie still attacks (\(f1(hp0 - g.hp)) damage in 10 s)")
}

// ---------------------------------------------------------------- 7. armour and creature damage
print("== armour and damage")
do {
    func blow(_ tier: Tier?) -> Double {
        let g = arena()
        g.inv.armor = [Stack?](repeating: nil, count: Inventory.armorSlots)
        if let t = tier {
            g.inv.armor[0] = Stack(item: .armor(.head, t), count: 1)
            g.inv.armor[1] = Stack(item: .armor(.chest, t), count: 1)
            g.inv.armor[2] = Stack(item: .armor(.legs, t), count: 1)
        }
        g.hp = 20; g.maxHP = 20; g.invuln = 0
        let z = put(g, .zombie, 0.3)
        var info = DamageInfo(amount: 10, type: .melee, source: .mob(z, .hostile))
        info.originX = z.b.x
        _ = g.hurtPlayer(info)
        return 20 - g.hp
    }
    let none: Double = blow(nil)
    let leather: Double = blow(.wood)
    let iron: Double = blow(.iron)
    let diamond: Double = blow(.diamond)
    let voidium: Double = blow(.voidium)
    print("   a 10-point blow: none \(f1(none)), leather \(f1(leather)), iron \(f1(iron)), diamond \(f1(diamond)), voidium \(f1(voidium))")
    check(none > leather && leather > iron && iron > diamond && diamond > voidium, "each better armour set takes clearly more off a blow")
    check(iron <= 6.0 && diamond <= 5.0, "iron armour takes off about 40%, diamond more than half (iron \(f1(iron)), diamond \(f1(diamond)) of 10)")
    check(voidium >= 2.0, "the best armour is not invincible (\(f1(voidium)) of 10 still gets through)")
    let g = arena()
    check(g.armorShare(1000) <= 0.8 + 1e-9, "armour never takes more than 80%")
    let weak: [MobKind] = [.zombie, .skeleton, .slime, .bat, .crawler, .archer]
    check(weak.allSatisfy { mobDef($0).dmg <= 5 }, "ordinary monsters hit for at most a quarter of the player's 20 health (\(weak.map { "\(mobDef($0).name) \(Int(mobDef($0).dmg))" }.joined(separator: ", ")))")
    let bosses: [MobKind] = [.bearBoss, .rex, .warden, .sentinel]
    check(bosses.allSatisfy { mobDef($0).dmg <= 13 }, "bosses hit hard but not for more than the player's whole health (\(bosses.map { "\(Int(mobDef($0).dmg))" }.joined(separator: ", ")))")
}

// ---------------------------------------------------------------- 8. the bow zombie
print("== bow zombie")
do {
    let d: MobDef = mobDef(.archer)
    check(d.name == "Bow Zombie" && d.behavior == .ranged && d.hostile, "the skeleton archer's place is taken by the Bow Zombie, a ranged monster")
    check(!MobKind.allCases.contains { mobDef($0).name == "Skeleton Archer" }, "no creature is a skeleton archer any more")
    check(mobDef(.skeleton).name == "Skeleton Knight", "the Skeleton Knight (sword and shield) is still there")
    let g = arena()
    g.timeOfDay = 0.75
    let a = put(g, .archer, 10.0)
    a.ai = .chase
    var shot: Bool = false
    var t = 0.0
    while t < 8.0 && !shot {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if g.projectiles.contains(where: { !$0.fromPlayer && $0.kind == .arrow }) { shot = true }
    }
    check(shot, "it shoots arrows at the player from a distance (after \(f1(t)) s)")
    let frames: [PixelBuf] = GameSprites.creatureFrames(.archer)
    check(!frames.isEmpty && frames[0].w > 0, "it has its own sprite frames (\(frames.count))")
}

// ---------------------------------------------------------------- 9. doors
print("== doors")
do {
    let g = arena()
    let dx: Int = Int(floor(g.pb.x)) + 3
    g.world.set(dx, 98, .doorClosed); g.world.set(dx, 99, .doorClosed)
    g.stick = 1.0
    var t = 0.0
    while t < 4.0 && g.pb.x < Double(dx) + 4.0 { g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    g.stick = 0
    let through: Bool = g.pb.x > Double(dx) + 2.0
    step(g, 1.5)
    check(through && g.world.tile(dx, 98) == .doorClosed && g.world.tile(dx, 99) == .doorClosed, "a door the player walks through closes behind them (through: \(through))")
    g.setDoor(dx, 99, open: true)
    step(g, 2.0)
    check(g.world.tile(dx, 99) == .doorOpen, "a door opened with a tap stays open")
}

// ---------------------------------------------------------------- 10. the camera, clouds and fireflies
print("== camera, clouds, fireflies")
do {
    let g = arena()
    g.settings.camDirect = true
    g.settings.camLookAhead = true
    g.settings.camDeadZone = 2.0
    step(g, 0.5)
    g.stick = 1.0
    step(g, 1.5)
    g.stick = 0
    step(g, 1.0)
    check(abs(g.camX - g.pb.x) < 0.25 && abs(g.camLead) < 0.05, "with direct follow the camera sits on the player: no dead zone, no look-ahead (off by \(f2(abs(g.camX - g.pb.x))))")
    var s = Settings()
    s.camDirect = true
    let data: Data = (try? JSONEncoder().encode(s)) ?? Data()
    let back: Settings? = try? JSONDecoder().decode(Settings.self, from: data)
    let old: Settings? = try? JSONDecoder().decode(Settings.self, from: Data("{\"tilePx\": 30}".utf8))
    check(back?.camDirect == true && old?.camDirect == false, "the setting is saved, and older settings without it read as off")
}
do {
    // fireflies: the same places in the world whether the player stands here or ten blocks away
    let g = arena()
    g.timeOfDay = 0.75
    g.settings.weatherOn = false
    g.weatherRain = 0
    let v: View2D = View2D(tp: 24, left: g.pb.x - 30, top: 70, wTiles: 60, hTiles: 40)
    let a: [(Double, Double, Double)] = WorldRenderer.fireflySpots(g, v)
    g.pb.x += 10
    let b: [(Double, Double, Double)] = WorldRenderer.fireflySpots(g, v)
    let same: Bool = a.count == b.count && zip(a, b).allSatisfy { abs($0.0 - $1.0) < 1e-9 && abs($0.1 - $1.1) < 1e-9 }
    check(same, "fireflies keep their places in the world when the player moves (\(a.count) of them, same spots: \(same))")
}

print("\n== done: \(passes) passed, \(fails) failed")
if fails == 0 { print("ALL \(passes) OVERHAUL CHECKS PASSED") } else { print("\(fails) FAILED, \(passes) passed") }
