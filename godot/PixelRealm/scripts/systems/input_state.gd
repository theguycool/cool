class_name InputState
extends RefCounted
## Everything the controls are doing right now, written by the touch sticks and buttons, the keyboard
## and the mouse, and read by the player each frame. The walking stick, JUMP, the attack stick and a
## finger on the world are separate, so any of them can be used together and letting go of one never
## affects the others.

## walking stick (or A/D): -1 left .. 1 right; and up (-1) / down (1) for ladders and dropping down
var move_x: float = 0.0
var move_y: float = 0.0
var jump: bool = false
var down: bool = false
## the attack stick (or the F key): held, and when the thumb is out past the dead zone its direction
var attack_held: bool = false
var attack_manual: bool = false
var attack_dir := Vector2.RIGHT
var attack_power: float = 0.0
## a finger (or the mouse) on the world: where, since when, and whether it has moved
var pointer_down: bool = false
var pointer_world := Vector2.ZERO
var pointer_start := Vector2.ZERO
var pointer_time: float = 0.0
var pointer_moved: bool = false
## a quick tap that has just ended (interact with a door, chest, station...)
var tap_world := Vector2.ZERO
var tap_pending: bool = false

## the attack stick's dead zone (share of its radius): leave `DEAD_IN` to aim by hand, come back
## inside `DEAD_OUT` to hand the aim back (the gap stops it flickering at the edge)
const DEAD_IN := 0.26
const DEAD_OUT := 0.17


## A thumb on the attack stick at (x, y), in stick radii from its centre
func attack_stick_at(v: Vector2) -> void:
	var length: float = v.length()
	attack_power = minf(1.0, length)
	attack_manual = attack_power > (DEAD_OUT if attack_manual else DEAD_IN)
	if attack_manual and length > 0.0001:
		attack_dir = v / length
	attack_held = true


func attack_stick_released() -> void:
	attack_held = false
	attack_manual = false
	attack_power = 0.0


func pointer_press(world_pos: Vector2) -> void:
	pointer_down = true
	pointer_world = world_pos
	pointer_start = world_pos
	pointer_time = 0.0
	pointer_moved = false


func pointer_move(world_pos: Vector2) -> void:
	pointer_world = world_pos
	if world_pos.distance_to(pointer_start) > 6.0:
		pointer_moved = true


func pointer_release() -> void:
	if pointer_down and not pointer_moved and pointer_time < 0.3:
		tap_world = pointer_start
		tap_pending = true
	pointer_down = false


## Drops every held control (a panel opened over them, the game paused, the player died)
func release_all() -> void:
	move_x = 0.0
	move_y = 0.0
	jump = false
	down = false
	attack_stick_released()
	pointer_down = false
	tap_pending = false
