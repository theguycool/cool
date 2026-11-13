// PIXEL REALM v2, part 4 of 6: Mod Creator+ (game content changes, ore controls, sprite tools, custom infusions, boss phases
// and summoning, custom dimensions with their suns, moons and trees, the Logic Studio, rules, weather, machines,
// vehicles and themes in mods), the art store and the player's look, sound, weather, ambient and animal life, the
// journal and telegraphed attacks.
// The game is six files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm6.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 1 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== p32_modplus =====

// MARK: - Mod Creator+: changing the game's own content

/// What a change to the game's own content applies to
enum ModOverrideKind: Int, Codable, CaseIterable {
	case block, item, creature
	var name: String {
		switch self {
		case .block: return "Game block"
		case .item: return "Game item"
		case .creature: return "Game creature"
		}
	}
}

/// A change a mod makes to something of the game itself: a block's hardness, a weapon's damage, a
/// creature's health and so on. Only the numbers set here change (nil: the game's own value), the
/// original is never touched (switching the mod off, or this change off, puts it back), and each
/// change can be switched off by itself.
struct ModOverride: Codable, Identifiable, Equatable {
	var id: String = ""
	var kind: ModOverrideKind = .block
	/// the block (tile number), item, or creature (kind number) changed
	var tile: Int = Int(Tile.stone.rawValue)
	var item: Item? = nil
	var mob: Int = MobKind.zombie.rawValue
	var enabled: Bool = true
	// blocks
	var hardness: Double? = nil
	var tier: Int? = nil
	var light: Int? = nil
	var unbreakable: Bool? = nil
	// items
	var damage: Double? = nil
	var cooldown: Double? = nil
	var reach: Double? = nil
	var knock: Double? = nil
	var crit: Double? = nil
	var mineSpeed: Double? = nil
	var defense: Double? = nil
	var hunger: Double? = nil
	var heal: Double? = nil
	// creatures
	var hp: Double? = nil
	var mobDamage: Double? = nil
	var speed: Double? = nil
	var detect: Double? = nil
	var jump: Double? = nil
	/// a creature's own sprite, painted over the game's (nil: the game's): every frame, in the game's
	/// order (standing, walking, the rest)
	var frames: [ModPixels]? = nil
	/// true when the frames were painted over the creature's hand-drawn picture (16 pixels to a block,
	/// its frame order); false for a repaint of the older picture, which keeps that one's size and order
	var fine: Bool = false

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		kind = c.val(.kind, .block)
		tile = c.val(.tile, Int(Tile.stone.rawValue))
		item = c.val(.item, nil)
		mob = c.val(.mob, MobKind.zombie.rawValue)
		enabled = c.val(.enabled, true)
		hardness = c.val(.hardness, nil)
		tier = c.val(.tier, nil)
		light = c.val(.light, nil)
		unbreakable = c.val(.unbreakable, nil)
		damage = c.val(.damage, nil)
		cooldown = c.val(.cooldown, nil)
		reach = c.val(.reach, nil)
		knock = c.val(.knock, nil)
		crit = c.val(.crit, nil)
		mineSpeed = c.val(.mineSpeed, nil)
		defense = c.val(.defense, nil)
		hunger = c.val(.hunger, nil)
		heal = c.val(.heal, nil)
		hp = c.val(.hp, nil)
		mobDamage = c.val(.mobDamage, nil)
		speed = c.val(.speed, nil)
		detect = c.val(.detect, nil)
		jump = c.val(.jump, nil)
		frames = c.val(.frames, nil)
		fine = c.val(.fine, false)
	}

	/// what it changes, by name
	var targetName: String {
		switch kind {
		case .block: return Tile(rawValue: UInt8(clampI(tile, 0, 255)))?.name ?? "Block"
		case .item: return item?.name ?? "Item"
		case .creature: return MobKind(rawValue: mob).map { mobDef($0).name } ?? "Creature"
		}
	}

	/// how many numbers it changes
	var changedCount: Int {
		let opts: [Bool] = [hardness != nil, tier != nil, light != nil, unbreakable != nil, damage != nil, cooldown != nil, reach != nil, knock != nil,
							crit != nil, mineSpeed != nil, defense != nil, hunger != nil, heal != nil, hp != nil, mobDamage != nil, speed != nil, detect != nil, jump != nil,
							frames != nil]
		return opts.filter { $0 }.count
	}

	/// Later changes win, field by field (the mod lower in the load order goes on top)
	mutating func merge(_ o: ModOverride) {
		if let v = o.hardness { hardness = v }
		if let v = o.tier { tier = v }
		if let v = o.light { light = v }
		if let v = o.unbreakable { unbreakable = v }
		if let v = o.damage { damage = v }
		if let v = o.cooldown { cooldown = v }
		if let v = o.reach { reach = v }
		if let v = o.knock { knock = v }
		if let v = o.crit { crit = v }
		if let v = o.mineSpeed { mineSpeed = v }
		if let v = o.defense { defense = v }
		if let v = o.hunger { hunger = v }
		if let v = o.heal { heal = v }
		if let v = o.hp { hp = v }
		if let v = o.mobDamage { mobDamage = v }
		if let v = o.speed { speed = v }
		if let v = o.detect { detect = v }
		if let v = o.jump { jump = v }
		if let v = o.frames {
			frames = v
			fine = o.fine
		}
	}

	/// A melee profile with this change's numbers
	func apply(_ p0: MeleeProfile) -> MeleeProfile {
		var p: MeleeProfile = p0
		if let v = damage { p.damage = v }
		if let v = cooldown { p.cooldown = v }
		if let v = reach { p.reach = v }
		if let v = knock { p.knock = v }
		if let v = crit { p.critChance = v }
		return p
	}
}

/// The changes to game content of the mods a world uses, merged and ready (empty without mods). The
/// game's own tables are put back before every new set goes in, so nothing stays changed by accident.
final class OverrideRT {
	static var shared: OverrideRT = OverrideRT()
	/// tiles and creatures whose table entries are changed now
	static var patchedTiles: Set<Int> = []
	static var patchedMobs: Set<Int> = []

	var blocks: [Int: ModOverride] = [:]
	var items: [Item: ModOverride] = [:]
	var mobs: [Int: ModOverride] = [:]
	/// creatures whose sprite a mod repainted: their frames, ready to draw
	var mobArt: [Int: [PixelBuf]] = [:]
	/// which of those repaints were painted over the hand-drawn picture (ModOverride.fine)
	var mobFine: [Int: Bool] = [:]
	var isEmpty: Bool { return blocks.isEmpty && items.isEmpty && mobs.isEmpty }

	static func build(_ packs: [ModPack], _ disabled: Set<String>) -> OverrideRT {
		let o = OverrideRT()
		for p in packs {
			for v in p.overrides where v.enabled && !disabled.contains(p.key(v.id)) {
				switch v.kind {
				case .block:
					guard let t = Tile(rawValue: UInt8(clampI(v.tile, 0, 255))), !t.isMod, t != .air, t != .bedrock else { continue }
					var m: ModOverride = o.blocks[v.tile] ?? v
					if o.blocks[v.tile] != nil { m.merge(v) }
					o.blocks[v.tile] = m
				case .item:
					guard let it = v.item, ModOverrideCheck.itemAllowed(it) else { continue }
					var m: ModOverride = o.items[it] ?? v
					if o.items[it] != nil { m.merge(v) }
					o.items[it] = m
				case .creature:
					guard let k = MobKind(rawValue: v.mob), k != .custom, k != .villager else { continue }
					var m: ModOverride = o.mobs[v.mob] ?? v
					if o.mobs[v.mob] != nil { m.merge(v) }
					o.mobs[v.mob] = m
				}
			}
		}
		for (raw, m) in o.mobs {
			guard let fr = m.frames, !fr.isEmpty, fr.allSatisfy({ $0.valid }) else { continue }
			var bufs: [PixelBuf] = []
			for f in fr { bufs.append(OverrideRT.frameBuf(f)) }
			o.mobArt[raw] = bufs
			o.mobFine[raw] = m.fine
		}
		return o
	}

	/// One repainted frame as the game draws it (with a dark outline when the maker switched it on;
	/// frames copied from the game already have theirs)
	static func frameBuf(_ f: ModPixels) -> PixelBuf {
		if !f.outlined(false) { return f.buf() }
		var b: PixelBuf = padBuf(f.buf())
		b.outline(0x101010)
		return b
	}

	/// A game creature's frames as a mod repainted them (nil: the game's own). Sheared sheep and tame
	/// wolves keep the game's look for that state.
	func creatureArt(_ k: MobKind, _ variant: Int) -> [PixelBuf]? {
		if mobArt.isEmpty { return nil }
		if variant != 0 && (k == .sheep || k == .wolf) { return nil }
		return mobArt[k.rawValue]
	}

	/// Puts the changes into the game's tables (after putting back the last set)
	func install() {
		for raw in OverrideRT.patchedTiles {
			if let t = Tile(rawValue: UInt8(clampI(raw, 0, 255))) { Tile.setGameDef(t, Tile.makeDef(t)) }
		}
		for raw in OverrideRT.patchedMobs {
			if let k = MobKind(rawValue: raw), raw < mobDefTable.count { mobDefTable[raw] = makeMobDef(k) }
		}
		OverrideRT.patchedTiles = []
		OverrideRT.patchedMobs = []
		for (raw, o) in blocks {
			guard let t = Tile(rawValue: UInt8(clampI(raw, 0, 255))) else { continue }
			var d: TileDef = Tile.makeDef(t)
			if let v = o.hardness { d.hard = v }
			if let v = o.tier { d.tier = v }
			if let v = o.light { d.light = v }
			if o.unbreakable == true { d.hard = 9999 }
			Tile.setGameDef(t, d)
			OverrideRT.patchedTiles.insert(raw)
		}
		for (raw, o) in mobs {
			guard let k = MobKind(rawValue: raw), raw < mobDefTable.count else { continue }
			var d: MobDef = makeMobDef(k)
			if let v = o.hp { d.hp = v }
			if let v = o.mobDamage { d.dmg = v }
			if let v = o.speed { d.speed = v }
			if let v = o.detect { d.aggro = v }
			if let v = o.jump { d.jump = v }
			mobDefTable[raw] = d
			OverrideRT.patchedMobs.insert(raw)
		}
	}

	/// a tool's mining speed when a mod changed it (nil: the game's own)
	func toolSpeed(_ it: Item) -> Double? {
		if items.isEmpty { return nil }
		return items[it]?.mineSpeed
	}
}

/// What the override editor may change, and the ranges it allows
enum ModOverrideCheck {
	static func itemAllowed(_ it: Item) -> Bool {
		switch it {
		case .sword, .spear, .hammer, .knife, .club, .relic, .tool, .armor, .food, .gun, .bow, .sling: return true
		default: return false
		}
	}

	/// Every game item that can be changed, in a sensible order
	static func items() -> [Item] {
		return allGameItems().filter { itemAllowed($0) }
	}

	/// Every game block that can be changed
	static func tiles() -> [Tile] {
		return Tile.allCases.filter { !$0.isMod && $0 != .air && $0 != .bedrock && $0 != .portalOn && $0 != .portalOff && $0 != .portalFrame }
	}

	/// Every game creature that can be changed
	static func mobs() -> [MobKind] {
		return MobKind.allCases.filter { $0 != .custom && $0 != .villager }
	}

	static func clamp(_ o: inout ModOverride, _ sandbox: Bool) {
		if let v = o.hardness { o.hardness = ModRange.hardness.clamp(v, sandbox) }
		if let v = o.tier { o.tier = clampI(v, 0, 9) }
		if let v = o.light { o.light = clampI(v, 0, 15) }
		if let v = o.damage { o.damage = ModRange.damage.clamp(v, sandbox) }
		if let v = o.cooldown { o.cooldown = ModRange.cooldown.clamp(v, sandbox) }
		if let v = o.reach { o.reach = ModRange.reach.clamp(v, sandbox) }
		if let v = o.knock { o.knock = ModRange.knock.clamp(v, sandbox) }
		if let v = o.crit { o.crit = clampD(v.isFinite ? v : 0, 0, 1) }
		if let v = o.mineSpeed { o.mineSpeed = ModRange.toolSpeed.clamp(v, sandbox) }
		if let v = o.defense { o.defense = ModRange.defense.clamp(v, sandbox) }
		if let v = o.hunger { o.hunger = ModRange.heal.clamp(v, sandbox) }
		if let v = o.heal { o.heal = ModRange.heal.clamp(v, sandbox) }
		if let v = o.hp { o.hp = ModRange.bossHP.clamp(max(1, v), sandbox) }
		if let fr = o.frames {
			// only whole, sound pictures, at most 12 frames, all one size
			let good: [ModPixels] = fr.filter { $0.valid }.prefix(12).map { $0 }
			if good.isEmpty { o.frames = nil } else {
				let w0: Int = good[0].w
				let h0: Int = good[0].h
				o.frames = good.map { ($0.w == w0 && $0.h == h0) ? $0 : $0.resized(w0, h0) }
			}
		}
		if let v = o.mobDamage { o.mobDamage = ModRange.damage.clamp(v, sandbox) }
		if let v = o.speed { o.speed = ModRange.mobSpeed.clamp(v, sandbox) }
		if let v = o.detect { o.detect = ModRange.detect.clamp(v, sandbox) }
		if let v = o.jump { o.jump = ModRange.jump.clamp(v, sandbox) }
		if o.kind == .creature && o.hp != nil { o.hp = max(1, min(o.hp ?? 1, sandbox ? 20000 : 4000)) }
	}
}

extension Tile {
	/// Changes a game tile's entry in every table (a mod's override, or putting the original back)
	static func setGameDef(_ t: Tile, _ d: TileDef) {
		let i: Int = Int(t.rawValue)
		if t.isMod || i >= defTable.count { return }
		defTable[i] = d
		hardTable[i] = d.hard
		tierTable[i] = d.tier
		lightTable[i] = d.light
	}
}

// MARK: - The game's own numbers, as the editors show them

/// How quickly a tool breaks a block: the same numbers mining uses (bare hands: kind nil). The time a
/// block takes is hardness x 1.5 divided by this; nil when the tool can't break it at all.
func miningSpeed(_ t: Tile, _ kind: ToolType?, _ tier: Tier?, toolSpeed: Double? = nil) -> Double? {
	let def: TileDef = t.def
	if def.hard >= 9999 { return nil }
	let cls: ToolType = toolClass(t)
	if def.tier > 0 {
		let pt: Int = (kind == cls) ? (tier?.rawValue ?? 0) : 0
		if pt < def.tier { return nil }
	}
	var speed: Double = 1.0
	if let k = kind, let tr = tier { speed = (toolSpeed ?? tr.mineSpeed) * (k == cls ? 1.0 : 0.35) }
	return speed
}

/// Seconds a block takes to break with a tool (nil: it can't)
func miningSeconds(_ t: Tile, _ kind: ToolType?, _ tier: Tier?, toolSpeed: Double? = nil) -> Double? {
	guard let s = miningSpeed(t, kind, tier, toolSpeed: toolSpeed) else { return nil }
	let need: Double = max(0.05, t.def.hard * 1.5)
	return need / max(0.001, s)
}

/// Seconds a mod block would take with a tool, from its own numbers (before it is in any world)
func miningSecondsFor(hardness: Double, tier: Int, blockTool: ToolType, unbreakable: Bool, _ kind: ToolType?, _ toolTier: Int, toolSpeed: Double) -> Double? {
	if unbreakable || hardness >= 9999 { return nil }
	if tier > 0 {
		let pt: Int = kind == blockTool ? toolTier : 0
		if pt < tier { return nil }
	}
	var speed: Double = 1.0
	if let k = kind { speed = toolSpeed * (k == blockTool ? 1.0 : 0.35) }
	let need: Double = max(0.05, hardness * 1.5)
	return need / max(0.001, speed)
}

func secondsText(_ s: Double?) -> String {
	guard let v = s else { return "can't" }
	if v < 10 { return String(format: "%.2f s", v) }
	return String(format: "%.0f s", v)
}

// MARK: - Starting from game content

extension ModBlock {
	/// A block's picture is 16 x 16 like the game's hand-drawn blocks, or 8 x 8 (drawn with every pixel
	/// doubled) as all custom blocks used to be; any other size is cut to 8 x 8
	static func fitArt(_ a: ModPixels) -> ModPixels {
		if a.w == tileArtPx && a.h == tileArtPx { return a }
		return a.resized(8, 8)
	}

	/// A custom block copied from one of the game's blocks: its picture and numbers, ready to change
	static func fromGame(_ t: Tile) -> ModBlock {
		var b = ModBlock()
		b.name = joinText(t.name, " (custom)")
		b.art = ModPixels(buf: tileBuf(t))
		b.hardness = min(40, t.def.hard)
		b.unbreakable = t.def.hard >= 9999
		b.tool = toolClass(t).rawValue
		b.tier = t.def.tier
		b.light = t.def.light
		b.transparent = !t.def.opaque
		b.collision = t.def.solid ? .solid : (t.def.platform ? .platform : .none)
		b.category = t.def.light > 0 ? .light : .building
		return b
	}
}

extension ModItem {
	/// A custom item copied from one of the game's items: its kind, look and numbers
	static func fromGame(_ it: Item) -> ModItem {
		var m = ModItem()
		m.name = joinText(it.name, " (custom)")
		m.baseIcon = it
		m.stack = it.maxStack
		let p: MeleeProfile = it.melee
		switch it {
		case .sword, .spear, .hammer, .knife, .club, .relic:
			m.kind = .melee
			m.damage = p.damage
			m.cooldown = p.cooldown
			m.reach = p.reach
			m.arc = p.halfArc
			m.knock = p.knock
			m.maxHits = p.maxHits
			m.heavy = p.heavy
			m.daze = p.daze
			m.burn = p.burn
			m.windup = p.windup
			m.combo = p.combo
			m.backstab = p.backstab
			m.undeadMult = p.undeadMult
			m.crit = p.critChance
			m.trail = p.trail
			m.style = p.style.rawValue
		case .tool(let k, let t):
			m.kind = .tool
			m.toolType = k.rawValue
			m.toolTier = t.rawValue
			m.toolSpeed = t.mineSpeed
			m.damage = p.damage
			m.cooldown = p.cooldown
		case .armor(let s, let t):
			m.kind = .armor
			m.slot = s.rawValue
			m.defense = t.defense * s.weight
			m.look = t.rawValue
		case .food(let f):
			m.kind = .food
			m.hunger = f.hunger
			if f.heal > 0 { m.effects = [ModEffect(.heal, f.heal, 0)] }
		case .gun(let g):
			m.kind = .gun
			m.damage = g.damage
			m.cooldown = g.cooldown
			m.speed = g.speed
			m.gravity = g.gravity
			m.pierce = g.pierce
			m.magazine = g.magazine
			m.reload = g.reloadTime
			m.needsPress = g.needsPress
			if let a = g.ammo { m.ammo = .ammo(a) }
		case .bow, .sling:
			m.kind = .bow
			m.damage = 8
		default:
			m.kind = .material
		}
		return m
	}
}

extension ModMob {
	/// A custom creature copied from one of the game's: its look (as its base) and its numbers
	static func fromGame(_ k: MobKind) -> ModMob {
		var m = ModMob()
		let d: MobDef = mobDef(k)
		m.name = joinText(d.name, " (custom)")
		m.base = k.rawValue
		m.hp = d.hp
		m.damage = d.dmg
		m.speed = d.speed
		m.detect = d.aggro
		m.jump = d.jump
		switch d.behavior {
		case .passive, .skittish: m.category = .passive
		case .defensive: m.category = .neutral
		case .boss: m.category = .boss
		case .flyer: m.category = .flying
		case .swimmer: m.category = .water
		default: m.category = d.hostile ? .hostile : .neutral
		}
		m.behavior.chase = d.hostile
		m.behavior.attackPlayer = d.hostile
		return m
	}
}

// MARK: - Versions, folders and dependencies

/// A saved snapshot of a mod
struct ModVersion: Codable {
	var label: String
	var time: Double
	var mod: ModPack
}

/// A snapshot as the version list shows it
struct ModVersionInfo: Identifiable {
	var id: String { return file }
	var file: String
	var label: String
	var time: Double
	var version: String
}

extension ModStore {
	static var versionDir: URL {
		let u: URL = dir.appendingPathComponent("versions", isDirectory: true)
		try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
		return u
	}
	static let maxVersions: Int = 12

	/// Keeps a copy of the mod as it is now, under a label (the oldest copies go past the limit)
	@discardableResult
	static func saveVersion(_ p: ModPack, label: String) -> Bool {
		if p.id.isEmpty { return false }
		let now: Double = Date().timeIntervalSince1970
		let v: ModVersion = ModVersion(label: label.isEmpty ? "Saved version" : String(label.prefix(40)), time: now, mod: p)
		guard let d = try? JSONEncoder().encode(v) else { return false }
		let name: String = joinText(p.id, "@", String(Int(now * 1000)), ".json")
		do {
			try d.write(to: versionDir.appendingPathComponent(name), options: .atomic)
		} catch {
			return false
		}
		let list: [ModVersionInfo] = versions(p.id)
		if list.count > maxVersions {
			for old in list.suffix(list.count - maxVersions) { try? FileManager.default.removeItem(at: versionDir.appendingPathComponent(old.file)) }
		}
		return true
	}

	/// The saved versions of a mod, newest first
	static func versions(_ id: String) -> [ModVersionInfo] {
		let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: versionDir.path)) ?? []
		var out: [ModVersionInfo] = []
		for n in names where n.hasPrefix(id + "@") && n.hasSuffix(".json") {
			guard let d = try? Data(contentsOf: versionDir.appendingPathComponent(n)), let v = try? JSONDecoder().decode(ModVersion.self, from: d) else { continue }
			out.append(ModVersionInfo(file: n, label: v.label, time: v.time, version: v.mod.version))
		}
		out.sort { $0.time > $1.time }
		return out
	}

	/// Puts a saved version back as the mod (keeping a copy of how it was just before)
	static func restoreVersion(_ id: String, _ file: String) -> ModPack? {
		guard let d = try? Data(contentsOf: versionDir.appendingPathComponent(file)), var v = try? JSONDecoder().decode(ModVersion.self, from: d) else { return nil }
		if let cur = pack(id) { saveVersion(cur, label: "Before restoring an older version") }
		v.mod.id = id
		return save(v.mod) ? pack(id) : nil
	}

	static func deleteVersion(_ file: String) {
		try? FileManager.default.removeItem(at: versionDir.appendingPathComponent(file))
	}

	/// The other mods this mod needs: those it names, and those whose content it uses
	static func dependencies(_ p: ModPack) -> [String] {
		var out: [String] = p.requires.filter { $0 != p.id }
		func add(_ k: String) {
			let m: String = splitModKey(k).0
			if !m.isEmpty && m != p.id && !out.contains(m) { out.append(m) }
		}
		func addItem(_ it: Item?) {
			if let i = it, case .custom(let k) = i { add(k) }
		}
		for b in p.blocks { addItem(b.drop) }
		for i in p.items {
			addItem(i.ammo)
			addItem(i.baseIcon)
		}
		for m in p.mobs {
			for d in m.drops { addItem(d.item) }
			if !m.behavior.guardKey.isEmpty { add(m.behavior.guardKey) }
		}
		for r in p.recipes {
			addItem(r.out)
			for c in r.cost { addItem(c.item) }
		}
		for l in p.loot { for e in l.entries { addItem(e.item) } }
		for s in p.structures { for k in s.palette where k.contains(":") { add(k) } }
		for f in p.infusions { for it in f.items { addItem(it) } }
		for m in p.mobs {
			for f in m.phases where f.helper.contains(":") { add(f.helper) }
			for sm in m.summons {
				addItem(sm.item)
				for k in sm.pattern.cells where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
			}
		}
		for o in p.ores {
			for k in o.hosts where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
			if o.near.contains(":") && !o.near.hasPrefix("tile:") { add(o.near) }
		}
		for m in p.mobs { for sm in m.summons { for k in sm.dimKeys { add(k) } } }
		for d in p.dims {
			for k in [d.stone, d.hazard, d.gateBlock] where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
			for z in d.zones {
				for k in [z.ground, z.filler, z.plant, z.log, z.leaves] where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
			}
			for sp in d.spawns where sp.creature.contains(":") { add(sp.creature) }
			addItem(d.entry.item)
			for k in d.entry.pattern.cells where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
		}
		for t in p.trees {
			for k in [t.trunk, t.branch, t.leaves, t.ground] where k.contains(":") && !k.hasPrefix("tile:") { add(k) }
		}
		for m in p.suitMats { addItem(m.cost) }
		for d in p.suitDesigns {
			for piece in d.design.pieces {
				if piece.modMat.contains(":") { add(piece.modMat) }
				if piece.modPart.contains(":") { add(piece.modPart) }
			}
		}
		for s in p.startItems { addItem(s.item) }
		for v in p.vehicles {
			for c in v.cells where c.block.contains(":") && !c.block.hasPrefix("tile:") { add(c.block) }
		}
		for sc in p.scripts { LKeys.uses(sc, add, addItem) }
		return out
	}

	/// Folder names in use, sorted
	static func folders() -> [String] {
		var out: Set<String> = []
		for e in entries() { if let p = e.pack, !p.folder.isEmpty { out.insert(p.folder) } }
		return out.sorted()
	}
}

extension ModValidator {
	/// The Mod Creator+ parts of a mod: changes to game content, the folder, needed mods and content
	/// switched off
	static func checkPlus(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		if p.folder.count > 24 { p.folder = String(p.folder.prefix(24)) }
		var req: [String] = []
		for q in p.requires where !q.isEmpty && q != p.id && !req.contains(q) { req.append(q) }
		if req.count > 12 { req = Array(req.prefix(12)) }
		p.requires = req
		if p.overrides.count > 64 {
			r.add(1, mn, "Mod", "Only 64 changes to game content fit in one mod; the rest were left out.")
			p.overrides = Array(p.overrides.prefix(64))
		}
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id })
		var keep: [ModOverride] = []
		for var o in p.overrides {
			if o.id.isEmpty || used.contains(o.id) { o.id = p.freshID("g") + String(keep.count) }
			used.insert(o.id)
			let place: String = joinText("Change to \u{201C}", o.targetName, "\u{201D}")
			switch o.kind {
			case .block:
				guard let t = Tile(rawValue: UInt8(clampI(o.tile, 0, 255))), ModOverrideCheck.tiles().contains(t) else {
					r.add(1, mn, place, "That block can't be changed; the change was left out.")
					continue
				}
			case .item:
				guard let it = o.item, ModOverrideCheck.itemAllowed(it) else {
					r.add(1, mn, place, "That item can't be changed; the change was left out.")
					continue
				}
			case .creature:
				guard let k = MobKind(rawValue: o.mob), k != .custom, k != .villager else {
					r.add(1, mn, place, "That creature can't be changed; the change was left out.")
					continue
				}
			}
			ModOverrideCheck.clamp(&o, sb)
			keep.append(o)
		}
		p.overrides = keep
		let ids: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.recipes.map { $0.id } + p.ores.map { $0.id } + p.structures.map { $0.id } + p.overrides.map { $0.id } + p.projectiles.map { $0.id } + p.loot.map { $0.id } + p.infusions.map { $0.id } + p.dims.map { $0.id } + p.scripts.map { $0.id })
		p.off = p.off.filter { ids.contains($0) }
		_ = known
		checkOrePlus(&p, mn, &r)
		checkInfusions(&p, mn, sb, known, &r)
		checkBosses(&p, mn, sb, known, &r)
		checkDims(&p, mn, sb, known, &r)
		checkSuits(&p, mn, sb, known, &r)
		checkWorldRules(&p, mn, sb, known, &r)
		checkScripts(&p, mn, sb, known, &r)
		let dimIDs: Set<String> = Set(p.dims.map { $0.id })
		for i in p.ores.indices where !p.ores[i].dimKey.isEmpty && !dimIDs.contains(p.ores[i].dimKey) { p.ores[i].dimKey = "" }
		for i in p.structures.indices where !p.structures[i].dimKey.isEmpty && !dimIDs.contains(p.structures[i].dimKey) { p.structures[i].dimKey = "" }
	}
}

// MARK: - Mod Creator+: ore generation

extension ModOre {
	static let placeNames: [String] = ["Inside the rock", "On cave walls", "Near the surface", "Under water"]
	static let placeHelp: [String] = ["Anywhere in its host ground between the two depths.",
									  "Only where the ground meets a cave (a block with open air beside it).",
									  "Within a few blocks of the top of the ground (the depths are ignored).",
									  "In the ground under seas and lakes (the depths are ignored)."]
	static let shapeNames: [String] = ["Lumps", "Streaks", "Scattered"]
}

/// Where one ore is generated, worked out once per world
extension ModOreRT {
	/// Places this ore in one freshly made chunk. With the original settings (inside the rock, every
	/// chunk, lumps, any host of its kind) it uses the same random numbers in the same order as before
	/// these controls existed, so worlds made with older mods keep generating the same ore.
	func place(_ g: WorldGen, _ ch: Chunk) {
		let H: Int = ch.H
		var rng = RNG(hashU(ch.cx, 0x51ED, g.seed &+ salt))
		var extra = RNG(hashU(ch.cx, 0x7A11, g.seed &+ salt))
		if rarity < 1.0 && extra.double() >= rarity { return }
		var colOK: [Bool] = [Bool](repeating: true, count: chunkW)
		if !biomes.isEmpty {
			var any: Bool = false
			for lx in 0..<chunkW {
				colOK[lx] = biomes.contains(g.col(ch.x0 + lx).biome.rawValue)
				if colOK[lx] { any = true }
			}
			if !any { return }
		}
		let whole: Int = Int(veins)
		let n: Int = min(24, whole + (rng.double() < veins - Double(whole) ? 1 : 0))
		let y0: Int = clampI(minY, 1, H - 2)
		let y1: Int = clampI(maxY, y0, H - 2)
		var v: Int = 0
		while v < n {
			var lx: Int = rng.int(chunkW)
			var y: Int = y0 + rng.int(y1 - y0 + 1)
			v += 1
			var lo: Int = y0
			var hi: Int = y1
			if place == 2 || place == 3 {
				// near the top of the ground (or the sea bed): the depths do not apply
				y = clampI(ch.surf[lx] + extra.int(3), 1, H - 2)
				lo = max(1, y - 3)
				hi = min(H - 2, y + 4)
			}
			if let near = nearTile {
				var found: Bool = hasNear(ch, lx, y, near)
				var tries: Int = 0
				while !found && tries < 10 {
					lx = extra.int(chunkW)
					y = lo + extra.int(max(1, hi - lo + 1))
					found = hasNear(ch, lx, y, near)
					tries += 1
				}
				if !found { continue }
			}
			var k: Int = 0
			switch shape {
			case 1:
				// a streak: a line in one direction, wandering a little
				let dirs: [(Int, Int)] = [(1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1), (0, 1), (0, -1)]
				let d: (Int, Int) = dirs[extra.int(dirs.count)]
				while k < size {
					put(ch, g, lx, y, colOK)
					lx = clampI(lx + d.0, 0, chunkW - 1)
					y = clampI(y + d.1, lo, hi)
					if extra.int(4) == 0 { y = clampI(y + (extra.int(2) == 0 ? -1 : 1), lo, hi) }
					k += 1
				}
			case 2:
				// scattered single blocks around the spot
				while k < size {
					put(ch, g, clampI(lx + extra.int(7) - 3, 0, chunkW - 1), clampI(y + extra.int(7) - 3, lo, hi), colOK)
					k += 1
				}
			default:
				// a short random walk keeps each vein in one lump, inside this chunk and the ore's depths
				while k < size {
					put(ch, g, lx, y, colOK)
					switch rng.int(4) {
					case 0: lx = min(chunkW - 1, lx + 1)
					case 1: lx = max(0, lx - 1)
					case 2: y = min(hi, y + 1)
					default: y = max(lo, y - 1)
					}
					k += 1
				}
			}
		}
	}

	/// One block of ore, if the spot is right for it
	func put(_ ch: Chunk, _ g: WorldGen, _ lx: Int, _ y: Int, _ colOK: [Bool]) {
		if !colOK[lx] { return }
		let t: Tile = ch.get(lx, y)
		if hostTiles.isEmpty {
			if !modOreHost(t, host) { return }
		} else if !hostTiles.contains(t.rawValue) {
			return
		}
		switch place {
		case 1:
			// a cave wall: open air beside it
			let open: Bool = (lx > 0 && ch.get(lx - 1, y) == .air) || (lx < chunkW - 1 && ch.get(lx + 1, y) == .air) || ch.get(lx, y - 1) == .air || ch.get(lx, y + 1) == .air
			if !open { return }
		case 3:
			// under water: water just above in this column
			var wet: Bool = false
			for dy in 1...4 where ch.get(lx, y - dy) == .water { wet = true }
			if !wet { return }
		default: break
		}
		ch.setLocal(lx, y, tile)
	}

	/// Another ore within three blocks (in this chunk)
	func hasNear(_ ch: Chunk, _ lx: Int, _ y: Int, _ t: Tile) -> Bool {
		for dy in -3...3 {
			for dx in -3...3 {
				let x: Int = lx + dx
				if x < 0 || x >= chunkW { continue }
				if ch.get(x, y + dy) == t { return true }
			}
		}
		return false
	}
}

/// Picks of game ground for an ore's host and neighbour: game tiles as "tile:<number>"
enum ModGround {
	static let hosts: [Tile] = [.stone, .slate, .deepRock, .dirt, .sand, .mud, .snow, .sandstone, .ashStone, .grass, .ice, .obsidian]
	static let ores: [Tile] = [.coal, .copper, .tin, .iron, .silver, .gold, .saltpeter, .amethyst, .diamond, .mythril, .emberOre, .voidOre, .crystalOre]

	static func key(_ t: Tile) -> String { return joinText("tile:", String(Int(t.rawValue))) }

	/// A host or neighbour key as a tile in a world (game tiles directly, mod blocks through the runtime)
	static func resolve(_ k: String, _ rt: ModRuntime) -> Tile? {
		if k.hasPrefix("tile:") {
			guard let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) else { return nil }
			return t
		}
		return rt.tileForKey[k]
	}

	static func name(_ k: String, _ p: ModPack) -> String {
		if k.hasPrefix("tile:") {
			if let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) { return t.name }
			return "Block"
		}
		let s: (String, String) = splitModKey(k)
		return p.blocks.first { $0.id == s.1 }?.name ?? k
	}
}

/// A picture of where an ore forms: a slice of a sample world (six chunks wide, from the sky to the
/// bottom), generated by the game's own world generator, with the ore marked
enum ModOrePreview {
	static let seed: UInt64 = 20_240_611
	static let chunks: Int = 6

	/// The picture (one pixel a block wide and two rows tall) and how many blocks of ore it holds
	static func render(_ o: ModOre, _ p: ModPack) -> (PixelBuf, Int) {
		let dim: Dimension = o.dim == 1 ? .umbral : .overworld
		let g = WorldGen(seed: seed, infinite: true, rareChance: 0.28)
		let marker: Tile = .amethystBlock
		var hosts: Set<UInt8> = []
		for k in o.hosts {
			if k.hasPrefix("tile:"), let n = Int(k.dropFirst(5)) { hosts.insert(UInt8(clampI(n, 0, 255))) }
		}
		var near: Tile? = nil
		if o.near.hasPrefix("tile:"), let n = Int(o.near.dropFirst(5)) { near = Tile(rawValue: UInt8(clampI(n, 0, 255))) }
		let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data((p.id + o.id).utf8)))
		let rtOre = ModOreRT(tile: marker, dim: o.dim, minY: o.minY, maxY: o.maxY, veins: o.veins, size: o.size, host: o.host, salt: salt,
							 place: o.place, biomes: Set(o.biomes), rarity: o.rarity, shape: o.shape, nearTile: near, hostTiles: hosts)
		let H: Int = dimHeight(dim)
		let rows: Int = (H + 1) / 2
		var b = PixelBuf(w: chunks * chunkW, h: rows)
		var count: Int = 0
		let ore: UInt32 = 0xFF40FF
		for c in 0..<chunks {
			let ch: Chunk = generateChunk(g, dim, c - chunks / 2)
			rtOre.place(g, ch)
			for lx in 0..<chunkW {
				let surf: Int = ch.surf[lx]
				for r in 0..<rows {
					let y0: Int = r * 2
					var col: UInt32 = 0
					var hit: Bool = false
					for y in y0..<min(H, y0 + 2) {
						let t: Tile = ch.get(lx, y)
						if t == marker { hit = true; count += 1 }
					}
					let t: Tile = ch.get(lx, y0)
					if hit {
						col = ore
					} else if t == .air {
						col = y0 < surf ? (dim == .umbral ? 0x2A1A3A : 0x7AB8F0) : 0x16161C
					} else if t == .water {
						col = 0x2E5FD0
					} else if t == .lava {
						col = 0xE8601A
					} else {
						col = shadeRGB(t.def.colors.first ?? 0x808080, 0.8)
					}
					b.set(c * chunkW + lx, r, col)
				}
			}
		}
		return (b, count)
	}
}

extension ModValidator {
	/// The ore controls kept in range; hosts and neighbours must be real blocks
	static func checkOrePlus(_ p: inout ModPack, _ mn: String, _ r: inout ModReport) {
		let own: Set<String> = Set(p.blocks.map { p.key($0.id) })
		let biomeRaws: Set<Int> = Set(ModBiomePicker.all.map { $0.rawValue })
		func validKey(_ k: String) -> Bool {
			if k.hasPrefix("tile:") {
				guard let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) else { return false }
				return !t.isMod && t != .air && t != .bedrock
			}
			return own.contains(k)
		}
		for i in p.ores.indices {
			var o: ModOre = p.ores[i]
			o.place = clampI(o.place, 0, 3)
			o.shape = clampI(o.shape, 0, 2)
			o.rarity = clampD(o.rarity.isFinite ? o.rarity : 1, 0.01, 1)
			o.biomes = Array(Set(o.biomes.filter { biomeRaws.contains($0) })).sorted()
			let hosts: [String] = o.hosts.filter { validKey($0) }
			if hosts.count != o.hosts.count { r.add(1, mn, joinText("Ore \u{201C}", o.name, "\u{201D}"), "A host block no longer exists and was taken off the list.") }
			o.hosts = Array(hosts.prefix(8))
			if !o.near.isEmpty && !validKey(o.near) {
				o.near = ""
				r.add(1, mn, joinText("Ore \u{201C}", o.name, "\u{201D}"), "The ore it formed next to no longer exists: it forms anywhere now.")
			}
			p.ores[i] = o
		}
	}
}

// MARK: - Mod Creator+: sprite tools

extension ModPixels {
	/// whether the game draws this picture with a dark outline (nil: the usual for what it is)
	func outlined(_ usual: Bool) -> Bool { return outline ?? usual }

	func flippedH() -> ModPixels {
		var o = ModPixels(w: w, h: h)
		o.outline = outline
		for y in 0..<h { for x in 0..<w { o.setARGB(w - 1 - x, y, argb(x, y)) } }
		return o
	}

	func flippedV() -> ModPixels {
		var o = ModPixels(w: w, h: h)
		o.outline = outline
		for y in 0..<h { for x in 0..<w { o.setARGB(x, h - 1 - y, argb(x, y)) } }
		return o
	}

	/// moved by a pixel or more, wrapping round the edges (nothing is lost)
	func shifted(_ dx: Int, _ dy: Int) -> ModPixels {
		var o = ModPixels(w: w, h: h)
		o.outline = outline
		for y in 0..<h {
			for x in 0..<w { o.setARGB(((x + dx) % w + w) % w, ((y + dy) % h + h) % h, argb(x, y)) }
		}
		return o
	}

	/// stretched or shrunk to a new size (each pixel copied from the nearest)
	func scaled(_ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		o.outline = outline
		for y in 0..<o.h {
			for x in 0..<o.w { o.setARGB(x, y, argb(x * w / max(1, o.w), y * h / max(1, o.h))) }
		}
		return o
	}

	/// a quarter turn clockwise (width and height swap)
	func rotated() -> ModPixels {
		var o = ModPixels(w: h, h: w)
		o.outline = outline
		for y in 0..<h { for x in 0..<w { o.setARGB(h - 1 - y, x, argb(x, y)) } }
		return o
	}

	/// A game picture fitted into this many pixels (nearest pixel, see-through kept)
	static func fitted(_ b: PixelBuf, _ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		for y in 0..<o.h {
			for x in 0..<o.w {
				let sx: Int = min(b.w - 1, x * b.w / max(1, o.w))
				let sy: Int = min(b.h - 1, y * b.h / max(1, o.h))
				o.setARGB(x, y, b.px[sy * b.w + sx])
			}
		}
		return o
	}

	/// A picture of any size squeezed into this many pixels by averaging (for pasted photos and
	/// drawings): `bytes` are RGBA, top row first
	static func fromRGBA(_ bytes: [UInt8], _ sw: Int, _ sh: Int, _ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		if sw <= 0 || sh <= 0 || bytes.count < sw * sh * 4 { return o }
		for y in 0..<o.h {
			for x in 0..<o.w {
				let x0: Int = x * sw / o.w
				let x1: Int = max(x0 + 1, (x + 1) * sw / o.w)
				let y0: Int = y * sh / o.h
				let y1: Int = max(y0 + 1, (y + 1) * sh / o.h)
				var r: Int = 0
				var g: Int = 0
				var b: Int = 0
				var a: Int = 0
				var n: Int = 0
				for yy in y0..<min(sh, y1) {
					for xx in x0..<min(sw, x1) {
						let i: Int = (yy * sw + xx) * 4
						let al: Int = Int(bytes[i + 3])
						r += Int(bytes[i]) * al
						g += Int(bytes[i + 1]) * al
						b += Int(bytes[i + 2]) * al
						a += al
						n += 1
					}
				}
				if n == 0 || a / n < 8 { continue }
				let rr: UInt32 = UInt32(clampI(r / max(1, a), 0, 255))
				let gg: UInt32 = UInt32(clampI(g / max(1, a), 0, 255))
				let bb: UInt32 = UInt32(clampI(b / max(1, a), 0, 255))
				let aa: UInt32 = UInt32(clampI(a / n, 0, 255))
				o.setARGB(x, y, (aa << 24) | (rr << 16) | (gg << 8) | bb)
			}
		}
		return o
	}

	/// The picture as a short text code, to copy between mods, worlds and iPads
	func spriteCode() -> String {
		return joinText("PRSPR1:", String(w), "x", String(h), ":", (outline ?? true) ? "o" : "n", ":", rgba.base64EncodedString())
	}

	/// A picture read back from its text code (nil: not a sprite code, or damaged)
	static func fromSpriteCode(_ code: String) -> ModPixels? {
		let parts: [Substring] = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
		if parts.count != 4 || parts[0] != "PRSPR1" { return nil }
		let wh: [Substring] = parts[1].split(separator: "x")
		guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]), w >= 1, h >= 1, w <= ModPixels.maxSide, h <= ModPixels.maxSide else { return nil }
		guard let data = Data(base64Encoded: String(parts[3])), data.count == w * h * 4 else { return nil }
		var p = ModPixels(w: w, h: h)
		p.rgba = data
		p.outline = parts[2] == "o"
		return p.valid ? p : nil
	}
}

/// Copying sprites in and out through the iPad's clipboard: as a text code (exact), or a picture
/// (any image copied from Photos or a drawing app, shrunk to the sprite's size)
enum SpriteClipboard {
	static func copy(_ p: ModPixels) {
		UIPasteboard.general.string = p.spriteCode()
	}

	static func pasteCode() -> ModPixels? {
		guard let s = UIPasteboard.general.string else { return nil }
		return ModPixels.fromSpriteCode(s)
	}

	/// The image on the clipboard shrunk to w x h pixels (nil: no image there)
	static func pasteImage(_ w: Int, _ h: Int) -> ModPixels? {
		guard let img = UIPasteboard.general.image, let cg = img.cgImage else { return nil }
		return pixels(cg, w, h)
	}

	/// A picture's pixels at its own size (capped at 256 on a side), then shrunk by averaging
	static func pixels(_ cg: CGImage, _ w: Int, _ h: Int) -> ModPixels? {
		let sw: Int = min(256, max(1, cg.width))
		let sh: Int = min(256, max(1, cg.height))
		var bytes: [UInt8] = [UInt8](repeating: 0, count: sw * sh * 4)
		let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
		let ok: Bool = bytes.withUnsafeMutableBytes { (bp: UnsafeMutableRawBufferPointer) -> Bool in
			guard let ctx = CGContext(data: bp.baseAddress, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			ctx.interpolationQuality = .medium
			ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))
			return true
		}
		if !ok { return nil }
		return ModPixels.fromRGBA(bytes, sw, sh, w, h)
	}
}

/// A sprite saved in the sprite library: finished or not, ready to use in any mod or as a reference
struct SpriteProject: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "Sprite"
	var frames: [ModPixels] = [ModPixels(w: 16, h: 16)]
	var edited: Double = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Sprite")
		var skip: Int = 0
		frames = c.list(.frames, &skip)
		if frames.isEmpty { frames = [ModPixels(w: 16, h: 16)] }
		edited = c.val(.edited, 0)
	}
}

/// The sprite library: sprites kept on this iPad apart from any mod
enum SpriteLibrary {
	static let maxSprites: Int = 120
	static var url: URL { return ModStore.dir.appendingPathComponent("sprites.json") }

	static func load() -> [SpriteProject] {
		guard let d = try? Data(contentsOf: url) else { return [] }
		let raw: [Lenient<SpriteProject>] = (try? JSONDecoder().decode([Lenient<SpriteProject>].self, from: d)) ?? []
		return raw.compactMap { $0.value }.filter { !$0.frames.isEmpty && $0.frames.allSatisfy { $0.valid } }
	}

	static func saveAll(_ list: [SpriteProject]) {
		guard let d = try? JSONEncoder().encode(Array(list.prefix(maxSprites))) else { return }
		try? d.write(to: url, options: .atomic)
	}

	/// Adds a sprite or replaces the one with its id; returns it as saved
	@discardableResult
	static func put(_ p0: SpriteProject) -> SpriteProject {
		var p: SpriteProject = p0
		if p.id.isEmpty { p.id = joinText("s", String(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000_000), String(Int.random(in: 10...99))) }
		if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = "Sprite" }
		p.name = String(p.name.prefix(32))
		p.frames = Array(p.frames.prefix(ModLimits.maxFrames)).filter { $0.valid }
		if p.frames.isEmpty { p.frames = [ModPixels(w: 16, h: 16)] }
		p.edited = Date().timeIntervalSince1970
		var list: [SpriteProject] = load()
		if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.insert(p, at: 0) }
		saveAll(list)
		return p
	}

	static func delete(_ id: String) {
		saveAll(load().filter { $0.id != id })
	}

	static func duplicate(_ id: String) -> SpriteProject? {
		guard var p = load().first(where: { $0.id == id }) else { return nil }
		p.id = ""
		p.name = String(joinText(p.name, " (copy)").prefix(32))
		return put(p)
	}
}

/// The game's own pictures, to use as a reference or a starting sample: creatures (each frame),
/// items and blocks
enum GameSprites {
	static func creatureFrames(_ k: MobKind) -> [PixelBuf] {
		return creatureArt(k, 0).0
	}

	static let creatures: [MobKind] = MobKind.allCases.filter { $0 != .custom && $0 != .villager }

	static func items() -> [Item] {
		return allGameItems().filter { if case .block = $0 { return false }; if case .wall = $0 { return false }; return true }
	}

	static func tiles() -> [Tile] {
		return Tile.allCases.filter { !$0.isMod && $0 != .air }
	}
}

// MARK: - Mod Creator+: custom infusions

/// When a custom infusion's effect is given to the player
enum ModInfuseTrigger: Int, Codable, CaseIterable {
	case none, onHit, onKill, whenHurt, lowHealth
	var name: String {
		switch self {
		case .none: return "Never"
		case .onHit: return "When it hits"
		case .onKill: return "When it fells a foe"
		case .whenHurt: return "When you are hurt"
		case .lowHealth: return "When your health is low"
		}
	}
}

/// An infusion made in the Mod Creator: what it goes on, the numbers it changes (added to, or
/// multiplied with, the others), what it does when it strikes or is struck, how it looks, and how
/// many times one item may hold it. Its compound is an item of the mod with the same key.
struct ModInfusion: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Infusion"
	var desc: String = ""
	/// its compound's icon (blank: a phial in its colour)
	var icon: ModPixels = ModPixels(w: 12, h: 12)
	var color: UInt32 = 0x60E0FF
	/// Rarity number (basic to boss relic)
	var rarity: Int = 1
	/// the kinds of equipment it goes on (InfuseClass numbers)
	var classes: [Int] = [InfuseClass.melee.rawValue]
	/// only these items (empty: anything of those kinds)
	var items: [Item] = []
	/// percentages multiply with the others (off: they add)
	var multiply: Bool = false
	var damagePct: Double = 0
	var damageFlat: Double = 0
	var attackSpeedPct: Double = 0
	var reach: Double = 0
	var critPct: Double = 0
	var knockPct: Double = 0
	var miningPct: Double = 0
	var defense: Double = 0
	var moveSpeedPct: Double = 0
	var fireCut: Double = 0
	var coldCut: Double = 0
	var stormCut: Double = 0
	/// health a minute while worn
	var regen: Double = 0
	/// less energy used by suit parts (percent)
	var energyPct: Double = 0
	/// on a hit: seconds of fire, seconds of slowing, seconds of poison
	var burn: Double = 0
	var slow: Double = 0
	var poison: Double = 0
	/// on a hit: the chance of a spark leaping to two more foes
	var sparkChance: Double = 0
	/// on a hit: a little blast of this much damage around what was hit
	var blast: Double = 0
	/// worn: the share of a melee blow returned to the attacker (percent)
	var thorns: Double = 0
	/// on a hit: the share of the damage healed back (percent)
	var lifeSteal: Double = 0
	var trigger: ModInfuseTrigger = .none
	var effect: ModEffect = ModEffect(.speed, 20, 8)
	var effectCooldown: Double = 10
	/// sparks of its colour when it does something
	var particles: Bool = true
	/// times one item may hold it
	var stack: Int = 1

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Infusion")
		desc = c.val(.desc, "")
		icon = c.val(.icon, ModPixels(w: 12, h: 12))
		color = c.val(.color, 0x60E0FF)
		rarity = c.val(.rarity, 1)
		classes = c.val(.classes, [0])
		items = c.val(.items, [])
		multiply = c.val(.multiply, false)
		damagePct = c.val(.damagePct, 0)
		damageFlat = c.val(.damageFlat, 0)
		attackSpeedPct = c.val(.attackSpeedPct, 0)
		reach = c.val(.reach, 0)
		critPct = c.val(.critPct, 0)
		knockPct = c.val(.knockPct, 0)
		miningPct = c.val(.miningPct, 0)
		defense = c.val(.defense, 0)
		moveSpeedPct = c.val(.moveSpeedPct, 0)
		fireCut = c.val(.fireCut, 0)
		coldCut = c.val(.coldCut, 0)
		stormCut = c.val(.stormCut, 0)
		regen = c.val(.regen, 0)
		energyPct = c.val(.energyPct, 0)
		burn = c.val(.burn, 0)
		slow = c.val(.slow, 0)
		poison = c.val(.poison, 0)
		sparkChance = c.val(.sparkChance, 0)
		blast = c.val(.blast, 0)
		thorns = c.val(.thorns, 0)
		lifeSteal = c.val(.lifeSteal, 0)
		trigger = c.val(.trigger, .none)
		effect = c.val(.effect, ModEffect(.speed, 20, 8))
		effectCooldown = c.val(.effectCooldown, 10)
		particles = c.val(.particles, true)
		stack = c.val(.stack, 1)
	}

	/// what it does, in a line (for tooltips and the crucible)
	var blurb: String {
		var parts: [String] = []
		func pct(_ v: Double, _ what: String) { if abs(v) > 0.01 { parts.append(joinText(v > 0 ? "+" : "", String(Int(v.rounded())), "% ", what)) } }
		pct(damagePct, "damage")
		if abs(damageFlat) > 0.01 { parts.append(joinText("+", String(format: "%.1f", damageFlat), " damage")) }
		pct(attackSpeedPct, "attack speed")
		if reach > 0.01 { parts.append(joinText("+", String(format: "%.1f", reach), " reach")) }
		pct(critPct, "critical chance")
		pct(knockPct, "knockback")
		pct(miningPct, "mining speed")
		if defense > 0.01 { parts.append(joinText("+", String(format: "%.1f", defense), " defence")) }
		pct(moveSpeedPct, "run speed")
		pct(fireCut, "less fire harm")
		pct(coldCut, "less cold")
		pct(stormCut, "less storm harm")
		if regen > 0.01 { parts.append(joinText("heals ", String(format: "%.1f", regen), " a minute")) }
		pct(energyPct, "less suit energy")
		if burn > 0.01 { parts.append("sets alight") }
		if slow > 0.01 { parts.append("slows") }
		if poison > 0.01 { parts.append("poisons") }
		if sparkChance > 0.01 { parts.append("sparks") }
		if blast > 0.01 { parts.append("bursts") }
		pct(thorns, "of blows returned")
		pct(lifeSteal, "of damage healed")
		if trigger != .none { parts.append(joinText(effect.kind.short.lowercased(), " ", trigger.name.lowercased())) }
		return parts.isEmpty ? "No effect yet" : parts.joined(separator: ", ")
	}
}

extension ModInfusion {
	/// Its numbers on a melee profile (percentages of the profile it is given, added or multiplied)
	func apply(_ p0: MeleeProfile) -> MeleeProfile {
		var p: MeleeProfile = p0
		if multiply {
			p.damage *= 1.0 + damagePct / 100.0
			p.cooldown /= max(0.2, 1.0 + attackSpeedPct / 100.0)
			p.knock *= 1.0 + knockPct / 100.0
			p.critChance *= 1.0 + critPct / 100.0
		} else {
			p.damage += p0.damage * damagePct / 100.0
			p.cooldown = max(0.08, p.cooldown - p0.cooldown * attackSpeedPct / 100.0)
			p.knock += p0.knock * knockPct / 100.0
			p.critChance += critPct / 100.0
		}
		p.damage += damageFlat
		p.reach += reach
		p.critChance = clampD(p.critChance, 0, 1)
		if burn > 0 { p.burn = max(p.burn, burn) }
		return p
	}
}

/// A custom infusion in a world: its number on items, its key, and what it goes on
final class ModInfusionRT {
	let key: String
	let number: Int
	let def: ModInfusion
	let classes: Set<Int>
	let items: Set<Item>

	init(key: String, number: Int, def: ModInfusion) {
		self.key = key
		self.number = number
		self.def = def
		self.classes = Set(def.classes)
		self.items = Set(def.items)
	}

	/// the share a percentage adds (or the factor it multiplies by)
	func factor(_ pct: Double) -> Double { return 1.0 + pct / 100.0 }
}

/// Custom infusions are numbered from here on items (the game's own use 0 to 999)
let customInfusionBase: Int = 1000
let maxCustomInfusions: Int = 256

extension ModRuntime {
	/// Gives each custom infusion its number (the world's own numbers first, so items keep theirs) and
	/// makes its compound an item of the mod
	func buildInfusions(_ world: ModWorldInfo?) {
		var taken: Set<Int> = []
		if let w = world {
			for (k, n) in w.infusions where n >= customInfusionBase && n < customInfusionBase + maxCustomInfusions {
				infusionNumber[k] = n
				taken.insert(n)
			}
		}
		var next: Int = customInfusionBase
		for p in packs {
			for f in p.infusions where !disabled.contains(p.key(f.id)) {
				let k: String = p.key(f.id)
				var n: Int = infusionNumber[k] ?? -1
				if n < 0 {
					while taken.contains(next) { next += 1 }
					if next >= customInfusionBase + maxCustomInfusions { continue }
					n = next
					taken.insert(n)
					infusionNumber[k] = n
				}
				infusionDefs[n] = ModInfusionRT(key: k, number: n, def: f)
				// its compound: an item of the mod under the same key
				var it = ModItem()
				it.id = f.id
				it.name = joinText(f.name, " Compound")
				it.desc = joinText("Work it into equipment at an Infusion Crucible: ", f.blurb)
				it.kind = .material
				it.stack = 10
				it.rarity = clampI(f.rarity, 0, 4)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				r.icon = compoundIcon(f)
				items[k] = r
				itemOrder.append(k)
			}
		}
	}

	func infusion(_ n: Int) -> ModInfusionRT? { return infusionDefs[n] }

	/// The compound's icon: its own picture, or a phial in its colour
	func compoundIcon(_ f: ModInfusion) -> PixelBuf {
		if !f.icon.isBlank {
			var b: PixelBuf = padBuf(f.icon.buf())
			if f.icon.outlined(true) { b.outline(0x1A1410) }
			return b
		}
		var b = PixelBuf(w: 12, h: 12)
		let c: UInt32 = f.color & 0xFFFFFF
		let ring: UInt32 = (Rarity(rawValue: clampI(f.rarity, 0, 4)) ?? .uncommon).color
		b.rect(5, 0, 2, 2, 0x6A6E78)
		b.rect(4, 2, 4, 1, ring)
		b.rect(3, 3, 6, 7, 0x2A2A34)
		b.rect(4, 4, 4, 5, c)
		b.set(4, 4, shadeRGB(c, 1.4))
		b.set(6, 6, shadeRGB(c, 0.6))
		b.rect(3, 10, 6, 1, ring)
		b.outline(0x1A1410)
		return b
	}
}

/// The name and colour of any infusion number (the game's own or a custom one)
func infusionName(_ n: Int) -> String {
	if let i = Infusion(rawValue: n) { return i.name }
	return ModRuntime.shared.infusion(n)?.def.name ?? "Missing infusion"
}

func infusionColor(_ n: Int) -> UInt32 {
	if let i = Infusion(rawValue: n) { return i.color }
	return ModRuntime.shared.infusion(n)?.def.color ?? 0xFF00FF
}

extension Stack {
	/// names of everything worked into it, custom infusions too
	var infusionNames: [String] { return (inf ?? []).map { infusionName($0) } }

	/// Why a custom infusion can't go on this item (nil: it can)
	func customProblem(_ r: ModInfusionRT) -> String? {
		let slots: Int = infusionSlots(item)
		if slots <= 0 { return "This can't be infused." }
		if item.maxStack > 1 { return "Only single items can be infused." }
		if !r.items.isEmpty {
			if !r.items.contains(item) { return joinText(r.def.name, " only goes on certain items.") }
		} else {
			let cls: [InfuseClass] = infuseClasses(item)
			if !cls.contains(where: { r.classes.contains($0.rawValue) }) { return joinText(r.def.name, " doesn't go on this kind of equipment.") }
		}
		let held: Int = (inf ?? []).filter { $0 == r.number }.count
		if held >= max(1, r.def.stack) { return r.def.stack > 1 ? joinText("It already holds ", r.def.name, " as many times as it can.") : joinText("It already has ", r.def.name, ".") }
		if (inf?.count ?? 0) >= slots { return joinText("All ", String(slots), " of its slots are taken.") }
		return nil
	}
}

extension Game {
	/// Works a custom infusion's compound into the item in a bag slot (checked again here, the item
	/// never leaves its slot)
	@discardableResult
	func infuseCustom(slot i: Int, _ number: Int) -> String {
		guard let r = ModRuntime.shared.infusion(number) else { return "That infusion's mod is not on." }
		guard i >= 0 && i < inv.slots.count, var s = inv.slots[i] else { return "That item is gone." }
		if let why = s.customProblem(r) { return why }
		let compound: Item = .custom(r.key)
		if !isCreative && inv.total(compound) < 1 { return joinText("You need a ", r.def.name, " compound.") }
		if !isCreative { _ = inv.remove(compound, 1) }
		var list: [Int] = s.inf ?? []
		list.append(number)
		s.inf = list
		inv.slots[i] = s
		sfx(.infuse, 0.8)
		spawnParticles(pb.x, pb.y - 1.2, r.def.color, 12, 3.0, 0.7, -4)
		bumpHUD()
		return joinText(s.item.name, " now holds ", r.def.name, ".")
	}

	/// Takes one custom infusion back out of an item (the compound is spent; the item is unharmed)
	@discardableResult
	func removeCustomInfusion(slot i: Int, _ number: Int) -> String {
		guard i >= 0 && i < inv.slots.count, var s = inv.slots[i], var list = s.inf, let k = list.firstIndex(of: number) else { return "Nothing to remove." }
		list.remove(at: k)
		s.inf = list.isEmpty ? nil : list
		inv.slots[i] = s
		sfx(.tap, 0.6)
		bumpHUD()
		return joinText(infusionName(number), " was drawn out of ", s.item.name, ".")
	}

	/// A custom infusion's numbers on a melee profile
	static func customProfile(_ p0: MeleeProfile, _ n: Int) -> MeleeProfile {
		guard let r = ModRuntime.shared.infusion(n) else { return p0 }
		return r.def.apply(p0)
	}

	/// What a custom infusion does when a blow or a shot lands on a creature
	func customHit(_ m: Mob, _ n: Int, _ dmg: Double, _ x: Double, _ y: Double) {
		guard let r = ModRuntime.shared.infusion(n) else { return }
		let d: ModInfusion = r.def
		if m.hp > 0 {
			if d.burn > 0 && !heatImmune(m) { m.burn = max(m.burn, d.burn) }
			if d.slow > 0 {
				m.slowT = max(m.slowT, m.isBoss ? d.slow * 0.5 : d.slow)
				m.slowAmt = max(m.slowAmt, m.isBoss ? 0.2 : 0.4)
			}
			if d.poison > 0 && !poisonImmune(m) {
				m.poisonT = max(m.poisonT, m.isBoss ? d.poison * 0.5 : d.poison)
				m.poisonDps = max(m.poisonDps, 1.0)
				m.poisonByPlayer = true
			}
			if d.sparkChance > 0 && Double.random(in: 0...1) < d.sparkChance { stormSpark(m) }
		}
		if d.blast > 0 { customBlast(x, y, d.blast, d.color) }
		if d.lifeSteal > 0 && !dead { heal(dmg * d.lifeSteal / 100.0) }
		if d.particles { spawnParticles(m.b.x, m.b.cy, d.color, 3, 2.0, 0.3, 4) }
		if d.trigger == .onHit || (d.trigger == .onKill && m.hp <= 0) { customTrigger(r) }
	}

	/// A custom infusion's little blast (hurts creatures close by, breaks nothing)
	func customBlast(_ x: Double, _ y: Double, _ dmg: Double, _ color: UInt32) {
		var info = DamageInfo(amount: dmg, type: .explosion, source: .player)
		info.knock = 4
		info.key = newID()
		info.cooldown = 0.5
		for m in mobsNear(x - 2.5, x + 2.5) where m.hp > 0 && !m.removed && !m.tame {
			if boxDistance(x, y, m.b.left, m.b.top, m.b.right, m.b.y) <= 1.3 {
				var i2: DamageInfo = info
				i2.originX = x
				i2.originY = y
				applyMobDamage(m, i2)
			}
		}
		spawnParticles(x, y, color, 8, 4.0, 0.3, 4)
	}

	/// Gives a custom infusion's effect to the player, no more often than its rest allows
	func customTrigger(_ r: ModInfusionRT) {
		let d: ModInfusion = r.def
		if d.trigger == .none { return }
		if let t = infTriggerCD[r.number], clock - t < d.effectCooldown { return }
		infTriggerCD[r.number] = clock
		applyEffects([d.effect])
		floatText(d.effect.kind.short, pb.x, pb.y - pb.h - 0.4, d.color)
	}

	/// After the player is hurt: worn custom infusions that answer being hurt (or low health)
	func customHurtTriggers() {
		for i in 0..<min(3, inv.armor.count) {
			guard let s = inv.armor[i], let l = s.inf else { continue }
			for n in l where n >= customInfusionBase {
				guard let r = ModRuntime.shared.infusion(n) else { continue }
				if r.def.trigger == .whenHurt || (r.def.trigger == .lowHealth && hp > 0 && hp < maxHP * 0.3) { customTrigger(r) }
			}
		}
	}

	/// A shot's custom infusions (worked out when it is fired)
	func customShot(_ p: inout Projectile, _ l: [Int]) {
		for n in l where n >= customInfusionBase {
			guard let r = ModRuntime.shared.infusion(n) else { continue }
			let d: ModInfusion = r.def
			p.dmg = d.multiply ? p.dmg * r.factor(d.damagePct) : p.dmg + p.dmg * d.damagePct / 100.0
			p.dmg += d.damageFlat
			if d.reach > 0 { p.life *= 1.0 + d.reach * 0.1 }
			p.custom.append(n)
		}
	}

	/// The held tool's custom mining infusions
	func customMining(_ s: Stack) -> Double {
		var m: Double = 1.0
		for n in s.inf ?? [] where n >= customInfusionBase {
			guard let r = ModRuntime.shared.infusion(n) else { continue }
			m *= r.factor(r.def.miningPct)
		}
		return m
	}
}

extension ArmorInf {
	/// A worn custom infusion's numbers
	mutating func addCustom(_ n: Int) {
		guard let r = ModRuntime.shared.infusion(n) else { return }
		let d: ModInfusion = r.def
		defense += d.defense
		fireCut = min(0.8, fireCut + d.fireCut / 100.0)
		coldCut = min(0.9, coldCut + d.coldCut / 100.0)
		stormCut = min(0.8, stormCut + d.stormCut / 100.0)
		speed = min(0.4, speed + d.moveSpeedPct / 100.0)
		regen = min(1.0, regen + d.regen / 60.0)
		thorns = min(0.6, thorns + d.thorns / 100.0)
	}
}

/// Less energy for suit parts holding custom infusions that save it
func customEnergyMul(_ s: Stack) -> Double {
	var m: Double = 1.0
	for n in s.inf ?? [] where n >= customInfusionBase {
		if let r = ModRuntime.shared.infusion(n) { m *= max(0.3, 1.0 - r.def.energyPct / 100.0) }
	}
	return m
}

extension ModValidator {
	/// Custom infusions: numbers in range, kinds and items real, ids not shared with items
	static func checkInfusions(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		if p.infusions.count > 24 {
			r.add(1, mn, "Mod", "Only 24 infusions fit in one mod; the rest were left out.")
			p.infusions = Array(p.infusions.prefix(24))
		}
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.projectiles.map { $0.id } + p.loot.map { $0.id })
		let mx: Double = sb ? 400 : 100
		for i in p.infusions.indices {
			var f: ModInfusion = p.infusions[i]
			if f.id.isEmpty || used.contains(f.id) { f.id = joinText("inf", String(i + 1), "x", String(used.count)) }
			used.insert(f.id)
			if f.name.trimmingCharacters(in: .whitespaces).isEmpty { f.name = "Infusion" }
			f.name = String(f.name.prefix(32))
			f.desc = String(f.desc.prefix(200))
			if !f.icon.valid { f.icon = ModPixels(w: 12, h: 12) }
			f.rarity = clampI(f.rarity, 0, 4)
			f.classes = Array(Set(f.classes.filter { $0 >= 0 && $0 <= 4 })).sorted()
			if f.classes.isEmpty && f.items.isEmpty { f.classes = [0] }
			f.items = Array(f.items.filter { it in
				if case .custom(let k) = it { return known[k] != nil || p.items.contains { p.key($0.id) == k } }
				return infusionSlots(it) > 0
			}.prefix(12))
			func c(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return clampD(v.isFinite ? v : 0, lo, hi) }
			f.damagePct = c(f.damagePct, -50, mx)
			f.damageFlat = c(f.damageFlat, 0, sb ? 100 : 20)
			f.attackSpeedPct = c(f.attackSpeedPct, -50, 60)
			f.reach = c(f.reach, 0, sb ? 4 : 1.5)
			f.critPct = c(f.critPct, 0, sb ? 100 : 40)
			f.knockPct = c(f.knockPct, -80, mx)
			f.miningPct = c(f.miningPct, 0, mx)
			f.defense = c(f.defense, 0, sb ? 20 : 4)
			f.moveSpeedPct = c(f.moveSpeedPct, 0, sb ? 50 : 15)
			f.fireCut = c(f.fireCut, 0, 60)
			f.coldCut = c(f.coldCut, 0, 75)
			f.stormCut = c(f.stormCut, 0, 60)
			f.regen = c(f.regen, 0, sb ? 60 : 12)
			f.energyPct = c(f.energyPct, 0, 50)
			f.burn = c(f.burn, 0, 8)
			f.slow = c(f.slow, 0, 8)
			f.poison = c(f.poison, 0, 10)
			f.sparkChance = c(f.sparkChance, 0, sb ? 1 : 0.4)
			f.blast = c(f.blast, 0, sb ? 40 : 8)
			f.thorns = c(f.thorns, 0, 40)
			f.lifeSteal = c(f.lifeSteal, 0, sb ? 50 : 15)
			f.effect.amount = f.effect.kind.amountRange.clamp(f.effect.amount, sb)
			f.effect.seconds = ModRange.seconds.clamp(f.effect.seconds, sb)
			f.effectCooldown = c(f.effectCooldown, 2, 300)
			f.stack = clampI(f.stack, 1, 3)
			p.infusions[i] = f
		}
	}
}

// MARK: - Mod Creator+: boss phases and summoning

/// What moves a creature on to its next phase
enum ModPhaseWhen: Int, Codable, CaseIterable {
	case health, time, helpersGone
	var name: String {
		switch self {
		case .health: return "Health falls below"
		case .time: return "After fighting for"
		case .helpersGone: return "Its helpers are beaten"
		}
	}
	var help: String {
		switch self {
		case .health: return "Begins when its health drops under this share of the most it has."
		case .time: return "Begins once the fight has gone on this long."
		case .helpersGone: return "Begins when every helper an earlier phase called is beaten."
		}
	}
}

/// One stage of a fight: when it begins, and how the creature changes for the rest of the fight.
/// Phases follow one another in order; each lasts until the next begins.
struct ModPhase: Codable, Equatable {
	var name: String = "Phase"
	var when: ModPhaseWhen = .health
	/// a share of its health (health phases) or seconds (time phases)
	var value: Double = 0.5
	var speedMul: Double = 1.2
	var damageMul: Double = 1.2
	/// how long its attacks rest between uses, as a share of their own rest
	var cooldownMul: Double = 0.8
	/// a share of every hit it shrugs off (on top of its own toughness)
	var defense: Double = 0
	/// the attacks it may use in this phase (their numbers; empty: all of them)
	var attacks: [Int] = []
	var tint: UInt32 = 0xFF4030
	var tintAmt: Double = 0.25
	/// share of its health healed as the phase begins
	var heal: Double = 0
	/// seconds it can't be hurt while it changes
	var shield: Double = 1.0
	/// helpers it calls: a creature ("mod:id" or a game creature's name) and how many
	var helper: String = ""
	var helpers: Int = 0
	var message: String = ""
	var roar: Bool = true

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = c.val(.name, "Phase")
		when = c.val(.when, .health)
		value = c.val(.value, 0.5)
		speedMul = c.val(.speedMul, 1.2)
		damageMul = c.val(.damageMul, 1.2)
		cooldownMul = c.val(.cooldownMul, 0.8)
		defense = c.val(.defense, 0)
		attacks = c.val(.attacks, [])
		tint = c.val(.tint, 0xFF4030)
		tintAmt = c.val(.tintAmt, 0.25)
		heal = c.val(.heal, 0)
		shield = c.val(.shield, 1.0)
		helper = c.val(.helper, "")
		helpers = c.val(.helpers, 0)
		message = c.val(.message, "")
		roar = c.val(.roar, true)
	}

	/// when it begins, in words
	var whenText: String {
		switch when {
		case .health: return joinText("below ", String(Int((value * 100).rounded())), "% health")
		case .time: return joinText("after ", String(Int(value.rounded())), " s of fighting")
		case .helpersGone: return "when its helpers are beaten"
		}
	}
}

/// How a summoning is started
enum ModSummonHow: Int, Codable, CaseIterable {
	case useItem, itemOnPattern, buildPattern
	var name: String {
		switch self {
		case .useItem: return "Use an item"
		case .itemOnPattern: return "Use an item on a shape"
		case .buildPattern: return "Finish building a shape"
		}
	}
	var help: String {
		switch self {
		case .useItem: return "Tap with the item in hand, where the conditions are right."
		case .itemOnPattern: return "Build the shape, then tap one of its blocks with the item in hand."
		case .buildPattern: return "Placing the last block of the shape calls the creature."
		}
	}
}

/// A shape of blocks for a summoning, top row first. A cell is "" (anything), "air" (must be empty),
/// or a block ("tile:<number>" for the game's own, "mod:id" for a mod's).
struct ModPattern: Codable, Equatable {
	static let maxSide: Int = 7
	var w: Int = 3
	var h: Int = 3
	var cells: [String] = [String](repeating: "", count: 9)

	init() {}
	init(w: Int, h: Int) {
		self.w = clampI(w, 1, ModPattern.maxSide)
		self.h = clampI(h, 1, ModPattern.maxSide)
		cells = [String](repeating: "", count: self.w * self.h)
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		w = c.val(.w, 3)
		h = c.val(.h, 3)
		cells = c.val(.cells, [])
	}

	func cell(_ x: Int, _ y: Int) -> String {
		if x < 0 || y < 0 || x >= w || y >= h { return "" }
		let i: Int = y * w + x
		return i < cells.count ? cells[i] : ""
	}

	mutating func set(_ x: Int, _ y: Int, _ k: String) {
		if x < 0 || y < 0 || x >= w || y >= h { return }
		while cells.count < w * h { cells.append("") }
		cells[y * w + x] = k
	}

	/// The same shape in a new size (what fits is kept, from the top left)
	func resized(_ nw: Int, _ nh: Int) -> ModPattern {
		var o = ModPattern(w: nw, h: nh)
		for y in 0..<o.h { for x in 0..<o.w { o.set(x, y, cell(x, y)) } }
		return o
	}

	/// cells that need a block
	var blockCells: Int { return cells.filter { !$0.isEmpty && $0 != "air" }.count }
}

/// A way to call a creature into the world: what the player does, the item and shape it takes, and
/// where and when it works. Every condition set must hold at once.
struct ModSummon: Codable, Equatable {
	var enabled: Bool = true
	var how: ModSummonHow = .useItem
	var item: Item? = nil
	var consume: Bool = true
	var pattern: ModPattern = ModPattern()
	/// the shape's blocks are used up when the creature comes
	var clearPattern: Bool = true
	/// Biome numbers (empty: any)
	var biomes: [Int] = []
	/// Dimension numbers (empty: any)
	var dims: [Int] = []
	/// 0 any time, 1 by day, 2 at night
	var time: Int = 0
	/// 0 any, 1 clear, 2 rain or snow, 3 thunderstorm, 4 snowfall
	var weather: Int = 0
	/// 0 anywhere, 1 under the open sky, 2 underground
	var place: Int = 0
	/// 0 right there (on the shape, or beside the player), 1 a little way off
	var appear: Int = 0
	var message: String = ""
	/// custom dimensions it works in ("mod:id"; with `dims`, any of them)
	var dimKeys: [String] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		enabled = c.val(.enabled, true)
		how = c.val(.how, .useItem)
		item = c.val(.item, nil)
		consume = c.val(.consume, true)
		pattern = c.val(.pattern, ModPattern())
		clearPattern = c.val(.clearPattern, true)
		biomes = c.val(.biomes, [])
		dims = c.val(.dims, [])
		time = c.val(.time, 0)
		weather = c.val(.weather, 0)
		place = c.val(.place, 0)
		appear = c.val(.appear, 0)
		message = c.val(.message, "")
		dimKeys = c.val(.dimKeys, [])
	}

	var usesItem: Bool { return how != .buildPattern }
	var usesPattern: Bool { return how != .useItem }
}

/// Words for the summoning settings (the editor and the messages in play use the same ones)
enum ModSummonText {
	static let times: [String] = ["Any time", "By day", "At night"]
	static let weathers: [String] = ["Any weather", "Clear skies", "Rain or snow", "Thunderstorm", "Snowfall"]
	static let places: [String] = ["Anywhere", "Open sky", "Underground"]
	static let appears: [String] = ["Right there", "A little way off"]
	static let timeWords: [String] = ["", "by day", "at night"]
	static let weatherWords: [String] = ["", "under clear skies", "in rain or snow", "in a thunderstorm", "while snow falls"]
	static let placeWords: [String] = ["", "under the open sky", "underground"]

	static func dimName(_ n: Int) -> String {
		switch n {
		case 0: return "the Overworld"
		case 1: return "the Umbral Realm"
		default: return "another dimension"
		}
	}

	static func biomeName(_ n: Int) -> String { return Biome(rawValue: n)?.name ?? "?" }

	/// "Hold Ember Totem and tap, at night, in Desert" (what the player needs to do)
	static func describe(_ s: ModSummon, _ itemName: String) -> String {
		var parts: [String] = []
		switch s.how {
		case .useItem: parts.append(joinText("Tap with ", itemName, " in hand"))
		case .itemOnPattern: parts.append(joinText("Build the shape, then tap it with ", itemName))
		case .buildPattern: parts.append("Finish building the shape")
		}
		if s.time > 0 && s.time < timeWords.count { parts.append(timeWords[s.time]) }
		if s.weather > 0 && s.weather < weatherWords.count { parts.append(weatherWords[s.weather]) }
		if s.place > 0 && s.place < placeWords.count { parts.append(placeWords[s.place]) }
		if !s.biomes.isEmpty { parts.append(joinText("in ", s.biomes.map { biomeName($0) }.joined(separator: " or "))) }
		if !s.dims.isEmpty { parts.append(joinText("in ", s.dims.map { dimName($0) }.joined(separator: " or "))) }
		return parts.joined(separator: ", ")
	}
}

/// A summoning ready for play: its creature, its item, and its shape as this world's blocks
final class ModSummonRT {
	let slot: Int
	let key: String
	let def: ModSummon
	/// the shape's cells that matter: across and down from its top left, and the block (nil: empty)
	let cells: [(Int, Int, Tile?)]
	/// a custom dimension's way in (its slot), instead of a creature (-1)
	let dimSlot: Int

	init(slot: Int, key: String, def: ModSummon, cells: [(Int, Int, Tile?)], dimSlot: Int = -1) {
		self.slot = slot
		self.key = key
		self.def = def
		self.cells = cells
		self.dimSlot = dimSlot
	}

	/// The top left of a finished shape that takes in the block at (x, y) (nil: there is none)
	func shapeAt(_ w: World, _ x: Int, _ y: Int) -> (Int, Int)? {
		let here: Tile = w.tile(x, y)
		if here == .air { return nil }
		for c in cells {
			guard let t = c.2, t == here else { continue }
			let ox: Int = x - c.0
			let oy: Int = y - c.1
			var ok: Bool = true
			for d in cells {
				let tt: Tile = w.tile(ox + d.0, oy + d.1)
				if let need = d.2 {
					if tt != need { ok = false; break }
				} else if tt != .air {
					ok = false
					break
				}
			}
			if ok { return (ox, oy) }
		}
		return nil
	}
}

extension ModRuntime {
	/// Every summoning of every custom creature, with its shape turned into this world's blocks (one
	/// whose item or blocks are missing is left out)
	func buildSummons() {
		summons = []
		for (i, r) in mobs.enumerated() {
			for s in r.def.summons where s.enabled {
				var cells: [(Int, Int, Tile?)] = []
				var bad: Bool = false
				if s.usesPattern {
					for y in 0..<s.pattern.h {
						for x in 0..<s.pattern.w {
							let k: String = s.pattern.cell(x, y)
							if k.isEmpty { continue }
							if k == "air" {
								cells.append((x, y, nil))
								continue
							}
							guard let t = ModGround.resolve(k, self), t != .air else {
								bad = true
								continue
							}
							cells.append((x, y, t))
						}
					}
					if bad || !cells.contains(where: { $0.2 != nil }) { continue }
				}
				if s.usesItem && s.item == nil { continue }
				summons.append(ModSummonRT(slot: i, key: r.key, def: s, cells: cells))
			}
		}
	}
}

/// A summoned creature still about when the world was saved (it comes back where it was)
struct ModBossSave: Codable {
	var key: String
	var x: Double
	var y: Double
	var hp: Double
	var phase: Int
	var fightT: Double
}

extension Game {
	// MARK: phases

	/// A custom creature's fight: the time it has been fighting, and the next phase when its moment
	/// comes (one at a time, in order)
	func stepPhases(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if m.phaseShield > 0 { m.phaseShield -= dt }
		let ph: [ModPhase] = r.def.phases
		if ph.isEmpty { return }
		if m.ai == .chase || m.ai == .alert || m.st >= 3 || clock - m.lastHitByPlayer < 8.0 { m.fightT += dt }
		if m.mphase >= ph.count { return }
		let p: ModPhase = ph[m.mphase]
		var go: Bool = false
		switch p.when {
		case .health: go = m.hp < m.maxHP * p.value
		case .time: go = m.fightT >= p.value
		case .helpersGone: go = m.helpersCalled > 0 && helpersAlive(m) == 0
		}
		if go { enterPhase(m, r, m.mphase, quiet: false) }
	}

	/// Starts phase k: its numbers from now on, and (unless quiet, as when a saved fight comes back) its
	/// healing, shield, message, roar and helpers
	func enterPhase(_ m: Mob, _ r: ModMobRT, _ k: Int, quiet: Bool) {
		guard k >= 0 && k < r.def.phases.count else { return }
		let p: ModPhase = r.def.phases[k]
		m.mphase = k + 1
		m.phaseSpeed = p.speedMul
		m.phaseDmg = p.damageMul
		m.phaseCD = p.cooldownMul
		m.phaseDef = p.defense
		if quiet { return }
		if p.heal > 0 { m.hp = min(m.maxHP, m.hp + m.maxHP * p.heal) }
		m.phaseShield = p.shield
		if !p.message.isEmpty { say(p.message, 3.0) }
		if p.roar {
			sfx(.roar, at: m.b.x, 0.9)
			addShake(0.3)
		}
		spawnParticles(m.b.x, m.b.cy, p.tint, 20, 6.0, 0.8, 0)
		if p.helpers > 0 && !p.helper.isEmpty { callHelpers(m, p) }
		if !logicRT.isEmpty { fireLogic(.phase, mob: m, key: r.key, number: Double(k + 1)) }
		bumpHUD()
	}

	/// Helpers called by a creature that are still standing
	func helpersAlive(_ m: Mob) -> Int {
		var n: Int = 0
		for o in mobs where o.helperOf == m.id && o.hp > 0 && !o.removed { n += 1 }
		return n
	}

	/// The helpers a phase calls: they appear on either side of the creature, where there is room
	func callHelpers(_ m: Mob, _ p: ModPhase) {
		let rt: ModRuntime = ModRuntime.shared
		let slot: Int? = rt.mobSlot[p.helper]
		var kind: MobKind? = nil
		if slot == nil { kind = MobKind.allCases.first { $0 != .custom && $0 != .villager && mobDef($0).name == p.helper } }
		var hw: Double = 0.6
		var hh: Double = 1.8
		if let s = slot, let hr = rt.mob(s) {
			hw = hr.mdef.w
			hh = hr.mdef.h
		} else if let k = kind {
			hw = mobDef(k).w
			hh = mobDef(k).h
		} else {
			return
		}
		var n: Int = 0
		var i: Int = 0
		while i < p.helpers * 3 && n < p.helpers {
			let side: Double = i % 2 == 0 ? 1.0 : -1.0
			let x: Double = m.b.x + side * (m.b.w * 0.5 + 1.5 + Double(i / 2) * (hw + 0.8))
			i += 1
			guard let y = roomNear(x, m.b.y, hw, hh) else { continue }
			var made: Mob? = nil
			if let s = slot { made = addCustomMob(s, x, y) } else if let k = kind { made = addMob(k, x, y) }
			guard let h = made else { break }
			h.helperOf = m.id
			h.lastHitByPlayer = clock
			spawnParticles(x, y - hh * 0.5, p.tint, 8, 3.0, 0.5, 0)
			n += 1
		}
		m.helpersCalled += n
	}

	/// Feet height near (x, y) where a body this big fits without touching blocks (nil: no room)
	func roomNear(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Double? {
		let tries: [Double] = [0, -1, -2, 1, -3, -4, 2, -5, -6, -8, -10]
		for d in tries {
			let fy: Double = floor(y + d) + 0.999
			if !world.boxSolid(x - w * 0.5, fy - h, x + w * 0.5, fy - 0.02) { return fy }
		}
		return nil
	}

	/// Whether the creature's present phase lets it use attack i
	func phaseAllows(_ m: Mob, _ r: ModMobRT, _ i: Int) -> Bool {
		if m.mphase <= 0 || m.mphase > r.def.phases.count { return true }
		let l: [Int] = r.def.phases[m.mphase - 1].attacks
		return l.isEmpty || l.contains(i)
	}

	/// The name on the boss bar: the creature's, and the phase it is in
	func bossTitle(_ b: Mob) -> String {
		if b.kind == .custom && b.mphase > 0, let r = ModRuntime.shared.mob(b.cslot), b.mphase <= r.def.phases.count {
			let pn: String = r.def.phases[b.mphase - 1].name.trimmingCharacters(in: .whitespaces)
			if !pn.isEmpty { return joinText(b.def.name, " \u{00B7} ", pn) }
		}
		return b.def.name
	}

	/// A summoned creature leaves once the player is gone (dead, or far away) for a few seconds
	func summonedLeaves(_ m: Mob, _ dt: Double) -> Bool {
		if dead || abs(pb.x - m.b.x) > 150 || abs(pb.y - m.b.y) > 100 { m.leaveT += dt } else { m.leaveT = 0 }
		if m.leaveT < 4.0 { return false }
		m.removed = true
		say(joinText(m.def.name, " has gone."), 2.5)
		spawnParticles(m.b.x, m.b.cy, 0xB0A0FF, 16, 4.0, 0.6, -2)
		return true
	}

	// MARK: summoning

	/// The biome at x in the world the player is in
	func biomeAt(_ x: Double) -> Biome {
		if world.dim == .overworld { return gen.col(Int(floor(x))).biome }
		if let d = customDim { return d.biomeAt(x) }
		return .umbral
	}

	/// Tries the summonings this item starts (a tap with it in hand). True when a creature came, or
	/// when the item does nothing else (then the reason it didn't work is shown)
	func trySummonWith(_ it: Item) -> Bool {
		var why: String? = nil
		for s in ModRuntime.shared.summons where s.def.usesItem && s.def.item == it {
			// inside the dimension, its key item takes the player back
			if s.dimSlot >= 0 && world.dim == .custom(s.dimSlot) {
				leaveCustomDim()
				return true
			}
			var at: (Int, Int)? = nil
			if s.def.how == .itemOnPattern {
				let tx: Int = Int(floor(aimX))
				let ty: Int = Int(floor(aimY))
				if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
					why = "Tap the shape you built, within reach."
					continue
				}
				guard let o = s.shapeAt(world, tx, ty) else {
					why = "Tap a block of the finished shape."
					continue
				}
				at = o
			}
			if s.dimSlot >= 0 {
				guard let dr = ModRuntime.shared.dimSlots[s.dimSlot] else { continue }
				if let w = conditionsProblem(s.def, dr.def.name, at) {
					why = w
					continue
				}
				if s.def.consume && !isCreative { inv.removeAt(sel, 1) }
				if let o = at, s.def.clearPattern { for c in s.cells where c.2 != nil { world.set(o.0 + c.0, o.1 + c.1, .air) } }
				enterCustomDim(dr)
				return true
			}
			if let w = summonProblem(s, at) {
				why = w
				continue
			}
			if let w = summonCreature(s, at) {
				why = w
				continue
			}
			if s.def.consume && !isCreative { inv.removeAt(sel, 1) }
			bumpHUD()
			return true
		}
		guard let w = why else { return false }
		say(w, 2.2)
		return summonOnly(it)
	}

	/// Items that do nothing but summon (a failed summoning doesn't fall through to another use)
	func summonOnly(_ it: Item) -> Bool {
		switch it {
		case .mat(let m): return m != .seeds && m != .vial
		case .custom(let k):
			guard let r = ModRuntime.shared.item(k) else { return true }
			return r.def.kind == .material || r.def.kind == .ammo
		default: return false
		}
	}

	/// After the player places a block: a shape it finishes calls its creature
	func summonByBuilding(_ x: Int, _ y: Int) {
		for s in ModRuntime.shared.summons where s.def.how == .buildPattern {
			guard let o = s.shapeAt(world, x, y) else { continue }
			if s.dimSlot >= 0 {
				guard let dr = ModRuntime.shared.dimSlots[s.dimSlot], world.dim != dr.dim else { continue }
				if let w = conditionsProblem(s.def, dr.def.name, o) {
					say(w, 2.5)
					continue
				}
				if s.def.clearPattern { for c in s.cells where c.2 != nil { world.set(o.0 + c.0, o.1 + c.1, .air) } }
				enterCustomDim(dr)
				return
			}
			if let w = summonProblem(s, o) {
				say(w, 2.5)
				continue
			}
			if let w = summonCreature(s, o) {
				say(w, 2.2)
				continue
			}
			return
		}
	}

	/// Why the summoning can't happen here and now (nil: it can)
	func summonProblem(_ s: ModSummonRT, _ at: (Int, Int)?) -> String? {
		guard let r = ModRuntime.shared.mob(s.slot) else { return "That creature's mod is not on." }
		let name: String = r.def.name
		for m in mobs where m.kind == .custom && m.cslot == s.slot && m.hp > 0 && !m.removed && (m.summoned || r.boss) {
			return joinText(name, " is already here.")
		}
		return conditionsProblem(s.def, name, at)
	}

	/// Why a summoning's (or a dimension's way in) conditions don't hold here and now (nil: they do)
	func conditionsProblem(_ d: ModSummon, _ name: String, _ at: (Int, Int)?) -> String? {
		var x: Double = pb.x
		var y: Double = pb.y - 0.5
		if let o = at {
			x = Double(o.0) + Double(d.pattern.w) * 0.5
			y = Double(o.1) - 0.5
		}
		if !d.dims.isEmpty || !d.dimKeys.isEmpty {
			var ok: Bool = d.dims.contains(world.dim.rawValue)
			if let cd = customDim, d.dimKeys.contains(cd.key) { ok = true }
			if !ok {
				var names: [String] = d.dims.map { ModSummonText.dimName($0) }
				for k in d.dimKeys {
					let n: String? = ModRuntime.shared.dimSlots.first { $0?.key == k }??.def.name
					names.append(n ?? "another dimension")
				}
				return joinText(name, " only answers in ", names.joined(separator: " or "), ".")
			}
		}
		if !d.biomes.isEmpty && !d.biomes.contains(biomeAt(x).rawValue) {
			return joinText(name, " only answers in ", d.biomes.map { ModSummonText.biomeName($0) }.joined(separator: " or "), ".")
		}
		if d.time == 1 && isNight { return joinText(name, " only answers by day.") }
		if d.time == 2 && !isNight { return joinText(name, " only answers at night.") }
		if d.weather > 0 && d.weather < ModSummonText.weatherWords.count && settings.weatherOn {
			let w: LocalWeather = weatherAt(x, y)
			var ok: Bool = true
			switch d.weather {
			case 1: ok = w.precip < 0.15 && w.thunder < 0.1
			case 2: ok = w.precip >= 0.2
			case 3: ok = w.thunder >= 0.2
			default: ok = w.snow && w.precip >= 0.2
			}
			if !ok { return joinText(name, " only answers ", ModSummonText.weatherWords[d.weather], ".") }
		}
		let open: Bool = world.isSkyExposed(Int(floor(x)), Int(floor(y)) - 1)
		if d.place == 1 && !open { return joinText(name, " only answers under the open sky.") }
		if d.place == 2 && open { return joinText(name, " only answers underground.") }
		return nil
	}

	/// Calls the creature: it appears on the shape (which is used up if the summoning says so), beside
	/// the player, or a little way off. Returns why it couldn't (nil: it came).
	func summonCreature(_ s: ModSummonRT, _ at: (Int, Int)?) -> String? {
		guard let r = ModRuntime.shared.mob(s.slot) else { return "That creature's mod is not on." }
		let w: Double = r.mdef.w
		let h: Double = r.mdef.h
		var x: Double = pb.x + Double(facing) * (w * 0.5 + 1.6)
		var y: Double = pb.y
		if let o = at {
			x = Double(o.0) + Double(s.def.pattern.w) * 0.5
			y = Double(o.1) - 0.001
		}
		if s.def.appear == 1 {
			let side: Double = Double.random(in: 0...1) < 0.5 ? -1.0 : 1.0
			x = pb.x + side * 14.0
			let open: Bool = world.isSkyExposed(Int(floor(pb.x)), Int(floor(pb.y)) - 2)
			y = open ? Double(world.surfaceY(Int(floor(x)))) - 0.001 : pb.y
		}
		// the shape goes first (so the creature can stand where it was); put back if nothing comes
		var used: [(Int, Int, Tile)] = []
		if let o = at, s.def.clearPattern {
			for c in s.cells where c.2 != nil {
				let tx: Int = o.0 + c.0
				let ty: Int = o.1 + c.1
				used.append((tx, ty, world.tile(tx, ty)))
				world.set(tx, ty, .air)
			}
		}
		func undo() { for u in used { world.set(u.0, u.1, u.2) } }
		guard let fy = roomNear(x, y, w, h) else {
			undo()
			return joinText("There's no room for ", r.def.name, " here.")
		}
		guard let m = addCustomMob(s.slot, x, fy) else {
			undo()
			return "Too many creatures are about right now."
		}
		m.persistent = true
		m.summoned = true
		m.homeX = x
		m.homeY = fy
		m.dir = pb.x >= x ? 1 : -1
		m.lastHitByPlayer = clock
		m.phaseShield = 1.0
		say(s.def.message.isEmpty ? joinText(r.def.name, " has been summoned!") : s.def.message, 3.5)
		sfx(.roar, at: x, 1.0)
		addShake(0.4)
		let glow: UInt32 = r.def.tintAmt > 0.05 ? r.def.tint : 0xC070FF
		spawnParticles(x, fy - h * 0.5, glow, 30, 7.0, 0.9, 0)
		for u in used { spawnParticles(Double(u.0) + 0.5, Double(u.1) + 0.5, glow, 3, 2.0, 0.5, 0) }
		refreshBossBar()
		return nil
	}

	// MARK: saving a fight

	func bossSaves() -> [ModBossSave]? {
		var out: [ModBossSave] = []
		for m in mobs where m.kind == .custom && m.summoned && m.hp > 0 && !m.removed {
			guard let r = ModRuntime.shared.mob(m.cslot) else { continue }
			out.append(ModBossSave(key: r.key, x: m.b.x, y: m.b.y, hp: m.hp, phase: m.mphase, fightT: m.fightT))
		}
		return out.isEmpty ? nil : out
	}

	/// Summoned creatures of a loaded world come back, in the phase they were in (if their mod is on,
	/// and they were near the player)
	func restoreBosses(_ l: [ModBossSave]) {
		for b in l {
			guard let slot = ModRuntime.shared.mobSlot[b.key], let r = ModRuntime.shared.mob(slot) else { continue }
			if abs(b.x - pb.x) > 60 || abs(b.y - pb.y) > 60 { continue }
			guard let m = addCustomMob(slot, b.x, b.y) else { continue }
			m.persistent = true
			m.summoned = true
			m.homeX = b.x
			m.homeY = b.y
			m.hp = clampD(b.hp.isFinite ? b.hp : m.maxHP, 1, m.maxHP)
			for k in 0..<clampI(b.phase, 0, r.def.phases.count) { enterPhase(m, r, k, quiet: true) }
			m.fightT = clampD(b.fightT.isFinite ? b.fightT : 0, 0, 3600)
		}
	}
}

extension Art {
	/// A custom creature's sprites in a phase (tinted with the phase's colour; made once per phase)
	func customMobSet(_ slot: Int, _ phase: Int) -> SpriteSet {
		if phase <= 0 { return customMobSet(slot) }
		let key: Int = 1_000_000 + slot * 16 + min(phase, 15)
		if let s = modMobSets[key] { return s }
		guard let r = ModRuntime.shared.mob(slot), phase <= r.def.phases.count else { return customMobSet(slot) }
		let p: ModPhase = r.def.phases[phase - 1]
		let s: SpriteSet = p.tintAmt > 0.01 ? modMobSpriteSet(r.def, tint: p.tint, amt: p.tintAmt) : customMobSet(slot)
		modMobSets[key] = s
		return s
	}
}

/// A custom creature's sprites with a colour laid over them (its phases)
func modMobSpriteSet(_ m: ModMob, tint: UInt32, amt: Double) -> SpriteSet {
	let fr: ([PixelBuf], CreatureAnim) = modMobFrames(m)
	var frames: [PixelBuf] = []
	for f in fr.0 { frames.append(recolorBuf(f, hue: 0, sat: 1, bright: 1, tint: tint, amt: clampD(amt, 0, 1))) }
	return modMobSet(m, frames, fr.1)
}

extension ModValidator {
	/// Phases and summonings of custom creatures: numbers in range, helpers, items and blocks real
	static func checkBosses(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		let ownMobs: Set<String> = Set(p.mobs.map { p.key($0.id) })
		let gameNames: Set<String> = Set(MobKind.allCases.filter { $0 != .custom && $0 != .villager }.map { mobDef($0).name })
		func c(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double { return clampD(v.isFinite ? v : d, lo, hi) }
		for i in p.mobs.indices {
			var m: ModMob = p.mobs[i]
			let place: String = joinText("Creature \u{201C}", m.name, "\u{201D}")
			if m.phases.count > ModLimits.maxPhases {
				r.add(1, mn, place, joinText("Only ", String(ModLimits.maxPhases), " phases fit; the rest were left out."))
				m.phases = Array(m.phases.prefix(ModLimits.maxPhases))
			}
			var calls: Bool = false
			var lastHealth: Double = 2
			for k in m.phases.indices {
				var f: ModPhase = m.phases[k]
				f.name = String(f.name.prefix(24))
				f.message = String(f.message.prefix(80))
				switch f.when {
				case .health:
					f.value = c(f.value, 0.05, 0.95, 0.5)
					if f.value > lastHealth + 0.001 { r.add(1, mn, place, joinText("Phase ", String(k + 1), " begins at more health than the one before it, so it follows straight after.")) }
					lastHealth = f.value
				case .time: f.value = c(f.value, 3, 600, 30)
				case .helpersGone:
					if !calls { r.add(1, mn, place, joinText("Phase ", String(k + 1), " waits for helpers, but no phase before it calls any.")) }
				}
				f.speedMul = c(f.speedMul, 0.5, sb ? 3 : 2, 1)
				f.damageMul = c(f.damageMul, 0.5, sb ? 6 : 3, 1)
				f.cooldownMul = c(f.cooldownMul, 0.3, 2, 1)
				f.defense = c(f.defense, 0, sb ? 0.9 : 0.6, 0)
				f.tintAmt = c(f.tintAmt, 0, 1, 0)
				f.heal = c(f.heal, 0, 0.5, 0)
				f.shield = c(f.shield, 0, 5, 0)
				f.attacks = Array(Set(f.attacks.filter { $0 >= 0 && $0 < m.attacks.count })).sorted()
				f.helpers = clampI(f.helpers, 0, sb ? 10 : 6)
				if !f.helper.isEmpty && !gameNames.contains(f.helper) && !ownMobs.contains(f.helper) && known[f.helper] != "mob" {
					r.add(1, mn, place, joinText("The helper phase ", String(k + 1), " calls does not exist."))
					f.helper = ""
				}
				if f.helper == p.key(m.id) {
					r.add(1, mn, place, "A creature can't call more of itself as helpers.")
					f.helper = ""
				}
				if f.helper.isEmpty { f.helpers = 0 }
				if f.helpers > 0 { calls = true }
				m.phases[k] = f
			}
			if m.summons.count > ModLimits.maxSummons {
				r.add(1, mn, place, joinText("Only ", String(ModLimits.maxSummons), " ways to summon fit; the rest were left out."))
				m.summons = Array(m.summons.prefix(ModLimits.maxSummons))
			}
			for k in m.summons.indices {
				var s: ModSummon = m.summons[k]
				for n in fixSummon(&s, p, known) { r.add(1, mn, place, n) }
				m.summons[k] = s
			}
			p.mobs[i] = m
		}
	}
}

// MARK: - Mod Creator+: custom dimensions

/// Height of every custom dimension (blocks)
let customDimH: Int = 320
/// Dimensions one world holds: the Overworld, the Umbral Realm and three custom ones
let dimCount: Int = 5

extension Dimension {
	var isCustom: Bool { return rawValue >= 2 }
	/// which of the three custom dimension slots it is (-1: not a custom one)
	var customSlot: Int { return rawValue >= 2 ? rawValue - 2 : -1 }
	static func custom(_ slot: Int) -> Dimension { return Dimension(rawValue: 2 + clampI(slot, 0, 2)) ?? .overworld }
}

/// Whether a dimension has open sky (sunlight, rain, the sky drawn behind it)
func dimHasSky(_ d: Dimension) -> Bool {
	if d == .overworld { return true }
	if d.isCustom, let r = ModRuntime.shared.dimRT(d) { return !r.def.ceiling }
	return false
}

/// The shape a tree design grows in
enum ModTreeShape: Int, Codable, CaseIterable {
	case round, pine, tall, umbrella, palm, willow, bush, bare, painted
	var name: String {
		switch self {
		case .round: return "Round"
		case .pine: return "Pine (a cone)"
		case .tall: return "Tall and thin"
		case .umbrella: return "Umbrella"
		case .palm: return "Palm"
		case .willow: return "Willow (hanging)"
		case .bush: return "Bush"
		case .bare: return "Bare (no leaves)"
		case .painted: return "Painted (your own)"
		}
	}
}

/// A tree painted cell by cell: 0 empty, 1 trunk, 2 branch, 3 leaves. Its root is the middle of the
/// bottom row, which stands on the ground.
struct ModTreeGrid: Codable, Equatable {
	var w: Int = 9
	var h: Int = 12
	var cells: [UInt8] = ModTreeGrid.sample(9, 12)

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		w = c.val(.w, 9)
		h = c.val(.h, 12)
		cells = c.val(.cells, [])
	}

	var valid: Bool { return w >= 3 && h >= 3 && w <= 15 && h <= 24 && cells.count == w * h }

	func at(_ x: Int, _ y: Int) -> UInt8 {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return 0 }
		return cells[y * w + x]
	}

	/// a small round tree to start painting from
	static func sample(_ w: Int, _ h: Int) -> [UInt8] {
		var out: [UInt8] = [UInt8](repeating: 0, count: w * h)
		let mid: Int = w / 2
		for y in (h - 5)..<h { out[y * w + mid] = 1 }
		for y in 0..<(h - 4) {
			for x in 0..<w {
				let dx: Double = Double(x - mid) / 3.5
				let dy: Double = Double(y - (h - 8)) / 3.6
				if dx * dx + dy * dy <= 1.0 && out[y * w + x] == 0 { out[y * w + x] = 3 }
			}
		}
		return out
	}

	/// another size, the tree kept standing at the bottom middle
	func resized(_ nw: Int, _ nh: Int) -> ModTreeGrid {
		var o = ModTreeGrid()
		o.w = clampI(nw, 3, 15)
		o.h = clampI(nh, 3, 24)
		o.cells = [UInt8](repeating: 0, count: o.w * o.h)
		let ox: Int = o.w / 2 - w / 2
		let oy: Int = o.h - h
		for y in 0..<h {
			for x in 0..<w {
				let tx: Int = x + ox
				let ty: Int = y + oy
				if tx >= 0 && ty >= 0 && tx < o.w && ty < o.h { o.cells[ty * o.w + tx] = at(x, y) }
			}
		}
		return o
	}
}

/// A tree design for a mod's dimensions: the blocks it is made of, its shape and size, how often it
/// grows and on what. Like the game's trees, its trunk, branches and leaves are passed through (a solid
/// block of a mod chosen for them gets a pass-through tree form of its own).
struct ModTree: Codable, Identifiable, Equatable {
	/// designs one mod may hold
	static let maxDesigns: Int = 12

	var id: String = ""
	var name: String = "New Tree"
	var trunk: String = ModGround.key(.log)
	/// the branches' block (empty: the trunk's)
	var branch: String = ""
	var leaves: String = ModGround.key(.leaves)
	var shape: ModTreeShape = .round
	var minHeight: Int = 4
	var maxHeight: Int = 7
	/// a trunk two blocks wide
	var thick: Bool = false
	/// how far the leaves reach from the trunk
	var crown: Int = 2
	var branches: Int = 1
	/// how full the leaves are (0.2 sparse ... 1 solid)
	var density: Double = 0.9
	var grid: ModTreeGrid = ModTreeGrid()
	/// how often it grows among its region's trees
	var weight: Double = 1
	/// it grows only on this ground (empty: on any)
	var ground: String = ""

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Tree")
		trunk = c.val(.trunk, ModGround.key(.log))
		branch = c.val(.branch, "")
		leaves = c.val(.leaves, ModGround.key(.leaves))
		shape = c.val(.shape, .round)
		minHeight = c.val(.minHeight, 4)
		maxHeight = c.val(.maxHeight, 7)
		thick = c.val(.thick, false)
		crown = c.val(.crown, 2)
		branches = c.val(.branches, 1)
		density = c.val(.density, 0.9)
		grid = c.val(.grid, ModTreeGrid())
		weight = c.val(.weight, 1)
		ground = c.val(.ground, "")
	}
}

/// A stretch of a custom dimension with its own ground, plants and trees: its biomes
struct ModDimZone: Codable, Equatable {
	var name: String = "Meadow"
	/// the game biome it counts as (for ores, structures, summoning and creature rules)
	var biome: Int = Biome.plains.rawValue
	var ground: String = ModGround.key(.grass)
	var filler: String = ModGround.key(.dirt)
	/// a small plant on the ground (empty: none)
	var plant: String = ModGround.key(.tallGrass)
	var plantChance: Double = 0.12
	/// 0 none, 1 a few, 2 many
	var trees: Int = 1
	var log: String = ModGround.key(.log)
	var leaves: String = ModGround.key(.leaves)
	/// the mod's tree designs that grow here, by id (empty: the simple trees of its log and leaves)
	var treeKinds: [String] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = c.val(.name, "Zone")
		biome = c.val(.biome, Biome.plains.rawValue)
		ground = c.val(.ground, ModGround.key(.grass))
		filler = c.val(.filler, ModGround.key(.dirt))
		plant = c.val(.plant, "")
		plantChance = c.val(.plantChance, 0.12)
		trees = c.val(.trees, 1)
		log = c.val(.log, ModGround.key(.log))
		leaves = c.val(.leaves, ModGround.key(.leaves))
		treeKinds = c.val(.treeKinds, [])
	}
}

/// A creature that lives in a custom dimension
struct ModDimSpawn: Codable, Equatable {
	/// "mod:id", or a game creature's name
	var creature: String = ""
	/// 0 on the surface, 1 in caves, 2 anywhere
	var place: Int = 0
	/// 0 any time, 1 by day, 2 at night
	var when: Int = 0
	var weight: Double = 5
	var group: Int = 1

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		creature = c.val(.creature, "")
		place = c.val(.place, 0)
		when = c.val(.when, 0)
		weight = c.val(.weight, 5)
		group = c.val(.group, 1)
	}
}

/// A sun or a moon of a mod's own: its picture (blank: the game's, in its colour), how big it is, its
/// glow, how it moves across the sky, and how much light it gives
struct ModSkyBody: Codable, Equatable {
	var art: ModPixels = ModPixels(w: 16, h: 16)
	/// times the game's size
	var size: Double = 1.0
	/// the colour of the game's round one (a picture keeps its own colours)
	var color: UInt32 = 0xFFD84A
	var glow: Double = 0.35
	var glowColor: UInt32 = 0xFFE680
	/// 0 rises and sets with the time of day, 1 stays in one place in the sky (day and night)
	var path: Int = 0
	/// how high its path climbs (0.2 low ... 1.2 high)
	var arc: Double = 1.0
	/// where it stays: across (0 left ... 1 right) and down (0 top ... 1 the horizon)
	var posX: Double = 0.75
	var posY: Double = 0.2
	/// the light it gives: a sun scales the daylight, a moon the light at night (1: the game's)
	var bright: Double = 1.0
	/// turning slowly (degrees a second; 0 still)
	var spin: Double = 0
	/// its glow swelling and fading (0 steady ... 1 strong)
	var pulse: Double = 0
	/// rays all round it
	var rays: Bool = false

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		art = c.val(.art, ModPixels(w: 16, h: 16))
		size = c.val(.size, 1.0)
		color = c.val(.color, 0xFFD84A)
		glow = c.val(.glow, 0.35)
		glowColor = c.val(.glowColor, 0xFFE680)
		path = c.val(.path, 0)
		arc = c.val(.arc, 1.0)
		posX = c.val(.posX, 0.75)
		posY = c.val(.posY, 0.2)
		bright = c.val(.bright, 1.0)
		spin = c.val(.spin, 0)
		pulse = c.val(.pulse, 0)
		rays = c.val(.rays, false)
	}

	/// a new moon: pale, faint glow
	static func moon() -> ModSkyBody {
		var m = ModSkyBody()
		m.color = 0xE8ECF4
		m.glow = 0.15
		m.glowColor = 0xC8D0E8
		return m
	}

	/// every number kept within what the sky can show
	mutating func clamp() {
		if !art.valid || art.w > 32 || art.h > 32 { art = ModPixels(w: 16, h: 16) }
		size = clampD(size.isFinite ? size : 1, 0.3, 3.0)
		glow = clampD(glow.isFinite ? glow : 0, 0, 1)
		path = clampI(path, 0, 1)
		arc = clampD(arc.isFinite ? arc : 1, 0.2, 1.2)
		posX = clampD(posX.isFinite ? posX : 0.75, 0, 1)
		posY = clampD(posY.isFinite ? posY : 0.2, 0, 1)
		bright = clampD(bright.isFinite ? bright : 1, 0, 2)
		spin = clampD(spin.isFinite ? spin : 0, -180, 180)
		pulse = clampD(pulse.isFinite ? pulse : 0, 0, 1)
	}
}

/// A dimension made in the Mod Creator: how its sky and light look, how its land is made, what lives
/// there, and how a player gets in and out. Each world gives its dimensions one of three slots.
struct ModDimension: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Dimension"
	var desc: String = ""
	// sky and light
	var skyTop: UInt32 = 0x3A2A6A
	var skyBottom: UInt32 = 0xC07AB0
	var nightTop: UInt32 = 0x080614
	var nightBottom: UInt32 = 0x241A3A
	/// how bright the open air is (0 dark ... 1 full daylight)
	var light: Double = 0.8
	/// follows the world's day and night (off: always the same time)
	var cycle: Bool = true
	/// the time it always is without a cycle (0.25 noon ... 0.75 midnight)
	var fixedTime: Double = 0.25
	var sun: Bool = true
	var moon: Bool = true
	var stars: Bool = true
	var sunColor: UInt32 = 0xFFE8A0
	/// its own sun and moon (nil: the game's round ones)
	var sunBody: ModSkyBody? = nil
	var moonBody: ModSkyBody? = nil
	/// floating motes: 0 none, 1 embers, 2 snowflakes, 3 fireflies, 4 ash, 5 spores
	var ambient: Int = 0
	/// 0 none, 1 drizzle, 2 rain, 3 thunderstorms, 4 snow
	var weather: Int = 0
	/// 0 mild ... 1 bitter cold (as the game's cold: it chills the player)
	var chill: Double = 0
	var hot: Bool = false
	// the land
	/// a roof of rock overhead: a cavern world, like the Umbral Realm (no sky, no sun)
	var ceiling: Bool = false
	/// the row the ground lies at (smaller is higher up)
	var surface: Int = 150
	var hills: Double = 12
	var roughness: Double = 1.0
	/// tall peaks (0 none ... 1 many)
	var mountains: Double = 0.2
	var caves: Double = 0.4
	/// floating islands in the sky (0 none ... 1 many)
	var islands: Double = 0
	/// the row its seas fill up to (0: no seas)
	var sea: Int = 0
	/// 0 water, 1 lava (seas, and pools deep in the caves)
	var liquid: Int = 0
	var pools: Bool = true
	var stone: String = ModGround.key(.stone)
	/// its regions, side by side (at least one)
	var zones: [ModDimZone] = [ModDimZone()]
	var zoneWidth: Int = 300
	/// a block scattered on the ground that harms or hinders (empty: none)
	var hazard: String = ""
	var hazardChance: Double = 0.02
	// life
	var spawns: [ModDimSpawn] = []
	// getting in and out
	var entry: ModSummon = ModDimension.defaultEntry
	/// a gate stands where the player arrives; tapping it takes them back
	var returnGate: Bool = true
	/// the gate's block: one of this mod's blocks (empty: a glowing crystal)
	var gateBlock: String = ""
	var arriveMessage: String = ""

	static var defaultEntry: ModSummon {
		var s = ModSummon()
		s.how = .itemOnPattern
		s.clearPattern = false
		return s
	}

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Dimension")
		desc = c.val(.desc, "")
		skyTop = c.val(.skyTop, 0x3A2A6A)
		skyBottom = c.val(.skyBottom, 0xC07AB0)
		nightTop = c.val(.nightTop, 0x080614)
		nightBottom = c.val(.nightBottom, 0x241A3A)
		light = c.val(.light, 0.8)
		cycle = c.val(.cycle, true)
		fixedTime = c.val(.fixedTime, 0.25)
		sun = c.val(.sun, true)
		moon = c.val(.moon, true)
		stars = c.val(.stars, true)
		sunColor = c.val(.sunColor, 0xFFE8A0)
		sunBody = c.val(.sunBody, nil)
		moonBody = c.val(.moonBody, nil)
		ambient = c.val(.ambient, 0)
		weather = c.val(.weather, 0)
		chill = c.val(.chill, 0)
		hot = c.val(.hot, false)
		ceiling = c.val(.ceiling, false)
		surface = c.val(.surface, 150)
		hills = c.val(.hills, 12)
		roughness = c.val(.roughness, 1.0)
		mountains = c.val(.mountains, 0.2)
		caves = c.val(.caves, 0.4)
		islands = c.val(.islands, 0)
		sea = c.val(.sea, 0)
		liquid = c.val(.liquid, 0)
		pools = c.val(.pools, true)
		stone = c.val(.stone, ModGround.key(.stone))
		zones = c.list(.zones, &skip)
		if zones.isEmpty { zones = [ModDimZone()] }
		zoneWidth = c.val(.zoneWidth, 300)
		hazard = c.val(.hazard, "")
		hazardChance = c.val(.hazardChance, 0.02)
		spawns = c.list(.spawns, &skip)
		entry = c.val(.entry, ModDimension.defaultEntry)
		returnGate = c.val(.returnGate, true)
		gateBlock = c.val(.gateBlock, "")
		arriveMessage = c.val(.arriveMessage, "")
	}
}

/// Words for the dimension settings
enum ModDimText {
	static let ambients: [String] = ["None", "Embers", "Snowflakes", "Fireflies", "Ash", "Spores"]
	static let weathers: [String] = ["None", "Drizzle", "Rain", "Thunderstorms", "Snow", "Strong wind", "Windstorms", "Hailstorms", "Blizzards"]
	static let liquids: [String] = ["Water", "Lava"]
	static let trees: [String] = ["None", "A few", "Many"]
	static let places: [String] = ["Surface", "Caves", "Anywhere"]
	static let times: [String] = ["Any time", "By day", "At night"]
}

/// Where a player came from when they entered a custom dimension (to go back there)
struct DimReturn: Codable, Equatable {
	var dim: Int
	var x: Double
	var y: Double
}

/// A custom dimension ready for play: its blocks resolved, its creature rules, its land's shape
final class ModDimRT {
	let key: String
	let slot: Int
	let def: ModDimension
	let salt: UInt64
	let stone: Tile
	let liquid: Tile
	let hazard: Tile?
	let gate: Tile
	let zones: [ModDimZoneRT]
	var spawnRules: [SpawnRule] = []
	var modName: String = ""
	/// some region grows the mod's tree designs
	let hasDesigns: Bool
	/// the regions' plants (trees grow over them), and their ground (where saplings take root)
	let plantTiles: Set<UInt8>
	let soils: Set<UInt8>

	var dim: Dimension { return .custom(slot) }

	/// `trees` are the mod's tree designs; `treeTile` gives the tile a tree is made of for a block key
	/// (a solid block's pass-through tree form; role 1 trunk or branch, 2 leaves)
	init(key: String, slot: Int, def: ModDimension, resolve: (String) -> Tile?, trees: [ModTree] = [], treeTile: ((String, Int) -> Tile?)? = nil) {
		self.key = key
		self.slot = slot
		self.def = def
		salt = UInt64(truncatingIfNeeded: modChecksum(Data(key.utf8))) &* 0x9E37_79B9 &+ 0x5D1
		func pick(_ k: String, _ d: Tile) -> Tile {
			guard let t = resolve(k), t != .air else { return d }
			return t
		}
		stone = pick(def.stone, .stone)
		liquid = def.liquid == 1 ? .lava : .water
		hazard = def.hazard.isEmpty ? nil : resolve(def.hazard)
		gate = def.gateBlock.isEmpty ? .glowCrystal : pick(def.gateBlock, .glowCrystal)
		func pickTree(_ k: String, _ role: Int, _ d: Tile) -> Tile {
			if let f = treeTile, let t = f(k, role), t != .air, !t.liquid { return t }
			return pick(k, d)
		}
		var zs: [ModDimZoneRT] = []
		var plants: Set<UInt8> = []
		var soil: Set<UInt8> = []
		var any: Bool = false
		for z in def.zones.prefix(4) {
			let plant: Tile? = z.plant.isEmpty ? nil : resolve(z.plant)
			var zr = ModDimZoneRT(ground: pick(z.ground, .grass), filler: pick(z.filler, .dirt), plant: plant, plantChance: z.plantChance,
								  trees: z.trees, log: pickTree(z.log, 1, .log), leaves: pickTree(z.leaves, 2, .leaves), biome: Biome(rawValue: z.biome) ?? .plains)
			for tid in z.treeKinds {
				guard let t = trees.first(where: { $0.id == tid }) else { continue }
				let trunk: Tile = pickTree(t.trunk, 1, .log)
				let br: Tile = t.branch.isEmpty ? trunk : pickTree(t.branch, 1, trunk)
				let lv: Tile = pickTree(t.leaves, 2, .leaves)
				let gr: Tile? = t.ground.isEmpty ? nil : resolve(t.ground)
				zr.designs.append(ModTreeRT(def: t, trunk: trunk, branch: br, leaves: lv, ground: gr))
			}
			if !zr.designs.isEmpty {
				any = true
				// trees stand further apart the wider the widest design grows
				var half: Int = 1
				for t in zr.designs {
					let w: Int = t.def.shape == .painted ? t.def.grid.w / 2 : clampI(t.def.crown, 0, 6) + (t.def.thick ? 1 : 0)
					half = max(half, w)
				}
				zr.gap = clampI(half + 2, 3, 12)
			}
			if let p = plant { plants.insert(p.rawValue) }
			soil.insert(zr.ground.rawValue)
			soil.insert(zr.filler.rawValue)
			zs.append(zr)
		}
		if zs.isEmpty { zs.append(ModDimZoneRT(ground: .grass, filler: .dirt, plant: nil, plantChance: 0, trees: 0, log: .log, leaves: .leaves, biome: .plains)) }
		zones = zs
		hasDesigns = any
		plantTiles = plants
		soils = soil
	}

	/// the region at column x
	func zoneIndex(_ x: Int) -> Int {
		if zones.count <= 1 { return 0 }
		let w: Int = max(40, def.zoneWidth)
		let off: Int = Int(salt % 997)
		let k: Int = floorDiv(x + off, w)
		return ((k % zones.count) + zones.count) % zones.count
	}

	func biomeAt(_ x: Double) -> Biome { return zones[zoneIndex(Int(floor(x)))].biome }

	/// The row of the ground at column x, for a world's seed
	func surfaceAt(_ x: Int, _ seed: UInt64) -> Int {
		let s: UInt64 = seed &+ salt
		let f: Double = clampD(def.roughness, 0.2, 3.0)
		let n: Double = fbm1(Double(x) / (60.0 / f), s &+ 501, 4)
		var h: Double = Double(def.surface) + (n - 0.5) * 2.0 * def.hills
		if def.mountains > 0.001 {
			let m: Double = fbm1(Double(x) / 140.0, s &+ 502, 3)
			let th: Double = 0.78 - def.mountains * 0.26
			if m > th { h -= pow((m - th) / (1.0 - th), 1.4) * 80.0 }
		}
		let lo: Int = def.ceiling ? 72 : 24
		return clampI(Int(h.rounded()), lo, customDimH - 30)
	}

	/// The row where the rock roof ends at column x (roofed dimensions)
	func ceilingAt(_ x: Int, _ seed: UInt64) -> Int {
		return 10 + Int(fbm1(Double(x) / 50.0, seed &+ salt &+ 511, 3) * 28.0)
	}

	/// Where a player arrives: the first dry column near the middle of the dimension
	func arrival(_ seed: UInt64) -> (Double, Double) {
		var x: Int = 0
		for k in 0..<400 {
			let c: Int = k % 2 == 0 ? k / 2 : -(k / 2) - 1
			let s: Int = surfaceAt(c, seed)
			if def.sea <= 0 || s < def.sea - 1 {
				x = c
				break
			}
		}
		return (Double(x) + 0.5, Double(surfaceAt(x, seed)) - 0.001)
	}
}

struct ModDimZoneRT {
	var ground: Tile
	var filler: Tile
	var plant: Tile?
	var plantChance: Double
	var trees: Int
	var log: Tile
	var leaves: Tile
	var biome: Biome
	/// the mod's tree designs that grow here (empty: the simple trees of its log and leaves)
	var designs: [ModTreeRT] = []
	/// how many columns apart its design trees stand at least (by the widest design's crown)
	var gap: Int = 4
}

/// A chunk of a custom dimension: rolling ground in regions, caves, seas, floating islands, trees,
/// plants and hazards, then the mods' ores and structures for it. A dimension whose mod is missing
/// is an empty void (nobody is sent there: see Game.load).
func generateCustomChunk(_ g: WorldGen, _ dim: Dimension, _ cx: Int) -> Chunk {
	let H: Int = customDimH
	let ch = Chunk(cx: cx, H: H)
	guard let d = ModRuntime.shared.dimRT(dim) else {
		ch.hasSky = false
		for lx in 0..<chunkW {
			for y in (H - 3)..<H { ch.tiles[lx * H + y] = Tile.bedrock.rawValue }
			ch.surf[lx] = H - 3
		}
		ch.rebuildSky()
		return ch
	}
	fillCustomChunk(g.seed, g.infinite, g.width, d, ch)
	if ModRuntime.shared.hasWorldGen { applyModGen(g, ch, dim) }
	ch.rebuildSky()
	return ch
}

/// The land of a custom dimension in one chunk (shared by the game and the editor's preview)
func fillCustomChunk(_ seed0: UInt64, _ infinite: Bool, _ width: Int, _ d: ModDimRT, _ ch: Chunk) {
	let H: Int = ch.H
	let def: ModDimension = d.def
	let seed: UInt64 = seed0 &+ d.salt
	ch.hasSky = !def.ceiling
	let x0: Int = ch.x0
	let caveT: Double = 0.035 + clampD(def.caves, 0, 1) * 0.07
	let cavern: Double = 0.9 - clampD(def.caves, 0, 1) * 0.12
	// floating islands: rarer and flatter than the noise alone would make them (they shade the ground)
	let isleT: Double = 0.86 - clampD(def.islands, 0, 1) * 0.08
	for lx in 0..<chunkW {
		let x: Int = x0 + lx
		let base: Int = lx * H
		if !infinite && (x < 0 || x >= width) {
			for y in 0..<H { ch.tiles[base + y] = Tile.bedrock.rawValue }
			continue
		}
		let surf: Int = d.surfaceAt(x, seed0)
		let ceil: Int = def.ceiling ? d.ceilingAt(x, seed0) : 0
		let z: ModDimZoneRT = d.zones[d.zoneIndex(x)]
		ch.surf[lx] = surf
		ch.ceilY[lx] = ceil
		let fill: Int = 3 + Int(hash2(x, 11, seed) * 3.0)
		let seaRow: Int = def.sea > 0 ? clampI(def.sea, 10, H - 10) : H
		for y in 0..<H {
			var t: Tile = .air
			if y >= H - 3 || (def.ceiling && y <= 2) {
				t = .bedrock
			} else if def.ceiling && y < ceil {
				t = d.stone
			} else if y >= surf {
				let depth: Int = y - surf
				t = depth == 0 ? (surf >= seaRow ? z.filler : z.ground) : (depth <= fill ? z.filler : d.stone)
				if depth >= 4 && def.caves > 0.001 {
					let a: Double = vnoise(Double(x) * 0.05, Double(y) * 0.08, seed &+ 601)
					let b: Double = vnoise(Double(x) * 0.028, Double(y) * 0.05, seed &+ 602)
					if abs(a - 0.5) < caveT || b > cavern {
						t = def.pools && y >= H - 40 ? d.liquid : .air
					}
				}
			} else {
				if y >= seaRow { t = d.liquid }
				if def.islands > 0.001 && y > (def.ceiling ? ceil + 12 : 30) && y < surf - 26 {
					let n: Double = vnoise(Double(x) * 0.05, Double(y) * 0.14, seed &+ 631)
					// they gather in a band some way above the ground
					let band: Double = abs(Double(y) - Double(surf - 60)) / 60.0
					if n > isleT + band * 0.06 { t = d.stone }
				}
			}
			ch.tiles[base + y] = t.rawValue
		}
		// the tops of floating islands get the region's ground
		if def.islands > 0.001 {
			var y: Int = 4
			while y < surf - 1 {
				if ch.tiles[base + y] == d.stone.rawValue && ch.tiles[base + y - 1] == Tile.air.rawValue {
					ch.tiles[base + y] = z.ground.rawValue
					if ch.tiles[base + y + 1] == d.stone.rawValue { ch.tiles[base + y + 1] = z.filler.rawValue }
				}
				y += 1
			}
		}
	}
	// trees, plants and hazards on dry ground (trees only where the whole tree fits in this chunk)
	for lx in 0..<chunkW {
		let x: Int = x0 + lx
		if !infinite && (x < 0 || x >= width) { continue }
		let surf: Int = ch.surf[lx]
		if surf <= 12 || surf >= H - 8 { continue }
		if def.sea > 0 && surf >= def.sea - 1 { continue }
		if ch.get(lx, surf - 1) != .air || ch.get(lx, surf) == .air { continue }
		let z: ModDimZoneRT = d.zones[d.zoneIndex(x)]
		if z.trees > 0 && z.designs.isEmpty && lx >= 2 && lx < chunkW - 2 && customTreeAt(x, z.trees, seed) {
			let h: Int = 4 + Int(hash2(x, 22, seed) * 4.0)
			if surf - h - 3 > (def.ceiling ? ch.ceilY[lx] + 2 : 2) {
				for k in 1...h { ch.setLocal(lx, surf - k, z.log) }
				let top: Int = surf - h
				for dy in -2...1 {
					for dx in -2...2 where abs(dx) + abs(dy) <= 3 && lx + dx >= 0 && lx + dx < chunkW {
						let y: Int = top + dy
						if ch.get(lx + dx, y) == .air { ch.setLocal(lx + dx, y, z.leaves) }
					}
				}
				continue
			}
		}
		let r: Double = hash2(x, 5, seed)
		if let hz = d.hazard, r < clampD(def.hazardChance, 0, 0.5) {
			ch.setLocal(lx, surf - 1, hz)
		} else if let p = z.plant, r < clampD(def.hazardChance, 0, 0.5) + clampD(z.plantChance, 0, 0.8) {
			ch.setLocal(lx, surf - 1, p)
		}
	}
	// the mod's own tree designs, in the regions that grow them
	plantTreeDesigns(seed0, infinite, width, d, ch)
}

/// Trees stand at least five columns apart
func customTreeAt(_ x: Int, _ trees: Int, _ seed: UInt64) -> Bool {
	let p: Double = trees >= 2 ? 0.2 : 0.07
	if hash2(x, 21, seed) >= p { return false }
	for k in 1...4 where hash2(x - k, 21, seed) < p { return false }
	return true
}

/// How far a tree design's cells may reach sideways from its root. The generator looks this far past
/// each side of a chunk for trees that lean into it, so a tree across a chunk's edge is whole.
let treeReach: Int = 9

/// One cell of a tree: where it is from the root (dx across, dy rows up: 1 is the row on the ground)
/// and what it is (1 trunk, 2 branch, 3 leaves)
struct TreeCell: Equatable {
	var dx: Int
	var dy: Int
	var part: UInt8
}

/// A tree design ready to grow in a world: its blocks as tiles (solid blocks as their pass-through
/// tree forms), and the ground it needs
struct ModTreeRT {
	var def: ModTree
	var trunk: Tile
	var branch: Tile
	var leaves: Tile
	/// it grows only on this tile (nil: on any ground)
	var ground: Tile?

	func tile(_ part: UInt8) -> Tile { return part == 1 ? trunk : (part == 2 ? branch : leaves) }

	/// rows from the ground to its top, about (for room under a roof and above a sapling)
	func height(_ h: Int) -> Int {
		if def.shape == .painted { return def.grid.h }
		return h + clampI(def.crown, 0, 6) + 2
	}
}

/// The shapes tree designs grow in. Everything comes from the design's numbers and one random seed,
/// so the same seed always makes the same tree.
enum TreeShapes {
	static func cells(_ t: ModTree, _ h0: Int, _ seed: UInt64) -> [TreeCell] {
		var b = TreeBuilder(t, seed)
		let h: Int = clampI(h0, 1, 24)
		switch t.shape {
		case .round: b.round(h)
		case .pine: b.pine(h)
		case .tall: b.tall(h)
		case .umbrella: b.umbrella(h)
		case .palm: b.palm(h)
		case .willow: b.willow(h)
		case .bush: b.bush(h)
		case .bare: b.bare(h)
		case .painted: b.painted()
		}
		return b.out()
	}
}

/// Builds one tree's cells: trunk first, then branches, then leaves, each only where nothing of higher
/// rank is (a trunk is never covered by its own leaves)
struct TreeBuilder {
	var map: [Int: UInt8] = [:]
	var order: [Int] = []
	var rng: RNG
	let c: Int
	let wide: Bool
	let cx: Double
	let dens: Double
	let branches: Int

	init(_ t: ModTree, _ seed: UInt64) {
		rng = RNG(seed)
		c = clampI(t.crown, 0, 6)
		wide = t.thick && t.shape != .painted && t.shape != .bush
		cx = wide ? 0.5 : 0
		dens = clampD(t.density.isFinite ? t.density : 1, 0.2, 1)
		branches = clampI(t.branches, 0, 4)
		grid = t.grid
	}

	let grid: ModTreeGrid

	func out() -> [TreeCell] {
		var o: [TreeCell] = []
		o.reserveCapacity(order.count)
		for k in order {
			guard let p = map[k] else { continue }
			o.append(TreeCell(dx: k / 128 - 64, dy: k % 128, part: p))
		}
		return o
	}

	mutating func put(_ dx: Int, _ dy: Int, _ p: UInt8) {
		if abs(dx) > treeReach || dy < 1 || dy > 60 { return }
		let k: Int = (dx + 64) * 128 + dy
		if let old = map[k] {
			if old <= p { return }
		} else {
			order.append(k)
		}
		map[k] = p
	}

	/// a leaf, kept by the design's fullness: cells at the edge of a crown go first
	mutating func leaf(_ dx: Int, _ dy: Int, _ edge: Double) {
		let e: Double = clampD(edge, 0, 1)
		let keep: Double = dens + (1 - dens) * (1 - e) * (1 - e)
		if rng.double() < keep { put(dx, dy, 3) }
	}

	/// leaves filling an oval around (ox, oy)
	mutating func blob(_ ox: Double, _ oy: Double, _ rx0: Double, _ ry0: Double) {
		let rx: Double = max(0.5, rx0)
		let ry: Double = max(0.5, ry0)
		let x0: Int = Int(floor(ox - rx))
		let x1: Int = Int(ceil(ox + rx))
		let y0: Int = max(1, Int(floor(oy - ry)))
		let y1: Int = Int(ceil(oy + ry))
		if x1 < x0 || y1 < y0 { return }
		for dy in y0...y1 {
			for dx in x0...x1 {
				let a: Double = (Double(dx) - ox) / rx
				let q: Double = (Double(dy) - oy) / ry
				let r2: Double = a * a + q * q
				if r2 <= 1.0 { leaf(dx, dy, sqrt(r2)) }
			}
		}
	}

	mutating func trunk(_ dy0: Int, _ dy1: Int) {
		if dy1 < dy0 { return }
		for dy in dy0...dy1 {
			put(0, dy, 1)
			if wide { put(1, dy, 1) }
		}
	}

	/// a branch from the trunk at height dy to one side, rising one row a cell; a tuft of leaves at its tip
	mutating func branch(_ dy: Int, _ side: Int, _ len: Int, _ tuft: Bool) {
		var x: Int = side < 0 ? 0 : (wide ? 1 : 0)
		var y: Int = dy
		if len <= 0 { return }
		for k in 0..<len {
			x += side
			if k > 0 { y += 1 }
			put(x, y, 2)
		}
		if tuft { blob(Double(x), Double(y) + 0.6, 1.3, 1.0) }
	}

	/// the design's branches spread up the trunk below its crown, sides taking turns
	mutating func sideBranches(_ h: Int, _ top: Int, _ tuft: Bool) {
		if branches <= 0 { return }
		let lo: Int = max(2, h / 2)
		let hi: Int = max(lo, top)
		let first: Int = rng.int(2) == 0 ? -1 : 1
		for k in 0..<branches {
			let by: Int = branches == 1 ? (lo + hi) / 2 : lo + (hi - lo) * k / (branches - 1)
			let side: Int = k % 2 == 0 ? first : -first
			let len: Int = 1 + rng.int(2) + c / 3
			branch(by, side, len, tuft)
		}
	}

	mutating func round(_ h: Int) {
		trunk(1, h)
		let rx: Double = Double(c) + 0.6
		let ry: Double = Double(c) * 0.8 + 0.7
		let oy: Double = Double(h) + Double(c) * 0.25
		blob(cx, oy, rx, ry)
		sideBranches(h, Int(oy - ry) - 1, true)
	}

	mutating func pine(_ h: Int) {
		let tip: Int = h + max(1, c)
		trunk(1, tip - 1)
		let base: Int = max(2, h / 3)
		if base <= tip - 1 {
			for dy in base...(tip - 1) {
				let f: Double = Double(tip - dy) / Double(max(1, tip - base))
				var w: Double = (Double(c) + 0.4) * f
				// boughs in tiers: every other row a little narrower, but never bare beside the trunk
				if (tip - dy) % 2 == 0 { w -= 0.7 }
				let ww: Double = max(c > 0 ? 1.0 : 0.0, w)
				let x0: Int = Int(floor(cx - ww - 0.01))
				let x1: Int = Int(ceil(cx + ww + 0.01))
				for dx in x0...x1 where abs(Double(dx) - cx) <= ww + 0.5 {
					leaf(dx, dy, abs(Double(dx) - cx) / (ww + 0.6))
				}
			}
		}
		put(0, tip, 3)
		if wide { put(1, tip, 3) }
	}

	mutating func tall(_ h: Int) {
		trunk(1, h)
		let ry: Double = Double(c) + 1.2
		let oy: Double = Double(h) - Double(c) * 0.3
		blob(cx, oy, max(0.8, Double(c) * 0.5 + 0.3), ry)
		sideBranches(h, Int(oy - ry) - 1, true)
	}

	mutating func umbrella(_ h: Int) {
		trunk(1, h)
		// two limbs fork up into the crown, then any others lower down
		if branches > 0 {
			branch(h - 1, -1, 2, false)
			branch(h - 1, 1, 2, false)
		}
		let w0: Double = Double(c) + 1.5
		let x0: Int = Int(floor(cx - w0))
		let x1: Int = Int(ceil(cx + w0))
		for dx in x0...x1 {
			let e: Double = abs(Double(dx) - cx) / w0
			if e <= 1 { leaf(dx, h + 1, e) }
			if e <= 0.7 { leaf(dx, h + 2, e + 0.3) }
		}
		if branches > 2 {
			for k in 2..<branches {
				let side: Int = k % 2 == 0 ? -1 : 1
				branch(max(2, h / 2 + k - 2), side, 1 + c / 2, true)
			}
		}
	}

	mutating func palm(_ h: Int) {
		// a trunk that leans as it climbs, with fronds that droop at their ends
		let side: Int = rng.int(2) == 0 ? -1 : 1
		var x: Int = 0
		for dy in 1...h {
			if dy > h / 2 && dy % 3 == 0 { x += side }
			put(x, dy, 1)
			if wide { put(x + 1, dy, 1) }
		}
		let right: Int = x + (wide ? 1 : 0)
		let reach: Int = max(2, c + 1)
		// fronds along the top, a few pointing up, and their tips drooping on both sides
		for dx in (x - reach + 1)...(right + reach - 1) {
			let from: Int = dx < x ? x : right
			put(dx, h + 1, abs(dx - from) <= 1 ? 3 : 3)
		}
		var k: Int = -reach + 2
		while k <= reach - 2 + (wide ? 1 : 0) {
			leaf(x + k, h + 2, 0.4)
			k += 2
		}
		for s in [-1, 1] {
			let from: Int = s < 0 ? x : right
			leaf(from + s * reach, h, 0.3)
			leaf(from + s * (reach + 1), h - 1, 0.5)
			if c >= 3 { leaf(from + s * (reach + 1), h - 2, 0.8) }
		}
	}

	mutating func willow(_ h: Int) {
		trunk(1, h)
		let rx: Double = Double(c) + 1.2
		let ry: Double = max(1.0, Double(c) * 0.55 + 0.5)
		let oy: Double = Double(h) + 0.5
		blob(cx, oy, rx, ry)
		sideBranches(h, h - 2, false)
		// strands hang from under the crown, clear of the trunk
		let x0: Int = Int(floor(cx - rx + 0.5))
		let x1: Int = Int(ceil(cx + rx - 0.5))
		if x1 < x0 { return }
		for dx in x0...x1 {
			if dx == 0 || (wide && dx == 1) { continue }
			if rng.double() > dens + (1 - dens) * 0.4 { continue }
			let a: Double = (Double(dx) - cx) / rx
			let bottom: Double = oy - ry * sqrt(max(0, 1 - a * a))
			let len: Int = 1 + rng.int(max(1, h - 1))
			let y0: Int = Int(bottom.rounded())
			for k in 0..<len { put(dx, y0 - k, 3) }
		}
	}

	mutating func bush(_ h: Int) {
		put(0, 1, 1)
		let ry: Double = Double(clampI(h / 2, 1, c + 2)) + 0.5
		blob(0, 0.5, Double(c) + 0.7, ry)
	}

	mutating func bare(_ h: Int) {
		trunk(1, h)
		let n: Int = max(2, branches + 1)
		let first: Int = rng.int(2) == 0 ? -1 : 1
		let step: Int = max(1, h / (n + 1))
		for k in 0..<n {
			let by: Int = max(2, h - 1 - k * step)
			let side: Int = k % 2 == 0 ? first : -first
			branch(by, side, 1 + rng.int(max(1, c + 1)), false)
		}
		let r: Int = wide ? 1 : 0
		put(-1, h + 1, 2)
		put(1 + r, h + 1, 2)
		if c >= 2 {
			put(-2, h + 2, 2)
			put(2 + r, h + 2, 2)
		}
	}

	mutating func painted() {
		let g: ModTreeGrid = grid
		if !g.valid { return }
		let mid: Int = g.w / 2
		for gy in 0..<g.h {
			for gx in 0..<g.w {
				let v: UInt8 = g.at(gx, gy)
				if v == 0 || v > 3 { continue }
				put(gx - mid, g.h - gy, v)
			}
		}
	}
}

/// The mod's tree designs in one chunk of a custom dimension. Each tree that could reach into the chunk
/// is worked out from the seed alone (where it stands, which design, how tall, its shape), so a tree
/// across a chunk's edge is the same on both sides. Its cells go only into open air or wild plants.
func plantTreeDesigns(_ seed0: UInt64, _ infinite: Bool, _ width: Int, _ d: ModDimRT, _ ch: Chunk) {
	if !d.hasDesigns { return }
	let H: Int = ch.H
	let seed: UInt64 = seed0 &+ d.salt
	let x0: Int = ch.x0
	for rx in (x0 - treeReach)..<(x0 + chunkW + treeReach) {
		guard let at = d.designTreeAt(rx, seed0, infinite, width) else { continue }
		let tr: ModTreeRT = at.0
		let surf: Int = at.1
		let cells: [TreeCell] = TreeShapes.cells(tr.def, at.2, hashU(rx, 47, seed))
		let top: Int = d.def.ceiling ? d.ceilingAt(rx, seed0) + 1 : 1
		for c in cells {
			let x: Int = rx + c.dx
			let lx: Int = x - x0
			if lx < 0 || lx >= chunkW { continue }
			if !infinite && (x < 0 || x >= width) { continue }
			let y: Int = surf - c.dy
			if y <= top || y >= H - 3 { continue }
			let old: Tile = ch.get(lx, y)
			if old != .air && !old.isPlant && !d.plantTiles.contains(old.rawValue) { continue }
			ch.setLocal(lx, y, tr.tile(c.part))
		}
	}
}

extension ModDimRT {
	/// The design tree rooted at column x, if one grows there: its design, the ground row and its
	/// trunk's height. It needs dry ground with no hazard, room under a roof, and a design that grows
	/// on the region's ground.
	func designTreeAt(_ x: Int, _ seed0: UInt64, _ infinite: Bool, _ width: Int) -> (ModTreeRT, Int, Int)? {
		if !infinite && (x < 0 || x >= width) { return nil }
		let z: ModDimZoneRT = zones[zoneIndex(x)]
		if z.designs.isEmpty || z.trees <= 0 { return nil }
		let seed: UInt64 = seed0 &+ salt
		// one tree at most in each stretch of columns, at least `gap` from the next: a stretch a little
		// wider than that for many trees, three times as wide for a few
		let m: Int = max(2, z.gap)
		let span: Int = z.trees >= 2 ? m + 3 : m * 3
		let k: Int = floorDiv(x, span)
		let at: Int = k * span + min(span - m, Int(hash2(k, 41, seed) * Double(span - m + 1)))
		if x != at || hash2(k, 42, seed) >= (z.trees >= 2 ? 0.9 : 0.7) { return nil }
		let surf: Int = surfaceAt(x, seed0)
		if surf <= 12 || surf >= customDimH - 8 { return nil }
		if def.sea > 0 && surf >= def.sea - 1 { return nil }
		if hazard != nil && hash2(x, 5, seed) < clampD(def.hazardChance, 0, 0.5) { return nil }
		guard let tr = pickDesign(z, z.ground, hash2(x, 43, seed)) else { return nil }
		let lo: Int = clampI(tr.def.minHeight, 1, 24)
		let hi: Int = max(lo, clampI(tr.def.maxHeight, 1, 24))
		let h: Int = min(hi, lo + Int(hash2(x, 44, seed) * Double(hi - lo + 1)))
		let roof: Int = def.ceiling ? ceilingAt(x, seed0) + 2 : 2
		if surf - tr.height(h) <= roof { return nil }
		return (tr, surf, h)
	}

	/// One of a region's designs, by their weights, among those that grow on this ground (r: 0 ..< 1)
	func pickDesign(_ z: ModDimZoneRT, _ ground: Tile, _ r: Double) -> ModTreeRT? {
		var total: Double = 0
		for t in z.designs where t.ground == nil || t.ground == ground { total += max(0.1, t.def.weight) }
		if total <= 0 { return nil }
		var left: Double = r * total
		var pick: ModTreeRT? = nil
		for t in z.designs where t.ground == nil || t.ground == ground {
			pick = t
			left -= max(0.1, t.def.weight)
			if left < 0 { break }
		}
		return pick
	}
}

extension ModRuntime {
	func dimRT(_ d: Dimension) -> ModDimRT? {
		let s: Int = d.customSlot
		if s < 0 || s >= dimSlots.count { return nil }
		return dimSlots[s]
	}

	/// Gives each custom dimension one of the three slots (the world's own first, so its land stays
	/// where it is), makes its creature rules, and adds its way in to the summonings
	func buildDims(_ world: ModWorldInfo?) {
		dimSlots = [ModDimRT?](repeating: nil, count: 3)
		dimSlotKey = [String?](repeating: nil, count: 3)
		var taken: Set<Int> = []
		if let w = world {
			for (k, s) in w.dims where s >= 0 && s < 3 {
				dimSlotKey[s] = k
				taken.insert(s)
			}
		}
		for p in packs {
			for d in p.dims where !disabled.contains(p.key(d.id)) {
				let k: String = p.key(d.id)
				var slot: Int = dimSlotKey.firstIndex { $0 == k } ?? -1
				if slot < 0 {
					guard let free = (0..<3).first(where: { !taken.contains($0) }) else {
						var r = ModReport()
						r.add(1, p.name, joinText("Dimension \u{201C}", d.name, "\u{201D}"), "A world holds three custom dimensions; this one was left out.")
						reports.append(r)
						continue
					}
					slot = free
					taken.insert(free)
					dimSlotKey[slot] = k
				}
				let designs: [ModTree] = p.trees.filter { !disabled.contains(p.key($0.id)) }
				let rt = ModDimRT(key: k, slot: slot, def: d, resolve: { key in ModGround.resolve(key, self) }, trees: designs,
								  treeTile: { (key: String, role: Int) -> Tile? in self.treeTile(key, role) })
				rt.modName = p.name
				rt.spawnRules = dimSpawnRules(d)
				dimSlots[slot] = rt
				// its way in: a summoning that takes the player there
				let e: ModSummon = d.entry
				if e.enabled {
					var cells: [(Int, Int, Tile?)] = []
					var bad: Bool = false
					if e.usesPattern {
						for y in 0..<e.pattern.h {
							for x in 0..<e.pattern.w {
								let c: String = e.pattern.cell(x, y)
								if c.isEmpty { continue }
								if c == "air" {
									cells.append((x, y, nil))
									continue
								}
								guard let t = ModGround.resolve(c, self), t != .air else {
									bad = true
									continue
								}
								cells.append((x, y, t))
							}
						}
						if !cells.contains(where: { $0.2 != nil }) { bad = true }
					}
					if e.usesItem && e.item == nil { bad = true }
					if !bad { summons.append(ModSummonRT(slot: -1, key: k, def: e, cells: cells, dimSlot: slot)) }
				}
			}
		}
	}

	/// A dimension's creatures as rules the spawner understands
	func dimSpawnRules(_ d: ModDimension) -> [SpawnRule] {
		var out: [SpawnRule] = []
		for s in d.spawns {
			var kind: MobKind = .custom
			var slot: Int = -1
			if let sl = mobSlot[s.creature] {
				slot = sl
			} else if let k = MobKind.allCases.first(where: { $0 != .custom && $0 != .villager && mobDef($0).name == s.creature }) {
				kind = k
			} else {
				continue
			}
			let when: SpawnWhen = s.when == 1 ? .day : (s.when == 2 ? .night : .any)
			var places: [SpawnPlace] = []
			if s.place == 0 || s.place == 2 { places.append(.surface) }
			if s.place == 1 || s.place == 2 { places.append(.cave) }
			for pl in places {
				var r = SpawnRule(kind: kind, weight: max(0.1, s.weight), place: pl, when: when, biomes: [], group: clampI(s.group, 1, 4))
				r.slot = slot
				r.maxNearby = slot >= 0 ? 6 : 99
				if slot >= 0, let m = mob(slot) { r.sky = m.mdef.flying }
				out.append(r)
			}
		}
		return out
	}

	/// A content dimension number for a mod's ore or structure: the game's own, or a custom one by key
	/// (-1: its dimension is not in this world)
	func dimNumber(_ dim: Int, _ key: String) -> Int {
		if key.isEmpty { return dim }
		guard let s = dimSlotKey.firstIndex(where: { $0 == key }), dimSlots[s] != nil else { return -1 }
		return 2 + s
	}
}

extension Game {
	/// The custom dimension the player is in (nil: the Overworld, the Umbral Realm, or its mod is off)
	var customDim: ModDimRT? { return world.dim.isCustom ? ModRuntime.shared.dimRT(world.dim) : nil }

	/// The ground row at x in a custom dimension
	func customSurface(_ x: Int) -> Int {
		guard let d = customDim else { return world.surfaceY(x) }
		return d.surfaceAt(x, gen.seed)
	}

	/// Takes the player into a custom dimension (remembering where they came from)
	func enterCustomDim(_ r: ModDimRT) {
		if world.dim == r.dim { return }
		if !world.dim.isCustom { dimReturn = DimReturn(dim: world.dim.rawValue, x: pb.x, y: pb.y) }
		let spot: (Double, Double) = r.arrival(gen.seed)
		travelTo(r.dim, arriveX: spot.0, arriveY: spot.1, silent: true)
		if r.def.returnGate { placeReturnGate(r) }
		say(r.def.arriveMessage.isEmpty ? joinText("You step into ", r.def.name, ".") : r.def.arriveMessage, 4.0)
		addShake(0.4)
		sfx(.portal, 0.8)
		spawnParticles(pb.x, pb.y - 1.0, 0xC8A0FF, 24, 5.0, 0.8, -2)
		if !logicRT.isEmpty { fireLogic(.enterDim, text: r.key) }
	}

	/// Back to where the player entered from (the Overworld's spawn if that is unknown)
	func leaveCustomDim() {
		let back: DimReturn = dimReturn ?? DimReturn(dim: 0, x: spawnX, y: spawnY)
		var d: Dimension = Dimension(rawValue: back.dim) ?? .overworld
		if d.isCustom { d = .overworld }
		dimReturn = nil
		travelTo(d, arriveX: back.x, arriveY: back.y, silent: true)
		say(d == .overworld ? "You return to the Overworld." : "You return to the Umbral Realm.", 3.0)
		addShake(0.3)
		sfx(.portal, 0.7)
	}

	/// The way back: a gate on the ground beside where the player arrived
	func placeReturnGate(_ r: ModDimRT) {
		for dx in [2, -2, 3, -3, 4] {
			let x: Int = Int(floor(pb.x)) + dx
			var y: Int = Int(floor(pb.y))
			var k: Int = 0
			while k < 6 && !world.tile(x, y).solid { y += 1; k += 1 }
			while k < 12 && world.tile(x, y - 1).solid { y -= 1; k += 1 }
			if world.tile(x, y).solid && world.tile(x, y - 1) == .air {
				world.set(x, y - 1, r.gate)
				return
			}
		}
	}

	/// A tap on the gate of the custom dimension the player is in takes them back
	func tryReturnGate() -> Bool {
		guard let d = customDim, d.def.returnGate else { return false }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if world.tile(tx, ty) != d.gate || !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
		leaveCustomDim()
		return true
	}

	/// The light of a custom dimension's day
	func customDayFactor(_ d: ModDimRT) -> Double {
		let t: Double = d.def.cycle ? timeOfDay : clampD(d.def.fixedTime, 0, 1)
		if t < 0.50 { return 1.0 }
		if t < 0.58 { return 1.0 - smooth((t - 0.50) / 0.08) }
		if t < 0.92 { return 0.0 }
		return smooth((t - 0.92) / 0.08)
	}

	/// A custom dimension's weather where it can fall (under the open sky): set by its maker
	func customWeather(_ d: ModDimRT, _ x: Double, _ y: Double) -> LocalWeather {
		var L = LocalWeather()
		L.chill = clampD(d.def.chill, 0, 1)
		L.hot = d.def.hot
		// nothing falls under a rock roof
		if d.def.ceiling { return L }
		switch d.def.weather {
		case 1:
			L.precip = 0.3
			L.cloud = 0.6
		case 2:
			L.precip = 0.75
			L.cloud = 0.9
		case 3:
			L.precip = 0.85
			L.cloud = 1.0
			L.thunder = 0.6
			L.wind = 4.0 * sin(clock * 0.3)
		case 4:
			L.precip = 0.6
			L.cloud = 0.85
			L.snow = true
			L.chill = max(L.chill, 0.55)
		case 5:
			L.cloud = 0.4
			L.wind = 8.0 * (0.8 + 0.4 * sin(clock * 0.5 + x * 0.02))
		case 6:
			L.cloud = 0.75
			L.precip = 0.15
			L.wind = 14.0 * (0.75 + 0.5 * sin(clock * 0.4 + x * 0.015))
		case 7:
			L.cloud = 0.95
			L.precip = 0.55
			L.hail = 1.0
			L.thunder = 2.0
			L.wind = 5.0 * sin(clock * 0.3)
		case 8:
			L.cloud = 1.0
			L.precip = 1.0
			L.snow = true
			L.chill = 1.0
			L.wind = 13.0 * (0.8 + 0.3 * sin(clock * 0.5))
		default: break
		}
		if L.chill >= 0.5 && L.precip > 0 { L.snow = true }
		L.wet = L.snow ? 0 : L.precip
		L.fog = L.precip * 0.3
		return L
	}

	/// Visiting a dimension from the Mod Test tools (by slot)
	@discardableResult
	func testVisitDim(_ slot: Int) -> String {
		guard let r = ModRuntime.shared.dimSlots.indices.contains(slot) ? ModRuntime.shared.dimSlots[slot] : nil else { return "That dimension is not in this world." }
		if world.dim == r.dim {
			leaveCustomDim()
			return "Back from the dimension."
		}
		enterCustomDim(r)
		return joinText("Visiting ", r.def.name, ".")
	}
}

extension WorldRenderer {
	/// The sky of a custom dimension: its colours by day and night, stars, sun and moon, and motes
	static func drawCustomSky(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D, _ d: ModDimRT) {
		let full: CGRect = mkRect(0, 0, W, H)
		let day: Double = d.def.ceiling ? 0 : g.dayFactor
		let def: ModDimension = d.def
		if def.ceiling {
			vGradient(&ctx, full, [rgbColor(shadeRGB(def.nightTop, 0.6)), rgbColor(def.nightBottom)], 0, H)
		} else {
			let top: UInt32 = mixRGB(def.nightTop, def.skyTop, day)
			let bot: UInt32 = mixRGB(def.nightBottom, def.skyBottom, day)
			vGradient(&ctx, full, [rgbColor(top), rgbColor(bot)], 0, H)
			let cover: Double = g.wxHere.cloud
			if def.stars && day < 0.6 {
				let a: Double = (0.6 - day) / 0.6 * (1.0 - cover * 0.8)
				var path: Path = Path()
				var i: Int = 0
				while i < 70 {
					let x: Double = hash2(i, 1, 9) * W
					let y: Double = hash2(i, 2, 9) * H * 0.6
					path.addRect(mkRect(x, y, i % 7 == 0 ? 3.0 : 2.0, i % 7 == 0 ? 3.0 : 2.0))
					i += 1
				}
				ctx.fill(path, with: .color(Color.white.opacity(a * (0.75 + 0.25 * sin(g.clock * 2.0)))))
			}
			let t: Double = def.cycle ? g.timeOfDay : clampD(def.fixedTime, 0, 1)
			let ang: Double = t < 0.5 ? (t / 0.5) : ((t - 0.5) / 0.5)
			let bx: Double = (0.1 + 0.8 * ang) * W
			let by: Double = H * (0.55 - 0.42 * sin(ang * Double.pi))
			let r: Double = max(10.0, v.tp * 1.6)
			// a mod's own sun and moon, each in place of the round one
			let night: UInt32 = mixRGB(def.nightTop, def.skyTop, day)
			if def.sun, let sb = def.sunBody { drawSkyBody(&ctx, W, H, g.clock, sb, t, false, r * 2.0, true, night) }
			if def.moon, let mb = def.moonBody { drawSkyBody(&ctx, W, H, g.clock, mb, t, true, r * 1.6, true, night) }
			if t < 0.5 && def.sun && def.sunBody == nil {
				ctx.fill(Path(ellipseIn: mkRect(bx - r * 1.6, by - r * 1.6, r * 3.2, r * 3.2)), with: .color(rgbColor(def.sunColor).opacity(0.18)))
				ctx.fill(Path(ellipseIn: mkRect(bx - r, by - r, r * 2.0, r * 2.0)), with: .color(rgbColor(def.sunColor)))
			} else if t >= 0.5 && def.moon && def.moonBody == nil {
				ctx.fill(Path(ellipseIn: mkRect(bx - r * 0.8, by - r * 0.8, r * 1.6, r * 1.6)), with: .color(Color(hex: 0xE8ECF8)))
				ctx.fill(Path(ellipseIn: mkRect(bx - r * 0.3, by - r * 0.9, r * 1.4, r * 1.4)), with: .color(rgbColor(mixRGB(def.nightTop, def.skyTop, day)).opacity(0.85)))
			}
		}
		// drifting motes, each in its own 12-block cell of the world: they stay put as the camera moves
		// (fireflies wander around their spot; embers, snow, ash and spores drift through their cell)
		if def.ambient > 0 {
			let cols: [UInt32] = [0, 0xFF8A3A, 0xF4F8FF, 0xD8F070, 0x8A8A8A, 0xB0E0A0]
			let col: UInt32 = cols[clampI(def.ambient, 0, cols.count - 1)]
			var path: Path = Path()
			let rise: Double = def.ambient == 2 || def.ambient == 4 ? -1.0 : 1.0
			let flies: Bool = def.ambient == 3
			let cell: Double = 12.0
			let v: View2D = View2D(tp: Double(g.tilePx), left: g.camX - W / Double(g.tilePx) * 0.5, top: g.camY - H / Double(g.tilePx) * 0.5, wTiles: W / Double(g.tilePx), hTiles: H / Double(g.tilePx))
			let cx0: Int = Int(floor(v.left / cell)), cx1: Int = Int(floor((v.left + v.wTiles) / cell))
			let cy0: Int = Int(floor(v.top / cell)), cy1: Int = Int(floor((v.top + v.hTiles) / cell))
			for cy in cy0...max(cy0, cy1) {
				for cx in cx0...max(cx0, cx1) {
					for k in 0..<3 {
						let id: Int = cx &* 7919 &+ cy &* 104729 &+ k
						let sp: Double = 0.4 + hash2(id, 31, 3) * 0.8
						var ox: Double = hash2(id, 32, 3) * cell
						var oy: Double = hash2(id, 33, 3) * cell
						if flies {
							ox += sin(g.clock * 0.5 + Double(k) * 2.1) * 0.8
							oy += sin(g.clock * 0.8 + Double(k) * 1.3) * 0.5
						} else {
							ox = (ox + sin(g.clock * 0.3 + Double(k)) * 0.6)
							oy = (oy - rise * g.clock * sp).truncatingRemainder(dividingBy: cell)
							if oy < 0 { oy += cell }
						}
						let wx: Double = Double(cx) * cell + ox
						let wy: Double = Double(cy) * cell + oy
						let s: Double = flies ? 3.0 : 2.0
						path.addRect(mkRect(v.sx(wx), v.sy(wy), s, s))
					}
				}
			}
			let a: Double = flies ? 0.5 + 0.5 * sin(g.clock * 3.0) : 0.75
			ctx.fill(path, with: .color(rgbColor(col).opacity(a)))
		}
	}
}

/// A picture of a custom dimension for its editor: six chunks of its land from the sky to the
/// bottom, made by the same generator the game uses (its mod's blocks drawn in their own colours)
enum ModDimPreview {
	static let seed: UInt64 = 7_771_234
	static let chunks: Int = 6

	static func render(_ d: ModDimension, _ p: ModPack) -> PixelBuf {
		// the mod's blocks stand in as spare tile numbers, coloured from their art
		var proxy: [String: Tile] = [:]
		var colour: [UInt8: UInt32] = [:]
		for (i, b) in p.blocks.prefix(ModLimits.blockSlots).enumerated() {
			guard let t = Tile(rawValue: Tile.modBase + UInt8(i)) else { continue }
			proxy[p.key(b.id)] = t
			colour[t.rawValue] = averageColor(b.art)
		}
		let rt = ModDimRT(key: p.key(d.id), slot: 0, def: d, resolve: { k in
			if k.hasPrefix("tile:") {
				guard let n = Int(k.dropFirst(5)) else { return nil }
				return Tile(rawValue: UInt8(clampI(n, 0, 255)))
			}
			return proxy[k]
		}, trees: p.trees)
		let H: Int = customDimH
		let rows: Int = (H + 1) / 2
		var b = PixelBuf(w: chunks * chunkW, h: rows)
		for c in 0..<chunks {
			let ch = Chunk(cx: c - chunks / 2, H: H)
			fillCustomChunk(seed, true, 0, rt, ch)
			for lx in 0..<chunkW {
				for r in 0..<rows {
					let y: Int = r * 2
					let t: Tile = ch.get(lx, y)
					var col: UInt32 = 0
					if t == .air {
						if d.ceiling && y < ch.ceilY[lx] + 2 { col = shadeRGB(d.nightBottom, 0.8) }
						else if y < ch.surf[lx] { col = mixRGB(d.skyTop, d.skyBottom, Double(y) / Double(max(1, ch.surf[lx]))) }
						else { col = 0x16161C }
					} else if t == .water {
						col = 0x2E5FD0
					} else if t == .lava {
						col = 0xE8601A
					} else if let mc = colour[t.rawValue] {
						col = mc
					} else {
						col = shadeRGB(t.def.colors.first ?? 0x808080, 0.85)
					}
					b.set(c * chunkW + lx, r, col)
				}
			}
		}
		return b
	}

	static func averageColor(_ p: ModPixels) -> UInt32 {
		var r: Int = 0
		var g: Int = 0
		var bl: Int = 0
		var n: Int = 0
		for y in 0..<p.h {
			for x in 0..<p.w {
				let c: UInt32 = p.argb(x, y)
				if c >> 24 < 128 { continue }
				r += Int((c >> 16) & 0xFF)
				g += Int((c >> 8) & 0xFF)
				bl += Int(c & 0xFF)
				n += 1
			}
		}
		if n == 0 { return 0x808080 }
		return (UInt32(r / n) << 16) | (UInt32(g / n) << 8) | UInt32(bl / n)
	}
}

extension ModValidator {
	/// One summoning's settings kept in range (a creature's, or a dimension's way in); returns what was wrong
	static func fixSummon(_ s: inout ModSummon, _ p: ModPack, _ known: [String: String]) -> [String] {
		var notes: [String] = []
		let ownItems: Set<String> = Set(p.items.map { p.key($0.id) } + p.infusions.map { p.key($0.id) })
		let ownBlocks: Set<String> = Set(p.blocks.map { p.key($0.id) })
		let ownDims: Set<String> = Set(p.dims.map { p.key($0.id) })
		s.message = String(s.message.prefix(80))
		s.time = clampI(s.time, 0, 2)
		s.weather = clampI(s.weather, 0, 4)
		s.place = clampI(s.place, 0, 2)
		s.appear = clampI(s.appear, 0, 1)
		s.biomes = Array(Set(s.biomes.filter { Biome(rawValue: $0) != nil })).sorted()
		s.dims = Array(Set(s.dims.filter { $0 >= 0 && $0 <= 1 })).sorted()
		s.dimKeys = Array(s.dimKeys.filter { ownDims.contains($0) || known[$0] == "dimension" }.prefix(3))
		var pt: ModPattern = s.pattern
		pt.w = clampI(pt.w, 1, ModPattern.maxSide)
		pt.h = clampI(pt.h, 1, ModPattern.maxSide)
		var cells: [String] = Array(pt.cells.prefix(pt.w * pt.h))
		while cells.count < pt.w * pt.h { cells.append("") }
		var broken: Bool = false
		for j in cells.indices {
			let key: String = cells[j]
			if key.isEmpty || key == "air" { continue }
			if key.hasPrefix("tile:") {
				if let n = Int(key.dropFirst(5)), n >= 0 && n <= 255, let t = Tile(rawValue: UInt8(n)), t != .air, !t.isMod { continue }
			} else if ownBlocks.contains(key) || known[key] == "block" {
				continue
			}
			cells[j] = ""
			broken = true
		}
		pt.cells = cells
		s.pattern = pt
		if broken { notes.append("A block in a shape does not exist; that cell now takes anything.") }
		if s.usesPattern && pt.blockCells == 0 && s.enabled {
			notes.append("A way that uses a shape needs at least one block in it; it is switched off.")
			s.enabled = false
		}
		if s.usesItem {
			if let it = s.item, case .custom(let key) = it, !ownItems.contains(key) && known[key] != "item" { s.item = nil }
			if s.item == nil && s.enabled {
				notes.append("A way that uses an item needs an item that exists; it is switched off.")
				s.enabled = false
			}
		}
		return notes
	}

	/// Custom dimensions: numbers in range, blocks and creatures real, a way in and a way back
	static func checkDims(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		p.skySun?.clamp()
		p.skyMoon?.clamp()
		checkTrees(&p, mn, known, &r)
		if p.dims.count > 3 {
			r.add(1, mn, "Mod", "Only 3 dimensions fit in one mod; the rest were left out.")
			p.dims = Array(p.dims.prefix(3))
		}
		let ownBlocks: Set<String> = Set(p.blocks.map { p.key($0.id) })
		let ownMobs: Set<String> = Set(p.mobs.map { p.key($0.id) })
		let gameNames: Set<String> = Set(MobKind.allCases.filter { $0 != .custom && $0 != .villager }.map { mobDef($0).name })
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.infusions.map { $0.id })
		func c(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double { return clampD(v.isFinite ? v : d, lo, hi) }
		func block(_ k: String, _ d: String, _ allowEmpty: Bool) -> String {
			if k.isEmpty { return allowEmpty ? "" : d }
			if k.hasPrefix("tile:") {
				if let n = Int(k.dropFirst(5)), n > 0 && n <= 255, let t = Tile(rawValue: UInt8(n)), !t.isMod, t != .air { return k }
				return allowEmpty ? "" : d
			}
			if ownBlocks.contains(k) || known[k] == "block" { return k }
			return allowEmpty ? "" : d
		}
		for i in p.dims.indices {
			var d: ModDimension = p.dims[i]
			if d.id.isEmpty || used.contains(d.id) { d.id = joinText("dim", String(i + 1), "x", String(used.count)) }
			used.insert(d.id)
			let place: String = joinText("Dimension \u{201C}", d.name, "\u{201D}")
			if d.name.trimmingCharacters(in: .whitespaces).isEmpty { d.name = "Dimension" }
			d.name = String(d.name.prefix(32))
			d.desc = String(d.desc.prefix(200))
			d.arriveMessage = String(d.arriveMessage.prefix(80))
			d.light = c(d.light, 0, 1, 0.8)
			d.fixedTime = c(d.fixedTime, 0, 1, 0.25)
			d.sunBody?.clamp()
			d.moonBody?.clamp()
			d.ambient = clampI(d.ambient, 0, ModDimText.ambients.count - 1)
			d.weather = clampI(d.weather, 0, ModDimText.weathers.count - 1)
			d.chill = c(d.chill, 0, 1, 0)
			d.surface = clampI(d.surface, d.ceiling ? 80 : 40, 260)
			d.hills = c(d.hills, 0, 40, 12)
			d.roughness = c(d.roughness, 0.2, 3, 1)
			d.mountains = c(d.mountains, 0, 1, 0)
			d.caves = c(d.caves, 0, 1, 0.4)
			d.islands = c(d.islands, 0, 1, 0)
			d.sea = d.sea <= 0 ? 0 : clampI(d.sea, 60, 280)
			d.liquid = clampI(d.liquid, 0, 1)
			d.stone = block(d.stone, ModGround.key(.stone), false)
			if d.zones.isEmpty { d.zones = [ModDimZone()] }
			if d.zones.count > 4 {
				r.add(1, mn, place, "Only 4 regions fit; the rest were left out.")
				d.zones = Array(d.zones.prefix(4))
			}
			for k in d.zones.indices {
				var z: ModDimZone = d.zones[k]
				z.name = String(z.name.prefix(24))
				if Biome(rawValue: z.biome) == nil { z.biome = Biome.plains.rawValue }
				z.ground = block(z.ground, ModGround.key(.grass), false)
				z.filler = block(z.filler, ModGround.key(.dirt), false)
				z.plant = block(z.plant, "", true)
				z.plantChance = c(z.plantChance, 0, 0.8, 0.1)
				z.trees = clampI(z.trees, 0, 2)
				z.log = block(z.log, ModGround.key(.log), false)
				z.leaves = block(z.leaves, ModGround.key(.leaves), false)
				var kinds: [String] = []
				for tid in z.treeKinds where !kinds.contains(tid) && p.trees.contains(where: { $0.id == tid }) { kinds.append(tid) }
				z.treeKinds = Array(kinds.prefix(ModTree.maxDesigns))
				d.zones[k] = z
			}
			d.zoneWidth = clampI(d.zoneWidth, 40, 2000)
			d.hazard = block(d.hazard, "", true)
			d.hazardChance = c(d.hazardChance, 0, 0.3, 0.02)
			if d.spawns.count > 8 {
				r.add(1, mn, place, "Only 8 kinds of creature fit; the rest were left out.")
				d.spawns = Array(d.spawns.prefix(8))
			}
			var keep: [ModDimSpawn] = []
			for var s in d.spawns {
				if !gameNames.contains(s.creature) && !ownMobs.contains(s.creature) && known[s.creature] != "mob" {
					r.add(1, mn, place, "A creature it spawns does not exist; it was left out.")
					continue
				}
				s.place = clampI(s.place, 0, 2)
				s.when = clampI(s.when, 0, 2)
				s.weight = c(s.weight, 0.1, 20, 5)
				s.group = clampI(s.group, 1, 4)
				keep.append(s)
			}
			d.spawns = keep
			d.gateBlock = block(d.gateBlock, "", true)
			if d.gateBlock.hasPrefix("tile:") { d.gateBlock = "" }
			for n in fixSummon(&d.entry, p, known) { r.add(1, mn, place, n) }
			if !d.entry.enabled { r.add(1, mn, place, "It has no way in that works yet: players can only reach it from the Mod Test tools.") }
			if !d.entry.usesItem && !d.returnGate {
				d.returnGate = true
				r.add(1, mn, place, "Without an item to use again, the way back is the gate; it was switched on.")
			}
			p.dims[i] = d
		}
	}
}

extension ModValidator {
	/// A mod's tree designs kept in range: blocks that exist (never air or a liquid), sizes the generator
	/// can grow, a painted design of a size that fits
	static func checkTrees(_ p: inout ModPack, _ mn: String, _ known: [String: String], _ r: inout ModReport) {
		if p.trees.count > ModTree.maxDesigns {
			r.add(1, mn, "Mod", joinText("Only ", String(ModTree.maxDesigns), " tree designs fit in one mod; the rest were left out."))
			p.trees = Array(p.trees.prefix(ModTree.maxDesigns))
		}
		let ownBlocks: Set<String> = Set(p.blocks.map { p.key($0.id) })
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.infusions.map { $0.id } + p.dims.map { $0.id })
		func block(_ k: String, _ d: String, _ allowEmpty: Bool) -> String {
			if k.isEmpty { return allowEmpty ? "" : d }
			if k.hasPrefix("tile:") {
				if let n = Int(k.dropFirst(5)), n > 0 && n <= 255, let t = Tile(rawValue: UInt8(n)), !t.isMod, t != .air, !t.liquid { return k }
				return allowEmpty ? "" : d
			}
			if ownBlocks.contains(k) || known[k] == "block" { return k }
			return allowEmpty ? "" : d
		}
		for i in p.trees.indices {
			var t: ModTree = p.trees[i]
			if t.id.isEmpty || used.contains(t.id) { t.id = joinText("tree", String(i + 1), "x", String(used.count)) }
			used.insert(t.id)
			if t.name.trimmingCharacters(in: .whitespaces).isEmpty { t.name = "Tree" }
			t.name = String(t.name.prefix(24))
			let place: String = joinText("Tree \u{201C}", t.name, "\u{201D}")
			let trunk0: String = t.trunk
			let leaves0: String = t.leaves
			t.trunk = block(t.trunk, ModGround.key(.log), false)
			t.branch = block(t.branch, "", true)
			t.leaves = block(t.leaves, ModGround.key(.leaves), false)
			t.ground = block(t.ground, "", true)
			if t.trunk != trunk0 || t.leaves != leaves0 { r.add(1, mn, place, "A block it was made of does not exist (or is a liquid); the game's log and leaves stand in.") }
			t.minHeight = clampI(t.minHeight, 1, 24)
			t.maxHeight = clampI(t.maxHeight, t.minHeight, 24)
			t.crown = clampI(t.crown, 0, 6)
			t.branches = clampI(t.branches, 0, 4)
			t.density = clampD(t.density.isFinite ? t.density : 0.9, 0.2, 1)
			t.weight = clampD(t.weight.isFinite ? t.weight : 1, 0.1, 20)
			var g: ModTreeGrid = t.grid
			if !g.valid {
				g = g.cells.isEmpty ? ModTreeGrid() : g.resized(g.w, g.h)
				if !g.valid { g = ModTreeGrid() }
			}
			for k in g.cells.indices where g.cells[k] > 3 { g.cells[k] = 0 }
			t.grid = g
			if t.shape == .painted && !g.cells.contains(where: { $0 != 0 }) { r.add(1, mn, place, "Its painted design is empty, so it grows nothing.") }
			p.trees[i] = t
		}
	}
}

// MARK: - Mod Creator+: Logic Studio (optional visual scripting)
//
// Scripts are data: stacks of blocks chosen from the lists below, nothing else. The game turns each into
// a short list of steps and runs it with its own interpreter, a little at a time each frame: a script
// can't run forever without waiting, call itself too deeply, reach outside the game, or crash it. Every
// number a block uses is kept in range, and anything it names (a block, an item, a creature) is looked up
// safely; what is missing is skipped and reported in the Mod Test tools' LOGIC tab.

/// What starts a script
enum LEvent: Int, Codable, CaseIterable {
	case worldStart, every, nightFalls, dayBreaks, custom, playerHurt, enterDim
	case spawned, hurt, dies, creatureEvery, phase
	case itemUsed, blockPlaced, blockBroken, blockTapped
	/// not an event: a group of blocks other scripts run ("run group")
	case group

	var name: String {
		switch self {
		case .worldStart: return "When the world starts"
		case .every: return "Every few seconds"
		case .nightFalls: return "When night falls"
		case .dayBreaks: return "When day breaks"
		case .custom: return "When I receive a message"
		case .playerHurt: return "When the player is hurt"
		case .enterDim: return "When the player enters a dimension"
		case .spawned: return "When my creature appears"
		case .hurt: return "When my creature is hurt"
		case .dies: return "When my creature is beaten"
		case .creatureEvery: return "Every few seconds, for each of my creatures"
		case .phase: return "When my creature enters a phase"
		case .itemUsed: return "When my item is used"
		case .blockPlaced: return "When my block is placed"
		case .blockBroken: return "When my block is broken"
		case .blockTapped: return "When my block is tapped"
		case .group: return "A group of blocks (run by other scripts)"
		}
	}
	/// what the script is about: 0 the world, 1 a creature, 2 an item, 3 a block
	var subject: Int {
		switch self {
		case .spawned, .hurt, .dies, .creatureEvery, .phase: return 1
		case .itemUsed: return 2
		case .blockPlaced, .blockBroken, .blockTapped: return 3
		default: return 0
		}
	}
}

/// A block's command
enum LOp: Int, Codable, CaseIterable {
	case ifThen, ifElse, repeatN, whileDo, forever, wait, stop, broadcast, runGroup, log
	case setVar, changeVar
	case say, floatText, particles, sound, shake, flash
	case jump, dash, stepToPlayer, teleportNear, facePlayer
	case hurtPlayer, healPlayer, hurtSelf, healSelf, hurtNearby, explode, fireShot, summon
	case giveEffect, placeBlock, breakBlock, setTime, giveItem, takeItem, enterPhase
}

/// A reporter (a value a block reads)
enum LEOp: Int, Codable, CaseIterable {
	case num, variable, param, random, add, sub, mul, div, mod, lt, gt, eq, and, or, not
	case playerHP, playerMaxHP, selfHP, selfHPPct, distance, timeOfDay, isNight, itemCount
	case playerX, playerY, selfX, selfY, nearby, inDim, inBiome, raining
}

/// A value: a number, a variable, or a reporter with its inputs
struct LExpr: Codable, Equatable {
	var op: LEOp = .num
	var v: Double = 0
	var s: String = ""
	var item: Item? = nil
	var args: [LExpr] = []

	init() {}
	init(_ v: Double) { self.v = v }
	init(op: LEOp, args: [LExpr] = []) {
		self.op = op
		self.args = args
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		op = c.val(.op, .num)
		v = c.val(.v, 0)
		s = c.val(.s, "")
		item = c.val(.item, nil)
		args = c.val(.args, [])
	}
}

/// One block of a script; `body` and `alt` hold the blocks inside an if, a loop or an else
struct LNode: Codable, Equatable {
	var op: LOp = .say
	var a: Double = 0
	var b: Double = 0
	var c: Double = 0
	var s: String = ""
	var item: Item? = nil
	var args: [LExpr] = []
	var body: [LNode] = []
	var alt: [LNode] = []

	init() {}
	init(_ op: LOp) {
		self.op = op
		let sp: LSpec = LSpec.of(op)
		for f in sp.fields {
			switch f.kind {
			case .number:
				if f.slot == 0 { a = f.def } else if f.slot == 1 { b = f.def } else { c = f.def }
			case .choice:
				if f.slot == 0 { a = f.def } else if f.slot == 1 { b = f.def } else { c = f.def }
			case .expr:
				while args.count <= f.slot { args.append(LExpr(0)) }
				args[f.slot] = LExpr(f.def)
			case .text: s = f.label == "" ? "" : s
			default: break
			}
		}
		if op == .say || op == .floatText { s = "Hello!" }
		if op == .log { s = "Here" }
	}

	init(from decoder: Decoder) throws {
		let c0 = try decoder.container(keyedBy: CodingKeys.self)
		op = c0.val(.op, .say)
		a = c0.val(.a, 0)
		b = c0.val(.b, 0)
		c = c0.val(.c, 0)
		s = c0.val(.s, "")
		item = c0.val(.item, nil)
		args = c0.val(.args, [])
		body = c0.val(.body, [])
		alt = c0.val(.alt, [])
	}
}

/// A script: what starts it, what it is about, and its blocks
struct ModScript: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "Script"
	var enabled: Bool = true
	var event: LEvent = .worldStart
	/// the event's number: seconds (every), a phase
	var ev: Double = 5
	/// the event's text: a message name, a dimension key
	var evText: String = ""
	/// the creature, item or block it belongs to (this mod's, "mod:id")
	var target: String = ""
	var blocks: [LNode] = []
	/// a group's inputs (up to three names)
	var params: [String] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Script")
		enabled = c.val(.enabled, true)
		event = c.val(.event, .worldStart)
		ev = c.val(.ev, 5)
		evText = c.val(.evText, "")
		target = c.val(.target, "")
		blocks = c.val(.blocks, [])
		params = c.val(.params, [])
	}
}

// MARK: the block catalogue (shared by the editor, the checks and the interpreter)

enum LCat: Int, CaseIterable {
	case control, looks, movement, combat, world, items, variables
	var name: String {
		switch self {
		case .control: return "CONTROL"
		case .looks: return "LOOKS & SOUND"
		case .movement: return "MOVEMENT"
		case .combat: return "COMBAT"
		case .world: return "WORLD"
		case .items: return "ITEMS & EFFECTS"
		case .variables: return "VARIABLES"
		}
	}
	var color: UInt32 {
		switch self {
		case .control: return 0xD8A030
		case .looks: return 0x9A6AE0
		case .movement: return 0x4A8AE0
		case .combat: return 0xD85A4A
		case .world: return 0x4AAA5A
		case .items: return 0x3AB0B0
		case .variables: return 0xE07A30
		}
	}
}

enum LFieldKind {
	case number, text, key, item, expr, choice
}

/// One input of a block: what it holds and where (slot: a b c for numbers, the argument for values)
struct LField {
	let kind: LFieldKind
	let slot: Int
	let label: String
	var lo: Double = 0
	var hi: Double = 100
	var def: Double = 0
	/// for keys: 0 creature, 1 block, 2 shot, 3 message, 4 variable, 5 group, 6 dimension
	/// for choices: 0 sound, 1 effect, 2 game shot
	var list: Int = 0
}

struct LSpec {
	let op: LOp
	let cat: LCat
	let title: String
	let fields: [LField]
	/// 0 no blocks inside, 1 blocks inside, 2 blocks inside and an else
	var inside: Int = 0
	/// it needs a creature to act on
	var creature: Bool = false

	static let all: [LSpec] = [
		LSpec(op: .ifThen, cat: .control, title: "if", fields: [LField(kind: .expr, slot: 0, label: "this is true", def: 1)], inside: 1),
		LSpec(op: .ifElse, cat: .control, title: "if, else", fields: [LField(kind: .expr, slot: 0, label: "this is true", def: 1)], inside: 2),
		LSpec(op: .repeatN, cat: .control, title: "repeat", fields: [LField(kind: .expr, slot: 0, label: "times", def: 3)], inside: 1),
		LSpec(op: .whileDo, cat: .control, title: "repeat while", fields: [LField(kind: .expr, slot: 0, label: "this is true", def: 1)], inside: 1),
		LSpec(op: .forever, cat: .control, title: "forever", fields: [], inside: 1),
		LSpec(op: .wait, cat: .control, title: "wait", fields: [LField(kind: .expr, slot: 0, label: "seconds", def: 1)]),
		LSpec(op: .stop, cat: .control, title: "stop this script", fields: []),
		LSpec(op: .broadcast, cat: .control, title: "send a message", fields: [LField(kind: .key, slot: 0, label: "message", list: 3)]),
		LSpec(op: .runGroup, cat: .control, title: "run a group", fields: [LField(kind: .key, slot: 0, label: "group", list: 5), LField(kind: .expr, slot: 0, label: "input 1"),
																			LField(kind: .expr, slot: 1, label: "input 2"), LField(kind: .expr, slot: 2, label: "input 3")]),
		LSpec(op: .log, cat: .control, title: "note in the test log", fields: [LField(kind: .text, slot: 0, label: "text"), LField(kind: .expr, slot: 0, label: "value")]),
		LSpec(op: .setVar, cat: .variables, title: "set variable", fields: [LField(kind: .key, slot: 0, label: "variable", list: 4), LField(kind: .expr, slot: 0, label: "to")]),
		LSpec(op: .changeVar, cat: .variables, title: "change variable", fields: [LField(kind: .key, slot: 0, label: "variable", list: 4), LField(kind: .expr, slot: 0, label: "by", def: 1)]),
		LSpec(op: .say, cat: .looks, title: "show a message", fields: [LField(kind: .text, slot: 0, label: "text"), LField(kind: .number, slot: 0, label: "seconds", lo: 0.5, hi: 10, def: 3)]),
		LSpec(op: .floatText, cat: .looks, title: "float text over it", fields: [LField(kind: .text, slot: 0, label: "text"), LField(kind: .number, slot: 0, label: "colour", lo: 0, hi: 7, def: 0)]),
		LSpec(op: .particles, cat: .looks, title: "sparkle", fields: [LField(kind: .number, slot: 0, label: "colour", lo: 0, hi: 7, def: 2), LField(kind: .number, slot: 1, label: "how many", lo: 1, hi: 40, def: 12)]),
		LSpec(op: .sound, cat: .looks, title: "play a sound", fields: [LField(kind: .choice, slot: 0, label: "sound", def: 0, list: 0)]),
		LSpec(op: .shake, cat: .looks, title: "shake the screen", fields: [LField(kind: .number, slot: 0, label: "strength", lo: 0.05, hi: 1, def: 0.3)]),
		LSpec(op: .flash, cat: .looks, title: "flash my creature", fields: [LField(kind: .number, slot: 0, label: "seconds", lo: 0.05, hi: 2, def: 0.3)], creature: true),
		LSpec(op: .jump, cat: .movement, title: "jump", fields: [LField(kind: .number, slot: 0, label: "strength", lo: 2, hi: 24, def: 12)], creature: true),
		LSpec(op: .dash, cat: .movement, title: "dash forward", fields: [LField(kind: .number, slot: 0, label: "speed", lo: 1, hi: 30, def: 12)], creature: true),
		LSpec(op: .stepToPlayer, cat: .movement, title: "lunge toward the player", fields: [LField(kind: .number, slot: 0, label: "speed", lo: 1, hi: 20, def: 6)], creature: true),
		LSpec(op: .teleportNear, cat: .movement, title: "appear beside the player", fields: [LField(kind: .number, slot: 0, label: "how far", lo: 2, hi: 12, def: 4)], creature: true),
		LSpec(op: .facePlayer, cat: .movement, title: "face the player", fields: [], creature: true),
		LSpec(op: .hurtPlayer, cat: .combat, title: "hurt the player", fields: [LField(kind: .expr, slot: 0, label: "damage", def: 4)]),
		LSpec(op: .healPlayer, cat: .combat, title: "heal the player", fields: [LField(kind: .expr, slot: 0, label: "health", def: 4)]),
		LSpec(op: .hurtSelf, cat: .combat, title: "hurt my creature", fields: [LField(kind: .expr, slot: 0, label: "damage", def: 4)], creature: true),
		LSpec(op: .healSelf, cat: .combat, title: "heal my creature", fields: [LField(kind: .expr, slot: 0, label: "health", def: 4)], creature: true),
		LSpec(op: .hurtNearby, cat: .combat, title: "hurt creatures nearby", fields: [LField(kind: .number, slot: 0, label: "how far", lo: 1, hi: 8, def: 3), LField(kind: .expr, slot: 0, label: "damage", def: 4)]),
		LSpec(op: .explode, cat: .combat, title: "blast (breaks no blocks)", fields: [LField(kind: .number, slot: 0, label: "size", lo: 1, hi: 4, def: 2), LField(kind: .number, slot: 1, label: "power", lo: 1, hi: 20, def: 6)]),
		LSpec(op: .fireShot, cat: .combat, title: "fire a shot at the player", fields: [LField(kind: .key, slot: 0, label: "mod shot (or none)", list: 2), LField(kind: .choice, slot: 1, label: "game shot", def: 2, list: 2),
																						 LField(kind: .number, slot: 0, label: "speed", lo: 4, hi: 30, def: 14), LField(kind: .number, slot: 2, label: "damage", lo: 0, hi: 30, def: 5)]),
		LSpec(op: .summon, cat: .combat, title: "call creatures", fields: [LField(kind: .key, slot: 0, label: "creature", list: 0), LField(kind: .number, slot: 0, label: "how many", lo: 1, hi: 4, def: 1)]),
		LSpec(op: .giveEffect, cat: .items, title: "give the player an effect", fields: [LField(kind: .choice, slot: 0, label: "effect", def: 2, list: 1), LField(kind: .number, slot: 1, label: "strength", lo: 0, hi: 100, def: 20),
																						 LField(kind: .number, slot: 2, label: "seconds", lo: 1, hi: 120, def: 10)]),
		LSpec(op: .placeBlock, cat: .world, title: "place a block", fields: [LField(kind: .key, slot: 0, label: "block", list: 1), LField(kind: .number, slot: 0, label: "across", lo: -8, hi: 8, def: 0),
																			LField(kind: .number, slot: 1, label: "up", lo: -8, hi: 8, def: 1)]),
		LSpec(op: .breakBlock, cat: .world, title: "break a block", fields: [LField(kind: .number, slot: 0, label: "across", lo: -8, hi: 8, def: 0), LField(kind: .number, slot: 1, label: "up", lo: -8, hi: 8, def: -1)]),
		LSpec(op: .setTime, cat: .world, title: "set the time of day", fields: [LField(kind: .number, slot: 0, label: "time (0.25 noon, 0.75 midnight)", lo: 0, hi: 1, def: 0.25)]),
		LSpec(op: .giveItem, cat: .items, title: "give the player items", fields: [LField(kind: .item, slot: 0, label: "item"), LField(kind: .number, slot: 0, label: "how many", lo: 1, hi: 64, def: 1)]),
		LSpec(op: .takeItem, cat: .items, title: "take items from the player", fields: [LField(kind: .item, slot: 0, label: "item"), LField(kind: .number, slot: 0, label: "how many", lo: 1, hi: 64, def: 1)]),
		LSpec(op: .enterPhase, cat: .combat, title: "move my creature to a phase", fields: [LField(kind: .number, slot: 0, label: "phase", lo: 1, hi: 6, def: 1)], creature: true),
	]

	static func of(_ op: LOp) -> LSpec {
		return all.first { $0.op == op } ?? LSpec(op: op, cat: .control, title: "?", fields: [])
	}
}

/// The reporters, by name, and how many values each takes
enum LReporters {
	static func name(_ op: LEOp) -> String {
		switch op {
		case .num: return "number"
		case .variable: return "variable"
		case .param: return "group input"
		case .random: return "random between"
		case .add: return "+"
		case .sub: return "\u{2212}"
		case .mul: return "\u{00D7}"
		case .div: return "\u{00F7}"
		case .mod: return "remainder"
		case .lt: return "<"
		case .gt: return ">"
		case .eq: return "="
		case .and: return "and"
		case .or: return "or"
		case .not: return "not"
		case .playerHP: return "player's health"
		case .playerMaxHP: return "player's most health"
		case .selfHP: return "my creature's health"
		case .selfHPPct: return "my creature's health %"
		case .distance: return "distance to the player"
		case .timeOfDay: return "time of day"
		case .isNight: return "it is night"
		case .itemCount: return "how many the player has of"
		case .playerX: return "player across"
		case .playerY: return "player up/down"
		case .selfX: return "my across"
		case .selfY: return "my up/down"
		case .nearby: return "creatures within"
		case .inDim: return "the player is in dimension"
		case .inBiome: return "the player is in biome"
		case .raining: return "it is raining or snowing"
		}
	}
	static func arity(_ op: LEOp) -> Int {
		switch op {
		case .random, .add, .sub, .mul, .div, .mod, .lt, .gt, .eq, .and, .or: return 2
		case .not: return 1
		default: return 0
		}
	}
	/// reporters that only make sense for a creature
	static func needsCreature(_ op: LEOp) -> Bool { return op == .selfHP || op == .selfHPPct }
	static let colours: [UInt32] = [0xFFFFFF, 0xFF5A4A, 0xFFD24A, 0x5AE070, 0x5AB8FF, 0xC070FF, 0xFF8A3A, 0x8A8A8A]
	static let sounds: [SoundID] = [.zap, .roar, .portal, .discovery, .warn, .explosion, .chestOpen, .craft, .infuse, .tap, .hit, .crit, .flask, .rareLoot]
	static let soundNames: [String] = ["Zap", "Roar", "Portal", "Discovery", "Warning", "Explosion", "Chest", "Craft", "Infuse", "Tap", "Hit", "Critical", "Flask", "Rare find"]
}

// MARK: the interpreter

/// A step of a compiled script
enum LInstr {
	case run(LNode)
	case jumpUnless(LExpr, Int)
	case jump(Int)
	case loopStart(Int, LExpr)
	case loopCheck(Int, Int)
	case wait(LExpr)
	case call(String, [LExpr])
	case stop
}

/// Limits that keep scripts from slowing or stopping the game
enum LLimits {
	static let maxThreads: Int = 32
	static let perScript: Int = 4
	static let stepsPerThread: Int = 300
	static let stepsPerFrame: Int = 3000
	static let maxDepth: Int = 8
	static let maxExprDepth: Int = 32
	static let maxRepeat: Int = 1000
	/// seconds a script may run without ever waiting before it is stopped
	static let noWaitLimit: Double = 10
	static let maxScripts: Int = 40
	static let maxBlocks: Int = 400
	static let maxVariables: Int = 16
}

extension LExpr {
	static var zero: LExpr { return LExpr(0) }
}

/// A script ready to run: its steps, its mod, what starts it
final class LProgram {
	let key: String
	let modID: String
	let name: String
	let def: ModScript
	var code: [LInstr] = []
	/// how many loop counters it needs
	var slots: Int = 0

	init(key: String, modID: String, def: ModScript) {
		self.key = key
		self.modID = modID
		self.name = def.name
		self.def = def
		var out: [LInstr] = []
		var n: Int = 0
		LProgram.compile(def.blocks, &out, &n)
		code = out
		slots = n
	}

	static func compile(_ list: [LNode], _ out: inout [LInstr], _ slots: inout Int) {
		for n in list {
			let cond: LExpr = n.args.first ?? LExpr.zero
			switch n.op {
			case .ifThen:
				let j: Int = out.count
				out.append(.jumpUnless(cond, -1))
				compile(n.body, &out, &slots)
				out[j] = .jumpUnless(cond, out.count)
			case .ifElse:
				let j: Int = out.count
				out.append(.jumpUnless(cond, -1))
				compile(n.body, &out, &slots)
				let k: Int = out.count
				out.append(.jump(-1))
				out[j] = .jumpUnless(cond, out.count)
				compile(n.alt, &out, &slots)
				out[k] = .jump(out.count)
			case .repeatN:
				let sl: Int = slots
				slots += 1
				out.append(.loopStart(sl, cond))
				let top: Int = out.count
				out.append(.loopCheck(sl, -1))
				compile(n.body, &out, &slots)
				out.append(.jump(top))
				out[top] = .loopCheck(sl, out.count)
			case .whileDo:
				let top: Int = out.count
				out.append(.jumpUnless(cond, -1))
				compile(n.body, &out, &slots)
				out.append(.jump(top))
				out[top] = .jumpUnless(cond, out.count)
			case .forever:
				let top: Int = out.count
				compile(n.body, &out, &slots)
				out.append(.jump(top))
			case .wait:
				out.append(.wait(cond))
			case .stop:
				out.append(.stop)
			case .runGroup:
				out.append(.call(n.s, n.args))
			default:
				out.append(.run(n))
			}
		}
	}
}

/// Where a running script is in one program (a group run from it gets a frame of its own)
struct LFrame {
	let prog: LProgram
	var pc: Int = 0
	var counters: [Int]
	var params: [Double]
}

/// One running script
final class LThread {
	let prog: LProgram
	let id: Int
	var frames: [LFrame]
	var waitT: Double = 0
	weak var mob: Mob? = nil
	var hasMob: Bool = false
	var bx: Int = 0
	var by: Int = 0
	var hasBlock: Bool = false
	var noWaitT: Double = 0
	var steps: Int = 0
	var done: Bool = false
	var error: String = ""

	init(_ p: LProgram, id: Int) {
		prog = p
		self.id = id
		frames = [LFrame(prog: p, pc: 0, counters: [Int](repeating: 0, count: p.slots), params: [0, 0, 0])]
	}

	/// where it is, for the step debugger ("Script name, step 3")
	var whereText: String {
		guard let f = frames.last else { return prog.name }
		return joinText(f.prog.name, ", step ", String(f.pc + 1), " of ", String(f.prog.code.count))
	}
}

/// The scripts of the world's mods, compiled once per world
final class LogicRT {
	var programs: [LProgram] = []
	var groups: [String: LProgram] = [:]
	/// programs by what starts them
	var byEvent: [LEvent: [LProgram]] = [:]

	var isEmpty: Bool { return programs.isEmpty }

	static func build(_ packs: [ModPack], _ off: Set<String>) -> LogicRT {
		let rt = LogicRT()
		for p in packs {
			for s in p.scripts where s.enabled && !off.contains(p.key(s.id)) {
				let prog = LProgram(key: p.key(s.id), modID: p.id, def: s)
				rt.programs.append(prog)
				if s.event == .group {
					rt.groups[p.key(s.id)] = prog
				} else {
					rt.byEvent[s.event, default: []].append(prog)
				}
			}
		}
		return rt
	}

	func listeners(_ e: LEvent) -> [LProgram] { return byEvent[e] ?? [] }
}

/// The running side of the Logic Studio in one game: running scripts, timers, the world's variables, the
/// test log, and the step debugger
final class LogicVM {
	var threads: [LThread] = []
	/// what the last scripts did (newest last), for the Mod Test tools
	var log: [String] = []
	var nextID: Int = 1
	var started: Bool = false
	var lastNight: Bool? = nil
	var timers: [String: Double] = [:]
	var mobTimers: [Int: Double] = [:]
	/// step debugger: scripts wait while paused; `stepOnce` lets one step through
	var paused: Bool = false
	var stepOnce: Bool = false
	var ran: Int = 0
	var errors: Int = 0

	func note(_ s: String) {
		log.append(s)
		if log.count > 60 { log.removeFirst(log.count - 60) }
	}
}

extension Game {
	// MARK: starting scripts

	var logicRT: LogicRT { return ModRuntime.shared.logic }

	/// Starts every script waiting for this event (that belongs to this subject)
	func fireLogic(_ e: LEvent, mob: Mob? = nil, x: Int = 0, y: Int = 0, block: Bool = false, key: String = "", text: String = "", number: Double = 0) {
		let rt: LogicRT = logicRT
		if rt.isEmpty { return }
		for p in rt.listeners(e) {
			let d: ModScript = p.def
			switch e.subject {
			case 1, 2, 3:
				if d.target != key { continue }
			default: break
			}
			if e == .custom && d.evText != text { continue }
			if e == .enterDim && !d.evText.isEmpty && d.evText != text { continue }
			if e == .phase && Int(d.ev.rounded()) != Int(number.rounded()) { continue }
			startThread(p, mob: mob, x: x, y: y, block: block)
		}
	}

	@discardableResult
	func startThread(_ p: LProgram, mob: Mob?, x: Int, y: Int, block: Bool) -> LThread? {
		let vm: LogicVM = logic
		if vm.threads.count >= LLimits.maxThreads {
			vm.note(joinText(p.name, ": not started, too many scripts are running at once."))
			return nil
		}
		var same: Int = 0
		for t in vm.threads where t.prog === p && !t.done { same += 1 }
		if same >= LLimits.perScript { return nil }
		let t = LThread(p, id: vm.nextID)
		vm.nextID += 1
		t.mob = mob
		t.hasMob = mob != nil
		t.bx = x
		t.by = y
		t.hasBlock = block
		vm.threads.append(t)
		vm.ran += 1
		return t
	}

	/// The clock of the Logic Studio: timed and time-of-day events, then a little of every running script
	func updateLogic(_ dt: Double) {
		let rt: LogicRT = logicRT
		let vm: LogicVM = logic
		if rt.isEmpty {
			if !vm.threads.isEmpty { vm.threads.removeAll() }
			return
		}
		// the step debugger stops the scripts' clock too: nothing new starts by time while paused
		if vm.paused {
			runLogic(dt)
			return
		}
		if !vm.started {
			vm.started = true
			fireLogic(.worldStart)
		}
		let night: Bool = isNight
		if let was = vm.lastNight, was != night { fireLogic(night ? .nightFalls : .dayBreaks) }
		vm.lastNight = night
		for p in rt.listeners(.every) {
			let gap: Double = clampD(p.def.ev, 0.25, 600)
			let next: Double = vm.timers[p.key] ?? (clock + gap)
			if clock >= next {
				vm.timers[p.key] = clock + gap
				startThread(p, mob: nil, x: 0, y: 0, block: false)
			} else if vm.timers[p.key] == nil {
				vm.timers[p.key] = next
			}
		}
		let each: [LProgram] = rt.listeners(.creatureEvery)
		if !each.isEmpty {
			for m in mobs where m.kind == .custom && m.hp > 0 && !m.removed {
				guard let r = ModRuntime.shared.mob(m.cslot) else { continue }
				for (i, p) in each.enumerated() where p.def.target == r.key {
					let k: Int = m.id &* 64 &+ i
					let gap: Double = clampD(p.def.ev, 0.25, 600)
					let next: Double = vm.mobTimers[k] ?? (clock + gap)
					if clock >= next {
						vm.mobTimers[k] = clock + gap
						startThread(p, mob: m, x: 0, y: 0, block: false)
					} else if vm.mobTimers[k] == nil {
						vm.mobTimers[k] = next
					}
				}
			}
			if vm.mobTimers.count > 400 { vm.mobTimers.removeAll() }
		}
		runLogic(dt)
	}

	/// Runs a little of each script (all of them wait while the step debugger is paused)
	func runLogic(_ dt: Double) {
		let vm: LogicVM = logic
		if vm.threads.isEmpty { return }
		if vm.paused {
			if !vm.stepOnce { return }
			vm.stepOnce = false
			if let t = vm.threads.first(where: { !$0.done }) {
				if t.waitT > 0 { t.waitT = 0 }
				logicStep(t)
			}
			vm.threads.removeAll { $0.done }
			return
		}
		var budget: Int = LLimits.stepsPerFrame
		for t in vm.threads where !t.done {
			if t.hasMob {
				// a creature's script ends with the creature (its "beaten" script still runs)
				if t.mob == nil || t.mob!.removed || (t.mob!.hp <= 0 && t.prog.def.event != .dies) {
					t.done = true
					continue
				}
			}
			if t.waitT > 0 {
				t.waitT -= dt
				t.noWaitT = 0
				continue
			}
			var n: Int = 0
			while n < LLimits.stepsPerThread && budget > 0 && !t.done && t.waitT <= 0 {
				logicStep(t)
				n += 1
				budget -= 1
			}
			if n >= LLimits.stepsPerThread {
				t.noWaitT += dt
				if t.noWaitT > LLimits.noWaitLimit {
					logicFail(t, "It ran for 10 seconds without waiting, so it was stopped. Put a \u{201C}wait\u{201D} inside loops that go on.")
				}
			}
			if budget <= 0 { break }
		}
		vm.threads.removeAll { $0.done }
	}

	func logicFail(_ t: LThread, _ why: String) {
		t.error = why
		t.done = true
		logic.errors += 1
		logic.note(joinText("\u{26A0} ", t.prog.name, ": ", why))
	}

	/// One step of a running script
	func logicStep(_ t: LThread) {
		guard !t.frames.isEmpty else {
			t.done = true
			return
		}
		let fi: Int = t.frames.count - 1
		let code: [LInstr] = t.frames[fi].prog.code
		let pc: Int = t.frames[fi].pc
		if pc >= code.count || pc < 0 {
			t.frames.removeLast()
			if t.frames.isEmpty { t.done = true }
			return
		}
		t.frames[fi].pc = pc + 1
		t.steps += 1
		switch code[pc] {
		case .run(let n):
			logicExec(t, n)
		case .jumpUnless(let e, let to):
			if logicEval(t, e, 0) == 0 { t.frames[fi].pc = to }
		case .jump(let to):
			t.frames[fi].pc = to
		case .loopStart(let sl, let e):
			if sl < t.frames[fi].counters.count { t.frames[fi].counters[sl] = clampI(Int(logicEval(t, e, 0).rounded()), 0, LLimits.maxRepeat) }
		case .loopCheck(let sl, let to):
			if sl >= t.frames[fi].counters.count || t.frames[fi].counters[sl] <= 0 {
				t.frames[fi].pc = to
			} else {
				t.frames[fi].counters[sl] -= 1
			}
		case .wait(let e):
			t.waitT = clampD(logicEval(t, e, 0), 0.05, 60)
			t.noWaitT = 0
		case .call(let name, let args):
			guard let g = logicRT.groups[name] else {
				logic.note(joinText(t.prog.name, ": the group it runs is missing; skipped."))
				return
			}
			if t.frames.count >= LLimits.maxDepth {
				logicFail(t, "Groups ran each other too deeply (more than 8 inside one another).")
				return
			}
			var ps: [Double] = [0, 0, 0]
			for k in 0..<min(3, args.count) { ps[k] = logicEval(t, args[k], 0) }
			t.frames.append(LFrame(prog: g, pc: 0, counters: [Int](repeating: 0, count: g.slots), params: ps))
		case .stop:
			t.done = true
		}
	}

	// MARK: values

	/// Where a script's subject is: its creature, its block, or the player
	func logicPos(_ t: LThread) -> (Double, Double) {
		if t.hasMob, let m = t.mob { return (m.b.x, m.b.cy) }
		if t.hasBlock { return (Double(t.bx) + 0.5, Double(t.by) + 0.5) }
		return (pb.x, pb.y - pb.h * 0.5)
	}

	func logicVarKey(_ t: LThread, _ name: String) -> String { return joinText(t.prog.modID, ":", name) }

	func logicEval(_ t: LThread, _ e: LExpr, _ depth: Int) -> Double {
		if depth > LLimits.maxExprDepth { return 0 }
		func arg(_ i: Int) -> Double { return i < e.args.count ? logicEval(t, e.args[i], depth + 1) : 0 }
		var v: Double = 0
		switch e.op {
		case .num: v = e.v
		case .variable: v = logicVars[logicVarKey(t, e.s)] ?? 0
		case .param:
			let k: Int = Int(e.v.rounded()) - 1
			if let f = t.frames.last, k >= 0 && k < f.params.count { v = f.params[k] }
		case .random:
			let a: Double = arg(0)
			let b: Double = arg(1)
			v = a == b ? a : Double.random(in: min(a, b)...max(a, b))
		case .add: v = arg(0) + arg(1)
		case .sub: v = arg(0) - arg(1)
		case .mul: v = arg(0) * arg(1)
		case .div:
			let d: Double = arg(1)
			v = d == 0 ? 0 : arg(0) / d
		case .mod:
			let d: Double = arg(1)
			v = d == 0 ? 0 : fmod(arg(0), d)
		case .lt: v = arg(0) < arg(1) ? 1 : 0
		case .gt: v = arg(0) > arg(1) ? 1 : 0
		case .eq: v = abs(arg(0) - arg(1)) < 0.0001 ? 1 : 0
		case .and: v = arg(0) != 0 && arg(1) != 0 ? 1 : 0
		case .or: v = arg(0) != 0 || arg(1) != 0 ? 1 : 0
		case .not: v = arg(0) == 0 ? 1 : 0
		case .playerHP: v = hp
		case .playerMaxHP: v = maxHP
		case .selfHP: v = t.mob?.hp ?? 0
		case .selfHPPct:
			if let m = t.mob, m.maxHP > 0 { v = m.hp / m.maxHP * 100.0 }
		case .distance:
			let p: (Double, Double) = logicPos(t)
			let dx: Double = p.0 - pb.x
			let dy: Double = p.1 - (pb.y - pb.h * 0.5)
			v = sqrt(dx * dx + dy * dy)
		case .timeOfDay: v = timeOfDay
		case .isNight: v = isNight ? 1 : 0
		case .itemCount: v = e.item.map { Double(inv.total($0)) } ?? 0
		case .playerX: v = pb.x
		case .playerY: v = pb.y
		case .selfX: v = logicPos(t).0
		case .selfY: v = logicPos(t).1
		case .nearby:
			let p: (Double, Double) = logicPos(t)
			let r: Double = clampD(e.v, 1, 30)
			var n: Int = 0
			for m in mobsNear(p.0 - r, p.0 + r) where m.hp > 0 && !m.removed && m !== t.mob {
				if abs(m.b.cy - p.1) <= r { n += 1 }
			}
			v = Double(n)
		case .inDim:
			if e.s == "overworld" { v = world.dim == .overworld ? 1 : 0 }
			else if e.s == "umbral" { v = world.dim == .umbral ? 1 : 0 }
			else { v = customDim?.key == e.s ? 1 : 0 }
		case .inBiome: v = biomeAt(pb.x).rawValue == Int(e.v.rounded()) ? 1 : 0
		case .raining: v = wxHere.precip > 0.2 ? 1 : 0
		}
		return v.isFinite ? v : 0
	}

	// MARK: commands

	func logicExec(_ t: LThread, _ n: LNode) {
		let sp: LSpec = LSpec.of(n.op)
		if sp.creature && t.mob == nil {
			logic.note(joinText(t.prog.name, ": \u{201C}", sp.title, "\u{201D} needs a creature; skipped."))
			return
		}
		func arg(_ i: Int) -> Double { return i < n.args.count ? logicEval(t, n.args[i], 0) : 0 }
		let pos: (Double, Double) = logicPos(t)
		let sb: Bool = ModRuntime.shared.packs.first { $0.id == t.prog.modID }?.sandbox ?? false
		let maxDmg: Double = sb ? 200 : 50
		switch n.op {
		case .broadcast:
			if !n.s.isEmpty { fireLogic(.custom, text: n.s) }
		case .log:
			let val: String = n.args.isEmpty ? "" : joinText(" = ", String(format: "%.2f", arg(0)))
			logic.note(joinText(t.prog.name, ": ", String(n.s.prefix(60)), val))
		case .setVar:
			if !n.s.isEmpty { logicVars[logicVarKey(t, n.s)] = clampD(arg(0), -1e9, 1e9) }
		case .changeVar:
			if !n.s.isEmpty {
				let k: String = logicVarKey(t, n.s)
				logicVars[k] = clampD((logicVars[k] ?? 0) + arg(0), -1e9, 1e9)
			}
		case .say:
			say(String(n.s.prefix(80)), clampD(n.a, 0.5, 10))
		case .floatText:
			let col: UInt32 = LReporters.colours[clampI(Int(n.a), 0, LReporters.colours.count - 1)]
			floatText(String(n.s.prefix(24)), pos.0, pos.1 - 1.0, col)
		case .particles:
			let col: UInt32 = LReporters.colours[clampI(Int(n.a), 0, LReporters.colours.count - 1)]
			spawnParticles(pos.0, pos.1, col, clampI(Int(n.b), 1, 40), 4.0, 0.6, 2)
		case .sound:
			let i: Int = clampI(Int(n.a), 0, LReporters.sounds.count - 1)
			sfx(LReporters.sounds[i], at: pos.0, 0.8)
		case .shake:
			addShake(clampD(n.a, 0, 1))
		case .flash:
			if let m = t.mob { m.flash = clampD(n.a, 0.05, 2) }
		case .jump:
			// on the ground, flying, or standing still (one that has just appeared has not landed yet)
			if let m = t.mob, m.b.onGround || m.def.flying || abs(m.b.vy) < 0.5 { m.b.vy = -clampD(n.a, 2, 24) }
		case .dash:
			if let m = t.mob { m.b.vx = Double(m.dir) * clampD(n.a, 1, 30) }
		case .stepToPlayer:
			if let m = t.mob {
				m.dir = pb.x >= m.b.x ? 1 : -1
				m.b.vx = Double(m.dir) * clampD(n.a, 1, 20)
			}
		case .teleportNear:
			if let m = t.mob {
				let d: Double = clampD(n.a, 2, 12)
				let side: Double = m.b.x >= pb.x ? 1.0 : -1.0
				for k in 0..<2 {
					let x: Double = pb.x + (k == 0 ? side : -side) * d
					if let y = roomNear(x, pb.y, m.b.w, m.b.h) {
						spawnParticles(m.b.x, m.b.cy, 0xC070FF, 10, 3.0, 0.5, 0)
						m.b.x = x
						m.b.y = y
						m.b.vx = 0
						m.b.vy = 0
						m.dir = pb.x >= x ? 1 : -1
						spawnParticles(x, y - m.b.h * 0.5, 0xC070FF, 10, 3.0, 0.5, 0)
						break
					}
				}
			}
		case .facePlayer:
			if let m = t.mob { m.dir = pb.x >= m.b.x ? 1 : -1 }
		case .hurtPlayer:
			let d: Double = clampD(arg(0), 0, maxDmg)
			if d > 0 {
				var info = DamageInfo(amount: d, type: .magic, source: t.mob.map { DamageSource.mob($0, faction(of: $0)) } ?? .environment)
				info.originX = pos.0
				info.originY = pos.1
				info.key = newID()
				_ = hurtPlayer(info)
			}
		case .healPlayer:
			let h: Double = clampD(arg(0), 0, maxDmg)
			if h > 0 && !dead { heal(h) }
		case .hurtSelf:
			if let m = t.mob {
				let d: Double = clampD(arg(0), 0, maxDmg * 4)
				if d > 0 { hurtMob(m, d, 0, 0, false) }
			}
		case .healSelf:
			if let m = t.mob, m.hp > 0 { m.hp = min(m.maxHP, m.hp + clampD(arg(0), 0, maxDmg * 4)) }
		case .hurtNearby:
			let r: Double = clampD(n.a, 1, 8)
			let d: Double = clampD(arg(0), 0, maxDmg)
			if d > 0 {
				var info = DamageInfo(amount: d, type: .magic, source: .player)
				info.key = newID()
				info.originX = pos.0
				info.originY = pos.1
				for m in mobsNear(pos.0 - r, pos.0 + r) where m.hp > 0 && !m.removed && !m.tame && m !== t.mob {
					if abs(m.b.cy - pos.1) <= r + m.b.h * 0.5 { applyMobDamage(m, info) }
				}
			}
		case .explode:
			let src: DamageSource = t.mob.map { DamageSource.mob($0, faction(of: $0)) } ?? .environment
			explode(pos.0, pos.1, radius: clampD(n.a, 1, 4), power: clampD(n.b, 1, 20), source: src, breakBlocks: false)
		case .fireShot:
			logicShot(t, n, pos)
		case .summon:
			let rt: ModRuntime = ModRuntime.shared
			let count: Int = clampI(Int(n.a), 1, 4)
			for k in 0..<count {
				let x: Double = pos.0 + (k % 2 == 0 ? 1.0 : -1.0) * (1.5 + Double(k / 2) * 1.2)
				if let slot = rt.mobSlot[n.s], let r = rt.mob(slot) {
					if let y = roomNear(x, pos.1 + 1.0, r.mdef.w, r.mdef.h) { addCustomMob(slot, x, y) }
				} else if let kind = MobKind.allCases.first(where: { $0 != .custom && $0 != .villager && mobDef($0).name == n.s }) {
					if let y = roomNear(x, pos.1 + 1.0, mobDef(kind).w, mobDef(kind).h) { _ = addMob(kind, x, y) }
				} else {
					logic.note(joinText(t.prog.name, ": the creature to call is missing; skipped."))
					break
				}
			}
		case .giveEffect:
			guard let kind = ModEffectKind(rawValue: clampI(Int(n.a), 0, ModEffectKind.allCases.count - 1)) else { return }
			let amt: Double = kind.amountRange.clamp(n.b, sb)
			applyEffects([ModEffect(kind, amt, ModRange.seconds.clamp(n.c, sb))])
		case .placeBlock:
			guard let tile = ModGround.resolve(n.s, ModRuntime.shared), tile != .air else {
				logic.note(joinText(t.prog.name, ": the block to place is missing; skipped."))
				return
			}
			let x: Int = Int(floor(pos.0)) + clampI(Int(n.a), -8, 8)
			let y: Int = Int(floor(pos.1)) - clampI(Int(n.b), -8, 8)
			let cur: Tile = world.tile(x, y)
			if !(cur == .air || cur.liquid || cur.isPlant) { return }
			if tile.solid && pb.right > Double(x) + 0.02 && pb.left < Double(x + 1) - 0.02 && pb.y > Double(y) + 0.02 && pb.top < Double(y + 1) - 0.02 { return }
			world.set(x, y, tile)
		case .breakBlock:
			let x: Int = Int(floor(pos.0)) + clampI(Int(n.a), -8, 8)
			let y: Int = Int(floor(pos.1)) - clampI(Int(n.b), -8, 8)
			let cur: Tile = world.tile(x, y)
			if cur == .air || cur.liquid || cur == .bedrock || cur.hardness >= 99 || cur == .chest || cur.isPower { return }
			if cur == .portalFrame || cur == .portalOff || cur == .portalOn { return }
			breakTile(x, y, false)
		case .setTime:
			timeOfDay = clampD(n.a, 0, 0.999)
			light.valid = false
		case .giveItem:
			if let it = n.item { giveItem(it, clampI(Int(n.a), 1, 64)) }
		case .takeItem:
			if let it = n.item {
				let k: Int = min(inv.total(it), clampI(Int(n.a), 1, 64))
				if k > 0 { _ = inv.remove(it, k) }
				bumpHUD()
			}
		case .enterPhase:
			if let m = t.mob, let r = ModRuntime.shared.mob(m.cslot) {
				let k: Int = clampI(Int(n.a), 1, max(1, r.def.phases.count)) - 1
				if k < r.def.phases.count && k + 1 > m.mphase { enterPhase(m, r, k, quiet: false) }
			}
		case .ifThen, .ifElse, .repeatN, .whileDo, .forever, .wait, .stop, .runGroup:
			break
		}
	}

	/// A scripted shot at the player: a mod's own shot, or one of the game's
	func logicShot(_ t: LThread, _ n: LNode, _ pos: (Double, Double)) {
		var live: Int = 0
		for p in projectiles where p.mod >= 0 || p.owner >= 0 { live += 1 }
		if live >= ModLimits.maxShotsLive { return }
		let speed: Double = clampD(n.a, 4, 30)
		var dx: Double = pb.x - pos.0
		var dy: Double = (pb.y - pb.h * 0.5) - pos.1
		let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
		dx /= len
		dy /= len
		var kind: ProjKind = .fireball
		let gk: Int = clampI(Int(n.b), 0, ModGameShots.kinds.count - 1)
		if let k = ProjKind(rawValue: ModGameShots.kinds[gk]) { kind = k }
		var p = Projectile(kind: kind, x: pos.0 + dx * 0.8, y: pos.1 + dy * 0.8, vx: dx * speed, vy: dy * speed, dmg: clampD(n.c, 0, 30), fromPlayer: false, gravity: 0)
		p.life = 4.0
		p.uid = newID()
		if let m = t.mob {
			p.owner = m.id
			p.source = .mob(m, faction(of: m))
		} else {
			p.source = .environment
		}
		if !n.s.isEmpty, let si = ModRuntime.shared.shotIndex[n.s], si < ModRuntime.shared.shots.count {
			let s: ModProjectile = ModRuntime.shared.shots[si]
			p.kind = .spit
			p.mod = si
			p.gravity = s.gravity
			p.life = s.life
			p.w = s.size
			p.pierce = s.pierce
		}
		projectiles.append(p)
	}

	// MARK: the Mod Test debugger

	func logicPauseToggle() {
		logic.paused.toggle()
		logic.note(logic.paused ? "Paused: scripts wait for STEP." : "Running again.")
	}

	func logicStepOnce() {
		logic.stepOnce = true
		runLogic(0)
	}
}

extension ModValidator {
	/// Logic Studio scripts: their number, their blocks' numbers and names, and blocks that can't work
	/// where they are (a creature's command in a world script) reported in plain words
	static func checkScripts(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		if p.scripts.count > LLimits.maxScripts {
			r.add(1, mn, "Logic Studio", joinText("Only ", String(LLimits.maxScripts), " scripts fit in one mod; the rest were left out."))
			p.scripts = Array(p.scripts.prefix(LLimits.maxScripts))
		}
		p.variables = Array(Set(p.variables.map { String($0.prefix(20)).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
		if p.variables.count > LLimits.maxVariables { p.variables = Array(p.variables.prefix(LLimits.maxVariables)) }
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.infusions.map { $0.id } + p.dims.map { $0.id })
		let groups: Set<String> = Set(p.scripts.filter { $0.event == .group }.map { p.key($0.id) })
		let vars: Set<String> = Set(p.variables)
		let ownMobs: Set<String> = Set(p.mobs.map { p.key($0.id) })
		let ownItems: Set<String> = Set(p.items.map { p.key($0.id) } + p.infusions.map { p.key($0.id) })
		let ownBlocks: Set<String> = Set(p.blocks.map { p.key($0.id) })
		let ownShots: Set<String> = Set(p.projectiles.map { p.key($0.id) })
		let gameNames: Set<String> = Set(MobKind.allCases.filter { $0 != .custom && $0 != .villager }.map { mobDef($0).name })
		for i in p.scripts.indices {
			var s: ModScript = p.scripts[i]
			if s.id.isEmpty || used.contains(s.id) { s.id = joinText("sc", String(i + 1), "x", String(used.count)) }
			used.insert(s.id)
			if s.name.trimmingCharacters(in: .whitespaces).isEmpty { s.name = "Script" }
			s.name = String(s.name.prefix(32))
			let place: String = joinText("Script \u{201C}", s.name, "\u{201D}")
			s.ev = clampD(s.ev.isFinite ? s.ev : 5, s.event == .phase ? 1 : 0.25, s.event == .phase ? 6 : 600)
			s.evText = String(s.evText.prefix(32))
			s.params = Array(s.params.prefix(3).map { String($0.prefix(16)) })
			// what it belongs to must be this mod's own
			switch s.event.subject {
			case 1:
				if !ownMobs.contains(s.target) {
					r.add(1, mn, place, "It belongs to a creature that does not exist; it is switched off.")
					s.enabled = false
				}
			case 2:
				if !ownItems.contains(s.target) {
					r.add(1, mn, place, "It belongs to an item that does not exist; it is switched off.")
					s.enabled = false
				}
			case 3:
				if !ownBlocks.contains(s.target) {
					r.add(1, mn, place, "It belongs to a block that does not exist; it is switched off.")
					s.enabled = false
				}
			default:
				s.target = ""
			}
			var count: Int = 0
			var notes: Set<String> = []
			let creature: Bool = s.event.subject == 1 || s.event == .group
			func fixExpr(_ e: inout LExpr, _ depth: Int) {
				if depth > 6 {
					e = LExpr(0)
					notes.insert("Values were put inside one another too deeply; the deepest became 0.")
					return
				}
				if !e.v.isFinite { e.v = 0 }
				e.s = String(e.s.prefix(40))
				let ar: Int = LReporters.arity(e.op)
				if e.args.count > ar { e.args = Array(e.args.prefix(ar)) }
				while e.args.count < ar { e.args.append(LExpr(0)) }
				switch e.op {
				case .variable:
					if !vars.contains(e.s) {
						notes.insert("A variable it reads does not exist; it reads 0.")
						e = LExpr(0)
					}
				case .param: e.v = clampD(e.v.rounded(), 1, 3)
				case .itemCount:
					if let it = e.item, case .custom(let k) = it, !ownItems.contains(k) && known[k] != "item" { e.item = nil }
				case .nearby: e.v = clampD(e.v, 1, 30)
				default: break
				}
				if LReporters.needsCreature(e.op) && !creature { notes.insert("It reads a creature's health, but it isn't a creature's script; that reads 0.") }
				for k in e.args.indices { fixExpr(&e.args[k], depth + 1) }
			}
			func fixList(_ list: inout [LNode], _ depth: Int) {
				var keep: [LNode] = []
				for var n in list {
					count += 1
					if count > LLimits.maxBlocks {
						notes.insert(joinText("Only ", String(LLimits.maxBlocks), " blocks fit in one script; the rest were left out."))
						break
					}
					if depth > 12 {
						notes.insert("Blocks were put inside one another too deeply; the deepest were left out.")
						continue
					}
					let sp: LSpec = LSpec.of(n.op)
					for f in sp.fields where f.kind == .number || f.kind == .choice {
						let hi: Double = f.kind == .choice ? Double(choiceCount(f.list) - 1) : f.hi
						if f.slot == 0 { n.a = clampD(n.a.isFinite ? n.a : f.def, f.lo, hi) }
						if f.slot == 1 { n.b = clampD(n.b.isFinite ? n.b : f.def, f.lo, hi) }
						if f.slot == 2 { n.c = clampD(n.c.isFinite ? n.c : f.def, f.lo, hi) }
					}
					n.s = String(n.s.prefix(80))
					for k in n.args.indices { fixExpr(&n.args[k], 0) }
					if sp.creature && !creature { notes.insert(joinText("\u{201C}", sp.title, "\u{201D} needs a creature; in this script it does nothing.")) }
					switch n.op {
					case .setVar, .changeVar:
						if !vars.contains(n.s) {
							notes.insert("It sets a variable that does not exist; that block does nothing.")
							n.s = ""
						}
					case .runGroup:
						if !groups.contains(n.s) {
							notes.insert("It runs a group that does not exist; that block does nothing.")
							n.s = ""
						}
					case .summon:
						if !gameNames.contains(n.s) && !ownMobs.contains(n.s) && known[n.s] != "mob" {
							notes.insert("It calls a creature that does not exist; that block does nothing.")
							n.s = ""
						}
					case .placeBlock:
						var ok: Bool = ownBlocks.contains(n.s) || known[n.s] == "block"
						if n.s.hasPrefix("tile:"), let v = Int(n.s.dropFirst(5)), v > 0 && v <= 255, let t = Tile(rawValue: UInt8(v)), !t.isMod, t != .bedrock, t != .portalOn, t != .portalOff, t != .portalFrame { ok = true }
						if !ok {
							notes.insert("It places a block that does not exist; that block does nothing.")
							n.s = ""
						}
					case .fireShot:
						if !n.s.isEmpty && !ownShots.contains(n.s) && known[n.s] != "shot" { n.s = "" }
					case .giveItem, .takeItem:
						if let it = n.item, case .custom(let k) = it, !ownItems.contains(k) && known[k] != "item" {
							notes.insert("It gives or takes an item that does not exist; that block does nothing.")
							n.item = nil
						}
					case .broadcast:
						n.s = String(n.s.prefix(32))
					default: break
					}
					if sp.inside == 0 {
						n.body = []
						n.alt = []
					} else {
						fixList(&n.body, depth + 1)
						if sp.inside == 2 { fixList(&n.alt, depth + 1) } else { n.alt = [] }
					}
					if n.op == .forever || n.op == .whileDo {
						if !LValidate.waits(n.body) { notes.insert("A loop that goes on has no \u{201C}wait\u{201D} inside: the game stops it after 10 seconds.") }
					}
					keep.append(n)
				}
				list = keep
			}
			fixList(&s.blocks, 0)
			for n in notes.sorted() { r.add(1, mn, place, n) }
			p.scripts[i] = s
		}
	}

	static func choiceCount(_ list: Int) -> Int {
		switch list {
		case 0: return LReporters.sounds.count
		case 1: return ModEffectKind.allCases.count
		default: return ModGameShots.kinds.count
		}
	}
}

enum LValidate {
	/// whether a list of blocks waits somewhere (so a loop around it gives the game room)
	static func waits(_ l: [LNode]) -> Bool {
		for n in l {
			if n.op == .wait || n.op == .runGroup { return true }
			if waits(n.body) || waits(n.alt) { return true }
		}
		return false
	}
}

/// The content keys inside scripts: renamed with their mod, and counted as dependencies
enum LKeys {
	static func rekey(_ s0: ModScript, _ fixKey: (String) -> String, _ fixItem: (Item) -> Item) -> ModScript {
		var s: ModScript = s0
		s.target = fixKey(s.target)
		if s.event == .enterDim { s.evText = fixKey(s.evText) }
		func fixE(_ e: inout LExpr) {
			if let it = e.item { e.item = fixItem(it) }
			if e.op == .inDim && e.s != "overworld" && e.s != "umbral" { e.s = fixKey(e.s) }
			for k in e.args.indices { fixE(&e.args[k]) }
		}
		func fixL(_ l: inout [LNode]) {
			for i in l.indices {
				switch l[i].op {
				case .summon, .placeBlock, .fireShot, .runGroup: l[i].s = fixKey(l[i].s)
				default: break
				}
				if let it = l[i].item { l[i].item = fixItem(it) }
				for k in l[i].args.indices { fixE(&l[i].args[k]) }
				fixL(&l[i].body)
				fixL(&l[i].alt)
			}
		}
		fixL(&s.blocks)
		return s
	}

	static func uses(_ s: ModScript, _ add: (String) -> Void, _ addItem: (Item?) -> Void) {
		func useE(_ e: LExpr) {
			addItem(e.item)
			if e.op == .inDim && e.s.contains(":") { add(e.s) }
			for a in e.args { useE(a) }
		}
		func useL(_ l: [LNode]) {
			for n in l {
				switch n.op {
				case .summon, .placeBlock, .fireShot, .runGroup:
					if n.s.contains(":") && !n.s.hasPrefix("tile:") { add(n.s) }
				default: break
				}
				addItem(n.item)
				for a in n.args { useE(a) }
				useL(n.body)
				useL(n.alt)
			}
		}
		useL(s.blocks)
	}
}

/// A mod block's key from its tile in this world ("mod:id"; the open or lit half of a pair counts as it)
func modBlockKey(_ t: Tile) -> String? {
	if !t.isMod { return nil }
	let i: Int = Int(t.rawValue) - Int(Tile.modBase)
	let keys: [String?] = ModRuntime.shared.slotKey
	if i < 0 || i >= keys.count { return nil }
	guard let k = keys[i] else { return nil }
	if k.hasSuffix("#alt") { return String(k.dropLast(4)) }
	return k
}

extension Game {
	/// A tap on one of the mods' blocks that a script listens for (the tap goes to the script)
	func tryLogicTap() -> Bool {
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		let t: Tile = world.tile(tx, ty)
		guard t.isMod, let k = modBlockKey(t), inReach(Double(tx) + 0.5, Double(ty) + 0.5) else { return false }
		if !logicRT.listeners(.blockTapped).contains(where: { $0.def.target == k }) { return false }
		fireLogic(.blockTapped, x: tx, y: ty, block: true, key: k)
		return true
	}
}

// MARK: - Rules, weather, machines, vehicles and looks in mods

/// A rule of the game a mod can change. A mod keeps it as a number under the rule's id (ModPack.rules);
/// a rule it leaves out stays the game's own. When the world's mods set the same rule, the one lowest
/// in the load order wins (ModRuntime.rules). The name, range and help of each are text (specText), in
/// the order of the cases.
enum GameRule: Int, CaseIterable {
	case day, gravity, health, hunger, healing, hurt, hit, mining, monsters, animals, falls, walk, jump, nights, deathDrop

	struct Spec {
		var id: String
		var name: String
		var unit: String
		var lo: Double
		var hi: Double
		var def: Double
		var step: Double
		var help: String
	}

	static let specs: [Spec] = parseSpecs(specText)
	var spec: Spec { return rawValue < GameRule.specs.count ? GameRule.specs[rawValue] : Spec(id: "", name: "", unit: "", lo: 0, hi: 1, def: 1, step: 0.1, help: "") }

	static func byID(_ id: String) -> GameRule? {
		for r in GameRule.allCases where r.spec.id == id { return r }
		return nil
	}

	static func parseSpecs(_ s: String) -> [Spec] {
		var out: [Spec] = []
		for line in s.split(separator: "\n") {
			let f: [String] = line.components(separatedBy: "|")
			if f.count < 8 { continue }
			out.append(Spec(id: f[0], name: f[1], unit: f[2], lo: Double(f[3]) ?? 0, hi: Double(f[4]) ?? 1, def: Double(f[5]) ?? 1, step: Double(f[6]) ?? 0.1, help: f[7]))
		}
		return out
	}

	/// id|name|unit|lowest|highest|the game's|step|what it does
	static let specText: String = """
		day|Day length|min|2|120|12|1|How many minutes a whole day and night take.
		gravity|Gravity|x|0.2|3|1|0.1|How hard everything falls: the player, creatures, loose blocks and vehicles (low gravity: higher jumps, gentler falls).
		health|Player health|pts|4|200|20|2|The player's full health (still shown as ten hearts).
		hunger|Hunger|x|0|5|1|0.1|How fast the player gets hungry (0: never).
		healing|Healing|x|0|5|1|0.1|How fast health comes back on a full stomach (0: only food and potions heal).
		hurt|Damage taken|x|0|5|1|0.1|How hard everything hits the player (0: nothing can hurt them).
		hit|Damage dealt|x|0.1|10|1|0.1|How hard the player hits creatures.
		mining|Mining speed|x|0.1|10|1|0.1|How fast blocks break under the player's tools and hands.
		monsters|Monsters|x|0|5|1|0.1|How many night monsters may be about at once (0: none come).
		animals|Animals|x|0|5|1|0.1|How many animals and fish may be about at once.
		falls|Fall damage|x|0|5|1|0.1|How much a hard landing hurts (0: falls never hurt).
		walk|Walking speed|x|0.3|3|1|0.1|How fast the player walks and runs.
		jump|Jump height|x|0.3|3|1|0.1|How high the player jumps.
		nights|Night light|x|0|2.5|1|0.1|How bright nights are (0: pitch dark under the stars; 2.5: as light as day).
		deathDrop|Drop items on death|on|0|1|0|1|On: everything in the bag falls where the player dies and waits there. Off: the player keeps it (the game's way).
		"""
}

/// The Overworld's weather as a mod has it: how often each kind comes (1: as the game, 0: never), how
/// strong rain, snow and wind are, how long spells last, and the colour of the rain
struct ModWeather: Codable, Equatable {
	var chance: [Double] = [Double](repeating: 1, count: WeatherKind.allCases.count)
	var rain: Double = 1
	var wind: Double = 1
	var length: Double = 1
	/// 0: the game's
	var rainColor: UInt32 = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		chance = c.val(.chance, [Double](repeating: 1, count: WeatherKind.allCases.count))
		rain = c.val(.rain, 1)
		wind = c.val(.wind, 1)
		length = c.val(.length, 1)
		rainColor = c.val(.rainColor, 0)
	}

	mutating func clamp() {
		var ch: [Double] = []
		for k in WeatherKind.allCases {
			let v: Double = k.rawValue < chance.count ? chance[k.rawValue] : 1
			ch.append(clampD(v.isFinite ? v : 1, 0, 10))
		}
		chance = ch
		rain = clampD(rain.isFinite ? rain : 1, 0, 3)
		wind = clampD(wind.isFinite ? wind : 1, 0, 3)
		length = clampD(length.isFinite ? length : 1, 0.25, 6)
		rainColor &= 0xFFFFFF
	}

	func chanceOf(_ k: WeatherKind) -> Double { return k.rawValue < chance.count ? chance[k.rawValue] : 1 }
}

/// What a mod block does on Sparkworks power lines (cases are only ever appended)
enum ModPowerRole: Int, Codable, CaseIterable {
	case none, generator, solar, battery, lamp, signal
	var name: String {
		switch self {
		case .none: return "No power"
		case .generator: return "Generator"
		case .solar: return "Solar generator"
		case .battery: return "Battery"
		case .lamp: return "Powered lamp"
		case .signal: return "Signal light"
		}
	}
	var help: String {
		switch self {
		case .none: return "It has nothing to do with power."
		case .generator: return "Makes its strength in sparks a second, day and night (a fuel generator makes 12)."
		case .solar: return "Makes up to its strength in sparks a second under the open sky by day, less under cloud (a solar panel makes 4)."
		case .battery: return "Stores 150 times its strength in sparks and passes 2.5 times its strength a second (a battery: strength 4)."
		case .lamp: return "Lights up while it has power (and its pulse wire is on, if it has one), using its strength in sparks a second. Give it a lit picture: set its function to Light switch."
		case .signal: return "Lights up while the pulse wire on it is on. Give it a lit picture: set its function to Light switch."
		}
	}
	/// the game's role it plays on the networks
	var role: PowerRole {
		switch self {
		case .none: return .none
		case .generator, .solar: return .generator
		case .battery: return .storage
		case .lamp: return .machine
		case .signal: return .indicator
		}
	}
}

/// One cell of a vehicle kept in a mod: where it is (x right, y down) and what it is: a game part, or
/// a block (a game block "tile:<n>" or one of a mod's blocks by key)
struct ModVehicleCell: Codable, Equatable {
	var x: Int = 0
	var y: Int = 0
	var part: Int = PartType.frame.rawValue
	var block: String = ""

	init() {}
	init(_ x: Int, _ y: Int, _ p: PartType, _ b: String = "") {
		self.x = x
		self.y = y
		part = p.rawValue
		block = b
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		x = c.val(.x, 0)
		y = c.val(.y, 0)
		part = c.val(.part, PartType.frame.rawValue)
		block = c.val(.block, "")
	}

	var partType: PartType { return PartType(rawValue: part) ?? .frame }
}

/// A whole vehicle kept in a mod: its cells, and the item that builds it (made by the mod's recipes;
/// used on open ground, or on water for a boat, it puts the vehicle there)
struct ModVehicle: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Vehicle"
	var desc: String = ""
	var cells: [ModVehicleCell] = []
	/// its item's icon (blank: drawn from its cells)
	var icon: ModPixels = ModPixels(w: 12, h: 12)
	/// put on water, like a boat
	var water: Bool = false
	/// fuel it comes with
	var fuel: Double = 40

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Vehicle")
		desc = c.val(.desc, "")
		cells = c.list(.cells, &skip)
		icon = c.val(.icon, ModPixels(w: 12, h: 12))
		water = c.val(.water, false)
		fuel = c.val(.fuel, 40)
	}

	static let maxCells: Int = 160
	static let maxSize: Int = 24
}

enum ModWorldLimits {
	static let startItems: Int = 12
	static let vehicles: Int = 12
}

extension ModValidator {
	/// A mod's rules, start items, weather and vehicles kept in range: rules the game knows held to
	/// their ranges, items that exist, vehicles of parts and blocks that exist and fit a 24 x 24 grid
	static func checkWorldRules(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		var kept: [String: Double] = [:]
		for (k, v) in p.rules {
			guard let g = GameRule.byID(k) else {
				r.add(1, mn, "Rules", joinText("The game has no rule \u{201C}", k, "\u{201D}; it was left out."))
				continue
			}
			let s: GameRule.Spec = g.spec
			kept[k] = clampD(v.isFinite ? v : s.def, s.lo, s.hi)
		}
		p.rules = kept
		let ownItems: Set<String> = Set(p.items.map { p.key($0.id) } + p.suitParts.map { p.key($0.id) } + p.vehicles.map { p.key($0.id) })
		func real(_ it: Item) -> Bool {
			if case .custom(let k) = it { return ownItems.contains(k) || known[k] == "item" }
			return true
		}
		if p.startItems.count > ModWorldLimits.startItems { p.startItems = Array(p.startItems.prefix(ModWorldLimits.startItems)) }
		var items: [ModCost] = []
		for var s in p.startItems {
			if !real(s.item) {
				r.add(1, mn, "Start items", "One of them does not exist; it was left out.")
				continue
			}
			s.n = clampI(s.n, 1, 999)
			items.append(s)
		}
		p.startItems = items
		if var w = p.weather {
			w.clamp()
			p.weather = w
		}
		if var t = p.theme {
			t.clamp()
			p.theme = t
		}
		if p.vehicles.count > ModWorldLimits.vehicles {
			r.add(1, mn, "Mod", joinText("Only ", String(ModWorldLimits.vehicles), " vehicles fit in one mod; the rest were left out."))
			p.vehicles = Array(p.vehicles.prefix(ModWorldLimits.vehicles))
		}
		let blocks: Set<String> = Set(p.blocks.map { p.key($0.id) })
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.dims.map { $0.id } + p.suitParts.map { $0.id })
		for i in p.vehicles.indices {
			var v: ModVehicle = p.vehicles[i]
			if v.id.isEmpty || used.contains(v.id) { v.id = joinText("veh", String(i + 1), "x", String(used.count)) }
			used.insert(v.id)
			let place: String = joinText("Vehicle \u{201C}", v.name, "\u{201D}")
			if v.name.trimmingCharacters(in: .whitespaces).isEmpty { v.name = "Vehicle" }
			v.name = String(v.name.prefix(24))
			v.desc = String(v.desc.prefix(120))
			v.fuel = clampD(v.fuel.isFinite ? v.fuel : 40, 0, 400)
			if !v.icon.valid || v.icon.w > 32 || v.icon.h > 32 { v.icon = ModPixels(w: 12, h: 12) }
			var seen: Set<Int> = []
			var cells: [ModVehicleCell] = []
			for var c in v.cells.prefix(ModVehicle.maxCells) {
				c.x = clampI(c.x, 0, ModVehicle.maxSize - 1)
				c.y = clampI(c.y, 0, ModVehicle.maxSize - 1)
				if PartType(rawValue: c.part) == nil { c.part = PartType.frame.rawValue }
				if !c.block.isEmpty && !c.block.hasPrefix("tile:") && !blocks.contains(c.block) && known[c.block] != "block" {
					c.block = ""
					c.part = PartType.frame.rawValue
				}
				if c.block.hasPrefix("tile:") {
					let n: Int = Int(c.block.dropFirst(5)) ?? -1
					if n <= 0 || n > 255 || Tile(rawValue: UInt8(n)) == nil || Tile(rawValue: UInt8(n))?.isMod == true { c.block = "tile:" + String(Tile.planks.rawValue) }
				}
				let key: Int = c.y * 100 + c.x
				if seen.contains(key) { continue }
				seen.insert(key)
				cells.append(c)
			}
			v.cells = cells
			if v.cells.isEmpty { r.add(0, mn, place, "It has no cells yet.") }
			p.vehicles[i] = v
		}
	}
}

extension ModRuntime {
	/// A rule as the world's mods set it (the game's own when none does)
	func rule(_ g: GameRule) -> Double {
		return g.rawValue < rules.count ? rules[g.rawValue] : g.spec.def
	}

	/// The mods' rules, start items, weather, block physics and power, and vehicles, ready for play
	func buildWorldRules() {
		rules = GameRule.specs.map { $0.def }
		for p in packs {
			for (k, v) in p.rules {
				if let g = GameRule.byID(k), g.rawValue < rules.count { rules[g.rawValue] = v }
			}
			for s in p.startItems { startItems.append(Stack(item: resolve(s.item), count: s.n)) }
			if let w = p.weather { weather = w }
			if let t = p.theme { theme = t }
			for v in p.vehicles where !disabled.contains(p.key(v.id)) {
				var mv: ModVehicle = v
				for i in mv.cells.indices where !mv.cells[i].block.isEmpty && !mv.cells[i].block.hasPrefix("tile:") {
					// a mod block that is not in this world becomes a frame
					if tileForKey[mv.cells[i].block] == nil {
						mv.cells[i].block = ""
						mv.cells[i].part = PartType.frame.rawValue
					}
				}
				vehicles[p.key(v.id)] = mv
			}
		}
		// mod blocks that fall, seat, put to bed or work on power lines
		for i in 0..<ModLimits.blockSlots {
			guard let b = slotDef[i] else { continue }
			let t: UInt8 = UInt8(Int(Tile.mod00.rawValue) + i)
			if slotTreeBase[i] != nil { continue }
			if b.falls { fallTiles.insert(t) }
			if b.function == .seat { seatTiles.insert(t) }
			if b.function == .bed { bedTiles.insert(t) }
			if b.powerRole != .none { powerTiles[t] = b.powerRole }
		}
	}

	/// The power role of a mod block (none for anything else)
	func powerRoleOf(_ t: Tile) -> ModPowerRole {
		if !t.isMod { return .none }
		return powerTiles[t.rawValue] ?? .none
	}

	/// A mod vehicle's item: held and used, it builds the vehicle
	func vehicleItem(_ p: ModPack, _ v: ModVehicle) -> ModItem {
		var it = ModItem()
		it.id = v.id
		it.name = v.name
		it.desc = v.desc.isEmpty ? "A vehicle kit: use it on open ground (a boat: on water) to build the vehicle." : v.desc
		it.kind = .special
		it.stack = 1
		it.rarity = 2
		if !v.icon.isBlank { it.icon = v.icon } else { it.icon = ModPixels(buf: vehicleIconBuf(v)) }
		return it
	}

	/// A small picture of a vehicle from its cells
	func vehicleIconBuf(_ v: ModVehicle) -> PixelBuf {
		var buf = PixelBuf(w: 12, h: 12)
		if v.cells.isEmpty { return buf }
		var w: Int = 1
		var h: Int = 1
		for c in v.cells {
			w = max(w, c.x + 1)
			h = max(h, c.y + 1)
		}
		let s: Int = max(1, min(12 / w, 12 / h))
		let ox: Int = (12 - w * s) / 2
		let oy: Int = 12 - h * s
		for c in v.cells {
			let col: UInt32 = vehicleCellColor(c)
			for yy in 0..<s {
				for xx in 0..<s {
					let px: Int = ox + c.x * s + xx
					let py: Int = oy + c.y * s + yy
					if px >= 0 && py >= 0 && px < 12 && py < 12 { buf.px[py * 12 + px] = 0xFF000000 | col }
				}
			}
		}
		return buf
	}

	func vehicleCellColor(_ c: ModVehicleCell) -> UInt32 {
		if c.block.hasPrefix("tile:"), let n = Int(c.block.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) {
			return t.def.colors.first ?? 0x8A8A8A
		}
		if !c.block.isEmpty, let t = tileForKey[c.block] { return t.def.colors.first ?? 0x8A8A8A }
		return partSwatch(c.partType)
	}
}

/// A colour that stands for a vehicle part in small pictures and the vehicle editor
func partSwatch(_ p: PartType) -> UInt32 {
	switch p {
	case .wheel, .track: return 0x2A2A2E
	case .engine, .jet: return 0x8A5A3A
	case .seat, .cockpit, .steering: return 0x3A6AA8
	case .wing, .elevator: return 0xC8C8D0
	case .rotor, .tailRotor, .airProp, .propeller, .paddle: return 0xE8D8A0
	case .envelope: return 0xE8E0D0
	case .hull: return 0x8F6732
	case .armor, .cannon, .autoGun: return 0x5A6270
	case .fuelTank: return 0xC03A3A
	default: return 0x9AA4B0
	}
}

extension Game {
	/// The player's full health as the world's mods have it (the game's 20 without them)
	func applyHealthRule(newWorld: Bool) {
		let h: Double = ModRuntime.shared.rule(.health)
		if maxHP != h || newWorld {
			maxHP = h
			hp = newWorld ? h : min(max(hp, 1), h)
		}
	}

	/// What the world's mods give a new world (not in creative)
	func giveStartItems() {
		if mode == .creative { return }
		for s in ModRuntime.shared.startItems { _ = inv.add(s.item, s.count) }
	}

	/// With the mods' "drop items on death" rule: the bag (and the carried stack) falls where the
	/// player died, held back until they come for it
	func dropBagOnDeath() {
		if mode == .creative || ModRuntime.shared.rule(.deathDrop) < 0.5 { return }
		var spilled: [Stack] = []
		if let c = carry { spilled.append(c) }
		carry = nil
		for i in inv.slots.indices {
			if let s = inv.slots[i] { spilled.append(s) }
			inv.slots[i] = nil
		}
		for (k, s) in spilled.enumerated() {
			let a: Double = Double(k) * 0.7
			spawnDrop(s, pb.x, pb.y - 0.8, cos(a) * 2.0, -3.0 - Double(k % 3), heldBack: true)
		}
	}

	/// Puts a mod's vehicle down at the aim from its kit item
	func placeModVehicle(_ key: String) {
		guard let mv = ModRuntime.shared.vehicles[key], !mv.cells.isEmpty else {
			say("This vehicle's mod is not installed.", 1.5)
			return
		}
		if !inReach(aimX, aimY) {
			say("Tap closer to you to place it.", 1.5)
			return
		}
		var w: Int = 1
		var h: Int = 1
		for c in mv.cells {
			w = max(w, c.x + 1)
			h = max(h, c.y + 1)
		}
		guard let spot = vehicleSpot(w, h, mv.water) else {
			say(mv.water ? "Not enough room here. Find open water." : "Not enough room here. Find open, flat ground.", 2.5)
			return
		}
		let first: PartType = mv.cells[0].partType
		let v: Vehicle = Vehicle(id: newID(), first: first, x: 0, y: 0)
		v.parts.removeAll()
		for c in mv.cells {
			let cell: PartCell = PartCell(dx: c.x, dy: c.y)
			if c.block.isEmpty {
				v.parts[cell] = c.partType
				continue
			}
			var t: Tile = .planks
			if c.block.hasPrefix("tile:") {
				t = Tile(rawValue: UInt8(clampI(Int(c.block.dropFirst(5)) ?? 0, 0, 255))) ?? .planks
			} else if let mt = ModRuntime.shared.tileForKey[c.block] {
				t = mt
			}
			// a mod block working as a part keeps its part; anything else is a plain block
			if let role = ModRuntime.shared.blockDef(t)?.vehRole.part { v.parts[cell] = role } else { v.parts[cell] = .block }
			v.blocks[cell] = t
		}
		v.recompute(keepAnchor: false)
		v.placeBox(left: Double(spot.0), bottom: Double(spot.1 + 1))
		if v.engines > 0 || v.jets > 0 || v.burners > 0 { v.fuel = min(v.fuelCapacity, mv.fuel) }
		vehicles.append(v)
		if !isCreative { inv.removeAt(sel, 1) }
		useCD = 0.3
		swingT = 0.15
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xFFF0A0, 10, 3.0, 0.5, 6)
		say(joinText(mv.name, " placed! Walk up to it and press DRIVE."), 3.0)
		bumpHUD()
	}

	/// A place for a w x h vehicle near the aim: open air for its box, and under it solid ground (or
	/// water, for a boat); the left column and the row of its bottom
	func vehicleSpot(_ w: Int, _ h: Int, _ water: Bool) -> (Int, Int)? {
		let ax: Int = Int(floor(aimX))
		let ay: Int = Int(floor(aimY))
		for off in [0, -1, 1, -2, 2, -3, 3] {
			let left: Int = ax - w / 2 + off
			for dy in -3...6 {
				let bottom: Int = ay + dy
				var ok: Bool = true
				for x in left..<(left + w) {
					// open air for its box (a boat sits on the water, not in it)
					for y in (bottom - h + 1)...bottom where world.solid(x, y) || world.tile(x, y).liquid {
						ok = false
						break
					}
					if !ok { break }
					let under: Tile = world.tile(x, bottom + 1)
					if water ? under != .water : !(under.solid || under.isPlatform) {
						if x == left || x == left + w - 1 { ok = false }
					}
				}
				if ok { return (left, bottom) }
			}
		}
		return nil
	}

	/// Makes a mod vehicle design from a vehicle in the world (for saving it to a mod from a test world)
	func vehicleDesign(_ v: Vehicle) -> ModVehicle {
		var mv = ModVehicle()
		mv.name = "My Vehicle"
		var minX: Int = Int.max
		var minY: Int = Int.max
		for c in v.parts.keys {
			minX = min(minX, c.dx)
			minY = min(minY, c.dy)
		}
		let keys: [PartCell] = v.parts.keys.sorted { $0.dy != $1.dy ? $0.dy < $1.dy : $0.dx < $1.dx }
		for c in keys {
			guard let p = v.parts[c] else { continue }
			var cell = ModVehicleCell(c.dx - minX, c.dy - minY, p)
			if let t = v.blocks[c] {
				if t.isMod { cell.block = ModRuntime.shared.slotKey[Int(t.rawValue) - Int(Tile.mod00.rawValue)] ?? "" } else { cell.block = "tile:" + String(t.rawValue) }
				if cell.block.isEmpty { cell.part = PartType.frame.rawValue }
			}
			mv.cells.append(cell)
		}
		mv.water = v.parts.values.contains(.hull)
		mv.fuel = min(400, v.fuel)
		return mv
	}
}

/// The parts of the game's screens a theme colours (cases are only ever appended)
enum ThemeRole: Int, Codable, CaseIterable {
	case buttons, panels, accept, danger, info, titles, tint
	var name: String {
		switch self {
		case .buttons: return "Buttons"
		case .panels: return "Panels and cards"
		case .accept: return "Go and accept buttons"
		case .danger: return "Danger and close buttons"
		case .info: return "Information buttons"
		case .titles: return "Titles"
		case .tint: return "Everything else (tint)"
		}
	}
	/// the game's own colours this role replaces
	var gameColors: [UInt32] {
		switch self {
		case .buttons: return [0x555555, 0x6B6B6B, 0x4A4A50, 0x444444, 0x3A3A3A]
		case .panels: return [0x2C2C30, 0x2E2E2E, 0x3A3A40]
		case .accept: return [0x4E8A3E, 0x2A6A2A, 0x4E6A3E]
		case .danger: return [0xA03030, 0xC02020, 0x8A3A3A]
		case .info: return [0x3E6FAA, 0x5A7A9A, 0x4E6A8A, 0x2E8A8A]
		case .titles: return [0xFFE066, 0xFFE070, 0xFFE080]
		case .tint: return []
		}
	}
	/// what the role shows in the editor before it is changed
	var gameColor: UInt32 { return gameColors.first ?? 0x8A8A8A }
}

/// How the game's screens look with a mod: colours by role (0: the game's), the style of the letters,
/// how round buttons and panels are, the title screen's words and picture, and the HUD's size, how
/// see-through it is and which side the controls are on
struct ModTheme: Codable, Equatable {
	var colors: [UInt32] = [UInt32](repeating: 0, count: ThemeRole.allCases.count)
	/// how strongly every other colour leans to the tint colour (0...1)
	var tintAmt: Double = 0
	/// letters: 0 blocky (the game's), 1 rounded, 2 serif, 3 plain
	var font: Int = 0
	/// 0: square pixel boxes (the game's) ... 16
	var corner: Double = 0
	/// the outline of buttons and panels (0: black)
	var outline: UInt32 = 0
	var title: String = ""
	var subtitle: String = ""
	/// the title screen's background (blank: the game's sky)
	var background: ModPixels = ModPixels(w: 1, h: 1)
	var hudScale: Double = 1
	var hudAlpha: Double = 1
	/// the attack stick and action buttons on the left, the walking stick on the right
	var swapSides: Bool = false

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		colors = c.val(.colors, [UInt32](repeating: 0, count: ThemeRole.allCases.count))
		tintAmt = c.val(.tintAmt, 0)
		font = c.val(.font, 0)
		corner = c.val(.corner, 0)
		outline = c.val(.outline, 0)
		title = c.val(.title, "")
		subtitle = c.val(.subtitle, "")
		background = c.val(.background, ModPixels(w: 1, h: 1))
		hudScale = c.val(.hudScale, 1)
		hudAlpha = c.val(.hudAlpha, 1)
		swapSides = c.val(.swapSides, false)
	}

	static let fonts: [String] = ["Blocky", "Rounded", "Serif", "Plain"]

	func color(_ r: ThemeRole) -> UInt32 { return r.rawValue < colors.count ? colors[r.rawValue] : 0 }

	mutating func clamp() {
		var cs: [UInt32] = []
		for r in ThemeRole.allCases { cs.append(color(r) & 0xFFFFFF) }
		colors = cs
		tintAmt = clampD(tintAmt.isFinite ? tintAmt : 0, 0, 1)
		font = clampI(font, 0, ModTheme.fonts.count - 1)
		corner = clampD(corner.isFinite ? corner : 0, 0, 16)
		outline &= 0xFFFFFF
		title = String(title.prefix(32))
		subtitle = String(subtitle.prefix(60))
		if !background.valid || background.w > 96 || background.h > 96 { background = ModPixels(w: 1, h: 1) }
		hudScale = clampD(hudScale.isFinite ? hudScale : 1, 0.6, 1.5)
		hudAlpha = clampD(hudAlpha.isFinite ? hudAlpha : 1, 0.3, 1)
	}
}

// ===== u01_art =====

// MARK: - Art store (converts the procedural PixelBufs into SwiftUI images)

extension Color {
	init(hex: UInt32, alpha: Double = 1.0) {
		let ir: UInt32 = (hex >> 16) & 255
		let ig: UInt32 = (hex >> 8) & 255
		let ib: UInt32 = hex & 255
		let r: Double = Double(ir) / 255.0
		let g: Double = Double(ig) / 255.0
		let b: Double = Double(ib) / 255.0
		self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
	}
}

/// Fast path: pixels are already premultiplied ARGB words (0xAARRGGBB). No per-pixel work.
func makeCGImagePremul(_ px: [UInt32], _ w: Int, _ h: Int) -> CGImage? {
	if w <= 0 || h <= 0 || px.count < w * h { return nil }
	let data: Data = px.withUnsafeBufferPointer { bp in Data(buffer: bp) }
	guard let provider = CGDataProvider(data: data as CFData) else { return nil }
	let raw: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
	let info: CGBitmapInfo = CGBitmapInfo(rawValue: raw)
	return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
				   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
				   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Pixels are non-premultiplied ARGB (what the art generators produce)
func makeCGImage(_ px: [UInt32], _ w: Int, _ h: Int) -> CGImage? {
	var p: [UInt32] = px
	premultiplyARGB(&p)
	return makeCGImagePremul(p, w, h)
}

func pixImage(_ b: PixelBuf) -> Image {
	if let cg = makeCGImage(b.px, b.w, b.h) {
		return Image(decorative: cg, scale: 1.0).interpolation(.none)
	}
	return Image(systemName: "questionmark")
}

/// A set of animation frames for one creature, with the metrics needed to stand it on the ground.
struct SpriteSet {
	var right: [Image]
	var left: [Image]
	var hurtR: [Image]
	var hurtL: [Image]
	var w: Int
	var h: Int
	var footRow: Int      // art pixel row of the bottom of the feet
	var centerCol: Double // art pixel column of the body centre (facing right)
	var scale: Double     // tiles per art pixel
	var anim: CreatureAnim = CreatureAnim()

	func frame(_ i: Int, left lf: Bool, hurt: Bool) -> Image {
		let n: Int = max(1, right.count)
		let k: Int = ((i % n) + n) % n
		if hurt { return lf ? hurtL[k] : hurtR[k] }
		return lf ? left[k] : right[k]
	}
}

func opaqueBounds(_ b: PixelBuf) -> (Int, Int, Int, Int) {
	var x0: Int = b.w
	var x1: Int = -1
	var y0: Int = b.h
	var y1: Int = -1
	for y in 0..<b.h {
		for x in 0..<b.w where (b.px[y * b.w + x] >> 24) != 0 {
			if x < x0 { x0 = x }
			if x > x1 { x1 = x }
			if y < y0 { y0 = y }
			if y > y1 { y1 = y }
		}
	}
	if x1 < 0 { return (0, 0, b.w - 1, b.h - 1) }
	return (x0, y0, x1, y1)
}

func makeSpriteSet(_ frames: [PixelBuf], hitH: Double, fixedScale: Double? = nil, anim: CreatureAnim = CreatureAnim(), foot footRow: Int? = nil, cx: Double? = nil) -> SpriteSet {
	let f0: PixelBuf = frames.isEmpty ? PixelBuf(w: 1, h: 1) : frames[0]
	let bb: (Int, Int, Int, Int) = opaqueBounds(f0)
	let opaqueH: Double = Double(bb.3 - bb.1 + 1)
	var sc: Double = 0.125
	if let f = fixedScale { sc = f } else {
		sc = clampD(hitH * 1.12 / max(1.0, opaqueH), 0.05, 0.125)
	}
	var r: [Image] = []
	var l: [Image] = []
	var hr: [Image] = []
	var hl: [Image] = []
	for f in frames {
		r.append(pixImage(f))
		l.append(pixImage(f.flipped()))
		// hit frames flash white (reads clearly on every creature, and is not a red full-body tint)
		let t: PixelBuf = f.whiteFlash()
		hr.append(pixImage(t))
		hl.append(pixImage(t.flipped()))
	}
	// the outline under the soles sits on the ground line; a hand-drawn creature says where its soles
	// and its middle are (a long tail or a raised arm must not move the body off its place)
	let foot: Int = footRow ?? bb.3
	let cc: Double = cx ?? Double(bb.0 + bb.2 + 1) * 0.5
	return SpriteSet(right: r, left: l, hurtR: hr, hurtL: hl, w: f0.w, h: f0.h, footRow: foot, centerCol: cc, scale: sc, anim: anim)
}

// MARK: - Suits drawn piece by piece

/// A picture three times finer, every pixel a 3 x 3 block
func upscale3(_ b: PixelBuf) -> PixelBuf {
	let u: Int = suitUnit
	var o = PixelBuf(w: b.w * u, h: b.h * u)
	for y in 0..<b.h {
		for x in 0..<b.w {
			let c: UInt32 = b.px[y * b.w + x]
			if c == 0 { continue }
			for yy in 0..<u {
				let row: Int = (y * u + yy) * o.w + x * u
				for xx in 0..<u { o.px[row + xx] = c }
			}
		}
	}
	return o
}

/// Lays a suit's working pieces over one frame of the figure drawn three times finer (`frame`: 0
/// standing, 1-2 walking, 3 winding up, 4 striking, 5 blocking, 6 shooting). Each piece moves with its
/// part of the body, shows its colour with lit and shaded edges and its part's marks, and cracks as it
/// wears; broken pieces are gone. `pick` (a piece id) is drawn brighter. A dark line is drawn round
/// what sticks out past the body.
func paintSuitPieces(_ cv: inout PixelBuf, _ d: SuitDesign, frame: Int, pick: Int = -1) {
	let ox: Double = Double(humanOX * suitUnit)
	var mine: [Bool] = [Bool](repeating: false, count: cv.w * cv.h)
	let order: [Int] = d.pieces.indices.sorted { (a: Int, b: Int) -> Bool in
		let la: Int = d.pieces[a].bone.layer
		let lb: Int = d.pieces[b].bone.layer
		return la != lb ? la < lb : a < b
	}
	for i in order {
		let p: SuitPiece = d.pieces[i]
		if p.broken { continue }
		let mv: BoneMove = BoneMove.of(p.bone, frame)
		// the piece's box in the frame, roomy enough for any turn
		let c: (Double, Double) = mv.apply(p.x, p.y)
		let r: Double = sqrt(p.w * p.w + p.h * p.h) * 0.5 + 1.0
		let x0: Int = max(0, Int(floor(c.0 + ox - r)))
		let x1: Int = min(cv.w - 1, Int(ceil(c.0 + ox + r)))
		let y0: Int = max(0, Int(floor(c.1 - r)))
		let y1: Int = min(cv.h - 1, Int(ceil(c.1 + r)))
		if x1 < x0 || y1 < y0 { continue }
		let ww: Int = x1 - x0 + 1
		let hh: Int = y1 - y0 + 1
		// which pixels it covers (tested back on the body standing still)
		var on: [Bool] = [Bool](repeating: false, count: ww * hh)
		let back: BoneMove = BoneMove(dx: -mv.dx, dy: -mv.dy, turn: 0, px: 0, py: 0)
		for yy in 0..<hh {
			for xx in 0..<ww {
				var bx: Double = Double(x0 + xx) + 0.5 - ox
				var by: Double = Double(y0 + yy) + 0.5
				let s: (Double, Double) = back.apply(bx, by)
				bx = s.0
				by = s.1
				if mv.turn != 0 {
					let cs: Double = cos(-mv.turn)
					let sn: Double = sin(-mv.turn)
					let rx: Double = bx - mv.px
					let ry: Double = by - mv.py
					bx = mv.px + rx * cs - ry * sn
					by = mv.py + rx * sn + ry * cs
				}
				if p.covers(bx, by) { on[yy * ww + xx] = true }
			}
		}
		var base: UInt32 = suitColor(p)
		if p.id == pick { base = mixRGB(base, 0xFFFFFF, 0.35) }
		let accent: UInt32 = suitAccent(p)
		for yy in 0..<hh {
			for xx in 0..<ww where on[yy * ww + xx] {
				let up: Bool = yy > 0 && on[(yy - 1) * ww + xx]
				let down: Bool = yy < hh - 1 && on[(yy + 1) * ww + xx]
				let left: Bool = xx > 0 && on[yy * ww + xx - 1]
				let right: Bool = xx < ww - 1 && on[yy * ww + xx + 1]
				var col: UInt32 = base
				if !up || !left { col = shadeRGB(base, 1.22) }
				if !down || !right { col = shadeRGB(base, 0.68) }
				let gx: Int = x0 + xx
				let gy: Int = y0 + yy
				// cracks as it wears
				if p.dmg > 0.3 {
					let hsh: Double = hash2(gx * 7 + p.id, gy * 13, 9091)
					if hsh < (p.dmg - 0.25) * 0.5 { col = shadeRGB(col, 0.45) }
				}
				cv.px[gy * cv.w + gx] = 0xFF000000 | col
				mine[gy * cv.w + gx] = true
			}
		}
		// its marks: a core glows at its heart, a working part shows its colour at its working end
		if accent != 0 {
			let a: Double = (p.rot + mv.turn * 180.0 / Double.pi) * Double.pi / 180.0
			let tip: (Double, Double)
			if p.kind == .core {
				tip = (c.0, c.1)
			} else {
				tip = (c.0 + cos(a) * p.w * 0.32, c.1 + sin(a) * p.w * 0.32)
			}
			let tx: Int = Int(floor(tip.0 + ox))
			let ty: Int = Int(floor(tip.1))
			for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
				let px: Int = tx + dx - 1
				let py: Int = ty + dy - 1
				if px < 0 || py < 0 || px >= cv.w || py >= cv.h { continue }
				if mine[py * cv.w + px] { cv.px[py * cv.w + px] = 0xFF000000 | accent }
			}
		}
	}
	// a dark edge round the pieces where they stand against nothing
	var edge: [Int] = []
	for y in 0..<cv.h {
		for x in 0..<cv.w where cv.px[y * cv.w + x] == 0 {
			var near: Bool = false
			for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
				let nx: Int = x + dx
				let ny: Int = y + dy
				if nx >= 0 && ny >= 0 && nx < cv.w && ny < cv.h && mine[ny * cv.w + nx] { near = true }
			}
			if near { edge.append(y * cv.w + x) }
		}
	}
	for k in edge { cv.px[k] = 0xFF1A1410 }
}

/// The mark a working part shows (0: none): a core's glow, a jet's flame, a lamp, a lens
func suitAccent(_ p: SuitPiece) -> UInt32 {
	if p.kind == .core, let c = p.core { return shadeRGB(c.color, 1.4) }
	guard p.kind == .module, let m = p.module else { return 0 }
	switch m {
	case .hover: return 0xFF9A3A
	case .lamp: return 0xFFF4C0
	case .laser: return 0xFF4A6A
	case .turret, .cannon: return 0x1E2028
	case .solar: return 0x2A4A8A
	case .magnet: return 0xD83A3A
	case .battery: return 0x8AE85A
	case .barrier: return 0xC07CFF
	case .gauntlet: return 0xFFF07A
	default: return shadeRGB(m.color, 1.3)
	}
}

/// The player's frames with a suit on: the figure drawn three times finer with the suit's pieces over
/// it, frame by frame
func suitFrames(_ plain: [PixelBuf], _ d: SuitDesign, pick: Int = -1) -> [PixelBuf] {
	var out: [PixelBuf] = []
	for (f, b) in plain.enumerated() {
		var cv: PixelBuf = upscale3(b)
		paintSuitPieces(&cv, d, frame: f, pick: pick)
		out.append(cv)
	}
	return out
}

/// Pictures of suit designs for the Assembly Station (drawn again only when the design changes)
final class SuitPictures: @unchecked Sendable {
	static let shared: SuitPictures = SuitPictures()
	var cache: [Int: Image] = [:]
	let plain: [PixelBuf] = humanoidFrames(playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil))

	/// the design worn by a plain figure, in one frame, with a piece shown picked
	func image(_ d: SuitDesign, _ frame: Int, _ pick: Int) -> Image {
		var h: Hasher = Hasher()
		h.combine(d)
		h.combine(frame)
		h.combine(pick)
		let key: Int = h.finalize()
		if let i = cache[key] { return i }
		let f: Int = clampI(frame, 0, plain.count - 1)
		var cv: PixelBuf = upscale3(plain[f])
		paintSuitPieces(&cv, d, frame: f, pick: pick)
		let img: Image = pixImage(cv)
		if cache.count > 48 { cache.removeAll() }
		cache[key] = img
		return img
	}
}

func heartBuf(_ full: Bool) -> PixelBuf {
	let rows: [String] = [".rr.rr..", "rRrrrrr.", "rRrrrrr.", "rrrrrrr.", ".rrrrr..", "..rrr...", "...r....", "........"]
	let col: UInt32 = full ? 0xE02828 : 0x3A2A2A
	let hi: UInt32 = full ? 0xFF9090 : 0x5A4A4A
	var b: PixelBuf = bufFromRows(rows, ["r": col, "R": hi])
	b = padBuf(b)
	b.outline(0x101010)
	return b
}

func foodBuf(_ full: Bool) -> PixelBuf {
	let rows: [String] = ["....bb..", "...bmm..", "..mmmm..", ".mmMmm..", ".mmmm...", "bmmm....", "bb......", "........"]
	let m: UInt32 = full ? 0xC0703A : 0x3A2E26
	let mh: UInt32 = full ? 0xE8A070 : 0x4A3E36
	let bo: UInt32 = full ? 0xF0E8D8 : 0x50504C
	var b: PixelBuf = bufFromRows(rows, ["m": m, "M": mh, "b": bo])
	b = padBuf(b)
	b.outline(0x101010)
	return b
}

func bubbleBuf() -> PixelBuf {
	let rows: [String] = ["..bbb...", ".bWbbb..", "bWbbbbb.", "bbbbbbb.", "bbbbbbb.", ".bbbbb..", "..bbb...", "........"]
	var b: PixelBuf = bufFromRows(rows, ["b": 0x6AB8FF, "W": 0xFFFFFF])
	b = padBuf(b)
	b.outline(0x102040)
	return b
}

func shieldBuf() -> PixelBuf {
	let rows: [String] = ["sssssss.", "sSSSSSs.", "sSssSSs.", "sSSSSSs.", ".sSSSs..", ".sSSSs..", "..sss...", "........"]
	var b: PixelBuf = bufFromRows(rows, ["s": 0x9AA0AA, "S": 0xC8D0DA])
	b = padBuf(b)
	b.outline(0x101010)
	return b
}

func padBuf(_ b: PixelBuf) -> PixelBuf {
	var o = PixelBuf(w: b.w + 2, h: b.h + 2)
	o.blit(b, 1, 1)
	return o
}

// MARK: - The player's look

/// The marker colours of the player's drawing (tools/art/creatures/player.py, MARK): the game swaps
/// each set, light to deep, for the chosen colour's tones. Keep them the same as the drawing's.
enum PlayerInk {
	static let hair: [UInt32] = [0xF00001, 0xF00002, 0xF00003, 0xF00004]
	static let shirt: [UInt32] = [0x00F001, 0x00F002, 0x00F003, 0x00F004]
	static let pants: [UInt32] = [0x0000F1, 0x0000F2, 0x0000F3, 0x0000F4]
	static let shoe: [UInt32] = [0xF0F001, 0xF0F002, 0xF0F003, 0xF0F004]
	static let scarf: [UInt32] = [0x00F0F1, 0x00F0F2, 0x00F0F3, 0x00F0F4]
	static let helm: [UInt32] = [0xF000F1, 0xF000F2, 0xF000F3, 0xF000F4]
	/// the shoes' own colour (leg armour makes them a darker shade of its metal)
	static let shoeColor: UInt32 = 0x24242E
}

/// Four tones of a colour, as the drawings shade with (`ramp` in tools/art/artlib.py): a warm light,
/// the colour, a shadow and a deep shadow that both lean cool
func artRamp(_ c: UInt32, light: UInt32 = 0xFFF0C8, dark: UInt32 = 0x241A38) -> [UInt32] {
	let s1: UInt32 = mixRGB(mixRGB(c, 0x000000, 0.22), dark, 0.18)
	let s2: UInt32 = mixRGB(mixRGB(c, 0x000000, 0.42), dark, 0.30)
	return [mixRGB(c, light, 0.28), c, s1, s2]
}

/// A chosen colour's tones through the game's grade, ready to swap for a set of markers
func lookRamp(_ c: UInt32) -> [UInt32] {
	return artRamp(c).map { artGrade($0) }
}

/// A picture with some colours swapped for others (exact matches only)
func swapColors(_ b: PixelBuf, _ map: [UInt32: UInt32]) -> PixelBuf {
	if map.isEmpty { return b }
	var o: PixelBuf = b
	for i in 0..<o.px.count {
		let c: UInt32 = o.px[i]
		if (c >> 24) == 0 { continue }
		if let n = map[c & 0xFFFFFF] { o.px[i] = (c & 0xFF000000) | n }
	}
	return o
}

/// What the player chose to look like (Settings), and the armour worn over it
struct PlayerLookChoice {
	var hair: Int = 0
	var hairStyle: Int = 0
	var shirt: Int = 0
	var shirtStyle: Int = 0
	var pants: Int = 0
	var pantsStyle: Int = 0
	var scarf: Int = 0
	var head: Tier? = nil
	var chest: Tier? = nil
	var legs: Tier? = nil

	init(_ s: Settings, head: Tier? = nil, chest: Tier? = nil, legs: Tier? = nil) {
		hair = clampI(s.hair, 0, hairChoices.count - 1)
		hairStyle = clampI(s.hairStyle, 0, hairStyleNames.count - 1)
		shirt = clampI(s.shirtColor, 0, shirtChoices.count - 1)
		shirtStyle = clampI(s.shirtStyle, 0, shirtStyleNames.count - 1)
		pants = clampI(s.pantsColor, 0, pantsChoices.count - 1)
		pantsStyle = clampI(s.pantsStyle, 0, pantsStyleNames.count - 1)
		scarf = clampI(s.scarf, 0, scarfChoices.count - 1)
		self.head = head
		self.chest = chest
		self.legs = legs
	}

	/// One number for the whole choice (the sprite caches are keyed by it)
	var key: Int {
		let looks: Int = (((((hair * 8 + hairStyle) * 16 + shirt) * 8 + shirtStyle) * 16 + pants) * 8 + pantsStyle) * 8 + scarf
		let worn: Int = ((head?.rawValue ?? 15) * 16 + (chest?.rawValue ?? 15)) * 16 + (legs?.rawValue ?? 15)
		return looks &* 4096 &+ worn
	}
}

/// The colour armour of a tier is drawn in
func armorLookColor(_ t: Tier) -> UInt32 {
	return t == .wood ? 0x9A5A2A : t.color
}

/// The player's frames: the bare figure with the chosen trousers, shirt, scarf and hair laid over it
/// (each a drawing of only what it changes), then every marker swapped for the chosen colour's
/// tones. Armour takes the place of the clothes: a chest piece is a long-sleeved top of its metal,
/// leg pieces are trousers of it (with darker boots), a helmet goes over the hair.
func playerFrames(_ c: PlayerLookChoice) -> [PixelBuf] {
	var frames: [PixelBuf] = CreatureSheet.frames("player")
	if frames.isEmpty { return frames }
	var map: [UInt32: UInt32] = [:]
	func tone(_ markers: [UInt32], _ col: UInt32) {
		let r: [UInt32] = lookRamp(col)
		for i in 0..<min(markers.count, r.count) { map[markers[i]] = r[i] }
	}
	func lay(_ name: String) {
		let over: [PixelBuf] = CreatureSheet.frames(name)
		for i in 0..<min(frames.count, over.count) { frames[i].blit(over[i], 0, 0) }
	}
	var pantsStyle: Int = c.pantsStyle
	var pantsCol: UInt32 = pantsChoices[c.pants]
	var shoeCol: UInt32 = PlayerInk.shoeColor
	if let t = c.legs {
		pantsStyle = 0
		pantsCol = shadeRGB(armorLookColor(t), 0.85)
		shoeCol = shadeRGB(armorLookColor(t), 0.6)
	}
	var shirtStyle: Int = c.shirtStyle
	var shirtCol: UInt32 = shirtChoices[c.shirt]
	if let t = c.chest {
		shirtStyle = 1
		shirtCol = armorLookColor(t)
	}
	lay(joinText("player_pants_", String(pantsStyle)))
	lay(joinText("player_shirt_", String(shirtStyle)))
	if c.scarf != 0 { lay("player_scarf") }
	lay(joinText("player_hair_", String(c.hairStyle)))
	if c.head != nil { lay("player_helm") }
	tone(PlayerInk.pants, pantsCol)
	tone(PlayerInk.shoe, shoeCol)
	tone(PlayerInk.shirt, shirtCol)
	tone(PlayerInk.hair, hairChoices[c.hair])
	if c.scarf != 0 { tone(PlayerInk.scarf, scarfChoices[c.scarf]) }
	if let t = c.head { tone(PlayerInk.helm, armorLookColor(t)) }
	return frames.map { swapColors($0, map) }
}

/// The player's look for a choice of clothes and armour
func playerLook(_ c: PlayerLookChoice) -> CreatureLook {
	guard let a = CreatureSheet.arts["player"] else {
		let st: HumanStyle = playerStyle(hairIdx: c.hair, scarfIdx: c.scarf, head: c.head, chest: c.chest, legs: c.legs)
		return CreatureLook(frames: humanoidFrames(st), anim: CreatureAnim(), scale: creatureScale)
	}
	return CreatureLook(frames: playerFrames(c), anim: CreatureSheet.anim(a), scale: fineScale, foot: a.foot + 1, cx: a.cx, fine: true)
}

final class Art: @unchecked Sendable {
	static let shared: Art = Art()

	var tiles: [Image] = []
	var tileBufs: [PixelBuf] = []
	var walls: [PixelBuf] = []
	var heartFull: Image
	var heartEmpty: Image
	var foodFull: Image
	var foodEmpty: Image
	var bubble: Image
	var shieldIcon: Image
	var boat: Image
	var boatL: Image
	var parts: [Image] = []
	/// the parts' pictures as pixels (for vehicles drawn from one picture), and a count of art changes
	var partBufs: [PixelBuf] = []
	var gen: Int = 0
	private var icons: [Item: Image] = [:]
	/// weather symbols (see weatherIcon)
	var wxIcons: [Int: Image] = [:]
	var mobSets: [Int: SpriteSet] = [:]
	/// sprites of custom creatures, by slot (rebuilt when the mods change)
	var modMobSets: [Int: SpriteSet] = [:]
	private var playerSets: [Int: SpriteSet] = [:]
	var crack: [Image] = []

	init() {
		let painter: SectionPainter = SectionPainter.shared
		tileBufs = painter.tileBufs
		var ti: [Image] = []
		for b in painter.tileBufs { ti.append(pixImage(b)) }
		tiles = ti
		// dark backdrop walls, indexed by backdrop kind - 1
		walls = painter.wallBufs
		heartFull = pixImage(heartBuf(true))
		heartEmpty = pixImage(heartBuf(false))
		foodFull = pixImage(foodBuf(true))
		foodEmpty = pixImage(foodBuf(false))
		bubble = pixImage(bubbleBuf())
		shieldIcon = pixImage(shieldBuf())
		let bt: PixelBuf = gradeBuf(spritePirateBoat())
		boat = pixImage(bt)
		boatL = pixImage(bt.flipped())
		var ps: [Image] = []
		var pb: [PixelBuf] = []
		for p in PartType.allCases {
			let b: PixelBuf = gradeBuf(partBuf(p))
			pb.append(b)
			ps.append(pixImage(b))
		}
		parts = ps
		partBufs = pb
		var cr: [Image] = []
		for stage in 0..<5 {
			var b = PixelBuf(w: 8, h: 8)
			var rng = RNG(UInt64(stage + 3))
			let n: Int = 3 + stage * 4
			for _ in 0..<n { b.set(rng.int(8), rng.int(8), 0x101010) }
			if stage >= 2 { b.line(1, 2, 6, 5, 0x101010) }
			if stage >= 3 { b.line(5, 0, 2, 7, 0x101010) }
			cr.append(pixImage(b))
		}
		crack = cr
	}

	func tile(_ t: Tile) -> Image { return tiles[Int(t.rawValue)] }

	/// After a world's mods change: new pictures for the reserved tiles, and forget every cached icon
	/// and sprite of custom content
	func refreshModArt() {
		gen &+= 1
		let painter: SectionPainter = SectionPainter.shared
		let base: Int = Int(Tile.modBase)
		for i in 0..<ModLimits.blockSlots where base + i < tiles.count && base + i < painter.tileBufs.count {
			tiles[base + i] = pixImage(painter.tileBufs[base + i])
			tileBufs[base + i] = painter.tileBufs[base + i]
		}
		var keep: [Item: Image] = [:]
		for (k, v) in icons {
			switch k {
			case .custom: continue
			case .block(let t): if t.isMod { continue }
			default: break
			}
			keep[k] = v
		}
		icons = keep
		modMobSets.removeAll()
		// game creatures a mod repaints (or stops repainting) are drawn afresh
		mobSets.removeAll()
	}

	func icon(_ it: Item) -> Image {
		if let i = icons[it] { return i }
		var b: PixelBuf = itemBuf(it)
		switch it {
		case .block, .custom: break
		default: b = gradeBuf(b)
		}
		let img: Image = pixImage(b)
		icons[it] = img
		return img
	}

	func playerSet(_ g: Game) -> SpriteSet {
		let key: Int = g.armorKey
		if let s = playerSets[key] { return s }
		let a = g.armorPieces()
		var s: SpriteSet
		if g.suit.worn && !g.suit.d.pieces.isEmpty {
			// a suit is built on the older figure, drawn three times finer: it stands where it always does
			let st: HumanStyle = playerStyle(hairIdx: g.settings.hair, scarfIdx: g.settings.scarf, head: a.0, chest: a.1, legs: a.2)
			let plain: [PixelBuf] = humanoidFrames(st)
			s = makeSpriteSet(suitFrames(plain, g.suit.d).map { gradeBuf($0) }, hitH: 1.8, fixedScale: 0.125 / Double(suitUnit))
			let bb: (Int, Int, Int, Int) = opaqueBounds(plain[0])
			s.footRow = bb.3 * suitUnit
			s.centerCol = Double(bb.0 + bb.2 + 1) * 0.5 * Double(suitUnit)
		} else {
			s = lookSpriteSet(playerLook(PlayerLookChoice(g.settings, head: a.0, chest: a.1, legs: a.2)), hitH: 1.8)
		}
		if playerSets.count > 24 { playerSets.removeAll() }
		playerSets[key] = s
		return s
	}

	/// The player as chosen on the character screen: from the front and from the side
	func previewPlayer(_ s: Settings) -> (Image, Image) {
		let l: CreatureLook = playerLook(PlayerLookChoice(s))
		let i: Int = l.anim.pose("front", 0)
		let front: Image = pixImage(l.frames[min(i, l.frames.count - 1)])
		let side: Image = pixImage(l.frames[0])
		return (front, side)
	}

	func mobSet(_ m: Mob) -> SpriteSet {
		if m.kind == .custom { return customMobSet(m.cslot, m.mphase) }
		var variant: Int = 0
		switch m.kind {
		case .zombie: variant = m.variant
		case .sheep: variant = m.sheared ? 1 : 0
		case .wolf: variant = m.tame ? 1 : 0
		default: variant = 0
		}
		let key: Int = m.kind.rawValue * 16 + variant
		if let s = mobSets[key] { return s }
		let s: SpriteSet = buildMobSet(m.kind, variant)
		mobSets[key] = s
		return s
	}

	func buildMobSet(_ k: MobKind, _ v: Int) -> SpriteSet {
		if let fr = OverrideRT.shared.creatureArt(k, v) {
			// a mod's repainted sprite, timed like the drawing it was painted over: the hand-drawn one,
			// or the older one for repaints made before the creature was redrawn
			let look: CreatureLook = creatureLook(k, v)
			if look.fine && OverrideRT.shared.mobFine[k.rawValue] == true {
				return makeSpriteSet(fr, hitH: mobDef(k).h, fixedScale: look.scale, anim: look.anim)
			}
			return makeSpriteSet(fr, hitH: mobDef(k).h, fixedScale: creatureScale, anim: olderCreatureArt(k, v).1)
		}
		return creatureSpriteSet(k, v)
	}

	/// A custom creature's sprites (made once per world; refreshModArt clears them)
	func customMobSet(_ slot: Int) -> SpriteSet {
		if let s = modMobSets[slot] { return s }
		guard let r = ModRuntime.shared.mob(slot) else { return creaturePreview(.zombie) }
		let s: SpriteSet = modMobSpriteSet(r.def)
		modMobSets[slot] = s
		return s
	}

	/// A game creature's sprites (the Mod Creator's body picker)
	func creaturePreview(_ k: MobKind) -> SpriteSet {
		let key: Int = k.rawValue * 16
		if let s = mobSets[key] { return s }
		let s: SpriteSet = buildMobSet(k, 0)
		mobSets[key] = s
		return s
	}
}

/// True for creatures drawn with the shared humanoid frames




// MARK: - Sound: every effect is synthesised at first use (no audio files), short and soft, in one style

enum SoundID: Int, CaseIterable {
	case digStone, digDirt, digWood, digSand, digCrystal, digLeaves
	case breakStone, breakDirt, breakWood, breakCrystal
	case place, pickup, craft, chestOpen, door
	case swing, hit, hurt, bow, arrowHit, gun, explosion, land, eat, splash
	case discovery, warn, roar, portal, tap
	/// combat (appended): a knife's flick, a heavy blow, a thrust, a critical hit, several foes at once,
	/// crossbow, sling, blunderbuss, lightning, a fire flask, a dazed foe, a weapon swap, a rare find
	case swingLight, swingHeavy, thrust, crit, multiHit, crossbow, sling, blunderbuss, zap, flask, daze, swap, rareLoot
	/// weather (appended): a close thunderclap, far-off rolling thunder, the crackle before a strike,
	/// an alert chime, a hailstone's tick
	case thunderNear, thunderFar, strikeWarn, weatherAlert, hailTick
	/// alchemy and the suit (appended): a sip, a flask breaking, an infusion taking hold, a suit closing
	case drink, potionBreak, infuse, suitUp
}

enum LoopID: Int, CaseIterable {
	case engine, drill, rain, wind
	/// weather beds (appended): a heavy downpour, a howling gale, hail on everything, a tornado's roar,
	/// a storm siren
	case heavyRain, gale, hail, tornado, siren
}

/// The sound a block makes when dug or broken
func soundMaterial(_ t: Tile) -> Int {
	if isLeafTile(t) || t.isPlant || t == .cobweb { return 5 }
	switch t {
	case .glass, .ice, .glowCrystal, .crystalOre, .diamond: return 4
	case .sand: return 3
	default: break
	}
	switch toolClass(t) {
	case .axe: return 2
	case .shovel, .hoe: return 1
	case .pickaxe: return 0
	}
}

/// Small additive synthesiser: tones with pitch sweeps, filtered noise and plucked strings, each with an
/// attack and an exponential decay, mixed and normalised
struct Synth {
	static let rate: Double = 22050
	var out: [Float]
	var seed: UInt64

	init(_ seconds: Double, seed: UInt64) {
		out = [Float](repeating: 0, count: max(1, Int(seconds * Synth.rate)))
		self.seed = seed &* 2862933555777941757 &+ 3037000493
	}

	static func env(_ t: Double, _ attack: Double, _ decay: Double) -> Double {
		return t < attack ? t / max(attack, 0.0001) : exp(-(t - attack) / max(decay, 0.0001))
	}

	/// wave: 0 sine, 1 triangle, 2 saw, 3 soft square
	mutating func tone(_ f0: Double, _ f1: Double, _ dur: Double, _ attack: Double, _ decay: Double, _ amp: Double, wave: Int = 0, at: Double = 0, vibrato: Double = 0) {
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var ph: Double = 0
		for i in 0..<n {
			let t: Double = Double(i) / Synth.rate
			let k: Double = t / max(dur, 0.0001)
			var f: Double = f0 + (f1 - f0) * k
			if vibrato > 0 { f *= 1.0 + 0.012 * sin(t * vibrato * 2.0 * Double.pi) }
			ph += f / Synth.rate
			let x: Double = ph - floor(ph)
			var v: Double
			switch wave {
			case 1: v = 4.0 * abs(x - 0.5) - 1.0
			case 2: v = 2.0 * x - 1.0
			case 3: v = tanh(sin(x * 2.0 * Double.pi) * 3.0)
			default: v = sin(x * 2.0 * Double.pi)
			}
			out[n0 + i] += Float(v * amp * Synth.env(t, attack, decay))
		}
	}

	mutating func rnd() -> Double {
		seed = seed &* 6364136223846793005 &+ 1442695040888963407
		return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF) * 2.0 - 1.0
	}

	/// noise through a one-pole low-pass (lp) and high-pass (hp); lp can sweep to lp1
	mutating func noise(_ dur: Double, _ attack: Double, _ decay: Double, _ amp: Double, lp: Double, hp: Double, lp1: Double = -1, at: Double = 0) {
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var low: Double = 0
		var low2: Double = 0
		let ah: Double = 1.0 - exp(-2.0 * Double.pi * hp / Synth.rate)
		for i in 0..<n {
			let t: Double = Double(i) / Synth.rate
			let cut: Double = lp1 > 0 ? lp + (lp1 - lp) * (t / dur) : lp
			let al: Double = 1.0 - exp(-2.0 * Double.pi * cut / Synth.rate)
			low += al * (rnd() - low)
			low2 += ah * (low - low2)
			out[n0 + i] += Float((low - low2) * amp * 2.2 * Synth.env(t, attack, decay))
		}
	}

	/// a plucked string (Karplus-Strong)
	mutating func pluck(_ f: Double, _ dur: Double, _ amp: Double, at: Double = 0) {
		let period: Int = max(2, Int(Synth.rate / f))
		var ring: [Double] = (0..<period).map { _ in rnd() }
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var k: Int = 0
		for i in 0..<n {
			let a: Double = ring[k]
			let b: Double = ring[(k + 1) % period]
			ring[k] = (a + b) * 0.497
			out[n0 + i] += Float(a * amp)
			k = (k + 1) % period
		}
	}

	/// peak-normalise and fade the ends so nothing clicks
	mutating func finish(_ peak: Float) {
		var m: Float = 0
		for v in out { m = max(m, abs(v)) }
		let g: Float = m > 0 ? peak / m : 0
		let fade: Int = min(out.count / 2, 66)
		for i in 0..<out.count {
			var v: Float = out[i] * g
			if i < fade { v *= Float(i) / Float(fade) }
			if i > out.count - 1 - fade { v *= Float(out.count - 1 - i) / Float(fade) }
			out[i] = v
		}
	}
}

enum SoundBank {
	static func effect(_ id: SoundID, _ variant: Int) -> [Float] {
		let p: Double = [0.94, 1.0, 1.06][variant % 3]
		let seed: UInt64 = UInt64(id.rawValue * 31 + variant + 1)
		var s: Synth
		var peak: Float = 0.75
		switch id {
		case .digStone, .breakStone:
			let big: Bool = id == .breakStone
			s = Synth(big ? 0.22 : 0.08, seed: seed)
			s.noise(big ? 0.2 : 0.06, 0.002, big ? 0.06 : 0.02, 0.6, lp: 6000, hp: 1500)
			s.tone(900 * p, 700 * p, 0.06, 0.001, 0.015, 0.3)
			if big { s.noise(0.18, 0.01, 0.06, 0.4, lp: 1500, hp: 200, at: 0.03) }
		case .digDirt, .breakDirt:
			let big: Bool = id == .breakDirt
			s = Synth(big ? 0.2 : 0.09, seed: seed)
			s.noise(big ? 0.18 : 0.08, 0.003, big ? 0.06 : 0.03, 0.8, lp: 900, hp: 80)
			s.tone(140 * p, 90 * p, 0.08, 0.002, 0.03, 0.4)
		case .digWood, .breakWood:
			let big: Bool = id == .breakWood
			s = Synth(big ? 0.25 : 0.09, seed: seed)
			s.tone(320 * p, 300 * p, 0.08, 0.001, 0.025, 0.6, wave: 1)
			s.tone(640 * p, 600 * p, 0.06, 0.001, 0.015, 0.25)
			s.noise(0.03, 0.001, 0.01, 0.3, lp: 3000, hp: 400)
			if big { s.tone(240 * p, 200 * p, 0.2, 0.002, 0.06, 0.5, wave: 1, at: 0.04); s.noise(0.15, 0.01, 0.05, 0.3, lp: 1200, hp: 150, at: 0.05) }
		case .digSand:
			s = Synth(0.1, seed: seed)
			s.noise(0.09, 0.005, 0.04, 0.6, lp: 2500, hp: 300)
		case .digCrystal, .breakCrystal:
			let big: Bool = id == .breakCrystal
			s = Synth(big ? 0.45 : 0.3, seed: seed)
			s.tone(1500 * p, 1500 * p, 0.3, 0.002, 0.12, 0.4)
			s.tone(2310 * p, 2300 * p, 0.25, 0.002, 0.08, 0.25)
			s.noise(0.02, 0.001, 0.006, 0.2, lp: 8000, hp: 2000)
			if big { for k in 0..<4 { s.tone((1800 + Double(k) * 420) * p, 1700 * p, 0.2, 0.002, 0.06, 0.18, at: 0.03 * Double(k)) } }
			peak = 0.55
		case .digLeaves:
			s = Synth(0.08, seed: seed)
			s.noise(0.07, 0.01, 0.025, 0.35, lp: 4000, hp: 1200)
			peak = 0.4
		case .place:
			s = Synth(0.09, seed: seed)
			s.tone(200 * p, 120 * p, 0.08, 0.002, 0.025, 0.7)
			s.noise(0.04, 0.001, 0.012, 0.3, lp: 1200, hp: 100)
		case .pickup:
			s = Synth(0.14, seed: seed)
			s.tone(660 * p, 660 * p, 0.06, 0.002, 0.03, 0.4, wave: 1)
			s.tone(990 * p, 990 * p, 0.08, 0.002, 0.04, 0.35, wave: 1, at: 0.05)
			peak = 0.4
		case .craft:
			s = Synth(0.4, seed: seed)
			s.tone(1180 * p, 1180 * p, 0.35, 0.001, 0.1, 0.4)
			s.tone(1770 * p, 1770 * p, 0.3, 0.001, 0.06, 0.3)
			s.tone(2900 * p, 2900 * p, 0.2, 0.001, 0.03, 0.15)
			s.noise(0.02, 0.001, 0.005, 0.3, lp: 7000, hp: 1500)
			peak = 0.5
		case .chestOpen:
			s = Synth(0.3, seed: seed)
			s.tone(150 * p, 130 * p, 0.26, 0.02, 0.12, 0.4, wave: 1, vibrato: 18)
			s.tone(95 * p, 80 * p, 0.08, 0.002, 0.03, 0.4, at: 0.2)
			peak = 0.5
		case .door:
			s = Synth(0.12, seed: seed)
			s.tone(240 * p, 180 * p, 0.08, 0.001, 0.025, 0.6, wave: 1)
			s.noise(0.05, 0.001, 0.015, 0.4, lp: 2000, hp: 150)
		case .swing:
			s = Synth(0.16, seed: seed)
			s.noise(0.15, 0.04, 0.05, 0.4, lp: 700 * p, hp: 250, lp1: 3200 * p)
			peak = 0.35
		case .hit:
			s = Synth(0.12, seed: seed)
			s.noise(0.08, 0.001, 0.025, 0.7, lp: 1800, hp: 100)
			s.tone(120 * p, 70 * p, 0.1, 0.001, 0.04, 0.8)
		case .hurt:
			s = Synth(0.2, seed: seed)
			s.tone(230 * p, 150 * p, 0.17, 0.005, 0.07, 0.5, wave: 1)
			s.noise(0.08, 0.002, 0.03, 0.3, lp: 1200, hp: 100)
		case .bow:
			s = Synth(0.3, seed: seed)
			s.pluck(196 * p, 0.28, 0.6)
			s.noise(0.03, 0.001, 0.01, 0.2, lp: 3000, hp: 600)
			peak = 0.5
		case .arrowHit:
			s = Synth(0.08, seed: seed)
			s.noise(0.04, 0.001, 0.012, 0.5, lp: 2500, hp: 300)
			s.tone(260 * p, 200 * p, 0.05, 0.001, 0.02, 0.4, wave: 1)
			peak = 0.45
		case .gun:
			s = Synth(0.16, seed: seed)
			s.noise(0.12, 0.001, 0.035, 0.9, lp: 7000, hp: 200)
			s.tone(90 * p, 50 * p, 0.12, 0.001, 0.05, 0.7)
			peak = 0.7
		case .explosion:
			s = Synth(1.0, seed: seed)
			s.noise(0.95, 0.003, 0.28, 1.0, lp: 700 * p, hp: 20)
			s.tone(60 * p, 35 * p, 0.8, 0.003, 0.3, 0.8)
			peak = 0.85
		case .land:
			s = Synth(0.09, seed: seed)
			s.noise(0.07, 0.002, 0.025, 0.7, lp: 600, hp: 40)
			s.tone(90 * p, 60 * p, 0.06, 0.001, 0.025, 0.4)
			peak = 0.5
		case .eat:
			s = Synth(0.3, seed: seed)
			for k in 0..<3 { s.noise(0.05, 0.002, 0.015, 0.4, lp: 2500, hp: 500, at: Double(k) * 0.09) }
			peak = 0.4
		case .splash:
			s = Synth(0.3, seed: seed)
			s.noise(0.28, 0.005, 0.1, 0.6, lp: 3000, hp: 400)
			peak = 0.45
		case .discovery:
			s = Synth(0.75, seed: seed)
			for (k, f) in [523.0, 659.0, 784.0, 1047.0].enumerated() { s.tone(f, f, 0.4, 0.004, 0.16, 0.3, wave: 1, at: Double(k) * 0.09) }
			peak = 0.45
		case .warn:
			s = Synth(0.5, seed: seed)
			s.tone(110, 165, 0.45, 0.05, 0.25, 0.35, wave: 3)
			peak = 0.4
		case .roar:
			s = Synth(1.1, seed: seed)
			s.noise(1.0, 0.08, 0.4, 0.8, lp: 500, hp: 40)
			s.tone(75 * p, 55 * p, 1.0, 0.06, 0.4, 0.5, wave: 2, vibrato: 7)
			peak = 0.7
		case .portal:
			s = Synth(1.0, seed: seed)
			for f in [440.0, 660.0, 880.0] { s.tone(f, f * 1.02, 0.9, 0.15, 0.4, 0.25, vibrato: 5) }
			peak = 0.45
		case .tap:
			s = Synth(0.04, seed: seed)
			s.tone(1400, 1300, 0.03, 0.001, 0.008, 0.3)
			peak = 0.25
		case .swingLight:
			s = Synth(0.1, seed: seed)
			s.noise(0.09, 0.01, 0.025, 0.4, lp: 1800 * p, hp: 700, lp1: 6000 * p)
			peak = 0.3
		case .swingHeavy:
			s = Synth(0.3, seed: seed)
			s.noise(0.28, 0.06, 0.08, 0.6, lp: 300 * p, hp: 60, lp1: 1400 * p)
			s.tone(95 * p, 60 * p, 0.25, 0.04, 0.08, 0.4)
			peak = 0.45
		case .thrust:
			s = Synth(0.12, seed: seed)
			s.noise(0.1, 0.005, 0.03, 0.5, lp: 2500 * p, hp: 500, lp1: 7000 * p)
			s.tone(500 * p, 900 * p, 0.05, 0.002, 0.02, 0.15)
			peak = 0.35
		case .crit:
			s = Synth(0.25, seed: seed)
			s.noise(0.08, 0.001, 0.025, 0.7, lp: 2400, hp: 100)
			s.tone(130 * p, 70 * p, 0.12, 0.001, 0.045, 0.8)
			s.tone(1480 * p, 1320 * p, 0.2, 0.001, 0.07, 0.3)
			s.tone(2220 * p, 2000 * p, 0.14, 0.001, 0.04, 0.15)
			peak = 0.75
		case .multiHit:
			s = Synth(0.3, seed: seed)
			s.tone(660 * p, 660 * p, 0.12, 0.002, 0.05, 0.35, wave: 1)
			s.tone(990 * p, 990 * p, 0.16, 0.002, 0.07, 0.35, wave: 1, at: 0.07)
			peak = 0.45
		case .crossbow:
			s = Synth(0.24, seed: seed)
			s.pluck(110 * p, 0.2, 0.7)
			s.noise(0.03, 0.001, 0.008, 0.5, lp: 4000, hp: 800)
			s.tone(180 * p, 120 * p, 0.06, 0.001, 0.02, 0.4, wave: 1, at: 0.01)
			peak = 0.55
		case .sling:
			s = Synth(0.26, seed: seed)
			s.noise(0.2, 0.02, 0.06, 0.35, lp: 900 * p, hp: 200, lp1: 2600 * p)
			for i in 0..<s.out.count { s.out[i] *= Float(0.6 + 0.4 * sin(Double(i) / Synth.rate * 38.0 * 2.0 * Double.pi)) }
			s.noise(0.05, 0.001, 0.015, 0.4, lp: 3500, hp: 600, at: 0.18)
			peak = 0.4
		case .blunderbuss:
			s = Synth(0.5, seed: seed)
			s.noise(0.45, 0.001, 0.12, 1.0, lp: 4500 * p, hp: 60, lp1: 900)
			s.tone(70 * p, 32 * p, 0.4, 0.001, 0.14, 0.9)
			peak = 0.85
		case .zap:
			s = Synth(0.3, seed: seed)
			for k in 0..<5 { s.noise(0.03, 0.001, 0.01, 0.6, lp: 9000, hp: 2200, at: Double(k) * 0.045) }
			s.tone(1900 * p, 420 * p, 0.25, 0.001, 0.08, 0.35, wave: 2)
			peak = 0.6
		case .flask:
			s = Synth(0.6, seed: seed)
			s.noise(0.06, 0.001, 0.02, 0.6, lp: 9000, hp: 3000)
			for k in 0..<3 { s.tone((2600 + Double(k) * 700) * p, 2400 * p, 0.08, 0.001, 0.03, 0.15, at: 0.01 * Double(k)) }
			s.noise(0.5, 0.08, 0.2, 0.7, lp: 400, hp: 60, lp1: 1600, at: 0.04)
			peak = 0.6
		case .daze:
			s = Synth(0.35, seed: seed)
			for (k, f) in [1500.0, 1900.0, 1700.0].enumerated() { s.tone(f * p, f * 1.05 * p, 0.08, 0.004, 0.03, 0.25, at: Double(k) * 0.09) }
			peak = 0.3
		case .swap:
			s = Synth(0.1, seed: seed)
			s.tone(900 * p, 850 * p, 0.04, 0.001, 0.012, 0.35, wave: 1)
			s.tone(1300 * p, 1250 * p, 0.04, 0.001, 0.012, 0.3, wave: 1, at: 0.045)
			s.noise(0.02, 0.001, 0.006, 0.2, lp: 6000, hp: 1500)
			peak = 0.3
		case .rareLoot:
			s = Synth(0.9, seed: seed)
			for (k, f) in [784.0, 988.0, 1175.0, 1568.0, 1976.0].enumerated() { s.tone(f, f, 0.45, 0.003, 0.18, 0.28, wave: 1, at: Double(k) * 0.07) }
			for k in 0..<6 { s.tone(3000 + Double(k) * 310, 2900, 0.1, 0.001, 0.04, 0.08, at: 0.35 + Double(k) * 0.05) }
			peak = 0.5
		case .thunderNear:
			// a sharp crack, then the long rumble rolling away under it
			s = Synth(2.4, seed: seed)
			s.noise(0.09, 0.001, 0.03, 1.0, lp: 9000, hp: 900)
			s.noise(0.25, 0.004, 0.09, 0.8, lp: 2600 * p, hp: 120, at: 0.02)
			s.noise(2.3, 0.03, 0.75, 0.9, lp: 420 * p, hp: 25, lp1: 160, at: 0.05)
			s.noise(1.2, 0.05, 0.35, 0.5, lp: 300 * p, hp: 25, at: 0.6 + 0.2 * Double(variant))
			s.tone(48 * p, 34 * p, 1.6, 0.02, 0.6, 0.35)
			peak = 0.9
		case .thunderFar:
			// rolls of low rumble, no crack (the high notes are lost on the way)
			s = Synth(3.0, seed: seed)
			s.noise(2.6, 0.25, 0.9, 0.7, lp: 260 * p, hp: 22, lp1: 140)
			s.noise(1.0, 0.1, 0.35, 0.55, lp: 220 * p, hp: 22, at: 0.5 + 0.3 * Double(variant))
			s.noise(1.0, 0.1, 0.35, 0.45, lp: 200 * p, hp: 22, at: 1.4)
			s.tone(40 * p, 30 * p, 2.4, 0.3, 0.8, 0.25)
			peak = 0.6
		case .strikeWarn:
			// the buzz and crackle in the air just before a strike
			s = Synth(0.7, seed: seed)
			for k in 0..<9 { s.noise(0.035, 0.001, 0.012, 0.45 + 0.05 * Double(k), lp: 9000, hp: 2600, at: Double(k) * 0.07) }
			s.tone(120 * p, 180 * p, 0.65, 0.2, 0.3, 0.2, wave: 2, vibrato: 30)
			peak = 0.5
		case .weatherAlert:
			s = Synth(0.9, seed: seed)
			s.tone(880, 880, 0.3, 0.005, 0.12, 0.35, wave: 1)
			s.tone(660, 660, 0.4, 0.005, 0.18, 0.35, wave: 1, at: 0.28)
			s.tone(880, 880, 0.3, 0.005, 0.12, 0.25, wave: 1, at: 0.56)
			peak = 0.45
		case .hailTick:
			s = Synth(0.05, seed: seed)
			s.noise(0.03, 0.0005, 0.008, 0.6, lp: 9000, hp: 2500)
			s.tone(2600 * p, 2400 * p, 0.02, 0.0005, 0.006, 0.3)
			peak = 0.3
		case .drink:
			// three soft gulps
			s = Synth(0.5, seed: seed)
			for k in 0..<3 { s.tone(320 * p, 220 * p, 0.09, 0.01, 0.04, 0.35, wave: 0, at: Double(k) * 0.14) }
			s.noise(0.4, 0.02, 0.15, 0.12, lp: 900, hp: 200)
			peak = 0.4
		case .potionBreak:
			// glass, then a hiss
			s = Synth(0.55, seed: seed)
			s.noise(0.05, 0.0008, 0.015, 0.7, lp: 9500, hp: 3500)
			for k in 0..<4 { s.tone((2900 + Double(k) * 520) * p, 2500 * p, 0.07, 0.001, 0.025, 0.14, at: 0.008 * Double(k)) }
			s.noise(0.45, 0.04, 0.16, 0.45, lp: 2600, hp: 500, at: 0.05)
			peak = 0.55
		case .infuse:
			// a rising shimmer
			s = Synth(0.8, seed: seed)
			for (k, f) in [440.0, 554.0, 659.0, 880.0].enumerated() { s.tone(f * p, f * 1.01 * p, 0.45, 0.04, 0.2, 0.22, wave: 1, at: Double(k) * 0.08, vibrato: 6) }
			peak = 0.45
		case .suitUp:
			// servos and a latch
			s = Synth(0.45, seed: seed)
			s.tone(180 * p, 420 * p, 0.25, 0.01, 0.1, 0.3, wave: 3)
			s.noise(0.06, 0.001, 0.02, 0.6, lp: 4000, hp: 800, at: 0.28)
			s.tone(1200 * p, 1100 * p, 0.05, 0.001, 0.02, 0.25, at: 0.3)
			peak = 0.45
		}
		s.finish(peak)
		return s.out
	}

	/// Seamless loops: whole numbers of cycles per loop, and noise cross-faded into its own start
	static func loop(_ id: LoopID) -> [Float] {
		var s: Synth
		switch id {
		case .engine:
			s = Synth(1.0, seed: 101)
			s.tone(55, 55, 1.0, 0.0001, 1000, 0.5, wave: 2)
			s.tone(110, 110, 1.0, 0.0001, 1000, 0.25, wave: 3)
			for i in 0..<s.out.count { s.out[i] *= Float(0.75 + 0.25 * sin(Double(i) / Synth.rate * 9.0 * 2.0 * Double.pi)) }
		case .drill:
			s = Synth(1.0, seed: 102)
			s.tone(180, 180, 1.0, 0.0001, 1000, 0.4, wave: 3)
			s.noise(1.0, 0.0001, 1000, 0.2, lp: 2000, hp: 300)
			for i in 0..<s.out.count { s.out[i] *= Float(0.7 + 0.3 * sin(Double(i) / Synth.rate * 30.0 * 2.0 * Double.pi)) }
		case .rain:
			s = Synth(2.2, seed: 103)
			s.noise(2.2, 0.0001, 1000, 0.6, lp: 3000, hp: 500)
		case .wind:
			s = Synth(3.2, seed: 104)
			s.noise(3.2, 0.0001, 1000, 0.6, lp: 300, hp: 40)
			for i in 0..<s.out.count { s.out[i] *= Float(0.6 + 0.4 * sin(Double(i) / Synth.rate / 3.0 * 2.0 * Double.pi)) }
		case .heavyRain:
			// denser and deeper than light rain, with slow surges
			s = Synth(3.0, seed: 105)
			s.noise(3.0, 0.0001, 1000, 0.7, lp: 1800, hp: 120)
			s.noise(3.0, 0.0001, 1000, 0.3, lp: 5000, hp: 1500)
			for i in 0..<s.out.count { s.out[i] *= Float(0.8 + 0.2 * sin(Double(i) / Synth.rate / 1.4 * 2.0 * Double.pi)) }
		case .gale:
			// a howl: band-limited noise whose loudness rises and falls in gusts
			s = Synth(4.2, seed: 106)
			s.noise(4.2, 0.0001, 1000, 0.6, lp: 900, hp: 250)
			s.noise(4.2, 0.0001, 1000, 0.4, lp: 260, hp: 60)
			for i in 0..<s.out.count {
				let t: Double = Double(i) / Synth.rate
				s.out[i] *= Float(0.55 + 0.3 * sin(t / 2.0 * 2.0 * Double.pi) + 0.15 * sin(t / 0.5 * 2.0 * Double.pi))
			}
		case .hail:
			// countless small stones ticking on everything
			s = Synth(2.2, seed: 107)
			s.noise(2.2, 0.0001, 1000, 0.15, lp: 6000, hp: 1800)
			var k: Int = 0
			while k < 110 {
				let at: Double = s.rnd() * 0.5 + 0.5
				s.noise(0.02, 0.0005, 0.006, 0.6, lp: 9000, hp: 2400, at: at * 2.0)
				k += 1
			}
		case .tornado:
			// a deep, steady roar like a train that does not pass
			s = Synth(3.4, seed: 108)
			s.noise(3.4, 0.0001, 1000, 0.8, lp: 180, hp: 25)
			s.noise(3.4, 0.0001, 1000, 0.3, lp: 700, hp: 200)
			for i in 0..<s.out.count { s.out[i] *= Float(0.75 + 0.25 * sin(Double(i) / Synth.rate / 0.85 * 2.0 * Double.pi)) }
		case .siren:
			// a siren's slow rise and fall: the pitch's swing averages out over the loop, so the wave
			// ends exactly where it began
			s = Synth(4.0, seed: 109)
			var ph: Double = 0
			for i in 0..<s.out.count {
				let t: Double = Double(i) / Synth.rate
				let f: Double = 640.0 + 220.0 * sin(t / 4.0 * 2.0 * Double.pi)
				ph += f / Synth.rate
				let x: Double = ph - floor(ph)
				s.out[i] = Float(tanh(sin(x * 2.0 * Double.pi) * 2.0) * 0.5)
			}
		}
		if id == .siren {
			// the siren's wave already joins up end to start: no fades, which would dip at the seam
			var m: Float = 0
			for v in s.out { m = max(m, abs(v)) }
			if m > 0 { for i in 0..<s.out.count { s.out[i] *= 0.6 / m } }
		} else {
			s.finish(0.6)
		}
		if id == .rain || id == .wind || id == .heavyRain || id == .gale || id == .hail || id == .tornado {
			// fold the extra 0.2 s back over the start so the loop point is seamless
			let tail: Int = Int(0.2 * Synth.rate)
			let n: Int = s.out.count - tail
			for i in 0..<tail {
				let k: Float = Float(i) / Float(tail)
				s.out[i] = s.out[i] * k + s.out[n + i] * (1 - k)
			}
			s.out.removeLast(tail)
		}
		return s.out
	}
}

/// Plays the effects: a small pool of voices (the oldest is cut off when all are busy), a minimum gap
/// between repeats of the same effect, and four looping beds whose volume follows the game.
final class Sound {
	static let shared: Sound = Sound()
	private let engine: AVAudioEngine = AVAudioEngine()
	private var format: AVAudioFormat? = nil
	private var voices: [AVAudioPlayerNode] = []
	private var loopNodes: [AVAudioPlayerNode] = []
	private var buffers: [Int: [AVAudioPCMBuffer]] = [:]
	private var lastPlay: [Int: Double] = [:]
	private var nextVoice: Int = 0
	private(set) var running: Bool = false
	private var started: Bool = false
	var enabled: Bool = true
	var sfxVolume: Float = 0.7
	var ambienceVolume: Float = 0.5

	/// Call once the game is on screen
	func start() {
		if started { return }
		started = true
		#if os(iOS)
		// ambient: mixes with the player's own music and respects the silent switch
		try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
		try? AVAudioSession.sharedInstance().setActive(true)
		#endif
		guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1) else { return }
		format = fmt
		for _ in 0..<8 {
			let n = AVAudioPlayerNode()
			engine.attach(n)
			engine.connect(n, to: engine.mainMixerNode, format: fmt)
			voices.append(n)
		}
		for _ in LoopID.allCases {
			let n = AVAudioPlayerNode()
			engine.attach(n)
			engine.connect(n, to: engine.mainMixerNode, format: fmt)
			n.volume = 0
			loopNodes.append(n)
		}
		engine.prepare()
		do { try engine.start() } catch { return }
		running = true
		for v in voices { v.play() }
		for l in LoopID.allCases {
			let n: AVAudioPlayerNode = loopNodes[l.rawValue]
			if let b = makeBuffer(SoundBank.loop(l)) {
				n.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
				n.play()
			}
		}
	}

	private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
		guard let fmt = format, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
		b.frameLength = AVAudioFrameCount(samples.count)
		if let ch = b.floatChannelData {
			for i in 0..<samples.count { ch[0][i] = samples[i] }
		}
		return b
	}

	static func minGap(_ id: SoundID) -> Double {
		switch id {
		case .pickup, .tap: return 0.05
		case .digStone, .digDirt, .digWood, .digSand, .digCrystal, .digLeaves: return 0.09
		case .hit, .arrowHit: return 0.06
		case .land, .place, .door: return 0.08
		case .warn: return 0.35
		case .roar, .portal, .discovery, .explosion, .rareLoot: return 0.25
		case .thunderNear: return 0.3
		case .thunderFar: return 0.5
		case .strikeWarn: return 0.6
		case .weatherAlert: return 2.0
		case .hailTick: return 0.07
		case .crit, .multiHit, .swingLight: return 0.05
		case .daze, .flask: return 0.15
		default: return 0.04
		}
	}

	func play(_ id: SoundID, _ volume: Double = 1.0) {
		guard running && enabled && sfxVolume > 0 && volume > 0.02 else { return }
		let now: Double = Date().timeIntervalSinceReferenceDate
		if let t = lastPlay[id.rawValue], now - t < Sound.minGap(id) { return }
		lastPlay[id.rawValue] = now
		if buffers[id.rawValue] == nil {
			var list: [AVAudioPCMBuffer] = []
			for v in 0..<3 { if let b = makeBuffer(SoundBank.effect(id, v)) { list.append(b) } }
			buffers[id.rawValue] = list
		}
		guard let list = buffers[id.rawValue], !list.isEmpty else { return }
		let b: AVAudioPCMBuffer = list[Int.random(in: 0..<list.count)]
		let v: AVAudioPlayerNode = voices[nextVoice]
		nextVoice = (nextVoice + 1) % voices.count
		v.volume = Float(min(1.0, volume)) * sfxVolume
		v.scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
		if !v.isPlaying { v.play() }
	}

	/// Silences every loop at once: leaving a world (nothing sets their volumes any more after that)
	func silenceLoops() {
		for n in loopNodes { n.volume = 0 }
	}

	func setLoop(_ id: LoopID, _ volume: Double) {
		guard running else { return }
		let target: Float = enabled ? Float(max(0, min(1, volume))) * ambienceVolume : 0
		let n: AVAudioPlayerNode = loopNodes[id.rawValue]
		// ease toward the target so loops fade in and out instead of popping
		n.volume += (target - n.volume) * 0.15
	}
}

extension Game {
	/// A sound effect; world events further than ~32 blocks from the player are not heard
	func sfx(_ id: SoundID, at x: Double? = nil, _ volume: Double = 1.0) {
		var v: Double = volume
		if let wx = x { v *= max(0, 1.0 - abs(wx - pb.x) / 32.0) }
		Sound.shared.play(id, v)
	}

	func digSound(_ t: Tile, broke: Bool) {
		let m: Int = soundMaterial(t)
		let id: SoundID
		switch m {
		case 0: id = broke ? .breakStone : .digStone
		case 1: id = broke ? .breakDirt : .digDirt
		case 2: id = broke ? .breakWood : .digWood
		case 3: id = broke ? .breakDirt : .digSand
		case 4: id = broke ? .breakCrystal : .digCrystal
		default: id = .digLeaves
		}
		sfx(id, broke ? 0.9 : 0.6)
	}

	/// Once a frame: settings into the mixer, and the looping beds (engine, drill, rain, wind)
	func updateAudio() {
		let snd: Sound = Sound.shared
		snd.enabled = settings.soundOn
		snd.sfxVolume = Float(settings.sfxVolume)
		snd.ambienceVolume = Float(settings.ambienceVolume)
		if !snd.running { return }
		var engineV: Double = 0
		var drillV: Double = 0
		if let v = inVehicle, v.engines > 0, v.fuel > 0 || isCreative {
			engineV = 0.3 + 0.5 * abs(v.throttle)
			if v.drilling { drillV = 0.7 }
		}
		snd.setLoop(.engine, engineV)
		snd.setLoop(.drill, drillV)
		// the weather beds, layered: light and heavy rain, wind and gale, hail, a tornado, a siren. They
		// all run from the start and only their volumes move, so nothing restarts or clicks. Under a roof
		// the rain and wind are muffled rather than cut.
		let L: LocalWeather = wxHere
		let ow: Bool = world.dim == .overworld && settings.weatherOn
		let muffle: Double = shelterLevel == 0 ? 1.0 : (shelterLevel == 1 ? 0.55 : (shelterLevel == 2 ? 0.3 : 0.08))
		let rainV: Double = ow && !L.snow ? L.precip : 0
		snd.setLoop(.rain, min(1.0, rainV * 1.1) * muffle)
		snd.setLoop(.heavyRain, clampD((rainV - 0.45) * 1.6, 0, 1) * muffle)
		let aw: Double = ow ? abs(L.wind) : 0
		let high: Double = world.dim == .overworld && shelterLevel == 0 && pb.y < 80 ? 0.35 : 0
		snd.setLoop(.wind, world.dim == .umbral ? 0.6 : max(high, clampD(aw / 10.0, 0, 0.8) * muffle))
		snd.setLoop(.gale, clampD((aw - 8.0) / 8.0, 0, 1) * muffle)
		snd.setLoop(.hail, ow ? clampD(L.hail * 1.2, 0, 1) * muffle : 0)
		var roar: Double = 0
		if ow, let e = weather.tornado { roar = clampD(1.0 - abs(e.x - pb.x) / 90.0, 0, 1) * e.funnel * max(muffle, 0.4) }
		snd.setLoop(.tornado, roar)
		snd.setLoop(.siren, sirenLevel * 0.7)
	}
}


// MARK: - Weather: one simulation for the whole overworld
// The weather is a single saved simulation (WeatherSim), stepped once a frame by the game clock. It
// holds the state over the region (clear, rain, a storm...), the plan of what comes next (the forecast
// devices read it directly), amounts that ease toward whatever the state and the settings allow (cloud,
// rain, wind, lightning, hail, cold) and the two rare events (a tornado, a hurricane). What a place
// actually gets is worked out from that and the place itself: storm cells drift over the land with the
// wind (a noise field in world space, so it is the same whichever chunks happen to be loaded), deserts
// stay dry, cold country gets snow and the coast takes the brunt of a hurricane. Nothing keeps a timer
// of its own: rain, lightning, hail, cold and the weather devices all read the simulation.

enum WeatherKind: Int, Codable, CaseIterable {
	case clear, partlyCloudy, overcast, lightRain, heavyRain, thunderstorm, strongWind, windstorm, hailstorm, snowfall, blizzard, tornado, hurricane

	var name: String {
		switch self {
		case .clear: return "Clear"
		case .partlyCloudy: return "Partly cloudy"
		case .overcast: return "Overcast"
		case .lightRain: return "Light rain"
		case .heavyRain: return "Heavy rain"
		case .thunderstorm: return "Thunderstorm"
		case .strongWind: return "Strong wind"
		case .windstorm: return "Windstorm"
		case .hailstorm: return "Hailstorm"
		case .snowfall: return "Snowfall"
		case .blizzard: return "Blizzard"
		case .tornado: return "Tornado"
		case .hurricane: return "Hurricane"
		}
	}

	var severe: Bool {
		switch self {
		case .thunderstorm, .windstorm, .hailstorm, .blizzard, .tornado, .hurricane: return true
		default: return false
		}
	}


	/// What a spell of it brings at full strength (before the settings and the place are applied)
	var profile: WeatherProfile {
		switch self {
		case .clear: return WeatherProfile(cloud: 0.04, wind: 1.2, gust: 0.25)
		case .partlyCloudy: return WeatherProfile(cloud: 0.35, wind: 2.4, gust: 0.35)
		case .overcast: return WeatherProfile(cloud: 0.72, wind: 3.0, gust: 0.35)
		case .lightRain: return WeatherProfile(cloud: 0.78, precip: 0.38, wind: 3.0, gust: 0.4, cover: 0.55)
		case .heavyRain: return WeatherProfile(cloud: 0.9, precip: 0.85, wind: 5.0, gust: 0.5, cover: 0.8)
		case .thunderstorm: return WeatherProfile(cloud: 1.0, precip: 0.9, wind: 7.0, gust: 0.7, thunder: 6.0, cover: 0.75)
		case .strongWind: return WeatherProfile(cloud: 0.4, wind: 9.0, gust: 0.6, cover: 0.3)
		case .windstorm: return WeatherProfile(cloud: 0.7, precip: 0.15, wind: 14.0, gust: 0.8, cover: 0.4)
		case .hailstorm: return WeatherProfile(cloud: 0.95, precip: 0.55, wind: 6.0, gust: 0.6, thunder: 2.0, hail: 1.0, cover: 0.6)
		case .snowfall: return WeatherProfile(cloud: 0.8, precip: 0.6, wind: 2.5, gust: 0.4, cover: 0.85, chill: 0.2)
		case .blizzard: return WeatherProfile(cloud: 1.0, precip: 1.0, wind: 13.0, gust: 0.7, cover: 1.0, chill: 1.0)
		case .tornado: return WeatherProfile(cloud: 1.0, precip: 0.75, wind: 8.0, gust: 0.8, thunder: 5.0, hail: 0.25, cover: 0.7)
		case .hurricane: return WeatherProfile(cloud: 1.0, precip: 1.0, wind: 15.0, gust: 0.8, thunder: 2.0, cover: 1.0)
		}
	}

	/// How long a spell of it lasts, in seconds of play (a day is 720)
	var spell: ClosedRange<Double> {
		switch self {
		case .clear: return 180...420
		case .partlyCloudy: return 150...300
		case .overcast: return 120...240
		case .lightRain: return 90...200
		case .heavyRain: return 70...150
		case .thunderstorm: return 80...150
		case .strongWind: return 70...140
		case .windstorm: return 60...110
		case .hailstorm: return 35...70
		case .snowfall: return 120...240
		case .blizzard: return 80...150
		case .tornado: return 95...120
		case .hurricane: return 330...440
		}
	}
}

struct WeatherProfile {
	var cloud: Double = 0
	var precip: Double = 0
	/// typical air speed over open ground, in blocks per second
	var wind: Double = 0
	/// how far the wind gusts above and below that (0 steady ... 1 wild)
	var gust: Double = 0
	/// lightning strikes per minute over the land around the player
	var thunder: Double = 0
	var hail: Double = 0
	/// how much of the land the rain covers at once (0 scattered showers ... 1 everywhere)
	var cover: Double = 0
	/// how much colder it makes the land
	var chill: Double = 0
}

struct WeatherStep: Codable {
	var kind: WeatherKind
	var dur: Double
}

/// A tornado: it forms far off (the warning), touches down and crosses the land with the wind, then
/// ropes out. Its strength never changes on the way, so its danger can be judged from afar.
struct TornadoEvent: Codable {
	var x: Double
	/// which way it travels (-1 west, 1 east) and how fast
	var dir: Double
	var speed: Double
	/// 0 forming (the warning), 1 on the ground, 2 roping out
	var phase: Int = 0
	var t: Double = 0
	var warnDur: Double
	var groundDur: Double
	var strength: Double
	var wander: Double
	/// blocks it has torn loose so far (it stops tearing at a limit)
	var broken: Int = 0
	var uid: Int = 0
	/// closest it came to the player (for the journal)
	var closest: Double = 1e9

	static let ropeDur: Double = 8.0

	/// 0...1: how much of a funnel there is (grows while forming, thins as it ropes out)
	var funnel: Double {
		switch phase {
		case 0: return clampD((t - warnDur + 12.0) / 12.0, 0, 1) * 0.55
		case 1: return min(1.0, 0.55 + t / 4.0)
		default: return max(0, 1.0 - t / TornadoEvent.ropeDur)
		}
	}
	/// how hard it blows and tears (0 while it is only forming)
	var force: Double {
		switch phase {
		case 0: return 0
		case 1: return strength * min(1.0, t / 4.0)
		default: return strength * max(0, 1.0 - t / TornadoEvent.ropeDur)
		}
	}
}

enum HurricaneStage: Int, Codable, CaseIterable {
	case approaching, intensifying, peak, eye, backside, weakening, clearing

	var name: String {
		switch self {
		case .approaching: return "approaching"
		case .intensifying: return "intensifying"
		case .peak: return "at its height"
		case .eye: return "the eye is passing"
		case .backside: return "back wall of the storm"
		case .weakening: return "weakening"
		case .clearing: return "clearing"
		}
	}
	/// how hard it blows in this stage (0...1 of its strength)
	var force: Double {
		switch self {
		case .approaching: return 0.35
		case .intensifying: return 0.7
		case .peak: return 1.0
		case .eye: return 0.12
		case .backside: return 0.95
		case .weakening: return 0.55
		case .clearing: return 0.2
		}
	}
	/// share of the whole storm's length
	var share: Double {
		switch self {
		case .approaching: return 0.26
		case .intensifying: return 0.15
		case .peak: return 0.13
		case .eye: return 0.05
		case .backside: return 0.12
		case .weakening: return 0.15
		case .clearing: return 0.14
		}
	}
}

/// A hurricane comes in off the sea in stages, blowing onshore until the eye passes and offshore
/// after it. It is felt hardest at the coast and fades inland.
struct HurricaneEvent: Codable {
	var stage: HurricaneStage = .approaching
	var t: Double = 0
	var total: Double
	/// the side the sea (and the storm) is on: -1 west, 1 east
	var side: Double
	/// where it comes ashore
	var coastX: Double
	var strength: Double
	/// eased 0...1 force now
	var force: Double = 0
	var broken: Int = 0
	var closest: Double = 1e9

	var stageDur: Double { return total * stage.share }
	/// seconds from now until the end of each stage, then the time it is over
	func timeLeft() -> Double {
		var left: Double = stageDur - t
		var k: Int = stage.rawValue + 1
		while k < HurricaneStage.allCases.count {
			left += total * HurricaneStage.allCases[k].share
			k += 1
		}
		return max(0, left)
	}
}

/// Wet ground and lying snow over a 48-block stretch of land
struct GroundCell: Codable {
	var wet: Double = 0
	var snow: Double = 0
	var t: Double = 0
}

struct SurgeCell: Codable, Hashable {
	var x: Int
	var y: Int
}

/// A storm the player lived through, for the journal
struct StormRecord: Codable {
	var kind: Int
	var day: Int
	var note: String
}

struct WeatherSim: Codable {
	var kind: WeatherKind = .clear
	var stateT: Double = 0
	var stateDur: Double = 300
	/// what comes after the present spell, in order (kept four steps long)
	var plan: [WeatherStep] = []
	/// smoothed amounts (see WeatherProfile); wind is signed, positive blowing east
	var cloud: Double = 0.04
	var precip: Double = 0
	var wind: Double = 1.0
	var gust: Double = 0.25
	var thunder: Double = 0
	var hail: Double = 0
	var chill: Double = 0
	var cover: Double = 0
	/// which way the wind is set to blow (-1 / 1); it may turn round between spells
	var windDir: Double = 1
	/// how far the storm cells and the clouds have drifted with the wind, in blocks
	var drift: Double = 0
	var cloudDrift: Double = 0
	/// weather clock: seconds of play since the simulation began
	var t: Double = 0
	var rngS: UInt64 = 0x51ED_2701
	/// a second stream for what the weather does (where bolts fall, what the wind tears loose), so
	/// those never change what the weather itself does next
	var fxS: UInt64 = 0xFACE_0FF5
	/// severe weather (and tornadoes and hurricanes, more rarely still) may not begin before these
	/// times: each severe spell is followed by a calm (a new world starts with one)
	var calmUntil: Double = 600
	var tornadoUntil: Double = 1200
	var hurricaneUntil: Double = 1800
	var bigHail: Bool = false
	var tornado: TornadoEvent? = nil
	var hurricane: HurricaneEvent? = nil
	var cells: [Int: GroundCell] = [:]
	/// what weather devices hold (rain collectors, turbines), by place
	var store: [String: Double] = [:]
	/// sea water a storm surge pushed ashore, taken away again when the storm passes
	var surge: [SurgeCell] = []
	/// the settings the plan was made under (a change makes it again)
	var planSig: Int = -1
	/// whether the master switch was on last frame
	var wasOn: Bool = true

	init() {}

	enum CodingKeys: String, CodingKey {
		case kind, stateT, stateDur, plan, cloud, precip, wind, gust, thunder, hail, chill, cover, windDir, drift, cloudDrift, t, rngS, fxS
		case calmUntil, tornadoUntil, hurricaneUntil, bigHail, tornado, hurricane, cells, store, surge, planSig, wasOn
	}

	/// Missing or damaged fields fall back to their defaults, so a weather record never stops a world
	/// from loading
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = (try? c.decodeIfPresent(WeatherKind.self, forKey: .kind)) ?? .clear
		stateT = (try? c.decodeIfPresent(Double.self, forKey: .stateT)) ?? 0
		stateDur = (try? c.decodeIfPresent(Double.self, forKey: .stateDur)) ?? 300
		plan = (try? c.decodeIfPresent([WeatherStep].self, forKey: .plan)) ?? []
		cloud = (try? c.decodeIfPresent(Double.self, forKey: .cloud)) ?? 0.04
		precip = (try? c.decodeIfPresent(Double.self, forKey: .precip)) ?? 0
		wind = (try? c.decodeIfPresent(Double.self, forKey: .wind)) ?? 1.0
		gust = (try? c.decodeIfPresent(Double.self, forKey: .gust)) ?? 0.25
		thunder = (try? c.decodeIfPresent(Double.self, forKey: .thunder)) ?? 0
		hail = (try? c.decodeIfPresent(Double.self, forKey: .hail)) ?? 0
		chill = (try? c.decodeIfPresent(Double.self, forKey: .chill)) ?? 0
		cover = (try? c.decodeIfPresent(Double.self, forKey: .cover)) ?? 0
		windDir = (try? c.decodeIfPresent(Double.self, forKey: .windDir)) ?? 1
		drift = (try? c.decodeIfPresent(Double.self, forKey: .drift)) ?? 0
		cloudDrift = (try? c.decodeIfPresent(Double.self, forKey: .cloudDrift)) ?? 0
		t = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
		rngS = (try? c.decodeIfPresent(UInt64.self, forKey: .rngS)) ?? 0x51ED_2701
		fxS = (try? c.decodeIfPresent(UInt64.self, forKey: .fxS)) ?? 0xFACE_0FF5
		calmUntil = (try? c.decodeIfPresent(Double.self, forKey: .calmUntil)) ?? 600
		tornadoUntil = (try? c.decodeIfPresent(Double.self, forKey: .tornadoUntil)) ?? 1200
		hurricaneUntil = (try? c.decodeIfPresent(Double.self, forKey: .hurricaneUntil)) ?? 1800
		bigHail = (try? c.decodeIfPresent(Bool.self, forKey: .bigHail)) ?? false
		tornado = (try? c.decodeIfPresent(TornadoEvent.self, forKey: .tornado)) ?? nil
		hurricane = (try? c.decodeIfPresent(HurricaneEvent.self, forKey: .hurricane)) ?? nil
		cells = (try? c.decodeIfPresent([Int: GroundCell].self, forKey: .cells)) ?? [:]
		store = (try? c.decodeIfPresent([String: Double].self, forKey: .store)) ?? [:]
		surge = (try? c.decodeIfPresent([SurgeCell].self, forKey: .surge)) ?? []
		planSig = (try? c.decodeIfPresent(Int.self, forKey: .planSig)) ?? -1
		wasOn = (try? c.decodeIfPresent(Bool.self, forKey: .wasOn)) ?? true
		// a record from a broken save must not leave the simulation stuck
		if !stateDur.isFinite || stateDur <= 0 { stateDur = 120 }
		if !stateT.isFinite || stateT < 0 { stateT = 0 }
		if !wind.isFinite { wind = 1 }
	}

	/// The simulation's own random numbers (saved with it, so a reloaded world carries on the same way)
	mutating func rand() -> Double {
		rngS = rngS &+ 0x9E3779B97F4A7C15
		var z: UInt64 = rngS
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		z = z ^ (z >> 31)
		return Double(z >> 11) / 9007199254740992.0
	}

	mutating func pick(_ r: ClosedRange<Double>) -> Double {
		let u: Double = rand()
		return r.lowerBound + (r.upperBound - r.lowerBound) * u
	}

	/// The effects' stream (see fxS)
	mutating func fx() -> Double {
		fxS = fxS &+ 0x9E3779B97F4A7C15
		var z: UInt64 = fxS
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		z = z ^ (z >> 31)
		return Double(z >> 11) / 9007199254740992.0
	}

	mutating func fxPick(_ r: ClosedRange<Double>) -> Double {
		let u: Double = fx()
		return r.lowerBound + (r.upperBound - r.lowerBound) * u
	}
}

/// The weather at one place, after the storm cells, the land and the height have had their say
struct LocalWeather {
	var cloud: Double = 0
	/// how hard it is falling here (0...1)
	var precip: Double = 0
	var snow: Bool = false
	/// signed air speed (blocks per second), gusts included
	var wind: Double = 0
	var thunder: Double = 0
	var hail: Double = 0
	/// 0 warm ... 1 bitter (snow falls from 0.5)
	var chill: Double = 0
	var hot: Bool = false
	/// how much the air is thick with rain or snow (0 clear ... 1 a whiteout)
	var fog: Double = 0
	var wet: Double = 0
	var snowCover: Double = 0
	/// 0...1: how hard a tornado or hurricane is felt here
	var tornado: Double = 0
	var hurricane: Double = 0
}

/// Where the weather is judged when picking what comes next
struct WeatherContext {
	var cold: Bool = false
	var dry: Bool = false
	var tornadoCountry: Bool = false
	/// the sea is that way (-1 west, 1 east) and near enough for a hurricane; 0 when too far inland
	var seaSide: Double = 0
	var coastX: Double = 0
}

/// Walks forward through the present spell and the plan, keeping track of when severe weather may
/// next begin (the planner and the simulation use the same rules, so the forecast holds)
struct PlanCursor {
	var T: Double
	var calm: Double
	var tor: Double
	var hur: Double
	var last: WeatherKind

	mutating func note(_ k: WeatherKind, _ end: Double, _ gaps: (Double, Double, Double)) {
		if k.severe { calm = max(calm, end + gaps.0) }
		if k == .tornado { tor = max(tor, end + gaps.1) }
		if k == .hurricane { hur = max(hur, end + gaps.2) }
		last = k
		T = end
	}
}

/// A bolt of lightning on screen: the main channel, a few forks, and how long it shows
struct LightningBolt {
	var pts: [(Double, Double)]
	var forks: [[(Double, Double)]]
	var life: Double
	var maxLife: Double
}

/// A strike about to land near the player: shown and heard first, so it can be dodged
struct StrikeMark {
	var x: Double
	var y: Double
	var t: Double
	var total: Double
}

struct PendingThunder {
	var t: Double
	var vol: Double
	var near: Bool
}

/// One hailstone of the small pool the hail is drawn from (it bounces once, then breaks)
struct HailStone {
	var x: Double = 0
	var y: Double = 0
	var vx: Double = 0
	var vy: Double = 0
	var bounces: Int = 0
	var size: Double = 0.12
	var on: Bool = false
}

struct ForecastLine {
	var kind: WeatherKind
	var startsIn: Double
	var dur: Double
}

// MARK: - Weather simulation: states, the plan, smoothing and the weather at a place

/// how wet a biome's weather is (deserts mostly stay dry under passing storms)
func biomeWetness(_ b: Biome) -> Double {
	switch b {
	case .desert: return 0.1
	case .savanna: return 0.5
	case .jungle: return 1.15
	case .swamp: return 1.1
	default: return 1.0
	}
}

/// width of the strips of land that remember wet ground and lying snow
let groundCellW: Double = 48.0

extension Game {
	/// Calm kept between severe spells, and the longer gaps between tornadoes and between hurricanes,
	/// by the frequency setting
	func weatherGaps() -> (Double, Double, Double) {
		switch settings.severeFrequency {
		case 0: return (900, 3600, 5400)
		case 2: return (150, 600, 900)
		default: return (420, 1800, 2700)
		}
	}

	/// How much more (or less) often severe weather is picked when it may come
	func severeWeight() -> Double {
		switch settings.severeFrequency {
		case 0: return 0.4
		case 2: return 2.2
		default: return 1.0
		}
	}

	var weatherIntensity: Double { return clampD(settings.weatherIntensity, 0.25, 1.5) }

	func weatherAllowed(_ k: WeatherKind) -> Bool {
		let s: Settings = settings
		switch k {
		case .lightRain, .heavyRain, .snowfall: return s.allowRain
		case .thunderstorm: return s.allowThunder
		case .strongWind, .windstorm: return s.allowWind
		case .hailstorm: return s.allowHail
		case .blizzard: return s.allowBlizzard
		case .tornado: return s.allowTornado
		case .hurricane: return s.allowHurricane
		default: return true
		}
	}

	/// The settings the forecast depends on; when they change the plan is made again
	func planSignature() -> Int {
		let s: Settings = settings
		var k: Int = s.severeFrequency
		let flags: [Bool] = [s.allowRain, s.allowThunder, s.allowWind, s.allowTornado, s.allowHurricane, s.allowBlizzard, s.allowHail]
		for f in flags { k = k * 2 + (f ? 1 : 0) }
		return k
	}

	/// What a state brings once the switched-off kinds of weather are taken out and the intensity is
	/// applied. Blizzards and hurricanes bring their own snow, rain and wind (their switches decide).
	func allowedProfile(_ k: WeatherKind) -> WeatherProfile {
		let s: Settings = settings
		if !s.weatherOn { return WeatherProfile() }
		var kk: WeatherKind = k
		if kk == .blizzard && !s.allowBlizzard { kk = .snowfall }
		if kk == .hurricane && !s.allowHurricane { kk = .windstorm }
		if kk == .tornado && !s.allowTornado { kk = .thunderstorm }
		var p: WeatherProfile = kk.profile
		let own: Bool = kk == .blizzard || kk == .hurricane
		if !s.allowRain && !own { p.precip = 0 }
		if !s.allowWind && !own {
			p.wind = 0
			p.gust = 0
		}
		if !s.allowThunder { p.thunder = 0 }
		if !s.allowHail { p.hail = 0 }
		let I: Double = weatherIntensity
		let mw: ModWeather? = ModRuntime.shared.weather
		p.precip = min(1.0, p.precip * I * (mw?.rain ?? 1))
		p.wind *= I * (mw?.wind ?? 1)
		p.thunder *= I
		p.hail = min(1.0, p.hail * I)
		return p
	}

	/// Where the weather is judged: the player in the overworld, or where they left it
	var weatherX: Double { return world.dim == .overworld ? pb.x : wxHomeX }

	func weatherContext() -> WeatherContext {
		var c = WeatherContext()
		let x: Int = Int(floor(weatherX))
		let col: Col = gen.col(x)
		let b: Biome = col.biome
		c.cold = b == .tundra || (b == .mountain && col.h < 84)
		c.dry = b == .desert
		c.tornadoCountry = b == .plains || b == .savanna || b == .forest || b == .swamp || b == .desert
		if let sea = seaNear(x) {
			c.seaSide = sea.0
			c.coastX = sea.1
		}
		return c
	}

	/// The nearest open sea within 280 blocks: which side it is on, and where its shore is
	func seaNear(_ x: Int) -> (Double, Double)? {
		let key: Int = floorDiv(x, 32)
		if let c = coastCache[key] { return c.0 == 0 ? nil : c }
		var found: (Double, Double) = (0, 0)
		var d: Int = 0
		while d <= 280 {
			if gen.col(x + d).biome == .ocean { found = (1, Double(x + d)); break }
			if gen.col(x - d).biome == .ocean { found = (-1, Double(x - d)); break }
			d += 8
		}
		if coastCache.count > 256 { coastCache.removeAll() }
		coastCache[key] = found
		return found.0 == 0 ? nil : found
	}

	// MARK: the plan (the forecast is read straight from it)

	/// Where the present spell and the plan end, and when severe weather may next begin after them
	func planCursor() -> PlanCursor {
		let gaps: (Double, Double, Double) = weatherGaps()
		var cur = PlanCursor(T: weather.t, calm: weather.calmUntil, tor: weather.tornadoUntil, hur: weather.hurricaneUntil, last: weather.kind)
		cur.note(weather.kind, weather.t + max(0, weather.stateDur - weather.stateT), gaps)
		for s in weather.plan { cur.note(s.kind, cur.T + s.dur, gaps) }
		return cur
	}

	func fillPlan() {
		if weather.plan.count >= 4 { return }
		let ctx: WeatherContext = weatherContext()
		let gaps: (Double, Double, Double) = weatherGaps()
		var cur: PlanCursor = planCursor()
		while weather.plan.count < 4 {
			let step: WeatherStep = planStep(cur, ctx)
			weather.plan.append(step)
			cur.note(step.kind, cur.T + step.dur, gaps)
		}
	}

	/// Picks the spell that follows `cur.last`, beginning at `cur.T`. Weather moves to its neighbours
	/// (clear to cloud to rain to storm and back), so it changes gradually; severe spells may only
	/// begin once the calm after the last one is over, and a thunderstorm may grow hail or spin up a
	/// tornado as part of the same storm.
	func planStep(_ cur: PlanCursor, _ ctx: WeatherContext) -> WeatherStep {
		let s: Settings = settings
		let fw: Double = severeWeight()
		let sev: Double = cur.T >= cur.calm ? fw : 0
		var opts: [(WeatherKind, Double)] = []
		let modWx: ModWeather? = ModRuntime.shared.weather
		func add(_ k: WeatherKind, _ w: Double) {
			let m: Double = modWx?.chanceOf(k) ?? 1
			if w > 0 && m > 0 && weatherAllowed(k) { opts.append((k, w * m)) }
		}
		let rain: WeatherKind = ctx.cold ? .snowfall : .lightRain
		let heavy: WeatherKind = ctx.cold ? .snowfall : .heavyRain
		let hurricaneOK: Bool = ctx.seaSide != 0 && !ctx.cold && cur.T >= cur.hur
		// with rain switched off the wet spells drop out; storms can still come, dry
		let dryFill: Double = s.allowRain ? 0 : 3.0
		switch cur.last {
		case .clear:
			add(.clear, 2.2)
			add(.partlyCloudy, 4.0)
			add(.strongWind, ctx.dry ? 1.2 : 0.5)
		case .partlyCloudy:
			add(.clear, 3.0)
			add(.partlyCloudy, 1.2)
			add(.overcast, 3.0)
			add(.strongWind, 0.6)
		case .overcast:
			add(.partlyCloudy, 2.5)
			add(.overcast, 0.6)
			add(rain, ctx.dry ? 0.7 : 3.0)
			add(heavy, ctx.dry ? 0.2 : 0.7)
			add(.windstorm, 0.35 * sev)
			if !ctx.cold { add(.hailstorm, 0.25 * sev) }
			if !s.allowRain && !ctx.cold { add(.thunderstorm, 0.6 * sev) }
			if hurricaneOK { add(.hurricane, 0.22 * sev) }
		case .lightRain:
			add(.overcast, 2.0)
			add(.lightRain, 1.0)
			add(.heavyRain, 2.4)
		case .heavyRain:
			add(.lightRain, 2.6)
			add(.heavyRain, 0.6)
			if !ctx.cold { add(.thunderstorm, 1.6 * sev) }
		case .thunderstorm:
			add(.heavyRain, 3.0)
			add(.overcast, dryFill)
			add(.hailstorm, 0.5 * fw)
			if ctx.tornadoCountry && cur.T >= cur.tor { add(.tornado, 0.45 * fw) }
		case .strongWind:
			add(.partlyCloudy, 2.4)
			add(.clear, 1.0)
			add(.strongWind, 0.6)
			add(.windstorm, 0.8 * sev)
			if hurricaneOK { add(.hurricane, 0.12 * sev) }
		case .windstorm:
			add(.strongWind, 2.5)
			add(.overcast, 1.5)
		case .hailstorm:
			add(.heavyRain, 2.5)
			add(.lightRain, 1.0)
			add(.overcast, dryFill)
		case .snowfall:
			add(.overcast, 2.4)
			add(.snowfall, 1.0)
			if ctx.cold { add(.blizzard, 0.9 * sev) }
		case .blizzard:
			add(.snowfall, 3.0)
			add(.overcast, dryFill)
		case .tornado, .hurricane:
			add(.heavyRain, 2.0)
			add(.lightRain, 1.0)
			add(.overcast, s.allowRain ? 0.3 : 3.0)
		}
		if opts.isEmpty, let mw = modWx {
			// a mod that rules out every usual next spell: any kind it allows comes straight in
			for k in WeatherKind.allCases where mw.chanceOf(k) > 0 && weatherAllowed(k) && (!k.severe || sev > 0) { opts.append((k, mw.chanceOf(k))) }
		}
		if opts.isEmpty { opts.append((.partlyCloudy, 1.0)) }
		var total: Double = 0
		for o in opts { total += o.1 }
		var r: Double = weather.rand() * total
		var k: WeatherKind = opts[opts.count - 1].0
		for o in opts {
			if r < o.1 {
				k = o.0
				break
			}
			r -= o.1
		}
		let dur: Double = weather.pick(k.spell) * (modWx?.length ?? 1)
		return WeatherStep(kind: k, dur: dur)
	}

	/// The present spell is over: the next one in the plan begins (and the plan is topped up)
	func advanceWeather() {
		let prev: WeatherKind = weather.kind
		let gaps: (Double, Double, Double) = weatherGaps()
		if prev.severe { weather.calmUntil = max(weather.calmUntil, weather.t + gaps.0) }
		if prev == .tornado { weather.tornadoUntil = max(weather.tornadoUntil, weather.t + gaps.1) }
		if prev == .hurricane { weather.hurricaneUntil = max(weather.hurricaneUntil, weather.t + gaps.2) }
		// a severe spell the player was out in goes in the journal (tornadoes and hurricanes keep their own)
		if prev.severe && prev != .tornado && prev != .hurricane && stormFelt && world.dim == .overworld {
			recordStorm(prev, weatherLabel(prev, snow: wxHere.snow).lowercased() == prev.name.lowercased() ? "weathered it" : weatherLabel(prev, snow: wxHere.snow).lowercased())
		}
		stormFelt = false
		if weather.plan.isEmpty { fillPlan() }
		var step: WeatherStep = weather.plan.removeFirst()
		let ctx: WeatherContext = weatherContext()
		// the land may have changed under the forecast (the player travelled): no hurricane far from
		// the sea, no tornado in the mountains or the snow
		if step.kind == .hurricane && ctx.seaSide == 0 { step.kind = settings.allowWind ? .windstorm : .overcast }
		if step.kind == .tornado && !ctx.tornadoCountry { step.kind = settings.allowThunder ? .thunderstorm : .heavyRain }
		weather.kind = step.kind
		weather.stateT = 0
		weather.stateDur = step.dur
		// calm spells can bring the wind round
		if (step.kind == .clear || step.kind == .partlyCloudy) && weather.rand() < 0.35 { weather.windDir = -weather.windDir }
		switch step.kind {
		case .tornado: spawnTornado()
		case .hurricane: spawnHurricane(ctx)
		case .hailstorm:
			weather.bigHail = weather.rand() < 0.15
			hailBroken = 0
		default: break
		}
		fillPlan()
		announceWeather(prev, step.kind)
	}

	/// Weather switched off: everything it was doing stops at once and leaves nothing behind (storm
	/// surge water is taken away as its ground loads; see updateSurge)
	func weatherShutdown() {
		weather.wasOn = false
		weather.tornado = nil
		weather.hurricane = nil
		weather.kind = .clear
		weather.stateT = 0
		weather.stateDur = 120
		weather.plan.removeAll()
		weather.cloud = 0
		weather.precip = 0
		weather.wind = 0
		weather.gust = 0
		weather.thunder = 0
		weather.hail = 0
		weather.chill = 0
		weather.cover = 0
		weather.cells.removeAll()
		clearWeatherFX()
		// fires lightning started go out with it
		fireZones.removeAll { $0.env }
	}

	/// The short-lived things weather puts in the world: bolts, thunder still on its way, a strike
	/// about to land, hailstones, alerts and the forces on the player
	func clearWeatherFX() {
		bolts.removeAll()
		thunderQueue.removeAll()
		strikeMark = nil
		strikeAcc = 0
		skyFlash = 0
		for i in 0..<hailPool.count { hailPool[i].on = false }
		hailAcc = 0
		wxBanner = ""
		wxBannerLevel = 0
		wxWalk = 0
		wxAirDrift = 0
		wxRest = 0
		wxAccelX = 0
		wxAccelY = 0
		wxSlip = 0
		wxSlow = 1
		weatherRain = 0
		weatherSnow = false
		wxHere = LocalWeather()
		tornadoAcc = 0
		hurricaneAcc = 0
	}

	/// Weather switched back on: it starts fair, with a calm before anything severe
	func weatherRestart() {
		weather.wasOn = true
		weather.kind = .clear
		weather.stateT = 0
		weather.stateDur = weather.pick(60...120)
		weather.calmUntil = max(weather.calmUntil, weather.t + 300)
		weather.plan.removeAll()
		weather.planSig = planSignature()
		fillPlan()
	}

	func easeTo(_ v: Double, _ to: Double, _ tau: Double, _ dt: Double) -> Double {
		let k: Double = 1.0 - exp(-dt / max(0.05, tau))
		return v + (to - v) * k
	}

	/// One step of the simulation (the regional state; what that means at a place is weatherAt)
	func stepWeatherSim(_ dt: Double) {
		if world.dim == .overworld { wxHomeX = pb.x }
		if !settings.weatherOn {
			if weather.wasOn { weatherShutdown() }
			// the scenery clouds still drift by as they always have
			weather.cloudDrift += CloudField.wind * dt
			return
		}
		if !weather.wasOn { weatherRestart() }
		weather.t += dt
		let sig: Int = planSignature()
		if sig != weather.planSig {
			weather.planSig = sig
			weather.plan.removeAll()
			// an event whose switch went off ends at once
			if weather.tornado != nil && !settings.allowTornado { endTornado(survived: false) }
			if weather.hurricane != nil && !settings.allowHurricane { endHurricane(survived: false) }
			fillPlan()
		}
		weather.stateT += dt
		let held: Bool = weather.tornado != nil || weather.hurricane != nil
		if weather.stateT >= weather.stateDur && !held { advanceWeather() }
		if weather.plan.count < 4 { fillPlan() }
		// ease toward what the state brings; anything switched off fades out within a second
		var p: WeatherProfile = allowedProfile(weather.kind)
		let raw: WeatherProfile = weather.kind.profile
		if let h = weather.hurricane {
			p.wind *= h.force
			p.precip *= clampD(h.force * 1.2, 0.2, 1.0)
			p.cloud = 0.55 + 0.45 * min(1.0, h.force * 1.6)
			p.thunder *= h.force
		}
		func tau(_ target: Double, _ rv: Double, _ normal: Double) -> Double {
			return (target <= 0.0001 && rv > 0.0001) ? 0.8 : normal
		}
		weather.cloud = easeTo(weather.cloud, p.cloud, 20, dt)
		weather.precip = easeTo(weather.precip, p.precip, tau(p.precip, raw.precip, 14), dt)
		weather.thunder = easeTo(weather.thunder, p.thunder, tau(p.thunder, raw.thunder, 8), dt)
		weather.hail = easeTo(weather.hail, p.hail, tau(p.hail, raw.hail, 6), dt)
		weather.chill = easeTo(weather.chill, p.chill, 25, dt)
		weather.cover = easeTo(weather.cover, p.cover, 18, dt)
		weather.gust = easeTo(weather.gust, p.gust, 10, dt)
		// the wind eases through calm when it turns round, never flipping in a frame
		if let h = weather.hurricane {
			// onshore until the eye has passed, offshore after it
			weather.windDir = h.stage.rawValue <= HurricaneStage.eye.rawValue ? -h.side : h.side
		}
		let wt: Double = p.wind * weather.windDir
		weather.wind = easeTo(weather.wind, wt, tau(abs(wt), raw.wind, 9), dt)
		weather.drift += weather.wind * 0.55 * dt
		weather.cloudDrift += (weather.wind * 0.16 + (abs(weather.wind) < 0.05 ? CloudField.wind : 0)) * dt
	}

	// MARK: the weather at a place

	/// How much of the land at x a storm cell covers just now (0 a dry gap ... 1 under the storm).
	/// The cells are a noise field in world space that drifts with the wind.
	func coverAt(_ x: Double) -> Double {
		let c: Double = weather.cover
		if c >= 0.99 { return 1 }
		if c <= 0.001 { return 0 }
		let n: Double = fbm1((x - weather.drift) / 170.0, gen.seed &+ 0x57A2, 2)
		let thr: Double = 1.0 - c - 0.11
		return smooth(clampD((n - thr) / 0.22, 0, 1))
	}

	/// The wind's gusting right now (the same everywhere; it rises and falls over a few seconds)
	func gustNow() -> Double {
		let g: Double = weather.gust
		if g <= 0.001 { return 1 }
		let n: Double = fbm1(weather.t * 0.23, gen.seed &+ 0x6057, 3)
		return clampD(1.0 + (n - 0.5) * 2.0 * g, 0.35, 1.6)
	}

	/// How cold it is: the land, the height, the night and the weather (snow falls from 0.5)
	func chillAt(_ y: Double, _ col: Col) -> Double {
		var c: Double
		switch col.biome {
		case .tundra: c = 0.75
		case .mountain: c = col.h < 84 ? 0.62 : 0.3
		case .desert, .savanna, .jungle: c = 0.0
		case .ocean: c = 0.2
		default: c = 0.18
		}
		if y < 76 { c += (76.0 - y) / 50.0 }
		let hot: Bool = col.biome == .desert || col.biome == .savanna || col.biome == .jungle
		if isNight && !hot { c += 0.12 }
		c += weather.chill * 0.4 + weather.precip * 0.05
		return clampD(c, 0, 1.2)
	}

	/// The weather at a place. Only reads the simulation and the world's (deterministic) biomes, so a
	/// place has the same weather whichever chunks are loaded.
	func weatherAt(_ x: Double, _ y: Double) -> LocalWeather {
		var L = LocalWeather()
		if let d = customDim, settings.weatherOn { return customWeather(d, x, y) }
		if world.dim != .overworld || !settings.weatherOn { return L }
		let ix: Int = Int(floor(x))
		let col: Col = gen.col(ix)
		let cov: Double = coverAt(x)
		// blended from one column to the next, so rain changes gradually over a biome border
		let wa: Double = landWetness(ix)
		let wetF: Double = wa + (landWetness(ix + 1) - wa) * (x - Double(ix))
		L.chill = chillAt(y, col)
		L.snow = L.chill >= 0.5
		L.hot = col.biome == .desert || col.biome == .savanna || col.biome == .jungle
		L.precip = clampD(weather.precip * cov * wetF, 0, 1)
		L.cloud = weather.cloud * (0.6 + 0.4 * cov)
		L.thunder = weather.thunder * cov
		// up in the cold, hail falls as snow
		L.hail = L.snow ? 0 : weather.hail * cov
		L.wind = weather.wind * gustNow()
		if let e = weather.tornado {
			let d: Double = abs(x - e.x)
			L.tornado = e.funnel * clampD(1.0 - (d - 4.0) / 40.0, 0, 1)
			L.cloud = max(L.cloud, min(1.0, 0.25 + e.funnel * clampD(1.0 - d / 120.0, 0, 1)))
		}
		if let h = weather.hurricane {
			let f: Double = hurricaneReach(x, h)
			L.hurricane = h.force * f
			L.wind *= 0.3 + 0.7 * f
			L.precip *= 0.5 + 0.5 * f
		}
		let blow: Double = clampD(abs(L.wind) / 14.0, 0, 1)
		L.fog = L.snow ? L.precip * (0.25 + 0.6 * blow) : L.precip * 0.3
		L.wet = groundValue(x, false)
		L.snowCover = groundValue(x, true)
		return L
	}

	/// How readily rain falls at column x: its biome's wetness, with the land 14 columns either side
	func landWetness(_ x: Int) -> Double {
		let w0: Double = biomeWetness(gen.col(x - 14).biome)
		let w1: Double = biomeWetness(gen.col(x).biome)
		let w2: Double = biomeWetness(gen.col(x + 14).biome)
		return (w0 + w1 * 2.0 + w2) * 0.25
	}

	/// How hard a hurricane is felt at x: fully over the sea and at the coast, fading inland
	func hurricaneReach(_ x: Double, _ h: HurricaneEvent) -> Double {
		let inland: Double = (h.coastX - x) * h.side
		return clampD(1.0 - (inland - 40.0) / 300.0, 0.25, 1.0)
	}

	/// Wet ground or lying snow at x (interpolated between the strips' centres)
	func groundValue(_ x: Double, _ snow: Bool) -> Double {
		let f: Double = x / groundCellW - 0.5
		let c0: Int = Int(floor(f))
		let u: Double = f - Double(c0)
		let a: GroundCell? = weather.cells[c0]
		let b: GroundCell? = weather.cells[c0 + 1]
		let va: Double = snow ? (a?.snow ?? 0) : (a?.wet ?? 0)
		let vb: Double = snow ? (b?.snow ?? 0) : (b?.wet ?? 0)
		return va + (vb - va) * u
	}

	/// Rain soaks the ground and snow lies on it, strip by strip around the player; strips the player
	/// has been away from catch up as if the weather had been fair meanwhile (cheap, and close enough)
	func updateGroundCells(_ dt: Double) {
		wxCellT += dt
		if wxCellT < 0.5 { return }
		let step: Double = wxCellT
		wxCellT = 0
		// the strips are the Overworld's ground: another dimension's weather never lies on them
		if !settings.weatherOn || world.dim != .overworld { return }
		let c0: Int = Int(floor(weatherX / groundCellW))
		for c in (c0 - 4)...(c0 + 4) {
			let cx: Double = (Double(c) + 0.5) * groundCellW
			var cell: GroundCell = weather.cells[c] ?? GroundCell(wet: 0, snow: 0, t: weather.t)
			let away: Double = max(0, weather.t - cell.t - step)
			let surf: Double = Double(gen.col(Int(cx)).h)
			let L: LocalWeather = weatherAt(cx, surf)
			if away > 0 {
				cell.wet *= exp(-away / 150.0)
				if L.chill < 0.5 { cell.snow *= exp(-away / 300.0) }
			}
			if L.precip > 0.03 && !L.snow {
				cell.wet = min(1.0, cell.wet + L.precip * step / 35.0)
			} else {
				let dryT: Double = L.hot ? 60 : (weather.cloud > 0.6 ? 220 : 110)
				cell.wet = max(0, cell.wet - step / dryT)
			}
			if L.snow && L.precip > 0.03 {
				cell.snow = min(1.0, cell.snow + L.precip * step / 50.0)
			} else if L.chill < 0.45 {
				let melt: Double = L.precip > 0.05 ? 50 : 140
				cell.snow = max(0, cell.snow - step / melt)
			}
			cell.t = weather.t
			weather.cells[c] = cell
		}
		if weather.cells.count > 40 {
			weather.cells = weather.cells.filter { abs($0.key - c0) <= 12 || $0.value.wet > 0.02 || $0.value.snow > 0.02 }
		}
	}

	// MARK: words for it: names, the forecast, pressure, alerts

	/// The name of a spell as it will actually be felt: with some kinds of weather switched off, a
	/// thunderstorm may be dry or a blizzard plain snow; up in the cold, rain is snow
	func weatherLabel(_ k: WeatherKind, snow: Bool) -> String {
		let s: Settings = settings
		if !s.weatherOn { return "No weather" }
		let p: WeatherProfile = allowedProfile(k)
		switch k {
		case .lightRain: return p.precip <= 0 ? "Overcast" : (snow ? "Light snow" : "Light rain")
		case .heavyRain: return p.precip <= 0 ? "Overcast" : (snow ? "Heavy snow" : "Heavy rain")
		case .snowfall: return p.precip <= 0 ? "Overcast" : (snow ? "Snowfall" : "Cold rain")
		case .thunderstorm:
			if p.thunder <= 0 { return p.precip > 0 ? (snow ? "Heavy snow" : "Heavy rain") : "Overcast" }
			return p.precip > 0 ? "Thunderstorm" : "Dry thunderstorm"
		case .hailstorm:
			if p.hail <= 0 { return p.thunder > 0 ? "Thunderstorm" : (p.precip > 0 ? "Heavy rain" : "Overcast") }
			return weather.bigHail && k == weather.kind ? "Large hail" : "Hailstorm"
		case .strongWind: return p.wind <= 0.01 ? "Partly cloudy" : "Strong wind"
		case .windstorm: return p.wind <= 0.01 ? "Overcast" : "Windstorm"
		case .blizzard: return s.allowBlizzard ? (snow ? "Blizzard" : "Gale and cold rain") : weatherLabel(.snowfall, snow: snow)
		case .tornado: return s.allowTornado ? "Tornado" : weatherLabel(.thunderstorm, snow: snow)
		case .hurricane: return s.allowHurricane ? "Hurricane" : weatherLabel(.windstorm, snow: snow)
		default: return k.name
		}
	}

	/// What the weather is doing where the player is, in a few words
	var weatherHereLabel: String {
		if world.dim != .overworld { return "" }
		if !settings.weatherOn { return "" }
		let L: LocalWeather = wxHere
		var name: String = weatherLabel(weather.kind, snow: L.snow)
		// a storm cell that has not reached here yet (or has passed) shows as such
		let p: WeatherProfile = allowedProfile(weather.kind)
		if p.precip > 0.2 && L.precip < 0.05 && weather.kind != .tornado && weather.kind != .hurricane { name = joinText(name, " nearby") }
		return name
	}

	/// The present spell, then the plan: what comes, when, and for how long
	func forecast() -> [ForecastLine] {
		var out: [ForecastLine] = []
		var t: Double = max(0, weather.stateDur - weather.stateT)
		if let h = weather.hurricane { t = max(t, h.timeLeft()) }
		out.append(ForecastLine(kind: weather.kind, startsIn: 0, dur: t))
		for s in weather.plan {
			out.append(ForecastLine(kind: s.kind, startsIn: t, dur: s.dur))
			t += s.dur
		}
		return out
	}

	/// Air pressure (hPa) from the simulation: low under storms, lowest near a hurricane's eye
	func pressureNow() -> Double {
		var p: Double = 1018.0 - 12.0 * weather.cloud - 9.0 * weather.precip - 0.8 * abs(weather.wind)
		if let h = weather.hurricane {
			let core: Double = h.stage == .eye ? 1.15 : h.force
			p -= 42.0 * core * h.strength * hurricaneReach(weatherX, h)
		}
		if let e = weather.tornado { p -= 8.0 * e.funnel }
		return p
	}

	/// The pressure the next spell will settle at (for the barometer's trend)
	func pressureNext() -> Double {
		let k: WeatherKind = weather.plan.first?.kind ?? weather.kind
		let p: WeatherProfile = allowedProfile(k)
		var v: Double = 1018.0 - 12.0 * p.cloud - 9.0 * p.precip - 0.8 * p.wind
		if k == .hurricane && settings.allowHurricane { v -= 40 }
		if k == .tornado && settings.allowTornado { v -= 8 }
		return v
	}

	/// A line in the message box when the weather turns (only for changes worth knowing about)
	func announceWeather(_ prev: WeatherKind, _ k: WeatherKind) {
		if !settings.weatherAlerts || world.dim != .overworld { return }
		let p: WeatherProfile = allowedProfile(k)
		let snow: Bool = wxHere.snow
		var line: String = ""
		switch k {
		case .lightRain:
			if prev != .heavyRain && p.precip > 0 { line = snow ? "Snow is beginning to fall." : "It's starting to rain." }
		case .heavyRain:
			if prev == .lightRain && p.precip > 0 { line = snow ? "The snow is getting heavier." : "The rain is getting heavier." }
		case .thunderstorm:
			if p.thunder > 0 { line = "A thunderstorm is rolling in. Lightning finds high, open ground." }
		case .strongWind:
			if (prev == .clear || prev == .partlyCloudy) && p.wind > 0 { line = "The wind is picking up." }
		case .windstorm:
			if p.wind > 0 { line = "Windstorm! Strong gusts will push you around." }
		case .hailstorm:
			if p.hail > 0 { line = weather.bigHail ? "Large hail! Get under a roof." : "Hail is falling." }
		case .snowfall:
			if p.precip > 0 && prev != .blizzard { line = snow ? "Snow is falling." : "A cold rain is falling." }
		case .blizzard:
			if settings.allowBlizzard { line = "A blizzard is blowing in. Find shelter and warmth." }
		case .clear, .partlyCloudy:
			if prev.severe || prev == .heavyRain { line = "The weather is clearing." }
		default:
			break
		}
		if !line.isEmpty {
			say(line, 3.5)
			if k.severe { sfx(.weatherAlert, 0.6) }
		}
	}

	/// The warning strip under the top bar while something dangerous is going on
	func updateWeatherBanner() {
		var text: String = ""
		var level: Int = 0
		let on: Bool = settings.weatherOn && world.dim == .overworld
		if on, let e = weather.tornado {
			let d: Double = e.x - pb.x
			let side: String = d > 0 ? "east" : "west"
			let dist: String = String(Int(abs(d).rounded()))
			switch e.phase {
			case 0:
				let left: Int = Int(max(0, e.warnDur - e.t).rounded())
				text = joinText("TORNADO WARNING · forming ", dist, " blocks ", side, " · take shelter (", String(left), " s)")
				level = 2
			case 1:
				text = joinText("TORNADO ON THE GROUND · ", dist, " blocks ", side, " · moving ", e.dir > 0 ? "east" : "west")
				level = 2
			default:
				text = "The tornado is lifting"
				level = 1
			}
		} else if on, let h = weather.hurricane {
			text = joinText("HURRICANE · ", h.stage.name)
			level = (h.stage == .approaching || h.stage == .clearing || h.stage == .eye) ? 1 : 2
		} else if on && strikeMark != nil {
			text = "LIGHTNING IS ABOUT TO STRIKE NEAR YOU · move or take cover"
			level = 2
		} else if on && weather.kind == .blizzard && settings.allowBlizzard && wxHere.snow {
			text = "BLIZZARD · stay sheltered and keep warm"
			level = 1
		} else if on && weather.kind == .hailstorm && weather.bigHail && wxHere.hail > 0.1 {
			text = "LARGE HAIL · get under a roof"
			level = 1
		} else if on && weather.kind == .thunderstorm && wxHere.thunder > 0.5 {
			text = "Thunderstorm · keep off high, open ground"
			level = 1
		} else if bodyCold > 0.45 && on {
			text = "Freezing · find a fire, shelter or warm clothes"
			level = 1
		}
		if !settings.weatherAlerts {
			text = ""
			level = 0
		}
		wxBanner = text
		wxBannerLevel = level
	}
}

// MARK: - Weather in the world: lightning, hail, cold, the wind's push, tornadoes and hurricanes

/// How readily wind tears a block loose (0: never). The ground itself, stone and anything built to
/// stand up to storms never goes; plants, leaves and light building blocks go first.
func windBreak(_ t: Tile) -> Double {
	if isLeafTile(t) { return 0.85 }
	if isLogTile(t) { return 0.18 }
	switch t {
	case .tallGrass, .flowerR, .flowerY, .deadBush, .reed, .mushroom: return 0.9
	case .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3: return 0.55
	case .torch, .cobweb: return 0.8
	case .hay: return 0.6
	case .glass: return 0.5
	case .cactus: return 0.3
	case .platform, .ladder: return 0.45
	case .planks: return 0.3
	case .doorClosed, .doorOpen: return 0.25
	case .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock: return 0.15
	case .workbench, .lantern, .crate: return 0.2
	case .crackedBrick: return 0.08
	case .brick, .mossBrick, .amethystBlock: return 0.02
	default: return 0
	}
}

/// Things lightning can set alight
func isFlammable(_ t: Tile) -> Bool {
	if isLeafTile(t) || isLogTile(t) { return true }
	switch t {
	case .tallGrass, .flowerR, .flowerY, .deadBush, .reed, .hay, .planks, .platform, .ladder, .dryGrass, .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock, .workbench, .crate, .cactus:
		return true
	default:
		return false
	}
}

/// How much a shot of each kind is carried by the wind (heavy and fast shots hardly at all)
func windCatch(_ k: ProjKind) -> Double {
	switch k {
	case .arrow: return 0.22
	case .quarrel, .bolt: return 0.15
	case .pebble, .spit: return 0.25
	case .bomb, .flask: return 0.3
	case .fireball: return 0.12
	case .rock, .shard: return 0.08
	case .pellet, .shell: return 0.05
	case .bullet, .shock: return 0
	}
}

/// Light creatures the wind carries along
func isWindBlown(_ k: MobKind) -> Bool {
	switch k {
	case .crow, .bat, .chicken: return true
	default: return false
	}
}

extension Game {
	/// How much of the open weather reaches someone at a given level of shelter
	func shelterExposure(_ level: Int) -> Double {
		switch level {
		case 0: return 1.0
		case 1: return 0.55
		default: return 0
		}
	}

	/// True when rain falls on the head of a body standing at (x, feet y) with the given height
	func rainReaches(_ x: Double, _ feetY: Double, _ h: Double) -> Bool {
		if world.dim != .overworld { return false }
		let tx: Int = Int(floor(x))
		return Int(floor(feetY - h)) < world.rainTop(tx)
	}

	/// 0 out in the open, 1 under a roof, 2 indoors (a roof and walls on both sides), 3 underground or
	/// in a reinforced storm shelter
	func shelterAt(_ x: Double, _ feetY: Double) -> Int {
		if world.dim != .overworld { return 3 }
		let tx: Int = Int(floor(x))
		let head: Int = Int(floor(feetY - 1.6))
		if head < world.rainTop(tx) { return 0 }
		var reinforced: Bool = false
		// count the solid cover overhead (four blocks or more is underground)
		var solidAbove: Int = 0
		var y: Int = head - 1
		var n: Int = 0
		while n < 24 && y > 0 {
			let t: Tile = world.tile(tx, y)
			if t.solid {
				solidAbove += 1
				if isStormproof(t) { reinforced = true }
			}
			y -= 1
			n += 1
		}
		if solidAbove >= 4 && !reinforced { return 3 }
		// walls on both sides, at head or body height
		func wall(_ dir: Int) -> Bool {
			var k: Int = 1
			while k <= 8 {
				let a: Tile = world.tile(tx + dir * k, head)
				let b: Tile = world.tile(tx + dir * k, head + 1)
				if a.solid || b.solid {
					if isStormproof(a) || isStormproof(b) { reinforced = true }
					return true
				}
				k += 1
			}
			return false
		}
		let left: Bool = wall(-1)
		let right: Bool = wall(1)
		if left && right { return reinforced ? 3 : 2 }
		return 1
	}

	// MARK: lightning

	func updateLightning(_ dt: Double) {
		if !bolts.isEmpty {
			for i in 0..<bolts.count { bolts[i].life -= dt }
			bolts.removeAll { $0.life <= 0 }
		}
		if skyFlash > 0 { skyFlash = max(0, skyFlash - dt * (settings.reduceFlashes ? 0.9 : 2.6)) }
		if playerStrikeCD > 0 { playerStrikeCD -= dt }
		if !thunderQueue.isEmpty {
			for i in 0..<thunderQueue.count { thunderQueue[i].t -= dt }
			for q in thunderQueue where q.t <= 0 { Sound.shared.play(q.near ? .thunderNear : .thunderFar, q.vol) }
			thunderQueue.removeAll { $0.t <= 0 }
		}
		let on: Bool = settings.weatherOn && settings.allowThunder && world.dim == .overworld
		if var m = strikeMark {
			if !on {
				strikeMark = nil
			} else {
				m.t -= dt
				if m.t <= 0 {
					strikeMark = nil
					lightningStrike(m.x, m.y, rod: false)
				} else {
					strikeMark = m
					if frameNo % 6 == 0 { spawnParticles(m.x + Double.random(in: -0.6...0.6), m.y - 0.3, 0xCFE4FF, 1, 2.0, 0.3, -4) }
				}
			}
		}
		if !on || weather.thunder < 0.01 {
			strikeAcc = 0
			return
		}
		strikeAcc += dt * weather.thunder / 60.0
		if strikeAcc >= 1.0 {
			strikeAcc = weather.fxPick(-0.4...0.2)
			pickStrike()
		}
	}

	/// Where the next bolt goes. Most land away from the player and some only light up the clouds;
	/// one landing near the player is marked first, and the next one near them waits a good while
	/// (lightning never singles a player out).
	func pickStrike() {
		let px: Double = pb.x
		var x: Double = px + weather.fxPick(-75...75)
		if coverAt(x) < 0.3 || weather.fx() < 0.3 {
			cloudFlash(x)
			return
		}
		if abs(x - px) < 12 && playerStrikeCD > 0 {
			x = px + (x >= px ? 1.0 : -1.0) * weather.fxPick(16...40)
		}
		guard let spot = strikeSpot(x) else {
			cloudFlash(x)
			return
		}
		if spot.2 {
			lightningStrike(spot.0, spot.1, rod: true)
			return
		}
		if abs(spot.0 - px) < 12 {
			// where it actually comes down decides: near the player again so soon, it stays in the cloud
			if playerStrikeCD > 0 {
				cloudFlash(spot.0)
				return
			}
			playerStrikeCD = 45
			strikeMark = StrikeMark(x: spot.0, y: spot.1, t: 1.5, total: 1.5)
			sfx(.strikeWarn, 0.8)
			return
		}
		lightningStrike(spot.0, spot.1, rod: false)
	}

	/// Lightning that stays in the cloud: a soft flicker and far-off thunder
	func cloudFlash(_ x: Double) {
		let d: Double = abs(x - pb.x)
		let k: Double = clampD(1.0 - d / 160.0, 0.2, 1.0)
		skyFlash = max(skyFlash, (settings.reduceFlashes ? 0.05 : 0.2) * k)
		thunderQueue.append(PendingThunder(t: 0.6 + d / 45.0, vol: 0.35 * k, near: false))
	}

	/// Where a bolt aimed at x comes down: a lightning rod in reach takes it, otherwise the highest
	/// exposed point close by (a tree top, a roof, a hill). Returns (x, top y, taken by a rod).
	func strikeSpot(_ x: Double) -> (Double, Double, Bool)? {
		if let r = rodCovering(x) { return (Double(r.x) + 0.5, Double(r.y), true) }
		var best: Int = Int.max
		let x0: Int = Int(floor(x))
		var bx: Int = x0
		for k in -3...3 {
			let cx: Int = x0 + k
			if !world.isLoaded(cx) { continue }
			let top: Int = world.rainTop(cx)
			if top < best {
				best = top
				bx = cx
			}
		}
		if best == Int.max || best >= world.H - 2 { return nil }
		// the highest point may lie within a rod's reach even if the aim did not
		if let r = rodCovering(Double(bx) + 0.5) { return (Double(r.x) + 0.5, Double(r.y), true) }
		return (Double(bx) + 0.5, Double(best), false)
	}

	func lightningStrike(_ x: Double, _ y: Double, rod: Bool) {
		let soft: Bool = settings.reduceFlashes
		makeBolt(x, y)
		stormEssenceAt(x, y, rod: rod)
		skyFlash = max(skyFlash, soft ? 0.12 : 0.55)
		addLightFlash(x, y - 0.5, peak: soft ? 11 : 15, dur: soft ? 0.7 : 0.35, radius: 1.4, color: 0xC8DCFF)
		// thunder: at once up close, later the further off it was (light is quick, sound is slow)
		let d: Double = abs(x - pb.x) + abs(y - pb.y) * 0.3
		let vol: Double = clampD(1.15 - d / 140.0, 0.12, 1.0)
		if d < 14 {
			Sound.shared.play(.thunderNear, vol)
		} else {
			thunderQueue.append(PendingThunder(t: d / 45.0, vol: vol, near: d < 40))
		}
		spawnParticles(x, y - 0.2, 0xE8F0FF, 8, 6.0, 0.35, 10)
		if d < 24 { addShake(0.35) }
		if rod {
			// the rod carries it safely into the ground
			spawnParticles(x, y + 0.2, 0xFFE8A0, 10, 4.0, 0.4, 14)
			return
		}
		let I: Double = weatherIntensity
		if settings.weatherHurtsPlayer && !dead && abs(pb.x - x) < 1.8 && pb.y > y - 0.5 && pb.top < y + 0.6 {
			var info = DamageInfo(amount: 7.0 * I, type: .shock, source: .environment)
			info.originX = x
			info.knock = 7
			info.key = newID()
			if hurtPlayer(info) && settings.weatherAlerts { say("Struck by lightning!", 1.5) }
		}
		if settings.weatherHurtsCreatures {
			for m in mobsNear(x - 3, x + 3) where m.hp > 0 && !m.removed {
				if abs(m.b.x - x) < 2.0 && m.b.y > y - 0.5 && m.b.top < y + 0.6 {
					var info = DamageInfo(amount: 12.0 * I, type: .shock, source: .environment)
					info.originX = x
					info.knock = 5
					info.key = newID()
					applyMobDamage(m, info)
				}
			}
		}
		if settings.weatherHurtsBlocks { lightningFire(Int(floor(x)), Int(floor(y))) }
	}

	/// A jagged bolt from the cloud base down to the strike, with a few forks
	func makeBolt(_ x: Double, _ y: Double) {
		let top: Double = min(y - 24.0, camY - viewTilesH * 0.5 - 3.0)
		var pts: [(Double, Double)] = []
		var cx: Double = x + weather.fxPick(-4...4)
		let n: Int = max(6, Int((y - top) / 1.6))
		for i in 0...n {
			let f: Double = Double(i) / Double(n)
			let cy: Double = top + (y - top) * f
			cx += weather.fxPick(-0.9...0.9)
			cx += (x - cx) * f * 0.35
			if i == n { cx = x }
			pts.append((cx, cy))
		}
		var forks: [[(Double, Double)]] = []
		let nf: Int = 1 + Int(weather.fx() * 3.0)
		for _ in 0..<nf {
			let k: Int = clampI(Int(weather.fxPick(0.15...0.6) * Double(n)), 1, n - 1)
			var fx: Double = pts[k].0
			var fy: Double = pts[k].1
			let side: Double = weather.fx() < 0.5 ? -1.0 : 1.0
			var f: [(Double, Double)] = [(fx, fy)]
			let len: Int = 3 + Int(weather.fx() * 4.0)
			for _ in 0..<len {
				fx += side * weather.fxPick(0.4...1.3)
				fy += weather.fxPick(0.8...1.6)
				f.append((fx, fy))
			}
			forks.append(f)
		}
		if bolts.count >= 4 { bolts.removeFirst() }
		bolts.append(LightningBolt(pts: pts, forks: forks, life: 0.32, maxLife: 0.32))
	}

	/// A strike on something that burns: leaves and plants go up, and a short fire burns where it hit
	/// (it dies sooner in the rain)
	func lightningFire(_ tx: Int, _ ty: Int) {
		let t: Tile = world.tile(tx, ty)
		if !isFlammable(t) { return }
		if isLeafTile(t) || t.isPlant || t == .hay { breakTile(tx, ty, false, dropChance: 0.3) }
		let rain: Double = weatherAt(Double(tx) + 0.5, Double(ty)).precip
		let ground: Int = world.groundBelow(tx, ty)
		if fireZones.count >= 6 { fireZones.removeFirst() }
		var z = FireZone(x: Double(tx) + 0.5, y: Double(ground), r: 1.6, t: max(1.5, 6.0 - 4.5 * rain), uid: newID())
		z.tick = 0.35
		z.env = true
		fireZones.append(z)
		spawnParticles(Double(tx) + 0.5, Double(ty), 0xFF8030, 10, 4.0, 0.6, -3)
	}

	// MARK: hail

	func updateHail(_ dt: Double) {
		let on: Bool = settings.weatherOn && settings.allowHail && world.dim == .overworld
		let h: Double = on ? wxHere.hail : 0
		if hailPool.isEmpty { hailPool = [HailStone](repeating: HailStone(), count: 56) }
		let density: Double = clampD(settings.weatherParticles, 0.2, 1.0)
		if h > 0.02 {
			hailAcc += dt * h * 70.0 * density
			let halfW: Double = viewTilesW * 0.5 + 3.0
			let topY: Double = camY - viewTilesH * 0.5 - 1.0
			while hailAcc >= 1.0 {
				hailAcc -= 1.0
				guard let i = hailPool.firstIndex(where: { !$0.on }) else {
					hailAcc = 0
					break
				}
				var s = HailStone()
				s.on = true
				s.x = camX + Double.random(in: -halfW...halfW)
				s.y = topY - Double.random(in: 0...3)
				s.vy = Double.random(in: 18...24)
				s.vx = wxHere.wind * 0.25
				s.size = weather.bigHail ? Double.random(in: 0.18...0.26) : Double.random(in: 0.09...0.14)
				hailPool[i] = s
			}
		} else {
			hailAcc = 0
		}
		let bottom: Double = camY + viewTilesH * 0.5 + 2.0
		for i in 0..<hailPool.count where hailPool[i].on {
			var s: HailStone = hailPool[i]
			s.vy = min(s.vy + 30.0 * dt, 26)
			s.vx += (wxHere.wind * 0.25 - s.vx) * min(1.0, dt * 2.0)
			s.x += s.vx * dt
			s.y += s.vy * dt
			let tx: Int = Int(floor(s.x))
			let ty: Int = Int(floor(s.y))
			if s.vy > 0 && ty >= world.rainTop(tx) && Tile.rainStopTable[world.tile(tx, ty).idx] {
				if s.bounces == 0 {
					// a bounce off whatever it hit, then it breaks
					s.y = Double(ty) - 0.02
					s.vy = -s.vy * 0.32
					s.vx += Double.random(in: -2.5...2.5)
					s.bounces = 1
					if abs(s.x - pb.x) < 6 && frameNo % 3 == 0 { sfx(.hailTick, 0.25) }
				} else {
					s.on = false
					if particles.count < 120 && abs(s.x - pb.x) < 20 { spawnParticles(s.x, s.y, 0xE8F4FF, 2, 2.0, 0.25, 22) }
				}
			}
			if s.y > bottom { s.on = false }
			hailPool[i] = s
		}
		if h < 0.05 { return }
		// what hail does: large stones sting whoever is out in it; crops, flowers and glass suffer
		hailHitT -= dt
		if hailHitT > 0 { return }
		hailHitT = weather.bigHail ? 1.6 : 2.4
		let I: Double = weatherIntensity
		if weather.bigHail && h > 0.3 {
			if settings.weatherHurtsPlayer && !dead && rainReaches(pb.x, pb.y, pb.h) {
				// a helmet turns most of the stones
				let helmet: Bool = inv.armor[0] != nil || suitHelmet
				if !helmet || Double.random(in: 0...1) < 0.35 {
					var info = DamageInfo(amount: 1.0 * I * (1.0 - armorInf.stormCut) * (suitHas(.seal) ? 0.5 : 1.0), type: .impact, source: .environment)
					info.originX = pb.x
					info.key = newID()
					_ = hurtPlayer(info)
				}
			}
			if settings.weatherHurtsCreatures {
				for m in mobsNear(pb.x - 30, pb.x + 30) where m.hp > 0 && !m.removed && !m.isBoss && m.kind != .fish {
					if Double.random(in: 0...1) < 0.3 && rainReaches(m.b.x, m.b.y, m.b.h) {
						var info = DamageInfo(amount: 1.0 * I, type: .impact, source: .environment)
						info.originX = m.b.x
						info.key = newID()
						applyMobDamage(m, info)
					}
				}
			}
		}
		if settings.weatherHurtsBlocks { hailDamage(h) }
	}

	/// Hail beats down crops a stage, shreds flowers and (large hail) breaks glass left open to the
	/// sky. A roof over anything protects it, and only a few panes go in one storm.
	func hailDamage(_ h: Double) {
		for _ in 0..<3 {
			let tx: Int = Int(floor(pb.x)) + Int.random(in: -30...30)
			if !world.isLoaded(tx) { continue }
			let ty: Int = world.rainTop(tx)
			// the first thing the hail hits, or a crop or plant standing on it
			var y: Int = ty
			var t: Tile = world.tile(tx, y)
			let above: Tile = world.tile(tx, y - 1)
			if above.isPlant {
				y -= 1
				t = above
			}
			let r: Double = Double.random(in: 0...1)
			switch t {
			case .wheat3: if r < 0.4 * h { world.set(tx, y, .wheat2) }
			case .wheat2: if r < 0.3 * h { world.set(tx, y, .wheat1) }
			case .carrot3: if r < 0.4 * h { world.set(tx, y, .carrot2) }
			case .carrot2: if r < 0.3 * h { world.set(tx, y, .carrot1) }
			case .tallGrass, .flowerR, .flowerY:
				if r < 0.25 * h { breakTile(tx, y, false, dropChance: 0.5) }
			case .glass:
				if weather.bigHail && hailBroken < 6 && r < 0.15 * h {
					hailBroken += 1
					breakTile(tx, y, false, dropChance: 0)
					sfx(.breakCrystal, at: Double(tx), 0.6)
				}
			default:
				break
			}
		}
	}

	// MARK: cold

	/// Heat from fires, furnaces, lamps and heaters close by (0...1)
	func heatNear() -> Double {
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1.0))
		var best: Double = 0
		for dy in -3...3 {
			for dx in -5...5 {
				let t: Tile = world.tile(px + dx, py + dy)
				var heat: Double = 0
				switch t {
				case .campfire, .heater: heat = 1.0
				case .furnace: heat = 0.7
				case .lantern: heat = 0.3
				case .torch: heat = 0.2
				case .lava: heat = 0.8
				default: break
				}
				if heat > 0 {
					let d: Double = sqrt(Double(dx * dx + dy * dy))
					best = max(best, heat * clampD(1.0 - d / 6.5, 0, 1))
				}
			}
		}
		return best
	}

	/// Cold country in bad weather draws the warmth out of a player who is out in it; shelter, heat
	/// and warm clothes keep it in. Far gone, the cold slows them and then starts to hurt (never to
	/// the death outside hardcore, like hunger).
	func updateCold(_ dt: Double) {
		warmthT -= dt
		if warmthT <= 0 {
			warmthT = 0.5
			warmthNear = heatNear()
			shelterLevel = shelterAt(pb.x, pb.y)
		}
		let L: LocalWeather = wxHere
		var loss: Double = 0
		if settings.weatherOn && world.dim == .overworld && mode != .creative && !dead {
			let cold: Double = clampD((L.chill - 0.5) * 2.0, 0, 1)
			if cold > 0 {
				loss = cold * (0.55 + 0.45 * clampD(abs(L.wind) / 12.0, 0, 1)) + L.precip * 0.15 * cold
				switch shelterLevel {
				case 1: loss *= 0.6
				case 2: loss *= 0.25
				case 3: loss *= 0.05
				default: break
				}
				if wearing(.winterCoat) { loss *= 0.35 }
				if wearing(.snowBoots) { loss *= 0.8 }
				if pb.inWater { loss += 0.6 * cold }
				loss *= coldGuard()
			}
		}
		let gain: Double = warmthNear * 0.12 + (loss <= 0.001 ? 0.05 : 0)
		// bare in a full blizzard a player freezes in about half a minute; a coat triples that
		bodyCold = clampD(bodyCold + (loss * 0.03 - gain) * dt, 0, 1)
		if !settings.weatherOn { bodyCold = max(0, bodyCold - dt * 0.2) }
		var slow: Double = 1.0 - 0.3 * clampD((bodyCold - 0.5) * 2.0, 0, 1)
		// deep snow drags at the feet (snow boots stay on top of it)
		if settings.weatherOn && pb.onGround && L.snowCover > 0.5 && shelterLevel == 0 && !wearing(.snowBoots) {
			slow *= 1.0 - 0.15 * clampD((L.snowCover - 0.5) * 2.0, 0, 1)
		}
		wxSlow = slow
		if bodyCold > 0.4 && !coldWarned {
			coldWarned = true
			if settings.weatherAlerts { say("You're getting cold. Get out of the wind, near a fire, or into warm clothes.", 3.5) }
		}
		if bodyCold < 0.2 { coldWarned = false }
		if bodyCold >= 0.97 && settings.weatherHurtsPlayer && settings.weatherOn {
			coldHurtT += dt
			if coldHurtT >= 4.0 {
				coldHurtT = 0
				if hp > 1 || mode == .hardcore {
					damagePlayer(1, from: pb.x, knock: 0, ignoreArmor: true)
					floatText("Freezing", pb.x, pb.y - pb.h - 0.6, 0xA8D8FF)
				}
			}
		} else {
			coldHurtT = 0
		}
	}

	// MARK: the wind's push

	/// The wind's (and a tornado's) hold on the player this frame: how it shifts walking, drifting in
	/// the air and standing still, how slippery the ground is, and a tornado's pull. Every part of it
	/// is bounded, and all of it is zero with the weather off.
	func updateWeatherForces(_ dt: Double) {
		wxWalk = 0
		wxAirDrift = 0
		wxRest = 0
		wxAccelX = 0
		wxAccelY = 0
		wxSlip = 0
		if flingT > 0 { flingT -= dt }
		if !settings.weatherOn || world.dim != .overworld || inVehicle != nil || mounted != nil || flying || noclip || dead { return }
		let expo: Double = shelterExposure(shelterLevel)
		// a breeze (under 3 blocks a second) moves nobody: calm weather leaves movement exactly as it was
		let raw: Double = wxHere.wind
		let w: Double = (raw > 0 ? 1.0 : -1.0) * max(0, abs(raw) - 3.0) * expo
		wxWalk = w * 0.1
		wxAirDrift = w * 0.3
		// a player standing still braces against the wind; only hurricane-force gusts shuffle them
		// along, slowly (at most 0.8 blocks a second), so nobody is blown across the map
		if abs(w) > 18.0 { wxRest = clampD((w - (w > 0 ? 18.0 : -18.0)) * 0.15, -0.8, 0.8) }
		if pb.onGround && expo > 0.5 {
			var slip: Double = clampD((wxHere.snowCover - 0.35) * 1.4, 0, 0.6)
			if wxHere.chill > 0.7 && wxHere.snowCover > 0.2 { slip = max(slip, 0.35) }
			if wxHere.precip > 0.4 && !wxHere.snow { slip = max(slip, 0.2 * wxHere.wet) }
			if wearing(.snowBoots) { slip *= 0.15 }
			wxSlip = slip
		}
		let tf: (Double, Double, Double) = tornadoField(pb.x, pb.y - pb.h * 0.5)
		if tf.2 > 0 {
			let k: Double = shelterLevel >= 3 ? 0 : (shelterLevel == 2 ? 0.3 : (shelterLevel == 1 ? 0.6 : 1.0))
			if k > 0 {
				wxAccelX = clampD((tf.0 - pb.vx) * 3.5, -40, 40) * k
				if tf.1 < -1.0 {
					let lift: Double = clampD(-tf.1 / 12.0, 0, 1)
					wxAccelY = (-gravityG * 1.05 * lift + clampD((tf.1 - pb.vy) * 2.5, -30, 30)) * k
					if wxAccelY < -8 { flingT = 2.5 }
				}
			}
		}
	}

	/// Light things in the open drift with the wind: shots in flight, items on the ground, small
	/// birds and bats
	func updateWindOnThings(_ dt: Double) {
		if !settings.weatherOn || world.dim != .overworld { return }
		let w: Double = wxHere.wind
		if abs(w) < 2.5 { return }
		for i in 0..<projectiles.count {
			let k: Double = windCatch(projectiles[i].kind)
			if k <= 0 || projectiles[i].stuck > 0 { continue }
			let px: Double = projectiles[i].x
			if projectiles[i].y >= Double(world.skyTop(Int(floor(px)))) { continue }
			projectiles[i].vx += w * k * dt
		}
		if abs(w) > 7.0 {
			for i in 0..<drops.count {
				let d: DropItem = drops[i]
				if d.y >= Double(world.skyTop(Int(floor(d.x)))) { continue }
				drops[i].vx = clampD(d.vx + (w * 0.45 - d.vx) * min(1.0, 0.8 * dt), -6, 6)
			}
		}
		for m in mobsNear(pb.x - 40, pb.x + 40) where isWindBlown(m.kind) && m.hp > 0 && !m.removed {
			if m.b.y >= Double(world.skyTop(Int(floor(m.b.x)))) { continue }
			m.b.vx = clampD(m.b.vx + w * 0.35 * dt, -9, 9)
		}
		// rough water tosses boats about
		let rough: Double = max(wxHere.hurricane, abs(w) > 9.0 ? (abs(w) - 9.0) / 10.0 : 0)
		if rough > 0.05 {
			for v in vehicles where v.isBoat && v.submerged > 0.05 && abs(v.px - pb.x) < 80 {
				v.asleep = false
				v.sleepT = 0
				let ph: Double = sin(weather.t * 1.7 + v.px * 0.3)
				v.vy = clampD(v.vy + ph * 10.0 * rough * dt, -6, 6)
				v.vx = clampD(v.vx + w * 0.15 * rough * dt, -10, 10)
				v.angVel = clampD(v.angVel + cos(weather.t * 1.3 + v.px * 0.2) * 1.4 * rough * dt, -1.5, 1.5)
			}
			// at a hurricane's height an open boat is swamped now and then
			if let v = inVehicle, v.isBoat, wxHere.hurricane > 0.7, settings.weatherHurtsPlayer {
				swampT += dt
				if swampT > 9.0 {
					swampT = 0
					if weather.fx() < 0.35 {
						dismount()
						pb.vy = -6
						sfx(.splash, 0.9)
						if settings.weatherAlerts { say("A wave swamps the boat and throws you into the sea!", 2.5) }
					}
				}
			} else {
				swampT = 0
			}
		}
	}

	// MARK: tornadoes

	func spawnTornado() {
		let dir: Double = weather.windDir
		let warn: Double = weather.pick(30...40)
		let ground: Double = max(30, weather.stateDur - warn - TornadoEvent.ropeDur)
		let dist: Double = weather.pick(85...110)
		let px: Double = weatherX
		let e = TornadoEvent(x: px - dir * dist, dir: dir, speed: weather.pick(2.6...3.4), warnDur: warn, groundDur: ground, strength: weather.pick(0.55...1.0), wander: weather.rand() * 6.283, uid: newID())
		weather.tornado = e
		tornadoAcc = 0
		if settings.weatherAlerts && world.dim == .overworld {
			say(joinText("Tornado warning! A funnel is forming to the ", dir > 0 ? "west" : "east", ". Get underground or into a shelter."), 4.5)
			sfx(.weatherAlert, 0.9)
		}
	}

	func endTornado(survived: Bool) {
		guard let e = weather.tornado else { return }
		weather.tornado = nil
		tornadoAcc = 0
		if weather.kind == .tornado { weather.stateT = max(weather.stateT, weather.stateDur) }
		if survived && e.closest < 120 {
			let d: Int = Int(e.closest.rounded())
			recordStorm(.tornado, e.closest < 30 ? joinText("passed within ", String(d), " blocks of you") : joinText("seen ", String(d), " blocks away"))
			if settings.weatherAlerts && world.dim == .overworld { say("The tornado has lifted. Look around for anything it scattered.", 3.5) }
		}
	}

	func updateTornado(_ dt: Double) {
		guard var e = weather.tornado else { return }
		e.t += dt
		switch e.phase {
		case 0:
			e.x += e.dir * 0.8 * dt
			if e.t >= e.warnDur {
				e.phase = 1
				e.t = 0
				if settings.weatherAlerts && world.dim == .overworld {
					say("A tornado has touched down!", 3.0)
					sfx(.weatherAlert, 0.9)
				}
			}
		case 1:
			e.x += (e.dir * e.speed + sin(e.wander + e.t * 0.35) * 1.3) * dt
			if e.t >= e.groundDur {
				e.phase = 2
				e.t = 0
			}
		default:
			e.x += e.dir * e.speed * 0.6 * dt
			if e.t >= TornadoEvent.ropeDur {
				weather.tornado = e
				endTornado(survived: true)
				return
			}
		}
		if world.dim == .overworld { e.closest = min(e.closest, abs(e.x - pb.x)) }
		weather.tornado = e
		// only near the player is it simulated in detail (beyond that it only moves)
		if world.dim == .overworld && abs(e.x - pb.x) < 100 && world.isLoaded(Int(floor(e.x))) {
			tornadoGround = Double(world.surfaceY(Int(floor(e.x))))
			tornadoEffects(dt)
		}
	}

	/// The air a tornado moves at a point: drawn in toward the funnel, lifted near it and swirled about
	/// it, strongest at the edge of its core and fading with distance; at the top of the funnel things
	/// are thrown outward. Returns (vx, vy, nearness 0...1). Speeds never exceed 16 blocks a second.
	func tornadoField(_ x: Double, _ y: Double) -> (Double, Double, Double) {
		guard let e = weather.tornado, world.dim == .overworld, settings.weatherOn else { return (0, 0, 0) }
		let f: Double = e.force * weatherIntensity
		if f <= 0.01 { return (0, 0, 0) }
		let dx: Double = x - e.x
		let ad: Double = abs(dx)
		let reach: Double = 24.0
		if ad > reach { return (0, 0, 0) }
		let core: Double = 3.2
		let height: Double = tornadoGround - y
		let near: Double = ad < core ? 1.0 : pow(max(0, (reach - ad) / (reach - core)), 1.6)
		let s: Double = dx >= 0 ? 1.0 : -1.0
		var vx: Double = -s * 9.0 * near * f
		if ad < core * 1.8 { vx += sin(weather.t * 4.2 + y * 0.7) * 7.0 * f }
		var vy: Double = 0
		if ad < core * 2.2 {
			let lift: Double = height < 18 ? 1.0 : max(0, 1.0 - (height - 18.0) / 6.0)
			vy = -12.0 * f * lift * (ad < core ? 1.0 : 0.6)
			if height >= 18 { vx = s * 10.0 * f }
		}
		let mag: Double = sqrt(vx * vx + vy * vy)
		if mag > 16.0 {
			vx *= 16.0 / mag
			vy *= 16.0 / mag
		}
		return (vx, vy, near)
	}

	/// What a tornado near the player does: it draws in and flings creatures, items, shots and
	/// vehicles, its debris hurts, and it tears loose plants, leaves and light building blocks (up to a
	/// limit; never the ground). Shelter keeps the player out of most of it.
	func tornadoEffects(_ dt: Double) {
		guard let e = weather.tornado else { return }
		let f: Double = e.force
		if f <= 0.01 { return }
		let I: Double = weatherIntensity
		for m in mobsNear(e.x - 24, e.x + 24) where m.hp > 0 && !m.removed && !m.isBoss && m.kind != .fish {
			let tf: (Double, Double, Double) = tornadoField(m.b.x, m.b.y - m.b.h * 0.5)
			if tf.2 <= 0 { continue }
			if !rainReaches(m.b.x, m.b.y, m.b.h) && shelterAt(m.b.x, m.b.y) >= 2 { continue }
			let light: Double = 1.0 / (1.0 + m.b.w * m.b.h * 0.6)
			m.b.vx = clampD(m.b.vx + clampD((tf.0 - m.b.vx) * 3.0, -40, 40) * light * dt, -16, 16)
			if tf.1 < -1.0 {
				m.b.vy = clampD(m.b.vy + (-gravityG * 1.05 + clampD((tf.1 - m.b.vy) * 2.5, -30, 30)) * light * dt, -14, 26)
				m.b.onGround = false
			}
			if !settings.weatherHurtsCreatures { m.fallPeak = 0 }
			if settings.weatherHurtsCreatures && abs(m.b.x - e.x) < 4.5 {
				var info = DamageInfo(amount: 2.0 * f * I, type: .impact, source: .environment)
				info.originX = e.x
				info.key = e.uid
				info.cooldown = 1.4
				applyMobDamage(m, info)
			}
		}
		for i in 0..<drops.count where abs(drops[i].x - e.x) < 24 {
			let tf: (Double, Double, Double) = tornadoField(drops[i].x, drops[i].y)
			if tf.2 <= 0 { continue }
			drops[i].vx = clampD(drops[i].vx + (tf.0 - drops[i].vx) * 2.0 * dt, -14, 14)
			if tf.1 < -1.0 { drops[i].vy = clampD(drops[i].vy + (tf.1 - drops[i].vy) * 2.5 * dt - gravityG * 0.8 * dt, -12, 18) }
		}
		for i in 0..<projectiles.count where abs(projectiles[i].x - e.x) < 24 && projectiles[i].stuck <= 0 {
			let tf: (Double, Double, Double) = tornadoField(projectiles[i].x, projectiles[i].y)
			projectiles[i].vx += tf.0 * 0.6 * dt
			projectiles[i].vy += tf.1 * 0.6 * dt
		}
		for v in vehicles where abs(v.px - e.x) < 24 {
			let tf: (Double, Double, Double) = tornadoField(v.px, v.py)
			if tf.2 <= 0 { continue }
			let heavy: Double = 1.0 / max(1.0, v.mass * 0.15)
			v.asleep = false
			v.sleepT = 0
			v.vx = clampD(v.vx + clampD((tf.0 - v.vx) * 0.8, -12, 12) * heavy * dt, -12, 12)
			v.angVel = clampD(v.angVel + tf.0 * 0.05 * heavy * dt, -2, 2)
		}
		// its debris
		if settings.weatherHurtsPlayer && !dead && abs(pb.x - e.x) < 4.5 && shelterLevel < 2 {
			wxDebrisT -= dt
			if wxDebrisT <= 0 {
				wxDebrisT = 1.4
				var info = DamageInfo(amount: 2.0 * f * I, type: .impact, source: .environment)
				info.originX = e.x
				info.knock = 3
				info.key = newID()
				_ = hurtPlayer(info)
			}
		}
		// the dust and wreckage thrown up at its foot
		if particles.count < 140 && abs(e.x - pb.x) < 50 && frameNo % 2 == 0 {
			let col: UInt32 = [0x8A7A60, 0x6A5A44, 0x5E8A4A, 0x9A8A70][frameNo % 4]
			spawnParticles(e.x + Double.random(in: -3...3), tornadoGround - 0.3, col, 2, 7.0, 0.8, 8)
		}
		if settings.weatherHurtsBlocks && e.broken < 90 {
			tornadoAcc += dt * 7.0 * f * I
			var broken: Int = e.broken
			while tornadoAcc >= 1.0 && broken < 90 {
				tornadoAcc -= 1.0
				let hit: Bool = weather.fx() < 0.7 ? tearAt(e.x + weather.fxPick(-4.8...4.8), f) : tearFace(e.x, e.dir, f)
				if hit { broken += 1 }
			}
			weather.tornado?.broken = broken
		} else {
			tornadoAcc = 0
		}
	}

	/// Tears one block loose at column x, working down from the first thing the wind reaches (plants
	/// and leaves give way; a solid roof or the ground stops it)
	@discardableResult
	func tearAt(_ x: Double, _ f: Double) -> Bool {
		let tx: Int = Int(floor(x))
		if !world.isLoaded(tx) { return false }
		var y: Int = max(1, world.rainTop(tx) - 1)
		var n: Int = 0
		while n < 4 {
			let t: Tile = world.tile(tx, y)
			if t == .air {
				y += 1
				n += 1
				continue
			}
			if weather.fx() < windBreak(t) * f {
				let c: UInt32 = t.def.colors.first ?? 0x8A7A60
				stormTear(tx, y, weather.wind >= 0 ? 1.0 : -1.0)
				spawnParticles(Double(tx) + 0.5, Double(y) + 0.5, c, 4, 7.0, 0.7, 6)
				return true
			}
			if t.solid { return false }
			y += 1
			n += 1
		}
		return false
	}

	/// Tears loose the first block the wind meets coming from `fromDir` at a random height near the
	/// surface around x: walls take the wind side-on (a closed storm shutter or a stone wall in front
	/// of a window keeps the glass whole)
	@discardableResult
	func tearFace(_ x: Double, _ fromDir: Double, _ f: Double) -> Bool {
		let cx: Int = Int(floor(x + weather.fxPick(-6...6)))
		if !world.isLoaded(cx) { return false }
		let ground: Int = world.surfaceY(cx)
		let y: Int = ground - 1 - Int(weather.fx() * 7.0)
		let step: Int = fromDir > 0 ? 1 : -1
		var tx: Int = cx - step * 12
		var k: Int = 0
		while k < 24 {
			let t: Tile = world.tile(tx, y)
			if t != .air && !t.liquid {
				if weather.fx() < windBreak(t) * f {
					stormTear(tx, y, fromDir)
					return true
				}
				return false
			}
			tx += step
			k += 1
		}
		return false
	}

	// MARK: hurricanes

	func spawnHurricane(_ ctx: WeatherContext) {
		let side: Double = ctx.seaSide != 0 ? ctx.seaSide : 1
		let h = HurricaneEvent(total: weather.stateDur, side: side, coastX: ctx.coastX, strength: weather.pick(0.7...1.0))
		weather.hurricane = h
		hurricaneAcc = 0
		if settings.weatherAlerts && world.dim == .overworld {
			say(joinText("Hurricane warning: a hurricane is coming in off the sea to the ", side > 0 ? "east" : "west", ". Close your shutters, then get to high ground or a shelter."), 5.0)
			sfx(.weatherAlert, 0.9)
		}
	}

	func endHurricane(survived: Bool) {
		guard let h = weather.hurricane else { return }
		weather.hurricane = nil
		hurricaneAcc = 0
		if weather.kind == .hurricane { weather.stateT = max(weather.stateT, weather.stateDur) }
		if survived && h.closest < 400 {
			recordStorm(.hurricane, h.closest < 80 ? "rode it out on the coast" : "felt it inland")
		}
	}

	func updateHurricane(_ dt: Double) {
		guard var h = weather.hurricane else { return }
		h.t += dt
		if h.t >= h.stageDur {
			h.t = 0
			if h.stage == .clearing {
				weather.hurricane = h
				endHurricane(survived: true)
				if settings.weatherAlerts && world.dim == .overworld { say("The hurricane has passed. The sea is going back down.", 3.5) }
				return
			}
			h.stage = HurricaneStage(rawValue: h.stage.rawValue + 1) ?? .clearing
			if settings.weatherAlerts && world.dim == .overworld {
				var line: String = ""
				switch h.stage {
				case .intensifying: line = "The hurricane is strengthening. The sea is rising."
				case .peak: line = "The hurricane is at its height!"
				case .eye: line = "The eye of the hurricane: a sudden calm. The far wall is coming, and the wind will turn."
				case .backside: line = "The wind is back, from the other side!"
				case .weakening: line = "The hurricane is weakening."
				case .clearing: line = "The hurricane is moving on."
				default: break
				}
				if !line.isEmpty { say(line, 3.5) }
			}
		}
		h.force = easeTo(h.force, h.stage.force * h.strength, 8, dt)
		if world.dim == .overworld { h.closest = min(h.closest, abs(pb.x - h.coastX)) }
		weather.hurricane = h
		if world.dim != .overworld { return }
		let reach: Double = hurricaneReach(pb.x, h)
		if settings.weatherHurtsBlocks && h.broken < 60 && h.force > 0.6 && reach > 0.4 {
			hurricaneAcc += dt * 1.2 * h.force * reach * weatherIntensity
			var broken: Int = h.broken
			while hurricaneAcc >= 1.0 && broken < 60 {
				hurricaneAcc -= 1.0
				let x: Double = pb.x + weather.fxPick(-40...40)
				let fromDir: Double = weather.wind >= 0 ? 1 : -1
				let hit: Bool = weather.fx() < 0.5 ? tearAt(x, h.force * 0.6) : tearFace(x, fromDir, h.force * 0.6)
				if hit { broken += 1 }
			}
			weather.hurricane?.broken = broken
		} else {
			hurricaneAcc = 0
		}
	}

	// MARK: storm surge

	/// At a hurricane's height the sea climbs a block or two up the shore near the player (sandbags
	/// hold it back). Every flooded spot is remembered, and saved, until the water has been taken
	/// away again once the storm eases; that also happens if the weather is switched off.
	func updateSurge(_ dt: Double) {
		surgeT -= dt
		if surgeT > 0 { return }
		surgeT = 0.5
		var rising: Bool = false
		var level: Int = WorldGen.sea - 1
		if settings.weatherOn && settings.allowHurricane && settings.weatherHurtsBlocks, let h = weather.hurricane, world.dim == .overworld {
			if h.stage == .peak || h.stage == .backside || h.stage == .intensifying {
				rising = true
				if h.stage == .peak || h.stage == .backside { level = WorldGen.sea - 2 }
			}
			if rising && weather.surge.count < 90 && abs(h.coastX - pb.x) < 140 { floodShore(h, level) }
		}
		if rising || weather.surge.isEmpty { return }
		// ebbing: a few spots at a time, wherever the ground is loaded (the rest waits for it). (The surge's
		// water is the storm's: it neither flows nor wakes the water round it.)
		var keep: [SurgeCell] = []
		var drained: Int = 0
		world.flowHold = true
		for c in weather.surge {
			if world.dim == .overworld && drained < 12 && world.isLoaded(c.x) {
				if world.tile(c.x, c.y) == .water { world.set(c.x, c.y, .air) }
				drained += 1
				continue
			}
			keep.append(c)
		}
		world.flowHold = false
		weather.surge = keep
	}

	/// Floods the low shore next to the sea, one strip of columns at a time
	func floodShore(_ h: HurricaneEvent, _ level: Int) {
		let inland: Int = h.side > 0 ? -1 : 1
		let sea: Int = WorldGen.sea
		// walk in from the open sea to the first column whose surface row is not sea water
		var x: Int = Int(floor(h.coastX)) - inland * 8
		var k: Int = 0
		while k < 60 && world.isLoaded(x) && world.tile(x, sea) == .water {
			x += inland
			k += 1
		}
		if !world.isLoaded(x) || k >= 60 { return }
		var added: Int = 0
		var col: Int = 0
		world.flowHold = true
		defer { world.flowHold = false }
		while col < 30 && added < 8 && weather.surge.count < 90 {
			let cx: Int = x + inland * col
			if !world.isLoaded(cx) { return }
			var y: Int = level
			var blocked: Bool = false
			while y < sea {
				let t: Tile = world.tile(cx, y)
				if t == .sandbag { blocked = true; break }
				if t == .air {
					world.set(cx, y, .water)
					weather.surge.append(SurgeCell(x: cx, y: y))
					added += 1
				}
				y += 1
			}
			// the surge stops at higher ground or at a sandbag wall
			if blocked || world.tile(cx, level).solid { return }
			col += 1
		}
	}

	// MARK: everything, once a frame

	func updateWeather(_ dt: Double) {
		if landT > 0 { landT -= dt }
		if pb.inWater && !wasInWater && pb.vy > 4.0 {
			sfx(.splash, clampD(pb.vy / 14.0, 0.3, 1.0))
			spawnParticles(pb.x, pb.y - 0.4, 0xB8D8F8, 8, 3.5, 0.45, 14)
		}
		wasInWater = pb.inWater
		stepWeatherSim(dt)
		wxHere = weatherAt(pb.x, pb.y - pb.h)
		weatherRain = wxHere.precip
		weatherSnow = wxHere.snow
		updateGroundCells(dt)
		updateTornado(dt)
		updateHurricane(dt)
		updateSurge(dt)
		updateLightning(dt)
		updateHail(dt)
		updateCold(dt)
		updateWeatherForces(dt)
		updateWindOnThings(dt)
		updateWeatherDevices(dt)
		updateWeatherBanner()
		wxNoteT -= dt
		if wxNoteT <= 0 {
			wxNoteT = 1.0
			checkWeatherNotes()
			let L: LocalWeather = wxHere
			if L.precip > 0.3 || abs(L.wind) > 8 || L.thunder > 0.5 || L.hail > 0.2 { stormFelt = true }
		}
		// rain puts out a burning player standing in it
		if weatherRain > 0.5 && !weatherSnow && playerBurn > 0 && rainReaches(pb.x, pb.y, pb.h) { playerBurn = 0 }
	}

	/// How hard it is raining at x (cheap: for checks made for many creatures)
	func precipAt(_ x: Double) -> Double {
		if world.dim != .overworld || !settings.weatherOn || weather.precip < 0.01 { return 0 }
		return weather.precip * coverAt(x) * biomeWetness(gen.col(Int(floor(x))).biome)
	}

	/// Keeps a storm the player lived through in the journal
	func recordStorm(_ k: WeatherKind, _ note: String) {
		var list: [StormRecord] = journal.storms ?? []
		list.append(StormRecord(kind: k.rawValue, day: dayCount, note: note))
		if list.count > 40 { list.removeFirst(list.count - 40) }
		journal.storms = list
	}
}

// MARK: - Weather on screen: storm skies, rain and snow, hail, wind, the funnel, lightning, waves
// Everything here is drawn from the simulation and a hash of each drop's index (no per-particle
// state), batched into one path per colour; only hailstones come from a small pool.

/// Small pixel-art weather symbols for the HUD and the station's screen
func weatherIconBuf(_ k: WeatherKind, _ snow: Bool) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let cloudL: UInt32 = 0xE8EEF4
	let cloudD: UInt32 = 0x8A929E
	let cloudS: UInt32 = 0x5A606C
	func cloud(_ c: UInt32, _ y: Int) {
		b.ellipse(4.5, Double(y) + 0.5, 2.6, 2.0, c)
		b.ellipse(7.5, Double(y) - 0.5, 3.0, 2.6, c)
		b.rect(2, y, 8, 2, c)
	}
	func drops(_ c: UInt32, _ n: Int) {
		for i in 0..<n {
			let x: Int = 2 + (i * 3) % 9
			let y: Int = 8 + (i % 2)
			b.set(x, y, c)
			b.set(x - 1, y + 2, c)
		}
	}
	func flakes() {
		for (x, y) in [(2, 9), (5, 10), (8, 9), (10, 11), (4, 11)] {
			b.set(x, y, 0xFFFFFF)
		}
	}
	switch k {
	case .clear:
		b.ellipse(6, 6, 3.0, 3.0, 0xFFD84A)
		b.ellipse(5.5, 5.5, 1.6, 1.6, 0xFFF2A0)
		for (x, y) in [(6, 0), (6, 11), (0, 6), (11, 6), (2, 2), (9, 2), (2, 9), (9, 9)] { b.set(x, y, 0xFFD84A) }
	case .partlyCloudy:
		b.ellipse(4, 4, 2.6, 2.6, 0xFFD84A)
		cloud(cloudL, 7)
	case .overcast:
		cloud(cloudD, 5)
		cloud(cloudL, 7)
	case .lightRain, .snowfall:
		cloud(cloudD, 4)
		if snow || k == .snowfall { flakes() } else { drops(0x7AB0F0, 3) }
	case .heavyRain:
		cloud(cloudS, 4)
		if snow { flakes() } else { drops(0x5A98F0, 6) }
	case .thunderstorm:
		cloud(cloudS, 4)
		b.line(7, 6, 5, 9, 0xFFE060)
		b.line(5, 9, 7, 9, 0xFFE060)
		b.line(7, 9, 5, 11, 0xFFE060)
		drops(0x5A98F0, 2)
	case .strongWind, .windstorm:
		b.line(1, 3, 8, 3, 0xE8EEF4)
		b.line(8, 3, 9, 2, 0xE8EEF4)
		b.line(0, 6, 10, 6, 0xE8EEF4)
		b.line(10, 6, 11, 5, 0xE8EEF4)
		b.line(2, 9, 7, 9, 0xE8EEF4)
		if k == .windstorm { b.set(9, 9, 0x8A6A3A); b.set(4, 11, 0x5E8A4A) }
	case .hailstorm:
		cloud(cloudS, 4)
		for (x, y) in [(3, 8), (6, 10), (9, 8), (4, 11)] { b.rect(x, y, 2, 1, 0xF4FAFF) }
	case .blizzard:
		cloud(cloudD, 3)
		flakes()
		b.line(0, 8, 6, 8, 0xC8D8E8)
	case .tornado:
		b.rect(1, 0, 10, 2, cloudS)
		b.rect(3, 2, 7, 2, 0x6E727B)
		b.rect(4, 4, 5, 2, 0x55585F)
		b.rect(5, 6, 3, 2, 0x6E727B)
		b.rect(5, 8, 2, 2, 0x55585F)
		b.rect(4, 10, 2, 1, 0x8A7A60)
	case .hurricane:
		b.ellipse(6, 6, 4.6, 4.6, 0x8A929E)
		b.ellipse(6, 6, 3.0, 3.0, 0xE8EEF4)
		b.ellipse(6, 6, 1.2, 1.2, 0x3A70C8)
		b.line(6, 1, 10, 2, 0xE8EEF4)
		b.line(6, 11, 2, 10, 0xE8EEF4)
	}
	b.outline(0x1A1410)
	return b
}

extension Art {
	func weatherIcon(_ k: WeatherKind, _ snow: Bool) -> Image {
		let key: Int = k.rawValue * 2 + (snow ? 1 : 0)
		if let i = wxIcons[key] { return i }
		let img: Image = pixImage(weatherIconBuf(k, snow))
		wxIcons[key] = img
		return img
	}
}

extension WorldRenderer {
	/// The sky's share of the weather: cloud cover and storm darkness, stars and sun hidden, the
	/// glow of lightning, and a hurricane's wall of cloud coming in off the sea
	static func drawSkyWeather(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D, _ day: Double) {
		let L: LocalWeather = g.wxHere
		let full: CGRect = mkRect(0, 0, W, H)
		let cl: Double = L.cloud
		if cl > 0.05 { fillRect(&ctx, full, Color(hex: 0x66707C, alpha: 0.7 * cl * max(0.3, day))) }
		let storm: Double = clampD((cl - 0.65) * 2.5, 0, 1) * (0.5 + 0.5 * L.precip)
		if storm > 0.02 { fillRect(&ctx, full, Color(hex: 0x262C36, alpha: 0.42 * storm * max(0.4, day))) }
		if L.snow && L.precip > 0.4 { fillRect(&ctx, full, Color(hex: 0xD8E0EA, alpha: 0.3 * L.precip * day)) }
	}

	/// The weather on the horizon: a hurricane's wall of cloud coming in off the sea
	static func drawSkyWeatherFront(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game) {
		if let h = g.weather.hurricane, h.stage.rawValue <= HurricaneStage.intensifying.rawValue {
			drawStormWall(&ctx, W, H, g, h)
		}
	}

	/// A towering wall of dark cloud on the sea-side horizon, growing as a hurricane comes in, with
	/// curtains of rain hanging under it
	static func drawStormWall(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ h: HurricaneEvent) {
		var prog: Double = clampD(h.t / max(1, h.stageDur), 0, 1)
		if h.stage == .intensifying { prog = 1.0 + prog }
		let width: Double = W * (0.22 + 0.3 * prog)
		let east: Bool = h.side > 0
		let step: Double = 8.0
		var wall: Path = Path()
		var shafts: Path = Path()
		var sx: Double = 0
		while sx < width {
			let x: Double = east ? W - sx - step : sx
			let n: Double = fbm1(sx / 60.0 + g.weather.t * 0.05, 4411, 3)
			// the wall rises toward the open sea, its top billowing
			let rise: Double = 0.35 + 0.5 * pow(1.0 - sx / width, 0.6) + 0.12 * n
			let top: Double = floor(H * (0.7 - rise * 0.75) / 4.0) * 4.0
			let base: Double = H * 0.7
			wall.addRect(mkRect(x, top, step + 1.0, base - top))
			if hash2(Int(sx / step), 3, 91) < 0.5 { shafts.addRect(mkRect(x + 2, base, 3, H * 0.2)) }
			sx += step
		}
		ctx.fill(wall, with: .color(Color(hex: 0x2E333C, alpha: 0.88)))
		ctx.fill(shafts, with: .color(Color(hex: 0x4A5464, alpha: 0.35)))
	}

	/// Lying snow (deeper where the wind drifts it), wet ground and puddles on the open surfaces in
	/// view. Drawn over the terrain and under everything else, so the light map shades it like the ground.
	static func drawGroundWeather(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld || !g.settings.weatherOn { return }
		if g.weather.cells.isEmpty { return }
		let x0: Int = Int(floor(v.left)) - 1
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 1
		let tp: Double = v.tp
		var snowP: Path = Path()
		var wetP: Path = Path()
		var pudP: Path = Path()
		var anySnow: Bool = false
		var anyWet: Bool = false
		var wetSum: Double = 0
		var wetN: Double = 0
		let lee: Double = g.weather.wind >= 0 ? 1 : -1
		let raining: Bool = g.wxHere.precip > 0.1 && !g.wxHere.snow
		var ripples: Path = Path()
		for x in x0...x1 {
			let top: Int = g.world.rainTop(x)
			if top <= 0 || top >= g.world.H - 2 { continue }
			let wy: Double = Double(top)
			if wy < v.top - 1 || wy > v.top + v.hTiles + 1 { continue }
			let t: Tile = g.world.tile(x, top)
			if t.liquid { continue }
			let wx: Double = Double(x) + 0.5
			let sc: Double = g.groundValue(wx, true)
			let wet: Double = g.groundValue(wx, false)
			let sx: Double = v.sx(Double(x))
			let sy: Double = v.sy(wy)
			if sc > 0.05 {
				let h0: Double = hash2(x, 41, 3)
				let dr: Double = 0.5 + 0.5 * sin(Double(x) * 0.37 * lee)
				let hh: Double = tp * min(0.45, sc * (0.12 + 0.22 * h0 + 0.15 * dr))
				let snapH: Double = max(2.0, floor(hh / 2.0) * 2.0)
				snowP.addRect(mkRect(sx, sy - snapH + 2.0, tp + 0.5, snapH))
				anySnow = true
			}
			if wet > 0.08 && t.solid && !isLeafTile(t) && sc < 0.3 {
				wetP.addRect(mkRect(sx, sy, tp + 0.5, max(2.0, tp * 0.14)))
				wetSum += wet
				wetN += 1
				anyWet = true
				let level: Bool = g.world.rainTop(x - 1) == top && g.world.rainTop(x + 1) == top
				if wet > 0.35 && t != .sand && level && hash2(x, 43, 5) < (wet - 0.3) * 0.9 {
					pudP.addRect(mkRect(sx + 1.0, sy - 2.0, tp - 2.0, 4.0))
					if raining && hash2(x, Int(g.clock * 3.0), 47) < 0.5 {
						let rx: Double = sx + tp * (0.2 + 0.6 * hash2(x, Int(g.clock * 3.0), 48))
						ripples.addRect(mkRect(rx - 2.0, sy - 3.0, 4.0, 1.0))
					}
				}
			}
		}
		if anyWet {
			let a: Double = 0.22 * clampD(wetSum / max(1, wetN), 0, 1)
			ctx.fill(wetP, with: .color(Color(hex: 0x10203A, alpha: a)))
			ctx.fill(pudP, with: .color(Color(hex: 0x6A9AD0, alpha: 0.62)))
			ctx.fill(ripples, with: .color(Color(hex: 0xD8ECFF, alpha: 0.7)))
		}
		if anySnow { ctx.fill(snowP, with: .color(Color(hex: 0xF4F8FF, alpha: 0.95))) }
	}

	/// Rain and snow falling in world space, slanted and carried by the wind and stopping on the first
	/// thing in their way; splashes where rain lands; hail from the pool; blown dust and grass bent
	/// over in the wind
	static func drawPrecip(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if (g.world.dim != .overworld && g.customDim == nil) || !g.settings.weatherOn { return }
		let dens: Double = clampD(g.settings.weatherParticles, 0.2, 1.0)
		let tp: Double = v.tp
		let bands: Int = 8
		var amt: [Double] = [Double](repeating: 0, count: bands)
		var cold: [Bool] = [Bool](repeating: false, count: bands)
		var anyP: Double = 0
		let midY: Double = v.top + v.hTiles * 0.5
		for b in 0..<bands {
			let x: Double = v.left + v.wTiles * (Double(b) + 0.5) / Double(bands)
			let L: LocalWeather = g.weatherAt(x, midY)
			amt[b] = L.precip
			cold[b] = L.snow
			anyP = max(anyP, L.precip)
		}
		let wind: Double = g.wxHere.wind
		let clock: Double = g.clock
		if anyP > 0.02 {
			let n: Int = Int(300.0 * dens)
			let span: Double = v.hTiles + 6.0
			let cell: Double = v.wTiles + 8.0
			let x0: Double = v.left - 4.0
			var rain: Path = Path()
			var heavy: Path = Path()
			var snow: Path = Path()
			var streak: Path = Path()
			for i in 0..<n {
				let fx: Double = hash2(i, 11, 77)
				let fy: Double = hash2(i, 12, 77)
				let fz: Double = hash2(i, 13, 77)
				let fw: Double = hash2(i, 14, 77)
				// which band it falls in decides whether it falls at all (storm cells have edges)
				let guess: Double = x0 + fx * cell
				let bi: Int = clampI(Int((guess - v.left) / v.wTiles * Double(bands)), 0, bands - 1)
				let a: Double = amt[bi]
				if fw > a { continue }
				let isSnow: Bool = cold[bi]
				let speed: Double = isSnow ? 2.6 + fz * 1.6 : 19.0 + fz * 7.0
				let vx: Double = isSnow ? wind * 0.85 : wind * 0.75
				let fallen: Double = (fy * span + clock * speed).truncatingRemainder(dividingBy: span)
				let wy: Double = v.top - 3.0 + fallen
				var raw: Double = fx * cell + vx * (fallen / speed)
				if isSnow { raw += sin(clock * 1.3 + Double(i)) * 0.5 }
				let rel: Double = raw.truncatingRemainder(dividingBy: cell)
				let wx: Double = x0 + (rel < 0 ? rel + cell : rel)
				if wy >= Double(g.world.rainTop(Int(floor(wx)))) { continue }
				let sx: Double = v.sx(wx)
				let sy: Double = v.sy(wy)
				if isSnow {
					if abs(vx) > 7.0 {
						let l: Double = tp * 0.45
						streak.move(to: mkPoint(sx, sy))
						streak.addLine(to: mkPoint(sx - (vx > 0 ? l : -l), sy - l * 0.25))
					} else {
						let s: Double = fz > 0.7 ? 3.0 : 2.0
						snow.addRect(mkRect(sx, sy, s, s))
					}
				} else {
					let len: Double = (a > 0.6 ? 0.75 : 0.5) * tp
					let dx: Double = vx / speed * len
					if a > 0.6 && fz < 0.5 {
						heavy.move(to: mkPoint(sx, sy))
						heavy.addLine(to: mkPoint(sx - dx, sy - len))
					} else {
						rain.move(to: mkPoint(sx, sy))
						rain.addLine(to: mkPoint(sx - dx, sy - len))
					}
				}
			}
			// a mod's rain colour (the Overworld's), else the game's
			let rc: UInt32 = g.world.dim == .overworld ? (ModRuntime.shared.weather?.rainColor ?? 0) : 0
			ctx.stroke(rain, with: .color(Color(hex: rc != 0 ? rc : 0xA8C8F0, alpha: 0.45)), lineWidth: 1.5)
			ctx.stroke(heavy, with: .color(Color(hex: rc != 0 ? shadeRGB(rc, 0.9) : 0x9CBCE4, alpha: 0.55)), lineWidth: 2.0)
			ctx.fill(snow, with: .color(Color.white.opacity(0.85)))
			ctx.stroke(streak, with: .color(Color.white.opacity(0.7)), lineWidth: 2.0)
			drawSplashes(&ctx, g, v, amt, cold)
		}
		drawHail(&ctx, g, v)
		drawWindFX(&ctx, g, v)
	}

	/// Little crowns of spray where rain is landing on open ground
	static func drawSplashes(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ amt: [Double], _ cold: [Bool]) {
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		let bands: Int = amt.count
		let tick: Int = Int(g.clock * 7.0)
		var p: Path = Path()
		var x: Int = x0
		while x <= x1 {
			let bi: Int = clampI(Int((Double(x) - v.left) / v.wTiles * Double(bands)), 0, bands - 1)
			let a: Double = amt[bi]
			if a > 0.05 && !cold[bi] && hash2(x, tick, 9) < a * 0.3 {
				let top: Int = g.world.rainTop(x)
				let wy: Double = Double(top)
				if top > 0 && v.visible(Double(x), wy, 1) && !g.world.tile(x, top).liquid {
					let ph: Double = (g.clock * 7.0).truncatingRemainder(dividingBy: 1.0)
					let sx: Double = v.sx(Double(x) + 0.2 + 0.6 * hash2(x, tick, 10))
					let sy: Double = v.sy(wy)
					let up: Double = 3.0 + 4.0 * ph
					p.addRect(mkRect(sx - 3.0 - ph * 2.0, sy - up, 2, 2))
					p.addRect(mkRect(sx + 1.0 + ph * 2.0, sy - up, 2, 2))
				}
			}
			x += 1
		}
		ctx.fill(p, with: .color(Color(hex: 0xC8DCF4, alpha: 0.6)))
	}

	static func drawHail(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.hailPool.isEmpty { return }
		var p: Path = Path()
		var any: Bool = false
		for s in g.hailPool where s.on {
			if !v.visible(s.x, s.y, 1) { continue }
			let r: Double = max(2.0, s.size * v.tp)
			p.addRect(mkRect(v.sx(s.x) - r * 0.5, v.sy(s.y) - r * 0.5, r, r))
			any = true
		}
		if !any { return }
		ctx.fill(p, with: .color(Color(hex: 0xF0F8FF, alpha: 0.95)))
		ctx.stroke(p, with: .color(Color(hex: 0x9AB0C8, alpha: 0.6)), lineWidth: 1)
	}

	/// Streaks of blown air (dust in dry country) and the grass bending over in the wind
	static func drawWindFX(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let wind: Double = g.wxHere.wind
		let aw: Double = abs(wind)
		if aw < 2.5 { return }
		let tp: Double = v.tp
		let dens: Double = clampD(g.settings.weatherParticles, 0.2, 1.0)
		if aw > 5.0 {
			let n: Int = min(48, Int((aw - 5.0) * 4.0 * dens))
			let cell: Double = v.wTiles + 8.0
			let x0: Double = v.left - 4.0
			let dry: Bool = g.biomeHere == .desert || g.biomeHere == .savanna
			var p: Path = Path()
			for i in 0..<n {
				let fx: Double = hash2(i, 21, 55)
				let fy: Double = hash2(i, 22, 55)
				let fz: Double = hash2(i, 23, 55)
				let raw: Double = (fx * cell + g.clock * wind * (1.1 + fz)).truncatingRemainder(dividingBy: cell)
				let wx: Double = x0 + (raw < 0 ? raw + cell : raw)
				let wy: Double = v.top + fy * v.hTiles
				if wy >= Double(g.world.rainTop(Int(floor(wx)))) { continue }
				let l: Double = tp * (0.8 + 1.2 * fz) * min(1.6, aw / 10.0)
				let sx: Double = v.sx(wx)
				let sy: Double = floor(v.sy(wy))
				p.addRect(mkRect(wind > 0 ? sx - l : sx, sy, l, dry ? 2 : 1))
			}
			ctx.fill(p, with: .color(dry ? Color(hex: 0xD8C890, alpha: 0.4) : Color.white.opacity(0.22)))
		}
		// grass bent over by the wind on open ground near the surface
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		let lean: Double = clampD(wind / 14.0, -1, 1) * 0.3
		var blades: Path = Path()
		var any: Bool = false
		for x in x0...x1 {
			let top: Int = g.world.rainTop(x)
			if top <= 0 || !v.visible(Double(x), Double(top), 1) { continue }
			let t: Tile = g.world.tile(x, top)
			if t != .grass && t != .dryGrass && t != .jungleGrass && t != .mossGrass { continue }
			let sx: Double = v.sx(Double(x))
			let sy: Double = v.sy(Double(top))
			for k in 0..<2 {
				let bx: Double = sx + tp * (0.25 + 0.5 * Double(k))
				let sway: Double = (lean + sin(g.clock * 3.1 + Double(x) * 0.9 + Double(k)) * 0.06 * g.weather.gust) * tp
				blades.move(to: mkPoint(bx, sy + 1.0))
				blades.addLine(to: mkPoint(bx + sway, sy - tp * 0.26))
				any = true
			}
		}
		if any { ctx.stroke(blades, with: .color(Color(hex: 0x6EB848, alpha: 0.9)), lineWidth: max(1.5, tp * 0.07)) }
	}

	/// The tornado: a swaying funnel of grey bands that turn as they rise, debris flung round it and
	/// a skirt of dust at its foot. While forming it only reaches part of the way down.
	static func drawTornado(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		guard let e = g.weather.tornado, g.world.dim == .overworld, g.settings.weatherOn else { return }
		let fn: Double = e.funnel
		if fn <= 0.02 { return }
		let ground: Double = g.tornadoGround > 0 ? g.tornadoGround : Double(g.world.surfaceY(Int(floor(e.x))))
		let cloudBase: Double = ground - 32.0
		if !v.visible(e.x, ground - 22.0, 40) { return }
		let tp: Double = v.tp
		let px: Double = tp / 8.0
		let reach: Double = e.phase == 0 ? cloudBase + (ground - cloudBase) * min(1.0, fn / 0.55) * 0.75 : ground
		var dark: Path = Path()
		var light: Path = Path()
		var y: Double = cloudBase
		let bandH: Double = 0.5
		while y < reach {
			let hf: Double = (ground - y) / (ground - cloudBase)
			let w: Double = (0.6 + 6.8 * pow(hf, 1.35)) * (0.5 + 0.5 * fn)
			let sway: Double = sin(g.clock * 1.6 + hf * 3.0) * (0.4 + hf * 1.6)
			let cx: Double = e.x + sway
			let sx: Double = floor(v.sx(cx - w) / px) * px
			let ex: Double = floor(v.sx(cx + w) / px) * px
			let sy: Double = floor(v.sy(y) / px) * px
			let stripe: Int = Int(floor(hf * 30.0 - g.clock * 5.0)) & 3
			let r: CGRect = mkRect(sx, sy, max(px, ex - sx), bandH * tp + 1.0)
			if stripe == 0 { light.addRect(r) } else { dark.addRect(r) }
			y += bandH
		}
		let a: Double = min(1.0, fn * 1.2)
		ctx.fill(dark, with: .color(Color(hex: 0x40434A, alpha: 0.95 * a)))
		ctx.fill(light, with: .color(Color(hex: 0x5E626B, alpha: 0.95 * a)))
		if e.phase == 0 { return }
		// debris whirling round it, and dust at the foot
		var deb: Path = Path()
		var leaf: Path = Path()
		for i in 0..<30 {
			let hf: Double = hash2(i, 61, 7) * 0.7
			let wy: Double = ground - hf * (ground - cloudBase)
			let w: Double = (0.6 + 6.8 * pow(hf, 1.35)) * 1.2 + 0.7
			let ang: Double = g.clock * (3.0 + hash2(i, 62, 7) * 2.0) + Double(i) * 1.7
			let wx: Double = e.x + cos(ang) * w + sin(g.clock * 1.6 + hf * 3.0) * (0.4 + hf * 1.6)
			let s: Double = max(2.0, tp * (0.12 + 0.12 * hash2(i, 63, 7)))
			let r: CGRect = mkRect(v.sx(wx), v.sy(wy), s, s)
			if i % 3 == 0 { leaf.addRect(r) } else { deb.addRect(r) }
		}
		ctx.fill(deb, with: .color(Color(hex: 0x6A5A44, alpha: 0.9 * a)))
		ctx.fill(leaf, with: .color(Color(hex: 0x4E7A3A, alpha: 0.9 * a)))
		var dust: Path = Path()
		for k in 0..<5 {
			let off: Double = (Double(k) - 2.0) * 1.6 + sin(g.clock * 2.0 + Double(k)) * 0.5
			let rw: Double = (2.2 + hash2(k, 64, 7) * 1.4) * tp
			let rh: Double = rw * 0.45
			dust.addEllipse(in: mkRect(v.sx(e.x + off) - rw * 0.5, v.sy(ground) - rh * 0.9, rw, rh))
		}
		ctx.fill(dust, with: .color(Color(hex: 0x8A7A60, alpha: 0.45 * a)))
	}

	/// Storm waves along the open sea's surface (a hurricane or a strong wind), with foam on the crests
	static func drawWaves(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld || !g.settings.weatherOn { return }
		let aw: Double = abs(g.weather.wind)
		let rough: Double = max(g.wxHere.hurricane, clampD((aw - 6.0) / 10.0, 0, 1) * 0.6)
		if rough < 0.05 { return }
		let sea: Int = WorldGen.sea
		if Double(sea) < v.top - 3.0 || Double(sea) > v.top + v.hTiles + 3.0 { return }
		let tp: Double = v.tp
		let dir: Double = g.weather.wind >= 0 ? 1 : -1
		var body: Path = Path()
		var foam: Path = Path()
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		for x in x0...x1 {
			// the water's surface at sea level, or a block or two above it where a surge has come in
			var top: Int = -1
			for y in (sea - 2)...sea where g.world.tile(x, y) == .water && g.world.tile(x, y - 1) == .air {
				top = y
				break
			}
			if top < 0 { continue }
			let sy: Double = v.sy(Double(top))
			let ph: Double = Double(x) * 0.42 - g.clock * 2.6 * dir
			let s: Double = sin(ph)
			let hgt: Double = floor(rough * 1.6 * (0.55 + 0.45 * s) * tp / 2.0) * 2.0
			let sx: Double = v.sx(Double(x))
			body.addRect(mkRect(sx, sy - hgt, tp + 0.5, hgt))
			if s > 0.55 { foam.addRect(mkRect(sx, sy - hgt - 2.0, tp + 0.5, 3.0)) }
		}
		ctx.fill(body, with: .color(Color(hex: artGrade(0x3B6FC8), alpha: 0.78)))
		ctx.fill(foam, with: .color(Color.white.opacity(0.75)))
	}

	/// Lightning (drawn over the darkness, so it lights up the night) and the warning glow where a
	/// strike is about to land
	static func drawBolts(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let tp: Double = v.tp
		if let m = g.strikeMark {
			let k: Double = clampD(1.0 - m.t / max(0.01, m.total), 0, 1)
			let pulse: Double = 0.5 + 0.5 * sin(g.clock * 18.0)
			let a: Double = (0.25 + 0.5 * k) * (g.settings.reduceFlashes ? 0.7 : (0.6 + 0.4 * pulse))
			let cx: Double = v.sx(m.x)
			let cy: Double = v.sy(m.y)
			fillRect(&ctx, mkRect(cx - tp * 0.15, cy - tp * 6.0, tp * 0.3, tp * 6.0), Color(hex: 0xCFE4FF, alpha: a * 0.35))
			fillOval(&ctx, mkRect(cx - tp * 1.2, cy - tp * 0.4, tp * 2.4, tp * 0.8), Color(hex: 0xCFE4FF, alpha: a * 0.6))
		}
		if g.bolts.isEmpty { return }
		let soft: Bool = g.settings.reduceFlashes
		for b in g.bolts {
			let k: Double = clampD(b.life / b.maxLife, 0, 1)
			// a double flicker (steady when flashes are turned down)
			let flick: Double = soft ? 0.8 : ((b.life > b.maxLife * 0.55 || b.life < b.maxLife * 0.3) ? 1.0 : 0.45)
			var main: Path = Path()
			for (i, p) in b.pts.enumerated() {
				let pt: CGPoint = mkPoint(v.sx(p.0), v.sy(p.1))
				if i == 0 { main.move(to: pt) } else { main.addLine(to: pt) }
			}
			var forks: Path = Path()
			for f in b.forks {
				for (i, p) in f.enumerated() {
					let pt: CGPoint = mkPoint(v.sx(p.0), v.sy(p.1))
					if i == 0 { forks.move(to: pt) } else { forks.addLine(to: pt) }
				}
			}
			ctx.stroke(main, with: .color(Color(hex: 0x9EC0FF, alpha: 0.35 * k * flick)), lineWidth: max(4.0, tp * 0.45))
			ctx.stroke(main, with: .color(Color.white.opacity(k * flick)), lineWidth: 2.5)
			ctx.stroke(forks, with: .color(Color(hex: 0xDDE8FF, alpha: 0.8 * k * flick)), lineWidth: 1.5)
		}
	}

	/// The air itself: a whiteout in a blizzard, grey murk in heavy rain, the dark under a tornado,
	/// frost creeping in at the edges when the player is freezing, and lightning's flash
	static func drawWeatherOverlay(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld { return }
		let L: LocalWeather = g.wxHere
		let full: CGRect = mkRect(0, 0, W, H)
		// heavy cloud dims the daylight evenly over everything (a storm by day is dark)
		let dim: Double = clampD((L.cloud - 0.55) * 2.2, 0, 1) * g.dayFactor
		if g.settings.weatherOn && dim > 0.02 { fillRect(&ctx, full, Color(hex: 0x0A0E16, alpha: 0.22 * dim)) }
		if g.settings.weatherOn && g.shelterLevel <= 1 {
			if L.fog > 0.02 {
				if L.snow {
					fillRect(&ctx, full, Color(hex: 0xDDE5EE, alpha: min(0.55, L.fog * 0.6)))
				} else {
					fillRect(&ctx, full, Color(hex: 0x7A8696, alpha: min(0.25, L.fog * 0.35)))
				}
			}
			if L.tornado > 0.05 { fillRect(&ctx, full, Color(hex: 0x1E2228, alpha: 0.22 * L.tornado)) }
			// blowing dust in dry country
			let aw: Double = abs(L.wind)
			let b: Biome = g.biomeHere
			if aw > 6 && (b == .desert || b == .savanna) {
				fillRect(&ctx, full, Color(hex: 0xD2B47A, alpha: 0.3 * clampD((aw - 6.0) / 8.0, 0, 1) * max(0.35, g.dayFactor)))
			}
		}
		if g.bodyCold > 0.3 { edgeVignette(&ctx, W, H, 0xCFEFFF, (g.bodyCold - 0.3) * 0.7) }
		if g.skyFlash > 0.01 {
			let inside: Double = g.shelterLevel >= 3 ? 0.3 : 1.0
			let a: Double = g.skyFlash * (g.settings.reduceFlashes ? 0.25 : 0.38) * inside
			fillRect(&ctx, full, Color(hex: 0xEEF4FF, alpha: a))
		}
	}
}

// MARK: - Weather devices: station, siren, lightning rod, turbine, rain barrels, vane, heater
// Every device reads the simulation itself (a station's forecast is the simulation's own plan, a vane
// points where the wind actually blows, a barrel fills with the rain that actually falls on it). Their
// places come from a per-chunk list that is rebuilt only when the chunk changes.

struct DeviceSpot {
	var x: Int
	var y: Int
	var t: Tile
}

/// Blocks built to stand up to storms: the wind never moves them, and walls or a roof of them make a
/// storm shelter
func isStormproof(_ t: Tile) -> Bool {
	switch t {
	case .stormBrick, .sandbag, .shutterClosed, .shingles: return true
	default: return false
	}
}

func isWeatherDevice(_ t: Tile) -> Bool {
	switch t {
	case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane: return true
	default: return false
	}
}

/// How far a lightning rod draws strikes (blocks to either side)
let rodReach: Double = 14.0
/// How far a turbine's charge reaches a Doppler station
let turbineReach: Double = 10.0

extension World {
	/// Re-reads a chunk's weather facts if it has changed since: per column, the row rain first stops
	/// at (anything solid, glass, leaves, platforms, water), and where its weather devices are
	func weatherScan(_ c: Chunk) {
		if c.wxRev == c.rev && c.wxTop.count == chunkW { return }
		c.wxRev = c.rev
		if c.wxTop.count != chunkW { c.wxTop = [Int](repeating: c.H, count: chunkW) }
		c.wxDev.removeAll(keepingCapacity: true)
		let H: Int = c.H
		for lx in 0..<chunkW {
			let base: Int = lx * H
			var top: Int = H
			var y: Int = 0
			while y < H {
				let raw: Int = Int(c.tiles[base + y])
				if raw != 0 {
					if top == H && Tile.rainStopTable[raw] { top = y }
					if Tile.deviceTable[raw] { c.wxDev.append(DeviceSpot(x: c.x0 + lx, y: y, t: Tile.make(UInt8(raw)))) }
				}
				y += 1
			}
			c.wxTop[lx] = c.hasSky ? top : 0
		}
	}

	/// The first row rain (or hail, or lightning) stops at in column x; 0 where nothing is loaded
	func rainTop(_ x: Int) -> Int {
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return 0 }
		weatherScan(c)
		return c.wxTop[x - cx * chunkW]
	}

	/// Weather devices of the given kinds between columns x0 and x1 (loaded chunks only)
	func devices(_ x0: Int, _ x1: Int, _ kinds: [Tile]) -> [DeviceSpot] {
		var out: [DeviceSpot] = []
		let c0: Int = floorDiv(x0, chunkW)
		let c1: Int = floorDiv(x1, chunkW)
		if c1 < c0 { return out }
		for cx in c0...c1 {
			guard let c = chunks[cx] else { continue }
			weatherScan(c)
			for d in c.wxDev where d.x >= x0 && d.x <= x1 && kinds.contains(d.t) { out.append(d) }
		}
		return out
	}
}

/// What a weather station's screen shows, a line at a time
struct StationLine {
	var kind: WeatherKind?
	var snow: Bool = false
	var text: String
	var sub: String = ""
	var color: UInt32 = 0xE8F0E8
}

func roughWhen(_ s: Double) -> String {
	if s < 90 { return "soon" }
	if s < 300 { return "in a few minutes" }
	if s < 600 { return "later on" }
	return "much later"
}

func minutesText(_ s: Double) -> String {
	let m: Int = Int((s / 60.0).rounded())
	if m <= 0 { return "under a minute" }
	return m == 1 ? "about 1 min" : joinText("about ", String(m), " min")
}

func windWords(_ w: Double) -> String {
	let a: Double = abs(w)
	let from: String = w > 0 ? "west" : "east"
	let speed: String = String(Int(a.rounded()))
	var how: String = "calm"
	if a >= 13 { how = "gale" } else if a >= 8 { how = "strong" } else if a >= 4 { how = "breezy" } else if a >= 1.5 { how = "light" }
	if a < 0.8 { return "Calm" }
	return joinText("Wind ", speed, " blocks/s from the ", from, " (", how, ")")
}

extension Game {
	/// The nearest lightning rod whose reach covers column x
	func rodCovering(_ x: Double) -> DeviceSpot? {
		let ix: Int = Int(floor(x))
		let r: Int = Int(rodReach)
		var best: DeviceSpot? = nil
		var bd: Int = Int.max
		for d in world.devices(ix - r, ix + r, [.lightningRod]) {
			let dd: Int = abs(d.x - ix)
			// a rod buried under a roof is no use: it has to stand in the open
			if d.y >= world.rainTop(d.x) && d.y > 0 { continue }
			if dd < bd {
				bd = dd
				best = d
			}
		}
		return best
	}

	func deviceKey(_ d: DeviceSpot) -> String { return joinText(String(d.x), ",", String(d.y)) }

	/// Rain barrels fill with the rain that falls on them, turbines store the wind's energy (and run
	/// Doppler stations near them), and sirens sound when a storm worth warning of is near
	func updateWeatherDevices(_ dt: Double) {
		wxDevT -= dt
		if wxDevT > 0 { return }
		let step: Double = 0.5 - wxDevT
		wxDevT = 0.5
		sirenLevel = 0
		if world.dim != .overworld { return }
		let px: Int = Int(floor(pb.x))
		let list: [DeviceSpot] = world.devices(px - 96, px + 96, [.rainBarrel, .rainCistern, .windTurbine, .stormSiren, .dopplerStation])
		if list.isEmpty { return }
		let warn: Bool = settings.weatherOn && sirenWorthy()
		for d in list {
			let k: String = deviceKey(d)
			switch d.t {
			case .rainBarrel, .rainCistern:
				let cap: Double = d.t == .rainBarrel ? 8 : 32
				let open: Bool = d.y < world.rainTop(d.x)
				let L: LocalWeather = weatherAt(Double(d.x) + 0.5, Double(d.y))
				if open && L.precip > 0.02 {
					let rate: Double = (L.snow ? 0.012 : 0.04) * (d.t == .rainCistern ? 2.0 : 1.0)
					weather.store[k] = min(cap, (weather.store[k] ?? 0) + L.precip * rate * step)
				}
			case .windTurbine:
				let open: Bool = d.y - 1 < world.rainTop(d.x) || world.tile(d.x, d.y - 1) == .air
				if open && settings.weatherOn {
					// like a real turbine it needs some wind before it turns (2 blocks a second)
					let w: Double = abs(weatherAt(Double(d.x) + 0.5, Double(d.y)).wind)
					weather.store[k] = min(100, (weather.store[k] ?? 0) + max(0, w - 2.0) * 0.35 * step)
				}
			case .dopplerStation:
				// the radar draws a little charge from a turbine close by
				if let t = poweringTurbine(d) {
					let tk: String = deviceKey(t)
					weather.store[tk] = max(0, (weather.store[tk] ?? 0) - 0.1 * step)
				}
			case .stormSiren:
				// sounds by itself for a dangerous storm, or whenever a pulse wire through it is on
				if warn || pulseOnAt(d.x, d.y) {
					let dist: Double = abs(Double(d.x) - pb.x)
					sirenLevel = max(sirenLevel, clampD(1.0 - dist / 64.0, 0, 1))
				}
			default:
				break
			}
		}
	}

	/// Storms a siren sounds for: a tornado forming or on the ground, a hurricane, a blizzard
	func sirenWorthy() -> Bool {
		if let e = weather.tornado, e.phase < 2, abs(e.x - pb.x) < 200 { return true }
		if let h = weather.hurricane, h.stage != .clearing { return true }
		if weather.kind == .blizzard && settings.allowBlizzard && wxHere.snow { return true }
		return false
	}

	/// A turbine with charge to spare close enough to run a Doppler station
	func poweringTurbine(_ d: DeviceSpot) -> DeviceSpot? {
		let r: Int = Int(turbineReach)
		for t in world.devices(d.x - r, d.x + r, [.windTurbine]) where abs(t.y - d.y) <= r {
			if (weather.store[deviceKey(t)] ?? 0) > 2 { return t }
		}
		return nil
	}

	/// Tapping a weather device
	func useWeatherDevice(_ tx: Int, _ ty: Int, _ t: Tile) {
		let d = DeviceSpot(x: tx, y: ty, t: t)
		let k: String = deviceKey(d)
		switch t {
		case .weatherStation, .dopplerStation:
			stationAt = d
			showWeather = true
			sfx(.tap, 0.6)
			bumpHUD()
		case .stormSiren:
			let on: Bool = settings.weatherOn && sirenWorthy()
			say(on ? "The siren is sounding: a dangerous storm is near. Take shelter!" : "Storm siren: it sounds by itself when a tornado, hurricane or blizzard comes near.", 3.0)
		case .lightningRod:
			let open: Bool = ty < world.rainTop(tx)
			say(open ? "Lightning rod: strikes within 14 blocks either side come down here, harmlessly." : "This rod is under cover. A lightning rod only works out in the open, on top of things.", 3.0)
		case .windTurbine:
			let charge: Double = weather.store[k] ?? 0
			if let st = heldStack, case .gun(.stormRod) = st.item, charge >= 50 {
				var n: Int = 0
				for i in 0..<inv.slots.count {
					if var s = inv.slots[i], case .gun(.stormRod) = s.item, s.extra < GunType.stormRod.magazine {
						s.extra = GunType.stormRod.magazine
						inv.slots[i] = s
						n += 1
					}
				}
				if n > 0 {
					weather.store[k] = charge - 50
					sfx(.zap, 0.6)
					say("The turbine's charge fills your storm rod.", 2.0)
					bumpHUD()
					return
				}
			}
			let w: Double = abs(weatherAt(Double(tx) + 0.5, Double(ty)).wind)
			say(joinText("Wind turbine: ", String(Int(charge.rounded())), "% charged (", w > 0.5 ? joinText("turning at ", String(Int(w.rounded())), " blocks/s of wind") : "becalmed", "). Runs a Doppler station within 10 blocks; tap it holding a storm rod to recharge the rod."), 3.5)
		case .rainBarrel, .rainCistern:
			let cap: Double = t == .rainBarrel ? 8 : 32
			let have: Double = weather.store[k] ?? 0
			if have >= 1.0 {
				weather.store[k] = have - 1.0
				giveItem(.gadget(.waterFlask), 1)
				sfx(.splash, 0.5)
				say(joinText("You fill a flask. ", String(Int(have - 1.0)), " of ", String(Int(cap)), " left."), 2.0)
			} else {
				say(joinText(t == .rainBarrel ? "Rain barrel" : "Rain cistern", ": ", String(format: "%.1f", have), " of ", String(Int(cap)), ". It fills when rain falls on it."), 2.5)
			}
		case .weatherVane:
			let w: Double = weatherAt(Double(tx) + 0.5, Double(ty)).wind
			say(joinText("Weather vane: ", windWords(w), "."), 2.5)
		case .shutterClosed, .shutterOpen:
			world.set(tx, ty, t == .shutterClosed ? .shutterOpen : .shutterClosed)
			sfx(.door, 0.6)
			light.valid = false
		case .heater:
			say("Heater: keeps you warm when you stand close to it, without the smoke of a fire.", 2.5)
		default:
			break
		}
	}

	/// What the station that was tapped shows (a Doppler station near a charged turbine shows more,
	/// and more exactly)
	func stationReport() -> [StationLine] {
		var out: [StationLine] = []
		guard let st = stationAt else { return out }
		let doppler: Bool = st.t == .dopplerStation
		let powered: Bool = doppler && poweringTurbine(st) != nil
		if !settings.weatherOn {
			out.append(StationLine(kind: .clear, text: "The weather is switched off", sub: "Turn it on in Settings (WEATHER) to see forecasts."))
			return out
		}
		let L: LocalWeather = weatherAt(Double(st.x) + 0.5, Double(st.y))
		let fc: [ForecastLine] = forecast()
		let now: ForecastLine = fc[0]
		out.append(StationLine(kind: weather.kind, snow: L.snow, text: joinText("Now: ", weatherLabel(weather.kind, snow: L.snow)), sub: joinText(powered ? minutesText(now.dur) : roughWhen(now.dur), " more"), color: 0xFFFFFF))
		let p: Double = pressureNow()
		let trend: Double = pressureNext() - p
		let tr: String = trend < -6 ? "falling fast" : (trend < -2 ? "falling" : (trend > 2 ? "rising" : "steady"))
		let temp: String = L.chill > 0.8 ? "freezing" : (L.chill > 0.5 ? "cold" : (L.chill > 0.25 ? "cool" : (L.hot ? "hot" : "mild")))
		out.append(StationLine(text: windWords(L.wind), sub: joinText("Pressure ", String(Int(p.rounded())), " hPa, ", tr, " · ", temp)))
		// warnings from the simulation's events
		if let e = weather.tornado {
			let d: Double = e.x - pb.x
			var line: String = joinText(e.phase == 0 ? "TORNADO FORMING " : "TORNADO ", String(Int(abs(d).rounded())), " blocks ", d > 0 ? "east" : "west")
			var sub: String = joinText("Moving ", e.dir > 0 ? "east" : "west")
			if powered {
				let coming: Bool = (d > 0) != (e.dir > 0)
				if coming && e.phase <= 1 {
					let eta: Double = abs(d) / max(0.5, e.speed) + (e.phase == 0 ? max(0, e.warnDur - e.t) : 0)
					sub = joinText(sub, " · reaches you in ", minutesText(eta))
				} else {
					sub = joinText(sub, " · moving away from you")
				}
				line = joinText(line, String(format: " · strength %d", Int((e.strength * 5.0).rounded())))
			}
			out.append(StationLine(kind: .tornado, text: line, sub: sub, color: 0xFF7060))
		}
		if let h = weather.hurricane {
			let sub: String = powered ? joinText("Over in ", minutesText(h.timeLeft()), " · sea to the ", h.side > 0 ? "east" : "west") : "Stay off the coast and out of boats"
			out.append(StationLine(kind: .hurricane, text: joinText("HURRICANE: ", h.stage.name), sub: sub, color: 0xFF7060))
		}
		if doppler && !powered { out.append(StationLine(text: "Radar unpowered", sub: "Put a charged wind turbine within 10 blocks for the full forecast", color: 0xFFC060)) }
		// the rain that is on its way (radar)
		if powered && L.precip < 0.05 && weather.precip > 0.15 {
			let up: Double = weather.wind >= 0 ? -1 : 1
			var dx: Double = 8
			while dx <= 240 {
				if coverAt(pb.x + up * dx) > 0.4 {
					let speed: Double = max(0.3, abs(weather.wind) * 0.55)
					out.append(StationLine(text: joinText("Rain ", String(Int(dx)), " blocks upwind"), sub: joinText("Reaches you in ", minutesText(dx / speed))))
					break
				}
				dx += 8
			}
		}
		// the plan
		let n: Int = powered ? fc.count : min(3, fc.count)
		if n > 1 {
			for i in 1..<n {
				let f: ForecastLine = fc[i]
				let when: String = powered ? joinText("In ", minutesText(f.startsIn), ", for ", minutesText(f.dur)) : roughWhen(f.startsIn).capitalized
				let warnCol: UInt32 = f.kind.severe ? 0xFFB060 : 0xE8F0E8
				out.append(StationLine(kind: f.kind, snow: L.snow, text: weatherLabel(f.kind, snow: L.snow), sub: when, color: warnCol))
			}
		}
		// devices close by
		let rods: Int = world.devices(st.x - 40, st.x + 40, [.lightningRod]).count
		let sirens: Int = world.devices(st.x - 64, st.x + 64, [.stormSiren]).count
		out.append(StationLine(text: joinText("Lightning rods nearby: ", String(rods), " · sirens: ", String(sirens)), sub: doppler ? "Doppler station" : "Weather station (craft a Doppler station for exact times)"))
		return out
	}

	/// A barometer in hand: less than a station tells, but always with you
	func barometerReading() -> String {
		if !settings.weatherOn { return "Barometer: steady (no weather)" }
		let p: Double = pressureNow()
		let trend: Double = pressureNext() - p
		var look: String = "fair"
		if trend < -6 || p < 995 { look = "storm likely" } else if trend < -2 { look = "unsettled" } else if trend > 2 { look = "clearing" }
		let arrow: String = trend < -2 ? "▼" : (trend > 2 ? "▲" : "▶")
		return joinText("Barometer ", String(Int(p.rounded())), " hPa ", arrow, " ", look)
	}

	/// Pouring a water flask: a crop grows a stage, a fire goes out, a burning player is doused
	func useWaterFlask(_ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		func spend() {
			if !isCreative { inv.removeAt(sel, 1) }
			useCD = 0.4
			swingT = 0.18
			sfx(.splash, 0.5)
			spawnParticles(aimX, aimY, 0x8DBBFF, 8, 2.5, 0.4, 14)
			bumpHUD()
		}
		if inReach(aimX, aimY) {
			let t: Tile = world.tile(tx, ty)
			var grown: Tile? = nil
			switch t {
			case .wheat1: grown = .wheat2
			case .wheat2: grown = .wheat3
			case .carrot1: grown = .carrot2
			case .carrot2: grown = .carrot3
			default: break
			}
			if let g = grown {
				world.set(tx, ty, g)
				spend()
				return
			}
			if let i = fireZones.firstIndex(where: { abs($0.x - aimX) < $0.r + 0.6 && abs($0.y - aimY) < 2.5 }) {
				fireZones.remove(at: i)
				spawnParticles(aimX, aimY, 0xC8C8C8, 10, 2.0, 0.8, -3)
				spend()
				return
			}
		}
		if playerBurn > 0 {
			playerBurn = 0
			spend()
			return
		}
		say("Pour it on a young crop to help it grow, or on a fire to put it out.", 2.0)
	}
}

extension WorldRenderer {
	/// The moving parts of weather devices in view: turbine blades turning with the wind, the vane
	/// pointing downwind, a siren's beacon, the water in a barrel, a station's blinking screen
	static func drawWeatherDevices(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld { return }
		let x0: Int = Int(floor(v.left)) - 2
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 2
		let list: [DeviceSpot] = g.world.devices(x0, x1, [.windTurbine, .weatherVane, .stormSiren, .rainBarrel, .rainCistern, .weatherStation, .dopplerStation])
		if list.isEmpty { return }
		let tp: Double = v.tp
		var blades: Path = Path()
		var vane: Path = Path()
		var water: Path = Path()
		var glow: Path = Path()
		var beacon: Path = Path()
		for d in list {
			if !v.visible(Double(d.x), Double(d.y), 3) { continue }
			let cx: Double = v.sx(Double(d.x) + 0.5)
			let top: Double = v.sy(Double(d.y))
			switch d.t {
			case .windTurbine:
				// three blades round the hub, turning with the local wind
				let w: Double = g.settings.weatherOn ? g.weatherAt(Double(d.x) + 0.5, Double(d.y)).wind : 0
				let ang: Double = g.clock * clampD(w * 0.6, -9, 9)
				let hx: Double = cx
				let hy: Double = top + tp * 0.18
				let len: Double = tp * 0.95
				for k in 0..<3 {
					let a: Double = ang + Double(k) * 2.0944
					blades.move(to: mkPoint(hx, hy))
					blades.addLine(to: mkPoint(hx + cos(a) * len, hy + sin(a) * len))
				}
			case .weatherVane:
				let w: Double = g.settings.weatherOn ? g.weatherAt(Double(d.x) + 0.5, Double(d.y)).wind : 0
				let s: Double = w >= 0 ? 1.0 : -1.0
				let wob: Double = sin(g.clock * 5.0) * min(0.15, abs(w) * 0.01)
				let y: Double = top + tp * 0.22
				vane.move(to: mkPoint(cx - s * tp * 0.45, y + wob * tp))
				vane.addLine(to: mkPoint(cx + s * tp * 0.45, y - wob * tp))
				vane.move(to: mkPoint(cx + s * tp * 0.45, y))
				vane.addLine(to: mkPoint(cx + s * tp * 0.25, y - tp * 0.15))
				vane.move(to: mkPoint(cx + s * tp * 0.45, y))
				vane.addLine(to: mkPoint(cx + s * tp * 0.25, y + tp * 0.15))
			case .stormSiren:
				if g.sirenLevel > 0.01 || (g.settings.weatherOn && g.sirenWorthy()) {
					let on: Bool = Int(g.clock * 3.0) % 2 == 0
					if on { beacon.addEllipse(in: mkRect(cx - tp * 0.7, top - tp * 0.5, tp * 1.4, tp * 1.0)) }
				}
			case .rainBarrel, .rainCistern:
				let cap: Double = d.t == .rainBarrel ? 8 : 32
				let f: Double = clampD((g.weather.store[g.deviceKey(d)] ?? 0) / cap, 0, 1)
				if f > 0.02 {
					let inner: Double = tp * 0.7
					let h: Double = max(2.0, tp * 0.75 * f)
					water.addRect(mkRect(cx - inner * 0.5, top + tp - h - tp * 0.05, inner, h))
				}
			case .weatherStation, .dopplerStation:
				if Int(g.clock * 1.5) % 3 != 0 { glow.addRect(mkRect(cx - tp * 0.32, top + tp * 0.55, tp * 0.64, tp * 0.2)) }
			default:
				break
			}
		}
		ctx.stroke(blades, with: .color(Color(hex: 0xF0F2F4)), lineWidth: max(2.0, tp * 0.12))
		ctx.stroke(vane, with: .color(Color(hex: 0xD2793A)), lineWidth: max(1.5, tp * 0.08))
		ctx.fill(water, with: .color(Color(hex: 0x3B7BE0, alpha: 0.85)))
		ctx.fill(glow, with: .color(Color(hex: 0x70F0B0, alpha: 0.5)))
		ctx.fill(beacon, with: .color(Color(hex: 0xFF3020, alpha: 0.45)))
	}
}

// MARK: - Weather settings, the station's screen, the journal's weather pages

/// Weather options, shared by the main settings screen and the pause menu. Every kind of weather
/// has its own switch; the first switch turns all of it off at once.
struct WeatherSettingsSection: View {
	@Binding var settings: Settings
	var onChange: () -> Void = {}

	func label(_ s: String, _ v: String) -> some View {
		Text(verbatim: joinText(s, ": ", v)).font(.pixel(12, .bold))
	}

	var freqName: String {
		switch settings.severeFrequency {
		case 0: return "rare"
		case 2: return "frequent"
		default: return "normal"
		}
	}

	func freqButton(_ i: Int, _ title: String) -> some View {
		SmallButton(title: title, color: settings.severeFrequency == i ? Color(hex: 0x4E8A3E) : Color(hex: 0x555555)) {
			settings.severeFrequency = i
			onChange()
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("WEATHER").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Toggle("Weather (all of it)", isOn: $settings.weatherOn)
			if settings.weatherOn {
				Toggle("Rain and snow", isOn: $settings.allowRain)
				Toggle("Thunderstorms and lightning", isOn: $settings.allowThunder)
				Toggle("Wind", isOn: $settings.allowWind)
				Toggle("Hail", isOn: $settings.allowHail)
				Toggle("Blizzards", isOn: $settings.allowBlizzard)
				Toggle("Tornadoes", isOn: $settings.allowTornado)
				Toggle("Hurricanes (near the sea)", isOn: $settings.allowHurricane)
				Text("WEATHER DAMAGE").font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
				Toggle("Hurts the player", isOn: $settings.weatherHurtsPlayer)
				Toggle("Damages blocks and buildings", isOn: $settings.weatherHurtsBlocks)
				Toggle("Hurts creatures", isOn: $settings.weatherHurtsCreatures)
				label("Intensity", joinText(String(Int((settings.weatherIntensity * 100.0).rounded())), "%"))
				Slider(value: $settings.weatherIntensity, in: 0.25...1.5, step: 0.05)
				label("Severe weather", freqName)
				HStack(spacing: 6) {
					freqButton(0, "RARE")
					freqButton(1, "NORMAL")
					freqButton(2, "FREQUENT")
				}
				Toggle("Weather alerts and warnings", isOn: $settings.weatherAlerts)
				label("Rain, snow and hail drawn", joinText(String(Int((settings.weatherParticles * 100.0).rounded())), "%"))
				Slider(value: $settings.weatherParticles, in: 0.2...1.0, step: 0.05)
				Toggle("Gentler lightning flashes", isOn: $settings.reduceFlashes)
			}
			SmallButton(title: "RESET WEATHER DEFAULTS") {
				settings.resetWeather()
				onChange()
			}
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}
}

/// How dangerous nights are, and when wiring is drawn
struct NightSettingsSection: View {
	@Binding var settings: Settings

	func choice(_ title: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
		SmallButton(title: title, color: on ? Color(hex: 0x4E8A3E) : Color(hex: 0x555555), action: act)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("NIGHTS").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Text("How many monsters come out at night, and how quickly").font(.pixel(11, .semibold))
			HStack(spacing: 6) {
				choice("CALM", settings.nightDanger == 0) { settings.nightDanger = 0 }
				choice("NORMAL", settings.nightDanger == 1) { settings.nightDanger = 1 }
				choice("DEADLY", settings.nightDanger == 2) { settings.nightDanger = 2 }
			}
			Text("POWER WIRING").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			HStack(spacing: 6) {
				choice("WHEN BUILDING", settings.showWires == 0) { settings.showWires = 0 }
				choice("ALWAYS", settings.showWires == 1) { settings.showWires = 1 }
				choice("FAINT", settings.showWires == 2) { settings.showWires = 2 }
			}
			buildingPart
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}

	var buildingPart: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("BUILDINGS").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Toggle("Structural physics", isOn: $settings.structural)
			Text("Blocks you build need support: each holds up so much weight and reaches out so far (shown in its info). Too far out or too heavy, it cracks and falls. The land itself never falls.").font(.pixel(11, .semibold))
			Toggle("Vehicle damage", isOn: $settings.vehicleDamage)
			Text("Shots, blasts and crashes damage vehicles: parts crack and break off. Hold an iron bar and tap a part to mend it.").font(.pixel(11, .semibold))
		}
	}
}

/// A weather station's screen, read live from the simulation
struct WeatherPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		let lines: [StationLine] = game.stationReport()
		let title: String = game.stationAt?.t == .dopplerStation ? "DOPPLER STATION" : "WEATHER STATION"
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: title).font(.pixel(17)).foregroundColor(Color(hex: 0x70F0B0))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) {
					game.showWeather = false
					game.bumpHUD()
				}
			}
			ForEach(0..<lines.count, id: \.self) { i in
				HStack(alignment: .top, spacing: 8) {
					if let k = lines[i].kind {
						Art.shared.weatherIcon(k, lines[i].snow).resizable().frame(width: 24, height: 24)
					} else {
						Color.clear.frame(width: 24, height: 24)
					}
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: lines[i].text).font(.pixel(13)).foregroundColor(Color(hex: lines[i].color))
						if !lines[i].sub.isEmpty {
							Text(verbatim: lines[i].sub).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xA8C8B8))
						}
					}
				}
			}
		}
		.padding(16)
		.background(PixelBox(color: Color(hex: 0x14201C)).opacity(0.96))
		.frame(maxWidth: 560)
		.padding(16)
	}
}

/// The weather a player has lived through, and the notes they have made about it
struct WeatherJournalPage: View {
	let game: Game
	let ink: Color
	var body: some View {
		let storms: [StormRecord] = game.journal.storms ?? []
		let notes: [String] = game.journal.lore.filter { $0.hasPrefix("wx.") }
		return VStack(alignment: .leading, spacing: 8) {
			Text("STORMS WEATHERED").font(.pixel(13)).foregroundColor(ink)
			if storms.isEmpty {
				Text("None yet. Severe weather is rare; a weather station shows what is coming.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<storms.count, id: \.self) { i in
				let s: StormRecord = storms[storms.count - 1 - i]
				let name: String = (WeatherKind(rawValue: s.kind) ?? .thunderstorm).name
				HStack {
					Text(verbatim: name).font(.pixel(12)).foregroundColor(ink)
					Text(verbatim: s.note).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x6A4A2A))
					Spacer()
					Text(verbatim: joinText("day ", String(s.day))).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x6A4A2A))
				}
			}
			Text("WEATHER NOTES").font(.pixel(13)).foregroundColor(ink).padding(.top, 6)
			if notes.isEmpty {
				Text("What you learn about lightning, wind, hail and storms is written down here as you meet them.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<notes.count, id: \.self) { i in
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: loreEntry(notes[i]).0).font(.pixel(12)).foregroundColor(ink)
					Text(verbatim: loreEntry(notes[i]).1).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x5A3A1A))
				}
			}
		}
	}
}

extension Game {
	/// Writes a weather note into the journal the first time the player meets that kind of weather
	func learnWeather(_ key: String) {
		if journal.lore.contains(key) { return }
		journal.lore.append(key)
		if settings.weatherAlerts { floatText("New note in your journal", pb.x, pb.y - pb.h - 1.0, 0xE8D8A0) }
	}

	/// Notes worth writing down from what is happening now (checked about once a second)
	func checkWeatherNotes() {
		if !settings.weatherOn || world.dim != .overworld { return }
		let L: LocalWeather = wxHere
		if let e = weather.tornado, e.phase >= 1, abs(e.x - pb.x) < 120 { learnWeather("wx.tornado") }
		if L.hurricane > 0.3 { learnWeather("wx.hurricane") }
		if weather.kind == .blizzard && settings.allowBlizzard && L.snow && L.precip > 0.4 { learnWeather("wx.blizzard") }
		if L.hail > 0.2 { learnWeather("wx.hail") }
		if abs(L.wind) > 9 { learnWeather("wx.wind") }
		if L.thunder > 1.0 { learnWeather("wx.lightning") }
		if bodyCold > 0.5 { learnWeather("wx.cold") }
	}

	/// Debug: make a kind of weather begin now (an event starts with its usual warning)
	func debugForceWeather(_ k: WeatherKind) {
		if !settings.weatherOn {
			say("Weather is switched off in Settings.", 2.0)
			return
		}
		weather.tornado = nil
		weather.hurricane = nil
		weather.kind = k
		weather.stateT = 0
		weather.stateDur = weather.pick(k.spell)
		weather.plan.removeAll()
		clearWeatherFX()
		if k == .tornado {
			if settings.allowTornado { spawnTornado() } else { say("Tornadoes are switched off in Settings.", 2.0) }
		}
		if k == .hurricane {
			if settings.allowHurricane {
				var ctx: WeatherContext = weatherContext()
				// debug storms come in anywhere: with no sea in reach, the "coast" is put to the east
				if ctx.seaSide == 0 {
					ctx.seaSide = 1
					ctx.coastX = pb.x + 60
				}
				spawnHurricane(ctx)
			} else {
				say("Hurricanes are switched off in Settings.", 2.0)
			}
		}
		if k == .hailstorm { weather.bigHail = true }
		// the amounts jump most of the way there, so the change can be seen at once
		let p: WeatherProfile = allowedProfile(k)
		weather.cloud = p.cloud
		weather.precip = p.precip * 0.8
		weather.cover = max(p.cover, 0.6)
		weather.thunder = p.thunder
		weather.hail = p.hail
		weather.chill = p.chill
		weather.wind = p.wind * weather.windDir
		fillPlan()
		say(joinText("Weather: ", weatherLabel(k, snow: wxHere.snow)), 1.5)
	}

	/// Counts the monsters that hold a place right now (the same count the spawner uses)
	func monstersAbout() -> Int {
		var n: Int = 0
		for m in mobs where m.hp > 0 && !m.removed && m.def.hostile && !m.kind.isPredator && !m.tame && !m.persistent && !m.isBoss && m.boat < 0 && m.lair == 0 {
			if abs(m.b.x - pb.x) <= 72 && abs(m.b.y - pb.y) <= 56 { n += 1 }
		}
		return n
	}

	func spawnDebugLines() -> [String] {
		var out: [String] = []
		let place: String = world.dim == .umbral ? "umbral" : (Int(pb.y) - gen.col(Int(floor(pb.x))).h > 18 ? "cave" : "surface")
		let cap: Int = monsterCap(place == "surface" ? .surface : .cave)
		out.append(joinText(isNight ? "Night" : "Day", "  ", place, "  monsters ", String(monstersAbout()), " / ", String(cap), String(format: "  next in %.1fs", max(0, monsterSpawnCD))))
		if !spawnLast.isEmpty { out.append(joinText("Last attempt: ", spawnLast)) }
		let top: [(String, Int)] = spawnLog.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
		for t in top { out.append(joinText("  ", t.0, " ×", String(t.1))) }
		return out
	}

	/// Debug: makes it night and runs forty spawn attempts at once (the pacing between monsters is
	/// skipped), then reports what came out and what stopped the rest
	func debugSpawnTest() {
		if world.dim == .overworld { debugSetTime(0.62) }
		spawnLog = [:]
		let before: Set<Int> = Set(mobs.map { $0.id })
		for _ in 0..<40 {
			spawnTimer = 0
			monsterSpawnCD = 0
			updateSpawning(0.0)
		}
		var made: [String: Int] = [:]
		for m in mobs where !before.contains(m.id) && m.def.hostile { made[m.def.name, default: 0] += 1 }
		let list: String = made.isEmpty ? "no monsters" : made.sorted { $0.value > $1.value }.map { joinText(String($0.value), " ", $0.key) }.joined(separator: ", ")
		say(joinText("Spawn test: ", list), 4.0)
		bumpHUD()
	}

	func debugStrikeNearby() {
		if !settings.weatherOn || !settings.allowThunder {
			say("Lightning is switched off in Settings.", 2.0)
			return
		}
		let x: Double = pb.x + Double(facing) * 6.0
		if let s = strikeSpot(x) { lightningStrike(s.0, s.1, rod: s.2) }
	}

	var weatherDebugLine: String {
		let k: WeatherKind = weather.kind
		let left: Int = Int(max(0, weather.stateDur - weather.stateT))
		let next: String = weather.plan.first?.kind.name ?? "-"
		return joinText(k.name, " ", String(left), "s → ", next, String(format: "  rain %.2f wind %.1f cl %.2f", weather.precip, weather.wind, weather.cloud))
	}
}

// MARK: - Ambient life

extension WorldRenderer {
	/// Fireflies over grass on clear nights; embers drifting up through the Umbral Realm. Drawn after
	/// the lighting so they glow in the dark. A handful of shapes, no particles.
	static func drawAmbientLife(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim == .umbral {
			var path: Path = Path()
			for i in 0..<24 {
				let fx: Double = hash2(i, 31, 13)
				let rise: Double = 1.2 + hash2(i, 32, 13) * 1.6
				let span: Double = v.hTiles + 4.0
				let wy: Double = v.top + span - 2.0 - (hash2(i, 33, 13) * span + g.clock * rise).truncatingRemainder(dividingBy: span)
				let wx: Double = v.left + fx * v.wTiles + sin(g.clock * 0.8 + Double(i) * 1.9) * 0.8
				let s: Double = i % 5 == 0 ? 3.0 : 2.0
				path.addRect(mkRect(v.sx(wx), v.sy(wy), s, s))
			}
			ctx.fill(path, with: .color(Color(hex: 0xFF9A4A, alpha: 0.55)))
			return
		}
		let tp: Double = v.tp
		for f in fireflySpots(g, v) {
			let x: Double = v.sx(f.0)
			let y: Double = v.sy(f.1)
			let blink: Double = f.2
			fillOval(&ctx, mkRect(x - tp * 0.22, y - tp * 0.22, tp * 0.44, tp * 0.44), Color(hex: 0xE8FF8A, alpha: 0.18 * blink))
			fillRect(&ctx, mkRect(x - 1.5, y - 1.5, 3, 3), Color(hex: 0xF4FFC0, alpha: 0.9 * blink))
		}
	}

	/// Where the fireflies are now (x and y in blocks, and how bright): at most one for every 6 columns,
	/// each at a place of its own in the world (it drifts a little around it, but never follows the
	/// player), over grass on clear nights in the overworld
	static func fireflySpots(_ g: Game, _ v: View2D) -> [(Double, Double, Double)] {
		var out: [(Double, Double, Double)] = []
		if g.dayFactor > 0.3 || g.weatherRain > 0.5 || g.world.dim != .overworld { return out }
		let c0: Int = Int(floor(v.left / 6.0)) - 1
		let c1: Int = Int(floor((v.left + v.wTiles) / 6.0)) + 1
		for cell in c0...max(c0, c1) {
			if hash2(cell, 20, 9) > 0.55 { continue }
			let i: Int = cell
			let wx: Double = Double(cell) * 6.0 + hash2(cell, 21, 9) * 6.0 + sin(g.clock * 0.4 + Double(i)) * 1.2
			let ix: Int = Int(floor(wx))
			let b: Biome = g.gen.col(ix).biome
			if !(b == .forest || b == .plains || b == .swamp || b == .jungle) { continue }
			let ground: Double = Double(g.world.surfaceY(ix))
			let wy: Double = ground - 1.0 - hash2(i, 22, 9) * 4.0 + sin(g.clock * 0.7 + Double(i) * 1.7) * 0.6
			if wy >= Double(g.world.skyTop(ix)) || !v.visible(wx, wy, 1) { continue }
			let blink: Double = 0.5 + 0.5 * sin(g.clock * 2.2 + Double(i) * 1.3)
			if blink < 0.25 { continue }
			out.append((wx, wy, blink))
		}
		return out
	}
}

// MARK: - Journal: places found, what they tell, and goals worth chasing

struct JournalPlace: Codable {
	var key: String
	var name: String
	var x: Int
	var day: Int
	var dim: Int
}

/// What the player has found and learned. Saved with the world (older saves start with an empty one).
struct Journal: Codable {
	var places: [JournalPlace] = []
	/// lore entries unlocked, in the order they were found
	var lore: [String] = []
	var relics: Int = 0
	/// names of things the player has crafted (for the goals list)
	var crafted: [String] = []
	/// storms lived through (nil in journals saved before the weather)
	var storms: [StormRecord]? = nil

	func has(_ key: String) -> Bool { return places.contains { $0.key == key } }
	func hasKind(_ prefix: String) -> Bool { return places.contains { $0.key.hasPrefix(prefix) } }
	func count(_ prefix: String) -> Int { return places.filter { $0.key.hasPrefix(prefix) }.count }
}

/// The story each kind of place tells, a line or two each
func loreEntry(_ key: String) -> (String, String) {
	switch key {
	case "ruin.house": return ("A Ruined House", "A cellar ladder, a cold hearth, a child's carving of a bear above the door. Whoever lived here left in a hurry, and went down rather than out.")
	case "ruin.tower": return ("A Ruined Tower", "The watch log's last entry: 'Lights under the hill again. Nobody goes down there now.'")
	case "ruin.fort": return ("An Old Fort", "Every arrowhead in these walls points outward and down. Whatever they fought came up out of the caves.")
	case "ruin.camp": return ("An Abandoned Camp", "Bedrolls for four, supplies for one. The tracks lead toward the mountains and do not come back.")
	case "ruin.overgrown": return ("An Overgrown Ruin", "Roots have split a shrine stone. Its carving shows a door torn open in the sky, and a hooded figure standing in it.")
	case "ruin.bunker": return ("A Buried Bunker", "Iron doors, rusted from the inside. Someone hoarded powder and shot for a war that never reached them.")
	case "mine": return ("An Old Mine", "A tally scratched into a support beam stops at forty-one. Under it, in a different hand: 'The rock sings this deep.'")
	case "grotto": return ("A Crystal Grotto", "The crystals hum when you stand still. Something set them here, and something keeps them.")
	case "lair.bear": return ("The Bear's Den", "Claw marks ring the stones. The great bear sleeps on a seal it was set to guard, and the key to that seal sleeps with it.")
	case "lair.rex": return ("The Bone Nest", "Ribs older than the hills. Whatever crowned itself with these bones still nests among them.")
	case "portal": return ("The Sealed Gate", "A chamber built around a door, deep under the earth, and a key-shaped hollow worn smooth by many hands.")
	case "umbral": return ("The Umbral Realm", "No sky, no sun, only ash and ember. The rift hums behind you. It is not the only door that was opened.")
	case "citadel": return ("The Warden's Citadel", "Carved over the gate: HERE THE WARDEN KEEPS THE DOOR, HOLLOW SINCE THE RIFT TORE OPEN.")
	case "sentinel": return ("The Sentinel", "It came apart into shards that still glow. It was not alive, but it was waiting, and it was told what to guard.")
	case "warden": return ("The Hollow Warden", "There was nothing inside the armour. Its heart is warm and beats slowly. A rift forge could bind it into something worn.")
	case "wx.lightning": return ("Notes on Lightning", "It strikes the highest thing near it: a tree top, a roof, a hill. There is a moment first, when the air crackles and your hair stands up. A copper rod standing high takes every strike within fourteen blocks safely into the ground.")
	case "wx.wind": return ("Notes on Wind", "A strong wind carries arrows and loose things with it and leans on you as you walk. A vane shows where it blows from; a turbine stores it up.")
	case "wx.hail": return ("Notes on Hail", "Most hail only bruises crops and flowers. Now and then it falls as big as eggs: then glass breaks and bare heads ache. A roof, or a helmet, is enough.")
	case "wx.blizzard": return ("Notes on Blizzards", "It is the wind on you that does the harm. A fire or a heater, a roof and walls, a good coat: any of them buys time. Snow boots keep you on your feet.")
	case "wx.cold": return ("Notes on the Cold", "Cold country, high ground and night all draw the warmth out of you, the wind and wet most of all. Stand by a fire to get it back.")
	case "wx.tornado": return ("Notes on Tornadoes", "They grow out of the worst thunderstorms and travel with the wind. Underground, or behind reinforced walls, you will hear it pass and little more. Out in the open it will pick you up.")
	case "wx.hurricane": return ("Notes on Hurricanes", "They come off the sea in walls of wind and rain. The calm in the middle is the eye; then the wind comes back from the other side. Sandbags hold back the sea, shutters save the windows.")
	default: return ("", "")
	}
}

struct JournalAim {
	var title: String
	var hint: String
	var done: Bool
}

extension Game {
	/// Goals the world offers, in roughly the order they open up. None is required; each says how to
	/// get going on it.
	func journalAims() -> [JournalAim] {
		let j: Journal = journal
		let bear: Bool = defeated.contains { $0 >= 0 && $0 < 1_000_000 }
		let rexDown: Bool = defeated.contains { $0 >= 1_000_000 && $0 < 2_000_000 }
		let sentinel: Bool = defeated.contains { $0 >= 6_000_000 && $0 < 8_000_000 }
		let sigil: Bool = j.crafted.contains(Gear.wardenSigil.name) || wearing(.wardenSigil) || inv.total(.gear(.wardenSigil)) > 0
		return [
			JournalAim(title: "Set up a workbench", hint: "Eight planks. Chop a tree with your hands or an axe, then make planks from the logs.", done: j.crafted.contains("Workbench")),
			JournalAim(title: "Forge iron on an anvil", hint: "Smelt iron ore in a furnace, then build an anvil (6 iron bars, 4 stone) at the workbench.", done: j.crafted.contains("Anvil")),
			JournalAim(title: "Explore an old mine", hint: "Look for a timber headframe over a covered shaft. The treasure map marks them.", done: j.hasKind("mine:")),
			JournalAim(title: "Find a crystal grotto", hint: "Deep underground, sometimes with a cave mouth leading down.", done: j.hasKind("grotto:")),
			JournalAim(title: "Defeat Ursavor", hint: "The great bear's den holds the Portal Key.", done: bear),
			JournalAim(title: "Open the sealed gate", hint: "The Portal Key opens the rift chamber far below the surface. The treasure map narrows it down.", done: portalOpened),
			JournalAim(title: "Defeat Tyrannax", hint: "Something nests among enormous bones in the jungle.", done: rexDown),
			JournalAim(title: "Silence a Crystal Sentinel", hint: "Each grotto has a guardian. Its shards are worth the fight.", done: sentinel),
			JournalAim(title: "Reach the Warden's citadel", hint: "In the Umbral Realm, several hundred blocks from the rift.", done: j.has("citadel")),
			JournalAim(title: "Defeat the Hollow Warden", hint: "Watch the ground: its strikes are marked before they land.", done: defeated.contains(WorldGen.wardenKey)),
			JournalAim(title: "Forge the Warden's Sigil", hint: "The Warden's heart, 4 voidium bars and 4 crystal shards at a rift forge.", done: sigil),
			JournalAim(title: "Recover relic fragments (\(min(j.relics, 10))/10)", hint: "Found in ruins, mines, grottos and with the bosses.", done: j.relics >= 10),
		]
	}

	func discover(_ key: String, _ name: String, _ x: Int, lore: String) {
		if journal.has(key) { return }
		journal.places.append(JournalPlace(key: key, name: name, x: x, day: dayCount, dim: world.dim.rawValue))
		var line: String = "Discovered: " + name + "."
		if !lore.isEmpty && !journal.lore.contains(lore) {
			journal.lore.append(lore)
			line += " (New journal entry)"
		}
		say(line, 3.5)
		sfx(.discovery, 0.8)
		spawnParticles(pb.x, pb.y - pb.h - 0.4, 0xFFE070, 10, 2.5, 0.8, -3)
		bumpHUD()
	}

	func addLore(_ key: String) {
		if !journal.lore.contains(key) { journal.lore.append(key) }
	}

	/// Checks twice a second whether the player has walked into a place worth noting
	func updateDiscoveries(_ dt: Double) {
		discoverT -= dt
		if discoverT > 0 || dead { return }
		discoverT = 0.5
		let px: Int = Int(floor(pb.x))
		let py: Double = pb.y
		if world.dim == .umbral {
			if !journal.has("umbral") { discover("umbral", "The Umbral Realm", px, lore: "umbral") }
			if let c = gen.citadel, abs(px - c.x) < 42 && abs(py - Double(c.floor)) < 14 {
				discover("citadel", "The Warden's Citadel", c.x, lore: "citadel")
			}
			return
		}
		if world.dim != .overworld { return }
		for r in gen.rareSites(overlapping: px - 20, px + 20) where abs(px - r.x) < 14 && abs(py - Double(gen.col(r.x).h)) < 14 {
			let k: String = "\(r.kind)"
			discover("ruin:\(r.cell)", rareName(r.kind), r.x, lore: "ruin." + k)
		}
		for m in gen.mineSites(overlapping: px - 6, px + 6) where px >= m.x - 3 && px <= m.x + 5 && py > Double(m.ground - 6) && py < Double(m.bottom + 2) {
			discover("mine:\(m.cell)", "Old Mine", m.x, lore: "mine")
		}
		for gs in gen.grottoSites(overlapping: px - 2, px + 2) where abs(px - gs.x) < gs.rx && abs(py - Double(gs.floorY)) < Double(gs.ry + 2) {
			discover("grotto:\(gs.cell)", "Crystal Grotto", gs.x, lore: "grotto")
		}
		for L in gen.lairCenters(near: px) where abs(px - L.cx) < 40 {
			discover("lair:\(L.kind):\(L.k)", L.kind == .bear ? "The Bear's Den" : "The Bone Nest", L.cx, lore: L.kind == .bear ? "lair.bear" : "lair.rex")
		}
		if abs(px - gen.portalX) < 12 && abs(py - Double(gen.portalY)) < 10 {
			discover("portal", "The Sealed Gate", gen.portalX, lore: "portal")
		}
	}
}

// MARK: - Animal life: herds, rest, water, predators and prey

/// Animals that predators hunt
func isPrey(_ k: MobKind) -> Bool {
	switch k {
	case .pig, .cow, .sheep, .chicken, .giraffe, .frog: return true
	default: return false
	}
}

extension Game {
	/// Herding, sleeping at night, walking to water to drink and running from hunting predators. It
	/// looks around about once a second (not every frame) and uses the creature grid for neighbours.
	/// Returns true when it moved the animal this frame (the caller then skips plain wandering).
	func animalLife(_ m: Mob, _ dt: Double) -> Bool {
		if m.poseT > 0 { m.poseT -= dt }
		if m.drinkT > 0 { m.drinkT -= dt }
		m.thinkT -= dt
		if m.thinkT <= 0 {
			m.thinkT = Double.random(in: 0.8...1.4)
			// a hunting predator close by: run
			for o in mobsNear(m.b.x - 10, m.b.x + 10) where o.hp > 0 && o !== m && o.preyID != 0 && !o.tame {
				if abs(o.b.x - m.b.x) < 10 && abs(o.b.y - m.b.y) < 4 {
					m.t2 = 3.0
					m.tx = o.b.x
					m.goal = 0
					return false
				}
			}
			// in a downpour, hail or a gale, animals out in the open head for cover (a tree, a roof)
			if m.goal == 0 && world.dim == .overworld && settings.weatherOn && abs(m.b.x - pb.x) < 60 {
				let bad: Bool = precipAt(m.b.x) > 0.55 || wxHere.hail > 0.2 || abs(wxHere.wind) > 11 || weather.tornado != nil
				if bad && rainReaches(m.b.x, m.b.y, m.b.h), let cx = coverNear(m, 14) {
					m.goal = 3
					m.goalX = cx
				}
			}
			// the herd and the water hole wait for daylight; at night animals settle where they are
			if m.goal == 0 && !(isNight && world.dim == .overworld) {
				if m.drinkT <= 0 && Double.random(in: 0...1) < 0.15, let wx = waterNear(m, 12) {
					m.goal = 1
					m.goalX = wx
				} else if Double.random(in: 0...1) < 0.3 {
					// drift back toward the rest of the herd
					var sum: Double = 0
					var n: Int = 0
					for o in mobsNear(m.b.x - 18, m.b.x + 18) where o.kind == m.kind && o !== m && o.hp > 0 && !o.tame {
						sum += o.b.x
						n += 1
					}
					if n > 0 {
						let cx: Double = sum / Double(n)
						if abs(cx - m.b.x) > 7 { m.goal = 2; m.goalX = cx }
					}
				}
			}
		}
		if m.goal != 0 {
			let dx: Double = m.goalX - m.b.x
			if (abs(dx) < 1.2 && m.goal != 3) || abs(dx) < 0.5 || (m.goal == 2 && abs(dx) < 4) {
				if m.goal == 3 {
					// sheltering: stand still under cover a while
					m.poseT = 6.0
					m.st = 0
				}
				if m.goal == 1 {
					// drinking: head down for a few seconds
					m.drinkT = Double.random(in: 25...45)
					m.poseT = 3.0
					m.st = 0
					m.t1 = 3.2
				}
				m.goal = 0
			} else {
				m.dir = dx > 0 ? 1 : -1
				// the water itself reads as a drop just before the edge; that is where it was going
				let edge: Bool = m.goal == 1 && abs(dx) < 2.5
				if (cliffAhead(m, m.dir) && !edge) || (m.b.hitWall && !m.b.onGround) {
					m.goal = 0
				} else {
					accelX(m, Double(m.dir) * m.def.speed * 0.6, 14, dt)
					if m.b.hitWall && m.b.onGround { m.b.vy = -m.def.jump }
					return true
				}
			}
		}
		if m.poseT > 0 {
			accelX(m, 0, 18, dt)
			return true
		}
		// at night farm animals mostly settle down and sleep
		if isNight && world.dim == .overworld && m.kind != .frog {
			if m.st == 1 && Double.random(in: 0...1) < 0.02 { m.st = 0; m.t1 = Double.random(in: 4...9) }
			if m.st == 0 {
				m.t1 -= dt
				if m.t1 <= 0 { m.st = 1; m.t1 = Double.random(in: 0.8...1.6); m.dir = Bool.random() ? 1 : -1 }
				accelX(m, 0, 18, dt)
				return true
			}
		}
		return false
	}

	/// The nearest column with cover overhead (leaves, a roof) at about the animal's own level
	func coverNear(_ m: Mob, _ r: Int) -> Double? {
		let x0: Int = Int(floor(m.b.x))
		let feet: Double = m.b.y
		var k: Int = 1
		while k <= r {
			for side in [1, -1] {
				let x: Int = x0 + side * k
				if !rainReaches(Double(x) + 0.5, feet, m.b.h) && world.groundBelow(x, Int(floor(feet)) - 1) <= Int(floor(feet)) + 1 {
					// a step further in, if that is covered too, so the whole body is under it
					let deeper: Int = x + side
					if !rainReaches(Double(deeper) + 0.5, feet, m.b.h) { return Double(deeper) + 0.5 }
					return Double(x) + 0.5
				}
			}
			k += 1
		}
		return nil
	}

	/// The nearest surface water within reach, as the column to stand at beside it
	func waterNear(_ m: Mob, _ r: Int) -> Double? {
		let x0: Int = Int(floor(m.b.x))
		let gy: Int = Int(floor(m.b.y))
		var k: Int = 1
		while k <= r {
			for side in [1, -1] {
				let x: Int = x0 + side * k
				for dy in -2...2 where world.tile(x, gy + dy) == .water {
					return Double(x - side) + 0.5
				}
			}
			k += 2
		}
		return nil
	}

	/// Predators (wolves at night, big cats and bears any time the player isn't their target) run down
	/// prey nearby, bite it, and rest after a kill. Returns true while it has prey to chase.
	func hunt(_ m: Mob, _ dt: Double, _ allowed: Bool) -> Bool {
		if m.poseT > 0 {
			// resting after a meal
			m.poseT -= dt
			accelX(m, 0, 18, dt)
			return true
		}
		var prey: Mob? = nil
		if m.preyID != 0 {
			if let o = m.prey, o.id == m.preyID, o.hp > 0, !o.removed { prey = o }
			if prey == nil {
				// the prey is gone: rest, and stay sated for a while
				m.preyID = 0
				m.poseT = 4.0
				m.drinkT = 60.0
				return true
			}
		}
		m.thinkT -= dt
		if prey == nil && allowed && m.thinkT <= 0 {
			m.thinkT = Double.random(in: 1.5...3.0)
			var bd: Double = 14
			for o in mobsNear(m.b.x - 14, m.b.x + 14) where isPrey(o.kind) && o.hp > 0 && !o.tame && abs(o.b.y - m.b.y) < 4 {
				let d: Double = abs(o.b.x - m.b.x)
				if d < bd { bd = d; prey = o }
			}
			if let p = prey { m.preyID = p.id; m.prey = p }
		}
		guard let p = prey else { return false }
		if !allowed || abs(p.b.x - m.b.x) > 26 { m.preyID = 0; return false }
		chase(m, p.b.x, 1.05, dt)
		if m.kind == .wolf && m.b.onGround && abs(p.b.x - m.b.x) < 4 && Double.random(in: 0...1) < 0.03 { m.b.vy = -11; m.b.vx = Double(m.dir) * 7 }
		if m.cd <= 0 && abs(p.b.x - m.b.x) < m.b.w * 0.5 + p.b.w * 0.5 + 0.4 && abs(p.b.y - m.b.y) < 1.4 {
			m.cd = 0.9
			m.atkT = Mob.atkDur
			hurtMob(p, m.def.dmg, Double(m.dir), 5, false)
			// the herd scatters
			for o in mobsNear(p.b.x - 10, p.b.x + 10) where o.kind == p.kind && o.hp > 0 { o.t2 = 3.0; o.tx = m.b.x }
		}
		return true
	}
}

// MARK: - Telegraphed attacks and the newer creatures' behaviour

/// Ground an attack is about to strike. Drawn as a pulsing warning that fills from the bottom as the
/// moment comes, so every telegraphed blow reads the same way and can be stepped out of.
struct DangerZone {
	var x0: Double
	var y0: Double
	var x1: Double
	var y1: Double
	/// seconds until the strike, and the whole wind-up
	var t: Double
	var dur: Double
	var color: UInt32
}

enum WardenAtk: Int {
	case none, sweep, bolts, blink, pillars, summon
}

extension WorldGen {
	/// the Hollow Warden's entry in the list of defeated bosses
	static let wardenKey: Int = 9_000_001
	/// a grotto's Crystal Sentinel in that list
	static func sentinelKey(_ cell: Int) -> Int { return 7_000_000 + cell }
}

extension Game {
	func warn(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ dur: Double, _ color: UInt32 = 0xFF3A2A) {
		if dangerZones.count >= 24 { dangerZones.removeFirst() }
		sfx(.warn, at: (x0 + x1) * 0.5, 0.6)
		dangerZones.append(DangerZone(x0: min(x0, x1), y0: min(y0, y1), x1: max(x0, x1), y1: max(y0, y1), t: dur, dur: max(0.05, dur), color: color))
	}

	func updateDangerZones(_ dt: Double) {
		if dangerZones.isEmpty { return }
		for i in dangerZones.indices { dangerZones[i].t -= dt }
		dangerZones.removeAll { $0.t <= 0 }
	}

	/// A creature's blow over a box; targets are pushed away from the creature
	func mobAttackBox(_ m: Mob, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, dmg: Double, knock: Double, type: DamageType = .melee) {
		var info = DamageInfo(amount: dmg, type: type, source: .mob(m, faction(of: m)))
		info.knock = knock
		info.originX = m.b.x
		info.originY = m.b.cy
		info.key = newID()
		damageBox(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), info)
	}

	// MARK: cave crawler: fast, crouches and pounces

	func updateCrawler(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		switch m.st {
		case 3:
			// a short crouch before the pounce
			m.t3 -= dt
			accelX(m, 0, 50, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.7
				m.cd = 0
				m.b.vy = -8.5
				m.b.vx = Double(m.dir) * 10.5
				m.atkT = Mob.atkDur
			}
		case 4:
			m.t3 -= dt
			contactHurt(m, d.dmg * 1.3)
			if (m.b.onGround && m.t3 < 0.55) || m.t3 <= 0 {
				m.st = 0
				m.cd = 1.3
			}
		default:
			if aggro {
				chase(m, m.aimX, 1.0, dt)
				// scrambles up ledges
				if m.b.hitWall && m.b.onGround { m.b.vy = -11.5 }
				if m.ai == .chase && m.b.onGround && m.cd <= 0 && dist > 1.8 && dist < 4.6 && abs(dyP) < 2.0 {
					m.st = 3
					m.t3 = 0.28
				}
				if m.ai == .chase { contactHurt(m, d.dmg) }
			} else {
				wander(m, dt, 0.6)
			}
		}
		stepMob(m, dt)
	}

	// MARK: stone golem: slow, armoured, slams the ground and throws rocks

	func updateGolem(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		switch m.st {
		case 3:
			// fists raised: the slam lands where the warning shows
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.35
				let x0: Double = m.dir > 0 ? m.b.x - 0.6 : m.b.x - 3.9
				let x1: Double = m.dir > 0 ? m.b.x + 3.9 : m.b.x + 0.6
				mobAttackBox(m, x0, m.b.y - 2.4, x1, m.b.y + 0.1, dmg: d.dmg, knock: 10)
				m.atkT = Mob.atkDur
				addShake(dist < 10 ? 0.2 : 0.06)
				spawnParticles(m.b.x + Double(m.dir) * 2.2, m.b.y - 0.1, 0x8A8680, 10, 4.0, 0.5, 14)
			}
		case 4:
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 { m.st = 0; m.cd = 1.6 }
		case 5:
			// a boulder held overhead
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				throwRock(m)
				m.st = 4
				m.t3 = 0.3
				m.cd = 2.8
			}
		default:
			if aggro {
				chase(m, m.aimX, 1.0, dt)
				if m.ai == .chase && m.cd <= 0 && m.b.onGround {
					if dist < 3.3 && abs(dyP) < 2.4 {
						m.st = 3
						m.t3 = 0.75
						m.dir = pb.x >= m.b.x ? 1 : -1
						let x0: Double = m.dir > 0 ? m.b.x - 0.6 : m.b.x - 3.9
						let x1: Double = m.dir > 0 ? m.b.x + 3.9 : m.b.x + 0.6
						warn(x0, m.b.y - 2.4, x1, m.b.y, 0.75, 0xFF8A2A)
					} else if dist > 4.5 && dist < 11 && Double.random(in: 0...(m.blockedT > 0 ? 0.3 : 1.0)) < 0.02
								&& world.lineClear(m.b.x, m.b.top - 1.5, pb.x, pb.y - pb.h * 0.6) {
						// lobbed, so it clears a low wall: thrown over anything it can see over
						m.st = 5
						m.t3 = 0.6
					}
				}
				if m.ai == .chase { contactHurt(m, d.dmg * 0.5) }
			} else {
				wander(m, dt, 0.35)
			}
		}
		stepMob(m, dt, stepUp: 1.0)
	}

	/// A lobbed boulder, aimed so its arc comes down on the player
	func throwRock(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let oy: Double = m.b.top + 0.2
		let dx: Double = pb.x - ox
		let t: Double = clampD(abs(dx) / 9.0, 0.5, 1.3)
		let grav: Double = 22.0
		let vx: Double = dx / t
		let vy: Double = ((pb.y - 0.8) - oy - 0.5 * grav * t * t) / t
		var p = Projectile(kind: .rock, x: ox, y: oy, vx: vx, vy: vy, dmg: m.def.dmg * 0.8, fromPlayer: false, gravity: grav)
		p.w = 0.6
		p.life = 3.0
		p.owner = m.id
		p.source = .mob(m, faction(of: m))
		p.uid = newID()
		projectiles.append(p)
		m.atkT = Mob.atkDur
	}

	// MARK: skeleton archer: keeps its distance and shoots arced arrows

	func updateArcher(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		switch m.st {
		case 3:
			// the draw: a clear moment to close in or take cover
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				if clearShot(m) {
					shootArrowAtPlayer(m)
					m.st = 6
					m.t3 = 0.25
				} else if m.t3 < -0.8 {
					// the target went behind cover: the draw is let down, and next time it climbs for a
					// better spot (see think)
					m.st = 0
					m.cd = 0.4
					m.blockedT += 0.6
				}
			}
		case 6:
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 { m.st = 0; m.cd = Double.random(in: 1.4...2.2) }
		default:
			if aggro {
				// keeps its distance from the moment it notices the player; shoots once it is fighting
				let sees: Bool = m.sees && (m.ai == .chase || m.ai == .alert)
				if dist < 5.0 && sees {
					// too close: back off, hopping away now and then
					flee(m, pb.x, dt, 1.1)
					if m.b.onGround && Double.random(in: 0...1) < 0.025 { m.b.vy = -10; m.b.vx = Double(m.dir) * 5.5 }
				} else if dist > 12.0 || !sees || m.blockedT > 0.5 || !m.b.onGround {
					chase(m, m.aimX, 0.9, dt)
				} else {
					accelX(m, 0, 20, dt)
					m.dir = pb.x >= m.b.x ? 1 : -1
				}
				if m.ai == .chase && m.cd <= 0 && sees && m.b.onGround && dist >= 3.0 && dist < 18 && abs(dyP) < 10 {
					m.st = 3
					m.t3 = 0.6
				}
			} else {
				wander(m, dt, 0.4)
			}
		}
		stepMob(m, dt)
	}

	/// A clear line from where a shot leaves to the player's chest, checked at the moment of release
	func clearShot(_ m: Mob) -> Bool {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		return world.lineClear(ox, shotY(m), pb.x, shotAimY(m))
	}

	/// Where a creature's shot leaves (its shoulder) and the part of the player it aims for: the chest,
	/// or the head when only the head shows over cover
	func shotY(_ m: Mob) -> Double { return m.b.top + 0.45 }

	func shotAimY(_ m: Mob) -> Double {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let chest: Double = pb.y - pb.h * 0.55
		if world.lineClear(ox, shotY(m), pb.x, chest) { return chest }
		return pb.top + 0.25
	}

	func shootArrowAtPlayer(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let oy: Double = shotY(m)
		let tx: Double = pb.x + pb.vx * 0.2
		let ty: Double = shotAimY(m)
		let grav: Double = 15.0
		let dx: Double = tx - ox
		let dy: Double = ty - oy
		let flight: Double = max(0.15, sqrt(dx * dx + dy * dy) / 19.0)
		var p = Projectile(kind: .arrow, x: ox, y: oy, vx: dx / flight, vy: dy / flight - 0.5 * grav * flight, dmg: m.def.dmg, fromPlayer: false, gravity: grav)
		p.life = 3.0
		p.w = 0.22
		p.owner = m.id
		p.source = .mob(m, faction(of: m))
		p.uid = newID()
		projectiles.append(p)
	}

	// MARK: mimic: a chest that bites

	func updateMimic(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		m.t1 -= dt
		m.angry = aggro
		if m.st == 3 {
			// jaws wide before the lunge
			m.t3 -= dt
			accelX(m, 0, 30, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.6
				m.cd = 0
				m.b.vy = -9.5
				m.b.vx = Double(m.dir) * 9.0
				m.atkT = Mob.atkDur
			}
		} else if m.st == 4 {
			m.t3 -= dt
			if abs(dyP) < 1.4 { contactHurt(m, d.dmg * 1.2) }
			if (m.b.onGround && m.t3 < 0.45) || m.t3 <= 0 {
				m.st = 0
				m.cd = m.hp < m.maxHP * 0.4 ? 0.7 : 1.1
			}
		} else if aggro {
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.b.onGround {
				m.b.vx *= 0.8
				if m.cd <= 0 && dist < 5.0 && abs(dyP) < 2.2 {
					m.st = 3
					m.t3 = 0.3
				} else if m.t1 <= 0 {
					m.b.vy = -8.0
					m.b.vx = Double(m.dir) * 5.0
					m.t1 = 0.45
				}
			}
			if abs(dyP) < 1.4 { contactHurt(m, d.dmg * 0.6) }
		} else {
			// sits still and passes for a chest again
			accelX(m, 0, 20, dt)
		}
		stepMob(m, dt)
	}

	/// Some unopened chests underground in newer worlds are mimics: opening one wakes it instead
	func tryMimic(_ x: Int, _ y: Int) -> Bool {
		if world.dim != .overworld || gen.genVersion < 3 { return false }
		if y < WorldGen.sea + 20 { return false }
		// opened before, or placed by the player
		if world.chests[world.chestKey(x, y)] != nil { return false }
		if hash2(x, y, gen.seed &+ 909) >= 0.08 { return false }
		// a grotto's altar chest has its own guardian
		for s in gen.grottoSites(overlapping: x - 2, x + 2) where abs(x - s.x) <= 1 && abs(y - (s.floorY - 2)) <= 1 { return false }
		let loot: [Stack] = world.removeChest(x, y)
		world.set(x, y, .air)
		let m: Mob = addMob(.mimic, Double(x) + 0.5, Double(y) + 1.0)
		m.loot = loot
		m.persistent = true
		m.homeX = Double(x) + 0.5
		m.homeY = Double(y) + 1.0
		m.dir = pb.x >= m.b.x ? 1 : -1
		m.st = 3
		m.t3 = 0.45
		m.angry = true
		addShake(0.12)
		spawnParticles(m.b.x, m.b.y - 0.5, 0xB98A4E, 8, 4.0, 0.4, 12)
		say("The chest was a Mimic!", 2.5)
		return true
	}

	// MARK: crystal sentinel: the grotto's guardian

	func updateGuardians() {
		let px: Int = Int(floor(pb.x))
		for s in gen.grottoSites(overlapping: px - 60, px + 60) {
			let key: Int = WorldGen.sentinelKey(s.cell)
			if defeated.contains(key) { continue }
			var existing: Mob? = nil
			for m in mobs where m.kind == .sentinel && m.lair == key && m.hp > 0 { existing = m }
			let dx: Double = abs(Double(s.x) + 0.5 - pb.x)
			let dy: Double = abs(Double(s.floorY) - pb.y)
			if existing == nil {
				if dx < Double(s.rx) + 1 && dy < Double(s.ry) + 3 && !dead && world.isLoaded(s.x) {
					let m: Mob = addMob(.sentinel, Double(s.x) + 0.5, Double(s.floorY) - 3.0)
					m.lair = key
					m.homeX = Double(s.x) + 0.5
					m.homeY = Double(s.floorY)
					m.persistent = true
					m.phase = 1
					m.t1 = 1.5
					m.dir = pb.x >= m.b.x ? 1 : -1
					say("A Crystal Sentinel wakes to guard the grotto!", 3.0)
				}
			} else if let e = existing, dx > 90 || dy > 60 {
				// leaving resets the fight
				e.hp = 0
				e.removed = true
			}
		}
	}

	func updateSentinel(_ m: Mob, _ dt: Double) {
		let floorY: Double = m.homeY
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		m.anim += dt * 2.5
		if m.phase < 2 && m.hp < m.maxHP * 0.55 && m.st != 1 {
			m.phase = 2
			say("The Crystal Sentinel flares with light!", 2.5)
			spawnParticles(m.b.x, m.b.cy, 0xD8FFFA, 24, 6.0, 0.7, 0)
		}
		var tx: Double = m.b.x
		var ty: Double = floorY - 2.8 + sin(clock * 1.7 + Double(m.id % 7)) * 0.5
		switch m.st {
		case 1:
			m.t2 -= dt
			m.tele = m.t2
			// dropping to the player's level before a dash
			if m.atk == 3 { ty = m.ty }
			if m.t2 <= 0 { m.tele = 0; executeSentinel(m) }
		case 2:
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0; m.t1 = m.phase == 2 ? Double.random(in: 0.9...1.4) : Double.random(in: 1.4...2.2) }
		case 5:
			// dashing straight through
			m.t2 -= dt
			m.b.vx = Double(m.dir) * 15.0
			m.b.vy = (m.ty - m.b.y) * 2.0
			if abs(dyP) < 1.8 { contactHurt(m, m.def.dmg * 1.3) }
			world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
			if m.t2 <= 0 || m.b.hitWall || abs(m.b.x - m.homeX) > 24 {
				m.st = 2
				m.t2 = 0.6
				m.b.vx *= 0.3
			}
			return
		default:
			m.dir = toP >= 0 ? 1 : -1
			if dead {
				tx = m.homeX
			} else {
				// keeps a few blocks off the player
				tx = pb.x - Double(m.dir) * 4.5
			}
			m.t1 -= dt
			if m.t1 <= 0 && !dead && dist < 28 { chooseSentinelAttack(m, dist) }
		}
		tx = clampD(tx, m.homeX - 20, m.homeX + 20)
		let sp: Double = m.def.speed * (m.phase == 2 ? 1.25 : 1.0)
		m.b.vx += (clampD((tx - m.b.x) * 1.8, -sp, sp) - m.b.vx) * min(1.0, dt * 3.0)
		m.b.vy += (clampD((ty - m.b.y) * 2.0, -sp * 1.5, sp * 1.5) - m.b.vy) * min(1.0, dt * 3.0)
		world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
		if !dead && abs(dyP) < 1.6 { contactHurt(m, m.def.dmg * 0.5) }
	}

	func chooseSentinelAttack(_ m: Mob, _ dist: Double) {
		let r: Double = Double.random(in: 0...1)
		let fy: Double = m.homeY
		m.dir = pb.x >= m.b.x ? 1 : -1
		if m.phase == 2 && r < 0.4 {
			// crystal spikes burst from the floor around the player
			m.atk = 2
			m.t2 = 0.95
			var xs: [Double] = []
			for k in -1...1 {
				let sx: Double = clampD(pb.x + Double(k) * 3.0 + Double.random(in: -0.5...0.5), m.homeX - 24, m.homeX + 24)
				xs.append(sx)
				warn(sx - 0.7, fy - 3.0, sx + 0.7, fy, 0.95, 0x5AF0F0)
			}
			m.spots = xs
		} else if r < 0.72 || dist > 9 {
			// a fan of shards
			m.atk = 1
			m.t2 = 0.6
		} else {
			// a dash along the player's level
			m.atk = 3
			m.t2 = 0.6
			m.ty = pb.y - 0.1
			warn(m.b.x, m.ty - 2.1, m.b.x + Double(m.dir) * 14.0, m.ty, 0.6, 0x5AF0F0)
		}
		m.st = 1
	}

	func executeSentinel(_ m: Mob) {
		let fy: Double = m.homeY
		switch m.atk {
		case 2:
			for sx in m.spots {
				mobAttackBox(m, sx - 0.7, fy - 3.0, sx + 0.7, fy + 0.1, dmg: 14, knock: 6, type: .impact)
				spawnParticles(sx, fy - 0.5, 0x8AF0E8, 8, 5.0, 0.5, 6)
			}
			m.spots = []
			addShake(0.12)
			m.st = 2
			m.t2 = 0.6
		case 3:
			m.st = 5
			m.t2 = 0.75
			m.atkT = Mob.atkDur
		default:
			let n: Int = m.phase == 2 ? 5 : 3
			let ox: Double = m.b.x + Double(m.dir) * 0.8
			let oy: Double = m.b.cy
			let aim: Double = atan2((pb.y - pb.h * 0.55) - oy, pb.x - ox)
			for k in 0..<n {
				let a: Double = aim + (Double(k) - Double(n - 1) * 0.5) * 0.17
				var p = Projectile(kind: .shard, x: ox, y: oy, vx: cos(a) * 13.0, vy: sin(a) * 13.0, dmg: 9, fromPlayer: false, gravity: 0)
				p.life = 3.0
				p.w = 0.25
				p.owner = m.id
				p.source = .mob(m, faction(of: m))
				p.uid = newID()
				projectiles.append(p)
			}
			m.atkT = Mob.atkDur
			spawnParticles(ox, oy, 0xD8FFFA, 6, 3.0, 0.25, 0)
			m.st = 2
			m.t2 = 0.5
		}
	}

	func onGuardianDefeated(_ m: Mob) {
		if m.lair != 0 { defeated.insert(m.lair) }
		dangerZones.removeAll()
		addShake(m.kind == .warden ? 0.6 : 0.35)
		spawnParticles(m.b.x, m.b.cy, m.kind == .warden ? 0xD8A8FF : 0x8AF0E8, 36, 8.0, 1.1, 6)
		addLore(m.kind == .warden ? "warden" : "sentinel")
		if m.kind == .warden {
			say("The Hollow Warden falls. Its heart still beats - a rift forge could bind it into a sigil.", 7.0)
		} else {
			say("The Crystal Sentinel shatters. The grotto is yours.", 4.5)
		}
	}

	// MARK: the Hollow Warden

	func updateWardenSpawn() {
		guard let c = gen.citadel else { return }
		let key: Int = WorldGen.wardenKey
		if defeated.contains(key) { return }
		var existing: Mob? = nil
		for m in mobs where m.kind == .warden && m.hp > 0 { existing = m }
		let dx: Double = abs(Double(c.x) + 0.5 - pb.x)
		let dy: Double = abs(Double(c.floor) - pb.y)
		if existing == nil {
			if dx < 30 && dy < 16 && !dead && world.isLoaded(c.throneX) {
				let m: Mob = addMob(.warden, Double(c.throneX) + 0.5, Double(c.floor) - 0.4)
				m.lair = key
				m.homeX = Double(c.x) + 0.5
				m.homeY = Double(c.floor)
				m.persistent = true
				m.phase = 1
				m.t1 = 2.0
				m.dir = pb.x >= m.b.x ? 1 : -1
				say("The Hollow Warden rises from its throne.", 4.0)
				sfx(.roar, at: m.b.x, 1.0)
			}
		} else if let e = existing, dx > 140 {
			e.hp = 0
			e.removed = true
			dangerZones.removeAll()
		}
	}

	func updateWarden(_ m: Mob, _ dt: Double) {
		let floorY: Double = m.homeY
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		let dirP: Int = toP >= 0 ? 1 : -1
		m.anim += dt * 2.0
		let hpf: Double = m.hp / m.maxHP
		let want: Int = hpf > 0.66 ? 1 : (hpf > 0.33 ? 2 : 3)
		if want > m.phase && (m.st == 0 || m.st == 2) {
			m.phase = want
			m.st = 1
			m.atk = WardenAtk.summon.rawValue
			m.t2 = 1.3
			m.spots = []
			say(want == 2 ? "The Hollow Warden calls up its servants!" : "The Warden's lights burn white. The floor trembles.", 3.0)
			addShake(0.3)
		}
		let quick: Double = m.phase == 3 ? 0.72 : (m.phase == 2 ? 0.86 : 1.0)
		var tx: Double = m.b.x
		let ty: Double = floorY - 0.4 + sin(clock * 1.4) * 0.25
		switch m.st {
		case 1:
			m.t2 -= dt
			m.tele = m.t2
			if m.t2 <= 0 { m.tele = 0; executeWarden(m) }
		case 2:
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0; m.t1 = Double.random(in: 1.0...1.7) * quick }
		case 3:
			// bolts, one after another
			m.t2 -= dt
			m.dir = dirP
			if m.t2 <= 0 {
				fireWardenBolt(m)
				m.t3 -= 1
				if m.t3 <= 0 { m.st = 2; m.t2 = 0.5 } else { m.t2 = m.phase == 1 ? 0.2 : 0.15 }
			}
		default:
			m.dir = dirP
			if dead { tx = m.homeX } else if dist > 4.2 { tx = pb.x - Double(dirP) * 3.6 } else if dist < 2.2 { tx = pb.x - Double(dirP) * 3.0 }
			m.t1 -= dt
			if m.t1 <= 0 && !dead && dist < 44 { chooseWardenAttack(m, dist) }
		}
		tx = clampD(tx, m.homeX - 37, m.homeX + 37)
		let sp: Double = m.def.speed * (m.phase == 1 ? 1.0 : (m.phase == 2 ? 1.2 : 1.4))
		m.b.vx += (clampD((tx - m.b.x) * 2.0, -sp, sp) - m.b.vx) * min(1.0, dt * 4.0)
		m.b.vy += ((ty - m.b.y) * 3.0 - m.b.vy) * min(1.0, dt * 4.0)
		world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
		if !dead && dist < m.b.w * 0.5 + 0.5 && abs((pb.y - pb.h * 0.5) - m.b.cy) < 2.6 { contactHurt(m, 10) }
	}

	func startWardenSweep(_ m: Mob, _ tele: Double) {
		m.atk = WardenAtk.sweep.rawValue
		m.t2 = tele
		let reach: Double = 7.0
		let x0: Double = m.dir > 0 ? m.b.x - 0.8 : m.b.x - reach
		let x1: Double = m.dir > 0 ? m.b.x + reach : m.b.x + 0.8
		m.tx = x0
		m.ty = x1
		warn(x0, m.homeY - 3.6, x1, m.homeY, tele)
		m.st = 1
	}

	func chooseWardenAttack(_ m: Mob, _ dist: Double) {
		var r: Double = Double.random(in: 0...1)
		let fy: Double = m.homeY
		m.dir = pb.x >= m.b.x ? 1 : -1
		// variety: in the last phase the void pillars come at least every third attack, and no attack
		// is used three times running
		if m.phase == 3 && m.sinceSignature >= 2 { r = 0 }
		if m.repeatN >= 2 && m.lastAtk == WardenAtk.bolts.rawValue && dist >= 7.5 { r = m.phase >= 2 ? 0.4 : 0.0 }
		if m.phase == 3 && r < 0.35 {
			// void pillars erupt in a row across the hall
			m.atk = WardenAtk.pillars.rawValue
			m.t2 = 1.0
			var xs: [Double] = []
			for k in -2...2 {
				let sx: Double = clampD(pb.x + Double(k) * 4.0, m.homeX - 38, m.homeX + 38)
				xs.append(sx)
				warn(sx - 0.8, fy - 8.0, sx + 0.8, fy, 1.0, 0xB060FF)
			}
			m.spots = xs
			m.st = 1
		} else if m.phase >= 2 && r < 0.62 && dist > 4.5 {
			// vanishes and reappears on the far side of the player
			m.atk = WardenAtk.blink.rawValue
			m.t2 = 0.7
			let side: Double = pb.x >= m.b.x ? 1.0 : -1.0
			let dest: Double = clampD(pb.x + side * 3.2, m.homeX - 36, m.homeX + 36)
			m.tx = dest
			warn(dest - 1.6, fy - 4.6, dest + 1.6, fy, 0.7, 0xB060FF)
			m.st = 1
		} else if dist < 7.5 {
			startWardenSweep(m, m.phase == 3 ? 0.6 : 0.8)
		} else {
			m.atk = WardenAtk.bolts.rawValue
			m.t2 = 0.55
			m.st = 1
		}
	}

	func executeWarden(_ m: Mob) {
		let fy: Double = m.homeY
		if m.atk != WardenAtk.summon.rawValue {
			m.repeatN = m.atk == m.lastAtk ? m.repeatN + 1 : 1
			m.lastAtk = m.atk
			m.sinceSignature = m.atk == WardenAtk.pillars.rawValue ? 0 : m.sinceSignature + 1
		}
		switch WardenAtk(rawValue: m.atk) ?? .none {
		case .sweep:
			mobAttackBox(m, m.tx, fy - 3.6, m.ty, fy + 0.1, dmg: m.def.dmg, knock: 12)
			m.atkT = 0.45
			addShake(0.16)
			spawnParticles((m.tx + m.ty) * 0.5, fy - 1.0, 0xC8C8E0, 10, 6.0, 0.3, 4)
			m.st = 2
			m.t2 = 0.55
		case .bolts:
			m.st = 3
			m.t3 = Double(m.phase == 1 ? 3 : 4)
			m.t2 = 0
		case .blink:
			spawnParticles(m.b.x, m.b.cy, 0x8A4AE0, 16, 4.0, 0.6, -2)
			m.b.x = m.tx
			m.b.vx = 0
			spawnParticles(m.b.x, m.b.cy, 0xD8A8FF, 16, 4.0, 0.6, -2)
			m.dir = pb.x >= m.b.x ? 1 : -1
			startWardenSweep(m, 0.42)
		case .pillars:
			for sx in m.spots {
				mobAttackBox(m, sx - 0.8, fy - 8.0, sx + 0.8, fy + 0.1, dmg: 20, knock: 9, type: .impact)
				for k in 0..<4 { spawnParticles(sx, fy - Double(k) * 2.0, 0xB070FF, 3, 2.5, 0.5, -6) }
			}
			m.spots = []
			addShake(0.22)
			m.st = 2
			m.t2 = 0.8
		case .summon:
			for side in [-1.0, 1.0] {
				let sx: Double = m.homeX + side * 28.0
				_ = addMob(.imp, sx, fy - 0.05)
				spawnParticles(sx, fy - 1.0, 0x8A4AE0, 14, 4.0, 0.6, -3)
			}
			m.st = 2
			m.t2 = 0.6
		case .none:
			m.st = 0
		}
	}

	func fireWardenBolt(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 1.6
		let oy: Double = m.b.y - 2.6
		let aim: Double = atan2((pb.y - pb.h * 0.55) - oy, pb.x - ox)
		// the last phase throws each bolt as a fan of three
		let fan: [Double] = m.phase == 3 ? [-0.2, 0, 0.2] : [Double.random(in: -0.06...0.06)]
		for off in fan {
			let a: Double = aim + off
			var p = Projectile(kind: .bolt, x: ox, y: oy, vx: cos(a) * 12.0, vy: sin(a) * 12.0, dmg: 13, fromPlayer: false, gravity: 0)
			p.life = 3.5
			p.w = 0.4
			p.owner = m.id
			p.source = .mob(m, faction(of: m))
			p.uid = newID()
			projectiles.append(p)
		}
		m.atkT = Mob.atkDur
		spawnParticles(ox, oy, 0xD8A8FF, 4, 2.0, 0.25, 0)
	}
}

func isHumanoid(_ k: MobKind) -> Bool {
	switch k {
	case .zombie, .skeleton, .pirate, .pirateGunner, .pirateCaptain, .imp, .archer: return true
	default: return false
	}
}
