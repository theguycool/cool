// PIXEL REALM v2, part 6 of 10: potions and mutation, infusions, the exosuit, building (furniture, stairs, lifts), block physics, and rails and trains.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== p29_alchemy =====

// MARK: - Alchemy: rarity, potions, ingredients

/// How rare something is. It colours a name and says how hard the ingredients are to come by: basic
/// things come from the overworld, rarer ones from deep places, storms, the Umbral realm and its bosses.
enum Rarity: Int, Codable, CaseIterable {
	case basic, uncommon, rare, veryRare, legendary
	var name: String {
		switch self {
		case .basic: return "Basic"
		case .uncommon: return "Uncommon"
		case .rare: return "Rare"
		case .veryRare: return "Very rare"
		case .legendary: return "Boss relic"
		}
	}
	var color: UInt32 {
		switch self {
		case .basic: return 0xD8D8D8
		case .uncommon: return 0x6EE07A
		case .rare: return 0x5AB4FF
		case .veryRare: return 0xC07CFF
		case .legendary: return 0xFFB040
		}
	}
}

/// Every potion. Drinkable ones work on the player at once or for a while; the rest are thrown and burst
/// over an area. Saved by number: new kinds only ever go on the end.
enum Potion: Int, Codable, CaseIterable {
	case mending, greaterMending, regrowth, brawn, quickstep, prospector, ironhide, emberward, deepbreath, owlsight, seeker, featherfall, hearthfire, springstep
	case searing, blight, mire, enfeeble, mendingSplash, regrowthSplash, smoke, frost, mutagen

	var name: String {
		switch self {
		case .mending: return "Mending Draught"
		case .greaterMending: return "Greater Mending Draught"
		case .regrowth: return "Regrowth Tonic"
		case .brawn: return "Brawn Brew"
		case .quickstep: return "Quickstep Elixir"
		case .prospector: return "Prospector's Draught"
		case .ironhide: return "Ironhide Tonic"
		case .emberward: return "Emberward Draught"
		case .deepbreath: return "Deepbreath Draught"
		case .owlsight: return "Owlsight Draught"
		case .seeker: return "Seeker's Tonic"
		case .featherfall: return "Featherfall Tonic"
		case .hearthfire: return "Hearthfire Tonic"
		case .springstep: return "Springstep Draught"
		case .searing: return "Searing Splash"
		case .blight: return "Blight Splash"
		case .mire: return "Mire Splash"
		case .enfeeble: return "Enfeebling Splash"
		case .mendingSplash: return "Mending Splash"
		case .regrowthSplash: return "Regrowth Splash"
		case .smoke: return "Smoke Flask"
		case .frost: return "Frost Splash"
		case .mutagen: return "Mutagen"
		}
	}

	/// thrown to burst (the others are drunk)
	var thrown: Bool { return rawValue >= Potion.searing.rawValue }

	/// the colour of what is inside (also the colour of its burst and of its effect's icon)
	var color: UInt32 {
		switch self {
		case .mending, .mendingSplash: return 0xE8445A
		case .greaterMending: return 0xFF2E6A
		case .regrowth, .regrowthSplash: return 0xF07AB8
		case .brawn: return 0xC8402A
		case .quickstep: return 0x7AD8F8
		case .prospector: return 0xE8B83A
		case .ironhide: return 0x9AA4B8
		case .emberward: return 0xFF8A2A
		case .deepbreath: return 0x2E7AE8
		case .owlsight: return 0x3A4AC8
		case .seeker: return 0x5AE070
		case .featherfall: return 0xE8ECF8
		case .hearthfire: return 0xE86A3A
		case .springstep: return 0x8AE85A
		case .searing: return 0xFF5A1E
		case .blight: return 0x6AB82E
		case .mire: return 0x7A5A3A
		case .enfeeble: return 0x8A7AA8
		case .smoke: return 0x8A8A90
		case .frost: return 0xA8E8FF
		case .mutagen: return 0x9AF04A
		}
	}

	var rarity: Rarity {
		switch self {
		case .mending, .springstep, .featherfall, .quickstep, .smoke, .mire: return .basic
		case .regrowth, .brawn, .prospector, .ironhide, .deepbreath, .owlsight, .hearthfire, .searing, .blight, .mendingSplash, .frost: return .uncommon
		case .emberward, .enfeeble, .regrowthSplash, .greaterMending: return .rare
		case .seeker: return .rare
		case .mutagen: return .veryRare
		}
	}

	/// the effect a drink gives, with its strength and seconds (nil: healing, which acts at once)
	var effect: ModEffect? {
		switch self {
		case .regrowth: return ModEffect(.regen, 1.0, 20)
		case .brawn: return ModEffect(.strength, 35, 60)
		case .quickstep: return ModEffect(.speed, 30, 90)
		case .prospector: return ModEffect(.mining, 60, 120)
		case .ironhide: return ModEffect(.resistance, 30, 90)
		case .emberward: return ModEffect(.fireproof, 1, 120)
		case .deepbreath: return ModEffect(.breathing, 1, 180)
		case .owlsight: return ModEffect(.nightVision, 1, 180)
		case .seeker: return ModEffect(.luck, 25, 150)
		case .featherfall: return ModEffect(.featherfall, 1, 120)
		case .hearthfire: return ModEffect(.warmth, 1, 240)
		case .springstep: return ModEffect(.jump, 40, 90)
		default: return nil
		}
	}

	/// health a mending potion gives back at once
	var healAmount: Double {
		switch self {
		case .mending: return 8
		case .greaterMending: return 14
		case .mendingSplash: return 6
		default: return 0
		}
	}

	/// how far a thrown potion's burst reaches (blocks)
	var radius: Double {
		switch self {
		case .searing: return 2.6
		case .blight: return 2.8
		case .mendingSplash, .regrowthSplash: return 3.2
		case .smoke: return 3.6
		case .mutagen: return 1.6
		default: return 3.0
		}
	}

	var maxStack: Int { return self == .mutagen ? 4 : (thrown ? 16 : 10) }

	/// what it does, in a line
	var blurb: String {
		switch self {
		case .mending: return "Heals 8 at once (then 10 s before mending works fully again)"
		case .greaterMending: return "Heals 14 at once (then 14 s before mending works fully again)"
		case .regrowth: return "Heals 1 a second for 20 s"
		case .brawn: return "Hit 35% harder for 60 s"
		case .quickstep: return "Run 30% faster for 90 s"
		case .prospector: return "Mine 60% faster for 2 min"
		case .ironhide: return "Take 30% less damage for 90 s"
		case .emberward: return "Fire and lava can't hurt you for 2 min"
		case .deepbreath: return "Breathe under water and swim faster for 3 min"
		case .owlsight: return "See in the dark for 3 min"
		case .seeker: return "A 25% chance of one extra ore, gem or creature drop, for 150 s"
		case .featherfall: return "Fall slowly and take no fall damage for 2 min"
		case .hearthfire: return "The cold can't get at you for 4 min"
		case .springstep: return "Jump 40% higher for 90 s"
		case .searing: return "Burns creatures it bursts over: 8 damage"
		case .blight: return "Poisons creatures: 1.5 a second for 8 s (not the undead or stone)"
		case .mire: return "Bogs creatures down: half speed for 8 s"
		case .enfeeble: return "Creatures hit 40% softer for 15 s"
		case .mendingSplash: return "Heals you and your animals within reach: 6"
		case .regrowthSplash: return "You and your animals heal 1 a second for 12 s"
		case .smoke: return "A cloud for 8 s: monsters can't see into or out of it"
		case .frost: return "Slows creatures hard, puts out fires, freezes still water"
		case .mutagen: return "The creature it hits doubles in size, health and strength"
		}
	}

	/// what it is like to use, for its tooltip
	var useLine: String {
		if self == .mutagen { return "Rare. Throw it at a creature: aim with the attack stick" }
		return thrown ? "Throw it: aim with the attack stick and let go" : "Tap to drink it"
	}
}

/// Seconds after drinking a mending potion before another heals fully (a second one inside that time
/// heals a third as much)
let mendingRest: [Double] = [10, 14]

// MARK: status effects on creatures

extension Mob {
	/// how hard its blows land: doubled by each mutation, softened while it is weakened
	var dmgMul: Double { return mutDmg * (weakT > 0 ? 0.6 : 1.0) * phaseDmg }
	/// how fast it moves: bogged down by mire, frost and frost-infused weapons
	var speedMul: Double { return slowT > 0 ? max(0.2, 1.0 - slowAmt) : 1.0 }
	/// any potion effect showing on it (for drawing)
	var hasStatus: Bool { return slowT > 0 || poisonT > 0 || weakT > 0 || regenT > 0 }
}

/// Creatures that poison does not touch: the restless dead, stone and crystal, and slimes
func poisonImmune(_ m: Mob) -> Bool {
	switch m.kind {
	case .zombie, .skeleton, .wraith, .golem, .sentinel, .warden, .slime, .emberSlime: return true
	default: return false
	}
}

// MARK: smoke

/// A smoke flask's cloud: monsters can't see into it or out of it while it lasts
struct SmokeCloud {
	var x: Double
	var y: Double
	var r: Double
	var t: Double
	var maxT: Double
}

/// Thrown-potion bursts drawn as a ring for a moment
struct BurstRing {
	var x: Double
	var y: Double
	var r: Double
	var t: Double
	var color: UInt32
}

// MARK: mutation limits

/// Safe limits for creature mutation. Each dose doubles size, health and strength, but the numbers stop
/// at these caps, so stacking can never break the physics, the drawing or the arithmetic.
enum MutationLimits {
	/// doses a creature can take (more still burst, but change nothing)
	static let maxStacks: Int = 8
	/// the most a body may grow to, in blocks
	static let maxW: Double = 7.0
	static let maxH: Double = 7.0
	/// size multiplier cap (whatever the doses)
	static let maxSize: Double = 8.0
	/// health: at most this many times the normal amount, and never above `maxHP`
	static let maxHPMul: Double = 64.0
	static let maxHP: Double = 3000.0
	/// strength: at most this many times the normal blow, and no blow above `maxBlow`
	static let maxDmgMul: Double = 6.0
	static let maxBlow: Double = 26.0
	/// bosses take one dose only, and it is milder
	static let bossHP: Double = 1.5
	static let bossDmg: Double = 1.25
	static let bossSize: Double = 1.15
	/// mutated creatures kept (and saved) at once; the oldest wild ones give way
	static let maxMutants: Int = 16
}

// MARK: saving

/// The player's potion effects in a save: each kind by number with its strength and time left
struct EffectsSave: Codable {
	var kinds: [Int]
	var amount: [Double]
	var time: [Double]
	/// seconds before mending potions heal fully again
	var mendCD: Double? = nil
}

/// A mutated creature in a save (wild ones as well as pets): where it is and how mutated
struct MutantSave: Codable {
	var kind: Int
	var x: Double
	var y: Double
	var hp: Double
	var maxHP: Double
	var mut: Int
	var variant: Int
	var tame: Bool
	var dim: Int
}

extension Game {
	// MARK: effects every frame

	/// Every frame: effects run down; regeneration heals; fire protection puts out flames. Runs in every
	/// world (mod armour's worn effects and jump pads are in updateModPlay).
	func updateEffects(_ dt: Double) {
		effects.tick(dt)
		if mendCD > 0 { mendCD = max(0, mendCD - dt) }
		let regen: Double = effects.value(.regen) + armorInf.regen
		if regen > 0 && !dead && hp < maxHP {
			effects.regenAcc += regen * dt
			if effects.regenAcc >= 1 {
				let n: Double = floor(effects.regenAcc)
				effects.regenAcc -= n
				hp = min(maxHP, hp + n)
				bumpHUD()
			}
		}
		if effects.value(.fireproof) > 0 { playerBurn = 0 }
		// a falling body drifts down gently and lands softly
		if effects.value(.featherfall) > 0 && !pb.onGround && !pb.inWater && inVehicle == nil && mounted == nil {
			if pb.vy > 5.5 { pb.vy = 5.5 }
			fallPeak = 0
		}
		if !smokes.isEmpty {
			for i in smokes.indices { smokes[i].t -= dt }
			smokes.removeAll { $0.t <= 0 }
		}
		if !rings.isEmpty {
			for i in rings.indices { rings[i].t -= dt }
			rings.removeAll { $0.t <= 0 }
		}
		updateSuit(dt)
	}

	/// Potion effects on a creature, once a frame: slows and weakness wear off, poison hurts once a
	/// second, regeneration heals
	func mobStatus(_ m: Mob, _ dt: Double) {
		if m.slowT > 0 { m.slowT -= dt }
		if m.weakT > 0 { m.weakT -= dt }
		if m.poisonT > 0 {
			m.poisonT -= dt
			m.poisonTick += dt
			if m.poisonTick >= 1.0 {
				m.poisonTick = 0
				var info = DamageInfo(amount: m.poisonDps, type: .poison, source: m.poisonByPlayer ? .player : .environment)
				info.originX = m.b.x
				applyMobDamage(m, info)
				spawnParticles(m.b.x, m.b.top + 0.2, 0x7AD040, 3, 1.2, 0.5, -3)
			}
		}
		if m.regenT > 0 {
			m.regenT -= dt
			m.regenAcc += m.regenRate * dt
			if m.regenAcc >= 1 {
				let n: Double = floor(m.regenAcc)
				m.regenAcc -= n
				m.hp = min(m.maxHP, m.hp + n)
			}
		}
	}

	// MARK: drinking

	/// A potion in hand: drink it, or throw it
	func usePotion(_ p: Potion, _ pressed: Bool) {
		if p.thrown {
			if pressed { throwPotion(p) }
			return
		}
		if !pressed || useCD > 0 { return }
		drinkPotion(p)
	}

	/// Drinks a potion from the selected slot: its effect, a sip sound, bubbles in its colour and a word
	/// over the player's head
	func drinkPotion(_ p: Potion) {
		guard let s = inv.slots[sel], s.item == .potion(p) else { return }
		if p.healAmount > 0 {
			if hp >= maxHP && !isCreative {
				say("You are not hurt.", 1.2)
				useCD = 0.4
				return
			}
			let rested: Bool = mendCD <= 0
			let amount: Double = rested ? p.healAmount : (p.healAmount / 3.0).rounded()
			heal(amount)
			mendCD = max(mendCD, p == .greaterMending ? mendingRest[1] : mendingRest[0])
			floatText(joinText("+", String(Int(amount))), pb.x, pb.y - pb.h - 0.4, 0x60F070)
			if !rested { say("Too soon after the last: it only mends a little.", 1.6) }
		} else if let e = p.effect {
			effects.add(e.kind, e.amount, e.seconds)
			floatText(e.kind.short, pb.x, pb.y - pb.h - 0.4, p.color)
			if e.kind == .nightVision { light.valid = false }
		}
		if !isCreative { inv.removeAt(sel, 1) }
		useCD = 0.7
		eatT = 0.6
		sfx(.drink, 0.7)
		spawnParticles(pb.x + Double(facing) * 0.3, pb.y - 1.5, p.color, 8, 2.0, 0.6, -3)
		if !journal.crafted.contains(p.name) { journal.crafted.append(p.name) }
		bumpHUD()
	}

	// MARK: throwing

	/// Throws a potion from the selected slot in a lob toward the aim: it flies as a flask and bursts
	/// where it lands or on the first creature it meets
	func throwPotion(_ p: Potion) {
		if useCD > 0 { return }
		guard let s = inv.slots[sel], s.item == .potion(p) else { return }
		if !isCreative { inv.removeAt(sel, 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		let a: Double = lobAngle(aimX - ox, aimY - oy, throwSpeed, throwGravity)
		var pr = Projectile(kind: .flask, x: ox, y: oy, vx: cos(a) * throwSpeed, vy: sin(a) * throwSpeed, dmg: 0, fromPlayer: true, gravity: throwGravity)
		pr.life = 2.5
		pr.w = 0.3
		pr.source = .player
		pr.uid = newID()
		pr.potion = p.rawValue
		// the creature under the aim (a mutagen goes to it even if it is hit only at the edge)
		pr.owner = -1
		projectiles.append(pr)
		useCD = 0.5
		swingT = 0.18
		swingDir = facing
		sfx(.swingLight, 0.5)
		bumpHUD()
	}

	/// A thrown potion breaks: what it does to everything within its reach (through open air only), a
	/// ring and a puff in its colour, and the sound of glass
	func burstPotion(_ p: Potion, _ x: Double, _ y: Double, direct: Mob?) {
		let r: Double = p.radius
		sfx(.potionBreak, at: x, 0.9)
		spawnParticles(x, y, p.color, 14, 4.5, 0.55, 6)
		spawnParticles(x, y, 0xD8F0FF, 5, 3.5, 0.3, 16)
		if rings.count >= 6 { rings.removeFirst() }
		rings.append(BurstRing(x: x, y: y, r: r, t: 0.35, color: p.color))
		addLightFlash(x, y - 0.3, peak: 9, dur: 0.35, radius: r, color: p.color)
		switch p {
		case .smoke:
			if smokes.count >= 4 { smokes.removeFirst() }
			smokes.append(SmokeCloud(x: x, y: y - 0.8, r: r, t: 8.0, maxT: 8.0))
			return
		case .mutagen:
			var target: Mob? = direct
			if target == nil {
				var bd: Double = r
				for m in mobsNear(x - r - 3, x + r + 3) where m.hp > 0 && !m.removed && !m.downed {
					let d: Double = boxDistance(x, y, m.b.left, m.b.top, m.b.right, m.b.y)
					if d <= bd { bd = d; target = m }
				}
			}
			if let m = target { _ = mutate(m) } else { floatText("Nothing to change", x, y - 0.6, 0xC8C8C8) }
			return
		default: break
		}
		let helpful: Bool = p == .mendingSplash || p == .regrowthSplash
		if helpful && !dead {
			let d: Double = boxDistance(x, y, pb.left, pb.top, pb.right, pb.y)
			if d <= r && world.lineClear(x, y, pb.x, pb.cy) { splashPlayer(p) }
		}
		if p == .frost { frostBurst(x, y, r) }
		for m in mobsNear(x - r - 4, x + r + 4) {
			if m.hp <= 0 || m.removed { continue }
			let d: Double = boxDistance(x, y, m.b.left, m.b.top, m.b.right, m.b.y)
			if d > r { continue }
			if !world.lineClear(x, y, m.b.x, m.b.cy) && direct !== m { continue }
			if helpful {
				if m.tame { splashMob(p, m) }
			} else if !m.tame {
				splashMob(p, m)
			}
		}
	}

	/// A helpful splash on the player
	func splashPlayer(_ p: Potion) {
		if p == .mendingSplash {
			let rested: Bool = mendCD <= 0
			let amount: Double = rested ? p.healAmount : (p.healAmount / 3.0).rounded()
			if hp < maxHP {
				heal(amount)
				floatText(joinText("+", String(Int(amount))), pb.x, pb.y - pb.h - 0.4, 0x60F070)
			}
			mendCD = max(mendCD, mendingRest[0])
		} else if p == .regrowthSplash {
			effects.add(.regen, 1.0, 12)
			floatText(ModEffectKind.regen.short, pb.x, pb.y - pb.h - 0.4, p.color)
		}
		bumpHUD()
	}

	/// A splash on a creature. Bosses feel the harmful ones less.
	func splashMob(_ p: Potion, _ m: Mob) {
		let boss: Bool = m.isBoss
		switch p {
		case .mendingSplash:
			m.hp = min(m.maxHP, m.hp + p.healAmount)
			floatText(joinText("+", String(Int(p.healAmount))), m.b.x, m.b.top - 0.3, 0x60F070)
		case .regrowthSplash:
			m.regenT = 12
			m.regenRate = 1.0
		case .searing:
			var info = DamageInfo(amount: 8, type: .magic, source: .player)
			info.originX = m.b.x
			info.knock = 3
			info.key = newID()
			applyMobDamage(m, info)
		case .blight:
			if poisonImmune(m) {
				floatText("Immune", m.b.x, m.b.top - 0.3, 0xB8B8B8)
			} else {
				m.poisonT = max(m.poisonT, boss ? 4.0 : 8.0)
				m.poisonDps = boss ? 0.75 : 1.5
				m.poisonByPlayer = true
				m.lastHitByPlayer = clock
				angerBy(m)
			}
		case .mire:
			m.slowT = max(m.slowT, boss ? 4.0 : 8.0)
			m.slowAmt = max(m.slowT > 0 ? m.slowAmt : 0, boss ? 0.25 : 0.5)
			angerBy(m)
		case .enfeeble:
			m.weakT = max(m.weakT, boss ? 8.0 : 15.0)
			angerBy(m)
		case .frost:
			m.slowT = max(m.slowT, boss ? 2.0 : 4.0)
			m.slowAmt = max(m.slowAmt, boss ? 0.35 : 0.7)
			m.burn = 0
			angerBy(m)
		default: break
		}
	}

	/// A harmful splash counts as an attack: animals that defend themselves turn on the player
	func angerBy(_ m: Mob) {
		m.lastHitByPlayer = clock
		if m.def.behavior == .defensive {
			m.angry = true
			m.t3 = 10.0
		}
	}

	/// Frost: fires in reach go out (on the player too), and still water near the burst freezes over
	func frostBurst(_ x: Double, _ y: Double, _ r: Double) {
		if !dead && boxDistance(x, y, pb.left, pb.top, pb.right, pb.y) <= r { playerBurn = 0 }
		fireZones.removeAll { abs($0.x - x) < r + $0.r && abs($0.y - y) < r + 1.5 }
		let x0: Int = Int(floor(x - r))
		let x1: Int = Int(floor(x + r))
		let y0: Int = Int(floor(y - r))
		let y1: Int = Int(floor(y + r))
		var frozen: Int = 0
		for ty in y0...y1 {
			for tx in x0...x1 where frozen < 16 {
				let dx: Double = Double(tx) + 0.5 - x
				let dy: Double = Double(ty) + 0.5 - y
				if dx * dx + dy * dy > r * r { continue }
				// only the surface of water (open air above it) freezes, so nothing is sealed in
				if world.tile(tx, ty) == .water && world.tile(tx, ty - 1) == .air {
					world.set(tx, ty, .ice)
					frozen += 1
				}
			}
		}
	}

	/// True when a point is inside a smoke cloud
	func inSmoke(_ x: Double, _ y: Double) -> Bool {
		for s in smokes {
			let dx: Double = x - s.x
			let dy: Double = y - s.y
			if dx * dx + dy * dy < s.r * s.r { return true }
		}
		return false
	}

	// MARK: vials and ingredients

	/// An empty vial held over water fills it (one each tap)
	func useVial(_ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if world.tile(tx, ty) == .water && inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
			_ = inv.remove(.mat(.vial), 1)
			giveItem(.mat(.waterVial), 1)
			sfx(.splash, 0.5)
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.2, 0x8DBBFF, 5, 2.0, 0.4, 10)
			useCD = 0.25
			bumpHUD()
		} else {
			say("Tap water with it to fill it.", 1.4)
			useCD = 0.4
		}
	}

	/// Ingredients a creature leaves when the player killed it, the extra drops of a Seeker's Tonic, and
	/// the glands of a mutated creature
	func alchemyDrops(_ m: Mob, _ rng: inout RNG, _ credit: Bool) -> [Stack] {
		var out: [Stack] = []
		if !credit || m.tame { return out }
		func chance(_ it: Mat, _ p: Double, _ n: Int = 1) {
			if rng.double() < p { out.append(Stack(item: .mat(it), count: n)) }
		}
		switch m.kind {
		case .slime: chance(.slimeGel, 0.6, 1 + rng.int(2))
		case .emberSlime: chance(.slimeGel, 0.4); chance(.emberAsh, 0.45)
		case .scorpion: chance(.venomSac, 0.5)
		case .crawler: chance(.venomSac, 0.35)
		case .polarBear: chance(.frostCrystal, 0.4)
		case .imp, .cinderBat: chance(.emberAsh, 0.4)
		case .wraith: chance(.wraithDust, 0.6)
		case .bat: chance(.glowcap, 0.25)
		case .golem: chance(.golemCore, 0.35)
		case .sentinel: out.append(Stack(item: .mat(.sentinelLens), count: 1 + rng.int(2)))
		case .warden: out.append(Stack(item: .mat(.emberAsh), count: 4))
		default: break
		}
		if m.mut > 0 {
			out.append(Stack(item: .mat(.mutantGland), count: min(4, 1 + m.mut / 2)))
		}
		// luck: one more of what it normally drops, now and then (never anything it would not drop)
		let luck: Double = effects.value(.luck) / 100.0
		if luck > 0 && rng.double() < luck {
			var r2 = RNG(UInt64(truncatingIfNeeded: m.id) &* 0x9E3779B97F4A7C15 &+ 77)
			if let extra = mobDrops(m.kind, &r2, m.sheared).first(where: { !$0.item.isRareLoot }) {
				out.append(Stack(item: extra.item, count: 1))
				floatText("Lucky!", m.b.x, m.b.top - 0.6, 0x5AE070)
			}
		}
		return out
	}

	// MARK: mutation

	/// One dose of mutagen on a creature: it grows to twice the size (as far as there is room), with
	/// twice the health and twice the strength, its colours shift a little, and it keeps its own mind.
	/// Every number stops at the limits in MutationLimits. Returns whether anything changed.
	@discardableResult
	func mutate(_ m: Mob) -> Bool {
		if m.hp <= 0 || m.removed { return false }
		let base: MobDef = m.def
		if m.isBoss && m.mut >= 1 {
			floatText("It resists further change", m.b.x, m.b.top - 0.6, 0xC8C8C8)
			return false
		}
		if m.mut >= MutationLimits.maxStacks {
			floatText("It can change no further", m.b.x, m.b.top - 0.6, 0xC8C8C8)
			return false
		}
		let boss: Bool = m.isBoss
		m.mut += 1
		// health: the same share of health as before, of a doubled (capped) total
		let frac: Double = m.maxHP > 0 ? clampD(m.hp / m.maxHP, 0.05, 1.0) : 1.0
		let hpMul: Double = boss ? MutationLimits.bossHP : 2.0
		let cap: Double = min(MutationLimits.maxHP, base.hp * mobHealthMult * MutationLimits.maxHPMul)
		m.maxHP = min(cap, max(m.maxHP, m.maxHP * hpMul))
		m.hp = max(1, m.maxHP * frac)
		// strength: doubled, with no single blow above the cap
		let dmgMul: Double = boss ? MutationLimits.bossDmg : 2.0
		let blowCap: Double = base.dmg > 0 ? MutationLimits.maxBlow / base.dmg : MutationLimits.maxDmgMul
		m.mutDmg = min(min(MutationLimits.maxDmgMul, blowCap), max(1.0, m.mutDmg * dmgMul))
		// size: doubled, within the caps and only as far as there is room around it
		let want: Double = min(mutCap(base), m.mutSize * (boss ? MutationLimits.bossSize : 2.0))
		let grown: Double = growRoom(m, base, want)
		let changedSize: Bool = grown > m.mutSize + 0.001
		setMutSize(m, base, grown)
		m.persistent = true
		m.flash = 0.25
		spawnParticles(m.b.x, m.b.cy, 0x9AF04A, 16, 4.0, 0.7, -2)
		spawnParticles(m.b.x, m.b.cy, 0xC07CFF, 8, 3.0, 0.6, -2)
		sfx(.roar, at: m.b.x, 0.5)
		addShake(0.2)
		var note: String = joinText(base.name, " mutates! (", String(m.mut), ")")
		if !changedSize && !boss { note = joinText(base.name, " grows stronger, but has no room to grow") }
		floatText(note, m.b.x, m.b.top - 0.8, 0x9AF04A)
		keepMutantsInCheck()
		bumpHUD()
		return true
	}

	/// The largest size up to `want` that fits where the creature stands (it may rise a little to fit)
	func growRoom(_ m: Mob, _ base: MobDef, _ want: Double) -> Double {
		var s: Double = want
		var tries: Int = 0
		while s > m.mutSize + 0.001 && tries < 6 {
			tries += 1
			let w: Double = base.w * s
			let h: Double = base.h * s
			let hw: Double = w * 0.5
			var lift: Double = 0
			while lift <= 2.0 {
				let fy: Double = m.b.y - lift
				if !world.boxSolid(m.b.x - hw + 0.02, fy - h + 0.02, m.b.x + hw - 0.02, fy - 0.02) {
					if lift > 0 { m.b.y = fy }
					return s
				}
				lift += 1.0
			}
			s = m.mutSize + (s - m.mutSize) * 0.6
			if s - m.mutSize < 0.1 { break }
		}
		return m.mutSize
	}

	/// The biggest a creature may grow: the size cap, and no wider or taller than the body limits
	func mutCap(_ base: MobDef) -> Double {
		let a: Double = MutationLimits.maxW / max(0.1, base.w)
		let b: Double = MutationLimits.maxH / max(0.1, base.h)
		return max(1.0, min(MutationLimits.maxSize, min(a, b)))
	}

	/// Sets the body size from the size multiplier, so the hit box and the picture always agree
	func setMutSize(_ m: Mob, _ base: MobDef, _ s: Double) {
		m.mutSize = clampD(s, 1.0, mutCap(base))
		m.b.w = base.w * m.mutSize
		m.b.h = base.h * m.mutSize
	}

	/// The drawn size of a creature against its normal size (1 for creatures that never mutated); the
	/// same number as its body, so what is seen is what can be hit
	func drawScale(_ m: Mob) -> Double {
		return m.mut > 0 ? max(1.0, m.mutSize) : 1.0
	}

