import SwiftUI
import Foundation
// The Mod Creator: the mod file format (reading damaged files safely), the mod store (save, order,
// enable, duplicate, delete, packages), the checks, and custom content working in the game: blocks,
// items, weapons, tools, armour, effects, creatures, recipes, loot, ores, structures, test worlds and
// world dependencies. The editor screens are compile-checked only (they are SwiftUI).

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}

// a scratch folder for the mod store
let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmods-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

func painted(_ w: Int, _ h: Int, _ c: UInt32) -> ModPixels {
    var p = ModPixels(w: w, h: h)
    for y in 0..<h { for x in 0..<w { p.setARGB(x, y, 0xFF000000 | c) } }
    return p
}

/// A mod with a bit of everything
func sampleMod() -> ModPack {
    var p = ModPack()
    p.id = "gemmod"
    p.name = "Gems and Beasts"
    p.author = "Tester"
    p.version = "1.2"
    var b = ModBlock()
    b.id = "ruby_ore"; b.name = "Ruby Ore"; b.category = .terrain
    b.art = painted(8, 8, 0xC02040); b.hardness = 3; b.tier = 4; b.tool = 0
    b.dropSelf = false; b.drop = .custom("gemmod:ruby"); b.dropCount = 2
    p.blocks.append(b)
    var lamp = ModBlock()
    lamp.id = "lamp"; lamp.name = "Ruby Lamp"; lamp.art = painted(8, 8, 0xFF8080); lamp.light = 13; lamp.function = .lamp
    p.blocks.append(lamp)
    var ruby = ModItem()
    ruby.id = "ruby"; ruby.name = "Ruby"; ruby.kind = .material; ruby.icon = painted(16, 16, 0xE02050)
    p.items.append(ruby)
    var sword = ModItem()
    sword.id = "ruby_sword"; sword.name = "Ruby Sword"; sword.kind = .melee; sword.damage = 12; sword.cooldown = 0.4; sword.reach = 3.2
    sword.baseIcon = .sword(.iron); sword.tint = 0xFF2040; sword.tintAmt = 0.5
    p.items.append(sword)
    var wand = ModItem()
    wand.id = "wand"; wand.name = "Spark Wand"; wand.kind = .magic; wand.damage = 7; wand.cooldown = 0.5; wand.projectile = "spark"; wand.speed = 28
    p.items.append(wand)
    var shot = ModProjectile()
    shot.id = "spark"; shot.name = "Spark"; shot.color = 0x60F0FF; shot.glow = 8
    p.projectiles.append(shot)
    var mob = ModMob()
    mob.id = "crystal_wolf"; mob.name = "Crystal Wolf"; mob.category = .hostile; mob.base = MobKind.wolf.rawValue
    mob.hp = 40; mob.damage = 7; mob.speed = 3.5; mob.hue = 160
    mob.behavior.chase = true; mob.behavior.attackPlayer = true
    mob.drops = [ModDrop(.custom("gemmod:ruby"), 1, 2, 1.0)]
    p.mobs.append(mob)
    var rec = ModRecipe()
    rec.id = "r_sword"; rec.out = .custom("gemmod:ruby_sword"); rec.count = 1
    rec.cost = [ModCost(.custom("gemmod:ruby"), 3), ModCost(.mat(.stick), 1)]; rec.station = Station.anvil.rawValue
    p.recipes.append(rec)
    var lt = ModLootTable()
    lt.id = "gems"; lt.name = "Gem Stash"; lt.rolls = 3
    lt.entries = [ModLootEntry(.custom("gemmod:ruby"), 1, 3, 0), ModLootEntry(.mat(.diamond), 1, 1, 2)]
    p.loot.append(lt)
    var ore = ModOre()
    ore.id = "ore_ruby"; ore.name = "Ruby veins"; ore.block = "ruby_ore"; ore.minY = 200; ore.maxY = 300; ore.veins = 3; ore.size = 8
    p.ores.append(ore)
    return p
}

// ---------------------------------------------------------------- stage 1: the format
print("== mod format")
do {
    let p: ModPack = sampleMod()
    let d: Data = try! JSONEncoder().encode(p)
    let q: ModPack = try! JSONDecoder().decode(ModPack.self, from: d)
    check(q == p, "a mod with blocks, items, weapons, shots, creatures, recipes, loot and ores survives a JSON round trip unchanged")
    check(q.blocks[0].art.argb(3, 3) == 0xFFC02040 && q.items[0].icon.valid, "pixel art is kept exactly (and stays valid)")
    check(p.summary.contains("2 blocks") && p.summary.contains("1 creature") && p.summary.contains("2 weapons"), "the mod list summary counts its content: " + p.summary)

    // missing fields fall back to defaults
    let thin: String = "{\"id\":\"x1\",\"name\":\"Thin\",\"blocks\":[{\"id\":\"b1\",\"name\":\"Plain\"}],\"items\":[{\"id\":\"i1\"}]}"
    let t: ModPack = try! JSONDecoder().decode(ModPack.self, from: Data(thin.utf8))
    check(t.blocks.count == 1 && t.blocks[0].hardness == 1.0 && t.blocks[0].collision == .solid && t.items[0].stack == 99,
          "a mod missing most fields still loads, with sensible defaults")
    check(t.version == "1.0" && t.author == "" && t.format == ModPack.currentFormat, "missing mod details get defaults")

    // one broken entry does not spoil the rest
    let broken: String = "{\"id\":\"x2\",\"name\":\"Broken\",\"blocks\":[{\"id\":\"b1\",\"name\":\"Good\"},{\"id\":\"b2\",\"name\":\"Bad\",\"collision\":\"banana\",\"art\":42},{\"id\":\"b3\"}],\"mobs\":[\"nonsense\",{\"id\":\"c1\"}]}"
    let bk: ModPack = try! JSONDecoder().decode(ModPack.self, from: Data(broken.utf8))
    check(bk.blocks.count == 3 && bk.blocks[1].collision == .solid, "a field with a wrong type falls back to its default (the entry stays)")
    check(bk.mobs.count == 1 && bk.skipped == 1, "an entry that is not an object at all is skipped and counted (1 skipped)")
    let garbage: Data = Data("not json at all {".utf8)
    check((try? JSONDecoder().decode(ModPack.self, from: garbage)) == nil, "a file that is not JSON at all is refused, not half-read")
}

// ---------------------------------------------------------------- stage 1: the store
print("== mod store")
do {
    var a: ModPack = sampleMod()
    check(ModStore.save(a), "saving a mod works")
    var b = ModPack()
    b.id = "second"; b.name = "Second Mod"
    check(ModStore.save(b), "saving a second mod works")
    let ents: [ModEntry] = ModStore.entries()
    check(ents.count == 2 && ents[0].id == "gemmod" && ents[1].id == "second", "the store lists mods in load order")
    check(ents[0].pack?.created ?? 0 > 0 && (ents[0].pack?.edited ?? 0) >= (ents[0].pack?.created ?? 0), "saving stamps the creation and edit dates")
    ModStore.setEnabled("second", true)
    ModStore.setEnabled("gemmod", true)
    check(ModStore.enabledPacks().map { $0.id } == ["gemmod", "second"], "enabled mods load in the store's order")
    ModStore.move("second", by: -1)
    check(ModStore.entries().map { $0.id } == ["second", "gemmod"] && ModStore.enabledPacks().first?.id == "second", "moving a mod up changes the load order")
    ModStore.setEnabled("second", false)
    check(ModStore.enabledPacks().map { $0.id } == ["gemmod"], "disabling a mod leaves it out of new worlds")
    // duplicate
    a = ModStore.pack("gemmod")!
    let dup: ModPack? = ModStore.duplicate(a)
    check(dup != nil && dup!.id != "gemmod" && dup!.name.contains("copy"), "duplicating makes a copy with its own id and name")
    if let dd = dup {
        let drop: Item? = dd.blocks[0].drop
        check(drop == .custom(dd.id + ":ruby"), "the copy's references point at its own content, not the original's")
        check(dd.recipes[0].out == .custom(dd.id + ":ruby_sword"), "recipes inside the copy are re-pointed too")
        ModStore.delete(dd.id)
        check(ModStore.pack(dd.id) == nil && !ModStore.entries().contains { $0.id == dd.id }, "deleting a mod removes its file and its place in the order")
    }
    // a damaged file shows up as damaged instead of crashing the list
    try? Data("{ broken".utf8).write(to: ModStore.url("damaged"))
    let withBad: [ModEntry] = ModStore.entries()
    let bad: ModEntry? = withBad.first { $0.id == "damaged" }
    check(bad != nil && bad!.pack == nil && !bad!.error.isEmpty, "a damaged mod file is listed with an error (and can be deleted)")
    ModStore.delete("damaged")
    // packages
    if let u = ModStore.exportPackage(a) {
        check(FileManager.default.fileExists(atPath: u.path) && u.pathExtension == "prmod", "exporting writes a package file")
        let data: Data = try! Data(contentsOf: u)
        let res: (ModPack?, String) = ModStore.importPackage(data)
        check(res.0 != nil && res.0!.id != "gemmod", "importing a mod that is already installed installs a copy under a new id")
        if let imp = res.0 {
            check(imp.blocks[0].drop == .custom(imp.id + ":ruby"), "an imported copy's references point at itself")
            ModStore.delete(imp.id)
        }
    } else {
        check(false, "exporting writes a package file")
    }
    let notPkg: (ModPack?, String) = ModStore.importPackage(Data("{\"hello\":1}".utf8))
    check(notPkg.0 == nil && !notPkg.1.isEmpty, "a file that is not a package is refused with a reason")
    ModStore.delete("second")
}

