extends RefCounted
## Orchestrator. Slides are shown at presentation size and the platformer
## adapts to them:
##   deck -> presentation scale -> slide placement (per mode) -> walkable
##   rects (measured by the renderer, or estimated from shapes headlessly)
##   -> platform candidates -> per-deck jump calibration -> layout.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const JumpCalibrator = preload("res://course_generation/jump_calibrator.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
const LayoutVertical = preload("res://course_generation/layout_vertical.gd")
const LayoutSpiral = preload("res://course_generation/layout_spiral.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

## Same order as GameSettings.CourseLayout.
enum Mode { SIDE_SCROLL, CLIMB, DROP, SPIRAL }

## Logical design resolution (project.godot viewport size).
const VIEW_SIZE := Vector2(1280, 720)
## Screen space kept for the stage strip below the slide and a top margin.
const STAGE_PX: float = 44.0
const TOP_MARGIN_PX: float = 12.0
const SIDE_MARGIN_FRACTION: float = 0.97
## Rotated content doesn't make a sensible flat ledge.
const MAX_PLATFORM_ROTATION_DEG: float = 3.0
## Rungs per slide for the presenter's toggleable "reach anything" assist.
const ASSIST_PLATFORMS_PER_SLIDE: int = 3

## px per cm so one slide fills the screen the way a projector shows it.
static func presentation_scale(deck: PresentationModel.SlideDeck) -> float:
	if deck.slides.is_empty():
		return 40.0
	var canvas := Vector2(deck.slides[0].canvas_w, deck.slides[0].canvas_h)
	return min(VIEW_SIZE.x * SIDE_MARGIN_FRACTION / canvas.x,
		(VIEW_SIZE.y - STAGE_PX - TOP_MARGIN_PX) / canvas.y)

static func slide_sizes(deck: PresentationModel.SlideDeck, scale_px_per_cm: float) -> Array[Vector2]:
	var sizes: Array[Vector2] = []
	for m in deck.slides:
		sizes.append(Vector2(m.canvas_w, m.canvas_h) * scale_px_per_cm)
	return sizes

static func place_slides(sizes: Array[Vector2], mode: Mode) -> Array[Rect2]:
	match mode:
		Mode.CLIMB:
			return LayoutVertical.place_slides(sizes, true)
		Mode.DROP:
			return LayoutVertical.place_slides(sizes, false)
		Mode.SPIRAL:
			return LayoutSpiral.place_slides(sizes)
	return LayoutSidescroll.place_slides(sizes)

## Headless estimate of walkable rects straight from shape frames (the
## renderer supplies measured text lines instead when it runs).
static func walkables_from_shapes(manifest: PresentationModel.SlideManifest, scale_px_per_cm: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for shape in manifest.shapes:
		if is_platform_shape(shape):
			out.append(Rect2(Vector2(shape.x, shape.y) * scale_px_per_cm, Vector2(shape.w, shape.h) * scale_px_per_cm))
	return out

static func is_platform_shape(shape: PresentationModel.ShapeRect) -> bool:
	if shape.type == PresentationModel.ShapeRect.Type.LINE:
		return false
	return abs(shape.rotation_deg) <= MAX_PLATFORM_ROTATION_DEG

static func generate(slide_rects: Array[Rect2], per_slide_walkables: Array, mode: Mode = Mode.SIDE_SCROLL) -> CourseModel.Layout:
	var per_slide_candidates: Array = []
	var sizes: Array[Vector2] = []
	for i in range(slide_rects.size()):
		per_slide_candidates.append(PlatformCandidateBuilder.build(per_slide_walkables[i]))
		sizes.append(slide_rects[i].size)

	# The jump is tuned on the slides' own content (side by side on one
	# floor), so it feels the same whichever way the course runs.
	var sidescroll: CourseModel.Layout = LayoutSidescroll.build(LayoutSidescroll.place_slides(sizes), per_slide_candidates)
	var profile = JumpCalibrator.calibrate(sidescroll)

	var layout: CourseModel.Layout
	match mode:
		Mode.CLIMB:
			layout = LayoutVertical.build(slide_rects, per_slide_candidates, profile, true)
		Mode.DROP:
			layout = LayoutVertical.build(slide_rects, per_slide_candidates, profile, false)
		Mode.SPIRAL:
			layout = LayoutSpiral.build(slide_rects, per_slide_candidates, profile)
		_:
			layout = sidescroll
	layout.jump_profile = profile
	_add_assist_platforms(layout)
	return layout

## Full slide width, evenly spaced down each slide, so anything on the slide
## is one short hop away when the presenter switches them on. Built after
## calibration, and kept in their own list, so the jump the deck's own
## content asks for is never quietly lowered by them being available.
static func _add_assist_platforms(layout: CourseModel.Layout) -> void:
	for i in range(layout.slide_rects.size()):
		var rect: Rect2 = layout.slide_rects[i]
		for step in range(1, ASSIST_PLATFORMS_PER_SLIDE + 1):
			var platform := CourseModel.Platform.new()
			platform.x = rect.position.x
			platform.y = rect.position.y + rect.size.y * float(step) / float(ASSIST_PLATFORMS_PER_SLIDE + 1)
			platform.width = rect.size.x
			platform.kind = CourseModel.Platform.Kind.ASSIST
			platform.slide_index = i
			layout.assist_platforms.append(platform)
