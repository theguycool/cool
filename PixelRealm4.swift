// PIXEL REALM v2, part 4 of 10: tools and items in use, creature AI, spawning, combat, damage and bosses, ships, the portal and map, saving,
// helpers, walls and doors, and the vehicle screens' logic.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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
	// a mod tree's pass-through trunk counts too (felled by an axe, keeping its leaves alive)
	if t.isMod { return ModRuntime.shared.treeRole(t) == 1 }
	return t == .log || t == .jungleLog || t == .palmLog || t == .birchLog
}

func isLeafTile(_ t: Tile) -> Bool {
	if t.isMod { return ModRuntime.shared.treeRole(t) == 2 }
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
func isSeat(_ t: Tile) -> Bool { return t == .chair || t == .sofa || (t.isMod && ModRuntime.shared.seatTiles.contains(t.rawValue)) }

/// Sand, and the mod blocks that fall like it
func fallsLikeSand(_ t: Tile) -> Bool { return t == .sand || (t.isMod && ModRuntime.shared.fallTiles.contains(t.rawValue)) }

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
		// (driving, or with the hands on a remote, nothing in hand is used)
		if dead || inVehicle != nil || remoteID != 0 {
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
		mineP += dt * speed * mineBoost(kind) * ModRuntime.shared.rule(.mining)
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
			// a mod tree's leaves give saplings as the game's do (they grow its designs where they belong)
			if isLeafTile(t) && Double.random(in: 0...1) < 0.085 { mod.append(Stack(item: .block(.sapling), count: 1)) }
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
		if isLeafTile(t) {
			for _ in 0..<3 { dropLeaf(Double(x) + Double.random(in: 0.1...0.9), Double(y) + Double.random(in: 0.2...0.8), t) }
		}
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
		if fallsLikeSand(world.tile(x, y - 1)) { checkFalling(x, y - 1) }
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
		if vehicleBuild && wallMode && canBeWall(t.placedForm) && attachWallToVehicle(t.placedForm) { return }
		if t == .doorClosed || t == .doorOpen {
			if vehicleBuild && attachDoorToVehicle() { return }
			if placeDoor(tx, ty) {
				if !isCreative { inv.removeAt(sel, 1) }
				placeCD = 0.25
				swingT = 0.14
				bumpHUD()
			}
			return
		}
		// the ON VEHICLE switch: the block is built onto the vehicle instead
		if vehicleBuild && attachBlockToVehicle(t.placedForm) { return }
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
		// a little of the archer's own motion carries into the arrow, so shots on the run still land;
		// all of the speed of a vehicle that carries the archer does (the arrow was going that fast already)
		let cv: (Double, Double) = carrierVel()
		let own: Double = inVehicle == nil ? pb.vx : 0
		return (ox + dx * 0.4, oy + dy * 0.4, dx * speed + own * 0.3 + cv.0, dy * speed + min(0, inVehicle == nil ? pb.vy : 0) * 0.2 + cv.1)
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
		case .bucket:
			if pressed { useBucket() }
		case .remote:
			if pressed { useRemote() }
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
			if pressed, useCD <= 0, inReach(aimX, aimY), let (v, c) = vehicleWallAtPoint(aimX, aimY), removeVehicleWall(v, c) {
				useCD = 0.3
			} else if pressed, useCD <= 0, let (v, c) = vehicleAtPoint(aimX, aimY), inReach(aimX, aimY) {
				removeVehiclePart(v, c)
				useCD = 0.3
			}
		case .portalKey:
			if pressed { say("Use the key on the sealed portal.", 2.0) }
		case .carKit, .boatKit, .motorboatKit, .planeKit, .heliKit, .airshipKit, .tankKit, .truckKit:
			if pressed && useCD <= 0 { placeKit(g) }
		case .assembler:
			useAssembler(pressed)
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
		if c.dx >= -32 && c.dx < 32 && c.dy >= -32 && c.dy < 32 {
			return IntPair(x: -1_000_000_000 + v.id * 4096 + (c.dx + 32) * 64 + (c.dy + 32), y: -77)
		}
		// a cell further out on a big vehicle (an assembled ship): the cell goes in the second number
		return IntPair(x: -1_000_000_000 + v.id, y: -100_000 - ((c.dx + 2048) * 4096 + (c.dy + 2048)))
	}

	func isCargoSpot(_ p: IntPair) -> Bool { return (p.y == -77 || p.y <= -100_000) && p.x < -900_000_000 }

	func removeVehiclePart(_ v: Vehicle, _ c: PartCell) {
		if v.rider { dismount() }
		let crates: [PartCell] = v.parts.keys.filter { vehicleStores(v, $0) }
		let spills: [(PartCell, (Double, Double))] = crates.map { ($0, v.cellCenter($0)) }
		let returned: [VCell] = v.cutAway(c)
		// a crate that comes off tips its contents onto the ground
		for (cell, at) in spills where v.parts[cell] == nil {
			let k: IntPair = cargoSpot(v, cell)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { spawnDrop(st, at.0, at.1, Double.random(in: -2...2), -3.5) }
		}
		for r in returned { giveItem(vehicleCellItem(r), 1) }
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
		if p == .bigWheel {
			if !attachBigWheel() { say("Tap next to a vehicle: the cell you tap is the big wheel's middle.", 2.0) }
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
			splitJointSections(v)
			if !isCreative { inv.removeAt(sel, 1) }
			useCD = 0.2
			swingT = 0.15
			let check: VehicleCheck = vehicleCheck(v)
			if check.ready && !wasReady {
				let kind: String = check.title.lowercased()
				say("Your \(kind) is ready! Stand next to it and press DRIVE.", 3.5)
			} else if let note = partNote(v, c, p) {
				say(note, 3.0)
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
		if let v = drivenVehicle, machineGuns(v) > 0 { return "FIRE" }
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
		suitFireHeld = false
		jointButtons = [false, false, false]
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
		let blocked: Bool = paused || showInventory || showMap || showJournal || showWeather || showPower || showCapture || showModTest || showInfuse || showExo || showJoint || showRadio || dead
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

// ===== p15a_mobai =====

// MARK: - Mob AI

extension Game {
	func buildDecks() -> [Deck] {
		var out: [Deck] = []
		let sea: Double = Double(WorldGen.sea)
		for s in ships where s.sink < 3.0 {
			let dy: Double = s.deckY(sea)
			out.append(Deck(x0: s.x - PirateShip.deckHalf, x1: s.x + PirateShip.deckHalf - 0.1, y: dy, vx: s.speed * Double(s.dir), id: s.id))
		}
		// lift cars
		for l in lifts { out.append(Deck(x0: l.x0, x1: l.x1, y: l.y, vx: 0, id: l.deckID)) }
		return out
	}

	func allDecks() -> [Deck] { return decksCache }

	func accelX(_ m: Mob, _ target: Double, _ a: Double, _ dt: Double) {
		let d: Double = target - m.b.vx
		let s: Double = a * dt
		if d > s { m.b.vx += s } else if d < -s { m.b.vx -= s } else { m.b.vx = target }
	}

	func stepMob(_ m: Mob, _ dt: Double, stepUp: Double = 1.0) {
		let d: MobDef = m.def
		if d.flying {
			// keep flyers from sinking; their AI sets vy directly
		} else if m.b.inWater {
			m.b.vy += 12.0 * dt
			m.b.vy = clampD(m.b.vy, -5.0, 5.0)
			if m.hp > 0 && d.behavior != .swimmer { m.b.vy -= 26.0 * dt }
		} else {
			m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
		}
		if m.knock > 0 { m.knock -= dt }
		if m.leapReq {
			// a harder leap at a wall it is stuck against (see think)
			m.leapReq = false
			if m.b.onGround && !d.flying {
				m.b.vy = -d.jump * 1.22
				m.b.vx = (m.aimX >= m.b.x ? 1.0 : -1.0) * max(2.5, d.speed)
				m.leapT = 1.6
			}
		}
		// slowed creatures cover less ground (their AI still asks for its usual speed)
		let sm: Double = m.speedMul
		if sm < 0.999 {
			m.b.vx *= sm
			if d.flying { m.b.vy *= sm }
		}
		moveThing(&m.b, dt, stepUp: d.flying ? 0 : stepUp, dropThrough: false, decks: decksCache, mass: mobMass(m), falls: !d.flying && !m.b.inWater)
		if sm < 0.999 {
			m.b.vx /= sm
			if d.flying { m.b.vy /= sm }
		}
		if m.b.deck >= 0 && m.b.deck < decksCache.count { m.b.x += decksCache[m.b.deck].vx * dt }
		if m.boat >= 0 { clampToDeck(m) }
		if m.b.onGround { m.anim += abs(m.b.vx) * dt * 0.8 } else { m.anim += dt * 0.5 }
	}

	func cliffAhead(_ m: Mob, _ dir: Int) -> Bool {
		let fx: Int = Int(floor(m.b.x + Double(dir) * (m.b.w * 0.5 + 0.6)))
		let fy: Int = Int(floor(m.b.y + 0.2))
		var d: Int = 0
		while d < 5 {
			let t: Tile = world.tile(fx, fy + d)
			if t.solid || t == .platform || t.liquid { return false }
			d += 1
		}
		return true
	}

	func wander(_ m: Mob, _ dt: Double, _ speedK: Double) {
		let d: MobDef = m.def
		m.t1 -= dt
		if m.t1 <= 0 {
			if m.st == 0 {
				m.st = 1
				m.dir = Bool.random() ? 1 : -1
				if abs(m.b.x - m.homeX) > 24 { m.dir = m.b.x > m.homeX ? -1 : 1 }
				m.t1 = Double.random(in: 1.5...4.5)
			} else {
				m.st = 0
				m.t1 = Double.random(in: 1.0...4.0)
			}
		}
		if m.st == 1 {
			if cliffAhead(m, m.dir) || (m.b.hitWall && !m.b.onGround) { m.dir = -m.dir }
			if m.b.hitWall && m.b.onGround { m.dir = -m.dir }
			accelX(m, Double(m.dir) * d.speed * speedK, 14, dt)
		} else {
			accelX(m, 0, 18, dt)
		}
	}

	func flee(_ m: Mob, _ fromX: Double, _ dt: Double, _ speedK: Double) {
		let dirX: Double = m.b.x >= fromX ? 1.0 : -1.0
		m.dir = Int(dirX)
		accelX(m, dirX * m.def.speed * speedK, 30, dt)
		if m.b.hitWall && m.b.onGround { m.b.vy = -m.def.jump }
	}

	func chase(_ m: Mob, _ tx: Double, _ speedK: Double, _ dt: Double) {
		let d: MobDef = m.def
		let dirX: Double = tx >= m.b.x ? 1.0 : -1.0
		if abs(tx - m.b.x) > 0.35 {
			m.dir = Int(dirX)
			accelX(m, dirX * d.speed * speedK, 26, dt)
		} else {
			accelX(m, 0, 30, dt)
		}
		if m.b.hitWall && m.b.onGround { m.b.vy = -d.jump }
		if m.b.inWater { m.b.vy -= 18 * dt }
	}

	func contactHurt(_ m: Mob, _ dmg: Double) {
		if m.cd > 0 || dead { return }
		// touching: overlapping across, and up and down anything from overlapping to standing on the
		// player's head (or the player on its back)
		let across: Bool = pb.right > m.b.left + 0.05 && pb.left < m.b.right - 0.05
		let upDown: Bool = pb.y > m.b.top - 0.2 && pb.top < m.b.y + 0.2
		if across && upDown {
			var info = DamageInfo(amount: dmg, type: .contact, source: .mob(m, faction(of: m)))
			info.knock = 6.5
			info.originX = m.b.x
			if hurtPlayer(info) { m.cd = 0.9; m.atkT = Mob.atkDur }
		}
	}

	/// A creature's swing: hits the player and any creature from another side inside the reach box
	func mobStrike(_ m: Mob, reach: Double, height: Double, dmg: Double, knock: Double) {
		m.atkT = Mob.atkDur
		// a mutated creature's swing reaches as far as it has grown
		let k: Double = max(1.0, m.mutSize)
		let reach: Double = reach * k
		let height: Double = height * k
		let x0: Double = m.dir > 0 ? m.b.x - 0.3 : m.b.x - reach - 0.3
		let x1: Double = m.dir > 0 ? m.b.x + reach + 0.3 : m.b.x + 0.3
		var info = DamageInfo(amount: dmg, type: .melee, source: .mob(m, faction(of: m)))
		info.dirX = Double(m.dir)
		info.knock = knock
		info.originX = m.b.x
		info.key = newID()
		damageBox(x0, m.b.y - height, x1, m.b.y + 0.1, info)
	}

	func updateMobs(_ dt: Double) {
		let t0: Double = perfNow()
		let px: Double = pb.x
		let py: Double = pb.y
		let offScreen: Double = viewTilesW * 0.5 + 6.0
		frameNo &+= 1
		// iterated by index because AI code may append new mobs while it runs
		var i: Int = 0
		while i < mobs.count {
			let m: Mob = mobs[i]
			i += 1
			if m.hp <= 0 || m.removed { continue }
			let dx: Double = abs(m.b.x - px)
			let dy: Double = abs(m.b.y - py)
			if !m.persistent && !m.tame && !m.isBoss && (dx > 115 || dy > 85) {
				m.removed = true
				continue
			}
			// a monster nobody is fighting that stays well off-screen wanders off after a while, making
			// room for another; at daybreak the night's hunters out of sight go back where they came from
			if m.def.hostile && !m.persistent && !m.tame && !m.isBoss && m.boat < 0 && m.lair == 0 {
				if (dx > offScreen || dy > 40) && m.ai != .chase {
					m.farT += dt
					if m.farT > ((m.hunter && !isNight) ? 4.0 : 40.0) {
						m.removed = true
						continue
					}
				} else {
					m.farT = 0
				}
			}
			if m.hurtT > 0 { m.hurtT -= dt }
			if m.cd > 0 { m.cd -= dt }
			if m.flash > 0 { m.flash -= dt }
			if m.lean != 0 { m.lean *= (1.0 - min(1.0, dt * 7.0)); if abs(m.lean) < 0.01 { m.lean = 0 } }
			if m.atkT > 0 { m.atkT -= dt }
			if m.turnT > 0 {
				m.turnT -= dt
				if m.turnT <= 0 { m.turnT = 0; m.face = m.dir }
			} else if m.face != m.dir {
				if m.face == 0 { m.face = m.dir } else { m.turnT = Mob.turnDur }
			}
			if m.regrow > 0 {
				m.regrow -= dt
				if m.regrow <= 0 { m.sheared = false }
			}
			if !world.isLoaded(Int(floor(m.b.x))) { continue }
			if m.dazeGuard > 0 { m.dazeGuard -= dt }
			if m.daze > 0 {
				// reeling from a club: it stands (or hangs) where it is and does nothing else
				m.daze -= dt
				if m.daze <= 0 { m.daze = 0; m.dazeGuard = 1.2 }
				m.b.vx *= max(0, 1.0 - dt * 9.0)
				if m.def.flying { m.b.vy *= max(0, 1.0 - dt * 9.0) }
				stepMob(m, dt)
				mobHazards(m, dt)
				continue
			}
			// creatures well off screen wait until the player comes closer (saves a lot of work)
			if !m.isBoss && !m.tame && m.boat < 0 && (dx > 72 || dy > 56) { continue }
			// mid-distance creatures think and move at a third of the rate, staggered by id, with the
			// skipped time folded into their next step so they still cover the same ground
			var step: Double = dt
			if !m.isBoss && !m.tame && m.boat < 0 && (dx > 40 || dy > 30) {
				m.aiAccum += dt
				if (frameNo &+ m.id) % 3 != 0 {
					Perf.shared.countSkip()
					continue
				}
				step = min(0.1, m.aiAccum)
			}
			m.aiAccum = 0
			updateMob(m, step)
			if m.hp > 0 { mobHazards(m, step) }
		}
		updateDying(dt)
		// compact once: drop removed mobs and finished death animations
		if mobs.contains(where: { $0.removed }) { mobs.removeAll { $0.removed } }
		Perf.shared.aiMs = Perf.smooth(Perf.shared.aiMs, perfNow() - t0)
	}

	func nearestHostileTo(_ x: Double, _ y: Double, _ r: Double) -> Mob? {
		var best: Mob? = nil
		var bd: Double = r * r
		for o in mobs {
			if o.hp <= 0 || o.tame || !o.def.hostile { continue }
			let dx: Double = o.b.x - x
			let dy: Double = o.b.cy - y
			let d: Double = dx * dx + dy * dy
			if d < bd { bd = d; best = o }
		}
		return best
	}

	func updateMob(_ m: Mob, _ dt: Double) {
		if m.kind == .custom {
			updateCustomMob(m, dt)
			return
		}
		let d: MobDef = m.def
		if m.kind == .bearBoss || m.kind == .rex {
			updateBossMob(m, dt)
			return
		}
		if m.kind == .sentinel { updateSentinel(m, dt); return }
		if m.kind == .warden { updateWarden(m, dt); return }
		if m.boat >= 0 && updateCrew(m, dt) { return }
		let toPX: Double = pb.x - m.b.x
		let dist: Double = abs(toPX)
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		let near: Bool = dist < d.aggro && abs(dyP) < 14 && !dead
		let peaceful: Bool = settings.peaceful
		if m.tame {
			updatePet(m, dt)
			return
		}
		// monsters decide for themselves whether they are after the player (see think)
		var engaged: Bool = near && !peaceful
		if m.kind.thinks { engaged = think(m, dt, dist, dyP) }
		switch m.kind {
		case .custom:
			// run by updateCustomMob (never reaches here)
			stepMob(m, dt)
		case .pig, .cow, .sheep, .villager:  // (villagers are retired and never appear)
			if m.t2 > 0 {
				m.t2 -= dt
				flee(m, m.tx, dt, 1.9)
			} else if !animalLife(m, dt) {
				wander(m, dt, 0.55)
			}
			stepMob(m, dt)
		case .giraffe, .chicken, .frog, .cat:
			if m.t2 > 0 {
				m.t2 -= dt
				flee(m, m.tx, dt, 1.7)
			} else if !(dist < 6.0 && !dead && m.kind != .cat) && m.kind != .cat && animalLife(m, dt) {
				// handled: resting, heading for water or the herd
			} else if dist < 6.0 && !dead && m.kind != .cat {
				flee(m, pb.x, dt, 1.4)
			} else {
				wander(m, dt, 0.5)
			}
			if m.kind == .frog && m.b.onGround && m.st == 1 && Double.random(in: 0...1) < 0.04 { m.b.vy = -9; m.b.vx = Double(m.dir) * 3.5 }
			stepMob(m, dt)
		case .elephant, .bear, .wolf:
			if m.drinkT > 0 && m.kind == .wolf { m.drinkT -= dt }
			// a wolf that turns on the player forgets its prey
			if m.angry { m.preyID = 0 }
			if !m.angry && m.kind == .wolf && hunt(m, dt, isNight && m.drinkT <= 0) {
				// a wolf pack runs down prey at night
			} else if m.angry && !dead {
				m.t3 -= dt
				if m.t3 <= 0 || dist > 30 { m.angry = false } else {
					chase(m, pb.x, 1.0, dt)
					if m.kind == .wolf && m.b.onGround && dist < 4.0 && Double.random(in: 0...1) < 0.03 { m.b.vy = -12; m.b.vx = Double(m.dir) * 7.0 }
					if peaceful { m.angry = false }
					else { contactHurt(m, d.dmg) }
				}
			} else {
				// animals are neutral: only a blow from the player makes them fight (see hurtMob)
				wander(m, dt, 0.5)
			}
			stepMob(m, dt)
		case .grizzly, .polarBear, .tiger, .scorpion:
			if m.drinkT > 0 { m.drinkT -= dt }
			// wild animals hunt their prey but leave the player alone, unless the player hurts them:
			// then they fight back for a while
			let provoked: Bool = wildProvoked(m)
			if !(provoked && !peaceful) && m.kind != .scorpion && hunt(m, dt, m.drinkT <= 0) {
				// hunting, or resting after a kill
			} else if !(provoked && !peaceful) {
				wander(m, dt, 0.4)
			} else if !dead {
				chase(m, pb.x, 1.0, dt)
				if m.kind == .tiger && m.b.onGround && dist < 6.5 && dist > 2.0 && m.cd <= 0.4 && Double.random(in: 0...1) < 0.04 {
					m.b.vy = -11.5
					m.b.vx = Double(m.dir) * 10.0
					m.t3 = 0.6
				}
				contactHurt(m, d.dmg)
			} else {
				wander(m, dt, 0.5)
			}
			stepMob(m, dt)
		case .zombie:
			updateZombie(m, dt, engaged, dyP)
		case .skeleton, .pirate, .pirateCaptain:
			updateSwordsman(m, dt, engaged, dist, dyP)
		case .pirateGunner, .imp:
			updateShooter(m, dt, engaged, dist, dyP)
		case .slime, .emberSlime:
			updateSlime(m, dt, engaged, dyP)
		case .crow, .bat, .cinderBat, .wraith:
			updateFlyer(m, dt, engaged, dist, dyP)
		case .fish:
			updateFish(m, dt)
		case .crawler:
			updateCrawler(m, dt, engaged, dist, dyP)
		case .golem:
			updateGolem(m, dt, engaged, dist, dyP)
		case .archer:
			updateArcher(m, dt, engaged, dist, dyP)
		case .mimic:
			updateMimic(m, dt, !peaceful && !dead && dist < 20, dist, dyP)
		case .bearBoss, .rex, .sentinel, .warden:
			break
		}
	}

	// MARK: hostile minds

	/// How far a monster's attack reaches (across, up or down) and whether it is shot from afar
	/// How far a creature's attack reaches: a mutated creature's blows reach as far as its size
	func attackReach(_ m: Mob) -> (Double, Double, Bool) {
		let r: (Double, Double, Bool) = attackReachBase(m)
		if m.mutSize <= 1.001 || r.2 { return r }
		return (r.0 * m.mutSize, r.1 * m.mutSize, r.2)
	}

	func attackReachBase(_ m: Mob) -> (Double, Double, Bool) {
		switch m.kind {
		case .zombie: return (1.5, 1.7, false)
		case .skeleton, .pirate, .pirateCaptain: return (2.0, 1.6, false)
		case .pirateGunner, .imp: return (17.0, 9.0, true)
		case .archer: return (18.0, 10.0, true)
		case .crawler: return (4.6, 2.0, false)
		case .golem: return (3.3, 2.4, false)
		case .custom: return ModRuntime.shared.mob(m.cslot)?.reach ?? (m.b.w * 0.5 + 0.5, 1.4, false)
		default: return (m.b.w * 0.5 + 0.5, 1.4, false)
		}
	}

	/// A monster's senses and its plan, the same for every kind (each has its own attacks).
	/// It notices the player by sight (a clear line from its eyes, rechecked a few times a second),
	/// by sound up close, or by being hit; after a beat of surprise it gives chase; when the player
	/// slips out of sight it searches where they were last seen, then goes home. Stuck against a wall
	/// it tries one harder leap, then backs off and comes again. Night hunters spawned on the surface
	/// roam toward the player before they have seen them. Returns whether it is after the player;
	/// `aimX` is where it is heading.
	func think(_ m: Mob, _ dt: Double, _ dist: Double, _ dyP: Double) -> Bool {
		let d: MobDef = m.def
		m.aiT += dt
		if m.leapT > 0 { m.leapT -= dt }
		if m.hunter && (m.kind == .skeleton || m.kind == .archer) && inSunlight(m) { m.burn = 2.0 }
		if dead || settings.peaceful {
			m.why = dead ? .playerGone : .peaceful
			if m.ai != .idle && m.ai != .back { m.ai = .back; m.aiT = 0 }
			if m.ai == .back && (abs(m.b.x - m.homeX) < 2.0 || m.aiT > 8.0) { m.ai = .idle; m.aiT = 0 }
			m.aimX = m.homeX
			return false
		}
		m.losT -= dt
		if m.losT <= 0 {
			// its eyes (a golem looks over a low wall) to the player's head or chest
			m.losT = 0.18 + Double(m.id % 7) * 0.02
			let ey: Double = m.kind == .golem ? m.b.top - 0.5 : shotY(m)
			m.sees = m.kind == .wraith || world.lineClear(m.b.x, ey, pb.x, pb.y - pb.h * 0.6) || world.lineClear(m.b.x, ey, pb.x, pb.top + 0.2)
			// smoke hides the player from eyes on either side of it
			if m.sees && !smokes.isEmpty && (inSmoke(pb.x, pb.cy) || inSmoke(m.b.x, m.b.cy)) { m.sees = false }
		}
		// sight reaches across most of the screen (further for the night's hunters, and for one already
		// fighting); footsteps and scent carry through walls over a shorter distance
		let base: Double = max(d.aggro, 16.0)
		let sight: Double = base * (m.hunter ? 1.25 : 1.0) * (m.ai == .chase ? 1.5 : 1.0)
		let sense: Double = base * 0.7
		let hurt: Bool = clock - m.lastHitByPlayer < 0.6
		let heard: Bool = dist < 3.5 && abs(dyP) < 3.0
		let detect: Bool = hurt || heard || (dist < sight && abs(dyP) < 12.0 && m.sees)
		let sensed: Bool = dist < sense && abs(dyP) < 10.0
		if detect || sensed {
			m.seenX = pb.x
			m.seenY = pb.y
			m.lostT = 0
		} else {
			m.lostT += dt
		}
		let hunting: Bool = m.hunter && isNight && world.dim == .overworld && dist < 80
		switch m.ai {
		case .idle, .back:
			if detect {
				m.ai = hurt ? .chase : .alert
				m.aiT = 0
			} else if sensed {
				// something moving nearby, out of sight: it goes to look
				m.ai = .search
				m.aiT = 0
			} else if hunting {
				// a hunter roams toward where the player is, give or take
				m.ai = .search
				m.aiT = 0
				m.seenX = pb.x + Double.random(in: -6...6)
				m.seenY = pb.y
			}
		case .alert:
			if m.aiT > 0.35 { m.ai = .chase; m.aiT = 0 }
		case .chase:
			if m.lostT > 2.5 { m.ai = .search; m.aiT = 0 }
		case .search:
			if detect {
				m.ai = .chase
				m.aiT = 0
			} else if sensed {
				m.aiT = 0
			} else if (abs(m.b.x - m.seenX) < 1.2 && m.aiT > 2.0) || m.aiT > (hunting ? 14.0 : 8.0) {
				if hunting {
					m.seenX = pb.x + Double.random(in: -8...8)
					m.seenY = pb.y
					m.aiT = 0
				} else {
					m.ai = .back
					m.aiT = 0
				}
			}
		case .retreat:
			if m.aiT > 2.5 { m.ai = detect ? .chase : .search; m.aiT = 0 }
		}
		switch m.ai {
		case .alert, .chase: m.aimX = pb.x
		case .search: m.aimX = m.seenX
		case .retreat: m.aimX = m.b.x + (m.b.x >= m.seenX ? 6.0 : -6.0)
		case .back: m.aimX = m.homeX
		case .idle: m.aimX = m.b.x
		}
		if m.ai == .back && abs(m.b.x - m.homeX) < 2.0 { m.ai = .idle; m.aiT = 0 }
		// getting nowhere (pressed against a wall it can't get over, or hopping at it): one harder
		// leap, then back off and come again. One already within reach of its attack is not stuck.
		let reach: (Double, Double, Bool) = attackReach(m)
		let inReach: Bool = dist <= reach.0 && abs(dyP) <= reach.1 && (!reach.2 || m.sees)
		// (states 0 and 1 are walking about; 3 and up are its attacks)
		let pushing: Bool = (m.ai == .chase || m.ai == .search) && abs(m.aimX - m.b.x) > 1.0 && m.st <= 1 && !(m.ai == .chase && inReach)
		if pushing {
			if abs(m.b.x - m.progX) > 0.6 {
				m.progX = m.b.x
				m.blockedT = max(0, m.blockedT - 0.5)
			} else {
				// a cactus or spikes in the way: it gives up on that much sooner
				let ax: Int = Int(floor(m.b.x + Double(m.dir) * (m.b.w * 0.5 + 0.3)))
				let thorny: Bool = world.tile(ax, Int(floor(m.b.y - 0.5))).hurts
				m.blockedT += thorny ? dt * 3.0 : dt
			}
			// (applied in stepMob, after the creature's own moves, so its usual hop can't cancel it)
			if !d.flying && m.blockedT > 0.9 && m.leapT <= 0 { m.leapReq = true }
			if m.blockedT > 3.2 {
				m.ai = .retreat
				m.aiT = 0
				m.blockedT = 0
			}
		} else if m.st <= 1 {
			m.progX = m.b.x
			m.blockedT = max(0, m.blockedT - dt * 0.5)
		}
		// the reason it is not attacking right now (shown by the AI overlay)
		if m.ai == .retreat || m.blockedT > 0.9 { m.why = .blocked }
		else if m.ai != .chase && m.ai != .alert { m.why = .notSeen }
		else if dist > reach.0 { m.why = .outOfRange }
		else if abs(dyP) > reach.1 { m.why = .tooHigh }
		else if reach.2 && !m.sees { m.why = .noSight }
		else if m.cd > 0 { m.why = .cooldown }
		else { m.why = .none }
		return m.ai != .idle && m.ai != .back
	}

	// MARK: specific AIs

	/// Out in full daylight under an open sky (the undead burn)
	func inSunlight(_ m: Mob) -> Bool {
		return world.dim == .overworld && dayFactor > 0.7 && precipAt(m.b.x) < 0.5 && wxHere.cloud < 0.9 && world.isSkyExposed(Int(floor(m.b.x)), Int(floor(m.b.y - 1))) && !m.b.inWater
	}

	func updateZombie(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dyP: Double) {
		let d: MobDef = m.def
		if inSunlight(m) { m.burn = 2.0 }
		let dist: Double = abs(pb.x - m.b.x)
		if m.st == 3 {
			// arms drawn back: the swipe lands a moment later, so a quick step back dodges it
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.25
				mobStrike(m, reach: 1.2, height: 1.8, dmg: d.dmg, knock: 6.5)
			}
		} else if m.st == 4 {
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 0
				m.cd = 0.9
			}
		} else if aggro {
			chase(m, m.aimX, 1.0, dt)
			if m.ai == .chase && (m.sees || dist < 1.0) && m.cd <= 0 && dist < 1.5 && abs(dyP) < 1.7 {
				m.st = 3
				m.t3 = 0.32
				m.dir = pb.x >= m.b.x ? 1 : -1
			}
		} else {
			wander(m, dt, 0.45)
		}
		stepMob(m, dt)
	}

	/// skeleton knight (shield), pirate and captain (cutlass)
	func updateSwordsman(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		let isSkel: Bool = m.kind == .skeleton
		if m.st == 3 {
			// wind-up
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.22
				// strike
				mobStrike(m, reach: 2.2, height: 1.9, dmg: d.dmg, knock: 7.0)
			}
		} else if m.st == 4 {
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 0
				m.cd = m.kind == .pirateCaptain ? 0.9 : 1.2
			}
		} else if aggro {
			let sp: Double = dist > 8 ? 1.15 : 0.95
			if isSkel {
				// raise the shield while approaching, drop it to attack
				m.blocking = dist > 2.4 && dist < 11 && m.ai == .chase
				if m.ai == .chase && m.sees && dist < 2.0 && m.cd <= 0 && abs(dyP) < 1.6 {
					m.st = 3
					m.t3 = 0.38
					m.blocking = false
					m.dir = pb.x >= m.b.x ? 1 : -1
				}
				chase(m, m.aimX, m.blocking ? 0.7 : sp, dt)
			} else {
				if m.ai == .chase && m.sees && dist < 2.0 && m.cd <= 0 && abs(dyP) < 1.6 {
					m.st = 3
					m.t3 = 0.3
					m.dir = pb.x >= m.b.x ? 1 : -1
				}
				chase(m, m.aimX, sp, dt)
			}
		} else {
			m.blocking = false
			wander(m, dt, 0.4)
		}
		if m.st == 0 && !aggro { m.blocking = false }
		stepMob(m, dt)
	}

	/// pirate gunner and imp: keep range and shoot
	func updateShooter(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let isImp: Bool = m.kind == .imp
		if m.st == 3 {
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				if clearShot(m) {
					m.st = 6
					m.t3 = 0.18
					shootAtPlayer(m, isImp)
				} else if m.t3 < -0.8 {
					m.st = 0
					m.cd = 0.4
					m.blockedT += 0.6
				}
			}
		} else if m.st == 6 {
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 { m.st = 0; m.cd = isImp ? 1.9 : 2.2 }
		} else if aggro {
			let want: Double = isImp ? 8.0 : 9.0
			if (m.ai != .chase && m.ai != .alert) || !m.sees || m.blockedT > 0.5 || !m.b.onGround {
				// no clear shot (or climbing for one): move in until there is one
				chase(m, m.aimX, 0.9, dt)
			} else if dist < want - 3.0 {
				flee(m, pb.x, dt, 0.8)
			} else if dist > want + 3.0 {
				chase(m, pb.x, 0.9, dt)
			} else {
				accelX(m, 0, 20, dt)
				m.dir = pb.x >= m.b.x ? 1 : -1
			}
			if m.ai == .chase && m.sees && m.b.onGround && m.cd <= 0 && dist < 17 && abs(dyP) < 9 {
				m.st = 3
				m.t3 = 0.5
			}
		} else {
			wander(m, dt, 0.4)
		}
		stepMob(m, dt)
	}

	func shootAtPlayer(_ m: Mob, _ fire: Bool) {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let oy: Double = shotY(m)
		var dx: Double = pb.x - ox
		var dy: Double = shotAimY(m) - oy
		let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
		dx /= len
		dy /= len
		let sp: Double = fire ? 11.0 : 20.0
		var p = Projectile(kind: fire ? .fireball : .bullet, x: ox, y: oy, vx: dx * sp, vy: dy * sp, dmg: m.def.dmg, fromPlayer: false, gravity: 0)
		p.life = 3.0
		p.owner = m.id
		p.source = .mob(m, faction(of: m))
		p.uid = newID()
		projectiles.append(p)
		spawnParticles(ox, oy, fire ? 0xFF7020 : 0xFFE080, 4, 2.5, 0.18, 0)
	}

	func updateSlime(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dyP: Double) {
		let d: MobDef = m.def
		m.t1 -= dt
		if m.b.onGround {
			m.b.vx *= 0.8
			if m.t1 <= 0 {
				if aggro {
					let dirX: Double = m.aimX >= m.b.x ? 1.0 : -1.0
					m.dir = Int(dirX)
					m.b.vy = -d.jump
					m.b.vx = dirX * d.speed * 1.6
					m.t1 = Double.random(in: 0.7...1.3)
				} else {
					m.dir = Bool.random() ? 1 : -1
					m.b.vy = -8.5
					m.b.vx = Double(m.dir) * 2.0
					m.t1 = Double.random(in: 1.5...3.5)
				}
			}
		}
		if aggro && !m.b.onGround {
			// a little steering in mid-hop, so a bounce at a wall carries over it
			accelX(m, (m.aimX >= m.b.x ? 1.0 : -1.0) * d.speed * 1.6, 5, dt)
		}
		if m.kind == .emberSlime && Double.random(in: 0...1) < 0.1 {
			spawnParticles(m.b.x, m.b.y - 0.4, 0xFF8A20, 1, 1.2, 0.4, -3)
		}
		if aggro && m.ai == .chase { contactHurt(m, d.dmg) }
		stepMob(m, dt)
	}

	func updateFlyer(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		m.anim += dt * 8.0
		var tx: Double = m.homeX
		var ty: Double = m.homeY
		var spd: Double = d.speed * 0.6
		if m.kind == .crow {
			// wander around home; flee when approached
			m.t1 -= dt
			if m.t1 <= 0 {
				m.t1 = Double.random(in: 2...5)
				m.tx = m.homeX + Double.random(in: -12...12)
				let gy: Double = Double(world.surfaceY(Int(floor(m.tx))))
				m.ty = gy - Double.random(in: 3...8)
			}
			tx = m.tx
			ty = m.ty
			if dist < 5.0 && !dead {
				tx = m.b.x + (m.b.x - pb.x) * 3
				ty = m.b.y - 6
				spd = d.speed * 1.4
			}
		} else if aggro {
			tx = m.aimX
			ty = (m.ai == .chase ? pb.y : m.seenY) - 1.3 + sin(clock * 3.0 + Double(m.id)) * 1.2
			spd = d.speed
		} else {
			m.t1 -= dt
			if m.t1 <= 0 {
				m.t1 = Double.random(in: 1.5...4)
				m.tx = m.b.x + Double.random(in: -8...8)
				m.ty = m.b.y + Double.random(in: -4...4)
			}
			tx = m.tx
			ty = m.ty
		}
		var ax: Double = tx - m.b.x
		var ay: Double = ty - m.b.y
		let len: Double = max(0.001, sqrt(ax * ax + ay * ay))
		ax /= len
		ay /= len
		m.b.vx += (ax * spd - m.b.vx) * min(1.0, dt * 4.0)
		m.b.vy += (ay * spd - m.b.vy) * min(1.0, dt * 4.0)
		if abs(m.b.vx) > 0.3 { m.dir = m.b.vx > 0 ? 1 : -1 }
		if m.kind == .wraith {
			// drifts through walls, slower inside solid tiles
			let inside: Bool = world.solid(Int(floor(m.b.x)), Int(floor(m.b.y - 0.7)))
			let k: Double = inside ? 0.5 : 1.0
			m.b.x += m.b.vx * dt * k
			m.b.y += m.b.vy * dt * k
		} else {
			world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
			if m.b.hitWall || m.b.hitCeil || m.b.onGround { m.b.vy = -1.0; m.t1 = 0 }
		}
		if aggro && m.kind != .crow && m.ai == .chase { contactHurt(m, d.dmg) }
	}

	func updateFish(_ m: Mob, _ dt: Double) {
		m.anim += dt * 6.0
		if !m.b.inWater {
			// flopping on land
			m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
			world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
			m.t2 += dt
			if m.t2 > 1.0 { m.t2 = 0; hurtMob(m, 1, 0, 0, false) }
			return
		}
		m.t1 -= dt
		if m.t1 <= 0 {
			m.t1 = Double.random(in: 1.5...4)
			m.tx = m.b.x + Double.random(in: -8...8)
			m.ty = m.b.y + Double.random(in: -3...3)
		}
		if abs(pb.x - m.b.x) < 4 && abs(pb.y - m.b.y) < 3 && pb.inWater {
			m.tx = m.b.x + (m.b.x - pb.x) * 3
			m.ty = m.b.y + (m.b.y - pb.y) * 2
		}
		var ax: Double = m.tx - m.b.x
		var ay: Double = m.ty - m.b.y
		let len: Double = max(0.001, sqrt(ax * ax + ay * ay))
		ax /= len
		ay /= len
		let sp: Double = m.def.speed
		m.b.vx += (ax * sp - m.b.vx) * min(1.0, dt * 3.0)
		m.b.vy += (ay * sp * 0.6 - m.b.vy) * min(1.0, dt * 3.0)
		if abs(m.b.vx) > 0.2 { m.dir = m.b.vx > 0 ? 1 : -1 }
		let nx: Double = m.b.x + m.b.vx * dt
		let ny: Double = m.b.y + m.b.vy * dt
		let tx: Int = Int(floor(nx))
		let ty: Int = Int(floor(ny - 0.2))
		if world.tile(tx, ty) == .water && world.tile(tx, Int(floor(ny))) != .air {
			m.b.x = nx
			m.b.y = ny
		} else {
			m.t1 = 0
			m.b.vx = -m.b.vx
			m.b.vy = -m.b.vy
		}
		let hw: Double = m.b.w * 0.5
		m.b.inWater = world.liquidFraction(m.b.x - hw, m.b.y - m.b.h, m.b.x + hw, m.b.y, false) > 0.3
	}

	// MARK: pets

	func updatePet(_ m: Mob, _ dt: Double) {
		let d: MobDef = m.def
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		if dist > 45 || abs(pb.y - m.b.y) > 30 {
			m.b.x = pb.x - Double(facing) * 1.5
			m.b.y = pb.y
			m.b.vx = 0
			m.b.vy = 0
			return
		}
		if m.st == 7 {
			accelX(m, 0, 20, dt)
			stepMob(m, dt)
			return
		}
		// attack nearby hostiles
		var target: Mob? = nil
		if m.kind == .wolf {
			target = nearestHostileTo(pb.x, pb.y - 1, 9.0)
		}
		if let t = target, t.hp > 0 {
			chase(m, t.b.x, 1.2, dt)
			if m.cd <= 0 && abs(t.b.x - m.b.x) < 1.6 && abs(t.b.cy - m.b.cy) < 1.5 {
				hurtMob(t, 7, Double(m.dir), 5.0, true)
				m.cd = 0.7
			}
		} else if dist > 3.5 {
			let sp: Double = dist > 12 ? 1.8 : 1.15
			chase(m, pb.x, sp, dt)
		} else {
			accelX(m, 0, 20, dt)
		}
		_ = d
		stepMob(m, dt)
	}

	func tryTame(_ m: Mob) -> Bool {
		if m.tame { return false }
		guard let it = heldItem else { return false }
		var ok: Bool = false
		if m.kind == .wolf, case .mat(let mm) = it, mm == .bone { ok = true }
		if m.kind == .cat, case .food(let f) = it, f == .rawFish || f == .cookedFish { ok = true }
		if !ok { return false }
		if !isCreative { inv.removeAt(sel, 1) }
		if Double.random(in: 0...1) < 0.6 {
			m.tame = true
			m.persistent = true
			m.angry = false
			m.hp = m.maxHP
			say("You tamed the " + m.def.name.lowercased() + "!", 3.0)
			spawnParticles(m.b.x, m.b.y - 1, 0xFF6080, 10, 3.0, 0.8, -4)
		} else {
			say("The " + m.def.name.lowercased() + " isn't convinced yet...", 2.0)
		}
		useCD = 0.5
		bumpHUD()
		return true
	}
}

