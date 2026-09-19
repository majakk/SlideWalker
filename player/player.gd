extends CharacterBody2D
## M0 movement controller: run + jump with coyote time and jump buffering.
## Ledge-grab/mantle and the animation state machine land in later
## milestones (M4/M5) — this establishes and tunes the raw movement feel
## that everything else, including course-gen reachability, is built on.

const ACCEL: float = 2500.0
const FRICTION: float = 3000.0
const COYOTE_TIME: float = 0.1
const JUMP_BUFFER_TIME: float = 0.1
## Course generation guarantees a continuous floor under every slide, so
## falling below the last solid ground should never actually happen — this
## is a defensive backstop, not a mechanic to design levels around.
const FALL_RESET_MARGIN: float = 800.0

var facing_direction: int = 1
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var last_safe_position: Vector2

const StickFigure = preload("res://player/stick_figure.gd")

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
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		last_safe_position = global_position
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)
		velocity.y = min(velocity.y + JumpPhysics.GRAVITY * delta, JumpPhysics.MAX_FALL_SPEED)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	var input_dir: float = Input.get_axis("move_left", "move_right")
	if input_dir != 0.0:
		velocity.x = move_toward(velocity.x, input_dir * JumpPhysics.RUN_SPEED, ACCEL * delta)
		facing_direction = sign(input_dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JumpPhysics.JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	move_and_slide()
	stick_figure_visual.set_motion(velocity, is_on_floor(), facing_direction)

	if global_position.y > last_safe_position.y + FALL_RESET_MARGIN:
		global_position = last_safe_position
		velocity = Vector2.ZERO
