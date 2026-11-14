// PIXEL REALM v2, part 5 of 8: Mod Creator+ (game content changes, ore controls, sprite tools, custom infusions, boss phases and
// summoning, custom dimensions with their suns, moons and trees, the Logic Studio, rules, weather, machines,
// vehicles and themes in mods), the HUD and the panels.
// The game is eight files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm8.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 2 (a01_artsheet).

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

// ===== u03_hud =====

// MARK: - Shared UI pieces

extension Font {
	static func pixel(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
		return Font.system(size: size, weight: weight, design: ThemeRT.design)
	}
}

/// How the game's screens look: the theme of the enabled mods (the last of them that has one). Its
/// colours by role take the place of the game's own (other shades of a role keep their lightness),
/// everything else leans to its tint; it sets the letters, the corners and outlines of buttons and
/// panels, the title screen and the HUD.
enum ThemeRT {
	static var current: ModTheme? = nil
	static var map: [UInt32: UInt32] = [:]
	static var design: Font.Design = .monospaced

	static func set(_ t: ModTheme?) {
		current = t
		var m: [UInt32: UInt32] = [:]
		if let th = t {
			for r in ThemeRole.allCases where r != .tint {
				let c: UInt32 = th.color(r)
				if c == 0 { continue }
				let base: Double = max(1, rgbLight(r.gameColor))
				for g in r.gameColors { m[g] = shadeRGB(c, clampD(rgbLight(g) / base, 0.3, 2.0)) }
			}
		}
		map = m
		switch t?.font ?? 0 {
		case 1: design = .rounded
		case 2: design = .serif
		case 3: design = .default
		default: design = .monospaced
		}
	}

	/// The theme of the enabled mods, read again (at the title screen, and after the Mod Creator)
	static func refresh() {
		var t: ModTheme? = nil
		for e in ModStore.entries() where e.enabled {
			if let th = e.pack?.theme { t = th }
		}
		set(t)
	}

	/// A colour of the game's screens as the theme has it
	static func color(_ hex: UInt32) -> UInt32 {
		guard let t = current else { return hex }
		if let m = map[hex] { return m }
		let tint: UInt32 = t.color(.tint)
		if tint != 0 && t.tintAmt > 0 { return mixRGB(hex, tint, t.tintAmt) }
		return hex
	}

	static var corner: CGFloat { return CGFloat(current?.corner ?? 0) }
	static var outline: Color { return Color(hex: current?.outline ?? 0) }
	static var hudScale: CGFloat { return CGFloat(current?.hudScale ?? 1) }
	static var hudAlpha: Double { return current?.hudAlpha ?? 1 }
	static var swapSides: Bool { return current?.swapSides ?? false }
}

/// How light a colour looks (0...255)
func rgbLight(_ c: UInt32) -> Double {
	let r: Double = Double((c >> 16) & 255)
	let g: Double = Double((c >> 8) & 255)
	let b: Double = Double(c & 255)
	return r * 0.3 + g * 0.59 + b * 0.11
}

extension Color {
	/// A colour of the game's screens (not of the world), as the enabled mods' theme has it
	init(ui hex: UInt32, alpha: Double = 1.0) {
		self.init(hex: ThemeRT.color(hex), alpha: alpha)
	}
}

/// Joins strings without long '+' chains (keeps the type checker fast)
func joinText(_ parts: String...) -> String {
	return parts.joined()
}

func pick(_ on: Bool, _ a: UInt32, _ b: UInt32) -> Color {
	if on { return Color(ui: a) }
	return Color(ui: b)
}

struct PixelBox: View {
	var color: Color = Color(ui: 0x6B6B6B)
	@ViewBuilder
	var body: some View {
		if ThemeRT.corner > 0 { rounded } else { square }
	}

	var square: some View {
		ZStack {
			Rectangle().fill(ThemeRT.outline)
			Rectangle().fill(color).padding(3)
			VStack(spacing: 0) {
				Rectangle().fill(Color.white.opacity(0.3)).frame(height: 3)
				Spacer(minLength: 0)
				Rectangle().fill(Color.black.opacity(0.35)).frame(height: 3)
			}
			.padding(3)
		}
	}

	/// a theme's rounded box: its outline, then the colour
	var rounded: some View {
		let r: CGFloat = ThemeRT.corner
		return ZStack {
			RoundedRectangle(cornerRadius: r).fill(ThemeRT.outline)
			RoundedRectangle(cornerRadius: max(1, r - 2)).fill(color).padding(3)
		}
	}
}

struct PixelButton: View {
	let title: String
	var color: Color = Color(ui: 0x6B6B6B)
	var action: () -> Void
	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.pixel(17))
				.foregroundColor(Color.white)
				.shadow(color: Color.black, radius: 0, x: 2, y: 2)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 11)
				.background(PixelBox(color: color))
		}
		.buttonStyle(.plain)
	}
}

struct SmallButton: View {
	let title: String
	var color: Color = Color(ui: 0x6B6B6B)
	var action: () -> Void
	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.pixel(13))
				.foregroundColor(Color.white)
				.lineLimit(1)
				.padding(.horizontal, 10)
				.padding(.vertical, 8)
				.background(PixelBox(color: color).opacity(0.92))
		}
		.buttonStyle(.plain)
	}
}

struct HoldButton: View {
	let label: String
	var size: CGFloat = 70
	var color: Color = Color(ui: 0x6B6B6B)
	var onChange: (Bool) -> Void
	@State var pressed: Bool = false
	var fontSize: CGFloat { return size * (label.count > 4 ? 0.2 : 0.3) }
	var fill: Color { return pressed ? Color(ui: 0x3A3A3A) : color }
	var body: some View {
		Text(label)
			.font(.pixel(fontSize))
			.foregroundColor(Color.white)
			.frame(width: size, height: size)
			.background(PixelBox(color: fill).opacity(0.78))
			.contentShape(Rectangle())
			.gesture(holdGesture)
	}

	var holdGesture: some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { _ in press() }
			.onEnded { _ in release() }
	}

	func press() {
		if !pressed {
			pressed = true
			onChange(true)
		}
	}

	func release() {
		pressed = false
		onChange(false)
	}
}

/// One tap to the next weapon: shows the weapon it will switch to
struct WeaponSwapButton: View {
	let stack: Stack
	var action: () -> Void
	var body: some View {
		Button(action: action) {
			ZStack(alignment: .bottomTrailing) {
				Art.shared.icon(stack.item)
					.resizable()
					.frame(width: 34, height: 34)
					.frame(width: 56, height: 56)
				Text("⇄")
					.font(.pixel(14))
					.foregroundColor(Color.white)
					.shadow(color: Color.black, radius: 0, x: 1, y: 1)
					.padding(3)
			}
			.frame(width: 56, height: 56)
			.background(PixelBox(color: Color(ui: 0x5A4A7A)).opacity(0.85))
		}
		.buttonStyle(.plain)
	}
}

/// Item icon with stack count, used by the hotbar and every inventory grid
struct SlotView: View {
	let stack: Stack?
	var selected: Bool = false
	var size: CGFloat = 44
	var dim: Bool = false
	var iconSize: CGFloat { return size * 0.72 }
	var countFont: CGFloat { return size * 0.27 }
	var ammoFont: CGFloat { return size * 0.22 }
	var border: Color { return selected ? Color.white : Color.gray.opacity(0.55) }
	var borderWidth: CGFloat { return selected ? 3 : 1 }
	var iconOpacity: Double { return dim ? 0.4 : 1.0 }
	func ammoText(_ s: Stack, _ gt: GunType) -> String {
		let a: String = String(s.extra)
		let b: String = String(gt.magazine)
		return "\(a)/\(b)"
	}
	var body: some View {
		ZStack(alignment: .bottomTrailing) {
			Rectangle().fill(Color.black.opacity(0.55))
			if let s = stack {
				Art.shared.icon(s.item)
					.resizable()
					.frame(width: iconSize, height: iconSize)
					.frame(width: size, height: size)
					.opacity(iconOpacity)
				if s.count > 1 {
					Text(String(s.count))
						.font(.pixel(countFont))
						.foregroundColor(Color.white)
						.shadow(color: Color.black, radius: 0, x: 1, y: 1)
						.padding(2)
				}
				if case .gun(let gt) = s.item {
					Text(ammoText(s, gt))
						.font(.pixel(ammoFont))
						.foregroundColor(Color(ui: 0xFFE080))
						.shadow(color: Color.black, radius: 0, x: 1, y: 1)
						.padding(2)
				}
				if let l = s.inf, !l.isEmpty { infusionMarks(l) }
			}
		}
		.frame(width: size, height: size)
		.overlay(Rectangle().stroke(border, lineWidth: borderWidth))
	}
}

struct IconRow: View {
	let value: Double
	let perIcon: Double
	let count: Int
	let full: Image
	let empty: Image
	var size: CGFloat = 18
	var body: some View {
		HStack(spacing: 1) {
			ForEach(0..<count, id: \.self) { i in
				ZStack(alignment: .leading) {
					empty.resizable().frame(width: size, height: size)
					full.resizable()
						.frame(width: size, height: size)
						.frame(width: partWidth(i), height: size, alignment: .leading)
						.clipped()
				}
				.frame(width: size, height: size, alignment: .leading)
			}
		}
	}

	func partWidth(_ i: Int) -> CGFloat {
		let f: CGFloat = fraction(i)
		return size * f
	}

	func fraction(_ i: Int) -> CGFloat {
		let f: Double = (value - Double(i) * perIcon) / perIcon
		let q: Double = (clampD(f, 0, 1) * 2.0).rounded(.down) / 2.0
		return CGFloat(q)
	}
}

struct OutlinedText: View {
	let text: String
	var size: CGFloat = 13
	var color: Color = .white
	var body: some View {
		Text(text)
			.font(.pixel(size))
			.foregroundColor(color)
			.shadow(color: Color.black, radius: 0, x: 1, y: 1)
			.shadow(color: Color.black, radius: 0, x: -1, y: -1)
	}
}

// MARK: - Virtual joystick

struct StickView: View {
	let game: Game
	var radius: CGFloat = 62
	@State var knob: CGSize = CGSize.zero
	var diameter: CGFloat { return radius * 2 }
	var box: CGFloat { return diameter + 30 }

