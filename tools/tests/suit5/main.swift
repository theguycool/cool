import SwiftUI
import Foundation
// Step 5b: the exosuit built piece by piece. Coverage and guarding from the pieces actually there,
// each piece damaged on its own (hits land where they land; layers; breaking off; mending), building
// and its bill, old suits rebuilt piece by piece, the suit drawn three times finer and moving with the
// body, and the working parts: jets that lift by their thrust against the suit's weight, wings, turrets,
// cannons, lasers, boosters, batteries, solar panels and the magnet. The designer screen is SwiftUI and
// is compile-checked only; what it calls is tested here.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { return abs(a - b) <= eps }

let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prsuit5-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

/// A flat stone floor at row 100, nothing spawning
func arena(mode: GameMode = .survival) -> Game {
    ModRuntime.activate([], world: nil)
    let g = Game(mode: mode, infinite: true, seed: 7272, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 5)
    for x in x0...(x0 + 80) {
        for y in 30..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.maxHP = 400; g.hp = 400
    g.timeOfDay = 0.25
    g.settings.weatherOn = false
    return g
}
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func aimAt(_ g: Game, _ x: Double, _ y: Double) { g.aimX = x; g.aimY = y; g.aimValid = true }
func foe(_ g: Game, _ k: MobKind, _ x: Double) -> Mob {
    let m: Mob = g.addMob(k, x, 100)
    m.persistent = true
    g.mobGrid.rebuild(g.mobs)
    return m
}

/// A design, its parts paid for from a creative-free bag: plates as given, plus cores and parts
func design(_ base: SuitDesign, _ parts: [SuitPiece] = []) -> SuitDesign {
    var d: SuitDesign = base
    for var p in parts {
        p.id = d.newID()
        d.pieces.append(p)
    }
    return d
}
/// Builds a design onto the player in creative (no bill) and puts it on
func wearIt(_ g: Game, _ d: SuitDesign) {
    let was: GameMode = g.mode
    g.mode = .creative
    _ = g.applyDesign(d)
    g.mode = was
    _ = g.wearSuit()
    g.suit.energy = g.suitStats.capacity
}
func plate(_ b: SuitBone, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ m: ExoMat = .iron, thick: Int = 1) -> SuitPiece {
    var p: SuitPiece = SuitTemplates.piece(.plate, b, cx, cy, w, h, m)
    p.thick = thick
    return p
}

// ---------------------------------------------------------------- guarding by what is there
print("== coverage and guarding")
do {
    let empty: ExoStats = ExoStats.of(SuitDesign())
    check(empty.guardAll == 0 && !empty.complete, "an empty suit guards nothing and can't be worn")
    let helm: SuitDesign = design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0)])
    let st: ExoStats = ExoStats.of(helm)
    let head: Int = SuitSection.head.rawValue
    let legs: Int = SuitSection.legs.rawValue
    check(st.cover[head] > 0.9 && st.cover[legs] == 0 && st.guardBy[head] > 0.15, "a helmet plate covers the head (\(Int(st.cover[head] * 100))%) and nothing else")
    check(st.guardAll > 0 && st.guardAll < st.guardBy[head], "the whole suit's guard is the coverage averaged over the body (\(Int(st.guardAll * 100))%)")
    let two: SuitDesign = design(helm, [plate(.head, 5.0, 3.0, 6.0, 5.0)])
    let st2: ExoStats = ExoStats.of(two)
    check(st2.guardBy[head] > st.guardBy[head] * 1.6 && st2.weight > st.weight * 1.9, "a second layer over it stops more and weighs twice as much (\(Int(st.guardBy[head] * 100))% -> \(Int(st2.guardBy[head] * 100))%)")
    let thick: SuitDesign = design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0, thick: 2)])
    let st3: ExoStats = ExoStats.of(thick)
    check(st3.guardBy[head] > st.guardBy[head] * 1.8 && st3.weight > st.weight * 1.9, "a double-thick plate guards and weighs about as two")
    let dia: ExoStats = ExoStats.of(design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0, .diamond)]))
    let gold: ExoStats = ExoStats.of(design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0, .gold)]))
    check(dia.guardBy[head] > st.guardBy[head] && gold.guardBy[head] < st.guardBy[head], "metals guard differently: diamond more, gilded less than iron")
    var turned: SuitPiece = plate(.torso, 5.0, 9.0, 8.0, 2.0)
    let flat: Double = ExoStats.of(design(SuitDesign(), [turned])).cover[SuitSection.torso.rawValue]
    turned.rot = 90
    let upright: Double = ExoStats.of(design(SuitDesign(), [turned])).cover[SuitSection.torso.rawValue]
    check(abs(flat - upright) > 0.05, "turning a piece changes what it covers (\(Int(flat * 100))% -> \(Int(upright * 100))%)")
    var round: SuitPiece = plate(.torso, 5.0, 9.0, 4.0, 4.0)
    round.shape = .round
    check(round.area < plate(.torso, 5.0, 9.0, 4.0, 4.0).area && round.covers(round.x, round.y) && !round.covers(round.x + round.w * 0.49, round.y + round.h * 0.49), "shapes: a round piece leaves its corners open")
    check(SuitBody.bone(15, 9) == .head && SuitBody.bone(15, 27) == .torso && SuitBody.bone(4, 25) == .armBack && SuitBody.bone(25, 25) == .armFront && SuitBody.bone(8, 40) == .legBack && SuitBody.bone(22, 40) == .legFront && SuitBody.bone(-6, 27) == .back,
          "a piece goes on the part of the body it is placed over")
}

