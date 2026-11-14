// Creatures: their kinds and numbers (from the Swift game through the exporter), drops, spawn rules
// and one creature's state (the Swift game's p13a_mobdefs).

/** every creature kind by key ("zombie"): name, size, health, speed, blows, behaviour, art */
const MOBS = {};
const MOB_BY_ID = [];
for (const m of DATA.mobs) { MOBS[m.key] = m; MOB_BY_ID[m.id] = m; }
const mobDef = (k) => MOBS[k];

const PREDATORS = new Set(["grizzly", "polarBear", "tiger", "scorpion"]);
const WILD_ANIMALS = new Set(["elephant", "bear", "wolf", "grizzly", "polarBear", "tiger", "scorpion"]);
const PREY = new Set(["pig", "cow", "sheep", "chicken", "giraffe", "frog", "cat"]);
const UNDEAD = new Set(["zombie", "skeleton", "archer", "wraith"]);
const HEAT_IMMUNE = new Set(["imp", "emberSlime", "cinderBat", "warden"]);
const BOSS_KINDS = new Set(["bearBoss", "rex", "sentinel", "warden"]);
const isPredator = (k) => PREDATORS.has(k);
const isWildAnimal = (k) => WILD_ANIMALS.has(k);
const isPrey = (k) => PREY.has(k);
const isUndead = (k) => UNDEAD.has(k);
const isHumanoid = (k) => !!MOBS[k].humanoid;
const thinks = (k) => !!MOBS[k].thinks;

