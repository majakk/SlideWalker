extends Node2D
## xkcd-style dust cloud: a few hollow ink circles that billow out, grow
## and fade. Spawned at the feet on sharp turns (skids) and hard landings.
## Uses the stick figure's contrast shader so it turns white on dark slides.

const LIFE := 0.5
const INK := Color(0.08, 0.08, 0.08)
const LINE_WIDTH := 2.0

var _puffs: Array[Dictionary] = []
var _t: float = 0.0

## direction: +1/-1 sends the puffs mostly that way (a skid kicks dust
## backward along the old motion); 0 spreads them to both sides (landing).
func setup(direction: float, count: int = 5) -> void:
	for i in range(count):
		var side: float = direction if direction != 0.0 else (1.0 if i % 2 == 0 else -1.0)
		var speed: float = randf_range(60.0, 150.0)
		var angle: float = randf_range(-0.45, 0.05)
		_puffs.append({
			"pos": Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 0.0)),
			"vel": Vector2(cos(angle) * side, sin(angle) - 0.35).normalized() * speed,
			"r0": randf_range(2.0, 4.0),
			"r1": randf_range(7.0, 12.0),
		})

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for p in _puffs:
		p.pos += p.vel * delta
		p.vel *= exp(-5.0 * delta)
	queue_redraw()

func _draw() -> void:
	var k: float = _t / LIFE
	var grow: float = 1.0 - pow(1.0 - k, 3.0)
	var color := Color(INK, 1.0 - k * k)
	for p in _puffs:
		draw_arc(p.pos, lerp(float(p.r0), float(p.r1), grow), 0.0, TAU, 20, color, LINE_WIDTH, true)
