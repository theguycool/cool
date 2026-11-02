import SwiftUI
import Foundation
// Potions, creature mutation, infusions and the modular exosuit: effects on the player and on creatures,
// throwing and bursting, the mutation limits, infusing and what infusions do, building, wearing,
// powering and saving a suit. The SwiftUI screens (the crucible and the assembly station) are
// compile-checked only; what they call is tested here.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}

// a scratch folder for the mod store (never the real one)
let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pralch-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

/// A flat stone floor at row 100 with open air above, the player in the middle, nothing spawning
func arena(mode: GameMode = .survival, seed: UInt64 = 5151) -> Game {
    ModRuntime.activate([], world: nil)
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
    g.maxHP = 20; g.hp = 20
    g.light.valid = false
    g.timeOfDay = 0.25
    g.settings.weatherOn = false
    return g
}
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func hold(_ g: Game, _ item: Item, _ n: Int = 1) {
    g.inv.slots[0] = Stack(item: item, count: n)
    g.setSel(0)
}
func aimAt(_ g: Game, _ x: Double, _ y: Double) { g.aimX = x; g.aimY = y; g.aimValid = true }
func run(_ g: Game, _ limit: Int, _ done: () -> Bool) -> Int {
    var n: Int = 0
    while n < limit && !done() { frame(g); n += 1 }
    return n
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { return abs(a - b) <= eps }
/// a creature that stands still (no AI moves it): for measuring
func dummy(_ g: Game, _ k: MobKind, _ x: Double, _ y: Double = 100) -> Mob {
    let m: Mob = g.addMob(k, x, y)
    m.persistent = true
    // creatures are found through a grid the game rebuilds every frame; a test acting at once rebuilds it
    g.mobGrid.rebuild(g.mobs)
    return m
}

// ---------------------------------------------------------------- stage 1: effects
print("== status effects")
do {
    let g = arena()
    check(!ModRuntime.shared.active, "this world has no mods (effects must work without them)")
    g.hp = 10
    // (hungry enough that natural healing stays out of the way)
    g.hunger = 10
    g.effects.add(.regen, 1.0, 5)
    frames(g, 60 * 3)
    check(g.hp >= 12.5 && g.hp <= 13.5, "regeneration heals about 1 a second in a world without mods (10 -> \(g.hp) in 3 s)")
    frames(g, 60 * 3)
    let afterRegen: Double = g.hp
    frames(g, 60 * 2)
    check(g.effects.value(.regen) == 0 && g.hp == afterRegen, "regeneration stops when its time runs out (\(afterRegen) stays \(g.hp))")
    // stacking: the strongest wins, time is refreshed, never added
    g.effects.add(.speed, 30, 90)
    g.effects.add(.speed, 30, 40)
    check(near(g.effects.value(.speed), 30) && near(g.effects.time[ModEffectKind.speed.rawValue], 90, 0.1), "a weaker or shorter dose of the same effect changes nothing (strength 30, 90 s)")
    g.effects.add(.speed, 60, 10)
    check(near(g.effects.value(.speed), 60) && near(g.effects.time[ModEffectKind.speed.rawValue], 90, 0.1), "a stronger dose takes over the strength and keeps the longer time")
    // every timed effect expires
    for k in [ModEffectKind.mining, .breathing, .nightVision, .luck, .featherfall, .warmth] { g.effects.add(k, 1, 1.0) }
    frames(g, 70)
    check([ModEffectKind.mining, .breathing, .nightVision, .luck, .featherfall, .warmth].allSatisfy { g.effects.value($0) == 0 }, "the new effects (mining, breathing, night vision, luck, slow falling, warmth) expire on time")
    // fire protection outside mod worlds
    g.playerBurn = 3
    g.effects.add(.fireproof, 1, 5)
    frames(g, 2)
    check(g.playerBurn == 0, "fire protection puts out flames in a world without mods")
}

// ---------------------------------------------------------------- stage 2: drinking
print("== drinking potions")
do {
    let g = arena()
    g.hp = 5
    hold(g, .potion(.mending), 3)
    g.drinkPotion(.mending)
    check(near(g.hp, 13) && g.inv.total(.potion(.mending)) == 2, "a Mending Draught heals 8 and is used up (5 -> \(g.hp))")
    check(g.mendCD > 9.0, "after mending, the body needs about 10 s before mending works fully again")
    g.hp = 5
    g.useCD = 0
    g.drinkPotion(.mending)
    check(near(g.hp, 8), "a second Mending Draught inside that time heals only a third (5 -> \(g.hp)): no endless instant healing")
    g.hp = g.maxHP
    g.useCD = 0
    let before: Int = g.inv.total(.potion(.mending))
    g.drinkPotion(.mending)
    check(g.inv.total(.potion(.mending)) == before, "a mending potion is not wasted at full health")
    // every drinkable gives its effect for its time
    var allOK: Bool = true
    var bad: [String] = []
    for p in Potion.allCases where !p.thrown {
        guard let e = p.effect else { continue }
        let h = arena()
        hold(h, .potion(p), 1)
        h.drinkPotion(p)
        let ok: Bool = near(h.effects.value(e.kind), e.amount) && near(h.effects.time[e.kind.rawValue], e.seconds, 0.1) && h.inv.total(.potion(p)) == 0
        if !ok { allOK = false; bad.append(p.name) }
    }
    check(allOK, "every drinkable potion gives its own effect, strength and time, and is used up \(bad)")
    check(Potion.allCases.allSatisfy { !$0.name.isEmpty && $0.color != 0 && !$0.blurb.isEmpty }, "every potion has a name, a colour and a line saying what it does")
    let names: Set<String> = Set(Potion.allCases.map { $0.name })
    check(names.count == Potion.allCases.count, "potion names are all different")
    // each potion has a recipe at the still, and its icon is drawn in its colour
    let missing: [Potion] = Potion.allCases.filter { p in !RecipeBook.all.contains { $0.out == .potion(p) && $0.station == .still } }
    check(missing.isEmpty, "every potion is brewed at the Alchemy Still \(missing.map { $0.name })")
    let ib: PixelBuf = itemBuf(.potion(.owlsight))
    check(ib.px.contains { $0 & 0xFFFFFF == Potion.owlsight.color }, "a potion's icon shows its colour")
}

print("== what drinks do")
do {
    // strength: harder blows
    let g = arena()
    let a: Mob = dummy(g, .pig, g.pb.x + 1.5)
    let b: Mob = dummy(g, .pig, g.pb.x + 1.5)
    a.maxHP = 500; a.hp = 500; b.maxHP = 500; b.hp = 500
    var info = DamageInfo(amount: 10, type: .melee, source: .player)
    info.originX = g.pb.x
    g.applyMobDamage(a, info)
    g.effects.add(.strength, 35, 60)
    g.applyMobDamage(b, info)
    check(near(500 - a.hp, 10, 0.6) && near(500 - b.hp, 13.5, 0.6), "Brawn Brew: blows land 35% harder (\(500 - a.hp) -> \(500 - b.hp))")
    // ironhide: less damage taken
    let h = arena()
    h.invuln = 0
    var hit = DamageInfo(amount: 10, type: .melee, source: .environment)
    hit.originX = h.pb.x
    _ = h.hurtPlayer(hit)
    let plain: Double = 20 - h.hp
    h.hp = 20; h.invuln = 0
    h.effects.add(.resistance, 30, 90)
    _ = h.hurtPlayer(hit)
    let guarded: Double = 20 - h.hp
    check(plain == 10 && guarded == 7, "Ironhide Tonic: 30% less damage (\(plain) -> \(guarded))")
    // emberward: no fire or lava damage
    h.hp = 20; h.invuln = 0
    h.effects.add(.fireproof, 1, 120)
    var fire = DamageInfo(amount: 6, type: .lava, source: .environment)
    fire.originX = h.pb.x
    check(!h.hurtPlayer(fire) && h.hp == 20, "Emberward Draught: lava does not hurt")
    // speed
    let s1 = arena()
    s1.keyR = true
    let x0: Double = s1.pb.x
    frames(s1, 60)
    let plainRun: Double = s1.pb.x - x0
    let s2 = arena()
    s2.effects.add(.speed, 30, 90)
    s2.keyR = true
    let x1: Double = s2.pb.x
    frames(s2, 60)
    let fastRun: Double = s2.pb.x - x1
    check(fastRun > plainRun * 1.2, "Quickstep Elixir: runs faster (\(String(format: "%.1f", plainRun)) -> \(String(format: "%.1f", fastRun)) blocks in 1 s)")
    // mining
    func mineTime(_ g: Game) -> Int {
        let tx: Int = Int(g.pb.x) + 1
        g.world.set(tx, 99, .stone)
        hold(g, .tool(.pickaxe, .stone))
        aimAt(g, Double(tx) + 0.5, 99.5)
        var n: Int = 0
        while g.world.tile(tx, 99) == .stone && n < 600 {
            g.mineStep(tx, 99, .pickaxe, .stone, 1.0 / 60.0)
            n += 1
        }
        return n
    }
    let m1 = arena()
    let tPlain: Int = mineTime(m1)
    let m2 = arena()
    m2.effects.add(.mining, 60, 120)
    let tFast: Int = mineTime(m2)
    check(Double(tFast) < Double(tPlain) * 0.7, "Prospector's Draught: mines faster (\(tPlain) -> \(tFast) frames for a stone block)")
    // breathing
    let w = arena()
    for x in (Int(w.pb.x) - 3)...(Int(w.pb.x) + 3) { for y in 95..<100 { w.world.set(x, y, .water) } }
    w.effects.add(.breathing, 1, 180)
    frames(w, 60 * 12)
    check(w.air >= 9.9, "Deepbreath Draught: under water the air never runs out (air \(w.air) after 12 s)")
    func swimRun(_ g: Game) -> Double {
        for x in (Int(g.pb.x) - 30)...(Int(g.pb.x) + 30) { for y in 92..<100 { g.world.set(x, y, .water) } }
        g.pb.y = 99
        frames(g, 30)
        g.keyR = true
        let x0: Double = g.pb.x
        frames(g, 60)
        return g.pb.x - x0
    }
    let sw1 = arena()
    let slowSwim: Double = swimRun(sw1)
    let sw2 = arena()
    sw2.effects.add(.breathing, 1, 180)
    let fastSwim: Double = swimRun(sw2)
    check(fastSwim > slowSwim * 1.3, "Deepbreath Draught: swims faster (\(String(format: "%.1f", slowSwim)) -> \(String(format: "%.1f", fastSwim)) blocks in 1 s)")
    // featherfall
    let f = arena()
    f.pb.y = 60
    f.effects.add(.featherfall, 1, 120)
    _ = run(f, 60 * 20) { f.pb.onGround }
    frames(f, 5)
    check(f.hp == 20, "Featherfall Tonic: a fall of 40 blocks does no harm")
    let f2 = arena()
    f2.pb.y = 60
    _ = run(f2, 60 * 20) { f2.pb.onGround }
    frames(f2, 5)
    check(f2.hp < 20, "(without it the same fall hurts: \(f2.hp))")
    // warmth
    let c = arena()
    c.effects.add(.warmth, 1, 240)
    check(c.coldGuard() == 0, "Hearthfire Tonic: no cold gets in")
    // night vision lifts the dark of a cave at night
    let n = arena()
    n.timeOfDay = 0.75
    for x in (Int(n.pb.x) - 30)...(Int(n.pb.x) + 30) { for y in 60..<99 { n.world.set(x, y, .stone) } }
    for x in (Int(n.pb.x) - 6)...(Int(n.pb.x) + 6) { for y in 94..<100 { n.world.set(x, y, .air) } }
    n.light.valid = false
    n.updateLight(0.1)
    func darkness(_ g: Game) -> Int { return g.lightDark.reduce(0) { $0 + Int($1 >> 24) } }
    let d0: Int = darkness(n)
    n.effects.add(.nightVision, 1, 180)
    n.light.valid = false
    n.lightTimer = 0
    n.updateLight(0.1)
    let d1: Int = darkness(n)
    check(d1 < d0, "Owlsight Draught: the dark is lifted (shade \(d0) -> \(d1))")
}

print("== luck")
do {
    let g = arena()
    hold(g, .tool(.pickaxe, .iron))
    var extra: Int = 0
    let tries: Int = 400
    for i in 0..<tries {
        let st: [Stack] = g.minedDrops(.coal, 10 + i, 90, true)
        if st.count > 1 { extra += 1 }
    }
    check(extra == 0, "no extra ore without luck")
    g.effects.add(.luck, 25, 150)
    extra = 0
    for i in 0..<tries {
        let st: [Stack] = g.minedDrops(.coal, 10 + i, 90, true)
        if st.count > 1 { extra += 1 }
    }
    let rate: Double = Double(extra) / Double(tries)
    check(rate > 0.17 && rate < 0.33, "Seeker's Tonic: about a quarter of ores give one more (\(String(format: "%.2f", rate)))")
    let stoneDrops: [Stack] = g.minedDrops(.stone, 5, 90, true)
    check(stoneDrops.count == 1, "luck does nothing for plain stone")
}

// ---------------------------------------------------------------- stage 2: throwing
print("== throwing potions")
do {
    let g = arena()
    hold(g, .potion(.searing), 4)
    let tx: Double = g.pb.x + 8
    aimAt(g, tx, 99.6)
    check(g.shotBallistics(.potion(.searing)).0 > 0 && Item.potion(.searing).isRanged, "a splash potion is aimed like a thrown weapon (the attack stick and the aiming arc)")
    g.useHeld = true
    check(!g.arrowPreview().isEmpty, "the aiming arc is shown while it is held")
    g.useHeld = false
    let foe: Mob = dummy(g, .pig, tx)
    foe.maxHP = 50; foe.hp = 50
    let far: Mob = dummy(g, .pig, tx + 9)
    far.maxHP = 50; far.hp = 50
    g.useCD = 0
    g.throwPotion(.searing)
    check(g.projectiles.count == 1 && g.projectiles[0].potion == Potion.searing.rawValue && g.inv.total(.potion(.searing)) == 3, "throwing launches a flask (one potion used)")
    let n: Int = run(g, 200) { g.projectiles.isEmpty }
    check(n < 200, "the flask flies and breaks (\(n) frames)")
    check(foe.hp < 50 && far.hp == 50, "the burst hurts what is within reach (\(50 - foe.hp)) and nothing beyond it")
    check(g.hp == 20, "the thrower's own harmful splash does not hurt them")
    if let r = g.rings.last { check(abs(r.x - tx) < 2.0, "it bursts where it was aimed (\(String(format: "%.1f", r.x)) for \(String(format: "%.1f", tx)))") } else { check(false, "a burst ring is drawn") }
    frames(g, 60)
    check(g.rings.isEmpty && g.projectiles.isEmpty, "nothing is left behind: the ring fades and the flask is gone")
}

print("== splash effects")
do {
    // line of sight: a wall shields a creature
    let g = arena()
    let x: Double = g.pb.x + 6
    let open: Mob = dummy(g, .pig, x - 1.5)
    let hidden: Mob = dummy(g, .pig, x + 1.8)
    for y in 95..<100 { g.world.set(Int(x) + 1, y, .stone) }
    open.maxHP = 50; open.hp = 50; hidden.maxHP = 50; hidden.hp = 50
    g.burstPotion(.searing, x, 99.2, direct: nil)
    check(open.hp < 50 && hidden.hp == 50, "a wall between the burst and a creature shields it")
    // pets are spared harm and get the help
    let p = arena()
    let pet: Mob = dummy(p, .wolf, p.pb.x + 3)
    pet.tame = true
    pet.maxHP = 30; pet.hp = 10
    let wild: Mob = dummy(p, .wolf, p.pb.x + 4)
    wild.maxHP = 30; wild.hp = 10
    p.hp = 10
    p.burstPotion(.mendingSplash, p.pb.x + 2, 99, direct: nil)
    check(near(pet.hp, 16) && wild.hp == 10 && near(p.hp, 16), "Mending Splash heals the player and their animals in reach, not wild creatures")
    p.burstPotion(.searing, p.pb.x + 3, 99, direct: nil)
    check(near(pet.hp, 16), "a harmful splash spares pets")
    p.burstPotion(.regrowthSplash, p.pb.x + 3, 99, direct: nil)
    check(pet.regenT > 0 && p.effects.value(.regen) > 0, "Regrowth Splash: the player and pets regenerate")
    // poison
    let q = arena()
    let boar: Mob = dummy(q, .pig, q.pb.x + 5)
    boar.maxHP = 50; boar.hp = 50
    let zed: Mob = dummy(q, .zombie, q.pb.x + 5.5)
    zed.maxHP = 50; zed.hp = 50
    q.burstPotion(.blight, q.pb.x + 5, 99, direct: nil)
    check(boar.poisonT > 7 && zed.poisonT == 0, "Blight Splash poisons a living creature; the undead are immune")
    frames(q, 60 * 5)
    let lost: Double = 50 - boar.hp
    check(lost >= 5 && lost <= 9, "poison hurts about 1.5 a second (\(lost) in 5 s)")
    frames(q, 60 * 5)
    let lost2: Double = 50 - boar.hp
    frames(q, 60 * 2)
    check(boar.poisonT <= 0 && near(50 - boar.hp, lost2), "poison wears off after its time and does no more harm")
    // slow
    let s = arena()
    let walker: Mob = s.addMob(.pig, s.pb.x + 10, 100)
    let walker2: Mob = s.addMob(.pig, s.pb.x - 10, 100)
    s.mobGrid.rebuild(s.mobs)
    walker.t2 = 5; walker.tx = walker.b.x + 40
    walker2.t2 = 5; walker2.tx = walker2.b.x - 40
    s.burstPotion(.mire, walker.b.x, 99, direct: nil)
    let wa: Double = walker.b.x
    let wb: Double = walker2.b.x
    frames(s, 60)
    let slowMoved: Double = abs(walker.b.x - wa)
    let freeMoved: Double = abs(walker2.b.x - wb)
    check(walker.slowT > 0 && slowMoved < freeMoved * 0.75, "Mire Splash: a bogged-down creature covers about half the ground (\(String(format: "%.1f", slowMoved)) vs \(String(format: "%.1f", freeMoved)))")
    // weakness
    let wk = arena()
    let brute: Mob = dummy(wk, .zombie, wk.pb.x + 1)
    var blow = DamageInfo(amount: 10, type: .melee, source: .mob(brute, .hostile))
    blow.originX = brute.b.x
    wk.invuln = 0
    _ = wk.hurtPlayer(blow)
    let full: Double = 20 - wk.hp
    wk.hp = 20; wk.invuln = 0
    wk.burstPotion(.enfeeble, brute.b.x, 99, direct: nil)
    var blow2 = DamageInfo(amount: 10, type: .melee, source: .mob(brute, .hostile))
    blow2.originX = brute.b.x
    _ = wk.hurtPlayer(blow2)
    let soft: Double = 20 - wk.hp
    check(brute.weakT > 0 && full == 10 && soft == 6, "Enfeebling Splash: the creature hits 40% softer (\(full) -> \(soft))")
    // smoke
    let sm = arena()
    let watcher: Mob = sm.addMob(.zombie, sm.pb.x + 8, 100)
    sm.mobGrid.rebuild(sm.mobs)
    watcher.losT = 0
    _ = sm.think(watcher, 1.0 / 60.0, 8, 0)
    let sawBefore: Bool = watcher.sees
    sm.burstPotion(.smoke, sm.pb.x, 99.5, direct: nil)
    watcher.losT = 0
    _ = sm.think(watcher, 1.0 / 60.0, 8, 0)
    check(sawBefore && !watcher.sees, "Smoke Flask: a monster can't see the player inside the cloud")
    frames(sm, 60 * 9)
    check(sm.smokes.isEmpty, "the smoke clears after its time (no lasting cloud)")
    // frost
    let fr = arena()
    let fx: Int = Int(fr.pb.x) + 6
    for x in (fx - 2)...(fx + 2) { for y in 97..<100 { fr.world.set(x, y, .water) } }
    let burner: Mob = dummy(fr, .pig, Double(fx) + 0.5, 97)
    burner.burn = 5
    fr.burstPotion(.frost, Double(fx) + 0.5, 97.0, direct: nil)
    var ice: Int = 0
    for x in (fx - 2)...(fx + 2) where fr.world.tile(x, 97) == .ice { ice += 1 }
    check(ice >= 3 && fr.world.tile(fx, 98) == .water, "Frost Splash: the surface of still water freezes (\(ice) blocks), the water below stays")
    check(burner.burn == 0 && burner.slowT > 0, "Frost Splash puts out a burning creature and slows it")
    // statuses on creatures run out
    let ex = arena()
    let t: Mob = dummy(ex, .pig, ex.pb.x + 4)
    t.slowT = 1; t.slowAmt = 0.5; t.weakT = 1; t.regenT = 1; t.regenRate = 1
    frames(ex, 80)
    check(t.slowT <= 0 && t.weakT <= 0 && t.regenT <= 0 && !t.hasStatus, "every effect on a creature runs out")
}

// ---------------------------------------------------------------- stage 3: mutation
print("== mutation")
do {
    let g = arena()
    let m: Mob = dummy(g, .zombie, g.pb.x + 8)
    let d: MobDef = mobDef(.zombie)
    let hp0: Double = m.maxHP
    check(g.mutate(m), "a dose of mutagen takes")
    check(m.mut == 1 && near(m.b.w, d.w * 2) && near(m.b.h, d.h * 2), "one dose: twice the size (\(m.b.w) x \(m.b.h))")
    check(near(m.maxHP, hp0 * 2) && near(m.hp, m.maxHP), "twice the health (\(hp0) -> \(m.maxHP))")
    check(near(m.dmgMul, 2), "twice the strength")
    let s0: SpriteSet = Art.shared.mobSet(m)
    let s1: SpriteSet = Art.shared.mutantSet(m)
    check(s0.w == s1.w && s0.h == s1.h, "it still looks like the same creature (same frames, turned colours)")
    let drawnH: Double = Double(s1.h) * s1.scale * g.drawScale(m)
    let normalH: Double = Double(s0.h) * s0.scale
    check(near(drawnH / normalH, m.b.h / d.h, 0.001), "the picture grows exactly as much as the hit box")
    // the blow it lands
    var blow = DamageInfo(amount: 3, type: .melee, source: .mob(m, .hostile))
    blow.originX = m.b.x
    g.invuln = 0
    _ = g.hurtPlayer(blow)
    check(g.hp == 14, "its blows land twice as hard (3 -> \(20 - g.hp))")
    // stacking
    _ = g.mutate(m)
    _ = g.mutate(m)
    check(m.mut == 3, "doses stack")
    check(m.b.w <= MutationLimits.maxW + 0.001 && m.b.h <= MutationLimits.maxH + 0.001, "size stays inside the body limits (\(m.b.w) x \(m.b.h))")
    check(near(m.b.w / d.w, m.b.h / d.h, 0.001) && near(g.drawScale(m), m.b.h / d.h, 0.001), "width and height grow together and match the drawing")
    check(near(m.maxHP, hp0 * 8), "health keeps doubling (x8 after 3 doses: \(m.maxHP))")
    check(m.dmgMul <= MutationLimits.maxDmgMul + 0.001 && d.dmg * m.dmgMul <= MutationLimits.maxBlow + 0.001, "strength stops at its caps (x\(m.dmgMul), a blow of \(d.dmg * m.dmgMul))")
    // overflow safety
    for _ in 0..<200 { _ = g.mutate(m) }
    check(m.mut == MutationLimits.maxStacks && m.maxHP <= MutationLimits.maxHP && m.maxHP.isFinite && m.b.w.isFinite && m.dmgMul.isFinite, "200 more doses: the counters and numbers stop at safe limits (\(m.mut) doses, \(m.maxHP) health)")
    check(!g.world.boxSolid(m.b.left + 0.02, m.b.top + 0.02, m.b.right - 0.02, m.b.y - 0.02), "the grown body is not inside the ground")
    // room to grow
    let t = arena()
    for x in (Int(t.pb.x) + 2)...(Int(t.pb.x) + 14) { for y in 90..<97 { t.world.set(x, y, .stone) } }
    let crawler: Mob = dummy(t, .pig, t.pb.x + 8)
    let ph: Double = mobDef(.pig).h
    for _ in 0..<4 { _ = t.mutate(crawler) }
    check(crawler.b.h <= 3.0 + 0.01 && near(crawler.b.h / ph, crawler.mutSize, 0.001), "in a low tunnel a creature only grows as far as there is room (\(String(format: "%.2f", crawler.b.h)) high in a 3-high gap)")
    check(crawler.maxHP > mobDef(.pig).hp * 8, "it still grows stronger where it can't grow bigger")
    // bosses
    let b = arena()
    let boss: Mob = dummy(b, .golem, b.pb.x + 10)
    _ = boss
    let bear: Mob = b.addMob(.bearBoss, b.pb.x + 12, 100)
    b.mobGrid.rebuild(b.mobs)
    let bhp: Double = bear.maxHP
    let bearDmg: Double = min(1.25, MutationLimits.maxBlow / mobDef(.bearBoss).dmg)
    check(bear.isBoss, "(the bear is a boss)")
    _ = b.mutate(bear)
    check(bear.mut == 1 && near(bear.maxHP, bhp * 1.5) && near(bear.dmgMul, max(1.0, bearDmg)) && near(bear.mutSize, 1.15), "a boss takes one milder dose: +50% health, up to +25% strength (no blow over the cap), 15% bigger (\(bear.maxHP / bhp), \(bear.dmgMul), \(bear.mutSize))")
    check(!b.mutate(bear) && bear.mut == 1, "a second dose on a boss does nothing")
    // the thrown mutagen hits the creature it lands on
    let th = arena()
    let target: Mob = dummy(th, .cow, th.pb.x + 7)
    hold(th, .potion(.mutagen), 2)
    aimAt(th, target.b.x, target.b.cy)
    th.throwPotion(.mutagen)
    _ = run(th, 200) { th.projectiles.isEmpty }
    check(target.mut == 1, "a thrown mutagen mutates the creature it hits")
    // its own AI and attacks still work
    let ai = arena()
    let z: Mob = ai.addMob(.zombie, ai.pb.x + 6, 100)
    z.persistent = true
    _ = ai.mutate(z)
    ai.monstersEnabled = true
    _ = run(ai, 60 * 12) { ai.hp < 20 }
    check(ai.hp < 20, "a mutated zombie still hunts and strikes the player (health \(ai.hp))")
    // loot
    let lt = arena()
    let cow: Mob = dummy(lt, .cow, lt.pb.x + 3)
    _ = lt.mutate(cow)
    _ = lt.mutate(cow)
    cow.lastHitByPlayer = lt.clock
    lt.killMob(cow, true)
    let glands: Int = lt.drops.filter { $0.stack.item == .mat(.mutantGland) }.reduce(0) { $0 + $1.stack.count }
    let meat: Int = lt.drops.filter { $0.stack.item == .food(.rawMeat) || $0.stack.item == .mat(.leather) }.count
    check(glands >= 1, "a mutated creature leaves mutant glands (\(glands))")
    check(meat >= 1, "and its normal loot")
    // many giants: physics and timing
    let pf = arena()
    var giants: [Mob] = []
    for i in 0..<MutationLimits.maxMutants {
        let gm: Mob = pf.addMob(.cow, pf.pb.x - 30 + Double(i) * 4, 100)
        for _ in 0..<5 { _ = pf.mutate(gm) }
        giants.append(gm)
    }
    let t0: Double = Date().timeIntervalSinceReferenceDate
    frames(pf, 300)
    let ms: Double = (Date().timeIntervalSinceReferenceDate - t0) * 1000.0 / 300.0
    let ok: Bool = giants.allSatisfy { g2 in g2.hp <= 0 || !pf.world.boxSolid(g2.b.left + 0.05, g2.b.top + 0.05, g2.b.right - 0.05, g2.b.y - 0.05) }
    check(ok, "16 giant creatures wander for 5 s without sinking into the ground")
    check(ms < 40, "16 giant creatures cost \(String(format: "%.2f", ms)) ms a frame (debug build)")
    // the mutant cap
    let cap = arena()
    for i in 0..<(MutationLimits.maxMutants + 6) {
        let cm: Mob = cap.addMob(.pig, cap.pb.x - 30 + Double(i) * 2, 100)
        _ = cap.mutate(cm)
    }
    let kept: Int = cap.mobs.filter { $0.mut > 0 && $0.persistent }.count
    check(kept <= MutationLimits.maxMutants, "at most \(MutationLimits.maxMutants) mutated creatures stay about (\(kept))")
}

print("== mutation saves")
do {
    let g = arena()
    let wild: Mob = dummy(g, .wolf, g.pb.x + 6)
    _ = g.mutate(wild)
    _ = g.mutate(wild)
    let pet: Mob = dummy(g, .wolf, g.pb.x - 4)
    pet.tame = true
    _ = g.mutate(pet)
    let sv: SaveData = g.makeSave()
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(sv))
    let h = Game.load(back, settings: Settings())
    let w2: Mob? = h.mobs.first { $0.kind == .wolf && !$0.tame && $0.mut > 0 }
    let p2: Mob? = h.mobs.first { $0.kind == .wolf && $0.tame }
    check(w2 != nil && w2!.mut == 2 && near(w2!.b.h, mobDef(.wolf).h * 4) && near(w2!.maxHP, wild.maxHP), "a mutated wild creature is saved and comes back as it was (2 doses, its size and health)")
    check(p2 != nil && p2!.mut == 1 && near(p2!.b.h, mobDef(.wolf).h * 2), "a mutated pet keeps its mutation")
}

