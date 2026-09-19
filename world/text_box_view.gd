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

## In this view's local px.
var line_rects: Array[Rect2] = []

var _shape: PresentationModel.ShapeRect
var _px_per_cm: float = 1.0
var _content: Control
## [{"root": Control, "body": RichTextLabel, "para": Paragraph}]
var _blocks: Array = []

## Call once the view is in the tree and sized to the shape's frame.
func build(shape: PresentationModel.ShapeRect, px_per_cm: float) -> void:
	_shape = shape
	_px_per_cm = px_per_cm
	mouse_filter = MOUSE_FILTER_IGNORE
	_content = Control.new()
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_content)

	var inner_w: float = max(1.0, size.x - (shape.text_insets.x + shape.text_insets.z) * px_per_cm)
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
		body.size = Vector2(max(1.0, inner_w - indent_px), 0.0)
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
			y += para.space_before_pt * PT_TO_CM * _px_per_cm
		(block["root"] as Control).position = Vector2(0.0, y)
		tops.append(y)
		y += (block["body"] as RichTextLabel).get_content_height()
	var total: float = y

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
		var block_origin: Vector2 = _content.position + Vector2(body.position.x, tops[i])
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
				var bullet_x: float = para.first_line_indent_cm * _px_per_cm
				w += x0 - min(x0, bullet_x)
				x0 = min(x0, bullet_x)
			var top: float = body.get_line_offset(line) + cap_drop
			line_rects.append(Rect2(block_origin + Vector2(x0, top), Vector2(w, body.get_line_height(line) - cap_drop)))

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

func _px(size_pt: float) -> int:
	return max(1, int(round(size_pt * PT_TO_CM * _px_per_cm)))