/** What a creature drops: [item, least, most, chance] (the Swift game's mobDrops) */
const MOB_DROPS = {
	pig: [["food:rawMeat", 1, 3, 1]],
	cow: [["food:rawMeat", 2, 4, 1], ["mat:leather", 1, 2, 0.8]],
	sheep: [["food:rawMeat", 1, 2, 1], ["mat:wool", 1, 3, 0.9, "wool"]],
	chicken: [["food:rawMeat", 1, 1, 0.9], ["mat:feather", 1, 3, 0.9]],
	crow: [["mat:feather", 1, 2, 0.8]],
	giraffe: [["food:rawMeat", 2, 4, 1], ["mat:leather", 2, 4, 0.9]],
	frog: [["mat:string", 0, 1, 0.1]],
	fish: [["food:rawFish", 1, 1, 1]],
	elephant: [["food:rawMeat", 4, 7, 1], ["mat:tusk", 1, 2, 0.8], ["mat:leather", 2, 4, 0.9]],
	bear: [["food:rawMeat", 2, 4, 1], ["mat:fur", 1, 3, 0.9], ["mat:claw", 1, 1, 0.3]],
	grizzly: [["food:rawMeat", 3, 5, 1], ["mat:fur", 2, 4, 1], ["mat:claw", 1, 2, 0.6]],
	polarBear: [["food:rawMeat", 3, 5, 1], ["mat:fur", 2, 4, 1], ["mat:claw", 1, 2, 0.5]],
	tiger: [["food:rawMeat", 2, 4, 1], ["mat:leather", 1, 3, 0.9], ["mat:claw", 1, 2, 0.6]],
	wolf: [["food:rawMeat", 1, 2, 0.9], ["mat:fur", 1, 2, 0.6], ["mat:bone", 1, 2, 0.4]],
	cat: [["mat:string", 1, 2, 0.5]],
	zombie: [["food:rawMeat", 0, 1, 0.3], ["mat:string", 0, 2, 0.3], ["food:carrot", 1, 1, 0.08], ["mat:ironBar", 1, 1, 0.04]],
	skeleton: [["mat:bone", 1, 3, 0.9], ["ammo:arrow", 2, 6, 0.5], ["sword:stone", 1, 1, 0.06], ["mat:coal", 1, 3, 0.4]],
	slime: [["mat:string", 1, 2, 0.4], ["block:torch", 1, 3, 0.3]],
	bat: [["mat:string", 0, 1, 0.2]],
	scorpion: [["mat:claw", 1, 1, 0.5], ["food:rawMeat", 1, 1, 0.5]],
	wraith: [["mat:mythrilOre", 1, 2, 0.4], ["mat:goldBar", 1, 2, 0.3]],
	pirate: [["mat:goldBar", 1, 2, 0.5], ["ammo:bullet", 2, 6, 0.4], ["mat:gunpowder", 1, 3, 0.5], ["sword:iron", 1, 1, 0.1], ["gadget:bomb", 1, 2, 0.15]],
	pirateGunner: [["mat:goldBar", 1, 2, 0.5], ["ammo:bullet", 3, 8, 0.7], ["mat:gunpowder", 1, 4, 0.7], ["gun:pistol", 1, 1, 0.12]],
	pirateCaptain: [["mat:goldBar", 4, 8, 1], ["mat:diamond", 1, 3, 0.8], ["gun:rifle", 1, 1, 0.4], ["ammo:bullet", 8, 16, 1]],
	imp: [["mat:emberOre", 1, 2, 0.5], ["mat:coal", 2, 4, 0.6]],
	emberSlime: [["mat:emberOre", 1, 3, 0.6], ["block:torch", 2, 5, 0.5]],
	cinderBat: [["mat:emberOre", 0, 1, 0.3]],
	bearBoss: [["mat:fur", 6, 10, 1], ["mat:claw", 3, 5, 1], ["mat:goldBar", 6, 12, 1], ["mat:diamond", 3, 6, 1], ["food:cookedMeat", 6, 10, 1], ["armor:chest:gold", 1, 1, 0.5]],
	rex: [["mat:bone", 10, 20, 1], ["mat:tusk", 2, 4, 1], ["mat:goldBar", 6, 12, 1], ["mat:mythrilBar", 2, 5, 1], ["food:cookedMeat", 6, 10, 1]],
	crawler: [["mat:string", 1, 3, 0.8], ["mat:claw", 1, 1, 0.25]],
	golem: [["block:stone", 4, 8, 1], ["mat:ironOre", 1, 3, 0.6], ["mat:crystalShard", 1, 2, 0.35], ["mat:relicFragment", 1, 1, 0.1]],
	archer: [["food:rawMeat", 0, 1, 0.3], ["mat:string", 0, 2, 0.4], ["ammo:arrow", 3, 8, 0.8], ["bow", 1, 1, 0.05]],
	sentinel: [["mat:crystalShard", 8, 14, 1], ["mat:diamond", 2, 4, 1], ["block:glowCrystal", 4, 8, 1], ["mat:relicFragment", 2, 3, 1], ["gear:headlamp", 1, 1, 0.35]],
	mimic: [["mat:goldBar", 2, 5, 1], ["mat:relicFragment", 1, 1, 0.8], ["mat:diamond", 1, 2, 0.35]],
	warden: [["mat:umbralHeart", 1, 1, 1], ["mat:voidBar", 6, 10, 1], ["mat:diamond", 4, 8, 1], ["mat:emberBar", 4, 8, 1], ["mat:relicFragment", 3, 3, 1]],
};
function mobDrops(k, rng, sheared) {
	const out = [];
	for (const [id, lo, hi, p, tag] of MOB_DROPS[k] || []) {
		if (tag === "wool" && sheared) continue;
		if (rng.double() < p) { const n = lo + rng.int(Math.max(1, hi - lo + 1)); if (n > 0) out.push(stack(id, n)); }
	}
	return out;
}

