import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double) -> Bool { return abs(a - b) <= eps }

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
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }

/// a standard generated-style tree: trunk of `logT` 6 tall at x, canopy above
func plantTree(_ g: Game, _ x: Int, _ logT: Tile = .log, _ leaf: Tile = .leaves) {
    for k in 1...6 { g.world.set(x, 100 - k, logT) }
    for dy in -3...1 { for dx in -2...2 { if g.world.tile(x + dx, 94 + dy) == .air { g.world.set(x + dx, 94 + dy, leaf) } } }
}

/// walk with the stick held for `secs`, return x travelled
func walk(_ g: Game, _ dir: Double, _ secs: Double) -> Double {
    let x0 = g.pb.x
    var t = 0.0
    while t < secs { g.stick = dir; g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    g.stick = 0
    return g.pb.x - x0
}

// ---------------------------------------------------------------- 1. tree logs
print("== tree logs")
do {
    for (logT, leaf, name) in [(Tile.log, Tile.leaves, "oak"), (.jungleLog, .jungleLeaves, "jungle"), (.palmLog, .jungleLeaves, "palm")] {
        let g = arena()
        let tx = Int(floor(g.pb.x)) + 4
        plantTree(g, tx, logT, leaf)
        let dx = walk(g, 1, 1.6)
        check(g.pb.x > Double(tx) + 2, "walking right through a \(name) trunk (moved \(String(format: "%.1f", dx)) blocks, ended at x \(String(format: "%.1f", g.pb.x - Double(tx))) past it)")
        let dx2 = walk(g, -1, 1.6)
        check(g.pb.x < Double(tx) - 1, "walking back left through the \(name) trunk (moved \(String(format: "%.1f", dx2)))")
    }
    // standing inside the trunk and jumping straight up through it and the canopy, then landing on top
    let g = arena()
    let tx = Int(floor(g.pb.x))
    plantTree(g, tx)
    check(!g.world.boxSolid(g.pb.left, g.pb.top, g.pb.right, g.pb.y - 0.01), "the player overlapping a trunk is not inside anything solid")
    g.jumpHeld = true
    var topY = g.pb.y
    var t = 0.0
    while t < 0.6 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; topY = min(topY, g.pb.y) }
    g.jumpHeld = false
    check(topY < 98.0, String(format: "jumping inside the trunk is not blocked (rose to y %.1f)", topY))
    // drop onto the canopy from above: leaves are one-way platforms, so the player lands on them
    g.pb.x = Double(tx) + 0.5; g.pb.y = 85; g.pb.vy = 0
    step(g, 1.5)
    check(near(g.pb.y, 91, 0.05), String(format: "falling onto the canopy lands on top of the leaves (feet y %.2f, canopy top 91)", g.pb.y))
    // walk sideways at canopy height through the leaves
    g.pb.x = Double(tx) - 6.5; g.pb.y = 95.0; g.pb.vy = 0; g.flying = true
    let dxc = walk(g, 1, 1.2)
    check(dxc > 7, String(format: "flying sideways through the canopy is not blocked (moved %.1f)", dxc))
    g.flying = false
    // creatures, drops and projectiles pass through trunks too
    let m = g.addMob(.zombie, Double(tx) - 3.5, 100)
    m.persistent = true
    var tm = 0.0
    while tm < 2.5 { m.b.vx = 2.0; g.stepMob(m, 1.0 / 60.0); tm += 1.0 / 60.0 }
    check(m.b.x > Double(tx) + 1, String(format: "a creature walks through the trunk (x %.1f)", m.b.x - Double(tx)))
    // fell the tree: no collision anywhere it stood
    g.fellTree(tx, 99)
    var any = false
    for y in 85...99 { for x in (tx - 3)...(tx + 3) where g.world.tile(x, y).solid { any = true } }
    check(!any, "after felling, nothing solid remains where the tree stood")
    // placed logs are a solid building block
    let g2 = arena()
    let px = Int(floor(g2.pb.x)) + 2
    g2.inv.slots[0] = Stack(item: .block(.log), count: 10)
    g2.sel = 0
    g2.aimX = Double(px) + 0.5; g2.aimY = 99.5; g2.aimValid = true
    g2.usePlaceBlock(.log, 1.0 / 60.0)
    check(g2.world.tile(px, 99) == .logBlock && g2.world.tile(px, 99).solid, "placing a log item builds a solid log block")
    g2.breakTile(px, 99, true)
    check(g2.drops.contains { $0.stack.item == .block(.log) }, "breaking a log block drops a log item")
    // sand still rests on a trunk
    let g3 = arena()
    let sx = Int(floor(g3.pb.x)) + 5
    for k in 1...3 { g3.world.set(sx, 100 - k, .log) }
    g3.world.set(sx, 90, .sand)
    g3.checkFalling(sx, 90)
    step(g3, 1.5)
    check(g3.world.tile(sx, 96) == .sand, "falling sand comes to rest on top of a trunk")
}

// generated trees in real worlds: no solid tile anywhere a trunk stands, and the ground under it is solid
do {
    var trunks = 0, blocked = 0
    for seed in [UInt64(4242), 777, 31337] {
        let wg = WorldGen(seed: seed, infinite: true, rareChance: 0.28)
        for cx in -12...12 {
            let ch = generateChunk(wg, .overworld, cx)
            for lx in 0..<chunkW {
                var y = 1
                while y < 300 {
                    let t = ch.get(lx, y)
                    if isLogTile(t) {
                        trunks += 1
                        if t.solid { blocked += 1 }
                    }
                    y += 1
                }
            }
        }
    }
    check(trunks > 200 && blocked == 0, "generated worlds: \(trunks) trunk tiles checked, \(blocked) with collision")
}

