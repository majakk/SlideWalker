extends Node2D
## Slide elements that link somewhere - a video still, a source URL - become
## things the presenter can walk up to. Standing at one shows a prompt over
## it; E (or the controller's X) opens it.
##
## Nothing is drawn unless the player is actually at a link, so the slide
## itself is untouched the rest of the time.

const VideoLink = preload("res://world/video_link.gd")
const FontCache = preload("res://world/font_cache.gd")

## How far from a link's own box still counts as standing at it.
const REACH_PX: float = 70.0
const PANEL_COLOR := Color(0.09, 0.1, 0.13, 0.9)
const OUTLINE_COLOR := Color(0.36, 0.76, 1.0, 0.85)
const TEXT_COLOR := Color(0.94, 0.96, 0.98)
const FONT_SIZE: int = 17
const PANEL_PAD := Vector2(14.0, 8.0)
const PANEL_GAP: float = 12.0
## The player's origin is at its feet, so the prompt clears its head.
const PLAYER_HEIGHT_PX: float = 74.0
const MARGIN_PX: float = 10.0

## [{"rect": Rect2 (world px), "url": String}]
var targets: Array = []

var _player: Node2D
var _active: int = -1

func setup(link_targets: Array, player: Node2D) -> void:
	targets = link_targets
	_player = player
	z_index = 8
	set_process(not targets.is_empty())

func _process(_delta: float) -> void:
	var found: int = _nearest()
	# The prompt follows the player, so it redraws while one is up.
	if found != _active or _active >= 0:
		_active = found
		queue_redraw()

## The link the player is standing at, preferring the closest one when a
## couple overlap (a caption under its own picture, say).
func _nearest() -> int:
	if _player == null:
		return -1
	var pos: Vector2 = _player.global_position
	var best: int = -1
	var best_distance: float = INF
	for i in range(targets.size()):
		var rect: Rect2 = targets[i]["rect"]
		var reachable: Rect2 = rect.grow(REACH_PX)
		if not reachable.has_point(pos):
			continue
		var distance: float = pos.distance_to(rect.get_center())
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

func _draw() -> void:
	if _active < 0:
		return
	var rect: Rect2 = targets[_active]["rect"]
	draw_rect(rect, OUTLINE_COLOR, false, 2.0)

	var font: Font = FontCache.get_font("", false, false)
	var text: String = VideoLink.prompt_for(targets[_active]["url"])
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	# Over the player rather than over the link: the prompt then never covers
	# the very thing it's pointing at, or the slide text around it.
	var anchor: Vector2 = _player.global_position
	var panel := Rect2(
		Vector2(anchor.x - text_size.x * 0.5 - PANEL_PAD.x,
			anchor.y - text_size.y - PANEL_PAD.y * 2.0 - PANEL_GAP - PLAYER_HEIGHT_PX),
		text_size + PANEL_PAD * 2.0)
	panel.position = _kept_on_screen(panel)
	draw_rect(panel, PANEL_COLOR)
	draw_string(font, panel.position + PANEL_PAD + Vector2(0.0, font.get_ascent(FONT_SIZE)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

## Standing at a link near the edge of the course would otherwise push half
## the prompt off-screen.
func _kept_on_screen(panel: Rect2) -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return panel.position
	var view: Vector2 = get_viewport_rect().size / camera.zoom
	var visible := Rect2(camera.get_screen_center_position() - view * 0.5, view).grow(-MARGIN_PX)
	return Vector2(
		clamp(panel.position.x, visible.position.x, max(visible.position.x, visible.end.x - panel.size.x)),
		clamp(panel.position.y, visible.position.y, max(visible.position.y, visible.end.y - panel.size.y)))

func _unhandled_input(event: InputEvent) -> void:
	if _active < 0 or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	OS.shell_open(targets[_active]["url"])