// ---------------------------------------------------------------- stage 4-5: infusion
print("== infusing")
do {
    let g = arena()
    let sword: Stack = Stack(item: .sword(.iron), count: 1)
    check(sword.infuseProblem(.honed) == nil, "Honed goes on an iron sword")
    check(sword.infuseProblem(.haste) != nil, "Haste does not go on a sword (it is for tools)")
    check(Stack(item: .tool(.pickaxe, .iron), count: 1).infuseProblem(.quarry) != nil && Stack(item: .tool(.pickaxe, .diamond), count: 1).infuseProblem(.quarry) == nil,
          "Quarry needs a diamond pickaxe or better")
    check(Stack(item: .gun(.stormRod), count: 1).infuseProblem(.volatile) != nil, "the storm rod can't take Volatile")
    check(Stack(item: .mat(.coal), count: 5).infuseProblem(.honed) != nil, "materials can't be infused")
    check(infusionSlots(.sword(.wood)) == 1 && infusionSlots(.sword(.iron)) == 2 && infusionSlots(.sword(.voidium)) == 3, "better metals hold more infusions (wood 1, iron 2, voidium 3)")
    // the act itself
    g.inv.slots[5] = Stack(item: .sword(.wood), count: 1)
    g.inv.slots[6] = Stack(item: .compound(.honed), count: 2)
    g.inv.slots[7] = Stack(item: .compound(.keen), count: 1)
    let msg: String = g.infuse(slot: 5, .honed)
    check(g.inv.slots[5]?.has(.honed) == true && g.inv.total(.compound(.honed)) == 1, "infusing works the compound into the item where it lies (\(msg))")
    let msg2: String = g.infuse(slot: 5, .keen)
    check(g.inv.slots[5]?.has(.keen) == false && g.inv.total(.compound(.keen)) == 1, "a full item refuses another, and the compound is kept (\(msg2))")
    let msg3: String = g.infuse(slot: 5, .honed)
    check(g.inv.slots[5]?.infusions.count == 1, "the same infusion twice is refused (\(msg3))")
    let none: String = g.infuse(slot: 9, .honed)
    check(g.inv.slots[9] == nil && g.inv.total(.compound(.honed)) == 1, "infusing an empty slot changes nothing (\(none))")
    g.inv.slots[8] = Stack(item: .sword(.iron), count: 1)
    g.inv.slots[6] = nil
    let noComp: String = g.infuse(slot: 8, .honed)
    check(g.inv.slots[8]?.infusions.isEmpty == true, "without a compound nothing happens (\(noComp))")
    // removal never harms the item
    let rm: String = g.removeInfusion(slot: 5, .honed)
    check(g.inv.slots[5]?.item == .sword(.wood) && g.inv.slots[5]?.infusions.isEmpty == true, "drawing an infusion out leaves the item whole (\(rm))")
    // saves keep infusions
    g.inv.slots[6] = Stack(item: .compound(.reinforced), count: 1)
    g.inv.slots[10] = Stack(item: .armor(.chest, .iron), count: 1)
    _ = g.infuse(slot: 10, .reinforced)
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    check(back.inv.slots[10]?.has(.reinforced) == true, "infusions are saved with the item")
    // a plain stack and an infused one never merge
    check(Stack(item: .sword(.iron), count: 1) != Stack(item: .sword(.iron), count: 1, extra: 0, inf: [Infusion.honed.rawValue]), "an infused item is told apart from a plain one")
    check(Infusion.allCases.allSatisfy { i in RecipeBook.all.contains { $0.out == .compound(i) && $0.station == .infuser } }, "every infusion has a compound made at the Infusion Crucible")
    // infusions survive every move: into a chest and back, carried, dropped and picked up
    let mv = arena()
    let cx: Int = Int(mv.pb.x) + 2
    mv.world.set(cx, 99, .chest)
    mv.world.setChestItems(cx, 99, [])
    let inf: Stack = Stack(item: .sword(.diamond), count: 1, extra: 0, inf: [Infusion.honed.rawValue, Infusion.keen.rawValue])
    mv.inv.slots[12] = inf
    mv.chestStore(cx, 99, 12)
    check(mv.inv.slots[12] == nil && mv.world.chestItems(cx, 99).first == inf, "an infused item stored in a chest keeps its infusions")
    mv.chestQuickMove(cx, 99, 0)
    check(mv.inv.slots.contains { $0 == inf }, "taken back out, it still has them")
    if let i = mv.inv.slots.firstIndex(where: { $0 == inf }) {
        mv.tapSlot(i)
        mv.returnCarried()
    }
    check(mv.inv.slots.contains { $0 == inf }, "picked up and put back, it still has them")
    if let i = mv.inv.slots.firstIndex(where: { $0 == inf }) { mv.inv.slots[i] = nil }
    mv.spawnDrop(inf, mv.pb.x, mv.pb.y - 0.5, 0, 0)
    mv.drops[mv.drops.count - 1].pickDelay = 0
    frames(mv, 30)
    check(mv.inv.slots.contains { $0 == inf }, "dropped on the ground and picked up again, it still has them")
    mv.inv.slots[20] = Stack(item: .potion(.mending), count: 3)
    _ = mv.inv.add(.potion(.mending), 2)
    check(mv.inv.total(.potion(.mending)) == 5 && mv.inv.slots[20]?.count == 5, "plain potions still stack together")
}

