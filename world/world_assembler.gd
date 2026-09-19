extends RefCounted
class_name WorldAssembler
## Instantiates a CourseModel.Layout as collision. Content ledges are
## invisible - the slides themselves are what you see and stand on - with
## an optional debug overlay. The floor is drawn as a slim stage strip under
## the slides, and walls close off both ends of the course.

const CourseModel = preload("res://course_generation/course_model.gd")

const STAGE_COLOR := Color(0.27, 0.3, 0.35)
const STAGE_EDGE_COLOR := Color(0.36, 0.4, 0.46)
const LEDGE_THICKNESS_PX: float = 12.0
const FLOOR_THICKNESS_PX: float = 200.0
const WALL_HEIGHT_PX: float = 4000.0
const DEBUG_COLOR := Color(1.0, 0.2, 0.5, 0.85)
const SLIDE_NUMBER_COLOR := Color(0.72, 0.76, 0.82)
const SLIDE_NUMBER_SIZE: int = 20
## Physics layers: floor and walls on 1, ledges on 2 (the player can drop
## through ledges by masking out layer 2, never through the floor).
const FLOOR_LAYER_BITS: int = 1
const LEDGE_LAYER_BITS: int = 2

## Returns the debug overlay node (hidden) so callers can toggle it.
static func assemble(parent: Node2D, layout: CourseModel.Layout) -> Node2D:
	var debug := Node2D.new()
	debug.name = "PlatformDebug"
	debug.visible = false
	debug.z_index = 10

	for platform in layout.platforms:
		var is_floor: bool = platform.kind == CourseModel.Platform.Kind.FLOOR
		var thickness: float = FLOOR_THICKNESS_PX if is_floor else LEDGE_THICKNESS_PX
		var body := StaticBody2D.new()
		body.collision_layer = FLOOR_LAYER_BITS if is_floor else LEDGE_LAYER_BITS
		body.position = Vector2(platform.x + platform.width * 0.5, platform.y + thickness * 0.5)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(platform.width, thickness)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		# Ledges are jump-through from below; the floor is always solid.
		collision.one_way_collision = not is_floor
		body.add_child(collision)
		parent.add_child(body)

		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(platform.x, platform.y), Vector2(platform.x + platform.width, platform.y)])
		line.width = 3.0
		line.default_color = DEBUG_COLOR
		debug.add_child(line)

	var stage := ColorRect.new()
	stage.color = STAGE_COLOR
	stage.position = Vector2(layout.world_left, 0.0)
	stage.size = Vector2(layout.world_right - layout.world_left, FLOOR_THICKNESS_PX)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stage)
	var edge := ColorRect.new()
	edge.color = STAGE_EDGE_COLOR
	edge.position = Vector2(layout.world_left, 0.0)
	edge.size = Vector2(layout.world_right - layout.world_left, 3.0)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(edge)

	# Slide numbers, centered under each slide in the stage strip.
	for i in range(layout.slide_rects.size()):
		var r: Rect2 = layout.slide_rects[i]
		var number := Label.new()
		number.text = "%d / %d" % [i + 1, layout.slide_rects.size()]
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_font_size_override("font_size", SLIDE_NUMBER_SIZE)
		number.add_theme_color_override("font_color", SLIDE_NUMBER_COLOR)
		number.position = Vector2(r.position.x, 10.0)
		number.size = Vector2(r.size.x, SLIDE_NUMBER_SIZE + 6)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(number)

	for x in [layout.world_left, layout.world_right]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, -WALL_HEIGHT_PX * 0.5)
		var wall_shape := RectangleShape2D.new()
		wall_shape.size = Vector2(20.0, WALL_HEIGHT_PX)
		var wall_collision := CollisionShape2D.new()
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)
		parent.add_child(wall)

	parent.add_child(debug)
	return debug
