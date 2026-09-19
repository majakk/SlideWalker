extends SceneTree
## M1 spike: parse the real sample decks in presentations_testing/ and print
## coverage stats, to validate the pure-GDScript pptx parsing bet before
## building course-gen on top of it. Run with:
##   godot --headless -s res://tests/parse_spike.gd

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

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
	var deck := PptxParser.parse(path)
	print("slides: ", deck.slides.size())

	var total_shapes := 0
	var explicit_count := 0
	var fallback_count := 0
	var type_counts: Dictionary = {}
	var image_refs: Array[String] = []

	for slide in deck.slides:
		for shape in slide.shapes:
			total_shapes += 1
			if shape.position_is_explicit:
				explicit_count += 1
			else:
				fallback_count += 1
			var type_name: String = PresentationModel.ShapeRect.Type.keys()[shape.type]
			type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1
			if shape.image_ref != "":
				image_refs.append(shape.image_ref)

	print("total shapes: ", total_shapes)
	print("explicit-position: ", explicit_count, "  fallback-position: ", fallback_count)
	print("by type: ", type_counts)
	print("image refs found: ", image_refs.size())

	var zip := ZIPReader.new()
	if zip.open(path) == OK:
		var missing := 0
		for ref in image_refs:
			if not zip.file_exists(ref):
				missing += 1
				print("  MISSING media: ", ref)
		print("image refs missing from archive: ", missing)
		zip.close()

	for i in range(min(5, deck.slides.size())):
		var s: PresentationModel.SlideManifest = deck.slides[i]
		print("  slide ", s.slide_id, " (", s.canvas_w, "x", s.canvas_h, "cm): ", s.shapes.size(), " shapes")
		for shape in s.shapes:
			var label: String = shape.text_summary if shape.text_summary != "" else shape.image_ref
			print("    - ", PresentationModel.ShapeRect.Type.keys()[shape.type], " @ (",
				"%.1f" % shape.x, ",", "%.1f" % shape.y, ") ",
				"%.1f" % shape.w, "x", "%.1f" % shape.h, "cm",
				" explicit=", shape.position_is_explicit,
				"  ", label.left(40))
	print("")