print("== infused weapons and tools")
do {
    func strike(_ inf: [Infusion], _ item: Item = .sword(.iron)) -> (Double, Mob, Game) {
        let g = arena()
        let m: Mob = dummy(g, .pig, g.pb.x + 1.6)
        m.maxHP = 500; m.hp = 500
        g.inv.slots[0] = Stack(item: item, count: 1, extra: 0, inf: inf.isEmpty ? nil : inf.map { $0.rawValue })
        g.setSel(0)
        aimAt(g, m.b.x, m.b.cy)
        g.facing = 1
        var p: MeleeProfile = g.infusedMelee(item)
        p.critChance = 0
        g.useCD = 0
        let plain: MeleeProfile = item.melee
        _ = plain
        g.swingEmpty(item)
        return (500 - m.hp, m, g)
    }
    let base: Double = Item.sword(.iron).melee.damage
    let honedP: MeleeProfile = Game.infuseProfile(Item.sword(.iron).melee, [Infusion.honed.rawValue])
    check(near(honedP.damage, base * 1.2), "Honed: +20% damage (\(base) -> \(honedP.damage))")
    let q: MeleeProfile = Game.infuseProfile(Item.sword(.iron).melee, [Infusion.quickened.rawValue, Infusion.keen.rawValue, Infusion.heft.rawValue, Infusion.longReach.rawValue])
    let b0: MeleeProfile = Item.sword(.iron).melee
    check(near(q.cooldown, b0.cooldown * 0.85) && near(q.critChance, b0.critChance + 0.12) && near(q.knock, b0.knock * 1.6) && near(q.reach, b0.reach + 0.6),
          "Quickened, Keen, Heft and Long Reach change speed, crits, knockback and reach")
    let hit = strike([.emberbrand, .frostbite])
    check(hit.0 > 0 && hit.1.burn > 0 && hit.1.slowT > 0, "Emberbrand sets the struck creature alight and Frostbite slows it")
    let v = strike([.venom])
    check(v.1.poisonT > 0, "Venom poisons what it hits")
    check(Game.infuseProfile(Item.sword(.wood).melee, [Infusion.honed.rawValue]).damage < Item.sword(.iron).melee.damage, "a honed wooden sword still hits softer than a plain iron one")
    // ranged
    let r = arena()
    r.inv.slots[0] = Stack(item: .gun(.pistol), count: 1, extra: 6, inf: [Infusion.honed.rawValue, Infusion.volatile.rawValue])
    r.setSel(0)
    var shot = Projectile(kind: .bullet, x: 0, y: 0, vx: 1, vy: 0, dmg: 10, fromPlayer: true, gravity: 0)
    r.infuseShot(&shot, .gun(.pistol))
    check(near(shot.dmg, 12) && shot.inf & 4 != 0, "a honed, volatile pistol fires shots that hit 20% harder and burst")
    let target: Mob = dummy(r, .pig, r.pb.x + 5)
    target.maxHP = 100; target.hp = 100
    let side: Mob = dummy(r, .pig, r.pb.x + 5.8)
    side.maxHP = 100; side.hp = 100
    r.shotInfusionHit(shot, target, target.b.x - 0.3, target.b.cy)
    check(side.hp < 100, "a volatile shot's little blast catches what stands beside its target")
    // tools
    func mineFrames(_ inf: [Infusion]) -> Int {
        let g = arena()
        let tx: Int = Int(g.pb.x) + 1
        g.world.set(tx, 99, .stone)
        g.inv.slots[0] = Stack(item: .tool(.pickaxe, .stone), count: 1, extra: 0, inf: inf.isEmpty ? nil : inf.map { $0.rawValue })
        g.setSel(0)
        aimAt(g, Double(tx) + 0.5, 99.5)
        var n: Int = 0
        while g.world.tile(tx, 99) == .stone && n < 600 { g.mineStep(tx, 99, .pickaxe, .stone, 1.0 / 60.0); n += 1 }
        return n
    }
    let tp: Int = mineFrames([])
    let th: Int = mineFrames([.haste])
    check(Double(th) < Double(tp) * 0.85, "Haste mines faster (\(tp) -> \(th) frames)")
    let bg = arena()
    bg.inv.slots[0] = Stack(item: .tool(.pickaxe, .iron), count: 1, extra: 0, inf: [Infusion.bountiful.rawValue])
    bg.setSel(0)
    var more: Int = 0
    for i in 0..<400 where bg.minedDrops(.iron, i, 80, true).count > 1 { more += 1 }
    check(more > 50 && more < 120, "Bountiful: about one ore in five gives one more (\(more) of 400)")
    let pr = arena()
    pr.inv.slots[0] = Stack(item: .tool(.pickaxe, .iron), count: 1, extra: 0, inf: [Infusion.precision.rawValue])
    pr.setSel(0)
    let glass: [Stack] = pr.minedDrops(.glass, 3, 80, true)
    let grass: [Stack] = pr.minedDrops(.grass, 3, 80, true)
    check(glass.first?.item == .block(.glass) && grass.first?.item == .block(.grass), "Precision lifts glass and grass whole")
    let qy = arena()
    let qx: Int = Int(qy.pb.x) + 1
    for y in 96..<100 { qy.world.set(qx, y, .stone) }
    qy.inv.slots[0] = Stack(item: .tool(.pickaxe, .diamond), count: 1, extra: 0, inf: [Infusion.quarry.rawValue])
    qy.setSel(0)
    aimAt(qy, Double(qx) + 0.5, 97.5)
    var n: Int = 0
    while qy.world.tile(qx, 97) == .stone && n < 600 { qy.mineStep(qx, 97, .pickaxe, .diamond, 1.0 / 60.0); n += 1 }
    check(qy.world.tile(qx, 96) == .air && qy.world.tile(qx, 98) == .air && qy.world.tile(qx, 99) == .stone, "Quarry also breaks the blocks just above and below, and no more")
}

