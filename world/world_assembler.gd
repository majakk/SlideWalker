extends RefCounted
class_name WorldAssembler
## Instantiates a generated CourseModel.Layout as live collision + visual
## nodes. Visuals here are flat placeholder rects; slide_content_renderer.gd
## (M3) replaces the content-platform visuals with the actual slide
## images/text, positioned identically to the collision shape.

const CourseModel = preload("res://course_generation/course_model.gd")

const FLOOR_COLOR := Color(0.36, 0.25, 0.2, 1)
const CONTENT_COLOR := Color(0.55, 0.38, 0.28, 1)
const PLATFORM_THICKNESS_PX: float = 20.0
const FLOOR_THICKNESS_PX: float = 100.0

static func assemble(parent: Node2D, layout: CourseModel.Layout) -> void:
	for platform in layout.platforms:
		var is_floor: bool = platform.kind == CourseModel.Platform.Kind.FLOOR
		var thickness: float = FLOOR_THICKNESS_PX if is_floor else PLATFORM_THICKNESS_PX

		var body := StaticBody2D.new()
		body.position = Vector2(platform.x + platform.width * 0.5, platform.y + thickness * 0.5)

		var shape := RectangleShape2D.new()
		shape.size = Vector2(platform.width, thickness)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		# Content platforms are jump-through from below and solid from
		# above; the floor is the always-solid safety net.
		collision.one_way_collision = not is_floor
		body.add_child(collision)

		var visual := ColorRect.new()
		visual.color = FLOOR_COLOR if is_floor else CONTENT_COLOR
		visual.position = Vector2(-platform.width * 0.5, -thickness * 0.5)
		visual.size = Vector2(platform.width, thickness)
		body.add_child(visual)

		parent.add_child(body)
