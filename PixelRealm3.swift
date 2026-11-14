// PIXEL REALM v2, part 3 of 8: creature AI, spawning, combat, damage and bosses, ships, the portal and map, saving, helpers, walls and
// doors, the vehicle screens' logic, vehicles of every kind (flight, weapons, damage, the assembler, the
// autopilot), and Sparkworks (power).
// The game is eight files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm8.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 2 (a01_artsheet).

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
		let throttle: Double = v.rider || v.auto != 0 ? v.throttle : 0
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

// ===== p33_vehicles =====

// MARK: - Vehicles of every kind: blocks on vehicles, flight, weapons, damage, turning, assembling, the autopilot
// A vehicle is a rigid body built cell by cell (p13b_vehicles, p17_vehicles_ships). This part adds what
// makes planes, helicopters, airships, tanks and anything in between work: every cell can be any block,
// each cell weighs what it is made of, and the air acts on each cell where it is (lift on wings, drag on
// exposed faces, thrust along propellers, rotor lift, hot air in balloons), so a design flies, floats or
// tumbles because of how it is built.

/// Hitting the ground faster than this (blocks per second, straight into it) breaks parts
let vehicleCrashSpeed: Double = 21.0

/// The numbers of the flight model
enum Aero {
	/// lift per wing cell: kLift x airspeed^2 x lift coefficient (a 10-mass plane with 3 wing cells
	/// leaves the ground at about 11 blocks a second)
	static let kLift: Double = 0.8
	/// drag per exposed face: kDrag x drag coefficient x airspeed^2
	static let kDrag: Double = 0.022
	/// how much a face tucked behind another still feels the air (skin friction)
	static let shielded: Double = 0.06
	/// share of the wing drag coefficient applied (the wing's own profile drag)
	static let dragShare: Double = 1.0
	/// lift slope per radian, the angle where a wing stalls, the post-stall lift
	static let liftSlope: Double = 5.0
	static let stallAngle: Double = 0.27
	/// how far an elevator's flap turns the airflow (radians at full stick), and the elevator's size
	/// against a wing's
	static let flap: Double = 0.55
	static let elevatorArea: Double = 1.0
	/// a wing's camber: it lifts a little even meeting the air head on (radians of extra angle)
	static let camber: Double = 0.07
	/// a wing's tilt: steps of this angle (radians), up to this many either way
	static let tiltStep: Double = 0.05
	static let tiltSteps: Int = 3
	/// a flap's drop at its lowest (it drops below flapSpeed, fully by half of it), and its drag then
	static let flapDrop: Double = 0.16
	static let flapSpeed: Double = 18.0
	static let flapDrag: Double = 0.07
	/// an open air brake's drag, and how fast it opens and closes (per second)
	static let brakeDrag: Double = 1.8
	static let brakeRate: Double = 2.5
	/// a tailplane's area (a wing is 1)
	static let stabArea: Double = 0.6
	/// how fast ballast tanks fill or empty at full stick (of a tank a second)
	static let ballastRate: Double = 0.25
	/// static thrust of an air propeller per engine of power, and the airspeed where it fades out
	static let propThrust: Double = 110.0
	static let propVmax: Double = 64.0
	/// a jet's thrust (it is its own engine)
	static let jetThrust: Double = 165.0
	/// rotor lift per engine of power at full blade pitch
	static let rotorLift: Double = 265.0
	/// a heated balloon envelope's lift (mass it can hold up at full heat), and how many envelopes one burner heats
	static let envLift: Double = 1.3
	static let burnerCells: Int = 12
	/// how far the cyclic tilts a helicopter at full stick, and how firmly it holds the tilt
	static let cyclicTilt: Double = 0.3
	/// hands off, a helicopter tilts against its drift to hover in place (radians per block a second)
	static let hoverHold: Double = 0.035
	/// the turning rotor disc resists the air across it (what keeps a helicopter's speed down)
	static let rotorDrag: Double = 0.25
	/// up and down on the stick ask a helicopter for this climb or sink rate (blocks a second)
	static let climbRate: Double = 9.0
	static let cyclicP: Double = 16.0
	static let cyclicD: Double = 7.5
	/// how fast blade pitch follows the stick, and how fast a burner heats the balloon and venting cools it
	static let collectiveRate: Double = 0.9
	static let heatRate: Double = 0.14
	static let ventRate: Double = 0.22
	/// a balloon's canopy against the air going up or down through it (a cold balloon comes down slowly)
	static let canopyDrag: Double = 8.0
	/// the cyclic's trim: how fast it learns to hold the tilt against an off-centre rotor
	static let cyclicI: Double = 6.0
	/// the pitch control: full stick asks for this pitch rate (radians a second); the elevators are moved
	/// to get it (as far as they can at this speed), and the trim learns what holds the nose steady
	static let pitchRate: Double = 0.9
	static let rateGain: Double = 1.3
	static let trimRate: Double = 1.6
	/// the stall guard: past this share of the stall angle the nose is eased down instead of pulled up
	static let alphaGuard: Double = 0.75
	/// hands off, how fast the nose comes back to level (radians a second per radian)
	static let levelRate: Double = 0.4
	/// seconds a turn to face the other way takes in flight
	static let turnTime: Double = 1.4
}

/// The numbers of wheels, tracks and water propellers
enum Drive {
	/// what one engine gives its wheels (push times speed): above about 8 blocks a second its push falls
	static let power: Double = 1415.0
	/// what the wheels and gearing take, per block a second of speed; a little more for every unit of
	/// weight on them; tracks take a good deal more
	static let loss: Double = 10.0
	static let lossPerMass: Double = 0.028
	static let trackLoss: Double = 0.8
	/// what one engine gives a water propeller, how fast a paddle's stroke goes (blocks a second), and
	/// the share of the water's drag that grows with the square of the speed
	static let propPower: Double = 130.0
	static let paddleStroke: Double = 9.0
	static let waterDrag: Double = 0.002
	/// how hard a tyre can push along what it touches, for each unit it is pressed against it
	static let tyreGrip: Double = 1.0
}

/// Air thins with height: full below the hills, about half at the top of the sky
func airDensity(_ y: Double) -> Double {
	let top: Double = Double(WorldGen.sea) - 60.0
	if y >= top { return 1.0 }
	return max(0.45, 1.0 - 0.55 * (top - y) / max(1.0, top))
}

/// A wing's lift coefficient at an angle of attack (radians, folded to -pi/2...pi/2): straight up to
/// the stall, then it falls away to a flat plate's
func liftCoefficient(_ a: Double) -> Double {
	let s: Double = Aero.stallAngle
	let m: Double = abs(a)
	let sign: Double = a >= 0 ? 1.0 : -1.0
	if m <= s { return Aero.liftSlope * a }
	let peak: Double = Aero.liftSlope * s
	let flat: Double = 0.9 * sin(2.0 * m)
	let fade: Double = clampD((m - s) / 0.16, 0, 1)
	return sign * (peak * 0.85 * (1.0 - fade) + flat * fade)
}

/// A wing's drag coefficient: a little on its own, more as it lifts, a flat plate's beyond the stall
func wingDrag(_ a: Double, _ cl: Double) -> Double {
	let sa: Double = sin(a)
	return 0.012 + 0.06 * cl * cl + 1.1 * sa * sa
}

/// How much a part catches the air (a bare block is 1)
func partDrag(_ t: PartType) -> Double {
	switch t {
	case .cockpit: return 0.45
	case .jet: return 0.3
	case .airProp, .tailRotor, .rotor: return 0.4
	case .envelope: return 3.0
	case .wheel, .offroadWheel: return 0.45
	case .headlight, .steering, .autopilot, .autoGun, .propeller, .paddle: return 0.5
	default: return 1.0
	}
}

/// The mass of a block built onto a vehicle: its building weight (planks 0.6, stone 2.5)
func vehicleBlockMass(_ b: Tile, _ t: PartType) -> Double {
	if b.isMod, t != .block, let m = ModRuntime.shared.blockDef(b), m.vehMass > 0 { return m.vehMass }
	return max(0.05, tileWeight(b))
}

/// How much water a cell pushes aside when under (its buoyancy): a solid block a whole cell (so wood
/// floats and stone sinks), anything else a little
func cellDisplacement(_ v: Vehicle, _ c: PartCell, _ t: PartType) -> Double {
	if t == .block, let b = v.blocks[c] { return b.solid ? 1.0 : 0.2 }
	if t == .ballast { return 0.15 + 0.85 * (1.0 - v.ballast) }
	if let k = v.spanOf[c], k != c { return 0 }
	return partDisplacement(t)
}

/// How much damage a part takes before it breaks off
func partHP(_ t: PartType) -> Double {
	switch t {
	case .hinge, .servo, .piston: return 35
	case .bigWheel: return 70
	case .railWheel, .coupler: return 30
	case .ballast: return 40
	case .flap: return 22
	case .airBrake: return 18
	case .stabilizer: return 14
	case .armor: return 160
	case .track, .jet, .drill, .diamondDrill, .voidDrill, .cannon: return 55
	case .engine, .hull, .cargo, .frame, .offroadWheel: return 40
	case .cockpit, .rotor, .autoGun, .burner, .fuelTank: return 30
	case .wheel, .seat, .wing, .airProp: return 22
	case .elevator, .propeller, .paddle, .steering, .tailRotor, .autopilot: return 14
	case .headlight: return 10
	case .envelope: return 7
	case .block: return 30
	}
}

/// How much damage one cell takes before it breaks (a block by its hardness and weight)
func vehicleCellHP(_ v: Vehicle, _ c: PartCell, _ t: PartType) -> Double {
	if let b = v.blocks[c] {
		let base: Double = 8.0 + min(90.0, b.hardness * 14.0) + tileWeight(b) * 4.0
		return t == .block ? base : max(base, partHP(t))
	}
	return partHP(t)
}

/// What a cell taken off a vehicle gives back: its block, or the part
func vehicleCellItem(_ r: VCell) -> Item {
	if let b = r.tile { return .block(b) }
	return .part(r.type == .block ? .frame : r.type)
}

/// A block turned to face the other way (stairs rise the other way, a bed's head moves)
func mirroredTile(_ t: Tile) -> Tile {
	switch t {
	case .stairWoodR: return .stairWoodL
	case .stairWoodL: return .stairWoodR
	case .stairStoneR: return .stairStoneL
	case .stairStoneL: return .stairStoneR
	case .stairBrickR: return .stairBrickL
	case .stairBrickL: return .stairBrickR
	case .bedL: return .bedR
	case .bedR: return .bedL
	default: return t
	}
}

/// Blocks the assembler leaves in the world: the ground's own, liquids, lifts and portals
func canAssemble(_ t: Tile) -> Bool {
	if t == .air || t.liquid || t == .bedrock { return false }
	switch t {
	case .liftRail, .liftButton, .liftCar, .portalOn, .portalOff: return false
	default: return true
	}
}

