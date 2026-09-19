extends SceneTree
## Neither real sample deck contains a <p:grpSp>, so the nested group-
## transform composition math in pptx_parser.gd is otherwise unexercised.
## This builds a synthetic shape tree (bypassing ZIPReader/XMLParser
## entirely) matching the {tag, attrs, children, text} shape that
## zip_xml_utils.gd produces, and checks the composed position/size against
## hand-calculated expected values.
##
## Group: off=(1,2)cm  ext=(10,5)cm  chOff=(0,0)cm  chExt=(5,2.5)cm
##   -> scale = (10/5, 5/2.5) = (2, 2)
## Child sp: off=(2.5,1.25)cm  ext=(1,1)cm  (local, in chOff/chExt space)
##   -> expected final: pos = (1,2) + (2.5,1.25)*2 = (6, 4.5) cm
##   -> expected final: size = (1,1)*2 = (2, 2) cm
##
## Run with: godot --headless -s res://tests/group_transform_test.gd

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

const EMU_PER_CM: float = 360000.0

func _emu(cm: float) -> String:
	return str(int(cm * EMU_PER_CM))

func _point_node(tag: String, x_attr: String, y_attr: String, x_cm: float, y_cm: float) -> Dictionary:
	var attrs: Dictionary = {}
	attrs[x_attr] = _emu(x_cm)
	attrs[y_attr] = _emu(y_cm)
	return {"tag": tag, "attrs": attrs, "children": [], "text": ""}

func _initialize() -> void:
	var child_xfrm: Dictionary = {
		"tag": "a:xfrm", "attrs": {}, "text": "",
		"children": [
			_point_node("a:off", "x", "y", 2.5, 1.25),
			_point_node("a:ext", "cx", "cy", 1.0, 1.0),
		],
	}
	var child_sp: Dictionary = {
		"tag": "p:sp", "attrs": {}, "text": "",
		"children": [
			{"tag": "p:nvSpPr", "attrs": {}, "text": "", "children": [
				{"tag": "p:cNvPr", "attrs": {"id": "2", "name": "TestShape"}, "text": "", "children": []},
			]},
			{"tag": "p:spPr", "attrs": {}, "text": "", "children": [child_xfrm]},
		],
	}
	var group_xfrm: Dictionary = {
		"tag": "a:xfrm", "attrs": {}, "text": "",
		"children": [
			_point_node("a:off", "x", "y", 1.0, 2.0),
			_point_node("a:ext", "cx", "cy", 10.0, 5.0),
			_point_node("a:chOff", "x", "y", 0.0, 0.0),
			_point_node("a:chExt", "cx", "cy", 5.0, 2.5),
		],
	}
	var group_sp: Dictionary = {
		"tag": "p:grpSp", "attrs": {}, "text": "",
		"children": [
			{"tag": "p:grpSpPr", "attrs": {}, "text": "", "children": [group_xfrm]},
			child_sp,
		],
	}
	var sp_tree: Dictionary = {
		"tag": "p:spTree", "attrs": {}, "text": "",
		"children": [group_sp],
	}

	var manifest := PresentationModel.SlideManifest.new()
	manifest.canvas_w = 25.4
	manifest.canvas_h = 14.29

	# The child is a filled rectangle so it counts as visible.
	(child_sp["children"][1]["children"] as Array).append({
		"tag": "a:solidFill", "attrs": {}, "text": "",
		"children": [{"tag": "a:srgbClr", "attrs": {"val": "336699"}, "text": "", "children": []}],
	})

	var ctx := PptxParser.SlideContext.new()
	ctx.doc = PptxParser.Doc.new()
	ctx.slide = PptxParser.Part.new()
	ctx.layout = PptxParser.Part.new()
	ctx.master = PptxParser.Part.new()
	ctx.theme = preload("res://presentation_import/pptx_theme.gd").new()
	var identity: Dictionary = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
	PptxParser._walk_shape_tree(sp_tree, identity, ctx.slide, ctx, manifest)

	print("shapes found: ", manifest.shapes.size())
	var ok: bool = manifest.shapes.size() == 1
	if ok:
		var s: PresentationModel.ShapeRect = manifest.shapes[0]
		print("got: pos=(%.3f,%.3f) size=(%.3f,%.3f)" % [s.x, s.y, s.w, s.h])
		var expected_pos := Vector2(6.0, 4.5)
		var expected_size := Vector2(2.0, 2.0)
		var pos_ok: bool = Vector2(s.x, s.y).distance_to(expected_pos) < 0.001
		var size_ok: bool = Vector2(s.w, s.h).distance_to(expected_size) < 0.001
		ok = pos_ok and size_ok
		print("expected: pos=(6.000,4.500) size=(2.000,2.000)")

	print("GROUP TRANSFORM TEST: ", "PASS" if ok else "FAIL")
	quit()
