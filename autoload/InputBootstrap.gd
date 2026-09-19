extends Node
## Registers input actions in code (keyboard WASD/arrows + Xbox-layout
## gamepad) rather than hand-authoring InputMap resource syntax in
## project.godot, so the action set stays a single readable source.

func _ready() -> void:
	_setup_action("move_left", [
		_key(KEY_A), _key(KEY_LEFT),
		_joy_axis(JOY_AXIS_LEFT_X, -1.0), _joy_button(JOY_BUTTON_DPAD_LEFT),
	])
	_setup_action("move_right", [
		_key(KEY_D), _key(KEY_RIGHT),
		_joy_axis(JOY_AXIS_LEFT_X, 1.0), _joy_button(JOY_BUTTON_DPAD_RIGHT),
	])
	# Drop down through the ledge you're standing on. Higher stick deadzone
	# so a slightly-down stick while running doesn't drop you by accident.
	_setup_action("move_down", [
		_key(KEY_S), _key(KEY_DOWN),
		_joy_axis(JOY_AXIS_LEFT_Y, 1.0), _joy_button(JOY_BUTTON_DPAD_DOWN),
	], 0.6)
	_setup_action("jump", [
		_key(KEY_SPACE), _joy_button(JOY_BUTTON_A),
	])
	# Activates slide media (video, GIF, click-to-reveal builds) near the
	# player. X rather than A, which is already jump.
	_setup_action("interact", [
		_key(KEY_E), _joy_button(JOY_BUTTON_X),
	])
	_setup_action("wave", [
		_key(KEY_Q), _joy_button(JOY_BUTTON_Y),
	])

func _setup_action(action_name: String, events: Array, deadzone: float = 0.2) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)
	else:
		InputMap.action_erase_events(action_name)
		InputMap.action_set_deadzone(action_name, deadzone)
	for event in events:
		InputMap.action_add_event(action_name, event)

func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event

func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event
