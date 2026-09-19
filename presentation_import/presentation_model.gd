extends RefCounted
class_name PresentationModel
## Format-agnostic intermediate representation. pptx_parser.gd and (later)
## odp_parser.gd both produce a SlideDeck of this shape; course_generation/
## and world/ never know which source format was loaded.

class ShapeRect:
	extends RefCounted

	enum Type { TEXT, IMAGE, SHAPE, TABLE }

	var id: String = ""
	var type: Type = Type.SHAPE
	## Position/size in centimeters, in slide-local coordinates (origin at
	## the slide's top-left, y increasing downward).
	var x: float = 0.0
	var y: float = 0.0
	var w: float = 0.0
	var h: float = 0.0
	var z_order: int = 0
	var image_ref: String = ""
	var text_summary: String = ""
	## False when the shape had no explicit position (placeholder-inherited
	## from a layout/master we don't chase in v1) and got a deterministic
	## fallback slot instead. Tracked to measure parser coverage.
	var position_is_explicit: bool = true

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
