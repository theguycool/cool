class_name Weather
extends Node
## The weather, as in the Swift game: one spell after another (clear, partly cloudy, overcast, light
## and heavy rain, thunderstorms, strong wind, windstorms, hail, snowfall, blizzards, tornadoes and
## hurricanes), each with its cloud, rain, wind, gusts and thunder easing in. Rain falls as snow in
## cold country. Lightning strikes the highest point near where it lands (a lightning rod takes every
## strike within fourteen blocks), wind leans on the player, snow and ice make footing slippery,
## big hail hurts the uncovered, and a tornado drags and throws what it crosses.

const KINDS := ["clear", "partlyCloudy", "overcast", "lightRain", "heavyRain", "thunderstorm", "strongWind", "windstorm",
	"hailstorm", "snowfall", "blizzard", "tornado", "hurricane"]
const NAMES := {"clear": "Clear", "partlyCloudy": "Partly cloudy", "overcast": "Overcast", "lightRain": "Light rain",
	"heavyRain": "Heavy rain", "thunderstorm": "Thunderstorm", "strongWind": "Strong wind", "windstorm": "Windstorm",
	"hailstorm": "Hailstorm", "snowfall": "Snowfall", "blizzard": "Blizzard", "tornado": "Tornado", "hurricane": "Hurricane"}
## cloud, precipitation, wind (blocks/s), gusts, thunder (strikes per minute), hail, cover, chill
const PROFILE := {
	"clear": [0.04, 0.0, 1.2, 0.25, 0.0, 0.0, 0.0, 0.0],
	"partlyCloudy": [0.35, 0.0, 2.4, 0.35, 0.0, 0.0, 0.0, 0.0],
	"overcast": [0.72, 0.0, 3.0, 0.35, 0.0, 0.0, 0.0, 0.0],
	"lightRain": [0.78, 0.38, 3.0, 0.4, 0.0, 0.0, 0.55, 0.0],
	"heavyRain": [0.9, 0.85, 5.0, 0.5, 0.0, 0.0, 0.8, 0.0],
	"thunderstorm": [1.0, 0.9, 7.0, 0.7, 6.0, 0.0, 0.75, 0.0],
	"strongWind": [0.4, 0.0, 9.0, 0.6, 0.0, 0.0, 0.3, 0.0],
	"windstorm": [0.7, 0.15, 14.0, 0.8, 0.0, 0.0, 0.4, 0.0],
	"hailstorm": [0.95, 0.55, 6.0, 0.6, 2.0, 1.0, 0.6, 0.0],
	"snowfall": [0.8, 0.6, 2.5, 0.4, 0.0, 0.0, 0.85, 0.2],
	"blizzard": [1.0, 1.0, 13.0, 0.7, 0.0, 0.0, 1.0, 1.0],
	"tornado": [1.0, 0.75, 8.0, 0.8, 5.0, 0.25, 0.7, 0.0],
	"hurricane": [1.0, 1.0, 15.0, 0.8, 2.0, 0.0, 1.0, 0.0],
}
const SPELL := {"clear": [180, 420], "partlyCloudy": [150, 300], "overcast": [120, 240], "lightRain": [90, 200],
	"heavyRain": [70, 150], "thunderstorm": [80, 150], "strongWind": [70, 140], "windstorm": [60, 110], "hailstorm": [35, 70],
	"snowfall": [120, 240], "blizzard": [80, 150], "tornado": [95, 120], "hurricane": [330, 440]}
## what can follow each kind, with weights
const NEXT := {
	"clear": [["clear", 3], ["partlyCloudy", 4], ["strongWind", 1]],
	"partlyCloudy": [["clear", 3], ["partlyCloudy", 2], ["overcast", 3], ["strongWind", 1]],
	"overcast": [["partlyCloudy", 3], ["overcast", 1], ["lightRain", 3], ["heavyRain", 2], ["snowfall", 1], ["windstorm", 1],
		["hailstorm", 1], ["thunderstorm", 2], ["hurricane", 0.2]],
	"lightRain": [["overcast", 3], ["heavyRain", 2], ["thunderstorm", 1], ["partlyCloudy", 2]],
	"heavyRain": [["lightRain", 3], ["overcast", 2], ["thunderstorm", 2]],
	"thunderstorm": [["heavyRain", 3], ["lightRain", 2], ["overcast", 2], ["tornado", 0.4]],
	"strongWind": [["partlyCloudy", 3], ["clear", 2], ["strongWind", 1], ["windstorm", 1]],
	"windstorm": [["strongWind", 3], ["overcast", 2]],
	"hailstorm": [["lightRain", 3], ["overcast", 2]],
	"snowfall": [["overcast", 3], ["blizzard", 1], ["snowfall", 1]],
	"blizzard": [["snowfall", 3], ["overcast", 2]],
	"tornado": [["thunderstorm", 3], ["overcast", 2]],
	"hurricane": [["heavyRain", 3], ["overcast", 2]],
}

