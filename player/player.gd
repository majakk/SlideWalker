extends CharacterBody2D
## Movement controller: run, jump (coyote time, buffering, variable height),
## a double jump, and dropping down through the ledge you're standing on.
## Physics values come from JumpPhysics.profile, which course setup tunes
## to the loaded deck.

const ACCEL: float = 2500.0
const FRICTION: float = 3000.0
const COYOTE_TIME: float = 0.1
const JUMP_BUFFER_TIME: float = 0.1
## Ledges live on this physics layer (the stage floor and walls on layer 1),
## so dropping down can never fall through the floor.
const LEDGE_LAYER: int = 2
const DROP_THROUGH_TIME: float = 0.22
const DROP_NUDGE_SPEED: float = 120.0
## Course generation guarantees a continuous floor under every slide, so
## falling below the last solid ground should never actually happen — this
## is a defensive backstop, not a mechanic to design levels around.
## (Drop-down courses fall about one slide height between floors.)
const FALL_RESET_MARGIN: float = 2000.0
## A turn counts as a skid (dust + brake pose) above this share of run speed.
const SKID_SPEED_FRACTION: float = 0.45
## Landing faster than this kicks up dust.
const LANDING_DUST_SPEED: float = 900.0

var facing_direction: int = 1
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var air_jumps_left: int = 0
var drop_timer: float = 0.0
var last_safe_position: Vector2
var _was_skidding: bool = false
var _was_on_floor: bool = true
var _fall_speed: float = 0.0

const StickFigure = preload("res://player/stick_figure.gd")
const DustPuff = preload("res://player/dust_puff.gd")

@onready var pixel_art_visual: Node2D = $PixelArtVisual
@onready var stick_figure_visual: StickFigure = $StickFigureVisual

func _ready() -> void:
	last_safe_position = global_position
	_apply_visual_style()

## Shows the visual variant matching the style picked in the startup menu.
## Physics/collision/state logic below is identical regardless of style —
## only which child node is visible changes.
func _apply_visual_style() -> void:
	var use_stick_figure: bool = GameSettings.player_style == GameSettings.PlayerStyle.STICK_FIGURE
	stick_figure_visual.visible = use_stick_figure
	pixel_art_visual.visible = not use_stick_figure

func _physics_process(delta: float) -> void:
	var profile = JumpPhysics.profile
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		air_jumps_left = profile.air_jumps
		last_safe_position = global_position
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)
		velocity.y = min(velocity.y + profile.gravity * delta, profile.max_fall_speed)

	if drop_timer > 0.0:
		drop_timer -= delta
		if drop_timer <= 0.0:
			set_collision_mask_value(LEDGE_LAYER, true)

	var jump_pressed: bool = Input.is_action_just_pressed("jump")
	if jump_pressed:
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	var input_dir: float = Input.get_axis("move_left", "move_right")
	if input_dir != 0.0:
		velocity.x = move_toward(velocity.x, input_dir * profile.run_speed, ACCEL * delta)
		facing_direction = sign(input_dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if Input.is_action_just_pressed("move_down") and is_on_floor():
		# Only ledges stop colliding; on the stage floor this does nothing.
		set_collision_mask_value(LEDGE_LAYER, false)
		drop_timer = DROP_THROUGH_TIME
		velocity.y = DROP_NUDGE_SPEED
		coyote_timer = 0.0
	elif jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = profile.jump_velocity
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
	elif jump_pressed and air_jumps_left > 0:
		velocity.y = profile.jump_velocity * profile.air_jump_strength
		air_jumps_left -= 1
		jump_buffer_timer = 0.0
		stick_figure_visual.play_air_jump()

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	if Input.is_action_just_pressed("wave"):
		stick_figure_visual.play_wave()

	# Sharp turn at speed: still sliding the old way while steering the new.
	var skidding: bool = is_on_floor() and input_dir != 0.0 \
		and sign(input_dir) != sign(velocity.x) \
		and abs(velocity.x) > profile.run_speed * SKID_SPEED_FRACTION
	if skidding and not _was_skidding:
		_spawn_dust(sign(velocity.x), 2)
	_was_skidding = skidding

	_fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor and _fall_speed > LANDING_DUST_SPEED:
		_spawn_dust(0.0, 2)
	_was_on_floor = is_on_floor()
	stick_figure_visual.set_motion(velocity, is_on_floor(), facing_direction, skidding)

	if global_position.y > last_safe_position.y + FALL_RESET_MARGIN:
		global_position = last_safe_position
		velocity = Vector2.ZERO

func _spawn_dust(direction: float, count: int) -> void:
	var dust := DustPuff.new()
	dust.material = stick_figure_visual.material
	dust.setup(direction, count)
	get_parent().add_child(dust)
	dust.global_position = global_position + Vector2(0.0, 22.0)
