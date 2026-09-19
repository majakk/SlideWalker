extends Control
## Startup screen. Currently just the player-style choice; the deck file
## picker and course-layout selector join this scene in milestone M9 once
## parsing (M1-M3) and course generation (M2) exist to feed them.

@onready var pixel_art_button: Button = %PixelArtButton
@onready var stick_figure_button: Button = %StickFigureButton

@onready var seamless_toggle: CheckButton = %SeamlessToggle

func _ready() -> void:
	pixel_art_button.pressed.connect(_on_style_chosen.bind(GameSettings.PlayerStyle.PIXEL_ART))
	stick_figure_button.pressed.connect(_on_style_chosen.bind(GameSettings.PlayerStyle.STICK_FIGURE))
	seamless_toggle.button_pressed = GameSettings.camera_mode == GameSettings.CameraMode.SEAMLESS
	seamless_toggle.toggled.connect(func(on: bool) -> void:
		GameSettings.camera_mode = GameSettings.CameraMode.SEAMLESS if on else GameSettings.CameraMode.PER_SLIDE)

func _on_style_chosen(style: GameSettings.PlayerStyle) -> void:
	GameSettings.player_style = style
	get_tree().change_scene_to_file("res://world/course_playtest.tscn")
