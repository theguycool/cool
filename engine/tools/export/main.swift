import SwiftUI
import Foundation
// Dumps the Swift game's own data and pixel art for the web engine (engine/tools/export.sh):
// JSON tables and raw .rgba pictures, which engine/tools/pack.py packs into engine/src/data_*.js.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/prexport"
let fm = FileManager.default
for sub in ["tiles", "walls", "wallicons", "items", "mobs", "sheet", "clouds", "misc", "parts"] {
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

func writeJSON(_ obj: Any, _ path: String) {
	let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
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
	case .custom(let s): return "custom:" + s
	case .potion(let p): return "potion:" + cn(p)
	case .compound(let c): return "compound:" + cn(c)
	case .exoPart(let p, let m): return "exoPart:" + cn(p) + ":" + cn(m)
	case .exoPlate(let m): return "exoPlate:" + cn(m)
	case .exoCore(let c): return "exoCore:" + cn(c)
	case .exoModule(let m): return "exoModule:" + cn(m)
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
	let bp: BlockPhys = blockPhys(t)
	var e: [String: Any] = ["id": t.idx, "key": cn(t), "name": d.name, "hard": d.hard, "tier": d.tier, "solid": d.solid,
	                        "opaque": d.opaque, "light": d.light, "liquid": d.liquid, "platform": d.platform, "plant": d.plant,
	                        "hurt": d.hurt, "noDrop": d.noDrop, "toolClass": cn(toolClass(t)), "leaf": isLeafTile(t), "log": isLogTile(t),
	                        "supports": t.supportsThings, "needsSupport": game.world.needsSupport(t), "placed": t.placedForm.idx,
	                        "trunk": t.trunkForm.idx, "stair": Int(stairSide(t)), "mod": t.isMod,
	                        "power": cn(powerRole(t)), "weatherDevice": isWeatherDevice(t),
	                        "flips": TileSheet.flips[t.rawValue] ?? 0, "drawn": TileSheet.bufs[t.rawValue] != nil,
	                        "weight": bp.weight, "carry": bp.carry, "span": bp.span, "grip": bp.grip, "bounce": bp.bounce,
	                        "color": Int(d.colors.first ?? 0)]
	if let dr = d.drop { e["drop"] = itemID(dr) }
	tiles.append(e)
}
writeJSON(tiles, "tiles.json")
for (i, w) in painter.wallBufs.enumerated() { writeBuf(w, "walls/\(i).rgba") }

// ---- items
var items: [[String: Any]] = []
var allItems: [Item] = game.creativeItems()
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
		let look: CreatureLook = creatureLook(k, v)
		let set: SpriteSet = lookSpriteSet(look, hitH: d.h)
		for (fi, f) in look.frames.enumerated() { writeBuf(f, "mobs/\(cn(k))_\(v)_\(fi).rgba") }
		variants.append(["frames": look.frames.count, "w": set.w, "h": set.h, "footRow": set.footRow, "centerCol": set.centerCol,
		                 "scale": set.scale, "fine": look.fine,
		                 "idleAlt": look.anim.idleAlt, "attack": look.anim.attack, "hop": look.anim.hop, "hopFrame": look.anim.hopFrame,
		                 "cycle": look.anim.cycle, "walk": look.anim.walk, "poses": look.anim.poses])
	}
	mobs.append(["id": k.rawValue, "key": cn(k), "name": d.name, "w": d.w, "h": d.h, "hp": d.hp, "speed": d.speed, "dmg": d.dmg,
	             "behavior": cn(d.behavior), "flying": d.flying, "aggro": d.aggro, "jump": d.jump, "hostile": d.hostile,
	             "predator": k.isPredator, "thinks": k.thinks, "humanoid": isHumanoid(k), "variants": variants])
}
writeJSON(mobs, "mobs.json")

// ---- every hand-drawn sheet by name (the player's layers are among them)
var sheet: [[String: Any]] = []
for (name, a) in CreatureSheet.arts.sorted(by: { $0.key < $1.key }) {
	let fr: [PixelBuf] = CreatureSheet.frames(name)
	for (i, b) in fr.enumerated() { writeBuf(b, "sheet/\(name)_\(i).rgba") }
	sheet.append(["name": name, "frames": fr.count, "w": a.w, "h": a.h, "foot": a.foot, "cx": a.cx, "poses": a.poses])
}
writeJSON(sheet, "sheet.json")

// ---- clouds, hud icons, vehicle parts
for (i, b) in CloudArt.shared.shapes.enumerated() { writeBuf(b, "clouds/\(i).rgba") }
writeJSON(["classes": CloudArt.shared.classes], "clouds.json")
writeBuf(heartBuf(true), "misc/heart_full.rgba")
writeBuf(heartBuf(false), "misc/heart_empty.rgba")
writeBuf(foodBuf(true), "misc/food_full.rgba")
writeBuf(foodBuf(false), "misc/food_empty.rgba")
writeBuf(bubbleBuf(), "misc/bubble.rgba")
writeBuf(shieldBuf(), "misc/shield.rgba")
for p in PartType.allCases { writeBuf(partBuf(p), "parts/\(cn(p)).rgba") }

// ---- misc tables
var biomes: [String] = []
var bi = 0
while let b = Biome(rawValue: bi) { biomes.append(cn(b)); bi += 1 }
var tiers: [[String: Any]] = []
for t in Tier.allCases { tiers.append(["id": t.rawValue, "key": cn(t), "name": t.name, "color": Int(t.color), "mineSpeed": t.mineSpeed, "damage": t.damage, "defense": t.defense]) }
var sfx: [String] = []
for id in SoundID.allCases { sfx.append(cn(id)) }
writeJSON(["biomes": biomes, "tiers": tiers, "hair": hairChoices.map { Int($0) }, "scarf": scarfChoices.map { Int($0) },
           "shirt": shirtChoices.map { Int($0) }, "pants": pantsChoices.map { Int($0) },
           "hairStyles": hairStyleNames, "shirtStyles": shirtStyleNames, "pantsStyles": pantsStyleNames,
           "hotbar": Inventory.hotbarCount, "bag": Inventory.size, "sfx": sfx], "misc.json")
print("export done:", tiles.count, "tiles,", items.count, "items,", recipes.count, "recipes,", mobs.count, "creatures,", sheet.count, "sheets")