var kind: String = "clear"
var spell_t: float = 0.0
var spell_dur: float = 300.0
var plan: Array = []
var cloud: float = 0.04
var precip: float = 0.0
var wind: float = 1.2
var wind_dir: float = 1.0
var gust: float = 0.0
var thunder: float = 0.0
var hail: float = 0.0
var cover: float = 0.0
var chill: float = 0.0
var cloud_drift: float = 0.0
var sky_flash: float = 0.0
var t: float = 0.0
var strike_t: float = 10.0
var hail_t: float = 0.0
var tornado_x: float = 0.0
var tornado_on: bool = false
var announced: String = ""


func _ready() -> void:
	spell_dur = randf_range(180.0, 420.0)
	_extend_plan()


func name_of(k: String) -> String:
	return String(NAMES.get(k, k))


func _extend_plan() -> void:
	while plan.size() < 3:
		var last: String = kind if plan.is_empty() else String(plan[plan.size() - 1]["kind"])
		var nk: String = _pick_next(last)
		var sp: Array = SPELL[nk]
		plan.append({"kind": nk, "dur": randf_range(float(sp[0]), float(sp[1]))})


## Whether the settings let this kind of weather happen
func allowed(k: String) -> bool:
	match k:
		"lightRain", "heavyRain", "snowfall":
			return bool(Game.setting("allow_rain", true))
		"thunderstorm":
			return bool(Game.setting("allow_thunder", true))
		"strongWind", "windstorm":
			return bool(Game.setting("allow_wind", true))
		"hailstorm":
			return bool(Game.setting("allow_hail", true))
		"blizzard":
			return bool(Game.setting("allow_blizzard", true))
		"tornado":
			return bool(Game.setting("allow_tornado", true))
		"hurricane":
			return bool(Game.setting("allow_hurricane", true))
	return true


func _pick_next(from: String) -> String:
	var all: Array = NEXT.get(from, [["clear", 1]])
	var opts: Array = []
	for o in all:
		if allowed(String((o as Array)[0])):
			opts.append(o)
	if opts.is_empty():
		return "partlyCloudy"
	var total: float = 0.0
	for o in opts:
		total += float(o[1])
	var r: float = randf() * total
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return String(o[0])
	return String(opts[0][0])


## Whether the weather here is cold enough for snow (cold biomes, high ground)
func is_cold(lv: Level) -> bool:
	var px: int = floori(lv.player.global_position.x / 8.0)
	var b: int = lv.gen.biome_at(px)
	return b == WorldGen.TUNDRA or (b == WorldGen.MOUNTAIN and lv.gen.surface_at(px) < 80) or chill > 0.5


func update_weather(lv: Level, delta: float) -> void:
	t += delta
	sky_flash = maxf(0.0, sky_flash - delta * 3.0)
	if not bool(Game.setting("weather", true)) or lv.dim != WorldGen.DIM_OVERWORLD:
		_ease(PROFILE["clear"] if lv.dim == WorldGen.DIM_OVERWORLD else [0.0, 0.0, 0.5, 0.2, 0.0, 0.0, 0.0, 0.0], delta)
		_loops(lv, true)
		return
	spell_t += delta
	if spell_t >= spell_dur:
		var nxt: Dictionary = plan.pop_front()
		kind = String(nxt["kind"])
		if is_cold(lv):
			if kind == "lightRain" or kind == "heavyRain":
				kind = "snowfall"
			elif kind == "thunderstorm" or kind == "hurricane":
				kind = "blizzard" if allowed("blizzard") else "snowfall"
		# the settings may have changed since this spell was planned
		if not allowed(kind):
			kind = "overcast"
		spell_dur = float(nxt["dur"])
		spell_t = 0.0
		_extend_plan()
		_announce(lv)
		if kind == "tornado":
			tornado_on = true
			tornado_x = lv.player.global_position.x + (1.0 if randf() < 0.5 else -1.0) * 600.0
			wind_dir = 1.0 if tornado_x < lv.player.global_position.x else -1.0
		else:
			tornado_on = false
		if randf() < 0.5:
			wind_dir = -wind_dir
	_ease(PROFILE[kind], delta)
	cloud_drift += (wind * 0.16 * wind_dir + 0.25) * delta
	_lightning(lv, delta)
	_hail(lv, delta)
	_tornado(lv, delta)
	_loops(lv, false)