// ---------------------------------------------------------------- stage 1: checks
print("== mod checks")
do {
    var p: ModPack = sampleMod()
    p.blocks[0].hardness = -5
    p.blocks[0].light = 99
    p.items[1].damage = 9999
    p.items[1].stack = 500
    p.mobs[0].hp = -10
    p.mobs[0].scale = 50
    p.mobs[0].spawn.group = 40
    p.items.append(p.items[0])                       // a repeated id
    var badRec = ModRecipe()
    badRec.id = "r_bad"; badRec.out = .custom("gemmod:nothing"); badRec.cost = [ModCost(.mat(.coal), 1)]
    p.recipes.append(badRec)
    var loop = ModRecipe()
    loop.id = "r_loop"; loop.out = .mat(.coal); loop.count = 1; loop.cost = [ModCost(.mat(.coal), 1)]
    p.recipes.append(loop)
    var neg = ModRecipe()
    neg.id = "r_neg"; neg.out = .custom("gemmod:ruby"); neg.count = -4; neg.cost = [ModCost(.mat(.coal), -3)]
    p.recipes.append(neg)
    var empty = ModLootTable()
    empty.id = "empty"
    p.loot.append(empty)
    var lostOre = ModOre()
    lostOre.id = "ore_lost"; lostOre.block = "gone"
    p.ores.append(lostOre)
    var st = ModStructure()
    st.id = "hut"; st.w = 3; st.h = 3; st.cells = [1, 2]
    p.structures.append(st)
    let r: ModReport = ModValidator.check(&p, known: [:])
    check(p.blocks[0].hardness >= 0.05 && p.blocks[0].light == 15, "out-of-range block numbers are brought into range")
    check(p.items[1].damage <= 60 && p.items[1].stack == 1, "weapon damage is capped and weapons do not stack")
    check(p.mobs[0].hp >= 1 && p.mobs[0].scale <= 2.5 && p.mobs[0].spawn.group <= 4, "creature health, size and group size are held in range")
    check(Set(p.items.map { $0.id }).count == p.items.count, "a repeated content id is renumbered")
    check(r.disabled.contains("r_bad") && r.disabled.contains("r_loop"), "a recipe for something missing, and a recipe that makes nothing new, are switched off")
    let fixedNeg: ModRecipe = p.recipes.first { $0.id == "r_neg" }!
    check(fixedNeg.count >= 1 && fixedNeg.cost[0].n >= 1 && !r.disabled.contains("r_neg"), "negative quantities are corrected (the recipe still works)")
    check(r.disabled.contains("empty") && r.disabled.contains("ore_lost") && r.disabled.contains("hut"),
          "an empty loot table, an ore with no block and a structure with broken cells are switched off")
    check(r.errors >= 5 && !r.fatal, "the problems are reported (" + String(r.errors) + " errors, " + String(r.warnings) + " warnings) without refusing the whole mod")
    var future = ModPack()
    future.format = 99
    let fr: ModReport = ModValidator.check(&future, known: [:])
    check(fr.fatal, "a mod from a newer version of the game is refused as a whole")
}


// ---------------------------------------------------------------- stage 2: blocks, items, weapons
func arena(_ packs: [ModPack], mode: GameMode = .survival, seed: UInt64 = 4242) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: mode, infinite: true, seed: seed, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
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
    g.maxHP = 400; g.hp = 400
    g.light.valid = false
    g.timeOfDay = 0.25
    return g
}
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func hold(_ g: Game, _ item: Item, _ n: Int = 1, extra: Int = 0) {
    g.inv.slots[0] = Stack(item: item, count: n, extra: extra)
    g.setSel(0)
}
func aimAt(_ g: Game, _ x: Double, _ y: Double) { g.aimX = x; g.aimY = y; g.aimValid = true }

print("== custom blocks")
do {
    let p: ModPack = sampleMod()
    let g = arena([p])
    let rt = ModRuntime.shared
    guard let ore = rt.tile("gemmod:ruby_ore"), let lampOff = rt.tile("gemmod:lamp"), let lampOn = rt.tile("gemmod:lamp#alt") else {
        check(false, "custom blocks get tile numbers"); exit(1)
    }
    check(ore.isMod && lampOff.isMod && lampOn.isMod && ore != lampOff && lampOff != lampOn, "each custom block gets its own reserved tile number (a lamp gets two: off and lit)")
    check(ore.name == "Ruby Ore" && ore.solid && ore.opaque && abs(ore.hardness - 3) < 0.001 && Tile.tierTable[ore.idx] == 4 && toolClass(ore) == .pickaxe,
          "the tile tables take the block's name, collision, hardness, tier and tool")
    check(SectionPainter.shared.tilePx[ore.idx * 64 + 9] == 0xFFC02040 && Art.shared.tileBufs[ore.idx].px[9] == 0xFFC02040, "the block's own pixel art is what the world draws")
    let bx = Int(g.pb.x) + 2
    g.world.set(bx, 99, ore)
    check(g.world.tile(bx, 99) == ore, "a custom block can be placed in the world (stored like any tile)")
    // mining needs the tier
    hold(g, .tool(.pickaxe, .stone))
    aimAt(g, Double(bx) + 0.5, 99.5)
    g.useHeld = true
    for _ in 0..<30 { g.mineStep(bx, 99, .pickaxe, .stone, 1.0 / 60.0) }
    check(g.world.tile(bx, 99) == ore, "a stone pickaxe cannot break a tier-4 custom ore")
    for _ in 0..<600 { g.mineStep(bx, 99, .pickaxe, .gold, 1.0 / 60.0); if g.world.tile(bx, 99) != ore { break } }
    check(g.world.tile(bx, 99) == .air, "a gold pickaxe (tier 5) breaks it")
    let dropped = g.drops.filter { $0.stack.item == .custom("gemmod:ruby") }
    check(dropped.count == 1 && dropped[0].stack.count == 2, "it drops what the mod says: 2 rubies (a custom item)")
    // lamps switch and light the area
    g.world.set(bx + 1, 99, lampOff)
    g.light.valid = false; frames(g, 2)
    let before = g.light.level(bx + 1, 97).1
    g.interact(Double(bx + 1) + 0.5, 99.5)
    check(g.world.tile(bx + 1, 99) == lampOn, "tapping a custom light switch turns it on (its lit tile)")
    g.light.valid = false; frames(g, 2)
    let after = g.light.level(bx + 1, 97).1
    check(lampOn.light >= 12 && after > before, "the lit lamp gives off light the light map uses (" + String(before) + " -> " + String(after) + ")")
    g.interact(Double(bx + 1) + 0.5, 99.5)
    check(g.world.tile(bx + 1, 99) == lampOff, "tapping it again turns it off")
    g.breakTile(bx + 1, 99, true)
    check(g.drops.contains { $0.stack.item == .block(lampOff) }, "a lamp drops itself (the off form)")
    // explosions and blast proofing
    var pb = sampleMod()
    pb.blocks[0].blastProof = true
    let g2 = arena([pb])
    let ore2 = ModRuntime.shared.tile("gemmod:ruby_ore")!
    let ex = Int(g2.pb.x) + 6
    g2.world.set(ex, 99, ore2)
    g2.world.set(ex + 1, 99, .dirt)
    g2.explode(Double(ex) + 0.5, 99.5, radius: 3, power: 1, source: .environment, breakBlocks: true)
    check(g2.world.tile(ex, 99) == ore2 && g2.world.tile(ex + 1, 99) != .dirt, "a blast-proof custom block survives an explosion that breaks the dirt beside it")
}

