extends Node2D
## Pixel-art player: the Brackeys knight (CC0, by analogStudios_; see
## assets/brackeys/LICENSE_AND_CREDITS.txt), animated from its sprite sheet.
## Same interface as stick_figure.gd, so the player drives either one.
##
## The sheet has idle/run/roll/hit/death; jump and fall use roll frames (as
## Brackeys did), the double jump plays the full roll, a skid uses a hit
## frame, and the wave uses two frames derived from idle
## (tools/make_knight_wave.py).

const SHEET := preload("res://assets/brackeys/knight.png")
const WAVE_SHEET := preload("res://assets/brackeys/knight_wave.png")
const CELL := 32
## The knight is 19px tall; this makes it match the 48px collision body.
const PIXEL_SCALE := 2.5
## Bottom edge of the knight's feet within a 32px cell.
const FEET_EDGE := 28
## Collision capsule bottom in player space.
const BODY_FEET_Y := 24.0
const ROLL_TIME := 0.38
const WAVE_TIME := 1.5
const RUN_FPS := 16.0

var _velocity := Vector2.ZERO
var _on_floor := true
var _facing := 1
var _skidding := false
var _roll := 0.0
var _wave := 0.0
var _sprite: AnimatedSprite2D

func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	# Put the knight's feet on the bottom of the collision body.
	_sprite.position = Vector2(0.0, BODY_FEET_Y - (FEET_EDGE - CELL * 0.5) * PIXEL_SCALE)
	add_child(_sprite)
	_sprite.play("idle")

func set_motion(velocity: Vector2, on_floor: bool, facing: int, skidding: bool = false) -> void:
	_velocity = velocity
	_on_floor = on_floor
	_facing = facing
	_skidding = skidding

func play_air_jump() -> void:
	_roll = 1.0
	_sprite.play("roll")

func play_wave() -> void:
	_wave = 1.0

func _process(delta: float) -> void:
	_roll = move_toward(_roll, 0.0, delta / ROLL_TIME)
	_wave = move_toward(_wave, 0.0, delta / WAVE_TIME)
	_sprite.flip_h = _facing < 0

	var anim: String
	var speed_scale: float = 1.0
	if _roll > 0.0:
		anim = "roll"
	elif _wave > 0.0 and _on_floor and abs(_velocity.x) < 20.0:
		anim = "wave"
	elif not _on_floor:
		anim = "jump" if _velocity.y < 0.0 else "fall"
	elif _skidding:
		anim = "skid"
	elif abs(_velocity.x) > 20.0:
		anim = "run"
		speed_scale = clamp(abs(_velocity.x) / JumpPhysics.profile.run_speed, 0.4, 1.2)
	else:
		anim = "idle"
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.speed_scale = speed_scale

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add(frames, "idle", SHEET, [[0, 0], [1, 0], [2, 0], [3, 0]], 7.0, true)
	var run_cells: Array = []
	for row in [2, 3]:
		for col in range(8):
			run_cells.append([col, row])
	_add(frames, "run", SHEET, run_cells, RUN_FPS, true)
	var roll_cells: Array = []
	for col in range(8):
		roll_cells.append([col, 5])
	_add(frames, "roll", SHEET, roll_cells, 8.0 / ROLL_TIME, false)
	_add(frames, "jump", SHEET, [[2, 5]], 1.0, false)
	_add(frames, "fall", SHEET, [[1, 5]], 1.0, false)
	_add(frames, "skid", SHEET, [[1, 6]], 1.0, false)
	_add(frames, "wave", WAVE_SHEET, [[0, 0], [1, 0]], 6.0, true)
	return frames

func _add(frames: SpriteFrames, anim: String, sheet: Texture2D, cells: Array, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for cell in cells:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(cell[0] * CELL, cell[1] * CELL, CELL, CELL)
		frames.add_frame(anim, atlas)
