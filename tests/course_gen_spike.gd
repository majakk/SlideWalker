extends SceneTree
## Course-generation check on every deck in presentations_testing/: presentation
## scale, calibrated jump profile, and ledge coverage (how many content ledges
## are reachable through jump chains from the floor). Walkables are estimated
## from shape frames here; the in-game renderer measures real text bounds.
## Run with: godot --headless -s res://tests/course_gen_spike.gd

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const LayoutSidescroll = preload("res://course_generation/layout_sidescroll.gd")
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
	var rects: Array[Rect2] = LayoutSidescroll.place_slides(deck, scale)
	var walkables: Array = []
	for m in deck.slides:
		walkables.append(CourseGenerator.walkables_from_shapes(m, scale))
	var layout: CourseModel.Layout = CourseGenerator.generate(rects, walkables)
	var profile = layout.jump_profile

	print("scale %.1f px/cm, slide %.0fx%.0f px, apex %.0f px (%.1f bodies), t_apex %.2fs, g %.0f" % [
		scale, rects[0].size.x, rects[0].size.y, profile.apex_height,
		profile.apex_height / profile.BODY_HEIGHT, profile.time_to_apex, profile.gravity])

	var floor_count: int = layout.platforms.filter(
		func(p: CourseModel.Platform) -> bool: return p.kind == CourseModel.Platform.Kind.FLOOR).size()
	print("floor segments: %d (must be 1), ledges reachable: %d/%d" % [
		floor_count, Reachability.ledge_coverage(layout.platforms, profile),
		layout.platforms.size() - floor_count])
	print("")