	/// Too many mutated creatures: the oldest wild ones (not pets, not bosses) lose their hold on the
	/// world and wander off like any other creature
	func keepMutantsInCheck() {
		let list: [Mob] = mobs.filter { $0.mut > 0 && $0.hp > 0 && !$0.removed }
		if list.count <= MutationLimits.maxMutants { return }
		var extra: Int = list.count - MutationLimits.maxMutants
		for m in list where extra > 0 && !m.tame && !m.isBoss {
			m.persistent = false
			extra -= 1
		}
	}

	/// The mutated creatures for a save
	func mutantSaves() -> [MutantSave]? {
		var out: [MutantSave] = []
		for m in mobs where m.mut > 0 && m.hp > 0 && !m.removed && m.persistent && m.kind != .rex && m.kind != .custom && !m.isBoss {
			if m.tame { continue }
			out.append(MutantSave(kind: m.kind.rawValue, x: m.b.x, y: m.b.y, hp: m.hp, maxHP: m.maxHP, mut: m.mut, variant: m.variant, tame: false, dim: world.dim.rawValue))
			if out.count >= MutationLimits.maxMutants { break }
		}
		return out.isEmpty ? nil : out
	}

	/// Brings saved mutated creatures back (those of the realm the player is in)
	func restoreMutants(_ list: [MutantSave]) {
		for s in list.prefix(MutationLimits.maxMutants) where s.dim == world.dim.rawValue {
			guard let k = MobKind(rawValue: s.kind), k != .custom, k != .rex else { continue }
			let m: Mob = addMob(k, s.x, s.y)
			m.variant = s.variant
			reapplyMutation(m, clampI(s.mut, 1, MutationLimits.maxStacks))
			m.maxHP = clampD(s.maxHP, 1, MutationLimits.maxHP)
			m.hp = clampD(s.hp, 1, m.maxHP)
			m.persistent = true
		}
	}

	/// Puts a creature back to `n` doses (loading): the size, health and strength it had
	func reapplyMutation(_ m: Mob, _ n: Int) {
		let base: MobDef = m.def
		m.mut = 0
		m.mutDmg = 1
		m.mutSize = 1
		let boss: Bool = m.isBoss
		let doses: Int = boss ? min(1, n) : n
		var size: Double = 1
		var dmg: Double = 1
		var hpv: Double = m.maxHP
		let cap: Double = min(MutationLimits.maxHP, base.hp * mobHealthMult * MutationLimits.maxHPMul)
		let blowCap: Double = base.dmg > 0 ? MutationLimits.maxBlow / base.dmg : MutationLimits.maxDmgMul
		for _ in 0..<doses {
			size = min(mutCap(base), size * (boss ? MutationLimits.bossSize : 2.0))
			dmg = min(min(MutationLimits.maxDmgMul, blowCap), dmg * (boss ? MutationLimits.bossDmg : 2.0))
			hpv = min(cap, hpv * (boss ? MutationLimits.bossHP : 2.0))
		}
		m.mut = doses
		m.mutDmg = max(1, dmg)
		m.maxHP = max(m.maxHP, hpv)
		m.hp = m.maxHP
		setMutSize(m, base, growRoom(m, base, size))
	}
}

extension Item {
	/// one of a kind or found only in the best chests (a Seeker's Tonic never doubles these)
	var isRareLoot: Bool {
		switch self {
		case .relic, .gear: return true
		case .mat(let m): return m == .umbralHeart || m == .relicFragment || m == .sentinelLens || m == .diamond
		default: return MineLoot.isExceptional(self)
		}
	}
}

extension ModEffectKind {
	/// a word or two shown over the player when the effect starts
	var short: String {
		switch self {
		case .heal: return "Healed"
		case .feed: return "Fed"
		case .speed: return "Swift"
		case .strength: return "Strong"
		case .resistance: return "Ironhide"
		case .regen: return "Regrowth"
		case .glow: return "Glowing"
		case .jump: return "Springy"
		case .fireproof: return "Fireproof"
		case .cure: return "Cured"
		case .mining: return "Prospecting"
		case .breathing: return "Water breathing"
		case .nightVision: return "Night vision"
		case .luck: return "Lucky"
		case .featherfall: return "Featherlight"
		case .warmth: return "Warm"
		}
	}

	/// the colour of its icon in the HUD
	var color: UInt32 {
		switch self {
		case .heal: return 0xE8445A
		case .feed: return 0xC0703A
		case .speed: return 0x7AD8F8
		case .strength: return 0xC8402A
		case .resistance: return 0x9AA4B8
		case .regen: return 0xF07AB8
		case .glow: return 0xFFE070
		case .jump: return 0x8AE85A
		case .fireproof: return 0xFF8A2A
		case .cure: return 0xE8E8E8
		case .mining: return 0xE8B83A
		case .breathing: return 0x2E7AE8
		case .nightVision: return 0x5A6AE8
		case .luck: return 0x5AE070
		case .featherfall: return 0xE8ECF8
		case .warmth: return 0xE86A3A
		}
	}
}

extension World {
	/// A few ingredients, now and then a potion or a compound, added to a chest's loot. Fixed by the
	/// world and the chest's place (like the rest of its loot); deeper and Umbral chests hold rarer finds.
	func alchemyChestExtras(_ base: [Stack], _ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> [Stack] {
		var out: [Stack] = base
		if out.count >= 27 { return out }
		var rng = RNG(hashU(x &+ 913, y, g.seed &+ 0xA1C4E))
		let deep: Bool = dim == .umbral || y > 140
		if rng.double() < 0.4 {
			var pool: [Mat] = [.sunleaf, .vial, .slimeGel, .waterVial]
			if deep { pool += [.glowcap, .frostCrystal, .venomSac] }
			if dim == .umbral { pool = [.emberAsh, .glowcap, .wraithDust, .venomSac] }
			let m: Mat = pool[rng.int(pool.count)]
			out.append(Stack(item: .mat(m), count: 1 + rng.int(3)))
		}
		if rng.double() < (deep ? 0.12 : 0.07) && out.count < 27 {
			let pool: [Potion] = deep ? [.regrowth, .ironhide, .owlsight, .prospector, .emberward, .blight] : [.mending, .quickstep, .springstep, .featherfall, .mire, .smoke]
			out.append(Stack(item: .potion(pool[rng.int(pool.count)]), count: 1 + rng.int(2)))
		}
		if rng.double() < (deep ? 0.05 : 0.02) && out.count < 27 {
			let pool: [Infusion] = deep ? [.keen, .venom, .bountiful, .fireward, .bulwark, .fleet] : [.honed, .heft, .haste, .reinforced]
			out.append(Stack(item: .compound(pool[rng.int(pool.count)]), count: 1))
		}
		return out
	}
}

extension Game {
	// MARK: guards on the player

	/// A hit after the armour infusions and the suit have done their part (before armour and wards)
	func guardedAmount(_ info: DamageInfo) -> Double {
		var a: Double = info.amount
		if info.source.kind == .mob { a *= info.source.mult }
		let ai: ArmorInf = armorInf
		if info.type == .fire || info.type == .lava { a *= 1.0 - ai.fireCut }
		if info.type == .shock { a *= 1.0 - ai.stormCut }
		if a > 6 && ai.heavyCut > 0 { a *= 1.0 - ai.heavyCut }
		return suitGuard(a, info)
	}

	/// How far the player is thrown by a blow: Bulwark armour and a heavy suit hold them steadier
	var knockTaken: Double {
		var k: Double = armorInf.knockMul
		if suit.worn { k *= suitStats.knockMul }
		return k
	}

	/// Barbed armour: a creature that strikes the player takes some of the blow back
	func thornsBack(_ info: DamageInfo, _ amount: Double) {
		let t: Double = armorInf.thorns
		if t <= 0 || info.source.kind != .mob { return }
		if info.type != .melee && info.type != .contact { return }
		guard let m = mobs.first(where: { $0.id == info.source.id }), m.hp > 0 else { return }
		var back = DamageInfo(amount: max(0.5, amount * t), type: .magic, source: .player)
		back.originX = pb.x
		applyMobDamage(m, back)
	}

	/// How much of the cold still gets in: a Hearthfire Tonic keeps it all out; Frostward armour and the
	/// suit keep some out
	func coldGuard() -> Double {
		if effects.value(.warmth) > 0 { return 0 }
		return (1.0 - armorInf.coldCut) * suitColdMul
	}

	/// The held weapon's Quickened infusion: attacks come sooner
	func quickMul() -> Double {
		if let s = inv.slots[sel], s.has(.quickened) { return 0.85 }
		return 1.0
	}

	/// A flask lands: a potion bursts, a fire flask catches
	func burstFlaskOrPotion(_ p: Projectile, _ x: Double, _ y: Double, _ m: Mob?) {
		if p.potion >= 0, let pt = Potion(rawValue: p.potion) {
			burstPotion(pt, x, y, direct: m)
		} else {
			burstFlask(x, y, p.source)
		}
	}

	/// A lightning strike near the player sometimes leaves a spark of storm essence behind (a lightning
	/// rod catches it more often)
	func stormEssenceAt(_ x: Double, _ y: Double, rod: Bool) {
		if abs(x - pb.x) > 60 || world.dim != .overworld { return }
		let p: Double = rod ? 0.5 : 0.2
		if Double.random(in: 0...1) < p {
			spawnDrop(Stack(item: .mat(.stormEssence), count: 1), x, y - 0.6, 0, -2)
			spawnParticles(x, y - 0.4, 0xFFF07A, 6, 2.0, 0.6, -2)
		}
	}

	/// The tapped station's screens
	func openExo() {
		showExo = true
		bumpHUD()
	}

	func openInfuser() {
		showInfuse = true
		bumpHUD()
	}

	// MARK: saving

	func effectsSave() -> EffectsSave? {
		var k: [Int] = []
		var a: [Double] = []
		var t: [Double] = []
		for kind in ModEffectKind.allCases where effects.time[kind.rawValue] > 0 {
			k.append(kind.rawValue)
			a.append(effects.amount[kind.rawValue])
			t.append(effects.time[kind.rawValue])
		}
		if k.isEmpty && mendCD <= 0 { return nil }
		return EffectsSave(kinds: k, amount: a, time: t, mendCD: mendCD > 0 ? mendCD : nil)
	}

	func restoreEffects(_ s: EffectsSave) {
		for (i, raw) in s.kinds.enumerated() where i < s.amount.count && i < s.time.count {
			guard let kind = ModEffectKind(rawValue: raw), kind.timed else { continue }
			let amount: Double = clampD(s.amount[i], kind.amountRange.lo, kind.amountRange.sandboxHi)
			effects.add(kind, amount, clampD(s.time[i], 0, 3600))
		}
		mendCD = clampD(s.mendCD ?? 0, 0, 60)
	}

	/// A saved suit, checked: one built the old way (a part in each place) is rebuilt piece by piece (a
	/// part in a place it doesn't fit goes back into the bag), every piece kept within the suit's limits
	func restoreSuit(_ s: ExoSuit) {
		var clean: ExoSuit = ExoSuit()
		var loose: [Stack] = []
		for (k, st) in s.parts {
			if let slot = ExoSlot(rawValue: k), slot.fits(st.item) { clean[slot] = st } else { loose.append(st) }
		}
		clean.design = s.design
		clean.migrate()
		var d: SuitDesign = clean.d
		if d.pieces.count > SuitDesign.maxPieces { d.pieces = Array(d.pieces.prefix(SuitDesign.maxPieces)) }
		for k in d.pieces.indices { d.pieces[k].clamp() }
		clean.d = d
		let stats: ExoStats = ExoStats.of(clean)
		clean.energy = clampD(s.energy, 0, stats.capacity)
		clean.worn = s.worn && stats.complete
		clean.off = s.off
		suit = clean
		for st in loose { addStack(st) }
		suitChanged()
	}
}

// MARK: - Recipes for alchemy, infusion compounds and the suit

extension RecipeBook {
	static func addFeatureRecipes(_ add: (Item, Int, [(Item, Int)], Station, RecipeCat) -> Void) {
		let wv: Item = .mat(.waterVial)
		func m(_ x: Mat) -> Item { return .mat(x) }
		func pot(_ p: Potion) -> Item { return .potion(p) }
		// the stations
		add(.block(.alchemyStill), 1, [(m(.copperBar), 4), (.block(.glass), 3), (.block(.stone), 4)], .bench, .alchemy)
		add(.block(.infuser), 1, [(.block(.obsidian), 4), (m(.goldBar), 2), (m(.crystalShard), 2), (m(.ironBar), 4)], .anvil, .infusion)
		add(.block(.exoStation), 1, [(m(.ironBar), 10), (m(.copperBar), 6), (.block(.glass), 2), (m(.goldBar), 1)], .anvil, .exosuit)
		// vials and water
		add(m(.vial), 3, [(.block(.glass), 1)], .furnace, .alchemy)
		add(m(.vial), 3, [(.block(.glass), 1)], .still, .alchemy)
		add(wv, 3, [(.gadget(.waterFlask), 1), (m(.vial), 3)], .still, .alchemy)
		// drinkable potions
		add(pot(.mending), 1, [(wv, 1), (m(.sunleaf), 2), (.food(.apple), 1)], .still, .alchemy)
		add(pot(.greaterMending), 1, [(pot(.mending), 1), (m(.glowcap), 1), (m(.crystalShard), 1)], .still, .alchemy)
		add(pot(.regrowth), 1, [(wv, 1), (m(.sunleaf), 1), (m(.slimeGel), 1), (.food(.carrot), 1)], .still, .alchemy)
		add(pot(.brawn), 1, [(wv, 1), (m(.claw), 1), (m(.bone), 1)], .still, .alchemy)
		add(pot(.quickstep), 1, [(wv, 1), (m(.feather), 2), (m(.sunleaf), 1)], .still, .alchemy)
		add(pot(.prospector), 1, [(wv, 1), (m(.amethyst), 1), (m(.glowcap), 1)], .still, .alchemy)
		add(pot(.ironhide), 1, [(wv, 1), (m(.ironBar), 1), (m(.tusk), 1)], .still, .alchemy)
		add(pot(.emberward), 1, [(wv, 1), (m(.frostCrystal), 1), (m(.slimeGel), 1), (.block(.obsidian), 1)], .still, .alchemy)
		add(pot(.deepbreath), 1, [(wv, 1), (.food(.rawFish), 1), (m(.sunleaf), 1)], .still, .alchemy)
		add(pot(.owlsight), 1, [(wv, 1), (m(.glowcap), 1), (.food(.carrot), 1)], .still, .alchemy)
		add(pot(.seeker), 1, [(wv, 1), (m(.goldBar), 1), (m(.crystalShard), 1), (m(.glowcap), 1)], .still, .alchemy)
		add(pot(.featherfall), 1, [(wv, 1), (m(.feather), 3)], .still, .alchemy)
		add(pot(.hearthfire), 1, [(wv, 1), (m(.coal), 1), (m(.fur), 1)], .still, .alchemy)
		add(pot(.springstep), 1, [(wv, 1), (m(.slimeGel), 1), (m(.feather), 1)], .still, .alchemy)
		// splashes (gunpowder bursts the flask)
		add(pot(.searing), 2, [(wv, 1), (m(.gunpowder), 1), (m(.saltpeter), 1)], .still, .alchemy)
		add(pot(.blight), 2, [(wv, 1), (m(.gunpowder), 1), (m(.venomSac), 1)], .still, .alchemy)
		add(pot(.mire), 2, [(wv, 1), (m(.gunpowder), 1), (m(.slimeGel), 2)], .still, .alchemy)
		add(pot(.enfeeble), 2, [(wv, 1), (m(.gunpowder), 1), (m(.wraithDust), 1)], .still, .alchemy)
		add(pot(.mendingSplash), 1, [(pot(.mending), 1), (m(.gunpowder), 1), (m(.sunleaf), 1)], .still, .alchemy)
		add(pot(.regrowthSplash), 1, [(pot(.regrowth), 1), (m(.gunpowder), 1)], .still, .alchemy)
		add(pot(.smoke), 2, [(wv, 1), (m(.gunpowder), 1), (m(.coal), 2)], .still, .alchemy)
		add(pot(.frost), 2, [(wv, 1), (m(.gunpowder), 1), (m(.frostCrystal), 1)], .still, .alchemy)
		add(pot(.mutagen), 1, [(wv, 1), (m(.crystalShard), 2), (m(.venomSac), 1), (m(.glowcap), 1), (m(.slimeGel), 1)], .still, .alchemy)
		add(pot(.mutagen), 1, [(wv, 1), (m(.mutantGland), 1), (m(.slimeGel), 1)], .still, .alchemy)
		// infusion compounds
		func comp(_ i: Infusion, _ cost: [(Item, Int)]) { add(.compound(i), 1, cost + [(wv, 1)], .infuser, .infusion) }
		comp(.honed, [(m(.ironBar), 1), (m(.saltpeter), 1)])
		comp(.quickened, [(m(.feather), 2), (m(.sunleaf), 2), (m(.silverBar), 1)])
		comp(.keen, [(m(.amethyst), 2), (m(.crystalShard), 1)])
		comp(.heft, [(m(.ironBar), 2), (m(.bone), 2)])
		comp(.longReach, [(m(.bronzeBar), 2), (m(.string), 3), (m(.feather), 1)])
		comp(.emberbrand, [(m(.emberAsh), 2), (m(.saltpeter), 1), (m(.goldBar), 1)])
		comp(.frostbite, [(m(.frostCrystal), 3), (m(.silverBar), 1)])
		comp(.stormcall, [(m(.stormEssence), 2), (m(.crystalShard), 2), (m(.silverBar), 2)])
		comp(.venom, [(m(.venomSac), 2), (m(.slimeGel), 1)])
		comp(.volatile, [(m(.gunpowder), 3), (m(.emberAsh), 1), (m(.saltpeter), 2)])
		comp(.voidrend, [(m(.umbralHeart), 1), (m(.voidBar), 2), (m(.sentinelLens), 1)])
		comp(.haste, [(m(.copperBar), 2), (m(.sunleaf), 2)])
		comp(.bountiful, [(m(.goldBar), 2), (m(.glowcap), 2), (m(.amethyst), 1)])
		comp(.precision, [(m(.silverBar), 1), (m(.crystalShard), 1), (m(.slimeGel), 1)])
		comp(.quarry, [(m(.golemCore), 1), (m(.diamond), 2), (m(.stormEssence), 1)])
		comp(.thrift, [(m(.golemCore), 1), (m(.copperBar), 4), (m(.crystalShard), 1)])
		comp(.reinforced, [(m(.ironBar), 2), (m(.leather), 2)])
		comp(.bulwark, [(m(.tusk), 2), (m(.ironBar), 2), (m(.fur), 1)])
		comp(.fireward, [(m(.frostCrystal), 1), (m(.slimeGel), 2), (.block(.obsidian), 1)])
		comp(.frostward, [(m(.fur), 2), (m(.coal), 2), (m(.wool), 2)])
		comp(.stormward, [(m(.stormEssence), 1), (m(.copperBar), 3), (m(.slimeGel), 1)])
		comp(.fleet, [(m(.feather), 3), (m(.sunleaf), 2), (m(.leather), 1)])
		comp(.renewal, [(m(.glowcap), 2), (m(.slimeGel), 2), (m(.crystalShard), 1), (m(.goldBar), 1)])
		comp(.barbed, [(m(.claw), 3), (m(.ironBar), 1)])
		// suits are built piece by piece from bars now: the old parts melt down into their metal
		for mt in ExoMat.allCases {
			let b: Item = mt.bar
			add(b, 2, [(.exoPart(.helmet, mt), 1)], .assembly, .exosuit)
			add(b, 4, [(.exoPart(.chestFrame, mt), 1)], .assembly, .exosuit)
			add(b, 2, [(.exoPart(.arm, mt), 1)], .assembly, .exosuit)
			add(b, 3, [(.exoPart(.legs, mt), 1)], .assembly, .exosuit)
			add(b, 2, [(.exoPart(.boots, mt), 1)], .assembly, .exosuit)
			add(b, 1, [(.exoPlate(mt), 1)], .assembly, .exosuit)
		}
		// power cores
		add(.exoCore(.sparkCell), 1, [(m(.copperBar), 4), (m(.coal), 4), (m(.ironBar), 1)], .assembly, .exosuit)
		add(.exoCore(.dynamo), 1, [(m(.ironBar), 4), (m(.copperBar), 4), (m(.goldBar), 2), (.block(.battery), 1)], .assembly, .exosuit)
		add(.exoCore(.crystal), 1, [(m(.crystalShard), 4), (m(.goldBar), 3), (.block(.accumulator), 1)], .assembly, .exosuit)
		add(.exoCore(.ember), 1, [(m(.emberBar), 4), (m(.emberAsh), 4), (m(.golemCore), 1)], .assembly, .exosuit)
		add(.exoCore(.heart), 1, [(m(.umbralHeart), 1), (m(.voidBar), 4), (m(.sentinelLens), 2)], .assembly, .exosuit)
		// modules
		add(.exoModule(.servo), 1, [(m(.ironBar), 4), (m(.copperBar), 3), (m(.string), 4)], .assembly, .exosuit)
		add(.exoModule(.drill), 1, [(m(.ironBar), 4), (.part(.drill), 1)], .assembly, .exosuit)
		add(.exoModule(.sprint), 1, [(m(.bronzeBar), 4), (m(.copperBar), 2), (m(.feather), 4)], .assembly, .exosuit)
		add(.exoModule(.leap), 1, [(m(.ironBar), 3), (m(.slimeGel), 4), (m(.copperBar), 2)], .assembly, .exosuit)
		add(.exoModule(.hover), 1, [(m(.mythrilBar), 4), (m(.stormEssence), 3), (m(.golemCore), 1)], .assembly, .exosuit)
		add(.exoModule(.lamp), 1, [(m(.copperBar), 2), (.block(.glass), 1), (.block(.torch), 2)], .assembly, .exosuit)
		add(.exoModule(.seal), 1, [(.block(.glass), 4), (m(.slimeGel), 4), (m(.frostCrystal), 2), (m(.emberAsh), 2)], .assembly, .exosuit)
		add(.exoModule(.cargo), 1, [(m(.leather), 6), (m(.ironBar), 2), (.block(.chest), 1)], .assembly, .exosuit)
		add(.exoModule(.gauntlet), 1, [(m(.copperBar), 4), (m(.silverBar), 2), (m(.stormEssence), 1)], .assembly, .exosuit)
		add(.exoModule(.barrier), 1, [(m(.crystalShard), 3), (m(.goldBar), 2), (m(.sentinelLens), 1)], .assembly, .exosuit)
		add(.exoModule(.wing), 1, [(m(.leather), 4), (m(.feather), 6), (m(.ironBar), 2)], .assembly, .exosuit)
		add(.exoModule(.battery), 1, [(m(.copperBar), 3), (.block(.battery), 1)], .assembly, .exosuit)
		add(.exoModule(.solar), 1, [(.block(.glass), 2), (m(.copperBar), 2), (m(.goldBar), 1)], .assembly, .exosuit)
		add(.exoModule(.turret), 1, [(m(.ironBar), 4), (m(.gunpowder), 2), (m(.copperBar), 2)], .assembly, .exosuit)
		add(.exoModule(.cannon), 1, [(m(.ironBar), 6), (m(.gunpowder), 4), (m(.bronzeBar), 2)], .assembly, .exosuit)
		add(.exoModule(.laser), 1, [(m(.crystalShard), 2), (m(.goldBar), 2), (m(.stormEssence), 1)], .assembly, .exosuit)
		add(.exoModule(.magnet), 1, [(m(.ironBar), 3), (m(.copperBar), 2), (m(.stormEssence), 1)], .assembly, .exosuit)
	}
}

/// The alchemy, infusion and suit items, in palette order
func featureItems() -> [Item] {
	var out: [Item] = []
	for p in Potion.allCases { out.append(.potion(p)) }
	for i in Infusion.allCases { out.append(.compound(i)) }
	for c in ExoCore.allCases { out.append(.exoCore(c)) }
	for m in ExoModule.allCases { out.append(.exoModule(m)) }
	return out
}

extension Art {
	/// A mutated creature's sprites: its own, with the colours turned a little further round the wheel
	/// for each dose (up to four steps). Built once per creature kind and step.
	func mutantSet(_ m: Mob) -> SpriteSet {
		if m.kind == .custom { return customMobSet(m.cslot, m.mphase) }
		var variant: Int = 0
		switch m.kind {
		case .zombie: variant = m.variant
		case .sheep: variant = m.sheared ? 1 : 0
		case .wolf: variant = m.tame ? 1 : 0
		default: variant = 0
		}
		let step: Int = clampI(m.mut, 1, 4)
		let key: Int = 1_000_000 + m.kind.rawValue * 256 + variant * 8 + step
		if let s = mobSets[key] { return s }
		var look: CreatureLook = creatureLook(m.kind, variant)
		let hue: Double = 12.0 * Double(step)
		look.frames = look.frames.map { recolorBuf($0, hue: hue, sat: 1.06, bright: 1.0, tint: 0x9AF04A, amt: 0.035 * Double(step)) }
		let s: SpriteSet = lookSpriteSet(look, hitH: mobDef(m.kind).h)
		mobSets[key] = s
		return s
	}
}

extension WorldRenderer {
	/// Smoke clouds (soft grey puffs that thin out as they end) and the rings of bursting potions
	static func drawPotionFX(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		for s in g.smokes {
			let a: Double = 0.55 * clampD(s.t / 1.5, 0, 1)
			for k in 0..<7 {
				let ang: Double = Double(k) * 0.898 + g.clock * 0.15
				let rr: Double = s.r * (0.35 + 0.12 * Double(k % 3))
				let px: Double = s.x + cos(ang) * rr
				let py: Double = s.y + sin(ang) * rr * 0.6
				let sz: Double = s.r * (0.75 + 0.1 * Double(k % 2))
				fillOval(&ctx, v.rect(px - sz * 0.5, py - sz * 0.4, sz, sz * 0.8), Color(hex: 0x8A8A90, alpha: a))
			}
		}
		for r in g.rings {
			let p: Double = 1.0 - r.t / 0.35
			let rad: Double = r.r * (0.3 + 0.7 * p)
			let path: Path = Path(ellipseIn: v.rect(r.x - rad, r.y - rad * 0.6, rad * 2.0, rad * 1.2))
			ctx.stroke(path, with: .color(Color(hex: r.color, alpha: 0.7 * (1.0 - p))), lineWidth: 3)
		}
	}
}

// ===== p30_infusion =====

// MARK: - Infusion: lasting properties worked into equipment

/// The kinds of equipment an infusion can go on
enum InfuseClass: Int {
	case melee, ranged, tool, armor, suit
	var name: String {
		switch self {
		case .melee: return "melee weapons"
		case .ranged: return "bows, slings and guns"
		case .tool: return "tools"
		case .armor: return "armour and suit plating"
		case .suit: return "suit cores and modules"
		}
	}
}

/// Infusions: a compound worked into a piece of equipment at an Infusion Crucible gives it one lasting
/// property. Each piece has a few slots (more for better metals), each infusion goes on it once, and
/// most bonuses are a share of what the item already does, so a good item stays better than a poor one.
/// Saved by number on the item: new kinds only go on the end.
enum Infusion: Int, Codable, CaseIterable {
	case honed, quickened, keen, heft, longReach, emberbrand, frostbite, stormcall, venom, volatile, voidrend
	case haste, bountiful, precision, quarry, thrift
	case reinforced, bulwark, fireward, frostward, stormward, fleet, renewal, barbed

	var name: String {
		switch self {
		case .honed: return "Honed"
		case .quickened: return "Quickened"
		case .keen: return "Keen"
		case .heft: return "Heft"
		case .longReach: return "Long Reach"
		case .emberbrand: return "Emberbrand"
		case .frostbite: return "Frostbite"
		case .stormcall: return "Stormcall"
		case .venom: return "Venom"
		case .volatile: return "Volatile"
		case .voidrend: return "Voidrend"
		case .haste: return "Haste"
		case .bountiful: return "Bountiful"
		case .precision: return "Precision"
		case .quarry: return "Quarry"
		case .thrift: return "Thrift"
		case .reinforced: return "Reinforced"
		case .bulwark: return "Bulwark"
		case .fireward: return "Fireward"
		case .frostward: return "Frostward"
		case .stormward: return "Stormward"
		case .fleet: return "Fleet"
		case .renewal: return "Renewal"
		case .barbed: return "Barbed"
		}
	}

	var rarity: Rarity {
		switch self {
		case .honed, .heft, .haste, .reinforced: return .basic
		case .quickened, .keen, .longReach, .venom, .bountiful, .precision, .bulwark, .fireward, .frostward, .fleet, .barbed: return .uncommon
		case .emberbrand, .frostbite, .volatile, .thrift, .stormward, .renewal: return .rare
		case .stormcall, .quarry: return .veryRare
		case .voidrend: return .legendary
		}
	}

	/// what it can go on
	var classes: [InfuseClass] {
		switch self {
		case .honed, .longReach, .emberbrand, .frostbite, .voidrend: return [.melee, .ranged]
		case .quickened: return [.melee, .ranged]
		case .keen, .heft, .stormcall, .venom: return [.melee]
		case .volatile: return [.ranged]
		case .haste, .bountiful, .precision, .quarry: return [.tool]
		case .thrift: return [.suit]
		case .reinforced, .bulwark, .fireward, .frostward, .stormward, .fleet, .renewal, .barbed: return [.armor]
		}
	}