	var body: some View {
		ZStack {
			Circle().fill(Color.black.opacity(0.22)).frame(width: diameter, height: diameter)
			Circle().stroke(Color.white.opacity(0.35), lineWidth: 3).frame(width: diameter, height: diameter)
			Rectangle().fill(Color.white.opacity(0.18)).frame(width: diameter, height: 2)
			Circle().fill(Color.white.opacity(0.55)).frame(width: 58, height: 58).offset(knob)
		}
		.frame(width: box, height: box)
		.contentShape(Rectangle())
		.gesture(stickGesture)
	}

	var stickGesture: some Gesture {
		DragGesture(minimumDistance: 0, coordinateSpace: .local)
			.onChanged { v in moved(v.location) }
			.onEnded { _ in released() }
	}

	func moved(_ p: CGPoint) {
		let r: Double = Double(radius)
		let c: Double = Double(box) * 0.5
		let pxd: Double = Double(p.x)
		let pyd: Double = Double(p.y)
		var dx: Double = pxd - c
		var dy: Double = pyd - c
		let len: Double = sqrt(dx * dx + dy * dy)
		if len > r {
			dx = dx / len * r
			dy = dy / len * r
		}
		knob = CGSize(width: CGFloat(dx), height: CGFloat(dy))
		var sx: Double = dx / r
		if abs(sx) < 0.18 { sx = 0 }
		// make walking feel snappy: most of the range is full speed
		let mag: Double = min(1.0, abs(sx) * 1.35)
		game.stick = sx >= 0 ? mag : -mag
		game.stickY = dy / r
	}

	func released() {
		knob = CGSize.zero
		game.stick = 0
		game.stickY = 0
	}
}

// MARK: - Combat stick

/// The attack stick, on the right beside JUMP. Touch and hold to attack; with the thumb in the middle the
/// game picks the target, and sliding it out aims by hand in any direction (what that means depends on
/// the weapon: see Game.stickAim). Letting go stops. It has its own touch, so it works at the same time
/// as the walking stick and the JUMP button, and releasing one never affects the others.
struct CombatStickView: View {
	let label: String
	var radius: CGFloat = 68
	@State var thumb: CGSize = CGSize.zero
	@State var down: Bool = false
	@State var manual: Bool = false
	var box: CGFloat { return radius * 2 + 34 }

	var body: some View {
		ZStack {
			Canvas { ctx, size in
				CombatStickView.paint(&ctx, size, Double(radius), Double(thumb.width), Double(thumb.height), down, manual)
			}
			.frame(width: box, height: box)
			if !down {
				Text(label).font(.pixel(13)).foregroundColor(Color.white.opacity(0.85))
			}
		}
		.frame(width: box, height: box)
		.contentShape(Rectangle())
		.gesture(stickGesture)
	}

	var stickGesture: some Gesture {
		DragGesture(minimumDistance: 0, coordinateSpace: .local)
			.onChanged { v in moved(v.location) }
			.onEnded { _ in released() }
	}

	func moved(_ p: CGPoint) {
		let r: Double = Double(radius)
		let c: Double = Double(box) * 0.5
		var dx: Double = Double(p.x) - c
		var dy: Double = Double(p.y) - c
		let len: Double = sqrt(dx * dx + dy * dy)
		if len > r {
			dx = dx / len * r
			dy = dy / len * r
		}
		thumb = CGSize(width: CGFloat(dx), height: CGFloat(dy))
		actState.stickAt(dx / r, dy / r)
		down = true
		manual = actState.manual
	}

	func released() {
		thumb = CGSize.zero
		down = false
		manual = false
		actState.stickReleased()
	}

	/// The dial: a ring with eight notches and the dead zone marked, an arrow toward the thumb while it
	/// aims by hand, and the thumb itself (amber while attacking)
	static func paint(_ ctx: inout GraphicsContext, _ size: CGSize, _ r: Double, _ tx: Double, _ ty: Double, _ down: Bool, _ manual: Bool) {
		let cx: Double = Double(size.width) * 0.5
		let cy: Double = Double(size.height) * 0.5
		let ring: Color = down ? Color(ui: 0xFFC850, alpha: 0.75) : Color(ui: 0xE0B060, alpha: 0.45)
		fillOval(&ctx, mkRect(cx - r, cy - r, r * 2.0, r * 2.0), Color(hex: 0x2A1A0C, alpha: 0.30))
		ctx.stroke(Path(ellipseIn: mkRect(cx - r, cy - r, r * 2.0, r * 2.0)), with: .color(ring), lineWidth: 3)
		let dz: Double = r * ActState.deadIn
		ctx.stroke(Path(ellipseIn: mkRect(cx - dz, cy - dz, dz * 2.0, dz * 2.0)), with: .color(Color.white.opacity(0.22)), lineWidth: 2)
		for k in 0..<8 {
			let a: Double = Double(k) * Double.pi / 4.0
			let c: Double = cos(a)
			let s: Double = sin(a)
			strokeLine(&ctx, cx + c * r * 0.80, cy + s * r * 0.80, cx + c * r * 0.95, cy + s * r * 0.95, Color.white.opacity(0.30), 2)
		}
		if manual {
			let len: Double = sqrt(tx * tx + ty * ty)
			if len > 1.0 {
				let ux: Double = tx / len
				let uy: Double = ty / len
				let arrow: Color = Color(ui: 0xFFE080, alpha: 0.9)
				strokeLine(&ctx, cx + ux * dz, cy + uy * dz, cx + ux * r * 0.78, cy + uy * r * 0.78, arrow, 4)
				var head: Path = Path()
				let bx: Double = cx + ux * r * 0.78
				let by: Double = cy + uy * r * 0.78
				head.move(to: mkPoint(cx + ux * r * 0.98, cy + uy * r * 0.98))
				head.addLine(to: mkPoint(bx - uy * 9.0, by + ux * 9.0))
				head.addLine(to: mkPoint(bx + uy * 9.0, by - ux * 9.0))
				head.closeSubpath()
				ctx.fill(head, with: .color(arrow))
			}
		}
		let tr: Double = 29.0
		let tc: Color = down ? Color(ui: 0xFFC850, alpha: 0.85) : Color.white.opacity(0.5)
		fillOval(&ctx, mkRect(cx + tx - tr, cy + ty - tr, tr * 2.0, tr * 2.0), tc)
		ctx.stroke(Path(ellipseIn: mkRect(cx + tx - tr, cy + ty - tr, tr * 2.0, tr * 2.0)), with: .color(Color.black.opacity(0.35)), lineWidth: 2)
	}
}

// MARK: - Vehicle checklist

struct VehicleHelpBox: View {
	let check: VehicleCheck
	var titleText: String {
		if check.ready { return joinText(check.title, " - READY") }
		return joinText(check.title, " - needs:")
	}
	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			OutlinedText(text: titleText, size: 13, color: pick(check.ready, 0x8CF07A, 0xFFE066))
			ForEach(0..<check.lines.count, id: \.self) { i in
				checkRow(i)
			}
			Text(verbatim: check.hint)
				.font(.pixel(10, .semibold))
				.foregroundColor(Color.white.opacity(0.75))
		}
		.padding(8)
		.background(PixelBox(color: Color(ui: 0x2A2A2E)).opacity(0.88))
		.frame(maxWidth: 320, alignment: .leading)
	}

	func checkRow(_ i: Int) -> some View {
		let ok: Bool = check.oks[i]
		let mark: String = ok ? "[x]" : "[ ]"
		return HStack(spacing: 5) {
			Text(verbatim: mark).font(.pixel(11)).foregroundColor(pick(ok, 0x8CF07A, 0xFF7060))
			Text(verbatim: check.lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
		}
	}
}

// MARK: - HUD

struct HUDView: View {
	let game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		VStack(spacing: 0) {
			topBar
			if !game.wxBanner.isEmpty { weatherBanner.padding(.top, 4) }
			if game.activeBoss != nil { bossBar.padding(.top, 4) }
			if let m = game.message {
				Text(m)
					.font(.pixel(14))
					.foregroundColor(Color.white)
					.multilineTextAlignment(.center)
					.padding(8)
					.background(PixelBox(color: Color(ui: 0x2E2E2E)).opacity(0.9))
					.padding(.top, 6)
					.frame(maxWidth: 560)
			}
			vehicleArea
			Spacer(minLength: 0)
			bottomArea
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
	}

	@ViewBuilder
	var vehicleArea: some View {
		if let v = game.vehicleHelpTarget {
			HStack {
				VehicleHelpBox(check: game.vehicleCheck(v))
				Spacer(minLength: 0)
			}
			.padding(.top, 6)
		} else if let tip = vehicleTip {
			HStack {
				Text(verbatim: tip)
					.font(.pixel(11, .bold))
					.foregroundColor(Color.white)
					.padding(8)
					.background(PixelBox(color: Color(ui: 0x2E2E2E)).opacity(0.85))
					.frame(maxWidth: 300, alignment: .leading)
				Spacer(minLength: 0)
			}
			.padding(.top, 6)
		}
	}

	var vehicleTip: String? {
		guard let it = game.heldItem else { return nil }
		if game.inVehicle != nil { return nil }
		switch it {
		case .gadget(let g):
			if isKit(g) { return "Tap open, flat ground near you to place it. Boats go on water." }
			return nil
		case .part:
			return "Place a Frame (car) or Hull Float (boat) on the ground first, then add parts to it. Kits in the Vehicles tab are quicker."
		default:
			return nil
		}
	}

	var topBar: some View {
		HStack(alignment: .top, spacing: 8) {
			statusBlock
			Spacer(minLength: 4)
			VStack(alignment: .trailing, spacing: 6) {
				HStack(spacing: 6) {
					SmallButton(title: "−") { zoom(-8) }
					SmallButton(title: "+") { zoom(8) }
					if game.gotMap || game.inv.total(.gadget(.treasureMap)) > 0 {
						SmallButton(title: "MAP", color: Color(ui: 0x9A7A3A)) { game.showMap = true }
					}
					SmallButton(title: "LOG", color: Color(ui: 0x7A5A2A)) { game.showJournal = true }
					if !game.testMod.isEmpty {
						SmallButton(title: "TEST", color: Color(ui: 0x2E8A8A)) { game.showModTest = true }
					}
					SmallButton(title: "DBG") { game.showDebug.toggle() }
					SmallButton(title: "II") { game.paused = true }
				}
				if game.settings.showCoords { infoBlock }
			}
		}
	}