/// Where a shot meets a vehicle: how far along its step, which vehicle, which cell
struct VehicleHit {
	var t: Double
	var v: Vehicle
	var cell: PartCell
}

extension Game {
	// MARK: power

	/// The engines' power goes where it is needed: driving wheels on a ground vehicle, every air
	/// propeller, every rotor (a rotor takes as much as three engines' worth, a propeller one and a half).
	/// The share for the wheels (1 for a car or a tank: they get it all)
	func groundShare(_ v: Vehicle) -> Double {
		let wheels: Double = v.wings == 0 && v.rotors == 0 ? 1.0 : 0.0
		let total: Double = wheels + Double(v.airProps) * 1.5 + Double(v.rotors) * 3.0
		return total <= 0 ? 0 : wheels / total
	}

	/// Engine power each air propeller and each rotor gets (in engines); `anyway` works it out as if
	/// fuelled and crewed (for the checklist)
	func airPower(_ v: Vehicle, anyway: Bool = false) -> (Double, Double) {
		if v.engines == 0 { return (0, 0) }
		if !anyway && (!(v.fuel > 0 || isCreative) || !(v.hasSeat && v.hasSteering)) { return (0, 0) }
		let wheels: Double = v.wings == 0 && v.rotors == 0 ? 1.0 : 0.0
		let total: Double = wheels + Double(v.airProps) * 1.5 + Double(v.rotors) * 3.0
		if total <= 0 { return (0, 0) }
		let e: Double = v.enginePower
		return (e * 1.5 / total, e * 3.0 / total)
	}

	/// The most the rotors can lift (force) here, at full blade pitch
	func rotorMax(_ v: Vehicle, anyway: Bool = false) -> Double {
		let p: (Double, Double) = airPower(v, anyway: anyway)
		return Aero.rotorLift * p.1 * v.rotorLift * (0.35 + 0.65 * airDensity(v.py))
	}

	/// The most the balloons can lift (force) here, at full heat
	func balloonMax(_ v: Vehicle) -> Double {
		if v.burners == 0 || v.envelopes == 0 { return 0 }
		let heated: Double = Double(min(v.envelopes, v.burners * Aero.burnerCells))
		return gravityG * Aero.envLift * heated * airDensity(v.py)
	}

	/// The wings' lift at a speed, flying level at a good angle (for the checklist and instruments)
	func wingLiftAt(_ v: Vehicle, _ speed: Double) -> Double {
		return Aero.kLift * speed * speed * Double(v.wings) * 1.1
	}

	/// The push the propellers and jets give at a speed, at full throttle
	func thrustAt(_ v: Vehicle, _ speed: Double) -> Double {
		let p: (Double, Double) = airPower(v, anyway: true)
		let prop: Double = Aero.propThrust * p.0 * Double(v.airProps) * max(0, 1.0 - speed / Aero.propVmax)
		let jet: Double = Aero.jetThrust * Double(v.jets) * max(0.35, 1.0 - speed / 90.0)
		return prop + jet
	}

	// MARK: the flight model

	/// Forces of the air on every part, for one physics step: drag on each part's exposed faces, lift on
	/// wings and elevators from the real airflow over each one (its speed, the angle it meets the wing at,
	/// the wind), thrust from propellers and jets along the vehicle's axis, rotor lift along the rotor
	/// shaft, and the hot air in the balloons pushing straight up. Each force acts at its own part, so the
	/// layout decides how the vehicle pitches: a tail far behind steadies it, balloons above keep it
	/// upright, a heavy nose tips it forward.
	func airForces(_ v: Vehicle, _ h: Double, _ throttle: Double) {
		let c: Double = v.cosA
		let s: Double = v.sinA
		let rho: Double = airDensity(v.py)
		let power: (Double, Double) = airPower(v)
		let canFly: Bool = (v.fuel > 0 || isCreative) && v.hasSeat && v.hasSteering
		// while turning round the throttle keeps pushing toward the nose, whichever way the stick points
		let steer: Double = v.turnT > 0 ? abs(throttle) * Double(v.fwd) : throttle
		let thr: Double = canFly ? steer : 0
		// the elevators turn the nose the way the stick says (up: toward the top of the screen)
		let noseX: Double = Double(v.fwd) * c
		let noseSign: Double = noseX >= 0 ? 1.0 : -1.0
		let rateErr: Double = pitchRateWanted(v) - (-v.angVel * noseSign)
		let cmd: Double = clampD(v.trim + Aero.rateGain * rateErr, -1, 1)
		let wantSpin: Double = -cmd * noseSign
		let bank: Double = v.turnT > 0 ? 0.7 + 0.3 * abs(cos(Double.pi * v.turnT)) : 1.0
		let rotorF: Double = Aero.rotorLift * power.1 * v.collective * (0.35 + 0.65 * rho)
		let heated: Double = v.envelopes > 0 ? min(1.0, Double(v.burners * Aero.burnerCells) / Double(v.envelopes)) : 0
		let envF: Double = gravityG * Aero.envLift * v.heat * heated * rho
		var fx: Double = 0
		var fy: Double = 0
		var torque: Double = 0
		var lift: Double = 0
		var thrust: Double = 0
		var stalled: Bool = false
		var alpha: Double = 0
		for (cell, t) in v.parts {
			let lx: Double = Double(cell.dx) + 0.5 - v.comX
			let ly: Double = Double(cell.dy) + 0.5 - v.comY
			let rx: Double = lx * c - ly * s
			let ry: Double = lx * s + ly * c
			// the air going past this part (the wind, less the part's own motion), in the vehicle's frame
			let ux: Double = v.windX - (v.vx - v.angVel * ry)
			let uy: Double = -(v.vy + v.angVel * rx)
			let bx: Double = ux * c + uy * s
			let by: Double = -ux * s + uy * c
			var fbx: Double = 0
			var fby: Double = 0
			let k: Double = v.boost[cell] ?? 1.0
			if t == .wing || t == .elevator || t == .flap || t == .stabilizer {
				// (its tilt, and a flap's drop when slow, turn the wing further into the air)
				var extra: Double = Double(v.tilt[cell] ?? 0) * Aero.tiltStep
				if t == .flap { extra += Aero.flapDrop * clampD((Aero.flapSpeed - v.airspeed) / (Aero.flapSpeed * 0.5), 0, 1) }
				let wide: Bool = t == .wing || t == .flap
				let f: (Double, Double, Double, Bool, Double) = wingForce(t, bx, by, lx, rho, wantSpin, wide ? bank * k : k, extra)
				fbx = f.0
				fby = f.1
				if t == .wing || t == .flap {
					lift += f.2
					alpha = max(alpha, f.4)
				}
				if f.3 { stalled = true }
			} else {
				let d: (Double, Double) = faceDrag(v, cell, t, bx, by, rho)
				fbx = d.0
				fby = d.1
				switch t {
				case .airProp:
					if power.0 > 0 && abs(thr) > 0.05 && !v.boxed.contains(cell) {
						// along the vehicle's axis either way (the blades reverse at half strength)
						let eff: Double = max(0, 1.0 - abs(bx) / Aero.propVmax)
						let w: Double = thr > 0 ? thr : thr * 0.5
						let f: Double = Aero.propThrust * power.0 * eff * w * k * (0.4 + 0.6 * rho)
						fbx += f
						thrust += abs(f)
					}
				case .jet:
					if canFly && abs(thr) > 0.05 && !v.boxed.contains(cell) {
						// it pushes away from its exhaust; pulled back, its reverser brakes at a third
						let dirX: Double = -Double((v.face[cell] ?? (-1, 0)).0)
						let along: Double = thr * dirX
						let w: Double = along > 0 ? along : along * 0.35
						let f: Double = Aero.jetThrust * w * k * dirX * (0.7 + 0.3 * rho) * max(0.35, 1.0 - abs(bx) / 90.0)
						fbx += f
						thrust += abs(f)
					}
				case .airBrake:
					if v.brakeOpen > 0.01 {
						// a panel across the flow: drag by how far it is open
						let q: Double = Aero.brakeDrag * Aero.kDrag * rho * v.brakeOpen * k
						fbx += q * bx * abs(bx)
						fby += q * by * abs(by)
					}
				case .rotor:
					if rotorF > 0 {
						// (blades with parts in their way lift by the room they have)
						let room: Double = v.rotorRoom[cell] ?? 1.0
						fby -= rotorF * k * room
						lift += rotorF * k * room
						// the disc drags against air going across it
						fbx += Aero.rotorDrag * rho * bx * abs(bx) * min(1.0, v.collective * 1.5)
					}
				default:
					break
				}
			}
			// to the world, then onto the body at this part
			var wfx: Double = fbx * c - fby * s
			var wfy: Double = fbx * s + fby * c
			if t == .envelope && envF > 0 {
				// hot air rises: straight up, whatever the tilt (so balloons above keep it upright)
				wfy -= envF * k
				lift += envF * k
			}
			fx += wfx
			fy += wfy
			torque += rx * wfy - ry * wfx
			wfx = 0
			wfy = 0
		}
		let invM: Double = 1.0 / v.mass
		v.vx += fx * invM * h
		v.vy += fy * invM * h
		v.angVel += torque / v.inertia * h
		if v.rotors > 0 && rotorF > 0 { cyclic(v, thr, h) }
		v.liftNow = lift
		v.thrustNow = thrust
		v.stall = stalled
		v.alpha = alpha
	}

	/// The pitch rate the pilot asks for (nose up positive), eased off near the stall: past the guard
	/// angle the nose is brought down a little, so holding the stick back climbs steeply without stalling
	/// while there is speed (slow it down too far and it still sinks)
	func pitchRateWanted(_ v: Vehicle) -> Double {
		var want: Double = v.pitch * Aero.pitchRate
		// hands off in flight, the nose eases back toward level (it holds a gentle climb or dive no longer)
		if abs(v.pitch) < 0.05 && v.contacts == 0 && v.auto == 0 {
			let noseUp: Double = -Double(v.fwd) * v.sinA
			want = clampD(-noseUp * Aero.levelRate, -0.3, 0.3)
		}
		let guardA: Double = Aero.stallAngle * Aero.alphaGuard
		// the angle the wing is heading for: now, plus where the nose is still swinging
		let noseX: Double = Double(v.fwd) * v.cosA
		let upRate: Double = -v.angVel * (noseX >= 0 ? 1.0 : -1.0)
		let ahead: Double = v.alpha + max(0, upRate) * 0.3
		if v.wings > 0 && ahead > guardA && v.airspeed > 4.0 { want = min(want, -(ahead - guardA) * 5.0) }
		return want
	}