	/// what it does, in a line
	var blurb: String {
		switch self {
		case .honed: return "+20% damage"
		case .quickened: return "Attacks and shots come 15% sooner"
		case .keen: return "+12% chance of a critical blow"
		case .heft: return "Blows knock foes 60% further"
		case .longReach: return "Melee reaches 0.6 further; shots fly 25% further"
		case .emberbrand: return "Sets what it hits alight for 3 s"
		case .frostbite: return "What it hits moves 40% slower for 3 s"
		case .stormcall: return "One blow in five sends a spark leaping to 2 more foes"
		case .venom: return "Poisons what it hits: 1 a second for 4 s"
		case .volatile: return "Shots burst on impact (3 damage around, no blocks broken)"
		case .voidrend: return "+15% damage, and 35% more against bosses and Umbral creatures"
		case .haste: return "Mines 25% faster"
		case .bountiful: return "A 20% chance of one extra ore, gem or crystal"
		case .precision: return "Glass, ice, crystal, leaves and grass come away whole"
		case .quarry: return "Also breaks the blocks above and below (diamond tools and better)"
		case .thrift: return "Powered suit parts use 25% less energy"
		case .reinforced: return "+1 defence"
		case .bulwark: return "Less knockback; heavy blows hurt 15% less"
		case .fireward: return "Fire and lava hurt 20% less (each piece)"
		case .frostward: return "The cold gets in 25% slower (each piece)"
		case .stormward: return "Lightning and hail hurt 30% less (each piece)"
		case .fleet: return "Run 4% faster (each piece)"
		case .renewal: return "Slowly heals you (each piece adds a little)"
		case .barbed: return "Foes that strike you take 15% of the blow back (each piece)"
		}
	}

	/// colour of its compound and of its mark on an item
	var color: UInt32 {
		switch self {
		case .honed: return 0xE0E4EC
		case .quickened: return 0x7AD8F8
		case .keen: return 0xC07CFF
		case .heft: return 0xA88A5A
		case .longReach: return 0x8AC8E8
		case .emberbrand: return 0xFF7A2A
		case .frostbite: return 0xA8E8FF
		case .stormcall: return 0xFFF07A
		case .venom: return 0x7AD040
		case .volatile: return 0xFF5A3A
		case .voidrend: return 0xB04CFF
		case .haste: return 0xE8B83A
		case .bountiful: return 0x5AE070
		case .precision: return 0xE8F4FF
		case .quarry: return 0xC8A070
		case .thrift: return 0x60E0C8
		case .reinforced: return 0xB8C0CC
		case .bulwark: return 0x8A9AB8
		case .fireward: return 0xFF9A4A
		case .frostward: return 0x9AD8FF
		case .stormward: return 0xE8E87A
		case .fleet: return 0x9AF0D0
		case .renewal: return 0xF07AB8
		case .barbed: return 0xC86A5A
		}
	}
}

/// How many infusions a piece of equipment holds: more for better metals and rarer finds (0: none)
func infusionSlots(_ it: Item) -> Int {
	func byTier(_ t: Tier) -> Int {
		switch t {
		case .wood, .stone, .copper: return 1
		case .iron, .gold, .diamond: return 2
		case .mythril, .ember, .voidium: return 3
		}
	}
	switch it {
	case .sword(let t), .spear(let t), .hammer(let t), .knife(let t): return byTier(t)
	case .tool(_, let t): return byTier(t)
	case .armor(_, let t): return byTier(t)
	case .club, .sling: return 1
	case .bow: return 2
	case .relic: return 3
	case .gun(let g):
		switch g {
		case .pistol, .crossbow, .blunderbuss: return 1
		case .rifle, .arbalest, .repeater, .stormRod: return 2
		}
	case .exoPart(_, let m): return m.slots
	case .exoPlate(let m): return max(1, m.slots - 1)
	case .exoCore, .exoModule: return 1
	case .custom(let k):
		guard let r = ModRuntime.shared.item(k) else { return 0 }
		return (r.def.kind.isWeapon || r.def.kind == .tool || r.def.kind == .armor) ? 1 : 0
	default: return 0
	}
}

/// The kinds of equipment an item counts as, for infusing
func infuseClasses(_ it: Item) -> [InfuseClass] {
	switch it {
	case .sword, .spear, .hammer, .knife, .club, .relic: return [.melee]
	case .bow, .sling: return [.ranged]
	case .gun: return [.ranged]
	case .tool: return [.tool]
	case .armor, .exoPart, .exoPlate: return [.armor]
	case .exoCore, .exoModule: return [.suit]
	case .custom(let k):
		guard let r = ModRuntime.shared.item(k) else { return [] }
		switch r.def.kind {
		case .melee: return [.melee]
		case .bow, .gun, .thrown, .magic: return [.ranged]
		case .tool: return [.tool]
		case .armor: return [.armor]
		default: return []
		}
	default: return []
	}
}

extension Stack {
	/// the infusions worked into this item
	var infusions: [Infusion] {
		guard let l = inf else { return [] }
		var out: [Infusion] = []
		for r in l { if let i = Infusion(rawValue: r) { out.append(i) } }
		return out
	}

	func has(_ i: Infusion) -> Bool { return inf?.contains(i.rawValue) ?? false }

	/// Why an infusion cannot go on this item (nil: it can)
	func infuseProblem(_ i: Infusion) -> String? {
		let slots: Int = infusionSlots(item)
		if slots <= 0 { return "This can't be infused." }
		let cls: [InfuseClass] = infuseClasses(item)
		if !i.classes.contains(where: { cls.contains($0) }) {
			let names: [String] = i.classes.map { $0.name }
			return joinText(i.name, " only goes on ", names.joined(separator: " or "), ".")
		}
		if has(i) { return joinText("It already has ", i.name, ".") }
		if (inf?.count ?? 0) >= slots { return joinText("All ", String(slots), " of its slots are taken.") }
		if i == .quarry {
			var ok: Bool = false
			if case .tool(let k, let t) = item, (k == .pickaxe || k == .shovel), t.rawValue >= Tier.diamond.rawValue { ok = true }
			if !ok { return "Quarry needs a diamond (or better) pickaxe or shovel." }
		}
		if i == .volatile, case .gun(let g) = item, g == .stormRod { return "The storm rod's lightning can't carry it." }
		if i == .longReach, case .gun(let g) = item, g == .stormRod { return "The storm rod's lightning can't carry it." }
		return nil
	}
}

/// Armour infusions summed over everything worn (worked out again only when what is worn changes)
struct ArmorInf {
	var defense: Double = 0
	var knockMul: Double = 1
	var heavyCut: Double = 0
	var fireCut: Double = 0
	var coldCut: Double = 0
	var stormCut: Double = 0
	var speed: Double = 0
	var regen: Double = 0
	var thorns: Double = 0

	mutating func add(_ s: Stack) {
		for n in s.inf ?? [] where n >= customInfusionBase { addCustom(n) }
		for i in s.infusions {
			switch i {
			case .reinforced: defense += 1.0
			case .bulwark:
				knockMul *= 0.75
				heavyCut = min(0.4, heavyCut + 0.15)
			case .fireward: fireCut = min(0.6, fireCut + 0.2)
			case .frostward: coldCut = min(0.75, coldCut + 0.25)
			case .stormward: stormCut = min(0.75, stormCut + 0.3)
			case .fleet: speed = min(0.2, speed + 0.04)
			case .renewal: regen = min(0.35, regen + 0.1)
			case .barbed: thorns = min(0.45, thorns + 0.15)
			default: break
			}
		}
	}
}

extension Game {
	// MARK: infusing

	/// Works a compound into the item in a bag slot. Everything is checked again here (the panel may be
	/// out of date): the item must still be there, the infusion must fit, and a compound must be in the
	/// bag. The item itself never leaves its slot, so nothing can be lost on the way. Returns what to say.
	@discardableResult
	func infuse(slot i: Int, _ inf: Infusion) -> String {
		guard i >= 0 && i < inv.slots.count, var s = inv.slots[i] else { return "That item is gone." }
		if let why = s.infuseProblem(inf) { return why }
		if !isCreative && inv.total(.compound(inf)) < 1 { return joinText("You need a ", inf.name, " compound.") }
		if !isCreative { _ = inv.remove(.compound(inf), 1) }
		var list: [Int] = s.inf ?? []
		list.append(inf.rawValue)
		s.inf = list
		inv.slots[i] = s
		sfx(.infuse, 0.8)
		spawnParticles(pb.x, pb.y - 1.2, inf.color, 12, 3.0, 0.7, -4)
		if !journal.crafted.contains(joinText("Infusion: ", inf.name)) { journal.crafted.append(joinText("Infusion: ", inf.name)) }
		bumpHUD()
		return joinText(s.item.name, " is now ", inf.name, ".")
	}

	/// Takes an infusion back out of an item (the compound is spent; the item is unharmed)
	@discardableResult
	func removeInfusion(slot i: Int, _ inf: Infusion) -> String {
		guard i >= 0 && i < inv.slots.count, var s = inv.slots[i], s.has(inf) else { return "Nothing to remove." }
		var list: [Int] = s.inf ?? []
		list.removeAll { $0 == inf.rawValue }
		s.inf = list.isEmpty ? nil : list
		inv.slots[i] = s
		sfx(.tap, 0.6)
		bumpHUD()
		return joinText(inf.name, " was drawn out of ", s.item.name, ".")
	}

	/// The infusions of the item in hand, if it is the given item (nil: none)
	func heldInfusions(_ it: Item?) -> [Int] {
		guard let i = it, let s = inv.slots[sel], s.item == i, let l = s.inf else { return [] }
		return l
	}

	/// The melee profile of an item as the player swings it: its own, changed by its infusions
	func infusedMelee(_ it: Item?) -> MeleeProfile {
		var p: MeleeProfile = it?.melee ?? Item.bareHands
		let l: [Int] = heldInfusions(it)
		if !l.isEmpty { p = Game.infuseProfile(p, l) }
		if suitWorn { p = suitMelee(p) }
		return p
	}

	static func infuseProfile(_ p0: MeleeProfile, _ l: [Int]) -> MeleeProfile {
		var p: MeleeProfile = p0
		for r in l {
			guard let i = Infusion(rawValue: r) else {
				p = Game.customProfile(p, r)
				continue
			}
			switch i {
			case .honed: p.damage *= 1.2
			case .quickened: p.cooldown *= 0.85
			case .keen: p.critChance += 0.12
			case .heft: p.knock *= 1.6
			case .longReach: p.reach += 0.6
			case .voidrend: p.damage *= 1.15
			case .emberbrand: p.burn = max(p.burn, 3.0)
			default: break
			}
		}
		return p
	}

	/// After a melee blow lands: frost, poison, voidrend's extra bite and stormcall's spark
	func meleeInfusionHit(_ m: Mob, _ l: [Int], _ dmg: Double) {
		if l.isEmpty { return }
		for r in l {
			guard let i = Infusion(rawValue: r) else {
				customHit(m, r, dmg, m.b.x, m.b.cy)
				continue
			}
			if m.hp <= 0 { continue }
			switch i {
			case .frostbite:
				m.slowT = max(m.slowT, m.isBoss ? 1.5 : 3.0)
				m.slowAmt = max(m.slowAmt, m.isBoss ? 0.2 : 0.4)
			case .venom:
				if !poisonImmune(m) {
					m.poisonT = max(m.poisonT, m.isBoss ? 2.0 : 4.0)
					m.poisonDps = max(m.poisonDps, 1.0)
					m.poisonByPlayer = true
				}
			case .voidrend:
				if m.isBoss || faction(of: m) == .umbral {
					var info = DamageInfo(amount: dmg * 0.2, type: .magic, source: .player)
					info.originX = pb.x
					applyMobDamage(m, info)
				}
			case .stormcall:
				if Double.random(in: 0...1) < 0.2 { stormSpark(m) }
			default: break
			}
		}
	}

	/// A spark leaps from a struck foe to up to two more close by
	func stormSpark(_ from: Mob) {
		var hit: [Mob] = []
		var prev: Mob = from
		for _ in 0..<2 {
			var best: Mob? = nil
			var bd: Double = 6.0
			for m in mobsNear(prev.b.x - 7, prev.b.x + 7) where m !== from && !hit.contains(where: { $0 === m }) {
				if m.hp <= 0 || m.removed || m.tame { continue }
				let d: Double = abs(m.b.x - prev.b.x) + abs(m.b.cy - prev.b.cy)
				if d < bd { bd = d; best = m }
			}
			guard let n = best else { break }
			arcs.append(ArcFX(pts: [(prev.b.x, prev.b.cy), ((prev.b.x + n.b.x) * 0.5, min(prev.b.cy, n.b.cy) - 0.6), (n.b.x, n.b.cy)], life: 0.2))
			var info = DamageInfo(amount: 5, type: .shock, source: .player)
			info.originX = prev.b.x
			info.key = newID()
			applyMobDamage(n, info)
			hit.append(n)
			prev = n
		}
		if !hit.isEmpty { sfx(.zap, at: from.b.x, 0.5) }
	}

	/// Infusions on the weapon that fires a shot: damage, range, and what it does when it lands
	func infuseShot(_ p: inout Projectile, _ it: Item?) {
		let l: [Int] = heldInfusions(it)
		if l.isEmpty { return }
		var bits: Int = 0
		for r in l {
			guard let i = Infusion(rawValue: r) else { continue }
			switch i {
			case .honed: p.dmg *= 1.2
			case .voidrend: p.dmg *= 1.15; bits |= 8
			case .longReach: p.life *= 1.25
			case .emberbrand: bits |= 1
			case .frostbite: bits |= 2
			case .volatile: bits |= 4
			default: break
			}
		}
		p.inf = bits
		customShot(&p, l)
	}

	/// A shot with infusions lands on a creature
	func shotInfusionHit(_ p: Projectile, _ m: Mob?, _ x: Double, _ y: Double) {
		if let mm = m { for n in p.custom { customHit(mm, n, p.dmg, x, y) } }
		if let mm = m, mm.hp > 0 {
			if p.inf & 1 != 0 && !heatImmune(mm) { mm.burn = max(mm.burn, 3.0) }
			if p.inf & 2 != 0 {
				mm.slowT = max(mm.slowT, mm.isBoss ? 1.5 : 3.0)
				mm.slowAmt = max(mm.slowAmt, mm.isBoss ? 0.2 : 0.4)
			}
			if p.inf & 8 != 0 && (mm.isBoss || faction(of: mm) == .umbral) {
				var info = DamageInfo(amount: p.dmg * 0.2, type: .magic, source: .player)
				info.originX = x
				applyMobDamage(mm, info)
			}
		}
		if p.inf & 4 != 0 { volatileBurst(x, y) }
	}

	/// A volatile shot's little blast: hurts what is close, breaks nothing
	func volatileBurst(_ x: Double, _ y: Double) {
		var info = DamageInfo(amount: 3, type: .explosion, source: .player)
		info.knock = 4
		info.key = newID()
		info.cooldown = 0.5
		for m in mobsNear(x - 2.5, x + 2.5) where m.hp > 0 && !m.removed && !m.tame {
			let d: Double = boxDistance(x, y, m.b.left, m.b.top, m.b.right, m.b.y)
			if d <= 1.3 {
				var i2: DamageInfo = info
				i2.originX = x
				i2.originY = y
				applyMobDamage(m, i2)
			}
		}
		spawnParticles(x, y, 0xFF8A3A, 8, 4.0, 0.3, 4)
		sfx(.flask, at: x, 0.35)
	}

	// MARK: mining with infusions

	/// How much faster than usual the player mines right now: potions, the tool's Haste, the suit's drill
	func mineBoost(_ kind: ToolType?) -> Double {
		var b: Double = 1.0 + effects.value(.mining) / 100.0
		if kind != nil, let s = inv.slots[sel], s.has(.haste) { b *= 1.25 }
		if kind != nil, let s = inv.slots[sel] { b *= customMining(s) }
		return b
	}

	/// What breaking a block gives: its usual drops, ingredients from plants and ice, whole blocks with
	/// Precision, and now and then one extra ore or gem (Bountiful, a Seeker's Tonic)
	func minedDrops(_ t: Tile, _ x: Int, _ y: Int, _ byPlayer: Bool) -> [Stack] {
		let held: Stack? = byPlayer ? inv.slots[sel] : nil
		var tool: Bool = false
		if let h = held, case .tool = h.item { tool = true }
		if tool, let h = held, h.has(.precision), precisionKeeps(t) {
			return [Stack(item: .block(t == .grass ? .grass : t), count: 1)]
		}
		var out: [Stack] = tileDropStacks(t, x, y)
		if !byPlayer { return out }
		let r: Double = Double.random(in: 0...1)
		switch t {
		case .tallGrass: if r < 0.1 { out.append(Stack(item: .mat(.sunleaf), count: 1)) }
		case .flowerR, .flowerY: if r < 0.35 { out.append(Stack(item: .mat(.sunleaf), count: 1)) }
		case .mushroom: if r < 0.3 { out.append(Stack(item: .mat(.glowcap), count: 1)) }
		case .ice: if r < 0.15 { out.append(Stack(item: .mat(.frostCrystal), count: 1)) }
		case .snow: if r < 0.03 { out.append(Stack(item: .mat(.frostCrystal), count: 1)) }
		default: break
		}
		if isOreTile(t), let first = out.first {
			var p: Double = effects.value(.luck) / 100.0
			if tool, let h = held, h.has(.bountiful) { p += 0.2 }
			if p > 0 && Double.random(in: 0...1) < min(0.5, p) {
				out.append(Stack(item: first.item, count: 1))
				floatText("+1", Double(x) + 0.5, Double(y) - 0.2, 0x5AE070)
			}
		}
		return out
	}

	/// Blocks that Precision lifts whole
	func precisionKeeps(_ t: Tile) -> Bool {
		switch t {
		case .glass, .ice, .glowCrystal, .grass, .leaves, .jungleLeaves, .birchLeaves, .pineLeaves, .snow: return true
		default: return false
		}
	}

	/// After a block breaks under a Quarry tool: the blocks right above and below go too, if they are
	/// no harder and the tool could mine them anyway
	func quarryAround(_ x: Int, _ y: Int, _ t0: Tile, _ kind: ToolType, _ tier: Tier) {
		guard let s = inv.slots[sel], s.has(.quarry) else { return }
		for dy in [-1, 1] {
			let t: Tile = world.tile(x, y + dy)
			if t == .air || t.liquid || t == .bedrock || t == .chest || t.isPower || t.hardness >= 99 { continue }
			if t.hardness > t0.hardness + 0.01 { continue }
			if toolClass(t) != kind || t.def.tier > tier.rawValue { continue }
			if t == .portalFrame || t == .portalOff || t == .portalOn { continue }
			breakTile(x, y + dy, true)
		}
	}

	// MARK: armour infusions

	/// Armour infusions over everything worn (rebuilt only when what is worn changes)
	var armorInf: ArmorInf {
		var h: Hasher = Hasher()
		for i in 0..<min(3, inv.armor.count) { h.combine(inv.armor[i]) }
		h.combine(suitRev)
		h.combine(suit.worn)
		let k: Int = h.finalize()
		if k == armorInfKey { return armorInfCache }
		var a: ArmorInf = ArmorInf()
		for i in 0..<min(3, inv.armor.count) { if let s = inv.armor[i] { a.add(s) } }
		if suit.worn {
			for s in suit.d.items.values { a.add(s) }
		}
		armorInfCache = a
		armorInfKey = k
		return a
	}

	/// Everything that guards the player: armour, its Reinforced infusions and a worn suit
	var totalDefense: Double {
		// (a suit guards by its plates where each blow lands: see suitGuard)
		return inv.defense + armorInf.defense
	}
}

/// The ores, gems and crystals a Bountiful tool or a Seeker's Tonic can turn up more of
func isOreTile(_ t: Tile) -> Bool {
	switch t {
	case .coal, .copper, .iron, .gold, .diamond, .mythril, .emberOre, .voidOre, .crystalOre, .tin, .saltpeter, .silver, .amethyst, .glowCrystal: return true
	default: return false
	}
}

// ===== p31_exosuit =====

// MARK: - The modular exosuit: parts, materials, cores and modules

/// The metals a suit part is made from. Iron is easy to come by and even; heavier metals guard better
/// but slow the wearer; gold carries energy well; rare metals are light or strong; the Umbral metals
/// shrug off fire, cold and lightning and give room for the most modules. Saved by number.
enum ExoMat: Int, Codable, CaseIterable {
	case iron, bronze, gold, diamond, mythril, ember, voidium

	var name: String {
		switch self {
		case .iron: return "Iron"
		case .bronze: return "Bronze"
		case .gold: return "Gilded"
		case .diamond: return "Diamond"
		case .mythril: return "Mythril"
		case .ember: return "Ember"
		case .voidium: return "Voidium"
		}
	}
	/// how much a part of this metal guards (iron 1)
	var protect: Double {
		switch self {
		case .iron: return 1.0
		case .bronze: return 0.85
		case .gold: return 0.7
		case .diamond: return 1.6
		case .mythril: return 1.5
		case .ember: return 1.8
		case .voidium: return 2.2
		}
	}
	/// how heavy a part of this metal is (iron 1)
	var weight: Double {
		switch self {
		case .iron: return 1.0
		case .bronze: return 0.85
		case .gold: return 1.2
		case .diamond: return 1.35
		case .mythril: return 0.7
		case .ember: return 1.5
		case .voidium: return 1.2
		}
	}
	/// how well it carries energy: powered parts use less in a suit of good conductors (iron 1)
	var conduct: Double {
		switch self {
		case .iron: return 1.0
		case .bronze: return 1.1
		case .gold: return 1.5
		case .diamond: return 0.9
		case .mythril: return 1.2
		case .ember: return 1.0
		case .voidium: return 1.3
		}
	}
	/// module sockets a chest frame of this metal has
	var sockets: Int {
		switch self {
		case .iron, .bronze, .gold: return 2
		case .diamond, .mythril, .ember: return 3
		case .voidium: return 4
		}
	}
	/// infusion slots on a part of this metal
	var slots: Int {
		switch self {
		case .iron, .bronze: return 1
		case .gold, .diamond: return 2
		case .mythril, .ember, .voidium: return 3
		}
	}
	/// the mining tier a drill arm of this metal bores at (pickaxe tiers)
	var drillTier: Int {
		switch self {
		case .bronze: return 3
		case .iron: return 4
		case .gold: return 5
		case .diamond: return 6
		case .mythril: return 7
		case .ember: return 8
		case .voidium: return 9
		}
	}
	var color: UInt32 {
		switch self {
		case .iron: return 0xC8CCD4
		case .bronze: return 0xC89040
		case .gold: return 0xF0C840
		case .diamond: return 0x5ADCE4
		case .mythril: return 0x8A7CFF
		case .ember: return 0xE8642A
		case .voidium: return 0x9A4CE8
		}
	}
	var rarity: Rarity {
		switch self {
		case .iron, .bronze: return .basic
		case .gold: return .uncommon
		case .diamond: return .rare
		case .mythril, .ember: return .veryRare
		case .voidium: return .legendary
		}
	}
	/// the metal a part is made of, for its recipe
	var bar: Item {
		switch self {
		case .iron: return .mat(.ironBar)
		case .bronze: return .mat(.bronzeBar)
		case .gold: return .mat(.goldBar)
		case .diamond: return .mat(.diamond)
		case .mythril: return .mat(.mythrilBar)
		case .ember: return .mat(.emberBar)
		case .voidium: return .mat(.voidBar)
		}
	}
	/// what it adds besides guarding
	var special: String {
		switch self {
		case .iron: return "Even and easy to make"
		case .bronze: return "Light and cheap, guards a little less"
		case .gold: return "Carries energy well: powered parts use less"
		case .diamond: return "Guards very well, but heavy"
		case .mythril: return "Strong and very light"
		case .ember: return "Turns fire and lava (each part)"
		case .voidium: return "Turns cold and lightning; room for 4 modules"
		}
	}
}

/// The frame parts of a suit
enum ExoPart: Int, Codable, CaseIterable {
	case helmet, chestFrame, arm, legs, boots
	var name: String {
		switch self {
		case .helmet: return "Suit Helmet"
		case .chestFrame: return "Chest Frame"
		case .arm: return "Suit Arm"
		case .legs: return "Suit Legs"
		case .boots: return "Suit Boots"
		}
	}
	var baseDefense: Double {
		switch self {
		case .helmet: return 0.9
		case .chestFrame: return 1.6
		case .arm: return 0.5
		case .legs: return 1.1
		case .boots: return 0.6
		}
	}
	var baseWeight: Double {
		switch self {
		case .helmet: return 3
		case .chestFrame: return 8
		case .arm: return 3
		case .legs: return 6
		case .boots: return 3
		}
	}
}

/// Power cores: how much energy they hold, how much they can give at once, and how fast they refill
enum ExoCore: Int, Codable, CaseIterable {
	case sparkCell, dynamo, crystal, ember, heart
	var name: String {
		switch self {
		case .sparkCell: return "Spark Cell"
		case .dynamo: return "Dynamo Core"
		case .crystal: return "Crystal Core"
		case .ember: return "Ember Core"
		case .heart: return "Heart Core"
		}
	}
	var capacity: Double {
		switch self {
		case .sparkCell: return 120
		case .dynamo: return 240
		case .crystal: return 400
		case .ember: return 600
		case .heart: return 1000
		}
	}
	/// the most energy a second it can give
	var output: Double {
		switch self {
		case .sparkCell: return 6
		case .dynamo: return 10
		case .crystal: return 14
		case .ember: return 20
		case .heart: return 30
		}
	}
	/// energy a second it makes by itself
	var recharge: Double {
		switch self {
		case .sparkCell: return 0.5
		case .dynamo: return 1.0
		case .crystal: return 1.6
		case .ember: return 2.4
		case .heart: return 4.0
		}
	}
	var color: UInt32 {
		switch self {
		case .sparkCell: return 0xFFC830
		case .dynamo: return 0x60E0FF
		case .crystal: return 0x8AF0E8
		case .ember: return 0xFF7A2A
		case .heart: return 0xD860FF
		}
	}
	var rarity: Rarity {
		switch self {
		case .sparkCell: return .basic
		case .dynamo: return .uncommon
		case .crystal: return .rare
		case .ember: return .veryRare
		case .heart: return .legendary
		}
	}
}

/// Suit modules: each does one thing, costs energy to run, and needs certain parts to hold it
enum ExoModule: Int, Codable, CaseIterable {
	case servo, drill, sprint, leap, hover, lamp, seal, cargo, gauntlet, barrier
	/// appended: wings, batteries, solar panels, turrets, cannons, lasers and a magnet
	case wing, battery, solar, turret, cannon, laser, magnet
	var name: String {
		switch self {
		case .servo: return "Servo Muscles"
		case .drill: return "Drill"
		case .sprint: return "Booster"
		case .leap: return "Leap Piston"
		case .hover: return "Jet"
		case .lamp: return "Suit Lamp"
		case .seal: return "Environment Seal"
		case .cargo: return "Cargo Pack"
		case .gauntlet: return "Shock Gauntlet"
		case .barrier: return "Barrier Projector"
		case .wing: return "Suit Wing"
		case .battery: return "Suit Battery"
		case .solar: return "Solar Panel"
		case .turret: return "Mini Turret"
		case .cannon: return "Mini Cannon"
		case .laser: return "Mini Laser"
		case .magnet: return "Magnet"
		}
	}
	var blurb: String {
		switch self {
		case .servo: return "Each carries 12 more weight and hits harder (a little energy each swing)"
		case .drill: return "On an arm: mine with any hand, faster, at the drill's metal tier (energy while mining)"
		case .sprint: return "Run faster: each booster adds speed (energy while running)"
		case .leap: return "Jump higher: each piston adds height (energy each jump)"
		case .hover: return "Hold jump in the air: jets push the way they point. Enough lift for the suit's weight and it flies (energy while firing)"
		case .lamp: return "Lights the way in the dark (a trickle of energy)"
		case .seal: return "Fire, lava, cold, water and lightning hurt far less (energy while it works)"
		case .cargo: return "A chest on your back: 27 stacks that go where you go (PACK button)"
		case .gauntlet: return "Melee blows add a shock (energy each hit)"
		case .barrier: return "Turns part of each hit into energy drain instead of harm"
		case .wing: return "Hold jump while falling to glide; more wing, slower fall"
		case .battery: return "Holds more energy (charged by cores, panels and stations)"
		case .solar: return "Makes energy under the open sky by day"
		case .turret: return "Shoots the nearest foe by itself (energy each shot)"
		case .cannon: return "Fires a shell at your aim while SUIT FIRE is held (energy each shot)"
		case .laser: return "A beam at your aim while SUIT FIRE is held (energy while firing)"
		case .magnet: return "Draws dropped things to you"
		}
	}
	var weight: Double {
		switch self {
		case .drill, .cannon: return 4
		case .hover, .cargo, .turret: return 3
		case .solar, .magnet, .lamp: return 1
		default: return 2
		}
	}
	var rarity: Rarity {
		switch self {
		case .lamp, .cargo, .battery, .wing: return .basic
		case .servo, .drill, .sprint, .leap, .solar, .magnet: return .uncommon
		case .seal, .gauntlet, .turret: return .rare
		case .hover, .barrier, .cannon, .laser: return .veryRare
		}
	}
	var color: UInt32 {
		switch self {
		case .servo: return 0xA8B0C0
		case .drill: return 0xD8D8E0
		case .sprint: return 0x7AD8F8
		case .leap: return 0x8AE85A
		case .hover: return 0xFF9A3A
		case .lamp: return 0xFFF0A0
		case .seal: return 0x60C8E8
		case .cargo: return 0x9A6A3A
		case .gauntlet: return 0xFFF07A
		case .barrier: return 0xC07CFF
		case .wing: return 0xD8D0C0
		case .battery: return 0x6ADA5A
		case .solar: return 0x3A5AB0
		case .turret: return 0x8A929E
		case .cannon: return 0x5A606A
		case .laser: return 0xE84A6A
		case .magnet: return 0xC8384A
		}
	}
}

/// The places on a suit. Frame parts first, then the core, the armour plates, and module sockets.
enum ExoSlot: Int, Codable, CaseIterable {
	case helmet, chest, armL, armR, legs, boots, core, plateHead, plateShoulders, plateChest, plateArms, plateLegs, mod1, mod2, mod3, mod4