print("== infused armour")
do {
    let g = arena()
    g.inv.armor[1] = Stack(item: .armor(.chest, .iron), count: 1)
    let d0: Double = g.totalDefense
    g.inv.armor[1] = Stack(item: .armor(.chest, .iron), count: 1, extra: 0, inf: [Infusion.reinforced.rawValue, Infusion.fireward.rawValue])
    check(near(g.totalDefense, d0 + 1), "Reinforced adds 1 defence (\(d0) -> \(g.totalDefense))")
    g.invuln = 0
    var fire = DamageInfo(amount: 10, type: .fire, source: .environment)
    fire.originX = g.pb.x
    _ = g.hurtPlayer(fire)
    check(g.hp == 12, "Fireward: fire hurts 20% less (10 -> \(20 - g.hp))")
    g.inv.armor[2] = Stack(item: .armor(.legs, .iron), count: 1, extra: 0, inf: [Infusion.fleet.rawValue])
    check(near(g.armorInf.speed, 0.04), "Fleet: 4% faster")
    // barbed
    let b = arena()
    b.inv.armor[1] = Stack(item: .armor(.chest, .iron), count: 1, extra: 0, inf: [Infusion.barbed.rawValue])
    let z: Mob = dummy(b, .zombie, b.pb.x + 1)
    z.maxHP = 50; z.hp = 50
    var hit = DamageInfo(amount: 10, type: .melee, source: .mob(z, .hostile))
    hit.originX = z.b.x
    b.invuln = 0
    _ = b.hurtPlayer(hit)
    check(z.hp < 50, "Barbed: the attacker takes some of its blow back (\(50 - z.hp))")
    // the cache follows what is worn
    let k0: Double = b.armorInf.thorns
    b.inv.armor[1] = nil
    check(k0 > 0 && b.armorInf.thorns == 0, "taking the armour off takes its infusions with it")
}

