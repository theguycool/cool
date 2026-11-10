import SwiftUI
import Foundation
// Step 5c: more of the game in mods. A mod's rules of the game (day length, gravity, health, hunger,
// healing, damage both ways, mining, monsters, animals, falls, walking, jumping, night light, drops on
// death) and the items a new world starts with; the Overworld's weather (chances, strength, length,
// rain colour) and more weather for custom dimensions; mod blocks with their own weight, that fall like
// sand, seats and beds, and blocks on Sparkworks power lines; whole vehicles kept in a mod and built
// from their kit item; a theme for the game's screens. The editors are SwiftUI and are compile-checked
// only; what they call is tested here.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { return abs(a - b) <= eps }

let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmod5c-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

/// A mod holding only rules
func rulesMod(_ id: String, _ rules: [String: Double]) -> ModPack {
    var p = ModPack(); p.id = id; p.name = id.capitalized
    p.rules = rules
    return p
}
/// A flat stone floor at row 100 with the mods on, nothing spawning
func arena(_ mods: [ModPack], mode: GameMode = .survival) -> Game {
    ModRuntime.activate(mods, world: nil)
    let g = Game(mode: mode, infinite: true, seed: 7373, settings: Settings())
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
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0; g.pb.onGround = true
    g.timeOfDay = 0.25
    g.settings.weatherOn = false
    return g
}
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func roundTrip(_ p: ModPack) -> ModPack? {
    guard let d = try? JSONEncoder().encode(p) else { return nil }
    return try? JSONDecoder().decode(ModPack.self, from: d)
}

// ---------------------------------------------------------------- rules
print("== the rules of the game")
do {
    check(GameRule.specs.count == GameRule.allCases.count, "every rule has its name, range and help (\(GameRule.specs.count))")
    var ordered: Bool = true
    for r in GameRule.allCases where r.spec.id != String(describing: r) { ordered = false }
    check(ordered, "the rules' text is in the order of the rules")
    for r in GameRule.allCases where !(r.spec.def >= r.spec.lo && r.spec.def <= r.spec.hi) { check(false, "\(r): the game's value is inside its range") }
    var p = rulesMod("odd", ["gravity": 99, "day": -4, "nonsense": 3, "deathDrop": 0.4, "hunger": .nan])
    let rep: ModReport = ModValidator.check(&p, known: [:])
    check(p.rules["gravity"] == 3 && p.rules["day"] == 2 && p.rules["nonsense"] == nil, "rules are held to their ranges and unknown ones left out")
    check(p.rules["hunger"] == 1 && rep.issues.contains { $0.text.contains("nonsense") }, "a rule that is not a number becomes the game's, and an unknown one is reported")
    ModRuntime.activate([rulesMod("a", ["gravity": 0.5, "day": 30]), rulesMod("b", ["gravity": 2])], world: nil)
    check(near(ModRuntime.shared.rule(.gravity), 2) && near(ModRuntime.shared.rule(.day), 30), "the mod lower in the load order wins a rule both set; others keep theirs")
    check(near(gravityG, 68) && near(ModRuntime.shared.rule(.hunger), 1), "gravity follows the rule; a rule nobody sets stays the game's")
    ModRuntime.activate([], world: nil)
    check(near(gravityG, 34) && near(ModRuntime.shared.rule(.day), 12), "without mods every rule is the game's own")
}

