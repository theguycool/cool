import SwiftUI
import Foundation
// Headless screenshots of the alchemy update: mutated creatures beside normal ones, the player in an
// exosuit, the new stations, a smoke cloud and a burst, and a sheet of the new icons and suit pictures
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/alchshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
func render(_ g: Game, _ name: String) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
func steps(_ g: Game, _ n: Int) { for _ in 0..<n { g.tick(1.0 / 60.0) } }

func suitedGame(_ seed: UInt64) -> Game {
    let g = Game(mode: .creative, infinite: true, seed: seed, settings: Settings(), options: .standard)
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
    g.settings.weatherOn = false
    g.tilePx = 30
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 6)
    for x in (cx - 40)...(cx + 40) {
        for y in 60..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) + 0.5; g.pb.y = 100
    // a mixed suit: voidium chest, diamond helmet, iron arms, mythril legs, plates, four modules
    var s = ExoSuit()
    s[.helmet] = Stack(item: .exoPart(.helmet, .diamond), count: 1)
    s[.chest] = Stack(item: .exoPart(.chestFrame, .voidium), count: 1)
    s[.armL] = Stack(item: .exoPart(.arm, .iron), count: 1)
    s[.armR] = Stack(item: .exoPart(.arm, .ember), count: 1)
    s[.legs] = Stack(item: .exoPart(.legs, .mythril), count: 1)
    s[.boots] = Stack(item: .exoPart(.boots, .iron), count: 1)
    s[.core] = Stack(item: .exoCore(.crystal), count: 1)
    s[.plateShoulders] = Stack(item: .exoPlate(.gold), count: 1)
    s[.plateChest] = Stack(item: .exoPlate(.diamond), count: 1)
    s[.plateLegs] = Stack(item: .exoPlate(.iron), count: 1)
    s[.mod1] = Stack(item: .exoModule(.drill), count: 1)
    s[.mod2] = Stack(item: .exoModule(.lamp), count: 1)
    s[.mod3] = Stack(item: .exoModule(.cargo), count: 1)
    s[.mod4] = Stack(item: .exoModule(.hover), count: 1)
    for st in s.parts.values { g.addStack(st) }
    _ = g.applySuit(s)
    _ = g.wearSuit()
    g.suit.energy = 300
    return g
}

// 1: the meadow: creatures at each step of mutation, the stations, smoke and a burst
do {
    let g = suitedGame(4242)
    let cx = Int(g.pb.x)
    g.world.set(cx - 4, 99, .alchemyStill)
    g.world.set(cx - 6, 99, .infuser)
    g.world.set(cx - 8, 99, .exoStation)
    var x: Double = g.pb.x + 3
    for doses in 0...3 {
        let m = g.addMob(.cow, x, 100)
        m.persistent = true
        m.dir = -1
        for _ in 0..<doses { _ = g.mutate(m) }
        x += m.b.w + 1.6
    }
    let z = g.addMob(.zombie, g.pb.x - 13, 100)
    z.persistent = true
    let z2 = g.addMob(.zombie, g.pb.x - 17, 100)
    z2.persistent = true
    _ = g.mutate(z2)
    z2.slowT = 5; z2.slowAmt = 0.5; z2.poisonT = 5
    g.smokes.append(SmokeCloud(x: g.pb.x - 20, y: 98.5, r: 3.0, t: 6, maxT: 8))
    g.rings.append(BurstRing(x: g.pb.x - 9, y: 99, r: 3, t: 0.2, color: Potion.frost.color))
    var p = Projectile(kind: .flask, x: g.pb.x + 1.5, y: 96.5, vx: 6, vy: -2, dmg: 0, fromPlayer: true, gravity: 0)
    p.potion = Potion.blight.rawValue
    p.life = 2
    g.projectiles.append(p)
    // (the moment of mutation flashes white; the picture shows them after it)
    for m in g.mobs { m.flash = 0 }
    g.timeOfDay = 0.3
    g.pauseMobs = true
    g.pauseProjectiles = true
    g.light.valid = false
    steps(g, 3)
    g.camX = g.pb.x - 2; g.camY = 95
    render(g, "1_meadow")
}

