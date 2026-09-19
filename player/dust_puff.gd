extends Node2D
## Cartoon dust "wind": gusts drawn as chains of connected half-circle bumps
## (a scalloped line), emitted from the feet: each gust bursts outward along
## the ground, growing as it travels, with a gentle curl at its outer end,
## and fades out. Spawned on sharp turns (skids) and hard landings; uses the
## stick figure's contrast shader so it turns white on dark slides.

const LIFE := 0.5
const INK := Color(0.08, 0.08, 0.08)
const LINE_WIDTH := 2.0
const PATH_STEPS := 30
## Path steps per half-circle bump (5 puffy bumps per gust).
const STEPS_PER_BUMP := 6
## How far the gust's inner end travels out from the feet over its life.
const TRAVEL_PX := 34.0
## Gust length at birth, as a fraction of its full length.
const BIRTH_LENGTH := 0.3

## Each gust: {"side": +1/-1, "length", "lift" (angle up from the ground,
## rad), "curl" (extra upward bend at the outer end, rad), "y" offset}
var _gusts: Array[Dictionary] = []
var _t: float = 0.0

## direction: +1/-1 sends the gusts that way (a skid kicks dust backward
## along the old motion); 0 sends one gust to each side (landing).
func setup(direction: float, count: int = 2) -> void:
	for i in range(count):
		var side: float = direction if direction != 0.0 else (1.0 if i % 2 == 0 else -1.0)
		_gusts.append({
			"side": side,
			"length": randf_range(46.0, 60.0) * (0.85 if direction == 0.0 else 1.0 - 0.3 * i),
			"lift": randf_range(0.04, 0.14) + (i * 0.1 if direction != 0.0 else 0.0),
			"curl": randf_range(0.7, 1.1),
			"y": -i * 6.0 if direction != 0.0 else 0.0,
		})

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k: float = _t / LIFE
	# Fast burst out of the feet that eases off, like a puff of air.
	var burst: float = 1.0 - pow(1.0 - k, 3.0)
	var color := Color(INK, 1.0 - pow(k, 2.5))
	for gust in _gusts:
		var points: PackedVector2Array = _gust_path(gust, burst)
		var i: int = 0
		while i + STEPS_PER_BUMP <= PATH_STEPS:
			_bump(points[i], points[i + STEPS_PER_BUMP], float(gust.side), color)
			i += STEPS_PER_BUMP

## The gust at a given point of its burst: its inner end has moved out from
## the feet and it has grown to full length; it runs outward along the
## ground, rising slightly and curling up gently at the far end.
func _gust_path(gust: Dictionary, burst: float) -> PackedVector2Array:
	var side: float = gust.side
	var pos := Vector2(side * (3.0 + TRAVEL_PX * burst), gust.y - 2.0 * burst)
	var step: float = gust.length * lerp(BIRTH_LENGTH, 1.0, burst) / PATH_STEPS
	var points := PackedVector2Array([pos])
	for i in range(PATH_STEPS):
		var s: float = float(i) / PATH_STEPS
		var heading: float = gust.lift + gust.curl * s * s * s
		# Heading 0 = along the ground away from the feet; positive = upward.
		pos += Vector2(cos(heading) * side, -sin(heading)) * step
		points.append(pos)
	return points

## Half-circle on chord a->b, bulging to the upper side of the gust.
func _bump(a: Vector2, b: Vector2, side: float, color: Color) -> void:
	var center: Vector2 = (a + b) * 0.5
	var radius: float = a.distance_to(b) * 0.5
	if radius < 0.5:
		return
	var travel: Vector2 = b - a
	var outward: Vector2 = Vector2(travel.y, -travel.x) * side
	var start: float = (a - center).angle()
	var sweep: float = PI
	if Vector2.from_angle(start + sweep * 0.5).dot(outward) < 0.0:
		sweep = -PI
	draw_arc(center, radius, start, start + sweep, 10, color, LINE_WIDTH, true)
