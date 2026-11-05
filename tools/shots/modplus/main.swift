import SwiftUI
import Foundation
// Headless screenshots of the Mod Creator+ update through the game's own renderer: two custom
// dimensions (an open snowy world with floating islands, and a roofed lava cavern) and a boss in a
// phase with the helpers it called. The Mod Creator's screens are SwiftUI and are not drawn here.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/modplusshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmodshots-" + String(Int.random(in: 1000...999999)), isDirectory: true)
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
func painted(_ c: UInt32) -> ModPixels {
    var p = ModPixels(w: 8, h: 8)
    for y in 0..<8 { for x in 0..<8 { p.setARGB(x, y, 0xFF000000 | (((x + y) % 3 == 0) ? shadeRGB(c, 0.85) : c)) } }
    return p
}

func world(_ packs: [ModPack]) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5150, settings: Settings(), options: .standard)
    g.modInfo = ModRuntime.shared.worldInfo()
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
    g.tilePx = 24
    return g
}

// 1: an open dimension: snow by day, two regions, pines, floating islands, snowflakes in the air
do {
    var p = ModPack()
    p.id = "frost"; p.name = "Frost"
    var ice = ModBlock(); ice.id = "ice"; ice.name = "Blue Ice"; ice.art = painted(0x6AA8E8)
    var gate = ModBlock(); gate.id = "gate"; gate.name = "Gate"; gate.art = painted(0xB0E0FF)
    p.blocks = [ice, gate]
    var d = ModDimension()
    d.id = "lands"; d.name = "Frostlands"
    d.skyTop = 0x3A6AA8; d.skyBottom = 0xD8ECFF; d.cycle = false; d.fixedTime = 0.22; d.light = 0.95
    d.weather = 4; d.chill = 0.6; d.ambient = 2; d.sunColor = 0xFFF4D0
    d.surface = 150; d.hills = 14; d.mountains = 0.5; d.islands = 0.5; d.caves = 0.5
    d.stone = "frost:ice"
    var z1 = ModDimZone(); z1.name = "Snowfield"; z1.biome = Biome.tundra.rawValue; z1.ground = ModGround.key(.snow); z1.trees = 2; z1.leaves = ModGround.key(.pineLeaves); z1.plant = ""
    var z2 = ModDimZone(); z2.name = "Glacier"; z2.biome = Biome.mountain.rawValue; z2.ground = "frost:ice"; z2.filler = "frost:ice"; z2.trees = 0; z2.plant = ""
    d.zones = [z1, z2]
    d.zoneWidth = 50
    d.gateBlock = "frost:gate"
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    let g = world([p])
    g.settings.weatherOn = true
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    steps(g, 90)
    render(g, "01_frostlands")
}

// 2: a roofed cavern dimension: a lava sea, ash rock, embers drifting, glow crystals
do {
    var p = ModPack()
    p.id = "ember"; p.name = "Ember"
    var d = ModDimension()
    d.id = "deep"; d.name = "The Cinder Deep"
    d.ceiling = true; d.nightTop = 0x200810; d.nightBottom = 0x5A1A10
    d.ambient = 1; d.hot = true
    d.surface = 200; d.hills = 18; d.roughness = 1.6; d.caves = 0.3; d.islands = 0.6
    d.sea = 206; d.liquid = 1
    d.stone = ModGround.key(.ashStone)
    var z = ModDimZone(); z.name = "Ash flats"; z.biome = Biome.desert.rawValue; z.ground = ModGround.key(.obsidian); z.filler = ModGround.key(.ashStone)
    z.trees = 0; z.plant = ModGround.key(.glowCrystal); z.plantChance = 0.1
    d.zones = [z]
    d.hazard = ModGround.key(.spikes); d.hazardChance = 0.04
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    let g = world([p])
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    steps(g, 90)
    render(g, "02_cinder_deep")
}

// 3: a boss in its second phase (tinted red) with the two helpers it called
do {
    var p = ModPack()
    p.id = "boss"; p.name = "Boss"
    var imp = ModMob(); imp.id = "imp"; imp.name = "Imp"; imp.category = .hostile; imp.base = MobKind.imp.rawValue; imp.hp = 10; imp.spawn.enabled = false
    var b = ModMob()
    b.id = "king"; b.name = "Frost King"; b.category = .boss; b.base = MobKind.golem.rawValue; b.hp = 600; b.scale = 1.6
    b.hue = 190; b.tint = 0x80C0FF; b.tintAmt = 0.3
    b.spawn.enabled = false
    var rage = ModPhase(); rage.name = "Enraged"; rage.value = 0.6; rage.tint = 0xFF3020; rage.tintAmt = 0.45; rage.helper = "boss:imp"; rage.helpers = 2; rage.shield = 0
    b.phases = [rage]
    p.mobs = [imp, b]
    _ = ModValidator.check(&p, known: [:])
    let g = world([p])
    g.settings.weatherOn = false
    g.timeOfDay = 0.3
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 6)
    for x in (cx - 40)...(cx + 40) {
        for y in 60..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) - 6.5; g.pb.y = 100
    let slot: Int = ModRuntime.shared.mobSlot["boss:king"]!
    let k: Mob = g.addCustomMob(slot, Double(cx) + 3.5, 100)!
    k.persistent = true
    k.dir = -1
    k.hp = k.maxHP * 0.5
    g.stepPhases(k, ModRuntime.shared.mob(slot)!, 1.0 / 60.0)
    for m in g.mobs { m.persistent = true }
    steps(g, 6)
    render(g, "03_boss_phase")
}
