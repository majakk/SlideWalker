extends RefCounted
## Movement physics for one course. Slides are shown at presentation size,
## so the platformer adapts to the deck: course generation derives the jump
## apex from the deck's actual content spacing, and gravity/jump velocity
## follow from apex + time-to-apex.

const BODY_HEIGHT: float = 48.0

var apex_height: float = 137.3
var time_to_apex: float = 0.443
var run_speed: float = 320.0
var max_fall_speed: float = 1200.0
var mantle_range: float = 40.0
## Extra jumps allowed in mid-air (1 = double jump).
var air_jumps: int = 1
## Air jump launch speed relative to the ground jump (height scales with
## its square). Slightly weaker so it reads as a boost, not a reset.
var air_jump_strength: float = 0.9

var gravity: float:
	get: return 2.0 * apex_height / (time_to_apex * time_to_apex)

var jump_velocity: float:
	get: return -2.0 * apex_height / time_to_apex

## Max height reachable when covering horizontal distance dx (both >= 0).
## Within the apex's horizontal reach the full apex height is available,
## since the player controls horizontal speed; beyond it, height follows
## the descending arc at full run speed. -INF when out of range entirely.
func max_up_dy(dx: float) -> float:
	var apex_dx: float = run_speed * time_to_apex
	if dx >= apex_dx * 2.0:
		return -INF
	if dx <= apex_dx:
		return apex_height
	var t: float = dx / run_speed
	return -jump_velocity * t - 0.5 * gravity * t * t

## Max height with a double jump, conservatively assuming the second jump
## fires at the first jump's apex.
func max_up_dy_double(dx: float) -> float:
	var apex_dx: float = run_speed * time_to_apex
	var second: float = max_up_dy(max(0.0, dx - apex_dx))
	if second == -INF:
		return max_up_dy(dx)
	return apex_height + second * air_jump_strength * air_jump_strength

## True if a target offset from the takeoff point is reachable, using the
## air jump when available. dy > 0 means the target is above the takeoff.
func reachable(dx: float, dy: float) -> bool:
	if dy <= 0.0:
		return true
	var limit: float = max_up_dy_double(abs(dx)) if air_jumps > 0 else max_up_dy(abs(dx))
	return dy <= limit

func with_air_jumps(count: int):
	var copy = get_script().new()
	copy.apex_height = apex_height
	copy.time_to_apex = time_to_apex
	copy.run_speed = run_speed
	copy.max_fall_speed = max_fall_speed
	copy.mantle_range = mantle_range
	copy.air_jumps = count
	copy.air_jump_strength = air_jump_strength
	return copy
