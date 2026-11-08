import SwiftUI
import Foundation
// Phase 3 of the overhaul, building and physics: blocks placed as walls, ladders built on by holding,
// furniture (sitting, sleeping, storage, beds in one piece), stairs walked up and down, lifts, block
// weight, blasts that destroy, throw or spare blocks by hardness and weight, storms carrying light
// blocks, and optional structural physics. Everything through the game's own code.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f2(_ v: Double) -> String { return String(format: "%.2f", v) }

/// A flat stone floor at row 100 (the land: not built), air above, nothing spawning, daytime
func arena(_ seed: UInt64 = 4242, mode: GameMode = .survival) -> Game {
    let g = Game(mode: mode, infinite: true, seed: seed, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.settings.weatherOn = false
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 6)
    for x in x0...(x0 + 80) {
        for y in 20..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.hp = g.maxHP
    g.timeOfDay = 0.25
    return g
}
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) {
    var t = 0.0
    while t < secs { g.tick(dt); g.hunger = 20; t += dt }
}
func hold(_ g: Game, _ item: Item, _ n: Int = 1) {
    g.inv.slots[0] = Stack(item: item, count: n)
    g.setSel(0)
}
func aimAt(_ g: Game, _ x: Double, _ y: Double) { g.aimX = x; g.aimY = y; g.aimValid = true }
/// One press of the use control at (x, y)
func use(_ g: Game, _ x: Int, _ y: Int) {
    aimAt(g, Double(x) + 0.5, Double(y) + 0.5)
    g.placeCD = 0
    g.useCD = 0
    g.usePressedFlag = true
    g.useHeld = true
    g.updateUse(1.0 / 60.0)
    g.useHeld = false
    g.usePressedFlag = false
}
/// Holding the use control for `secs` while aiming at (x, y)
func holdUse(_ g: Game, _ x: Double, _ y: Double, _ secs: Double) {
    var t = 0.0
    aimAt(g, x, y)
    g.useHeld = true
    while t < secs {
        aimAt(g, x, y)
        g.updateUse(1.0 / 60.0)
        t += 1.0 / 60.0
    }
    g.useHeld = false
}
/// Builds a block as the player would have (marked as built)
func build(_ g: Game, _ x: Int, _ y: Int, _ t: Tile) {
    g.world.set(x, y, t)
    g.world.setBuilt(x, y, true)
}