// ===== p15b_spawn =====

// MARK: - Mob spawning

extension Game {
	/// Notes how a spawn attempt ended (the debug panel shows the tally)
	func spawnNote(_ s: String) {
		spawnLast = s
		if spawnLog.count < 40 || spawnLog[s] != nil { spawnLog[s, default: 0] += 1 }
	}

	/// The most lamplight a monster may come out in (0...15). A torch (12) keeps them off the ground
	/// about seven blocks round it in the open, less where walls or ground stand in the way.
	static let spawnGlowMax: Int = 4

	/// The light at a creature's two cells above its feet at (x, feetY), worked out by the game's own
	/// light flood over the ground around it, on screen or not: (sky light, light of glowing blocks).
	/// Torches, lanterns, campfires, lamps, glowing mod blocks and every other light-giving block count,
	/// fading with distance and held back by walls and ground; a torch in the player's hand does not.
	func lightForSpawn(_ x: Int, _ feetY: Int) -> (Int, Int) {
		if !spawnLight.covers(x - 1, feetY - 3, x + 1, feetY) || spawnLight.stamp != world.version || spawnLight.skyUsed != skyLevel || spawnLight.dimUsed != world.dim.rawValue {
			let r: Int = 18
			spawnLight.compute(world, x - r, feetY - r, r * 2 + 1, r * 2 + 1, skyLevel, [], noteSeen: false)
		}
		let a: (Int, Int) = spawnLight.level(x, feetY - 1)
		let b: (Int, Int) = spawnLight.level(x, feetY - 2)
		return (max(a.0, b.0), max(a.1, b.1))
	}

	/// Ground monsters can come out on: earth, sand, snow and rock, never planks, brick, glass or other
	/// building blocks (so not on the roof or floor of a house)
	func naturalGround(_ t: Tile) -> Bool {
		switch t {
		case .grass, .dirt, .stone, .sand, .snow, .ice, .sandstone, .mud, .dryGrass, .jungleGrass, .mossGrass,
			 .slate, .deepRock, .obsidian, .ashStone, .farmland, .coal, .copper, .iron, .tin, .saltpeter: return true
		default: return false
		}
	}

	/// How many monsters may be about at once (surface or underground) at this night-danger setting
	func monsterCap(_ place: SpawnPlace) -> Int {
		let d: Int = clampI(settings.nightDanger, 0, 2)
		let base: Int = (place == .surface || place == .ocean) ? [3, 6, 10][d] : [6, 9, 12][d]
		return Int((Double(base) * ModRuntime.shared.rule(.monsters)).rounded())
	}

	/// How many animals (and fish) may be about at once (9, or as a mod's rule has it)
	var animalCap: Int { return Int((9.0 * ModRuntime.shared.rule(.animals)).rounded()) }

	func updateSpawning(_ dt: Double) {
		if monsterSpawnCD > 0 { monsterSpawnCD -= dt }
		spawnTimer -= dt
		if spawnTimer > 0 { return }
		spawnTimer = Double.random(in: 0.45...1.0)
		if dead { return }
		var passive: Int = 0
		var hostile: Int = 0
		var predators: Int = 0
		var aquatic: Int = 0
		for m in mobs {
			if m.hp <= 0 || m.removed || m.tame || m.persistent { continue }
			let dx: Double = abs(m.b.x - pb.x)
			if dx > 100 { continue }
			if m.kind == .fish { aquatic += 1 }
			else if m.def.hostile {
				// only creatures still in play hold a place: bosses, lair guards and crews have their own
				// rules, and one standing frozen far off-screen is about to leave
				if m.isBoss || m.boat >= 0 || m.lair != 0 || dx > 72 || abs(m.b.y - pb.y) > 56 { continue }
				if m.kind.isPredator { predators += 1 } else { hostile += 1 }
			}
			else { passive += 1 }
		}
		let px: Int = Int(floor(pb.x))
		var place: SpawnPlace = .surface
		if world.dim == .umbral {
			place = .umbral
		} else {
			let sh: Int = world.dim.isCustom ? customSurface(px) : gen.col(px).h
			let open: Bool = world.isSkyExposed(px, Int(pb.y) - 1)
			let depth: Int = Int(pb.y) - sh
			if depth > 18 && !open { place = .cave }
		}
		// just past the edge of the screen, so what comes is soon in sight
		let half: Double = viewTilesW * 0.5 + 3.0
		let side: Double = Bool.random() ? 1.0 : -1.0
		let sx: Double = pb.x + side * (half + Double.random(in: 1...16))
		let ix: Int = Int(floor(sx))
		if !world.isLoaded(ix) { spawnNote("spot not loaded"); return }
		if !gen.infinite && (ix < 4 || ix > gen.width - 5) { return }
		var sy: Double = 0
		var eff: SpawnPlace = place
		if place == .surface {
			let h: Int = world.surfaceY(ix)
			let ht: Tile = world.tile(ix, h)
			if ht.liquid {
				eff = .ocean
				var wy: Int = h + 1
				var dep: Int = 0
				while world.tile(ix, wy) == .water && dep < 40 { wy += 1; dep += 1 }
				if dep < 5 { spawnNote("shallow water"); return }
				sy = Double(h + 2 + Int.random(in: 0..<max(1, dep - 3)))
			} else if ht.solid {
				if world.solid(ix, h - 1) || world.solid(ix, h - 2) || world.tile(ix, h - 1).liquid { spawnNote("no headroom"); return }
				sy = Double(h)
			} else { spawnNote("no ground"); return }
		} else {
			let startY: Int = Int(pb.y) + Int.random(in: -20...20)
			var found: Bool = false
			var y: Int = startY
			var tries: Int = 0
			while tries < 22 {
				if !world.solid(ix, y) && !world.solid(ix, y - 1) && !world.solid(ix, y - 2) && world.solid(ix, y + 1) && !world.tile(ix, y).liquid {
					found = true
					break
				}
				y += 1
				tries += 1
			}
			if !found { spawnNote("no floor"); return }
			if place == .cave && world.isSkyExposed(ix, y) { spawnNote("open sky"); return }
			// lamplight, or daylight reaching in from a cave mouth
			let lit: (Int, Int) = lightForSpawn(ix, y + 1)
			if lit.1 > Game.spawnGlowMax || lit.0 > 6 { spawnNote("too bright"); return }
			sy = Double(y + 1)
		}
		let biome: Biome = biomeAt(Double(ix))
		// under a dark storm by day, now and then the night's creatures come out too
		let stormDark: Bool = world.dim == .overworld && settings.weatherOn && wxHere.cloud > 0.9 && wxHere.precip > 0.6 && Double.random(in: 0...1) < 0.35
		let night: Bool = isNight || stormDark
		// on the surface, monsters stay out of lamplight, off roofs and away from ground far above or
		// below the player (somewhere they could never reach them from)
		var monsterBlock: String = ""
		if eff == .surface {
			let gy: Int = Int(sy)
			if lightForSpawn(ix, gy).1 > Game.spawnGlowMax { monsterBlock = "lit by a lamp" }
			else if !naturalGround(world.tile(ix, gy)) { monsterBlock = "on a building" }
			else if abs(sy - pb.y) > 30 { monsterBlock = "out of reach" }
			else if monsterSpawnCD > 0 { monsterBlock = "pacing" }
		}
		let cap: Int = monsterCap(eff)
		var capped: Bool = false
		var cands: [SpawnRule] = []
		var total: Double = 0
		// the custom creatures of the world's mods spawn by the same rules, beside the game's own
		let rt: ModRuntime = ModRuntime.shared
		// a custom dimension has only its own creatures
		let rules: [SpawnRule] = world.dim.isCustom ? (customDim?.spawnRules ?? []) : (rt.spawnRules.isEmpty ? spawnRules : spawnRules + rt.spawnRules)
		var customN: Int = -1
		for r in rules {
			if r.place != eff { continue }
			if r.when == .day && night { continue }
			if r.when == .night && !night { continue }
			if !r.biomes.isEmpty && !r.biomes.contains(biome) { continue }
			if eff == .cave || eff == .umbral || r.slot >= 0 {
				if Int(sy) < r.minY || Int(sy) > r.maxY { continue }
			}
			var d: MobDef = mobDef(r.kind)
			if r.slot >= 0 {
				guard let cr = rt.mob(r.slot) else { continue }
				d = cr.mdef
				if customN < 0 { customN = customMobCount() }
				if customN >= ModLimits.maxActiveMobs || customNearby(r.slot) >= r.maxNearby { continue }
			}
			if d.hostile {
				if !monstersEnabled || settings.peaceful { continue }
				if r.kind.isPredator {
					// wild predators have their own small number and come by day too
					if predators >= min(3, cap) { continue }
				} else {
					if hostile >= cap { capped = true; continue }
					if !monsterBlock.isEmpty { continue }
				}
			} else if r.kind == .fish || (r.slot >= 0 && r.place == .ocean) {
				if aquatic >= animalCap { continue }
			} else {
				if passive >= animalCap { continue }
			}
			cands.append(r)
			total += r.weight
		}
		if cands.isEmpty || total <= 0 {
			if capped { spawnNote("monster limit reached") }
			else if !monsterBlock.isEmpty && night { spawnNote(monsterBlock) }
			else { spawnNote(night ? "nothing for this place" : "nothing for this place by day") }
			return
		}
		var pick: Double = Double.random(in: 0..<total)
		var chosen: SpawnRule = cands[0]
		for r in cands {
			pick -= r.weight
			if pick <= 0 { chosen = r; break }
		}
		let def: MobDef = chosen.slot >= 0 ? (rt.mob(chosen.slot)?.mdef ?? mobDef(chosen.kind)) : mobDef(chosen.kind)
		let monster: Bool = def.hostile && !chosen.kind.isPredator
		var n: Int = 1 + Int.random(in: 0..<max(1, chosen.group))
		if monster { n = min(n, cap - hostile) }
		var made: Int = 0
		for k in 0..<n {
			let ox: Double = Double(k) * 1.1 * side + Double.random(in: -0.4...0.4)
			let x: Double = sx + ox
			var y: Double = sy
			// every member finds its own footing: the ground in its own column on the surface, and
			// nobody appears inside a wall or hanging over a drop
			if eff == .surface && !def.flying {
				let gyS: Int = world.surfaceY(Int(floor(x)))
				if world.tile(Int(floor(x)), gyS).liquid || abs(gyS - Int(sy)) > 3 { continue }
				y = Double(gyS)
			}
			if def.flying && eff != .ocean { y -= chosen.sky ? Double.random(in: 7...14) : Double.random(in: 1...3) }
			// each monster of a group only comes out where it is dark enough itself
			if monster && eff != .ocean && lightForSpawn(Int(floor(x)), Int(floor(y))).1 > Game.spawnGlowMax { continue }
			if eff != .ocean && !spawnSpotClear(def, x, y) { continue }
			var made1: Mob? = nil
			if chosen.slot >= 0 { made1 = addCustomMob(chosen.slot, x, y) } else { made1 = addMob(chosen.kind, x, y) }
			guard let m = made1 else { continue }
			m.homeX = x
			m.homeY = y
			// the night's monsters on the surface come looking for the player
			if monster && eff == .surface && night { m.hunter = true }
			if chosen.kind == .sheep && Double.random(in: 0...1) < 0.1 { m.sheared = true }
			made += 1
		}
		if made == 0 { spawnNote("no room to stand"); return }
		spawnNote(joinText("spawned ", def.name))
		if monster && eff == .surface {
			let d: Int = clampI(settings.nightDanger, 0, 2)
			monsterSpawnCD = [8.0, 4.0, 2.0][d] * Double.random(in: 0.8...1.25)
		}
	}

	/// How many of one custom creature are about near the player
	func customNearby(_ slot: Int) -> Int {
		var n: Int = 0
		for m in mobs where m.kind == .custom && m.cslot == slot && m.hp > 0 && !m.removed && abs(m.b.x - pb.x) < 100 { n += 1 }
		return n
	}

	/// Room for a creature of this size standing at (x, y): no solid tile inside its box, and (unless it
	/// flies) something to stand on under its feet
	func spawnSpotClear(_ d: MobDef, _ x: Double, _ y: Double) -> Bool {
		let hw: Double = d.w * 0.5
		if world.boxSolid(x - hw + 0.02, y - d.h, x + hw - 0.02, y - 0.05) { return false }
		if d.flying { return true }
		let gy: Int = Int(floor(y + 0.05))
		let l: Int = Int(floor(x - hw + 0.05))
		let r: Int = Int(floor(x + hw - 0.05))
		var footing: Int = 0
		for tx in l...r where world.solid(tx, gy) || world.tile(tx, gy).isPlatform { footing += 1 }
		return footing * 2 >= (r - l + 1)
	}
}

// ===== p16a_combat =====

// MARK: - Combat: damage, death, projectiles, drops, particles

extension Game {
	func hurtMob(_ m: Mob, _ dmg: Double, _ dirX: Double, _ knock: Double, _ byPlayer: Bool, heavy: Bool = false, crit: Bool = false) {
		if m.hp <= 0 { return }
		if m.kind == .rex && m.tame && byPlayer { return }
		// a wild animal remembers being hurt by the player (it fights back, see wildProvoked)
		if byPlayer { m.lastHitByPlayer = clock }
		var d: Double = byPlayer ? dmg * ModRuntime.shared.rule(.hit) : dmg
		var kb: Double = knock
		if m.blocking && m.kind == .skeleton && dirX != 0 && dirX * Double(m.dir) < 0 {
			if heavy {
				// a hammer blow knocks the shield aside and leaves the skeleton open for a moment
				m.blocking = false
				m.cd = max(m.cd, 0.9)
				spawnParticles(m.b.x - Double(m.dir) * 0.5, m.b.y - 1.0, 0xFFF0C0, 8, 5.0, 0.25, 0)
				floatText("Guard broken", m.b.x, m.b.top - 0.4, 0xFFD080)
			} else {
				d *= 0.1
				kb *= 0.25
				spawnParticles(m.b.x - Double(m.dir) * 0.5, m.b.y - 1.0, 0xE8F0FF, 5, 4.0, 0.2, 0)
				floatText("Blocked", m.b.x, m.b.top - 0.4, 0xA0C0FF)
			}
		}
		if d < 0.5 { d = 0.5 }
		m.hp -= d
		m.hurtT = 0.22
		m.flash = 0.12
		if dirX != 0 && kb > 0 { m.lean = clampD(dirX * kb / 9.0, -1, 1) }
		var resist: Double = m.isBoss ? 0.97 : (m.def.w > 2.0 ? 0.6 : 0.0)
		if m.kind == .golem { resist = heavy ? 0.45 : 0.88 }
		if m.kind == .custom, let r = ModRuntime.shared.mob(m.cslot) { resist = max(resist, clampD(r.def.knockResist, 0, 1)) }
		if dirX != 0 && kb > 0 {
			m.b.vx = dirX * kb * (1.0 - resist)
			if resist < 0.9 { m.b.vy = min(m.b.vy, -3.5) }
		}
		if crit && byPlayer {
			floatText(String(Int(d.rounded())) + "!", m.b.x, m.b.top - 0.35, 0xFFE040)
		} else {
			floatText(String(Int(d.rounded())), m.b.x, m.b.top - 0.2, byPlayer ? 0xFFFFFF : 0xFFAA40)
		}
		spawnParticles(m.b.x, m.b.cy, m.kind == .skeleton ? 0xE8E8E0 : 0xB02828, 4, 3.0, 0.4, 14)
		switch m.def.behavior {
		case .passive, .skittish:
			m.t2 = 3.5
			m.tx = m.b.x - (dirX == 0 ? 1.0 : dirX) * 6.0
		case .defensive:
			// animals only hold a grudge against the player; hurt by anything else they just bolt
			if !byPlayer { break }
			m.angry = true
			m.t3 = 10.0
			if m.kind == .wolf {
				for o in mobs where o.kind == .wolf && !o.tame && abs(o.b.x - m.b.x) < 16 {
					o.angry = true
					o.t3 = 12.0
				}
			}
		default: break
		}
		if m.boat >= 0 { alertShip(m.boat) }
		if m.kind == .custom && !logicRT.isEmpty, let r = ModRuntime.shared.mob(m.cslot) { fireLogic(.hurt, mob: m, key: r.key) }
		if m.hp <= 0 { killMob(m, byPlayer) }
	}