// ---------------------------------------------------------------- 3. explosion light
print("== explosion light")
func cave(_ g: Game) -> (Int, Int) {
    // a sealed stone room 40 wide, 10 tall, deep underground (no sky light at all)
    let cx = Int(floor(g.pb.x))
    let y0 = 300
    g.world.loadAround(centerX: cx, radius: 5)
    for x in (cx - 30)...(cx + 30) { for y in (y0 - 14)...(y0 + 4) { g.world.set(x, y, .stone) } }
    for x in (cx - 25)...(cx + 25) { for y in (y0 - 10)...(y0 - 1) { g.world.set(x, y, .air) } }
    // a wall splitting the room, with the far side sealed off
    for y in (y0 - 10)...(y0 - 1) { for x in (cx + 12)...(cx + 14) { g.world.set(x, y, .stone) } }
    g.pb.x = Double(cx - 20) + 0.5; g.pb.y = Double(y0); g.pb.vx = 0; g.pb.vy = 0
    g.debugSetTime(0.75)
    g.light.valid = false
    return (cx, y0)
}
func lightAt(_ g: Game, _ x: Int, _ y: Int) -> Int { return g.light.covers(x, y, x, y) ? g.light.level(x, y).1 : -1 }
do {
    let g = arena()
    let (cx, y0) = cave(g)
    step(g, 0.3)
    let bx = cx + 6, by = y0 - 4
    let near0 = lightAt(g, bx + 3, by), behind0 = lightAt(g, cx + 16, by)
    g.explode(Double(bx) + 0.5, Double(by) + 0.5, radius: 3.0, power: 0, source: .environment, breakBlocks: false)
    step(g, 1.0 / 60.0)
    let near1 = lightAt(g, bx + 3, by), behind1 = lightAt(g, cx + 16, by), open1 = lightAt(g, bx - 10, by)
    step(g, 0.35)
    let near2 = lightAt(g, bx + 3, by)
    step(g, 0.6)
    let near3 = lightAt(g, bx + 3, by)
    check(near0 == 0 && near1 >= 10, "a blast in a dark cave lights blocks 3 away (light \(near0) -> \(near1))")
    check(near2 > 0 && near2 < near1, "the light fades smoothly (\(near1) -> \(near2) after 0.35 s)")
    check(near3 == near0 && g.flashes.isEmpty, "after the blast the light returns to darkness (\(near3)) and the flash is removed")
    check(behind1 < open1, "a thick wall shades the far side: 10 blocks away behind it \(behind0) -> \(behind1), 10 blocks away in the open \(open1)")
    // two blasts far apart each light their own area
    let g2 = arena()
    let (cx2, y02) = cave(g2)
    step(g2, 0.3)
    g2.explode(Double(cx2 - 8) + 0.5, Double(y02 - 4) + 0.5, radius: 3, power: 0, source: .environment, breakBlocks: false)
    g2.explode(Double(cx2 + 6) + 0.5, Double(y02 - 4) + 0.5, radius: 3, power: 0, source: .environment, breakBlocks: false)
    step(g2, 1.0 / 60.0)
    check(lightAt(g2, cx2 - 8, y02 - 4) >= 14 && lightAt(g2, cx2 + 6, y02 - 4) >= 14 && g2.flashes.count == 2, "two blasts light both spots independently")
    // the other dimension
    let g3 = arena()
    g3.debugSwitchDimension()
    step(g3, 0.5)
    let ux = Int(floor(g3.pb.x)) - 7, uy = Int(floor(g3.pb.y)) - 3
    let u0 = lightAt(g3, ux, uy)
    g3.explode(Double(ux) + 0.5, Double(uy) + 0.5, radius: 3, power: 0, source: .environment, breakBlocks: false)
    step(g3, 1.0 / 60.0)
    check(lightAt(g3, ux, uy) > u0 && lightAt(g3, ux, uy) >= 14, "a blast lights up the Umbral Realm too (\(u0) -> \(lightAt(g3, ux, uy)))")
    step(g3, 1.0)
    check(g3.flashes.isEmpty, "flashes are cleaned up in the Umbral Realm")
    // daytime surface: the flash is recorded (drawn as glow) even though the light map is already full
    let g4 = arena()
    g4.debugSetTime(0.25)
    step(g4, 0.3)
    g4.explode(g4.pb.x + 5, 98, radius: 3, power: 0, source: .environment, breakBlocks: false)
    step(g4, 1.0 / 60.0)
    check(g4.flashes.count == 1 && g4.flashes[0].strength > 0.9, "a daytime blast keeps its flash for the glow")
    step(g4, 1.0)
    check(g4.flashes.isEmpty, "and removes it when it fades")
    // a real bomb: thrown, explodes when its fuse runs out, flashes
    let g5 = arena()
    let (cx5, y05) = cave(g5)
    step(g5, 0.3)
    g5.inv.slots[0] = Stack(item: .gadget(.bomb), count: 3); g5.sel = 0
    g5.aimX = Double(cx5 - 14); g5.aimY = Double(y05 - 3); g5.aimValid = true
    g5.throwBomb()
    var sawFlash = false
    var t5 = 0.0
    while t5 < 3.2 { g5.tick(1.0 / 60.0); t5 += 1.0 / 60.0; if !g5.flashes.isEmpty { sawFlash = true } }
    check(sawFlash && g5.flashes.isEmpty && g5.projectiles.isEmpty, "a thrown bomb explodes with a flash that is cleaned up afterwards")
}

// ---------------------------------------------------------------- 4. clouds
print("== clouds")
do {
    let layers = CloudField.layers.count
    func all(_ seed: UInt64, _ d: Double, _ x0: Double, _ x1: Double, _ fill: Double) -> [[CloudField.Cloud]] {
        return (0..<layers).map { CloudField.clouds(seed, $0, d, x0, x1, fill: fill) }
    }
    let a = all(4242, 7.5, -500, 500, 0.6)
    let b = all(4242, 7.5, -500, 500, 0.6)
    let n = a.reduce(0) { $0 + $1.count }
    check(n > 150 && a.indices.allSatisfy { i in a[i].count == b[i].count && zip(a[i], b[i]).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.kind == $1.kind } }, "clouds are placed deterministically (\(n) across 1000 blocks)")
    let kinds = Set(a.flatMap { $0 }.map { $0.kind })
    check(kinds.count >= 18 && CloudArt.shared.shapes.count == 24, "clouds come in many shapes (\(kinds.count) of \(CloudArt.shared.shapes.count) used)")
    let widths = CloudArt.shared.shapes.map { $0.w }
    check((widths.min() ?? 0) <= 46 && (widths.max() ?? 0) >= 190, "sizes run from small puffs (\(widths.min() ?? 0) px) to huge formations (\(widths.max() ?? 0) px)")
    // a bigger sky than the old single row: the big class is at least four times the old widest cloud
    check(CloudArt.shared.classes.count == 5 && CloudArt.shared.classes.allSatisfy { !$0.isEmpty }, "all five size classes have templates")
    let later = all(4242, 17.5, -500, 500, 0.6)
    var movedOK = true
    for li in 0..<layers {
        let sp = CloudField.layers[li].speed
        if let c0 = a[li].first(where: { $0.alpha == 1 }), let c1 = later[li].first(where: { $0.kind == c0.kind && abs($0.y - c0.y) < 0.001 && $0.x > c0.x }) {
            if !near(c1.x - c0.x, 10.0 * sp, 0.01) { movedOK = false }
        } else { movedOK = false }
    }
    check(movedOK, "every layer drifts with the wind at its own speed")
    // groups: some cells hold a loose formation of several clouds close together
    var grouped = false
    for l in a { let s = l.sorted { $0.x < $1.x }; for i in 4..<max(4, s.count) where s[i].x - s[i - 4].x < 30 && abs(s[i].y - s[i - 4].y) < 8 { grouped = true } }
    check(grouped, "clouds sometimes gather in formations")
    // the sky is never empty and never solid
    var emptyWindow = false, solidWindow = false
    var wx = -400.0
    while wx < 400 {
        let w = all(4242, 7.5, wx, wx + 40, 0.46)
        let cnt = w.reduce(0) { $0 + $1.count }
        if cnt < 2 { emptyWindow = true }
        let wc = all(4242, 7.5, wx, wx + 40, 0.0)
        if wc.reduce(0, { $0 + $1.count }) > 0 { solidWindow = true }
        wx += 40
    }
    check(!emptyWindow, "a clear-sky window always has some cloud in it")
    check(!solidWindow, "fill 0 means no cloud at all")
    let thin = all(4242, 7.5, -200, 200, 0.46).reduce(0) { $0 + $1.count }
    let thick = all(4242, 7.5, -200, 200, 0.92).reduce(0) { $0 + $1.count }
    check(thick > thin * 3 / 2, "an overcast sky holds more cloud than a clear one (\(thin) vs \(thick))")
    let g = arena()
    g.flying = true
    g.pb.x = 0; g.pb.y = 78
    for y in 60..<95 { for x in -20...20 { g.world.set(x, y, .air) } }
    let x0 = g.pb.x
    for _ in 0..<60 { g.stick = 1; g.tick(1.0 / 60.0) }
    g.stick = 0
    check(g.pb.x - x0 > 6, "flying through the sky is not blocked by clouds")
    let t0 = perfNow()
    for i in 0..<500 { _ = all(4242, Double(i) * 0.1, Double(i), Double(i) + 60, 0.9) }
    let ms = (perfNow() - t0) * 1000 / 500
    check(ms < 0.3, String(format: "placing every visible cloud costs %.4f ms per frame", ms))
}

