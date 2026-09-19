extends Control
## Draws a shape's fill/outline for its preset geometry (rect, roundRect,
## ellipse; other presets fall back to their bounding rectangle), or a
## straight connector line.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")

var fill_color: Color = Color(0, 0, 0, 0)
var line_color: Color = Color(0, 0, 0, 0)
var line_width: float = 0.0
var geometry: String = "rect"
var is_line: bool = false
var flip_h: bool = false
var flip_v: bool = false

func _draw() -> void:
	if is_line:
		var a := Vector2(size.x if flip_h else 0.0, size.y if flip_v else 0.0)
		var b := Vector2(0.0 if flip_h else size.x, 0.0 if flip_v else size.y)
		draw_line(a, b, line_color, max(1.0, line_width), true)
		return

	var outline: PackedVector2Array = _outline_points()
	if fill_color.a > 0.0:
		draw_colored_polygon(outline, fill_color)
	if line_color.a > 0.0 and line_width > 0.0:
		var closed := outline.duplicate()
		closed.append(outline[0])
		draw_polyline(closed, line_color, line_width, true)

func _outline_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	match geometry:
		"ellipse":
			var c: Vector2 = size * 0.5
			for i in range(64):
				var a: float = TAU * i / 64.0
				pts.append(c + Vector2(cos(a) * c.x, sin(a) * c.y))
		"roundRect":
			# Default roundRect adjustment: corner radius = 16.667% of the short side.
			var r: float = min(size.x, size.y) * 0.16667
			var corners := [Vector2(size.x - r, r), Vector2(size.x - r, size.y - r),
				Vector2(r, size.y - r), Vector2(r, r)]
			for ci in range(4):
				for s in range(9):
					var a: float = -PI / 2.0 + (ci + s / 8.0) * PI / 2.0
					pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
		_:
			pts = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	return pts
