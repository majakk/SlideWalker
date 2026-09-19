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

## True if a target offset from the takeoff point is reachable by a plain
## jump. dy > 0 means the target is above the takeoff point.
func reachable(dx: float, dy: float) -> bool:
	if dy <= 0.0:
		return true
	return dy <= max_up_dy(abs(dx))