// ---------------------------------------------------------------- walls
print("== blocks as walls")
do {
    let g = arena()
    let px = Int(g.pb.x)
    check(canBeWall(.planks) && canBeWall(.brick) && canBeWall(.stone) && canBeWall(.glass), "planks, brick, stone and glass can go up as walls")
    check(!canBeWall(.chest) && !canBeWall(.furnace) && !canBeWall(.doorClosed) && !canBeWall(.bedrock) && !canBeWall(.water) && !canBeWall(.torch), "chests, furnaces, doors, bedrock, water and torches cannot")
    hold(g, .block(.planks), 10)
    check(g.canToggleWall && !g.wallMode, "holding planks, the HUD offers the WALL switch (off to begin with)")
    g.toggleWallMode()
    use(g, px + 2, 98)
    let wall: Int = g.world.wallAt(px + 2, 98)
    check(g.world.tile(px + 2, 98) == .air && blockWallTile(wall) == .planks && g.inv.total(.block(.planks)) == 9, "with it on, a plank goes up as a wall: no block there, a planks wall behind (one plank used)")
    check(!g.world.boxSolid(Double(px + 2), 97.0, Double(px + 3), 99.0), "and nothing solid: the player walks through it")
    let ch: Chunk = g.world.chunks[floorDiv(px + 2, chunkW)]!
    let back: [UInt8] = g.world.backdrop(ch)
    check(Int(back[(px + 2 - ch.x0) * ch.H + 98]) == wall, "the backdrop behind the cell is the planks wall")
    let paint: [UInt32] = SectionPainter.shared.paint(g.world, ch, 98 / 16)
    let lx: Int = px + 2 - ch.x0
    let ly: Int = 98 - (98 / 16) * 16
    var drawn: Int = 0
    for yy in 0..<8 { for xx in 0..<8 where (paint[(ly * 8 + yy) * 128 + lx * 8 + xx] >> 24) != 0 { drawn += 1 } }
    check(drawn == 64, "and it is drawn ( \(drawn) of 64 pixels of the wall's cell painted)")
    check(wallName(wall) == "Planks Wall", "it is called \(wallName(wall))")
    g.toggleWallMode()
    use(g, px + 3, 99)
    check(g.world.tile(px + 3, 99) == .planks, "with the switch off, planks go up solid again")
    g.world.setWall(px + 4, 96, blockWallValue(.stone))
    use(g, px + 4, 96)
    check(g.world.tile(px + 4, 96) == .planks, "and a block can be put in front of a wall with nothing else to hold onto")
    // mining the wall gives the plank back
    g.inv = Inventory()
    hold(g, .tool(.pickaxe, .iron), 1)
    var t = 0.0
    while t < 3.0 && g.world.wallAt(px + 2, 98) != 0 {
        _ = g.mineWall(px + 2, 98, .pickaxe, .iron, 1.0 / 60.0)
        t += 1.0 / 60.0
    }
    var back2: Int = 0
    for d in g.drops where d.stack.item == .block(.planks) { back2 += d.stack.count }
    check(g.world.wallAt(px + 2, 98) == 0 && back2 == 1, "a pickaxe takes the wall down and it drops as a plank (\(back2))")
    // kept in the save
    g.world.setWall(px + 5, 97, blockWallValue(.brick))
    let s: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    let g2 = Game.load(s, settings: Settings())
    check(blockWallTile(g2.world.wallAt(px + 5, 97)) == .brick, "a brick wall is kept when the world is saved and loaded")
}

// ---------------------------------------------------------------- ladders
print("== ladders built on by holding")
do {
    let g = arena()
    let px = Int(g.pb.x)
    // a shaft down beside the player, a ladder at its top
    for y in 100...130 { g.world.set(px + 2, y, .air) }
    g.world.set(px + 2, 100, .ladder)
    hold(g, .block(.ladder), 40)
    holdUse(g, Double(px + 2) + 0.5, 100.5, 3.0)
    var rungs: Int = 0
    var gap: Bool = false
    var y = 100
    while g.world.tile(px + 2, y) == .ladder { rungs += 1; y += 1 }
    for yy in y...131 where g.world.tile(px + 2, yy) == .ladder { gap = true }
    let used: Int = 40 - g.inv.total(.block(.ladder))
    check(rungs > 3 && !gap && used == rungs - 1, "holding place on the ladder builds it on downward: \(rungs) rungs in one unbroken line, \(used) ladders used")
    check(!g.inReach(Double(px + 2) + 0.5, Double(y) + 0.5), "it stops where the player can no longer reach (next rung at row \(y))")
    // upward, aiming above the head
    g.world.set(px + 1, 97, .ladder)
    hold(g, .block(.ladder), 2)
    holdUse(g, Double(px + 1) + 0.5, 97.5, 3.0)
    var up: Int = 0
    for yy in 80...97 where g.world.tile(px + 1, yy) == .ladder { up += 1 }
    check(up == 3 && g.inv.total(.block(.ladder)) == 0, "aiming above the head builds it upward, and with 2 ladders it stops after 2 (\(up) rungs in all)")
    // creative: no ladders used, and further down
    let c = arena(mode: .creative)
    let cx = Int(c.pb.x)
    for y in 100...140 { c.world.set(cx + 2, y, .air) }
    c.world.set(cx + 2, 100, .ladder)
    hold(c, .block(.ladder), 1)
    holdUse(c, Double(cx + 2) + 0.5, 100.5, 4.0)
    var cr: Int = 0
    var cy = 100
    while c.world.tile(cx + 2, cy) == .ladder { cr += 1; cy += 1 }
    check(cr > rungs && c.inv.total(.block(.ladder)) == 1, "in creative it costs nothing and reaches further (\(cr) rungs)")
}

