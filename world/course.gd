extends Node2D
## The course: the presentation chosen in the menu (or, if none, the dev
## decks in presentations_testing/, Tab to cycle) rendered as a platformer
## in the chosen layout. C toggles per-slide / seamless camera, T the timer,
## F3 shows ledges. Esc pauses and opens the menu over the presentation
## (Resume continues right where you were).

const PresentationParser = preload("res://presentation_import/presentation_parser.gd")
const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const SlideContentRenderer = preload("res://world/slide_content_renderer.gd")
const WorldAssembler = preload("res://world/world_assembler.gd")
const InteractZones = preload("res://world/interact_zones.gd")

const MenuScene = preload("res://ui/main_menu.tscn")

const DECK_DIR := "res://presentations_testing"
const HUD_COLOR := Color(0.72, 0.76, 0.82)
const HUD_FONT_SIZE: int = 20
const HUD_MARGIN: float = 16.0
const TOAST_SECONDS: float = 1.6

static var deck_index: int = 0

@onready var slides_root: Node2D = $SlidesRoot
@onready var platforms_root: Node2D = $PlatformsRoot
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $CameraRig

var _debug_overlay: Node2D
var _menu_layer: CanvasLayer
var _timer_label: Label
var _elapsed: float = 0.0
var _assist_root: Node2D
var _assist_on: bool = false
var _toast: Label
var _toast_left: float = 0.0

func _ready() -> void:
	var args: Dictionary = _user_args()
	if args.has("deck"):
		deck_index = int(args["deck"])
	if args.has("mode"):
		GameSettings.course_layout = int(args["mode"]) as GameSettings.CourseLayout
	if args.has("seamless"):
		GameSettings.camera_mode = GameSettings.CameraMode.SEAMLESS
	if args.has("timer"):
		GameSettings.show_timer = true
	if args.has("pixel"):
		GameSettings.player_style = GameSettings.PlayerStyle.PIXEL_ART
		player._apply_visual_style()

	var deck_path: String = GameSettings.deck_path
	if deck_path == "":
		var decks: Array[String] = _find_dev_decks()
		if decks.is_empty():
			push_warning("No presentation chosen and no presentations in %s" % DECK_DIR)
			return
		deck_path = decks[deck_index % decks.size()]
	var mode: int = GameSettings.course_layout

	var t0: int = Time.get_ticks_msec()
	var deck = PresentationParser.parse(deck_path)
	if deck.slides.is_empty():
		push_warning("Could not read any slides from %s" % deck_path)
		_show_load_failure(deck_path)
		return
	var px_per_cm: float = CourseGenerator.presentation_scale(deck)
	var slide_rects: Array[Rect2] = CourseGenerator.place_slides(CourseGenerator.slide_sizes(deck, px_per_cm), mode)

	var renderer := SlideContentRenderer.new()
	renderer.open(deck_path, px_per_cm)
	var walkables: Array = []
	for i in range(deck.slides.size()):
		walkables.append(renderer.render_slide(slides_root, deck.slides[i], slide_rects[i]))
	renderer.close()

	GameSettings.session_active = true
	GameSettings.session_deck_path = GameSettings.deck_path
	GameSettings.session_layout = GameSettings.course_layout
	_build_hud()

	var layout: CourseModel.Layout = CourseGenerator.generate(slide_rects, walkables, mode)
	JumpPhysics.profile = layout.jump_profile
	_debug_overlay = WorldAssembler.assemble(platforms_root, layout)
	_assist_root = platforms_root.get_node(WorldAssembler.ASSIST_ROOT_NAME)

	var zones := InteractZones.new()
	add_child(zones)
	zones.setup(renderer.link_targets, player)

	player.global_position = layout.entry_position
	if args.has("slide"):
		var r: Rect2 = slide_rects[clamp(int(args["slide"]) - 1, 0, slide_rects.size() - 1)]
		player.global_position = Vector2(r.position.x + 60.0, r.end.y - 30.0)
	camera.setup(layout, player)
	if args.has("debug"):
		_debug_overlay.visible = true
	if args.has("assist"):
		_toggle_assist()
	if args.has("overview"):
		# Dev aid: zoom out to the whole course.
		camera.set_process(false)
		var all: Rect2 = slide_rects[0]
		for r in slide_rects:
			all = all.merge(r)
		all = all.grow(200.0)
		var view: Vector2 = get_viewport_rect().size
		var fit: float = min(view.x / all.size.x, view.y / all.size.y)
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2(fit, fit)
		camera.global_position = all.get_center()

	var helpers: int = layout.platforms.filter(
		func(p: CourseModel.Platform) -> bool: return p.kind == CourseModel.Platform.Kind.HELPER).size()
	print("%s [%s]: %d slides at %.1f px/cm, %d platforms (%d helper rungs), jump apex %.0fpx, built in %d ms" % [
		deck_path.get_file(), CourseGenerator.Mode.keys()[mode], deck.slides.size(), px_per_cm,
		layout.platforms.size(), helpers, layout.jump_profile.apex_height, Time.get_ticks_msec() - t0])

	if args.has("pausemenu"):
		_open_menu()
	if args.has("screenshot"):
		_save_screenshot_and_quit(String(args["screenshot"]))