print("== custom block functions")
do {
    var p = ModPack()
    p.id = "fun"; p.name = "Fun"
    func blk(_ id: String, _ f: ModBlockFunction, _ pw: Double = 6) -> ModBlock {
        var b = ModBlock(); b.id = id; b.name = id; b.art = painted(8, 8, 0x8080FF); b.function = f; b.power = pw; return b
    }
    p.blocks = [blk("box", .storage), blk("door", .door), blk("pad", .bounce, 14), blk("trap", .trap, 5), blk("shrine", .healer, 10), blk("sign", .sign)]
    p.blocks[5].text = "Hello there"
    let g = arena([p])
    let rt = ModRuntime.shared
    let box = rt.tile("fun:box")!, door = rt.tile("fun:door")!, doorOpen = rt.tile("fun:door#alt")!
    let pad = rt.tile("fun:pad")!, trap = rt.tile("fun:trap")!, shrine = rt.tile("fun:shrine")!, sign = rt.tile("fun:sign")!
    let x = Int(g.pb.x)
    // storage
    hold(g, .block(box), 1)
    g.world.set(x + 2, 99, .air)
    g.usePlaceBlock(box, 1.0 / 60.0)
    // place at the aim (set it directly if the aim is elsewhere)
    if g.world.tile(x + 2, 99) != box { g.world.set(x + 2, 99, box); g.world.setChestItems(x + 2, 99, []) }
    g.interact(Double(x + 2) + 0.5, 99.5)
    check(g.showInventory && g.openChest == IntPair(x: x + 2, y: 99) && g.world.chestItems(x + 2, 99).isEmpty, "a custom storage block opens as an empty chest")
    g.world.setChestItems(x + 2, 99, [Stack(item: .mat(.coal), count: 5)])
    g.showInventory = false; g.openChest = nil
    g.breakTile(x + 2, 99, true)
    check(g.drops.contains { $0.stack.item == .mat(.coal) && $0.stack.count == 5 } && g.drops.contains { $0.stack.item == .block(box) },
          "breaking it spills what it held, and drops the block")
    // door
    g.world.set(x + 3, 99, door)
    check(door.solid && !doorOpen.solid, "a custom door is solid shut and open to walk through")
    g.interact(Double(x + 3) + 0.5, 99.5)
    check(g.world.tile(x + 3, 99) == doorOpen, "tapping the door opens it")
    // jump pad
    g.world.set(x, 100, pad)
    g.pb.y = 100; g.pb.vy = 0; g.pb.onGround = true
    g.updateModPlay(1.0 / 60.0)
    check(g.pb.vy <= -13.9, "standing on a jump pad throws the player up with its strength")
    g.world.set(x, 100, .stone)
    // trap
    g.world.set(x, 99, trap)
    g.pb.x = Double(x) + 0.5; g.pb.y = 100; g.invuln = 0
    let hp0 = g.hp
    g.checkHazards(1.0 / 60.0)
    check(g.hp < hp0 && hp0 - g.hp <= 5.5, "a damage trap hurts the player who steps on it (by its damage, through the shared damage rules)")
    g.world.set(x, 99, .air)
    // healer
    g.hp = 100
    g.world.set(x + 1, 99, shrine)
    g.interact(Double(x + 1) + 0.5, 99.5)
    check(abs(g.hp - 110) < 0.01, "a healing shrine heals by its amount")
    g.interact(Double(x + 1) + 0.5, 99.5)
    check(abs(g.hp - 110) < 0.01, "and then rests before it heals again")
    // sign
    g.world.set(x - 1, 99, sign)
    g.interact(Double(x - 1) + 0.5, 99.5)
    check(g.message == "Hello there", "a sign shows its text")
}

print("== custom tools, weapons and armour")
do {
    var p: ModPack = sampleMod()
    var pick = ModItem(); pick.id = "ruby_pick"; pick.name = "Ruby Pickaxe"; pick.kind = .tool; pick.toolType = 0; pick.toolTier = 5; pick.toolSpeed = 12
    var helm = ModItem(); helm.id = "ruby_helm"; helm.name = "Ruby Helmet"; helm.kind = .armor; helm.slot = 0; helm.defense = 4; helm.look = 7
    helm.wornEffect = ModEffect(.speed, 25, 0)
    var potion = ModItem(); potion.id = "potion"; potion.name = "Haste Potion"; potion.kind = .consumable
    potion.effects = [ModEffect(.heal, 12, 0), ModEffect(.speed, 50, 10), ModEffect(.strength, 100, 10)]
    var gun = ModItem(); gun.id = "ruby_gun"; gun.name = "Ruby Pistol"; gun.kind = .gun; gun.damage = 8; gun.magazine = 3; gun.reload = 0.5
    gun.ammo = .ammo(.bullet); gun.speed = 40; gun.shot = ProjKind.bullet.rawValue
    var bomb = ModItem(); bomb.id = "boom"; bomb.name = "Boom Wand"; bomb.kind = .magic; bomb.damage = 20; bomb.projectile = "blast"; bomb.speed = 30
    var blast = ModProjectile(); blast.id = "blast"; blast.explode = 2.5
    p.items += [pick, helm, potion, gun, bomb]
    p.projectiles.append(blast)
    let g = arena([p])
    // tool
    let ore = ModRuntime.shared.tile("gemmod:ruby_ore")!
    let bx = Int(g.pb.x) + 2
    g.world.set(bx, 99, ore)
    hold(g, .custom("gemmod:ruby_pick"))
    aimAt(g, Double(bx) + 0.5, 99.5)
    g.useHeld = true
    var n = 0
    while g.world.tile(bx, 99) == ore && n < 600 { g.useModTool(ModRuntime.shared.item("gemmod:ruby_pick")!, 1.0 / 60.0, n == 0); n += 1 }
    check(g.world.tile(bx, 99) == .air && n < 60, "a custom tier-5 pickaxe with speed 12 breaks the ruby ore quickly (" + String(n) + " frames)")
    // melee
    let m = g.addMob(.zombie, g.pb.x + 1.6, 100)
    m.b.vx = 0
    g.mobGrid.rebuild(g.mobs)
    hold(g, .custom("gemmod:ruby_sword"))
    g.facing = 1
    aimAt(g, m.b.x, m.b.cy)
    let hp0 = m.hp
    g.swingEmpty(.custom("gemmod:ruby_sword"))
    check(hp0 - m.hp >= 11.9, "a custom sword hits a zombie for its damage (" + String(format: "%.1f", hp0 - m.hp) + ") through the game's melee system")
    // strength potion through the same damage path
    hold(g, .custom("gemmod:potion"), 3)
    g.hp = 300
    g.useModConsumable(ModRuntime.shared.item("gemmod:potion")!, true)
    check(abs(g.hp - 312) < 0.01 && g.effects.value(.speed) == 50 && g.effects.value(.strength) == 100 && g.inv.total(.custom("gemmod:potion")) == 2,
          "a potion heals, gives its effects and is used up")
    m.hp = 200; m.maxHP = 200
    g.useCD = 0
    hold(g, .custom("gemmod:ruby_sword"))
    aimAt(g, m.b.x, m.b.cy)
    let before = m.hp
    g.swingEmpty(.custom("gemmod:ruby_sword"))
    check(before - m.hp >= 23.9, "a strength boost doubles the sword's blow (" + String(format: "%.1f", before - m.hp) + ")")
    g.effects.clear()
    // gun: magazine and reload from the bag
    hold(g, .custom("gemmod:ruby_gun"), 1, extra: 3)
    g.inv.slots[1] = Stack(item: .ammo(.bullet), count: 10)
    aimAt(g, g.pb.x + 10, 99)
    var fired = 0
    for _ in 0..<3 { g.useCD = 0; let before = g.projectiles.count; g.useModGun(ModRuntime.shared.item("gemmod:ruby_gun")!, true); if g.projectiles.count > before { fired += 1 } }
    check(fired == 3 && g.inv.slots[0]?.extra == 0 && g.reloadT > 0, "a custom gun fires its magazine, then starts reloading by itself")
    for _ in 0..<60 { g.updateReload(1.0 / 60.0) }
    check(g.inv.slots[0]?.extra == 3 && g.inv.total(.ammo(.bullet)) == 7, "the reload fills the magazine from the bag's bullets")
    // wand with an exploding custom shot (the sword's zombie and the gun's bullets are cleared out of its way)
    g.mobs.removeAll()
    g.projectiles.removeAll()
    let target = g.addMob(.zombie, g.pb.x + 6, 100)
    target.b.vx = 0
    g.mobGrid.rebuild(g.mobs)
    hold(g, .custom("gemmod:boom"))
    aimAt(g, target.b.x, target.b.cy)
    g.useCD = 0
    g.useModShooter(ModRuntime.shared.item("gemmod:boom")!, true)
    let shots = g.projectiles.filter { $0.mod >= 0 }
    check(shots.count == 1, "a projectile weapon fires its custom shot")
    let thp = target.hp
    for _ in 0..<60 { g.updateProjectiles(1.0 / 60.0); g.mobGrid.rebuild(g.mobs) }
    check(target.hp < thp && g.projectiles.filter { $0.mod >= 0 }.isEmpty, "the custom shot flies, hits the zombie and bursts (" + String(format: "%.1f", thp - target.hp) + " damage)")
    // armour
    let def0 = g.inv.defense
    g.inv.slots[2] = Stack(item: .custom("gemmod:ruby_helm"), count: 1)
    g.quickEquip(2)
    check(g.inv.armor[0]?.item == .custom("gemmod:ruby_helm") && abs(g.inv.defense - def0 - 4) < 0.01, "custom armour goes into its own slot and adds its defense")
    check(g.armorPieces().0 == .mythril, "it is drawn as the armour tier it looks like")
    g.updateModPlay(1.0 / 60.0)
    check(g.effects.value(.speed) == 25, "its effect lasts while it is worn")
    g.inv.armor[0] = nil
    for _ in 0..<30 { g.updateModPlay(1.0 / 60.0) }
    check(g.effects.value(.speed) == 0, "and ends when it comes off")
    check(Item.custom("gemmod:ruby_sword").isWeapon && Item.custom("gemmod:ruby_sword").isMeleeWeapon && Item.custom("gemmod:wand").isRanged && Item.custom("gemmod:ruby").maxStack == 99,
          "custom items answer the inventory's questions (weapon, ranged, stack size) like the game's own")
    check(g.creativeItems().contains(.custom("gemmod:ruby_sword")) && g.creativeItems().contains(.block(ore)), "custom items and blocks are in the creative palette")
}