print("== hits land where they land")
do {
    let g = arena()
    wearIt(g, design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0), plate(.legBack, 3.0, 13.5, 2.0, 3.0), plate(.legFront, 7.0, 13.5, 2.0, 3.0)]))
    g.invuln = 0
    var high = DamageInfo(amount: 10, type: .melee, source: .environment)
    high.originX = g.pb.x
    high.originY = g.pb.top + 0.1
    var through: Double = 0
    for _ in 0..<20 { through += g.suitTakeBlow(10, high) }
    let d: SuitDesign = g.suit.d
    let headPiece: SuitPiece = d.pieces[0]
    check(headPiece.dmg > 0 && d.pieces[1].dmg == 0 && d.pieces[2].dmg == 0, "blows at head height wear the helmet plate only (\(Int(headPiece.dmg * 100))%)")
    check(through < 200 * 0.9, "and it stops part of them (\(Int(through)) of 200 got through)")
    let bare = arena()
    wearIt(bare, design(SuitDesign(), [plate(.head, 5.0, 3.0, 6.0, 5.0)]))
    var low = DamageInfo(amount: 10, type: .melee, source: .environment)
    low.originX = bare.pb.x
    low.originY = bare.pb.y - 0.05
    var feet: Double = 0
    for _ in 0..<20 { feet += bare.suitTakeBlow(10, low) }
    check(feet > 199.0 && bare.suit.d.pieces[0].dmg == 0, "blows at the legs and feet of a suit with only a helmet get through whole (\(Int(feet)) of 200), the helmet untouched")
    // a creature's blow lands at its own height
    let slime: Mob = foe(g, .slime, g.pb.x + 1)
    var bite = DamageInfo(amount: 6, type: .melee, source: DamageSource.mob(slime, .hostile))
    bite.originX = slime.b.x
    let f: Double? = g.suitHitHeight(bite)
    check(f != nil && f! > 0.6, "a small creature's bite lands low (height \(String(format: "%.2f", f ?? -1)))")
    // breaking off
    var broke: Bool = false
    var n: Int = 0
    while !broke && n < 300 {
        _ = g.suitTakeBlow(12, high)
        broke = g.suit.d.pieces[0].broken
        n += 1
    }
    check(broke && !g.suit.d.pieces[1].broken && g.suitStats.broken == 1, "enough blows break the plate off (\(n) more), and only it")
    check(g.suitStats.cover[SuitSection.head.rawValue] == 0, "a broken plate covers nothing")
    var after: Double = 0
    for _ in 0..<10 { after += g.suitTakeBlow(10, high) }
    check(after > 99.0, "and stops nothing (\(Int(after)) of 100)")
    // a blast spreads over the body
    let h = arena()
    wearIt(h, SuitTemplates.design(2, .iron))
    let boom = DamageInfo(amount: 20, type: .explosion, source: .environment)
    _ = h.suitTakeBlow(20, boom)
    let worn: Int = h.suit.d.pieces.filter { $0.dmg > 0 }.count
    check(worn >= 2, "a blast wears several pieces at once (\(worn))")
    // through the game's own damage: plates spare health
    let a = arena()
    wearIt(a, SuitTemplates.design(3, .diamond))
    let b = arena()
    a.invuln = 0
    b.invuln = 0
    var tot: (Double, Double) = (0, 0)
    for _ in 0..<12 {
        a.invuln = 0
        b.invuln = 0
        var hit = DamageInfo(amount: 10, type: .melee, source: .environment)
        hit.originX = a.pb.x
        let ha: Double = a.hp
        let hb: Double = b.hp
        _ = a.hurtPlayer(hit)
        _ = b.hurtPlayer(hit)
        tot.0 += ha - a.hp
        tot.1 += hb - b.hp
    }
    check(tot.0 < tot.1 * 0.75, "a heavy diamond suit takes far less from the same blows (\(Int(tot.0)) against \(Int(tot.1)) unsuited)")
}

