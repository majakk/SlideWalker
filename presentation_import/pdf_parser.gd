extends RefCounted
## Parses a .pdf file into a PresentationModel.SlideDeck, on the assumption
## that it's a presentation exported to PDF (Google Slides' "Download as
## PDF" is the common case) - one page per slide, at a consistent page size.
##
## PDF has no authored shapes to walk the way pptx/odp do - it's page content
## streams, not an editable document model - so unlike the other two parsers
## this one leans on poppler-utils (pdftoppm/pdftotext), a deliberate,
## user-approved exception to the "no sidecar" rule (same precedent as the
## FFmpeg video plugin in the plan): each page is rasterized at high DPI as
## the slide's true-fidelity background image, and `pdftotext -bbox-layout`
## (which already reports per-line bounding boxes) supplies real line-level
## ledges on top of it - visual fidelity from the raster, ledge granularity
## from the text layer, without writing a PDF content-stream parser.
##
## The line shapes carry no visible text of their own (text_summary stays
## empty) - the raster image already shows the real glyphs, so drawing our
## own font-substituted text on top would just double it up, usually
## mismatched. They're ledges only; SlideContentRenderer never draws them.
##
## Rasterized pages are cached in the user data dir, keyed by source path +
## mtime, so re-opening the same file (playtesting, course_gen_spike) doesn't
## re-run poppler every time.

