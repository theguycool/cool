import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f2(_ v: Double) -> String { return String(format: "%.2f", v) }

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
    g.maxHP = 400; g.hp = 400
    g.light.valid = false
    g.timeOfDay = 0.25
    return g
}
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }
/// a creature standing on the arena floor `dx` blocks from the player (box centre), facing `dir`
func put(_ g: Game, _ k: MobKind, _ dx: Double, dy: Double = 0, dir: Int = -1, hp: Double? = nil) -> Mob {
    let m = g.addMob(k, g.pb.x + dx, 100 + dy)
    m.b.vx = 0; m.b.vy = 0; m.dir = dir
    if let h = hp { m.maxHP = h; m.hp = h }
    g.mobGrid.rebuild(g.mobs)
    return m
}
/// distance from the shoulder at which a creature's near edge sits `edge` blocks away
func atEdge(_ k: MobKind, _ edge: Double) -> Double { return edge + mobDef(k).w * 0.5 }
func hold(_ g: Game, _ item: Item, extra: Int = 0) {
    g.inv.slots[0] = Stack(item: item, count: item.maxStack > 1 ? 10 : 1, extra: extra)
    g.setSel(0)
}
func aimAt(_ g: Game, _ m: Mob) { g.aimX = m.b.x; g.aimY = m.b.cy; g.aimValid = true }
/// press and hold the world for `secs` (fresh press on the first frame)
func pressHold(_ g: Game, _ secs: Double, aim: ((Game) -> Void)? = nil) {
    g.useHeld = true
    g.useWasHeld = false
    var t = 0.0
    while t < secs { aim?(g); g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    g.useHeld = false
    g.tick(1.0 / 60.0)
}

// ---------------------------------------------------------------- A. aim decides where a blow goes
print("== aim")
do {
    // facing right, a zombie on the left: tapping it swings left and hits it
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    g.facing = 1
    let z = put(g, .zombie, -atEdge(.zombie, 1.2), dir: 1)
    aimAt(g, z)
    let h0 = z.hp
    pressHold(g, 0.05)
    check(z.hp < h0 && g.facing == -1, "aiming left while facing right turns and hits the zombie on the left (hp \(Int(h0)) -> \(Int(z.hp)))")
}
do {
    // a bat two blocks up and one forward: aiming up at it with a sword hits it
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let bat = put(g, .bat, 1.0, dy: -2.6)
    bat.b.y = g.pb.y - 3.4
    aimAt(g, bat)
    let h0 = bat.hp
    pressHold(g, 0.05)
    check(bat.hp < h0, "aiming up at a bat over your head hits it (the old sword only reached chest height)")
    // straight overhead, but aimed straight ahead: the arc does not reach round to it
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .sword(.iron))
    let bat2 = put(g2, .bat, 0.0)
    bat2.b.y = g2.pb.y - 4.2
    g2.aimX = g2.pb.x + 4; g2.aimY = g2.shoulderY; g2.aimValid = true
    let h2 = bat2.hp
    pressHold(g2, 0.05)
    check(bat2.hp == h2, "a blow aimed straight ahead does not hit a bat hanging overhead")
}
do {
    // reach is the same however the attack starts: a tap on the foe, the action button, or a swing at air
    for (edge, expect) in [(2.8, true), (3.3, false)] {
        var results: [Bool] = []
        for mode in 0..<3 {
            let g = arena(); g.pauseMobs = true
            hold(g, .sword(.iron))
            let z = put(g, .zombie, atEdge(.zombie, edge))
            let h0 = z.hp
            switch mode {
            case 0:
                aimAt(g, z); pressHold(g, 0.05)
            case 1:
                actState.held = true
                g.applyActButton(); g.tick(1.0 / 60.0); g.applyActButton(); g.tick(1.0 / 60.0)
                actState.held = false
                g.applyActButton(); g.tick(1.0 / 60.0)
            default:
                g.aimX = g.pb.x + 6; g.aimY = g.shoulderY; g.aimValid = true
                g.swingEmpty(.sword(.iron))
            }
            results.append(z.hp < h0)
        }
        check(results.allSatisfy { $0 == expect }, "a zombie \(edge) blocks away is \(expect ? "hit" : "missed") by a sword the same way by tap, action button and free swing (\(results))")
    }
}
do {
    // no hitting through walls
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let wx = Int(floor(g.pb.x)) + 1
    for y in 96..<100 { g.world.set(wx, y, .stone) }
    let z = put(g, .zombie, 2.2)
    aimAt(g, z)
    let h0 = z.hp
    g.swingEmpty(.sword(.iron))
    check(z.hp == h0, "a sword does not cut through a stone wall to the zombie behind it")
}