print("== the rules at play")
do {
    let plainDay: Double = arena([]).dayLength
    let fast: Game = arena([rulesMod("days", ["day": 3])])
    check(near(plainDay, 720) && near(fast.dayLength, 180), "a day lasts as the rule says (12 minutes -> 3)")
    let t0: Double = fast.timeOfDay
    fast.freezeTime = false
    for _ in 0..<60 { fast.updateTime(1.0) }
    check(fast.timeOfDay - t0 > 0.3 || fast.timeOfDay < t0, "a minute of play turns a short day a third round")

    // gravity: a fall from the same height takes longer under low gravity
    func fallTime(_ g: Game) -> Int {
        g.pb.y = 80; g.pb.vy = 0; g.pb.onGround = false
        var n: Int = 0
        while !g.pb.onGround && n < 600 { frame(g); n += 1 }
        return n
    }
    let low: Game = arena([rulesMod("moon", ["gravity": 0.4])])
    let tLow: Int = fallTime(low)
    let tNormal: Int = fallTime(arena([]))
    check(tLow > tNormal, "under low gravity a fall takes longer (\(tNormal) -> \(tLow) frames)")

    let tough: Game = arena([rulesMod("hp", ["health": 60])])
    check(tough.maxHP == 60 && tough.hp == 60, "a new world starts with the rule's full health")
    let save = tough.makeSave()
    ModRuntime.activate([rulesMod("hp", ["health": 60])], world: save.mods)
    let back: Game = Game.load(save, settings: Settings())
    check(back.maxHP == 60, "a world loaded with the mod keeps the rule's health")
    ModRuntime.activate([], world: nil)
    let back2: Game = Game.load(save, settings: Settings())
    check(back2.maxHP == 20 && back2.hp <= 20, "without the mod it is the game's 20 again")

    // the rules belong to the mods that are on, so each world is tried right after it is made
    func hungerAfter(_ mods: [ModPack]) -> Double {
        let g: Game = arena(mods)
        g.hunger = 20
        for _ in 0..<600 { g.updateSurvival(0.1, 0) }
        return g.hunger
    }
    let fedH: Double = hungerAfter([rulesMod("fed", ["hunger": 0])])
    let normalH: Double = hungerAfter([])
    check(fedH == 20 && normalH < 20, "with hunger at 0 the player never gets hungry")

    func healedTo(_ mods: [ModPack]) -> Double {
        let g: Game = arena(mods)
        g.hp = 10; g.hunger = 20
        for _ in 0..<50 { g.updateSurvival(0.1, 0) }
        return g.hp
    }
    let noHeal: Double = healedTo([rulesMod("nh", ["healing": 0])])
    let quickHeal: Double = healedTo([rulesMod("qh", ["healing": 3])])
    let baseHeal: Double = healedTo([])
    check(noHeal == 10 && quickHeal > baseHeal && baseHeal > 10, "healing 0 never heals; faster healing heals faster (\(Int(baseHeal)) -> \(Int(quickHeal)))")

    let god: Game = arena([rulesMod("safe", ["hurt": 0])])
    god.damagePlayer(8, from: god.pb.x, knock: 0, ignoreArmor: true)
    let glass: Game = arena([rulesMod("glass", ["hurt": 2])])
    glass.damagePlayer(4, from: glass.pb.x, knock: 0, ignoreArmor: true)
    check(god.hp == god.maxHP && glass.hp == glass.maxHP - 8, "damage taken follows the rule (0: none, 2: twice)")

    let strong: Game = arena([rulesMod("str", ["hit": 3])])
    let z1: Mob = strong.addMob(.zombie, strong.pb.x + 3, 100)
    z1.maxHP = 500; z1.hp = 500
    strong.hurtMob(z1, 10, 1, 0, true)
    let z2: Mob = strong.addMob(.zombie, strong.pb.x + 5, 100)
    z2.maxHP = 500; z2.hp = 500
    strong.hurtMob(z2, 10, 1, 0, false)
    check(near(500 - z1.hp, 30, 1) && near(500 - z2.hp, 10, 1), "the player's blows hit as the rule says; others' do not change")

    func mined(_ g: Game) -> Double {
        let tx: Int = Int(g.pb.x) + 1
        g.mineP = 0
        g.mineStep(tx, 100, nil, nil, 0.1)
        return g.mineP
    }
    let quick: Game = arena([rulesMod("dig", ["mining": 4])])
    check(near(mined(quick), mined(arena([])) * 4, 0.001), "mining goes as fast as the rule says")

    let calm: Game = arena([rulesMod("calm", ["monsters": 0, "animals": 2])])
    check(calm.monsterCap(.surface) == 0 && calm.monsterCap(.cave) == 0 && calm.animalCap == 18, "monsters 0: none may come; animals x2: twice as many")

    func landing(_ g: Game) -> Double {
        g.hp = g.maxHP
        g.pb.y = 40; g.pb.vy = 0; g.pb.onGround = false; g.fallPeak = 0
        var n: Int = 0
        while !g.pb.onGround && n < 900 { frame(g); n += 1 }
        return g.maxHP - g.hp
    }
    let softHurt: Double = landing(arena([rulesMod("soft", ["falls": 0])]))
    let hardHurt: Double = landing(arena([]))
    check(softHurt == 0 && hardHurt > 0, "falls 0: a long fall does no harm (\(Int(hardHurt)) without the rule)")

    func runSpeed(_ g: Game) -> Double {
        g.keyR = true
        frames(g, 60)
        g.keyR = false
        return abs(g.pb.vx)
    }
    let sprinter: Game = arena([rulesMod("run", ["walk": 2])])
    let vRun: Double = runSpeed(sprinter)
    let vWalk: Double = runSpeed(arena([]))
    check(near(vRun, vWalk * 2, 0.2), "walking speed follows the rule (\(String(format: "%.1f", vWalk)) -> \(String(format: "%.1f", vRun)))")

    func jumpSpeed(_ g: Game) -> Double {
        frames(g, 5)
        g.jumpHeld = true
        frame(g)
        g.jumpHeld = false
        return -g.pb.vy
    }
    let hopper: Game = arena([rulesMod("hop", ["jump": 2])])
    let j2: Double = jumpSpeed(hopper)
    let j1: Double = jumpSpeed(arena([]))
    check(j1 > 5 && near(j2 / j1, sqrt(2), 0.05), "a jump twice as high starts sqrt(2) times as fast")

    func nightLight(_ mods: [ModPack], _ sun: Double) -> Double {
        let g: Game = arena(mods)
        g.timeOfDay = 0.75
        g.updateTime(0)
        return g.skyLight(sun, 1)
    }
    let darkL: Double = nightLight([rulesMod("dark", ["nights": 0])], 0)
    let brightL: Double = nightLight([rulesMod("bright", ["nights": 2.5])], 0)
    let brightMax: Double = nightLight([rulesMod("bright", ["nights": 2.5])], 1)
    let usualL: Double = nightLight([], 0)
    check(darkL < 0.5 && brightL > usualL && brightMax <= 15, "night light follows the rule (\(String(format: "%.1f", darkL)), \(String(format: "%.1f", usualL)), \(String(format: "%.1f", brightL)))")

    let loser: Game = arena([rulesMod("drop", ["deathDrop": 1])])
    _ = loser.inv.add(.mat(.ironBar), 7)
    _ = loser.inv.add(.block(.planks), 20)
    let before: Int = loser.drops.count
    loser.die()
    check(loser.inv.slots.allSatisfy { $0 == nil } && loser.drops.count >= before + 2, "drop items on death: the bag falls where the player died")
    let keeper: Game = arena([])
    _ = keeper.inv.add(.mat(.ironBar), 7)
    keeper.die()
    check(keeper.inv.total(.mat(.ironBar)) == 7, "without the rule the player keeps the bag (the game's way)")
}

