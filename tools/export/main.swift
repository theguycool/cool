import SwiftUI
import Foundation
// Exports the game's own pixel art, sound effects and data tables so the Godot version can use them:
//   tools/export.sh [folder]   (raw .rgba buffers, .f32 sound samples and JSON tables; tools/godot_assets.py
//   turns them into PNG sheets, WAV files and GDScript data)

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/prexport"
let fm = FileManager.default
for sub in ["tiles", "walls", "wallicons", "items", "mobs", "player", "clouds", "misc", "sfx", "loops", "parts"] {
    try? fm.createDirectory(atPath: outDir + "/" + sub, withIntermediateDirectories: true)
}

/// width, height (little-endian 32-bit) then RGBA bytes
func writeBuf(_ b: PixelBuf, _ path: String) {
    var d = Data()
    var w = UInt32(b.w).littleEndian, h = UInt32(b.h).littleEndian
    withUnsafeBytes(of: &w) { d.append(contentsOf: $0) }
    withUnsafeBytes(of: &h) { d.append(contentsOf: $0) }
    var bytes = [UInt8](repeating: 0, count: b.w * b.h * 4)
    for i in 0..<(b.w * b.h) {
        let c = b.px[i]
        bytes[i * 4] = UInt8((c >> 16) & 255)
        bytes[i * 4 + 1] = UInt8((c >> 8) & 255)
        bytes[i * 4 + 2] = UInt8(c & 255)
        bytes[i * 4 + 3] = UInt8((c >> 24) & 255)
    }
    d.append(contentsOf: bytes)
    fm.createFile(atPath: outDir + "/" + path, contents: d)
}

func writeSamples(_ s: [Float], _ path: String) {
    var d = Data()
    s.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: $0.baseAddress, count: $0.count)) }
    fm.createFile(atPath: outDir + "/" + path, contents: d)
}

func writeJSON(_ obj: Any, _ path: String) {
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    fm.createFile(atPath: outDir + "/" + path, contents: d)
}

func cn<T>(_ v: T) -> String { return "\(v)" }

func itemID(_ it: Item) -> String {
    switch it {
    case .block(let t): return "block:" + cn(t)
    case .tool(let k, let t): return "tool:" + cn(k) + ":" + cn(t)
    case .sword(let t): return "sword:" + cn(t)
    case .armor(let s, let t): return "armor:" + cn(s) + ":" + cn(t)
    case .mat(let m): return "mat:" + cn(m)
    case .food(let f): return "food:" + cn(f)
    case .bow: return "bow"
    case .gun(let g): return "gun:" + cn(g)
    case .ammo(let a): return "ammo:" + cn(a)
    case .part(let p): return "part:" + cn(p)
    case .gadget(let g): return "gadget:" + cn(g)
    case .wall(let k): return "wall:" + String(k)
    case .spear(let t): return "spear:" + cn(t)
    case .hammer(let t): return "hammer:" + cn(t)
    case .gear(let g): return "gear:" + cn(g)
    case .knife(let t): return "knife:" + cn(t)
    case .club(let k): return "club:" + cn(k)
    case .sling: return "sling"
    case .relic(let r): return "relic:" + cn(r)
    }
}

func melee(_ p: MeleeProfile) -> [String: Any] {
    return ["damage": p.damage, "cooldown": p.cooldown, "reach": p.reach, "halfArc": p.halfArc, "style": cn(p.style),
            "band": p.band, "maxHits": p.maxHits, "knock": p.knock, "heavy": p.heavy, "daze": p.daze, "windup": p.windup,
            "swingTime": p.swingTime, "moveScale": p.moveScale, "critChance": p.critChance, "burn": p.burn,
            "undeadMult": p.undeadMult, "combo": p.combo, "backstab": p.backstab, "shockwave": p.shockwave, "trail": Int(p.trail)]
}

let game = Game(mode: .survival, infinite: true, seed: 1, settings: Settings())