// ---------------------------------------------------------------- furniture
print("== furniture")
do {
    let g = arena()
    let px = Int(g.pb.x)
    for (k, t) in [Tile.chair, .table, .cabinet, .wardrobe, .shelf, .bookshelf, .floorLamp, .sofa].enumerated() {
        hold(g, .block(t), 1)
        use(g, px - 4 + k, 99)
    }
    var placed: [String] = []
    for k in 0..<8 where g.world.tile(px - 4 + k, 99) != .air { placed.append(g.world.tile(px - 4 + k, 99).def.name) }
    check(placed.count == 8, "chair, table, cabinet, wardrobe, shelf, bookshelf, floor lamp and sofa all place (\(placed))")
    check(g.world.isBuilt(px - 4, 99) && g.world.isBuilt(px + 3, 99), "and count as built")
    check(Tile.lightTable[Int(Tile.floorLamp.rawValue)] >= 12 && Tile.table.isPlatform && Tile.cabinet.isPlatform, "the lamp lights the room; tables and cabinets can be stood on")
    // a bed is two tiles
    g.pb.x = Double(px + 5) + 0.5
    hold(g, .block(.bedL), 1)
    use(g, px + 6, 99)
    check(g.world.tile(px + 6, 99) == .bedL && g.world.tile(px + 7, 99) == .bedR && g.inv.total(.block(.bedL)) == 0, "a bed takes two tiles, its head on the left")
    // sitting
    g.pb.x = Double(px - 4) + 0.5
    g.interact(Double(px - 4) + 0.5, 99.5)
    step(g, 1.0)
    check(g.seat != nil && abs(g.pb.x - (Double(px - 4) + 0.5)) < 0.01 && abs(g.pb.y - 100) < 0.01, "tapping the chair sits the player on it, and they stay there")
    g.keyR = true
    step(g, 0.3)
    g.keyR = false
    check(g.seat == nil && g.pb.x > Double(px - 4) + 0.6, "walking off gets them up")
    // sleeping
    g.pb.x = Double(px + 6) + 0.5
    g.timeOfDay = 0.25
    g.interact(Double(px + 6) + 0.5, 99.5)
    check(abs(g.spawnX - Double(px + 7)) < 0.01 && g.timeOfDay == 0.25, "by day the bed only becomes where the player wakes up")
    g.timeOfDay = 0.75
    let day0: Int = g.dayCount
    let z: Mob = g.addMob(.zombie, g.pb.x + 5, 100)
    g.mobGrid.rebuild(g.mobs)
    g.interact(Double(px + 6) + 0.5, 99.5)
    check(g.isNight, "with a zombie close by the player cannot sleep (still night)")
    z.hp = 0; z.removed = true
    g.mobs.removeAll()
    g.hp = 10
    g.interact(Double(px + 7) + 0.5, 99.5)
    check(!g.isNight && g.dayCount == day0 + 1 && g.hp > 10, "with none, they sleep until morning (day \(day0) -> \(g.dayCount)) and feel better")
    // storage
    g.pb.x = Double(px - 1) + 0.5
    g.interact(Double(px - 2) + 0.5, 99.5)
    check(g.openChest == IntPair(x: px - 2, y: 99) && g.showInventory, "a cabinet opens like a chest")
    g.showInventory = false
    g.openChest = nil
    g.world.setChestItems(px - 2, 99, [Stack(item: .mat(.coal), count: 7)])
    g.breakTile(px - 2, 99, true)
    var coal: Int = 0
    var cab: Int = 0
    for d in g.drops {
        if d.stack.item == .mat(.coal) { coal += d.stack.count }
        if d.stack.item == .block(.cabinet) { cab += d.stack.count }
    }
    check(coal == 7 && cab == 1, "breaking it spills what it held and drops the cabinet")
    // a bed comes down whole and drops one bed
    g.drops.removeAll()
    g.breakTile(px + 7, 99, false)
    var beds: Int = 0
    for d in g.drops where d.stack.item == .block(.bedL) { beds += d.stack.count }
    check(g.world.tile(px + 6, 99) == .air && g.world.tile(px + 7, 99) == .air && beds == 1, "breaking either half takes the whole bed down, one bed dropped")
    // recipes
    let outs: [Item] = RecipeBook.base.map { $0.out }
    var missing: [String] = []
    for t in [Tile.chair, .table, .bedL, .cabinet, .wardrobe, .shelf, .bookshelf, .floorLamp, .sofa, .stairWoodR, .stairStoneR, .stairBrickR, .liftRail, .liftButton, .liftCar] where !outs.contains(.block(t)) { missing.append(t.def.name) }
    check(missing.isEmpty, "every piece of furniture, the stairs and the lift parts can be crafted" + (missing.isEmpty ? "" : " (missing \(missing))"))
    check(!allGameItems().contains(.block(.bedR)) && !allGameItems().contains(.block(.stairWoodL)) && allGameItems().contains(.block(.sofa)), "the creative palette has one bed and one of each stair")
}

