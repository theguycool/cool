// PIXEL REALM v2, part 5 of 10: vehicles of every kind (flight, weapons, damage, the assembler, the autopilot), Sparkworks (power) and the
// Mod Creator's data, checks and runtime.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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
	case .receiver: return 20
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
			if fromVehicle && p.owner == 2_000_000 + machineRoot(v).id { continue }
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
		// (a gun on any section of a machine answers whoever drives the machine)
		let driving: Bool = playerDrives(v)
		let firing: Bool = driving && useHeld && aimValid
		let buttons: [Bool] = machineButtonsHeld(v, driving)
		for (c, t) in v.parts where t == .cannon || t == .autoGun {
			let f: (Int, Int) = v.face[c] ?? (1, 0)
			let base: Double = v.angle + atan2(Double(f.1), Double(f.0))
			let o: (Double, Double) = v.cellCenter(c)
			var want: Double = base
			if driving && aimValid { want = atan2(aimY - o.1, aimX - o.0) }
			var shoot: Bool = firing
			let mode: GunMode = GunMode(rawValue: v.gunMode[c] ?? 0) ?? .driver
			switch mode {
			case .driver:
				break
			case .auto:
				// a turret picks its own target and fires by itself
				shoot = false
				if let tg = turretTarget(v, c, o, base) {
					want = atan2(tg.1 - o.1, tg.0 - o.0)
					shoot = true
				}
			case .buttonA, .buttonB, .buttonC:
				shoot = buttons[mode.rawValue - GunMode.buttonA.rawValue]
			case .signal:
				shoot = machineSignalOn(v)
			}
			let rel: Double = clampD(remainder(want - base, 2.0 * Double.pi), -Radio.gunArc, Radio.gunArc)
			let a: Double = base + rel
			let cur: Double = v.aimAng[c] ?? base
			let turn: Double = remainder(a - cur, 2.0 * Double.pi)
			let rate: Double = (t == .cannon ? 3.0 : 6.0) * dt
			let na: Double = cur + clampD(turn, -rate, rate)
			v.aimAng[c] = na
			if shoot && (v.gunCD[c] ?? 0) <= 0 && abs(remainder(want - na, 2.0 * Double.pi)) < 0.35 && !v.boxed.contains(c) {
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
		// a mod's gun block can fire its own shot, as fast, as hard and as often as its maker set
		let gun: ModGunRT = modGun(v, c)
		let speed: Double = gun.speed > 0 ? gun.speed : (cannon ? 34.0 : 44.0)
		let dmg: Double = (gun.damage > 0 ? gun.damage : (cannon ? 24 : 4.5)) * k
		var grav: Double = cannon ? 14 : 3
		var life: Double = cannon ? 4.0 : 1.3
		var kind: ProjKind = cannon ? .shell : .bullet
		var w: Double = cannon ? 0.35 : 0.15
		if gun.shot >= 0 && gun.shot < ModRuntime.shared.shots.count {
			let ms: ModProjectile = ModRuntime.shared.shots[gun.shot]
			grav = ms.gravity
			life = ms.life
			kind = .spit
			w = ms.size
		}
		var p = Projectile(kind: kind, x: mx, y: my, vx: cos(a) * speed + v.vx, vy: sin(a) * speed + v.vy, dmg: dmg, fromPlayer: true, gravity: grav)
		p.life = life
		p.w = w
		p.mod = gun.shot
		p.source = .player
		// (the shot passes every section of the machine it came from)
		p.owner = 2_000_000 + machineRoot(v).id
		p.uid = newID()
		p.knock = cannon ? 9 : 3
		projectiles.append(p)
		v.gunCD[c] = gun.rate > 0 ? 1.0 / gun.rate : (cannon ? 2.0 : 0.13)
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
		guard let v = drivenVehicle, v.turnT == 0 else { return }
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
		guard let v = drivenVehicle, v.autopilots > 0 else { return }
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
		guard let v = drivenVehicle, v.autopilots > 0 else { return }
		if v.route.count >= 16 { v.route.removeFirst() }
		v.route.append(VWaypoint(x: v.px, y: v.py))
		let n: Int = v.route.count
		say(n < 2 ? "Point 1 marked. Drive on and mark more." : joinText("Point ", String(n), " marked. AUTO twice to drive the route."), 2.0)
		bumpHUD()
	}

	func clearRoute() {
		guard let v = drivenVehicle else { return }
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
	case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor: return .sensor
	case .gateClosed, .gateOpen, .lampOff, .lampOn, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .exoStation, .signalPost: return .machine
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
		case .vehicleSensor: param = 3
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
		case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor: return 0.5
		case .signalPost: return 0.5
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
		case .vehicleSensor:
			return vehicleNearSensor(cx, cy, clampD(d.param, 1, 8), d.mode)
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
		var posts: [Bool] = [Bool](repeating: false, count: Radio.channels)
		for d in sim.machines {
			// a signal post sends its channel while it runs
			if d.tile == .signalPost {
				applyMachine(d)
				if d.enabled && d.powered { posts[clampI(d.mode, 0, Radio.channels - 1)] = true }
				continue
			}
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
		postChannels = posts
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
							 .itemSensor, .proximitySensor, .gateClosed, .lampOff, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .signalLight,
							 .signalPost, .vehicleSensor]
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
		case .vehicleSensor: return ["ANY VEHICLE", "DRIVEN", "NOBODY ABOARD"]
		case .signalPost: return (1...Radio.channels).map { (n: Int) in joinText("CH ", String(n)) }
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
		case .signalPost: return "The channel it sends to receivers"
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
		case .vehicleSensor: return ("Range (blocks)", 1, 8, 1)
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
		case .signalPost: return "Sends its channel to every receiver on it while powered (and while its pulse wire is on, if it has one)."
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
			case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor:
				led(d.out, L + tp * 0.85, T + tp * 0.15, &teal)
			case .signalPost:
				led(d.enabled && d.powered, L + tp * 0.5, T + tp * 0.1, &amber)
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

	/// Big enough to draw on, small enough to stay cheap, and the bytes match the size (up to 96 for
	/// the game's big creatures, whose sprites can be edited)
	var valid: Bool { return w >= 1 && h >= 1 && w <= ModPixels.maxSide && h <= ModPixels.maxSide && rgba.count == w * h * 4 }

	static let maxSide: Int = 96

	/// The pixel as 0xAARRGGBB with its own opacity (0 outside the picture, or all but invisible)
	func argb(_ x: Int, _ y: Int) -> UInt32 {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return 0 }
		let i: Int = (y * w + x) * 4
		let a: UInt32 = UInt32(rgba[i + 3])
		if a < 8 { return 0 }
		let r: UInt32 = UInt32(rgba[i])
		let g: UInt32 = UInt32(rgba[i + 1])
		let b: UInt32 = UInt32(rgba[i + 2])
		return (a << 24) | (r << 16) | (g << 8) | b
	}

	/// Sets a pixel, keeping its opacity (pictures saved before pixels could be part see-through only
	/// ever held fully solid or fully clear ones, so they read the same)
	mutating func setARGB(_ x: Int, _ y: Int, _ c: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return }
		let i: Int = (y * w + x) * 4
		let a: UInt8 = UInt8((c >> 24) & 0xFF)
		rgba[i] = a == 0 ? 0 : UInt8((c >> 16) & 0xFF)
		rgba[i + 1] = a == 0 ? 0 : UInt8((c >> 8) & 0xFF)
		rgba[i + 2] = a == 0 ? 0 : UInt8(c & 0xFF)
		rgba[i + 3] = a
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
			if rgba[i] >= 8 { return false }
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

	/// The picture at another size, its pixels doubled or dropped to fit (nearest pixel)
	func stretched(_ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		o.outline = outline
		if !valid { return o }
		for y in 0..<o.h {
			for x in 0..<o.w { o.setARGB(x, y, argb(min(w - 1, x * w / o.w), min(h - 1, y * h / o.h))) }
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
	/// climbed like a ladder; sticky: slows what moves through it; decoration: like a flower (appended)
	case climbable, sticky, decor
	/// a liquid that flows, with the numbers in the block's LIQUID section (appended)
	case liquid
	var name: String {
		switch self {
		case .liquid: return "Liquid"
		case .solid: return "Solid"
		case .platform: return "Platform (stand on top)"
		case .none: return "Pass through"
		case .climbable: return "Climbable"
		case .sticky: return "Sticky"
		case .decor: return "Decoration"
		}
	}
	var help: String {
		switch self {
		case .solid: return "A wall and a floor: nothing passes it."
		case .platform: return "Walk and jump up through it, land on top of it (hold down to drop through)."
		case .none: return "Everything passes through it, as through a tree trunk."
		case .climbable: return "Passed through, and climbed like a ladder: jump or up to climb, down to go down."
		case .sticky: return "Passed through slowly, like a cobweb: walking, jumping and falling all slow down in it."
		case .decor: return "Like a flower or tall grass: passed through, needs ground under it, and a block built there replaces it."
		case .liquid: return "A liquid: it flows down and spreads, things swim and float in it, and it can harm, heal or harden where it meets another liquid."
		}
	}
}

/// What tapping (or touching) a block does. Doors and switches use a second tile number for their
/// other state (open, lit).
enum ModBlockFunction: Int, Codable, CaseIterable {
	case none, storage, station, lamp, door, healer, bounce, trap, sign
	/// furniture (appended): a seat to sit on, a bed to sleep in
	case seat, bed
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
		case .seat: return "Seat"
		case .bed: return "Bed"
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
		case .seat: return "Tap it to sit down, like a chair (walk or jump to get up)."
		case .bed: return "Tap it at night to sleep until morning; it becomes where you wake up."
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
	/// working as a cannon or machine gun: the mod's own shot it fires (its id; "": the game's), how
	/// fast and how hard (0: the game part's own), and how many a second (0: the part's own)
	var shot: String = ""
	var shotSpeed: Double = 0
	var shotDamage: Double = 0
	var fireRate: Double = 0
	/// as building material: its weight and what it holds up (0: worked out from its hardness), and
	/// whether it falls like sand with nothing under it
	var weight: Double = 0
	var carry: Double = 0
	var falls: Bool = false
	/// what it is like to touch: how well wheels, hulls and feet grip it (1: stone; ice is 0.12) and how
	/// much of a blow it gives back (0: none, 1: all of it)
	var grip: Double = 1.0
	var bounce: Double = 0.0
	/// as a liquid (collision .liquid): density (water 1), thickness (water 1, lava 4), how far a block of
	/// it spreads, harm a second, whether it burns, how see-through it is, the block it hardens into
	/// where it meets another liquid ("" none), whether a thin film dries up, and an effect it gives
	/// whoever is in it (a ModEffectKind number, -1 none) and how strong
	var liqDensity: Double = 1.0
	var liqThick: Double = 1.0
	var liqReach: Int = 7
	var liqHarm: Double = 0
	var liqHot: Bool = false
	var liqOpacity: Double = 0.75
	var liqHardens: String = ""
	var liqDries: Bool = false
	var liqEffect: Int = -1
	var liqEffectAmt: Double = 10
	/// on Sparkworks power lines: what it does, and how strong it is at it
	var powerRole: ModPowerRole = .none
	var powerAmt: Double = 4

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
		shot = c.val(.shot, "")
		shotSpeed = c.val(.shotSpeed, 0)
		shotDamage = c.val(.shotDamage, 0)
		fireRate = c.val(.fireRate, 0)
		weight = c.val(.weight, 0)
		carry = c.val(.carry, 0)
		falls = c.val(.falls, false)
		grip = c.val(.grip, 1.0)
		liqDensity = c.val(.liqDensity, 1.0)
		liqThick = c.val(.liqThick, 1.0)
		liqReach = c.val(.liqReach, 7)
		liqHarm = c.val(.liqHarm, 0)
		liqHot = c.val(.liqHot, false)
		liqOpacity = c.val(.liqOpacity, 0.75)
		liqHardens = c.val(.liqHardens, "")
		liqDries = c.val(.liqDries, false)
		liqEffect = c.val(.liqEffect, -1)
		liqEffectAmt = c.val(.liqEffectAmt, 10)
		bounce = c.val(.bounce, 0.0)
		powerRole = c.val(.powerRole, .none)
		powerAmt = c.val(.powerAmt, 4)
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
	/// the Overworld's sun and moon as this mod draws them (nil: the game's)
	var skySun: ModSkyBody? = nil
	var skyMoon: ModSkyBody? = nil
	/// tree designs for its dimensions' regions
	var trees: [ModTree] = []
	/// suit materials, suit parts and whole suit designs
	var suitMats: [ModSuitMat] = []
	var suitParts: [ModSuitPart] = []
	var suitDesigns: [ModSuitDesign] = []
	/// rules of the game in the worlds it is in, by rule id (GameRule; a rule left out is the game's own)
	var rules: [String: Double] = [:]
	/// what a new world (not in creative) starts with in the bag
	var startItems: [ModCost] = []
	/// the Overworld's weather as this mod has it (nil: the game's)
	var weather: ModWeather? = nil
	/// whole vehicles, each also an item that builds it
	var vehicles: [ModVehicle] = []
	/// how the game's screens look (nil: the game's own)
	var theme: ModTheme? = nil
	/// entries left out because they could not be read (not saved)
	var skipped: Int = 0

	enum CodingKeys: String, CodingKey {
		case format, id, name, desc, author, version, created, edited, sandbox
		case blocks, items, mobs, projectiles, recipes, loot, ores, structures
		case folder, requires, off, overrides, infusions, dims, scripts, variables
		case skySun, skyMoon, trees
		case suitMats, suitParts, suitDesigns
		case rules, startItems, weather, vehicles, theme
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
		skySun = c.val(.skySun, nil)
		skyMoon = c.val(.skyMoon, nil)
		trees = c.list(.trees, &skip)
		suitMats = c.list(.suitMats, &skip)
		suitParts = c.list(.suitParts, &skip)
		suitDesigns = c.list(.suitDesigns, &skip)
		rules = c.val(.rules, [:])
		startItems = c.list(.startItems, &skip)
		weather = c.val(.weather, nil)
		vehicles = c.list(.vehicles, &skip)
		theme = c.val(.theme, nil)
		skipped = skip
	}

	/// The key other content uses for something of this mod
	func key(_ contentID: String) -> String { return id + ":" + contentID }

	var contentCount: Int {
		let counts: [Int] = [blocks.count, items.count, mobs.count, projectiles.count, recipes.count, loot.count, ores.count, structures.count, overrides.count, infusions.count, dims.count, scripts.count, trees.count, suitMats.count, suitParts.count, suitDesigns.count, vehicles.count, rules.isEmpty && startItems.isEmpty ? 0 : 1, weather == nil ? 0 : 1, theme == nil ? 0 : 1]
		var n: Int = 0
		for c in counts { n += c }
		return n
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
		for t in trees { used.insert(t.id) }
		for m in suitMats { used.insert(m.id) }
		for sp in suitParts { used.insert(sp.id) }
		for sd in suitDesigns { used.insert(sd.id) }
		for v in vehicles { used.insert(v.id) }
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
		for i in p.suitMats.indices { if let it = p.suitMats[i].cost { p.suitMats[i].cost = fix(it) } }
		for i in p.suitDesigns.indices {
			for k in p.suitDesigns[i].design.pieces.indices {
				p.suitDesigns[i].design.pieces[k].modMat = fixRef(p.suitDesigns[i].design.pieces[k].modMat)
				p.suitDesigns[i].design.pieces[k].modPart = fixRef(p.suitDesigns[i].design.pieces[k].modPart)
			}
		}
		for i in p.startItems.indices { p.startItems[i].item = fix(p.startItems[i].item) }
		for i in p.vehicles.indices {
			for k in p.vehicles[i].cells.indices { p.vehicles[i].cells[k].block = fixRef(p.vehicles[i].cells[k].block) }
		}
		for i in p.trees.indices {
			p.trees[i].trunk = fixRef(p.trees[i].trunk)
			p.trees[i].branch = fixRef(p.trees[i].branch)
			p.trees[i].leaves = fixRef(p.trees[i].leaves)
			p.trees[i].ground = fixRef(p.trees[i].ground)
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
			for sp in p.suitParts { c.keys[p.key(sp.id)] = "item"; c.names[p.key(sp.id)] = sp.name }
			for m in p.suitMats { c.keys[p.key(m.id)] = "suitmat"; c.names[p.key(m.id)] = m.name }
			for v in p.vehicles { c.keys[p.key(v.id)] = "item"; c.names[p.key(v.id)] = v.name }
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
				b.art = b.art.valid ? ModBlock.fitArt(b.art) : ModPixels(w: 8, h: 8)
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
			b.shotSpeed = clampD(b.shotSpeed.isFinite ? b.shotSpeed : 0, 0, sb ? 200 : 80)
			b.shotDamage = clampD(b.shotDamage.isFinite ? b.shotDamage : 0, 0, sb ? 500 : 120)
			b.fireRate = clampD(b.fireRate.isFinite ? b.fireRate : 0, 0, sb ? 60 : 30)
			if !b.shot.isEmpty && !p.projectiles.contains(where: { $0.id == b.shot }) {
				r.add(1, mn, place, "Its gun's shot is not one of this mod's shots: it fires the game's own.")
				b.shot = ""
			}
			b.weight = clampD(b.weight.isFinite ? b.weight : 0, 0, sb ? 40 : 12)
			b.carry = clampD(b.carry.isFinite ? b.carry : 0, 0, sb ? 4000 : 400)
			b.grip = clampD(b.grip.isFinite ? b.grip : 1, 0.02, sb ? 4 : 2)
			b.bounce = clampD(b.bounce.isFinite ? b.bounce : 0, 0, sb ? 1.2 : 0.9)
			b.liqDensity = clampD(b.liqDensity.isFinite ? b.liqDensity : 1, 0.2, sb ? 12 : 5)
			b.liqThick = clampD(b.liqThick.isFinite ? b.liqThick : 1, 1, sb ? 20 : 8)
			b.liqReach = clampI(b.liqReach, 1, sb ? 30 : 12)
			b.liqHarm = clampD(b.liqHarm.isFinite ? b.liqHarm : 0, 0, sb ? 100 : 20)
			b.liqOpacity = clampD(b.liqOpacity.isFinite ? b.liqOpacity : 0.75, 0.1, 1)
			b.liqEffect = clampI(b.liqEffect, -1, ModEffectKind.allCases.count - 1)
			b.liqEffectAmt = clampD(b.liqEffectAmt.isFinite ? b.liqEffectAmt : 10, 0, sb ? 200 : 60)
			if b.liqHardens.count > 80 { b.liqHardens = "" }
			b.powerAmt = clampD(b.powerAmt.isFinite ? b.powerAmt : 4, 0.1, sb ? 200 : 40)
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
	/// a pass-through tree form of a solid block (for trees in custom dimensions): the block it stands
	/// for, and the part it plays (0 not a tree form, 1 trunk or branch, 2 leaves)
	var slotTreeBase: [Tile?] = [Tile?](repeating: nil, count: ModLimits.blockSlots)
	var slotTreeRole: [UInt8] = [UInt8](repeating: 0, count: ModLimits.blockSlots)
	/// mod blocks climbed like a ladder, and those that slow what moves through them
	var climbTiles: Set<UInt8> = []
	var stickyTiles: Set<UInt8> = []
	/// the mods' liquids by tile number (see p12c_fluids)
	var liquidDefs: [UInt8: LiquidDef] = [:]
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
	/// mods' suit materials and suit parts, by key
	var suitMats: [String: SuitMatInfo] = [:]
	var suitParts: [String: SuitPartInfo] = [:]
	/// the mods' whole suit designs, with their names (to start from at an Assembly Station)
	var suitDesigns: [(String, SuitDesign)] = []
	/// the Overworld's sun and moon as the mods draw them (the last mod that sets one wins)
	var overSun: ModSkyBody? = nil
	var overMoon: ModSkyBody? = nil
	var dimSlotKey: [String?] = [nil, nil, nil]
	/// the rules of the game as the mods set them (by GameRule number), what a new world starts with,
	/// the Overworld's weather and the screens' look as the last mod that sets them has them
	var rules: [Double] = GameRule.specs.map { $0.def }
	var startItems: [Stack] = []
	var weather: ModWeather? = nil
	var theme: ModTheme? = nil
	/// the mods' vehicles by key
	var vehicles: [String: ModVehicle] = [:]
	/// mod blocks that fall like sand, seats, beds, and those on power lines
	var fallTiles: Set<UInt8> = []
	var seatTiles: Set<UInt8> = []
	var bedTiles: Set<UInt8> = []
	var powerTiles: [UInt8: ModPowerRole] = [:]

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
		rt.buildSuits()
		rt.buildInfusions(world)
		rt.buildLoot()
		rt.buildMobs()
		rt.buildSummons()
		rt.buildDims(world)
		rt.buildWorldRules()
		for p in rt.packs {
			if let b = p.skySun { rt.overSun = b }
			if let b = p.skyMoon { rt.overMoon = b }
		}
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
		// pass-through forms of the solid blocks trees in custom dimensions are made of (after every
		// block, so blocks keep the numbers they had). A world keeps the forms it has, even once its
		// mod no longer needs them, so the trees already grown there stay as they were.
		var forms: [(String, Tile, Int)] = treeFormsWanted()
		if let w = world {
			for k in w.blocks.keys.sorted() where (k.hasSuffix("#tree") || k.hasSuffix("#leaf")) && !forms.contains(where: { $0.0 == k }) {
				guard let bt = ModGround.resolve(String(k.dropLast(5)), self), bt != .air, !bt.liquid else { continue }
				if let bi = slot(bt), slotDef[bi] == nil { continue }
				forms.append((k, bt, k.hasSuffix("#leaf") ? 2 : 1))
			}
		}
		for (k, bt, role) in forms {
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
			slotTreeBase[i] = bt
			slotTreeRole[i] = UInt8(role)
			if let bi = slot(bt), let b0 = slotDef[bi] {
				var b: ModBlock = b0
				b.function = .none
				b.vehRole = .none
				b.collision = role == 2 ? .platform : .none
				slotDef[i] = b
				slotTool[i] = slotTool[bi]
			} else {
				slotDef[i] = nil
				slotTool[i] = toolClass(bt)
			}
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

	/// The solid blocks the trees of the custom dimensions are made of, each with the part it plays
	/// (1 trunk or branch, 2 leaves): each gets a pass-through tree form, so no tree is a wall
	func treeFormsWanted() -> [(String, Tile, Int)] {
		var out: [(String, Tile, Int)] = []
		var seen: Set<String> = []
		func want(_ k: String, _ role: Int) {
			if k.isEmpty { return }
			let fk: String = k + (role == 2 ? "#leaf" : "#tree")
			if seen.contains(fk) { return }
			guard let t = ModGround.resolve(k, self), t != .air, !t.liquid, t.trunkForm == t else { return }
			if let i = slot(t) {
				guard let b = slotDef[i], b.collision == .solid, !slotAlt[i] else { return }
			} else if !t.solid {
				return
			}
			seen.insert(fk)
			out.append((fk, t, role))
		}
		for p in packs {
			for d in p.dims where !disabled.contains(p.key(d.id)) {
				for z in d.zones {
					want(z.log, 1)
					want(z.leaves, 2)
					for tid in z.treeKinds {
						guard let tr = p.trees.first(where: { $0.id == tid }), !disabled.contains(p.key(tid)) else { continue }
						want(tr.trunk, 1)
						want(tr.branch, 1)
						want(tr.leaves, 2)
					}
				}
			}
		}
		return out
	}

	/// The part a tile plays as a tree form: 1 trunk or branch, 2 leaves, 0 not a tree form
	func treeRole(_ t: Tile) -> UInt8 {
		guard let i = slot(t) else { return 0 }
		return slotTreeRole[i]
	}

	/// The tile a tree is made of for a block key: the block's pass-through tree form when it is solid
	/// (role 1 trunk or branch, 2 leaves), the tree trunk of a log block, or the block itself
	func treeTile(_ key: String, _ role: Int) -> Tile? {
		if let t = tileForKey[key + (role == 2 ? "#leaf" : "#tree")] { return t }
		guard let t = ModGround.resolve(key, self) else { return nil }
		return t.trunkForm
	}

	/// Slot index of a tile (nil for game tiles)
	@inline(__always) func slot(_ t: Tile) -> Int? {
		let i: Int = Int(t.rawValue) - Int(Tile.modBase)
		return i >= 0 && i < ModLimits.blockSlots ? i : nil
	}

	func blockDef(_ t: Tile) -> ModBlock? {
		guard let i = slot(t) else { return nil }
		return slotDef[i]
	}

	/// The mod shot a mod's gun block fires (its number among the shots; -1: the game's own)
	func blockShot(_ t: Tile) -> Int {
		guard let i = slot(t), let k = slotKey[i], let d = slotDef[i], !d.shot.isEmpty else { return -1 }
		let modID: String = String(k.split(separator: ":").first ?? "")
		return shotIndex[joinText(modID, ":", d.shot)] ?? -1
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
		if slotTreeRole[i] != 0, let bt = slotTreeBase[i] {
			// a tree form: the block it stands for, passed through (leaves can be stood on, as the game's)
			var d: TileDef = Tile.makeDef(bt)
			if let bi = slot(bt) { d = tileDef(bi) }
			d.solid = false
			d.opaque = false
			d.platform = slotTreeRole[i] == 2
			d.plant = false
			d.hurt = false
			d.liquid = false
			d.drop = nil
			d.noDrop = false
			return d
		}
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
		d.plant = b.collision == .decor
		d.liquid = b.collision == .liquid
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
		if slotTreeRole[i] != 0 {
			// a tree form gives what the block it stands for gives
			guard let bt = slotTreeBase[i] else { return [] }
			if slot(bt) != nil { return blockDrops(bt) ?? [] }
			let bd: TileDef = Tile.makeDef(bt)
			if bd.noDrop { return [] }
			return [Stack(item: bd.drop ?? .block(bt), count: 1)]
		}
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
			// a suit part is an item too
			for sp in p.suitParts where !disabled.contains(p.key(sp.id)) {
				let k: String = p.key(sp.id)
				let it: ModItem = suitPartItem(p, sp)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				r.icon = itemIconBuf(it)
				items[k] = r
				itemOrder.append(k)
			}
			// a vehicle's kit is an item too
			for v in p.vehicles where !disabled.contains(p.key(v.id)) {
				let k: String = p.key(v.id)
				let it: ModItem = vehicleItem(p, v)
				let r = ModItemRT(key: k, def: it, modName: p.name)
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
		climbTiles = []
		stickyTiles = []
		liquidDefs = [:]
		for i in 0..<ModLimits.blockSlots {
			guard let t = Tile(rawValue: UInt8(base + i)) else { continue }
			slotArt[i] = slotArtBuf(i)
			Tile.patch(t, tileDef(i), tool: slotTool[i])
			Liquids.hotTable[Int(t.rawValue)] = false
			if let b = slotDef[i], slotTreeRole[i] == 0 {
				if b.collision == .climbable { climbTiles.insert(t.rawValue) }
				if b.collision == .sticky { stickyTiles.insert(t.rawValue) }
				if b.collision == .liquid {
					liquidDefs[t.rawValue] = modLiquid(b, t, slotArt[i] ?? PixelBuf(w: 8, h: 8))
					Liquids.hotTable[Int(t.rawValue)] = b.liqHot
				}
			}
			if let b = slotDef[i], !slotAlt[i], !b.dropSelf, let d = b.drop {
				slotDrop[i] = Stack(item: resolve(d), count: b.dropCount)
			}
		}
		RecipeBook.all = RecipeBook.base + recipes
		OverrideRT.shared.install()
		SectionPainter.shared.refreshModTiles()
		Art.shared.refreshModArt()
	}

	/// A mod block that is a liquid, as the flow sees it (its colour from its picture)
	func modLiquid(_ b: ModBlock, _ t: Tile, _ art: PixelBuf) -> LiquidDef {
		var d: LiquidDef = LiquidDef(tile: t)
		d.color = averageColor(art)
		d.opacity = b.liqOpacity
		d.density = b.liqDensity
		d.thick = b.liqThick
		d.reach = b.liqReach
		d.harm = b.liqHarm
		d.hot = b.liqHot
		d.dries = b.liqDries
		d.effect = b.liqEffect
		d.effectAmt = b.liqEffectAmt
		if !b.liqHardens.isEmpty {
			if b.liqHardens.hasPrefix("tile:"), let n = Int(b.liqHardens.dropFirst(5)), n >= 0, n < 256, let gt = Tile(rawValue: UInt8(n)), gt.solid { d.hardens = gt }
			else if let mt = tileForKey[b.liqHardens] { d.hardens = mt }
		}
		return d
	}

	/// The picture a slot draws: the block's art (an open door shows its edge, an unlit lamp is darker)
	func slotArtBuf(_ i: Int) -> PixelBuf {
		if slotTreeRole[i] != 0, let bt = slotTreeBase[i] {
			if let bi = slot(bt) { return slotArtBuf(bi) }
			return tileBuf(bt)
		}
		guard let b = slotDef[i] else { return missingTileBuf() }
		var art: PixelBuf = b.art.isBlank ? greyTileBuf() : b.art.buf()
		if b.art.outlined(false) { art.outline(0x101010) }
		if b.function == .door && slotAlt[i] {
			// an open door shows its edge: the left quarter of its picture
			var o = PixelBuf(w: art.w, h: art.h)
			for y in 0..<art.h {
				for x in 0..<max(1, art.w / 4) { o.px[y * art.w + x] = art.px[y * art.w + x] }
			}
			art = o
		}
		if b.function == .lamp && !slotAlt[i] {
			for k in 0..<art.px.count where (art.px[k] >> 24) != 0 {
				art.px[k] = (art.px[k] & 0xFF000000) | shadeRGB(art.px[k] & 0xFFFFFF, 0.55)
			}
		}
		return art
	}
}

extension ModRuntime {
	/// The custom blocks and items the creative palette and the test tools offer
	func paletteItems() -> [Item] {
		var out: [Item] = []
		for i in 0..<ModLimits.blockSlots where slotDef[i] != nil && !slotAlt[i] && slotTreeRole[i] == 0 {
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
		// a part see-through pixel stays as see-through
		o.px[i] = (c & 0xFF000000) | rgb
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

/// The game creature a custom creature takes its body from
func modMobBase(_ m: ModMob) -> MobKind {
	let base: MobKind = MobKind(rawValue: m.base) ?? .zombie
	return base == .custom ? .zombie : base
}

/// A custom creature's frames as a sprite set: its own art sized to its hit box, or its game
/// creature's look (in that look's own pixel size) grown by the creature's scale
func modMobSet(_ m: ModMob, _ frames: [PixelBuf], _ anim: CreatureAnim) -> SpriteSet {
	let base: MobKind = modMobBase(m)
	let h: Double = clampD(mobDef(base).h * m.scale, 0.3, 8)
	if m.customArt && !m.frames.isEmpty && !m.frames[0].isBlank, let f0 = frames.first {
		let bb: (Int, Int, Int, Int) = opaqueBounds(f0)
		let oh: Double = Double(bb.3 - bb.1 + 1)
		return makeSpriteSet(frames, hitH: h, fixedScale: h * 1.05 / max(1.0, oh), anim: anim)
	}
	let look: CreatureLook = creatureLook(base, 0)
	return makeSpriteSet(frames, hitH: h, fixedScale: look.scale * m.scale, anim: anim, foot: look.foot, cx: look.cx)
}

/// The sprites of a custom creature, sized to its hit box
func modMobSpriteSet(_ m: ModMob) -> SpriteSet {
	let fr: ([PixelBuf], CreatureAnim) = modMobFrames(m)
	return modMobSet(m, fr.0, fr.1)
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
		// a vehicle's kit builds the vehicle
		if ModRuntime.shared.vehicles[k] != nil {
			if pressed && useCD <= 0 { placeModVehicle(k) }
			return
		}
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
		case .seat:
			sitOn(tx, ty)
		case .bed:
			sleepIn(tx, ty)
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
		return stationAboard(t)
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