// ---- spawn rules: [kind, weight, place, when, biomes, group, minY]
const SPAWN_RULES = [
	["pig", 5, "surface", "any", ["plains", "forest"], 2], ["cow", 5, "surface", "any", ["plains", "forest"], 2],
	["sheep", 5, "surface", "any", ["plains", "forest", "mountain"], 3], ["chicken", 4, "surface", "day", ["plains", "forest", "savanna"], 3],
	["crow", 3, "surface", "any", ["plains", "forest", "desert", "savanna", "swamp", "mountain"], 2],
	["giraffe", 5, "surface", "any", ["savanna"], 2], ["elephant", 3, "surface", "any", ["savanna", "jungle"], 1],
	["tiger", 3, "surface", "any", ["jungle", "savanna"], 1], ["bear", 3, "surface", "any", ["forest", "mountain"], 1],
	["grizzly", 2, "surface", "any", ["mountain", "forest"], 1], ["polarBear", 4, "surface", "any", ["tundra"], 1],
	["wolf", 3, "surface", "night", ["tundra", "forest", "plains"], 3], ["frog", 5, "surface", "any", ["swamp"], 2],
	["scorpion", 5, "surface", "any", ["desert"], 1],
	["zombie", 7, "surface", "night", [], 2], ["slime", 3, "surface", "night", ["plains", "forest", "jungle", "swamp"], 1],
	["fish", 8, "ocean", "any", [], 4],
	["skeleton", 6, "cave", "any", [], 2, 150], ["zombie", 2, "cave", "any", [], 1, 140], ["slime", 3, "cave", "any", [], 2, 140],
	["bat", 4, "cave", "any", [], 3, 150], ["wraith", 2, "cave", "any", [], 1, 380], ["crawler", 4, "cave", "any", [], 2, 140],
	["archer", 3, "cave", "any", [], 1, 150], ["golem", 1.5, "cave", "any", [], 1, 260],
	["archer", 2, "surface", "night", [], 1], ["skeleton", 2, "surface", "night", ["plains", "desert", "tundra", "mountain", "savanna"], 1],
	["crawler", 2, "surface", "night", ["jungle", "swamp", "forest"], 2],
	["imp", 5, "umbral", "any", [], 1], ["wraith", 3, "umbral", "any", [], 1], ["emberSlime", 5, "umbral", "any", [], 2], ["cinderBat", 4, "umbral", "any", [], 3],
].map(([kind, weight, place, when, biomes, group, minY]) => ({ kind, weight, place, when, biomes: biomes.map((b) => Biome[b]), group, minY: minY || 0, maxY: 9999 }));

let mobSerial = 0;
/** one creature (the Swift game's Mob): its body, health, timers and its mind's state */
function makeMob(kind, x, y) {
	const d = MOBS[kind];
	return {
		id: ++mobSerial, kind, def: d, b: makeBody(x, y, d.w, d.h), hp: d.hp, maxHP: d.hp,
		dir: Math.random() < 0.5 ? -1 : 1, anim: 0, hurtT: 0, cd: 0, t1: rand(0.5, 3), t2: 0, t3: 0, st: 0, variant: 0,
		tame: false, angry: false, persistent: false, sheared: false, blocking: false, boat: -1, burn: 0,
		homeX: x, homeY: y, lastX: x, downed: false, lair: 0, phase: 0, atk: 0, tx: 0, ty: 0, regrow: 0, knock: 0,
		aiAccum: 0, removed: false, flash: 0, deathT: -1, lean: 0, hazardT: 0, lastAttacker: 0, lastHitByPlayer: -100,
		hitStamps: new Map(), fallPeak: 0, burnTick: 0, face: 0, turnT: 0, atkT: 0, loot: [], thinkT: 0,
		lastAtk: 0, repeatN: 0, sinceSignature: 0, goal: 0, goalX: 0, drinkT: 0, preyID: 0, prey: null, poseT: 0,
		daze: 0, dazeGuard: 0, ai: "idle", aiT: 0, sees: false, losT: 0, seenX: 0, seenY: 0, lostT: 99, aimX: x,
		blockedT: 0, progX: x, leapT: 0, leapReq: false, why: "", hunter: false, farT: 0,
		slowT: 0, slowAmt: 0, poisonT: 0, weakT: 0, mut: 0, mutSize: 1, mutDmg: 1,
	};
}
const MOB_TURN = 0.14, MOB_ATK = 0.28;
const mobCY = (m) => m.b.y - m.b.h * 0.5;
const isBossMob = (m) => BOSS_KINDS.has(m.kind) && !m.tame;
const mobDmgMul = (m) => m.mutDmg * (m.weakT > 0 ? 0.6 : 1);
const mobSpeedMul = (m) => m.slowT > 0 ? Math.max(0.2, 1 - m.slowAmt) : 1;
