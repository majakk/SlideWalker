extends Node
## Dev tool: renders the actual in-game stick figure (idle, mid-wave) to a
## 512x512 PNG for use as a menu/app icon, on solid white - post-processed
## (see the ImageMagick pipeline this is called from) into alpha via
## inverse luminance, since the art is flat black ink: no fringing, unlike
## chroma-keying. Reuses player/stick_figure.gd directly so the icon always
## matches the real character. Renders on the root viewport (not a
## SubViewport - that blurred these vector strokes badly at this scale).
## Run windowed (not --headless, which has no real renderer):
##   godot --path . res://tools/make_stick_icon.tscn

const StickFigure = preload("res://player/stick_figure.gd")

const SIZE := 512
const CHROMA_KEY := Color(1.0, 1.0, 1.0)
## Figure is ~48px tall (head top to feet) in its own local space; this
## scale leaves a comfortable margin inside the 512px canvas.
const SCALE := 8.0
const OUT_PATH := "res://assets/icons/_stickman_icon_raw.png"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = CHROMA_KEY
	bg.size = Vector2(SIZE, SIZE)
	add_child(bg)

	var figure := StickFigure.new()
	figure.position = Vector2(SIZE / 2.0, SIZE / 2.0 + 20.0)
	figure.scale = Vector2(SCALE, SCALE)
	add_child(figure)

	# Idle, facing right, waving - a friendly figure for an icon.
	figure.set_motion(Vector2.ZERO, true, 1, false)
	figure.play_wave()

	# Let a few frames run so _process/_draw actually execute before capture.
	for i in range(12):
		await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	img.save_png(OUT_PATH)
	print("wrote ", OUT_PATH, " ", img.get_size())
	get_tree().quit()