// ---------------------------------------------------------------- B. hits, misses, crowds
print("== hits and misses")
do {
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let zs = [1.3, 2.0, 2.7].map { put(g, .zombie, atEdge(.zombie, $0) - 0.3) }
    g.aimX = g.pb.x + 3; g.aimY = g.shoulderY; g.aimValid = true
    g.swingEmpty(.sword(.iron))
    check(g.lastStrikeHits == 3 && zs.allSatisfy { $0.hp < $0.maxHP }, "a sword sweep hits all three zombies in front (\(g.lastStrikeHits) hits)")
    check(g.floats.contains { $0.text == "x3" }, "hitting three at once says so (x3)")
    check(g.hitStopT > 0 && !g.slashes.isEmpty && g.slashes.last!.hit, "a landed blow freezes the action for a moment and leaves a bright trail")
    // the freeze holds creatures still, briefly
    let z = zs[0]
    z.b.vx = 5
    let x0 = z.b.x
    g.pauseMobs = false
    g.tick(1.0 / 60.0)
    let frozenMove = abs(z.b.x - x0)
    step(g, 0.2)
    check(frozenMove < 0.01 && g.hitStopT <= 0, "creatures hold still during the hit freeze, which ends within a fifth of a second")
}
do {
    // a tap on a foe that is out of reach still swings (feedback) and shows "miss"
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let z = put(g, .zombie, atEdge(.zombie, 3.8))
    aimAt(g, z)
    let h0 = z.hp
    pressHold(g, 0.05)
    check(z.hp == h0 && g.swingT > 0 && g.floats.contains { $0.text == "miss" }, "tapping a zombie just out of reach swings and shows \"miss\"")
}
do {
    // holding on empty ground swings once, not over and over
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    g.aimX = g.pb.x + 3; g.aimY = g.shoulderY; g.aimValid = true
    var swings = 0
    g.useHeld = true; g.useWasHeld = false
    for _ in 0..<90 { let before = g.useCD; g.tick(1.0 / 60.0); if g.useCD > before + 0.1 { swings += 1 } }
    g.useHeld = false; g.tick(1.0 / 60.0)
    check(swings == 1, "holding a sword on empty ground swings once, not again and again (\(swings) swings in 1.5 s)")
    // with a foe in reach, holding keeps attacking at the weapon's own rate
    let z = put(g, .zombie, atEdge(.zombie, 1.5), hp: 999)
    var hits = 0
    var last = z.hp
    g.useHeld = true; g.useWasHeld = false
    for _ in 0..<90 { aimAt(g, z); g.tick(1.0 / 60.0); if z.hp < last { hits += 1; last = z.hp } }
    g.useHeld = false; g.tick(1.0 / 60.0)
    let expect = Int(1.5 / Item.sword(.iron).meleeCooldown)
    check(abs(hits - expect) <= 1, "holding on a zombie in reach keeps swinging at the sword's rate (\(hits) hits in 1.5 s, cooldown \(Item.sword(.iron).meleeCooldown))")
}