print("== start items")
do {
    var p = ModPack(); p.id = "kit"; p.name = "Kit"
    var gem = ModItem(); gem.id = "gem"; gem.name = "Gem"; gem.kind = .material
    p.items = [gem]
    p.startItems = [ModCost(.mat(.ironBar), 5), ModCost(.custom("kit:gem"), 3), ModCost(.custom("other:none"), 2), ModCost(.block(.planks), 5000)]
    _ = ModValidator.check(&p, known: [:])
    check(p.startItems.count == 3 && p.startItems[2].n == 999, "start items must exist and are held to 999")
    let g: Game = arena([p])
    check(g.inv.total(.mat(.ironBar)) == 5 && g.inv.total(.custom("kit:gem")) == 3, "a new survival world starts with them")
    let c: Game = arena([p], mode: .creative)
    check(c.inv.total(.mat(.ironBar)) == 0, "a creative world does not")
    let keyed: ModPack = ModStore.rekey(p, from: "kit", to: "kit2")
    check(keyed.startItems.contains { $0.item == .custom("kit2:gem") }, "renaming the mod renames its start items")
}

// ---------------------------------------------------------------- weather
print("== weather")
do {
    var w = ModWeather()
    for k in WeatherKind.allCases { w.chance[k.rawValue] = 0 }
    w.chance[WeatherKind.snowfall.rawValue] = 1
    w.chance[WeatherKind.overcast.rawValue] = 1
    w.rain = 2
    w.length = 2
    w.rainColor = 0x40FF60
    var p = ModPack(); p.id = "winter"; p.name = "Winter"
    p.weather = w
    let g: Game = arena([p])
    g.settings.weatherOn = true
    g.weather.plan.removeAll()
    g.fillPlan()
    var kinds: Set<WeatherKind> = []
    for _ in 0..<12 {
        g.advanceWeather()
        kinds.insert(g.weather.kind)
    }
    check(!kinds.isEmpty && kinds.isSubset(of: [.snowfall, .overcast]), "only the kinds the mod allows come (\(kinds.map { $0.name }.sorted()))")
    let modRain: Double = g.allowedProfile(.lightRain).precip
    var total: Double = 0
    for s in g.weather.plan { total += s.dur / Double(g.weather.plan.count) }
    check(total > 150, "spells last longer as the mod has it (about \(Int(total)) s)")
    check(ModRuntime.shared.weather?.rainColor == 0x40FF60, "the rain's colour is the mod's")
    let plain: Game = arena([])
    plain.settings.weatherOn = true
    check(modRain > plain.allowedProfile(.lightRain).precip * 1.5, "rain falls harder as the mod has it")
    var bad = ModPack(); bad.id = "bad"; bad.name = "Bad"
    var bw = ModWeather(); bw.chance = [99, -3]; bw.rain = 50; bw.length = 0
    bad.weather = bw
    _ = ModValidator.check(&bad, known: [:])
    check(bad.weather?.chance.count == WeatherKind.allCases.count && bad.weather?.chance[0] == 10 && bad.weather?.chance[1] == 0 && bad.weather?.rain == 3 && bad.weather?.length == 0.25, "the weather's numbers are held to their ranges")
    check(ModDimText.weathers.count == 9, "custom dimensions have nine kinds of weather to choose from")
}