	var name: String {
		switch self {
		case .helmet: return "Helmet"
		case .chest: return "Chest frame"
		case .armL: return "Left arm"
		case .armR: return "Right arm"
		case .legs: return "Legs"
		case .boots: return "Boots"
		case .core: return "Power core"
		case .plateHead: return "Helmet plate"
		case .plateShoulders: return "Shoulder plates"
		case .plateChest: return "Chest plate"
		case .plateArms: return "Arm plates"
		case .plateLegs: return "Leg plates"
		case .mod1: return "Module 1"
		case .mod2: return "Module 2"
		case .mod3: return "Module 3"
		case .mod4: return "Module 4"
		}
	}
	var isPlate: Bool { return rawValue >= ExoSlot.plateHead.rawValue && rawValue <= ExoSlot.plateLegs.rawValue }
	var isModule: Bool { return rawValue >= ExoSlot.mod1.rawValue }
	/// the frame part a plate is fixed to
	var plateBase: ExoSlot? {
		switch self {
		case .plateHead: return .helmet
		case .plateShoulders, .plateChest: return .chest
		case .plateArms: return .armL
		case .plateLegs: return .legs
		default: return nil
		}
	}
	/// how much a plate here guards (before its metal)
	var plateDefense: Double {
		switch self {
		case .plateHead: return 0.5
		case .plateShoulders: return 0.6
		case .plateChest: return 0.9
		case .plateArms: return 0.5
		case .plateLegs: return 0.6
		default: return 0
		}
	}
	/// what kind of part fits here
	func fits(_ it: Item) -> Bool {
		switch it {
		case .exoPart(let p, _):
			switch p {
			case .helmet: return self == .helmet
			case .chestFrame: return self == .chest
			case .arm: return self == .armL || self == .armR
			case .legs: return self == .legs
			case .boots: return self == .boots
			}
		case .exoPlate: return isPlate
		case .exoCore: return self == .core
		case .exoModule: return isModule
		default: return false
		}
	}
}

/// A suit: built piece by piece (its design: every plate and working part, each with its own damage),
/// whether it is being worn, and the energy in it. `parts` is how a suit was built before (one part in
/// each place): it is read from old saves and rebuilt piece by piece (see migrate).
struct ExoSuit: Codable, Equatable {
	var parts: [Int: Stack] = [:]
	var worn: Bool = false
	var energy: Double = 0
	/// the module switches the player has turned off (by module number)
	var off: [Int]? = nil
	/// the suit as built piece by piece (nil only in a save from before)
	var design: SuitDesign? = nil

	init() {}

	/// the design (empty when there is none yet)
	var d: SuitDesign {
		get { return design ?? SuitDesign() }
		set { design = newValue }
	}

	var isEmpty: Bool { return parts.isEmpty && (design?.pieces.isEmpty ?? true) }

	subscript(_ s: ExoSlot) -> Stack? {
		get { return parts[s.rawValue] }
		set { parts[s.rawValue] = newValue }
	}

	/// the metal of an old-style part
	func material(_ s: ExoSlot) -> ExoMat? {
		if let st = parts[s.rawValue] {
			if case .exoPart(_, let m) = st.item { return m }
			if case .exoPlate(let m) = st.item { return m }
		}
		return nil
	}
}

// MARK: - Suits built piece by piece

/// Who a suit's cannon shell belongs to: a small blast that never breaks blocks (see shellBurst)
let suitShellOwner: Int = 3_000_000

/// Suit units to a sprite pixel: pieces sit on a grid three times finer than the sprite's
let suitUnit: Int = 3
/// The body's design space in suit units: the figure is 30 wide (10 pixels) and 51 tall (17 rows of
/// its frame, feet on row 15); pieces may hang 18 units off either side (wings, a pack, a cannon)
let suitBodyW: Double = 30
let suitBodyH: Double = 51
let suitMargin: Double = 18

/// Where a piece is fixed: it moves with that part of the body (the legs stride, the front arm swings
/// out to strike and shoot). Drawn back to front in `layer` order.
enum SuitBone: Int, Codable, CaseIterable {
	case head, torso, armBack, armFront, legBack, legFront, back
	var name: String {
		switch self {
		case .head: return "Head"
		case .torso: return "Body"
		case .armBack: return "Back arm"
		case .armFront: return "Front arm"
		case .legBack: return "Back leg"
		case .legFront: return "Front leg"
		case .back: return "Back"
		}
	}
	var layer: Int {
		switch self {
		case .back: return 0
		case .armBack: return 1
		case .legBack: return 2
		case .torso: return 3
		case .head: return 4
		case .legFront: return 5
		case .armFront: return 6
		}
	}
	/// the same place on the other side (for mirrored copies)
	var other: SuitBone {
		switch self {
		case .armBack: return .armFront
		case .armFront: return .armBack
		case .legBack: return .legFront
		case .legFront: return .legBack
		default: return self
		}
	}
}

/// The body's parts for guarding: a blow lands on one of them
enum SuitSection: Int, CaseIterable {
	case head, torso, arms, legs, feet
	var name: String {
		switch self {
		case .head: return "Head"
		case .torso: return "Body"
		case .arms: return "Arms"
		case .legs: return "Legs"
		case .feet: return "Feet"
		}
	}
}

/// The outline of a piece
enum SuitShape: Int, Codable, CaseIterable {
	case box, rounded, round, wedge, spike
	var name: String {
		switch self {
		case .box: return "Box"
		case .rounded: return "Rounded"
		case .round: return "Round"
		case .wedge: return "Wedge"
		case .spike: return "Spike"
		}
	}
	/// how much of its box it fills
	var fill: Double {
		switch self {
		case .box: return 1.0
		case .rounded: return 0.92
		case .round: return 0.785
		case .wedge, .spike: return 0.5
		}
	}
	/// whether a point of the piece's box (each from -1 to 1 across and down) is on it
	func inside(_ u: Double, _ v: Double) -> Bool {
		if abs(u) > 1.0 || abs(v) > 1.0 { return false }
		switch self {
		case .box: return true
		case .rounded:
			let a: Double = abs(u) - 0.55
			let b: Double = abs(v) - 0.55
			return a <= 0 || b <= 0 || a * a + b * b <= 0.2025
		case .round: return u * u + v * v <= 1.0
		case .wedge: return v >= -u
		case .spike: return abs(u) <= (v + 1.0) * 0.5
		}
	}
}

/// What a piece is: an armour plate (guards), a frame piece (light, guards a little), a power core,
/// or a working part (one of the modules, or a mod's part)
enum SuitKind: Int, Codable, CaseIterable {
	case plate, frame, core, module
	var name: String {
		switch self {
		case .plate: return "Plate"
		case .frame: return "Frame"
		case .core: return "Core"
		case .module: return "Part"
		}
	}
}

/// One piece of a suit: where it is (its centre, measured on the body standing still, in suit units),
/// its size, turn, shape and thickness, what it is made of and painted, and how damaged it is
struct SuitPiece: Codable, Hashable, Identifiable {
	var id: Int = 0
	var kind: SuitKind = .plate
	/// a core's or a module's number (cores: ExoCore, modules: ExoModule)
	var part: Int = 0
	/// a mod's part, by key (then `part` is the module it works as)
	var modPart: String = ""
	var bone: SuitBone = .torso
	var x: Double = 15
	var y: Double = 25
	var w: Double = 6
	var h: Double = 6
	/// turned clockwise, in degrees
	var rot: Double = 0
	var shape: SuitShape = .box
	/// layers of material (1 to 3): thicker guards more and weighs more
	var thick: Int = 1
	/// the game's metal (ExoMat), or a mod's material by key
	var mat: Int = 0
	var modMat: String = ""
	/// paint (0: the material's own colour)
	var color: UInt32 = 0
	/// how damaged (0 whole ... 1 broken off)
	var dmg: Double = 0
	/// the group of the item it was made from (0: made of material); see SuitDesign.items
	var src: Int = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, 0)
		kind = c.val(.kind, .plate)
		part = c.val(.part, 0)
		modPart = c.val(.modPart, "")
		bone = c.val(.bone, .torso)
		x = c.val(.x, 15)
		y = c.val(.y, 25)
		w = c.val(.w, 6)
		h = c.val(.h, 6)
		rot = c.val(.rot, 0)
		shape = c.val(.shape, .box)
		thick = c.val(.thick, 1)
		mat = c.val(.mat, 0)
		modMat = c.val(.modMat, "")
		color = c.val(.color, 0)
		dmg = c.val(.dmg, 0)
		src = c.val(.src, 0)
	}

	var broken: Bool { return dmg >= 0.999 }
	var area: Double { return w * h * shape.fill }
	var module: ExoModule? { return kind == .module ? ExoModule(rawValue: part) : nil }
	var core: ExoCore? { return kind == .core ? ExoCore(rawValue: part) : nil }

	/// whether a point (suit units, the body standing still) is on the piece
	func covers(_ px: Double, _ py: Double) -> Bool {
		let a: Double = -rot * Double.pi / 180.0
		let dx: Double = px - x
		let dy: Double = py - y
		let lx: Double = dx * cos(a) - dy * sin(a)
		let ly: Double = dx * sin(a) + dy * cos(a)
		return shape.inside(lx / max(0.5, w * 0.5), ly / max(0.5, h * 0.5))
	}

	/// the same piece as it looks and is made (everything but where it is and how damaged)
	func sameMake(_ o: SuitPiece) -> Bool {
		return kind == o.kind && part == o.part && modPart == o.modPart && w == o.w && h == o.h && shape == o.shape && thick == o.thick && mat == o.mat && modMat == o.modMat
	}

	/// the piece kept within what the suit allows (sizes, places, thickness)
	mutating func clamp() {
		w = clampD(w.isFinite ? w : 6, 1, 30)
		h = clampD(h.isFinite ? h : 6, 1, 30)
		x = clampD(x.isFinite ? x : 15, -suitMargin, suitBodyW + suitMargin)
		y = clampD(y.isFinite ? y : 25, 0, suitBodyH)
		rot = rot.isFinite ? rot.truncatingRemainder(dividingBy: 360) : 0
		thick = clampI(thick, 1, 3)
		dmg = clampD(dmg.isFinite ? dmg : 0, 0, 1)
		if kind == .core && ExoCore(rawValue: part) == nil { part = 0 }
		if kind == .module && ExoModule(rawValue: part) == nil { part = 0 }
	}
}

/// A whole suit design: its pieces (drawn and guarding in order: later pieces lie over earlier ones on
/// the same part of the body), and the items its working parts were made from, by group (a core, a
/// module, or a part of a suit built the old way). An item goes back to the bag when every piece of
/// its group is taken off.
struct SuitDesign: Codable, Hashable {
	var pieces: [SuitPiece] = []
	var items: [Int: Stack] = [:]
	var nextID: Int = 1

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		pieces = c.list(.pieces, &skip)
		items = c.val(.items, [:])
		nextID = c.val(.nextID, 1)
		let top: Int = pieces.map { $0.id }.max() ?? 0
		if nextID <= top { nextID = top + 1 }
	}

	/// most pieces a suit may have
	static let maxPieces: Int = 160

	mutating func newID() -> Int {
		let n: Int = nextID
		nextID += 1
		return n
	}

	/// a new group for an item
	mutating func newGroup() -> Int {
		var g: Int = 1
		while items[g] != nil { g += 1 }
		return g
	}

	/// pieces that still work
	var working: [SuitPiece] { return pieces.filter { !$0.broken } }

	func index(_ id: Int) -> Int? { return pieces.firstIndex { $0.id == id } }
}

/// A mod's suit part, ready for play: the module it works as, its name and colour, how strong it is at
/// that work (1 the game's own) and what it weighs
struct SuitPartInfo {
	var name: String = "Part"
	var color: UInt32 = 0x8A929E
	var works: ExoModule = .turret
	var power: Double = 1
	var weight: Double = 2
}

/// The numbers of a suit material: the game's metals, or a mod's
struct SuitMatInfo {
	var name: String = "Iron"
	var color: UInt32 = 0xC8CCD4
	/// how well a layer guards (iron 1)
	var protect: Double = 1
	/// weight for its size (iron 1)
	var weight: Double = 1
	/// how much it takes before it breaks (iron 1)
	var durability: Double = 1
	/// how well it carries energy (iron 1)
	var conduct: Double = 1
	/// what each piece of it takes off fire, cold and lightning
	var fireCut: Double = 0
	var coldCut: Double = 0
	var stormCut: Double = 0
	/// what it is paid with, a unit at a time
	var cost: Item = .mat(.ironBar)
	/// the mining tier a drill of it bores at
	var drillTier: Int = 4
}

extension ExoMat {
	/// how much a piece of this metal takes before it breaks (iron 1)
	var durability: Double {
		switch self {
		case .iron: return 1.0
		case .bronze: return 0.85
		case .gold: return 0.6
		case .diamond: return 1.4
		case .mythril: return 1.3
		case .ember: return 1.5
		case .voidium: return 1.8
		}
	}

	var info: SuitMatInfo {
		var i = SuitMatInfo()
		i.name = name
		i.color = color
		i.protect = protect
		i.weight = weight
		i.durability = durability
		i.conduct = conduct
		i.fireCut = self == .ember ? 0.05 : 0
		i.coldCut = self == .voidium ? 0.04 : 0
		i.stormCut = self == .voidium ? 0.04 : 0
		i.cost = bar
		i.drillTier = drillTier
		return i
	}
}

/// A piece's material numbers (a mod's, if it names one that is on)
func suitMat(_ p: SuitPiece) -> SuitMatInfo {
	if !p.modMat.isEmpty, let m = ModRuntime.shared.suitMats[p.modMat] { return m }
	return (ExoMat(rawValue: p.mat) ?? .iron).info
}

/// The colour a piece shows
func suitColor(_ p: SuitPiece) -> UInt32 {
	if p.color != 0 { return p.color & 0xFFFFFF }
	if p.kind == .core, let c = p.core { return c.color }
	if p.kind == .module, !p.modPart.isEmpty, let mp = ModRuntime.shared.suitParts[p.modPart] { return mp.color }
	if p.kind == .module, let m = p.module { return shadeRGB(m.color, 0.85) }
	return suitMat(p).color
}

/// The body standing still, cell by cell (sprite pixels, columns from the figure's left edge), with the
/// part of the body each cell is: what a blow can land on
enum SuitBody {
	/// rows: (row, first column, last column, section)
	static let spans: [(Int, Int, Int, SuitSection)] = [
		(1, 3, 6, .head), (2, 2, 7, .head), (3, 2, 7, .head), (4, 2, 7, .head), (5, 3, 6, .head),
		(6, 3, 6, .torso),
		(7, 1, 2, .arms), (7, 3, 6, .torso), (7, 7, 8, .arms),
		(8, 1, 2, .arms), (8, 3, 6, .torso), (8, 7, 8, .arms),
		(9, 1, 2, .arms), (9, 3, 6, .torso), (9, 7, 8, .arms),
		(10, 2, 7, .torso), (11, 2, 7, .torso),
		(12, 2, 3, .legs), (12, 6, 7, .legs), (13, 2, 3, .legs), (13, 6, 7, .legs), (14, 2, 3, .legs), (14, 6, 7, .legs),
		(15, 2, 3, .feet), (15, 6, 7, .feet)
	]

	/// every body cell of a section, as (column, row)
	static let cells: [[(Int, Int)]] = {
		var out: [[(Int, Int)]] = [[(Int, Int)]](repeating: [], count: SuitSection.allCases.count)
		for s in spans {
			for x in s.1...s.2 { out[s.3.rawValue].append((x, s.0)) }
		}
		return out
	}()

	/// the section of a body cell (nil: not the body)
	static func section(_ col: Int, _ row: Int) -> SuitSection? {
		for s in spans where s.0 == row && col >= s.1 && col <= s.2 { return s.3 }
		return nil
	}

	/// The part of the body a piece placed with its centre at (x, y) belongs to
	static func bone(_ x: Double, _ y: Double) -> SuitBone {
		let col: Int = Int(floor(x / Double(suitUnit)))
		let row: Int = Int(floor(y / Double(suitUnit)))
		if row <= 5 { return .head }
		if row >= 12 { return col <= 4 ? .legBack : .legFront }
		if col < 1 { return .back }
		if row >= 6 && row <= 10 {
			if col <= 2 { return .armBack }
			if col >= 7 { return .armFront }
		}
		return .torso
	}
}

/// How a part of the body is moved in one of the sprite's frames (0 standing, 1-2 walking, 3 winding up,
/// 4 striking, 5 blocking, 6 shooting): shifted, and the front arm turned out from the shoulder
struct BoneMove {
	var dx: Double = 0
	var dy: Double = 0
	var turn: Double = 0
	var px: Double = 0
	var py: Double = 0

	static func of(_ b: SuitBone, _ frame: Int) -> BoneMove {
		var m = BoneMove()
		let u: Double = Double(suitUnit)
		switch b {
		case .legBack:
			if frame == 1 { m.dx = -u } else if frame == 2 { m.dx = u }
		case .legFront:
			if frame == 1 { m.dx = u } else if frame == 2 { m.dx = -u }
		case .armFront:
			if frame >= 3 {
				// the arm swings forward from the shoulder (raised a pixel while winding up)
				m.turn = -Double.pi / 2
				m.px = 8 * u
				m.py = 8 * u
				if frame == 3 { m.dy = -u }
			}
		default: break
		}
		return m
	}

	/// a point (suit units, standing still) where it is in this frame
	func apply(_ x: Double, _ y: Double) -> (Double, Double) {
		if turn == 0 { return (x + dx, y + dy) }
		let c: Double = cos(turn)
		let s: Double = sin(turn)
		let rx: Double = x - px
		let ry: Double = y - py
		return (px + rx * c - ry * s + dx, py + rx * s + ry * c + dy)
	}
}

/// What a suit adds up to: worked out once each time it changes, never every frame
struct ExoStats {
	var weight: Double = 0
	var strength: Double = 20
	var speedMul: Double = 1
	var jumpMul: Double = 1
	var capacity: Double = 0
	var output: Double = 0
	var recharge: Double = 0
	var drainMul: Double = 1
	var fireCut: Double = 0
	var coldCut: Double = 0
	var stormCut: Double = 0
	var knockMul: Double = 1
	var drillTier: Int = 0
	/// the share of a blow its plates stop, on average over the whole body (0 ... 1)
	var guardAll: Double = 0
	/// for each part of the body (SuitSection): the share of it covered by working plates, and the
	/// share of a blow there they stop on average
	var cover: [Double] = [0, 0, 0, 0, 0]
	var guardBy: [Double] = [0, 0, 0, 0, 0]
	/// working parts by module, and their strength (a mod's part counts as more)
	var counts: [Int: Int] = [:]
	var power: [Int: Double] = [:]
	/// the jets' lift, in body weights (over 1 rises), and the wings' area
	var thrust: Double = 0
	var wingArea: Double = 0
	/// energy the solar panels make a second in full sun
	var solar: Double = 0
	var modules: [ExoModule] = []
	/// can be worn: it has some pieces
	var complete: Bool = false
	/// what is wrong or missing, in plain words
	var notes: [String] = []
	var thrift: Set<Int> = []
	var pieces: Int = 0
	var broken: Int = 0

	func has(_ m: ExoModule) -> Bool { return (counts[m.rawValue] ?? 0) > 0 }
	func count(_ m: ExoModule) -> Int { return counts[m.rawValue] ?? 0 }
	func strength(_ m: ExoModule) -> Double { return power[m.rawValue] ?? 0 }

	/// what the old defence number would have been (for the item screens): 25 points stop everything
	var defense: Double { return guardAll * 25.0 }

	static func of(_ s: ExoSuit) -> ExoStats { return of(s.d) }

	static func of(_ d: SuitDesign) -> ExoStats {
		var r: ExoStats = ExoStats()
		var conductSum: Double = 0
		var conductN: Double = 0
		var drill: Int = 0
		for p in d.pieces {
			r.pieces += 1
			if p.broken {
				r.broken += 1
				continue
			}
			let mi: SuitMatInfo = suitMat(p)
			switch p.kind {
			case .plate, .frame:
				let k: Double = p.kind == .plate ? 1.0 : 0.6
				r.weight += p.area * Double(p.thick) * mi.weight * 0.035 * k
				conductSum += mi.conduct
				conductN += 1
				r.fireCut = min(0.6, r.fireCut + mi.fireCut)
				r.coldCut = min(0.6, r.coldCut + mi.coldCut)
				r.stormCut = min(0.6, r.stormCut + mi.stormCut)
			case .core:
				guard let c = p.core else { continue }
				r.capacity += c.capacity
				r.output += c.output
				r.recharge += c.recharge
				r.weight += 3
				if let st = d.items[p.src], st.has(.thrift) { r.drainMul *= 0.75 }
			case .module:
				guard let m = p.module else { continue }
				var k: Double = 1.0
				if !p.modPart.isEmpty, let mp = ModRuntime.shared.suitParts[p.modPart] {
					k = mp.power
					r.weight += mp.weight
				} else {
					r.weight += m.weight
				}
				r.counts[m.rawValue, default: 0] += 1
				r.power[m.rawValue, default: 0] += k
				if let st = d.items[p.src], st.has(.thrift) { r.thrift.insert(m.rawValue) }
				switch m {
				case .hover:
					// a jet lifts more the bigger it is, along the way it points (straight down: all up)
					let lift: Double = clampD(0.25 + p.area * 0.012, 0.25, 1.0) * k
					r.thrust += lift * max(0, cos(p.rot * Double.pi / 180.0))
				case .wing: r.wingArea += p.area * k
				case .battery: r.capacity += clampD(60 + p.area * 1.5, 60, 160) * k
				case .solar: r.solar += clampD(0.2 + p.area * 0.01, 0.2, 0.6) * k
				case .drill: drill = max(drill, mi.drillTier)
				default: break
				}
			}
		}
		if conductN > 0 { r.drainMul /= max(0.6, conductSum / conductN) }
		r.drillTier = drill
		var mods: [ExoModule] = []
		for m in ExoModule.allCases where r.has(m) { mods.append(m) }
		r.modules = mods
		// servos: more strength and harder blows
		r.strength += 12.0 * min(3.0, r.strength(.servo))
		// weight against strength, the jets' lift against the suit's weight
		let over: Double = max(0, r.weight - r.strength)
		r.speedMul = 1.0 - min(0.35, over * 0.006)
		r.jumpMul = 1.0 - min(0.3, over * 0.004)
		r.knockMul = max(0.35, 1.0 - r.weight * 0.012)
		r.thrust /= 1.0 + r.weight / 60.0
		// how well it guards, part of the body by part
		let g: SuitGuardMap = SuitGuardMap.of(d)
		r.cover = g.cover
		r.guardBy = g.guardBy
		r.guardAll = g.guardAll
		r.complete = !d.pieces.isEmpty
		if d.pieces.isEmpty { r.notes.append("Place some pieces: plates to guard, and parts that work.") }
		if r.capacity <= 0 && !r.modules.isEmpty { r.notes.append("Fit a power core or a battery: its parts have no energy without one.") }
		if r.capacity > 0 && r.output <= 0 && !r.modules.isEmpty { r.notes.append("Batteries hold energy but only a core can give it out quickly; fit a core.") }
		if r.has(.hover) && r.thrust < 1.0 { r.notes.append(joinText("Its jets lift ", String(Int((r.thrust * 100).rounded())), "% of its weight: they slow a fall but can't climb.")) }
		if r.has(.drill) && !d.pieces.contains(where: { $0.module == .drill && !$0.broken && ($0.bone == .armFront || $0.bone == .armBack) }) {
			r.notes.append("A drill works only on an arm.")
		}
		if r.broken > 0 { r.notes.append(joinText(String(r.broken), r.broken == 1 ? " piece is" : " pieces are", " broken: mend them at an Assembly Station.")) }
		for st in d.items.values { r.drainMul *= customEnergyMul(st) }
		// a drill must be on an arm to bore
		if !d.pieces.contains(where: { $0.module == .drill && !$0.broken && ($0.bone == .armFront || $0.bone == .armBack) }) {
			r.counts[ExoModule.drill.rawValue] = nil
			r.modules.removeAll { $0 == .drill }
			r.drillTier = 0
		}
		return r
	}
}

/// How well a design guards, worked out over the body cell by cell (each cell split three by three)
struct SuitGuardMap {
	var cover: [Double] = [0, 0, 0, 0, 0]
	var guardBy: [Double] = [0, 0, 0, 0, 0]
	var guardAll: Double = 0

	static func of(_ d: SuitDesign) -> SuitGuardMap {
		var g = SuitGuardMap()
		var total: Double = 0
		var n: Double = 0
		let u: Int = suitUnit
		for sec in SuitSection.allCases {
			var covered: Double = 0
			var stop: Double = 0
			var cells: Double = 0
			for (cx, cy) in SuitBody.cells[sec.rawValue] {
				for sy in 0..<u {
					for sx in 0..<u {
						let px: Double = Double(cx * u + sx) + 0.5
						let py: Double = Double(cy * u + sy) + 0.5
						let pass: Double = suitPass(d, px, py).0
						if pass < 0.999 { covered += 1 }
						stop += 1.0 - pass
						cells += 1
					}
				}
			}
			if cells > 0 {
				g.cover[sec.rawValue] = covered / cells
				g.guardBy[sec.rawValue] = stop / cells
			}
			total += stop
			n += cells
		}
		g.guardAll = n > 0 ? total / n : 0
		return g
	}
}

/// What a piece stops of a blow that lands on it (0 ... 0.8): plates by their metal and thickness,
/// less as they wear; frames a little; working parts hardly at all
func suitShare(_ p: SuitPiece) -> Double {
	if p.broken { return 0 }
	let mi: SuitMatInfo = suitMat(p)
	var s: Double
	switch p.kind {
	case .plate: s = clampD(0.2 * mi.protect * Double(p.thick), 0.05, 0.8)
	case .frame: s = clampD(0.08 * mi.protect * Double(p.thick), 0.02, 0.4)
	case .core, .module: s = 0.06
	}
	return s * (1.0 - 0.5 * clampD(p.dmg, 0, 1))
}

/// What gets through a blow at a body point (suit units, standing still), and the pieces over it
/// outermost first (the share each one takes is its own; a blow passes through them in turn)
func suitPass(_ d: SuitDesign, _ px: Double, _ py: Double) -> (Double, [Int]) {
	var over: [Int] = []
	for (i, p) in d.pieces.enumerated() where !p.broken && p.covers(px, py) { over.append(i) }
	if over.isEmpty { return (1.0, []) }
	over.sort { (a: Int, b: Int) -> Bool in
		let la: Int = d.pieces[a].bone.layer
		let lb: Int = d.pieces[b].bone.layer
		return la != lb ? la > lb : a > b
	}
	var pass: Double = 1.0
	for i in over { pass *= 1.0 - suitShare(d.pieces[i]) }
	return (pass, over)
}

/// How much a piece can take before it breaks
func suitPieceHP(_ p: SuitPiece) -> Double {
	let mi: SuitMatInfo = suitMat(p)
	switch p.kind {
	case .plate, .frame: return 6.0 + p.area * Double(p.thick) * mi.durability * 0.35
	case .core: return 14
	case .module: return 10
	}
}

/// What a piece costs to make: units of its material (plates and frames), or its item (cores and parts)
func suitPieceCost(_ p: SuitPiece) -> (Item, Int)? {
	if p.kind != .plate && p.kind != .frame { return nil }
	let per: Double = p.kind == .plate ? 40.0 : 80.0
	let n: Int = max(1, Int(ceil(p.area * Double(p.thick) / per)))
	return (suitMat(p).cost, n)
}

/// A bill: items to pay and to give back
struct SuitBill {
	var pay: [Item: Int] = [:]
	var back: [Item: Int] = [:]
	/// item stacks to take from the bag, and to give back (cores, parts, old suit parts)
	var take: [Stack] = []
	var give: [Stack] = []

	var isEmpty: Bool { return pay.isEmpty && back.isEmpty && take.isEmpty && give.isEmpty }

	/// what is paid, in words
	func payText() -> String {
		var parts: [String] = []
		for (it, n) in pay.sorted(by: { $0.key.name < $1.key.name }) { parts.append(joinText(String(n), " ", it.name)) }
		for s in take { parts.append(s.item.name) }
		return parts.joined(separator: ", ")
	}
}

