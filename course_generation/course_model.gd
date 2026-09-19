extends RefCounted
class_name CourseModel
## Output of course generation: world-space platforms plus the slide frames
## they belong to. world_assembler.gd turns platforms into collision;
## slide_content_renderer.gd draws the slides into the slide frames.

const JumpProfile = preload("res://player/jump_profile.gd")

class Platform:
	extends RefCounted

	enum Kind { CONTENT, FLOOR }

	## World-space left end of the walkable top edge (px). Floor platforms
	## are the completability safety net; content platforms are the top
	## edges of slide content and are jump-through from below (one-way).
	var x: float = 0.0
	var y: float = 0.0
	var width: float = 0.0
	var kind: Kind = Kind.CONTENT
	var slide_index: int = -1

class Layout:
	extends RefCounted

	var platforms: Array[Platform] = []
	## World-space rect of each slide, in deck order.
	var slide_rects: Array[Rect2] = []
	var world_left: float = 0.0
	var world_right: float = 0.0
	var entry_position: Vector2 = Vector2.ZERO
	var jump_profile: JumpProfile
