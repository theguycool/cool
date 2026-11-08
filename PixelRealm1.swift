// PIXEL REALM v2, part 1 of 4: utilities, tiles, items, recipes, creature sprites, world generation, chunks, structures, the Umbral
// Realm, the world, light, physics, creatures, vehicles, the game state, the player, input and tools.
// The game is four files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm4.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). All art is generated in code.

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== p01_util =====
// ============================================================
// PIXEL REALM 2  -  expanded survival sandbox
// Single file. Paste it as the entire contents of MyApp.swift
// (delete ContentView.swift). iOS 16+ / macOS 13+.
// ============================================================

// MARK: - Utilities

// Fast conversions. Playgrounds builds in debug mode, where the generic integer
// initialisers (Int(UInt8), UInt64(Int)...) are slow function calls. These avoid them.
@inline(__always) func i8(_ v: UInt8) -> Int { return Int(Double(v)) }
// unsafeBitCast is transparent (inlined even in debug builds) and is exactly a bit reinterpretation
// between the two 64-bit types; the generic truncatingIfNeeded path was a large share of hashing time.
@inline(__always) func u64(_ v: Int) -> UInt64 { return unsafeBitCast(v, to: UInt64.self) }
@inline(__always) func iu64(_ v: UInt64) -> Int { return unsafeBitCast(v, to: Int.self) }

// MARK: - Performance counters (shown in the debug menu)

@inline(__always) func perfNow() -> Double { return Date().timeIntervalSinceReferenceDate }

final class Perf: @unchecked Sendable {
	static let shared: Perf = Perf()
	/// smoothed milliseconds
	var genMs: Double = 0
	var genWorstMs: Double = 0
	var chunksGenerated: Int = 0
	var aiMs: Double = 0
	var physMs: Double = 0
	var lightMs: Double = 0
	var renderMs: Double = 0
	/// per-frame counts (the last finished frame)
	var moveCalls: Int = 0
	var boxChecks: Int = 0
	var damageQueries: Int = 0
	var lightFull: Int = 0
	var lightDyn: Int = 0
	var aiSkipped: Int = 0
	private var curMove: Int = 0
	private var curBox: Int = 0
	private var curDmg: Int = 0
	private var curSkip: Int = 0

	@inline(__always) func countMove() { curMove &+= 1 }
	@inline(__always) func countBox() { curBox &+= 1 }
	@inline(__always) func countDamage() { curDmg &+= 1 }
	@inline(__always) func countSkip() { curSkip &+= 1 }

	func endFrame() {
		moveCalls = curMove; boxChecks = curBox; damageQueries = curDmg; aiSkipped = curSkip
		curMove = 0; curBox = 0; curDmg = 0; curSkip = 0
	}

	func noteGen(_ secs: Double) {
		let ms: Double = secs * 1000.0
		chunksGenerated += 1
		genMs = genMs == 0 ? ms : genMs * 0.8 + ms * 0.2
		genWorstMs = max(genWorstMs * 0.999, ms)
	}

	static func smooth(_ old: Double, _ secs: Double) -> Double {
		return old * 0.9 + secs * 1000.0 * 0.1
	}
}

struct RNG {
	var s: UInt64
	init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
	mutating func next() -> UInt64 {
		s = s &+ 0x9E3779B97F4A7C15
		var z: UInt64 = s
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		return z ^ (z >> 31)
	}
	mutating func double() -> Double { Double(next() >> 11) / 9007199254740992.0 }
	mutating func int(_ n: Int) -> Int { return iu64(next() % u64(max(1, n))) }
}

func hashU(_ x: Int, _ y: Int, _ s: UInt64) -> UInt64 {
	var h: UInt64 = u64(x) &* 0x9E3779B97F4A7C15
	h ^= u64(y) &* 0xC2B2AE3D27D4EB4F
	h ^= s &* 0x165667B19E3779F9
	h ^= h >> 29
	h = h &* 0xBF58476D1CE4E5B9
	h ^= h >> 32
	h = h &* 0x94D049BB133111EB
	h ^= h >> 29
	return h
}

func hash2(_ x: Int, _ y: Int, _ s: UInt64) -> Double {
	return Double(iu64(hashU(x, y, s) >> 40)) / 16777216.0
}

func smooth(_ f: Double) -> Double { return f * f * (3.0 - 2.0 * f) }

func noise1(_ x: Double, _ s: UInt64) -> Double {
	let fl: Double = floor(x)
	let xi: Int = Int(fl)
	let u: Double = smooth(x - fl)
	let a: Double = hash2(xi, 7, s)
	let b: Double = hash2(xi + 1, 7, s)
	return a + (b - a) * u
}

func fbm1(_ x: Double, _ s: UInt64, _ oct: Int) -> Double {
	var sum: Double = 0
	var amp: Double = 1
	var freq: Double = 1
	var norm: Double = 0
	for i in 0..<oct {
		sum += noise1(x * freq, s &+ u64(i) &* 101) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.0
	}
	return sum / norm
}

func vnoise(_ x: Double, _ y: Double, _ s: UInt64) -> Double {
	let fx0: Double = floor(x)
	let fy0: Double = floor(y)
	let xi: Int = Int(fx0)
	let yi: Int = Int(fy0)
	let u: Double = smooth(x - fx0)
	let v: Double = smooth(y - fy0)
	let a: Double = hash2(xi, yi, s)
	let b: Double = hash2(xi + 1, yi, s)
	let c: Double = hash2(xi, yi + 1, s)
	let d: Double = hash2(xi + 1, yi + 1, s)
	let top: Double = a + (b - a) * u
	let bot: Double = c + (d - c) * u
	return top + (bot - top) * v
}

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return max(lo, min(hi, v)) }
func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { return a + (b - a) * t }
func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { return max(lo, min(hi, v)) }

func floorDiv(_ a: Int, _ b: Int) -> Int {
	var q: Int = a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) { q -= 1 }
	return q
}

func mixRGB(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
	let tt: Double = clampD(t, 0, 1)
	func ch(_ s: UInt32) -> UInt32 {
		let ia: UInt32 = (a >> s) & 255
		let ib: UInt32 = (b >> s) & 255
		let ca: Double = Double(ia)
		let cb: Double = Double(ib)
		let d: Double = cb - ca
		let v: Double = ca + d * tt
		return UInt32(v)
	}
	return (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

func shadeRGB(_ c: UInt32, _ f: Double) -> UInt32 {
	func ch(_ s: UInt32) -> UInt32 {
		let ic: UInt32 = (c >> s) & 255
		let base: Double = Double(ic)
		let v: Double = base * f
		let cl: Double = clampD(v, 0, 255)
		return UInt32(cl)
	}
	return (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

// MARK: - Pixel buffers (platform neutral)

struct PixelBuf {
	var w: Int
	var h: Int
	var px: [UInt32]

	init(w: Int, h: Int) {
		self.w = w
		self.h = h
		self.px = [UInt32](repeating: 0, count: w * h)
	}

	func get(_ x: Int, _ y: Int) -> UInt32 {
		if x < 0 || y < 0 || x >= w || y >= h { return 0 }
		return px[y * w + x]
	}

	mutating func set(_ x: Int, _ y: Int, _ rgb: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h { return }
		px[y * w + x] = 0xFF000000 | rgb
	}

	mutating func clear(_ x: Int, _ y: Int) {
		if x < 0 || y < 0 || x >= w || y >= h { return }
		px[y * w + x] = 0
	}

	mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ rgb: UInt32) {
		if rw <= 0 || rh <= 0 { return }
		for yy in y..<(y + rh) {
			for xx in x..<(x + rw) { set(xx, yy, rgb) }
		}
	}

	mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rgb: UInt32) {
		let x0: Int = Int(floor(cx - rx)) - 1
		let x1: Int = Int(ceil(cx + rx)) + 1
		let y0: Int = Int(floor(cy - ry)) - 1
		let y1: Int = Int(ceil(cy + ry)) + 1
		for yy in y0...y1 {
			for xx in x0...x1 {
				let dx: Double = (Double(xx) + 0.5 - cx) / rx
				let dy: Double = (Double(yy) + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0 { set(xx, yy, rgb) }
			}
		}
	}

	mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ rgb: UInt32) {
		let n: Int = max(abs(x1 - x0), abs(y1 - y0))
		if n == 0 { set(x0, y0, rgb); return }
		for i in 0...n {
			let t: Double = Double(i) / Double(n)
			let xx: Int = Int((Double(x0) + Double(x1 - x0) * t).rounded())
			let yy: Int = Int((Double(y0) + Double(y1 - y0) * t).rounded())
			set(xx, yy, rgb)
		}
	}

	/// 1px outline around opaque pixels (needs transparent margin)
	mutating func outline(_ rgb: UInt32) {
		var out: [UInt32] = px
		for yy in 0..<h {
			for xx in 0..<w {
				if (px[yy * w + xx] >> 24) != 0 { continue }
				var near: Bool = false
				if xx > 0 && (px[yy * w + xx - 1] >> 24) != 0 { near = true }
				if xx < w - 1 && (px[yy * w + xx + 1] >> 24) != 0 { near = true }
				if yy > 0 && (px[(yy - 1) * w + xx] >> 24) != 0 { near = true }
				if yy < h - 1 && (px[(yy + 1) * w + xx] >> 24) != 0 { near = true }
				if near { out[yy * w + xx] = 0xFF000000 | rgb }
			}
		}
		px = out
	}

	func flipped() -> PixelBuf {
		var o = PixelBuf(w: w, h: h)
		for yy in 0..<h {
			for xx in 0..<w { o.px[yy * w + (w - 1 - xx)] = px[yy * w + xx] }
		}
		return o
	}

	/// Draw another buffer on top (alpha is on/off)
	mutating func blit(_ other: PixelBuf, _ ox: Int, _ oy: Int) {
		for yy in 0..<other.h {
			for xx in 0..<other.w {
				let c: UInt32 = other.px[yy * other.w + xx]
				if (c >> 24) == 0 { continue }
				let tx: Int = ox + xx
				let ty: Int = oy + yy
				if tx < 0 || ty < 0 || tx >= w || ty >= h { continue }
				px[ty * w + tx] = c
			}
		}
	}

	func tinted(_ rgb: UInt32, _ amount: Double) -> PixelBuf {
		var o = self
		for i in 0..<o.px.count {
			let c: UInt32 = o.px[i]
			if (c >> 24) == 0 { continue }
			o.px[i] = 0xFF000000 | mixRGB(c & 0xFFFFFF, rgb, amount)
		}
		return o
	}

	func whiteFlash() -> PixelBuf { return tinted(0xFFFFFF, 0.75) }
}

/// Build a buffer from rows of characters and a palette.
func bufFromRows(_ rows: [String], _ pal: [Character: UInt32]) -> PixelBuf {
	var wmax: Int = 1
	for r in rows { wmax = max(wmax, r.count) }
	var b = PixelBuf(w: wmax, h: rows.count)
	for (y, row) in rows.enumerated() {
		let chars: [Character] = Array(row)
		for x in 0..<chars.count {
			if let c = pal[chars[x]] { b.set(x, y, c) }
		}
	}
	return b
}

// ===== p02_tiles =====

// MARK: - Tiles

enum TStyle: Int {
	case noise, grassTop, log, leaves, planks, bricks, ore, water, glass, custom, lava, snow, ice, mud, cactus, crystal, farmland, sandstone, ash
}

struct TileDef {
	var name: String
	var hard: Double = 1.0
	var tier: Int = 0
	var solid: Bool = true
	var opaque: Bool = true
	var light: Int = 0
	var liquid: Bool = false
	var platform: Bool = false
	var plant: Bool = false
	var hurt: Bool = false
	var style: TStyle = .noise
	var colors: [UInt32] = [0x8A8A8A, 0x7A7A7A, 0x9A9A9A, 0x6A6A6A, 0x8A8A8A]
	var drop: Item? = nil
	var noDrop: Bool = false
}

enum Tile: UInt8, CaseIterable, Codable {
	case air, grass, dirt, stone, sand, log, leaves, water
	case coal, copper, iron, gold, diamond, mythril
	case planks, glass, brick, bedrock
	case snow, ice, sandstone, cactus, jungleLeaves, mud, dryGrass, jungleGrass, mossGrass
	case slate, deepRock, lava, obsidian
	case tallGrass, flowerR, flowerY, deadBush, mushroom, reed
	case workbench, furnace, campfire, torch, lantern, chest, platform
	case farmland, wheat1, wheat2, wheat3, carrot1, carrot2, carrot3
	case crackedBrick, mossBrick, spikes, fossil
	case ashStone, emberOre, voidOre, glowCrystal
	case portalFrame, portalOff, portalOn
	case jungleLog, palmLog, cobweb, hay
	case doorClosed, doorOpen
	/// logs placed by the player as building blocks: solid, unlike tree trunks (appended, so the raw
	/// values of every existing tile, and therefore old saves, are unchanged)
	case logBlock, jungleLogBlock, palmLogBlock
	/// climbable: hold jump (or up) to climb, down to descend
	case ladder
	/// workstations: metalwork from iron up, machinery and vehicles, and Umbral gear
	case anvil, tinkerBench, riftForge
	/// crystal deposits that line the walls of crystal grottos
	case crystalOre
	/// birch trunks (passable, like every tree trunk) and the solid block a placed birch log becomes,
	/// birch and pine foliage
	case birchLog, birchLogBlock, birchLeaves, pineLeaves
	/// ores of the upper ground and the middle depths (tin, saltpeter, silver, amethyst geodes), a
	/// building block cut from amethyst, and old mine fittings: rails, supply crates and ore carts
	case tin, saltpeter, silver, amethyst, amethystBlock, rail, crate, oreCart
	/// weather (appended): a weather station and its Doppler upgrade, a storm siren, a lightning rod, a
	/// wind turbine, a rain barrel and the larger cistern, a weather vane, a heater, and storm building:
	/// sandbags, storm shutters (closed and open), reinforced walls and storm shingles
	case weatherStation, dopplerStation, stormSiren, lightningRod, windTurbine, rainBarrel, rainCistern, weatherVane, heater
	case sandbag, shutterClosed, shutterOpen, stormBrick, shingles
	/// Sparkworks power and automation (appended): generators, storage, power control, pulse sources
	/// and logic, sensors, and machines (lamps and gates have on and off forms)
	case crankGen, solarPanel, fuelGen, waterWheel, emberDynamo
	case battery, accumulator
	case powerSwitch, breaker, powerMeter
	case lever, pushButton, pressurePlate, pulseTimer, repeater, inverter, logicGate
	case motionSensor, daySensor, weatherSensor, itemSensor, proximitySensor
	case gateClosed, gateOpen, lampOff, lampOn, arcTrap, autoDrill, conveyor, collector, autoCrafter, sumpPump, signalLight
	/// reserved for blocks from mods (appended): what each one is depends on the mods the world uses
	/// (see ModRuntime); each world remembers which block has which number
	case mod00, mod01, mod02, mod03, mod04, mod05, mod06, mod07, mod08, mod09, mod10, mod11, mod12, mod13, mod14, mod15, mod16, mod17, mod18, mod19, mod20, mod21, mod22, mod23, mod24, mod25, mod26, mod27, mod28, mod29, mod30, mod31, mod32, mod33, mod34, mod35, mod36, mod37, mod38, mod39, mod40, mod41, mod42, mod43, mod44, mod45, mod46, mod47, mod48, mod49, mod50, mod51, mod52, mod53, mod54, mod55, mod56, mod57, mod58, mod59, mod60, mod61, mod62, mod63
	/// alchemy, infusion and the exosuit (appended after the mod tiles, so every saved number stays)
	case alchemyStill, infuser, exoStation
	/// a young tree (appended): planted on soil, it grows into a tree that suits the land it stands in
	case sapling
	/// furniture (appended): to sit on, sleep in, keep things in, or to make a room look lived in. A bed
	/// is two tiles, its head on the left
	case chair, table, bedL, bedR, cabinet, wardrobe, shelf, bookshelf, floorLamp, sofa
	/// stairs (appended), rising to the right (R) or the left (L): a full-width lower step and a
	/// half-width upper one, walked up like any step (see World.stairHit)
	case stairWoodR, stairWoodL, stairStoneR, stairStoneL, stairBrickR, stairBrickL
	/// elevators (appended): the rail a lift car runs on, the button that calls it to a floor, and the
	/// car itself (an item: placed on a rail it becomes a moving Lift)
	case liftRail, liftButton, liftCar

	// the tables are built once; the reserved mod tiles are rewritten when a world's mods are switched
	// on (see `patch`), the game's own tiles never change
	static var defTable: [TileDef] = Tile.allCases.map { Tile.makeDef($0) }
	static var solidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid }
	static var opaqueTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).opaque }
	static var lightTable: [Int] = Tile.allCases.map { Tile.makeDef($0).light }
	static var liquidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).liquid }
	static var hurtTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).hurt }
	static var platformTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).platform }
	static var plantTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).plant }
	static var hardTable: [Double] = Tile.allCases.map { Tile.makeDef($0).hard }
	static var tierTable: [Int] = Tile.allCases.map { Tile.makeDef($0).tier }
	/// things can rest on or hang from these (solid tiles, plus tree trunks, which have no collision)
	static var supportTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid || isLogTile($0) || stairSide($0) != 0 }
	/// rain, hail and lightning stop at these (anything solid, glass, platforms, leaves, water)
	static var rainStopTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid || Tile.makeDef($0).platform || Tile.makeDef($0).liquid || isLeafTile($0) || stairSide($0) != 0 }
	/// stairs by raw value: 1 rising to the right, 2 rising to the left, 0 not a stair (see World.stairHit)
	static let stairTable: [UInt8] = Tile.allCases.map { stairSide($0) }
	static let deviceTable: [Bool] = Tile.allCases.map { isWeatherDevice($0) }
	static let powerTable: [Bool] = Tile.allCases.map { powerRole($0) != .none }
	/// the tool that mines each reserved mod tile at full speed
	static var modToolTable: [ToolType] = [ToolType](repeating: .pickaxe, count: ModLimits.blockSlots)
	/// the first tile number reserved for mods
	static let modBase: UInt8 = Tile.mod00.rawValue

	/// a tile reserved for a mod block
	var isMod: Bool { return rawValue >= Tile.modBase && Int(rawValue) < Int(Tile.modBase) + ModLimits.blockSlots }

	/// Rewrites one reserved mod tile in every table
	static func patch(_ t: Tile, _ d: TileDef, tool: ToolType) {
		let i: Int = Int(t.rawValue)
		if !t.isMod || i >= defTable.count { return }
		defTable[i] = d
		solidTable[i] = d.solid
		opaqueTable[i] = d.opaque
		lightTable[i] = d.light
		liquidTable[i] = false
		hurtTable[i] = d.hurt
		platformTable[i] = d.platform
		plantTable[i] = false
		hardTable[i] = d.hard
		tierTable[i] = d.tier
		supportTable[i] = d.solid
		rainStopTable[i] = d.solid || d.platform
		modToolTable[i - Int(modBase)] = tool
	}

	var idx: Int { return i8(rawValue) }
	var def: TileDef { return Tile.defTable[i8(rawValue)] }
	var solid: Bool { return Tile.solidTable[i8(rawValue)] }
	var opaque: Bool { return Tile.opaqueTable[i8(rawValue)] }
	var light: Int { return Tile.lightTable[i8(rawValue)] }
	var liquid: Bool { return Tile.liquidTable[i8(rawValue)] }
	var name: String { return def.name }
	var isPlant: Bool { return Tile.plantTable[i8(rawValue)] }
	var hurts: Bool { return Tile.hurtTable[i8(rawValue)] }
	var isPlatform: Bool { return Tile.platformTable[i8(rawValue)] }
	var hardness: Double { return Tile.hardTable[i8(rawValue)] }
	var supportsThings: Bool { return Tile.supportTable[i8(rawValue)] }
	/// a Sparkworks device (or the wind turbine, which feeds power cable too)
	var isPower: Bool { return Tile.powerTable[i8(rawValue)] }

	/// The tile a held block becomes when placed: a log item builds a solid log block, not a tree trunk
	var placedForm: Tile {
		switch self {
		case .log: return .logBlock
		case .jungleLog: return .jungleLogBlock
		case .palmLog: return .palmLogBlock
		case .birchLog: return .birchLogBlock
		default: return self
		}
	}

	static func make(_ raw: UInt8) -> Tile { return Tile(rawValue: raw) ?? .air }

	static func makeDef(_ t: Tile) -> TileDef {
		let stoneCols: [UInt32] = [0x8A8A8A, 0x7A7A7A, 0x9A9A9A, 0x6A6A6A, 0x8A8A8A]
		switch t {
		case .air:
			return TileDef(name: "Air", hard: 0, solid: false, opaque: false)
		case .grass:
			return TileDef(name: "Grass", hard: 0.5, style: .grassTop, colors: [0x5DAA3A, 0x4B9230, 0x7A5230, 0x5A3A1E, 0x8A6038], drop: .block(.dirt))
		case .dirt:
			return TileDef(name: "Dirt", hard: 0.4, colors: [0x7A5230, 0x6B4626, 0x8A6038, 0x5A3A1E, 0x7A5230])
		case .stone:
			return TileDef(name: "Stone", hard: 1.2, tier: 1, colors: stoneCols)
		case .sand:
			return TileDef(name: "Sand", hard: 0.4, colors: [0xE0D08A, 0xD2C078, 0xEBDDA0, 0xC4B268, 0xE0D08A])
		case .log:
			// tree trunks have no collision: everything walks (and flies, drives and shoots) through
			// them, and they let skylight past like the canopy does (a trunk standing on the ground
			// used to cast a dark shaft down through it). See logBlock for the solid building block.
			return TileDef(name: "Log", hard: 0.9, solid: false, opaque: false, style: .log, colors: [0x6B4A2A, 0x5A3C20, 0x7C5733, 0x4A3018, 0x6B4A2A])
		case .leaves:
			// canopies are one-way: walk and shoot through them, land on top of them
			return TileDef(name: "Leaves", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x3E8A2E, 0x2F7324, 0x56A83F, 0x225C1A, 0x3E8A2E], noDrop: true)
		case .water:
			return TileDef(name: "Water", hard: 0, solid: false, opaque: false, liquid: true, style: .water, colors: [0x3B7BE0, 0x4F90F0, 0x2E64C0, 0x8DBBFF, 0x3B7BE0], noDrop: true)
		case .coal:
			return TileDef(name: "Coal Ore", hard: 1.6, tier: 1, style: .ore, colors: stoneCols + [0x1E1E1E, 0x333333], drop: .mat(.coal))
		case .copper:
			return TileDef(name: "Copper Ore", hard: 1.8, tier: 2, style: .ore, colors: stoneCols + [0xD2793A, 0xF0A060], drop: .mat(.copperOre))
		case .iron:
			return TileDef(name: "Iron Ore", hard: 2.2, tier: 3, style: .ore, colors: stoneCols + [0xD8A878, 0xB88858], drop: .mat(.ironOre))
		case .gold:
			return TileDef(name: "Gold Ore", hard: 2.6, tier: 4, light: 2, style: .ore, colors: stoneCols + [0xF5D142, 0xFFE98A], drop: .mat(.goldOre))
		case .diamond:
			return TileDef(name: "Diamond Ore", hard: 3.2, tier: 5, light: 4, style: .ore, colors: stoneCols + [0x4FE3E8, 0xB8FBFF], drop: .mat(.diamond))
		case .mythril:
			return TileDef(name: "Mythril Ore", hard: 4.0, tier: 6, light: 5, style: .ore, colors: stoneCols + [0x6A5CFF, 0xB3A8FF], drop: .mat(.mythrilOre))
		case .planks:
			return TileDef(name: "Planks", hard: 0.8, style: .planks, colors: [0xB98A4E, 0x8F6732, 0xC89B5E, 0x7A5628, 0xB98A4E])
		case .glass:
			return TileDef(name: "Glass", hard: 0.3, opaque: false, style: .glass, colors: [0xCFEFFF, 0xFFFFFF, 0x9CCBE0, 0xCFEFFF, 0xCFEFFF])
		case .brick:
			return TileDef(name: "Stone Brick", hard: 1.5, tier: 1, style: .bricks, colors: [0xA64B3C, 0x8A8A8A, 0xB85A48, 0x8E3B2E, 0xA64B3C])
		case .bedrock:
			return TileDef(name: "Bedrock", hard: 9999, tier: 99, colors: [0x3A3A3A, 0x2A2A2A, 0x4A4A4A, 0x1A1A1A, 0x3A3A3A], noDrop: true)
		case .snow:
			return TileDef(name: "Snow", hard: 0.3, style: .snow, colors: [0xF2F8FF, 0xDCEBFA, 0xFFFFFF, 0xC4D8EE, 0xF2F8FF])
		case .ice:
			return TileDef(name: "Ice", hard: 0.5, opaque: false, style: .ice, colors: [0xAEDCF5, 0x8CC8EC, 0xD6F0FF, 0x78B4DC, 0xAEDCF5])
		case .sandstone:
			return TileDef(name: "Sandstone", hard: 1.0, tier: 1, style: .sandstone, colors: [0xD2B574, 0xC4A562, 0xDEC488, 0xB89850, 0xD2B574])
		case .cactus:
			return TileDef(name: "Cactus", hard: 0.4, hurt: true, style: .cactus, colors: [0x3F8F3F, 0x2F7A2F, 0x58AE58, 0x1F5F1F, 0x3F8F3F])
		case .jungleLeaves:
			return TileDef(name: "Jungle Leaves", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x1F8A3A, 0x146B2A, 0x32AA4E, 0x0E5420, 0x1F8A3A], noDrop: true)
		case .mud:
			return TileDef(name: "Mud", hard: 0.5, style: .mud, colors: [0x4E3A2A, 0x3E2E20, 0x5E4834, 0x30241A, 0x4E3A2A])
		case .dryGrass:
			return TileDef(name: "Dry Grass", hard: 0.5, style: .grassTop, colors: [0xBDB35A, 0xA39A48, 0x7A5230, 0x5A3A1E, 0x8A6038], drop: .block(.dirt))
		case .jungleGrass:
			return TileDef(name: "Jungle Grass", hard: 0.5, style: .grassTop, colors: [0x2E9E3A, 0x1F8A2C, 0x4E3A2A, 0x3E2E20, 0x5E4834], drop: .block(.mud))
		case .mossGrass:
			return TileDef(name: "Moss", hard: 0.5, style: .grassTop, colors: [0x6E8A3A, 0x5A7430, 0x4E3A2A, 0x3E2E20, 0x5E4834], drop: .block(.mud))
		case .slate:
			return TileDef(name: "Slate", hard: 1.7, tier: 1, colors: [0x5E6678, 0x4F5666, 0x6D7688, 0x40475A, 0x5E6678])
		case .deepRock:
			return TileDef(name: "Deep Rock", hard: 2.6, tier: 3, colors: [0x3E3846, 0x34303C, 0x4A4452, 0x2A2632, 0x3E3846])
		case .lava:
			return TileDef(name: "Lava", hard: 0, solid: false, opaque: false, light: 14, liquid: true, hurt: true, style: .lava, colors: [0xE8580C, 0xFF8A1E, 0xC03A06, 0xFFD060, 0xE8580C], noDrop: true)
		case .obsidian:
			return TileDef(name: "Obsidian", hard: 4.2, tier: 5, colors: [0x241838, 0x1A1028, 0x34244E, 0x120A1E, 0x241838])
		case .tallGrass:
			return TileDef(name: "Tall Grass", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
		case .flowerR:
			return TileDef(name: "Red Flower", hard: 0, solid: false, opaque: false, plant: true, style: .custom)
		case .flowerY:
			return TileDef(name: "Yellow Flower", hard: 0, solid: false, opaque: false, plant: true, style: .custom)
		case .deadBush:
			return TileDef(name: "Dead Bush", hard: 0, solid: false, opaque: false, plant: true, style: .custom, drop: .mat(.stick))
		case .mushroom:
			return TileDef(name: "Glow Mushroom", hard: 0, solid: false, opaque: false, light: 6, plant: true, style: .custom)
		case .reed:
			return TileDef(name: "Reed", hard: 0, solid: false, opaque: false, plant: true, style: .custom, drop: .mat(.stick))
		case .workbench:
			return TileDef(name: "Workbench", hard: 0.6, solid: false, opaque: false, style: .custom)
		case .furnace:
			return TileDef(name: "Furnace", hard: 1.0, tier: 1, solid: false, opaque: false, light: 7, style: .custom)
		case .campfire:
			return TileDef(name: "Campfire", hard: 0.5, solid: false, opaque: false, light: 13, hurt: false, style: .custom)
		case .torch:
			return TileDef(name: "Torch", hard: 0, solid: false, opaque: false, light: 12, plant: true, style: .custom)
		case .lantern:
			return TileDef(name: "Lantern", hard: 0.2, solid: false, opaque: false, light: 14, plant: true, style: .custom)
		case .chest:
			return TileDef(name: "Chest", hard: 0.8, solid: false, opaque: false, style: .custom, noDrop: false)
		case .platform:
			return TileDef(name: "Platform", hard: 0.3, solid: false, opaque: false, platform: true, style: .custom)
		case .farmland:
			return TileDef(name: "Farmland", hard: 0.4, style: .farmland, colors: [0x5A3A1E, 0x4A2E16, 0x6B4626, 0x3A220E, 0x5A3A1E], drop: .block(.dirt))
		case .wheat1, .wheat2, .wheat3:
			return TileDef(name: "Wheat", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
		case .carrot1, .carrot2, .carrot3:
			return TileDef(name: "Carrots", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
		case .crackedBrick:
			return TileDef(name: "Cracked Brick", hard: 1.0, tier: 1, style: .bricks, colors: [0x8E7A68, 0x6A5A4C, 0xA08C78, 0x5A4A3C, 0x8E7A68])
		case .mossBrick:
			return TileDef(name: "Mossy Brick", hard: 1.4, tier: 1, style: .bricks, colors: [0x6E8A5A, 0x4C5E3E, 0x82A06C, 0x3C4C30, 0x6E8A5A])
		case .spikes:
			return TileDef(name: "Spikes", hard: 0.8, tier: 1, solid: false, opaque: false, hurt: true, style: .custom)
		case .fossil:
			return TileDef(name: "Fossil Block", hard: 1.5, tier: 1, style: .custom, drop: .mat(.bone))
		case .ashStone:
			return TileDef(name: "Ashstone", hard: 2.2, tier: 4, style: .ash, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48])
		case .emberOre:
			return TileDef(name: "Ember Ore", hard: 3.4, tier: 7, light: 7, style: .ore, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48, 0xFF7A1E, 0xFFC050], drop: .mat(.emberOre))
		case .voidOre:
			return TileDef(name: "Voidium Ore", hard: 4.6, tier: 8, light: 8, style: .ore, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48, 0xB04CFF, 0xE8A8FF], drop: .mat(.voidOre))
		case .glowCrystal:
			return TileDef(name: "Glow Crystal", hard: 1.2, tier: 4, opaque: false, light: 11, style: .crystal, colors: [0x7A4CFF, 0xB38CFF, 0x4E2AC0, 0xE6D8FF, 0x7A4CFF])
		case .portalFrame:
			return TileDef(name: "Rift Anchor", hard: 99999, tier: 99, light: 4, style: .custom, colors: [0x23262E, 0x3A3F4A, 0x2E323B, 0x16181E, 0x23262E], noDrop: true)
		case .portalOff:
			return TileDef(name: "Dormant Rift", hard: 99999, tier: 99, solid: false, opaque: false, style: .custom, noDrop: true)
		case .portalOn:
			return TileDef(name: "Open Rift", hard: 99999, tier: 99, solid: false, opaque: false, light: 13, style: .custom, noDrop: true)
		case .jungleLog:
			return TileDef(name: "Jungle Log", hard: 1.0, solid: false, opaque: false, style: .log, colors: [0x5A4A2A, 0x4A3A20, 0x6C5C34, 0x3A2C14, 0x5A4A2A])
		case .palmLog:
			return TileDef(name: "Palm Log", hard: 0.8, solid: false, opaque: false, style: .log, colors: [0x9A7A4A, 0x826238, 0xB08C58, 0x6A4E2A, 0x9A7A4A])
		case .cobweb:
			return TileDef(name: "Cobweb", hard: 0.1, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
		case .hay:
			return TileDef(name: "Hay Bale", hard: 0.4, style: .noise, colors: [0xD8B83A, 0xBE9E2A, 0xE8CC52, 0xA88820, 0xD8B83A])
		case .doorClosed:
			return TileDef(name: "Wooden Door", hard: 0.6, solid: true, opaque: false, style: .custom, colors: [0x8F6732], drop: .block(.doorClosed))
		case .doorOpen:
			return TileDef(name: "Open Door", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x8F6732], drop: .block(.doorClosed))
		case .logBlock:
			return TileDef(name: "Log", hard: 0.9, style: .log, colors: [0x6B4A2A, 0x5A3C20, 0x7C5733, 0x4A3018, 0x6B4A2A], drop: .block(.log))
		case .jungleLogBlock:
			return TileDef(name: "Jungle Log", hard: 1.0, style: .log, colors: [0x5A4A2A, 0x4A3A20, 0x6C5C34, 0x3A2C14, 0x5A4A2A], drop: .block(.jungleLog))
		case .palmLogBlock:
			return TileDef(name: "Palm Log", hard: 0.8, style: .log, colors: [0x9A7A4A, 0x826238, 0xB08C58, 0x6A4E2A, 0x9A7A4A], drop: .block(.palmLog))
		case .ladder:
			return TileDef(name: "Ladder", hard: 0.3, solid: false, opaque: false, style: .custom, colors: [0x9A6E3A])
		case .anvil:
			return TileDef(name: "Anvil", hard: 1.6, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x5A5E68])
		case .tinkerBench:
			return TileDef(name: "Tinker's Bench", hard: 0.8, solid: false, opaque: false, style: .custom, colors: [0x8F6732])
		case .riftForge:
			return TileDef(name: "Rift Forge", hard: 3.0, tier: 5, solid: false, opaque: false, light: 9, style: .custom, colors: [0x2A1A3A])
		case .crystalOre:
			return TileDef(name: "Crystal Vein", hard: 2.8, tier: 4, light: 6, style: .custom, colors: [0x5E6678, 0x4F5666, 0x6D7688, 0x40475A, 0x5E6678, 0x8AF0E8, 0xD8FFFA], drop: .mat(.crystalShard))
		case .birchLog:
			return TileDef(name: "Birch Log", hard: 0.8, solid: false, opaque: false, style: .custom, colors: [0xE2DED2, 0xC8C4B8, 0xF4F2EA, 0x3A3632, 0xE2DED2])
		case .birchLogBlock:
			return TileDef(name: "Birch Log", hard: 0.8, style: .custom, colors: [0xE2DED2, 0xC8C4B8, 0xF4F2EA, 0x3A3632, 0xE2DED2], drop: .block(.birchLog))
		case .birchLeaves:
			return TileDef(name: "Birch Leaves", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x7DB846, 0x649A34, 0x9ACC5A, 0x4E7E28, 0x7DB846], noDrop: true)
		case .pineLeaves:
			return TileDef(name: "Pine Needles", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x2E6E52, 0x225A42, 0x3E8464, 0x18463A, 0x2E6E52], noDrop: true)
		case .tin:
			return TileDef(name: "Tin Ore", hard: 1.7, tier: 2, style: .custom, colors: stoneCols + [0xC8D2DA, 0xF2F6FA], drop: .mat(.tinOre))
		case .saltpeter:
			return TileDef(name: "Saltpeter", hard: 1.0, tier: 1, style: .custom, colors: stoneCols + [0xEDEAE0, 0xFFFFFF], drop: .mat(.saltpeter))
		case .silver:
			return TileDef(name: "Silver Ore", hard: 2.4, tier: 3, light: 1, style: .custom, colors: stoneCols + [0xDDE4EE, 0xFFFFFF], drop: .mat(.silverOre))
		case .amethyst:
			return TileDef(name: "Amethyst Geode", hard: 1.8, tier: 2, light: 4, style: .custom, colors: stoneCols + [0x9A5ADC, 0xE0C0FF], drop: .mat(.amethyst))
		case .amethystBlock:
			return TileDef(name: "Amethyst Block", hard: 1.4, tier: 1, light: 6, style: .crystal, colors: [0x8A4CC8, 0xB07AE8, 0x6A34A8, 0xE8D0FF, 0x8A4CC8])
		case .rail:
			return TileDef(name: "Rail", hard: 0.2, solid: false, opaque: false, plant: true, style: .custom, colors: [0x6A6A72])
		case .crate:
			return TileDef(name: "Supply Crate", hard: 0.7, style: .custom, colors: [0xA97B45])
		case .oreCart:
			return TileDef(name: "Ore Cart", hard: 0.8, solid: false, opaque: false, style: .custom, colors: [0x5A5E68], noDrop: true)
		case .weatherStation:
			return TileDef(name: "Weather Station", hard: 1.0, solid: false, opaque: false, light: 3, style: .custom, colors: [0x8F6732])
		case .dopplerStation:
			return TileDef(name: "Doppler Station", hard: 1.4, tier: 1, solid: false, opaque: false, light: 5, style: .custom, colors: [0x5A6470])
		case .stormSiren:
			return TileDef(name: "Storm Siren", hard: 1.4, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x8A8E98])
		case .lightningRod:
			return TileDef(name: "Lightning Rod", hard: 0.8, solid: false, opaque: false, style: .custom, colors: [0xD2793A])
		case .windTurbine:
			return TileDef(name: "Wind Turbine", hard: 1.2, tier: 1, solid: false, opaque: false, style: .custom, colors: [0xC8CCD4])
		case .rainBarrel:
			return TileDef(name: "Rain Barrel", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0x8F6732])
		case .rainCistern:
			return TileDef(name: "Rain Cistern", hard: 1.4, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x6A6E78])
		case .weatherVane:
			return TileDef(name: "Weather Vane", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0xD2793A])
		case .heater:
			return TileDef(name: "Heater", hard: 1.2, tier: 1, solid: false, opaque: false, light: 9, style: .custom, colors: [0x4A4E58])
		case .sandbag:
			return TileDef(name: "Sandbags", hard: 0.9, style: .custom, colors: [0xB8A070])
		case .shutterClosed:
			return TileDef(name: "Storm Shutter", hard: 1.0, style: .custom, colors: [0x6A7A5A], drop: .block(.shutterClosed))
		case .shutterOpen:
			return TileDef(name: "Open Shutter", hard: 1.0, solid: false, opaque: false, style: .custom, colors: [0x6A7A5A], drop: .block(.shutterClosed))
		case .stormBrick:
			return TileDef(name: "Reinforced Wall", hard: 3.0, tier: 2, style: .custom, colors: [0x6A6E78])
		case .shingles:
			return TileDef(name: "Storm Shingles", hard: 1.1, tier: 1, style: .custom, colors: [0x7A4A3A])
		case .crankGen:
			return TileDef(name: "Hand Crank Generator", hard: 1.0, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .solarPanel:
			return TileDef(name: "Solar Panel", hard: 1.0, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x2A5A9A])
		case .fuelGen:
			return TileDef(name: "Fuel Generator", hard: 1.4, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .waterWheel:
			return TileDef(name: "Water Wheel", hard: 0.9, solid: false, opaque: false, style: .custom, colors: [0x8F6732])
		case .emberDynamo:
			return TileDef(name: "Ember Dynamo", hard: 2.4, tier: 4, solid: false, opaque: false, light: 5, style: .custom, colors: [0x2A1E2E])
		case .battery:
			return TileDef(name: "Copper Cell", hard: 1.0, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .accumulator:
			return TileDef(name: "Crystal Accumulator", hard: 1.8, tier: 2, solid: false, opaque: false, light: 3, style: .custom, colors: [0x30A0A0])
		case .powerSwitch:
			return TileDef(name: "Power Switch", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .breaker:
			return TileDef(name: "Circuit Breaker", hard: 0.8, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .powerMeter:
			return TileDef(name: "Power Meter", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0xE8E4D8])
		case .lever:
			return TileDef(name: "Lever", hard: 0.5, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .pushButton:
			return TileDef(name: "Push Button", hard: 0.5, solid: false, opaque: false, style: .custom, colors: [0x30B0C0])
		case .pressurePlate:
			return TileDef(name: "Pressure Plate", hard: 0.5, solid: false, opaque: false, style: .custom, colors: [0x8A94A4])
		case .pulseTimer:
			return TileDef(name: "Pulse Timer", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0xE8E4D8])
		case .repeater:
			return TileDef(name: "Pulse Relay", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .inverter:
			return TileDef(name: "Inverter", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x6A4A7A])
		case .logicGate:
			return TileDef(name: "Logic Gate", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x3A6A6A])
		case .motionSensor:
			return TileDef(name: "Motion Sensor", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0xC86A3A])
		case .daySensor:
			return TileDef(name: "Daylight Sensor", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0x5A8AC8])
		case .weatherSensor:
			return TileDef(name: "Weather Sensor", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0x3B7BE0])
		case .itemSensor:
			return TileDef(name: "Item Sensor", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0xA97B45])
		case .proximitySensor:
			return TileDef(name: "Proximity Sensor", hard: 0.7, solid: false, opaque: false, style: .custom, colors: [0x30E0D0])
		case .gateClosed:
			return TileDef(name: "Steel Gate", hard: 2.2, tier: 2, opaque: false, style: .custom, colors: [0x8A94A4], drop: .block(.gateClosed))
		case .gateOpen:
			return TileDef(name: "Open Steel Gate", hard: 2.2, tier: 2, solid: false, opaque: false, style: .custom, colors: [0x8A94A4], drop: .block(.gateClosed))
		case .lampOff:
			return TileDef(name: "Spark Lamp", hard: 0.8, opaque: false, style: .custom, colors: [0x8A9AA0], drop: .block(.lampOff))
		case .lampOn:
			return TileDef(name: "Lit Spark Lamp", hard: 0.8, opaque: false, light: 15, style: .custom, colors: [0xFFF4C0], drop: .block(.lampOff))
		case .arcTrap:
			return TileDef(name: "Arc Trap", hard: 1.8, tier: 2, style: .custom, colors: [0x5A6270])
		case .autoDrill:
			return TileDef(name: "Auto Drill", hard: 2.0, tier: 2, style: .custom, colors: [0xE8C020])
		case .conveyor:
			return TileDef(name: "Conveyor Belt", hard: 1.2, tier: 1, style: .custom, colors: [0x2A2A2E])
		case .collector:
			return TileDef(name: "Item Collector", hard: 1.2, tier: 1, style: .custom, colors: [0x8A94A4])
		case .autoCrafter:
			return TileDef(name: "Auto Crafter", hard: 1.6, tier: 2, style: .custom, colors: [0xB0A060])
		case .sumpPump:
			return TileDef(name: "Sump Pump", hard: 1.4, tier: 1, style: .custom, colors: [0x3B7BE0])
		case .signalLight:
			return TileDef(name: "Pulse Indicator", hard: 0.4, solid: false, opaque: false, style: .custom, colors: [0x30E0D0])
		case .alchemyStill:
			return TileDef(name: "Alchemy Still", hard: 1.0, solid: false, opaque: false, light: 4, style: .custom, colors: [0xD2793A])
		case .infuser:
			return TileDef(name: "Infusion Crucible", hard: 2.0, tier: 1, solid: false, opaque: false, light: 6, style: .custom, colors: [0x6A5A8A])
		case .exoStation:
			return TileDef(name: "Assembly Station", hard: 2.0, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x5A6270])
		case .sapling:
			return TileDef(name: "Sapling", hard: 0, solid: false, opaque: false, plant: true, style: .custom, colors: [0x4B9A30])
		case .chair:
			return TileDef(name: "Chair", hard: 0.4, solid: false, opaque: false, style: .custom, colors: [0xA0703A])
		case .table:
			return TileDef(name: "Table", hard: 0.5, solid: false, opaque: false, platform: true, style: .custom, colors: [0xC89B5E])
		case .bedL:
			return TileDef(name: "Bed", hard: 0.4, solid: false, opaque: false, platform: true, style: .custom, colors: [0xC03838])
		case .bedR:
			return TileDef(name: "Bed", hard: 0.4, solid: false, opaque: false, platform: true, style: .custom, colors: [0xC03838], drop: .block(.bedL))
		case .cabinet:
			return TileDef(name: "Cabinet", hard: 0.6, solid: false, opaque: false, platform: true, style: .custom, colors: [0x9A6A38])
		case .wardrobe:
			return TileDef(name: "Wardrobe", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x7A5230])
		case .shelf:
			return TileDef(name: "Shelf", hard: 0.3, solid: false, opaque: false, platform: true, style: .custom, colors: [0xC89B5E])
		case .bookshelf:
			return TileDef(name: "Bookshelf", hard: 0.6, solid: false, opaque: false, platform: true, style: .custom, colors: [0x8F6732])
		case .floorLamp:
			return TileDef(name: "Floor Lamp", hard: 0.3, solid: false, opaque: false, light: 13, style: .custom, colors: [0xFFE680])
		case .sofa:
			return TileDef(name: "Sofa", hard: 0.4, solid: false, opaque: false, style: .custom, colors: [0x3A6AA8])
		case .stairWoodR, .stairWoodL:
			return TileDef(name: "Wooden Stairs", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0xC89B5E], drop: .block(.stairWoodR))
		case .stairStoneR, .stairStoneL:
			return TileDef(name: "Stone Stairs", hard: 1.4, tier: 1, solid: false, opaque: false, style: .custom, colors: [0x8A8A8A], drop: .block(.stairStoneR))
		case .stairBrickR, .stairBrickL:
			return TileDef(name: "Brick Stairs", hard: 1.6, tier: 1, solid: false, opaque: false, style: .custom, colors: [0xB0503A], drop: .block(.stairBrickR))
		case .liftRail:
			return TileDef(name: "Lift Rail", hard: 0.5, solid: false, opaque: false, style: .custom, colors: [0x9AA4B0])
		case .liftButton:
			return TileDef(name: "Lift Button", hard: 0.3, solid: false, opaque: false, light: 4, style: .custom, colors: [0x5A6270])
		case .liftCar:
			return TileDef(name: "Lift Car", hard: 0.5, solid: false, opaque: false, style: .custom, colors: [0x7A8490])
		default:
			// the tiles reserved for mods, until a world's mods give them a meaning (see ModRuntime)
			return TileDef(name: "Unused Mod Block", hard: 9999, style: .custom, colors: [0xFF00FF, 0x200020, 0xFF00FF, 0x200020, 0xFF00FF], noDrop: true)
		}
	}
}

// MARK: - Tile art

func customTileRows(_ t: Tile) -> ([String], [Character: UInt32])? {
	switch t {
	case .torch:
		return ([".......", "...y...", "..yoy..", "...r...", "...b...", "...b...", "...b...", "...b..."].map { String($0) },
				["y": 0xFFE680, "o": 0xFFA030, "r": 0xE05818, "b": 0x8A5A2A])
	case .lantern:
		return (["...kk...", "..kyyk..", ".kyYYyk.", ".kyYYyk.", ".kyyyyk.", "..kkkk.."],
				["k": 0x3A3A3A, "y": 0xFFC84A, "Y": 0xFFF2B0])
	case .campfire:
		return (["........", "...y....", "..yoy.y.", "..oryo..", ".bbrobb.", "bbbbbbbb", "ssbbbbss", "........"],
				["y": 0xFFE680, "o": 0xFFA030, "r": 0xE05818, "b": 0x6B4A2A, "s": 0x808080])
	case .workbench:
		return (["........", "........", "tttttttt", "bbbbbbbb", "b.b..b.b", "b.b..b.b", "b.b..b.b", "b.b..b.b"],
				["t": 0xC89B5E, "b": 0x8F6732])
	case .furnace:
		return (["ssssssss", "sSSSSSSs", "sSkkkkSs", "sSkoOkSs", "sSkOykSs", "sSkkkkSs", "sSSSSSSs", "ssssssss"],
				["s": 0x6A6A6A, "S": 0x8A8A8A, "k": 0x2A2020, "o": 0xE05818, "O": 0xFFA030, "y": 0xFFE680])
	case .chest:
		return (["........", "........", "wwwwwwww", "wddddddw", "wwwgwwww", "wddddddw", "wddddddw", "wwwwwwww"],
				["w": 0x8F6732, "d": 0xB98A4E, "g": 0xF5D142])
	case .platform:
		return (["........", "........", "........", "........", "........", "........", "pppppppp", "qqqqqqqq"],
				["p": 0xC89B5E, "q": 0x8F6732])
	case .tallGrass:
		return (["........", "........", "........", ".g...g..", ".g.g.g.g", "gg.g.ggg", "gggggggg", "gggggggg"],
				["g": 0x4B9A30])
	case .flowerR:
		return (["........", "........", "...rr...", "..rYr...", "...rr...", "....g...", "....g...", "...ggg.."],
				["r": 0xE63A3A, "Y": 0xFFE060, "g": 0x3E8A2E])
	case .flowerY:
		return (["........", "........", "..yy....", ".yOyy...", "..yy....", "...g....", "...g....", "..ggg..."],
				["y": 0xFFE040, "O": 0xE08A20, "g": 0x3E8A2E])
	case .deadBush:
		return (["........", "........", ".b...b..", "..b.b...", "...b..b.", "..bbbb..", "...b....", "...b...."],
				["b": 0x8A6A3A])
	case .mushroom:
		return (["........", "........", "..cccc..", ".cCcccc.", ".cccCcc.", "...ww...", "...ww...", "...ww..."],
				["c": 0x3AC8C8, "C": 0xA8FFFF, "w": 0xD8E8F0])
	case .reed:
		return (["...b....", "...b..b.", "...g..b.", "...g..g.", ".g.g..g.", ".g.g.gg.", ".g.ggg..", "..gggg.."],
				["g": 0x6E8A3A, "b": 0x6B4A2A])
	case .wheat1:
		return (["........", "........", "........", "........", "........", "g.g..g.g", "g.g..g.g", "gggggggg"],
				["g": 0x7AB83A])
	case .wheat2:
		return (["........", "........", "........", "y.y..y.y", "g.g..g.g", "g.g..g.g", "g.g..g.g", "gggggggg"],
				["g": 0x8AB03A, "y": 0xD8C050])
	case .wheat3:
		return (["y.y..y.y", "yyy..yyy", "yyy..yyy", "y.y..y.y", "g.g..g.g", "g.g..g.g", "g.g..g.g", "gggggggg"],
				["g": 0xB0A030, "y": 0xE8C850])
	case .carrot1:
		return (["........", "........", "........", "........", "........", "..g..g..", ".ggggg..", "gggggggg"],
				["g": 0x4EA83A])
	case .carrot2:
		return (["........", "........", "........", "..g..g..", ".ggggg..", ".gggggg.", "gggggggg", "gggggggg"],
				["g": 0x4EB83A])
	case .carrot3:
		return (["........", "..g..g..", ".ggggg..", ".gggggg.", "ggoggogg", "gggggggg", "gggoggog", "gggggggg"],
				["g": 0x4EB83A, "o": 0xF08A1E])
	case .spikes:
		return (["........", "........", "........", "...s....", "..sss.s.", ".sssssss", "ssssssss", "dddddddd"],
				["s": 0xC8C8D0, "d": 0x5A5A5A])
	case .fossil:
		return (["ssssssss", "sbbsssss", "ssbbssss", "sssbbbbs", "ssssbssb", "sbbbssbs", "ssbssbss", "ssssssss"],
				["s": 0x8A8A8A, "b": 0xE8E0C8])
	case .portalOff, .portalOn:
		// drawn as one shape by the renderer's rift pass; the tiles themselves are see-through
		return (["........"], [:])
	case .portalFrame:
		// dark basalt anchor stone with an amber vein
		return (["kkbbbbkk", "kbbBbbbk", "bbbbaBbb", "bBbaabbb", "bbaabbBb", "bbabbbbb", "kbbbBbbk", "kkbbbbkk"],
				["k": 0x16181E, "b": 0x2A2E37, "B": 0x3C424E, "a": 0xC08040])
	case .doorClosed:
		return (["dDDDDDDd", "dDdddDDd", "dDdddDDd", "dDDDDDDd", "dDDDDgDd", "dDdddDDd", "dDdddDDd", "dDDDDDDd"],
				["d": 0x6A4A22, "D": 0xA97B45, "g": 0xE8C040])
	case .doorOpen:
		return (["dD......", "dD......", "dD......", "dD......", "dD......", "dD......", "dD......", "dD......"],
				["d": 0x6A4A22, "D": 0xA97B45])
	case .cobweb:
		return (["w.....w.", ".w...w..", "..w.w...", "...w....", "..w.w...", ".w...w..", "w.....w.", "........"],
				["w": 0xE8E8F0])
	case .ladder:
		return ([".r....r.", ".rgggggr", ".r....r.", ".r....r.", ".r....r.", ".rgggggr", ".r....r.", ".r....r."].map { String($0.prefix(8)) },
				["r": 0x7A5428, "g": 0xB98A4E])
	case .anvil:
		return (["........", "........", "hhhhhhh.", ".HHHHHHh", "..sss...", "..sss...", ".bbbbb..", "bbbbbbb."],
				["h": 0x8A8E98, "H": 0x6A6E78, "s": 0x4A4E58, "b": 0x3A3E48])
	case .tinkerBench:
		return (["....g...", "...ggg..", "tttttttt", "bbbbbbbb", "b.c..k.b", "b.c..k.b", "b......b", "b......b"],
				["t": 0xC89B5E, "b": 0x8F6732, "g": 0xD8A040, "c": 0xB0B4BC, "k": 0xC03A3A])
	case .riftForge:
		return (["..pppp..", ".pPppPp.", "oovvvvoo", "ovVvvVvo", "ovvVVvvo", "oovvvvoo", "oooooooo", "oooooooo"],
				["o": 0x241838, "p": 0x8A4CD8, "P": 0xD8A8FF, "v": 0x4A2A7A, "V": 0xB070FF])
	case .alchemyStill:
		// a copper pot on a stand, its coil running to a flask
		return (["..c.....", ".ccc..g.", "cCCCc.g.", "cCCCcgg.", "cCCCc.f.", ".ccc.fFf", "bbbbbfff", "b...b..."],
				["c": 0xB8612A, "C": 0xF0A060, "g": 0xCFEFFF, "f": 0xB8E0F0, "F": 0x7AD040, "b": 0x5A4A3A])
	case .infuser:
		// a stone crucible brimming with something that glows
		return (["..p..p..", ".PvvvvP.", "svVVVVvs", "sSvvvvSs", ".sSSSSs.", "..ssss..", ".ssssss.", "ssssssss"],
				["p": 0xC07CFF, "P": 0x8A6AB8, "v": 0x9A5ADC, "V": 0xE0B8FF, "s": 0x5A5E68, "S": 0x7A7E88])
	case .chair:
		// side on, its back to the left
		return (["b.......", "b.......", "b.......", "bsssss..", "bSSSSS..", "b....l..", "b....l..", "b....l.."],
				["b": 0x7A5230, "s": 0xC08A50, "S": 0x9A6A38, "l": 0x7A5230])
	case .table:
		return (["........", "........", "tttttttt", "TTTTTTTT", ".l....l.", ".l....l.", ".l....l.", ".l....l."],
				["t": 0xC89B5E, "T": 0x8F6732, "l": 0x7A5230])
	case .bedL:
		// the headboard and the pillow
		return (["hh......", "hh......", "hh......", "hhwwwbbb", "hhWWWBBB", "hhffffff", "hh......", "h......."],
				["h": 0x7A5230, "w": 0xF0EEE6, "W": 0xC8C4B8, "b": 0xC83A3A, "B": 0x962828, "f": 0x8F6732])
	case .bedR:
		// the foot of the bed
		return (["........", "........", ".......f", "bbbbbbbf", "BBBBBBBf", "ffffffff", ".......f", ".......f"],
				["b": 0xC83A3A, "B": 0x962828, "f": 0x7A5230])
	case .cabinet:
		return (["tttttttt", "cddkkddc", "cddkkddc", "cddddddc", "cddddddc", "cddddddc", "cccccccc", "c......c"],
				["t": 0xC89B5E, "c": 0x7A5230, "d": 0xB07E48, "k": 0xE8C84A])
	case .wardrobe:
		return (["cccccccc", "cdddcddc", "cddkckdc", "cdddcddc", "cdddcddc", "cdddcddc", "cccccccc", "c......c"],
				["c": 0x5E3E22, "d": 0x8F6732, "k": 0xE8C84A])
	case .shelf:
		return (["........", "........", "..r..g..", ".rr.ggb.", "pppppppp", "PPPPPPPP", ".k....k.", "........"],
				["r": 0xC83A3A, "g": 0x4E9A3E, "b": 0x3A6AA8, "p": 0xC89B5E, "P": 0x8F6732, "k": 0x5A5A5A])
	case .bookshelf:
		return (["wwwwwwww", "wrgbywbw", "wrgbyrbw", "wwwwwwww", "wbyrgwrw", "wbyrgbrw", "wwwwwwww", "w......w"],
				["w": 0x7A5230, "r": 0xB83A3A, "g": 0x3E8A4E, "b": 0x3A5AA8, "y": 0xD8B040])
	case .floorLamp:
		return (["..yyyy..", ".yYYYYy.", ".yyyyyy.", "...ss...", "...ss...", "...ss...", "..ssss..", ".ssssss."],
				["y": 0xE8C060, "Y": 0xFFF2B0, "s": 0x4A4A52])
	case .sofa:
		return (["........", "bbbbbbbb", "BbbbbbbB", "aBccccBa", "aBCCCCBa", "aaaaaaaa", "l......l", "........"],
				["b": 0x4A7AB8, "B": 0x3A6AA8, "a": 0x2E5A90, "c": 0x5A8AC8, "C": 0x4A7AB8, "l": 0x5E3E22])
	case .stairWoodR, .stairWoodL:
		let r: [String] = ["....tttt", "....pppp", "....pppp", "....PPPP", "tttttttt", "pppppppp", "pppppppp", "PPPPPPPP"]
		return (t == .stairWoodR ? r : r.map { String($0.reversed()) }, ["t": 0xE0B47A, "p": 0xC89B5E, "P": 0x8F6732])
	case .stairStoneR, .stairStoneL:
		let r: [String] = ["....tttt", "....sSss", "....ssSs", "....dddd", "tttttttt", "sSssSsss", "ssSsssSs", "dddddddd"]
		return (t == .stairStoneR ? r : r.map { String($0.reversed()) }, ["t": 0xB0B0B0, "s": 0x8A8A8A, "S": 0x9A9A9A, "d": 0x5E5E5E])
	case .stairBrickR, .stairBrickL:
		let r: [String] = ["....tttt", "....bbmb", "....bbmb", "....mmmm", "tttttttt", "bbmbbbmb", "bbmbbbmb", "mmmmmmmm"]
		return (t == .stairBrickR ? r : r.map { String($0.reversed()) }, ["t": 0xD07050, "b": 0xB0503A, "m": 0x8A8070])
	case .liftRail:
		return (["Mm....mM", "Mm....mM", "Mm....mM", "MmxxxxmM", "Mm....mM", "Mm....mM", "Mm....mM", "MmxxxxmM"],
				["M": 0x5A6270, "m": 0x9AA4B0, "x": 0x7A5230])
	case .liftButton:
		return (["........", "..pppp..", "..pUUp..", "..pppp..", "..pDDp..", "..pppp..", "........", "........"],
				["p": 0x4A5260, "U": 0x5AD05A, "D": 0xE05050])
	case .liftCar:
		return (["kkkkkkkk", "k.k..k.k", "k.k..k.k", "k.k..k.k", "k.k..k.k", "k......k", "ffffffff", "FFFFFFFF"],
				["k": 0x5A6270, "f": 0x9AA4B0, "F": 0x4A5260])
	case .sapling:
		// a thin stem with a few young leaves
		return (["........", "...gg...", "..gGgg..", ".gg.bgg.", "..g.b.g.", "....b...", "...bb...", "....b..."],
				["g": 0x4B9A30, "G": 0x7AC84A, "b": 0x7A5230])
	case .exoStation:
		// a gantry with a suit hanging in its clamps
		return (["kkkkkkkk", "k.mmmm.k", "k.mccm.k", "kmmmmmmk", "k.mmmm.k", "k.m..m.k", "ssssssss", "sysyysys"],
				["k": 0x4A5260, "m": 0x9AA4B0, "c": 0x60E0FF, "s": 0x3A3E48, "y": 0xE8C020])
	case .crystalOre:
		// slate with a cluster of pale cyan shards breaking through it
		return (["sSsdsSss", "sdsscCss", "ssscWCds", "sSccWCcs", "dscWCcss", "ssCcsdSs", "sSsssscs", "dsSdsssS"],
				["s": 0x5E6678, "S": 0x6D7688, "d": 0x4F5666, "c": 0x3AA8B0, "C": 0x8AF0E8, "W": 0xE8FFFF])
	case .birchLog, .birchLogBlock:
		return (["lwwwwwws", "lwwkkwws", "lwwwwwws", "lwwwwwws", "lkwwwwks", "lwwwwwws", "lwwwkkws", "lwwwwwws"],
				["l": 0xF4F2EA, "w": 0xE2DED2, "k": 0x3A3632, "s": 0xB8B4A8])
	// the newer ores each get their own shape, not just a colour, so they read at a glance in a dark cave
	case .tin:
		// rounded pale nuggets with a bright glint
		return (["sSsdssSs", "sttsSdss", "tWTtssds", "sTTsdttS", "ssdsTWTs", "dSsstTTs", "stTssdss", "sTWsSssd"],
				["s": 0x8A8A8A, "S": 0x9A9A9A, "d": 0x6A6A6A, "t": 0xAEB8C2, "T": 0xC8D2DA, "W": 0xF2F6FA])
	case .saltpeter:
		// a white crust in feathery streaks along the bedding of the rock
		return (["sSswwsds", "swwWwsss", "ssssdSss", "dsswwwWs", "sSwWwsss", "sssssdss", "swwwSsds", "sSdwWwws"],
				["s": 0x8A8A8A, "S": 0x9A9A9A, "d": 0x6A6A6A, "w": 0xDCD8CC, "W": 0xFFFFFF])
	case .silver:
		// thin bright veins with sparkling points
		return (["sSssdsvW", "ssdssvvs", "sSsvvsSs", "dsvvssds", "svvsSsss", "vWsssdss", "vssdsSsv", "sSdsssvW"],
				["s": 0x7E8088, "S": 0x92949C, "d": 0x62646C, "v": 0xC4CCD8, "W": 0xFFFFFF])
	case .amethyst:
		// violet crystal points growing out of a hollow in the rock
		return (["sSsdssSs", "ssdsaSss", "sSsaAads", "dsaAWAas", "saAWAAas", "aAAAaAAa", "dsSssdSs", "sSdssSsd"],
				["s": 0x8A8A8A, "S": 0x9A9A9A, "d": 0x6A6A6A, "a": 0x7A3CBC, "A": 0xB07AE8, "W": 0xEEDCFF])
	case .rail:
		return (["........", "........", "........", "........", "........", "........", "rrrrrrrr", "t.t..t.t"],
				["r": 0x9A9EA8, "t": 0x6A4A26])
	case .crate:
		return (["pppppppp", "pPddddPp", "pdPddPdp", "pddPPddp", "pddPPddp", "pdPddPdp", "pPddddPp", "pppppppp"],
				["p": 0x7A5628, "P": 0xA97B45, "d": 0xC89B5E])
	case .oreCart:
		return (["........", "........", "..oyoc..", "mmmmmmmm", "mMMMMMMm", "mMMMMMMm", ".kk..kk.", ".kk..kk."],
				["m": 0x4A4E58, "M": 0x6A6E78, "o": 0xD2793A, "y": 0xC8D2DA, "c": 0x2A2A2E, "k": 0x2A2A2E])
	// weather devices: each reads at a glance (cups on a station, a dish on the Doppler, a horn and
	// beacon on the siren); their moving parts are drawn live over the tile
	case .weatherStation:
		return ([".c...c..", ".ccpcc..", "...p....", "bbbbbbbb", "bkkkkkkb", "bkGgGgkb", "bbbbbbbb", "bb....bb"],
				["c": 0xC8CCD4, "p": 0x8A8E98, "b": 0x8F6732, "k": 0x1A2A2A, "G": 0x60E0A0, "g": 0x2A8A5A])
	case .dopplerStation:
		return (["..dddd..", ".dDDDDd.", "...pp...", "mmmmmmmm", "mkkkkkkm", "mkRgRgkm", "mmmmmmmm", "mm....mm"],
				["d": 0xE0E4EA, "D": 0x9AA0AC, "p": 0x6A6E78, "m": 0x5A6470, "k": 0x10181C, "R": 0xFF5050, "g": 0x60E0A0])
	case .stormSiren:
		return (["...rr...", "..rRRr..", "..mmmm..", "hHmmmmHh", "hHmmmmHh", "...pp...", "...pp...", "..bbbb.."],
				["r": 0xC02020, "R": 0xFF6060, "m": 0x8A8E98, "h": 0x6A6E78, "H": 0xA8AEB8, "p": 0x5A5E68, "b": 0x3A3E48])
	case .lightningRod:
		return (["...yy...", "...oo...", "...oO...", "...oO...", "...oO...", "...oO...", "..bbbb..", ".bbbbbb."],
				["y": 0xFFE8A0, "o": 0xD2793A, "O": 0xA85A28, "b": 0x5A5E68])
	case .windTurbine:
		return (["..nnnn..", "..nNNn..", "...pp...", "...pp...", "...pp...", "...pp...", "...pp...", "..bbbb.."],
				["n": 0xE8ECF0, "N": 0xC8CCD4, "p": 0xD8DCE2, "b": 0x6A6E78])
	case .rainBarrel:
		return (["........", ".kddddk.", ".bBbbBb.", ".hhhhhh.", ".bBbbBb.", ".bBbbBb.", ".hhhhhh.", ".bBbbBb."],
				["k": 0x5A3A1A, "d": 0x2A1A0E, "b": 0x8F6732, "B": 0xB98A4E, "h": 0x5A5E68])
	case .rainCistern:
		return (["mmmmmmmm", "mkkkkkkm", "mSSSSSSm", "mSsSSsSm", "mSSSSSSm", "mSsSSsSm", "mSSSSSSm", "mmmmmmmm"],
				["m": 0x5A5E68, "k": 0x1A1A20, "S": 0x8A8A8A, "s": 0x7A7A7A])
	case .weatherVane:
		return (["........", "........", "...yy...", "...pp...", "..cpPc..", "...pp...", "...pp...", "..bbbb.."],
				["y": 0xFFE8A0, "p": 0xA85A28, "P": 0xD2793A, "c": 0xD2793A, "b": 0x5A5E68])
	case .heater:
		return (["...pp...", "...pp...", "mmmmmmmm", "mkooookm", "mkOyOokm", "mkooookm", "mmmmmmmm", "m.m..m.m"],
				["p": 0x4A4E58, "m": 0x5A5E68, "k": 0x2A2A2E, "o": 0xE05818, "O": 0xFFA030, "y": 0xFFE680])
	case .sandbag:
		return (["tTTttTTt", "tttttttt", "dttdtttd", "TTttTTtt", "tttttttt", "tdtttdtt", "tTTttTTt", "tttttttt"],
				["t": 0xB8A070, "T": 0xD2BC8A, "d": 0x8A7448])
	case .shutterClosed:
		return (["ffffffff", "fsSsSsSf", "fssssssf", "fsSsSsSf", "fssssssf", "fsSsSsSf", "fssssssf", "ffffffff"],
				["f": 0x4A4E58, "s": 0x6A7A5A, "S": 0x8A9A72])
	case .shutterOpen:
		return (["ff......", "fs......", "fS......", "fs......", "fS......", "fs......", "fS......", "ff......"],
				["f": 0x4A4E58, "s": 0x6A7A5A, "S": 0x8A9A72])
	case .stormBrick:
		return (["iiiiiiii", "bbbkbbbk", "bbbkbbbk", "kkkkkkkk", "bkbbbkbb", "bkbbbkbb", "iiiiiiii", "bbbkbbbk"],
				["i": 0x9AA0AC, "b": 0x6A6E78, "k": 0x4A4E58])
	case .shingles:
		return (["rRrrRrrR", "rrrrrrrr", "kkkkkkkk", "RrrRrrRr", "rrrrrrrr", "kkkkkkkk", "rRrrRrrR", "rrrrrrrr"],
				["r": 0x7A4A3A, "R": 0x9A6250, "k": 0x4A2A20])
	// Sparkworks: slate casings with copper fittings and teal or amber lights; switch handles, dials,
	// arrows, charge bars and moving parts are drawn live over the tile
	case .crankGen:
		return (["......hH", "...mm.h.", "..mMMmh.", "kmmmmmmk", "kmccccmk", "kmcaacmk", "kmmmmmmk", "kk....kk"],
				["k": 0x2E323A, "m": 0x5A6270, "M": 0x8A94A4, "c": 0xD2793A, "a": 0xFFC020, "h": 0x8A5A2A, "H": 0xC89040])
	case .solarPanel:
		return (["........", "bBbBbBbB", "BbBbBbBb", "bBbBbBbB", "mmmmmmmm", "...pp...", "...pp...", "..mmmm.."],
				["b": 0x1A3A6A, "B": 0x2E62A8, "m": 0x8A94A4, "p": 0x5A6270])
	case .fuelGen:
		return ([".pp.....", ".pp.....", "kkkkkkkk", "kmmmmmmk", "kmrrrrmk", "kmrrrrmk", "kmmmmmmk", "kk....kk"],
				["k": 0x2E323A, "m": 0x5A6270, "r": 0x1A1A1E, "p": 0x6A6E78])
	case .waterWheel:
		return (["..wwww..", ".wWwwWw.", "wWw..wWw", "ww.pp.ww", "ww.pp.ww", "wWw..wWw", ".wWwwWw.", "..wwww.."],
				["w": 0x8F6732, "W": 0xB98A4E, "p": 0x5A5E68])
	case .emberDynamo:
		return (["kkkkkkkk", "kOOOOOOk", "kOeEEeOk", "kOEyyEOk", "kOEyyEOk", "kOeEEeOk", "kOOOOOOk", "kkkkkkkk"],
				["k": 0x16121A, "O": 0x2A1E2E, "e": 0xC04010, "E": 0xFF7020, "y": 0xFFD060])
	case .battery:
		return (["..cccc..", ".kkkkkk.", ".kmmmmk.", ".kmmmmk.", ".kmmmmk.", ".kmmmmk.", ".kmmmmk.", ".kkkkkk."],
				["k": 0x2E323A, "m": 0x4A515E, "c": 0xD2793A])
	case .accumulator:
		return (["kkkkkkkk", "kgGggGgk", "kGtttTGk", "kgtTttgk", "kgtttTgk", "kGTtttGk", "kgGggGgk", "kkkkkkkk"],
				["k": 0x2E323A, "g": 0x5A8A90, "G": 0x8AC8C8, "t": 0x30A0A0, "T": 0x8AF0E8])
	case .powerSwitch:
		return (["........", ".kkkkkk.", ".kmmmmk.", ".km..mk.", ".km..mk.", ".kmmmmk.", ".kkkkkk.", "........"],
				["k": 0x2E323A, "m": 0x6A7280])
	case .breaker:
		return (["kkkkkkkk", "kyykyykk", "kmmmmmmk", "kmk..kmk", "kmk..kmk", "kmkkkkmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "y": 0xE8C020])
	case .powerMeter:
		return ([".kkkkkk.", "kwwwwwwk", "kwnwwwwk", "kwwnwwwk", "kwwwnwwk", "kkkkkkkk", "kmmmmmmk", ".kkkkkk."],
				["k": 0x2E323A, "w": 0xE8E4D8, "n": 0x3A3A40, "m": 0x5A6270])
	case .lever:
		return (["........", "........", "........", "........", "........", "..kkkk..", ".kmmmmk.", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x6A7280])
	case .pushButton:
		return (["........", "........", "..kkkk..", ".kmmmmk.", ".kmBBmk.", ".kmBBmk.", ".kmmmmk.", "..kkkk.."],
				["k": 0x2E323A, "m": 0x6A7280, "B": 0x30B0C0])
	case .pressurePlate:
		return (["........", "........", "........", "........", "........", "........", ".mMMMMm.", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x6A7280, "M": 0x9AA4B4])
	case .pulseTimer:
		return (["kkkkkkkk", "kmwwwwmk", "kwwnwwwk", "kwwnnnwk", "kwwwwwwk", "kmwwwwmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "w": 0xE8E4D8, "n": 0x3A3A40])
	case .repeater:
		return (["........", "........", "kkkkkkkk", "kmmmmmmk", "kmmmmmmk", "kmmmmmmk", "kkkkkkkk", "........"],
				["k": 0x2E323A, "m": 0x5A6270])
	case .inverter:
		return (["........", "........", "kkkkkkkk", "kiiiiiik", "kiiiiiik", "kiiiiiik", "kkkkkkkk", "........"],
				["k": 0x2E323A, "i": 0x6A4A7A])
	case .logicGate:
		return (["........", "kkkkkkkk", "kqqqqqqk", "kqqqqqqk", "kqqqqqqk", "kqqqqqqk", "kkkkkkkk", "........"],
				["k": 0x2E323A, "q": 0x3A6A6A])
	case .motionSensor:
		return (["..gggg..", ".gGggGg.", ".gggggg.", "kkkkkkkk", "kmmmmmmk", "kmmmmmmk", "kkkkkkkk", "........"],
				["k": 0x2E323A, "m": 0x5A6270, "g": 0xC86A3A, "G": 0xF0A070])
	case .daySensor:
		return (["kkkkkkkk", "kssSSssk", "ksSyySsk", "ksSyySsk", "kssSSssk", "kmmmmmmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "s": 0x3A5A8A, "S": 0xE8C040, "y": 0xFFF0A0])
	case .weatherSensor:
		return ([".c...c..", ".ccpcc..", "...p....", "kkkkkkkk", "kmdmmmmk", "kdddmmmk", "kmdmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "c": 0xC8CCD4, "p": 0x8A8E98, "d": 0x3B7BE0])
	case .itemSensor:
		return (["kkkkkkkk", "kmmmmmmk", "kmbbbbmk", "kmbBBbmk", "kmbbbbmk", "kmmmmmmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "b": 0xA97B45, "B": 0xE8C060])
	case .proximitySensor:
		return (["..tttt..", ".t....t.", "t..tt..t", "..t..t..", "...tt...", "kkkkkkkk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "t": 0x30E0D0])
	case .gateClosed:
		return (["kkkkkkkk", "kM.M.M.k", "kM.M.M.k", "kkkkkkkk", "kM.M.M.k", "kM.M.M.k", "kM.M.M.k", "kkkkkkkk"],
				["k": 0x4A515E, "M": 0x9AA4B4])
	case .gateOpen:
		return (["kk....kk", "k......k", "k......k", "k......k", "k......k", "k......k", "k......k", "kk....kk"],
				["k": 0x4A515E])
	case .lampOff:
		return (["kmmmmmmk", "mgggggGm", "mggGgggm", "mgggggGm", "mgGggggm", "mgggggGm", "mggggggm", "kmmmmmmk"],
				["k": 0x2E323A, "m": 0x6A7280, "g": 0x7A8A90, "G": 0x9AAAB0])
	case .lampOn:
		return (["kmmmmmmk", "myyyyyWm", "myyWyyym", "myyyyyWm", "myWyyyym", "myyyyyWm", "myyyyyym", "kmmmmmmk"],
				["k": 0x2E323A, "m": 0x8A94A4, "y": 0xFFF0B0, "W": 0xFFFFFF])
	case .arcTrap:
		return (["cCcCcCcC", "kkkkkkkk", "kmmmmmmk", "kmcmcmck", "kmmmmmmk", "kmcmcmck", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "c": 0xD2793A, "C": 0x8AF0E8])
	case .autoDrill:
		return (["kkkkkkkk", "kmmmmmmk", "kmyyyymk", "kmykkymk", "kmykkymk", "kmyyyymk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "y": 0xE8C020])
	case .conveyor:
		return (["bBbbBbbB", "bbbbbbbb", "kkkkkkkk", "kmRmmRmk", "kRMRRMRk", "kmRmmRmk", "kkkkkkkk", "k......k"],
				["b": 0x2A2A2E, "B": 0x4A4A52, "k": 0x2E323A, "m": 0x5A6270, "R": 0x9AA0AC, "M": 0x6A7280])
	case .collector:
		return (["MMMMMMMM", ".mMMMMm.", "..mMMm..", "kkkkkkkk", "kmmmmmmk", "kmbbbbmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "M": 0x9AA4B4, "b": 0x1A1A1E])
	case .autoCrafter:
		return (["kkkkkkkk", "kmmmmmmk", "kmGmmGmk", "kmmGGmmk", "kmmGGmmk", "kmGmmGmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "G": 0xC8B060])
	case .sumpPump:
		return (["...pp...", "...pp...", "kkkkkkkk", "kmddddmk", "kmdDDdmk", "kmddddmk", "kmmmmmmk", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "p": 0x6A6E78, "d": 0x2A5AB0, "D": 0x5A9AE8])
	case .signalLight:
		return (["........", "..gggg..", ".gGggGg.", ".gggggg.", "..gggg..", "..kkkk..", ".kmmmmk.", "kkkkkkkk"],
				["k": 0x2E323A, "m": 0x5A6270, "g": 0x2A5A5A, "G": 0x4A8A8A])
	default:
		return nil
	}
}

func tileBuf(_ t: Tile) -> PixelBuf {
	if t.isMod {
		let i: Int = Int(t.rawValue - Tile.modBase)
		return ModRuntime.shared.slotArt[i] ?? missingTileBuf()
	}
	var b = PixelBuf(w: 8, h: 8)
	let d: TileDef = t.def
	if d.style == .custom {
		if let cr = customTileRows(t) {
			// always hand back an 8x8 tile: centre narrow art, stand short art on the floor
			let cb: PixelBuf = bufFromRows(cr.0, cr.1)
			var o = PixelBuf(w: 8, h: 8)
			o.blit(cb, (8 - cb.w) / 2, 8 - cb.h)
			return o
		}
		return b
	}
	var rng = RNG(UInt64(t.rawValue) &* 7919 &+ 13)
	let c: [UInt32] = d.colors
	// calmer textures: pixels group into 2x2 clumps and the accent colours sit closer to the base,
	// so terrain reads as surfaces rather than static
	let k1: UInt32 = mixRGB(c[0], c[1], 0.6)
	let k2: UInt32 = mixRGB(c[0], c[2], 0.6)
	let k3: UInt32 = mixRGB(c[0], c[3], 0.5)
	func clump(_ x: Int, _ y: Int) -> Int {
		return Int(hashU(x / 2 + (y / 2) * 5, Int(t.rawValue), 9127) % 100)
	}
	func calm(_ x: Int, _ y: Int, _ r: Int) -> UInt32 {
		let cl: Int = clump(x, y)
		if r < 6 { return k3 }
		if cl < 28 { return k1 }
		if cl > 80 { return k2 }
		return c[0]
	}
	let specks: [(Int, Int)] = [(2, 2), (3, 2), (3, 3), (5, 5), (6, 5), (5, 6), (1, 6), (6, 1)]
	for y in 0..<8 {
		for x in 0..<8 {
			let r: Int = rng.int(100)
			var col: UInt32 = c[0]
			switch d.style {
			case .grassTop:
				if y < 2 { col = r < 60 ? c[0] : c[1] }
				else if y == 2 { col = r < 50 ? c[1] : c[2] }
				else {
					let cl: Int = clump(x, y)
					col = cl < 60 ? c[2] : (cl < 88 ? mixRGB(c[2], c[3], 0.7) : mixRGB(c[2], c[4], 0.7))
				}
			case .log:
				col = (x % 4 == 0) ? c[1] : (r < 20 ? c[2] : c[0])
				if x == 7 { col = c[3] }
			case .leaves:
				col = r < 50 ? c[0] : (r < 80 ? c[1] : (r < 92 ? c[2] : c[3]))
				if r > 95 { b.clear(x, y); continue }
			case .planks:
				col = (y == 3 || y == 7) ? c[1] : (r < 15 ? c[3] : (r < 40 ? c[2] : c[0]))
			case .bricks:
				let off: Int = (y / 4) % 2 == 0 ? 0 : 4
				if y % 4 == 3 || (x + off) % 8 == 7 { col = c[1] }
				else { col = r < 50 ? c[0] : (r < 80 ? c[2] : c[3]) }
			case .glass:
				if x == 0 || y == 0 || x == 7 || y == 7 { col = c[2] }
				else if (x == y && x < 4) || (x == y + 1 && x < 3) { col = c[1] }
				else { continue }
			case .water:
				let base: UInt32 = (y == 0 || r < 10) ? c[3] : (r < 50 ? c[1] : c[0])
				b.px[y * 8 + x] = 0xB0000000 | base
				continue
			case .lava:
				col = r < 25 ? c[3] : (r < 60 ? c[1] : (r < 85 ? c[0] : c[2]))
			case .ore:
				col = calm(x, y, r + 10)
				if specks.contains(where: { $0.0 == x && $0.1 == y }) { col = r < 60 ? c[5] : c[6] }
			case .snow:
				col = calm(x, y, 50)
			case .ice:
				col = r < 50 ? c[0] : (r < 75 ? c[1] : c[2])
				if (x + y) % 6 == 0 { col = c[3] }
				b.px[y * 8 + x] = 0xE0000000 | col
				continue
			case .mud:
				col = calm(x, y, r)
			case .cactus:
				col = (x == 0 || x == 7) ? c[3] : ((x == 3 || x == 4) ? c[2] : c[0])
				if y % 4 == 1 && (x == 1 || x == 6) { col = c[3] }
			case .crystal:
				col = r < 40 ? c[0] : (r < 70 ? c[1] : c[2])
				if (x + y) % 5 == 0 { col = c[3] }
			case .farmland:
				col = (y % 3 == 1) ? c[1] : (r < 40 ? c[2] : c[0])
			case .sandstone:
				col = (y % 3 == 2) ? c[1] : (r < 25 ? c[2] : c[0])
			case .ash:
				col = calm(x, y, r)
			default:
				col = calm(x, y, r)
			}
			b.set(x, y, col)
		}
	}
	return b
}

// ===== p03_items =====

// MARK: - Items

enum Tier: Int, Codable, CaseIterable {
	case wood = 1, stone, copper, iron, gold, diamond, mythril, ember, voidium

	var name: String {
		switch self {
		case .wood: return "Wooden"
		case .stone: return "Stone"
		case .copper: return "Copper"
		case .iron: return "Iron"
		case .gold: return "Golden"
		case .diamond: return "Diamond"
		case .mythril: return "Mythril"
		case .ember: return "Ember"
		case .voidium: return "Voidium"
		}
	}
	var armorName: String { return self == .wood ? "Leather" : name }
	var color: UInt32 {
		switch self {
		case .wood: return 0xB98A4E
		case .stone: return 0x8E8E96
		case .copper: return 0xD2793A
		case .iron: return 0xD0D4DA
		case .gold: return 0xF5D142
		case .diamond: return 0x4FE3E8
		case .mythril: return 0x8A7CFF
		case .ember: return 0xFF6A1E
		case .voidium: return 0xB04CFF
		}
	}
	var mineSpeed: Double {
		let t: [Double] = [1, 2.0, 3.2, 4.2, 5.5, 7.0, 9.0, 12.0, 16.0, 22.0]
		return t[rawValue]
	}
	var damage: Double {
		let t: [Double] = [2, 4, 5.5, 6.5, 8.5, 10, 14, 19, 26, 36]
		return t[rawValue]
	}
	/// armour points of one piece (times the slot's share: a full set is three times this). Each point
	/// takes 4% off a blow, at most 80%: a full leather set 19%, iron 41%, diamond 55%, voidium 80%
	var defense: Double {
		let t: [Double] = [0, 1.6, 2.0, 2.6, 3.4, 3.8, 4.6, 5.4, 6.2, 7.0]
		return t[rawValue]
	}
}

enum ToolType: Int, Codable, CaseIterable {
	case pickaxe, axe, shovel, hoe
	var name: String {
		switch self {
		case .pickaxe: return "Pickaxe"
		case .axe: return "Axe"
		case .shovel: return "Shovel"
		case .hoe: return "Hoe"
		}
	}
}

enum ArmorSlot: Int, Codable, CaseIterable {
	case head, chest, legs
	var name: String {
		switch self {
		case .head: return "Helmet"
		case .chest: return "Chestplate"
		case .legs: return "Leggings"
		}
	}
	var weight: Double {
		switch self {
		case .head: return 0.8
		case .chest: return 1.3
		case .legs: return 0.9
		}
	}
}

enum Mat: Int, Codable, CaseIterable {
	case stick, coal, copperOre, ironOre, goldOre, mythrilOre, diamond, emberOre, voidOre
	case copperBar, ironBar, goldBar, mythrilBar, emberBar, voidBar
	case string, leather, bone, feather, wool, gunpowder, seeds, claw, tusk, fur
	/// rare: crystal grottos, relic chests in ruins, and the Hollow Warden's heart
	case crystalShard, relicFragment, umbralHeart
	/// appended: tin (alloyed with copper into bronze), saltpeter for powder and fire, silver, amethyst
	case tinOre, bronzeBar, saltpeter, silverOre, silverBar, amethyst
	/// appended: alchemy (vials and water, herbs, creature parts, storm essence) and rare relics of golems,
	/// the Crystal Sentinel and mutated creatures
	case vial, waterVial, sunleaf, glowcap, slimeGel, venomSac, frostCrystal, emberAsh, wraithDust, stormEssence, golemCore, sentinelLens, mutantGland

	var name: String {
		switch self {
		case .vial: return "Empty Vial"
		case .waterVial: return "Water Vial"
		case .sunleaf: return "Sunleaf"
		case .glowcap: return "Glowcap"
		case .slimeGel: return "Slime Gel"
		case .venomSac: return "Venom Sac"
		case .frostCrystal: return "Frost Crystal"
		case .emberAsh: return "Ember Ash"
		case .wraithDust: return "Wraith Dust"
		case .stormEssence: return "Storm Essence"
		case .golemCore: return "Golem Core"
		case .sentinelLens: return "Sentinel Lens"
		case .mutantGland: return "Mutant Gland"

		case .tinOre: return "Tin Ore"
		case .bronzeBar: return "Bronze Bar"
		case .saltpeter: return "Saltpeter"
		case .silverOre: return "Silver Ore"
		case .silverBar: return "Silver Bar"
		case .amethyst: return "Amethyst Shard"
		case .stick: return "Stick"
		case .coal: return "Coal"
		case .copperOre: return "Copper Ore"
		case .ironOre: return "Iron Ore"
		case .goldOre: return "Gold Ore"
		case .mythrilOre: return "Mythril Ore"
		case .diamond: return "Diamond"
		case .emberOre: return "Ember Ore"
		case .voidOre: return "Voidium Ore"
		case .copperBar: return "Copper Bar"
		case .ironBar: return "Iron Bar"
		case .goldBar: return "Gold Bar"
		case .mythrilBar: return "Mythril Bar"
		case .emberBar: return "Ember Bar"
		case .voidBar: return "Voidium Bar"
		case .string: return "String"
		case .leather: return "Leather"
		case .bone: return "Bone"
		case .feather: return "Feather"
		case .wool: return "Wool"
		case .gunpowder: return "Gunpowder"
		case .seeds: return "Seeds"
		case .claw: return "Claw"
		case .tusk: return "Tusk"
		case .fur: return "Thick Fur"
		case .crystalShard: return "Crystal Shard"
		case .relicFragment: return "Relic Fragment"
		case .umbralHeart: return "Umbral Heart"
		}
	}

	/// what the material is good for, for its tooltip
	var use: String {
		switch self {
		case .coal: return "Fuel for smelting; torches; gunpowder"
		case .copperOre, .ironOre, .goldOre, .mythrilOre, .emberOre, .voidOre, .silverOre: return "Smelt it into bars in a furnace"
		case .tinOre: return "Smelt with copper ore into bronze"
		case .bronzeBar: return "Crossbows, bolts, maces, lanterns, rails"
		case .saltpeter: return "Strong gunpowder and fire flasks"
		case .silverBar: return "Silver charm, storm rod"
		case .amethyst: return "Amethyst blocks, headlamps, the storm rod"
		case .copperBar, .ironBar, .goldBar, .mythrilBar, .emberBar, .voidBar: return "Tools, weapons and armour"
		case .crystalShard, .relicFragment, .umbralHeart: return "Rare crafting material"
		case .vial: return "Tap water with it to fill it"
		case .waterVial: return "The base of every potion and compound"
		case .sunleaf: return "Herb: from tall grass and flowers"
		case .glowcap: return "Cave mushroom: from mushrooms and bats"
		case .slimeGel: return "From slimes"
		case .venomSac: return "From scorpions and crawlers"
		case .frostCrystal: return "From ice, snow and polar bears"
		case .emberAsh: return "From Umbral creatures"
		case .wraithDust: return "From wraiths"
		case .stormEssence: return "Left where lightning strikes (a rod catches more)"
		case .golemCore: return "From golems: cores, Quarry, Thrift"
		case .sentinelLens: return "From the Crystal Sentinel: the rarest work"
		case .mutantGland: return "From mutated creatures: cheaper mutagen"
		default: return "Crafting material"
		}
	}
}

enum Food: Int, Codable, CaseIterable {
	case apple, rawMeat, cookedMeat, rawFish, cookedFish, wheat, bread, carrot
	var name: String {
		switch self {
		case .apple: return "Apple"
		case .rawMeat: return "Raw Meat"
		case .cookedMeat: return "Steak"
		case .rawFish: return "Raw Fish"
		case .cookedFish: return "Cooked Fish"
		case .wheat: return "Wheat"
		case .bread: return "Bread"
		case .carrot: return "Carrot"
		}
	}
	var hunger: Double {
		switch self {
		case .apple: return 3
		case .rawMeat: return 2
		case .cookedMeat: return 8
		case .rawFish: return 2
		case .cookedFish: return 6
		case .wheat: return 1
		case .bread: return 6
		case .carrot: return 3
		}
	}
	var heal: Double {
		switch self {
		case .cookedMeat: return 3
		case .cookedFish: return 2
		case .bread: return 1
		default: return 0
		}
	}
}

/// Weapons that are loaded and then fired with a tap: firearms, bolt throwers and the storm rod. Each
/// keeps its loaded shots in the stack's `extra`.
enum GunType: Int, Codable, CaseIterable {
	case pistol, rifle
	/// appended (saved numbers stay valid): a bolt thrower and its heavy upgrade, a scattergun, a rare
	/// repeating crossbow, and a rod whose charge of lightning refills on its own
	case crossbow, arbalest, blunderbuss, repeater, stormRod
	var name: String {
		switch self {
		case .pistol: return "Flintlock Pistol"
		case .rifle: return "Long Rifle"
		case .crossbow: return "Crossbow"
		case .arbalest: return "Heavy Crossbow"
		case .blunderbuss: return "Blunderbuss"
		case .repeater: return "Prospector's Repeater"
		case .stormRod: return "Storm Rod"
		}
	}
	/// damage of one shot (one pellet for the blunderbuss, the first strike for the storm rod)
	var damage: Double {
		switch self {
		case .pistol: return 9
		case .rifle: return 24
		case .crossbow: return 15
		case .arbalest: return 26
		case .blunderbuss: return 4.5
		case .repeater: return 11
		case .stormRod: return 12
		}
	}
	var cooldown: Double {
		switch self {
		case .pistol: return 0.32
		case .rifle: return 0.85
		case .crossbow, .arbalest, .blunderbuss: return 0.2
		case .repeater: return 0.2
		case .stormRod: return 0.5
		}
	}
	var magazine: Int {
		switch self {
		case .pistol: return 6
		case .rifle: return 4
		case .crossbow, .arbalest, .blunderbuss: return 1
		case .repeater: return 5
		case .stormRod: return 5
		}
	}
	var reloadTime: Double {
		switch self {
		case .pistol: return 1.3
		case .rifle: return 2.2
		case .crossbow: return 0.85
		case .arbalest: return 1.35
		case .blunderbuss: return 1.7
		case .repeater: return 2.0
		case .stormRod: return 2.5
		}
	}
	var speed: Double {
		switch self {
		case .pistol: return 34
		case .rifle: return 48
		case .crossbow: return 42
		case .arbalest: return 50
		case .blunderbuss: return 30
		case .repeater: return 40
		case .stormRod: return 0
		}
	}
	/// what a reload takes from the bag (the storm rod recharges by itself instead)
	var ammo: AmmoType? {
		switch self {
		case .pistol, .rifle, .blunderbuss: return .bullet
		case .crossbow, .arbalest, .repeater: return .bolt
		case .stormRod: return nil
		}
	}
	/// creatures each shot may pass through before it stops
	var pierce: Int {
		switch self {
		case .rifle, .crossbow: return 1
		case .arbalest: return 2
		default: return 0
		}
	}
	/// downward pull on the shot (bolts drop a little; bullets fly straight)
	var gravity: Double {
		switch self {
		case .crossbow, .repeater: return 6
		case .arbalest: return 4
		default: return 0
		}
	}
	/// how long a shot flies before it is spent (sets the range)
	var shotLife: Double {
		switch self {
		case .blunderbuss: return 0.3
		case .crossbow, .arbalest, .repeater: return 2.0
		default: return 1.6
		}
	}
	var knock: Double {
		switch self {
		case .arbalest: return 8
		case .blunderbuss: return 3.2
		case .crossbow, .repeater: return 5
		default: return 4
		}
	}
	/// heavy weapons need a fresh press for every shot; the rest keep firing while held
	var needsPress: Bool { return self == .rifle || self == .arbalest || self == .blunderbuss }
	var isFirearm: Bool { return self == .pistol || self == .rifle || self == .blunderbuss }
	var isBoltThrower: Bool { return self == .crossbow || self == .arbalest || self == .repeater }
}

enum AmmoType: Int, Codable, CaseIterable {
	case arrow, bullet
	/// crossbow bolts (appended)
	case bolt
	var name: String {
		switch self {
		case .arrow: return "Arrow"
		case .bullet: return "Bullet"
		case .bolt: return "Crossbow Bolt"
		}
	}
}

/// The club family: crude blunt weapons whose blows leave foes dazed for a moment
enum ClubKind: Int, Codable, CaseIterable {
	case wooden, studded, mace
	var name: String {
		switch self {
		case .wooden: return "Wooden Club"
		case .studded: return "Studded Club"
		case .mace: return "Bronze Mace"
		}
	}
	var damage: Double {
		switch self {
		case .wooden: return 5
		case .studded: return 7.5
		case .mace: return 11
		}
	}
	var daze: Double {
		switch self {
		case .wooden: return 0.45
		case .studded: return 0.55
		case .mace: return 0.7
		}
	}
}

/// One-of-a-kind weapons. They are never crafted: they turn up, rarely, in the deeper and better
/// hidden chests of old mines, grottos and lairs.
enum Relic: Int, Codable, CaseIterable {
	case moonDagger, emberCleaver, quakeMaul
	var name: String {
		switch self {
		case .moonDagger: return "Moonsilver Dagger"
		case .emberCleaver: return "Ember Cleaver"
		case .quakeMaul: return "Quake Maul"
		}
	}
}

enum PartType: Int, Codable, CaseIterable {
	case frame, wheel, engine, steering, seat, fuelTank, hull, propeller, paddle, drill, diamondDrill
	/// appended (saved part numbers stay valid): a heavy wheel that pulls harder, a lamp that lights the
	/// way ahead while driving, a crate that carries 27 stacks, and a drill that bores through anything
	case offroadWheel, headlight, cargo, voidDrill
	var name: String {
		switch self {
		case .frame: return "Vehicle Frame"
		case .wheel: return "Wheel"
		case .engine: return "Engine"
		case .steering: return "Steering Wheel"
		case .seat: return "Seat"
		case .fuelTank: return "Fuel Tank"
		case .hull: return "Hull Float"
		case .propeller: return "Propeller"
		case .paddle: return "Paddle"
		case .drill: return "Iron Drill"
		case .diamondDrill: return "Diamond Drill"
		case .offroadWheel: return "Offroad Wheel"
		case .headlight: return "Headlight"
		case .cargo: return "Cargo Crate"
		case .voidDrill: return "Void Drill"
		}
	}
	var mass: Double {
		switch self {
		case .frame: return 1.0
		case .wheel: return 0.6
		case .engine: return 2.0
		case .steering: return 0.3
		case .seat: return 0.5
		case .fuelTank: return 1.2
		case .hull: return 0.8
		case .propeller: return 0.5
		case .paddle: return 0.3
		case .drill: return 1.6
		case .diamondDrill: return 1.8
		case .offroadWheel: return 1.1
		case .headlight: return 0.3
		case .cargo: return 1.0
		case .voidDrill: return 2.0
		}
	}

	/// what the part does, for its tooltip
	var role: String {
		switch self {
		case .wheel: return "Goes under the body. Two or more, plus an engine, drive on land."
		case .offroadWheel: return "A heavier wheel that pulls harder up slopes and over rough ground."
		case .headlight: return "Lights the way ahead while someone is driving."
		case .cargo: return "Tap it to store up to 27 stacks; they travel with the vehicle."
		case .drill, .diamondDrill, .voidDrill: return "Bores through blocks in front of it while the engine runs."
		default: return "Vehicle part"
		}
	}
}

func isWheelPart(_ p: PartType) -> Bool { return p == .wheel || p == .offroadWheel }

/// Equipment worn in the two gear slots
enum Gear: Int, Codable, CaseIterable {
	case headlamp, swiftBoots, divingMask, emberCharm, wardenSigil
	/// appended: a silver ward against the restless dead
	case silverCharm
	/// appended: warm clothes against the cold, and boots that grip snow and ice
	case winterCoat, snowBoots
	var name: String {
		switch self {
		case .winterCoat: return "Winter Coat"
		case .snowBoots: return "Snow Boots"
		case .headlamp: return "Headlamp"
		case .swiftBoots: return "Swift Boots"
		case .divingMask: return "Diving Mask"
		case .emberCharm: return "Ember Charm"
		case .wardenSigil: return "Warden's Sigil"
		case .silverCharm: return "Silver Charm"
		}
	}
	var effect: String {
		switch self {
		case .headlamp: return "Lights the way around you"
		case .swiftBoots: return "Run 18% faster"
		case .divingMask: return "Hold your breath three times as long"
		case .emberCharm: return "Lava and fire hurt far less"
		case .wardenSigil: return "Hit 20% harder, take 15% less damage"
		case .silverCharm: return "The undead hit you 25% softer; you hit them 25% harder"
		case .winterCoat: return "Keeps out most of the cold of a blizzard"
		case .snowBoots: return "No slipping on snow and ice, no sinking in deep snow"
		}
	}
}

enum Gadget: Int, Codable, CaseIterable {
	case shears, wrench, treasureMap, portalKey, carKit, boatKit, motorboatKit, bomb
	/// appended: a thrown flask that bursts into a patch of fire
	case fireFlask
	/// appended: a pocket barometer, and a flask of rainwater from a rain barrel
	case barometer, waterFlask
	/// Sparkworks (appended): spools of power cable and pulse wire (two colours), snips that take wire
	/// back up, and the probe that reads and sets up devices and networks
	case powerCable, pulseWire, pulseWireB, wireSnips, probe

	/// a wiring tool: taps lay or cut wire instead of using what is under them
	var wiring: Bool { return self == .powerCable || self == .pulseWire || self == .pulseWireB || self == .wireSnips }
	/// the wire layer a spool lays (0 power, 1 amber pulse, 2 teal pulse)
	var wireLayer: Int { return self == .powerCable ? 0 : (self == .pulseWire ? 1 : 2) }

	var name: String {
		switch self {
		case .powerCable: return "Power Cable"
		case .pulseWire: return "Pulse Wire (amber)"
		case .pulseWireB: return "Pulse Wire (teal)"
		case .wireSnips: return "Wire Snips"
		case .probe: return "Spark Probe"
		case .barometer: return "Barometer"
		case .waterFlask: return "Water Flask"
		case .fireFlask: return "Fire Flask"
		case .shears: return "Shears"
		case .wrench: return "Wrench"
		case .treasureMap: return "Treasure Map"
		case .portalKey: return "Portal Key"
		case .carKit: return "Car Kit"
		case .boatKit: return "Rowboat Kit"
		case .motorboatKit: return "Motorboat Kit"
		case .bomb: return "Bomb"
		}
	}
}

/// The shape of a melee swing (drives the hit test, the animation and the trail)
enum SwingStyle: Int {
	case slash, thrust, smash, stab, bash
}

/// How a melee weapon strikes. One table drives the hit test, the timing, the animation and the
/// effects, so a weapon reaches exactly as far and as wide whether the player taps a foe, holds the
/// attack stick or swings at empty air.
struct MeleeProfile {
	var damage: Double
	var cooldown: Double
	/// from the shoulder to the near edge of a target
	var reach: Double
	/// half the angle swept either side of the aim (radians)
	var halfArc: Double
	var style: SwingStyle = .slash
	/// thrusts hit along a straight band this wide instead of an arc
	var band: Double = 0.55
	var maxHits: Int = 99
	var knock: Double = 6
	/// a crushing blow: breaks raised guards and cracks stone hides
	var heavy: Bool = false
	/// seconds a struck foe is left dazed (clubs)
	var daze: Double = 0
	/// the blow lands this long after the swing starts (heavy weapons)
	var windup: Double = 0
	var swingTime: Double = 0.25
	/// run speed while the swing lasts (heavy weapons commit you to the blow)
	var moveScale: Double = 1.0
	var critChance: Double = 0.1
	/// seconds of fire a hit sets on the target
	var burn: Double = 0
	var undeadMult: Double = 1
	/// every third blow in a quick run lands twice as hard
	var combo: Bool = false
	/// multiplier for a blow into a foe's back
	var backstab: Double = 1
	/// the blow sends a shockwave along the ground
	var shockwave: Bool = false
	var trail: UInt32 = 0xFFFFFF
}

enum Item: Hashable, Codable {
	case block(Tile)
	case tool(ToolType, Tier)
	case sword(Tier)
	case armor(ArmorSlot, Tier)
	case mat(Mat)
	case food(Food)
	case bow
	case gun(GunType)
	case ammo(AmmoType)
	case part(PartType)
	case gadget(Gadget)
	case wall(Int)
	/// long reach, a quick thrust that runs through two foes in a line
	case spear(Tier)
	/// slow and heavy: big knockback, smashes guards and stone hides
	case hammer(Tier)
	case gear(Gear)
	/// appended: quick stabs at close range, every third in a run hits twice as hard, cuts deep from behind
	case knife(Tier)
	/// cheap blunt weapons that daze
	case club(ClubKind)
	/// slings stones (any rock in the bag) in a lob that knocks foes back
	case sling
	/// one of a kind, found and never made
	case relic(Relic)
	/// appended: an item from a player's mod ("mod:id"); see ModRuntime
	case custom(String)
	/// appended: potions, infusion compounds, and the exosuit's parts, plates, cores and modules
	case potion(Potion)
	case compound(Infusion)
	case exoPart(ExoPart, ExoMat)
	case exoPlate(ExoMat)
	case exoCore(ExoCore)
	case exoModule(ExoModule)

	/// Order used by inventory sorting: gear first, then building blocks, materials and the rest
	var sortGroup: Int {
		switch self {
		case .sword, .spear, .hammer, .knife, .club, .relic: return 0
		case .gear: return 4
		case .bow, .gun, .sling: return 1
		case .ammo: return 2
		case .tool: return 3
		case .armor: return 4
		case .food: return 5
		case .gadget: return 6
		case .part: return 7
		case .block: return 8
		case .wall: return 9
		case .mat: return 10
		case .custom(let k): return ModRuntime.shared.item(k)?.sortGroup ?? 10
		case .potion: return 5
		case .compound: return 6
		case .exoPart, .exoPlate, .exoCore, .exoModule: return 4
		}
	}

	/// The bag's filter groups (see ItemBrowser.groups): 0 blocks, 1 tools, 2 weapons and ammunition,
	/// 3 armour and suit parts, 4 materials, 5 food and potions, 6 everything else
	var bagGroup: Int {
		switch sortGroup {
		case 0, 1, 2: return 2
		case 3: return 1
		case 4: return 3
		case 5: return 5
		case 8, 9: return 0
		case 10: return 4
		default: return 6
		}
	}

	/// Short description lines for tooltips: what the weapon is for, then its numbers
	var infoLines: [String] {
		switch self {
		case .sword, .spear, .hammer, .knife, .club, .relic:
			let p: MeleeProfile = melee
			var lines: [String] = [weaponBlurb]
			lines.append(String(format: "Damage %.1f · every %.2f s", p.damage, p.cooldown))
			let reachS: String = String(format: "Reach %.1f", p.reach)
			let hits: String = p.maxHits >= 99 ? "hits all in the arc" : (p.maxHits == 1 ? "one foe" : "up to \(p.maxHits) foes")
			lines.append(reachS + " · " + hits)
			return lines
		case .gear(let g): return ["Gear: wear it in a gear slot", g.effect]
		case .tool(let k, let t): return [k.name + " (tool)", String(format: "Mining speed x%.1f", t.mineSpeed), "Tier \(t.rawValue)"]
		case .armor(let s, let t): return [s.name + " armour", String(format: "Defense +%.1f", t.defense * s.weight)]
		case .food(let f): return ["Food", String(format: "Restores %.0f hunger", f.hunger), f.heal > 0 ? String(format: "Heals %.0f", f.heal) : "Eat to recover"]
		case .bow: return ["Bow: hold to draw, release to fire", "Damage 5-14 · arcing shots", "Uses arrows"]
		case .sling: return ["Sling: tap to throw a stone in a lob", "Damage 4.5 · every 0.55 s · big knockback", "Uses any stone or slate you carry"]
		case .gun(let g):
			var lines: [String] = [weaponBlurb]
			if g == .blunderbuss {
				lines.append(String(format: "7 pellets x %.1f · reload %.1f s", g.damage, g.reloadTime))
			} else if g == .stormRod {
				lines.append(String(format: "Damage %.0f, then leaps to 3 more · %d charges", g.damage, g.magazine))
			} else {
				lines.append(String(format: "Damage %.0f · %d loaded · reload %.1f s", g.damage, g.magazine, g.reloadTime))
			}
			if let a = g.ammo { lines.append("Uses " + a.name.lowercased() + "s") } else { lines.append("Recharges by itself") }
			return lines
		case .ammo: return ["Ammunition"]
		case .part(let p): return [p.role, String(format: "Mass %.1f", p.mass)]
		case .gadget(let g):
			if g == .fireFlask { return ["Throw it: bursts into fire that burns", "everything standing in it"] }
			if g == .bomb { return ["Throw it: explodes after a moment", "Breaks blocks"] }
			if g == .barometer { return ["Hold it to read the air pressure", "Falling fast: a storm is coming"] }
			if g == .waterFlask { return ["Rainwater: pour it on a young crop", "to help it grow, or on a fire"] }
			if g == .powerCable { return ["Carries power from generators", "to batteries and machines: drag to lay"] }
			if g == .pulseWire || g == .pulseWireB { return ["Carries on/off pulses from switches,", "sensors and logic to machines: drag to lay"] }
			if g == .wireSnips { return ["Drag over wire to take it back up"] }
			if g == .probe { return ["Tap a device to set it up, or a wire", "to see its whole network and its power"] }
			return ["Gadget: use it from the hotbar"]
		case .block(.sapling): return ["Plant it on grass, dirt or snow", "It grows into a tree that suits the land"]
		case .block(let t) where furnitureBlurb(t) != nil: return [furnitureBlurb(t) ?? "", weightLine(t)]
		case .block(let t): return [t.solid ? "Building block" : "Placeable", t.light > 0 ? "Gives light" : (t.hardness >= 99 ? "Unbreakable" : String(format: "Hardness %.1f", t.hardness)), weightLine(t)]
		case .wall: return ["Background wall"]
		case .mat(let m): return [m.use]
		case .custom(let k): return ModRuntime.shared.item(k)?.infoLines ?? ["From a mod that is not installed", "Kept safe until the mod is back"]
		case .potion(let p): return [p.useLine, p.blurb, p.rarity.name]
		case .compound(let i):
			let goes: [String] = i.classes.map { $0.name }
			return ["Infusion compound: work it in at an Infusion Crucible", i.blurb, joinText("Goes on ", goes.joined(separator: " or "), " · ", i.rarity.name)]
		case .exoPart(let p, let m):
			return [joinText("Suit part (", m.special.lowercased(), ")"), String(format: "Defence %.1f · weight %.1f", p.baseDefense * m.protect, p.baseWeight * m.weight), p == .chestFrame ? joinText(String(m.sockets), " module sockets") : "Fit it at an Assembly Station"]
		case .exoPlate(let m): return ["Armour plate: fits any plate place on a suit", String(format: "Guards x%.1f · weight %.1f", m.protect, 2.0 * m.weight), m.special]
		case .exoCore(let c): return ["Suit power core", String(format: "Holds %.0f · gives %.0f a second", c.capacity, c.output), String(format: "Refills %.1f a second by itself", c.recharge)]
		case .exoModule(let m):
			let needs: [String] = m.needs.map { $0.name.lowercased() }
			return [m.blurb, needs.isEmpty ? "Needs only the chest frame" : joinText("Needs the ", needs.joined(separator: " and ")), String(format: "Weight %.0f · %@", m.weight, m.rarity.name)]
		}
	}

	/// What a weapon is for, in a line
	var weaponBlurb: String {
		switch self {
		case .sword: return "Sword: quick, even sweeps that hit every foe in front"
		case .spear: return "Spear: long reach, a thrust that runs through two foes"
		case .hammer: return "Hammer: slow and heavy, smashes guards and stone"
		case .knife: return "Knife: fast stabs, every 3rd in a run hits double, deadly from behind"
		case .club: return "Club: cheap blunt blows that leave foes dazed"
		case .relic(let r):
			switch r {
			case .moonDagger: return "Relic knife: the restless dead fall to it twice as fast"
			case .emberCleaver: return "Relic blade: a wide sweep that sets foes ablaze"
			case .quakeMaul: return "Relic maul: its blow sends a quake along the ground"
			}
		case .gun(let g):
			switch g {
			case .pistol: return "Pistol: quick shots, six to a load"
			case .rifle: return "Rifle: a heavy shot that runs through a foe"
			case .crossbow: return "Crossbow: tap to fire a fast, flat bolt"
			case .arbalest: return "Heavy crossbow: a crushing bolt through two foes"
			case .blunderbuss: return "Blunderbuss: a close-range blast of pellets"
			case .repeater: return "Repeater: five bolts in quick succession"
			case .stormRod: return "Storm rod: lightning that leaps between foes"
			}
		default: return name
		}
	}

	var name: String {
		switch self {
		case .block(let t): return t.name
		case .tool(let k, let t): return t.name + " " + k.name
		case .sword(let t): return t.name + " Sword"
		case .spear(let t): return t.name + " Spear"
		case .hammer(let t): return t.name + " War Hammer"
		case .knife(let t): return t.name + " Knife"
		case .club(let k): return k.name
		case .relic(let r): return r.name
		case .sling: return "Sling"
		case .gear(let g): return g.name
		case .armor(let s, let t): return t.armorName + " " + s.name
		case .mat(let m): return m.name
		case .food(let f): return f.name
		case .bow: return "Bow"
		case .gun(let g): return g.name
		case .ammo(let a): return a.name
		case .part(let p): return p.name
		case .gadget(let g): return g.name
		case .wall(let k): return wallName(k)
		case .custom(let k): return ModRuntime.shared.item(k)?.def.name ?? "Missing item"
		case .potion(let p): return p.name
		case .compound(let i): return joinText(i.name, " Compound")
		case .exoPart(let p, let m): return joinText(m.name, " ", p.name)
		case .exoPlate(let m): return joinText(m.name, " Armour Plate")
		case .exoCore(let c): return c.name
		case .exoModule(let m): return m.name
		}
	}

	var maxStack: Int {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.stack ?? 99
		case .potion(let p): return p.maxStack
		case .compound: return 10
		case .block, .mat, .food, .ammo, .wall: return 99
		case .part: return 20
		case .gadget(let g): return g == .bomb ? 30 : (g == .fireFlask ? 20 : (g == .waterFlask ? 10 : ((g == .powerCable || g == .pulseWire || g == .pulseWireB) ? 250 : 1)))
		default: return 1
		}
	}

	var isWeapon: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind.isWeapon ?? false
		case .sword, .spear, .hammer, .knife, .club, .relic, .bow, .gun, .sling: return true
		case .gadget(let g): return g == .bomb || g == .fireFlask
		case .potion(let p): return p.thrown
		default: return false
		}
	}

	/// a hand-held melee weapon (tools are not, though they can still hit)
	var isMeleeWeapon: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind == .melee
		case .sword, .spear, .hammer, .knife, .club, .relic: return true
		default: return false
		}
	}

	var isRanged: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind.isRanged ?? false
		case .bow, .gun, .sling: return true
		case .gadget(let g): return g == .bomb || g == .fireFlask
		case .potion(let p): return p.thrown
		default: return false
		}
	}

	/// How this item strikes when swung, with any change a mod makes to a game weapon or tool
	var melee: MeleeProfile {
		let p: MeleeProfile = baseMelee
		if OverrideRT.shared.items.isEmpty { return p }
		if let o = OverrideRT.shared.items[self] { return o.apply(p) }
		return p
	}

	/// How this item strikes when swung (anything can be swung; weapons are made for it)
	var baseMelee: MeleeProfile {
		switch self {
		case .sword(let t):
			return MeleeProfile(damage: t.damage, cooldown: 0.42, reach: 3.0, halfArc: 1.1, style: .slash, knock: 6, trail: tierShade(t.color, 1.2))
		case .spear(let t):
			return MeleeProfile(damage: t.damage * 0.95, cooldown: 0.48, reach: 3.8, halfArc: 0.25, style: .thrust, band: 0.55, maxHits: 2, knock: 4.5, swingTime: 0.3, trail: tierShade(t.color, 1.2))
		case .hammer(let t):
			return MeleeProfile(damage: t.damage * 1.75, cooldown: 0.8, reach: 2.6, halfArc: 0.95, style: .smash, knock: 11.5, heavy: true, windup: 0.14, swingTime: 0.42, moveScale: 0.55, trail: tierShade(t.color, 1.1))
		case .knife(let t):
			return MeleeProfile(damage: t.damage * 0.48, cooldown: 0.24, reach: 2.0, halfArc: 0.6, style: .stab, maxHits: 1, knock: 3, swingTime: 0.16, critChance: 0.08, combo: true, backstab: 1.5, trail: tierShade(t.color, 1.3))
		case .club(let k):
			return MeleeProfile(damage: k.damage, cooldown: 0.62, reach: 2.5, halfArc: 0.85, style: .bash, maxHits: 2, knock: 8, daze: k.daze, windup: 0.06, swingTime: 0.32, moveScale: 0.8, trail: 0xE8D8B8)
		case .relic(let r):
			switch r {
			case .moonDagger:
				return MeleeProfile(damage: 6.5, cooldown: 0.24, reach: 2.1, halfArc: 0.65, style: .stab, maxHits: 1, knock: 3, swingTime: 0.16, critChance: 0.1, undeadMult: 2.0, combo: true, backstab: 1.6, trail: 0xC8E8FF)
			case .emberCleaver:
				return MeleeProfile(damage: 13, cooldown: 0.5, reach: 3.1, halfArc: 1.3, style: .slash, knock: 7, swingTime: 0.3, burn: 3.0, trail: 0xFF8A30)
			case .quakeMaul:
				return MeleeProfile(damage: 20, cooldown: 0.95, reach: 2.7, halfArc: 1.0, style: .smash, knock: 13, heavy: true, windup: 0.18, swingTime: 0.46, moveScale: 0.5, shockwave: true, trail: 0xE8C878)
			}
		case .tool(let k, let t):
			var d: Double = t.damage * 0.4
			switch k {
			case .axe: d = t.damage * 0.8
			case .pickaxe: d = t.damage * 0.6
			case .shovel: d = t.damage * 0.5
			case .hoe: d = t.damage * 0.4
			}
			return MeleeProfile(damage: d, cooldown: k == .axe ? 0.55 : 0.5, reach: 2.4, halfArc: 0.8, style: .slash, knock: 5, swingTime: 0.25, trail: 0xE0E0E0)
		case .gun, .bow, .sling:
			return MeleeProfile(damage: 2.0, cooldown: 0.4, reach: 1.9, halfArc: 0.7, style: .bash, knock: 4, swingTime: 0.22, trail: 0xD0D0D0)
		case .custom(let k):
			return ModRuntime.shared.item(k)?.melee ?? Item.bareHands
		default:
			return Item.bareHands
		}
	}

	/// what an empty hand does
	static let bareHands: MeleeProfile = MeleeProfile(damage: 1.5, cooldown: 0.4, reach: 1.8, halfArc: 0.75, style: .bash, knock: 4, swingTime: 0.22, trail: 0xE8D8C8)

	/// Melee damage when swung
	var meleeDamage: Double { return melee.damage }
	var meleeCooldown: Double { return melee.cooldown }
	var meleeReach: Double { return melee.reach }

	/// how long the swing animation of a melee attack lasts
	var swingTime: Double { return melee.swingTime }
}

struct Stack: Codable, Hashable {
	var item: Item
	var count: Int
	var extra: Int = 0
	/// the infusions worked into it (by number; nil: none)
	var inf: [Int]? = nil
}

// MARK: - Item icons

func tierShade(_ c: UInt32, _ f: Double) -> UInt32 { return shadeRGB(c, f) }

func iconTool(_ k: ToolType, _ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	let hi: UInt32 = tierShade(m, 1.25)
	let lo: UInt32 = tierShade(m, 0.7)
	let hd: UInt32 = 0x9A6A32
	let hdd: UInt32 = 0x5E3C1C
	b.line(1, 11, 8, 4, hd)
	b.line(2, 11, 9, 4, hdd)
	switch k {
	case .pickaxe:
		b.line(4, 1, 10, 7, m)
		b.line(5, 1, 10, 6, hi)
		b.line(3, 2, 4, 1, lo)
		b.line(10, 7, 11, 8, lo)
		b.line(4, 2, 10, 8, lo)
	case .axe:
		b.ellipse(8.5, 3.0, 3.0, 2.6, m)
		b.line(6, 1, 6, 5, hi)
		b.line(11, 1, 11, 6, lo)
		b.line(8, 6, 10, 5, lo)
	case .shovel:
		b.ellipse(9.0, 3.0, 2.2, 2.8, m)
		b.line(8, 1, 8, 4, hi)
		b.line(10, 5, 10, 5, lo)
	case .hoe:
		b.line(7, 3, 11, 3, m)
		b.line(7, 2, 10, 2, hi)
		b.line(11, 3, 11, 6, lo)
		b.line(10, 4, 10, 5, m)
	}
	b.outline(0x1A1410)
	return b
}

func iconSword(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	let hi: UInt32 = tierShade(m, 1.3)
	let lo: UInt32 = tierShade(m, 0.7)
	b.line(5, 6, 10, 1, m)
	b.line(6, 6, 10, 2, lo)
	b.line(5, 5, 9, 1, hi)
	b.line(3, 6, 5, 8, 0xC8A040)
	b.line(1, 10, 4, 7, 0x8A5A2A)
	b.set(1, 10, 0xE0C060)
	b.outline(0x1A1410)
	return b
}

func iconArmor(_ s: ArmorSlot, _ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	let hi: UInt32 = tierShade(m, 1.25)
	let lo: UInt32 = tierShade(m, 0.7)
	switch s {
	case .head:
		b.rect(3, 3, 6, 5, m)
		b.rect(4, 2, 4, 1, m)
		b.rect(3, 8, 1, 2, m)
		b.rect(8, 8, 1, 2, m)
		b.rect(4, 5, 4, 2, 0x20202A)
		b.rect(4, 3, 4, 1, hi)
		b.rect(3, 7, 6, 1, lo)
	case .chest:
		b.rect(2, 2, 8, 8, m)
		b.rect(0, 2, 2, 4, m)
		b.rect(10, 2, 2, 4, m)
		b.rect(4, 2, 4, 1, 0x20202A)
		b.rect(3, 4, 6, 1, hi)
		b.rect(2, 9, 8, 1, lo)
		b.rect(5, 5, 2, 4, lo)
	case .legs:
		b.rect(2, 1, 8, 3, m)
		b.rect(2, 4, 3, 6, m)
		b.rect(7, 4, 3, 6, m)
		b.rect(2, 2, 8, 1, hi)
		b.rect(2, 9, 3, 1, lo)
		b.rect(7, 9, 3, 1, lo)
	}
	b.outline(0x1A1410)
	return b
}

func iconMat(_ m: Mat) -> PixelBuf {
	var b = PixelBuf(w: 10, h: 10)
	func ore(_ c: UInt32) {
		b.ellipse(5, 5.5, 3.6, 3.2, 0x8A8A8A)
		b.rect(3, 4, 2, 1, c)
		b.rect(6, 6, 2, 2, c)
		b.rect(4, 7, 1, 1, c)
		b.rect(6, 3, 1, 1, tierShade(c, 1.3))
	}
	func bar(_ c: UInt32) {
		b.rect(1, 4, 8, 4, c)
		b.rect(2, 3, 6, 1, tierShade(c, 1.3))
		b.rect(1, 7, 8, 1, tierShade(c, 0.7))
		b.rect(3, 5, 2, 1, tierShade(c, 1.4))
	}
	switch m {
	case .stick: b.line(2, 8, 7, 2, 0x8A5A2A); b.line(3, 8, 8, 2, 0x6A4220)
	case .coal: b.ellipse(5, 5.5, 3.4, 3.0, 0x222226); b.set(4, 4, 0x55555C); b.set(6, 6, 0x3A3A40)
	case .copperOre: ore(0xD2793A)
	case .ironOre: ore(0xD8A878)
	case .goldOre: ore(0xF5D142)
	case .mythrilOre: ore(0x8A7CFF)
	case .emberOre: ore(0xFF7A1E)
	case .voidOre: ore(0xB04CFF)
	case .diamond:
		b.rect(3, 2, 4, 1, 0xB8FBFF); b.rect(2, 3, 6, 2, 0x4FE3E8); b.rect(3, 5, 4, 2, 0x2EB8C0); b.rect(4, 7, 2, 1, 0x1E8890); b.set(4, 3, 0xFFFFFF)
	case .copperBar: bar(0xD2793A)
	case .ironBar: bar(0xD0D4DA)
	case .goldBar: bar(0xF5D142)
	case .mythrilBar: bar(0x8A7CFF)
	case .emberBar: bar(0xFF6A1E)
	case .voidBar: bar(0xB04CFF)
	case .string: b.line(1, 2, 8, 3, 0xEEEEEE); b.line(8, 3, 2, 5, 0xDDDDDD); b.line(2, 5, 8, 7, 0xEEEEEE); b.line(8, 7, 2, 8, 0xCCCCCC)
	case .leather: b.rect(2, 2, 6, 6, 0x9A5A2A); b.rect(3, 3, 4, 4, 0xB8743A); b.set(2, 2, 0); b.set(7, 7, 0)
	case .bone: b.line(2, 7, 7, 2, 0xE8E0C8); b.rect(1, 6, 2, 2, 0xE8E0C8); b.rect(7, 1, 2, 2, 0xE8E0C8)
	case .feather: b.line(2, 8, 8, 1, 0xDDDDEE); b.line(3, 8, 8, 2, 0x9A9AB0); b.line(2, 8, 1, 9, 0x666666)
	case .wool: b.ellipse(5, 5, 3.6, 3.2, 0xF4F4F0); b.rect(3, 3, 2, 1, 0xFFFFFF); b.rect(5, 7, 3, 1, 0xD8D8D0)
	case .gunpowder: b.ellipse(5, 6, 3.4, 2.4, 0x5A5A60); b.rect(3, 5, 1, 1, 0x8A8A90); b.rect(6, 6, 1, 1, 0x3A3A40)
	case .seeds: b.rect(2, 3, 1, 1, 0xC8B040); b.rect(5, 2, 1, 1, 0xC8B040); b.rect(7, 5, 1, 1, 0xC8B040); b.rect(3, 6, 1, 1, 0xC8B040); b.rect(6, 8, 1, 1, 0xC8B040)
	case .claw: b.line(2, 7, 7, 2, 0xEDE6D0); b.line(3, 7, 7, 3, 0xBDB69A); b.rect(1, 7, 2, 2, 0x7A5A3A)
	case .tusk: b.line(2, 8, 4, 3, 0xF4EEDC); b.line(4, 3, 8, 2, 0xF4EEDC); b.line(3, 8, 5, 4, 0xC8C0A8)
	case .fur: b.rect(2, 2, 6, 6, 0x7A7066); b.rect(3, 3, 4, 4, 0x9A9086); b.set(2, 2, 0); b.set(7, 7, 0); b.set(3, 5, 0xBAB0A6)
	case .crystalShard:
		b.line(3, 8, 5, 1, 0x8AF0E8); b.line(4, 8, 6, 2, 0x5CC8C8); b.line(5, 8, 7, 4, 0x3A9AA8)
		b.rect(2, 8, 6, 1, 0x3A9AA8); b.set(5, 2, 0xD8FFFA); b.set(4, 4, 0xD8FFFA)
	case .relicFragment:
		b.rect(2, 3, 6, 5, 0xB8A070); b.rect(2, 3, 6, 1, 0xD8C090); b.rect(2, 7, 6, 1, 0x8A7450)
		b.set(4, 5, 0x5ED8C8); b.set(5, 5, 0x5ED8C8); b.set(7, 2, 0xB8A070); b.set(1, 6, 0x8A7450)
	case .umbralHeart:
		b.ellipse(3.6, 4.2, 2.0, 2.0, 0x8A3CD0); b.ellipse(6.4, 4.2, 2.0, 2.0, 0x8A3CD0)
		b.rect(2, 5, 6, 2, 0x8A3CD0); b.rect(3, 7, 4, 1, 0x6A2AA8); b.rect(4, 8, 2, 1, 0x4A1A80)
		b.set(3, 3, 0xE0B8FF); b.set(4, 5, 0xFF60C0)
	case .tinOre:
		b.ellipse(5, 5.5, 3.6, 3.2, 0x8A8A8A)
		b.ellipse(3.6, 4.6, 1.2, 1.1, 0xC8D2DA); b.ellipse(6.4, 6.6, 1.3, 1.1, 0xC8D2DA); b.set(3, 4, 0xF2F6FA); b.set(6, 6, 0xF2F6FA)
	case .bronzeBar: bar(0xC89040)
	case .saltpeter:
		b.ellipse(5, 6.5, 3.8, 2.4, 0xD8D4C8); b.rect(3, 4, 2, 2, 0xF4F2EA); b.rect(5, 3, 2, 3, 0xFFFFFF); b.set(7, 5, 0xEDEAE0); b.set(2, 7, 0xB8B4A8)
	case .silverOre:
		b.ellipse(5, 5.5, 3.6, 3.2, 0x7E8088)
		b.line(2, 7, 7, 3, 0xC4CCD8); b.line(3, 7, 7, 4, 0xDDE4EE); b.set(6, 3, 0xFFFFFF); b.set(3, 7, 0xFFFFFF)
	case .silverBar: bar(0xD8DEE8)
	case .amethyst:
		b.line(3, 8, 4, 2, 0xB07AE8); b.line(4, 8, 5, 3, 0x7A3CBC); b.line(5, 8, 7, 3, 0x9A5ADC); b.line(6, 8, 8, 5, 0x7A3CBC)
		b.rect(2, 8, 7, 1, 0x5A2A8A); b.set(4, 3, 0xEEDCFF); b.set(6, 4, 0xEEDCFF)
	case .vial:
		b.rect(4, 1, 2, 1, 0x8A5A2A); b.rect(4, 2, 2, 2, 0xCFEFFF); b.ellipse(5, 6.5, 2.8, 2.6, 0xCFEFFF); b.set(4, 5, 0xFFFFFF)
	case .waterVial:
		b.rect(4, 1, 2, 1, 0x8A5A2A); b.rect(4, 2, 2, 2, 0xCFEFFF); b.ellipse(5, 6.5, 2.8, 2.6, 0xCFEFFF); b.ellipse(5, 7.2, 2.1, 1.8, 0x3B7BE0); b.set(4, 5, 0xFFFFFF)
	case .sunleaf:
		b.ellipse(5.5, 4.5, 3.0, 2.0, 0x9AD040); b.line(2, 8, 5, 5, 0x5A8A2A); b.line(4, 4, 7, 5, 0xC8E870); b.set(7, 3, 0xF0F070)
	case .glowcap:
		b.ellipse(5, 4, 3.6, 2.2, 0x40C8D8); b.rect(4, 5, 2, 4, 0xD8D0C0); b.set(3, 3, 0xB8FFFF); b.set(6, 3, 0xB8FFFF)
	case .slimeGel:
		b.ellipse(5, 6, 3.6, 2.8, 0x6AC85A); b.ellipse(4, 5, 1.2, 0.9, 0xB8F0A8); b.set(6, 7, 0x3A8A3A)
	case .venomSac:
		b.ellipse(5, 5.5, 3.2, 3.2, 0x7A5AA0); b.ellipse(5, 6, 2.0, 1.8, 0x9AE050); b.set(4, 4, 0xD8C8F0)
	case .frostCrystal:
		b.line(5, 1, 5, 8, 0xA8E8FF); b.line(3, 3, 7, 7, 0xD8F8FF); b.line(7, 3, 3, 7, 0xD8F8FF); b.line(2, 5, 8, 5, 0x7AC8F0); b.set(5, 5, 0xFFFFFF)
	case .emberAsh:
		b.ellipse(5, 6.5, 3.6, 2.2, 0x4A4448); b.set(3, 6, 0xFF7A2A); b.set(6, 5, 0xFFB040); b.set(5, 7, 0xE8502A)
	case .wraithDust:
		b.set(3, 3, 0xD8C8F0); b.set(6, 2, 0xB8A8E0); b.set(4, 6, 0xE8E0FF); b.set(7, 5, 0xC8B8F0); b.set(2, 7, 0xB8A8E0); b.set(6, 8, 0xD8C8F0); b.set(5, 4, 0xFFFFFF)
	case .stormEssence:
		b.ellipse(5, 5, 3.2, 3.2, 0x5A5A3A); b.line(5, 1, 3, 5, 0xFFF07A); b.line(3, 5, 6, 5, 0xFFF07A); b.line(6, 5, 4, 9, 0xFFF07A); b.set(5, 5, 0xFFFFFF)
	case .golemCore:
		b.ellipse(5, 5, 3.6, 3.6, 0x7A7E88); b.line(3, 3, 6, 6, 0x60E0FF); b.line(6, 6, 7, 4, 0x60E0FF); b.set(4, 3, 0xA8ACB8)
	case .sentinelLens:
		b.rect(3, 2, 4, 1, 0xF0B8E8); b.rect(2, 3, 6, 3, 0xC88AE8); b.rect(3, 6, 4, 2, 0x8AF0E8); b.set(4, 3, 0xFFFFFF); b.set(5, 6, 0xD8FFFA)
	case .mutantGland:
		b.ellipse(5, 5.5, 3.4, 3.0, 0xC8789A); b.ellipse(4, 5, 1.4, 1.2, 0x9AF04A); b.set(6, 7, 0x7A3A5A); b.set(3, 4, 0xF0B8D0)
	}
	b.outline(0x1A1410)
	return b
}

func iconSpear(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	// a long shaft with a leaf-shaped head, drawn on the same diagonal as the sword
	b.line(1, 11, 8, 4, 0x9A6A32)
	b.line(2, 11, 8, 5, 0x5E3C1C)
	b.line(8, 3, 11, 0, m)
	b.line(8, 4, 10, 2, tierShade(m, 0.7))
	b.line(9, 2, 10, 1, tierShade(m, 1.3))
	b.rect(7, 4, 2, 1, 0xC8A040)
	b.outline(0x1A1410)
	return b
}

func iconHammer(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	let hi: UInt32 = tierShade(m, 1.25)
	let lo: UInt32 = tierShade(m, 0.7)
	b.line(1, 11, 7, 5, 0x9A6A32)
	b.line(2, 11, 7, 6, 0x5E3C1C)
	// a broad, squared head across the top of the haft
	b.rect(5, 1, 6, 4, m)
	b.rect(5, 1, 6, 1, hi)
	b.rect(5, 4, 6, 1, lo)
	b.rect(10, 1, 1, 4, lo)
	b.rect(7, 2, 2, 1, hi)
	b.outline(0x1A1410)
	return b
}

func iconKnife(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	// a short, broad blade on the sword's diagonal, a stubby guard and a wrapped grip
	b.line(6, 5, 10, 1, m)
	b.line(6, 6, 10, 2, tierShade(m, 0.7))
	b.line(5, 5, 9, 1, tierShade(m, 1.35))
	b.line(4, 5, 6, 7, 0x6A6A74)
	b.line(2, 9, 5, 6, 0x6A4220)
	b.set(3, 8, 0x9A6A32)
	b.set(2, 9, 0x9A6A32)
	b.outline(0x1A1410)
	return b
}

func iconClub(_ k: ClubKind) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch k {
	case .wooden, .studded:
		// a haft that swells into a knotted head
		b.line(1, 11, 5, 7, 0x7A5428)
		b.line(2, 11, 5, 8, 0x5E3C1C)
		b.ellipse(7.8, 4.2, 3.2, 3.2, 0x9A6A32)
		b.ellipse(7.2, 3.6, 1.6, 1.4, 0xB98A4E)
		b.set(9, 6, 0x6A4220)
		if k == .studded {
			for (x, y) in [(6, 2), (9, 2), (10, 5), (7, 6), (5, 4)] { b.set(x, y, 0xD8D8E0) }
		}
	case .mace:
		b.line(1, 11, 6, 6, 0x6A4220)
		b.line(2, 11, 6, 7, 0x4A3018)
		b.ellipse(8, 4, 2.8, 2.8, 0xC89040)
		b.ellipse(7.4, 3.4, 1.2, 1.2, 0xF0C070)
		b.rect(7, 0, 2, 1, 0xA87030); b.rect(11, 3, 1, 2, 0xA87030); b.rect(4, 3, 1, 2, 0xA87030); b.rect(7, 7, 2, 1, 0xA87030)
	}
	b.outline(0x1A1410)
	return b
}

func iconSling() -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	// two cords meeting in a leather pouch that holds a stone
	b.line(1, 1, 6, 8, 0xC8B080)
	b.line(4, 1, 7, 7, 0xA89060)
	b.ellipse(7.5, 8.5, 2.6, 2.0, 0x8A5A2A)
	b.ellipse(7.5, 8.0, 1.4, 1.2, 0x9A9A9A)
	b.set(7, 7, 0xC8C8C8)
	b.rect(0, 0, 2, 2, 0x6A4220)
	b.outline(0x1A1410)
	return b
}

func iconRelic(_ r: Relic) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch r {
	case .moonDagger:
		b.line(5, 6, 11, 0, 0xDDE4EE)
		b.line(6, 6, 11, 1, 0x9AA8C0)
		b.line(5, 5, 10, 0, 0xFFFFFF)
		b.line(3, 5, 6, 8, 0x8AA8E8)
		b.line(1, 10, 4, 7, 0x3A4A7A)
		b.set(1, 10, 0xC8E8FF)
		b.set(9, 3, 0xC8E8FF)
	case .emberCleaver:
		// a broad, hooked blade glowing along its edge
		b.line(1, 11, 4, 8, 0x4A3018)
		b.rect(4, 6, 2, 2, 0x3A2A2A)
		b.line(5, 5, 10, 0, 0x5A3A3A)
		b.line(6, 6, 11, 1, 0xC0401A)
		b.line(7, 6, 11, 2, 0xFF7A1E)
		b.line(7, 7, 11, 3, 0xFFC050)
		b.set(11, 0, 0xFFE080)
	case .quakeMaul:
		b.line(1, 11, 6, 6, 0x6A4A26)
		b.line(2, 11, 6, 7, 0x4A3018)
		b.rect(4, 0, 7, 5, 0x8A8070)
		b.rect(4, 0, 7, 1, 0xB8AC90)
		b.rect(4, 4, 7, 1, 0x5A5448)
		b.line(6, 1, 8, 3, 0xF0C860)
		b.line(8, 3, 9, 1, 0xF0C860)
	}
	b.outline(0x1A1410)
	return b
}

func iconLauncher(_ g: GunType) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch g {
	case .crossbow, .arbalest, .repeater:
		let prod: UInt32 = g == .crossbow ? 0xA06A2E : (g == .arbalest ? 0x9AA0AA : 0xC89040)
		// a stock pointing right, the bow arms across its front, the drawn string behind them
		b.rect(1, 6, 9, 2, 0x8A5A2A)
		b.rect(1, 7, 3, 2, 0x6A4220)
		b.line(9, 1, 10, 5, prod); b.line(10, 8, 9, 11, prod); b.rect(9, 5, 2, 3, prod)
		b.line(9, 1, 6, 6, 0xE8E8E8); b.line(6, 7, 9, 11, 0xE8E8E8)
		b.rect(7, 5, 4, 1, 0xC8C8D0)
		if g == .arbalest { b.rect(0, 5, 2, 1, 0x6A6E78); b.set(0, 4, 0x6A6E78) }
		if g == .repeater { b.rect(4, 3, 4, 3, 0x7A5428); b.rect(4, 3, 4, 1, 0xC89040) }
	case .blunderbuss:
		b.rect(3, 4, 7, 2, 0x5A5A64)
		b.rect(3, 4, 7, 1, 0x7A7A84)
		b.rect(10, 2, 2, 6, 0x6A6A74)
		b.rect(11, 3, 1, 4, 0x2A2A30)
		b.rect(0, 5, 4, 3, 0x8A5A2A)
		b.rect(4, 6, 2, 2, 0x6A4220)
		b.set(1, 5, 0xB07A40)
	case .stormRod:
		b.line(1, 11, 8, 4, 0xC4CCD8)
		b.line(2, 11, 8, 5, 0x8A929E)
		b.ellipse(9, 2.8, 2.2, 2.2, 0x9A5ADC)
		b.ellipse(8.6, 2.4, 1.0, 1.0, 0xEEDCFF)
		b.set(11, 0, 0xFFF4A0); b.set(11, 5, 0xFFF4A0); b.set(6, 1, 0xFFF4A0)
		b.rect(6, 6, 2, 1, 0xD2793A)
	default:
		break
	}
	b.outline(0x1A1410)
	return b
}

func iconGear(_ g: Gear) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch g {
	case .headlamp:
		b.rect(1, 5, 10, 2, 0x5A4030); b.rect(1, 5, 10, 1, 0x7A5A40)
		b.ellipse(6, 5.5, 2.4, 2.4, 0x6A6E78); b.ellipse(6, 5.5, 1.4, 1.4, 0xFFF0A0); b.set(5, 5, 0xFFFFFF)
		b.set(9, 3, 0xFFF0A0); b.set(10, 2, 0xFFF0A0)
	case .swiftBoots:
		b.rect(2, 2, 4, 6, 0x8A5A2A); b.rect(2, 8, 8, 2, 0x8A5A2A); b.rect(2, 10, 9, 1, 0x4A3018)
		b.rect(3, 3, 2, 4, 0xB8743A); b.line(6, 4, 9, 2, 0xF0F0F8); b.line(6, 5, 9, 4, 0xC8C8D8)
	case .divingMask:
		b.rect(1, 4, 10, 4, 0x3A4A5A); b.rect(2, 5, 3, 2, 0x8AD0F0); b.rect(7, 5, 3, 2, 0x8AD0F0)
		b.set(2, 5, 0xE0F8FF); b.set(7, 5, 0xE0F8FF); b.rect(5, 8, 2, 3, 0xD87A30); b.rect(5, 1, 2, 3, 0xD87A30)
	case .wardenSigil:
		b.ellipse(6, 6, 4.6, 4.6, 0x3A2C4A); b.ellipse(6, 6, 3.4, 3.4, 0x6A4A8A)
		b.line(6, 3, 6, 9, 0xD8A8FF); b.line(3, 6, 9, 6, 0xD8A8FF); b.set(6, 6, 0xFFFFFF)
		b.set(4, 4, 0xB070FF); b.set(8, 8, 0xB070FF); b.set(4, 8, 0xB070FF); b.set(8, 4, 0xB070FF)
	case .emberCharm:
		b.line(3, 1, 6, 4, 0xC8A040); b.line(9, 1, 6, 4, 0xC8A040)
		b.ellipse(6, 7, 3.0, 3.4, 0xE8580C); b.ellipse(6, 7.4, 1.8, 2.0, 0xFFA030); b.set(6, 7, 0xFFE680); b.set(5, 5, 0xFFD060)
	case .silverCharm:
		// a silver crescent on a fine chain
		b.line(3, 1, 6, 4, 0xA8AEB8); b.line(9, 1, 6, 4, 0xA8AEB8)
		b.ellipse(6, 7.5, 3.4, 3.4, 0xDDE4EE)
		// the bite that makes it a crescent is cut clean out (left see-through, not painted black)
		for yy in 0..<12 { for xx in 0..<12 {
			let dx: Double = Double(xx) + 0.5 - 7.6
			let dy: Double = Double(yy) + 0.5 - 6.6
			if dx * dx + dy * dy < 2.7 * 2.7 { b.clear(xx, yy) }
		} }
		b.set(3, 8, 0xFFFFFF); b.set(5, 10, 0xB8C0CC); b.set(3, 6, 0xF4F8FF)
	case .winterCoat:
		// a padded coat with a fur collar
		b.rect(2, 2, 8, 9, 0x8A3A3A); b.rect(1, 3, 2, 6, 0x8A3A3A); b.rect(9, 3, 2, 6, 0x8A3A3A)
		b.rect(3, 1, 6, 2, 0xE8E0D0); b.line(6, 3, 6, 10, 0x5A2424)
		b.set(5, 5, 0xD8C060); b.set(5, 7, 0xD8C060); b.rect(3, 4, 1, 5, 0xA84A4A)
	case .snowBoots:
		// fur-topped boots with a cleated sole
		b.rect(2, 2, 4, 6, 0x5A4030); b.rect(2, 8, 8, 2, 0x5A4030); b.rect(2, 1, 4, 2, 0xE8E0D0)
		b.rect(2, 10, 9, 1, 0x2A2A30); b.set(3, 11, 0x9AA0AC); b.set(6, 11, 0x9AA0AC); b.set(9, 11, 0x9AA0AC)
	}
	b.outline(0x1A1410)
	return b
}

func iconFood(_ f: Food) -> PixelBuf {
	var b = PixelBuf(w: 10, h: 10)
	switch f {
	case .apple:
		b.ellipse(5, 6, 3.4, 3.2, 0xD62E2E); b.set(4, 4, 0xFF9A9A); b.line(5, 2, 5, 3, 0x6B4A2A); b.rect(6, 1, 2, 1, 0x3E8A2E)
	case .rawMeat:
		b.ellipse(5, 5.5, 3.8, 3.0, 0xE06A7A); b.ellipse(4.5, 5, 1.8, 1.4, 0xF0A0AA); b.rect(7, 2, 1, 2, 0xE8E0C8)
	case .cookedMeat:
		b.ellipse(5, 5.5, 3.8, 3.0, 0x8A4A24); b.ellipse(4.5, 5, 1.8, 1.4, 0xB86A38); b.rect(7, 2, 1, 2, 0xE8E0C8)
	case .rawFish:
		b.ellipse(5, 5, 3.4, 2.2, 0x8FB4D8); b.rect(8, 3, 1, 4, 0x6A94B8); b.set(3, 4, 0x101010)
	case .cookedFish:
		b.ellipse(5, 5, 3.4, 2.2, 0xC88A4A); b.rect(8, 3, 1, 4, 0xA06A30); b.set(3, 4, 0x101010)
	case .wheat:
		b.line(5, 9, 5, 3, 0xC8B040); b.rect(4, 1, 3, 3, 0xE8C850); b.set(3, 4, 0xE8C850); b.set(7, 5, 0xE8C850)
	case .bread:
		b.ellipse(5, 6, 4.0, 2.6, 0xC88A3A); b.rect(3, 4, 4, 1, 0xE0A850); b.set(4, 6, 0x9A6A2A)
	case .carrot:
		b.line(2, 3, 7, 8, 0xF08A1E); b.line(3, 3, 7, 7, 0xD06A10); b.line(1, 1, 3, 3, 0x4EB83A); b.line(3, 1, 3, 3, 0x4EB83A)
	}
	b.outline(0x1A1410)
	return b
}

func iconMisc(_ it: Item) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch it {
	case .bow:
		b.line(8, 0, 10, 3, 0xA06A2E); b.line(10, 3, 10, 8, 0xA06A2E); b.line(10, 8, 8, 11, 0xA06A2E)
		b.line(9, 0, 11, 3, 0x7A4A1E); b.line(11, 3, 11, 8, 0x7A4A1E); b.line(11, 8, 9, 11, 0x7A4A1E)
		b.line(8, 0, 8, 11, 0xE8E8E8)
		b.line(2, 6, 7, 6, 0xB08A5A); b.set(1, 6, 0xDDDDDD)
	case .gun(let g) where g != .pistol && g != .rifle:
		return iconLauncher(g)
	case .ammo(.bolt):
		b.line(2, 9, 8, 3, 0x7A5428); b.line(3, 9, 8, 4, 0x5E3C1C)
		b.rect(8, 2, 2, 2, 0xC89040); b.set(10, 1, 0xF0C070)
		b.line(1, 10, 2, 8, 0xC8C8D0); b.line(1, 10, 3, 10, 0xC8C8D0)
	case .gadget(.fireFlask):
		b.ellipse(6, 7.5, 3.6, 3.4, 0xB8E0F0)
		b.ellipse(6, 8.2, 2.8, 2.4, 0xFF7A1E)
		b.ellipse(5.4, 7.4, 1.2, 1.0, 0xFFD060)
		b.rect(5, 2, 2, 2, 0xB8E0F0)
		b.rect(5, 1, 2, 1, 0x8A5A2A)
		b.set(8, 6, 0xFFFFFF)
	case .gun(let g):
		if g == .pistol {
			b.rect(2, 3, 8, 2, 0x6A6A74); b.rect(2, 5, 4, 2, 0x5A5A64); b.rect(2, 5, 2, 4, 0x8A5A2A); b.rect(9, 2, 2, 1, 0x9A9AA4); b.set(6, 5, 0x3A3A44)
		} else {
			b.rect(0, 4, 11, 1, 0x6A6A74); b.rect(4, 5, 4, 2, 0x5A5A64); b.rect(0, 5, 4, 3, 0x8A5A2A); b.rect(5, 7, 1, 2, 0x8A5A2A); b.rect(10, 3, 1, 1, 0x9A9AA4)
		}
	case .ammo(let a):
		if a == .arrow {
			b.line(1, 10, 9, 2, 0x8A5A2A); b.rect(9, 1, 2, 2, 0xC8C8D0); b.line(1, 10, 1, 8, 0xF0F0F0); b.line(1, 10, 3, 10, 0xF0F0F0)
		} else {
			b.rect(4, 3, 3, 6, 0xC8A040); b.rect(4, 2, 3, 1, 0x8A8A90); b.set(5, 4, 0xFFE080)
		}
	case .part(let p):
		switch p {
		case .frame: b.rect(1, 3, 10, 6, 0xB98A4E); b.rect(2, 4, 8, 4, 0x2A2A30); b.line(2, 4, 9, 7, 0x8F6732); b.line(2, 7, 9, 4, 0x8F6732)
		case .wheel: b.ellipse(6, 6, 5, 5, 0x222226); b.ellipse(6, 6, 3, 3, 0x9A9AA4); b.set(6, 6, 0x222226)
		case .engine: b.rect(1, 3, 10, 6, 0x6A6A74); b.rect(3, 1, 2, 2, 0xA8A8B0); b.rect(7, 1, 2, 2, 0xA8A8B0); b.rect(2, 5, 8, 1, 0xE06A2A); b.rect(0, 5, 1, 2, 0x4A4A52)
		case .steering: b.ellipse(6, 6, 4.5, 4.5, 0x8A5A2A); b.ellipse(6, 6, 2.6, 2.6, 0); b.line(6, 1, 6, 11, 0x8A5A2A); b.line(1, 6, 11, 6, 0x8A5A2A)
		case .seat: b.rect(2, 1, 3, 7, 0x8A3A3A); b.rect(2, 7, 8, 3, 0x9A4A4A); b.rect(2, 10, 2, 1, 0x4A4A52); b.rect(8, 10, 2, 1, 0x4A4A52)
		case .fuelTank: b.rect(2, 2, 8, 8, 0xC03A3A); b.rect(2, 2, 8, 1, 0xE06A6A); b.rect(4, 0, 4, 2, 0x4A4A52); b.rect(4, 5, 4, 3, 0xF0E0A0)
		case .hull: b.rect(0, 4, 12, 3, 0x8F6732); b.rect(1, 7, 10, 2, 0x6A4A22); b.rect(2, 9, 8, 1, 0x4A3216); b.rect(1, 3, 10, 1, 0xB98A4E)
		case .propeller: b.rect(5, 1, 2, 10, 0x9A9AA4); b.rect(1, 5, 10, 2, 0x7A7A84); b.rect(5, 5, 2, 2, 0x4A4A52)
		case .paddle: b.line(2, 10, 8, 4, 0x8A5A2A); b.rect(8, 1, 3, 5, 0xB98A4E); b.rect(8, 1, 1, 5, 0x8F6732)
		case .offroadWheel: b.ellipse(6, 6, 5.6, 5.6, 0x18181C); b.ellipse(6, 6, 3.4, 3.4, 0x3A3A42); b.ellipse(6, 6, 2.2, 2.2, 0xC89040); b.set(6, 6, 0x4A3A20)
		case .headlight: b.rect(1, 4, 5, 5, 0x5A5A64); b.rect(6, 3, 4, 7, 0x9A9AA4); b.rect(7, 4, 3, 5, 0xFFF0A0); b.set(8, 5, 0xFFFFFF); b.line(10, 4, 11, 2, 0xFFF0A0); b.line(10, 8, 11, 10, 0xFFF0A0)
		case .cargo: b.rect(1, 2, 10, 9, 0x8F6732); b.rect(2, 3, 8, 7, 0xB98A4E); b.line(2, 3, 9, 9, 0x8F6732); b.line(2, 9, 9, 3, 0x8F6732); b.rect(1, 2, 10, 1, 0x6A6A74)
		case .drill, .diamondDrill, .voidDrill:
			let bit: UInt32 = p == .drill ? 0xC8CCD4 : (p == .diamondDrill ? 0x6FE6EC : 0xB070FF)
			b.rect(0, 3, 4, 6, 0x6A6A74); b.rect(0, 3, 4, 1, 0x9A9AA4)
			b.rect(4, 3, 3, 6, bit); b.rect(7, 4, 2, 4, bit); b.rect(9, 5, 2, 2, bit); b.set(11, 5, bit)
			b.line(5, 3, 7, 8, shadeRGB(bit, 0.7)); b.line(8, 4, 9, 7, shadeRGB(bit, 0.7))
		}
	case .gadget(let g):
		switch g {
		case .powerCable, .pulseWire, .pulseWireB:
			// a spool of wire with a loose end
			let c: UInt32 = g == .powerCable ? 0xD2793A : (g == .pulseWire ? 0xFFC020 : 0x30E0D0)
			let dk: UInt32 = shadeRGB(c, 0.6)
			b.ellipse(5.5, 6.0, 4.4, 4.4, dk); b.ellipse(5.5, 6.0, 3.6, 3.6, c); b.ellipse(5.5, 6.0, 1.4, 1.4, 0x5A4030)
			b.line(2, 4, 9, 4, dk); b.line(2, 7, 9, 7, dk); b.line(9, 6, 11, 10, c); b.set(11, 11, 0xE8E8EC)
		case .wireSnips:
			b.line(2, 2, 7, 7, 0xC8CCD4); b.line(9, 2, 4, 7, 0xA8AEB8); b.rect(5, 6, 2, 2, 0x6A6E78)
			b.line(3, 8, 1, 11, 0xD2793A); b.line(8, 8, 10, 11, 0xD2793A); b.line(4, 8, 2, 11, 0xA85A28); b.line(7, 8, 9, 11, 0xA85A28)
		case .probe:
			// a hand meter with a dial and a probe lead
			b.rect(2, 1, 7, 9, 0x3A3F4A); b.rect(3, 2, 5, 4, 0xE8E4D8); b.line(4, 5, 6, 3, 0x2A2A30); b.set(5, 7, 0x30E0D0); b.set(7, 7, 0xFFC020)
			b.line(8, 9, 10, 11, 0xD2793A); b.set(11, 11, 0xE8E8EC)
		case .fireFlask: break
		case .shears: b.line(2, 9, 8, 3, 0xC8C8D0); b.line(3, 3, 9, 9, 0xA8A8B0); b.ellipse(2.5, 9.5, 1.6, 1.6, 0xD04A3A); b.ellipse(9.5, 9.5, 1.6, 1.6, 0xD04A3A)
		case .wrench: b.line(2, 10, 8, 4, 0xB8B8C0); b.line(3, 10, 9, 4, 0x8A8A94); b.ellipse(9, 3, 2.2, 2.2, 0xB8B8C0); b.rect(9, 1, 2, 2, 0)
		case .treasureMap:
			b.rect(1, 2, 10, 8, 0xE8D4A0); b.rect(1, 2, 10, 1, 0xC8B080); b.rect(1, 9, 10, 1, 0xC8B080)
			b.line(3, 7, 5, 5, 0x7A5A2A); b.line(5, 5, 7, 6, 0x7A5A2A); b.line(7, 6, 9, 4, 0x7A5A2A)
			b.line(7, 3, 9, 5, 0xD02020); b.line(9, 3, 7, 5, 0xD02020)
		case .portalKey:
			b.ellipse(3.5, 3.5, 2.6, 2.6, 0xB04CFF); b.ellipse(3.5, 3.5, 1.2, 1.2, 0); b.line(5, 5, 10, 10, 0xD8A8FF); b.line(6, 4, 10, 8, 0x8A3CD0); b.rect(8, 9, 2, 1, 0xD8A8FF); b.rect(9, 7, 1, 1, 0xD8A8FF)
		case .carKit:
			b.rect(1, 5, 10, 3, 0xC03A3A); b.rect(3, 3, 5, 2, 0xC03A3A); b.rect(4, 3, 3, 1, 0x9AD0F0)
			b.ellipse(3, 9, 1.8, 1.8, 0x222226); b.ellipse(9, 9, 1.8, 1.8, 0x222226); b.set(3, 9, 0x9A9AA4); b.set(9, 9, 0x9A9AA4)
		case .boatKit:
			b.rect(1, 6, 10, 2, 0x8F6732); b.rect(2, 8, 8, 1, 0x6A4A22); b.rect(3, 9, 6, 1, 0x4A3216); b.line(8, 1, 10, 6, 0xB98A4E)
			b.rect(1, 10, 10, 1, 0x3A70C8)
		case .motorboatKit:
			b.rect(1, 6, 10, 2, 0xE8E8EC); b.rect(2, 8, 8, 1, 0x3A6AA8); b.rect(3, 9, 6, 1, 0x2A4A78); b.rect(5, 4, 4, 2, 0x9AD0F0)
			b.rect(0, 7, 1, 2, 0x6A6A74); b.rect(1, 10, 10, 1, 0x3A70C8)
		case .bomb:
			b.ellipse(5.5, 7.0, 3.8, 3.8, 0x3A3A44); b.ellipse(4.5, 6.0, 1.4, 1.2, 0x6A6A78)
			b.rect(5, 2, 2, 2, 0x8A6A3A); b.line(7, 2, 9, 0, 0xC8A060); b.set(9, 0, 0xFFD040); b.set(10, 0, 0xFF8030)
		case .barometer:
			// a brass dial with a needle
			b.ellipse(6, 6, 5.0, 5.0, 0xC89040); b.ellipse(6, 6, 3.8, 3.8, 0xF0E8D0)
			b.line(6, 6, 8, 3, 0x2A2A30); b.set(6, 6, 0x8A3A3A); b.set(3, 6, 0x6A6A70); b.set(9, 6, 0x6A6A70); b.set(6, 9, 0x6A6A70)
		case .waterFlask:
			b.ellipse(6, 7.5, 3.6, 3.4, 0xB8E0F0); b.ellipse(6, 8.2, 2.8, 2.4, 0x3B7BE0); b.ellipse(5.4, 7.4, 1.0, 0.8, 0x8DBBFF)
			b.rect(5, 2, 2, 2, 0xB8E0F0); b.rect(5, 1, 2, 1, 0x8A5A2A); b.set(8, 6, 0xFFFFFF)
		}
	default:
		break
	}
	b.outline(0x1A1410)
	return b
}

/// Icon buffer for any item (blocks use their 8x8 tile art)
func itemBuf(_ it: Item) -> PixelBuf {
	switch it {
	case .block(let t): return tileBuf(t)
	case .tool(let k, let t): return iconTool(k, t)
	case .sword(let t): return iconSword(t)
	case .spear(let t): return iconSpear(t)
	case .hammer(let t): return iconHammer(t)
	case .knife(let t): return iconKnife(t)
	case .club(let k): return iconClub(k)
	case .relic(let r): return iconRelic(r)
	case .sling: return iconSling()
	case .gear(let g): return iconGear(g)
	case .armor(let s, let t): return iconArmor(s, t)
	case .mat(let m): return iconMat(m)
	case .food(let f): return iconFood(f)
	case .wall(let k): return wallIcon(k)
	case .custom(let k): return ModRuntime.shared.item(k)?.icon ?? missingItemBuf()
	case .potion(let p): return iconPotion(p)
	case .compound(let i): return iconCompound(i)
	case .exoPart, .exoPlate, .exoCore, .exoModule: return iconExo(it)
	default: return iconMisc(it)
	}
}

/// The icon of an item whose mod is missing: a question mark on magenta
func missingItemBuf() -> PixelBuf {
	let rows: [String] = [".mmmmmm.", "mmkkkkmm", "mkmmmmkm", "mmmmmkmm", "mmmmkmmm", "mmmkmmmm", "mmmmmmmm", ".mmkmmm."]
	var b: PixelBuf = bufFromRows(rows, ["m": 0xE040E0, "k": 0x200020])
	b = padBuf(b)
	b.outline(0x101010)
	return b
}

// ===== p04_recipes =====

// MARK: - Recipes & inventory

enum Station: Int, Codable {
	case hand, bench, furnace, campfire
	/// appended, so the raw values above never change: metalwork, machinery, Umbral smithing
	case anvil, tinker, forge
	/// appended: brewing, infusion compounds and suit parts
	case still, infuser, assembly
	var name: String {
		switch self {
		case .still: return "Alchemy Still"
		case .infuser: return "Infusion Crucible"
		case .assembly: return "Assembly Station"
		case .hand: return "By hand"
		case .bench: return "Workbench"
		case .furnace: return "Furnace"
		case .campfire: return "Campfire / Furnace"
		case .anvil: return "Anvil"
		case .tinker: return "Tinker's Bench"
		case .forge: return "Rift Forge"
		}
	}
	/// the block that provides this station
	var tile: Tile? {
		switch self {
		case .hand, .campfire: return nil
		case .bench: return .workbench
		case .furnace: return .furnace
		case .anvil: return .anvil
		case .tinker: return .tinkerBench
		case .forge: return .riftForge
		case .still: return .alchemyStill
		case .infuser: return .infuser
		case .assembly: return .exoStation
		}
	}
}

/// Which station a tier of tools, weapons and armour is made at: wood to copper at the workbench,
/// iron to mythril on an anvil, and the Umbral metals only in a rift forge
func tierStation(_ t: Tier) -> Station {
	switch t {
	case .wood, .stone, .copper: return .bench
	case .iron, .gold, .diamond, .mythril: return .anvil
	case .ember, .voidium: return .forge
	}
}

enum RecipeCat: Int, CaseIterable {
	case basic, build, tools, weapons, armor, gear, smelt, food, vehicle
	/// appended: weather devices and storm building
	case weather
	/// appended: Sparkworks power, pulses and machines
	case power
	/// appended: recipes from mods
	case mods
	/// appended: potions, infusion compounds, suit parts
	case alchemy, infusion, exosuit
	var name: String {
		switch self {
		case .alchemy: return "Alchemy"
		case .infusion: return "Infusion"
		case .exosuit: return "Exosuit"
		case .mods: return "Mods"
		case .power: return "Power"
		case .weather: return "Weather"
		case .basic: return "Basics"
		case .build: return "Building"
		case .tools: return "Tools"
		case .weapons: return "Weapons"
		case .armor: return "Armor"
		case .gear: return "Gear"
		case .smelt: return "Smelting"
		case .food: return "Food"
		case .vehicle: return "Vehicles"
		}
	}
}

struct CostLine {
	var item: Item
	var n: Int
}

struct Recipe: Identifiable {
	let id: Int
	let out: Item
	let outCount: Int
	let cost: [CostLine]
	let station: Station
	let cat: RecipeCat
	/// a mod block that must be nearby instead of a game station (mod recipes only)
	var modStation: Tile? = nil
}

func tierMaterial(_ t: Tier) -> Item {
	switch t {
	case .wood: return .block(.planks)
	case .stone: return .block(.stone)
	case .copper: return .mat(.copperBar)
	case .iron: return .mat(.ironBar)
	case .gold: return .mat(.goldBar)
	case .diamond: return .mat(.diamond)
	case .mythril: return .mat(.mythrilBar)
	case .ember: return .mat(.emberBar)
	case .voidium: return .mat(.voidBar)
	}
}

func armorMaterial(_ t: Tier) -> Item {
	if t == .wood { return .mat(.leather) }
	return tierMaterial(t)
}

enum RecipeBook {
	/// the game's own recipes
	static let base: [Recipe] = RecipeBook.build()
	/// what the crafting screens show: the game's recipes, then those of the world's mods
	static var all: [Recipe] = RecipeBook.base

	static func build() -> [Recipe] {
		var list: [Recipe] = []
		func add(_ out: Item, _ n: Int, _ cost: [(Item, Int)], _ st: Station, _ cat: RecipeCat) {
			let lines: [CostLine] = cost.map { CostLine(item: $0.0, n: $0.1) }
			list.append(Recipe(id: list.count, out: out, outCount: n, cost: lines, station: st, cat: cat))
		}
		let stick: Item = .mat(.stick)
		let coal: Item = .mat(.coal)
		let planks: Item = .block(.planks)
		// Basics
		add(planks, 4, [(.block(.log), 1)], .hand, .basic)
		add(planks, 4, [(.block(.jungleLog), 1)], .hand, .basic)
		add(planks, 4, [(.block(.palmLog), 1)], .hand, .basic)
		add(planks, 4, [(.block(.birchLog), 1)], .hand, .basic)
		add(stick, 4, [(planks, 2)], .hand, .basic)
		add(.block(.workbench), 1, [(planks, 8)], .hand, .basic)
		add(.block(.torch), 4, [(stick, 1), (coal, 1)], .hand, .basic)
		add(.block(.campfire), 1, [(.block(.log), 3), (stick, 2)], .hand, .basic)
		add(.block(.furnace), 1, [(.block(.stone), 12)], .bench, .basic)
		// the stations that unlock the later recipe tiers
		add(.block(.anvil), 1, [(.mat(.ironBar), 6), (.block(.stone), 4)], .bench, .basic)
		add(.block(.tinkerBench), 1, [(planks, 6), (.mat(.ironBar), 3), (.mat(.copperBar), 2)], .bench, .basic)
		add(.block(.riftForge), 1, [(.block(.obsidian), 12), (.block(.glowCrystal), 4), (.mat(.emberBar), 2)], .anvil, .basic)
		add(.mat(.string), 2, [(.mat(.wool), 1)], .hand, .basic)
		add(.mat(.gunpowder), 2, [(coal, 1), (.block(.sand), 1)], .bench, .basic)
		add(.mat(.gunpowder), 4, [(coal, 1), (.mat(.saltpeter), 1)], .bench, .basic)
		add(.block(.glass), 1, [(.block(.sand), 2)], .furnace, .smelt)
		// Building: platforms, ladders, storage, light, doors and background walls (no collision)
		add(.block(.platform), 4, [(planks, 2)], .hand, .build)
		add(.block(.ladder), 3, [(stick, 5)], .hand, .build)
		add(.block(.chest), 1, [(planks, 8)], .bench, .build)
		add(.block(.brick), 2, [(.block(.stone), 2)], .bench, .build)
		add(.block(.lantern), 1, [(.mat(.ironBar), 1), (.block(.torch), 1)], .bench, .build)
		add(.block(.hay), 2, [(.food(.wheat), 4)], .bench, .build)
		add(.block(.doorClosed), 1, [(planks, 6)], .bench, .build)
		add(.wall(5), 4, [(planks, 1)], .bench, .build)
		add(.wall(6), 4, [(.block(.brick), 1)], .bench, .build)
		add(.wall(2), 4, [(.block(.stone), 1)], .bench, .build)
		add(.wall(1), 4, [(.block(.dirt), 1)], .bench, .build)
		add(.wall(7), 4, [(.block(.sandstone), 1)], .bench, .build)
		add(.wall(4), 4, [(.block(.ashStone), 1)], .bench, .build)
		add(.block(.amethystBlock), 1, [(.mat(.amethyst), 4)], .bench, .build)
		add(.block(.lantern), 1, [(.mat(.bronzeBar), 1), (.block(.torch), 1)], .bench, .build)
		add(.block(.rail), 8, [(.mat(.bronzeBar), 1), (stick, 2)], .bench, .build)
		add(.block(.crate), 1, [(planks, 6)], .bench, .build)
		// Smelting
		add(.mat(.copperBar), 1, [(.mat(.copperOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.ironBar), 1, [(.mat(.ironOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.goldBar), 1, [(.mat(.goldOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.mythrilBar), 1, [(.mat(.mythrilOre), 3), (coal, 2)], .furnace, .smelt)
		add(.mat(.emberBar), 1, [(.mat(.emberOre), 3), (coal, 1)], .furnace, .smelt)
		add(.mat(.voidBar), 1, [(.mat(.voidOre), 3), (coal, 2)], .furnace, .smelt)
		// bronze is copper with a little tin; silver smelts like the other metals
		add(.mat(.bronzeBar), 2, [(.mat(.copperOre), 2), (.mat(.tinOre), 1), (coal, 1)], .furnace, .smelt)
		add(.mat(.silverBar), 1, [(.mat(.silverOre), 2), (coal, 1)], .furnace, .smelt)
		// Food
		add(.food(.cookedMeat), 1, [(.food(.rawMeat), 1)], .campfire, .food)
		add(.food(.cookedFish), 1, [(.food(.rawFish), 1)], .campfire, .food)
		add(.food(.bread), 1, [(.food(.wheat), 3)], .bench, .food)
		// Tools, swords, armor for every tier
		// Tools, weapons and armour for every tier, each tier at its own station
		for t in Tier.allCases {
			let m: Item = tierMaterial(t)
			let st: Station = tierStation(t)
			add(.tool(.pickaxe, t), 1, [(m, 3), (stick, 2)], st, .tools)
			add(.tool(.axe, t), 1, [(m, 3), (stick, 2)], st, .tools)
			add(.tool(.shovel, t), 1, [(m, 1), (stick, 2)], st, .tools)
			add(.tool(.hoe, t), 1, [(m, 2), (stick, 2)], st, .tools)
			add(.sword(t), 1, [(m, 2), (stick, 1)], st, .weapons)
			add(.spear(t), 1, [(m, 2), (stick, 3)], st, .weapons)
			add(.hammer(t), 1, [(m, 4), (stick, 2)], st, .weapons)
			if t != .wood { add(.knife(t), 1, [(m, 1), (stick, 1)], st, .weapons) }
			let a: Item = armorMaterial(t)
			add(.armor(.head, t), 1, [(a, 5)], st, .armor)
			add(.armor(.chest, t), 1, [(a, 8)], st, .armor)
			add(.armor(.legs, t), 1, [(a, 7)], st, .armor)
		}
		// Ranged
		add(.bow, 1, [(stick, 3), (.mat(.string), 3)], .bench, .weapons)
		add(.ammo(.arrow), 6, [(stick, 1), (.mat(.feather), 1), (.block(.stone), 1)], .bench, .weapons)
		add(.gun(.pistol), 1, [(.mat(.ironBar), 5), (planks, 2)], .anvil, .weapons)
		add(.gun(.rifle), 1, [(.mat(.ironBar), 8), (planks, 4), (.mat(.gunpowder), 2)], .anvil, .weapons)
		add(.ammo(.bullet), 8, [(.mat(.ironBar), 1), (.mat(.gunpowder), 1)], .anvil, .weapons)
		add(.gadget(.shears), 1, [(.mat(.ironBar), 2)], .anvil, .tools)
		add(.gadget(.wrench), 1, [(.mat(.ironBar), 3), (stick, 1)], .anvil, .tools)
		add(.gadget(.bomb), 3, [(.mat(.gunpowder), 2), (.mat(.ironBar), 1), (.mat(.string), 1)], .bench, .weapons)
		// the club line: a crude start, studded with bone, then a bronze mace
		add(.club(.wooden), 1, [(planks, 3), (stick, 1)], .hand, .weapons)
		add(.club(.studded), 1, [(.club(.wooden), 1), (.mat(.bone), 3)], .bench, .weapons)
		add(.club(.mace), 1, [(.club(.studded), 1), (.mat(.bronzeBar), 4)], .anvil, .weapons)
		add(.sling, 1, [(.mat(.leather), 1), (.mat(.string), 2)], .hand, .weapons)
		// bolt throwers: bronze makes the crossbow and its bolts; iron makes the heavy one
		add(.gun(.crossbow), 1, [(.mat(.bronzeBar), 3), (planks, 3), (.mat(.string), 2)], .bench, .weapons)
		add(.ammo(.bolt), 8, [(.mat(.bronzeBar), 1), (stick, 2)], .bench, .weapons)
		add(.ammo(.bolt), 8, [(.mat(.ironBar), 1), (stick, 2)], .anvil, .weapons)
		add(.gun(.arbalest), 1, [(.gun(.crossbow), 1), (.mat(.ironBar), 4), (.mat(.string), 2)], .anvil, .weapons)
		add(.gun(.blunderbuss), 1, [(.mat(.bronzeBar), 5), (.mat(.ironBar), 2), (planks, 2), (.mat(.gunpowder), 2)], .anvil, .weapons)
		add(.gadget(.fireFlask), 2, [(.block(.glass), 1), (.mat(.saltpeter), 1), (coal, 1)], .bench, .weapons)
		add(.gun(.stormRod), 1, [(.mat(.silverBar), 3), (.mat(.amethyst), 4), (.mat(.copperBar), 2), (.mat(.goldBar), 1)], .tinker, .weapons)
		// Gear, worn in the two gear slots
		add(.gear(.divingMask), 1, [(.block(.glass), 3), (.mat(.copperBar), 2), (.mat(.leather), 1)], .bench, .gear)
		add(.gear(.headlamp), 1, [(.mat(.ironBar), 2), (.mat(.crystalShard), 1), (.block(.torch), 1)], .tinker, .gear)
		add(.gear(.headlamp), 1, [(.mat(.ironBar), 2), (.mat(.amethyst), 2), (.block(.torch), 1)], .tinker, .gear)
		add(.gear(.silverCharm), 1, [(.mat(.silverBar), 4), (.mat(.string), 1)], .anvil, .gear)
		add(.gear(.swiftBoots), 1, [(.mat(.leather), 4), (.mat(.feather), 3), (.mat(.goldBar), 2)], .anvil, .gear)
		add(.gear(.emberCharm), 1, [(.mat(.emberBar), 3), (.block(.glowCrystal), 2), (.mat(.crystalShard), 1)], .forge, .gear)
		add(.gear(.wardenSigil), 1, [(.mat(.umbralHeart), 1), (.mat(.voidBar), 4), (.mat(.crystalShard), 4)], .forge, .gear)
		// Ready-made vehicles (place them in one tap) - easiest way to get driving
		add(.gadget(.carKit), 1, [(planks, 10), (.mat(.ironBar), 14), (.mat(.leather), 2), (.mat(.wool), 2)], .tinker, .vehicle)
		add(.gadget(.boatKit), 1, [(planks, 20), (.mat(.string), 4), (.mat(.wool), 2)], .bench, .vehicle)
		add(.gadget(.motorboatKit), 1, [(planks, 20), (.mat(.ironBar), 12), (.mat(.copperBar), 3), (.mat(.wool), 2), (.block(.glass), 1)], .tinker, .vehicle)
		// Vehicle parts (for building your own design): wooden ones at the workbench, machinery at
		// the tinker's bench
		add(.part(.frame), 1, [(planks, 4), (.mat(.ironBar), 1)], .bench, .vehicle)
		add(.part(.wheel), 1, [(.mat(.ironBar), 2), (.mat(.leather), 1)], .tinker, .vehicle)
		add(.part(.engine), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 3), (coal, 2)], .tinker, .vehicle)
		add(.part(.steering), 1, [(.mat(.ironBar), 1), (stick, 2)], .tinker, .vehicle)
		add(.part(.seat), 1, [(planks, 2), (.mat(.wool), 2)], .bench, .vehicle)
		add(.part(.fuelTank), 1, [(.mat(.ironBar), 3), (.block(.glass), 1)], .tinker, .vehicle)
		add(.part(.hull), 1, [(planks, 6), (.mat(.string), 2)], .bench, .vehicle)
		add(.part(.propeller), 1, [(.mat(.ironBar), 3)], .tinker, .vehicle)
		add(.part(.propeller), 1, [(.mat(.bronzeBar), 3)], .tinker, .vehicle)
		add(.part(.paddle), 1, [(planks, 2), (stick, 2)], .bench, .vehicle)
		add(.part(.drill), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 2)], .tinker, .vehicle)
		add(.part(.diamondDrill), 1, [(.part(.drill), 1), (.mat(.diamond), 4), (.mat(.goldBar), 2)], .tinker, .vehicle)
		add(.part(.offroadWheel), 1, [(.mat(.ironBar), 3), (.mat(.leather), 2), (.mat(.fur), 1)], .tinker, .vehicle)
		add(.part(.headlight), 1, [(.mat(.copperBar), 1), (.block(.glass), 1), (.block(.torch), 2)], .tinker, .vehicle)
		add(.part(.cargo), 1, [(planks, 8), (.mat(.ironBar), 2)], .tinker, .vehicle)
		add(.part(.voidDrill), 1, [(.part(.diamondDrill), 1), (.mat(.voidBar), 4), (.mat(.emberBar), 2)], .forge, .vehicle)
		// Weather: reading it, warning of it, and building against it
		add(.block(.weatherStation), 1, [(.mat(.copperBar), 3), (.block(.glass), 2), (planks, 4), (.mat(.feather), 1)], .bench, .weather)
		add(.block(.dopplerStation), 1, [(.block(.weatherStation), 1), (.mat(.silverBar), 2), (.mat(.amethyst), 2), (.mat(.copperBar), 2)], .tinker, .weather)
		add(.gadget(.barometer), 1, [(.mat(.copperBar), 2), (.block(.glass), 1)], .bench, .weather)
		add(.block(.weatherVane), 1, [(.mat(.copperBar), 2), (stick, 2)], .bench, .weather)
		add(.block(.lightningRod), 1, [(.mat(.copperBar), 4)], .bench, .weather)
		add(.block(.stormSiren), 1, [(.mat(.ironBar), 3), (.mat(.copperBar), 2), (.mat(.bronzeBar), 1)], .anvil, .weather)
		add(.block(.windTurbine), 1, [(.mat(.ironBar), 4), (planks, 6), (.mat(.copperBar), 2)], .tinker, .weather)
		add(.block(.rainBarrel), 1, [(planks, 6), (.mat(.copperBar), 1)], .bench, .weather)
		add(.block(.rainCistern), 1, [(.block(.rainBarrel), 1), (.mat(.ironBar), 3), (.block(.stone), 6)], .anvil, .weather)
		add(.block(.heater), 1, [(.mat(.ironBar), 3), (.block(.brick), 2), (coal, 2)], .bench, .weather)
		add(.block(.sandbag), 4, [(.block(.sand), 4), (.mat(.string), 1)], .bench, .weather)
		add(.block(.shutterClosed), 2, [(planks, 3), (.mat(.ironBar), 1)], .bench, .weather)
		add(.block(.stormBrick), 4, [(.block(.brick), 4), (.mat(.ironBar), 1)], .anvil, .weather)
		add(.block(.shingles), 6, [(planks, 3), (.block(.stone), 3)], .bench, .weather)
		add(.gear(.winterCoat), 1, [(.mat(.wool), 5), (.mat(.leather), 3)], .bench, .weather)
		add(.gear(.winterCoat), 1, [(.mat(.fur), 3), (.mat(.leather), 2)], .bench, .weather)
		add(.gear(.snowBoots), 1, [(.mat(.leather), 3), (.mat(.wool), 2)], .bench, .weather)
		add(.block(.mud), 2, [(.block(.dirt), 2), (.gadget(.waterFlask), 1)], .hand, .weather)
		// Sparkworks. First steps at the workbench: wire, a crank, a battery, switches and lamps.
		let cu: Item = .mat(.copperBar)
		let fe: Item = .mat(.ironBar)
		let bz: Item = .mat(.bronzeBar)
		let ag: Item = .mat(.silverBar)
		let glass: Item = .block(.glass)
		let stone: Item = .block(.stone)
		add(.gadget(.powerCable), 12, [(cu, 1)], .bench, .power)
		add(.gadget(.pulseWire), 12, [(bz, 1)], .bench, .power)
		add(.gadget(.pulseWireB), 12, [(bz, 1), (glass, 1)], .bench, .power)
		add(.gadget(.wireSnips), 1, [(fe, 1), (cu, 1)], .bench, .power)
		add(.gadget(.probe), 1, [(cu, 2), (glass, 1)], .bench, .power)
		add(.block(.crankGen), 1, [(planks, 4), (cu, 2), (stick, 2)], .bench, .power)
		add(.block(.waterWheel), 1, [(planks, 8), (fe, 1)], .bench, .power)
		add(.block(.battery), 1, [(cu, 4), (fe, 1), (coal, 2)], .bench, .power)
		add(.block(.powerSwitch), 1, [(cu, 1), (stone, 2)], .bench, .power)
		add(.block(.lever), 1, [(stick, 1), (stone, 1)], .hand, .power)
		add(.block(.pushButton), 2, [(stone, 2)], .hand, .power)
		add(.block(.pressurePlate), 1, [(stone, 2), (cu, 1)], .bench, .power)
		add(.block(.lampOff), 2, [(glass, 2), (cu, 1)], .bench, .power)
		add(.block(.signalLight), 2, [(glass, 1), (cu, 1)], .bench, .power)
		// Then metalwork and machinery: solar, fuel, breakers and meters, logic, sensors, machines.
		add(.block(.solarPanel), 1, [(glass, 3), (ag, 1), (cu, 2)], .tinker, .power)
		add(.block(.fuelGen), 1, [(fe, 6), (.block(.furnace), 1), (cu, 2)], .anvil, .power)
		add(.block(.breaker), 1, [(fe, 1), (cu, 2), (bz, 1)], .tinker, .power)
		add(.block(.powerMeter), 1, [(glass, 1), (cu, 2), (fe, 1)], .tinker, .power)
		add(.block(.repeater), 2, [(bz, 1), (stone, 2), (cu, 1)], .tinker, .power)
		add(.block(.inverter), 2, [(bz, 1), (stone, 2), (.mat(.saltpeter), 1)], .tinker, .power)
		add(.block(.logicGate), 2, [(bz, 2), (ag, 1), (stone, 2)], .tinker, .power)
		add(.block(.pulseTimer), 1, [(bz, 2), (glass, 1), (cu, 1)], .tinker, .power)
		add(.block(.motionSensor), 1, [(ag, 1), (glass, 1), (cu, 2)], .tinker, .power)
		add(.block(.daySensor), 1, [(glass, 2), (ag, 1), (cu, 1)], .tinker, .power)
		add(.block(.weatherSensor), 1, [(cu, 2), (glass, 1), (.mat(.feather), 1)], .tinker, .power)
		add(.block(.itemSensor), 1, [(cu, 2), (fe, 1), (.block(.chest), 1)], .tinker, .power)
		add(.block(.proximitySensor), 1, [(ag, 1), (.mat(.amethyst), 1), (cu, 2)], .tinker, .power)
		add(.block(.gateClosed), 1, [(fe, 4), (cu, 1)], .anvil, .power)
		add(.block(.arcTrap), 1, [(fe, 3), (cu, 4), (ag, 1)], .anvil, .power)
		add(.block(.conveyor), 4, [(fe, 2), (.mat(.leather), 2), (cu, 1)], .tinker, .power)
		add(.block(.collector), 1, [(fe, 3), (cu, 2), (.block(.chest), 1)], .tinker, .power)
		add(.block(.sumpPump), 1, [(fe, 4), (bz, 1), (glass, 1)], .tinker, .power)
		// Late: big storage, automation that mines and makes things, and the Umbral-fired dynamo.
		add(.block(.accumulator), 1, [(.block(.battery), 2), (.mat(.crystalShard), 4), (.mat(.goldBar), 2)], .tinker, .power)
		add(.block(.autoDrill), 1, [(fe, 6), (.mat(.diamond), 1), (cu, 3)], .anvil, .power)
		add(.block(.autoCrafter), 1, [(.block(.workbench), 1), (fe, 4), (.mat(.goldBar), 2), (.mat(.crystalShard), 1)], .tinker, .power)
		add(.block(.emberDynamo), 1, [(.mat(.emberBar), 4), (.block(.obsidian), 6), (.mat(.crystalShard), 2), (.block(.accumulator), 1)], .forge, .power)
		addFeatureRecipes(add)
		// appended last so every older recipe keeps its number
		addBuildingRecipes(add)
		return list
	}
}

// MARK: - Inventory

struct Inventory: Codable {
	var slots: [Stack?]
	/// head, body, legs, then the two gear slots
	var armor: [Stack?]
	static let hotbarCount: Int = 10
	static let size: Int = 40
	static let armorSlots: Int = 5
	static let firstGearSlot: Int = 3

	enum CodingKeys: String, CodingKey {
		case slots, armor
	}

	init() {
		slots = [Stack?](repeating: nil, count: Inventory.size)
		armor = [Stack?](repeating: nil, count: Inventory.armorSlots)
	}

	/// Saves from before the gear slots hold three armour entries: they gain two empty gear slots
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		slots = try c.decode([Stack?].self, forKey: .slots)
		armor = try c.decode([Stack?].self, forKey: .armor)
		while slots.count < Inventory.size { slots.append(nil) }
		while armor.count < Inventory.armorSlots { armor.append(nil) }
	}

	func wearing(_ g: Gear) -> Bool {
		for i in Inventory.firstGearSlot..<armor.count {
			if let s = armor[i], case .gear(let x) = s.item, x == g { return true }
		}
		return false
	}

	func total(_ item: Item) -> Int {
		var n: Int = 0
		for s in slots {
			if let st = s, st.item == item { n += st.count }
		}
		return n
	}

	/// Adds items, returns the leftover count that did not fit. Infused items keep their infusions and
	/// never merge with plain ones.
	mutating func add(_ item: Item, _ count: Int, extra: Int = 0, inf: [Int]? = nil) -> Int {
		var left: Int = count
		let ms: Int = item.maxStack
		if ms > 1 {
			for i in 0..<slots.count {
				if left <= 0 { break }
				if var st = slots[i], st.item == item, st.inf == inf, st.count < ms {
					let put: Int = min(ms - st.count, left)
					st.count += put
					slots[i] = st
					left -= put
				}
			}
		}
		for i in 0..<slots.count {
			if left <= 0 { break }
			if slots[i] == nil {
				let put: Int = min(ms, left)
				slots[i] = Stack(item: item, count: put, extra: extra, inf: inf)
				left -= put
			}
		}
		return left
	}

	mutating func remove(_ item: Item, _ count: Int) -> Bool {
		if total(item) < count { return false }
		var left: Int = count
		for i in 0..<slots.count {
			if left <= 0 { break }
			if var st = slots[i], st.item == item {
				let take: Int = min(st.count, left)
				st.count -= take
				left -= take
				slots[i] = st.count > 0 ? st : nil
			}
		}
		return true
	}

	func canAfford(_ cost: [CostLine]) -> Bool {
		for c in cost {
			if total(c.item) < c.n { return false }
		}
		return true
	}

	func canFit(_ item: Item, _ count: Int) -> Bool {
		var room: Int = 0
		let ms: Int = item.maxStack
		for s in slots {
			if let st = s {
				if st.item == item && ms > 1 { room += ms - st.count }
			} else { room += ms }
		}
		return room >= count
	}

	mutating func removeAt(_ i: Int, _ n: Int) {
		if i < 0 || i >= slots.count { return }
		if var st = slots[i] {
			st.count -= n
			slots[i] = st.count > 0 ? st : nil
		}
	}

	mutating func swap(_ a: Int, _ b: Int) {
		let t: Stack? = slots[a]
		slots[a] = slots[b]
		slots[b] = t
	}

	/// Merges partial stacks of the same item (same load and infusions) into the first of them, bag and
	/// hotbar alike, so a material spread over many slots ends up in as few as it fits. Gives how many
	/// stacks were folded in.
	mutating func mergeStacks() -> Int {
		var merged: Int = 0
		for i in 0..<slots.count {
			guard var a = slots[i] else { continue }
			let ms: Int = a.item.maxStack
			if ms <= 1 || a.count >= ms { continue }
			for j in (i + 1)..<slots.count {
				if a.count >= ms { break }
				guard var b = slots[j], b.item == a.item, b.extra == a.extra, b.inf == a.inf else { continue }
				let put: Int = min(ms - a.count, b.count)
				a.count += put
				b.count -= put
				slots[j] = b.count > 0 ? b : nil
				merged += 1
			}
			slots[i] = a
		}
		return merged
	}

	/// Sorts the bag (everything past the hotbar): equal stacks merge, then items group by kind and name.
	/// The hotbar is left alone so a sort never moves what the player has ready.
	mutating func sortBag() {
		var list: [Stack] = []
		for i in Inventory.hotbarCount..<slots.count {
			guard let s = slots[i] else { continue }
			slots[i] = nil
			if s.item.maxStack > 1, let j = list.firstIndex(where: { $0.item == s.item && $0.extra == s.extra && $0.inf == s.inf && $0.count < $0.item.maxStack }) {
				let room: Int = list[j].item.maxStack - list[j].count
				let put: Int = min(room, s.count)
				list[j].count += put
				if s.count - put > 0 { var r: Stack = s; r.count = s.count - put; list.append(r) }
			} else {
				list.append(s)
			}
		}
		list.sort { a, b in
			let ka: Int = a.item.sortGroup
			let kb: Int = b.item.sortGroup
			if ka != kb { return ka < kb }
			if a.item.name != b.item.name { return a.item.name < b.item.name }
			return a.count > b.count
		}
		for (k, s) in list.enumerated() where Inventory.hotbarCount + k < slots.count {
			slots[Inventory.hotbarCount + k] = s
		}
	}

	/// Total armor defense value
	var defense: Double {
		var d: Double = 0
		for s in armor {
			if let st = s, case .armor(let slot, let tier) = st.item { d += OverrideRT.shared.items[st.item]?.defense ?? tier.defense * slot.weight }
			if let st = s, case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .armor { d += r.def.defense }
		}
		return d
	}

}

// ===== p05a_humanoid =====

// MARK: - Creature art: inks, the shared finishing pass and frame composition

/// Sprite inks. The alpha byte tells the finishing pass how to treat a pixel:
/// 0xFF is body material (it gets the top light and the bottom shadow), 0xFE is a flat detail
/// (eyes, claws, markings, hand-placed tones) that keeps its colour.
@inline(__always) func inkS(_ c: UInt32) -> UInt32 { return 0xFF000000 | c }
@inline(__always) func inkF(_ c: UInt32) -> UInt32 { return 0xFE000000 | c }

/// The tones every creature derives from its base colours: a warm highlight, a cool shadow and a
/// darkened outline of the neighbouring colour (never plain black)
func toneL(_ c: UInt32) -> UInt32 { return mixRGB(c, 0xFFF2D8, 0.28) }
func toneD(_ c: UInt32) -> UInt32 { return mixRGB(shadeRGB(c, 0.76), 0x2A2448, 0.14) }
func toneO(_ c: UInt32) -> UInt32 { return mixRGB(shadeRGB(c, 0.45), 0x1E1828, 0.42) }

func artLum(_ c: UInt32) -> Double {
	return Double((c >> 16) & 0xFF) * 0.3 + Double((c >> 8) & 0xFF) * 0.59 + Double(c & 0xFF) * 0.11
}

/// All creatures, the player and the terrain share one pixel size: 8 art pixels per block
let creatureScale: Double = 0.125

extension PixelBuf {
	/// Writes an ink (alpha byte included) without touching it
	mutating func ink(_ x: Int, _ y: Int, _ v: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h { return }
		px[y * w + x] = v
	}

	/// Paints rows of palette letters; '.' is transparent
	mutating func paint(_ rows: [String], _ pal: [Character: UInt32], _ ox: Int, _ oy: Int) {
		var y: Int = 0
		for row in rows {
			var x: Int = 0
			for ch in row {
				if ch != "." && ch != " ", let v = pal[ch] { ink(ox + x, oy + y, v) }
				x += 1
			}
			y += 1
		}
	}

	mutating func inkRect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ v: UInt32) {
		if rw <= 0 || rh <= 0 { return }
		for yy in y..<(y + rh) {
			for xx in x..<(x + rw) { ink(xx, yy, v) }
		}
	}

	mutating func inkEllipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ v: UInt32) {
		let x0: Int = Int(floor(cx - rx)) - 1
		let x1: Int = Int(ceil(cx + rx)) + 1
		let y0: Int = Int(floor(cy - ry)) - 1
		let y1: Int = Int(ceil(cy + ry)) + 1
		for yy in y0...y1 {
			for xx in x0...x1 {
				let dx: Double = (Double(xx) + 0.5 - cx) / rx
				let dy: Double = (Double(yy) + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0 { ink(xx, yy, v) }
			}
		}
	}

	/// Filled polygon (even-odd test per pixel centre)
	mutating func inkPoly(_ pts: [(Double, Double)], _ v: UInt32) {
		if pts.count < 3 { return }
		var minX: Double = pts[0].0, maxX: Double = pts[0].0, minY: Double = pts[0].1, maxY: Double = pts[0].1
		for p in pts { minX = min(minX, p.0); maxX = max(maxX, p.0); minY = min(minY, p.1); maxY = max(maxY, p.1) }
		for yy in Int(floor(minY))...Int(ceil(maxY)) {
			for xx in Int(floor(minX))...Int(ceil(maxX)) {
				let px: Double = Double(xx) + 0.5
				let py: Double = Double(yy) + 0.5
				var inside: Bool = false
				var j: Int = pts.count - 1
				for i in 0..<pts.count {
					let a = pts[i]
					let b = pts[j]
					if (a.1 > py) != (b.1 > py) && px < (b.0 - a.0) * (py - a.1) / (b.1 - a.1) + a.0 { inside = !inside }
					j = i
				}
				if inside { ink(xx, yy, v) }
			}
		}
	}

	mutating func inkLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt32) {
		let n: Int = max(abs(x1 - x0), abs(y1 - y0))
		if n == 0 { ink(x0, y0, v); return }
		for i in 0...n {
			let t: Double = Double(i) / Double(n)
			let xx: Int = Int((Double(x0) + Double(x1 - x0) * t).rounded())
			let yy: Int = Int((Double(y0) + Double(y1 - y0) * t).rounded())
			ink(xx, yy, v)
		}
	}
}

/// The finishing pass every creature goes through, so they all read as one set:
/// - body pixels open to the sky get a warm rim light (two rows on large sprites)
/// - body pixels just above empty space get a cool shadow (`band` rows deep)
/// - a 1px outline in a darkened version of the colour it borders
/// Flat details are left as drawn.
func finishCreature(_ src: PixelBuf, band: Int) -> PixelBuf {
	let w: Int = src.w
	let h: Int = src.h
	let base: [UInt32] = src.px
	var out: [UInt32] = src.px
	func opaque(_ x: Int, _ y: Int) -> Bool {
		if x < 0 || y < 0 || x >= w || y >= h { return false }
		return (base[y * w + x] >> 24) != 0
	}
	for y in 0..<h {
		for x in 0..<w {
			let v: UInt32 = base[y * w + x]
			if (v >> 24) != 0xFF { continue }
			let c: UInt32 = v & 0xFFFFFF
			if !opaque(x, y - 1) { out[y * w + x] = 0xFF000000 | toneL(c); continue }
			if band > 1 && !opaque(x, y - 2) { out[y * w + x] = 0xFF000000 | mixRGB(c, toneL(c), 0.45); continue }
			var k: Int = 1
			while k <= band {
				if !opaque(x, y + k) { out[y * w + x] = 0xFF000000 | toneD(c); break }
				k += 1
			}
		}
	}
	var res: [UInt32] = out
	for y in 0..<h {
		for x in 0..<w {
			if opaque(x, y) { continue }
			var best: UInt32 = 0
			var found: Bool = false
			for (dx, dy) in [(0, 1), (0, -1), (-1, 0), (1, 0)] {
				if !opaque(x + dx, y + dy) { continue }
				let n: UInt32 = base[(y + dy) * w + x + dx] & 0xFFFFFF
				if !found || artLum(n) < artLum(best) { best = n; found = true }
			}
			if found { res[y * w + x] = 0xFF000000 | toneO(best) }
		}
	}
	for i in 0..<res.count where (res[i] >> 24) != 0 { res[i] = 0xFF000000 | (res[i] & 0xFFFFFF) }
	var b: PixelBuf = src
	b.px = res
	return b
}

/// Builds finished frames from parts: each frame lists (rows, dx, dy) drawn in order onto a w x h
/// interior with a 1px margin for the outline
func composeCreature(_ w: Int, _ h: Int, _ pal: [Character: UInt32], _ frames: [[([String], Int, Int)]], band: Int = 0) -> [PixelBuf] {
	var out: [PixelBuf] = []
	for fr in frames {
		var b = PixelBuf(w: w + 2, h: h + 2)
		for p in fr { b.paint(p.0, pal, 1 + p.1, 1 + p.2) }
		out.append(finishCreature(b, band: band > 0 ? band : (b.h <= 16 ? 1 : 2)))
	}
	return out
}

/// How a creature's frames are used beyond the walk cycle (frames 1-2)
struct CreatureAnim {
	/// shown now and then while standing still (grazing, pecking); -1 for none
	var idleAlt: Int = -1
	/// shown while an attack lands; -1 for none
	var attack: Int = -1
	/// 0 on the ground, 1 in the air (slimes, frogs)
	var hop: Bool = false
	/// looping frames for swimmers and fliers
	var cycle: [Int] = []
}

// MARK: - Humanoid sprites

enum HandItem { case none, sword, cutlass, pistol, bow }

struct HumanStyle {
	var skin: UInt32 = 0xF1C27D
	var hair: UInt32 = 0x3B2417
	var shirt: UInt32 = 0x8A5A2E
	var sleeve: UInt32 = 0x7A4C24
	var belt: UInt32 = 0xD8B060
	var pants: UInt32 = 0x3A4A6E
	var boots: UInt32 = 0x2A2A30
	var scarf: UInt32 = 0
	var eye: UInt32 = 0x1E1418
	var hat: UInt32 = 0
	/// 0 cap or helmet, 1 bandana, 2 tricorn, 3 horns
	var hatStyle: Int = 0
	var weapon: HandItem = .none
	var weaponColor: UInt32 = 0xD0D4DA
	var shield: UInt32 = 0
	var zombieArms: Bool = false
	var ribs: Bool = false
	var skull: Bool = false
	var beard: UInt32 = 0
	var patch: Bool = false
	var coat: Bool = false
	var tail: Bool = false
	/// an exosuit worn over the body (nil: none)
	var suit: SuitLook? = nil
}

let humanW: Int = 22
let humanH: Int = 17
let humanOX: Int = 6

/// One humanoid frame: a 10 x 15 figure (head 5, neck 1, torso 3, belt 1, hips 1, legs 4) facing right,
/// with room on the right for a weapon. legs: 0 standing, 1 stride, 2 passing. pose: 0 idle,
/// 1 wind-up, 2 attack, 3 block, 4 shoot.
func humanoidFrame(_ s: HumanStyle, legs: Int, pose: Int) -> PixelBuf {
	var rows: [String] = []
	let hasHat: Bool = s.hat != 0
	if s.skull {
		rows += ["...HHHH...", "..HHHHHH..", "..Hsksks..", "..ssssss..", "...sjsj..."]
	} else if hasHat && s.hatStyle == 1 {
		rows += ["..HHHHH...", ".HHHHHHH..", "H.hssses..", "..ssssss..", "...ssss..."]
	} else if hasHat && s.hatStyle == 2 {
		rows += ["..HHHHH...", "HHHHHHHHH.", "..hsssse..", "..ssssss..", "...ssss..."]
	} else if hasHat && s.hatStyle == 3 {
		rows += ["..H....H..", "..hhhhhh..", "..hsssse..", "..ssssss..", "...ssss..."]
	} else if hasHat {
		rows += ["...HHHH...", "..HHHHHH..", "..HHssse..", "..ssssss..", "...ssss..."]
	} else if s.hair == 0 {
		rows += ["...ssss...", "..ssssss..", "..ssssse..", "..ssssss..", "...ssss..."]
	} else {
		rows += ["...hhhh...", "..hhhhhh..", "..hsssse..", "..ssssss..", "...ssss..."]
	}
	if s.beard != 0 {
		rows[3] = "..sbbbbb.."
		rows[4] = "...bbbb..."
	}
	if s.patch {
		var ch: [Character] = Array(rows[2])
		ch[7] = "k"
		rows[2] = String(ch)
	}
	rows.append(s.scarf != 0 ? "..cccccc.." : "...tttt...")
	rows += [".aattttaa.", ".aattttaa.", ".ssttttss."]
	rows.append("..xxxxxx..")
	rows.append(s.coat ? ".aappppaa." : "..pppppp..")
	if legs == 1 {
		rows += [".pp....pp.", ".pp....pp.", ".pp....pp.", ".oo....oo."]
	} else if legs == 2 {
		rows += ["...pppp...", "...pppp...", "...pppp...", "...oooo..."]
	} else {
		rows += ["..pp..pp..", "..pp..pp..", "..pp..pp..", "..oo..oo.."]
	}
	if s.ribs {
		rows[6] = ".aatgtgaa."
		rows[7] = ".aagtgtaa."
	}
	var pal: [Character: UInt32] = [:]
	pal["h"] = inkS(s.hair)
	pal["H"] = inkS(s.hat)
	pal["s"] = inkS(s.skin)
	pal["e"] = inkF(s.eye)
	pal["k"] = inkF(0x1E1418)
	pal["t"] = inkS(s.shirt)
	pal["a"] = inkS(s.sleeve)
	pal["x"] = inkS(s.belt)
	pal["p"] = inkS(s.pants)
	pal["o"] = inkS(s.boots)
	pal["c"] = inkS(s.scarf)
	pal["b"] = inkS(s.beard)
	pal["g"] = inkF(0x6A6A70)
	pal["j"] = inkF(0x3A3040)
	var cv = PixelBuf(w: humanW, h: humanH)
	cv.paint(rows, pal, humanOX, 1)
	// arms: remove the right arm for poses that draw their own
	if pose >= 2 || s.zombieArms {
		for y in 7...9 { cv.clear(13, y); cv.clear(14, y) }
	}
	if let l = s.suit { paintSuit(&cv, l, legs: legs, pose: pose) }
	if s.zombieArms {
		// arms reach forward; raised a pixel in the attack pose
		let lift: Int = pose == 2 ? 1 : 0
		for i in 0..<6 {
			let c: UInt32 = i < 4 ? s.sleeve : s.skin
			cv.ink(13 + i, 7 - lift, inkS(c))
			cv.ink(13 + i, 8 - lift, inkS(c))
		}
	}
	if s.tail {
		cv.ink(6, 12, inkS(s.skin)); cv.ink(5, 13, inkS(s.skin)); cv.ink(4, 13, inkS(s.skin)); cv.ink(3, 12, inkS(s.skin))
		cv.ink(3, 11, inkF(0x3A1414))
	}
	if s.zombieArms { return finishCreature(cv, band: 1) }
	let bl: UInt32 = inkF(s.weaponColor)
	let blh: UInt32 = inkF(shadeRGB(s.weaponColor, 1.3))
	let gold: UInt32 = inkF(0xC8A040)
	switch s.weapon {
	case .sword, .cutlass:
		if pose == 0 {
			cv.inkLine(15, 2, 15, 8, bl)
			cv.ink(15, 1, blh)
			cv.inkRect(14, 8, 3, 1, gold)
			cv.ink(15, 9, inkF(0x6A4220))
		} else if pose == 1 {
			cv.inkRect(13, 6, 3, 2, inkS(s.sleeve))
			cv.inkLine(14, 6, 11, 1, bl)
			cv.inkLine(15, 6, 12, 1, blh)
			cv.inkRect(14, 6, 2, 1, gold)
		} else if pose == 2 {
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkRect(15, 8, 1, 1, inkS(s.skin))
			cv.inkRect(16, 6, 1, 5, gold)
			cv.inkLine(17, 8, 20, 8, bl)
			cv.inkLine(17, 7, 20, 7, blh)
			if s.weapon == .cutlass { cv.ink(20, 9, bl); cv.ink(20, 6, blh) }
		}
	case .pistol:
		if pose == 4 || pose == 2 {
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkRect(16, 7, 4, 2, inkF(0x4A4A54))
			cv.inkRect(16, 9, 1, 2, inkF(0x8A5A2A))
			cv.ink(20, 7, inkF(0xFFE080))
		}
	case .bow:
		let wood: UInt32 = inkF(s.weaponColor)
		let str: UInt32 = inkF(0xE8E0D0)
		if pose == 4 || pose == 2 {
			// arm out, string drawn back to the cheek, arrow nocked
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkLine(17, 3, 18, 5, wood)
			cv.inkLine(18, 5, 18, 10, wood)
			cv.inkLine(18, 10, 17, 12, wood)
			cv.inkLine(17, 3, 14, 7, str)
			cv.inkLine(14, 8, 17, 12, str)
			cv.inkLine(14, 8, 20, 8, inkF(0xB08A5A))
			cv.ink(21, 8, inkF(0xD0D0D8))
		} else {
			// carried at the side
			cv.inkLine(15, 4, 16, 6, wood)
			cv.inkLine(16, 6, 16, 10, wood)
			cv.inkLine(16, 10, 15, 12, wood)
			cv.inkLine(15, 5, 15, 11, str)
		}
	case .none:
		break
	}
	if s.shield != 0 && pose == 3 {
		let sh: UInt32 = s.shield
		cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
		cv.inkRect(15, 4, 5, 10, inkF(shadeRGB(sh, 0.6)))
		cv.inkRect(16, 5, 3, 8, inkF(sh))
		cv.inkRect(17, 7, 1, 4, inkF(shadeRGB(sh, 1.4)))
		cv.inkRect(16, 5, 3, 1, inkF(shadeRGB(sh, 1.25)))
	} else if s.shield != 0 {
		// shield worn on the back arm side, low
		cv.inkRect(8, 8, 2, 5, inkF(shadeRGB(s.shield, 0.7)))
		cv.inkRect(8, 9, 1, 3, inkF(s.shield))
	}
	return finishCreature(cv, band: 1)
}

/// frames: 0 idle, 1 walkA, 2 walkB, 3 windup, 4 attack, 5 block, 6 shoot
func humanoidFrames(_ s: HumanStyle) -> [PixelBuf] {
	var out: [PixelBuf] = []
	out.append(humanoidFrame(s, legs: 0, pose: 0))
	out.append(humanoidFrame(s, legs: 1, pose: 0))
	out.append(humanoidFrame(s, legs: 2, pose: 0))
	out.append(humanoidFrame(s, legs: 0, pose: 1))
	out.append(humanoidFrame(s, legs: 0, pose: 2))
	out.append(humanoidFrame(s, legs: 0, pose: 3))
	out.append(humanoidFrame(s, legs: 0, pose: 4))
	return out
}

// MARK: - Character styles

let hairChoices: [UInt32] = [0xC8501E, 0x2B2B30, 0xE8D080, 0x6A3A8A, 0x3A8A5A]
let scarfChoices: [UInt32] = [0xE8C03A, 0xD03A3A, 0x2EB8B0, 0xF0F0F0, 0xE060A8]

func playerStyle(hairIdx: Int, scarfIdx: Int, head: Tier?, chest: Tier?, legs: Tier?) -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xF1C27D
	s.hair = hairChoices[clampI(hairIdx, 0, hairChoices.count - 1)]
	s.scarf = scarfChoices[clampI(scarfIdx, 0, scarfChoices.count - 1)]
	s.shirt = 0x8A5A2E
	s.sleeve = 0x7A4C24
	s.belt = 0xD8B060
	s.pants = 0x3A4A6E
	s.boots = 0x2A2A30
	if let t = head { s.hat = t == .wood ? 0x9A5A2A : t.color }
	if let t = chest {
		let c: UInt32 = t == .wood ? 0x9A5A2A : t.color
		s.shirt = c
		s.sleeve = shadeRGB(c, 0.82)
	}
	if let t = legs {
		let c: UInt32 = t == .wood ? 0x7A4A22 : t.color
		s.pants = shadeRGB(c, 0.85)
		s.boots = shadeRGB(c, 0.6)
	}
	return s
}

/// 0 green zombie, 1 desert husk, 2 drowned
func zombieStyle(_ variant: Int) -> HumanStyle {
	let v: Int = variant >= 0 && variant <= 2 ? variant : 0
	var s = HumanStyle()
	s.skin = [0x76B060, 0xC8B074, 0x6EA4A0][v]
	s.hair = [0x2E5A2E, 0x8A7A4A, 0x2E4A5A][v]
	s.shirt = [0x3A8A8A, 0xA08A5A, 0x4A6A50][v]
	s.sleeve = shadeRGB(s.shirt, 0.85)
	s.belt = 0x3A3030
	s.pants = [0x34407A, 0x7A6A4A, 0x3A4A5A][v]
	s.boots = 0x3A3438
	s.eye = 0xE03A2A
	s.zombieArms = true
	return s
}

/// The Skeleton Knight: a skull under an iron helm, ribs showing, sword and shield
func skeletonStyle() -> HumanStyle {
	var s = HumanStyle()
	s.skull = true
	s.skin = 0xEAE4D2
	s.hair = 0
	s.hat = 0x8C94A2
	s.shirt = 0xDCD6C4
	s.sleeve = 0xD0CAB6
	s.belt = 0x6A5A4A
	s.pants = 0xD0CAB6
	s.boots = 0x8C94A2
	s.weapon = .sword
	s.weaponColor = 0xB8C0CC
	s.shield = 0x8A5A2E
	s.ribs = true
	return s
}

/// The Skeleton Archer: a hooded skull with a longbow and no shield
/// The Bow Zombie, which took the skeleton archer's place: a zombie in a ragged hunter's hood, bow in hand
func zombieArcherStyle() -> HumanStyle {
	var s = zombieStyle(2)
	s.zombieArms = false
	s.hat = 0x4A3A28
	s.shirt = 0x5A6A3A
	s.sleeve = shadeRGB(0x5A6A3A, 0.85)
	s.belt = 0x5A3A20
	s.weapon = .bow
	s.weaponColor = 0x8A5A2A
	return s
}

func skeletonArcherStyle() -> HumanStyle {
	var s = skeletonStyle()
	s.hat = 0x3E4A36
	s.shield = 0
	s.weapon = .bow
	s.weaponColor = 0x8A5A2A
	s.belt = 0x5A4A30
	return s
}

/// Deckhands wear a bandana and an eye patch; the captain a tricorn, a long coat and a beard
func pirateStyle(_ captain: Bool) -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xE0B080
	s.hair = 0x2A1A10
	s.boots = 0x2A2024
	s.weapon = .cutlass
	s.weaponColor = 0xC8CCD4
	if captain {
		s.hat = 0x2A2A3A
		s.hatStyle = 2
		s.shirt = 0x9A2E2E
		s.sleeve = 0x7A2222
		s.belt = 0xD8B060
		s.pants = 0x2E2E3E
		s.coat = true
		s.beard = 0x2A1A10
	} else {
		s.hat = 0xC83A34
		s.hatStyle = 1
		s.shirt = 0xEDEAE0
		s.sleeve = 0xC84A44
		s.belt = 0x3A2A20
		s.pants = 0x6A5440
		s.patch = true
	}
	return s
}

func pirateGunnerStyle() -> HumanStyle {
	var s = pirateStyle(false)
	s.weapon = .pistol
	s.shirt = 0x3E62A0
	s.sleeve = 0x324F84
	s.hat = 0x2E4E86
	s.patch = false
	return s
}

/// The Umbral Imp: red skin, horns, glowing eyes, clawed arms and a tail
func impStyle() -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xD04A34
	s.hair = 0x6A1414
	s.hat = 0x3A1414
	s.hatStyle = 3
	s.shirt = 0x5A1E22
	s.sleeve = 0x4A1418
	s.belt = 0xFFB030
	s.pants = 0x5A1E22
	s.boots = 0x3A1010
	s.eye = 0xFFE040
	s.zombieArms = true
	s.tail = true
	return s
}

// MARK: - Boss sprites (shapes plus hand-placed details, through the same finishing pass)

/// Ursavor, the bear boss: a hulking bear with bone plates along its spine, a scarred eye and an amber glare.
/// Frames: 0-1 walk, 2 rear up (roar / slam wind-up), 3 swipe.
func spriteBearBoss() -> [PixelBuf] {
	let W: Int = 51
	let H: Int = 34
	let fur: UInt32 = 0x5E4230
	let far: UInt32 = 0x46301F
	let muz: UInt32 = 0xA8865E
	let bone: UInt32 = inkF(0xE6DAC0)
	let boneD: UInt32 = inkF(0xA89878)
	let claw: UInt32 = inkF(0xF2ECDC)
	let eye: UInt32 = inkF(0xFFB02E)
	let gnd: Int = H
	var out: [PixelBuf] = []

	func paw(_ b: inout PixelBuf, _ x: Int, _ top: Int, _ c: UInt32, _ claws: Bool) {
		b.inkRect(x, top, 6, gnd - top - 1, inkS(c))
		b.inkRect(x - 1, gnd - 2, 8, 2, inkS(c))
		if claws { b.ink(x + 2, gnd, claw); b.ink(x + 4, gnd, claw); b.ink(x + 6, gnd, claw) }
	}

	for f in 0..<2 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		let s: Int = f == 0 ? 2 : -2
		let bob: Int = f == 0 ? 0 : 1
		let bd: Double = Double(bob)
		paw(&b, 15 - s, 24, far, false)
		paw(&b, 34 + s, 24, far, false)
		b.inkEllipse(9.5, 19 + bd, 8.5, 8.5, inkS(fur))                    // rump
		b.inkEllipse(22, 18 + bd, 18, 10, inkS(fur))                       // body
		b.inkEllipse(30, 13.5 + bd, 11, 9, inkS(fur))                      // shoulder hump
		b.inkEllipse(24, 25.5 + bd, 14, 2.2, inkF(toneD(fur)))             // shadowed belly
		paw(&b, 9 + s, 25, fur, true)
		paw(&b, 29 - s, 25, fur, true)
		// bone plates along the spine
		let plates: [(Double, Double, Double)] = [(7, 12, 3), (12, 9.5, 4), (17.5, 8, 5), (23, 6.5, 5.5), (28.5, 5.5, 6), (34, 6, 5)]
		for p in plates {
			let x: Double = p.0
			let top: Double = p.1 + bd
			b.inkPoly([(x - 1.8, top + 1.5), (x + 0.6, top - p.2), (x + 2.2, top + 1.5)], bone)
			b.ink(Int(x) - 1, Int(top) + 1, boneD)
			b.ink(Int(x) + 1, Int(top) + 1, boneD)
		}
		let hy: Int = 19 + bob
		let hyd: Double = Double(hy)
		let hx: Int = 1
		let hxd: Double = Double(hx)
		let head: UInt32 = mixRGB(fur, muz, 0.2)                            // a shade lighter than the body
		b.inkEllipse(37.5 + hxd, hyd - 6.2, 2.3, 2.3, inkS(far))            // ears
		b.inkEllipse(43 + hxd, hyd - 6.8, 2.3, 2.3, inkS(far))
		b.inkEllipse(41 + hxd, hyd, 7.4, 6.6, inkS(head))                   // head
		b.inkEllipse(46.6 + hxd, hyd + 2.4, 3.8, 2.9, inkS(muz))            // muzzle
		b.inkRect(49 + hx, hy, 2, 2, inkF(0x1E1418))                        // nose
		b.inkLine(43 + hx, hy + 4, 49 + hx, hy + 4, inkF(0x3A2418))         // mouth
		b.ink(45 + hx, hy + 5, claw)
		b.ink(48 + hx, hy + 5, claw)
		b.inkRect(43 + hx, hy - 2, 2, 1, eye)
		b.ink(45 + hx, hy - 2, inkF(0x2A1000))
		b.inkLine(42 + hx, hy - 3, 46 + hx, hy - 4, inkF(0x2C1E16))         // brow
		b.inkLine(42 + hx, hy - 5, 45 + hx, hy + 1, inkF(0xC8A888))         // scar
		out.append(b)
	}

	for pose in 0..<2 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		paw(&b, 15, 27, far, false)
		paw(&b, 25, 27, fur, true)
		if pose == 0 {
			// far arm raised
			b.inkPoly([(17, 15), (21, 14), (17, 3), (13, 4)], inkS(far))
			b.inkEllipse(15, 3.5, 3, 2.6, inkS(far))
			b.ink(13, 0, claw); b.ink(15, 0, claw); b.ink(17, 0, claw)
		} else {
			b.inkPoly([(17, 15), (21, 15), (20, 25), (16, 25)], inkS(far))
		}
		b.inkEllipse(22, 25, 10, 8.5, inkS(fur))                            // belly
		b.inkEllipse(23, 16, 8.5, 8.5, inkS(fur))                           // chest
		b.inkEllipse(23, 31.5, 8, 1.8, inkF(toneD(fur)))
		// plates down the back
		for k in 0..<5 {
			let kd: Double = Double(k)
			let py: Double = 9 + kd * 4.0
			let px: Double = 15.5 - (k < 3 ? kd * 0.9 : (4 - kd) * 0.9 + 1.0)
			b.inkPoly([(px + 1.5, py - 1.7), (px - 3.5, py - 0.3), (px + 1.5, py + 1.7)], bone)
			b.ink(Int(px), Int(py), boneD)
		}
		b.inkEllipse(25.5, 2.8, 2.2, 2.2, inkS(far))
		b.inkEllipse(31, 2.4, 2.2, 2.2, inkS(far))
		b.inkEllipse(29, 8.5, 6.8, 6, inkS(fur))                            // head, roaring
		b.inkEllipse(34.2, 11, 3.6, 2.9, inkS(muz))
		b.inkRect(36, 7, 2, 2, inkF(0x1E1418))
		b.inkRect(32, 11, 5, 3, inkF(0x5A0E10))                             // open mouth
		b.ink(33, 11, claw); b.ink(35, 11, claw); b.ink(34, 13, claw)
		b.inkRect(30, 5, 2, 1, eye)
		b.ink(32, 5, inkF(0x2A1000))
		b.inkLine(29, 4, 33, 3, inkF(0x2C1E16))
		b.inkLine(29, 2, 32, 7, inkF(0xC8A888))
		if pose == 0 {
			// near arm raised high
			b.inkPoly([(26, 17), (31, 18), (40, 5), (36, 3)], inkS(fur))
			b.inkEllipse(39, 3.6, 3.3, 2.8, inkS(fur))
			b.ink(37, 0, claw); b.ink(39, 0, claw); b.ink(41, 0, claw)
		} else {
			// swipe: arm thrown forward, claws spread
			b.inkPoly([(26, 15), (45, 13), (46, 19), (27, 21)], inkS(fur))
			b.inkEllipse(46, 16, 3.6, 4, inkS(fur))
			b.inkLine(49, 12, 51, 11, claw)
			b.inkLine(50, 15, 52, 15, claw)
			b.inkLine(50, 18, 52, 19, claw)
			b.inkLine(49, 20, 50, 22, claw)
		}
		out.append(b)
	}
	return out.map { finishCreature(padBuf($0), band: 2) }
}

/// Tyrannax the Bonecrown: a dark olive hunter with a crown of bone spikes, a striped back and a pale throat.
/// Frames: 0-1 walk, 2 bite (jaw open, head lunging).
func spriteTRex() -> [PixelBuf] {
	let W: Int = 62
	let H: Int = 37
	let skin: UInt32 = 0x5A8A42
	let far: UInt32 = 0x426A32
	let stripe: UInt32 = inkF(0x34522A)
	let belly: UInt32 = inkS(0xDCD4A0)
	let bone: UInt32 = inkF(0xE8DEC4)
	let boneD: UInt32 = inkF(0xAA9C7C)
	let claw: UInt32 = inkF(0xF2ECDC)
	let eye: UInt32 = inkF(0xFFC23A)
	let gnd: Int = H
	let gd: Double = Double(gnd)
	var out: [PixelBuf] = []

	func leg(_ b: inout PixelBuf, _ hipX: Double, _ step: Double, _ c: UInt32, _ near: Bool) {
		b.inkEllipse(hipX, 23, 5.5, 7, inkS(c))                                                       // thigh
		let footX: Double = hipX + step
		let shin: UInt32 = near ? inkF(toneD(c)) : inkS(c)
		b.inkPoly([(hipX - 2.5, 26), (hipX + 2.5, 26), (footX + 1.8, gd - 2), (footX - 1.8, gd - 2)], shin)
		b.inkRect(Int(footX) - 3, gnd - 2, 8, 2, shin)
		b.ink(Int(footX) + 5, gnd - 1, claw)
		b.ink(Int(footX) + 2, gnd - 1, claw)
	}

	for f in 0..<3 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		let step: Double = f == 0 ? 2.5 : (f == 1 ? -2.5 : 0)
		let bob: Double = f == 1 ? 1 : 0
		let bite: Bool = f == 2
		leg(&b, 30, -step, far, false)
		b.inkPoly([(18, 10 + bob), (0, 18 + bob), (1, 20 + bob), (19, 24 + bob)], inkS(skin))            // tail
		b.inkPoly([(9, 16 + bob), (0, 18 + bob), (1, 20 + bob), (10, 20 + bob)], inkF(toneD(skin)))
		b.inkEllipse(26, 17 + bob, 12, 7.5, inkS(skin))                                                 // body
		b.inkPoly([(24, 23 + bob), (35, 21.5 + bob), (40, 17 + bob), (37, 24 + bob), (25, 25.5 + bob)], belly)
		let hx: Double = bite ? 2 : 0
		let hy: Double = bite ? 2 : 0
		let hxi: Int = Int(hx)
		let yo: Double = bob + hy
		let yoi: Int = Int(yo)
		b.inkPoly([(32, 13 + bob), (40, 6 + yo), (44, 13 + yo), (36, 21 + bob)], inkS(skin))               // neck
		b.inkEllipse(47 + hx, 9 + yo, 8, 5.5, inkS(skin))                                                // skull
		b.inkPoly([(47 + hx, 5 + yo), (61, 7 + yo), (61, 11 + yo), (47 + hx, 12 + yo)], inkS(skin))      // snout
		b.ink(59, 8 + yoi, stripe)                                                                       // nostril
		let jy: Double = bite ? 16 : 12
		b.inkPoly([(41 + hx, 12 + yo), (60, jy - 1 + yo), (59, jy + 1.5 + yo), (42 + hx, 16 + yo)], inkF(toneD(skin)))   // lower jaw
		b.inkPoly([(41 + hx, 13.5 + yo), (52, jy + 0.5 + yo), (52, jy + 2 + yo), (42 + hx, 17 + yo)], belly)            // throat
		if bite {
			b.inkPoly([(48 + hx, 11.5 + yo), (61, 11.5 + yo), (59, 14.5 + yo), (49 + hx, 14 + yo)], inkF(0x6A1420))
		}
		var tx: Int = 50 + hxi
		while tx < 61 {
			b.ink(tx, 11 + yoi, claw)
			b.ink(tx + 1, (bite ? Int(jy) - 1 : 12) + yoi, claw)
			tx += 3
		}
		b.inkRect(48 + hxi, 7 + yoi, 2, 1, eye)
		b.ink(49 + hxi, 7 + yoi, inkF(0x201000))
		b.inkLine(45 + hxi, 6 + yoi, 51 + hxi, 5 + yoi, stripe)                                          // brow ridge
		// crown of bone spikes
		for k in 0..<5 {
			let kd: Double = Double(k)
			let cx: Double = 41.5 + hx + kd * 2.4
			let tip: Double = 1.2 + yo - (k == 2 ? 1 : 0)
			b.inkPoly([(cx - 1.2, 4.8 + yo - kd * 0.15), (cx, tip), (cx + 1.2, 4.8 + yo - kd * 0.15)], bone)
			b.ink(Int(cx), Int(4.4 + yo), boneD)
		}
		// back stripes
		let bobi: Int = Int(bob)
		for k in 0..<6 {
			let sx: Int = 15 + k * 4
			b.inkLine(sx, 10 + bobi + abs(k - 3) / 2, sx - 2, 14 + bobi + abs(k - 3) / 2, stripe)
		}
		// little arm
		b.inkLine(39, 19 + bobi, 42, 21 + bobi, inkF(toneD(skin)))
		b.ink(43, 21 + bobi, claw)
		leg(&b, 23, step, skin, true)
		out.append(b)
	}
	return out.map { finishCreature(padBuf($0), band: 2) }
}

// MARK: - Creature table

/// Finished frames and frame roles for every creature
func creatureArt(_ k: MobKind, _ v: Int) -> ([PixelBuf], CreatureAnim) {
	var a = CreatureAnim()
	switch k {
	case .pig: a.idleAlt = 3; return (spritePig(), a)
	case .cow: a.idleAlt = 3; return (spriteCow(), a)
	case .sheep: a.idleAlt = 3; return (v == 1 ? spriteSheepShorn() : spriteSheepWool(), a)
	case .chicken: a.idleAlt = 3; return (spriteChicken(), a)
	case .crow: a.cycle = [0, 1, 2, 1]; return (spriteCrow(), a)
	case .giraffe: a.idleAlt = 3; return (spriteGiraffe(), a)
	case .frog: a.hop = true; return (spriteFrog(), a)
	case .fish: a.cycle = [0, 1]; return (spriteFish(), a)
	case .elephant: a.attack = 3; return (spriteElephant(), a)
	case .bear: a.attack = 3; return (spriteBrownBear(), a)
	case .grizzly: a.attack = 3; return (spriteGrizzly(), a)
	case .polarBear: a.attack = 3; return (spritePolarBear(), a)
	case .tiger: a.attack = 3; return (spriteTiger(), a)
	case .wolf: a.attack = 3; return (v == 1 ? spriteDog() : spriteWildWolf(), a)
	case .cat: return (spriteCat(), a)
	case .zombie: return (humanoidFrames(zombieStyle(v)), a)
	case .skeleton: return (humanoidFrames(skeletonStyle()), a)
	case .slime: a.hop = true; a.attack = 2; return (spriteGreenSlime(), a)
	case .bat: a.cycle = [0, 1, 2, 1]; return (spriteCaveBat(), a)
	case .scorpion: a.attack = 3; return (spriteScorpion(), a)
	case .wraith: a.cycle = [0, 1]; a.attack = 2; return (spriteWraith(), a)
	// a retired kind (villagers are gone): kept so saved creature numbers stay the same
	case .villager: return (humanoidFrames(zombieStyle(v)), a)
	case .pirate: return (humanoidFrames(pirateStyle(false)), a)
	case .pirateGunner: return (humanoidFrames(pirateGunnerStyle()), a)
	case .pirateCaptain: return (humanoidFrames(pirateStyle(true)), a)
	case .imp: return (humanoidFrames(impStyle()), a)
	case .emberSlime: a.hop = true; a.attack = 2; return (spriteEmberSlime(), a)
	case .cinderBat: a.cycle = [0, 1, 2, 1]; return (spriteCinderBat(), a)
	case .bearBoss: return (spriteBearBoss(), a)
	case .rex: return (spriteTRex(), a)
	case .crawler: a.attack = 3; return (spriteCaveCrawler(), a)
	case .golem: return (spriteStoneGolem(), a)
	case .archer: return (humanoidFrames(zombieArcherStyle()), a)
	case .sentinel: a.cycle = [0, 1]; return (spriteCrystalSentinel(), a)
	case .mimic: return (spriteMimic(), a)
	case .warden: return (spriteHollowWarden(), a)
	case .custom: return creatureArt(.zombie, 0)
	}
}

// ===== p05e_newcreatures =====

// MARK: - Sprites for the cave crawler, stone golem, crystal sentinel, mimic and Hollow Warden

/// Cave Crawler: a low, many-legged hunter with a red eye cluster. Frames: 0 idle, 1-2 scuttle, 3 pounce.
func spriteCaveCrawler() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x6A5078), "d": inkS(0x4A3858), "e": inkF(0xFF5A4A), "E": inkF(0xFFB0A0),
									"l": inkF(0x2E2238), "f": inkF(0xE8E0C8), "s": inkF(0x8A6A9A)]
	let body: [String] = [
		"....dbbbd...",
		"..dbbsbsbbb.",
		".dbbbbbbbbeE",
		"..dbdbdbbbef",
	]
	let legs0: [String] = [
		".l.l..l.l.l.",
		"l..l..l..l.l",
	]
	let legs1: [String] = [
		"..l.l.l..l..",
		".l...l..l..l",
	]
	let legs2: [String] = [
		".ll..l.ll...",
		"l...l..l..ll",
	]
	let pounceBody: [String] = [
		"...dbbbd....",
		".dbbsbsbbbb.",
		"dbbbbbbbbbeE",
		".dbdbdbbbbef",
	]
	let pounceLegs: [String] = [
		"l.l......lll",
		".l.........l",
	]
	return composeCreature(12, 6, pal, [
		[(body, 0, 0), (legs0, 0, 4)],
		[(body, 0, 0), (legs1, 0, 4)],
		[(body, 0, 0), (legs2, 0, 4)],
		[(pounceBody, 0, 0), (pounceLegs, 0, 4)],
	])
}

/// Stone Golem: a hulking boulder with glowing eyes, moss on its shoulders and a crystal set in its
/// chest. Frames: 0 idle, 1-2 walk, 3 fists raised, 4 slam, 5 throw.
func spriteStoneGolem() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x6E6A66), "G": inkS(0x8A8682), "s": inkS(0x7A7672), "S": inkS(0x96928C),
									"e": inkF(0x7AF8F0), "m": inkS(0x5E8A3E), "c": inkF(0x8AF0E8), "k": inkF(0x4A4644), "a": inkS(0x6A6662)]
	let head: [String] = [
		"....gggggg....",
		"...gGGGGGGg...",
		"...gGeGGeGg...",
		"...gGGGGGGg...",
		"....gkkkkg....",
	]
	let torso: [String] = [
		"..mmsssssmm...",
		".msSSSSSSSSsm.",
		".sSSSSSSSSSSs.",
		".sSSSSccSSSSs.",
		".sSSSSckSSSSs.",
		"..sSSSSSSSSs..",
		"...ssssssss...",
	]
	let armsDown: [String] = [
		"aa..........aa",
		"aa..........aa",
		"aaa........aaa",
		"aaa........aaa",
		".aa........aa.",
	]
	let legsA: [String] = [
		"...sss..sss...",
		"...sss..sss...",
		"..ssss..ssss..",
		"..kkkk..kkkk..",
	]
	let legsB: [String] = [
		"..sss....sss..",
		"..sss....sss..",
		".ssss....ssss.",
		".kkkk....kkkk.",
	]
	let legsC: [String] = [
		"....ssssss....",
		"....ss..ss....",
		"...sss..sss...",
		"...kkk..kkk...",
	]
	let armsUp: [String] = [
		"aa..........aa",
		"aaa........aaa",
		"aaa........aaa",
		".aa........aa.",
		"..a........a..",
	]
	let armsSlam: [String] = [
		"...........aaa",
		"..........aaaa",
		"..........aaaa",
		"...........aaa",
	]
	let rock: [String] = [
		"...........kk.",
		"..........kggk",
		"..........kggk",
		"...........kk.",
	]
	return composeCreature(14, 20, pal, [
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsA, 0, 12), (["....ssssss...."], 0, 11)],
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsB, 0, 12), (["....ssssss...."], 0, 11)],
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsC, 0, 12), (["....ssssss...."], 0, 11)],
		[(armsUp, 0, 0), (head, 0, 1), (torso, 0, 6), (legsA, 0, 13), (["....ssssss...."], 0, 12)],
		[(head, 0, 2), (torso, 0, 7), (armsSlam, 0, 13), (legsB, 0, 14), (["....ssssss...."], 0, 13)],
		[(rock, 0, 0), (["...........aa.", "...........aa."], 0, 4), (head, 0, 1), (torso, 0, 6), (armsDown, 0, 7), (legsA, 0, 13), (["....ssssss...."], 0, 12)],
	])
}

/// Crystal Sentinel: a floating construct of crystal around a bright core, with shards orbiting it.
/// Frames: 0-1 hovering, 2 charging, 3 striking.
func spriteCrystalSentinel() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["c": inkS(0x2E8E9A), "C": inkS(0x5ECAD2), "H": inkS(0xA8F0F0), "W": inkF(0xF0FFFF),
									"O": inkF(0xFFFFFF), "o": inkF(0x9AF8F0), "k": inkF(0x1E5A66)]
	let core: [String] = [
		".....cc.....",
		"....cHCc....",
		"...cHCCCc...",
		"...cWkWCc...",
		"...cCCCCc...",
		"....cCCc....",
		"............",
		"....cCCc....",
		"...cHooCc...",
		"...cCOOCc...",
		"...cCooCc...",
		"....cCCc....",
		".....cc.....",
		"......c.....",
	]
	let shardsA: [String] = [
		".c........c.",
		"cC........Cc",
		".c........c.",
	]
	let shardsB: [String] = [
		"............",
		".c........c.",
		"cC........Cc",
		".c........c.",
	]
	let below: [String] = [".....cc.....", "......c....."]
	let chargeCore: [String] = [
		"...cHOOCc...",
		"...cOOOOc...",
		"...cHOOCc...",
	]
	let strikeShards: [String] = [
		"..........cC",
		"...........c",
		"..........cC",
	]
	return composeCreature(12, 17, pal, [
		[(core, 0, 0), (shardsA, 0, 7), (below, 0, 15)],
		[(core, 0, 0), (shardsB, 0, 7), (below, 0, 14)],
		[(core, 0, 0), (chargeCore, 0, 8), (["c..........c", "Cc........cC", "c..........c"], 0, 6), (below, 0, 15)],
		[(core, 0, 0), (chargeCore, 0, 8), (strikeShards, 0, 7), (below, 0, 15)],
	])
}

/// Mimic: closed, it is a plain wooden chest; open, a mouthful of teeth. Frames: 0 closed, 1-2 hopping
/// with the lid ajar, 3 biting wide.
func spriteMimic() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0x8F6732), "d": inkS(0xB98A4E), "g": inkF(0xF5D142), "t": inkF(0xF4F0E0),
									"k": inkF(0x2A1010), "r": inkF(0xD04A5A), "e": inkF(0xFFE040)]
	let closed: [String] = [
		"..........",
		"..........",
		"wwwwwwwwww",
		"wddddddddw",
		"wwwwgwwwww",
		"wddddddddw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	let ajar: [String] = [
		"..........",
		"wwwwwwwwww",
		"wddddddeew",
		"wtkttkttkw",
		"kkkkkkkrrk",
		"wtttkttttw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	let wide: [String] = [
		"wwwwwwwww.",
		"wdddddeew.",
		"wtktktktw.",
		"kk.......k",
		"kkkkkkrrrk",
		"wttkttkttw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	return composeCreature(10, 8, pal, [
		[(closed, 0, 0)],
		[(ajar, 0, 0)],
		[(ajar, 0, 0)],
		[(wide, 0, 0)],
	])
}

/// The Hollow Warden: an empty suit of armour under a ragged hood, two violet lights for eyes, carrying a
/// great scythe. Frames: 0-1 hovering, 2 scythe drawn back, 3 sweep, 4 casting.
func spriteHollowWarden() -> [PixelBuf] {
	let W: Int = 30
	let H: Int = 42
	let cloak: UInt32 = 0x34283E
	let cloakHi: UInt32 = 0x4A3A58
	let iron: UInt32 = 0x5C5A6E
	let ironHi: UInt32 = 0x8A88A0
	let hood: UInt32 = 0x2A2034
	let eye: UInt32 = 0xE0B0FF
	let rune: UInt32 = 0xB070FF
	let shaft: UInt32 = 0x8A6A4A
	let blade: UInt32 = 0xD8DCE8
	let edge: UInt32 = 0x9A9EB0
	func base(_ sway: Int) -> PixelBuf {
		var b = PixelBuf(w: W + 2, h: H + 2)
		let ox: Int = 1
		let oy: Int = 1
		// cloak: widening from the shoulders to a ragged hem
		for y in 12..<38 {
			let half: Int = 5 + (y - 12) / 3
			let cx: Int = 13 + ox
			for x in (cx - half)...(cx + half) { b.ink(x, y + oy, inkS(cloak)) }
			b.ink(cx - half + 1, y + oy, inkS(cloakHi))
		}
		for x in 4..<24 {
			let len: Int = (x + sway) % 3 == 0 ? 3 : ((x + sway) % 3 == 1 ? 1 : 2)
			for k in 0..<len where 38 + k < H { b.ink(x + ox, 38 + k + oy, inkS(cloak)) }
		}
		// pauldrons and breastplate
		b.inkRect(6 + ox, 11 + oy, 6, 3, inkS(iron))
		b.inkRect(15 + ox, 11 + oy, 6, 3, inkS(iron))
		b.inkRect(7 + ox, 11 + oy, 4, 1, inkS(ironHi))
		b.inkRect(16 + ox, 11 + oy, 4, 1, inkS(ironHi))
		b.inkRect(10 + ox, 14 + oy, 7, 8, inkS(iron))
		b.inkRect(11 + ox, 14 + oy, 1, 8, inkS(ironHi))
		b.ink(13 + ox, 17 + oy, inkF(rune)); b.ink(13 + ox, 18 + oy, inkF(rune)); b.ink(12 + ox, 18 + oy, inkF(rune)); b.ink(14 + ox, 18 + oy, inkF(rune)); b.ink(13 + ox, 19 + oy, inkF(rune))
		b.inkRect(9 + ox, 22 + oy, 9, 1, inkS(0x6A5A4A))
		// hood with a dark hollow and two lights
		b.inkEllipse(13.5 + Double(ox), 6.0 + Double(oy), 5.2, 5.6, inkS(hood))
		b.inkEllipse(14.2 + Double(ox), 7.2 + Double(oy), 3.2, 3.4, inkF(0x0E0814))
		b.ink(13 + ox, 7 + oy, inkF(eye)); b.ink(16 + ox, 7 + oy, inkF(eye))
		b.ink(13 + ox, 8 + oy, inkF(0x8A5AC0)); b.ink(16 + ox, 8 + oy, inkF(0x8A5AC0))
		return b
	}
	func scythe(_ b: inout PixelBuf, _ pose: Int) {
		let ox: Int = 1
		let oy: Int = 1
		switch pose {
		case 0:
			// upright in the front hand
			b.inkLine(22 + ox, 3 + oy, 22 + ox, 40 + oy, inkF(shaft))
			b.inkLine(22 + ox, 1 + oy, 28 + ox, 4 + oy, inkF(blade))
			b.inkLine(22 + ox, 2 + oy, 28 + ox, 5 + oy, inkF(blade))
			b.inkLine(23 + ox, 3 + oy, 28 + ox, 6 + oy, inkF(edge))
			b.inkLine(28 + ox, 5 + oy, 28 + ox, 8 + oy, inkF(blade))
			b.inkRect(20 + ox, 20 + oy, 3, 3, inkS(iron))
		case 1:
			// drawn back over the shoulder
			b.inkLine(4 + ox, 4 + oy, 20 + ox, 26 + oy, inkF(shaft))
			b.inkLine(3 + ox, 4 + oy, 0 + ox, 11 + oy, inkF(blade))
			b.inkLine(4 + ox, 4 + oy, 1 + ox, 11 + oy, inkF(blade))
			b.inkLine(5 + ox, 4 + oy, 2 + ox, 11 + oy, inkF(edge))
			b.inkRect(18 + ox, 22 + oy, 3, 3, inkS(iron))
		case 2:
			// swept low and level in front
			b.inkLine(6 + ox, 27 + oy, 29 + ox, 27 + oy, inkF(shaft))
			b.inkLine(6 + ox, 28 + oy, 29 + ox, 28 + oy, inkF(shaft))
			b.inkLine(29 + ox, 27 + oy, 26 + ox, 36 + oy, inkF(blade))
			b.inkLine(28 + ox, 28 + oy, 25 + ox, 36 + oy, inkF(blade))
			b.inkLine(27 + ox, 28 + oy, 24 + ox, 35 + oy, inkF(edge))
			b.inkRect(18 + ox, 25 + oy, 3, 3, inkS(iron))
		default:
			// held aside while the free hand casts
			b.inkLine(4 + ox, 6 + oy, 4 + ox, 40 + oy, inkF(shaft))
			b.inkLine(4 + ox, 4 + oy, 0 + ox, 8 + oy, inkF(blade))
			b.inkLine(4 + ox, 5 + oy, 0 + ox, 9 + oy, inkF(blade))
			b.inkRect(20 + ox, 18 + oy, 3, 3, inkS(iron))
			b.inkEllipse(25.0 + Double(ox), 19.5 + Double(oy), 2.4, 2.4, inkF(0x9A5AE0))
			b.inkEllipse(25.0 + Double(ox), 19.5 + Double(oy), 1.2, 1.2, inkF(0xF0D8FF))
		}
	}
	var frames: [PixelBuf] = []
	for (sway, pose) in [(0, 0), (1, 0), (0, 1), (0, 2), (1, 3)] {
		var b: PixelBuf = base(sway)
		scythe(&b, pose)
		frames.append(finishCreature(b, band: 2))
	}
	return frames
}

func creatureSpriteSet(_ k: MobKind, _ v: Int) -> SpriteSet {
	let art: ([PixelBuf], CreatureAnim) = creatureArt(k, v)
	return makeSpriteSet(art.0, hitH: mobDef(k).h, fixedScale: creatureScale, anim: art.1)
}

// ===== p05b_animals =====

// MARK: - Animal and monster sprites (hand-drawn rows; see composeCreature)

/// Pig. Frames: 0 idle, 1-2 walk, 3 grazing.
func spritePig() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["p": inkS(0xF0A0B0), "e": inkS(0xD9788E), "n": inkF(0xD06C84), "k": inkF(0x2A1A22), "h": inkF(0x7A4A50)]
	let frame0: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		".h.h..h.h",
	]
	let frame1: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		"h..h.h..h",
	]
	let frame2: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		"..hh...hh",
	]
	let frame3: [String] = [
		".....e...",
		".ppppppe.",
		"epppppppp",
		".ppppppkp",
		".h.h..hnn",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Cow. Frames: 0 idle, 1-2 walk, 3 grazing.
func spriteCow() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF4F2EC), "s": inkS(0x3A3438), "m": inkS(0xF0B0B8), "k": inkF(0x1E1418), "h": inkF(0xE8DCC0), "l": inkS(0xF4F2EC), "L": inkS(0xCFCAC2), "f": inkF(0x4A3A30), "t": inkS(0x3A3438)]
	let frame0: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		".lL....lL...",
		".ff....ff...",
	]
	let frame1: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		"l..L..l..L..",
		"f..f..f..f..",
	]
	let frame2: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		"..lL...Ll...",
		"..ff...ff...",
	]
	let frame3: [String] = [
		"............",
		"t...........",
		"twwssswwwh.h",
		"twwwsswwswsw",
		".wwwwwwwswkw",
		".wwwwmwwwwmm",
		".lL....lL.mm",
		".ff....ff...",
	]
	return composeCreature(12, 8, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Sheep in full wool. Frames: 0 idle, 1-2 walk, 3 grazing.
func spriteSheepWool() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF2F0E8), "f": inkS(0x4A4450), "k": inkF(0xF4F0E0), "l": inkS(0x4A4450), "h": inkF(0x2A2430)]
	let frame0: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		"..l.l..l.l",
		"..h.h..h.h",
	]
	let frame1: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		".l..l.l..l",
		".h..h.h..h",
	]
	let frame2: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		"...ll...ll",
		"...hh...hh",
	]
	let frame3: [String] = [
		"..w.w.w...",
		".wwwwwww..",
		"wwwwwwwwf.",
		"wwwwwwwfff",
		".wwwwwwfkf",
		"..l.l..lff",
		"..h.h..h..",
	]
	return composeCreature(10, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Shorn sheep (same frames as the woolly one).
func spriteSheepShorn() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xE8C4B4), "f": inkS(0x4A4450), "k": inkF(0xF4F0E0), "l": inkS(0x4A4450), "h": inkF(0x2A2430)]
	let frame0: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		"..l.l..l.l",
		"..h.h..h.h",
	]
	let frame1: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		".l..l.l..l",
		".h..h.h..h",
	]
	let frame2: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		"...ll...ll",
		"...hh...hh",
	]
	let frame3: [String] = [
		"..........",
		"..wwwwww..",
		".wwwwwwwf.",
		".wwwwwwfff",
		"..wwwwwfkf",
		"..l.l..lff",
		"..h.h..h..",
	]
	return composeCreature(10, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Chicken. Frames: 0 idle, 1-2 walk, 3 pecking.
func spriteChicken() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF6F4EE), "r": inkF(0xE04038), "y": inkF(0xF0B030), "k": inkF(0x1E1418)]
	let frame0: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		"..y.y.",
	]
	let frame1: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		".y..y.",
	]
	let frame2: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		"...yy.",
	]
	let frame3: [String] = [
		"......",
		"w.....",
		"wwwwr.",
		".wwwwk",
		"..y.yy",
	]
	return composeCreature(6, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Brown bear. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteBrownBear() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x7A5436), "B": inkS(0x5E402A), "g": inkS(0xB08A5A), "m": inkS(0xC49A68), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		".bBb.....bBb....",
		".bBb.....bBb....",
		"cbBbc...cbBbc...",
	]
	let frame1: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		"bb.Bb...bb.Bb...",
		"bb..Bb..bb..Bb..",
		"cb...Bc.cb...Bc.",
	]
	let frame2: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		"..bBb.....bBb...",
		"..bbB.....bbB...",
		".cbbBc...cbbBc..",
	]
	let frame3: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkmn",
		"bbbbbbbbbbbbbbm.",
		".bbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbmmm",
		".bBb.....bBb....",
		".bBb.....bBb....",
		"cbBbc...cbBbc...",
	]
	return composeCreature(16, 10, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Grizzly: bigger, with a frosted shoulder hump. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteGrizzly() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x8E6236), "B": inkS(0x6A4626), "g": inkS(0xB08A5A), "m": inkS(0xD0A872), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		".bBb.....bBb.....",
		".bBb.....bBb.....",
		"cbBbc...cbBbc....",
	]
	let frame1: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		"bb.Bb...bb.Bb....",
		"bb..Bb..bb..Bb...",
		"cb...Bc.cb...Bc..",
	]
	let frame2: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		"..bBb.....bBb....",
		"..bbB.....bbB....",
		".cbbBc...cbbBc...",
	]
	let frame3: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkmn",
		"bbbbbbbbbbbbbbbm.",
		".bbbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbbmmm",
		".bBb.....bBb.....",
		".bBb.....bBb.....",
		"cbBbc...cbBbc....",
	]
	return composeCreature(17, 11, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Polar bear: long neck, low head. Frames: 0 idle, 1-2 walk, 3 bite.
func spritePolarBear() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0xF0F2F4), "B": inkS(0xC8D0DA), "g": inkS(0xB08A5A), "m": inkS(0xFAFAF6), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		".bBb.....bBb......",
		".bBb.....bBb......",
		"cbBbc...cbBbc.....",
	]
	let frame1: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		"bb.Bb...bb.Bb.....",
		"bb..Bb..bb..Bb....",
		"cb...Bc.cb...Bc...",
	]
	let frame2: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		"..bBb.....bBb.....",
		"..bbB.....bbB.....",
		".cbbBc...cbbBc....",
	]
	let frame3: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkn",
		"bbbbbbbbbbbbbbbbb.",
		".bbbbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbbbbbb",
		".bBb.....bBb......",
		".bBb.....bBb......",
		"cbBbc...cbBbc.....",
	]
	return composeCreature(18, 10, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Tiger. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteTiger() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["o": inkS(0xE8862C), "w": inkS(0xF6EEDC), "s": inkF(0x2E1E1A), "k": inkF(0x1E1418), "n": inkF(0xE06878), "O": inkS(0xC06A22), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4)]
	let frame0: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"...oO......oO.....",
		"...oO......oO.....",
		"...cc......cc.....",
	]
	let frame1: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"..o..O....o..O....",
		".o....O..o....O...",
		".c....c..c....c...",
	]
	let frame2: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"....oO.....Oo.....",
		"....oO.....Oo.....",
		"....cc.....cc.....",
	]
	let frame3: [String] = [
		"s.............o.o.",
		"o..ososososoooooo.",
		".oooososososoosokn",
		"..ooooooooooooooo.",
		"..owwwwwwwwwoowrc.",
		"...oO......oO.....",
		"...oO......oO.....",
		"...cc......cc.....",
	]
	return composeCreature(18, 8, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Wolf: grey, amber eyes, tail low. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteWildWolf() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x8A909A), "G": inkS(0x666C78), "w": inkS(0xC8CCD2), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4), "C": inkF(0xD83A3A), "e": inkF(0xFFD040)]
	let frame0: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"...gG....gG.....",
		"...gG....gG.....",
	]
	let frame1: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"..g..G..g..G....",
		".g....Gg....G...",
	]
	let frame2: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"....gG...Gg.....",
		"....gG...Gg.....",
	]
	let frame3: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggeggn",
		"ggggggggggggggg.",
		"g..gwwwwwwgwrc..",
		"...gG....gG.....",
		"...gG....gG.....",
	]
	return composeCreature(16, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Tamed wolf: golden coat, red collar, tail up. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteDog() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0xD8A860), "G": inkS(0xB08442), "w": inkS(0xF2DCAA), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4), "C": inkF(0xD83A3A), "e": inkF(0x1E1418)]
	let frame0: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"...gG....gG....",
		"...gG....gG....",
	]
	let frame1: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"..g..G..g..G...",
		".g....Gg....G..",
	]
	let frame2: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"....gG...Gg....",
		"....gG...Gg....",
	]
	let frame3: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgekn",
		"..ggggggggCggg.",
		"..gwwwwwwwgwrc.",
		"...gG....gG....",
		"...gG....gG....",
	]
	return composeCreature(15, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Cat. Frames: 0 idle, 1-2 walk.
func spriteCat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["o": inkS(0xE8964A), "s": inkF(0xB8682A), "w": inkS(0xF6E6C8), "k": inkF(0x1E1418), "n": inkF(0xF08898), "O": inkS(0xC07838)]
	let frame0: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		".o.O.oO.",
	]
	let frame1: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		"o..Oo..O",
	]
	let frame2: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		"..oO.Oo.",
	]
	return composeCreature(8, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Elephant. Frames: 0 idle, 1-2 walk, 3 trunk raised (attack).
func spriteElephant() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x9298A2), "G": inkS(0x737A86), "e": inkS(0x7E8492), "E": inkF(0xB8A0A8), "k": inkF(0x1E1418), "t": inkF(0xF6F0E0), "n": inkF(0x5E6470)]
	let farIdle: [String] = [
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
	]
	let tail: [String] = [
		"g",
		"g",
		"g",
		"n",
	]
	let body: [String] = [
		"......gggggggggg.......",
		"...gggggggggggggggg....",
		"..gggggggggggggggggg...",
		".gggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		".ggggggggggggggggggg...",
		"..gggggggggggggggggg...",
	]
	let legsIdle: [String] = [
		"..gggg........gggg...",
		"..gggg........gggg...",
		"..gggg........gggg...",
		"..gggg........gggg...",
		".tgtgt.......tgtgt...",
	]
	let head: [String] = [
		"...gggg...",
		"..gggggg..",
		".eeeggggg.",
		"eeEeegkgg.",
		"eeEeegggg.",
		"eeEeegggg.",
		"eeeeegggt.",
		".eeeggggtt",
		"..eeggg..t",
		"....gggg..",
		".....ggg..",
		"......gg..",
		"......gn..",
	]
	let farA: [String] = [
		"......GGGG....GGGG...",
		"......GGGG....GGGG...",
		".......GGGG..GGGG....",
		".......GGGG..GGGG....",
		".......GGGG..GGGG....",
	]
	let legsA: [String] = [
		".gggg..........gggg..",
		".gggg..........gggg..",
		"gggg............gggg.",
		"gggg............gggg.",
		"tgtg............tgtg.",
	]
	let farB: [String] = [
		"...GGGG.........GGGG.",
		"...GGGG.........GGGG.",
		"..GGGG...........GGGG",
		"..GGGG...........GGGG",
		"..GGGG...........GGGG",
	]
	let legsB: [String] = [
		"...gggg......gggg....",
		"...gggg......gggg....",
		"...gggg......gggg....",
		"...gggg......gggg....",
		"..tgtgt.....tgtgt....",
	]
	let headTrunkUp: [String] = [
		"...gggg.....",
		"..gggggg....",
		".eeeggggg...",
		"eeEeegkggg..",
		"eeEeeggggg..",
		"eeEeegggtgg.",
		"eeeeegggt.g.",
		".eeeggggt.g.",
		"..eeggg..gg.",
		"....gg...g..",
	]
	return composeCreature(26, 20, pal, [
		[(farIdle, 1, 15), (tail, 0, 6), (body, 1, 6), (legsIdle, 1, 15), (head, 16, 1)],
		[(farA, 1, 15), (tail, 0, 6), (body, 1, 6), (legsA, 1, 15), (head, 16, 1)],
		[(farB, 1, 15), (tail, 0, 6), (body, 1, 6), (legsB, 1, 15), (head, 16, 1)],
		[(farIdle, 1, 15), (tail, 0, 6), (body, 1, 6), (legsIdle, 1, 15), (headTrunkUp, 16, 1)],
	], band: 2)
}

/// Giraffe. Frames: 0 idle, 1-2 walk, 3 head dipped.
func spriteGiraffe() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["y": inkS(0xEAC25A), "p": inkF(0xA86A30), "Y": inkS(0xC8A048), "k": inkF(0x1E1418), "h": inkF(0x6A4A2A), "m": inkS(0xD8A870), "w": inkS(0xF4E4B0)]
	let farIdle: [String] = [
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...hh.....hh",
	]
	let tail: [String] = [
		"y",
		"y",
		"y",
		"h",
	]
	let body: [String] = [
		".........yy.",
		".yyyyyyyyyyy",
		"yypyyypyyyyy",
		"yyyyyyyyypyy",
		"ypyypyyyyyyy",
		".yyyyyyyyyy.",
	]
	let legsIdle: [String] = [
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".hh......hh.",
	]
	let neck: [String] = [
		"....h.h",
		"....yyyy",
		"...yykyyy",
		"...yyyyymm",
		"....yyymm.",
		"...yyy....",
		"...ypy....",
		"...yyy....",
		"..yyp.....",
		"..yyy.....",
		"..pyy.....",
		"..yyy.....",
		".yypy.....",
		".yyyy.....",
		".ypyy.....",
		"yyyy......",
	]
	let farA: [String] = [
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....hh..hh..",
	]
	let legsA: [String] = [
		".yy.......yy",
		".yy.......yy",
		"yy.........y",
		"yy........yy",
		"yy........yy",
		"yy........yy",
		"yy........yy",
		"hh........hh",
	]
	let farB: [String] = [
		"..YY......YY",
		".YY.......YY",
		".YY........Y",
		".YY........Y",
		".YY.......YY",
		".YY.......YY",
		".YY.......YY",
		".hh.......hh",
	]
	let legsB: [String] = [
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..hh....hh..",
	]
	return composeCreature(19, 27, pal, [
		[(farIdle, 1, 19), (tail, 0, 14), (body, 1, 13), (legsIdle, 1, 19), (neck, 8, 0)],
		[(farA, 1, 19), (tail, 0, 14), (body, 1, 13), (legsA, 1, 19), (neck, 8, 0)],
		[(farB, 1, 19), (tail, 0, 14), (body, 1, 13), (legsB, 1, 19), (neck, 8, 0)],
		[(farIdle, 1, 19), (tail, 0, 14), (body, 1, 13), (legsIdle, 1, 19), (neck, 8, 1)],
	], band: 2)
}

/// Frog. Frames: 0 sitting, 1 hop.
func spriteFrog() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x5AB040), "G": inkS(0x3E8A30), "y": inkS(0xD8EC98), "e": inkF(0x1E1418)]
	let frame0: [String] = [
		"..g.g.",
		".gggge",
		"Gggyg.",
	]
	let frame1: [String] = [
		"...g.g",
		"Ggggge",
		"G...GG",
	]
	return composeCreature(6, 3, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
	])
}

/// Fish. Frames: 0-1 swim.
func spriteFish() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x5EA8DC), "f": inkS(0x3C7CB8), "w": inkS(0xD4ECF8), "k": inkF(0x1E1418)]
	let frame0: [String] = [
		"f.bbb.",
		"fbbbkb",
		"f.www.",
	]
	let frame1: [String] = [
		"..bbb.",
		"ffbbkb",
		"..www.",
	]
	return composeCreature(6, 3, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
	])
}

/// Crow. Frames: 0 wings up, 1 level, 2 down.
func spriteCrow() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["c": inkS(0x343448), "C": inkS(0x22222E), "y": inkF(0xD8A030), "k": inkF(0xD8D4E0)]
	let frame0: [String] = [
		"..C....",
		"...C...",
		"CccCcky",
		"..cc...",
		".......",
	]
	let frame1: [String] = [
		".......",
		".......",
		"CcccCky",
		"CCCC...",
		".......",
	]
	let frame2: [String] = [
		".......",
		".......",
		"Cccccky",
		"..CC...",
		"...C...",
	]
	return composeCreature(7, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Slime. Frames: 0 resting, 1 airborne, 2 bite.
func spriteGreenSlime() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x58C050), "h": inkF(0xB4F0A0), "c": inkS(0x3E9A3A), "k": inkF(0x1E2A1A), "m": inkF(0x6A1E20), "y": inkF(0xFFD060)]
	let frame0: [String] = [
		".........",
		"..ggggg..",
		".ghhggggg",
		"gggggkgkg",
		"ggcgggggg",
		".ggggggg.",
	]
	let frame1: [String] = [
		"...ggg...",
		"..ghggg..",
		".ggggkgk.",
		".gcgggg..",
		".ccggggg.",
		"..ggggg..",
	]
	let frame2: [String] = [
		".........",
		"..ggggg..",
		".ghhgkgkg",
		"gggggmmmg",
		"ggcggymyg",
		".gggggggg",
	]
	return composeCreature(9, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Ember slime: a magma slime with glowing cracks. Frames as the slime.
func spriteEmberSlime() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0xE86A28), "h": inkF(0xFFC870), "c": inkS(0xC04A1A), "k": inkF(0x3A1008), "m": inkF(0x5A1408), "y": inkF(0xFFD060)]
	let frame0: [String] = [
		".........",
		"..ggggg..",
		".ghhggggg",
		"gggggkgkg",
		"ggyggggyg",
		".gggggyg.",
	]
	let frame1: [String] = [
		"...ggg...",
		"..ghggg..",
		".ggggkgk.",
		".gygggg..",
		".gggyggg.",
		"..ggggg..",
	]
	let frame2: [String] = [
		".........",
		"..ggggg..",
		".ghhgkgkg",
		"gggggmmmg",
		"ggyggymyg",
		".gggggggg",
	]
	return composeCreature(9, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Cave bat. Frames: 0 wings up, 1 level, 2 down.
func spriteCaveBat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x4A3A5E), "w": inkS(0x6A5480), "k": inkF(0xFF4A4A)]
	let frame0: [String] = [
		"w.......w",
		"ww.b.b.ww",
		".wwbbbww.",
		"...bkb...",
		".........",
	]
	let frame1: [String] = [
		".........",
		"...b.b...",
		"wwwbbbwww",
		".w.bkb.w.",
		".........",
	]
	let frame2: [String] = [
		".........",
		"...b.b...",
		"..wbbbw..",
		".wwbkbww.",
		"w.......w",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Cinder bat: charcoal body, ember wings. Frames as the cave bat.
func spriteCinderBat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x3A2A2A), "w": inkS(0xE06A28), "k": inkF(0xFFD040)]
	let frame0: [String] = [
		"w.......w",
		"ww.b.b.ww",
		".wwbbbww.",
		"...bkb...",
		".........",
	]
	let frame1: [String] = [
		".........",
		"...b.b...",
		"wwwbbbwww",
		".w.bkb.w.",
		".........",
	]
	let frame2: [String] = [
		".........",
		"...b.b...",
		"..wbbbw..",
		".wwbkbww.",
		"w.......w",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Scorpion. Frames: 0 idle, 1-2 walk, 3 sting.
func spriteScorpion() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["a": inkS(0xC88A40), "A": inkS(0xA87034), "d": inkS(0x9A6430), "s": inkF(0xE85030), "k": inkF(0x1E1418), "l": inkS(0x9A6430)]
	let frame0: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	let frame1: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		"l.l.l.l....",
	]
	let frame2: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	let frame3: [String] = [
		"....aAas...",
		"..aA.......",
		".a.........",
		"aAaAaAa...d",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	return composeCreature(11, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Wraith. Frames: 0-1 drifting, 2 grab.
func spriteWraith() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["r": inkS(0x5A3A8A), "R": inkS(0x3E2668), "v": inkF(0x140A20), "e": inkF(0xFFE070), "c": inkF(0xC8C0D8)]
	let frame0: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvr.",
		"rrvvvvrr.",
		"rrrrrrcc.",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		".R.Rr.r..",
		"...R...r.",
	]
	let frame1: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvr.",
		"rrvvvvrr.",
		"rrrrrrcc.",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		"..RR.rr..",
		".R..r..r.",
	]
	let frame2: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvrc",
		"rrvvvvrrc",
		"rrrrrrrcc",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		".R.Rr.r..",
		"...R...r.",
	]
	return composeCreature(9, 12, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

// ===== p05c_bosses =====

// MARK: - Boat and vehicle-part sprites

func spritePirateBoat() -> PixelBuf {
	var b = PixelBuf(w: 76, h: 40)
	let wood: UInt32 = 0x6A4220
	let woodHi: UInt32 = 0x8A5A2E
	let woodLo: UInt32 = 0x3E2610
	// hull rows
	for y in 22..<34 {
		let k: Int = y - 22
		let x0: Int = 4 + k
		let x1: Int = 70 - k
		b.rect(x0, y, x1 - x0, 1, (y % 3 == 0) ? woodLo : wood)
	}
	b.rect(3, 21, 68, 2, woodHi)
	b.rect(4, 22, 66, 1, 0xA8743A)
	// cannon ports
	var p: Int = 16
	while p < 60 {
		b.rect(p, 26, 3, 3, 0x14100A)
		b.set(p + 1, 27, 0x6A6A70)
		p += 12
	}
	// rails
	b.rect(5, 17, 64, 1, woodHi)
	var rp: Int = 5
	while rp < 70 {
		b.rect(rp, 17, 1, 5, wood)
		rp += 6
	}
	// bowsprit
	b.line(70, 21, 75, 16, wood)
	// mast and yard
	b.rect(36, 3, 3, 18, woodHi)
	b.rect(36, 3, 1, 18, wood)
	b.rect(24, 6, 27, 2, woodHi)
	// sail
	b.rect(25, 8, 25, 11, 0xE8E0C8)
	b.rect(25, 8, 25, 1, 0xC8C0A8)
	for i in 0..<6 {
		b.rect(26 + i * 4, 17 + (i % 2), 2, 2, 0xE8E0C8)
		b.rect(27 + i * 4, 9, 1, 8, 0xD0C8B0)
	}
	// skull emblem
	b.rect(35, 10, 5, 4, 0x1A1A1E)
	b.set(36, 11, 0xE8E0C8); b.set(38, 11, 0xE8E0C8)
	b.rect(36, 14, 3, 1, 0x1A1A1E)
	// flag
	b.rect(39, 0, 8, 4, 0x1A1A1E)
	b.set(42, 1, 0xE8E0C8)
	b.rect(39, 2, 2, 1, 0x1A1A1E)
	b.outline(0x0A0604)
	return b
}

func partBuf(_ p: PartType) -> PixelBuf {
	var b = PixelBuf(w: 8, h: 8)
	switch p {
	case .frame:
		b.rect(0, 0, 8, 1, 0xA8783A); b.rect(0, 7, 8, 1, 0x6A4A22)
		b.rect(0, 0, 1, 8, 0xA8783A); b.rect(7, 0, 1, 8, 0x6A4A22)
		b.line(1, 1, 6, 6, 0x8A5A2E); b.line(1, 6, 6, 1, 0x8A5A2E)
	case .wheel:
		b.ellipse(4, 4, 4, 4, 0x1E1E22)
		b.ellipse(4, 4, 2.4, 2.4, 0xA0A0AA)
		b.set(4, 4, 0x3A3A44)
		b.set(3, 3, 0xD8D8E0)
	case .engine:
		b.rect(0, 1, 8, 6, 0x6A6A74)
		b.rect(0, 1, 8, 1, 0x9A9AA4)
		b.rect(1, 3, 4, 2, 0xE06A2A)
		b.rect(6, 3, 2, 2, 0x3A3A44)
		b.rect(2, 0, 1, 1, 0xA8A8B0); b.rect(5, 0, 1, 1, 0xA8A8B0)
	case .steering:
		b.ellipse(4, 4, 3.4, 3.4, 0x8A5A2E)
		b.ellipse(4, 4, 1.8, 1.8, 0)
		b.rect(3, 6, 2, 2, 0x4A4A52)
	case .seat:
		b.rect(1, 0, 2, 6, 0x9A3A3A)
		b.rect(1, 5, 6, 2, 0xB04A4A)
		b.rect(1, 7, 1, 1, 0x4A4A52); b.rect(6, 7, 1, 1, 0x4A4A52)
	case .fuelTank:
		b.rect(1, 1, 6, 6, 0xC03A3A)
		b.rect(1, 1, 6, 1, 0xE06A6A)
		b.rect(3, 0, 2, 1, 0x4A4A52)
		b.rect(2, 3, 4, 2, 0xF0E0A0)
	case .hull:
		b.rect(0, 3, 8, 2, 0xB98A4E)
		b.rect(0, 5, 8, 2, 0x7A5628)
		b.rect(1, 7, 6, 1, 0x4A3216)
		b.rect(0, 2, 8, 1, 0xE8E0C8)
	case .propeller:
		b.rect(3, 0, 2, 8, 0x9A9AA4)
		b.rect(0, 3, 8, 2, 0x7A7A84)
		b.rect(3, 3, 2, 2, 0x4A4A52)
	case .paddle:
		b.line(0, 7, 5, 2, 0x8A5A2E)
		b.rect(5, 0, 3, 4, 0xB98A4E)
	case .offroadWheel:
		b.ellipse(4, 4, 4, 4, 0x18181C)
		for k in 0..<8 {
			let a: Double = Double(k) / 8.0 * 2.0 * Double.pi
			b.set(Int((4.0 + cos(a) * 3.6).rounded()), Int((4.0 + sin(a) * 3.6).rounded()), 0x3A3A42)
		}
		b.ellipse(4, 4, 2.0, 2.0, 0xC89040)
		b.set(4, 4, 0x4A3A20)
		b.set(3, 3, 0xF0C060)
	case .headlight:
		b.rect(0, 2, 4, 4, 0x5A5A64); b.rect(0, 2, 4, 1, 0x8A8A94)
		b.rect(4, 1, 3, 6, 0x9A9AA4); b.rect(5, 2, 2, 4, 0xFFF0A0); b.set(6, 3, 0xFFFFFF); b.set(7, 4, 0xFFF0A0)
	case .cargo:
		b.rect(0, 0, 8, 8, 0x8F6732); b.rect(1, 1, 6, 6, 0xB98A4E)
		b.line(1, 1, 6, 6, 0x8F6732); b.line(1, 6, 6, 1, 0x8F6732)
		b.rect(0, 0, 8, 1, 0x6A6A74); b.rect(0, 7, 8, 1, 0x6A6A74)
	case .drill, .diamondDrill, .voidDrill:
		// drawn pointing right; the renderer turns it to face its open side
		let bit: UInt32 = p == .drill ? 0xC8CCD4 : (p == .diamondDrill ? 0x6FE6EC : 0xB070FF)
		b.rect(0, 1, 3, 6, 0x5A5A64); b.rect(0, 1, 3, 1, 0x8A8A94)
		b.rect(3, 1, 2, 6, bit); b.rect(5, 2, 1, 4, bit); b.rect(6, 3, 1, 2, bit); b.set(7, 3, bit); b.set(7, 4, shadeRGB(bit, 0.7))
		b.set(3, 2, shadeRGB(bit, 0.65)); b.set(4, 4, shadeRGB(bit, 0.65)); b.set(3, 6, shadeRGB(bit, 0.65)); b.set(5, 5, shadeRGB(bit, 0.65))
	}
	b.outline(0x1A1410)
	return b
}

// ===== p06_worldgen =====

// MARK: - World generation (deterministic, chunk based)

enum Biome: Int, Codable {
	case ocean, plains, forest, desert, tundra, jungle, savanna, swamp, mountain, umbral

	var name: String {
		switch self {
		case .ocean: return "Ocean"
		case .plains: return "Plains"
		case .forest: return "Forest"
		case .desert: return "Desert"
		case .tundra: return "Snowy Tundra"
		case .jungle: return "Jungle"
		case .savanna: return "Savanna"
		case .swamp: return "Swamp"
		case .mountain: return "Mountains"
		case .umbral: return "Umbral Realm"
		}
	}
}

enum Dimension: Int, Codable {
	case overworld, umbral
	/// appended: the three custom dimension slots a world's mods can fill (see ModDimension)
	case custom0, custom1, custom2
}

enum LairKind: Int { case bear, rex }

struct Col {
	var h: Int
	var biome: Biome
	var land: Double
	var mtn: Double
	var swamp: Double
}

struct VillageSite {
	var cell: Int
	var x: Int
	var halfW: Int
	var seed: UInt64
	var ground: Int
	var biome: Biome
}

enum RareKind: Int {
	case house, tower, fort, camp, overgrown, bunker
}

struct RareSite {
	var cell: Int
	var x: Int
	var kind: RareKind
	var seed: UInt64
}

/// A flat world's pond: a bowl of water whose surface is level with the ground
struct PondSite {
	var cx: Int
	var halfW: Int
	var depth: Int
}

struct LairInfo {
	var kind: LairKind
	var cx: Int
	var k: Int
}

/// Memoised world-generation lookups. Column, village and ruin queries are pure functions of the
/// seed, but chunk generation asked for the same ones thousands of times (every column checks three
/// village cells, and every village check samples ~14 columns). A class so the value-type WorldGen
/// can share it.
final class GenCache {
	var cols: [Int: Col] = [:]
	var villages: [Int: VillageSite?] = [:]
	var rares: [Int: RareSite?] = [:]
	var ponds: [Int: PondSite?] = [:]
	var grottos: [Int: GrottoSite?] = [:]
	var mines: [Int: MineSite?] = [:]
	/// the Warden's citadel, worked out once (nil inside = this world has none)
	var citadel: CitadelSite?? = nil
	var hits: Int = 0
	var misses: Int = 0

	func clear() {
		cols.removeAll(keepingCapacity: true)
		villages.removeAll(keepingCapacity: true)
		rares.removeAll(keepingCapacity: true)
		ponds.removeAll(keepingCapacity: true)
		grottos.removeAll(keepingCapacity: true)
		mines.removeAll(keepingCapacity: true)
	}

	/// Keeps memory bounded in infinite worlds
	func trim() {
		if cols.count > 24_000 { cols.removeAll(keepingCapacity: true) }
		if villages.count > 4_000 { villages.removeAll(keepingCapacity: true) }
		if rares.count > 8_000 { rares.removeAll(keepingCapacity: true) }
		if ponds.count > 8_000 { ponds.removeAll(keepingCapacity: true) }
		if grottos.count > 4_000 { grottos.removeAll(keepingCapacity: true) }
		if mines.count > 4_000 { mines.removeAll(keepingCapacity: true) }
	}
}

/// Choices made when a world is created; saved with the world so it keeps generating the same way
struct WorldOptions: Codable, Equatable {
	/// flat terrain: one surface height and the same layers everywhere (no caves, seas or mountains)
	var flat: Bool = false
	/// flat worlds only: trees and plants on the surface
	var trees: Bool = true
	/// flat worlds only: ruins, mines and boss lairs (the buried portal chamber is always there)
	var structures: Bool = true
	/// flat worlds only: caves, underground lakes and deep lava, all below an unbroken crust
	var caves: Bool = false
	/// flat worlds only: small ponds set into the ground, their water level with the surface
	var ponds: Bool = false

	static let standard: WorldOptions = WorldOptions()

	enum CodingKeys: String, CodingKey {
		case flat, trees, structures, caves, ponds
	}
}

extension WorldOptions {
	/// Saves from earlier versions lack the newer keys. They decode with those features off, so the
	/// terrain such a world has not generated yet still matches the terrain it already has.
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		flat = try c.decodeIfPresent(Bool.self, forKey: .flat) ?? false
		trees = try c.decodeIfPresent(Bool.self, forKey: .trees) ?? true
		structures = try c.decodeIfPresent(Bool.self, forKey: .structures) ?? true
		caves = try c.decodeIfPresent(Bool.self, forKey: .caves) ?? false
		ponds = try c.decodeIfPresent(Bool.self, forKey: .ponds) ?? false
	}
}

struct WorldGen {
	let cache: GenCache = GenCache()
	let seed: UInt64
	let infinite: Bool
	let width: Int
	let spawnX: Int
	/// 1 = original rules (kept for worlds saved before ocean basins), 2 = with ocean basins,
	/// 3 = buildings and lairs that never wall off the way along the ground, birch and pine trees,
	/// surface landmarks, crystal grottos and abandoned mines, 4 = mines grown into branching networks
	/// (side rooms, drifts down ladders, dead ends, collapses hiding chests, a great chamber),
	/// 5 = no villages (worlds saved earlier keep the villages they already have, empty of villagers),
	/// 6 = more trees (and a grove around the spawn), iron from higher up, a little more coal, copper
	/// and tin, and seas about a fifth narrower
	let genVersion: Int
	static let currentVersion: Int = 6
	let options: WorldOptions
	let rareChance: Double
	let zones: [Int]
	var portalX: Int
	var portalY: Int
	static let H: Int = 560
	static let sea: Int = 120
	static let villageCell: Int = 640
	static let rareCell: Int = 192
	static let finiteWidth: Int = 4096
	static let edgeOcean: Int = 520
	/// surface row of flat worlds: the height boss lairs are built at, ten rows above sea level
	static let flatSurface: Int = WorldGen.sea - 10
	/// rows of solid ground kept under a flat world's surface before any cave may open
	static let flatCrust: Int = 16

	var hasTrees: Bool { return !options.flat || options.trees }
	/// Structures built so the ground can always be walked through: doors at both ends, walk-through
	/// posts, ruins with gateways, lair rims and ribs a jump clears. Worlds saved with older rules keep
	/// their structures exactly (their unexplored ground must match what they already have), except
	/// flat worlds, where a wall across the only way along is a dead end.
	var passableStructures: Bool { return genVersion >= 3 || options.flat }
	var hasStructures: Bool { return !options.flat || options.structures }
	/// Villages are only generated for worlds saved before generator version 5, so their unexplored
	/// ground matches what they already have. New worlds have none.
	var hasVillages: Bool { return genVersion < 5 && hasStructures }

	/// Finite worlds lay biome zones out in a seeded order so every biome is always present.
	/// climate ids: 0 tundra, 1 plains, 2 forest, 3 desert, 4 jungle, 5 savanna, 6 swamp
	static func makeZones(_ seed: UInt64, _ infinite: Bool) -> [Int] {
		if infinite { return [] }
		var pool: [Int] = [0, 3, 5, 6, 1, 2]
		let extra: [Int] = [0, 3, 5, 1, 2]
		pool[5] = extra[Int(hash2(7, 7, seed) * 5.0) % 5]
		var rng = RNG(seed &+ 4242)
		var i: Int = pool.count - 1
		while i > 0 {
			let j: Int = rng.int(i + 1)
			pool.swapAt(i, j)
			i -= 1
		}
		var z: [Int] = [Int](repeating: 1, count: 9)
		z[1] = 4
		z[4] = hash2(8, 8, seed) < 0.5 ? 1 : 2
		z[7] = 2
		let slots: [Int] = [0, 2, 3, 5, 6, 8]
		for k in 0..<6 { z[slots[k]] = pool[k] }
		return z
	}

	init(seed: UInt64, infinite: Bool, rareChance: Double, genVersion: Int = WorldGen.currentVersion, options: WorldOptions = .standard) {
		self.genVersion = genVersion
		self.options = options
		self.seed = seed
		self.infinite = infinite
		self.width = infinite ? 2_000_000_000 : WorldGen.finiteWidth
		self.spawnX = infinite ? 0 : WorldGen.finiteWidth / 2
		self.rareChance = rareChance
		self.zones = WorldGen.makeZones(seed, infinite)
		// provisional values so methods can be used while searching for the portal
		self.portalX = 0
		self.portalY = 0
		let hs: Double = hash2(1, 2, seed)
		let dist: Int = infinite ? 1500 + Int(hs * 1800.0) : 300 + Int(hs * 400.0)
		let side: Int = hash2(3, 4, seed) < 0.5 ? -1 : 1
		var found: Int = spawnX + side * dist
		var ok: Bool = false
		for attempt in 0..<4 {
			let sd: Int = attempt % 2 == 0 ? side : -side
			let dd: Int = attempt < 2 ? dist : (infinite ? 2400 : 520)
			var step: Int = 0
			while step < 400 && !ok {
				let off: Int = ((step % 2 == 0) ? 1 : -1) * ((step + 1) / 2) * 5
				let x: Int = spawnX + sd * dd + off
				let c: Col = options.flat ? WorldGen.flatColStatic(seed, infinite, width, spawnX, zones, x, lairs: false) : WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2, smallSeas: genVersion >= 6)
				if c.biome != .ocean && c.biome != .swamp && c.land > 0.5 && WorldGen.lairStatic(spawnX, infinite, x, 230) == nil && abs(x - spawnX) < 3800 && abs(x - spawnX) > 200 {
					found = x
					ok = true
				}
				step += 1
			}
			if ok { break }
		}
		self.portalX = found
		self.portalY = 350 + Int(hash2(5, 6, seed) * 60.0)
	}

	// MARK: lairs

	static func lairStatic(_ spawnX: Int, _ infinite: Bool, _ x: Int, _ radius: Int) -> LairInfo? {
		let period: Int = 4096
		let bases: [Int] = [spawnX + 1000, spawnX - 1100]
		for i in 0..<2 {
			let base: Int = bases[i]
			var k: Int = Int((Double(x - base) / Double(period)).rounded())
			if !infinite { k = 0 }
			let cx: Int = base + k * period
			if abs(x - cx) < radius { return LairInfo(kind: i == 0 ? .bear : .rex, cx: cx, k: k) }
		}
		return nil
	}

	func lairAt(_ x: Int, radius: Int = 150) -> LairInfo? {
		if !hasStructures { return nil }
		return WorldGen.lairStatic(spawnX, infinite, x, radius)
	}

	func lairCenters(near x: Int) -> [LairInfo] {
		var out: [LairInfo] = []
		if !hasStructures { return out }
		let period: Int = 4096
		let bases: [Int] = [spawnX + 1000, spawnX - 1100]
		for i in 0..<2 {
			let base: Int = bases[i]
			let kc: Int = infinite ? Int((Double(x - base) / Double(period)).rounded()) : 0
			let ks: [Int] = infinite ? [kc - 1, kc, kc + 1] : [0]
			for k in ks { out.append(LairInfo(kind: i == 0 ? .bear : .rex, cx: base + k * period, k: k)) }
		}
		return out
	}

	// MARK: climate & terrain

	static let zoneClimate: [(Double, Double)] = [
		(0.14, 0.50), (0.50, 0.33), (0.50, 0.64), (0.88, 0.14), (0.88, 0.88), (0.88, 0.50), (0.50, 0.90)
	]

	/// position inside the zone layout: 0 = centre of first zone ... count-1 = centre of last
	static func zoneCoord(_ width: Int, _ count: Int, _ x: Int) -> Double {
		let x0: Double = Double(WorldGen.edgeOcean)
		let zw: Double = (Double(width) - 2.0 * x0) / Double(count)
		return (Double(x) - x0) / zw - 0.5
	}

	static func climate(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ zones: [Int], _ x: Int) -> (Double, Double) {
		let fx: Double = Double(x)
		var temp: Double = fbm1(fx / 700.0, seed &+ 11, 2)
		var humid: Double = fbm1(fx / 520.0, seed &+ 12, 2)
		if infinite || zones.count < 2 {
			temp = 0.5 + (temp - 0.5) * 1.3
			humid = 0.5 + (humid - 0.5) * 1.3
			return (temp, humid)
		}
		let t: Double = clampD(zoneCoord(width, zones.count, x), 0, Double(zones.count - 1) - 0.0001)
		let i: Int = Int(t)
		let f: Double = t - Double(i)
		let s: Double = smooth(clampD((f - 0.3) / 0.4, 0, 1))
		let a: (Double, Double) = zoneClimate[zones[i]]
		let b: (Double, Double) = zoneClimate[zones[i + 1]]
		temp = lerpD(a.0, b.0, s) + (temp - 0.5) * 0.30
		humid = lerpD(a.1, b.1, s) + (humid - 0.5) * 0.30
		return (temp, humid)
	}

	/// 0...1 bump marking a mountain range centred somewhere near x
	static func rangeBump(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ x: Int) -> Double {
		var best: Double = 0
		if infinite {
			let cellW: Int = 1100
			let c0: Int = floorDiv(x, cellW)
			for c in (c0 - 1)...(c0 + 1) {
				if hash2(c, 302, seed) > 0.52 { continue }
				let cen: Int = c * cellW + 200 + Int(hash2(c, 303, seed) * 700.0)
				let hw: Double = 130.0 + hash2(c, 304, seed) * 110.0
				let b: Double = smooth(clampD(1.0 - Double(abs(x - cen)) / hw, 0, 1))
				best = max(best, b)
			}
		} else {
			let zw: Double = (Double(width) - 2.0 * Double(WorldGen.edgeOcean)) / 9.0
			let ka: Int = 2 + Int(hash2(1, 305, seed) * 2.0)
			let kb: Int = 6 + Int(hash2(2, 305, seed) * 2.0)
			let ca: Double = Double(WorldGen.edgeOcean) + zw * Double(ka) + (hash2(1, 307, seed) - 0.5) * 80.0
			let cb: Double = Double(WorldGen.edgeOcean) + zw * Double(kb) + (hash2(2, 307, seed) - 0.5) * 80.0
			let cs: [Double] = [ca, cb]
			for k in 0..<2 {
				let hw: Double = 160.0 + hash2(k, 306, seed) * 70.0
				let b: Double = smooth(clampD(1.0 - abs(Double(x) - cs[k]) / hw, 0, 1))
				best = max(best, b)
			}
		}
		return best
	}

	/// Lair centres near x (bear at spawn+1000, rex at spawn-1100, repeating every 4096 in infinite worlds)
	static func lairCentersStatic(_ spawnX: Int, _ infinite: Bool, _ x: Int) -> [Int] {
		var out: [Int] = []
		for base in [spawnX + 1000, spawnX - 1100] {
			if !infinite { out.append(base); continue }
			let k: Int = Int((Double(x - base) / 4096.0).rounded())
			for kk in (k - 1)...(k + 1) { out.append(base + kk * 4096) }
		}
		return out
	}

	/// One ocean basin: centre, half width of the open water, and the coastal ramp width
	struct Basin {
		var center: Int
		var halfW: Int
		var ramp: Int
	}

	/// The guaranteed sea near spawn, on a seeded side, so every world has an ocean within reach
	/// (narrower from generator 6: `small`)
	static func homeBasin(_ seed: UInt64, _ spawnX: Int, small: Bool = false) -> Basin {
		let side: Int = hash2(41, 42, seed) < 0.5 ? -1 : 1
		let off: Int = 560 + Int(hash2(43, 44, seed) * 120.0)
		if small { return Basin(center: spawnX + side * off, halfW: 112 + Int(hash2(45, 46, seed) * 38.0), ramp: 90) }
		return Basin(center: spawnX + side * off, halfW: 150 + Int(hash2(45, 46, seed) * 50.0), ramp: 110)
	}

	/// Random large basins in infinite worlds (about two in five 1600-wide cells), kept clear of spawn and lairs
	static func cellBasin(_ seed: UInt64, _ spawnX: Int, _ c: Int, small: Bool = false) -> Basin? {
		if hash2(c, 401, seed) > 0.26 { return nil }
		let cellW: Int = 1600
		var hw: Int = 140 + Int(hash2(c, 402, seed) * 220.0)
		let cen: Int = c * cellW + hw + 140 + Int(hash2(c, 403, seed) * Double(max(1, cellW - 2 * hw - 280)))
		if abs(cen - spawnX) < hw + 900 { return nil }
		for lc in lairCentersStatic(spawnX, true, cen) where abs(cen - lc) < hw + 330 { return nil }
		// generator 6: the same seas, a quarter narrower, with shorter shelving coasts
		if small {
			hw = hw * 3 / 4
			return Basin(center: cen, halfW: hw, ramp: 105)
		}
		return Basin(center: cen, halfW: hw, ramp: 140)
	}

	/// 0...1: how strongly x lies inside an ocean basin (1 = open sea, ramping down over the coast)
	static func oceanBasin(_ seed: UInt64, _ infinite: Bool, _ spawnX: Int, _ x: Int, small: Bool = false) -> Double {
		func weight(_ b: Basin) -> Double {
			let d: Double = Double(abs(x - b.center))
			return 1.0 - smooth(clampD((d - Double(b.halfW)) / Double(b.ramp), 0, 1))
		}
		var w: Double = weight(homeBasin(seed, spawnX, small: small))
		if infinite {
			let c0: Int = floorDiv(x, 1600)
			for c in (c0 - 1)...(c0 + 1) {
				if let b = cellBasin(seed, spawnX, c, small: small) { w = max(w, weight(b)) }
			}
		}
		return w
	}

	static func colBaseStatic(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ spawnX: Int, _ zones: [Int], _ x: Int, basins: Bool = true, smallSeas: Bool = false) -> Col {
		let fx: Double = Double(x)
		let H: Int = WorldGen.H
		let sea: Int = WorldGen.sea
		// generator 6: seas and continents a little narrower, so a crossing is shorter
		var land: Double = fbm1(fx / (smallSeas ? 700.0 : 800.0), seed &+ 1, 3)
		if !infinite {
			let e: Double = Double(min(x, width - 1 - x))
			let eo: Double = Double(WorldGen.edgeOcean)
			if e < eo { land *= smooth(clampD(e / eo, 0, 1)) }
			if x < 0 || x >= width { land = 0 }
			if zones.count > 1 && e > eo * 0.55 {
				// guarantee some dry land in the middle of every biome zone
				let zc: Double = zoneCoord(width, zones.count, x) + 0.5
				let fr: Double = abs(zc - zc.rounded(.down) - 0.5)
				let wgt: Double = 1.0 - smooth(clampD((fr - 0.2) / 0.2, 0, 1))
				land = lerpD(land, max(land, 0.62), wgt)
			}
		}
		let ds: Double = Double(abs(x - spawnX))
		if ds < 320 { land = lerpD(land, max(land, 0.64), min(1.0, (1.0 - ds / 320.0) * 1.6)) }
		var lw: Double = 0
		var forced: Biome? = nil
		if let L = WorldGen.lairStatic(spawnX, infinite, x, 150) {
			let d: Double = Double(abs(x - L.cx))
			lw = 1.0 - smooth(clampD((d - 60.0) / 90.0, 0, 1))
			land = max(land, lerpD(land, 0.65, lw))
			if d < 120 { forced = L.kind == .bear ? .forest : .jungle }
		}
		// generator 6: the open sea the land field makes on its own ends sooner (land just under the
		// shore line is lifted a little, so coasts move out to sea; the deep water is unchanged)
		if smallSeas && land < 0.50 && land > 0.25 {
			land += 0.06 * (1.0 - smooth(clampD(abs(land - 0.40) / 0.09, 0, 1)))
		}
		// ocean basins pull the land value down into deep water (after the spawn/lair guarantees,
		// which basins are placed well away from)
		let basin: Double = basins ? WorldGen.oceanBasin(seed, infinite, spawnX, x, small: smallSeas) : 0
		if basin > 0 { land = min(land, lerpD(land, 0.17, basin)) }
		let mraw: Double = max(fbm1(fx / 420.0, seed &+ 3, 2) - 0.08, 0.56 + 0.40 * WorldGen.rangeBump(seed, infinite, width, x))
		var mtn: Double = smooth(clampD((mraw - 0.60) / 0.16, 0, 1)) * clampD((land - 0.45) / 0.1, 0, 1)
		mtn *= clampD((ds - 170.0) / 130.0, 0, 1)
		if lw > 0 { mtn *= (1.0 - lw) }
		let cl: (Double, Double) = WorldGen.climate(seed, infinite, width, zones, x)
		let temp: Double = cl.0
		let humid: Double = cl.1
		let tundra: Double = smooth(clampD((0.31 - temp) / 0.06, 0, 1))
		let hot: Double = smooth(clampD((temp - 0.64) / 0.06, 0, 1))
		let desert: Double = hot * smooth(clampD((0.42 - humid) / 0.06, 0, 1))
		let jungle: Double = hot * smooth(clampD((humid - 0.58) / 0.06, 0, 1))
		let savanna: Double = hot * (1.0 - desert) * (1.0 - jungle)
		var swamp: Double = smooth(clampD((humid - 0.68) / 0.06, 0, 1)) * (1.0 - tundra) * (1.0 - hot)
		if lw > 0 { swamp *= (1.0 - lw) }
		var biome: Biome = humid > 0.5 ? .forest : .plains
		if tundra > 0.5 { biome = .tundra }
		else if desert > 0.5 { biome = .desert }
		else if jungle > 0.5 { biome = .jungle }
		else if savanna > 0.5 { biome = .savanna }
		else if swamp > 0.5 { biome = .swamp }
		if mtn > 0.35 { biome = .mountain }
		if land < 0.40 { biome = .ocean }
		if let f = forced { biome = f }
		let amp: Double = max(0.12, 1.0 - 0.4 * tundra - 0.3 * desert - 0.5 * savanna - 0.88 * swamp + 0.15 * jungle)
		var h: Double
		if land >= 0.40 {
			let t: Double = clampD((land - 0.40) / 0.25, 0, 1)
			h = Double(sea) - 2.0 - t * 12.0
			let hills: Double = (fbm1(fx / 55.0, seed &+ 2, 3) - 0.5) * 2.0 * 15.0 * amp
			let bumps: Double = (noise1(fx / 9.0, seed &+ 8) - 0.5) * 3.0 * amp
			h -= hills + bumps
			let v: Double = fbm1(fx / 140.0, seed &+ 5, 2)
			if v < 0.36 { h += (0.36 - v) / 0.36 * 16.0 * min(1.0, amp) }
			let cliff: Double = noise1(fx / 95.0, seed &+ 6)
			if cliff > 0.72 { h -= 10.0 * smooth(clampD((cliff - 0.72) / 0.015, 0, 1)) }
			let peak: Double = fbm1(fx / 70.0, seed &+ 4, 4)
			h -= mtn * (14.0 + peak * 70.0)
			if swamp > 0 {
				let target: Double = Double(sea) + (noise1(fx / 14.0, seed &+ 9) - 0.55) * 5.0
				h = lerpD(h, target, swamp)
			}
		} else {
			let d: Double = clampD((0.40 - land) / 0.14, 0, 1)
			h = Double(sea) - 2.0 + d * 48.0 + (noise1(fx / 7.0, seed &+ 10) - 0.5) * 3.0 * d
		}
		if lw > 0 { h = lerpD(h, Double(sea - 10), lw) }
		let hi: Int = clampI(Int(h.rounded()), 14, H - 80)
		return Col(h: hi, biome: biome, land: land, mtn: mtn, swamp: swamp)
	}

	/// Flat worlds: every column has the same height; the biome comes from the climate alone (the
	/// same temperature and humidity thresholds as colBaseStatic, without seas or mountains), and the
	/// ground around a boss lair keeps its forest or jungle
	static func flatColStatic(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ spawnX: Int, _ zones: [Int], _ x: Int, lairs: Bool) -> Col {
		let cl: (Double, Double) = WorldGen.climate(seed, infinite, width, zones, x)
		let temp: Double = cl.0
		let humid: Double = cl.1
		let tundra: Double = smooth(clampD((0.31 - temp) / 0.06, 0, 1))
		let hot: Double = smooth(clampD((temp - 0.64) / 0.06, 0, 1))
		let desert: Double = hot * smooth(clampD((0.42 - humid) / 0.06, 0, 1))
		let jungle: Double = hot * smooth(clampD((humid - 0.58) / 0.06, 0, 1))
		let savanna: Double = hot * (1.0 - desert) * (1.0 - jungle)
		let swamp: Double = smooth(clampD((humid - 0.68) / 0.06, 0, 1)) * (1.0 - tundra) * (1.0 - hot)
		var biome: Biome = humid > 0.5 ? .forest : .plains
		if tundra > 0.5 { biome = .tundra }
		else if desert > 0.5 { biome = .desert }
		else if jungle > 0.5 { biome = .jungle }
		else if savanna > 0.5 { biome = .savanna }
		else if swamp > 0.5 { biome = .swamp }
		if lairs, let L = WorldGen.lairStatic(spawnX, infinite, x, 150), abs(x - L.cx) < 120 { biome = L.kind == .bear ? .forest : .jungle }
		return Col(h: WorldGen.flatSurface, biome: biome, land: 0.7, mtn: 0, swamp: 0)
	}

	func colBase(_ x: Int) -> Col {
		if let c = cache.cols[x] {
			cache.hits &+= 1
			return c
		}
		cache.misses &+= 1
		let c: Col = options.flat ? WorldGen.flatColStatic(seed, infinite, width, spawnX, zones, x, lairs: hasStructures) : WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2, smallSeas: genVersion >= 6)
		cache.cols[x] = c
		return c
	}

	// MARK: village sites

	func villageSite(cell c: Int) -> VillageSite? {
		if let v = cache.villages[c] { return v }
		let v: VillageSite? = computeVillageSite(cell: c)
		cache.villages[c] = v
		return v
	}

	func computeVillageSite(cell c: Int) -> VillageSite? {
		if !hasVillages { return nil }
		let cellW: Int = WorldGen.villageCell
		let spawnCell: Bool = floorDiv(spawnX, cellW) == c
		if !spawnCell && hash2(c, 99, seed) > 0.62 { return nil }
		var sx: Int = c * cellW + 120 + Int(hash2(c, 98, seed) * Double(cellW - 240))
		if spawnCell {
			let side: Int = hash2(c, 96, seed) < 0.5 ? -1 : 1
			sx = spawnX + side * (150 + Int(hash2(c, 98, seed) * 60.0))
		}
		let halfW: Int = 28 + Int(hash2(c, 97, seed) * 12.0)
		let base: Col = colBase(sx)
		let ok: [Biome] = [.plains, .forest, .savanna, .desert, .tundra, .jungle]
		if !ok.contains(base.biome) || base.land < 0.5 { return nil }
		if lairAt(sx, radius: 330) != nil && !spawnCell { return nil }
		// footprint must be on land
		var dx: Int = -halfW
		while dx <= halfW {
			let cc: Col = colBase(sx + dx)
			if cc.biome == .ocean || cc.biome == .mountain || cc.biome == .swamp { return nil }
			if abs(cc.h - base.h) > 45 { return nil }
			dx += 6
		}
		if !infinite && (sx - halfW < 300 || sx + halfW > width - 300) { return nil }
		return VillageSite(cell: c, x: sx, halfW: halfW, seed: hashU(c, 55, seed), ground: base.h, biome: base.biome)
	}

	func villages(overlapping x0: Int, _ x1: Int) -> [VillageSite] {
		var out: [VillageSite] = []
		let cellW: Int = WorldGen.villageCell
		let c0: Int = floorDiv(x0 - 80, cellW) - 1
		let c1: Int = floorDiv(x1 + 80, cellW) + 1
		for c in c0...c1 {
			if let v = villageSite(cell: c) {
				if v.x + v.halfW + 8 >= x0 && v.x - v.halfW - 8 <= x1 { out.append(v) }
			}
		}
		return out
	}

	func nearestVillage(to x: Int) -> VillageSite? {
		let vs: [VillageSite] = villages(overlapping: x - 700, x + 700)
		var best: VillageSite? = nil
		var bd: Int = Int.max
		for v in vs {
			let d: Int = abs(v.x - x)
			if d < bd { bd = d; best = v }
		}
		return best
	}

	// MARK: rare sites

	func rareSite(cell c: Int) -> RareSite? {
		if let r = cache.rares[c] { return r }
		let r: RareSite? = computeRareSite(cell: c)
		cache.rares[c] = r
		return r
	}

	func computeRareSite(cell c: Int) -> RareSite? {
		if !hasStructures { return nil }
		if hash2(c, 71, seed) > rareChance { return nil }
		let cellW: Int = WorldGen.rareCell
		let sx: Int = c * cellW + 32 + Int(hash2(c, 72, seed) * Double(cellW - 64))
		let base: Col = colBase(sx)
		if base.biome == .ocean || base.land < 0.45 { return nil }
		if lairAt(sx, radius: 260) != nil { return nil }
		if abs(sx - portalX) < 90 { return nil }
		if !infinite && (sx < 300 || sx > width - 300) { return nil }
		if nearestVillageSimple(sx) { return nil }
		// flat worlds keep the spawn point clear (in other worlds the terrain search does that)
		if options.flat && abs(sx - spawnX) < 48 { return nil }
		let r: Double = hash2(c, 73, seed)
		var kind: RareKind = .house
		if r < 0.17 { kind = .house }
		else if r < 0.34 { kind = .tower }
		else if r < 0.51 { kind = .fort }
		else if r < 0.68 { kind = .camp }
		else if r < 0.84 { kind = .overgrown }
		else { kind = .bunker }
		return RareSite(cell: c, x: sx, kind: kind, seed: hashU(c, 74, seed))
	}

	func nearestVillageSimple(_ x: Int) -> Bool {
		let cellW: Int = WorldGen.villageCell
		let c0: Int = floorDiv(x, cellW)
		for c in (c0 - 1)...(c0 + 1) {
			if let v = villageSite(cell: c) {
				if abs(v.x - x) < v.halfW + 90 { return true }
			}
		}
		return false
	}

	func rareSites(overlapping x0: Int, _ x1: Int) -> [RareSite] {
		var out: [RareSite] = []
		let cellW: Int = WorldGen.rareCell
		let c0: Int = floorDiv(x0 - 40, cellW)
		let c1: Int = floorDiv(x1 + 40, cellW)
		for c in c0...c1 {
			if let s = rareSite(cell: c) {
				if s.x + 30 >= x0 && s.x - 30 <= x1 { out.append(s) }
			}
		}
		return out
	}

	// MARK: ponds (flat worlds)

	static let pondCell: Int = 260

	func pondSite(cell c: Int) -> PondSite? {
		if let p = cache.ponds[c] { return p }
		let p: PondSite? = computePondSite(cell: c)
		cache.ponds[c] = p
		return p
	}

	func computePondSite(cell c: Int) -> PondSite? {
		if !options.flat || !options.ponds { return nil }
		if hash2(c, 501, seed) > 0.5 { return nil }
		let cw: Int = WorldGen.pondCell
		let cx: Int = c * cw + 50 + Int(hash2(c, 502, seed) * Double(cw - 100))
		let hw: Int = 4 + Int(hash2(c, 503, seed) * 6.0)
		let depth: Int = hash2(c, 504, seed) < 0.4 ? 3 : 2
		if !infinite && (cx - hw < 40 || cx + hw > width - 40) { return nil }
		// never where something else is built, or at the spawn point
		if abs(cx - spawnX) < hw + 24 { return nil }
		if abs(cx - portalX) < hw + 16 { return nil }
		if lairAt(cx, radius: hw + 60) != nil { return nil }
		for v in villages(overlapping: cx - hw - 20, cx + hw + 20) where abs(v.x - cx) < v.halfW + hw + 20 { return nil }
		for r in rareSites(overlapping: cx - hw - 40, cx + hw + 40) where abs(r.x - cx) < hw + 40 { return nil }
		return PondSite(cx: cx, halfW: hw, depth: depth)
	}

	/// Water depth of a flat world's pond at x (0 = dry ground); the bowl is deepest in the middle
	func pondDepth(_ x: Int) -> Int {
		if !options.flat || !options.ponds { return 0 }
		let c: Int = floorDiv(x, WorldGen.pondCell)
		for cc in (c - 1)...(c + 1) {
			guard let p = pondSite(cell: cc) else { continue }
			let dx: Int = abs(x - p.cx)
			if dx > p.halfW { continue }
			let f: Double = Double(dx) / (Double(p.halfW) + 0.5)
			let d: Int = Int((Double(p.depth) * sqrt(max(0, 1.0 - f * f))).rounded(.up))
			return clampI(d, 1, p.depth)
		}
		return 0
	}

	/// True within `pad` columns of a pond (its sandy banks, and where trees keep back)
	func nearPond(_ x: Int, _ pad: Int) -> Bool {
		if !options.flat || !options.ponds { return false }
		let c: Int = floorDiv(x, WorldGen.pondCell)
		for cc in (c - 1)...(c + 1) {
			if let p = pondSite(cell: cc), abs(x - p.cx) <= p.halfW + pad { return true }
		}
		return false
	}

	/// Full column info including village flattening
	func col(_ x: Int) -> Col {
		var c: Col = colBase(x)
		let cellW: Int = WorldGen.villageCell
		let c0: Int = floorDiv(x, cellW)
		for cc in (c0 - 1)...(c0 + 1) {
			if let v = villageSite(cell: cc) {
				let d: Int = abs(x - v.x)
				if d <= v.halfW + 10 {
					let t: Double = clampD(Double(d - v.halfW) / 10.0, 0, 1)
					c.h = Int(lerpD(Double(v.ground), Double(c.h), t).rounded())
					if d <= v.halfW + 4 && c.biome != .ocean { c.biome = v.biome }
				}
			}
		}
		return c
	}
}

// ===== p07_chunk =====

// MARK: - Chunks

let chunkW: Int = 16

final class Chunk {
	/// a number no other chunk made in this run has (the renderer only reuses a picture of the land
	/// for the very chunk it was drawn from)
	let serial: Int = Chunk.nextSerial()
	static var serialCount: Int = 0
	static func nextSerial() -> Int {
		serialCount += 1
		return serialCount
	}
	let cx: Int
	let H: Int
	var tiles: [UInt8]
	var skyTop: [Int]
	var dirty: Bool = false
	var hasSky: Bool = true
	var rev: Int = 0
	var surf: [Int] = [Int](repeating: 0, count: chunkW)
	var ceilY: [Int] = [Int](repeating: 0, count: chunkW)
	var back: [UInt8] = []
	var walls: [UInt8] = []
	/// which blocks were put there rather than generated (see World.isBuilt); empty until the first
	var built: [UInt8] = []
	/// how many stair tiles the chunk holds (-1: not counted yet; see World.stairsNear)
	var stairs: Int = -1
	/// Sparkworks wiring over each cell (see Wire), and how many cells have any
	var wires: [UInt8] = []
	var wireCount: Int = 0
	var backRev: Int = -1
	/// change counter per 16-row section (the renderer only rebuilds sections that changed)
	var secRev: [Int]
	/// weather facts re-read when the chunk changes (see World.weatherScan): per column the row rain
	/// stops at, and the weather devices standing in it
	var wxRev: Int = -1
	var wxTop: [Int] = []
	var wxDev: [DeviceSpot] = []

	init(cx: Int, H: Int) {
		self.cx = cx
		self.H = H
		self.tiles = [UInt8](repeating: 0, count: chunkW * H)
		self.skyTop = [Int](repeating: 0, count: chunkW)
		self.secRev = [Int](repeating: 0, count: H / 16 + 1)
	}

	/// Marks every section touching rows y0...y1 as changed
	func bumpRows(_ y0: Int, _ y1: Int) {
		let n: Int = secRev.count
		var s: Int = max(0, y0) / 16
		let e: Int = min(n - 1, max(0, y1) / 16)
		while s <= e {
			secRev[s] &+= 1
			s += 1
		}
	}

	var x0: Int { return cx * chunkW }

	@inline(__always) func get(_ lx: Int, _ y: Int) -> Tile {
		if y < 0 { return .air }
		if y >= H { return .bedrock }
		return Tile.make(tiles[lx * H + y])
	}

	@inline(__always) func raw(_ lx: Int, _ y: Int) -> UInt8 {
		return tiles[lx * H + y]
	}

	func setLocal(_ lx: Int, _ y: Int, _ t: Tile) {
		if lx < 0 || lx >= chunkW || y < 0 || y >= H { return }
		tiles[lx * H + y] = t.rawValue
	}

	/// Global-x write used by structure builders; ignores anything outside this chunk
	func put(_ x: Int, _ y: Int, _ t: Tile) {
		let lx: Int = x - x0
		if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
		tiles[lx * H + y] = t.rawValue
	}

	func putIfAir(_ x: Int, _ y: Int, _ t: Tile) {
		let lx: Int = x - x0
		if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
		if tiles[lx * H + y] == Tile.air.rawValue { tiles[lx * H + y] = t.rawValue }
	}

	func at(_ x: Int, _ y: Int) -> Tile {
		let lx: Int = x - x0
		if lx < 0 || lx >= chunkW || y < 0 || y >= H { return .air }
		return Tile.make(tiles[lx * H + y])
	}

	func fill(_ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ t: Tile) {
		if xb < xa || yb < ya { return }
		for x in xa...xb {
			if x < x0 || x >= x0 + chunkW { continue }
			for y in ya...yb { put(x, y, t) }
		}
	}

	/// Global-x background wall write used by structure builders
	func putWall(_ x: Int, _ y: Int, _ k: UInt8) {
		let lx: Int = x - x0
		if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
		if walls.isEmpty { walls = [UInt8](repeating: 0, count: chunkW * H) }
		walls[lx * H + y] = k
	}

	func fillWall(_ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ k: UInt8) {
		if xb < xa || yb < ya { return }
		for x in xa...xb { for y in ya...yb { putWall(x, y, k) } }
	}

	func rebuildSky() {
		for lx in 0..<chunkW { recomputeSky(lx) }
	}

	func recomputeSky(_ lx: Int) {
		if !hasSky { skyTop[lx] = H; return }
		var y: Int = 0
		while y < H {
			if Tile.opaqueTable[Int(tiles[lx * H + y])] { break }
			y += 1
		}
		skyTop[lx] = y
	}
}

// MARK: - Cave, ore and tree rules

struct OreRule {
	var tile: Tile
	var minY: Int
	var maxY: Int
	var thr: Double
	var p: Double
	var salt: UInt64
	/// above 0: the ore only forms where a broad regional field passes this value, so it is common in
	/// some stretches of land and absent from others
	var region: Double = 0
}

/// Ores by depth (rows count down from the sky; the sea is at 120). Each rule is a field of blobs: rock
/// where the field passes `thr` turns to ore with chance `p`. The first rule that matches wins, so
/// the rare ones come first. Shallow ground has coal, copper, saltpeter and (in some regions) tin;
/// iron and silver start in the middle depths; gold, diamond and mythril are kept for the deep.
let oreRules: [OreRule] = [
	OreRule(tile: .amethyst, minY: 150, maxY: 330, thr: 0.967, p: 0.9, salt: 41),
	OreRule(tile: .saltpeter, minY: 112, maxY: 205, thr: 0.865, p: 0.55, salt: 42),
	OreRule(tile: .tin, minY: 122, maxY: 265, thr: 0.845, p: 0.62, salt: 43, region: 0.47),
	OreRule(tile: .coal, minY: 120, maxY: 340, thr: 0.81, p: 0.66, salt: 31),
	OreRule(tile: .copper, minY: 125, maxY: 345, thr: 0.84, p: 0.65, salt: 32),
	OreRule(tile: .silver, minY: 200, maxY: 400, thr: 0.913, p: 0.6, salt: 44),
	OreRule(tile: .iron, minY: 205, maxY: 450, thr: 0.86, p: 0.56, salt: 33),
	OreRule(tile: .gold, minY: 310, maxY: 530, thr: 0.885, p: 0.58, salt: 34),
	OreRule(tile: .diamond, minY: 390, maxY: 548, thr: 0.925, p: 0.55, salt: 35),
	OreRule(tile: .mythril, minY: 455, maxY: 548, thr: 0.945, p: 0.55, salt: 36)
]

/// Generator 6: iron from row 150 (some 35 blocks under the ground instead of 90), and a little more
/// coal, copper and tin; everything deeper as before
let oreRules6: [OreRule] = [
	OreRule(tile: .amethyst, minY: 150, maxY: 330, thr: 0.967, p: 0.9, salt: 41),
	OreRule(tile: .saltpeter, minY: 112, maxY: 205, thr: 0.865, p: 0.55, salt: 42),
	OreRule(tile: .tin, minY: 122, maxY: 265, thr: 0.832, p: 0.62, salt: 43, region: 0.47),
	OreRule(tile: .coal, minY: 120, maxY: 340, thr: 0.79, p: 0.66, salt: 31),
	OreRule(tile: .copper, minY: 125, maxY: 345, thr: 0.82, p: 0.65, salt: 32),
	OreRule(tile: .silver, minY: 200, maxY: 400, thr: 0.913, p: 0.6, salt: 44),
	OreRule(tile: .iron, minY: 150, maxY: 450, thr: 0.86, p: 0.56, salt: 33),
	OreRule(tile: .gold, minY: 310, maxY: 530, thr: 0.885, p: 0.58, salt: 34),
	OreRule(tile: .diamond, minY: 390, maxY: 548, thr: 0.925, p: 0.55, salt: 35),
	OreRule(tile: .mythril, minY: 455, maxY: 548, thr: 0.945, p: 0.55, salt: 36)
]

func oreBias(_ b: Biome, _ t: Tile) -> Double {
	switch (b, t) {
	case (.desert, .gold): return 0.045
	case (.mountain, .iron): return 0.035
	case (.mountain, .mythril): return 0.03
	case (.tundra, .diamond): return 0.03
	case (.jungle, .copper): return 0.04
	case (.savanna, .gold): return 0.03
	case (.swamp, .coal): return 0.05
	// saltpeter crusts form in dry ground and hardly at all in wet
	case (.desert, .saltpeter): return 0.05
	case (.savanna, .saltpeter): return 0.04
	case (.mountain, .saltpeter): return 0.02
	case (.swamp, .saltpeter), (.jungle, .saltpeter), (.ocean, .saltpeter): return -0.2
	case (.mountain, .tin), (.tundra, .tin): return 0.03
	case (.mountain, .silver), (.tundra, .silver): return 0.02
	default: return 0
	}
}

/// the broad field that decides where regional ores (tin) form
func oreRegion(_ x: Int, _ salt: UInt64, _ seed: UInt64) -> Double {
	return vnoise(Double(x) * 0.006, 0.37, seed &+ salt &+ 900)
}

extension WorldGen {
	func isCave(_ x: Int, _ y: Int, _ depth: Int) -> Bool {
		if depth < 5 { return false }
		let fx: Double = Double(x)
		let fy: Double = Double(y)
		// winding tunnels follow the 0.5 contour of a smooth noise field
		let region: Double = vnoise(fx * 0.013, fy * 0.013, seed &+ 25)
		if region > 0.34 {
			let a: Double = vnoise(fx * 0.045, fy * 0.06, seed &+ 21)
			let w: Double = 0.030 + 0.05 * vnoise(fx * 0.02, fy * 0.02, seed &+ 22)
			if abs(a - 0.5) < w { return true }
		}
		// big chambers
		if depth > 26 {
			let c: Double = vnoise(fx * 0.03, fy * 0.045, seed &+ 23) * 0.65 + vnoise(fx * 0.085, fy * 0.1, seed &+ 24) * 0.35
			let bonus: Double = min(0.05, Double(max(0, y - 150)) * 0.00015)
			if c > 0.715 - bonus { return true }
		}
		// surface shafts: a few cave mouths
		if depth < 40 {
			let n: Double = noise1(fx / 18.0, seed &+ 26)
			if n > 0.90 && vnoise(fx * 0.2, fy * 0.2, seed &+ 27) > 0.35 { return true }
		}
		return false
	}

	/// The ore table this world generates with
	var oreTable: [OreRule] { return genVersion >= 6 ? oreRules6 : oreRules }

	func oreAt(_ x: Int, _ y: Int, _ biome: Biome) -> Tile? {
		let fx: Double = Double(x)
		let fy: Double = Double(y)
		for r in oreTable {
			if y < r.minY || y > r.maxY { continue }
			if r.region > 0 && oreRegion(x, r.salt, seed) < r.region { continue }
			let blob: Double = vnoise(fx * 0.22, fy * 0.22, seed &+ r.salt)
			if blob + oreBias(biome, r.tile) > r.thr {
				if hash2(x, y, seed &+ 40 &+ r.salt) < r.p { return r.tile }
			}
		}
		return nil
	}

	func rockAt(_ x: Int, _ y: Int) -> Tile {
		let hy: Double = hash2(x, y / 3, seed &+ 5)
		let hoff: Double = (hy - 0.5) * 12.0
		let by: Int = y + Int(hoff)
		if by < 300 { return .stone }
		if by < 430 { return .slate }
		return .deepRock
	}

	/// The chance a column starts a tree (four columns are always kept between trees)
	func treeDensity(_ b: Biome, _ h: Int, _ x: Int = Int.min) -> Double {
		if genVersion >= 6 { return treeDensity6(b, h, x) }
		switch b {
		case .forest: return 0.14
		case .plains: return 0.04
		case .jungle: return 0.22
		case .savanna: return 0.04
		case .tundra: return 0.08
		case .swamp: return 0.10
		case .mountain: return h > 98 ? 0.05 : 0.0
		case .desert: return 0.035
		default: return 0.0
		}
	}

	/// Generator 6: about half as many trees again, and a grove around the spawn, so the first wood is
	/// never far away (forests stay walkable: trees still stand at least four columns apart)
	func treeDensity6(_ b: Biome, _ h: Int, _ x: Int) -> Double {
		var d: Double = 0
		switch b {
		case .forest: d = 0.22
		case .plains: d = 0.10
		case .jungle: d = 0.24
		case .savanna: d = 0.065
		case .tundra: d = 0.12
		case .swamp: d = 0.13
		case .mountain: d = h > 98 ? 0.08 : 0.0
		case .desert: return 0.035
		default: return 0.0
		}
		if x != Int.min && abs(x - spawnX) < 110 && b != .mountain { d = max(d, 0.22) }
		return d
	}
}

// MARK: - Overworld chunk generation

func generateOverworldChunk(_ g: WorldGen, _ cx: Int) -> Chunk {
	let H: Int = WorldGen.H
	let sea: Int = WorldGen.sea
	let ch = Chunk(cx: cx, H: H)
	let x0: Int = cx * chunkW
	let m: Int = 12
	var cols: [Col] = []
	for x in (x0 - m)..<(x0 + chunkW + m) { cols.append(g.col(x)) }
	func colAt(_ x: Int) -> Col { return cols[x - (x0 - m)] }
	var surfBiome: [Biome] = []
	var samp: GenSampler = GenSampler(g)
	defer { samp.free() }
	for lx in 0..<chunkW {
		let x: Int = x0 + lx
		let c: Col = colAt(x)
		samp.startColumn(x, c.h, caves: !g.options.flat || g.options.caves)
		let hj: Double = hash2(x, 1, g.seed &+ 61)
		let jd: Double = (hj - 0.5) * 10.0
		let jit: Int = Int(jd)
		var sb: Biome = colAt(x + jit).biome
		if c.biome == .ocean { sb = .ocean }
		else if sb == .ocean { sb = c.biome }
		surfBiome.append(sb)
		let base: Int = lx * H
		if !g.infinite && (x < 0 || x >= g.width) {
			for y in 0..<H { ch.tiles[base + y] = Tile.bedrock.rawValue }
			continue
		}
		let h: Int = c.h
		ch.surf[lx] = h
		if g.options.flat {
			fillFlatColumn(ch, g, &samp, lx, x, h, sb, c.biome)
		} else {
			fillStandardColumn(ch, g, &samp, lx, x, h, sb, c.biome)
		}
		// underground decoration on cave floors / ceilings
		var y: Int = h + 8
		while y < H - 6 {
			if ch.tiles[base + y] == Tile.air.rawValue {
				let below: Tile = Tile.make(ch.tiles[base + y + 1])
				let above: Tile = Tile.make(ch.tiles[base + y - 1])
				if below.solid && below != .bedrock && y > 190 && y < 470 && hash2(x, y, g.seed &+ 81) < 0.025 {
					ch.tiles[base + y] = Tile.mushroom.rawValue
				} else if above.solid && hash2(x, y, g.seed &+ 82) < 0.012 {
					ch.tiles[base + y] = Tile.cobweb.rawValue
				}
			}
			y += 1
		}
	}
	// surface plants & trees
	let villages: [VillageSite] = g.villages(overlapping: x0 - 20, x0 + chunkW + 20)
	let rares: [RareSite] = g.rareSites(overlapping: x0 - 30, x0 + chunkW + 30)
	// mine headframes and grotto cave mouths keep their ground clear as well
	let mines: [MineSite] = g.mineSites(overlapping: x0 - 20, x0 + chunkW + 20)
	var mouths: [Int] = []
	for s in g.grottoSites(overlapping: x0 - 30, x0 + chunkW + 30) where s.open { mouths.append(s.passStartX + s.dir * s.passLen) }
	func blocked(_ x: Int) -> Bool {
		for v in villages { if abs(x - v.x) < v.halfW + 6 { return true } }
		for r in rares { if abs(x - r.x) < 16 { return true } }
		for mn in mines { if x >= mn.x - 6 && x <= mn.x + (mn.plan == nil ? 8 : 11) { return true } }
		for mx in mouths { if abs(x - mx) < 16 { return true } }
		if let l = g.lairAt(x, radius: 110) { _ = l; return true }
		// flat worlds keep the spawn point clear of trees, and trees out of ponds
		if g.options.flat && (abs(x - g.spawnX) < 5 || g.nearPond(x, 2)) { return true }
		return false
	}
	func isTree(_ x: Int) -> Bool {
		let c: Col = colAt(x)
		let d: Double = g.treeDensity(c.biome, c.h, x)
		if d <= 0 { return false }
		if hash2(x, 3, g.seed &+ 99) >= d { return false }
		if c.h > sea - 1 && c.biome != .swamp { return false }
		return true
	}
	for lx in -6..<(chunkW + 6) where g.hasTrees {
		let x: Int = x0 + lx
		if !g.infinite && (x < 4 || x > g.width - 5) { continue }
		let c: Col = colAt(x)
		if c.biome == .ocean || blocked(x) { continue }
		let sbIdx: Int = lx >= 0 && lx < chunkW ? lx : -1
		let sb: Biome = sbIdx >= 0 ? surfBiome[sbIdx] : c.biome
		// plants (only for columns inside this chunk)
		if sbIdx >= 0 {
			let r: Double = hash2(x, 5, g.seed &+ 90)
			let gy: Int = c.h - 1
			let surf: Tile = ch.get(lx, c.h)
			if gy > 0 && ch.get(lx, gy) == .air && c.h <= sea {
				switch (sb, surf) {
				case (.plains, .grass), (.forest, .grass):
					if r < 0.20 { ch.setLocal(lx, gy, .tallGrass) } else if r < 0.235 { ch.setLocal(lx, gy, .flowerR) } else if r < 0.27 { ch.setLocal(lx, gy, .flowerY) }
				case (.jungle, .jungleGrass):
					if r < 0.30 { ch.setLocal(lx, gy, .tallGrass) } else if r < 0.34 { ch.setLocal(lx, gy, .flowerR) }
				case (.savanna, .dryGrass):
					if r < 0.14 { ch.setLocal(lx, gy, .tallGrass) }
				case (.swamp, .mossGrass):
					if r < 0.14 { ch.setLocal(lx, gy, .reed) } else if r < 0.17 { ch.setLocal(lx, gy, .mushroom) }
				case (.desert, .sand):
					if r < 0.03 { ch.setLocal(lx, gy, .deadBush) }
				default: break
				}
			}
		}
		// trees: origin at x, drawn clipped into this chunk; four columns apart (from generator 6
		// three, except the broad jungle trees)
		if !isTree(x) { continue }
		if isTree(x - 1) || isTree(x - 2) { continue }
		if (g.genVersion < 6 || c.biome == .jungle) && isTree(x - 3) { continue }
		if abs(colAt(x - 1).h - colAt(x + 1).h) > 1 { continue }
		let tr: Double = hash2(x, 4, g.seed &+ 98)
		let gy: Int = c.h
		let tb: Biome = c.biome
		if tb == .desert {
			let th: Int = 2 + Int(tr * 4.0)
			for k in 1...th { ch.put(x, gy - k, .cactus) }
			if th >= 4 { ch.put(x - 1, gy - 3, .cactus); ch.put(x + 1, gy - 2, .cactus) }
		} else if tb == .jungle {
			let th: Int = 9 + Int(tr * 9.0)
			for k in 1...th { ch.put(x, gy - k, .jungleLog) }
			for dy in -3...1 { for dx in -4...4 {
				if abs(dx) == 4 && abs(dy + 1) > 1 { continue }
				if abs(dx) + abs(dy + 1) > 6 { continue }
				ch.putIfAir(x + dx, gy - th + dy, .jungleLeaves)
			} }
		} else if tb == .savanna {
			let th: Int = 5 + Int(tr * 3.0)
			for k in 1...th { ch.put(x, gy - k, .log) }
			for dx in -4...4 { ch.putIfAir(x + dx, gy - th, .leaves) }
			for dx in -2...2 { ch.putIfAir(x + dx, gy - th - 1, .leaves) }
		} else if tb == .tundra || (tb == .mountain && c.h > 98) {
			let needles: Tile = g.genVersion >= 3 ? .pineLeaves : .leaves
			let th: Int = 6 + Int(tr * 5.0)
			for k in 1...th { ch.put(x, gy - k, .log) }
			var layer: Int = 0
			while layer < th - 1 {
				let wdt: Int = min(3, 1 + layer / 2)
				for dx in -wdt...wdt { ch.putIfAir(x + dx, gy - th - 1 + layer, needles) }
				layer += 1
			}
			ch.putIfAir(x, gy - th - 2, needles)
		} else if tb == .swamp {
			let th: Int = 4 + Int(tr * 2.0)
			for k in 1...th { ch.put(x, gy - k, .log) }
			for dx in -3...3 { ch.putIfAir(x + dx, gy - th, .jungleLeaves); if abs(dx) < 3 { ch.putIfAir(x + dx, gy - th - 1, .jungleLeaves) } }
		} else {
			// newer worlds mix birches into forests and plains, and tall pines into forests
			let variety: Double = g.genVersion >= 3 ? hash2(x, 8, g.seed &+ 96) : 1.0
			if variety < 0.3 && (tb == .forest || tb == .plains) {
				// birch: a slim white trunk under a narrow, airy crown
				let th: Int = 6 + Int(tr * 4.0)
				for k in 1...th { ch.put(x, gy - k, .birchLog) }
				for dy in -4...0 {
					let w: Int = (dy == -4 || dy == 0) ? 1 : 2
					for dx in -w...w {
						if abs(dx) == 2 && hash2(x + dx, gy + dy, g.seed &+ 95) < 0.3 { continue }
						ch.putIfAir(x + dx, gy - th + dy, .birchLeaves)
					}
				}
				ch.putIfAir(x, gy - th - 5, .birchLeaves)
			} else if variety < 0.44 && tb == .forest {
				// pine: tall, with a stepped cone of dark needles
				let th: Int = 10 + Int(tr * 5.0)
				for k in 1...th { ch.put(x, gy - k, .log) }
				var layer: Int = 0
				while layer < th - 4 {
					var wdt: Int = min(3, 1 + layer / 3)
					if layer % 3 == 0 && layer > 0 { wdt -= 1 }
					for dx in -wdt...wdt { ch.putIfAir(x + dx, gy - th - 1 + layer, .pineLeaves) }
					layer += 1
				}
				ch.putIfAir(x, gy - th - 2, .pineLeaves)
			} else {
				let th: Int = 4 + Int(tr * 4.0)
				for k in 1...th { ch.put(x, gy - k, .log) }
				for dy in -3...1 { for dx in -2...2 {
					if abs(dx) == 2 && (dy == -3 || dy == 1) { continue }
					ch.putIfAir(x + dx, gy - th + dy, .leaves)
				} }
			}
		}
	}
	// palms on warm beaches
	for lx in 0..<chunkW where g.hasTrees {
		let x: Int = x0 + lx
		let c: Col = colAt(x)
		if c.biome == .ocean || c.h < sea - 3 || c.h > sea + 1 { continue }
		if ch.get(lx, c.h) != .sand || ch.get(lx, c.h - 1) != .air { continue }
		if hash2(x, 6, g.seed &+ 97) > 0.035 { continue }
		let th: Int = 6 + Int(hash2(x, 7, g.seed &+ 97) * 4.0)
		for k in 1...th { ch.put(x + (k > th - 3 ? 1 : 0), c.h - k, .palmLog) }
		for dx in -3...4 { ch.putIfAir(x + 1 + dx, c.h - th - (abs(dx - 0) > 2 ? 0 : 1), .jungleLeaves) }
	}
	if g.hasLandmarks { placeLandmarks(g, ch, colAt, blocked) }
	applyStructures(g, ch, cols, x0 - m)
	if ModRuntime.shared.hasWorldGen { applyModGen(g, ch, .overworld) }
	ch.rebuildSky()
	return ch
}

/// One column of a standard world: the biome's surface and topsoil, sea water above low ground,
/// rock layers, caves (with underground lakes and deep lava) and ores
func fillStandardColumn(_ ch: Chunk, _ g: WorldGen, _ samp: inout GenSampler, _ lx: Int, _ x: Int, _ h: Int, _ sb: Biome, _ biome: Biome) {
	let H: Int = WorldGen.H
	let sea: Int = WorldGen.sea
	let base: Int = lx * H
	var topT: Tile = .grass
	var fillT: Tile = .dirt
	var fillD: Int = 5
	switch sb {
	case .plains, .forest: break
	case .desert: topT = .sand; fillT = .sand; fillD = 9
	case .tundra: topT = .snow; fillT = .snow; fillD = 3
	case .jungle: topT = .jungleGrass; fillT = .mud; fillD = 7
	case .savanna: topT = .dryGrass; fillD = 4
	case .swamp: topT = .mossGrass; fillT = .mud; fillD = 6
	case .ocean: topT = .sand; fillT = .sand; fillD = 5
	case .mountain:
		if h <= 72 { topT = .snow; fillT = .snow; fillD = 3 }
		else if h <= 100 { topT = .stone; fillT = .stone; fillD = 4 }
	case .umbral: break
	}
	if sb != .ocean && sb != .swamp && sb != .desert && h >= sea - 1 && h <= sea + 2 { topT = .sand; fillT = .sand; fillD = 4 }
	if h > sea {
		for y in sea..<h {
			ch.tiles[base + y] = ((sb == .tundra && y == sea) ? Tile.ice : Tile.water).rawValue
		}
	}
	ch.tiles.withUnsafeMutableBufferPointer { tb in
		guard let tp = tb.baseAddress else { return }
		var y: Int = h
		while y < H {
			let depth: Int = y - h
			var t: Tile
			if y >= H - 1 { t = .bedrock }
			else if y >= H - 5 && hash2(x, y, g.seed &+ 3) < Double(y - (H - 6)) * 0.22 { t = .bedrock }
			else if depth == 0 { t = topT }
			else if depth < fillD { t = (sb == .tundra && depth >= 3) ? .dirt : fillT }
			else if sb == .desert && depth < 24 { t = .sandstone }
			else { t = samp.rockAt(x, y) }
			if depth >= 4 && y < H - 5 {
				if samp.isCave(x, y, depth) {
					if y >= 500 { t = .lava }
					else if y > 200 && y < 430 && hash2(x / 60, y / 48, g.seed &+ 28) < 0.28 && (y % 48) > 28 { t = .water }
					else { t = .air }
				} else if depth > 8 && t != .sand && t != .snow {
					if let o = samp.oreAt(x, y, biome) { t = o }
				}
			}
			tp[base + y] = t.rawValue
			y += 1
		}
	}
}

/// One column of a flat world: the same layers everywhere. The surface block and four rows of
/// topsoil follow the biome; below them stone to row 300, slate to 430, deep rock, and a three-row
/// bedrock floor, with ores in the rock. With caves on, tunnels and chambers (and their lakes and deep
/// lava) open up only below an unbroken crust, so nothing underground ever reaches the surface.
/// Ponds sit in the ground with their water level with the surface, on a sandy bed with sandy banks.
func fillFlatColumn(_ ch: Chunk, _ g: WorldGen, _ samp: inout GenSampler, _ lx: Int, _ x: Int, _ h: Int, _ surfBiome: Biome, _ biome: Biome) {
	let H: Int = WorldGen.H
	var topT: Tile = .grass
	var fillT: Tile = .dirt
	switch surfBiome {
	case .desert: topT = .sand; fillT = .sand
	case .tundra: topT = .snow
	case .jungle: topT = .jungleGrass; fillT = .mud
	case .savanna: topT = .dryGrass
	case .swamp: topT = .mossGrass; fillT = .mud
	default: break
	}
	let pond: Int = g.pondDepth(x)
	if pond == 0 && g.nearPond(x, 1) { topT = .sand }
	let caves: Bool = g.options.caves
	let base: Int = lx * H
	var y: Int = h
	while y < H {
		let depth: Int = y - h
		var t: Tile
		if y >= H - 3 { t = .bedrock }
		else if depth < pond { t = (surfBiome == .tundra && depth == 0) ? .ice : .water }
		else if depth == pond && pond > 0 { t = .sand }
		else if depth == 0 { t = topT }
		else if depth <= 4 { t = fillT }
		else if y < 300 { t = .stone }
		else if y < 430 { t = .slate }
		else { t = .deepRock }
		if y < H - 5 && depth >= WorldGen.flatCrust && caves && samp.isCave(x, y, depth) {
			if y >= 500 { t = .lava }
			else if y > 200 && y < 430 && hash2(x / 60, y / 48, g.seed &+ 28) < 0.28 && (y % 48) > 28 { t = .water }
			else { t = .air }
		} else if depth > 8 && y < H - 5, let o = samp.oreAt(x, y, biome) {
			t = o
		}
		ch.tiles[base + y] = t.rawValue
		y += 1
	}
}

// MARK: - Column samplers for chunk generation

/// Fills out[y - y0] with vnoise(fx, Double(y) * fyScale, seed) for y in y0...y1. Gives bit-identical
/// values to vnoise(), but hashes each lattice row once instead of four hashes per sample, and makes
/// no function calls per sample (in debug builds each call costs more than the maths).
func columnNoise(_ seed: UInt64, _ fx: Double, _ fyScale: Double, _ y0: Int, _ y1: Int, _ out: inout [Double]) {
	if y1 < y0 { return }
	let n: Int = y1 - y0 + 1
	if out.count < n { out = [Double](repeating: 0, count: n) }
	let fx0: Double = floor(fx)
	let xi: Int = Int(fx0)
	let fu: Double = fx - fx0
	let u: Double = fu * fu * (3.0 - 2.0 * fu)
	var rowI: Int = Int.min
	var a: Double = 0, b: Double = 0, c: Double = 0, d: Double = 0
	var top: Double = 0
	var bot: Double = 0
	// fy0 tracks floor(fy) incrementally (samples only move forward), avoiding a libm call per sample
	var fy0: Double = floor(Double(y0) * fyScale)
	out.withUnsafeMutableBufferPointer { bp in
		guard let p = bp.baseAddress else { return }
		var y: Int = y0
		var k: Int = 0
		while k < n {
			let fy: Double = Double(y) * fyScale
			while fy >= fy0 + 1.0 { fy0 += 1.0 }
			let yi: Int = Int(fy0)
			if yi != rowI {
				if yi == rowI &+ 1 {
					a = c
					b = d
				} else {
					a = hash2(xi, yi, seed)
					b = hash2(xi + 1, yi, seed)
				}
				c = hash2(xi, yi + 1, seed)
				d = hash2(xi + 1, yi + 1, seed)
				top = a + (b - a) * u
				bot = c + (d - c) * u
				rowI = yi
			}
			let f: Double = fy - fy0
			let v: Double = f * f * (3.0 - 2.0 * f)
			p[k] = top + (bot - top) * v
			y += 1
			k += 1
		}
	}
}

/// Cave, ore and rock sampling for one column at a time. startColumn() precomputes every noise
/// field the column needs; isCave/oreAt/rockAt then only read buffers. Same results as the
/// per-tile WorldGen.isCave/oreAt/rockAt.
/// Written for debug builds: a struct used as a local `var` with mutating methods (no copies and
/// no runtime exclusivity checks), and raw buffers instead of arrays (no retain/release per read).
/// Call free() when done.
struct GenSampler {
	let seed: UInt64
	let H: Int
	var top: Int = 0
	var chamTop: Int = 0
	var shaftN: Double = 0
	var biasBiome: Int = -1
	var rockY3: Int = Int.min
	var rockH: Double = 0
	var scratch: [Double] = []
	let region: UnsafeMutablePointer<Double>
	let tunnel: UnsafeMutablePointer<Double>
	let width: UnsafeMutablePointer<Double>
	let cham: UnsafeMutablePointer<Double>
	let shaft: UnsafeMutablePointer<Double>
	let ores: UnsafeMutablePointer<Double>
	/// per ore rule: [lo, hi] rows, threshold+bias, chance, salt, tile
	let oreLo: UnsafeMutablePointer<Int>
	let oreHi: UnsafeMutablePointer<Int>
	let oreThr: UnsafeMutablePointer<Double>
	let oreP: UnsafeMutablePointer<Double>
	let oreSalt: UnsafeMutablePointer<UInt64>
	let oreTile: UnsafeMutablePointer<UInt8>
	let nOre: Int
	/// the ore table of the world being generated (see WorldGen.oreTable)
	let rules: [OreRule]

	init(_ g: WorldGen) {
		seed = g.seed
		H = WorldGen.H
		rules = g.oreTable
		nOre = rules.count
		region = UnsafeMutablePointer<Double>.allocate(capacity: H)
		tunnel = UnsafeMutablePointer<Double>.allocate(capacity: H)
		width = UnsafeMutablePointer<Double>.allocate(capacity: H)
		cham = UnsafeMutablePointer<Double>.allocate(capacity: H)
		shaft = UnsafeMutablePointer<Double>.allocate(capacity: H)
		ores = UnsafeMutablePointer<Double>.allocate(capacity: H * rules.count)
		oreLo = UnsafeMutablePointer<Int>.allocate(capacity: rules.count)
		oreHi = UnsafeMutablePointer<Int>.allocate(capacity: rules.count)
		oreThr = UnsafeMutablePointer<Double>.allocate(capacity: rules.count)
		oreP = UnsafeMutablePointer<Double>.allocate(capacity: rules.count)
		oreSalt = UnsafeMutablePointer<UInt64>.allocate(capacity: rules.count)
		oreTile = UnsafeMutablePointer<UInt8>.allocate(capacity: rules.count)
		for k in 0..<rules.count {
			oreP[k] = rules[k].p
			oreSalt[k] = rules[k].salt
			oreTile[k] = rules[k].tile.rawValue
			oreThr[k] = rules[k].thr
			oreLo[k] = 0
			oreHi[k] = -1
		}
	}

	func free() {
		region.deallocate(); tunnel.deallocate(); width.deallocate(); cham.deallocate(); shaft.deallocate()
		ores.deallocate(); oreLo.deallocate(); oreHi.deallocate(); oreThr.deallocate(); oreP.deallocate()
		oreSalt.deallocate(); oreTile.deallocate()
	}

	private mutating func fill(_ dst: UnsafeMutablePointer<Double>, _ s: UInt64, _ fx: Double, _ fyScale: Double, _ y0: Int, _ y1: Int) {
		if y1 < y0 { return }
		columnNoise(s, fx, fyScale, y0, y1, &scratch)
		let n: Int = y1 - y0 + 1
		scratch.withUnsafeBufferPointer { bp in
			guard let src = bp.baseAddress else { return }
			dst.update(from: src, count: n)
		}
	}

	/// Call once per column (h = surface row) before sampling it. Without caves only the ore fields
	/// are prepared (isCave must not be called then).
	mutating func startColumn(_ cx: Int, _ h: Int, caves: Bool = true) {
		rockY3 = Int.min
		let fx: Double = Double(cx)
		if caves { startCaves(cx, h) }
		var k: Int = 0
		while k < nOre {
			let lo: Int = max(rules[k].minY, h + 9)
			var hi: Int = min(rules[k].maxY, H - 6)
			// a regional ore is missing from this column altogether outside its region
			if rules[k].region > 0 && oreRegion(cx, oreSalt[k], seed) < rules[k].region { hi = lo - 1 }
			oreLo[k] = lo
			oreHi[k] = hi
			if hi >= lo { fill(ores + k * H, seed &+ oreSalt[k], fx * 0.22, 0.22, lo, hi) }
			k += 1
		}
	}

	private mutating func startCaves(_ cx: Int, _ h: Int) {
		let fx: Double = Double(cx)
		shaftN = noise1(fx / 18.0, seed &+ 26)
		top = h + 5
		chamTop = h + 27
		let y1: Int = H - 1
		fill(region, seed &+ 25, fx * 0.013, 0.013, top, y1)
		fill(tunnel, seed &+ 21, fx * 0.045, 0.06, top, y1)
		fill(width, seed &+ 22, fx * 0.02, 0.02, top, y1)
		// chambers: keep the combined value
		if chamTop <= y1 {
			let n: Int = y1 - chamTop + 1
			fill(cham, seed &+ 23, fx * 0.03, 0.045, chamTop, y1)
			columnNoise(seed &+ 24, fx * 0.085, 0.1, chamTop, y1, &scratch)
			let c: UnsafeMutablePointer<Double> = cham
			scratch.withUnsafeBufferPointer { bp in
				guard let src = bp.baseAddress else { return }
				var k: Int = 0
				while k < n { c[k] = c[k] * 0.65 + src[k] * 0.35; k += 1 }
			}
		}
		if shaftN > 0.90 { fill(shaft, seed &+ 27, fx * 0.2, 0.2, top, min(y1, h + 39)) }
	}

	mutating func isCave(_ x: Int, _ y: Int, _ depth: Int) -> Bool {
		if depth < 5 || y < top { return false }
		let i: Int = y - top
		if region[i] > 0.34 {
			let a: Double = tunnel[i]
			let w: Double = 0.030 + 0.05 * width[i]
			if abs(a - 0.5) < w { return true }
		}
		if depth > 26 && y >= chamTop {
			let bonus: Double = min(0.05, Double(max(0, y - 150)) * 0.00015)
			if cham[y - chamTop] > 0.715 - bonus { return true }
		}
		if depth < 40 && shaftN > 0.90 {
			if shaft[i] > 0.35 { return true }
		}
		return false
	}

	mutating func oreAt(_ x: Int, _ y: Int, _ biome: Biome) -> Tile? {
		if biome.rawValue != biasBiome {
			biasBiome = biome.rawValue
			var k: Int = 0
			while k < nOre {
				oreThr[k] = rules[k].thr - oreBias(biome, rules[k].tile)
				k += 1
			}
		}
		var k: Int = 0
		while k < nOre {
			let lo: Int = oreLo[k]
			if y >= lo && y <= oreHi[k] {
				if ores[k * H + (y - lo)] > oreThr[k] {
					if hash2(x, y, seed &+ 40 &+ oreSalt[k]) < oreP[k] { return Tile.make(oreTile[k]) }
				}
			}
			k += 1
		}
		return nil
	}

	mutating func rockAt(_ x: Int, _ y: Int) -> Tile {
		let y3: Int = y / 3
		if y3 != rockY3 {
			rockY3 = y3
			rockH = hash2(x, y3, seed &+ 5)
		}
		let hoff: Double = (rockH - 0.5) * 12.0
		let by: Int = y + Int(hoff)
		if by < 300 { return .stone }
		if by < 430 { return .slate }
		return .deepRock
	}
}

// ===== p08a_villages =====

// MARK: - Structures: villages

struct Palette {
	var wall: Tile
	var post: Tile
	var roof: Tile
	var floor: Tile
	var path: Tile
	/// free-standing uprights (porch, smithy, stall and well posts): trunk tiles, which can be walked
	/// through, so a building never walls off the way along the ground
	var beam: Tile
	/// see WorldGen.passableStructures
	var passable: Bool = true
}

func villagePalette(_ b: Biome, passable: Bool) -> Palette {
	var p: Palette = villagePaletteBase(b)
	p.passable = passable
	if !passable { p.beam = p.post }
	return p
}

func villagePaletteBase(_ b: Biome) -> Palette {
	switch b {
	case .desert: return Palette(wall: .sandstone, post: .sandstone, roof: .sandstone, floor: .sandstone, path: .sandstone, beam: .palmLog)
	case .tundra: return Palette(wall: .planks, post: .log, roof: .snow, floor: .planks, path: .stone, beam: .log)
	case .savanna: return Palette(wall: .planks, post: .log, roof: .hay, floor: .planks, path: .dirt, beam: .log)
	case .jungle: return Palette(wall: .planks, post: .jungleLog, roof: .hay, floor: .planks, path: .mud, beam: .jungleLog)
	default: return Palette(wall: .planks, post: .log, roof: .brick, floor: .planks, path: .dirt, beam: .log)
	}
}

func buildHouse(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ ht: Int, _ pal: Palette, _ seed: UInt64) {
	ch.fill(x - 1, gy - ht - w / 2 - 3, x + w, gy - 1, .air)
	ch.fill(x, gy, x + w - 1, gy, pal.floor)
	for yy in (gy - ht)...(gy - 1) {
		ch.put(x, yy, pal.wall)
		ch.put(x + w - 1, yy, pal.wall)
	}
	ch.put(x, gy - 1, pal.post); ch.put(x, gy - ht, pal.post)
	ch.put(x + w - 1, gy - 1, pal.post); ch.put(x + w - 1, gy - ht, pal.post)
	// a door in each end wall (the way along the ground always goes through a house), and a
	// window above one of them
	let doorLeft: Bool = hash2(x, 1, seed) < 0.5
	let wx: Int = doorLeft ? x + w - 1 : x
	if pal.passable {
		for dx in [x, x + w - 1] { ch.put(dx, gy - 1, .doorClosed); ch.put(dx, gy - 2, .doorClosed) }
		if ht >= 4 { ch.put(wx, gy - 3, .glass) }
	} else {
		let dx: Int = doorLeft ? x : x + w - 1
		ch.put(dx, gy - 1, .doorClosed); ch.put(dx, gy - 2, .doorClosed)
		ch.put(wx, gy - 3, .glass)
	}
	// background wall inside the house
	let wk: UInt8 = pal.wall == .sandstone ? 7 : 5
	ch.fillWall(x + 1, gy - ht, x + w - 2, gy - 1, wk)
	// gabled roof
	var k: Int = 0
	while x - 1 + k <= x + w - k {
		let yy: Int = gy - ht - 1 - k
		for xx in (x - 1 + k)...(x + w - k) { ch.put(xx, yy, pal.roof) }
		k += 1
	}
	ch.fillWall(x, gy - ht, x + w - 1, gy - ht, wk)
	// interior
	ch.put(x + w / 2, gy - ht + 1, .lantern)
	let r: Double = hash2(x, 2, seed)
	if r < 0.5 {
		ch.put(x + 2, gy - 1, .workbench)
		ch.put(x + w - 3, gy - 1, .chest)
	} else {
		ch.put(x + 2, gy - 1, .chest)
		ch.put(x + w - 3, gy - 1, .furnace)
	}
	ch.put(x + w / 2, gy - 1, .platform)
}

func buildWell(_ ch: Chunk, _ x: Int, _ gy: Int, _ pal: Palette) {
	ch.fill(x - 1, gy - 6, x + 5, gy - 1, .air)
	ch.fill(x + 1, gy, x + 3, gy + 3, .water)
	ch.fill(x, gy - 1, x, gy - 1, .brick)
	ch.fill(x + 4, gy - 1, x + 4, gy - 1, .brick)
	ch.fill(x, gy, x, gy + 3, .brick)
	ch.fill(x + 4, gy, x + 4, gy + 3, .brick)
	ch.fill(x, gy + 4, x + 4, gy + 4, .brick)
	ch.fill(x, gy - 4, x, gy - 2, pal.beam)
	ch.fill(x + 4, gy - 4, x + 4, gy - 2, pal.beam)
	// a plank cover level with the lip, so the way through the village walks straight over the well
	// (drop through it to reach the water)
	if pal.passable { ch.fill(x + 1, gy - 1, x + 3, gy - 1, .platform) }
	ch.fill(x - 1, gy - 5, x + 5, gy - 5, pal.wall)
	ch.fill(x, gy - 6, x + 4, gy - 6, pal.roof)
}

func buildFarm(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ seed: UInt64) {
	ch.fill(x - 1, gy - 4, x + w, gy - 1, .air)
	for i in 0..<w {
		let xx: Int = x + i
		if i % 5 == 2 {
			ch.put(xx, gy, .water)
			ch.put(xx, gy + 1, .brick)
		} else {
			ch.put(xx, gy, .farmland)
			let wheat: Bool = hash2(xx, 3, seed) < 0.6
			ch.put(xx, gy - 1, wheat ? .wheat3 : .carrot3)
		}
	}
	ch.put(x - 1, gy - 1, .log); ch.put(x + w, gy - 1, .log)
	ch.put(x - 1, gy - 2, .lantern)
}

func buildSmithy(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
	ch.fill(x - 1, gy - 8, x + w, gy - 1, .air)
	ch.fill(x, gy, x + w - 1, gy, .stone)
	ch.fill(x, gy - 4, x, gy - 1, pal.beam)
	ch.fill(x + w - 1, gy - 4, x + w - 1, gy - 1, pal.beam)
	ch.fill(x - 1, gy - 5, x + w, gy - 5, pal.roof == .brick ? .planks : pal.roof)
	ch.put(x + 2, gy - 1, .furnace)
	ch.put(x + 4, gy - 1, .workbench)
	ch.fillWall(x, gy - 4, x + w - 1, gy - 1, 5)
	ch.put(x + w - 3, gy - 1, .chest)
	ch.put(x + w / 2, gy - 4, .lantern)
	ch.put(x + 1, gy - 1, .hay)
}

func buildStall(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
	ch.fill(x - 1, gy - 7, x + w, gy - 1, .air)
	ch.fill(x, gy - 3, x, gy - 1, pal.beam)
	ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 1, pal.beam)
	ch.fill(x - 1, gy - 4, x + w, gy - 4, pal.roof == .brick ? .hay : pal.roof)
	ch.put(x + 1, gy - 1, .hay)
	ch.put(x + 2, gy - 1, .chest)
	ch.put(x + w - 2, gy - 1, .hay)
}

func buildTower(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
	let ht: Int = 14
	ch.fill(x - 1, gy - ht - 4, x + w, gy - 1, .air)
	ch.fill(x, gy, x + w - 1, gy, .brick)
	ch.fill(x, gy - ht, x, gy - 1, .brick)
	ch.fill(x + w - 1, gy - ht, x + w - 1, gy - 1, .brick)
	ch.fill(x - 1, gy - ht - 1, x + w, gy - ht - 1, .brick)
	var cr: Int = x - 1
	while cr <= x + w {
		ch.put(cr, gy - ht - 2, .brick)
		cr += 2
	}
	// zig-zag platforms to climb
	var yy: Int = gy - 2
	var left: Bool = true
	while yy > gy - ht {
		if left { ch.fill(x + 1, yy, x + w - 3, yy, .platform) } else { ch.fill(x + 2, yy, x + w - 2, yy, .platform) }
		left = !left
		yy -= 2
	}
	ch.put(x, gy - 1, .doorClosed); ch.put(x, gy - 2, .doorClosed)
	if pal.passable { ch.put(x + w - 1, gy - 1, .doorClosed); ch.put(x + w - 1, gy - 2, .doorClosed) }
	ch.fillWall(x + 1, gy - ht, x + w - 2, gy - 1, 6)
	ch.put(x + w / 2, gy - ht + 1, .lantern)
	ch.put(x + w / 2, gy - 1, .torch)
	ch.put(x + 1, gy - ht, .chest)
}

func buildLamp(_ ch: Chunk, _ x: Int, _ gy: Int) {
	ch.fill(x, gy - 3, x, gy - 1, .log)
	ch.put(x, gy - 4, .lantern)
}

func buildVillage(_ g: WorldGen, _ ch: Chunk, _ v: VillageSite) {
	let x0: Int = ch.x0
	if v.x + v.halfW + 14 < x0 || v.x - v.halfW - 14 > x0 + chunkW { return }
	var rng = RNG(v.seed)
	let gy: Int = v.ground
	let pal: Palette = villagePalette(v.biome, passable: g.passableStructures)
	let left: Int = v.x - v.halfW
	let right: Int = v.x + v.halfW
	ch.fill(left - 3, gy - 24, right + 3, gy - 1, .air)
	for x in (left - 1)...(right + 1) {
		ch.put(x, gy, pal.path)
		if v.biome == .desert { ch.put(x, gy + 1, .sandstone) } else { ch.put(x, gy + 1, .dirt) }
	}
	buildWell(ch, v.x - 2, gy, pal)
	var haveSmithy: Bool = false
	var haveTower: Bool = false
	var haveFarm: Bool = false
	for side in 0..<2 {
		let dir: Int = side == 0 ? -1 : 1
		var cursor: Int = v.x + dir * 7
		var guardCount: Int = 0
		while abs(cursor - v.x) < v.halfW - 4 && guardCount < 12 {
			guardCount += 1
			let r: Double = rng.double()
			var kind: Int = 0
			if r < 0.28 { kind = 0 } else if r < 0.48 { kind = 1 } else if r < 0.62 { kind = 3 } else if r < 0.74 { kind = 4 } else if r < 0.86 { kind = 5 } else { kind = 6 }
			if kind == 4 && haveSmithy { kind = 1 }
			if kind == 6 && haveTower { kind = 0 }
			if kind == 3 && haveFarm && side == 0 { kind = 1 }
			var w: Int = 9
			switch kind {
			case 0: w = 9
			case 1: w = 7
			case 3: w = 12
			case 4: w = 9
			case 5: w = 6
			default: w = 7
			}
			let bx: Int = dir < 0 ? cursor - w + 1 : cursor
			if abs(bx - v.x) + w > v.halfW + 2 { break }
			switch kind {
			case 0: buildHouse(ch, bx, gy, w, 5, pal, rng.next())
			case 1: buildHouse(ch, bx, gy, w, 4, pal, rng.next())
			case 3: buildFarm(ch, bx, gy, w, rng.next()); haveFarm = true
			case 4: buildSmithy(ch, bx, gy, w, pal); haveSmithy = true
			case 5: buildStall(ch, bx, gy, w, pal)
			default: buildTower(ch, bx, gy, w, pal); haveTower = true
			}
			let gap: Int = 2 + rng.int(3)
			if gap >= 3 {
				let lx: Int = dir < 0 ? bx - 1 - gap / 2 : bx + w + gap / 2
				buildLamp(ch, lx, gy)
			}
			cursor = dir < 0 ? bx - gap - 1 : bx + w + gap
		}
	}
	// flowers & hay near the well
	ch.put(v.x - 4, gy - 1, .flowerR)
	ch.put(v.x + 4, gy - 1, .flowerY)
}

// ===== p08b_ruins =====

// MARK: - Structures: ruins, lairs, portal chamber

func groundAtX(_ g: WorldGen, _ cols: [Col], _ off: Int, _ x: Int) -> Int {
	let i: Int = x - off
	if i >= 0 && i < cols.count { return cols[i].h }
	return g.col(x).h
}

/// Level the ground between xa...xb to row gy and clear the air above
func padGround(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ xa: Int, _ xb: Int, _ gy: Int, _ clearH: Int) {
	for x in xa...xb {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let h: Int = groundAtX(g, cols, off, x)
		if h > gy { ch.fill(x, gy, x, h - 1, .dirt) }
		if h < gy { ch.fill(x, h, x, gy - 1, .air) }
		ch.fill(x, gy - clearH, x, gy - 1, .air)
		ch.put(x, gy, .dirt)
	}
}

func decay(_ ch: Chunk, _ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ p: Double, _ seed: UInt64) {
	for x in xa...xb {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		for y in ya...yb {
			let t: Tile = ch.at(x, y)
			if !t.solid { continue }
			if hash2(x, y, seed) < p { ch.put(x, y, .air) }
			else if hash2(x, y, seed &+ 5) < 0.18 {
				if t == .planks || t == .log { ch.put(x, y, .mossBrick) }
			}
		}
	}
}

func scatterCobwebs(_ ch: Chunk, _ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ p: Double, _ seed: UInt64) {
	for x in xa...xb {
		for y in ya...yb {
			if ch.at(x, y) == .air && hash2(x, y, seed) < p { ch.putIfAir(x, y, .cobweb) }
		}
	}
}

func buildRuinHouse(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let w: Int = 11
	let x: Int = s.x - w / 2
	let gy: Int = groundAtX(g, cols, off, s.x)
	padGround(g, ch, cols, off, x - 2, x + w + 2, gy, 12)
	buildHouse(ch, x, gy, w, 5, villagePalette(.plains, passable: g.passableStructures), s.seed)
	decay(ch, x - 1, gy - 12, x + w, gy - 1, 0.28, s.seed &+ 1)
	scatterCobwebs(ch, x + 1, gy - 5, x + w - 2, gy - 1, 0.18, s.seed &+ 2)
	for k in 0..<4 { ch.putIfAir(x + 2 + k * 2, gy - 1, hash2(k, 1, s.seed) < 0.5 ? .tallGrass : .flowerY) }
	// cellar reached through a hatch in the floor, with a spike trap
	let hx: Int = x + w / 2
	ch.fill(x + 1, gy + 1, x + w - 2, gy + 7, .mossBrick)
	ch.fill(x + 2, gy + 2, x + w - 3, gy + 6, .air)
	ch.put(hx, gy, .air); ch.put(hx, gy + 1, .air)
	ch.fill(hx - 1, gy + 6, hx + 1, gy + 6, .spikes)
	ch.put(x + 2, gy + 6, .chest)
	ch.put(x + w - 3, gy + 6, .chest)
	// the way back up: a ladder under a platform in the floor
	if g.passableStructures {
		ch.put(x + 3, gy, .platform)
		ch.fill(x + 3, gy + 1, x + 3, gy + 6, .ladder)
	}
	ch.put(x + w / 2 + 2, gy + 2, .lantern)
	ch.fill(x + 2, gy + 7, x + w - 3, gy + 7, .mossBrick)
}

func buildRuinTower(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let w: Int = 9
	let x: Int = s.x - w / 2
	let gy: Int = groundAtX(g, cols, off, s.x)
	let ht: Int = 14 + Int(hash2(1, 1, s.seed) * 6.0)
	padGround(g, ch, cols, off, x - 3, x + w + 2, gy, ht + 4)
	ch.fill(x, gy - ht, x + w - 1, gy, .mossBrick)
	ch.fill(x + 1, gy - ht + 1, x + w - 2, gy - 1, .air)
	ch.fill(x, gy, x + w - 1, gy, .brick)
	var yy: Int = gy - 3
	var odd: Bool = true
	while yy > gy - ht {
		if odd { ch.fill(x + 1, yy, x + w - 4, yy, .platform) } else { ch.fill(x + 3, yy, x + w - 2, yy, .platform) }
		odd = !odd
		yy -= 3
	}
	if g.passableStructures {
		for dx in [x, x + w - 1] { ch.fill(dx, gy - 3, dx, gy - 1, .air) }
	} else {
		ch.put(x, gy - 1, .air); ch.put(x, gy - 2, .air); ch.put(x, gy - 3, .air)
	}
	ch.put(x + w - 1, gy - ht + 4, .glass)
	ch.put(x + w / 2, gy - 1, .chest)
	ch.put(x + 2, gy - 1, .torch)
	for k in 0..<ht {
		let frac: Double = Double(k) / Double(ht)
		decay(ch, x - 1, gy - k, x + w, gy - k, 0.04 + frac * 0.55, s.seed &+ UInt64(k))
	}
	scatterCobwebs(ch, x + 1, gy - ht, x + w - 2, gy - 4, 0.08, s.seed &+ 9)
	for dx in -2...(w + 1) {
		if hash2(dx, 3, s.seed) < 0.5 { ch.putIfAir(x + dx, gy - 1, .mossBrick) }
		if hash2(dx, 4, s.seed) < 0.35 { ch.putIfAir(x + dx, gy - 2, .leaves) }
	}
}

func buildRuinFort(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let x: Int = s.x - 17
	let gy: Int = groundAtX(g, cols, off, s.x)
	padGround(g, ch, cols, off, x - 2, x + 36, gy, 14)
	// left wall block and right wall block with a collapsed gate between
	ch.fill(x, gy - 8, x + 9, gy, .brick)
	ch.fill(x + 1, gy - 7, x + 8, gy - 1, .air)
	ch.fill(x + 25, gy - 6, x + 34, gy, .brick)
	ch.fill(x + 26, gy - 5, x + 33, gy - 1, .air)
	var cx: Int = x
	while cx <= x + 9 { ch.put(cx, gy - 9, .brick); cx += 2 }
	cx = x + 25
	while cx <= x + 34 { ch.put(cx, gy - 7, .brick); cx += 2 }
	// low connecting wall
	ch.fill(x + 10, gy - 2, x + 24, gy, .mossBrick)
	for k in 0...6 { ch.fill(x + 11 + k * 2, gy - 3, x + 11 + k * 2, gy - 3, .mossBrick) }
	// rubble mounds (no higher than a jump where structures are passable)
	let capH: Int = g.passableStructures ? 3 : 4
	for dx in 8...14 { let hgt: Int = min(capH, max(0, 4 - abs(dx - 11))); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .stone) }
	for dx in 22...28 { let hgt: Int = max(0, 3 - abs(dx - 25)); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .brick) }
	// broken gateways through each wall block, so the fort can be walked through
	if g.passableStructures { for wx in [x, x + 9, x + 25, x + 34] { ch.fill(wx, gy - 3, wx, gy - 1, .air) } }
	// courtyard camp inside
	ch.put(x + 17, gy - 1, .campfire)
	ch.put(x + 20, gy - 1, .chest)
	ch.put(x + 4, gy - 1, .chest)
	ch.put(x + 4, gy - 6, .lantern)
	ch.put(x + 29, gy - 1, .hay)
	decay(ch, x - 1, gy - 10, x + 35, gy - 2, 0.30, s.seed)
	scatterCobwebs(ch, x + 1, gy - 7, x + 34, gy - 2, 0.05, s.seed &+ 3)
}

func buildCamp(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let x: Int = s.x - 8
	let gy: Int = groundAtX(g, cols, off, s.x)
	padGround(g, ch, cols, off, x - 2, x + 18, gy, 8)
	// tent
	var k: Int = 0
	while k < 5 {
		ch.put(x + k, gy - 1 - k, .planks)
		ch.put(x + 9 - k, gy - 1 - k, .planks)
		k += 1
	}
	ch.put(x + 4, gy - 5, .planks); ch.put(x + 5, gy - 5, .planks)
	ch.fill(x + 1, gy - 1, x + 8, gy - 1, .air)
	// the tent flap is open on the fire side
	if g.passableStructures { ch.put(x + 9, gy - 1, .air); ch.put(x + 8, gy - 2, .air) }
	ch.put(x + 3, gy - 1, .hay)
	ch.put(x + 7, gy - 1, .chest)
	ch.put(x + 14, gy - 1, .campfire)
	ch.put(x + 12, gy - 1, .log)
	ch.put(x + 16, gy - 1, .log)
	ch.put(x + 13, gy - 2, .fossil)
	ch.put(x + 17, gy - 1, .deadBush)
	scatterCobwebs(ch, x + 1, gy - 4, x + 8, gy - 2, 0.1, s.seed)
}

func buildOvergrown(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let x: Int = s.x - 12
	let gy: Int = groundAtX(g, cols, off, s.x)
	padGround(g, ch, cols, off, x - 2, x + 26, gy, 12)
	ch.fill(x, gy, x + 24, gy, .mossBrick)
	for p in 0..<5 {
		let px: Int = x + 1 + p * 6
		let ph: Int = 4 + Int(hash2(p, 1, s.seed) * 6.0)
		if g.passableStructures {
			// the shafts are crumbled to their back walls; their capitals still stand overhead
			ch.fillWall(px, gy - ph + 1, px + 1, gy - 1, 6)
			ch.fill(px, gy - ph, px + 1, gy - ph, .mossBrick)
			if hash2(p, 3, s.seed) < 0.5 { ch.put(px, gy - 1, .mossBrick) }
		} else {
			ch.fill(px, gy - ph, px + 1, gy - 1, .mossBrick)
		}
		if hash2(p, 2, s.seed) < 0.6 && p < 4 { ch.fill(px + 2, gy - ph, px + 6, gy - ph, .mossBrick) }
		for lv in 0..<6 {
			let lx: Int = px - 1 + Int(hash2(lv, p, s.seed) * 4.0)
			ch.putIfAir(lx, gy - ph - 1 - Int(hash2(p, lv, s.seed &+ 1) * 2.0), .leaves)
		}
	}
	ch.put(x + 12, gy - 1, .chest)
	ch.put(x + 11, gy - 1, .flowerR)
	ch.put(x + 13, gy - 1, .flowerY)
	ch.put(x + 9, gy - 1, .reed)
	decay(ch, x, gy - 12, x + 24, gy - 2, 0.22, s.seed &+ 7)
	for dx in 0...24 { if hash2(dx, 8, s.seed) < 0.5 { ch.putIfAir(x + dx, gy - 1, hash2(dx, 9, s.seed) < 0.5 ? .tallGrass : .mushroom) } }
}

func buildBunker(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	let gy: Int = groundAtX(g, cols, off, s.x)
	let y0: Int = gy + 60 + Int(hash2(2, 2, s.seed) * 90.0)
	let x: Int = s.x - 14
	ch.fill(x, y0 - 1, x + 28, y0 + 11, .mossBrick)
	ch.fill(x + 1, y0, x + 27, y0 + 9, .air)
	ch.fill(x, y0 + 10, x + 28, y0 + 10, .brick)
	// inner divider with a cracked (hidden) door
	ch.fill(x + 18, y0, x + 18, y0 + 9, .brick)
	ch.fill(x + 18, y0 + 7, x + 18, y0 + 9, .crackedBrick)
	// corridor with traps
	for k in 0..<5 { ch.put(x + 4 + k * 3, y0 + 9, .spikes) }
	ch.put(x + 2, y0 + 9, .chest)
	ch.put(x + 14, y0 + 8, .torch)
	ch.put(x + 7, y0 + 1, .lantern)
	// treasure room
	ch.put(x + 21, y0 + 9, .chest)
	ch.put(x + 25, y0 + 9, .chest)
	ch.put(x + 23, y0 + 1, .lantern)
	ch.put(x + 20, y0 + 9, .torch)
	ch.put(x + 22, y0 + 9, .glowCrystal)
	scatterCobwebs(ch, x + 1, y0, x + 17, y0 + 4, 0.1, s.seed)
}

func buildRare(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
	switch s.kind {
	case .house: buildRuinHouse(g, ch, cols, off, s)
	case .tower: buildRuinTower(g, ch, cols, off, s)
	case .fort: buildRuinFort(g, ch, cols, off, s)
	case .camp: buildCamp(g, ch, cols, off, s)
	case .overgrown: buildOvergrown(g, ch, cols, off, s)
	case .bunker: buildBunker(g, ch, cols, off, s)
	}
}

// MARK: lairs

/// Row the boss stands on: the floor of the pit, or the ground of a flat world's open arena
func lairFloorRow(_ g: WorldGen) -> Int { return g.options.flat ? WorldGen.flatSurface : WorldGen.sea - 10 + 9 }

func buildLair(_ g: WorldGen, _ ch: Chunk, _ L: LairInfo) {
	if g.options.flat {
		buildFlatLair(g, ch, L)
		return
	}
	let gy: Int = WorldGen.sea - 10
	let cx: Int = L.cx
	let kraw: UInt64 = UInt64(L.kind.rawValue + 1)
	let kmul: UInt64 = kraw &* 7777
	let seed: UInt64 = g.seed &+ kmul
	let isRex: Bool = L.kind == .rex
	for x in (cx - 52)...(cx + 52) {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let d: Int = abs(x - cx)
		var depth: Int = 0
		if d <= 30 { depth = 9 } else if d <= 39 { depth = 9 - (d - 30) }
		ch.fill(x, gy - 22, x, gy - 1, .air)
		if depth > 0 { ch.fill(x, gy, x, gy + depth - 1, .air) }
		// floor surface of the pit
		if depth > 0 {
			ch.put(x, gy + depth, isRex ? .mud : .stone)
			ch.put(x, gy + depth + 1, isRex ? .mud : .stone)
		} else {
			ch.put(x, gy, isRex ? .jungleGrass : .grass)
		}
		let fy: Int = gy + depth - 1
		if depth >= 8 && hash2(x, 1, seed) < 0.09 { ch.put(x, fy, .fossil) }
		if depth >= 8 && hash2(x, 2, seed) < 0.05 { ch.put(x, fy - 1, .cobweb) }
		if depth == 0 && hash2(x, 3, seed) < 0.12 { ch.put(x, gy - 1, isRex ? .tallGrass : .deadBush) }
	}
	// rim decorations: marker stones (low enough to jump where structures are passable; a full jump
	// clears three blocks)
	let rimH: Int = g.passableStructures ? 2 : 4
	for side in [-1, 1] {
		let rx: Int = cx + side * 44
		ch.fill(rx, gy - rimH, rx, gy - 1, .stone)
		ch.put(rx, gy - rimH - 1, .torch)
		let rx2: Int = cx + side * 36
		ch.put(rx2, gy - 1, .torch)
	}
	if isRex {
		// the half-buried ribs of something enormous: two-block stubs curling over at the top, low
		// enough that the nest floor can still be crossed with a jump
		for side in [-1, 1] {
			for rb in 0..<3 {
				let bx: Int = cx + side * (14 + rb * 8)
				if g.passableStructures {
					ch.fill(bx, gy + 7, bx, gy + 8, .fossil)
					ch.put(bx - side, gy + 7, .fossil)
				} else {
					// older worlds: full ribs arching over the nest
					let top: Int = gy + 9 - 10 - rb
					ch.fill(bx, top, bx, gy + 8, .fossil)
					ch.put(bx - side, top - 1, .fossil)
					ch.put(bx - 2 * side, top - 1, .fossil)
				}
			}
		}
		for k in 0..<10 { ch.putIfAir(cx - 24 + k * 5, gy + 7, .jungleLeaves) }
	} else {
		ch.fill(cx - 18, gy + 6, cx - 18, gy + 8, .stone)
		ch.fill(cx + 18, gy + 6, cx + 18, gy + 8, .stone)
		ch.put(cx - 18, gy + 5, .torch)
		ch.put(cx + 18, gy + 5, .torch)
	}
	// treasure chest at the far edge of the pit floor
	ch.put(cx + (isRex ? -27 : 27), gy + 8, .chest)
}

/// A flat world's lair: an open arena on the surface instead of a pit, paved and ringed with low
/// marker stones, so the ground stays level. The boss fights on the surface (see lairFloorRow).
func buildFlatLair(_ g: WorldGen, _ ch: Chunk, _ L: LairInfo) {
	let gy: Int = WorldGen.flatSurface
	let cx: Int = L.cx
	let kraw: UInt64 = UInt64(L.kind.rawValue + 1)
	let seed: UInt64 = g.seed &+ (kraw &* 7777)
	let isRex: Bool = L.kind == .rex
	for x in (cx - 52)...(cx + 52) {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let d: Int = abs(x - cx)
		ch.fill(x, gy - 22, x, gy - 1, .air)
		if d <= 39 {
			// the trampled arena floor
			let worn: Bool = hash2(x, 4, seed) < (isRex ? 0.25 : 0.35)
			ch.put(x, gy, isRex ? (worn ? .mossGrass : .mud) : (worn ? .crackedBrick : .stone))
			ch.put(x, gy + 1, isRex ? .mud : .stone)
			if d >= 4 && hash2(x, 1, seed) < 0.07 { ch.put(x, gy, .fossil) }
		} else {
			ch.put(x, gy, isRex ? .jungleGrass : .grass)
			if hash2(x, 3, seed) < 0.12 { ch.put(x, gy - 1, isRex ? .tallGrass : .deadBush) }
		}
	}
	for side in [-1, 1] {
		let rx: Int = cx + side * 44
		ch.fill(rx, gy - 2, rx, gy - 1, .stone)
		ch.put(rx, gy - 3, .torch)
		ch.put(cx + side * 36, gy - 1, .torch)
	}
	if isRex {
		for side in [-1, 1] {
			for rb in 0..<3 {
				let bx: Int = cx + side * (14 + rb * 8)
				ch.fill(bx, gy - 2, bx, gy - 1, .fossil)
				ch.put(bx - side, gy - 2, .fossil)
			}
		}
		for k in 0..<10 { ch.putIfAir(cx - 24 + k * 5, gy - 1, .tallGrass) }
	} else {
		for side in [-1, 1] {
			ch.put(cx + side * 18, gy - 1, .stone)
			ch.put(cx + side * 18, gy - 2, .torch)
		}
	}
	ch.put(cx + (isRex ? -27 : 27), gy - 1, .chest)
}

// MARK: portal chamber

func buildPortalChamber(_ g: WorldGen, _ ch: Chunk) {
	let px: Int = g.portalX
	let py: Int = g.portalY
	ch.fill(px - 12, py - 10, px + 12, py + 7, .brick)
	ch.fill(px - 10, py - 8, px + 10, py + 5, .air)
	ch.fill(px - 12, py + 6, px + 12, py + 7, .obsidian)
	// frame: 7 wide, 9 tall; interior 5x7
	let fx: Int = px - 3
	let fy: Int = py + 5
	if g.genVersion >= 2 {
		buildRift(ch, px, fy, .portalOff)
	} else {
		ch.fill(fx, fy - 8, fx + 6, fy - 8, .portalFrame)
		ch.fill(fx, fy, fx + 6, fy, .portalFrame)
		ch.fill(fx, fy - 8, fx, fy, .portalFrame)
		ch.fill(fx + 6, fy - 8, fx + 6, fy, .portalFrame)
		ch.fill(fx + 1, fy - 7, fx + 5, fy - 1, .portalOff)
	}
	// decorations: torches and mossy rubble
	ch.put(px - 9, py + 4, .torch)
	ch.put(px + 9, py + 4, .torch)
	ch.put(px - 9, py - 4, .lantern)
	ch.put(px + 9, py - 4, .lantern)
	for k in 0..<8 {
		let rx: Int = px - 10 + k * 3
		if abs(rx - px) <= 3 { continue }
		if hash2(rx, 1, g.seed) < 0.6 { ch.put(rx, py + 5, .mossBrick) }
		if hash2(rx, 2, g.seed) < 0.3 { ch.put(rx, py + 4, .cobweb) }
	}
	ch.put(px - 7, py + 5, .glowCrystal)
	ch.put(px + 7, py + 5, .glowCrystal)
}

func applyStructures(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int) {
	let x0: Int = ch.x0
	let mid: Int = x0 + chunkW / 2
	for L in g.lairCenters(near: mid) {
		if abs(L.cx - mid) < 62 { buildLair(g, ch, L) }
	}
	for v in g.villages(overlapping: x0 - 14, x0 + chunkW + 14) { buildVillage(g, ch, v) }
	for r in g.rareSites(overlapping: x0 - 30, x0 + chunkW + 30) { buildRare(g, ch, cols, off, r) }
	if abs(g.portalX - mid) < 24 { buildPortalChamber(g, ch) }
	for s in g.grottoSites(overlapping: x0, x0 + chunkW - 1) { buildGrotto(g, ch, s) }
	for s in g.mineSites(overlapping: x0, x0 + chunkW - 1) { buildMine(g, ch, s) }
}

// MARK: - Crystal grottos, old mines and surface landmarks (generator version 3)

/// A vaulted cavern deep underground, its walls studded with crystal, a guarded altar chest at the
/// centre, a still pool, and a long stepped passage climbing from it toward the surface (in standard
/// worlds it comes out as a cave mouth; flat worlds keep their crust whole, so there it ends sealed)
struct GrottoSite {
	var cell: Int
	var x: Int
	/// the row the cavern floor is on
	var floorY: Int
	var rx: Int
	var ry: Int
	/// the passage leaves the cavern on this side and climbs one row per column
	var dir: Int
	var passLen: Int
	/// whether the passage reaches the surface
	var open: Bool
	var seed: UInt64
	var passStartX: Int { return x + dir * (rx - 3) }
	var minX: Int { return min(x - rx - 3, passStartX + min(0, dir * passLen) - 2) }
	var maxX: Int { return max(x + rx + 3, passStartX + max(0, dir * passLen) + 2) }
}

/// An old mine: a timber headframe over a covered, laddered shaft, with galleries off it
struct MineSite {
	var cell: Int
	/// left column of the three-wide shaft (the ladder runs up the middle column)
	var x: Int
	var ground: Int
	/// floor rows of the galleries, top to bottom; the last one is the floor of the shaft
	var levels: [Int]
	var left: [Int]
	var right: [Int]
	var seed: UInt64
	/// worlds made with generator version 4 or later: the whole network, laid out once
	var plan: MinePlan? = nil
	var bottom: Int { return levels.last ?? ground }
	var minX: Int { if let p = plan { return p.minX - 2 }; return x - (left.max() ?? 0) - 3 }
	var maxX: Int { if let p = plan { return p.maxX + 2 }; return x + 2 + (right.max() ?? 0) + 3 }
	/// the lowest open row anywhere in the mine
	var deepest: Int { return max(bottom, plan?.maxY ?? bottom) }
}

extension WorldGen {
	static let grottoCell: Int = 700
	static let mineCell: Int = 900
	static let landmarkCell: Int = 72
	/// the longest passage a grotto may have (the deepest floors lie about 280 rows down)
	static let grottoReach: Int = 420

	var hasGrottos: Bool { return genVersion >= 3 && hasStructures && (!options.flat || options.caves) }
	var hasMines: Bool { return genVersion >= 3 && hasStructures }
	var hasLandmarks: Bool { return genVersion >= 3 && hasTrees }

	func grottoSite(cell c: Int) -> GrottoSite? {
		if let v = cache.grottos[c] { return v }
		let v: GrottoSite? = computeGrottoSite(cell: c)
		cache.grottos[c] = v
		return v
	}

	/// whether a grotto passage may come out of the ground at x: dry land with nothing built there
	func caveMouthClear(_ x: Int) -> Bool {
		let c: Col = col(x)
		if c.biome == .ocean || c.h >= WorldGen.sea - 1 { return false }
		if abs(x - spawnX) < 30 || abs(x - portalX) < 60 { return false }
		if lairAt(x, radius: 140) != nil { return false }
		for v in villages(overlapping: x - 20, x + 20) where abs(v.x - x) < v.halfW + 16 { return false }
		for r in rareSites(overlapping: x - 40, x + 40) where abs(r.x - x) < 40 { return false }
		return true
	}

	func computeGrottoSite(cell c: Int) -> GrottoSite? {
		if !hasGrottos { return nil }
		if hash2(c, 601, seed) > 0.6 { return nil }
		let cw: Int = WorldGen.grottoCell
		let x: Int = c * cw + 90 + Int(hash2(c, 602, seed) * Double(cw - 180))
		if !infinite && (x < 260 || x > width - 260) { return nil }
		if abs(x - portalX) < 240 { return nil }
		let rx: Int = 17 + Int(hash2(c, 604, seed) * 9.0)
		let ry: Int = 8 + Int(hash2(c, 605, seed) * 4.0)
		let floorY: Int = 250 + Int(hash2(c, 603, seed) * 130.0)
		let first: Int = hash2(c, 606, seed) < 0.5 ? -1 : 1
		var site = GrottoSite(cell: c, x: x, floorY: floorY, rx: rx, ry: ry, dir: first, passLen: 0, open: false, seed: hashU(c, 607, seed))
		// trace the passage up one row per column; try the other side if the first comes out badly
		var best: (Int, Int, Bool)? = nil
		for d in [first, -first] {
			let sx: Int = x + d * (rx - 3)
			var k: Int = 0
			var result: (Int, Bool)? = nil
			var checked: Bool = false
			while k < WorldGen.grottoReach {
				let px: Int = sx + d * k
				if !infinite && (px < 40 || px > width - 40) { result = (max(0, k - 1), false); break }
				let h: Int = col(px).h
				let fk: Int = floorY - k
				if options.flat {
					// stop while the passage roof is still below the crust
					if fk - 5 < h + WorldGen.flatCrust { result = (max(0, k - 1), false); break }
				} else {
					if !checked && fk <= h + 8 {
						// the last stretch: open only onto clear, dry ground
						checked = true
						var clear: Bool = true
						var j: Int = 0
						while j <= 16 && clear { clear = caveMouthClear(px + d * j); j += 4 }
						if !clear {
							// generator 6: the passage stops short enough that its roof keeps four rows of
							// ground over it, even where the land drops away just there
							var kk: Int = k
							if genVersion >= 6 {
								while kk > 0 && floorY - kk - 4 <= col(sx + d * kk).h + 3 { kk -= 1 }
							}
							result = (kk, false)
							break
						}
					}
					if fk <= h { result = (k, true); break }
				}
				k += 1
			}
			let r: (Int, Bool) = result ?? (k, false)
			if r.1 { best = (d, r.0, true); break }
			if best == nil { best = (d, r.0, false) }
		}
		if let b = best {
			site.dir = b.0
			site.passLen = b.1
			site.open = b.2
		}
		return site
	}

	func grottoSites(overlapping x0: Int, _ x1: Int) -> [GrottoSite] {
		var out: [GrottoSite] = []
		if !hasGrottos { return out }
		let cw: Int = WorldGen.grottoCell
		let c0: Int = floorDiv(x0 - WorldGen.grottoReach - 40, cw)
		let c1: Int = floorDiv(x1 + WorldGen.grottoReach + 40, cw)
		for c in c0...c1 {
			if let s = grottoSite(cell: c), s.maxX >= x0 && s.minX <= x1 { out.append(s) }
		}
		return out
	}

	func mineSite(cell c: Int) -> MineSite? {
		if let v = cache.mines[c] { return v }
		let v: MineSite? = computeMineSite(cell: c)
		cache.mines[c] = v
		return v
	}

	func computeMineSite(cell c: Int) -> MineSite? {
		if !hasMines { return nil }
		if hash2(c, 621, seed) > (genVersion >= 4 ? 0.62 : 0.55) { return nil }
		let cw: Int = WorldGen.mineCell
		let ok: [Biome] = [.plains, .forest, .mountain, .tundra, .savanna, .desert]
		// a few tries across the cell for a level spot to sink the shaft
		func usable(_ x: Int) -> Col? {
			if !infinite && (x < 320 || x > width - 320) { return nil }
			if abs(x - spawnX) < 60 || abs(x - portalX) < 80 { return nil }
			let base: Col = col(x)
			if !ok.contains(base.biome) || base.h >= WorldGen.sea - 1 { return nil }
			for d in -4...6 {
				let cc: Col = col(x + d)
				if cc.biome == .ocean || abs(cc.h - base.h) > 1 { return nil }
			}
			if lairAt(x, radius: 200) != nil { return nil }
			if nearestVillageSimple(x) { return nil }
			for r in rareSites(overlapping: x - 70, x + 70) where abs(r.x - x) < 70 { return nil }
			return base
		}
		var found: (Int, Col)? = nil
		for attempt in 0..<10 {
			let x: Int = c * cw + 120 + Int(hash2(c, 622 + attempt * 3, seed) * Double(cw - 240))
			if let b = usable(x) { found = (x, b); break }
		}
		guard let (x, base) = found else { return nil }
		if genVersion >= 4 {
			let (plan, levels, lefts, rights) = planMine(cell: c, x: x, ground: base.h)
			var site = MineSite(cell: c, x: x, ground: base.h, levels: levels, left: lefts, right: rights, seed: hashU(c, 624, seed))
			site.plan = plan
			return site
		}
		let depth: Int = 60 + Int(hash2(c, 623, seed) * 100.0)
		let n: Int = depth > 130 ? 3 : (depth > 90 ? 2 : 1)
		var levels: [Int] = []
		var left: [Int] = []
		var right: [Int] = []
		for k in 0..<n {
			levels.append(base.h + depth * (k + 1) / n)
			left.append(16 + Int(hash2(c, 630 + k, seed) * 40.0))
			right.append(16 + Int(hash2(c, 640 + k, seed) * 40.0))
		}
		return MineSite(cell: c, x: x, ground: base.h, levels: levels, left: left, right: right, seed: hashU(c, 624, seed))
	}

	func mineSites(overlapping x0: Int, _ x1: Int) -> [MineSite] {
		var out: [MineSite] = []
		if !hasMines { return out }
		let cw: Int = WorldGen.mineCell
		let reach: Int = genVersion >= 4 ? 160 : 80
		for c in floorDiv(x0 - reach, cw)...floorDiv(x1 + reach, cw) {
			if let s = mineSite(cell: c), s.maxX >= x0 && s.minX <= x1 { out.append(s) }
		}
		return out
	}
}

/// Water or lava touching carved-out space becomes stone, so nothing hangs in the air
private func sealLiquid(_ ch: Chunk, _ x: Int, _ y: Int) {
	if ch.at(x, y).liquid { ch.put(x, y, .stone) }
}

func buildGrotto(_ g: WorldGen, _ ch: Chunk, _ s: GrottoSite) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	let rxD: Double = Double(s.rx)
	let ryD: Double = Double(s.ry)
	let fy: Int = s.floorY
	let xa: Int = max(cx0, s.x - s.rx - 3)
	let xb: Int = min(cx1, s.x + s.rx + 3)
	if xa <= xb {
		for x in xa...xb {
			let u: Double = Double(x - s.x) / rxD
			let wob: Double = 1.0 + (vnoise(Double(x) * 0.18, 3.0, s.seed) - 0.5) * 0.26
			let inner: Double = wob * wob - u * u
			let vaultD: Double = inner > 0 ? (sqrt(inner) / wob * ryD).rounded() : 0
			let vault: Int = Int(vaultD)
			let ow: Double = wob * 1.28
			let outer: Double = ow * ow - u * u
			let shellD: Double = outer > 0 ? (sqrt(outer) / ow * ryD * 1.2).rounded() + 1.0 : 0
			let shell: Int = Int(shellD)
			let side: Double = -Double(s.dir)
			let along: Double = u * side
			let pool: Bool = along > 0.45 && along < 0.8
			// crystal-studded shell around the vault
			if shell > 0 {
				for y in (fy - shell - 1)...(fy + 1) {
					if y >= fy - vault && y < fy { continue }
					let t: Tile = ch.at(x, y)
					if t.liquid { ch.put(x, y, .stone); continue }
					if !t.solid || t == .bedrock { continue }
					let r: Double = hash2(x, y, s.seed &+ 3)
					if r < 0.22 { ch.put(x, y, .crystalOre) } else if r < 0.27 { ch.put(x, y, .glowCrystal) }
				}
			}
			if vault <= 0 { continue }
			for y in (fy - vault)..<fy { ch.put(x, y, .air) }
			// a level floor (stone bridges any cave below), or the pool
			if pool {
				ch.put(x, fy, .water)
				ch.put(x, fy + 1, .water)
				if !ch.at(x, fy + 2).solid { ch.put(x, fy + 2, .stone) }
				sealLiquid(ch, x, fy + 2)
			} else if !ch.at(x, fy).solid || ch.at(x, fy) == .glowCrystal {
				ch.put(x, fy, .stone)
			}
			// crystals hanging from the vault and standing on the floor
			if vault > 4 && hash2(x, 1, s.seed &+ 5) < 0.14 { ch.put(x, fy - vault, .glowCrystal) }
			if !pool && abs(x - s.x) > 7 && hash2(x, 2, s.seed &+ 5) < 0.08 { ch.put(x, fy - 1, .glowCrystal) }
		}
		// the altar, its chest, and two crystal pillars standing guard
		for dx in -2...2 { ch.put(s.x + dx, fy - 1, .mossBrick) }
		ch.put(s.x, fy - 2, .chest)
		for side in [-1, 1] {
			ch.put(s.x + side * 6, fy - 1, .glowCrystal)
			ch.put(s.x + side * 6, fy - 2, .glowCrystal)
		}
	}
	// the passage: four rows tall, climbing one row per column, lit by crystals in its roof
	if s.passLen <= 0 { return }
	let sx: Int = s.passStartX
	for k in 0...s.passLen {
		let px: Int = sx + s.dir * k
		if px < cx0 || px > cx1 { continue }
		let fk: Int = fy - k
		for y in (fk - 4)...(fk - 1) where ch.at(px, y) != .bedrock { ch.put(px, y, .air) }
		if !ch.at(px, fk).solid && k < s.passLen - 2 { ch.put(px, fk, .stone) }
		sealLiquid(ch, px, fk)
		sealLiquid(ch, px, fk - 5)
		if k % 7 == 3 && ch.at(px, fk - 5).solid && ch.at(px, fk - 5) != .bedrock { ch.put(px, fk - 5, .glowCrystal) }
		if s.open {
			// near the mouth, clear away trunks and leaves left hanging over the cut
			let h: Int = g.col(px).h
			let lo: Int = max(1, h - 18)
			let hi: Int = fk - 4
			if fk - 5 <= h + 1 && lo < hi {
				for y in lo..<hi {
					let t: Tile = ch.at(px, y)
					if isLogTile(t) || isLeafTile(t) { ch.put(px, y, .air) }
				}
			}
		}
	}
}

func buildMine(_ g: WorldGen, _ ch: Chunk, _ s: MineSite) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	let gy: Int = s.ground
	let bottom: Int = s.bottom
	let sx: Int = s.x
	let plankWall: UInt8 = 5
	func clipped(_ a: Int, _ b: Int) -> ClosedRange<Int>? {
		let lo: Int = max(a, cx0)
		let hi: Int = min(b, cx1)
		return lo <= hi ? lo...hi : nil
	}
	// the headframe: two timber posts (background walls, so they never block the way), a beam you
	// can stand on, a lantern under it, torches either side
	if let r = clipped(sx - 2, sx + 4) {
		for x in r {
			for y in (gy - 7)...(gy - 1) {
				let t: Tile = ch.at(x, y)
				if t.isPlant || isLogTile(t) || isLeafTile(t) { ch.put(x, y, .air) }
			}
		}
	}
	ch.fillWall(sx - 1, gy - 5, sx - 1, gy - 1, plankWall)
	ch.fillWall(sx + 3, gy - 5, sx + 3, gy - 1, plankWall)
	ch.fill(sx - 1, gy - 6, sx + 3, gy - 6, .platform)
	ch.put(sx + 1, gy - 5, .lantern)
	ch.put(sx - 2, gy - 1, .torch)
	ch.put(sx + 4, gy - 1, .torch)
	if let plan = s.plan {
		// version 4: the shaft is covered with boards you drop through; the network lies below
		if let r = clipped(sx, sx + 2) { for x in r { ch.put(x, gy, .platform) } }
		// an ore cart left on a short run of rail by the headframe
		if let r = clipped(sx + 5, sx + 9) {
			for x in r where (ch.at(x, gy - 1) == .air || ch.at(x, gy - 1).isPlant) && ch.at(x, gy).solid { ch.put(x, gy - 1, x == sx + 7 ? .oreCart : .rail) }
		}
		buildMinePlan(g, ch, s, plan)
		return
	}
	let galleryRows: Set<Int> = Set(s.levels.flatMap { [$0 - 3, $0 - 2, $0 - 1] })
	// the shaft: covered with planks you can drop through, a ladder all the way down
	if let r = clipped(sx, sx + 2) {
		for x in r {
			ch.put(x, gy, .platform)
			for y in (gy + 1)..<bottom { ch.put(x, y, x == sx + 1 ? .ladder : .air) }
			ch.put(x, bottom, .planks)
			ch.fillWall(x, gy + 1, x, bottom - 1, plankWall)
		}
	}
	// timber lining where the shaft passes through open cave or water
	for x in [sx - 1, sx + 3] where x >= cx0 && x <= cx1 {
		for y in (gy + 1)..<bottom where !galleryRows.contains(y) {
			let t: Tile = ch.at(x, y)
			if !t.solid || t.liquid { ch.put(x, y, .planks) }
		}
	}
	// the galleries
	for (i, f) in s.levels.enumerated() {
		let xa: Int = sx - s.left[i]
		let xb: Int = sx + 2 + s.right[i]
		let depthBelow: Int = f - gy
		if let r = clipped(xa, xb) {
			for x in r {
				let inShaft: Bool = x >= sx && x <= sx + 2
				if inShaft {
					// landings either side of the ladder at the upper galleries
					if f != bottom && x != sx + 1 { ch.put(x, f, .platform) }
					continue
				}
				let rel: Int = x < sx ? sx - x : x - (sx + 2)
				for y in (f - 3)...(f - 1) { ch.put(x, y, .air) }
				if !ch.at(x, f).solid || ch.at(x, f).liquid { ch.put(x, f, .planks) }
				sealLiquid(ch, x, f - 4)
				if rel % 6 == 3 {
					// a timber support: posts behind, a beam overhead
					ch.fillWall(x, f - 3, x, f - 1, plankWall)
					ch.put(x, f - 4, .planks)
				} else if rel % 12 == 7 {
					ch.put(x, f - 1, .torch)
				}
				if rel % 6 == 4 && hash2(x, f + 1, s.seed) < 0.35 { ch.put(x, f - 3, .cobweb) }
				// ore showing in the roof and floor
				let r0: Double = hash2(x, f, s.seed &+ 7)
				if r0 < 0.09 && rel % 6 != 3 {
					let ores: [Tile] = depthBelow < 80 ? [.coal, .copper, .coal] : (depthBelow < 130 ? [.iron, .copper, .coal] : [.iron, .gold, .iron])
					let ore: Tile = ores[Int(hash2(x, f, s.seed &+ 8) * 3.0) % 3]
					let oy: Int = r0 < 0.05 ? f - 4 : f
					if ch.at(x, oy).solid && ch.at(x, oy) != .planks { ch.put(x, oy, ore) }
				}
			}
		}
		// one end keeps a chest, the other has caved in
		let chestLeft: Bool = hash2(i, 650, s.seed) < 0.5
		if hash2(i, 651, s.seed) < 0.75 { ch.put(chestLeft ? xa + 1 : xb - 1, f - 1, .chest) }
		let rubble: Int = chestLeft ? xb : xa
		ch.put(rubble, f - 1, .stone)
		ch.put(rubble, f - 2, .stone)
	}
}

// MARK: - Old mines, version 4: a branching network round a laddered shaft

/// Where a chest in a mine sits, which sets what it may hold: out in a gallery, in a side room or at
/// a dead end, or hidden (behind fallen rock, or in a nook high in a chamber roof)
enum MineSpot: Int {
	case open, room, hidden
}

struct MineChest {
	var x: Int
	var y: Int
	var spot: MineSpot
	/// 0 for the top gallery, rising with depth (the great chamber counts one deeper)
	var depth: Int
}

/// A column of open space carved out of the rock
struct MineSpan {
	var x: Int
	var y0: Int
	var y1: Int
}

struct MineTile {
	var x: Int
	var y: Int
	var t: Tile
}

struct MineWall {
	var x: Int
	var y0: Int
	var y1: Int
}

/// Everything a v4 mine is made of, worked out once per site: the spaces to carve, the floors to make
/// sound, the timber walls behind, the fittings, the ore showing in the walls and the chests. Each
/// chunk applies the part that falls inside it, in the same order, so a mine is seamless across chunks.
struct MinePlan {
	var carve: [MineSpan] = []
	var floors: [MineTile] = []
	var walls: [MineWall] = []
	var tiles: [MineTile] = []
	/// ore exposed in the rock face: only placed where the rock is still solid
	var ores: [MineTile] = []
	var chests: [MineChest] = []
	var minX: Int = 0
	var maxX: Int = 0
	var maxY: Int = 0
	/// how the mine is laid out (for tests, and to keep the variety honest)
	var tunnels: Int = 0
	var rooms: Int = 0
	var chambers: Int = 0
	var winzes: Int = 0
	var deadEnds: Int = 0
	/// where the great chamber is, if there is one (its centre column and floor row)
	var chamberX: Int = 0
	var chamberFloor: Int = 0
}

/// One gallery as laid out: where it starts, which way it runs and its floor row at each column
struct MineRun {
	var startX: Int
	var dir: Int
	var floors: [Int]
	var depth: Int
	func x(_ k: Int) -> Int { return startX + dir * k }
}

/// Builds a plan. Everything is drawn from the site's own seeded generator, so the same world seed
/// always gives the same mine. Side workings are tried one at a time and kept only if the space they
/// would open does not run into space already opened (apart from where they are meant to join),
/// so no drift ever cuts across a gallery or lays its floor in someone else's way.
struct MinePlanner {
	var plan: MinePlan = MinePlan()
	var rng: RNG
	let shaftX: Int
	let ground: Int
	/// every open cell so far, for the overlap test
	var open: Set<Int> = []

	init(seed: UInt64, shaftX: Int, ground: Int) {
		rng = RNG(seed)
		self.shaftX = shaftX
		self.ground = ground
		plan.minX = shaftX - 3
		plan.maxX = shaftX + 5
	}

	@inline(__always) static func key(_ x: Int, _ y: Int) -> Int { return x &* 4096 &+ y }

	mutating func chance(_ p: Double) -> Bool { return rng.double() < p }
	mutating func range(_ lo: Int, _ hi: Int) -> Int { return lo + rng.int(max(1, hi - lo + 1)) }

	mutating func carve(_ x: Int, _ y0: Int, _ y1: Int) {
		if y1 < y0 { return }
		plan.carve.append(MineSpan(x: x, y0: y0, y1: y1))
		plan.minX = min(plan.minX, x - 1)
		plan.maxX = max(plan.maxX, x + 1)
		plan.maxY = max(plan.maxY, y1 + 1)
	}

	mutating func tile(_ x: Int, _ y: Int, _ t: Tile) { plan.tiles.append(MineTile(x: x, y: y, t: t)) }
	mutating func floor(_ x: Int, _ y: Int) { plan.floors.append(MineTile(x: x, y: y, t: .planks)) }
	mutating func wall(_ x: Int, _ y0: Int, _ y1: Int) { plan.walls.append(MineWall(x: x, y0: y0, y1: y1)) }
	mutating func ore(_ x: Int, _ y: Int, _ t: Tile) { plan.ores.append(MineTile(x: x, y: y, t: t)) }

	/// chests go in last, each on sound floor (see buildMinePlan)
	mutating func chest(_ x: Int, _ y: Int, _ spot: MineSpot, _ depth: Int) {
		if plan.chests.contains(where: { abs($0.x - x) <= 1 && $0.y == y }) { return }
		plan.chests.append(MineChest(x: x, y: y, spot: spot, depth: depth))
	}

	/// marks everything carved since `from` as open
	mutating func commit(_ from: Int) {
		var i: Int = from
		while i < plan.carve.count {
			let sp: MineSpan = plan.carve[i]
			for y in sp.y0...sp.y1 { open.insert(MinePlanner.key(sp.x, y)) }
			i += 1
		}
	}

	/// Lays out a side working with `body`; keeps it only if what it carves (and the floor and fittings
	/// it lays) stays clear of space opened before, except inside the joint (`jx0...jx1` x `jy0...jy1`)
	@discardableResult
	mutating func attempt(_ jx0: Int, _ jx1: Int, _ jy0: Int, _ jy1: Int, _ body: (inout MinePlanner) -> Void) -> Bool {
		let snap: MinePlan = plan
		let c0: Int = plan.carve.count
		let f0: Int = plan.floors.count
		let t0: Int = plan.tiles.count
		body(&self)
		func clash(_ x: Int, _ y: Int) -> Bool {
			if x >= jx0 && x <= jx1 && y >= jy0 && y <= jy1 { return false }
			return open.contains(MinePlanner.key(x, y))
		}
		var bad: Bool = false
		var i: Int = c0
		while i < plan.carve.count && !bad {
			let sp: MineSpan = plan.carve[i]
			for y in (sp.y0 - 1)...(sp.y1 + 1) where clash(sp.x, y) || clash(sp.x - 1, y) || clash(sp.x + 1, y) { bad = true; break }
			i += 1
		}
		// a floor plank or a fitting laid inside space that is already open would be in the way
		var j: Int = f0
		while j < plan.floors.count && !bad { if clash(plan.floors[j].x, plan.floors[j].y) { bad = true }; j += 1 }
		var k: Int = t0
		while k < plan.tiles.count && !bad { if clash(plan.tiles[k].x, plan.tiles[k].y) { bad = true }; k += 1 }
		if bad {
			plan = snap
			return false
		}
		commit(c0)
		return true
	}

	/// The ore that shows in a mine's rock face at row y, following the same depth bands as the ore in
	/// the open ground: coal, copper, tin and saltpeter up top, iron and silver from the middle depths,
	/// gold only deep down, and a little amethyst in between
	mutating func oreFor(_ y: Int) -> Tile {
		let r: Double = rng.double()
		if y < 205 { return r < 0.45 ? .coal : (r < 0.75 ? .copper : (r < 0.92 ? .tin : .saltpeter)) }
		if y < 300 { return r < 0.22 ? .coal : (r < 0.38 ? .copper : (r < 0.5 ? .tin : (r < 0.8 ? .iron : (r < 0.95 ? .silver : .amethyst)))) }
		return r < 0.15 ? .coal : (r < 0.55 ? .iron : (r < 0.8 ? .silver : .gold))
	}

	/// A run of gallery from x0 out to x1 (either way) whose floor drifts up and down a row at a
	/// time, with timber sets, torches, rails, cobwebs and ore along it
	mutating func gallery(from x0: Int, to x1: Int, floor f0: Int, depth: Int, rails: Bool, lit: Double) -> MineRun {
		let dir: Int = x1 >= x0 ? 1 : -1
		let n: Int = abs(x1 - x0) + 1
		var floors: [Int] = []
		var f: Int = f0
		var nextStep: Int = range(7, 15)
		let support: Int = range(5, 7)
		let torchGap: Int = range(10, 15)
		var lastTorch: Int = -range(2, 6)
		var k: Int = 0
		while k < n {
			let x: Int = x0 + dir * k
			// the floor drifts a row now and then, never far from the level's own height
			if k == nextStep && k > 3 && k < n - 3 {
				let d: Int = chance(0.5) ? 1 : -1
				if abs(f + d - f0) <= 3 { f += d }
				nextStep = k + range(7, 15)
			}
			floors.append(f)
			let tall: Bool = k > 0 && floors[k - 1] != f
			carve(x, f - (tall ? 4 : 3), f - 1)
			floor(x, f)
			var torch: Bool = false
			if k % support == support / 2 && k > 1 {
				// a timber set: posts behind, a beam overhead (a few have rotted away)
				if chance(0.85) {
					wall(x, f - 3, f - 1)
					tile(x, f - 4 - (tall ? 1 : 0), .planks)
				} else {
					wall(x, f - 2, f - 1)
				}
			} else if k - lastTorch >= torchGap && chance(lit) {
				tile(x, f - 1, .torch)
				lastTorch = k
				torch = true
			} else if chance(0.05 + 0.03 * Double(depth)) {
				tile(x, f - 3, .cobweb)
			}
			if rails && !torch && k > 2 && !tall && chance(0.92) { tile(x, f - 1, .rail) }
			// ore showing in the roof and floor
			if chance(0.085) { ore(x, chance(0.55) ? f - 4 - (tall ? 1 : 0) : f, oreFor(f)) }
			k += 1
		}
		plan.tunnels += 1
		return MineRun(startX: x0, dir: dir, floors: floors, depth: depth)
	}

	/// A storage room above the gallery, reached by a short ladder through its roof
	mutating func storageRoom(_ x: Int, _ f: Int, _ depth: Int) {
		let w: Int = range(6, 9)
		let x0: Int = x - w / 2
		let x1: Int = x0 + w - 1
		let rf: Int = f - 5
		let h: Int = 4
		for xx in x0...x1 {
			carve(xx, rf - h, rf - 1)
			floor(xx, rf)
			wall(xx, rf - h, rf - 1)
		}
		// the hatch: a ladder from the gallery up through the room's floor
		carve(x, rf, f - 4)
		for y in rf...(f - 1) { tile(x, y, .ladder) }
		// crates stacked along the walls, a lantern, and the chest in a corner
		let crateLeft: Bool = chance(0.5)
		let cx: Int = crateLeft ? x0 : x1
		tile(cx, rf - 1, .crate)
		if chance(0.6) { tile(cx, rf - 2, .crate) }
		let other: Int = crateLeft ? x1 : x0
		tile(other, rf - 1, .crate)
		tile(x, rf - h, .lantern)
		chest(crateLeft ? x0 + 1 : x1 - 1, rf - 1, .room, depth)
		plan.rooms += 1
	}

	/// An abandoned work area: the gallery opens up, a workbench and furnace stand cold, a cart sits
	/// off its rails; sometimes a chest of the crew's things
	mutating func workArea(_ run: MineRun, _ k0: Int, _ w: Int) {
		let f: Int = run.floors[k0]
		for j in 0..<w {
			let xx: Int = run.x(k0 + j)
			carve(xx, f - 5, f - 4)
			wall(xx, f - 5, f - 1)
		}
		tile(run.x(k0 + 1), f - 1, .workbench)
		tile(run.x(k0 + 2), f - 1, .furnace)
		tile(run.x(k0 + w - 2), f - 1, .oreCart)
		tile(run.x(k0 + w / 2), f - 5, .lantern)
		if chance(0.5) { chest(run.x(k0 + w - 3), f - 1, .room, run.depth) }
		plan.rooms += 1
	}

	/// A ladder down from the gallery to a short drift that runs off one way and ends blind
	mutating func winze(_ x: Int, _ f: Int, _ depth: Int, _ drop: Int) {
		let bottom: Int = f + drop
		carve(x, f, bottom - 1)
		for y in f...(bottom - 1) { tile(x, y, .ladder) }
		let dir: Int = chance(0.5) ? 1 : -1
		let len: Int = range(12, 24)
		let run: MineRun = gallery(from: x, to: x + dir * len, floor: bottom, depth: depth + 1, rails: false, lit: 0.3)
		plan.winzes += 1
		deadEnd(run.x(len), run.floors.last ?? bottom, dir, depth + 1)
	}

	/// A ladder up through the gallery roof to a short drift above it that ends blind
	mutating func raise(_ x: Int, _ f: Int, _ depth: Int, _ rise: Int) {
		let top: Int = f - rise
		carve(x, top - 3, f - 4)
		for y in (top - 1)...(f - 1) { tile(x, y, .ladder) }
		let dir: Int = chance(0.5) ? 1 : -1
		let len: Int = range(10, 20)
		let run: MineRun = gallery(from: x + dir, to: x + dir * len, floor: top, depth: depth, rails: false, lit: 0.3)
		plan.winzes += 1
		deadEnd(run.x(len - 1), run.floors.last ?? top, dir, depth)
	}

	/// A sloping drift carried on past the end of a gallery, climbing or falling a row every two
	/// columns, to a dead end
	mutating func ramp(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		let rise: Int = chance(0.5) ? -1 : 1
		let rows: Int = range(4, 7)
		var ff: Int = f
		for k in 0..<(rows * 2) {
			if k % 2 == 1 { ff += rise }
			let xx: Int = x + dir * k
			carve(xx, ff - 3 - (k % 2 == 1 ? 1 : 0), ff - 1)
			floor(xx, ff)
		}
		let x1: Int = x + dir * (rows * 2)
		let len: Int = range(5, 12)
		let run: MineRun = gallery(from: x1, to: x1 + dir * len, floor: ff, depth: depth, rails: false, lit: 0.2)
		deadEnd(run.x(len), run.floors.last ?? ff, dir, depth)
	}

	/// The blind end of a drift at x: bare rock and a cart, or a chest left behind, or a fall of rock
	/// that hides a little pocket with a chest in it (dig through to find it)
	mutating func deadEnd(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		plan.deadEnds += 1
		let r: Double = rng.double()
		if r < 0.3 {
			chest(x - dir, f - 1, .room, depth)
		} else if r < 0.55 {
			attempt(x, x, f - 4, f) { p in p.collapse(x, f, dir, depth) }
		} else if r < 0.75 {
			tile(x - dir, f - 1, .oreCart)
		}
		// otherwise just the rock face
	}

	/// rubble two or three blocks thick at the end of a drift, then the pocket beyond it
	mutating func collapse(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		let thick: Int = range(2, 3)
		for j in 1...thick {
			let xx: Int = x + dir * j
			carve(xx, f - 3, f - 1)
			for y in (f - 3)...(f - 1) { tile(xx, y, rubble()) }
			floor(xx, f)
		}
		let p0: Int = x + dir * (thick + 1)
		for j in 0..<4 {
			carve(p0 + dir * j, f - 3, f - 1)
			floor(p0 + dir * j, f)
		}
		chest(p0 + dir * 3, f - 1, .hidden, depth)
		tile(p0 + dir * 1, f - 3, .cobweb)
	}

	/// what a collapse is made of: broken stone, earth and rotten timber
	mutating func rubble() -> Tile {
		let r: Double = rng.double()
		return r < 0.45 ? .stone : (r < 0.8 ? .dirt : .planks)
	}

	/// The great chamber on the lowest level: a tall hall over the gallery shored up with timber, a
	/// scaffold half-way up with a chest on it, ore-rich walls, and a nook high in the roof with
	/// something tucked away (only reached by building up to it)
	mutating func chamber(_ run: MineRun, _ kc: Int, _ hw: Int) {
		let f: Int = run.floors[kc]
		let cx: Int = run.x(kc)
		let h: Int = range(9, 12)
		for dx in -hw...hw {
			let x: Int = cx + dx
			let u: Double = Double(dx) / Double(hw)
			let top: Int = f - 3 - Int((Double(h - 3) * (1.0 - u * u)).rounded())
			carve(x, top, f - 4)
			if abs(dx) % 7 == 3 && abs(dx) < hw - 1 { wall(x, top, f - 1) }
			if chance(0.3) { ore(x, top - 1, oreFor(top)) }
		}
		for y in (f - 6)...(f - 1) where chance(0.4) {
			ore(cx - hw - 1, y, oreFor(y))
			ore(cx + hw + 1, y, oreFor(y))
		}
		// the scaffold: a walkway half-way up with a ladder at one end
		let sy: Int = f - 5
		let s0: Int = cx - hw / 2
		let s1: Int = cx + hw / 2
		for x in s0...s1 { tile(x, sy, .platform) }
		for y in sy...(f - 1) { tile(s0, y, .ladder) }
		chest(s1 - 1, sy - 1, .room, run.depth + 1)
		tile(cx, f - h + 1, .lantern)
		// the nook: a hollow just above the roof's high point
		if chance(0.6) {
			let ny: Int = f - h - 1
			carve(cx + 2, ny - 1, ny)
			carve(cx + 3, ny - 1, ny)
			floor(cx + 3, ny + 1)
			chest(cx + 3, ny, .hidden, run.depth + 1)
		}
		plan.chambers += 1
		plan.chamberX = cx
		plan.chamberFloor = f
	}
}

extension WorldGen {
	/// Lays out a version-4 mine at `x` (left column of the three-wide shaft) on ground row `ground`
	func planMine(cell c: Int, x: Int, ground: Int) -> (MinePlan, [Int], [Int], [Int]) {
		var p = MinePlanner(seed: hashU(c, 700, seed), shaftX: x, ground: ground)
		let depth: Int = 60 + p.rng.int(100)
		let nLevels: Int = depth > 135 ? 4 : (depth > 95 ? 3 : 2)
		var levels: [Int] = []
		for k in 0..<nLevels {
			var f: Int = ground + depth * (k + 1) / nLevels
			if k < nLevels - 1 { f += p.range(-3, 3) }
			levels.append(f)
		}
		let bottom: Int = levels.last ?? (ground + depth)
		// the shaft: three wide, a ladder up the middle, covered over at the top
		for xx in x...(x + 2) {
			p.carve(xx, ground + 1, bottom - 1)
			p.wall(xx, ground + 1, bottom - 1)
		}
		for y in (ground + 1)...(bottom - 1) { p.tile(x + 1, y, .ladder) }
		for xx in x...(x + 2) { p.floor(xx, bottom) }
		// first every level's landing and its two galleries
		var lefts: [Int] = []
		var rights: [Int] = []
		var runs: [(MineRun, MineRun)] = []
		for (i, f) in levels.enumerated() {
			let left: Int = p.range(24, 64)
			let right: Int = p.range(24, 64)
			lefts.append(left)
			rights.append(right)
			let rails: Bool = i < 2 && p.chance(0.7)
			let lit: Double = max(0.25, 0.9 - 0.2 * Double(i))
			for xx in x...(x + 2) { p.carve(xx, f - 3, f - 1) }
			if f != bottom {
				p.tile(x, f, .platform)
				p.tile(x + 2, f, .platform)
			}
			let l: MineRun = p.gallery(from: x - 1, to: x - left, floor: f, depth: i, rails: rails, lit: lit)
			let r: MineRun = p.gallery(from: x + 3, to: x + 2 + right, floor: f, depth: i, rails: rails, lit: lit)
			runs.append((l, r))
		}
		p.commit(0)
		// the great chamber, on the lowest level, along its longer gallery
		if p.chance(0.66), let last = runs.last {
			let run: MineRun = last.0.floors.count >= last.1.floors.count ? last.0 : last.1
			if run.floors.count >= 30 {
				let hw: Int = p.range(9, min(13, (run.floors.count - 10) / 2))
				let kc: Int = p.range(hw + 4, run.floors.count - hw - 4)
				let cx: Int = run.x(kc)
				// the hall opens round its own gallery, whose floor wanders a few rows: all of that is the joint
				p.attempt(cx - hw - 2, cx + hw + 2, run.floors[kc] - 8, run.floors[kc] + 4) { q in q.chamber(run, kc, hw) }
			}
		}
		// then the side workings along each gallery, each kept only if it fits
		for (i, pair) in runs.enumerated() {
			for run in [pair.0, pair.1] {
				let n: Int = run.floors.count
				var k: Int = p.range(8, 13)
				while k < n - 6 {
					let gx: Int = run.x(k)
					let gf: Int = run.floors[k]
					let r: Double = p.rng.double()
					var used: Int = 0
					if r < 0.24 {
						if p.attempt(gx - 1, gx + 1, gf - 6, gf) { q in q.storageRoom(gx, gf, i) } { used = 10 }
					} else if r < 0.42 {
						let drop: Int = p.range(8, 13)
						if p.attempt(gx - 1, gx + 1, gf - 4, gf + 1) { q in q.winze(gx, gf, i, drop) } { used = 9 }
					} else if r < 0.56 {
						let rise: Int = p.range(7, 10)
						if p.attempt(gx - 1, gx + 1, gf - 5, gf) { q in q.raise(gx, gf, i, rise) } { used = 9 }
					} else if r < 0.7 {
						let w: Int = p.range(6, 8)
						if k + w < n - 2 && (0..<w).allSatisfy({ run.floors[k + $0] == gf }) {
							let xa: Int = min(run.x(k), run.x(k + w - 1))
							let xb: Int = max(run.x(k), run.x(k + w - 1))
							if p.attempt(xa - 1, xb + 1, gf - 4, gf) { q in q.workArea(run, k, w) } { used = w + 2 }
						}
					}
					k += max(used, p.range(5, 9)) + p.range(3, 7)
				}
				// the far end: a slope carried on to a dead end, or the dead end itself
				let endX: Int = run.x(n - 1)
				let endF: Int = run.floors.last ?? levels[i]
				if p.chance(0.4) {
					let ja: Int = min(endX, endX + run.dir)
					let jb: Int = max(endX, endX + run.dir)
					if !p.attempt(ja, jb, endF - 4, endF + 1, { q in q.ramp(endX + run.dir, endF, run.dir, i) }) {
						p.deadEnd(endX, endF, run.dir, i)
					}
				} else {
					p.deadEnd(endX, endF, run.dir, i)
				}
			}
		}
		return (p.plan, levels, lefts, rights)
	}
}

/// Builds the part of a version-4 mine that falls in this chunk: carve, seal any water or lava that
/// would pour in, make the floors sound, timber behind, fittings, ore in the rock face, then chests
func buildMinePlan(_ g: WorldGen, _ ch: Chunk, _ s: MineSite, _ plan: MinePlan) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	@inline(__always) func inside(_ x: Int) -> Bool { return x >= cx0 && x <= cx1 }
	for sp in plan.carve where sp.x >= cx0 - 1 && sp.x <= cx1 + 1 {
		if inside(sp.x) { for y in sp.y0...sp.y1 { ch.put(sp.x, y, .air) } }
	}
	for sp in plan.carve where sp.x >= cx0 - 1 && sp.x <= cx1 + 1 {
		for y in sp.y0...sp.y1 {
			if ch.at(sp.x - 1, y).liquid { ch.put(sp.x - 1, y, .stone) }
			if ch.at(sp.x + 1, y).liquid { ch.put(sp.x + 1, y, .stone) }
		}
		if ch.at(sp.x, sp.y0 - 1).liquid { ch.put(sp.x, sp.y0 - 1, .stone) }
		if ch.at(sp.x, sp.y1 + 1).liquid { ch.put(sp.x, sp.y1 + 1, .stone) }
	}
	for f in plan.floors where inside(f.x) {
		let t: Tile = ch.at(f.x, f.y)
		if !t.solid || t.liquid { ch.put(f.x, f.y, f.t) }
	}
	let plankWall: UInt8 = 5
	for w in plan.walls where inside(w.x) { ch.fillWall(w.x, w.y0, w.x, w.y1, plankWall) }
	for t in plan.tiles where inside(t.x) { ch.put(t.x, t.y, t.t) }
	for o in plan.ores where inside(o.x) {
		let t: Tile = ch.at(o.x, o.y)
		if t == .stone || t == .slate || t == .deepRock || t == .sandstone { ch.put(o.x, o.y, o.t) }
	}
	for c in plan.chests where inside(c.x) {
		let below: Tile = ch.at(c.x, c.y + 1)
		if !(below.solid || below == .platform) || below.liquid { ch.put(c.x, c.y + 1, .planks) }
		ch.put(c.x, c.y, .chest)
	}
}

/// The small set pieces scattered over the land
enum Landmark {
	case boulder, mossyBoulder, snowBoulder, fallenLog, fallenJungleLog, mossyLog, meadow, mushroomRing
	case bones, sandstoneRuin, iceSpikes, cairn, termiteMound, reeds

	var halfWidth: Int {
		switch self {
		case .boulder, .mossyBoulder, .snowBoulder, .termiteMound: return 2
		case .fallenLog, .fallenJungleLog, .mossyLog, .bones, .sandstoneRuin, .reeds: return 4
		case .meadow: return 6
		case .mushroomRing, .iceSpikes: return 3
		case .cairn: return 1
		}
	}

	static func pick(_ b: Biome, _ r: Double) -> Landmark? {
		switch b {
		case .plains: return r < 0.4 ? .boulder : (r < 0.75 ? .meadow : .fallenLog)
		case .forest: return r < 0.45 ? .fallenLog : (r < 0.7 ? .mossyBoulder : .mushroomRing)
		case .jungle: return r < 0.5 ? .fallenJungleLog : .meadow
		case .savanna: return r < 0.45 ? .boulder : (r < 0.75 ? .bones : .termiteMound)
		case .desert: return r < 0.55 ? .bones : .sandstoneRuin
		case .tundra: return r < 0.6 ? .iceSpikes : .snowBoulder
		case .swamp: return r < 0.55 ? .mossyLog : .reeds
		case .mountain: return r < 0.65 ? .boulder : .cairn
		case .ocean, .umbral: return nil
		}
	}
}

/// One landmark (or none) per 72 columns, picked by biome. Each is at most three blocks tall, so it
/// can always be walked or hopped over, and each only goes on level, dry ground away from buildings.
func placeLandmarks(_ g: WorldGen, _ ch: Chunk, _ colAt: (Int) -> Col, _ blocked: (Int) -> Bool) {
	let x0: Int = ch.x0
	let cw: Int = WorldGen.landmarkCell
	for c in floorDiv(x0 - 8, cw)...floorDiv(x0 + chunkW + 8, cw) {
		if hash2(c, 701, g.seed) > 0.5 { continue }
		let lx: Int = c * cw + 8 + Int(hash2(c, 702, g.seed) * Double(cw - 16))
		if lx + 6 < x0 || lx - 6 >= x0 + chunkW { continue }
		if !g.infinite && (lx < 24 || lx > g.width - 24) { continue }
		if abs(lx - g.spawnX) < 14 { continue }
		let base: Col = colAt(lx)
		guard let kind = Landmark.pick(base.biome, hash2(c, 703, g.seed)) else { continue }
		let hw: Int = kind.halfWidth
		var ok: Bool = true
		for d in -hw...hw {
			let cc: Col = colAt(lx + d)
			if cc.biome == .ocean || cc.h >= WorldGen.sea - 1 || abs(cc.h - base.h) > 1 || blocked(lx + d) { ok = false; break }
		}
		if !ok { continue }
		let seed: UInt64 = hashU(c, 704, g.seed)
		// writes over air and small plants only, so trunks and buildings stay as they are
		func place(_ d: Int, _ up: Int, _ t: Tile) {
			let x: Int = lx + d
			let y: Int = colAt(x).h - up
			let cur: Tile = ch.at(x, y)
			if cur == .air || (cur.isPlant && cur != .torch && cur != .lantern) { ch.put(x, y, t) }
		}
		func plant(_ d: Int, _ t: Tile) {
			let x: Int = lx + d
			let h: Int = colAt(x).h
			if x < x0 || x >= x0 + chunkW { return }
			if !ch.at(x, h).solid { return }
			if ch.at(x, h - 1) == .air || ch.at(x, h - 1) == .tallGrass { ch.put(x, h - 1, t) }
		}
		func rnd(_ k: Int) -> Double { return hash2(lx, k, seed) }
		switch kind {
		case .boulder, .mossyBoulder, .snowBoulder:
			let cap: Tile = kind == .mossyBoulder ? .mossGrass : (kind == .snowBoulder ? .snow : .stone)
			let wide: Bool = rnd(1) < 0.5
			for d in -2...2 {
				if abs(d) == 2 && !wide { continue }
				let hgt: Int = abs(d) == 2 || (abs(d) == 1 && !wide) ? 1 : 2
				for k in 1...hgt { place(d, k, k == hgt ? cap : .stone) }
			}
		case .fallenLog, .fallenJungleLog, .mossyLog:
			let len: Int = 4 + Int(rnd(1) * 4.0)
			let start: Int = -len / 2
			let wood: Tile = kind == .fallenJungleLog ? .jungleLogBlock : (rnd(3) < 0.35 && kind == .fallenLog ? .birchLogBlock : .logBlock)
			for d in start..<(start + len) { place(d, 1, wood) }
			if rnd(2) < 0.6 || kind == .mossyLog { place(start + 1, 2, .mushroom) }
			if kind == .mossyLog { place(start + len - 2, 2, .mushroom) }
			plant(start - 1, .tallGrass)
			plant(start + len, .tallGrass)
		case .meadow:
			for d in -6...6 {
				let r: Double = rnd(10 + d)
				plant(d, r < 0.36 ? .flowerR : (r < 0.72 ? .flowerY : .tallGrass))
			}
		case .mushroomRing:
			for d in [-3, -2, 2, 3] { plant(d, .mushroom) }
			plant(0, .tallGrass)
		case .bones:
			for d in -3...3 { place(d, 1, .fossil) }
			for d in [-2, 0, 2] { place(d, 2, .fossil) }
			place(4, 1, .fossil)
			place(4, 2, .fossil)
		case .sandstoneRuin:
			for d in [-3, 3] {
				place(d, 1, .sandstone)
				if rnd(d + 5) < 0.7 { place(d, 2, .sandstone) }
			}
			for d in -1...1 { place(d, 1, .sandstone) }
			if rnd(4) < 0.3 { place(0, 2, .chest) }
		case .iceSpikes:
			for (d, hgt) in [(-2, 2), (0, 3), (2, 2)] where rnd(d + 7) < 0.85 || d == 0 {
				for k in 1...hgt { place(d, k, .ice) }
			}
		case .cairn:
			for k in 1...3 { place(0, k, .stone) }
			place(0, 4, .torch)
			place(-1, 1, .stone)
			place(1, 1, .stone)
		case .termiteMound:
			for (d, hgt) in [(-2, 1), (-1, 2), (0, 3), (1, 2), (2, 1)] {
				for k in 1...hgt { place(d, k, .dirt) }
			}
		case .reeds:
			for d in -4...4 where rnd(20 + d) < 0.7 { plant(d, .reed) }
		}
	}
}

// ===== p09_umbral =====

// MARK: - Umbral Realm (second dimension)

let umbralH: Int = 320
let umbralLava: Int = 240

extension WorldGen {
	func uCeil(_ x: Int) -> Int {
		return 12 + Int(fbm1(Double(x) / 55.0, seed &+ 501, 3) * 30.0)
	}

	func uFloorRaw(_ x: Int) -> Int {
		return 176 + Int(fbm1(Double(x) / 75.0, seed &+ 502, 3) * 86.0)
	}

	/// floor level of the portal platform
	var umbralPortalFloor: Int {
		return clampI(uFloorRaw(portalX), 192, 226)
	}

	func uFloor(_ x: Int) -> Int {
		var raw: Int = uFloorRaw(x)
		if let c = citadel {
			// the citadel stands on level ground, with long ramps down (or up) to the cavern floor
			let dc: Int = abs(x - c.x)
			if dc <= 110 {
				let t: Double = smooth(clampD(Double(dc - 50) / 60.0, 0, 1))
				raw = Int(lerpD(Double(c.floor), Double(raw), t).rounded())
			}
		}
		let d: Int = abs(x - portalX)
		if d > 44 { return raw }
		let t: Double = smooth(clampD((Double(d) - 16.0) / 28.0, 0, 1))
		return Int(lerpD(Double(umbralPortalFloor), Double(raw), t).rounded())
	}

	/// The Hollow Warden's citadel (worlds of generator version 3): some 380 to 540 blocks from the
	/// rift, its gate facing back toward it
	var citadel: CitadelSite? {
		if let c = cache.citadel { return c }
		let c: CitadelSite? = computeCitadel()
		cache.citadel = .some(c)
		return c
	}

	func computeCitadel() -> CitadelSite? {
		if genVersion < 3 { return nil }
		let side: Int = hash2(77, 78, seed) < 0.5 ? -1 : 1
		let dist: Int = 380 + Int(hash2(79, 80, seed) * 160.0)
		var x: Int = portalX + side * dist
		if !infinite && (x < 200 || x > width - 200) { x = portalX - side * dist }
		if !infinite && (x < 200 || x > width - 200) { return nil }
		let floor: Int = clampI(uFloorRaw(x), 190, 226)
		return CitadelSite(x: x, floor: floor, gate: portalX >= x ? 1 : -1)
	}

	func uRuinSite(cell c: Int) -> Int? {
		if hash2(c, 511, seed) > 0.55 { return nil }
		if let cd = citadel, abs(c * 260 + 140 - cd.x) < 200 { return nil }
		let sx: Int = c * 260 + 40 + Int(hash2(c, 512, seed) * 180.0)
		if abs(sx - portalX) < 60 { return nil }
		if !infinite && (sx < 40 || sx > width - 40) { return nil }
		return sx
	}
}

func generateUmbralChunk(_ g: WorldGen, _ cx: Int) -> Chunk {
	let H: Int = umbralH
	let ch = Chunk(cx: cx, H: H)
	ch.hasSky = false
	let x0: Int = cx * chunkW
	for lx in 0..<chunkW {
		let x: Int = x0 + lx
		let base: Int = lx * H
		if !g.infinite && (x < 0 || x >= g.width) {
			for y in 0..<H { ch.tiles[base + y] = Tile.bedrock.rawValue }
			continue
		}
		let ceil: Int = g.uCeil(x)
		let floorY: Int = g.uFloor(x)
		ch.surf[lx] = floorY
		ch.ceilY[lx] = ceil
		for y in 0..<H {
			var t: Tile = .air
			if y <= 2 || y >= H - 3 { t = .bedrock }
			else if y < ceil { t = .ashStone }
			else if y >= floorY {
				let depth: Int = y - floorY
				t = .ashStone
				if depth >= 5 && g.isCave(x, y, depth) {
					t = y >= umbralLava - 10 ? .lava : .air
				} else if depth >= 3 {
					let ev: Double = vnoise(Double(x) * 0.2, Double(y) * 0.2, g.seed &+ 521)
					let vv: Double = vnoise(Double(x) * 0.2, Double(y) * 0.2, g.seed &+ 522)
					let ob: Double = vnoise(Double(x) * 0.12, Double(y) * 0.12, g.seed &+ 523)
					if ev > 0.80 && hash2(x, y, g.seed &+ 524) < 0.7 { t = .emberOre }
					else if vv > 0.895 && y > 235 && hash2(x, y, g.seed &+ 525) < 0.7 { t = .voidOre }
					else if ob > 0.86 { t = .obsidian }
					else if depth > 30 && hash2(x, y / 4, g.seed &+ 526) < 0.02 { t = .deepRock }
				}
			} else {
				// open cavern: floating islands
				if y > ceil + 14 && y < floorY - 26 {
					let isle: Double = vnoise(Double(x) * 0.045, Double(y) * 0.085, g.seed &+ 531)
					let mid: Double = Double(ceil + floorY) * 0.5
					let pen: Double = abs(Double(y) - mid) * 0.0035
					if isle > 0.735 + pen { t = .ashStone }
				}
				if y >= umbralLava && t == .air { t = .lava }
			}
			ch.tiles[base + y] = t.rawValue
		}
		// stalactites hanging from the ceiling
		let sn: Double = hash2(x, 3, g.seed &+ 541)
		if sn < 0.16 {
			let len: Int = 1 + Int(hash2(x, 4, g.seed &+ 541) * 7.0)
			for k in 0..<len { ch.setLocal(lx, ceil + k, .ashStone) }
			if sn < 0.012 { ch.setLocal(lx, ceil + len, .glowCrystal) }
		}
		// surface decoration: crystals, spikes
		if floorY > 3 && floorY < H - 6 {
			let above: Tile = ch.get(lx, floorY - 1)
			if above == .air {
				let r: Double = hash2(x, 5, g.seed &+ 551)
				if r < 0.03 { ch.setLocal(lx, floorY - 1, .glowCrystal) }
				else if r < 0.08 && abs(x - g.portalX) > 20 { ch.setLocal(lx, floorY - 1, .spikes) }
				else if r < 0.11 { ch.setLocal(lx, floorY - 1, .mushroom) }
			}
		}
	}
	for c in (floorDiv(x0 - 40, 260))...(floorDiv(x0 + chunkW + 40, 260)) {
		if let sx = g.uRuinSite(cell: c) { buildUmbralRuin(g, ch, sx, hashU(c, 513, g.seed)) }
	}
	if abs(g.portalX - (x0 + chunkW / 2)) < 30 { buildUmbralPortal(g, ch) }
	if let c = g.citadel, abs(c.x - (x0 + chunkW / 2)) < 60 { buildCitadel(g, ch, c) }
	if ModRuntime.shared.hasWorldGen { applyModGen(g, ch, .umbral) }
	ch.rebuildSky()
	return ch
}

/// Where the Hollow Warden keeps its hall
struct CitadelSite {
	var x: Int
	var floor: Int
	/// the side the gate faces (toward the rift); the throne stands at the far end
	var gate: Int
	var throneX: Int { return x - gate * 33 }
	var chestX: Int { return x - gate * 37 }
}

/// A ruined hall: a paved floor between two gate towers, ash-stone walls behind, broken arches above,
/// lanterns on plinths, a throne on a low dais and the Warden's hoard behind it. Both towers have
/// doorways, so the hall can always be walked through.
func buildCitadel(_ g: WorldGen, _ ch: Chunk, _ c: CitadelSite) {
	let f: Int = c.floor
	let seed: UInt64 = g.seed &+ 9191
	for x in (c.x - 50)...(c.x + 50) {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let dx: Int = x - c.x
		ch.fill(x, f - 22, x, f - 1, .air)
		ch.fill(x, f + 1, x, f + 3, .obsidian)
		ch.put(x, f, abs(dx) % 6 == 0 ? .crackedBrick : .brick)
		if abs(dx) <= 40 { ch.fillWall(x, f - 14, x, f - 1, 4) }
		if abs(dx) == 12 || abs(dx) == 26 { ch.fillWall(x, f - 14, x, f - 1, 6) }
		// gate towers with doorways
		if abs(dx) == 41 || abs(dx) == 42 {
			ch.fill(x, f - 15, x, f - 6, .brick)
			if hash2(x, 3, seed) < 0.3 { ch.put(x, f - 10, .crackedBrick) }
		}
		// the broken arches overhead
		if abs(dx) <= 42 && hash2(x, 4, seed) > 0.2 {
			ch.put(x, f - 16, hash2(x, 5, seed) < 0.25 ? .crackedBrick : .brick)
			if abs(dx) % 9 == 4 { ch.put(x, f - 15, .glowCrystal) }
		}
		// lanterns on plinths
		if abs(dx) == 6 || abs(dx) == 19 || abs(dx) == 33 {
			if x != c.throneX && x != c.chestX {
				ch.put(x, f - 1, .brick)
				ch.put(x, f - 2, .lantern)
			}
		}
	}
	// the throne on its dais, the hoard behind it
	for dx in -3...3 { ch.put(c.throneX + dx, f - 1, .brick) }
	ch.fill(c.throneX - c.gate, f - 4, c.throneX - c.gate, f - 2, .obsidian)
	ch.put(c.throneX + 1, f - 2, .crackedBrick)
	ch.put(c.throneX - 1, f - 2, .crackedBrick)
	ch.put(c.chestX, f - 1, .chest)
}

func buildUmbralRuin(_ g: WorldGen, _ ch: Chunk, _ sx: Int, _ seed: UInt64) {
	let gy: Int = g.uFloor(sx)
	let w: Int = 15
	let x: Int = sx - w / 2
	// level the site
	for xx in (x - 3)...(x + w + 2) {
		if xx < ch.x0 || xx >= ch.x0 + chunkW { continue }
		let f: Int = g.uFloor(xx)
		if f > gy { ch.fill(xx, gy, xx, f, .ashStone) }
		ch.fill(xx, gy - 10, xx, gy - 1, .air)
		ch.put(xx, gy, .ashStone)
	}
	ch.fill(x, gy - 7, x + w - 1, gy - 1, .brick)
	ch.fill(x + 1, gy - 6, x + w - 2, gy - 2, .air)
	ch.fill(x, gy - 1, x + w - 1, gy - 1, .brick)
	ch.fill(x + 1, gy - 1, x + w - 2, gy - 1, .air)
	// doorway and roof gap
	ch.fill(x, gy - 3, x, gy - 2, .air)
	ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 2, .air)
	for k in 0..<5 { if hash2(k, 1, seed) < 0.6 { ch.put(x + 3 + k * 2, gy - 7, .air) } }
	// contents
	ch.put(x + 2, gy - 2, .torch)
	ch.put(x + w - 3, gy - 2, .torch)
	ch.put(x + w / 2, gy - 2, .chest)
	ch.put(x + w / 2 - 3, gy - 2, .spikes)
	ch.put(x + w / 2 + 3, gy - 2, .spikes)
	if hash2(1, 2, seed) < 0.6 { ch.put(x + w / 2 + 5, gy - 2, .chest) }
	ch.put(x + 1, gy - 5, .glowCrystal)
	// crumble
	for xx in x...(x + w - 1) {
		for yy in (gy - 7)...(gy - 2) {
			if ch.at(xx, yy) == .brick && hash2(xx, yy, seed) < 0.12 { ch.put(xx, yy, .crackedBrick) }
		}
	}
}

/// The rift (world version 2+): an oval tear standing on a low basalt plinth, held by two floating
/// anchor crescents and a keystone. Open at the sides, so it is walked into rather than climbed into.
/// The oval occupies the same 5x7 footprint as the old frame's interior, so its centre is unchanged.
func buildRift(_ ch: Chunk, _ px: Int, _ base: Int, _ fill: Tile) {
	riftShape(px, base, fill) { x, y, t in ch.put(x, y, t) }
}

func riftShape(_ px: Int, _ base: Int, _ fill: Tile, _ put: (Int, Int, Tile) -> Void) {
	for dx in -3...3 { put(px + dx, base, .portalFrame) }
	for dy in -7...(-1) {
		for dx in -2...2 {
			let ey: Double = (Double(dy) + 4.0) / 3.6
			let ex: Double = Double(dx) / 2.6
			put(px + dx, base + dy, ex * ex + ey * ey <= 1.0 ? fill : .air)
		}
	}
	for side in [-3, 3] {
		put(px + side, base - 6, .portalFrame)
		put(px + side, base - 5, .portalFrame)
		put(px + side, base - 4, .portalFrame)
	}
	put(px, base - 9, .portalFrame)
}

func buildUmbralPortal(_ g: WorldGen, _ ch: Chunk) {
	let px: Int = g.portalX
	let gy: Int = g.umbralPortalFloor
	ch.fill(px - 14, gy - 14, px + 14, gy - 1, .air)
	ch.fill(px - 14, gy, px + 14, gy + 3, .obsidian)
	for dx in -14...14 {
		if abs(dx) > 11 { ch.put(px + dx, gy, .ashStone) }
	}
	let fx: Int = px - 3
	let fyb: Int = gy - 1
	if g.genVersion >= 2 {
		buildRift(ch, px, fyb, .portalOn)
	} else {
		ch.fill(fx, fyb - 8, fx + 6, fyb - 8, .portalFrame)
		ch.fill(fx, fyb, fx + 6, fyb, .portalFrame)
		ch.fill(fx, fyb - 8, fx, fyb, .portalFrame)
		ch.fill(fx + 6, fyb - 8, fx + 6, fyb, .portalFrame)
		ch.fill(fx + 1, fyb - 7, fx + 5, fyb - 1, .portalOn)
	}
	// lights and a welcome chest
	ch.put(px - 9, gy - 1, .lantern)
	ch.put(px + 9, gy - 1, .lantern)
	ch.put(px - 12, gy - 1, .glowCrystal)
	ch.put(px + 12, gy - 1, .glowCrystal)
	ch.put(px + 7, gy - 1, .chest)
}

/// What the world's mods add to a freshly made chunk: veins of their ores (and their structures, see
/// applyModStructures). It all comes from the world seed and the chunk's place, so a chunk always comes
/// out the same; the work is done once, when the chunk is first made, never per frame.
func applyModGen(_ g: WorldGen, _ ch: Chunk, _ dim: Dimension) {
	let rt: ModRuntime = ModRuntime.shared
	let d: Int = dim.rawValue
	let H: Int = ch.H
	_ = H
	// each ore places itself (see ModOreRT.place: the original settings give the original veins)
	for o in rt.ores where o.dim == d { o.place(g, ch) }
	applyModStructures(g, ch, dim)
}

/// The ground a custom ore may take the place of: 0 any rock, 1 stone, 2 slate and deep rock,
/// 3 dirt and sand, 4 any natural ground
func modOreHost(_ t: Tile, _ host: Int) -> Bool {
	switch host {
	case 1: return t == .stone
	case 2: return t == .slate || t == .deepRock
	case 3: return t == .dirt || t == .sand || t == .mud
	case 4:
		switch t {
		case .stone, .slate, .deepRock, .ashStone, .sandstone, .dirt, .sand, .mud, .snow: return true
		default: return false
		}
	default:
		switch t {
		case .stone, .slate, .deepRock, .ashStone, .sandstone: return true
		default: return false
		}
	}
}

/// True where a custom structure must not go: the spawn point, the rift gate, and the world's own
/// villages, ruins, mines, lairs and landmarks, and (for one underground) the crystal grottos; on the
/// surface only a grotto's cave mouth matters (Umbral: the gate, the citadel and the ruins)
func modSiteBlocked(_ g: WorldGen, _ dim: Dimension, _ xa: Int, _ xb: Int, _ placement: ModPlacement = .surface) -> Bool {
	func hits(_ a: Int, _ b: Int) -> Bool { return xb > a && xa < b }
	if dim == .umbral {
		if hits(g.portalX - 40, g.portalX + 40) { return true }
		if let c = g.citadel, hits(c.x - 90, c.x + 90) { return true }
		for c in floorDiv(xa - 40, 260)...floorDiv(xb + 40, 260) {
			if let rx = g.uRuinSite(cell: c), hits(rx - 30, rx + 30) { return true }
		}
		return false
	}
	if hits(g.spawnX - 16, g.spawnX + 16) || hits(g.portalX - 50, g.portalX + 50) { return true }
	for v in g.villages(overlapping: xa - 20, xb + 20) where hits(v.x - v.halfW - 6, v.x + v.halfW + 6) { return true }
	for r in g.rareSites(overlapping: xa - 30, xb + 30) where hits(r.x - 16, r.x + 16) { return true }
	for mn in g.mineSites(overlapping: xa - 20, xb + 20) where hits(mn.x - 8, mn.x + 14) { return true }
	for s in g.grottoSites(overlapping: xa - 60, xb + 60) {
		if placement == .underground {
			let p0: Int = min(s.x - s.rx, s.passStartX + min(0, s.dir * s.passLen))
			let p1: Int = max(s.x + s.rx, s.passStartX + max(0, s.dir * s.passLen))
			if hits(p0 - 8, p1 + 8) { return true }
		} else if placement == .surface && s.open {
			let mouth: Int = s.passStartX + s.dir * s.passLen
			if hits(mouth - 16, mouth + 16) { return true }
		}
	}
	for L in g.lairCenters(near: (xa + xb) / 2) where hits(L.cx - 70, L.cx + 70) { return true }
	if placement != .underground {
		let cw: Int = WorldGen.landmarkCell
		for c in floorDiv(xa - 8, cw)...floorDiv(xb + 8, cw) {
			if hash2(c, 701, g.seed) > 0.5 { continue }
			let lx: Int = c * cw + 8 + Int(hash2(c, 702, g.seed) * Double(cw - 16))
			if hits(lx - 7, lx + 7) { return true }
		}
	}
	return false
}

/// A custom structure's site in one of its spacing cells: its left column and top row, or nil when the
/// cell holds none. It comes from the seed and the generator's own ground heights only, so every chunk
/// agrees on it, however the world is explored.
func modStructSite(_ g: WorldGen, _ s: ModStructRT, _ dim: Dimension, _ cell: Int) -> (Int, Int)? {
	let d: ModStructure = s.def
	let sp: Int = max(64, d.spacing)
	let key: UInt64 = g.seed &+ s.salt
	if hash2(cell, 1907, key) >= d.chance { return nil }
	let room: Int = max(1, sp - d.w - 16)
	let sx: Int = cell * sp + 8 + Int(hash2(cell, 1913, key) * Double(room))
	if !g.infinite && (sx < 24 || sx + d.w > g.width - 24) { return nil }
	if modSiteBlocked(g, dim, sx - 4, sx + d.w + 4, d.placement) { return nil }
	let mid: Int = sx + d.w / 2
	let pick: Double = hash2(cell, 1931, key)
	let H: Int = dimHeight(dim)
	var top: Int = 0
	if dim.isCustom {
		guard let cd = ModRuntime.shared.dimRT(dim) else { return nil }
		let surf: Int = cd.surfaceAt(mid, g.seed)
		if !d.biomes.isEmpty && !d.biomes.contains(cd.biomeAt(Double(mid)).rawValue) { return nil }
		switch d.placement {
		case .surface:
			if cd.def.sea > 0 && surf >= cd.def.sea - 1 { return nil }
			top = surf - d.h + 1
		case .underground:
			let lo: Int = max(d.minY, surf + 6)
			let hi: Int = max(lo, d.maxY - d.h)
			top = lo + Int(pick * Double(hi - lo + 1))
		case .sky: top = surf - d.h - 18 - Int(pick * 14.0)
		}
	} else if dim == .overworld {
		let c: Col = g.col(mid)
		if !d.biomes.isEmpty && !d.biomes.contains(c.biome.rawValue) { return nil }
		switch d.placement {
		case .surface:
			// on dry land only; its bottom row takes the place of the ground's top
			if c.biome == .ocean || c.h >= WorldGen.sea { return nil }
			top = c.h - d.h + 1
		case .underground:
			let lo: Int = max(d.minY, c.h + 6)
			let hi: Int = max(lo, d.maxY - d.h)
			top = lo + Int(pick * Double(hi - lo + 1))
		case .sky:
			top = c.h - d.h - 18 - Int(pick * 14.0)
		}
	} else {
		switch d.placement {
		case .surface: top = g.uFloor(mid) - d.h + 1
		case .underground:
			let hi: Int = max(d.minY, d.maxY - d.h)
			top = d.minY + Int(pick * Double(hi - d.minY + 1))
		case .sky: top = g.uCeil(mid) + 1
		}
	}
	top = clampI(top, 2, H - 3 - d.h)
	return (sx, top)
}

/// Builds the custom structures of the world's mods into a freshly made chunk, clipped to it (each chunk
/// builds its own part, so a structure across several chunks comes out whole). Bedrock is never touched;
/// a structure on the surface gets a foundation of earth under it so it never floats.
func applyModStructures(_ g: WorldGen, _ ch: Chunk, _ dim: Dimension) {
	let rt: ModRuntime = ModRuntime.shared
	if rt.structures.isEmpty { return }
	if dim == .overworld && !g.hasLandmarks { return }
	let d: Int = dim.rawValue
	let x0: Int = ch.x0
	let x1: Int = x0 + chunkW - 1
	for s in rt.structures where s.def.dim == d {
		let sp: Int = max(64, s.def.spacing)
		for cell in floorDiv(x0 - ModLimits.maxStructW - 16, sp)...floorDiv(x1, sp) {
			guard let site = modStructSite(g, s, dim, cell) else { continue }
			if site.0 + s.def.w - 1 < x0 || site.0 > x1 { continue }
			buildModStructure(ch, s, site.0, site.1, foundation: s.def.placement == .surface)
		}
	}
}

func buildModStructure(_ ch: Chunk, _ s: ModStructRT, _ sx: Int, _ top: Int, foundation: Bool) {
	let w: Int = s.def.w
	let h: Int = s.def.h
	var cx: Int = 0
	while cx < w {
		let lx: Int = sx + cx - ch.x0
		if lx < 0 || lx >= chunkW {
			cx += 1
			continue
		}
		var cy: Int = 0
		while cy < h {
			let v: Int = s.cells[cy * w + cx]
			let y: Int = top + cy
			if v >= 0 && v < 256 && y >= 1 && y < ch.H - 1 && ch.get(lx, y) != .bedrock {
				ch.setLocal(lx, y, Tile.make(UInt8(v)))
			}
			cy += 1
		}
		if foundation {
			// earth under a solid bottom block, down to the ground (at most 12 rows)
			let bottom: Int = s.cells[(h - 1) * w + cx]
			if bottom > 0 && bottom < 256 && Tile.make(UInt8(bottom)).solid {
				var y: Int = top + h
				var k: Int = 0
				while k < 12 && y < ch.H - 1 && !ch.get(lx, y).solid {
					ch.setLocal(lx, y, .dirt)
					y += 1
					k += 1
				}
			}
		}
		cx += 1
	}
}

extension ModRuntime {
	/// The loot table for a chest that one of the mods' structures put there, if any
	func structureChestLoot(_ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> String? {
		let d: Int = dim.rawValue
		if dim == .overworld && !g.hasLandmarks { return nil }
		for s in structures where s.def.dim == d && !s.loot.isEmpty {
			let sp: Int = max(64, s.def.spacing)
			for cell in floorDiv(x - ModLimits.maxStructW - 16, sp)...floorDiv(x, sp) {
				guard let site = modStructSite(g, s, dim, cell) else { continue }
				let cx: Int = x - site.0
				let cy: Int = y - site.1
				if cx < 0 || cy < 0 || cx >= s.def.w || cy >= s.def.h { continue }
				if s.cells[cy * s.def.w + cx] == Int(Tile.chest.rawValue) { return s.loot }
			}
		}
		return nil
	}
}

extension Game {
	// MARK: structure capture

	/// Starts picking a part of the world to save as a structure (two taps on the world)
	func startCapture() {
		capturing = true
		showCapture = false
		capA = nil
		capB = nil
		releaseAllInput()
		say("Tap two corners of what you built.", 4.0)
		bumpHUD()
	}

	func cancelCapture() {
		capturing = false
		showCapture = false
		capA = nil
		capB = nil
		bumpHUD()
	}

	/// A tap while capturing: the first corner, then the second (which opens the save panel); a third
	/// tap starts again
	func captureTap(_ wx: Double, _ wy: Double) {
		let t: (Int, Int) = (Int(floor(wx)), Int(floor(wy)))
		if capA == nil || capB != nil {
			capA = t
			capB = nil
		} else {
			capB = t
			showCapture = true
		}
		bumpHUD()
	}

	/// The selection with its corners in order, held to the largest structure size
	func captureRect() -> (Int, Int, Int, Int)? {
		guard let a = capA else { return nil }
		let b: (Int, Int) = capB ?? (Int(floor(aimX)), Int(floor(aimY)))
		let x0: Int = min(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let x1: Int = min(max(a.0, b.0), x0 + ModLimits.maxStructW - 1)
		let y1: Int = min(max(a.1, b.1), y0 + ModLimits.maxStructH - 1)
		return (x0, y0, x1, y1)
	}

	/// Turns the selected blocks into a structure. Machines, the rift gate and bedrock are left out (they
	/// can't be copied safely) and counted; empty space either clears the ground or leaves it as it is.
	/// Custom blocks are kept by their keys, so the structure works in any world that has their mod.
	func captureStructure(clearAir: Bool) -> (ModStructure, Int) {
		var st = ModStructure()
		guard let r = captureRect() else { return (st, 0) }
		let rt: ModRuntime = ModRuntime.shared
		st.w = r.2 - r.0 + 1
		st.h = r.3 - r.1 + 1
		st.dim = world.dim == .umbral ? 1 : 0
		if let cd = customDim { st.dimKey = splitModKey(cd.key).1 }
		var skipped: Int = 0
		var cells: [Int] = []
		cells.reserveCapacity(st.w * st.h)
		for y in r.1...r.3 {
			for x in r.0...r.2 {
				let t: Tile = world.tile(x, y)
				if t == .air {
					cells.append(clearAir ? 0 : -1)
				} else if t.isMod {
					var key: String = rt.slotKey[Int(t.rawValue - Tile.modBase)] ?? ""
					if let hash = key.firstIndex(of: "#") { key = String(key[key.startIndex..<hash]) }
					if key.isEmpty {
						cells.append(-1)
						skipped += 1
					} else {
						if !st.palette.contains(key) { st.palette.append(key) }
						cells.append(1000 + (st.palette.firstIndex(of: key) ?? 0))
					}
				} else if !modStructureTileOK(t) {
					cells.append(-1)
					skipped += 1
				} else {
					cells.append(Int(t.rawValue))
				}
			}
		}
		st.cells = cells
		// where it was found decides where it goes: on the surface, underground or up in the sky
		let mid: Int = (r.0 + r.2) / 2
		if world.dim == .overworld {
			let ground: Int = gen.col(mid).h
			if r.3 > ground + 6 {
				st.placement = .underground
				st.minY = clampI(r.1 - 40, 4, 550)
				st.maxY = clampI(r.3 + 40, st.minY, 550)
			} else if r.3 < ground - 12 {
				st.placement = .sky
			}
		}
		return (st, skipped)
	}

	/// Saves the captured structure into a mod (a new one, switched on, when `modID` is empty) and ends
	/// the capture. Returns what to tell the player.
	func saveCapture(name: String, modID: String, newModName: String, placement: ModPlacement, clearAir: Bool) -> String {
		var cap: (ModStructure, Int) = captureStructure(clearAir: clearAir)
		if cap.0.w < 1 || cap.0.h < 1 { return "Pick two corners first." }
		if !cap.0.cells.contains(where: { $0 > 0 }) { return "There are no blocks in that area." }
		var p: ModPack = ModPack()
		var isNew: Bool = true
		if !modID.isEmpty, let existing = ModStore.pack(modID) {
			p = existing
			isNew = false
		} else {
			p.id = newModID()
			let nm: String = newModName.trimmingCharacters(in: .whitespaces)
			p.name = nm.isEmpty ? "My Structures" : String(nm.prefix(32))
		}
		if p.structures.count >= ModLimits.maxStructures { return joinText(p.name, " already holds the most structures a mod can.") }
		let nm: String = name.trimmingCharacters(in: .whitespaces)
		cap.0.name = nm.isEmpty ? "Structure" : String(nm.prefix(32))
		cap.0.placement = placement
		cap.0.id = p.freshID("structure")
		p.structures.append(cap.0)
		if !ModStore.save(p) { return "The mod could not be saved." }
		if isNew { ModStore.setEnabled(p.id, true) }
		cancelCapture()
		let note: String = cap.1 > 0 ? " Machines, bedrock and the rift gate were left out." : ""
		return joinText("Saved \u{201C}", cap.0.name, "\u{201D} in ", p.name, ". New worlds with this mod will have it.", note)
	}
}

/// Blocks a structure may hold: not machines (their wiring and settings can't come along), the rift gate
/// (one per world) or bedrock
func modStructureTileOK(_ t: Tile) -> Bool {
	if t.isPower || t == .bedrock || t == .portalFrame || t == .portalOff || t == .portalOn { return false }
	if Tile(rawValue: t.rawValue) == nil { return false }
	switch t {
	case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater: return false
	default: return true
	}
}

func generateChunk(_ g: WorldGen, _ dim: Dimension, _ cx: Int) -> Chunk {
	if dim.isCustom { return generateCustomChunk(g, dim, cx) }
	return dim == .overworld ? generateOverworldChunk(g, cx) : generateUmbralChunk(g, cx)
}

func dimHeight(_ dim: Dimension) -> Int {
	if dim.isCustom { return customDimH }
	return dim == .overworld ? WorldGen.H : umbralH
}

// ===== p10_world =====

// MARK: - World container: chunk streaming, tile access, chests

struct ChestKey: Hashable, Codable {
	var d: Int
	var x: Int
	var y: Int
}

struct ChestEntry: Codable {
	var key: ChestKey
	var items: [Stack]
}

final class World {
	let gen: WorldGen
	var dim: Dimension = .overworld
	var H: Int = WorldGen.H
	var chunks: [Int: Chunk] = [:]
	var parked: [[Int: Chunk]] = [[Int: Chunk]](repeating: [:], count: dimCount)
	/// bounding box of tile edits since the light map last looked (lets lighting skip far-away edits)
	var editAny: Bool = false
	var editX0: Int = 0
	var editX1: Int = 0
	var editY0: Int = 0
	var editY1: Int = 0
	/// bumps when chunks load/unload or the dimension changes
	var layoutVersion: Int = 0
	/// structural physics is on: every change is noted for it to look at (see Game.updateStructures)
	var structWatch: Bool = false
	var structEdits: [IntPair] = []

	func noteEdit(_ x: Int, _ y: Int) {
		if !editAny {
			editAny = true
			editX0 = x; editX1 = x; editY0 = y; editY1 = y
		} else {
			if x < editX0 { editX0 = x }
			if x > editX1 { editX1 = x }
			if y < editY0 { editY0 = y }
			if y > editY1 { editY1 = y }
		}
	}
	var chests: [ChestKey: [Stack]] = [:]
	/// Sparkworks devices by place (settings and charge), and a counter bumped whenever wiring or
	/// devices change, so the networks are worked out again
	var devs: [ChestKey: PowerDev] = [:]
	var powerRev: Int = 0
	var version: Int = 0
	private var cacheCX: Int = Int.min
	private var cacheChunk: Chunk? = nil

	init(gen: WorldGen) {
		self.gen = gen
	}

	// MARK: chunk streaming

	func inRange(_ cx: Int) -> Bool {
		if gen.infinite { return true }
		return cx >= 0 && cx < gen.width / chunkW
	}

	func chunk(_ cx: Int) -> Chunk? {
		if cx == cacheCX { return cacheChunk }
		let c: Chunk? = chunks[cx]
		cacheCX = cx
		cacheChunk = c
		return c
	}

	func isLoaded(_ x: Int) -> Bool {
		return chunks[floorDiv(x, chunkW)] != nil
	}

	@discardableResult
	func loadChunk(_ cx: Int) -> Chunk? {
		if let c = chunks[cx] { return c }
		if !inRange(cx) { return nil }
		var c: Chunk
		if let p = parked[dim.rawValue][cx] {
			c = p
			parked[dim.rawValue][cx] = nil
		} else {
			let t0: Double = perfNow()
			c = generateChunk(gen, dim, cx)
			Perf.shared.noteGen(perfNow() - t0)
		}
		chunks[cx] = c
		cacheCX = Int.min
		version += 1
		if c.wireCount > 0 { powerRev &+= 1 }
		noteEdit(cx * chunkW, 0)
		noteEdit(cx * chunkW + chunkW - 1, H - 1)
		gen.cache.trim()
		return c
	}

	func unloadChunk(_ cx: Int) {
		guard let c = chunks[cx] else { return }
		if c.dirty { parked[dim.rawValue][cx] = c }
		if c.wireCount > 0 { powerRev &+= 1 }
		chunks[cx] = nil
		cacheCX = Int.min
		version += 1
		noteEdit(cx * chunkW, 0)
		noteEdit(cx * chunkW + chunkW - 1, H - 1)
	}

	/// Streams chunks around a centre column. Loads nearest first (budget limits work per call);
	/// unloads only chunks farther than load radius + hysteresis, and never any in `keep`.
	@discardableResult
	func stream(centerX: Int, radius: Int, hysteresis: Int, budget: Int, keep: Set<Int>) -> Int {
		let cc: Int = floorDiv(centerX, chunkW)
		var loaded: Int = 0
		var d: Int = 0
		while d <= radius && loaded < budget {
			let a: Int = cc - d
			let b: Int = cc + d
			if inRange(a) && chunks[a] == nil { loadChunk(a); loaded += 1 }
			if d > 0 && loaded < budget && inRange(b) && chunks[b] == nil { loadChunk(b); loaded += 1 }
			d += 1
		}
		if chunks.count > radius * 2 + 4 {
			var drop: [Int] = []
			for k in chunks.keys {
				if abs(k - cc) > radius + hysteresis && !keep.contains(k) { drop.append(k) }
			}
			for k in drop { unloadChunk(k) }
		}
		return loaded
	}

	func loadAround(centerX: Int, radius: Int) {
		let cc: Int = floorDiv(centerX, chunkW)
		for d in 0...radius {
			if inRange(cc - d) { loadChunk(cc - d) }
			if inRange(cc + d) { loadChunk(cc + d) }
		}
	}

	func switchDimension(_ nd: Dimension) {
		if nd == dim { return }
		for (k, c) in chunks { if c.dirty { parked[dim.rawValue][k] = c } }
		chunks.removeAll()
		cacheCX = Int.min
		powerRev &+= 1
		dim = nd
		H = dimHeight(nd)
		version += 1
		layoutVersion += 1
	}

	var dirtyChunkCount: Int {
		var n: Int = 0
		for (_, c) in chunks { if c.dirty { n += 1 } }
		for d in 0..<parked.count { n += parked[d].count }
		return n
	}

	// MARK: tile access

	func virtualTile(_ x: Int, _ y: Int) -> Tile {
		if !gen.infinite && (x < 0 || x >= gen.width) { return .bedrock }
		return .stone
	}

	@inline(__always) func tile(_ x: Int, _ y: Int) -> Tile {
		if y < 0 { return .air }
		if y >= H { return .bedrock }
		let cx: Int = floorDiv(x, chunkW)
		if let c = chunk(cx) { return c.get(x - cx * chunkW, y) }
		return virtualTile(x, y)
	}

	func solid(_ x: Int, _ y: Int) -> Bool { return tile(x, y).solid }

	/// Returns the previous tile. Handles dependent tiles (unsupported plants) and sky light columns.
	@discardableResult
	func set(_ x: Int, _ y: Int, _ t: Tile) -> Tile {
		if y < 1 || y >= H - 1 { return .air }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return .air }
		let lx: Int = x - cx * chunkW
		let old: Tile = c.get(lx, y)
		if old == t { return old }
		c.tiles[lx * H + y] = t.rawValue
		c.dirty = true
		c.rev &+= 1
		version += 1
		// a new block is not "built" until whoever put it there says so (see setBuilt)
		if !c.built.isEmpty { c.built[lx * H + y] = 0 }
		if c.stairs >= 0 {
			if Tile.stairTable[Int(old.rawValue)] != 0 { c.stairs -= 1 }
			if Tile.stairTable[Int(t.rawValue)] != 0 { c.stairs += 1 }
		}
		if structWatch && structEdits.count < 128 { structEdits.append(IntPair(x: x, y: y)) }
		// a roof can add or remove house walls up to 12 rows below it
		c.bumpRows(y - 1, y + 13)
		if old.opaque != t.opaque {
			let before: Int = c.skyTop[lx]
			c.recomputeSky(lx)
			let after: Int = c.skyTop[lx]
			if before != after { c.bumpRows(min(before, after) - 1, max(before, after) + 13) }
		}
		noteEdit(x, y)
		if Tile.powerTable[i8(old.rawValue)] || Tile.powerTable[i8(t.rawValue)] { powerTileChanged(x, y, old, t) }
		return old
	}

	func needsSupport(_ t: Tile) -> Bool {
		if t.isPlant && t != .torch && t != .lantern && t != .cobweb { return true }
		switch t {
		case .workbench, .furnace, .chest, .campfire, .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3, .doorClosed, .doorOpen, .oreCart: return true
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater: return true
		case .crankGen, .solarPanel, .fuelGen, .emberDynamo, .battery, .accumulator, .pressurePlate, .lever: return true
		case .alchemyStill, .infuser, .exoStation: return true
		case .chair, .table, .bedL, .bedR, .cabinet, .wardrobe, .bookshelf, .floorLamp, .sofa: return true
		default: return false
		}
	}

	func supports(_ below: Tile, _ t: Tile) -> Bool {
		switch t {
		case .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3: return below == .farmland
		case .sapling: return isSoil(below)
		case .doorClosed, .doorOpen: return below.solid || below == .doorClosed || below == .doorOpen
		default: return below.supportsThings || below == .platform
		}
	}

	/// Ground a sapling takes root in
	func isSoil(_ t: Tile) -> Bool {
		switch t {
		case .grass, .dirt, .farmland, .jungleGrass, .mossGrass, .dryGrass, .snow, .mud: return true
		default: return false
		}
	}

	func skyTop(_ x: Int) -> Int {
		let cx: Int = floorDiv(x, chunkW)
		if let c = chunk(cx) { return c.skyTop[x - cx * chunkW] }
		return 0
	}

	func isSkyExposed(_ x: Int, _ y: Int) -> Bool {
		if dim != .overworld && !dimHasSky(dim) { return false }
		return y < skyTop(x)
	}

	func surfaceY(_ x: Int) -> Int {
		var y: Int = 0
		while y < H - 1 {
			let t: Tile = tile(x, y)
			if t.solid || t.liquid { return y }
			y += 1
		}
		return H - 1
	}

	/// Row of the first solid tile at or below fromY
	func groundBelow(_ x: Int, _ fromY: Int) -> Int {
		var y: Int = max(0, fromY)
		while y < H - 1 {
			if tile(x, y).solid { return y }
			y += 1
		}
		return H - 1
	}

	// MARK: chests

	func chestKey(_ x: Int, _ y: Int) -> ChestKey {
		return ChestKey(d: dim.rawValue, x: x, y: y)
	}

	func chestItems(_ x: Int, _ y: Int) -> [Stack] {
		let k: ChestKey = chestKey(x, y)
		if let it = chests[k] { return it }
		let rt: ModRuntime = ModRuntime.shared
		var it: [Stack] = []
		if rt.active, let key = rt.structureChestLoot(gen, dim, x, y) {
			var rng = RNG(hashU(x, y, gen.seed &+ 4441))
			it = rt.roll(key, &rng)
		} else {
			// the game's own chests also turn up ingredients (a mod structure's chest holds only its table)
			it = alchemyChestExtras(generateChestLoot(gen, dim, x, y), gen, dim, x, y)
		}
		if rt.active { it = rt.addChestLoot(it, gen, dim, x, y) }
		chests[k] = it
		return it
	}

	func setChestItems(_ x: Int, _ y: Int, _ items: [Stack]) {
		chests[chestKey(x, y)] = items
	}

	func removeChest(_ x: Int, _ y: Int) -> [Stack] {
		let k: ChestKey = chestKey(x, y)
		var out: [Stack] = []
		// storage under a key outside the world (a vehicle's cargo crate, the suit's pack) is never rolled
		if let it = chests[k] { out = it } else if y >= 0 { out = chestItems(x, y) }
		chests[k] = nil
		return out
	}

	// MARK: save helpers (RLE of raw tile bytes)

	static func rle(_ a: [UInt8]) -> [UInt8] {
		var out: [UInt8] = []
		var i: Int = 0
		while i < a.count {
			let v: UInt8 = a[i]
			var n: Int = 1
			while i + n < a.count && a[i + n] == v && n < 255 { n += 1 }
			out.append(UInt8(n))
			out.append(v)
			i += n
		}
		return out
	}

	static func unrle(_ a: [UInt8], _ count: Int) -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(count)
		var i: Int = 0
		while i + 1 < a.count {
			let n: Int = Int(a[i])
			let v: UInt8 = a[i + 1]
			for _ in 0..<n { out.append(v) }
			i += 2
		}
		if out.count < count { out.append(contentsOf: [UInt8](repeating: 0, count: count - out.count)) }
		return out
	}
}

// MARK: - Chest loot (deterministic per position, generated on first open)

func lootStack(_ it: Item, _ n: Int) -> Stack { return Stack(item: it, count: n) }

/// One line of a loot table: what, how many, how likely against the others in its tier, and the
/// shallowest mine level it can turn up at
struct LootEntry {
	var item: Item
	var lo: Int
	var hi: Int
	var weight: Double
	var minDepth: Int = 0
}

/// Mine chest loot by rarity. Most of what a chest holds comes from the common tier; a pull from the
/// useful tier is occasional; a chest gets at most one chance at the exceptional tier, and that chance
/// is small: larger deeper down and in rooms, and largest in chests that were hidden away.
enum MineLoot {
	static let common: [LootEntry] = [
		LootEntry(item: .mat(.coal), lo: 3, hi: 8, weight: 10),
		LootEntry(item: .block(.torch), lo: 3, hi: 8, weight: 9),
		LootEntry(item: .block(.planks), lo: 4, hi: 10, weight: 5),
		LootEntry(item: .mat(.stick), lo: 3, hi: 8, weight: 4),
		LootEntry(item: .mat(.copperOre), lo: 2, hi: 5, weight: 5),
		LootEntry(item: .mat(.tinOre), lo: 2, hi: 4, weight: 4),
		LootEntry(item: .mat(.string), lo: 1, hi: 4, weight: 3),
		LootEntry(item: .food(.bread), lo: 1, hi: 2, weight: 4),
		LootEntry(item: .food(.apple), lo: 1, hi: 3, weight: 2),
		LootEntry(item: .block(.ladder), lo: 2, hi: 6, weight: 3),
		LootEntry(item: .block(.rail), lo: 3, hi: 8, weight: 2),
		LootEntry(item: .mat(.ironOre), lo: 1, hi: 3, weight: 3, minDepth: 1)
	]
	static let useful: [LootEntry] = [
		LootEntry(item: .mat(.ironBar), lo: 1, hi: 3, weight: 6),
		LootEntry(item: .mat(.bronzeBar), lo: 2, hi: 4, weight: 6),
		LootEntry(item: .ammo(.arrow), lo: 6, hi: 14, weight: 4),
		LootEntry(item: .ammo(.bolt), lo: 4, hi: 10, weight: 4),
		LootEntry(item: .ammo(.bullet), lo: 4, hi: 8, weight: 2, minDepth: 1),
		LootEntry(item: .mat(.saltpeter), lo: 2, hi: 5, weight: 3),
		LootEntry(item: .mat(.gunpowder), lo: 2, hi: 4, weight: 3),
		LootEntry(item: .gadget(.fireFlask), lo: 1, hi: 2, weight: 2),
		LootEntry(item: .gadget(.bomb), lo: 1, hi: 2, weight: 2),
		LootEntry(item: .block(.lantern), lo: 1, hi: 2, weight: 3),
		LootEntry(item: .food(.cookedMeat), lo: 1, hi: 3, weight: 3),
		LootEntry(item: .mat(.silverBar), lo: 1, hi: 2, weight: 2, minDepth: 1),
		LootEntry(item: .mat(.goldBar), lo: 1, hi: 2, weight: 2, minDepth: 2),
		LootEntry(item: .mat(.amethyst), lo: 1, hi: 3, weight: 1.5, minDepth: 1),
		LootEntry(item: .knife(.iron), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .tool(.pickaxe, .iron), lo: 1, hi: 1, weight: 1.2),
		LootEntry(item: .club(.studded), lo: 1, hi: 1, weight: 1),
		LootEntry(item: .gun(.crossbow), lo: 1, hi: 1, weight: 0.8),
		LootEntry(item: .armor(.head, .iron), lo: 1, hi: 1, weight: 0.8)
	]
	static let exceptional: [LootEntry] = [
		LootEntry(item: .relic(.moonDagger), lo: 1, hi: 1, weight: 2),
		LootEntry(item: .relic(.emberCleaver), lo: 1, hi: 1, weight: 1.5, minDepth: 2),
		LootEntry(item: .relic(.quakeMaul), lo: 1, hi: 1, weight: 1.5, minDepth: 2),
		LootEntry(item: .gun(.repeater), lo: 1, hi: 1, weight: 2, minDepth: 1),
		LootEntry(item: .gun(.stormRod), lo: 1, hi: 1, weight: 1, minDepth: 2),
		LootEntry(item: .mat(.diamond), lo: 1, hi: 3, weight: 3, minDepth: 1),
		LootEntry(item: .mat(.mythrilBar), lo: 1, hi: 2, weight: 1.5, minDepth: 2),
		LootEntry(item: .gear(.swiftBoots), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .gear(.headlamp), lo: 1, hi: 1, weight: 2),
		LootEntry(item: .gear(.silverCharm), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .mat(.relicFragment), lo: 1, hi: 2, weight: 2)
	]

	/// the chance a chest gets its one pull from the exceptional tier
	static func exceptionalChance(_ spot: MineSpot, _ depth: Int) -> Double {
		var p: Double = 0.012 + 0.008 * Double(depth)
		if spot == .room { p += 0.012 }
		if spot == .hidden { p += 0.05 }
		return min(p, 0.12)
	}

	/// the chance each pull comes from the useful tier rather than the common one
	static func usefulChance(_ spot: MineSpot, _ depth: Int) -> Double {
		var p: Double = 0.18 + 0.05 * Double(depth)
		if spot == .room { p += 0.06 }
		if spot == .hidden { p += 0.15 }
		return min(p, 0.55)
	}

	static func pick(_ table: [LootEntry], _ depth: Int, _ rng: inout RNG) -> LootEntry? {
		let ok: [LootEntry] = table.filter { $0.minDepth <= depth }
		var total: Double = 0
		for e in ok { total += e.weight }
		if total <= 0 { return nil }
		var r: Double = rng.double() * total
		for e in ok {
			r -= e.weight
			if r <= 0 { return e }
		}
		return ok.last
	}

	/// Rolls a mine chest: two to four stacks, never the same item twice, counts within stack limits
	static func roll(_ rng: inout RNG, _ spot: MineSpot, _ depth: Int) -> [Stack] {
		var out: [Stack] = []
		var n: Int = 2 + rng.int(2) + (spot == .open ? 0 : 1)
		func add(_ e: LootEntry, _ rng: inout RNG) -> Bool {
			if out.contains(where: { $0.item == e.item }) { return false }
			let c: Int = min(e.item.maxStack, max(1, e.lo + rng.int(max(1, e.hi - e.lo + 1))))
			out.append(Stack(item: e.item, count: c))
			return true
		}
		if rng.double() < exceptionalChance(spot, depth), let e = pick(exceptional, depth, &rng) {
			if add(e, &rng) { n -= 1 }
		}
		let pu: Double = usefulChance(spot, depth)
		var tries: Int = 0
		while n > 0 && tries < 12 {
			tries += 1
			let table: [LootEntry] = rng.double() < pu ? useful : common
			if let e = pick(table, depth, &rng), add(e, &rng) { n -= 1 }
		}
		if out.isEmpty { out.append(Stack(item: .block(.torch), count: 4)) }
		return out
	}

	static func isExceptional(_ it: Item) -> Bool {
		return exceptional.contains { $0.item == it }
	}
}

func generateChestLoot(_ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> [Stack] {
	var rng = RNG(hashU(x, y, g.seed &+ 777))
	var out: [Stack] = []
	func add(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
		if rng.double() < p { out.append(lootStack(it, lo + rng.int(max(1, hi - lo + 1)))) }
	}
	func tierPick(_ lo: Int, _ hi: Int) -> Tier {
		let r: Int = lo + rng.int(max(1, hi - lo + 1))
		return Tier(rawValue: clampI(r, 1, 9)) ?? .wood
	}
	if dim == .umbral, let c = g.citadel, abs(x - c.chestX) <= 1 && abs(y - (c.floor - 1)) <= 1 {
		// the Warden's hoard
		add(.mat(.voidBar), 3, 6, 1.0)
		add(.mat(.emberBar), 4, 8, 1.0)
		add(.mat(.diamond), 3, 6, 1.0)
		add(.mat(.relicFragment), 2, 3, 1.0)
		add(.armor(ArmorSlot.allCases[rng.int(3)], .voidium), 1, 1, 0.5)
		add(.spear(.voidium), 1, 1, 0.3)
		return out
	}
	if dim == .umbral {
		add(.mat(.emberBar), 2, 6, 0.8)
		add(.mat(.voidBar), 1, 3, 0.35)
		add(.mat(.diamond), 1, 4, 0.6)
		add(.ammo(.arrow), 15, 40, 0.5)
		add(.ammo(.bullet), 8, 20, 0.5)
		add(.sword(tierPick(6, 8)), 1, 1, 0.35)
		add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(6, 8)), 1, 1, 0.3)
		add(.food(.cookedMeat), 3, 6, 0.6)
		add(.block(.lantern), 2, 4, 0.5)
		return out
	}
	// portal vault
	if abs(x - g.portalX) < 20 && y > 300 {
		add(.mat(.diamond), 3, 7, 1.0)
		add(.mat(.mythrilBar), 2, 5, 0.9)
		add(.mat(.goldBar), 4, 9, 0.8)
		add(.gun(.rifle), 1, 1, 0.5)
		add(.ammo(.bullet), 12, 30, 0.9)
		add(.food(.cookedMeat), 4, 8, 0.8)
		return out
	}
	// lair treasure
	if let L = g.lairAt(x, radius: 70), y < 200 {
		add(.mat(.goldBar), 3, 8, 0.9)
		add(.mat(.diamond), 1, 3, 0.6)
		add(.sword(tierPick(4, 6)), 1, 1, 0.5)
		add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(4, 6)), 1, 1, 0.5)
		if L.kind == .bear { add(.mat(.fur), 2, 5, 0.9); add(.mat(.claw), 1, 3, 0.7) } else { add(.mat(.tusk), 1, 2, 0.5); add(.mat(.bone), 6, 14, 1.0) }
		add(.food(.cookedMeat), 3, 6, 0.8)
		return out
	}
	// crystal grottos and old mines
	if y > 150 {
		for s in g.grottoSites(overlapping: x - 2, x + 2) where abs(x - s.x) <= s.rx && abs(y - s.floorY) < 6 {
			add(.mat(.crystalShard), 3, 7, 1.0)
			add(.mat(.diamond), 1, 3, 0.7)
			add(.block(.glowCrystal), 2, 5, 0.8)
			add(.mat(.relicFragment), 1, 2, 0.8)
			add(.mat(.mythrilBar), 1, 3, 0.45)
			add(.gear(.headlamp), 1, 1, 0.3)
			add(.spear(tierPick(4, 6)), 1, 1, 0.35)
			return out
		}
	}
	if g.hasMines {
		for s in g.mineSites(overlapping: x - 2, x + 2) where y > s.ground + 8 && y <= s.deepest + 2 {
			if let plan = s.plan {
				// version 4: the plan knows each chest's place, and that sets its loot
				if let c = plan.chests.first(where: { $0.x == x && $0.y == y }) { return MineLoot.roll(&rng, c.spot, c.depth) }
				return MineLoot.roll(&rng, .open, 0)
			}
			// older mines: a chest at the end of a gallery, deeper galleries a little richer
			var lv: Int = 0
			for (i, f) in s.levels.enumerated() where y <= f { lv = i; break }
			return MineLoot.roll(&rng, .room, lv)
		}
	}
	// chests in the villages of worlds saved before generator version 5 (new worlds have none)
	if y < 200, let v = g.nearestVillage(to: x), abs(x - v.x) <= v.halfW + 12 {
		add(.food(.bread), 2, 5, 0.9)
		add(.food(.carrot), 2, 5, 0.6)
		add(.mat(.seeds), 3, 8, 0.8)
		add(.block(.torch), 4, 10, 0.8)
		add(.tool(.pickaxe, tierPick(2, 3)), 1, 1, 0.35)
		add(.sword(tierPick(2, 4)), 1, 1, 0.3)
		add(.mat(.ironBar), 1, 4, 0.45)
		add(.mat(.string), 2, 5, 0.4)
		add(.ammo(.arrow), 8, 20, 0.35)
		if out.isEmpty { add(.block(.planks), 6, 12, 1.0) }
		return out
	}
	// ruins by kind
	if y < 260 {
		for r in g.rareSites(overlapping: x - 40, x + 40) {
			if abs(r.x - x) > 40 { continue }
			switch r.kind {
			case .tower:
				add(.bow, 1, 1, 0.45); add(.ammo(.arrow), 12, 30, 0.9); add(.mat(.goldBar), 1, 4, 0.5)
			case .fort:
				add(.sword(tierPick(3, 5)), 1, 1, 0.6); add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(3, 5)), 1, 1, 0.6); add(.ammo(.bullet), 6, 14, 0.4)
			case .camp:
				add(.food(.cookedMeat), 2, 5, 0.9); add(.food(.bread), 2, 4, 0.7); add(.mat(.string), 3, 7, 0.6); add(.block(.torch), 5, 12, 0.8)
			case .overgrown:
				add(.mat(.seeds), 5, 12, 0.9); add(.food(.apple), 3, 6, 0.8); add(.mat(.diamond), 1, 2, 0.3); add(.gadget(.shears), 1, 1, 0.3)
			case .bunker:
				add(.gun(.pistol), 1, 1, 0.55); add(.gun(.rifle), 1, 1, 0.18); add(.ammo(.bullet), 10, 28, 0.9); add(.mat(.goldBar), 3, 8, 0.8); add(.mat(.mythrilBar), 1, 3, 0.4)
			case .house:
				add(.food(.cookedFish), 2, 5, 0.7); add(.block(.lantern), 1, 3, 0.6); add(.tool(.axe, tierPick(2, 4)), 1, 1, 0.4); add(.mat(.copperBar), 2, 6, 0.6)
			}
			if out.isEmpty { add(.block(.planks), 5, 10, 1.0) }
			return out
		}
	}
	// generic by depth
	if y < WorldGen.sea + 40 {
		add(.block(.planks), 6, 14, 0.8)
		add(.food(.bread), 1, 3, 0.6)
		add(.block(.torch), 3, 8, 0.7)
		add(.mat(.copperBar), 1, 4, 0.5)
		if g.genVersion >= 3 { add(.mat(.relicFragment), 1, 1, 0.15) }
	} else if y < 320 {
		add(.mat(.ironBar), 2, 6, 0.8)
		add(.mat(.goldBar), 1, 4, 0.5)
		add(.block(.torch), 6, 14, 0.8)
		add(.tool(.pickaxe, tierPick(3, 5)), 1, 1, 0.25)
		add(.ammo(.arrow), 10, 24, 0.5)
		add(.food(.cookedMeat), 2, 4, 0.6)
	} else {
		add(.mat(.goldBar), 3, 8, 0.8)
		add(.mat(.diamond), 1, 4, 0.55)
		add(.mat(.mythrilBar), 1, 3, 0.4)
		add(.sword(tierPick(5, 7)), 1, 1, 0.3)
		add(.ammo(.bullet), 8, 20, 0.45)
		add(.block(.lantern), 2, 5, 0.6)
	}
	if out.isEmpty { add(.block(.torch), 3, 6, 1.0) }
	return out
}

// ===== p11_light =====

// MARK: - Lighting: flood-fill light over the visible window (sky light + block light)
// Written with raw buffers and plain Ints so it stays fast in Swift Playgrounds' debug builds.

/// Brightness per light level. Slightly lifted (gamma 0.85) so torchlight reaches further into caves and
/// the step from lit to unlit is less harsh.
let lightLUT: [Double] = (0...15).map { pow(Double($0) / 15.0, 0.85) }

final class LightMap {
	var ox: Int = 0
	var oy: Int = 0
	var w: Int = 0
	var h: Int = 0
	var sky: [Int] = []
	var blk: [Int] = []
	/// block light from tiles only; moving lights are layered on top by applyDynamic()
	var blkBase: [Int] = []
	var opq: [Bool] = []
	var drawn: [Bool] = []
	var valid: Bool = false
	var stamp: Int = -1
	var skyUsed: Int = -1
	var dynUsed: Int = 0
	var dimUsed: Int = -1
	var layoutUsed: Int = -1
	// bucket queues: 16 levels, each with room for every cell (a cell enters a level at most once)
	private var qCap: Int = 0
	private var queue: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 1)
	private var skySeed: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 1)
	private var lens: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 16)
	private var skyN: Int = 0
	// colour tables for buildPixels (index = sky * 16 + block)
	private var darkLUT: [UInt32] = [UInt32](repeating: 0, count: 256)
	private var glowLUT: [UInt32] = [UInt32](repeating: 0, count: 256)

	deinit {
		queue.deallocate()
		skySeed.deallocate()
		lens.deallocate()
	}

	func covers(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Bool {
		return valid && x0 >= ox && y0 >= oy && x1 < ox + w && y1 < oy + h
	}

	/// Lights the window (nox, noy, nw, nh). `noteSeen` is false for a look at ground off the screen
	/// (spawning): the screen's own light map still has to see the edits made since it last looked.
	func compute(_ world: World, _ nox: Int, _ noy: Int, _ nw: Int, _ nh: Int, _ skyLevel: Int, _ dyn: [(Int, Int, Int)], noteSeen: Bool = true) {
		ox = nox; oy = noy; w = nw; h = nh
		let n: Int = w * h
		if sky.count != n {
			sky = [Int](repeating: 0, count: n)
			blk = [Int](repeating: 0, count: n)
			opq = [Bool](repeating: false, count: n)
			drawn = [Bool](repeating: true, count: n)
		}
		if qCap < n {
			queue.deallocate()
			skySeed.deallocate()
			qCap = n
			queue = UnsafeMutablePointer<Int>.allocate(capacity: n * 16)
			skySeed = UnsafeMutablePointer<Int>.allocate(capacity: n)
		}
		var l0: Int = 0
		while l0 < 16 { lens[l0] = 0; l0 += 1 }
		let H: Int = world.H
		let hasSky: Bool = dimHasSky(world.dim)
		let sl: Int = clampI(skyLevel, 0, 15)
		let q: UnsafeMutablePointer<Int> = queue
		let ss: UnsafeMutablePointer<Int> = skySeed
		let ln: UnsafeMutablePointer<Int> = lens
		let cap: Int = qCap
		let ww: Int = w
		let hh: Int = h
		let oxx: Int = ox
		let oyy: Int = oy
		var sn: Int = 0
		let opT: [Bool] = Tile.opaqueTable
		let liT: [Int] = Tile.lightTable
		sky.withUnsafeMutableBufferPointer { skyB in
			blk.withUnsafeMutableBufferPointer { blkB in
				opq.withUnsafeMutableBufferPointer { opqB in
					drawn.withUnsafeMutableBufferPointer { drB in
						opT.withUnsafeBufferPointer { opTB in
							liT.withUnsafeBufferPointer { liTB in
								guard let skyP = skyB.baseAddress, let blkP = blkB.baseAddress, let opqP = opqB.baseAddress,
									  let drP = drB.baseAddress, let opTP = opTB.baseAddress, let liTP = liTB.baseAddress else { return }
								var i0: Int = 0
								while i0 < n { skyP[i0] = 0; blkP[i0] = 0; i0 += 1 }
								var ix: Int = 0
								while ix < ww {
									let x: Int = oxx + ix
									let cx: Int = floorDiv(x, chunkW)
									let lx: Int = x - cx * chunkW
									if let c = world.chunk(cx) {
										let skyTop: Int = hasSky ? c.skyTop[lx] : -1
										let back: [UInt8] = world.backdrop(c)
										c.tiles.withUnsafeBufferPointer { tb in
											back.withUnsafeBufferPointer { bb in
												guard let tp = tb.baseAddress, let bp = bb.baseAddress else { return }
												let base: Int = lx * H
												var iy: Int = 0
												var i: Int = ix
												while iy < hh {
													let y: Int = oyy + iy
													if y < 0 {
														opqP[i] = false
														drP[i] = false
														if hasSky && sl > 0 {
															skyP[i] = sl
															ss[sn] = i; sn += 1
														}
													} else if y >= H {
														opqP[i] = true
														drP[i] = true
													} else {
														let rb: UInt8 = tp[base + y]
														let raw: Int = i8(rb)
														let op: Bool = opTP[raw]
														opqP[i] = op
														drP[i] = rb != 0 || bp[base + y] != 0
														let emit: Int = liTP[raw]
														if emit > 0 {
															blkP[i] = emit
															q[emit * cap + ln[emit]] = i; ln[emit] += 1
														}
														if hasSky && !op && y < skyTop && sl > 0 {
															skyP[i] = sl
															ss[sn] = i; sn += 1
														}
													}
													iy += 1
													i += ww
												}
											}
										}
									} else {
										var iy: Int = 0
										var i: Int = ix
										while iy < hh {
											let y: Int = oyy + iy
											opqP[i] = y >= 0
											drP[i] = y >= 0
											if y < 0 && hasSky && sl > 0 {
												skyP[i] = sl
												ss[sn] = i; sn += 1
											}
											iy += 1
											i += ww
										}
									}
									ix += 1
								}
							}
						}
					}
				}
			}
		}
		skyN = sn
		// block light pass (tiles only)
		blk.withUnsafeMutableBufferPointer { p in propagate(p) }
		// sky light pass
		var l1: Int = 0
		while l1 < 16 { lens[l1] = 0; l1 += 1 }
		if sl > 0 {
			var k: Int = 0
			let dst: UnsafeMutablePointer<Int> = queue + sl * qCap
			while k < skyN { dst[k] = skySeed[k]; k += 1 }
			lens[sl] = skyN
		}
		sky.withUnsafeMutableBufferPointer { p in propagate(p) }
		blkBase = blk
		applyDynamic(dyn)
		valid = true
		skyUsed = skyLevel
		dimUsed = world.dim.rawValue
		stamp = world.version
		layoutUsed = world.layoutVersion
		if noteSeen {
			Perf.shared.lightFull += 1
			world.editAny = false
		}
	}

	/// Re-lights only what moving light sources touch: starts from the cached tile light and floods
	/// outward from each source. Far cheaper than a full recompute when only the player moved.
	func applyDynamic(_ dyn: [(Int, Int, Int)]) {
		if blkBase.count != w * h || blkBase.isEmpty { return }
		blk = blkBase
		var l: Int = 0
		while l < 16 { lens[l] = 0; l += 1 }
		var any: Bool = false
		for (dx, dy, lv) in dyn {
			let lx: Int = dx - ox
			let ly: Int = dy - oy
			if lx < 0 || ly < 0 || lx >= w || ly >= h { continue }
			let i: Int = ly * w + lx
			let v: Int = clampI(lv, 0, 15)
			if v > blk[i] {
				blk[i] = v
				queue[v * qCap + lens[v]] = i
				lens[v] += 1
				any = true
			}
		}
		if any { blk.withUnsafeMutableBufferPointer { p in propagate(p) } }
	}

	private func propagate(_ lvb: UnsafeMutableBufferPointer<Int>) {
		guard let lv = lvb.baseAddress else { return }
		let q: UnsafeMutablePointer<Int> = queue
		let ln: UnsafeMutablePointer<Int> = lens
		let cap: Int = qCap
		let ww: Int = w
		let hh: Int = h
		opq.withUnsafeBufferPointer { opb in
			guard let op = opb.baseAddress else { return }
			var l: Int = 15
			while l >= 2 {
				var k: Int = 0
				let nl: Int = l - 1
				let ol: Int = l - 2
				let qa: UnsafeMutablePointer<Int> = q + l * cap
				let qn: UnsafeMutablePointer<Int> = q + nl * cap
				let qo: UnsafeMutablePointer<Int> = q + ol * cap
				while k < ln[l] {
					let ci: Int = qa[k]
					k += 1
					if lv[ci] != l { continue }
					let cy: Int = ci / ww
					let cx: Int = ci - cy * ww
					if cx > 0 {
						let nb: Int = ci - 1
						if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
						else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
					}
					if cx < ww - 1 {
						let nb: Int = ci + 1
						if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
						else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
					}
					if cy > 0 {
						let nb: Int = ci - ww
						if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
						else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
					}
					if cy < hh - 1 {
						let nb: Int = ci + ww
						if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
						else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
						// open air also lights the solid cells diagonally below it, so a block standing
						// on the ground (a cactus, a post) does not leave a dark shaft down its column
						if !op[ci] && ol >= 1 {
							if cx > 0 {
								let dg: Int = nb - 1
								if op[dg] && lv[dg] < ol { lv[dg] = ol; qo[ln[ol]] = dg; ln[ol] += 1 }
							}
							if cx < ww - 1 {
								let dg: Int = nb + 1
								if op[dg] && lv[dg] < ol { lv[dg] = ol; qo[ln[ol]] = dg; ln[ol] += 1 }
							}
						}
					}
				}
				l -= 1
			}
		}
	}

	/// Light level seen at a cell (opaque cells show the light of their brightest open neighbour)
	func level(_ x: Int, _ y: Int) -> (Int, Int) {
		let lx: Int = x - ox
		let ly: Int = y - oy
		if lx < 0 || ly < 0 || lx >= w || ly >= h { return (0, 0) }
		let i: Int = ly * w + lx
		var s: Int = sky[i]
		var b: Int = blk[i]
		if opq[i] {
			if lx > 0 { s = max(s, sky[i - 1]); b = max(b, blk[i - 1]) }
			if lx < w - 1 { s = max(s, sky[i + 1]); b = max(b, blk[i + 1]) }
			if ly > 0 { s = max(s, sky[i - w]); b = max(b, blk[i - w]) }
			if ly < h - 1 { s = max(s, sky[i + w]); b = max(b, blk[i + w]) }
		}
		return (s, b)
	}

	/// Best single brightness 0...15 at a tile (for gameplay checks such as spawning)
	func brightness(_ x: Int, _ y: Int) -> Int {
		let (s, b) = level(x, y)
		return max(s, b)
	}

	private func buildTables(_ ambient: Double, _ nightMix: Double) {
		for s in 0..<16 {
			for b in 0..<16 {
				let sb: Double = lightLUT[s]
				let bb: Double = lightLUT[b]
				let bright: Double = max(max(sb, bb), ambient)
				// never quite pitch black: cave walls stay faintly readable
				let a: Int = max(0, Int((1.0 - bright) * 238.0))
				let skyShare: Double = sb > bb ? 1.0 : 0.0
				let tint: Double = skyShare * nightMix
				let r: Int = Int(3.0 + 9.0 * tint)
				let g: Int = Int(4.0 + 14.0 * tint)
				let bl: Int = Int(9.0 + 44.0 * tint)
				// premultiplied ARGB (the renderer hands these straight to Core Graphics)
				let packed: Int = (a << 24) | ((r * a / 255) << 16) | ((g * a / 255) << 8) | (bl * a / 255)
				darkLUT[s * 16 + b] = UInt32(packed)
				let ga: Double = bb * (1.0 - sb * 0.9) * 0.34
				let gaa: Int = Int(ga * 255.0)
				let gp: Int = (gaa << 24) | ((255 * gaa / 255) << 16) | ((0x96 * gaa / 255) << 8) | (0x3C * gaa / 255)
				glowLUT[s * 16 + b] = UInt32(gp)
			}
		}
	}

	/// Builds the two overlay layers (premultiplied ARGB): darkness and warm glow.
	func buildPixels(_ dark: inout [UInt32], _ glow: inout [UInt32], _ ambient: Double, _ nightMix: Double) {
		let n: Int = w * h
		if dark.count != n { dark = [UInt32](repeating: 0, count: n) }
		if glow.count != n { glow = [UInt32](repeating: 0, count: n) }
		buildTables(ambient, nightMix)
		let ww: Int = w
		let hh: Int = h
		dark.withUnsafeMutableBufferPointer { dB in
			glow.withUnsafeMutableBufferPointer { gB in
				sky.withUnsafeBufferPointer { sB in
					blk.withUnsafeBufferPointer { bB in
						opq.withUnsafeBufferPointer { oB in
							drawn.withUnsafeBufferPointer { drB in
								darkLUT.withUnsafeBufferPointer { dLB in
									glowLUT.withUnsafeBufferPointer { gLB in
										guard let dP = dB.baseAddress, let gP = gB.baseAddress, let sP = sB.baseAddress, let bP = bB.baseAddress,
											  let oP = oB.baseAddress, let drP = drB.baseAddress, let dL = dLB.baseAddress, let gL = gLB.baseAddress else { return }
										var iy: Int = 0
										while iy < hh {
											var ix: Int = 0
											let row: Int = iy * ww
											while ix < ww {
												let i: Int = row + ix
												if !drP[i] {
													dP[i] = 0
													gP[i] = 0
													ix += 1
													continue
												}
												var s: Int = sP[i]
												var b: Int = bP[i]
												if oP[i] {
													if ix > 0 { s = max(s, sP[i - 1]); b = max(b, bP[i - 1]) }
													if ix < ww - 1 { s = max(s, sP[i + 1]); b = max(b, bP[i + 1]) }
													if iy > 0 { s = max(s, sP[i - ww]); b = max(b, bP[i - ww]) }
													if iy < hh - 1 { s = max(s, sP[i + ww]); b = max(b, bP[i + ww]) }
												}
												let k: Int = s * 16 + b
												dP[i] = dL[k]
												gP[i] = gL[k]
												ix += 1
											}
											iy += 1
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

// ===== p12_phys =====

// MARK: - Physics: bodies, collision, projectiles, drops, particles

struct Deck {
	var x0: Double
	var x1: Double
	var y: Double
	var vx: Double
	var id: Int
}

struct Body {
	var x: Double          // centre x
	var y: Double          // feet y (bottom)
	var vx: Double = 0
	var vy: Double = 0
	var w: Double
	var h: Double
	var onGround: Bool = false
	var hitWall: Bool = false
	var hitCeil: Bool = false
	var inWater: Bool = false
	var inLava: Bool = false
	var deck: Int = -1
	var wasOnGround: Bool = false

	init(x: Double, y: Double, w: Double, h: Double) {
		self.x = x
		self.y = y
		self.w = w
		self.h = h
	}

	var left: Double { return x - w * 0.5 }
	var right: Double { return x + w * 0.5 }
	var top: Double { return y - h }
	var cy: Double { return y - h * 0.5 }
}

let gravityG: Double = 34.0
let terminalV: Double = 26.0

extension World {
	// Box queries read chunk storage directly, one column at a time: a column of a chunk is a
	// contiguous run of bytes, so this avoids a full tile(x, y) lookup per cell (the hottest path in
	// physics). Columns outside loaded chunks fall back to tile(x, y).

	/// Finds the first tile in the box whose flag in `table` is set. Returns its raw value or -1.
	private func scanBox(_ tx0: Int, _ ty0: Int, _ tx1: Int, _ ty1: Int, _ table: [Bool]) -> Int {
		// (plain local arrays, no closures: withUnsafeBufferPointer costs more than the scan itself in
		// unoptimised builds)
		let hh: Int = H
		let ya: Int = ty0 > 0 ? ty0 : 0
		let yb: Int = ty1 < hh - 1 ? ty1 : hh - 1
		let tb: [Bool] = table
		var tx: Int = tx0
		while tx <= tx1 {
			let cx: Int = floorDiv(tx, chunkW)
			if let c = chunk(cx) {
				let arr: [UInt8] = c.tiles
				var i: Int = (tx - cx * chunkW) * hh + ya
				var y: Int = ya
				while y <= yb {
					let r: Int = i8(arr[i])
					if tb[r] { return r }
					y += 1
					i += 1
				}
				// rows below the world are bedrock (rows above are air)
				if ty1 >= hh {
					let br: Int = i8(Tile.bedrock.rawValue)
					if tb[br] { return br }
				}
			} else {
				var y2: Int = ty0
				while y2 <= ty1 {
					let r: Int = i8(tile(tx, y2).rawValue)
					if tb[r] { return r }
					y2 += 1
				}
			}
			tx += 1
		}
		return -1
	}

	func boxSolid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		Perf.shared.countBox()
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return false }
		return scanBox(tx0, ty0, tx1, ty1, Tile.solidTable) >= 0
	}

	func boxHurts(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Tile? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		let r: Int = scanBox(tx0, ty0, tx1, ty1, Tile.hurtTable)
		return r >= 0 ? Tile.make(UInt8(truncatingIfNeeded: r)) : nil
	}

	/// Fractions of a box covered by water and by lava, in one pass
	func liquidFractions(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Double, Double) {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return (0, 0) }
		let waterR: UInt8 = Tile.water.rawValue
		let lavaR: UInt8 = Tile.lava.rawValue
		let hh: Int = H
		var w: Int = 0
		var l: Int = 0
		var tx: Int = tx0
		while tx <= tx1 {
			let cx: Int = floorDiv(tx, chunkW)
			if let c = chunk(cx), ty0 >= 0, ty1 < hh {
				let arr: [UInt8] = c.tiles
				var i: Int = (tx - cx * chunkW) * hh + ty0
				var y: Int = ty0
				while y <= ty1 {
					let r: UInt8 = arr[i]
					if r == waterR { w += 1 } else if r == lavaR { l += 1 }
					y += 1
					i += 1
				}
			} else {
				for y in ty0...ty1 {
					let t: Tile = tile(tx, y)
					if t == .water { w += 1 } else if t == .lava { l += 1 }
				}
			}
			tx += 1
		}
		let n: Double = Double((tx1 - tx0 + 1) * (ty1 - ty0 + 1))
		return (Double(w) / n, Double(l) / n)
	}

	func liquidFraction(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ lava: Bool) -> Double {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return 0 }
		var n: Int = 0
		var m: Int = 0
		for ty in ty0...ty1 {
			for tx in tx0...tx1 {
				m += 1
				let t: Tile = tile(tx, ty)
				if lava { if t == .lava { n += 1 } } else if t == .water { n += 1 }
			}
		}
		return m > 0 ? Double(n) / Double(m) : 0
	}

	// MARK: stairs
	// A stair tile is not solid; it has two solid parts instead: a full-width lower step (its bottom
	// half) and an upper step on its high side (top half, the right half for R, the left for L).
	// Bodies collide with those parts, and step up half a tile at a time.

	func stairAt(_ x: Int, _ y: Int) -> UInt8 {
		if y < 0 || y >= H { return 0 }
		return Tile.stairTable[Int(tile(x, y).rawValue)]
	}

	/// Whether any stairs stand in the loaded chunks covering columns x0...x1 (counted once per chunk)
	func stairsNear(_ x0: Double, _ x1: Double) -> Bool {
		var cx: Int = floorDiv(Int(floor(x0)), chunkW)
		let c1: Int = floorDiv(Int(floor(x1)), chunkW)
		while cx <= c1 {
			if let c = chunk(cx) {
				if c.stairs < 0 {
					var n: Int = 0
					for r in c.tiles where Tile.stairTable[Int(r)] != 0 { n += 1 }
					c.stairs = n
				}
				if c.stairs > 0 { return true }
			}
			cx += 1
		}
		return false
	}

	/// Whether a box overlaps the solid part of any stair
	func stairHit(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return false }
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let fx: Double = Double(tx)
				let fy: Double = Double(ty)
				// the lower step, full width
				if y1 > fy + 0.5 && y0 < fy + 1.0 { return true }
				// the upper step, on the high side
				let hx: Double = s == 1 ? fx + 0.5 : fx
				if y1 > fy && y0 < fy + 0.5 && x1 > hx && x0 < hx + 0.5 { return true }
			}
		}
		return false
	}

	/// Solid tiles, and the solid parts of stairs when there are any about
	func boxBlocked(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ stairs: Bool) -> Bool {
		if boxSolid(x0, y0, x1, y1) { return true }
		return stairs && stairHit(x0, y0, x1, y1)
	}

	/// The first stair top a body's feet meet coming down from prevY to ny over x0...x1
	func stairLanding(_ x0: Double, _ x1: Double, _ prevY: Double, _ ny: Double) -> Double? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(prevY - 0.001))
		let ty1: Int = Int(floor(ny + 0.0005))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		var best: Double? = nil
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let low: Double = Double(ty) + 0.5
				if low >= prevY - 0.001 && low <= ny + 0.0005 { best = min(best ?? low, low) }
				let hx: Double = s == 1 ? Double(tx) + 0.5 : Double(tx)
				if x1 > hx + 0.001 && x0 < hx + 0.499 {
					let up: Double = Double(ty)
					if up >= prevY - 0.001 && up <= ny + 0.0005 { best = min(best ?? up, up) }
				}
			}
		}
		return best
	}

	/// The first stair underside a body's head meets going up from prevTop to newTop over x0...x1
	func stairCeiling(_ x0: Double, _ x1: Double, _ prevTop: Double, _ newTop: Double) -> Double? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(newTop)) - 1
		let ty1: Int = Int(floor(prevTop))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		var best: Double? = nil
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let low: Double = Double(ty) + 1.0
				if low <= prevTop + 0.001 && low >= newTop - 0.0005 { best = max(best ?? low, low) }
				let hx: Double = s == 1 ? Double(tx) + 0.5 : Double(tx)
				if x1 > hx + 0.001 && x0 < hx + 0.499 {
					let up: Double = Double(ty) + 0.5
					if up <= prevTop + 0.001 && up >= newTop - 0.0005 { best = max(best ?? up, up) }
				}
			}
		}
		return best
	}

	/// Moves a body with gravity-free integration; the caller sets vx/vy. Collides with solid tiles,
	/// stairs, one-way platforms and decks. stepUp = max ledge height (tiles) climbed automatically
	/// (half a tile at a time on stairs).
	func moveBody(_ b: inout Body, _ dt: Double, stepUp: Double, dropThrough: Bool, decks: [Deck]) {
		Perf.shared.countMove()
		b.wasOnGround = b.onGround
		b.hitWall = false
		b.hitCeil = false
		b.onGround = false
		b.deck = -1
		let speed: Double = max(abs(b.vx), abs(b.vy))
		let steps: Int = max(1, Int(ceil(speed * dt / 0.3)))
		let sdt: Double = dt / Double(steps)
		let hw: Double = b.w * 0.5
		let st: Bool = stairsNear(b.x - hw - 1.0, b.x + hw + 1.0)
		let liftStep: Double = st ? 0.5 : 1.0
		// unstick: if inside solid, push upward
		if boxBlocked(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02, st) {
			var k: Int = 0
			while k < (st ? 12 : 6) && boxBlocked(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02, st) {
				b.y -= liftStep
				k += 1
			}
		}
		for _ in 0..<steps {
			// horizontal
			if b.vx != 0 {
				let nx: Double = b.x + b.vx * sdt
				if !boxBlocked(nx - hw, b.y - b.h + 0.001, nx + hw, b.y - 0.001, st) {
					b.x = nx
				} else {
					var done: Bool = false
					if (b.wasOnGround || b.onGround) && stepUp > 0 {
						var lift: Double = liftStep
						while lift <= stepUp + 0.001 && !done {
							if !boxBlocked(nx - hw, b.y - lift - b.h + 0.001, nx + hw, b.y - lift - 0.001, st) {
								b.x = nx
								b.y -= lift
								done = true
							}
							lift += liftStep
						}
					}
					if !done {
						b.hitWall = true
						b.vx = 0
					}
				}
			}
			// vertical
			do {
				let prevY: Double = b.y
				let ny: Double = b.y + b.vy * sdt
				if b.vy >= 0 {
					var landed: Bool = false
					var landY: Double = ny
					if boxSolid(b.x - hw, ny - b.h + 0.001, b.x + hw, ny + 0.0005) {
						// find top of the colliding row at feet
						landY = floor(ny + 0.0005)
						if landY < prevY - 0.0001 { landY = prevY }
						if st, let sl = stairLanding(b.x - hw, b.x + hw, prevY, ny), sl < landY { landY = max(sl, prevY) }
						landed = true
					} else if st, let sl = stairLanding(b.x - hw, b.x + hw, prevY, ny) {
						landed = true
						landY = sl
					} else {
						// platforms
						let rowF: Int = Int(floor(ny + 0.0005))
						if !dropThrough {
							let tx0: Int = Int(floor(b.x - hw))
							let tx1: Int = Int(floor(b.x + hw - 0.0001))
							if tx1 >= tx0 {
								for tx in tx0...tx1 {
									if tile(tx, rowF).isPlatform && prevY <= Double(rowF) + 0.001 && ny >= Double(rowF) - 0.0001 {
										landed = true
										landY = Double(rowF)
									}
								}
							}
						}
						if !landed {
							for (i, d) in decks.enumerated() {
								if b.x + hw > d.x0 && b.x - hw < d.x1 && prevY <= d.y + 0.06 && ny >= d.y - 0.0001 && !dropThrough {
									landed = true
									landY = d.y
									b.deck = i
								}
							}
						}
					}
					if landed {
						b.y = landY
						b.vy = 0
						b.onGround = true
					} else {
						b.y = ny
					}
				} else {
					if boxSolid(b.x - hw, ny - b.h, b.x + hw, ny - 0.001) {
						let ceilRow: Double = floor(ny - b.h) + 1.0
						b.y = ceilRow + b.h
						b.vy = 0
						b.hitCeil = true
					} else if st, let sc = stairCeiling(b.x - hw, b.x + hw, prevY - b.h, ny - b.h) {
						b.y = sc + b.h
						b.vy = 0
						b.hitCeil = true
					} else {
						b.y = ny
					}
				}
			}
		}
		// liquids
		let lf: (Double, Double) = liquidFractions(b.x - hw, b.y - b.h, b.x + hw, b.y)
		b.inWater = lf.0 > 0.35
		b.inLava = lf.1 > 0.2
	}

}

// MARK: - Projectiles

enum ProjKind: Int, Codable {
	case arrow, bullet, fireball, rock, shock, spit, bolt, bomb
	/// a crystal shard thrown by the Crystal Sentinel
	case shard
	/// the player's crossbow bolt, a blunderbuss pellet, a slung stone and a thrown fire flask
	case quarrel, pellet, pebble, flask
}

struct Projectile {
	var kind: ProjKind
	var x: Double
	var y: Double
	var vx: Double
	var vy: Double
	var dmg: Double
	var fromPlayer: Bool
	var life: Double = 4.0
	var stuck: Double = 0
	var gravity: Double
	var owner: Int = -1
	var pierce: Int = 0
	var hit: Bool = false
	var w: Double = 0.3
	/// who fired it (decides what it may hurt and who gets the kill)
	var source: DamageSource = DamageSource.environment
	/// attack instance id for damage cooldowns
	var uid: Int = 0
	/// id of the last creature it passed through (piercing shots)
	var lastHit: Int = -1
	var stuckAngle: Double = 0
	var trail: Int = 0
	/// knockback on hit (0: the kind's usual push)
	var knock: Double = 0
	/// a shot from a mod (index into ModRuntime.shots; -1 for the game's own shots)
	var mod: Int = -1
	/// a thrown potion (its number; -1: a fire flask or any other shot)
	var potion: Int = -1
	/// infusions of the weapon that fired it: 1 fire, 2 frost, 4 volatile, 8 voidrend
	var inf: Int = 0
	/// its custom infusions (their numbers)
	var custom: [Int] = []
	var angle: Double { return atan2(vy, vx) }
}

// MARK: - Drops and particles

struct DropItem {
	var stack: Stack
	var x: Double
	var y: Double
	var vx: Double
	var vy: Double
	var age: Double = 0
	var pickDelay: Double = 0.5
	var onGround: Bool = false
	/// thrown away by the player: it is not picked up again until the player has walked off from it
	var heldBack: Bool = false
}

struct Particle {
	var x: Double
	var y: Double
	var vx: Double
	var vy: Double
	var life: Double
	var maxLife: Double
	var color: UInt32
	var size: Double
	var gravity: Double
}

struct FloatText {
	var x: Double
	var y: Double
	var text: String
	var life: Double
	var color: UInt32
}

// ===== p13a_mobdefs =====

// MARK: - Mob definitions

enum MobKind: Int, Codable, CaseIterable {
	case pig, cow, sheep, chicken, crow, giraffe, frog, fish
	case elephant, bear, grizzly, polarBear, tiger, wolf, cat
	case zombie, skeleton, slime, bat, scorpion, wraith
	case villager, pirate, pirateGunner, pirateCaptain
	case imp, emberSlime, cinderBat
	case bearBoss, rex
	/// appended, so saved creature kinds keep their numbers
	case crawler, golem, archer, sentinel, mimic, warden
	/// a creature from a player's mod (which one: `Mob.cslot`, see ModRuntime)
	case custom

	/// wild hunters that roam by day as well: they have their own small number in the spawner, so
	/// they never use up the night's monsters
	var isPredator: Bool { return self == .grizzly || self == .polarBear || self == .tiger || self == .scorpion }

	/// monsters run by `think` (senses, memory, chase, search, return) around their own attacks
	var thinks: Bool {
		switch self {
		case .zombie, .skeleton, .pirate, .pirateCaptain, .pirateGunner, .imp, .slime, .emberSlime,
			 .bat, .cinderBat, .wraith, .crawler, .golem, .archer, .custom: return true
		default: return false
		}
	}
}

enum Behavior: Int {
	case passive, skittish, defensive, hostile, ranged, flyer, swimmer, boss
}

struct MobDef {
	var name: String
	var w: Double
	var h: Double
	var hp: Double
	var speed: Double
	var dmg: Double
	var behavior: Behavior
	var flying: Bool = false
	var aggro: Double = 14
	var jump: Double = 12
	var hostile: Bool = false
}

/// Mob definitions are built once into a table: building a MobDef (it holds a String) on every
/// lookup was one of the hottest calls in the AI loop in debug builds.
var mobDefTable: [MobDef] = MobKind.allCases.map { makeMobDef($0) }

@inline(__always) func mobDef(_ k: MobKind) -> MobDef { return mobDefTable[k.rawValue] }

func makeMobDef(_ k: MobKind) -> MobDef {
	switch k {
	case .pig: return MobDef(name: "Pig", w: 0.9, h: 0.7, hp: 10, speed: 1.6, dmg: 0, behavior: .passive)
	case .cow: return MobDef(name: "Cow", w: 1.3, h: 1.1, hp: 14, speed: 1.4, dmg: 0, behavior: .passive)
	case .sheep: return MobDef(name: "Sheep", w: 1.1, h: 0.95, hp: 12, speed: 1.5, dmg: 0, behavior: .passive)
	case .chicken: return MobDef(name: "Chicken", w: 0.6, h: 0.6, hp: 5, speed: 1.8, dmg: 0, behavior: .skittish)
	case .crow: return MobDef(name: "Crow", w: 0.6, h: 0.5, hp: 4, speed: 3.6, dmg: 0, behavior: .flyer, flying: true)
	case .giraffe: return MobDef(name: "Giraffe", w: 1.6, h: 3.2, hp: 30, speed: 3.4, dmg: 0, behavior: .skittish)
	case .frog: return MobDef(name: "Frog", w: 0.5, h: 0.4, hp: 3, speed: 2.0, dmg: 0, behavior: .skittish, jump: 9)
	case .fish: return MobDef(name: "Fish", w: 0.7, h: 0.4, hp: 3, speed: 2.2, dmg: 0, behavior: .swimmer)
	case .elephant: return MobDef(name: "Elephant", w: 2.8, h: 2.4, hp: 80, speed: 2.4, dmg: 7, behavior: .defensive, aggro: 10)
	case .bear: return MobDef(name: "Brown Bear", w: 1.8, h: 1.2, hp: 42, speed: 2.8, dmg: 5, behavior: .defensive, aggro: 11)
	case .grizzly: return MobDef(name: "Grizzly Bear", w: 2.0, h: 1.4, hp: 70, speed: 3.4, dmg: 7, behavior: .hostile, aggro: 12, hostile: true)
	case .polarBear: return MobDef(name: "Polar Bear", w: 2.0, h: 1.4, hp: 64, speed: 3.2, dmg: 7, behavior: .hostile, aggro: 12, hostile: true)
	case .tiger: return MobDef(name: "Tiger", w: 1.7, h: 1.0, hp: 48, speed: 4.6, dmg: 6, behavior: .hostile, aggro: 14, jump: 15, hostile: true)
	case .wolf: return MobDef(name: "Wolf", w: 1.2, h: 0.9, hp: 24, speed: 4.0, dmg: 3, behavior: .defensive, aggro: 11, jump: 14)
	case .cat: return MobDef(name: "Cat", w: 0.7, h: 0.6, hp: 10, speed: 3.0, dmg: 0, behavior: .skittish, jump: 13)
	case .zombie: return MobDef(name: "Zombie", w: 0.7, h: 1.7, hp: 30, speed: 1.8, dmg: 4, behavior: .hostile, aggro: 16, hostile: true)
	case .skeleton: return MobDef(name: "Skeleton Knight", w: 0.7, h: 1.8, hp: 38, speed: 2.1, dmg: 5, behavior: .hostile, aggro: 15, hostile: true)
	case .slime: return MobDef(name: "Slime", w: 0.9, h: 0.7, hp: 18, speed: 2.6, dmg: 3, behavior: .hostile, aggro: 12, jump: 11, hostile: true)
	case .bat: return MobDef(name: "Cave Bat", w: 0.6, h: 0.4, hp: 6, speed: 4.2, dmg: 2, behavior: .flyer, flying: true, aggro: 12, hostile: true)
	case .scorpion: return MobDef(name: "Scorpion", w: 1.2, h: 0.6, hp: 26, speed: 2.6, dmg: 4, behavior: .hostile, aggro: 11, hostile: true)
	case .wraith: return MobDef(name: "Wraith", w: 0.9, h: 1.5, hp: 44, speed: 2.8, dmg: 6, behavior: .flyer, flying: true, aggro: 18, hostile: true)
	case .villager: return MobDef(name: "Villager", w: 0.7, h: 1.7, hp: 20, speed: 1.4, dmg: 0, behavior: .passive)  // retired: never spawns
	case .pirate: return MobDef(name: "Pirate", w: 0.7, h: 1.8, hp: 48, speed: 2.5, dmg: 6, behavior: .hostile, aggro: 20, hostile: true)
	case .pirateGunner: return MobDef(name: "Pirate Gunner", w: 0.7, h: 1.8, hp: 40, speed: 1.9, dmg: 5, behavior: .ranged, aggro: 20, hostile: true)
	case .pirateCaptain: return MobDef(name: "Pirate Captain", w: 0.8, h: 1.9, hp: 140, speed: 2.5, dmg: 8, behavior: .hostile, aggro: 22, hostile: true)
	case .imp: return MobDef(name: "Umbral Imp", w: 0.7, h: 1.5, hp: 34, speed: 2.6, dmg: 5, behavior: .ranged, aggro: 18, hostile: true)
	case .emberSlime: return MobDef(name: "Ember Slime", w: 1.0, h: 0.8, hp: 36, speed: 2.8, dmg: 5, behavior: .hostile, aggro: 12, jump: 12, hostile: true)
	case .cinderBat: return MobDef(name: "Cinder Bat", w: 0.6, h: 0.4, hp: 14, speed: 4.6, dmg: 4, behavior: .flyer, flying: true, aggro: 14, hostile: true)
	case .bearBoss: return MobDef(name: "Ursavor, Warden of the Gate", w: 5.2, h: 3.9, hp: 900, speed: 3.0, dmg: 10, behavior: .boss, aggro: 60, hostile: true)
	case .rex: return MobDef(name: "Tyrannax the Bonecrown", w: 7.0, h: 4.4, hp: 1400, speed: 3.4, dmg: 13, behavior: .boss, aggro: 60, hostile: true)
	case .crawler: return MobDef(name: "Cave Crawler", w: 1.1, h: 0.6, hp: 22, speed: 4.4, dmg: 4, behavior: .hostile, aggro: 13, jump: 11.5, hostile: true)
	case .golem: return MobDef(name: "Stone Golem", w: 1.5, h: 2.2, hp: 150, speed: 1.15, dmg: 8, behavior: .hostile, aggro: 12, jump: 9, hostile: true)
	case .archer: return MobDef(name: "Bow Zombie", w: 0.7, h: 1.7, hp: 30, speed: 2.3, dmg: 4, behavior: .ranged, aggro: 20, hostile: true)
	case .sentinel: return MobDef(name: "Crystal Sentinel", w: 1.4, h: 2.0, hp: 320, speed: 3.0, dmg: 7, behavior: .boss, flying: true, aggro: 30, hostile: true)
	case .mimic: return MobDef(name: "Mimic", w: 1.0, h: 0.95, hp: 90, speed: 3.2, dmg: 7, behavior: .hostile, aggro: 16, jump: 12, hostile: true)
	case .warden: return MobDef(name: "The Hollow Warden", w: 3.0, h: 4.6, hp: 2200, speed: 2.6, dmg: 11, behavior: .boss, flying: true, aggro: 60, hostile: true)
	case .custom: return MobDef(name: "Custom Creature", w: 0.8, h: 1.6, hp: 20, speed: 2, dmg: 4, behavior: .hostile, hostile: true)
	}
}

// MARK: - Drops

func mobDrops(_ k: MobKind, _ rng: inout RNG, _ sheared: Bool) -> [Stack] {
	var out: [Stack] = []
	func add(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
		if rng.double() < p { out.append(Stack(item: it, count: lo + rng.int(max(1, hi - lo + 1)))) }
	}
	switch k {
	case .pig: add(.food(.rawMeat), 1, 3, 1.0)
	case .cow: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 2, 0.8)
	case .sheep: add(.food(.rawMeat), 1, 2, 1.0); if !sheared { add(.mat(.wool), 1, 3, 0.9) }
	case .chicken: add(.food(.rawMeat), 1, 1, 0.9); add(.mat(.feather), 1, 3, 0.9)
	case .crow: add(.mat(.feather), 1, 2, 0.8)
	case .giraffe: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 2, 4, 0.9)
	case .frog: add(.mat(.string), 0, 1, 0.1)
	case .fish: add(.food(.rawFish), 1, 1, 1.0)
	case .elephant: add(.food(.rawMeat), 4, 7, 1.0); add(.mat(.tusk), 1, 2, 0.8); add(.mat(.leather), 2, 4, 0.9)
	case .bear: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.fur), 1, 3, 0.9); add(.mat(.claw), 1, 1, 0.3)
	case .grizzly: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.6)
	case .polarBear: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.5)
	case .tiger: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 3, 0.9); add(.mat(.claw), 1, 2, 0.6)
	case .wolf: add(.food(.rawMeat), 1, 2, 0.9); add(.mat(.fur), 1, 2, 0.6); add(.mat(.bone), 1, 2, 0.4)
	case .cat: add(.mat(.string), 1, 2, 0.5)
	case .zombie: add(.food(.rawMeat), 0, 1, 0.3); add(.mat(.string), 0, 2, 0.3); add(.food(.carrot), 1, 1, 0.08); add(.mat(.ironBar), 1, 1, 0.04)
	case .skeleton: add(.mat(.bone), 1, 3, 0.9); add(.ammo(.arrow), 2, 6, 0.5); add(.sword(.stone), 1, 1, 0.06); add(.mat(.coal), 1, 3, 0.4)
	case .slime: add(.mat(.string), 1, 2, 0.4); add(.block(.torch), 1, 3, 0.3)
	case .bat: add(.mat(.string), 0, 1, 0.2)
	case .scorpion: add(.mat(.claw), 1, 1, 0.5); add(.food(.rawMeat), 1, 1, 0.5)
	case .wraith: add(.mat(.mythrilOre), 1, 2, 0.4); add(.mat(.goldBar), 1, 2, 0.3)
	case .villager: break
	case .pirate: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 2, 6, 0.4); add(.mat(.gunpowder), 1, 3, 0.5); add(.sword(.iron), 1, 1, 0.1); add(.gadget(.bomb), 1, 2, 0.15)
	case .pirateGunner: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 3, 8, 0.7); add(.mat(.gunpowder), 1, 4, 0.7); add(.gun(.pistol), 1, 1, 0.12)
	case .pirateCaptain: add(.mat(.goldBar), 4, 8, 1.0); add(.mat(.diamond), 1, 3, 0.8); add(.gun(.rifle), 1, 1, 0.4); add(.ammo(.bullet), 8, 16, 1.0)
	case .imp: add(.mat(.emberOre), 1, 2, 0.5); add(.mat(.coal), 2, 4, 0.6)
	case .emberSlime: add(.mat(.emberOre), 1, 3, 0.6); add(.block(.torch), 2, 5, 0.5)
	case .cinderBat: add(.mat(.emberOre), 0, 1, 0.3)
	case .bearBoss:
		add(.mat(.fur), 6, 10, 1.0); add(.mat(.claw), 3, 5, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
		add(.mat(.diamond), 3, 6, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
		add(.armor(.chest, .gold), 1, 1, 0.5)
	case .rex:
		add(.mat(.bone), 10, 20, 1.0); add(.mat(.tusk), 2, 4, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
		add(.mat(.mythrilBar), 2, 5, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
	case .crawler: add(.mat(.string), 1, 3, 0.8); add(.mat(.claw), 1, 1, 0.25)
	case .golem:
		add(.block(.stone), 4, 8, 1.0); add(.mat(.ironOre), 1, 3, 0.6); add(.mat(.crystalShard), 1, 2, 0.35)
		add(.mat(.relicFragment), 1, 1, 0.1)
	case .archer: add(.food(.rawMeat), 0, 1, 0.3); add(.mat(.string), 0, 2, 0.4); add(.ammo(.arrow), 3, 8, 0.8); add(.bow, 1, 1, 0.05)
	case .sentinel:
		add(.mat(.crystalShard), 8, 14, 1.0); add(.mat(.diamond), 2, 4, 1.0); add(.block(.glowCrystal), 4, 8, 1.0)
		add(.mat(.relicFragment), 2, 3, 1.0); add(.gear(.headlamp), 1, 1, 0.35)
	case .mimic: add(.mat(.goldBar), 2, 5, 1.0); add(.mat(.relicFragment), 1, 1, 0.8); add(.mat(.diamond), 1, 2, 0.35)
	case .warden:
		add(.mat(.umbralHeart), 1, 1, 1.0); add(.mat(.voidBar), 6, 10, 1.0); add(.mat(.diamond), 4, 8, 1.0)
		add(.mat(.emberBar), 4, 8, 1.0); add(.mat(.relicFragment), 3, 3, 1.0)
	case .custom:
		// a custom creature's drops come from its mod (see dropModLoot)
		break
	}
	return out
}

// MARK: - Spawn rules

enum SpawnPlace { case surface, cave, ocean, umbral }
enum SpawnWhen { case any, day, night }

struct SpawnRule {
	var kind: MobKind
	var weight: Double
	var place: SpawnPlace
	var when: SpawnWhen
	var biomes: [Biome]
	var group: Int
	var minY: Int = 0
	var maxY: Int = 9999
	/// a custom creature's slot (-1 for the game's creatures), how many of it may be about at once, and
	/// whether it appears high in the sky
	var slot: Int = -1
	var maxNearby: Int = 99
	var sky: Bool = false
}

let spawnRules: [SpawnRule] = [
	// surface, passive and wild animals by biome
	SpawnRule(kind: .pig, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
	SpawnRule(kind: .cow, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
	SpawnRule(kind: .sheep, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest, .mountain], group: 3),
	SpawnRule(kind: .chicken, weight: 4, place: .surface, when: .day, biomes: [.plains, .forest, .savanna], group: 3),
	SpawnRule(kind: .crow, weight: 3, place: .surface, when: .any, biomes: [.plains, .forest, .desert, .savanna, .swamp, .mountain], group: 2),
	SpawnRule(kind: .giraffe, weight: 5, place: .surface, when: .any, biomes: [.savanna], group: 2),
	SpawnRule(kind: .elephant, weight: 3, place: .surface, when: .any, biomes: [.savanna, .jungle], group: 1),
	SpawnRule(kind: .tiger, weight: 3, place: .surface, when: .any, biomes: [.jungle, .savanna], group: 1),
	SpawnRule(kind: .bear, weight: 3, place: .surface, when: .any, biomes: [.forest, .mountain], group: 1),
	SpawnRule(kind: .grizzly, weight: 2, place: .surface, when: .any, biomes: [.mountain, .forest], group: 1),
	SpawnRule(kind: .polarBear, weight: 4, place: .surface, when: .any, biomes: [.tundra], group: 1),
	SpawnRule(kind: .wolf, weight: 3, place: .surface, when: .night, biomes: [.tundra, .forest, .plains], group: 3),
	SpawnRule(kind: .frog, weight: 5, place: .surface, when: .any, biomes: [.swamp], group: 2),
	SpawnRule(kind: .scorpion, weight: 5, place: .surface, when: .any, biomes: [.desert], group: 1),
	// surface hostile
	SpawnRule(kind: .zombie, weight: 7, place: .surface, when: .night, biomes: [], group: 2),
	SpawnRule(kind: .slime, weight: 3, place: .surface, when: .night, biomes: [.plains, .forest, .jungle, .swamp], group: 1),
	// oceans
	SpawnRule(kind: .fish, weight: 8, place: .ocean, when: .any, biomes: [], group: 4),
	// caves
	SpawnRule(kind: .skeleton, weight: 6, place: .cave, when: .any, biomes: [], group: 2, minY: 150),
	SpawnRule(kind: .zombie, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 140),
	SpawnRule(kind: .slime, weight: 3, place: .cave, when: .any, biomes: [], group: 2, minY: 140),
	SpawnRule(kind: .bat, weight: 4, place: .cave, when: .any, biomes: [], group: 3, minY: 150),
	SpawnRule(kind: .wraith, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 380),
	SpawnRule(kind: .crawler, weight: 4, place: .cave, when: .any, biomes: [], group: 2, minY: 140),
	SpawnRule(kind: .archer, weight: 3, place: .cave, when: .any, biomes: [], group: 1, minY: 150),
	SpawnRule(kind: .golem, weight: 1.5, place: .cave, when: .any, biomes: [], group: 1, minY: 260),
	SpawnRule(kind: .archer, weight: 2, place: .surface, when: .night, biomes: [], group: 1),
	SpawnRule(kind: .skeleton, weight: 2, place: .surface, when: .night, biomes: [.plains, .desert, .tundra, .mountain, .savanna], group: 1),
	SpawnRule(kind: .crawler, weight: 2, place: .surface, when: .night, biomes: [.jungle, .swamp, .forest], group: 2),
	// umbral realm
	SpawnRule(kind: .imp, weight: 5, place: .umbral, when: .any, biomes: [], group: 1),
	SpawnRule(kind: .wraith, weight: 3, place: .umbral, when: .any, biomes: [], group: 1),
	SpawnRule(kind: .emberSlime, weight: 5, place: .umbral, when: .any, biomes: [], group: 2),
	SpawnRule(kind: .cinderBat, weight: 4, place: .umbral, when: .any, biomes: [], group: 3)
]

// MARK: - Mob instance

final class Mob {
	let id: Int
	var kind: MobKind
	var b: Body
	var hp: Double
	var maxHP: Double
	var dir: Int = 1
	var anim: Double = 0
	var hurtT: Double = 0
	var cd: Double = 0
	var t1: Double = 0
	var t2: Double = 0
	var t3: Double = 0
	var st: Int = 0
	var variant: Int = 0
	var tame: Bool = false
	var angry: Bool = false
	var persistent: Bool = false
	var sheared: Bool = false
	var blocking: Bool = false
	var boat: Int = -1
	var raiding: Bool = false
	var burn: Double = 0
	var stuckT: Double = 0
	var lastX: Double = 0
	var homeX: Double = 0
	var homeY: Double = 0
	var mounted: Bool = false
	var downed: Bool = false
	var lair: Int = 0
	var phase: Int = 0
	var tele: Double = 0
	var atk: Int = 0
	var tx: Double = 0
	var ty: Double = 0
	var regrow: Double = 0
	var knock: Double = 0
	/// time folded in while far-away AI updates were skipped
	var aiAccum: Double = 0
	/// set when the mob should leave the list at the end of the frame
	var removed: Bool = false
	/// white hit flash, death animation and knockback lean
	var flash: Double = 0
	var deathT: Double = -1
	var lean: Double = 0
	/// hazard and damage bookkeeping (see the damage system)
	var hazardT: Double = 0
	var lastAttacker: Int = 0
	var lastHitByPlayer: Double = -100
	var hitStamps: [Int: Double] = [:]
	var fallPeak: Double = 0
	var burnTick: Double = 0
	/// facing shown on screen, the turn animation and the attack lunge (visual only; the AI uses `dir`)
	var face: Int = 0
	var turnT: Double = 0
	var atkT: Double = 0
	/// a mimic's hoard (dropped when it dies) and the spots a telegraphed attack will strike
	var loot: [Stack] = []
	var spots: [Double] = []
	/// animal life: when to look around next, a place it is heading for (1 water, 2 its herd),
	/// a thirst timer, the prey it is hunting and a pose to hold (grazing, drinking)
	var thinkT: Double = 0
	/// boss attack variety: the last attack, how often in a row, and attacks since the signature move
	var lastAtk: Int = 0
	var repeatN: Int = 0
	var sinceSignature: Int = 0
	var goal: Int = 0
	var goalX: Double = 0
	var drinkT: Double = 0
	var preyID: Int = 0
	weak var prey: Mob? = nil
	var poseT: Double = 0
	/// dazed by a club: stands reeling, then can't be dazed again for a moment
	var daze: Double = 0
	var dazeGuard: Double = 0
	/// hostile AI (see `think`): its state and how long it has been in it, whether it can see the
	/// player (rechecked a few times a second), where it last saw them and how long ago, where it is
	/// heading, how long it has been pushing against a wall, and why it did not attack (for the overlay)
	var ai: MobAI = .idle
	var aiT: Double = 0
	var sees: Bool = false
	var losT: Double = 0
	var seenX: Double = 0
	var seenY: Double = 0
	var lostT: Double = 99
	var aimX: Double = 0
	var blockedT: Double = 0
	var progX: Double = 0
	var leapT: Double = 0
	var leapReq: Bool = false
	var why: AttackBlock = .none
	/// came out at night to look for the player; how long it has been far away and forgotten
	var hunter: Bool = false
	var farT: Double = 0
	/// a custom creature's slot in ModRuntime.mobs (-1 for the game's own creatures)
	var cslot: Int = -1
	/// custom creatures: each attack's cooldown, the creature it guards, the monster it fights or runs
	/// from (and timers for looking for them), its home biome, the blow under way (its key, target and
	/// whether that is the player) and how long a water creature has been on land
	var modCD: [Double] = []
	weak var ward: Mob? = nil
	var wardT: Double = 0
	weak var foe: Mob? = nil
	weak var threat: Mob? = nil
	var foeT: Double = 0
	var homeBiome: Int = -1
	var biomeT: Double = 0
	var strayed: Bool = false
	var atkKey: Int = 0
	var atkX: Double = 0
	var atkY: Double = 0
	var vsPlayer: Bool = true
	var dryT: Double = 0
	/// potion effects: slowed (by how much), poisoned (damage a second, and whether the player gets the
	/// credit), weakened, regenerating; and their timers
	var slowT: Double = 0
	var slowAmt: Double = 0
	var poisonT: Double = 0
	var poisonDps: Double = 0
	var poisonTick: Double = 0
	var poisonByPlayer: Bool = false
	var weakT: Double = 0
	var regenT: Double = 0
	var regenRate: Double = 0
	var regenAcc: Double = 0
	/// mutation: doses taken, the size its body has grown to and how much harder it hits
	var mut: Int = 0
	var mutSize: Double = 1
	var mutDmg: Double = 1
	/// custom creatures' fights (Mod Creator phases): the phase it is in (0: none yet) and its numbers
	/// there, how long it can't be hurt, how long it has been fighting, how many helpers it has called,
	/// the creature it helps (its id), whether a summoning called it, and how long the player has been gone
	var mphase: Int = 0
	var phaseSpeed: Double = 1
	var phaseDmg: Double = 1
	var phaseCD: Double = 1
	var phaseDef: Double = 0
	var phaseShield: Double = 0
	var fightT: Double = 0
	var helpersCalled: Int = 0
	var helperOf: Int = -1
	var summoned: Bool = false
	var leaveT: Double = 0
	static let turnDur: Double = 0.14
	static let atkDur: Double = 0.28

	init(id: Int, kind: MobKind, x: Double, y: Double) {
		self.id = id
		self.kind = kind
		let d: MobDef = mobDef(kind)
		self.b = Body(x: x, y: y, w: d.w, h: d.h)
		self.hp = d.hp
		self.maxHP = d.hp
		self.homeX = x
		self.homeY = y
		self.lastX = x
		self.dir = Int.random(in: 0...1) == 0 ? -1 : 1
		self.t1 = Double.random(in: 0.5...3.0)
	}

	var def: MobDef {
		if kind == .custom, let r = ModRuntime.shared.mob(cslot) { return r.mdef }
		return mobDef(kind)
	}
	var x: Double { return b.x }
	var y: Double { return b.y }
	/// a boss or guardian kind (worked out once: this is checked for every creature every frame)
	private(set) lazy var bossKind: Bool = Mob.isBossKind(kind, cslot)
	/// bosses never become tame, except the T-rex, which then stops being one
	var isBoss: Bool { return bossKind && !tame }

	static func isBossKind(_ k: MobKind, _ slot: Int) -> Bool {
		switch k {
		case .bearBoss, .rex, .sentinel, .warden: return true
		case .custom: return ModRuntime.shared.mob(slot)?.boss ?? false
		default: return false
		}
	}
}

/// What a hostile creature is doing. Attack and recover come from its attack routine (a wind-up, the
/// blow, the moment after); the rest are decided by `think`.
enum MobAI: UInt8 {
	case idle, alert, chase, search, back, retreat
	var name: String {
		switch self {
		case .idle: return "idle"
		case .alert: return "alert"
		case .chase: return "chase"
		case .search: return "search"
		case .back: return "return"
		case .retreat: return "regroup"
		}
	}
}

/// Why a creature that wants to hit the player has not (shown by the AI overlay)
enum AttackBlock: UInt8 {
	case none, notSeen, outOfRange, cooldown, noSight, tooHigh, blocked, peaceful, playerGone
	var name: String {
		switch self {
		case .none: return ""
		case .notSeen: return "hasn't seen you"
		case .outOfRange: return "out of range"
		case .cooldown: return "cooling down"
		case .noSight: return "no line of sight"
		case .tooHigh: return "can't reach that height"
		case .blocked: return "path blocked"
		case .peaceful: return "peaceful"
		case .playerGone: return "player dead"
		}
	}
}

struct MobSave: Codable {
	var kind: Int
	var x: Double
	var y: Double
	var hp: Double
	var maxHP: Double
	var tame: Bool
	var variant: Int
	var downed: Bool
	var lair: Int
	/// mutation doses (nil in saves from before mutation, and for creatures that never mutated)
	var mut: Int? = nil
}

// ===== p13b_vehicles =====

// MARK: - Vehicles (player built) and pirate ships

struct PartCell: Hashable, Codable {
	var dx: Int
	var dy: Int
}

struct VPartSave: Codable {
	var dx: Int
	var dy: Int
	var type: Int
}

struct VehicleSave: Codable {
	var id: Int
	var parts: [VPartSave]
	/// centre of mass (saves with `rot`), or the bottom-centre of the box (older saves)
	var x: Double
	var y: Double
	var fuel: Double
	var dir: Int
	var kit: Int?
	/// rotation in radians; nil in saves made before vehicles could rotate
	var rot: Double? = nil
}

/// Displaced volume per part (how much it floats)
func partVolume(_ p: PartType) -> Double {
	switch p {
	case .hull: return 4.0
	case .frame: return 0.3
	case .fuelTank: return 0.25
	case .seat: return 0.1
	default: return 0.0
	}
}

/// Mining power of a drill part: (tier it can break, speed)
func drillPower(_ p: PartType) -> (Int, Double) {
	switch p {
	case .drill: return (4, 4.6)
	case .diamondDrill: return (7, 8.5)
	case .voidDrill: return (9, 13.0)
	default: return (0, 0)
	}
}

func isDrill(_ p: PartType) -> Bool { return p == .drill || p == .diamondDrill || p == .voidDrill }

/// A player-built vehicle: a rigid body made of 1x1 parts. It has a centre of mass, a rotation and
/// an angular velocity, and every part collides, floats and drives at its rotated position, so
/// what you see is exactly what touches the world.
final class Vehicle {
	let id: Int
	var parts: [PartCell: PartType] = [:]
	/// world-space bounding box of the rotated parts (kept for spawning, decks, pick tests)
	var b: Body
	// rigid body state
	var px: Double = 0
	var py: Double = 0
	var vx: Double = 0
	var vy: Double = 0
	var angle: Double = 0
	var angVel: Double = 0
	/// centre of mass in cell coordinates (cell (0,0) spans 0...1)
	var comX: Double = 0.5
	var comY: Double = 0.5
	var inertia: Double = 1
	var fuel: Double = 0
	var dir: Int = 1
	var minX: Int = 0
	var maxX: Int = 0
	var minY: Int = 0
	var maxY: Int = 0
	var mass: Double = 1
	var buoyancy: Double = 0
	var engines: Int = 0
	var wheels: Int = 0
	var propellers: Int = 0
	var paddles: Int = 0
	var tanks: Int = 0
	var drills: Int = 0
	var offroadWheels: Int = 0
	var headlights: Int = 0
	var hasSeat: Bool = false
	var hasSteering: Bool = false
	var throttle: Double = 0
	var wheelRot: Double = 0
	var rider: Bool = false
	var propRot: Double = 0
	var drillRot: Double = 0
	var drilling: Bool = false
	var smoke: Double = 0
	/// contacts touched in the last physics step (wheels on the ground, any part on the ground)
	var wheelContacts: Int = 0
	var contacts: Int = 0
	var submerged: Double = 0
	var sleepT: Double = 0
	var asleep: Bool = false
	/// physics time not yet simulated (vehicles step at a fixed rate)
	var physAccum: Double = 0
	/// direction each drill faces in vehicle space, and its mining progress
	var drillDir: [PartCell: (Int, Int)] = [:]
	var drillWork: [PartCell: (Int, Int, Double)] = [:]
	/// the kit this vehicle came from (-1 = built part by part, or changed since)
	var kit: Int = -1

	init(id: Int, first: PartType, x: Double, y: Double) {
		self.id = id
		self.b = Body(x: x, y: y, w: 1, h: 1)
		parts[PartCell(dx: 0, dy: 0)] = first
		recompute(keepAnchor: false)
		placeBox(left: x - 0.5, bottom: y)
	}

	// MARK: transforms

	var cosA: Double { return cos(angle) }
	var sinA: Double { return sin(angle) }

	/// vehicle-space point (cell units) to world
	func toWorld(_ lx: Double, _ ly: Double) -> (Double, Double) {
		let ox: Double = lx - comX
		let oy: Double = ly - comY
		let c: Double = cosA
		let s: Double = sinA
		return (px + ox * c - oy * s, py + ox * s + oy * c)
	}

	/// world point to vehicle space (cell units)
	func toLocal(_ wx: Double, _ wy: Double) -> (Double, Double) {
		let dx: Double = wx - px
		let dy: Double = wy - py
		let c: Double = cosA
		let s: Double = sinA
		return (dx * c + dy * s + comX, -dx * s + dy * c + comY)
	}

	func cellCenter(_ c: PartCell) -> (Double, Double) {
		return toWorld(Double(c.dx) + 0.5, Double(c.dy) + 0.5)
	}

	/// top-left of the cell's (unrotated) box around its rotated centre
	func cellPos(_ c: PartCell) -> (Double, Double) {
		let p: (Double, Double) = cellCenter(c)
		return (p.0 - 0.5, p.1 - 0.5)
	}

	func cellAt(_ wx: Double, _ wy: Double) -> PartCell {
		let l: (Double, Double) = toLocal(wx, wy)
		return PartCell(dx: Int(floor(l.0)), dy: Int(floor(l.1)))
	}

	/// Places an unrotated vehicle so its parts' box has this left edge and bottom
	func placeBox(left: Double, bottom: Double) {
		angle = 0
		px = left + (comX - Double(minX))
		py = bottom - (Double(maxY + 1) - comY)
		updateBox()
	}

	/// Recomputes the world bounding box from the rotated part corners
	func updateBox() {
		var x0: Double = 1e9, x1: Double = -1e9, y0: Double = 1e9, y1: Double = -1e9
		let c: Double = cosA
		let s: Double = sinA
		for (cell, _) in parts {
			let corners: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
			for k in corners {
				let ox: Double = Double(cell.dx) + k.0 - comX
				let oy: Double = Double(cell.dy) + k.1 - comY
				let wx: Double = px + ox * c - oy * s
				let wy: Double = py + ox * s + oy * c
				x0 = min(x0, wx); x1 = max(x1, wx); y0 = min(y0, wy); y1 = max(y1, wy)
			}
		}
		b.w = max(0.1, x1 - x0)
		b.h = max(0.1, y1 - y0)
		b.x = (x0 + x1) * 0.5
		b.y = y1
		b.vx = vx
		b.vy = vy
	}

	func recompute(keepAnchor: Bool) {
		// remember where one surviving cell is, so the rest of the vehicle stays put in the world
		var anchor: PartCell? = nil
		var anchorW: (Double, Double) = (0, 0)
		if keepAnchor, let c0 = parts.keys.first {
			anchor = c0
			anchorW = cellCenter(c0)
		}
		var x0: Int = 0, x1: Int = 0, y0: Int = 0, y1: Int = 0
		var first: Bool = true
		mass = 0
		buoyancy = 0
		engines = 0; wheels = 0; propellers = 0; paddles = 0; tanks = 0; drills = 0; offroadWheels = 0; headlights = 0
		hasSeat = false
		hasSteering = false
		var mx: Double = 0
		var my: Double = 0
		for (c, t) in parts {
			if first { x0 = c.dx; x1 = c.dx; y0 = c.dy; y1 = c.dy; first = false }
			x0 = min(x0, c.dx); x1 = max(x1, c.dx); y0 = min(y0, c.dy); y1 = max(y1, c.dy)
			mass += t.mass
			mx += t.mass * (Double(c.dx) + 0.5)
			my += t.mass * (Double(c.dy) + 0.5)
			buoyancy += partVolume(t)
			switch t {
			case .engine: engines += 1
			case .wheel: wheels += 1
			case .offroadWheel: wheels += 1; offroadWheels += 1
			case .headlight: headlights += 1
			case .propeller: propellers += 1
			case .paddle: paddles += 1
			case .fuelTank: tanks += 1
			case .seat: hasSeat = true
			case .steering: hasSteering = true
			case .drill, .diamondDrill, .voidDrill: drills += 1
			default: break
			}
		}
		minX = x0; maxX = x1; minY = y0; maxY = y1
		mass = max(0.3, mass)
		comX = mx / mass
		comY = my / mass
		// moment of inertia: each part as a 1x1 plate around the centre of mass
		var inert: Double = 0
		for (c, t) in parts {
			let ox: Double = Double(c.dx) + 0.5 - comX
			let oy: Double = Double(c.dy) + 0.5 - comY
			inert += t.mass * (ox * ox + oy * oy + 1.0 / 6.0)
		}
		inertia = max(0.2, inert)
		// drills face the open side of their cell
		drillDir.removeAll()
		for (c, t) in parts where isDrill(t) {
			let free: (PartCell) -> Bool = { self.parts[$0] == nil }
			if free(PartCell(dx: c.dx + 1, dy: c.dy)) && !free(PartCell(dx: c.dx - 1, dy: c.dy)) { drillDir[c] = (1, 0) }
			else if free(PartCell(dx: c.dx - 1, dy: c.dy)) && !free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (-1, 0) }
			else if free(PartCell(dx: c.dx, dy: c.dy + 1)) { drillDir[c] = (0, 1) }
			else if free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (1, 0) }
			else { drillDir[c] = (0, -1) }
		}
		drillWork = drillWork.filter { parts[$0.key] != nil }
		if let a = anchor, parts[a] != nil {
			// put the anchor cell back where it was
			let ox: Double = Double(a.dx) + 0.5 - comX
			let oy: Double = Double(a.dy) + 0.5 - comY
			let c: Double = cosA
			let s: Double = sinA
			px = anchorW.0 - (ox * c - oy * s)
			py = anchorW.1 - (ox * s + oy * c)
		}
		asleep = false
		updateBox()
	}

	var fuelCapacity: Double { return Double(tanks) * 60.0 + (engines > 0 ? 8.0 : 0.0) }
	var isBoat: Bool { return buoyancy > 0 }
	var canDriveOnLand: Bool { return wheels >= 2 && engines > 0 }
	var canSail: Bool { return buoyancy >= mass * 0.8 && ((engines > 0 && propellers > 0) || paddles > 0) }
	var topY: Double { return b.y - b.h }
	var speed: Double { return sqrt(vx * vx + vy * vy) }
	/// roughly upright (flat enough to stand on, to place kits next to, and so on)
	var upright: Bool { return abs(remainder(angle, 2.0 * Double.pi)) < 0.35 }

	func hasNeighbor(_ c: PartCell) -> Bool {
		let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
		for k in n { if parts[k] != nil { return true } }
		return false
	}

	func canAttach(_ c: PartCell, _ t: PartType) -> Bool {
		if parts[c] != nil { return false }
		if !hasNeighbor(c) { return false }
		if isWheelPart(t) {
			// wheels hang below the body: something must be directly above, nothing below
			if parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil { return false }
			if parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return false }
		}
		if t == .steering {
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
			var ok: Bool = false
			for k in n { if parts[k] == .seat { ok = true } }
			if !ok { return false }
		}
		if t == .propeller || t == .paddle {
			// must sit at the edge of the vehicle
			let side: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy)]
			var free: Bool = false
			for k in side { if parts[k] == nil { free = true } }
			if !free { return false }
		}
		if isDrill(t) {
			// a drill needs one open side to bore into
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1)]
			var free: Bool = false
			for k in n { if parts[k] == nil { free = true } }
			if !free { return false }
		}
		return true
	}

	/// Removes a part, returning every part that is no longer connected (including the removed one)
	func removePart(_ c: PartCell) -> [PartType] {
		var out: [PartType] = []
		if let t = parts[c] { out.append(t) }
		parts[c] = nil
		if parts.isEmpty { return out }
		// flood fill from any remaining cell
		var seen: Set<PartCell> = []
		var stack: [PartCell] = [parts.keys.first!]
		while let cur = stack.popLast() {
			if seen.contains(cur) { continue }
			seen.insert(cur)
			let n: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
			for k in n { if parts[k] != nil && !seen.contains(k) { stack.append(k) } }
		}
		// keep the largest connected group
		var group: Set<PartCell> = seen
		if seen.count * 2 < parts.count {
			var other: Set<PartCell> = []
			for k in parts.keys { if !seen.contains(k) { other.insert(k) } }
			group = other
		}
		for k in Array(parts.keys) {
			if !group.contains(k) {
				if let t = parts[k] { out.append(t) }
				parts[k] = nil
			}
		}
		return out
	}

	func save() -> VehicleSave {
		var ps: [VPartSave] = []
		for (c, t) in parts { ps.append(VPartSave(dx: c.dx, dy: c.dy, type: t.rawValue)) }
		return VehicleSave(id: id, parts: ps, x: px, y: py, fuel: fuel, dir: dir, kit: kit, rot: angle)
	}

	static func restore(_ s: VehicleSave) -> Vehicle {
		let v = Vehicle(id: s.id, first: .frame, x: s.x, y: s.y)
		v.parts.removeAll()
		for p in s.parts { v.parts[PartCell(dx: p.dx, dy: p.dy)] = PartType(rawValue: p.type) ?? .frame }
		if v.parts.isEmpty { v.parts[PartCell(dx: 0, dy: 0)] = .frame }
		v.recompute(keepAnchor: false)
		if let r = s.rot {
			v.px = s.x
			v.py = s.y
			v.angle = r
			v.updateBox()
		} else {
			// older save: x, y were the bottom-centre of an unrotated box
			let w: Double = Double(v.maxX - v.minX + 1)
			v.placeBox(left: s.x - w * 0.5, bottom: s.y)
		}
		v.fuel = s.fuel
		v.dir = s.dir
		v.kit = s.kit ?? -1
		return v
	}
}

// MARK: - Pirate ships

final class PirateShip {
	let id: Int
	var x: Double
	var dir: Int
	var hp: Double = 180
	var maxHP: Double = 180
	var crew: [Int] = []
	var state: Int = 0
	var t: Double = 0
	var looted: Bool = false
	var bob: Double = 0
	var patrolMin: Double
	var patrolMax: Double
	var sink: Double = 0
	var hitT: Double = 0
	var speed: Double = 0

	static let deckHalf: Double = 4.0
	static let spriteW: Double = 9.5
	static let spriteH: Double = 5.0
	static let waterRow: Double = 3.6
	static let deckRow: Double = 2.625

	init(id: Int, x: Double, dir: Int, pMin: Double, pMax: Double) {
		self.id = id
		self.x = x
		self.dir = dir
		self.patrolMin = pMin
		self.patrolMax = pMax
	}

	/// y of the deck standing line in tiles
	func deckY(_ seaY: Double) -> Double {
		return seaY - PirateShip.waterRow + PirateShip.deckRow + sink + sin(bob) * 0.12
	}
}

// ===== p14a_game =====

// MARK: - Game state

enum GameMode: String, Codable {
	case survival, creative, hardcore
	var title: String { return rawValue.capitalized }
}

struct Settings: Codable {
	var hair: Int = 0
	var scarf: Int = 0
	var touchControls: Bool = true
	var peaceful: Bool = false
	var showCoords: Bool = true
	var tilePx: Int = 24
	var rareChance: Double = 0.28
	var smoothLight: Bool = true
	/// true = 60 frames per second, false = 30 (smoother on older iPads)
	var fps60: Bool = true
	var showFPS: Bool = false
	// camera
	var camSmoothOn: Bool = true
	/// 0 = loose and floaty, 1 = tight
	var camFollow: Double = 0.55
	/// tiles the player can move before the camera starts to follow
	var camDeadZone: Double = 0.8
	var camLookAhead: Bool = true
	/// the camera stays on the player: no dead zone, no look-ahead, a quick smooth follow
	var camDirect: Bool = false
	var shakeOn: Bool = true
	var shakeIntensity: Double = 0.5
	var showTrajectory: Bool = true
	// sound
	var soundOn: Bool = true
	var sfxVolume: Double = 0.7
	var ambienceVolume: Double = 0.5
	// weather: a master switch, a switch for each kind, what it may damage, how strong and how often
	// severe weather is, alerts, how much is drawn, and gentler lightning
	var weatherOn: Bool = true
	var allowRain: Bool = true
	var allowThunder: Bool = true
	var allowWind: Bool = true
	var allowTornado: Bool = true
	var allowHurricane: Bool = true
	var allowBlizzard: Bool = true
	var allowHail: Bool = true
	var weatherHurtsPlayer: Bool = true
	var weatherHurtsBlocks: Bool = true
	var weatherHurtsCreatures: Bool = true
	/// 0.25 (gentle) ... 1.5 (fierce)
	var weatherIntensity: Double = 1.0
	/// how often severe weather comes: 0 rare, 1 normal, 2 frequent
	var severeFrequency: Int = 1
	var weatherAlerts: Bool = true
	/// 0.2 ... 1: how many raindrops, flakes and stones are drawn
	var weatherParticles: Double = 1.0
	/// lightning lights the scene gently instead of flashing it (strikes still happen)
	var reduceFlashes: Bool = false
	/// how dangerous nights are: 0 calm, 1 normal, 2 deadly (how many monsters, how quickly they come)
	var nightDanger: Int = 1
	/// how wiring is drawn: 0 only while a wiring tool or the probe is in hand, 1 always, 2 always but faint
	var showWires: Int = 0
	/// structural physics: built blocks need support and can only carry so much (see updateStructures)
	var structural: Bool = false

	var shakeScale: Double { return shakeOn ? shakeIntensity : 0 }

	mutating func resetWeather() {
		let d: Settings = Settings()
		weatherOn = d.weatherOn
		allowRain = d.allowRain
		allowThunder = d.allowThunder
		allowWind = d.allowWind
		allowTornado = d.allowTornado
		allowHurricane = d.allowHurricane
		allowBlizzard = d.allowBlizzard
		allowHail = d.allowHail
		weatherHurtsPlayer = d.weatherHurtsPlayer
		weatherHurtsBlocks = d.weatherHurtsBlocks
		weatherHurtsCreatures = d.weatherHurtsCreatures
		weatherIntensity = d.weatherIntensity
		severeFrequency = d.severeFrequency
		weatherAlerts = d.weatherAlerts
		weatherParticles = d.weatherParticles
		reduceFlashes = d.reduceFlashes
	}

	static let cameraDefaults: Settings = Settings()

	mutating func resetCamera() {
		let d: Settings = Settings.cameraDefaults
		camSmoothOn = d.camSmoothOn
		camFollow = d.camFollow
		camDeadZone = d.camDeadZone
		camLookAhead = d.camLookAhead
		camDirect = d.camDirect
		shakeOn = d.shakeOn
		shakeIntensity = d.shakeIntensity
		tilePx = d.tilePx
	}

	init() {}

	// Missing keys (settings saved by an older version) fall back to the defaults
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		hair = (try? c.decodeIfPresent(Int.self, forKey: .hair)) ?? 0
		scarf = (try? c.decodeIfPresent(Int.self, forKey: .scarf)) ?? 0
		touchControls = (try? c.decodeIfPresent(Bool.self, forKey: .touchControls)) ?? true
		peaceful = (try? c.decodeIfPresent(Bool.self, forKey: .peaceful)) ?? false
		showCoords = (try? c.decodeIfPresent(Bool.self, forKey: .showCoords)) ?? true
		tilePx = (try? c.decodeIfPresent(Int.self, forKey: .tilePx)) ?? 24
		rareChance = (try? c.decodeIfPresent(Double.self, forKey: .rareChance)) ?? 0.28
		smoothLight = (try? c.decodeIfPresent(Bool.self, forKey: .smoothLight)) ?? true
		fps60 = (try? c.decodeIfPresent(Bool.self, forKey: .fps60)) ?? true
		showFPS = (try? c.decodeIfPresent(Bool.self, forKey: .showFPS)) ?? false
		camSmoothOn = (try? c.decodeIfPresent(Bool.self, forKey: .camSmoothOn)) ?? true
		camFollow = (try? c.decodeIfPresent(Double.self, forKey: .camFollow)) ?? 0.55
		camDeadZone = (try? c.decodeIfPresent(Double.self, forKey: .camDeadZone)) ?? 0.8
		camLookAhead = (try? c.decodeIfPresent(Bool.self, forKey: .camLookAhead)) ?? true
		camDirect = (try? c.decodeIfPresent(Bool.self, forKey: .camDirect)) ?? false
		shakeOn = (try? c.decodeIfPresent(Bool.self, forKey: .shakeOn)) ?? true
		shakeIntensity = (try? c.decodeIfPresent(Double.self, forKey: .shakeIntensity)) ?? 0.5
		showTrajectory = (try? c.decodeIfPresent(Bool.self, forKey: .showTrajectory)) ?? true
		soundOn = (try? c.decodeIfPresent(Bool.self, forKey: .soundOn)) ?? true
		sfxVolume = (try? c.decodeIfPresent(Double.self, forKey: .sfxVolume)) ?? 0.7
		ambienceVolume = (try? c.decodeIfPresent(Double.self, forKey: .ambienceVolume)) ?? 0.5
		weatherOn = (try? c.decodeIfPresent(Bool.self, forKey: .weatherOn)) ?? true
		allowRain = (try? c.decodeIfPresent(Bool.self, forKey: .allowRain)) ?? true
		allowThunder = (try? c.decodeIfPresent(Bool.self, forKey: .allowThunder)) ?? true
		allowWind = (try? c.decodeIfPresent(Bool.self, forKey: .allowWind)) ?? true
		allowTornado = (try? c.decodeIfPresent(Bool.self, forKey: .allowTornado)) ?? true
		allowHurricane = (try? c.decodeIfPresent(Bool.self, forKey: .allowHurricane)) ?? true
		allowBlizzard = (try? c.decodeIfPresent(Bool.self, forKey: .allowBlizzard)) ?? true
		allowHail = (try? c.decodeIfPresent(Bool.self, forKey: .allowHail)) ?? true
		weatherHurtsPlayer = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsPlayer)) ?? true
		weatherHurtsBlocks = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsBlocks)) ?? true
		weatherHurtsCreatures = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsCreatures)) ?? true
		weatherIntensity = clampD((try? c.decodeIfPresent(Double.self, forKey: .weatherIntensity)) ?? 1.0, 0.25, 1.5)
		severeFrequency = clampI((try? c.decodeIfPresent(Int.self, forKey: .severeFrequency)) ?? 1, 0, 2)
		weatherAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .weatherAlerts)) ?? true
		weatherParticles = clampD((try? c.decodeIfPresent(Double.self, forKey: .weatherParticles)) ?? 1.0, 0.2, 1.0)
		reduceFlashes = (try? c.decodeIfPresent(Bool.self, forKey: .reduceFlashes)) ?? false
		nightDanger = clampI((try? c.decodeIfPresent(Int.self, forKey: .nightDanger)) ?? 1, 0, 2)
		showWires = clampI((try? c.decodeIfPresent(Int.self, forKey: .showWires)) ?? 0, 0, 2)
		structural = (try? c.decodeIfPresent(Bool.self, forKey: .structural)) ?? false
	}
}

/// The HUD and panels watch this instead of the whole game, so they only redraw when something they show changes.
final class HUDSignal: ObservableObject, @unchecked Sendable {
	@Published var tick: Int = 0
}

/// The world canvas watches this; it changes once per game step.
final class FrameTicker: ObservableObject, @unchecked Sendable {
	@Published var frame: Int = 0
}

struct IntPair: Hashable {
	var x: Int
	var y: Int
}

final class Game: ObservableObject, @unchecked Sendable {
	/// a number no other game in this run has (what the render cache knows a world by)
	let serial: Int = Game.nextSerial()
	static var serialCount: Int = 0
	static func nextSerial() -> Int {
		serialCount += 1
		return serialCount
	}
	// UI refresh signals
	let hud: HUDSignal = HUDSignal()
	let ticker: FrameTicker = FrameTicker()
	var lastHudKey: Int = 0
	var renderFPS: Double = 0
	@Published var showInventory: Bool = false
	@Published var showDebug: Bool = false
	@Published var showMap: Bool = false
	@Published var showJournal: Bool = false
	@Published var paused: Bool = false
	@Published var openChest: IntPair? = nil
	@Published var message: String? = nil
	@Published var dead: Bool = false
	@Published var craftStation: Station = .hand

	// setup
	var world: World
	var settings: Settings
	var mode: GameMode
	var worldName: String = "World"
	var slot: Int = 0
	var seedValue: UInt64

	// time
	var timeOfDay: Double = 0.06
	let dayLength: Double = 720
	var dayCount: Int = 1
	var clock: Double = 0
	var playSeconds: Double = 0
	var messageT: Double = 0
	var hudAccum: Int = 0

	// player
	var pb: Body
	var facing: Int = 1
	var hp: Double = 20
	var maxHP: Double = 20
	var hunger: Double = 20
	var air: Double = 10
	var hurtT: Double = 0
	var invuln: Double = 0
	var deathT: Double = 0
	var inv: Inventory = Inventory()
	var sel: Int = 0
	var spawnX: Double = 0
	var spawnY: Double = 0
	var kills: Int = 0
	var coyote: Double = 0
	var jumpBuf: Double = 0
	var dropT: Double = 0
	/// time left in a vault out of water onto a ledge
	var vaultT: Double = 0
	var starveT: Double = 0
	var regenT: Double = 0
	var lastVy: Double = 0
	var walkAnim: Double = 0
	var fallPeak: Double = 0

	// cheats / debug
	var flying: Bool = false
	var noclip: Bool = false
	var godMode: Bool = false
	var freezeTime: Bool = false
	var monstersEnabled: Bool = true
	var speedMult: Double = 1.0
	var showHitboxes: Bool = false
	/// debug: each hostile's AI state, what it knows of the player and why it is not attacking
	var showAI: Bool = false
	var showChunks: Bool = false
	var fullBright: Bool = false
	var infiniteReach: Bool = false
	/// debug: multiplies the health of newly spawned creatures
	var mobHealthMult: Double = 1.0
	/// debug: individual systems can be paused to isolate problems
	var pauseMobs: Bool = false
	var pauseBosses: Bool = false
	var pauseSpawning: Bool = false
	var pauseProjectiles: Bool = false
	var pauseVehicles: Bool = false
	var pauseWorldTicks: Bool = false
	var pauseParticles: Bool = false
	/// debug: the creature picked with "Select at cursor"
	weak var debugSelected: Mob? = nil
	/// lairs whose boss stays away until the player has left the area (after "Delete all entities")
	var suppressedLairs: Set<Int> = []

	// tool use
	var swingT: Double = 0
	var swingDur: Double = 0.25
	var swingDir: Int = 1
	var useCD: Double = 0
	var bowCharge: Double = 0
	var reloadT: Double = 0
	var reloadSlot: Int = -1
	var mineX: Int = 0
	var mineY: Int = 0
	var mineP: Double = 0
	var mining: Bool = false
	var muzzleT: Double = 0
	var recoilT: Double = 0
	var bowRecoil: Double = 0
	var eatT: Double = 0

	// input state (set by the UI layer)
	var stick: Double = 0
	var stickY: Double = 0
	var keyL: Bool = false
	var keyR: Bool = false
	var jumpHeld: Bool = false
	var jumpPrev: Bool = false
	var downHeld: Bool = false
	var useHeld: Bool = false
	var usePressedFlag: Bool = false
	var useReleasedFlag: Bool = false
	var aimX: Double = 0
	var aimY: Double = 0
	var aimValid: Bool = false
	var useWasHeld: Bool = false
	var lavaT: Double = 0
	var drownT: Double = 0
	var hardcoreOver: Bool = false
	var pendingInteract: Bool = false
	var downTime: Double = 0
	var pointerStartX: Double = 0
	var pointerStartY: Double = 0
	var carry: Stack? = nil
	var placeCD: Double = 0
	var decksCache: [Deck] = []
	var mineNeed: Double = 1

	// camera and view
	var camX: Double = 0
	/// where the camera is heading (dead zone applied); camX/camY ease toward it
	var camTX: Double = 0
	var camTY: Double = 0
	var camLead: Double = 0
	var camY: Double = 0
	var viewW: Double = 1024
	var viewH: Double = 768
	var tilePx: Int = 24
	var shake: Double = 0

	// entities
	var mobs: [Mob] = []
	var projectiles: [Projectile] = []
	var drops: [DropItem] = []
	/// doors the player walked through, closing behind them (see updateWalkDoors)
	var walkDoors: [WalkDoor] = []
	var particles: [Particle] = []
	var floats: [FloatText] = []
	var vehicles: [Vehicle] = []
	var ships: [PirateShip] = []
	var nextID: Int = 1
	var spawnTimer: Double = 2.0
	/// Sparkworks networks and their live state
	let power: PowerSim = PowerSim()
	/// time before the next monster may come out on the surface (sets the pace of a night)
	var monsterSpawnCD: Double = 0
	/// debug: how spawn attempts ended, by reason, and the last one
	var spawnLog: [String: Int] = [:]
	var spawnLast: String = ""
	var shipTimer: Double = 20.0
	var fallingBlocks: [FallingBlock] = []
	/// placing a held block as a wall instead (the HUD's WALL switch)
	var wallMode: Bool = false
	/// the item in hand while the use button is held, and whether that hold used it up (see updateUse)
	var lastUsedItem: Item? = nil
	var handEmptied: Bool = false
	/// the chair or sofa the player is sitting on
	var seat: IntPair? = nil
	/// the lift cars of this dimension, and those left in the others
	var lifts: [Lift] = []
	var liftStash: [[Lift]] = [[Lift]](repeating: [], count: dimCount)
	/// structural physics: changes waiting to be looked at, a moment's wait to gather them, and the
	/// blocks under strain (drawn cracked)
	var structQueue: [IntPair] = []
	var structT: Double = 0
	var stress: [Int: Double] = [:]
	var decayZones: [DecayZone] = []
	/// short-lived lights from explosions (fed into the light map as moving lights, then removed)
	var flashes: [LightFlash] = []
	/// ground about to be struck by a telegraphed attack (drawn as a warning)
	var dangerZones: [DangerZone] = []
	var journal: Journal = Journal()
	var discoverT: Double = 0
	var guardianT: Double = 0
	/// weather (see WeatherSim): the simulation, what it brings to where the player stands, and the
	/// short-lived things it puts in the world
	var weather: WeatherSim = WeatherSim()
	var wxHere: LocalWeather = LocalWeather()
	/// kept for the code that reads them: how hard rain or snow falls on the player, and whether it is snow
	var weatherRain: Double = 0
	var weatherSnow: Bool = false
	/// where the player last stood in the overworld (the weather is judged there while they are away)
	var wxHomeX: Double = 0
	var coastCache: [Int: (Double, Double)] = [:]
	var bolts: [LightningBolt] = []
	var thunderQueue: [PendingThunder] = []
	var strikeMark: StrikeMark? = nil
	var strikeAcc: Double = 0
	var playerStrikeCD: Double = 0
	var skyFlash: Double = 0
	var hailPool: [HailStone] = []
	var hailAcc: Double = 0
	var hailHitT: Double = 0
	var hailBroken: Int = 0
	/// how much warmth the player has lost to the cold (0 fine ... 1 freezing), and what keeps it in
	var bodyCold: Double = 0
	var coldHurtT: Double = 0
	var coldWarned: Bool = false
	var warmthNear: Double = 0
	var warmthT: Double = 0
	/// 0 open, 1 under a roof, 2 indoors, 3 underground or in a storm shelter (see shelterAt)
	var shelterLevel: Int = 0
	var wxCellT: Double = 0
	/// the wind's hold on the player this frame (see updateWeatherForces)
	var wxWalk: Double = 0
	var wxAirDrift: Double = 0
	var wxRest: Double = 0
	var wxAccelX: Double = 0
	var wxAccelY: Double = 0
	var wxSlip: Double = 0
	var wxSlow: Double = 1
	/// thrown by a tornado: a hard landing hurts less
	var flingT: Double = 0
	var wxDebrisT: Double = 0
	var tornadoAcc: Double = 0
	var tornadoGround: Double = 0
	var hurricaneAcc: Double = 0
	var surgeT: Double = 0
	var swampT: Double = 0
	var wxDevT: Double = 0
	var wxNoteT: Double = 0
	/// the present severe spell actually reached the player (it then goes in the journal)
	var stormFelt: Bool = false
	var sirenLevel: Double = 0
	/// the warning strip under the top bar (0 none, 1 advisory, 2 warning)
	var wxBanner: String = ""
	var wxBannerLevel: Int = 0
	/// the weather station whose screen is open
	var stationAt: DeviceSpot? = nil
	@Published var showWeather: Bool = false
	/// a Sparkworks device's panel, and which device
	@Published var showPower: Bool = false
	var powerAt: ChestKey? = nil
	/// the last cell a wire drag reached, the network the probe lit up
	var wireLast: IntPair? = nil
	var wireSoundT: Double = 0
	var inspect: PowerInspect? = nil
	/// the landing squash and the last frame's water state (for splashes)
	var landT: Double = 0
	var wasInWater: Bool = false
	let mobGrid: MobGrid = MobGrid()
	var frameNo: Int = 0

	// combat: the blow a heavy weapon is winding up, the brief freeze when a hit lands, the foe the
	// aim is locked onto, a knife's run of quick hits, the trails, lightning and fire on screen
	var strikeT: Double = 0
	var strikeSel: Int = -1
	var strikeItem: Item? = nil
	weak var strikeTarget: Mob? = nil
	var hitStopT: Double = 0
	weak var lockTarget: Mob? = nil
	var lockT: Double = 0
	var comboN: Int = 0
	var comboT: Double = -10
	var slashes: [SlashFX] = []
	var arcs: [ArcFX] = []
	var fireZones: [FireZone] = []
	var rodT: Double = 0
	/// a finger is on the world (it aims for itself; the action button only keeps the action going)
	var touchActive: Bool = false
	/// a panel, the pause menu or death is covering the controls (their held state is dropped)
	var inputBlocked: Bool = false
	var lastWeaponSel: Int = -1
	/// what the last melee blow hit (for the feedback and the tests)
	var lastStrikeHits: Int = 0

	// damage bookkeeping
	var playerHitStamps: [Int: Double] = [:]
	var playerBurn: Double = 0
	var playerBurnTick: Double = 0
	/// the mods this world uses (see ModRuntime; nil for a world without mods)
	var modInfo: ModWorldInfo? = nil
	/// the id of the mod being tried out in a mod test world ("" in a real world)
	var testMod: String = ""
	/// structure capture: picking two corners on the world, then the save panel (see startCapture)
	@Published var capturing: Bool = false
	@Published var showCapture: Bool = false
	/// the Mod Test tools (test worlds only)
	@Published var showModTest: Bool = false
	var capA: (Int, Int)? = nil
	var capB: (Int, Int)? = nil
	/// effects from potions, food and armour (see PlayerEffects)
	var effects: PlayerEffects = PlayerEffects()
	/// seconds before mending potions heal fully again
	var mendCD: Double = 0
	/// smoke clouds and the rings of bursting potions
	var smokes: [SmokeCloud] = []
	var rings: [BurstRing] = []
	/// the exosuit, a counter bumped whenever it changes, and the numbers worked out from it
	var suit: ExoSuit = ExoSuit()
	var suitRev: Int = 0
	var suitStatsRev: Int = -1
	var suitStatsCache: ExoStats = ExoStats()
	/// energy a second the suit's running modules are drawing this frame, and what is running
	var suitLoad: Double = 0
	var suitLastLoad: Double = 0
	var suitHover: Bool = false
	var suitSprinting: Bool = false
	var suitLit: Bool = false
	var suitEmptyWarned: Bool = false
	/// armour infusions summed over what is worn, and the key of what was worn then
	var armorInfCache: ArmorInf = ArmorInf()
	var armorInfKey: Int = 0
	@Published var showInfuse: Bool = false
	/// when each custom infusion last gave its effect (by number)
	var infTriggerCD: [Int: Double] = [:]
	@Published var showExo: Bool = false
	/// a healing shrine rests between uses
	var healerCD: Double = 0
	/// debug multipliers: damage the player deals / takes
	var dmgOutMult: Double = 1.0
	var dmgInMult: Double = 1.0

	// lighting
	var light: LightMap = LightMap()
	/// the light around a spot a creature might appear at (see glowForSpawn)
	let spawnLight: LightMap = LightMap()
	var lightDark: [UInt32] = []
	var lightGlow: [UInt32] = []
	var lightRev: Int = 0
	var lightTimer: Double = 0

	// bosses & progress
	var defeated: Set<Int> = []
	var rex: Mob? = nil
	var activeBoss: Mob? = nil
	var bossBarName: String = ""
	var bossBarFrac: Double = 0
	var gotMap: Bool = false
	var portalOpened: Bool = false
	var portalT: Double = 0
	var portalCool: Double = 0
	/// set by a portal trip: the rift will not pull the player again until they have stepped out of it
	var portalNeedsExit: Bool = false
	var riftCheckT: Double = 0
	var fadeT: Double = 0
	var mounted: Mob? = nil
	var inVehicle: Vehicle? = nil
	var vehicleStash: [[Vehicle]] = [[Vehicle]](repeating: [], count: dimCount)
	/// where the player came from into a custom dimension (to go back there)
	var dimReturn: DimReturn? = nil
	/// the Logic Studio's running scripts, and the variables of the world's mods ("mod:name")
	var logic: LogicVM = LogicVM()
	var logicVars: [String: Double] = [:]
	var mapCache: TreasureMap? = nil
	var hintT: Double = 0
	var autosaveT: Double = 0

	// streaming stats
	var loadRadius: Int = 5
	var lastStreamCX: Int = Int.min
	var chunksLoadedLast: Int = 0
	var tickMs: Double = 0
	var tickWorstMs: Double = 0

	/// A new world, with the land around its spawn made. A world being loaded passes `loadSpawn: false`:
	/// its land comes from the save, around where the player was (making the spawn's land first only
	/// to throw it away cost a dozen chunks every time a world was loaded).
	init(mode: GameMode, infinite: Bool, seed: UInt64, settings: Settings, genVersion: Int = WorldGen.currentVersion, options: WorldOptions = .standard, loadSpawn: Bool = true) {
		self.mode = mode
		self.settings = settings
		self.seedValue = seed
		let gen = WorldGen(seed: seed, infinite: infinite, rareChance: settings.rareChance, genVersion: genVersion, options: options)
		self.world = World(gen: gen)
		self.tilePx = settings.tilePx
		self.pb = Body(x: Double(gen.spawnX) + 0.5, y: 100, w: 0.7, h: 1.8)
		if loadSpawn {
			world.loadAround(centerX: gen.spawnX, radius: 6)
			let sy: Int = world.surfaceY(gen.spawnX)
			pb.y = Double(sy)
		}
		spawnX = pb.x
		spawnY = pb.y
		camX = pb.x
		camY = pb.y - 2
		setupStartingKit()
		timeOfDay = 0.06
		// the weather has its own random numbers, started from the world's seed
		weather.rngS = seed ^ 0x57EA_7E12_9B3D_0451
		weather.fxS = seed ^ 0x0FF5_E7FA_CE12_7731
		wxHomeX = pb.x
	}

	func setupStartingKit() {
		if mode == .creative {
			flying = false
			return
		}
		_ = inv.add(.block(.torch), 4)
	}

	var gen: WorldGen { return world.gen }
	var isCreative: Bool { return mode == .creative }
	var viewTilesW: Double { return viewW / Double(tilePx) }
	var viewTilesH: Double { return viewH / Double(tilePx) }

	func newID() -> Int {
		nextID += 1
		return nextID
	}

	func say(_ s: String, _ t: Double = 3.0) {
		message = s
		messageT = t
		hud.tick &+= 1
	}

	func bumpHUD() {
		hud.tick &+= 1
	}

	// MARK: time of day

	/// 1 = full day, 0 = deep night
	var dayFactor: Double {
		let t: Double = timeOfDay
		if world.dim != .overworld {
			if let d = customDim, !d.def.ceiling { return customDayFactor(d) }
			return 0
		}
		if t < 0.50 { return 1.0 }
		if t < 0.58 { return 1.0 - smooth((t - 0.50) / 0.08) }
		if t < 0.92 { return 0.0 }
		return smooth((t - 0.92) / 0.08)
	}

	var skyLevel: Int {
		if world.dim != .overworld {
			guard let d = customDim, !d.def.ceiling else { return 0 }
			return Int((clampD(d.def.light, 0, 1) * (6.0 + 9.0 * dayFactor)).rounded())
		}
		return Int((6.0 + 9.0 * dayFactor).rounded())
	}

	var isNight: Bool { return dayFactor < 0.35 }

	// MARK: items

	func giveItem(_ it: Item, _ n: Int, extra: Int = 0) {
		let left: Int = inv.add(it, n, extra: extra)
		if left > 0 {
			spawnDrop(Stack(item: it, count: left, extra: extra), pb.x, pb.y - 1.0, Double(facing) * 3.0, -4.0)
		}
		bumpHUD()
	}

	func spawnDrop(_ s: Stack, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, heldBack: Bool = false) {
		if s.count <= 0 { return }
		var d: DropItem = DropItem(stack: s, x: x, y: y, vx: vx, vy: vy)
		d.heldBack = heldBack
		drops.append(d)
	}

	func spawnParticles(_ x: Double, _ y: Double, _ color: UInt32, _ n: Int, _ speed: Double, _ life: Double = 0.6, _ grav: Double = 18) {
		if particles.count > 160 { return }
		for _ in 0..<n {
			let a: Double = Double.random(in: 0...(2 * Double.pi))
			let s: Double = Double.random(in: 0.3...1.0) * speed
			particles.append(Particle(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s - speed * 0.3, life: life * Double.random(in: 0.6...1.2), maxLife: life, color: color, size: Double.random(in: 0.08...0.18), gravity: grav))
		}
	}

	func floatText(_ s: String, _ x: Double, _ y: Double, _ color: UInt32 = 0xFFFFFF) {
		if floats.count > 14 { floats.removeFirst() }
		floats.append(FloatText(x: x, y: y, text: s, life: 1.0, color: color))
	}

	// MARK: selected item helpers

	var heldStack: Stack? { return inv.slots[sel] }
	var heldItem: Item? { return inv.slots[sel]?.item }

	func setSel(_ i: Int) {
		let n: Int = clampI(i, 0, Inventory.hotbarCount - 1)
		if n != sel, let it = heldItem, it.isWeapon { lastWeaponSel = sel }
		// switching while the attack control is down must not fire the new weapon in the same instant
		if n != sel && actState.held { useCD = max(useCD, 0.15) }
		sel = n
		bowCharge = 0
		mining = false
		mineP = 0
		// a blow being wound up is dropped with the weapon; a knife's run starts over
		strikeT = 0
		comboN = 0
		bumpHUD()
	}

}

// ===== p14b_player =====

// MARK: - Master tick, player movement, survival, camera, streaming, lighting

extension Game {
	func tick(_ rawDt: Double) {
		if paused { return }
		let dt: Double = min(max(rawDt, 0.001), 0.05) * (freezeTime ? 1.0 : 1.0)
		let t0: Double = Date().timeIntervalSinceReferenceDate
		clock += dt
		if !dead { playSeconds += dt }
		if messageT > 0 {
			messageT -= dt
			if messageT <= 0 { message = nil }
		}
		updateTime(dt)
		updateInputGate()
		mobGrid.rebuild(mobs)
		updateLifts(dt)
		decksCache = (ships.isEmpty && vehicles.isEmpty && lifts.isEmpty) ? [] : buildDecks()
		updatePointerTimers(dt)
		updateInputEdges()
		updatePlayer(dt)
		updateUse(dt)
		updateEffects(dt)
		updateModPlay(dt)
		updateLogic(dt)
		// a landed blow holds the creatures still for a frame or two (the player keeps moving), which
		// is what makes a hit feel like it connected
		let frozen: Bool = hitStopT > 0
		if frozen { hitStopT -= dt }
		if !pauseMobs && !frozen { updateMobs(dt) }
		updateDangerZones(dt)
		updateDiscoveries(dt)
		if !pauseBosses && !frozen { updateBosses(dt) }
		if !pauseSpawning { updateSpawning(dt) }
		if !pauseProjectiles { updateProjectiles(dt) }
		updateCombatFX(dt)
		if !pauseWorldTicks {
			updateFallingBlocks(dt)
			updateStructures(dt)
		}
		updateDrops(dt)
		if !pauseVehicles { updateVehicles(dt) }
		if !pauseMobs { updateShips(dt) }
		if !pauseWorldTicks { updateWorldTicks(dt) }
		updatePortal(dt)
		updateAutosave(dt)
		if !pauseParticles { updateParticles(dt) }
		updateFlashes(dt)
		updateWeather(dt)
		if !pauseWorldTicks { updatePower(dt) }
		updatePowerUI(dt)
		updateAudio()
		updateStreaming()
		updateCamera(dt)
		updateLight(dt)
		hudAccum += 1
		if hudAccum >= 5 {
			hudAccum = 0
			let k: Int = hudKey()
			if k != lastHudKey || showDebug {
				lastHudKey = k
				hud.tick &+= 1
			}
		}
		let t1: Double = Date().timeIntervalSinceReferenceDate
		tickMs = tickMs * 0.9 + (t1 - t0) * 1000.0 * 0.1
		tickWorstMs = max(tickWorstMs * 0.995, (t1 - t0) * 1000.0)
		Perf.shared.endFrame()
	}

	/// Screen shake, scaled (or disabled) by the camera settings
	func addShake(_ amount: Double) {
		shake = max(shake, amount * settings.shakeScale)
	}

	func updateTime(_ dt: Double) {
		if freezeTime || world.dim != .overworld { return }
		timeOfDay += dt / dayLength
		if timeOfDay >= 1.0 {
			timeOfDay -= 1.0
			dayCount += 1
		}
	}

	func updateInputEdges() {
		if useHeld && !usePressedFlag && !useWasHeld { usePressedFlag = true }
		useWasHeld = useHeld
	}

	// MARK: player

	func updatePlayer(_ dt: Double) {
		if dead {
			deathT += dt
			return
		}
		if invuln > 0 { invuln -= dt }
		if hurtT > 0 { hurtT -= dt }
		if shake > 0 { shake = max(0, shake - dt * 1.5) }
		var ix: Double = stick
		if keyL { ix -= 1.0 }
		if keyR { ix += 1.0 }
		ix = clampD(ix, -1.0, 1.0)
		if abs(ix) < 0.08 { ix = 0 }
		let jumpPressed: Bool = jumpHeld && !jumpPrev
		jumpPrev = jumpHeld
		if let v = inVehicle {
			driveVehicle(v, ix, jumpPressed, dt)
			return
		}
		if let r = mounted {
			rideRex(r, ix, jumpPressed, dt)
			return
		}
		if seat != nil && stayInSeat(ix, jumpPressed) {
			lastVy = 0
			return
		}
		var runMax: Double = 7.4 * speedMult * (wearing(.swiftBoots) ? 1.18 : 1.0) * wxSlow * (1.0 + effects.value(.speed) / 100.0) * (1.0 + armorInf.speed) * suitSpeedMul
		// heavy weapons commit you to the blow: slower on your feet while it lasts
		if swingT > 0 || strikeT > 0, let it = heldItem, it.isMeleeWeapon { runMax *= it.melee.moveScale }
		if ix != 0 {
			facing = ix > 0 ? 1 : -1
		}
		if swingT > 0 || useHeld {
			if aimValid {
				facing = aimFacing()
			}
		}
		if flying || noclip {
			let tx: Double = ix * 13.0 * speedMult
			var ty: Double = 0
			if jumpHeld { ty = -10.0 }
			if downHeld || stickY > 0.55 { ty = 10.0 }
			pb.vx += (tx - pb.vx) * min(1.0, dt * 9.0)
			pb.vy += (ty - pb.vy) * min(1.0, dt * 9.0)
			if noclip {
				pb.x += pb.vx * dt
				pb.y += pb.vy * dt
			} else {
				world.moveBody(&pb, dt, stepUp: 0, dropThrough: true, decks: [])
			}
			walkAnim += abs(pb.vx) * dt * 0.5
			lastVy = pb.vy
			checkHazards(dt)
			return
		}
		let inWater: Bool = pb.inWater
		let inLava: Bool = pb.inLava
		// climbing out of water: pushing against a bank or a ledge with jump held vaults onto it, if the
		// top is within reach (water used to pin the player under any ledge above its surface). Decided
		// before swimming, so the swim limits on rising speed do not cancel the vault.
		if (inWater || inLava) && vaultT <= 0 && jumpHeld && ix != 0 && pb.hitWall && ledgeWithinReach(ix > 0 ? 1 : -1) {
			vaultT = 0.32
			pb.vy = -13.0
		}
		if vaultT > 0 { vaultT -= dt }
		let swimming: Bool = (inWater || inLava) && vaultT <= 0
		// ladders: while the body overlaps one the player climbs (jump or up to climb, down to descend)
		if !swimming, let lc = ladderColumn() {
			let climbUp: Bool = jumpHeld || stickY < -0.45
			let climbDown: Bool = downHeld || stickY > 0.45
			let vyT: Double = climbUp ? -5.2 : (climbDown ? 5.2 : 0.0)
			pb.vy += (vyT - pb.vy) * min(1.0, dt * 16.0)
			var tx: Double = ix * runMax * 0.7
			// while climbing with no sideways input the body settles onto the rungs
			if ix == 0 && (climbUp || climbDown) { tx = (Double(lc) + 0.5 - pb.x) * 8.0 }
			pb.vx += (tx - pb.vx) * min(1.0, dt * 14.0)
			world.moveBody(&pb, dt, stepUp: 1.0, dropThrough: climbDown, decks: allDecks())
			coyote = 0.11
			jumpBuf = 0
			fallPeak = 0
			walkAnim += (abs(pb.vy) + abs(pb.vx)) * dt * 0.55
			lastVy = pb.vy
			checkHazards(dt)
			updateSurvival(dt, ix)
			return
		}
		// the wind (see updateWeatherForces) helps or holds back a walk, carries a jump, and in a gale
		// pushes even a player standing still; snow and wet ground make the footing slippery. All of
		// these are zero in calm weather, so movement is then exactly as it always was.
		let windT: Double = swimming ? 0 : (pb.onGround ? wxWalk : wxAirDrift)
		let swimMul: Double = (effects.value(.breathing) > 0 && !inLava) ? 0.85 : 0.55
		let target: Double = ix * runMax * (swimming ? swimMul : 1.0) + (ix != 0 ? windT : 0)
		let grip: Double = pb.onGround ? 1.0 - 0.6 * wxSlip : 1.0
		let accel: Double = (pb.onGround ? 72.0 : 40.0) * grip
		if ix != 0 {
			if pb.vx < target { pb.vx = min(target, pb.vx + accel * dt) } else { pb.vx = max(target, pb.vx - accel * dt) }
		} else {
			let rest: Double = swimming ? 0 : (pb.onGround ? wxRest : wxAirDrift)
			let fr: Double = (pb.onGround ? 90.0 * (1.0 - 0.8 * wxSlip) : 12.0) * dt
			if pb.vx > rest { pb.vx = max(rest, pb.vx - fr) } else { pb.vx = min(rest, pb.vx + fr) }
		}
		// a tornado's pull and lift (bounded; zero without one)
		if wxAccelX != 0 || wxAccelY != 0 {
			pb.vx = clampD(pb.vx + wxAccelX * dt, -16, 16)
			pb.vy = clampD(pb.vy + wxAccelY * dt, -14, terminalV)
			if wxAccelY < -8 { pb.onGround = false }
		}
		if pb.onGround { coyote = 0.11 } else { coyote -= dt }
		if jumpPressed { jumpBuf = 0.13 } else { jumpBuf -= dt }
		if jumpBuf > 0 && coyote > 0 && !swimming {
			// a jump boost raises the jump's height by its percentage
			pb.vy = -15.9 * sqrt(1.0 + effects.value(.jump) / 100.0) * suitJumpMul()
			coyote = 0
			jumpBuf = 0
			pb.onGround = false
			spawnParticles(pb.x, pb.y, 0xB0A890, 4, 2.5, 0.35, 10)
		}
		if swimming {
			pb.vy += (inLava ? 14.0 : 11.0) * dt
			if jumpHeld { pb.vy = max(pb.vy - 52.0 * dt, -6.5) }
			pb.vy = clampD(pb.vy, -8.0, inLava ? 3.0 : 6.0)
		} else {
			var g: Double = gravityG
			if !jumpHeld && pb.vy < -5.0 { g *= 2.6 }
			pb.vy = min(pb.vy + g * dt, terminalV)
		}
		if (downHeld || stickY > 0.6) { dropT = 0.22 }
		if dropT > 0 { dropT -= dt }
		let decks: [Deck] = allDecks()
		let wasAir: Bool = !pb.onGround
		let peak: Double = pb.vy
		world.moveBody(&pb, dt, stepUp: 1.0, dropThrough: dropT > 0, decks: decks)
		if pb.deck >= 0 && pb.deck < decks.count {
			let dk: Deck = decks[pb.deck]
			pb.x += dk.vx * dt
		}
		doorTouch(ix)
		updateWalkDoors(dt)
		if !pb.onGround && pb.vy > 0 { fallPeak = max(fallPeak, pb.vy) }
		if pb.onGround && wasAir {
			if fallPeak > 20.0 && !swimming && mode != .creative && !godMode {
				var dmg: Double = (fallPeak - 20.0) * 1.15
				// thrown by a tornado: a hard landing, but one that can be lived through
				if flingT > 0 { dmg = settings.weatherHurtsPlayer ? min(dmg, 3.0) : 0 }
				if dmg > 0 { damagePlayer(dmg, from: pb.x, knock: 0, ignoreArmor: true) }
				addShake(0.3)
			}
			if fallPeak > 9.0 { spawnParticles(pb.x, pb.y, 0xB0A890, 6, 3.0, 0.4, 10) }
			if fallPeak > 6.0 { sfx(.land, clampD((fallPeak - 6.0) / 14.0, 0.2, 1.0)); landT = 0.12 }
			fallPeak = 0
		}
		if pb.onGround || swimming { fallPeak = 0 }
		_ = peak
		walkAnim += abs(pb.vx) * dt * 0.55
		lastVy = pb.vy
		checkHazards(dt)
		updateSurvival(dt, ix)
	}

	/// Column of a ladder the body is on (its centre within a third of a block of the ladder), or nil.
	/// The tile right under the feet counts too, so a climb carries on until the player stands at the
	/// top, and a ladder going down a hole can be walked across.
	func ladderColumn() -> Int? {
		let cx: Int = Int(floor(pb.x))
		let frac: Double = pb.x - Double(cx)
		var cols: [Int] = [cx]
		if frac < 0.34 { cols.append(cx - 1) } else if frac > 0.66 { cols.append(cx + 1) }
		let y0: Int = Int(floor(pb.top + 0.1))
		let y1: Int = Int(floor(pb.y + 0.05))
		for tx in cols {
			var y: Int = y0
			while y <= y1 {
				let t: Tile = world.tile(tx, y)
				if t == .ladder { return tx }
				// a platform laid over the top of a ladder (a hatch) is climbed through and stepped onto
				if t == .platform && world.tile(tx, y + 1) == .ladder { return tx }
				y += 1
			}
		}
		return nil
	}

	func onLadder() -> Bool { return ladderColumn() != nil }

	/// A ledge in front of the player whose top is at most about 2.5 blocks above the feet, with room
	/// to stand on it
	func ledgeWithinReach(_ dir: Int) -> Bool {
		let fx: Int = Int(floor(pb.x + Double(dir) * (pb.w * 0.5 + 0.15)))
		let feet: Int = Int(floor(pb.y - 0.05))
		var k: Int = 0
		while k <= 3 {
			let row: Int = feet - k
			if !world.solid(fx, row) && !world.solid(fx, row - 1) && world.solid(fx, row + 1) {
				return pb.y - Double(row + 1) <= 2.6
			}
			k += 1
		}
		return false
	}

	func checkHazards(_ dt: Double) {
		if mode == .creative || godMode { return }
		// spikes underfoot, cactus touched from the side (cactus is solid, so test a slightly wider box)
		if let t = world.boxHurts(pb.left + 0.05, pb.top + 0.1, pb.right - 0.05, pb.y - 0.02) ?? world.boxHurts(pb.left - 0.04, pb.top + 0.2, pb.right + 0.04, pb.y - 0.1) {
			if t == .spikes || t == .cactus || t.isMod {
				let dmg: Double = t.isMod ? (ModRuntime.shared.blockDef(t)?.power ?? 4) : (t == .spikes ? 6 : 3)
				var info = DamageInfo(amount: dmg, type: .hazard, source: .environment)
				info.originX = pb.x + Double(-facing)
				info.knock = 5
				_ = hurtPlayer(info)
			}
		}
		if world.tile(Int(floor(pb.x)), Int(floor(pb.y - 0.5))) == .campfire { playerBurn = max(playerBurn, 1.2) }
		if pb.inLava {
			let charm: Bool = wearing(.emberCharm)
			playerBurn = max(playerBurn, charm ? 1.0 : 2.5)
			lavaT += dt
			if lavaT > 0.35 {
				lavaT = 0
				var info = DamageInfo(amount: charm ? 2 : 5, type: .lava, source: .environment)
				info.originX = pb.x
				_ = hurtPlayer(info)
			}
		} else {
			lavaT = 0
		}
		updatePlayerBurn(dt)
	}

	func updateSurvival(_ dt: Double, _ ix: Double) {
		if mode == .creative { return }
		// air
		let headY: Int = Int(floor(pb.y - pb.h * 0.92))
		// a Deepbreath Draught or a sealed suit keeps the air coming
		if world.tile(Int(floor(pb.x)), headY) == .water && effects.value(.breathing) <= 0 && !suitHas(.seal) {
			air -= dt * (wearing(.divingMask) ? 1.0 / 3.0 : 1.0)
			if air <= 0 {
				air = 0
				drownT += dt
				if drownT >= 1.0 {
					drownT = 0
					damagePlayer(2, from: pb.x, knock: 0, ignoreArmor: true)
				}
			}
		} else {
			air = min(10.0, air + dt * 5.0)
			drownT = 0
		}
		// hunger
		let rate: Double = (ix != 0 ? 0.030 : 0.016) * (pb.inWater ? 1.3 : 1.0)
		hunger = max(0, hunger - rate * dt)
		if hunger <= 0 {
			starveT += dt
			if starveT >= 3.0 {
				starveT = 0
				if hp > 1 || mode == .hardcore { damagePlayer(1, from: pb.x, knock: 0, ignoreArmor: true) }
			}
		} else {
			starveT = 0
		}
		// a frozen body does not heal until it has warmed up
		if hunger >= 14 && hp < maxHP && bodyCold < 0.9 {
			regenT += dt
			let period: Double = hunger >= 18 ? 0.9 : 1.6
			if regenT >= period {
				regenT = 0
				hp = min(maxHP, hp + 1)
				hunger = max(0, hunger - 0.12)
				bumpHUD()
			}
		} else {
			regenT = 0
		}
	}

	func damagePlayer(_ dmg: Double, from sx: Double, knock: Double = 6, ignoreArmor: Bool = false) {
		if dead || godMode || mode == .creative { return }
		if invuln > 0 && !ignoreArmor { return }
		var d: Double = dmg
		if !ignoreArmor { d *= 1.0 - armorShare(totalDefense) }
		d = max(1.0, d.rounded())
		hp -= d
		sfx(.hurt, 0.8)
		invuln = 0.55
		hurtT = 0.35
		if knock > 0 {
			let dirk: Double = pb.x >= sx ? 1.0 : -1.0
			pb.vx = dirk * knock
			pb.vy = -6.0
		}
		floatText("-" + String(Int(d)), pb.x, pb.y - pb.h - 0.3, 0xFF5050)
		addShake(0.2)
		bumpHUD()
		if hp <= 0 { die() }
	}

	/// The share of a blow that armour takes: 4% a point, at most 80% (never invincible)
	func armorShare(_ defense: Double) -> Double {
		return min(0.8, max(0, defense) * 0.04)
	}

	func heal(_ amount: Double) {
		hp = min(maxHP, hp + amount)
		bumpHUD()
	}

	func die() {
		if dead { return }
		dead = true
		hp = 0
		deathT = 0
		mounted = nil
		if let v = inVehicle { v.rider = false }
		inVehicle = nil
		spawnParticles(pb.x, pb.y - 1, 0xC03030, 24, 6.0, 0.9, 16)
		say(mode == .hardcore ? "You died. Your hardcore world is lost." : "You died!", 5.0)
		if mode == .hardcore { hardcoreOver = true }
		bumpHUD()
	}

	func respawn() {
		if mode == .hardcore && hardcoreOver { return }
		if world.dim != .overworld { travelTo(.overworld, arriveX: spawnX, arriveY: spawnY, silent: true) }
		dimReturn = nil
		dead = false
		hp = maxHP
		hunger = max(hunger, 14)
		air = 10
		pb.x = spawnX
		pb.y = spawnY
		pb.vx = 0
		pb.vy = 0
		invuln = 3.0
		fallPeak = 0
		world.loadAround(centerX: Int(spawnX), radius: 3)
		let sy: Int = world.surfaceY(Int(spawnX))
		pb.y = Double(sy)
		camX = pb.x
		camY = pb.y - 2
		say("Respawned.", 2.0)
		bumpHUD()
	}

	// MARK: camera, streaming, light

	/// Camera follow: a dead zone around the player, optional look-ahead in the direction of travel
	/// (eased so turning around does not jerk the view), and frame-rate independent exponential smoothing.
	func updateCamera(_ dt: Double) {
		let st: Settings = settings
		// look ahead: further when driving fast, eased in and out
		var leadTarget: Double = 0
		if st.camLookAhead && !st.camDirect {
			if let v = inVehicle {
				leadTarget = clampD(v.vx * 0.35, -6.0, 6.0)
			} else if abs(pb.vx) > 1.0 {
				leadTarget = Double(facing) * 1.6
			}
		}
		camLead += (leadTarget - camLead) * min(1.0, dt * 2.5)
		let fx: Double = pb.x + camLead
		let fy: Double = pb.y - 1.6
		// the target only moves once the player leaves the dead zone around it
		let dz: Double = st.camDirect ? 0 : clampD(st.camDeadZone, 0, 4)
		if fx > camTX + dz { camTX = fx - dz } else if fx < camTX - dz { camTX = fx + dz }
		let dzy: Double = dz * 0.75
		if fy > camTY + dzy { camTY = fy - dzy } else if fy < camTY - dzy { camTY = fy + dzy }
		if abs(camTX - camX) > 40 || abs(camTY - camY) > 40 || !st.camSmoothOn {
			// teleports, respawns and "smoothing off" snap straight to the target
			camX = camTX
			camY = camTY
		} else {
			let rate: Double = st.camDirect ? 12.0 : 2.5 + clampD(st.camFollow, 0, 1) * 11.5
			let k: Double = 1.0 - exp(-rate * dt)
			camX += (camTX - camX) * k
			camY += (camTY - camY) * k
		}
		let halfW: Double = viewTilesW * 0.5
		let halfH: Double = viewTilesH * 0.5
		if !gen.infinite {
			if viewTilesW < Double(gen.width) { camX = clampD(camX, halfW, Double(gen.width) - halfW) }
		}
		let Hh: Double = Double(world.H)
		camY = clampD(camY, halfH - 14.0, Hh - halfH + 1.0)
	}

	func updateStreaming() {
		let need: Int = Int(ceil(viewTilesW * 0.5 / Double(chunkW))) + 2
		loadRadius = need
		var keep: Set<Int> = []
		for m in mobs where m.persistent || m.isBoss || m.tame {
			keep.insert(floorDiv(Int(floor(m.b.x)), chunkW))
		}
		for v in vehicles { keep.insert(floorDiv(Int(floor(v.b.x)), chunkW)) }
		let cx: Int = Int(floor(camX))
		let n: Int = world.stream(centerX: cx, radius: loadRadius, hysteresis: 3, budget: 1, keep: keep)
		chunksLoadedLast = n
		// keep the player's own chunk always available
		let pc: Int = floorDiv(Int(floor(pb.x)), chunkW)
		if world.chunks[pc] == nil { world.loadChunk(pc) }
	}

	func heldLightLevel() -> Int {
		if let it = heldItem, case .custom(let k) = it, let r = ModRuntime.shared.item(k), r.def.light > 0 { return r.def.light }
		if let it = heldItem, case .block(let t) = it {
			let l: Int = t.light
			if l >= 9 { return l - 2 }
		}
		return 0
	}

	func updateLight(_ dt: Double) {
		lightTimer -= dt
		// dynamic lights
		var dyn: [(Int, Int, Int)] = []
		let pcx: Int = Int(floor(pb.x))
		let pcy: Int = Int(floor(pb.y - pb.h * 0.6))
		var hl: Int = heldLightLevel()
		hl = max(hl, wearing(.headlamp) ? 11 : 5)
		hl = max(hl, Int(effects.value(.glow)))
		if suitLit { hl = max(hl, 12) }
		dyn.append((pcx, pcy, hl))
		for m in mobs {
			var lv: Int = 0
			switch m.kind {
			case .emberSlime: lv = 9
			case .imp: lv = 8
			case .wraith: lv = 6
			case .cinderBat: lv = 6
			case .bearBoss, .rex: lv = m.isBoss ? 6 : 0
			case .sentinel: lv = 9
			case .warden: lv = 10
			case .custom: lv = clampI(ModRuntime.shared.mob(m.cslot)?.def.glow ?? 0, 0, 12)
			default: lv = 0
			}
			if m.burn > 0 { lv = max(lv, 6) }
			if lv > 0 { dyn.append((Int(floor(m.b.x)), Int(floor(m.b.y - m.b.h * 0.5)), lv)) }
		}
		for p in projectiles where p.mod >= 0 && p.mod < ModRuntime.shared.shots.count {
			let gl: Int = ModRuntime.shared.shots[p.mod].glow
			if gl > 0 { dyn.append((Int(floor(p.x)), Int(floor(p.y)), gl)) }
		}
		for p in projectiles where p.kind == .fireball || p.kind == .bomb {
			// fireballs glow; a bomb's lit fuse gives a small light
			dyn.append((Int(floor(p.x)), Int(floor(p.y)), p.kind == .fireball ? 10 : 5))
		}
		for f in flashes {
			let lv: Int = f.level
			if lv > 0 { dyn.append((Int(floor(f.x)), Int(floor(f.y)), lv)) }
		}
		for z in fireZones { dyn.append((Int(floor(z.x)), Int(floor(z.y - 0.6)), 11)) }
		for s in ships {
			dyn.append((Int(floor(s.x)) - 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
			dyn.append((Int(floor(s.x)) + 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
		}
		for v in vehicles where v.rider && v.engines > 0 && v.fuel > 0 {
			dyn.append((Int(floor(v.b.x + Double(v.dir) * (v.b.w * 0.5 + 1.0))), Int(floor(v.b.y - v.b.h * 0.5)), 10))
		}
		// headlights throw a beam ahead of a driven vehicle
		for v in vehicles where v.rider && v.headlights > 0 {
			for (cell, t) in v.parts where t == .headlight {
				let d: Double = Double(v.dir)
				for (k, lv) in [(0.0, 10), (2.5, 14), (5.0, 13), (7.5, 11)] {
					let p: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + d * k, Double(cell.dy) + 0.5)
					dyn.append((Int(floor(p.0)), Int(floor(p.1)), lv))
				}
			}
		}
		let nightVision: Bool = effects.value(.nightVision) > 0
		var key: Int = dyn.count &+ (nightVision ? 7919 : 0)
		for d in dyn { key = key &* 31 &+ d.0 &* 7 &+ d.1 &* 13 &+ d.2 }
		// window
		let vw: Int = Int(ceil(viewTilesW)) + 2
		let vh: Int = Int(ceil(viewTilesH)) + 2
		let vx0: Int = Int(floor(camX - viewTilesW * 0.5)) - 1
		let vy0: Int = Int(floor(camY - viewTilesH * 0.5)) - 1
		let covered: Bool = light.covers(vx0 - 3, vy0 - 3, vx0 + vw + 3, vy0 + vh + 3)
		// only edits that touch the light window matter (crops growing far away do not)
		var edited: Bool = false
		if world.editAny {
			let ex0: Int = light.ox - 1
			let ex1: Int = light.ox + light.w
			let ey0: Int = light.oy - 1
			let ey1: Int = light.oy + light.h
			if world.editX1 >= ex0 && world.editX0 <= ex1 && world.editY1 >= ey0 && world.editY0 <= ey1 {
				edited = true
			} else {
				world.editAny = false
			}
		}
		let layoutChanged: Bool = light.layoutUsed != world.layoutVersion
		let needsStatic: Bool = !light.valid || !covered || light.skyUsed != skyLevel || light.dimUsed != world.dim.rawValue || edited || layoutChanged
		var amb: Double = fullBright ? 1.0 : (world.dim == .umbral ? 0.2 : (world.dim.isCustom ? 0.12 : 0.07))
		// an Owlsight Draught lifts the dark
		if nightVision { amb = max(amb, 0.5) }
		if !needsStatic {
			// only moving lights changed: cheap partial relight
			if light.dynUsed == key { return }
			let t0: Double = perfNow()
			light.applyDynamic(dyn)
			light.dynUsed = key
			light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
			lightRev &+= 1
			Perf.shared.lightDyn += 1
			Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
			return
		}
		if lightTimer > 0 && light.valid && covered && light.dimUsed == world.dim.rawValue { return }
		let t0: Double = perfNow()
		lightTimer = 0.04
		let m: Int = 17
		var ox: Int = vx0 - m
		ox = floorDiv(ox, 4) * 4
		var oy: Int = vy0 - m
		oy = floorDiv(oy, 4) * 4
		var w: Int = (vx0 + vw + m) - ox + 4
		w = (w / 4 + 1) * 4
		var h: Int = (vy0 + vh + m) - oy + 4
		h = (h / 4 + 1) * 4
		light.compute(world, ox, oy, w, h, skyLevel, dyn)
		light.dynUsed = key
		light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
		lightRev &+= 1
		Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
	}

	// MARK: random world ticks (crops, grass)

	func updateWorldTicks(_ dt: Double) {
		let n: Int = 7
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y))
		for _ in 0..<n {
			let x: Int = px + Int.random(in: -40...40)
			let y: Int = py + Int.random(in: -26...26)
			let t: Tile = world.tile(x, y)
			// rain falling on a crop (not snow) helps it along
			var grow: Double = 0.35
			if t.isPlant && weatherRain > 0.2 && !weatherSnow && y < world.rainTop(x) + 1 { grow = 0.35 + 0.3 * weatherRain }
			switch t {
			case .wheat1: if Double.random(in: 0...1) < grow { world.set(x, y, .wheat2) }
			case .wheat2: if Double.random(in: 0...1) < grow { world.set(x, y, .wheat3) }
			case .carrot1: if Double.random(in: 0...1) < grow { world.set(x, y, .carrot2) }
			case .carrot2: if Double.random(in: 0...1) < grow { world.set(x, y, .carrot3) }
			case .sapling: if Double.random(in: 0...1) < grow * 0.4 { growSapling(x, y) }
			case .dirt:
				if world.dim == .overworld && y < world.skyTop(x) + 1 && world.tile(x, y - 1) == .air {
					let a: Tile = world.tile(x - 1, y)
					let b: Tile = world.tile(x + 1, y)
					if a == .grass || b == .grass { if Double.random(in: 0...1) < 0.2 { world.set(x, y, .grass) } }
				}
			case .grass:
				if world.tile(x, y - 1).opaque && Double.random(in: 0...1) < 0.3 { world.set(x, y, .dirt) }
			default: break
			}
		}
		updateLeafDecay(dt)
		// lantern/torch/crop support is checked when neighbours change (see breakTile)
	}

	/// Open air or a wild plant a growing tree may take the place of (never a torch or anything built)
	func treeRoom(_ t: Tile) -> Bool {
		return t == .air || t == .tallGrass || t == .flowerR || t == .flowerY || t == .deadBush
	}

	/// A sapling grows into a tree that suits the land it stands in: a pine in snow and on mountains, a
	/// tall jungle tree, a flat-topped savanna tree, a low swamp tree, a birch or an oak elsewhere (in a
	/// custom dimension, a tree of its region's own log and leaves). It grows as tall as the room above
	/// it allows, and waits while there is not room for its smallest kind. True when it grew.
	@discardableResult
	func growSapling(_ x: Int, _ y: Int) -> Bool {
		if world.tile(x, y) != .sapling || !world.isSoil(world.tile(x, y + 1)) { return false }
		let r: Double = Double.random(in: 0..<1)
		var log: Tile = .log
		var leaves: Tile = .leaves
		// 0 oak, 1 birch, 2 pine, 3 jungle, 4 savanna, 5 swamp
		var shape: Int = 0
		if let d = customDim {
			let z: ModDimZoneRT = d.zones[d.zoneIndex(x)]
			log = z.log
			leaves = z.leaves
		} else {
			switch biomeAt(Double(x)) {
			case .tundra, .mountain: shape = 2; leaves = .pineLeaves
			case .jungle: shape = 3; log = .jungleLog; leaves = .jungleLeaves
			case .savanna: shape = 4
			case .swamp: shape = 5; leaves = .jungleLeaves
			default: if r < 0.3 { shape = 1; log = .birchLog; leaves = .birchLeaves }
			}
		}
		let wants: [Int] = [4 + Int(r * 4.0), 6 + Int(r * 4.0), 6 + Int(r * 5.0), 9 + Int(r * 6.0), 5 + Int(r * 3.0), 4 + Int(r * 2.0)]
		let least: [Int] = [4, 5, 6, 8, 5, 4]
		// free cells straight up from the sapling (its own cell counts): the trunk and two above it
		var room: Int = 1
		while room < wants[shape] + 2 && treeRoom(world.tile(x, y - room)) { room += 1 }
		let th: Int = min(wants[shape], room - 2)
		if th < least[shape] { return false }
		let gy: Int = y + 1
		for k in 1...th { world.set(x, gy - k, log) }
		func leaf(_ lx: Int, _ ly: Int) {
			if treeRoom(world.tile(lx, ly)) { world.set(lx, ly, leaves) }
		}
		let top: Int = gy - th
		switch shape {
		case 1:
			for dy in -4...0 {
				let w: Int = (dy == -4 || dy == 0) ? 1 : 2
				for dx in -w...w { leaf(x + dx, top + dy) }
			}
			leaf(x, top - 5)
		case 2:
			var layer: Int = 0
			while layer < th - 1 {
				let w: Int = min(3, 1 + layer / 2)
				for dx in -w...w { leaf(x + dx, top - 1 + layer) }
				layer += 1
			}
			leaf(x, top - 2)
		case 3:
			for dy in -3...1 {
				for dx in -4...4 where !(abs(dx) == 4 && abs(dy + 1) > 1) && abs(dx) + abs(dy + 1) <= 6 { leaf(x + dx, top + dy) }
			}
		case 4:
			for dx in -4...4 { leaf(x + dx, top) }
			for dx in -2...2 { leaf(x + dx, top - 1) }
		case 5:
			for dx in -3...3 {
				leaf(x + dx, top)
				if abs(dx) < 3 { leaf(x + dx, top - 1) }
			}
		default:
			for dy in -3...1 {
				for dx in -2...2 where !(abs(dx) == 2 && (dy == -3 || dy == 1)) { leaf(x + dx, top + dy) }
			}
		}
		spawnParticles(Double(x) + 0.5, Double(top) + 0.5, 0x56A83F, 8, 3.0, 0.6, 10)
		return true
	}
}

// ===== p14c_input =====

// MARK: - Pointer input, interaction, inventory operations, crafting

extension Game {
	// MARK: pointer (world coordinates in tiles)

	func pointerDown(_ wx: Double, _ wy: Double) {
		aimX = wx
		aimY = wy
		aimValid = true
		if capturing {
			if !showCapture { captureTap(wx, wy) }
			return
		}
		downTime = 0
		usePressedFlag = false
		touchActive = true
		// with a weapon out, a tap on a foe is an attack, even if a door or chest is behind it
		let fight: Bool = (heldItem?.isWeapon ?? false) && hostileAt(wx, wy)
		if !fight && isInteractive(wx, wy) {
			pendingInteract = true
			useHeld = false
		} else {
			pendingInteract = false
			useHeld = true
			useWasHeld = false
		}
		pointerStartX = wx
		pointerStartY = wy
	}

	func pointerMove(_ wx: Double, _ wy: Double) {
		aimX = wx
		aimY = wy
		aimValid = true
		if capturing { return }
		if pendingInteract {
			let dx: Double = wx - pointerStartX
			let dy: Double = wy - pointerStartY
			if dx * dx + dy * dy > 0.5 {
				pendingInteract = false
				useHeld = true
			}
		}
	}

	func pointerUp() {
		touchActive = false
		if capturing {
			useHeld = false
			pendingInteract = false
			return
		}
		if pendingInteract {
			if downTime < 0.3 { interact(aimX, aimY) }
			pendingInteract = false
		}
		// the action button may still be held: then it carries on (and aims for itself again)
		if actState.held { return }
		if useHeld { useReleasedFlag = true }
		useHeld = false
		useWasHeld = false
	}

	/// A wild animal (bear, elephant, wolf, grizzly, polar bear, tiger, scorpion): neutral to the player
	func isWildAnimal(_ k: MobKind) -> Bool {
		switch k {
		case .elephant, .bear, .wolf, .grizzly, .polarBear, .tiger, .scorpion: return true
		default: return false
		}
	}

	/// A wild hunter the player has hurt lately (it fights back for twelve seconds)
	func wildProvoked(_ m: Mob) -> Bool {
		return clock - m.lastHitByPlayer < 12.0
	}

	/// A creature that is out to hurt the player: monsters and enemies, and animals once angered
	func isThreat(_ m: Mob) -> Bool {
		if m.angry { return true }
		if isWildAnimal(m.kind) { return wildProvoked(m) }
		return m.def.hostile
	}

	/// a hostile (or angered) creature under or right next to a point
	func hostileAt(_ wx: Double, _ wy: Double) -> Bool {
		for m in mobsNear(wx - 4, wx + 4) where m.hp > 0 && !m.tame && isThreat(m) {
			if wx >= m.b.left - 0.4 && wx <= m.b.right + 0.4 && wy >= m.b.top - 0.4 && wy <= m.b.y + 0.4 { return true }
		}
		return false
	}

	func updatePointerTimers(_ dt: Double) {
		if pendingInteract {
			downTime += dt
			if downTime >= 0.3 {
				pendingInteract = false
				useHeld = true
				useWasHeld = false
			}
		}
	}

	func reachDistance() -> Double {
		if infiniteReach { return 60 }
		return isCreative ? 8.0 : 5.5
	}

	func inReach(_ x: Double, _ y: Double) -> Bool {
		let dx: Double = x - pb.x
		let dy: Double = y - (pb.y - pb.h * 0.6)
		let r: Double = reachDistance()
		return dx * dx + dy * dy <= r * r
	}

	// MARK: interactive targets

	func mobAtPoint(_ wx: Double, _ wy: Double, _ pad: Double) -> Mob? {
		var best: Mob? = nil
		var bd: Double = 1e9
		for m in mobs {
			if m.hp <= 0 { continue }
			let x0: Double = m.b.left - pad
			let x1: Double = m.b.right + pad
			let y0: Double = m.b.top - pad
			let y1: Double = m.b.y + pad
			if wx >= x0 && wx <= x1 && wy >= y0 && wy <= y1 {
				let d: Double = abs(wx - m.b.x) + abs(wy - m.b.cy)
				if d < bd { bd = d; best = m }
			}
		}
		return best
	}

	func vehicleAtPoint(_ wx: Double, _ wy: Double) -> (Vehicle, PartCell)? {
		for v in vehicles {
			if wx < v.b.left - 0.2 || wx > v.b.right + 0.2 || wy < v.b.top - 0.2 || wy > v.b.y + 0.2 { continue }
			// pick in the vehicle's own (rotated) grid
			let c: PartCell = v.cellAt(wx, wy)
			if v.parts[c] != nil { return (v, c) }
		}
		return nil
	}

	func shipChestAt(_ wx: Double, _ wy: Double) -> PirateShip? {
		for s in ships {
			if s.looted { continue }
			let dy: Double = s.deckY(Double(WorldGen.sea))
			if abs(wx - (s.x - 2.5)) < 1.2 && abs(wy - (dy - 0.6)) < 1.4 { return s }
		}
		return nil
	}

	func isInteractive(_ wx: Double, _ wy: Double) -> Bool {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		let t: Tile = world.tile(tx, ty)
		// with wire in hand every tap lays or cuts wire, even over a door or a lever
		if holdingWireSpool { return false }
		if case .gadget(.probe)? = heldItem { return t.isPower || world.wireAt(tx, ty) != 0 }
		if t.isPower { return true }
		if t.isMod {
			guard let b = ModRuntime.shared.blockDef(t) else { return true }
			if b.function != .none && b.function != .bounce && b.function != .trap { return true }
		}
		switch t {
		case .chest, .workbench, .furnace, .campfire, .portalOff, .doorClosed, .doorOpen, .anvil, .tinkerBench, .riftForge, .alchemyStill, .infuser, .exoStation: return true
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .shutterClosed, .shutterOpen: return true
		case .chair, .sofa, .bedL, .bedR, .cabinet, .wardrobe, .liftButton: return true
		default: break
		}
		if liftAt(wx, wy) != nil { return true }
		if let m = mobAtPoint(wx, wy, 0.15) {
			if m.tame { return true }
		}
		if vehicleAtPoint(wx, wy) != nil {
			if let it = heldItem, case .part = it { return false }
			if let it = heldItem, case .gadget(let g) = it, g == .wrench { return false }
			return true
		}
		if shipChestAt(wx, wy) != nil { return true }
		return false
	}

	func interact(_ wx: Double, _ wy: Double) {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		if !inReach(wx, wy) && !(mobAtPoint(wx, wy, 0.2)?.tame ?? false) {
			say("Too far away.", 1.2)
			return
		}
		let t: Tile = world.tile(tx, ty)
		if case .gadget(.probe)? = heldItem {
			probeAt(wx, wy)
			return
		}
		if case .gadget(.wrench)? = heldItem, wrenchLift(wx, wy) { return }
		if t == .exoStation {
			openExo()
			return
		}
		if t.isPower && t != .windTurbine {
			usePowerDevice(tx, ty, t)
			return
		}
		if t.isMod && interactModBlock(tx, ty, t) { return }
		switch t {
		case .chest:
			if tryMimic(tx, ty) { return }
			let firstLook: Bool = world.chests[world.chestKey(tx, ty)] == nil
			sfx(.chestOpen, 0.7)
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.3, 0xC8A878, 5, 2.0, 0.4, 6)
			if firstLook && world.chestItems(tx, ty).contains(where: { MineLoot.isExceptional($0.item) }) {
				// a rare find: it should feel like one
				sfx(.rareLoot, 0.8)
				spawnParticles(Double(tx) + 0.5, Double(ty) + 0.2, 0xFFE070, 16, 3.5, 0.9, -3)
				addLightFlash(Double(tx) + 0.5, Double(ty) + 0.3, peak: 10, dur: 0.8, radius: 1.8, color: 0xFFD860)
				say("Something rare glints in this chest!", 2.5)
			}
			openChest = IntPair(x: tx, y: ty)
			showInventory = true
			bumpHUD()
			return
		case .workbench:
			craftStation = .bench
			showInventory = true
			bumpHUD()
			return
		case .furnace:
			craftStation = .furnace
			showInventory = true
			bumpHUD()
			return
		case .campfire:
			craftStation = .campfire
			showInventory = true
			bumpHUD()
			return
		case .anvil, .tinkerBench, .riftForge:
			craftStation = t == .anvil ? .anvil : (t == .tinkerBench ? .tinker : .forge)
			showInventory = true
			bumpHUD()
			return
		case .alchemyStill:
			craftStation = .still
			showInventory = true
			sfx(.splash, 0.3)
			bumpHUD()
			return
		case .infuser:
			openInfuser()
			return
		case .portalOff:
			tryOpenPortal(tx, ty)
			return
		case .doorClosed, .doorOpen:
			toggleDoor(tx, ty)
			return
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .shutterClosed, .shutterOpen:
			useWeatherDevice(tx, ty, t)
			return
		case .chair, .sofa:
			sitOn(tx, ty)
			return
		case .bedL, .bedR:
			sleepIn(tx, ty)
			return
		case .cabinet, .wardrobe:
			openStorage(tx, ty)
			return
		case .liftButton:
			callLift(tx, ty)
			return
		default: break
		}
		if let l = liftAt(wx, wy) {
			rideLiftTap(l, wy)
			return
		}
		if let m = mobAtPoint(wx, wy, 0.2) {
			interactMob(m)
			return
		}
		if let (v, c) = vehicleAtPoint(wx, wy) {
			interactVehicle(v, c)
			return
		}
		if let s = shipChestAt(wx, wy) {
			lootShip(s)
			return
		}
	}

	func interactMob(_ m: Mob) {
		switch m.kind {
		case .rex:
			if m.tame { mountRex(m) }
		case .wolf, .cat:
			if m.tame {
				m.st = m.st == 7 ? 0 : 7
				say(m.st == 7 ? "Your pet will stay here." : "Your pet follows you.", 2.0)
			}
		default: break
		}
	}

	func tryOpenPortal(_ tx: Int, _ ty: Int) {
		let key: Item = .gadget(.portalKey)
		if !isCreative && inv.total(key) < 1 {
			say("The portal is sealed. It needs a Portal Key.", 3.0)
			return
		}
		if !isCreative { _ = inv.remove(key, 1) }
		// flood fill all dormant portal tiles
		var stack: [IntPair] = [IntPair(x: tx, y: ty)]
		var count: Int = 0
		while let p = stack.popLast() {
			if world.tile(p.x, p.y) != .portalOff { continue }
			world.set(p.x, p.y, .portalOn)
			count += 1
			if count > 80 { break }
			stack.append(IntPair(x: p.x + 1, y: p.y))
			stack.append(IntPair(x: p.x - 1, y: p.y))
			stack.append(IntPair(x: p.x, y: p.y + 1))
			stack.append(IntPair(x: p.x, y: p.y - 1))
		}
		portalOpened = true
		spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, 0xF0A848, 40, 7.0, 1.2, 0)
		addShake(0.5)
		say("The rift tears open! Walk into it to cross to the Umbral Realm.", 5.0)
		sfx(.portal, 1.0)
		bumpHUD()
	}

	func lootShip(_ s: PirateShip) {
		if !s.crew.isEmpty {
			var alive: Bool = false
			for id in s.crew { for m in mobs { if m.id == id && m.hp > 0 { alive = true } } }
			if alive {
				say("Defeat the crew first!", 2.0)
				return
			}
		}
		s.looted = true
		var rng = RNG(UInt64(truncatingIfNeeded: s.id) &* 7919 &+ gen.seed)
		giveItem(.mat(.goldBar), 3 + rng.int(6))
		giveItem(.ammo(.bullet), 8 + rng.int(14))
		giveItem(.mat(.gunpowder), 2 + rng.int(5))
		if rng.double() < 0.35 { giveItem(.gun(.pistol), 1) }
		if rng.double() < 0.5 { giveItem(.mat(.diamond), 1 + rng.int(3)) }
		giveItem(.food(.cookedFish), 2 + rng.int(4))
		say("You looted the pirate treasure!", 3.0)
		spawnParticles(s.x - 2.5, s.deckY(Double(WorldGen.sea)) - 1, 0xF5D142, 20, 5.0, 0.9, 12)
	}

	// MARK: inventory operations (used by the UI)

	func tapSlot(_ i: Int) {
		if let h = carry {
			// place carried stack
			if let s = inv.slots[i] {
				if s.item == h.item && h.item.maxStack > 1 {
					let room: Int = h.item.maxStack - s.count
					let put: Int = min(room, h.count)
					var ns: Stack = s
					ns.count += put
					inv.slots[i] = ns
					if h.count - put > 0 {
						var c: Stack = h
						c.count = h.count - put
						carry = c
					} else {
						carry = nil
					}
				} else {
					inv.slots[i] = h
					carry = s
				}
			} else {
				inv.slots[i] = h
				carry = nil
			}
		} else if let s = inv.slots[i] {
			carry = s
			inv.slots[i] = nil
		}
		bumpHUD()
	}

	func splitSlot(_ i: Int) {
		if carry != nil { return }
		if let s = inv.slots[i], s.count > 1 {
			let half: Int = s.count / 2
			var a: Stack = s
			a.count = s.count - half
			var b: Stack = s
			b.count = half
			inv.slots[i] = a
			carry = b
			bumpHUD()
		}
	}

	// MARK: drag and drop

	enum SlotRef: Hashable {
		case inv(Int)
		case armor(Int)
		case chest(Int)
		case drop
		/// creative mode: back to the creative menu
		case trash
	}

	func stackAt(_ r: SlotRef) -> Stack? {
		switch r {
		case .inv(let i): return i >= 0 && i < inv.slots.count ? inv.slots[i] : nil
		case .armor(let i): return i >= 0 && i < inv.armor.count ? inv.armor[i] : nil
		case .chest(let i):
			guard let p = openChest else { return nil }
			let items: [Stack] = world.chestItems(p.x, p.y)
			return i >= 0 && i < items.count ? items[i] : nil
		case .drop, .trash: return nil
		}
	}

	private func tapRef(_ r: SlotRef) {
		switch r {
		case .inv(let i): tapSlot(i)
		case .armor(let i): tapArmorSlot(i)
		case .chest(let i): if let p = openChest { chestTapSlot(p.x, p.y, i) }
		case .drop: dropCarried()
		case .trash: discardCarried()
		}
	}

	/// Drags the stack in `from` onto `to`: places, merges or swaps using the same rules as tapping, so
	/// armour only goes into its own slot and chests keep their limits. Anything that cannot land goes
	/// back where it came from (or into the bag).
	func dragStack(from: SlotRef, to: SlotRef?) {
		if carry != nil { returnCarried() }
		if stackAt(from) == nil { return }
		tapRef(from)
		guard carry != nil else { return }
		if let to = to, to != from {
			tapRef(to)
		}
		if carry != nil {
			// put the remainder (or the swapped stack) back into the slot the drag started from
			switch from {
			case .chest:
				if let p = openChest { chestTapSlot(p.x, p.y, Int.max) }
			default:
				if stackAt(from) == nil { tapRef(from) }
			}
		}
		if carry != nil { returnCarried() }
		bumpHUD()
	}

	func sortBag() {
		returnCarried()
		inv.sortBag()
		say("Bag sorted.", 1.2)
		bumpHUD()
	}

	/// Folds partial stacks together across the bag and hotbar
	func stackAll() {
		returnCarried()
		let n: Int = inv.mergeStacks()
		say(n > 0 ? "Stacks merged." : "Nothing to merge.", 1.2)
		bumpHUD()
	}

	/// Creative mode: the held stack goes back to the creative menu (it leaves the bag). In survival it
	/// is thrown away instead, as with DROP.
	func discardCarried() {
		if carry == nil { return }
		if !isCreative {
			dropCarried()
			return
		}
		carry = nil
		sfx(.tap, 0.5)
		bumpHUD()
	}

	/// Moves every bag stack (not the hotbar) whose item the open chest already holds into that chest
	func quickStack() {
		guard let p = openChest else { return }
		var items: [Stack] = world.chestItems(p.x, p.y)
		var moved: Int = 0
		for i in Inventory.hotbarCount..<inv.slots.count {
			guard var s = inv.slots[i] else { continue }
			if !items.contains(where: { $0.item == s.item }) { continue }
			// top up existing chest stacks first, then use free chest slots
			if s.item.maxStack > 1 {
				for k in 0..<items.count where items[k].item == s.item && items[k].extra == s.extra && items[k].inf == s.inf && items[k].count < s.item.maxStack && s.count > 0 {
					let put: Int = min(s.item.maxStack - items[k].count, s.count)
					items[k].count += put
					s.count -= put
					moved += put
				}
			}
			if s.count > 0 && items.count < 27 {
				items.append(s)
				moved += s.count
				s.count = 0
			}
			inv.slots[i] = s.count > 0 ? s : nil
		}
		world.setChestItems(p.x, p.y, items)
		say(moved > 0 ? "Stored \(moved) items in the chest." : "Nothing here matches the chest.", 1.5)
		bumpHUD()
	}

	func dropCarried() {
		if let c = carry {
			spawnDrop(c, pb.x + Double(facing) * 0.8, pb.y - 1.2, Double(facing) * 4.0, -4.0, heldBack: true)
			carry = nil
			bumpHUD()
		}
	}

	func returnCarried() {
		if let c = carry {
			let left: Int = inv.add(c.item, c.count, extra: c.extra, inf: c.inf)
			if left > 0 { spawnDrop(Stack(item: c.item, count: left, extra: c.extra, inf: c.inf), pb.x, pb.y - 1.0, 2.0, -3.0) }
			carry = nil
			bumpHUD()
		}
	}

	/// Whether an item may go into armour slot `i`: armour into its own slot, gear into either gear slot
	func fitsArmorSlot(_ it: Item, _ i: Int) -> Bool {
		switch it {
		case .armor(let slot, _): return slot.rawValue == i && !(suit.worn && i < 3)
		case .gear: return i >= Inventory.firstGearSlot && i < inv.armor.count
		case .custom(let k):
			guard let r = ModRuntime.shared.item(k), r.def.kind == .armor else { return false }
			return r.def.slot == i && !(suit.worn && i < 3)
		default: return false
		}
	}

	func tapArmorSlot(_ i: Int) {
		if i < 0 || i >= inv.armor.count { return }
		if let h = carry {
			if fitsArmorSlot(h.item, i) {
				let old: Stack? = inv.armor[i]
				inv.armor[i] = h
				carry = old
			}
		} else if let s = inv.armor[i] {
			carry = s
			inv.armor[i] = nil
		}
		bumpHUD()
	}

	func quickEquip(_ i: Int) {
		guard let s = inv.slots[i] else { return }
		var target: Int = -1
		switch s.item {
		case .armor(let slot, _): target = slot.rawValue
		case .gear(let g):
			// the same piece already worn is swapped out; otherwise the first free gear slot, else the first
			target = Inventory.firstGearSlot
			var free: Int = -1
			for k in Inventory.firstGearSlot..<inv.armor.count {
				if let w = inv.armor[k], case .gear(let x) = w.item, x == g { free = k; break }
				if inv.armor[k] == nil && free < 0 { free = k }
			}
			if free >= 0 { target = free }
		case .custom(let k):
			guard let r = ModRuntime.shared.item(k), r.def.kind == .armor else { return }
			target = clampI(r.def.slot, 0, 2)
		default: return
		}
		if target < 0 || target >= inv.armor.count { return }
		let old: Stack? = inv.armor[target]
		inv.armor[target] = s
		inv.slots[i] = old
		bumpHUD()
	}

	func wearing(_ g: Gear) -> Bool { return inv.wearing(g) }

	// chest transfer
	func chestTapSlot(_ cx: Int, _ cy: Int, _ idx: Int) {
		var items: [Stack] = world.chestItems(cx, cy)
		if let h = carry {
			if idx < items.count {
				let s: Stack = items[idx]
				if s.item == h.item && h.item.maxStack > 1 {
					var ns: Stack = s
					let put: Int = min(h.item.maxStack - s.count, h.count)
					ns.count += put
					items[idx] = ns
					if h.count - put > 0 { var c: Stack = h; c.count = h.count - put; carry = c } else { carry = nil }
				} else {
					items[idx] = h
					carry = s
				}
			} else if items.count < 27 {
				items.append(h)
				carry = nil
			}
		} else if idx < items.count {
			carry = items[idx]
			items.remove(at: idx)
		}
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	func chestQuickMove(_ cx: Int, _ cy: Int, _ idx: Int) {
		var items: [Stack] = world.chestItems(cx, cy)
		if idx >= items.count { return }
		let s: Stack = items[idx]
		let left: Int = inv.add(s.item, s.count, extra: s.extra, inf: s.inf)
		if left == 0 { items.remove(at: idx) } else { items[idx].count = left }
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	func chestStore(_ cx: Int, _ cy: Int, _ slotIndex: Int) {
		guard let s = inv.slots[slotIndex] else { return }
		var items: [Stack] = world.chestItems(cx, cy)
		if items.count >= 27 { say("Chest is full.", 1.5); return }
		items.append(s)
		inv.slots[slotIndex] = nil
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	// MARK: crafting

	func stationAvailable(_ s: Station) -> Bool {
		if s == .hand { return true }
		if isCreative { return true }
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1))
		for dy in -4...3 {
			for dx in -5...5 {
				let t: Tile = world.tile(px + dx, py + dy)
				// a mod block that works as this station
				if t.isMod, let b = ModRuntime.shared.blockDef(t), b.function == .station, b.station == s.rawValue { return true }
				switch s {
				case .bench: if t == .workbench { return true }
				case .furnace: if t == .furnace { return true }
				case .campfire: if t == .furnace || t == .campfire { return true }
				case .anvil: if t == .anvil { return true }
				case .tinker: if t == .tinkerBench { return true }
				case .forge: if t == .riftForge { return true }
				case .still: if t == .alchemyStill { return true }
				case .infuser: if t == .infuser { return true }
				case .assembly: if t == .exoStation { return true }
				case .hand: return true
				}
			}
		}
		return false
	}

	func canCraft(_ r: Recipe) -> Bool {
		if !recipeStationOK(r) { return false }
		if !inv.canAfford(r.cost) { return false }
		return inv.canFit(r.out, r.outCount)
	}

	func craft(_ r: Recipe) {
		if !canCraft(r) {
			if !recipeStationOK(r) { say("Needs a " + recipeStationName(r) + " nearby.", 2.0) }
			return
		}
		for c in r.cost { _ = inv.remove(c.item, c.n) }
		if !journal.crafted.contains(r.out.name) { journal.crafted.append(r.out.name) }
		sfx(.craft, 0.6)
		// a new storm rod comes charged; firearms and crossbows still need loading
		let ex: Int = r.out == .gun(.stormRod) ? GunType.stormRod.magazine : 0
		let left: Int = inv.add(r.out, r.outCount, extra: ex)
		if left > 0 { spawnDrop(Stack(item: r.out, count: left, extra: ex), pb.x, pb.y - 1, 2, -3) }
		floatText("+" + String(r.outCount) + " " + r.out.name, pb.x, pb.y - 2.2, 0xFFE070)
		bumpHUD()
	}

	// MARK: creative palette

	/// Everything the creative palette offers: the game's items, then those of the world's mods
	func creativeItems() -> [Item] {
		return allGameItems() + ModRuntime.shared.paletteItems()
	}

	func creativeGive(_ it: Item) {
		let n: Int = it.maxStack > 1 ? it.maxStack : 1
		giveItem(it, n, extra: gunLoad(it))
		bumpHUD()
	}

	func gunLoad(_ it: Item) -> Int {
		if case .gun(let g) = it { return g.magazine }
		if case .custom(let k) = it, let r = ModRuntime.shared.item(k), r.def.kind == .gun { return r.def.magazine }
		return 0
	}
}

/// Every item of the game itself (no mod content), in palette order
func allGameItems() -> [Item] {
	var out: [Item] = []
	for t in Tile.allCases {
		if t.isMod { continue }
		switch t {
		case .bedR, .stairWoodL, .stairStoneL, .stairBrickL: continue
		case .air, .water, .lava, .bedrock, .portalFrame, .portalOff, .portalOn, .wheat1, .wheat2, .carrot1, .carrot2, .doorOpen,
			 .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock, .shutterOpen, .lampOn, .gateOpen: continue
		default: out.append(.block(t))
		}
	}
	for tier in Tier.allCases {
		for k in ToolType.allCases { out.append(.tool(k, tier)) }
		out.append(.sword(tier))
		out.append(.spear(tier))
		out.append(.hammer(tier))
		if tier != .wood { out.append(.knife(tier)) }
		for s in ArmorSlot.allCases { out.append(.armor(s, tier)) }
	}
	for g in Gear.allCases { out.append(.gear(g)) }
	out.append(.bow)
	out.append(.sling)
	for c in ClubKind.allCases { out.append(.club(c)) }
	for r in Relic.allCases { out.append(.relic(r)) }
	for gt in GunType.allCases { out.append(.gun(gt)) }
	for a in AmmoType.allCases { out.append(.ammo(a)) }
	for g in Gadget.allCases { out.append(.gadget(g)) }
	for k in wallKinds { out.append(.wall(k)) }
	for p in PartType.allCases { out.append(.part(p)) }
	for f in Food.allCases { out.append(.food(f)) }
	for m in Mat.allCases { out.append(.mat(m)) }
	out.append(contentsOf: featureItems())
	return out
}

// ===== p14d_tools =====

// MARK: - Item use: mining, placing, melee, ranged weapons, eating, farming

func toolClass(_ t: Tile) -> ToolType {
	if t.isMod { return Tile.modToolTable[Int(t.rawValue - Tile.modBase)] }
	switch t {
	case .log, .jungleLog, .palmLog, .logBlock, .jungleLogBlock, .palmLogBlock, .planks, .workbench, .chest, .platform, .leaves, .jungleLeaves, .cactus, .hay, .reed, .lantern, .torch, .ladder, .tinkerBench,
		 .birchLog, .birchLogBlock, .birchLeaves, .pineLeaves, .weatherStation, .rainBarrel, .shutterClosed, .shutterOpen:
		return .axe
	case .chair, .table, .bedL, .bedR, .cabinet, .wardrobe, .shelf, .bookshelf, .sofa, .stairWoodR, .stairWoodL:
		return .axe
	case .dirt, .grass, .sand, .snow, .mud, .dryGrass, .jungleGrass, .mossGrass, .farmland, .sandbag:
		return .shovel
	default:
		return .pickaxe
	}
}

func isLogTile(_ t: Tile) -> Bool {
	return t == .log || t == .jungleLog || t == .palmLog || t == .birchLog
}

func isLeafTile(_ t: Tile) -> Bool {
	return t == .leaves || t == .jungleLeaves || t == .birchLeaves || t == .pineLeaves
}

/// Which way a stair rises: 1 to the right, 2 to the left, 0 for anything that is not a stair
func stairSide(_ t: Tile) -> UInt8 {
	switch t {
	case .stairWoodR, .stairStoneR, .stairBrickR: return 1
	case .stairWoodL, .stairStoneL, .stairBrickL: return 2
	default: return 0
	}
}

/// The stair facing the other way (the same tile for anything else)
func stairMirror(_ t: Tile) -> Tile {
	switch t {
	case .stairWoodR: return .stairWoodL
	case .stairWoodL: return .stairWoodR
	case .stairStoneR: return .stairStoneL
	case .stairStoneL: return .stairStoneR
	case .stairBrickR: return .stairBrickL
	case .stairBrickL: return .stairBrickR
	default: return t
	}
}

/// Furniture that stores things like a chest (its contents live in World.chests)
func isStorageFurniture(_ t: Tile) -> Bool { return t == .cabinet || t == .wardrobe }

/// Furniture the player can sit on
func isSeat(_ t: Tile) -> Bool { return t == .chair || t == .sofa }

struct DecayZone {
	var x: Int
	var y: Int
	var t: Double
}

extension Game {
	/// Any trunk tile within r tiles (keeps a tree's canopy alive)
	func logNear(_ x: Int, _ y: Int, _ r: Int) -> Bool {
		for dy in -r...r {
			for dx in -r...r where isLogTile(world.tile(x + dx, y + dy)) { return true }
		}
		return false
	}

	/// Where a trunk was cut, leaves that no longer have a trunk nearby wither over the next half
	/// minute. Only around cut trees, so leafy ruin decorations are left alone.
	func updateLeafDecay(_ dt: Double) {
		if decayZones.isEmpty { return }
		var keep: [DecayZone] = []
		for z0 in decayZones {
			var z: DecayZone = z0
			z.t -= dt
			for _ in 0..<4 {
				let x: Int = z.x + Int.random(in: -7...7)
				let y: Int = z.y + Int.random(in: -10...4)
				let t: Tile = world.tile(x, y)
				if isLeafTile(t) && !logNear(x, y, 4) { breakTile(x, y, false) }
			}
			if z.t > 0 { keep.append(z) }
		}
		decayZones = keep
	}
}

extension Game {
	func updateUse(_ dt: Double) {
		if useCD > 0 { useCD -= dt }
		if swingT > 0 { swingT -= dt } else { swingDur = 0.25 }
		if muzzleT > 0 { muzzleT -= dt }
		if bowRecoil > 0 { bowRecoil -= dt }
		if eatT > 0 { eatT -= dt }
		if placeCD > 0 { placeCD -= dt }
		if lockT > 0 { lockT -= dt }
		if let t = lockTarget, t.hp <= 0 || t.removed { lockTarget = nil }
		if dead || inVehicle != nil {
			mining = false
			usePressedFlag = false
			useReleasedFlag = false
			strikeT = 0
			return
		}
		// a heavy blow lands at the end of its wind-up, if the same weapon is still in hand
		if strikeT > 0 {
			strikeT -= dt
			if strikeT <= 0 {
				strikeT = 0
				if sel == strikeSel && heldItem == strikeItem { resolveMelee(strikeItem) }
			}
		}
		updateReload(dt)
		let pressed: Bool = usePressedFlag
		usePressedFlag = false
		let released: Bool = useReleasedFlag
		useReleasedFlag = false
		if !aimValid { return }
		let held: Item? = heldItem
		if !useHeld {
			mining = false
			mineP = max(0, mineP - dt * 2.0)
			wireLast = nil
		}
		// bow release logic works on edges
		if case .bow? = held {
			handleBow(dt, pressed, released)
			return
		} else if case .custom(let k)? = held, let r = ModRuntime.shared.item(k), r.def.kind == .bow {
			handleModBow(r, dt, pressed, released)
			return
		} else if bowCharge > 0 {
			bowCharge = 0
		}
		if !useHeld {
			handEmptied = false
			lastUsedItem = nil
			return
		}
		guard let it = held else {
			// a stack used up while the button is held (the last ladder or block placed) does not turn
			// the hold into mining with bare hands: that waits for the next press
			if lastUsedItem != nil { handEmptied = true }
			lastUsedItem = nil
			if !handEmptied { useBareHand(dt, pressed) }
			return
		}
		lastUsedItem = it
		// a custom dimension's gate, then a mod's summoning item (tried before the item's own use)
		if pressed && world.dim.isCustom && tryReturnGate() { return }
		if pressed && !logicRT.isEmpty && tryLogicTap() { return }
		if pressed && !ModRuntime.shared.summons.isEmpty && trySummonWith(it) { return }
		switch it {
		case .block(let t): usePlaceBlock(t, dt)
		case .tool(let k, let tr): useToolItem(k, tr, dt, pressed)
		case .sword, .spear, .hammer, .knife, .club, .relic: useMeleeWeapon(it, pressed)
		case .gun(let g): useGun(g, pressed)
		case .sling: useSling(pressed)
		case .food(let f): useFood(f, pressed)
		case .mat(let m):
			if m == .seeds { usePlant(.wheat1, it, pressed) }
			if m == .vial { useVial(pressed) }
		case .part(let p): usePart(p, pressed)
		case .gadget(let g): useGadget(g, pressed)
		case .wall(let k): usePlaceWall(k)
		case .armor, .gear:
			if pressed { quickEquip(sel); say("Equipped.", 1.0) }
		case .custom(let k): useModItem(k, dt, pressed)
		case .potion(let p): usePotion(p, pressed)
		case .compound:
			if pressed { say("Work it into equipment at an Infusion Crucible.", 1.8) }
		case .exoPart, .exoPlate, .exoCore, .exoModule:
			if pressed { say("Fit it to your suit at an Assembly Station.", 1.8) }
		default: break
		}
	}

	// MARK: bare hands & tools

	func useBareHand(_ dt: Double, _ pressed: Bool) {
		if pressed && world.dim.isCustom && tryReturnGate() { return }
		if pressed && !logicRT.isEmpty && tryLogicTap() { return }
		if let m = mobUnderAim(Item.bareHands) {
			if pressed || (useCD <= 0 && !meleeCandidates(Item.bareHands).isEmpty) { startMelee(nil, target: m) }
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		mineStep(tx, ty, nil, nil, dt)
	}

	func useToolItem(_ k: ToolType, _ tr: Tier, _ dt: Double, _ pressed: Bool) {
		let it: Item = .tool(k, tr)
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		// pointing at a creature means fighting it, not digging the block behind it
		if let m = mobUnderAim(infusedMelee(it)) {
			if pressed || (useCD <= 0 && !meleeCandidates(infusedMelee(it)).isEmpty) { startMelee(it, target: m) }
			return
		}
		if k == .hoe {
			if useCD <= 0 {
				let t: Tile = world.tile(tx, ty)
				if (t == .grass || t == .dirt || t == .dryGrass || t == .mossGrass) && inReach(Double(tx) + 0.5, Double(ty) + 0.5) && !world.tile(tx, ty - 1).solid {
					world.set(tx, ty, .farmland)
					// plants on top of the tilled tile are removed
					if world.tile(tx, ty - 1).isPlant { world.set(tx, ty - 1, .air) }
					useCD = 0.25
					swingT = 0.2
					swingDir = facing
					spawnParticles(Double(tx) + 0.5, Double(ty), 0x6B4626, 6, 2.5, 0.4, 12)
					return
				}
			}
		}
		mineStep(tx, ty, k, tr, dt, speed: OverrideRT.shared.toolSpeed(.tool(k, tr)))
	}

	/// A melee weapon in hand. A fresh press always swings (toward the aim, or the foe under it); held
	/// down it keeps swinging, but only while a foe is actually in reach, so holding on empty ground or
	/// on a foe that is still too far away never wastes swings.
	func useMeleeWeapon(_ it: Item, _ pressed: Bool) {
		let p: MeleeProfile = infusedMelee(it)
		let target: Mob? = mobUnderAim(p)
		if let t = target {
			// the touch landed on (or close to) a foe: the blow goes at it
			aimX = t.b.x
			aimY = t.b.cy
		}
		if !pressed {
			// held: nothing to do while the weapon recovers (this runs every frame). Held on the attack
			// stick it swings again as soon as the weapon is ready; a finger held on the world swings
			// only while something is actually in reach
			if useCD > 0 || strikeT > 0 { return }
			let onStick: Bool = actState.held && !touchActive
			if !onStick && meleeCandidates(p).isEmpty { return }
		}
		startMelee(it, target: target)
	}

	/// Swings the item right now, ignoring its cooldown and wind-up (used by debug tools and tests)
	func swingEmpty(_ it: Item?) {
		useCD = 0
		strikeT = 0
		if startMelee(it) && strikeT > 0 {
			strikeT = 0
			resolveMelee(it)
		}
	}

	/// The foe the player is pointing at: under the aim, or close to it (fingers are not precise),
	/// near enough to be worth swinging at
	func mobUnderAim(_ p: MeleeProfile) -> Mob? {
		if !aimValid { return nil }
		let pad: Double = 0.9
		var best: Mob? = nil
		var bd: Double = 1e9
		for m in mobsNear(aimX - 6, aimX + 6) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			let x0: Double = m.b.left - pad
			let x1: Double = m.b.right + pad
			let y0: Double = m.b.top - pad
			let y1: Double = m.b.y + pad
			if aimX < x0 || aimX > x1 || aimY < y0 || aimY > y1 { continue }
			let reach: Double = boxDistance(m, shoulderX, shoulderY)
			if reach > max(p.reach + 1.5, 4.0) { continue }
			var d: Double = abs(aimX - m.b.x) + abs(aimY - m.b.cy)
			if !isThreat(m) { d += 2.0 }
			if d < bd { bd = d; best = m }
		}
		return best
	}

	// MARK: mining & breaking

	func mineStep(_ tx: Int, _ ty: Int, _ kind: ToolType?, _ tier: Tier?, _ dt: Double, speed toolSpeed: Double? = nil) {
		let t: Tile = world.tile(tx, ty)
		if t == .air && mineWall(tx, ty, kind, tier, dt) { return }
		if t == .air || t.liquid {
			mining = false
			mineP = 0
			if useCD <= 0 && kind != nil && kind != .hoe {
				swingT = 0.2
				swingDir = aimFacing()
				facing = swingDir
				useCD = 0.3
			}
			return
		}
		let def: TileDef = t.def
		if def.hard >= 9999 {
			if useCD <= 0 { say("That can't be broken.", 1.2); useCD = 0.6 }
			return
		}
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
			mining = false
			mineP = 0
			return
		}
		let cls: ToolType = toolClass(t)
		// a suit's drill arm bores anything up to its metal's tier, whatever is in hand
		let drill: Int = suitDrillTier()
		if def.tier > 0 && !isCreative {
			// a tier asks for a strong enough tool of the block's own kind (a pickaxe for the game's ores)
			var pt: Int = (kind == cls) ? (tier?.rawValue ?? 0) : 0
			if drill > pt { pt = drill }
			if pt < def.tier {
				mining = false
				if useCD <= 0 {
					let tn: String = cls.name.lowercased()
					say(kind == cls ? "This needs a stronger " + tn + "." : "You need a " + tn + " for that.", 1.5)
					useCD = 0.8
					swingT = 0.2
					swingDir = aimFacing()
				}
				return
			}
		}
		if mineX != tx || mineY != ty || !mining {
			if mineX != tx || mineY != ty { mineP = 0 }
			mineX = tx
			mineY = ty
		}
		mining = true
		var speed: Double = 1.0
		if let k = kind, let tr = tier { speed = (toolSpeed ?? tr.mineSpeed) * (k == cls ? 1.0 : 0.35) }
		if drill > 0 {
			let ds: Double = (Tier(rawValue: drill)?.mineSpeed ?? 4.0) * 1.25
			if ds > speed && suitRun(.drill, 4.0, dt) { speed = ds }
		}
		if isCreative { speed = 1000 }
		mineNeed = max(0.05, def.hard * 1.5)
		mineP += dt * speed * mineBoost(kind)
		if useCD <= 0 {
			swingT = 0.22
			swingDir = aimFacing()
			facing = swingDir
			useCD = 0.26
			let col: UInt32 = def.colors.first ?? 0x888888
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, col, 3, 3.0, 0.4, 14)
			digSound(t, broke: false)
		}
		if mineP >= mineNeed {
			mineP = 0
			mining = false
			digSound(t, broke: true)
			let fell: Bool = isLogTile(t) && kind == .axe
			if fell {
				fellTree(tx, ty)
			} else {
				breakTile(tx, ty, true)
				if let k = kind, let tr = tier, k == cls { quarryAround(tx, ty, t, k, tr) }
			}
		}
	}

	func tileDropStacks(_ t: Tile, _ x: Int, _ y: Int) -> [Stack] {
		if t.isMod, let st = ModRuntime.shared.blockDrops(t) {
			var mod: [Stack] = st
			// a custom storage block spills what it held
			if ModRuntime.shared.blockDef(t)?.function == .storage, world.chests[world.chestKey(x, y)] != nil {
				mod.append(contentsOf: world.removeChest(x, y))
			}
			return mod
		}
		var out: [Stack] = []
		let r: Double = Double.random(in: 0...1)
		switch t {
		case .tallGrass:
			if r < 0.14 { out.append(Stack(item: .mat(.seeds), count: 1)) }
		case .leaves, .jungleLeaves, .birchLeaves, .pineLeaves:
			if (t == .leaves || t == .jungleLeaves) && r < 0.05 { out.append(Stack(item: .food(.apple), count: 1)) }
			// about one leaf block in twelve gives a sapling (a felled tree's leaves fall by themselves)
			if Double.random(in: 0...1) < 0.085 { out.append(Stack(item: .block(.sapling), count: 1)) }
		case .wheat3:
			out.append(Stack(item: .food(.wheat), count: 1 + Int.random(in: 0...1)))
			out.append(Stack(item: .mat(.seeds), count: 1 + Int.random(in: 0...2)))
		case .wheat1, .wheat2:
			out.append(Stack(item: .mat(.seeds), count: 1))
		case .carrot3:
			out.append(Stack(item: .food(.carrot), count: 1 + Int.random(in: 0...2)))
		case .carrot1, .carrot2:
			out.append(Stack(item: .food(.carrot), count: 1))
		case .cobweb:
			out.append(Stack(item: .mat(.string), count: 1))
		case .saltpeter:
			out.append(Stack(item: .mat(.saltpeter), count: 1 + (r < 0.35 ? 1 : 0)))
		case .amethyst:
			out.append(Stack(item: .mat(.amethyst), count: 1 + (r < 0.5 ? 1 : 0)))
		case .oreCart:
			// an abandoned cart still holds a little of what was being hauled out (fixed by its spot)
			for st in oreCartLoad(x, y) { out.append(st) }
		case .chest:
			for s in world.removeChest(x, y) { out.append(s) }
			out.append(Stack(item: .block(.chest), count: 1))
		case .cabinet, .wardrobe:
			for s in world.removeChest(x, y) { out.append(s) }
			out.append(Stack(item: .block(t), count: 1))
		default:
			if let d = t.def.drop { out.append(Stack(item: d, count: 1)) }
			else if !t.def.noDrop { out.append(Stack(item: .block(t), count: 1)) }
		}
		return out
	}

	func breakTile(_ x: Int, _ y: Int, _ byPlayer: Bool, dropChance: Double = 1.0) {
		let t: Tile = world.tile(x, y)
		if t == .air || t.hardness >= 9999 { return }
		if isDoor(t) {
			// remove the other half quietly so a door only drops once
			if isDoor(world.tile(x, y - 1)) { world.set(x, y - 1, .air) }
			if isDoor(world.tile(x, y + 1)) { world.set(x, y + 1, .air) }
		}
		// a bed is taken down whole (it drops once)
		if t == .bedL && world.tile(x + 1, y) == .bedR { world.set(x + 1, y, .air) }
		if t == .bedR && world.tile(x - 1, y) == .bedL { world.set(x - 1, y, .air) }
		if world.set(x, y, .air) == .air && t != .air { return }
		if byPlayer && t.isMod && !logicRT.isEmpty, let k = modBlockKey(t) { fireLogic(.blockBroken, x: x, y: y, block: true, key: k) }
		if isLogTile(t) && decayZones.count < 24 { decayZones.append(DecayZone(x: x, y: y, t: 30)) }
		let col: UInt32 = t.def.colors.first ?? 0x888888
		spawnParticles(Double(x) + 0.5, Double(y) + 0.5, col, 6, 3.5, 0.5, 16)
		if !(byPlayer && isCreative) {
			for s in minedDrops(t, x, y, byPlayer) {
				if dropChance < 1.0 && Double.random(in: 0...1) > dropChance { continue }
				spawnDrop(s, Double(x) + 0.5, Double(y) + 0.4, Double.random(in: -1.5...1.5), -3.0)
			}
		} else if t == .chest {
			_ = world.removeChest(x, y)
		}
		// dependent tiles
		let above: Tile = world.tile(x, y - 1)
		if world.needsSupport(above) && !world.supports(world.tile(x, y), above) {
			breakTile(x, y - 1, byPlayer)
		}
		if t == .farmland {
			let a2: Tile = world.tile(x, y - 1)
			if a2 == .wheat1 || a2 == .wheat2 || a2 == .wheat3 || a2 == .carrot1 || a2 == .carrot2 || a2 == .carrot3 { breakTile(x, y - 1, byPlayer) }
		}
		// unsupported sand above falls
		if world.tile(x, y - 1) == .sand { checkFalling(x, y - 1) }
		bumpHUD()
	}

	func fellTree(_ x: Int, _ y: Int) {
		// find the base and walk upward
		var by: Int = y
		while isLogTile(world.tile(x, by + 1)) { by += 1 }
		var cy: Int = by
		var top: Int = y
		var count: Int = 0
		while isLogTile(world.tile(x, cy)) && count < 40 {
			top = cy
			cy -= 1
			count += 1
		}
		// remove logs from top to bottom (only from the struck tile upwards)
		var yy: Int = y
		while isLogTile(world.tile(x, yy)) && yy >= top {
			breakTile(x, yy, true)
			yy -= 1
		}
		// leaves around the crown
		let ty: Int = top
		for dy in -7...3 {
			for dx in -6...6 {
				let lx: Int = x + dx
				let ly: Int = ty + dy
				let lt: Tile = world.tile(lx, ly)
				if isLeafTile(lt) {
					// only fell leaves that belong to this tree (near the trunk top)
					if abs(dx) + abs(dy + 1) <= 8 { breakTile(lx, ly, true) }
				}
			}
		}
	}

	// MARK: placing blocks

	func canPlaceAt(_ tx: Int, _ ty: Int, _ t: Tile) -> Bool {
		if ty < 2 || ty >= world.H - 2 { return false }
		let cur: Tile = world.tile(tx, ty)
		if !(cur == .air || cur.liquid || (cur.isPlant && cur != .torch && cur != .lantern) || cur == .cobweb) { return false }
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
		if t.solid {
			// no overlap with bodies
			let x0: Double = Double(tx), x1: Double = Double(tx + 1)
			let y0: Double = Double(ty), y1: Double = Double(ty + 1)
			if pb.right > x0 + 0.02 && pb.left < x1 - 0.02 && pb.y > y0 + 0.02 && pb.top < y1 - 0.02 && !noclip { return false }
			for m in mobs {
				if m.hp <= 0 { continue }
				if m.b.right > x0 + 0.02 && m.b.left < x1 - 0.02 && m.b.y > y0 + 0.02 && m.b.top < y1 - 0.02 { return false }
			}
			for v in vehicles {
				if v.b.x + v.b.w * 0.5 > x0 + 0.02 && v.b.x - v.b.w * 0.5 < x1 - 0.02 && v.b.y > y0 + 0.02 && v.b.y - v.b.h < y1 - 0.02 { return false }
			}
		}
		if world.needsSupport(t) {
			let below: Tile = world.tile(tx, ty + 1)
			if !world.supports(below, t) { return false }
		}
		if isCreative || flying { return true }
		// needs an adjacent tile to attach to, or a wall behind it
		let n: [Tile] = [world.tile(tx - 1, ty), world.tile(tx + 1, ty), world.tile(tx, ty - 1), world.tile(tx, ty + 1)]
		for k in n {
			if k != .air && !k.liquid && !(k.isPlant && k != .torch) { return true }
		}
		return world.wallAt(tx, ty) != 0
	}

	func usePlaceBlock(_ t: Tile, _ dt: Double) {
		if placeCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if t == .doorClosed || t == .doorOpen {
			if placeDoor(tx, ty) {
				if !isCreative { inv.removeAt(sel, 1) }
				placeCD = 0.25
				swingT = 0.14
				bumpHUD()
			}
			return
		}
		// the WALL switch: the block goes up as a passable wall instead
		if wallMode && canBeWall(t.placedForm) {
			placeBlockAsWall(t.placedForm)
			return
		}
		// aiming at a ladder with ladders in hand builds it on; beds, stairs and lift cars place their own way
		if t == .ladder && extendLadder(tx, ty) { return }
		if placeSpecial(t, tx, ty) { return }
		// a log item builds a solid log block (tree trunks themselves have no collision)
		let placed: Tile = t.placedForm
		if !canPlaceAt(tx, ty, placed) { return }
		// plants / crops need special support handled in canPlaceAt through needsSupport
		world.set(tx, ty, placed)
		world.setBuilt(tx, ty, true)
		if t == .chest { world.setChestItems(tx, ty, []) }
		if placed.isMod, ModRuntime.shared.blockDef(placed)?.function == .storage { world.setChestItems(tx, ty, []) }
		// parts that point a way face the way the player does
		if powerDirectional(placed), let d = world.powerDev(tx, ty) { d.dir = facing >= 0 ? 0 : 2 }
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		// the last block of a summoning shape
		if !ModRuntime.shared.summons.isEmpty { summonByBuilding(tx, ty) }
		if placed.isMod && !logicRT.isEmpty, let k = modBlockKey(placed) { fireLogic(.blockPlaced, x: tx, y: ty, block: true, key: k) }
		placeCD = 0.11
		swingT = 0.14
		swingDir = aimFacing()
		facing = swingDir
		bumpHUD()
	}

	func usePlant(_ crop: Tile, _ it: Item, _ pressed: Bool) {
		if placeCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if world.tile(tx, ty) == .air && world.tile(tx, ty + 1) == .farmland && inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
			world.set(tx, ty, crop)
			if !isCreative { inv.removeAt(sel, 1) }
			placeCD = 0.2
			swingT = 0.14
			bumpHUD()
		}
	}

	// MARK: food

	func useFood(_ f: Food, _ pressed: Bool) {
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if f == .carrot && world.tile(tx, ty) == .air && world.tile(tx, ty + 1) == .farmland {
			usePlant(.carrot1, .food(.carrot), pressed)
			return
		}
		if !pressed || eatT > 0.0 { return }
		if hunger >= 19.5 && hp >= maxHP && !isCreative {
			say("You're not hungry.", 1.2)
			return
		}
		let fo: ModOverride? = OverrideRT.shared.items[.food(f)]
		let fh: Double = fo?.hunger ?? f.hunger
		let fl: Double = fo?.heal ?? f.heal
		hunger = min(20, hunger + fh)
		if fl > 0 { heal(fl) }
		if !isCreative { inv.removeAt(sel, 1) }
		eatT = 0.5
		useCD = 0.5
		sfx(.eat, 0.6)
		spawnParticles(pb.x + Double(facing) * 0.4, pb.y - 1.4, 0xC8A060, 5, 2.0, 0.4, 8)
		floatText("+" + String(Int(f.hunger)), pb.x, pb.y - pb.h - 0.4, 0xE0A040)
		bumpHUD()
	}

	// MARK: bow

	/// Bow stats live in one place so new bows only need a new entry here
	struct BowStats {
		var minSpeed: Double = 20
		var maxSpeed: Double = 40
		var baseDamage: Double = 5
		var chargeDamage: Double = 9
		var chargeTime: Double = 0.55
		var useTime: Double = 0.32
		var gravity: Double = 15
	}

	func bowStats(_ it: Item) -> BowStats { return BowStats() }

	/// Hold to draw (aim with your finger, the dotted arc shows the flight path), release to shoot.
	/// A quick tap still fires a useful shot, and holding at full draw keeps firing automatically.
	func handleBow(_ dt: Double, _ pressed: Bool, _ released: Bool) {
		let hasArrow: Bool = isCreative || inv.total(.ammo(.arrow)) > 0
		let st: BowStats = bowStats(.bow)
		if useHeld {
			if !hasArrow {
				if pressed { say("No arrows!", 1.2) }
				bowCharge = 0
				return
			}
			if useCD > 0 && bowCharge == 0 { return }
			bowCharge = min(1.0, max(bowCharge, 0.01) + dt / st.chargeTime)
			facing = aimFacing()
			if bowCharge >= 1.0 && useCD <= 0 {
				fireArrow(1.0)
				bowCharge = 0.3
			}
		} else if released && bowCharge > 0 && hasArrow {
			fireArrow(max(0.45, bowCharge))
			bowCharge = 0
		} else {
			bowCharge = 0
		}
	}

	/// Where the arrow leaves the bow and its starting velocity for a given draw
	func arrowLaunch(_ charge: Double) -> (Double, Double, Double, Double) {
		let st: BowStats = bowStats(.bow)
		let ox: Double = pb.x + Double(facing) * 0.35
		let oy: Double = pb.y - 1.2
		var dx: Double = aimX - ox
		var dy: Double = aimY - oy
		let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
		dx /= len
		dy /= len
		let speed: Double = st.minSpeed + (st.maxSpeed - st.minSpeed) * charge
		// a little of the archer's own motion carries into the arrow, so shots on the run still land
		return (ox + dx * 0.4, oy + dy * 0.4, dx * speed + pb.vx * 0.3, dy * speed + min(0, pb.vy) * 0.2)
	}

	func fireArrow(_ charge: Double) {
		if !isCreative { _ = inv.remove(.ammo(.arrow), 1) }
		let st: BowStats = bowStats(.bow)
		let l: (Double, Double, Double, Double) = arrowLaunch(charge)
		var dmg: Double = st.baseDamage + st.chargeDamage * charge
		// a mod may change the bow's full-draw damage
		if let o = OverrideRT.shared.items[.bow], let v = o.damage { dmg *= v / max(0.1, st.baseDamage + st.chargeDamage) }
		if charge >= 0.99 && Double.random(in: 0...1) < 0.15 { dmg *= 1.5 }
		var p = Projectile(kind: .arrow, x: l.0, y: l.1, vx: l.2, vy: l.3, dmg: dmg, fromPlayer: true, gravity: st.gravity)
		p.life = 6.0
		p.w = 0.22
		p.source = .player
		p.uid = newID()
		infuseShot(&p, heldItem)
		projectiles.append(p)
		sfx(.bow, 0.7)
		useCD = st.useTime * quickMul()
		swingT = 0.18
		swingDir = facing
		bowRecoil = 0.12
		bumpHUD()
	}

	/// Sample points of the shot's flight for the aiming arc: the bow while it is drawn, the sling and
	/// bolt throwers while the aim is held
	func arrowPreview() -> [(Double, Double)] {
		var l: (Double, Double, Double, Double)
		var grav: Double
		if bowCharge > 0 {
			let st: BowStats = bowStats(.bow)
			l = arrowLaunch(max(0.45, bowCharge))
			grav = st.gravity
		} else if useHeld && aimValid && inVehicle == nil, let it = heldItem {
			var speed: Double = 0
			var ox: Double = pb.x + Double(facing) * 0.4
			var oy: Double = pb.y - 1.3
			switch it {
			case .sling: speed = 23; grav = 16
			case .gun(let g) where g.isBoltThrower:
				speed = g.speed; grav = g.gravity
				ox = pb.x + Double(facing) * 0.7
				oy = pb.y - 1.2
			case .gadget(let gd) where gd == .bomb || gd == .fireFlask: speed = throwSpeed; grav = throwGravity
			case .potion(let pt) where pt.thrown: speed = throwSpeed; grav = throwGravity
			default: return []
			}
			let a: Double = lobAngle(aimX - ox, aimY - oy, speed, grav)
			l = (ox, oy, cos(a) * speed, sin(a) * speed)
		} else {
			return []
		}
		var x: Double = l.0
		var y: Double = l.1
		let vx: Double = l.2
		var vy: Double = l.3
		var out: [(Double, Double)] = []
		let step: Double = 0.03
		var i: Int = 0
		while i < 40 {
			vy = min(vy + grav * step, 40)
			let nx: Double = x + vx * step
			let ny: Double = y + vy * step
			if world.segmentSolidT(x, y, nx, ny) != nil { break }
			x = nx
			y = ny
			if i % 2 == 1 { out.append((x, y)) }
			i += 1
		}
		return out
	}

	// MARK: guns

	func updateReload(_ dt: Double) {
		if reloadT <= 0 { return }
		if reloadSlot != sel {
			reloadT = 0
			reloadSlot = -1
			return
		}
		reloadT -= dt
		if reloadT <= 0 {
			reloadT = 0
			if var st = inv.slots[sel], case .gun(let g) = st.item, let a = g.ammo {
				let need: Int = g.magazine - st.extra
				var take: Int = need
				if !isCreative {
					take = min(need, inv.total(.ammo(a)))
					_ = inv.remove(.ammo(a), take)
				}
				st.extra += take
				inv.slots[sel] = st
				if g.isBoltThrower { sfx(.tap, 0.5) }
				bumpHUD()
			} else if let st = inv.slots[sel], case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .gun {
				finishModReload(r)
			}
			reloadSlot = -1
		}
	}

	func startReload() {
		if let st = heldStack, case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .gun {
			startModReload(r, st)
			return
		}
		guard let st = heldStack, case .gun(let g) = st.item, let a = g.ammo else { return }
		if reloadT > 0 || st.extra >= g.magazine { return }
		if !isCreative && inv.total(.ammo(a)) <= 0 {
			say("Out of " + a.name.lowercased() + "s!", 1.5)
			return
		}
		reloadT = g.reloadTime
		reloadSlot = sel
		// a crossbow is cocked after every bolt: no need to announce that each time
		if g.magazine > 1 { say("Reloading...", 1.0) }
	}

	/// Fires a loaded weapon: bullets, bolts, a spread of pellets, or the storm rod's lightning. Heavy
	/// weapons need a fresh press per shot; the rest keep firing while held. Empty ones reload by
	/// themselves when there is ammunition.
	func useGun(_ g: GunType, _ pressed: Bool) {
		guard var st = inv.slots[sel] else { return }
		if reloadT > 0 { return }
		if st.extra <= 0 {
			if g == .stormRod {
				if pressed { say("The rod is still gathering its charge.", 1.2) }
				return
			}
			if pressed || useCD <= 0 { startReload() }
			return
		}
		if useCD > 0 { return }
		if g.needsPress && !pressed { return }
		if !isCreative || g != .stormRod { st.extra -= 1 }
		inv.slots[sel] = st
		useCD = (OverrideRT.shared.items[.gun(g)]?.cooldown ?? g.cooldown) * quickMul()
		if g == .stormRod {
			fireStormRod()
			bumpHUD()
			return
		}
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.7
		let oy: Double = pb.y - 1.2
		// bolts drop a little: they are raised just enough to fly through the spot aimed at
		let base: Double = lobAngle(aimX - ox, aimY - oy, g.speed, g.gravity)
		let n: Int = g == .blunderbuss ? 7 : 1
		for i in 0..<n {
			var a: Double = base
			// an even fan of pellets, so the spread always covers the same cone
			if n > 1 { a += (Double(i) / Double(n - 1) - 0.5) * 0.6 }
			let dx: Double = cos(a)
			let dy: Double = sin(a)
			let kind: ProjKind = g == .blunderbuss ? .pellet : (g.isBoltThrower ? .quarrel : .bullet)
			var p = Projectile(kind: kind, x: ox, y: oy, vx: dx * g.speed, vy: dy * g.speed, dmg: OverrideRT.shared.items[.gun(g)]?.damage ?? g.damage, fromPlayer: true, gravity: g.gravity)
			p.life = g.shotLife * (n > 1 ? Double.random(in: 0.85...1.1) : 1.0)
			p.source = .player
			p.uid = newID()
			p.pierce = g.pierce
			p.knock = g.knock
			if kind == .pellet { p.w = 0.16 }
			if kind == .quarrel { p.w = 0.22 }
			infuseShot(&p, heldItem)
			projectiles.append(p)
		}
		let heavyShot: Bool = g == .rifle || g == .arbalest || g == .blunderbuss
		switch g {
		case .blunderbuss: sfx(.blunderbuss, 0.9)
		case .crossbow, .arbalest, .repeater: sfx(.crossbow, 0.75)
		default: sfx(.gun, 0.8)
		}
		muzzleT = g.isBoltThrower ? 0 : 0.08
		swingT = 0.1
		swingDir = facing
		addShake(heavyShot ? 0.16 : 0.07)
		pb.vx -= Double(facing) * (g == .blunderbuss ? 4.0 : (heavyShot ? 2.5 : 1.0))
		let dx0: Double = cos(base)
		let dy0: Double = sin(base)
		if g.isFirearm { spawnParticles(ox + dx0 * 0.4, oy + dy0 * 0.4, 0xFFE080, g == .blunderbuss ? 9 : 4, 3.0, 0.15, 0) }
		if st.extra <= 0, let am = g.ammo, isCreative || inv.total(.ammo(am)) > 0 { startReload() }
		bumpHUD()
	}

	// MARK: gadgets & vehicle parts

	func useGadget(_ g: Gadget, _ pressed: Bool) {
		switch g {
		case .treasureMap:
			if pressed {
				showMap = true
				bumpHUD()
			}
		case .shears:
			if let m = mobAtPoint(aimX, aimY, 0.3), m.kind == .sheep, !m.sheared, inReach(m.b.x, m.b.cy), useCD <= 0 {
				m.sheared = true
				m.regrow = 150
				useCD = 0.4
				swingT = 0.2
				for _ in 0..<(1 + Int.random(in: 0...2)) {
					spawnDrop(Stack(item: .mat(.wool), count: 1), m.b.x, m.b.y - 0.8, Double.random(in: -2...2), -4)
				}
				spawnParticles(m.b.x, m.b.cy, 0xF0F0F0, 8, 3.0, 0.5, 8)
			}
		case .wrench:
			if pressed, useCD <= 0, let (v, c) = vehicleAtPoint(aimX, aimY), inReach(aimX, aimY) {
				removeVehiclePart(v, c)
				useCD = 0.3
			}
		case .portalKey:
			if pressed { say("Use the key on the sealed portal.", 2.0) }
		case .carKit, .boatKit, .motorboatKit:
			if pressed && useCD <= 0 { placeKit(g) }
		case .bomb:
			if pressed { throwBomb() }
		case .fireFlask:
			if pressed { throwFlask() }
		case .barometer:
			if pressed { say(barometerReading(), 2.5) }
		case .waterFlask:
			useWaterFlask(pressed)
		case .powerCable, .pulseWire, .pulseWireB, .wireSnips:
			useWiring(g, pressed)
		case .probe:
			if pressed { probeAt(aimX, aimY) }
		}
	}

	/// A cargo crate's storage lives with the other chests, under a key no block can have (built from
	/// the vehicle's saved id and the crate's cell), so it is saved and loaded like any chest
	func cargoSpot(_ v: Vehicle, _ c: PartCell) -> IntPair {
		return IntPair(x: -1_000_000_000 + v.id * 4096 + (c.dx + 32) * 64 + (c.dy + 32), y: -77)
	}

	func isCargoSpot(_ p: IntPair) -> Bool { return p.y == -77 && p.x < -900_000_000 }

	func removeVehiclePart(_ v: Vehicle, _ c: PartCell) {
		if v.rider { dismount() }
		let crates: [PartCell] = v.parts.filter { $0.value == .cargo }.map { $0.key }
		let spills: [(PartCell, (Double, Double))] = crates.map { ($0, v.cellCenter($0)) }
		let returned: [PartType] = v.removePart(c)
		// a crate that comes off tips its contents onto the ground
		for (cell, at) in spills where v.parts[cell] == nil {
			let k: IntPair = cargoSpot(v, cell)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { spawnDrop(st, at.0, at.1, Double.random(in: -2...2), -3.5) }
		}
		for t in returned { giveItem(.part(t), 1) }
		if v.parts.isEmpty {
			vehicles.removeAll { $0.id == v.id }
		} else {
			v.recompute(keepAnchor: true)
		}
		bumpHUD()
	}

	func usePart(_ p: PartType, _ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		if !inReach(aimX, aimY) {
			say("Too far away. Tap closer to you.", 1.2)
			return
		}
		// attach to an existing vehicle (the tapped cell must touch it)
		for v in vehicles {
			if aimX < v.b.left - 1.5 || aimX > v.b.right + 1.5 || aimY < v.b.top - 1.5 || aimY > v.b.y + 1.5 { continue }
			let c: PartCell = v.cellAt(aimX, aimY)
			if v.parts[c] != nil || !v.hasNeighbor(c) { continue }
			if let problem = attachProblem(v, c, p) {
				say(problem + " Green squares show where it fits.", 2.5)
				useCD = 0.3
				return
			}
			let wasReady: Bool = vehicleCheck(v).ready
			liftIfBuried(v, c)
			v.parts[c] = p
			v.recompute(keepAnchor: true)
			if !isCreative { inv.removeAt(sel, 1) }
			useCD = 0.2
			swingT = 0.15
			let check: VehicleCheck = vehicleCheck(v)
			if check.ready && !wasReady {
				let kind: String = check.title.lowercased()
				say("Your \(kind) is ready! Stand next to it and press DRIVE.", 3.5)
			}
			bumpHUD()
			return
		}
		// start a new vehicle on the ground
		let first: [PartType] = [.frame, .hull, .seat, .fuelTank, .engine]
		if !first.contains(p) {
			if nearestVehicle(10) != nil {
				let pn: String = p.name
				say("Tap one of the green squares to attach the \(pn).", 2.5)
			} else {
				say("Start with a Frame (car) or Hull Float (boat). Or craft a ready-made kit in Vehicles.", 3.0)
			}
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if world.solid(tx, ty) { return }
		let v = Vehicle(id: newID(), first: p, x: Double(tx) + 0.5, y: Double(ty) + 1.0)
		vehicles.append(v)
		if !isCreative { inv.removeAt(sel, 1) }
		useCD = 0.25
		say("Vehicle started. Now hold more parts: green squares show where they fit.", 3.0)
		bumpHUD()
	}
}

// MARK: - Combat: melee strikes, aim, weapon switching, ranged and special weapons, feedback

/// A melee swing, drawn for a moment after it is made: the trail covers exactly the space it swept
struct SlashFX {
	var x: Double
	var y: Double
	var ang: Double
	var reach: Double
	var halfArc: Double
	var style: SwingStyle
	var color: UInt32
	var life: Double
	var maxLife: Double
	var hit: Bool
}

/// A lightning arc from the storm rod: a jagged line through these points
struct ArcFX {
	var pts: [(Double, Double)]
	var life: Double
}

/// Ground set alight by a fire flask; it burns whatever stands in it
struct FireZone {
	var x: Double
	/// the ground the flames stand on
	var y: Double
	var r: Double
	var t: Double
	var tick: Double = 0
	var uid: Int
	/// started by lightning, not by a thrown flask (it then answers to the weather damage settings)
	var env: Bool = false
}

func isUndead(_ k: MobKind) -> Bool {
	switch k {
	case .zombie, .skeleton, .archer, .wraith: return true
	default: return false
	}
}

/// signed difference between two angles, in -pi...pi
func angleDiff(_ a: Double, _ b: Double) -> Double {
	var d: Double = a - b
	while d > Double.pi { d -= 2.0 * Double.pi }
	while d < -Double.pi { d += 2.0 * Double.pi }
	return d
}

/// Rock blocks a sling can throw
let slingAmmo: [Tile] = [.stone, .slate, .deepRock, .sandstone, .ashStone]

/// The direction (radians, y pointing down) to launch a shot of speed `v` falling under gravity `g`
/// so that it passes through the point (dx, dy) from where it starts, on the lower, flatter of the two
/// arcs. Out of reach: the longest-reaching throw toward it (45 degrees up).
func lobAngle(_ dx: Double, _ dy: Double, _ v: Double, _ g: Double) -> Double {
	if g <= 0.001 { return atan2(dy, dx) }
	let x: Double = max(0.001, abs(dx))
	let up: Double = -dy
	let v2: Double = v * v
	let disc: Double = v2 * v2 - g * (g * x * x + 2.0 * up * v2)
	let th: Double = disc < 0 ? Double.pi * 0.25 : atan((v2 - sqrt(disc)) / (g * x))
	return dx >= 0 ? -th : Double.pi + th
}

/// Thrown and lobbed weapons are aimed at the spot itself: the game works out the arc
let throwSpeed: Double = 15.0
let throwGravity: Double = 22.0

extension Game {
	// MARK: geometry

	/// The way the player turns to face the aim: toward it, but aiming straight up or down (within a third
	/// of a block of the player's own column) keeps the way they already face
	func aimFacing() -> Int {
		let d: Double = aimX - pb.x
		if abs(d) < 0.3 { return facing }
		return d >= 0 ? 1 : -1
	}

	/// where melee blows start from
	var shoulderX: Double { return pb.x }
	var shoulderY: Double { return pb.y - pb.h * 0.55 }

	/// The way an attack goes: toward the aim, or straight ahead when there is no aim (or the aim is on
	/// the player's own body, where its direction would be noise)
	func attackAngle() -> Double {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		if aimValid {
			let dx: Double = aimX - ox
			let dy: Double = aimY - oy
			if dx * dx + dy * dy > 0.36 { return atan2(dy, dx) }
		}
		return facing >= 0 ? 0 : Double.pi
	}

	/// distance from a point to the nearest edge of a creature's box (0 inside it)
	func boxDistance(_ m: Mob, _ ox: Double, _ oy: Double) -> Double {
		let nx: Double = clampD(ox, m.b.left, m.b.right)
		let ny: Double = clampD(oy, m.b.top, m.b.y)
		let dx: Double = nx - ox
		let dy: Double = ny - oy
		return sqrt(dx * dx + dy * dy)
	}

	/// Whether a swing with profile `p` aimed along (dirx, diry) from the shoulder reaches `m`; returns
	/// how far away it is. The same test serves every way of attacking, so reach never depends on how
	/// the attack was started.
	func meleeReach(_ m: Mob, _ dirx: Double, _ diry: Double, _ p: MeleeProfile) -> Double? {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let hw: Double = m.b.w * 0.5
		let hh: Double = m.b.h * 0.5
		let cx: Double = m.b.x
		let cy: Double = m.b.y - hh
		let nx: Double = clampD(ox, cx - hw, cx + hw)
		let ny: Double = clampD(oy, cy - hh, cy + hh)
		let ddx: Double = nx - ox
		let ddy: Double = ny - oy
		let dist: Double = sqrt(ddx * ddx + ddy * ddy)
		if dist > p.reach { return nil }
		let vx: Double = cx - ox
		let vy: Double = cy - oy
		if p.style == .thrust {
			// a straight band along the aim
			let along: Double = vx * dirx + vy * diry
			let ext: Double = hw * abs(dirx) + hh * abs(diry)
			if along + ext < 0 || along - ext > p.reach { return nil }
			let perp: Double = abs(vx * diry - vy * dirx)
			let pext: Double = hw * abs(diry) + hh * abs(dirx)
			if perp - pext > p.band { return nil }
		} else if dist > 0.45 {
			// inside the arc: the angle to the box centre, widened by how wide the box looks from here
			let cd: Double = max(0.2, sqrt(vx * vx + vy * vy))
			let off: Double = abs(angleDiff(atan2(vy, vx), atan2(diry, dirx)))
			let ext: Double = hw * abs(vy / cd) + hh * abs(vx / cd)
			if off > p.halfArc + atan(ext / cd) { return nil }
		} else if vx * dirx < -0.3 && abs(dirx) > 0.3 {
			// pressed right up against the player: anything on the side being swung at
			return nil
		}
		// blades do not pass through walls
		let ix: Double = nx + (cx - nx) * 0.25
		let iy: Double = ny + (cy - ny) * 0.25
		if !world.lineClear(ox, oy, ix, iy) && !world.lineClear(ox, oy, cx, cy) { return nil }
		return dist
	}

	/// every creature the current aim would catch, nearest first, at most the weapon's limit
	func meleeCandidates(_ p: MeleeProfile) -> [(Mob, Double)] {
		let ang: Double = attackAngle()
		let dirx: Double = cos(ang)
		let diry: Double = sin(ang)
		let ox: Double = shoulderX
		var out: [(Mob, Double)] = []
		for m in mobsNear(ox - p.reach - 4, ox + p.reach + 4) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			if let d = meleeReach(m, dirx, diry, p) { out.append((m, d)) }
		}
		if out.count > 1 { out.sort { $0.1 < $1.1 } }
		if out.count > p.maxHits { out.removeLast(out.count - p.maxHits) }
		return out
	}

	// MARK: melee

	/// Starts a melee attack with the held item (nil: bare hands). A heavy weapon winds up first and
	/// its blow lands a moment later; everything else strikes at once. False while still recovering.
	@discardableResult
	func startMelee(_ it: Item?, target: Mob? = nil) -> Bool {
		if useCD > 0 || strikeT > 0 { return false }
		let p: MeleeProfile = infusedMelee(it)
		useCD = p.cooldown
		swingDur = p.swingTime
		swingT = p.swingTime
		let ang: Double = attackAngle()
		// a blow straight up or down keeps the way the player already faces
		swingDir = abs(cos(ang)) < 0.25 ? facing : (cos(ang) >= 0 ? 1 : -1)
		facing = swingDir
		strikeItem = it
		strikeSel = sel
		strikeTarget = target
		if p.windup > 0 {
			strikeT = p.windup
		} else {
			resolveMelee(it)
		}
		return true
	}

	/// The blow itself: everything inside the swing's shape is hit, with the weapon's knockback,
	/// crits, combo, backstab, daze and fire; then the trail, sound and hit feedback
	func resolveMelee(_ it: Item?) {
		let p: MeleeProfile = infusedMelee(it)
		let infs: [Int] = heldInfusions(it)
		if suitHas(.servo) { _ = suitSpend(.servo, 1.0) }
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let ang: Double = attackAngle()
		let swingKey: Int = newID()
		let targets: [(Mob, Double)] = meleeCandidates(p)
		var hits: Int = 0
		var crits: Int = 0
		var undead: Bool = false
		for (m, _) in targets {
			var d: Double = p.damage
			var crit: Bool = false
			if p.combo {
				comboN = clock - comboT < 0.7 ? comboN + 1 : 1
				comboT = clock
				if comboN % 3 == 0 { d *= 2.0; crit = true }
			}
			if !crit && Double.random(in: 0...1) < p.critChance { d *= 1.5; crit = true }
			if p.backstab > 1 && (pb.x - m.b.x) * Double(m.dir) < 0 && !m.isBoss {
				d *= p.backstab
				crit = true
			}
			if p.undeadMult != 1 && isUndead(m.kind) { d *= p.undeadMult; undead = true }
			let dx: Double = m.b.x - ox
			var info = DamageInfo(amount: d, type: .melee, source: .player)
			info.dirX = abs(dx) > 0.2 ? (dx > 0 ? 1.0 : -1.0) : Double(swingDir)
			info.knock = p.knock
			info.originX = ox
			info.originY = oy
			info.key = swingKey
			info.cooldown = 0.3
			info.heavy = p.heavy
			info.crit = crit
			if applyMobDamage(m, info) {
				hits += 1
				if crit { crits += 1 }
				if p.burn > 0 && !heatImmune(m) { m.burn = max(m.burn, p.burn) }
				if p.daze > 0 { dazeMob(m, p.daze) }
				meleeInfusionHit(m, infs, d)
				suitMeleeHit(m)
				spawnSparks(m.b.x - info.dirX * m.b.w * 0.3, m.b.cy, info.dirX, p.trail, crit ? 7 : 4)
				lockTarget = m
				lockT = 2.0
			}
		}
		// pirate ships
		for sh in ships {
			let dx: Double = abs(sh.x - ox)
			let dy: Double = abs(sh.deckY(Double(WorldGen.sea)) - pb.y)
			if dx < 5.0 + p.reach * 0.3 && dy < 3.5 {
				sh.hp -= p.damage * 0.6
				sh.hitT = 0.2
				hits += 1
			}
		}
		if p.shockwave {
			// the maul's blow runs along the ground as a quake
			var q = Projectile(kind: .shock, x: pb.x + Double(swingDir) * 1.2, y: pb.y - 0.5, vx: Double(swingDir) * 15.0, vy: 0, dmg: 12, fromPlayer: true, gravity: 0)
			q.life = 0.55
			q.source = .player
			q.uid = newID()
			projectiles.append(q)
			addShake(0.3)
			spawnParticles(pb.x + Double(swingDir) * 1.4, pb.y - 0.1, 0xA08860, 10, 4.0, 0.5, 12)
		}
		lastStrikeHits = hits
		if slashes.count > 8 { slashes.removeFirst() }
		let life: Double = max(0.12, p.swingTime * 0.7)
		slashes.append(SlashFX(x: ox, y: oy, ang: ang, reach: p.reach, halfArc: p.halfArc, style: p.style, color: p.trail, life: life, maxLife: life, hit: hits > 0))
		switch p.style {
		case .stab: sfx(.swingLight, 0.5)
		case .thrust: sfx(.thrust, 0.55)
		case .smash, .bash: sfx(p.heavy || p.daze > 0 ? .swingHeavy : .swing, 0.6)
		case .slash: sfx(.swing, 0.5)
		}
		if hits > 0 {
			hitStopT = max(hitStopT, p.heavy ? 0.07 : (crits > 0 ? 0.05 : 0.03))
			addShake(p.heavy ? 0.18 : (crits > 0 ? 0.12 : 0.07))
			sfx(crits > 0 ? .crit : .hit, p.heavy ? 1.0 : 0.75)
			if hits >= 2 {
				floatText("x" + String(hits), pb.x, pb.y - pb.h - 0.9, 0xFFD060)
				sfx(.multiHit, 0.6)
			}
			if undead && p.undeadMult > 1 { spawnParticles(pb.x + Double(swingDir) * 1.2, pb.y - 1.2, 0xC8E8FF, 5, 2.5, 0.4, -2) }
		} else if let t = strikeTarget ?? (lockT > 0 ? lockTarget : nil), t.hp > 0, !t.removed {
			// aimed at something and missed: say so, where it is
			floatText("miss", t.b.x, t.b.top - 0.3, 0xA8A8A8)
		}
		strikeTarget = nil
	}

	/// Leaves a creature reeling: it cannot move or attack for a moment, then cannot be dazed again
	/// right away (no stun-locking). Bosses shrug it off; the golem only half feels it.
	func dazeMob(_ m: Mob, _ t: Double) {
		if m.isBoss || m.dazeGuard > 0 || m.hp <= 0 { return }
		let k: Double = m.kind == .golem ? 0.5 : 1.0
		m.daze = max(m.daze, t * k)
		m.atkT = 0
		m.blocking = false
		sfx(.daze, at: m.b.x, 0.5)
	}

	/// sparks thrown back along the line of a blow
	func spawnSparks(_ x: Double, _ y: Double, _ dirX: Double, _ color: UInt32, _ n: Int) {
		if particles.count > 160 { return }
		for _ in 0..<n {
			let a: Double = Double.random(in: -0.9...0.9) + (dirX >= 0 ? 0 : Double.pi)
			let sp: Double = Double.random(in: 4.0...8.0)
			let c: UInt32 = Double.random(in: 0...1) < 0.5 ? color : 0xFFF4D0
			particles.append(Particle(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp - 2.0, life: Double.random(in: 0.12...0.25), maxLife: 0.25, color: c, size: Double.random(in: 0.07...0.13), gravity: 20))
		}
	}

	// MARK: aim assist for the action button

	/// The creature the action button should go for: hostile ones first (and the one already locked
	/// on), in sight for ranged weapons, within reach for melee (a little beyond it, so the player
	/// turns to face what is coming). Animals only when nothing hostile is near and a weapon is out.
	func autoTarget(_ it: Item?) -> Mob? {
		let ranged: Bool = it?.isRanged ?? false
		let weapon: Bool = it?.isWeapon ?? false
		let p: MeleeProfile = infusedMelee(it)
		let range: Double = ranged ? 22.0 : p.reach + 3.0
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		var best: Mob? = nil
		var bs: Double = 1e9
		for m in mobsNear(ox - range - 4, ox + range + 4) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			let foe: Bool = isThreat(m)
			if !foe && !weapon { continue }
			let d: Double = boxDistance(m, ox, oy)
			if d > range { continue }
			var score: Double = d
			if !foe { score += 8.0 }
			if !world.lineClear(ox, oy, m.b.x, m.b.cy) {
				if ranged { continue }
				score += 6.0
			}
			if m === lockTarget { score -= 1.5 }
			if score < bs { bs = score; best = m }
		}
		return best
	}

	/// launch speed and gravity of what the held item fires (0 speed: not a projectile weapon)
	func shotBallistics(_ it: Item?) -> (Double, Double) {
		guard let i = it else { return (0, 0) }
		switch i {
		case .bow: let st: BowStats = bowStats(.bow); return (st.maxSpeed, st.gravity)
		case .gun(let g): return (g.speed, g.gravity)
		case .sling: return (23.0, 16.0)
		case .gadget(let g): return (g == .bomb || g == .fireFlask) ? (throwSpeed, throwGravity) : (0, 0)
		case .potion(let p): return p.thrown ? (throwSpeed, throwGravity) : (0, 0)
		default: return (0, 0)
		}
	}

	/// Where to aim to hit `m`: its centre, led by its speed and raised to allow for the drop
	func aimPointFor(_ m: Mob, _ it: Item?) -> (Double, Double) {
		var tx: Double = m.b.x
		var ty: Double = m.b.cy
		let (spd, grav) = shotBallistics(it)
		if spd > 0 {
			let dx: Double = tx - pb.x
			let dy: Double = ty - (pb.y - 1.2)
			let t: Double = sqrt(dx * dx + dy * dy) / spd
			tx += m.b.vx * t
			// the bow is drawn and loosed along the aim, so it is aimed above the target; everything
			// else works its own arc out to the point it is aimed at
			if case .bow? = it { ty -= 0.5 * grav * t * t }
		}
		return (tx, ty)
	}

	// MARK: weapon switching

	/// The hotbar slot "next weapon" would pick: the weapon used last when something else is in hand,
	/// otherwise the next weapon along the hotbar
	func nextWeaponSlot() -> Int? {
		let n: Int = Inventory.hotbarCount
		let holdingWeapon: Bool = heldItem?.isWeapon ?? false
		if !holdingWeapon && lastWeaponSel >= 0 && lastWeaponSel < n && lastWeaponSel != sel {
			if let s = inv.slots[lastWeaponSel], s.item.isWeapon { return lastWeaponSel }
		}
		var k: Int = 1
		while k < n {
			let i: Int = (sel + k) % n
			if let s = inv.slots[i], s.item.isWeapon { return i }
			k += 1
		}
		return nil
	}

	/// One tap to the next weapon (or back to the weapon from a tool); the HUD button and the Q key
	func cycleWeapon() {
		guard let i = nextWeaponSlot() else {
			say("No other weapon in your hotbar.", 1.2)
			return
		}
		setSel(i)
		sfx(.swap, 0.6)
		floatText(inv.slots[i]?.item.name ?? "", pb.x, pb.y - pb.h - 0.6, 0xE8E8E8)
	}

	/// What the action button does with the item in hand
	var useLabel: String {
		guard let it = heldItem else { return "PUNCH" }
		if it.isWeapon { return "ATTACK" }
		switch it {
		case .tool: return "MINE"
		case .block, .wall: return "BUILD"
		case .food: return "EAT"
		default: return "USE"
		}
	}

	// MARK: input safety

	/// Drops every held control. Panels, the pause menu and death take the on-screen controls away
	/// mid-press, and a button that disappears never hears its finger lift, so without this an attack,
	/// a walk or a jump could carry on by itself once the panel closes.
	func releaseAllInput() {
		actState.stickReleased()
		actState.was = false
		stick = 0
		stickY = 0
		jumpHeld = false
		downHeld = false
		keyL = false
		keyR = false
		useHeld = false
		useWasHeld = false
		usePressedFlag = false
		useReleasedFlag = false
		touchActive = false
		pendingInteract = false
		bowCharge = 0
		mining = false
	}

	/// Once a frame: releases the controls when something covers them
	func updateInputGate() {
		let blocked: Bool = paused || showInventory || showMap || showJournal || showWeather || showPower || showCapture || showModTest || showInfuse || showExo || dead
		if blocked && !inputBlocked { releaseAllInput() }
		inputBlocked = blocked
	}

	// MARK: sling

	func useSling(_ pressed: Bool) {
		if useCD > 0 { return }
		var ammo: Tile? = nil
		if !isCreative {
			for t in slingAmmo where inv.total(.block(t)) > 0 { ammo = t; break }
			if ammo == nil {
				if pressed { say("The sling needs stones: any stone or slate in your bag.", 1.8) }
				return
			}
		}
		if let t = ammo { _ = inv.remove(.block(t), 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		// the stone is lobbed so that it comes down on the spot aimed at
		let a: Double = lobAngle(aimX - ox, aimY - oy, 23.0, 16.0)
		var p = Projectile(kind: .pebble, x: ox, y: oy, vx: cos(a) * 23.0, vy: sin(a) * 23.0, dmg: 4.5, fromPlayer: true, gravity: 16)
		p.life = 3.0
		p.w = 0.22
		p.knock = 7.5
		p.source = .player
		p.uid = newID()
		infuseShot(&p, heldItem)
		projectiles.append(p)
		useCD = 0.55 * quickMul()
		swingDur = 0.2
		swingT = 0.2
		swingDir = facing
		sfx(.sling, 0.6)
		bumpHUD()
	}

	// MARK: fire flask

	func throwFlask() {
		if useCD > 0 { return }
		if !isCreative { inv.removeAt(sel, 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		let a: Double = lobAngle(aimX - ox, aimY - oy, throwSpeed, throwGravity)
		var p = Projectile(kind: .flask, x: ox, y: oy, vx: cos(a) * throwSpeed, vy: sin(a) * throwSpeed, dmg: 2, fromPlayer: true, gravity: throwGravity)
		p.life = 2.5
		p.w = 0.3
		p.source = .player
		p.uid = newID()
		projectiles.append(p)
		useCD = 0.45
		swingT = 0.18
		swingDir = facing
		bumpHUD()
	}

	/// A flask breaks: a patch of fire on the ground below, and everything in it starts burning
	func burstFlask(_ x: Double, _ y: Double, _ src: DamageSource) {
		let gx: Int = Int(floor(x))
		var gy: Double = y
		let ground: Int = world.groundBelow(gx, Int(floor(y)))
		if Double(ground) - y < 4.0 { gy = Double(ground) }
		if fireZones.count >= 6 { fireZones.removeFirst() }
		var z = FireZone(x: x, y: gy, r: 2.2, t: 3.5, uid: newID())
		z.tick = 0.35
		fireZones.append(z)
		sfx(.flask, at: x, 0.9)
		spawnParticles(x, gy - 0.4, 0xFF8030, 14, 5.0, 0.6, -2)
		spawnParticles(x, y, 0xB8E0F0, 6, 4.0, 0.3, 18)
		addLightFlash(x, gy - 0.8, peak: 12, dur: 0.5, radius: 3.0)
		_ = src
	}

	// MARK: storm rod

	/// Lightning down the aim to the first creature in its path, then leaping to up to three more
	/// close by (each strike a little weaker); creatures standing in water take half as much again
	func fireStormRod() {
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.25
		facing = aimFacing()
		let ang: Double = atan2(aimY - oy, aimX - ox)
		let dx: Double = cos(ang)
		let dy: Double = sin(ang)
		let maxL: Double = 14.0
		let ex: Double = ox + dx * maxL
		let ey: Double = oy + dy * maxL
		var endT: Double = 1.0
		if let w = world.segmentSolidT(ox, oy, ex, ey) { endT = w.2 }
		var first: Mob? = nil
		var ft: Double = endT
		for m in mobsNear(min(ox, ex) - 3, max(ox, ex) + 3) {
			if m.hp <= 0 || m.removed || m.downed { continue }
			if !canHarm(.player, targetFaction: faction(of: m), targetID: m.id, area: false) { continue }
			if let t = segmentBoxT(ox, oy, ex, ey, m.b.left - 0.15, m.b.top - 0.15, m.b.right + 0.15, m.b.y + 0.15), t < ft {
				ft = t
				first = m
			}
		}
		var anchors: [(Double, Double)] = [(ox, oy)]
		if let m0 = first {
			var chain: [Mob] = [m0]
			while chain.count < 4 {
				guard let cur = chain.last else { break }
				var next: Mob? = nil
				var nd: Double = 5.5 * 5.5
				for o in mobsNear(cur.b.x - 6, cur.b.x + 6) {
					if o.hp <= 0 || o.removed || o.downed || chain.contains(where: { $0 === o }) { continue }
					if !canHarm(.player, targetFaction: faction(of: o), targetID: o.id, area: false) { continue }
					let ddx: Double = o.b.x - cur.b.x
					let ddy: Double = o.b.cy - cur.b.cy
					let d2: Double = ddx * ddx + ddy * ddy
					if d2 < nd && world.lineClear(cur.b.x, cur.b.cy, o.b.x, o.b.cy) { nd = d2; next = o }
				}
				guard let n = next else { break }
				chain.append(n)
			}
			var dmg: Double = GunType.stormRod.damage
			var px: Double = ox
			for c in chain {
				var info = DamageInfo(amount: c.b.inWater ? dmg * 1.5 : dmg, type: .shock, source: .player)
				info.knock = 2.5
				info.originX = px
				info.originY = c.b.cy
				info.key = newID()
				if applyMobDamage(c, info) {
					lockTarget = c
					lockT = 2.0
				}
				anchors.append((c.b.x, c.b.cy))
				addLightFlash(c.b.x, c.b.cy, peak: 9, dur: 0.22, radius: 1.0, color: 0x6AA8FF)
				spawnParticles(c.b.x, c.b.cy, 0xD8F0FF, 4, 4.0, 0.2, 0)
				px = c.b.x
				dmg *= 0.8
			}
			if chain.count >= 2 {
				floatText("x" + String(chain.count), pb.x, pb.y - pb.h - 0.9, 0xB8E0FF)
				sfx(.multiHit, 0.5)
			}
		} else {
			anchors.append((ox + dx * maxL * endT, oy + dy * maxL * endT))
		}
		// a jagged line between the strikes
		var pts: [(Double, Double)] = [anchors[0]]
		var k: Int = 1
		while k < anchors.count {
			let a: (Double, Double) = anchors[k - 1]
			let b: (Double, Double) = anchors[k]
			let sx: Double = b.0 - a.0
			let sy: Double = b.1 - a.1
			let len: Double = max(0.01, sqrt(sx * sx + sy * sy))
			let steps: Int = max(2, Int(len / 1.2))
			for j in 1..<steps {
				let f: Double = Double(j) / Double(steps)
				let off: Double = Double.random(in: -0.35...0.35)
				pts.append((a.0 + sx * f - sy / len * off, a.1 + sy * f + sx / len * off))
			}
			pts.append(b)
			k += 1
		}
		if arcs.count > 6 { arcs.removeFirst() }
		arcs.append(ArcFX(pts: pts, life: 0.2))
		addLightFlash(ox + dx * 0.6, oy + dy * 0.6, peak: 8, dur: 0.15, radius: 0.7, color: 0x6AA8FF)
		sfx(.zap, 0.8)
		muzzleT = 0.08
		swingT = 0.12
		swingDir = facing
	}

	// MARK: effects, fire and recharge, once a frame

	func updateCombatFX(_ dt: Double) {
		if !slashes.isEmpty {
			for i in 0..<slashes.count { slashes[i].life -= dt }
			slashes.removeAll { $0.life <= 0 }
		}
		if !arcs.isEmpty {
			for i in 0..<arcs.count { arcs[i].life -= dt }
			arcs.removeAll { $0.life <= 0 }
		}
		if !fireZones.isEmpty { updateFireZones(dt) }
		// storm rods gather their charge back, one strike every few seconds, wherever they are carried
		rodT += dt
		if rodT >= GunType.stormRod.reloadTime {
			rodT = 0
			for i in 0..<inv.slots.count {
				if var st = inv.slots[i], case .gun(.stormRod) = st.item, st.extra < GunType.stormRod.magazine {
					st.extra += 1
					inv.slots[i] = st
					if i == sel { bumpHUD() }
				}
			}
		}
	}

	func updateFireZones(_ dt: Double) {
		var keep: [FireZone] = []
		for z0 in fireZones {
			var z: FireZone = z0
			z.t -= dt
			// rain puts fires out sooner
			let rain: Double = abs(z.x - pb.x) < 40 ? wxHere.precip : precipAt(z.x)
			if rain > 0.05 && !wxHere.snow { z.t -= dt * 2.0 * rain }
			z.tick += dt
			if z.tick >= 0.35 {
				z.tick = 0
				let src: DamageSource = z.env ? .environment : .player
				let hurtsMobs: Bool = !z.env || settings.weatherHurtsCreatures
				for m in mobsNear(z.x - z.r - 2, z.x + z.r + 2) where hurtsMobs {
					if m.hp <= 0 || m.removed { continue }
					if abs(m.b.x - z.x) > z.r + m.b.w * 0.5 { continue }
					if m.b.y < z.y - 2.4 || m.b.top > z.y + 0.4 { continue }
					if !canHarm(src, targetFaction: faction(of: m), targetID: m.id, area: true) { continue }
					var info = DamageInfo(amount: 2.0, type: .fire, source: src)
					info.originX = z.x
					info.key = z.uid
					info.cooldown = 0.3
					if applyMobDamage(m, info) && !heatImmune(m) { m.burn = max(m.burn, 2.5) }
				}
				// the thrower is not spared if they stand in it
				let hurtsPlayer: Bool = !z.env || settings.weatherHurtsPlayer
				if hurtsPlayer && !dead && abs(pb.x - z.x) < z.r + pb.w * 0.5 && pb.y > z.y - 2.0 && pb.top < z.y + 0.3 && !wearing(.emberCharm) {
					playerBurn = max(playerBurn, 0.8)
				}
				if z.t > 0.3 { spawnParticles(z.x + Double.random(in: -z.r...z.r), z.y - 0.3, 0xFFA030, 2, 1.5, 0.45, -5) }
			}
			if z.t > 0 { keep.append(z) }
		}
		fireZones = keep
	}

	/// What an abandoned ore cart still holds: a little ore, fixed by where it stands
	func oreCartLoad(_ x: Int, _ y: Int) -> [Stack] {
		var rng = RNG(hashU(x, y, gen.seed &+ 991))
		let deep: Bool = y > 230
		let kinds: [Mat] = deep ? [.ironOre, .silverOre, .coal, .tinOre, .goldOre] : [.coal, .copperOre, .tinOre, .coal, .ironOre]
		var out: [Stack] = []
		let a: Mat = kinds[rng.int(kinds.count)]
		out.append(Stack(item: .mat(a), count: 2 + rng.int(4)))
		if rng.double() < 0.5 {
			let b: Mat = kinds[rng.int(kinds.count)]
			if b != a { out.append(Stack(item: .mat(b), count: 1 + rng.int(3))) }
		}
		return out
	}
}