print("== building, bills and mending")
do {
    let g = arena()
    let plan: SuitDesign = design(SuitDesign(), [plate(.torso, 5.0, 9.0, 4.0, 6.0)])
    let cost: Int = suitPieceCost(plan.pieces[0])!.1
    let b: SuitBill = g.suit.d.bill(to: plan)
    check(b.pay[.mat(.ironBar)] == cost && b.back.isEmpty, "a new plate costs bars of its metal by its size (\(cost))")
    g.inv.slots = [Stack?](repeating: nil, count: g.inv.slots.count)
    let none: String = g.applyDesign(plan)
    check(g.suit.d.pieces.isEmpty, "without the bars nothing is built (\(none))")
    _ = g.inv.add(.mat(.ironBar), cost)
    _ = g.applyDesign(plan)
    check(g.suit.d.pieces.count == 1 && g.inv.total(.mat(.ironBar)) == 0, "with them it is built")
    var remade: SuitDesign = g.suit.d
    remade.pieces[0].mat = ExoMat.gold.rawValue
    let bill2: SuitBill = g.suit.d.bill(to: remade)
    check(bill2.pay[.mat(.goldBar)] == cost && bill2.back[.mat(.ironBar)] == cost, "remaking it in gold pays gold and gives the iron back")
    var moved: SuitDesign = g.suit.d
    moved.pieces[0].x += 3
    check(g.suit.d.bill(to: moved).isEmpty, "moving a piece costs nothing")
    // damage, mending and what comes back
    var hurt: SuitDesign = g.suit.d
    hurt.pieces[0].dmg = 0.5
    g.suit.d = hurt
    let rb: [Item: Int] = g.suit.d.repairBill()
    check((rb[.mat(.ironBar)] ?? 0) >= 1, "mending costs a share of its metal")
    let back: Int = g.suit.d.bill(to: SuitDesign()).back[.mat(.ironBar)] ?? 0
    check(back < cost, "a worn piece taken off gives back less (\(back) of \(cost))")
    _ = g.inv.add(.mat(.ironBar), 5)
    let msg: String = g.repairSuit()
    check(g.suit.d.pieces[0].dmg == 0, "mending makes it whole (\(msg))")
    // a damaged piece kept as it was keeps its damage through a rebuild
    var hurt2: SuitDesign = g.suit.d
    hurt2.pieces[0].dmg = 0.3
    g.suit.d = hurt2
    var plan2: SuitDesign = g.suit.d
    plan2.pieces[0].dmg = 0
    plan2.pieces[0].y += 1
    _ = g.applyDesign(plan2)
    check(near(g.suit.d.pieces[0].dmg, 0.3), "moving a worn piece doesn't mend it")
    check(SuitTemplates.names.count == 5 && (1...4).allSatisfy { !SuitTemplates.design($0, .iron).pieces.isEmpty }, "ready-made designs to start from")
    let fl: ExoStats = ExoStats.of(SuitTemplates.design(4, .mythril))
    check(fl.has(.hover) && fl.wingArea > 0, "the flyer's design has jets and a wing")
}