	var statusBlock: some View {
		let art: Art = Art.shared
		return VStack(alignment: .leading, spacing: 3) {
			if game.isCreative {
				OutlinedText(text: "CREATIVE", size: 14)
			} else {
				IconRow(value: game.hp, perIcon: game.maxHP / 10.0, count: 10, full: art.heartFull, empty: art.heartEmpty)
				IconRow(value: game.hunger, perIcon: 2.0, count: 10, full: art.foodFull, empty: art.foodEmpty)
				if game.air < 9.99 {
					IconRow(value: game.air, perIcon: 1.0, count: 10, full: art.bubble, empty: art.heartEmpty, size: 14)
				}
				if game.totalDefense > 0 {
					HStack(spacing: 4) {
						art.shieldIcon.resizable().frame(width: 16, height: 16)
						OutlinedText(text: String(Int(game.totalDefense.rounded())), size: 12)
					}
				}
				if game.suit.worn { SuitBar(game: game, tick: hud.tick) }
			}
			if !game.activeEffects().isEmpty { EffectStrip(game: game, tick: hud.tick) }
			if let v = game.inVehicle { vehicleReadout(v) }
			if game.mode == .hardcore { OutlinedText(text: "HARDCORE", size: 11, color: Color(ui: 0xFF6060)) }
			if !game.testMod.isEmpty { OutlinedText(text: "MOD TEST · NOT SAVED", size: 11, color: Color(ui: 0x60E0FF)) }
		}
	}

	/// The flight instruments while flying, and a line about the guns and the autopilot
	@ViewBuilder
	func vehicleReadout(_ v: Vehicle) -> some View {
		if v.aero {
			let lines: [String] = game.flightReadout(v)
			ForEach(0..<lines.count, id: \.self) { (i: Int) in
				OutlinedText(text: lines[i], size: 12, color: lines[i] == "STALL!" ? Color(ui: 0xFF5050) : Color(ui: 0xB8F0FF))
			}
		}
		if let st = game.vehicleStatusLine(v) {
			OutlinedText(text: st, size: 11, color: Color(ui: 0xFFE080))
		}
	}

	var infoBlock: some View {
		let x: Int = Int(floor(game.pb.x))
		let y: Int = Int(floor(game.pb.y))
		var dayText: String = "Umbral Realm"
		if game.world.dim != .umbral {
			let dn: Int = Int(game.dayCount)
			let nt: String = game.isNight ? " · Night" : ""
			dayText = "Day \(dn)\(nt)"
		}
		return VStack(alignment: .trailing, spacing: 1) {
			OutlinedText(text: joinText("X ", String(x), "  Y ", String(y)), size: 11)
			OutlinedText(text: joinText(game.biomeHere.name, " · ", game.depthText), size: 11)
			OutlinedText(text: dayText, size: 11)
			weatherLine
			if let hint = game.wiringHint {
				OutlinedText(text: hint, size: 11, color: Color(ui: 0x9AF0E0))
			}
		}
	}

	/// The weather where the player is: a symbol, its name and the wind (and a barometer's reading
	/// while one is held)
	@ViewBuilder
	var weatherLine: some View {
		if game.world.dim == .overworld && game.settings.weatherOn {
			HStack(spacing: 4) {
				Art.shared.weatherIcon(game.weather.kind, game.wxHere.snow).resizable().frame(width: 16, height: 16)
				OutlinedText(text: weatherText, size: 11)
			}
			if case .gadget(.barometer)? = game.heldItem {
				OutlinedText(text: game.barometerReading(), size: 11, color: Color(ui: 0xE8D090))
			}
		}
	}

	var weatherText: String {
		let w: Double = game.wxHere.wind
		let name: String = game.weatherHereLabel
		if abs(w) < 3.0 { return name }
		return joinText(name, " · wind ", String(Int(abs(w).rounded())), w > 0 ? " →" : " ←")
	}

	var weatherBanner: some View {
		let warn: Bool = game.wxBannerLevel >= 2
		return Text(verbatim: game.wxBanner)
			.font(.pixel(13))
			.foregroundColor(Color.white)
			.multilineTextAlignment(.center)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(PixelBox(color: warn ? Color(ui: 0xA02020) : Color(ui: 0x8A6A1A)).opacity(0.92))
			.frame(maxWidth: 620)
	}

	var bossBar: some View {
		let fracD: Double = game.bossBarFrac * 356.0
		let barW: CGFloat = CGFloat(fracD)
		return VStack(spacing: 2) {
			OutlinedText(text: game.bossBarName, size: 14, color: Color(ui: 0xFFD060))
			ZStack(alignment: .leading) {
				Rectangle().fill(Color.black.opacity(0.75)).frame(width: 360, height: 14)
				Rectangle().fill(Color(hex: 0xC02828)).frame(width: barW, height: 10).padding(.leading, 2)
			}
			.overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 2))
		}
	}

	var bottomArea: some View {
		let swap: Bool = ThemeRT.swapSides
		return HStack(alignment: .bottom, spacing: 8) {
			if swap { actionSide } else { moveSide }
			Spacer(minLength: 0)
			VStack(spacing: 6) {
				contextButtons
				OutlinedText(text: game.selectedName, size: 12)
				hotbar
			}
			Spacer(minLength: 0)
			if swap { moveSide } else { actionSide }
		}
		.scaleEffect(ThemeRT.hudScale, anchor: .bottom)
		.opacity(ThemeRT.hudAlpha)
	}

	/// the walking stick
	@ViewBuilder
	var moveSide: some View {
		if game.settings.touchControls { StickView(game: game) }
	}

	/// JUMP, the weapon swap and the attack stick
	@ViewBuilder
	var actionSide: some View {
		if game.settings.touchControls {
			HStack(alignment: .bottom, spacing: 6) {
				VStack(alignment: .trailing, spacing: 8) {
					if let next = game.nextWeaponSlot(), let st = game.inv.slots[next] {
						WeaponSwapButton(stack: st) { game.cycleWeapon() }
					}
					HoldButton(label: "JUMP", size: 82, color: Color(ui: 0x4E8A3E)) { down in game.jumpHeld = down }
				}
				CombatStickView(label: game.useLabel)
			}
		}
	}

	var contextButtons: some View {
		HStack(spacing: 6) {
			if game.canToggleWall {
				SmallButton(title: game.wallMode ? "AS WALL" : "AS BLOCK", color: game.wallMode ? Color(ui: 0x6A5A8A) : Color(ui: 0x4E6A3E)) { game.toggleWallMode() }
			}
			if game.canBuildOnVehicle {
				SmallButton(title: game.vehicleBuild ? "ON VEHICLE" : "IN WORLD", color: game.vehicleBuild ? Color(ui: 0x2E7A8A) : Color(ui: 0x4E6A3E)) { game.toggleVehicleBuild() }
			}
			if game.inVehicle != nil { vehicleButtons }
			if game.vehicleNearby != nil {
				SmallButton(title: "DRIVE", color: Color(ui: 0x4E8A3E)) { game.driveNearby() }
				SmallButton(title: "PACK UP", color: Color(ui: 0x6A5A2A)) { game.packUpVehicle() }
			}
			if game.mounted != nil || game.inVehicle != nil {
				SmallButton(title: "DISMOUNT", color: Color(ui: 0xA03030)) { game.dismount() }
			}
			if let s = game.heldStack, case .gun(let gt) = s.item {
				if game.reloadT > 0 {
					OutlinedText(text: gt.isBoltThrower && gt.magazine == 1 ? "COCKING" : "RELOADING", size: 12, color: Color(ui: 0xFFE080))
				} else if gt == .stormRod {
					if s.extra < gt.magazine { OutlinedText(text: "CHARGING", size: 12, color: Color(ui: 0xB8E0FF)) }
				} else if s.extra < gt.magazine {
					SmallButton(title: "RELOAD", color: Color(ui: 0x6A5A2A)) { game.startReload() }
				}
			}
			if game.flying || game.noclip {
				HoldButton(label: "▼", size: 44) { down in game.downHeld = down }
			}
		}
	}

	/// While driving: turn round, and the autopilot's buttons when the vehicle has one
	@ViewBuilder
	var vehicleButtons: some View {
		SmallButton(title: "TURN", color: Color(ui: 0x3A6AA8)) { game.turnVehicle() }
		if let v = game.inVehicle, !v.joints.isEmpty { jointButtonRow }
		if let v = game.inVehicle, v.autopilots > 0 {
			SmallButton(title: "AUTO", color: v.auto == 0 ? Color(ui: 0x5A5A64) : Color(ui: 0x2E8A5A)) { game.cycleAutopilot() }
			SmallButton(title: "MARK", color: Color(ui: 0x6A5A2A)) { game.markWaypoint() }
			if !v.route.isEmpty {
				SmallButton(title: "CLEAR", color: Color(ui: 0x7A3A3A)) { game.clearRoute() }
			}
		}
	}

	/// The joints' buttons A, B and C (held), shown while driving a machine with joints
	var jointButtonRow: some View {
		HStack(spacing: 6) {
			HoldButton(label: "A", size: 46, color: Color(ui: 0x6A4A8A)) { (down: Bool) in game.jointButtons[0] = down }
			HoldButton(label: "B", size: 46, color: Color(ui: 0x4A6A8A)) { (down: Bool) in game.jointButtons[1] = down }
			HoldButton(label: "C", size: 46, color: Color(ui: 0x4A8A5A)) { (down: Bool) in game.jointButtons[2] = down }
		}
	}

	var hotbar: some View {
		HStack(spacing: 3) {
			ForEach(0..<Inventory.hotbarCount, id: \.self) { i in
				Button {
					game.setSel(i)
				} label: {
					SlotView(stack: game.inv.slots[i], selected: game.sel == i, size: 40)
				}
				.buttonStyle(.plain)
			}
			// the bag opens from the end of the hotbar (replaces the old BAG text button)
			Button {
				game.showInventory = true
				game.bumpHUD()
			} label: {
				ZStack {
					Rectangle().fill(Color(hex: 0x3E5A7A, alpha: 0.85))
					Art.shared.icon(.block(.chest)).resizable().frame(width: 26, height: 26)
					Text("BAG").font(.pixel(8)).foregroundColor(Color.white).offset(y: 14)
				}
				.frame(width: 40, height: 40)
				.overlay(Rectangle().stroke(Color(hex: 0xA0C0E0), lineWidth: 1))
			}
			.buttonStyle(.plain)
		}
	}

	func zoom(_ d: Int) {
		game.tilePx = clampI(game.tilePx + d, 16, 56)
		game.settings.tilePx = game.tilePx
		game.light.valid = false
		game.bumpHUD()
	}
}

