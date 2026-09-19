extends Control
## Startup screen. Currently just the player-style choice; the deck file
## picker and course-layout selector join this scene in milestone M9 once
## parsing (M1-M3) and course generation (M2) exist to feed them.

@onready var pixel_art_button: Button = %PixelArtButton
@onready var stick_figure_button: Button = %StickFigureButton

func _ready() -> void:
	pixel_art_button.pressed.connect(_on_style_chosen.bind(GameSettings.PlayerStyle.PIXEL_ART))
	stick_figure_button.pressed.connect(_on_style_chosen.bind(GameSettings.PlayerStyle.STICK_FIGURE))

func _on_style_chosen(style: GameSettings.PlayerStyle) -> void:
	GameSettings.player_style = style
	get_tree().change_scene_to_file("res://world/test_level.tscn")