// ---------------------------------------------------------------- stairs
print("== stairs")
do {
    let g = arena()
    let px = Int(g.pb.x)
    // six wooden stairs rising to the right, then a landing at row 94
    for k in 0..<6 { build(g, px + 3 + k, 99 - k, .stairWoodR) }
    for x in (px + 9)...(px + 16) { g.world.set(x, 94, .stone) }
    g.pb.x = Double(px) + 0.5
    g.keyR = true
    var t = 0.0
    while t < 4.0 && g.pb.x < Double(px + 12) { step(g, 0.1); t += 0.1 }
    g.keyR = false
    step(g, 0.3)
    check(abs(g.pb.y - 94.0) < 0.05 && g.pb.x > Double(px + 9), "the player walks up six stairs onto the landing (x \(f1(g.pb.x - Double(px))), y \(f2(g.pb.y)))")
    check(t < 3.0, "at a walk, without jumping (\(f1(t)) s)")
    g.keyL = true
    t = 0
    while t < 4.0 && g.pb.x > Double(px) + 0.8 { step(g, 0.1); t += 0.1 }
    g.keyL = false
    step(g, 0.5)
    check(abs(g.pb.y - 100.0) < 0.05, "and back down to the ground (y \(f2(g.pb.y)))")
    // standing on a stair: half way up its tile
    g.pb.x = Double(px + 3) + 0.1
    g.pb.y = 98.0
    g.pb.vy = 0
    step(g, 0.5)
    check(abs(g.pb.y - 99.5) < 0.05, "standing on the low side of a stair the feet are half a block up (y \(f2(g.pb.y)))")
    // a zombie climbs them too
    let h = arena()
    let hx = Int(h.pb.x)
    for k in 0..<6 { build(h, hx + 3 + k, 99 - k, .stairStoneR) }
    for x in (hx + 9)...(hx + 16) { h.world.set(x, 94, .stone) }
    h.pb.x = Double(hx + 8) + 0.75; h.pb.y = 94
    h.monstersEnabled = true
    h.settings.peaceful = false
    h.godMode = true
    h.timeOfDay = 0.75
    let z: Mob = h.addMob(.zombie, Double(hx) + 0.5, 100)
    z.persistent = true
    h.mobGrid.rebuild(h.mobs)
    step(h, 8.0)
    check(z.b.y < 95.0, "a zombie chasing the player climbs the stairs as well (y \(f1(z.b.y)))")
    // placing faces the way the player does
    let p = arena()
    let qx = Int(p.pb.x)
    hold(p, .block(.stairBrickR), 4)
    use(p, qx + 2, 99)
    use(p, qx - 2, 99)
    check(p.world.tile(qx + 2, 99) == .stairBrickR && p.world.tile(qx - 2, 99) == .stairBrickL, "a stair placed to the right rises to the right, one placed to the left rises to the left")
    p.breakTile(qx - 2, 99, true)
    var r: Int = 0
    for d in p.drops where d.stack.item == .block(.stairBrickR) { r += d.stack.count }
    check(r == 1, "and either kind drops the same stair item")
}