	func killMob(_ m: Mob, _ byPlayer: Bool) {
		if m.kind == .rex && m.tame {
			downRex(m)
			return
		}
		m.hp = 0
		m.deathT = 0
		m.burn = 0
		// a creature the player hit recently still counts as the player's kill if lava, a fall or
		// another creature finishes it off
		let credit: Bool = byPlayer || clock - m.lastHitByPlayer < 6.0
		var rng = RNG(UInt64(truncatingIfNeeded: m.id) &* 6364136223846793005 &+ UInt64(truncatingIfNeeded: Int(clock * 1000)))
		for s in mobDrops(m.kind, &rng, m.sheared) {
			spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2...2), -4.5)
		}
		if m.kind == .custom { dropModLoot(m, &rng) }
		if m.kind == .custom && !logicRT.isEmpty, let r = ModRuntime.shared.mob(m.cslot) { fireLogic(.dies, mob: m, key: r.key) }
		for s in alchemyDrops(m, &rng, credit) {
			spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2...2), -4.5)
		}
		var col: UInt32 = 0xB02828
		if m.kind == .skeleton { col = 0xE8E8E0 }
		if m.kind == .slime { col = 0x60C060 }
		if m.kind == .emberSlime { col = 0xFF8A20 }
		spawnParticles(m.b.x, m.b.cy, col, Int(10 + m.b.w * 4), 5.0, 0.7, 14)
		if credit { kills += 1 }
		if m.kind == .bearBoss { onBearDefeated(m) }
		if m.kind == .rex { onRexDefeated(m) }
		if m.kind == .sentinel || m.kind == .warden { onGuardianDefeated(m) }
		for s in m.loot { spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2.5...2.5), -5.0) }
		m.loot = []
		if m === activeBoss { activeBoss = nil }
		bumpHUD()
	}

	func addMob(_ kind: MobKind, _ x: Double, _ y: Double) -> Mob {
		let m = Mob(id: newID(), kind: kind, x: x, y: y)
		if kind == .zombie { m.variant = Int.random(in: 0...2) }
		if mobHealthMult != 1.0 {
			m.maxHP *= mobHealthMult
			m.hp = m.maxHP
		}
		mobs.append(m)
		return m
	}

	// MARK: projectiles

	/// Steps every projectile. Collision is swept along the whole frame's movement, so fast arrows and
	/// bullets cannot skip over a target between frames, and the first thing along the path is hit.
	func updateProjectiles(_ dt: Double) {
		if projectiles.isEmpty { return }
		let list: [Projectile] = projectiles
		// projectiles created while stepping (none today, but explosions could) land in the fresh array
		projectiles = []
		var keep: [Projectile] = []
		keep.reserveCapacity(list.count)
		for p0 in list {
			var p: Projectile = p0
			if stepProjectile(&p, dt) { keep.append(p) }
		}
		if !projectiles.isEmpty { keep.append(contentsOf: projectiles) }
		projectiles = keep
	}

	/// Returns false when the projectile is used up
	func stepProjectile(_ p: inout Projectile, _ dt: Double) -> Bool {
		p.life -= dt
		if p.life <= 0 {
			if p.mod >= 0 { modShotLanded(p, p.x, p.y, mob: nil, player: false) }
			if p.kind == .bomb { explode(p.x, p.y, radius: 3.4, power: p.dmg, source: p.source, breakBlocks: true) }
			if p.kind == .shell { shellBurst(p, p.x, p.y) }
			if p.kind == .flask { burstFlaskOrPotion(p, p.x, p.y, nil) }
			return false
		}
		if p.stuck > 0 {
			p.stuck -= dt
			if p.stuck <= 0 && (p.kind == .arrow || p.kind == .quarrel) && p.source.kind == .player && !isCreative && Double.random(in: 0...1) < 0.35 {
				// some arrows and bolts survive and can be picked back up
				spawnDrop(Stack(item: .ammo(p.kind == .arrow ? .arrow : .bolt), count: 1), p.x, p.y, 0, -1)
			}
			return p.stuck > 0
		}
		if p.kind == .shock { return stepShock(&p, dt) }
		p.vy = min(p.vy + p.gravity * dt, 40.0)
		let nx: Double = p.x + p.vx * dt
		let ny: Double = p.y + p.vy * dt
		// first solid tile along the path
		var wallT: Double = 2.0
		var wallTile: (Int, Int) = (0, 0)
		if let hit = world.segmentSolidT(p.x, p.y, nx, ny) {
			wallT = hit.2
			wallTile = (hit.0, hit.1)
		}
		// a vehicle's parts stop shots aimed at it (the player's own shots pass their vehicles)
		var vehHit: VehicleHit? = nil
		if !vehicles.isEmpty && p.kind != .bomb { vehHit = vehicleOnPath(p, nx, ny, maxT: wallT) }
		let entityMax: Double = vehHit?.t ?? wallT
		// first creature (or the player) along the path, before the wall
		if p.kind != .bomb {
			if let target = firstEntityOnPath(p, nx, ny, maxT: entityMax) {
				let hx: Double = p.x + (nx - p.x) * target.t
				let hy: Double = p.y + (ny - p.y) * target.t
				if p.kind == .flask {
					burstFlaskOrPotion(p, hx, hy, target.mob)
					return false
				}
				if p.kind == .shell {
					shellBurst(p, hx, hy)
					return false
				}
				let dirx: Double = p.vx >= 0 ? 1.0 : -1.0
				var info = DamageInfo(amount: p.dmg, type: .projectile, source: p.source)
				info.dirX = dirx
				info.knock = p.knock > 0 ? p.knock : (p.kind == .bullet ? 4.0 : (p.kind == .arrow ? 3.5 : 3.0))
				info.originX = p.x
				info.originY = p.y
				info.key = p.uid
				info.cooldown = 1.0
				if p.kind == .fireball { info.type = .fire }
				if let m = target.mob {
					if applyMobDamage(m, info) {
						if p.mod >= 0 {
							let s: ModProjectile? = p.mod < ModRuntime.shared.shots.count ? ModRuntime.shared.shots[p.mod] : nil
							if let sh = s, sh.explode > 0 {
								modShotLanded(p, hx, hy, mob: m, player: false)
								return false
							}
							if let sh = s, sh.burn > 0 { m.burn = max(m.burn, sh.burn) }
						}
						if p.kind == .fireball { m.burn = max(m.burn, 2.5) }
						if p.inf != 0 || !p.custom.isEmpty { shotInfusionHit(p, m, hx, hy) }
						spawnParticles(hx, hy, p.kind == .fireball ? 0xFF8030 : 0xE8E0D0, 3, 2.5, 0.25, 8)
						if p.source.kind == .player {
							// a clear "it landed" for the player's own shots
							sfx(.arrowHit, 0.55)
							lockTarget = m
							lockT = 2.0
						}
					}
					p.lastHit = m.id
				} else {
					_ = hurtPlayer(info)
					if p.mod >= 0 {
						modShotLanded(p, hx, hy, mob: nil, player: true)
						return false
					}
					if p.kind == .fireball { playerBurn = max(playerBurn, 1.5); spawnParticles(hx, hy, 0xFF8030, 8, 4.0, 0.4, 6) }
				}
				if p.pierce > 0 && target.mob != nil {
					p.pierce -= 1
					p.dmg *= 0.7
				} else {
					return false
				}
			}
		}
		if let vh = vehHit {
			shotHitsVehicle(p, vh, p.x + (nx - p.x) * vh.t, p.y + (ny - p.y) * vh.t)
			return false
		}
		if wallT <= 1.0 {
			let hx: Double = p.x + (nx - p.x) * wallT
			let hy: Double = p.y + (ny - p.y) * wallT
			if p.mod >= 0 {
				modShotLanded(p, hx, hy, mob: nil, player: false)
				return false
			}
			if p.inf & 4 != 0 { volatileBurst(hx, hy) }
			switch p.kind {
			case .flask:
				burstFlaskOrPotion(p, hx, hy, nil)
				return false
			case .pebble:
				spawnParticles(hx, hy, 0x9A9A9A, 4, 2.5, 0.3, 14)
				return false
			case .arrow, .quarrel:
				// stick into the block, nudged back out of it slightly so it reads as embedded
				p.x = hx - p.vx * 0.004
				p.y = hy - p.vy * 0.004
				p.stuckAngle = atan2(p.vy, p.vx)
				p.vx = 0
				p.vy = 0
				p.stuck = 4.0
				p.gravity = 0
				spawnParticles(hx, hy, 0xA0A0A0, 2, 1.5, 0.2, 8)
				return true
			case .rock:
				rockImpact(p, hx, hy)
				return false
			case .shell:
				shellBurst(p, hx - p.vx * 0.004, hy - p.vy * 0.004)
				return false
			case .bomb:
				// bounce off the face it struck, losing energy, and come to rest on top of the ground
				// (it used to work its way into the floor and go off inside the rock)
				let tx: Double = Double(wallTile.0)
				let ty: Double = Double(wallTile.1)
				let onTop: Bool = abs(hy - ty) < 0.02 && p.vy > 0
				let onBottom: Bool = abs(hy - (ty + 1.0)) < 0.02 && p.vy < 0
				if onTop || onBottom {
					// the ground grips it: it settles close to where it came down
					p.vy = -p.vy * 0.35
					p.vx *= onTop ? 0.4 : 0.7
					p.x = hx
					p.y = onTop ? ty - 0.02 : ty + 1.02
					if onTop && abs(p.vy) < 1.5 { p.vy = 0; p.vx *= 0.6 }
				} else {
					p.vx = -p.vx * 0.45
					p.x = p.vx < 0 ? tx - 0.02 : tx + 1.02
					p.y = hy
				}
				if world.solid(Int(floor(p.x)), Int(floor(p.y))) { p.y = Double(world.groundBelow(Int(floor(p.x)), Int(floor(p.y)) - 4)) - 0.02 }
				return true
			default:
				spawnParticles(hx, hy, p.kind == .fireball ? 0xFF8030 : 0xFFE080, 5, 3.0, 0.25, 6)
				if p.kind == .fireball { igniteNear(hx, hy, p.source) }
				return false
			}
		}
		p.x = nx
		p.y = ny
		// player shots also damage pirate ships
		if p.source.kind == .player {
			for s in ships {
				let dy: Double = s.deckY(Double(WorldGen.sea))
				if abs(p.x - s.x) < 4.6 && p.y > dy - 3.0 && p.y < dy + 2.0 {
					s.hp -= p.dmg * 0.5
					s.hitT = 0.2
					spawnParticles(p.x, p.y, 0x8A5A2E, 4, 3.0, 0.3, 12)
					return false
				}
			}
		}
		if p.kind == .fireball && Double.random(in: 0...1) < 0.5 { spawnParticles(p.x, p.y, 0xFFB040, 1, 1.0, 0.25, -2) }
		if p.kind == .arrow && p.source.kind == .player && p.trail < 6 { p.trail += 1 }
		return true
	}

	struct PathHit {
		var t: Double
		var mob: Mob?
	}

	/// Nearest creature or player the segment passes through that this projectile is allowed to hurt
	func firstEntityOnPath(_ p: Projectile, _ nx: Double, _ ny: Double, maxT: Double) -> PathHit? {
		var best: PathHit? = nil
		var bt: Double = min(1.0, maxT)
		let pad: Double = max(0.08, p.w * 0.5)
		if !dead && canHarm(p.source, targetFaction: .player, targetID: 0, area: false) {
			if let t = segmentBoxT(p.x, p.y, nx, ny, pb.left - pad, pb.top - pad, pb.right + pad, pb.y + pad), t <= bt {
				bt = t
				best = PathHit(t: t, mob: nil)
			}
		}
		let x0: Double = min(p.x, nx) - 4.0
		let x1: Double = max(p.x, nx) + 4.0
		for m in mobsNear(x0, x1) {
			if m.hp <= 0 || m.id == p.lastHit || m.downed { continue }
			if !canHarm(p.source, targetFaction: faction(of: m), targetID: m.id, area: false) { continue }
			if let t = segmentBoxT(p.x, p.y, nx, ny, m.b.left - pad, m.b.top - pad, m.b.right + pad, m.b.y + pad), t <= bt {
				bt = t
				best = PathHit(t: t, mob: m)
			}
		}
		return best
	}

	/// Boss shockwaves run along the ground and hurt anything standing in them
	func stepShock(_ p: inout Projectile, _ dt: Double) -> Bool {
		p.x += p.vx * dt
		let gy: Int = world.groundBelow(Int(floor(p.x)), Int(floor(p.y)) - 3)
		p.y = Double(gy) - 0.5
		if world.solid(Int(floor(p.x)), Int(floor(p.y - 0.6))) && world.solid(Int(floor(p.x + p.vx * 0.1)), Int(floor(p.y - 0.4))) { return false }
		var info = DamageInfo(amount: p.dmg, type: .stomp, source: p.source)
		info.dirX = p.vx >= 0 ? 1 : -1
		info.knock = 7.0
		info.originX = p.x - p.vx
		info.originY = p.y
		info.key = p.uid
		info.cooldown = 2.0
		damageBox(p.x - 0.5, p.y - 0.9, p.x + 0.5, p.y + 0.5, info)
		if Double.random(in: 0...1) < 0.5 { spawnParticles(p.x, p.y + 0.3, 0xA08860, 1, 1.5, 0.3, 6) }
		return true
	}

	func rockImpact(_ p: Projectile, _ x: Double, _ y: Double) {
		spawnParticles(x, y, 0x8A8A8A, 10, 5.0, 0.5, 16)
		addShake(0.25)
		var info = DamageInfo(amount: p.dmg, type: .impact, source: p.source)
		info.knock = 5.0
		info.originX = x
		info.originY = y - 1.0
		info.key = p.uid
		info.cooldown = 1.0
		damageArea(x, y - 0.8, radius: 1.8, info, falloff: false, lineOfSight: false)
	}

	/// Fireballs set fire to whatever stands where they burst
	func igniteNear(_ x: Double, _ y: Double, _ src: DamageSource) {
		for m in mobsNear(x - 1.5, x + 1.5) where m.hp > 0 && !heatImmune(m) {
			if abs(m.b.cy - y) < m.b.h * 0.5 + 1.0 && canHarm(src, targetFaction: faction(of: m), targetID: m.id, area: true) {
				m.burn = max(m.burn, 2.0)
			}
		}
	}

	func throwBomb() {
		if useCD > 0 { return }
		if !isCreative { inv.removeAt(sel, 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		// thrown on the arc that lands it on the spot aimed at (then it may bounce a little)
		let a: Double = lobAngle(aimX - ox, aimY - oy, throwSpeed, throwGravity)
		var p = Projectile(kind: .bomb, x: ox, y: oy, vx: cos(a) * throwSpeed, vy: sin(a) * throwSpeed, dmg: 26, fromPlayer: true, gravity: throwGravity)
		p.life = 1.8
		p.w = 0.4
		p.source = DamageSource.player
		p.uid = newID()
		projectiles.append(p)
		useCD = 0.45
		swingT = 0.18
		swingDir = facing
		bumpHUD()
	}

	// MARK: drops

	func updateDrops(_ dt: Double) {
		var i: Int = 0
		while i < drops.count {
			var d: DropItem = drops[i]
			d.age += dt
			if d.pickDelay > 0 { d.pickDelay -= dt }
			if d.age > 400 {
				drops.remove(at: i)
				continue
			}
			var b = Body(x: d.x, y: d.y, w: 0.3, h: 0.3)
			b.vx = d.vx
			b.vy = d.vy
			b.ride = d.ride
			b.rlx = d.rlx
			b.rly = d.rly
			b.onGround = d.onGround
			let px: Double = pb.x
			let py: Double = pb.y - pb.h * 0.5
			let dx: Double = px - d.x
			let dy: Double = py - (d.y - 0.15)
			let dist: Double = sqrt(dx * dx + dy * dy)
			// a stack the player threw away waits until they have walked off from it
			if d.heldBack && dist > 3.6 { d.heldBack = false }
			var magnet: Bool = false
			if !dead && d.pickDelay <= 0 && !d.heldBack && dist < 3.2 && inv.canFit(d.stack.item, 1) {
				magnet = true
				let k: Double = 16.0
				b.vx = dx / max(dist, 0.1) * k * (1.0 + (3.2 - dist) * 0.3)
				b.vy = dy / max(dist, 0.1) * k * (1.0 + (3.2 - dist) * 0.3)
			} else {
				b.vy = min(b.vy + gravityG * 0.8 * dt, 18)
				b.vx *= (1.0 - min(1.0, dt * (d.onGround ? 6.0 : 0.6)))
			}
			if magnet {
				// drawn to the player through the air, whatever it was lying on
				if b.ride != 0 { b.ride = 0 }
				b.x += b.vx * dt
				b.y += b.vy * dt
			} else {
				moveThing(&b, dt, stepUp: 0, dropThrough: false, decks: decksCache, mass: 0)
				if b.inWater { b.vy = min(b.vy, 1.5); b.vx *= 0.9 }
			}
			d.x = b.x
			d.y = b.y
			d.vx = b.vx
			d.vy = b.vy
			d.onGround = b.onGround
			d.ride = b.ride
			d.rlx = b.rlx
			d.rly = b.rly
			if !dead && d.pickDelay <= 0 && !d.heldBack && dist < 0.9 {
				let left: Int = inv.add(d.stack.item, d.stack.count, extra: d.stack.extra, inf: d.stack.inf)
				if left < d.stack.count {
					if d.stack.item == .mat(.relicFragment) { journal.relics += d.stack.count - left }
					sfx(.pickup, 0.5)
					floatText("+" + String(d.stack.count - left) + " " + d.stack.item.name, px, pb.y - pb.h - 0.5, 0xFFF0A0)
					bumpHUD()
				}
				if left == 0 {
					drops.remove(at: i)
					continue
				} else {
					d.stack.count = left
				}
			}
			drops[i] = d
			i += 1
		}
	}

	// MARK: particles and floating text

	/// Leaves come loose from the canopies on screen now and then (more in a wind, and where the player
	/// pushes through them) and drift down, swaying and tumbling, until they settle and fade
	func updateLeafFall(_ dt: Double) {
		let wind: Double = settings.weatherOn ? wxHere.wind : 0
		var w: Int = 0
		for i in 0..<leafFlakes.count {
			var f: LeafFlake = leafFlakes[i]
			f.life -= dt
			if f.life <= 0 { continue }
			if !f.landed {
				f.phase += dt * (2.0 + abs(wind) * 0.15)
				f.vy += (0.9 - f.vy) * min(1.0, dt * 2.0)
				f.x += (sin(f.phase) * 0.9 + wind * 0.18) * dt
				f.y += f.vy * dt
				let tx: Int = Int(floor(f.x))
				let ty: Int = Int(floor(f.y))
				let t: Tile = world.tile(tx, ty)
				if t.liquid {
					continue
				}
				if t.solid || Tile.opaqueTable[Int(t.rawValue)] {
					// come to rest on the block below
					f.y = Double(ty) - 0.02
					f.landed = true
					f.life = min(f.life, 2.5)
				}
			}
			leafFlakes[w] = f
			w += 1
		}
		if w < leafFlakes.count { leafFlakes.removeLast(leafFlakes.count - w) }
		if leafFlakes.count >= 40 { return }
		// a few tries a second to find the underside of a canopy in a column on screen
		let tries: Double = (3.0 + min(6.0, abs(wind) * 0.4)) * dt
		if Double.random(in: 0...1) < tries {
			let x0: Int = Int(floor(camX - viewTilesW * 0.5))
			let x: Int = x0 + Int.random(in: 0...max(1, Int(viewTilesW)))
			let top: Int = Int(floor(camY - viewTilesH * 0.5))
			let bottom: Int = top + Int(viewTilesH) + 1
			var y: Int = max(1, top)
			while y < bottom {
				let t: Tile = world.tile(x, y)
				if isLeafTile(t) {
					let under: Tile = world.tile(x, y + 1)
					if !isLeafTile(under) && !under.solid {
						dropLeaf(Double(x) + Double.random(in: 0.1...0.9), Double(y) + 1.0, t)
						break
					}
				}
				y += 1
			}
		}
		// pushing through leaves shakes some loose
		if abs(pb.vx) + abs(pb.vy) > 2.0 {
			let t: Tile = world.tile(Int(floor(pb.x)), Int(floor(pb.y - 1.0)))
			if isLeafTile(t) && Double.random(in: 0...1) < dt * 3.0 { dropLeaf(pb.x, pb.y - 1.0, t) }
		}
	}

	/// One leaf off a leaf block, in that block's own colours
	func dropLeaf(_ x: Double, _ y: Double, _ t: Tile) {
		if leafFlakes.count >= 48 { return }
		let tn: [UInt32] = SectionPainter.shared.leafTones[Int(t.rawValue)] ?? [0x6A9A4A, 0x4C7A3A, 0x3A5E30, 0x284426]
		leafFlakes.append(LeafFlake(x: x, y: y, vy: 0.3, phase: Double.random(in: 0...6.28), life: 14.0, light: tn[1], dark: tn[2]))
	}

	func updateParticles(_ dt: Double) {
		// compact in place: remove(at:) in a loop was O(n^2) when bursts of particles expired together
		let n: Int = particles.count
		var w: Int = 0
		particles.withUnsafeMutableBufferPointer { bp in
			var i: Int = 0
			while i < n {
				var p: Particle = bp[i]
				p.life -= dt
				if p.life > 0 {
					p.vy += p.gravity * dt
					p.x += p.vx * dt
					p.y += p.vy * dt
					bp[w] = p
					w += 1
				}
				i += 1
			}
		}
		if w < n { particles.removeLast(n - w) }
		var j: Int = 0
		while j < floats.count {
			floats[j].life -= dt
			floats[j].y -= dt * 1.1
			if floats[j].life <= 0 { floats.remove(at: j); continue }
			j += 1
		}
	}
}

// ===== p16c_damage =====

// MARK: - Unified damage system
// Every source of harm (swings, projectiles, boss stomps, explosions, falling blocks, vehicles, lava,
// fire, spikes) builds a DamageInfo and goes through the same few functions. They decide who can be
// hurt (factions), stop one attack from hitting the same target every frame (per-attack cooldown
// keys), apply armor and resistances, push targets back, and remember who to credit for a kill.

enum DamageType: Int {
	case melee, projectile, explosion, fire, lava, impact, stomp, contact, fall, drown, starve, hazard, crush
	/// lightning from the storm rod
	case shock
	/// potions (appended): poison over time, and the searing splash's burn
	case poison, magic

	/// Armor does not help against these
	var bypassesArmor: Bool {
		switch self {
		case .fire, .lava, .fall, .drown, .starve, .poison: return true
		default: return false
		}
	}

	/// Area attacks hit everything in range (except their owner), including members of the attacker's
	/// own side. Aimed attacks never hurt the attacker's own side.
	var isArea: Bool {
		switch self {
		case .explosion, .stomp, .impact, .crush, .fire, .lava, .hazard: return true
		default: return false
		}
	}
}

enum Faction: Int {
	case player, ally, wild, hostile, pirate, umbral, boss, environment
}

enum SourceKind: Int {
	case player, mob, environment
}

struct DamageSource {
	var kind: SourceKind
	var id: Int
	var faction: Faction
	/// how hard a creature's blows land (mutation doubles it, weakness softens it): fixed when the blow starts
	var mult: Double = 1

	static let player: DamageSource = DamageSource(kind: .player, id: 0, faction: .player)
	static let environment: DamageSource = DamageSource(kind: .environment, id: -1, faction: .environment)
	static func mob(_ m: Mob, _ f: Faction) -> DamageSource { return DamageSource(kind: .mob, id: m.id, faction: f, mult: m.dmgMul) }
}

struct DamageInfo {
	var amount: Double
	var type: DamageType
	var source: DamageSource
	/// knockback direction (-1 / 1); 0 = push away from the origin
	var dirX: Double = 0
	var knock: Double = 0
	var originX: Double = 0
	var originY: Double = 0
	/// attack instance id: the same key never hits the same target twice within `cooldown` seconds
	var key: Int = 0
	var cooldown: Double = 0.5
	/// a crushing blow (war hammer): breaks a raised guard and cracks stone hides
	var heavy: Bool = false
	/// a critical blow (shown bigger and brighter)
	var crit: Bool = false

	init(amount: Double, type: DamageType, source: DamageSource) {
		self.amount = amount
		self.type = type
		self.source = source
	}
}

/// Bucketed mob positions, rebuilt once per frame, so area attacks and projectiles only look at
/// creatures near them instead of every mob in the world.
final class MobGrid {
	static let cell: Int = 8
	var buckets: [Int: [Mob]] = [:]

	func rebuild(_ mobs: [Mob]) {
		for k in buckets.keys { buckets[k]?.removeAll(keepingCapacity: true) }
		for m in mobs where m.hp > 0 && !m.removed {
			let k: Int = floorDiv(Int(floor(m.b.x)), MobGrid.cell)
			if buckets[k] == nil { buckets[k] = [] }
			buckets[k]?.append(m)
		}
		if buckets.count > 256 { buckets = buckets.filter { !$0.value.isEmpty } }
	}
}

func isHeatImmune(_ k: MobKind) -> Bool {
	switch k {
	case .imp, .emberSlime, .cinderBat, .warden: return true
	default: return false
	}
}

/// Fraction of damage a creature takes from a damage type (1 = full)
func damageResist(_ k: MobKind, _ t: DamageType) -> Double {
	switch (k, t) {
	case (.imp, .fire), (.emberSlime, .fire), (.cinderBat, .fire), (.imp, .lava), (.emberSlime, .lava), (.cinderBat, .lava): return 0
	case (.wraith, .fall), (.bat, .fall), (.cinderBat, .fall), (.crow, .fall): return 0
	case (.skeleton, .projectile): return 0.75
	case (.bearBoss, .lava), (.rex, .lava): return 0.5
	case (.bearBoss, .explosion), (.rex, .explosion): return 0.6
	case (.slime, .fall), (.emberSlime, .fall), (.cat, .fall), (.frog, .fall): return 0.2
	// the golem's stone hide shrugs off blades and arrows (a hammer's crushing blow gets through)
	case (.golem, .melee), (.golem, .contact): return 0.55
	case (.golem, .projectile): return 0.35
	case (.golem, .fire), (.golem, .fall): return 0.2
	case (.golem, .explosion): return 1.25
	case (.sentinel, .fall), (.warden, .fall), (.warden, .lava), (.mimic, .fall): return 0
	case (.sentinel, .projectile): return 0.8
	case (.warden, .explosion): return 0.7
	// lightning: stone and crystal carry it poorly
	case (.golem, .shock): return 0.6
	case (.sentinel, .shock): return 0.5
	// poison does not take hold in the dead, in stone or crystal, or in slimes
	case (.zombie, .poison), (.skeleton, .poison), (.wraith, .poison), (.golem, .poison), (.sentinel, .poison), (.warden, .poison), (.slime, .poison), (.emberSlime, .poison): return 0
	case (.warden, .shock): return 0.75
	default: return 1
	}
}

/// Segment/box intersection (slab method). Returns the entry fraction along the segment, or nil.
func segmentBoxT(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ bx0: Double, _ by0: Double, _ bx1: Double, _ by1: Double) -> Double? {
	let dx: Double = x1 - x0
	let dy: Double = y1 - y0
	var tmin: Double = 0
	var tmax: Double = 1
	if abs(dx) < 1e-9 {
		if x0 < bx0 || x0 > bx1 { return nil }
	} else {
		var ta: Double = (bx0 - x0) / dx
		var tb: Double = (bx1 - x0) / dx
		if ta > tb { let s: Double = ta; ta = tb; tb = s }
		tmin = max(tmin, ta)
		tmax = min(tmax, tb)
		if tmin > tmax { return nil }
	}
	if abs(dy) < 1e-9 {
		if y0 < by0 || y0 > by1 { return nil }
	} else {
		var ta: Double = (by0 - y0) / dy
		var tb: Double = (by1 - y0) / dy
		if ta > tb { let s: Double = ta; ta = tb; tb = s }
		tmin = max(tmin, ta)
		tmax = min(tmax, tb)
		if tmin > tmax { return nil }
	}
	return tmin
}

extension World {
	/// First solid tile along a segment: (tile x, tile y, fraction along the segment)
	func segmentSolidT(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Int, Int, Double)? {
		let dx: Double = x1 - x0
		let dy: Double = y1 - y0
		let dist: Double = sqrt(dx * dx + dy * dy)
		let n: Int = max(1, Int(ceil(dist / 0.2)))
		var i: Int = 1
		while i <= n {
			let t: Double = Double(i) / Double(n)
			let tx: Int = Int(floor(x0 + dx * t))
			let ty: Int = Int(floor(y0 + dy * t))
			if tile(tx, ty).solid {
				// refine the entry point against the tile box
				let et: Double = segmentBoxT(x0, y0, x1, y1, Double(tx), Double(ty), Double(tx + 1), Double(ty + 1)) ?? t
				return (tx, ty, et)
			}
			i += 1
		}
		return nil
	}

	/// True when nothing solid blocks the straight line between two points
	func lineClear(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		return segmentSolidT(x0, y0, x1, y1) == nil
	}
}

extension Game {
	// MARK: sides

	func faction(of m: Mob) -> Faction {
		if m.tame { return .ally }
		switch m.kind {
		case .pirate, .pirateGunner, .pirateCaptain: return .pirate
		case .imp, .emberSlime, .cinderBat: return .umbral
		case .bearBoss, .rex, .sentinel, .warden: return .boss
		case .custom: return ModRuntime.shared.mob(m.cslot)?.faction ?? .wild
		default: return m.def.hostile ? .hostile : .wild
		}
	}

	/// May `src` hurt a target of `targetFaction`?
	func canHarm(_ src: DamageSource, targetFaction tf: Faction, targetID: Int, area: Bool) -> Bool {
		// nothing hurts itself (the player's own bombs are the exception, handled in explode())
		if src.kind == .mob && src.id == targetID { return false }
		if src.kind == .player && tf == .player { return false }
		switch src.faction {
		case .environment, .boss: return true
		case .player: return tf != .ally
		case .ally: return tf != .player && tf != .ally
		default:
			if area { return true }
			return tf != src.faction
		}
	}

	// MARK: queries

	func mobsNear(_ x0: Double, _ x1: Double) -> [Mob] {
		Perf.shared.countDamage()
		let c0: Int = floorDiv(Int(floor(x0)), MobGrid.cell)
		let c1: Int = floorDiv(Int(floor(x1)), MobGrid.cell)
		if c1 - c0 > 64 { return mobs }
		var out: [Mob] = []
		var c: Int = c0
		while c <= c1 {
			if let b = mobGrid.buckets[c] { out.append(contentsOf: b) }
			c += 1
		}
		return out
	}

	// MARK: applying damage

	/// Damages a creature. Returns true if the hit landed.
	@discardableResult
	func applyMobDamage(_ m: Mob, _ info: DamageInfo) -> Bool {
		if m.hp <= 0 || m.removed { return false }
		if !canHarm(info.source, targetFaction: faction(of: m), targetID: m.id, area: info.type.isArea) { return false }
		if info.key != 0 {
			if let last = m.hitStamps[info.key], clock - last < info.cooldown { return false }
			m.hitStamps[info.key] = clock
			if m.hitStamps.count > 24 { m.hitStamps = m.hitStamps.filter { clock - $0.value < 4.0 } }
		}
		var amount: Double = info.amount * damageResist(m.kind, info.type) * (info.source.kind == .mob ? info.source.mult : 1.0)
		if m.kind == .custom, let r = ModRuntime.shared.mob(m.cslot) {
			amount *= r.resist(info.type) * (1.0 - m.phaseDef)
			// changing phase: blows glance off
			if m.phaseShield > 0 {
				if info.source.kind == .player { spawnParticles(m.b.x, m.b.cy, 0xE0E8FF, 3, 2.5, 0.25, 6) }
				return false
			}
		}
		if info.heavy && m.kind == .golem { amount *= 1.9 }
		if info.source.kind == .player {
			amount *= dmgOutMult * (1.0 + effects.value(.strength) / 100.0)
			if wearing(.wardenSigil) { amount *= 1.2 }
			if isUndead(m.kind) && wearing(.silverCharm) { amount *= 1.25 }
		}
		if amount <= 0 { return false }
		let byPlayer: Bool = info.source.kind == .player
		if byPlayer { m.lastHitByPlayer = clock }
		m.lastAttacker = info.source.id
		var dir: Double = info.dirX
		if dir == 0 && info.knock > 0 { dir = m.b.x >= info.originX ? 1.0 : -1.0 }
		hurtMob(m, amount, dir, info.knock, byPlayer, heavy: info.heavy, crit: info.crit)
		return true
	}

	/// Damages the player. Returns true if the hit landed.
	@discardableResult
	func hurtPlayer(_ info: DamageInfo) -> Bool {
		if dead { return false }
		if !canHarm(info.source, targetFaction: .player, targetID: 0, area: info.type.isArea) && info.source.kind != .player { return false }
		if info.key != 0 {
			if let last = playerHitStamps[info.key], clock - last < info.cooldown { return false }
			playerHitStamps[info.key] = clock
			if playerHitStamps.count > 24 { playerHitStamps = playerHitStamps.filter { clock - $0.value < 4.0 } }
		}
		if effects.value(.fireproof) > 0 && (info.type == .fire || info.type == .lava) { return false }
		let before: Double = hp
		var ward: Double = wearing(.wardenSigil) ? 0.85 : 1.0
		ward *= 1.0 - clampD(effects.value(.resistance), 0, 90) / 100.0
		if info.source.kind == .mob && wearing(.silverCharm), let src = mobs.first(where: { $0.id == info.source.id }), isUndead(src.kind) { ward *= 0.75 }
		// armour infusions and the suit take their share first
		let amount: Double = guardedAmount(info)
		if amount <= 0.001 { return false }
		damagePlayer(amount * dmgInMult * ward, from: info.originX, knock: info.knock * knockTaken, ignoreArmor: info.type.bypassesArmor)
		if hp < before { thornsBack(info, amount) }
		if hp < before { customHurtTriggers() }
		if hp < before && !logicRT.isEmpty { fireLogic(.playerHurt) }
		return hp < before
	}

	/// Hits everything (player and creatures) inside a box
	func damageBox(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ info: DamageInfo) {
		if !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.top < y1 { _ = hurtPlayer(info) }
		for m in mobsNear(x0 - 4, x1 + 4) {
			if m.hp <= 0 { continue }
			if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.top < y1 { applyMobDamage(m, info) }
		}
	}

	/// Hits everything within `radius` of a point. With falloff, damage drops to 35% at the edge;
	/// with lineOfSight, targets behind solid blocks are spared.
	func damageArea(_ cx: Double, _ cy: Double, radius: Double, _ info: DamageInfo, falloff: Bool, lineOfSight: Bool) {
		func scaled(_ d: Double) -> DamageInfo {
			var i: DamageInfo = info
			if falloff { i.amount = info.amount * (1.0 - 0.65 * clampD(d / radius, 0, 1)) }
			i.knock = info.knock * (falloff ? (1.0 - 0.5 * clampD(d / radius, 0, 1)) : 1.0)
			i.originX = cx
			i.originY = cy
			return i
		}
		if !dead {
			let d: Double = boxDistance(cx, cy, pb.left, pb.top, pb.right, pb.y)
			if d <= radius && (!lineOfSight || world.lineClear(cx, cy, pb.x, pb.cy)) { _ = hurtPlayer(scaled(d)) }
		}
		for m in mobsNear(cx - radius - 4, cx + radius + 4) {
			if m.hp <= 0 { continue }
			let d: Double = boxDistance(cx, cy, m.b.left, m.b.top, m.b.right, m.b.y)
			if d > radius { continue }
			if lineOfSight && !world.lineClear(cx, cy, m.b.x, m.b.cy) { continue }
			applyMobDamage(m, scaled(d))
		}
	}

	func boxDistance(_ px: Double, _ py: Double, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Double {
		let dx: Double = max(0, max(x0 - px, px - x1))
		let dy: Double = max(0, max(y0 - py, py - y1))
		return sqrt(dx * dx + dy * dy)
	}

	// MARK: explosions

	func explode(_ x: Double, _ y: Double, radius: Double, power: Double, source: DamageSource, breakBlocks: Bool) {
		sfx(.explosion, at: x, 1.0)
		var info = DamageInfo(amount: power, type: .explosion, source: source)
		info.knock = 11.0
		info.key = newID()
		info.cooldown = 1.0
		damageArea(x, y, radius: radius, info, falloff: true, lineOfSight: true)
		// the thrower is not immune to their own bomb, but takes less
		if source.kind == .player && !dead {
			let d: Double = boxDistance(x, y, pb.left, pb.top, pb.right, pb.y)
			if d <= radius && world.lineClear(x, y, pb.x, pb.cy) {
				damagePlayer(power * 0.45 * (1.0 - 0.65 * clampD(d / radius, 0, 1)), from: x, knock: 9.0)
			}
		}
		if breakBlocks { blastBlocks(x, y, radius: radius, power: power) }
		if !vehicles.isEmpty { blastVehicles(x, y, radius: radius, power: power) }
		for s in ships where abs(s.x - x) < radius + 4.5 && abs(s.deckY(Double(WorldGen.sea)) - y) < radius + 2 {
			s.hp -= power
			s.hitT = 0.3
		}
		spawnParticles(x, y, 0xFFC050, 18, 8.0, 0.5, 2)
		spawnParticles(x, y, 0x606060, 12, 4.0, 1.0, -3)
		addShake(0.6)
		// the blast lights up its surroundings for a moment (the light map floods it through open space,
		// so walls still cast shadows), fading out over the same time as the fire particles
		addLightFlash(x, y, peak: 15, dur: 0.75, radius: radius + 2.5)
	}

	// MARK: hazards for creatures

	/// Lava, fire, spikes, cactus and fall damage for every creature, through the same damage path
	/// as everything else. Hazards are timed (not per frame) and resistances apply.
	func mobHazards(_ m: Mob, _ dt: Double) {
		if m.removed || m.downed { return }
		if m.hasStatus { mobStatus(m, dt) }
		if m.hazardT > 0 { m.hazardT -= dt }
		let b: Body = m.b
		let def: MobDef = m.def
		let hw: Double = b.w * 0.5
		let x0: Double = b.x - hw
		let x1: Double = b.x + hw
		let immune: Bool = heatImmune(m)
		let fx: Int = Int(floor(b.x))
		// lava: physics already worked out whether the body is in lava; also catch feet just touching it
		let inLava: Bool = b.inLava || world.tile(fx, Int(floor(b.y - 0.1))) == .lava
		if inLava && !immune {
			m.burn = max(m.burn, 3.0)
			if m.hazardT <= 0 {
				m.hazardT = 0.35
				var info = DamageInfo(amount: m.isBoss ? 14 : 6, type: .lava, source: .environment)
				info.originX = m.b.x
				applyMobDamage(m, info)
				if m.hp > 0 && !m.def.flying { m.b.vy = min(m.b.vy, -7.0) }
			}
		}
		// burning
		if m.burn > 0 {
			if immune || m.b.inWater {
				m.burn = 0
			} else {
				m.burn -= dt
				m.burnTick += dt
				if m.burnTick >= 0.5 {
					m.burnTick = 0
					var info = DamageInfo(amount: m.isBoss ? 3 : 2, type: .fire, source: .environment)
					info.originX = m.b.x
					applyMobDamage(m, info)
					spawnParticles(m.b.x, m.b.y - m.b.h * 0.7, 0xFF8030, 2, 1.5, 0.4, -4)
				}
			}
		}
		// spikes, cactus, campfires (checked every 4th frame per creature, staggered; these only
		// apply damage on a 0.6 s timer anyway)
		if !def.flying && m.hazardT <= 0 && (frameNo &+ m.id) & 3 == 0 {
			if let t = world.boxHurts(x0 + 0.05, m.b.y - 0.6, x1 - 0.05, m.b.y + 0.05) ?? world.boxHurts(x0 - 0.02, m.b.top + 0.1, x1 + 0.02, m.b.y - 0.1) {
				if t == .spikes || t == .cactus || t.isMod {
					m.hazardT = 0.6
					let dmg: Double = t.isMod ? (ModRuntime.shared.blockDef(t)?.power ?? 4) : (t == .spikes ? 5 : 2)
					var info = DamageInfo(amount: dmg, type: .hazard, source: .environment)
					info.originX = m.b.x - Double(m.dir)
					info.knock = 3.0
					applyMobDamage(m, info)
				}
			}
			let fy: Int = Int(floor(b.y - 0.5))
			if world.tile(fx, fy) == .campfire && !immune { m.burn = max(m.burn, 2.0) }
		}
		// falling (knockback off a ledge counts too)
		if !def.flying && m.kind != .fish {
			if !m.b.onGround && m.b.vy > 0 && !m.b.inWater { m.fallPeak = max(m.fallPeak, m.b.vy) }
			if m.b.onGround || m.b.inWater {
				if m.fallPeak > 23.0 && !m.b.inWater && !m.isBoss {
					var info = DamageInfo(amount: (m.fallPeak - 21.0) * 1.5, type: .fall, source: .environment)
					info.originX = m.b.x
					applyMobDamage(m, info)
				}
				m.fallPeak = 0
			}
		}
	}

	/// Dead creatures topple, fall and fade out for a moment before they are removed
	func updateDying(_ dt: Double) {
		for m in mobs where m.hp <= 0 && !m.removed {
			if m.deathT < 0 { m.deathT = 0 }
			m.deathT += dt
			if !m.def.flying || m.deathT > 0.1 {
				m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
				m.b.vx *= (1.0 - min(1.0, dt * 4.0))
				if m.deathT < 0.8 { world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: []) }
			}
			if m.deathT > 0.7 { m.removed = true }
		}
	}

	// MARK: player fire

	func updatePlayerBurn(_ dt: Double) {
		if playerBurn <= 0 { return }
		if pb.inWater || mode == .creative { playerBurn = 0; return }
		// the ember charm makes flames die out twice as fast
		playerBurn -= dt * (wearing(.emberCharm) ? 2.0 : 1.0)
		playerBurnTick += dt
		if playerBurnTick >= 0.6 {
			playerBurnTick = 0
			var info = DamageInfo(amount: 1, type: .fire, source: .environment)
			info.originX = pb.x
			_ = hurtPlayer(info)
			spawnParticles(pb.x, pb.y - 1.2, 0xFF8030, 2, 1.5, 0.4, -4)
		}
	}

	// MARK: falling blocks

	// MARK: light flashes

	func addLightFlash(_ x: Double, _ y: Double, peak: Int, dur: Double, radius: Double, color: UInt32 = 0xFF8A30) {
		// a cap keeps a chain of explosions from piling up work; the oldest gives way
		if flashes.count >= 12 { flashes.removeFirst() }
		flashes.append(LightFlash(x: x, y: y, peak: clampI(peak, 0, 15), dur: dur, radius: radius, color: color))
	}

	func updateFlashes(_ dt: Double) {
		if flashes.isEmpty { return }
		var keep: [LightFlash] = []
		for f0 in flashes {
			var f: LightFlash = f0
			f.age += dt
			if f.age < f.dur { keep.append(f) }
		}
		flashes = keep
	}

	/// Sand (and a mod's blocks that fall) with nothing under it falls; it hurts whatever it lands on
	func checkFalling(_ x: Int, _ y: Int) {
		var yy: Int = y
		var n: Int = 0
		while n < 16 && fallsLikeSand(world.tile(x, yy)) {
			let below: Tile = world.tile(x, yy + 1)
			if below.supportsThings || below.isPlatform { break }
			let t: Tile = world.tile(x, yy)
			world.set(x, yy, .air)
			fallingBlocks.append(FallingBlock(x: Double(x) + 0.5, y: Double(yy) + 1.0, vy: 0, tile: t, uid: newID()))
			yy -= 1
			n += 1
		}
	}

	/// Moves the blocks on the move. Sand drops straight down; a thrown block also flies sideways,
	/// turns, is carried by a storm's wind (less the heavier it is), bounces off walls and slides along
	/// the ground until it is slow, then settles back into a block (settleBlock). Anything still in the
	/// air after 14 s settles where it is. A heavy, fast block hurts what it hits.
	func updateFallingBlocks(_ dt: Double) {
		if fallingBlocks.isEmpty { return }
		var keep: [FallingBlock] = []
		for fb0 in fallingBlocks {
			var fb: FallingBlock = fb0
			fb.age += dt
			fb.vy = min(fb.vy + gravityG * dt, terminalV)
			if fb.flung {
				windOnBlock(&fb, dt)
				fb.vx *= exp(-dt * 0.35)
				fb.ang += fb.spin * dt
				let nx: Double = fb.x + fb.vx * dt
				let side: Double = nx + (fb.vx >= 0 ? 0.45 : -0.45)
				if world.solid(Int(floor(side)), Int(floor(fb.y - 0.5))) {
					fb.vx = -fb.vx * 0.3
					fb.spin *= -0.5
				} else {
					fb.x = nx
				}
			}
			let ny: Double = fb.y + fb.vy * dt
			// crush whatever is in the way while moving fast enough (heavier blocks hit harder)
			let speed: Double = max(fb.vy, abs(fb.vx))
			if speed > 4.0 {
				var info = DamageInfo(amount: (2.0 + speed * 0.4) * clampD(0.5 + fb.mass * 0.3, 0.5, 2.5), type: .crush, source: .environment)
				info.originX = fb.x
				info.originY = fb.y - 1.0
				info.key = fb.uid
				info.cooldown = 5.0
				damageBox(fb.x - 0.45, fb.y - 1.0, fb.x + 0.45, max(ny, fb.y), info)
			}
			let tx: Int = Int(floor(fb.x))
			if fb.vy < 0 {
				// rising: a ceiling stops it
				if world.solid(tx, Int(floor(ny - 1.0))) { fb.vy = 0 } else { fb.y = ny }
				keep.append(fb)
				continue
			}
			let landRow: Int = Int(floor(ny))
			if world.tile(tx, landRow).supportsThings || world.tile(tx, landRow).isPlatform || landRow >= world.H - 2 {
				if fb.flung && abs(fb.vx) > 2.5 && fb.age < 10 {
					// still going: a little bounce, and it slides on
					fb.y = Double(landRow)
					fb.vy = -min(4.0, fb.vy * 0.25)
					fb.vx *= 0.55
					fb.spin *= 0.6
					keep.append(fb)
					continue
				}
				settleBlock(fb, landRow - 1)
				spawnParticles(fb.x, Double(landRow), fb.tile.def.colors.first ?? 0xE0D08A, 4, 2.0, 0.3, 10)
				continue
			}
			fb.y = ny
			if fb.age > 14.0 || fb.y > Double(world.H - 2) {
				settleBlock(fb, Int(floor(fb.y - 0.5)))
				continue
			}
			keep.append(fb)
		}
		fallingBlocks = keep
	}
}

/// A burst of light at a fixed spot in the world that fades out (explosions)
struct LightFlash {
	var x: Double
	var y: Double
	/// light level at the moment it starts (0...15)
	var peak: Int
	var age: Double = 0
	var dur: Double
	/// glow radius in blocks for the drawn flash
	var radius: Double
	/// tint of the drawn glow (explosions are amber, lightning pale blue)
	var color: UInt32 = 0xFF8A30

	/// 1 at the start, easing smoothly to 0 at the end
	var strength: Double {
		let t: Double = clampD(age / max(0.01, dur), 0, 1)
		let u: Double = 1.0 - t
		return u * u * (3.0 - 2.0 * u)
	}
	/// current light level for the light map
	var level: Int { return Int((Double(peak) * strength).rounded()) }
}

/// A block on the move: sand with nothing under it, or a block knocked loose by a blast, a storm or
/// a structure giving way. x is its centre, y its bottom edge.
struct FallingBlock {
	var x: Double
	var y: Double
	var vy: Double
	var tile: Tile
	var uid: Int
	var vx: Double = 0
	/// how it is turned (drawn), and how fast it turns
	var ang: Double = 0
	var spin: Double = 0
	var mass: Double = 1.6
	var age: Double = 0
	/// thrown (it slides and bounces before it settles, and the wind carries it)
	var flung: Bool = false
	/// it was part of something built (it counts as built again once it settles)
	var built: Bool = false
}

// ===== p16b_bosses =====

// MARK: - Bosses (giant bear, T-rex), rex companion

enum BossAtk: Int {
	case melee, sweep, charge, slam, roar
}

extension Game {
	func lairKey(_ L: LairInfo) -> Int {
		return L.kind.rawValue * 1_000_000 + (L.k + 500_000)
	}

	func updateBosses(_ dt: Double) {
		guardianT -= dt
		let checkGuardians: Bool = guardianT <= 0
		if checkGuardians { guardianT = 0.25 }
		if world.dim == .umbral {
			if checkGuardians { updateWardenSpawn() }
			refreshBossBar()
			return
		}
		if world.dim.isCustom {
			refreshBossBar()
			return
		}
		if world.dim != .overworld {
			activeBoss = nil
			return
		}
		if checkGuardians { updateGuardians() }
		// the lairs are checked four times a second too (a boss wakes as you approach, not to the frame)
		if !checkGuardians {
			refreshBossBar()
			return
		}
		let px: Int = Int(floor(pb.x))
		for L in gen.lairCenters(near: px) {
			let key: Int = lairKey(L)
			if defeated.contains(key) { continue }
			let dist: Double = abs(Double(L.cx) - pb.x)
			if suppressedLairs.contains(key) {
				if dist > 180 { suppressedLairs.remove(key) }
				continue
			}
			var existing: Mob? = nil
			for m in mobs where m.isBoss && m.lair == key { existing = m }
			if dist < 90 && existing == nil && world.isLoaded(L.cx) && !dead {
				spawnBoss(L, key)
			} else if dist > 180, let e = existing {
				e.hp = 0
				mobs.removeAll { $0 === e }
			}
		}
		refreshBossBar()
	}

	func refreshBossBar() {
		var best: Mob? = nil
		var bd: Double = 70
		for m in mobs where m.isBoss && m.hp > 0 {
			let d: Double = abs(m.b.x - pb.x)
			if d < bd { bd = d; best = m }
		}
		activeBoss = best
		if let b = best {
			bossBarName = bossTitle(b)
			bossBarFrac = clampD(b.hp / b.maxHP, 0, 1)
		}
		// companion housekeeping
		if let r = rex, r.hp <= 0 && !r.downed { rex = nil }
	}

	func spawnBoss(_ L: LairInfo, _ key: Int) {
		let kind: MobKind = L.kind == .bear ? .bearBoss : .rex
		let floorY: Double = Double(lairFloorRow(gen))
		let m: Mob = addMob(kind, Double(L.cx) + 0.5, floorY)
		m.lair = key
		m.homeX = Double(L.cx)
		m.homeY = floorY
		m.st = 3
		m.t2 = 1.5
		m.t1 = 2.0
		m.phase = 1
		m.persistent = true
		m.dir = pb.x >= m.b.x ? 1 : -1
		say(m.def.name + " awakens!", 3.5)
		sfx(.roar, at: m.b.x, 1.0)
	}

	func updateBossMob(_ m: Mob, _ dt: Double) {
		if m.kind == .rex && m.tame {
			updateRexCompanion(m, dt)
			return
		}
		bossBrain(m, dt)
	}

	// MARK: boss attack machine

	func bossBrain(_ m: Mob, _ dt: Double) {
		let isBear: Bool = m.kind == .bearBoss
		let hpf: Double = m.hp / m.maxHP
		let newPhase: Int = hpf < 0.5 ? 2 : 1
		if newPhase != m.phase {
			m.phase = newPhase
			if newPhase == 2 {
				m.st = 1
				m.atk = BossAtk.roar.rawValue
				m.t2 = 1.3
				say(m.def.name + " flies into a rage!", 3.0)
			}
		}
		let enrage: Bool = hpf < 0.25
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		let dirP: Int = toP >= 0 ? 1 : -1
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		let sp: Double = m.def.speed * (m.phase == 2 ? 1.25 : 1.0) * (enrage ? 1.15 : 1.0)
		if dead {
			accelX(m, 0, 20, dt)
			m.st = 0
			stepMob(m, dt, stepUp: 2.0)
			return
		}
		switch m.st {
		case 0:
			m.dir = dirP
			if dist > (isBear ? 2.6 : 3.8) {
				accelX(m, Double(dirP) * sp, 16, dt)
			} else {
				accelX(m, 0, 30, dt)
			}
			if abs(m.b.x - m.homeX) > 33 && (m.b.x - m.homeX) * Double(dirP) > 0 { accelX(m, 0, 40, dt) }
			if m.b.hitWall && m.b.onGround { m.b.vy = -12 }
			m.t1 -= dt
			if dist < (isBear ? 3.4 : 4.6) && abs(dyP) < 2.8 { contactHurt(m, m.def.dmg * 0.45) }
			if m.t1 <= 0 { chooseAttack(m, dist) }
		case 1:
			accelX(m, 0, 40, dt)
			if m.t2 > 0.25 { m.dir = dirP }
			m.tele = m.t2
			m.t2 -= dt
			if m.atk == BossAtk.charge.rawValue && Double.random(in: 0...1) < 0.5 {
				spawnParticles(m.b.x + Double(m.dir) * 1.5, m.b.y, 0xA08860, 1, 3.0, 0.4, 6)
			}
			if m.atk == BossAtk.roar.rawValue { addShake(0.1) }
			if m.t2 <= 0 { beginAttack(m) }
		case 2:
			runAttack(m, dt)
		case 3:
			accelX(m, 0, 30, dt)
			m.tele = 0
			m.t2 -= dt
			if m.t2 <= 0 {
				m.st = 0
				m.t1 = m.phase == 2 ? Double.random(in: 0.8...1.6) : Double.random(in: 1.4...2.6)
			}
		case 4:
			accelX(m, 0, 30, dt)
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0; m.t1 = 0.9 }
		default:
			m.st = 0
		}
		stepMob(m, dt, stepUp: 2.0)
	}

	func chooseAttack(_ m: Mob, _ dist: Double) {
		let isBear: Bool = m.kind == .bearBoss
		var opts: [(BossAtk, Double)] = []
		if dist < (isBear ? 6.5 : 8.5) {
			opts.append((.melee, 5))
			if !isBear { opts.append((.sweep, 3)) }
			opts.append((.slam, 2.5))
			opts.append((.charge, 1.5))
		} else {
			opts.append((.charge, 5))
			opts.append((.slam, 3))
			opts.append((.melee, 1))
			if m.phase == 2 { opts.append((.roar, 2)) }
		}
		var total: Double = 0
		for o in opts { total += o.1 }
		var r: Double = Double.random(in: 0..<total)
		var pick: BossAtk = .melee
		for o in opts {
			r -= o.1
			if r <= 0 { pick = o.0; break }
		}
		m.atk = pick.rawValue
		m.st = 1
		var tt: Double = 0.9
		switch pick {
		case .melee: tt = isBear ? 0.95 : 0.8
		case .sweep: tt = 0.75
		case .charge: tt = 1.05
		case .slam: tt = 0.95
		case .roar: tt = 1.3
		}
		if m.phase == 2 { tt *= 0.8 }
		m.t2 = tt
		m.dir = pb.x >= m.b.x ? 1 : -1
	}

	func beginAttack(_ m: Mob) {
		m.st = 2
		m.t3 = 0
		m.tele = 0
		m.knock = 0
		let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
		switch a {
		case .melee: m.t2 = 0.4
		case .sweep: m.t2 = 0.35
		case .charge: m.t2 = 1.6
		case .slam:
			m.t2 = 2.4
			m.b.vy = -17.0
			m.tx = pb.x
			m.t3 = 0
		case .roar:
			m.t2 = 3.2
			m.ty = 0
			addShake(0.35)
		}
	}

	func runAttack(_ m: Mob, _ dt: Double) {
		let isBear: Bool = m.kind == .bearBoss
		let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
		m.t2 -= dt
		switch a {
		case .melee:
			accelX(m, Double(m.dir) * (isBear ? 0.0 : 6.0), 30, dt)
			if m.t3 == 0 {
				let reach: Double = isBear ? 5.6 : 7.6
				let fx0: Double = m.dir > 0 ? m.b.x - 0.5 : m.b.x - reach
				let fx1: Double = m.dir > 0 ? m.b.x + reach : m.b.x + 0.5
				var info = DamageInfo(amount: m.def.dmg, type: .melee, source: .mob(m, .boss))
				info.dirX = Double(m.dir)
				info.knock = 10.0
				info.originX = m.b.x
				info.key = newID()
				damageBox(fx0, m.b.top - 0.5, fx1, m.b.y + 0.2, info)
				addShake(0.3)
				m.t3 = 1
				spawnParticles(m.b.x + Double(m.dir) * (reach * 0.6), m.b.y - 1.6, 0xE8E0D0, 6, 5.0, 0.3, 4)
			}
			if m.t2 <= 0 { m.st = 3; m.t2 = 0.8 }
		case .sweep:
			accelX(m, 0, 30, dt)
			if m.t3 == 0 {
				var info = DamageInfo(amount: m.def.dmg * 0.75, type: .stomp, source: .mob(m, .boss))
				info.knock = 11.0
				info.originX = m.b.x
				info.key = newID()
				damageBox(m.b.x - 7.0, m.b.y - 2.0, m.b.x + 7.0, m.b.y + 0.3, info)
				m.t3 = 1
				addShake(0.25)
				spawnParticles(m.b.x - Double(m.dir) * 4.5, m.b.y - 0.4, 0xA08860, 8, 5.0, 0.4, 6)
			}
			if m.t2 <= 0 { m.st = 3; m.t2 = 0.8 }
		case .charge:
			let spd: Double = (isBear ? 13.0 : 11.5) * (m.phase == 2 ? 1.15 : 1.0)
			m.b.vx = Double(m.dir) * spd
			if Double.random(in: 0...1) < 0.7 { spawnParticles(m.b.x - Double(m.dir) * 2.0, m.b.y, 0xA08860, 1, 3.0, 0.4, 6) }
			// the charge tramples everything in its path, one hit per target
			var info = DamageInfo(amount: m.def.dmg * 1.3, type: .impact, source: .mob(m, .boss))
			info.dirX = Double(m.dir)
			info.knock = 13.0
			info.originX = m.b.x
			info.key = m.id &* 1000 &+ Int(m.t2 > 0 ? 1 : 0) &+ m.atk
			info.cooldown = 1.2
			damageBox(m.b.left - 0.1, m.b.top, m.b.right + 0.1, m.b.y + 0.1, info)
			if m.b.hitWall {
				m.st = 4
				m.t2 = 1.8
				m.b.vx = 0
				addShake(0.6)
				spawnParticles(m.b.x + Double(m.dir) * 2.5, m.b.y - 2.0, 0x9A9A9A, 20, 6.0, 0.7, 18)
				rainRocks(m, 3)
			} else if m.t2 <= 0 {
				m.st = 3
				m.t2 = 0.9
			}
		case .slam:
			if !m.b.onGround { m.t3 = 1 }
			let flight: Double = 0.95
			if m.t3 == 0 || !m.b.onGround {
				let target: Double = clampD(m.tx, m.homeX - 33, m.homeX + 33)
				m.b.vx = clampD((target - m.b.x) / flight, -11, 11)
			}
			if m.b.onGround && m.t3 == 1 {
				addShake(0.7)
				spawnParticles(m.b.x, m.b.y, 0xA08860, 24, 7.0, 0.6, 10)
				let sp: Double = isBear ? 9.0 : 8.0
				for sgn in [-1.0, 1.0] {
					var p = Projectile(kind: .shock, x: m.b.x + sgn * (m.b.w * 0.5), y: m.b.y - 0.5, vx: sgn * sp, vy: 0, dmg: m.def.dmg * 0.8, fromPlayer: false, gravity: 0)
					p.life = 3.0
					p.w = 0.6
					p.source = .mob(m, .boss)
					p.uid = newID()
					projectiles.append(p)
				}
				// the landing itself: everything under and right beside the body
				var info = DamageInfo(amount: m.def.dmg, type: .stomp, source: .mob(m, .boss))
				info.knock = 9.0
				info.originX = m.b.x
				info.key = newID()
				damageArea(m.b.x, m.b.y - 0.5, radius: m.b.w * 0.5 + 1.2, info, falloff: true, lineOfSight: false)
				m.st = 3
				m.t2 = 1.0
				m.b.vx = 0
			} else if m.t2 <= 0 {
				m.st = 3
				m.t2 = 0.8
			}
		case .roar:
			accelX(m, 0, 30, dt)
			addShake(0.15)
			m.ty -= dt
			if m.ty <= 0 {
				m.ty = 0.42
				rainRocks(m, 1)
			}
			if m.t2 <= 0 { m.st = 3; m.t2 = 1.0 }
		}
	}

	func rainRocks(_ m: Mob, _ n: Int) {
		for _ in 0..<n {
			let rx: Double = clampD(pb.x + Double.random(in: -9...9), m.homeX - 36, m.homeX + 36)
			var p = Projectile(kind: .rock, x: rx, y: m.b.y - 17.0, vx: 0, vy: 0, dmg: 16, fromPlayer: false, gravity: 26)
			p.life = 5.0
			p.w = 0.9
			// falling rocks hurt anyone underneath, the boss's own minions included
			p.source = .mob(m, .boss)
			p.uid = newID()
			projectiles.append(p)
			spawnParticles(rx, m.b.y - 0.3, 0x8A8A8A, 2, 1.0, 0.8, 0)
		}
	}

	// MARK: rewards

	func onBearDefeated(_ m: Mob) {
		defeated.insert(m.lair)
		addShake(0.8)
		spawnDrop(Stack(item: .gadget(.portalKey), count: 1), m.b.x, m.b.y - 2.0, 0, -6.0)
		spawnDrop(Stack(item: .gadget(.treasureMap), count: 1), m.b.x + 0.8, m.b.y - 2.0, 1.0, -6.0)
		gotMap = true
		say(m.def.name + " has fallen! It dropped a Portal Key and a Treasure Map.", 6.0)
		spawnParticles(m.b.x, m.b.cy, 0xFFE070, 40, 9.0, 1.2, 8)
	}

	func onRexDefeated(_ m: Mob) {
		defeated.insert(m.lair)
		addShake(0.8)
		spawnParticles(m.b.x, m.b.cy, 0xFFE070, 40, 9.0, 1.2, 8)
		if rex == nil {
			m.tame = true
			m.persistent = true
			m.maxHP = 700
			m.hp = 420
			m.downed = false
			m.st = 0
			m.phase = 1
			m.lair = 0
			rex = m
			say(m.def.name + " bows its head. It will follow you now. Tap it to ride!", 6.0)
		} else {
			say(m.def.name + " has fallen!", 4.0)
		}
	}

	// MARK: companion

	func downRex(_ m: Mob) {
		m.downed = true
		m.hp = 1
		m.t1 = 40
		m.mounted = false
		if mounted === m {
			dismount()
		}
		floatText("Tyrannax is down!", m.b.x, m.b.top - 0.5, 0xFF6060)
		say("Tyrannax collapsed. It will recover in a moment.", 3.0)
	}

	func nearestGround(_ x: Double, _ y: Double) -> Double {
		let ix: Int = Int(floor(x))
		var yy: Int = Int(floor(y)) - 8
		var n: Int = 0
		while n < 40 {
			if world.solid(ix, yy) { return Double(yy) }
			yy += 1
			n += 1
		}
		return y
	}

	func teleportRexNearPlayer(_ m: Mob) {
		let side: Double = Double(-facing)
		var x: Double = pb.x + side * 6.0
		if !world.isLoaded(Int(floor(x))) { x = pb.x }
		// find a free spot big enough
		var y: Double = pb.y
		var tries: Int = 0
		while tries < 4 && world.boxSolid(x - m.b.w * 0.5, y - m.b.h, x + m.b.w * 0.5, y - 0.05) {
			x = pb.x + side * (6.0 + Double(tries) * 3.0)
			y = nearestGround(x, pb.y - 6.0)
			tries += 1
		}
		if world.boxSolid(x - m.b.w * 0.5, y - m.b.h, x + m.b.w * 0.5, y - 0.05) {
			// carve space if the area is blocked
			let x0: Int = Int(floor(x - m.b.w * 0.5))
			let x1: Int = Int(ceil(x + m.b.w * 0.5))
			let y0: Int = Int(floor(y - m.b.h))
			let y1: Int = Int(ceil(y)) - 1
			for tx in x0...x1 { for ty in y0...y1 { if world.tile(tx, ty).solid && world.tile(tx, ty).def.hard < 9000 { world.set(tx, ty, .air) } } }
		}
		m.b.x = x
		m.b.y = y
		m.b.vx = 0
		m.b.vy = 0
		m.stuckT = 0
		m.lastX = x
	}

	func updateRexCompanion(_ m: Mob, _ dt: Double) {
		if m.downed {
			m.t1 -= dt
			m.b.vx = 0
			m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
			world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
			if m.t1 <= 0 {
				m.downed = false
				m.hp = m.maxHP * 0.5
				floatText("Tyrannax rises!", m.b.x, m.b.top - 0.5, 0x80FF80)
			}
			return
		}
		if mounted === m { return }
		m.hp = min(m.maxHP, m.hp + dt * 1.2)
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		if dist > 70 || abs(pb.y - m.b.y) > 40 || m.stuckT > 4.0 {
			if dist > 12 || abs(pb.y - m.b.y) > 6 { teleportRexNearPlayer(m) }
			m.stuckT = 0
		}
		var target: Mob? = nil
		if !dead { target = nearestHostileTo(m.b.x, m.b.cy, 13.0) }
		if let t = target, t.hp > 0, !t.isBoss {
			let dx: Double = t.b.x - m.b.x
			m.dir = dx >= 0 ? 1 : -1
			if abs(dx) > 4.2 { accelX(m, Double(m.dir) * 5.5, 22, dt) } else { accelX(m, 0, 30, dt) }
			if m.cd <= 0 && abs(dx) < 5.6 && abs(t.b.cy - m.b.cy) < 3.5 {
				m.st = 2
				m.t2 = 0.3
				m.cd = 1.1
				hurtMob(t, 28, Double(m.dir), 9.0, true)
			}
		} else if dist > 7.5 {
			m.dir = toP >= 0 ? 1 : -1
			let sp: Double = dist > 25 ? 11.0 : 6.0
			accelX(m, Double(m.dir) * sp, 24, dt)
		} else {
			accelX(m, 0, 24, dt)
			if dist > 1 { m.dir = toP >= 0 ? 1 : -1 }
		}
		if m.st == 2 {
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0 }
		}
		if m.b.hitWall && m.b.onGround { m.b.vy = -16.0 }
		// stuck detection
		m.t3 += dt
		if m.t3 >= 0.5 {
			m.t3 = 0
			let moved: Double = abs(m.b.x - m.lastX)
			m.lastX = m.b.x
			if moved < 0.15 && abs(m.b.vx) > 0.5 && dist > 8 { m.stuckT += 0.5 } else if moved >= 0.15 { m.stuckT = 0 }
		}
		stepMob(m, dt, stepUp: 2.0)
	}

	func mountRex(_ m: Mob) {
		if m.downed { say("Tyrannax is recovering.", 2.0); return }
		if inVehicle != nil { return }
		if abs(m.b.x - pb.x) > 9 || abs(m.b.y - pb.y) > 8 { say("Get closer to ride.", 2.0); return }
		mounted = m
		m.mounted = true
		pb.vx = 0
		pb.vy = 0
		say("Riding Tyrannax. Bite attacks are automatic!", 2.5)
		bumpHUD()
	}

	func rideRex(_ r: Mob, _ ix: Double, _ jumpPressed: Bool, _ dt: Double) {
		if r.downed || r.hp <= 0 {
			dismount()
			return
		}
		if ix != 0 { r.dir = ix > 0 ? 1 : -1 }
		let target: Double = ix * 10.0
		accelX(r, target, 40, dt)
		if jumpPressed && r.b.onGround { r.b.vy = -19.0 }
		if r.cd > 0 { r.cd -= dt }
		if r.st == 2 {
			r.t2 -= dt
			if r.t2 <= 0 { r.st = 0 }
		}
		// auto bite
		if r.cd <= 0 {
			var bestM: Mob? = nil
			var bd: Double = 6.5
			for o in mobs {
				if o === r || o.hp <= 0 || o.tame { continue }
				let dx: Double = (o.b.x - r.b.x) * Double(r.dir)
				if dx < -1.0 { continue }
				let d: Double = abs(o.b.x - r.b.x) - o.b.w * 0.5
				if d < bd && abs(o.b.cy - r.b.cy) < 3.8 && (!o.isBoss || true) { bd = d; bestM = o }
			}
			if let t = bestM {
				hurtMob(t, 26, Double(r.dir), 9.0, true)
				r.st = 2
				r.t2 = 0.3
				r.cd = 0.9
			}
		}
		stepMob(r, dt, stepUp: 2.0)
		pb.x = r.b.x - Double(r.dir) * 0.5
		pb.y = r.b.y - 3.4
		pb.vx = 0
		pb.vy = 0
		facing = r.dir
		fallPeak = 0
		walkAnim += dt * 2
	}

	func dismount() {
		if let r = mounted {
			r.mounted = false
			pb.x = r.b.x + Double(-r.dir) * 1.5
			pb.y = r.b.y
			pb.vx = 0
			pb.vy = 0
			mounted = nil
			invuln = max(invuln, 0.5)
		}
		if let v = inVehicle {
			v.rider = false
			v.throttle = 0
			v.pitch = 0
			pb.x = v.b.x
			pb.y = v.b.y - v.b.h - 0.1
			pb.vx = 0
			pb.vy = 0
			inVehicle = nil
		}
		bumpHUD()
	}
}

