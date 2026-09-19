extends RefCounted
## Draws slides the way they look in the original deck: background, then
## every shape in z-order (fills/outlines, images with crop/flip, styled
## text, connector lines), clipped to the slide like a slideshow. Returns
## each slide's walkable rectangles (slide-local px) for course generation.

const PresentationModel = preload("res://presentation_import/presentation_model.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")
const ShapeView = preload("res://world/shape_view.gd")
const TextBoxView = preload("res://world/text_box_view.gd")

const UNSUPPORTED_FILL := Color(0.85, 0.86, 0.88)

var px_per_cm: float = 1.0
var _zip := ZIPReader.new()
var _textures: Dictionary = {}

func open(deck_path: String, scale_px_per_cm: float) -> bool:
	px_per_cm = scale_px_per_cm
	return _zip.open(deck_path) == OK

func close() -> void:
	_zip.close()

func render_slide(parent: Node, manifest: PresentationModel.SlideManifest, rect: Rect2) -> Array[Rect2]:
	var card := Panel.new()
	card.name = "Slide%d" % manifest.slide_id
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = rect.position
	card.size = rect.size
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = manifest.bg_color
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 6)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	if manifest.bg_image_ref != "":
		var bg_tex: Texture2D = _texture(manifest.bg_image_ref)
		if bg_tex:
			card.add_child(_texture_rect(bg_tex, Rect2(Vector2.ZERO, rect.size)))

	var walkables: Array[Rect2] = []
	for shape in manifest.shapes:
		var box := Rect2(Vector2(shape.x, shape.y) * px_per_cm, Vector2(shape.w, shape.h) * px_per_cm)
		var shape_walkables: Array[Rect2] = [box]

		if shape.type == PresentationModel.ShapeRect.Type.IMAGE:
			_add_rotated(card, _image_view(shape, box), shape, box)
		else:
			var has_frame: bool = shape.fill_color.a > 0.0 or shape.line_color.a > 0.0 \
				or shape.type in [PresentationModel.ShapeRect.Type.LINE, PresentationModel.ShapeRect.Type.TABLE]
			if has_frame:
				var view := ShapeView.new()
				view.fill_color = shape.fill_color
				view.line_color = shape.line_color
				view.line_width = shape.line_width_cm * px_per_cm
				view.geometry = shape.geometry
				view.is_line = shape.type == PresentationModel.ShapeRect.Type.LINE
				view.flip_h = shape.flip_h
				view.flip_v = shape.flip_v
				_add_rotated(card, view, shape, box)
			if shape.has_visible_text():
				var text := TextBoxView.new()
				_add_rotated(card, text, shape, box)
				text.build(shape, px_per_cm)
				# Unframed text: every rendered line is a ledge; the invisible
				# frame itself is not.
				if not has_frame:
					shape_walkables.clear()
					for line in text.line_rects:
						shape_walkables.append(Rect2(box.position + line.position, line.size))

		if CourseGenerator.is_platform_shape(shape):
			walkables.append_array(shape_walkables)
	return walkables

func _add_rotated(card: Control, view: Control, shape: PresentationModel.ShapeRect, box: Rect2) -> void:
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = box.position
	view.size = box.size
	view.pivot_offset = box.size * 0.5
	view.rotation = deg_to_rad(shape.rotation_deg)
	card.add_child(view)

func _image_view(shape: PresentationModel.ShapeRect, box: Rect2) -> Control:
	var tex: Texture2D = _texture(shape.image_ref)
	if tex == null:
		# GIF (decoder lands in M3b) or a format Godot can't load (EMF/WMF).
		var placeholder := ColorRect.new()
		placeholder.color = UNSUPPORTED_FILL
		var label := Label.new()
		label.text = shape.image_ref.get_extension().to_upper()
		label.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		placeholder.add_child(label)
		return placeholder
	var crop: Rect2 = shape.image_crop
	if crop != Rect2(0, 0, 1, 1):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		var tex_size: Vector2 = tex.get_size()
		atlas.region = Rect2(crop.position * tex_size, crop.size * tex_size)
		tex = atlas
	var view := _texture_rect(tex, box)
	view.flip_h = shape.flip_h
	view.flip_v = shape.flip_v
	return view

func _texture_rect(tex: Texture2D, box: Rect2) -> TextureRect:
	var view := TextureRect.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture = tex
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	view.position = box.position
	view.size = box.size
	return view

func _texture(ref: String) -> Texture2D:
	if _textures.has(ref):
		return _textures[ref]
	var tex: Texture2D = null
	if _zip.file_exists(ref):
		var bytes: PackedByteArray = _zip.read_file(ref)
		var img := Image.new()
		var err: int = FAILED
		match ref.get_extension().to_lower():
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
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_textures[ref] = tex
	return tex
