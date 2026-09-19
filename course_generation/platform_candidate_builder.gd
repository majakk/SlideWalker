extends RefCounted
class_name PlatformCandidateBuilder
## Turns a slide's walkable rectangles (slide-local presentation px) into
## platform candidates: each rectangle's top edge is a walkable segment.
## Near-coincident overlapping edges merge so dense slides don't produce
## bumpy micro-platforms.

## Narrower edges (px) are too thin to stand on.
const MIN_WIDTH_PX: float = 24.0
## Top edges within this vertical distance (px) that overlap horizontally
## become one platform.
const MERGE_Y_EPSILON_PX: float = 6.0

class Candidate:
	extends RefCounted
	var left: float = 0.0
	var right: float = 0.0
	var top: float = 0.0

static func build(walkables: Array[Rect2]) -> Array[Candidate]:
	var raw: Array[Candidate] = []
	for r in walkables:
		if r.size.x < MIN_WIDTH_PX:
			continue
		var c := Candidate.new()
		c.left = r.position.x
		c.right = r.end.x
		c.top = r.position.y
		raw.append(c)

	raw.sort_custom(func(a: Candidate, b: Candidate) -> bool: return a.top < b.top)
	var merged: Array[Candidate] = []
	for c in raw:
		var absorbed := false
		for existing in merged:
			var y_close: bool = abs(existing.top - c.top) <= MERGE_Y_EPSILON_PX
			var x_overlaps: bool = c.left < existing.right and c.right > existing.left
			if y_close and x_overlaps:
				existing.top = min(existing.top, c.top)
				existing.left = min(existing.left, c.left)
				existing.right = max(existing.right, c.right)
				absorbed = true
				break
		if not absorbed:
			merged.append(c)
	return merged