## The debug menu: switch to a kind of weather now (it then runs its usual course)
func force(lv: Level, k: String) -> void:
	if not PROFILE.has(k):
		return
	kind = k
	spell_t = 0.0
	spell_dur = 240.0
	tornado_on = k == "tornado"
	if tornado_on:
		tornado_x = lv.player.global_position.x + (1.0 if randf() < 0.5 else -1.0) * 400.0
		wind_dir = 1.0 if tornado_x < lv.player.global_position.x else -1.0
	# jump most of the way to the new weather so it shows at once
	var p: Array = PROFILE[k]
	cloud = lerpf(cloud, float(p[0]), 0.8)
	precip = lerpf(precip, float(p[1]), 0.8)
	wind = lerpf(wind, float(p[2]), 0.8)
	thunder = lerpf(thunder, float(p[4]), 0.8)
	hail = lerpf(hail, float(p[5]), 0.8)
	cover = lerpf(cover, float(p[6]), 0.8)
	chill = lerpf(chill, float(p[7]), 0.8)
	_announce(lv)


func _ease(p: Array, delta: float) -> void:
	var k: float = minf(1.0, delta / 25.0)
	cloud = lerpf(cloud, float(p[0]), k)
	precip = lerpf(precip, float(p[1]), k)
	wind = lerpf(wind, float(p[2]), k)
	thunder = lerpf(thunder, float(p[4]), k)
	hail = lerpf(hail, float(p[5]), k)
	cover = lerpf(cover, float(p[6]), k)
	chill = lerpf(chill, float(p[7]), k)
	gust = sin(t * 0.7) * 0.5 + sin(t * 1.9 + 1.3) * 0.5
	gust *= float(p[3])


func _announce(lv: Level) -> void:
	var warn: String = ""
	match kind:
		"thunderstorm":
			warn = "A thunderstorm is coming. Lightning strikes the highest thing near it."
			lv.journal.add_lore("wx.lightning")
		"windstorm":
			warn = "Windstorm! Hold on to your footing."
			lv.journal.add_lore("wx.wind")
		"hailstorm":
			warn = "Hail is falling. Get under a roof."
			lv.journal.add_lore("wx.hail")
		"blizzard":
			warn = "Blizzard! Find shelter and a fire."
			lv.journal.add_lore("wx.blizzard")
		"tornado":
			warn = "TORNADO WARNING: a funnel is coming. Get underground!"
			lv.journal.add_lore("wx.tornado")
		"hurricane":
			warn = "HURRICANE WARNING: days of wind and rain are coming in off the sea."
			lv.journal.add_lore("wx.hurricane")
	if warn != "" and bool(Game.setting("weather_alerts", true)):
		Sfx.play("weatherAlert", 0.7)
		lv.say(warn, 5.0)


## How hard it rains (or snows) where the player stands (0..1)
func rain_here(lv: Level) -> float:
	if lv.dim != WorldGen.DIM_OVERWORLD or precip < 0.02:
		return 0.0
	var x: float = lv.player.global_position.x / 8.0
	var patch: float = PRNG.noise1(x / 90.0 + t * 0.004, 4411)
	var covered: float = clampf((cover - patch) * 4.0 + 0.5, 0.0, 1.0) if cover < 0.99 else 1.0
	return precip * covered


func snowing(lv: Level) -> bool:
	return is_cold(lv) or kind == "snowfall" or kind == "blizzard"


## How much the clouds darken the day (0..1)
func darkness() -> float:
	return clampf((cloud - 0.6) * 1.5, 0.0, 0.6) + (0.2 if kind == "thunderstorm" or kind == "hurricane" else 0.0)


