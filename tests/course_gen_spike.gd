extends SceneTree
## Course-generation check on every deck in presentations_testing/, for all
## three course types: calibrated jump, ledge coverage, and (climb) that the
## top slide is reachable from the start, with how many helper rungs that
## took. Walkables are estimated from shape frames here; the in-game
## renderer measures real text lines.
## Run with: godot --headless -s res://tests/course_gen_spike.gd

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const Reachability = preload("res://course_generation/reachability.gd")

func _initialize() -> void:
	var dir := DirAccess.open("res://presentations_testing")
	if dir == null:
		print("No presentations_testing/ directory found.")
		quit()
		return
	for f in dir.get_files():
		if f.to_lower().ends_with(".pptx"):
			_report("res://presentations_testing/".path_join(f))
	quit()

func _report(path: String) -> void:
	print("==== ", path.get_file(), " ====")
	var deck = PptxParser.parse(path)
	var scale: float = CourseGenerator.presentation_scale(deck)
	var walkables: Array = []
	for m in deck.slides:
		walkables.append(CourseGenerator.walkables_from_shapes(m, scale))

	for mode in [CourseGenerator.Mode.SIDE_SCROLL, CourseGenerator.Mode.CLIMB, CourseGenerator.Mode.DROP, CourseGenerator.Mode.SPIRAL]:
		var rects: Array[Rect2] = CourseGenerator.place_slides(CourseGenerator.slide_sizes(deck, scale), mode)
		var layout: CourseModel.Layout = CourseGenerator.generate(rects, walkables, mode)
		var profile = layout.jump_profile
		var reach: Dictionary = Reachability.reachable_set(layout.platforms, profile, [layout.start_index])
		var helpers: int = 0
		var last_floor: int = -1
		for i in range(layout.platforms.size()):
			var p: CourseModel.Platform = layout.platforms[i]
			if p.kind == CourseModel.Platform.Kind.HELPER:
				helpers += 1
			if p.kind == CourseModel.Platform.Kind.FLOOR and p.slide_index == rects.size() - 1:
				last_floor = i
		var line: String = "%-11s apex %3.0fpx, %3d platforms, reachable from start %3d/%3d" % [
			CourseGenerator.Mode.keys()[mode], profile.apex_height, layout.platforms.size(),
			reach.size(), layout.platforms.size()]
		if mode == CourseGenerator.Mode.CLIMB:
			line += ", helper rungs %d, top slide reachable: %s" % [helpers, reach.has(last_floor)]
		if mode == CourseGenerator.Mode.SPIRAL:
			var floors: int = 0
			var floors_reached: int = 0
			for i in range(layout.platforms.size()):
				if layout.platforms[i].kind == CourseModel.Platform.Kind.FLOOR:
					floors += 1
					if reach.has(i):
						floors_reached += 1
			line += ", helper rungs %d, rows reachable %d/%d" % [helpers, floors_reached, floors]
		print(line)
	print("")