print("== saving custom content")
do {
    let p: ModPack = sampleMod()
    let g = arena([p])
    let ore = ModRuntime.shared.tile("gemmod:ruby_ore")!
    let x = Int(g.pb.x) + 3
    g.world.set(x, 99, ore)
    g.inv.slots[5] = Stack(item: .custom("gemmod:ruby_sword"), count: 1)
    g.inv.slots[6] = Stack(item: .block(ore), count: 7)
    g.slot = 3
    let save = g.makeSave()
    let data = try! JSONEncoder().encode(save)
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    check(back.mods?.mods.first?.id == "gemmod" && back.mods?.blocks["gemmod:ruby_ore"] == Int(ore.rawValue), "a save remembers the world's mods and each custom block's tile number")
    // another mod installed meanwhile takes slots first: the world's own numbers still win
    var other = ModPack(); other.id = "aaa"; other.name = "Other"
    var ob = ModBlock(); ob.id = "x"; ob.art = painted(8, 8, 0x00FF00)
    other.blocks = [ob, ob, ob]
    other.blocks[1].id = "y"; other.blocks[2].id = "z"
    ModRuntime.activate([other, p], world: back.mods)
    let g2 = Game.load(back, settings: Settings())
    let ore2 = ModRuntime.shared.tile("gemmod:ruby_ore")!
    check(ore2 == ore && g2.world.tile(x, 99) == ore2 && ore2.name == "Ruby Ore", "loaded with another mod added, the custom block keeps its number and is still in the world")
    check(g2.inv.slots[5]?.item == .custom("gemmod:ruby_sword") && g2.inv.slots[6]?.item == .block(ore2) && g2.inv.slots[6]?.count == 7, "custom items and blocks in the bag come back")
    // the mod missing: placeholders, nothing lost
    ModRuntime.activate([], world: back.mods)
    let g3 = Game.load(back, settings: Settings())
    check(g3.world.tile(x, 99) == ore && ore.name.contains("Missing") && ore.hardness >= 9999, "with the mod missing its block stays (an unbreakable placeholder)")
    check(Item.custom("gemmod:ruby_sword").name == "Missing item" && g3.inv.slots[5]?.item == .custom("gemmod:ruby_sword"), "its items wait in the bag, marked missing")
    let resave = g3.makeSave()
    check(resave.mods?.blocks["gemmod:ruby_ore"] == Int(ore.rawValue) && resave.mods?.mods.contains { $0.id == "gemmod" } == true,
          "saving without the mod keeps its record, so nothing is forgotten")
    ModRuntime.activate([p], world: resave.mods)
    let g4 = Game.load(resave, settings: Settings())
    check(g4.world.tile(x, 99).name == "Ruby Ore", "once the mod is back, the world is whole again")
    ModRuntime.deactivate()
    check(!ModRuntime.shared.active && Tile.mod00.name == "Unused Mod Block" && RecipeBook.all.count == RecipeBook.base.count, "leaving the world switches every mod off again")
}

// ---------------------------------------------------------------- stage 3: creatures
func attack(_ k: ModAttackKind, _ dmg: Double, range: Double = 1.6, cd: Double = 1.0, windup: Double = 0.3) -> ModAttack {
    var a = ModAttack(); a.kind = k; a.damage = dmg; a.range = range; a.cooldown = cd; a.windup = windup
    return a
}
func beast(_ id: String, _ cat: ModMobCategory, _ attacks: [ModAttack], base: MobKind = .zombie) -> ModMob {
    var m = ModMob(); m.id = id; m.name = id.capitalized; m.category = cat; m.base = base.rawValue
    m.hp = 60; m.damage = 0; m.speed = 2.5; m.attacks = attacks; m.spawn.enabled = false
    m.behavior = ModBehavior()
    if cat == .hostile || cat == .boss { m.behavior.chase = true; m.behavior.attackPlayer = true }
    return m
}
func beastMod() -> ModPack {
    var p = ModPack(); p.id = "beasts"; p.name = "Beasts"; p.author = "Tester"
    var brute = beast("brute", .hostile, [attack(.melee, 15, range: 1.4, windup: 0.4)])
    brute.scale = 1.5; brute.defense = 0.5; brute.knockResist = 1.0
    brute.drops = [ModDrop(.mat(.coal), 2, 2, 1.0)]
    var spit = beast("spitter", .hostile, [attack(.ranged, 8, range: 14, cd: 1.2)])
    spit.attacks[0].aim = .atTarget; spit.attacks[0].shot = ProjKind.bullet.rawValue; spit.attacks[0].speed = 24
    spit.behavior.runAway = true
    var glob = ModProjectile(); glob.id = "glob"; glob.name = "Glob"; glob.explode = 2.0; glob.breakBlocks = true
    p.projectiles = [glob]
    var bomber = beast("bomber", .hostile, [attack(.ranged, 10, range: 14, cd: 1.2)])
    bomber.attacks[0].projectile = "glob"
    let charger = beast("charger", .hostile, [attack(.charge, 12, range: 3, cd: 2.0, windup: 0.3)])
    var stomper = beast("stomper", .hostile, [attack(.stomp, 10, range: 4, cd: 2.0, windup: 0.3)])
    stomper.attacks[0].radius = 2
    let leaper = beast("leaper", .hostile, [attack(.jump, 12, range: 3, cd: 2.0, windup: 0.2)])
    var whirl = beast("whirler", .hostile, [attack(.area, 9, cd: 1.5, windup: 0.3)])
    whirl.attacks[0].radius = 2.5
    var flurry = beast("flurry", .hostile, [attack(.multiHit, 4, range: 1.5, cd: 2.0, windup: 0.1)])
    flurry.attacks[0].hits = 3
    var bunny = beast("bunny", .passive, [], base: .chicken)
    bunny.hp = 10; bunny.behavior.runAway = true; bunny.behavior.retaliate = false
    var grump = beast("grump", .neutral, [attack(.melee, 10, range: 1.5, windup: 0.2)])
    grump.behavior.retaliate = true; grump.behavior.chase = true
    var guardian = beast("guardian", .neutral, [attack(.melee, 20, range: 1.6, cd: 0.6, windup: 0.1)])
    guardian.behavior.attackMobs = true; guardian.behavior.retaliate = false; guardian.speed = 4
    var sentry = beast("sentry", .neutral, [attack(.melee, 10, range: 1.5, windup: 0.2)])
    sentry.behavior.defendArea = true; sentry.behavior.defendRadius = 6; sentry.behavior.wander = false; sentry.behavior.retaliate = false
    var shepherd = beast("shepherd", .neutral, [])
    shepherd.behavior.guardKey = "beasts:bunny"; shepherd.behavior.retaliate = false; shepherd.speed = 3.5
    var moth = beast("moth", .flying, [attack(.melee, 6, range: 1.2, windup: 0.1)], base: .bat)
    moth.behavior.fly = true; moth.behavior.chase = true; moth.behavior.attackPlayer = true; moth.speed = 4
    var eel = beast("eel", .water, [], base: .fish)
    eel.behavior.swim = true; eel.behavior.wander = true
    var king = beast("king", .boss, [attack(.melee, 18, range: 2.0, cd: 1.6), attack(.stomp, 14, range: 4, cd: 4, windup: 0.8)])
    king.hp = 900; king.scale = 2.2; king.loot = "hoard"; king.glow = 7
    var hoard = ModLootTable(); hoard.id = "hoard"; hoard.name = "Hoard"; hoard.rolls = 1
    hoard.entries = [ModLootEntry(.mat(.goldBar), 3, 3, 0)]
    p.loot = [hoard]
    var walker = beast("walker", .neutral, [])
    walker.behavior.patrol = true; walker.behavior.patrolRange = 4; walker.behavior.wander = false; walker.behavior.retaliate = false
    var hot = beast("salamander", .hostile, [attack(.melee, 5)])
    hot.fireproof = true
    var night = beast("nightling", .hostile, [attack(.melee, 5)])
    night.spawn.enabled = true; night.spawn.when = 2; night.spawn.place = .surface; night.spawn.weight = 10; night.spawn.maxNearby = 8
    var art = beast("doodle", .neutral, [])
    art.customArt = true
    art.frames = [painted(10, 12, 0x30C0F0), painted(10, 12, 0x30A0E0), painted(10, 12, 0x3080D0), painted(10, 12, 0xF04040)]
    var pal = beast("pal", .neutral, [])
    pal.behavior.followPlayer = true; pal.behavior.retaliate = false; pal.speed = 3
    var statue = beast("statue", .hostile, [attack(.melee, 5, range: 1.4, windup: 0.2)])
    statue.behavior.standStill = true; statue.behavior.chase = false
    var ghoul = beast("ghoul", .hostile, [attack(.melee, 5)])
    ghoul.behavior.burnsInSun = true
    var homebody = beast("homebody", .neutral, [])
    homebody.behavior.stayInBiome = true; homebody.behavior.retaliate = false
    p.mobs = [brute, spit, bomber, charger, stomper, leaper, whirl, flurry, bunny, grump, guardian, sentry, shepherd, moth, eel, king, walker, hot, night, art,
              pal, statue, ghoul, homebody]
    return p
}
/// a fresh round in the same arena: nobody about, the player healed and in the middle
func reset(_ g: Game, _ cx: Double) {
    g.mobs.removeAll(); g.projectiles.removeAll(); g.dangerZones.removeAll(); g.drops.removeAll()
    g.pb.x = cx; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.hp = 400; g.invuln = 0; g.dead = false
}
func spawn(_ g: Game, _ id: String, _ dx: Double, _ y: Double = 100) -> Mob {
    let m = g.addCustomMob(ModRuntime.shared.mobSlot["beasts:" + id]!, g.pb.x + dx, y)!
    m.homeX = m.b.x; m.homeY = m.b.y
    g.mobGrid.rebuild(g.mobs)
    return m
}
/// runs frames until `done` (or the limit); returns the frames taken
@discardableResult
func run(_ g: Game, _ limit: Int, _ done: () -> Bool) -> Int {
    var n = 0
    while n < limit && !done() { frame(g); n += 1 }
    return n
}