// ---------------------------------------------------------------- C. weapon behaviour
print("== weapon behaviour")
do {
    // spear: a band along the aim, two foes deep
    let g = arena(); g.pauseMobs = true
    let zs = [1.2, 2.0, 2.6].map { put(g, .zombie, atEdge(.zombie, $0)) }
    g.aimX = g.pb.x + 5; g.aimY = g.shoulderY; g.aimValid = true
    g.swingEmpty(.spear(.iron))
    let hit = zs.filter { $0.hp < $0.maxHP }.count
    check(hit == 2 && zs[2].hp == zs[2].maxHP, "a spear thrust runs through the two nearest of three zombies (hit \(hit))")
    let g2 = arena(); g2.pauseMobs = true
    let far = put(g2, .zombie, atEdge(.zombie, 3.6))
    g2.aimX = g2.pb.x + 5; g2.aimY = g2.shoulderY; g2.aimValid = true
    g2.swingEmpty(.spear(.iron))
    check(far.hp < far.maxHP, "the spear reaches a zombie 3.6 blocks out")
}
do {
    // knife: every third blow in a quick run lands double
    let g = arena(); g.pauseMobs = true
    hold(g, .knife(.iron))
    let z = put(g, .zombie, atEdge(.zombie, 1.0), dir: -1, hp: 999)
    let base = Item.knife(.iron).meleeDamage
    var dmg: [Double] = []
    for _ in 0..<3 {
        let h = z.hp
        aimAt(g, z)
        g.swingEmpty(.knife(.iron))
        dmg.append(h - z.hp)
        g.clock += 0.3
    }
    let firstTwoOK = dmg[0] >= base * 0.99 && dmg[1] >= base * 0.99 && dmg[0] <= base * 1.51 && dmg[1] <= base * 1.51
    check(firstTwoOK && abs(dmg[2] - base * 2) < 0.01, "a knife's third quick stab lands double (\(dmg.map { f1($0) }), base \(f1(base)))")
    // ...but not after a pause
    let g2 = arena(); g2.pauseMobs = true
    let z2 = put(g2, .zombie, atEdge(.zombie, 1.0), dir: -1, hp: 999)
    var d2: [Double] = []
    for _ in 0..<3 { let h = z2.hp; aimAt(g2, z2); g2.swingEmpty(.knife(.iron)); d2.append(h - z2.hp); g2.clock += 1.0 }
    check(d2[2] <= base * 1.51, "the run resets after a pause (third stab \(f1(d2[2])))")
    // backstab: a zombie facing away takes half as much again
    let g3 = arena(); g3.pauseMobs = true
    let z3 = put(g3, .zombie, atEdge(.zombie, 1.0), dir: 1, hp: 999)
    aimAt(g3, z3)
    let h3 = z3.hp
    g3.swingEmpty(.knife(.iron))
    check(h3 - z3.hp >= base * 1.49, "a knife in the back of a zombie that faces away cuts deep (\(f1(h3 - z3.hp)) vs \(f1(base)))")
}
do {
    // club: daze stops a zombie attacking for a moment; no stun lock
    let g = arena()
    g.pauseMobs = false
    hold(g, .club(.wooden))
    let z = put(g, .zombie, atEdge(.zombie, 0.4), hp: 999)
    aimAt(g, z)
    g.swingEmpty(.club(.wooden))
    check(z.daze > 0.3, "a club leaves the zombie dazed (\(f2(z.daze)) s)")
    let hp0 = g.hp
    // the blow's knockback carries it back a little first; after that it does not walk
    step(g, 0.2)
    let x0 = z.b.x
    step(g, 0.2)
    check(g.hp == hp0 && abs(z.b.x - x0) < 0.25, "a dazed zombie stands reeling and does not attack (moved \(f2(abs(z.b.x - x0))), hp \(Int(hp0)) -> \(Int(g.hp)))")
    step(g, 0.3)
    g.useCD = 0
    aimAt(g, z)
    g.swingEmpty(.club(.wooden))
    check(z.daze == 0 && z.dazeGuard > 0, "it cannot be dazed again straight away (no stun-locking)")
    var hit = false
    var t = 0.0
    while t < 4 && !hit { g.tick(1.0 / 60.0); t += 1.0 / 60.0; if g.hp < hp0 { hit = true } }
    check(hit, "once it recovers, the zombie attacks again (enemies stay dangerous, hit after \(f1(t)) s)")
    // bosses shrug it off
    let gb = arena(); gb.pauseMobs = true
    let boss = put(gb, .bearBoss, atEdge(.bearBoss, 0.5))
    boss.persistent = true
    aimAt(gb, boss)
    gb.swingEmpty(.club(.mace))
    check(boss.daze == 0, "a boss cannot be dazed")
}
do {
    // hammer: the blow lands after its wind-up, and only if it is still in hand
    let g = arena(); g.pauseMobs = true
    hold(g, .hammer(.iron))
    let z = put(g, .zombie, atEdge(.zombie, 1.4))
    aimAt(g, z)
    g.useHeld = true; g.useWasHeld = false
    g.tick(1.0 / 60.0)
    let atStart = z.hp
    step(g, 0.25)
    g.useHeld = false
    check(atStart == z.maxHP && z.hp < z.maxHP, "a hammer winds up, then the blow lands (hp \(Int(atStart)) then \(Int(z.hp)))")
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .hammer(.iron))
    g2.inv.slots[1] = Stack(item: .sword(.iron), count: 1)
    let z2 = put(g2, .zombie, atEdge(.zombie, 1.4))
    aimAt(g2, z2)
    g2.useHeld = true; g2.useWasHeld = false
    g2.tick(1.0 / 60.0)
    g2.useHeld = false
    g2.setSel(1)
    step(g2, 0.3)
    check(z2.hp == z2.maxHP, "switching weapons mid wind-up drops the blow")
    // heavy weapons slow you while they swing
    let g3 = arena(); g3.pauseMobs = true
    hold(g3, .hammer(.iron))
    g3.aimX = g3.pb.x + 3; g3.aimY = g3.shoulderY; g3.aimValid = true
    g3.swingEmpty(.hammer(.iron))
    g3.swingT = 0.42
    var tt = 0.0; let xa = g3.pb.x
    while tt < 0.35 { g3.stick = 1; g3.tick(1.0 / 60.0); tt += 1.0 / 60.0 }
    let slow = g3.pb.x - xa
    let g4 = arena(); g4.pauseMobs = true
    hold(g4, .sword(.iron))
    var t4 = 0.0; let xb = g4.pb.x
    while t4 < 0.35 { g4.stick = 1; g4.tick(1.0 / 60.0); t4 += 1.0 / 60.0 }
    let fast = g4.pb.x - xb
    check(slow < fast * 0.8, "swinging a hammer slows you down (\(f2(slow)) vs \(f2(fast)) blocks)")
}