	/// One wing or elevator: lift across the airflow and drag along it, from the angle the air meets it
	/// (folded so the wing works flying either way), with an elevator's flap turned by the stick.
	/// Returns the body-frame force, the lift, and whether it has stalled.
	func wingForce(_ t: PartType, _ bx: Double, _ by: Double, _ lx: Double, _ rho: Double, _ wantSpin: Double, _ scale: Double, _ extra: Double = 0) -> (Double, Double, Double, Bool, Double) {
		let sp2: Double = bx * bx + by * by
		if sp2 < 0.09 { return (0, 0, 0, false, 0) }
		let sp: Double = sqrt(sp2)
		let dx: Double = bx / sp
		let dy: Double = by / sp
		var a: Double = atan2(-dy, -dx)
		if a > Double.pi * 0.5 { a -= Double.pi } else if a < -Double.pi * 0.5 { a += Double.pi }
		// the camber lifts toward the top of the wing whichever way the air comes; a tilt or a dropped flap
		// adds to it
		if t == .wing || t == .flap { a += dx < 0 ? Aero.camber : -Aero.camber }
		if extra != 0 { a += dx < 0 ? extra : -extra }
		var area: Double = 1.0
		if t == .stabilizer { area = Aero.stabArea }
		if t == .elevator {
			// the flap, tilted the way that turns the nose as asked (behind or ahead of the centre of mass)
			area = Aero.elevatorArea
			let flow: Double = bx < 0 ? 1.0 : -1.0
			let side: Double = lx >= 0 ? 1.0 : -1.0
			a += -wantSpin * side * flow * Aero.flap
		}
		let cl: Double = liftCoefficient(a)
		var cd: Double = wingDrag(a, cl)
		if t == .flap { cd += Aero.flapDrag * clampD(extra / Aero.flapDrop, 0, 1) }
		let q: Double = Aero.kLift * rho * sp2 * area * scale
		let fbx: Double = q * cl * -dy + q * Aero.dragShare * cd * dx
		let fby: Double = q * cl * dx + q * Aero.dragShare * cd * dy
		let stalled: Bool = (t == .wing || t == .flap) && abs(a) > Aero.stallAngle && sp > 4.0
		return (fbx, fby, abs(q * cl), stalled, sp > 4.0 ? abs(a) : 0)
	}

	/// Drag on a part's faces that meet the air (a face tucked behind another part barely feels it)
	func faceDrag(_ v: Vehicle, _ cell: PartCell, _ t: PartType, _ bx: Double, _ by: Double, _ rho: Double) -> (Double, Double) {
		let cdp: Double = partDrag(t) * Aero.kDrag * rho
		var fx: Double = 0
		var fy: Double = 0
		if abs(bx) > 0.01 {
			let up: Int = bx < 0 ? 1 : -1
			let ex: Double = v.parts[PartCell(dx: cell.dx + up, dy: cell.dy)] == nil ? 1.0 : Aero.shielded
			fx = cdp * ex * bx * abs(bx)
		}
		if abs(by) > 0.01 {
			let up: Int = by < 0 ? 1 : -1
			let ey: Double = v.parts[PartCell(dx: cell.dx, dy: cell.dy + up)] == nil ? 1.0 : Aero.shielded
			let canopy: Double = t == .envelope ? Aero.canopyDrag : 1.0
			fy = cdp * ey * canopy * by * abs(by)
		}
		return (fx, fy)
	}

	/// The cyclic: the rotor tilts the helicopter toward the stick and holds it there (so it flies
	/// that way). A single rotor needs a tail rotor for this; without one its torque swings the
	/// helicopter round and it can hardly be steered. Two rotors turn opposite ways and need none.
	func cyclic(_ v: Vehicle, _ thr: Double, _ h: Double) {
		let steady: Bool = v.openTails > 0 || v.rotors >= 2
		// the stick tilts it; hands off it leans against its drift and comes to a hover
		var target: Double = clampD(thr, -1, 1) * Aero.cyclicTilt
		if abs(thr) < 0.1 { target = clampD(-v.vx * Aero.hoverHold, -Aero.cyclicTilt, Aero.cyclicTilt) }
		let a: Double = remainder(v.angle, 2.0 * Double.pi)
		let auth: Double = (0.35 + 0.65 * v.collective) * (steady ? 1.0 : 0.2)
		// the trim builds up against a steady pull (an off-centre rotor or load) so the tilt holds
		if steady { v.cycI = clampD(v.cycI + (target - a) * Aero.cyclicI * h, -12, 12) }
		v.angVel += (Aero.cyclicP * (target - a) + v.cycI - Aero.cyclicD * v.angVel) * auth * h
		if !steady { v.angVel += sin(clock * 2.3 + Double(v.id)) * 4.0 * v.collective * h }
	}

	/// Once a frame: blade pitch and burner heat follow the stick (hands off, they hold the height), the
	/// elevator trim settles, and the nose end is worked out from the way the vehicle moves
	func flightControls(_ v: Vehicle, _ dt: Double) {
		let piloted: Bool = (v.rider || v.auto != 0) && v.hasSeat && v.hasSteering
		let airborne: Bool = v.contacts == 0 && v.submerged <= 0.02
		let along: Double = v.vx * v.cosA + v.vy * v.sinA
		if abs(along) > 3.0 { v.fwd = along > 0 ? 1 : -1 }
		else if abs(v.throttle) > 0.2 && v.rider { v.fwd = v.throttle > 0 ? 1 : -1 }
		if v.rotors > 0 {
			if !piloted || airPower(v).1 <= 0 {
				v.collective = max(0, v.collective - dt * 0.4)
			} else if airborne || v.pitch > 0.05 {
				// the stick asks for a climb or sink rate (hands off: none, a hover); the blade pitch is set
				// for it, as far as the rotor can lift
				let need: Double = max(0, v.mass * gravityG - balloonLiftNow(v))
				let hover: Double = need / max(1.0, rotorMax(v))
				let wantVy: Double = -v.pitch * Aero.climbRate
				let want: Double = clampD(hover + (v.vy - wantVy) * 0.05, 0, 1)
				let step: Double = Aero.collectiveRate * dt
				v.collective += clampD((want - v.collective) * min(1.0, 4.0 * dt), -step, step)
			} else {
				v.collective = max(0, v.collective - dt * 0.6)
			}
			if !airborne { v.cycI *= (1.0 - min(1.0, 2.0 * dt)) }
		}
		if v.burners > 0 && v.envelopes > 0 {
			let fuelOK: Bool = v.fuel > 0 || isCreative
			if !piloted || !fuelOK {
				v.heat = max(0, v.heat - dt * 0.035)
			} else if abs(v.pitch) > 0.05 {
				v.heat = clampD(v.heat + v.pitch * (v.pitch > 0 ? Aero.heatRate : Aero.ventRate) * dt, 0, 1)
			} else if airborne {
				// hands off: the burner keeps the balloon just warm enough to float (no faster than it can heat)
				let full: Double = balloonMax(v)
				let need: Double = max(0, v.mass * gravityG - v.liftNow + balloonLiftNow(v))
				let eq: Double = full > 1 ? need / full : 0
				let want: Double = clampD(eq + v.vy * 0.05, 0, 1)
				v.heat += clampD(want - v.heat, -Aero.ventRate * dt, Aero.heatRate * dt)
			} else {
				v.heat = max(0, v.heat - dt * 0.05)
			}
		}
		if v.elevators > 0 {
			if airborne && v.turnT == 0 {
				// the trim learns the elevator that gives the pitch rate asked for (hands off: none, so the
				// nose stays where it is)
				let noseX: Double = Double(v.fwd) * v.cosA
				let upRate: Double = -v.angVel * (noseX >= 0 ? 1.0 : -1.0)
				v.trim = clampD(v.trim + (pitchRateWanted(v) - upRate) * Aero.trimRate * dt, -0.9, 0.9)
			} else if !airborne {
				v.trim *= (1.0 - min(1.0, 0.8 * dt))
			}
		}
	}

	/// The balloons' lift right now (force)
	func balloonLiftNow(_ v: Vehicle) -> Double {
		return balloonMax(v) * v.heat
	}

	/// Fuel for what flies: rotors turning, jets, burners (driving and propellers already burn it)
	func airFuel(_ v: Vehicle, _ dt: Double) {
		if isCreative || v.fuel <= 0 { return }
		var use: Double = 0
		let thr: Double = abs(v.throttle)
		if v.rotors > 0 && v.collective > 0.05 && thr <= 0.1 { use += Double(v.engines) * (0.4 + 0.6 * v.collective) }
		if v.jets > 0 && thr > 0.05 && (v.rider || v.auto != 0) { use += Double(v.jets) * 2.5 * thr }
		if v.burners > 0 && v.heat > 0.05 && (v.rider || v.auto != 0) { use += Double(v.burners) * 0.6 * v.heat }
		v.fuel = max(0, v.fuel - use * dt)
	}
}

extension Game {
	// MARK: every frame

	/// What a vehicle does besides moving, once a frame (even at rest): the flight controls and fuel,
	/// the guns, the autopilot when nobody drives, a turn in progress, rotor blades striking the ground,
	/// fuel tanks that burst
	func vehicleExtras(_ v: Vehicle, _ dt: Double) {
		if v.parts.isEmpty { return }
		if v.hitT > 0 { v.hitT -= dt }
		ballastAndBrakes(v, dt)
		updateHullAir(v, dt)
		if !v.asleep || v.aero { v.windX = windAtVehicle(v) * 0.6 }
		if v.aero {
			if v.auto != 0 && !v.rider { autopilotSteer(v, 0, 0, dt) }
			flightControls(v, dt)
			airFuel(v, dt)
			if v.rotors > 0 { rotorBlades(v, dt) }
			let spin: Double = v.rotors > 0 ? v.collective : min(1.0, abs(v.throttle))
			if v.rotors + v.airProps + v.tailRotors > 0 && airPower(v).0 + airPower(v).1 > 0 { v.propRot += dt * (4.0 + 26.0 * spin) }
			v.airspeed = sqrt((v.vx - v.windX) * (v.vx - v.windX) + v.vy * v.vy)
		} else if v.auto != 0 && !v.rider {
			autopilotSteer(v, 0, 0, dt)
		}
		if v.turnT > 0 { stepTurn(v, dt) }
		if v.cannons + v.guns > 0 { runVehicleWeapons(v, dt) }
	}

	/// Fuel tanks that burst last frame go off now
	func flushVehicleBlasts() {
		if vehBlasts.isEmpty { return }
		let list: [(Double, Double)] = vehBlasts
		vehBlasts.removeAll()
		for b in list { explode(b.0, b.1, radius: 2.0, power: 14, source: .environment, breakBlocks: false) }
	}

