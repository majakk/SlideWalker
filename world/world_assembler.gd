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