// ---- tiles
let painter = SectionPainter.shared
var tiles: [[String: Any]] = []
for t in Tile.allCases {
    writeBuf(painter.tileBufs[t.idx], "tiles/\(t.idx).rgba")
    let d: TileDef = t.def
    var e: [String: Any] = ["id": t.idx, "key": cn(t), "name": d.name, "hard": d.hard, "tier": d.tier, "solid": d.solid,
                            "opaque": d.opaque, "light": d.light, "liquid": d.liquid, "platform": d.platform, "plant": d.plant,
                            "hurt": d.hurt, "noDrop": d.noDrop, "toolClass": cn(toolClass(t)), "leaf": isLeafTile(t), "log": isLogTile(t),
                            "supports": t.supportsThings, "needsSupport": game.world.needsSupport(t), "placed": t.placedForm.idx,
                            "sound": soundMaterial(t), "power": cn(powerRole(t)), "weatherDevice": isWeatherDevice(t),
                            "kind": painter.tileKind[t.idx], "color": Int(d.colors.first ?? 0)]
    if let dr = d.drop { e["drop"] = itemID(dr) }
    tiles.append(e)
}
writeJSON(tiles, "tiles.json")
for (i, w) in painter.wallBufs.enumerated() { writeBuf(w, "walls/\(i + 1).rgba") }
var walls: [[String: Any]] = []
for k in 1...7 {
    writeBuf(wallIcon(k), "wallicons/\(k).rgba")
    walls.append(["kind": k, "name": wallName(k), "source": wallSourceTile(k).idx, "craftable": wallKinds.contains(k)])
}
writeJSON(walls, "walls.json")

// ---- items
var items: [[String: Any]] = []
var allItems: [Item] = game.creativeItems()
for k in [3] where !allItems.contains(.wall(k)) { allItems.append(.wall(k)) }
for (i, it) in allItems.enumerated() {
    let id = itemID(it)
    writeBuf(itemBuf(it), "items/\(i).rgba")
    var e: [String: Any] = ["id": id, "icon": i, "name": it.name, "info": it.infoLines, "maxStack": it.maxStack,
                            "sortGroup": it.sortGroup, "isWeapon": it.isWeapon, "isMelee": it.isMeleeWeapon,
                            "isRanged": it.isRanged, "melee": melee(it.melee)]
    switch it {
    case .block(let t): e["tile"] = t.idx
    case .tool(let k, let t): e["toolKind"] = cn(k); e["tier"] = t.rawValue; e["mineSpeed"] = t.mineSpeed
    case .sword(let t), .spear(let t), .hammer(let t), .knife(let t): e["tier"] = t.rawValue
    case .armor(let s, let t): e["slot"] = cn(s); e["tier"] = t.rawValue; e["defense"] = t.defense * s.weight
    case .food(let f): e["hunger"] = f.hunger; e["heal"] = f.heal
    case .gun(let g):
        var gd: [String: Any] = ["damage": g.damage, "cooldown": g.cooldown, "magazine": g.magazine, "reload": g.reloadTime,
                                 "speed": g.speed, "pierce": g.pierce, "gravity": g.gravity, "life": g.shotLife, "knock": g.knock,
                                 "needsPress": g.needsPress, "firearm": g.isFirearm, "bolts": g.isBoltThrower]
        if let a = g.ammo { gd["ammo"] = itemID(.ammo(a)) }
        e["gun"] = gd
    case .gear(let g): e["effect"] = g.effect
    case .club(let k): e["daze"] = k.daze
    case .part(let p): e["mass"] = p.mass; e["role"] = p.role
    case .mat(let m): e["use"] = m.use
    case .wall(let k): e["wall"] = k
    default: break
    }
    items.append(e)
}
writeJSON(items, "items.json")

// ---- recipes
var recipes: [[String: Any]] = []
for r in RecipeBook.all {
    recipes.append(["out": itemID(r.out), "count": r.outCount, "cost": r.cost.map { [itemID($0.item), $0.n] as [Any] },
                    "station": cn(r.station), "cat": cn(r.cat)])
}
writeJSON(recipes, "recipes.json")