	/// Rotor blades sweep a line two cells either side of the hub; if they cut into the ground the
	/// rotor is wrecked in a moment
	func rotorBlades(_ v: Vehicle, _ dt: Double) {
		if v.collective < 0.05 && v.propRot == 0 { return }
		if !(airPower(v).1 > 0) { return }
		var struck: PartCell? = nil
		for (c, t) in v.parts where t == .rotor {
			var k: Double = -2.4
			while k <= 2.41 {
				let p: (Double, Double) = v.toWorld(Double(c.dx) + 0.5 + k, Double(c.dy) + 0.02)
				if world.solid(Int(floor(p.0)), Int(floor(p.1))) { struck = c; break }
				k += 0.8
			}
			if struck != nil { break }
		}
		guard let c = struck else { v.bladeHit = 0; return }
		v.bladeHit += dt
		let at: (Double, Double) = v.cellCenter(c)
		if Double.random(in: 0...1) < 0.4 { spawnParticles(at.0, at.1 - 0.5, 0xFFE080, 2, 4.0, 0.25, 8) }
		damageVehicle(v, c, 40.0 * dt, at.0, at.1)
	}

	// MARK: damage

	/// A hard landing or a crash: each part that hit the ground too fast takes damage by how much too fast
	func crashDamage(_ v: Vehicle, _ crash: [PartCell: Double]) {
		if !settings.vehicleDamage { return }
		var worst: Double = 0
		for (c, over) in crash where v.parts[c] != nil {
			let at: (Double, Double) = v.cellCenter(c)
			damageVehicle(v, c, over * 3.2 * (1.0 + v.mass / 30.0), at.0, at.1)
			worst = max(worst, over)
		}
		if worst > 0 {
			addShake(min(0.8, 0.2 + worst * 0.05))
			sfx(.land, at: v.px, 0.9)
		}
	}

	/// Damage to one cell; when it has taken all it can, it breaks off
	func damageVehicle(_ v: Vehicle, _ c: PartCell, _ amount: Double, _ x: Double, _ y: Double) {
		guard let t = v.parts[c], amount > 0 else { return }
		if !settings.vehicleDamage { return }
		let hp: Double = vehicleCellHP(v, c, t) * (v.boost[c] ?? 1.0)
		let d: Double = (v.dmg[c] ?? 0) + amount
		v.dmg[c] = d
		v.hitT = 0.15
		if d >= hp { breakVehicleCell(v, c) }
	}

	/// A cell breaks off: it flies off as debris (a block keeps flying as a falling block), whatever is no
	/// longer joined to the driver's part becomes a wreck of its own, falling with its own physics, and a
	/// burst fuel tank goes off
	func breakVehicleCell(_ v: Vehicle, _ c: PartCell) {
		guard let t = v.parts[c] else { return }
		let at: (Double, Double) = v.cellCenter(c)
		let pv: (Double, Double) = (v.vx - v.angVel * (at.1 - v.py), v.vy + v.angVel * (at.0 - v.px))
		let color: UInt32 = v.blocks[c].map { $0.def.colors.first ?? 0x8A8A8A } ?? 0x8A8A94
		spawnParticles(at.0, at.1, color, 10, 4.5, 0.6, 14)
		spawnParticles(at.0, at.1, 0x5A5A5A, 6, 2.5, 0.9, -2)
		sfx(v.blocks[c] != nil && toolClass(v.blocks[c]!) == .axe ? .breakWood : .breakStone, at: at.0, 0.9)
		addShake(0.2)
		if t == .fuelTank && (v.fuel > 4 || isCreative) { vehBlasts.append(at) }
		if t == .envelope { spawnParticles(at.0, at.1, 0xF0E4D0, 6, 5.0, 0.4, 4) }
		// what the stores carried spills out of every store that comes away
		let stores: [(PartCell, (Double, Double))] = v.parts.keys.filter { vehicleStores(v, $0) }.map { ($0, v.cellCenter($0)) }
		let seat: PartCell? = seatCell(v)
		let wasDriver: Bool = v.rider && inVehicle === v
		// the transform before anything changes: the wrecks keep their place in the world
		let old: Vehicle = v
		var off: [VCell] = old.cutAway(c, keep: seat == c ? nil : seat)
		if let first = off.first, first.cell == c {
			off.removeFirst()
			if let b = first.tile, b.solid, fallingBlocks.count < 120 {
				var fb: FallingBlock = FallingBlock(x: at.0, y: at.1 + 0.5, vy: pv.1 - 3.0, tile: b, uid: newID())
				fb.vx = pv.0 + Double.random(in: -2...2)
				fb.mass = max(0.2, tileWeight(b))
				fb.spin = Double.random(in: -6...6)
				fb.flung = true
				fallingBlocks.append(fb)
			} else if Double.random(in: 0...1) < 0.35 {
				spawnDrop(Stack(item: vehicleCellItem(first), count: 1), at.0, at.1, pv.0 * 0.5, -4)
			}
		}
		if !off.isEmpty { makeWrecks(old, off) }
		for (sc, sp) in stores where v.parts[sc] == nil {
			let k: IntPair = cargoSpot(v, sc)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { spawnDrop(st, sp.0, sp.1, Double.random(in: -2...2), -3.5) }
		}
		if v.parts.isEmpty {
			if wasDriver { dismount() }
			return
		}
		v.recompute(keepAnchor: true)
		v.kit = -1
		if wasDriver && (seatCell(v) == nil || !v.hasSteering) {
			dismount()
			say("Your seat was shot away!", 2.0)
		}
		bumpHUD()
	}

	/// Pieces broken off a vehicle become wrecks: vehicles of their own (no seat, so nobody drives them)
	/// that keep the place, turn and speed they had
	func makeWrecks(_ from: Vehicle, _ cells: [VCell]) {
		var left: [PartCell: VCell] = [:]
		for r in cells { left[r.cell] = r }
		while let start = left.keys.first {
			var group: [VCell] = []
			var stack: [PartCell] = [start]
			while let cur = stack.popLast() {
				guard let r = left[cur] else { continue }
				left[cur] = nil
				group.append(r)
				let n: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
				for k in n where left[k] != nil { stack.append(k) }
			}
			if vehicles.count >= 40 {
				for r in group {
					let p: (Double, Double) = from.cellCenter(r.cell)
					if Double.random(in: 0...1) < 0.4 { spawnDrop(Stack(item: vehicleCellItem(r), count: 1), p.0, p.1, 0, -3) }
				}
				continue
			}
			let w: Vehicle = Vehicle(id: newID(), first: .frame, x: 0, y: 0)
			w.parts.removeAll()
			for r in group {
				w.parts[r.cell] = r.type
				if let b = r.tile { w.blocks[r.cell] = b }
			}
			w.recompute(keepAnchor: false)
			let p: (Double, Double) = from.toWorld(w.comX, w.comY)
			w.px = p.0
			w.py = p.1
			w.angle = from.angle
			w.vx = from.vx - from.angVel * (p.1 - from.py) + Double.random(in: -1.5...1.5)
			w.vy = from.vy + from.angVel * (p.0 - from.px) - 2.0
			w.angVel = from.angVel + Double.random(in: -1.5...1.5)
			w.updateBox()
			vehicles.append(w)
		}
	}

	/// Blasts damage every part in reach (less further out) and shove the vehicle away
	func blastVehicles(_ x: Double, _ y: Double, radius: Double, power: Double) {
		let list: [Vehicle] = vehicles
		for v in list {
			if v.b.right < x - radius - 1 || v.b.left > x + radius + 1 || v.b.y < y - radius - 1 || v.b.top > y + radius + 1 { continue }
			var hits: [(PartCell, Double)] = []
			for (c, _) in v.parts {
				let p: (Double, Double) = v.cellCenter(c)
				let d: Double = sqrt((p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y))
				if d > radius + 0.5 { continue }
				hits.append((c, power * 1.1 * (1.0 - 0.6 * clampD(d / max(0.5, radius), 0, 1))))
			}
			if hits.isEmpty { continue }
			let dx: Double = v.px - x
			let dy: Double = v.py - y
			let dl: Double = max(0.5, sqrt(dx * dx + dy * dy))
			let push: Double = power * 0.9 * Double(hits.count) / Double(max(1, v.parts.count)) / max(1.0, v.mass * 0.25)
			v.vx += dx / dl * min(14.0, push)
			v.vy += dy / dl * min(14.0, push) - 1.0
			v.asleep = false
			for h in hits where v.parts[h.0] != nil {
				let p: (Double, Double) = v.cellCenter(h.0)
				damageVehicle(v, h.0, h.1, p.0, p.1)
			}
		}
	}

	/// The first vehicle cell a shot's step passes through. Shots from monsters, and from other vehicles'
	/// guns, hit vehicles; the player's own shots pass their vehicles, and a gun never hits its own vehicle.
	func vehicleOnPath(_ p: Projectile, _ nx: Double, _ ny: Double, maxT: Double) -> VehicleHit? {
		let fromVehicle: Bool = p.owner >= 2_000_000
		if p.source.kind == .player && !fromVehicle { return nil }
		var best: VehicleHit? = nil
		var bt: Double = min(1.0, maxT)
		let x0: Double = min(p.x, nx)
		let x1: Double = max(p.x, nx)
		let y0: Double = min(p.y, ny)
		let y1: Double = max(p.y, ny)
		for v in vehicles {
			if fromVehicle && p.owner == 2_000_000 + v.id { continue }
			if x1 < v.b.left || x0 > v.b.right || y1 < v.b.top || y0 > v.b.y { continue }
			let a: (Double, Double) = v.toLocal(p.x, p.y)
			let b: (Double, Double) = v.toLocal(nx, ny)
			let len: Double = sqrt((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1))
			let n: Int = max(1, Int(ceil(len / 0.2)))
			var i: Int = 0
			while i <= n {
				let t: Double = Double(i) / Double(n)
				if t > bt { break }
				let lx: Double = a.0 + (b.0 - a.0) * t
				let ly: Double = a.1 + (b.1 - a.1) * t
				let c: PartCell = PartCell(dx: Int(floor(lx)), dy: Int(floor(ly)))
				if v.parts[c] != nil {
					bt = t
					best = VehicleHit(t: t, v: v, cell: c)
					break
				}
				i += 1
			}
		}
		return best
	}

	/// A shot strikes a vehicle part
	func shotHitsVehicle(_ p: Projectile, _ vh: VehicleHit, _ x: Double, _ y: Double) {
		if p.kind == .shell {
			shellBurst(p, x, y)
			return
		}
		if p.mod >= 0 { modShotLanded(p, x, y, mob: nil, player: false) }
		var amount: Double = p.dmg
		if p.kind == .fireball { amount *= 1.3 }
		if vh.v.parts[vh.cell] == .armor { spawnParticles(x, y, 0xFFE8A0, 4, 4.0, 0.2, 6) } else { spawnParticles(x, y, 0xC8C8C8, 3, 3.0, 0.3, 10) }
		sfx(.arrowHit, at: x, 0.5)
		damageVehicle(vh.v, vh.cell, amount, x, y)
	}

