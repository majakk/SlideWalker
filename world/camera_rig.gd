extends Camera2D
## Frames the slide the player is in, like a presentation: the slide fills
## the window (whatever its aspect ratio) with the stage strip below.
## Crossing into the next slide pans over (camera smoothing) - the slide
## transition. Adaptive zoom (M8) layers on top of this.

const CourseGenerator = preload("res://course_generation/course_generator.gd")

var slide_rects: Array[Rect2] = []
var target: Node2D

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 4.5

func current_slide_index() -> int:
	var best: int = 0
	var best_dist: float = INF
	for i in range(slide_rects.size()):
		var r: Rect2 = slide_rects[i]
		var dist: float = max(0.0, max(r.position.x - target.global_position.x, target.global_position.x - r.end.x))
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

func snap_to_target() -> void:
	_update_framing()
	reset_smoothing()

func _process(_delta: float) -> void:
	_update_framing()

func _update_framing() -> void:
	if target == null or slide_rects.is_empty():
		return
	var r: Rect2 = slide_rects[current_slide_index()]
	# Region to show: the slide, a top margin, and the stage strip below.
	var region := Rect2(
		r.position - Vector2(r.size.x * (1.0 / CourseGenerator.SIDE_MARGIN_FRACTION - 1.0) * 0.5, CourseGenerator.TOP_MARGIN_PX),
		Vector2(r.size.x / CourseGenerator.SIDE_MARGIN_FRACTION, r.size.y + CourseGenerator.TOP_MARGIN_PX + CourseGenerator.STAGE_PX))
	var view: Vector2 = get_viewport_rect().size
	var fit: float = min(view.x / region.size.x, view.y / region.size.y)
	zoom = Vector2(fit, fit)
	global_position = region.get_center()
