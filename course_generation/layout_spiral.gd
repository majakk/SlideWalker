extends RefCounted
## Prezi-style "big canvas": slides on a 2D grid in a square spiral winding
## outward from slide 1 in the middle - right, up, left, left, down, down,
## right x3, up x3, ... Every grid row shares one floor across the whole
## canvas, so walking sideways reaches the neighbouring slide in the row;
## rows are jump-through, so you can climb into the row above or drop into
## the row below - skipping ahead or back between rings of the spiral.
## Where a row can't be reached from below with the slides' own content,
## helper rungs are added at the canvas's right edge (never on a slide).

const CourseModel = preload("res://course_generation/course_model.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
const Reachability = preload("res://course_generation/reachability.gd")

const COLUMN_GAP_PX: float = 160.0
## Stage band between rows (slide numbers live here).
const ROW_GAP_PX: float = 110.0
const SIDE_ZONE_PX: float = 140.0
const RUNG_OFFSET_PX: float = 26.0
const RUNG_WIDTH_PX: float = 84.0
const RUNG_SPACING_FRACTION: float = 0.7
const BOTTOM_STAGE_DEPTH_PX: float = 200.0
const HEADROOM_ABOVE_PX: float = 2000.0

## Grid cell (x right, y up) of each slide along the square spiral.
static func spiral_cells(count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var pos := Vector2i.ZERO
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var dir: int = 0
	var leg: int = 1
	cells.append(pos)
	while cells.size() < count:
		# Leg lengths go 1, 1, 2, 2, 3, 3, ...
		for _twice in range(2):
			for _step in range(leg):
				if cells.size() >= count:
					return cells
				pos += dirs[dir]
				cells.append(pos)
			dir = (dir + 1) % 4
		leg += 1
	return cells

static func place_slides(sizes: Array[Vector2]) -> Array[Rect2]:
	var cell_size := Vector2.ZERO
	for s in sizes:
		cell_size = Vector2(max(cell_size.x, s.x), max(cell_size.y, s.y))
	var pitch := cell_size + Vector2(COLUMN_GAP_PX, ROW_GAP_PX)
	var rects: Array[Rect2] = []
	var cells: Array[Vector2i] = spiral_cells(sizes.size())
	for i in range(sizes.size()):
		var c: Vector2i = cells[i]
		# Row y=0 sits on world y=0; rows above extend upward (negative y).
		var bottom: float = -c.y * pitch.y
		var x: float = c.x * pitch.x + (cell_size.x - sizes[i].x) * 0.5
		rects.append(Rect2(Vector2(x, bottom - sizes[i].y), sizes[i]))
	return rects

static func build(slide_rects: Array[Rect2], per_slide_candidates: Array, profile) -> CourseModel.Layout:
	var layout := CourseModel.Layout.new()
	layout.slide_rects = slide_rects
	layout.vertical = false
	layout.two_d = true
	layout.side_zone = SIDE_ZONE_PX

	var left: float = INF
	var right: float = -INF
	var top: float = INF
	var row_bottoms: Array[float] = []
	for r in slide_rects:
		left = min(left, r.position.x - SIDE_ZONE_PX)
		right = max(right, r.end.x + SIDE_ZONE_PX)
		top = min(top, r.position.y)
		if not row_bottoms.has(r.end.y):
			row_bottoms.append(r.end.y)
	# Lowest row first (largest y).
	row_bottoms.sort()
	row_bottoms.reverse()

	var floor_indices: Array[int] = []
	for i in range(row_bottoms.size()):
		var y: float = row_bottoms[i]
		var floor_platform := CourseModel.Platform.new()
		floor_platform.x = left
		floor_platform.y = y
		floor_platform.width = right - left
		floor_platform.kind = CourseModel.Platform.Kind.FLOOR
		floor_platform.solid = i == 0
		floor_indices.append(layout.platforms.size())
		layout.platforms.append(floor_platform)
		var depth: float = BOTTOM_STAGE_DEPTH_PX if i == 0 else ROW_GAP_PX
		layout.stage_rects.append(Rect2(left, y, right - left, depth))

	for i in range(slide_rects.size()):
		for p in LayoutSidescroll.slide_ledges(slide_rects[i], per_slide_candidates[i], i):
			layout.platforms.append(p)

	var bottom: float = row_bottoms[0]
	layout.world_bounds = Rect2(left, top - HEADROOM_ABOVE_PX, right - left,
		bottom - top + HEADROOM_ABOVE_PX + BOTTOM_STAGE_DEPTH_PX)

	var start_row: int = row_bottoms.find(slide_rects[0].end.y)
	layout.start_index = floor_indices[start_row]
	layout.entry_position = Vector2(slide_rects[0].position.x + 60.0, slide_rects[0].end.y - 30.0)
	_add_rungs(layout, floor_indices, right - SIDE_ZONE_PX, profile)
	return layout

## Walking up the rows from the bottom: wherever a row's floor isn't
## reachable yet, add a rung column up from the row below it.
static func _add_rungs(layout: CourseModel.Layout, floor_indices: Array[int], canvas_right: float, profile) -> void:
	var spacing: float = profile.apex_height * RUNG_SPACING_FRACTION
	var reach: Dictionary = Reachability.reachable_set(layout.platforms, profile, [layout.start_index])
	for row in range(1, floor_indices.size()):
		if reach.has(floor_indices[row]):
			continue
		var from_y: float = layout.platforms[floor_indices[row - 1]].y
		var to_y: float = layout.platforms[floor_indices[row]].y
		var y: float = from_y - spacing
		while y > to_y + spacing * 0.5:
			var rung := CourseModel.Platform.new()
			rung.x = canvas_right + RUNG_OFFSET_PX
			rung.y = y
			rung.width = RUNG_WIDTH_PX
			rung.kind = CourseModel.Platform.Kind.HELPER
			layout.platforms.append(rung)
			y -= spacing
		reach = Reachability.reachable_set(layout.platforms, profile, [layout.start_index])