// ---------------------------------------------------------------- stage 6-8: the exosuit
print("== building a suit")
do {
    let g = arena()
    // every part has a recipe at the assembly station
    var missing: [String] = []
    for it in featureItems() {
        switch it {
        case .exoPart, .exoPlate, .exoCore, .exoModule:
            if !RecipeBook.all.contains(where: { $0.out == it && $0.station == .assembly }) { missing.append(it.name) }
        default: break
        }
    }
    check(missing.isEmpty, "every suit part, plate, core and module is made at the Assembly Station \(missing)")
    // crafting one at a station
    g.world.set(Int(g.pb.x) + 2, 99, .exoStation)
    check(g.stationAvailable(.assembly), "an Assembly Station nearby counts as the station")
    let r: Recipe = RecipeBook.all.first { $0.out == .exoPart(.helmet, .iron) }!
    for c in r.cost { g.giveItem(c.item, c.n) }
    g.craft(r)
    check(g.inv.total(.exoPart(.helmet, .iron)) == 1, "an Iron Suit Helmet can be made there")
    // fitting
    let parts: [Item] = [.exoPart(.chestFrame, .iron), .exoCore(.sparkCell), .exoPart(.arm, .iron), .exoPart(.arm, .diamond), .exoPart(.legs, .iron), .exoPart(.boots, .iron), .exoPlate(.iron), .exoModule(.sprint)]
    for p in parts { g.giveItem(p, 1) }
    var plan: ExoSuit = g.suit
    plan[.helmet] = Stack(item: .exoPart(.helmet, .iron), count: 1)
    plan[.chest] = Stack(item: .exoPart(.chestFrame, .iron), count: 1)
    plan[.core] = Stack(item: .exoCore(.sparkCell), count: 1)
    plan[.armL] = Stack(item: .exoPart(.arm, .iron), count: 1)
    plan[.armR] = Stack(item: .exoPart(.arm, .diamond), count: 1)
    plan[.legs] = Stack(item: .exoPart(.legs, .iron), count: 1)
    plan[.boots] = Stack(item: .exoPart(.boots, .iron), count: 1)
    plan[.plateChest] = Stack(item: .exoPlate(.iron), count: 1)
    plan[.mod1] = Stack(item: .exoModule(.sprint), count: 1)
    let before: Int = g.inv.slots.compactMap { $0 }.count
    let msg: String = g.applySuit(plan)
    check(g.suit[.chest] != nil && g.suit[.mod1] != nil && g.inv.total(.exoPart(.chestFrame, .iron)) == 0 && g.inv.slots.compactMap { $0 }.count == before - 9, "APPLY fits every planned part and takes them out of the bag (\(msg))")
    let st: ExoStats = g.suitStats
    let wantDef: Double = 0.9 + 1.6 + 0.5 + 0.5 * 1.6 + 1.1 + 0.6 + 0.9
    check(near(st.defense, wantDef, 0.01), "defence adds up part by part and by metal (\(st.defense))")
    check(st.complete && near(st.capacity, 120) && st.has(.sprint), "with a chest frame and a core it is complete; the core sets its energy; the module works")
    check(st.drillTier == ExoMat.diamond.drillTier, "the right arm's metal would set a drill's tier")
    // swapping arms needs no bag item: the parts are already on the suit
    var swap: ExoSuit = g.suit
    swap[.armL] = g.suit[.armR]
    swap[.armR] = g.suit[.armL]
    let msgSwap: String = g.applySuit(swap)
    check(g.suit.material(.armL) == .diamond && g.suit.material(.armR) == .iron, "parts can be swapped between places (\(msgSwap))")
    // taking a part off returns it, infusions and all
    var off: ExoSuit = g.suit
    off[.plateChest] = nil
    _ = g.applySuit(off)
    check(g.suit[.plateChest] == nil && g.inv.total(.exoPlate(.iron)) == 1, "a part taken off goes back to the bag")
    // a planned part that is not in the bag: nothing at all changes
    var bad: ExoSuit = g.suit
    bad[.plateHead] = Stack(item: .exoPlate(.voidium), count: 1)
    bad[.plateArms] = Stack(item: .exoPlate(.iron), count: 1)
    let suitBefore: ExoSuit = g.suit
    let invBefore: [Stack?] = g.inv.slots
    let refused: String = g.applySuit(bad)
    check(g.suit == suitBefore && g.inv.slots == invBefore, "if any planned part is missing, nothing changes and nothing is lost (\(refused))")
    // metals matter
    var a: ExoSuit = ExoSuit()
    a[.chest] = Stack(item: .exoPart(.chestFrame, .iron), count: 1)
    var dmd: ExoSuit = ExoSuit()
    dmd[.chest] = Stack(item: .exoPart(.chestFrame, .diamond), count: 1)
    var myth: ExoSuit = ExoSuit()
    myth[.chest] = Stack(item: .exoPart(.chestFrame, .mythril), count: 1)
    var vd: ExoSuit = ExoSuit()
    vd[.chest] = Stack(item: .exoPart(.chestFrame, .voidium), count: 1)
    let sa: ExoStats = ExoStats.of(a)
    let sd: ExoStats = ExoStats.of(dmd)
    let sm: ExoStats = ExoStats.of(myth)
    check(sd.defense > sa.defense && sd.weight > sa.weight, "diamond guards better than iron but weighs more")
    check(sm.defense > sa.defense && sm.weight < sa.weight, "mythril guards better and weighs less (rare)")
    check(a.sockets == 2 && dmd.sockets == 3 && vd.sockets == 4, "the chest frame's metal sets the module sockets (iron 2, diamond 3, voidium 4)")
    // a module needs its parts and a socket
    var noArm: ExoSuit = ExoSuit()
    noArm[.chest] = Stack(item: .exoPart(.chestFrame, .iron), count: 1)
    noArm[.mod1] = Stack(item: .exoModule(.drill), count: 1)
    noArm[.mod3] = Stack(item: .exoModule(.lamp), count: 1)
    let sn: ExoStats = ExoStats.of(noArm)
    check(!sn.has(.drill) && !sn.has(.lamp) && sn.notes.count >= 2, "a drill without its right arm, or a module beyond the sockets, does not work, and the screen says why")
    check(ExoSlot.armL.fits(.exoPart(.arm, .iron)) && !ExoSlot.helmet.fits(.exoPart(.arm, .iron)) && ExoSlot.mod2.fits(.exoModule(.lamp)) && !ExoSlot.core.fits(.exoPlate(.iron)),
          "each place takes only its own kind of part")
}