// ---------------------------------------------------------------- blocks
func blockMod() -> ModPack {
    var p = ModPack(); p.id = "bk"; p.name = "Blocks"
    func block(_ id: String, _ f: (inout ModBlock) -> Void) -> ModBlock {
        var b = ModBlock(); b.id = id; b.name = id.capitalized
        var px = ModPixels(w: 8, h: 8)
        for y in 0..<8 { for x in 0..<8 { px.setARGB(x, y, 0xFF8A6A4A) } }
        b.art = px
        f(&b)
        return b
    }
    p.blocks = [
        block("lead") { $0.weight = 9; $0.carry = 300; $0.hardness = 1 },
        block("gravel") { $0.falls = true; $0.hardness = 0.5 },
        block("stool") { $0.function = .seat; $0.collision = .none },
        block("cot") { $0.function = .bed; $0.collision = .none },
        block("dynamo") { $0.powerRole = .generator; $0.powerAmt = 6 },
        block("panel") { $0.powerRole = .solar; $0.powerAmt = 5 },
        block("cell") { $0.powerRole = .battery; $0.powerAmt = 4 },
        block("glowlamp") { $0.powerRole = .lamp; $0.function = .lamp; $0.powerAmt = 2; $0.collision = .none },
        block("wingblock") { $0.vehRole = .wing; $0.vehPower = 1.5 }
    ]
    return p
}

