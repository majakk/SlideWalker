extends Control
## Renders one text shape as in the original: insets, vertical anchor, and
## one block per paragraph (exact indents, hanging bullets, line spacing,
## space-before). Per-paragraph blocks are also the unit click-to-reveal
## builds (M3b) show one at a time.
##
## After layout, line_rects holds every rendered (wrapped) line, from its
## cap line down: each line of text - titles included - is a ledge you can
## stand on, rather than the (often much larger) text frame.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const FontCache = preload("res://world/font_cache.gd")

const PT_TO_CM: float = 2.54 / 72.0
## PowerPoint's single line spacing is ~1.2x the font size.
const PPT_LINE_HEIGHT: float = 1.2
## Cap height as a fraction of font size (Arial/Liberation Sans ~0.716).
const CAP_HEIGHT_FRACTION: float = 0.72
## Font sizes are whole pixels, so at presentation scale an 18pt run wanting
## 29.5px renders at 30 - 1.7% wide, which is enough to drop the last word of
## a line that fit in the original. Text is laid out at this multiple and the
## whole block scaled back down, which cuts that error to a few tenths of a
## percent and keeps our line breaks where the deck's author saw them.
const LAYOUT_SUPERSAMPLE: float = 4.0

## How far text may be shrunk to fit its own frame before it's left to clip,
## and how many passes that takes (each pass re-wraps, which changes height).
const MIN_FIT_SCALE: float = 0.55
const FIT_PASSES: int = 3

## In this view's local px.
var line_rects: Array[Rect2] = []

var _shape: PresentationModel.ShapeRect
var _px_per_cm: float = 1.0
var _content: Control
## [{"root": Control, "body": RichTextLabel, "para": Paragraph}]
var _blocks: Array = []
## Shrink-to-fit factor on every font size, as PowerPoint's own autofit does.
var _fit_scale: float = 1.0
var _content_height: float = 0.0

## Call once the view is in the tree and sized to the shape's frame.
func build(shape: PresentationModel.ShapeRect, px_per_cm: float) -> void:
	_shape = shape
	_px_per_cm = px_per_cm
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_blocks()
	layout_text()
	_shrink_to_fit()

## Only for frames whose deck asks for "shrink text on overflow": a uniform
## scale inside the shape's own frame, which moves nothing. Re-wrapping at the
## smaller size changes the height again, hence the passes. Frames that don't
## ask for it are left to overflow exactly as the author had them - titles
## routinely sit in a frame shorter than the title itself.
func _shrink_to_fit() -> void:
	if not _shape.text_autofit:
		return
	var inner_h: float = size.y - (_shape.text_insets.y + _shape.text_insets.w) * _px_per_cm
	if inner_h <= 0.0:
		return
	for _pass in range(FIT_PASSES):
		if _content_height <= inner_h or _fit_scale <= MIN_FIT_SCALE:
			return
		_fit_scale = max(MIN_FIT_SCALE, _fit_scale * inner_h / _content_height)
		remove_child(_content)
		_content.queue_free()
		_blocks.clear()
		_build_blocks()
		layout_text()

## Everything inside _content is laid out in supersampled px; _content's own
## scale brings it back to view px. Only _content.position is in view px.
func _build_blocks() -> void:
	var shape: PresentationModel.ShapeRect = _shape
	var px_per_cm: float = _px_per_cm * LAYOUT_SUPERSAMPLE
	_content = Control.new()
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	_content.scale = Vector2.ONE / LAYOUT_SUPERSAMPLE
	add_child(_content)

	var inner_w: float = max(1.0, (size.x - (shape.text_insets.x + shape.text_insets.z) * _px_per_cm) * LAYOUT_SUPERSAMPLE)
	for para in shape.paragraphs:
		var root := Control.new()
		root.mouse_filter = MOUSE_FILTER_IGNORE
		_content.add_child(root)

		var indent_px: float = para.indent_cm * px_per_cm
		var body := RichTextLabel.new()
		body.mouse_filter = MOUSE_FILTER_IGNORE
		body.fit_content = true
		body.scroll_active = false
		body.clip_contents = false
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if shape.text_wrap else TextServer.AUTOWRAP_OFF
		body.position = Vector2(indent_px, 0.0)
		# Godot counts a wrapped line's trailing space against the width,
		# where the authoring apps let it hang past the margin - without this
		# allowance a line that just fits loses its last word, which cascades
		# into an extra line and text pushed out of the frame.
		var first_run: PresentationModel.TextRun = para.runs[0]
		var space_px: float = FontCache.get_font(first_run.font_family, first_run.bold, first_run.italic) \
			.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, _px(first_run.size_pt)).x
		body.size = Vector2(max(1.0, inner_w - indent_px + space_px), 0.0)
		root.add_child(body)
		_fill(body, para)

		if para.bullet != "":
			var first: PresentationModel.TextRun = para.runs[0]
			var bullet := Label.new()
			bullet.mouse_filter = MOUSE_FILTER_IGNORE
			bullet.text = para.bullet
			bullet.add_theme_font_override("font", FontCache.get_font(first.font_family, false, false))
			bullet.add_theme_font_size_override("font_size", _px(first.size_pt))
			bullet.add_theme_color_override("font_color", first.color)
			bullet.position = Vector2(indent_px + para.first_line_indent_cm * px_per_cm, 0.0)
			root.add_child(bullet)

		_blocks.append({"root": root, "body": body, "para": para})
	layout_text()

