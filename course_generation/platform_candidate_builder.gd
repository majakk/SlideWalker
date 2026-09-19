extends RefCounted
class_name PlatformCandidateBuilder
## Turns a slide's shapes into platform candidates: each shape's top edge is
## a walkable segment. Near-coincident overlapping candidates are merged
## (highest z-order/topmost-drawn shape wins) so dense decks don't produce
## bumpy micro-platform noise.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")

## Shapes narrower than this (cm) are dropped as platform candidates -
## too thin to stand on - but still render as scenery in later milestones.
const MIN_WIDTH_CM: float = 1.0
## Top edges within this vertical distance (cm), with overlapping
## horizontal spans, are treated as the same platform.
const MERGE_Y_EPSILON_CM: float = 0.3

class Candidate:
	extends RefCounted
	var left_cm: float = 0.0
	var right_cm: float = 0.0
	var top_cm: float = 0.0
	var z_order: int = -1
	var source_shape: PresentationModel.ShapeRect = null

static func build(manifest: PresentationModel.SlideManifest) -> Array[Candidate]:
	var raw: Array[Candidate] = []
	for shape in manifest.shapes:
		if shape.w < MIN_WIDTH_CM:
			continue
		var c := Candidate.new()
		c.left_cm = shape.x
		c.right_cm = shape.x + shape.w
		c.top_cm = shape.y
		c.z_order = shape.z_order
		c.source_shape = shape
		raw.append(c)
	return _merge(raw)

static func _merge(raw: Array[Candidate]) -> Array[Candidate]:
	raw.sort_custom(func(a: Candidate, b: Candidate) -> bool: return a.top_cm < b.top_cm)
	var merged: Array[Candidate] = []
	for c in raw:
		var absorbed := false
		for existing in merged:
			var y_close: bool = abs(existing.top_cm - c.top_cm) <= MERGE_Y_EPSILON_CM
			var x_overlaps: bool = c.left_cm < existing.right_cm and c.right_cm > existing.left_cm
			if y_close and x_overlaps:
				if c.z_order > existing.z_order:
					existing.top_cm = c.top_cm
					existing.z_order = c.z_order
					existing.source_shape = c.source_shape
				existing.left_cm = min(existing.left_cm, c.left_cm)
				existing.right_cm = max(existing.right_cm, c.right_cm)
				absorbed = true
				break
		if not absorbed:
			merged.append(c)
	return merged