func _exposed(lv: Level, pos: Vector2) -> bool:
	var x: int = floori(pos.x / 8.0)
	return floori((pos.y - 14.0) / 8.0) < lv.world.sky_top(x)


## Extra sideways speed the wind gives the player (px/s); only out in the open
func wind_push(lv: Level, on_floor: bool) -> float:
	if lv.dim != WorldGen.DIM_OVERWORLD or wind < 5.0 or not _exposed(lv, lv.player.global_position):
		return 0.0
	var w: float = (wind + gust * 3.0 - 5.0) * wind_dir
	return w * (1.6 if on_floor else 2.4)


func walk_scale(lv: Level) -> float:
	if kind == "blizzard" and _exposed(lv, lv.player.global_position) and not lv.player.inv.wearing("gear:snowBoots"):
		return 0.75
	return 1.0


func slip(lv: Level) -> float:
	if snowing(lv) and precip > 0.4 and _exposed(lv, lv.player.global_position):
		return 0.35
	return 0.0


## a strike about to land near the player: {"x", "top", "t"} (the ground glows and crackles first)
var pending_strike := {}


func _lightning(lv: Level, delta: float) -> void:
	if not pending_strike.is_empty():
		pending_strike["t"] = float(pending_strike["t"]) - delta
		var mx: int = int(pending_strike["x"])
		var mt: int = int(pending_strike["top"])
		lv.effects.marks = [[Vector2(mx * 8 + 4, mt * 8), 14.0, float(pending_strike["t"]), 1.4]]
		if float(pending_strike["t"]) <= 0.0:
			pending_strike = {}
			lv.effects.marks = []
			_strike(lv, mx, mt)
		return
	if thunder < 0.3:
		return
	strike_t -= delta
	if strike_t > 0.0:
		return
	strike_t = 60.0 / thunder * randf_range(0.5, 1.5)
	var p: Player = lv.player
	var x: int = floori(p.global_position.x / 8.0) + randi_range(-50, 50)
	if not lv.world.is_loaded_x(x):
		return
	# a lightning rod nearby takes the strike
	var top: int = lv.world.sky_top(x)
	for dx in range(-14, 15):
		var rx: int = x + dx
		var rt: int = lv.world.sky_top(rx)
		if lv.world.get_tile(rx, rt) == T.LIGHTNING_ROD:
			x = rx
			top = rt
			break
	# close to the player and not drawn by a rod: the spot glows and crackles before it strikes
	if lv.world.get_tile(x, top) != T.LIGHTNING_ROD and absi(x - floori(p.global_position.x / 8.0)) < 26:
		pending_strike = {"x": x, "top": top, "t": 1.4}
		Sfx.play("strikeWarn", 0.8)
		return
	_strike(lv, x, top)


func _strike(lv: Level, x: int, top: int) -> void:
	var p: Player = lv.player
	var from := Vector2(x * 8 + 4, (top - 40) * 8)
	var to := Vector2(x * 8 + 4, top * 8)
	var pts: Array = [from]
	for k in range(1, 6):
		pts.append(from.lerp(to, float(k) / 6.0) + Vector2(randf_range(-10.0, 10.0), 0))
	pts.append(to)
	lv.effects.lightning(pts, 0.3)
	sky_flash = 1.0 if not bool(Game.setting("reduce_flashes", false)) else 0.4
	var near: bool = absf(to.x - p.global_position.x) < 160.0
	Sfx.play("thunderNear" if near else "thunderFar", 1.0 if near else 0.6)
	if lv.world.get_tile(x, top) != T.LIGHTNING_ROD:
		if p.global_position.distance_to(to) < 20.0 and bool(Game.setting("weather_hurts", true)):
			p.hurt(8.0, to.x, 6.0, true, "lightning")
			p.burn = maxf(p.burn, 2.0)
		for m in lv.mobs_near(to.x - 20.0, to.x + 20.0):
			(m as Mob).take_damage({"amount": 12.0, "from": to, "knock": 6.0, "by_player": false, "shock": true})