func layout_text() -> void:
	var ins: Vector4 = _shape.text_insets * _px_per_cm
	var inner := Rect2(ins.x, ins.y, size.x - ins.x - ins.z, size.y - ins.y - ins.w)

	var y: float = 0.0
	var tops: Array[float] = []
	for i in range(_blocks.size()):
		var block: Dictionary = _blocks[i]
		var para: PresentationModel.Paragraph = block["para"]
		if i > 0:
			y += para.space_before_pt * _fit_scale * PT_TO_CM * _px_per_cm * LAYOUT_SUPERSAMPLE
		(block["root"] as Control).position = Vector2(0.0, y)
		tops.append(y)
		y += (block["body"] as RichTextLabel).get_content_height()
	# y is supersampled; everything outside _content works in view px.
	var total: float = y / LAYOUT_SUPERSAMPLE
	_content_height = total

	var offset: float = 0.0
	match _shape.text_anchor:
		"ctr":
			offset = (inner.size.y - total) * 0.5
		"b":
			offset = inner.size.y - total
	_content.position = inner.position + Vector2(0.0, offset)

	# One ledge per rendered line, on its cap line, spanning the glyphs.
	line_rects.clear()
	for i in range(_blocks.size()):
		var para: PresentationModel.Paragraph = _blocks[i]["para"]
		if not _has_text(para):
			continue
		var body: RichTextLabel = _blocks[i]["body"]
		var first: PresentationModel.TextRun = para.runs[0]
		var px: int = _px(first.size_pt)
		var cap_drop: float = FontCache.get_font(first.font_family, first.bold, first.italic).get_ascent(px) \
			- px * CAP_HEIGHT_FRACTION
		var block_origin: Vector2 = _content.position \
			+ Vector2(body.position.x, tops[i]) / LAYOUT_SUPERSAMPLE
		for line in range(body.get_line_count()):
			var w: float = body.get_line_width(line)
			if w <= 0.0:
				continue
			var x0: float = 0.0
			match para.align:
				"ctr":
					x0 = (body.size.x - w) * 0.5
				"r":
					x0 = body.size.x - w
			if line == 0 and para.bullet != "":
				var bullet_x: float = para.first_line_indent_cm * _px_per_cm * LAYOUT_SUPERSAMPLE
				w += x0 - min(x0, bullet_x)
				x0 = min(x0, bullet_x)
			var top: float = body.get_line_offset(line) + cap_drop
			# Measured supersampled, reported in view px like the rest.
			line_rects.append(Rect2(
				block_origin + Vector2(x0, top) / LAYOUT_SUPERSAMPLE,
				Vector2(w, body.get_line_height(line) - cap_drop) / LAYOUT_SUPERSAMPLE))

func _fill(body: RichTextLabel, para: PresentationModel.Paragraph) -> void:
	var first: PresentationModel.TextRun = para.runs[0]
	var first_px: int = _px(first.size_pt)
	var first_font: Font = FontCache.get_font(first.font_family, first.bold, first.italic)
	var line_height: float = first_px * PPT_LINE_HEIGHT * para.line_spacing
	body.add_theme_constant_override("line_separation", int(round(line_height - first_font.get_height(first_px))))

	var align: int = HORIZONTAL_ALIGNMENT_LEFT
	match para.align:
		"ctr":
			align = HORIZONTAL_ALIGNMENT_CENTER
		"r":
			align = HORIZONTAL_ALIGNMENT_RIGHT
		"just", "dist":
			align = HORIZONTAL_ALIGNMENT_FILL
	body.push_paragraph(align)

	var any_text := false
	for run in para.runs:
		if run.text == "":
			continue
		any_text = true
		body.push_font(FontCache.get_font(run.font_family, run.bold, run.italic), _px(run.size_pt))
		body.push_color(run.color)
		if run.underline:
			body.push_underline()
		body.add_text(run.text)
		if run.underline:
			body.pop()
		body.pop()
		body.pop()
	if not any_text:
		# Empty paragraphs still take one line of vertical space.
		body.push_font(first_font, first_px)
		body.add_text(" ")
		body.pop()
	body.pop()

func _has_text(para: PresentationModel.Paragraph) -> bool:
	for run in para.runs:
		if run.text.strip_edges() != "":
			return true
	return false

## Font size in supersampled px - every glyph lives inside _content.
func _px(size_pt: float) -> int:
	return max(1, int(round(size_pt * _fit_scale * PT_TO_CM * _px_per_cm * LAYOUT_SUPERSAMPLE)))