print("== wearing and power")
do {
    let g = arena()
    g.inv.armor[0] = Stack(item: .armor(.head, .iron), count: 1)
    var plan: ExoSuit = ExoSuit()
    let kit: [(ExoSlot, Item)] = [(.helmet, .exoPart(.helmet, .iron)), (.chest, .exoPart(.chestFrame, .iron)), (.core, .exoCore(.dynamo)),
                                 (.armL, .exoPart(.arm, .iron)), (.armR, .exoPart(.arm, .iron)), (.legs, .exoPart(.legs, .iron)), (.boots, .exoPart(.boots, .iron)),
                                 (.mod1, .exoModule(.drill)), (.mod2, .exoModule(.lamp))]
    for (s, it) in kit {
        g.giveItem(it, 1)
        plan[s] = Stack(item: it, count: 1)
    }
    _ = g.applySuit(plan)
    let worn: String = g.wearSuit()
    check(g.suit.worn && g.inv.armor[0] == nil && g.inv.total(.armor(.head, .iron)) == 1, "wearing the suit moves armour into the bag (\(worn))")
    check(!g.fitsArmorSlot(.armor(.head, .iron), 0), "armour can't be put on over the suit")
    check(g.totalDefense > 5, "the suit guards the wearer (defence \(g.totalDefense))")
    // the look follows the suit
    let k1: Int = g.armorKey
    var st: HumanStyle = playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil)
    let plainFrame: PixelBuf = humanoidFrame(st, legs: 0, pose: 0)
    st.suit = g.suitLook()
    let suitFrame: PixelBuf = humanoidFrame(st, legs: 0, pose: 0)
    check(plainFrame.px != suitFrame.px, "the player's sprite shows the suit")
    var swap: ExoSuit = g.suit
    g.giveItem(.exoPart(.helmet, .voidium), 1)
    swap[.helmet] = Stack(item: .exoPart(.helmet, .voidium), count: 1)
    _ = g.applySuit(swap)
    check(g.suit.worn && g.armorKey != k1, "changing a part changes the look (a new sprite is made)")
    // energy
    g.suit.energy = 0
    frames(g, 60 * 5)
    check(near(g.suit.energy, 5.0, 0.6), "the core refills by itself in daylight (dynamo: 1 a second, \(String(format: "%.1f", g.suit.energy)) after 5 s; the lamp stays off by day)")
    g.suit.energy = 10_000
    frame(g)
    check(g.suit.energy <= g.suitStats.capacity, "energy never goes above the core's capacity")
    // the drill: bare hands bore iron ore at the arm's tier, spending energy
    g.suit.energy = 100
    let tx: Int = Int(g.pb.x) + 1
    g.world.set(tx, 99, .iron)
    g.inv.slots[0] = nil
    g.setSel(0)
    aimAt(g, Double(tx) + 0.5, 99.5)
    var n: Int = 0
    while g.world.tile(tx, 99) == .iron && n < 900 { g.mineStep(tx, 99, nil, nil, 1.0 / 60.0); n += 1 }
    check(g.world.tile(tx, 99) != .iron, "the drill arm lets bare hands bore iron ore (\(n) frames)")
    check(g.suit.energy < 100, "the drill spends energy while it works (\(String(format: "%.1f", g.suit.energy)) left)")
    g.suit.energy = 0
    g.world.set(tx, 99, .iron)
    n = 0
    while g.world.tile(tx, 99) == .iron && n < 300 { g.mineStep(tx, 99, nil, nil, 1.0 / 60.0); n += 1 }
    check(g.world.tile(tx, 99) == .iron, "with no energy the drill is dead weight (bare hands can't mine iron)")
    // lamp in the dark
    g.suit.energy = 50
    frame(g)
    check(!g.suitLit, "the helmet lamp stays off in daylight")
    g.timeOfDay = 0.75
    frame(g)
    check(g.suitLit, "at night the helmet lamp lights itself (while there is energy)")
    g.timeOfDay = 0.25
    // taking it off
    let offMsg: String = g.takeOffSuit()
    check(!g.suit.worn && g.fitsArmorSlot(.armor(.head, .iron), 0), "taking it off frees the armour slots (\(offMsg))")
    // a suit without a core can't be worn
    let h = arena()
    var noCore: ExoSuit = ExoSuit()
    h.giveItem(.exoPart(.chestFrame, .iron), 1)
    noCore[.chest] = Stack(item: .exoPart(.chestFrame, .iron), count: 1)
    _ = h.applySuit(noCore)
    let why: String = h.wearSuit()
    check(!h.suit.worn, "a suit without a core can't be worn (\(why))")
}