// ===== p17_vehicles_ships =====

// MARK: - Vehicle driving and rigid-body physics

/// One collision sample on a vehicle part: where it is on the part (vehicle space), whether it
/// belongs to a wheel (wheels roll and push), and whether block corners act as ramps for it
/// (wheels and the underside of hulls, so cars climb steps and boats slide on and off beaches)
struct VSample {
	var lx: Double
	var ly: Double
	var wheel: Bool
	var ramp: Bool
	var hull: Bool
	/// a track (grips harder than a wheel and rolls less freely)
	var track: Bool = false
	/// a rail wheel (rolls almost freely on rails, drags elsewhere)
	var rail: Bool = false
	/// the cell it belongs to (a hard crash damages that part)
	var cx: Int = 0
	var cy: Int = 0
}

/// Water a part displaces when fully under (in tiles of water). Every part floats a little; hulls a
/// lot. Parts without displacement (the old model) made engines and propellers drag boats under.
func partDisplacement(_ p: PartType) -> Double {
	switch p {
	case .hinge, .servo, .piston: return 0.5
	case .receiver: return 0.2
	case .railWheel: return 0.5
	case .coupler: return 0.3
	case .bigWheel: return 3.0
	case .flap: return 0.3
	case .airBrake, .stabilizer: return 0.2
	case .ballast: return 1.0
	case .hull: return 4.0
	case .fuelTank: return 1.0
	case .frame: return 0.8
	case .seat: return 0.5
	case .wheel: return 0.5
	case .engine: return 0.7
	case .steering: return 0.2
	case .propeller: return 0.25
	case .paddle: return 0.3
	case .drill, .diamondDrill, .voidDrill: return 0.3
	case .offroadWheel: return 0.5
	case .headlight: return 0.2
	case .cargo: return 0.9
	case .block: return 1.0
	case .cockpit: return 0.6
	case .wing: return 0.3
	case .elevator: return 0.2
	case .airProp: return 0.25
	case .jet: return 0.6
	case .rotor: return 0.3
	case .tailRotor: return 0.2
	case .envelope: return 0.15
	case .burner: return 0.4
	case .track: return 0.6
	case .armor: return 0.5
	case .cannon: return 0.6
	case .autoGun: return 0.3
	case .autopilot: return 0.2
	}
}

/// Fixed physics step for vehicles (seconds). Simulating in fixed steps makes boats and cars behave
/// the same at 30 and 60 frames per second.
let vehicleStep: Double = 1.0 / 120.0

/// One place a vehicle touches the land in a physics step: where (from its centre of mass), which way
/// the surface faces, how hard a push there turns and moves it, how fast it must be leaving the surface
/// afterwards (its bounce), its grip, and the pushes given so far along the surface's face and along it
struct VContact {
	var rx: Double
	var ry: Double
	var nx: Double
	var ny: Double
	var rn: Double
	var kn: Double
	var rt: Double
	var kt: Double
	var want: Double
	var mu: Double
	var jn: Double = 0
	var jt: Double = 0
	/// a wheel's contact, and the grip of what it touches (for driving along it)
	var wheel: Bool = false
	var grip: Double = 1
	/// another vehicle it touches (nil: the land): where the place is from that one's centre of mass, how
	/// hard a push there turns it, and how easily it moves (0 while it is at rest or not being stepped)
	var other: Vehicle? = nil
	var ox: Double = 0
	var oy: Double = 0
	var on: Double = 0
	var ot: Double = 0
	var oInvM: Double = 0
	var oInvI: Double = 0
}

/// Per-frame contact summary gathered over the fixed steps
struct VStepStats {
	var anyHits: Int = 0
	var wheelHits: Int = 0
	var wet: Double = 0
	var nearWater: Bool = false
	var rammed: [(Int, Int)] = []
	/// the hardest hit each part took (speed into the ground beyond what it shrugs off)
	var crash: [PartCell: Double] = [:]
	/// hard hits on other vehicles' cells (their id, the cell, the speed beyond a landing)
	var crashOther: [(Int, PartCell, Double)] = []
	/// the vehicle it last stood on (0: none)
	var restOn: Int = 0
}

/// How far a vehicle met by another in one step is to be moved out of it (the most each way)
struct VPush {
	let o: Vehicle
	var right: Double = 0
	var left: Double = 0
	var down: Double = 0
	var up: Double = 0
}

/// What a vehicle met of the other vehicles in one step
struct VMeet {
	var hits: Int = 0
	/// its wheels standing on another vehicle, and the one most of them stand on (it takes the
	/// push back when they drive)
	var wheelsUnder: Int = 0
	var wheelOn: Vehicle? = nil
	var wheelOnN: Int = 0
	var right: Double = 0
	var left: Double = 0
	var down: Double = 0
	var up: Double = 0
	var pushes: [VPush] = []
}

/// One vehicle's frame of physics while all of them are stepped together
final class VRun {
	let v: Vehicle
	let samples: [VSample]
	let throttle: Double
	let airBusy: Bool
	let n: Int
	var stats: VStepStats = VStepStats()
	/// the other vehicles near enough to meet it this frame
	var near: [Vehicle] = []
	/// where it was at the start of the frame (a machine's sections judge stillness by how far they went)
	let x0: Double
	let y0: Double
	let a0: Double

	init(_ v: Vehicle, _ samples: [VSample], _ throttle: Double, _ airBusy: Bool, _ n: Int) {
		self.v = v
		self.samples = samples
		self.throttle = throttle
		self.airBusy = airBusy
		self.n = n
		self.x0 = v.px
		self.y0 = v.py
		self.a0 = v.angle
	}
}

extension Game {
	func updateVehicles(_ dt: Double) {
		let t0: Double = perfNow()
		radioControls(dt)
		jointControls(dt)
		stepVehicles(vehicles, dt)
		formCouplings(dt)
		// weapons, the autopilot, turns and damage (also for a vehicle at rest)
		for v in vehicles { vehicleExtras(v, dt) }
		flushVehicleBlasts()
		if vehicles.contains(where: { $0.parts.isEmpty }) { vehicles.removeAll { $0.parts.isEmpty } }
		Perf.shared.physMs = Perf.smooth(Perf.shared.physMs, perfNow() - t0)
	}

	/// What the player weighs on whatever they stand on (a vehicle frame is 1)
	var playerMass: Double { return Phys.playerMass }

	/// The seat the driver sits in: the one they got in by, or else the first (topmost, then leftmost)
	func seatCell(_ v: Vehicle) -> PartCell? {
		if let c = v.seatAt, let t = v.parts[c], t == .seat || t == .cockpit { return c }
		var best: PartCell? = nil
		for (c, t) in v.parts where t == .seat || t == .cockpit {
			if let b = best, b.dy < c.dy || (b.dy == c.dy && b.dx < c.dx) { continue }
			best = c
		}
		return best
	}

	/// Collision samples: the four corners and edge midpoints of square parts; a ring for wheels.
	/// Hull samples follow the visible hull (its art leaves the top quarter of the cell empty).
	func vehicleSamples(_ v: Vehicle) -> [VSample] {
		// (worked out again only when the vehicle changes: a big ship has thousands)
		if v.sampleKey == v.artRev && !v.sampleCache.isEmpty { return v.sampleCache }
		let made: [VSample] = makeVehicleSamples(v)
		v.sampleCache = made
		v.sampleKey = v.artRev
		return made
	}

	func makeVehicleSamples(_ v: Vehicle) -> [VSample] {
		var out: [VSample] = []
		out.reserveCapacity(v.parts.count * 8)
		// on a boat every part slides like a hull (engine and propeller included)
		let boat: Bool = v.buoyancy > 0 && v.wheels < 2
		for (c, t) in v.parts {
			let x0: Double = Double(c.dx)
			let y0: Double = Double(c.dy)
			if isWheelPart(t) {
				if let m = v.spanOf[c], m != c { continue }
				var k: Int = 0
				let tr: Bool = t == .track
				// (a big wheel: one ring three cells across round its middle)
				let big: Bool = t == .bigWheel
				let r: Double = big ? 1.47 : 0.47
				let n: Int = big ? 22 : 10
				while k < n {
					let a: Double = Double(k) / Double(n) * 2.0 * Double.pi
					var smp: VSample = VSample(lx: x0 + 0.5 + cos(a) * r, ly: y0 + 0.5 + sin(a) * r, wheel: true, ramp: true, hull: false, track: tr, cx: c.dx, cy: c.dy)
					smp.rail = t == .railWheel
					out.append(smp)
					k += 1
				}
			} else {
				let isHull: Bool = t == .hull
				let top: Double = isHull ? 0.25 : 0.02
				let mid: Double = isHull ? 0.6 : 0.5
				let pts: [(Double, Double)] = [(0.02, top), (0.5, isHull ? 0.25 : 0.0), (0.98, top), (1.0, mid), (0.98, 0.98), (0.5, 1.0), (0.02, 0.98), (0.0, mid)]
				for p in pts {
					// only outer edges can touch the world
					let nx: Int = p.0 < 0.25 ? -1 : (p.0 > 0.75 ? 1 : 0)
					let ny: Int = p.1 < 0.3 ? -1 : (p.1 > 0.75 ? 1 : 0)
					let openX: Bool = nx == 0 || v.parts[PartCell(dx: c.dx + nx, dy: c.dy)] == nil
					let openY: Bool = ny == 0 || v.parts[PartCell(dx: c.dx, dy: c.dy + ny)] == nil
					if openX || openY {
						out.append(VSample(lx: x0 + p.0, ly: y0 + p.1, wheel: false, ramp: (isHull || boat) && p.1 > 0.75, hull: isHull || boat, cx: c.dx, cy: c.dy))
					}
				}
			}
		}
		return out
	}

	/// How far a point is inside solid ground and which way is out (the exposed face it is nearest).
	/// For ramp samples (wheels, hull bottoms), the top corner of a block with open space above acts
	/// like a slope, so cars roll up one-block steps and boats slide over beach steps instead of jamming.
	func penetration(_ x: Double, _ y: Double, wheel: Bool = false) -> (Double, Double, Double)? {
		let tx: Int = Int(floor(x))
		let ty: Int = Int(floor(y))
		if !world.tile(tx, ty).solid { return nil }
		var best: Double = 9
		var nx: Double = 0
		var ny: Double = -1
		let up: Double = y - Double(ty)
		let down: Double = Double(ty + 1) - y
		let left: Double = x - Double(tx)
		let right: Double = Double(tx + 1) - x
		let topOpen: Bool = !world.tile(tx, ty - 1).solid
		if wheel && topOpen && up < 0.8 {
			let leftOpen: Bool = !world.tile(tx - 1, ty).solid
			let rightOpen: Bool = !world.tile(tx + 1, ty).solid
			if leftOpen && left < up { return (up * 0.75, -0.6, -0.8) }
			if rightOpen && right < up { return (up * 0.75, 0.6, -0.8) }
			return (up, 0, -1)
		}
		// prefer resting on top over catching on a side when barely inside
		if topOpen && up < 0.3 { return (up, 0, -1) }
		if topOpen && up < best { best = up; nx = 0; ny = -1 }
		if !world.tile(tx - 1, ty).solid && left < best { best = left; nx = -1; ny = 0 }
		if !world.tile(tx + 1, ty).solid && right < best { best = right; nx = 1; ny = 0 }
		if !world.tile(tx, ty + 1).solid && down < best { best = down; nx = 0; ny = 1 }
		if best > 8 { best = up; nx = 0; ny = -1 }
		return (best, nx, ny)
	}

	/// How much of a 1x1 part centred at (x, cy) is under water, 0...1, from the real water surface
	/// in that column (continuous, so buoyancy changes smoothly instead of in jumps)
	func submergedFraction(_ x: Double, _ cy: Double, reach: Double = 0) -> Double {
		let tx: Int = Int(floor(x))
		let bottom: Double = cy + 0.5 + reach
		let start: Int = Int(floor(cy - 0.5))
		let end: Int = Int(floor(bottom))
		var y: Int = start
		while y <= end {
			let t: Tile = world.tile(tx, y)
			if t.liquid {
				var top: Int = y
				if y == start {
					// already under at the part's top: find the surface above
					var k: Int = 0
					while k < 6 && world.tile(tx, top - 1).liquid { top -= 1; k += 1 }
				}
				// (the top cell may be only part full: its surface is lower)
				let surface: Double = Double(top) + 1.0 - world.liquidAmount(tx, top)
				return clampD(bottom - surface, 0, 1)
			}
			y += 1
		}
		return 0
	}

	/// How dense the liquid at a point is (water 1; no liquid: water's)
	func liquidDensity(_ x: Double, _ y: Double) -> Double {
		let t: Tile = world.tile(Int(floor(x)), Int(floor(y + 0.4)))
		if !t.liquid || t == .water { return 1.0 }
		return Liquids.def(t)?.density ?? 1.0
	}

	/// True when every chunk under (and next to) the vehicle is loaded. Otherwise the vehicle waits:
	/// unloaded chunks read as stone, which used to shove boats and cars around at chunk edges.
	func vehicleAreaLoaded(_ v: Vehicle) -> Bool {
		let c0: Int = floorDiv(Int(floor(v.b.left)) - 2, chunkW)
		let c1: Int = floorDiv(Int(floor(v.b.right)) + 2, chunkW)
		var c: Int = c0
		while c <= c1 {
			if world.chunks[c] == nil && world.inRange(c) { return false }
			c += 1
		}
		return true
	}

	/// One vehicle's frame of physics (the others it meets are pushed, but not stepped)
	func stepVehicle(_ v: Vehicle, _ dt: Double) {
		stepVehicles([v], dt)
	}

	/// Every vehicle's physics for one frame, in step with each other: fixed step k of every vehicle is
	/// done before step k + 1 of any, so vehicles that meet push each other at the same moment. Each one
	/// still splits its own steps as finely as its speed (and how fast it closes on the others) needs.
	func stepVehicles(_ list: [Vehicle], _ dt: Double) {
		var runs: [VRun] = []
		var resting: [Vehicle] = []
		for v in list {
			if let r = startVehicleFrame(v, dt) { runs.append(r) } else if v.asleep && v.restOn != 0 { resting.append(v) }
		}
		// a vehicle at rest on another that moves now wakes with it (it is carried, or slides off)
		for v in resting {
			guard let o = vehicleByID(v.restOn), runs.contains(where: { $0.v === o }) else { continue }
			v.asleep = false
			v.sleepT = 0
			if let r = startVehicleFrame(v, dt) { runs.append(r) }
		}
		if runs.isEmpty { return }
		for r in runs { r.v.inStep = true }
		if vehicles.count > 1 {
			for r in runs { r.near = vehiclesNear(r.v, dt) }
		}
		var most: Int = 0
		for r in runs { most = max(most, r.n) }
		var k: Int = 0
		let linked: Bool = vehicles.contains { !$0.links.isEmpty }
		let jointed: Bool = vehicles.contains { !$0.joints.isEmpty }
		while k < most {
			for r in runs where k < r.n { vehicleFixedStep(r) }
			if linked { solveCouplings(vehicleStep) }
			if jointed { solveJoints(vehicleStep) }
			k += 1
		}
		for r in runs { r.v.inStep = false }
		for r in runs { finishVehicleFrame(r, dt) }
	}

	/// The other vehicles a vehicle could meet this frame (boxes within what both can travel)
	func vehiclesNear(_ v: Vehicle, _ dt: Double) -> [Vehicle] {
		var out: [Vehicle] = []
		let t: Double = min(dt, 0.1)
		let mine: Double = (v.speed + abs(v.angVel) * v.radius) * t + 0.6
		for o in vehicles where o !== v && !o.parts.isEmpty {
			let r: Double = mine + (o.speed + abs(o.angVel) * o.radius) * t
			if o.b.right < v.b.left - r || o.b.left > v.b.right + r || o.b.y < v.b.top - r || o.b.top > v.b.y + r { continue }
			out.append(o)
		}
		return out
	}

	/// Before a vehicle's fixed steps: whether it moves at all this frame (a vehicle at rest stays at rest
	/// until something wakes it), and how many fixed steps it takes
	func startVehicleFrame(_ v: Vehicle, _ dt: Double) -> VRun? {
		if !vehicleAreaLoaded(v) { return nil }
		let throttle: Double = v.rider || v.auto != 0 || v.signalDrive ? v.throttle : 0
		let airBusy: Bool = v.aero && (abs(v.pitch) > 0.05 || v.heat > 0.02 || v.collective > 0.02 || v.turnT > 0)
		if v.asleep && abs(throttle) < 0.05 && !v.drilling && !airBusy {
			// resting vehicles cost nothing until something wakes them (one resting on another vehicle
			// sleeps while that one does)
			var held: Bool = world.boxSolid(v.b.left + 0.05, v.b.y + 0.02, v.b.right - 0.05, v.b.y + 0.2) || v.submerged > 0
			if v.restOn != 0 { held = vehicleByID(v.restOn)?.asleep ?? false }
			// (a section of a machine is held by the one it hangs from)
			if v.parentID != 0 { held = vehicleByID(v.parentID)?.asleep ?? false }
			if held { return nil }
		}
		v.asleep = false
		let samples: [VSample] = vehicleSamples(v)
		// fixed steps: the same motion whatever the frame rate (leftover time carries to the next frame)
		v.physAccum += min(dt, 0.1)
		var n: Int = Int(v.physAccum / vehicleStep)
		if n > 12 { n = 12; v.physAccum = 0 } else { v.physAccum -= Double(n) * vehicleStep }
		return VRun(v, samples, throttle, airBusy, n)
	}

