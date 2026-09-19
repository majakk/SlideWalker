extends RefCounted
## Parses a .pptx (OOXML) file into a fully resolved PresentationModel.SlideDeck
## using only Godot's built-in ZIPReader/XMLParser.
##
## Fidelity to the original slides is the goal, so each slide follows its own
## slide -> layout -> master -> theme chain for: placeholder positions, text
## styles (size/color/bold/bullets/alignment), body properties, backgrounds,
## and the decorative non-placeholder shapes on the layout/master.
##
## Remaining scope cuts: tables/charts/SmartArt render as opaque boxes;
## custom geometry renders as its bounding rectangle.

const ZipXmlUtils = preload("res://presentation_import/zip_xml_utils.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const PptxTheme = preload("res://presentation_import/pptx_theme.gd")

const EMU_PER_CM: float = 360000.0
const DEFAULT_FONT_SIZE_PT: float = 18.0
const TITLE_TYPES := ["title", "ctrTitle"]
const BODY_TYPES := ["body", "subTitle", "obj"]

## One XML part (slide, layout or master) with its relationships.
class Part:
	extends RefCounted
	var path: String = ""
	var tree: Dictionary = {}
	## id -> {"target": String, "type": String, "external": bool}
	var rels: Dictionary = {}

	func target_of_type(type_name: String) -> String:
		for id in rels:
			if rels[id]["type"] == type_name:
				return rels[id]["target"]
		return ""

	func internal_target(id: String) -> String:
		if rels.has(id) and not rels[id]["external"]:
			return rels[id]["target"]
		return ""

## Shared across all slides of one file: the open zip plus parse caches.
class Doc:
	extends RefCounted
	var zip: ZIPReader
	var parts: Dictionary = {}
	var themes: Dictionary = {}
	var default_text_style: Dictionary = {}
	var canvas: Vector2 = Vector2(25.4, 19.05)

## Per-slide parse state.
class SlideContext:
	extends RefCounted
	var slide: Part
	var layout: Part
	var master: Part
	var theme: PptxTheme
	var doc: Doc
	var z_counter: int = 0
	var fallback_cursor_y: float = 0.0

static func parse(path: String) -> PresentationModel.SlideDeck:
	var deck := PresentationModel.SlideDeck.new()
	deck.source_path = path

	var doc := Doc.new()
	doc.zip = ZIPReader.new()
	if doc.zip.open(path) != OK:
		push_warning("PptxParser: failed to open %s" % path)
		return deck

	var pres: Part = _part(doc, "ppt/presentation.xml")
	doc.canvas = _get_slide_size(pres.tree)
	doc.default_text_style = ZipXmlUtils.find_first(pres.tree, "p:defaultTextStyle")

	var idx: int = 0
	for target in _get_ordered_slide_targets(pres):
		idx += 1
		var ctx := SlideContext.new()
		ctx.doc = doc
		ctx.slide = _part(doc, target)
		if ctx.slide.tree.is_empty():
			continue
		ctx.layout = _part(doc, ctx.slide.target_of_type("slideLayout"))
		ctx.master = _part(doc, ctx.layout.target_of_type("slideMaster"))
		ctx.theme = _theme_for(doc, ctx.master)
		deck.slides.append(_parse_slide(ctx, idx))

	doc.zip.close()
	return deck

# --- parts, relationships, themes ---

static func _part(doc: Doc, path: String) -> Part:
	if doc.parts.has(path):
		return doc.parts[path]
	var part := Part.new()
	part.path = path
	if path != "":
		part.tree = ZipXmlUtils.open_zip_entry_tree(doc.zip, path)
		part.rels = _parse_rels(doc.zip, _rels_path_for(path), path.get_base_dir())
	doc.parts[path] = part
	return part

static func _theme_for(doc: Doc, master: Part) -> PptxTheme:
	if doc.themes.has(master.path):
		return doc.themes[master.path]
	var theme := PptxTheme.new()
	var theme_part: Part = _part(doc, master.target_of_type("theme"))
	theme.load_from(theme_part.tree, master.tree)
	doc.themes[master.path] = theme
	return theme

static func _rels_path_for(target: String) -> String:
	return target.get_base_dir().path_join("_rels").path_join(target.get_file() + ".rels")

static func _parse_rels(zip: ZIPReader, rels_path: String, base_dir: String) -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ZipXmlUtils.open_zip_entry_tree(zip, rels_path)
	for rel in ZipXmlUtils.find_all(tree, "Relationship"):
		var attrs: Dictionary = rel.get("attrs", {})
		var id: String = attrs.get("Id", "")
		var target: String = attrs.get("Target", "")
		if id == "" or target == "":
			continue
		var external: bool = attrs.get("TargetMode", "") == "External"
		out[id] = {
			"target": target if external else _normalize_path(base_dir, target),
			"type": String(attrs.get("Type", "")).get_file(),
			"external": external,
		}
	return out

static func _normalize_path(base_dir: String, target: String) -> String:
	if target.begins_with("/"):
		return target.substr(1)
	var result: Array[String] = []
	for part in base_dir.path_join(target).split("/"):
		if part == "..":
			if not result.is_empty():
				result.remove_at(result.size() - 1)
		elif part != "." and part != "":
			result.append(part)
	return "/".join(result)

# --- presentation.xml ---

static func _get_slide_size(pres_tree: Dictionary) -> Vector2:
	var sld_sz: Dictionary = ZipXmlUtils.find_first(pres_tree, "p:sldSz")
	if sld_sz.is_empty():
		return Vector2(25.4, 19.05)
	var attrs: Dictionary = sld_sz.get("attrs", {})
	return Vector2(float(attrs.get("cx", "9144000")), float(attrs.get("cy", "6858000"))) / EMU_PER_CM

static func _get_ordered_slide_targets(pres: Part) -> Array[String]:
	var out: Array[String] = []
	var id_lst: Dictionary = ZipXmlUtils.find_first(pres.tree, "p:sldIdLst")
	for sld_id in ZipXmlUtils.direct_children(id_lst, "p:sldId"):
		var target: String = pres.internal_target(sld_id.get("attrs", {}).get("r:id", ""))
		if target != "":
			out.append(target)
	return out

# --- slide ---

static func _parse_slide(ctx: SlideContext, slide_index: int) -> PresentationModel.SlideManifest:
	var manifest := PresentationModel.SlideManifest.new()
	manifest.slide_id = slide_index
	manifest.canvas_w = ctx.doc.canvas.x
	manifest.canvas_h = ctx.doc.canvas.y
	_resolve_background(ctx, manifest)

	var identity: Dictionary = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
	var slide_shows_master: bool = ctx.slide.tree.get("attrs", {}).get("showMasterSp", "1") != "0"
	var layout_shows_master: bool = ctx.layout.tree.get("attrs", {}).get("showMasterSp", "1") != "0"
	if slide_shows_master and layout_shows_master:
		_walk_shape_tree(ZipXmlUtils.find_first(ctx.master.tree, "p:spTree"), identity, ctx.master, ctx, manifest)
	if slide_shows_master:
		_walk_shape_tree(ZipXmlUtils.find_first(ctx.layout.tree, "p:spTree"), identity, ctx.layout, ctx, manifest)
	_walk_shape_tree(ZipXmlUtils.find_first(ctx.slide.tree, "p:spTree"), identity, ctx.slide, ctx, manifest)
	return manifest

static func _resolve_background(ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	for part in [ctx.slide, ctx.layout, ctx.master]:
		var bg: Dictionary = ZipXmlUtils.find_first(part.tree, "p:bg")
		if bg.is_empty():
			continue
		var bg_pr: Dictionary = ZipXmlUtils.find_first(bg, "p:bgPr")
		if not bg_pr.is_empty():
			var blip: Dictionary = ZipXmlUtils.find_first(bg_pr, "a:blip")
			if not blip.is_empty():
				manifest.bg_image_ref = part.internal_target(blip.get("attrs", {}).get("r:embed", ""))
			var fill = _fill_color(ctx, [bg_pr])
			if fill != null:
				manifest.bg_color = fill
			return
		var bg_ref: Dictionary = ZipXmlUtils.find_first(bg, "p:bgRef")
		var ref_color = ctx.theme.color_in(bg_ref)
		if ref_color != null:
			manifest.bg_color = ref_color
		return

# --- shape tree walk ---

static func _walk_shape_tree(container: Dictionary, transform: Dictionary, part: Part, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	for child in container.get("children", []):
		var tag: String = child.get("tag", "")
		if tag == "p:grpSp":
			_process_group(child, transform, part, ctx, manifest)
			continue
		if not tag in ["p:sp", "p:pic", "p:graphicFrame", "p:cxnSp"]:
			continue
		var c_nv_pr: Dictionary = ZipXmlUtils.find_first(child, "p:cNvPr")
		if c_nv_pr.get("attrs", {}).get("hidden", "0") in ["1", "true"]:
			continue
		var ph: Dictionary = _placeholder_of(child)
		# Layout/master placeholders are prompts for slide content, never drawn.
		if part != ctx.slide and not ph.is_empty():
			continue
		var shape: PresentationModel.ShapeRect = _process_shape(child, tag, ph, transform, part, ctx, manifest)
		if shape == null or not shape.is_visible():
			continue
		# Straight connectors are routinely zero-height or zero-width.
		var has_area: bool = shape.w > 0.0 and shape.h > 0.0
		var is_line: bool = shape.type == PresentationModel.ShapeRect.Type.LINE and (shape.w > 0.0 or shape.h > 0.0)
		if has_area or is_line:
			manifest.shapes.append(shape)

static func _process_group(node: Dictionary, transform: Dictionary, part: Part, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	var xfrm: Dictionary = ZipXmlUtils.find_first(ZipXmlUtils.find_first(node, "p:grpSpPr"), "a:xfrm")
	var off: Vector2 = _read_point(xfrm, "a:off")
	var ext: Vector2 = _read_point(xfrm, "a:ext", "cx", "cy")
	var ch_off: Vector2 = _read_point(xfrm, "a:chOff")
	var ch_ext: Vector2 = _read_point(xfrm, "a:chExt", "cx", "cy")
	if xfrm.is_empty() or ch_ext.x == 0.0 or ch_ext.y == 0.0:
		_walk_shape_tree(node, transform, part, ctx, manifest)
		return
	var g_scale := Vector2(ext.x / ch_ext.x, ext.y / ch_ext.y)
	var g_trans: Vector2 = off - ch_off * g_scale
	var cur_scale: Vector2 = transform["scale"]
	var cur_trans: Vector2 = transform["trans"]
	_walk_shape_tree(node, {
		"scale": cur_scale * g_scale,
		"trans": cur_scale * g_trans + cur_trans,
	}, part, ctx, manifest)

static func _process_shape(node: Dictionary, tag: String, ph: Dictionary, transform: Dictionary, part: Part, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> PresentationModel.ShapeRect:
	var shape := PresentationModel.ShapeRect.new()
	shape.id = _get_shape_id(node)
	shape.z_order = ctx.z_counter
	ctx.z_counter += 1
	shape.placeholder_type = ph.get("type", "")

	# Inherited placeholder definitions (only slide shapes inherit).
	var layout_ph: Dictionary = {}
	var master_ph: Dictionary = {}
	if not ph.is_empty():
		layout_ph = _find_placeholder(ctx.layout, ph, false)
		master_ph = _find_placeholder(ctx.master, ph, true)

	var sp_pr: Dictionary = ZipXmlUtils.find_first(node, "p:spPr")
	var sp_prs: Array = [sp_pr]
	for inherited in [layout_ph, master_ph]:
		if not inherited.is_empty():
			sp_prs.append(ZipXmlUtils.find_first(inherited, "p:spPr"))

	_apply_position(shape, node, tag, sp_prs, transform, ctx, manifest)
	var geom: Dictionary = ZipXmlUtils.find_first(sp_pr, "a:prstGeom")
	shape.geometry = geom.get("attrs", {}).get("prst", "rect")

	var style: Dictionary = ZipXmlUtils.find_first(node, "p:style")
	_apply_line(shape, sp_prs, style, ctx)

	match tag:
		"p:pic":
			shape.type = PresentationModel.ShapeRect.Type.IMAGE
			var blip_fill: Dictionary = ZipXmlUtils.find_first(node, "p:blipFill")
			var blip: Dictionary = ZipXmlUtils.find_first(blip_fill, "a:blip")
			shape.image_ref = part.internal_target(blip.get("attrs", {}).get("r:embed", ""))
			shape.image_crop = _read_crop(ZipXmlUtils.find_first(blip_fill, "a:srcRect"))
		"p:graphicFrame":
			shape.type = PresentationModel.ShapeRect.Type.TABLE
			shape.line_color = Color(0.6, 0.6, 0.6)
			shape.line_width_cm = 0.03
		"p:cxnSp":
			shape.type = PresentationModel.ShapeRect.Type.LINE
		_:
			var fill = _fill_color(ctx, sp_prs)
			if fill == null:
				fill = _style_ref_color(ctx, style, "a:fillRef")
			if fill != null:
				shape.fill_color = fill
			var font_ref: Dictionary = ZipXmlUtils.find_first(style, "a:fontRef")
			_apply_text(shape, node, ph, layout_ph, master_ph, ctx, ctx.theme.color_in(font_ref))
			shape.type = PresentationModel.ShapeRect.Type.TEXT if shape.has_visible_text() \
				else PresentationModel.ShapeRect.Type.SHAPE
	return shape

# --- geometry ---

static func _apply_position(shape: PresentationModel.ShapeRect, node: Dictionary, tag: String, sp_prs: Array, transform: Dictionary, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	# graphicFrame's transform is <p:xfrm> directly on the frame; everything
	# else uses <a:xfrm> inside spPr.
	var own_xfrm: Dictionary = ZipXmlUtils.find_first(node, "p:xfrm") if tag == "p:graphicFrame" \
		else ZipXmlUtils.find_first(sp_prs[0], "a:xfrm")
	var xfrm: Dictionary = own_xfrm
	var xfrm_transform: Dictionary = transform
	if xfrm.is_empty():
		# Inherited placeholder positions live in layout/master space, which
		# is never inside a group.
		xfrm_transform = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
		for i in range(1, sp_prs.size()):
			xfrm = ZipXmlUtils.find_first(sp_prs[i], "a:xfrm")
			if not xfrm.is_empty():
				break
	if xfrm.is_empty():
		_apply_fallback_position(shape, manifest, ctx)
		return

	var scale: Vector2 = xfrm_transform["scale"]
	var pos: Vector2 = scale * _read_point(xfrm, "a:off") + (xfrm_transform["trans"] as Vector2)
	var size: Vector2 = scale * _read_point(xfrm, "a:ext", "cx", "cy")
	shape.x = pos.x
	shape.y = pos.y
	shape.w = size.x
	shape.h = size.y
	var attrs: Dictionary = xfrm.get("attrs", {})
	shape.rotation_deg = float(attrs.get("rot", "0")) / 60000.0
	shape.flip_h = attrs.get("flipH", "0") in ["1", "true"]
	shape.flip_v = attrs.get("flipV", "0") in ["1", "true"]
	shape.position_is_explicit = true

static func _apply_fallback_position(shape: PresentationModel.ShapeRect, manifest: PresentationModel.SlideManifest, ctx: SlideContext) -> void:
	shape.x = manifest.canvas_w * 0.05
	shape.y = ctx.fallback_cursor_y
	shape.w = manifest.canvas_w * 0.6
	shape.h = manifest.canvas_h * 0.15
	shape.position_is_explicit = false
	ctx.fallback_cursor_y += shape.h + manifest.canvas_h * 0.05

static func _read_point(xfrm: Dictionary, tag: String, x_attr: String = "x", y_attr: String = "y") -> Vector2:
	var node: Dictionary = ZipXmlUtils.find_first(xfrm, tag)
	if node.is_empty():
		return Vector2.ZERO
	var attrs: Dictionary = node.get("attrs", {})
	return Vector2(float(attrs.get(x_attr, "0")), float(attrs.get(y_attr, "0"))) / EMU_PER_CM

static func _read_crop(src_rect: Dictionary) -> Rect2:
	var attrs: Dictionary = src_rect.get("attrs", {})
	var l: float = clamp(float(attrs.get("l", "0")) / 100000.0, 0.0, 1.0)
	var t: float = clamp(float(attrs.get("t", "0")) / 100000.0, 0.0, 1.0)
	var r: float = clamp(float(attrs.get("r", "0")) / 100000.0, 0.0, 1.0)
	var b: float = clamp(float(attrs.get("b", "0")) / 100000.0, 0.0, 1.0)
	return Rect2(l, t, max(0.01, 1.0 - l - r), max(0.01, 1.0 - t - b))

# --- fills and lines ---

## First explicit fill in the spPr inheritance chain. null = unspecified,
## transparent Color = explicitly no fill.
static func _fill_color(ctx: SlideContext, sp_prs: Array) -> Variant:
	for sp_pr in sp_prs:
		for child in (sp_pr as Dictionary).get("children", []):
			match String(child.get("tag", "")):
				"a:noFill":
					return Color(0, 0, 0, 0)
				"a:solidFill":
					return ctx.theme.color_in(child)
				"a:gradFill":
					return ctx.theme.color_in(ZipXmlUtils.find_first(child, "a:gs"))
	return null

static func _style_ref_color(ctx: SlideContext, style: Dictionary, ref_tag: String) -> Variant:
	var ref: Dictionary = ZipXmlUtils.find_first(style, ref_tag)
	if ref.is_empty() or ref.get("attrs", {}).get("idx", "0") == "0":
		return null
	return ctx.theme.color_in(ref)

static func _apply_line(shape: PresentationModel.ShapeRect, sp_prs: Array, style: Dictionary, ctx: SlideContext) -> void:
	for sp_pr in sp_prs:
		var ln: Dictionary = ZipXmlUtils.find_first(sp_pr, "a:ln")
		if ln.is_empty():
			continue
		if not ZipXmlUtils.find_first(ln, "a:noFill").is_empty():
			return
		var c = ctx.theme.color_in(ZipXmlUtils.find_first(ln, "a:solidFill"))
		if c == null:
			c = _style_ref_color(ctx, style, "a:lnRef")
		if c != null:
			shape.line_color = c
			shape.line_width_cm = float(ln.get("attrs", {}).get("w", "12700")) / EMU_PER_CM
		return
	var ref_color = _style_ref_color(ctx, style, "a:lnRef")
	if ref_color != null:
		shape.line_color = ref_color
		shape.line_width_cm = 12700.0 / EMU_PER_CM

# --- placeholders ---

static func _placeholder_of(node: Dictionary) -> Dictionary:
	for nv_tag in ["p:nvSpPr", "p:nvPicPr", "p:nvGraphicFramePr", "p:nvCxnSpPr"]:
		var nv: Dictionary = ZipXmlUtils.find_first(node, nv_tag)
		if nv.is_empty():
			continue
		var ph: Dictionary = ZipXmlUtils.find_first(nv, "p:ph")
		if ph.is_empty():
			return {}
		var attrs: Dictionary = ph.get("attrs", {})
		return {"type": attrs.get("type", "obj"), "idx": attrs.get("idx", "")}
	return {}

## Finds the layout/master placeholder a slide placeholder inherits from:
## by idx first (layouts), then by type. Masters only carry the generic
## types, so ctrTitle -> title and subTitle/obj -> body there.
static func _find_placeholder(part: Part, ph: Dictionary, is_master: bool) -> Dictionary:
	var candidates: Array = []
	for child in ZipXmlUtils.find_first(part.tree, "p:spTree").get("children", []):
		var cand_ph: Dictionary = _placeholder_of(child)
		if not cand_ph.is_empty():
			candidates.append([child, cand_ph])

	var want_type: String = ph.get("type", "obj")
	if is_master:
		want_type = _master_type(want_type)
	else:
		var want_idx: String = ph.get("idx", "")
		if want_idx != "":
			for c in candidates:
				if c[1]["idx"] == want_idx:
					return c[0]
	for c in candidates:
		var cand_type: String = c[1]["type"]
		if is_master:
			cand_type = _master_type(cand_type)
		if cand_type == want_type:
			return c[0]
	if not is_master and want_type in BODY_TYPES:
		for c in candidates:
			if c[1]["type"] in BODY_TYPES:
				return c[0]
	return {}

static func _master_type(ph_type: String) -> String:
	if ph_type == "ctrTitle":
		return "title"
	if ph_type in BODY_TYPES:
		return "body"
	return ph_type

# --- text ---

## style_font_color: the shape style's <a:fontRef> color, which outranks the
## master/presentation text styles but not the shape's own formatting.
static func _apply_text(shape: PresentationModel.ShapeRect, node: Dictionary, ph: Dictionary, layout_ph: Dictionary, master_ph: Dictionary, ctx: SlideContext, style_font_color: Variant = null) -> void:
	var tx_body: Dictionary = ZipXmlUtils.find_first(node, "p:txBody")
	if tx_body.is_empty():
		return

	var tx_bodies: Array = [tx_body]
	for inherited in [layout_ph, master_ph]:
		if not inherited.is_empty():
			tx_bodies.append(ZipXmlUtils.find_first(inherited, "p:txBody"))

	# Body properties: anchor, insets, wrap, autofit.
	var body_prs: Array = []
	for tb in tx_bodies:
		body_prs.append(ZipXmlUtils.find_first(tb, "a:bodyPr"))
	shape.text_anchor = _first_attr(body_prs, "anchor", "t")
	shape.text_wrap = _first_attr(body_prs, "wrap", "square") != "none"
	shape.text_insets = Vector4(
		float(_first_attr(body_prs, "lIns", "91440")) / EMU_PER_CM,
		float(_first_attr(body_prs, "tIns", "45720")) / EMU_PER_CM,
		float(_first_attr(body_prs, "rIns", "91440")) / EMU_PER_CM,
		float(_first_attr(body_prs, "bIns", "45720")) / EMU_PER_CM)
	var autofit: Dictionary = ZipXmlUtils.find_first(body_prs[0], "a:normAutofit")
	var font_scale: float = float(autofit.get("attrs", {}).get("fontScale", "100000")) / 100000.0
	var spacing_reduction: float = float(autofit.get("attrs", {}).get("lnSpcReduction", "0")) / 100000.0

	# List-style containers, most specific first.
	var containers: Array = []
	for tb in tx_bodies:
		containers.append(ZipXmlUtils.find_first(tb, "a:lstStyle"))
	var tx_styles: Dictionary = ZipXmlUtils.find_first(ctx.master.tree, "p:txStyles")
	var ph_type: String = ph.get("type", "")
	var is_title: bool = ph_type in TITLE_TYPES
	if ph.is_empty():
		containers.append(ZipXmlUtils.find_first(tx_styles, "p:otherStyle"))
	elif is_title:
		containers.append(ZipXmlUtils.find_first(tx_styles, "p:titleStyle"))
	elif ph_type in BODY_TYPES:
		containers.append(ZipXmlUtils.find_first(tx_styles, "p:bodyStyle"))
	else:
		containers.append(ZipXmlUtils.find_first(tx_styles, "p:otherStyle"))
	containers.append(ctx.doc.default_text_style)

	var default_font: String = ctx.theme.major_font if is_title else ctx.theme.minor_font
	var style_split: int = 2 + tx_bodies.size()
	var autonum_counters: Dictionary = {}
	var summary: Array[String] = []

	for p in ZipXmlUtils.direct_children(tx_body, "a:p"):
		var para := PresentationModel.Paragraph.new()
		var p_pr: Dictionary = ZipXmlUtils.find_first(p, "a:pPr")
		para.level = int(p_pr.get("attrs", {}).get("lvl", "0"))

		var level_nodes: Array = [p_pr]
		for container in containers:
			var lvl: Dictionary = ZipXmlUtils.find_first(container, "a:lvl%dpPr" % (para.level + 1))
			if lvl.is_empty():
				lvl = ZipXmlUtils.find_first(container, "a:defPPr")
			level_nodes.append(lvl)

		para.align = _first_attr(level_nodes, "algn", "l")
		para.indent_cm = float(_first_attr(level_nodes, "marL", "0")) / EMU_PER_CM
		para.first_line_indent_cm = float(_first_attr(level_nodes, "indent", "0")) / EMU_PER_CM
		var def_rprs: Array = []
		for lvl_node in level_nodes:
			def_rprs.append(ZipXmlUtils.find_first(lvl_node, "a:defRPr"))

		var runs_out: Array[PresentationModel.TextRun] = []
		for child in p.get("children", []):
			match String(child.get("tag", "")):
				"a:r", "a:fld":
					var r_pr: Dictionary = ZipXmlUtils.find_first(child, "a:rPr")
					var run := _make_run(ctx, [r_pr] + def_rprs, font_scale, default_font, style_font_color, style_split)
					run.text = String(ZipXmlUtils.find_first(child, "a:t").get("text", ""))
					runs_out.append(run)
				"a:br":
					var br_run := _make_run(ctx, [ZipXmlUtils.find_first(child, "a:rPr")] + def_rprs, font_scale, default_font, style_font_color, style_split)
					br_run.text = "\n"
					runs_out.append(br_run)
		if runs_out.is_empty():
			# Empty paragraphs still take a line of vertical space.
			var end_run := _make_run(ctx, [ZipXmlUtils.find_first(p, "a:endParaRPr")] + def_rprs, font_scale, default_font, style_font_color, style_split)
			runs_out.append(end_run)
		para.runs = runs_out

		var para_text: String = ""
		for run in runs_out:
			para_text += run.text
		var size_pt: float = runs_out[0].size_pt
		para.bullet = _bullet_for(level_nodes, para.level, autonum_counters) if para_text.strip_edges() != "" else ""
		para.line_spacing = _line_spacing(level_nodes, size_pt) * (1.0 - spacing_reduction)
		para.space_before_pt = _space_before(level_nodes, size_pt) * (1.0 - spacing_reduction)
		shape.paragraphs.append(para)
		if para_text.strip_edges() != "":
			summary.append(para_text.strip_edges())

	shape.text_summary = " ".join(summary)

static func _make_run(ctx: SlideContext, rprs: Array, font_scale: float, default_font: String, style_font_color: Variant = null, style_split: int = -1) -> PresentationModel.TextRun:
	var run := PresentationModel.TextRun.new()
	run.size_pt = float(_first_attr(rprs, "sz", str(DEFAULT_FONT_SIZE_PT * 100.0))) / 100.0 * font_scale
	run.bold = _first_attr(rprs, "b", "0") in ["1", "true"]
	run.italic = _first_attr(rprs, "i", "0") in ["1", "true"]
	run.underline = _first_attr(rprs, "u", "none") != "none"

	# Direct children only: a nested <a:ln> (text outline) also has a solidFill.
	var is_link: bool = not ZipXmlUtils.direct_children(rprs[0], "a:hlinkClick").is_empty()
	var color = null
	for i in range(rprs.size()):
		if i == style_split and style_font_color != null:
			color = style_font_color
			break
		var fills: Array = ZipXmlUtils.direct_children(rprs[i], "a:solidFill")
		if not fills.is_empty():
			color = ctx.theme.color_in(fills[0])
			break
		# Hyperlinks use the theme link color unless the run sets its own.
		if i == 0 and is_link and ctx.theme.colors.has("hlink"):
			color = ctx.theme.colors["hlink"]
			run.underline = true
			break
	if color == null:
		color = ctx.theme.colors.get(ctx.theme.clr_map.get("tx1", "dk1"), Color.BLACK)
	run.color = color

	run.font_family = default_font
	for rpr in rprs:
		var latins: Array = ZipXmlUtils.direct_children(rpr, "a:latin")
		var face: String = latins[0].get("attrs", {}).get("typeface", "") if not latins.is_empty() else ""
		if face != "":
			run.font_family = ctx.theme.resolve_font(face)
			break
	return run

static func _bullet_for(level_nodes: Array, level: int, counters: Dictionary) -> String:
	for node in level_nodes:
		for child in (node as Dictionary).get("children", []):
			match String(child.get("tag", "")):
				"a:buNone":
					return ""
				"a:buChar":
					return String(child.get("attrs", {}).get("char", "•"))
				"a:buAutoNum":
					counters[level] = int(counters.get(level, int(child.get("attrs", {}).get("startAt", "1")) - 1)) + 1
					return "%d." % counters[level]
	return ""

static func _line_spacing(level_nodes: Array, size_pt: float) -> float:
	for node in level_nodes:
		var ln: Dictionary = ZipXmlUtils.find_first(node, "a:lnSpc")
		if ln.is_empty():
			continue
		var pct: Dictionary = ZipXmlUtils.find_first(ln, "a:spcPct")
		if not pct.is_empty():
			return float(pct.get("attrs", {}).get("val", "100000")) / 100000.0
		var pts: Dictionary = ZipXmlUtils.find_first(ln, "a:spcPts")
		if not pts.is_empty() and size_pt > 0.0:
			return float(pts.get("attrs", {}).get("val", "0")) / 100.0 / (size_pt * 1.2)
	return 1.0

static func _space_before(level_nodes: Array, size_pt: float) -> float:
	for node in level_nodes:
		var sb: Dictionary = ZipXmlUtils.find_first(node, "a:spcBef")
		if sb.is_empty():
			continue
		var pts: Dictionary = ZipXmlUtils.find_first(sb, "a:spcPts")
		if not pts.is_empty():
			return float(pts.get("attrs", {}).get("val", "0")) / 100.0
		var pct: Dictionary = ZipXmlUtils.find_first(sb, "a:spcPct")
		if not pct.is_empty():
			return float(pct.get("attrs", {}).get("val", "0")) / 100000.0 * size_pt
	return 0.0

## First value of attr across a chain of nodes (most specific first).
static func _first_attr(nodes: Array, attr: String, fallback: String) -> String:
	for node in nodes:
		var attrs: Dictionary = (node as Dictionary).get("attrs", {})
		if attrs.has(attr):
			return attrs[attr]
	return fallback

static func _get_shape_id(node: Dictionary) -> String:
	var attrs: Dictionary = ZipXmlUtils.find_first(node, "p:cNvPr").get("attrs", {})
	return "%s:%s" % [attrs.get("id", ""), attrs.get("name", "")]
