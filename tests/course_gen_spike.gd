extends SceneTree
## M2 spike: generate a course from each real sample deck and verify the
## floor safety net is genuinely continuous (the completability guarantee).
## Run with: godot --headless -s res://tests/course_gen_spike.gd

const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const JumpPhysics = preload("res://autoload/JumpPhysics.gd")

func _initialize() -> void:
	var dir := DirAccess.open("res://presentations_testing")
	if dir == null:
		print("No presentations_testing/ directory found.")
		quit()
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".pptx"):
			_report("res://presentations_testing/".path_join(file_name))
		file_name = dir.get_next()
	quit()

func _report(path: String) -> void:
	print("==== ", path, " ====")
	var layout: CourseModel.Layout = CourseGenerator.generate_from_pptx(path)
	print("platforms: ", layout.platforms.size(), "  world_width: ", "%.0f" % layout.world_width)

	var floor_count := 0
	var content_count := 0
	for p in layout.platforms:
		if p.kind == CourseModel.Platform.Kind.FLOOR:
			floor_count += 1
		else:
			content_count += 1
	print("floor segments: ", floor_count, "  content platforms: ", content_count)

	var floors: Array = layout.platforms.filter(func(p: CourseModel.Platform) -> bool: return p.kind == CourseModel.Platform.Kind.FLOOR)
	floors.sort_custom(func(a: CourseModel.Platform, b: CourseModel.Platform) -> bool: return a.x < b.x)
	var max_gap := 0.0
	for i in range(1, floors.size()):
		var prev: CourseModel.Platform = floors[i - 1]
		var cur: CourseModel.Platform = floors[i]
		max_gap = max(max_gap, cur.x - (prev.x + prev.width))
	print("max floor gap (px, must be ~0): ", "%.2f" % max_gap)

	# Informational coverage: BFS from the floor through jump-reachable
	# platform chains. M2 doesn't repair unreachable content yet - that's the
	# coverage-optimization pass in a later milestone.
	var platforms: Array = layout.platforms
	var visited: Dictionary = {}
	var queue: Array = []
	for i in range(platforms.size()):
		if platforms[i].kind == CourseModel.Platform.Kind.FLOOR:
			visited[i] = true
			queue.append(i)
	while not queue.is_empty():
		var a: CourseModel.Platform = platforms[queue.pop_front()]
		for j in range(platforms.size()):
			if visited.has(j):
				continue
			var b: CourseModel.Platform = platforms[j]
			var dx: float = max(0.0, max(b.x - (a.x + a.width), a.x - (b.x + b.width)))
			var dy: float = a.y - b.y
			if JumpPhysics.reachable(dx, dy):
				visited[j] = true
				queue.append(j)
	print("content coverage (reachable via jump chains from floor): ",
		visited.size() - floor_count, "/", content_count)
	print("")