print("== blocks: weight, falling, seats and beds")
do {
    var p = blockMod()
    p.blocks[0].weight = 500
    p.blocks[4].powerAmt = 9999
    _ = ModValidator.check(&p, known: [:])
    check(p.blocks[0].weight == 12 && p.blocks[4].powerAmt == 40, "a block's weight and power are held to their ranges")
    let g: Game = arena([blockMod()])
    let rt: ModRuntime = ModRuntime.shared
    guard let lead = rt.tileForKey["bk:lead"], let gravel = rt.tileForKey["bk:gravel"], let stool = rt.tileForKey["bk:stool"], let cot = rt.tileForKey["bk:cot"] else {
        check(false, "the blocks are in the world")
        exit(1)
    }
    check(near(blockPhys(lead).weight, 9) && near(blockPhys(lead).carry, 300), "a block's own weight and what it holds up are used")
    check(near(blockPhys(gravel).weight, blockPhysFrom(gravel.def).weight), "a block without its own weight is worked out from its hardness")
    let x: Int = Int(g.pb.x) + 4
    g.world.set(x, 99, .stone)
    g.world.set(x, 98, gravel)
    g.breakTile(x, 99, true)
    check(g.world.tile(x, 98) != gravel && g.fallingBlocks.contains { $0.tile == gravel }, "a falling block drops when what holds it up breaks")
    frames(g, 120)
    check(g.world.tile(x, 99) == gravel, "it lands and settles as itself")
    g.inv.slots[0] = Stack(item: .block(gravel), count: 5)
    g.sel = 0
    g.finishPlace(gravel, x + 2, 95)
    check(g.world.tile(x + 2, 95) != gravel && g.fallingBlocks.contains { $0.tile == gravel }, "one put up in the air falls at once")
    check(isSeat(stool) && !isSeat(cot), "a seat block is a seat")
    g.world.set(x - 3, 99, stool)
    g.interact(Double(x - 3) + 0.5, 99.5)
    check(g.seat?.x == x - 3, "tapping it sits the player down")
    g.seat = nil
    g.world.set(x - 6, 99, cot)
    g.timeOfDay = 0.8
    g.interact(Double(x - 6) + 0.5, 99.5)
    check(near(g.spawnX, Double(x - 6) + 0.5) && g.timeOfDay < 0.1, "a bed block: sleep until morning, and wake there")
}

print("== blocks on power lines")
do {
    let g: Game = arena([blockMod()])
    let rt: ModRuntime = ModRuntime.shared
    guard let dyn = rt.tileForKey["bk:dynamo"], let panel = rt.tileForKey["bk:panel"], let cell = rt.tileForKey["bk:cell"], let lamp = rt.tileForKey["bk:glowlamp"], let lit = rt.tileForKey["bk:glowlamp#alt"] else {
        check(false, "the power blocks are in the world")
        exit(1)
    }
    check(dyn.isPower && cell.isPower && lamp.isPower && lit.isPower, "power blocks are devices")
    check(powerRole(dyn) == .generator && powerRole(panel) == .generator && powerRole(cell) == .storage && powerRole(lamp) == .machine, "each plays its part on the lines")
    check(PowerSpec.capacity(cell) == 600 && PowerSpec.rate(cell) == 10 && PowerSpec.draw(lamp) == 2 && powerFamily(lit) == lamp, "a battery's store, a lamp's draw, and the lit lamp is the same device")
    let y: Int = 99
    let x0: Int = Int(g.pb.x) - 6
    g.world.set(x0, y, dyn)
    g.world.set(x0 + 4, y, lamp)
    for x in x0...(x0 + 4) { _ = g.world.setWire(x, y, g.world.wireAt(x, y) | Wire.power) }
    func run(_ n: Int) {
        for _ in 0..<n {
            g.clock += 0.1
            g.updatePower(0.1)
        }
    }
    run(40)
    check(g.world.tile(x0 + 4, y) == lit, "a generator lights a powered lamp on the same line")
    if let d = g.power.devs.first(where: { $0.x == x0 }) { check(near(g.generatorRate(d, 0.25), 6), "the generator makes its strength in sparks") }
    g.world.set(x0, y, .air)
    run(40)
    check(g.world.tile(x0 + 4, y) == lamp, "without power the lamp goes dark")
    g.world.set(x0 + 8, 90, panel)
    run(5)
    if let d = g.power.devs.first(where: { $0.x == x0 + 8 }) {
        g.timeOfDay = 0.25
        let day: Double = g.generatorRate(d, 0.25)
        g.timeOfDay = 0.75
        let night: Double = g.generatorRate(d, 0.25)
        check(day > 3 && night < 0.5, "a solar generator works by day only (\(String(format: "%.1f", day)) by day)")
    } else { check(false, "the solar block is a device") }
}

