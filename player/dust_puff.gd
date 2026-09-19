extends Node2D
## Cartoon dust "wind": wave fronts drawn as chains of connected half-circle
## bumps (a scalloped arc) centered on the feet. Each front stands across
## the direction of travel, bulges outward - like ")))" - and expands away
## from the feet while fading. Spawned on sharp turns (skids) and hard
## landings; uses the stick figure's contrast shader so it turns white on
## dark slides.

const LIFE := 0.5
const INK := Color(0.08, 0.08, 0.08)
const LINE_WIDTH := 2.0
const ARC_STEPS := 20
## Arc steps per half-circle bump (5 bumps per front).
const STEPS_PER_BUMP := 4
const START_RADIUS := 6.0
## Fronts are a little wider than tall, hugging the ground.
const HEIGHT_RATIO := 0.85

## Each front: {"side": +1/-1, "radius" (final), "span" (rad above the
## ground), "delay" (0..1 of life)}
var _fronts: Array[Dictionary] = []
var _t: float = 0.0

## direction: +1/-1 sends the fronts that way (a skid kicks dust backward
## along the old motion); 0 sends one front to each side (landing).
func setup(direction: float, count: int = 2) -> void:
	for i in range(count):
		var side: float = direction if direction != 0.0 else (1.0 if i % 2 == 0 else -1.0)
		var trailing: bool = direction != 0.0 and i > 0
		_fronts.append({
			"side": side,
			"radius": randf_range(40.0, 50.0) * (0.62 if trailing else 1.0),
			"span": randf_range(1.05, 1.3),
			"delay": 0.12 if trailing else 0.0,
		})

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k: float = _t / LIFE
	for front in _fronts:
		var local: float = clamp((k - front.delay) / (1.0 - front.delay), 0.0, 1.0)
		if local <= 0.0:
			continue
		# Fast burst out of the feet that eases off, like a puff of air.
		var burst: float = 1.0 - pow(1.0 - local, 3.0)
		var radius: float = lerp(START_RADIUS, float(front.radius), burst)
		var color := Color(INK, 1.0 - pow(local, 2.5))
		var points: PackedVector2Array = _front_arc(front.side, radius, front.span)
		var i: int = 0
		while i + STEPS_PER_BUMP <= ARC_STEPS:
			_bump(points[i], points[i + STEPS_PER_BUMP], color)
			i += STEPS_PER_BUMP

## Arc around the feet from ground level up by `span`, on the given side.
func _front_arc(side: float, radius: float, span: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(ARC_STEPS + 1):
		var a: float = span * float(i) / ARC_STEPS
		points.append(Vector2(cos(a) * radius * side, -sin(a) * radius * HEIGHT_RATIO))
	return points

## Half-circle on chord a->b, bulging away from the feet (the origin).
func _bump(a: Vector2, b: Vector2, color: Color) -> void:
	var center: Vector2 = (a + b) * 0.5
	var radius: float = a.distance_to(b) * 0.5
	if radius < 0.5:
		return
	var start: float = (a - center).angle()
	var sweep: float = PI
	if Vector2.from_angle(start + sweep * 0.5).dot(center) < 0.0:
		sweep = -PI
	draw_arc(center, radius, start, start + sweep, 10, color, LINE_WIDTH, true)