print("== custom creatures")
do {
    let p = beastMod()
    let g = arena([p])
    let rt = ModRuntime.shared
    let cx = g.pb.x
    check(rt.mobs.count == 24 && rt.spawnRules.count == 1, "every creature of the mod is ready, and the one that spawns has its rule")

    // a brute: size, health, side, a telegraphed blow
    reset(g, cx)
    let brute = spawn(g, "brute", 6)
    check(brute.kind == .custom && brute.def.name == "Brute" && abs(brute.b.h - mobDef(.zombie).h * 1.5) < 0.01 && abs(brute.maxHP - 60) < 0.01,
          "a custom creature appears with its name, its size and its health")
    check(g.faction(of: brute) == .hostile && brute.def.hostile, "a hostile creature is on the monsters' side")
    var warned = false
    var hp0 = g.hp
    var n = run(g, 600) { if !g.dangerZones.isEmpty { warned = true }; return g.hp < hp0 }
    check(g.hp < hp0 && warned, "it notices the player, walks up, shows where its blow will land, and the blow hurts (" + String(n) + " frames, " + String(format: "%.0f", hp0 - g.hp) + " damage)")
    let bhp = brute.hp
    var hitInfo = DamageInfo(amount: 20, type: .melee, source: .player); hitInfo.knock = 9; hitInfo.dirX = 1
    g.applyMobDamage(brute, hitInfo)
    check(abs((bhp - brute.hp) - 20 * g.dmgOutMult * 0.5) < 0.01, "its toughness shrugs off half of a sword blow (" + String(format: "%.1f", bhp - brute.hp) + ")")
    check(abs(brute.b.vx) < 0.01, "full knockback resistance: the blow does not push it")
    g.applyMobDamage(brute, DamageInfo(amount: 9999, type: .melee, source: .player))
    check(brute.hp <= 0 && g.drops.contains { $0.stack.item == .mat(.coal) && $0.stack.count == 2 }, "killed, it drops what its maker set")

    // a fireproof one
    reset(g, cx)
    let sal = spawn(g, "salamander", 10)
    let shp = sal.hp
    var lava = DamageInfo(amount: 30, type: .lava, source: .environment); lava.originX = sal.b.x
    check(!g.applyMobDamage(sal, lava) && sal.hp == shp && g.heatImmune(sal), "a fireproof creature takes nothing from lava or fire")

    // ranged: aims and hits; keeps its distance
    reset(g, cx)
    let spitter = spawn(g, "spitter", 9)
    hp0 = g.hp
    var fired = false
    n = run(g, 600) { if g.projectiles.contains(where: { $0.owner == spitter.id }) { fired = true }; return g.hp < hp0 }
    check(fired && g.hp < hp0, "a shooter fires at the player and its shot hurts (" + String(n) + " frames)")
    reset(g, cx)
    let kiter = spawn(g, "spitter", 3)
    frames(g, 150)
    check(abs(kiter.b.x - g.pb.x) > 4.5, "a shooter that runs away keeps its distance (" + String(format: "%.1f", abs(kiter.b.x - g.pb.x)) + " blocks away)")

    // a creature's exploding custom shot never breaks blocks
    reset(g, cx)
    let bomber = spawn(g, "bomber", 9)
    let wx = Int(cx) + 4
    g.world.set(wx, 99, .stone)
    var shotP = Projectile(kind: .spit, x: Double(wx) + 0.5, y: 99.5, vx: 0, vy: 0, dmg: 10, fromPlayer: false, gravity: 0)
    shotP.source = .mob(bomber, .hostile); shotP.mod = rt.shotIndex["beasts:glob"]!; shotP.owner = bomber.id
    g.modShotLanded(shotP, Double(wx) + 0.5, 99.5, mob: nil, player: false)
    check(g.world.tile(wx, 99) == .stone, "a creature's blast does not break blocks, even if its shot is set to")
    g.world.set(wx, 99, .air)

    // charge, stomp, leap, area, flurry
    reset(g, cx)
    let charger = spawn(g, "charger", 6)
    hp0 = g.hp
    var charged = false
    n = run(g, 600) { if charger.st == 5 { charged = true }; return g.hp < hp0 }
    check(charged && g.hp < hp0, "a charger rushes at the player and the rush hurts (" + String(n) + " frames)")
    reset(g, cx)
    let stomper = spawn(g, "stomper", 5)
    hp0 = g.hp
    var waves = false
    n = run(g, 600) { if g.projectiles.contains(where: { $0.kind == .shock && $0.owner == stomper.id }) { waves = true }; return g.hp < hp0 && waves }
    check(waves && g.hp < hp0, "a stomp sends shockwaves along the ground and hurts (" + String(n) + " frames)")
    reset(g, cx)
    let leaper = spawn(g, "leaper", 6)
    hp0 = g.hp
    var flew = false
    n = run(g, 600) { if leaper.st == 7 && !leaper.b.onGround { flew = true }; return g.hp < hp0 }
    check(flew && g.hp < hp0 && abs(leaper.b.x - g.pb.x) < 3.0, "a jump attack leaps at the player and lands on them (" + String(n) + " frames)")
    reset(g, cx)
    _ = spawn(g, "whirler", 2)
    hp0 = g.hp
    n = run(g, 600) { g.hp < hp0 }
    check(g.hp < hp0, "an area burst hurts everyone around it (" + String(n) + " frames)")
    reset(g, cx)
    let fl = spawn(g, "flurry", 1.2)
    let pig = g.addMob(.pig, g.pb.x + 0.6, 100)
    pig.hp = 200; pig.maxHP = 200
    var blows = 0
    var last = pig.hp
    run(g, 600) {
        pig.b.x = g.pb.x + 0.6; pig.b.vx = 0
        if pig.hp < last { blows += 1; last = pig.hp }
        return blows >= 3 || fl.hp <= 0
    }
    check(blows >= 3, "a multi-hit attack lands blow after blow (" + String(blows) + " on a pig in the way)")

    // passive and neutral
    reset(g, cx)
    let bunny = spawn(g, "bunny", 3)
    hp0 = g.hp
    frames(g, 90)
    check(abs(bunny.b.x - g.pb.x) > 5.0 && g.hp == hp0, "a timid animal runs from the player and never hurts anyone")
    reset(g, cx)
    let grump = spawn(g, "grump", 4)
    hp0 = g.hp
    frames(g, 180)
    let calm = g.hp == hp0 && grump.ai == .idle
    var poke = DamageInfo(amount: 2, type: .melee, source: .player); poke.originX = g.pb.x
    g.applyMobDamage(grump, poke)
    n = run(g, 600) { g.hp < hp0 }
    check(calm && g.hp < hp0, "a neutral creature leaves the player alone until it is hit, then fights back (" + String(n) + " frames)")

    // a guardian: fights monsters, never the player
    reset(g, cx)
    let guardian = spawn(g, "guardian", 22)
    let zombie = g.addMob(.zombie, g.pb.x + 27, 100)
    zombie.hp = 400; zombie.maxHP = 400
    let zhp = zombie.hp
    hp0 = g.hp
    n = run(g, 900) { zombie.hp < zhp }
    check(g.faction(of: guardian) == .ally && zombie.hp < zhp && g.hp == hp0, "a guardian hunts a monster near it (" + String(n) + " frames) and leaves the player alone")
    check(!g.applyMobDamage(guardian, DamageInfo(amount: 10, type: .melee, source: .player)), "the player's blows can't hurt a guardian by mistake")

    // defending an area
    reset(g, cx)
    let sentry = spawn(g, "sentry", 10)
    hp0 = g.hp
    frames(g, 120)
    let stayed = g.hp == hp0 && abs(sentry.b.x - sentry.homeX) < 2.5
    g.pb.x = sentry.b.x - 3
    n = run(g, 600) { g.hp < hp0 }
    check(stayed && g.hp < hp0, "a creature that defends an area ignores the player outside it and attacks inside it (" + String(n) + " frames)")
    g.pb.x = sentry.homeX - 25
    frames(g, 400)
    check(abs(sentry.b.x - sentry.homeX) < 4.0, "when the player leaves, it goes back to its post (" + String(format: "%.1f", abs(sentry.b.x - sentry.homeX)) + " blocks off)")

    // a guard stays beside the creature it guards
    reset(g, cx)
    let lamb = spawn(g, "bunny", -20)
    let shepherd = spawn(g, "shepherd", -12)
    frames(g, 240)
    let near1 = abs(shepherd.b.x - lamb.b.x) < 5.0
    lamb.b.x -= 12
    lamb.homeX = lamb.b.x
    frames(g, 300)
    check(near1 && abs(shepherd.b.x - lamb.b.x) < 5.0 && shepherd.ward === lamb, "a guard finds the creature it guards and follows it")

    // patrol
    reset(g, cx)
    let walker = spawn(g, "walker", -20)
    var lo = walker.b.x
    var hi = walker.b.x
    run(g, 900) { lo = min(lo, walker.b.x); hi = max(hi, walker.b.x); return false }
    check(hi - walker.homeX > 3.0 && walker.homeX - lo > 3.0 && hi - walker.homeX < 6.0 && walker.homeX - lo < 6.0,
          "a patrolling creature walks its beat back and forth (" + String(format: "%.1f to %.1f", lo - walker.homeX, hi - walker.homeX) + ")")

    // flying and swimming
    reset(g, cx)
    let moth = spawn(g, "moth", 9, 94)
    var lowest: Double = 0
    hp0 = g.hp
    n = run(g, 600) { lowest = max(lowest, moth.b.y); return g.hp < hp0 }
    check(moth.def.flying && lowest < 99.95 && g.hp < hp0, "a flying creature flies at the player without landing, and hurts (" + String(n) + " frames)")
    reset(g, cx)
    let px = Int(cx)
    for x in (px + 10)...(px + 22) { for y in 95...99 { g.world.set(x, y, .water) } }
    for y in 94...99 { g.world.set(px + 9, y, .stone); g.world.set(px + 23, y, .stone) }
    let eel = spawn(g, "eel", 16, 98.5)
    eel.b.inWater = true
    let ex0 = eel.b.x
    var dryFrames = 0
    var farthest = 0.0
    run(g, 600) {
        if g.world.tile(Int(floor(eel.b.x)), Int(floor(eel.b.y - eel.b.h * 0.5))) != .water { dryFrames += 1 }
        farthest = max(farthest, abs(eel.b.x - ex0))
        return false
    }
    check(dryFrames == 0 && farthest > 0.5 && eel.hp > 0, "a water creature swims about and stays in the water (" + String(dryFrames) + " frames dry, went " + String(format: "%.1f", farthest) + " blocks)")
    for x in (px + 9)...(px + 23) { for y in 95...99 { g.world.set(x, y, .air) } }

    // following, standing still, the sun, the biome
    reset(g, cx)
    let pal = spawn(g, "pal", 14)
    frames(g, 240)
    let close1 = abs(pal.b.x - g.pb.x) < 4.5
    g.pb.x -= 12
    frames(g, 300)
    check(close1 && abs(pal.b.x - g.pb.x) < 4.5 && g.hp == 400, "a creature that follows the player keeps close to them, without attacking")
    reset(g, cx)
    let statue = spawn(g, "statue", 5)
    frames(g, 240)
    let still = abs(statue.b.x - statue.homeX) < 0.3
    g.pb.x = statue.b.x - 1.0
    hp0 = g.hp
    n = run(g, 300) { g.hp < hp0 }
    check(still && g.hp < hp0 && abs(statue.b.x - statue.homeX) < 0.6, "a creature that stands still stays put, and strikes when the player comes within reach (" + String(n) + " frames)")
    reset(g, cx)
    g.settings.weatherOn = false
    let ghoul = spawn(g, "ghoul", -25)
    frames(g, 3)
    check(!g.inSunlight(ghoul) || ghoul.burn > 0, "a creature that burns in sunlight catches fire in the open by day" + (g.inSunlight(ghoul) ? "" : " (not in sunlight here)"))
    g.settings.weatherOn = true
    reset(g, cx)
    let homebody = spawn(g, "homebody", -20)
    homebody.homeBiome = 99
    homebody.homeX = homebody.b.x - 12
    let hx0 = homebody.b.x
    frames(g, 240)
    check(homebody.b.x < hx0 - 4.0, "a creature that keeps to its biome heads back when it finds itself outside it")

    // a boss
    reset(g, cx)
    let king = spawn(g, "king", 14)
    g.refreshBossBar()
    check(king.isBoss && g.activeBoss === king && g.bossBarName == "King", "a custom boss gets the boss health bar")
    check(g.faction(of: king) == .boss, "a boss is on its own side")
    g.applyMobDamage(king, DamageInfo(amount: 99999, type: .melee, source: .player))
    check(king.hp <= 0 && g.drops.contains { $0.stack.item == .mat(.goldBar) && $0.stack.count == 3 } && (g.message ?? "").contains("King"),
          "beaten, it rolls its loot table and the game says so")

    // art
    reset(g, cx)
    let doodle = spawn(g, "doodle", 5)
    let set1 = Art.shared.mobSet(doodle)
    let set2 = Art.shared.mobSet(spawn(g, "brute", 8))
    check(set1.right.count == 4 && set1.anim.attack == 3 && set2.right.count == Art.shared.creaturePreview(.zombie).right.count,
          "custom art gives four frames (with an attack frame); a recoloured body keeps its base's frames")

    // limits
    reset(g, cx)
    var made = 0
    for k in 0..<40 { if g.addCustomMob(rt.mobSlot["beasts:bunny"]!, g.pb.x - 30 + Double(k), 100) != nil { made += 1 } }
    check(made == ModLimits.maxActiveMobs, "no more than " + String(ModLimits.maxActiveMobs) + " custom creatures can be about at once")

    // spawning at night beside the game's own creatures
    reset(g, cx)
    g.monstersEnabled = true
    g.pauseSpawning = false
    g.timeOfDay = 0.75
    var got: Mob? = nil
    var tries = 0
    while got == nil && tries < 400 {
        g.spawnTimer = 0; g.monsterSpawnCD = 0
        g.updateSpawning(0.01)
        got = g.mobs.first { $0.kind == .custom }
        if g.mobs.count > 6 { g.mobs.removeAll() }
        tries += 1
    }
    check(got?.def.name == "Nightling" && got?.hunter == true, "at night the mod's creature spawns among the game's monsters and comes hunting (" + String(tries) + " tries)")
    g.timeOfDay = 0.25
    g.monstersEnabled = false
    g.pauseSpawning = true
    ModRuntime.deactivate()
}