// ---------------------------------------------------------------- vehicles
func vehicleMod() -> ModPack {
    var p = blockMod()
    var v = ModVehicle(); v.id = "glider"; v.name = "Glider"
    v.cells = [ModVehicleCell(0, 0, .cockpit), ModVehicleCell(1, 1, .frame), ModVehicleCell(0, 1, .frame), ModVehicleCell(2, 1, .frame, "bk:wingblock"),
               ModVehicleCell(3, 1, .frame, "tile:" + String(Tile.planks.rawValue)), ModVehicleCell(4, 1, .engine), ModVehicleCell(5, 1, .airProp),
               ModVehicleCell(1, 2, .wheel), ModVehicleCell(4, 2, .wheel), ModVehicleCell(3, 1, .seat)]
    p.vehicles = [v]
    var r = ModRecipe(); r.id = "mkglider"; r.out = .custom("bk:glider"); r.cost = [ModCost(.block(.planks), 10)]; r.station = 0
    p.recipes = [r]
    return p
}

print("== vehicles in mods")
do {
    var p = vehicleMod()
    p.vehicles[0].cells.append(ModVehicleCell(40, -3, .frame))
    p.vehicles[0].cells.append(ModVehicleCell(1, 0, .frame, "bk:nothing"))
    _ = ModValidator.check(&p, known: [:])
    let cells: [ModVehicleCell] = p.vehicles[0].cells
    check(cells.count == 11 && cells.contains { $0.x == 23 && $0.y == 0 }, "cells are kept on a 24 x 24 grid and a cell used twice is kept once")
    check(cells.contains { $0.x == 1 && $0.y == 0 && $0.block.isEmpty && $0.partType == .frame }, "a block that does not exist becomes a frame")
    let cat: ModCatalog = ModCatalog.build([p])
    check(cat.keys["bk:glider"] == "item", "a vehicle is an item other mods can use in recipes")
    let g: Game = arena([vehicleMod()])
    let rt: ModRuntime = ModRuntime.shared
    check(rt.vehicles["bk:glider"] != nil && rt.items["bk:glider"] != nil, "its kit is an item in play")
    check(RecipeBook.all.contains { $0.out == .custom("bk:glider") }, "the mod's recipe makes the kit")
    if let it = rt.items["bk:glider"] { check(!it.def.icon.isBlank, "the kit's icon is drawn from its cells") }
    g.inv.slots[0] = Stack(item: .custom("bk:glider"), count: 1)
    g.sel = 0
    g.aimX = g.pb.x + 5; g.aimY = 99; g.aimValid = true
    let n0: Int = g.vehicles.count
    g.useModItem("bk:glider", 1.0 / 60.0, true)
    check(g.vehicles.count == n0 + 1 && g.inv.slots[0] == nil, "using the kit builds the vehicle and uses the kit up")
    if let v = g.vehicles.last {
        check(v.parts.count == 9 && v.parts[PartCell(dx: 2, dy: 1)] == .wing && v.blocks[PartCell(dx: 2, dy: 1)] == rt.tileForKey["bk:wingblock"], "a mod block that works as a wing is a wing with the block's look")
        check(v.parts[PartCell(dx: 3, dy: 1)] == .block && v.blocks[PartCell(dx: 3, dy: 1)] == .planks, "a game block is a plain block")
        check(v.fuel > 0, "it comes with fuel")
        let back: ModVehicle = g.vehicleDesign(v)
        check(back.cells.count == 9 && back.cells.contains { $0.block == "bk:wingblock" } && back.cells.contains { $0.block == "tile:" + String(Tile.planks.rawValue) }, "a vehicle in the world can be kept as a design again")
    } else { check(false, "the vehicle is there") }
    let keyed: ModPack = ModStore.rekey(vehicleMod(), from: "bk", to: "bk2")
    check(keyed.vehicles[0].cells.contains { $0.block == "bk2:wingblock" }, "renaming the mod renames the blocks its vehicles use")
    var other = ModPack(); other.id = "fleet"; other.name = "Fleet"
    var ov = ModVehicle(); ov.id = "raft"; ov.cells = [ModVehicleCell(0, 0, .hull, "bk:lead")]
    other.vehicles = [ov]
    check(ModStore.dependencies(other).contains("bk"), "a vehicle made of another mod's blocks needs that mod")
}