extension SuitDesign {
	/// What changing this design into `plan` costs: new and changed pieces are paid for, pieces taken
	/// off give back what is left of them (a damaged piece less), and an item comes back when the last
	/// piece of its group goes
	func bill(to plan: SuitDesign) -> SuitBill {
		var b = SuitBill()
		var old: [Int: SuitPiece] = [:]
		for p in pieces { old[p.id] = p }
		var keep: Set<Int> = []
		for p in plan.pieces {
			if let o = old[p.id], o.sameMake(p) {
				keep.insert(p.id)
				continue
			}
			if let c = suitPieceCost(p) { b.pay[c.0, default: 0] += c.1 }
		}
		for p in pieces where !keep.contains(p.id) {
			if let c = suitPieceCost(p) {
				let n: Int = Int(floor(Double(c.1) * (1.0 - p.dmg)))
				if n > 0 { b.back[c.0, default: 0] += n }
			}
		}
		// items: groups in the plan that are new, groups no longer used
		let usedNow: Set<Int> = Set(plan.pieces.map { $0.src }.filter { $0 != 0 })
		for (g, st) in plan.items where usedNow.contains(g) && items[g] != st { b.take.append(st) }
		for (g, st) in items where !usedNow.contains(g) || plan.items[g] != st { b.give.append(st) }
		// what is both paid and given back of the same item only costs the difference
		for (it, n) in b.back {
			if let p = b.pay[it] {
				let m: Int = min(p, n)
				b.pay[it] = p - m == 0 ? nil : p - m
				b.back[it] = n - m == 0 ? nil : n - m
			}
		}
		return b
	}

	/// What mending every damaged piece costs: its share of its material (cores and parts: copper)
	func repairBill() -> [Item: Int] {
		var out: [Item: Int] = [:]
		for p in pieces where p.dmg > 0.001 {
			if let c = suitPieceCost(p) {
				out[c.0, default: 0] += max(1, Int(ceil(Double(c.1) * p.dmg)))
			} else {
				out[.mat(.copperBar), default: 0] += max(1, Int(ceil(2.0 * p.dmg)))
			}
		}
		return out
	}
}

extension Game {
	// MARK: suit state

	/// a suit is on
	var suitWorn: Bool { return suit.worn }

	/// the suit's numbers, worked out again only when it changes
	var suitStats: ExoStats {
		if suitStatsRev == suitRev { return suitStatsCache }
		suitStatsCache = ExoStats.of(suit)
		suitStatsRev = suitRev
		return suitStatsCache
	}

	/// Call after any change to the suit: its numbers, its armour infusions and its look are redone
	func suitChanged() {
		suitRev &+= 1
		bumpHUD()
	}

	/// A module that is fitted, working, switched on and has energy behind it
	func suitHas(_ m: ExoModule) -> Bool {
		if !suit.worn || suit.energy <= 0.01 { return false }
		if suit.off?.contains(m.rawValue) ?? false { return false }
		return suitStats.has(m)
	}

	/// Spends energy on a module; false (nothing spent) when there is not enough
	@discardableResult
	func suitSpend(_ m: ExoModule, _ amount: Double) -> Bool {
		if isCreative { return true }
		let st: ExoStats = suitStats
		var a: Double = amount * st.drainMul
		if st.thrift.contains(m.rawValue) { a *= 0.75 }
		if suit.energy < a { return false }
		suit.energy -= a
		return true
	}

	/// Spends energy over time for a module that runs continuously, within what the cores can give
	/// each second; false when they can't keep it going
	func suitRun(_ m: ExoModule, _ perSec: Double, _ dt: Double) -> Bool {
		if !suitHas(m) { return false }
		let st: ExoStats = suitStats
		var rate: Double = perSec * st.drainMul
		if st.thrift.contains(m.rawValue) { rate *= 0.75 }
		if suitLoad + rate > st.output + 1e-6 { return false }
		suitLoad += rate
		if isCreative { return true }
		let a: Double = rate * dt
		if suit.energy < a { return false }
		suit.energy -= a
		return true
	}

	/// A point of the suit (suit units, the body standing still) in the world, as the player stands and
	/// faces now
	func suitPoint(_ x: Double, _ y: Double) -> (Double, Double) {
		let ax: Double = x / Double(suitUnit) - 5.0
		let ay: Double = y / Double(suitUnit) - 16.0
		return (pb.x + Double(facing) * ax * 0.125, pb.y + ay * 0.125)
	}

	/// Once a frame while the suit is worn: the cores refill a little (and the sun through solar
	/// panels), the parts that run by themselves take their share, jets lift, wings glide, turrets shoot
	func updateSuit(_ dt: Double) {
		// the load counts everything run since the last frame's end (the drill runs earlier in the
		// frame, while mining), so all modules share the cores' output together
		defer {
			suitLastLoad = suitLoad
			suitLoad = 0
		}
		suitHover = false
		suitBeams.removeAll()
		if !suit.worn { return }
		let st: ExoStats = suitStats
		if !st.complete {
			suit.worn = false
			suitChanged()
			return
		}
		var gain: Double = st.recharge
		if st.solar > 0 && suitInSun() { gain += st.solar * dayFactor }
		suit.energy = min(st.capacity, suit.energy + gain * dt)
		if dead || inVehicle != nil || mounted != nil { return }
		// the seal works only while something it guards against is around
		if st.has(.seal) && sealNeeded() { _ = suitRun(.seal, 2.0, dt) }
		suitFly(st, dt)
		if st.has(.sprint) && abs(pb.vx) > 4.0 && pb.onGround { suitSprinting = suitRun(.sprint, 1.2, dt) } else { suitSprinting = false }
		// the lamp lights itself in the dark: at night, under ground, in the Umbral realm
		if st.has(.lamp) && suitNeedsLight() { suitLit = suitRun(.lamp, 0.25, dt) } else { suitLit = false }
		if st.has(.servo) { _ = suitRun(.servo, 0.1, dt) }
		if st.has(.magnet) && suitRun(.magnet, 0.3, dt) { suitPull(st, dt) }
		if st.has(.turret) { suitTurrets(st, dt) }
		if suitFireHeld && (st.has(.cannon) || st.has(.laser)) { suitFire(st, dt) }
		if suit.energy <= 0.01 && !suitEmptyWarned && !st.modules.isEmpty {
			suitEmptyWarned = true
			say("Suit energy is spent: its parts are dead weight until it charges.", 2.5)
		} else if suit.energy > 5 {
			suitEmptyWarned = false
		}
	}

	/// Under the open sky (for solar panels)
	func suitInSun() -> Bool {
		if !dimHasSky(world.dim) { return false }
		return world.isSkyExposed(Int(floor(pb.x)), Int(floor(pb.y - 1.6)))
	}

	/// Jets and wings, with jump held in the air: the jets push along the way they point (lifting the
	/// suit if their lift beats its weight), and wings hold a fall to a glide
	func suitFly(_ st: ExoStats, _ dt: Double) {
		if !jumpHeld || pb.onGround || pb.inWater || flying { return }
		var glide: Bool = false
		if st.has(.hover) {
			let rate: Double = 2.5 * max(0.3, st.strength(.hover))
			if suitRun(.hover, rate, dt) {
				suitHover = true
				var push: Double = 0
				for p in suit.d.working where p.module == .hover {
					let lift: Double = clampD(0.25 + p.area * 0.012, 0.25, 1.0)
					push += lift * sin(p.rot * Double.pi / 180.0)
				}
				pb.vy -= gravityG * st.thrust * dt
				pb.vy = max(pb.vy, -8.0)
				pb.vx += Double(facing) * push * gravityG * 0.5 * dt
				fallPeak = 0
				if frameNo % 3 == 0 {
					for p in suit.d.working where p.module == .hover {
						let q: (Double, Double) = suitPoint(p.x, p.y + p.h * 0.5)
						spawnParticles(q.0, q.1, 0xFF9A3A, 1, 1.5, 0.25, 6)
					}
				}
			}
		}
		if st.wingArea > 0 && pb.vy > 0 {
			// the more wing, the slower the fall, and a little carry forward
			let maxFall: Double = clampD(7.0 - st.wingArea * 0.06, 1.2, 7.0)
			if pb.vy > maxFall {
				pb.vy = maxFall
				glide = true
			}
			if glide {
				let carry: Double = min(3.0, st.wingArea * 0.03)
				pb.vx += Double(facing) * carry * dt * 4.0
				fallPeak = 0
			}
		}
	}

	/// The magnet draws dropped things to the player
	func suitPull(_ st: ExoStats, _ dt: Double) {
		let r: Double = 6.0 + 2.0 * Double(max(0, st.count(.magnet) - 1))
		for i in drops.indices {
			let dx: Double = pb.x - drops[i].x
			let dy: Double = (pb.y - 0.8) - drops[i].y
			let d: Double = sqrt(dx * dx + dy * dy)
			if d > r || d < 0.3 || drops[i].heldBack { continue }
			drops[i].vx += dx / d * 18.0 * dt
			drops[i].vy += dy / d * 18.0 * dt - 6.0 * dt
		}
	}

	/// The nearest foe in reach of a point, and in sight of it
	func suitTarget(_ x: Double, _ y: Double, _ reach: Double) -> Mob? {
		var best: Mob? = nil
		var bd: Double = reach
		for m in mobsNear(x - reach, x + reach) where m.hp > 0 && !m.removed && !m.downed && isThreat(m) {
			let d: Double = hypot(m.b.x - x, m.b.cy - y)
			if d < bd && world.lineClear(x, y, m.b.x, m.b.cy) {
				bd = d
				best = m
			}
		}
		return best
	}

	/// Turrets find the nearest foe and shoot at it by themselves (energy each shot)
	func suitTurrets(_ st: ExoStats, _ dt: Double) {
		for p in suit.d.working where p.module == .turret {
			let cd: Double = (suitGunCD[p.id] ?? 0) - dt
			if cd > 0 {
				suitGunCD[p.id] = cd
				continue
			}
			let o: (Double, Double) = suitPoint(p.x, p.y)
			guard let m = suitTarget(o.0, o.1, 12.0) else {
				suitGunCD[p.id] = 0.25
				continue
			}
			if !suitSpend(.turret, 1.2) {
				suitGunCD[p.id] = 0.5
				continue
			}
			let k: Double = suitPartPower(p)
			let a: Double = atan2(m.b.cy - o.1, m.b.x + m.b.vx * 0.15 - o.0)
			suitShoot(.bullet, o, a, 40.0, (3.0 + min(3.0, p.area * 0.05)) * k, 2.0)
			suitGunCD[p.id] = 1.1
			sfx(.gun, at: o.0, 0.25)
		}
	}

	/// Cannons and lasers, while the suit's FIRE control is held: at the aim, or the nearest foe
	func suitFire(_ st: ExoStats, _ dt: Double) {
		for p in suit.d.working where p.module == .cannon || p.module == .laser {
			let o: (Double, Double) = suitPoint(p.x, p.y)
			var tx: Double = o.0 + Double(facing) * 10.0
			var ty: Double = o.1
			if aimValid {
				tx = aimX
				ty = aimY
			} else if let m = suitTarget(o.0, o.1, 16.0) {
				tx = m.b.x
				ty = m.b.cy
			}
			let a: Double = atan2(ty - o.1, tx - o.0)
			let k: Double = suitPartPower(p)
			if p.module == .cannon {
				let cd: Double = (suitGunCD[p.id] ?? 0) - dt
				suitGunCD[p.id] = cd
				if cd > 0 || !suitSpend(.cannon, 10.0) { continue }
				suitShoot(.shell, o, a, 30.0, 14.0 * k, 9.0)
				suitGunCD[p.id] = 2.2
				spawnParticles(o.0, o.1, 0xFFC050, 6, 4.0, 0.25, 2)
				pb.vx -= cos(a) * 3.0
				addShake(0.15)
				sfx(.blunderbuss, at: o.0, 0.7)
			} else {
				if !suitRun(.laser, 5.0, dt) { continue }
				suitLaser(o, a, 10.0 * k * dt, p.id)
			}
		}
	}

	/// A shot from the suit: the player's own
	func suitShoot(_ kind: ProjKind, _ o: (Double, Double), _ a: Double, _ speed: Double, _ dmg: Double, _ knock: Double) {
		var q = Projectile(kind: kind, x: o.0 + cos(a) * 0.4, y: o.1 + sin(a) * 0.4, vx: cos(a) * speed + (inVehicle == nil ? pb.vx : 0) * 0.5 + carrierVel().0, vy: sin(a) * speed + carrierVel().1, dmg: dmg, fromPlayer: true, gravity: kind == .shell ? 14 : 2)
		q.life = kind == .shell ? 4.0 : 1.2
		q.w = kind == .shell ? 0.3 : 0.12
		q.source = .player
		q.owner = kind == .shell ? suitShellOwner : 0
		q.uid = newID()
		q.knock = knock
		projectiles.append(q)
	}

	/// A laser's beam: it runs straight until a block stops it, and burns the first foe in its way
	func suitLaser(_ o: (Double, Double), _ a: Double, _ dmg: Double, _ id: Int) {
		let dx: Double = cos(a)
		let dy: Double = sin(a)
		var x: Double = o.0
		var y: Double = o.1
		var hitMob: Mob? = nil
		var k: Int = 0
		while k < 56 {
			x += dx * 0.25
			y += dy * 0.25
			if world.tile(Int(floor(x)), Int(floor(y))).solid { break }
			if let m = mobsNear(x - 1, x + 1).first(where: { $0.hp > 0 && !$0.removed && isThreat($0) && x >= $0.b.left && x <= $0.b.right && y >= $0.b.top && y <= $0.b.y }) {
				hitMob = m
				break
			}
			k += 1
		}
		suitBeams.append((o.0, o.1, x, y))
		guard let m = hitMob else { return }
		var info = DamageInfo(amount: dmg, type: .magic, source: .player)
		info.originX = o.0
		info.originY = o.1
		applyMobDamage(m, info)
		if frameNo % 4 == 0 { spawnParticles(x, y, 0xFF5A8A, 2, 2.0, 0.2, 0) }
	}

	/// How strong a working part is: a mod's part by its own number, the game's by 1
	func suitPartPower(_ p: SuitPiece) -> Double {
		if !p.modPart.isEmpty, let mp = ModRuntime.shared.suitParts[p.modPart] { return mp.power }
		return 1.0
	}

	/// Dark enough for the helmet lamp
	func suitNeedsLight() -> Bool {
		if world.dim != .overworld { return true }
		if dayFactor < 0.5 { return true }
		return !world.isSkyExposed(Int(floor(pb.x)), Int(floor(pb.y - 1.0)))
	}

	/// Fire, lava, deep water, a blizzard or a thunderstorm around the player
	func sealNeeded() -> Bool {
		if playerBurn > 0 || pb.inLava || lavaT > 0 { return true }
		let headY: Int = Int(floor(pb.y - pb.h * 0.92))
		if world.tile(Int(floor(pb.x)), headY) == .water { return true }
		if world.dim == .overworld && settings.weatherOn {
			if wxHere.chill > 0.5 || wxHere.thunder > 0.4 || wxHere.hail > 0.3 { return true }
		}
		return false
	}

	/// The suit's speed: its weight against its strength, and the boosters
	var suitSpeedMul: Double {
		if !suit.worn { return 1.0 }
		var m: Double = suitStats.speedMul
		if suitSprinting { m *= min(1.4, 1.0 + 0.2 * suitStats.strength(.sprint)) }
		return m
	}

	/// The suit's jump: weight, and the leap pistons (each boosted jump costs energy)
	func suitJumpMul() -> Double {
		if !suit.worn { return 1.0 }
		var m: Double = suitStats.jumpMul
		if suitHas(.leap) && suitSpend(.leap, 3.0) { m *= min(1.6, 1.0 + 0.35 * suitStats.strength(.leap)) }
		return m
	}

	/// A melee blow through the suit: servos hit harder
	func suitMelee(_ p0: MeleeProfile) -> MeleeProfile {
		var p: MeleeProfile = p0
		if suitHas(.servo) { p.damage *= 1.0 + 0.25 * min(2.0, suitStats.strength(.servo)) }
		return p
	}

	/// After a melee blow lands with the suit on: the gauntlet's shock
	func suitMeleeHit(_ m: Mob) {
		if m.hp <= 0 || !suitHas(.gauntlet) { return }
		if !suitSpend(.gauntlet, 1.5) { return }
		var info = DamageInfo(amount: 4 * max(1.0, suitStats.strength(.gauntlet)), type: .shock, source: .player)
		info.originX = pb.x
		info.key = newID()
		applyMobDamage(m, info)
		spawnParticles(m.b.x, m.b.cy, 0xFFF07A, 5, 3.0, 0.2, 0)
	}

	/// The share of a blow the suit lets through: its plates where it lands (each takes the damage
	/// itself, layer by layer), the metals and the seal against fire, water and lightning, and the
	/// barrier turning some of what is left into energy drain
	func suitGuard(_ amount: Double, _ info: DamageInfo) -> Double {
		if !suit.worn { return amount }
		let st: ExoStats = suitStats
		let type: DamageType = info.type
		var a: Double = amount
		if type == .fire || type == .lava {
			a *= 1.0 - st.fireCut
			if suitHas(.seal) { a *= 0.4 }
		}
		if type == .shock {
			a *= 1.0 - st.stormCut
			if suitHas(.seal) { a *= 0.5 }
		}
		if type == .drown && suitHas(.seal) { a = 0 }
		if a > 0 && !type.bypassesArmor && type != .shock { a = suitTakeBlow(a, info) }
		if a > 0 && suitHas(.barrier) && type != .starve && type != .drown {
			let take: Double = a * min(0.6, 0.4 * suitStats.strength(.barrier))
			if suitSpend(.barrier, take * 3.0) {
				a -= take
				spawnParticles(pb.x, pb.cy, 0xC07CFF, 4, 2.5, 0.25, 0)
			}
		}
		return a
	}

	/// How high on the body a blow lands (0 the top of the head ... 1 the feet; nil: anywhere)
	func suitHitHeight(_ info: DamageInfo) -> Double? {
		var oy: Double? = nil
		if info.source.kind == .mob, let m = mobs.first(where: { $0.id == info.source.id }) { oy = m.b.cy }
		if oy == nil && info.originY != 0 { oy = info.originY }
		guard let y = oy else { return nil }
		return clampD((y - pb.top) / max(0.5, pb.h), 0, 1)
	}

	/// A point on the body (suit units, standing still) a blow lands on: at about the height given,
	/// spread a little, or anywhere on the body
	func suitBodyPoint(_ f: Double?) -> (Double, Double) {
		var cells: [(Int, Int)] = []
		if let h = f {
			let row: Int = clampI(1 + Int(((h + Double.random(in: -0.15...0.15)) * 15.0).rounded()), 1, 15)
			for sec in SuitBody.cells {
				for c in sec where abs(c.1 - row) <= 1 { cells.append(c) }
			}
		}
		if cells.isEmpty { for sec in SuitBody.cells { cells += sec } }
		let c: (Int, Int) = cells[Int.random(in: 0..<cells.count)]
		let u: Double = Double(suitUnit)
		return (Double(c.0) * u + Double.random(in: 0..<u), Double(c.1) * u + Double.random(in: 0..<u))
	}

	/// A blow on the suit: where it lands the pieces over the body take it in turn, outermost first,
	/// each stopping its share and taking that much damage itself. A blast spreads over the body.
	/// Returns what gets through.
	func suitTakeBlow(_ amount: Double, _ info: DamageInfo) -> Double {
		var d: SuitDesign = suit.d
		if d.pieces.isEmpty { return amount }
		var points: [(Double, Double)] = []
		if info.type.isArea {
			for _ in 0..<6 { points.append(suitBodyPoint(nil)) }
		} else {
			points.append(suitBodyPoint(suitHitHeight(info)))
		}
		let share: Double = 1.0 / Double(points.count)
		var through: Double = 0
		var broke: [String] = []
		var look: Bool = false
		for pt in points {
			let over: [Int] = suitPass(d, pt.0, pt.1).1
			var left: Double = amount * share
			for i in over {
				let took: Double = left * suitShare(d.pieces[i])
				left -= took
				let before: Int = Int(d.pieces[i].dmg * 3.0)
				let hp: Double = suitPieceHP(d.pieces[i])
				d.pieces[i].dmg = min(1.0, d.pieces[i].dmg + took * 1.3 / max(1.0, hp))
				if d.pieces[i].broken {
					broke.append(suitPieceName(d.pieces[i]))
					let q: (Double, Double) = suitPoint(d.pieces[i].x, d.pieces[i].y)
					spawnParticles(q.0, q.1, suitColor(d.pieces[i]), 7, 3.5, 0.5, 14)
				} else if Int(d.pieces[i].dmg * 3.0) != before {
					look = true
				}
			}
			through += left
		}
		suit.d = d
		if !broke.isEmpty {
			sfx(.breakStone, 0.6)
			if suitSayT <= clock {
				suitSayT = clock + 2.0
				say(joinText("A suit piece broke: ", broke[0], "."), 1.8)
			}
			suitChanged()
		} else if look {
			suitChanged()
		}
		return through
	}

	/// A piece's name, in words
	func suitPieceName(_ p: SuitPiece) -> String {
		if p.kind == .core, let c = p.core { return c.name }
		if p.kind == .module {
			if !p.modPart.isEmpty, let mp = ModRuntime.shared.suitParts[p.modPart] { return mp.name }
			if let m = p.module { return m.name }
		}
		return joinText(suitMat(p).name.lowercased(), " ", p.kind == .plate ? "plate" : "frame", " on the ", p.bone.name.lowercased())
	}

	/// How much slower the cold gets in through the suit
	var suitColdMul: Double {
		if !suit.worn { return 1.0 }
		var m: Double = 1.0 - suitStats.coldCut
		if suitHas(.seal) { m *= 0.1 }
		return m
	}

	/// The drill, if it can bore right now: its tier (0: no drill)
	func suitDrillTier() -> Int {
		if !suitHas(.drill) { return 0 }
		return suitStats.drillTier
	}

	/// The suit covers the head (a hailstone can't reach it)
	var suitHelmet: Bool { return suit.worn && suitStats.cover[SuitSection.head.rawValue] > 0.5 }

	// MARK: putting the suit on and off

	/// Puts the suit on: the armour slots for head, body and legs must be free (armour worn there goes
	/// into the bag first). Returns what to say.
	@discardableResult
	func wearSuit() -> String {
		let st: ExoStats = suitStats
		if !st.complete { return st.notes.first ?? "The suit has no pieces yet." }
		if suit.worn { return "You are already wearing it." }
		for i in 0..<3 {
			if let a = inv.armor[i] {
				if inv.canFit(a.item, 1) {
					addStack(a)
					inv.armor[i] = nil
				} else {
					return "Your bag is too full to take off your armour."
				}
			}
		}
		suit.worn = true
		if suit.energy <= 0 && isCreative { suit.energy = st.capacity }
		sfx(.suitUp, 0.8)
		spawnParticles(pb.x, pb.y - 1.0, st.modules.isEmpty ? 0xC8CCD4 : 0x60E0FF, 12, 3.0, 0.5, -2)
		suitChanged()
		return "Suit on."
	}

	@discardableResult
	func takeOffSuit() -> String {
		if !suit.worn { return "You are not wearing it." }
		suit.worn = false
		sfx(.suitUp, 0.5)
		suitChanged()
		return "Suit off."
	}

	/// Puts a whole stack (with its infusions) into the bag, or at the player's feet if it is full:
	/// nothing is ever lost
	func addStack(_ s: Stack) {
		for i in 0..<inv.slots.count where inv.slots[i] == nil {
			inv.slots[i] = s
			bumpHUD()
			return
		}
		spawnDrop(s, pb.x, pb.y - 1, 0, -2)
		say("Your bag is full: it went on the ground.", 1.6)
	}

	/// Gives items to the bag (what does not fit goes on the ground)
	func giveItems(_ it: Item, _ n: Int) {
		let left: Int = inv.add(it, n)
		if left > 0 { spawnDrop(Stack(item: it, count: left), pb.x, pb.y - 1, 0, -2) }
		bumpHUD()
	}

	/// Builds a planned design: new and changed pieces are paid for out of the bag (their metal, and the
	/// cores and parts placed), pieces taken off give back what is left of them, and an item comes back
	/// when the last piece of its group goes. All or nothing. Returns what to say.
	@discardableResult
	func applyDesign(_ plan0: SuitDesign) -> String {
		var plan: SuitDesign = plan0
		if plan.pieces.count > SuitDesign.maxPieces { return joinText("A suit holds at most ", String(SuitDesign.maxPieces), " pieces.") }
		var now: [Int: SuitPiece] = [:]
		for p in suit.d.pieces { now[p.id] = p }
		for k in plan.pieces.indices {
			plan.pieces[k].clamp()
			// a piece kept as it was keeps its damage; a new or remade one is whole
			if let o = now[plan.pieces[k].id], o.sameMake(plan.pieces[k]) { plan.pieces[k].dmg = o.dmg } else { plan.pieces[k].dmg = 0 }
			if !isCreative && (plan.pieces[k].kind == .core || plan.pieces[k].kind == .module) && plan.items[plan.pieces[k].src] == nil {
				return joinText(suitPieceName(plan.pieces[k]), " has to be made first (at the Assembly Station) and taken from your bag.")
			}
		}
		let used: Set<Int> = Set(plan.pieces.map { $0.src })
		plan.items = plan.items.filter { used.contains($0.key) }
		if plan.nextID <= (plan.pieces.map { $0.id }.max() ?? 0) { plan.nextID = (plan.pieces.map { $0.id }.max() ?? 0) + 1 }
		let b: SuitBill = suit.d.bill(to: plan)
		if !isCreative {
			for (it, n) in b.pay where inv.total(it) < n {
				return joinText("Not enough ", it.name, ": it takes ", String(n), " and you have ", String(inv.total(it)), ". Nothing was changed.")
			}
			var bag: [Stack?] = inv.slots
			for st in b.take {
				guard let i = bag.firstIndex(where: { $0 == st }) else { return joinText(st.item.name, " is no longer in your bag: nothing was changed.") }
				bag[i] = nil
			}
			inv.slots = bag
			for (it, n) in b.pay { _ = inv.remove(it, n) }
			for (it, n) in b.back { giveItems(it, n) }
			for st in b.give { addStack(st) }
		}
		let wasWorn: Bool = suit.worn
		suit.d = plan
		let st: ExoStats = ExoStats.of(plan)
		suit.energy = min(suit.energy, st.capacity)
		if !st.has(.cargo) { emptyPack() }
		if wasWorn && !st.complete { suit.worn = false }
		suitChanged()
		sfx(.craft, 0.7)
		if wasWorn && !st.complete { return "Built. The suit came off: it has no pieces." }
		return wasWorn ? "Built and still on." : "Built."
	}

	/// Mends every damaged and broken piece, paying its share of its metal (cores and parts: copper).
	/// Returns what to say.
	@discardableResult
	func repairSuit() -> String {
		let bill: [Item: Int] = suit.d.repairBill()
		if bill.isEmpty { return "Nothing needs mending." }
		if !isCreative {
			for (it, n) in bill where inv.total(it) < n {
				return joinText("Mending takes ", String(n), " ", it.name, " (you have ", String(inv.total(it)), ").")
			}
			for (it, n) in bill { _ = inv.remove(it, n) }
		}
		var d: SuitDesign = suit.d
		for k in d.pieces.indices { d.pieces[k].dmg = 0 }
		suit.d = d
		suitChanged()
		sfx(.craft, 0.6)
		return "Every piece is whole again."
	}

	/// Opens the cargo pack (stored like a chest, under a key no block can have)
	func openPack() {
		if !(suit.worn && suitStats.has(.cargo)) { return }
		let k: IntPair = packSpot
		// the pack is kept with the realm the player is in: bring it along from the other one
		for d in 0..<dimCount where d != world.dim.rawValue {
			let other: ChestKey = ChestKey(d: d, x: k.x, y: k.y)
			if let items = world.chests[other] {
				let here: ChestKey = world.chestKey(k.x, k.y)
				world.chests[here] = (world.chests[here] ?? []) + items
				world.chests[other] = nil
			}
		}
		if world.chests[world.chestKey(k.x, k.y)] == nil { world.setChestItems(k.x, k.y, []) }
		openChest = k
		showInventory = true
		sfx(.chestOpen, 0.6)
		bumpHUD()
	}

	/// Everything in the cargo pack goes into the bag (or at the player's feet)
	func emptyPack() {
		let k: IntPair = packSpot
		for d in 0..<dimCount {
			let key: ChestKey = ChestKey(d: d, x: k.x, y: k.y)
			if let items = world.chests[key] {
				world.chests[key] = nil
				for st in items { addStack(st) }
			}
		}
		if let p = openChest, isPackSpot(p) { openChest = nil }
	}

	/// The pack's storage key (outside any block a world can have)
	var packSpot: IntPair { return IntPair(x: -1_900_000_000, y: -88) }

	/// The pack's storage lives in the overworld's chest list wherever the player is: it travels along
	func isPackSpot(_ p: IntPair) -> Bool { return p.y == -88 && p.x == -1_900_000_000 }

	// MARK: charging

	/// The assembly station charges a worn suit nearby from the power line it is wired to (it takes
	/// sparks from the network only while it has a suit to charge)
	func runSuitDock(_ d: PowerDev, _ dt: Double) {
		let near: Bool = suit.worn && abs(Double(d.x) + 0.5 - pb.x) < 4.5 && abs(Double(d.y) + 0.5 - pb.cy) < 4.0
		let st: ExoStats = suitStats
		let wants: Bool = near && suit.energy < st.capacity - 0.01
		if d.enabled != wants { d.enabled = wants }
		if wants && d.powered {
			suit.energy = min(st.capacity, suit.energy + PowerSpec.draw(.exoStation) * dt)
			if frameNo % 20 == 0 { spawnParticles(pb.x, pb.y - 1.0, 0x60E0FF, 1, 1.5, 0.3, -2) }
		}
	}

