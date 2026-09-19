extends Node2D
## Cartoon dust "wind": gusts drawn as chains of connected half-circle
## bumps (a scalloped line) that sweep outward from the feet and curl
## upward at the end. Each gust unrolls from the feet, then disappears from
## its tail. Spawned on sharp turns (skids) and hard landings; uses the
## stick figure's contrast shader so it turns white on dark slides.

const LIFE := 0.55
const INK := Color(0.08, 0.08, 0.08)
const LINE_WIDTH := 2.0
const PATH_STEPS := 30
## Path steps per half-circle bump (5 big puffy bumps per gust).
const STEPS_PER_BUMP := 6

## Each gust: {"side": +1/-1, "length", "lift" (start angle up from the
## ground, rad), "curl" (how far the end curls up, rad), "y" offset}
var _gusts: Array[Dictionary] = []
var _t: float = 0.0

## direction: +1/-1 sends the gusts that way (a skid kicks dust backward
## along the old motion); 0 sends one gust to each side (landing).
func setup(direction: float, count: int = 2) -> void:
	for i in range(count):
		var side: float = direction if direction != 0.0 else (1.0 if i % 2 == 0 else -1.0)
		_gusts.append({
			"side": side,
			"length": randf_range(52.0, 68.0) * (0.8 if direction == 0.0 else 1.0),
			"lift": randf_range(0.05, 0.25) + i * 0.12,
			"curl": randf_range(2.2, 3.0),
			"y": -i * 5.0,
		})

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k: float = _t / LIFE
	# Head unrolls quickly, the tail follows and eats the gust.
	var head: float = 1.0 - pow(1.0 - clamp(k / 0.45, 0.0, 1.0), 2.0)
	var tail: float = clamp((k - 0.35) / 0.65, 0.0, 1.0)
	var color := Color(INK, 1.0 - pow(k, 3.0))
	for gust in _gusts:
		var points: PackedVector2Array = _gust_path(gust, k)
		var first: int = int(tail * PATH_STEPS)
		var last: int = int(head * PATH_STEPS)
		var i: int = first
		while i + STEPS_PER_BUMP <= last:
			_bump(points[i], points[i + STEPS_PER_BUMP], float(gust.side), color)
			i += STEPS_PER_BUMP

## Path from the feet: outward and slightly up, heading bending upward and
## back over its length into a curl. Drifts a little outward over time.
func _gust_path(gust: Dictionary, k: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var side: float = gust.side
	var pos := Vector2(side * (4.0 + k * 10.0), gust.y)
	var step: float = gust.length / PATH_STEPS
	points.append(pos)
	for i in range(PATH_STEPS):
		var s: float = float(i) / PATH_STEPS
		var heading: float = gust.lift + gust.curl * s * s
		# Heading 0 = along the ground away from the feet; positive = upward.
		pos += Vector2(cos(heading) * side, -sin(heading)) * step * (1.0 - 0.25 * s)
		points.append(pos)
	return points

## Half-circle on chord a->b, bulging to the upper/outer side of the gust.
func _bump(a: Vector2, b: Vector2, side: float, color: Color) -> void:
	var center: Vector2 = (a + b) * 0.5
	var radius: float = a.distance_to(b) * 0.5
	if radius < 0.5:
		return
	var travel: Vector2 = b - a
	# Upper side of travel: rotate the travel direction toward screen-up.
	var outward: Vector2 = Vector2(travel.y, -travel.x) * side
	var start: float = (a - center).angle()
	var sweep: float = PI
	if Vector2.from_angle(start + sweep * 0.5).dot(outward) < 0.0:
		sweep = -PI
	draw_arc(center, radius, start, start + sweep, 10, color, LINE_WIDTH, true)