// ---------------------------------------------------------------- the look of the screens
print("== themes")
do {
    var t = ModTheme()
    t.colors[ThemeRole.buttons.rawValue] = 0x2050A0
    t.colors[ThemeRole.titles.rawValue] = 0xFF4080
    t.colors[ThemeRole.tint.rawValue] = 0x00FF00
    t.tintAmt = 0.5
    t.font = 2
    t.corner = 99
    t.hudScale = 9
    t.title = String(repeating: "X", count: 80)
    var p = ModPack(); p.id = "look"; p.name = "Look"
    p.theme = t
    _ = ModValidator.check(&p, known: [:])
    check(p.theme?.corner == 16 && p.theme?.hudScale == 1.5 && p.theme?.title.count == 32, "a theme's numbers and words are held to their ranges")
    ThemeRT.set(p.theme)
    check(ThemeRT.color(0x6B6B6B) != 0x6B6B6B && ThemeRT.color(0xFFE066) == 0xFF4080, "the game's button and title colours become the theme's")
    let other: UInt32 = ThemeRT.color(0x8A3A3A)
    check(other != 0x8A3A3A, "colours of roles the theme leaves alone lean to its tint")
    check(ThemeRT.design == .serif && ThemeRT.corner == 16, "the letters and corners follow the theme")
    let shadeA: UInt32 = ThemeRT.color(0x555555)
    let shadeB: UInt32 = ThemeRT.color(0x3A3A3A)
    check(rgbLight(shadeA) > rgbLight(shadeB), "darker shades of a role stay darker in the theme's colour")
    ThemeRT.set(nil)
    check(ThemeRT.color(0x6B6B6B) == 0x6B6B6B && ThemeRT.design == .monospaced, "without a theme every colour is the game's")
    // the enabled mods decide the theme (the last one in the list that has one)
    var a = ModPack(); a.id = "thema"; a.name = "Theme A"
    var ta = ModTheme(); ta.title = "AAA"
    a.theme = ta
    var b2 = ModPack(); b2.id = "themb"; b2.name = "Theme B"
    var tb = ModTheme(); tb.title = "BBB"
    b2.theme = tb
    _ = ModStore.save(a)
    _ = ModStore.save(b2)
    ModStore.setEnabled("thema", true)
    ModStore.setEnabled("themb", true)
    ThemeRT.refresh()
    let before: String = ThemeRT.current?.title ?? ""
    ModStore.setEnabled("themb", false)
    ThemeRT.refresh()
    let after: String = ThemeRT.current?.title ?? ""
    check(before == "BBB" && after == "AAA", "the theme of the last enabled mod is used (\(before) -> \(after) with B off)")
    ModStore.setEnabled("thema", false)
    ThemeRT.refresh()
    check(ThemeRT.current == nil, "with no themed mod on, the game's look")
}

// ---------------------------------------------------------------- saving it all
print("== saved in the mod")
do {
    var p = vehicleMod()
    p.rules = ["gravity": 0.7, "deathDrop": 1]
    p.startItems = [ModCost(.mat(.coal), 4)]
    var w = ModWeather(); w.rain = 1.5; w.rainColor = 0x123456
    p.weather = w
    var t = ModTheme(); t.colors[ThemeRole.buttons.rawValue] = 0x225588; t.font = 1; t.corner = 6; t.title = "STAR REALM"; t.hudScale = 1.2
    p.theme = t
    if let back = roundTrip(p) {
        check(back.rules == p.rules && back.startItems == p.startItems && back.weather == p.weather && back.vehicles == p.vehicles && back.theme == p.theme, "rules, start items, weather, vehicles and the theme come back from the mod's file")
        check(back.blocks[1].falls && back.blocks[4].powerRole == .generator && back.blocks[2].function == .seat, "blocks keep falling, power and furniture")
    } else { check(false, "the mod round-trips") }
    let oldJSON: String = "{\"id\":\"old\",\"name\":\"Old\",\"blocks\":[{\"id\":\"b1\",\"name\":\"B\"}]}"
    if let old = try? JSONDecoder().decode(ModPack.self, from: Data(oldJSON.utf8)) {
        check(old.rules.isEmpty && old.weather == nil && old.theme == nil && old.vehicles.isEmpty && old.blocks[0].powerRole == .none && !old.blocks[0].falls, "an older mod reads with none of it")
    } else { check(false, "an older mod still reads") }
}

print("== done: \(passes) passed, \(fails) failed")
if fails > 0 { exit(1) }