// ===== u04_panels =====

// MARK: - Inventory, crafting, chests, creative palette

/// Where each slot sits on screen (in the panel's "inv" space), so a drag can find what it was dropped on.
/// Filled while the slots lay out; a plain reference box keeps it out of SwiftUI state updates.
final class SlotFrames: @unchecked Sendable {
	var map: [Game.SlotRef: CGRect] = [:]

	func target(at p: CGPoint) -> Game.SlotRef? {
		for (k, r) in map where r.contains(p) { return k }
		return nil
	}
}

/// Every item, with a search box and groups to narrow it down: the creative palette and the debug menu's
/// give. Tapping an item calls `tap`; the selected one is ringed.
struct ItemBrowser: View {
	let items: [Item]
	@Binding var search: String
	@Binding var group: Int
	var selected: Item? = nil
	var height: CGFloat = 300
	var tap: (Item) -> Void

	static let groups: [String] = ["ALL", "BLOCKS", "TOOLS", "WEAPONS", "ARMOR", "MATERIALS", "FOOD", "OTHER"]

	var body: some View {
		let list: [Item] = ItemBrowser.filter(items, search, group)
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 3)]
		return VStack(alignment: .leading, spacing: 6) {
			TextField("Search items by name", text: $search)
				.font(.pixel(13, .bold))
				.foregroundColor(Color.white)
				.padding(8)
				.background(Color.black.opacity(0.5))
			groupRow
			Text(verbatim: joinText(String(list.count), list.count == 1 ? " item" : " items")).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.6))
			ScrollView {
				LazyVGrid(columns: cols, spacing: 3) {
					ForEach(0..<list.count, id: \.self) { (i: Int) in self.cell(list[i]) }
				}
			}
			.frame(height: height)
		}
	}

	var groupRow: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 3) {
				ForEach(0..<4, id: \.self) { (i: Int) in self.groupButton(i) }
			}
			HStack(spacing: 3) {
				ForEach(4..<ItemBrowser.groups.count, id: \.self) { (i: Int) in self.groupButton(i) }
			}
		}
	}

	func groupButton(_ i: Int) -> some View {
		let on: Bool = group == i
		let col: Color = on ? Color(ui: 0x4E8A3E) : Color(ui: 0x555555)
		return SmallButton(title: ItemBrowser.groups[i], color: col) { self.group = i }
	}

	func cell(_ it: Item) -> some View {
		let on: Bool = selected == it
		return SlotView(stack: Stack(item: it, count: 1), selected: on, size: 40)
			.onTapGesture { self.tap(it) }
	}

	/// The items matching a search (by name) and a group (0: all)
	static func filter(_ items: [Item], _ search: String, _ group: Int) -> [Item] {
		let q: String = search.trimmingCharacters(in: .whitespaces).lowercased()
		var out: [Item] = []
		for it in items {
			if group > 0 && it.bagGroup != group - 1 { continue }
			if !q.isEmpty && !it.name.lowercased().contains(q) { continue }
			out.append(it)
		}
		return out
	}
}