	/// One fixed step of a vehicle, split as often as its speed needs
	func vehicleFixedStep(_ r: VRun) {
		let v: Vehicle = r.v
		// Nothing may move further than Phys.maxStep between collision checks, however fast it goes:
		// the step is split as often as the speed needs. With no land or water anywhere it could
		// reach in this step there is nothing to check against, and one step does (open sky is free).
		let fast: Double = v.speed + abs(v.angVel) * v.radius
		let travel: Double = fast * vehicleStep
		var split: Int = 1
		var open: Bool = false
		if travel > Phys.maxStep * 0.5 || v.contacts == 0 {
			let rr: Double = travel + 1.0
			open = world.boxOpen(v.b.left - rr, v.b.top - rr, v.b.right + rr, v.b.y + rr)
			if !open { split = min(Phys.maxSplit, max(1, Int(ceil(travel / Phys.maxStep)))) }
		}
		if !r.near.isEmpty {
			// another vehicle is near: as fine as the two close on each other
			var other: Double = 0
			for o in r.near { other = max(other, o.speed + abs(o.angVel) * o.radius) }
			let closing: Double = (fast + other) * vehicleStep
			split = max(split, min(Phys.maxSplit, max(1, Int(ceil(closing / Phys.maxStep)))))
		}
		var s: Int = 0
		while s < split {
			vehicleSubstep(v, vehicleStep / Double(split), r.samples, r.throttle, &r.stats, open: open, near: r.near)
			s += 1
		}
		if split > 1 || open || !r.near.isEmpty { v.updateBox() }
	}

	/// After a vehicle's fixed steps: blocks it rammed, what it touched, crashes, fuel, exhaust, drills,
	/// creatures it hit, and whether it can rest now
	func finishVehicleFrame(_ r: VRun, _ dt: Double) {
		let v: Vehicle = r.v
		let throttle: Double = r.throttle
		let airBusy: Bool = r.airBusy
		let n: Int = r.n
		let stats: VStepStats = r.stats
		for rm in stats.rammed where world.tile(rm.0, rm.1).solid {
			breakTile(rm.0, rm.1, v.rider)
			addShake(0.25)
			v.vx *= 0.6
		}
		if n > 0 {
			v.wheelContacts = stats.wheelHits
			// (what other vehicles met of it counts as touching too)
			v.contacts = stats.anyHits + v.touched
			v.submerged = stats.wet / Double(n)
			v.restOn = stats.restOn != 0 ? stats.restOn : v.leanOn
		}
		v.touched = 0
		v.leanOn = 0
		if !stats.crash.isEmpty { crashDamage(v, stats.crash) }
		for hit in stats.crashOther {
			if let o = vehicleByID(hit.0) { crashDamage(o, [hit.1: hit.2]) }
		}
		// fuel and exhaust
		let burning: Bool = v.engines > 0 && v.fuel > 0 && abs(throttle) > 0.1
		if burning && !isCreative {
			v.fuel = max(0, v.fuel - dt * Double(v.engines) * (v.drilling ? 1.5 : 1.0))
		}
		if burning {
			v.smoke += dt
			if v.smoke > 0.12 {
				v.smoke = 0
				let back: (Double, Double) = v.toWorld(v.dir > 0 ? Double(v.minX) - 0.2 : Double(v.maxX) + 1.2, Double(v.maxY) + 0.3)
				spawnParticles(back.0, back.1, 0x707070, 1, 1.5, 0.6, -2)
			}
		}
		if abs(throttle) > 0.2 { v.dir = throttle > 0 ? 1 : -1 }
		v.wheelRot += (v.vx * v.cosA + v.vy * v.sinA) * dt * 2.0
		v.propRot += (abs(throttle) > 0.1 && v.submerged > 0 ? 18.0 : 3.0) * dt
		v.updateBox()
		if v.drills > 0 { runDrills(v, dt) }
		vehicleImpacts(v, dt)
		// resting (on the ground, or floating calmly): let it sleep so it stops costing time and cannot jitter
		var calm: Bool = v.speed < 0.08 && abs(v.angVel) < 0.03 && abs(throttle) < 0.05 && !v.drilling && !airBusy
		if v.parentID != 0 || !v.joints.isEmpty {
			// (a section's joints leave it a little speed each step that its next step takes away again:
			// what counts is how far it really went this frame)
			let went: Double = hypot(v.px - r.x0, v.py - r.y0) / max(dt, 1e-6)
			let turned: Double = abs(v.angle - r.a0) / max(dt, 1e-6)
			calm = went < 0.08 && turned < 0.03 && abs(throttle) < 0.05 && !v.drilling && !airBusy
		}
		// (a section of a machine is held up by the one it hangs from: the machine rests as one)
		if calm && (v.contacts > 0 || v.submerged > 0 || v.parentID != 0) {
			v.sleepT += dt
			if v.sleepT > (v.submerged > 0 ? 1.5 : 0.6) { v.asleep = true; v.vx = 0; v.vy = 0; v.angVel = 0 }
		} else {
			v.sleepT = 0
		}
		if v.py > Double(world.H) + 5 {
			v.py = Double(world.H) - 6
			v.vy = 0
		}
	}

	/// One fixed physics step: gravity, buoyancy and water drag per part, propulsion, contacts with
	/// impulses and friction, positional correction, stability assists
	func vehicleSubstep(_ v: Vehicle, _ h: Double, _ samples: [VSample], _ throttle: Double, _ stats: inout VStepStats, open: Bool = false, near: [Vehicle] = []) {
		let steerOK: Bool = v.hasSeat && v.hasSteering
		let hasFuel: Bool = v.fuel > 0 || isCreative
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		v.vy += gravityG * h
		let c: Double = v.cosA
		let s: Double = v.sinA
		// buoyancy and water drag, part by part, from how deep each part really is: boats settle at
		// the waterline, tilt back level by themselves and stop bobbing quickly
		var wetSum: Double = 0
		var hullWet: Double = 0
		var hullN: Int = 0
		var nearWater: Bool = false
		for (cell, t) in v.parts {
			if open { break }
			let lx: Double = Double(cell.dx) + 0.5 - v.comX
			let ly: Double = Double(cell.dy) + 0.5 - v.comY
			let wx: Double = v.px + lx * c - ly * s
			let wy: Double = v.py + lx * s + ly * c
			let f: Double = submergedFraction(wx, wy)
			if t == .hull { hullN += 1; hullWet += f }
			if f <= 0 {
				if t == .hull && !nearWater && submergedFraction(wx, wy, reach: 1.5) > 0 { nearWater = true }
				continue
			}
			nearWater = true
			wetSum += f
			// (what it floats in: lava holds things up three times as hard as water)
			let disp: Double = cellDisplacement(v, cell, t) * liquidDensity(wx, wy)
			let rx: Double = wx - v.px
			let ry: Double = wy - v.py
			let pvx: Double = v.vx - v.angVel * ry
			let pvy: Double = v.vy + v.angVel * rx
			// (a share of the water's drag grows with the square of the speed: what holds a fast boat back)
			let fx: Double = -pvx * (0.35 + 0.3 * disp + Drive.waterDrag * disp * abs(pvx)) * f
			let fy: Double = -gravityG * disp * f - pvy * 4.5 * disp * f
			v.vx += fx * invM * h
			v.vy += fy * invM * h
			v.angVel += (rx * fy - ry * fx) * invI * h
		}
		if !open && !v.hullAir.isEmpty { hullAirForces(v, h, c, s) }
		if v.railWheels > 0 && !open { railHold(v, h) }
		let sub: Double = wetSum / Double(max(1, v.parts.count))
		// how deep the hulls sit: about 0.4 when floating freely, falling as a boat runs aground
		let hullDepth: Double = hullN > 0 ? hullWet / Double(hullN) : sub
		stats.wet += sub
		if nearWater { stats.nearWater = true }
		if sub > 0 {
			// water resists rotation, and a keel keeps a floating hull level with the surface
			let grip: Double = min(1.0, hullDepth * 4.0)
			let a: Double = remainder(v.angle, 2.0 * Double.pi)
			if abs(a) < 2.6 { v.angVel -= sin(a) * 36.0 * grip * h }
			v.angVel *= (1.0 - min(1.0, 3.5 * grip * h))
		}
		// boat propulsion along the water (horizontal, so a tilted hull cannot dive or climb on thrust).
		// A boat grounded at the edge of the water can still push itself back off.
		if steerOK && abs(throttle) > 0.1 && v.buoyancy > 0 && (sub > 0 || (nearWater && stats.anyHits > 0)) {
			// a propeller pushes with the engines' power (so its push falls as the boat gains speed); a
			// paddle's stroke only goes so fast. What a boat reaches is where that meets the water's drag.
			var thrust: Double = 0
			let going: Double = v.vx * throttle > 0 ? abs(v.vx) : 0
			if v.engines > 0 && v.openProps > 0 && hasFuel {
				thrust = min(Double(v.engines) * 16.0, Double(v.engines) * Drive.propPower / max(going, 0.1))
			} else if v.openPaddles > 0 {
				thrust = Double(v.openPaddles) * 9.0 * max(0, 1.0 - going / Drive.paddleStroke)
			}
			if sub <= 0 { thrust *= 0.45 }
			// touching the bottom: thrust fades as the hull comes out of the water, so a boat runs
			// aground at the shoreline instead of motoring up the beach (reversing off still works)
			if stats.anyHits > 0 && throttle * v.vx >= 0 {
				let landward: Bool = submergedFraction(v.px + Double(throttle > 0 ? 1 : -1) * (v.b.w * 0.5 + 0.5), v.py) <= 0
				if landward { thrust *= clampD((hullDepth - 0.12) / 0.25, 0, 1) }
			}
			v.vx += thrust * throttle * invM * h
		}
		// lift, drag and thrust in the air, part by part (wings, rotors, balloons, propellers, jets)
		if v.aero { airForces(v, h, throttle) }
		// integrate
		v.px += v.vx * h
		v.py += v.vy * h
		v.angle += v.angVel * h
		// contacts
		let c2: Double = v.cosA
		let s2: Double = v.sinA
		// deepest penetration per direction; pushing out by the maximum (not the sum) keeps many
		// simultaneous contacts from launching the vehicle, and the push per step is capped so a
		// vehicle never jumps when it ends up overlapping blocks (chunk loads, placed blocks)
		var outUp: Double = 0
		var outDown: Double = 0
		var outLeft: Double = 0
		var outRight: Double = 0
		var stepWheel: Int = 0
		var hits: Int = 0
		vContacts.removeAll(keepingCapacity: true)
		for smp in samples {
			if open { break }
			let lx: Double = smp.lx - v.comX
			let ly: Double = smp.ly - v.comY
			let rx: Double = lx * c2 - ly * s2
			let ry: Double = lx * s2 + ly * c2
			let wx: Double = v.px + rx
			let wy: Double = v.py + ry
			// (a rail wheel rides the rails' smooth surface where there are rails)
			let found: (Double, Double, Double)? = smp.rail ? railPenetration(wx, wy) : penetration(wx, wy, wheel: smp.ramp)
			guard let pen = found else { continue }
			let depth: Double = pen.0
			let nx: Double = pen.1
			let ny: Double = pen.2
			hits += 1
			if smp.wheel && ny < -0.5 { stepWheel += 1 }
			// velocity of the contact point
			let pvx: Double = v.vx - v.angVel * ry
			let pvy: Double = v.vy + v.angVel * rx
			let vn: Double = pvx * nx + pvy * ny
			// ramming: a hard hit knocks out weak wooden builds (planks, log blocks). Terrain (dirt,
			// sand, stone) never gets dug out, and tree trunks have no collision, so they never get here.
			if vn < -5.5 && v.mass * -vn > 25.0 {
				let tt: Tile = world.tile(Int(floor(wx)), Int(floor(wy)))
				if tt.hardness <= 1.0 && tt != .doorClosed && toolClass(tt) == .axe { stats.rammed.append((Int(floor(wx)), Int(floor(wy)))) }
			}
			// a crash: hitting the ground far faster than any landing breaks the part that hits (wheels and
			// tracks take a harder landing first)
			let crashAt: Double = smp.wheel ? vehicleCrashSpeed + 5.0 : vehicleCrashSpeed
			if vn < -crashAt {
				let pc: PartCell = PartCell(dx: smp.cx, dy: smp.cy)
				stats.crash[pc] = max(stats.crash[pc] ?? 0, -vn - crashAt)
			}
			// what it touches: ice grips far less than stone, hay gives a little back
			let ground: BlockPhys = blockPhys(world.tile(Int(floor(wx)), Int(floor(wy))))
			let rn: Double = rx * ny - ry * nx
			let tx: Double = -ny
			let ty: Double = nx
			let rt: Double = rx * ty - ry * tx
			let vt: Double = pvx * tx + pvy * ty
			// friction along the surface; wheels roll unless braking, hulls slide on sand and stone.
			// A boat's parts slide on sand and stone, very easily while it is still partly afloat (so it
			// eases off a beach under its own power); car bodies grip
			var mu: Double = smp.hull ? (sub > 0 ? 0.05 : 0.22) : 0.7
			if smp.wheel {
				// an aircraft's wheels roll free on the throttle and brake without it
				let braking: Bool = abs(throttle) < 0.1 || (throttle * vt < 0 && !v.aero)
				mu = braking ? (v.rider ? 0.9 : 0.25) : (v.aero ? 0.02 : 0.06)
				if smp.track { mu = braking ? (v.rider ? 1.1 : 0.4) : 0.14 }
				if smp.rail {
					// (a rail wheel coasts unless the driver pulls against the motion)
					let pulling: Bool = v.rider && abs(throttle) > 0.1 && throttle * vt < 0
					mu = railGrip(Int(floor(wx)), Int(floor(wy)), pulling, v.rider)
				}
			}
			let leave: Double = vn < 0 ? -max(0.04, ground.bounce) * vn : 0
			var kc: VContact = VContact(rx: rx, ry: ry, nx: nx, ny: ny, rn: rn, kn: invM + rn * rn * invI, rt: rt, kt: invM + rt * rt * invI, want: leave, mu: mu * ground.grip)
			kc.wheel = smp.wheel
			kc.grip = ground.grip
			vContacts.append(kc)
			let d: Double = min(0.12, max(0, depth - 0.01))
			if ny < -0.5 { outUp = max(outUp, d) } else if ny > 0.5 { outDown = max(outDown, d) }
			else if nx < -0.5 { outLeft = max(outLeft, d) } else { outRight = max(outRight, d) }
		}
		// other vehicles' cells it is inside: contacts that push both
		var meet: VMeet = VMeet()
		if !near.isEmpty { meetVehicleCells(v, samples, near, throttle, sub, &meet, &stats) }
		// The blows at every place it touches, worked out together: each is given what stops it going
		// into the surface there (and the little the surface gives back), then friction up to its grip,
		// and the round is gone through a few times so that what one place gives is taken into account
		// at the others. (One pass, as it used to be, gave a block landing flat far too much at its first
		// corner: it bounced high and spun, differently every time.)
		if !vContacts.isEmpty {
			var round: Int = 0
			while round < 4 {
				var i: Int = 0
				while i < vContacts.count {
					var k: VContact = vContacts[i]
					// (against another vehicle: the speed of one place against the other, and both pushed)
					let o: Vehicle? = k.oInvM > 0 ? k.other : nil
					var vn: Double = (v.vx - v.angVel * k.ry) * k.nx + (v.vy + v.angVel * k.rx) * k.ny
					if let ov = o { vn -= (ov.vx - ov.angVel * k.oy) * k.nx + (ov.vy + ov.angVel * k.ox) * k.ny }
					let jn0: Double = k.jn
					k.jn = max(0, jn0 + (k.want - vn) / k.kn)
					let dn: Double = k.jn - jn0
					if dn != 0 {
						v.vx += dn * k.nx * invM
						v.vy += dn * k.ny * invM
						v.angVel += k.rn * dn * invI
						if let ov = o {
							ov.vx -= dn * k.nx * k.oInvM
							ov.vy -= dn * k.ny * k.oInvM
							ov.angVel -= k.on * dn * k.oInvI
						}
					}
					let tx: Double = -k.ny
					let ty: Double = k.nx
					var vt: Double = (v.vx - v.angVel * k.ry) * tx + (v.vy + v.angVel * k.rx) * ty
					if let ov = o { vt -= (ov.vx - ov.angVel * k.oy) * tx + (ov.vy + ov.angVel * k.ox) * ty }
					let lim: Double = k.mu * k.jn
					let jt0: Double = k.jt
					k.jt = clampD(jt0 - vt / k.kt, -lim, lim)
					let dtn: Double = k.jt - jt0
					if dtn != 0 {
						v.vx += dtn * tx * invM
						v.vy += dtn * ty * invM
						v.angVel += k.rt * dtn * invI
						if let ov = o {
							ov.vx -= dtn * tx * k.oInvM
							ov.vy -= dtn * ty * k.oInvM
							ov.angVel -= k.ot * dtn * k.oInvI
						}
					}
					vContacts[i] = k
					i += 1
				}
				round += 1
			}
		}
		// (a machine's sections keep theirs: the joints are worked out with them, so a servo's turning
		// push on a section standing on the ground is held by its grip, not slid along)
		if v.parentID != 0 || !v.joints.isEmpty {
			v.heldContacts.removeAll(keepingCapacity: true)
			for k in vContacts where k.oInvM == 0 { v.heldContacts.append(k) }
		}
		v.px += (outRight - outLeft) * 0.8
		v.py += (outDown - outUp) * 0.8
		if meet.hits > 0 { settleVehicleMeet(v, meet) }
		hits += meet.hits
		stepWheel += meet.wheelsUnder
		stats.anyHits += hits
		stats.wheelHits = max(stats.wheelHits, stepWheel)
		let wrapped: Double = remainder(v.angle, 2.0 * Double.pi)
		// grounded stability assist: a tilted vehicle resting on something is eased back toward
		// upright, and rotation that would tip it further is damped. Flips stay possible in the air.
		if hits > 0 && abs(wrapped) > 0.4 && abs(wrapped) < 2.5 {
			v.angVel -= sin(wrapped) * 11.0 * h
			if v.angVel * wrapped > 0 { v.angVel *= (1.0 - min(1.0, 8.0 * h)) }
		}
		// engine drive through wheels that are on the ground
		// (only while roughly upright: a car on its nose or roof cannot push itself along)
		if stepWheel > 0 && v.canDriveOnLand && steerOK && hasFuel && abs(throttle) > 0.1 && abs(wrapped) < 1.0 && v.rotors == 0 {
			// tracks are slow but pull like nothing else
			let trackShare: Double = Double(v.tracks) / Double(max(1, v.wheels))
			let along: Double = v.vx * c2 + v.vy * s2
			// heavier builds accelerate and climb slower; more engines help, and offroad wheels pull
			// harder (their extra weight is the price)
			let grip: Double = 1.0 + 0.7 * Double(v.offroadWheels) / Double(max(1, v.wheels)) + 1.4 * trackShare
			let share: Double = groundShare(v)
			var push: Double = v.enginePower * 135.0 * grip * min(1.0, Double(stepWheel) / 4.0 + 0.5) * share
			// An engine gives so much power, so the push it can give falls as the speed rises (power is
			// push times speed), and the wheels, the gearing and the weight on them take a share that
			// grows with the speed. There is no top speed built in: a vehicle reaches the speed where
			// the two meet, so more engines or less weight is faster.
			let going: Double = along * throttle > 0 ? abs(along) : 0
			if going > 0.1 { push = min(push, v.enginePower * Drive.power * share / going) }
			let loss: Double = Drive.loss * (1.0 + Drive.lossPerMass * v.mass) * (1.0 + Drive.trackLoss * trackShare) * along * share
			let f: Double = push * throttle - loss
			v.vx += c2 * f * invM * h
			v.vy += s2 * f * invM * h
			// wheels driving on another vehicle push it back as hard
			if let o = meet.wheelOn, o.inStep && !o.asleep {
				let part: Double = Double(meet.wheelOnN) / Double(max(1, stepWheel))
				o.vx -= c2 * f * part / o.mass * h
				o.vy -= s2 * f * part / o.mass * h
			}
		} else if v.canDriveOnLand && steerOK && hasFuel && abs(throttle) > 0.1 && v.rotors == 0 {
			// not upright, or the wheels touch something beside or above it: each wheel that touches
			// pushes along what it touches, as hard as its grip there lets it
			wheelsAlongContacts(v, throttle, h)
		}
		if !v.aero {
			// the air against a vehicle with no wings (aircraft work theirs out part by part): it grows
			// with the square of the speed, on the faces that meet it
			let rho: Double = airDensity(v.py)
			// (the air moves too: a gale leans on a balloon of planks or a parked raft)
			let ax: Double = v.vx - v.windX
			v.vx -= Aero.kDrag * rho * Double(v.gridH) * ax * abs(ax) * invM * h
			v.vy -= Aero.kDrag * rho * Double(v.gridW) * v.vy * abs(v.vy) * invM * h
		}
		if hits == 0 && sub <= 0 && v.wheels > 0 && !v.aero {
			// airborne wheeled vehicles slowly level out and shed spin (arcade suspension: driving off a
			// ledge at speed no longer guarantees a nosedive)
			if abs(wrapped) < 2.0 { v.angVel -= sin(wrapped) * 4.0 * h }
			v.angVel *= (1.0 - min(1.0, 1.5 * h))
		}
		if hits == 0 && sub <= 0 && v.rider && abs(throttle) > 0.1 && !v.aero {
			// in the air the driver can lean the vehicle: gentle and capped, so holding the throttle over a
			// jump leans the car rather than spinning it (throttle leans back, reverse tips the nose down)
			if abs(v.angVel) < 2.5 || v.angVel * throttle > 0 { v.angVel -= throttle * 2.5 * h }
		}
		// a little rolling drag and air resistance
		v.vx *= (1.0 - min(1.0, 0.05 * h))
		v.angVel *= (1.0 - min(1.0, (hits > 0 ? 1.2 : 0.3) * h))
		// No limit on speed or spin: the sub-steps above keep fast things from passing through the land.
		// Only numbers that are no longer numbers are put right (they would spread to everything).
		if !(v.vx.isFinite && v.vy.isFinite && v.angVel.isFinite && v.px.isFinite && v.py.isFinite && v.angle.isFinite) {
			v.vx = 0
			v.vy = 0
			v.angVel = 0
			if !v.px.isFinite { v.px = v.b.x }
			if !v.py.isFinite { v.py = v.b.y - v.b.h * 0.5 }
			if !v.angle.isFinite { v.angle = 0 }
		}
	}

	/// Where a vehicle's collision samples are inside another vehicle's cells. Each becomes a contact
	/// that pushes both, by their masses, the way out of the other's nearest open face: a plane comes to
	/// rest on a carrier's deck and is carried by it (its grip there), a tank pushes a car, two cars that
	/// meet head on trade their speed. A vehicle at rest (or not moving this frame) is pushed against as
	/// if it were the land, and is woken by a hard enough blow.
	func meetVehicleCells(_ v: Vehicle, _ samples: [VSample], _ near: [Vehicle], _ throttle: Double, _ sub: Double, _ meet: inout VMeet, _ stats: inout VStepStats) {
		let c: Double = v.cosA
		let s: Double = v.sinA
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		let mine: Int = v.parentID != 0 || !v.joints.isEmpty ? machineRoot(v).id : -1
		for o in near {
			if o.parts.isEmpty { continue }
			// (the sections of one jointed machine pass each other: the joints hold them)
			if mine >= 0 && (o.parentID != 0 || !o.joints.isEmpty) && machineRoot(o).id == mine { continue }
			let gx: Double = o.px - v.px
			let gy: Double = o.py - v.py
			let reach: Double = v.radius + o.radius + 0.3
			if gx * gx + gy * gy > reach * reach { continue }
			let oDyn: Bool = o.inStep && !o.asleep
			let oInvM: Double = oDyn ? 1.0 / o.mass : 0
			let oInvI: Double = oDyn ? 1.0 / o.inertia : 0
			let oc: Double = o.cosA
			let os: Double = o.sinA
			// how much of the way out each one takes (all of it against one at rest)
			let mine: Double = oDyn ? o.mass / (v.mass + o.mass) : 1.0
			var push: VPush = VPush(o: o)
			var underHere: Int = 0
			for smp in samples {
				let lx: Double = smp.lx - v.comX
				let ly: Double = smp.ly - v.comY
				let rx: Double = lx * c - ly * s
				let ry: Double = lx * s + ly * c
				let dx: Double = v.px + rx - o.px
				let dy: Double = v.py + ry - o.py
				let ol: Double = dx * oc + dy * os + o.comX
				let om: Double = -dx * os + dy * oc + o.comY
				let cx: Int = Int(floor(ol))
				let cy: Int = Int(floor(om))
				let kind: UInt8 = o.meetAt(cx, cy)
				if kind == cellOpen { continue }
				guard let pen = cellPenetration(o, cx, cy, ol - Double(cx), om - Double(cy), kind, smp.ramp) else { continue }
				let nx: Double = pen.1 * oc - pen.2 * os
				let ny: Double = pen.1 * os + pen.2 * oc
				let pvx: Double = v.vx - v.angVel * ry - (oDyn ? o.vx - o.angVel * dy : 0)
				let pvy: Double = v.vy + v.angVel * rx - (oDyn ? o.vy + o.angVel * dx : 0)
				let vn: Double = pvx * nx + pvy * ny
				// a crash breaks the parts that meet, on both
				let crashAt: Double = smp.wheel ? vehicleCrashSpeed + 5.0 : vehicleCrashSpeed
				if vn < -crashAt {
					let pc: PartCell = PartCell(dx: smp.cx, dy: smp.cy)
					stats.crash[pc] = max(stats.crash[pc] ?? 0, -vn - crashAt)
					stats.crashOther.append((o.id, PartCell(dx: cx, dy: cy), (-vn - crashAt) * min(1.0, v.mass / o.mass)))
				}
				let here: BlockPhys = o.blocks[PartCell(dx: cx, dy: cy)].map { blockPhys($0) } ?? BlockPhys(weight: 1, carry: 1, span: 1)
				var mu: Double = smp.hull ? (sub > 0 ? 0.05 : 0.22) : 0.7
				if smp.wheel {
					let braking: Bool = abs(throttle) < 0.1
					mu = braking ? (v.rider ? 0.9 : 0.25) : (v.aero ? 0.02 : 0.06)
					if smp.track { mu = braking ? (v.rider ? 1.1 : 0.4) : 0.14 }
				}
				let rn: Double = rx * ny - ry * nx
				let on: Double = dx * ny - dy * nx
				let tx: Double = -ny
				let ty: Double = nx
				let rt: Double = rx * ty - ry * tx
				let ot: Double = dx * ty - dy * tx
				let kn: Double = invM + rn * rn * invI + oInvM + on * on * oInvI
				let kt: Double = invM + rt * rt * invI + oInvM + ot * ot * oInvI
				let leave: Double = vn < 0 ? -max(0.04, here.bounce) * vn : 0
				var k: VContact = VContact(rx: rx, ry: ry, nx: nx, ny: ny, rn: rn, kn: kn, rt: rt, kt: kt, want: leave, mu: mu * here.grip)
				k.wheel = smp.wheel
				k.grip = here.grip
				k.other = o
				k.ox = dx
				k.oy = dy
				k.on = on
				k.ot = ot
				k.oInvM = oInvM
				k.oInvI = oInvI
				vContacts.append(k)
				meet.hits += 1
				o.touched += 1
				if ny < -0.5 {
					stats.restOn = o.id
					if smp.wheel { meet.wheelsUnder += 1; underHere += 1 }
				} else if ny > 0.5 {
					// it is under the other one: that one rests on it
					o.leanOn = v.id
				}
				// out of each other: this one by its share, the other by the rest
				let d: Double = min(0.12, max(0, pen.0 - 0.01))
				let a: Double = d * mine
				let b: Double = d - a
				if nx > 0 { meet.right = max(meet.right, nx * a) } else { meet.left = max(meet.left, -nx * a) }
				if ny > 0 { meet.down = max(meet.down, ny * a) } else { meet.up = max(meet.up, -ny * a) }
				if oDyn && b > 0 {
					if nx > 0 { push.left = max(push.left, nx * b) } else { push.right = max(push.right, -nx * b) }
					if ny > 0 { push.up = max(push.up, ny * b) } else { push.down = max(push.down, -ny * b) }
				}
			}
			if oDyn && (push.right + push.left + push.up + push.down) > 0 { meet.pushes.append(push) }
			if underHere > meet.wheelOnN {
				meet.wheelOn = o
				meet.wheelOnN = underHere
			}
		}
	}

	/// How far a point is inside a vehicle's cell (fx, fy: where in the cell, 0...1) and which way is
	/// out, in that vehicle's own frame: the nearest face with no solid cell beyond it. A cell stood on
	/// from above only (a platform) is met near its top. For wheels and hull bottoms the top corner of a
	/// cell with open space above acts as a slope, as on the land (a car drives up onto a flatbed).
	func cellPenetration(_ o: Vehicle, _ cx: Int, _ cy: Int, _ fx: Double, _ fy: Double, _ kind: UInt8, _ ramp: Bool) -> (Double, Double, Double)? {
		if kind == cellRound {
			// a wheel: out from its middle
			let ex: Double = fx - 0.5
			let ey: Double = fy - 0.5
			let d: Double = sqrt(ex * ex + ey * ey)
			if d >= 0.47 { return nil }
			if d < 1e-6 { return (0.47, 0, -1) }
			return (0.47 - d, ex / d, ey / d)
		}
		let topOpen: Bool = o.meetAt(cx, cy - 1) != cellSolid
		if kind == cellPlatform { return topOpen && fy < 0.3 ? (fy, 0, -1) : nil }
		let leftOpen: Bool = o.meetAt(cx - 1, cy) != cellSolid
		let rightOpen: Bool = o.meetAt(cx + 1, cy) != cellSolid
		if ramp && topOpen && fy < 0.8 {
			if leftOpen && fx < fy { return (fy * 0.75, -0.6, -0.8) }
			if rightOpen && 1.0 - fx < fy { return (fy * 0.75, 0.6, -0.8) }
			return (fy, 0, -1)
		}
		if topOpen && fy < 0.3 { return (fy, 0, -1) }
		var best: Double = 9
		var nx: Double = 0
		var ny: Double = -1
		if topOpen { best = fy }
		if leftOpen && fx < best { best = fx; nx = -1; ny = 0 }
		if rightOpen && 1.0 - fx < best { best = 1.0 - fx; nx = 1; ny = 0 }
		if o.meetAt(cx, cy + 1) != cellSolid && 1.0 - fy < best { best = 1.0 - fy; nx = 0; ny = 1 }
		if best > 8 { return nil }
		return (best, nx, ny)
	}

	/// Moves two vehicles that overlap out of each other, each by its share (from meetVehicleCells),
	/// and wakes one at rest that was hit hard
	func settleVehicleMeet(_ v: Vehicle, _ meet: VMeet) {
		// (each vehicle also meets the other's samples, so each pair is settled from both sides: half each)
		v.px += (meet.right - meet.left) * 0.5
		v.py += (meet.down - meet.up) * 0.5
		for p in meet.pushes {
			p.o.px += (p.right - p.left) * 0.5
			p.o.py += (p.down - p.up) * 0.5
		}
		for k in vContacts where k.oInvM == 0 {
			guard let o = k.other, o.asleep else { continue }
			if k.jn / o.mass > 0.25 {
				o.asleep = false
				o.sleepT = 0
			}
		}
	}

	/// Wheels driving along whatever they touch (a wall the vehicle leans on, the ground when it lies on
	/// its side or roof): the engines' push is shared between the wheels that touch, each giving no more
	/// than its grip there allows. Upright on the ground the drive above is used instead.
	func wheelsAlongContacts(_ v: Vehicle, _ throttle: Double, _ h: Double) {
		var n: Int = 0
		for k in vContacts where k.wheel && k.jn > 0 { n += 1 }
		if n == 0 { return }
		let push: Double = v.enginePower * 135.0 * groundShare(v) * throttle / Double(n)
		let invM: Double = 1.0 / v.mass
		for k in vContacts where k.wheel && k.jn > 0 {
			let tx: Double = -k.ny
			let ty: Double = k.nx
			let lim: Double = Drive.tyreGrip * k.grip * k.jn
			let j: Double = clampD(push * h, -lim, lim)
			v.vx += tx * j * invM
			v.vy += ty * j * invM
			if let o = k.other, k.oInvM > 0 {
				o.vx -= tx * j * k.oInvM
				o.vy -= ty * j * k.oInvM
			}
		}
	}

	/// Hitting creatures (or the player) at speed hurts them according to speed and weight
	func vehicleImpacts(_ v: Vehicle, _ dt: Double) {
		let sp: Double = v.speed
		if sp < 4.0 { return }
		let src: DamageSource = v.rider ? .player : .environment
		let nudge: Double = 0.15
		// (the way it came this frame: at a few hundred blocks a second that is several blocks)
		let backX: Double = sp * dt > 0.6 ? v.vx * dt : 0
		let backY: Double = sp * dt > 0.6 ? v.vy * dt : 0
		let sweptL: Double = v.b.left - max(0, backX)
		let sweptR: Double = v.b.right - min(0, backX)
		let sweptT: Double = v.b.top - max(0, backY)
		let sweptB: Double = v.b.y - min(0, backY)
		for m in mobsNear(sweptL - 1, sweptR + 1) {
			if m.hp <= 0 || m.tame || m.b.ride == v.id { continue }
			if m.b.right < sweptL - nudge || m.b.left > sweptR + nudge || m.b.y < sweptT || m.b.top > sweptB { continue }
			// must actually touch a part, not just the box
			let cell: PartCell = v.cellAt(m.b.x, m.b.cy)
			var touching: Bool = v.parts[cell] != nil || backX != 0 || backY != 0
			if !touching {
				for (c, _) in v.parts {
					let cc: (Double, Double) = v.cellCenter(c)
					if abs(cc.0 - m.b.x) < 0.5 + m.b.w * 0.5 + nudge && abs(cc.1 - m.b.cy) < 0.5 + m.b.h * 0.5 { touching = true; break }
				}
			}
			if !touching { continue }
			var info = DamageInfo(amount: (sp - 3.0) * (1.2 + v.mass * 0.35), type: .impact, source: src)
			info.dirX = v.vx >= 0 ? 1 : -1
			info.knock = min(14.0, 4.0 + sp * 0.8)
			info.originX = v.b.x
			info.key = 7_000_000 + v.id
			info.cooldown = 0.7
			if applyMobDamage(m, info) {
				// the creature's weight slows the vehicle (when the vehicle's cells push it along, that
				// push already takes it: see meetVehicles; this is for a blow in passing at high speed)
				if backX != 0 || backY != 0 { v.vx *= v.mass / (v.mass + mobMass(m) * 0.5) }
				addShake(0.12)
			}
		}
		if !v.rider && !dead && inVehicle !== v && pb.ride != v.id {
			if pb.right > v.b.left && pb.left < v.b.right && pb.y > v.b.top && pb.top < v.b.y {
				var info = DamageInfo(amount: (sp - 3.0) * (1.0 + v.mass * 0.3), type: .impact, source: .environment)
				info.knock = 9.0
				info.originX = v.b.x
				info.key = 7_000_000 + v.id
				info.cooldown = 0.8
				_ = hurtPlayer(info)
			}
		}
	}

	// MARK: drills

