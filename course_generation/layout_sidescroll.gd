extends RefCounted
class_name LayoutSidescroll
## Places slides left-to-right at presentation scale, bottoms aligned on one
## continuous floor (the completability guarantee). The gap between slides
## is floor-only "stage", like the space between projected slides.

const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const JumpProfile = preload("res://player/jump_profile.gd")

const SLIDE_GAP_PX: float = 160.0
const STAGE_DEPTH_PX: float = 200.0
const WALL_HEIGHT_PX: float = 4000.0

## World rect of each slide. Floor is y=0; slides extend upward.
static func place_slides(sizes: Array[Vector2]) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var cursor_x: float = 0.0
	for size in sizes:
		rects.append(Rect2(Vector2(cursor_x, -size.y), size))
		cursor_x += size.x + SLIDE_GAP_PX
	return rects

## per_slide_candidates: Array[Array[Candidate]] in slide-local px.
static func build(slide_rects: Array[Rect2], per_slide_candidates: Array) -> CourseModel.Layout:
	var layout := CourseModel.Layout.new()
	layout.slide_rects = slide_rects
	var left: float = -SLIDE_GAP_PX * 0.5
	var right: float = slide_rects[-1].end.x + SLIDE_GAP_PX * 0.5 if not slide_rects.is_empty() else 0.0
	layout.world_bounds = Rect2(left, -WALL_HEIGHT_PX, right - left, WALL_HEIGHT_PX + STAGE_DEPTH_PX)
	layout.stage_rects = [Rect2(left, 0.0, right - left, STAGE_DEPTH_PX)]

	var floor_platform := CourseModel.Platform.new()
	floor_platform.x = left
	floor_platform.width = right - left
	floor_platform.kind = CourseModel.Platform.Kind.FLOOR
	floor_platform.solid = true
	layout.platforms.append(floor_platform)
	layout.start_index = 0

	for i in range(slide_rects.size()):
		for p in slide_ledges(slide_rects[i], per_slide_candidates[i], i):
			layout.platforms.append(p)

	layout.entry_position = Vector2(60.0, -30.0)
	return layout

## Content ledges of one slide in world space (shared by all layouts).
static func slide_ledges(rect: Rect2, candidates: Array, slide_index: int) -> Array[CourseModel.Platform]:
	var out: Array[CourseModel.Platform] = []
	for c in candidates:
		var candidate: PlatformCandidateBuilder.Candidate = c
		# Content resting on the slide's bottom edge is already the floor.
		if candidate.top >= rect.size.y - 2.0:
			continue
		# Standing here would put the figure outside the slide (e.g. the
		# top edge of a full-bleed image, or content above the slide).
		if candidate.top < JumpProfile.BODY_HEIGHT:
			continue
		# Content hanging off the sides is clipped, like in a slideshow.
		var left: float = max(candidate.left, 0.0)
		var right: float = min(candidate.right, rect.size.x)
		if right - left < PlatformCandidateBuilder.MIN_WIDTH_PX:
			continue
		var p := CourseModel.Platform.new()
		p.x = rect.position.x + left
		p.y = rect.position.y + candidate.top
		p.width = right - left
		p.slide_index = slide_index
		out.append(p)
	return out