// ---------------------------------------------------------------- stage 4: recipes, loot, ores
func smithMod() -> ModPack {
    var p = ModPack(); p.id = "smith"; p.name = "Smithing"; p.author = "Tester"
    var gem = ModItem(); gem.id = "gem"; gem.name = "Gem"; gem.kind = .material; gem.icon = painted(16, 16, 0x40E0A0)
    var ring = ModItem(); ring.id = "ring"; ring.name = "Gem Ring"; ring.kind = .material; ring.icon = painted(16, 16, 0xE0E040)
    var forge = ModBlock(); forge.id = "forge"; forge.name = "Gem Forge"; forge.art = painted(8, 8, 0x804020); forge.function = .station
    var ore = ModBlock(); ore.id = "gem_ore"; ore.name = "Gem Ore"; ore.art = painted(8, 8, 0x30A070); ore.hardness = 2; ore.tier = 2
    var ash = ModBlock(); ash.id = "ash_ore"; ash.name = "Ash Ore"; ash.art = painted(8, 8, 0x703030)
    p.items = [gem, ring]; p.blocks = [forge, ore, ash]
    var r1 = ModRecipe(); r1.id = "r_ring"; r1.out = .custom("smith:ring"); r1.count = 1
    r1.cost = [ModCost(.custom("smith:gem"), 2), ModCost(.mat(.goldBar), 1)]; r1.station = -1; r1.stationBlock = "forge"
    var r2 = ModRecipe(); r2.id = "r_forge"; r2.out = .custom("smith:forge"); r2.cost = [ModCost(.block(.stone), 10)]; r2.station = 0
    r2.cat = RecipeCat.basic.rawValue
    // loops: a plank back into a log would turn one log into four with the game's own recipe
    var r3 = ModRecipe(); r3.id = "r_unplank"; r3.out = .block(.log); r3.cost = [ModCost(.block(.planks), 1)]
    // four planks back into a log gains nothing: allowed
    var r4 = ModRecipe(); r4.id = "r_fair"; r4.out = .block(.log); r4.cost = [ModCost(.block(.planks), 4)]
    // two of the mod's own: 1 gem -> 2 rings, 1 ring -> 1 gem doubles gems
    var r5 = ModRecipe(); r5.id = "r_split"; r5.out = .custom("smith:ring"); r5.count = 2; r5.cost = [ModCost(.custom("smith:gem"), 1)]
    var r6 = ModRecipe(); r6.id = "r_join"; r6.out = .custom("smith:gem"); r6.cost = [ModCost(.custom("smith:ring"), 1)]
    p.recipes = [r1, r2, r3, r4, r5, r6]
    var t = ModLootTable(); t.id = "gems"; t.name = "Gems"; t.rolls = 1; t.nothing = 2
    t.entries = [ModLootEntry(.custom("smith:gem"), 1, 3, 0), ModLootEntry(.mat(.goldBar), 1, 1, 1), ModLootEntry(.mat(.diamond), 1, 1, 2), ModLootEntry(.custom("smith:ring"), 1, 1, 3)]
    t.chestChance = 1.0
    p.loot = [t]
    var o = ModOre(); o.id = "o_gem"; o.name = "Gem veins"; o.block = "gem_ore"; o.minY = 200; o.maxY = 320; o.veins = 3; o.size = 8; o.host = 0
    var u = ModOre(); u.id = "o_ash"; u.name = "Ash veins"; u.block = "ash_ore"; u.dim = 1; u.minY = 205; u.maxY = 300; u.veins = 4; u.size = 10; u.host = 0
    p.ores = [o, u]
    return p
}

