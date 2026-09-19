extends RefCounted
## SystemFont per (family, bold, italic). Families are the deck's own
## typefaces; fontconfig substitutes metric-compatible fonts where needed
## (Arial -> Liberation Sans, Calibri -> Carlito), so line wrapping matches
## the original. MSDF keeps text sharp under any camera zoom.

## Godot matches system font family names exactly (no fontconfig aliasing),
## so Office fonts are mapped to their metric-compatible open substitutes
## explicitly - same glyph widths means the same line wrapping as the original.
const METRIC_SUBSTITUTES := {
	"arial": ["Liberation Sans", "Arimo"],
	"helvetica": ["Liberation Sans", "Arimo"],
	"helvetica neue": ["Liberation Sans", "Arimo"],
	"calibri": ["Carlito"],
	"calibri light": ["Carlito"],
	"cambria": ["Caladea"],
	"times new roman": ["Liberation Serif", "Tinos"],
	"times": ["Liberation Serif", "Tinos"],
	"courier new": ["Liberation Mono", "Cousine"],
	"arial narrow": ["Liberation Sans Narrow"],
}

static var _fonts: Dictionary = {}

static func get_font(family: String, bold: bool, italic: bool) -> Font:
	var key := "%s|%s|%s" % [family, bold, italic]
	if _fonts.has(key):
		return _fonts[key]
	var names := PackedStringArray()
	if family != "":
		names.append(family)
		for sub in METRIC_SUBSTITUTES.get(family.to_lower(), []):
			names.append(sub)
	names.append("Liberation Sans")
	names.append("sans-serif")
	var font := SystemFont.new()
	font.font_names = names
	font.font_weight = 700 if bold else 400
	font.font_italic = italic
	font.multichannel_signed_distance_field = true
	font.generate_mipmaps = true
	_fonts[key] = font
	return font
