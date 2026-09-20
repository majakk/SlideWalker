extends RefCounted
## Parses a .odp (ODF) file into a fully resolved PresentationModel.SlideDeck,
## using only Godot's built-in ZIPReader/XMLParser - mirrors pptx_parser.gd's
## fidelity goal, adapted to ODF's own model:
##   - draw:page per slide; shapes are usually exported with explicit,
##     already-resolved svg:x/y/width/height (LibreOffice/Google Slides both
##     bake placeholder positions onto the frame), so the placeholder-
##     inheritance-without-position case pptx needs a fallback for is rare
##     here - the same fallback exists for when it happens anyway.
##   - Styles (text/paragraph/graphic/presentation/drawing-page families) are
##     resolved by name through style:parent-style-name chains, searched
##     across both content.xml's automatic-styles and styles.xml's
##     automatic-styles/office:styles/default-style, since a chain can cross
##     either file.
##   - No theme/lumMod color system: colors are direct fo:color/draw:fill-color.
##   - Images are referenced directly by zip path (xlink:href), no relationship
##     IDs to resolve.
##
## Scope cuts, consistent with pptx_parser.gd: tables/charts/OLE render as
## opaque boxes; draw:custom-shape geometry renders as its bounding rectangle
## (best-effort ellipse/roundRect sniffing from the enhanced-geometry type);
## draw:g group transforms only handle a translate() component (no real deck
## in the sample corpus uses draw:transform at all, let alone rotate/skew).