// ---------------------------------------------------------------- D. every weapon can be equipped, used and connects
print("== every weapon")
func ammoFor(_ it: Item) -> [(Item, Int)] {
    switch it {
    case .bow: return [(.ammo(.arrow), 30)]
    case .sling: return [(.block(.stone), 30)]
    case .gun(let g):
        if let a = g.ammo { return [(.ammo(a), 40)] }
        return []
    default: return []
    }
}
let weapons: [Item] = [.sword(.iron), .spear(.iron), .hammer(.iron), .knife(.iron), .club(.wooden), .club(.studded), .club(.mace),
                       .relic(.moonDagger), .relic(.emberCleaver), .relic(.quakeMaul),
                       .bow, .sling, .gun(.pistol), .gun(.rifle), .gun(.crossbow), .gun(.arbalest), .gun(.blunderbuss), .gun(.repeater), .gun(.stormRod),
                       .gadget(.bomb), .gadget(.fireFlask)]
for it in weapons {
    let g = arena(); g.pauseMobs = true
    let ranged = it.isRanged
    var extra = 0
    if case .gun(let gt) = it { extra = gt.magazine }
    hold(g, it, extra: extra)
    for (a, n) in ammoFor(it) { _ = g.inv.add(a, n) }
    let dist: Double
    switch it {
    case .gun(.blunderbuss): dist = 4.0
    case .gadget: dist = 6.0
    default: dist = ranged ? 9.0 : atEdge(.zombie, it.meleeReach * 0.7)
    }
    let z = put(g, .zombie, dist, hp: 999)
    var hits = 0
    var last = z.hp
    g.useHeld = true; g.useWasHeld = false
    var t = 0.0
    var needsPress = false
    if case .gun(let gt) = it { needsPress = gt.needsPress }
    var frame = 0
    while t < 4.0 {
        aimAt(g, z)
        if case .gadget = it { g.aimY = z.b.y - 0.3 }
        // heavy guns take a fresh tap for each shot: lift the finger for a frame now and then
        if needsPress { g.useHeld = frame % 40 != 39 }
        g.tick(1.0 / 60.0)
        frame += 1
        if z.hp < last { hits += 1; last = z.hp }
        if case .gadget = it, t > 0.1 { g.useHeld = false }
        t += 1.0 / 60.0
    }
    g.useHeld = false; g.tick(1.0 / 60.0)
    let selOK = g.heldItem == it || it.maxStack > 1
    check(selOK && hits >= 1 && z.hp < 999, "\(it.name): equipped and used, it connects with a zombie \(f1(dist)) blocks away (\(hits) damaging hits, \(Int(999 - z.hp)) damage in 4 s)")
}

