extends Camera2D
## Frames the slide the player is in, like a presentation: the slide fills
## the window (whatever its aspect ratio) with its stage below. In per-slide
## mode, moving into the next slide pans over (camera smoothing) - the slide
## transition; in seamless mode the camera follows the player along the
## course (sideways, or up/down for vertical courses).

const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

var target: Node2D
var _layout: CourseModel.Layout

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 4.5

func setup(layout: CourseModel.Layout, follow: Node2D) -> void:
	_layout = layout
	target = follow
	_update_framing()
	reset_smoothing()

func snap_to_target() -> void:
	_update_framing()
	reset_smoothing()

func current_slide_index() -> int:
	var best: int = 0
	var best_dist: float = INF
	var p: Vector2 = target.global_position
	for i in range(_layout.slide_rects.size()):
		var r: Rect2 = _layout.slide_rects[i]
		var dist: float
		if _layout.vertical:
			# The stage band under a slide belongs to that slide.
			dist = max(0.0, max(r.position.y - p.y, p.y - (r.end.y + CourseGenerator.STAGE_PX)))
		else:
			dist = max(0.0, max(r.position.x - p.x, p.x - r.end.x))
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

func _process(_delta: float) -> void:
	_update_framing()

func _update_framing() -> void:
	if target == null or _layout == null or _layout.slide_rects.is_empty():
		return
	var r: Rect2 = _layout.slide_rects[current_slide_index()]
	var side: float = max(r.size.x * (1.0 / CourseGenerator.SIDE_MARGIN_FRACTION - 1.0) * 0.5, _layout.side_zone)
	# Region to show: the slide, side room, a top margin, and the stage below.
	var region := Rect2(
		r.position - Vector2(side, CourseGenerator.TOP_MARGIN_PX),
		Vector2(r.size.x + side * 2.0, r.size.y + CourseGenerator.TOP_MARGIN_PX + CourseGenerator.STAGE_PX))
	var view: Vector2 = get_viewport_rect().size
	var fit: float = min(view.x / region.size.x, view.y / region.size.y)
	zoom = Vector2(fit, fit)
	if GameSettings.camera_mode == GameSettings.CameraMode.PER_SLIDE:
		global_position = region.get_center()
		return

	# Seamless: same zoom, follow the player along the course axis, held back
	# at the ends so the view never runs past the first/last slide.
	var first: Rect2 = _layout.slide_rects[0]
	var last: Rect2 = _layout.slide_rects[-1]
	if _layout.vertical:
		var half_h: float = view.y / fit * 0.5
		var lo: float = min(first.position.y, last.position.y) - CourseGenerator.TOP_MARGIN_PX + half_h
		var hi: float = max(first.end.y, last.end.y) + CourseGenerator.STAGE_PX - half_h
		var y: float = clamp(target.global_position.y, lo, hi) if lo <= hi else (lo + hi) * 0.5
		global_position = Vector2(region.get_center().x, y)
	else:
		var half_w: float = view.x / fit * 0.5
		var left: float = first.position.x - side + half_w
		var right: float = last.end.x + side - half_w
		var x: float = clamp(target.global_position.x, left, right) if left <= right else (left + right) * 0.5
		global_position = Vector2(x, region.get_center().y)