	/// A cannon shell bursts: a small blast that breaks and throws blocks like a bomb's
	func shellBurst(_ p: Projectile, _ x: Double, _ y: Double) {
		// a suit's mini cannon: a small blast that leaves the ground alone
		if p.owner == suitShellOwner {
			explode(x, y, radius: 1.4, power: p.dmg, source: p.source, breakBlocks: false)
			return
		}
		explode(x, y, radius: 2.3, power: p.dmg, source: p.source, breakBlocks: true)
	}

	// MARK: weapons

	/// The guns turn toward where the driver aims (each within its own arc) and fire while the attack
	/// stick is held. Cannons fire shells (one gunpowder each) and kick the vehicle back; machine guns
	/// fire a stream of bullets.
	func runVehicleWeapons(_ v: Vehicle, _ dt: Double) {
		for (c, cd) in v.gunCD where cd > 0 { v.gunCD[c] = cd - dt }
		let driving: Bool = v.rider && inVehicle === v
		let firing: Bool = driving && useHeld && aimValid
		for (c, t) in v.parts where t == .cannon || t == .autoGun {
			let f: (Int, Int) = v.face[c] ?? (1, 0)
			let base: Double = v.angle + atan2(Double(f.1), Double(f.0))
			let o: (Double, Double) = v.cellCenter(c)
			var want: Double = base
			if driving && aimValid { want = atan2(aimY - o.1, aimX - o.0) }
			let rel: Double = clampD(remainder(want - base, 2.0 * Double.pi), -1.4, 1.4)
			let a: Double = base + rel
			let cur: Double = v.aimAng[c] ?? base
			let turn: Double = remainder(a - cur, 2.0 * Double.pi)
			let rate: Double = (t == .cannon ? 3.0 : 6.0) * dt
			let na: Double = cur + clampD(turn, -rate, rate)
			v.aimAng[c] = na
			if firing && (v.gunCD[c] ?? 0) <= 0 && abs(remainder(want - na, 2.0 * Double.pi)) < 0.35 && !v.boxed.contains(c) {
				fireVehicleGun(v, c, t, na, o)
			}
		}
	}

	func fireVehicleGun(_ v: Vehicle, _ c: PartCell, _ t: PartType, _ a: Double, _ o: (Double, Double)) {
		let cannon: Bool = t == .cannon
		if !isCreative {
			let ammo: Item = cannon ? .mat(.gunpowder) : .ammo(.bullet)
			if !inv.remove(ammo, 1) {
				v.gunCD[c] = 1.0
				if vehSayT <= clock {
					vehSayT = clock + 3.0
					say(cannon ? "The cannon needs gunpowder." : "The machine gun needs bullets.", 2.0)
				}
				return
			}
		}
		let k: Double = v.boost[c] ?? 1.0
		let mx: Double = o.0 + cos(a) * 0.9
		let my: Double = o.1 + sin(a) * 0.9
		let speed: Double = cannon ? 34.0 : 44.0
		var p = Projectile(kind: cannon ? .shell : .bullet, x: mx, y: my, vx: cos(a) * speed + v.vx, vy: sin(a) * speed + v.vy, dmg: cannon ? 24 * k : 4.5 * k, fromPlayer: true, gravity: cannon ? 14 : 3)
		p.life = cannon ? 4.0 : 1.3
		p.w = cannon ? 0.35 : 0.15
		p.source = .player
		p.owner = 2_000_000 + v.id
		p.uid = newID()
		p.knock = cannon ? 9 : 3
		projectiles.append(p)
		v.gunCD[c] = cannon ? 2.0 : 0.13
		if cannon {
			// the recoil kicks the vehicle back, around the cannon
			let j: Double = 10.0
			let rx: Double = o.0 - v.px
			let ry: Double = o.1 - v.py
			let jx: Double = -cos(a) * j
			let jy: Double = -sin(a) * j
			v.vx += jx / v.mass
			v.vy += jy / v.mass
			v.angVel += (rx * jy - ry * jx) / v.inertia
			v.asleep = false
			spawnParticles(mx, my, 0xFFC050, 8, 5.0, 0.25, 2)
			spawnParticles(mx, my, 0x8A8A8A, 6, 2.0, 0.8, -3)
			addShake(0.25)
			sfx(.blunderbuss, at: mx, 0.9)
		} else {
			if Double.random(in: 0...1) < 0.5 { spawnParticles(mx, my, 0xFFE080, 2, 3.0, 0.12, 0) }
			sfx(.gun, at: mx, 0.3)
		}
	}

	/// Where the guns aim with the attack stick held but not pushed: the nearest foe in range and in
	/// sight, led a little for its speed (nil: none, the guns look ahead)
	func vehicleAutoAim(_ v: Vehicle) -> (Double, Double)? {
		var best: Mob? = nil
		var bd: Double = 26.0
		for m in mobsNear(v.px - 26, v.px + 26) where m.hp > 0 && !m.removed && !m.downed && isThreat(m) {
			let d: Double = abs(m.b.x - v.px) + abs(m.b.cy - v.py) * 0.7
			if d < bd && world.lineClear(v.px, v.py, m.b.x, m.b.cy) {
				bd = d
				best = m
			}
		}
		guard let m = best else { return nil }
		let lead: Double = bd / 40.0
		return (m.b.x + m.b.vx * lead, m.b.cy + m.b.vy * lead)
	}

	// MARK: repairs and storage

	/// Holding an iron bar, a tap on a damaged part mends it (the bar is used up)
	func repairVehiclePart(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let it = heldItem, it == .mat(.ironBar), let d = v.dmg[c], d > 0.5 else { return false }
		v.dmg[c] = nil
		if !isCreative { inv.removeAt(sel, 1) }
		let p: (Double, Double) = v.cellCenter(c)
		spawnParticles(p.0, p.1, 0xFFE8A0, 6, 2.5, 0.4, 4)
		sfx(.craft, at: p.0, 0.6)
		say("Mended.", 1.0)
		bumpHUD()
		return true
	}

	/// Cells that hold things: cargo crates, and chests, cabinets, wardrobes or a mod's storage built on
	func vehicleStores(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let t = v.parts[c] else { return false }
		if t == .cargo { return true }
		guard t == .block, let b = v.blocks[c] else { return false }
		if b == .chest || b == .cabinet || b == .wardrobe { return true }
		if b.isMod, ModRuntime.shared.blockDef(b)?.function == .storage { return true }
		return false
	}

	/// Puts a whole stack (infusions and all) in the bag, dropping what does not fit
	func giveStack(_ st: Stack) {
		let left: Int = inv.add(st.item, st.count, extra: st.extra, inf: st.inf)
		if left > 0 {
			var rest: Stack = st
			rest.count = left
			spawnDrop(rest, pb.x, pb.y - 1.0, Double(facing) * 3.0, -4.0)
		}
		bumpHUD()
	}

	/// What the controls do in this vehicle (said when getting in)
	func controlsHint(_ v: Vehicle) -> String {
		if v.ballasts > 0 && v.wings == 0 && v.rotors == 0 { return "Under way. Stick down floods the ballast tanks to dive, up blows them to rise; left and right: the propeller." }
		if v.rotors > 0 { return "Flying. Stick up and down: climb and sink (let go to hover). Left and right: tilt and fly that way." }
		if v.burners > 0 && v.envelopes > 0 { return "Ballooning. Stick up: heat the balloon and rise; down: let it cool and sink. Left and right: the propellers." }
		if v.wings > 0 { return "Flying. Left and right: the throttle. Up and down: pitch the nose (gather speed on the ground, then pull up). TURN turns round." }
		if v.tracks > 0 { return "Driving a tracked vehicle: slow, but it climbs anything. Jump to get up from the seat." }
		return "Driving. Hold the stick to move; in the air it tilts the vehicle. Jump to get up from the seat."
	}
}

extension Game {
	// MARK: turning round

	/// TURN is offered while driving: in flight it is a banked turn out of the screen and back; standing
	/// still (or nearly), the vehicle simply faces the other way if it has room
	var canTurnVehicle: Bool {
		guard let v = inVehicle else { return false }
		return v.turnT == 0 && (v.aero || v.speed < 2.0)
	}

	func turnVehicle() {
		guard let v = inVehicle, v.turnT == 0 else { return }
		if !v.joints.isEmpty || v.parentID != 0 {
			say("A machine with joints can't turn round: drive it the other way.", 2.0)
			return
		}
		let flying: Bool = v.aero && v.contacts == 0 && v.submerged <= 0.02 && v.speed > 3.0
		if flying {
			v.turnT = 0.001
			v.turnVX = v.vx
			v.turned = false
			v.asleep = false
			return
		}
		if v.speed > 2.0 {
			say("Slow down to turn round.", 1.5)
			return
		}
		if !mirrorVehicle(v, check: true) { say("No room to turn round here.", 1.8) }
	}

	/// A turn in flight: it banks round out of the screen and back (drawn narrowing to its edge and
	/// widening again), the wings lift a little less while banked, and halfway round it faces and flies
	/// the other way, keeping its airspeed less what the turn costs
	func stepTurn(_ v: Vehicle, _ dt: Double) {
		v.turnT = min(1.0, v.turnT + dt / Aero.turnTime)
		if !v.turned && v.turnT >= 0.5 {
			v.turned = true
			_ = mirrorVehicle(v, check: false)
			v.vx = -v.vx * 0.92
			for o in vehicles where o !== v && o.restOn == v.id { o.vx = v.vx; o.vy = v.vy }
		}
		if v.turnT >= 1.0 { v.turnT = 0 }
	}

