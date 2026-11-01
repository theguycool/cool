extends Node
## Sound effects and ambience (autoload "Sfx"). Every effect has three recorded variants (exported
## from the Swift game's synthesiser), picked at random; loops (rain, wind, engine...) fade in and out.

const MiscData = preload("res://scripts/data/misc_data.gd")
const VOICES := 10

var sfx_volume: float = 0.7
var ambience_volume: float = 0.5
var enabled: bool = true
var _streams := {}
var _players: Array = []
var _next: int = 0
var _last := {}
var _loops := {}
var _loop_target := {}

const MIN_GAP := {"pickup": 0.05, "tap": 0.05, "digStone": 0.09, "digDirt": 0.09, "digWood": 0.09, "digSand": 0.09,
	"digCrystal": 0.09, "digLeaves": 0.09, "hit": 0.06, "arrowHit": 0.06, "land": 0.08, "place": 0.08, "door": 0.08,
	"warn": 0.35, "roar": 0.25, "portal": 0.25, "discovery": 0.25, "explosion": 0.25, "rareLoot": 0.25,
	"thunderNear": 0.3, "thunderFar": 0.5, "strikeWarn": 0.6, "weatherAlert": 2.0, "hailTick": 0.07,
	"crit": 0.05, "multiHit": 0.05, "swingLight": 0.05, "daze": 0.15, "flask": 0.15}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for loop_name in MiscData.LOOPS:
		var lp := AudioStreamPlayer.new()
		lp.volume_db = -80.0
		add_child(lp)
		var st: AudioStream = load("res://assets/sounds/loops/%s.wav" % loop_name)
		lp.stream = st
		# the recordings are seamless: start again the moment they end
		lp.finished.connect(lp.play)
		_loops[loop_name] = lp
		_loop_target[loop_name] = 0.0


func _stream(snd: String, v: int) -> AudioStream:
	var key: String = "%s_%d" % [snd, v]
	if _streams.has(key):
		return _streams[key]
	var path: String = "res://assets/sounds/sfx/%s.wav" % key
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	_streams[key] = st
	return st


## Plays an effect (names are the Swift SoundID cases: "digStone", "hit", "explosion"...)
func play(snd: String, volume: float = 1.0) -> void:
	if not enabled or sfx_volume <= 0.0 or volume <= 0.02:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var gap: float = float(MIN_GAP.get(snd, 0.04))
	if _last.has(snd) and now - float(_last[snd]) < gap:
		return
	_last[snd] = now
	var st: AudioStream = _stream(snd, randi() % 3)
	if st == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.volume_db = linear_to_db(clampf(volume, 0.0, 1.0) * sfx_volume)
	p.pitch_scale = 1.0
	p.play()


## Sets how loud an ambience loop should be (0 silent); it eases there over a second or so
func set_loop(loop_name: String, volume: float) -> void:
	if _loop_target.has(loop_name):
		_loop_target[loop_name] = clampf(volume, 0.0, 1.0)


func stop_loops() -> void:
	for loop_name in _loop_target.keys():
		_loop_target[loop_name] = 0.0


func _process(delta: float) -> void:
	for loop_name in _loops.keys():
		var lp: AudioStreamPlayer = _loops[loop_name]
		var target: float = float(_loop_target[loop_name]) * ambience_volume if enabled else 0.0
		var cur: float = db_to_linear(lp.volume_db) if lp.playing else 0.0
		cur = move_toward(cur, target, delta * 0.8)
		if cur <= 0.001:
			if lp.playing:
				lp.stop()
			lp.volume_db = -80.0
		else:
			lp.volume_db = linear_to_db(cur)
			if not lp.playing:
				lp.play()


## The sound a block makes when dug or broken
func dig_sound(tile_id: int, broke: bool) -> String:
	var m: int = DB.sound_mat[tile_id]
	if broke:
		match m:
			0: return "breakStone"
			2: return "breakWood"
			4: return "breakCrystal"
			_: return "breakDirt"
	match m:
		0: return "digStone"
		1: return "digDirt"
		2: return "digWood"
		3: return "digSand"
		4: return "digCrystal"
		_: return "digLeaves"
