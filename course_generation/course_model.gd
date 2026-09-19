extends RefCounted
class_name CourseModel
## Output of course generation: a flat, layout-mode-agnostic list of world-
## space platforms. world_assembler.gd turns this into live scene nodes.

class Platform:
	extends RefCounted

	enum Kind { CONTENT, FLOOR }

	## World-space top-left corner (px). Floor platforms are the safety net
	## that guarantees completability; content platforms are the top edges
	## of actual slide shapes and are jump-through from below (one-way).
	var x: float = 0.0
	var y: float = 0.0
	var width: float = 0.0
	var kind: Kind = Kind.CONTENT
	var source_slide_id: int = -1
	var image_ref: String = ""
	var text_summary: String = ""

class Layout:
	extends RefCounted

	var platforms: Array[Platform] = []
	var world_width: float = 0.0
	var entry_position: Vector2 = Vector2.ZERO