	/// Mirrors a vehicle left to right about its centre of mass (it then faces the other way). With
	/// `check`, only if the mirrored vehicle fits where it is. Stores keep what they hold.
	@discardableResult
	func mirrorVehicle(_ v: Vehicle, check: Bool, depth: Int = 0) -> Bool {
		let sx: Int = v.minX + v.maxX
		if check {
			for (c, _) in v.parts {
				let p: (Double, Double) = v.cellCenter(c)
				let mx: Double = 2.0 * v.px - p.0
				if world.boxSolid(mx - 0.4, p.1 - 0.4, mx + 0.4, p.1 + 0.4) { return false }
			}
		}
		var np: [PartCell: PartType] = [:]
		var nb: [PartCell: Tile] = [:]
		var nd: [PartCell: Double] = [:]
		var moved: [(IntPair, [Stack])] = []
		for (c, t) in v.parts {
			let m: PartCell = PartCell(dx: sx - c.dx, dy: c.dy)
			np[m] = t
			if let b = v.blocks[c] { nb[m] = mirroredTile(b) }
			if let d = v.dmg[c] { nd[m] = d }
			if vehicleStores(v, c) {
				let k: IntPair = cargoSpot(v, c)
				if let p = openChest, p == k { openChest = nil }
				moved.append((cargoSpot(v, m), world.removeChest(k.x, k.y)))
			}
		}
		let cx: Double = v.px
		let cy: Double = v.py
		mirrorRiders(v, sx)
		// vehicles resting on it (a plane parked on a carrier) are turned round with it
		let carried: [Vehicle] = depth > 2 ? [] : vehicles.filter { $0 !== v && $0.restOn == v.id }
		let carriedAt: [(Double, Double)] = carried.map { v.toLocal($0.px, $0.py) }
		var nw: [PartCell: UInt8] = [:]
		for (c, k) in v.walls { nw[PartCell(dx: sx - c.dx, dy: c.dy)] = k }
		v.walls = nw
		var ns: [PartCell: PartCell] = [:]
		for (c, m) in v.spanOf { ns[PartCell(dx: sx - c.dx, dy: c.dy)] = PartCell(dx: sx - m.dx, dy: m.dy) }
		v.spanOf = ns
		for i in v.links.indices { v.links[i].cell = PartCell(dx: sx - v.links[i].cell.dx, dy: v.links[i].cell.dy) }
		if let st = v.seatAt { v.seatAt = PartCell(dx: sx - st.dx, dy: st.dy) }
		v.parts = np
		v.blocks = nb
		v.dmg = nd
		v.gunCD.removeAll()
		v.aimAng.removeAll()
		v.drillWork.removeAll()
		v.recompute(keepAnchor: false)
		v.angle = -v.angle
		v.angVel = -v.angVel
		v.px = cx
		v.py = cy
		v.dir = -v.dir
		v.fwd = -v.fwd
		v.kit = -1
		v.asleep = false
		v.updateBox()
		for m in moved { world.setChestItems(m.0.x, m.0.y, m.1) }
		for (i, o) in carried.enumerated() {
			let l: (Double, Double) = carriedAt[i]
			_ = mirrorVehicle(o, check: false, depth: depth + 1)
			let w: (Double, Double) = v.toWorld(Double(sx + 1) - l.0, l.1)
			o.px = w.0
			o.py = w.1
			o.vx = v.vx
			o.vy = v.vy
			o.updateBox()
		}
		return true
	}

	// MARK: building blocks onto vehicles

	/// The ON VEHICLE switch shows while a block is in hand near a vehicle
	var canBuildOnVehicle: Bool {
		guard inVehicle == nil, !dead, let it = heldItem, case .block(let t) = it else { return false }
		if t == .liftCar || t == .sapling || t.isPlant { return false }
		return nearestVehicle(8) != nil
	}

	func toggleVehicleBuild() {
		vehicleBuild.toggle()
		say(vehicleBuild ? "Blocks now go onto the vehicle: tap a green square." : "Blocks go into the world again.", 2.0)
		bumpHUD()
	}

	/// Builds the block in hand onto the vehicle at the aim point (it becomes one of its cells, with its
	/// weight, and moves with it). A mod block made to work as a vehicle part does that part's work.
	func attachBlockToVehicle(_ t: Tile) -> Bool {
		guard let (v, c) = vehicleCellAtAim() else {
			if nearestVehicle(8) == nil { return false }
			if placeCD <= 0 { say("Tap a green square next to the vehicle.", 1.5) }
			placeCD = 0.3
			return true
		}
		var part: PartType = .block
		if t.isMod, let d = ModRuntime.shared.blockDef(t), let p = d.vehRole.part { part = p }
		if let problem = attachProblem(v, c, part) {
			say(problem, 2.0)
			placeCD = 0.3
			return true
		}
		liftIfBuried(v, c)
		v.parts[c] = part
		v.blocks[c] = t
		v.recompute(keepAnchor: true)
		splitJointSections(v)
		v.kit = -1
		if t == .chest || t == .cabinet || t == .wardrobe { world.setChestItems(cargoSpot(v, c).x, cargoSpot(v, c).y, []) }
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		placeCD = 0.16
		swingT = 0.14
		bumpHUD()
		return true
	}

	/// Builds a door onto a vehicle at the aim point: two cells high where the cell above is free (one
	/// otherwise). True when the tap was for a vehicle.
	func attachDoorToVehicle() -> Bool {
		guard let (v, c) = vehicleCellAtAim() else { return nearestVehicle(8) != nil }
		if placeCD > 0 { return true }
		placeCD = 0.25
		if let problem = attachProblem(v, c, .block) {
			say(problem, 2.0)
			return true
		}
		v.parts[c] = .block
		v.blocks[c] = .doorClosed
		let up: PartCell = PartCell(dx: c.dx, dy: c.dy - 1)
		let down: PartCell = PartCell(dx: c.dx, dy: c.dy + 1)
		if v.parts[up] == nil { v.parts[up] = .block; v.blocks[up] = .doorClosed }
		else if v.parts[down] == nil { v.parts[down] = .block; v.blocks[down] = .doorClosed }
		v.recompute(keepAnchor: true)
		v.kit = -1
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		swingT = 0.14
		bumpHUD()
		return true
	}

	/// The free cell next to a vehicle under the aim point (the one a block or part would go in)
	func vehicleCellAtAim() -> (Vehicle, PartCell)? {
		for v in vehicles {
			if aimX < v.b.left - 1.5 || aimX > v.b.right + 1.5 || aimY < v.b.top - 1.5 || aimY > v.b.y + 1.5 { continue }
			let c: PartCell = v.cellAt(aimX, aimY)
			if v.parts[c] == nil && v.hasNeighbor(c) { return (v, c) }
		}
		return nil
	}

	// MARK: the assembler

	/// The Vehicle Assembler: a tap on a structure you built turns it (every built block joined to it)
	/// into a vehicle, joined to a vehicle it touches if there is one; a tap on a parked vehicle puts its
	/// blocks back into the world and its parts in your bag
	func useAssembler(_ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		useCD = 0.4
		swingT = 0.15
		if !inReach(aimX, aimY) {
			say("Tap closer to you.", 1.2)
			return
		}
		if let hit = vehicleAtPoint(aimX, aimY) {
			disassembleVehicle(hit.0)
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if !world.isBuilt(tx, ty) || !canAssemble(world.tile(tx, ty)) {
			say("Tap a block you built: it and every built block joined to it become one vehicle.", 3.0)
			return
		}
		assembleStructure(tx, ty)
	}

	/// The built blocks joined to (x, y), side by side (up to 800)
	func builtStructure(_ x: Int, _ y: Int) -> [IntPair] {
		var out: [IntPair] = []
		var seen: Set<IntPair> = []
		var stack: [IntPair] = [IntPair(x: x, y: y)]
		while let p = stack.popLast() {
			if seen.contains(p) { continue }
			seen.insert(p)
			if !world.isBuilt(p.x, p.y) || !canAssemble(world.tile(p.x, p.y)) { continue }
			out.append(p)
			if out.count >= 800 { break }
			stack.append(IntPair(x: p.x + 1, y: p.y))
			stack.append(IntPair(x: p.x - 1, y: p.y))
			stack.append(IntPair(x: p.x, y: p.y + 1))
			stack.append(IntPair(x: p.x, y: p.y - 1))
		}
		return out
	}

	func assembleStructure(_ x: Int, _ y: Int) {
		let cells: [IntPair] = builtStructure(x, y)
		if cells.isEmpty { return }
		if cells.count >= 800 {
			say("That structure is too big to move (800 blocks at most).", 2.5)
			return
		}
		// a vehicle the structure touches takes it in (it must be roughly level)
		var host: Vehicle? = nil
		for v in vehicles where abs(remainder(v.angle, 2.0 * Double.pi)) < 0.08 && !v.rider {
			for p in cells {
				let c: PartCell = v.cellAt(Double(p.x) + 0.5, Double(p.y) + 0.5)
				if v.parts[c] == nil && v.hasNeighbor(c) { host = v; break }
			}
			if host != nil { break }
		}
		var x0: Int = Int.max
		var y1: Int = Int.min
		for p in cells { x0 = min(x0, p.x); y1 = max(y1, p.y) }
		let v: Vehicle = host ?? Vehicle(id: newID(), first: .frame, x: 0, y: 0)
		if host == nil { v.parts.removeAll() }
		var stores: [(PartCell, [Stack])] = []
		var added: Int = 0
		for p in cells {
			let t: Tile = world.tile(p.x, p.y)
			let c: PartCell = host != nil ? v.cellAt(Double(p.x) + 0.5, Double(p.y) + 0.5) : PartCell(dx: p.x - x0, dy: p.y - y1)
			if v.parts[c] != nil {
				// no cell free for it in the vehicle: it goes to the bag (with what it held)
				giveItem(.block(t), 1)
				if t == .chest || t == .cabinet || t == .wardrobe { for st in world.removeChest(p.x, p.y) { giveStack(st) } }
				continue
			}
			var part: PartType = .block
			if t.isMod, let d = ModRuntime.shared.blockDef(t), let pp = d.vehRole.part { part = pp }
			v.parts[c] = part
			v.blocks[c] = t
			added += 1
			if t == .chest || t == .cabinet || t == .wardrobe || (t.isMod && ModRuntime.shared.blockDef(t)?.function == .storage) {
				stores.append((c, world.removeChest(p.x, p.y)))
			}
		}
		// the back walls of the structure go with it: behind its blocks, and behind the open cells
		// inside it (between its blocks in the same row)
		var inBlocks: Set<IntPair> = Set(cells)
		var walls: [(PartCell, UInt8)] = []
		var rows: [Int: (Int, Int)] = [:]
		for p in cells { let r: (Int, Int) = rows[p.y] ?? (p.x, p.x); rows[p.y] = (min(r.0, p.x), max(r.1, p.x)) }
		for (y, span) in rows {
			var x: Int = span.0
			while x <= span.1 {
				let k: Int = world.wallAt(x, y)
				let here: IntPair = IntPair(x: x, y: y)
				if k > 0 && (inBlocks.contains(here) || world.tile(x, y) == .air) {
					let c: PartCell = host != nil ? v.cellAt(Double(x) + 0.5, Double(y) + 0.5) : PartCell(dx: x - x0, dy: y - y1)
					if v.walls[c] == nil {
						walls.append((c, UInt8(k)))
						_ = world.setWall(x, y, 0)
					}
				}
				x += 1
			}
		}
		inBlocks.removeAll()
		for w in walls { v.walls[w.0] = w.1 }
		for p in cells {
			world.setBuilt(p.x, p.y, false)
			world.set(p.x, p.y, .air)
		}
		if host == nil {
			v.recompute(keepAnchor: false)
			v.placeBox(left: Double(x0), bottom: Double(y1 + 1))
			vehicles.append(v)
		} else {
			v.recompute(keepAnchor: true)
		}
		v.kit = -1
		v.asleep = false
		for s in stores { world.setChestItems(cargoSpot(v, s.0).x, cargoSpot(v, s.0).y, s.1) }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0x30C0E0, 14, 4.0, 0.6, 2)
		sfx(.craft, 0.8)
		let massS: String = String(format: "%.0f", v.mass)
		let what: String = host == nil ? "a new vehicle" : "the vehicle"
		say(joinText("Assembled ", String(added), " blocks into ", what, " (mass ", massS, "). ", vehicleCheck(v).hint), 4.0)
		bumpHUD()
	}

