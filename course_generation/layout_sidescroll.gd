extends RefCounted
class_name LayoutSidescroll
## Places slides left-to-right. Floor height is kept identical across every
## slide (only content height varies) so the floor is one continuous strip
## for the whole course - the completability guarantee - with no bridging
## logic needed: padding between slides simply extends the floor a bit
## further before the next slide's content begins.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

const INTER_SLIDE_PADDING_PX: float = 80.0

static func build(deck: PresentationModel.SlideDeck, scale_px_per_cm: float) -> CourseModel.Layout:
	var layout := CourseModel.Layout.new()
	var cursor_x: float = 0.0

	for manifest in deck.slides:
		var slide_w_px: float = manifest.canvas_w * scale_px_per_cm
		var span_px: float = slide_w_px + INTER_SLIDE_PADDING_PX

		var floor_platform := CourseModel.Platform.new()
		floor_platform.x = cursor_x
		floor_platform.y = 0.0
		floor_platform.width = span_px
		floor_platform.kind = CourseModel.Platform.Kind.FLOOR
		floor_platform.source_slide_id = manifest.slide_id
		layout.platforms.append(floor_platform)

		for c in PlatformCandidateBuilder.build(manifest):
			var candidate: PlatformCandidateBuilder.Candidate = c
			var height_above_floor_cm: float = manifest.canvas_h - candidate.top_cm
			var p := CourseModel.Platform.new()
			p.x = cursor_x + candidate.left_cm * scale_px_per_cm
			p.y = -height_above_floor_cm * scale_px_per_cm
			p.width = (candidate.right_cm - candidate.left_cm) * scale_px_per_cm
			p.kind = CourseModel.Platform.Kind.CONTENT
			p.source_slide_id = manifest.slide_id
			if candidate.source_shape:
				p.image_ref = candidate.source_shape.image_ref
				p.text_summary = candidate.source_shape.text_summary
			layout.platforms.append(p)

		cursor_x += span_px

	layout.world_width = cursor_x
	layout.entry_position = Vector2(40.0, -40.0)
	return layout
