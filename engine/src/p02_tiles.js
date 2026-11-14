// Tiles: the Swift game's own table (DATA.tiles), as flat lookups by tile number.

const NT = DATA.tiles.length;
/** tile numbers by name: T.grass, T.stone ... */
const T = {};
const TILE = DATA.tiles;
for (const t of TILE) T[t.key] = t.id;
const u8table = (f) => { const a = new Uint8Array(256); for (const t of TILE) a[t.id] = f(t) ? 1 : 0; return a; };
const SOLID = u8table((t) => t.solid);
const OPAQUE = u8table((t) => t.opaque);
const LIQUID = u8table((t) => t.liquid);
const PLATFORM = u8table((t) => t.platform);
const PLANT = u8table((t) => t.plant);
const HURTS = u8table((t) => t.hurt);
const IS_LEAF = u8table((t) => t.leaf);
const IS_LOG = u8table((t) => t.log);
const SUPPORTS = u8table((t) => t.supports);
const NEEDS_SUPPORT = u8table((t) => t.needsSupport);
const MEET = u8table((t) => t.solid || t.liquid);
const RAINSTOP = u8table((t) => t.solid || t.platform || t.liquid || t.leaf || t.stair);
const LIGHT = new Uint8Array(256), STAIR = new Uint8Array(256), TIER_OF = new Uint8Array(256), TILE_FLIP = new Uint8Array(256);
const HARD = new Float64Array(256);
for (const t of TILE) { LIGHT[t.id] = t.light; STAIR[t.id] = t.stair; TIER_OF[t.id] = Math.min(255, t.tier); HARD[t.id] = t.hard; TILE_FLIP[t.id] = t.flips; }
// rows below the world are bedrock
const tileName = (t) => (TILE[t] ? TILE[t].name : "?");
const placedForm = (t) => TILE[t].placed;
const trunkForm = (t) => TILE[t].trunk;
const isModTile = (t) => TILE[t] && TILE[t].mod;