// ---------------------------------------------------------------- E. ranged specifics
print("== ranged")
do {
    // a crossbow bolt flies far and flat and passes through one foe into a second
    let g = arena(); g.pauseMobs = true
    hold(g, .gun(.crossbow), extra: 1)
    let a = put(g, .zombie, 12, hp: 999), b = put(g, .zombie, 14, hp: 999)
    g.aimX = a.b.x; g.aimY = a.b.cy; g.aimValid = true
    pressHold(g, 0.05)
    step(g, 1.0)
    check(a.hp < 999 && b.hp < 999, "a crossbow bolt hits a zombie 12 blocks off and runs on into the one behind it")
    check(g.reloadT > 0 || g.inv.slots[0]!.extra == 1 || g.inv.total(.ammo(.bolt)) == 0, "the crossbow re-cocks by itself after a shot when bolts are carried")
    // no bolts: it says so
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .gun(.crossbow), extra: 0)
    g2.aimX = g2.pb.x + 5; g2.aimY = g2.shoulderY; g2.aimValid = true
    pressHold(g2, 0.05)
    check(g2.message?.contains("bolts") ?? false, "with no bolts the crossbow says so (\(g2.message ?? "-"))")
}
do {
    // blunderbuss: a cone of pellets catches several foes close up, but not far ones
    let g = arena(); g.pauseMobs = true
    hold(g, .gun(.blunderbuss), extra: 1)
    // a zombie straight ahead, and another behind it standing a block higher on a ledge: the pellets
    // that spread upward pass over the first and catch the second
    let lx = Int(floor(g.pb.x + 5.5))
    for x in (lx - 1)...(lx + 1) { g.world.set(x, 99, .stone) }
    let zs = [put(g, .zombie, 3.5, hp: 999)]
    let second = put(g, .zombie, 5.5, hp: 999)
    second.b.y = 99
    g.aimX = g.pb.x + 4; g.aimY = g.pb.y - 1.2; g.aimValid = true
    pressHold(g, 0.05)
    step(g, 0.5)
    let n = (zs + [second]).filter { $0.hp < 999 }.count
    check(n == 2, "a blunderbuss blast catches both foes in its cone, the near one and the one on the ledge behind (\(n) of 2)")
    check(zs[0].b.vx > 3 || zs[0].b.x > g.pb.x + 3.3, "and throws the zombie back hard")
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .gun(.blunderbuss), extra: 1)
    let far = put(g2, .zombie, 16, hp: 999)
    aimAt(g2, far)
    pressHold(g2, 0.05)
    step(g2, 1.0)
    check(far.hp == 999, "...but its pellets are spent before they reach a zombie 16 blocks away")
}
do {
    // storm rod: leaps between foes, weaker each time, recharges by itself
    let g = arena(); g.pauseMobs = true
    hold(g, .gun(.stormRod), extra: 5)
    let zs = [4.0, 7.0, 10.0, 13.0, 25.0].map { put(g, .zombie, $0, hp: 999) }
    aimAt(g, zs[0])
    pressHold(g, 0.05)
    let dmg = zs.map { 999 - $0.hp }
    check(dmg[0] > 0 && dmg[1] > 0 && dmg[2] > 0 && dmg[3] > 0 && dmg[4] == 0, "the storm rod's lightning leaps through four zombies, not to one far off (\(dmg.map { Int($0) }))")
    check(dmg[0] > dmg[3], "each leap is weaker (\(Int(dmg[0])) then \(Int(dmg[3])))")
    let left = g.inv.slots[0]!.extra
    step(g, GunType.stormRod.reloadTime + 0.2)
    check(g.inv.slots[0]!.extra == left + 1, "it recharges a strike by itself after \(GunType.stormRod.reloadTime) s (\(left) -> \(g.inv.slots[0]!.extra))")
    // a foe standing in water takes more
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .gun(.stormRod), extra: 5)
    let wz = put(g2, .zombie, 4.0, hp: 999)
    for x in Int(floor(wz.b.x)) - 1...Int(floor(wz.b.x)) + 1 { for y in 97..<100 { g2.world.set(x, y, .water) } }
    g2.tick(1.0 / 60.0)
    wz.b.inWater = true
    aimAt(g2, wz)
    let h = wz.hp
    g2.fireStormRod()
    check(h - wz.hp >= GunType.stormRod.damage * 1.45, "lightning hits a zombie standing in water half as hard again (\(f1(h - wz.hp)))")
}
do {
    // fire flask: a burning patch that burns what stands in it
    let g = arena(); g.pauseMobs = true
    hold(g, .gadget(.fireFlask))
    g.inv.slots[0]!.count = 3
    let zs = [put(g, .zombie, 6.0, hp: 999), put(g, .zombie, 7.0, hp: 999)]
    g.aimX = g.pb.x + 6.5; g.aimY = 99.0; g.aimValid = true
    pressHold(g, 0.05)
    step(g, 2.0)
    check(!g.fireZones.isEmpty || zs.allSatisfy { $0.hp < 999 }, "a thrown fire flask bursts into a patch of fire")
    check(zs.allSatisfy { $0.hp < 999 }, "both zombies standing in it burn (\(zs.map { Int(999 - $0.hp) }) damage)")
    check(g.inv.slots[0]!.count == 2, "it used one flask")
}
do {
    // sling: stones from the bag; none, and it says so
    let g = arena(); g.pauseMobs = true
    hold(g, .sling)
    _ = g.inv.add(.block(.stone), 5)
    let z = put(g, .zombie, 7, hp: 999)
    aimAt(g, z)
    pressHold(g, 0.05)
    step(g, 1.5)
    check(g.inv.total(.block(.stone)) == 4 && z.hp < 999, "tapping a zombie 7 blocks off, the sling lobs one stone from the bag onto it (\(Int(999 - z.hp)) damage)")
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .sling)
    g2.aimX = g2.pb.x + 5; g2.aimY = g2.shoulderY; g2.aimValid = true
    pressHold(g2, 0.05)
    check(g2.projectiles.isEmpty && (g2.message?.contains("stones") ?? false), "with no stones the sling does nothing and says why")
}