// ---------------------------------------------------------------- 5. creature art
print("== creatures")
do {
    var variants: [(MobKind, Int)] = MobKind.allCases.map { ($0, 0) }
    variants += [(.sheep, 1), (.wolf, 1), (.zombie, 1), (.zombie, 2), (.villager, 1), (.villager, 2), (.villager, 3)]
    // every creature (and variant) builds, at the one shared pixel scale
    var scales = Set<Double>()
    var badFrames: [String] = []
    var t0 = perfNow()
    for (k, v) in variants {
        let set = creatureSpriteSet(k, v)
        scales.insert(set.scale)
        let n = set.right.count
        let a = set.anim
        // every frame index the renderer can ask for exists
        // walkers use frames 0-2; swimmers, fliers and hoppers only their own frames
        var need = a.cycle.isEmpty && !a.hop ? 2 : 0
        if isHumanoid(k) { need = 6 }
        if k == .bearBoss { need = 3 }
        if k == .rex { need = 2 }
        if a.attack >= 0 { need = max(need, a.attack) }
        if a.idleAlt >= 0 { need = max(need, a.idleAlt) }
        for c in a.cycle { need = max(need, c) }
        if a.hop { need = max(1, a.attack) }
        if n <= need { badFrames.append("\(k)/\(v): \(n) frames, needs \(need + 1)") }
    }
    let buildMs = (perfNow() - t0) * 1000
    check(scales == [0.125], "all \(variants.count) creatures and variants share one pixel scale (8 art pixels per block, like terrain and the player): \(scales.sorted())")
    check(badFrames.isEmpty, "every frame the renderer can pick exists \(badFrames)")
    check(buildMs < 4000, String(format: "building every creature's frames takes %.0f ms (once per kind, on first sight)", buildMs))
    // outlines are a darkened version of the colour they border (the old art used one near-black for
    // everything, luminance 25), never pure black, and there is no speckle noise (few colours per frame)
    var darkest = 999.0
    var sumMean = 0.0, nMean = 0.0
    var allOutlineColours = Set<UInt32>()
    var maxColours = 0
    for (k, v) in variants {
        let fr = creatureArt(k, v).0
        for b in fr {
            var colours = Set<UInt32>()
            var edgeColours = Set<UInt32>()
            var edgeSum = 0.0, edgeN = 0.0
            for y in 0..<b.h { for x in 0..<b.w {
                let c = b.px[y * b.w + x]
                if (c >> 24) == 0 { continue }
                colours.insert(c & 0xFFFFFF)
                let edge = (b.get(x - 1, y) >> 24) == 0 || (b.get(x + 1, y) >> 24) == 0 || (b.get(x, y - 1) >> 24) == 0 || (b.get(x, y + 1) >> 24) == 0
                if edge { let l = artLum(c & 0xFFFFFF); darkest = min(darkest, l); edgeSum += l; edgeN += 1; edgeColours.insert(c & 0xFFFFFF) }
            } }
            maxColours = max(maxColours, colours.count)
            allOutlineColours.formUnion(edgeColours)
            sumMean += edgeSum / max(1, edgeN); nMean += 1
            _ = k
        }
    }
    let meanOutline = sumMean / max(1, nMean)
    check(darkest > 10 && meanOutline > 35, String(format: "outlines are tinted, never pure black: average outline luminance %.0f (old fixed outline 25), darkest %.0f", meanOutline, darkest))
    check(allOutlineColours.count > 60, "outlines take the colour of what they border (\(allOutlineColours.count) different outline colours across all creatures; the old art used one)")
    check(maxColours <= 48, "restrained palettes: at most \(maxColours) colours in any frame (bosses included)")
    t0 = perfNow()
    for (k, v) in variants { _ = creatureArt(k, v) }
    _ = t0

    // turning: a creature that changes direction plays a short turn and ends facing the new way
    let g = arena()
    let m = g.addMob(.pig, g.pb.x + 6, 100)
    m.persistent = true
    step(g, 0.2)
    let before = m.face
    m.dir = -before
    g.updateMobs(1.0 / 60.0)
    check(m.turnT > 0, "a change of direction starts the turn animation (turn time \(String(format: "%.2f", m.turnT)) s)")
    m.dir = -before
    step(g, 0.3)
    m.dir = -before
    g.updateMobs(1.0 / 60.0)
    check(m.face == -before && m.turnT == 0, "after the turn the sprite faces the new direction")
    // AI direction is untouched by the animation
    check(m.dir == -before, "the turn is visual only: the creature's direction is unchanged")

    // attack: a hostile creature that hits the player shows its attack frame and lunges
    let g2 = arena()
    g2.monstersEnabled = true
    let wolfM = g2.addMob(.slime, g2.pb.x + 0.3, 100)
    wolfM.persistent = true
    wolfM.angry = true
    var sawAttack = false
    var maxAtk = 0.0
    for _ in 0..<240 {
        g2.tick(1.0 / 60.0)
        if wolfM.atkT > 0 {
            maxAtk = max(maxAtk, wolfM.atkT)
            let set = Art.shared.mobSet(wolfM)
            if WorldRenderer.mobFrame(wolfM, set, g2.clock) == set.anim.attack { sawAttack = true }
        }
    }
    check(sawAttack && g2.hp < g2.maxHP, "a slime that hits the player shows its bite frame (attack timer up to \(String(format: "%.2f", maxAtk)) s, player hp \(String(format: "%.0f", g2.hp))/\(String(format: "%.0f", g2.maxHP)))")
    // idle variation: grazing animals sometimes lower their heads while standing
    let g3 = arena()
    let cow = g3.addMob(.cow, g3.pb.x + 5, 100)
    cow.persistent = true
    step(g3, 0.5)
    let cset = Art.shared.mobSet(cow)
    var graze = 0, idle = 0
    var clock = 0.0
    while clock < 30 {
        cow.b.vx = 0; cow.b.onGround = true
        let f = WorldRenderer.mobFrame(cow, cset, clock)
        if f == 3 { graze += 1 } else if f == 0 { idle += 1 }
        clock += 0.05
    }
    check(graze > 0 && idle > graze, "a standing cow grazes part of the time (\(graze) grazing vs \(idle) idle samples)")
    // flyers loop their wing frames, hoppers use the air frame off the ground
    let bat = g3.addMob(.bat, g3.pb.x + 3, 95)
    let bset = Art.shared.mobSet(bat)
    var seen = Set<Int>()
    for i in 0..<40 { bat.anim = Double(i) * 0.3; seen.insert(WorldRenderer.mobFrame(bat, bset, 0)) }
    check(seen == [0, 1, 2], "a bat cycles through its three wing frames (\(seen.sorted()))")
    let sl = g3.addMob(.slime, g3.pb.x + 8, 100)
    let sset = Art.shared.mobSet(sl)
    sl.b.onGround = false
    let air = WorldRenderer.mobFrame(sl, sset, 0)
    sl.b.onGround = true
    let ground = WorldRenderer.mobFrame(sl, sset, 0)
    check(air == 1 && ground == 0, "a slime stretches in the air and rests on the ground")
    // the whole scene still draws with every creature on screen (stub canvas)
    let g4 = arena()
    var i = 0
    for k in MobKind.allCases where k != .bearBoss && k != .rex {
        let mm = g4.addMob(k, g4.pb.x - 30 + Double(i) * 2.2, 99)
        mm.persistent = true
        i += 1
    }
    var ctx = GraphicsContext()
    let size = CGSize(width: 1180, height: 820)
    for n in 0..<120 {
        g4.tick(1.0 / 60.0)
        if n % 20 == 0 { for mm in g4.mobs { mm.dir = -mm.dir } }
        WorldRenderer.draw(&ctx, size, g4)
    }
    check(g4.mobs.count >= 28, "every creature kind drew for 2 s while turning back and forth (\(g4.mobs.count) on screen)")
}

