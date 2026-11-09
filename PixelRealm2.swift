// PIXEL REALM v2, part 2 of 4: creature AI, spawning, combat and damage, bosses, vehicles and ships, the portal and map, saving,
// helpers, walls and doors, Sparkworks (power), the Mod Creator's data, checks and runtime, potions and mutation, infusions,
// the exosuit, building (furniture, stairs, lifts) and block physics.
// The game is four files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm4.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). All art is generated in code.

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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
		// a parked vehicle you can stand on (only while it is roughly level)
		for v in vehicles where !v.rider && v.upright {
			out.append(Deck(x0: v.b.x - v.b.w * 0.5, x1: v.b.x + v.b.w * 0.5, y: v.b.y - v.b.h, vx: v.vx, id: 1_000_000 + v.id))
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
		world.moveBody(&m.b, dt, stepUp: d.flying ? 0 : stepUp, dropThrough: false, decks: decksCache)
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
		if place == .surface || place == .ocean { return [3, 6, 10][d] }
		return [6, 9, 12][d]
	}

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
					if predators >= 3 { continue }
				} else {
					if hostile >= cap { capped = true; continue }
					if !monsterBlock.isEmpty { continue }
				}
			} else if r.kind == .fish || (r.slot >= 0 && r.place == .ocean) {
				if aquatic >= 9 { continue }
			} else {
				if passive >= 9 { continue }
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
		var d: Double = dmg
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
				b.x += b.vx * dt
				b.y += b.vy * dt
			} else {
				world.moveBody(&b, dt, stepUp: 0, dropThrough: false, decks: decksCache)
				if b.inWater { b.vy = min(b.vy, 1.5); b.vx *= 0.9 }
			}
			d.x = b.x
			d.y = b.y
			d.vx = b.vx
			d.vy = b.vy
			d.onGround = b.onGround
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

	/// Sand with nothing under it falls; it hurts whatever it lands on
	func checkFalling(_ x: Int, _ y: Int) {
		var yy: Int = y
		var n: Int = 0
		while n < 16 && world.tile(x, yy) == .sand {
			let below: Tile = world.tile(x, yy + 1)
			if below.supportsThings || below.isPlatform { break }
			world.set(x, yy, .air)
			fallingBlocks.append(FallingBlock(x: Double(x) + 0.5, y: Double(yy) + 1.0, vy: 0, tile: .sand, uid: newID()))
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
	/// the cell it belongs to (a hard crash damages that part)
	var cx: Int = 0
	var cy: Int = 0
}

/// Water a part displaces when fully under (in tiles of water). Every part floats a little; hulls a
/// lot. Parts without displacement (the old model) made engines and propellers drag boats under.
func partDisplacement(_ p: PartType) -> Double {
	switch p {
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

/// Per-frame contact summary gathered over the fixed steps
struct VStepStats {
	var anyHits: Int = 0
	var wheelHits: Int = 0
	var wet: Double = 0
	var nearWater: Bool = false
	var rammed: [(Int, Int)] = []
	/// the hardest hit each part took (speed into the ground beyond what it shrugs off)
	var crash: [PartCell: Double] = [:]
}

extension Game {
	func updateVehicles(_ dt: Double) {
		let t0: Double = perfNow()
		for v in vehicles { stepVehicle(v, dt) }
		separateVehicles()
		// weapons, the autopilot, turns and damage (also for a vehicle at rest)
		for v in vehicles { vehicleExtras(v, dt) }
		flushVehicleBlasts()
		if vehicles.contains(where: { $0.parts.isEmpty }) { vehicles.removeAll { $0.parts.isEmpty } }
		Perf.shared.physMs = Perf.smooth(Perf.shared.physMs, perfNow() - t0)
	}

	func seatCell(_ v: Vehicle) -> PartCell? {
		for (c, t) in v.parts where t == .seat || t == .cockpit { return c }
		return nil
	}

	/// Collision samples: the four corners and edge midpoints of square parts; a ring for wheels.
	/// Hull samples follow the visible hull (its art leaves the top quarter of the cell empty).
	func vehicleSamples(_ v: Vehicle) -> [VSample] {
		var out: [VSample] = []
		out.reserveCapacity(v.parts.count * 8)
		// on a boat every part slides like a hull (engine and propeller included)
		let boat: Bool = v.buoyancy > 0 && v.wheels < 2
		for (c, t) in v.parts {
			let x0: Double = Double(c.dx)
			let y0: Double = Double(c.dy)
			if isWheelPart(t) {
				var k: Int = 0
				let tr: Bool = t == .track
				while k < 10 {
					let a: Double = Double(k) / 10.0 * 2.0 * Double.pi
					out.append(VSample(lx: x0 + 0.5 + cos(a) * 0.47, ly: y0 + 0.5 + sin(a) * 0.47, wheel: true, ramp: true, hull: false, track: tr, cx: c.dx, cy: c.dy))
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
			if world.tile(tx, y) == .water {
				var top: Int = y
				if y == start {
					// already under water at the part's top: find the surface above
					var k: Int = 0
					while k < 6 && world.tile(tx, top - 1) == .water { top -= 1; k += 1 }
				}
				return clampD(bottom - Double(top), 0, 1)
			}
			y += 1
		}
		return 0
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

	func stepVehicle(_ v: Vehicle, _ dt: Double) {
		if !vehicleAreaLoaded(v) { return }
		let throttle: Double = v.rider || v.auto == 2 ? v.throttle : 0
		let airBusy: Bool = v.aero && (abs(v.pitch) > 0.05 || v.heat > 0.02 || v.collective > 0.02 || v.turnT > 0)
		if v.asleep && abs(throttle) < 0.05 && !v.drilling && !airBusy {
			// resting vehicles cost nothing until something wakes them
			if world.boxSolid(v.b.left + 0.05, v.b.y + 0.02, v.b.right - 0.05, v.b.y + 0.2) || v.submerged > 0 { return }
		}
		v.asleep = false
		let samples: [VSample] = vehicleSamples(v)
		// fixed steps: the same motion whatever the frame rate (leftover time carries to the next frame)
		v.physAccum += min(dt, 0.1)
		var n: Int = Int(v.physAccum / vehicleStep)
		if n > 12 { n = 12; v.physAccum = 0 } else { v.physAccum -= Double(n) * vehicleStep }
		var stats = VStepStats()
		var k: Int = 0
		while k < n {
			// split a step when moving fast, so no sample moves more than ~0.2 blocks at once
			let fast: Double = v.speed + abs(v.angVel) * 3.0
			let split: Int = fast * vehicleStep > 0.2 ? 2 : 1
			var s: Int = 0
			while s < split {
				vehicleSubstep(v, vehicleStep / Double(split), samples, throttle, &stats)
				s += 1
			}
			k += 1
		}
		for r in stats.rammed where world.tile(r.0, r.1).solid {
			breakTile(r.0, r.1, v.rider)
			addShake(0.25)
			v.vx *= 0.6
		}
		if n > 0 {
			v.wheelContacts = stats.wheelHits
			v.contacts = stats.anyHits
			v.submerged = stats.wet / Double(n)
		}
		if !stats.crash.isEmpty { crashDamage(v, stats.crash) }
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
		let calm: Bool = v.speed < 0.08 && abs(v.angVel) < 0.03 && abs(throttle) < 0.05 && !v.drilling && !airBusy
		if calm && (v.contacts > 0 || v.submerged > 0) {
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
	func vehicleSubstep(_ v: Vehicle, _ h: Double, _ samples: [VSample], _ throttle: Double, _ stats: inout VStepStats) {
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
			let disp: Double = cellDisplacement(v, cell, t)
			let rx: Double = wx - v.px
			let ry: Double = wy - v.py
			let pvx: Double = v.vx - v.angVel * ry
			let pvy: Double = v.vy + v.angVel * rx
			let fx: Double = -pvx * (0.35 + 0.3 * disp) * f
			let fy: Double = -gravityG * disp * f - pvy * 4.5 * disp * f
			v.vx += fx * invM * h
			v.vy += fy * invM * h
			v.angVel += (rx * fy - ry * fx) * invI * h
		}
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
			var thrust: Double = 0
			var vmax: Double = 0
			if v.engines > 0 && v.propellers > 0 && hasFuel {
				thrust = Double(v.engines) * 16.0
				vmax = min(10.0, 5.0 + 2.0 * Double(v.engines))
			} else if v.paddles > 0 {
				thrust = Double(v.paddles) * 5.5
				vmax = 3.4
			}
			if sub <= 0 { thrust *= 0.45 }
			// touching the bottom: thrust fades as the hull comes out of the water, so a boat runs
			// aground at the shoreline instead of motoring up the beach (reversing off still works)
			if stats.anyHits > 0 && throttle * v.vx >= 0 {
				let landward: Bool = submergedFraction(v.px + Double(throttle > 0 ? 1 : -1) * (v.b.w * 0.5 + 0.5), v.py) <= 0
				if landward { thrust *= clampD((hullDepth - 0.12) / 0.25, 0, 1) }
			}
			if !(abs(v.vx) > vmax && v.vx * throttle > 0) { v.vx += thrust * throttle * invM * h }
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
		for smp in samples {
			let lx: Double = smp.lx - v.comX
			let ly: Double = smp.ly - v.comY
			let rx: Double = lx * c2 - ly * s2
			let ry: Double = lx * s2 + ly * c2
			let wx: Double = v.px + rx
			let wy: Double = v.py + ry
			guard let pen = penetration(wx, wy, wheel: smp.ramp) else { continue }
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
			if vn < 0 {
				let rn: Double = rx * ny - ry * nx
				let kn: Double = invM + rn * rn * invI
				let jn: Double = -(1.0 + 0.04) * vn / kn
				v.vx += jn * nx * invM
				v.vy += jn * ny * invM
				v.angVel += rn * jn * invI
				// friction along the surface; wheels roll unless braking, hulls slide on sand and stone
				let tx: Double = -ny
				let ty: Double = nx
				let pvx2: Double = v.vx - v.angVel * ry
				let pvy2: Double = v.vy + v.angVel * rx
				let vt: Double = pvx2 * tx + pvy2 * ty
				let rt: Double = rx * ty - ry * tx
				let kt: Double = invM + rt * rt * invI
				// a boat's parts slide on sand and stone, very easily while it is still partly afloat (so it
				// eases off a beach under its own power); car bodies grip
				var mu: Double = smp.hull ? (sub > 0 ? 0.05 : 0.22) : 0.7
				if smp.wheel {
					// an aircraft's wheels roll free on the throttle and brake without it
					let braking: Bool = abs(throttle) < 0.1 || (throttle * vt < 0 && !v.aero)
					mu = braking ? (v.rider ? 0.9 : 0.25) : (v.aero ? 0.02 : 0.06)
					if smp.track { mu = braking ? (v.rider ? 1.1 : 0.4) : 0.14 }
				}
				var jt: Double = -vt / kt
				let lim: Double = mu * jn
				jt = clampD(jt, -lim, lim)
				v.vx += jt * tx * invM
				v.vy += jt * ty * invM
				v.angVel += rt * jt * invI
			}
			let d: Double = min(0.12, max(0, depth - 0.01))
			if ny < -0.5 { outUp = max(outUp, d) } else if ny > 0.5 { outDown = max(outDown, d) }
			else if nx < -0.5 { outLeft = max(outLeft, d) } else { outRight = max(outRight, d) }
		}
		v.px += (outRight - outLeft) * 0.8
		v.py += (outDown - outUp) * 0.8
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
			let vmax: Double = min(17.0, 6.5 + 3.0 * Double(v.engines)) * (1.0 - 0.45 * trackShare)
			let along: Double = v.vx * c2 + v.vy * s2
			if !(abs(along) > vmax && along * throttle > 0) {
				// heavier builds accelerate and climb slower; more engines help, and offroad wheels pull
				// harder (their extra weight is the price)
				let grip: Double = 1.0 + 0.7 * Double(v.offroadWheels) / Double(max(1, v.wheels)) + 1.4 * trackShare
				let power: Double = v.enginePower * 135.0 * grip * min(1.0, Double(stepWheel) / 4.0 + 0.5) * groundShare(v)
				v.vx += c2 * power * throttle * invM * h
				v.vy += s2 * power * throttle * invM * h
			}
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
		// stability limits
		v.vx = clampD(v.vx, -30, 30)
		v.vy = clampD(v.vy, -30, 30)
		v.angVel = clampD(v.angVel, -12, 12)
	}

	/// Vehicles shove each other apart instead of overlapping
	func separateVehicles() {
		if vehicles.count < 2 { return }
		for i in 0..<vehicles.count {
			for j in (i + 1)..<vehicles.count {
				let a: Vehicle = vehicles[i]
				let b: Vehicle = vehicles[j]
				let ox: Double = min(a.b.right, b.b.right) - max(a.b.left, b.b.left)
				let oy: Double = min(a.b.y, b.b.y) - max(a.b.top, b.b.top)
				if ox <= 0 || oy <= 0 { continue }
				let dirx: Double = a.b.x < b.b.x ? -1.0 : 1.0
				let tot: Double = a.mass + b.mass
				let push: Double = min(ox, 0.3)
				a.px += dirx * push * (b.mass / tot)
				b.px -= dirx * push * (a.mass / tot)
				let rel: Double = (a.vx - b.vx) * -dirx
				if rel < 0 {
					// exchange momentum along x
					let j: Double = rel * a.mass * b.mass / tot * 1.1
					a.vx += dirx * j / a.mass * -1.0
					b.vx -= dirx * j / b.mass * -1.0
				}
				a.asleep = false
				b.asleep = false
				a.updateBox()
				b.updateBox()
			}
		}
	}

	/// Hitting creatures (or the player) at speed hurts them according to speed and weight
	func vehicleImpacts(_ v: Vehicle, _ dt: Double) {
		let sp: Double = v.speed
		if sp < 4.0 { return }
		let src: DamageSource = v.rider ? .player : .environment
		let nudge: Double = 0.15
		for m in mobsNear(v.b.left - 1, v.b.right + 1) {
			if m.hp <= 0 || m.tame { continue }
			if m.b.right < v.b.left - nudge || m.b.left > v.b.right + nudge || m.b.y < v.b.top || m.b.top > v.b.y { continue }
			// must actually touch a part, not just the box
			let cell: PartCell = v.cellAt(m.b.x, m.b.cy)
			var touching: Bool = v.parts[cell] != nil
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
				// the creature's weight slows the vehicle
				let mm: Double = m.def.w * m.def.h * 0.8
				v.vx *= v.mass / (v.mass + mm * 0.5)
				addShake(0.12)
			}
		}
		if !v.rider && !dead && inVehicle !== v {
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
		for (cell, d) in v.drillDir {
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
			} else if v.speed < 2.5 {
				dismount()
			}
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
		if let t = v.parts[c], t == .seat || t == .steering || t == .cockpit {
			mountVehicle(v)
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
		else if !v.hasSteering { info += ". Needs a steering wheel next to the seat." }
		else if v.buoyancy > 0 && !v.canSail && v.wheels < 2 { info += ". Add engine + propeller (or a paddle)." }
		else if v.wheels >= 2 && v.engines == 0 { info += ". Add an engine." }
		else { info += ". Tap the seat to drive." }
		say(info, 3.5)
	}

	func mountVehicle(_ v: Vehicle) {
		if !v.hasSeat || !v.hasSteering {
			say(v.hasSeat ? "Add a steering wheel next to the seat." : "Add a seat or a cockpit first.", 2.5)
			return
		}
		if mounted != nil { dismount() }
		inVehicle = v
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
			cs.append(ChunkSave(dim: cur, cx: k, data: Data(World.rle(tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls)), wires: c.wireCount == 0 ? nil : Data(World.rle(c.wires)), built: c.built.isEmpty ? nil : Data(World.rle(c.built))))
		}
		for d in 0..<world.parked.count {
			for (k, c) in world.parked[d] {
				if d == cur && world.chunks[k] != nil { continue }
				cs.append(ChunkSave(dim: d, cx: k, data: Data(World.rle(c.tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls)), wires: c.wireCount == 0 ? nil : Data(World.rle(c.wires)), built: c.built.isEmpty ? nil : Data(World.rle(c.built))))
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
		return SaveData(meta: meta, settings: settings, px: px, py: py, hp: max(1, hp), maxHP: maxHP, hunger: hunger, timeOfDay: timeOfDay, kills: kills, spawnX: spawnX, spawnY: spawnY, inv: inv, sel: sel, defeated: Array(defeated), gotMap: gotMap, portalOpened: portalOpened, chests: chestList, chunks: cs, vehicles: vs, pets: pets, rex: rs, nextID: nextID, journal: journal, weather: weather, bodyCold: bodyCold, power: powerSave(), mods: mi, effects: effectsSave(), mutants: mutantSaves(), suit: suit.isEmpty ? nil : suit, bosses: bossSaves(), dimReturn: dimReturn, logicVars: logicVars.isEmpty ? nil : logicVars, lifts: ls.isEmpty ? nil : ls)
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
		// in an armed vehicle the attack stick aims and fires its guns
		if let v = inVehicle, v.cannons + v.guns > 0 {
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
		let suitPart: Int = suitLook()?.hashValue ?? 0
		return (h * 100 + c * 10 + l + settings.hair * 1000 + settings.scarf * 10000) &+ suitPart
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

// ===== p24_painter =====

// MARK: - Fast terrain section painter
// Paints a 16x16-tile section into a premultiplied ARGB pixel buffer using raw pointers,
// so it stays quick in Playgrounds' debug builds. The UI turns the result into an image.

/// Premultiplies non-premultiplied ARGB pixels in place (only pixels with partial alpha change).
func premultiplyARGB(_ px: inout [UInt32]) {
	let n: Int = px.count
	px.withUnsafeMutableBufferPointer { bp in
		guard let p = bp.baseAddress else { return }
		var i: Int = 0
		while i < n {
			let c: UInt32 = p[i]
			let a: UInt32 = c >> 24
			if a == 0 {
				p[i] = 0
			} else if a != 255 {
				let r: UInt32 = ((c >> 16) & 255) * a / 255
				let g: UInt32 = ((c >> 8) & 255) * a / 255
				let b: UInt32 = (c & 255) * a / 255
				p[i] = (a << 24) | (r << 16) | (g << 8) | b
			}
			i += 1
		}
	}
}

final class SectionPainter: @unchecked Sendable {
	static let shared: SectionPainter = SectionPainter()

	let tileCount: Int
	/// 8x8 art for every tile, by raw value (64 pixels each)
	var tilePx: [UInt32]
	/// 0 = fully transparent, 1 = fully opaque, 2 = mixed alpha
	var tileKind: [Int]
	/// darkened 8x8 backdrop walls, by wall kind - 1
	var wallPx: [UInt32]
	var wallBufs: [PixelBuf]
	var tileBufs: [PixelBuf]
	let wallCount: Int

	init() {
		var tb: [PixelBuf] = []
		for t in Tile.allCases { tb.append(tileBuf(t)) }
		tileBufs = tb
		tileCount = tb.count
		var px: [UInt32] = [UInt32](repeating: 0, count: 256 * 64)
		var kinds: [Int] = [Int](repeating: 0, count: 256)
		for (i, b) in tb.enumerated() {
			var allClear: Bool = true
			var allSolid: Bool = true
			for k in 0..<64 {
				let c: UInt32 = k < b.px.count ? b.px[k] : 0
				px[i * 64 + k] = c
				let a: UInt32 = c >> 24
				if a != 0 { allClear = false }
				if a != 255 { allSolid = false }
			}
			kinds[i] = allClear ? 0 : (allSolid ? 1 : 2)
		}
		tilePx = px
		tileKind = kinds
		let srcs: [Tile] = [.dirt, .stone, .deepRock, .ashStone, .planks, .brick, .sandstone]
		var ws: [PixelBuf] = []
		var wp: [UInt32] = []
		for (k, s) in srcs.enumerated() {
			var w: PixelBuf = tileBuf(s)
			let f: Double = k >= 4 ? 0.55 : 0.42
			for i in 0..<w.px.count {
				let c: UInt32 = w.px[i]
				w.px[i] = 0xFF000000 | shadeRGB(c & 0xFFFFFF, f)
			}
			ws.append(w)
			for i in 0..<64 { wp.append(i < w.px.count ? w.px[i] : 0xFF000000) }
		}
		// walls made from any block (wall value 8 + its tile number): its art, darkened
		while wp.count < (blockWallBase - 1) * 64 { wp.append(0) }
		for raw in 0..<tb.count {
			let b: PixelBuf = tb[raw]
			for k in 0..<64 {
				let c: UInt32 = k < b.px.count ? b.px[k] : 0
				let a: UInt32 = c >> 24
				wp.append(a == 0 ? 0 : (c & 0xFF000000) | shadeRGB(c & 0xFFFFFF, 0.5))
			}
		}
		wallBufs = ws
		wallPx = wp
		wallCount = blockWallBase - 1 + tb.count
	}

	/// Redraws the art of the tiles reserved for mods (their meaning changes with a world's mods)
	func refreshModTiles() {
		let base: Int = Int(Tile.modBase)
		for i in 0..<ModLimits.blockSlots {
			let raw: Int = base + i
			guard raw < tileBufs.count, let t = Tile(rawValue: UInt8(raw)) else { continue }
			let b: PixelBuf = tileBuf(t)
			tileBufs[raw] = b
			var allClear: Bool = true
			var allSolid: Bool = true
			let wb: Int = (blockWallBase - 1 + raw) * 64
			for k in 0..<64 {
				let c: UInt32 = k < b.px.count ? b.px[k] : 0
				tilePx[raw * 64 + k] = c
				if wb + k < wallPx.count { wallPx[wb + k] = (c >> 24) == 0 ? 0 : (c & 0xFF000000) | shadeRGB(c & 0xFFFFFF, 0.5) }
				let a: UInt32 = c >> 24
				if a != 0 { allClear = false }
				if a != 255 { allSolid = false }
			}
			tileKind[raw] = allClear ? 0 : (allSolid ? 1 : 2)
		}
	}

	/// Paints section `sy` (rows sy*16 ..< sy*16+16) of a chunk. Returns 128x128 premultiplied ARGB.
	func paint(_ world: World, _ ch: Chunk, _ sy: Int) -> [UInt32] {
		let W: Int = chunkW * 8
		let Hh: Int = 16 * 8
		var buf: [UInt32] = [UInt32](repeating: 0, count: W * Hh)
		let H: Int = ch.H
		let y0: Int = sy * 16
		let back: [UInt8] = world.backdrop(ch)
		let opT: [Bool] = Tile.opaqueTable
		// edge shading follows "solid or trunk", so trees look exactly as they did when trunks had collision
		let soT: [Bool] = Tile.supportTable
		let wc: Int = wallCount
		buf.withUnsafeMutableBufferPointer { bb in
			ch.tiles.withUnsafeBufferPointer { tb in
				back.withUnsafeBufferPointer { kb in
					tilePx.withUnsafeBufferPointer { ab in
						tileKind.withUnsafeBufferPointer { kib in
							wallPx.withUnsafeBufferPointer { wb in
								opT.withUnsafeBufferPointer { ob in
									soT.withUnsafeBufferPointer { sb in
										guard let out = bb.baseAddress, let tiles = tb.baseAddress, let backs = kb.baseAddress,
											  let art = ab.baseAddress, let tk = kib.baseAddress, let walls = wb.baseAddress,
											  let opq = ob.baseAddress, let sol = sb.baseAddress else { return }
										var lx: Int = 0
										while lx < chunkW {
											let colBase: Int = lx * H
											let ox: Int = lx * 8
											var ly: Int = 0
											while ly < 16 {
												let y: Int = y0 + ly
												if y < 0 || y >= H { ly += 1; continue }
												let raw: Int = i8(tiles[colBase + y])
												let oy: Int = ly * 8
												let opaque: Bool = opq[raw]
												let wall: Int = i8(backs[colBase + y]) - 1
												if wall >= 0 && wall < wc && !opaque {
													let src: UnsafePointer<UInt32> = walls + wall * 64
													var yy: Int = 0
													while yy < 8 {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
														let s: UnsafePointer<UInt32> = src + yy * 8
														row[0] = s[0]; row[1] = s[1]; row[2] = s[2]; row[3] = s[3]
														row[4] = s[4]; row[5] = s[5]; row[6] = s[6]; row[7] = s[7]
														yy += 1
													}
												}
												if raw == 0 { ly += 1; continue }
												let kind: Int = tk[raw]
												let src: UnsafePointer<UInt32> = art + raw * 64
												if kind == 1 {
													var yy: Int = 0
													while yy < 8 {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
														let s: UnsafePointer<UInt32> = src + yy * 8
														row[0] = s[0]; row[1] = s[1]; row[2] = s[2]; row[3] = s[3]
														row[4] = s[4]; row[5] = s[5]; row[6] = s[6]; row[7] = s[7]
														yy += 1
													}
												} else if kind == 2 {
													var yy: Int = 0
													while yy < 8 {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
														var xx: Int = 0
														while xx < 8 {
															let c: UInt32 = src[yy * 8 + xx]
															let a: UInt32 = c >> 24
															if a == 255 {
																row[xx] = c
															} else if a != 0 {
																let under: UInt32 = row[xx]
																if (under >> 24) == 0 {
																	row[xx] = c
																} else {
																	let f: Double = Double(a) / 255.0
																	row[xx] = 0xFF000000 | mixRGB(under & 0xFFFFFF, c & 0xFFFFFF, f)
																}
															}
															xx += 1
														}
														yy += 1
													}
												}
												// darker rim where a solid block meets open space (easier to read the terrain)
												if sol[raw] && opaque {
													let upOpaque: Bool = y > 0 ? opq[i8(tiles[colBase + y - 1])] : false
													if !upOpaque {
														let row: UnsafeMutablePointer<UInt32> = out + oy * W + ox
														var xx: Int = 0
														while xx < 8 {
															row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 1.12)
															xx += 1
														}
													}
													let dnOpaque: Bool = y + 1 < H ? opq[i8(tiles[colBase + y + 1])] : true
													if !dnOpaque {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + 7) * W + ox
														var xx: Int = 0
														while xx < 8 {
															row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 0.7)
															xx += 1
														}
													}
												}
												ly += 1
											}
											lx += 1
										}
									}
								}
							}
						}
					}
				}
			}
		}
		premultiplyARGB(&buf)
		return buf
	}
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
		if isWheelPart(p) {
			if v.parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil { return "Wheels go directly under another part." }
			if v.parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return "Wheels must be on the bottom." }
		}
		if p == .steering && !v.canAttach(c, p) { return "The steering wheel goes right next to the seat." }
		if (p == .propeller || p == .paddle || p == .airProp || p == .jet || p == .tailRotor) && !v.canAttach(c, p) { return "That goes on an end of the vehicle (open to one side)." }
		if p == .rotor && !v.canAttach(c, p) { return "A rotor goes on top, with nothing above it or beside its blades." }
		if (p == .cannon || p == .autoGun) && !v.canAttach(c, p) { return "A gun needs an open side to fire from." }
		for k in -2...2 where v.parts[PartCell(dx: c.dx + k, dy: c.dy + 1)] == .rotor { return "That is where the rotor blades turn." }
		if !v.canAttach(c, p) { return "Can't attach that there." }
		let wp: (Double, Double) = v.cellPos(c)
		if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
			// a part under a vehicle that sits on the ground: lift the vehicle one block to make room
			if c.dy > v.maxY && canLift(v, c) { return nil }
			return "Something is in the way."
		}
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

// ===== p27_power =====

// MARK: - Sparkworks: power and automation
//
// Power (measured in sparks) runs through power cable from generators to batteries and machines.
// On/off pulses run separately through pulse wire, in two colours (amber and teal) so two circuits can
// cross. Both are an overlay over the tiles, stored per chunk like background walls, so they are saved,
// parked and reloaded with the chunk. Devices are ordinary tiles; their settings and charge live in
// World.devs. Networks are worked out again only when wiring or devices change (World.powerRev).
// Power is shared out four times a second. Pulses step twenty times a second from a queue of changes,
// and every logic part adds at least one step of delay, so a loop can never run away within a frame
// (one that flips too fast burns out for a moment instead).

/// The overlay bits on a cell
enum Wire {
	static let power: UInt8 = 1
	static let pulseA: UInt8 = 2
	static let pulseB: UInt8 = 4
	/// the bit for layer 0 (power), 1 (amber) or 2 (teal)
	static func bit(_ layer: Int) -> UInt8 { return UInt8(1 << layer) }
}

/// What a device does on the networks
enum PowerRole {
	case none, generator, storage, conductor, meter, source, logic, sensor, machine, indicator
}

func powerRole(_ t: Tile) -> PowerRole {
	switch t {
	case .crankGen, .solarPanel, .fuelGen, .waterWheel, .emberDynamo, .windTurbine: return .generator
	case .battery, .accumulator: return .storage
	case .powerSwitch, .breaker: return .conductor
	case .powerMeter: return .meter
	case .lever, .pushButton, .pressurePlate: return .source
	case .pulseTimer, .repeater, .inverter, .logicGate: return .logic
	case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor: return .sensor
	case .gateClosed, .gateOpen, .lampOff, .lampOn, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .exoStation: return .machine
	case .signalLight: return .indicator
	default: return .none
	}
}

/// The two forms of a device (a lamp lit or dark, a gate open or shut) are the same device
func powerFamily(_ t: Tile) -> Tile {
	switch t {
	case .lampOn: return .lampOff
	case .gateOpen: return .gateClosed
	default: return t
	}
}

/// Parts that point a way (their output side; inputs at the back or the sides)
func powerDirectional(_ t: Tile) -> Bool {
	switch t {
	case .pulseTimer, .repeater, .inverter, .logicGate, .autoDrill, .conveyor, .autoCrafter: return true
	default: return false
	}
}

/// Plain tiles that follow a pulse on their cell without needing power: wooden doors open, storm
/// shutters close, a storm siren sounds
func pulseFollower(_ t: Tile) -> Bool {
	return t == .doorClosed || t == .doorOpen || t == .shutterClosed || t == .shutterOpen || t == .stormSiren
}

/// Steps of 90 degrees: 0 right, 1 down, 2 left, 3 up
let sideDX: [Int] = [1, 0, -1, 0]
let sideDY: [Int] = [0, 1, 0, -1]

/// A placed device: its settings and charge (saved), and what the simulation knows of it right now
final class PowerDev {
	let key: ChestKey
	var tile: Tile
	/// facing (the output side for parts that point a way)
	var dir: Int = 0
	/// a setting chosen in its panel (gate type, sensor mode, breaker rating and so on)
	var mode: Int = 0
	/// a number set in its panel (a delay, a period, a range)
	var param: Double = 0
	/// stored energy (batteries, a crank's flywheel) or fuel left in seconds (generators)
	var charge: Double = 0
	/// a lever or switch position, a breaker closed
	var on: Bool = false
	/// a second setting (a trap that hurts the player too, a breaker that has tripped)
	var flag: Bool = false
	/// an auto crafter's recipe
	var item: Int = -1
	// live state (not saved)
	var pnet: Int = -1
	/// pulse nets on its own cell (amber, teal)
	var snets: [Int] = [-1, -1]
	/// pulse nets at each side (right, down, left, up), amber then teal, for parts that point a way
	var ports: [Int] = [-1, -1, -1, -1, -1, -1, -1, -1]
	var out: Bool = false
	var pend: [(Int, Bool)] = []
	var powered: Bool = false
	var want: Double = 0
	var made: Double = 0
	var timer: Double = 0
	var flips: Int = 0
	var flipT: Double = 0
	var burnT: Double = 0
	var lastSwap: Double = -10
	var work: Double = 0
	var enabled: Bool = true
	/// index among the logic parts (for the evaluation queue)
	var li: Int = -1

	init(key: ChestKey, tile: Tile) {
		self.key = key
		self.tile = tile
		switch tile {
		case .pushButton: param = 1.0
		case .pulseTimer: param = 1.0
		case .repeater: param = 1
		case .motionSensor, .proximitySensor: param = 5
		case .breaker: mode = 1; on = true
		case .powerSwitch: on = true
		case .autoCrafter: item = -1
		default: break
		}
	}

	var x: Int { return key.x }
	var y: Int { return key.y }
	var role: PowerRole { return powerRole(tile) }
}

struct PowerDevSave: Codable {
	var d: Int
	var x: Int
	var y: Int
	var t: Int
	var dir: Int
	var mode: Int
	var param: Double
	var charge: Double
	var on: Bool
	var flag: Bool
	var item: Int
}

final class PowerNet {
	var devs: [PowerDev] = []
	var cells: Int = 0
	/// last share-out: made, used, asked for, stored and room (sparks per second and sparks)
	var made: Double = 0
	var used: Double = 0
	var asked: Double = 0
	var stored: Double = 0
	var cap: Double = 0
	var short: Bool = false
}

final class PulseNet {
	var sources: [PowerDev] = []
	var readers: [PowerDev] = []
	/// doors, shutters and sirens on its wire
	var followers: [IntPair] = []
	var cells: Int = 0
	var on: Bool = false
	var dirty: Bool = true
}

/// Everything the simulation works out from the wiring, rebuilt when the wiring changes
final class PowerSim {
	var builtRev: Int = -1
	var builtDim: Int = -1
	var pnets: [PowerNet] = []
	var snets: [PulseNet] = []
	/// net index of each wired cell, by layer and position
	var cellNet: [Int: Int] = [:]
	var devs: [PowerDev] = []
	var logic: [PowerDev] = []
	var polled: [PowerDev] = []
	var machines: [PowerDev] = []
	var conveyors: [PowerDev] = []
	var queue: Set<Int> = []
	var tickNo: Int = 0
	var powerT: Double = 0
	var pulseT: Double = 0
	var machineT: Double = 0
	/// tile swaps left this step (lamps, gates, doors), so a fast clock can't relight the world every frame
	var swaps: Int = 0
	var sirens: Set<IntPair> = []
	/// devices that flipped too fast and burnt out (for a warning)
	var burnNote: Double = 0
	var rebuilds: Int = 0
	/// after a rebuild every reader and follower is brought in line with its net once
	var settle: Bool = false

	static func cellKey(_ layer: Int, _ x: Int, _ y: Int) -> Int {
		return (((x &+ (1 << 30)) << 12) | (y & 4095)) << 2 | layer
	}
}

/// Fuel for generators: seconds of burning per item (the dynamo only takes ember)
func fuelSeconds(_ it: Item, dynamo: Bool) -> Double {
	if dynamo {
		switch it {
		case .mat(.emberBar): return 300
		case .mat(.emberOre): return 70
		default: return 0
		}
	}
	switch it {
	case .mat(.coal): return 60
	case .block(.log), .block(.jungleLog), .block(.palmLog), .block(.birchLog): return 20
	case .block(.planks): return 6
	case .mat(.stick): return 2
	default: return 0
	}
}

/// How much a device makes or uses, its storage, and a breaker's limit
enum PowerSpec {
	static func capacity(_ t: Tile) -> Double {
		switch t {
		case .battery: return 600
		case .accumulator: return 5000
		case .crankGen: return 60
		default: return 0
		}
	}
	static func rate(_ t: Tile) -> Double {
		switch t {
		case .battery: return 15
		case .accumulator: return 60
		default: return 0
		}
	}
	/// sparks per second while running
	static func draw(_ t: Tile) -> Double {
		switch t {
		case .lampOff, .lampOn: return 1
		case .gateClosed, .gateOpen: return 0.5
		case .arcTrap: return 3
		case .autoDrill: return 8
		case .conveyor: return 1.5
		case .collector: return 1
		case .autoCrafter: return 5
		case .sumpPump: return 4
		case .exoStation: return 10
		case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor: return 0.5
		default: return 0
		}
	}
	static let breakerLimits: [Double] = [10, 25, 50, 100, 250]
	static let fuelRate: Double = 12
	static let dynamoRate: Double = 40
}

// MARK: - Wires in the world

extension World {
	func wireAt(_ x: Int, _ y: Int) -> UInt8 {
		if y < 0 || y >= H { return 0 }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx), c.wireCount > 0 else { return 0 }
		return c.wires[(x - cx * chunkW) * H + y]
	}

	/// Sets the wire bits on a cell; returns false if the cell is not loaded
	@discardableResult
	func setWire(_ x: Int, _ y: Int, _ bits: UInt8) -> Bool {
		if y < 1 || y >= H - 1 { return false }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return false }
		if c.wires.isEmpty {
			if bits == 0 { return true }
			c.wires = [UInt8](repeating: 0, count: chunkW * H)
		}
		let i: Int = (x - cx * chunkW) * H + y
		let old: UInt8 = c.wires[i]
		if old == bits { return true }
		if old == 0 { c.wireCount += 1 }
		if bits == 0 { c.wireCount -= 1 }
		c.wires[i] = bits
		c.dirty = true
		c.bumpRows(y - 1, y + 1)
		powerRev &+= 1
		return true
	}

	func powerKey(_ x: Int, _ y: Int) -> ChestKey { return ChestKey(d: dim.rawValue, x: x, y: y) }

	func powerDev(_ x: Int, _ y: Int) -> PowerDev? { return devs[powerKey(x, y)] }

	/// Keeps the device list in step with the tiles (called from set): a new device gets its default
	/// settings, a removed one is forgotten, and switching between a device's two forms keeps it
	func powerTileChanged(_ x: Int, _ y: Int, _ old: Tile, _ new: Tile) {
		let k: ChestKey = powerKey(x, y)
		if new.isPower {
			if let d = devs[k], powerFamily(d.tile) == powerFamily(new) {
				d.tile = new
				return
			}
			devs[k] = PowerDev(key: k, tile: new)
		} else if old.isPower {
			devs[k] = nil
		}
		powerRev &+= 1
	}
}

// MARK: - The simulation

extension Game {
	/// Called every frame
	func updatePower(_ dt: Double) {
		let sim: PowerSim = power
		if world.devs.isEmpty && sim.devs.isEmpty { return }
		if sim.builtRev != world.powerRev || sim.builtDim != world.dim.rawValue { rebuildPower() }
		if sim.devs.isEmpty { return }
		sim.powerT += dt
		if sim.powerT >= 0.25 {
			let step: Double = min(sim.powerT, 1.0)
			sim.powerT = 0
			powerTick(step)
		}
		sim.pulseT += dt
		var n: Int = 0
		while sim.pulseT >= 0.05 && n < 3 {
			sim.pulseT -= 0.05
			n += 1
			pulseTick()
		}
		if sim.pulseT > 0.15 { sim.pulseT = 0 }
		sim.machineT += dt
		if sim.machineT >= 0.1 {
			let step: Double = min(sim.machineT, 0.3)
			sim.machineT = 0
			machineTick(step)
		}
		if !sim.conveyors.isEmpty { runConveyors(dt) }
		if sim.burnNote > 0 { sim.burnNote -= dt }
	}

	/// Works out every network from the wiring and devices in loaded chunks
	func rebuildPower() {
		let sim: PowerSim = power
		let w: World = world
		sim.builtRev = w.powerRev
		sim.builtDim = w.dim.rawValue
		sim.rebuilds += 1
		sim.pnets.removeAll()
		sim.snets.removeAll()
		sim.cellNet.removeAll(keepingCapacity: true)
		sim.devs.removeAll()
		sim.logic.removeAll()
		sim.polled.removeAll()
		sim.machines.removeAll()
		sim.conveyors.removeAll()
		sim.sirens.removeAll()
		sim.queue.removeAll()
		let dim: Int = w.dim.rawValue
		var gone: [ChestKey] = []
		for (k, d) in w.devs where k.d == dim {
			if !w.isLoaded(k.x) { continue }
			let t: Tile = w.tile(k.x, k.y)
			if !t.isPower || powerFamily(t) != powerFamily(d.tile) { gone.append(k); continue }
			d.tile = t
			d.pnet = -1
			d.snets = [-1, -1]
			d.ports = [-1, -1, -1, -1, -1, -1, -1, -1]
			sim.devs.append(d)
		}
		for k in gone { w.devs[k] = nil }
		sim.devs.sort { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
		// flood every wired cell into networks, layer by layer, in a fixed order
		let cks: [Int] = w.chunks.keys.sorted()
		for cx in cks {
			guard let c = w.chunks[cx], c.wireCount > 0 else { continue }
			let H: Int = c.H
			for lx in 0..<chunkW {
				let base: Int = lx * H
				for y in 0..<H {
					let b: UInt8 = c.wires[base + y]
					if b == 0 { continue }
					let x: Int = c.x0 + lx
					for layer in 0..<3 where b & Wire.bit(layer) != 0 {
						if sim.cellNet[PowerSim.cellKey(layer, x, y)] == nil && conducts(layer, x, y) { floodNet(layer, x, y) }
					}
				}
			}
		}
		// hook the devices onto the networks
		for d in sim.devs {
			let role: PowerRole = d.role
			if role == .generator || role == .storage || role == .meter || role == .sensor || role == .machine || role == .conductor {
				if let p = sim.cellNet[PowerSim.cellKey(0, d.x, d.y)] {
					d.pnet = p
					sim.pnets[p].devs.append(d)
				}
			}
			if role == .logic {
				// inputs and the output are the cells around it; its own cell joins nothing
				for side in 0..<4 {
					let nx: Int = d.x + sideDX[side]
					let ny: Int = d.y + sideDY[side]
					for c in 0..<2 {
						if let s = sim.cellNet[PowerSim.cellKey(c + 1, nx, ny)] {
							d.ports[side * 2 + c] = s
							if side == d.dir { sim.snets[s].sources.append(d) } else if isLogicInput(d, side) { sim.snets[s].readers.append(d) }
						}
					}
				}
				d.li = sim.logic.count
				sim.logic.append(d)
			} else {
				for c in 0..<2 {
					if let s = sim.cellNet[PowerSim.cellKey(c + 1, d.x, d.y)] {
						d.snets[c] = s
						if role == .source || role == .sensor { sim.snets[s].sources.append(d) } else { sim.snets[s].readers.append(d) }
					}
				}
			}
			if role == .sensor || d.tile == .pressurePlate || d.tile == .pushButton { sim.polled.append(d) }
			if role == .machine || role == .conductor { sim.machines.append(d) }
			if d.tile == .conveyor { sim.conveyors.append(d) }
			if d.tile == .pushButton && d.timer <= 0 { d.out = false }
			if d.tile == .lever { d.out = d.on }
		}
		// every pulse net starts dirty so its followers and readers settle on the wiring as it is now
		for n in sim.snets { n.dirty = true }
		for i in 0..<sim.logic.count { sim.queue.insert(i) }
		sim.settle = true
	}

	/// Whether a layer passes through a cell: power stops at an open switch or a tripped breaker,
	/// pulses stop at logic parts (their sides are separate inputs and an output)
	func conducts(_ layer: Int, _ x: Int, _ y: Int) -> Bool {
		let t: Tile = world.tile(x, y)
		if layer == 0 {
			if t == .powerSwitch || t == .breaker {
				return world.powerDev(x, y)?.on ?? true
			}
			return true
		}
		return powerRole(t) != .logic
	}

	func floodNet(_ layer: Int, _ sx: Int, _ sy: Int) {
		let sim: PowerSim = power
		let id: Int
		let pn: PowerNet? = layer == 0 ? PowerNet() : nil
		let sn: PulseNet? = layer == 0 ? nil : PulseNet()
		if let p = pn { id = sim.pnets.count; sim.pnets.append(p) } else { id = sim.snets.count; sim.snets.append(sn!) }
		let bit: UInt8 = Wire.bit(layer)
		var stack: [IntPair] = [IntPair(x: sx, y: sy)]
		sim.cellNet[PowerSim.cellKey(layer, sx, sy)] = id
		var n: Int = 0
		while let c = stack.popLast() {
			n += 1
			if let s = sn {
				let t: Tile = world.tile(c.x, c.y)
				if pulseFollower(t) {
					s.followers.append(c)
					if t == .stormSiren { sim.sirens.insert(c) }
				}
			}
			// a very long line still works, but stops growing past this many cells
			if n > 20000 { continue }
			for side in 0..<4 {
				let nx: Int = c.x + sideDX[side]
				let ny: Int = c.y + sideDY[side]
				if world.wireAt(nx, ny) & bit == 0 { continue }
				let k: Int = PowerSim.cellKey(layer, nx, ny)
				if sim.cellNet[k] != nil { continue }
				if !conducts(layer, nx, ny) { continue }
				sim.cellNet[k] = id
				stack.append(IntPair(x: nx, y: ny))
			}
		}
		if let p = pn { p.cells = n } else { sn!.cells = n }
	}

	/// The sides a logic part reads: the back for a relay, inverter or timer; both sides for a gate
	func isLogicInput(_ d: PowerDev, _ side: Int) -> Bool {
		if d.tile == .logicGate { return side == (d.dir + 1) % 4 || side == (d.dir + 3) % 4 }
		return side == (d.dir + 2) % 4
	}

	// MARK: power

	/// Shares the power out on every network: generators first, batteries make up the difference or
	/// take the surplus, fuel is only burnt for what is actually needed, and if there still isn't
	/// enough the machines are served in a fixed order and the rest stop
	func powerTick(_ dt: Double) {
		let sim: PowerSim = power
		for d in sim.devs where d.pnet < 0 {
			// not on any power line
			d.made = 0
			if d.powered { d.powered = false; powerChanged(d) }
			if d.tile == .crankGen { d.charge = max(0, d.charge - 6.0 * dt) }
		}
		for net in sim.pnets {
			var made: Double = 0
			var asked: Double = 0
			var room: Double = 0
			var avail: Double = 0
			var stored: Double = 0
			var cap: Double = 0
			var burners: [PowerDev] = []
			var loads: [PowerDev] = []
			var stores: [PowerDev] = []
			var breakers: [PowerDev] = []
			for d in net.devs {
				switch d.role {
				case .generator:
					if d.tile == .fuelGen || d.tile == .emberDynamo || d.tile == .windTurbine {
						burners.append(d)
					} else {
						let r: Double = generatorRate(d, dt)
						d.made = r
						made += r
					}
				case .storage:
					stores.append(d)
					let c: Double = PowerSpec.capacity(d.tile)
					let r: Double = PowerSpec.rate(d.tile)
					room += min(r, max(0, c - d.charge) / dt)
					avail += min(r, d.charge / dt)
					stored += d.charge
					cap += c
				case .conductor:
					if d.tile == .breaker { breakers.append(d) }
				case .machine, .sensor:
					d.want = d.enabled ? PowerSpec.draw(d.tile) : 0
					if d.want > 0 { loads.append(d) } else if d.powered {
						d.powered = false
						powerChanged(d)
					}
					asked += d.want
				default:
					break
				}
			}
			// generators that burn fuel cover only what the others can't (and topping up batteries); a
			// wind turbine gives from its own charge, which the wind keeps topping up (see the weather
			// devices), so what isn't needed stays in it for its Doppler station and storm rod
			var need: Double = max(0, asked + room - made)
			for f in burners {
				if f.tile == .windTurbine {
					let k: String = deviceKey(DeviceSpot(x: f.x, y: f.y, t: .windTurbine))
					let have: Double = weather.store[k] ?? 0
					let r: Double = min(8.0, have / dt, need)
					weather.store[k] = max(0, have - r * dt)
					f.made = r
					made += r
					need -= r
					continue
				}
				let top: Double = f.tile == .emberDynamo ? PowerSpec.dynamoRate : PowerSpec.fuelRate
				if f.charge > 0 && need > 0.01 {
					let r: Double = min(top, need)
					f.charge = max(0, f.charge - dt * r / top)
					f.made = r
					made += r
					need -= r
				} else {
					f.made = 0
				}
			}
			var supply: Double = made + avail
			var used: Double = 0
			for d in loads {
				let ok: Bool = supply + 1e-9 >= d.want
				if ok {
					supply -= d.want
					used += d.want
				}
				if ok != d.powered {
					d.powered = ok
					powerChanged(d)
				}
			}
			// what is left over charges the batteries; a shortfall drains them (the first ones first)
			var flow: Double = made - used
			for b in stores {
				let c: Double = PowerSpec.capacity(b.tile)
				let r: Double = PowerSpec.rate(b.tile)
				if flow > 0 {
					let take: Double = min(flow, r, max(0, c - b.charge) / dt)
					b.charge += take * dt
					flow -= take
				} else if flow < 0 {
					let give: Double = min(-flow, r, b.charge / dt)
					b.charge = max(0, b.charge - give * dt)
					flow += give
				}
			}
			net.made = made
			net.used = used
			net.asked = asked
			net.stored = stored
			net.cap = cap
			net.short = used + 1e-6 < asked
			// a breaker opens when the machines on its line ask for more than its limit
			for b in breakers where b.on {
				let limit: Double = PowerSpec.breakerLimits[clampI(b.mode, 0, PowerSpec.breakerLimits.count - 1)]
				if asked > limit {
					b.on = false
					b.flag = true
					world.powerRev &+= 1
					sfx(.zap, at: Double(b.x), 0.6)
					spawnParticles(Double(b.x) + 0.5, Double(b.y) + 0.4, 0xFFE070, 8, 3.0, 0.4, 10)
					floatText("Breaker tripped: overload", Double(b.x) + 0.5, Double(b.y) - 0.6, 0xFF8040)
				}
			}
		}
	}

	/// Sparks per second a generator makes right now (fuel burners are worked out separately)
	func generatorRate(_ d: PowerDev, _ dt: Double) -> Double {
		switch d.tile {
		case .crankGen:
			// a flywheel spun up by hand: it gives its charge back steadily
			let r: Double = min(6.0, d.charge / dt)
			d.charge = max(0, d.charge - r * dt)
			return r
		case .solarPanel:
			// needs open sky above (glass lets the light through)
			if world.dim != .overworld || d.y >= world.skyTop(d.x) { return 0 }
			let cloud: Double = settings.weatherOn ? weatherAt(Double(d.x) + 0.5, Double(d.y)).cloud : 0
			return 4.0 * dayFactor * (1.0 - 0.75 * clampD(cloud, 0, 1))
		case .waterWheel:
			var n: Int = 0
			for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) { if world.tile(d.x + dx, d.y + dy) == .water { n += 1 } } }
			var r: Double = Double(n) * 0.75
			if settings.weatherOn && world.dim == .overworld && d.y < world.rainTop(d.x) + 1 {
				r += weatherAt(Double(d.x) + 0.5, Double(d.y)).precip * 1.5
			}
			return min(6.0, r)
		default:
			return 0
		}
	}

	/// A machine just gained or lost power
	func powerChanged(_ d: PowerDev) {
		applyMachine(d)
	}

	// MARK: pulses

	func pulseTick() {
		let sim: PowerSim = power
		sim.tickNo += 1
		sim.swaps = 48
		let now: Int = sim.tickNo
		// sources that watch the world
		for d in sim.polled {
			if d.tile == .pushButton {
				if d.timer > 0 {
					d.timer -= 0.05
					if d.timer <= 0 { setOut(d, false) }
				}
				continue
			}
			if d.tile == .pressurePlate {
				if (now &+ d.x) % 2 == 0 { setOut(d, plateDown(d)) }
				continue
			}
			// sensors look four times a second, staggered, and only with power
			if (now &+ d.x &+ d.y) % 5 != 0 { continue }
			setOut(d, d.powered && sensorReads(d))
		}
		// logic outputs whose delay has run out
		for d in sim.logic {
			if d.burnT > 0 {
				d.burnT -= 0.05
				if d.burnT <= 0 { d.burnT = 0; sim.queue.insert(d.li) }
				continue
			}
			if d.tile == .pulseTimer && d.mode == 0 { clockStep(d) }
			while let p = d.pend.first, p.0 <= now {
				d.pend.removeFirst()
				setOut(d, p.1)
			}
		}
		// nets whose drivers changed
		var changed: [PulseNet] = []
		for n in sim.snets where n.dirty {
			n.dirty = false
			var on: Bool = false
			for s in n.sources where s.out && s.burnT <= 0 { on = true; break }
			if on != n.on || sim.settle {
				n.on = on
				changed.append(n)
			}
		}
		sim.settle = false
		for n in changed {
			for r in n.readers {
				if r.role == .logic {
					if r.li >= 0 { sim.queue.insert(r.li) }
				} else {
					controlChanged(r)
				}
			}
			for c in n.followers { followPulse(c, n.on) }
		}
		// logic parts whose inputs changed: work out the new output, due after its delay
		if !sim.queue.isEmpty {
			let list: [Int] = sim.queue.sorted()
			sim.queue.removeAll()
			var budget: Int = 3000
			for i in list {
				if i >= sim.logic.count { continue }
				budget -= 1
				if budget < 0 { sim.queue.insert(i); continue }
				evalLogic(sim.logic[i], now)
			}
		}
	}

	/// Whether any pulse net on a device's own cell is on (a lamp, gate or machine's control)
	func pulseHere(_ d: PowerDev) -> Bool? {
		var wired: Bool = false
		var on: Bool = false
		for c in 0..<2 where d.snets[c] >= 0 {
			wired = true
			if power.snets[d.snets[c]].on { on = true }
		}
		return wired ? on : nil
	}

	/// Reads a logic part's input on one side (either colour)
	func portOn(_ d: PowerDev, _ side: Int) -> Bool? {
		var wired: Bool = false
		var on: Bool = false
		for c in 0..<2 {
			let s: Int = d.ports[side * 2 + c]
			if s >= 0 {
				wired = true
				if power.snets[s].on { on = true }
			}
		}
		return wired ? on : nil
	}

	func evalLogic(_ d: PowerDev, _ now: Int) {
		if d.burnT > 0 { return }
		let back: Int = (d.dir + 2) % 4
		var target: Bool = d.out
		var delay: Int = 1
		switch d.tile {
		case .inverter:
			target = !(portOn(d, back) ?? false)
		case .repeater:
			target = portOn(d, back) ?? false
			delay = clampI(Int(d.param.rounded()), 1, 4)
		case .logicGate:
			let a: Bool = portOn(d, (d.dir + 1) % 4) ?? false
			let b: Bool = portOn(d, (d.dir + 3) % 4) ?? false
			switch d.mode {
			case 0: target = a && b
			case 1: target = a || b
			case 2: target = a != b
			case 3: target = !(a && b)
			default: target = !(a || b)
			}
		case .pulseTimer:
			if d.mode == 1 {
				// delay: the output repeats the input's changes after the set time
				target = portOn(d, back) ?? false
				delay = max(1, Int((d.param / 0.05).rounded()))
			} else {
				// clock: an input wired to the back switches it on and off
				return
			}
		default:
			return
		}
		let last: Bool = d.pend.last?.1 ?? d.out
		if target == last { return }
		if d.pend.count >= 16 { d.pend.removeFirst() }
		d.pend.append((now + delay, target))
	}

	/// A clock timer: on for half its period, off for the other half, while enabled
	func clockStep(_ d: PowerDev) {
		let enabled: Bool = portOn(d, (d.dir + 2) % 4) ?? true
		if !enabled {
			d.timer = 0
			if d.out { setOut(d, false) }
			return
		}
		d.timer += 0.05
		let half: Double = max(0.1, d.param * 0.5)
		if d.timer >= half - 1e-9 {
			d.timer = 0
			setOut(d, !d.out)
		}
	}

	/// Changes what a device sends out, marking the nets it drives. A part that flips more than about
	/// twenty-five times a second (a loop with no delay worth the name) burns out for three seconds.
	func setOut(_ d: PowerDev, _ v: Bool) {
		if d.out == v { return }
		let sim: PowerSim = power
		if clock - d.flipT > 1.0 {
			d.flipT = clock
			d.flips = 0
		}
		d.flips += 1
		if d.flips > 25 {
			d.burnT = 3.0
			d.out = false
			d.pend.removeAll()
			if sim.burnNote <= 0 {
				sim.burnNote = 4.0
				floatText("Circuit overloaded: flipping too fast", Double(d.x) + 0.5, Double(d.y) - 0.6, 0xFF8040)
				spawnParticles(Double(d.x) + 0.5, Double(d.y) + 0.3, 0x8A8A8A, 6, 1.5, 0.8, -4)
			}
		} else {
			d.out = v
		}
		if d.role == .logic {
			for c in 0..<2 {
				let s: Int = d.ports[d.dir * 2 + c]
				if s >= 0 { sim.snets[s].dirty = true }
			}
		} else {
			for c in 0..<2 where d.snets[c] >= 0 { sim.snets[d.snets[c]].dirty = true }
		}
	}

	/// Something stands on a pressure plate: anyone, only the player, or only creatures
	func plateDown(_ d: PowerDev) -> Bool {
		let x0: Double = Double(d.x) + 0.1
		let x1: Double = Double(d.x) + 0.9
		let y0: Double = Double(d.y) + 0.3
		let y1: Double = Double(d.y) + 1.05
		if d.mode != 2 && !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.y < y1 + 0.1 { return true }
		if d.mode == 1 { return false }
		for m in mobsNear(x0 - 2, x1 + 2) where m.hp > 0 {
			if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.y < y1 + 0.1 { return true }
		}
		return false
	}

	/// What a sensor sees (it only reports with power)
	func sensorReads(_ d: PowerDev) -> Bool {
		let cx: Double = Double(d.x) + 0.5
		let cy: Double = Double(d.y) + 0.5
		switch d.tile {
		case .daySensor:
			let day: Bool = world.dim == .overworld && dayFactor > 0.5
			return d.mode == 0 ? day : !day
		case .weatherSensor:
			if !settings.weatherOn || world.dim != .overworld { return false }
			let L: LocalWeather = weatherAt(cx, cy)
			switch d.mode {
			case 0: return L.precip > 0.12
			case 1: return L.thunder > 0.3 || L.hail > 0.1
			case 2: return abs(L.wind) > 10
			default: return sirenWorthy() || L.tornado > 0.05 || L.hurricane > 0.05
			}
		case .motionSensor, .proximitySensor:
			// motion: 0 anything moving, 1 creatures only, 2 the player only
			// proximity: 0 the player, 1 hostile creatures, 2 any creature, 3 anyone
			let r: Double = clampD(d.param, 2, 12)
			let moving: Bool = d.tile == .motionSensor
			let player: Bool = moving ? d.mode != 1 : (d.mode == 0 || d.mode == 3)
			let creatures: Bool = moving ? d.mode != 2 : d.mode != 0
			let hostileOnly: Bool = !moving && d.mode == 1
			if player && !dead {
				let dx: Double = pb.x - cx
				let dy: Double = pb.cy - cy
				if dx * dx + dy * dy <= r * r && (!moving || abs(pb.vx) > 0.6 || abs(pb.vy) > 0.6) { return true }
			}
			if !creatures { return false }
			for m in mobsNear(cx - r, cx + r) where m.hp > 0 && !m.removed {
				let dx: Double = m.b.x - cx
				let dy: Double = m.b.cy - cy
				if dx * dx + dy * dy > r * r { continue }
				if moving && abs(m.b.vx) < 0.6 && abs(m.b.vy) < 0.6 { continue }
				if hostileOnly && !(m.def.hostile && !m.tame) { continue }
				return true
			}
			return false
		case .itemSensor:
			var n: Int = 0
			var full: Bool = false
			for side in 0..<4 {
				let nx: Int = d.x + sideDX[side]
				let ny: Int = d.y + sideDY[side]
				if world.tile(nx, ny) == .chest {
					let items: [Stack] = world.chestItems(nx, ny)
					for s in items { n += s.count }
					if items.count >= 27 && items.allSatisfy({ $0.count >= $0.item.maxStack }) { full = true }
				}
			}
			for dr in drops where abs(dr.x - cx) < 0.7 && abs(dr.y - cy) < 0.8 { n += dr.stack.count }
			switch d.mode {
			case 0: return n >= 1
			case 1: return n >= 16
			case 2: return n >= 64
			default: return full
			}
		default:
			return false
		}
	}

	/// The pulse on a machine's cell changed
	func controlChanged(_ d: PowerDev) {
		applyMachine(d)
	}

	/// Brings a machine, switch or light in line with its power and its pulse. Lamps and gates change
	/// their tile; a few such changes are allowed per step, the rest wait for the next one.
	func applyMachine(_ d: PowerDev) {
		let sim: PowerSim = power
		let pulse: Bool? = pulseHere(d)
		switch d.tile {
		case .powerSwitch:
			if let p = pulse, p != d.on {
				d.on = p
				world.powerRev &+= 1
			}
			return
		case .lampOff, .lampOn:
			d.enabled = pulse ?? true
			let lit: Bool = d.enabled && d.powered
			let want: Tile = lit ? .lampOn : .lampOff
			if d.tile != want && clock - d.lastSwap > 0.12 && sim.swaps > 0 {
				sim.swaps -= 1
				d.lastSwap = clock
				world.set(d.x, d.y, want)
			}
		case .gateClosed, .gateOpen:
			if let p = pulse {
				d.enabled = true
				d.on = p
			}
			// a powered gate needs power to move; with no pulse wire, its own setting (tap it) decides
			let open: Bool = d.on && d.powered
			let want: Tile = open ? .gateOpen : .gateClosed
			if d.tile != want && clock - d.lastSwap > 0.12 && sim.swaps > 0 {
				if want == .gateClosed && doorBlocked(d.x, d.y, d.y) { return }
				sim.swaps -= 1
				d.lastSwap = clock
				world.set(d.x, d.y, want)
				sfx(.door, at: Double(d.x), 0.4)
			}
		default:
			// a machine runs while its pulse wire is on (or always, with none); a sensor's own cell carries
			// its own output, so sensors are never switched by it
			if d.role == .machine || d.role == .indicator { d.enabled = pulse ?? true }
		}
	}

	/// A door, shutter or siren on a pulse wire
	func followPulse(_ c: IntPair, _ on: Bool) {
		let t: Tile = world.tile(c.x, c.y)
		let sim: PowerSim = power
		if sim.swaps <= 0 { return }
		switch t {
		case .doorClosed, .doorOpen:
			let open: Bool = t == .doorOpen
			if open != on {
				sim.swaps -= 1
				setDoor(c.x, c.y, open: on)
			}
		case .shutterClosed, .shutterOpen:
			let closed: Bool = t == .shutterClosed
			if closed != on {
				sim.swaps -= 1
				world.set(c.x, c.y, on ? .shutterClosed : .shutterOpen)
			}
		default:
			break
		}
	}

	/// Whether a pulse is on at a cell (sirens ask this)
	func pulseOnAt(_ x: Int, _ y: Int) -> Bool {
		let sim: PowerSim = power
		for layer in 1...2 {
			if let s = sim.cellNet[PowerSim.cellKey(layer, x, y)], s < sim.snets.count, sim.snets[s].on { return true }
		}
		return false
	}

	// MARK: machines

	/// Machines at work (ten times a second): traps, drills, collectors, crafters and pumps
	func machineTick(_ dt: Double) {
		let sim: PowerSim = power
		for d in sim.machines {
			// a lamp or gate that was held back by the limit on tile changes catches up
			if d.tile == .lampOff || d.tile == .lampOn || d.tile == .gateClosed || d.tile == .gateOpen { applyMachine(d) }
			let running: Bool = d.enabled && d.powered
			if !running {
				d.work = 0
				continue
			}
			switch d.tile {
			case .arcTrap: runArcTrap(d, dt)
			case .autoDrill: runDrill(d, dt)
			case .exoStation: runSuitDock(d, dt)
			case .collector: runCollector(d, dt)
			case .autoCrafter: runCrafter(d, dt)
			case .sumpPump: runPump(d, dt)
			default: break
			}
		}
	}

	/// An arc trap zaps whatever stands on it, once a second (the player only if set to)
	func runArcTrap(_ d: PowerDev, _ dt: Double) {
		d.work -= dt
		if d.work > 0 { return }
		let x0: Double = Double(d.x) + 0.05
		let x1: Double = Double(d.x) + 0.95
		let y0: Double = Double(d.y) - 2.0
		let y1: Double = Double(d.y) + 0.05
		var hit: Bool = false
		var info = DamageInfo(amount: 7, type: .shock, source: .environment)
		info.knock = 3.0
		info.originX = Double(d.x) + 0.5
		info.key = d.key.hashValue
		info.cooldown = 0.9
		for m in mobsNear(x0 - 2, x1 + 2) where m.hp > 0 && !m.tame {
			if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.y <= y1 + 0.1 {
				if applyMobDamage(m, info) { hit = true }
			}
		}
		if d.flag && !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.y <= y1 + 0.1 {
			if hurtPlayer(info) { hit = true }
		}
		if hit {
			d.work = 1.0
			sfx(.zap, at: Double(d.x), 0.5)
			spawnParticles(Double(d.x) + 0.5, Double(d.y) - 0.3, 0x8AF0E8, 8, 4.0, 0.25, 0)
			addLightFlash(Double(d.x) + 0.5, Double(d.y) - 0.5, peak: 9, dur: 0.25, radius: 1.6, color: 0x8AF0E8)
		}
	}

	/// An auto drill bores out the block it faces, as fast as the block's hardness allows. It digs what
	/// an iron pickaxe could, and what it breaks drops as if mined by hand.
	func runDrill(_ d: PowerDev, _ dt: Double) {
		let tx: Int = d.x + sideDX[d.dir]
		let ty: Int = d.y + sideDY[d.dir]
		let t: Tile = world.tile(tx, ty)
		if t == .air || t.liquid || t.hardness >= 50 || t.def.tier > 3 || t == .chest || t.isPower || t == .portalFrame || t == .portalOn || t == .portalOff || t == .bedrock {
			d.work = 0
			return
		}
		d.work += dt
		let need: Double = 0.6 + t.hardness * 0.9
		if Int(d.work * 6.0) != Int((d.work - dt) * 6.0) {
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, t.def.colors.first ?? 0x888888, 1, 2.0, 0.3, 10)
		}
		if d.work >= need {
			d.work = 0
			breakTile(tx, ty, false)
			sfx(.digStone, at: Double(tx), 0.4)
		}
	}

	/// An item collector draws loose items within two blocks into a chest beside it, as far as they fit
	func runCollector(_ d: PowerDev, _ dt: Double) {
		d.work -= dt
		if d.work > 0 { return }
		d.work = 0.25
		var chest: IntPair? = nil
		for side in 0..<4 where world.tile(d.x + sideDX[side], d.y + sideDY[side]) == .chest {
			chest = IntPair(x: d.x + sideDX[side], y: d.y + sideDY[side])
			break
		}
		guard let c = chest else { return }
		let cx: Double = Double(d.x) + 0.5
		let cy: Double = Double(d.y) + 0.5
		var items: [Stack] = world.chestItems(c.x, c.y)
		var changed: Bool = false
		var i: Int = 0
		while i < drops.count {
			let dr: DropItem = drops[i]
			if abs(dr.x - cx) > 2.0 || abs(dr.y - cy) > 2.0 || dr.age < 0.3 { i += 1; continue }
			let left: Int = chestAdd(&items, dr.stack)
			if left == dr.stack.count { i += 1; continue }
			changed = true
			spawnParticles(dr.x, dr.y, 0xE8E0C0, 2, 1.5, 0.2, 0)
			if left == 0 {
				drops.remove(at: i)
			} else {
				drops[i].stack.count = left
				i += 1
			}
		}
		if changed { world.setChestItems(c.x, c.y, items) }
	}

	/// An auto crafter makes its chosen recipe every two seconds from the chest behind it into the chest
	/// in front of it, but only when every ingredient is there and the result fits
	func runCrafter(_ d: PowerDev, _ dt: Double) {
		d.work += dt
		if d.work < 2.0 { return }
		d.work = 0
		if d.item < 0 || d.item >= RecipeBook.all.count { return }
		let r: Recipe = RecipeBook.all[d.item]
		if !crafterCan(r.station) { return }
		let side: Int = d.dir == 2 ? 2 : 0
		let ix: Int = d.x - sideDX[side]
		let ox: Int = d.x + sideDX[side]
		if world.tile(ix, d.y) != .chest || world.tile(ox, d.y) != .chest { return }
		var input: [Stack] = world.chestItems(ix, d.y)
		var output: [Stack] = world.chestItems(ox, d.y)
		for c in r.cost where chestCount(input, c.item) < c.n { return }
		var trial: [Stack] = output
		if chestAdd(&trial, Stack(item: r.out, count: r.outCount)) > 0 { return }
		for c in r.cost { chestTake(&input, c.item, c.n) }
		_ = chestAdd(&output, Stack(item: r.out, count: r.outCount))
		world.setChestItems(ix, d.y, input)
		world.setChestItems(ox, d.y, output)
		sfx(.craft, at: Double(d.x), 0.4)
		spawnParticles(Double(d.x) + 0.5, Double(d.y) + 0.2, 0xC8B060, 4, 2.0, 0.3, 6)
	}

	/// The stations an auto crafter stands in for: hand work, the workbench, the anvil and the
	/// tinker's bench (not the furnace, campfire or Rift Forge, which need heat or the Umbral fire)
	func crafterCan(_ s: Station) -> Bool {
		return s == .hand || s == .bench || s == .anvil || s == .tinker
	}

	/// A sump pump drains the nearest water within four blocks, a block at a time, into a rain barrel
	/// or cistern beside it if there is one
	func runPump(_ d: PowerDev, _ dt: Double) {
		d.work += dt
		if d.work < 0.4 { return }
		d.work = 0
		var best: IntPair? = nil
		var bd: Int = 999
		for dy in -4...4 {
			for dx in -4...4 {
				let x: Int = d.x + dx
				let y: Int = d.y + dy
				if world.tile(x, y) != .water { continue }
				let dist: Int = abs(dx) + abs(dy)
				if dist < bd || (dist == bd && y < (best?.y ?? 0)) { bd = dist; best = IntPair(x: x, y: y) }
			}
		}
		guard let w = best else { return }
		world.set(w.x, w.y, .air)
		spawnParticles(Double(w.x) + 0.5, Double(w.y) + 0.5, 0x3B7BE0, 3, 1.5, 0.3, 8)
		for side in 0..<4 {
			let nx: Int = d.x + sideDX[side]
			let ny: Int = d.y + sideDY[side]
			let t: Tile = world.tile(nx, ny)
			if t == .rainBarrel || t == .rainCistern {
				let k: String = deviceKey(DeviceSpot(x: nx, y: ny, t: t))
				let cap: Double = t == .rainBarrel ? 8 : 32
				weather.store[k] = min(cap, (weather.store[k] ?? 0) + 1)
				break
			}
		}
	}

	/// Running conveyor belts carry what lies on them (and walk anyone standing on them along)
	func runConveyors(_ dt: Double) {
		let sim: PowerSim = power
		var belts: [Int: Int] = [:]
		for d in sim.conveyors where d.enabled && d.powered {
			belts[PowerSim.cellKey(0, d.x, d.y)] = d.dir == 2 ? -1 : 1
		}
		if belts.isEmpty { return }
		let speed: Double = 2.4
		for i in 0..<drops.count {
			let dr: DropItem = drops[i]
			let k: Int = PowerSim.cellKey(0, Int(floor(dr.x)), Int(floor(dr.y + 0.1)))
			if let s = belts[k] {
				drops[i].x += Double(s) * speed * dt
				drops[i].vx = 0
			}
		}
		if !dead && inVehicle == nil && pb.onGround {
			let k: Int = PowerSim.cellKey(0, Int(floor(pb.x)), Int(floor(pb.y + 0.1)))
			if let s = belts[k] { pb.x += Double(s) * speed * 0.8 * dt }
		}
		for m in mobs where m.hp > 0 && m.b.onGround && !m.def.flying {
			let k: Int = PowerSim.cellKey(0, Int(floor(m.b.x)), Int(floor(m.b.y + 0.1)))
			if let s = belts[k] { m.b.x += Double(s) * speed * 0.8 * dt }
		}
	}

	/// The devices' settings and charge for the save (wiring is saved with each chunk)
	var powerDebugLine: String {
		let sim: PowerSim = power
		var short: Int = 0
		for n in sim.pnets where n.short { short += 1 }
		var on: Int = 0
		for n in sim.snets where n.on { on += 1 }
		return joinText(String(sim.devs.count), " devices live (", String(world.devs.count), " placed) · ", String(sim.pnets.count), " power lines (", String(short), " short) · ", String(sim.snets.count), " pulse lines (", String(on), " on) · rebuilt ", String(sim.rebuilds), "x")
	}

	/// Debug: one of every Sparkworks part, and plenty of wire
	func debugPowerKit() {
		let parts: [Tile] = [.crankGen, .solarPanel, .fuelGen, .waterWheel, .emberDynamo, .battery, .accumulator, .powerSwitch, .breaker, .powerMeter,
							 .lever, .pushButton, .pressurePlate, .pulseTimer, .repeater, .inverter, .logicGate, .motionSensor, .daySensor, .weatherSensor,
							 .itemSensor, .proximitySensor, .gateClosed, .lampOff, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .signalLight]
		for g in [Gadget.powerCable, .pulseWire, .pulseWireB] { giveItem(.gadget(g), 250) }
		giveItem(.gadget(.wireSnips), 1)
		giveItem(.gadget(.probe), 1)
		for t in parts { giveItem(.block(t), 8) }
		say("Power kit: every Sparkworks part, wire, snips and a probe.", 2.5)
		bumpHUD()
	}

	func debugChargeAll() {
		for (_, d) in world.devs {
			let c: Double = PowerSpec.capacity(d.tile)
			if c > 0 { d.charge = c }
			if d.tile == .fuelGen || d.tile == .emberDynamo { d.charge = 3600 }
		}
		say("Batteries charged, generators fuelled.", 1.5)
	}

	func powerSave() -> [PowerDevSave]? {
		if world.devs.isEmpty { return nil }
		var out: [PowerDevSave] = []
		for (k, d) in world.devs {
			out.append(PowerDevSave(d: k.d, x: k.x, y: k.y, t: Int(d.tile.rawValue), dir: d.dir, mode: d.mode, param: d.param, charge: d.charge, on: d.on, flag: d.flag, item: d.item))
		}
		out.sort { $0.d != $1.d ? $0.d < $1.d : ($0.x != $1.x ? $0.x < $1.x : $0.y < $1.y) }
		return out
	}

	// MARK: chests as machine storage (27 stacks, stacked up to each item's limit)

	func chestCount(_ items: [Stack], _ it: Item) -> Int {
		var n: Int = 0
		for s in items where s.item == it { n += s.count }
		return n
	}

	/// Adds a stack to a chest's contents; returns how many did not fit
	func chestAdd(_ items: inout [Stack], _ st: Stack) -> Int {
		var left: Int = st.count
		let ms: Int = st.item.maxStack
		if ms > 1 {
			for i in 0..<items.count where left > 0 && items[i].item == st.item && items[i].extra == st.extra && items[i].count < ms {
				let put: Int = min(ms - items[i].count, left)
				items[i].count += put
				left -= put
			}
		}
		while left > 0 && items.count < 27 {
			let put: Int = min(ms, left)
			items.append(Stack(item: st.item, count: put, extra: st.extra))
			left -= put
		}
		return left
	}

	func chestTake(_ items: inout [Stack], _ it: Item, _ n: Int) {
		var left: Int = n
		var i: Int = items.count - 1
		while i >= 0 && left > 0 {
			if items[i].item == it {
				let take: Int = min(items[i].count, left)
				items[i].count -= take
				left -= take
				if items[i].count <= 0 { items.remove(at: i) }
			}
			i -= 1
		}
	}
}

// MARK: - Sparkworks: wiring by touch, the probe, tapping devices

/// The network the probe last looked at, lit up on screen for a few seconds
struct PowerInspect {
	var layer: Int
	var cells: [IntPair]
	var t: Double
}

struct PanelLine {
	var text: String
	var color: UInt32
}

extension Game {
	/// A wiring tool or the probe is in hand (wiring is drawn in full)
	var holdingWiringTool: Bool {
		if case .gadget(let g)? = heldItem { return g.wiring || g == .probe }
		return false
	}

	/// A line on the HUD while a wiring tool is in hand
	var wiringHint: String? {
		guard case .gadget(let g)? = heldItem else { return nil }
		switch g {
		case .powerCable: return "Drag to lay power cable through generators, batteries and machines"
		case .pulseWire, .pulseWireB: return "Drag to lay pulse wire from switches and sensors to what they control"
		case .wireSnips: return "Drag over wire to take it back up"
		case .probe: return "Tap a device to set it up, or a wire to see its network"
		default: return nil
		}
	}

	var holdingWireSpool: Bool {
		if case .gadget(let g)? = heldItem { return g.wiring }
		return false
	}

	/// Dragging with a spool lays wire cell by cell (a fast drag leaves no gaps); snips take it back up
	func useWiring(_ g: Gadget, _ pressed: Bool) {
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		let here: IntPair = IntPair(x: tx, y: ty)
		guard let last = wireLast, !pressed else {
			wireLast = here
			_ = wireCell(g, tx, ty)
			return
		}
		if last == here { return }
		var x: Int = last.x
		var y: Int = last.y
		var n: Int = 0
		while (x != tx || y != ty) && n < 64 {
			// step along whichever way is further to go, so a diagonal drag makes a staircase
			if abs(tx - x) >= abs(ty - y) { x += tx > x ? 1 : -1 } else { y += ty > y ? 1 : -1 }
			n += 1
			if !wireCell(g, x, y) { break }
		}
		wireLast = IntPair(x: x, y: y)
	}

	/// Lays (or with snips, removes) wire on one cell; false stops the drag (out of reach or of wire)
	func wireCell(_ g: Gadget, _ x: Int, _ y: Int) -> Bool {
		let dx: Double = Double(x) + 0.5 - pb.x
		let dy: Double = Double(y) + 0.5 - (pb.y - pb.h * 0.6)
		let r: Double = reachDistance() + 2.5
		if dx * dx + dy * dy > r * r || !world.isLoaded(x) { return false }
		let cur: UInt8 = world.wireAt(x, y)
		if g == .wireSnips {
			if cur == 0 { return true }
			if !isCreative {
				let back: [Gadget] = [.powerCable, .pulseWire, .pulseWireB]
				for layer in 0..<3 where cur & Wire.bit(layer) != 0 { giveItem(.gadget(back[layer]), 1) }
			}
			world.setWire(x, y, 0)
			spawnParticles(Double(x) + 0.5, Double(y) + 0.5, 0xD2793A, 2, 1.5, 0.25, 10)
			wireSound()
			return true
		}
		let bit: UInt8 = Wire.bit(g.wireLayer)
		if cur & bit != 0 { return true }
		// a logic part's own cell takes no pulse wire: its sides are its inputs and its output
		if g.wireLayer > 0 && powerRole(world.tile(x, y)) == .logic { return true }
		if !isCreative {
			guard let st = heldStack, st.item == .gadget(g), st.count > 0 else {
				say(joinText("Out of ", g.name.lowercased(), "."), 1.5)
				return false
			}
			inv.removeAt(sel, 1)
		}
		world.setWire(x, y, cur | bit)
		wireSound()
		bumpHUD()
		return true
	}

	func wireSound() {
		if clock - wireSoundT > 0.06 {
			wireSoundT = clock
			sfx(.tap, 0.3)
		}
	}

	// MARK: the probe

	/// The probe on a device opens its panel; on a wire it lights up the whole network and says how it is
	func probeAt(_ wx: Double, _ wy: Double) {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		if let d = world.powerDev(tx, ty), world.tile(tx, ty).isPower {
			openPowerPanel(d)
			let layer: Int = d.pnet >= 0 ? 0 : (d.snets[0] >= 0 ? 1 : (d.snets[1] >= 0 ? 2 : -1))
			if layer >= 0 { inspectNet(layer, tx, ty) }
			return
		}
		let bits: UInt8 = world.wireAt(tx, ty)
		if bits == 0 {
			say("Nothing wired here. Tap a device or a wire.", 1.5)
			return
		}
		// several layers on one cell: each tap shows the next
		var layer: Int = -1
		let start: Int = (inspect?.cells.contains(IntPair(x: tx, y: ty)) ?? false) ? ((inspect?.layer ?? -1) + 1) : 0
		for k in 0..<3 {
			let l: Int = (start + k) % 3
			if bits & Wire.bit(l) != 0 { layer = l; break }
		}
		if layer < 0 { return }
		inspectNet(layer, tx, ty)
		say(netSummary(layer, tx, ty), 4.0)
		sfx(.tap, 0.5)
	}

	/// Lights up every cell of one network
	func inspectNet(_ layer: Int, _ x: Int, _ y: Int) {
		let bit: UInt8 = Wire.bit(layer)
		var seen: Set<IntPair> = [IntPair(x: x, y: y)]
		var stack: [IntPair] = [IntPair(x: x, y: y)]
		var cells: [IntPair] = []
		while let c = stack.popLast(), cells.count < 4000 {
			cells.append(c)
			if !conducts(layer, c.x, c.y) && !(c.x == x && c.y == y) { continue }
			for side in 0..<4 {
				let n: IntPair = IntPair(x: c.x + sideDX[side], y: c.y + sideDY[side])
				if seen.contains(n) || world.wireAt(n.x, n.y) & bit == 0 { continue }
				seen.insert(n)
				stack.append(n)
			}
		}
		inspect = PowerInspect(layer: layer, cells: cells, t: 8.0)
	}

	/// One line about a network: what it makes, uses and stores, or whether a pulse is on
	func netSummary(_ layer: Int, _ x: Int, _ y: Int) -> String {
		let sim: PowerSim = power
		guard let i = sim.cellNet[PowerSim.cellKey(layer, x, y)] else { return "This wire is not connected to anything yet." }
		if layer == 0 {
			if i >= sim.pnets.count { return "Power cable" }
			let n: PowerNet = sim.pnets[i]
			var s: String = joinText("Power line: makes ", sparks(n.made), ", uses ", sparks(n.used))
			if n.cap > 0 { s = joinText(s, ", stored ", String(Int(n.stored)), "/", String(Int(n.cap))) }
			if n.short { s = joinText(s, ". NOT ENOUGH POWER: machines want ", sparks(n.asked)) }
			if n.devs.isEmpty { s = "Power cable with nothing on it yet." }
			return s
		}
		if i >= sim.snets.count { return "Pulse wire" }
		let n: PulseNet = sim.snets[i]
		let col: String = layer == 1 ? "Amber" : "Teal"
		return joinText(col, " pulse line: ", n.on ? "ON" : "off", " · ", String(n.sources.count), " sending, ", String(n.readers.count + n.followers.count), " listening")
	}

	func sparks(_ v: Double) -> String { return String(format: "%.1f sparks/s", v) }

	// MARK: tapping a device

	/// A device does its own thing when tapped: levers flip, buttons press, a crank winds up, a
	/// breaker resets, fuel goes in; anything else opens its panel
	func usePowerDevice(_ x: Int, _ y: Int, _ t: Tile) {
		guard let d = world.powerDev(x, y) else { return }
		// wearing the suit, a tap on a battery fills the suit from it
		if (t == .battery || t == .accumulator) && suit.worn && chargeSuitFrom(d) { return }
		switch t {
		case .lever:
			d.on.toggle()
			setOut(d, d.on)
			sfx(.tap, at: Double(x), 0.8)
			spawnParticles(Double(x) + 0.5, Double(y) + 0.6, 0xC8CCD4, 2, 1.0, 0.2, 6)
		case .pushButton:
			d.timer = max(0.25, d.param)
			setOut(d, true)
			sfx(.tap, at: Double(x), 0.8)
		case .crankGen:
			// winding by hand is work: a little hunger for every turn
			let cap: Double = PowerSpec.capacity(.crankGen)
			if d.charge >= cap - 0.5 {
				say("The flywheel is spinning as fast as it can.", 1.2)
				return
			}
			d.charge = min(cap, d.charge + 15)
			if !isCreative { hunger = max(0, hunger - 0.08) }
			sfx(.swingLight, at: Double(x), 0.5)
			spawnParticles(Double(x) + 0.8, Double(y) + 0.2, 0xFFC020, 3, 2.0, 0.3, 6)
			floatText(joinText(String(Int(d.charge)), " / ", String(Int(cap))), Double(x) + 0.5, Double(y) - 0.4, 0xFFD060)
		case .breaker:
			if !d.on {
				d.on = true
				d.flag = false
				world.powerRev &+= 1
				say("Breaker reset. If the line is still overloaded it will trip again.", 2.0)
			} else {
				d.on = false
				world.powerRev &+= 1
				say("Breaker opened: the line is cut here.", 1.5)
			}
			sfx(.tap, at: Double(x), 0.8)
		case .powerSwitch:
			if d.snets[0] >= 0 || d.snets[1] >= 0 {
				say("This switch follows its pulse wire.", 1.5)
			} else {
				d.on.toggle()
				world.powerRev &+= 1
				sfx(.tap, at: Double(x), 0.8)
			}
		case .fuelGen, .emberDynamo:
			if let it = heldItem, fuelSeconds(it, dynamo: t == .emberDynamo) > 0 {
				let secs: Double = fuelSeconds(it, dynamo: t == .emberDynamo)
				if d.charge + secs > 3600 {
					say("It is full of fuel.", 1.2)
					return
				}
				d.charge += secs
				if !isCreative { inv.removeAt(sel, 1) }
				sfx(.place, at: Double(x), 0.5)
				floatText(joinText("Fuel: ", fuelText(d.charge)), Double(x) + 0.5, Double(y) - 0.4, 0xFFB050)
				bumpHUD()
			} else {
				openPowerPanel(d)
			}
		case .gateClosed, .gateOpen:
			if pulseHere(d) != nil {
				say("This gate follows its pulse wire.", 1.5)
			} else if !d.powered {
				say("The gate needs power to move.", 1.5)
			} else {
				d.on.toggle()
				applyMachine(d)
			}
		default:
			openPowerPanel(d)
		}
		bumpHUD()
	}

	func fuelText(_ s: Double) -> String {
		if s >= 60 { return joinText(String(Int(s / 60)), " min ", String(Int(s.truncatingRemainder(dividingBy: 60))), " s") }
		return joinText(String(Int(s)), " s")
	}

	func openPowerPanel(_ d: PowerDev) {
		powerAt = d.key
		showPower = true
		sfx(.tap, 0.6)
		bumpHUD()
	}

	var powerDevOpen: PowerDev? {
		guard let k = powerAt else { return nil }
		return world.devs[k]
	}

	// MARK: the device panel

	func modeNames(_ t: Tile) -> [String] {
		switch t {
		case .logicGate: return ["AND", "OR", "XOR", "NAND", "NOR"]
		case .pulseTimer: return ["CLOCK", "DELAY"]
		case .pressurePlate: return ["ANYONE", "PLAYER", "CREATURES"]
		case .motionSensor: return ["ANYTHING", "CREATURES", "PLAYER"]
		case .proximitySensor: return ["PLAYER", "HOSTILE", "ANY CREATURE", "ANYONE"]
		case .daySensor: return ["ON BY DAY", "ON AT NIGHT"]
		case .weatherSensor: return ["RAIN/SNOW", "STORM", "STRONG WIND", "SEVERE"]
		case .itemSensor: return ["ANY ITEM", "16+", "64+", "FULL"]
		case .breaker: return PowerSpec.breakerLimits.map { String(Int($0)) }
		default: return []
		}
	}

	func modeTitle(_ t: Tile) -> String {
		switch t {
		case .logicGate: return "Gate type (inputs at the two sides, output where the arrow points)"
		case .pulseTimer: return "Mode"
		case .breaker: return "Trips above (sparks per second asked)"
		case .itemSensor: return "On when the chest beside it holds"
		default: return "Responds to"
		}
	}

	/// The number a device's panel sets: its label, range and step
	func paramSpec(_ d: PowerDev) -> (String, Double, Double, Double)? {
		switch d.tile {
		case .pushButton: return ("Pulse length (s)", 0.25, 5, 0.25)
		case .pulseTimer: return (d.mode == 0 ? "Period (s)" : "Delay (s)", 0.1, 10, 0.1)
		case .repeater: return ("Delay (steps of 0.05 s)", 1, 4, 1)
		case .motionSensor, .proximitySensor: return ("Range (blocks)", 2, 12, 1)
		default: return nil
		}
	}

	func setPowerMode(_ d: PowerDev, _ m: Int) {
		d.mode = m
		if d.role == .logic {
			d.pend.removeAll()
			if d.li >= 0 { power.queue.insert(d.li) }
		}
		if d.tile == .breaker { world.powerRev &+= 1 }
		bumpHUD()
	}

	func stepPowerParam(_ d: PowerDev, _ dir: Double) {
		guard let p = paramSpec(d) else { return }
		d.param = clampD(((d.param + dir * p.3) / p.3).rounded() * p.3, p.1, p.2)
		bumpHUD()
	}

	/// Turns a device a quarter (conveyors and crafters only turn round)
	func rotatePower(_ d: PowerDev) {
		if d.tile == .conveyor || d.tile == .autoCrafter {
			d.dir = d.dir == 0 ? 2 : 0
		} else {
			d.dir = (d.dir + 1) % 4
		}
		d.pend.removeAll()
		world.powerRev &+= 1
		bumpHUD()
	}

	/// What the panel says about a device and the line it is on
	func powerPanelLines(_ d: PowerDev) -> [PanelLine] {
		var out: [PanelLine] = []
		let good: UInt32 = 0x8AF0B0
		let bad: UInt32 = 0xFF8060
		let plain: UInt32 = 0xE8E4D8
		switch d.role {
		case .generator:
			switch d.tile {
			case .crankGen:
				out.append(PanelLine(text: joinText("Flywheel: ", String(Int(d.charge)), " / 60 sparks. Tap it to crank."), color: plain))
			case .fuelGen, .emberDynamo:
				let what: String = d.tile == .emberDynamo ? "ember bars or ember ore" : "coal, logs, planks or sticks"
				out.append(PanelLine(text: joinText("Fuel: ", fuelText(d.charge), ". Tap it holding ", what, " to add more."), color: d.charge > 0 ? plain : bad))
				out.append(PanelLine(text: "It only burns fuel for power that is actually needed.", color: plain))
			case .solarPanel:
				out.append(PanelLine(text: "Makes up to 4 sparks/s in full sun under open sky; clouds and night cut it.", color: plain))
			case .waterWheel:
				out.append(PanelLine(text: "Turns with water around it (up to 6 sparks/s), more in the rain.", color: plain))
			case .windTurbine:
				let k: String = deviceKey(DeviceSpot(x: d.x, y: d.y, t: .windTurbine))
				out.append(PanelLine(text: joinText("Charge: ", String(Int(weather.store[k] ?? 0)), " / 100 (the wind fills it)."), color: plain))
			default:
				break
			}
			out.append(PanelLine(text: joinText("Making ", sparks(d.made)), color: d.made > 0 ? good : plain))
		case .storage:
			let c: Double = PowerSpec.capacity(d.tile)
			out.append(PanelLine(text: joinText("Charge: ", String(Int(d.charge)), " / ", String(Int(c)), " sparks (", String(Int(100 * d.charge / max(1, c))), "%)"), color: d.charge > 1 ? good : plain))
			out.append(PanelLine(text: joinText("Charges and gives back up to ", String(Int(PowerSpec.rate(d.tile))), " sparks/s. Taken down, it loses its charge."), color: plain))
		case .conductor:
			if d.tile == .breaker {
				if d.flag && !d.on { out.append(PanelLine(text: "TRIPPED: too much was asked of this line. Tap it to reset.", color: bad)) }
				else { out.append(PanelLine(text: d.on ? "Closed: power passes." : "Open: the line is cut here.", color: d.on ? good : bad)) }
			} else {
				out.append(PanelLine(text: d.on ? "On: power passes." : "Off: the line is cut here.", color: d.on ? good : bad))
			}
		case .source, .sensor, .logic:
			out.append(PanelLine(text: joinText("Sending: ", d.out ? "ON" : "off"), color: d.out ? good : plain))
			if d.burnT > 0 { out.append(PanelLine(text: "Burnt out for a moment: it was flipping too fast (a loop with no delay?)", color: bad)) }
			if d.role == .logic {
				let back: Int = (d.dir + 2) % 4
				if d.tile == .logicGate {
					let a: String = (portOn(d, (d.dir + 1) % 4) ?? false) ? "ON" : "off"
					let b: String = (portOn(d, (d.dir + 3) % 4) ?? false) ? "ON" : "off"
					out.append(PanelLine(text: joinText("Inputs: ", a, " and ", b), color: plain))
				} else if let i = portOn(d, back) {
					out.append(PanelLine(text: joinText("Input: ", i ? "ON" : "off"), color: plain))
				} else if d.tile != .pulseTimer || d.mode == 1 {
					out.append(PanelLine(text: "No pulse wire at its back (the input).", color: bad))
				}
			}
		case .machine:
			let wants: Double = PowerSpec.draw(d.tile)
			if !d.enabled { out.append(PanelLine(text: "Off: its pulse wire is off.", color: plain)) }
			else if d.powered { out.append(PanelLine(text: joinText("Running on ", sparks(wants)), color: good)) }
			else { out.append(PanelLine(text: joinText("NO POWER: it needs ", sparks(wants)), color: bad)) }
			out.append(PanelLine(text: machineHelp(d.tile), color: plain))
		case .meter:
			out.append(PanelLine(text: "Reads the power line it sits on.", color: plain))
		case .indicator:
			out.append(PanelLine(text: joinText("Shows its pulse wire: ", (pulseHere(d) ?? false) ? "ON" : "off"), color: plain))
		case .none:
			break
		}
		if d.role == .sensor && !d.powered { out.append(PanelLine(text: "Sensors need a little power (0.5 sparks/s) to work.", color: bad)) }
		// the power line it is on
		let usesPower: Bool = d.role == .generator || d.role == .storage || d.role == .machine || d.role == .sensor || d.role == .meter
		if usesPower {
			if d.pnet >= 0 && d.pnet < power.pnets.count {
				let n: PowerNet = power.pnets[d.pnet]
				out.append(PanelLine(text: joinText("Line: makes ", sparks(n.made), " · uses ", sparks(n.used), n.cap > 0 ? joinText(" · stored ", String(Int(n.stored)), "/", String(Int(n.cap))) : ""), color: plain))
				if n.short { out.append(PanelLine(text: joinText("NOT ENOUGH POWER on this line: machines want ", sparks(n.asked)), color: bad)) }
			} else {
				out.append(PanelLine(text: "Not on a power line: lay power cable through it.", color: bad))
			}
		}
		if let p = pulseHere(d), d.role != .logic {
			out.append(PanelLine(text: joinText("Pulse wire here: ", p ? "ON" : "off"), color: p ? good : plain))
		}
		return out
	}

	func machineHelp(_ t: Tile) -> String {
		switch t {
		case .lampOff, .lampOn: return "Lights up while powered (and while its pulse wire is on, if it has one)."
		case .gateClosed, .gateOpen: return "Opens while its pulse wire is on; with none, tap it. Needs power to move."
		case .arcTrap: return "Zaps whatever stands on it, once a second."
		case .autoDrill: return "Bores out the block it faces (what an iron pickaxe could). Drops land as if mined."
		case .exoStation: return "Builds suits; charges a suit worn close by from this line (10 a second, only while it charges)."
		case .conveyor: return "Carries items (and anyone) along the way the arrow points."
		case .collector: return "Draws loose items within two blocks into a chest beside it."
		case .autoCrafter: return "Makes its recipe from the chest behind it into the chest in front, every 2 s."
		case .sumpPump: return "Drains water within four blocks, into a rain barrel or cistern beside it if there is one."
		default: return ""
		}
	}

	/// Recipes an auto crafter can make
	func crafterRecipes() -> [Recipe] {
		return RecipeBook.all.filter { crafterCan($0.station) && $0.modStation == nil }
	}

	func updatePowerUI(_ dt: Double) {
		if var i = inspect {
			i.t -= dt
			inspect = i.t > 0 ? i : nil
		}
		if showPower, let k = powerAt, world.devs[k] == nil {
			showPower = false
			powerAt = nil
			bumpHUD()
		}
	}
}

// MARK: - Sparkworks drawing

extension WorldRenderer {
	/// Wiring over the tiles: copper power cable (bright when the line has power, red flashes when it is
	/// short), and thinner pulse wire in amber and teal that glows while on. Shown in full while a
	/// wiring tool is in hand, and otherwise as the settings say.
	static func drawWiring(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let mode: Int = g.settings.showWires
		let tool: Bool = g.holdingWiringTool
		if mode == 0 && !tool && g.inspect == nil { return }
		let faint: Bool = !tool && mode == 2
		let sim: PowerSim = g.power
		let x0: Int = Int(floor(v.left)) - 1
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 1
		let y0: Int = max(0, Int(floor(v.top)) - 1)
		let y1: Int = min(g.world.H - 1, Int(ceil(v.top + v.hTiles)) + 1)
		let tp: Double = v.tp
		var paths: [Path] = [Path(), Path(), Path(), Path(), Path(), Path(), Path()]
		var used: [Bool] = [false, false, false, false, false, false, false]
		var cx: Int = floorDiv(x0, chunkW)
		let blink: Bool = Int(g.clock * 3.0) % 2 == 0
		while cx <= floorDiv(x1, chunkW) {
			defer { cx += 1 }
			guard let c = g.world.chunk(cx), c.wireCount > 0 else { continue }
			let H: Int = c.H
			let ax: Int = max(x0, c.x0)
			let bx: Int = min(x1, c.x0 + chunkW - 1)
			if ax > bx { continue }
			for x in ax...bx {
				let base: Int = (x - c.x0) * H
				for y in y0...y1 {
					let b: UInt8 = c.wires[base + y]
					if b == 0 { continue }
					for layer in 0..<3 where b & Wire.bit(layer) != 0 {
						let off: Double = layer == 0 ? 0 : (layer == 1 ? -0.2 : 0.2)
						let px: Double = v.sx(Double(x) + 0.5 + off)
						let py: Double = v.sy(Double(y) + 0.5 + off)
						var slot: Int = layer == 0 ? 0 : (layer == 1 ? 2 : 4)
						if let n = sim.cellNet[PowerSim.cellKey(layer, x, y)] {
							if layer == 0, n < sim.pnets.count {
								let net: PowerNet = sim.pnets[n]
								if net.short && blink { slot = 6 } else if net.made > 0 || net.stored > 1 { slot = 1 }
							} else if layer > 0, n < sim.snets.count, sim.snets[n].on {
								slot += 1
							}
						}
						let bit: UInt8 = Wire.bit(layer)
						// a stub to each wired neighbour to the right and below (each joint drawn once)
						if g.world.wireAt(x + 1, y) & bit != 0 {
							paths[slot].move(to: mkPoint(px, py))
							paths[slot].addLine(to: mkPoint(px + tp, py))
						}
						if g.world.wireAt(x, y + 1) & bit != 0 {
							paths[slot].move(to: mkPoint(px, py))
							paths[slot].addLine(to: mkPoint(px, py + tp))
						}
						let r: Double = layer == 0 ? tp * 0.11 : tp * 0.08
						paths[slot].addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2))
						used[slot] = true
					}
				}
			}
		}
		let a: Double = faint ? 0.35 : 1.0
		let cols: [UInt32] = [0x8A5A30, 0xFFA040, 0x6A5010, 0xFFD040, 0x1A6A66, 0x50FFF0, 0xFF4030]
		let widths: [Double] = [0.16, 0.16, 0.09, 0.11, 0.09, 0.11, 0.16]
		for i in 0..<7 where used[i] {
			ctx.stroke(paths[i], with: .color(Color(hex: 0x14100C, alpha: 0.7 * a)), lineWidth: tp * widths[i] + 2.0)
			ctx.stroke(paths[i], with: .color(Color(hex: cols[i], alpha: a)), lineWidth: tp * widths[i])
		}
		// the network the probe is looking at
		if let ins = g.inspect {
			let pulse: Double = 0.35 + 0.25 * sin(g.clock * 6.0)
			let col: UInt32 = ins.layer == 0 ? 0xFFC060 : (ins.layer == 1 ? 0xFFE060 : 0x80FFF0)
			var hp: Path = Path()
			for c in ins.cells where v.visible(Double(c.x), Double(c.y), 2) {
				hp.addRect(v.rect(Double(c.x) + 0.12, Double(c.y) + 0.12, 0.76, 0.76))
			}
			ctx.stroke(hp, with: .color(Color(hex: col, alpha: pulse * min(1.0, ins.t))), lineWidth: 2)
		}
	}

	/// What each device in view is doing: lever handles, lights, arrows on parts that point a way,
	/// charge bars, moving parts, and a red bolt on a machine that wants power and has none
	static func drawPowerDevices(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let sim: PowerSim = g.power
		if sim.devs.isEmpty { return }
		let tp: Double = v.tp
		let blink: Bool = Int(g.clock * 2.5) % 2 == 0
		var dark: Path = Path()
		var amber: Path = Path()
		var teal: Path = Path()
		var red: Path = Path()
		var green: Path = Path()
		var white: Path = Path()
		var fire: Path = Path()
		for d in sim.devs {
			if !v.visible(Double(d.x), Double(d.y), 2) { continue }
			let L: Double = v.sx(Double(d.x))
			let T: Double = v.sy(Double(d.y))
			let cx: Double = L + tp * 0.5
			let cy: Double = T + tp * 0.5
			func led(_ on: Bool, _ px: Double, _ py: Double, _ onPath: inout Path) {
				let r: Double = max(1.5, tp * 0.07)
				if on { onPath.addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2)) } else { dark.addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2)) }
			}
			func arrow(_ dir: Int, _ path: inout Path) {
				let ax: Double = Double(sideDX[dir])
				let ay: Double = Double(sideDY[dir])
				let s: Double = tp * 0.22
				let tipX: Double = cx + ax * tp * 0.34
				let tipY: Double = cy + ay * tp * 0.34
				path.move(to: mkPoint(tipX, tipY))
				path.addLine(to: mkPoint(tipX - ax * s - ay * s, tipY - ay * s + ax * s))
				path.addLine(to: mkPoint(tipX - ax * s + ay * s, tipY - ay * s - ax * s))
				path.closeSubpath()
			}
			switch d.tile {
			case .lever:
				let ang: Double = d.on ? -0.6 : -2.5
				white.move(to: mkPoint(cx, T + tp * 0.7))
				white.addLine(to: mkPoint(cx + cos(ang) * tp * 0.45, T + tp * 0.7 + sin(ang) * tp * 0.45))
				led(d.on, cx + cos(ang) * tp * 0.45, T + tp * 0.7 + sin(ang) * tp * 0.45, &amber)
			case .pushButton:
				if d.out { teal.addRect(mkRect(L + tp * 0.375, T + tp * 0.5, tp * 0.25, tp * 0.25)) }
			case .pressurePlate:
				if d.out { amber.addRect(mkRect(L + tp * 0.15, T + tp * 0.8, tp * 0.7, tp * 0.06)) }
			case .repeater, .inverter, .logicGate, .pulseTimer:
				if d.burnT > 0 { arrow(d.dir, &red) } else if d.out { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
				if d.tile == .logicGate {
					let names: [String] = ["AND", "OR", "XOR", "NAND", "NOR"]
					drawLabel(&ctx, names[clampI(d.mode, 0, 4)], cx, T + tp * 0.12, max(6.0, tp * 0.26), Color(hex: 0xC8F0E8))
				}
				if d.tile == .pulseTimer {
					let a: Double = d.mode == 0 ? g.clock * 3.0 : (d.out ? 0 : 3.14)
					white.move(to: mkPoint(cx, cy))
					white.addLine(to: mkPoint(cx + cos(a) * tp * 0.25, cy + sin(a) * tp * 0.25))
				}
			case .autoDrill:
				if d.enabled && d.powered { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
			case .conveyor, .autoCrafter:
				if d.enabled && d.powered { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
				if d.tile == .conveyor && d.enabled && d.powered {
					let shift: Double = (g.clock * 2.4).truncatingRemainder(dividingBy: 1.0) * (d.dir == 2 ? -1.0 : 1.0)
					for k in 0..<3 {
						var fx: Double = (Double(k) / 3.0 + shift).truncatingRemainder(dividingBy: 1.0)
						if fx < 0 { fx += 1.0 }
						white.addRect(mkRect(L + fx * tp, T + tp * 0.02, max(1.5, tp * 0.06), tp * 0.1))
					}
				}
			case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor:
				led(d.out, L + tp * 0.85, T + tp * 0.15, &teal)
			case .signalLight:
				if g.pulseHere(d) ?? false {
					let glow: Double = tp * 0.32
					teal.addEllipse(in: mkRect(cx - glow, T + tp * 0.4 - glow, glow * 2, glow * 2))
				}
			case .crankGen:
				let spin: Double = g.clock * min(12.0, d.charge * 0.4)
				white.move(to: mkPoint(L + tp * 0.8, T + tp * 0.25))
				white.addLine(to: mkPoint(L + tp * 0.8 + cos(spin) * tp * 0.2, T + tp * 0.25 + sin(spin) * tp * 0.2))
				led(d.made > 0, L + tp * 0.5, T + tp * 0.65, &green)
			case .waterWheel:
				let spin: Double = g.clock * (d.made > 0 ? 1.5 : 0)
				for k in 0..<4 {
					let a: Double = spin + Double(k) * 1.5708
					dark.move(to: mkPoint(cx, cy))
					dark.addLine(to: mkPoint(cx + cos(a) * tp * 0.45, cy + sin(a) * tp * 0.45))
				}
			case .fuelGen, .emberDynamo:
				if d.made > 0 {
					let f: Double = 0.7 + 0.3 * sin(g.clock * 17.0 + Double(d.x))
					fire.addEllipse(in: mkRect(cx - tp * 0.22 * f, T + tp * 0.45, tp * 0.44 * f, tp * 0.3 * f))
				}
				led(d.charge > 0, L + tp * 0.85, T + tp * 0.85, &green)
			case .solarPanel, .windTurbine:
				led(d.made > 0, L + tp * 0.85, T + tp * 0.92, &green)
			case .battery, .accumulator:
				let f: Double = clampD(d.charge / max(1, PowerSpec.capacity(d.tile)), 0, 1)
				let h: Double = tp * 0.6 * f
				if f > 0.01 {
					let col: Path = Path(mkRect(L + tp * 0.32, T + tp * 0.85 - h, tp * 0.36, h))
					ctx.fill(col, with: .color(Color(hex: f > 0.5 ? 0x50E070 : (f > 0.2 ? 0xE8D040 : 0xE05030), alpha: 0.9)))
				}
			case .powerMeter:
				var frac: Double = 0
				var short: Bool = false
				if d.pnet >= 0 && d.pnet < sim.pnets.count {
					let n: PowerNet = sim.pnets[d.pnet]
					frac = n.made > 0 ? clampD(n.used / n.made, 0, 1) : (n.used > 0 ? 1 : 0)
					short = n.short
				}
				let a: Double = 3.4 + frac * 2.6
				white.move(to: mkPoint(cx, T + tp * 0.6))
				white.addLine(to: mkPoint(cx + cos(a) * tp * 0.35, T + tp * 0.6 + sin(a) * tp * 0.35))
				if short { led(true, L + tp * 0.85, T + tp * 0.8, &red) } else { led(true, L + tp * 0.85, T + tp * 0.8, &green) }
			case .powerSwitch:
				let r: CGRect = mkRect(L + tp * 0.375, T + (d.on ? tp * 0.32 : tp * 0.5), tp * 0.25, tp * 0.18)
				if d.on { green.addRect(r) } else { red.addRect(r) }
			case .breaker:
				if d.on { led(true, cx, T + tp * 0.5, &green) } else { led(true, cx, T + tp * 0.5, &red) }
			default:
				break
			}
			// a machine or sensor that wants power and has none
			if (d.role == .machine || d.role == .sensor) && d.enabled && !d.powered && blink {
				let s: Double = tp * 0.18
				red.move(to: mkPoint(cx + s * 0.3, T - s * 2.2))
				red.addLine(to: mkPoint(cx - s * 0.6, T - s * 0.9))
				red.addLine(to: mkPoint(cx + s * 0.2, T - s * 0.9))
				red.addLine(to: mkPoint(cx - s * 0.4, T + s * 0.4))
			}
		}
		let lw: Double = max(1.5, tp * 0.07)
		ctx.stroke(dark, with: .color(Color(hex: 0x1A1A20, alpha: 0.9)), lineWidth: lw)
		ctx.fill(dark, with: .color(Color(hex: 0x1A1A20, alpha: 0.9)))
		ctx.stroke(white, with: .color(Color(hex: 0xE8ECF0)), lineWidth: lw)
		ctx.fill(amber, with: .color(Color(hex: 0xFFC020)))
		ctx.fill(teal, with: .color(Color(hex: 0x50FFF0, alpha: 0.9)))
		ctx.fill(green, with: .color(Color(hex: 0x50F080)))
		ctx.fill(fire, with: .color(Color(hex: 0xFF8A20, alpha: 0.85)))
		ctx.stroke(red, with: .color(Color(hex: 0xFF4030)), lineWidth: lw * 1.3)
		ctx.fill(red, with: .color(Color(hex: 0xFF4030, alpha: 0.8)))
	}
}

// MARK: - Sparkworks panel

/// A device's panel: how it is doing, the line it is on, and its settings
struct PowerPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal

	func pick(_ on: Bool, _ title: String, _ act: @escaping () -> Void) -> some View {
		SmallButton(title: title, color: on ? Color(hex: 0x3A8A7A) : Color(hex: 0x4A4E58), action: act)
	}

	var body: some View {
		let dev: PowerDev? = game.powerDevOpen
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: dev?.tile.name.uppercased() ?? "DEVICE").font(.pixel(17)).foregroundColor(Color(hex: 0x80F0E0))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) {
					game.showPower = false
					game.bumpHUD()
				}
			}
			if let d = dev {
				let lines: [PanelLine] = game.powerPanelLines(d)
				ForEach(0..<lines.count, id: \.self) { i in
					Text(verbatim: lines[i].text).font(.pixel(12, .semibold)).foregroundColor(Color(hex: lines[i].color))
				}
				controls(d)
			}
		}
		.padding(16)
		.background(PixelBox(color: Color(hex: 0x182024)).opacity(0.96))
		.frame(maxWidth: 600)
		.padding(16)
	}

	@ViewBuilder
	func controls(_ d: PowerDev) -> some View {
		let modes: [String] = game.modeNames(d.tile)
		if !modes.isEmpty {
			Text(verbatim: game.modeTitle(d.tile)).font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
				ForEach(0..<modes.count, id: \.self) { i in
					pick(d.mode == i, modes[i]) { game.setPowerMode(d, i) }
				}
			}
		}
		if let p = game.paramSpec(d) {
			HStack(spacing: 8) {
				Text(verbatim: joinText(p.0, ": ", String(format: p.3 < 1 ? "%.2f" : "%.0f", d.param))).font(.pixel(12)).foregroundColor(Color.white)
				SmallButton(title: "-") { game.stepPowerParam(d, -1) }
				SmallButton(title: "+") { game.stepPowerParam(d, 1) }
			}
		}
		if powerDirectional(d.tile) {
			HStack(spacing: 8) {
				Text(verbatim: joinText("Facing: ", ["right", "down", "left", "up"][clampI(d.dir, 0, 3)])).font(.pixel(12)).foregroundColor(Color.white)
				SmallButton(title: "ROTATE") { game.rotatePower(d) }
			}
		}
		if d.tile == .arcTrap {
			pick(d.flag, d.flag ? "HURTS THE PLAYER TOO" : "CREATURES ONLY") {
				d.flag.toggle()
				game.bumpHUD()
			}
		}
		if d.tile == .autoCrafter {
			let list: [Recipe] = game.crafterRecipes()
			let cur: String = (d.item >= 0 && d.item < RecipeBook.all.count) ? RecipeBook.all[d.item].out.name : "nothing yet"
			Text(verbatim: joinText("Making: ", cur, " (chest behind = ingredients, chest in front = results)")).font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
					ForEach(0..<list.count, id: \.self) { i in
						pick(list[i].id == d.item, joinText(list[i].out.name, list[i].outCount > 1 ? joinText(" x", String(list[i].outCount)) : "")) {
							d.item = list[i].id
							d.work = 0
							game.bumpHUD()
						}
					}
				}
			}
			.frame(maxHeight: 220)
		}
	}
}

// ===== p28_mods =====

// MARK: - Mods: what a player-made mod is made of
//
// A mod is one JSON file in Documents/PixelRealmMods: who made it and the custom blocks, items,
// creatures, shots, recipes, loot tables, ores and structures it adds. Nothing in a mod is code: every
// behaviour is picked from what the game already does, and every number is held to a safe range when
// the mod is read. `ModRuntime` turns the mods a world uses into ordinary game content (tiles, items,
// creatures, recipes), so custom content is mined, fought, crafted, drawn and saved by the same code
// as everything else.

extension KeyedDecodingContainer {
	/// The value under a key, or `d` when the key is missing or holds something unreadable
	func val<T: Decodable>(_ k: Key, _ d: T) -> T {
		return (try? decodeIfPresent(T.self, forKey: k)) ?? d
	}

	/// A list where entries that cannot be read are left out (and counted in `skipped`)
	func list<T: Decodable>(_ k: Key, _ skipped: inout Int) -> [T] {
		guard let raw = try? decodeIfPresent([Lenient<T>].self, forKey: k) else { return [] }
		var out: [T] = []
		for e in raw {
			if let v = e.value { out.append(v) } else { skipped += 1 }
		}
		return out
	}
}

/// One entry of a list that may fail to decode without spoiling the rest of the list
struct Lenient<T: Decodable>: Decodable {
	let value: T?
	init(from decoder: Decoder) throws {
		value = try? T(from: decoder)
	}
}

/// Limits that keep a mod from hurting the game: how much a mod may hold, how many custom creatures
/// may be about at once, how big art and structures may be. Numbers inside content have their own
/// ranges (see `ModRange`), wider when a mod is set to sandbox mode.
enum ModLimits {
	static let maxMods: Int = 12
	/// custom blocks across every mod a world uses (each takes one of the reserved tile numbers)
	static let blockSlots: Int = 64
	static let maxBlocks: Int = 48
	static let maxItems: Int = 120
	static let maxMobs: Int = 40
	static let maxShots: Int = 16
	static let maxRecipes: Int = 240
	static let maxLoot: Int = 40
	static let maxOres: Int = 16
	static let maxStructures: Int = 16
	static let maxStructW: Int = 48
	static let maxStructH: Int = 32
	static let maxMobArt: Int = 32
	static let maxFrames: Int = 4
	/// custom creatures alive at once (spawning stops at this many; test spawning too)
	static let maxActiveMobs: Int = 24
	/// ores and structures one world generates, across all its mods (keeps new chunks quick to make)
	static let maxWorldOres: Int = 32
	static let maxWorldStructures: Int = 32
	/// shots fired by custom creatures and weapons that may be in the air at once
	static let maxShotsLive: Int = 80
	static let maxEffects: Int = 4
	static let maxAttacks: Int = 4
	static let maxDrops: Int = 8
	static let maxLootEntries: Int = 16
	static let maxCost: Int = 6
	/// phases and ways to summon one creature may have
	static let maxPhases: Int = 6
	static let maxSummons: Int = 3
}

/// The range a number may take: normal play and sandbox mode
struct ModRange {
	var lo: Double
	var hi: Double
	var sandboxHi: Double

	func clamp(_ v: Double, _ sandbox: Bool) -> Double {
		if !v.isFinite { return lo }
		return clampD(v, lo, sandbox ? sandboxHi : hi)
	}

	static let hardness: ModRange = ModRange(lo: 0.05, hi: 40, sandboxHi: 200)
	static let mobHP: ModRange = ModRange(lo: 1, hi: 400, sandboxHi: 20000)
	static let bossHP: ModRange = ModRange(lo: 50, hi: 4000, sandboxHi: 20000)
	static let damage: ModRange = ModRange(lo: 0, hi: 60, sandboxHi: 500)
	static let mobSpeed: ModRange = ModRange(lo: 0, hi: 8, sandboxHi: 20)
	static let detect: ModRange = ModRange(lo: 2, hi: 32, sandboxHi: 64)
	static let reach: ModRange = ModRange(lo: 0.5, hi: 6, sandboxHi: 12)
	static let cooldown: ModRange = ModRange(lo: 0.15, hi: 10, sandboxHi: 10)
	static let knock: ModRange = ModRange(lo: 0, hi: 16, sandboxHi: 40)
	static let scale: ModRange = ModRange(lo: 0.5, hi: 2.5, sandboxHi: 4)
	static let shotSpeed: ModRange = ModRange(lo: 4, hi: 60, sandboxHi: 90)
	static let gravity: ModRange = ModRange(lo: 0, hi: 40, sandboxHi: 60)
	static let defense: ModRange = ModRange(lo: 0, hi: 12, sandboxHi: 40)
	static let toolSpeed: ModRange = ModRange(lo: 0.3, hi: 30, sandboxHi: 200)
	static let heal: ModRange = ModRange(lo: 0, hi: 40, sandboxHi: 400)
	static let seconds: ModRange = ModRange(lo: 0, hi: 300, sandboxHi: 1800)
	static let radius: ModRange = ModRange(lo: 0.5, hi: 6, sandboxHi: 12)
	static let jump: ModRange = ModRange(lo: 0, hi: 20, sandboxHi: 30)
}

/// Pixel art stored in a mod: width, height and RGBA bytes, row by row (alpha 0 is see-through)
struct ModPixels: Codable, Equatable {
	var w: Int
	var h: Int
	var rgba: Data
	/// drawn with a dark outline in the game (nil: the usual for what it is: creatures and items yes,
	/// blocks no)
	var outline: Bool? = nil

	init(w: Int, h: Int) {
		self.w = max(1, w)
		self.h = max(1, h)
		self.rgba = Data(count: self.w * self.h * 4)
	}

	init(buf: PixelBuf) {
		self.init(w: buf.w, h: buf.h)
		for y in 0..<h {
			for x in 0..<w { setARGB(x, y, buf.px[y * buf.w + x]) }
		}
	}

	/// Big enough to draw on, small enough to stay cheap, and the bytes match the size
	var valid: Bool { return w >= 1 && h >= 1 && w <= 64 && h <= 64 && rgba.count == w * h * 4 }

	/// The pixel as 0xAARRGGBB (0 outside the picture)
	func argb(_ x: Int, _ y: Int) -> UInt32 {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return 0 }
		let i: Int = (y * w + x) * 4
		let a: UInt32 = UInt32(rgba[i + 3])
		if a < 128 { return 0 }
		let r: UInt32 = UInt32(rgba[i])
		let g: UInt32 = UInt32(rgba[i + 1])
		let b: UInt32 = UInt32(rgba[i + 2])
		return 0xFF000000 | (r << 16) | (g << 8) | b
	}

	mutating func setARGB(_ x: Int, _ y: Int, _ c: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return }
		let i: Int = (y * w + x) * 4
		let on: Bool = (c >> 24) != 0
		rgba[i] = UInt8((c >> 16) & 0xFF)
		rgba[i + 1] = UInt8((c >> 8) & 0xFF)
		rgba[i + 2] = UInt8(c & 0xFF)
		rgba[i + 3] = on ? 255 : 0
	}

	/// The picture as a game pixel buffer
	func buf() -> PixelBuf {
		var b = PixelBuf(w: w, h: h)
		for y in 0..<h {
			for x in 0..<w { b.px[y * w + x] = argb(x, y) }
		}
		return b
	}

	var isBlank: Bool {
		if !valid { return true }
		var i: Int = 3
		while i < rgba.count {
			if rgba[i] >= 128 { return false }
			i += 4
		}
		return true
	}

	/// The same picture at another size (cropped or padded, anchored to the bottom centre)
	func resized(_ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		let ox: Int = (nw - w) / 2
		let oy: Int = nh - h
		for y in 0..<h {
			for x in 0..<w { o.setARGB(x + ox, y + oy, argb(x, y)) }
		}
		return o
	}
}

// MARK: blocks

enum ModBlockCategory: Int, Codable, CaseIterable {
	case terrain, building, decorative, storage, interactive, machine, light
	var name: String {
		switch self {
		case .terrain: return "Terrain"
		case .building: return "Building"
		case .decorative: return "Decorative"
		case .storage: return "Storage"
		case .interactive: return "Interactive"
		case .machine: return "Machine"
		case .light: return "Light source"
		}
	}
}

enum ModCollision: Int, Codable, CaseIterable {
	case solid, platform, none
	var name: String {
		switch self {
		case .solid: return "Solid"
		case .platform: return "Platform (stand on top)"
		case .none: return "No collision"
		}
	}
}

/// What tapping (or touching) a block does. Doors and switches use a second tile number for their
/// other state (open, lit).
enum ModBlockFunction: Int, Codable, CaseIterable {
	case none, storage, station, lamp, door, healer, bounce, trap, sign
	var name: String {
		switch self {
		case .none: return "Nothing"
		case .storage: return "Storage chest"
		case .station: return "Crafting station"
		case .lamp: return "Light switch"
		case .door: return "Door"
		case .healer: return "Healing shrine"
		case .bounce: return "Jump pad"
		case .trap: return "Damage trap"
		case .sign: return "Sign"
		}
	}
	var help: String {
		switch self {
		case .none: return "An ordinary block."
		case .storage: return "Tap it to store 27 stacks, like a chest."
		case .station: return "Recipes can need it nearby, or it works as a game station."
		case .lamp: return "Tap it to turn its light on and off."
		case .door: return "Tap it to open (walk through) and close."
		case .healer: return "Tap it to heal (rests between uses)."
		case .bounce: return "Throws you up when you land on it."
		case .trap: return "Hurts anything that touches it."
		case .sign: return "Tap it to read its text."
		}
	}
	/// functions that need a second tile number for the other state
	var paired: Bool { return self == .lamp || self == .door }
}

/// What a mod block does when it is built onto a vehicle (cases are only ever appended): nothing
/// special (it is just a block of its weight), or the work of one of the game's vehicle parts, with the
/// block's own picture, its own weight and its own strength
enum ModVehicleRole: Int, Codable, CaseIterable {
	case none, wing, elevator, propeller, jet, rotor, tailRotor, balloon, burner, engine, wheel, track, armor, fuelTank, cockpit, cannon, machineGun
	/// the game part it works as
	var part: PartType? {
		switch self {
		case .none: return nil
		case .wing: return .wing
		case .elevator: return .elevator
		case .propeller: return .airProp
		case .jet: return .jet
		case .rotor: return .rotor
		case .tailRotor: return .tailRotor
		case .balloon: return .envelope
		case .burner: return .burner
		case .engine: return .engine
		case .wheel: return .wheel
		case .track: return .track
		case .armor: return .armor
		case .fuelTank: return .fuelTank
		case .cockpit: return .cockpit
		case .cannon: return .cannon
		case .machineGun: return .autoGun
		}
	}
	var name: String {
		if self == .none { return "Just a block" }
		return part?.name ?? "Just a block"
	}
}

struct ModBlock: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Block"
	var desc: String = ""
	var category: ModBlockCategory = .building
	/// 8 x 8 picture
	var art: ModPixels = ModPixels(w: 8, h: 8)
	/// seconds of mining with bare hands is about hardness x 1.5
	var hardness: Double = 1.0
	var unbreakable: Bool = false
	/// the tool that mines it at full speed (ToolType number)
	var tool: Int = 0
	/// tool tier needed (0: anything can break it)
	var tier: Int = 0
	var collision: ModCollision = .solid
	var transparent: Bool = false
	/// light given off, 0 to 15
	var light: Int = 0
	var dropSelf: Bool = true
	/// what it drops instead of itself (nil with dropSelf off: nothing)
	var drop: Item? = nil
	var dropCount: Int = 1
	/// explosions leave it standing
	var blastProof: Bool = false
	var function: ModBlockFunction = .none
	/// station number (Station) it works as; -1: its own station for this mod's recipes
	var station: Int = -1
	/// heal amount, jump pad strength or trap damage
	var power: Double = 6
	var text: String = ""
	/// on a vehicle: the part it works as, its mass there (0: its block weight), and how strong it is at
	/// that work (lift, thrust, power, toughness: 1 is the game part's own)
	var vehRole: ModVehicleRole = .none
	var vehMass: Double = 0
	var vehPower: Double = 1.0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Block")
		desc = c.val(.desc, "")
		category = c.val(.category, .building)
		art = c.val(.art, ModPixels(w: 8, h: 8))
		hardness = c.val(.hardness, 1.0)
		unbreakable = c.val(.unbreakable, false)
		tool = c.val(.tool, 0)
		tier = c.val(.tier, 0)
		collision = c.val(.collision, .solid)
		transparent = c.val(.transparent, false)
		light = c.val(.light, 0)
		dropSelf = c.val(.dropSelf, true)
		drop = c.val(.drop, nil)
		dropCount = c.val(.dropCount, 1)
		blastProof = c.val(.blastProof, false)
		function = c.val(.function, .none)
		station = c.val(.station, -1)
		power = c.val(.power, 6)
		text = c.val(.text, "")
		vehRole = c.val(.vehRole, .none)
		vehMass = c.val(.vehMass, 0)
		vehPower = c.val(.vehPower, 1.0)
	}
}

// MARK: items

enum ModItemKind: Int, Codable, CaseIterable {
	case material, food, consumable, tool, melee, bow, gun, thrown, magic, armor, ammo, special
	var name: String {
		switch self {
		case .material: return "Material"
		case .food: return "Food"
		case .consumable: return "Potion / consumable"
		case .tool: return "Tool"
		case .melee: return "Melee weapon"
		case .bow: return "Bow"
		case .gun: return "Gun / crossbow"
		case .thrown: return "Thrown weapon"
		case .magic: return "Projectile weapon"
		case .armor: return "Armor"
		case .ammo: return "Ammunition"
		case .special: return "Special item"
		}
	}
	var help: String {
		switch self {
		case .material: return "A crafting ingredient."
		case .food: return "Eaten from the hotbar: fills hunger and can give effects."
		case .consumable: return "Used up for its effects (healing, speed, strength...)."
		case .tool: return "Mines blocks: pickaxe, axe, shovel or hoe."
		case .melee: return "Swung at foes, aimed with the attack stick."
		case .bow: return "Hold to draw, release to shoot."
		case .gun: return "Fires shots, reloads from ammunition."
		case .thrown: return "Lobs a shot in an arc, further the further you aim."
		case .magic: return "Fires its shot on every use (no ammunition)."
		case .armor: return "Worn for defense (and an effect while worn)."
		case .ammo: return "Used up by bows and guns."
		case .special: return "Gives light when held, or an effect when used."
		}
	}
	var isWeapon: Bool { return self == .melee || self == .bow || self == .gun || self == .thrown || self == .magic }
	var isRanged: Bool { return self == .bow || self == .gun || self == .thrown || self == .magic }
}

/// Effects an item can give, taken from a fixed list (no custom code)
enum ModEffectKind: Int, Codable, CaseIterable {
	case heal, feed, speed, strength, resistance, regen, glow, jump, fireproof, cure
	/// appended (potions): mining speed, water breathing, night vision, luck, slow falling, warmth
	case mining, breathing, nightVision, luck, featherfall, warmth
	var name: String {
		switch self {
		case .mining: return "Mining speed"
		case .breathing: return "Water breathing"
		case .nightVision: return "Night vision"
		case .luck: return "Luck"
		case .featherfall: return "Slow falling"
		case .warmth: return "Warmth (cold)"

		case .heal: return "Restore health"
		case .feed: return "Restore hunger"
		case .speed: return "Speed boost"
		case .strength: return "Strength boost"
		case .resistance: return "Resistance"
		case .regen: return "Regeneration"
		case .glow: return "Glow (light)"
		case .jump: return "Jump boost"
		case .fireproof: return "Fire protection"
		case .cure: return "Cure (fire, cold)"
		}
	}
	/// lasts for a while (the others act at once)
	var timed: Bool {
		switch self {
		case .heal, .feed, .cure: return false
		default: return true
		}
	}
	/// what the amount means, for the editor
	var amountLabel: String {
		switch self {
		case .heal: return "Health"
		case .feed: return "Hunger"
		case .speed, .strength, .jump: return "Extra %"
		case .resistance: return "Damage blocked %"
		case .regen: return "Health per second"
		case .glow: return "Light level"
		case .fireproof, .cure: return "Strength"
		case .mining: return "Extra %"
		case .luck: return "Chance %"
		case .breathing, .nightVision, .featherfall, .warmth: return "Strength"
		}
	}
	var amountRange: ModRange {
		switch self {
		case .heal, .feed: return ModRange.heal
		case .speed, .jump: return ModRange(lo: 0, hi: 60, sandboxHi: 200)
		case .strength: return ModRange(lo: 0, hi: 100, sandboxHi: 400)
		case .resistance: return ModRange(lo: 0, hi: 60, sandboxHi: 90)
		case .regen: return ModRange(lo: 0, hi: 4, sandboxHi: 40)
		case .glow: return ModRange(lo: 1, hi: 15, sandboxHi: 15)
		case .fireproof, .cure: return ModRange(lo: 0, hi: 1, sandboxHi: 1)
		case .mining: return ModRange(lo: 0, hi: 80, sandboxHi: 300)
		case .luck: return ModRange(lo: 0, hi: 30, sandboxHi: 60)
		case .breathing, .nightVision, .featherfall, .warmth: return ModRange(lo: 0, hi: 1, sandboxHi: 1)
		}
	}
}

struct ModEffect: Codable, Equatable {
	var kind: ModEffectKind = .heal
	var amount: Double = 6
	var seconds: Double = 20

	init() {}
	init(_ k: ModEffectKind, _ a: Double, _ s: Double) {
		kind = k
		amount = a
		seconds = s
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = c.val(.kind, .heal)
		amount = c.val(.amount, 6)
		seconds = c.val(.seconds, 20)
	}
}

struct ModItem: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Item"
	var desc: String = ""
	var kind: ModItemKind = .material
	/// 16 x 16 picture; when blank, `baseIcon` (an item of the game) is drawn, tinted
	var icon: ModPixels = ModPixels(w: 16, h: 16)
	var baseIcon: Item? = nil
	var tint: UInt32 = 0xFFFFFF
	var tintAmt: Double = 0
	var stack: Int = 99
	/// 0 common, 1 uncommon, 2 rare, 3 epic, 4 legendary (the colour of its name)
	var rarity: Int = 0
	// food and consumables
	var hunger: Double = 0
	var effects: [ModEffect] = []
	var useTime: Double = 0.6
	// tools
	var toolType: Int = 0
	var toolTier: Int = 3
	var toolSpeed: Double = 4
	// melee (also how a tool swings)
	var style: Int = 0
	var damage: Double = 6
	var cooldown: Double = 0.45
	var reach: Double = 3
	/// half the swing's angle (radians)
	var arc: Double = 1.0
	var knock: Double = 6
	var maxHits: Int = 99
	var heavy: Bool = false
	var daze: Double = 0
	var burn: Double = 0
	var windup: Double = 0
	var combo: Bool = false
	var backstab: Double = 1
	var undeadMult: Double = 1
	var crit: Double = 0.1
	var trail: UInt32 = 0xFFFFFF
	// ranged
	/// a shot of this mod (empty: the game shot `shot`)
	var projectile: String = ""
	var shot: Int = 0
	var speed: Double = 30
	var gravity: Double = 0
	var pierce: Int = 0
	/// shots per use, spread in a fan
	var spread: Int = 1
	var magazine: Int = 6
	var reload: Double = 1.5
	/// what each shot uses up (nil: nothing)
	var ammo: Item? = nil
	var needsPress: Bool = false
	// armor
	var slot: Int = 0
	var defense: Double = 2
	/// the game armour tier it is drawn as
	var look: Int = 4
	var wornEffect: ModEffect? = nil
	// special
	/// light it gives when held (0: none)
	var light: Int = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Item")
		desc = c.val(.desc, "")
		kind = c.val(.kind, .material)
		icon = c.val(.icon, ModPixels(w: 16, h: 16))
		baseIcon = c.val(.baseIcon, nil)
		tint = c.val(.tint, 0xFFFFFF)
		tintAmt = c.val(.tintAmt, 0)
		stack = c.val(.stack, 99)
		rarity = c.val(.rarity, 0)
		hunger = c.val(.hunger, 0)
		effects = c.list(.effects, &skip)
		useTime = c.val(.useTime, 0.6)
		toolType = c.val(.toolType, 0)
		toolTier = c.val(.toolTier, 3)
		toolSpeed = c.val(.toolSpeed, 4)
		style = c.val(.style, 0)
		damage = c.val(.damage, 6)
		cooldown = c.val(.cooldown, 0.45)
		reach = c.val(.reach, 3)
		arc = c.val(.arc, 1.0)
		knock = c.val(.knock, 6)
		maxHits = c.val(.maxHits, 99)
		heavy = c.val(.heavy, false)
		daze = c.val(.daze, 0)
		burn = c.val(.burn, 0)
		windup = c.val(.windup, 0)
		combo = c.val(.combo, false)
		backstab = c.val(.backstab, 1)
		undeadMult = c.val(.undeadMult, 1)
		crit = c.val(.crit, 0.1)
		trail = c.val(.trail, 0xFFFFFF)
		projectile = c.val(.projectile, "")
		shot = c.val(.shot, 0)
		speed = c.val(.speed, 30)
		gravity = c.val(.gravity, 0)
		pierce = c.val(.pierce, 0)
		spread = c.val(.spread, 1)
		magazine = c.val(.magazine, 6)
		reload = c.val(.reload, 1.5)
		ammo = c.val(.ammo, nil)
		needsPress = c.val(.needsPress, false)
		slot = c.val(.slot, 0)
		defense = c.val(.defense, 2)
		look = c.val(.look, 4)
		wornEffect = c.val(.wornEffect, nil)
		light = c.val(.light, 0)
	}
}

// MARK: shots

enum ModShotShape: Int, Codable, CaseIterable {
	case orb, arrow, bolt, shard, rock
	var name: String {
		switch self {
		case .orb: return "Orb"
		case .arrow: return "Arrow"
		case .bolt: return "Bolt"
		case .shard: return "Shard"
		case .rock: return "Rock"
		}
	}
}

/// A projectile of a mod: how it looks, how it flies and what it does when it lands
struct ModProjectile: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Shot"
	var shape: ModShotShape = .orb
	var color: UInt32 = 0x8AF0FF
	var size: Double = 0.3
	var glow: Int = 6
	var gravity: Double = 0
	var pierce: Int = 0
	var life: Double = 2
	/// blast radius when it lands (0: no blast)
	var explode: Double = 0
	var breakBlocks: Bool = false
	/// seconds of fire it sets on what it hits
	var burn: Double = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Shot")
		shape = c.val(.shape, .orb)
		color = c.val(.color, 0x8AF0FF)
		size = c.val(.size, 0.3)
		glow = c.val(.glow, 6)
		gravity = c.val(.gravity, 0)
		pierce = c.val(.pierce, 0)
		life = c.val(.life, 2)
		explode = c.val(.explode, 0)
		breakBlocks = c.val(.breakBlocks, false)
		burn = c.val(.burn, 0)
	}
}

// MARK: creatures

enum ModMobCategory: Int, Codable, CaseIterable {
	case passive, neutral, hostile, boss, flying, water
	var name: String {
		switch self {
		case .passive: return "Passive animal"
		case .neutral: return "Neutral creature"
		case .hostile: return "Hostile enemy"
		case .boss: return "Boss"
		case .flying: return "Flying creature"
		case .water: return "Water creature"
		}
	}
	var help: String {
		switch self {
		case .passive: return "Never attacks; runs when hurt."
		case .neutral: return "Leaves you alone until you hit it."
		case .hostile: return "Hunts the player."
		case .boss: return "A big fight with a health bar at the top of the screen."
		case .flying: return "Flies freely."
		case .water: return "Lives in water."
		}
	}
}

enum ModAttackKind: Int, Codable, CaseIterable {
	case melee, charge, ranged, area, jump, stomp, multiHit
	var name: String {
		switch self {
		case .melee: return "Melee"
		case .charge: return "Charge"
		case .ranged: return "Ranged shot"
		case .area: return "Area burst"
		case .jump: return "Jump attack"
		case .stomp: return "Stomp"
		case .multiHit: return "Multi-hit"
		}
	}
	var help: String {
		switch self {
		case .melee: return "A blow at whatever is in front of it."
		case .charge: return "Rushes forward, hurting what it runs into."
		case .ranged: return "Fires shots at the target."
		case .area: return "Hurts everything around it."
		case .jump: return "Leaps at the target and lands on it."
		case .stomp: return "Slams the ground: a shockwave along it."
		case .multiHit: return "A flurry of quick blows."
		}
	}
}

enum ModAttackAim: Int, Codable, CaseIterable {
	case forward, atTarget, around, down
	var name: String {
		switch self {
		case .forward: return "Forward"
		case .atTarget: return "At the target"
		case .around: return "All around"
		case .down: return "Downward"
		}
	}
}

struct ModAttack: Codable, Equatable {
	var kind: ModAttackKind = .melee
	var damage: Double = 6
	var range: Double = 1.6
	var cooldown: Double = 1.2
	var aim: ModAttackAim = .forward
	/// a shot of this mod (empty: the game shot `shot`)
	var projectile: String = ""
	var shot: Int = 2
	var speed: Double = 16
	var knock: Double = 6
	var radius: Double = 2.5
	var hits: Int = 3
	/// the warning before the blow lands
	var windup: Double = 0.3

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = c.val(.kind, .melee)
		damage = c.val(.damage, 6)
		range = c.val(.range, 1.6)
		cooldown = c.val(.cooldown, 1.2)
		aim = c.val(.aim, .forward)
		projectile = c.val(.projectile, "")
		shot = c.val(.shot, 2)
		speed = c.val(.speed, 16)
		knock = c.val(.knock, 6)
		radius = c.val(.radius, 2.5)
		hits = c.val(.hits, 3)
		windup = c.val(.windup, 0.3)
	}
}

/// Behaviour switches; the game's creature AI (senses, chase, search, return) does the rest
struct ModBehavior: Codable, Equatable {
	var wander: Bool = true
	var standStill: Bool = false
	var patrol: Bool = false
	var patrolRange: Double = 8
	var followPlayer: Bool = false
	var runAway: Bool = false
	var chase: Bool = false
	var attackPlayer: Bool = false
	var attackMobs: Bool = false
	var retaliate: Bool = true
	var defendArea: Bool = false
	var defendRadius: Double = 10
	/// stays beside the nearest creature of this kind ("mod:id", or a game creature's name)
	var guardKey: String = ""
	var fly: Bool = false
	var swim: Bool = false
	var stayInBiome: Bool = false
	var burnsInSun: Bool = false

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		wander = c.val(.wander, true)
		standStill = c.val(.standStill, false)
		patrol = c.val(.patrol, false)
		patrolRange = c.val(.patrolRange, 8)
		followPlayer = c.val(.followPlayer, false)
		runAway = c.val(.runAway, false)
		chase = c.val(.chase, false)
		attackPlayer = c.val(.attackPlayer, false)
		attackMobs = c.val(.attackMobs, false)
		retaliate = c.val(.retaliate, true)
		defendArea = c.val(.defendArea, false)
		defendRadius = c.val(.defendRadius, 10)
		guardKey = c.val(.guardKey, "")
		fly = c.val(.fly, false)
		swim = c.val(.swim, false)
		stayInBiome = c.val(.stayInBiome, false)
		burnsInSun = c.val(.burnsInSun, false)
	}
}

enum ModSpawnPlace: Int, Codable, CaseIterable {
	case surface, cave, ocean, umbral, sky
	var name: String {
		switch self {
		case .surface: return "Surface"
		case .cave: return "Caves"
		case .ocean: return "Ocean"
		case .umbral: return "Umbral Realm"
		case .sky: return "In the sky"
		}
	}
}

struct ModSpawn: Codable, Equatable {
	var enabled: Bool = true
	var place: ModSpawnPlace = .surface
	/// 0 any time, 1 by day, 2 at night
	var when: Int = 0
	/// Biome numbers (empty: every biome)
	var biomes: [Int] = []
	var minY: Int = 0
	var maxY: Int = 560
	/// how common it is next to the game's creatures (the zombie is 7)
	var weight: Double = 3
	var group: Int = 1
	var maxNearby: Int = 4

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		enabled = c.val(.enabled, true)
		place = c.val(.place, .surface)
		when = c.val(.when, 0)
		biomes = c.val(.biomes, [])
		minY = c.val(.minY, 0)
		maxY = c.val(.maxY, 560)
		weight = c.val(.weight, 3)
		group = c.val(.group, 1)
		maxNearby = c.val(.maxNearby, 4)
	}
}

struct ModDrop: Codable, Equatable {
	var item: Item = .mat(.string)
	var min: Int = 1
	var max: Int = 1
	var chance: Double = 0.5

	init() {}
	init(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
		item = it
		min = lo
		max = hi
		chance = p
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .mat(.string))
		min = c.val(.min, 1)
		max = c.val(.max, 1)
		chance = c.val(.chance, 0.5)
	}
}

struct ModMob: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Creature"
	var desc: String = ""
	var category: ModMobCategory = .hostile
	/// the game creature its body (and hit box) starts from
	var base: Int = MobKind.zombie.rawValue
	/// draw `frames` instead of the recoloured base body
	var customArt: Bool = false
	/// up to 4 frames: standing, two walking, attacking
	var frames: [ModPixels] = []
	/// colour changes for the base body: hue turn (degrees), saturation and brightness, and a tint
	var hue: Double = 0
	var saturation: Double = 1
	var brightness: Double = 1
	var tint: UInt32 = 0xFFFFFF
	var tintAmt: Double = 0
	var scale: Double = 1
	var hp: Double = 30
	var damage: Double = 6
	var speed: Double = 2
	var detect: Double = 14
	var jump: Double = 12
	/// share of incoming damage shrugged off (0 ... 0.9)
	var defense: Double = 0
	var knockResist: Double = 0
	var fireproof: Bool = false
	var behavior: ModBehavior = ModBehavior()
	var attacks: [ModAttack] = [ModAttack()]
	var spawn: ModSpawn = ModSpawn()
	var drops: [ModDrop] = []
	/// a loot table of this mod, rolled as well as `drops`
	var loot: String = ""
	var glow: Int = 0
	/// the stages of its fight, in order (see ModPhase)
	var phases: [ModPhase] = []
	/// ways a player can call it into the world (see ModSummon)
	var summons: [ModSummon] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Creature")
		desc = c.val(.desc, "")
		category = c.val(.category, .hostile)
		base = c.val(.base, MobKind.zombie.rawValue)
		customArt = c.val(.customArt, false)
		frames = c.list(.frames, &skip)
		hue = c.val(.hue, 0)
		saturation = c.val(.saturation, 1)
		brightness = c.val(.brightness, 1)
		tint = c.val(.tint, 0xFFFFFF)
		tintAmt = c.val(.tintAmt, 0)
		scale = c.val(.scale, 1)
		hp = c.val(.hp, 30)
		damage = c.val(.damage, 6)
		speed = c.val(.speed, 2)
		detect = c.val(.detect, 14)
		jump = c.val(.jump, 12)
		defense = c.val(.defense, 0)
		knockResist = c.val(.knockResist, 0)
		fireproof = c.val(.fireproof, false)
		behavior = c.val(.behavior, ModBehavior())
		attacks = c.list(.attacks, &skip)
		spawn = c.val(.spawn, ModSpawn())
		drops = c.list(.drops, &skip)
		loot = c.val(.loot, "")
		glow = c.val(.glow, 0)
		phases = c.list(.phases, &skip)
		summons = c.list(.summons, &skip)
	}
}

// MARK: recipes, loot, ores, structures

struct ModCost: Codable, Equatable {
	var item: Item = .block(.planks)
	var n: Int = 1

	init() {}
	init(_ it: Item, _ k: Int) {
		item = it
		n = k
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .block(.planks))
		n = c.val(.n, 1)
	}
}

struct ModRecipe: Codable, Identifiable, Equatable {
	var id: String = ""
	var out: Item = .block(.planks)
	var count: Int = 1
	var cost: [ModCost] = []
	/// Station number; -1: near a block of this mod (`stationBlock`)
	var station: Int = 0
	var stationBlock: String = ""
	/// crafting tab (RecipeCat number)
	var cat: Int = RecipeCat.mods.rawValue

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		out = c.val(.out, .block(.planks))
		count = c.val(.count, 1)
		cost = c.list(.cost, &skip)
		station = c.val(.station, 0)
		stationBlock = c.val(.stationBlock, "")
		cat = c.val(.cat, RecipeCat.mods.rawValue)
	}
}

struct ModLootEntry: Codable, Equatable {
	var item: Item = .mat(.coal)
	var min: Int = 1
	var max: Int = 1
	/// 0 common, 1 uncommon, 2 rare, 3 very rare
	var rarity: Int = 0
	/// a weight of its own instead of the rarity's (0: use the rarity)
	var weight: Double = 0

	init() {}
	init(_ it: Item, _ lo: Int, _ hi: Int, _ r: Int) {
		item = it
		min = lo
		max = hi
		rarity = r
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .mat(.coal))
		min = c.val(.min, 1)
		max = c.val(.max, 1)
		rarity = c.val(.rarity, 0)
		weight = c.val(.weight, 0)
	}

	static let rarityNames: [String] = ["Common", "Uncommon", "Rare", "Very rare"]
	static let rarityWeights: [Double] = [60, 25, 10, 3]
	static let rarityColors: [UInt32] = [0xE8E8E8, 0x6AD86A, 0x5AA8FF, 0xC070FF]

	var effectiveWeight: Double {
		if weight > 0 { return weight }
		return ModLootEntry.rarityWeights[clampI(rarity, 0, 3)]
	}
}

/// A weighted loot table: each roll picks one entry (or nothing) by weight
struct ModLootTable: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Loot Table"
	var rolls: Int = 2
	/// weight of rolling nothing
	var nothing: Double = 0
	var entries: [ModLootEntry] = []
	/// chance (0 ... 1) that a chest anywhere in the world also gets a roll of this table
	var chestChance: Double = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Loot")
		rolls = c.val(.rolls, 2)
		nothing = c.val(.nothing, 0)
		entries = c.list(.entries, &skip)
		chestChance = c.val(.chestChance, 0)
	}

	var totalWeight: Double {
		var t: Double = max(0, nothing)
		for e in entries { t += max(0, e.effectiveWeight) }
		return t
	}

	/// Chance (0...1) that one roll gives entry i
	func chance(_ i: Int) -> Double {
		let t: Double = totalWeight
		if t <= 0 || i < 0 || i >= entries.count { return 0 }
		return max(0, entries[i].effectiveWeight) / t
	}
}

struct ModOre: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Ore"
	/// a block of this mod
	var block: String = ""
	/// 0 overworld, 1 Umbral Realm
	var dim: Int = 0
	/// rows from the top of the world (the sea is at 120, the bottom at 559)
	var minY: Int = 150
	var maxY: Int = 330
	/// veins in an average 16-wide stretch of ground
	var veins: Double = 1.5
	/// blocks in a vein
	var size: Int = 6
	/// 0 any rock, 1 stone, 2 slate and deep rock, 3 dirt and sand, 4 any natural ground
	var host: Int = 0
	/// where in the ground: 0 inside the rock, 1 on cave walls, 2 near the surface, 3 under water
	var place: Int = 0
	/// biomes it forms under (empty: all)
	var biomes: [Int] = []
	/// the chance a chunk (16 blocks of width) has any of it at all
	var rarity: Double = 1
	/// 0 lumps, 1 streaks, 2 scattered blocks
	var shape: Int = 0
	/// another ore it forms next to ("tile:<n>" or a block key; empty: anywhere)
	var near: String = ""
	/// the exact blocks it may replace (empty: the host choice)
	var hosts: [String] = []
	/// one of this mod's dimensions (its id) instead of `dim` (empty: `dim` decides)
	var dimKey: String = ""

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Ore")
		block = c.val(.block, "")
		dim = c.val(.dim, 0)
		minY = c.val(.minY, 150)
		maxY = c.val(.maxY, 330)
		veins = c.val(.veins, 1.5)
		size = c.val(.size, 6)
		host = c.val(.host, 0)
		place = c.val(.place, 0)
		biomes = c.val(.biomes, [])
		rarity = c.val(.rarity, 1)
		shape = c.val(.shape, 0)
		near = c.val(.near, "")
		hosts = c.val(.hosts, [])
		dimKey = c.val(.dimKey, "")
	}

	static let hostNames: [String] = ["Any rock", "Stone", "Slate and deep rock", "Dirt and sand", "Any natural ground"]
}

enum ModPlacement: Int, Codable, CaseIterable {
	case surface, underground, sky
	var name: String {
		switch self {
		case .surface: return "On the surface"
		case .underground: return "Underground"
		case .sky: return "Floating in the sky"
		}
	}
}

/// A structure captured from the world: its cells, where it may appear and how often
struct ModStructure: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Structure"
	var w: Int = 0
	var h: Int = 0
	/// row by row: -1 leaves the ground as it is, 0...255 a game tile, 1000 + k the custom block palette[k]
	var cells: [Int] = []
	/// custom blocks it uses ("mod:block")
	var palette: [String] = []
	var placement: ModPlacement = .surface
	var minY: Int = 150
	var maxY: Int = 400
	var biomes: [Int] = []
	/// chance that a possible site holds one
	var chance: Double = 0.35
	/// blocks between possible sites
	var spacing: Int = 300
	var dim: Int = 0
	/// one of this mod's dimensions (its id) instead of `dim` (empty: `dim` decides)
	var dimKey: String = ""
	/// loot table of this mod for chests inside
	var loot: String = ""

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Structure")
		w = c.val(.w, 0)
		h = c.val(.h, 0)
		cells = c.val(.cells, [])
		palette = c.val(.palette, [])
		placement = c.val(.placement, .surface)
		minY = c.val(.minY, 150)
		maxY = c.val(.maxY, 400)
		biomes = c.val(.biomes, [])
		chance = c.val(.chance, 0.35)
		spacing = c.val(.spacing, 300)
		dim = c.val(.dim, 0)
		loot = c.val(.loot, "")
		dimKey = c.val(.dimKey, "")
	}

	func cell(_ x: Int, _ y: Int) -> Int {
		if x < 0 || y < 0 || x >= w || y >= h { return -1 }
		let i: Int = y * w + x
		return i < cells.count ? cells[i] : -1
	}
}

// MARK: the mod

struct ModPack: Codable, Identifiable, Equatable {
	static let currentFormat: Int = 1
	var format: Int = ModPack.currentFormat
	var id: String = ""
	var name: String = "My Mod"
	var desc: String = ""
	var author: String = ""
	var version: String = "1.0"
	var created: Double = 0
	var edited: Double = 0
	/// sandbox mode: wider limits on the numbers inside
	var sandbox: Bool = false
	var blocks: [ModBlock] = []
	var items: [ModItem] = []
	var mobs: [ModMob] = []
	var projectiles: [ModProjectile] = []
	var recipes: [ModRecipe] = []
	var loot: [ModLootTable] = []
	var ores: [ModOre] = []
	var structures: [ModStructure] = []
	/// the folder the mod is filed under in the Mod Creator (empty: none)
	var folder: String = ""
	/// other mods this one needs (their ids; those whose content it uses are found as well)
	var requires: [String] = []
	/// content switched off for now (by id): kept with the mod, left out of worlds
	var off: [String] = []
	/// changes to the game's own blocks, items and creatures
	var overrides: [ModOverride] = []
	/// infusions of this mod (each has a compound: an item under the same key)
	var infusions: [ModInfusion] = []
	/// dimensions of this mod
	var dims: [ModDimension] = []
	/// Logic Studio scripts and the variables they keep (optional)
	var scripts: [ModScript] = []
	var variables: [String] = []
	/// entries left out because they could not be read (not saved)
	var skipped: Int = 0

	enum CodingKeys: String, CodingKey {
		case format, id, name, desc, author, version, created, edited, sandbox
		case blocks, items, mobs, projectiles, recipes, loot, ores, structures
		case folder, requires, off, overrides, infusions, dims, scripts, variables
	}

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		format = c.val(.format, ModPack.currentFormat)
		id = c.val(.id, "")
		name = c.val(.name, "Mod")
		desc = c.val(.desc, "")
		author = c.val(.author, "")
		version = c.val(.version, "1.0")
		created = c.val(.created, 0)
		edited = c.val(.edited, 0)
		sandbox = c.val(.sandbox, false)
		blocks = c.list(.blocks, &skip)
		items = c.list(.items, &skip)
		mobs = c.list(.mobs, &skip)
		projectiles = c.list(.projectiles, &skip)
		recipes = c.list(.recipes, &skip)
		loot = c.list(.loot, &skip)
		ores = c.list(.ores, &skip)
		structures = c.list(.structures, &skip)
		folder = c.val(.folder, "")
		requires = c.val(.requires, [])
		off = c.val(.off, [])
		overrides = c.list(.overrides, &skip)
		infusions = c.list(.infusions, &skip)
		dims = c.list(.dims, &skip)
		scripts = c.list(.scripts, &skip)
		variables = c.val(.variables, [])
		skipped = skip
	}

	/// The key other content uses for something of this mod
	func key(_ contentID: String) -> String { return id + ":" + contentID }

	var contentCount: Int {
		return blocks.count + items.count + mobs.count + projectiles.count + recipes.count + loot.count + ores.count + structures.count + overrides.count + infusions.count + dims.count + scripts.count
	}

	/// "3 creatures, 2 weapons, 5 blocks..." for the mod list
	var summary: String {
		var parts: [String] = []
		func add(_ n: Int, _ one: String, _ many: String) {
			if n > 0 { parts.append(String(n) + " " + (n == 1 ? one : many)) }
		}
		let weapons: Int = items.filter { $0.kind.isWeapon }.count
		add(blocks.count, "block", "blocks")
		add(items.count - weapons, "item", "items")
		add(weapons, "weapon", "weapons")
		add(mobs.count, "creature", "creatures")
		add(recipes.count, "recipe", "recipes")
		add(ores.count, "ore", "ores")
		add(structures.count, "structure", "structures")
		add(loot.count, "loot table", "loot tables")
		add(projectiles.count, "shot", "shots")
		add(overrides.count, "change to the game", "changes to the game")
		add(infusions.count, "infusion", "infusions")
		add(dims.count, "dimension", "dimensions")
		add(scripts.count, "script", "scripts")
		return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
	}

	/// A content id not used yet ("b1", "b2"...)
	func freshID(_ prefix: String) -> String {
		var used: Set<String> = []
		for b in blocks { used.insert(b.id) }
		for i in items { used.insert(i.id) }
		for m in mobs { used.insert(m.id) }
		for p in projectiles { used.insert(p.id) }
		for r in recipes { used.insert(r.id) }
		for l in loot { used.insert(l.id) }
		for o in ores { used.insert(o.id) }
		for s in structures { used.insert(s.id) }
		for o in overrides { used.insert(o.id) }
		for f in infusions { used.insert(f.id) }
		for d in dims { used.insert(d.id) }
		for sc in scripts { used.insert(sc.id) }
		var n: Int = 1
		while used.contains(prefix + String(n)) { n += 1 }
		return prefix + String(n)
	}
}

/// A new random mod id (lowercase letters and digits)
func newModID() -> String {
	let chars: [Character] = Array("abcdefghijkmnpqrstuvwxyz23456789")
	var s: String = "m"
	for _ in 0..<9 { s.append(chars[Int.random(in: 0..<chars.count)]) }
	return s
}

/// The mod and content parts of a key ("m2k4x:b3" -> ("m2k4x", "b3"))
func splitModKey(_ key: String) -> (String, String) {
	guard let i = key.firstIndex(of: ":") else { return ("", key) }
	let a: String = String(key[key.startIndex..<i])
	let b: String = String(key[key.index(after: i)...])
	return (a, b)
}

// MARK: - Mods on disk

/// Which mods are switched on for new worlds, and the order they load in (later mods win when two
/// change the same thing)
struct ModIndex: Codable {
	var order: [String] = []
	var enabled: [String] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		order = c.val(.order, [])
		enabled = c.val(.enabled, [])
	}
}

/// A mod file: the mod, or why it could not be read
struct ModEntry: Identifiable {
	var id: String
	var pack: ModPack?
	var error: String
	var enabled: Bool
}

/// A mod packed for sharing: a header the importer checks, the mod, and a checksum of its content
struct ModPackage: Codable {
	var kind: String = "PixelRealmMod"
	var format: Int = ModPack.currentFormat
	var mod: ModPack
	var check: Int = 0
}

/// A cheap, stable checksum (FNV-1a) of some bytes
func modChecksum(_ d: Data) -> Int {
	var h: UInt64 = 0xcbf29ce484222325
	for b in d {
		h ^= UInt64(b)
		h = h &* 0x100000001b3
	}
	return Int(truncatingIfNeeded: h & 0x7FFF_FFFF_FFFF)
}

enum ModStore {
	/// tests point this at a scratch folder
	static var overrideDir: URL? = nil

	static var dir: URL {
		let fm = FileManager.default
		if let o = overrideDir {
			try? fm.createDirectory(at: o, withIntermediateDirectories: true)
			return o
		}
		if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
			let u = d.appendingPathComponent("PixelRealmMods", isDirectory: true)
			try? fm.createDirectory(at: u, withIntermediateDirectories: true)
			return u
		}
		return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PixelRealmMods", isDirectory: true)
	}

	/// shared mod packages are written here (and read from here to import)
	static var packageDir: URL {
		let u = dir.appendingPathComponent("Packages", isDirectory: true)
		try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
		return u
	}

	static func url(_ id: String) -> URL { return dir.appendingPathComponent(id + ".json") }
	static var indexURL: URL { return dir.appendingPathComponent("index.json") }

	static func loadIndex() -> ModIndex {
		guard let d = try? Data(contentsOf: indexURL), let ix = try? JSONDecoder().decode(ModIndex.self, from: d) else { return ModIndex() }
		return ix
	}

	static func saveIndex(_ ix: ModIndex) {
		if let d = try? JSONEncoder().encode(ix) { try? d.write(to: indexURL, options: .atomic) }
	}

	/// Ids of every mod file in the folder
	static func fileIDs() -> [String] {
		let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		var out: [String] = []
		for n in names where n.hasSuffix(".json") && n != "index.json" {
			out.append(String(n.dropLast(5)))
		}
		return out.sorted()
	}

	static func read(_ id: String) -> ModEntry {
		let on: Bool = loadIndex().enabled.contains(id)
		guard let d = try? Data(contentsOf: url(id)) else {
			return ModEntry(id: id, pack: nil, error: "The file could not be opened.", enabled: on)
		}
		do {
			var p: ModPack = try JSONDecoder().decode(ModPack.self, from: d)
			if p.id.isEmpty { p.id = id }
			if p.id != id {
				// the file name is the mod's identity; a mismatch (a copied file) takes the file's name
				p.id = id
			}
			return ModEntry(id: id, pack: p, error: "", enabled: on)
		} catch {
			return ModEntry(id: id, pack: nil, error: "This file is not a readable mod (it may be damaged).", enabled: on)
		}
	}

	static func pack(_ id: String) -> ModPack? { return read(id).pack }

	/// Every mod, in load order (mods not in the order yet come last, by name)
	static func entries() -> [ModEntry] {
		let ix: ModIndex = loadIndex()
		let ids: [String] = fileIDs()
		var out: [ModEntry] = []
		var seen: Set<String> = []
		for id in ix.order where ids.contains(id) && !seen.contains(id) {
			out.append(read(id))
			seen.insert(id)
		}
		var rest: [ModEntry] = []
		for id in ids where !seen.contains(id) { rest.append(read(id)) }
		rest.sort { ($0.pack?.name ?? $0.id) < ($1.pack?.name ?? $1.id) }
		out.append(contentsOf: rest)
		return out
	}

	@discardableResult
	static func save(_ p0: ModPack) -> Bool {
		var p: ModPack = p0
		if p.id.isEmpty { p.id = newModID() }
		let now: Double = Date().timeIntervalSince1970
		if p.created == 0 { p.created = now }
		p.edited = now
		let enc = JSONEncoder()
		guard let d = try? enc.encode(p) else { return false }
		do {
			try d.write(to: url(p.id), options: .atomic)
		} catch {
			return false
		}
		var ix: ModIndex = loadIndex()
		if !ix.order.contains(p.id) {
			ix.order.append(p.id)
			saveIndex(ix)
		}
		return true
	}

	static func delete(_ id: String) {
		try? FileManager.default.removeItem(at: url(id))
		var ix: ModIndex = loadIndex()
		ix.order.removeAll { $0 == id }
		ix.enabled.removeAll { $0 == id }
		saveIndex(ix)
	}

	/// A copy with a new identity (its content keeps the same ids, under the new mod)
	static func duplicate(_ p: ModPack) -> ModPack? {
		var c: ModPack = p
		c.id = newModID()
		c.name = p.name + " (copy)"
		c.created = 0
		// keys inside the copy that pointed at the original now point at the copy
		c = rekey(c, from: p.id, to: c.id)
		return save(c) ? pack(c.id) : nil
	}

	static func isEnabled(_ id: String) -> Bool { return loadIndex().enabled.contains(id) }

	static func setEnabled(_ id: String, _ on: Bool) {
		var ix: ModIndex = loadIndex()
		ix.enabled.removeAll { $0 == id }
		if on { ix.enabled.append(id) }
		if !ix.order.contains(id) { ix.order.append(id) }
		saveIndex(ix)
	}

	/// Moves a mod earlier (-1) or later (+1) in the load order
	static func move(_ id: String, by delta: Int) {
		var ix: ModIndex = loadIndex()
		var order: [String] = entries().map { $0.id }
		guard let i = order.firstIndex(of: id) else { return }
		let j: Int = clampI(i + delta, 0, order.count - 1)
		if i == j { return }
		order.remove(at: i)
		order.insert(id, at: j)
		ix.order = order
		saveIndex(ix)
	}

	/// The mods switched on for new worlds, readable ones only, in load order
	static func enabledPacks() -> [ModPack] {
		var out: [ModPack] = []
		for e in entries() where e.enabled {
			if let p = e.pack { out.append(p) }
			if out.count >= ModLimits.maxMods { break }
		}
		return out
	}

	// MARK: sharing (local files only)

	/// Writes the mod as a package file and returns where it went
	static func exportPackage(_ p: ModPack) -> URL? {
		guard let body = try? JSONEncoder().encode(p) else { return nil }
		let pkg = ModPackage(mod: p, check: modChecksum(body))
		guard let d = try? JSONEncoder().encode(pkg) else { return nil }
		var safe: String = ""
		for ch in p.name where ch.isLetter || ch.isNumber { safe.append(ch) }
		if safe.isEmpty { safe = "Mod" }
		let u: URL = packageDir.appendingPathComponent(safe + "-" + p.version + ".prmod")
		do {
			try d.write(to: u, options: .atomic)
			return u
		} catch {
			return nil
		}
	}

	/// Package files waiting in the packages folder
	static func packageFiles() -> [URL] {
		let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: packageDir.path)) ?? []
		return names.filter { $0.hasSuffix(".prmod") }.sorted().map { packageDir.appendingPathComponent($0) }
	}

	/// Reads a package, checks it and installs the mod (as a copy when the id is already used).
	/// Returns the installed mod, or why it was refused.
	static func importPackage(_ data: Data) -> (ModPack?, String) {
		guard let pkg = try? JSONDecoder().decode(ModPackage.self, from: data) else {
			return (nil, "That file is not a Pixel Realm mod package.")
		}
		if pkg.kind != "PixelRealmMod" { return (nil, "That file is not a Pixel Realm mod package.") }
		if pkg.format > ModPack.currentFormat { return (nil, "This mod was made with a newer version of the game.") }
		var p: ModPack = pkg.mod
		let report: ModReport = ModValidator.check(&p, known: ModCatalog.installed().keys)
		if report.fatal { return (nil, "The mod is too damaged to use: " + (report.issues.first?.text ?? "")) }
		let oldID: String = p.id
		if p.id.isEmpty || !p.id.allSatisfy({ $0.isLetter || $0.isNumber }) || FileManager.default.fileExists(atPath: url(p.id).path) {
			p.id = newModID()
			p = rekey(p, from: oldID, to: p.id)
			if FileManager.default.fileExists(atPath: url(oldID).path) { p.name += " (imported)" }
		}
		if !save(p) { return (nil, "The mod could not be saved.") }
		return (pack(p.id), "Installed " + p.name + ".")
	}

	/// Points every key of mod `from` inside the mod at mod `to`
	static func rekey(_ p0: ModPack, from: String, to: String) -> ModPack {
		if from.isEmpty || from == to { return p0 }
		var p: ModPack = p0
		func fix(_ it: Item) -> Item {
			if case .custom(let k) = it {
				let s: (String, String) = splitModKey(k)
				if s.0 == from { return .custom(to + ":" + s.1) }
			}
			return it
		}
		func fixKey(_ k: String) -> String {
			let s: (String, String) = splitModKey(k)
			return s.0 == from ? to + ":" + s.1 : k
		}
		for i in p.blocks.indices { if let d = p.blocks[i].drop { p.blocks[i].drop = fix(d) } }
		for i in p.items.indices {
			if let a = p.items[i].ammo { p.items[i].ammo = fix(a) }
			if let b = p.items[i].baseIcon { p.items[i].baseIcon = fix(b) }
		}
		for i in p.mobs.indices {
			for k in p.mobs[i].drops.indices { p.mobs[i].drops[k].item = fix(p.mobs[i].drops[k].item) }
			p.mobs[i].behavior.guardKey = fixKey(p.mobs[i].behavior.guardKey)
		}
		for i in p.recipes.indices {
			p.recipes[i].out = fix(p.recipes[i].out)
			for k in p.recipes[i].cost.indices { p.recipes[i].cost[k].item = fix(p.recipes[i].cost[k].item) }
		}
		for i in p.loot.indices {
			for k in p.loot[i].entries.indices { p.loot[i].entries[k].item = fix(p.loot[i].entries[k].item) }
		}
		for i in p.structures.indices { p.structures[i].palette = p.structures[i].palette.map { fixKey($0) } }
		for i in p.infusions.indices { p.infusions[i].items = p.infusions[i].items.map { fix($0) } }
		func fixRef(_ k: String) -> String { return k.isEmpty || k == "air" || k.hasPrefix("tile:") ? k : fixKey(k) }
		for i in p.mobs.indices {
			for k in p.mobs[i].phases.indices { p.mobs[i].phases[k].helper = fixRef(p.mobs[i].phases[k].helper) }
			for k in p.mobs[i].summons.indices {
				if let it = p.mobs[i].summons[k].item { p.mobs[i].summons[k].item = fix(it) }
				p.mobs[i].summons[k].pattern.cells = p.mobs[i].summons[k].pattern.cells.map { fixRef($0) }
			}
		}
		for i in p.ores.indices {
			p.ores[i].hosts = p.ores[i].hosts.map { fixRef($0) }
			p.ores[i].near = fixRef(p.ores[i].near)
		}
		for i in p.mobs.indices {
			for k in p.mobs[i].summons.indices { p.mobs[i].summons[k].dimKeys = p.mobs[i].summons[k].dimKeys.map { fixRef($0) } }
		}
		for i in p.dims.indices {
			var d: ModDimension = p.dims[i]
			d.stone = fixRef(d.stone)
			d.hazard = fixRef(d.hazard)
			d.gateBlock = fixRef(d.gateBlock)
			for k in d.zones.indices {
				d.zones[k].ground = fixRef(d.zones[k].ground)
				d.zones[k].filler = fixRef(d.zones[k].filler)
				d.zones[k].plant = fixRef(d.zones[k].plant)
				d.zones[k].log = fixRef(d.zones[k].log)
				d.zones[k].leaves = fixRef(d.zones[k].leaves)
			}
			for k in d.spawns.indices { d.spawns[k].creature = fixRef(d.spawns[k].creature) }
			if let it = d.entry.item { d.entry.item = fix(it) }
			d.entry.pattern.cells = d.entry.pattern.cells.map { fixRef($0) }
			d.entry.dimKeys = d.entry.dimKeys.map { fixRef($0) }
			p.dims[i] = d
		}
		for i in p.scripts.indices { p.scripts[i] = LKeys.rekey(p.scripts[i], fixRef, fix) }
		return p
	}
}

extension ModValidator {
	/// Recipes that turn one thing into another, chained back to where they started (with the game's own
	/// recipes too), must never give back more than went in. Returns each mod recipe that closes such a
	/// loop, with a name for the recipe it loops with; each one found is left out before looking again.
	static func gainLoops(_ p: ModPack, _ off: Set<String>) -> [(String, String)] {
		var from: [Item] = []
		var to: [Item] = []
		var ratio: [Double] = []
		var rid: [String] = []
		var label: [String] = []
		for r in RecipeBook.base where r.cost.count == 1 && r.cost[0].n > 0 {
			from.append(r.cost[0].item)
			to.append(r.out)
			ratio.append(Double(r.outCount) / Double(r.cost[0].n))
			rid.append("")
			label.append("the game's recipe for " + r.out.name)
		}
		for r in p.recipes where !off.contains(r.id) && r.cost.count == 1 && r.cost[0].n > 0 {
			from.append(r.cost[0].item)
			to.append(r.out)
			ratio.append(Double(r.count) / Double(r.cost[0].n))
			rid.append(r.id)
			label.append("the recipe " + r.id)
		}
		var live: [Bool] = [Bool](repeating: true, count: from.count)
		var out: [(String, String)] = []
		for e in from.indices where !rid[e].isEmpty {
			// look for a way back from what it makes to what it uses, three recipes deep at most
			var stack: [(Item, Double, Int, Int)] = [(to[e], ratio[e], 0, -1)]
			var found: Int = -2
			while let top = stack.popLast(), found == -2 {
				for k in from.indices where live[k] && k != e && from[k] == top.0 {
					let gain: Double = top.1 * ratio[k]
					let first: Int = top.3 < 0 ? k : top.3
					if to[k] == from[e] {
						if gain > 1.0001 { found = first; break }
					} else if top.2 < 2 {
						stack.append((to[k], gain, top.2 + 1, first))
					}
				}
			}
			if found >= 0 {
				live[e] = false
				out.append((rid[e], label[found]))
			}
		}
		return out
	}
}

// MARK: - Every installed mod's content, by key (for checks and the editor)

struct ModCatalog {
	/// key -> what it is ("block", "item", "mob", "shot", "loot")
	var keys: [String: String] = [:]
	var names: [String: String] = [:]
	var packs: [ModPack] = []

	static func build(_ packs: [ModPack]) -> ModCatalog {
		var c = ModCatalog()
		c.packs = packs
		for p in packs {
			for b in p.blocks { c.keys[p.key(b.id)] = "block"; c.names[p.key(b.id)] = b.name }
			for i in p.items { c.keys[p.key(i.id)] = "item"; c.names[p.key(i.id)] = i.name }
			for m in p.mobs { c.keys[p.key(m.id)] = "mob"; c.names[p.key(m.id)] = m.name }
			for s in p.projectiles { c.keys[p.key(s.id)] = "shot"; c.names[p.key(s.id)] = s.name }
			for l in p.loot { c.keys[p.key(l.id)] = "loot"; c.names[p.key(l.id)] = l.name }
			for f in p.infusions { c.keys[p.key(f.id)] = "item"; c.names[p.key(f.id)] = joinText(f.name, " Compound") }
			for d in p.dims { c.keys[p.key(d.id)] = "dimension"; c.names[p.key(d.id)] = d.name }
		}
		return c
	}

	static func installed() -> ModCatalog {
		var ps: [ModPack] = []
		for e in ModStore.entries() { if let p = e.pack { ps.append(p) } }
		return build(ps)
	}

	func block(_ key: String) -> ModBlock? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.blocks.first { $0.id == s.1 } }
		return nil
	}

	func item(_ key: String) -> ModItem? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.items.first { $0.id == s.1 } }
		return nil
	}

	func mob(_ key: String) -> ModMob? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.mobs.first { $0.id == s.1 } }
		return nil
	}
}

// MARK: - Checking a mod

/// A problem found in a mod. Level 0 is a note, 1 a warning (the content still works, perhaps
/// changed), 2 an error (that content is left out until it is fixed).
struct ModIssue: Identifiable {
	var id: Int
	var level: Int
	var mod: String
	var place: String
	var text: String
}

struct ModReport {
	var issues: [ModIssue] = []
	/// content ids of this mod left out because they cannot work
	var disabled: Set<String> = []
	/// the mod as a whole cannot be used
	var fatal: Bool = false

	var errors: Int { return issues.filter { $0.level >= 2 }.count }
	var warnings: Int { return issues.filter { $0.level == 1 }.count }

	mutating func add(_ level: Int, _ mod: String, _ place: String, _ text: String) {
		issues.append(ModIssue(id: issues.count, level: level, mod: mod, place: place, text: text))
	}
}

enum ModValidator {
	/// Cleans a mod in place (numbers into their ranges, ids unique, sizes legal, broken references
	/// removed where that is safe) and reports what was wrong. Content that cannot work at all is
	/// listed in `disabled` and left out when the mod is used, so a mistake never stops the game.
	/// `known` holds every key of every installed mod (for references to other mods).
	static func check(_ p: inout ModPack, known: [String: String]) -> ModReport {
		var r = ModReport()
		let mn: String = p.name.isEmpty ? "Mod" : p.name
		let sb: Bool = p.sandbox
		if p.format > ModPack.currentFormat {
			r.add(2, mn, "Mod", "Made with a newer version of the game.")
			r.fatal = true
			return r
		}
		if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = "Untitled Mod"; r.add(0, mn, "Mod", "It had no name.") }
		if p.name.count > 40 { p.name = String(p.name.prefix(40)) }
		if p.author.count > 40 { p.author = String(p.author.prefix(40)) }
		if p.desc.count > 500 { p.desc = String(p.desc.prefix(500)) }
		if p.version.isEmpty { p.version = "1.0" }
		if p.version.count > 12 { p.version = String(p.version.prefix(12)) }
		if p.skipped > 0 { r.add(1, mn, "Mod", String(p.skipped) + " damaged entries could not be read and were left out.") }
		trim(&p.blocks, ModLimits.maxBlocks, "blocks", mn, &r)
		trim(&p.items, ModLimits.maxItems, "items", mn, &r)
		trim(&p.mobs, ModLimits.maxMobs, "creatures", mn, &r)
		trim(&p.projectiles, ModLimits.maxShots, "shots", mn, &r)
		trim(&p.recipes, ModLimits.maxRecipes, "recipes", mn, &r)
		trim(&p.loot, ModLimits.maxLoot, "loot tables", mn, &r)
		trim(&p.ores, ModLimits.maxOres, "ores", mn, &r)
		trim(&p.structures, ModLimits.maxStructures, "structures", mn, &r)
		uniqueIDs(&p, mn, &r)
		// what this mod's own content is, by key
		var own: [String: String] = [:]
		for b in p.blocks { own[p.key(b.id)] = "block" }
		for i in p.items { own[p.key(i.id)] = "item" }
		for m in p.mobs { own[p.key(m.id)] = "mob" }
		for s in p.projectiles { own[p.key(s.id)] = "shot" }
		for l in p.loot { own[p.key(l.id)] = "loot" }
		// an infusion's compound is an item of the mod
		for f in p.infusions { own[p.key(f.id)] = "item" }
		for d in p.dims { own[p.key(d.id)] = "dimension" }
		func exists(_ it: Item) -> Bool {
			if case .custom(let k) = it {
				let kind: String = own[k] ?? known[k] ?? ""
				return kind == "block" || kind == "item"
			}
			return true
		}
		let shotIDs: Set<String> = Set(p.projectiles.map { $0.id })
		let lootIDs: Set<String> = Set(p.loot.map { $0.id })
		// blocks
		for i in p.blocks.indices {
			var b: ModBlock = p.blocks[i]
			let place: String = "Block \u{201C}" + b.name + "\u{201D}"
			if b.name.trimmingCharacters(in: .whitespaces).isEmpty { b.name = "Block" }
			if b.name.count > 32 { b.name = String(b.name.prefix(32)) }
			if !b.art.valid || b.art.w != 8 || b.art.h != 8 {
				b.art = b.art.valid ? b.art.resized(8, 8) : ModPixels(w: 8, h: 8)
				r.add(1, mn, place, "Its picture was not 8 x 8 and was fitted.")
			}
			if b.art.isBlank { r.add(0, mn, place, "It has no picture yet (it shows as grey).") }
			b.hardness = ModRange.hardness.clamp(b.hardness, sb)
			b.tool = clampI(b.tool, 0, 3)
			b.tier = clampI(b.tier, 0, 9)
			b.light = clampI(b.light, 0, 15)
			b.dropCount = clampI(b.dropCount, 1, 16)
			b.station = clampI(b.station, -1, 9)
			b.power = clampD(b.power.isFinite ? b.power : 0, 0, sb ? 400 : 40)
			b.vehMass = clampD(b.vehMass.isFinite ? b.vehMass : 0, 0, sb ? 60 : 20)
			b.vehPower = clampD(b.vehPower.isFinite ? b.vehPower : 1, 0.25, sb ? 10 : 4)
			if b.text.count > 200 { b.text = String(b.text.prefix(200)) }
			if let d = b.drop, !exists(d) {
				b.drop = nil
				b.dropSelf = true
				r.add(1, mn, place, "It dropped something that does not exist; it drops itself now.")
			}
			p.blocks[i] = b
		}
		// shots
		for i in p.projectiles.indices {
			var s: ModProjectile = p.projectiles[i]
			if s.name.trimmingCharacters(in: .whitespaces).isEmpty { s.name = "Shot" }
			s.size = clampD(s.size.isFinite ? s.size : 0.3, 0.1, 1.0)
			s.glow = clampI(s.glow, 0, 12)
			s.gravity = ModRange.gravity.clamp(s.gravity, sb)
			s.pierce = clampI(s.pierce, 0, 5)
			s.life = clampD(s.life.isFinite ? s.life : 2, 0.2, 6)
			s.explode = clampD(s.explode.isFinite ? s.explode : 0, 0, sb ? 12 : 6)
			s.burn = clampD(s.burn.isFinite ? s.burn : 0, 0, 10)
			p.projectiles[i] = s
		}
		// items
		for i in p.items.indices {
			var it: ModItem = p.items[i]
			let place: String = "Item \u{201C}" + it.name + "\u{201D}"
			if it.name.trimmingCharacters(in: .whitespaces).isEmpty { it.name = "Item" }
			if it.name.count > 32 { it.name = String(it.name.prefix(32)) }
			if !it.icon.valid || it.icon.w > 32 || it.icon.h > 32 {
				it.icon = ModPixels(w: 16, h: 16)
				r.add(1, mn, place, "Its picture was too big or damaged and was cleared.")
			}
			if let b = it.baseIcon, !exists(b) { it.baseIcon = nil }
			if it.icon.isBlank && it.baseIcon == nil { r.add(0, mn, place, "It has no picture yet.") }
			it.stack = clampI(it.stack, 1, sb ? 999 : 99)
			if it.kind.isWeapon || it.kind == .tool || it.kind == .armor { it.stack = 1 }
			it.rarity = clampI(it.rarity, 0, 4)
			it.tintAmt = clampD(it.tintAmt.isFinite ? it.tintAmt : 0, 0, 1)
			it.hunger = clampD(it.hunger.isFinite ? it.hunger : 0, 0, 20)
			if it.effects.count > ModLimits.maxEffects { it.effects = Array(it.effects.prefix(ModLimits.maxEffects)) }
			for k in it.effects.indices {
				it.effects[k].amount = it.effects[k].kind.amountRange.clamp(it.effects[k].amount, sb)
				it.effects[k].seconds = ModRange.seconds.clamp(it.effects[k].seconds, sb)
			}
			if var we = it.wornEffect {
				we.amount = we.kind.amountRange.clamp(we.amount, sb)
				it.wornEffect = we
			}
			it.useTime = clampD(it.useTime.isFinite ? it.useTime : 0.6, 0.1, 5)
			it.toolType = clampI(it.toolType, 0, 3)
			it.toolTier = clampI(it.toolTier, 1, 9)
			it.toolSpeed = ModRange.toolSpeed.clamp(it.toolSpeed, sb)
			it.style = clampI(it.style, 0, 4)
			it.damage = ModRange.damage.clamp(it.damage, sb)
			it.cooldown = ModRange.cooldown.clamp(it.cooldown, sb)
			it.reach = ModRange.reach.clamp(it.reach, sb)
			it.arc = clampD(it.arc.isFinite ? it.arc : 1, 0.1, 1.6)
			it.knock = ModRange.knock.clamp(it.knock, sb)
			it.maxHits = clampI(it.maxHits, 1, 99)
			it.daze = clampD(it.daze.isFinite ? it.daze : 0, 0, 3)
			it.burn = clampD(it.burn.isFinite ? it.burn : 0, 0, 8)
			it.windup = clampD(it.windup.isFinite ? it.windup : 0, 0, 0.6)
			it.backstab = clampD(it.backstab.isFinite ? it.backstab : 1, 1, 3)
			it.undeadMult = clampD(it.undeadMult.isFinite ? it.undeadMult : 1, 0.5, 3)
			it.crit = clampD(it.crit.isFinite ? it.crit : 0.1, 0, 0.6)
			it.shot = clampI(it.shot, 0, 12)
			it.speed = ModRange.shotSpeed.clamp(it.speed, sb)
			it.gravity = ModRange.gravity.clamp(it.gravity, sb)
			it.pierce = clampI(it.pierce, 0, 5)
			it.spread = clampI(it.spread, 1, sb ? 12 : 7)
			it.magazine = clampI(it.magazine, 1, sb ? 99 : 30)
			it.reload = clampD(it.reload.isFinite ? it.reload : 1.5, 0.2, 6)
			it.slot = clampI(it.slot, 0, 2)
			it.defense = ModRange.defense.clamp(it.defense, sb)
			it.look = clampI(it.look, 1, 9)
			it.light = clampI(it.light, 0, 15)
			if !it.projectile.isEmpty && !shotIDs.contains(it.projectile) {
				it.projectile = ""
				r.add(1, mn, place, "Its shot no longer exists; it fires a game shot.")
			}
			if let a = it.ammo, !exists(a) {
				it.ammo = nil
				r.add(1, mn, place, "Its ammunition does not exist; it needs none now.")
			}
			p.items[i] = it
		}
		// creatures
		for i in p.mobs.indices {
			var m: ModMob = p.mobs[i]
			let place: String = "Creature \u{201C}" + m.name + "\u{201D}"
			if m.name.trimmingCharacters(in: .whitespaces).isEmpty { m.name = "Creature" }
			if m.name.count > 32 { m.name = String(m.name.prefix(32)) }
			if MobKind(rawValue: m.base) == nil || m.base == MobKind.custom.rawValue || m.base == MobKind.villager.rawValue {
				m.base = MobKind.zombie.rawValue
				r.add(1, mn, place, "Its body was unknown; it uses the zombie body.")
			}
			var frames: [ModPixels] = []
			for f in m.frames.prefix(ModLimits.maxFrames) {
				if f.valid && f.w <= ModLimits.maxMobArt && f.h <= ModLimits.maxMobArt { frames.append(f) }
			}
			if frames.count != m.frames.count { r.add(1, mn, place, "Some of its pictures were too big or damaged and were left out.") }
			m.frames = frames
			if m.customArt && (frames.isEmpty || frames[0].isBlank) {
				m.customArt = false
				r.add(1, mn, place, "Its own picture is empty; it uses its base body.")
			}
			m.hue = clampD(m.hue.isFinite ? m.hue : 0, -180, 180)
			m.saturation = clampD(m.saturation.isFinite ? m.saturation : 1, 0, 2)
			m.brightness = clampD(m.brightness.isFinite ? m.brightness : 1, 0.4, 1.6)
			m.tintAmt = clampD(m.tintAmt.isFinite ? m.tintAmt : 0, 0, 1)
			m.scale = ModRange.scale.clamp(m.scale, sb || m.category == .boss)
			m.hp = (m.category == .boss ? ModRange.bossHP : ModRange.mobHP).clamp(m.hp, sb)
			m.damage = ModRange.damage.clamp(m.damage, sb)
			m.speed = ModRange.mobSpeed.clamp(m.speed, sb)
			m.detect = ModRange.detect.clamp(m.detect, sb)
			m.jump = ModRange.jump.clamp(m.jump, sb)
			m.defense = clampD(m.defense.isFinite ? m.defense : 0, 0, 0.9)
			m.knockResist = clampD(m.knockResist.isFinite ? m.knockResist : 0, 0, 1)
			m.glow = clampI(m.glow, 0, 10)
			m.behavior.patrolRange = clampD(m.behavior.patrolRange.isFinite ? m.behavior.patrolRange : 8, 2, 40)
			m.behavior.defendRadius = clampD(m.behavior.defendRadius.isFinite ? m.behavior.defendRadius : 10, 3, 40)
			if m.category == .flying { m.behavior.fly = true }
			if m.category == .water { m.behavior.swim = true }
			if !m.behavior.guardKey.isEmpty {
				let gk: String = m.behavior.guardKey
				let native: Bool = MobKind.allCases.contains { mobDef($0).name == gk }
				if !native && (own[gk] ?? known[gk] ?? "") != "mob" {
					m.behavior.guardKey = ""
					r.add(1, mn, place, "The creature it guarded does not exist.")
				}
			}
			if m.attacks.count > ModLimits.maxAttacks { m.attacks = Array(m.attacks.prefix(ModLimits.maxAttacks)) }
			for k in m.attacks.indices {
				var a: ModAttack = m.attacks[k]
				a.damage = ModRange.damage.clamp(a.damage, sb)
				a.range = clampD(a.range.isFinite ? a.range : 1.6, 0.5, a.kind == .ranged ? 30 : (sb ? 12 : 8))
				a.cooldown = clampD(a.cooldown.isFinite ? a.cooldown : 1.2, 0.2, 20)
				a.shot = clampI(a.shot, 0, 12)
				a.speed = ModRange.shotSpeed.clamp(a.speed, sb)
				a.knock = ModRange.knock.clamp(a.knock, sb)
				a.radius = ModRange.radius.clamp(a.radius, sb)
				a.hits = clampI(a.hits, 1, sb ? 12 : 6)
				a.windup = clampD(a.windup.isFinite ? a.windup : 0.3, 0, 2)
				if !a.projectile.isEmpty && !shotIDs.contains(a.projectile) {
					a.projectile = ""
					r.add(1, mn, place, "An attack's shot no longer exists; it fires a game shot.")
				}
				m.attacks[k] = a
			}
			if m.drops.count > ModLimits.maxDrops { m.drops = Array(m.drops.prefix(ModLimits.maxDrops)) }
			var drops: [ModDrop] = []
			for d0 in m.drops {
				var d: ModDrop = d0
				if !exists(d.item) {
					r.add(1, mn, place, "A drop that does not exist was removed.")
					continue
				}
				d.min = clampI(d.min, 0, 64)
				d.max = clampI(d.max, d.min, 64)
				d.chance = clampD(d.chance.isFinite ? d.chance : 0, 0, 1)
				drops.append(d)
			}
			m.drops = drops
			if !m.loot.isEmpty && !lootIDs.contains(m.loot) {
				m.loot = ""
				r.add(1, mn, place, "Its loot table no longer exists.")
			}
			var sp: ModSpawn = m.spawn
			sp.when = clampI(sp.when, 0, 2)
			sp.biomes = sp.biomes.filter { Biome(rawValue: $0) != nil }
			sp.minY = clampI(sp.minY, 0, 559)
			sp.maxY = clampI(sp.maxY, sp.minY, 559)
			sp.weight = clampD(sp.weight.isFinite ? sp.weight : 1, 0.1, 10)
			sp.group = clampI(sp.group, 1, m.category == .boss ? 1 : 4)
			sp.maxNearby = clampI(sp.maxNearby, 1, m.category == .boss ? 1 : 8)
			m.spawn = sp
			p.mobs[i] = m
		}
		// recipes
		for i in p.recipes.indices {
			var rc: ModRecipe = p.recipes[i]
			let place: String = "Recipe for " + itemLabel(rc.out, own: p, known: known)
			rc.count = clampI(rc.count, 1, 99)
			if rc.cost.count > ModLimits.maxCost { rc.cost = Array(rc.cost.prefix(ModLimits.maxCost)) }
			for k in rc.cost.indices { rc.cost[k].n = clampI(rc.cost[k].n, 1, 999) }
			rc.station = clampI(rc.station, -1, 9)
			rc.cat = clampI(rc.cat, 0, RecipeCat.allCases.count - 1)
			var bad: String = ""
			if !exists(rc.out) { bad = "It makes something that does not exist." }
			else if rc.cost.isEmpty { bad = "It needs at least one ingredient." }
			else if rc.cost.contains(where: { !exists($0.item) }) { bad = "One of its ingredients does not exist." }
			else if rc.cost.contains(where: { $0.item == rc.out && $0.n >= rc.count }) { bad = "It uses up as much as it makes (a loop that makes nothing)." }
			if rc.station == -1 {
				let blk: ModBlock? = p.blocks.first { $0.id == rc.stationBlock }
				if blk == nil || blk?.function != .station {
					rc.station = 0
					r.add(1, mn, place, "Its station block is missing or is not a station; it is made by hand.")
				}
			}
			if !bad.isEmpty {
				r.add(2, mn, place, bad)
				r.disabled.insert(rc.id)
			}
			p.recipes[i] = rc
		}
		for (rid, other) in gainLoops(p, r.disabled) {
			let rc: ModRecipe? = p.recipes.first { $0.id == rid }
			let place: String = "Recipe for " + itemLabel(rc?.out ?? .mat(.stick), own: p, known: known)
			r.add(2, mn, place, "Crafting it and " + other + " back and forth would make things from nothing.")
			r.disabled.insert(rid)
		}
		// loot tables
		for i in p.loot.indices {
			var lt: ModLootTable = p.loot[i]
			let place: String = "Loot table \u{201C}" + lt.name + "\u{201D}"
			lt.rolls = clampI(lt.rolls, 1, 6)
			lt.nothing = clampD(lt.nothing.isFinite ? lt.nothing : 0, 0, 1000)
			lt.chestChance = clampD(lt.chestChance.isFinite ? lt.chestChance : 0, 0, 1)
			if lt.entries.count > ModLimits.maxLootEntries { lt.entries = Array(lt.entries.prefix(ModLimits.maxLootEntries)) }
			var ents: [ModLootEntry] = []
			for e0 in lt.entries {
				var e: ModLootEntry = e0
				if !exists(e.item) {
					r.add(1, mn, place, "An entry for something that does not exist was removed.")
					continue
				}
				e.min = clampI(e.min, 1, 64)
				e.max = clampI(e.max, e.min, 64)
				e.rarity = clampI(e.rarity, 0, 3)
				e.weight = clampD(e.weight.isFinite ? e.weight : 0, 0, 1000)
				ents.append(e)
			}
			lt.entries = ents
			if lt.entries.isEmpty {
				r.add(2, mn, place, "It has nothing in it.")
				r.disabled.insert(lt.id)
			}
			p.loot[i] = lt
		}
		// ores
		for i in p.ores.indices {
			var o: ModOre = p.ores[i]
			let place: String = "Ore \u{201C}" + o.name + "\u{201D}"
			o.dim = clampI(o.dim, 0, 1)
			let bottom: Int = o.dim == 0 ? WorldGen.H - 2 : umbralH - 2
			o.minY = clampI(o.minY, 2, bottom)
			o.maxY = clampI(o.maxY, o.minY, bottom)
			o.veins = clampD(o.veins.isFinite ? o.veins : 1, 0.05, 8)
			o.size = clampI(o.size, 1, 24)
			o.host = clampI(o.host, 0, 4)
			if !p.blocks.contains(where: { $0.id == o.block }) {
				r.add(2, mn, place, "Choose which block of this mod it is made of.")
				r.disabled.insert(o.id)
			}
			p.ores[i] = o
		}
		// structures
		for i in p.structures.indices {
			var s: ModStructure = p.structures[i]
			let place: String = "Structure \u{201C}" + s.name + "\u{201D}"
			s.chance = clampD(s.chance.isFinite ? s.chance : 0.3, 0.01, 1)
			s.spacing = clampI(s.spacing, 64, 4096)
			s.dim = clampI(s.dim, 0, 1)
			s.minY = clampI(s.minY, 4, 550)
			s.maxY = clampI(s.maxY, s.minY, 550)
			s.biomes = s.biomes.filter { Biome(rawValue: $0) != nil }
			if s.w < 1 || s.h < 1 || s.w > ModLimits.maxStructW || s.h > ModLimits.maxStructH || s.cells.count != s.w * s.h {
				r.add(2, mn, place, "It has no captured blocks, or its size is wrong. Capture it again.")
				r.disabled.insert(s.id)
			} else {
				for k in s.cells.indices {
					let v: Int = s.cells[k]
					if v >= 1000 {
						let pi: Int = v - 1000
						let key: String = pi < s.palette.count ? s.palette[pi] : ""
						if (own[key] ?? known[key] ?? "") != "block" { s.cells[k] = -1 }
					} else if v > 255 || v < -1 {
						s.cells[k] = -1
					} else if v >= 0 {
						// custom blocks go by key (their numbers differ per world); machines, bedrock and the
						// rift gate (one per world) can't be copied
						if let t = Tile(rawValue: UInt8(v)), !t.isMod && modStructureTileOK(t) { continue }
						s.cells[k] = -1
					}
				}
			}
			if !s.loot.isEmpty && !lootIDs.contains(s.loot) {
				s.loot = ""
				r.add(1, mn, place, "Its loot table no longer exists.")
			}
			p.structures[i] = s
		}
		checkPlus(&p, mn, sb, known, &r)
		return r
	}

	static func trim<T>(_ a: inout [T], _ n: Int, _ what: String, _ mn: String, _ r: inout ModReport) {
		if a.count > n {
			r.add(1, mn, "Mod", "Only " + String(n) + " " + what + " fit in one mod; the rest were left out.")
			a = Array(a.prefix(n))
		}
	}

	/// Gives empty or repeated ids fresh ones
	static func uniqueIDs(_ p: inout ModPack, _ mn: String, _ r: inout ModReport) {
		var used: Set<String> = []
		var fixed: Int = 0
		func fresh(_ id: String, _ prefix: String) -> String {
			let ok: Bool = !id.isEmpty && id.count <= 24 && !id.contains(":") && !used.contains(id)
			if ok {
				used.insert(id)
				return id
			}
			var n: Int = 1
			while used.contains(prefix + String(n)) { n += 1 }
			used.insert(prefix + String(n))
			fixed += 1
			return prefix + String(n)
		}
		for i in p.blocks.indices { p.blocks[i].id = fresh(p.blocks[i].id, "b") }
		for i in p.items.indices { p.items[i].id = fresh(p.items[i].id, "i") }
		for i in p.mobs.indices { p.mobs[i].id = fresh(p.mobs[i].id, "c") }
		for i in p.projectiles.indices { p.projectiles[i].id = fresh(p.projectiles[i].id, "s") }
		for i in p.recipes.indices { p.recipes[i].id = fresh(p.recipes[i].id, "r") }
		for i in p.loot.indices { p.loot[i].id = fresh(p.loot[i].id, "l") }
		for i in p.ores.indices { p.ores[i].id = fresh(p.ores[i].id, "o") }
		for i in p.structures.indices { p.structures[i].id = fresh(p.structures[i].id, "t") }
		if fixed > 0 { r.add(1, mn, "Mod", String(fixed) + " content ids were missing or repeated and were renumbered.") }
	}

	/// A readable name for an item in a message
	static func itemLabel(_ it: Item, own: ModPack, known: [String: String]) -> String {
		if case .custom(let k) = it {
			let s: (String, String) = splitModKey(k)
			if s.0 == own.id {
				if let b = own.blocks.first(where: { $0.id == s.1 }) { return b.name }
				if let i = own.items.first(where: { $0.id == s.1 }) { return i.name }
			}
			return known[k] != nil ? k : "missing " + k
		}
		return it.name
	}
}

extension Game {
	// MARK: custom creatures in play

	/// Puts a custom creature into the world, sized and given health from its definition. Returns nil
	/// for an unknown slot, or when as many custom creatures as the limit allows are already about.
	@discardableResult
	func addCustomMob(_ slot: Int, _ x: Double, _ y: Double) -> Mob? {
		guard let r = ModRuntime.shared.mob(slot) else { return nil }
		if customMobCount() >= ModLimits.maxActiveMobs { return nil }
		let m = Mob(id: newID(), kind: .custom, x: x, y: y)
		m.cslot = slot
		let d: MobDef = r.mdef
		m.b = Body(x: x, y: y, w: d.w, h: d.h)
		m.maxHP = d.hp * mobHealthMult
		m.hp = m.maxHP
		m.modCD = [Double](repeating: 0, count: r.attacks.count)
		m.lastAtk = -1
		if world.dim == .overworld { m.homeBiome = gen.col(Int(floor(x))).biome.rawValue }
		mobs.append(m)
		if !r.key.isEmpty && !logicRT.isEmpty { fireLogic(.spawned, mob: m, key: r.key) }
		return m
	}

	/// Custom creatures alive right now
	func customMobCount() -> Int {
		var n: Int = 0
		for m in mobs where m.kind == .custom && m.hp > 0 && !m.removed { n += 1 }
		return n
	}

	/// Custom creatures don't feel fire when their maker made them fireproof
	func heatImmune(_ m: Mob) -> Bool {
		if m.kind == .custom { return ModRuntime.shared.mob(m.cslot)?.def.fireproof ?? false }
		return isHeatImmune(m.kind)
	}

	/// A custom creature's turn. Its behaviour switches (see ModBehavior) decide what it does; the game's
	/// creature AI gives it senses and memory (`think`), and every attack it makes hurts through the shared
	/// damage system, so armour, sides, knockback and hit cooldowns work as they do for the game's own.
	func updateCustomMob(_ m: Mob, _ dt: Double) {
		guard let r = ModRuntime.shared.mob(m.cslot) else {
			m.removed = true
			return
		}
		if m.summoned && summonedLeaves(m, dt) { return }
		if !r.def.phases.isEmpty || m.phaseShield > 0 { stepPhases(m, r, dt) }
		let bh: ModBehavior = r.def.behavior
		if m.modCD.count != r.attacks.count { m.modCD = [Double](repeating: 0, count: r.attacks.count) }
		var i: Int = 0
		while i < m.modCD.count {
			if m.modCD[i] > 0 { m.modCD[i] -= dt }
			i += 1
		}
		if bh.burnsInSun && !r.def.fireproof && inSunlight(m) { m.burn = 2.0 }
		if r.guards { followWard(m, r, dt) }
		if r.aquatic && !m.b.inWater {
			// out of the water it flops about and slowly suffocates
			m.dryT += dt
			if m.dryT > 1.0 { m.dryT = 0; hurtMob(m, 1, 0, 0, false) }
		}
		// an attack under way plays out to its end (the warning it showed has to be honest)
		if m.st >= 3 {
			stepCustomAttack(m, r, dt)
			customPhysics(m, r, dt)
			return
		}
		let dist: Double = abs(pb.x - m.b.x)
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		let armed: Bool = r.canAttack
		let calm: Bool = dead || settings.peaceful || !armed
		// after the player: hunting them, paying them back for a hit, or keeping them out of its area
		let provoked: Bool = bh.retaliate && clock - m.lastHitByPlayer < 12.0
		var wants: Bool = !calm && (bh.attackPlayer || provoked)
		if !calm && bh.defendArea {
			let rr: Double = bh.defendRadius * (m.ai == .chase ? 1.5 : 1.0)
			wants = abs(pb.x - m.homeX) < rr && abs(pb.y - m.homeY) < rr
		}
		var engaged: Bool = false
		if wants {
			engaged = think(m, dt, dist, dyP)
			// one that holds its ground is never "stuck against a wall" (no leaps, no backing off)
			if bh.standStill || !(bh.chase || provoked || bh.defendArea) {
				m.leapReq = false
				m.blockedT = 0
				m.progX = m.b.x
			}
		} else {
			if m.ai != .idle { m.ai = .idle; m.aiT = 0 }
			m.why = calm && !armed ? .none : (settings.peaceful ? .peaceful : .none)
		}
		let onPlayer: Bool = engaged && (m.ai == .chase || m.ai == .alert)
		// a creature it fights (guardians go for monsters near them)
		var foe: Mob? = nil
		if bh.attackMobs && armed && !onPlayer {
			if let f = m.foe, f.hp <= 0 || f.removed || f.downed || abs(f.b.x - m.b.x) > max(8.0, r.mdef.aggro) * 1.5 { m.foe = nil }
			m.foeT -= dt
			if m.foe == nil && m.foeT <= 0 {
				m.foeT = 0.5
				m.foe = findFoe(m, r)
			}
			foe = m.foe
		}
		// where it heads this frame: 0 stand, 1 go to (gx, gy), 2 run from gx, 3 wander, 4 patrol
		var mode: Int = 0
		var gx: Double = m.b.x
		var gy: Double = m.b.y
		var spd: Double = 1.0
		var tgtX: Double = 0
		var tgtY: Double = 0
		var hasTarget: Bool = false
		if onPlayer {
			tgtX = pb.x
			tgtY = pb.y - pb.h * 0.55
			hasTarget = true
		} else if let f = foe {
			tgtX = f.b.x
			tgtY = f.b.cy
			hasTarget = true
		}
		if m.t2 > 0 {
			// frightened by a hit (passive creatures, see hurtMob)
			m.t2 -= dt
			mode = 2
			gx = m.tx
			spd = 1.8
		} else if hasTarget {
			let adx: Double = abs(tgtX - m.b.x)
			let shooter: Bool = r.reach.2
			let pursue: Bool = !bh.standStill && (bh.chase || provoked || bh.defendArea || foe != nil)
			if bh.runAway && shooter && adx < r.reach.0 * 0.45 {
				// keeps its distance and shoots
				mode = 2
				gx = tgtX
				spd = 1.1
			} else if shooter && adx < r.reach.0 * 0.8 && (foe != nil || m.sees) {
				mode = 0
			} else if pursue {
				mode = 1
				gx = onPlayer ? m.aimX : tgtX
				gy = tgtY
				spd = adx > 8.0 ? 1.15 : 1.0
			}
			if mode == 0 { m.dir = tgtX >= m.b.x ? 1 : -1 }
		} else if engaged {
			// searching where the player was last seen, or going home (see think)
			if !bh.standStill || m.ai == .back {
				mode = 1
				gx = m.aimX
				gy = m.seenY - 1.0
				spd = 0.85
			}
		} else if bh.runAway, let from = scaryNear(m, r, dt) {
			mode = 2
			gx = from
			spd = 1.5
		} else if bh.followPlayer && !dead && dist < 48 {
			if dist > 3.0 || abs(dyP) > 4.0 {
				mode = 1
				gx = pb.x - Double(facing) * 1.5
				gy = pb.y - 1.5
				spd = dist > 10 ? 1.4 : 1.0
			}
		} else if (r.guards && m.ward != nil) || bh.defendArea {
			// stays by the creature it guards, or in the area it defends
			let away: Double = abs(m.b.x - m.homeX)
			if away > (r.guards ? 3.0 : 4.0) {
				mode = 1
				gx = m.homeX
				gy = m.homeY - 1.0
				spd = away > 10 ? 1.2 : 0.8
			} else if !bh.standStill && bh.wander {
				mode = 3
			}
		} else if bh.standStill {
			mode = 0
		} else if bh.patrol {
			mode = 4
		} else if bh.wander {
			mode = 3
		}
		if bh.stayInBiome && (mode == 3 || mode == 4) && strayed(m, dt) {
			mode = 1
			gx = m.homeX
			gy = m.homeY - 1.0
			spd = 0.8
		}
		moveCustom(m, r, mode, gx, gy, spd * m.phaseSpeed, dt)
		// touching it hurts while it is after the player (its contact damage)
		if onPlayer && m.ai == .chase && r.def.damage > 0 { contactHurt(m, r.def.damage) }
		if hasTarget && m.cd <= 0 && m.daze <= 0, let k = pickCustomAttack(m, r, tgtX, tgtY, foe) {
			startCustomAttack(m, r, k, tgtX, tgtY, foe)
		}
		customPhysics(m, r, dt)
	}

	/// A guard keeps its home beside the creature it guards, and looks for another when that one is gone
	func followWard(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if let w = m.ward, w.hp > 0 && !w.removed {
			m.homeX = w.b.x
			m.homeY = w.b.y
			return
		}
		m.ward = nil
		m.wardT -= dt
		if m.wardT > 0 { return }
		m.wardT = 1.0
		var best: Mob? = nil
		var bd: Double = 30.0
		for o in mobs where o !== m && o.hp > 0 && !o.removed {
			var match: Bool = false
			if r.guardSlot >= 0 { match = o.kind == .custom && o.cslot == r.guardSlot }
			else if let gk = r.guardKind { match = o.kind == gk }
			if !match { continue }
			let d: Double = abs(o.b.x - m.b.x)
			if d < bd {
				bd = d
				best = o
			}
		}
		m.ward = best
	}

	/// The nearest monster a guardian may go for: hostile to the player, within its senses, and on a
	/// side its blows can hurt
	func findFoe(_ m: Mob, _ r: ModMobRT) -> Mob? {
		let range: Double = max(8.0, r.mdef.aggro)
		let src: DamageSource = .mob(m, faction(of: m))
		var best: Mob? = nil
		var bd: Double = range * range
		for o in mobsNear(m.b.x - range, m.b.x + range) {
			if o === m || o.hp <= 0 || o.removed || o.downed || o.tame { continue }
			if !(o.def.hostile || o.isBoss) { continue }
			if o.kind == .custom && o.cslot == m.cslot { continue }
			if !canHarm(src, targetFaction: faction(of: o), targetID: o.id, area: false) { continue }
			let dx: Double = o.b.x - m.b.x
			let dy: Double = o.b.cy - m.b.cy
			let dd: Double = dx * dx + dy * dy
			if dd < bd {
				bd = dd
				best = o
			}
		}
		return best
	}

	/// What a timid creature runs from: the player close by, or (looked for twice a second) a monster
	func scaryNear(_ m: Mob, _ r: ModMobRT, _ dt: Double) -> Double? {
		if r.mdef.hostile { return nil }
		if !dead && abs(pb.x - m.b.x) < 6.0 && abs(pb.y - m.b.y) < 4.0 { return pb.x }
		m.foeT -= dt
		if m.foeT <= 0 {
			m.foeT = 0.5
			m.threat = nearestHostileTo(m.b.x, m.b.cy, 7.0)
		}
		if let t = m.threat, t.hp > 0 && !t.removed && t !== m && abs(t.b.x - m.b.x) < 9.0 { return t.b.x }
		return nil
	}

	/// True when a creature that keeps to its biome has wandered out of it (checked twice a second)
	func strayed(_ m: Mob, _ dt: Double) -> Bool {
		if world.dim != .overworld || m.homeBiome < 0 { return false }
		m.biomeT -= dt
		if m.biomeT <= 0 {
			m.biomeT = 0.5
			let ahead: Int = Int(floor(m.b.x + Double(m.dir) * 2.0))
			m.strayed = gen.col(ahead).biome.rawValue != m.homeBiome
		}
		return m.strayed
	}

	/// Moves a custom creature by the plan made in updateCustomMob: walking, flying or swimming
	func moveCustom(_ m: Mob, _ r: ModMobRT, _ mode: Int, _ gx: Double, _ gy: Double, _ spd: Double, _ dt: Double) {
		let d: MobDef = r.mdef
		let bh: ModBehavior = r.def.behavior
		let swimming: Bool = m.b.inWater && (r.aquatic || bh.swim)
		if d.flying || swimming {
			// free movement: a point to head for (a new one now and then when idle)
			var tx: Double = m.b.x
			var ty: Double = m.b.y
			var sp: Double = d.speed * spd
			switch mode {
			case 1:
				tx = gx
				ty = gy + (d.flying ? sin(clock * 3.0 + Double(m.id)) * 0.8 : 0)
			case 2:
				tx = m.b.x + (m.b.x >= gx ? 6.0 : -6.0)
				ty = m.b.y - (d.flying ? 3.0 : 0)
			case 3, 4:
				m.t1 -= dt
				if m.t1 <= 0 || mode == 4 && abs(m.b.x - m.tx) < 1.0 {
					m.t1 = Double.random(in: 1.5...4.0)
					if mode == 4 {
						m.goal = m.goal >= 0 ? -1 : 1
						m.tx = m.homeX + Double(m.goal) * bh.patrolRange
						m.ty = m.homeY
					} else {
						m.tx = m.homeX + Double.random(in: -8...8)
						m.ty = m.homeY + Double.random(in: -4...3)
					}
				}
				tx = m.tx
				ty = m.ty
				sp *= 0.6
			default:
				sp = 0
			}
			var ax: Double = tx - m.b.x
			var ay: Double = ty - m.b.y
			let len: Double = sqrt(ax * ax + ay * ay)
			if len < 0.4 || sp <= 0 {
				ax = 0
				ay = 0
			} else {
				ax /= len
				ay /= len
			}
			let k: Double = min(1.0, dt * (swimming ? 3.0 : 4.0))
			m.b.vx += (ax * sp - m.b.vx) * k
			m.b.vy += (ay * sp * (swimming ? 0.7 : 1.0) - m.b.vy) * k
			if abs(m.b.vx) > 0.3 { m.dir = m.b.vx > 0 ? 1 : -1 }
			return
		}
		switch mode {
		case 1:
			chase(m, gx, spd, dt)
		case 2:
			flee(m, gx, dt, spd)
		case 3:
			wander(m, dt, 0.5)
		case 4:
			if m.goal == 0 { m.goal = m.dir }
			let end: Double = m.homeX + Double(m.goal) * bh.patrolRange
			if (m.goal > 0 && m.b.x >= end) || (m.goal < 0 && m.b.x <= end) || cliffAhead(m, m.goal) || (m.b.hitWall && m.b.onGround) {
				m.goal = -m.goal
			}
			m.dir = m.goal
			accelX(m, Double(m.goal) * d.speed * 0.6, 14, dt)
		default:
			accelX(m, 0, 18, dt)
		}
	}

	/// Steps a custom creature's body: swimmers glide through water (and never leave it on their own),
	/// fliers bounce off what they hit, walkers use the game's usual physics
	func customPhysics(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if r.aquatic && m.b.inWater {
			let nx: Double = m.b.x + m.b.vx * dt
			let ny: Double = m.b.y + m.b.vy * dt
			let hw: Double = m.b.w * 0.45
			let ix: Int = Int(floor(nx))
			let midWet: Bool = world.tile(ix, Int(floor(ny - m.b.h * 0.5))) == .water
			let topWet: Bool = world.tile(ix, Int(floor(ny - m.b.h + 0.1))).liquid
			let sides: Bool = !world.solid(Int(floor(nx - hw)), Int(floor(ny - m.b.h * 0.5))) && !world.solid(Int(floor(nx + hw)), Int(floor(ny - m.b.h * 0.5)))
			let floorOK: Bool = !world.solid(ix, Int(floor(ny - 0.05)))
			if midWet && topWet && sides && floorOK {
				m.b.x = nx
				m.b.y = ny
			} else {
				m.t1 = 0
				m.b.vx = -m.b.vx * 0.5
				m.b.vy = -m.b.vy * 0.5
			}
			let fw: Double = m.b.w * 0.5
			m.b.inWater = world.liquidFraction(m.b.x - fw, m.b.y - m.b.h, m.b.x + fw, m.b.y, false) > 0.3
			m.anim += dt * 6.0
			return
		}
		if r.def.behavior.swim && m.b.inWater && !r.mdef.flying {
			let sm: Double = m.speedMul
			if sm < 0.999 { m.b.vx *= sm }
			world.moveBody(&m.b, dt, stepUp: 1.0, dropThrough: false, decks: decksCache)
			if sm < 0.999 { m.b.vx /= sm }
			m.anim += dt * 4.0
			return
		}
		stepMob(m, dt)
		if r.mdef.flying {
			m.anim += dt * 6.0
			if m.st < 3 && (m.b.hitWall || m.b.hitCeil || m.b.onGround) {
				m.b.vy = -1.0
				m.t1 = 0
			}
		}
	}

	/// Which of its attacks could reach a target this far away now; one is picked at random (not the
	/// same one twice running when there is a choice)
	func pickCustomAttack(_ m: Mob, _ r: ModMobRT, _ tx: Double, _ ty: Double, _ foe: Mob?) -> Int? {
		let dx: Double = abs(tx - m.b.x)
		let dy: Double = abs(ty - m.b.cy)
		let hw: Double = m.b.w * 0.5
		let footing: Bool = m.b.onGround || r.mdef.flying || m.b.inWater
		var seesFoe: Bool? = nil
		var opts: [Int] = []
		var i: Int = 0
		while i < r.attacks.count && i < m.modCD.count {
			let a: ModAttack = r.attacks[i].def
			if m.modCD[i] > 0 || !phaseAllows(m, r, i) {
				i += 1
				continue
			}
			var ok: Bool = false
			switch a.kind {
			case .melee, .multiHit:
				ok = dx <= a.range + hw + 0.3 && dy <= max(1.8, m.b.h * 0.7 + 0.6)
			case .charge:
				ok = footing && dx >= 2.0 && dx <= max(4.0, a.range * 3.0) && dy < max(2.5, m.b.h)
			case .ranged:
				if dx <= a.range && dy <= a.range * 0.7 + 1.0 {
					if let f = foe {
						if seesFoe == nil { seesFoe = world.lineClear(m.b.x, shotY(m), f.b.x, f.b.cy) }
						ok = seesFoe ?? false
					} else {
						ok = m.sees
					}
				}
			case .area:
				ok = sqrt(dx * dx + dy * dy) <= a.radius + hw
			case .jump:
				ok = footing && dx >= 1.5 && dx <= max(5.0, a.range * 3.0) && dy < 6.0
			case .stomp:
				ok = footing && dx <= max(a.radius * 1.5, a.range + 3.0) && dy < max(2.5, m.b.h)
			}
			if ok { opts.append(i) }
			i += 1
		}
		if opts.isEmpty { return nil }
		if opts.count > 1, let k = opts.firstIndex(of: m.lastAtk) { opts.remove(at: k) }
		return opts[Int.random(in: 0..<opts.count)]
	}

	/// Begins an attack: it turns to the target, starts the attack's cooldown and shows the warning
	func startCustomAttack(_ m: Mob, _ r: ModMobRT, _ i: Int, _ tx: Double, _ ty: Double, _ foe: Mob?) {
		let a: ModAttack = r.attacks[i].def
		m.atk = i
		m.lastAtk = i
		m.modCD[i] = max(0.2, a.cooldown * m.phaseCD)
		m.st = 3
		m.t3 = max(0, a.windup)
		m.atkX = tx
		m.atkY = ty
		m.vsPlayer = foe == nil
		m.dir = tx >= m.b.x ? 1 : -1
		m.atkKey = newID()
		// short wind-ups go unannounced (a warning every fraction of a second would be noise)
		if a.windup >= 0.25 { warnCustomAttack(m, a) }
	}

	/// The red (or orange) box where an attack is about to land
	func warnCustomAttack(_ m: Mob, _ a: ModAttack) {
		let dirD: Double = Double(m.dir)
		let hw: Double = m.b.w * 0.5
		switch a.kind {
		case .melee, .multiHit:
			let reach: Double = a.range + hw + 0.3
			if a.aim == .around {
				warn(m.b.x - reach, m.b.top - 0.3, m.b.x + reach, m.b.y, a.windup)
			} else {
				warn(m.b.x, m.b.top - 0.3, m.b.x + dirD * reach, m.b.y, a.windup)
			}
		case .charge:
			let len: Double = max(4.0, a.range * 3.0) + hw
			warn(m.b.x, m.b.top, m.b.x + dirD * len, m.b.y, a.windup, 0xFFB030)
		case .area:
			let rr: Double = a.radius + hw
			warn(m.b.x - rr, m.b.cy - rr, m.b.x + rr, m.b.cy + rr, a.windup)
		case .stomp:
			let len: Double = max(a.radius * 1.5, a.range + 3.0)
			warn(m.b.x - len, m.b.y - 1.2, m.b.x + len, m.b.y, a.windup, 0xFF8A2A)
		case .jump:
			let rr: Double = max(1.4, hw + 0.9)
			warn(m.atkX - rr, m.atkY - 1.2, m.atkX + rr, m.atkY + 1.2, a.windup)
		case .ranged:
			break
		}
	}

	/// Where the target of the attack under way is now (the player, or the creature it fights)
	func customTargetNow(_ m: Mob) -> (Double, Double)? {
		if m.vsPlayer { return dead ? nil : (pb.x, pb.y - pb.h * 0.55) }
		if let f = m.foe, f.hp > 0 && !f.removed { return (f.b.x, f.b.cy) }
		return nil
	}

	/// Slows a creature that is winding up or recovering (a flyer or swimmer hangs where it is)
	func brakeCustom(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if r.mdef.flying || (m.b.inWater && (r.aquatic || r.def.behavior.swim)) {
			let k: Double = max(0, 1.0 - dt * 6.0)
			m.b.vx *= k
			m.b.vy *= k
		} else {
			accelX(m, 0, 40, dt)
		}
	}

	/// The states of an attack: 3 the wind-up, 4 recovering, 5 charging, 6 a flurry, 7 a leap
	func stepCustomAttack(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		guard m.atk >= 0 && m.atk < r.attacks.count else {
			m.st = 0
			return
		}
		let ar: ModAttackRT = r.attacks[m.atk]
		let a: ModAttack = ar.def
		switch m.st {
		case 3:
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if a.kind == .ranged, let p = customTargetNow(m) { m.dir = p.0 >= m.b.x ? 1 : -1 }
			if m.t3 <= 0 { releaseCustomAttack(m, r, ar) }
		case 4:
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if m.t3 <= 0 {
				m.st = 0
				m.cd = 0.3
			}
		case 5:
			// a straight rush that hurts what it runs into (each thing once)
			m.t3 -= dt
			let cs: Double = max(8.0, r.mdef.speed * 3.2)
			m.b.vx = Double(m.dir) * cs
			if r.mdef.flying { m.b.vy += ((m.atkY - m.b.cy) * 2.0 - m.b.vy) * min(1.0, dt * 4.0) }
			var info = DamageInfo(amount: a.damage, type: .melee, source: .mob(m, faction(of: m)))
			info.dirX = Double(m.dir)
			info.knock = a.knock
			info.originX = m.b.x
			info.key = m.atkKey
			info.cooldown = 1.5
			damageBox(m.b.left - 0.2, m.b.top - 0.1, m.b.right + 0.2, m.b.y + 0.1, info)
			if Double.random(in: 0...1) < 0.4 { spawnParticles(m.b.x - Double(m.dir) * m.b.w * 0.5, m.b.y - 0.1, 0xA08860, 1, 1.5, 0.3, 6) }
			if m.b.hitWall {
				// into a wall: it reels for a moment, a chance to hit back
				addShake(abs(pb.x - m.b.x) < 12 ? 0.15 : 0.04)
				spawnParticles(m.b.x + Double(m.dir) * m.b.w * 0.5, m.b.cy, 0xC0B090, 8, 3.5, 0.4, 10)
				m.b.vx = -Double(m.dir) * 2.0
				m.daze = 0.8
				m.st = 4
				m.t3 = 0.2
			} else if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.35
			}
		case 6:
			// a flurry: a blow every 0.16 s
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if m.t3 <= 0 {
				customBlow(m, a)
				m.phase -= 1
				m.t3 = 0.16
				if m.phase <= 0 {
					m.st = 4
					m.t3 = 0.3
				}
			}
		case 7:
			// in the air on a leap (or a flyer's dive): it comes down on the spot it went for
			m.t3 -= dt
			let landed: Bool = r.mdef.flying ? abs(m.b.x - m.atkX) < 0.8 && abs(m.b.cy - m.atkY) < 1.2 : (m.b.onGround && m.t3 < 1.85)
			if landed || m.t3 <= 0 || (r.mdef.flying && (m.b.hitWall || m.b.onGround)) {
				var info = DamageInfo(amount: a.damage, type: .stomp, source: .mob(m, faction(of: m)))
				info.knock = a.knock
				info.key = m.atkKey
				info.cooldown = 1.0
				info.originX = m.b.x
				let rr: Double = max(1.4, m.b.w * 0.5 + 0.9)
				damageArea(m.b.x, m.b.y - min(0.8, m.b.h * 0.5), radius: rr, info, falloff: false, lineOfSight: false)
				spawnParticles(m.b.x, m.b.y - 0.1, 0xA08860, 10, 4.0, 0.45, 14)
				addShake(abs(pb.x - m.b.x) < 12 ? 0.18 : 0.04)
				sfx(.land, at: m.b.x, 0.8)
				m.st = 4
				m.t3 = 0.35
			}
		default:
			m.st = 0
		}
	}

	/// The moment an attack lands (or sets off)
	func releaseCustomAttack(_ m: Mob, _ r: ModMobRT, _ ar: ModAttackRT) {
		let a: ModAttack = ar.def
		// shots and leaps aim at where the target is now; blows land where the warning showed
		if a.kind == .ranged || a.kind == .jump, let p = customTargetNow(m) {
			m.atkX = p.0
			m.atkY = p.1
		}
		m.atkT = Mob.atkDur
		switch a.kind {
		case .melee:
			customBlow(m, a)
			m.st = 4
			m.t3 = 0.25
		case .multiHit:
			m.phase = max(1, a.hits)
			m.st = 6
			m.t3 = 0
		case .charge:
			let cs: Double = max(8.0, r.mdef.speed * 3.2)
			m.st = 5
			m.t3 = clampD((max(4.0, a.range * 3.0) + m.b.w * 0.5) / cs, 0.3, 2.0)
			sfx(.roar, at: m.b.x, 0.5)
		case .ranged:
			fireCustomShots(m, r, ar)
			m.st = 4
			m.t3 = 0.25
		case .area:
			var info = DamageInfo(amount: a.damage, type: .impact, source: .mob(m, faction(of: m)))
			info.knock = a.knock
			info.key = m.atkKey
			info.cooldown = 1.0
			damageArea(m.b.x, m.b.cy, radius: a.radius + m.b.w * 0.5, info, falloff: false, lineOfSight: true)
			spawnParticles(m.b.x, m.b.cy, 0xFFD070, 18, 6.5, 0.45, 0)
			addShake(abs(pb.x - m.b.x) < 14 ? 0.2 : 0.05)
			sfx(.explosion, at: m.b.x, 0.5)
			m.st = 4
			m.t3 = 0.35
		case .jump:
			if r.mdef.flying {
				// a flyer dives at the target instead
				let dx: Double = m.atkX - m.b.x
				let dy: Double = m.atkY - m.b.cy
				let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
				let sp: Double = max(9.0, r.mdef.speed * 3.0)
				m.b.vx = dx / len * sp
				m.b.vy = dy / len * sp
				m.t3 = clampD(len / sp + 0.25, 0.3, 1.6)
			} else {
				let vy: Double = -max(10.0, r.mdef.jump * 1.1)
				let flight: Double = max(0.3, 2.0 * abs(vy) / gravityG)
				m.b.vy = vy
				m.b.vx = clampD((m.atkX - m.b.x) / flight, -14, 14)
				m.t3 = 2.0
			}
			m.st = 7
		case .stomp:
			var info = DamageInfo(amount: a.damage, type: .stomp, source: .mob(m, faction(of: m)))
			info.knock = a.knock
			info.key = m.atkKey
			info.cooldown = 1.0
			info.originX = m.b.x
			damageArea(m.b.x, m.b.y - 0.4, radius: a.radius + m.b.w * 0.5, info, falloff: true, lineOfSight: false)
			// shockwaves run along the ground: both ways, or only forward
			let len: Double = max(a.radius * 1.5, a.range + 3.0)
			let sp: Double = 12.0
			let dirs: [Double] = a.aim == .forward ? [Double(m.dir)] : [-1.0, 1.0]
			for sgn in dirs where projectiles.count < 400 {
				var p = Projectile(kind: .shock, x: m.b.x + sgn * (m.b.w * 0.5), y: m.b.y - 0.5, vx: sgn * sp, vy: 0, dmg: a.damage * 0.8, fromPlayer: false, gravity: 0)
				p.life = len / sp
				p.w = 0.6
				p.owner = m.id
				p.source = .mob(m, faction(of: m))
				p.uid = newID()
				projectiles.append(p)
			}
			addShake(abs(pb.x - m.b.x) < 16 ? 0.35 : 0.08)
			spawnParticles(m.b.x, m.b.y - 0.1, 0xA08860, 16, 6.0, 0.55, 12)
			sfx(.land, at: m.b.x, 1.0)
			m.st = 4
			m.t3 = 0.4
		}
	}

	/// A melee blow over the box the warning showed
	func customBlow(_ m: Mob, _ a: ModAttack) {
		let hw: Double = m.b.w * 0.5
		let reach: Double = a.range + hw + 0.3
		let top: Double = m.b.top - 0.3
		let bottom: Double = m.b.y + 0.1
		m.atkT = Mob.atkDur
		switch a.aim {
		case .around:
			mobAttackBox(m, m.b.x - reach, top, m.b.x + reach, bottom, dmg: a.damage, knock: a.knock)
		case .down:
			mobAttackBox(m, m.b.x - hw - 0.3, m.b.cy, m.b.x + hw + 0.3, m.b.y + reach, dmg: a.damage, knock: a.knock)
		default:
			mobAttackBox(m, m.b.x - Double(m.dir) * 0.3, top, m.b.x + Double(m.dir) * reach, bottom, dmg: a.damage, knock: a.knock)
		}
		sfx(.swing, at: m.b.x, 0.5)
	}

	/// Shots of a custom creature's ranged attack: one aimed or straight ahead, a ring, or one dropped
	/// straight down. Custom shots behave as their maker set them up.
	func fireCustomShots(_ m: Mob, _ r: ModMobRT, _ ar: ModAttackRT) {
		let a: ModAttack = ar.def
		var live: Int = 0
		for p in projectiles where p.mod >= 0 || p.owner >= 0 { live += 1 }
		if live >= ModLimits.maxShotsLive { return }
		let ox: Double = m.b.x + Double(m.dir) * (m.b.w * 0.5 + 0.1)
		let oy: Double = r.mdef.flying ? m.b.cy : shotY(m)
		let speed: Double = max(4.0, a.speed)
		var grav: Double = 0
		var life: Double = clampD(a.range / speed * 1.5 + 0.2, 0.3, 6.0)
		var kind: ProjKind = .bullet
		if ModGameShots.kinds.contains(a.shot), let k = ProjKind(rawValue: a.shot) { kind = k }
		var w: Double = 0.3
		var pierce: Int = 0
		var modIdx: Int = -1
		if ar.shot >= 0 && ar.shot < ModRuntime.shared.shots.count {
			let s: ModProjectile = ModRuntime.shared.shots[ar.shot]
			grav = s.gravity
			life = s.life
			kind = .spit
			w = s.size
			pierce = s.pierce
			modIdx = ar.shot
		} else {
			switch kind {
			case .arrow, .quarrel: grav = 15
			case .rock: grav = 22; w = 0.6
			case .pebble: grav = 12
			default: grav = 0
			}
		}
		var angles: [Double] = []
		switch a.aim {
		case .forward:
			angles = [m.dir > 0 ? 0 : Double.pi]
		case .atTarget:
			angles = [lobAngle(m.atkX - ox, m.atkY - oy, speed, grav)]
		case .around:
			let n: Int = clampI(a.hits, 3, 12)
			for k in 0..<n { angles.append(Double(k) / Double(n) * 2.0 * Double.pi) }
		case .down:
			angles = [Double.pi * 0.5]
		}
		for ang in angles {
			if live >= ModLimits.maxShotsLive { break }
			var p = Projectile(kind: kind, x: ox, y: oy, vx: cos(ang) * speed, vy: sin(ang) * speed, dmg: a.damage, fromPlayer: false, gravity: grav)
			p.life = life
			p.owner = m.id
			p.source = .mob(m, faction(of: m))
			p.uid = newID()
			p.knock = a.knock
			p.w = w
			p.pierce = pierce
			p.mod = modIdx
			projectiles.append(p)
			live += 1
		}
		spawnParticles(ox, oy, kind == .fireball ? 0xFF7020 : 0xFFE080, 3, 2.0, 0.18, 0)
		switch kind {
		case .arrow, .quarrel: sfx(.bow, at: m.b.x, 0.5)
		case .bullet, .pellet: sfx(.gun, at: m.b.x, 0.5)
		case .rock, .pebble: sfx(.sling, at: m.b.x, 0.5)
		default: sfx(.zap, at: m.b.x, 0.45)
		}
	}

	/// A custom creature's drops and its loot table, when it dies
	func dropModLoot(_ m: Mob, _ rng: inout RNG) {
		guard let r = ModRuntime.shared.mob(m.cslot) else { return }
		for d in r.drops {
			if rng.double() >= d.chance { continue }
			let lo: Int = max(1, d.min)
			let n: Int = lo + rng.int(max(1, d.max - lo + 1))
			spawnDrop(Stack(item: d.item, count: n), m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2...2), -4.5)
		}
		if !r.loot.isEmpty {
			for s in ModRuntime.shared.roll(r.loot, &rng) {
				spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2.5...2.5), -5.0)
			}
		}
		if r.boss {
			say(joinText(r.def.name, " is defeated!"), 3.0)
			sfx(.discovery, 0.8)
		}
	}
}

// MARK: - The mods a world uses, turned into game content

/// Which mods a world was made with, and which tile number each of their blocks has in it. Saved with
/// the world, so its blocks keep their numbers whatever else is installed.
struct ModWorldInfo: Codable, Equatable {
	var mods: [ModDep] = []
	/// block key ("mod:id", or "mod:id#alt" for a door's open or a lamp's lit state) -> tile number
	var blocks: [String: Int] = [:]
	/// custom infusion key -> its number on items
	var infusions: [String: Int] = [:]
	/// custom dimension key -> its slot (0 to 2)
	var dims: [String: Int] = [:]

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		mods = c.list(.mods, &skip)
		blocks = c.val(.blocks, [:])
		infusions = c.val(.infusions, [:])
		dims = c.val(.dims, [:])
	}
}

/// A mod a world depends on
struct ModDep: Codable, Equatable, Identifiable {
	var id: String
	var name: String
	var author: String
	var version: String
}

/// A custom item ready to use: its checked definition plus everything worked out once
final class ModItemRT {
	let key: String
	let def: ModItem
	let modName: String
	var melee: MeleeProfile
	var ammo: Item? = nil
	/// index into ModRuntime.shots, or -1 for a game shot
	var shot: Int = -1
	var icon: PixelBuf

	init(key: String, def: ModItem, modName: String) {
		self.key = key
		self.def = def
		self.modName = modName
		let st: SwingStyle = SwingStyle(rawValue: def.style) ?? .slash
		var p = MeleeProfile(damage: def.damage, cooldown: def.cooldown, reach: def.reach, halfArc: def.arc, style: st)
		p.band = 0.55
		p.maxHits = def.maxHits
		p.knock = def.knock
		p.heavy = def.heavy
		p.daze = def.daze
		p.windup = def.windup
		p.swingTime = clampD(def.cooldown * 0.6, 0.14, 0.5)
		p.moveScale = def.heavy ? 0.6 : 1.0
		p.critChance = def.crit
		p.burn = def.burn
		p.undeadMult = def.undeadMult
		p.combo = def.combo
		p.backstab = def.backstab
		p.trail = def.trail
		if def.kind != .melee && def.kind != .tool {
			// bows, guns and the rest only bash when swung
			p = MeleeProfile(damage: 2.0, cooldown: 0.4, reach: 1.9, halfArc: 0.7, style: .bash, knock: 4, swingTime: 0.22, trail: 0xD0D0D0)
		}
		melee = p
		icon = PixelBuf(w: 16, h: 16)
	}
}

extension ModItemRT {
	/// where it sorts in the bag (weapons first, materials last), like the game's own items
	var sortGroup: Int {
		switch def.kind {
		case .melee: return 0
		case .bow, .gun, .thrown, .magic: return 1
		case .ammo: return 2
		case .tool: return 3
		case .armor: return 4
		case .food, .consumable: return 5
		case .special: return 6
		case .material: return 10
		}
	}

	/// Tooltip lines: what it is, its numbers, and which mod it comes from
	var infoLines: [String] {
		let d: ModItem = def
		var lines: [String] = [d.desc.isEmpty ? d.kind.name : d.desc]
		switch d.kind {
		case .melee:
			lines.append(String(format: "Damage %.1f · every %.2f s · reach %.1f", d.damage, d.cooldown, d.reach))
		case .bow, .gun, .thrown, .magic:
			var l: String = String(format: "Damage %.1f · every %.2f s", d.damage, d.cooldown)
			if d.kind == .gun { l += " · " + String(d.magazine) + " loaded" }
			lines.append(l)
			if let a = ammo { lines.append("Uses " + a.name) }
		case .tool:
			let tt: ToolType = ToolType(rawValue: d.toolType) ?? .pickaxe
			lines.append(tt.name + String(format: " · tier %d · speed x%.1f", d.toolTier, d.toolSpeed))
		case .armor:
			let sl: ArmorSlot = ArmorSlot(rawValue: d.slot) ?? .head
			lines.append(sl.name + String(format: " · defense +%.1f", d.defense))
		case .food, .consumable:
			var parts: [String] = []
			if d.hunger > 0 { parts.append(String(format: "+%.0f hunger", d.hunger)) }
			for e in d.effects { parts.append(e.kind.name) }
			if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
		default:
			break
		}
		lines.append("From " + modName)
		return lines
	}
}

/// A resolved attack of a custom creature
struct ModAttackRT {
	var def: ModAttack
	var shot: Int
}

/// A custom creature ready to use
final class ModMobRT {
	let key: String
	let def: ModMob
	let modName: String
	var mdef: MobDef
	var base: MobKind
	var attacks: [ModAttackRT] = []
	var drops: [ModDrop] = []
	var loot: String = ""
	var faction: Faction = .hostile
	var boss: Bool = false
	/// kind it guards: a game creature, or a custom one (slot)
	var guardKind: MobKind? = nil
	var guardSlot: Int = -1

	init(key: String, def: ModMob, modName: String) {
		self.key = key
		self.def = def
		self.modName = modName
		let b: MobKind = MobKind(rawValue: def.base) ?? .zombie
		base = b
		let bd: MobDef = mobDef(b)
		var beh: Behavior = .hostile
		switch def.category {
		case .passive: beh = .passive
		case .neutral: beh = .defensive
		case .hostile: beh = .hostile
		case .boss: beh = .boss
		case .flying: beh = .flyer
		case .water: beh = .swimmer
		}
		// a creature that goes for the player unprovoked counts as a monster (limits, despawning, pets)
		let hostile: Bool = def.category == .hostile || def.category == .boss || (def.category != .passive && def.behavior.attackPlayer)
		let fly: Bool = def.behavior.fly || def.category == .flying
		mdef = MobDef(name: def.name, w: clampD(bd.w * def.scale, 0.3, 8), h: clampD(bd.h * def.scale, 0.3, 8), hp: def.hp, speed: def.speed,
						dmg: def.damage, behavior: beh, flying: fly, aggro: def.detect, jump: def.jump, hostile: hostile)
		boss = def.category == .boss
		// a guardian that fights monsters but never the player is on the player's side
		if boss { faction = .boss }
		else if hostile { faction = .hostile }
		else if def.behavior.attackMobs { faction = .ally }
		else { faction = .wild }
	}

	/// how far its attacks reach (across, up or down) and whether the longest is a shot (see think)
	var reach: (Double, Double, Bool) = (1.0, 1.4, false)
	/// creatures that live in water (they flop about on land)
	var aquatic: Bool { return def.category == .water }
	/// it can hurt something: it has attacks, or hurts by touch
	var canAttack: Bool { return !attacks.isEmpty || def.damage > 0 }
	/// it stays beside another kind of creature
	var guards: Bool { return guardSlot >= 0 || guardKind != nil }

	/// Works out what its attacks reach, once they are known
	func finish() {
		var across: Double = mdef.w * 0.5 + 0.5
		var up: Double = 1.4
		var shot: Bool = false
		for a in attacks {
			let d: ModAttack = a.def
			var r: Double = 0
			var h: Double = 1.4
			switch d.kind {
			case .ranged:
				if d.range > across || !shot {
					across = max(d.range, shot ? across : 0)
					up = d.range * 0.7 + 1.0
					shot = true
				}
				continue
			case .charge, .jump:
				r = max(4.0, d.range * 3.0)
				h = 2.5
			case .area, .stomp:
				r = d.radius + mdef.w * 0.5
				h = max(1.4, d.radius)
			case .melee, .multiHit:
				r = d.range + mdef.w * 0.5 + 0.3
				h = max(1.8, mdef.h * 0.7 + 0.6)
			}
			if !shot && r > across {
				across = r
				up = h
			}
		}
		reach = (across, up, shot)
	}

	/// Share of a hit of this kind that gets through its hide
	func resist(_ t: DamageType) -> Double {
		let tough: Double = 1.0 - clampD(def.defense, 0, 0.9)
		switch t {
		case .fire, .lava: return def.fireproof ? 0 : tough
		case .fall: return mdef.flying || aquatic ? 0 : tough
		case .drown: return aquatic || def.behavior.swim ? 0 : 1
		default: return tough
		}
	}
}

/// A custom ore, resolved to its tile
struct ModOreRT {
	var tile: Tile
	var dim: Int
	var minY: Int
	var maxY: Int
	var veins: Double
	var size: Int
	var host: Int
	var salt: UInt64
	var place: Int = 0
	var biomes: Set<Int> = []
	var rarity: Double = 1
	var shape: Int = 0
	var nearTile: Tile? = nil
	var hostTiles: Set<UInt8> = []
}

/// A custom structure with its cells turned into tile numbers (-1: leave the ground as it is)
struct ModStructRT {
	var key: String
	var def: ModStructure
	var cells: [Int]
	var salt: UInt64
	var loot: String
}

/// A custom creature's spawning, resolved
struct ModSpawnRT {
	var slot: Int
	var spawn: ModSpawn
}

final class ModRuntime {
	/// what the current world uses (empty in the menu and in worlds without mods)
	static var shared: ModRuntime = ModRuntime()

	var packs: [ModPack] = []
	var reports: [ModReport] = []
	/// mods the world needs that are not installed
	var missing: [ModDep] = []
	/// content left out by the checks, by key
	var disabled: Set<String> = []
	// blocks: per reserved slot (0 ..< blockSlots) its key, definition and art
	var slotKey: [String?] = [String?](repeating: nil, count: ModLimits.blockSlots)
	var slotDef: [ModBlock?] = [ModBlock?](repeating: nil, count: ModLimits.blockSlots)
	/// true for the second state of a door (open) or a lamp (lit)
	var slotAlt: [Bool] = [Bool](repeating: false, count: ModLimits.blockSlots)
	var slotArt: [PixelBuf?] = [PixelBuf?](repeating: nil, count: ModLimits.blockSlots)
	var slotDrop: [Stack?] = [Stack?](repeating: nil, count: ModLimits.blockSlots)
	var slotTool: [ToolType] = [ToolType](repeating: .pickaxe, count: ModLimits.blockSlots)
	var tileForKey: [String: Tile] = [:]
	var items: [String: ModItemRT] = [:]
	var itemOrder: [String] = []
	var mobs: [ModMobRT] = []
	var mobSlot: [String: Int] = [:]
	var shots: [ModProjectile] = []
	var shotIndex: [String: Int] = [:]
	var loot: [String: ModLootTable] = [:]
	/// loot tables that also turn up in the world's chests
	var chestTables: [String] = []
	var recipes: [Recipe] = []
	var ores: [ModOreRT] = []
	var structures: [ModStructRT] = []
	var spawns: [ModSpawnRT] = []
	/// the custom creatures' spawning as rules beside the game's own (see updateSpawning)
	var spawnRules: [SpawnRule] = []
	/// names of missing mods by id (for "Missing block" labels)
	var missingNames: [String: String] = [:]
	/// custom infusions by their number on items, and the numbers by key
	var infusionDefs: [Int: ModInfusionRT] = [:]
	var infusionNumber: [String: Int] = [:]
	/// every way to summon a custom creature, ready for play
	var summons: [ModSummonRT] = []
	/// the Logic Studio scripts of the world's mods, compiled
	var logic: LogicRT = LogicRT()
	/// the world's three custom dimension slots, and the key each holds (kept for missing mods)
	var dimSlots: [ModDimRT?] = [nil, nil, nil]
	var dimSlotKey: [String?] = [nil, nil, nil]

	var active: Bool { return !packs.isEmpty || !missing.isEmpty }
	var hasWorldGen: Bool { return !ores.isEmpty || !structures.isEmpty }

	// MARK: switching mods on

	/// Builds the runtime for these mods (in load order) and installs it: tiles, recipes and art all
	/// change to match. `world` is the saved mapping of an existing world (nil for a new world).
	/// Nothing here can stop the game: broken content is left out and reported.
	@discardableResult
	static func activate(_ list: [ModPack], world: ModWorldInfo?) -> ModRuntime {
		let rt = ModRuntime()
		let known: [String: String] = ModCatalog.build(list).keys
		var seen: Set<String> = []
		for p0 in list {
			if rt.packs.count >= ModLimits.maxMods { break }
			if p0.id.isEmpty || seen.contains(p0.id) { continue }
			seen.insert(p0.id)
			var p: ModPack = p0
			let rep: ModReport = ModValidator.check(&p, known: known)
			rt.reports.append(rep)
			if rep.fatal { continue }
			rt.packs.append(p)
			for d in rep.disabled { rt.disabled.insert(p.key(d)) }
			// content the maker switched off for now
			for d in p.off { rt.disabled.insert(p.key(d)) }
		}
		// a mod that needs another that is not on: say so (what it uses from it is left out)
		for p in rt.packs {
			for dep in ModStore.dependencies(p) where !rt.packs.contains(where: { $0.id == dep }) {
				var dr = ModReport()
				let name: String = ModStore.pack(dep)?.name ?? dep
				dr.add(2, p.name, "Mod", joinText("Needs the mod \u{201C}", name, "\u{201D}, which is not on: what it uses from it is left out."))
				rt.reports.append(dr)
			}
		}
		if let w = world {
			for d in w.mods where !rt.packs.contains(where: { $0.id == d.id }) {
				rt.missing.append(d)
				rt.missingNames[d.id] = d.name
			}
		}
		rt.assignBlocks(world)
		rt.buildShots()
		rt.buildItems()
		rt.buildInfusions(world)
		rt.buildLoot()
		rt.buildMobs()
		rt.buildSummons()
		rt.buildDims(world)
		rt.logic = LogicRT.build(rt.packs, rt.disabled)
		rt.buildRecipes()
		rt.buildOres()
		rt.buildStructures()
		OverrideRT.shared = OverrideRT.build(rt.packs, rt.disabled)
		shared = rt
		rt.install()
		return rt
	}

	/// Back to no mods (the menu, a world without mods)
	static func deactivate() {
		activate([], world: nil)
	}

	/// Every issue of every active mod
	var issues: [ModIssue] {
		var out: [ModIssue] = []
		for r in reports { out.append(contentsOf: r.issues) }
		return out
	}

	/// What a world made now should remember
	func worldInfo() -> ModWorldInfo {
		var w = ModWorldInfo()
		for p in packs { w.mods.append(ModDep(id: p.id, name: p.name, author: p.author, version: p.version)) }
		for d in missing { w.mods.append(d) }
		for i in 0..<ModLimits.blockSlots {
			if let k = slotKey[i] { w.blocks[k] = Int(Tile.modBase) + i }
		}
		for (k, n) in infusionNumber { w.infusions[k] = n }
		for i in 0..<dimSlotKey.count { if let k = dimSlotKey[i] { w.dims[k] = i } }
		return w
	}

	// MARK: blocks

	func assignBlocks(_ world: ModWorldInfo?) {
		// the keys each mod block needs: one, or two for doors and lamps
		var wanted: [(String, ModBlock, Bool)] = []
		for p in packs {
			for b in p.blocks where !disabled.contains(p.key(b.id)) {
				wanted.append((p.key(b.id), b, false))
				if b.function.paired { wanted.append((p.key(b.id) + "#alt", b, true)) }
			}
		}
		var taken: [Bool] = [Bool](repeating: false, count: ModLimits.blockSlots)
		let base: Int = Int(Tile.modBase)
		// first the numbers the world already gave them (and the slots of blocks that are missing now)
		if let w = world {
			for (k, raw) in w.blocks {
				let i: Int = raw - base
				if i < 0 || i >= ModLimits.blockSlots || taken[i] { continue }
				taken[i] = true
				slotKey[i] = k
			}
		}
		var free: Int = 0
		var overflow: Int = 0
		for (k, b, alt) in wanted {
			var i: Int = -1
			if let found = slotKey.firstIndex(where: { $0 == k }) { i = found }
			if i < 0 {
				while free < ModLimits.blockSlots && taken[free] { free += 1 }
				if free >= ModLimits.blockSlots {
					overflow += 1
					continue
				}
				i = free
				taken[i] = true
				slotKey[i] = k
			}
			slotDef[i] = b
			slotAlt[i] = alt
			slotTool[i] = ToolType(rawValue: b.tool) ?? .pickaxe
			if let t = Tile(rawValue: UInt8(base + i)) { tileForKey[k] = t }
		}
		if overflow > 0 {
			var rep = ModReport()
			rep.add(2, "Mods", "Blocks", String(overflow) + " custom blocks did not fit (a world holds " + String(ModLimits.blockSlots) + ") and were left out.")
			reports.append(rep)
		}
	}

	/// The tile of a block key (nil if it has none in this world)
	func tile(_ key: String) -> Tile? { return tileForKey[key] }

	/// Slot index of a tile (nil for game tiles)
	@inline(__always) func slot(_ t: Tile) -> Int? {
		let i: Int = Int(t.rawValue) - Int(Tile.modBase)
		return i >= 0 && i < ModLimits.blockSlots ? i : nil
	}

	func blockDef(_ t: Tile) -> ModBlock? {
		guard let i = slot(t) else { return nil }
		return slotDef[i]
	}

	func isAlt(_ t: Tile) -> Bool {
		guard let i = slot(t) else { return false }
		return slotAlt[i]
	}

	/// The other state of a door or lamp tile
	func partner(_ t: Tile) -> Tile? {
		guard let i = slot(t), let k = slotKey[i] else { return nil }
		if slotAlt[i] { return tileForKey[String(k.dropLast(4))] }
		return tileForKey[k + "#alt"]
	}

	/// A game item for a mod reference: blocks become their tile, items stay custom
	func resolve(_ it: Item) -> Item {
		if case .custom(let k) = it, let t = tileForKey[k] { return .block(t) }
		return it
	}

	/// The tile definition the game uses for a slot
	func tileDef(_ i: Int) -> TileDef {
		guard let b = slotDef[i] else {
			var d = TileDef(name: missingLabel(i))
			d.hard = 9999
			d.style = .custom
			d.colors = [0xFF00FF, 0x200020, 0xFF00FF, 0x200020, 0xFF00FF]
			d.noDrop = true
			return d
		}
		let alt: Bool = slotAlt[i]
		var d = TileDef(name: b.name)
		d.hard = b.unbreakable ? 9999 : b.hardness
		d.tier = b.tier
		d.solid = b.collision == .solid
		d.platform = b.collision == .platform
		d.opaque = d.solid && !b.transparent
		d.light = b.light
		d.hurt = b.function == .trap
		d.style = .custom
		if b.function == .door && alt {
			d.solid = false
			d.opaque = false
		}
		if b.function == .lamp {
			d.light = alt ? max(b.light, 12) : 0
		}
		let art: PixelBuf = b.art.buf()
		d.colors = [averageColor(art), averageColor(art), averageColor(art), averageColor(art), averageColor(art)]
		d.noDrop = !b.dropSelf && b.drop == nil
		if alt { d.drop = .block(tileForKey[String((slotKey[i] ?? "").dropLast(4))] ?? .stone) }
		return d
	}

	func missingLabel(_ i: Int) -> String {
		guard let k = slotKey[i] else { return "Unused Mod Block" }
		let m: String = splitModKey(k).0
		return "Missing block (" + (missingNames[m] ?? "a mod") + ")"
	}

	/// What breaking a custom block drops (nil: the game's usual rule)
	func blockDrops(_ t: Tile) -> [Stack]? {
		guard let i = slot(t) else { return nil }
		guard let b = slotDef[i] else { return [] }
		if slotAlt[i] {
			if let main = partner(t) { return [Stack(item: .block(main), count: 1)] }
			return []
		}
		if b.dropSelf { return [Stack(item: .block(t), count: max(1, b.dropCount))] }
		if let d = b.drop { return [Stack(item: resolve(d), count: max(1, b.dropCount))] }
		return []
	}

	// MARK: items

	func buildItems() {
		for p in packs {
			for it in p.items where !disabled.contains(p.key(it.id)) {
				let k: String = p.key(it.id)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				if let a = it.ammo { r.ammo = resolve(a) }
				if !it.projectile.isEmpty { r.shot = shotIndex[p.key(it.projectile)] ?? -1 }
				r.icon = itemIconBuf(it)
				items[k] = r
				itemOrder.append(k)
			}
		}
	}

	func item(_ key: String) -> ModItemRT? { return items[key] }

	/// The icon of a custom item: its own picture, or the chosen game item's icon tinted
	func itemIconBuf(_ it: ModItem) -> PixelBuf {
		if !it.icon.isBlank {
			var b: PixelBuf = it.icon.buf()
			b = padBuf(b)
			if it.icon.outlined(true) { b.outline(0x1A1410) }
			return b
		}
		if let base = it.baseIcon {
			var b: PixelBuf = itemBuf(resolve(base))
			if it.tintAmt > 0.01 { b = b.tinted(it.tint & 0xFFFFFF, it.tintAmt) }
			return b
		}
		var b = PixelBuf(w: 12, h: 12)
		b.rect(2, 2, 8, 8, 0x9A8A70)
		b.rect(4, 4, 4, 4, 0xC8B898)
		b.outline(0x1A1410)
		return b
	}

	// MARK: shots, loot, creatures, recipes, ores, structures

	func buildShots() {
		for p in packs {
			for s in p.projectiles {
				shotIndex[p.key(s.id)] = shots.count
				shots.append(s)
			}
		}
	}

	func buildLoot() {
		for p in packs {
			for l0 in p.loot where !disabled.contains(p.key(l0.id)) {
				var l: ModLootTable = l0
				for k in l.entries.indices { l.entries[k].item = resolve(l.entries[k].item) }
				loot[p.key(l.id)] = l
				if l.chestChance > 0 { chestTables.append(p.key(l.id)) }
			}
		}
	}

	/// A chest's contents with the world's mods: the tables set to turn up in chests each get their
	/// chance, rolled from the chest's position (the same chest always holds the same), up to a full chest
	func addChestLoot(_ base: [Stack], _ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> [Stack] {
		var out: [Stack] = base
		for key in chestTables {
			guard let l = loot[key] else { continue }
			let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data(key.utf8)))
			var rng = RNG(hashU(x, y &+ dim.rawValue &* 7_919, g.seed &+ salt))
			if rng.double() >= l.chestChance { continue }
			for st in roll(key, &rng) where out.count < 27 { out.append(st) }
		}
		return out
	}

	/// Rolls a loot table: each roll picks one entry (or nothing) by weight
	func roll(_ key: String, _ rng: inout RNG) -> [Stack] {
		guard let l = loot[key] else { return [] }
		let total: Double = l.totalWeight
		if total <= 0 { return [] }
		var out: [Stack] = []
		for _ in 0..<l.rolls {
			var r: Double = rng.double() * total
			r -= max(0, l.nothing)
			if r < 0 { continue }
			for e in l.entries {
				r -= max(0, e.effectiveWeight)
				if r < 0 {
					let n: Int = e.min + rng.int(max(1, e.max - e.min + 1))
					out.append(Stack(item: e.item, count: max(1, n)))
					break
				}
			}
		}
		return out
	}

	func buildMobs() {
		for p in packs {
			for m in p.mobs where !disabled.contains(p.key(m.id)) {
				let k: String = p.key(m.id)
				let r = ModMobRT(key: k, def: m, modName: p.name)
				for a in m.attacks {
					let si: Int = a.projectile.isEmpty ? -1 : (shotIndex[p.key(a.projectile)] ?? -1)
					r.attacks.append(ModAttackRT(def: a, shot: si))
				}
				for d0 in m.drops {
					var d: ModDrop = d0
					d.item = resolve(d.item)
					r.drops.append(d)
				}
				if !m.loot.isEmpty && loot[p.key(m.loot)] != nil { r.loot = p.key(m.loot) }
				mobSlot[k] = mobs.count
				mobs.append(r)
				if m.spawn.enabled { spawns.append(ModSpawnRT(slot: mobs.count - 1, spawn: m.spawn)) }
			}
		}
		// who guards whom (custom kinds are known only now)
		for r in mobs where !r.def.behavior.guardKey.isEmpty {
			let gk: String = r.def.behavior.guardKey
			if let s = mobSlot[gk] { r.guardSlot = s } else { r.guardKind = MobKind.allCases.first { mobDef($0).name == gk } }
		}
		for r in mobs { r.finish() }
		buildSpawnRules()
	}

	/// Turns each custom creature's spawning settings into a rule the game's spawner understands
	func buildSpawnRules() {
		spawnRules = []
		for s in spawns {
			guard let r = mob(s.slot) else { continue }
			let sp: ModSpawn = s.spawn
			var place: SpawnPlace = .surface
			switch sp.place {
			case .surface, .sky: place = .surface
			case .cave: place = .cave
			case .ocean: place = .ocean
			case .umbral: place = .umbral
			}
			let when: SpawnWhen = sp.when == 1 ? .day : (sp.when == 2 ? .night : .any)
			var biomes: [Biome] = []
			for b in sp.biomes {
				if let bb = Biome(rawValue: b) { biomes.append(bb) }
			}
			var rule = SpawnRule(kind: .custom, weight: max(0, sp.weight), place: place, when: when, biomes: biomes, group: max(1, sp.group), minY: sp.minY, maxY: sp.maxY)
			rule.slot = s.slot
			rule.maxNearby = max(1, sp.maxNearby)
			rule.sky = sp.place == .sky && r.mdef.flying
			if rule.weight > 0 { spawnRules.append(rule) }
		}
	}

	func mob(_ slot: Int) -> ModMobRT? { return slot >= 0 && slot < mobs.count ? mobs[slot] : nil }

	func buildRecipes() {
		var list: [Recipe] = []
		var nextID: Int = RecipeBook.base.count
		for p in packs {
			for r in p.recipes where !disabled.contains(p.key(r.id)) {
				let out: Item = resolve(r.out)
				var lines: [CostLine] = []
				for c in r.cost { lines.append(CostLine(item: resolve(c.item), n: c.n)) }
				let st: Station = Station(rawValue: max(0, r.station)) ?? .hand
				var rec = Recipe(id: nextID, out: out, outCount: r.count, cost: lines, station: r.station < 0 ? .hand : st, cat: RecipeCat(rawValue: r.cat) ?? .mods)
				if r.station < 0 { rec.modStation = tileForKey[p.key(r.stationBlock)] }
				list.append(rec)
				nextID += 1
			}
		}
		recipes = list
	}

	func buildOres() {
		var skipped: Int = 0
		defer { capNote(skipped, "ores", ModLimits.maxWorldOres) }
		for p in packs {
			for o in p.ores where !disabled.contains(p.key(o.id)) {
				guard let t = tileForKey[p.key(o.block)] else { continue }
				if ores.count >= ModLimits.maxWorldOres {
					skipped += 1
					continue
				}
				let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data((p.id + o.id).utf8)))
				var hostTiles: Set<UInt8> = []
				for k in o.hosts { if let h = ModGround.resolve(k, self) { hostTiles.insert(h.rawValue) } }
				let near: Tile? = o.near.isEmpty ? nil : ModGround.resolve(o.near, self)
				let od: Int = dimNumber(o.dim, o.dimKey.isEmpty ? "" : p.key(o.dimKey))
				if od < 0 { continue }
				ores.append(ModOreRT(tile: t, dim: od, minY: o.minY, maxY: o.maxY, veins: o.veins, size: o.size, host: o.host, salt: salt,
									 place: o.place, biomes: Set(o.biomes), rarity: o.rarity, shape: o.shape, nearTile: near, hostTiles: hostTiles))
			}
		}
	}

	/// A note when the world's mods together have more ores or structures than one world makes
	func capNote(_ skipped: Int, _ what: String, _ cap: Int) {
		if skipped <= 0 { return }
		var rep = ModReport()
		rep.add(1, "Mods", "World", joinText(String(skipped), " ", what, " were left out: a world makes at most ", String(cap), " (from all its mods together)."))
		reports.append(rep)
	}

	func buildStructures() {
		var skipped: Int = 0
		defer { capNote(skipped, "structures", ModLimits.maxWorldStructures) }
		for p in packs {
			for s in p.structures where !disabled.contains(p.key(s.id)) {
				if structures.count >= ModLimits.maxWorldStructures {
					skipped += 1
					continue
				}
				var cells: [Int] = []
				cells.reserveCapacity(s.cells.count)
				for v in s.cells {
					if v >= 1000 {
						let pi: Int = v - 1000
						let k: String = pi < s.palette.count ? s.palette[pi] : ""
						if let t = tileForKey[k] { cells.append(Int(t.rawValue)) } else { cells.append(-1) }
					} else {
						cells.append(v)
					}
				}
				let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data((p.id + s.id).utf8)))
				var sd: ModStructure = s
				sd.dim = dimNumber(s.dim, s.dimKey.isEmpty ? "" : p.key(s.dimKey))
				if sd.dim < 0 { continue }
				structures.append(ModStructRT(key: p.key(s.id), def: sd, cells: cells, salt: salt, loot: s.loot.isEmpty ? "" : p.key(s.loot)))
			}
		}
	}

	// MARK: installing

	/// Puts this runtime's blocks into the tile tables and art, and its recipes into the recipe book
	func install() {
		let base: Int = Int(Tile.modBase)
		for i in 0..<ModLimits.blockSlots {
			guard let t = Tile(rawValue: UInt8(base + i)) else { continue }
			slotArt[i] = slotArtBuf(i)
			Tile.patch(t, tileDef(i), tool: slotTool[i])
			if let b = slotDef[i], !slotAlt[i], !b.dropSelf, let d = b.drop {
				slotDrop[i] = Stack(item: resolve(d), count: b.dropCount)
			}
		}
		RecipeBook.all = RecipeBook.base + recipes
		OverrideRT.shared.install()
		SectionPainter.shared.refreshModTiles()
		Art.shared.refreshModArt()
	}

	/// The picture a slot draws: the block's art (an open door shows its edge, an unlit lamp is darker)
	func slotArtBuf(_ i: Int) -> PixelBuf {
		guard let b = slotDef[i] else { return missingTileBuf() }
		var art: PixelBuf = b.art.isBlank ? greyTileBuf() : b.art.buf()
		if b.art.outlined(false) { art.outline(0x101010) }
		if b.function == .door && slotAlt[i] {
			var o = PixelBuf(w: 8, h: 8)
			for y in 0..<8 {
				for x in 0..<2 { o.px[y * 8 + x] = art.px[y * 8 + x] }
			}
			art = o
		}
		if b.function == .lamp && !slotAlt[i] {
			for k in 0..<art.px.count where (art.px[k] >> 24) != 0 {
				art.px[k] = 0xFF000000 | shadeRGB(art.px[k] & 0xFFFFFF, 0.55)
			}
		}
		return art
	}
}

extension ModRuntime {
	/// The custom blocks and items the creative palette and the test tools offer
	func paletteItems() -> [Item] {
		var out: [Item] = []
		for i in 0..<ModLimits.blockSlots where slotDef[i] != nil && !slotAlt[i] {
			if let t = Tile(rawValue: UInt8(Int(Tile.modBase) + i)) { out.append(.block(t)) }
		}
		for k in itemOrder { out.append(.custom(k)) }
		return out
	}
}

/// Whether a saved world's mods are all installed (checked before it is loaded)
struct ModLoadCheck {
	var save: SaveData
	var packs: [ModPack] = []
	var missing: [ModDep] = []
	/// mods installed in a different version than the world was made with
	var changed: [String] = []

	static func check(_ s: SaveData) -> ModLoadCheck {
		var c = ModLoadCheck(save: s)
		guard let info = s.mods else { return c }
		for d in info.mods {
			if let p = ModStore.pack(d.id) {
				c.packs.append(p)
				if p.version != d.version { c.changed.append(p.name) }
			} else {
				c.missing.append(d)
			}
		}
		return c
	}
}

/// Mod testing: a flat creative world with the mod switched on, separate from real worlds and never
/// saved, with tools to spawn, give, place and clear things
enum ModTest {
	static let seed: UInt64 = 777_000_111

	static func makeWorld(_ p: ModPack, settings: Settings) -> Game {
		var list: [ModPack] = [p]
		for e in ModStore.enabledPacks() where e.id != p.id { list.append(e) }
		ModRuntime.activate(list, world: nil)
		var opts: WorldOptions = .standard
		opts.flat = true
		opts.trees = true
		opts.ponds = true
		opts.structures = true
		opts.caves = true
		let g = Game(mode: .creative, infinite: true, seed: seed, settings: settings, options: opts)
		g.testMod = p.id
		g.slot = -1
		g.worldName = "Mod test: " + p.name
		g.modInfo = ModRuntime.shared.worldInfo()
		g.timeOfDay = 0.3
		return g
	}
}

/// The magenta and black checks of a block whose mod is missing
func missingTileBuf() -> PixelBuf {
	var b = PixelBuf(w: 8, h: 8)
	for y in 0..<8 {
		for x in 0..<8 { b.set(x, y, ((x / 4) + (y / 4)) % 2 == 0 ? 0xFF00FF : 0x200020) }
	}
	return b
}

/// A plain grey block (a custom block nobody has painted yet)
func greyTileBuf() -> PixelBuf {
	var b = PixelBuf(w: 8, h: 8)
	for y in 0..<8 {
		for x in 0..<8 { b.set(x, y, (x == 0 || y == 0) ? 0x9A9A9A : ((x == 7 || y == 7) ? 0x5A5A5A : 0x7A7A7A)) }
	}
	return b
}

/// The average colour of a picture's visible pixels (for particles and maps)
func averageColor(_ b: PixelBuf) -> UInt32 {
	var r: Int = 0
	var g: Int = 0
	var bl: Int = 0
	var n: Int = 0
	for c in b.px where (c >> 24) != 0 {
		r += Int((c >> 16) & 0xFF)
		g += Int((c >> 8) & 0xFF)
		bl += Int(c & 0xFF)
		n += 1
	}
	if n == 0 { return 0x8A8A8A }
	return UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(bl / n)
}

// MARK: - Custom creature art

/// Red, green and blue (0...1) to hue (0...1), saturation and value
func rgbToHSV(_ c: UInt32) -> (Double, Double, Double) {
	let r: Double = Double((c >> 16) & 0xFF) / 255.0
	let g: Double = Double((c >> 8) & 0xFF) / 255.0
	let b: Double = Double(c & 0xFF) / 255.0
	let mx: Double = max(r, max(g, b))
	let mn: Double = min(r, min(g, b))
	let d: Double = mx - mn
	var h: Double = 0
	if d > 0.00001 {
		if mx == r { h = (g - b) / d } else if mx == g { h = 2.0 + (b - r) / d } else { h = 4.0 + (r - g) / d }
		h /= 6.0
		if h < 0 { h += 1.0 }
	}
	let s: Double = mx <= 0 ? 0 : d / mx
	return (h, s, mx)
}

func hsvToRGB(_ h0: Double, _ s: Double, _ v: Double) -> UInt32 {
	let h: Double = (h0 - floor(h0)) * 6.0
	let i: Int = Int(floor(h)) % 6
	let f: Double = h - floor(h)
	let p: Double = v * (1 - s)
	let q: Double = v * (1 - s * f)
	let t: Double = v * (1 - s * (1 - f))
	var r: Double = v
	var g: Double = t
	var b: Double = p
	switch i {
	case 1: r = q; g = v; b = p
	case 2: r = p; g = v; b = t
	case 3: r = p; g = q; b = v
	case 4: r = t; g = p; b = v
	case 5: r = v; g = p; b = q
	default: break
	}
	let ri: UInt32 = UInt32(clampD(r * 255.0, 0, 255).rounded())
	let gi: UInt32 = UInt32(clampD(g * 255.0, 0, 255).rounded())
	let bi: UInt32 = UInt32(clampD(b * 255.0, 0, 255).rounded())
	return (ri << 16) | (gi << 8) | bi
}

/// Turns the hue, scales saturation and brightness, then mixes in a tint, on every visible pixel.
/// Near-black pixels (outlines) stay dark so the creature keeps its shape.
func recolorBuf(_ b: PixelBuf, hue: Double, sat: Double, bright: Double, tint: UInt32, amt: Double) -> PixelBuf {
	if abs(hue) < 0.5 && abs(sat - 1) < 0.01 && abs(bright - 1) < 0.01 && amt < 0.01 { return b }
	var o: PixelBuf = b
	let turn: Double = hue / 360.0
	for i in 0..<o.px.count {
		let c: UInt32 = o.px[i]
		if (c >> 24) == 0 { continue }
		let hsv: (Double, Double, Double) = rgbToHSV(c & 0xFFFFFF)
		if hsv.2 < 0.14 { continue }
		let s2: Double = clampD(hsv.1 * sat, 0, 1)
		let v2: Double = clampD(hsv.2 * bright, 0, 1)
		var rgb: UInt32 = hsvToRGB(hsv.0 + turn, s2, v2)
		if amt > 0.01 { rgb = mixRGB(rgb, tint & 0xFFFFFF, amt) }
		o.px[i] = 0xFF000000 | rgb
	}
	return o
}

/// A custom creature's frames: its own pictures (outlined, all the size of the first), or its base
/// creature's frames recoloured
func modMobFrames(_ m: ModMob) -> ([PixelBuf], CreatureAnim) {
	if m.customArt && !m.frames.isEmpty && !m.frames[0].isBlank {
		let w0: Int = m.frames[0].w
		let h0: Int = m.frames[0].h
		var out: [PixelBuf] = []
		for f in m.frames.prefix(ModLimits.maxFrames) {
			let same: ModPixels = (f.w == w0 && f.h == h0) ? f : f.resized(w0, h0)
			var b: PixelBuf = padBuf(same.buf())
			if f.outlined(true) { b.outline(0x101010) }
			out.append(b)
		}
		var a = CreatureAnim()
		if out.count >= 4 { a.attack = 3 }
		if m.behavior.fly || m.behavior.swim || m.category == .flying || m.category == .water {
			if out.count >= 3 { a.cycle = [0, 1, 2, 1] } else if out.count == 2 { a.cycle = [0, 1] }
		}
		return (out, a)
	}
	let base: MobKind = MobKind(rawValue: m.base) ?? .zombie
	let art: ([PixelBuf], CreatureAnim) = creatureArt(base == .custom ? .zombie : base, 0)
	var out: [PixelBuf] = []
	for f in art.0 { out.append(recolorBuf(f, hue: m.hue, sat: m.saturation, bright: m.brightness, tint: m.tint, amt: m.tintAmt)) }
	return (out, art.1)
}

/// The sprites of a custom creature, sized to its hit box
func modMobSpriteSet(_ m: ModMob) -> SpriteSet {
	let fr: ([PixelBuf], CreatureAnim) = modMobFrames(m)
	let base: MobKind = MobKind(rawValue: m.base) ?? .zombie
	let h: Double = clampD(mobDef(base == .custom ? .zombie : base).h * m.scale, 0.3, 8)
	if m.customArt && !m.frames.isEmpty && !m.frames[0].isBlank, let f0 = fr.0.first {
		let bb: (Int, Int, Int, Int) = opaqueBounds(f0)
		let oh: Double = Double(bb.3 - bb.1 + 1)
		return makeSpriteSet(fr.0, hitH: h, fixedScale: h * 1.05 / max(1.0, oh), anim: fr.1)
	}
	return makeSpriteSet(fr.0, hitH: h, fixedScale: creatureScale * m.scale, anim: fr.1)
}

// MARK: - Custom content in play

/// Effects on the player from potions, food and the armour worn: each kind has a strength and the
/// seconds it has left. The strongest of the same kind wins.
struct PlayerEffects {
	var amount: [Double] = [Double](repeating: 0, count: ModEffectKind.allCases.count)
	var time: [Double] = [Double](repeating: 0, count: ModEffectKind.allCases.count)
	var regenAcc: Double = 0

	func value(_ k: ModEffectKind) -> Double {
		let i: Int = k.rawValue
		return time[i] > 0 ? amount[i] : 0
	}

	mutating func add(_ k: ModEffectKind, _ a: Double, _ secs: Double) {
		let i: Int = k.rawValue
		if time[i] <= 0 || a >= amount[i] { amount[i] = a }
		time[i] = max(time[i], secs)
	}

	mutating func tick(_ dt: Double) {
		for i in 0..<time.count where time[i] > 0 { time[i] = max(0, time[i] - dt) }
	}

	mutating func clear() {
		for i in 0..<time.count { time[i] = 0 }
	}

	/// What is active, for the HUD: name and seconds left (worn effects show no time)
	var list: [(String, Double)] {
		var out: [(String, Double)] = []
		for k in ModEffectKind.allCases where k.timed && time[k.rawValue] > 0 {
			out.append((k.name, time[k.rawValue]))
		}
		return out
	}
}

/// Reloading data for a gun of a mod: magazine, time and ammunition (nil: it needs none)
struct ModGunSpec {
	var magazine: Int
	var time: Double
	var ammo: Item?
}

extension Game {
	/// Once a frame in a world with mods: worn mod armour keeps its effect up and jump pads throw the
	/// player up (effects themselves run down in updateEffects, in every world)
	func updateModPlay(_ dt: Double) {
		if healerCD > 0 { healerCD -= dt }
		let rt: ModRuntime = ModRuntime.shared
		if !rt.active { return }
		for i in 0..<min(3, inv.armor.count) {
			if let s = inv.armor[i], case .custom(let k) = s.item, let r = rt.item(k), r.def.kind == .armor, let e = r.def.wornEffect {
				effects.add(e.kind, e.amount, 0.3)
			}
		}
		// a jump pad under the feet
		if pb.onGround && !dead && inVehicle == nil {
			let under: Tile = world.tile(Int(floor(pb.x)), Int(floor(pb.y + 0.05)))
			if under.isMod, let b = rt.blockDef(under), b.function == .bounce {
				pb.vy = -max(4.0, b.power)
				pb.onGround = false
				fallPeak = 0
				sfx(.land, 0.7)
				spawnParticles(pb.x, pb.y, averageColor(b.art.buf()), 6, 3.0, 0.4, 10)
			}
		}
	}

	// MARK: using custom items

	func useModItem(_ k: String, _ dt: Double, _ pressed: Bool) {
		guard let r = ModRuntime.shared.item(k) else {
			if pressed { say("This item's mod is not installed.", 1.5) }
			return
		}
		let d: ModItem = r.def
		if pressed && !logicRT.isEmpty { fireLogic(.itemUsed, key: k) }
		switch d.kind {
		case .tool: useModTool(r, dt, pressed)
		case .melee: useMeleeWeapon(.custom(k), pressed)
		case .gun: useModGun(r, pressed)
		case .thrown, .magic: useModShooter(r, pressed)
		case .bow: break
		case .food, .consumable: useModConsumable(r, pressed)
		case .armor:
			if pressed {
				quickEquip(sel)
				say("Equipped.", 1.0)
			}
		case .special:
			if pressed && !d.effects.isEmpty && useCD <= 0 {
				applyEffects(d.effects)
				useCD = max(2.0, d.cooldown)
				sfx(.zap, 0.5)
				spawnParticles(pb.x, pb.y - 1.0, 0xC8E8FF, 8, 3.0, 0.5, -2)
			}
		case .material, .ammo: break
		}
	}

	/// A custom tool: fights a creature under the aim, tills with a hoe, otherwise mines with its own
	/// tier and speed
	func useModTool(_ r: ModItemRT, _ dt: Double, _ pressed: Bool) {
		let it: Item = .custom(r.key)
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if let m = mobUnderAim(infusedMelee(it)) {
			if pressed || (useCD <= 0 && !meleeCandidates(infusedMelee(it)).isEmpty) { startMelee(it, target: m) }
			return
		}
		let tt: ToolType = ToolType(rawValue: r.def.toolType) ?? .pickaxe
		if tt == .hoe && useCD <= 0 {
			let t: Tile = world.tile(tx, ty)
			if (t == .grass || t == .dirt || t == .dryGrass || t == .mossGrass) && inReach(Double(tx) + 0.5, Double(ty) + 0.5) && !world.tile(tx, ty - 1).solid {
				world.set(tx, ty, .farmland)
				if world.tile(tx, ty - 1).isPlant { world.set(tx, ty - 1, .air) }
				useCD = 0.25
				swingT = 0.2
				swingDir = facing
				return
			}
		}
		let tier: Tier = Tier(rawValue: clampI(r.def.toolTier, 1, 9)) ?? .wood
		mineStep(tx, ty, tt, tier, dt, speed: r.def.toolSpeed)
	}

	/// What reloading a custom gun takes
	func modGunSpec(_ r: ModItemRT) -> ModGunSpec {
		return ModGunSpec(magazine: max(1, r.def.magazine), time: r.def.reload, ammo: r.ammo)
	}

	func useModGun(_ r: ModItemRT, _ pressed: Bool) {
		guard var st = inv.slots[sel] else { return }
		if reloadT > 0 { return }
		if st.extra <= 0 {
			if pressed || useCD <= 0 { startReload() }
			return
		}
		if useCD > 0 { return }
		if r.def.needsPress && !pressed { return }
		st.extra -= 1
		inv.slots[sel] = st
		fireModShots(r, charge: 1.0, useAmmo: false)
		if st.extra <= 0 {
			let spec: ModGunSpec = modGunSpec(r)
			if spec.ammo == nil || isCreative || inv.total(spec.ammo!) > 0 { startReload() }
		}
		bumpHUD()
	}

	func startModReload(_ r: ModItemRT, _ st: Stack) {
		let spec: ModGunSpec = modGunSpec(r)
		if reloadT > 0 || st.extra >= spec.magazine { return }
		if let a = spec.ammo, !isCreative && inv.total(a) <= 0 {
			say("Out of " + a.name.lowercased() + "!", 1.5)
			return
		}
		reloadT = spec.time
		reloadSlot = sel
		if spec.magazine > 1 { say("Reloading...", 1.0) }
	}

	/// The end of a custom gun's reload: the magazine fills from the bag (or freely without ammunition)
	func finishModReload(_ r: ModItemRT) {
		guard var st = inv.slots[sel] else { return }
		let spec: ModGunSpec = modGunSpec(r)
		let need: Int = spec.magazine - st.extra
		var take: Int = need
		if let a = spec.ammo, !isCreative {
			take = min(need, inv.total(a))
			_ = inv.remove(a, take)
		}
		st.extra += max(0, take)
		inv.slots[sel] = st
		sfx(.tap, 0.5)
		bumpHUD()
	}

	/// Thrown weapons and projectile weapons: one use, one volley
	func useModShooter(_ r: ModItemRT, _ pressed: Bool) {
		if useCD > 0 { return }
		if r.def.needsPress && !pressed { return }
		if let a = r.ammo, !isCreative && inv.total(a) <= 0 {
			if pressed { say("No " + a.name.lowercased() + "!", 1.2) }
			return
		}
		fireModShots(r, charge: 1.0, useAmmo: true)
		if r.def.kind == .thrown && r.ammo == nil && !isCreative { inv.removeAt(sel, 1) }
		bumpHUD()
	}

	/// A custom bow: hold to draw, release to shoot (a full draw keeps firing while held)
	func handleModBow(_ r: ModItemRT, _ dt: Double, _ pressed: Bool, _ released: Bool) {
		var hasAmmo: Bool = true
		if let a = r.ammo, !isCreative { hasAmmo = inv.total(a) > 0 }
		if useHeld {
			if !hasAmmo {
				if pressed { say("No " + (r.ammo?.name.lowercased() ?? "ammunition") + "!", 1.2) }
				bowCharge = 0
				return
			}
			if useCD > 0 && bowCharge == 0 { return }
			bowCharge = min(1.0, max(bowCharge, 0.01) + dt / 0.55)
			facing = aimFacing()
			if bowCharge >= 1.0 && useCD <= 0 {
				fireModShots(r, charge: 1.0, useAmmo: true)
				bowCharge = 0.3
			}
		} else if released && bowCharge > 0 && hasAmmo {
			fireModShots(r, charge: max(0.45, bowCharge), useAmmo: true)
			bowCharge = 0
		} else {
			bowCharge = 0
		}
	}

	/// Fires a custom weapon's volley toward the aim, through the game's projectiles (so its shots
	/// hurt, pierce and knock back like every other shot)
	func fireModShots(_ r: ModItemRT, charge: Double, useAmmo: Bool) {
		let d: ModItem = r.def
		if useAmmo, let a = r.ammo, !isCreative { _ = inv.remove(a, 1) }
		facing = aimFacing()
		let bow: Bool = d.kind == .bow
		let speed: Double = d.speed * (bow ? 0.55 + 0.45 * charge : 1.0)
		let dmg: Double = d.damage * (bow ? 0.4 + 0.6 * charge : 1.0)
		var grav: Double = d.gravity
		var life: Double = 3.0
		var kind: ProjKind = ProjKind(rawValue: d.shot) ?? .arrow
		var w: Double = 0.24
		if r.shot >= 0 && r.shot < ModRuntime.shared.shots.count {
			let s: ModProjectile = ModRuntime.shared.shots[r.shot]
			grav = s.gravity
			life = s.life
			kind = .spit
			w = s.size
		}
		let ox: Double = pb.x + Double(facing) * 0.6
		let oy: Double = pb.y - 1.2
		let base: Double = lobAngle(aimX - ox, aimY - oy, speed, grav)
		let n: Int = max(1, d.spread)
		let live: Int = projectiles.filter { $0.mod >= 0 }.count
		if live >= ModLimits.maxShotsLive { return }
		for i in 0..<n {
			var a: Double = base
			if n > 1 { a += (Double(i) / Double(n - 1) - 0.5) * min(1.2, 0.18 * Double(n)) }
			var p = Projectile(kind: kind, x: ox, y: oy, vx: cos(a) * speed, vy: sin(a) * speed, dmg: dmg, fromPlayer: true, gravity: grav)
			p.life = life
			p.source = .player
			p.uid = newID()
			p.pierce = d.pierce
			p.knock = d.knock
			p.w = w
			p.mod = r.shot
			if r.shot < 0 && kind == .fireball { p.life = 2.5 }
			infuseShot(&p, heldItem)
			projectiles.append(p)
		}
		useCD = d.cooldown * quickMul()
		swingT = 0.14
		swingDir = facing
		switch d.kind {
		case .bow: sfx(.bow, 0.7); bowRecoil = 0.12
		case .gun: sfx(kind == .quarrel ? .crossbow : .gun, 0.75); muzzleT = 0.08; addShake(0.08)
		case .thrown: sfx(.sling, 0.6)
		default: sfx(.zap, 0.6)
		}
	}

	/// Food, potions and other consumables: hunger, effects, then one is used up
	func useModConsumable(_ r: ModItemRT, _ pressed: Bool) {
		if !pressed || eatT > 0 { return }
		let d: ModItem = r.def
		if d.kind == .food && d.effects.isEmpty && hunger >= 19.5 && hp >= maxHP && !isCreative {
			say("You're not hungry.", 1.2)
			return
		}
		if d.hunger > 0 {
			hunger = min(20, hunger + d.hunger)
			floatText("+" + String(Int(d.hunger)), pb.x, pb.y - pb.h - 0.4, 0xE0A040)
		}
		applyEffects(d.effects)
		if !isCreative { inv.removeAt(sel, 1) }
		eatT = d.useTime
		useCD = d.useTime
		sfx(.eat, 0.6)
		spawnParticles(pb.x + Double(facing) * 0.4, pb.y - 1.4, 0xC8A0E0, 6, 2.0, 0.4, 6)
		bumpHUD()
	}

	/// Applies effects: healing, food and cures at once, the rest for their time
	func applyEffects(_ list: [ModEffect]) {
		for e in list {
			switch e.kind {
			case .heal: heal(e.amount)
			case .feed: hunger = min(20, hunger + e.amount)
			case .cure:
				playerBurn = 0
				bodyCold = 0
			default: effects.add(e.kind, e.amount, e.seconds)
			}
		}
		bumpHUD()
	}

	// MARK: custom blocks

	/// Tapping a custom block: storage opens, doors and lamps switch, shrines heal, signs speak.
	/// Returns false for blocks that do nothing when tapped.
	func interactModBlock(_ tx: Int, _ ty: Int, _ t: Tile) -> Bool {
		guard let b = ModRuntime.shared.blockDef(t) else {
			say(t.name + ": its mod is not installed.", 2.0)
			return true
		}
		switch b.function {
		case .storage:
			sfx(.chestOpen, 0.7)
			if world.chests[world.chestKey(tx, ty)] == nil { world.setChestItems(tx, ty, []) }
			openChest = IntPair(x: tx, y: ty)
			showInventory = true
			bumpHUD()
		case .station:
			if b.station >= 1, let s = Station(rawValue: b.station) { craftStation = s } else { craftStation = .hand }
			showInventory = true
			bumpHUD()
		case .lamp, .door:
			guard let other = ModRuntime.shared.partner(t) else { return false }
			if b.function == .door && ModRuntime.shared.isAlt(t) {
				// closing a door the player stands in would trap them
				if pb.right > Double(tx) && pb.left < Double(tx + 1) && pb.y > Double(ty) && pb.top < Double(ty + 1) { return true }
			}
			world.set(tx, ty, other)
			sfx(b.function == .door ? .door : .tap, 0.6)
		case .healer:
			if healerCD > 0 {
				say("The shrine is resting.", 1.2)
			} else {
				heal(b.power)
				healerCD = 5
				sfx(.discovery, 0.5)
				spawnParticles(Double(tx) + 0.5, Double(ty) + 0.2, 0x80FF90, 12, 3.0, 0.8, -3)
			}
		case .sign:
			say(b.text.isEmpty ? b.name : b.text, 4.0)
		default:
			return false
		}
		return true
	}

	/// True if a recipe's station (a game station or a mod block) is close enough
	func recipeStationOK(_ r: Recipe) -> Bool {
		if let ms = r.modStation {
			if isCreative { return true }
			let px: Int = Int(floor(pb.x))
			let py: Int = Int(floor(pb.y - 1))
			for dy in -4...3 {
				for dx in -5...5 where world.tile(px + dx, py + dy) == ms { return true }
			}
			return false
		}
		return stationAvailable(r.station)
	}

	func recipeStationName(_ r: Recipe) -> String {
		if let ms = r.modStation { return ms.name }
		return r.station.name
	}

	// MARK: custom shots

	/// A custom shot came down (on a creature, the player or a block): its blast and its fire
	func modShotLanded(_ p: Projectile, _ x: Double, _ y: Double, mob: Mob?, player: Bool) {
		guard p.mod >= 0 && p.mod < ModRuntime.shared.shots.count else { return }
		let s: ModProjectile = ModRuntime.shared.shots[p.mod]
		if s.burn > 0 {
			if let m = mob { m.burn = max(m.burn, s.burn) }
			if player && effects.value(.fireproof) <= 0 { playerBurn = max(playerBurn, s.burn * 0.5) }
		}
		if s.explode > 0 {
			// (only the player's own shots may break blocks; a creature's never wrecks the world)
			explode(x, y, radius: s.explode, power: p.dmg, source: p.source, breakBlocks: s.breakBlocks && p.source.kind == .player)
		} else {
			spawnParticles(x, y, s.color & 0xFFFFFF, 5, 3.0, 0.3, 6)
		}
	}
}

extension Game {
	// MARK: Mod Test tools

	/// Spawns a custom creature a few blocks in front of the player. It stays put (persistent) until
	/// cleared. Returns what to tell the player.
	func testSpawn(_ slot: Int) -> String {
		guard let r = ModRuntime.shared.mob(slot) else { return "That creature is not in this world." }
		let x: Double = pb.x + Double(facing) * max(3.0, r.mdef.w + 2.0)
		var y: Double = pb.y
		if r.mdef.flying {
			y = pb.y - 3.0
		} else if !r.aquatic {
			y = Double(world.groundBelow(Int(floor(x)), Int(floor(pb.y)) - 8))
		}
		guard let m = addCustomMob(slot, x, y) else {
			return joinText("No more than ", String(ModLimits.maxActiveMobs), " custom creatures at once: clear some first.")
		}
		m.homeX = x
		m.homeY = y
		m.persistent = true
		m.dir = pb.x >= x ? 1 : -1
		var note: String = joinText("Spawned ", r.def.name, ".")
		if r.aquatic && !m.b.inWater { note = joinText(note, " It lives in water: put it in a pool.") }
		return note
	}

	/// One of the game's own creatures to try the mod's creatures and weapons on
	func testSpawnGame(_ k: MobKind) -> String {
		let x: Double = pb.x + Double(facing) * 4.0
		let y: Double = Double(world.groundBelow(Int(floor(x)), Int(floor(pb.y)) - 8))
		let m: Mob = addMob(k, x, y)
		m.homeX = x
		m.homeY = y
		m.persistent = true
		return joinText("Spawned a ", mobDef(k).name.lowercased(), ".")
	}

	/// Removes every creature (pets stay), every shot and every warning
	func clearCreatures() {
		mobs.removeAll { !$0.tame }
		projectiles.removeAll()
		dangerZones.removeAll()
		activeBoss = nil
		bumpHUD()
	}

	/// Gives what a recipe needs and, if it needs a station, puts that station beside the player, so it
	/// can be tried in the crafting panel straight away
	func testIngredients(_ r: Recipe) -> String {
		for c in r.cost { giveItem(c.item, c.n) }
		var station: Tile? = r.modStation
		if station == nil {
			switch r.station {
			case .hand: station = nil
			case .bench: station = .workbench
			case .furnace, .campfire: station = .furnace
			case .anvil: station = .anvil
			case .tinker: station = .tinkerBench
			case .forge: station = .riftForge
			case .still: station = .alchemyStill
			case .infuser: station = .infuser
			case .assembly: station = .exoStation
			}
		}
		var placed: String = ""
		if let st = station {
			let px: Int = Int(floor(pb.x))
			let py: Int = Int(floor(pb.y)) - 1
			var done: Bool = stationNear(st)
			for dx in [-2, 2, -3, 3] where !done {
				let x: Int = px + dx
				if world.tile(x, py) == .air && world.solid(x, py + 1) {
					world.set(x, py, st)
					done = true
					placed = joinText(" and a ", st.name, " beside you")
				}
			}
		}
		bumpHUD()
		return joinText("Here is what ", r.out.name, " needs", placed, ".")
	}

	/// A station tile within reach of the player already
	func stationNear(_ t: Tile) -> Bool {
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1))
		for dy in -4...3 {
			for dx in -5...5 where world.tile(px + dx, py + dy) == t { return true }
		}
		return false
	}

	/// Survival rules in the test world: hunger, damage and using things up (off: creative)
	var testSurvival: Bool {
		get { return mode == .survival }
		set {
			mode = newValue ? .survival : .creative
			if newValue && hp <= 0 { hp = maxHP }
			bumpHUD()
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
		return suitGuard(a, info.type)
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

	/// A saved suit, checked: a part in a place it doesn't fit goes back into the bag
	func restoreSuit(_ s: ExoSuit) {
		var clean: ExoSuit = ExoSuit()
		var loose: [Stack] = []
		for (k, st) in s.parts {
			if let slot = ExoSlot(rawValue: k), slot.fits(st.item) { clean[slot] = st } else { loose.append(st) }
		}
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
		// suit parts in every metal (the Umbral metals and boss relics for the best)
		for mt in ExoMat.allCases {
			let b: Item = mt.bar
			let n: Int = mt == .diamond ? 1 : 2
			var helm: [(Item, Int)] = [(b, 2 * n), (.block(.glass), 1)]
			var chest: [(Item, Int)] = [(b, 4 * n), (m(.copperBar), 2)]
			if mt == .diamond { helm.append((m(.ironBar), 2)); chest.append((m(.ironBar), 4)) }
			if mt == .ember { chest.append((.block(.obsidian), 4)) }
			if mt == .voidium { chest.append((m(.umbralHeart), 1)) }
			add(.exoPart(.helmet, mt), 1, helm, .assembly, .exosuit)
			add(.exoPart(.chestFrame, mt), 1, chest, .assembly, .exosuit)
			add(.exoPart(.arm, mt), 1, [(b, n + 1), (m(.copperBar), 1)] + (mt == .diamond ? [(m(.ironBar), 2)] : []), .assembly, .exosuit)
			add(.exoPart(.legs, mt), 1, [(b, 2 * n + 1), (m(.copperBar), 1)] + (mt == .diamond ? [(m(.ironBar), 3)] : []), .assembly, .exosuit)
			add(.exoPart(.boots, mt), 1, [(b, n + 1), (m(.leather), 1)] + (mt == .diamond ? [(m(.ironBar), 2)] : []), .assembly, .exosuit)
			add(.exoPlate(mt), 1, [(b, n)] + (mt == .diamond ? [(m(.ironBar), 1)] : []), .assembly, .exosuit)
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
	}
}

/// The alchemy, infusion and suit items, in palette order
func featureItems() -> [Item] {
	var out: [Item] = []
	for p in Potion.allCases { out.append(.potion(p)) }
	for i in Infusion.allCases { out.append(.compound(i)) }
	for mt in ExoMat.allCases {
		for p in ExoPart.allCases { out.append(.exoPart(p, mt)) }
		out.append(.exoPlate(mt))
	}
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
		let art: ([PixelBuf], CreatureAnim) = creatureArt(m.kind, variant)
		var frames: [PixelBuf] = []
		let hue: Double = 12.0 * Double(step)
		for f in art.0 { frames.append(recolorBuf(f, hue: hue, sat: 1.06, bright: 1.0, tint: 0x9AF04A, amt: 0.035 * Double(step))) }
		let s: SpriteSet = makeSpriteSet(frames, hitH: mobDef(m.kind).h, fixedScale: creatureScale, anim: art.1)
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
			for s in suit.parts.values { a.add(s) }
		}
		armorInfCache = a
		armorInfKey = k
		return a
	}

	/// Everything that guards the player: armour, its Reinforced infusions and a worn suit
	var totalDefense: Double {
		var d: Double = inv.defense + armorInf.defense
		if suitWorn { d += suitStats.defense }
		return d
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
	var name: String {
		switch self {
		case .servo: return "Servo Muscles"
		case .drill: return "Drill Arm"
		case .sprint: return "Sprint Actuators"
		case .leap: return "Leap Pistons"
		case .hover: return "Hover Jets"
		case .lamp: return "Helmet Lamp"
		case .seal: return "Environment Seal"
		case .cargo: return "Cargo Pack"
		case .gauntlet: return "Shock Gauntlet"
		case .barrier: return "Barrier Projector"
		}
	}
	var blurb: String {
		switch self {
		case .servo: return "Carries 25 more weight and hits 25% harder (a little energy each swing)"
		case .drill: return "Mine with any hand, faster, at the right arm's metal tier (energy while mining)"
		case .sprint: return "Run 20% faster (energy while running)"
		case .leap: return "Jump 35% higher (energy each jump)"
		case .hover: return "Hold jump in the air to hover and glide (a lot of energy)"
		case .lamp: return "Lights the way in the dark (a trickle of energy)"
		case .seal: return "Fire, lava, cold, water and lightning hurt far less (energy while it works)"
		case .cargo: return "A chest on your back: 27 stacks that go where you go (PACK button)"
		case .gauntlet: return "Melee blows add a 4-damage shock (energy each hit)"
		case .barrier: return "Turns 40% of each hit into energy drain instead of harm"
		}
	}
	/// the parts it needs to be mounted (besides the chest frame)
	var needs: [ExoSlot] {
		switch self {
		case .drill: return [.armR]
		case .gauntlet: return [.armL]
		case .servo: return [.armL, .armR]
		case .sprint: return [.legs]
		case .leap: return [.legs, .boots]
		case .hover: return [.legs, .boots]
		case .lamp, .seal: return [.helmet]
		case .cargo, .barrier: return []
		}
	}
	var weight: Double {
		switch self {
		case .drill: return 4
		case .hover, .cargo: return 3
		default: return 2
		}
	}
	var rarity: Rarity {
		switch self {
		case .lamp, .cargo: return .basic
		case .servo, .drill, .sprint, .leap: return .uncommon
		case .seal, .gauntlet: return .rare
		case .hover, .barrier: return .veryRare
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

/// A suit: what is fitted in each place (each part keeps its own infusions), whether it is being worn
/// and the energy in its core. The parts live in the suit, not in the bag.
struct ExoSuit: Codable, Equatable {
	var parts: [Int: Stack] = [:]
	var worn: Bool = false
	var energy: Double = 0
	/// the module switches the player has turned off (by module number)
	var off: [Int]? = nil

	init() {}

	subscript(_ s: ExoSlot) -> Stack? {
		get { return parts[s.rawValue] }
		set { parts[s.rawValue] = newValue }
	}

	var isEmpty: Bool { return parts.isEmpty }

	func material(_ s: ExoSlot) -> ExoMat? {
		if let st = parts[s.rawValue] {
			if case .exoPart(_, let m) = st.item { return m }
			if case .exoPlate(let m) = st.item { return m }
		}
		return nil
	}

	var core: ExoCore? {
		if let st = parts[ExoSlot.core.rawValue], case .exoCore(let c) = st.item { return c }
		return nil
	}

	/// the module sockets the chest frame has
	var sockets: Int { return material(.chest)?.sockets ?? 0 }

	/// every module fitted in a socket that is open and whose parts are there, in socket order
	var modules: [ExoModule] {
		var out: [ExoModule] = []
		let n: Int = sockets
		for (k, s) in [ExoSlot.mod1, .mod2, .mod3, .mod4].enumerated() where k < n {
			if let st = parts[s.rawValue], case .exoModule(let m) = st.item {
				if m.needs.allSatisfy({ parts[$0.rawValue] != nil }) && !out.contains(m) { out.append(m) }
			}
		}
		return out
	}
}

/// What a suit adds up to: worked out once each time it changes, never every frame
struct ExoStats {
	var defense: Double = 0
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
	var modules: [ExoModule] = []
	/// can be worn: a chest frame and a core
	var complete: Bool = false
	/// what is wrong or missing, in plain words
	var notes: [String] = []
	var thrift: Set<Int> = []

	func has(_ m: ExoModule) -> Bool { return modules.contains(m) }

	static func of(_ s: ExoSuit) -> ExoStats {
		var r: ExoStats = ExoStats()
		var conductSum: Double = 0
		var conductN: Double = 0
		for slot in ExoSlot.allCases {
			guard let st = s[slot] else { continue }
			switch st.item {
			case .exoPart(let p, let m):
				r.defense += p.baseDefense * m.protect
				r.weight += p.baseWeight * m.weight
				conductSum += m.conduct
				conductN += 1
				if m == .ember { r.fireCut = min(0.6, r.fireCut + 0.12) }
				if m == .voidium {
					r.coldCut = min(0.6, r.coldCut + 0.1)
					r.stormCut = min(0.6, r.stormCut + 0.1)
				}
			case .exoPlate(let m):
				if let b = slot.plateBase, s[b] == nil {
					r.notes.append(joinText(slot.name, " has nothing to hold it (fit the ", b.name.lowercased(), ")."))
					continue
				}
				r.defense += slot.plateDefense * m.protect
				r.weight += 2.0 * m.weight
				if m == .ember { r.fireCut = min(0.6, r.fireCut + 0.06) }
			case .exoCore(let c):
				r.capacity = c.capacity
				r.output = c.output
				r.recharge = c.recharge
				r.weight += 3
				if st.has(.thrift) { r.drainMul *= 0.75 }
			case .exoModule(let m):
				r.weight += m.weight
				if st.has(.thrift) { r.thrift.insert(m.rawValue) }
			default: break
			}
		}
		if conductN > 0 { r.drainMul /= max(0.6, conductSum / conductN) }
		r.modules = s.modules
		// modules fitted but not working, and why
		let open: Int = s.sockets
		for (k, slot) in [ExoSlot.mod1, .mod2, .mod3, .mod4].enumerated() {
			guard let st = s[slot], case .exoModule(let m) = st.item else { continue }
			if k >= open {
				r.notes.append(joinText(m.name, ": the chest frame has only ", String(open), " sockets."))
			} else if let miss = m.needs.first(where: { s[$0] == nil }) {
				r.notes.append(joinText(m.name, " needs the ", miss.name.lowercased(), "."))
			}
		}
		if r.has(.servo) { r.strength += 25 }
		let over: Double = max(0, r.weight - r.strength)
		r.speedMul = 1.0 - min(0.35, over * 0.006)
		r.jumpMul = 1.0 - min(0.3, over * 0.004)
		r.knockMul = max(0.35, 1.0 - r.weight * 0.012)
		if let m = s.material(.armR) { r.drillTier = m.drillTier }
		r.complete = s[.chest] != nil && s[.core] != nil
		if s[.chest] == nil { r.notes.insert("Fit a chest frame: every suit is built on one.", at: 0) }
		if s[.core] == nil { r.notes.insert("Fit a power core: without one nothing can run.", at: 0) }
		for st in s.parts.values { r.drainMul *= customEnergyMul(st) }
		return r
	}
}

extension Game {
	// MARK: suit state

	/// a suit is on and has its frame and core
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

	/// Spends energy over time for a module that runs continuously, within what the core can give
	/// each second; false when the core can't keep it going
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

	/// Once a frame while the suit is worn: the core refills a little, and the modules that run by
	/// themselves (lamp, seal, jets, sprint) take their share of its output
	func updateSuit(_ dt: Double) {
		// the load counts everything run since the last frame's end (the drill runs earlier in the
		// frame, while mining), so all modules share the core's output together
		defer {
			suitLastLoad = suitLoad
			suitLoad = 0
		}
		suitHover = false
		if !suit.worn { return }
		let st: ExoStats = suitStats
		if !st.complete {
			suit.worn = false
			suitChanged()
			say("The suit can't run without its chest frame and core.", 2.0)
			return
		}
		suit.energy = min(st.capacity, suit.energy + st.recharge * dt)
		if dead || inVehicle != nil || mounted != nil { return }
		// the seal works only while something it guards against is around
		if suitStats.has(.seal) && sealNeeded() { _ = suitRun(.seal, 2.0, dt) }
		// jets: hold jump in the air to hover
		if suitStats.has(.hover) && jumpHeld && !pb.onGround && !pb.inWater && pb.vy > -2.0 && !flying {
			if suitRun(.hover, 6.0, dt) {
				suitHover = true
				pb.vy = min(pb.vy, 0.6)
				fallPeak = 0
				if frameNo % 3 == 0 { spawnParticles(pb.x, pb.y + 0.05, 0xFF9A3A, 1, 1.5, 0.25, 6) }
			}
		}
		if suitStats.has(.sprint) && abs(pb.vx) > 4.0 && pb.onGround { suitSprinting = suitRun(.sprint, 1.2, dt) } else { suitSprinting = false }
		// the lamp lights itself in the dark: at night, under ground, in the Umbral realm
		if suitStats.has(.lamp) && suitNeedsLight() { suitLit = suitRun(.lamp, 0.25, dt) } else { suitLit = false }
		if suitStats.has(.servo) { _ = suitRun(.servo, 0.1, dt) }
		if suit.energy <= 0.01 && !suitEmptyWarned {
			suitEmptyWarned = true
			say("Suit energy is spent: its modules are dead weight until it charges.", 2.5)
		} else if suit.energy > 5 {
			suitEmptyWarned = false
		}
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

	/// The suit's speed: its weight against its strength, and the sprint actuators
	var suitSpeedMul: Double {
		if !suit.worn { return 1.0 }
		var m: Double = suitStats.speedMul
		if suitSprinting { m *= 1.2 }
		return m
	}

	/// The suit's jump: weight, and the leap pistons (each boosted jump costs energy)
	func suitJumpMul() -> Double {
		if !suit.worn { return 1.0 }
		var m: Double = suitStats.jumpMul
		if suitHas(.leap) && suitSpend(.leap, 3.0) { m *= 1.35 }
		return m
	}

	/// A melee blow through the suit: servos hit harder (energy each swing)
	func suitMelee(_ p0: MeleeProfile) -> MeleeProfile {
		var p: MeleeProfile = p0
		if suitHas(.servo) { p.damage *= 1.25 }
		return p
	}

	/// After a melee blow lands with the suit on: the gauntlet's shock
	func suitMeleeHit(_ m: Mob) {
		if m.hp <= 0 || !suitHas(.gauntlet) { return }
		if !suitSpend(.gauntlet, 1.5) { return }
		var info = DamageInfo(amount: 4, type: .shock, source: .player)
		info.originX = pb.x
		info.key = newID()
		applyMobDamage(m, info)
		spawnParticles(m.b.x, m.b.cy, 0xFFF07A, 5, 3.0, 0.2, 0)
	}

	/// The share of a hit the suit takes: the seal against fire, water and lightning, the metals'
	/// own resistances, and the barrier turning some of what is left into energy drain
	func suitGuard(_ amount: Double, _ type: DamageType) -> Double {
		if !suit.worn { return amount }
		let st: ExoStats = suitStats
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
		if a > 0 && suitHas(.barrier) && type != .starve && type != .drown {
			let take: Double = a * 0.4
			if suitSpend(.barrier, take * 3.0) {
				a -= take
				spawnParticles(pb.x, pb.cy, 0xC07CFF, 4, 2.5, 0.25, 0)
			}
		}
		return a
	}

	/// How much slower the cold gets in through the suit
	var suitColdMul: Double {
		if !suit.worn { return 1.0 }
		var m: Double = 1.0 - suitStats.coldCut
		if suitHas(.seal) { m *= 0.1 }
		return m
	}

	/// The drill arm, if it can bore right now: its tier (0: no drill)
	func suitDrillTier() -> Int {
		if !suitHas(.drill) { return 0 }
		return suitStats.drillTier
	}

	// MARK: putting the suit on and off

	/// Puts the suit on: it needs its chest frame and core, and the armour slots for head, body and legs
	/// must be free (armour worn there goes into the bag first). Returns what to say.
	@discardableResult
	func wearSuit() -> String {
		let st: ExoStats = suitStats
		if !st.complete { return st.notes.first ?? "The suit is not complete." }
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

	/// Fits every part of a planned suit at once. A planned part comes from the suit itself if it is
	/// already on it (moved or kept), otherwise out of the bag (the very item chosen, infusions and all);
	/// the parts left over go back into the bag. If anything planned can't be found, nothing at all
	/// changes. Returns what to say.
	@discardableResult
	func applySuit(_ plan: ExoSuit) -> String {
		for slot in ExoSlot.allCases {
			if let n = plan[slot], !slot.fits(n.item) { return joinText(n.item.name, " doesn't fit the ", slot.name.lowercased(), ".") }
		}
		var pool: [Stack] = Array(suit.parts.values)
		var bag: [Stack?] = inv.slots
		for slot in ExoSlot.allCases {
			guard let n = plan[slot] else { continue }
			if let j = pool.firstIndex(of: n) {
				pool.remove(at: j)
			} else if let i = bag.firstIndex(where: { $0 == n }) {
				bag[i] = nil
			} else {
				return joinText(n.item.name, " is no longer in your bag: nothing was changed.")
			}
		}
		inv.slots = bag
		let wasWorn: Bool = suit.worn
		var next: ExoSuit = plan
		next.worn = false
		next.energy = suit.energy
		next.off = suit.off
		suit = next
		// the parts taken off go back (after the new ones have left the bag, so there is room)
		for b in pool { addStack(b) }
		let st: ExoStats = ExoStats.of(suit)
		suit.energy = min(suit.energy, st.capacity)
		if wasWorn && st.complete { suit.worn = true }
		// a cargo pack taken off empties into the bag (nothing is left stranded in it)
		if !st.has(.cargo) { emptyPack() }
		suitChanged()
		sfx(.craft, 0.7)
		if wasWorn && !st.complete { return "Built. The suit came off: it needs a chest frame and a core to run." }
		return wasWorn ? "Built and still on." : "Built."
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

	/// The look the player's sprite takes from the suit (nil: not worn)
	func suitLook() -> SuitLook? {
		if !suit.worn { return nil }
		var l: SuitLook = SuitLook()
		func col(_ s: ExoSlot) -> UInt32 { return suit.material(s)?.color ?? 0 }
		l.helmet = col(.helmet)
		l.chest = col(.chest)
		l.armL = col(.armL)
		l.armR = col(.armR)
		l.legs = col(.legs)
		l.boots = col(.boots)
		l.plateHead = col(.plateHead)
		l.plateShoulders = col(.plateShoulders)
		l.plateChest = col(.plateChest)
		l.plateArms = col(.plateArms)
		l.plateLegs = col(.plateLegs)
		l.core = suit.core?.color ?? 0
		let st: ExoStats = suitStats
		l.drill = st.has(.drill)
		l.lamp = st.has(.lamp)
		l.pack = st.has(.cargo)
		l.jets = st.has(.hover)
		return l
	}
}

/// How a worn suit looks on the player: a colour for each part (0: not fitted) and its modules
struct SuitLook: Hashable {
	var helmet: UInt32 = 0
	var chest: UInt32 = 0
	var armL: UInt32 = 0
	var armR: UInt32 = 0
	var legs: UInt32 = 0
	var boots: UInt32 = 0
	var plateHead: UInt32 = 0
	var plateShoulders: UInt32 = 0
	var plateChest: UInt32 = 0
	var plateArms: UInt32 = 0
	var plateLegs: UInt32 = 0
	var core: UInt32 = 0
	var drill: Bool = false
	var lamp: Bool = false
	var pack: Bool = false
	var jets: Bool = false
}

/// The suit drawn over a humanoid frame (22 x 17, the figure 10 wide from column 6): frame colours on
/// the body, a visor across the face, plates where they are fitted, the core's glow, and the modules
/// that show (a drill on the front arm, a lamp on the helmet, a pack on the back, jets on the boots)
func paintSuit(_ cv: inout PixelBuf, _ l: SuitLook, legs: Int, pose: Int) {
	let ox: Int = humanOX
	func px(_ x: Int, _ y: Int, _ c: UInt32) { cv.ink(ox + x, y, inkS(c)) }
	func lit(_ x: Int, _ y: Int, _ c: UInt32) { cv.ink(ox + x, y, inkF(c)) }
	let dark: UInt32 = 0x2A2E36
	if l.helmet != 0 {
		// a closed helm: the face is behind a visor
		for x in 3...6 { px(x, 1, l.helmet) }
		for x in 2...7 { px(x, 2, l.helmet) }
		px(2, 3, l.helmet)
		px(3, 3, l.helmet)
		for x in 4...7 { lit(x, 3, 0x60E0FF) }
		for x in 2...7 { px(x, 4, shadeRGB(l.helmet, 0.85)) }
		for x in 3...6 { px(x, 5, shadeRGB(l.helmet, 0.7)) }
		if l.plateHead != 0 { for x in 3...6 { px(x, 1, shadeRGB(l.plateHead, 1.15)) } }
		if l.lamp { lit(7, 2, 0xFFF4C0) }
	}
	if l.chest != 0 {
		for y in 7...9 { for x in 3...6 { px(x, y, l.chest) } }
		for x in 2...7 { px(x, 10, dark) }
		if l.plateChest != 0 {
			for x in 3...6 { px(x, 7, shadeRGB(l.plateChest, 1.15)) }
			for x in 3...6 { px(x, 8, l.plateChest) }
		}
		if l.core != 0 {
			lit(4, 8, l.core)
			lit(5, 8, shadeRGB(l.core, 1.3))
		}
	}
	// arms: the back arm (left column pair) and the front arm (right pair, unless a pose draws its own)
	let frontFree: Bool = pose < 2
	for y in 7...9 {
		if l.armL != 0 { px(1, y, l.armL); px(2, y, shadeRGB(l.armL, 0.85)) }
		if l.armR != 0 && frontFree { px(7, y, l.armR); px(8, y, shadeRGB(l.armR, 0.85)) }
	}
	if l.plateShoulders != 0 && l.chest != 0 {
		px(1, 7, shadeRGB(l.plateShoulders, 1.2))
		px(2, 7, l.plateShoulders)
		if frontFree { px(7, 7, l.plateShoulders); px(8, 7, shadeRGB(l.plateShoulders, 1.2)) }
		px(1, 6, l.plateShoulders)
		if frontFree { px(8, 6, l.plateShoulders) }
	}
	if l.plateArms != 0 {
		if l.armL != 0 { px(1, 9, l.plateArms); px(2, 9, l.plateArms) }
		if l.armR != 0 && frontFree { px(7, 9, l.plateArms); px(8, 9, l.plateArms) }
	}
	if l.drill && l.armR != 0 && frontFree {
		lit(9, 9, 0xD8D8E0)
		lit(10, 9, 0xB0B0B8)
		lit(11, 9, 0x8A8A94)
	}
	// legs and boots follow the stride of the frame
	let legCols: [Int] = legs == 1 ? [1, 2, 7, 8] : (legs == 2 ? [3, 4, 5, 6] : [2, 3, 6, 7])
	if l.legs != 0 {
		for y in 11...14 { for x in legCols { px(x, y, y == 11 ? shadeRGB(l.legs, 0.9) : l.legs) } }
		if l.plateLegs != 0 { for x in legCols { px(x, 13, shadeRGB(l.plateLegs, 1.15)) } }
	}
	if l.boots != 0 {
		for x in legCols { px(x, 15, l.boots) }
		if l.jets { lit(legCols[0], 15, 0xFF9A3A) }
	}
	if l.pack {
		for y in 7...10 {
			cv.ink(ox - 1, y, inkS(0x6A4A2A))
			cv.ink(ox, y, inkS(0x8A6A3A))
		}
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

/// The suit seen from the front (view 0) or the back (view 1), 40 x 56. Fitted parts in their metal's
/// colour; missing ones as a faint outline, so the empty places can be seen.
func suitViewBuf(_ s: ExoSuit, _ view: Int) -> PixelBuf {
	var b = PixelBuf(w: 40, h: 56)
	let ghost: UInt32 = 0x46505E
	let dark: UInt32 = 0x2A2E36
	func part(_ slot: ExoSlot) -> UInt32? { return s.material(slot)?.color }
	func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32?) {
		if let col = c {
			b.rect(x, y, w, h, col)
			b.rect(x, y, w, 1, shadeRGB(col, 1.25))
			b.rect(x, y + h - 1, w, 1, shadeRGB(col, 0.7))
		} else {
			// outline only
			b.rect(x, y, w, 1, ghost)
			b.rect(x, y + h - 1, w, 1, ghost)
			b.rect(x, y, 1, h, ghost)
			b.rect(x + w - 1, y, 1, h, ghost)
		}
	}
	let back: Bool = view == 1
	// left and right as the viewer sees them: from the back, the suit's left arm is on the left
	let leftArm: ExoSlot = back ? .armL : .armR
	let rightArm: ExoSlot = back ? .armR : .armL
	// helmet
	box(14, 2, 12, 10, part(.helmet))
	if part(.helmet) != nil {
		if !back { b.rect(15, 6, 10, 3, 0x60E0FF); b.rect(15, 6, 10, 1, 0xB8F4FF) } else { b.rect(16, 5, 8, 1, shadeRGB(part(.helmet) ?? 0, 0.75)) }
		if let p = part(.plateHead) { b.rect(15, 2, 10, 2, shadeRGB(p, 1.15)) }
		if s.modules.contains(.lamp) && !back { b.rect(25, 5, 2, 2, 0xFFF4C0) }
	}
	b.rect(18, 12, 4, 2, dark)
	// chest frame
	box(11, 14, 18, 13, part(.chest))
	box(13, 27, 14, 3, part(.chest))
	if let c = part(.chest) {
		if let p = part(.plateChest), !back { b.rect(13, 16, 14, 7, shadeRGB(p, 0.9)); b.rect(14, 17, 12, 5, p); b.rect(14, 17, 12, 1, shadeRGB(p, 1.3)) }
		if let core = s.core, !back {
			b.ellipse(20, 20, 2.6, 2.6, shadeRGB(core.color, 0.7))
			b.ellipse(20, 20, 1.6, 1.6, core.color)
			b.set(19, 19, 0xFFFFFF)
		}
		if back {
			b.rect(15, 16, 10, 9, shadeRGB(c, 0.8))
			for k in 0..<3 { b.rect(16, 17 + k * 3, 8, 1, dark) }
			if s.modules.contains(.cargo) { b.rect(13, 15, 14, 12, 0x6A4A2A); b.rect(13, 15, 14, 2, 0x8A6A3A); b.rect(19, 19, 2, 2, 0xE8C060) }
			if s.modules.contains(.hover) { b.rect(12, 18, 3, 8, 0x9AA4B0); b.rect(25, 18, 3, 8, 0x9AA4B0); b.rect(12, 26, 3, 2, 0xFF9A3A); b.rect(25, 26, 3, 2, 0xFF9A3A) }
		} else if s.modules.contains(.cargo) {
			b.rect(14, 14, 1, 12, 0x6A4A2A)
			b.rect(25, 14, 1, 12, 0x6A4A2A)
		}
	}
	if let p = part(.plateShoulders), part(.chest) != nil {
		b.rect(7, 13, 7, 4, shadeRGB(p, 0.85)); b.rect(7, 13, 7, 1, shadeRGB(p, 1.3))
		b.rect(26, 13, 7, 4, shadeRGB(p, 0.85)); b.rect(26, 13, 7, 1, shadeRGB(p, 1.3))
	}
	// arms
	box(6, 16, 5, 18, part(leftArm))
	box(29, 16, 5, 18, part(rightArm))
	if let p = part(.plateArms) {
		if part(leftArm) != nil { b.rect(6, 19, 5, 4, shadeRGB(p, 1.1)) }
		if part(rightArm) != nil { b.rect(29, 19, 5, 4, shadeRGB(p, 1.1)) }
	}
	if part(leftArm) != nil { b.rect(6, 34, 5, 3, dark) }
	if part(rightArm) != nil { b.rect(29, 34, 5, 3, dark) }
	// the drill on the right arm, the gauntlet on the left
	let drillSide: Int = back ? 6 : 29
	let gauntSide: Int = back ? 29 : 6
	if s.modules.contains(.drill) { b.rect(drillSide + 1, 37, 3, 3, 0xD8D8E0); b.rect(drillSide + 2, 40, 1, 2, 0xA8A8B0) }
	if s.modules.contains(.gauntlet) { b.rect(gauntSide, 33, 5, 3, 0xFFF07A) }
	// legs and boots
	b.rect(13, 30, 14, 2, dark)
	box(13, 32, 6, 16, part(.legs))
	box(21, 32, 6, 16, part(.legs))
	if let p = part(.plateLegs), part(.legs) != nil { b.rect(13, 38, 6, 3, shadeRGB(p, 1.15)); b.rect(21, 38, 6, 3, shadeRGB(p, 1.15)) }
	box(12, 48, 7, 6, part(.boots))
	box(21, 48, 7, 6, part(.boots))
	if s.modules.contains(.hover) && part(.boots) != nil { b.rect(14, 54, 2, 2, 0xFF9A3A); b.rect(24, 54, 2, 2, 0xFF9A3A) }
	if s.modules.contains(.sprint) && part(.legs) != nil { b.rect(13, 44, 6, 1, 0x7AD8F8); b.rect(21, 44, 6, 1, 0x7AD8F8) }
	b.outline(0x101418)
	return b
}

/// Built suit pictures (redrawn only when the suit or the view changes)
final class SuitArt: @unchecked Sendable {
	static let shared: SuitArt = SuitArt()
	var cache: [Int: Image] = [:]

	func image(_ s: ExoSuit, _ view: Int) -> Image {
		var h: Hasher = Hasher()
		for k in s.parts.keys.sorted() {
			h.combine(k)
			h.combine(s.parts[k]?.item)
		}
		h.combine(view)
		let key: Int = h.finalize()
		if let i = cache[key] { return i }
		var img: Image
		if view == 2 {
			// side on, as it is worn in the world
			var st: HumanStyle = playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil)
			st.suit = suitLookOf(s)
			img = pixImage(humanoidFrame(st, legs: 0, pose: 0))
		} else {
			img = pixImage(suitViewBuf(s, view))
		}
		if cache.count > 64 { cache.removeAll() }
		cache[key] = img
		return img
	}
}

/// How a suit would look worn (for the side view, worn or not)
func suitLookOf(_ s: ExoSuit) -> SuitLook {
	var l: SuitLook = SuitLook()
	func col(_ x: ExoSlot) -> UInt32 { return s.material(x)?.color ?? 0 }
	l.helmet = col(.helmet)
	l.chest = col(.chest)
	l.armL = col(.armL)
	l.armR = col(.armR)
	l.legs = col(.legs)
	l.boots = col(.boots)
	l.plateHead = col(.plateHead)
	l.plateShoulders = col(.plateShoulders)
	l.plateChest = col(.plateChest)
	l.plateArms = col(.plateArms)
	l.plateLegs = col(.plateLegs)
	l.core = s.core?.color ?? 0
	let mods: [ExoModule] = s.modules
	l.drill = mods.contains(.drill)
	l.lamp = mods.contains(.lamp)
	l.pack = mods.contains(.cargo)
	l.jets = mods.contains(.hover)
	return l
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
		if t != .bedL && t != .bedR { return }
		let hx: Int = t == .bedR ? tx - 1 : tx
		spawnX = Double(hx) + 1.0
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
}

enum BlockPhysTable {
	static let table: [BlockPhys] = Tile.allCases.map { blockPhysOf($0) }
}

/// The material numbers of the game's own blocks (mod blocks are worked out from their hardness)
func blockPhysOf(_ t: Tile) -> BlockPhys {
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
	if t.isMod { return blockPhysFrom(t.def) }
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