	/// Tapping a battery or accumulator while wearing the suit fills it from the stored charge
	func chargeSuitFrom(_ d: PowerDev) -> Bool {
		if !suit.worn { return false }
		let st: ExoStats = suitStats
		let room: Double = st.capacity - suit.energy
		if room <= 0.5 {
			say("The suit is full.", 1.2)
			return true
		}
		let take: Double = min(room, d.charge)
		if take < 0.5 {
			say("That battery is empty.", 1.2)
			return true
		}
		d.charge -= take
		suit.energy += take
		sfx(.zap, 0.5)
		say(joinText("The suit takes ", String(Int(take.rounded())), " from the battery (", String(Int(suit.energy)), " of ", String(Int(st.capacity)), ")."), 2.0)
		return true
	}

	/// What the player's sprite is drawn from: the suit's pieces and how damaged they look (0: no suit)
	var suitDrawKey: Int {
		if !suit.worn { return 0 }
		var h: Hasher = Hasher()
		for p in suit.d.pieces {
			h.combine(p.id)
			h.combine(p.x)
			h.combine(p.y)
			h.combine(p.w)
			h.combine(p.h)
			h.combine(p.rot)
			h.combine(p.shape.rawValue)
			h.combine(p.bone.rawValue)
			h.combine(suitColor(p))
			h.combine(Int(p.dmg * 3.0))
		}
		return h.finalize() | 1
	}
}

extension ExoSuit {
	/// A suit built the old way (a part in each place) rebuilt piece by piece: each part becomes the
	/// pieces that cover what it covered, in its metal. The parts themselves stay with the design (their
	/// infusions still count) and come back to the bag when all their pieces are taken off.
	mutating func migrate() {
		if parts.isEmpty {
			if design == nil { design = SuitDesign() }
			return
		}
		var d: SuitDesign = design ?? SuitDesign()
		for slot in ExoSlot.allCases {
			guard let st = parts[slot.rawValue] else { continue }
			let g: Int = d.newGroup()
			d.items[g] = st
			for p0 in SuitTemplates.oldPart(slot, st.item) {
				var p: SuitPiece = p0
				p.id = d.newID()
				p.src = g
				d.pieces.append(p)
			}
		}
		parts = [:]
		design = d
	}
}

/// Ready-made pieces: what a part of a suit built the old way turns into, where a new working part
/// goes first, and whole designs to start from
enum SuitTemplates {
	/// a piece: centre and size in sprite pixels (columns from the figure's left edge, rows from the
	/// frame's top), made of a metal
	static func piece(_ kind: SuitKind, _ bone: SuitBone, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ m: ExoMat, _ shape: SuitShape = .box) -> SuitPiece {
		var p = SuitPiece()
		let u: Double = Double(suitUnit)
		p.kind = kind
		p.bone = bone
		p.x = cx * u
		p.y = cy * u
		p.w = w * u
		p.h = h * u
		p.mat = m.rawValue
		p.shape = shape
		return p
	}

	/// a working part where it first goes on the body
	static func module(_ m: ExoModule) -> SuitPiece {
		var p: SuitPiece
		switch m {
		case .drill: p = piece(.module, .armFront, 9.5, 9.5, 1.6, 1.0, .iron, .spike); p.rot = 90
		case .gauntlet: p = piece(.module, .armBack, 1.5, 9.8, 2.0, 0.8, .iron)
		case .servo: p = piece(.module, .torso, 5.0, 7.0, 2.6, 0.7, .iron, .rounded)
		case .sprint: p = piece(.module, .legFront, 7.0, 13.5, 1.4, 1.2, .iron)
		case .leap: p = piece(.module, .legBack, 3.0, 15.6, 1.8, 0.6, .iron)
		case .hover: p = piece(.module, .back, -0.5, 10.0, 1.4, 2.4, .iron, .rounded)
		case .lamp: p = piece(.module, .head, 7.6, 2.6, 1.0, 1.0, .iron, .round)
		case .seal: p = piece(.module, .head, 5.0, 5.6, 4.0, 0.6, .iron)
		case .cargo: p = piece(.module, .back, -1.0, 9.0, 2.4, 4.0, .iron, .rounded)
		case .barrier: p = piece(.module, .torso, 5.0, 10.0, 1.4, 1.4, .iron, .round)
		case .wing: p = piece(.module, .back, -3.0, 8.0, 5.0, 2.2, .iron, .wedge); p.rot = -20
		case .battery: p = piece(.module, .back, 0.2, 8.4, 1.2, 2.4, .iron)
		case .solar: p = piece(.module, .back, -1.6, 6.6, 3.0, 0.6, .iron)
		case .turret: p = piece(.module, .torso, 5.2, 6.6, 1.6, 1.2, .iron, .rounded)
		case .cannon: p = piece(.module, .torso, 6.8, 6.8, 3.0, 1.0, .iron)
		case .laser: p = piece(.module, .armFront, 9.2, 8.6, 1.8, 0.8, .iron)
		case .magnet: p = piece(.module, .torso, 4.0, 9.6, 1.2, 1.2, .iron, .round)
		}
		p.part = m.rawValue
		return p
	}

	/// a power core over the heart
	static func core(_ c: ExoCore) -> SuitPiece {
		var p: SuitPiece = piece(.core, .torso, 5.0, 8.3, 1.6, 1.6, .iron, .round)
		p.part = c.rawValue
		return p
	}

	/// The pieces a part of a suit built the old way becomes
	static func oldPart(_ slot: ExoSlot, _ it: Item) -> [SuitPiece] {
		switch it {
		case .exoCore(let c): return [core(c)]
		case .exoModule(let m): return [module(m)]
		case .exoPart(_, let m), .exoPlate(let m):
			switch slot {
			case .helmet:
				var visor: SuitPiece = piece(.frame, .head, 6.0, 3.5, 4.0, 1.0, m)
				visor.color = 0x60E0FF
				return [piece(.plate, .head, 5.0, 3.5, 6.0, 5.0, m, .rounded), visor]
			case .chest: return [piece(.plate, .torso, 5.0, 9.0, 4.0, 6.0, m)]
			case .armL: return [piece(.plate, .armBack, 2.0, 8.5, 2.0, 3.0, m)]
			case .armR: return [piece(.plate, .armFront, 8.0, 8.5, 2.0, 3.0, m)]
			case .legs: return [piece(.plate, .legBack, 3.0, 13.5, 2.0, 3.0, m), piece(.plate, .legFront, 7.0, 13.5, 2.0, 3.0, m)]
			case .boots: return [piece(.plate, .legBack, 3.0, 15.5, 2.2, 1.0, m), piece(.plate, .legFront, 7.0, 15.5, 2.2, 1.0, m)]
			case .plateHead: return [piece(.plate, .head, 5.0, 1.5, 4.0, 1.0, m)]
			case .plateShoulders: return [piece(.plate, .armBack, 2.0, 7.5, 2.4, 1.0, m, .rounded), piece(.plate, .armFront, 8.0, 7.5, 2.4, 1.0, m, .rounded)]
			case .plateChest: return [piece(.plate, .torso, 5.0, 8.0, 4.0, 2.0, m)]
			case .plateArms: return [piece(.plate, .armBack, 2.0, 9.5, 2.0, 1.0, m), piece(.plate, .armFront, 8.0, 9.5, 2.0, 1.0, m)]
			case .plateLegs: return [piece(.plate, .legBack, 3.0, 13.5, 2.0, 1.0, m), piece(.plate, .legFront, 7.0, 13.5, 2.0, 1.0, m)]
			default: return []
			}
		default: return []
		}
	}

	/// Whole designs to start from: a light suit, a knight's, a heavy one, and a flyer's
	static let names: [String] = ["Empty", "Light", "Knight", "Heavy", "Flyer"]

	static func design(_ i: Int, _ m: ExoMat) -> SuitDesign {
		var d = SuitDesign()
		var ps: [SuitPiece] = []
		func plate(_ b: SuitBone, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ s: SuitShape = .box, thick: Int = 1, rot: Double = 0) {
			var p: SuitPiece = piece(.plate, b, cx, cy, w, h, m, s)
			p.thick = thick
			p.rot = rot
			ps.append(p)
		}
		switch i {
		case 1:
			plate(.head, 5.0, 2.0, 5.0, 2.4, .rounded)
			plate(.torso, 5.0, 8.4, 4.0, 3.4)
			plate(.legBack, 3.0, 13.6, 2.0, 2.0)
			plate(.legFront, 7.0, 13.6, 2.0, 2.0)
		case 2:
			plate(.head, 5.0, 3.0, 6.0, 4.4, .rounded)
			var visor: SuitPiece = piece(.frame, .head, 6.2, 3.4, 3.6, 0.7, m)
			visor.color = 0x2A2E36
			ps.append(visor)
			plate(.head, 5.0, 0.8, 1.0, 1.6, .spike)
			plate(.torso, 5.0, 8.6, 4.0, 4.2)
			plate(.torso, 5.0, 10.6, 6.0, 1.0)
			plate(.armBack, 2.0, 7.4, 2.8, 1.4, .rounded)
			plate(.armFront, 8.0, 7.4, 2.8, 1.4, .rounded)
			plate(.armBack, 2.0, 9.0, 2.0, 2.0)
			plate(.armFront, 8.0, 9.0, 2.0, 2.0)
			plate(.legBack, 3.0, 13.4, 2.0, 3.0)
			plate(.legFront, 7.0, 13.4, 2.0, 3.0)
			plate(.legBack, 3.0, 15.5, 2.4, 1.0, .rounded)
			plate(.legFront, 7.0, 15.5, 2.4, 1.0, .rounded)
		case 3:
			plate(.head, 5.0, 3.0, 6.4, 5.0, .rounded, thick: 2)
			plate(.torso, 5.0, 8.8, 4.6, 5.0, thick: 2)
			plate(.torso, 5.0, 8.4, 3.0, 2.0, thick: 1)
			plate(.armBack, 2.0, 7.3, 3.2, 1.8, .rounded, thick: 2)
			plate(.armFront, 8.0, 7.3, 3.2, 1.8, .rounded, thick: 2)
			plate(.armBack, 2.0, 9.0, 2.2, 2.4, thick: 2)
			plate(.armFront, 8.0, 9.0, 2.2, 2.4, thick: 2)
			plate(.torso, 5.0, 11.0, 6.4, 1.6, thick: 2)
			plate(.legBack, 3.0, 13.5, 2.4, 3.2, thick: 2)
			plate(.legFront, 7.0, 13.5, 2.4, 3.2, thick: 2)
			plate(.legBack, 3.0, 15.4, 2.8, 1.4, .rounded, thick: 2)
			plate(.legFront, 7.0, 15.4, 2.8, 1.4, .rounded, thick: 2)
		case 4:
			plate(.head, 5.0, 2.6, 5.4, 3.6, .rounded)
			plate(.torso, 5.0, 8.6, 4.0, 3.6)
			plate(.legBack, 3.0, 13.6, 2.0, 2.4)
			plate(.legFront, 7.0, 13.6, 2.0, 2.4)
			var w: SuitPiece = module(.wing)
			w.mat = m.rawValue
			ps.append(w)
			var j1: SuitPiece = module(.hover)
			j1.mat = m.rawValue
			ps.append(j1)
			var j2: SuitPiece = module(.hover)
			j2.mat = m.rawValue
			j2.y += 6
			ps.append(j2)
		default: break
		}
		for var p in ps {
			p.id = d.newID()
			d.pieces.append(p)
		}
		return d
	}
}

// MARK: - Suits in mods: materials, parts and whole designs

/// A metal (or any material) of a mod's for suit pieces: its colour and numbers, and what it is paid with
struct ModSuitMat: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Metal"
	var color: UInt32 = 0x8AC8E8
	var protect: Double = 1.2
	var weight: Double = 1.0
	var durability: Double = 1.2
	var conduct: Double = 1.0
	var fireCut: Double = 0
	var coldCut: Double = 0
	var stormCut: Double = 0
	/// what a unit of it is paid with (nil: iron bars)
	var cost: Item? = nil
	var drillTier: Int = 4

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Metal")
		color = c.val(.color, 0x8AC8E8)
		protect = c.val(.protect, 1.2)
		weight = c.val(.weight, 1.0)
		durability = c.val(.durability, 1.2)
		conduct = c.val(.conduct, 1.0)
		fireCut = c.val(.fireCut, 0)
		coldCut = c.val(.coldCut, 0)
		stormCut = c.val(.stormCut, 0)
		cost = c.val(.cost, nil)
		drillTier = c.val(.drillTier, 4)
	}
}

/// A working part of a mod's for suits: an item (made by the mod's recipes) that, placed on a suit,
/// works as one of the game's parts at its own strength, weight and colour
struct ModSuitPart: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Part"
	var desc: String = ""
	var works: ExoModule = .turret
	/// how strong it is at its work (1: as the game's own part)
	var power: Double = 1.0
	var weight: Double = 2.0
	var color: UInt32 = 0x8A929E
	/// its icon (blank: the game part's, in its colour)
	var icon: ModPixels = ModPixels(w: 12, h: 12)

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Part")
		desc = c.val(.desc, "")
		works = c.val(.works, .turret)
		power = c.val(.power, 1.0)
		weight = c.val(.weight, 2.0)
		color = c.val(.color, 0x8A929E)
		icon = c.val(.icon, ModPixels(w: 12, h: 12))
	}
}

/// A whole suit design kept in a mod, to start from at an Assembly Station
struct ModSuitDesign: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Suit"
	var design: SuitDesign = SuitDesign()

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Suit")
		design = c.val(.design, SuitDesign())
	}
}

/// The limits on a mod's suit content
enum ModSuitLimits {
	static let mats: Int = 12
	static let parts: Int = 24
	static let designs: Int = 12
}

extension ModValidator {
	/// A mod's suit materials, parts and designs kept in range: numbers within limits, what a metal is
	/// paid with an item that exists, designs only of what the suit allows and of this mod's own
	/// materials and parts
	static func checkSuits(_ p: inout ModPack, _ mn: String, _ sb: Bool, _ known: [String: String], _ r: inout ModReport) {
		func c(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double { return clampD(v.isFinite ? v : d, lo, hi) }
		if p.suitMats.count > ModSuitLimits.mats {
			r.add(1, mn, "Mod", joinText("Only ", String(ModSuitLimits.mats), " suit materials fit in one mod; the rest were left out."))
			p.suitMats = Array(p.suitMats.prefix(ModSuitLimits.mats))
		}
		if p.suitParts.count > ModSuitLimits.parts {
			r.add(1, mn, "Mod", joinText("Only ", String(ModSuitLimits.parts), " suit parts fit in one mod; the rest were left out."))
			p.suitParts = Array(p.suitParts.prefix(ModSuitLimits.parts))
		}
		if p.suitDesigns.count > ModSuitLimits.designs {
			r.add(1, mn, "Mod", joinText("Only ", String(ModSuitLimits.designs), " suit designs fit in one mod; the rest were left out."))
			p.suitDesigns = Array(p.suitDesigns.prefix(ModSuitLimits.designs))
		}
		let ownItems: Set<String> = Set(p.items.map { p.key($0.id) } + p.suitParts.map { p.key($0.id) })
		var used: Set<String> = Set(p.blocks.map { $0.id } + p.items.map { $0.id } + p.mobs.map { $0.id } + p.infusions.map { $0.id } + p.dims.map { $0.id } + p.trees.map { $0.id })
		func fresh(_ id: String, _ pre: String, _ i: Int) -> String {
			if !id.isEmpty && !used.contains(id) { return id }
			return joinText(pre, String(i + 1), "x", String(used.count))
		}
		for i in p.suitMats.indices {
			var m: ModSuitMat = p.suitMats[i]
			m.id = fresh(m.id, "smat", i)
			used.insert(m.id)
			if m.name.trimmingCharacters(in: .whitespaces).isEmpty { m.name = "Metal" }
			m.name = String(m.name.prefix(24))
			m.protect = c(m.protect, 0.2, sb ? 6 : 3, 1)
			m.weight = c(m.weight, 0.2, sb ? 6 : 3, 1)
			m.durability = c(m.durability, 0.2, sb ? 8 : 4, 1)
			m.conduct = c(m.conduct, 0.5, sb ? 4 : 2, 1)
			m.fireCut = c(m.fireCut, 0, 0.1, 0)
			m.coldCut = c(m.coldCut, 0, 0.1, 0)
			m.stormCut = c(m.stormCut, 0, 0.1, 0)
			m.drillTier = clampI(m.drillTier, 0, 9)
			if let it = m.cost, case .custom(let k) = it, !ownItems.contains(k) && known[k] != "item" {
				r.add(1, mn, joinText("Suit material \u{201C}", m.name, "\u{201D}"), "What it is paid with does not exist; iron bars stand in.")
				m.cost = nil
			}
			p.suitMats[i] = m
		}
		for i in p.suitParts.indices {
			var sp: ModSuitPart = p.suitParts[i]
			sp.id = fresh(sp.id, "spart", i)
			used.insert(sp.id)
			if sp.name.trimmingCharacters(in: .whitespaces).isEmpty { sp.name = "Part" }
			sp.name = String(sp.name.prefix(24))
			sp.desc = String(sp.desc.prefix(120))
			sp.power = c(sp.power, 0.25, sb ? 10 : 4, 1)
			sp.weight = c(sp.weight, 0, sb ? 30 : 10, 2)
			if !sp.icon.valid || sp.icon.w > 32 || sp.icon.h > 32 { sp.icon = ModPixels(w: 12, h: 12) }
			p.suitParts[i] = sp
		}
		let mats: Set<String> = Set(p.suitMats.map { p.key($0.id) })
		let parts: Set<String> = Set(p.suitParts.map { p.key($0.id) })
		for i in p.suitDesigns.indices {
			var d: ModSuitDesign = p.suitDesigns[i]
			d.id = fresh(d.id, "suit", i)
			used.insert(d.id)
			if d.name.trimmingCharacters(in: .whitespaces).isEmpty { d.name = "Suit" }
			d.name = String(d.name.prefix(24))
			var g: SuitDesign = d.design
			if g.pieces.count > SuitDesign.maxPieces { g.pieces = Array(g.pieces.prefix(SuitDesign.maxPieces)) }
			var keep: [SuitPiece] = []
			for var piece in g.pieces {
				piece.clamp()
				piece.dmg = 0
				piece.src = 0
				if !piece.modMat.isEmpty && !mats.contains(piece.modMat) && known[piece.modMat] != "suitmat" { piece.modMat = "" }
				if !piece.modPart.isEmpty && !parts.contains(piece.modPart) && known[piece.modPart] != "item" { continue }
				keep.append(piece)
			}
			g.pieces = keep
			g.items = [:]
			d.design = g
			p.suitDesigns[i] = d
		}
	}
}

extension ModRuntime {
	/// The mods' suit materials and parts, ready for play (each part is also an item, see buildItems)
	func buildSuits() {
		for p in packs {
			for m in p.suitMats where !disabled.contains(p.key(m.id)) {
				var i = SuitMatInfo()
				i.name = m.name
				i.color = m.color & 0xFFFFFF
				i.protect = m.protect
				i.weight = m.weight
				i.durability = m.durability
				i.conduct = m.conduct
				i.fireCut = m.fireCut
				i.coldCut = m.coldCut
				i.stormCut = m.stormCut
				i.cost = m.cost.map { resolve($0) } ?? .mat(.ironBar)
				i.drillTier = m.drillTier
				suitMats[p.key(m.id)] = i
			}
			for sp in p.suitParts where !disabled.contains(p.key(sp.id)) {
				var i = SuitPartInfo()
				i.name = sp.name
				i.color = sp.color & 0xFFFFFF
				i.works = sp.works
				i.power = sp.power
				i.weight = sp.weight
				suitParts[p.key(sp.id)] = i
			}
			for d in p.suitDesigns where !disabled.contains(p.key(d.id)) {
				suitDesigns.append((joinText(d.name, " (", p.name, ")"), d.design))
			}
		}
	}

	/// A suit part as an item: held, crafted by the mod's recipes, placed at an Assembly Station
	func suitPartItem(_ p: ModPack, _ sp: ModSuitPart) -> ModItem {
		var it = ModItem()
		it.id = sp.id
		it.name = sp.name
		it.desc = sp.desc.isEmpty ? joinText("A suit part: works as a ", sp.works.name.lowercased(), ". Place it on a suit at an Assembly Station.") : sp.desc
		it.kind = .material
		it.stack = 1
		it.rarity = 2
		if sp.icon.isBlank {
			it.baseIcon = .exoModule(sp.works)
			it.tint = sp.color
			it.tintAmt = 0.5
		} else {
			it.icon = sp.icon
		}
		return it
	}
}

// MARK: - Alchemy, infusion and suit art

/// A potion's icon: a round flask for a drink, a squat strapped flask for a splash, the mutagen glowing
func iconPotion(_ p: Potion) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let liq: UInt32 = p.color
	let glass: UInt32 = 0xCFEFFF
	if p.thrown {
		b.rect(5, 0, 2, 1, 0x5A4A3A)
		b.rect(4, 1, 4, 2, glass)
		b.rect(2, 3, 8, 8, glass)
		b.rect(3, 5, 6, 5, liq)
		b.rect(3, 9, 6, 1, shadeRGB(liq, 0.75))
		b.rect(2, 4, 8, 1, 0x7A5A3A)
		b.set(4, 6, shadeRGB(liq, 1.45))
		b.set(8, 4, 0xFFFFFF)
		if p == .mutagen {
			b.set(5, 7, 0xC07CFF)
			b.set(7, 6, 0xC07CFF)
			b.set(6, 8, 0xE0B8FF)
		}
	} else {
		b.rect(5, 0, 2, 1, 0x8A5A2A)
		b.rect(5, 1, 2, 2, glass)
		b.ellipse(6, 7.5, 4.0, 3.8, glass)
		b.ellipse(6, 8.2, 3.2, 2.9, liq)
		b.ellipse(4.8, 7.0, 1.0, 0.8, shadeRGB(liq, 1.45))
		b.set(8, 5, 0xFFFFFF)
		if p == .greaterMending { b.set(6, 3, 0xFFD040) }
	}
	b.outline(0x1A1410)
	return b
}

/// An infusion compound's icon: a stoppered phial with a swirl in the infusion's colour, ringed in
/// its rarity's colour
func iconCompound(_ i: Infusion) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let c: UInt32 = i.color
	let ring: UInt32 = i.rarity.color
	b.rect(5, 0, 2, 2, 0x6A6E78)
	b.rect(4, 2, 4, 1, ring)
	b.rect(3, 3, 6, 7, 0x2A2A34)
	b.rect(4, 4, 4, 5, c)
	b.set(4, 4, shadeRGB(c, 1.4))
	b.set(6, 6, shadeRGB(c, 0.6))
	b.set(5, 7, shadeRGB(c, 1.3))
	b.rect(3, 10, 6, 1, ring)
	b.outline(0x1A1410)
	return b
}

/// The icon of a suit part, plate, core or module
func iconExo(_ it: Item) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch it {
	case .exoPart(let p, let m):
		let c: UInt32 = m.color
		let hi: UInt32 = shadeRGB(c, 1.25)
		let lo: UInt32 = shadeRGB(c, 0.7)
		switch p {
		case .helmet:
			b.rect(3, 2, 6, 7, c); b.rect(4, 1, 4, 1, c); b.rect(3, 5, 6, 2, 0x60E0FF); b.rect(3, 2, 6, 1, hi); b.rect(3, 8, 6, 1, lo)
		case .chestFrame:
			b.rect(2, 2, 8, 7, c); b.rect(3, 9, 6, 2, lo); b.rect(0, 2, 2, 3, c); b.rect(10, 2, 2, 3, c)
			b.rect(5, 4, 2, 2, 0xFFC830); b.rect(2, 2, 8, 1, hi)
		case .arm:
			b.rect(4, 1, 4, 4, c); b.rect(5, 5, 3, 4, lo); b.rect(5, 9, 3, 2, 0x3A3E48); b.rect(4, 1, 4, 1, hi)
		case .legs:
			b.rect(2, 1, 8, 2, lo); b.rect(2, 3, 3, 8, c); b.rect(7, 3, 3, 8, c); b.rect(2, 6, 3, 1, hi); b.rect(7, 6, 3, 1, hi)
		case .boots:
			b.rect(1, 5, 4, 4, c); b.rect(7, 5, 4, 4, c); b.rect(0, 9, 5, 2, lo); b.rect(7, 9, 5, 2, lo); b.rect(1, 5, 4, 1, hi); b.rect(7, 5, 4, 1, hi)
		}
	case .exoPlate(let m):
		let c: UInt32 = m.color
		b.rect(1, 2, 10, 8, shadeRGB(c, 0.75)); b.rect(2, 3, 8, 6, c); b.rect(2, 3, 8, 1, shadeRGB(c, 1.3))
		b.set(2, 3, 0x3A3E48); b.set(9, 3, 0x3A3E48); b.set(2, 8, 0x3A3E48); b.set(9, 8, 0x3A3E48)
	case .exoCore(let k):
		let c: UInt32 = k.color
		b.ellipse(6, 6, 4.6, 4.6, 0x3A3E48); b.ellipse(6, 6, 3.4, 3.4, shadeRGB(c, 0.7)); b.ellipse(6, 6, 2.2, 2.2, c)
		b.set(5, 5, 0xFFFFFF); b.rect(5, 0, 2, 2, 0x6A6E78); b.rect(5, 10, 2, 2, 0x6A6E78)
	case .exoModule(let m):
		let c: UInt32 = m.color
		b.rect(1, 2, 10, 8, 0x3A3E48); b.rect(2, 3, 8, 6, 0x5A6270)
		switch m {
		case .drill: b.rect(3, 5, 3, 2, c); b.rect(6, 5, 2, 2, shadeRGB(c, 0.8)); b.set(8, 5, c); b.set(9, 6, c)
		case .lamp: b.ellipse(6, 6, 2.2, 2.2, c); b.set(6, 6, 0xFFFFFF)
		case .hover: b.rect(3, 4, 2, 4, 0x9AA4B0); b.rect(7, 4, 2, 4, 0x9AA4B0); b.rect(3, 8, 2, 1, c); b.rect(7, 8, 2, 1, c)
		case .cargo: b.rect(3, 4, 6, 4, c); b.rect(3, 4, 6, 1, shadeRGB(c, 1.3)); b.set(6, 6, 0xE8C060)
		case .barrier: b.ellipse(6, 6, 3.0, 3.0, c); b.ellipse(6, 6, 1.8, 1.8, 0x5A6270)
		case .gauntlet: b.line(3, 8, 6, 4, c); b.line(6, 4, 5, 6, c); b.line(5, 6, 8, 3, c)
		default: b.rect(3, 4, 6, 4, c); b.rect(4, 5, 4, 2, shadeRGB(c, 1.3))
		}
		b.rect(1, 2, 10, 1, shadeRGB(0x5A6270, 1.3))
	default: break
	}
	b.outline(0x1A1410)
	return b
}

// ===== p31b_building =====

// MARK: - Building: blocks placed as walls, ladders built on, furniture, lifts

/// A wall made from any block (as opposed to the seven old wall kinds) is stored in the wall layer as
/// 8 + the block's tile number
let blockWallBase: Int = 8

/// The wall value of a block placed as a wall (0 if it cannot be one)
func blockWallValue(_ t: Tile) -> Int {
	let v: Int = blockWallBase + Int(t.rawValue)
	return v <= 255 ? v : 0
}

/// The block a wall was made from (nil for the old wall kinds)
func blockWallTile(_ k: Int) -> Tile? {
	if k < blockWallBase || k > 255 { return nil }
	return Tile(rawValue: UInt8(k - blockWallBase))
}

/// Blocks that can be put up as a wall instead: anything solid that is only a block (not a machine,
/// a chest, a door, the rift or bedrock)
func canBeWall(_ t: Tile) -> Bool {
	if !t.solid || t.liquid || t.isPower || t.hardness >= 9000 { return false }
	if isDoor(t) || t == .chest || t == .furnace || t == .portalFrame || t == .portalOff || t == .portalOn { return false }
	if t.isMod, let b = ModRuntime.shared.blockDef(t), b.function != .none { return false }
	return blockWallValue(t) > 0
}

/// The words for one piece of furniture (nil for anything else)
func furnitureBlurb(_ t: Tile) -> String? {
	switch t {
	case .chair, .sofa: return "Furniture: tap it to sit down"
	case .bedL, .bedR: return "Furniture: sleep through the night, and wake here"
	case .cabinet, .wardrobe: return "Furniture: keeps things like a chest"
	case .table, .shelf, .bookshelf: return "Furniture: things can stand on top"
	case .floorLamp: return "Furniture: a bright lamp"
	case .stairWoodR, .stairStoneR, .stairBrickR, .stairWoodL, .stairStoneL, .stairBrickL: return "Stairs: walk up them; they face the way you place them"
	case .liftRail: return "Lift: a column of rails for a lift car"
	case .liftButton: return "Lift: beside the rails, calls the car to this floor"
	case .liftCar: return "Lift: place it on a lift rail"
	default: return nil
	}
}

extension Game {
	// MARK: walls

	/// Whether the held item is a block that can go up as a wall (the HUD shows the WALL switch then)
	var canToggleWall: Bool {
		guard let it = heldItem, case .block(let t) = it else { return false }
		return canBeWall(t.placedForm)
	}

	/// The HUD's WALL switch: blocks go up as passable walls, or solid as usual
	func toggleWallMode() {
		wallMode.toggle()
		say(wallMode ? "Blocks now go up as walls you can walk through." : "Blocks now go up solid.", 1.6)
		bumpHUD()
	}