const ZipXmlUtils = preload("res://presentation_import/zip_xml_utils.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

const CM_PER_PT: float = 2.54 / 72.0
const RASTER_DPI: int = 200
## poppler reports a line's box from the font's ascender, but a ledge belongs
## on the cap line so the player stands on the capitals rather than floating
## above them (text_box_view.gd does the same for pptx/odp text). For Arial-
## metric fonts, ascender-to-cap is ~0.19em of a ~1.12em line box.
const CAP_DROP_FRACTION: float = 0.17

const MISSING_POPPLER_MESSAGE := "PDF files need poppler-utils (pdftoppm and pdftotext) installed and on your PATH. " \
	+ "Most Linux distributions ship it; on macOS use \"brew install poppler\". .pptx and .odp files work without it."

## Checked before starting a course so the menu can explain the one external
## dependency SlideWalker has, instead of opening an empty presentation.
static func poppler_missing() -> bool:
	return not _tool_available("pdftoppm") or not _tool_available("pdftotext")

static func parse(path: String) -> PresentationModel.SlideDeck:
	var deck := PresentationModel.SlideDeck.new()
	deck.source_path = path

	if poppler_missing():
		push_warning("PdfParser: %s" % MISSING_POPPLER_MESSAGE)
		return deck

	var real_path: String = ProjectSettings.globalize_path(path)
	var page_images: Array[String] = _rasterize(real_path)
	if page_images.is_empty():
		push_warning("PdfParser: pdftoppm produced no pages for %s" % path)
		return deck

	var bbox_xml: String = _run_capture("pdftotext", ["-bbox-layout", real_path, "-"])
	var doc_tree: Dictionary = _extract_doc_tree(bbox_xml)
	var pages: Array = ZipXmlUtils.find_all(doc_tree, "page")

	for i in range(page_images.size()):
		var page_node: Dictionary = pages[i] if i < pages.size() else {}
		deck.slides.append(_build_slide(deck.slides.size() + 1, page_images[i], page_node))
	return deck

static func _tool_available(tool_name: String) -> bool:
	var out: Array = []
	return _exec("which", [tool_name], out) == 0 and not out.is_empty()

## Inside a Flatpak sandbox (the Godot editor here, and SlideWalker itself if
## it's ever packaged as one) host binaries aren't on PATH, so poppler has to
## be reached through the portal instead.
static func _exec(tool_name: String, args: PackedStringArray, out: Array, read_stderr: bool = false) -> int:
	if FileAccess.file_exists("/.flatpak-info"):
		var host_args := PackedStringArray(["--host", tool_name])
		host_args.append_array(args)
		return OS.execute("flatpak-spawn", host_args, out, read_stderr)
	return OS.execute(tool_name, args, out, read_stderr)

static func _rasterize(real_path: String) -> Array[String]:
	var cache_dir: String = _cache_dir_for(real_path)
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var existing: Array[String] = _sorted_pages(cache_dir)
	if not existing.is_empty():
		return existing
	_drop_stale_caches(cache_dir)

	var prefix: String = cache_dir.path_join("page")
	var out: Array = []
	var code: int = _exec("pdftoppm", ["-r", str(RASTER_DPI), "-png", real_path, prefix], out, true)
	if code != 0:
		push_warning("PdfParser: pdftoppm failed (%d): %s" % [code, "".join(out)])
		return []
	return _sorted_pages(cache_dir)

## Cache key: sanitized basename + source mtime, so an edited-and-resaved
## file under the same name re-rasterizes instead of serving a stale cache.
static func _cache_dir_for(real_path: String) -> String:
	var mtime: int = FileAccess.get_modified_time(real_path)
	var safe_name: String = real_path.get_file().get_basename().validate_filename()
	return OS.get_user_data_dir().path_join("pdf_cache").path_join("%s_%d" % [safe_name, mtime])

## Earlier rasters of the same file, from before it was last edited: a deck
## re-exported a few times would otherwise leave every old set on disk.
static func _drop_stale_caches(current_dir: String) -> void:
	var root: String = current_dir.get_base_dir()
	var prefix: String = current_dir.get_file().substr(0, current_dir.get_file().rfind("_") + 1)
	var dir := DirAccess.open(root)
	if dir == null or prefix == "":
		return
	for name in dir.get_directories():
		if not name.begins_with(prefix) or name == current_dir.get_file():
			continue
		var stale := root.path_join(name)
		var stale_dir := DirAccess.open(stale)
		if stale_dir == null:
			continue
		for f in stale_dir.get_files():
			DirAccess.remove_absolute(stale.path_join(f))
		DirAccess.remove_absolute(stale)

static func _sorted_pages(cache_dir: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("page") and f.get_extension().to_lower() == "png":
			out.append(cache_dir.path_join(f))
	# Files are "page-1.png".."page-N.png" (zero-padded once N >= 10) -
	# sort by the embedded page number, not lexicographically.
	out.sort_custom(func(a: String, b: String) -> bool:
		return _page_number(a) < _page_number(b))
	return out

static func _page_number(file_path: String) -> int:
	var digits: String = ""
	for c in file_path.get_file().get_basename():
		if c.is_valid_int():
			digits += c
	return digits.to_int()

static func _run_capture(tool_name: String, args: PackedStringArray) -> String:
	var out: Array = []
	_exec(tool_name, args, out)
	return "".join(out) if not out.is_empty() else ""

## pdftotext -bbox-layout wraps the useful <doc>...</doc> in an XHTML shell
## with a DOCTYPE Godot's XMLParser won't accept - the <doc> subtree alone is
## well-formed, so that's all that's parsed.
static func _extract_doc_tree(bbox_xml: String) -> Dictionary:
	var start: int = bbox_xml.find("<doc>")
	var end: int = bbox_xml.find("</doc>")
	if start == -1 or end == -1:
		return {}
	return ZipXmlUtils.parse_xml_tree((bbox_xml.substr(start, end - start + "</doc>".length())).to_utf8_buffer())

static func _build_slide(slide_index: int, image_path: String, page_node: Dictionary) -> PresentationModel.SlideManifest:
	var manifest := PresentationModel.SlideManifest.new()
	manifest.slide_id = slide_index

	var img := Image.new()
	var page_attrs: Dictionary = page_node.get("attrs", {})
	var canvas_pt: Vector2
	if page_attrs.has("width") and page_attrs.has("height"):
		canvas_pt = Vector2(float(page_attrs["width"]), float(page_attrs["height"]))
	elif img.load(image_path) == OK:
		# No text layer at all (a scanned/image-only PDF) - fall back to the
		# raster's own pixel size at the DPI it was rendered at.
		canvas_pt = Vector2(img.get_size()) * 72.0 / float(RASTER_DPI)
	else:
		canvas_pt = Vector2(960.0, 540.0)
	manifest.canvas_w = canvas_pt.x * CM_PER_PT
	manifest.canvas_h = canvas_pt.y * CM_PER_PT

	# The page raster is the slide's background, not a shape: full bleed,
	# drawn under everything, and - unlike a shape - it never becomes one
	# page-sized platform that would bury every real ledge beneath it.
	manifest.bg_image_ref = image_path

	var z: int = 1
	for line in ZipXmlUtils.find_all(page_node, "line"):
		var attrs: Dictionary = line.get("attrs", {})
		var x_min: float = float(attrs.get("xMin", "0"))
		var y_min: float = float(attrs.get("yMin", "0"))
		var x_max: float = float(attrs.get("xMax", "0"))
		var y_max: float = float(attrs.get("yMax", "0"))
		if x_max <= x_min or y_max <= y_min:
			continue
		var ledge := PresentationModel.ShapeRect.new()
		ledge.id = "line-%d" % z
		ledge.type = PresentationModel.ShapeRect.Type.TEXT
		var cap_drop: float = (y_max - y_min) * CAP_DROP_FRACTION
		ledge.x = x_min * CM_PER_PT
		ledge.y = (y_min + cap_drop) * CM_PER_PT
		ledge.w = (x_max - x_min) * CM_PER_PT
		ledge.h = (y_max - y_min - cap_drop) * CM_PER_PT
		ledge.z_order = z
		z += 1
		# Intentionally no paragraphs/text_summary: the raster image already
		# shows the real glyphs, this shape exists purely as a ledge.
		manifest.shapes.append(ledge)

	return manifest