// ---------------------------------------------------------------- lifts
print("== lifts")
do {
    let g = arena()
    let px = Int(g.pb.x)
    let sx: Int = px + 10
    for y in 80...99 { g.world.set(sx, y, .liftRail) }
    // the ground floor's button, and an upper floor ten rows up with its own
    g.world.set(sx + 2, 99, .liftButton)
    for x in (sx + 2)...(sx + 6) { g.world.set(x, 90, .stone) }
    g.world.set(sx + 2, 89, .liftButton)
    g.pb.x = Double(sx + 3) + 0.5
    hold(g, .block(.liftCar), 1)
    use(g, sx, 99)
    check(g.lifts.count == 1 && abs(g.lifts[0].y - 100) < 0.01 && g.inv.total(.block(.liftCar)) == 0, "a lift car placed on the rail sits on the ground floor")
    let l: Lift = g.lifts[0]
    check(g.liftStops(l) == [90.0, 100.0], "its floors are the two rows with buttons (\(g.liftStops(l)))")
    // ride up
    g.pb.x = Double(sx) + 0.5
    g.pb.y = 100
    step(g, 0.3)
    g.rideLiftTap(l, 97.0)
    step(g, 5.0)
    check(abs(l.y - 90) < 0.02 && l.target == nil, "tapping the car's upper half takes it up to the next floor (y \(f2(l.y)))")
    check(abs(g.pb.y - 90) < 0.1 && g.pb.onGround, "carrying the player standing in it (y \(f2(g.pb.y)))")
    // step off, call it down from the ground floor, then back up with the upper button
    g.pb.x = Double(sx + 4) + 0.5
    step(g, 0.5)
    g.callLift(sx + 2, 99)
    step(g, 5.0)
    check(abs(l.y - 100) < 0.02 && abs(g.pb.y - 90) < 0.05, "the ground floor's button calls the empty car down (car y \(f2(l.y)))")
    g.callLift(sx + 2, 89)
    step(g, 5.0)
    check(abs(l.y - 90) < 0.02, "and the upper floor's button calls it back up")
    // a block in the shaft stops it
    g.world.set(sx - 1, 95, .stone)
    g.callLift(sx + 2, 99)
    step(g, 5.0)
    check(l.y < 95.5 && l.y > 89.9 && l.target == nil, "a block left in the shaft stops it (y \(f2(l.y)))")
    g.world.set(sx - 1, 95, .air)
    // speed, saving
    hold(g, .gadget(.wrench), 1)
    _ = g.wrenchLift(Double(sx + 2) + 0.5, 99.5)
    check(l.speed == 2, "a wrench on a button sets the car's speed (\(Lift.speedNames[l.speed]))")
    let s: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    let g2 = Game.load(s, settings: Settings())
    check(g2.lifts.count == 1 && abs(g2.lifts[0].y - l.y) < 0.01 && g2.lifts[0].speed == 2, "the car, where it is and its speed are kept when the world is saved and loaded")
    // packed up with the wrench; a car whose rail is taken away falls apart into its item
    g.drops.removeAll()
    _ = g.wrenchLift(Double(sx) + 0.5, l.y - 1.0)
    check(g.lifts.isEmpty && g.drops.contains { $0.stack.item == .block(.liftCar) }, "a wrench on the car packs it up")
    g2.world.set(g2.lifts[0].x, Int(floor(g2.lifts[0].y - 0.001)), .air)
    step(g2, 0.2)
    check(g2.lifts.isEmpty && g2.drops.contains { $0.stack.item == .block(.liftCar) }, "a car whose rail is broken comes off as its item")
}