func _hail(lv: Level, delta: float) -> void:
	if hail < 0.3 or not bool(Game.setting("weather_hurts", true)):
		return
	hail_t -= delta
	if hail_t > 0.0:
		return
	hail_t = randf_range(1.5, 3.5)
	var p: Player = lv.player
	if _exposed(lv, p.global_position) and p.inv.armor_tier(0) == 0 and randf() < hail * 0.5:
		p.hurt(1.0, p.global_position.x, 0.0, true, "hail")
		Sfx.play("hailTick", 0.6)


func _tornado(lv: Level, delta: float) -> void:
	if not tornado_on:
		return
	tornado_x += wind_dir * 36.0 * delta
	var p: Player = lv.player
	var dx: float = tornado_x - p.global_position.x
	if absf(dx) < 80.0 and _exposed(lv, p.global_position):
		p.velocity.x += signf(dx) * 160.0 * delta
		if absf(dx) < 24.0:
			p.velocity.y = minf(p.velocity.y, -120.0)
			if randf() < delta * 0.5 and bool(Game.setting("weather_hurts", true)):
				p.hurt(2.0, tornado_x, 8.0, true, "tornado")
	for m in lv.mobs_near(tornado_x - 40.0, tornado_x + 40.0):
		var mm: Mob = m
		if not mm.is_boss():
			mm.velocity.y = minf(mm.velocity.y, -100.0)
			mm.velocity.x += signf(tornado_x - mm.global_position.x) * 200.0 * delta


func _loops(lv: Level, quiet: bool) -> void:
	if quiet:
		for n in ["rain", "heavyRain", "wind", "gale", "hail", "tornado"]:
			Sfx.set_loop(n, 0.0)
		return
	var exposed: bool = _exposed(lv, lv.player.global_position)
	var r: float = rain_here(lv) * (1.0 if exposed else 0.4)
	var snow: bool = snowing(lv)
	Sfx.set_loop("rain", 0.0 if snow else clampf(r * 1.4, 0.0, 0.8))
	Sfx.set_loop("heavyRain", 0.0 if snow else clampf((r - 0.5) * 2.0, 0.0, 1.0))
	Sfx.set_loop("wind", clampf((wind - 2.0) / 8.0, 0.0, 0.6) * (1.0 if exposed else 0.4))
	Sfx.set_loop("gale", clampf((wind - 9.0) / 6.0, 0.0, 1.0) * (1.0 if exposed else 0.3))
	Sfx.set_loop("hail", clampf(hail, 0.0, 1.0) * (1.0 if exposed else 0.5))
	Sfx.set_loop("tornado", clampf(1.0 - absf(tornado_x - lv.player.global_position.x) / 600.0, 0.0, 1.0) if tornado_on else 0.0)


func barometer_text() -> String:
	var next: String = String(plan[0]["kind"]) if not plan.is_empty() else kind
	var bad: Array = ["thunderstorm", "hailstorm", "blizzard", "tornado", "hurricane", "windstorm", "heavyRain"]
	if bad.has(next):
		return "The needle is falling fast: %s on the way." % name_of(next).to_lower()
	if next == "clear" or next == "partlyCloudy":
		return "The needle is rising: fair weather ahead."
	return "The needle is steady: %s next." % name_of(next).to_lower()


func forecast() -> Array:
	var out: Array = [[name_of(kind), maxf(0.0, spell_dur - spell_t)]]
	for p in plan:
		out.append([name_of(String(p["kind"])), float(p["dur"])])
	return out


func to_save() -> Dictionary:
	return {"kind": kind, "spell_t": spell_t, "spell_dur": spell_dur, "plan": plan, "cloud": cloud, "precip": precip,
		"wind": wind, "wind_dir": wind_dir, "drift": cloud_drift}


func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	kind = String(d.get("kind", "clear"))
	if not PROFILE.has(kind):
		kind = "clear"
	spell_t = float(d.get("spell_t", 0.0))
	spell_dur = float(d.get("spell_dur", 300.0))
	plan = []
	for p in d.get("plan", []):
		if p is Dictionary and PROFILE.has(String(p.get("kind", ""))):
			plan.append({"kind": String(p["kind"]), "dur": float(p.get("dur", 200.0))})
	_extend_plan()
	cloud = float(d.get("cloud", 0.04))
	precip = float(d.get("precip", 0.0))
	wind = float(d.get("wind", 1.2))
	wind_dir = float(d.get("wind_dir", 1.0))
	cloud_drift = float(d.get("drift", 0.0))
	tornado_on = kind == "tornado"