print("== old suits rebuilt piece by piece")
do {
    let g = arena()
    var old = ExoSuit()
    old[.helmet] = Stack(item: .exoPart(.helmet, .iron), count: 1, extra: 0, inf: [Infusion.reinforced.rawValue])
    old[.chest] = Stack(item: .exoPart(.chestFrame, .diamond), count: 1)
    old[.legs] = Stack(item: .exoPart(.legs, .iron), count: 1)
    old[.core] = Stack(item: .exoCore(.dynamo), count: 1)
    old[.mod1] = Stack(item: .exoModule(.sprint), count: 1)
    old.worn = true
    old.energy = 50
    var save: SaveData = g.makeSave()
    save.suit = old
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(save))
    let h = Game.load(back, settings: Settings())
    let d: SuitDesign = h.suit.d
    check(h.suit.parts.isEmpty && d.pieces.count >= 7 && d.items.count == 5, "an old suit loads rebuilt as \(d.pieces.count) pieces, its 5 parts kept with it")
    check(h.suit.worn && near(h.suit.energy, 50) && h.suitStats.has(.sprint) && h.suitStats.capacity == ExoCore.dynamo.capacity, "still worn, with its energy, core and booster working")
    check(d.pieces.contains { $0.mat == ExoMat.diamond.rawValue && $0.bone == .torso }, "each part's pieces are of its metal")
    check(h.armorInf.defense >= 1, "an old part's infusion still counts")
    var noLegs: SuitDesign = d
    let legGroup: Int = d.pieces.first { $0.bone == .legBack }!.src
    let legIDs: [Int] = d.pieces.filter { $0.src == legGroup }.map { $0.id }
    noLegs.pieces.removeAll { $0.id == legIDs[0] }
    _ = h.applyDesign(noLegs)
    check(h.inv.total(.exoPart(.legs, .iron)) == 0, "taking off one of its leg pieces gives nothing back yet")
    var noLegs2: SuitDesign = h.suit.d
    noLegs2.pieces.removeAll { $0.src == legGroup }
    _ = h.applyDesign(noLegs2)
    check(h.inv.total(.exoPart(.legs, .iron)) == 1, "taking off the last gives the old part back")
    var noHelm: SuitDesign = h.suit.d
    let helmGroup: Int = h.suit.d.pieces.first { $0.bone == .head }!.src
    noHelm.pieces.removeAll { $0.src == helmGroup }
    _ = h.applyDesign(noHelm)
    let gotHelm: Stack? = h.inv.slots.compactMap { $0 }.first { $0.item == .exoPart(.helmet, .iron) }
    check(gotHelm?.has(.reinforced) == true, "with its infusion")
}