struct InventoryPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var cat: RecipeCat = .basic
	@State var creativeTab: Bool = false
	@State var onlyCraftable: Bool = false
	/// the bag filter (ItemBrowser.groups; 0 shows everything)
	@State var bagGroup: Int = 0
	/// an item picked in the creative palette or the crafting list, to read about without taking it
	@State var infoItem: Item? = nil
	@State var infoRecipe: Int = -1
	@State var search: String = ""
	@State var paletteGroup: Int = 0
	// drag and drop
	@State var dragFrom: Game.SlotRef? = nil
	@State var dragPoint: CGPoint = .zero
	@State var hoverRef: Game.SlotRef? = nil
	@State var frames: SlotFrames = SlotFrames()

	var body: some View {
		ZStack(alignment: .topLeading) {
			VStack(spacing: 8) {
				header
				HStack(alignment: .top, spacing: 12) {
					leftColumn
					rightColumn
				}
			}
			.foregroundColor(Color.white)
			.padding(14)
			.background(PixelBox(color: Color(ui: 0x2C2C30)).opacity(0.97))
			// the stack being dragged follows the finger
			if let f = dragFrom, let s = game.stackAt(f) {
				SlotView(stack: s, size: 44)
					.opacity(0.9)
					.position(x: dragPoint.x, y: dragPoint.y)
					.allowsHitTesting(false)
			}
		}
		.coordinateSpace(name: "inv")
		.frame(maxWidth: 1000)
		.padding(10)
		.onAppear {
			switch game.craftStation {
			case .still: cat = .alchemy
			case .infuser: cat = .infusion
			case .assembly: cat = .exosuit
			default: break
			}
		}
	}

	/// A slot that can be tapped (pick up / place), long-pressed, hovered for info, and dragged
	func dragSlot(_ ref: Game.SlotRef, _ stack: Stack?, size: CGFloat, selected: Bool = false, tap: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
		let box: SlotFrames = frames
		let g: Game = game
		return SlotView(stack: stack, selected: selected, size: size)
			.background(GeometryReader { gp -> Color in
				box.map[ref] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.opacity(dragFrom == ref ? 0.35 : 1.0)
			.onTapGesture {
				hoverRef = ref
				tap()
			}
			.onLongPressGesture(minimumDuration: 0.35) { hold() }
			.onHover { inside in if inside { hoverRef = ref } }
			.gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("inv"))
				.onChanged { v in
					if dragFrom == nil {
						if g.carry != nil || g.stackAt(ref) == nil { return }
						dragFrom = ref
						hoverRef = ref
					}
					dragPoint = v.location
				}
				.onEnded { v in
					if let from = dragFrom {
						g.dragStack(from: from, to: box.target(at: v.location))
					}
					dragFrom = nil
				})
	}

	/// Drop zone: dragging a stack here throws it out into the world
	var dropZone: some View {
		let box: SlotFrames = frames
		let active: Bool = dragFrom != nil
		return Text(active ? "DROP HERE" : "DROP")
			.font(.pixel(11))
			.foregroundColor(Color.white.opacity(active ? 1.0 : 0.6))
			.frame(width: 84, height: 36)
			.background(Color(ui: active ? 0x7A3A2A : 0x3A2E2A).opacity(0.9))
			.overlay(Rectangle().stroke(Color(hex: 0xA06A2A), lineWidth: active ? 2 : 1))
			.background(GeometryReader { gp -> Color in
				box.map[.drop] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.onTapGesture { game.dropCarried() }
	}

	/// Name and details of the item picked in a list, else of the slot last touched or hovered
	var infoBox: some View {
		let s: Stack? = hoverRef.flatMap { game.stackAt($0) } ?? game.carry
		return VStack(alignment: .leading, spacing: 2) {
			if let it = infoItem {
				pickedInfo(it)
			} else if let st = s {
				Text(verbatim: st.count > 1 ? joinText(st.item.name, "  x", String(st.count)) : st.item.name).font(.pixel(12))
				Text(verbatim: st.item.infoLines.joined(separator: " · ")).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75))
				if !st.infusionNames.isEmpty {
					Text(verbatim: joinText("Infused: ", st.infusionNames.joined(separator: ", "))).font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xC07CFF))
				}
			} else {
				Text("Tap or hover an item to see what it does.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.55))
			}
		}
		.frame(maxWidth: 460, minHeight: 34, alignment: .leading)
		.padding(.horizontal, 6)
		.background(Color.black.opacity(0.25))
	}

	/// An item picked in the creative palette or the crafting list: what it is, and for a recipe what it
	/// takes (and how many of each the bag holds)
	func pickedInfo(_ it: Item) -> some View {
		let lines: String = it.infoLines.joined(separator: " · ")
		let need: String = recipeNeeds()
		return VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(verbatim: it.name).font(.pixel(12))
				Spacer()
				SmallButton(title: "OK") { self.infoItem = nil; self.infoRecipe = -1 }
			}
			if !lines.isEmpty { Text(verbatim: lines).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75)) }
			if !need.isEmpty { Text(verbatim: need).font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xFFE070)) }
		}
	}

	func recipeNeeds() -> String {
		guard infoRecipe >= 0, let r = RecipeBook.all.first(where: { $0.id == infoRecipe }) else { return "" }
		var parts: [String] = []
		for c in r.cost {
			parts.append(joinText(String(c.n), " ", c.item.name, " (have ", String(game.inv.total(c.item)), ")"))
		}
		var s: String = joinText("Needs: ", parts.joined(separator: ", "))
		if !game.recipeStationOK(r) { s = joinText(s, ". At a ", game.recipeStationName(r), ".") }
		return s
	}

	var titleText: String {
		if let p = game.openChest, game.isCargoSpot(p) { return "INVENTORY  ·  CARGO" }
		if let p = game.openChest, game.isPackSpot(p) { return "INVENTORY  ·  SUIT PACK" }
		if game.openChest != nil { return "INVENTORY  ·  CHEST" }
		return "INVENTORY"
	}

	var header: some View {
		HStack {
			Text(verbatim: titleText).font(.pixel(18))
			Spacer()
			if game.isCreative && game.openChest == nil {
				SmallButton(title: creativeTab ? "CRAFTING" : "ALL ITEMS", color: Color(ui: 0x3E6FAA)) { creativeTab.toggle() }
			}
			SmallButton(title: "SORT", color: Color(ui: 0x4E6A8A)) { game.sortBag() }
			SmallButton(title: "STACK", color: Color(ui: 0x4E6A8A)) { game.stackAll() }
			if game.openChest != nil {
				SmallButton(title: "QUICK STACK", color: Color(ui: 0x4E8A3E)) { game.quickStack() }
			}
			SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { close() }
		}
	}

	func close() {
		game.returnCarried()
		game.openChest = nil
		game.craftStation = .hand
		game.showInventory = false
		game.bumpHUD()
	}

	var leftColumn: some View {
		VStack(alignment: .leading, spacing: 8) {
			bagFilter
			HStack(alignment: .top, spacing: 10) {
				armorColumn
				VStack(spacing: 3) {
					ForEach(0..<4, id: \.self) { r in
						HStack(spacing: 3) {
							ForEach(0..<10, id: \.self) { c in
								invSlot(r * 10 + c)
							}
						}
					}
				}
			}
			carryBar
			infoBox
			Text(verbatim: holdHint)
				.font(.pixel(10, .semibold))
				.foregroundColor(Color.white.opacity(0.7))
		}
	}

	/// Show only one kind of item in the bag (the others dim, so nothing moves)
	var bagFilter: some View {
		HStack(spacing: 3) {
			ForEach(0..<ItemBrowser.groups.count, id: \.self) { (i: Int) in self.filterChip(i) }
		}
	}

	func filterChip(_ i: Int) -> some View {
		let on: Bool = bagGroup == i
		let col: Color = on ? Color(ui: 0x4E8A3E) : Color(ui: 0x4A4A50)
		return Button(action: { self.bagGroup = i }) {
			Text(verbatim: ItemBrowser.groups[i]).font(.pixel(9, .bold)).foregroundColor(Color.white)
				.padding(.horizontal, 5).padding(.vertical, 5)
				.background(col)
		}
		.buttonStyle(.plain)
	}

	/// whether a slot's stack is outside the bag filter (it is drawn dim)
	func filteredOut(_ s: Stack?) -> Bool {
		guard bagGroup > 0, let st = s else { return false }
		return st.item.bagGroup != bagGroup - 1
	}

	var holdHint: String {
		let tail: String = game.openChest != nil ? "move to chest." : "split stack, equip armor."
		return joinText("Drag to move, swap or stack (onto DROP to throw away). Tap: pick up / place. Hold: ", tail)
	}

	func invSlot(_ i: Int) -> some View {
		let isHot: Bool = i < Inventory.hotbarCount
		let selected: Bool = isHot && game.sel == i
		let ring: Color = isHot ? Color(ui: 0xFFE070, alpha: 0.35) : Color.clear
		let dimmed: Bool = filteredOut(game.inv.slots[i])
		return dragSlot(.inv(i), game.inv.slots[i], size: 40, selected: selected, tap: { game.tapSlot(i) }, hold: { longPress(i) })
			.overlay(Rectangle().stroke(ring, lineWidth: 1))
			.opacity(dimmed ? 0.25 : 1.0)
	}

	func longPress(_ i: Int) {
		if let p = game.openChest {
			game.chestStore(p.x, p.y, i)
			return
		}
		if let s = game.inv.slots[i] {
			switch s.item {
			case .armor, .gear:
				game.quickEquip(i)
				return
			default: break
			}
		}
		game.splitSlot(i)
	}

	var armorColumn: some View {
		let names: [String] = ["Head", "Body", "Legs", "Gear", "Gear"]
		let n: Int = min(names.count, game.inv.armor.count)
		return HStack(alignment: .top, spacing: 4) {
			VStack(spacing: 4) {
				ForEach(0..<min(3, n), id: \.self) { i in
					equipSlot(i, names[i])
				}
				HStack(spacing: 2) {
					Art.shared.shieldIcon.resizable().frame(width: 14, height: 14)
					Text(String(Int(game.inv.defense.rounded()))).font(.pixel(11))
				}
			}
			VStack(spacing: 4) {
				ForEach(min(3, n)..<n, id: \.self) { i in
					equipSlot(i, names[i])
				}
			}
		}
	}

	func equipSlot(_ i: Int, _ name: String) -> some View {
		VStack(spacing: 1) {
			dragSlot(.armor(i), game.inv.armor[i], size: 40, tap: { game.tapArmorSlot(i) }, hold: {})
			Text(name).font(.pixel(9, .bold)).foregroundColor(Color.white.opacity(0.7))
		}
	}

	var carryBar: some View {
		HStack(spacing: 8) {
			if let c = game.carry {
				SlotView(stack: c, size: 36)
				Text(verbatim: joinText("Holding ", c.item.name)).font(.pixel(12))
				Spacer()
				SmallButton(title: "PUT BACK") { game.returnCarried() }
			} else {
				Text("Hand empty").font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.6))
				Spacer()
			}
			if game.isCreative { returnZone }
			dropZone
		}
		.frame(height: 40)
	}

	/// Creative mode: drag a stack here (or tap while holding one) to put it back in the creative menu
	var returnZone: some View {
		let box: SlotFrames = frames
		let active: Bool = dragFrom != nil
		return Text(active ? "RETURN HERE" : "RETURN")
			.font(.pixel(11))
			.foregroundColor(Color.white.opacity(active ? 1.0 : 0.6))
			.frame(width: 96, height: 36)
			.background(Color(ui: active ? 0x2A4A7A : 0x2A344A).opacity(0.9))
			.overlay(Rectangle().stroke(Color(hex: 0x5A8AD0), lineWidth: active ? 2 : 1))
			.background(GeometryReader { gp -> Color in
				box.map[.trash] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.onTapGesture { game.discardCarried() }
	}

	@ViewBuilder
	var rightColumn: some View {
		if let p = game.openChest {
			chestGrid(p.x, p.y)
		} else if creativeTab && game.isCreative {
			creativePalette
		} else {
			craftingList
		}
	}

	var creativePalette: some View {
		let items: [Item] = game.creativeItems()
		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				Text("ALL ITEMS").font(.pixel(15))
				Spacer()
				if let it = infoItem {
					SmallButton(title: "TAKE 1", color: Color(ui: 0x4E8A3E)) { game.giveItem(it, 1, extra: game.gunLoad(it)) }
					SmallButton(title: "TAKE STACK", color: Color(ui: 0x4E8A3E)) { game.creativeGive(it) }
				}
			}
			Text("Tap an item to read about it, tap it again to take a stack. Put things back with RETURN.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
			ItemBrowser(items: items, search: $search, group: $paletteGroup, selected: infoItem, height: 260, tap: { (it: Item) in self.paletteTap(it) })
		}
		.frame(minWidth: 280, maxWidth: 420)
	}

	func paletteTap(_ it: Item) {
		if infoItem == it {
			game.creativeGive(it)
		} else {
			infoItem = it
			infoRecipe = -1
		}
	}

	var stationText: String {
		var s: [String] = ["Hand"]
		if game.stationAvailable(.bench) { s.append("Workbench") }
		if game.stationAvailable(.furnace) { s.append("Furnace") }
		else if game.stationAvailable(.campfire) { s.append("Campfire") }
		for st in [Station.anvil, .tinker, .forge] where game.stationAvailable(st) { s.append(st.name) }
		return "Near: " + s.joined(separator: ", ")
	}

	func visibleRecipes() -> [Recipe] {
		var out: [Recipe] = []
		for r in RecipeBook.all {
			if r.cat != cat { continue }
			if onlyCraftable && !game.canCraft(r) { continue }
			out.append(r)
		}
		return out
	}

	/// A crafting row with what the bag holds of each ingredient worked out here: the row redraws as soon
	/// as the bag changes (pick up, use, craft, drop, move)
	func recipeRow(_ r: Recipe) -> RecipeRow {
		let rid: Int = r.id
		var row: RecipeRow = RecipeRow.live(game, r)
		row.picked = infoRecipe == rid
		row.info = {
			self.infoItem = r.out
			self.infoRecipe = rid
		}
		return row
	}

	func catButton(_ c: RecipeCat) -> some View {
		let col: Color = pick(c == cat, 0x4E8A3E, 0x555555)
		return SmallButton(title: c.name, color: col) { cat = c }
	}

	var craftingList: some View {
		let list: [Recipe] = visibleRecipes()
		return VStack(alignment: .leading, spacing: 6) {
			Text("CRAFTING").font(.pixel(15))
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 4) {
					ForEach(RecipeCat.allCases.filter { $0 != .mods || ModRuntime.shared.recipes.contains { r in r.cat == .mods } }, id: \.self) { c in
						catButton(c)
					}
				}
			}
			HStack {
				Text(stationText).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75))
				Spacer()
				SmallButton(title: onlyCraftable ? "CAN MAKE" : "SHOW ALL") { onlyCraftable.toggle() }
			}
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 4) {
					ForEach(list) { (r: Recipe) in self.recipeRow(r) }
				}
			}
			.frame(maxHeight: 330)
		}
		.frame(minWidth: 300, maxWidth: 440)
	}
}

/// One recipe in the crafting list. What the bag holds of each ingredient, and whether it can be made,
/// come in from the panel as plain values, so the row redraws whenever they change.
struct RecipeRow: View {
	let game: Game
	let recipe: Recipe
	let have: [Int]
	let ok: Bool
	let stationOK: Bool
	var picked: Bool = false
	var info: () -> Void = {}

	/// A row with what the bag holds worked out now
	static func live(_ game: Game, _ r: Recipe) -> RecipeRow {
		var have: [Int] = []
		for c in r.cost { have.append(game.inv.total(c.item)) }
		return RecipeRow(game: game, recipe: r, have: have, ok: game.canCraft(r), stationOK: game.recipeStationOK(r))
	}

	var body: some View {
		return HStack(spacing: 6) {
			SlotView(stack: Stack(item: recipe.out, count: recipe.outCount), selected: picked, size: 34)
				.onTapGesture { self.info() }
			VStack(alignment: .leading, spacing: 2) {
				Text(recipe.out.name).font(.pixel(12)).lineLimit(1)
				HStack(spacing: 4) {
					ForEach(0..<recipe.cost.count, id: \.self) { (k: Int) in
						self.costView(recipe.cost[k], k < have.count ? have[k] : 0)
					}
				}
				if !stationOK {
					Text(verbatim: joinText("Needs ", game.recipeStationName(recipe))).font(.pixel(9, .bold)).foregroundColor(Color(ui: 0xFF8A60))
				}
			}
			Spacer(minLength: 2)
			makeButton(ok)
		}
		.padding(4)
		.background(Color.black.opacity(0.25))
	}

	func makeButton(_ ok: Bool) -> some View {
		let col: Color = pick(ok, 0x4E8A3E, 0x444444)
		let op: Double = ok ? 1.0 : 0.6
		return SmallButton(title: "MAKE", color: col) { game.craft(recipe) }.opacity(op)
	}

	/// An ingredient: its icon, then what the bag holds out of what it takes ("3/5")
	func costView(_ c: CostLine, _ held: Int) -> some View {
		let enough: Bool = held >= c.n || game.isCreative
		let text: String = joinText(String(min(held, 999)), "/", String(c.n))
		return HStack(spacing: 1) {
			Art.shared.icon(c.item).resizable().frame(width: 16, height: 16)
			Text(verbatim: text).font(.pixel(10)).foregroundColor(pick(enough, 0xFFFFFF, 0xFF6060))
		}
	}
}

