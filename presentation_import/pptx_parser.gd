extends RefCounted
class_name PptxParser
## Parses a .pptx (OOXML) file into a PresentationModel.SlideDeck using only
## Godot's built-in ZIPReader/XMLParser — no external dependency.
##
## v1 scope cuts (see plan): shape rotation is ignored (position/size only);
## tables/charts/SmartArt are treated as opaque bounding boxes; shapes
## without an explicit <a:xfrm> (placeholder-inherited from a layout/master)
## get a deterministic fallback slot instead of full layout/master chasing.

const ZipXmlUtils = preload("res://presentation_import/zip_xml_utils.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

const EMU_PER_CM: float = 360000.0

class ParseContext:
	extends RefCounted
	var z_counter: int = 0
	var fallback_cursor_y: float = 0.0

static func parse(path: String) -> PresentationModel.SlideDeck:
	var deck := PresentationModel.SlideDeck.new()
	deck.source_path = path

	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		push_warning("PptxParser: failed to open %s" % path)
		return deck

	var pres_tree: Dictionary = ZipXmlUtils.open_zip_entry_tree(zip, "ppt/presentation.xml")
	var pres_rels: Dictionary = _parse_rels(zip, "ppt/_rels/presentation.xml.rels", "ppt")
	var slide_size: Vector2 = _get_slide_size(pres_tree)
	var slide_targets: Array[String] = _get_ordered_slide_targets(pres_tree, pres_rels)

	var idx: int = 0
	for target in slide_targets:
		idx += 1
		var slide_tree: Dictionary = ZipXmlUtils.open_zip_entry_tree(zip, target)
		if slide_tree.is_empty():
			continue
		var rels_path: String = _rels_path_for(target)
		var slide_rels: Dictionary = _parse_rels(zip, rels_path, target.get_base_dir())
		deck.slides.append(_parse_slide(slide_tree, idx, slide_size, slide_rels))

	zip.close()
	return deck

# --- presentation.xml ---

static func _get_slide_size(pres_tree: Dictionary) -> Vector2:
	var sld_sz: Dictionary = ZipXmlUtils.find_first(pres_tree, "p:sldSz")
	if sld_sz.is_empty():
		return Vector2(25.4, 19.05)  # fallback: standard 10in x 7.5in in cm
	var attrs: Dictionary = sld_sz.get("attrs", {})
	var cx: float = float(attrs.get("cx", "9144000"))
	var cy: float = float(attrs.get("cy", "6858000"))
	return Vector2(cx / EMU_PER_CM, cy / EMU_PER_CM)

static func _get_ordered_slide_targets(pres_tree: Dictionary, pres_rels: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id_lst: Dictionary = ZipXmlUtils.find_first(pres_tree, "p:sldIdLst")
	if id_lst.is_empty():
		return out
	for sld_id in ZipXmlUtils.direct_children(id_lst, "p:sldId"):
		var rid: String = (sld_id.get("attrs", {}) as Dictionary).get("r:id", "")
		if pres_rels.has(rid):
			out.append(pres_rels[rid])
	return out

# --- relationship (.rels) resolution ---

static func _rels_path_for(target: String) -> String:
	return target.get_base_dir().path_join("_rels").path_join(target.get_file() + ".rels")

static func _parse_rels(zip: ZIPReader, rels_path: String, base_dir: String) -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ZipXmlUtils.open_zip_entry_tree(zip, rels_path)
	if tree.is_empty():
		return out
	for rel in ZipXmlUtils.find_all(tree, "Relationship"):
		var attrs: Dictionary = rel.get("attrs", {})
		var id: String = attrs.get("Id", "")
		var target: String = attrs.get("Target", "")
		var mode: String = attrs.get("TargetMode", "")
		if id == "" or target == "" or mode == "External":
			continue
		out[id] = _normalize_path(base_dir, target)
	return out

static func _normalize_path(base_dir: String, target: String) -> String:
	if target.begins_with("/"):
		return target.substr(1)
	var combined: String = base_dir.path_join(target)
	var parts: PackedStringArray = combined.split("/")
	var result: Array[String] = []
	for part in parts:
		if part == "..":
			if not result.is_empty():
				result.remove_at(result.size() - 1)
		elif part == "." or part == "":
			continue
		else:
			result.append(part)
	return "/".join(result)

# --- slide shape tree ---

static func _parse_slide(slide_tree: Dictionary, slide_index: int, slide_size: Vector2, slide_rels: Dictionary) -> PresentationModel.SlideManifest:
	var manifest := PresentationModel.SlideManifest.new()
	manifest.slide_id = slide_index
	manifest.canvas_w = slide_size.x
	manifest.canvas_h = slide_size.y

	var sp_tree: Dictionary = ZipXmlUtils.find_first(slide_tree, "p:spTree")
	if sp_tree.is_empty():
		return manifest

	var ctx := ParseContext.new()
	var identity: Dictionary = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
	_walk_shape_tree(sp_tree, identity, slide_rels, manifest, ctx)
	return manifest

static func _walk_shape_tree(container: Dictionary, transform: Dictionary, rels: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	for child in container.get("children", []):
		match String(child.get("tag", "")):
			"p:sp":
				_process_sp(child, transform, manifest, ctx)
			"p:pic":
				_process_pic(child, transform, rels, manifest, ctx)
			"p:graphicFrame":
				_process_graphic_frame(child, transform, manifest, ctx)
			"p:grpSp":
				_process_group(child, transform, rels, manifest, ctx)
			_:
				pass

static func _process_group(node: Dictionary, transform: Dictionary, rels: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	var grp_pr: Dictionary = ZipXmlUtils.find_first(node, "p:grpSpPr")
	var xfrm: Dictionary = ZipXmlUtils.find_first(grp_pr, "a:xfrm")
	if xfrm.is_empty():
		_walk_shape_tree(node, transform, rels, manifest, ctx)
		return

	var off: Vector2 = _read_point(xfrm, "a:off")
	var ext: Vector2 = _read_point(xfrm, "a:ext", "cx", "cy")
	var ch_off: Vector2 = _read_point(xfrm, "a:chOff")
	var ch_ext: Vector2 = _read_point(xfrm, "a:chExt", "cx", "cy")
	if ch_ext.x == 0.0 or ch_ext.y == 0.0:
		_walk_shape_tree(node, transform, rels, manifest, ctx)
		return

	var g_scale: Vector2 = Vector2(ext.x / ch_ext.x, ext.y / ch_ext.y)
	var g_trans: Vector2 = off - ch_off * g_scale
	var cur_scale: Vector2 = transform["scale"]
	var cur_trans: Vector2 = transform["trans"]
	var new_transform: Dictionary = {
		"scale": cur_scale * g_scale,
		"trans": cur_scale * g_trans + cur_trans,
	}
	_walk_shape_tree(node, new_transform, rels, manifest, ctx)

static func _process_sp(node: Dictionary, transform: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	var sp_pr: Dictionary = ZipXmlUtils.find_first(node, "p:spPr")
	var xfrm: Dictionary = ZipXmlUtils.find_first(sp_pr, "a:xfrm")

	var rect := PresentationModel.ShapeRect.new()
	rect.id = _get_shape_id(node)
	rect.z_order = ctx.z_counter
	ctx.z_counter += 1

	var text: String = _extract_text(node)
	rect.text_summary = text
	rect.type = PresentationModel.ShapeRect.Type.TEXT if text != "" else PresentationModel.ShapeRect.Type.SHAPE

	_apply_position(rect, xfrm, transform, manifest, ctx)
	if rect.w > 0.0 and rect.h > 0.0:
		manifest.shapes.append(rect)

static func _process_pic(node: Dictionary, transform: Dictionary, rels: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	var sp_pr: Dictionary = ZipXmlUtils.find_first(node, "p:spPr")
	var xfrm: Dictionary = ZipXmlUtils.find_first(sp_pr, "a:xfrm")

	var rect := PresentationModel.ShapeRect.new()
	rect.id = _get_shape_id(node)
	rect.type = PresentationModel.ShapeRect.Type.IMAGE
	rect.z_order = ctx.z_counter
	ctx.z_counter += 1

	var blip: Dictionary = ZipXmlUtils.find_first(node, "a:blip")
	if not blip.is_empty():
		var embed_id: String = (blip.get("attrs", {}) as Dictionary).get("r:embed", "")
		if rels.has(embed_id):
			rect.image_ref = rels[embed_id]

	_apply_position(rect, xfrm, transform, manifest, ctx)
	if rect.w > 0.0 and rect.h > 0.0:
		manifest.shapes.append(rect)

static func _process_graphic_frame(node: Dictionary, transform: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	# graphicFrame's transform element is namespaced "p:xfrm", unlike the
	# "a:xfrm" used inside sp/pic's spPr — a real OOXML inconsistency.
	var xfrm: Dictionary = ZipXmlUtils.find_first(node, "p:xfrm")

	var rect := PresentationModel.ShapeRect.new()
	rect.id = _get_shape_id(node)
	rect.type = PresentationModel.ShapeRect.Type.TABLE
	rect.z_order = ctx.z_counter
	ctx.z_counter += 1

	_apply_position(rect, xfrm, transform, manifest, ctx)
	if rect.w > 0.0 and rect.h > 0.0:
		manifest.shapes.append(rect)

static func _apply_position(rect: PresentationModel.ShapeRect, xfrm: Dictionary, transform: Dictionary, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	if xfrm.is_empty():
		_apply_fallback_position(rect, manifest, ctx)
		return
	var off: Vector2 = _read_point(xfrm, "a:off")
	var ext: Vector2 = _read_point(xfrm, "a:ext", "cx", "cy")
	var pos: Vector2 = (transform["scale"] as Vector2) * off + (transform["trans"] as Vector2)
	var size: Vector2 = (transform["scale"] as Vector2) * ext
	rect.x = pos.x
	rect.y = pos.y
	rect.w = size.x
	rect.h = size.y
	rect.position_is_explicit = true

static func _apply_fallback_position(rect: PresentationModel.ShapeRect, manifest: PresentationModel.SlideManifest, ctx: ParseContext) -> void:
	var default_w: float = manifest.canvas_w * 0.6
	var default_h: float = manifest.canvas_h * 0.15
	rect.x = manifest.canvas_w * 0.05
	rect.y = ctx.fallback_cursor_y
	rect.w = default_w
	rect.h = default_h
	rect.position_is_explicit = false
	ctx.fallback_cursor_y += default_h + manifest.canvas_h * 0.05

static func _read_point(xfrm: Dictionary, tag: String, x_attr: String = "x", y_attr: String = "y") -> Vector2:
	var node: Dictionary = ZipXmlUtils.find_first(xfrm, tag)
	if node.is_empty():
		return Vector2.ZERO
	var attrs: Dictionary = node.get("attrs", {})
	var vx: float = float(attrs.get(x_attr, "0"))
	var vy: float = float(attrs.get(y_attr, "0"))
	return Vector2(vx / EMU_PER_CM, vy / EMU_PER_CM)

static func _get_shape_id(node: Dictionary) -> String:
	var c_nv_pr: Dictionary = ZipXmlUtils.find_first(node, "p:cNvPr")
	if c_nv_pr.is_empty():
		return ""
	var attrs: Dictionary = c_nv_pr.get("attrs", {})
	return "%s:%s" % [attrs.get("id", ""), attrs.get("name", "")]

static func _extract_text(node: Dictionary) -> String:
	var tx_body: Dictionary = ZipXmlUtils.find_first(node, "p:txBody")
	if tx_body.is_empty():
		return ""
	var parts: Array[String] = []
	for run in ZipXmlUtils.find_all(tx_body, "a:t"):
		var t: String = String(run.get("text", "")).strip_edges()
		if t != "":
			parts.append(t)
	return " ".join(parts)