// ---- creatures
var mobs: [[String: Any]] = []
for k in MobKind.allCases {
    let d = mobDef(k)
    var variants: [[String: Any]] = []
    let vcount: Int = k == .zombie ? 3 : ((k == .sheep || k == .wolf) ? 2 : 1)
    for v in 0..<vcount {
        let art = creatureArt(k, v)
        let set = makeSpriteSet(art.0, hitH: d.h, fixedScale: creatureScale, anim: art.1)
        for (fi, f) in art.0.enumerated() { writeBuf(f, "mobs/\(cn(k))_\(v)_\(fi).rgba") }
        variants.append(["frames": art.0.count, "w": set.w, "h": set.h, "footRow": set.footRow, "centerCol": set.centerCol,
                         "idleAlt": art.1.idleAlt, "attack": art.1.attack, "hop": art.1.hop, "cycle": art.1.cycle])
    }
    mobs.append(["id": k.rawValue, "key": cn(k), "name": d.name, "w": d.w, "h": d.h, "hp": d.hp, "speed": d.speed, "dmg": d.dmg,
                 "behavior": cn(d.behavior), "flying": d.flying, "aggro": d.aggro, "jump": d.jump, "hostile": d.hostile,
                 "predator": k.isPredator, "thinks": k.thinks, "humanoid": isHumanoid(k), "variants": variants])
}
writeJSON(mobs, "mobs.json")

// ---- the player: every hair and scarf, and each armour piece on its own (the Godot side layers them)
var player: [String: Any] = ["hairs": hairChoices.count, "scarves": scarfChoices.count]
for h in 0..<hairChoices.count {
    for s in 0..<scarfChoices.count {
        let f = humanoidFrames(playerStyle(hairIdx: h, scarfIdx: s, head: nil, chest: nil, legs: nil))
        for (i, b) in f.enumerated() { writeBuf(b, "player/base_\(h)_\(s)_\(i).rgba") }
    }
}
for t in Tier.allCases {
    for slot in ArmorSlot.allCases {
        let f = humanoidFrames(playerStyle(hairIdx: 0, scarfIdx: 0, head: slot == .head ? t : nil, chest: slot == .chest ? t : nil, legs: slot == .legs ? t : nil))
        for (i, b) in f.enumerated() { writeBuf(b, "player/armor_\(cn(slot))_\(t.rawValue)_\(i).rgba") }
    }
}
let pf = humanoidFrames(playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil))
let pset = makeSpriteSet(pf, hitH: 1.8, fixedScale: 0.125)
player["frames"] = pf.count
player["w"] = pset.w; player["h"] = pset.h; player["footRow"] = pset.footRow; player["centerCol"] = pset.centerCol
writeJSON(player, "player.json")

// ---- clouds, hud icons, boat, vehicle parts
for (i, b) in CloudArt.shared.shapes.enumerated() { writeBuf(b, "clouds/\(i).rgba") }
writeJSON(["classes": CloudArt.shared.classes], "clouds.json")
writeBuf(heartBuf(true), "misc/heart_full.rgba")
writeBuf(heartBuf(false), "misc/heart_empty.rgba")
writeBuf(foodBuf(true), "misc/food_full.rgba")
writeBuf(foodBuf(false), "misc/food_empty.rgba")
writeBuf(bubbleBuf(), "misc/bubble.rgba")
writeBuf(shieldBuf(), "misc/shield.rgba")
writeBuf(spritePirateBoat(), "misc/pirate_ship.rgba")
for p in PartType.allCases { writeBuf(partBuf(p), "parts/\(cn(p)).rgba") }

// ---- sound
var sfx: [String] = []
for id in SoundID.allCases {
    for v in 0..<3 { writeSamples(SoundBank.effect(id, v), "sfx/\(cn(id))_\(v).f32") }
    sfx.append(cn(id))
}
var loops: [String] = []
for l in LoopID.allCases { writeSamples(SoundBank.loop(l), "loops/\(cn(l)).f32"); loops.append(cn(l)) }
writeJSON(["sfx": sfx, "loops": loops, "rate": Synth.rate], "sound.json")

// ---- misc tables
var biomes: [String] = []
var bi = 0
while let b = Biome(rawValue: bi) { biomes.append(cn(b)); bi += 1 }
var tiers: [[String: Any]] = []
for t in Tier.allCases { tiers.append(["id": t.rawValue, "key": cn(t), "name": t.name, "color": Int(t.color), "mineSpeed": t.mineSpeed, "damage": t.damage, "defense": t.defense]) }
writeJSON(["biomes": biomes, "tiers": tiers, "hair": hairChoices.map { Int($0) }, "scarf": scarfChoices.map { Int($0) },
           "hotbar": Inventory.hotbarCount, "bag": Inventory.size], "misc.json")
print("export done:", tiles.count, "tiles,", items.count, "items,", recipes.count, "recipes,", mobs.count, "creatures,", sfx.count, "sounds")