// ---------------------------------------------------------------- weight and blasts
print("== weight and blasts")
do {
    check(tileWeight(.planks) < tileWeight(.brick) && tileWeight(.brick) < tileWeight(.stone) && tileWeight(.stone) < tileWeight(.gold), "planks are lighter than brick, brick than stone, stone than gold")
    check(weightLine(.brick).contains("holds 120") && weightLine(.planks).contains("reaches 4"), "a block's info tells its weight, what it holds and how far it reaches (\(weightLine(.brick)))")
    // a bomb on the stone floor: close blocks destroyed, a ring knocked loose, the rest untouched
    let g = arena()
    let px = Int(g.pb.x) + 15
    g.godMode = true
    let before: Int = (90..<108).reduce(0) { (a: Int, y: Int) -> Int in a + (px - 8...px + 8).filter { g.world.tile($0, y) == .stone }.count }
    g.explode(Double(px) + 0.5, 100.2, radius: 3.4, power: 26, source: .environment, breakBlocks: true)
    let flying: Int = g.fallingBlocks.count
    let after: Int = (90..<108).reduce(0) { (a: Int, y: Int) -> Int in a + (px - 8...px + 8).filter { g.world.tile($0, y) == .stone }.count }
    check(g.world.tile(px, 100) == .air && g.world.tile(px, 101) == .air, "the stone where the bomb went off is gone")
    check(flying >= 4, "a ring of blocks around it is knocked loose and thrown (\(flying) flying)")
    check(g.world.tile(px + 6, 101) == .stone && g.world.tile(px, 105) == .stone, "blocks further off are untouched")
    var t = 0.0
    var maxUp: Double = 0
    var startY: [Int: Double] = [:]
    for fb in g.fallingBlocks { startY[fb.uid] = fb.y }
    while t < 14 && !g.fallingBlocks.isEmpty {
        for fb in g.fallingBlocks { maxUp = max(maxUp, (startY[fb.uid] ?? fb.y) - fb.y) }
        step(g, 1.0 / 60.0)
        t += 1.0 / 60.0
    }
    let settled: Int = (90..<108).reduce(0) { (a: Int, y: Int) -> Int in a + (px - 8...px + 8).filter { g.world.tile($0, y) == .stone }.count }
    check(g.fallingBlocks.isEmpty && t < 12 && maxUp > 0.4, "the loosened stone, heavy, hops up (\(f2(maxUp)) blocks) and all of it comes down and settles within \(f1(t)) s")
    check(settled - after >= flying / 2, "most settle back into blocks (\(settled - after) of \(flying); \(before - settled) stone gone in all)")
    var stuck: Int = 0
    for y in 80..<100 { for x in (px - 12)...(px + 12) where g.world.tile(x, y) == .stone && g.world.tile(x, y + 1) == .air { stuck += 1 } }
    check(stuck == 0, "none is left hanging in the air")
    // light blocks are thrown from further off than heavy ones
    func throwFrom(_ t: Tile, _ dx: Int) -> (Int, Double) {
        let h = arena()
        let hx = Int(h.pb.x) + 15
        h.godMode = true
        for y in 96...99 { build(h, hx + dx, y, t) }
        h.explode(Double(hx) + 0.5, 98.5, radius: 3.4, power: 26, source: .environment, breakBlocks: true)
        var n: Int = 0
        for fb in h.fallingBlocks where fb.tile == t && abs(fb.x - (Double(hx + dx) + 0.5)) < 0.1 { n += 1 }
        var far: Double = 0
        var tt = 0.0
        while tt < 14 && !h.fallingBlocks.isEmpty {
            for fb in h.fallingBlocks where fb.tile == t { far = max(far, abs(fb.x - (Double(hx + dx) + 0.5))) }
            step(h, 0.05)
            tt += 0.05
        }
        return (n, far)
    }
    let pl: (Int, Double) = throwFrom(.planks, 4)
    let st: (Int, Double) = throwFrom(.stone, 4)
    check(pl.0 >= 2 && pl.1 >= 2.0, "a blast four blocks off throws a plank wall (\(pl.0) planks, up to \(f1(pl.1)) blocks)")
    check(st.0 == 0, "but leaves a stone wall at the same distance standing (\(st.0) thrown)")
    // falling sand is drawn now as it falls (it is in the list of falling blocks) and lands
    let s = arena()
    let sx = Int(s.pb.x) + 5
    for y in 90...95 { s.world.set(sx, y, .sand) }
    s.checkFalling(sx, 95)
    check(s.fallingBlocks.count == 6 && s.world.tile(sx, 95) == .air, "sand with nothing under it falls as six falling blocks")
    step(s, 2.0)
    var sand: Int = 0
    for y in 90..<100 where s.world.tile(sx, y) == .sand { sand += 1 }
    check(s.fallingBlocks.isEmpty && sand == 6 && s.world.tile(sx, 99) == .sand, "and lands as a pile of six on the floor")
}

