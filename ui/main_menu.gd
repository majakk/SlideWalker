extends Control
## Startup screen: pick a presentation, course type, player style and camera
## mode, then start. Built in code to keep the scene file trivial.

const COURSE_SCENE := "res://world/course.tscn"
const DEV_DECK_DIR := "res://presentations_testing"

const BACKDROP := Color(0.88, 0.9, 0.93)
const INK := Color(0.12, 0.13, 0.15)
const MUTED := Color(0.45, 0.48, 0.53)
const ACCENT := Color(0.18, 0.44, 0.85)

var _file_label: Label
var _start_button: Button
var _dialog: FileDialog

func _ready() -> void:
	theme = _light_theme()
	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color.WHITE
	card_style.set_corner_radius_all(14)
	card_style.shadow_color = Color(0, 0, 0, 0.16)
	card_style.shadow_size = 24
	card_style.shadow_offset = Vector2(0, 8)
	card_style.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(520, 0)
	card.add_child(col)

	col.add_child(_label("PlatformPresenter", 36, INK))
	col.add_child(_label("Present your slides by walking through them.", 16, MUTED))
	col.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)

	grid.add_child(_label("Presentation", 16, MUTED))
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 10)
	var choose := Button.new()
	choose.text = "Choose file…"
	choose.pressed.connect(_open_file_dialog)
	file_row.add_child(choose)
	_file_label = _label("", 14, INK)
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.clip_text = true
	_file_label.custom_minimum_size = Vector2(260, 0)
	file_row.add_child(_file_label)
	grid.add_child(file_row)

	grid.add_child(_label("Course", 16, MUTED))
	var course := OptionButton.new()
	course.add_item("Side-scroller  →", GameSettings.CourseLayout.SIDE_SCROLL)
	course.add_item("Climb up  ↑", GameSettings.CourseLayout.CLIMB)
	course.add_item("Drop down  ↓", GameSettings.CourseLayout.DROP)
	course.select(course.get_item_index(GameSettings.course_layout))
	course.item_selected.connect(func(i: int) -> void:
		GameSettings.course_layout = course.get_item_id(i))
	grid.add_child(course)

	grid.add_child(_label("Player", 16, MUTED))
	var style := OptionButton.new()
	style.add_item("Stick figure", GameSettings.PlayerStyle.STICK_FIGURE)
	style.add_item("Pixel art", GameSettings.PlayerStyle.PIXEL_ART)
	style.select(style.get_item_index(GameSettings.player_style))
	style.item_selected.connect(func(i: int) -> void:
		GameSettings.player_style = style.get_item_id(i))
	grid.add_child(style)

	grid.add_child(_label("Camera", 16, MUTED))
	var seamless := CheckButton.new()
	seamless.text = "Seamless scrolling (instead of slide by slide)"
	seamless.button_pressed = GameSettings.camera_mode == GameSettings.CameraMode.SEAMLESS
	seamless.toggled.connect(func(on: bool) -> void:
		GameSettings.camera_mode = GameSettings.CameraMode.SEAMLESS if on else GameSettings.CameraMode.PER_SLIDE)
	grid.add_child(seamless)

	_start_button = Button.new()
	_start_button.text = "Start presenting"
	_start_button.custom_minimum_size = Vector2(0, 52)
	_start_button.add_theme_font_size_override("font_size", 20)
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = ACCENT
	start_style.set_corner_radius_all(10)
	_start_button.add_theme_stylebox_override("normal", start_style)
	var start_hover := start_style.duplicate()
	start_hover.bg_color = ACCENT.lightened(0.12)
	_start_button.add_theme_stylebox_override("hover", start_hover)
	_start_button.add_theme_stylebox_override("pressed", start_style)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_start_button.add_theme_color_override(c, Color.WHITE)
	var start_focus := start_style.duplicate()
	start_focus.border_color = ACCENT.darkened(0.3)
	start_focus.set_border_width_all(2)
	_start_button.add_theme_stylebox_override("focus", start_focus)
	_start_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(COURSE_SCENE))
	col.add_child(_start_button)

	var controls := _label("A/D or stick: move · Space/A: jump (again in the air: double jump) · S/down: drop · " +
		"Q/Y: wave · C: camera · Esc: menu", 13, MUTED)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(controls)

	_refresh_file_label()
	_start_button.grab_focus()

	# Dev aid: `-- --screenshot=/abs/path.png` saves the menu and quits.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			for _i in range(10):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
			get_tree().quit()

func _open_file_dialog() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.pptx ; PowerPoint presentations"])
		_dialog.use_native_dialog = true
		_dialog.title = "Choose a presentation"
		_dialog.current_dir = GameSettings.deck_path.get_base_dir() if GameSettings.deck_path != "" \
			else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		_dialog.file_selected.connect(func(path: String) -> void:
			GameSettings.deck_path = path
			_refresh_file_label())
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)

func _refresh_file_label() -> void:
	if GameSettings.deck_path != "":
		_file_label.text = GameSettings.deck_path.get_file()
		_file_label.add_theme_color_override("font_color", INK)
		_start_button.disabled = false
	elif _has_dev_decks():
		_file_label.text = "Test decks (Tab cycles)"
		_file_label.add_theme_color_override("font_color", MUTED)
		_start_button.disabled = false
	else:
		_file_label.text = "No file chosen"
		_file_label.add_theme_color_override("font_color", MUTED)
		_start_button.disabled = true

func _has_dev_decks() -> bool:
	var dir := DirAccess.open(DEV_DECK_DIR)
	if dir == null:
		return false
	for f in dir.get_files():
		if f.to_lower().ends_with(".pptx"):
			return true
	return false

## Light controls matching the white card (Godot's default theme is dark).
func _light_theme() -> Theme:
	var t := Theme.new()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.96, 0.97, 0.98)
	normal.border_color = Color(0.8, 0.82, 0.86)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.92, 0.94, 0.96)
	var focus := normal.duplicate()
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, hover)
		t.set_stylebox("focus", type, focus)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, type, INK)
	var flat := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(s, "CheckButton", flat)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "CheckButton", INK)
	return t

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
