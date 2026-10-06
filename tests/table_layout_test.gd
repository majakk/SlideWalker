extends SceneTree
## Tables are sized from their grid, not the graphicFrame's <p:xfrm> extent:
## Google Slides exports every table with a fixed 3000000x3000000 EMU
## (8.33cm square) placeholder extent, which stretched one-row tables into
## tall boxes running off the slide. Builds a synthetic graphicFrame (same
## {tag, attrs, children, text} shape zip_xml_utils.gd produces) and checks
## the table and cell rectangles against hand-calculated values.
##
## Frame: off=(2,3)cm  ext=(8.33,8.33)cm (the Google placeholder)
## Grid:  cols 1cm, 2cm, 3cm   rows 0.5cm, 0.75cm
##   row 0: "A" with gridSpan=2 (+ hMerge cell), "B"
##   row 1: "C", "D", "E"
##   -> table: pos=(2,3) size=(6,1.25)
##   -> "A" (2,3) 3x0.5   "B" (5,3) 3x0.5   "E" (5,3.5) 3x0.75
##
## Run with: godot --headless -s res://tests/table_layout_test.gd

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")

const EMU_PER_CM: float = 360000.0

func _emu(cm: float) -> String:
	return str(int(round(cm * EMU_PER_CM)))

func _node(tag: String, attrs: Dictionary = {}, children: Array = [], text: String = "") -> Dictionary:
	return {"tag": tag, "attrs": attrs, "children": children, "text": text}

func _cell(text: String, attrs: Dictionary = {}) -> Dictionary:
	var runs: Array = [] if text == "" else [_node("a:r", {}, [_node("a:t", {}, [], text)])]
	return _node("a:tc", attrs, [
		_node("a:txBody", {}, [_node("a:bodyPr"), _node("a:p", {}, runs)]),
		_node("a:tcPr"),
	])

func _near(s: PresentationModel.ShapeRect, x: float, y: float, w: float, h: float) -> bool:
	return Vector2(s.x, s.y).distance_to(Vector2(x, y)) < 0.001 \
		and Vector2(s.w, s.h).distance_to(Vector2(w, h)) < 0.001

func _initialize() -> void:
	var tbl := _node("a:tbl", {}, [
		_node("a:tblGrid", {}, [
			_node("a:gridCol", {"w": _emu(1.0)}),
			_node("a:gridCol", {"w": _emu(2.0)}),
			_node("a:gridCol", {"w": _emu(3.0)}),
		]),
		_node("a:tr", {"h": _emu(0.5)}, [_cell("A", {"gridSpan": "2"}), _cell("", {"hMerge": "1"}), _cell("B")]),
		_node("a:tr", {"h": _emu(0.75)}, [_cell("C"), _cell("D"), _cell("E")]),
	])
	var frame := _node("p:graphicFrame", {}, [
		_node("p:nvGraphicFramePr", {}, [_node("p:cNvPr", {"id": "7", "name": "Table"})]),
		_node("p:xfrm", {}, [
			_node("a:off", {"x": _emu(2.0), "y": _emu(3.0)}),
			_node("a:ext", {"cx": "3000000", "cy": "3000000"}),
		]),
		_node("a:graphic", {}, [_node("a:graphicData", {}, [tbl])]),
	])
	var sp_tree := _node("p:spTree", {}, [frame])

	var manifest := PresentationModel.SlideManifest.new()
	manifest.canvas_w = 25.4
	manifest.canvas_h = 14.29
	var ctx := PptxParser.SlideContext.new()
	ctx.doc = PptxParser.Doc.new()
	ctx.slide = PptxParser.Part.new()
	ctx.layout = PptxParser.Part.new()
	ctx.master = PptxParser.Part.new()
	ctx.theme = preload("res://presentation_import/pptx_theme.gd").new()
	var identity: Dictionary = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
	PptxParser._walk_shape_tree(sp_tree, identity, ctx.slide, ctx, manifest)

	var by_text: Dictionary = {}
	var table: PresentationModel.ShapeRect = null
	for s in manifest.shapes:
		print("%s pos=(%.3f,%.3f) size=(%.3f,%.3f) text=%s" % [s.id, s.x, s.y, s.w, s.h, s.text_summary])
		if s.type == PresentationModel.ShapeRect.Type.TABLE:
			table = s
		elif s.is_table_cell:
			by_text[s.text_summary] = s

	var ok: bool = table != null and manifest.shapes.size() == 6
	ok = ok and _near(table, 2.0, 3.0, 6.0, 1.25)
	ok = ok and by_text.has("A") and _near(by_text["A"], 2.0, 3.0, 3.0, 0.5)
	ok = ok and by_text.has("B") and _near(by_text["B"], 5.0, 3.0, 3.0, 0.5)
	ok = ok and by_text.has("E") and _near(by_text["E"], 5.0, 3.5, 3.0, 0.75)
	# Only the table as a whole is a platform, not every row boundary.
	ok = ok and CourseGenerator.is_platform_shape(table)
	for cell in by_text.values():
		ok = ok and not CourseGenerator.is_platform_shape(cell)

	print("TABLE LAYOUT TEST: ", "PASS" if ok else "FAIL")
	quit()