// ---------------------------------------------------------------- storms
print("== storms carry light blocks")
do {
    func shed(_ t: Tile) -> (Int, Int, Bool) {
        let g = arena()
        g.settings.weatherOn = true
        g.settings.weatherHurtsBlocks = true
        g.godMode = true
        let px = Int(g.pb.x) + 6
        for x in px...(px + 8) { build(g, x, 92, t) }
        for y in 93...99 { build(g, px, y, t); build(g, px + 8, y, t) }
        var e = TornadoEvent(x: Double(px) + 4.5, dir: 1, speed: 0.01, warnDur: 0, groundDur: 120, strength: 1.0, wander: 0, uid: 77)
        e.phase = 1
        e.t = 5
        g.weather.tornado = e
        var seen: Set<Int> = []
        var clock = 0.0
        while clock < 20 {
            g.weather.tornado?.x = Double(px) + 4.5
            step(g, 0.1)
            for fb in g.fallingBlocks where fb.flung && fb.tile == t { seen.insert(fb.uid) }
            clock += 0.1
        }
        g.weather.tornado = nil
        var tt = 0.0
        while tt < 20 && !g.fallingBlocks.isEmpty { step(g, 0.1); tt += 0.1 }
        return (seen.count, g.fallingBlocks.count, true)
    }
    let light: (Int, Int, Bool) = shed(.planks)
    let heavy: (Int, Int, Bool) = shed(.brick)
    check(light.0 >= 3, "a tornado over a plank shed tears planks loose and carries them (\(light.0) blocks)")
    check(heavy.0 < light.0, "a brick shed loses far fewer (\(heavy.0))")
    check(light.1 == 0 && heavy.1 == 0, "once it has passed, everything it carried has come down and settled")
}