print("== modules")
do {
    func suited(_ mods: [ExoModule], core: ExoCore = .heart, chest: ExoMat = .voidium) -> Game {
        let g = arena()
        var plan: ExoSuit = ExoSuit()
        var kit: [(ExoSlot, Item)] = [(.helmet, .exoPart(.helmet, .iron)), (.chest, .exoPart(.chestFrame, chest)), (.core, .exoCore(core)),
                                     (.armL, .exoPart(.arm, .iron)), (.armR, .exoPart(.arm, .iron)), (.legs, .exoPart(.legs, .mythril)), (.boots, .exoPart(.boots, .mythril))]
        let sockets: [ExoSlot] = [.mod1, .mod2, .mod3, .mod4]
        for (i, m) in mods.enumerated() where i < 4 { kit.append((sockets[i], .exoModule(m))) }
        for (s, it) in kit {
            g.giveItem(it, 1)
            plan[s] = Stack(item: it, count: 1)
        }
        _ = g.applySuit(plan)
        _ = g.wearSuit()
        g.suit.energy = g.suitStats.capacity
        return g
    }
    // sprint
    let a = suited([])
    a.keyR = true
    let ax: Double = a.pb.x
    frames(a, 90)
    let plainRun: Double = a.pb.x - ax
    let b = suited([.sprint])
    b.keyR = true
    let bx: Double = b.pb.x
    let e0: Double = b.suit.energy
    frames(b, 90)
    check(b.pb.x - bx > plainRun * 1.1 && b.suit.energy < e0, "sprint actuators: faster running that costs energy (\(String(format: "%.1f", plainRun)) -> \(String(format: "%.1f", b.pb.x - bx)))")
    // leap
    let c = suited([.leap])
    frames(c, 10)
    c.jumpHeld = true
    frame(c)
    let vyLeap: Double = c.pb.vy
    let c2 = suited([])
    frames(c2, 10)
    c2.jumpHeld = true
    frame(c2)
    check(vyLeap < c2.pb.vy * 1.2, "leap pistons: a higher jump (launch \(String(format: "%.1f", c2.pb.vy)) -> \(String(format: "%.1f", vyLeap)))")
    // hover
    let d = suited([.hover])
    d.pb.y = 70
    d.pb.onGround = false
    d.jumpHeld = true
    frames(d, 60)
    let fallHover: Double = d.pb.y - 70
    let d2 = suited([])
    d2.pb.y = 70
    d2.pb.onGround = false
    d2.jumpHeld = true
    frames(d2, 60)
    check(fallHover < (d2.pb.y - 70) * 0.5 && d.suit.energy < d.suitStats.capacity, "hover jets: holding jump in the air slows the fall to a glide (\(String(format: "%.1f", fallHover)) vs \(String(format: "%.1f", d2.pb.y - 70)) blocks) and drains energy")
    // seal: breathing and fire
    let e = suited([.seal])
    for x in (Int(e.pb.x) - 3)...(Int(e.pb.x) + 3) { for y in 95..<100 { e.world.set(x, y, .water) } }
    frames(e, 60 * 12)
    check(e.air >= 9.9 && e.suit.energy < e.suitStats.capacity, "environment seal: air under water, while it spends energy")
    let f = suited([.seal])
    f.invuln = 0
    f.playerBurn = 1
    var fire = DamageInfo(amount: 10, type: .fire, source: .environment)
    fire.originX = f.pb.x
    frame(f)
    _ = f.hurtPlayer(fire)
    check(20 - f.hp <= 4, "environment seal: fire hurts far less (\(20 - f.hp) of 10)")
    // barrier
    let gb = suited([.barrier])
    gb.invuln = 0
    let e1: Double = gb.suit.energy
    var hit = DamageInfo(amount: 10, type: .melee, source: .environment)
    hit.originX = gb.pb.x
    let gb2 = suited([])
    gb2.invuln = 0
    _ = gb.hurtPlayer(hit)
    _ = gb2.hurtPlayer(hit)
    check(gb.hp > gb2.hp && gb.suit.energy < e1, "barrier projector: part of a hit drains energy instead of health (\(20 - gb2.hp) -> \(20 - gb.hp))")
    // servo and gauntlet
    let sv = suited([.servo, .gauntlet])
    let foe: Mob = dummy(sv, .pig, sv.pb.x + 1.5)
    sv.hitStopT = 0
    foe.maxHP = 500; foe.hp = 500
    sv.inv.slots[0] = Stack(item: .sword(.iron), count: 1)
    sv.setSel(0)
    aimAt(sv, foe.b.x, foe.b.cy)
    sv.facing = 1
    sv.swingEmpty(.sword(.iron))
    let dealt: Double = 500 - foe.hp
    check(dealt >= Item.sword(.iron).melee.damage * 1.25 + 3.5, "servo muscles hit 25% harder and the gauntlet adds a shock (\(dealt))")
    // cargo pack
    let cg = suited([.cargo])
    cg.openPack()
    check(cg.showInventory && cg.openChest != nil && cg.isPackSpot(cg.openChest!), "the cargo pack opens as storage")
    cg.world.setChestItems(cg.packSpot.x, cg.packSpot.y, [Stack(item: .mat(.coal), count: 9)])
    cg.showInventory = false
    cg.openChest = nil
    var noPack: ExoSuit = cg.suit
    noPack[.mod1] = nil
    _ = cg.applySuit(noPack)
    check(cg.inv.total(.mat(.coal)) == 9, "taking the cargo pack off empties it into the bag: nothing is stranded")
    // no energy, no modules
    let z = suited([.sprint])
    z.suit.energy = 0
    check(!z.suitHas(.sprint), "with no energy the modules stop")
    // output limit: a weak core can't run everything at once
    let w = suited([.hover, .sprint, .lamp, .seal], core: .sparkCell, chest: .voidium)
    w.pb.y = 70
    w.pb.onGround = false
    w.jumpHeld = true
    for x in (Int(w.pb.x) - 3)...(Int(w.pb.x) + 3) { for y in 60..<75 { w.world.set(x, y, .water) } }
    frame(w)
    check(w.suitLastLoad <= w.suitStats.output + 0.001 && w.suitLastLoad > 0, "a core never gives more than its output a second (asked for more, gave \(String(format: "%.1f", w.suitLastLoad)) of \(w.suitStats.output))")
}