print("== drawn finer, moving with the body")
do {
    let g = arena()
    wearIt(g, SuitTemplates.design(2, .iron))
    let s: SpriteSet = Art.shared.playerSet(g)
    check(s.w == humanW * suitUnit && near(s.scale, 0.125 / 3.0, 0.0001), "the suited player is drawn three times finer at the same size")
    let plain: [PixelBuf] = humanoidFrames(playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil))
    let bb: (Int, Int, Int, Int) = opaqueBounds(plain[0])
    check(s.footRow == bb.3 * suitUnit && near(s.centerCol, Double(bb.0 + bb.2 + 1) * 1.5), "and stands exactly where the plain figure stands")
    let k1: Int = g.armorKey
    var d: SuitDesign = g.suit.d
    d.pieces[0].dmg = 1.0
    g.suit.d = d
    g.suitChanged()
    check(g.armorKey != k1, "a broken piece changes the sprite")
    let leg: SuitPiece = plate(.legFront, 7.0, 13.5, 2.0, 3.0)
    let f0: (Double, Double) = BoneMove.of(.legFront, 0).apply(leg.x, leg.y)
    let f1: (Double, Double) = BoneMove.of(.legFront, 1).apply(leg.x, leg.y)
    let arm: (Double, Double) = BoneMove.of(.armFront, 4).apply(24, 27)
    check(f1.0 > f0.0 && arm.0 > 24.5 && arm.1 < 27, "leg pieces stride with the leg; arm pieces swing out with a blow")
    var cv: PixelBuf = upscale3(plain[0])
    let before: PixelBuf = cv
    var one: SuitDesign = design(SuitDesign(), [plate(.torso, 5.0, 9.0, 4.0, 6.0, .ember)])
    paintSuitPieces(&cv, one, frame: 0)
    check(cv.px != before.px && cv.px.contains { $0 & 0xFFFFFF == ExoMat.ember.color }, "a piece is drawn in its metal")
    one.pieces[0].color = 0x3080FF
    var cv2: PixelBuf = upscale3(plain[0])
    paintSuitPieces(&cv2, one, frame: 0)
    check(cv2.px.contains { $0 & 0xFFFFFF == 0x3080FF }, "or in its paint")
    one.pieces[0].dmg = 1
    var cv3: PixelBuf = upscale3(plain[0])
    paintSuitPieces(&cv3, one, frame: 0)
    check(cv3.px == before.px, "a broken piece is not drawn")
}

// ---------------------------------------------------------------- working parts
print("== jets and wings")
do {
    func flight(_ base: SuitDesign, _ jets: Int, rot: Double = 0, wing: Bool = false) -> Game {
        let g = arena()
        var parts: [SuitPiece] = [SuitTemplates.core(.heart)]
        for k in 0..<jets {
            var j: SuitPiece = SuitTemplates.module(.hover)
            j.w = 6
            j.h = 9
            j.y += Double(k) * 3
            j.rot = rot
            parts.append(j)
        }
        if wing {
            var w: SuitPiece = SuitTemplates.module(.wing)
            w.w = 30
            w.h = 9
            parts.append(w)
        }
        wearIt(g, design(base, parts))
        g.pb.y = 70
        g.pb.onGround = false
        g.pb.vy = 0
        g.jumpHeld = true
        return g
    }
    let light: Game = flight(SuitTemplates.design(1, .mythril), 3)
    check(light.suitStats.thrust > 1.0, "three jets on a light suit lift more than its weight (\(String(format: "%.2f", light.suitStats.thrust)))")
    frames(light, 90)
    check(light.pb.y < 69, "and it flies up while jump is held (from row 70 to \(String(format: "%.1f", light.pb.y)))")
    let heavy: Game = flight(SuitTemplates.design(3, .diamond), 1)
    check(heavy.suitStats.thrust < 1.0 && heavy.suitStats.notes.contains { $0.contains("lift") }, "one jet on a heavy suit can't lift it (\(String(format: "%.2f", heavy.suitStats.thrust))), and the screen says so")
    let none: Game = flight(SuitTemplates.design(3, .diamond), 0)
    frames(heavy, 40)
    frames(none, 40)
    check(heavy.pb.y > 70.5 && heavy.pb.y < none.pb.y - 1, "it only slows the fall (\(String(format: "%.1f", heavy.pb.y - 70)) against \(String(format: "%.1f", none.pb.y - 70)) blocks)")
    let tilt: Game = flight(SuitTemplates.design(1, .mythril), 3, rot: 40)
    tilt.facing = 1
    frames(tilt, 40)
    check(tilt.pb.vx > 1.0, "jets turned back push the suit forward (\(String(format: "%.1f", tilt.pb.vx)))")
    let glide: Game = flight(SuitTemplates.design(1, .mythril), 0, wing: true)
    let drop: Game = flight(SuitTemplates.design(1, .mythril), 0)
    frames(glide, 60)
    frames(drop, 60)
    check(glide.pb.y < drop.pb.y - 3 && glide.pb.vy < 5, "a wing turns a fall into a glide (\(String(format: "%.1f", glide.pb.y - 70)) against \(String(format: "%.1f", drop.pb.y - 70)) blocks)")
}

