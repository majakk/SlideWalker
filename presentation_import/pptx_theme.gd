extends RefCounted
## One slide master's theme: named scheme colors, the master's color map
## (bg1/tx1/... -> lt1/dk1/...), and major/minor fonts. Resolves any DrawingML
## color element (<a:srgbClr>, <a:schemeClr>, ...) including the lumMod/
## lumOff/tint/shade/alpha modifiers that theme-based decks use everywhere.

const ZipXmlUtils = preload("res://presentation_import/zip_xml_utils.gd")

const COLOR_TAGS := ["a:srgbClr", "a:schemeClr", "a:sysClr", "a:prstClr", "a:scrgbClr", "a:hslClr"]

var colors: Dictionary = {}
var clr_map: Dictionary = {
	"bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2",
	"accent1": "accent1", "accent2": "accent2", "accent3": "accent3",
	"accent4": "accent4", "accent5": "accent5", "accent6": "accent6",
	"hlink": "hlink", "folHlink": "folHlink",
}
var major_font: String = "Arial"
var minor_font: String = "Arial"

func load_from(theme_tree: Dictionary, master_tree: Dictionary) -> void:
	var scheme: Dictionary = ZipXmlUtils.find_first(theme_tree, "a:clrScheme")
	for entry in scheme.get("children", []):
		var name: String = String(entry.get("tag", "")).trim_prefix("a:")
		var c = _base_color(entry)
		if c != null:
			colors[name] = c
	major_font = _latin_typeface(ZipXmlUtils.find_first(theme_tree, "a:majorFont"), major_font)
	minor_font = _latin_typeface(ZipXmlUtils.find_first(theme_tree, "a:minorFont"), minor_font)
	var map_node: Dictionary = ZipXmlUtils.find_first(master_tree, "p:clrMap")
	for key in map_node.get("attrs", {}):
		clr_map[key] = map_node["attrs"][key]

static func _latin_typeface(font_node: Dictionary, fallback: String) -> String:
	for child in ZipXmlUtils.direct_children(font_node, "a:latin"):
		var face: String = child.get("attrs", {}).get("typeface", "")
		if face != "":
			return face
	return fallback

## Maps "+mj-lt"/"+mn-lt" theme font references to real family names.
func resolve_font(typeface: String) -> String:
	if typeface.begins_with("+mj"):
		return major_font
	if typeface.begins_with("+mn"):
		return minor_font
	return typeface

## Resolves the color inside a fill-like container (<a:solidFill>, <a:defRPr>'s
## fill, <p:bgRef>, ...). Returns null when there is no color element.
func color_in(container: Dictionary) -> Variant:
	if container.is_empty():
		return null
	for child in container.get("children", []):
		if COLOR_TAGS.has(child.get("tag", "")):
			return resolve(child)
	return null

func resolve(color_node: Dictionary) -> Variant:
	var base = _base_color(color_node)
	if base == null:
		return null
	return _apply_modifiers(base, color_node)

func _base_color(node: Dictionary) -> Variant:
	var attrs: Dictionary = node.get("attrs", {})
	match String(node.get("tag", "")):
		"a:srgbClr":
			return Color.html("#" + String(attrs.get("val", "000000")))
		"a:sysClr":
			return Color.html("#" + String(attrs.get("lastClr", "000000")))
		"a:schemeClr":
			var name: String = attrs.get("val", "tx1")
			name = clr_map.get(name, name)
			return colors.get(name, Color.BLACK)
		"a:prstClr":
			var named := Color.from_string(String(attrs.get("val", "black")), Color.BLACK)
			return named
		"a:scrgbClr":
			return Color(float(attrs.get("r", "0")) / 100000.0,
				float(attrs.get("g", "0")) / 100000.0,
				float(attrs.get("b", "0")) / 100000.0)
		_:
			# Theme <a:dk1> etc. wrap the actual color element.
			for child in node.get("children", []):
				if COLOR_TAGS.has(child.get("tag", "")):
					return _base_color(child)
	return null

func _apply_modifiers(color: Color, node: Dictionary) -> Color:
	var c := color
	for mod in node.get("children", []):
		var val: float = float(mod.get("attrs", {}).get("val", "100000")) / 100000.0
		match String(mod.get("tag", "")):
			"a:lumMod":
				var hsl := _to_hsl(c)
				c = _from_hsl(hsl.x, hsl.y, clamp(hsl.z * val, 0.0, 1.0), c.a)
			"a:lumOff":
				var hsl := _to_hsl(c)
				c = _from_hsl(hsl.x, hsl.y, clamp(hsl.z + val, 0.0, 1.0), c.a)
			"a:tint":
				c = Color(lerp(1.0, c.r, val), lerp(1.0, c.g, val), lerp(1.0, c.b, val), c.a)
			"a:shade":
				c = Color(c.r * val, c.g * val, c.b * val, c.a)
			"a:alpha":
				c.a = val
	return c

static func _to_hsl(c: Color) -> Vector3:
	var mx: float = max(c.r, max(c.g, c.b))
	var mn: float = min(c.r, min(c.g, c.b))
	var l: float = (mx + mn) * 0.5
	if mx == mn:
		return Vector3(0.0, 0.0, l)
	var d: float = mx - mn
	var s: float = d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
	var h: float
	if mx == c.r:
		h = (c.g - c.b) / d + (6.0 if c.g < c.b else 0.0)
	elif mx == c.g:
		h = (c.b - c.r) / d + 2.0
	else:
		h = (c.r - c.g) / d + 4.0
	return Vector3(h / 6.0, s, l)

static func _from_hsl(h: float, s: float, l: float, a: float) -> Color:
	if s == 0.0:
		return Color(l, l, l, a)
	var q: float = l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p: float = 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0), a)

static func _hue(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p