print("== charging from Sparkworks")
do {
    let g = arena()
    var plan: ExoSuit = ExoSuit()
    for (s, it) in [(ExoSlot.chest, Item.exoPart(.chestFrame, .iron)), (.core, .exoCore(.crystal))] {
        g.giveItem(it, 1)
        plan[s] = Stack(item: it, count: 1)
    }
    _ = g.applySuit(plan)
    _ = g.wearSuit()
    g.suit.energy = 0
    // a battery tapped while wearing the suit
    let bx: Int = Int(g.pb.x) + 2
    g.world.set(bx, 99, .battery)
    frames(g, 2)
    if let d = g.world.powerDev(bx, 99) {
        d.charge = 150
        g.interact(Double(bx) + 0.5, 99.5)
        check(g.suit.energy >= 149 && d.charge < 1, "tapping a battery fills the suit from its charge (\(Int(g.suit.energy)))")
    } else {
        check(false, "the battery is a power device")
    }
    // the station on a powered line charges it
    let h = arena()
    var plan2: ExoSuit = ExoSuit()
    for (s, it) in [(ExoSlot.chest, Item.exoPart(.chestFrame, .iron)), (.core, .exoCore(.crystal))] {
        h.giveItem(it, 1)
        plan2[s] = Stack(item: it, count: 1)
    }
    _ = h.applySuit(plan2)
    _ = h.wearSuit()
    h.suit.energy = 0
    let sx: Int = Int(h.pb.x) + 2
    h.world.set(sx, 99, .exoStation)
    h.world.set(sx + 1, 99, .accumulator)
    frames(h, 2)
    h.world.powerDev(sx + 1, 99)?.charge = 4000
    for x in sx...(sx + 1) { h.world.setWire(x, 99, Wire.power) }
    h.world.powerRev &+= 1
    frames(h, 60 * 3)
    check(h.suit.energy > 20, "an Assembly Station wired to a charged accumulator charges a suit worn close by (\(Int(h.suit.energy)) in 3 s)")
    let left: Double = h.world.powerDev(sx + 1, 99)?.charge ?? 0
    check(left < 4000, "and that energy comes out of the network (\(Int(left)) left)")
    h.pb.x += 20
    let e2: Double = h.suit.energy
    frames(h, 60)
    check(h.suit.energy - e2 < 2.5, "walk away and the station stops charging (only the core's own trickle)")
}

print("== saving a suit")
do {
    let g = arena()
    var plan: ExoSuit = ExoSuit()
    let kit: [(ExoSlot, Stack)] = [(.chest, Stack(item: .exoPart(.chestFrame, .gold), count: 1)), (.core, Stack(item: .exoCore(.dynamo), count: 1, extra: 0, inf: [Infusion.thrift.rawValue])),
                                  (.plateChest, Stack(item: .exoPlate(.diamond), count: 1, extra: 0, inf: [Infusion.reinforced.rawValue])), (.mod1, Stack(item: .exoModule(.lamp), count: 1))]
    for (s, st) in kit {
        g.addStack(st)
        plan[s] = st
    }
    _ = g.applySuit(plan)
    _ = g.wearSuit()
    g.suit.energy = 77
    g.effects.add(.speed, 30, 50)
    g.mendCD = 4
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    let h = Game.load(back, settings: Settings())
    check(h.suit.parts == g.suit.parts && h.suit.worn && near(h.suit.energy, 77), "the suit comes back with every part, still worn, with its energy")
    check(h.suit[.core]?.has(.thrift) == true && h.suit[.plateChest]?.has(.reinforced) == true, "suit parts keep their infusions")
    check(h.suitStats.drainMul < 0.8, "a Thrift core and gilded frame cut energy use (x\(String(format: "%.2f", h.suitStats.drainMul)))")
    check(near(h.effects.value(.speed), 30) && near(h.effects.time[ModEffectKind.speed.rawValue], 50, 0.5) && near(h.mendCD, 4, 0.1), "potion effects and the mending rest are saved")
    // an old save without any of this loads with nothing
    var old: SaveData = back
    old.suit = nil
    old.effects = nil
    old.mutants = nil
    let k = Game.load(old, settings: Settings())
    check(k.suit.isEmpty && k.activeEffects().isEmpty, "a save from before this update loads with no suit and no effects")
}

print("== stations and screens")
do {
    let g = arena()
    let x: Int = Int(g.pb.x)
    g.world.set(x + 2, 99, .alchemyStill)
    g.world.set(x - 2, 99, .infuser)
    g.world.set(x + 3, 99, .exoStation)
    frames(g, 2)
    g.interact(Double(x + 2) + 0.5, 99.5)
    check(g.showInventory && g.craftStation == .still, "tapping the Alchemy Still opens brewing")
    g.showInventory = false
    g.craftStation = .hand
    g.interact(Double(x - 2) + 0.5, 99.5)
    check(g.showInfuse, "tapping the Infusion Crucible opens its screen")
    g.updateInputGate()
    check(g.inputBlocked, "the crucible's screen blocks the controls under it")
    g.showInfuse = false
    g.updateInputGate()
    g.interact(Double(x + 3) + 0.5, 99.5)
    check(g.showExo, "tapping the Assembly Station opens the suit builder")
    g.updateInputGate()
    check(g.inputBlocked, "the builder blocks the controls under it")
    g.showExo = false
    let ga = arena()
    let gb = arena()
    check(ga.serial != gb.serial && gb.serial != g.serial, "every world gets its own number, so the render cache never shows one world's pictures in another")
    check(Tile.alchemyStill.rawValue > Tile.mod63.rawValue && !Tile.alchemyStill.isMod && !Tile.exoStation.isMod && Tile.mod63.isMod, "the new tiles come after the mod tiles and are not mistaken for them")
    check(customTileRows(.alchemyStill) != nil && customTileRows(.infuser) != nil && customTileRows(.exoStation) != nil, "the stations have their own art")
    check(allGameItems().contains(.potion(.mutagen)) && allGameItems().contains(.exoModule(.hover)) && allGameItems().contains(.block(.infuser)), "everything new is in the creative palette")
    // the suit pictures
    var s = ExoSuit()
    s[.chest] = Stack(item: .exoPart(.chestFrame, .ember), count: 1)
    let front: PixelBuf = suitViewBuf(s, 0)
    let empty: PixelBuf = suitViewBuf(ExoSuit(), 0)
    check(front.px != empty.px && front.px.contains { $0 & 0xFFFFFF == ExoMat.ember.color }, "the builder's picture shows each fitted part in its metal's colour")
    // sounds stay short
    var longest: Double = 0
    for id in [SoundID.drink, .potionBreak, .infuse, .suitUp] { longest = max(longest, Double(SoundBank.effect(id, 0).count) / Synth.rate) }
    check(longest <= 1.2, "the new sounds are short (\(String(format: "%.2f", longest)) s)")
}

print("== chests, storms and mods")
do {
    let g = arena()
    var found: Int = 0
    for i in 0..<200 {
        let a: [Stack] = g.world.alchemyChestExtras([], g.gen, .overworld, 100 + i * 7, 120)
        let b: [Stack] = g.world.alchemyChestExtras([], g.gen, .overworld, 100 + i * 7, 120)
        if a != b { found = -1000 }
        if !a.isEmpty { found += 1 }
    }
    check(found > 40, "chests now and then hold ingredients, potions or compounds, fixed by their place (\(found) of 200)")
    let g2 = arena()
    let opened: [Stack] = g.world.chestItems(321, 140)
    let broken: [Stack] = g2.world.removeChest(321, 140)
    check(opened == broken, "a chest broken before it is opened gives just what opening it would have")
    check(g.world.removeChest(-1_000_000_000, -77).isEmpty && g.world.removeChest(g.packSpot.x, g.packSpot.y).isEmpty, "storage outside the world (a cargo crate never opened, the suit pack) never rolls loot")
    var essence: Int = 0
    for _ in 0..<60 {
        g.drops.removeAll()
        g.lightningStrike(g.pb.x + 5, 99, rod: true)
        essence += g.drops.filter { $0.stack.item == .mat(.stormEssence) }.count
    }
    check(essence > 15 && essence < 45, "a lightning rod catches storm essence about half the time (\(essence) of 60)")
    // mod items can give the new effects, clamped
    var p = ModPack()
    p.id = "brew"
    p.name = "Brew"
    var it = ModItem()
    it.id = "pick_tea"
    it.name = "Pick Tea"
    it.kind = .consumable
    it.effects = [ModEffect(.mining, 999, 30), ModEffect(.nightVision, 1, 60)]
    p.items.append(it)
    let rep: ModReport = ModValidator.check(&p, known: [:])
    _ = rep
    check(p.items[0].effects[0].amount <= ModEffectKind.mining.amountRange.hi, "a mod's mining effect is clamped to the limit (\(p.items[0].effects[0].amount))")
    let h = arena()
    h.applyEffects(p.items[0].effects)
    check(h.effects.value(.mining) > 0 && h.effects.value(.nightVision) > 0, "a mod item can give the new effects")
    check(Station(rawValue: 7) == .still && Station.assembly.tile == .exoStation, "mods can name the new stations for their recipes")
}

print(fails == 0 ? "ALL \(passes) ALCHEMY CHECKS PASSED" : "\(fails) FAILED, \(passes) passed")
exit(fails == 0 ? 0 : 1)
