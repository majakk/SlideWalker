extends RefCounted
class_name CourseModel
## Output of course generation: world-space platforms plus the slide frames
## they belong to. world_assembler.gd turns platforms into collision;
## slide_content_renderer.gd draws the slides into the slide frames.

const JumpProfile = preload("res://player/jump_profile.gd")

class Platform:
	extends RefCounted

	## CONTENT: top edge of slide content (a text line, image, shape).
	## FLOOR: a slide's bottom edge / the stage. HELPER: generated climbing
	## rungs outside the slide, only where content alone can't get you on.
	enum Kind { CONTENT, FLOOR, HELPER }

	## World-space left end of the walkable top edge (px).
	var x: float = 0.0
	var y: float = 0.0
	var width: float = 0.0
	var kind: Kind = Kind.CONTENT
	## Solid platforms can't be jumped through or dropped through (the
	## bottom of the course); everything else is one-way.
	var solid: bool = false
	var slide_index: int = -1

class Layout:
	extends RefCounted

	var platforms: Array[Platform] = []
	## World-space rect of each slide, in deck order.
	var slide_rects: Array[Rect2] = []
	## Index of the platform the course starts on.
	var start_index: int = 0
	var entry_position: Vector2 = Vector2.ZERO
	## Stage areas to draw (under slides).
	var stage_rects: Array[Rect2] = []
	## Walls sit on the left/right edges of this rect.
	var world_bounds: Rect2 = Rect2()
	## Slides stacked vertically (climb/drop) rather than side by side.
	var vertical: bool = false
	## Extra horizontal room the camera keeps on each side of a slide
	## (vertical courses place helper rungs there).
	var side_zone: float = 0.0
	var jump_profile: JumpProfile