// 2: night under ground: the helmet lamp lights the way, the drill arm at a seam of ore
do {
    let g = suitedGame(777)
    let cx = Int(g.pb.x)
    for x in (cx - 40)...(cx + 40) { for y in 80..<100 { g.world.set(x, y, .stone) } }
    for x in (cx - 14)...(cx + 14) { for y in 96..<100 { g.world.set(x, y, .air); g.world.setWall(x, y, 1) } }
    for x in (cx + 4)...(cx + 7) { g.world.set(x, 97, .iron); g.world.set(x, 98, .gold) }
    g.timeOfDay = 0.75
    g.light.valid = false
    g.mode = .survival
    g.godMode = true
    steps(g, 4)
    g.camX = g.pb.x; g.camY = 96
    render(g, "2_lamp_underground")
}

// 3: a sheet: every potion, compound and suit item, and the builder's pictures of three suits
do {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    fillRect(&ctx, mkRect(0, 0, Double(W), Double(H)), Color(hex: 0x262A32))
    var items: [Item] = featureItems()
    items += [.mat(.vial), .mat(.waterVial), .mat(.sunleaf), .mat(.glowcap), .mat(.slimeGel), .mat(.venomSac), .mat(.frostCrystal), .mat(.emberAsh), .mat(.wraithDust), .mat(.stormEssence), .mat(.golemCore), .mat(.sentinelLens), .mat(.mutantGland)]
    items += [.block(.alchemyStill), .block(.infuser), .block(.exoStation)]
    let size: Double = 36
    for (i, it) in items.enumerated() {
        let col: Int = i % 18
        let row: Int = i / 18
        let r: CGRect = mkRect(16 + Double(col) * (size + 6), 16 + Double(row) * (size + 6), size, size)
        fillRect(&ctx, r, Color.black.opacity(0.4))
        ctx.draw(pixImage(itemBuf(it)), in: mkRect(Double(r.minX) + 4, Double(r.minY) + 4, size - 8, size - 8))
    }
    var a = ExoSuit()
    a[.chest] = Stack(item: .exoPart(.chestFrame, .iron), count: 1)
    a[.core] = Stack(item: .exoCore(.sparkCell), count: 1)
    a[.helmet] = Stack(item: .exoPart(.helmet, .iron), count: 1)
    var b = a
    b[.armL] = Stack(item: .exoPart(.arm, .bronze), count: 1)
    b[.armR] = Stack(item: .exoPart(.arm, .bronze), count: 1)
    b[.legs] = Stack(item: .exoPart(.legs, .gold), count: 1)
    b[.boots] = Stack(item: .exoPart(.boots, .gold), count: 1)
    b[.plateChest] = Stack(item: .exoPlate(.gold), count: 1)
    b[.mod1] = Stack(item: .exoModule(.sprint), count: 1)
    var c = ExoSuit()
    for (sl, it) in [(ExoSlot.helmet, Item.exoPart(.helmet, .voidium)), (.chest, .exoPart(.chestFrame, .voidium)), (.armL, .exoPart(.arm, .ember)), (.armR, .exoPart(.arm, .diamond)),
                     (.legs, .exoPart(.legs, .mythril)), (.boots, .exoPart(.boots, .mythril)), (.core, .exoCore(.heart)), (.plateHead, .exoPlate(.voidium)), (.plateShoulders, .exoPlate(.ember)),
                     (.plateChest, .exoPlate(.voidium)), (.plateArms, .exoPlate(.diamond)), (.plateLegs, .exoPlate(.mythril)), (.mod1, .exoModule(.drill)), (.mod2, .exoModule(.hover)),
                     (.mod3, .exoModule(.cargo)), (.mod4, .exoModule(.gauntlet))] {
        c[sl] = Stack(item: it, count: 1)
    }
    let suits: [ExoSuit] = [a, b, c]
    for (k, s) in suits.enumerated() {
        let x0: Double = 30 + Double(k) * 360
        let y0: Double = 300
        ctx.draw(pixImage(suitViewBuf(s, 0)), in: mkRect(x0, y0, 120, 168))
        ctx.draw(pixImage(suitViewBuf(s, 1)), in: mkRect(x0 + 125, y0, 120, 168))
        var st: HumanStyle = playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil)
        st.suit = suitLookOf(s)
        ctx.draw(pixImage(humanoidFrame(st, legs: 1, pose: 0)), in: mkRect(x0 + 245, y0 + 40, 110, 85))
    }
    GraphicsContext.target = nil
    t.save(outDir + "/3_sheet.rgb")
    print("rendered 3_sheet")
}