// ---------------------------------------------------------------- 6. flat world
print("== flat world")
func flatGame(_ infinite: Bool, _ seed: UInt64, _ opts: WorldOptions, _ mode: GameMode = .survival) -> Game {
    let g = Game(mode: mode, infinite: infinite, seed: seed, settings: Settings(), options: opts)
    g.viewW = 1100; g.viewH = 800
    return g
}
let surfaceTiles: Set<Tile> = [.grass, .sand, .snow, .jungleGrass, .dryGrass, .mossGrass]
let fillerTiles: Set<Tile> = [.dirt, .sand, .mud]
let oreTiles: Set<Tile> = [.coal, .copper, .iron, .gold, .diamond, .mythril, .tin, .saltpeter, .silver, .amethyst]
let decorTiles: Set<Tile> = [.log, .jungleLog, .palmLog, .leaves, .jungleLeaves, .tallGrass, .flowerR, .flowerY, .cactus, .reed, .mushroom, .deadBush,
                             .birchLog, .birchLeaves, .pineLeaves]
/// landmark pieces (boulders, fallen logs, bones, ice spikes, cairns, mounds, a ruin's chest and the
/// cairn's torch): allowed only within four rows of the ground, so a hill could never pass as one
let landmarkTiles: Set<Tile> = [.stone, .mossGrass, .snow, .logBlock, .jungleLogBlock, .birchLogBlock, .fossil, .sandstone, .ice, .dirt, .chest, .torch]
/// checks every column of the given chunks against the flat layer stack; columns under structures are skipped
let caveTiles: Set<Tile> = [.air, .water, .lava, .mushroom, .cobweb]
/// checks every column of the given chunks against the flat layer stack; columns under structures are skipped
func flatScan(_ g: WorldGen, _ cxs: [Int]) -> (cols: Int, bad: [String], heights: Set<Int>, decor: Int, skipped: Int, caveTiles: Int, pondCols: Int) {
    var bad: [String] = []
    var heights = Set<Int>()
    var decor = 0, n = 0, skipped = 0, caves = 0, ponds = 0, structTiles = 0
    for cx in cxs {
        let c = generateChunk(g, .overworld, cx)
        let x0 = cx * chunkW
        let vs = g.villages(overlapping: x0 - 20, x0 + chunkW + 20)
        let rs = g.rareSites(overlapping: x0 - 40, x0 + chunkW + 40)
        for lx in 0..<chunkW {
            let x = x0 + lx
            if !g.infinite && (x < 0 || x >= g.width) { continue }
            heights.insert(g.col(x).h)
            var inStruct = abs(x - g.portalX) < 14
            // old mines are structures with a covered shaft through the crust
            for m in g.mineSites(overlapping: x - 4, x + 4) where x >= m.x - 2 && x <= m.x + (m.plan == nil ? 4 : 10) { inStruct = true }
            for v in vs where abs(x - v.x) <= v.halfW + 16 { inStruct = true }
            for r in rs where abs(x - r.x) <= 34 { inStruct = true }
            if g.lairAt(x, radius: 60) != nil { inStruct = true }
            if inStruct { skipped += 1; continue }
            n += 1
            func t(_ y: Int) -> Tile { return c.get(lx, y) }
            let H = WorldGen.H
            let s = WorldGen.flatSurface
            let pd = g.pondDepth(x)
            if pd > 0 {
                ponds += 1
                for y in s..<(s + pd) where !(t(y) == .water || (t(y) == .ice && y == s)) { bad.append("x \(x) y \(y): pond holds \(t(y))"); break }
                if t(s + pd) != .sand { bad.append("x \(x): pond bed \(t(s + pd))") }
            } else if g.nearPond(x, 1) {
                if t(s) != .sand { bad.append("x \(x): pond bank \(t(s))") }
            } else if !surfaceTiles.contains(t(s)) { bad.append("x \(x): surface \(t(s))") }
            for y in (s + max(1, pd + 1))...(s + 4) where !fillerTiles.contains(t(y)) { bad.append("x \(x) y \(y): topsoil \(t(y))"); break }
            // rows dug out by underground structures (mine galleries, crystal grottos and their passages)
            var dug: [ClosedRange<Int>] = []
            for m in g.mineSites(overlapping: x - 2, x + 2) {
                if let plan = m.plan {
                    // a newer mine: every space its plan opens, with the floor, rubble and ore round it
                    for sp in plan.carve where abs(sp.x - x) <= 1 { dug.append((sp.y0 - 2)...(sp.y1 + 2)) }
                    for c in plan.chests where abs(c.x - x) <= 1 { dug.append((c.y - 1)...(c.y + 1)) }
                } else {
                    for (i, f) in m.levels.enumerated() where x >= m.x - m.left[i] - 1 && x <= m.x + 2 + m.right[i] + 1 { dug.append((f - 4)...(f + 1)) }
                }
            }
            for gs in g.grottoSites(overlapping: x - 2, x + 2) {
                if abs(x - gs.x) <= gs.rx + 3 { dug.append((gs.floorY - gs.ry * 2 - 4)...(gs.floorY + 3)) }
                let k = (x - gs.passStartX) * gs.dir
                if k >= 0 && k <= gs.passLen { dug.append((gs.floorY - k - 5)...(gs.floorY - k + 1)) }
            }
            for y in (s + 5)..<(H - 3) {
                let k = t(y)
                let want: Tile = y < 300 ? .stone : (y < 430 ? .slate : .deepRock)
                if k == want || oreTiles.contains(k) { continue }
                if dug.contains(where: { $0.contains(y) }) {
                    // underground structures stay below the crust
                    if y - s < WorldGen.flatCrust { bad.append("x \(x) y \(y): a structure breaks the crust (\(k))"); break }
                    structTiles += 1; continue
                }
                if g.options.caves && y - s >= WorldGen.flatCrust && caveTiles.contains(k) { caves += 1; continue }
                bad.append("x \(x) y \(y): \(k) instead of \(want)"); break
            }
            for y in (H - 3)..<H where t(y) != .bedrock { bad.append("x \(x) y \(y): no bedrock"); break }
            for y in 0..<s {
                let k = t(y)
                if k == .air { continue }
                if decorTiles.contains(k) || (landmarkTiles.contains(k) && y >= s - 4) { decor += 1 } else { bad.append("x \(x) y \(y): \(k) above the surface"); break }
            }
        }
    }
    return (n, bad, heights, decor, skipped, caves, ponds)
}
do {
    let full = WorldOptions(flat: true, trees: true, structures: true)
    // an infinite flat world: near spawn, and chunks a hundred thousand blocks out either way
    let gi = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, options: full)
    let far = Array(-130...130) + Array(6240...6260) + Array(-6260...(-6240))
    let si = flatScan(gi, far)
    check(si.heights == [WorldGen.flatSurface], "infinite flat world: every one of \(far.count * chunkW) columns has its surface at row \(WorldGen.flatSurface) (heights \(si.heights.sorted()))")
    check(si.bad.isEmpty, "infinite flat world: the same layers in all \(si.cols) open columns, out to 100 000 blocks: surface, 4 topsoil, stone to 300, slate to 430, deep rock, bedrock; no caves, water or lava \(si.bad.prefix(4))")
    check(si.decor > 200, "trees and plants grow on it (\(si.decor) tiles)")
    let ruins = gi.rareSites(overlapping: -2100, 2100).count
    let lairs = gi.lairCenters(near: 0).count
    check(gi.villages(overlapping: -2100, 2100).isEmpty && ruins > 0 && lairs > 0, "structures on: no villages, \(ruins) ruins and \(lairs) boss lairs within 2100 blocks")
    // a flat world saved before generator version 5 keeps the villages it already has, at the flat surface
    let g4 = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, genVersion: 4, options: full)
    var villageGround = Set<Int>()
    var vill = 0
    for v in g4.villages(overlapping: -2100, 2100) { vill += 1; villageGround.insert(v.ground) }
    check(vill > 0 && villageGround == [WorldGen.flatSurface], "a version-4 flat world keeps its \(vill) villages, all built at the flat surface")
    // a classic flat world, edge to edge
    let gc = WorldGen(seed: 777, infinite: false, rareChance: 0.28, options: full)
    let sc = flatScan(gc, Array(0..<(WorldGen.finiteWidth / chunkW)))
    check(sc.heights == [WorldGen.flatSurface] && sc.bad.isEmpty, "classic flat world: all \(sc.cols) open columns of the 4096-wide world are flat with the same layers \(sc.bad.prefix(3))")
    let edge = generateChunk(gc, .overworld, -1)
    check(edge.tiles.allSatisfy { $0 == Tile.bedrock.rawValue }, "classic flat world: bedrock beyond the world edge (no edge ocean)")
    // toggles
    let bare = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, options: WorldOptions(flat: true, trees: false, structures: false))
    let sb = flatScan(bare, Array(-130...130))
    check(sb.decor == 0 && sb.bad.isEmpty && sb.skipped < 30, "trees off, structures off: bare flat ground, no trees or plants (\(sb.decor) decoration tiles, \(sb.skipped) columns at the portal chamber)")
    check(bare.villages(overlapping: -5000, 5000).isEmpty && bare.rareSites(overlapping: -5000, 5000).isEmpty && bare.lairCenters(near: 0).isEmpty && bare.lairAt(1000) == nil, "structures off: no villages, ruins or boss lairs")
    let pc = generateChunk(bare, .overworld, floorDiv(bare.portalX, chunkW))
    var portalTiles = 0
    for b in pc.tiles where b == Tile.portalOff.rawValue { portalTiles += 1 }
    check(portalTiles > 0 && bare.portalY > WorldGen.flatSurface + 200, "the buried portal chamber is still there (row \(bare.portalY), \(portalTiles) portal tiles), so the Umbral Realm stays reachable")
    // generation cost compared with a standard world
    var t0 = perfNow()
    for cx in 300..<340 { _ = generateChunk(gi, .overworld, cx) }
    let flatMs = (perfNow() - t0) * 1000 / 40
    let gs = WorldGen(seed: 4242, infinite: true, rareChance: 0.28)
    t0 = perfNow()
    for cx in 300..<340 { _ = generateChunk(gs, .overworld, cx) }
    let stdMs = (perfNow() - t0) * 1000 / 40
    check(flatMs < stdMs, String(format: "a flat chunk generates in %.2f ms (standard %.2f ms)", flatMs, stdMs))
}
do {
    // safe spawn: on the surface, on the ground, nothing solid in the way, dry, unhurt; several seeds, both world kinds
    var problems: [String] = []
    for seed in [UInt64(1), 2, 3, 4242, 99991] {
        for infinite in [true, false] {
            for opts in [WorldOptions(flat: true, trees: true, structures: true), WorldOptions(flat: true, trees: false, structures: false)] {
                let g = flatGame(infinite, seed, opts)
                g.monstersEnabled = false
                step(g, 2.0)
                let x = Int(floor(g.pb.x))
                let headClear = !g.world.solid(x, Int(floor(g.pb.y)) - 1) && !g.world.solid(x, Int(floor(g.pb.y)) - 2)
                if !(near(g.pb.y, Double(WorldGen.flatSurface), 0.01) && g.pb.onGround && headClear && !g.pb.inWater && g.hp == g.maxHP) {
                    problems.append("seed \(seed) \(infinite ? "infinite" : "classic"): y \(g.pb.y) ground \(g.pb.onGround) head \(headClear) hp \(g.hp)")
                }
            }
        }
    }
    check(problems.isEmpty, "safe spawn on 20 flat worlds: standing on the surface, head clear, dry, unhurt \(problems.prefix(3))")
}
do {
    // mining and building with the normal controls
    let g = flatGame(true, 4242, WorldOptions(flat: true, trees: false, structures: false))
    g.monstersEnabled = false
    step(g, 1.0)
    _ = g.inv.add(.tool(.pickaxe, .stone), 1)
    var pick = 0
    for (i, s) in g.inv.slots.enumerated() { if case .tool(.pickaxe, _)? = s?.item, i < Inventory.hotbarCount { pick = i } }
    g.setSel(pick)
    let tx = Int(floor(g.pb.x)) + 1
    let s = WorldGen.flatSurface
    var mined = 0
    for y in s...(s + 2) {
        g.aimX = Double(tx) + 0.5; g.aimY = Double(y) + 0.5; g.aimValid = true
        g.useHeld = true
        var t = 0.0
        while t < 6 && g.world.tile(tx, y) != .air { g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
        g.useHeld = false
        g.tick(1.0 / 60.0)
        if g.world.tile(tx, y) == .air { mined += 1 }
    }
    step(g, 1.5)
    var dirt = 0
    var dirtSlot = -1
    var soil: Tile = .dirt
    for (i, s) in g.inv.slots.enumerated() { if let st = s, case .block(let bt) = st.item, fillerTiles.contains(bt) { dirt += st.count; soil = bt; if i < Inventory.hotbarCount { dirtSlot = i } } }
    check(mined == 3 && dirt >= 2, "mining: dug the surface block and two rows of topsoil with a pickaxe (\(mined) of 3), and picked up the \(soil) (\(dirt))")
    // stone further down breaks and drops too
    let before = g.drops.count
    g.breakTile(tx, 200, true)
    check(g.world.tile(tx, 200) == .air && g.drops.count > before, "mining: stone deeper down breaks and drops")
    // build: put the dirt back into the hole
    if dirtSlot < 0 { for (i, s) in g.inv.slots.enumerated() where i < Inventory.hotbarCount && s == nil { dirtSlot = i; break } }
    if dirtSlot >= 0 {
        g.setSel(dirtSlot)
        g.aimX = Double(tx) + 0.5; g.aimY = Double(s + 2) + 0.5; g.aimValid = true
        g.useHeld = true
        step(g, 0.3)
        g.useHeld = false
    }
    check(g.world.tile(tx, s + 2) == soil, "building: placed a \(soil) block back in the hole (\(g.world.tile(tx, s + 2)))")
}
do {
    // creatures spawn on flat ground: animals by day, monsters at night
    let g = flatGame(true, 4242, WorldOptions(flat: true, trees: true, structures: false))
    g.timeOfDay = 0.25
    step(g, 40)
    let day = g.mobs.filter { !$0.def.hostile && $0.kind != .villager }.count
    for m in g.mobs { m.removed = true }
    g.mobs.removeAll()
    g.timeOfDay = 0.72
    step(g, 40)
    let night = g.mobs.filter { $0.def.hostile }.count
    let kinds = Set(g.mobs.map { "\($0.kind)" })
    check(day > 0 && night > 0, "mobs spawn on a flat world: \(day) animals by day, \(night) monsters at night (\(kinds.sorted()))")
}
do {
    // streaming far out in an infinite flat world
    let g = flatGame(true, 4242, WorldOptions(flat: true, trees: true, structures: true))
    g.monstersEnabled = false
    g.debugTeleport(100_000.5, Double(WorldGen.flatSurface) - 3)
    step(g, 2.0)
    var flatOK = true
    for x in 99_900...100_100 where g.world.isLoaded(x) && g.world.tile(x, WorldGen.flatSurface + 1) != .dirt && !fillerTiles.contains(g.world.tile(x, WorldGen.flatSurface + 1)) { flatOK = false }
    check(flatOK && near(g.pb.y, Double(WorldGen.flatSurface), 0.01) && g.world.chunks.count > 6, "streaming chunks 100 000 blocks out: flat ground, player lands on the surface (\(g.world.chunks.count) chunks loaded)")
}
do {
    // the world type is saved with the world and survives loading; old saves stay standard
    let opts = WorldOptions(flat: true, trees: false, structures: true)
    let g = flatGame(true, 99, opts)
    g.monstersEnabled = false
    step(g, 0.5)
    let bx = Int(floor(g.pb.x)) + 3
    g.world.set(bx, WorldGen.flatSurface - 1, .brick)
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let gl = Game.load(back, settings: Settings())
    check(gl.gen.options == opts && back.meta.options == opts, "the world type is stored in the save and restored on load (flat \(gl.gen.options.flat), trees \(gl.gen.options.trees), structures \(gl.gen.options.structures))")
    check(gl.world.tile(bx, WorldGen.flatSurface - 1) == .brick, "edits in a loaded flat world are kept")
    let a = generateChunk(g.gen, .overworld, 900), b = generateChunk(gl.gen, .overworld, 900)
    check(a.tiles == b.tiles, "chunks that were never saved regenerate identically after loading")
    // a save from before world types existed has no options key: it loads as a standard world
    var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    var meta = json["meta"] as! [String: Any]
    meta.removeValue(forKey: "options")
    json["meta"] = meta
    let oldData = try! JSONSerialization.data(withJSONObject: json)
    let old = try! JSONDecoder().decode(SaveData.self, from: oldData)
    let go = Game.load(old, settings: Settings())
    check(old.meta.options == nil && go.gen.options == .standard && !go.gen.options.flat, "an older save without a world type loads as a standard world (not converted)")
    // and standard worlds save as standard
    let gstd = Game(mode: .survival, infinite: true, seed: 5, settings: Settings())
    let sdata = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(gstd.makeSave()))
    check(Game.load(sdata, settings: Settings()).gen.options == .standard, "a standard world stays standard through save and load")
}