func _process(delta: float) -> void:
	# Pauses with the tree while the menu overlay is open.
	_elapsed += delta
	if _timer_label and _timer_label.visible:
		var total: int = int(_elapsed)
		var h: int = floori(total / 3600.0)
		var m: int = floori(total / 60.0) % 60
		var sec: int = total % 60
		_timer_label.text = "%d:%02d:%02d" % [h, m, sec] if h > 0 else "%02d:%02d" % [m, sec]
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0

## Assist rungs are invisible by design, so pressing H has to say what it did.
func _toggle_assist() -> void:
	if _assist_root == null:
		return
	_assist_on = not _assist_on
	for body in _assist_root.get_children():
		(body as StaticBody2D).collision_layer = WorldAssembler.ONE_WAY_LAYER_BITS if _assist_on else 0
	_toast.text = "Assist platforms on" if _assist_on else "Assist platforms off"
	_toast.visible = true
	_toast_left = TOAST_SECONDS

## Screen-space timer in the bottom-right corner, styled like the slide
## numbers in the stage strip.
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	_timer_label.add_theme_color_override("font_color", HUD_COLOR)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_timer_label.offset_left = -200.0
	_timer_label.offset_top = -HUD_FONT_SIZE * 2.0
	_timer_label.offset_right = -HUD_MARGIN
	_timer_label.offset_bottom = -HUD_MARGIN * 0.5
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label.visible = GameSettings.show_timer
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	_toast.add_theme_color_override("font_color", HUD_COLOR)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = HUD_MARGIN
	_toast.offset_bottom = HUD_MARGIN + HUD_FONT_SIZE * 1.6
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	hud.add_child(_toast)
	hud.add_child(_timer_label)

## Nothing to walk on, so say why rather than leaving an empty world up.
func _show_load_failure(deck_path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var reason: String = PresentationParser.unmet_requirement(deck_path)
	if reason == "":
		reason = "Could not read any slides from this file."
	var label := Label.new()
	label.text = "%s\n\n%s\n\nPress Esc for the menu." % [deck_path.get_file(), reason]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HUD_COLOR)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 120.0
	label.offset_right = -120.0
	layer.add_child(label)

func _open_menu() -> void:
	get_tree().paused = true
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var menu = MenuScene.instantiate()
	menu.in_session = true
	menu.resume_requested.connect(_resume)
	_menu_layer.add_child(menu)
	add_child(_menu_layer)

func _resume() -> void:
	_menu_layer.queue_free()
	_menu_layer = null
	get_tree().paused = false
	# Settings that can change live while paused.
	player._apply_visual_style()
	_timer_label.visible = GameSettings.show_timer

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("assist"):
		get_viewport().set_input_as_handled()
		_toggle_assist()
		return
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
			KEY_T:
				GameSettings.show_timer = not GameSettings.show_timer
				_timer_label.visible = GameSettings.show_timer
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_open_menu()

## Dev aid: `godot --path . res://world/course.tscn -- --deck=N --mode=N
## --slide=N [--debug] [--assist] [--seamless] --screenshot=/abs/path.png`.
func _save_screenshot_and_quit(path: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		if PresentationParser.is_supported(f):
			out.append(DECK_DIR.path_join(f))
	out.sort()
	return out
