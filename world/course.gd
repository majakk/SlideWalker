extends Node2D
## The course: the presentation chosen in the menu (or, if none, the dev
## decks in presentations_testing/, Tab to cycle) rendered as a platformer
## in the chosen layout. C toggles per-slide / seamless camera, F3 shows
## ledges, Esc returns to the menu.

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const SlideContentRenderer = preload("res://world/slide_content_renderer.gd")
const WorldAssembler = preload("res://world/world_assembler.gd")

const DECK_DIR := "res://presentations_testing"
const MENU_SCENE := "res://ui/main_menu.tscn"

static var deck_index: int = 0

@onready var slides_root: Node2D = $SlidesRoot
@onready var platforms_root: Node2D = $PlatformsRoot
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $CameraRig

var _debug_overlay: Node2D

func _ready() -> void:
	var args: Dictionary = _user_args()
	if args.has("deck"):
		deck_index = int(args["deck"])
	if args.has("mode"):
		GameSettings.course_layout = int(args["mode"])
	if args.has("seamless"):
		GameSettings.camera_mode = GameSettings.CameraMode.SEAMLESS

	var deck_path: String = GameSettings.deck_path
	if deck_path == "":
		var decks: Array[String] = _find_dev_decks()
		if decks.is_empty():
			push_warning("No presentation chosen and no .pptx files in %s" % DECK_DIR)
			return
		deck_path = decks[deck_index % decks.size()]
	var mode: int = GameSettings.course_layout

	var t0: int = Time.get_ticks_msec()
	var deck = PptxParser.parse(deck_path)
	if deck.slides.is_empty():
		push_warning("Could not read any slides from %s" % deck_path)
		return
	var px_per_cm: float = CourseGenerator.presentation_scale(deck)
	var slide_rects: Array[Rect2] = CourseGenerator.place_slides(CourseGenerator.slide_sizes(deck, px_per_cm), mode)

	var renderer := SlideContentRenderer.new()
	renderer.open(deck_path, px_per_cm)
	var walkables: Array = []
	for i in range(deck.slides.size()):
		walkables.append(renderer.render_slide(slides_root, deck.slides[i], slide_rects[i]))
	renderer.close()

	var layout: CourseModel.Layout = CourseGenerator.generate(slide_rects, walkables, mode)
	JumpPhysics.profile = layout.jump_profile
	_debug_overlay = WorldAssembler.assemble(platforms_root, layout)

	player.global_position = layout.entry_position
	if args.has("slide"):
		var r: Rect2 = slide_rects[clamp(int(args["slide"]) - 1, 0, slide_rects.size() - 1)]
		player.global_position = Vector2(r.position.x + 60.0, r.end.y - 30.0)
	camera.setup(layout, player)
	if args.has("debug"):
		_debug_overlay.visible = true

	var helpers: int = layout.platforms.filter(
		func(p: CourseModel.Platform) -> bool: return p.kind == CourseModel.Platform.Kind.HELPER).size()
	print("%s [%s]: %d slides at %.1f px/cm, %d platforms (%d helper rungs), jump apex %.0fpx, built in %d ms" % [
		deck_path.get_file(), CourseGenerator.Mode.keys()[mode], deck.slides.size(), px_per_cm,
		layout.platforms.size(), helpers, layout.jump_profile.apex_height, Time.get_ticks_msec() - t0])

	if args.has("screenshot"):
		_save_screenshot_and_quit(String(args["screenshot"]))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				if _debug_overlay:
					_debug_overlay.visible = not _debug_overlay.visible
			KEY_TAB:
				if GameSettings.deck_path == "":
					deck_index += 1
					get_tree().reload_current_scene()
			KEY_C:
				GameSettings.camera_mode = GameSettings.CameraMode.SEAMLESS \
					if GameSettings.camera_mode == GameSettings.CameraMode.PER_SLIDE \
					else GameSettings.CameraMode.PER_SLIDE
			KEY_ESCAPE:
				get_tree().change_scene_to_file(MENU_SCENE)

## Dev aid: `godot --path . res://world/course.tscn -- --deck=N --mode=N
## --slide=N [--debug] [--seamless] --screenshot=/abs/path.png`.
func _save_screenshot_and_quit(path: String) -> void:
	for _i in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot: player at %s on_floor=%s velocity=%s" % [
		player.global_position, player.is_on_floor(), player.velocity])
	get_tree().quit()

func _user_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out

func _find_dev_decks() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DECK_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.to_lower().ends_with(".pptx"):
			out.append(DECK_DIR.path_join(f))
	out.sort()
	return out