print("== turrets, cannons and lasers")
do {
    let g = arena()
    // a battery and no core: the energy it spends doesn't come back while we watch
    wearIt(g, design(SuitTemplates.design(1, .iron), [SuitTemplates.module(.battery), SuitTemplates.module(.turret)]))
    let z: Mob = foe(g, .zombie, g.pb.x + 7)
    z.maxHP = 400
    z.hp = 400
    let e0: Double = g.suit.energy
    var shots: Int = 0
    for _ in 0..<180 {
        frame(g)
        z.b.x = g.pb.x + 7
        z.b.vx = 0
        shots = max(shots, g.projectiles.filter { $0.fromPlayer && $0.kind == .bullet }.count)
    }
    check(shots > 0 && z.hp < 400 && g.suit.energy < e0, "a turret shoots the nearest foe by itself (foe at \(Int(z.hp)) of 400)")
    let c = arena()
    wearIt(c, design(SuitTemplates.design(1, .iron), [SuitTemplates.core(.heart), SuitTemplates.module(.cannon)]))
    aimAt(c, c.pb.x + 12, c.pb.y - 3)
    c.suitFireHeld = true
    frame(c)
    let shell: Bool = c.projectiles.contains { $0.kind == .shell && $0.fromPlayer && $0.vx > 0 }
    let left: Double = c.suit.energy
    frames(c, 30)
    let shells: Int = c.projectiles.filter { $0.kind == .shell }.count
    check(shell && left < c.suitStats.capacity && shells <= 1, "SUIT FIRE fires the cannon at the aim, once until it has reloaded")
    let l = arena()
    wearIt(l, design(SuitTemplates.design(1, .iron), [SuitTemplates.core(.heart), SuitTemplates.module(.laser)]))
    let t: Mob = foe(l, .zombie, l.pb.x + 5)
    t.maxHP = 300
    t.hp = 300
    aimAt(l, t.b.x, t.b.cy)
    l.suitFireHeld = true
    var beams: Int = 0
    for _ in 0..<60 {
        frame(l)
        t.b.x = l.pb.x + 5
        aimAt(l, t.b.x, t.b.cy)
        beams += l.suitBeams.count
    }
    check(t.hp < 300 && beams > 30, "the laser burns the foe it is aimed at while SUIT FIRE is held (\(Int(300 - t.hp)) damage)")
    l.suitFireHeld = false
    frame(l)
    check(l.suitBeams.isEmpty, "and stops when it is let go")
}