	/// Puts the held block up as a wall behind the aimed spot (passable, drawn darker, mined back into
	/// the block)
	func placeBlockAsWall(_ t: Tile) {
		let v: Int = blockWallValue(t)
		if v == 0 { return }
		usePlaceWall(v)
	}

	// MARK: ladders

	/// Holding a ladder against one already up builds it on: the next rung goes at the end the player
	/// aims toward (down past its foot when aiming level or lower, up past its top when aiming above
	/// the head; it stops when that end is out of reach or blocked), so a long ladder needs no tapping,
	/// never has a gap and never doubles up. Each rung uses one ladder (none in creative, where it can
	/// be built on up to 24 blocks away).
	func extendLadder(_ tx: Int, _ ty: Int) -> Bool {
		if world.tile(tx, ty) != .ladder { return false }
		let up: Bool = aimY < pb.y - pb.h
		for d in [up ? -1 : 1] {
			var y: Int = ty
			var n: Int = 0
			while world.tile(tx, y + d) == .ladder && n < 400 {
				y += d
				n += 1
			}
			let ny: Int = y + d
			if ny < 2 || ny >= world.H - 2 { continue }
			let cur: Tile = world.tile(tx, ny)
			if !(cur == .air || cur.liquid || (cur.isPlant && cur != .torch && cur != .lantern)) { continue }
			// within reach (in creative, anywhere within 24 blocks)
			let near: Bool = isCreative ? abs(Double(ny) + 0.5 - pb.cy) <= 24 && abs(Double(tx) + 0.5 - pb.x) <= 24 : inReach(Double(tx) + 0.5, Double(ny) + 0.5)
			if !near { continue }
			world.set(tx, ny, .ladder)
			world.setBuilt(tx, ny, true)
			if !isCreative { inv.removeAt(sel, 1) }
			sfx(.place, 0.5)
			placeCD = 0.12
			swingT = 0.12
			bumpHUD()
			return true
		}
		return false
	}

	// MARK: furniture

	/// Places a piece of furniture or a stair: a bed takes two tiles (its foot to the right of the
	/// aimed one, or to the left if that is taken), stairs rise away from the player. True when it
	/// was handled (placed or refused); false for anything else.
	func placeSpecial(_ t: Tile, _ tx: Int, _ ty: Int) -> Bool {
		if t == .oreCart { return placeOreCart(tx, ty) }
		if stairSide(t) != 0 {
			let s: Tile = stairSide(t) == 1 ? t : stairMirror(t)
			let placed: Tile = aimX >= pb.x ? s : stairMirror(s)
			if !canPlaceAt(tx, ty, placed) { return true }
			finishPlace(placed, tx, ty)
			return true
		}
		if t == .bedL || t == .bedR {
			if !canPlaceAt(tx, ty, .bedL) { return true }
			var hx: Int = tx
			if !bedSpotFree(tx + 1, ty) {
				if !bedSpotFree(tx - 1, ty) { say("A bed needs two spaces side by side.", 1.5); return true }
				hx = tx - 1
			}
			world.set(hx, ty, .bedL)
			world.set(hx + 1, ty, .bedR)
			world.setBuilt(hx, ty, true)
			world.setBuilt(hx + 1, ty, true)
			if !isCreative { inv.removeAt(sel, 1) }
			sfx(.place, 0.6)
			placeCD = 0.25
			swingT = 0.14
			bumpHUD()
			return true
		}
		if t == .liftCar {
			placeLiftCar(tx, ty)
			return true
		}
		return false
	}

	func bedSpotFree(_ x: Int, _ y: Int) -> Bool {
		let cur: Tile = world.tile(x, y)
		if !(cur == .air || (cur.isPlant && cur != .torch && cur != .lantern)) { return false }
		return world.supports(world.tile(x, y + 1), .bedL)
	}

	/// The common end of placing a block: the tile, its record as something built, the item used up
	func finishPlace(_ placed: Tile, _ tx: Int, _ ty: Int) {
		world.set(tx, ty, placed)
		world.setBuilt(tx, ty, true)
		// a mod block that falls like sand drops at once when put up in the air
		if placed.isMod && fallsLikeSand(placed) { checkFalling(tx, ty) }
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		placeCD = 0.11
		swingT = 0.14
		swingDir = aimFacing()
		facing = swingDir
		bumpHUD()
	}

	/// Sits on a chair or sofa: the player rests on it until they walk or jump off
	func sitOn(_ tx: Int, _ ty: Int) {
		if !isSeat(world.tile(tx, ty)) { return }
		if mounted != nil || inVehicle != nil { return }
		seat = IntPair(x: tx, y: ty)
		pb.x = Double(tx) + 0.5
		pb.y = Double(ty) + 1.0
		pb.vx = 0
		pb.vy = 0
		say("You sit down. Walk or jump to get up.", 1.6)
		bumpHUD()
	}

	/// Keeps a seated player on their seat; false (and standing up) once they move, jump, or the seat
	/// is gone
	func stayInSeat(_ ix: Double, _ jumpPressed: Bool) -> Bool {
		guard let s = seat else { return false }
		if ix != 0 || jumpPressed || downHeld || !isSeat(world.tile(s.x, s.y)) {
			seat = nil
			bumpHUD()
			return false
		}
		pb.x = Double(s.x) + 0.5
		pb.y = Double(s.y) + 1.0
		pb.vx = 0
		pb.vy = 0
		pb.onGround = true
		fallPeak = 0
		return true
	}

	/// A bed: at night, with no monster near, the player sleeps until morning and is healed a little;
	/// at any time it becomes where they wake after dying
	func sleepIn(_ tx: Int, _ ty: Int) {
		let t: Tile = world.tile(tx, ty)
		let modBed: Bool = t.isMod && ModRuntime.shared.bedTiles.contains(t.rawValue)
		if t != .bedL && t != .bedR && !modBed { return }
		let hx: Int = t == .bedR ? tx - 1 : tx
		spawnX = Double(hx) + (modBed ? 0.5 : 1.0)
		spawnY = Double(ty) + 1.0
		if world.dim != .overworld {
			say("This bed is now where you wake up. (Nights only pass in the Overworld.)", 3.0)
			return
		}
		if !isNight {
			say("You can only sleep at night. This bed is now where you wake up.", 2.5)
			return
		}
		for m in mobs where m.hp > 0 && !m.removed && isThreat(m) && abs(m.b.x - pb.x) < 16 && abs(m.b.y - pb.y) < 10 {
			say("You can't sleep now: there are monsters nearby.", 2.0)
			return
		}
		// on to the next morning
		if timeOfDay > 0.5 { dayCount += 1 }
		timeOfDay = 0.02
		hp = min(maxHP, hp + 6.0)
		fadeT = 1.0
		light.valid = false
		say("You sleep until morning. This bed is where you wake up.", 3.0)
		bumpHUD()
	}

	/// A cabinet or wardrobe opens like a chest
	func openStorage(_ tx: Int, _ ty: Int) {
		sfx(.chestOpen, 0.6)
		openChest = IntPair(x: tx, y: ty)
		showInventory = true
		bumpHUD()
	}
}

extension RecipeBook {
	/// Furniture, stairs and lifts (appended after every older recipe, so their numbers stay)
	static func addBuildingRecipes(_ add: (Item, Int, [(Item, Int)], Station, RecipeCat) -> Void) {
		let planks: Item = .block(.planks)
		let stick: Item = .mat(.stick)
		let fe: Item = .mat(.ironBar)
		let cu: Item = .mat(.copperBar)
		let glass: Item = .block(.glass)
		add(.block(.chair), 1, [(planks, 3), (stick, 2)], .bench, .build)
		add(.block(.table), 1, [(planks, 4), (stick, 2)], .bench, .build)
		add(.block(.bedL), 1, [(planks, 4), (.mat(.wool), 3)], .bench, .build)
		add(.block(.cabinet), 1, [(planks, 6), (cu, 1)], .bench, .build)
		add(.block(.wardrobe), 1, [(planks, 8), (cu, 1)], .bench, .build)
		add(.block(.shelf), 2, [(planks, 2), (stick, 1)], .bench, .build)
		add(.block(.bookshelf), 1, [(planks, 6), (.mat(.leather), 2)], .bench, .build)
		add(.block(.floorLamp), 1, [(fe, 1), (glass, 1), (.block(.torch), 1)], .bench, .build)
		add(.block(.sofa), 1, [(planks, 3), (.mat(.wool), 2), (.mat(.leather), 1)], .bench, .build)
		add(.block(.stairWoodR), 4, [(planks, 3)], .bench, .build)
		add(.block(.stairStoneR), 4, [(.block(.stone), 3)], .bench, .build)
		add(.block(.stairBrickR), 4, [(.block(.brick), 3)], .bench, .build)
		add(.block(.liftRail), 4, [(fe, 1), (planks, 2)], .anvil, .build)
		add(.block(.liftButton), 1, [(cu, 1), (.block(.stone), 1)], .bench, .build)
		add(.block(.liftCar), 1, [(fe, 6), (planks, 4), (glass, 2)], .anvil, .build)
	}
}

// MARK: - Lifts

/// An elevator car: a platform three blocks wide riding up and down a column of lift rails, with
/// the rail column in its middle. Floors are where lift buttons stand two blocks beside the rails;
/// the car stops level with the floor of each. Riders, creatures and dropped things standing on it
/// move with it; it stops if anything solid or anybody is in its way.
final class Lift {
	let id: Int
	var x: Int
	/// the car's floor (where a rider's feet are)
	var y: Double
	var vy: Double = 0
	var target: Double? = nil
	/// 0 slow, 1 normal, 2 fast
	var speed: Int = 1
	/// how far it moved this frame
	var dy: Double = 0
	static let speeds: [Double] = [2.5, 4.5, 7.5]
	static let speedNames: [String] = ["slow", "normal", "fast"]

	init(id: Int, x: Int, y: Double) {
		self.id = id
		self.x = x
		self.y = y
	}

	var x0: Double { return Double(x) - 1.0 }
	var x1: Double { return Double(x) + 2.0 }
	var deckID: Int { return 2_000_000 + id }
}

struct LiftSave: Codable {
	var d: Int
	var x: Int
	var y: Double
	var speed: Int
}

extension Game {
	func liftOnColumn(_ x: Int) -> Lift? {
		for l in lifts where l.x == x { return l }
		return nil
	}

	/// The lift whose car covers a point (for taps)
	func liftAt(_ wx: Double, _ wy: Double) -> Lift? {
		for l in lifts where wx >= l.x0 && wx < l.x1 && wy >= l.y - 3.2 && wy <= l.y + 0.4 { return l }
		return nil
	}

	/// Whether the car can be at floor height y: a rail in the cell above its floor, and nothing solid
	/// in the three cells across its floor's row or the two rows above it
	func liftCanBe(_ l: Lift, _ y: Double) -> Bool {
		let row: Int = Int(floor(y - 0.001))
		if world.tile(l.x, row) != .liftRail { return false }
		for dx in -1...1 {
			for r in (row - 1)...row where world.tile(l.x + dx, r).solid { return false }
		}
		return true
	}

	/// The floors of a lift: rows beside its rails with a lift button, reachable along unbroken rail
	func liftStops(_ l: Lift) -> [Double] {
		var out: [Double] = []
		let row0: Int = Int(floor(l.y - 0.001))
		for dir in [-1, 1] {
			var r: Int = row0
			var n: Int = 0
			while world.tile(l.x, r) == .liftRail && n < 300 {
				if world.tile(l.x - 2, r) == .liftButton || world.tile(l.x + 2, r) == .liftButton { out.append(Double(r + 1)) }
				r += dir
				n += 1
			}
		}
		return Array(Set(out)).sorted()
	}

	/// Puts a lift car on the rail at the aimed spot, its floor at the bottom of that rail cell
	func placeLiftCar(_ tx: Int, _ ty: Int) {
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return }
		if world.tile(tx, ty) != .liftRail {
			say("Place the lift car on a lift rail.", 1.6)
			placeCD = 0.3
			return
		}
		if liftOnColumn(tx) != nil {
			say("This rail already has a car.", 1.6)
			placeCD = 0.3
			return
		}
		let l: Lift = Lift(id: newID(), x: tx, y: Double(ty + 1))
		if !liftCanBe(l, l.y) {
			say("The car needs three blocks of clear space across the rail.", 2.0)
			placeCD = 0.3
			return
		}
		lifts.append(l)
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.7)
		placeCD = 0.3
		say("Lift car placed. Buttons two blocks beside the rails make floors.", 2.5)
		bumpHUD()
	}

	/// Sends a lift to the floor at y (true if it can go there)
	@discardableResult
	func sendLift(_ l: Lift, _ y: Double) -> Bool {
		if abs(l.y - y) < 0.02 { return false }
		l.target = y
		sfx(.tap, 0.6)
		return true
	}

	/// A tap on a lift button calls the car to this floor
	func callLift(_ bx: Int, _ by: Int) {
		for x in [bx - 2, bx + 2] {
			guard let l = liftOnColumn(x) else { continue }
			let y: Double = Double(by + 1)
			if liftStops(l).contains(y) {
				if !sendLift(l, y) { say("The lift is here.", 1.2) }
				return
			}
		}
		say("No lift car on rails beside this button.", 1.6)
	}

	/// A tap on the car: up to the next floor when tapping its upper half, down when tapping low
	func rideLiftTap(_ l: Lift, _ wy: Double) {
		let up: Bool = wy < l.y - 1.5
		let stops: [Double] = liftStops(l)
		let from: Double = l.target ?? l.y
		let next: Double? = up ? stops.filter { $0 < from - 0.02 }.max() : stops.filter { $0 > from + 0.02 }.min()
		if let n = next {
			sendLift(l, n)
		} else {
			say(up ? "No floor above." : "No floor below.", 1.2)
		}
	}

	/// The wrench: on a lift button it changes the car's speed, on the car it packs the car up
	func wrenchLift(_ wx: Double, _ wy: Double) -> Bool {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		if world.tile(tx, ty) == .liftButton {
			for x in [tx - 2, tx + 2] {
				guard let l = liftOnColumn(x) else { continue }
				l.speed = (l.speed + 1) % Lift.speeds.count
				say(joinText("Lift speed: ", Lift.speedNames[l.speed], "."), 1.5)
				return true
			}
			return false
		}
		if let l = liftAt(wx, wy) {
			lifts.removeAll { $0 === l }
			spawnDrop(Stack(item: .block(.liftCar), count: 1), Double(l.x) + 0.5, l.y - 0.5, 0, -2)
			say("Lift car packed up.", 1.2)
			return true
		}
		return false
	}

	/// Moves the lifts: each eases toward its floor; riders standing on it move with it. A car whose
	/// rail is gone falls apart into its item.
	func updateLifts(_ dt: Double) {
		if lifts.isEmpty { return }
		var gone: [Lift] = []
		for l in lifts {
			l.dy = 0
			if !liftCanBe(l, l.y) && world.tile(l.x, Int(floor(l.y - 0.001))) != .liftRail {
				gone.append(l)
				continue
			}
			guard let t = l.target else { continue }
			let dist: Double = t - l.y
			if abs(dist) < 0.01 {
				l.y = t
				l.vy = 0
				l.target = nil
				sfx(.door, at: Double(l.x), 0.4)
				continue
			}
			let vmax: Double = Lift.speeds[clampI(l.speed, 0, Lift.speeds.count - 1)]
			let acc: Double = 7.0
			let want: Double = (dist > 0 ? 1.0 : -1.0) * min(vmax, sqrt(2.0 * acc * abs(dist)) + 0.3)
			l.vy += clampD(want - l.vy, -acc * dt, acc * dt)
			var step: Double = l.vy * dt
			if abs(step) > abs(dist) { step = dist }
			let ny: Double = l.y + step
			if !liftCanBe(l, ny) || (step > 0 && liftBlockedBelow(l, ny)) {
				l.vy = 0
				l.target = nil
				say("The lift is blocked.", 1.2)
				continue
			}
			carryOnLift(l, step)
			l.y = ny
			l.dy = step
		}
		for l in gone {
			lifts.removeAll { $0 === l }
			spawnDrop(Stack(item: .block(.liftCar), count: 1), Double(l.x) + 0.5, l.y - 0.5, 0, -2)
		}
	}

	/// Somebody under the car's floor in the way of a car going down
	func liftBlockedBelow(_ l: Lift, _ ny: Double) -> Bool {
		if !dead && pb.right > l.x0 && pb.left < l.x1 && pb.top < ny && pb.top >= l.y - 0.05 && !(abs(pb.y - l.y) < 0.08) { return true }
		for m in mobsNear(l.x0 - 1, l.x1 + 1) where m.hp > 0 && !m.removed {
			if m.b.right > l.x0 && m.b.left < l.x1 && m.b.top < ny && m.b.top >= l.y - 0.05 && !(abs(m.b.y - l.y) < 0.08) { return true }
		}
		return false
	}

	/// Moves whatever stands on the car's floor along with it
	func carryOnLift(_ l: Lift, _ step: Double) {
		if !dead && pb.right > l.x0 + 0.05 && pb.left < l.x1 - 0.05 && abs(pb.y - l.y) < 0.12 && pb.vy >= -0.5 {
			pb.y = l.y + step
			if step < 0 { pb.vy = min(pb.vy, 0) }
		}
		for m in mobsNear(l.x0 - 1, l.x1 + 1) where m.hp > 0 && !m.removed && !m.def.flying {
			if m.b.right > l.x0 + 0.05 && m.b.left < l.x1 - 0.05 && abs(m.b.y - l.y) < 0.12 && m.b.vy >= -0.5 {
				m.b.y = l.y + step
			}
		}
		for i in 0..<drops.count where drops[i].x > l.x0 && drops[i].x < l.x1 && abs(drops[i].y - l.y) < 0.15 {
			drops[i].y = l.y + step
			drops[i].vy = 0
		}
	}

	func liftSaves() -> [LiftSave] {
		var out: [LiftSave] = []
		for d in 0..<dimCount {
			let list: [Lift] = d == world.dim.rawValue ? lifts : liftStash[d]
			// where the car is now (a rider is saved where they stand, on it)
			for l in list { out.append(LiftSave(d: d, x: l.x, y: l.y, speed: l.speed)) }
		}
		return out
	}

	func restoreLifts(_ saves: [LiftSave]) {
		for s in saves where s.d >= 0 && s.d < dimCount {
			let l: Lift = Lift(id: newID(), x: s.x, y: s.y)
			l.speed = clampI(s.speed, 0, Lift.speeds.count - 1)
			if s.d == world.dim.rawValue { lifts.append(l) } else { liftStash[s.d].append(l) }
		}
	}
}

// ===== p31c_blockphys =====

// MARK: - Block weight, flying blocks and structures

/// A block as building material: how heavy it is (stone 2.5), how much weight can rest on it before
/// it gives way, and how many blocks it can reach out sideways from a support. One table used by
/// blasts, storms, falling blocks and structural physics.
struct BlockPhys {
	var weight: Double
	var carry: Double
	var span: Int
	/// how well wheels, hulls and feet grip it (1: stone and soil; ice far less)
	var grip: Double = 1.0
	/// how much of a blow it gives back (0: none; hay a little)
	var bounce: Double = 0.0
}

enum BlockPhysTable {
	static let table: [BlockPhys] = Tile.allCases.map { blockPhysOf($0) }
}

/// The material numbers of the game's own blocks (mod blocks are worked out from their hardness)
func blockPhysOf(_ t: Tile) -> BlockPhys {
	var p: BlockPhys = blockWeights(t)
	switch t {
	case .ice: p.grip = 0.12
	case .snow: p.grip = 0.6
	case .mud: p.grip = 0.7
	case .sand: p.grip = 0.85
	case .glass, .obsidian: p.grip = 0.75
	case .sandbag: p.grip = 1.15
	case .hay: p.grip = 0.9; p.bounce = 0.3
	case .crate, .planks, .platform: p.bounce = 0.08
	default: break
	}
	return p
}

/// Weight, carry and reach of the game's own blocks
func blockWeights(_ t: Tile) -> BlockPhys {
	switch t {
	case .air, .water, .lava: return BlockPhys(weight: 0, carry: 0, span: 0)
	case .bedrock: return BlockPhys(weight: 20, carry: 9999, span: 9)
	case .grass, .dirt, .farmland, .dryGrass, .jungleGrass, .mossGrass: return BlockPhys(weight: 1.5, carry: 30, span: 1)
	case .mud: return BlockPhys(weight: 1.8, carry: 20, span: 1)
	case .sand: return BlockPhys(weight: 1.6, carry: 20, span: 0)
	case .snow: return BlockPhys(weight: 0.4, carry: 4, span: 1)
	case .ice: return BlockPhys(weight: 0.9, carry: 16, span: 2)
	case .stone, .fossil: return BlockPhys(weight: 2.5, carry: 150, span: 2)
	case .slate: return BlockPhys(weight: 2.7, carry: 160, span: 2)
	case .deepRock: return BlockPhys(weight: 3.0, carry: 200, span: 2)
	case .sandstone: return BlockPhys(weight: 2.2, carry: 90, span: 2)
	case .obsidian: return BlockPhys(weight: 2.6, carry: 260, span: 3)
	case .ashStone: return BlockPhys(weight: 2.4, carry: 120, span: 2)
	case .coal, .saltpeter: return BlockPhys(weight: 2.2, carry: 120, span: 2)
	case .copper, .tin, .diamond, .crystalOre: return BlockPhys(weight: 3.5, carry: 150, span: 2)
	case .iron, .mythril, .emberOre, .voidOre: return BlockPhys(weight: 4.0, carry: 170, span: 2)
	case .silver: return BlockPhys(weight: 4.5, carry: 160, span: 2)
	case .gold: return BlockPhys(weight: 6.0, carry: 140, span: 2)
	case .amethyst: return BlockPhys(weight: 2.6, carry: 120, span: 2)
	case .planks: return BlockPhys(weight: 0.6, carry: 24, span: 4)
	case .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock: return BlockPhys(weight: 0.8, carry: 40, span: 5)
	case .glass: return BlockPhys(weight: 1.0, carry: 6, span: 1)
	case .brick, .mossBrick: return BlockPhys(weight: 2.0, carry: 120, span: 3)
	case .crackedBrick: return BlockPhys(weight: 1.9, carry: 60, span: 2)
	case .stormBrick: return BlockPhys(weight: 2.6, carry: 220, span: 3)
	case .shingles: return BlockPhys(weight: 0.8, carry: 16, span: 4)
	case .hay: return BlockPhys(weight: 0.3, carry: 3, span: 2)
	case .amethystBlock: return BlockPhys(weight: 2.6, carry: 160, span: 3)
	case .sandbag: return BlockPhys(weight: 1.4, carry: 60, span: 1)
	case .crate: return BlockPhys(weight: 0.7, carry: 14, span: 2)
	case .platform: return BlockPhys(weight: 0.3, carry: 8, span: 4)
	case .ladder: return BlockPhys(weight: 0.3, carry: 8, span: 1)
	case .liftRail: return BlockPhys(weight: 1.2, carry: 40, span: 1)
	case .signalPost, .vehicleSensor: return BlockPhys(weight: 0.8, carry: 6, span: 1)
	case .doorClosed, .doorOpen, .shutterClosed, .shutterOpen: return BlockPhys(weight: 0.7, carry: 10, span: 1)
	case .gateClosed, .gateOpen: return BlockPhys(weight: 3.0, carry: 60, span: 2)
	case .stairWoodR, .stairWoodL: return BlockPhys(weight: 0.5, carry: 20, span: 3)
	case .stairStoneR, .stairStoneL: return BlockPhys(weight: 2.0, carry: 120, span: 2)
	case .stairBrickR, .stairBrickL: return BlockPhys(weight: 1.8, carry: 110, span: 2)
	case .chair, .shelf: return BlockPhys(weight: 0.4, carry: 4, span: 1)
	case .table, .floorLamp: return BlockPhys(weight: 0.6, carry: 8, span: 1)
	case .bedL, .bedR: return BlockPhys(weight: 0.8, carry: 8, span: 1)
	case .sofa: return BlockPhys(weight: 1.0, carry: 8, span: 1)
	case .cabinet: return BlockPhys(weight: 1.2, carry: 10, span: 1)
	case .bookshelf: return BlockPhys(weight: 1.4, carry: 10, span: 1)
	case .wardrobe: return BlockPhys(weight: 1.6, carry: 10, span: 1)
	case .chest, .workbench: return BlockPhys(weight: 1.0, carry: 10, span: 1)
	case .furnace, .alchemyStill: return BlockPhys(weight: 3.0, carry: 20, span: 1)
	case .anvil: return BlockPhys(weight: 7.0, carry: 40, span: 1)
	case .torch, .lantern, .cobweb: return BlockPhys(weight: 0.1, carry: 1, span: 1)
	default:
		let d: TileDef = Tile.makeDef(t)
		if isLeafTile(t) || d.plant { return BlockPhys(weight: 0.1, carry: 1, span: 1) }
		return blockPhysFrom(d)
	}
}

/// Material numbers from a block's hardness (mod blocks, and anything without its own entry)
func blockPhysFrom(_ d: TileDef) -> BlockPhys {
	if !d.solid { return BlockPhys(weight: 0.5, carry: 6, span: 1) }
	let w: Double = clampD(0.6 + d.hard * 0.9, 0.3, 8.0)
	return BlockPhys(weight: w, carry: 20.0 + d.hard * 40.0, span: d.hard < 1.0 ? 3 : 2)
}

/// A block's material numbers
func blockPhys(_ t: Tile) -> BlockPhys {
	if t.isMod {
		var p: BlockPhys = blockPhysFrom(t.def)
		if let b = ModRuntime.shared.blockDef(t) {
			if b.weight > 0 { p.weight = b.weight }
			if b.carry > 0 { p.carry = b.carry }
			p.grip = b.grip
			p.bounce = b.bounce
		}
		return p
	}
	let i: Int = Int(t.rawValue)
	return i < BlockPhysTable.table.count ? BlockPhysTable.table[i] : BlockPhys(weight: 1, carry: 20, span: 2)
}

func tileWeight(_ t: Tile) -> Double { return blockPhys(t).weight }

/// Part of a structure: something that holds other blocks up (solid blocks, platforms, ladders,
/// stairs, lift rails); everything else (furniture, machines, torches) only rests on it as a load
func isStructural(_ t: Tile) -> Bool {
	return t.solid || t.isPlatform || t == .ladder || t == .liftRail || stairSide(t) != 0
}

/// The item info line with a block's weight (and, for building blocks, what it holds and reaches)
func weightLine(_ t: Tile) -> String {
	let p: BlockPhys = blockPhys(t)
	if !isStructural(t) { return String(format: "Weight %.1f", p.weight) }
	return joinText(String(format: "Weight %.1f", p.weight), " · holds ", String(Int(p.carry)), " · reaches ", String(p.span))
}

/// How hard a blast has to be to break a block (a blast nearly that strong only knocks it loose)
func blastResist(_ t: Tile) -> Double {
	if Tile.tierTable[t.idx] > 4 { return 99 }
	return t.hardness + tileWeight(t) * 0.25
}

extension World {
	/// Whether the block at (x, y) was put there (by the player, or settled there after being thrown):
	/// what structural physics looks at. The generated land never counts.
	func isBuilt(_ x: Int, _ y: Int) -> Bool {
		if y < 0 || y >= H { return false }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx), !c.built.isEmpty else { return false }
		return c.built[(x - cx * chunkW) * H + y] != 0
	}

	func setBuilt(_ x: Int, _ y: Int, _ on: Bool) {
		if y < 0 || y >= H { return }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return }
		if c.built.isEmpty {
			if !on { return }
			c.built = [UInt8](repeating: 0, count: chunkW * H)
		}
		let i: Int = (x - cx * chunkW) * H + y
		let v: UInt8 = on ? 1 : 0
		if c.built[i] == v { return }
		c.built[i] = v
		c.dirty = true
	}
}

// MARK: flying blocks

extension Game {
	/// Knocks a block loose: it leaves its place and flies with the given speed, by its weight, until
	/// it lands and settles back into a block (see updateFallingBlocks). Too many already flying: it
	/// just breaks.
	func displaceBlock(_ x: Int, _ y: Int, vx: Double, vy: Double) {
		let t: Tile = world.tile(x, y)
		if t == .air || t.liquid { return }
		if fallingBlocks.count >= 120 {
			breakTile(x, y, false, dropChance: 0.4)
			return
		}
		let built: Bool = world.isBuilt(x, y)
		if world.set(x, y, .air) != t { return }
		var fb: FallingBlock = FallingBlock(x: Double(x) + 0.5, y: Double(y) + 1.0, vy: vy, tile: t, uid: newID())
		fb.vx = vx
		fb.mass = max(0.2, tileWeight(t))
		fb.spin = clampD(vx * 0.6, -9, 9)
		fb.built = built
		fb.flung = true
		fallingBlocks.append(fb)
		// what stood on it comes down too
		let above: Tile = world.tile(x, y - 1)
		if world.needsSupport(above) && !world.supports(.air, above) { breakTile(x, y - 1, false) }
	}

