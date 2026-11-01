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

print("== done: " + String(passes) + " passed, " + String(fails) + " failed")
try? FileManager.default.removeItem(at: scratch)
exit(fails == 0 ? 0 : 1)
