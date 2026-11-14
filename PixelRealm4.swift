// PIXEL REALM v2, part 4 of 5: bosses, the portal and map, saving, potions and mutation, infusions, the exosuit, building (furniture, stairs,
// lifts), block physics, rails and trains, Mod Creator+ (game content changes, ore controls, sprite tools, custom
// infusions, boss phases and summoning, custom dimensions, the Logic Studio, rules, weather, machines, vehicles and
// themes in mods), the HUD and the panels.
// The game is five files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm5.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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
	/// appended: a signal channel turns on
	case channelOn

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
		case .channelOn: return "When a signal channel turns on"
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
	/// appended: turn a signal channel on or off
	case setChannel
}

/// A reporter (a value a block reads)
enum LEOp: Int, Codable, CaseIterable {
	case num, variable, param, random, add, sub, mul, div, mod, lt, gt, eq, and, or, not
	case playerHP, playerMaxHP, selfHP, selfHPPct, distance, timeOfDay, isNight, itemCount
	case playerX, playerY, selfX, selfY, nearby, inDim, inBiome, raining
	/// appended: whether a signal channel is on
	case channel
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
		LSpec(op: .setChannel, cat: .world, title: "set a signal channel", fields: [LField(kind: .number, slot: 0, label: "channel", lo: 1, hi: 8, def: 1),
																					LField(kind: .number, slot: 1, label: "on (1) or off (0)", lo: 0, hi: 1, def: 1)]),
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
		case .channel: return "signal channel is on"
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
			if e == .channelOn && Int(d.ev.rounded()) != Int(number.rounded()) { continue }
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
		case .channel: v = channelIsOn(Int(e.v.rounded())) ? 1 : 0
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
		case .setChannel:
			setLogicChannel(Int(n.a.rounded()), n.b >= 0.5)
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
			if let v = game.drivenVehicle { vehicleReadout(v) }
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
			if game.drivenVehicle != nil { vehicleButtons }
			if game.vehicleNearby != nil {
				SmallButton(title: "DRIVE", color: Color(ui: 0x4E8A3E)) { game.driveNearby() }
				SmallButton(title: "PACK UP", color: Color(ui: 0x6A5A2A)) { game.packUpVehicle() }
			}
			if game.mounted != nil || game.inVehicle != nil {
				SmallButton(title: "DISMOUNT", color: Color(ui: 0xA03030)) { game.dismount() }
			}
			if game.remoteID != 0 {
				SmallButton(title: "LET GO", color: Color(ui: 0xA03030)) { game.endRemote("Remote off.") }
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
		if let v = game.drivenVehicle, !v.joints.isEmpty { jointButtonRow }
		if let v = game.drivenVehicle, v.autopilots > 0 {
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