	/// What a blast does to the blocks around it, nearest first. Each block takes the blast's strength
	/// where it stands (falling off with distance) against what it can stand (blastResist: its hardness
	/// and weight): strong enough, it is destroyed. If it survives and has room to move, it is knocked
	/// loose and thrown when the blast was nearly strong enough to break it, or when the blast's push
	/// (which reaches further) is more than its weight can hold against: light blocks are thrown from
	/// further off, and fly further. Otherwise it is untouched. Chests and storage keep their place
	/// (and contents).
	func blastBlocks(_ x: Double, _ y: Double, radius: Double, power power0: Double) {
		// a blast breaks blocks by its size as much as by how hard it hits creatures (a mod's explosive
		// shot with little damage still breaks the ground it was made to; a bomb is both)
		let power: Double = max(power0, radius * 7.6)
		let reach: Double = radius + 0.6
		let pushReach: Double = radius + 2.5
		let r: Int = Int(ceil(pushReach))
		let tx: Int = Int(floor(x))
		let ty: Int = Int(floor(y))
		var cells: [(Int, Int, Double)] = []
		for dy in -r...r {
			for dx in -r...r {
				let cx: Double = Double(tx + dx) + 0.5 - x
				let cy: Double = Double(ty + dy) + 0.5 - y
				let d: Double = sqrt(cx * cx + cy * cy)
				if d <= pushReach { cells.append((tx + dx, ty + dy, d)) }
			}
		}
		cells.sort { $0.2 < $1.2 }
		for (cx, cy, d) in cells {
			let t: Tile = world.tile(cx, cy)
			if t == .air || t.liquid || t.hardness >= 9000 { continue }
			if t == .chest || isStorageFurniture(t) || t == .portalOff || t == .portalOn || t == .portalFrame { continue }
			if t.isMod && (ModRuntime.shared.blockDef(t)?.blastProof ?? true) { continue }
			let f: Double = min(1.0, d / reach)
			let blast: Double = power * 0.16 * (1.0 - f * f)
			let shove: Double = power * 0.12 * max(0, 1.0 - d / pushReach)
			let resist: Double = blastResist(t)
			let w: Double = tileWeight(t)
			let hold: Double = w * 0.5 + t.hardness * 0.25
			if blast >= resist {
				breakTile(cx, cy, false, dropChance: 0.35)
			} else if t.solid && (blast >= resist * 0.5 || shove >= hold) && openSide(cx, cy) {
				var ux: Double = Double(cx) + 0.5 - x
				var uy: Double = Double(cy) + 0.5 - y
				let len: Double = max(0.3, sqrt(ux * ux + uy * uy))
				ux /= len
				uy /= len
				let push: Double = clampD((max(blast - resist * 0.5, 0) + shove) * 6.0 / max(0.4, w), 3.0, 16.0)
				// away from the blast where there is room, else out of the open side (up out of a crater)
				let away: Int = ux >= 0 ? 1 : -1
				var vx: Double = ux * push
				var vy: Double = min(-2.5, uy * push - 3.0)
				if !world.solid(cx, cy - 1) {
					if world.solid(cx + away, cy) { vx = ux * push * 0.4 }
					vy = min(vy, -(3.0 + push * 0.7))
				} else if !world.solid(cx + away, cy) {
					vx = Double(away) * push
				} else if !world.solid(cx - away, cy) {
					vx = -Double(away) * push * 0.5
				} else {
					vx = 0
					vy = 0
				}
				displaceBlock(cx, cy, vx: vx, vy: vy)
			}
		}
	}

	/// Whether a block has room to move: anything not solid beside, above or below it (a block buried in
	/// the ground stays put; the edge of a fresh crater has room)
	func openSide(_ x: Int, _ y: Int) -> Bool {
		return !world.solid(x - 1, y) || !world.solid(x + 1, y) || !world.solid(x, y - 1) || !world.solid(x, y + 1)
	}

	/// A storm tears a block loose: plants, leaves and the like are broken off; a building block is
	/// lifted and carried, by its weight (see the wind in updateFallingBlocks)
	func stormTear(_ x: Int, _ y: Int, _ windDir: Double) {
		let t: Tile = world.tile(x, y)
		if t.solid && !t.liquid && t.hardness < 9000 && !isStorageFurniture(t) && t != .chest {
			let light: Double = 1.0 / max(0.3, tileWeight(t))
			displaceBlock(x, y, vx: windDir * clampD(4.0 * light, 1.5, 9.0), vy: -clampD(3.0 + 4.0 * light, 3.0, 10.0))
		} else {
			breakTile(x, y, false, dropChance: 0.5)
		}
	}

	/// The wind on a flying block: a tornado's swirl and lift, a hurricane's gale, felt less by heavy
	/// blocks
	func windOnBlock(_ fb: inout FallingBlock, _ dt: Double) {
		if weather.tornado == nil && weather.hurricane == nil { return }
		let light: Double = 1.0 / (1.0 + fb.mass)
		let tf: (Double, Double, Double) = tornadoField(fb.x, fb.y - 0.5)
		if tf.2 > 0 {
			fb.vx += clampD((tf.0 - fb.vx) * 2.4, -40, 40) * light * dt
			if tf.1 < -1.0 { fb.vy += (-gravityG * 0.9 + clampD((tf.1 - fb.vy) * 2.2, -30, 30)) * light * dt }
		}
		if let h = weather.hurricane, world.dim == .overworld {
			let w: Double = weather.wind * h.force * hurricaneReach(fb.x, h)
			fb.vx += clampD(w - fb.vx, -12, 12) * 0.6 * light * dt
		}
	}

	/// Puts a block that has come to rest back into the world: in the cell it landed in, or one beside
	/// or above it that is free; with nowhere to go, it drops as an item
	func settleBlock(_ fb: FallingBlock, _ row: Int) {
		let tx: Int = Int(floor(fb.x))
		let spots: [(Int, Int)] = [(tx, row), (tx, row - 1), (tx - 1, row), (tx + 1, row), (tx, row - 2)]
		for (sx, sy) in spots {
			let cur: Tile = world.tile(sx, sy)
			if !(cur == .air || cur.liquid || (cur.isPlant && cur != .torch && cur != .lantern)) { continue }
			let below: Tile = world.tile(sx, sy + 1)
			if !(below.supportsThings || below.isPlatform) && sy != row { continue }
			world.set(sx, sy, fb.tile)
			if fb.built { world.setBuilt(sx, sy, true) }
			spawnParticles(Double(sx) + 0.5, Double(sy) + 1.0, fb.tile.def.colors.first ?? 0xA09080, 4, 2.0, 0.3, 10)
			return
		}
		let item: Item = fb.tile.def.drop ?? .block(fb.tile)
		spawnDrop(Stack(item: item, count: 1), fb.x, Double(row), 0, -2)
	}
}

// MARK: structural physics

/// What a structure check found: the blocks crushed by more weight than they can carry (worst first),
/// the blocks nothing holds up (lowest first), those under strain (how close to their limit,
/// 0.7...1), how many blocks were looked at, and where they were
struct StructCheck {
	var crushed: [IntPair] = []
	var fails: [IntPair] = []
	var strained: [(IntPair, Double)] = []
	var count: Int = 0
	var minX: Int = Int.max
	var maxX: Int = Int.min
	var minY: Int = Int.max
	var maxY: Int = Int.min
}

/// One block of a structure while it is being looked at
struct StructNode {
	var x: Int
	var y: Int
	var phys: BlockPhys
	/// how much further it can hold out (0: nothing holds it)
	var sup: Int = 0
	var parent: Int = -1
	var load: Double = 0
}

extension Game {
	/// Structural physics (Settings.structural): built blocks (what the player placed) make up
	/// structures standing on the land, which never moves. A block standing on a held block is held;
	/// a block beside or under one is held if it is within its reach (`span`) of a standing support;
	/// everything resting on a block (the blocks it holds up, furniture on it) must not weigh more than
	/// it can carry. Blocks out of reach, or carrying too much, crack and fall. Only structures next
	/// to a change are looked at, a little at a time, and never more than `maxNodes` blocks at once.
	func updateStructures(_ dt: Double) {
		if !settings.structural {
			if world.structWatch {
				world.structWatch = false
				world.structEdits.removeAll()
				structQueue.removeAll()
				stress.removeAll()
			}
			return
		}
		world.structWatch = true
		if !world.structEdits.isEmpty {
			// only changes next to something built matter (grass spreading, crops growing do not)
			for e in world.structEdits where structQueue.count < 48 && builtNear(e.x, e.y) {
				if !structQueue.contains(e) { structQueue.append(e) }
			}
			world.structEdits.removeAll()
			structT = max(structT, 0.12)
		}
		if structT > 0 {
			structT -= dt
			return
		}
		if structQueue.isEmpty { return }
		let e: IntPair = structQueue.removeFirst()
		let fails: Int = settleStructure(e.x, e.y, maxFalls: 12)
		if fails > 0 {
			// what was resting on them is looked at again once they are gone
			structQueue.append(e)
			structT = 0.18
		}
	}

	/// Looks at the structure around (x, y) and brings down what cannot stand (at most `maxFalls`
	/// blocks, worst first). Returns how many fell.
	@discardableResult
	func settleStructure(_ x: Int, _ y: Int, maxFalls: Int) -> Int {
		let res: StructCheck = checkStructure(x, y)
		// strain marks: those of the blocks just looked at are replaced
		if res.count > 0 && !stress.isEmpty {
			stress = stress.filter { (kv: (key: Int, value: Double)) -> Bool in
				let sx: Int = floorDiv(kv.key, 4096)
				let sy: Int = kv.key - sx * 4096
				return sx < res.minX || sx > res.maxX || sy < res.minY || sy > res.maxY
			}
		}
		for (p, f) in res.strained { stress[structKey(p.x, p.y)] = f }
		var n: Int = 0
		// a block carrying more than it can breaks under the weight
		for p in res.crushed {
			if n >= maxFalls { break }
			if world.tile(p.x, p.y) == .air { continue }
			stress[structKey(p.x, p.y)] = nil
			breakTile(p.x, p.y, false)
			n += 1
		}
		// a block nothing holds up falls (and settles where it lands)
		for p in res.fails {
			if n >= maxFalls { break }
			let t: Tile = world.tile(p.x, p.y)
			if t == .air { continue }
			stress[structKey(p.x, p.y)] = nil
			if fallingBlocks.count < 120 && t.solid {
				displaceBlock(p.x, p.y, vx: Double.random(in: -0.6...0.6), vy: 0)
			} else {
				breakTile(p.x, p.y, false)
			}
			n += 1
		}
		if n > 0 {
			sfx(.breakWood, at: Double(x) + 0.5, 0.7)
			addShake(min(0.5, 0.08 * Double(n)))
		} else if res.count > 0 {
			// a creak and some dust where it is near its limit
			let worst: (IntPair, Double)? = res.strained.max { $0.1 < $1.1 }
			if let w = worst, w.1 > 0.92 {
				sfx(.digWood, at: Double(w.0.x) + 0.5, 0.4)
				spawnParticles(Double(w.0.x) + 0.5, Double(w.0.y) + 1.0, 0xB0A080, 3, 1.5, 0.6, 12)
			}
		}
		return n
	}

	func structKey(_ x: Int, _ y: Int) -> Int { return x &* 4096 &+ y }

	/// Something built in the 3x3 around (x, y)
	func builtNear(_ x: Int, _ y: Int) -> Bool {
		for dy in -1...1 { for dx in -1...1 where world.isBuilt(x + dx, y + dy) { return true } }
		return false
	}

	/// The structure check (see updateStructures)
	func checkStructure(_ x0: Int, _ y0: Int) -> StructCheck {
		let maxNodes: Int = 5000
		var nodes: [StructNode] = []
		var index: [Int: Int] = [:]
		var stack: [Int] = []
		func consider(_ x: Int, _ y: Int) {
			let k: Int = structKey(x, y)
			if index[k] != nil { return }
			let t: Tile = world.tile(x, y)
			if !isStructural(t) || !world.isBuilt(x, y) { return }
			index[k] = nodes.count
			stack.append(nodes.count)
			nodes.append(StructNode(x: x, y: y, phys: blockPhys(t)))
		}
		for dy in -1...1 { for dx in -1...1 { consider(x0 + dx, y0 + dy) } }
		var out: StructCheck = StructCheck()
		if nodes.isEmpty { return out }
		while let i = stack.popLast() {
			if nodes.count > maxNodes {
				// too big to look at in one go: left standing
				out.count = nodes.count
				return out
			}
			let nx: Int = nodes[i].x
			let ny: Int = nodes[i].y
			consider(nx - 1, ny)
			consider(nx + 1, ny)
			consider(nx, ny - 1)
			consider(nx, ny + 1)
		}
		// standing: on the land, built into it at the side, or on a standing block of the same column
		// (worked out from the bottom up); each holds out to its full reach
		var sup: [Int] = [Int](repeating: 0, count: nodes.count)
		var parent: [Int] = [Int](repeating: -1, count: nodes.count)
		var depth: [Int] = [Int](repeating: 0, count: nodes.count)
		var buckets: [[Int]] = [[Int]](repeating: [], count: 11)
		let upward: [Int] = Array(0..<nodes.count).sorted { nodes[$0].y > nodes[$1].y }
		for i in upward {
			let n: StructNode = nodes[i]
			let full: Int = clampI(n.phys.span + 1, 1, 10)
			if landAt(n.x, n.y + 1) || landAt(n.x - 1, n.y) || landAt(n.x + 1, n.y) {
				sup[i] = full
			} else if let j = index[structKey(n.x, n.y + 1)], sup[j] > 0 {
				sup[i] = full
				parent[i] = j
				depth[i] = depth[j] + 1
			}
			if sup[i] > 0 { buckets[sup[i]].append(i) }
		}
		// reach spreads out from the standing blocks: one less for each block out sideways or down,
		// the same up (a block resting on a held block is held as well as it is), never more than a
		// block's own reach
		var done: [Bool] = [Bool](repeating: false, count: nodes.count)
		var level: Int = 10
		while level >= 1 {
			if buckets[level].isEmpty {
				level -= 1
				continue
			}
			let i: Int = buckets[level].removeLast()
			if done[i] || sup[i] != level { continue }
			done[i] = true
			let n: StructNode = nodes[i]
			let nbr: [(Int, Int, Bool)] = [(n.x, n.y - 1, true), (n.x - 1, n.y, false), (n.x + 1, n.y, false), (n.x, n.y + 1, false)]
			for (ax, ay, up) in nbr {
				guard let j = index[structKey(ax, ay)], !done[j] else { continue }
				let cap: Int = clampI(nodes[j].phys.span + 1, 1, 10)
				let cand: Int = min(cap, up ? level : level - 1)
				if cand > sup[j] {
					sup[j] = cand
					parent[j] = i
					depth[j] = depth[i] + 1
					buckets[cand].append(j)
				}
			}
		}
		// the load flows down the support tree, the furthest blocks first: each block carries itself,
		// what rests on it, and what it holds up
		let byDepth: [Int] = Array(0..<nodes.count).sorted { depth[$0] > depth[$1] }
		for i in byDepth {
			let n: StructNode = nodes[i]
			var load: Double = nodes[i].load + n.phys.weight
			let above: Tile = world.tile(n.x, n.y - 1)
			if above != .air && !isStructural(above) && !above.liquid { load += tileWeight(above) }
			nodes[i].load = load
			nodes[i].sup = sup[i]
			if parent[i] >= 0 { nodes[parent[i]].load += load }
		}
		var fails: [(IntPair, Double)] = []
		var crushed: [(IntPair, Double)] = []
		var strained: [(IntPair, Double)] = []
		for i in 0..<nodes.count {
			let n: StructNode = nodes[i]
			let p: IntPair = IntPair(x: n.x, y: n.y)
			out.minX = min(out.minX, n.x)
			out.maxX = max(out.maxX, n.x)
			out.minY = min(out.minY, n.y)
			out.maxY = max(out.maxY, n.y)
			if n.sup <= 0 {
				// nothing holds it: the lowest come down first
				fails.append((p, Double(n.y)))
				continue
			}
			let carried: Double = n.load - n.phys.weight
			let f: Double = carried / max(0.1, n.phys.carry)
			if f > 1.0 {
				crushed.append((p, f))
			} else if f > 0.7 || (n.sup == 1 && n.phys.span > 1) {
				strained.append((p, max(0.7, f)))
			}
		}
		crushed.sort { $0.1 > $1.1 }
		fails.sort { $0.1 > $1.1 }
		out.crushed = crushed.map { $0.0 }
		out.fails = fails.map { $0.0 }
		out.strained = strained
		out.count = nodes.count
		return out
	}

	/// The land holds structures up: a solid block that was not built, or the bottom of the world
	func landAt(_ x: Int, _ y: Int) -> Bool {
		if y >= world.H - 1 { return true }
		let t: Tile = world.tile(x, y)
		return t.solid && !world.isBuilt(x, y)
	}
}

// ===== p31d_rails =====

// MARK: - Rails, the ore cart, trains and big parts
// A rail wheel rolls almost freely along rails (and brakes only when the driver pulls against the
// motion), and drags anywhere else. An ore cart put on a rail is a little vehicle of two crates on two
// rail wheels: pushed, ridden, loaded, or pulled by an engine. Couplers that touch link two vehicles
// into a train: each pulls and pushes the other at the coupler, and a tap on one lets go. A big wheel is
// a part three cells across (Vehicle.spanOf maps its cells to its middle).

/// A coupling between two vehicles (each keeps one, naming the other): this vehicle's coupler cell, the
/// other vehicle and its coupler cell, and how far apart the two are held
struct VLink: Codable {
	var cell: PartCell
	var other: Int
	var oc: PartCell
	var len: Double
}

/// The numbers of rails and trains
enum Rails {
	/// how a rail wheel rolls on rails, and drags off them
	static let roll: Double = 0.004
	static let offRail: Double = 0.35
	/// how close two couplers link up, the most a coupling stretches before it breaks, and how long a
	/// pair let go by hand waits before it can link again (seconds)
	static let reach: Double = 1.35
	static let snap: Double = 3.0
	static let wait: Double = 2.0
	/// how hard a coupling pulls a stretch back each step (of the stretch)
	static let stiff: Double = 0.25
	/// how hard rails hold a rail wheel that has come off them but is still over them (in its weight)
	static let hold: Double = 2.5
}

extension Game {
	/// A rail wheel's grip where it touches: on rails it rolls almost freely, braking only when told to;
	/// off them its flange drags
	func railGrip(_ tx: Int, _ ty: Int, _ braking: Bool, _ rider: Bool) -> Double {
		let onRail: Bool = world.tile(tx, ty - 1) == .rail || world.tile(tx, ty) == .rail || world.tile(tx, ty + 1) == .rail
		if onRail { return braking && rider ? 0.6 : Rails.roll }
		return braking ? 0.7 : Rails.offRail
	}

	/// The top of the track under a rail wheel at a point: the ground under the rails, sloping evenly from
	/// the middle of one column to the next where the rails rise or fall a block (a track built in steps
	/// is a ramp to a rail wheel). nil where there are no rails near.
	func railSurface(_ x: Double, _ y: Double) -> (Double, Double)? {
		let tx: Int = Int(floor(x))
		guard let h0 = railTop(tx, y) else { return nil }
		let f: Double = x - (Double(tx) + 0.5)
		let side: Int = f >= 0 ? 1 : -1
		guard let h1 = railTop(tx + side, h0 - 0.5), abs(h1 - h0) <= 1.01 else { return (h0, 0) }
		// height here, and how it falls per block to the right
		return (h0 + (h1 - h0) * abs(f), (h1 - h0) * Double(side))
	}

	/// The top of the ground under a rail in a column, near a height (a rail sits on the block below it)
	func railTop(_ tx: Int, _ near: Double) -> Double? {
		let ny: Int = Int(floor(near))
		for dy in [0, -1, 1, 2] where world.tile(tx, ny + dy) == .rail { return Double(ny + dy + 1) }
		return nil
	}

	/// Where a rail wheel's sample meets the track: by the rails' smooth surface where there are rails,
	/// else the land as for any wheel
	func railPenetration(_ x: Double, _ y: Double) -> (Double, Double, Double)? {
		guard let s = railSurface(x, y) else { return penetration(x, y, wheel: true) }
		let depth: Double = y - s.0
		if depth <= 0 { return nil }
		let k: Double = sqrt(s.1 * s.1 + 1.0)
		return (depth / k, s.1 / k, -1.0 / k)
	}

	/// Rails hold their wheels: a rail wheel in the air with rails under it (going down a step, over a
	/// crest) is pulled down onto them, so a cart follows the track instead of tipping over the edge
	func railHold(_ v: Vehicle, _ h: Double) {
		var cells: [PartCell] = []
		for (c, t) in v.parts where t == .railWheel { cells.append(c) }
		if cells.isEmpty { return }
		let share: Double = v.mass / Double(cells.count)
		for c in cells {
			let w: (Double, Double) = v.cellCenter(c)
			let bx: Int = Int(floor(w.0))
			let by: Int = Int(floor(w.1 + 0.56))
			// (standing: the cell under the wheel is ground)
			if world.tile(bx, by).solid { continue }
			var over: Bool = false
			var k: Int = 0
			while k <= 1 && !over {
				if world.tile(bx, by + k) == .rail { over = true }
				k += 1
			}
			if over { v.push(w.0, w.1, 0, Rails.hold * gravityG * share * h) }
		}
	}

	/// An ore cart put on a rail: a little vehicle of two crates on two rail wheels
	func placeOreCart(_ tx: Int, _ ty: Int) -> Bool {
		var ry: Int = ty
		if world.tile(tx, ry) != .rail {
			if world.tile(tx, ry + 1) == .rail { ry += 1 } else {
				say("Put the ore cart on a rail.", 1.6)
				return true
			}
		}
		var left: Int = tx
		if world.tile(tx + 1, ry) != .rail && world.tile(tx - 1, ry) == .rail { left = tx - 1 }
		for x in left...(left + 1) {
			for y in (ry - 1)...ry where world.tile(x, y).solid {
				say("No room for the cart here.", 1.5)
				return true
			}
		}
		if !inReach(Double(tx) + 0.5, Double(ry) + 0.5) { return true }
		let v: Vehicle = Vehicle(id: newID(), first: .frame, x: 0, y: 0)
		v.parts.removeAll()
		v.parts[PartCell(dx: 0, dy: 0)] = .cargo
		v.parts[PartCell(dx: 1, dy: 0)] = .cargo
		v.parts[PartCell(dx: 0, dy: 1)] = .railWheel
		v.parts[PartCell(dx: 1, dy: 1)] = .railWheel
		v.recompute(keepAnchor: false)
		v.placeBox(left: Double(left), bottom: Double(ry + 1))
		vehicles.append(v)
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.7)
		say("An ore cart on the rails: push it, ride it, load it (tap it), or couple it to an engine.", 3.0)
		bumpHUD()
		return true
	}

	/// A big wheel: the cell tapped is its middle; all nine cells must be free, one of them next to the
	/// vehicle. Where the land is in the way the vehicle is lifted (up to three blocks) if it fits higher.
	/// True when the tap was for a vehicle.
	func attachBigWheel() -> Bool {
		for v in vehicles {
			if aimX < v.b.left - 3 || aimX > v.b.right + 3 || aimY < v.b.top - 3 || aimY > v.b.y + 3 { continue }
			let mid: PartCell = v.cellAt(aimX, aimY)
			var cells: [PartCell] = []
			var touches: Bool = false
			var free: Bool = true
			for dy in -1...1 {
				for dx in -1...1 {
					let k: PartCell = PartCell(dx: mid.dx + dx, dy: mid.dy + dy)
					if v.parts[k] != nil { free = false }
					if v.hasNeighbor(k) { touches = true }
					cells.append(k)
				}
			}
			if !touches { continue }
			if useCD > 0 { return true }
			useCD = 0.3
			if !free {
				say("A big wheel needs a free space three by three (the cell you tap is its middle).", 2.5)
				return true
			}
			var lift: Int = 0
			while lift <= 3 && bigWheelBlocked(v, cells, lift) { lift += 1 }
			if lift > 3 {
				say("The ground is in the way of the big wheel.", 2.0)
				return true
			}
			if lift > 0 {
				v.py -= Double(lift)
				v.vy = 0
				v.updateBox()
			}
			for k in cells {
				v.parts[k] = .bigWheel
				v.spanOf[k] = mid
			}
			v.recompute(keepAnchor: true)
			v.kit = -1
			v.asleep = false
			if !isCreative { inv.removeAt(sel, 1) }
			sfx(.place, 0.7)
			swingT = 0.15
			bumpHUD()
			return true
		}
		return false
	}

	/// Whether the land is in the way of a vehicle and its new cells, lifted so many blocks
	func bigWheelBlocked(_ v: Vehicle, _ extra: [PartCell], _ lift: Int) -> Bool {
		var all: [PartCell] = Array(v.parts.keys)
		all.append(contentsOf: extra)
		for c in all {
			let wp: (Double, Double) = v.cellPos(c)
			let y: Double = wp.1 - Double(lift)
			if world.boxSolid(wp.0 + 0.02, y + 0.02, wp.0 + 0.98, y + 0.98) { return true }
		}
		return false
	}

	// MARK: trains

	/// Couplers that come within reach of each other link up (each vehicle keeps the link)
	func formCouplings(_ dt: Double) {
		var any: Bool = false
		for v in vehicles where v.couplers > 0 {
			if v.noCoupleT > 0 { v.noCoupleT -= dt }
			any = true
		}
		if !any { return }
		for a in vehicles where a.couplers > 0 && a.noCoupleT <= 0 {
			for (ca, ta) in a.parts where ta == .coupler && !a.links.contains(where: { $0.cell == ca }) {
				let pa: (Double, Double) = a.cellCenter(ca)
				for b in vehicles where b !== a && b.couplers > 0 && b.noCoupleT <= 0 {
					if b.b.right < pa.0 - 2 || b.b.left > pa.0 + 2 || b.b.y < pa.1 - 2 || b.b.top > pa.1 + 2 { continue }
					for (cb, tb) in b.parts where tb == .coupler && !b.links.contains(where: { $0.cell == cb }) {
						let pb: (Double, Double) = b.cellCenter(cb)
						let d: Double = sqrt((pb.0 - pa.0) * (pb.0 - pa.0) + (pb.1 - pa.1) * (pb.1 - pa.1))
						if d > Rails.reach { continue }
						let len: Double = max(1.0, d)
						a.links.append(VLink(cell: ca, other: b.id, oc: cb, len: len))
						b.links.append(VLink(cell: cb, other: a.id, oc: ca, len: len))
						sfx(.hit, at: pa.0, 0.5)
						if abs(pa.0 - self.pb.x) < 30 { say("Coupled.", 1.0) }
						break
					}
					if a.links.contains(where: { $0.cell == ca }) { break }
				}
			}
		}
	}

	/// Every coupling pulls and pushes its two vehicles at the couplers toward the length it was made at
	/// (worked out together a few times, as the contacts are); one stretched far past it breaks
	func solveCouplings(_ h: Double) {
		var round: Int = 0
		while round < 4 {
			for a in vehicles where !a.links.isEmpty {
				for (i, l) in a.links.enumerated() where a.id < l.other {
					guard let b = vehicleByID(l.other) else { a.links.remove(at: i); return }
					coupleStep(a, b, l, h, round == 0)
				}
			}
			round += 1
		}
	}

	func coupleStep(_ a: Vehicle, _ b: Vehicle, _ l: VLink, _ h: Double, _ first: Bool) {
		let pa: (Double, Double) = a.cellCenter(l.cell)
		let pb: (Double, Double) = b.cellCenter(l.oc)
		let dx: Double = pb.0 - pa.0
		let dy: Double = pb.1 - pa.1
		let d: Double = sqrt(dx * dx + dy * dy)
		if d < 1e-6 { return }
		if first && d > l.len + Rails.snap {
			// pulled apart: the coupling gives
			uncouple(a, l.cell)
			return
		}
		let nx: Double = dx / d
		let ny: Double = dy / d
		let aDyn: Bool = a.inStep || !a.asleep
		let bDyn: Bool = b.inStep || !b.asleep
		let ia: Double = aDyn ? 1.0 / a.mass : 0
		let ib: Double = bDyn ? 1.0 / b.mass : 0
		let iia: Double = aDyn ? 1.0 / a.inertia : 0
		let iib: Double = bDyn ? 1.0 / b.inertia : 0
		let rax: Double = pa.0 - a.px
		let ray: Double = pa.1 - a.py
		let rbx: Double = pb.0 - b.px
		let rby: Double = pb.1 - b.py
		let rna: Double = rax * ny - ray * nx
		let rnb: Double = rbx * ny - rby * nx
		let k: Double = ia + rna * rna * iia + ib + rnb * rnb * iib
		if k <= 0 { return }
		let va: (Double, Double) = a.pointVel(pa.0, pa.1)
		let vb: (Double, Double) = b.pointVel(pb.0, pb.1)
		let vrel: Double = (vb.0 - va.0) * nx + (vb.1 - va.1) * ny
		let target: Double = -Rails.stiff * (d - l.len) / max(h, 1e-4)
		let lam: Double = (target - vrel) / k
		if abs(lam) < 1e-9 { return }
		b.vx += lam * nx * ib
		b.vy += lam * ny * ib
		b.angVel += rnb * lam * iib
		a.vx -= lam * nx * ia
		a.vy -= lam * ny * ia
		a.angVel -= rna * lam * iia
		if abs(lam) * max(ia, ib) > 0.2 {
			a.asleep = false
			b.asleep = false
		}
	}

	/// Lets go of a coupling at a coupler (both vehicles forget it; they wait a moment before linking again)
	func uncouple(_ v: Vehicle, _ c: PartCell) {
		guard let i = v.links.firstIndex(where: { $0.cell == c }) else { return }
		let l: VLink = v.links[i]
		v.links.remove(at: i)
		v.noCoupleT = Rails.wait
		if let o = vehicleByID(l.other) {
			o.links.removeAll { $0.other == v.id && $0.cell == l.oc }
			o.noCoupleT = Rails.wait
		}
	}
}