	/// Running drills bore into the block in front of them, using the same hardness and tier rules
	/// (and drops) as hand mining. One block at a time per drill.
	func runDrills(_ v: Vehicle, _ dt: Double) {
		let powered: Bool = v.rider && (v.engines > 0 && (v.fuel > 0 || isCreative))
		v.drilling = false
		if !powered { v.drillWork.removeAll(); return }
		v.drillRot += dt * 25.0
		for (cell, d) in v.drillDir where !v.boxed.contains(cell) {
			guard let pt = v.parts[cell] else { continue }
			let pw: (Int, Double) = drillPower(pt)
			let tip: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + Double(d.0) * 0.85, Double(cell.dy) + 0.5 + Double(d.1) * 0.85)
			// the bit is three blocks wide across its facing (so the hull and wheels behind it fit
			// through the hole); it clears one block at a time, the centre one first
			var tx: Int = Int(floor(tip.0))
			var ty: Int = Int(floor(tip.1))
			var t: Tile = world.tile(tx, ty)
			if t == .air || t.liquid || t.isPlant || Tile.tierTable[t.idx] > pw.0 {
				for side in [1.0, -1.0] {
					let q: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + Double(d.0) * 0.85 + Double(d.1) * side * -1.0 + (d.1 == 0 ? 0 : 0),
													   Double(cell.dy) + 0.5 + Double(d.1) * 0.85 + Double(d.0) * side * (d.0 == 0 ? 0 : 1))
					let qt: Tile = world.tile(Int(floor(q.0)), Int(floor(q.1)))
					if qt != .air && !qt.liquid && !qt.isPlant && qt.hardness < 9000 && Tile.tierTable[qt.idx] <= pw.0 {
						tx = Int(floor(q.0)); ty = Int(floor(q.1)); t = qt
						break
					}
				}
			}
			// creatures caught in the bit get hurt
			for m in mobsNear(tip.0 - 1, tip.0 + 1) where m.hp > 0 && !m.tame {
				if abs(m.b.x - tip.0) < m.b.w * 0.5 + 0.3 && tip.1 > m.b.top - 0.2 && tip.1 < m.b.y + 0.2 {
					var info = DamageInfo(amount: 5, type: .melee, source: .player)
					info.originX = v.px
					info.knock = 4
					info.key = 8_000_000 + v.id
					info.cooldown = 0.35
					applyMobDamage(m, info)
				}
			}
			if t == .air || t.liquid || t.isPlant {
				v.drillWork[cell] = nil
				continue
			}
			let hard: Double = t.hardness
			if hard >= 9000 || Tile.tierTable[t.idx] > pw.0 {
				if Double.random(in: 0...1) < 0.1 { spawnParticles(tip.0, tip.1, 0xFFE080, 1, 3.0, 0.2, 6) }
				continue
			}
			v.drilling = true
			var work: (Int, Int, Double) = v.drillWork[cell] ?? (tx, ty, 0)
			if work.0 != tx || work.1 != ty { work = (tx, ty, 0) }
			work.2 += dt * pw.1
			if Double.random(in: 0...1) < 0.35 {
				spawnParticles(tip.0, tip.1, t.def.colors.first ?? 0x888888, 1, 3.0, 0.3, 12)
			}
			if work.2 >= max(0.05, hard * 1.5) {
				breakTile(tx, ty, true)
				v.drillWork[cell] = nil
				addShake(0.04)
			} else {
				v.drillWork[cell] = work
			}
		}
	}

	// MARK: driving

	func driveVehicle(_ v: Vehicle, _ ix: Double, _ jumpPressed: Bool, _ dt: Double) {
		v.throttle = ix
		// up and down on the stick: the elevators, the rotor's pitch, the burner
		var up: Double = -stickY
		if abs(up) < 0.15 { up = 0 }
		v.pitch = clampD(up, -1, 1)
		if v.auto != 0 { autopilotSteer(v, ix, up, dt) }
		if abs(v.throttle) > 0.05 || abs(v.pitch) > 0.05 { v.asleep = false }
		if let c = seatCell(v) {
			// sit on the seat, following the vehicle's rotation
			let p: (Double, Double) = v.toWorld(Double(c.dx) + 0.5, Double(c.dy) + 0.95)
			pb.x = p.0
			pb.y = p.1
		} else {
			pb.x = v.b.x
			pb.y = v.b.top
		}
		pb.vx = v.vx
		pb.vy = v.vy
		fallPeak = 0
		facing = v.dir
		if jumpPressed {
			let tilt: Double = abs(remainder(v.angle, 2.0 * Double.pi))
			if tilt > 0.9 && v.contacts > 0 && v.speed < 3.0 {
				// upside down: give it a shove back onto its wheels
				v.vy = -7.5
				v.angVel = (remainder(v.angle, 2.0 * Double.pi) > 0 ? -1.0 : 1.0) * 6.0
				v.asleep = false
				say("Heave! Flipping the vehicle back over.", 1.5)
			} else {
				leaveSeat(v)
			}
		}
	}

	/// Getting up from the seat. With a floor under the seat the player stands up where they sat, at any
	/// speed, and can walk about the vehicle while it carries on (the autopilot keeps its hands on the
	/// controls; without one the engines idle). With nothing to stand on they hop out as before, which
	/// only a slow vehicle allows.
	func leaveSeat(_ v: Vehicle) {
		if let c = seatCell(v) {
			let floorK: UInt8 = v.walkAt(c.dx, c.dy + 1)
			let headK: UInt8 = v.walkAt(c.dx, c.dy - 1)
			if floorK != cellOpen && headK != cellSolid {
				v.rider = false
				if v.auto == 0 {
					v.throttle = 0
					v.pitch = 0
				}
				inVehicle = nil
				boardFrame(&pb, v, Double(c.dx) + 0.5, Double(c.dy) + 1.0)
				pb.onGround = true
				fallPeak = 0
				if v.speed > 2.5 { say(v.auto != 0 ? "You stand up. The autopilot flies on." : "You stand up. Nobody is at the controls.", 2.5) }
				bumpHUD()
				return
			}
		}
		if v.speed < 2.5 {
			dismount()
		} else if v.contacts == 0 && v.submerged <= 0.02 {
			say("Nothing to stand on here. Put a floor under the seat to walk about in flight.", 3.0)
		} else {
			say("Slow down to get out (or put a floor under the seat).", 2.5)
		}
	}

	func cellPos(_ v: Vehicle, _ c: PartCell) -> (Double, Double) {
		return v.cellPos(c)
	}

	func interactVehicle(_ v: Vehicle, _ c: PartCell) {
		if let it = heldItem {
			var add: Double = 0
			switch it {
			case .mat(let m):
				if m == .coal { add = 30 }
				if m == .emberBar { add = 120 }
			case .block(let t):
				if t == .planks { add = 8 }
				if isLogTile(t) { add = 14 }
			default: break
			}
			if add > 0 {
				if v.fuelCapacity <= 0 {
					say("This vehicle has no engine or fuel tank.", 2.5)
					return
				}
				if v.fuel >= v.fuelCapacity - 0.5 {
					say("The fuel tank is full.", 1.5)
					return
				}
				v.fuel = min(v.fuelCapacity, v.fuel + add)
				if !isCreative { inv.removeAt(sel, 1) }
				say("Refueled: " + String(Int(v.fuel)) + "/" + String(Int(v.fuelCapacity)), 1.5)
				bumpHUD()
				return
			}
		}
		if repairVehiclePart(v, c) { return }
		if useVehicleBlock(v, c) { return }
		if let t = v.parts[c], t == .hinge || t == .servo || t == .piston, v.joints.contains(where: { $0.cell == c }), inVehicle == nil {
			jointEdit = JointRef(vid: v.id, cell: c)
			showJoint = true
			bumpHUD()
			return
		}
		if let t = v.parts[c], t == .cannon || t == .autoGun, inVehicle == nil {
			cycleGunMode(v, c)
			return
		}
		if v.parts[c] == .receiver && inVehicle == nil {
			radioEdit = v.id
			showRadio = true
			bumpHUD()
			return
		}
		if v.parts[c] == .coupler && v.links.contains(where: { $0.cell == c }) {
			uncouple(v, c)
			say("Uncoupled.", 1.2)
			return
		}
		if let t = v.parts[c], t == .seat || t == .steering || t == .cockpit {
			mountVehicle(v, at: t == .steering ? nil : c)
			return
		}
		if v.parts[c] != nil && vehicleStores(v, c) {
			let k: IntPair = cargoSpot(v, c)
			if world.chests[world.chestKey(k.x, k.y)] == nil { world.setChestItems(k.x, k.y, []) }
			openChest = k
			showInventory = true
			bumpHUD()
			return
		}
		if let t = v.parts[c], t == .wing || t == .flap || t == .elevator || t == .stabilizer, !v.rider, heldItem == nil || heldItem == .gadget(.wrench) {
			tiltWing(v, c)
			return
		}
		let massS: String = String(format: "%.1f", v.mass)
		let fuelA: Int = Int(v.fuel)
		let fuelB: Int = Int(v.fuelCapacity)
		var info: String = "Vehicle: mass \(massS), fuel \(fuelA)/\(fuelB)"
		if let d = v.dmg[c], d > 0.5, let t = v.parts[c] {
			let hpS: Int = Int(max(0, vehicleCellHP(v, c, t) - d))
			info = joinText(t == .block ? (v.blocks[c]?.name ?? "Block") : t.name, " damaged: ", String(hpS), " left. Hold an iron bar and tap it to mend it.")
			say(info, 3.0)
			return
		}
		if v.aero { say(joinText(info, ". ", vehicleCheck(v).hint), 3.5); return }
		if !v.hasSeat { info += ". Needs a seat." }
		else if !v.hasSteering { info += ". Needs a steering wheel." }
		else if v.buoyancy > 0 && !v.canSail && v.wheels < 2 { info += ". Add engine + propeller (or a paddle)." }
		else if v.wheels >= 2 && v.engines == 0 { info += ". Add an engine." }
		else { info += ". Tap the seat to drive." }
		say(info, 3.5)
	}

	/// Gets in to drive: in the seat tapped (with several seats), or the one sat in last
	func mountVehicle(_ v: Vehicle, at seatTapped: PartCell? = nil) {
		if !v.hasSeat || !v.hasSteering {
			say(v.hasSeat ? "Add a steering wheel (anywhere on it)." : "Add a seat or a cockpit first.", 2.5)
			return
		}
		if mounted != nil { dismount() }
		if let c = seatTapped { v.seatAt = c }
		seat = nil
		seatAboard = nil
		inVehicle = v
		pb.ride = 0
		v.rider = true
		v.asleep = false
		v.holdY = v.py
		let drillTip: String = v.drills > 0 ? " Drills spin while the engine runs." : ""
		let armed: String = v.cannons + v.guns > 0 ? " The attack stick fires the guns." : ""
		say(joinText(controlsHint(v), drillTip, armed), 4.0)
		bumpHUD()
	}
}

// MARK: - Pirate ships

extension Game {
	func shipById(_ id: Int) -> PirateShip? {
		for s in ships where s.id == id { return s }
		return nil
	}

	func alertShip(_ id: Int) {
		guard let s = shipById(id) else { return }
		if s.state == 0 { s.state = 1 }
		for cid in s.crew {
			for m in mobs where m.id == cid { m.t3 = max(m.t3, 0) }
		}
	}

	func updateCrew(_ m: Mob, _ dt: Double) -> Bool {
		guard let s = shipById(m.boat) else {
			m.boat = -1
			return false
		}
		if s.sink >= 3.0 { m.boat = -1; return false }
		if !m.raiding && s.state == 2 {
			// anchored at the shore: attackers go ashore
			if abs(pb.x - s.x) < 40 { m.raiding = true }
		}
		return false
	}

	func clampToDeck(_ m: Mob) {
		guard m.boat >= 0, !m.raiding, let s = shipById(m.boat) else { return }
		let lo: Double = s.x - PirateShip.deckHalf + m.b.w * 0.5
		let hi: Double = s.x + PirateShip.deckHalf - 0.2 - m.b.w * 0.5
		if m.b.x < lo { m.b.x = lo; m.b.vx = max(0, m.b.vx) }
		if m.b.x > hi { m.b.x = hi; m.b.vx = min(0, m.b.vx) }
	}

	func oceanOK(_ x: Int) -> Bool {
		let c: Col = gen.col(x)
		return c.biome == .ocean && c.h - WorldGen.sea >= 9
	}

	func updateShips(_ dt: Double) {
		if world.dim != .overworld {
			if !ships.isEmpty {
				for s in ships { for id in s.crew { mobs.removeAll { $0.id == id } } }
				ships.removeAll()
			}
			return
		}
		// spawning
		shipTimer -= dt
		if shipTimer <= 0 {
			shipTimer = Double.random(in: 25...50)
			trySpawnShip()
		}
		var i: Int = 0
		let sea: Double = Double(WorldGen.sea)
		while i < ships.count {
			let s: PirateShip = ships[i]
			if abs(s.x - pb.x) > 170 {
				for id in s.crew { mobs.removeAll { $0.id == id } }
				ships.remove(at: i)
				continue
			}
			if !world.isLoaded(Int(floor(s.x))) { i += 1; continue }
			s.bob += dt * 1.5
			if s.hitT > 0 { s.hitT -= dt }
			if s.hp <= 0 && s.sink == 0 {
				s.sink = 0.01
				say("The pirate ship is sinking!", 3.0)
				for id in s.crew { for m in mobs where m.id == id { m.boat = -1; m.raiding = true } }
				for _ in 0..<6 { spawnDrop(Stack(item: .block(.planks), count: 2), s.x + Double.random(in: -3...3), s.deckY(sea) - 1, Double.random(in: -2...2), -4) }
				spawnDrop(Stack(item: .mat(.goldBar), count: 2 + Int.random(in: 0...3)), s.x, s.deckY(sea) - 1, 0, -5)
				if !s.looted { spawnDrop(Stack(item: .mat(.gunpowder), count: 4), s.x + 1, s.deckY(sea) - 1, 1, -5) }
			}
			if s.sink > 0 {
				s.sink += dt * 0.8
				s.speed = 0
				spawnParticles(s.x + Double.random(in: -4...4), sea - 0.2, 0xFFFFFF, 1, 1.5, 0.5, 4)
				if s.sink > 6.0 {
					ships.remove(at: i)
					continue
				}
				i += 1
				continue
			}
			// crew bookkeeping
			var alive: Int = 0
			for id in s.crew { for m in mobs where m.id == id && m.hp > 0 { alive += 1 } }
			if alive == 0 && s.state != 3 {
				s.state = 3
				s.speed = 0
			}
			let dxP: Double = pb.x - s.x
			let landOnly: Bool = !pb.inWater
			switch s.state {
			case 0:
				s.speed = 1.6
				if abs(dxP) < 75 && landOnly && pb.y < sea + 2 { s.state = 1 }
			case 1:
				s.speed = 2.6
				s.dir = dxP >= 0 ? 1 : -1
				if abs(dxP) > 110 { s.state = 0 }
			case 2:
				s.speed = 0
				if abs(dxP) > 70 { s.state = 0 }
			default:
				s.speed = 0
			}
			if s.state == 0 || s.state == 1 {
				let aheadX: Int = Int(floor(s.x + Double(s.dir) * 6.0))
				let waterAhead: Bool = world.tile(aheadX, WorldGen.sea + 1) == .water && world.tile(aheadX, WorldGen.sea + 5) == .water
				let withinPatrol: Bool = s.x + Double(s.dir) * 6.0 > s.patrolMin && s.x + Double(s.dir) * 6.0 < s.patrolMax
				if !waterAhead || (!withinPatrol && s.state == 0) {
					if s.state == 1 { s.state = 2; s.speed = 0 } else { s.dir = -s.dir }
				} else {
					s.x += Double(s.dir) * s.speed * dt
				}
				// reached the shore: anchor and let the raiders out
				if s.state == 1 && abs(dxP) < 14 && !waterAhead { s.state = 2 }
			}
			i += 1
		}
	}

	func trySpawnShip() {
		if ships.count >= 2 || dead { return }
		if Double.random(in: 0...1) > 0.55 { return }
		let side: Double = Bool.random() ? 1.0 : -1.0
		let x: Int = Int(floor(pb.x + side * Double.random(in: 52...78)))
		if !world.isLoaded(x) { return }
		if !gen.infinite && (x < 40 || x > gen.width - 40) { return }
		if !oceanOK(x) || !oceanOK(x - 6) || !oceanOK(x + 6) { return }
		if world.tile(x, WorldGen.sea + 1) != .water { return }
		// patrol range = ocean extent
		var lo: Int = x
		var hi: Int = x
		var n: Int = 0
		while n < 260 && oceanOK(lo - 4) { lo -= 4; n += 1 }
		n = 0
		while n < 260 && oceanOK(hi + 4) { hi += 4; n += 1 }
		if hi - lo < 50 { return }
		let s = PirateShip(id: newID(), x: Double(x), dir: side > 0 ? -1 : 1, pMin: Double(lo + 8), pMax: Double(hi - 8))
		s.state = 0
		let sea: Double = Double(WorldGen.sea)
		let dy: Double = s.deckY(sea)
		var kinds: [MobKind] = [.pirate, .pirateGunner, .pirate]
		if Double.random(in: 0...1) < 0.3 { kinds.append(.pirateCaptain) }
		if Double.random(in: 0...1) < 0.4 { kinds.append(.pirateGunner) }
		var k: Int = 0
		for kind in kinds {
			let ox: Double = -2.8 + Double(k) * 1.8
			let m: Mob = addMob(kind, s.x + ox, dy)
			m.boat = s.id
			m.homeX = m.b.x
			m.persistent = true
			s.crew.append(m.id)
			k += 1
		}
		ships.append(s)
		say("Pirates ahoy! A pirate ship patrols the sea.", 3.0)
	}
}

// ===== p18_portal_map =====

// MARK: - Portal travel between dimensions

extension Game {
	func updatePortal(_ dt: Double) {
		if portalCool > 0 { portalCool -= dt }
		if fadeT > 0 { fadeT = max(0, fadeT - dt * 1.4) }
		if dead {
			portalT = 0
			return
		}
		var px: Double = pb.x
		var py: Double = pb.y - pb.h * 0.5
		if let r = mounted {
			px = r.b.x
			py = r.b.cy
		}
		let a: Tile = world.tile(Int(floor(px)), Int(floor(py)))
		let b: Tile = world.tile(Int(floor(px)), Int(floor(pb.y - 0.3)))
		let inside: Bool = a == .portalOn || b == .portalOn
		if !inside { portalNeedsExit = false }
		riftCheckT -= dt
		if riftCheckT <= 0 {
			riftCheckT = 1.0
			migrateOldRift()
		}
		if inside && portalCool <= 0 && !portalNeedsExit {
			portalT += dt
			fadeT = max(fadeT, min(1.0, portalT / 1.1))
			if Double.random(in: 0...1) < 0.5 {
				spawnParticles(px + Double.random(in: -1...1), py + Double.random(in: -1.5...1.5), 0x7FE8DA, 1, 2.0, 0.6, -2)
			}
			if portalT >= 1.1 {
				portalT = 0
				let dest: Dimension = world.dim == .overworld ? .umbral : .overworld
				let spot: (Double, Double) = portalArrival(dest)
				travelTo(dest, arriveX: spot.0, arriveY: spot.1, silent: false)
				portalNeedsExit = true
			}
		} else if portalT > 0 {
			portalT = max(0, portalT - dt * 2.0)
		}
		// the key hums when the hidden portal is near
		if world.dim == .overworld && !portalOpened {
			hintT -= dt
			if hintT <= 0 {
				hintT = 6.0
				if inv.total(.gadget(.portalKey)) > 0 {
					let lv: Int = portalHintLevel()
					if lv >= 2 { say(portalHintText(lv), 3.0) }
				}
			}
		}
	}

	/// Floor row the rift stands on in the current dimension
	var riftBase: Int {
		return world.dim == .overworld ? gen.portalY + 5 : gen.umbralPortalFloor - 1
	}

	/// Middle of the rift's oval (same for both the old frame and the new rift)
	var riftCenter: (Double, Double) {
		return (Double(gen.portalX) + 0.5, Double(riftBase - 4) + 0.5)
	}

	/// Worlds made before the rift redesign have a closed rectangular frame (which also could not be
	/// walked into). Once the area is loaded it is rebuilt as the new open rift, keeping its state.
	func migrateOldRift() {
		let px: Int = gen.portalX
		let base: Int = riftBase
		if !world.isLoaded(px - 3) || !world.isLoaded(px + 3) { return }
		if world.tile(px - 3, base - 8) != .portalFrame || world.tile(px - 3, base - 2) != .portalFrame { return }
		let fill: Tile = world.tile(px, base - 4) == .portalOn ? .portalOn : .portalOff
		for x in (px - 3)...(px + 3) {
			for y in (base - 8)...(base - 1) { _ = world.set(x, y, .air) }
		}
		let w: World = world
		riftShape(px, base, fill) { x, y, t in _ = w.set(x, y, t) }
		light.valid = false
	}

	/// Standing spot just to the right of the portal frame in the given dimension
	func portalArrival(_ dim: Dimension) -> (Double, Double) {
		if dim == .overworld {
			return (Double(gen.portalX) + 5.5, Double(gen.portalY + 6))
		}
		return (Double(gen.portalX) + 5.5, Double(gen.umbralPortalFloor))
	}

	func standable(_ x: Int, _ y: Int) -> Bool {
		// feet at row y means the tile at row y is the floor
		let f: Tile = world.tile(x, y)
		if !(f.solid || f == .platform) { return false }
		for k in 1...2 {
			let t: Tile = world.tile(x, y - k)
			if t.solid || t.liquid || t == .portalOn { return false }
		}
		return true
	}

	func findSafeSpot(_ ax: Double, _ ay: Double) -> (Double, Double) {
		let bx: Int = Int(floor(ax))
		let by: Int = Int(floor(ay))
		let offs: [Int] = [0, 1, -1, 2, -2, 3, -3, 4, -4, 6, -6, 8, -8, 10, -10]
		for o in offs {
			let x: Int = bx + o
			for dy in 0...24 {
				for sgn in [1, -1] {
					let y: Int = by + dy * sgn
					if y < 3 || y >= world.H - 2 { continue }
					if standable(x, y) { return (Double(x) + 0.5, Double(y)) }
					if dy == 0 { break }
				}
			}
		}
		// nothing usable: carve a 2x3 pocket and lay a floor
		for x in bx...(bx + 1) {
			for y in (by - 3)...(by - 1) {
				let t: Tile = world.tile(x, y)
				if t.def.hard < 9000 { world.set(x, y, .air) }
			}
			if !world.tile(x, by).solid { world.set(x, by, .stone) }
		}
		return (Double(bx) + 0.5, Double(by))
	}

	func travelTo(_ dim: Dimension, arriveX: Double, arriveY: Double, silent: Bool) {
		if inVehicle != nil { dismount() }
		let riding: Mob? = mounted
		// pets close to the player come along
		var carried: [Mob] = []
		for m in mobs where m.tame && m.hp > 0 && !(m === rex) {
			if abs(m.b.x - pb.x) < 14 && abs(m.b.y - pb.y) < 10 && m.st != 7 { carried.append(m) }
		}
		let bringRex: Mob? = (rex != nil && rex!.hp > 0) ? rex : nil
		// everything else stays behind
		vehicleStash[world.dim.rawValue] = vehicles
		vehicles = vehicleStash[dim.rawValue]
		vehicleStash[dim.rawValue] = []
		liftStash[world.dim.rawValue] = lifts
		lifts = liftStash[dim.rawValue]
		liftStash[dim.rawValue] = []
		seat = nil
		mobs.removeAll()
		projectiles.removeAll()
		drops.removeAll()
		particles.removeAll()
		flashes.removeAll()
		dangerZones.removeAll()
		ships.removeAll()
		smokes.removeAll()
		rings.removeAll()
		shipTimer = 30
		activeBoss = nil
		decksCache = []
		world.switchDimension(dim)
		world.loadAround(centerX: Int(floor(arriveX)), radius: 3)
		let spot: (Double, Double) = findSafeSpot(arriveX, arriveY)
		pb.x = spot.0
		pb.y = spot.1
		pb.vx = 0
		pb.vy = 0
		pb.onGround = true
		fallPeak = 0
		facing = -1
		camX = pb.x
		camY = pb.y - 2
		lastStreamCX = Int.min
		light.valid = false
		lightTimer = 0
		portalCool = 3.0
		portalT = 0
		fadeT = 1.0
		for (i, m) in carried.enumerated() {
			m.b.x = pb.x + 1.2 + Double(i) * 0.9
			m.b.y = pb.y
			m.b.vx = 0
			m.b.vy = 0
			mobs.append(m)
		}
		if let r = bringRex {
			r.b.vx = 0
			r.b.vy = 0
			if riding === r {
				r.b.x = pb.x
				r.b.y = pb.y
				if world.boxSolid(r.b.left, r.b.top, r.b.right, r.b.y - 0.05) {
					r.b.x = Double(gen.portalX) - 6.5
				}
			} else {
				r.b.x = Double(gen.portalX) - 6.5
				r.b.y = pb.y
			}
			if world.boxSolid(r.b.left, r.b.top, r.b.right, r.b.y - 0.05) {
				teleportRexNearPlayer(r)
			}
			r.stuckT = 0
			r.lastX = r.b.x
			mobs.append(r)
		} else {
			mounted = nil
		}
		if let r = mounted, r !== bringRex { _ = r; mounted = nil }
		if !silent {
			if dim == .umbral {
				say("You step into the Umbral Realm. Beware the heat and the dark.", 5.0)
			} else {
				say("You return to the Overworld.", 3.0)
			}
			addShake(0.4)
		}
		bumpHUD()
	}

	// MARK: portal proximity hint

	/// 0 silent ... 4 right on top of it
	func portalHintLevel() -> Int {
		if world.dim != .overworld { return 0 }
		let dx: Double = pb.x - Double(gen.portalX)
		let dy: Double = (pb.y - Double(gen.portalY)) * 0.6
		let d: Double = sqrt(dx * dx + dy * dy)
		if d < 45 { return 4 }
		if d < 120 { return 3 }
		if d < 300 { return 2 }
		if d < 700 { return 1 }
		return 0
	}

	func portalHintText(_ lv: Int) -> String {
		switch lv {
		case 4: return "The Portal Key burns in your hand. The gate is very close!"
		case 3: return "The Portal Key hums loudly. You are near."
		case 2: return "The Portal Key trembles faintly..."
		case 1: return "The Portal Key is cool and quiet. The gate is far."
		default: return "The Portal Key is silent."
		}
	}
}

// MARK: - Treasure map

struct MapMarker {
	var x: Int
	var kind: Int      // 0 spawn, 1 bear lair, 2 rex lair, 4 ruin, 5 mine shaft
	var label: String
}

struct TreasureMap {
	var x0: Int
	var x1: Int
	var step: Int
	var heights: [Int]
	var biomes: [Biome]
	var ringX: Int
	var ringY: Int
	var ringRX: Int
	var ringRY: Int
	var markers: [MapMarker]
	var clues: [String]
	var worldH: Int
}

func biomeMapColor(_ b: Biome) -> UInt32 {
	switch b {
	case .ocean: return 0x5C88B0
	case .plains: return 0x8DB25A
	case .forest: return 0x4E8A3E
	case .desert: return 0xE0C878
	case .tundra: return 0xE8F0F4
	case .jungle: return 0x2F7A2A
	case .savanna: return 0xC8B058
	case .swamp: return 0x5E7048
	case .mountain: return 0x8C8478
	case .umbral: return 0x50306A
	}
}

func roughDistance(_ d: Int) -> String {
	let unit: Int = d < 1000 ? 50 : 100
	let r: Int = max(unit, Int((Double(d) / Double(unit)).rounded()) * unit)
	if r >= 1000 {
		let th: Int = r / 1000
		let rest: Int = (r % 1000) / 100
		return String(th) + "," + String(rest) + "00"
	}
	return String(r)
}

extension Game {
	func treasureMap() -> TreasureMap {
		if let m = mapCache { return m }
		let m: TreasureMap = buildTreasureMap()
		mapCache = m
		return m
	}

	func buildTreasureMap() -> TreasureMap {
		let g: WorldGen = gen
		let px: Int = g.portalX
		let py: Int = g.portalY
		let rx: Int = 150
		let ry: Int = 80
		// the ring is offset so the exact spot stays a mystery, but the portal is always inside it
		let ox: Int = Int((hash2(11, 12, g.seed) - 0.5) * 2.0 * 0.55 * Double(rx))
		let oy: Int = Int((hash2(13, 14, g.seed) - 0.5) * 2.0 * 0.55 * Double(ry))
		let ringX: Int = px + ox
		let ringY: Int = clampI(py + oy, 200 + ry / 2, WorldGen.H - 20 - ry / 2)
		let sx: Int = g.spawnX
		var x0: Int = min(sx, ringX - rx) - 160
		var x1: Int = max(sx, ringX + rx) + 160
		if !g.infinite {
			x0 = max(0, x0)
			x1 = min(g.width - 1, x1)
		}
		let step: Int = max(4, (x1 - x0) / 300)
		var hs: [Int] = []
		var bs: [Biome] = []
		var x: Int = x0
		while x <= x1 {
			let c: Col = g.col(x)
			hs.append(c.h)
			bs.append(c.biome)
			x += step
		}
		var markers: [MapMarker] = [MapMarker(x: sx, kind: 0, label: "Start")]
		for L in g.lairCenters(near: (x0 + x1) / 2) {
			if L.cx < x0 || L.cx > x1 { continue }
			markers.append(MapMarker(x: L.cx, kind: L.kind == .bear ? 1 : 2, label: L.kind == .bear ? "Bear Den" : "Bone Nest"))
		}
		var ruins: [RareSite] = []
		for r in g.rareSites(overlapping: x0, x1) {
			ruins.append(r)
			markers.append(MapMarker(x: r.x, kind: 4, label: rareName(r.kind)))
		}
		for s in g.mineSites(overlapping: x0, x1) {
			markers.append(MapMarker(x: s.x + 1, kind: 5, label: "Mine Shaft"))
		}
		// clues
		var clues: [String] = []
		let d: Int = abs(px - sx)
		let dirS: String = px >= sx ? "east" : "west"
		clues.append("The gate lies roughly " + roughDistance(d) + " blocks " + dirS + " of where you first woke.")
		let top: Col = g.col(px)
		clues.append("Above it, the land is " + top.biome.name + ".")
		clues.append("It sleeps far below the surface, deeper than the iron veins. Dig down.")
		// nearest landmark
		var best: MapMarker? = nil
		var bd: Int = Int.max
		for mk in markers where mk.kind != 0 {
			let dd: Int = abs(mk.x - px)
			if dd < bd && dd < 900 { bd = dd; best = mk }
		}
		if let b = best {
			let side: String = b.x < px ? "west" : "east"
			clues.append("The nearest landmark, a " + b.label.lowercased() + ", stands about " + roughDistance(bd) + " blocks to its " + side + ".")
		}
		// terrain hint on each side
		for side in [-1, 1] {
			var mt: Int = 0
			var oc: Int = 0
			var k: Int = 20
			while k <= 220 {
				let b: Biome = g.colBase(px + side * k).biome
				if b == .mountain { mt += 1 }
				if b == .ocean { oc += 1 }
				k += 20
			}
			let sn: String = side < 0 ? "west" : "east"
			if mt >= 3 { clues.append("Mountains guard its " + sn + " side.") }
			else if oc >= 3 { clues.append("The sea is close on its " + sn + " side.") }
		}
		clues.append("The Portal Key hums louder as you draw near.")
		_ = ruins
		return TreasureMap(x0: x0, x1: x1, step: step, heights: hs, biomes: bs, ringX: ringX, ringY: ringY, ringRX: rx, ringRY: ry, markers: markers, clues: clues, worldH: WorldGen.H)
	}
}

func rareName(_ k: RareKind) -> String {
	switch k {
	case .house: return "Ruined House"
	case .tower: return "Ruined Tower"
	case .fort: return "Old Fort"
	case .camp: return "Abandoned Camp"
	case .overgrown: return "Overgrown Ruin"
	case .bunker: return "Buried Bunker"
	}
}

// ===== p19_save =====

// MARK: - Saving and loading

struct ChunkSave: Codable {
	var dim: Int
	var cx: Int
	var data: Data
	var walls: Data? = nil
	/// Sparkworks wiring (nil in older saves and chunks with none)
	var wires: Data? = nil
	/// which blocks the player built (nil: none; see World.isBuilt)
	var built: Data? = nil
	/// how full each part-full liquid cell is (nil: none; see p12c_fluids)
	var levels: Data? = nil
}

struct SaveMeta: Codable {
	var slot: Int
	var name: String
	var mode: GameMode
	var infinite: Bool
	var seed: UInt64
	var day: Int
	var playSeconds: Double
	var dim: Int
	/// world generation rules the world was created with (nil in saves made before basins existed)
	var genVersion: Int? = nil
	/// world type chosen at creation (nil in saves made before flat worlds existed: a standard world)
	var options: WorldOptions? = nil
}

struct SaveData: Codable {
	var version: Int = 2
	var meta: SaveMeta
	var settings: Settings
	var px: Double
	var py: Double
	var hp: Double
	var maxHP: Double
	var hunger: Double
	var timeOfDay: Double
	var kills: Int
	var spawnX: Double
	var spawnY: Double
	var inv: Inventory
	var sel: Int
	var defeated: [Int]
	var gotMap: Bool
	var portalOpened: Bool
	var chests: [ChestEntry]
	var chunks: [ChunkSave]
	var vehicles: [[VehicleSave]]
	var pets: [MobSave]
	var rex: MobSave?
	var nextID: Int
	/// nil in saves made before the journal
	var journal: Journal? = nil
	/// nil in saves made before the weather simulation (such worlds start with fair weather)
	var weather: WeatherSim? = nil
	/// how cold the player was
	var bodyCold: Double? = nil
	/// Sparkworks devices: settings and charge (nil in saves made before power)
	var power: [PowerDevSave]? = nil
	/// the mods the world was made with and its custom blocks' tile numbers (nil: no mods)
	var mods: ModWorldInfo? = nil
	/// potion effects on the player (nil: none, or a save from before potions)
	var effects: EffectsSave? = nil
	/// mutated creatures still about (nil: none)
	var mutants: [MutantSave]? = nil
	/// the exosuit (nil: never built)
	var suit: ExoSuit? = nil
	/// summoned mod creatures still about (nil: none)
	var bosses: [ModBossSave]? = nil
	/// where the player came into a custom dimension from (nil: not in one)
	var dimReturn: DimReturn? = nil
	/// the Logic Studio variables of the world's mods (nil: none)
	var logicVars: [String: Double]? = nil
	/// lift cars in every dimension (nil: none)
	var lifts: [LiftSave]? = nil
	/// the vehicle the remote control is paired with (nil: none)
	var remotePair: Int? = nil
	/// the signal channels the Logic Studio left on (nil: none)
	var logicChannels: [Bool]? = nil
}

func mobToSave(_ m: Mob) -> MobSave {
	return MobSave(kind: m.kind.rawValue, x: m.b.x, y: m.b.y, hp: m.hp, maxHP: m.maxHP, tame: m.tame, variant: m.variant, downed: m.downed, lair: m.lair, mut: m.mut > 0 ? m.mut : nil)
}

enum SaveStore {
	static var dir: URL {
		let fm = FileManager.default
		if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
			let u = d.appendingPathComponent("PixelRealmSaves", isDirectory: true)
			try? fm.createDirectory(at: u, withIntermediateDirectories: true)
			return u
		}
		return URL(fileURLWithPath: NSTemporaryDirectory())
	}

	static func url(_ slot: Int) -> URL {
		return dir.appendingPathComponent("slot" + String(slot) + ".json")
	}

	static func metaURL(_ slot: Int) -> URL {
		return dir.appendingPathComponent("slot" + String(slot) + ".meta.json")
	}

	static func write(_ s: SaveData) -> Bool {
		let enc = JSONEncoder()
		guard let d = try? enc.encode(s), let m = try? enc.encode(s.meta) else { return false }
		do {
			try d.write(to: url(s.meta.slot), options: .atomic)
			try m.write(to: metaURL(s.meta.slot), options: .atomic)
			return true
		} catch {
			return false
		}
	}

	static func read(_ slot: Int) -> SaveData? {
		guard let d = try? Data(contentsOf: url(slot)) else { return nil }
		return try? JSONDecoder().decode(SaveData.self, from: d)
	}

	static func meta(_ slot: Int) -> SaveMeta? {
		guard let d = try? Data(contentsOf: metaURL(slot)) else { return nil }
		return try? JSONDecoder().decode(SaveMeta.self, from: d)
	}

	static func delete(_ slot: Int) {
		try? FileManager.default.removeItem(at: url(slot))
		try? FileManager.default.removeItem(at: metaURL(slot))
	}

	static let slotCount: Int = 4

	/// First empty slot, or the least recently played one when all are used
	static func freeSlot() -> Int {
		for i in 0..<slotCount where meta(i) == nil { return i }
		var best: Int = 0
		var bt: Date = .distantFuture
		for i in 0..<slotCount {
			let attrs = try? FileManager.default.attributesOfItem(atPath: url(i).path)
			let t: Date = (attrs?[.modificationDate] as? Date) ?? .distantPast
			if t < bt { bt = t; best = i }
		}
		return best
	}

}

