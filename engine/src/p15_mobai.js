// What creatures do (the Swift game's p15a_mobai, p15b_spawn and the animal life and newer creatures
// from u01_art): moving, wandering, fleeing, chasing; every monster's senses and plan (`think`); each
// kind's attacks; animals that graze, drink, herd and hunt; pets; and where and when creatures appear.

const SPAWN_GLOW_MAX = 4;
const NATURAL_GROUND = new Set([T.grass, T.dirt, T.stone, T.sand, T.snow, T.ice, T.sandstone, T.mud, T.dryGrass, T.jungleGrass, T.mossGrass, T.slate, T.deepRock, T.obsidian, T.ashStone, T.farmland, T.coal, T.copper, T.iron, T.tin, T.saltpeter].filter((t) => t !== undefined));

Object.assign(Game.prototype, {
	accelX(m, target, a, dt) {
		const d = target - m.b.vx, s = a * dt;
		if (d > s) m.b.vx += s; else if (d < -s) m.b.vx -= s; else m.b.vx = target;
	},
	stepMob(m, dt, stepUp = 1) {
		const d = m.def, b = m.b;
		if (d.flying) { /* their AI sets vy */ }
		else if (b.inWater) {
			b.vy = clampD(b.vy + 12 * dt, -5, 5);
			if (m.hp > 0 && d.behavior !== "swimmer") b.vy -= 26 * dt;
		} else b.vy = Math.min(b.vy + gravityG() * dt, terminalV);
		if (m.knock > 0) m.knock -= dt;
		if (m.leapReq) {
			m.leapReq = false;
			if (b.onGround && !d.flying) { b.vy = -d.jump * 1.22; b.vx = (m.aimX >= b.x ? 1 : -1) * Math.max(2.5, d.speed); m.leapT = 1.6; }
		}
		const sm = mobSpeedMul(m);
		if (sm < 0.999) { b.vx *= sm; if (d.flying) b.vy *= sm; }
		this.world.moveBody(b, dt, d.flying ? 0 : stepUp, false, null);
		if (sm < 0.999) { b.vx /= sm; if (d.flying) b.vy /= sm; }
		m.anim += b.onGround ? Math.abs(b.vx) * dt * 0.8 : dt * 0.5;
	},
	cliffAhead(m, dir) {
		const fx = Math.floor(m.b.x + dir * (m.b.w * 0.5 + 0.6)), fy = Math.floor(m.b.y + 0.2);
		for (let d = 0; d < 5; d++) { const t = this.world.tile(fx, fy + d); if (SOLID[t] || t === T.platform || LIQUID[t]) return false; }
		return true;
	},
	wander(m, dt, k) {
		m.t1 -= dt;
		if (m.t1 <= 0) {
			if (m.st === 0) {
				m.st = 1; m.dir = Math.random() < 0.5 ? 1 : -1;
				if (Math.abs(m.b.x - m.homeX) > 24) m.dir = m.b.x > m.homeX ? -1 : 1;
				m.t1 = rand(1.5, 4.5);
			} else { m.st = 0; m.t1 = rand(1, 4); }
		}
		if (m.st === 1) {
			if (this.cliffAhead(m, m.dir) || (m.b.hitWall && !m.b.onGround)) m.dir = -m.dir;
			if (m.b.hitWall && m.b.onGround) m.dir = -m.dir;
			this.accelX(m, m.dir * m.def.speed * k, 14, dt);
		} else this.accelX(m, 0, 18, dt);
	},
	flee(m, fromX, dt, k) {
		const dx = m.b.x >= fromX ? 1 : -1;
		m.dir = dx;
		this.accelX(m, dx * m.def.speed * k, 30, dt);
		if (m.b.hitWall && m.b.onGround) m.b.vy = -m.def.jump;
	},
	chase(m, tx, k, dt) {
		const dx = tx >= m.b.x ? 1 : -1;
		if (Math.abs(tx - m.b.x) > 0.35) { m.dir = dx; this.accelX(m, dx * m.def.speed * k, 26, dt); }
		else this.accelX(m, 0, 30, dt);
		if (m.b.hitWall && m.b.onGround) m.b.vy = -m.def.jump;
		if (m.b.inWater) m.b.vy -= 18 * dt;
	},
	/** touching: across, and anything from overlapping to standing on the player's head */
	contactHurt(m, dmg) {
		if (m.cd > 0 || this.dead) return;
		const pb = this.pb;
		if (bodyRight(pb) > bodyLeft(m.b) + 0.05 && bodyLeft(pb) < bodyRight(m.b) - 0.05 && pb.y > bodyTop(m.b) - 0.2 && bodyTop(pb) < m.b.y + 0.2) {
			const info = dinfo(dmg, "contact", srcMob(this, m));
			info.knock = 6.5; info.originX = m.b.x;
			if (this.hurtPlayer(info)) { m.cd = 0.9; m.atkT = MOB_ATK; }
		}
	},
	/** a creature's swing: hits the player and creatures of other sides in the reach box */
	mobStrike(m, reach, height, dmg, knock) {
		m.atkT = MOB_ATK;
		const k = Math.max(1, m.mutSize);
		reach *= k; height *= k;
		const x0 = m.dir > 0 ? m.b.x - 0.3 : m.b.x - reach - 0.3, x1 = m.dir > 0 ? m.b.x + reach + 0.3 : m.b.x + 0.3;
		const info = dinfo(dmg, "melee", srcMob(this, m));
		info.dirX = m.dir; info.knock = knock; info.originX = m.b.x; info.key = newAttackKey();
		this.damageBox(x0, m.b.y - height, x1, m.b.y + 0.1, info);
	},
	updateMobs(dt) {
		const t0 = performance.now(), px = this.pb.x, py = this.pb.y;
		const offScreen = this.viewTilesW * 0.5 + 6;
		this.frameNo = (this.frameNo || 0) + 1;
		this.rebuildMobGrid();
		for (let i = 0; i < this.mobs.length; i++) {
			const m = this.mobs[i];
			if (m.hp <= 0 || m.removed) continue;
			const dx = Math.abs(m.b.x - px), dy = Math.abs(m.b.y - py);
			const boss = isBossMob(m);
			if (!m.persistent && !m.tame && !boss && (dx > 115 || dy > 85)) { m.removed = true; continue; }
			if (m.def.hostile && !m.persistent && !m.tame && !boss && m.lair === 0) {
				if ((dx > offScreen || dy > 40) && m.ai !== "chase") {
					m.farT += dt;
					if (m.farT > ((m.hunter && !this.isNight) ? 4 : 40)) { m.removed = true; continue; }
				} else m.farT = 0;
			}
			if (m.hurtT > 0) m.hurtT -= dt;
			if (m.cd > 0) m.cd -= dt;
			if (m.flash > 0) m.flash -= dt;
			if (m.lean !== 0) { m.lean *= 1 - Math.min(1, dt * 7); if (Math.abs(m.lean) < 0.01) m.lean = 0; }
			if (m.atkT > 0) m.atkT -= dt;
			if (m.turnT > 0) { m.turnT -= dt; if (m.turnT <= 0) { m.turnT = 0; m.face = m.dir; } }
			else if (m.face !== m.dir) { if (m.face === 0) m.face = m.dir; else m.turnT = MOB_TURN; }
			if (m.regrow > 0) { m.regrow -= dt; if (m.regrow <= 0) m.sheared = false; }
			if (!this.world.isLoaded(Math.floor(m.b.x))) continue;
			if (m.dazeGuard > 0) m.dazeGuard -= dt;
			if (m.daze > 0) {
				m.daze -= dt;
				if (m.daze <= 0) { m.daze = 0; m.dazeGuard = 1.2; }
				m.b.vx *= Math.max(0, 1 - dt * 9);
				if (m.def.flying) m.b.vy *= Math.max(0, 1 - dt * 9);
				this.stepMob(m, dt);
				this.mobHazards(m, dt);
				continue;
			}
			if (!boss && !m.tame && (dx > 72 || dy > 56)) continue;
			// mid-distance creatures think at a third of the rate, staggered, with the time folded in
			let step = dt;
			if (!boss && !m.tame && (dx > 40 || dy > 30)) {
				m.aiAccum += dt;
				if ((this.frameNo + m.id) % 3 !== 0) continue;
				step = Math.min(0.1, m.aiAccum);
			}
			m.aiAccum = 0;
			this.updateMob(m, step);
			if (m.hp > 0) this.mobHazards(m, step);
		}
		this.updateDying(dt);
		if (this.mobs.some((m) => m.removed)) this.mobs = this.mobs.filter((m) => !m.removed);
		PERF.aiMs = (PERF.aiMs || 0) * 0.9 + (performance.now() - t0) * 0.1;
	},
	nearestHostileTo(x, y, r) {
		let best = null, bd = r * r;
		for (const o of this.mobsNear(x - r, x + r)) {
			if (o.hp <= 0 || o.tame || !o.def.hostile) continue;
			const d = (o.b.x - x) ** 2 + (mobCY(o) - y) ** 2;
			if (d < bd) { bd = d; best = o; }
		}
		return best;
	},
	updateMob(m, dt) {
		if (mobKindHook(this, m, dt)) return;
		const d = m.def, pb = this.pb;
		const dist = Math.abs(pb.x - m.b.x), dyP = (pb.y - pb.h * 0.5) - mobCY(m);
		const peaceful = this.settings.peaceful;
		if (m.tame) { this.updatePet(m, dt); return; }
		let engaged = dist < d.aggro && Math.abs(dyP) < 14 && !this.dead && !peaceful;
		if (thinks(m.kind)) engaged = this.think(m, dt, dist, dyP);
		switch (m.kind) {
			case "pig": case "cow": case "sheep": case "villager":
				if (m.t2 > 0) { m.t2 -= dt; this.flee(m, m.tx, dt, 1.9); }
				else if (!this.animalLife(m, dt)) this.wander(m, dt, 0.55);
				this.stepMob(m, dt);
				break;
			case "giraffe": case "chicken": case "frog": case "cat": {
				const scared = dist < 6 && !this.dead && m.kind !== "cat";
				if (m.t2 > 0) { m.t2 -= dt; this.flee(m, m.tx, dt, 1.7); }
				else if (!scared && m.kind !== "cat" && this.animalLife(m, dt)) { /* resting, drinking, herding */ }
				else if (scared) this.flee(m, pb.x, dt, 1.4);
				else this.wander(m, dt, 0.5);
				if (m.kind === "frog" && m.b.onGround && m.st === 1 && Math.random() < 0.04) { m.b.vy = -9; m.b.vx = m.dir * 3.5; }
				this.stepMob(m, dt);
				break;
			}
			case "elephant": case "bear": case "wolf":
				if (m.drinkT > 0 && m.kind === "wolf") m.drinkT -= dt;
				if (m.angry) m.preyID = 0;
				if (!m.angry && m.kind === "wolf" && this.hunt(m, dt, this.isNight && m.drinkT <= 0)) { /* a pack running down prey */ }
				else if (m.angry && !this.dead) {
					m.t3 -= dt;
					if (m.t3 <= 0 || dist > 30) m.angry = false;
					else {
						this.chase(m, pb.x, 1, dt);
						if (m.kind === "wolf" && m.b.onGround && dist < 4 && Math.random() < 0.03) { m.b.vy = -12; m.b.vx = m.dir * 7; }
						if (peaceful) m.angry = false; else this.contactHurt(m, d.dmg);
					}
				} else this.wander(m, dt, 0.5);
				this.stepMob(m, dt);
				break;
			case "grizzly": case "polarBear": case "tiger": case "scorpion": {
				if (m.drinkT > 0) m.drinkT -= dt;
				const provoked = this.wildProvoked(m) && !peaceful;
				if (!provoked && m.kind !== "scorpion" && this.hunt(m, dt, m.drinkT <= 0)) { /* hunting */ }
				else if (!provoked) this.wander(m, dt, 0.4);
				else if (!this.dead) {
					this.chase(m, pb.x, 1, dt);
					if (m.kind === "tiger" && m.b.onGround && dist < 6.5 && dist > 2 && m.cd <= 0.4 && Math.random() < 0.04) { m.b.vy = -11.5; m.b.vx = m.dir * 10; m.t3 = 0.6; }
					this.contactHurt(m, d.dmg);
				} else this.wander(m, dt, 0.5);
				this.stepMob(m, dt);
				break;
			}
			case "zombie": this.updateZombie(m, dt, engaged, dyP); break;
			case "skeleton": case "pirate": case "pirateCaptain": this.updateSwordsman(m, dt, engaged, dist, dyP); break;
			case "pirateGunner": case "imp": this.updateShooter(m, dt, engaged, dist, dyP); break;
			case "slime": case "emberSlime": this.updateSlime(m, dt, engaged); break;
			case "crow": case "bat": case "cinderBat": case "wraith": this.updateFlyer(m, dt, engaged, dist); break;
			case "fish": this.updateFish(m, dt); break;
			case "crawler": this.updateCrawler(m, dt, engaged, dist, dyP); break;
			case "golem": this.updateGolem(m, dt, engaged, dist, dyP); break;
			case "archer": this.updateArcher(m, dt, engaged, dist, dyP); break;
			case "mimic": this.updateMimic(m, dt, !peaceful && !this.dead && dist < 20, dist, dyP); break;
			default: this.stepMob(m, dt);
		}
	},

	// ---- hostile minds
	attackReach(m) {
		let r;
		switch (m.kind) {
			case "zombie": r = [1.5, 1.7, false]; break;
			case "skeleton": case "pirate": case "pirateCaptain": r = [2, 1.6, false]; break;
			case "pirateGunner": case "imp": r = [17, 9, true]; break;
			case "archer": r = [18, 10, true]; break;
			case "crawler": r = [4.6, 2, false]; break;
			case "golem": r = [3.3, 2.4, false]; break;
			default: r = [m.b.w * 0.5 + 0.5, 1.4, false];
		}
		if (m.mutSize > 1.001 && !r[2]) { r[0] *= m.mutSize; r[1] *= m.mutSize; }
		return r;
	},
	/** A monster's senses and plan, the same for every kind: it notices the player by sight, by sound up
	 *  close or by being hit; gives chase after a beat; searches where they were last seen when they slip
	 *  away, then goes home. Stuck at a wall it leaps once, then backs off and comes again. Night hunters
	 *  roam toward the player before seeing them. Returns whether it is after the player. */
	think(m, dt, dist, dyP) {
		const d = m.def, pb = this.pb;
		m.aiT += dt;
		if (m.leapT > 0) m.leapT -= dt;
		if (m.hunter && (m.kind === "skeleton" || m.kind === "archer") && this.inSunlight(m)) m.burn = 2;
		if (this.dead || this.settings.peaceful) {
			m.why = this.dead ? "player dead" : "peaceful";
			if (m.ai !== "idle" && m.ai !== "back") { m.ai = "back"; m.aiT = 0; }
			if (m.ai === "back" && (Math.abs(m.b.x - m.homeX) < 2 || m.aiT > 8)) { m.ai = "idle"; m.aiT = 0; }
			m.aimX = m.homeX;
			return false;
		}
		m.losT -= dt;
		if (m.losT <= 0) {
			m.losT = 0.18 + (m.id % 7) * 0.02;
			const ey = m.kind === "golem" ? bodyTop(m.b) - 0.5 : this.shotY(m);
			m.sees = m.kind === "wraith" || this.world.lineClear(m.b.x, ey, pb.x, pb.y - pb.h * 0.6) || this.world.lineClear(m.b.x, ey, pb.x, bodyTop(pb) + 0.2);
		}
		const base = Math.max(d.aggro, 16);
		const sight = base * (m.hunter ? 1.25 : 1) * (m.ai === "chase" ? 1.5 : 1), sense = base * 0.7;
		const hurt = this.clock - m.lastHitByPlayer < 0.6;
		const heard = dist < 3.5 && Math.abs(dyP) < 3;
		const detect = hurt || heard || (dist < sight && Math.abs(dyP) < 12 && m.sees);
		const sensed = dist < sense && Math.abs(dyP) < 10;
		if (detect || sensed) { m.seenX = pb.x; m.seenY = pb.y; m.lostT = 0; } else m.lostT += dt;
		const hunting = m.hunter && this.isNight && this.world.dim === Dimension.overworld && dist < 80;
		switch (m.ai) {
			case "idle": case "back":
				if (detect) { m.ai = hurt ? "chase" : "alert"; m.aiT = 0; }
				else if (sensed) { m.ai = "search"; m.aiT = 0; }
				else if (hunting) { m.ai = "search"; m.aiT = 0; m.seenX = pb.x + rand(-6, 6); m.seenY = pb.y; }
				break;
			case "alert": if (m.aiT > 0.35) { m.ai = "chase"; m.aiT = 0; } break;
			case "chase": if (m.lostT > 2.5) { m.ai = "search"; m.aiT = 0; } break;
			case "search":
				if (detect) { m.ai = "chase"; m.aiT = 0; }
				else if (sensed) m.aiT = 0;
				else if ((Math.abs(m.b.x - m.seenX) < 1.2 && m.aiT > 2) || m.aiT > (hunting ? 14 : 8)) {
					if (hunting) { m.seenX = pb.x + rand(-8, 8); m.seenY = pb.y; m.aiT = 0; }
					else { m.ai = "back"; m.aiT = 0; }
				}
				break;
			case "retreat": if (m.aiT > 2.5) { m.ai = detect ? "chase" : "search"; m.aiT = 0; } break;
		}
		switch (m.ai) {
			case "alert": case "chase": m.aimX = pb.x; break;
			case "search": m.aimX = m.seenX; break;
			case "retreat": m.aimX = m.b.x + (m.b.x >= m.seenX ? 6 : -6); break;
			case "back": m.aimX = m.homeX; break;
			default: m.aimX = m.b.x;
		}
		if (m.ai === "back" && Math.abs(m.b.x - m.homeX) < 2) { m.ai = "idle"; m.aiT = 0; }
		const reach = this.attackReach(m);
		const inReach = dist <= reach[0] && Math.abs(dyP) <= reach[1] && (!reach[2] || m.sees);
		const pushing = (m.ai === "chase" || m.ai === "search") && Math.abs(m.aimX - m.b.x) > 1 && m.st <= 1 && !(m.ai === "chase" && inReach);
		if (pushing) {
			if (Math.abs(m.b.x - m.progX) > 0.6) { m.progX = m.b.x; m.blockedT = Math.max(0, m.blockedT - 0.5); }
			else {
				const ax = Math.floor(m.b.x + m.dir * (m.b.w * 0.5 + 0.3));
				m.blockedT += HURTS[this.world.tile(ax, Math.floor(m.b.y - 0.5))] ? dt * 3 : dt;
			}
			if (!d.flying && m.blockedT > 0.9 && m.leapT <= 0) m.leapReq = true;
			if (m.blockedT > 3.2) { m.ai = "retreat"; m.aiT = 0; m.blockedT = 0; }
		} else if (m.st <= 1) { m.progX = m.b.x; m.blockedT = Math.max(0, m.blockedT - dt * 0.5); }
		if (m.ai === "retreat" || m.blockedT > 0.9) m.why = "path blocked";
		else if (m.ai !== "chase" && m.ai !== "alert") m.why = "hasn't seen you";
		else if (dist > reach[0]) m.why = "out of range";
		else if (Math.abs(dyP) > reach[1]) m.why = "can't reach that height";
		else if (reach[2] && !m.sees) m.why = "no line of sight";
		else if (m.cd > 0) m.why = "cooling down";
		else m.why = "";
		return m.ai !== "idle" && m.ai !== "back";
	},
	/** out in full daylight under the open sky (the undead burn) */
	inSunlight(m) {
		return this.world.dim === Dimension.overworld && this.dayFactor > 0.7 && this.world.isSkyExposed(Math.floor(m.b.x), Math.floor(m.b.y - 1)) && !m.b.inWater && !(this.cloudCover && this.cloudCover() > 0.9);
	},
	updateZombie(m, dt, aggro, dyP) {
		const d = m.def, dist = Math.abs(this.pb.x - m.b.x);
		if (this.inSunlight(m)) m.burn = 2;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 4; m.t3 = 0.25; this.mobStrike(m, 1.2, 1.8, d.dmg, 6.5); }
		} else if (m.st === 4) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 0; m.cd = 0.9; }
		} else if (aggro) {
			this.chase(m, m.aimX, 1, dt);
			if (m.ai === "chase" && (m.sees || dist < 1) && m.cd <= 0 && dist < 1.5 && Math.abs(dyP) < 1.7) { m.st = 3; m.t3 = 0.32; m.dir = this.pb.x >= m.b.x ? 1 : -1; }
		} else this.wander(m, dt, 0.45);
		this.stepMob(m, dt);
	},
	/** the skeleton knight (with a shield), the pirate and the captain (cutlasses) */
	updateSwordsman(m, dt, aggro, dist, dyP) {
		const d = m.def, isSkel = m.kind === "skeleton", pb = this.pb;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 4; m.t3 = 0.22; this.mobStrike(m, 2.2, 1.9, d.dmg, 7); }
		} else if (m.st === 4) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 0; m.cd = m.kind === "pirateCaptain" ? 0.9 : 1.2; }
		} else if (aggro) {
			const sp = dist > 8 ? 1.15 : 0.95;
			const ready = m.ai === "chase" && m.sees && dist < 2 && m.cd <= 0 && Math.abs(dyP) < 1.6;
			if (isSkel) {
				m.blocking = dist > 2.4 && dist < 11 && m.ai === "chase";
				if (ready) { m.st = 3; m.t3 = 0.38; m.blocking = false; m.dir = pb.x >= m.b.x ? 1 : -1; }
				this.chase(m, m.aimX, m.blocking ? 0.7 : sp, dt);
			} else {
				if (ready) { m.st = 3; m.t3 = 0.3; m.dir = pb.x >= m.b.x ? 1 : -1; }
				this.chase(m, m.aimX, sp, dt);
			}
		} else { m.blocking = false; this.wander(m, dt, 0.4); }
		if (m.st === 0 && !aggro) m.blocking = false;
		this.stepMob(m, dt);
	},
	/** the pirate gunner and the imp: keep their range and shoot */
	updateShooter(m, dt, aggro, dist, dyP) {
		const isImp = m.kind === "imp", pb = this.pb;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			m.dir = pb.x >= m.b.x ? 1 : -1;
			if (m.t3 <= 0) {
				if (this.clearShot(m)) { m.st = 6; m.t3 = 0.18; this.shootAtPlayer(m, isImp); }
				else if (m.t3 < -0.8) { m.st = 0; m.cd = 0.4; m.blockedT += 0.6; }
			}
		} else if (m.st === 6) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 0; m.cd = isImp ? 1.9 : 2.2; }
		} else if (aggro) {
			const want = isImp ? 8 : 9;
			if ((m.ai !== "chase" && m.ai !== "alert") || !m.sees || m.blockedT > 0.5 || !m.b.onGround) this.chase(m, m.aimX, 0.9, dt);
			else if (dist < want - 3) this.flee(m, pb.x, dt, 0.8);
			else if (dist > want + 3) this.chase(m, pb.x, 0.9, dt);
			else { this.accelX(m, 0, 20, dt); m.dir = pb.x >= m.b.x ? 1 : -1; }
			if (m.ai === "chase" && m.sees && m.b.onGround && m.cd <= 0 && dist < 17 && Math.abs(dyP) < 9) { m.st = 3; m.t3 = 0.5; }
		} else this.wander(m, dt, 0.4);
		this.stepMob(m, dt);
	},
	shootAtPlayer(m, fire) {
		const ox = m.b.x + m.dir * 0.6, oy = this.shotY(m);
		let dx = this.pb.x - ox, dy = this.shotAimY(m) - oy;
		const len = Math.max(0.001, Math.hypot(dx, dy)); dx /= len; dy /= len;
		const sp = fire ? 11 : 20;
		this.shoot({ kind: fire ? "fireball" : "bullet", x: ox, y: oy, vx: dx * sp, vy: dy * sp, dmg: m.def.dmg, life: 3, owner: m.id, source: srcMob(this, m) });
		this.spawnParticles(ox, oy, fire ? 0xFF7020 : 0xFFE080, 4, 2.5, 0.18, 0);
	},
	updateSlime(m, dt, aggro) {
		const d = m.def;
		m.t1 -= dt;
		if (m.b.onGround) {
			m.b.vx *= 0.8;
			if (m.t1 <= 0) {
				if (aggro) { const dx = m.aimX >= m.b.x ? 1 : -1; m.dir = dx; m.b.vy = -d.jump; m.b.vx = dx * d.speed * 1.6; m.t1 = rand(0.7, 1.3); }
				else { m.dir = Math.random() < 0.5 ? 1 : -1; m.b.vy = -8.5; m.b.vx = m.dir * 2; m.t1 = rand(1.5, 3.5); }
			}
		}
		if (aggro && !m.b.onGround) this.accelX(m, (m.aimX >= m.b.x ? 1 : -1) * d.speed * 1.6, 5, dt);
		if (m.kind === "emberSlime" && Math.random() < 0.1) this.spawnParticles(m.b.x, m.b.y - 0.4, 0xFF8A20, 1, 1.2, 0.4, -3);
		if (aggro && m.ai === "chase") this.contactHurt(m, d.dmg);
		this.stepMob(m, dt);
	},
	updateFlyer(m, dt, aggro, dist) {
		const d = m.def, pb = this.pb;
		m.anim += dt * 8;
		let tx = m.homeX, ty = m.homeY, spd = d.speed * 0.6;
		if (m.kind === "crow") {
			m.t1 -= dt;
			if (m.t1 <= 0) { m.t1 = rand(2, 5); m.tx = m.homeX + rand(-12, 12); m.ty = this.world.surfaceY(Math.floor(m.tx)) - rand(3, 8); }
			tx = m.tx; ty = m.ty;
			if (dist < 5 && !this.dead) { tx = m.b.x + (m.b.x - pb.x) * 3; ty = m.b.y - 6; spd = d.speed * 1.4; }
		} else if (aggro) {
			tx = m.aimX; ty = (m.ai === "chase" ? pb.y : m.seenY) - 1.3 + Math.sin(this.clock * 3 + m.id) * 1.2; spd = d.speed;
		} else {
			m.t1 -= dt;
			if (m.t1 <= 0) { m.t1 = rand(1.5, 4); m.tx = m.b.x + rand(-8, 8); m.ty = m.b.y + rand(-4, 4); }
			tx = m.tx; ty = m.ty;
		}
		let ax = tx - m.b.x, ay = ty - m.b.y;
		const len = Math.max(0.001, Math.hypot(ax, ay)); ax /= len; ay /= len;
		const k = Math.min(1, dt * 4);
		m.b.vx += (ax * spd - m.b.vx) * k; m.b.vy += (ay * spd - m.b.vy) * k;
		if (Math.abs(m.b.vx) > 0.3) m.dir = m.b.vx > 0 ? 1 : -1;
		if (m.kind === "wraith") {
			const f = this.world.solid(Math.floor(m.b.x), Math.floor(m.b.y - 0.7)) ? 0.5 : 1;
			m.b.x += m.b.vx * dt * f; m.b.y += m.b.vy * dt * f;
		} else {
			this.world.moveBody(m.b, dt, 0, false, null);
			if (m.b.hitWall || m.b.hitCeil || m.b.onGround) { m.b.vy = -1; m.t1 = 0; }
		}
		if (aggro && m.kind !== "crow" && m.ai === "chase") this.contactHurt(m, d.dmg);
	},
	updateFish(m, dt) {
		const pb = this.pb, w = this.world;
		m.anim += dt * 6;
		if (!m.b.inWater) {
			m.b.vy = Math.min(m.b.vy + gravityG() * dt, terminalV);
			w.moveBody(m.b, dt, 0, false, null);
			m.t2 += dt;
			if (m.t2 > 1) { m.t2 = 0; this.hurtMob(m, 1, 0, 0, false); }
			return;
		}
		m.t1 -= dt;
		if (m.t1 <= 0) { m.t1 = rand(1.5, 4); m.tx = m.b.x + rand(-8, 8); m.ty = m.b.y + rand(-3, 3); }
		if (Math.abs(pb.x - m.b.x) < 4 && Math.abs(pb.y - m.b.y) < 3 && pb.inWater) { m.tx = m.b.x + (m.b.x - pb.x) * 3; m.ty = m.b.y + (m.b.y - pb.y) * 2; }
		let ax = m.tx - m.b.x, ay = m.ty - m.b.y;
		const len = Math.max(0.001, Math.hypot(ax, ay)); ax /= len; ay /= len;
		const sp = m.def.speed, k = Math.min(1, dt * 3);
		m.b.vx += (ax * sp - m.b.vx) * k; m.b.vy += (ay * sp * 0.6 - m.b.vy) * k;
		if (Math.abs(m.b.vx) > 0.2) m.dir = m.b.vx > 0 ? 1 : -1;
		const nx = m.b.x + m.b.vx * dt, ny = m.b.y + m.b.vy * dt;
		if (w.tile(Math.floor(nx), Math.floor(ny - 0.2)) === T.water && w.tile(Math.floor(nx), Math.floor(ny)) !== T.air) { m.b.x = nx; m.b.y = ny; }
		else { m.t1 = 0; m.b.vx = -m.b.vx; m.b.vy = -m.b.vy; }
		const f = w.liquidFractions(m.b.x - m.b.w * 0.5, m.b.y - m.b.h, m.b.x + m.b.w * 0.5, m.b.y);
		m.b.inWater = f[0] > 0.3;
	},
	updateCrawler(m, dt, aggro, dist, dyP) {
		const d = m.def, pb = this.pb;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 50, dt);
			m.dir = pb.x >= m.b.x ? 1 : -1;
			if (m.t3 <= 0) { m.st = 4; m.t3 = 0.7; m.cd = 0; m.b.vy = -8.5; m.b.vx = m.dir * 10.5; m.atkT = MOB_ATK; }
		} else if (m.st === 4) {
			m.t3 -= dt;
			this.contactHurt(m, d.dmg * 1.3);
			if ((m.b.onGround && m.t3 < 0.55) || m.t3 <= 0) { m.st = 0; m.cd = 1.3; }
		} else if (aggro) {
			this.chase(m, m.aimX, 1, dt);
			if (m.b.hitWall && m.b.onGround) m.b.vy = -11.5;
			if (m.ai === "chase" && m.b.onGround && m.cd <= 0 && dist > 1.8 && dist < 4.6 && Math.abs(dyP) < 2) { m.st = 3; m.t3 = 0.28; }
			if (m.ai === "chase") this.contactHurt(m, d.dmg);
		} else this.wander(m, dt, 0.6);
		this.stepMob(m, dt);
	},
	/** the stone golem: slow and armoured, slams the ground and throws rocks */
	updateGolem(m, dt, aggro, dist, dyP) {
		const d = m.def, pb = this.pb;
		const box = () => [m.dir > 0 ? m.b.x - 0.6 : m.b.x - 3.9, m.dir > 0 ? m.b.x + 3.9 : m.b.x + 0.6];
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) {
				m.st = 4; m.t3 = 0.35;
				const [x0, x1] = box();
				this.mobAttackBox(m, x0, m.b.y - 2.4, x1, m.b.y + 0.1, d.dmg, 10);
				m.atkT = MOB_ATK;
				this.addShake(dist < 10 ? 0.2 : 0.06);
				this.spawnParticles(m.b.x + m.dir * 2.2, m.b.y - 0.1, 0x8A8680, 10, 4, 0.5, 14);
			}
		} else if (m.st === 4) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 0; m.cd = 1.6; }
		} else if (m.st === 5) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			m.dir = pb.x >= m.b.x ? 1 : -1;
			if (m.t3 <= 0) { this.throwRock(m); m.st = 4; m.t3 = 0.3; m.cd = 2.8; }
		} else if (aggro) {
			this.chase(m, m.aimX, 1, dt);
			if (m.ai === "chase" && m.cd <= 0 && m.b.onGround) {
				if (dist < 3.3 && Math.abs(dyP) < 2.4) {
					m.st = 3; m.t3 = 0.75; m.dir = pb.x >= m.b.x ? 1 : -1;
					const [x0, x1] = box();
					this.warn(x0, m.b.y - 2.4, x1, m.b.y, 0.75, 0xFF8A2A);
				} else if (dist > 4.5 && dist < 11 && Math.random() * (m.blockedT > 0 ? 0.3 : 1) < 0.02 && this.world.lineClear(m.b.x, bodyTop(m.b) - 1.5, pb.x, pb.y - pb.h * 0.6)) { m.st = 5; m.t3 = 0.6; }
			}
			if (m.ai === "chase") this.contactHurt(m, d.dmg * 0.5);
		} else this.wander(m, dt, 0.35);
		this.stepMob(m, dt, 1);
	},
	throwRock(m) {
		const pb = this.pb, ox = m.b.x + m.dir * 0.6, oy = bodyTop(m.b) + 0.2, dx = pb.x - ox;
		const t = clampD(Math.abs(dx) / 9, 0.5, 1.3), grav = 22;
		this.shoot({ kind: "rock", x: ox, y: oy, vx: dx / t, vy: ((pb.y - 0.8) - oy - 0.5 * grav * t * t) / t, dmg: m.def.dmg * 0.8, gravity: grav, w: 0.6, life: 3, owner: m.id, source: srcMob(this, m) });
		m.atkT = MOB_ATK;
	},
	/** the bow zombie: keeps its distance and shoots arcing arrows */
	updateArcher(m, dt, aggro, dist, dyP) {
		const pb = this.pb;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			m.dir = pb.x >= m.b.x ? 1 : -1;
			if (m.t3 <= 0) {
				if (this.clearShot(m)) { this.shootArrowAtPlayer(m); m.st = 6; m.t3 = 0.25; }
				else if (m.t3 < -0.8) { m.st = 0; m.cd = 0.4; m.blockedT += 0.6; }
			}
		} else if (m.st === 6) {
			m.t3 -= dt; this.accelX(m, 0, 40, dt);
			if (m.t3 <= 0) { m.st = 0; m.cd = rand(1.4, 2.2); }
		} else if (aggro) {
			const sees = m.sees && (m.ai === "chase" || m.ai === "alert");
			if (dist < 5 && sees) { this.flee(m, pb.x, dt, 1.1); if (m.b.onGround && Math.random() < 0.025) { m.b.vy = -10; m.b.vx = m.dir * 5.5; } }
			else if (dist > 12 || !sees || m.blockedT > 0.5 || !m.b.onGround) this.chase(m, m.aimX, 0.9, dt);
			else { this.accelX(m, 0, 20, dt); m.dir = pb.x >= m.b.x ? 1 : -1; }
			if (m.ai === "chase" && m.cd <= 0 && sees && m.b.onGround && dist >= 3 && dist < 18 && Math.abs(dyP) < 10) { m.st = 3; m.t3 = 0.6; }
		} else this.wander(m, dt, 0.4);
		this.stepMob(m, dt);
	},
	clearShot(m) { return this.world.lineClear(m.b.x + m.dir * 0.6, this.shotY(m), this.pb.x, this.shotAimY(m)); },
	shotY(m) { return bodyTop(m.b) + 0.45; },
	shotAimY(m) {
		const pb = this.pb, chest = pb.y - pb.h * 0.55;
		return this.world.lineClear(m.b.x + m.dir * 0.6, this.shotY(m), pb.x, chest) ? chest : bodyTop(pb) + 0.25;
	},
	shootArrowAtPlayer(m) {
		const pb = this.pb, ox = m.b.x + m.dir * 0.6, oy = this.shotY(m);
		const tx = pb.x + pb.vx * 0.2, ty = this.shotAimY(m), grav = 15, dx = tx - ox, dy = ty - oy;
		const flight = Math.max(0.15, Math.hypot(dx, dy) / 19);
		this.shoot({ kind: "arrow", x: ox, y: oy, vx: dx / flight, vy: dy / flight - 0.5 * grav * flight, dmg: m.def.dmg, gravity: grav, life: 3, w: 0.22, owner: m.id, source: srcMob(this, m) });
	},
	/** the mimic: a chest that bites */
	updateMimic(m, dt, aggro, dist, dyP) {
		const d = m.def, pb = this.pb;
		m.t1 -= dt;
		m.angry = aggro;
		if (m.st === 3) {
			m.t3 -= dt; this.accelX(m, 0, 30, dt);
			if (m.t3 <= 0) { m.st = 4; m.t3 = 0.6; m.cd = 0; m.b.vy = -9.5; m.b.vx = m.dir * 9; m.atkT = MOB_ATK; }
		} else if (m.st === 4) {
			m.t3 -= dt;
			if (Math.abs(dyP) < 1.4) this.contactHurt(m, d.dmg * 1.2);
			if ((m.b.onGround && m.t3 < 0.45) || m.t3 <= 0) { m.st = 0; m.cd = m.hp < m.maxHP * 0.4 ? 0.7 : 1.1; }
		} else if (aggro) {
			m.dir = pb.x >= m.b.x ? 1 : -1;
			if (m.b.onGround) {
				m.b.vx *= 0.8;
				if (m.cd <= 0 && dist < 5 && Math.abs(dyP) < 2.2) { m.st = 3; m.t3 = 0.3; }
				else if (m.t1 <= 0) { m.b.vy = -8; m.b.vx = m.dir * 5; m.t1 = 0.45; }
			}
			if (Math.abs(dyP) < 1.4) this.contactHurt(m, d.dmg * 0.6);
		} else this.accelX(m, 0, 20, dt);
		this.stepMob(m, dt);
	},
	/** some unopened chests deep underground are mimics: opening one wakes it */
	tryMimic(x, y) {
		const w = this.world;
		if (w.dim !== Dimension.overworld || this.gen.genVersion < 3 || y < GEN_SEA + 20) return false;
		if (w.chests.has(w.chestKey(x, y)) || w.isBuilt(x, y)) return false;
		if (hash2(x, y, (this.gen.seed + 909) | 0) >= 0.08) return false;
		const loot = w.removeChest(x, y);
		w.set(x, y, T.air);
		const m = this.addMob("mimic", x + 0.5, y + 1);
		m.loot = loot; m.persistent = true; m.homeX = x + 0.5; m.homeY = y + 1;
		m.dir = this.pb.x >= m.b.x ? 1 : -1; m.st = 3; m.t3 = 0.45; m.angry = true;
		this.addShake(0.12);
		this.spawnParticles(m.b.x, m.b.y - 0.5, 0xB98A4E, 8, 4, 0.4, 12);
		this.say("The chest was a Mimic!", 2.5);
		return true;
	},

	// ---- animal life: herds, water holes, shelter, sleep at night, running from hunters
	animalLife(m, dt) {
		if (m.poseT > 0) m.poseT -= dt;
		if (m.drinkT > 0) m.drinkT -= dt;
		m.thinkT -= dt;
		const night = this.isNight && this.world.dim === Dimension.overworld;
		if (m.thinkT <= 0) {
			m.thinkT = rand(0.8, 1.4);
			for (const o of this.mobsNear(m.b.x - 10, m.b.x + 10)) {
				if (o.hp > 0 && o !== m && o.preyID !== 0 && !o.tame && Math.abs(o.b.x - m.b.x) < 10 && Math.abs(o.b.y - m.b.y) < 4) { m.t2 = 3; m.tx = o.b.x; m.goal = 0; return false; }
			}
			if (m.goal === 0 && !night) {
				const wx = m.drinkT <= 0 && Math.random() < 0.15 ? this.waterNear(m, 12) : null;
				if (wx !== null) { m.goal = 1; m.goalX = wx; }
				else if (Math.random() < 0.3) {
					let sum = 0, n = 0;
					for (const o of this.mobsNear(m.b.x - 18, m.b.x + 18)) if (o.kind === m.kind && o !== m && o.hp > 0 && !o.tame) { sum += o.b.x; n++; }
					if (n > 0) { const cx = sum / n; if (Math.abs(cx - m.b.x) > 7) { m.goal = 2; m.goalX = cx; } }
				}
			}
		}
		if (m.goal !== 0) {
			const dx = m.goalX - m.b.x;
			if ((Math.abs(dx) < 1.2 && m.goal !== 3) || Math.abs(dx) < 0.5 || (m.goal === 2 && Math.abs(dx) < 4)) {
				if (m.goal === 3) { m.poseT = 6; m.st = 0; }
				if (m.goal === 1) { m.drinkT = rand(25, 45); m.poseT = 3; m.st = 0; m.t1 = 3.2; }
				m.goal = 0;
			} else {
				m.dir = dx > 0 ? 1 : -1;
				const edge = m.goal === 1 && Math.abs(dx) < 2.5;
				if ((this.cliffAhead(m, m.dir) && !edge) || (m.b.hitWall && !m.b.onGround)) m.goal = 0;
				else {
					this.accelX(m, m.dir * m.def.speed * 0.6, 14, dt);
					if (m.b.hitWall && m.b.onGround) m.b.vy = -m.def.jump;
					return true;
				}
			}
		}
		if (m.poseT > 0) { this.accelX(m, 0, 18, dt); return true; }
		if (night && m.kind !== "frog") {
			if (m.st === 1 && Math.random() < 0.02) { m.st = 0; m.t1 = rand(4, 9); }
			if (m.st === 0) {
				m.t1 -= dt;
				if (m.t1 <= 0) { m.st = 1; m.t1 = rand(0.8, 1.6); m.dir = Math.random() < 0.5 ? 1 : -1; }
				this.accelX(m, 0, 18, dt);
				return true;
			}
		}
		return false;
	},
	waterNear(m, r) {
		const x0 = Math.floor(m.b.x), gy = Math.floor(m.b.y);
		for (let k = 1; k <= r; k += 2) for (const side of [1, -1]) {
			const x = x0 + side * k;
			for (let dy = -2; dy <= 2; dy++) if (this.world.tile(x, gy + dy) === T.water) return x - side + 0.5;
		}
		return null;
	},
	/** wolves at night, big cats and bears run down prey nearby, bite it and rest after a kill */
	hunt(m, dt, allowed) {
		if (m.poseT > 0) { m.poseT -= dt; this.accelX(m, 0, 18, dt); return true; }
		let prey = null;
		if (m.preyID !== 0) {
			const o = m.prey;
			if (o && o.id === m.preyID && o.hp > 0 && !o.removed) prey = o;
			if (!prey) { m.preyID = 0; m.poseT = 4; m.drinkT = 60; return true; }
		}
		m.thinkT -= dt;
		if (!prey && allowed && m.thinkT <= 0) {
			m.thinkT = rand(1.5, 3);
			let bd = 14;
			for (const o of this.mobsNear(m.b.x - 14, m.b.x + 14)) {
				if (!isPrey(o.kind) || o.hp <= 0 || o.tame || Math.abs(o.b.y - m.b.y) >= 4) continue;
				const d = Math.abs(o.b.x - m.b.x);
				if (d < bd) { bd = d; prey = o; }
			}
			if (prey) { m.preyID = prey.id; m.prey = prey; }
		}
		if (!prey) return false;
		if (!allowed || Math.abs(prey.b.x - m.b.x) > 26) { m.preyID = 0; return false; }
		this.chase(m, prey.b.x, 1.05, dt);
		if (m.kind === "wolf" && m.b.onGround && Math.abs(prey.b.x - m.b.x) < 4 && Math.random() < 0.03) { m.b.vy = -11; m.b.vx = m.dir * 7; }
		if (m.cd <= 0 && Math.abs(prey.b.x - m.b.x) < m.b.w * 0.5 + prey.b.w * 0.5 + 0.4 && Math.abs(prey.b.y - m.b.y) < 1.4) {
			m.cd = 0.9; m.atkT = MOB_ATK;
			this.hurtMob(prey, m.def.dmg, m.dir, 5, false);
			for (const o of this.mobsNear(prey.b.x - 10, prey.b.x + 10)) if (o.kind === prey.kind && o.hp > 0) { o.t2 = 3; o.tx = m.b.x; }
		}
		return true;
	},
	// ---- pets
	updatePet(m, dt) {
		const pb = this.pb, dist = Math.abs(pb.x - m.b.x);
		if (dist > 45 || Math.abs(pb.y - m.b.y) > 30) { m.b.x = pb.x - this.facing * 1.5; m.b.y = pb.y; m.b.vx = 0; m.b.vy = 0; return; }
		if (m.st === 7) { this.accelX(m, 0, 20, dt); this.stepMob(m, dt); return; }
		const t = m.kind === "wolf" ? this.nearestHostileTo(pb.x, pb.y - 1, 9) : null;
		if (t && t.hp > 0) {
			this.chase(m, t.b.x, 1.2, dt);
			if (m.cd <= 0 && Math.abs(t.b.x - m.b.x) < 1.6 && Math.abs(mobCY(t) - mobCY(m)) < 1.5) { this.hurtMob(t, 7, m.dir, 5, true); m.cd = 0.7; }
		} else if (dist > 3.5) this.chase(m, pb.x, dist > 12 ? 1.8 : 1.15, dt);
		else this.accelX(m, 0, 20, dt);
		this.stepMob(m, dt);
	},

	// ---- spawning
	lightForSpawn(x, feetY) {
		const L = this.spawnLight || (this.spawnLight = new LightMap());
		if (!L.covers(x - 1, feetY - 3, x + 1, feetY) || L.stamp !== this.world.version || L.skyUsed !== this.skyLevel || L.dimUsed !== this.world.dim) {
			const r = 18;
			L.compute(this.world, x - r, feetY - r, r * 2 + 1, r * 2 + 1, this.skyLevel, [], false);
			L.stamp = this.world.version;
		}
		return [Math.max(L.levelSky(x, feetY - 1), L.levelSky(x, feetY - 2)), Math.max(L.levelBlk(x, feetY - 1), L.levelBlk(x, feetY - 2))];
	},
	monsterCap(place) {
		const d = clampI(this.settings.nightDanger, 0, 2);
		const base = (place === "surface" || place === "ocean") ? [3, 6, 10][d] : [6, 9, 12][d];
		return Math.round(base * rule("monsters"));
	},
	spawnNote(s) { this.spawnLast = s; const L = this.spawnLog || (this.spawnLog = new Map()); if (L.size < 40 || L.has(s)) L.set(s, (L.get(s) || 0) + 1); },
	updateSpawning(dt) {
		if (this.monsterSpawnCD > 0) this.monsterSpawnCD -= dt;
		this.spawnTimer = (this.spawnTimer || 0) - dt;
		if (this.spawnTimer > 0) return;
		this.spawnTimer = rand(0.45, 1);
		if (this.dead || this.noSpawning) return;
		const pb = this.pb, w = this.world;
		let passive = 0, hostile = 0, predators = 0, aquatic = 0;
		for (const m of this.mobs) {
			if (m.hp <= 0 || m.removed || m.tame || m.persistent) continue;
			const dx = Math.abs(m.b.x - pb.x);
			if (dx > 100) continue;
			if (m.kind === "fish") aquatic++;
			else if (m.def.hostile) {
				if (isBossMob(m) || m.lair !== 0 || dx > 72 || Math.abs(m.b.y - pb.y) > 56) continue;
				if (isPredator(m.kind)) predators++; else hostile++;
			} else passive++;
		}
		const px = Math.floor(pb.x);
		let place = "surface";
		if (w.dim === Dimension.umbral) place = "umbral";
		else if (Math.floor(pb.y) - this.gen.col(px).h > 18 && !w.isSkyExposed(px, Math.floor(pb.y) - 1)) place = "cave";
		const half = this.viewTilesW * 0.5 + 3, side = Math.random() < 0.5 ? 1 : -1;
		const sx = pb.x + side * (half + rand(1, 16)), ix = Math.floor(sx);
		if (!w.isLoaded(ix)) { this.spawnNote("spot not loaded"); return; }
		if (!this.gen.infinite && (ix < 4 || ix > this.gen.width - 5)) return;
		let sy = 0, eff = place;
		if (place === "surface") {
			const h = w.surfaceY(ix), ht = w.tile(ix, h);
			if (LIQUID[ht]) {
				eff = "ocean";
				let wy = h + 1, dep = 0;
				while (w.tile(ix, wy) === T.water && dep < 40) { wy++; dep++; }
				if (dep < 5) { this.spawnNote("shallow water"); return; }
				sy = h + 2 + randInt(0, Math.max(1, dep - 3) - 1);
			} else if (SOLID[ht]) {
				if (w.solid(ix, h - 1) || w.solid(ix, h - 2) || LIQUID[w.tile(ix, h - 1)]) { this.spawnNote("no headroom"); return; }
				sy = h;
			} else { this.spawnNote("no ground"); return; }
		} else {
			let y = Math.floor(pb.y) + randInt(-20, 20), found = false;
			for (let tries = 0; tries < 22; tries++, y++) {
				if (!w.solid(ix, y) && !w.solid(ix, y - 1) && !w.solid(ix, y - 2) && w.solid(ix, y + 1) && !LIQUID[w.tile(ix, y)]) { found = true; break; }
			}
			if (!found) { this.spawnNote("no floor"); return; }
			if (place === "cave" && w.isSkyExposed(ix, y)) { this.spawnNote("open sky"); return; }
			const lit = this.lightForSpawn(ix, y + 1);
			if (lit[1] > SPAWN_GLOW_MAX || lit[0] > 6) { this.spawnNote("too bright"); return; }
			sy = y + 1;
		}
		const biome = this.biomeAt(ix), night = this.isNight;
		let block = "";
		if (eff === "surface") {
			const gy = Math.floor(sy);
			if (this.lightForSpawn(ix, gy)[1] > SPAWN_GLOW_MAX) block = "lit by a lamp";
			else if (!NATURAL_GROUND.has(w.tile(ix, gy))) block = "on a building";
			else if (Math.abs(sy - pb.y) > 30) block = "out of reach";
			else if (this.monsterSpawnCD > 0) block = "pacing";
		}
		const cap = this.monsterCap(eff);
		let capped = false, total = 0;
		const cands = [];
		for (const r of SPAWN_RULES) {
			if (r.place !== eff) continue;
			if (r.when === "day" && night) continue;
			if (r.when === "night" && !night) continue;
			if (r.biomes.length && !r.biomes.includes(biome)) continue;
			if ((eff === "cave" || eff === "umbral") && (sy < r.minY || sy > r.maxY)) continue;
			const d = MOBS[r.kind];
			if (d.hostile) {
				if (this.settings.peaceful || this.monstersOff) continue;
				if (isPredator(r.kind)) { if (predators >= Math.min(3, cap)) continue; }
				else { if (hostile >= cap) { capped = true; continue; } if (block) continue; }
			} else if (r.kind === "fish") { if (aquatic >= this.animalCap) continue; }
			else if (passive >= this.animalCap) continue;
			cands.push(r); total += r.weight;
		}
		if (!cands.length || total <= 0) {
			this.spawnNote(capped ? "monster limit reached" : (block && night) ? block : night ? "nothing for this place" : "nothing for this place by day");
			return;
		}
		let pick = Math.random() * total, chosen = cands[0];
		for (const r of cands) { pick -= r.weight; if (pick <= 0) { chosen = r; break; } }
		const def = MOBS[chosen.kind], monster = def.hostile && !isPredator(chosen.kind);
		let n = 1 + randInt(0, Math.max(1, chosen.group) - 1);
		if (monster) n = Math.min(n, cap - hostile);
		let made = 0;
		for (let k = 0; k < n; k++) {
			const x = sx + k * 1.1 * side + rand(-0.4, 0.4);
			let y = sy;
			if (eff === "surface" && !def.flying) {
				const gyS = w.surfaceY(Math.floor(x));
				if (LIQUID[w.tile(Math.floor(x), gyS)] || Math.abs(gyS - Math.floor(sy)) > 3) continue;
				y = gyS;
			}
			if (def.flying && eff !== "ocean") y -= rand(1, 3);
			if (monster && eff !== "ocean" && this.lightForSpawn(Math.floor(x), Math.floor(y))[1] > SPAWN_GLOW_MAX) continue;
			if (eff !== "ocean" && !this.spawnSpotClear(def, x, y)) continue;
			const m = this.addMob(chosen.kind, x, y);
			m.homeX = x; m.homeY = y;
			if (monster && eff === "surface" && night) m.hunter = true;
			if (chosen.kind === "sheep" && Math.random() < 0.1) m.sheared = true;
			made++;
		}
		if (!made) { this.spawnNote("no room to stand"); return; }
		this.spawnNote("spawned " + def.name);
		if (monster && eff === "surface") this.monsterSpawnCD = [8, 4, 2][clampI(this.settings.nightDanger, 0, 2)] * rand(0.8, 1.25);
	},
	spawnSpotClear(d, x, y) {
		const hw = d.w * 0.5, w = this.world;
		if (w.boxSolid(x - hw + 0.02, y - d.h, x + hw - 0.02, y - 0.05)) return false;
		if (d.flying) return true;
		const gy = Math.floor(y + 0.05), l = Math.floor(x - hw + 0.05), r = Math.floor(x + hw - 0.05);
		let footing = 0;
		for (let tx = l; tx <= r; tx++) if (w.solid(tx, gy) || w.tile(tx, gy) === T.platform) footing++;
		return footing * 2 >= r - l + 1;
	},
});
// the "animalCap" getter must be a real property (Object.assign would copy its value once)
Object.defineProperty(Game.prototype, "animalCap", { get() { return Math.round(9 * rule("animals")); } });
/** bosses and other special creatures take over their own update through this; true when one did */
function mobKindHook(g, m, dt) { return bossUpdate(g, m, dt); }