print("== boosters, energy and the magnet")
do {
    let a = arena()
    wearIt(a, design(SuitTemplates.design(1, .mythril), [SuitTemplates.core(.heart)]))
    let b = arena()
    wearIt(b, design(SuitTemplates.design(1, .mythril), [SuitTemplates.core(.heart), SuitTemplates.module(.sprint), SuitTemplates.module(.sprint)]))
    let c = arena()
    wearIt(c, design(SuitTemplates.design(1, .mythril), [SuitTemplates.core(.heart), SuitTemplates.module(.sprint)]))
    for g in [a, b, c] { g.keyR = true }
    let x0: (Double, Double, Double) = (a.pb.x, b.pb.x, c.pb.x)
    frames(a, 90)
    frames(b, 90)
    frames(c, 90)
    let runs: (Double, Double, Double) = (a.pb.x - x0.0, b.pb.x - x0.1, c.pb.x - x0.2)
    check(runs.1 > runs.2 && runs.2 > runs.0, "each booster adds speed (\(String(format: "%.1f / %.1f / %.1f", runs.0, runs.2, runs.1)))")
    let bat: ExoStats = ExoStats.of(design(SuitDesign(), [SuitTemplates.core(.sparkCell), SuitTemplates.module(.battery)]))
    check(bat.capacity > ExoCore.sparkCell.capacity, "a battery holds more energy (\(Int(bat.capacity)))")
    let s = arena()
    wearIt(s, design(SuitDesign(), [SuitTemplates.module(.battery), SuitTemplates.module(.solar), plate(.torso, 5.0, 9.0, 4.0, 4.0)]))
    s.suit.energy = 0
    frames(s, 60 * 5)
    let sun: Double = s.suit.energy
    s.timeOfDay = 0.75
    s.suit.energy = 0
    frames(s, 60 * 5)
    check(sun > 0.5 && s.suit.energy < 0.01, "a solar panel charges a battery by day under open sky, not at night (\(String(format: "%.1f", sun)) in 5 s)")
    let m = arena()
    wearIt(m, design(SuitTemplates.design(1, .iron), [SuitTemplates.core(.heart), SuitTemplates.module(.magnet)]))
    m.spawnDrop(Stack(item: .mat(.coal), count: 1), m.pb.x + 5, m.pb.y - 1, 0, 0)
    let dx0: Double = m.drops.last!.x - m.pb.x
    frames(m, 40)
    let dx1: Double = (m.drops.last?.x ?? m.pb.x) - m.pb.x
    check(dx1 < dx0 - 1 || m.inv.total(.mat(.coal)) == 1, "the magnet draws dropped things in (\(String(format: "%.1f -> %.1f", dx0, dx1)))")
}