	/// Puts a parked, level vehicle's blocks back into the world, each in the cell it is over (blocks
	/// that have no room go to the bag, as do the parts); stores keep their things as chests
	func disassembleVehicle(_ v: Vehicle) {
		if v.rider || v.speed > 1.0 || !v.upright {
			say("Park it level and get out first.", 2.0)
			return
		}
		var placed: Int = 0
		var bagged: Int = 0
		for (c, t) in v.parts {
			let p: (Double, Double) = v.cellCenter(c)
			let tx: Int = Int(floor(p.0))
			let ty: Int = Int(floor(p.1))
			var held: [Stack] = []
			if vehicleStores(v, c) {
				let k: IntPair = cargoSpot(v, c)
				if let o = openChest, o == k { openChest = nil }
				held = world.removeChest(k.x, k.y)
			}
			let here: Tile = world.tile(tx, ty)
			let free: Bool = here == .air || here.liquid || here.isPlant
			if let b = v.blocks[c], free {
				world.set(tx, ty, b)
				world.setBuilt(tx, ty, true)
				if b == .chest || b == .cabinet || b == .wardrobe || (b.isMod && ModRuntime.shared.blockDef(b)?.function == .storage) {
					world.setChestItems(tx, ty, held)
					held = []
				}
				placed += 1
			} else {
				giveItem(vehicleCellItem(VCell(cell: c, type: t, tile: v.blocks[c])), 1)
				bagged += 1
			}
			for st in held { giveStack(st) }
		}
		// its back walls go back up where there is none (or to the bag)
		for (c, k) in v.walls {
			let p: (Double, Double) = v.cellCenter(c)
			let tx: Int = Int(floor(p.0))
			let ty: Int = Int(floor(p.1))
			if world.wallAt(tx, ty) == 0 && world.setWall(tx, ty, Int(k)) { continue }
			if let t = blockWallTile(Int(k)) { giveItem(.block(t), 1) }
		}
		vehicles.removeAll { $0 === v }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0x30C0E0, 14, 4.0, 0.6, 2)
		sfx(.craft, 0.8)
		say(joinText("Taken apart: ", String(placed), " blocks back in place, ", String(bagged), " to your bag."), 3.0)
		bumpHUD()
	}

	// MARK: the autopilot

	/// AUTO cycles the autopilot: off, cruise (it holds the speed and the height you had), route (it
	/// drives the points you marked, round and round, even with nobody aboard)
	func cycleAutopilot() {
		guard let v = inVehicle, v.autopilots > 0 else { return }
		var next: Int = (v.auto + 1) % 3
		if next == 2 && v.route.count < 2 { next = 0 }
		v.auto = next
		v.holdThr = abs(v.throttle) > 0.1 ? v.throttle : (abs(v.vx) > 1.5 ? (v.vx > 0 ? 0.7 : -0.7) : 0)
		v.holdY = v.py
		v.holdVX = v.vx
		if next == 2 { v.routeAt = nearestWaypoint(v) }
		let names: [String] = ["Autopilot off.", "Autopilot: cruise. It holds your speed and height, even if you get up and walk about.", "Autopilot: route. It drives your marked points round and round, even if you get out."]
		say(names[next], 3.0)
		bumpHUD()
	}

	/// MARK adds where the vehicle is now to its route (up to 16 points)
	func markWaypoint() {
		guard let v = inVehicle, v.autopilots > 0 else { return }
		if v.route.count >= 16 { v.route.removeFirst() }
		v.route.append(VWaypoint(x: v.px, y: v.py))
		let n: Int = v.route.count
		say(n < 2 ? "Point 1 marked. Drive on and mark more." : joinText("Point ", String(n), " marked. AUTO twice to drive the route."), 2.0)
		bumpHUD()
	}

	func clearRoute() {
		guard let v = inVehicle else { return }
		v.route.removeAll()
		if v.auto == 2 { v.auto = 0 }
		say("Route cleared.", 1.5)
		bumpHUD()
	}

	func nearestWaypoint(_ v: Vehicle) -> Int {
		var best: Int = 0
		var bd: Double = 1e18
		for (i, w) in v.route.enumerated() {
			let d: Double = (w.x - v.px) * (w.x - v.px) + (w.y - v.py) * (w.y - v.py)
			if d < bd { bd = d; best = i }
		}
		return best
	}

	/// The autopilot's hands on the controls. The driver's own input wins while the stick is pushed
	/// (and cruise then takes up the new speed or height). Cruise holds the throttle, and in the air the
	/// height; a route steers for each point in turn.
	func autopilotSteer(_ v: Vehicle, _ ix: Double, _ up: Double, _ dt: Double) {
		if v.autopilots == 0 { v.auto = 0; return }
		let touched: Bool = abs(ix) > 0.1 || abs(up) > 0.1
		if v.auto == 1 {
			if abs(ix) > 0.1 { v.holdThr = ix } else { v.throttle = v.holdThr }
			if abs(up) > 0.1 { v.holdY = v.py } else if v.aero { v.pitch = holdHeight(v, v.holdY) }
			return
		}
		if v.auto != 2 || v.route.count < 2 { return }
		if touched && v.rider { return }
		if v.routeAt >= v.route.count { v.routeAt = 0 }
		let w: VWaypoint = v.route[v.routeAt]
		let dx: Double = w.x - v.px
		let dy: Double = w.y - v.py
		let flyer: Bool = v.aero && (v.rotors > 0 || v.envelopes > 0 || v.wings > 0)
		let arrived: Bool = abs(dx) < 2.5 && (!flyer || abs(dy) < 3.0)
		if arrived {
			v.routeAt = (v.routeAt + 1) % v.route.count
			return
		}
		if v.wings > 0 && v.rotors == 0 && v.envelopes == 0 {
			// a plane flies on at full throttle and turns round when the point is behind it
			let ahead: Double = dx * Double(v.fwd) * (v.cosA >= 0 ? 1.0 : -1.0)
			if ahead < -6.0 && v.turnT == 0 && v.contacts == 0 && v.speed > 3.0 {
				v.turnT = 0.001
				v.turnVX = v.vx
				v.turned = false
			}
			v.throttle = Double(v.fwd)
			v.pitch = holdHeight(v, w.y)
			return
		}
		let gain: Double = flyer ? 0.15 : 0.35
		var thr: Double = clampD(dx * gain, -1, 1)
		if abs(thr) < 0.35 { thr = thr >= 0 ? 0.35 : -0.35 }
		if flyer && abs(dx) < 6.0 { thr *= abs(dx) / 6.0 }
		v.throttle = thr
		v.pitch = flyer ? holdHeight(v, w.y) : 0
	}

	/// The up/down input that brings the vehicle to a height and holds it there
	func holdHeight(_ v: Vehicle, _ y: Double) -> Double {
		let err: Double = v.py - y
		if v.wings > 0 && v.rotors == 0 && v.envelopes == 0 {
			return clampD(err * 0.12 + v.vy * 0.12, -0.7, 0.7)
		}
		return clampD(err * 0.35 + v.vy * 0.3, -1, 1)
	}
}

extension Game {
	// MARK: what kind of vehicle, and is it ready

	/// What the design is, from what it is built of (a hybrid when it is more than one thing)
	func vehicleKindName(_ v: Vehicle) -> String {
		var kinds: [String] = []
		if v.rotors > 0 { kinds.append("HELICOPTER") }
		if v.envelopes > 0 && v.burners > 0 { kinds.append("AIRSHIP") }
		if v.wings > 0 && v.rotors == 0 { kinds.append(v.airProps + v.jets > 0 ? (v.jets > 0 ? "JET" : "PLANE") : "GLIDER") }
		var hulls: Int = 0
		for (_, t) in v.parts where t == .hull { hulls += 1 }
		if hulls > 0 { kinds.append("BOAT") }
		// on an aircraft, wheels are its landing gear
		let flies: Bool = v.rotors > 0 || v.wings > 0 || (v.envelopes > 0 && v.burners > 0)
		if v.wheels >= 2 {
			if v.tracks > 0 { kinds.append(v.cannons > 0 ? "TANK" : "TRACKED") }
			else if kinds.isEmpty { kinds.append(v.parts.count >= 14 || cargoCount(v) >= 2 ? "TRUCK" : "CAR") }
			else if !flies { kinds.append("WHEELS") }
		}
		if kinds.isEmpty { return v.parts.contains { $0.value == .block } ? "STRUCTURE" : "VEHICLE" }
		if kinds.count == 1 { return kinds[0] }
		return joinText(kinds.prefix(2).joined(separator: " + "), " HYBRID")
	}

	func cargoCount(_ v: Vehicle) -> Int {
		var n: Int = 0
		for c in v.parts.keys where vehicleStores(v, c) { n += 1 }
		return n
	}

