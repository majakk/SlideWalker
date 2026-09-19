extends RefCounted
class_name CourseGenerator
## Orchestrator. Slides are shown at presentation size and the platformer
## adapts to them:
##   deck -> presentation scale -> slide placement -> walkable rects
##   (measured by the renderer, or estimated from shapes headlessly)
##   -> platform candidates -> per-deck jump calibration -> layout.
## Side-scroll only so far; vertical/big-canvas layouts plug in the same way.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const JumpCalibrator = preload("res://course_generation/jump_calibrator.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

## Logical design resolution (project.godot viewport size).
const VIEW_SIZE := Vector2(1280, 720)
## Screen space kept for the stage strip below the slide and a top margin.
const STAGE_PX: float = 44.0
const TOP_MARGIN_PX: float = 12.0
const SIDE_MARGIN_FRACTION: float = 0.97
## Rotated content doesn't make a sensible flat ledge.
const MAX_PLATFORM_ROTATION_DEG: float = 3.0

## px per cm so one slide fills the screen the way a projector shows it.
static func presentation_scale(deck: PresentationModel.SlideDeck) -> float:
	if deck.slides.is_empty():
		return 40.0
	var canvas := Vector2(deck.slides[0].canvas_w, deck.slides[0].canvas_h)
	return min(VIEW_SIZE.x * SIDE_MARGIN_FRACTION / canvas.x,
		(VIEW_SIZE.y - STAGE_PX - TOP_MARGIN_PX) / canvas.y)

## Headless estimate of walkable rects straight from shape frames (the
## renderer supplies measured text bounds instead when it runs).
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

static func generate(slide_rects: Array[Rect2], per_slide_walkables: Array) -> CourseModel.Layout:
	var per_slide_candidates: Array = []
	for i in range(slide_rects.size()):
		per_slide_candidates.append(PlatformCandidateBuilder.build(per_slide_walkables[i]))
	var layout: CourseModel.Layout = LayoutSidescroll.build(slide_rects, per_slide_candidates)
	layout.jump_profile = JumpCalibrator.calibrate(layout)
	return layout
