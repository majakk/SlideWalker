extends Node
## Single source of truth for player movement physics and the jump
## reachability envelope that course generation (M2+) validates against.

const GRAVITY: float = 1400.0
const JUMP_VELOCITY: float = -620.0
const RUN_SPEED: float = 320.0
const MAX_FALL_SPEED: float = 1200.0
const MANTLE_GRAB_RANGE: float = 40.0

## Time from takeoff to jump apex.
static func _time_to_apex() -> float:
	return -JUMP_VELOCITY / GRAVITY

## Max horizontal distance coverable before falling back to takeoff height.
static func _max_flight_dx() -> float:
	return RUN_SPEED * _time_to_apex() * 2.0

## Max upward height reachable when covering horizontal distance dx during
## the jump (dx and the returned height are both >= 0). The player controls
## horizontal speed, so anything within the apex's horizontal reach can be
## hit at full apex height; beyond that, height follows the descending arc
## at full run speed. Returns -INF when dx exceeds a single jump's range.
static func max_up_dy(dx: float) -> float:
	if dx >= _max_flight_dx():
		return -INF
	var apex: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
	if dx <= RUN_SPEED * _time_to_apex():
		return apex
	var t: float = dx / RUN_SPEED
	return -JUMP_VELOCITY * t - 0.5 * GRAVITY * t * t

## Dropping down is always possible; there is no fall damage.
static func max_down_dy(_dx: float) -> float:
	return INF

## Ledge-grab/mantle extends effective reach by a fixed grab tolerance.
static func mantle_up_dy(dx: float) -> float:
	var base: float = max_up_dy(dx)
	if base == -INF:
		return -INF
	return base + MANTLE_GRAB_RANGE

## True if a target offset (dx, dy) from the takeoff point is reachable by a
## plain jump. dy > 0 means the target is above the takeoff point.
static func reachable(dx: float, dy: float) -> bool:
	if dy <= 0.0:
		return true
	return dy <= max_up_dy(abs(dx))
