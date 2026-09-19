extends RefCounted
class_name LayoutSidescroll
## Places slides left-to-right at presentation scale, bottoms aligned on one
## continuous floor (the completability guarantee). The gap between slides
## is floor-only "stage", like the space between projected slides.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

const SLIDE_GAP_PX: float = 160.0

## World rect of each slide. Floor is y=0; slides extend upward.
static func place_slides(deck: PresentationModel.SlideDeck, scale_px_per_cm: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var cursor_x: float = 0.0
	for manifest in deck.slides:
		var size := Vector2(manifest.canvas_w, manifest.canvas_h) * scale_px_per_cm
		rects.append(Rect2(Vector2(cursor_x, -size.y), size))
		cursor_x += size.x + SLIDE_GAP_PX
	return rects

## per_slide_candidates: Array[Array[Candidate]] in slide-local px.
static func build(slide_rects: Array[Rect2], per_slide_candidates: Array) -> CourseModel.Layout:
	var layout := CourseModel.Layout.new()
	layout.slide_rects = slide_rects
	layout.world_left = -SLIDE_GAP_PX * 0.5
	layout.world_right = slide_rects[-1].end.x + SLIDE_GAP_PX * 0.5 if not slide_rects.is_empty() else 0.0

	var floor_platform := CourseModel.Platform.new()
	floor_platform.x = layout.world_left
	floor_platform.width = layout.world_right - layout.world_left
	floor_platform.kind = CourseModel.Platform.Kind.FLOOR
	layout.platforms.append(floor_platform)

	for i in range(slide_rects.size()):
		var origin: Vector2 = slide_rects[i].position
		for c in per_slide_candidates[i]:
			var candidate: PlatformCandidateBuilder.Candidate = c
			# Content resting on the slide's bottom edge is already the floor.
			if candidate.top >= slide_rects[i].size.y - 2.0:
				continue
			var p := CourseModel.Platform.new()
			p.x = origin.x + candidate.left
			p.y = origin.y + candidate.top
			p.width = candidate.right - candidate.left
			p.slide_index = i
			layout.platforms.append(p)

	layout.entry_position = Vector2(60.0, -30.0)
	return layout