extension Game {
	func makeSave() -> SaveData {
		var cs: [ChunkSave] = []
		let cur: Int = world.dim.rawValue
		// a mimic still on the loose is saved as the chest it came out of, its hoard back inside
		var mimicSpots: [Int: [(Int, Int, [Stack])]] = [:]
		for m in mobs where m.kind == .mimic && m.hp > 0 && !m.removed {
			let ox: Int = Int(floor(m.homeX))
			let oy: Int = Int(floor(m.homeY)) - 1
			mimicSpots[floorDiv(ox, chunkW), default: []].append((ox, oy, m.loot))
		}
		for (k, c) in world.chunks where c.dirty {
			var tiles: [UInt8] = c.tiles
			for (ox, oy, _) in mimicSpots[k] ?? [] {
				let i: Int = (ox - c.x0) * c.H + oy
				if i >= 0 && i < tiles.count && tiles[i] == Tile.air.rawValue { tiles[i] = Tile.chest.rawValue }
			}
			var one: ChunkSave = ChunkSave(dim: cur, cx: k, data: Data(World.rle(tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls)), wires: c.wireCount == 0 ? nil : Data(World.rle(c.wires)), built: c.built.isEmpty ? nil : Data(World.rle(c.built)))
			if c.partials > 0 { one.levels = Data(World.rle(c.level)) }
			cs.append(one)
		}
		for d in 0..<world.parked.count {
			for (k, c) in world.parked[d] {
				if d == cur && world.chunks[k] != nil { continue }
				var one: ChunkSave = ChunkSave(dim: d, cx: k, data: Data(World.rle(c.tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls)), wires: c.wireCount == 0 ? nil : Data(World.rle(c.wires)), built: c.built.isEmpty ? nil : Data(World.rle(c.built)))
				if c.partials > 0 { one.levels = Data(World.rle(c.level)) }
				cs.append(one)
			}
		}
		var chestList: [ChestEntry] = []
		for (k, v) in world.chests { chestList.append(ChestEntry(key: k, items: v)) }
		for (_, list) in mimicSpots {
			for (ox, oy, loot) in list {
				let key: ChestKey = world.chestKey(ox, oy)
				chestList.removeAll { $0.key == key }
				chestList.append(ChestEntry(key: key, items: loot))
			}
		}
		var vs: [[VehicleSave]] = [[VehicleSave]](repeating: [], count: dimCount)
		for d in 0..<dimCount {
			let list: [Vehicle] = d == cur ? vehicles : vehicleStash[d]
			vs[d] = list.map { $0.save() }
		}
		var pets: [MobSave] = []
		for m in mobs where m.tame && m.hp > 0 && m.kind != .rex { pets.append(mobToSave(m)) }
		var rs: MobSave? = nil
		if let r = rex { rs = mobToSave(r) }
		var px: Double = pb.x
		var py: Double = pb.y
		if let r = mounted { px = r.b.x; py = r.b.y }
		if let v = inVehicle { px = v.b.x; py = v.b.y - v.b.h }
		let meta = SaveMeta(slot: slot, name: worldName, mode: mode, infinite: gen.infinite, seed: seedValue, day: dayCount, playSeconds: playSeconds, dim: cur, genVersion: gen.genVersion, options: gen.options)
		// the world's mods: those it was made with (a missing one stays listed, so it is never forgotten)
		var mi: ModWorldInfo? = modInfo
		if ModRuntime.shared.active { mi = ModRuntime.shared.worldInfo() }
		let ls: [LiftSave] = liftSaves()
		return SaveData(meta: meta, settings: settings, px: px, py: py, hp: max(1, hp), maxHP: maxHP, hunger: hunger, timeOfDay: timeOfDay, kills: kills, spawnX: spawnX, spawnY: spawnY, inv: inv, sel: sel, defeated: Array(defeated), gotMap: gotMap, portalOpened: portalOpened, chests: chestList, chunks: cs, vehicles: vs, pets: pets, rex: rs, nextID: nextID, journal: journal, weather: weather, bodyCold: bodyCold, power: powerSave(), mods: mi, effects: effectsSave(), mutants: mutantSaves(), suit: suit.isEmpty ? nil : suit, bosses: bossSaves(), dimReturn: dimReturn, logicVars: logicVars.isEmpty ? nil : logicVars, lifts: ls.isEmpty ? nil : ls, remotePair: remotePair != 0 ? remotePair : nil, logicChannels: logicChannels.contains(true) ? logicChannels : nil)
	}

	@discardableResult
	func saveNow() -> Bool {
		// a mod test world is never saved (it would overwrite a real world's slot)
		if !testMod.isEmpty || slot < 0 { return false }
		if mode == .hardcore && hardcoreOver { return false }
		if dead { return false }
		return SaveStore.write(makeSave())
	}

	static func load(_ s: SaveData, settings: Settings) -> Game {
		var st: Settings = settings
		st.rareChance = s.settings.rareChance
		// worlds saved before the generation changes keep generating exactly as they did, and
		// worlds saved before world types existed are standard worlds
		let g = Game(mode: s.meta.mode, infinite: s.meta.infinite, seed: s.meta.seed, settings: st, genVersion: s.meta.genVersion ?? 1, options: s.meta.options ?? .standard, loadSpawn: false)
		g.slot = s.meta.slot
		g.worldName = s.meta.name
		g.dayCount = s.meta.day
		g.playSeconds = s.meta.playSeconds
		g.timeOfDay = s.timeOfDay
		g.hp = s.hp
		g.maxHP = s.maxHP
		g.applyHealthRule(newWorld: false)
		g.hunger = s.hunger
		g.kills = s.kills
		g.spawnX = s.spawnX
		g.spawnY = s.spawnY
		g.inv = s.inv
		g.sel = clampI(s.sel, 0, Inventory.hotbarCount - 1)
		g.defeated = Set(s.defeated)
		g.journal = s.journal ?? Journal()
		// the weather carries on as it was (its plan is only remade if the settings differ from when
		// it was saved)
		if let w = s.weather { g.weather = w }
		g.bodyCold = clampD(s.bodyCold ?? 0, 0, 1)
		g.modInfo = s.mods
		if let e = s.effects { g.restoreEffects(e) }
		if let su = s.suit { g.restoreSuit(su) }
		g.gotMap = s.gotMap
		g.portalOpened = s.portalOpened
		g.nextID = max(g.nextID, s.nextID)
		let w: World = g.world
		w.chunks.removeAll()
		w.parked = [[Int: Chunk]](repeating: [:], count: dimCount)
		for c in s.chunks {
			if c.dim < 0 || c.dim >= dimCount { continue }
			let H: Int = dimHeight(Dimension(rawValue: c.dim) ?? .overworld)
			let ch = Chunk(cx: c.cx, H: H)
			ch.hasSky = dimHasSky(Dimension(rawValue: c.dim) ?? .overworld)
			ch.tiles = World.unrle([UInt8](c.data), chunkW * H)
			if ch.tiles.count > chunkW * H { ch.tiles = Array(ch.tiles.prefix(chunkW * H)) }
			if let wd = c.walls { ch.walls = World.unrle([UInt8](wd), chunkW * H) }
			if let wr = c.wires {
				ch.wires = World.unrle([UInt8](wr), chunkW * H)
				if ch.wires.count != chunkW * H { ch.wires = [] }
				ch.wireCount = ch.wires.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
			}
			if let bd = c.built {
				ch.built = World.unrle([UInt8](bd), chunkW * H)
				if ch.built.count != chunkW * H { ch.built = [] }
			}
			if let lv = c.levels {
				ch.level = World.unrle([UInt8](lv), chunkW * H)
				if ch.level.count != chunkW * H { ch.level = [] }
			}
			ch.dirty = true
			ch.rebuildSky()
			fillSurface(ch, g.gen, Dimension(rawValue: c.dim) ?? .overworld)
			w.parked[c.dim][c.cx] = ch
		}
		for e in s.chests { w.chests[e.key] = e.items }
		for p in s.power ?? [] {
			guard let t = Tile(rawValue: UInt8(clampI(p.t, 0, 255))), t.isPower else { continue }
			let k: ChestKey = ChestKey(d: p.d, x: p.x, y: p.y)
			let d: PowerDev = PowerDev(key: k, tile: t)
			d.dir = clampI(p.dir, 0, 3)
			d.mode = p.mode
			d.param = p.param
			d.charge = max(0, p.charge)
			d.on = p.on
			d.flag = p.flag
			d.item = p.item
			w.devs[k] = d
		}
		w.powerRev &+= 1
		var dim: Dimension = Dimension(rawValue: s.meta.dim) ?? .overworld
		var startX: Double = s.px
		var startY: Double = s.py
		g.dimReturn = s.dimReturn
		if dim.isCustom && ModRuntime.shared.dimRT(dim) == nil {
			// saved in a custom dimension whose mod is missing: back at the Overworld's spawn (the
			// dimension itself is kept for when its mod returns)
			dim = .overworld
			startX = s.spawnX
			startY = s.spawnY
			g.dimReturn = nil
			g.say("That dimension's mod is missing, so you are back in the Overworld.", 5.0)
		}
		if dim != w.dim {
			w.dim = dim
			w.H = dimHeight(dim)
		}
		w.version += 1
		w.layoutVersion += 1
		for d in 0..<min(dimCount, s.vehicles.count) {
			let list: [Vehicle] = s.vehicles[d].map { Vehicle.restore($0) }
			if d == dim.rawValue { g.vehicles = list } else { g.vehicleStash[d] = list }
		}
		if let ls = s.lifts { g.restoreLifts(ls) }
		w.loadAround(centerX: Int(floor(startX)), radius: 4)
		g.pb.x = startX
		g.pb.y = startY
		g.pb.vx = 0
		g.pb.vy = 0
		if w.boxSolid(g.pb.left, g.pb.top, g.pb.right, g.pb.y - 0.05) {
			let spot: (Double, Double) = g.findSafeSpot(startX, startY)
			g.pb.x = spot.0
			g.pb.y = spot.1
		}
		g.camX = g.pb.x
		g.camY = g.pb.y - 2
		for p in s.pets {
			guard let k = MobKind(rawValue: p.kind) else { continue }
			let m: Mob = g.addMob(k, g.pb.x + Double.random(in: -2...2), g.pb.y)
			m.tame = true
			m.hp = p.hp
			m.maxHP = p.maxHP
			m.variant = p.variant
			if let mu = p.mut, mu > 0 {
				g.reapplyMutation(m, clampI(mu, 1, MutationLimits.maxStacks))
				m.maxHP = clampD(p.maxHP, 1, MutationLimits.maxHP)
				m.hp = clampD(p.hp, 1, m.maxHP)
			}
		}
		if let r = s.rex {
			let m: Mob = g.addMob(.rex, r.x, r.y)
			m.tame = true
			m.persistent = true
			m.hp = max(1, r.hp)
			m.maxHP = r.maxHP
			m.downed = r.downed
			if m.downed { m.t1 = 20 }
			g.rex = m
			if abs(m.b.x - g.pb.x) > 40 || w.boxSolid(m.b.left, m.b.top, m.b.right, m.b.y - 0.05) {
				g.teleportRexNearPlayer(m)
			}
		}
		if let ms = s.mutants { g.restoreMutants(ms) }
		if let bs = s.bosses { g.restoreBosses(bs) }
		g.logicVars = (s.logicVars ?? [:]).filter { $0.value.isFinite }
		g.remotePair = s.remotePair ?? 0
		for (i, on) in (s.logicChannels ?? []).enumerated() where i < Radio.channels { g.logicChannels[i] = on }
		g.invuln = 2.0
		return g
	}

	func updateAutosave(_ dt: Double) {
		autosaveT += dt
		if autosaveT >= 60 {
			autosaveT = 0
			if saveNow() { floatText("Saved", pb.x, pb.y - pb.h - 0.8, 0xA0FFA0) }
		}
		if mode == .hardcore && hardcoreOver && SaveStore.meta(slot) != nil {
			SaveStore.delete(slot)
		}
	}
}

// ===== p20_assist =====

// MARK: - Action button (auto-aim), debug commands, info for the HUD

/// The attack control. `held` is true while it is down (the combat stick, or the F key). The combat stick
/// also reports where the thumb is: `power` is how far out (0 to 1), `dirX`/`dirY` the unit direction, and
/// `manual` whether it is out far enough to aim by hand. Inside the dead zone the game aims for itself.
final class ActState: @unchecked Sendable {
	var held: Bool = false
	var was: Bool = false
	var dirX: Double = 0
	var dirY: Double = 0
	var power: Double = 0
	var manual: Bool = false
	/// the dead zone, as a share of the stick's radius: a thumb has to leave `deadIn` to start aiming by
	/// hand, and come back inside `deadOut` to hand the aim back (the gap stops it flickering at the edge)
	static let deadIn: Double = 0.26
	static let deadOut: Double = 0.17

	/// A finger is on the combat stick at (x, y), measured from its centre in stick radii (any length;
	/// anything past the edge counts as the edge). Diagonals are as strong as straight lines.
	func stickAt(_ x: Double, _ y: Double) {
		let len: Double = sqrt(x * x + y * y)
		power = min(1.0, len)
		manual = power > (manual ? ActState.deadOut : ActState.deadIn)
		if manual && len > 0.0001 {
			dirX = x / len
			dirY = y / len
		}
		held = true
	}

	/// The finger left the combat stick
	func stickReleased() {
		held = false
		manual = false
		power = 0
		dirX = 0
		dirY = 0
	}
}

let actState = ActState()

extension Game {
	/// Called once per frame before tick. While the on-screen action button is held, the game aims
	/// for you: the best foe for the weapon in hand (hostile ones first, the one already locked on,
	/// in sight for ranged weapons, led and raised for the shot's drop), otherwise the block in front.
	/// A finger on the world aims for itself; then the button only keeps the action going.
	func applyActButton() {
		let held: Bool = actState.held
		defer { actState.was = held }
		if !held {
			if actState.was && !touchActive {
				useHeld = false
				useWasHeld = false
				useReleasedFlag = true
			}
			return
		}
		if dead { return }
		if touchActive {
			useHeld = true
			return
		}
		// in an armed vehicle (or one driven by remote) the attack stick aims and fires its guns
		if let v = drivenVehicle, machineGuns(v) > 0 {
			if actState.manual {
				aimX = v.px + actState.dirX * 18.0
				aimY = v.py + actState.dirY * 18.0
			} else if let a = vehicleAutoAim(v) {
				aimX = a.0
				aimY = a.1
			} else {
				aimX = v.px + Double(v.dir) * 14.0
				aimY = v.py
			}
			aimValid = true
			holdAction()
			return
		}
		let it: Item? = heldItem
		if actState.manual {
			// the thumb is out past the dead zone: aim where it points, with this weapon's own rules
			let a: (Double, Double) = stickAim(it, actState.dirX, actState.dirY, actState.power)
			aimX = a.0
			aimY = a.1
			aimValid = true
			lockTarget = nil
			if abs(actState.dirX) > 0.25 { facing = actState.dirX >= 0 ? 1 : -1 }
			holdAction()
			return
		}
		var tx: Double = pb.x + Double(facing) * 1.1
		var ty: Double = pb.y - 1.3
		var aimed: Bool = false
		var wantsMob: Bool = true
		if let i = it {
			switch i {
			case .block, .part, .mat, .food, .wall: wantsMob = false
			case .potion(let pt): wantsMob = pt.thrown && pt != .mendingSplash && pt != .regrowthSplash
			default: wantsMob = true
			}
		}
		if wantsMob, let m = autoTarget(it) {
			let a: (Double, Double) = aimPointFor(m, it)
			tx = a.0
			ty = a.1
			aimed = true
			lockTarget = m
			lockT = max(lockT, 0.5)
		}
		if case .potion(let pt)? = it, pt == .mendingSplash || pt == .regrowthSplash {
			// a helpful splash thrown with no direction bursts at the player's own feet
			tx = pb.x + Double(facing) * 0.6
			ty = pb.y - 0.3
			aimed = true
		}
		if !aimed {
			let fx: Int = Int(floor(pb.x + Double(facing) * (pb.w * 0.5 + 0.55)))
			let chest: Int = Int(floor(pb.y - 1.3))
			let feet: Int = Int(floor(pb.y - 0.4))
			let below: Int = Int(floor(pb.y + 0.5))
			var placing: Bool = false
			if case .block? = it { placing = true }
			if case .wall? = it { placing = true }
			if placing {
				// build in front at foot level, then the step below
				if !world.solid(fx, feet) { tx = Double(fx) + 0.5; ty = Double(feet) + 0.5 }
				else if !world.solid(fx, chest) { tx = Double(fx) + 0.5; ty = Double(chest) + 0.5 }
				else { tx = Double(fx) + 0.5; ty = Double(chest - 1) + 0.5 }
			} else if world.tile(fx, chest) != .air {
				tx = Double(fx) + 0.5; ty = Double(chest) + 0.5
			} else if world.tile(fx, feet) != .air {
				tx = Double(fx) + 0.5; ty = Double(feet) + 0.5
			} else if stickY > 0.5 {
				let px: Int = Int(floor(pb.x))
				tx = Double(px) + 0.5; ty = Double(below) + 0.5
			} else {
				tx = Double(fx) + 0.5; ty = Double(chest) + 0.5
			}
		}
		aimX = tx
		aimY = ty
		aimValid = true
		holdAction()
	}

	/// Keeps the action going; the first frame of a press starts it fresh
	func holdAction() {
		if !actState.was {
			useWasHeld = false
			usePressedFlag = false
		}
		useHeld = true
	}

	/// The point the combat stick aims at, from the direction (dx, dy) (a unit vector) and how far out
	/// the thumb is (0 to 1). Each kind of item reads it its own way: a blade or spear swings along the
	/// direction, bows and guns shoot along it, slings and thrown flasks land further out the further
	/// the thumb is pushed, tools and fists work on the first creature or block along it, and blocks go
	/// down against the first surface along it.
	func stickAim(_ it: Item?, _ dx: Double, _ dy: Double, _ power: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let reach: Double = min(reachDistance(), 5.5) - 0.3
		guard let item = it else { return stickDigPoint(dx, dy, reach) }
		switch item {
		case .sword, .spear, .hammer, .knife, .club, .relic:
			let d: Double = max(1.0, infusedMelee(item).reach)
			return (ox + dx * d, oy + dy * d)
		case .bow, .gun:
			return (ox + dx * 14.0, oy + dy * 14.0)
		case .sling:
			let d: Double = 4.0 + 9.0 * power
			return (ox + dx * d, oy + dy * d)
		case .potion(let pt) where pt.thrown:
			let d: Double = 3.0 + 9.0 * power
			return (ox + dx * d, oy + dy * d)
		case .gadget(let g):
			if g == .bomb || g == .fireFlask {
				let d: Double = 3.0 + 9.0 * power
				return (ox + dx * d, oy + dy * d)
			}
			return stickDigPoint(dx, dy, reach)
		case .tool:
			return stickDigPoint(dx, dy, reach)
		case .block, .wall, .part:
			return stickPlacePoint(dx, dy, reach)
		default:
			return (ox + dx * 1.5, oy + dy * 1.5)
		}
	}

	/// The first creature, or failing that the first block, along a direction from the shoulder within
	/// `r` blocks: what a pickaxe or a fist works on. With nothing in the way, the point at full reach.
	func stickDigPoint(_ dx: Double, _ dy: Double, _ r: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let near: [Mob] = mobsNear(ox - r - 1.0, ox + r + 1.0)
		var d: Double = 0.7
		while d <= r {
			let x: Double = ox + dx * d
			let y: Double = oy + dy * d
			for m in near where m.hp > 0 && !m.removed && !m.tame && !m.downed {
				if x >= m.b.left - 0.2 && x <= m.b.right + 0.2 && y >= m.b.top - 0.2 && y <= m.b.y + 0.2 { return (m.b.x, m.b.cy) }
			}
			let tx: Int = Int(floor(x))
			let ty: Int = Int(floor(y))
			let t: Tile = world.tile(tx, ty)
			if t != .air && !t.liquid { return (Double(tx) + 0.5, Double(ty) + 0.5) }
			d += 0.25
		}
		return (ox + dx * r, oy + dy * r)
	}

	/// The empty block just in front of the first solid one along a direction: where a block would go
	/// to build against what the stick points at
	func stickPlacePoint(_ dx: Double, _ dy: Double, _ r: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		var last: (Int, Int)? = nil
		var d: Double = 0.7
		while d <= r {
			let tx: Int = Int(floor(ox + dx * d))
			let ty: Int = Int(floor(oy + dy * d))
			if world.solid(tx, ty) { break }
			last = (tx, ty)
			d += 0.25
		}
		if let l = last { return (Double(l.0) + 0.5, Double(l.1) + 0.5) }
		return (ox + dx * 1.2, oy + dy * 1.2)
	}

	// MARK: debug

	func debugSpawn(_ k: MobKind) {
		let x: Double = pb.x + Double(facing) * 5.0
		var y: Double = pb.y
		let ix: Int = Int(floor(x))
		var yy: Int = Int(floor(pb.y)) - 6
		var n: Int = 0
		while n < 30 {
			if world.solid(ix, yy) && !world.solid(ix, yy - 1) && !world.solid(ix, yy - 2) { y = Double(yy); break }
			yy += 1
			n += 1
		}
		if k == .fish {
			y = pb.y - 0.5
		}
		let m: Mob = addMob(k, x, y)
		m.homeX = x
		m.homeY = y
		if k == .bearBoss || k == .rex {
			m.persistent = true
			m.homeX = x
			m.st = 3
			m.t2 = 1.0
			m.phase = 1
			m.lair = -1
		}
		say("Spawned " + m.def.name, 1.5)
	}

	/// The debug menu's give: any item of the game or of the world's mods, as many as asked (what does
	/// not fit falls at the player's feet)
	func debugGive(_ it: Item, _ n: Int) {
		let count: Int = clampI(n, 1, 9999)
		giveItem(it, count, extra: gunLoad(it))
		say(joinText("Gave ", String(count), " ", it.name, "."), 1.5)
	}

	func debugGiveKit() {
		let kit: [(Item, Int)] = [
			(.tool(.pickaxe, .diamond), 1), (.tool(.axe, .diamond), 1), (.sword(.diamond), 1), (.bow, 1),
			(.ammo(.arrow), 99), (.gun(.rifle), 1), (.gun(.pistol), 1), (.ammo(.bullet), 99),
			(.block(.torch), 99), (.block(.planks), 99), (.block(.stone), 99), (.food(.cookedMeat), 30),
			(.armor(.head, .diamond), 1), (.armor(.chest, .diamond), 1), (.armor(.legs, .diamond), 1),
			(.part(.frame), 10), (.part(.wheel), 4), (.part(.engine), 2), (.part(.seat), 1), (.part(.steering), 1),
			(.part(.fuelTank), 2), (.part(.hull), 6), (.part(.propeller), 1), (.mat(.coal), 40), (.gadget(.wrench), 1),
			(.gadget(.portalKey), 1), (.gadget(.treasureMap), 1), (.gadget(.carKit), 1), (.gadget(.motorboatKit), 1),
			(.knife(.diamond), 1), (.club(.mace), 1), (.sling, 1), (.gun(.crossbow), 1), (.gun(.blunderbuss), 1),
			(.gun(.stormRod), 1), (.ammo(.bolt), 99), (.gadget(.fireFlask), 20)
		]
		for (it, n) in kit { giveItem(it, n, extra: gunLoad(it)) }
		gotMap = true
		say("Debug kit added.", 2.0)
	}

	func debugKillHostiles() {
		for m in mobs where m.def.hostile && !m.tame && m.hp > 0 { killMob(m, true) }
	}

	struct EntityCounts {
		var hostile: Int = 0
		var passive: Int = 0
		var bosses: Int = 0
		var dying: Int = 0
		var projectiles: Int = 0
		var drops: Int = 0
		var particles: Int = 0
		var falling: Int = 0
		var vehicles: Int = 0
		var ships: Int = 0
	}

	func entityCounts() -> EntityCounts {
		var c = EntityCounts()
		for m in mobs {
			if m.hp <= 0 && !m.downed { c.dying += 1 } else if m.isBoss { c.bosses += 1 } else if m.def.hostile { c.hostile += 1 } else { c.passive += 1 }
		}
		c.projectiles = projectiles.count
		c.drops = drops.count
		c.particles = particles.count
		c.falling = fallingBlocks.count
		c.vehicles = vehicles.count
		c.ships = ships.count
		return c
	}

	/// Removes every creature, boss, ship, projectile, dropped item, falling block and particle (and,
	/// if asked, vehicles). References to them are cleared so nothing keeps a removed entity alive, and
	/// nearby lair bosses stay away until the player has left the area.
	func debugDeleteAllEntities(includeVehicles: Bool) {
		if mounted != nil || (includeVehicles && inVehicle != nil) { dismount() }
		if world.dim == .overworld {
			for L in gen.lairCenters(near: Int(floor(pb.x))) where abs(Double(L.cx) - pb.x) < 180 {
				suppressedLairs.insert(lairKey(L))
			}
		}
		for m in mobs { m.removed = true }
		mobs.removeAll()
		mobGrid.rebuild(mobs)
		activeBoss = nil
		rex = nil
		mounted = nil
		debugSelected = nil
		ships.removeAll()
		projectiles.removeAll()
		drops.removeAll()
		particles.removeAll()
		flashes.removeAll()
		fallingBlocks.removeAll()
		floats.removeAll()
		playerHitStamps.removeAll()
		if includeVehicles {
			inVehicle = nil
			vehicles.removeAll()
		}
		say("All entities deleted.", 2.0)
		bumpHUD()
	}

	/// Picks the creature closest to the cursor (or to the player when there is no cursor)
	func debugSelectAtCursor() {
		let tx: Double = aimValid ? aimX : pb.x
		let ty: Double = aimValid ? aimY : pb.y - 1
		var best: Mob? = nil
		var bd: Double = 36
		for m in mobs where m.hp > 0 || m.downed {
			let dx: Double = m.b.x - tx
			let dy: Double = m.b.cy - ty
			let d: Double = dx * dx + dy * dy
			if d < bd { bd = d; best = m }
		}
		debugSelected = best
		if best == nil { say("Nothing near the cursor.", 1.2) }
		bumpHUD()
	}

	func debugRemoveSelected() {
		guard let m = debugSelected else { return }
		m.removed = true
		mobs.removeAll { $0 === m }
		if m === activeBoss { activeBoss = nil }
		if m === rex { rex = nil }
		if m === mounted { dismount(); mounted = nil }
		debugSelected = nil
		bumpHUD()
	}

	// hazard tests: each creates a hazard right next to the player so damage, immunities and
	// knockback can be checked by eye
	func debugLavaPool() {
		let x0: Int = Int(floor(pb.x)) + facing * 3
		let y: Int = Int(floor(pb.y))
		for dx in 0..<4 {
			let x: Int = x0 + (facing > 0 ? dx : -dx)
			_ = world.set(x, y, .lava)
			_ = world.set(x, y + 1, .stone)
		}
		light.valid = false
	}

	func debugExplosionAtCursor() {
		let x: Double = aimValid ? aimX : pb.x + Double(facing) * 4
		let y: Double = aimValid ? aimY : pb.y - 1
		explode(x, y, radius: 3.0, power: 20, source: .environment, breakBlocks: false)
	}

	func debugSandDrop() {
		let x: Int = Int(floor(pb.x)) + facing * 2
		let top: Int = Int(floor(pb.y)) - 8
		for k in 0..<3 where !world.solid(x, top + k) { _ = world.set(x, top + k, .sand) }
		checkFalling(x, top + 2)
	}

	func debugSpikes() {
		let x: Int = Int(floor(pb.x)) + facing * 2
		let y: Int = Int(floor(pb.y)) - 1
		if !world.solid(x, y) { _ = world.set(x, y, .spikes) }
	}

	func debugResetMultipliers() {
		speedMult = 1
		dmgOutMult = 1
		dmgInMult = 1
		mobHealthMult = 1
		bumpHUD()
	}

	func debugResetSystems() {
		pauseMobs = false
		pauseBosses = false
		pauseSpawning = false
		pauseProjectiles = false
		pauseVehicles = false
		pauseWorldTicks = false
		pauseParticles = false
		light.valid = false
		RenderCache.shared.clearAll()
		Perf.shared.genWorstMs = 0
		tickWorstMs = 0
		say("Systems reset.", 1.2)
		bumpHUD()
	}

	/// Short report of the world generator around the player
	func debugWorldgenLines() -> [String] {
		let x: Int = Int(floor(pb.x))
		var out: [String] = []
		out.append(joinText("Gen version ", String(gen.genVersion), "  sea ", String(WorldGen.sea), gen.options.flat ? "  flat" : ""))
		out.append(joinText("Biome ", biomeHere.name, "  surface y ", String(world.surfaceY(x))))
		var nearest: Int = -1
		var d: Int = 0
		while d < 3000 && nearest < 0 {
			for sx in [x - d, x + d] {
				if !gen.infinite && (sx < 0 || sx >= gen.width) { continue }
				if gen.colBase(sx).biome == .ocean { nearest = sx; break }
			}
			d += 16
		}
		if nearest >= 0 { out.append(joinText("Nearest ocean x ", String(nearest), " (", String(abs(nearest - x)), " away)")) }
		else { out.append("No ocean within 3000 blocks") }
		return out
	}

	func debugTeleport(_ x: Double, _ y: Double) {
		if inVehicle != nil || mounted != nil { dismount() }
		world.loadAround(centerX: Int(floor(x)), radius: 3)
		let s: (Double, Double) = findSafeSpot(x, y)
		pb.x = s.0
		pb.y = s.1
		pb.vx = 0
		pb.vy = 0
		fallPeak = 0
		camX = pb.x
		camY = pb.y - 2
		light.valid = false
		if let r = rex, r.hp > 0 { teleportRexNearPlayer(r) }
	}

	func debugToSurface() {
		let x: Int = Int(floor(pb.x))
		if world.dim == .overworld {
			debugTeleport(Double(x) + 0.5, Double(world.surfaceY(x)))
		} else {
			debugTeleport(Double(x) + 0.5, Double(gen.uFloor(x)))
		}
	}

	func debugToPortal() {
		if world.dim == .overworld {
			let a: (Double, Double) = portalArrival(.overworld)
			debugTeleport(a.0, a.1)
		} else {
			let a: (Double, Double) = portalArrival(.umbral)
			debugTeleport(a.0, a.1)
		}
	}

	func debugToLair(_ kind: LairKind) {
		if world.dim != .overworld { travelTo(.overworld, arriveX: spawnX, arriveY: spawnY, silent: true) }
		for L in gen.lairCenters(near: Int(floor(pb.x))) where L.kind == kind {
			let x: Double = Double(L.cx) + (Double(L.cx) > pb.x ? -60.0 : 60.0)
			world.loadAround(centerX: Int(x), radius: 3)
			debugTeleport(x, Double(world.surfaceY(Int(x))))
			return
		}
	}

	func debugSwitchDimension() {
		let dest: Dimension = world.dim == .overworld ? .umbral : .overworld
		let a: (Double, Double) = portalArrival(dest)
		travelTo(dest, arriveX: a.0, arriveY: a.1, silent: false)
	}

	func debugSetTime(_ t: Double) {
		timeOfDay = t
		light.valid = false
	}

	// MARK: info

	var biomeHere: Biome {
		if world.dim == .umbral { return .umbral }
		if world.dim.isCustom { return customDim?.biomeAt(pb.x) ?? .plains }
		return gen.col(Int(floor(pb.x))).biome
	}

	var depthText: String {
		let y: Int = Int(floor(pb.y))
		if world.dim == .umbral { return "Umbral depth " + String(y) }
		let d: Int = y - WorldGen.sea
		if d < -2 { return String(-d) + " above sea" }
		if d <= 2 { return "Sea level" }
		if d < 60 { return String(d) + " deep" }
		if d < 220 { return String(d) + " deep (caverns)" }
		if d < 360 { return String(d) + " deep (deep caves)" }
		return String(d) + " deep (the abyss)"
	}

	var selectedName: String {
		guard let s = heldStack else { return "Empty hand" }
		let nm: String = s.item.name
		switch s.item {
		case .gun(let g):
			let ex: Int = s.extra
			let mg: Int = g.magazine
			if let a = g.ammo {
				let left: Int = inv.total(.ammo(a))
				return "\(nm)  \(ex)/\(mg) · \(left) left"
			}
			return "\(nm)  \(ex)/\(mg) charges"
		case .bow:
			let n: Int = inv.total(.ammo(.arrow))
			return "\(nm) · \(n) arrows"
		case .sling:
			var n: Int = 0
			for t in slingAmmo { n += inv.total(.block(t)) }
			return "\(nm) · \(n) stones"
		default:
			return nm
		}
	}

	func armorPieces() -> (Tier?, Tier?, Tier?) {
		var r: [Tier?] = [nil, nil, nil]
		for i in 0..<3 {
			if let s = inv.armor[i], case .armor(_, let t) = s.item { r[i] = t }
			if let s = inv.armor[i], case .custom(let k) = s.item, let m = ModRuntime.shared.item(k), m.def.kind == .armor { r[i] = Tier(rawValue: m.def.look) }
		}
		return (r[0], r[1], r[2])
	}

	var armorKey: Int {
		let a = armorPieces()
		let h: Int = a.0?.rawValue ?? 0
		let c: Int = a.1?.rawValue ?? 0
		let l: Int = a.2?.rawValue ?? 0
		return (h * 100 + c * 10 + l) &+ PlayerLookChoice(settings).key &* 1000 &+ suitDrawKey
	}

	/// Which humanoid frame to show for the player: 0 idle, 1/2 walk, 3 windup, 4 attack, 6 shoot
	func playerFrame() -> Int {
		if mounted != nil || inVehicle != nil { return 0 }
		if swingT > 0 {
			if let it = heldItem, it.isRanged { return 6 }
			return swingT > swingDur * 0.5 ? 3 : 4
		}
		if bowCharge > 0 { return 6 }
		if !pb.onGround && !pb.inWater { return 1 }
		if abs(pb.vx) > 0.6 {
			return (Int(walkAnim * 2.0) % 2 == 0) ? 1 : 2
		}
		return 0
	}
}

// ===== p21_backdrop =====

// MARK: - Backdrop walls (drawn behind open tiles; also decides what the light overlay may darken)
// 0 none (sky shows through), 1 dirt, 2 stone, 3 deep rock, 4 ash, 5 planks, 6 brick, 7 sandstone

func fillSurface(_ ch: Chunk, _ g: WorldGen, _ dim: Dimension) {
	let cd: ModDimRT? = dim.isCustom ? ModRuntime.shared.dimRT(dim) : nil
	for lx in 0..<chunkW {
		let x: Int = ch.x0 + lx
		if dim.isCustom {
			ch.surf[lx] = cd?.surfaceAt(x, g.seed) ?? ch.H - 3
			ch.ceilY[lx] = (cd?.def.ceiling ?? false) ? (cd?.ceilingAt(x, g.seed) ?? 0) : 0
		} else if dim == .overworld {
			ch.surf[lx] = g.col(x).h
		} else {
			ch.surf[lx] = g.uFloor(x)
			ch.ceilY[lx] = g.uCeil(x)
		}
	}
}

func wallForRoof(_ t: Tile) -> UInt8 {
	switch t {
	case .brick, .crackedBrick, .mossBrick, .stone, .obsidian, .portalFrame: return 6
	case .sandstone: return 7
	case .ashStone: return 4
	default: return 5
	}
}

extension World {
	func backdrop(_ ch: Chunk) -> [UInt8] {
		if ch.backRev == ch.rev && !ch.back.isEmpty { return ch.back }
		let H: Int = ch.H
		var b: [UInt8] = [UInt8](repeating: 0, count: chunkW * H)
		let over: Bool = dim == .overworld
		let hasWalls: Bool = !ch.walls.isEmpty
		for lx in 0..<chunkW {
			let x: Int = ch.x0 + lx
			let s: Int = ch.surf[lx]
			let base: Int = lx * H
			let top: Int = ch.skyTop[lx]
			var y: Int = 0
			while y < H {
				var k: UInt8 = 0
				if over {
					if y > s + 1 {
						let d: Int = y - s
						k = d < 14 ? 1 : (y < 330 ? 2 : 3)
					}
				} else if y > s + 1 || y < ch.ceilY[lx] - 1 {
					k = 4
				}
				if hasWalls && ch.walls[base + y] != 0 {
					k = ch.walls[base + y]
				} else if k == 0 && y >= top && ch.tiles[base + y] == 0 {
					k = enclosedWall(x, y, ch, lx)
				}
				b[base + y] = k
				y += 1
			}
		}
		ch.back = b
		ch.backRev = ch.rev
		return b
	}