// ---------------------------------------------------------------- structural physics
print("== structural physics")
func structWorld() -> Game {
    let g = arena()
    g.settings.structural = true
    g.godMode = true
    step(g, 0.1)
    return g
}
do {
    // off: nothing falls
    let o = arena()
    let ox = Int(o.pb.x) + 5
    for y in 95...99 { build(o, ox, y, .planks) }
    for x in (ox + 1)...(ox + 10) { build(o, x, 95, .planks) }
    step(o, 2.0)
    check(o.world.tile(ox + 10, 95) == .planks, "with structural physics off (the default), a long beam just hangs there")
    check(!Settings().structural, "it is off unless switched on")
    // a plank beam reaches four blocks out from its post
    let g = structWorld()
    let px = Int(g.pb.x) + 5
    for y in 95...99 { build(g, px, y, .planks) }
    for x in (px + 1)...(px + 10) { build(g, x, 95, .planks) }
    step(g, 4.0)
    var kept: Int = 0
    for x in (px + 1)...(px + 10) where g.world.tile(x, 95) == .planks { kept += 1 }
    check(kept == 4, "on, a plank beam holds four blocks out from its post, the rest fall (\(kept) kept)")
    check(g.world.tile(px, 99) == .planks, "the post stands")
    var t = 0.0
    while t < 8 && !g.fallingBlocks.isEmpty { step(g, 0.1); t += 0.1 }
    var landed: Int = 0
    for x in (px + 5)...(px + 12) where g.world.tile(x, 99) == .planks { landed += 1 }
    check(g.fallingBlocks.isEmpty && landed >= 4, "the fallen planks land on the floor (\(landed))")
    // too much weight on glass
    let h = structWorld()
    let hx = Int(h.pb.x) + 5
    build(h, hx, 99, .glass)
    for y in 95...98 { build(h, hx, y, .brick) }
    step(h, 3.0)
    check(h.world.tile(hx, 99) != .glass, "four bricks (8) on a glass block (holds 6) break it")
    var t2 = 0.0
    while t2 < 8 && !h.fallingBlocks.isEmpty { step(h, 0.1); t2 += 0.1 }
    var bricks: Int = 0
    for y in 90...99 where h.world.tile(hx, y) == .brick { bricks += 1 }
    check(bricks == 4, "and the bricks come down onto the floor (\(bricks))")
    // tall towers: 50 bricks stand, 70 are too heavy for the bottom one
    let a = structWorld()
    let ax = Int(a.pb.x) + 5
    for y in 50...99 { build(a, ax, y, .brick) }
    step(a, 2.0)
    check(a.world.tile(ax, 99) == .brick && a.world.tile(ax, 50) == .brick, "a 50-brick tower stands (the bottom carries 98 of 120)")
    let b = structWorld()
    let bx = Int(b.pb.x) + 5
    for y in 30...99 { build(b, bx, y, .brick) }
    step(b, 3.0)
    var standing: Int = 0
    for y in 30...99 where b.world.tile(bx, y) == .brick { standing += 1 }
    check(standing < 70, "a 70-brick tower is too heavy for its bottom brick and comes down (\(standing) still in place after 3 s)")
    // taking out a post brings down what it held
    let c = structWorld()
    let cx = Int(c.pb.x) + 5
    for y in 95...99 { build(c, cx, y, .planks); build(c, cx + 8, y, .planks) }
    for x in (cx + 1)...(cx + 7) { build(c, x, 95, .planks) }
    step(c, 2.0)
    check(c.world.tile(cx + 4, 95) == .planks, "a plank bridge between two posts stands")
    for y in 96...99 { c.breakTile(cx + 8, y, true) }
    step(c, 4.0)
    var bridge: Int = 0
    for x in (cx + 1)...(cx + 8) where c.world.tile(x, 95) == .planks { bridge += 1 }
    check(bridge == 4, "take one post away and only the four planks within reach of the other stay (\(bridge))")
    // the land never falls, and neither does what the world made
    let d = structWorld()
    let dx = Int(d.pb.x) + 5
    d.world.set(dx, 103, .air)
    d.world.set(dx, 104, .air)
    d.world.set(dx + 2, 95, .planks)
    for x in (dx + 3)...(dx + 12) { d.world.set(x, 95, .planks) }
    step(d, 3.0)
    check(d.world.tile(dx, 102) == .stone && d.world.tile(dx + 12, 95) == .planks, "the land never falls, and nor do blocks the world itself made")
    // saved: what was built stays built
    let s: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    let g2 = Game.load(s, settings: Settings())
    check(g2.world.isBuilt(px, 99) && !g2.world.isBuilt(px, 100), "which blocks were built is kept in the save")
    // a big structure is looked at quickly
    let e = structWorld()
    let ex = Int(e.pb.x) - 35
    for x in ex..<(ex + 50) { for y in 40...99 { build(e, x, y, .brick) } }
    let t0 = Date()
    let res: StructCheck = e.checkStructure(ex + 10, 99)
    let ms: Double = Date().timeIntervalSince(t0) * 1000
    check(res.count == 3000 && res.fails.isEmpty, "a wall of 3000 bricks is checked whole and stands (\(res.count) blocks, \(f1(ms)) ms)")
}

print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL BUILDING AND PHYSICS TESTS PASSED" : "SOME BUILDING AND PHYSICS TESTS FAILED")
exit(fails == 0 ? 0 : 1)
