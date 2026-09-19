extends RefCounted
## Instantiates a CourseModel.Layout as collision. Content ledges are
## invisible - the slides themselves are what you see and stand on - with
## an optional debug overlay. Stage areas are drawn under the slides, helper
## rungs (outside slides) are drawn as small stage-colored bars, and walls
## close off the course's sides.

const CourseModel = preload("res://course_generation/course_model.gd")

const STAGE_COLOR := Color(0.27, 0.3, 0.35)
const STAGE_EDGE_COLOR := Color(0.36, 0.4, 0.46)
const RUNG_COLOR := Color(0.36, 0.4, 0.46)
const LEDGE_THICKNESS_PX: float = 12.0
const SOLID_THICKNESS_PX: float = 200.0
const DEBUG_COLOR := Color(1.0, 0.2, 0.5, 0.85)
const SLIDE_NUMBER_COLOR := Color(0.72, 0.76, 0.82)
const SLIDE_NUMBER_SIZE: int = 20
## Physics layers: solid floor and walls on 1, one-way platforms on 2 (the
## player drops through by masking out layer 2, never through the floor).
const SOLID_LAYER_BITS: int = 1
const ONE_WAY_LAYER_BITS: int = 2

## Returns the debug overlay node (hidden) so callers can toggle it.
static func assemble(parent: Node2D, layout: CourseModel.Layout) -> Node2D:
	var debug := Node2D.new()
	debug.name = "PlatformDebug"
	debug.visible = false
	debug.z_index = 10

	for rect in layout.stage_rects:
		_rect(parent, rect, STAGE_COLOR)
		_rect(parent, Rect2(rect.position, Vector2(rect.size.x, 3.0)), STAGE_EDGE_COLOR)

	for platform in layout.platforms:
		var thickness: float = SOLID_THICKNESS_PX if platform.solid else LEDGE_THICKNESS_PX
		var body := StaticBody2D.new()
		body.collision_layer = SOLID_LAYER_BITS if platform.solid else ONE_WAY_LAYER_BITS
		body.position = Vector2(platform.x + platform.width * 0.5, platform.y + thickness * 0.5)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(platform.width, thickness)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.one_way_collision = not platform.solid
		body.add_child(collision)
		parent.add_child(body)

		if platform.kind == CourseModel.Platform.Kind.HELPER:
			_rect(parent, Rect2(platform.x, platform.y, platform.width, 8.0), RUNG_COLOR)

		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(platform.x, platform.y), Vector2(platform.x + platform.width, platform.y)])
		line.width = 3.0
		line.default_color = DEBUG_COLOR
		debug.add_child(line)

	# Slide numbers, centered under each slide in the stage.
	for i in range(layout.slide_rects.size()):
		var r: Rect2 = layout.slide_rects[i]
		var number := Label.new()
		number.text = "%d / %d" % [i + 1, layout.slide_rects.size()]
		# On the 2D canvas, point the presenter toward the next slide.
		if layout.two_d and i + 1 < layout.slide_rects.size():
			var step: Vector2 = layout.slide_rects[i + 1].get_center() - r.get_center()
			if abs(step.x) > abs(step.y):
				number.text += "   →" if step.x > 0.0 else "   ←"
			else:
				number.text += "   ↓" if step.y > 0.0 else "   ↑"
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_font_size_override("font_size", SLIDE_NUMBER_SIZE)
		number.add_theme_color_override("font_color", SLIDE_NUMBER_COLOR)
		number.position = Vector2(r.position.x, r.end.y + 10.0)
		number.size = Vector2(r.size.x, SLIDE_NUMBER_SIZE + 6)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(number)

	var b: Rect2 = layout.world_bounds
	for x in [b.position.x, b.end.x]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, b.get_center().y)
		var wall_shape := RectangleShape2D.new()
		wall_shape.size = Vector2(20.0, b.size.y)
		var wall_collision := CollisionShape2D.new()
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)
		parent.add_child(wall)

	parent.add_child(debug)
	return debug

static func _rect(parent: Node, rect: Rect2, color: Color) -> void:
	var r := ColorRect.new()
	r.color = color
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