	/// Air under a roof with walls on both sides (a house, a ruin) gets a wall behind it
	func enclosedWall(_ x: Int, _ y: Int, _ ch: Chunk, _ lx: Int) -> UInt8 {
		var roof: Tile = .air
		var k: Int = 1
		while k <= 12 {
			let t: Tile = ch.get(lx, y - k)
			if t.opaque && t.solid {
				switch t {
				case .planks, .brick, .crackedBrick, .mossBrick, .sandstone, .hay: roof = t
				default: return 0
				}
				break
			}
			k += 1
		}
		if roof == .air { return 0 }
		var leftOK: Bool = false
		var d: Int = 1
		while d <= 12 {
			let t: Tile = tile(x - d, y)
			if t.solid || t == .glass { leftOK = true; break }
			d += 1
		}
		if !leftOK { return 0 }
		d = 1
		while d <= 12 {
			let t: Tile = tile(x + d, y)
			if t.solid || t == .glass { return wallForRoof(roof) }
			d += 1
		}
		return 0
	}
}

// ===== p22_walls_doors =====

// MARK: - Background walls (no collision) and doors

let wallKinds: [Int] = [1, 2, 4, 5, 6, 7]

func wallName(_ k: Int) -> String {
	if let t = blockWallTile(k) { return joinText(t.def.name, " Wall") }
	switch k {
	case 1: return "Dirt Wall"
	case 2: return "Stone Wall"
	case 3: return "Deep Rock Wall"
	case 4: return "Ash Wall"
	case 5: return "Plank Wall"
	case 6: return "Brick Wall"
	case 7: return "Sandstone Wall"
	default: return "Wall"
	}
}

func wallSourceTile(_ k: Int) -> Tile {
	if let t = blockWallTile(k) { return t }
	switch k {
	case 1: return .dirt
	case 2: return .stone
	case 3: return .deepRock
	case 4: return .ashStone
	case 5: return .planks
	case 6: return .brick
	default: return .sandstone
	}
}

/// Inventory icon: a darkened block with a frame, so walls read differently from blocks
func wallIcon(_ k: Int) -> PixelBuf {
	var b: PixelBuf = tileBuf(wallSourceTile(k))
	for i in 0..<b.px.count {
		let c: UInt32 = b.px[i]
		if (c >> 24) != 0 { b.px[i] = 0xFF000000 | shadeRGB(c & 0xFFFFFF, 0.6) }
	}
	for i in 0..<8 {
		b.set(i, 0, 0x2A2420); b.set(i, 7, 0x2A2420); b.set(0, i, 0x2A2420); b.set(7, i, 0x2A2420)
	}
	return b
}

extension World {
	func wallAt(_ x: Int, _ y: Int) -> Int {
		if y < 0 || y >= H { return 0 }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx), !c.walls.isEmpty else { return 0 }
		return Int(c.walls[(x - cx * chunkW) * H + y])
	}

	@discardableResult
	func setWall(_ x: Int, _ y: Int, _ k: Int) -> Bool {
		if y < 1 || y >= H - 1 { return false }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return false }
		if c.walls.isEmpty {
			if k == 0 { return false }
			c.walls = [UInt8](repeating: 0, count: chunkW * H)
		}
		let i: Int = (x - cx * chunkW) * H + y
		if Int(c.walls[i]) == k { return false }
		c.walls[i] = UInt8(clampI(k, 0, 255))
		c.dirty = true
		c.rev &+= 1
		c.bumpRows(y - 1, y + 1)
		version += 1
		noteEdit(x, y)
		return true
	}
}

func isDoor(_ t: Tile) -> Bool { return t == .doorClosed || t == .doorOpen }

/// A door the player walked through, waiting to close behind them
struct WalkDoor {
	var x: Int
	var y: Int
	var t: Double
}

extension Game {
	/// The two cells of the door containing (x, y): (top, bottom)
	func doorCells(_ x: Int, _ y: Int) -> (Int, Int) {
		var top: Int = y
		var bot: Int = y
		if isDoor(world.tile(x, y - 1)) && !isDoor(world.tile(x, y + 1)) { top = y - 1 }
		else if isDoor(world.tile(x, y + 1)) { bot = y + 1 }
		return (top, bot)
	}

	func doorBlocked(_ x: Int, _ top: Int, _ bot: Int) -> Bool {
		let x0: Double = Double(x), x1: Double = Double(x + 1)
		let y0: Double = Double(top), y1: Double = Double(bot + 1)
		if pb.right > x0 + 0.05 && pb.left < x1 - 0.05 && pb.y > y0 + 0.05 && pb.top < y1 - 0.05 { return true }
		for m in mobs where m.hp > 0 {
			if m.b.right > x0 + 0.05 && m.b.left < x1 - 0.05 && m.b.y > y0 + 0.05 && m.b.top < y1 - 0.05 { return true }
		}
		return false
	}

	func setDoor(_ x: Int, _ y: Int, open: Bool) {
		let c: (Int, Int) = doorCells(x, y)
		if !open && doorBlocked(x, c.0, c.1) { return }
		let t: Tile = open ? .doorOpen : .doorClosed
		for yy in c.0...c.1 where isDoor(world.tile(x, yy)) { world.set(x, yy, t) }
	}

	func toggleDoor(_ x: Int, _ y: Int) {
		let open: Bool = world.tile(x, y) == .doorClosed
		setDoor(x, y, open: open)
		sfx(.door, at: Double(x), 0.7)
		spawnParticles(Double(x) + 0.5, Double(y) + 0.5, 0xA97B45, 2, 1.5, 0.3, 8)
	}

	/// Walking into a closed door opens it, and it closes again once the player has gone through (a door
	/// opened or shut with a tap stays as it was set)
	func doorTouch(_ ix: Double) {
		if ix != 0 {
			let sgn: Double = ix > 0 ? 1.0 : -1.0
			let reachX: Double = pb.w * 0.5 + 0.2
			let fxd: Double = pb.x + sgn * reachX
			let fx: Int = Int(floor(fxd))
			for yy in [Int(floor(pb.y - 0.5)), Int(floor(pb.y - 1.4))] {
				if world.tile(fx, yy) == .doorClosed {
					setDoor(fx, yy, open: true)
					let c: (Int, Int) = doorCells(fx, yy)
					if !walkDoors.contains(where: { $0.x == fx && $0.y == c.0 }) && walkDoors.count < 16 {
						walkDoors.append(WalkDoor(x: fx, y: c.0, t: 0))
					}
					break
				}
			}
		}
	}

	/// Closes the doors the player walked through, once they are clear of the doorway
	func updateWalkDoors(_ dt: Double) {
		if walkDoors.isEmpty { return }
		var keep: [WalkDoor] = []
		for var w in walkDoors {
			w.t += dt
			if world.tile(w.x, w.y) != .doorOpen { continue }
			let c: (Int, Int) = doorCells(w.x, w.y)
			let away: Bool = abs(pb.x - (Double(w.x) + 0.5)) > pb.w * 0.5 + 1.1 || pb.y < Double(c.0) - 0.5 || pb.top > Double(c.1) + 1.5
			if w.t > 0.5 && away && !doorBlocked(w.x, c.0, c.1) {
				setDoor(w.x, w.y, open: false)
				sfx(.door, at: Double(w.x), 0.5)
				continue
			}
			if w.t < 60 { keep.append(w) }
		}
		walkDoors = keep
	}

	func placeDoor(_ tx: Int, _ ty0: Int) -> Bool {
		// aim at either cell: the door always stands on the floor
		var ty: Int = ty0
		if world.tile(tx, ty + 1) == .air && world.tile(tx, ty + 2).solid { ty += 1 }
		if !world.tile(tx, ty + 1).solid { return false }
		for yy in [ty, ty - 1] {
			let cur: Tile = world.tile(tx, yy)
			if !(cur == .air || (cur.isPlant && cur != .torch && cur != .lantern)) { return false }
		}
		if doorBlocked(tx, ty - 1, ty) { return false }
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
		world.set(tx, ty - 1, .doorClosed)
		world.set(tx, ty, .doorClosed)
		world.setBuilt(tx, ty - 1, true)
		world.setBuilt(tx, ty, true)
		return true
	}

	func usePlaceWall(_ k: Int) {
		if placeCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return }
		if world.wallAt(tx, ty) != 0 { return }
		if world.setWall(tx, ty, k) {
			if !isCreative { inv.removeAt(sel, 1) }
			placeCD = 0.06
			swingT = 0.12
			swingDir = aimFacing()
			facing = swingDir
			bumpHUD()
		}
	}

	/// Pickaxes and axes knock out placed walls when nothing is in front of them
	func mineWall(_ tx: Int, _ ty: Int, _ kind: ToolType?, _ tier: Tier?, _ dt: Double) -> Bool {
		let k: Int = world.wallAt(tx, ty)
		if k == 0 || kind == nil || kind == .hoe { return false }
		if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
		if mineX != tx || mineY != ty { mineP = 0; mineX = tx; mineY = ty }
		mining = true
		mineNeed = 0.9
		let sp: Double = isCreative ? 1000 : (tier?.mineSpeed ?? 1.0)
		mineP += dt * sp
		if useCD <= 0 {
			swingT = 0.22
			swingDir = aimFacing()
			facing = swingDir
			useCD = 0.26
		}
		if mineP >= mineNeed {
			mineP = 0
			mining = false
			world.setWall(tx, ty, 0)
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, shadeRGB(wallSourceTile(k).def.colors.first ?? 0x888888, 0.6), 5, 3.0, 0.4, 14)
			// a block put up as a wall comes back as the block
			let back: Item = blockWallTile(k).map { Item.block($0) } ?? .wall(k)
			if !isCreative { spawnDrop(Stack(item: back, count: 1), Double(tx) + 0.5, Double(ty) + 0.5, 0, -2) }
		}
		return true
	}
}

// ===== p23_fast =====

// MARK: - Fast enum comparisons
// In debug builds (which Playgrounds uses) "==" on raw-value enums otherwise goes through a slow
// generic RawRepresentable path. These concrete versions compare the raw values directly.

extension TStyle {
	static func == (a: TStyle, b: TStyle) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: TStyle, b: TStyle) -> Bool { return a.rawValue != b.rawValue }
}

extension Tile {
	static func == (a: Tile, b: Tile) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Tile, b: Tile) -> Bool { return a.rawValue != b.rawValue }
}

extension Tier {
	static func == (a: Tier, b: Tier) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Tier, b: Tier) -> Bool { return a.rawValue != b.rawValue }
}

extension ToolType {
	static func == (a: ToolType, b: ToolType) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: ToolType, b: ToolType) -> Bool { return a.rawValue != b.rawValue }
}

extension ArmorSlot {
	static func == (a: ArmorSlot, b: ArmorSlot) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: ArmorSlot, b: ArmorSlot) -> Bool { return a.rawValue != b.rawValue }
}

extension Mat {
	static func == (a: Mat, b: Mat) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Mat, b: Mat) -> Bool { return a.rawValue != b.rawValue }
}

extension Food {
	static func == (a: Food, b: Food) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Food, b: Food) -> Bool { return a.rawValue != b.rawValue }
}

extension GunType {
	static func == (a: GunType, b: GunType) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: GunType, b: GunType) -> Bool { return a.rawValue != b.rawValue }
}

extension AmmoType {
	static func == (a: AmmoType, b: AmmoType) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: AmmoType, b: AmmoType) -> Bool { return a.rawValue != b.rawValue }
}

extension PartType {
	static func == (a: PartType, b: PartType) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: PartType, b: PartType) -> Bool { return a.rawValue != b.rawValue }
}

extension Gadget {
	static func == (a: Gadget, b: Gadget) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Gadget, b: Gadget) -> Bool { return a.rawValue != b.rawValue }
}

extension Station {
	static func == (a: Station, b: Station) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Station, b: Station) -> Bool { return a.rawValue != b.rawValue }
}

extension RecipeCat {
	static func == (a: RecipeCat, b: RecipeCat) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: RecipeCat, b: RecipeCat) -> Bool { return a.rawValue != b.rawValue }
}

extension Biome {
	static func == (a: Biome, b: Biome) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Biome, b: Biome) -> Bool { return a.rawValue != b.rawValue }
}

extension Dimension {
	static func == (a: Dimension, b: Dimension) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Dimension, b: Dimension) -> Bool { return a.rawValue != b.rawValue }
}

extension LairKind {
	static func == (a: LairKind, b: LairKind) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: LairKind, b: LairKind) -> Bool { return a.rawValue != b.rawValue }
}

extension RareKind {
	static func == (a: RareKind, b: RareKind) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: RareKind, b: RareKind) -> Bool { return a.rawValue != b.rawValue }
}

extension ProjKind {
	static func == (a: ProjKind, b: ProjKind) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: ProjKind, b: ProjKind) -> Bool { return a.rawValue != b.rawValue }
}

extension MobKind {
	static func == (a: MobKind, b: MobKind) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: MobKind, b: MobKind) -> Bool { return a.rawValue != b.rawValue }
}

extension Behavior {
	static func == (a: Behavior, b: Behavior) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: Behavior, b: Behavior) -> Bool { return a.rawValue != b.rawValue }
}

extension BossAtk {
	static func == (a: BossAtk, b: BossAtk) -> Bool { return a.rawValue == b.rawValue }
	static func != (a: BossAtk, b: BossAtk) -> Bool { return a.rawValue != b.rawValue }
}

// ===== p25_hud =====

// MARK: - HUD change detection
// The HUD only redraws when something it shows has changed (checked a few times a second).

extension Game {
	func hudKey() -> Int {
		var h: Hasher = Hasher()
		// an open device panel shows live readings: it refreshes twice a second
		if showPower { h.combine(Int(clock * 2.0)) }
		// the flight instruments and the guns' reload: four times a second while driving
		if let v = inVehicle {
			h.combine(Int(clock * 4.0))
			h.combine(v.auto)
			h.combine(v.route.count)
		}
		h.combine(vehicleBuild)
		h.combine(canBuildOnVehicle)
		h.combine(Int(hp * 2.0))
		h.combine(Int(maxHP))
		h.combine(Int(hunger * 2.0))
		h.combine(Int(air * 2.0))
		h.combine(Int(totalDefense))
		// effects tick down a second at a time; the suit's energy in steps
		for e in activeEffects() {
			h.combine(e.0.rawValue)
			h.combine(Int(e.1))
		}
		h.combine(suit.worn)
		h.combine(Int(suit.energy / 3.0))
		h.combine(sel)
		for i in 0..<Inventory.hotbarCount {
			if let s = inv.slots[i] {
				h.combine(s.item)
				h.combine(s.count)
				h.combine(s.extra)
			} else {
				h.combine(-1)
			}
		}
		if showInventory || openChest != nil {
			for i in Inventory.hotbarCount..<inv.slots.count {
				if let s = inv.slots[i] {
					h.combine(i)
					h.combine(s.item)
					h.combine(s.count)
				}
			}
			for a in inv.armor { h.combine(a?.item) }
			h.combine(carry?.item)
			h.combine(carry?.count ?? 0)
			if let p = openChest {
				let items: [Stack] = world.chestItems(p.x, p.y)
				for s in items {
					h.combine(s.item)
					h.combine(s.count)
				}
			}
		}
		h.combine(reloadT > 0)
		h.combine(mounted != nil)
		h.combine(inVehicle != nil)
		h.combine(flying || noclip)
		h.combine(activeBoss != nil)
		h.combine(Int(bossBarFrac * 120.0))
		h.combine(gotMap)
		h.combine(dayCount)
		h.combine(isNight)
		h.combine(world.dim.rawValue)
		h.combine(tilePx)
		if settings.showCoords {
			h.combine(Int(floor(pb.x)))
			h.combine(Int(floor(pb.y)))
		}
		h.combine(vehicleHelpKey())
		h.combine(message ?? "")
		// weather: the banner, what is shown in the info corner, a barometer in hand
		h.combine(wxBanner)
		h.combine(weather.kind.rawValue)
		h.combine(wxHere.snow)
		h.combine(Int(abs(wxHere.wind)))
		h.combine(weatherHereLabel)
		if case .gadget(.barometer)? = heldItem { h.combine(Int(pressureNow())) }
		if settings.showFPS { h.combine(Int(renderFPS)) }
		return h.finalize()
	}
}

// ===== p26_vehicle_ux =====

// MARK: - Vehicle building made simple: kits, attach hints, a checklist, drive / pack-up

struct KitPart {
	var dx: Int
	var dy: Int
	var p: PartType
}

/// Ready-made layouts (dy grows downwards; row 0 is the top)
func kitLayout(_ g: Gadget) -> [KitPart] {
	switch g {
	case .carKit:
		return [KitPart(dx: 1, dy: 0, p: .seat), KitPart(dx: 2, dy: 0, p: .steering),
				KitPart(dx: 0, dy: 1, p: .fuelTank), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .engine),
				KitPart(dx: 0, dy: 2, p: .wheel), KitPart(dx: 3, dy: 2, p: .wheel)]
	case .boatKit:
		return [KitPart(dx: 1, dy: 0, p: .seat), KitPart(dx: 2, dy: 0, p: .steering),
				KitPart(dx: 0, dy: 1, p: .hull), KitPart(dx: 1, dy: 1, p: .hull), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .paddle)]
	case .motorboatKit:
		// the engine sits on the hull (not out past its end, which tipped the old layout stern-down)
		return [KitPart(dx: 1, dy: 0, p: .engine), KitPart(dx: 2, dy: 0, p: .seat), KitPart(dx: 3, dy: 0, p: .steering), KitPart(dx: 4, dy: 0, p: .fuelTank),
				KitPart(dx: 0, dy: 1, p: .propeller), KitPart(dx: 1, dy: 1, p: .hull), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .hull), KitPart(dx: 4, dy: 1, p: .hull)]
	case .planeKit:
		// a light plane, nose to the right: tail elevator, wings under the cockpit, engine and propeller in front
		return [KitPart(dx: 0, dy: 0, p: .elevator), KitPart(dx: 4, dy: 0, p: .cockpit),
				KitPart(dx: 0, dy: 1, p: .frame), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .wing), KitPart(dx: 3, dy: 1, p: .wing), KitPart(dx: 4, dy: 1, p: .wing),
				KitPart(dx: 5, dy: 1, p: .fuelTank), KitPart(dx: 6, dy: 1, p: .engine), KitPart(dx: 7, dy: 1, p: .airProp),
				KitPart(dx: 3, dy: 2, p: .wheel), KitPart(dx: 6, dy: 2, p: .wheel)]
	case .heliKit:
		// two engines under one rotor, a tail rotor on the boom, skids below
		return [KitPart(dx: 3, dy: 0, p: .rotor),
				KitPart(dx: 0, dy: 1, p: .tailRotor), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .engine), KitPart(dx: 4, dy: 1, p: .cockpit),
				KitPart(dx: 3, dy: 2, p: .engine), KitPart(dx: 4, dy: 2, p: .fuelTank),
				KitPart(dx: 2, dy: 3, p: .frame), KitPart(dx: 3, dy: 3, p: .frame), KitPart(dx: 4, dy: 3, p: .frame)]
	case .airshipKit:
		// a balloon of 20 envelopes, two burners under it, a gondola with propellers at both ends
		var out: [KitPart] = []
		for x in 1...6 { out.append(KitPart(dx: x, dy: 0, p: .envelope)) }
		for x in 0...7 { out.append(KitPart(dx: x, dy: 1, p: .envelope)) }
		for x in 1...6 { out.append(KitPart(dx: x, dy: 2, p: .envelope)) }
		out.append(contentsOf: [KitPart(dx: 2, dy: 3, p: .frame), KitPart(dx: 3, dy: 3, p: .burner), KitPart(dx: 4, dy: 3, p: .burner), KitPart(dx: 5, dy: 3, p: .frame),
								KitPart(dx: 0, dy: 4, p: .airProp), KitPart(dx: 1, dy: 4, p: .frame), KitPart(dx: 2, dy: 4, p: .cockpit), KitPart(dx: 3, dy: 4, p: .engine),
								KitPart(dx: 4, dy: 4, p: .fuelTank), KitPart(dx: 5, dy: 4, p: .frame), KitPart(dx: 6, dy: 4, p: .airProp)])
		return out
	case .tankKit:
		// armour all round, a cannon on the turret, two engines, tracks the whole length
		var out: [KitPart] = [KitPart(dx: 3, dy: 0, p: .armor), KitPart(dx: 4, dy: 0, p: .cannon),
							  KitPart(dx: 1, dy: 1, p: .armor), KitPart(dx: 2, dy: 1, p: .seat), KitPart(dx: 3, dy: 1, p: .steering), KitPart(dx: 4, dy: 1, p: .armor),
							  KitPart(dx: 0, dy: 2, p: .armor), KitPart(dx: 1, dy: 2, p: .engine), KitPart(dx: 2, dy: 2, p: .fuelTank), KitPart(dx: 3, dy: 2, p: .engine),
							  KitPart(dx: 4, dy: 2, p: .frame), KitPart(dx: 5, dy: 2, p: .armor)]
		for x in 0...5 { out.append(KitPart(dx: x, dy: 3, p: .track)) }
		return out
	case .truckKit:
		// a cab with two engines and a headlight, a bed of three cargo crates, three axles
		return [KitPart(dx: 0, dy: 0, p: .cargo), KitPart(dx: 1, dy: 0, p: .cargo), KitPart(dx: 2, dy: 0, p: .cargo), KitPart(dx: 4, dy: 0, p: .seat), KitPart(dx: 5, dy: 0, p: .steering), KitPart(dx: 6, dy: 0, p: .headlight),
				KitPart(dx: 0, dy: 1, p: .frame), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .frame), KitPart(dx: 4, dy: 1, p: .fuelTank),
				KitPart(dx: 5, dy: 1, p: .engine), KitPart(dx: 6, dy: 1, p: .engine),
				KitPart(dx: 0, dy: 2, p: .wheel), KitPart(dx: 2, dy: 2, p: .wheel), KitPart(dx: 5, dy: 2, p: .wheel)]
	default:
		return []
	}
}

/// Earlier layouts of a kit, so vehicles placed by older versions still pack back into their kit
func legacyKitLayouts(_ g: Gadget) -> [[KitPart]] {
	if g == .motorboatKit {
		return [[KitPart(dx: 1, dy: 0, p: .fuelTank), KitPart(dx: 2, dy: 0, p: .seat), KitPart(dx: 3, dy: 0, p: .steering),
				 KitPart(dx: 0, dy: 1, p: .propeller), KitPart(dx: 1, dy: 1, p: .engine), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .hull), KitPart(dx: 4, dy: 1, p: .hull)]]
	}
	return []
}

func isKit(_ g: Gadget) -> Bool {
	switch g {
	case .carKit, .boatKit, .motorboatKit, .planeKit, .heliKit, .airshipKit, .tankKit, .truckKit: return true
	default: return false
	}
}

struct VehicleCheck {
	var title: String
	var lines: [String]
	var oks: [Bool]
	var ready: Bool
	var hint: String
}

/// A spot where the held part could go, in world coordinates (top-left of the cell)
struct GhostCell {
	var x: Double
	var y: Double
	var ok: Bool
	var ang: Double = 0
}

extension Game {
	// MARK: kits

	/// Where a kit would land if placed at the aim point: (left tile x, bottom tile y, fits).
	/// Tries a few spots around the aim so small bumps, plants or trees don't block it.
	func kitPlacement(_ g: Gadget, _ ax: Double, _ ay: Double) -> (Int, Int, Bool) {
		let layout: [KitPart] = kitLayout(g)
		var w: Int = 1
		var h: Int = 1
		for k in layout { w = max(w, k.dx + 1); h = max(h, k.dy + 1) }
		let baseLeft: Int = Int(floor(ax)) - w / 2
		let shifts: [Int] = [0, 1, -1, 2, -2, 3, -3]
		var firstLeft: Int = baseLeft
		var firstBottom: Int = Int(floor(ay))
		var firstSet: Bool = false
		for sx in shifts {
			let left: Int = baseLeft + sx
			// drop down onto the ground (or the water surface) below the aim point
			var bottom: Int = Int(floor(ay))
			var n: Int = 0
			while n < 10 && !kitSupport(left, w, bottom + 1) {
				bottom += 1
				n += 1
			}
			if !firstSet {
				firstSet = true
				firstLeft = left
				firstBottom = bottom
			}
			var lift: Int = 0
			while lift <= 3 {
				let by: Int = bottom - lift
				if kitFits(layout, left, by, h) { return (left, by, true) }
				lift += 1
			}
		}
		return (firstLeft, firstBottom, false)
	}

	/// Something to rest on under any column of the kit
	func kitSupport(_ left: Int, _ w: Int, _ y: Int) -> Bool {
		var x: Int = left
		while x < left + w {
			let t: Tile = world.tile(x, y)
			if t.solid || t.liquid || t == .platform { return true }
			x += 1
		}
		return false
	}

	func kitFits(_ layout: [KitPart], _ left: Int, _ bottom: Int, _ h: Int) -> Bool {
		for k in layout {
			let tx: Int = left + k.dx
			let ty: Int = bottom - (h - 1) + k.dy
			if world.solid(tx, ty) { return false }
		}
		return true
	}

	func placeKit(_ g: Gadget) {
		let layout: [KitPart] = kitLayout(g)
		if layout.isEmpty { return }
		if !inReach(aimX, aimY) {
			say("Tap closer to you to place it.", 1.5)
			return
		}
		let pl: (Int, Int, Bool) = kitPlacement(g, aimX, aimY)
		if !pl.2 {
			say("Not enough room here. Find open, flat ground (or water for a boat).", 2.5)
			return
		}
		var h: Int = 1
		for k in layout { h = max(h, k.dy + 1) }
		let v: Vehicle = Vehicle(id: newID(), first: layout[0].p, x: 0, y: 0)
		v.parts.removeAll()
		for k in layout { v.parts[PartCell(dx: k.dx, dy: k.dy)] = k.p }
		v.recompute(keepAnchor: false)
		v.placeBox(left: Double(pl.0), bottom: Double(pl.1 + 1))
		_ = h
		v.kit = g.rawValue
		if v.engines > 0 || v.jets > 0 || v.burners > 0 { v.fuel = min(v.fuelCapacity, 40.0) }
		vehicles.append(v)
		if !isCreative { inv.removeAt(sel, 1) }
		useCD = 0.3
		swingT = 0.15
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xFFF0A0, 10, 3.0, 0.5, 6)
		say("Placed! Walk up to it and press DRIVE.", 3.0)
		bumpHUD()
	}

	// MARK: finding vehicles

	func nearestVehicle(_ maxDist: Double) -> Vehicle? {
		var best: Vehicle? = nil
		var bd: Double = maxDist
		for v in vehicles {
			let dx: Double = abs(v.b.x - pb.x) - v.b.w * 0.5
			let dy: Double = abs((v.b.y - v.b.h * 0.5) - (pb.y - pb.h * 0.5)) - v.b.h * 0.5
			let d: Double = max(0, max(dx, dy))
			if d <= bd {
				bd = d
				best = v
			}
		}
		return best
	}

	var holdingVehicleThing: Bool {
		guard let it = heldItem else { return false }
		switch it {
		case .part: return true
		case .gadget(let g): return g == .wrench || g == .assembler || isKit(g)
		case .block: return vehicleBuild
		default: return false
		}
	}

	/// The vehicle the help box talks about (nil = no box)
	var vehicleHelpTarget: Vehicle? {
		if inVehicle != nil || dead { return nil }
		if holdingVehicleThing { return nearestVehicle(10) }
		return nearestVehicle(2.5)
	}

	/// The vehicle the DRIVE / PACK UP buttons act on
	var vehicleNearby: Vehicle? {
		if inVehicle != nil || mounted != nil || dead { return nil }
		return nearestVehicle(2.0)
	}

	// MARK: attaching parts

	/// Why a part can't go in a cell (nil = it can)
	func attachProblem(_ v: Vehicle, _ c: PartCell, _ p: PartType) -> String? {
		if v.parts[c] != nil { return "That spot is taken." }
		if !v.hasNeighbor(c) { return "Parts must touch the vehicle." }
		// any part goes anywhere it touches: how well it works there is physics (see partNote)
		let wp: (Double, Double) = v.cellPos(c)
		if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
			// a part under a vehicle that sits on the ground: lift the vehicle one block to make room
			if c.dy > v.maxY && canLift(v, c) { return nil }
			return "Something is in the way."
		}
		return nil
	}

	/// How a part will work where it has just been put, when that is not the usual way (said after
	/// attaching it; nil when there is nothing to say)
	func partNote(_ v: Vehicle, _ c: PartCell, _ p: PartType) -> String? {
		if p == .rotor {
			let room: Double = v.rotorRoom[c] ?? 1.0
			if room < 0.99 { return joinText("Its blades have ", String(Int((room * 100).rounded())), "% of their room: it lifts that much.") }
		}
		if v.boxed.contains(c) {
			if isDrill(p) { return "Boxed in: it bores once one side is open." }
			if p == .cannon || p == .autoGun { return "Boxed in: it fires once one side is open." }
			return "Boxed in on both sides: it pushes once one side is open."
		}
		if isWheelPart(p) && v.parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return "A wheel drives wherever it touches the ground (or a wall)." }
		if p == .steering, let seat = seatCell(v), abs(seat.dx - c.dx) + abs(seat.dy - c.dy) > 1 { return "It steers from any seat on the vehicle." }
		return nil
	}

	/// True if the whole vehicle (plus the new cell) would fit one block higher
	func canLift(_ v: Vehicle, _ extra: PartCell) -> Bool {
		var cells: [PartCell] = Array(v.parts.keys)
		cells.append(extra)
		for c in cells {
			let wp: (Double, Double) = v.cellPos(c)
			let y: Double = wp.1 - 1.0
			if world.boxSolid(wp.0 + 0.02, y + 0.02, wp.0 + 0.98, y + 0.98) { return false }
		}
		return true
	}

	/// Lifts the vehicle one block if the new cell is buried in the ground
	func liftIfBuried(_ v: Vehicle, _ c: PartCell) {
		let wp: (Double, Double) = v.cellPos(c)
		if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
			v.py -= 1.0
			v.vy = 0
			v.updateBox()
		}
	}

	/// Every free cell around a vehicle where the part would fit
	func attachSpots(_ v: Vehicle, _ p: PartType) -> [PartCell] {
		var out: [PartCell] = []
		var seen: Set<PartCell> = []
		for (c, _) in v.parts {
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy),
								 PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
			for k in n {
				if seen.contains(k) || v.parts[k] != nil { continue }
				seen.insert(k)
				if attachProblem(v, k, p) == nil { out.append(k) }
			}
		}
		return out
	}

	/// Outlines drawn while holding a part (green = can attach here) or a kit (its footprint)
	func vehicleGhosts() -> [GhostCell] {
		guard let it = heldItem, inVehicle == nil, !dead else { return [] }
		var out: [GhostCell] = []
		switch it {
		case .part(let p):
			if let v = nearestVehicle(10) {
				for c in attachSpots(v, p) {
					let wp: (Double, Double) = v.cellPos(c)
					out.append(GhostCell(x: wp.0, y: wp.1, ok: true, ang: v.angle))
				}
			}
		case .block(let t):
			// with ON VEHICLE: where the block can go on the nearest vehicle
			if vehicleBuild, let v = nearestVehicle(8) {
				var part: PartType = .block
				if t.isMod, let d = ModRuntime.shared.blockDef(t), let pp = d.vehRole.part { part = pp }
				for c in attachSpots(v, part) {
					let wp: (Double, Double) = v.cellPos(c)
					out.append(GhostCell(x: wp.0, y: wp.1, ok: true, ang: v.angle))
				}
			}
		case .gadget(let g):
			if isKit(g) && aimValid {
				let pl: (Int, Int, Bool) = kitPlacement(g, aimX, aimY)
				let layout: [KitPart] = kitLayout(g)
				var h: Int = 1
				for k in layout { h = max(h, k.dy + 1) }
				let ok: Bool = pl.2 && inReach(aimX, aimY)
				for k in layout {
					out.append(GhostCell(x: Double(pl.0 + k.dx), y: Double(pl.1 - (h - 1) + k.dy), ok: ok))
				}
			}
		default:
			break
		}
		return out
	}

	// MARK: checklist

	func vehicleCheck(_ v: Vehicle) -> VehicleCheck {
		if v.aero || v.tracks > 0 || v.cannons + v.guns > 0 || v.hasCockpit { return flightCheck(v) }
		var lines: [String] = []
		var oks: [Bool] = []
		var hulls: Int = 0
		for (_, t) in v.parts where t == .hull { hulls += 1 }
		let isBoat: Bool = hulls > 0 && v.wheels < 2
		func add(_ ok: Bool, _ s: String) {
			lines.append(s)
			oks.append(ok)
		}
		add(v.hasSeat, "Seat")
		add(v.hasSteering, "Steering wheel (next to the seat)")
		var hint: String = ""
		if isBoat {
			let floats: Bool = v.buoyancy >= v.mass * 0.8
			add(floats, "Enough hull floats to stay up")
			let motor: Bool = v.engines > 0 && v.propellers > 0
			add(motor || v.paddles > 0, "Paddle, or engine + propeller")
			if v.engines > 0 { add(v.fuel > 0.5, fuelLine(v)) }
			hint = "Boats only move in water."
		} else {
			let wn: Int = v.wheels
			add(v.wheels >= 2, "2 wheels under the frame (\(wn)/2)")
			add(v.engines > 0, "Engine")
			add(v.fuel > 0.5, fuelLine(v))
			hint = "Refuel: hold coal or wood and tap the vehicle."
		}
		var ready: Bool = true
		for o in oks where !o { ready = false }
		let title: String = isBoat ? (v.engines > 0 ? "MOTORBOAT" : "BOAT") : vehicleKindName(v)
		return VehicleCheck(title: title, lines: lines, oks: oks, ready: ready, hint: hint)
	}

	func fuelLine(_ v: Vehicle) -> String {
		let a: Int = Int(v.fuel)
		let b: Int = Int(v.fuelCapacity)
		return "Fuel \(a)/\(b)"
	}

	/// Changes whenever the help box or vehicle buttons would look different
	func vehicleHelpKey() -> Int {
		var k: Int = 0
		if let v = vehicleHelpTarget {
			k = v.id &* 31 &+ v.parts.count &* 7 &+ Int(v.fuel) &+ 1
		}
		if let v = vehicleNearby { k = k &* 13 &+ v.id &+ 5 }
		if holdingVehicleThing { k = k &* 3 &+ 1 }
		return k
	}

	// MARK: drive / pack up

	func driveNearby() {
		guard let v = vehicleNearby else { return }
		mountVehicle(v)
	}

	func packUpVehicle() {
		guard let v = vehicleNearby else { return }
		if v.rider { dismount() }
		var back: [Item] = []
		if v.kit >= 0, let g = Gadget(rawValue: v.kit), kitMatches(v, g) {
			back.append(.gadget(g))
		} else {
			for (c, t) in v.parts { back.append(vehicleCellItem(VCell(cell: c, type: t, tile: v.blocks[c]))) }
		}
		// what the vehicle carried comes back too
		for c in v.parts.keys where vehicleStores(v, c) {
			let k: IntPair = cargoSpot(v, c)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { giveStack(st) }
		}
		for it in back { giveItem(it, 1) }
		vehicles.removeAll { $0.id == v.id }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xC8C8C8, 8, 3.0, 0.4, 6)
		say("Packed up. Place it again any time.", 2.0)
		bumpHUD()
	}

	func kitMatches(_ v: Vehicle, _ g: Gadget) -> Bool {
		for layout in [kitLayout(g)] + legacyKitLayouts(g) {
			if layout.count != v.parts.count { continue }
			var same: Bool = true
			for k in layout where v.parts[PartCell(dx: k.dx, dy: k.dy)] != k.p { same = false }
			if same { return true }
		}
		return false
	}
}