/// The open chest, shown beside the bag; its slots take part in drag and drop like the bag's
extension InventoryPanel {
	func chestGrid(_ cx: Int, _ cy: Int) -> some View {
		let items: [Stack] = game.world.chestItems(cx, cy)
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("CHEST").font(.pixel(15))
				Spacer()
				SmallButton(title: "TAKE ALL", color: Color(ui: 0x4E8A3E)) { takeAll(cx, cy) }
			}
			VStack(spacing: 3) {
				ForEach(0..<3, id: \.self) { r in
					HStack(spacing: 3) {
						ForEach(0..<9, id: \.self) { c in
							chestSlot(cx, cy, r * 9 + c, items)
						}
					}
				}
			}
			Text("Drag between chest and bag. Tap: take / put the held stack. Hold: move into your bag.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
		}
	}

	func chestSlot(_ cx: Int, _ cy: Int, _ i: Int, _ items: [Stack]) -> some View {
		let s: Stack? = i < items.count ? items[i] : nil
		let g: Game = game
		return dragSlot(.chest(i), s, size: 40, tap: { g.chestTapSlot(cx, cy, i) }, hold: { g.chestQuickMove(cx, cy, i) })
	}

	func takeAll(_ cx: Int, _ cy: Int) {
		var n: Int = 0
		while n < 30 {
			let items: [Stack] = game.world.chestItems(cx, cy)
			if items.isEmpty { break }
			let before: Int = items.count
			game.chestQuickMove(cx, cy, 0)
			if game.world.chestItems(cx, cy).count >= before { break }
			n += 1
		}
	}
}

// MARK: - Treasure map


// MARK: - Journal panel

let parchment: UInt32 = 0xE8D4A0
let parchmentInk: UInt32 = 0x3A2410

struct JournalPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var tab: Int = 0
	var body: some View {
		let ink: Color = Color(ui: parchmentInk)
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 6) {
				Text("JOURNAL").font(.pixel(18)).foregroundColor(Color(ui: 0x4A2A10))
				Spacer()
				tabButton(0, "GOALS")
				tabButton(1, "PLACES")
				tabButton(2, "LORE")
				tabButton(3, "WEATHER")
				SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { game.showJournal = false }
			}
			ScrollView {
				VStack(alignment: .leading, spacing: 8) {
					switch tab {
					case 0: aims(ink)
					case 1: places(ink)
					case 2: lore(ink)
					default: WeatherJournalPage(game: game, ink: ink)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(maxHeight: 380)
		}
		.padding(16)
		.background(Color(ui: parchment))
		.overlay(Rectangle().stroke(Color(hex: 0x5A3A1A), lineWidth: 4))
		.frame(maxWidth: 820)
		.padding(16)
	}

	func tabButton(_ i: Int, _ title: String) -> some View {
		SmallButton(title: title, color: i == tab ? Color(ui: 0x7A5A2A) : Color(ui: 0xA8906C)) { tab = i }
	}

	func aims(_ ink: Color) -> some View {
		let list: [JournalAim] = game.journalAims()
		return VStack(alignment: .leading, spacing: 7) {
			ForEach(0..<list.count, id: \.self) { i in
				HStack(alignment: .top, spacing: 8) {
					Text(list[i].done ? "✓" : "○").font(.pixel(14)).foregroundColor(list[i].done ? Color(ui: 0x2A6A2A) : ink)
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: list[i].title).font(.pixel(13)).foregroundColor(list[i].done ? Color(ui: 0x6A5A40) : ink)
						if !list[i].done {
							Text(verbatim: list[i].hint).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x6A4A2A))
						}
					}
				}
			}
		}
	}

	func places(_ ink: Color) -> some View {
		let ps: [JournalPlace] = game.journal.places
		return VStack(alignment: .leading, spacing: 6) {
			if ps.isEmpty {
				Text("Nothing yet. The world is wide: ruins, old mines and stranger places are out there.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<ps.count, id: \.self) { i in
				HStack {
					Text(verbatim: ps[i].name).font(.pixel(13)).foregroundColor(ink)
					Spacer()
					Text(verbatim: placeWhere(ps[i])).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x6A4A2A))
				}
			}
		}
	}

	func placeWhere(_ p: JournalPlace) -> String {
		let start: Int = game.gen.spawnX
		let d: Int = p.x - start
		let side: String = abs(d) < 30 ? "by your first camp" : (roughDistance(abs(d)) + (d > 0 ? " east" : " west") + " of your start")
		return (p.dim == 1 ? "Umbral, " : "") + side + ", day " + String(p.day)
	}

	func lore(_ ink: Color) -> some View {
		let keys: [String] = game.journal.lore.filter { !$0.hasPrefix("wx.") }
		return VStack(alignment: .leading, spacing: 10) {
			if keys.isEmpty {
				Text("Places you find will tell you something. Their stories collect here.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<keys.count, id: \.self) { i in
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: loreEntry(keys[i]).0).font(.pixel(13)).foregroundColor(ink)
					Text(verbatim: loreEntry(keys[i]).1).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x5A3A1A))
				}
			}
		}
	}
}

struct MapPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		let map: TreasureMap = game.treasureMap()
		return VStack(spacing: 8) {
			HStack {
				Text("TREASURE MAP").font(.pixel(18)).foregroundColor(Color(ui: 0x4A2A10))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { game.showMap = false }
			}
			Canvas { ctx, size in
				MapDrawer.draw(&ctx, size, map, game)
			}
			.frame(height: 260)
			.overlay(Rectangle().stroke(Color(hex: 0x7A5A2A), lineWidth: 3))
			VStack(alignment: .leading, spacing: 4) {
				ForEach(0..<map.clues.count, id: \.self) { i in
					Text(verbatim: joinText("• ", map.clues[i])).font(.pixel(12, .bold)).foregroundColor(Color(ui: 0x3A2410))
				}
				if game.inv.total(.gadget(.portalKey)) > 0 && game.world.dim == .overworld {
					Text(verbatim: joinText("Key: ", game.portalHintText(game.portalHintLevel())))
						.font(.pixel(12, .heavy)).foregroundColor(Color(ui: 0x6A2AB0))
				}
				if game.portalOpened {
					Text("The gate has been opened.").font(.pixel(12, .heavy)).foregroundColor(Color(ui: 0x2A6A2A))
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(16)
		.background(Color(ui: 0xE8D4A0))
		.overlay(Rectangle().stroke(Color(hex: 0x5A3A1A), lineWidth: 4))
		.frame(maxWidth: 820)
		.padding(16)
	}
}

enum MapDrawer {
	static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ m: TreasureMap, _ g: Game) {
		let W: Double = Double(size.width)
		let Hh: Double = Double(size.height)
		let span: Double = Double(max(1, m.x1 - m.x0))
		let yTop: Double = 20.0
		let yBot: Double = Double(m.worldH) - 40.0
		let x0: Double = Double(m.x0)
		func mx(_ x: Double) -> Double {
			let d: Double = x - x0
			return d / span * W
		}
		func my(_ y: Double) -> Double {
			let d: Double = y - yTop
			let r: Double = yBot - yTop
			return d / r * Hh
		}
		fillRect(&ctx, mkRect(0, 0, W, Hh), Color(hex: 0xF0E0B4))
		let n: Int = m.heights.count
		if n == 0 { return }
		let nD: Double = Double(n)
		let colW: Double = max(1.0, W / nD + 1.0)
		let seaY: Double = my(Double(WorldGen.sea))
		let deepY: Double = my(330.0)
		let water: Color = Color(ui: 0x7AA4C8)
		let soil: Color = Color(ui: 0xB89868)
		let rock: Color = Color(ui: 0xA8906C)
		let deep: Color = Color(ui: 0x988060)
		for i in 0..<n {
			let x: Double = Double(i) / nD * W
			let hD: Double = Double(m.heights[i])
			let b: Biome = m.biomes[i]
			let top: Double = my(hD)
			let soilEnd: Double = my(hD + 30.0)
			if b == .ocean {
				fillRect(&ctx, mkRect(x, seaY, colW, max(0.0, top - seaY)), water)
			}
			let surf: Color = rgbColor(mixRGB(biomeMapColor(b), 0xE8D4A0, 0.25))
			fillRect(&ctx, mkRect(x, top, colW, 4.0), surf)
			let soilTop: Double = top + 4.0
			fillRect(&ctx, mkRect(x, soilTop, colW, max(0.0, soilEnd - soilTop)), soil)
			fillRect(&ctx, mkRect(x, soilEnd, colW, max(0.0, deepY - soilEnd)), rock)
			fillRect(&ctx, mkRect(x, deepY, colW, max(0.0, Hh - deepY)), deep)
		}
		// depth lines
		let dash: StrokeStyle = StrokeStyle(lineWidth: 1, dash: [3, 5])
		let lineCol: Color = Color(ui: 0x7A5A3A, alpha: 0.35)
		for d in [200.0, 330.0, 450.0] {
			let y: Double = my(d)
			var p: Path = Path()
			p.move(to: mkPoint(0, y))
			p.addLine(to: mkPoint(W, y))
			ctx.stroke(p, with: .color(lineCol), style: dash)
		}
		// markers
		let stepN: Int = max(1, m.step)
		for mk in m.markers {
			let x: Double = mx(Double(mk.x))
			let rel: Int = mk.x - m.x0
			let idxRaw: Int = rel / stepN
			let idx: Int = clampI(idxRaw, 0, n - 1)
			let y: Double = my(Double(m.heights[idx])) - 10.0
			var sym: String = "●"
			var col: Color = Color(ui: 0x3A2410)
			switch mk.kind {
			case 0:
				sym = "⌂"
				col = Color(hex: 0x2A6A2A)
			case 1:
				sym = "☠"
				col = Color(hex: 0x8A2A1A)
			case 2:
				sym = "☠"
				col = Color(hex: 0x5A3A8A)
			case 5:
				sym = "▼"
				col = Color(hex: 0x7A4A20)
			default:
				sym = "▲"
				col = Color(hex: 0x5A5A5A)
			}
			drawLabel(&ctx, sym, x, y, 16, col)
			if mk.kind <= 2 { drawLabel(&ctx, mk.label, x, y - 14.0, 9, col) }
		}
		// the dashed ring (the gate is somewhere inside)
		let rx: Double = Double(m.ringRX) / span * W
		let ry: Double = Double(m.ringRY) / (yBot - yTop) * Hh
		let cx: Double = mx(Double(m.ringX))
		let cy: Double = my(Double(m.ringY))
		let ring: CGRect = mkRect(cx - rx, cy - ry, rx * 2.0, ry * 2.0)
		let ringStyle: StrokeStyle = StrokeStyle(lineWidth: 3, dash: [8, 6])
		ctx.stroke(Path(ellipseIn: ring), with: .color(Color(hex: 0xC02020)), style: ringStyle)
		drawLabel(&ctx, "?", cx, cy, 22, Color(hex: 0xC02020))
		// you are here
		if g.world.dim == .overworld {
			let px: Double = g.pb.x
			if px >= x0 && px <= Double(m.x1) {
				let ux: Double = mx(px)
				let uy: Double = my(g.pb.y)
				fillOval(&ctx, mkRect(ux - 5.0, uy - 5.0, 10, 10), Color(hex: 0x2050D0))
				drawLabel(&ctx, "YOU", ux, uy - 12.0, 9, Color(hex: 0x2050D0))
			}
		}
		drawLabel(&ctx, "W  <-  -> E", W - 60.0, 14, 11, Color(hex: 0x5A3A1A))
	}
}