const ZipXmlUtils = preload("res://presentation_import/zip_xml_utils.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

const CM_PER_PT: float = 2.54 / 72.0
const DEFAULT_FONT_SIZE_PT: float = 18.0
const DEFAULT_CANVAS := Vector2(25.4, 14.29)
const TEXT_TAGS := ["draw:frame", "draw:custom-shape", "draw:rect", "draw:ellipse"]

## Shared across the whole document: the open zip plus parse caches.
class Doc:
	extends RefCounted
	var zip: ZIPReader
	## "family|name" -> style node, merged across content.xml + styles.xml.
	var styles: Dictionary = {}
	## family -> <style:default-style> node.
	var default_styles: Dictionary = {}
	## style:name -> <text:list-style> node.
	var list_styles: Dictionary = {}
	## style:name -> <style:page-layout> node.
	var page_layouts: Dictionary = {}
	## style:name -> <style:master-page> node.
	var master_pages: Dictionary = {}
	## style:name (font-face) -> real family name.
	var font_faces: Dictionary = {}
	## fill-image style:name -> zip path.
	var fill_images: Dictionary = {}
	## image zip path -> natural size in cm.
	var image_sizes: Dictionary = {}
	var canvas: Vector2 = DEFAULT_CANVAS

## Per-slide parse state.
class SlideContext:
	extends RefCounted
	var doc: Doc
	var z_counter: int = 0
	var fallback_cursor_y: float = 0.0

static func parse(path: String) -> PresentationModel.SlideDeck:
	var deck := PresentationModel.SlideDeck.new()
	deck.source_path = path

	var doc := Doc.new()
	doc.zip = ZIPReader.new()
	if doc.zip.open(path) != OK:
		push_warning("OdpParser: failed to open %s" % path)
		return deck

	var content: Dictionary = ZipXmlUtils.open_zip_entry_tree(doc.zip, "content.xml")
	var styles_doc: Dictionary = ZipXmlUtils.open_zip_entry_tree(doc.zip, "styles.xml")
	if content.is_empty():
		doc.zip.close()
		push_warning("OdpParser: no content.xml in %s" % path)
		return deck

	_index_styles(content, doc)
	_index_styles(styles_doc, doc)
	_index_master_pages(styles_doc, doc)
	doc.canvas = _resolve_canvas(doc)

	var presentation: Dictionary = ZipXmlUtils.find_first(ZipXmlUtils.find_first(content, "office:body"), "office:presentation")
	for page in ZipXmlUtils.direct_children(presentation, "draw:page"):
		if _page_is_hidden(page, doc):
			continue
		var ctx := SlideContext.new()
		ctx.doc = doc
		deck.slides.append(_parse_slide(page, ctx, deck.slides.size() + 1))

	doc.zip.close()
	return deck

## A slide the author marked "Hide Slide" is skipped by an actual slideshow
## or PDF export, so it's skipped here too - the deck's slide numbers should
## match what a viewer would reach. ODF carries this on the page's
## drawing-page style rather than on the page element itself.
static func _page_is_hidden(page: Dictionary, doc: Doc) -> bool:
	var attrs: Dictionary = page.get("attrs", {})
	if attrs.get("presentation:visibility", "visible") == "hidden":
		return true
	var chain: Array = _style_chain(doc, "drawing-page", attrs.get("draw:style-name", ""))
	return _chain_attr(chain, "style:drawing-page-properties", "presentation:visibility", "visible") == "hidden"

# --- style indexing ---

static func _index_styles(root: Dictionary, doc: Doc) -> void:
	if root.is_empty():
		return
	for scope_tag in ["office:automatic-styles", "office:styles"]:
		var scope: Dictionary = ZipXmlUtils.find_first(root, scope_tag)
		for node in ZipXmlUtils.direct_children(scope, "style:style"):
			var attrs: Dictionary = node.get("attrs", {})
			var name: String = attrs.get("style:name", "")
			var family: String = attrs.get("style:family", "")
			if name != "":
				doc.styles["%s|%s" % [family, name]] = node
		for node in ZipXmlUtils.direct_children(scope, "style:default-style"):
			var family: String = node.get("attrs", {}).get("style:family", "")
			if family != "":
				doc.default_styles[family] = node
		for node in ZipXmlUtils.direct_children(scope, "text:list-style"):
			var name: String = node.get("attrs", {}).get("style:name", "")
			if name != "":
				doc.list_styles[name] = node
		for node in ZipXmlUtils.direct_children(scope, "style:page-layout"):
			var name: String = node.get("attrs", {}).get("style:name", "")
			if name != "":
				doc.page_layouts[name] = node
		for node in ZipXmlUtils.direct_children(scope, "draw:fill-image"):
			var attrs: Dictionary = node.get("attrs", {})
			var name: String = attrs.get("draw:name", "")
			if name != "":
				doc.fill_images[name] = attrs.get("xlink:href", "")
	var face_decls: Dictionary = ZipXmlUtils.find_first(root, "office:font-face-decls")
	for node in ZipXmlUtils.direct_children(face_decls, "style:font-face"):
		var attrs: Dictionary = node.get("attrs", {})
		var name: String = attrs.get("style:name", "")
		if name != "":
			doc.font_faces[name] = attrs.get("svg:font-family", name).strip_edges().trim_prefix("'").trim_suffix("'")

static func _index_master_pages(styles_doc: Dictionary, doc: Doc) -> void:
	var master_styles: Dictionary = ZipXmlUtils.find_first(styles_doc, "office:master-styles")
	for node in ZipXmlUtils.direct_children(master_styles, "style:master-page"):
		var name: String = node.get("attrs", {}).get("style:name", "")
		if name != "":
			doc.master_pages[name] = node

static func _resolve_canvas(doc: Doc) -> Vector2:
	for master in doc.master_pages.values():
		var layout_name: String = master.get("attrs", {}).get("style:page-layout-name", "")
		var layout: Dictionary = doc.page_layouts.get(layout_name, {})
		var props: Dictionary = ZipXmlUtils.find_first(layout, "style:page-layout-properties")
		if not props.is_empty():
			var attrs: Dictionary = props.get("attrs", {})
			var w: float = _len_cm(attrs.get("fo:page-width", ""))
			var h: float = _len_cm(attrs.get("fo:page-height", ""))
			if w > 0.0 and h > 0.0:
				return Vector2(w, h)
	return DEFAULT_CANVAS

## Resolves a style chain (most specific first) by name+family, following
## style:parent-style-name across both files, ending in the family's
## default-style if one exists. Capped against malformed cyclic chains.
static func _style_chain(doc: Doc, family: String, name: String) -> Array:
	var chain: Array = []
	var seen: Dictionary = {}
	var cur: String = name
	for _i in range(8):
		if cur == "" or seen.has(cur):
			break
		seen[cur] = true
		var node: Dictionary = doc.styles.get("%s|%s" % [family, cur], {})
		if node.is_empty():
			break
		chain.append(node)
		cur = node.get("attrs", {}).get("style:parent-style-name", "")
	if doc.default_styles.has(family):
		chain.append(doc.default_styles[family])
	return chain

## A shape's own style chain. Ordinary shapes name it with draw:style-name,
## placeholders with presentation:style-name, and the name belongs to either
## the graphic or the presentation family.
static func _shape_style_chain(doc: Doc, attrs: Dictionary) -> Array:
	for key in ["draw:style-name", "presentation:style-name"]:
		var name: String = attrs.get(key, "")
		if name == "":
			continue
		for family in ["graphic", "presentation"]:
			if doc.styles.has("%s|%s" % [family, name]):
				return _style_chain(doc, family, name)
	return []

static func _chain_attr(chain: Array, prop_tag: String, attr: String, fallback: String) -> String:
	for node in chain:
		var props: Dictionary = ZipXmlUtils.find_first(node, prop_tag)
		var attrs: Dictionary = props.get("attrs", {})
		if attrs.has(attr):
			return attrs[attr]
	return fallback

static func _len_cm(value: String) -> float:
	if value == "":
		return 0.0
	if value.ends_with("cm"):
		return value.trim_suffix("cm").to_float()
	if value.ends_with("mm"):
		return value.trim_suffix("mm").to_float() / 10.0
	if value.ends_with("in"):
		return value.trim_suffix("in").to_float() * 2.54
	if value.ends_with("pt"):
		return value.trim_suffix("pt").to_float() * CM_PER_PT
	if value.ends_with("px"):
		return value.trim_suffix("px").to_float() * CM_PER_PT * 0.75
	return value.to_float()

static func _len_pt(value: String) -> float:
	return _len_cm(value) / CM_PER_PT

# --- slide ---

static func _parse_slide(page: Dictionary, ctx: SlideContext, slide_index: int) -> PresentationModel.SlideManifest:
	var manifest := PresentationModel.SlideManifest.new()
	manifest.slide_id = slide_index
	manifest.canvas_w = ctx.doc.canvas.x
	manifest.canvas_h = ctx.doc.canvas.y
	_resolve_background(page, ctx, manifest)

	var identity: Dictionary = {"scale": Vector2.ONE, "trans": Vector2.ZERO}
	_walk_shapes(page, identity, ctx, manifest)
	return manifest

static func _resolve_background(page: Dictionary, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	var page_style: String = page.get("attrs", {}).get("draw:style-name", "")
	if _apply_drawing_page_bg(ctx, page_style, manifest):
		return
	var master_name: String = page.get("attrs", {}).get("draw:master-page-name", "")
	var master: Dictionary = ctx.doc.master_pages.get(master_name, {})
	_apply_drawing_page_bg(ctx, master.get("attrs", {}).get("draw:style-name", ""), manifest)

static func _apply_drawing_page_bg(ctx: SlideContext, style_name: String, manifest: PresentationModel.SlideManifest) -> bool:
	if style_name == "":
		return false
	var chain: Array = _style_chain(ctx.doc, "drawing-page", style_name)
	var fill: String = _chain_attr(chain, "style:drawing-page-properties", "draw:fill", "")
	if fill == "none":
		return true
	if fill == "solid":
		var hex: String = _chain_attr(chain, "style:drawing-page-properties", "draw:fill-color", "")
		if hex != "":
			manifest.bg_color = Color.html(hex)
			return true
	if fill == "bitmap":
		var img_name: String = _chain_attr(chain, "style:drawing-page-properties", "draw:fill-image-name", "")
		if ctx.doc.fill_images.has(img_name):
			manifest.bg_image_ref = ctx.doc.fill_images[img_name]
			return true
	return false

# --- shape tree walk ---

static func _walk_shapes(container: Dictionary, transform: Dictionary, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	for child in container.get("children", []):
		var tag: String = child.get("tag", "")
		if tag == "presentation:notes":
			continue
		if tag == "draw:g":
			_process_group(child, transform, ctx, manifest)
			continue
		if tag == "draw:a":
			# A hyperlink wrapping one or more shapes: parse them normally,
			# then hand the link down to whichever came out without one.
			var first: int = manifest.shapes.size()
			_walk_shapes(child, transform, ctx, manifest)
			var href: String = child.get("attrs", {}).get("xlink:href", "")
			for i in range(first, manifest.shapes.size()):
				if manifest.shapes[i].link_url == "":
					manifest.shapes[i].link_url = href
			continue
		if not tag in ["draw:frame", "draw:custom-shape", "draw:rect", "draw:ellipse", "draw:line", "draw:connector"]:
			continue
		var attrs: Dictionary = child.get("attrs", {})
		if attrs.get("presentation:class", "") == "notes":
			continue
		var shape: PresentationModel.ShapeRect = _process_shape(child, tag, transform, ctx, manifest)
		if shape == null or not shape.is_visible():
			continue
		var has_area: bool = shape.w > 0.0 and shape.h > 0.0
		var is_line: bool = shape.type == PresentationModel.ShapeRect.Type.LINE and (shape.w > 0.0 or shape.h > 0.0)
		if has_area or is_line:
			manifest.shapes.append(shape)

static func _process_group(node: Dictionary, transform: Dictionary, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> void:
	var offset := Vector2.ZERO
	var raw: String = node.get("attrs", {}).get("draw:transform", "")
	var m: RegEx = RegEx.new()
	m.compile("translate\\s*\\(\\s*([\\-0-9.]+)(cm|mm|in|pt)?[ ,]+([\\-0-9.]+)(cm|mm|in|pt)?\\s*\\)")
	var res: RegExMatch = m.search(raw)
	if res:
		var unit_x: String = res.get_string(2) if res.get_string(2) != "" else "cm"
		var unit_y: String = res.get_string(4) if res.get_string(4) != "" else "cm"
		offset = Vector2(_len_cm(res.get_string(1) + unit_x), _len_cm(res.get_string(3) + unit_y))
	var cur_scale: Vector2 = transform["scale"]
	var cur_trans: Vector2 = transform["trans"]
	_walk_shapes(node, {"scale": cur_scale, "trans": cur_trans + cur_scale * offset}, ctx, manifest)

static func _process_shape(node: Dictionary, tag: String, transform: Dictionary, ctx: SlideContext, manifest: PresentationModel.SlideManifest) -> PresentationModel.ShapeRect:
	var shape := PresentationModel.ShapeRect.new()
	var attrs: Dictionary = node.get("attrs", {})
	shape.id = attrs.get("draw:name", "")
	shape.z_order = ctx.z_counter
	ctx.z_counter += 1

	# Connectors between shapes carry endpoints rather than a frame, same as
	# a plain line; an elbow connector is approximated by its straight span.
	if tag == "draw:line" or tag == "draw:connector":
		_apply_line_endpoints(shape, attrs, transform)
	else:
		_apply_position(shape, attrs, transform, manifest, ctx)

	shape.link_url = _link_url(node)
	var chain: Array = _shape_style_chain(ctx.doc, attrs)
	_apply_fill_and_line(shape, chain)

	match tag:
		"draw:ellipse":
			shape.type = PresentationModel.ShapeRect.Type.SHAPE
			shape.geometry = "ellipse"
		"draw:line", "draw:connector":
			shape.type = PresentationModel.ShapeRect.Type.LINE
		"draw:custom-shape":
			shape.type = PresentationModel.ShapeRect.Type.SHAPE
			shape.geometry = _sniff_custom_geometry(node)
			_maybe_parse_text(shape, node, chain, ctx)
		"draw:rect":
			shape.type = PresentationModel.ShapeRect.Type.SHAPE
			shape.geometry = "rect"
			_maybe_parse_text(shape, node, chain, ctx)
		_:
			# draw:frame: image, text box, or an opaque embedded object.
			var image: Dictionary = ZipXmlUtils.find_first(node, "draw:image")
			if not image.is_empty():
				shape.type = PresentationModel.ShapeRect.Type.IMAGE
				shape.image_ref = image.get("attrs", {}).get("xlink:href", "")
				shape.image_crop = _read_clip(chain, _image_size_cm(ctx.doc, shape.image_ref))
			elif not ZipXmlUtils.find_first(node, "draw:object").is_empty():
				shape.type = PresentationModel.ShapeRect.Type.TABLE
				if shape.line_color.a == 0.0:
					shape.line_color = Color(0.6, 0.6, 0.6)
					shape.line_width_cm = 0.03
			else:
				_maybe_parse_text(shape, node, chain, ctx)
	return shape

static func _maybe_parse_text(shape: PresentationModel.ShapeRect, node: Dictionary, chain: Array, ctx: SlideContext) -> void:
	# draw:frame wraps its text in a draw:text-box; draw:custom-shape/rect/
	# ellipse carry text:p directly as their own children.
	var text_box: Dictionary = ZipXmlUtils.find_first(node, "draw:text-box")
	if text_box.is_empty():
		text_box = node
	if _text_container_is_empty(text_box):
		return
	shape.text_anchor = _anchor_from(chain)
	shape.text_autofit = _chain_attr(chain, "style:graphic-properties", "style:shrink-to-fit", "false") == "true" \
		or _chain_attr(chain, "style:graphic-properties", "draw:fit-to-size", "false") in ["true", "shrink-on-overflow"]
	var pad_l: float = _len_cm(_chain_attr(chain, "style:graphic-properties", "fo:padding-left", ""))
	var pad_t: float = _len_cm(_chain_attr(chain, "style:graphic-properties", "fo:padding-top", ""))
	var pad_r: float = _len_cm(_chain_attr(chain, "style:graphic-properties", "fo:padding-right", ""))
	var pad_b: float = _len_cm(_chain_attr(chain, "style:graphic-properties", "fo:padding-bottom", ""))
	if pad_l > 0.0 or pad_t > 0.0 or pad_r > 0.0 or pad_b > 0.0:
		shape.text_insets = Vector4(pad_l, pad_t, pad_r, pad_b)
	_parse_text_content(shape, text_box, ctx)
	shape.type = PresentationModel.ShapeRect.Type.TEXT if shape.has_visible_text() \
		else PresentationModel.ShapeRect.Type.SHAPE

## ODF writes a shape's hyperlink as a click event listener; text hyperlinks
## are text:a instead. Either means this shape leads somewhere.
static func _link_url(node: Dictionary) -> String:
	var candidates: Array = ZipXmlUtils.find_all(node, "presentation:event-listener")
	candidates.append_array(ZipXmlUtils.find_all(node, "text:a"))
	for candidate in candidates:
		var href: String = (candidate as Dictionary).get("attrs", {}).get("xlink:href", "")
		if href != "":
			return href
	return ""

static func _text_container_is_empty(container: Dictionary) -> bool:
	for child in container.get("children", []):
		if String(child.get("tag", "")) in ["text:p", "text:list"]:
			return false
	return true

static func _anchor_from(chain: Array) -> String:
	match _chain_attr(chain, "style:graphic-properties", "draw:textarea-vertical-align", "top"):
		"middle":
			return "ctr"
		"bottom":
			return "b"
	return "t"

# --- geometry ---

static func _apply_position(shape: PresentationModel.ShapeRect, attrs: Dictionary, transform: Dictionary, manifest: PresentationModel.SlideManifest, ctx: SlideContext) -> void:
	if not attrs.has("svg:x") or not attrs.has("svg:y"):
		_apply_fallback_position(shape, manifest, ctx)
		return
	var scale: Vector2 = transform["scale"]
	var pos: Vector2 = scale * Vector2(_len_cm(attrs.get("svg:x", "0cm")), _len_cm(attrs.get("svg:y", "0cm"))) + (transform["trans"] as Vector2)
	var size: Vector2 = scale * Vector2(_len_cm(attrs.get("svg:width", "0cm")), _len_cm(attrs.get("svg:height", "0cm")))
	shape.x = pos.x
	shape.y = pos.y
	shape.w = size.x
	shape.h = size.y
	shape.position_is_explicit = true

static func _apply_line_endpoints(shape: PresentationModel.ShapeRect, attrs: Dictionary, transform: Dictionary) -> void:
	var scale: Vector2 = transform["scale"]
	var trans: Vector2 = transform["trans"]
	var a: Vector2 = scale * Vector2(_len_cm(attrs.get("svg:x1", "0cm")), _len_cm(attrs.get("svg:y1", "0cm"))) + trans
	var b: Vector2 = scale * Vector2(_len_cm(attrs.get("svg:x2", "0cm")), _len_cm(attrs.get("svg:y2", "0cm"))) + trans
	shape.x = min(a.x, b.x)
	shape.y = min(a.y, b.y)
	shape.w = abs(b.x - a.x)
	shape.h = abs(b.y - a.y)
	shape.flip_h = b.x < a.x
	shape.flip_v = b.y < a.y
	shape.position_is_explicit = true

static func _apply_fallback_position(shape: PresentationModel.ShapeRect, manifest: PresentationModel.SlideManifest, ctx: SlideContext) -> void:
	shape.x = manifest.canvas_w * 0.05
	shape.y = ctx.fallback_cursor_y
	shape.w = manifest.canvas_w * 0.6
	shape.h = manifest.canvas_h * 0.15
	shape.position_is_explicit = false
	ctx.fallback_cursor_y += shape.h + manifest.canvas_h * 0.05

static func _sniff_custom_geometry(node: Dictionary) -> String:
	var geom: Dictionary = ZipXmlUtils.find_first(node, "draw:enhanced-geometry")
	var kind: String = String(geom.get("attrs", {}).get("draw:type", "")).to_lower()
	if kind.contains("ellipse") or kind.contains("circle"):
		return "ellipse"
	if kind.contains("round"):
		return "roundRect"
	return "rect"

## The image's natural size, which fo:clip is measured against. ODF stores no
## DPI for an image, and LibreOffice writes clip lengths against the 96-DPI
## reading of its pixel size, so that's what's assumed here.
static func _image_size_cm(doc: Doc, href: String) -> Vector2:
	if doc.image_sizes.has(href):
		return doc.image_sizes[href]
	var size := Vector2.ZERO
	if href != "" and doc.zip.file_exists(href):
		var img := Image.new()
		var bytes: PackedByteArray = doc.zip.read_file(href)
		var err: int = FAILED
		match href.get_extension().to_lower():
			"png":
				err = img.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				err = img.load_jpg_from_buffer(bytes)
			"webp":
				err = img.load_webp_from_buffer(bytes)
			"bmp":
				err = img.load_bmp_from_buffer(bytes)
			"tga":
				err = img.load_tga_from_buffer(bytes)
			"svg":
				err = img.load_svg_from_buffer(bytes)
		if err == OK:
			size = Vector2(img.get_size()) / 96.0 * 2.54
	doc.image_sizes[href] = size
	return size

## fo:clip="rect(top, right, bottom, left)" gives how much is cut from each
## edge of the image at its natural size (pptx's srcRect states the visible
## fraction directly instead). Negative insets are an outset rather than a
## crop, which the model can't express, so those are left uncropped - as is
## an image whose natural size couldn't be measured.
static func _read_clip(chain: Array, source_cm: Vector2) -> Rect2:
	var clip: String = _chain_attr(chain, "style:graphic-properties", "fo:clip", "")
	if clip == "" or source_cm.x <= 0.0 or source_cm.y <= 0.0:
		return Rect2(0, 0, 1, 1)
	var m := RegEx.new()
	m.compile("rect\\(([^,]+),([^,]+),([^,]+),([^,)]+)\\)")
	var res: RegExMatch = m.search(clip)
	if res == null:
		return Rect2(0, 0, 1, 1)
	var t: float = _len_cm(res.get_string(1).strip_edges())
	var r: float = _len_cm(res.get_string(2).strip_edges())
	var b: float = _len_cm(res.get_string(3).strip_edges())
	var l: float = _len_cm(res.get_string(4).strip_edges())
	if t < 0.0 or r < 0.0 or b < 0.0 or l < 0.0:
		return Rect2(0, 0, 1, 1)
	var left: float = clamp(l / source_cm.x, 0.0, 1.0)
	var top: float = clamp(t / source_cm.y, 0.0, 1.0)
	return Rect2(left, top,
		max(0.01, 1.0 - left - clamp(r / source_cm.x, 0.0, 1.0)),
		max(0.01, 1.0 - top - clamp(b / source_cm.y, 0.0, 1.0)))

# --- fills and lines ---

static func _apply_fill_and_line(shape: PresentationModel.ShapeRect, chain: Array) -> void:
	match _chain_attr(chain, "style:graphic-properties", "draw:fill", "none"):
		"solid":
			var hex: String = _chain_attr(chain, "style:graphic-properties", "draw:fill-color", "")
			if hex != "":
				shape.fill_color = Color.html(hex)
		"none":
			pass
		_:
			# gradient/bitmap/hatch: best-effort tint if a plain fill color is
			# still present, otherwise leave transparent (scope cut).
			var hex: String = _chain_attr(chain, "style:graphic-properties", "draw:fill-color", "")
			if hex != "":
				shape.fill_color = Color.html(hex)
	if _chain_attr(chain, "style:graphic-properties", "draw:stroke", "none") != "none":
		var hex: String = _chain_attr(chain, "style:graphic-properties", "svg:stroke-color", "")
		if hex != "":
			shape.line_color = Color.html(hex)
			shape.line_width_cm = _len_cm(_chain_attr(chain, "style:graphic-properties", "svg:stroke-width", "0.02cm"))

# --- text ---

static func _parse_text_content(shape: PresentationModel.ShapeRect, text_box: Dictionary, ctx: SlideContext) -> void:
	var counters: Dictionary = {}
	var summary: Array[String] = []
	for child in text_box.get("children", []):
		match String(child.get("tag", "")):
			"text:p":
				_append_paragraph(shape, child, 0, "", ctx, counters, summary)
			"text:list":
				_walk_text_list(child, 1, "", shape, ctx, counters, summary)
	shape.text_summary = " ".join(summary)

static func _walk_text_list(list_node: Dictionary, level: int, inherited_style: String, shape: PresentationModel.ShapeRect, ctx: SlideContext, counters: Dictionary, summary: Array[String]) -> void:
	var list_style: String = list_node.get("attrs", {}).get("text:style-name", inherited_style)
	for item in ZipXmlUtils.direct_children(list_node, "text:list-item"):
		for child in item.get("children", []):
			match String(child.get("tag", "")):
				"text:p":
					_append_paragraph(shape, child, level, list_style, ctx, counters, summary)
				"text:list":
					_walk_text_list(child, level + 1, list_style, shape, ctx, counters, summary)

static func _append_paragraph(shape: PresentationModel.ShapeRect, p_node: Dictionary, level: int, list_style_name: String, ctx: SlideContext, counters: Dictionary, summary: Array[String]) -> void:
	var para := PresentationModel.Paragraph.new()
	para.level = level
	var p_style: String = p_node.get("attrs", {}).get("text:style-name", "")
	var p_chain: Array = _style_chain(ctx.doc, "paragraph", p_style)

	match _chain_attr(p_chain, "style:paragraph-properties", "fo:text-align", "start"):
		"center":
			para.align = "ctr"
		"end", "right":
			para.align = "r"
		"justify":
			para.align = "just"
		_:
			para.align = "l"

	var list_level: Dictionary = _list_level_props(ctx.doc, list_style_name, level)
	if not list_level.is_empty():
		var space_before: float = _len_cm(list_level.get("text:space-before", "0cm"))
		var label_w: float = _len_cm(list_level.get("text:min-label-width", "0cm"))
		para.indent_cm = space_before + label_w
		para.first_line_indent_cm = -label_w
	else:
		para.indent_cm = _len_cm(_chain_attr(p_chain, "style:paragraph-properties", "fo:margin-left", "0cm"))
		para.first_line_indent_cm = _len_cm(_chain_attr(p_chain, "style:paragraph-properties", "fo:text-indent", "0cm"))

	var runs_out: Array[PresentationModel.TextRun] = []
	_collect_runs(p_node, p_style, p_chain, ctx, runs_out)
	if runs_out.is_empty():
		runs_out.append(_make_run(ctx, p_chain))
	para.runs = runs_out

	var para_text: String = ""
	for run in runs_out:
		para_text += run.text
	var size_pt: float = runs_out[0].size_pt
	para.bullet = _bullet_for(ctx.doc, list_style_name, level, counters, size_pt) if para_text.strip_edges() != "" else ""

	var line_height: String = _chain_attr(p_chain, "style:paragraph-properties", "fo:line-height", "100%")
	para.line_spacing = line_height.trim_suffix("%").to_float() / 100.0 if line_height.ends_with("%") else 1.0
	para.space_before_pt = _len_pt(_chain_attr(p_chain, "style:paragraph-properties", "fo:margin-top", "0cm"))

	shape.paragraphs.append(para)
	if para_text.strip_edges() != "":
		summary.append(para_text.strip_edges())

static func _collect_runs(p_node: Dictionary, p_style: String, p_chain: Array, ctx: SlideContext, out: Array[PresentationModel.TextRun]) -> void:
	for child in p_node.get("children", []):
		var tag: String = String(child.get("tag", ""))
		match tag:
			"text:span", "text:a":
				# text:a is a hyperlink, which can wrap runs directly or sit
				# inside a span; either way its text belongs to the paragraph.
				var span_style: String = child.get("attrs", {}).get("text:style-name", "")
				var span_chain: Array = _style_chain(ctx.doc, "text", span_style) + p_chain
				var run := _make_run(ctx, span_chain)
				run.text = _span_text(child)
				out.append(run)
			"text:line-break":
				var run := _make_run(ctx, p_chain)
				run.text = "\n"
				out.append(run)
			"text:s":
				var run := _make_run(ctx, p_chain)
				run.text = " ".repeat(max(1, int(child.get("attrs", {}).get("text:c", "1"))))
				out.append(run)
			"text:tab":
				var run := _make_run(ctx, p_chain)
				run.text = "\t"
				out.append(run)
			ZipXmlUtils.TEXT_TAG:
				# Text written straight into the paragraph, with no span of
				# its own, takes the paragraph's style.
				var run := _make_run(ctx, p_chain)
				run.text = String(child.get("text", ""))
				out.append(run)

## Text of a span, in document order: character data, runs of spaces, tabs
## and breaks are all separate nodes, and " <text:s c=4/>Design" means four
## spaces before the word, not after it.
static func _span_text(span_node: Dictionary) -> String:
	var out: String = ""
	for child in span_node.get("children", []):
		match String(child.get("tag", "")):
			ZipXmlUtils.TEXT_TAG:
				out += String(child.get("text", ""))
			"text:line-break":
				out += "\n"
			"text:s":
				out += " ".repeat(max(1, int(child.get("attrs", {}).get("text:c", "1"))))
			"text:tab":
				out += "\t"
			"text:span", "text:a":
				out += _span_text(child)
	return out

static func _make_run(ctx: SlideContext, chain: Array) -> PresentationModel.TextRun:
	var run := PresentationModel.TextRun.new()
	var size_str: String = _chain_attr(chain, "style:text-properties", "fo:font-size", "%.0fpt" % DEFAULT_FONT_SIZE_PT)
	run.size_pt = _len_pt(size_str)
	var weight: String = _chain_attr(chain, "style:text-properties", "fo:font-weight", "normal")
	run.bold = weight == "bold" or (weight.is_valid_float() and weight.to_float() >= 600.0)
	var style: String = _chain_attr(chain, "style:text-properties", "fo:font-style", "normal")
	run.italic = style == "italic" or style == "oblique"
	run.underline = _chain_attr(chain, "style:text-properties", "style:text-underline-style", "none") != "none"
	var color_hex: String = _chain_attr(chain, "style:text-properties", "fo:color", "")
	run.color = Color.html(color_hex) if color_hex != "" else Color.BLACK
	var font_name: String = _chain_attr(chain, "style:text-properties", "style:font-name", "")
	if font_name == "":
		font_name = _chain_attr(chain, "style:text-properties", "fo:font-family", "Arial")
	run.font_family = ctx.doc.font_faces.get(font_name, font_name)
	return run

static func _list_level_props(doc: Doc, list_style_name: String, level: int) -> Dictionary:
	if list_style_name == "" or not doc.list_styles.has(list_style_name):
		return {}
	var list_style: Dictionary = doc.list_styles[list_style_name]
	for tag in ["text:list-level-style-bullet", "text:list-level-style-number", "text:list-level-style-image"]:
		for entry in ZipXmlUtils.direct_children(list_style, tag):
			if int(entry.get("attrs", {}).get("text:level", "-1")) == level:
				var props: Dictionary = ZipXmlUtils.find_first(entry, "style:list-level-properties")
				return props.get("attrs", {})
	return {}

static func _bullet_for(doc: Doc, list_style_name: String, level: int, counters: Dictionary, size_pt: float) -> String:
	if list_style_name == "" or not doc.list_styles.has(list_style_name):
		return ""
	var list_style: Dictionary = doc.list_styles[list_style_name]
	for entry in ZipXmlUtils.direct_children(list_style, "text:list-level-style-bullet"):
		if int(entry.get("attrs", {}).get("text:level", "-1")) == level:
			return String(entry.get("attrs", {}).get("text:bullet-char", "•"))
	for entry in ZipXmlUtils.direct_children(list_style, "text:list-level-style-number"):
		if int(entry.get("attrs", {}).get("text:level", "-1")) == level:
			var key: String = "%s:%d" % [list_style_name, level]
			counters[key] = int(counters.get(key, 0)) + 1
			return "%d." % counters[key]
	return ""