print("== recipes, loot and ores")
do {
    var checked: ModPack = smithMod()
    let rep: ModReport = ModValidator.check(&checked, known: [:])
    check(rep.disabled.contains("r_unplank") && !rep.disabled.contains("r_fair"),
          "a recipe that loops with the game's own into more than it started with is switched off; a fair one is kept")
    check(rep.disabled.contains("r_split") != rep.disabled.contains("r_join"), "of two recipes that double each other's items, one is switched off")
    check(rep.issues.contains { $0.text.contains("from nothing") }, "the report says why")

    let g = arena([smithMod()])
    let rt = ModRuntime.shared
    let ring: Recipe? = RecipeBook.all.first { $0.out == .custom("smith:ring") && $0.outCount == 1 }
    let forgeT: Tile = rt.tile("smith:forge")!
    let forgeR: Recipe? = RecipeBook.all.first { $0.out == .block(forgeT) }
    check(ring != nil && forgeR != nil && ring?.cat == .mods && forgeR?.cat == .basic && RecipeBook.all.count == RecipeBook.base.count + rt.recipes.count,
          "the mod's recipes join the crafting book under the tabs chosen for them")
    check(!RecipeBook.all.contains { $0.out == .block(.log) && $0.cost.first?.n == 1 && $0.cost.first?.item == .block(.planks) }, "the looping recipe is not in the book")
    hold(g, .block(.stone), 12)
    g.craft(forgeR!)
    check(g.inv.total(.block(forgeT)) == 1 && g.inv.total(.block(.stone)) == 2, "a recipe by hand uses its ingredients and gives the custom block")
    g.inv.slots[1] = Stack(item: .custom("smith:gem"), count: 5)
    g.inv.slots[2] = Stack(item: .mat(.goldBar), count: 2)
    let away: Bool = !g.canCraft(ring!)
    let fx = Int(g.pb.x) + 2
    g.world.set(fx, 99, rt.tile("smith:forge")!)
    let near: Bool = g.canCraft(ring!)
    g.craft(ring!)
    check(away && near && g.inv.total(.custom("smith:ring")) == 1 && g.inv.total(.custom("smith:gem")) == 3 && g.inv.total(.mat(.goldBar)) == 1,
          "a recipe that needs the mod's own station works only beside it")
    check(!g.crafterRecipes().contains { $0.out == .custom("smith:ring") }, "an auto crafter can't make a recipe that needs a mod station")
    g.world.set(fx, 99, .air)

    // loot: the odds the editor shows are the odds you get
    guard let table = rt.loot["smith:gems"] else { check(false, "the loot table is ready"); exit(1) }
    var rng = RNG(12345)
    var counts: [Int] = [0, 0, 0, 0]
    var nothing = 0
    let rolls = 40000
    for _ in 0..<rolls {
        let got: [Stack] = rt.roll("smith:gems", &rng)
        if got.isEmpty { nothing += 1; continue }
        if let i = table.entries.firstIndex(where: { $0.item == got[0].item }) { counts[i] += 1 }
    }
    var worst: Double = 0
    for i in 0..<4 { worst = max(worst, abs(Double(counts[i]) / Double(rolls) - table.chance(i))) }
    let pNothing: Double = 2.0 / table.totalWeight
    check(worst < 0.01 && abs(Double(nothing) / Double(rolls) - pNothing) < 0.01,
          "common, uncommon, rare and very rare come up as often as the table says (worst gap " + String(format: "%.4f", worst) + ")")
    check(table.chance(0) > table.chance(1) && table.chance(1) > table.chance(2) && table.chance(2) > table.chance(3), "rarer entries are rarer")
    // chests: the table is added to a chest, the same every time
    let c1: [Stack] = g.world.chestItems(Int(g.pb.x) - 7, 90)
    let ids: Set<String> = Set(table.entries.map { $0.item.name })
    let has1: Bool = c1.contains { ids.contains($0.item.name) }
    let g2 = arena([smithMod()])
    let c2: [Stack] = g2.world.chestItems(Int(g.pb.x) - 7, 90)
    check(has1 && c1.map { $0.item.name + String($0.count) } == c2.map { $0.item.name + String($0.count) } && c1.count <= 27,
          "a loot table set to turn up in chests is in a chest, the same contents every time")

    // ores: in the chosen depths, only in rock, the same every time, both realms
    let gemT: Tile = rt.tile("smith:gem_ore")!
    let ashT: Tile = rt.tile("smith:ash_ore")!
    var total = 0
    var outside = 0
    var badHost = 0
    var same = true
    let base0 = Int(g.pb.x) / chunkW + 40
    for k in 0..<24 {
        let c: Chunk = generateChunk(g.gen, .overworld, base0 + k)
        let again: Chunk = generateChunk(g.gen, .overworld, base0 + k)
        if c.tiles != again.tiles { same = false }
        for lx in 0..<chunkW {
            for y in 0..<c.H where c.get(lx, y) == gemT {
                total += 1
                if y < 200 || y > 320 { outside += 1 }
            }
        }
    }
    // the same chunks without the mod: every ore tile was rock before
    ModRuntime.deactivate()
    let gPlain = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    ModRuntime.activate([smithMod()], world: g.modInfo)
    for k in 0..<24 {
        let plain: Chunk = generateChunk(gPlain.gen, .overworld, base0 + k)
        let modded: Chunk = generateChunk(g.gen, .overworld, base0 + k)
        for i in 0..<plain.tiles.count where plain.tiles[i] != modded.tiles[i] {
            let was: Tile = Tile.make(plain.tiles[i])
            if Tile.make(modded.tiles[i]) != gemT || !modOreHost(was, 0) { badHost += 1 }
        }
    }
    check(total > 24 * 8 && outside == 0, "custom ore veins appear in the chosen depths (" + String(total) + " blocks in 24 chunks)")
    check(badHost == 0, "veins only take the place of rock; nothing else in the chunk changes")
    check(same, "a chunk comes out the same every time it is made")
    var ash = 0
    for k in 0..<12 {
        let c: Chunk = generateChunk(g.gen, .umbral, base0 + k)
        for lx in 0..<chunkW { for y in 0..<c.H where c.get(lx, y) == ashT { ash += 1 } }
    }
    check(ash > 0, "an ore set for the Umbral Realm appears there (" + String(ash) + " blocks)")
    ModRuntime.deactivate()
    let plainAgain: Chunk = generateChunk(gPlain.gen, .overworld, base0)
    var stray = 0
    for i in 0..<plainAgain.tiles.count where Tile.make(plainAgain.tiles[i]).isMod { stray += 1 }
    check(stray == 0, "with no mods, generation is the game's own")
}