do {
    // lobbed and thrown shots come down on the spot tapped, near or far, up or down
    var worst = 0.0
    for (dx, dy) in [(4.0, 0.0), (8.0, -2.0), (-6.0, 1.0), (10.0, 0.0), (3.0, -3.0)] {
        for kind in [0, 1] {
            let g = arena(); g.pauseMobs = true
            hold(g, kind == 0 ? .sling : .gadget(.fireFlask))
            _ = g.inv.add(.block(.stone), 5)
            g.aimX = g.pb.x + dx; g.aimY = g.pb.y - 1.0 + dy; g.aimValid = true
            g.facing = dx >= 0 ? 1 : -1
            g.useHeld = true; g.useWasHeld = false
            g.tick(1.0 / 60.0)
            g.useHeld = false
            guard var p = g.projectiles.last else { worst = 99; continue }
            // fly it without collisions and find how close it passes to the spot
            var best = 99.0
            for _ in 0..<400 {
                p.vy += p.gravity / 240.0; p.x += p.vx / 240.0; p.y += p.vy / 240.0
                best = min(best, hypot(p.x - g.aimX, p.y - g.aimY))
            }
            worst = max(worst, best)
        }
    }
    check(worst < 0.3, "the sling and fire flask arcs pass within \(f2(worst)) blocks of the spot tapped, near and far, above and below")
}