	/// The checklist for anything that flies, fights or runs on tracks: what it needs, and whether its
	/// design can do it (lift against weight, a tail behind the centre of mass, power for its rotors)
	func flightCheck(_ v: Vehicle) -> VehicleCheck {
		var lines: [String] = []
		var oks: [Bool] = []
		func add(_ ok: Bool, _ s: String) {
			lines.append(s)
			oks.append(ok)
		}
		let weight: Double = v.mass * gravityG
		let massS: String = String(format: "%.1f", v.mass)
		add(v.hasSeat && v.hasSteering, v.hasCockpit ? "Cockpit" : "Seat and steering wheel (or a cockpit)")
		var hint: String = joinText("Mass ", massS, ". Refuel: hold coal or wood and tap it.")
		if v.rotors > 0 {
			let lift: Double = rotorMax(v, anyway: true) + balloonMax(v)
			let pct: Int = Int((lift / max(1, weight) * 100).rounded())
			add(v.engines > 0, joinText("Engines to turn the rotor (", String(v.engines), ")"))
			add(lift > weight * 1.05, joinText("Rotor lift ", String(pct), "% of the weight"))
			add(v.tailRotors > 0 || v.rotors >= 2, "Tail rotor (or a second main rotor)")
			hint = lift > weight * 1.05 ? joinText("Mass ", massS, ". Stick up to lift off; let go to hover.") : "Too heavy for the rotor: add engines or take weight off."
		} else if v.envelopes > 0 {
			let lift: Double = balloonMax(v)
			let pct: Int = Int((lift / max(1, weight) * 100).rounded())
			let need: Int = (v.envelopes + Aero.burnerCells - 1) / Aero.burnerCells
			add(v.burners >= need, joinText("Burners: ", String(v.burners), " of ", String(need), " (one heats 12 envelopes)"))
			add(lift > weight * 1.05, joinText("Balloon lift ", String(pct), "% of the weight (full heat)"))
			add(v.airProps > 0 && v.engines > 0, "Propeller and engine to move (optional)")
			oks[oks.count - 1] = true
			hint = lift > weight * 1.05 ? joinText("Mass ", massS, ". Stick up to heat the balloon and rise.") : "Not enough balloon for the weight: add envelopes (and burners)."
		} else if v.wings > 0 {
			let takeoff: Double = sqrt(weight / max(0.01, Aero.kLift * Double(v.wings) * 1.15))
			let thrust: Bool = (v.airProps > 0 && v.engines > 0) || v.jets > 0
			add(thrust, "Air propeller with an engine, or a jet")
			add(takeoff < 20.0, joinText("Wings lift it at ", String(Int(takeoff.rounded())), " blocks/s (", String(v.wings), " wing cells)"))
			// the push it has at that speed against its weight: under a fifth, it never gets there
			let push: Double = thrustAt(v, takeoff) / max(1, weight)
			add(push >= 0.2, joinText("Thrust ", String(Int((push * 100).rounded())), "% of the weight at take-off (20% needed)"))
			let tail: (Bool, Bool) = tailCheck(v)
			add(tail.0, "Tail elevator, well behind the centre of mass")
			add(tail.1, "Centre of mass ahead of the wings (or it flips)")
			if takeoff >= 20.0 { hint = "The wings are too small for its weight: add wing cells." }
			else if push < 0.2 { hint = "Too heavy for its engines: add engines or a jet, or take weight off." }
			else { hint = "Throttle up along the ground; at speed, stick up to lift off." }
		}
		if v.tracks > 0 || v.cannons + v.guns > 0 {
			if v.rotors == 0 && v.wings == 0 && v.envelopes == 0 {
				add(v.wheels >= 2, joinText("Tracks or wheels under the hull (", String(v.wheels), ")"))
				add(v.engines > 0, "Engine")
			}
			if v.cannons + v.guns > 0 {
				let ammo: Bool = isCreative || (v.cannons == 0 || inv.total(.mat(.gunpowder)) > 0) && (v.guns == 0 || inv.total(.ammo(.bullet)) > 0)
				add(ammo, v.cannons > 0 ? "Gunpowder in your bag (cannon shells)" : "Bullets in your bag (machine gun)")
				if v.rotors == 0 && v.wings == 0 && v.envelopes == 0 { hint = "Drive with the stick; aim and fire with the attack stick." }
			}
		}
		if v.engines > 0 || v.jets > 0 || v.burners > 0 { add(v.fuel > 0.5 || isCreative, fuelLine(v)) }
		var ready: Bool = true
		for o in oks where !o { ready = false }
		return VehicleCheck(title: vehicleKindName(v), lines: lines, oks: oks, ready: ready, hint: hint)
	}

	/// Is there a tail elevator well behind the centre of mass, and is the centre of mass ahead of the
	/// wings' middle (so the plane noses down when slow instead of flipping onto its back)?
	func tailCheck(_ v: Vehicle) -> (Bool, Bool) {
		var wingX: Double = 0
		var n: Int = 0
		var tailX: Double = 0
		var tn: Int = 0
		for (c, t) in v.parts {
			if t == .wing { wingX += Double(c.dx) + 0.5; n += 1 }
			if t == .elevator { tailX += Double(c.dx) + 0.5; tn += 1 }
		}
		if n == 0 { return (tn > 0, true) }
		wingX /= Double(n)
		// the nose: the end the thrust is at, or failing that the end away from the tail
		var front: Double = 1
		if tn > 0 { tailX /= Double(tn); front = tailX < v.comX ? 1 : -1 }
		let tailOK: Bool = tn > 0 && (tailX - v.comX) * front < -1.5
		let balanced: Bool = (v.comX - wingX) * front > -0.6
		return (tailOK, balanced)
	}

	/// The flight instruments shown while flying: speed, height, climb, lift against weight, the
	/// rotor or burner, fuel, and a stall warning
	func flightReadout(_ v: Vehicle) -> [String] {
		var out: [String] = []
		let alt: Int = Int((Double(WorldGen.sea) - v.b.y).rounded())
		let climb: Double = -v.vy
		out.append(joinText("SPD ", String(Int(v.airspeed.rounded())), "  ALT ", String(alt), "  ", climb >= 0 ? "▲" : "▼", String(format: "%.1f", abs(climb))))
		let weight: Double = max(1, v.mass * gravityG)
		let liftPct: Int = Int((v.liftNow / weight * 100).rounded())
		var l2: String = joinText("LIFT ", String(liftPct), "%")
		if v.rotors > 0 { l2 = joinText(l2, "  ROTOR ", String(Int((v.collective * 100).rounded())), "%") }
		if v.burners > 0 && v.envelopes > 0 { l2 = joinText(l2, "  HEAT ", String(Int((v.heat * 100).rounded())), "%") }
		if v.airProps + v.jets > 0 { l2 = joinText(l2, "  THR ", String(Int((abs(v.throttle) * 100).rounded())), "%") }
		out.append(l2)
		if v.engines + v.jets + v.burners > 0 && !isCreative { out.append(joinText("FUEL ", String(Int(v.fuel)), "/", String(Int(v.fuelCapacity)))) }
		if v.stall { out.append("STALL!") }
		return out
	}

	/// A line about the guns (reload) and the autopilot, while driving
	func vehicleStatusLine(_ v: Vehicle) -> String? {
		var parts: [String] = []
		if v.ballasts > 0 { parts.append(joinText("BALLAST ", String(Int((v.ballast * 100).rounded())), "%")) }
		if v.airBrakes > 0 && v.brakeOpen > 0.5 { parts.append("AIR BRAKES") }
		if v.cannons > 0 {
			var cd: Double = 0
			for (c, t) in v.parts where t == .cannon { cd = max(cd, v.gunCD[c] ?? 0) }
			parts.append(cd > 0.05 ? joinText("CANNON ", String(format: "%.1f", cd), "s") : "CANNON READY")
		}
		if v.autopilots > 0 {
			let modes: [String] = ["AUTO OFF", "AUTO CRUISE", "AUTO ROUTE"]
			var s: String = modes[max(0, min(2, v.auto))]
			if v.auto == 2 { s = joinText(s, " ", String(v.routeAt + 1), "/", String(v.route.count)) }
			else if !v.route.isEmpty { s = joinText(s, " · ", String(v.route.count), " PTS") }
			parts.append(s)
		}
		return parts.isEmpty ? nil : parts.joined(separator: "  ")
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
	default: return t.isMod ? ModRuntime.shared.powerRoleOf(t).role : .none
	}
}

/// The two forms of a device (a lamp lit or dark, a gate open or shut) are the same device
func powerFamily(_ t: Tile) -> Tile {
	switch t {
	case .lampOn: return .lampOff
	case .gateOpen: return .gateClosed
	default:
		// a mod lamp lit is the same device as unlit
		if t.isMod && ModRuntime.shared.isAlt(t), let p = ModRuntime.shared.partner(t) { return p }
		return t
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
		default: return modBattery(t) * 150
		}
	}
	static func rate(_ t: Tile) -> Double {
		switch t {
		case .battery: return 15
		case .accumulator: return 60
		default: return modBattery(t) * 2.5
		}
	}
	/// a mod battery's strength (0 for anything else)
	static func modBattery(_ t: Tile) -> Double {
		if !t.isMod || ModRuntime.shared.powerRoleOf(t) != .battery { return 0 }
		return ModRuntime.shared.blockDef(t)?.powerAmt ?? 0
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
		default:
			if t.isMod && ModRuntime.shared.powerRoleOf(t) == .lamp { return ModRuntime.shared.blockDef(t)?.powerAmt ?? 0 }
			return 0
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
			return modGeneratorRate(d)
		}
	}

	/// Sparks a second a mod's generator makes: steadily, or by daylight under the open sky
	func modGeneratorRate(_ d: PowerDev) -> Double {
		if !d.tile.isMod { return 0 }
		let role: ModPowerRole = ModRuntime.shared.powerRoleOf(d.tile)
		let amt: Double = ModRuntime.shared.blockDef(d.tile)?.powerAmt ?? 0
		if role == .generator { return amt }
		if role != .solar { return 0 }
		// open sky above it (the block itself may be the highest thing in its column)
		if d.y > world.skyTop(d.x) { return 0 }
		let cloud: Double = settings.weatherOn && world.dim == .overworld ? weatherAt(Double(d.x) + 0.5, Double(d.y)).cloud : 0
		return amt * dayFactor * (1.0 - 0.75 * clampD(cloud, 0, 1))
	}

	/// A mod's powered lamp or signal light: its lit form while it has power (and its pulse wire is on,
	/// if it has one), or while its pulse wire is on. False for anything else.
	func modPowerLamp(_ d: PowerDev, _ pulse: Bool?) -> Bool {
		if !d.tile.isMod { return false }
		let role: ModPowerRole = ModRuntime.shared.powerRoleOf(d.tile)
		if role != .lamp && role != .signal { return false }
		d.enabled = pulse ?? true
		let lit: Bool = role == .lamp ? (d.enabled && d.powered) : (pulse ?? false)
		let rt: ModRuntime = ModRuntime.shared
		guard let other = rt.partner(d.tile) else { return true }
		if lit != rt.isAlt(d.tile) && clock - d.lastSwap > 0.12 && power.swaps > 0 {
			power.swaps -= 1
			d.lastSwap = clock
			world.set(d.x, d.y, other)
		}
		return true
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
			if modPowerLamp(d, pulse) { return }
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
			if d.tile == .lampOff || d.tile == .lampOn || d.tile == .gateClosed || d.tile == .gateOpen || d.tile.isMod { applyMachine(d) }
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
		// a block's worth of water a stroke, from the nearest cells first (the water flows, so a
		// part-full cell counts by what it holds)
		var cells: [(Int, IntPair)] = []
		for dy in -4...4 {
			for dx in -4...4 {
				let x: Int = d.x + dx
				let y: Int = d.y + dy
				if world.tile(x, y) != .water { continue }
				cells.append((abs(dx) + abs(dy), IntPair(x: x, y: y)))
			}
		}
		if cells.isEmpty { return }
		cells.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1.y < $1.1.y) }
		var want: Int = 255
		for c in cells where want > 0 {
			let have: Int = world.liquidLevel(c.1.x, c.1.y)
			let take: Int = min(have, want)
			world.setLiquidLevel(c.1.x, c.1.y, .water, have - take)
			want -= take
		}
		let w: IntPair = cells[0].1
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