// ---------------------------------------------------------------- stage 5: structures
func hutMod(_ placement: ModPlacement = .surface) -> ModPack {
    var p = smithMod()
    let B: Int = Int(Tile.brick.rawValue)
    let C: Int = Int(Tile.chest.rawValue)
    var st = ModStructure(); st.id = "hut"; st.name = "Gem Hut"; st.w = 5; st.h = 4
    st.cells = [-1, B, B, B, -1,
                B, 0, 1000, 0, B,
                B, 0, C, 0, B,
                B, B, B, B, B]
    st.palette = ["smith:forge"]
    st.placement = placement; st.chance = 1.0; st.spacing = 64; st.loot = "gems"
    st.minY = 260; st.maxY = 300
    p.structures = [st]
    p.loot[0].chestChance = 0
    return p
}

print("== structures")
do {
    // capture what was built
    let g = arena([sampleMod()])
    let rt = ModRuntime.shared
    let px = Int(g.pb.x) + 6
    let lamp: Tile = rt.tile("gemmod:lamp")!
    for x in px...(px + 4) { g.world.set(x, 99, .planks); g.world.set(x, 95, .planks) }
    for y in 96...98 { g.world.set(px, y, .brick); g.world.set(px + 4, y, .brick) }
    g.world.set(px + 2, 98, .chest)
    g.world.set(px + 1, 96, lamp)
    g.world.set(px + 3, 96, .battery)
    g.world.set(px + 2, 96, .bedrock)
    g.startCapture()
    g.captureTap(Double(px) + 0.5, 95.5)
    check(g.capturing && !g.showCapture, "capture mode starts, and the first tap sets a corner")
    g.pointerDown(Double(px + 4) + 0.5, 99.5)
    g.pointerUp()
    check(g.showCapture && g.world.tile(px + 4, 99) == .planks, "the second tap opens the save panel (and breaks nothing)")
    let cap = g.captureStructure(clearAir: true)
    let st = cap.0
    check(st.w == 5 && st.h == 5 && st.cells.count == 25, "the captured structure has the selection's size (" + String(st.w) + " x " + String(st.h) + ")")
    check(st.cell(2, 3) == Int(Tile.chest.rawValue) && st.cell(0, 1) == Int(Tile.brick.rawValue) && st.cell(1, 1) == 1000 && st.palette == ["gemmod:lamp"],
          "it keeps the game's blocks by number and custom blocks by their key")
    check(cap.1 == 2 && st.cell(3, 1) == -1 && st.cell(2, 1) == -1, "a machine and bedrock are left out")
    check(st.cell(1, 2) == 0 && g.captureStructure(clearAir: false).0.cell(1, 2) == -1, "empty space clears the ground, or leaves it, as chosen")
    let msg = g.saveCapture(name: "Lamp Hut", modID: "", newModName: "My Huts", placement: .surface, clearAir: true)
    let saved: ModEntry? = ModStore.entries().first { $0.pack?.name == "My Huts" }
    check(saved?.pack?.structures.first?.name == "Lamp Hut" && saved?.enabled == true && !g.capturing && msg.contains("My Huts"),
          "saved into a new mod, which is switched on for new worlds")
    // into the same mod again: a second structure with its own id
    g.startCapture()
    g.captureTap(Double(px) + 0.5, 97.5)
    g.captureTap(Double(px + 4) + 0.5, 99.5)
    _ = g.saveCapture(name: "Floor", modID: saved!.id, newModName: "", placement: .underground, clearAir: false)
    let again: ModPack = ModStore.pack(saved!.id)!
    check(again.structures.count == 2 && again.structures[0].id != again.structures[1].id && again.structures[1].placement == .underground,
          "a second capture joins the same mod")
    var checkedP: ModPack = again
    let rep2: ModReport = ModValidator.check(&checkedP, known: ModCatalog.build([sampleMod(), again]).keys)
    check(!rep2.disabled.contains(again.structures[0].id) && checkedP.structures[0].cell(1, 1) == 1000, "the saved structure passes the checks, custom block and all")
    var forged = again
    forged.structures[0].cells[0] = Int(Tile.bedrock.rawValue)
    forged.structures[0].cells[1] = Int(Tile.mod05.rawValue)
    forged.structures[0].cells[2] = Int(Tile.battery.rawValue)
    _ = ModValidator.check(&forged, known: [:])
    check(forged.structures[0].cells[0] == -1 && forged.structures[0].cells[1] == -1 && forged.structures[0].cells[2] == -1,
          "a hand-edited structure can't sneak in bedrock, machines or raw custom block numbers")
    ModStore.delete(saved!.id)

    // generation: placed whole, the same every time, clear of the world's landmarks
    let h = arena([hutMod()])
    let hrt = ModRuntime.shared
    let s: ModStructRT = hrt.structures[0]
    let forge: Tile = hrt.tile("smith:forge")!
    var chunkCache: [Int: Chunk] = [:]
    func tileAt(_ x: Int, _ y: Int) -> Tile {
        let cx = floorDiv(x, chunkW)
        if chunkCache[cx] == nil { chunkCache[cx] = generateChunk(h.gen, .overworld, cx) }
        return chunkCache[cx]!.get(x - cx * chunkW, y)
    }
    var sites = 0
    var whole = 0
    var blockedHit = 0
    var chestSpot: (Int, Int)? = nil
    let firstCell = floorDiv(Int(h.pb.x) + 200, 64)
    for cell in firstCell..<(firstCell + 60) {
        guard let site = modStructSite(h.gen, s, .overworld, cell) else { continue }
        sites += 1
        if modSiteBlocked(h.gen, .overworld, site.0, site.0 + 5, .surface) { blockedHit += 1 }
        var ok = true
        for cy in 0..<4 { for cx in 0..<5 {
            let v = s.cells[cy * 5 + cx]
            if v < 0 { continue }
            if tileAt(site.0 + cx, site.1 + cy) != Tile.make(UInt8(v)) { ok = false }
        } }
        if ok { whole += 1 }
        if chestSpot == nil { chestSpot = (site.0 + 2, site.1 + 2) }
    }
    check(sites >= 5 && whole == sites, "custom structures generate whole, across chunk edges (" + String(whole) + " of " + String(sites) + " sites)")
    check(blockedHit == 0, "no site lands on the spawn point, the rift gate or the world's own landmarks")
    check(s.cells[7] == Int(forge.rawValue), "a custom block in a structure becomes that world's tile for it")
    let again1: Chunk = generateChunk(h.gen, .overworld, floorDiv(chestSpot!.0, chunkW))
    check(again1.tiles == chunkCache[floorDiv(chestSpot!.0, chunkW)]!.tiles, "a chunk with a structure comes out the same every time")
    let loot: [Stack] = h.world.chestItems(chestSpot!.0, chestSpot!.1)
    let gemNames: Set<String> = Set(hrt.loot["smith:gems"]!.entries.map { $0.item.name })
    check(!loot.isEmpty && loot.allSatisfy { gemNames.contains($0.item.name) }, "a chest in a structure holds the structure's loot table")
    // under the ground and up in the sky
    let u = arena([hutMod(.underground)])
    let us: ModStructRT = ModRuntime.shared.structures[0]
    var deep = 0
    var deepOK = 0
    for cell in firstCell..<(firstCell + 20) {
        guard let site = modStructSite(u.gen, us, .overworld, cell) else { continue }
        deep += 1
        if site.1 >= 260 && site.1 <= 296 && site.1 > u.gen.col(site.0 + 2).h { deepOK += 1 }
    }
    check(deep > 0 && deep == deepOK, "an underground structure sits inside its chosen depths (" + String(deepOK) + ")")
    let k = arena([hutMod(.sky)])
    let ks: ModStructRT = ModRuntime.shared.structures[0]
    var high = 0
    var highOK = 0
    for cell in firstCell..<(firstCell + 20) {
        guard let site = modStructSite(k.gen, ks, .overworld, cell) else { continue }
        high += 1
        if site.1 + 4 < k.gen.col(site.0 + 2).h - 10 { highOK += 1 }
    }
    check(high > 0 && high == highOK, "a sky structure floats well above the ground")
    // a world made with the structure mod loads safely without it
    let sv = h.makeSave()
    ModRuntime.activate([], world: sv.mods)
    let back = Game.load(sv, settings: Settings())
    check(back.modInfo?.mods.first?.id == "smith", "a world with mod structures loads without the mod and still remembers it")
    ModRuntime.deactivate()
}

print("== done: " + String(passes) + " passed, " + String(fails) + " failed")
try? FileManager.default.removeItem(at: scratch)
exit(fails == 0 ? 0 : 1)