// ---------------------------------------------------------------- F. controls
print("== controls")
do {
    // with a weapon out, tapping a foe in a doorway attacks instead of opening the door
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let dx = Int(floor(g.pb.x)) + 2
    g.world.set(dx, 99, .doorOpen); g.world.set(dx, 98, .doorOpen)
    let z = put(g, .zombie, Double(dx) + 0.5 - g.pb.x)
    g.pointerDown(z.b.x, z.b.cy)
    g.tick(1.0 / 60.0); g.tick(1.0 / 60.0)
    g.pointerUp()
    g.tick(1.0 / 60.0)
    check(g.world.tile(dx, 99) == .doorOpen && z.hp < z.maxHP, "a tap on a zombie in a doorway attacks it, the door stays as it was")
    // without a foe there, the same tap still works the door
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .sword(.iron))
    let d2 = Int(floor(g2.pb.x)) + 2
    g2.world.set(d2, 99, .doorOpen); g2.world.set(d2, 98, .doorOpen)
    g2.pointerDown(Double(d2) + 0.5, 99.5)
    g2.tick(1.0 / 60.0)
    g2.pointerUp()
    check(g2.world.tile(d2, 99) == .doorClosed, "with nothing in the way, tapping the door shuts it")
}
do {
    // a panel opening mid-press drops every held control; nothing carries on afterwards
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    actState.held = true
    g.stick = 1; g.jumpHeld = true
    g.applyActButton(); g.tick(1.0 / 60.0)
    g.showInventory = true
    g.tick(1.0 / 60.0)
    check(!actState.held && !g.useHeld && g.stick == 0 && !g.jumpHeld, "opening the bag mid-attack releases the action button, the stick and jump")
    g.showInventory = false
    let x0 = g.pb.x
    let cd0 = g.useCD
    step(g, 1.0)
    check(abs(g.pb.x - x0) < 0.05 && g.useCD <= max(0, cd0), "after the bag closes the player neither walks nor attacks by themselves")
    // the same on death
    let g2 = arena(); g2.pauseMobs = true
    g2.stick = -1; actState.held = true
    g2.dead = true
    g2.tick(1.0 / 60.0)
    check(!actState.held && g2.stick == 0, "dying releases the held controls too")
    actState.held = false
}
do {
    // the action button picks the foe, not the cow standing nearer
    let g = arena(); g.pauseMobs = true
    hold(g, .sword(.iron))
    let cow = put(g, .cow, 1.6, hp: 999)
    let z = put(g, .zombie, 2.6, hp: 999)
    actState.held = true
    for _ in 0..<3 { g.applyActButton(); g.tick(1.0 / 60.0) }
    actState.held = false; g.applyActButton(); g.tick(1.0 / 60.0)
    check(z.hp < 999 && g.lockTarget === z, "the action button goes for the zombie, not the nearer cow (cow hp \(Int(cow.hp)))")
    // ranged: the foe in sight, not the closer one behind a wall
    let g2 = arena(); g2.pauseMobs = true
    hold(g2, .gun(.crossbow), extra: 1)
    _ = g2.inv.add(.ammo(.bolt), 10)
    let wx = Int(floor(g2.pb.x)) - 3
    for y in 90..<100 { g2.world.set(wx, y, .stone) }
    let hidden = put(g2, .zombie, -5, hp: 999)
    let seen = put(g2, .zombie, 9, hp: 999)
    g2.applyActButton()
    actState.held = true; g2.applyActButton()
    let t = g2.autoTarget(g2.heldItem)
    actState.held = false; g2.applyActButton()
    check(t === seen, "aiming a crossbow, the action button picks the zombie in sight over a closer one behind a wall (hidden \(Int(hidden.hp)))")
}
do {
    // one tap switches weapons; from a tool it goes back to the weapon used last
    let g = arena(); g.pauseMobs = true
    g.inv.slots[0] = Stack(item: .sword(.iron), count: 1)
    g.inv.slots[1] = Stack(item: .tool(.pickaxe, .iron), count: 1)
    g.inv.slots[2] = Stack(item: .bow, count: 1)
    g.inv.slots[4] = Stack(item: .gun(.crossbow), count: 1)
    g.setSel(0)
    var seq: [Int] = []
    for _ in 0..<3 { g.cycleWeapon(); seq.append(g.sel) }
    check(seq == [2, 4, 0], "the swap button steps sword -> bow -> crossbow -> sword (\(seq))")
    g.setSel(2)
    g.setSel(1)
    g.cycleWeapon()
    check(g.sel == 2, "from the pickaxe, one tap goes back to the bow used last (slot \(g.sel))")
    check(g.useLabel == "ATTACK", "the action button reads ATTACK with a weapon out")
    g.setSel(1)
    check(g.useLabel == "MINE", "...and MINE with a pickaxe")
}

