extends RefCounted
## Format-agnostic intermediate representation. pptx_parser.gd and (later)
## odp_parser.gd both produce a SlideDeck of this shape; course_generation/
## and world/ never know which source format was loaded. Everything here is
## fully resolved (inherited styles, theme colors, placeholder positions),
## so the renderer never needs to know about layouts or masters.

class TextRun:
	extends RefCounted
	var text: String = ""
	var size_pt: float = 18.0
	var bold: bool = false
	var italic: bool = false
	var underline: bool = false
	var color: Color = Color.BLACK
	var font_family: String = ""

class Paragraph:
	extends RefCounted
	## "l", "ctr", "r", "just"
	var align: String = "l"
	var level: int = 0
	## Bullet glyph to prefix, or "" for none.
	var bullet: String = ""
	## Left margin of the paragraph text (marL).
	var indent_cm: float = 0.0
	## First-line offset relative to indent_cm (usually negative: a hanging
	## indent where the bullet sits left of the text).
	var first_line_indent_cm: float = 0.0
	var space_before_pt: float = 0.0
	## Multiplier, 1.0 = single spacing.
	var line_spacing: float = 1.0
	var runs: Array[TextRun] = []

class ShapeRect:
	extends RefCounted

	enum Type { TEXT, IMAGE, SHAPE, TABLE, LINE }

	var id: String = ""
	var type: Type = Type.SHAPE
	## Position/size in centimeters, in slide-local coordinates (origin at
	## the slide's top-left, y increasing downward).
	var x: float = 0.0
	var y: float = 0.0
	var w: float = 0.0
	var h: float = 0.0
	var rotation_deg: float = 0.0
	var flip_h: bool = false
	var flip_v: bool = false
	var z_order: int = 0
	## False when no explicit or inherited position could be found and the
	## shape got a deterministic fallback slot. Tracked to measure coverage.
	var position_is_explicit: bool = true
	## Placeholder type ("title", "body", ...) or "" for regular shapes.
	var placeholder_type: String = ""

	## Preset geometry name from <a:prstGeom> ("rect", "roundRect", "ellipse", ...).
	var geometry: String = "rect"
	var fill_color: Color = Color(0, 0, 0, 0)
	var line_color: Color = Color(0, 0, 0, 0)
	var line_width_cm: float = 0.0

	var image_ref: String = ""
	## Visible fraction of the source image: Rect2(left, top, width, height),
	## each 0..1, from <a:srcRect>.
	var image_crop: Rect2 = Rect2(0, 0, 1, 1)

	var paragraphs: Array[Paragraph] = []
	## "t", "ctr", "b"
	var text_anchor: String = "t"
	## left, top, right, bottom insets in cm.
	var text_insets: Vector4 = Vector4(0.254, 0.127, 0.254, 0.127)
	var text_wrap: bool = true
	var text_summary: String = ""

	func has_visible_text() -> bool:
		return text_summary.strip_edges() != ""

	func is_visible() -> bool:
		return has_visible_text() or image_ref != "" or fill_color.a > 0.0 \
			or (line_color.a > 0.0 and line_width_cm > 0.0) or type == Type.TABLE

class SlideManifest:
	extends RefCounted

	var slide_id: int = 0
	var canvas_w: float = 0.0
	var canvas_h: float = 0.0
	var shapes: Array[ShapeRect] = []
	var bg_color: Color = Color.WHITE
	var bg_image_ref: String = ""

class SlideDeck:
	extends RefCounted

	var slides: Array[SlideManifest] = []
	var source_path: String = ""
