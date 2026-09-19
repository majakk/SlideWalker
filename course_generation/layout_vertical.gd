extends RefCounted
## Slides stacked vertically at presentation scale.
##
## CLIMB: slide 1 at the bottom; climb upward. Each slide's bottom edge is a
## jump-through floor into the slide above. Where the content alone can't
## get you up to the next slide, climbing rungs are added just outside the
## slide's right edge - never on the slide itself.
##
## DROP: slide 1 at the top; start on its highest ledge and drop down
## (press down) through lines and floors. Always completable by design.

const CourseModel = preload("res://course_generation/course_model.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
const Reachability = preload("res://course_generation/reachability.gd")

## Stage band between stacked slides (slide numbers live here).
const SLIDE_GAP_PX: float = 110.0
## Room beside each slide for helper rungs; the camera keeps it in view.
const SIDE_ZONE_PX: float = 140.0
const RUNG_OFFSET_PX: float = 26.0
const RUNG_WIDTH_PX: float = 84.0
## Rung spacing as a fraction of the single-jump apex: easy, relaxed hops.
const RUNG_SPACING_FRACTION: float = 0.7
const BOTTOM_STAGE_DEPTH_PX: float = 200.0
const HEADROOM_ABOVE_PX: float = 2000.0

## World rect of each slide, deck order. CLIMB stacks upward from y=0,
## DROP stacks downward from y=0.
static func place_slides(sizes: Array[Vector2], climb: bool) -> Array[Rect2]:
	var max_w: float = 0.0
	for s in sizes:
		max_w = max(max_w, s.x)
	var rects: Array[Rect2] = []
	var cursor: float = 0.0
	for s in sizes:
		var x: float = (max_w - s.x) * 0.5
		if climb:
			rects.append(Rect2(Vector2(x, cursor - s.y), s))
			cursor -= s.y + SLIDE_GAP_PX
		else:
			rects.append(Rect2(Vector2(x, cursor), s))
			cursor += s.y + SLIDE_GAP_PX
	return rects

static func build(slide_rects: Array[Rect2], per_slide_candidates: Array, profile, climb: bool) -> CourseModel.Layout:
	var layout := CourseModel.Layout.new()
	layout.slide_rects = slide_rects
	layout.vertical = true
	layout.side_zone = SIDE_ZONE_PX
	var n: int = slide_rects.size()
	# The slide at the bottom of the stack gets the solid floor.
	var bottom_slide: int = 0 if climb else n - 1

	var left: float = INF
	var right: float = -INF
	var top: float = INF
	var bottom: float = -INF
	var floor_indices: Array[int] = []
	for i in range(n):
		var r: Rect2 = slide_rects[i]
		left = min(left, r.position.x - SIDE_ZONE_PX)
		right = max(right, r.end.x + SIDE_ZONE_PX)
		top = min(top, r.position.y)
		bottom = max(bottom, r.end.y)

		var floor_platform := CourseModel.Platform.new()
		floor_platform.x = r.position.x - SIDE_ZONE_PX
		floor_platform.y = r.end.y
		floor_platform.width = r.size.x + SIDE_ZONE_PX * 2.0
		floor_platform.kind = CourseModel.Platform.Kind.FLOOR
		floor_platform.solid = i == bottom_slide
		floor_platform.slide_index = i
		floor_indices.append(layout.platforms.size())
		layout.platforms.append(floor_platform)

		var depth: float = BOTTOM_STAGE_DEPTH_PX if i == bottom_slide else SLIDE_GAP_PX
		layout.stage_rects.append(Rect2(r.position.x - SIDE_ZONE_PX, r.end.y, r.size.x + SIDE_ZONE_PX * 2.0, depth))

	for i in range(n):
		for p in LayoutSidescroll.slide_ledges(slide_rects[i], per_slide_candidates[i], i):
			layout.platforms.append(p)

	layout.world_bounds = Rect2(left, top - HEADROOM_ABOVE_PX, right - left,
		bottom - top + HEADROOM_ABOVE_PX + BOTTOM_STAGE_DEPTH_PX)

	if climb:
		layout.start_index = floor_indices[0]
		layout.entry_position = Vector2(slide_rects[0].position.x + 60.0, slide_rects[0].end.y - 30.0)
		_add_rungs(layout, floor_indices, profile)
	else:
		layout.start_index = _highest_ledge(layout, 0, floor_indices[0])
		var s: CourseModel.Platform = layout.platforms[layout.start_index]
		layout.entry_position = Vector2(s.x + min(40.0, s.width * 0.5), s.y - 30.0)
	return layout

## Adds rung columns beside slide k wherever slide k+1's floor isn't
## reachable yet from the start.
static func _add_rungs(layout: CourseModel.Layout, floor_indices: Array[int], profile) -> void:
	var spacing: float = profile.apex_height * RUNG_SPACING_FRACTION
	var reach: Dictionary = Reachability.reachable_set(layout.platforms, profile, [layout.start_index])
	for k in range(floor_indices.size() - 1):
		if reach.has(floor_indices[k + 1]):
			continue
		var from_y: float = layout.platforms[floor_indices[k]].y
		var to_y: float = layout.platforms[floor_indices[k + 1]].y
		var r: Rect2 = layout.slide_rects[k]
		var y: float = from_y - spacing
		while y > to_y + spacing * 0.5:
			var rung := CourseModel.Platform.new()
			rung.x = r.end.x + RUNG_OFFSET_PX
			rung.y = y
			rung.width = RUNG_WIDTH_PX
			rung.kind = CourseModel.Platform.Kind.HELPER
			rung.slide_index = k
			layout.platforms.append(rung)
			y -= spacing
		reach = Reachability.reachable_set(layout.platforms, profile, [layout.start_index])

static func _highest_ledge(layout: CourseModel.Layout, slide_index: int, fallback: int) -> int:
	var best: int = fallback
	for i in range(layout.platforms.size()):
		var p: CourseModel.Platform = layout.platforms[i]
		if p.kind == CourseModel.Platform.Kind.CONTENT and p.slide_index == slide_index \
				and p.y < layout.platforms[best].y:
			best = i
	return best