// ---------------------------------------------------------------- G. enemies still fight fairly
print("== enemies")
for k in [MobKind.zombie, .skeleton, .crawler, .archer] {
    let g = arena()
    g.pauseMobs = false
    hold(g, .sword(.iron))
    let m = put(g, k, k == .archer ? 8 : 1.2, dir: -1)
    _ = m
    let hp0 = g.hp
    var t = 0.0
    while t < 6 && g.hp >= hp0 { g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    check(g.hp < hp0, "a \(mobDef(k).name) still lands its attacks on the player (after \(f1(t)) s)")
}
do {
    // silver charm: undead hit softer, and take more
    var taken: [Double] = []
    for charm in [false, true] {
        let g = arena()
        if charm { g.inv.armor[3] = Stack(item: .gear(.silverCharm), count: 1) }
        let z = put(g, .zombie, 1.0)
        var info = DamageInfo(amount: 8, type: .melee, source: .mob(z, .hostile))
        info.originX = z.b.x
        let h = g.hp
        _ = g.hurtPlayer(info)
        taken.append(h - g.hp)
    }
    check(taken[1] < taken[0] * 0.8, "wearing the silver charm, a zombie's blow hurts less (\(f1(taken[0])) -> \(f1(taken[1])))")
    var dealt: [Double] = []
    for (charm, k) in [(false, MobKind.zombie), (true, .zombie), (true, .slime)] {
        let g = arena(); g.pauseMobs = true
        if charm { g.inv.armor[3] = Stack(item: .gear(.silverCharm), count: 1) }
        let m = put(g, k, 1.5, hp: 999)
        var info = DamageInfo(amount: 10, type: .projectile, source: .player)
        info.originX = g.pb.x
        g.applyMobDamage(m, info)
        dealt.append(999 - m.hp)
    }
    check(abs(dealt[1] - dealt[0] * 1.25) < 0.01 && abs(dealt[2] - 10) < 0.01, "the charm adds a quarter against the undead only (\(dealt.map { f1($0) }))")
}

// ---------------------------------------------------------------- H. balance
print("== balance")
do {
    // sustained melee damage per second at iron: the families sit in one band, so none is simply best
    let fam: [Item] = [.sword(.iron), .spear(.iron), .hammer(.iron), .knife(.iron)]
    let dps = fam.map { $0.meleeDamage / $0.meleeCooldown * ($0.melee.combo ? 4.0 / 3.0 : 1.0) }
    check(dps.max()! / dps.min()! < 1.4, "iron sword, spear, hammer and knife (with its combo) deal damage per second within 40% of each other (\(dps.map { f1($0) }))")
    // the crude club line stays below the metal weapons of its stage but is worth having early
    let wood = Item.club(.wooden).meleeDamage / Item.club(.wooden).meleeCooldown
    let woodSword = Item.sword(.wood).meleeDamage / Item.sword(.wood).meleeCooldown
    let mace = Item.club(.mace).meleeDamage / Item.club(.mace).meleeCooldown
    let ironSword = Item.sword(.iron).meleeDamage / Item.sword(.iron).meleeCooldown
    check(wood < woodSword * 1.0 && wood > woodSword * 0.7 && mace < ironSword, "clubs trade damage for the daze (wooden \(f1(wood)) vs wooden sword \(f1(woodSword)); mace \(f1(mace)) vs iron sword \(f1(ironSword)))")
    // relics are strong but do not outclass the top crafted tiers
    let mythSword = Item.sword(.mythril).meleeDamage / Item.sword(.mythril).meleeCooldown
    for r in Relic.allCases {
        let it = Item.relic(r)
        let d = it.meleeDamage / it.meleeCooldown * (it.melee.combo ? 4.0 / 3.0 : 1.0)
        check(d > ironSword && d < mythSword, "\(it.name) (\(f1(d)) per second) beats iron (\(f1(ironSword))) but stays under a mythril sword (\(f1(mythSword)))")
    }
    // ranged sustained damage (shots and reloads) sits in one band too
    func sustained(_ g: GunType) -> Double {
        let per: Double = g == .blunderbuss ? g.damage * 7 : g.damage
        let cycle: Double = Double(g.magazine) * g.cooldown + g.reloadTime
        return per * Double(g.magazine) / cycle
    }
    let guns: [GunType] = [.pistol, .rifle, .crossbow, .arbalest, .blunderbuss, .repeater]
    let gd = guns.map { sustained($0) }
    check(gd.max()! / gd.min()! < 1.6, "pistol, rifle, crossbows, blunderbuss and repeater have sustained damage within a band (\(zip(guns, gd).map { "\($0.0.name) \(f1($0.1))" }))")
}

// ---------------------------------------------------------------- I. saving the new items
print("== saving")
do {
    var inv = Inventory()
    let items: [(Item, Int, Int)] = [(.knife(.gold), 1, 0), (.club(.mace), 1, 0), (.relic(.quakeMaul), 1, 0), (.sling, 1, 0),
                                     (.gun(.arbalest), 1, 1), (.gun(.stormRod), 1, 3), (.ammo(.bolt), 64, 0), (.gadget(.fireFlask), 7, 0),
                                     (.mat(.bronzeBar), 12, 0), (.mat(.amethyst), 5, 0)]
    for (i, (it, n, ex)) in items.enumerated() { inv.slots[i] = Stack(item: it, count: n, extra: ex) }
    inv.armor[4] = Stack(item: .gear(.silverCharm), count: 1)
    let data = try! JSONEncoder().encode(inv)
    let back = try! JSONDecoder().decode(Inventory.self, from: data)
    var same = true
    for i in 0..<items.count where back.slots[i] != inv.slots[i] { same = false }
    check(same && back.armor[4]?.item == .gear(.silverCharm), "new weapons, ammo, loaded charges and gear save and load unchanged")
}

print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL COMBAT TESTS PASSED" : "SOME COMBAT TESTS FAILED")