// MARK: - Pause, death

struct PauseView: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var worldLine: String {
		let kind: String = game.gen.infinite ? " · Infinite" : " · Classic"
		return joinText(game.worldName, " · ", game.mode.title, kind, game.gen.options.flat ? " · Flat" : "")
	}
	var quit: () -> Void
	@State var savedNote: String = ""
	var body: some View {
		ZStack {
			Color.black.opacity(0.6).ignoresSafeArea()
			// scrolls on short screens now that the camera options live here too
			ScrollView {
			VStack(spacing: 12) {
				Text("PAUSED").font(.pixel(30)).foregroundColor(Color.white)
				Text(verbatim: worldLine)
					.font(.pixel(12, .bold)).foregroundColor(Color.white.opacity(0.8))
				PixelButton(title: "RESUME", color: Color(ui: 0x4E8A3E)) {
					// settings changed here are kept on the device straight away
					SettingsStore.save(game.settings)
					game.paused = false
				}
				if game.testMod.isEmpty {
					PixelButton(title: "SAVE GAME", color: Color(ui: 0x3E6FAA)) {
						savedNote = game.saveNow() ? "Saved!" : "Could not save."
					}
				} else {
					Text("A mod test world: nothing is saved.").font(.pixel(12, .bold)).foregroundColor(Color(ui: 0x60E0FF))
					PixelButton(title: "TEST TOOLS", color: Color(ui: 0x2E8A8A)) {
						game.paused = false
						game.showModTest = true
					}
				}
				PixelButton(title: "CAPTURE STRUCTURE", color: Color(ui: 0x2E8A8A)) {
					game.paused = false
					game.startCapture()
				}
				toggles
				CameraSettingsSection(settings: settingsBinding, onChange: { game.tilePx = game.settings.tilePx })
				WeatherSettingsSection(settings: settingsBinding, onChange: { game.bumpHUD() })
				NightSettingsSection(settings: settingsBinding)
				PixelButton(title: game.testMod.isEmpty ? "SAVE & QUIT" : "EXIT TEST", color: Color(ui: 0xA03030)) { quit() }
				if !savedNote.isEmpty { Text(savedNote).font(.pixel(12)).foregroundColor(Color.white) }
			}
			.frame(maxWidth: 340)
			.padding()
			}
		}
	}

	var settingsBinding: Binding<Settings> {
		let g: Game = game
		return Binding<Settings>(get: { g.settings }, set: { v in
			g.settings = v
			g.bumpHUD()
		})
	}

	/// A toggle binding that also refreshes this screen (the game is paused, so nothing else would)
	func setting(_ kp: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
		let g: Game = game
		return Binding<Bool>(get: { g.settings[keyPath: kp] }, set: { v in
			g.settings[keyPath: kp] = v
			g.light.valid = false
			g.bumpHUD()
		})
	}

	var toggles: some View {
		VStack(spacing: 8) {
			Toggle("Touch controls", isOn: setting(\.touchControls))
			Toggle("Smooth lighting", isOn: setting(\.smoothLight))
			Toggle("Show coordinates", isOn: setting(\.showCoords))
			Toggle("60 FPS (off = 30, smoother on older iPads)", isOn: setting(\.fps60))
			Toggle("Show FPS counter", isOn: setting(\.showFPS))
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}
}

struct DeathView: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var quit: () -> Void
	var deathTitle: String {
		if game.mode == .hardcore { return "GAME OVER" }
		return "YOU DIED"
	}
	var body: some View {
		ZStack {
			Color(ui: 0x700000, alpha: 0.45).ignoresSafeArea()
			VStack(spacing: 12) {
				Text(verbatim: deathTitle).font(.pixel(34)).foregroundColor(Color.white)
					.shadow(color: Color.black, radius: 0, x: 3, y: 3)
				Text(verbatim: joinText("Kills: ", String(game.kills), "   Days: ", String(game.dayCount))).font(.pixel(14)).foregroundColor(Color.white)
				if game.mode == .hardcore {
					Text("This hardcore world has been deleted.").font(.pixel(12, .bold)).foregroundColor(Color.white)
				} else {
					PixelButton(title: "RESPAWN", color: Color(ui: 0x4E8A3E)) { game.respawn() }
				}
				PixelButton(title: "MAIN MENU", color: Color(ui: 0xA03030)) { quit() }
			}
			.frame(maxWidth: 320)
			.padding()
		}
	}
}

// MARK: - Debug menu