print("== suits in mods")
do {
    var p = ModPack(); p.id = "forge"; p.name = "Forge"
    var bar = ModItem(); bar.id = "starbar"; bar.name = "Star Bar"; bar.kind = .material
    p.items = [bar]
    var m = ModSuitMat(); m.id = "star"; m.name = "Starsteel"; m.color = 0x30E0C0; m.protect = 99; m.weight = 0.5; m.durability = 2; m.cost = .custom("forge:starbar")
    var part = ModSuitPart(); part.id = "lance"; part.name = "Plasma Turret"; part.works = .turret; part.power = 2; part.weight = 1
    p.suitMats = [m]
    p.suitParts = [part]
    var d = ModSuitDesign(); d.id = "knight"; d.name = "Star Knight"
    var g0: SuitDesign = SuitTemplates.design(2, .iron)
    for k in g0.pieces.indices { g0.pieces[k].modMat = "forge:star" }
    var tp: SuitPiece = SuitTemplates.module(.turret)
    tp.modPart = "forge:lance"
    tp.id = g0.newID()
    g0.pieces.append(tp)
    var ghost: SuitPiece = SuitTemplates.module(.laser)
    ghost.modPart = "forge:nothing"
    ghost.id = g0.newID()
    g0.pieces.append(ghost)
    var oddMat: SuitPiece = plate(.torso, 5.0, 9.0, 2.0, 2.0)
    oddMat.modMat = "forge:nope"
    oddMat.id = g0.newID()
    g0.pieces.append(oddMat)
    d.design = g0
    p.suitDesigns = [d]
    let rep: ModReport = ModValidator.check(&p, known: [:])
    check(p.suitMats[0].protect == 3 && rep.errors == 0, "a suit material's numbers are kept in range")
    check(!p.suitDesigns[0].design.pieces.contains { $0.modPart == "forge:nothing" } && p.suitDesigns[0].design.pieces.last?.modMat == "", "a design's missing part is left out, a missing material falls back to the game's")
    ModRuntime.activate([p], world: nil)
    let rt: ModRuntime = ModRuntime.shared
    check(rt.suitMats["forge:star"]?.cost == .custom("forge:starbar") && rt.suitMats["forge:star"]?.color == 0x30E0C0, "the mod's metal is ready, paid with the mod's own bar")
    check(rt.items["forge:lance"] != nil && rt.paletteItems().contains(.custom("forge:lance")), "its working part is an item (craftable, in the palette)")
    check(rt.suitDesigns.count == 1 && rt.suitDesigns[0].0.contains("Star Knight"), "its design is offered at the Assembly Station")
    let ironD: SuitDesign = SuitTemplates.design(2, .iron)
    let starD: SuitDesign = rt.suitDesigns[0].1
    let si: ExoStats = ExoStats.of(ironD)
    let ss: ExoStats = ExoStats.of(starD)
    check(ss.guardAll > si.guardAll * 1.5 && ss.weight < si.weight, "starsteel plates guard better and weigh less than iron (\(Int(si.guardAll * 100))% -> \(Int(ss.guardAll * 100))%)")
    check(ss.count(.turret) == 1 && near(ss.strength(.turret), 2), "the mod's part works as a turret at twice the strength")
    let bill: SuitBill = SuitDesign().bill(to: starD)
    check((bill.pay[.custom("forge:starbar")] ?? 0) > 0, "building starsteel pieces costs Star Bars")
    let g = arena()
    ModRuntime.activate([p], world: nil)
    wearIt(g, starD)
    let shotBefore: Int = g.projectiles.count
    let z: Mob = foe(g, .zombie, g.pb.x + 6)
    z.maxHP = 400
    z.hp = 400
    for _ in 0..<120 {
        frame(g)
        z.b.x = g.pb.x + 6
    }
    check(z.hp < 400 && g.projectiles.count >= shotBefore, "the mod's turret shoots in play")
    let re: ModPack = ModStore.rekey(p, from: "forge", to: "smithy")
    check(re.suitMats[0].cost == .custom("smithy:starbar") && re.suitDesigns[0].design.pieces.contains { $0.modMat == "smithy:star" } && re.suitDesigns[0].design.pieces.contains { $0.modPart == "smithy:lance" }, "renaming the mod renames what its suits use")
    var other = ModPack(); other.id = "fan"; other.name = "Fan"
    var od = ModSuitDesign(); od.id = "x"
    var op: SuitPiece = plate(.torso, 5.0, 9.0, 4.0, 4.0)
    op.modMat = "forge:star"
    od.design.pieces = [op]
    other.suitDesigns = [od]
    check(ModStore.dependencies(other).contains("forge"), "a design using another mod's metal needs that mod")
    let back: ModPack = try! JSONDecoder().decode(ModPack.self, from: try! JSONEncoder().encode(p))
    check(back.suitMats == p.suitMats && back.suitParts == p.suitParts && back.suitDesigns == p.suitDesigns, "suit materials, parts and designs are saved with the mod")
    ModRuntime.activate([], world: nil)
}

print("== saved designs")
do {
    var p = SuitPiece()
    p.x = 9999
    p.w = -4
    p.thick = 9
    p.rot = 725
    p.clamp()
    check(p.x <= suitBodyW + suitMargin && p.w >= 1 && p.thick == 3 && abs(p.rot) < 360, "a piece's numbers are kept within the suit's limits")
    let raw: String = "{\"pieces\":[{\"id\":4,\"x\":12,\"y\":20},{\"id\":\"bad\"}],\"nextID\":1}"
    let d: SuitDesign = try! JSONDecoder().decode(SuitDesign.self, from: raw.data(using: .utf8)!)
    check(d.pieces.count == 2 && d.pieces[0].w == 6 && d.nextID > 4, "a design is read leniently: missing numbers take their defaults, ids never repeat")
}

ModRuntime.activate([], world: nil)
try? FileManager.default.removeItem(at: scratch)
print("suit5: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