// ---------------------------------------------------------------- 7. flat world, round 3
print("== flat world: travel, arenas, caves, ponds, saves")
/// walks with the real controls, holding jump (a full jump) whenever blocked; returns stuck spots
func walkFar(_ g: Game, _ dir: Double, _ dist: Double, _ maxT: Double) -> (moved: Double, stuck: [String]) {
    // plays like a person heading one way: jumps whatever is in the way, swims up out of water, and if
    // stuck in a hole climbs the nearest ladder
    let x0 = g.pb.x
    var stuck: [String] = []
    var t = 0.0, still = 0.0, lastX = g.pb.x, jumpT = 0.0
    var ladderX: Int? = nil
    var ladderTop = 0
    while abs(g.pb.x - x0) < dist && t < maxT {
        var stick = dir
        if let lx = ladderX {
            // step onto the ladder, climb it to the top, then carry on
            if !g.onLadder() && abs(Double(lx) + 0.5 - g.pb.x) > 0.3 { stick = Double(lx) + 0.5 > g.pb.x ? 1 : -1 } else { stick = 0; jumpT = 0.1 }
            if g.pb.y <= Double(ladderTop) + 0.05 && !g.onLadder() { ladderX = nil }
        }
        g.stick = stick
        if g.pb.hitWall && g.pb.onGround { jumpT = 0.45 }
        if g.pb.inWater { jumpT = 0.1 }
        g.jumpHeld = jumpT > 0
        jumpT -= 1.0 / 60.0
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if abs(g.pb.x - lastX) < 0.02 && ladderX == nil { still += 1.0 / 60.0 } else { still = 0 }
        lastX = g.pb.x
        if still > 1.2 && ladderX == nil {
            // look for a ladder at this level before giving up
            let ix = Int(floor(g.pb.x)), iy = Int(floor(g.pb.y - 0.5))
            for d in 0...10 { for sx in [ix - d, ix + d] where g.world.tile(sx, iy) == .ladder && ladderX == nil { ladderX = sx } }
            if let lx = ladderX {
                var top = iy
                while g.world.tile(lx, top - 1) == .ladder { top -= 1 }
                ladderTop = top
                still = 0
                continue
            }
        }
        if still > 2.0 {
            let ix = Int(floor(g.pb.x))
            var what = ""
            if let L = g.gen.lairAt(ix, radius: 70) { what = " near the \(L.kind) lair" }
            for v in g.gen.villages(overlapping: ix - 2, ix + 2) { what += " in the village at \(v.x)" }
            for r in g.gen.rareSites(overlapping: ix - 40, ix + 40) where abs(r.x - ix) < 40 { what += " at a \(r.kind) ruin" }
            let feetRow = Int(floor(g.pb.y)) - 1
            let blockers = (0..<4).map { "\(g.world.tile(ix + Int(dir), feetRow - $0))" }.joined(separator: ",")
            stuck.append(String(format: "x %.1f y %.2f%@ (in front: %@; at feet %@, water %@)", g.pb.x, g.pb.y, what, blockers, "\(g.world.tile(ix, Int(floor(g.pb.y))))", g.pb.inWater ? "yes" : "no"))
            g.pb.x += dir * 3; still = 0
        }
    }
    g.stick = 0; g.jumpHeld = false
    return (abs(g.pb.x - x0), stuck)
}
do {
    // walking a flat world with every structure on: past both boss lairs, villages and ruins, both ways
    var allStuck: [String] = []
    var walked = 0.0
    var passed = Set<String>()
    for seed in [UInt64(271828), 4242, 99] {
        let g = flatGame(true, seed, WorldOptions(flat: true, trees: true, structures: true, caves: true, ponds: true))
        g.godMode = true
        g.monstersEnabled = false
        for dir in [1.0, -1.0] {
            g.debugTeleport(Double(g.gen.spawnX) + 0.5, Double(WorldGen.flatSurface) - 0.5)
            step(g, 0.3)
            let t0w = g.clock
            let r = walkFar(g, dir, 1500, 420)
            walked += r.moved
            print(String(format: "   seed %d dir %+.0f: %.0f blocks in %.0f s", Int(seed), dir, r.moved, g.clock - t0w))
            allStuck += r.stuck.map { "seed \(seed): " + $0 }
        }
        for v in g.gen.villages(overlapping: -1500, 1500) { passed.insert("village \(v.x)") }
        for r in g.gen.rareSites(overlapping: -1500, 1500) { passed.insert("\(r.kind) ruin") }
        for L in g.gen.lairCenters(near: 0) where abs(L.cx) < 1500 { passed.insert("\(L.kind) lair") }
    }
    check(allStuck.isEmpty && walked > 8500, String(format: "walked %.0f blocks across three flat worlds with the normal controls, through %d villages, ruins and lairs, never blocked", walked, passed.count) + (allStuck.isEmpty ? "" : " STUCK: \(allStuck.prefix(5))"))
}
do {
    // a flat world's lairs are open arenas on the surface and the boss stands on the ground
    for kind in [LairKind.bear, .rex] {
        let g = flatGame(true, 4242, WorldOptions(flat: true, trees: true, structures: true))
        g.monstersEnabled = false
        let L = g.gen.lairCenters(near: 0).first { $0.kind == kind }!
        var dug = 0
        let ch = generateChunk(g.gen, .overworld, floorDiv(L.cx, chunkW))
        for lx in 0..<chunkW { if ch.get(lx, WorldGen.flatSurface) == .air { dug += 1 } }
        g.debugTeleport(Double(L.cx) - 40.5, Double(WorldGen.flatSurface) - 0.5)
        step(g, 2.0)
        let boss = g.mobs.first { $0.isBoss }
        let ok = boss.map { $0.b.onGround && near($0.b.y, Double(WorldGen.flatSurface), 0.05) && !g.world.boxSolid($0.b.left + 0.05, $0.b.top, $0.b.right - 0.05, $0.b.y - 0.05) } ?? false
        check(dug == 0 && ok, "flat \(kind) lair: no pit (\(dug) open surface tiles), the boss stands on the arena floor at row \(WorldGen.flatSurface) (y \(boss.map { String(format: "%.2f", $0.b.y) } ?? "none"))")
    }
    // standard worlds keep their pit lairs; walking straight through one (down the slope, across the
    // floor, past the ribs or boulders, up the far side) never gets stuck
    for kind in [LairKind.bear, .rex] {
        let g = flatGame(true, 4242, .standard)
        g.godMode = true
        g.monstersEnabled = false
        let L = g.gen.lairCenters(near: 0).first { $0.kind == kind }!
        g.defeated.insert(g.lairKey(L))
        g.debugTeleport(Double(L.cx) - 56.5, Double(WorldGen.sea - 10) - 0.5)
        step(g, 0.5)
        let r = walkFar(g, 1, 112, 90)
        check(r.stuck.isEmpty && r.moved >= 111, String(format: "standard world: walked through the %@ lair pit end to end (%.0f blocks)", "\(kind)", r.moved) + (r.stuck.isEmpty ? "" : " STUCK \(r.stuck)"))
    }
}
do {
    // caves: under an unbroken 16-row crust, branching tunnels and chambers with their lakes and lava
    let g = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, options: WorldOptions(flat: true, trees: true, structures: true, caves: true, ponds: true))
    let sc = flatScan(g, Array(-160...160))
    check(sc.bad.isEmpty && sc.heights == [WorldGen.flatSurface], "caves on: still flat, the crust intact and the layers right in all \(sc.cols) open columns \(sc.bad.prefix(3))")
    check(sc.caveTiles > 20000, "caves on: \(sc.caveTiles) cave tiles under 5100 blocks of ground (tunnels, chambers, lakes, deep lava)")
    check(sc.pondCols > 20, "ponds: \(sc.pondCols) pond columns, every one holding water level with the ground on a sand bed with sandy banks")
    // the same chunk generates the same way every time (unload, reload, revisit)
    var same = true
    for cx in [-3, 0, 7, 61, 6250] {
        let a = generateChunk(g, .overworld, cx).tiles
        g.cache.clear()
        let b = generateChunk(g, .overworld, cx).tiles
        if a != b { same = false }
    }
    check(same, "chunks regenerate identically (also after the generator cache is cleared)")
    // neighbouring chunks meet without a step: the ground row matches across every boundary
    var seams = 0
    var seamAt: [Int] = []
    for cx in -40...40 {
        let a = generateChunk(g, .overworld, cx), b = generateChunk(g, .overworld, cx + 1)
        let s = WorldGen.flatSurface
        let bx = cx * chunkW + chunkW
        let built = !g.villages(overlapping: bx - 20, bx + 20).isEmpty || !g.rareSites(overlapping: bx - 40, bx + 40).isEmpty || g.lairAt(bx, radius: 60) != nil || abs(bx - g.portalX) < 16
        if a.surf[chunkW - 1] != b.surf[0] || a.surf[chunkW - 1] != s { seams += 1; seamAt.append(bx) }
        if !built && !g.nearPond(bx, 2) && a.get(chunkW - 1, s + 2).solid != b.get(0, s + 2).solid { seams += 1; seamAt.append(bx) }
    }
    check(seams == 0, "80 chunk boundaries line up exactly (\(seams) mismatches \(seamAt))")
}
do {
    // a long session: walk out, dig, walk back, revisit, save to disk, load from disk
    let g = flatGame(true, 271828, WorldOptions(flat: true, trees: true, structures: true, caves: true, ponds: true))
    g.godMode = true
    g.monstersEnabled = false
    let r = walkFar(g, 1, 900, 300)
    let hx = Int(floor(g.pb.x)) + 2
    for y in WorldGen.flatSurface...(WorldGen.flatSurface + 2) { g.breakTile(hx, y, true) }
    g.world.set(hx - 4, WorldGen.flatSurface - 1, .brick)
    let back = walkFar(g, -1, 900, 300)
    g.debugTeleport(Double(hx) + 5.5, Double(WorldGen.flatSurface) - 0.5)
    step(g, 1.0)
    let kept = g.world.tile(hx, WorldGen.flatSurface) == .air && g.world.tile(hx - 4, WorldGen.flatSurface - 1) == .brick
    check(r.stuck.isEmpty && back.stuck.isEmpty && kept, String(format: "walked %.0f out and %.0f back; the hole and the placed brick are still there on return", r.moved, back.moved))
    g.slot = 9
    g.worldName = "Round3 flat"
    let saved = g.saveNow()
    let meta = SaveStore.meta(9)
    if let data = SaveStore.read(9) {
        let gl = Game.load(data, settings: Settings())
        gl.viewW = 1100; gl.viewH = 800
        gl.debugTeleport(Double(hx) + 5.5, Double(WorldGen.flatSurface) - 0.5)
        step(gl, 1.0)
        let ok = gl.gen.options == g.gen.options && gl.world.tile(hx, WorldGen.flatSurface) == .air && gl.world.tile(hx - 4, WorldGen.flatSurface - 1) == .brick
        check(saved && meta?.options == g.gen.options && ok, "saved to disk, closed and reopened: still a flat world with caves and ponds, edits intact (list entry: \(meta.map { "\($0.name), flat \($0.options?.flat ?? false)" } ?? "missing"))")
    } else {
        check(false, "the save could be read back from disk")
    }
    SaveStore.delete(9)
}
do {
    // saves from the first flat-world release (no caves or ponds keys) keep generating exactly as before
    let json = #"{"flat":true,"trees":true,"structures":true}"#
    let o = try! JSONDecoder().decode(WorldOptions.self, from: json.data(using: .utf8)!)
    check(o.flat && o.trees && o.structures && !o.caves && !o.ponds, "an earlier flat world's options decode with caves and ponds off (its unexplored ground stays cave-free)")
    let broken = #"{"trees":false}"#
    let o2 = try! JSONDecoder().decode(WorldOptions.self, from: broken.data(using: .utf8)!)
    check(!o2.flat && !o2.trees, "missing keys never fail the whole save (a partial options entry decodes)")
}
do {
    // creatures never appear inside solid ground: spawn for a while and inspect everyone
    let g = flatGame(true, 4242, WorldOptions(flat: true, trees: true, structures: true, caves: true, ponds: true))
    g.godMode = true
    var inside = 0, total = 0
    for night in [false, true] {
        g.timeOfDay = night ? 0.72 : 0.25
        for _ in 0..<1800 {
            g.tick(1.0 / 60.0)
        }
        for m in g.mobs where m.hp > 0 && !m.def.flying {
            total += 1
            if g.world.boxSolid(m.b.left + 0.06, m.b.top + 0.06, m.b.right - 0.06, m.b.y - 0.08) { inside += 1 }
        }
    }
    check(total > 5 && inside == 0, "\(total) creatures spawned on a flat world, none inside solid ground")
    let d = mobDef(.cow)
    let wallX = Int(floor(g.pb.x)) + 6
    for y in (WorldGen.flatSurface - 3)..<WorldGen.flatSurface { g.world.set(wallX, y, .stone) }
    check(!g.spawnSpotClear(d, Double(wallX) + 0.5, Double(WorldGen.flatSurface)) && g.spawnSpotClear(d, Double(wallX) + 4.5, Double(WorldGen.flatSurface)), "the spawn check refuses a spot inside a wall and accepts open ground")
}

print("")
print(fails == 0 ? "ALL \(passes) TESTS PASSED" : "\(fails) FAILED, \(passes) passed")