struct DebugPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var confirmDelete: Bool = false
	@State var includeVehicles: Bool = false
	@State var tpX: String = ""
	@State var tpY: String = ""
	@State var showPerf: Bool = true
	@State var showSystems: Bool = false
	@State var showWorld: Bool = false
	@State var showGive: Bool = false
	@State var giveSearch: String = ""
	@State var giveGroup: Int = 0
	@State var giveItem: Item? = nil
	@State var giveCount: Int = 1
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("DEBUG").font(.pixel(16)).foregroundColor(Color(ui: 0xFFE066))
					Spacer()
					SmallButton(title: "X", color: Color(ui: 0xA03030)) { game.showDebug = false }
				}
				stats
				toggles
				VStack(alignment: .leading, spacing: 4) {
					Text(verbatim: joinText("Speed x", String(format: "%.1f", game.speedMult))).font(.pixel(11, .semibold))
					Slider(value: $game.speedMult, in: 0.5...4.0, step: 0.5)
				}
				actions
				entitySection
				multiplierSection
				hazardSection
				weatherSection
				nightSection
				powerSection
				if showPerf { perfSection }
				SmallButton(title: showSystems ? "Hide systems" : "Systems...") { showSystems.toggle() }
				if showSystems { systemsSection }
				SmallButton(title: showWorld ? "Hide worldgen" : "Worldgen...") { showWorld.toggle() }
				if showWorld { worldSection }
				SmallButton(title: showGive ? "Hide give item" : "Give item...") { showGive.toggle() }
				if showGive { giveSection }
				section("SPAWN MOB")
				spawnGrid
			}
			.font(.pixel(12, .bold))
			.foregroundColor(Color.white)
			.padding(12)
		}
		.background(PixelBox(color: Color(ui: 0x1E1E1E)).opacity(0.94))
	}

	static let giveCounts: [Int] = [1, 10, 64, 100, 500]

	/// Any item of the game or of the world's mods, found by name or group, as many as wanted
	var giveSection: some View {
		let items: [Item] = game.creativeItems()
		let title: String = giveItem.map { joinText("GIVE ", String(giveCount), " ", $0.name) } ?? "Pick an item"
		return VStack(alignment: .leading, spacing: 6) {
			section("GIVE ITEM")
			ItemBrowser(items: items, search: $giveSearch, group: $giveGroup, selected: giveItem, height: 220, tap: { (it: Item) in self.giveItem = it })
			HStack(spacing: 4) {
				ForEach(0..<DebugPanel.giveCounts.count, id: \.self) { (i: Int) in self.countButton(DebugPanel.giveCounts[i]) }
			}
			SmallButton(title: title, color: Color(ui: 0x4E8A3E)) {
				if let it = self.giveItem { self.game.debugGive(it, self.giveCount) }
			}
		}
	}

	func countButton(_ n: Int) -> some View {
		let on: Bool = giveCount == n
		return SmallButton(title: joinText("x", String(n)), color: on ? Color(ui: 0x4E8A3E) : Color(ui: 0x555555)) { self.giveCount = n }
	}

	var actions: some View {
		VStack(alignment: .leading, spacing: 8) {
			section("TIME")
			HStack(spacing: 6) {
				SmallButton(title: "Dawn") { game.debugSetTime(0.0) }
				SmallButton(title: "Noon") { game.debugSetTime(0.25) }
				SmallButton(title: "Dusk") { game.debugSetTime(0.5) }
				SmallButton(title: "Night") { game.debugSetTime(0.75) }
			}
			section("PLAYER")
			HStack(spacing: 6) {
				SmallButton(title: "Heal") { game.hp = game.maxHP; game.hunger = 20; game.air = 10; game.bumpHUD() }
				SmallButton(title: "Give kit") { game.debugGiveKit() }
				SmallButton(title: "Kill hostiles") { game.debugKillHostiles() }
			}
			section("TELEPORT")
			VStack(alignment: .leading, spacing: 6) {
				HStack(spacing: 6) {
					SmallButton(title: "Spawn") { game.debugTeleport(game.spawnX, game.spawnY) }
					SmallButton(title: "Surface") { game.debugToSurface() }
					SmallButton(title: "Portal") { game.debugToPortal() }
				}
				HStack(spacing: 6) {
					SmallButton(title: "Bear den") { game.debugToLair(.bear) }
					SmallButton(title: "Rex nest") { game.debugToLair(.rex) }
					SmallButton(title: "Other realm", color: Color(ui: 0x6A3AA0)) { game.debugSwitchDimension() }
				}
				HStack(spacing: 6) {
					SmallButton(title: "Up 20") { game.pb.y -= 20; game.pb.vy = 0; game.fallPeak = 0 }
					SmallButton(title: "Down 20") { game.pb.y += 20; game.pb.vy = 0; game.fallPeak = 0 }
					SmallButton(title: "→ 200") { game.debugTeleport(game.pb.x + 200, game.pb.y) }
				}
				HStack(spacing: 6) {
					TextField("X", text: $tpX).frame(width: 64).padding(3).background(Color.white.opacity(0.15))
					TextField("Y", text: $tpY).frame(width: 64).padding(3).background(Color.white.opacity(0.15))
					SmallButton(title: "Go") {
						if let x = Double(tpX.trimmingCharacters(in: .whitespaces)) {
							let y: Double = Double(tpY.trimmingCharacters(in: .whitespaces)) ?? game.pb.y
							game.debugTeleport(x, y)
						}
					}
				}
			}
		}
	}

	var entitySection: some View {
		let c: Game.EntityCounts = game.entityCounts()
		return VStack(alignment: .leading, spacing: 6) {
			section("ENTITIES")
			Text(verbatim: joinText("Hostile ", String(c.hostile), "  Passive ", String(c.passive), "  Bosses ", String(c.bosses), "  Dying ", String(c.dying)))
				.font(.pixel(10, .semibold))
			Text(verbatim: joinText("Shots ", String(c.projectiles), "  Drops ", String(c.drops), "  Falling ", String(c.falling), "  FX ", String(c.particles)))
				.font(.pixel(10, .semibold))
			Text(verbatim: joinText("Vehicles ", String(c.vehicles), "  Ships ", String(c.ships)))
				.font(.pixel(10, .semibold))
			HStack(spacing: 6) {
				SmallButton(title: "Select at cursor") { game.debugSelectAtCursor() }
				if game.debugSelected != nil {
					SmallButton(title: "Remove", color: Color(ui: 0xA03030)) { game.debugRemoveSelected() }
				}
			}
			if let m = game.debugSelected {
				Text(verbatim: joinText(m.def.name, " #", String(m.id), String(format: "  HP %.0f/%.0f  ", m.hp, m.maxHP), String(format: "x %.1f y %.1f", m.b.x, m.b.y)))
					.font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xA0E0FF))
				HStack(spacing: 6) {
					SmallButton(title: "Heal") { m.hp = m.maxHP; game.bumpHUD() }
					SmallButton(title: "HP x2") { m.maxHP *= 2; m.hp = m.maxHP; game.bumpHUD() }
					SmallButton(title: "Kill") { if m.hp > 0 { game.killMob(m, false) }; game.bumpHUD() }
				}
			}
			Toggle("Include vehicles", isOn: $includeVehicles).font(.pixel(11, .bold))
			if confirmDelete {
				HStack(spacing: 6) {
					SmallButton(title: "CONFIRM DELETE ALL", color: Color(ui: 0xC02020)) {
						game.debugDeleteAllEntities(includeVehicles: includeVehicles)
						confirmDelete = false
					}
					SmallButton(title: "Cancel") { confirmDelete = false }
				}
			} else {
				SmallButton(title: "Delete all entities", color: Color(ui: 0xA03030)) { confirmDelete = true }
			}
		}
	}

	var multiplierSection: some View {
		VStack(alignment: .leading, spacing: 4) {
			section("MULTIPLIERS")
			Text(verbatim: joinText("Creature health (new spawns) x", String(format: "%.2f", game.mobHealthMult))).font(.pixel(10, .semibold))
			Slider(value: $game.mobHealthMult, in: 0.25...5.0, step: 0.25)
			Text(verbatim: joinText("Damage dealt x", String(format: "%.2f", game.dmgOutMult))).font(.pixel(10, .semibold))
			Slider(value: $game.dmgOutMult, in: 0.0...10.0, step: 0.25)
			Text(verbatim: joinText("Damage taken x", String(format: "%.2f", game.dmgInMult))).font(.pixel(10, .semibold))
			Slider(value: $game.dmgInMult, in: 0.0...5.0, step: 0.25)
			SmallButton(title: "Reset multipliers") { game.debugResetMultipliers() }
		}
	}

	var hazardSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			section("HAZARD TESTS")
			HStack(spacing: 6) {
				SmallButton(title: "Lava pool") { game.debugLavaPool() }
				SmallButton(title: "Explosion") { game.debugExplosionAtCursor() }
			}
			HStack(spacing: 6) {
				SmallButton(title: "Sand drop") { game.debugSandDrop() }
				SmallButton(title: "Spikes") { game.debugSpikes() }
				SmallButton(title: "Set on fire") { game.playerBurn = 3.0; game.bumpHUD() }
			}
		}
	}

	var perfLines: [String] {
		let p: Perf = Perf.shared
		var out: [String] = []
		out.append(String(format: "Tick %.2f ms (worst %.1f)  Draw %.2f ms", game.tickMs, game.tickWorstMs, p.renderMs))
		out.append(String(format: "AI %.2f  Physics %.2f  Light %.2f ms", p.aiMs, p.physMs, p.lightMs))
		out.append(String(format: "Chunk gen %.1f ms (worst %.1f), %d made", p.genMs, p.genWorstMs, p.chunksGenerated))
		out.append(joinText("Light full/partial ", String(p.lightFull), "/", String(p.lightDyn)))
		out.append(joinText("Moves ", String(p.moveCalls), "  Box checks ", String(p.boxChecks)))
		out.append(joinText("Damage queries ", String(p.damageQueries), "  AI skipped ", String(p.aiSkipped)))
		return out
	}

	var perfSection: some View {
		let lines: [String] = perfLines
		return VStack(alignment: .leading, spacing: 2) {
			section("PERFORMANCE")
			ForEach(0..<lines.count, id: \.self) { i in
				Text(lines[i]).font(.pixel(10, .semibold))
			}
		}
	}

	var systemsSection: some View {
		VStack(alignment: .leading, spacing: 4) {
			section("PAUSE SYSTEMS")
			Toggle("Creatures", isOn: $game.pauseMobs)
			Toggle("Bosses", isOn: $game.pauseBosses)
			Toggle("Spawning", isOn: $game.pauseSpawning)
			Toggle("Projectiles", isOn: $game.pauseProjectiles)
			Toggle("Vehicles", isOn: $game.pauseVehicles)
			Toggle("World ticks (plants, sand, leaves)", isOn: $game.pauseWorldTicks)
			Toggle("Particles", isOn: $game.pauseParticles)
			HStack(spacing: 6) {
				SmallButton(title: "Reset systems") { game.debugResetSystems() }
				SmallButton(title: "Reset camera") { game.settings.resetCamera(); game.bumpHUD() }
			}
		}
		.font(.pixel(11, .bold))
	}

	var worldSection: some View {
		let lines: [String] = game.debugWorldgenLines()
		return VStack(alignment: .leading, spacing: 2) {
			section("WORLD GENERATION")
			ForEach(0..<lines.count, id: \.self) { i in
				Text(lines[i]).font(.pixel(10, .semibold))
			}
			Text(verbatim: joinText("Structures chance ", String(format: "%.2f", game.gen.rareChance))).font(.pixel(10, .semibold))
		}
	}

	func section(_ s: String) -> some View {
		return Text(s).font(.pixel(11)).foregroundColor(Color(ui: 0xFFE066)).padding(.top, 4)
	}

	var statLines: [String] {
		var out: [String] = []
		let tickS: String = String(format: "%.2f", game.tickMs)
		out.append("Tick \(tickS) ms")
		let fpsN: Int = Int(game.renderFPS.rounded())
		out.append("FPS \(fpsN)")
		let dimName: String = game.world.dim == .overworld ? "Overworld" : (game.customDim?.def.name ?? "Umbral")
		let xs: String = String(format: "%.1f", game.pb.x)
		let ys: String = String(format: "%.1f", game.pb.y)
		out.append("XY \(xs), \(ys)  \(dimName)")
		let kind: String = joinText(game.gen.infinite ? "Infinite" : "Classic", game.gen.options.flat ? " flat" : "")
		let seedS: String = String(game.seedValue)
		out.append("Seed \(seedS)  \(kind)")
		let chunkN: Int = game.world.chunks.count
		let dirtyN: Int = game.world.dirtyChunkCount
		out.append("Chunks \(chunkN)  Dirty \(dirtyN)")
		let mobN: Int = game.mobs.count
		let shipN: Int = game.ships.count
		out.append("Mobs \(mobN)  Ships \(shipN)")
		let vehN: Int = game.vehicles.count
		out.append("Vehicles \(vehN)")
		let timeS: String = String(format: "%.2f", game.timeOfDay)
		let dayN: Int = game.dayCount
		let skyN: Int = Int(game.skyLevel)
		out.append("Time \(timeS)  Day \(dayN)  Sky \(skyN)")
		let open: String = game.portalOpened ? " (open)" : ""
		let px: Int = Int(game.gen.portalX)
		let py: Int = Int(game.gen.portalY)
		out.append("Portal \(px),\(py)\(open)")
		return out
	}

	var stats: some View {
		let lines: [String] = statLines
		return VStack(alignment: .leading, spacing: 2) {
			ForEach(0..<lines.count, id: \.self) { i in
				Text(lines[i])
			}
		}
		.font(.pixel(10, .semibold))
	}

	var toggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			Toggle("God mode", isOn: $game.godMode)
			Toggle("Fly", isOn: $game.flying)
			Toggle("Noclip", isOn: $game.noclip)
			Toggle("Monsters", isOn: $game.monstersEnabled)
			Toggle("Freeze time", isOn: $game.freezeTime)
			Toggle("Full bright", isOn: $game.fullBright)
			Toggle("Infinite reach", isOn: $game.infiniteReach)
			Toggle("Hitboxes", isOn: $game.showHitboxes)
			Toggle("Chunk borders", isOn: $game.showChunks)
		}
		.font(.pixel(12, .bold))
	}

	var spawnGrid: some View {
		let kinds: [MobKind] = MobKind.allCases
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 104), spacing: 4)]
		return LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
			ForEach(0..<kinds.count, id: \.self) { i in
				SmallButton(title: shortName(kinds[i])) { game.debugSpawn(kinds[i]) }
			}
		}
	}

	func shortName(_ k: MobKind) -> String {
		switch k {
		case .bearBoss: return "Bear Boss"
		case .rex: return "T-Rex Boss"
		case .pirateGunner: return "Gunner"
		case .pirateCaptain: return "Captain"
		case .polarBear: return "Polar Bear"
		case .emberSlime: return "Ember Slime"
		case .cinderBat: return "Cinder Bat"
		default: return mobDef(k).name
		}
	}
}
