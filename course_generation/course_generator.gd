extends RefCounted
class_name CourseGenerator
## Orchestrator: parsed deck -> candidate extraction -> deck-wide scale
## calibration -> mode-specific layout. Side-scroll only for M2;
## layout_vertical.gd / layout_bigcanvas.gd plug in the same way later.

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
const ScaleCalibrator = preload("res://course_generation/scale_calibrator.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
const CourseModel = preload("res://course_generation/course_model.gd")

static func generate_from_pptx(path: String) -> CourseModel.Layout:
	return generate_from_deck(PptxParser.parse(path))

static func generate_from_deck(deck: PresentationModel.SlideDeck) -> CourseModel.Layout:
	var per_slide_candidates: Array = []
	for manifest in deck.slides:
		per_slide_candidates.append(PlatformCandidateBuilder.build(manifest))

	var scale: float = ScaleCalibrator.calibrate(per_slide_candidates)
	return LayoutSidescroll.build(deck, scale)
